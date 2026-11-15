package projectops

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// ExecuteThreeWayMerge applies Staging.db -> Target.db changes inside a single atomic
// BEGIN IMMEDIATE transaction on Target.db, honoring per-plot and per-field conflict
// resolutions ('keep_target' | 'accept_source'), allocating monotonic child IDs via
// __VPRO_ChildIdentity without reusing deleted IDs, and recording full <Target>_Audit entries.
func ExecuteThreeWayMerge(s *vprocore.ContextService, ctx context.Context, contextID string, req ThreeWayMergeExecuteRequest) (ThreeWayMergeResult, error) {
	defaultRes := strings.TrimSpace(req.DefaultConflictResolution)
	if defaultRes == "" {
		defaultRes = MergeResolutionKeepTarget
	}
	if err := validateMergeResolutionChoice(defaultRes); err != nil {
		return ThreeWayMergeResult{}, err
	}
	for k, v := range req.PlotResolutions {
		if k == "" {
			return ThreeWayMergeResult{}, errors.New("plot resolution key must not be empty")
		}
		if err := validateMergeResolutionChoice(v); err != nil {
			return ThreeWayMergeResult{}, err
		}
	}
	for k, v := range req.FieldResolutions {
		if k == "" {
			return ThreeWayMergeResult{}, errors.New("field resolution key must not be empty")
		}
		if err := validateMergeResolutionChoice(v); err != nil {
			return ThreeWayMergeResult{}, err
		}
	}

	srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor, err := resolveMergeEndpoints(
		ctx, s, contextID,
		req.SourcePath, req.SourceProject,
		req.TargetPath, req.TargetProject,
		req.BasePath, req.BaseProject,
	)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}

	resolveDecision := func(item MergeConflictItem) string {
		if choice, ok := req.FieldResolutions[item.ConflictID]; ok {
			return choice
		}
		if choice, ok := req.PlotResolutions[item.PlotNumber]; ok {
			return choice
		}
		if item.Kind == "FastForward" || item.Kind == "TargetModifiedOnly" || item.Kind == "SourceDelete" {
			return item.DefaultResolution
		}
		return defaultRes
	}

	runMergeOnConn := func(conn *sql.Conn) (ThreeWayMergeResult, error) {
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return ThreeWayMergeResult{}, err
		}
		var txErr error
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				txErr = errors.Join(txErr, rb)
			}
		}()

		preview, srcSnap, tgtSnap, _, pErr := buildThreeWayMergePreviewInternal(ctx, srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, tx, req.CaseInsensitiveText)
		if pErr != nil {
			return ThreeWayMergeResult{}, pErr
		}
		if exp := strings.TrimSpace(req.ExpectedPreviewDigest); exp != "" && exp != preview.PreviewDigest {
			return ThreeWayMergeResult{}, errors.New("source or target database changed since preview; re-run PreviewThreeWayMerge before executing")
		}

		if err := ensureChildIdentityTable(ctx, tx); err != nil {
			return ThreeWayMergeResult{}, err
		}

		auditTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_Audit")
		auditStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+auditTbl+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`)
		if err != nil {
			return ThreeWayMergeResult{}, err
		}
		defer auditStmt.Close()

		now := time.Now().Format("2006-01-02 15:04:05")
		var allocatedIDs, reservedDeletedIDs []int64
		addedPlots, updatedPlots, skippedPlots, deletedPlots, auditRows := 0, 0, 0, 0, 0

		deleteWholePlotFromTarget := func(plot string) error {
			// Reserve child IDs before deleting rows in FK order (children -> Admin -> Env).
			for _, suffix := range []string{"Other", "Mineral", "Humus", "Veg"} {
				tgtChildRows := tgtSnap.rawCells[suffix][plot]
				var keys []string
				for k := range tgtChildRows {
					keys = append(keys, k)
				}
				slices.Sort(keys)
				for _, rk := range keys {
					if idCell := tgtChildRows[rk]["ID"]; idCell.storage == "integer" && idCell.intVal > 0 {
						if err := reserveChildID(ctx, tx, tgtProj+"_"+suffix, idCell.intVal); err != nil {
							return err
						}
						reservedDeletedIDs = append(reservedDeletedIDs, idCell.intVal)
					}
				}
				qTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_" + suffix)
				if _, err := tx.ExecContext(ctx, `DELETE FROM `+qTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`, plot); err != nil {
					return err
				}
			}
			adminTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_Admin")
			if _, err := tx.ExecContext(ctx, `DELETE FROM `+adminTbl+` WHERE typeof("Plot")='text' AND CAST("Plot" AS BLOB)=CAST(? AS BLOB)`, plot); err != nil {
				return err
			}
			envTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_Env")
			dRes, dErr := tx.ExecContext(ctx, `DELETE FROM `+envTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`, plot)
			if dErr != nil {
				return dErr
			}
			if n, _ := dRes.RowsAffected(); n != 1 {
				return fmt.Errorf("merge plot delete on %s matched %d Env rows", plot, n)
			}
			// Record deletion provenance with PlotNumber=NULL so ON DELETE CASCADE on _Env neither
			// cascades out the deletion audit trail nor triggers FK error after _Env removal.
			if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, nil, "_Env", "PlotNumber", now, plot, nil, nil); err != nil {
				return err
			}
			auditRows++
			return nil
		}

		insertPlotChildRow := func(suffix, plot string, srcRaw map[string]rawSQLiteCell) error {
			cols := tgtSnap.columns[suffix]
			newID, aErr := allocateSafeChildID(ctx, tx, tgtProj, suffix)
			if aErr != nil {
				return aErr
			}
			allocatedIDs = append(allocatedIDs, newID)

			quotedCols := make([]string, len(cols))
			marks := make([]string, len(cols))
			args := make([]any, len(cols))
			for i, col := range cols {
				quotedCols[i] = vprocore.QuoteHeaderIdentifier(col)
				marks[i] = "?"
				switch col {
				case "PlotNumber":
					args[i] = plot
				case "ID":
					args[i] = newID
				default:
					cell := srcRaw[col]
					if err := validateMergedCell(suffix, col, cell); err != nil {
						return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, col, err)
					}
					args[i] = normalizeMergedParam(suffix, col, cell)
				}
			}
			insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
				vprocore.QuoteHeaderIdentifier(tgtProj+"_"+suffix),
				strings.Join(quotedCols, ", "),
				strings.Join(marks, ", "),
			)
			if _, err := tx.ExecContext(ctx, insSQL, args...); err != nil {
				return err
			}
			for _, col := range cols {
				if col == "PlotNumber" || col == "ID" {
					continue
				}
				c := srcRaw[col]
				if c.storage == "null" || (col == "Flag" && c.storage == "integer" && c.intVal == 0) {
					continue
				}
				if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, col, now, nil, auditTextForRawCell(c), newID); err != nil {
					return err
				}
				auditRows++
			}
			return nil
		}

		insertWholePlotFromSource := func(plot string) error {
			if err := validateUTF16Max("PlotNumber", plot, 7); err != nil {
				return err
			}
			for _, suffix := range []string{"Env", "Admin"} {
				srcRaw, ok := srcSnap.rawCells[suffix][plot][suffix]
				if !ok {
					return fmt.Errorf("source plot %s is missing required %s row", plot, suffix)
				}
				cols := tgtSnap.columns[suffix]
				quotedCols := make([]string, len(cols))
				marks := make([]string, len(cols))
				args := make([]any, len(cols))
				keyCol := "PlotNumber"
				if suffix == "Admin" {
					keyCol = "Plot"
				}
				for i, col := range cols {
					quotedCols[i] = vprocore.QuoteHeaderIdentifier(col)
					marks[i] = "?"
					if col == keyCol {
						args[i] = plot
					} else {
						cell := srcRaw[col]
						if err := validateMergedCell(suffix, col, cell); err != nil {
							return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, col, err)
						}
						args[i] = normalizeMergedParam(suffix, col, cell)
					}
				}
				insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
					vprocore.QuoteHeaderIdentifier(tgtProj+"_"+suffix),
					strings.Join(quotedCols, ", "),
					strings.Join(marks, ", "),
				)
				if _, err := tx.ExecContext(ctx, insSQL, args...); err != nil {
					return err
				}
				for _, col := range cols {
					c := srcRaw[col]
					if col == keyCol {
						if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, col, now, nil, plot, nil); err != nil {
							return err
						}
						auditRows++
						continue
					}
					if c.storage == "null" {
						continue
					}
					if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, col, now, nil, auditTextForRawCell(c), nil); err != nil {
						return err
					}
					auditRows++
				}
			}
			for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other"} {
				srcChildRows := srcSnap.rawCells[suffix][plot]
				var keys []string
				for k := range srcChildRows {
					keys = append(keys, k)
				}
				slices.Sort(keys)
				for _, rk := range keys {
					if err := insertPlotChildRow(suffix, plot, srcChildRows[rk]); err != nil {
						return err
					}
				}
			}
			return nil
		}

		for _, plotPlan := range preview.Plots {
			if err := ctx.Err(); err != nil {
				return ThreeWayMergeResult{}, err
			}
			plot := plotPlan.PlotNumber
			switch plotPlan.Category {
			case "Identical", "TargetOnly":
				skippedPlots++
			case "Added":
				if choice, ok := req.PlotResolutions[plot]; ok && choice == MergeResolutionKeepTarget {
					skippedPlots++
					continue
				}
				if err := insertWholePlotFromSource(plot); err != nil {
					return ThreeWayMergeResult{}, err
				}
				addedPlots++
			case "SourceDelete":
				if len(plotPlan.Items) == 1 && resolveDecision(plotPlan.Items[0]) == MergeResolutionAcceptSource {
					if err := deleteWholePlotFromTarget(plot); err != nil {
						return ThreeWayMergeResult{}, err
					}
					deletedPlots++
				} else {
					skippedPlots++
				}
			case "FastForward", "Conflict":
				// Handle special cases where plot membership differs vs Base:
				// (a) Base had plot, Target deleted it, Source kept it -> re-insert if accept_source
				// (b) Base had plot, Source deleted it, Target modified it -> delete if accept_source
				if len(plotPlan.Items) == 1 && plotPlan.Items[0].Key == "Plot" {
					if !tgtSnap.plots[plot] && srcSnap.plots[plot] {
						if resolveDecision(plotPlan.Items[0]) == MergeResolutionAcceptSource {
							if err := insertWholePlotFromSource(plot); err != nil {
								return ThreeWayMergeResult{}, err
							}
							addedPlots++
						} else {
							skippedPlots++
						}
						continue
					}
					if tgtSnap.plots[plot] && !srcSnap.plots[plot] {
						if resolveDecision(plotPlan.Items[0]) == MergeResolutionAcceptSource {
							if err := deleteWholePlotFromTarget(plot); err != nil {
								return ThreeWayMergeResult{}, err
							}
							deletedPlots++
						} else {
							skippedPlots++
						}
						continue
					}
				}

				plotModified := false
				for _, item := range plotPlan.Items {
					if resolveDecision(item) != MergeResolutionAcceptSource {
						continue
					}
					suffix := item.Table
					quotedTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_" + suffix)

					if suffix == "Env" || suffix == "Admin" {
						keyCol := "PlotNumber"
						if suffix == "Admin" {
							keyCol = "Plot"
						}
						srcCell := srcSnap.rawCells[suffix][plot][suffix][item.Field]
						if err := validateMergedCell(suffix, item.Field, srcCell); err != nil {
							return ThreeWayMergeResult{}, fmt.Errorf("plot %s %s.%s: %w", plot, suffix, item.Field, err)
						}
						param := normalizeMergedParam(suffix, item.Field, srcCell)
						uRes, uErr := tx.ExecContext(ctx, `UPDATE `+quotedTbl+` SET `+vprocore.QuoteHeaderIdentifier(item.Field)+
							` = ? WHERE typeof(`+vprocore.QuoteHeaderIdentifier(keyCol)+`)='text' AND CAST(`+vprocore.QuoteHeaderIdentifier(keyCol)+` AS BLOB)=CAST(? AS BLOB)`,
							param, plot)
						if uErr != nil {
							return ThreeWayMergeResult{}, uErr
						}
						if n, _ := uRes.RowsAffected(); n != 1 {
							return ThreeWayMergeResult{}, fmt.Errorf("merge update on %s.%s for plot %s matched %d rows", suffix, item.Field, plot, n)
						}
						var beforeVal, afterVal any
						if item.TargetVal != nil {
							beforeVal = *item.TargetVal
						}
						if item.SourceVal != nil {
							afterVal = *item.SourceVal
						}
						if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, item.Field, now, beforeVal, afterVal, nil); err != nil {
							return ThreeWayMergeResult{}, err
						}
						auditRows++
						plotModified = true
						continue
					}

					// Child table item (Veg, Humus, Mineral, Other).
					if item.Field == "*" {
						if item.SourceVal != nil && item.TargetVal == nil {
							// Row added in Source -> allocate monotonic child ID & insert.
							sKey := item.srcRowKey
							if sKey == "" {
								sKey = item.Key
							}
							srcRow := srcSnap.rawCells[suffix][plot][sKey]
							if err := insertPlotChildRow(suffix, plot, srcRow); err != nil {
								return ThreeWayMergeResult{}, err
							}
							plotModified = true
						} else if item.SourceVal == nil && item.TargetVal != nil {
							// Row deleted in Source -> delete from Target and permanently reserve ID!
							tKey := item.tgtRowKey
							if tKey == "" {
								tKey = item.Key
							}
							tgtRow := tgtSnap.rawCells[suffix][plot][tKey]
							idCell := tgtRow["ID"]
							if idCell.storage != "integer" {
								return ThreeWayMergeResult{}, fmt.Errorf("cannot delete target %s row in plot %s without integer ID", suffix, plot)
							}
							targetID := idCell.intVal
							if targetID > 0 {
								if err := reserveChildID(ctx, tx, tgtProj+"_"+suffix, targetID); err != nil {
									return ThreeWayMergeResult{}, err
								}
								reservedDeletedIDs = append(reservedDeletedIDs, targetID)
							}
							dRes, dErr := tx.ExecContext(ctx, `DELETE FROM `+quotedTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`, plot, targetID)
							if dErr != nil {
								return ThreeWayMergeResult{}, dErr
							}
							if n, _ := dRes.RowsAffected(); n != 1 {
								return ThreeWayMergeResult{}, fmt.Errorf("merge child delete on %s (plot %s, ID %d) matched %d rows", suffix, plot, targetID, n)
							}
							for _, col := range tgtSnap.columns[suffix] {
								if col == "PlotNumber" || col == "ID" {
									continue
								}
								oldCell := tgtRow[col]
								if oldCell.storage == "null" || (col == "Flag" && oldCell.storage == "integer" && oldCell.intVal == 0) {
									continue
								}
								if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, col, now, auditTextForRawCell(oldCell), nil, targetID); err != nil {
									return ThreeWayMergeResult{}, err
								}
								auditRows++
							}
							plotModified = true
						}
						continue
					}

					// Field-level update on a matched child row.
					idx := strings.LastIndex(item.Key, ".")
					if idx <= 0 {
						return ThreeWayMergeResult{}, fmt.Errorf("malformed child diff key %q", item.Key)
					}
					rowKey := item.Key[:idx]
					sKey := item.srcRowKey
					if sKey == "" {
						sKey = rowKey
					}
					tKey := item.tgtRowKey
					if tKey == "" {
						tKey = rowKey
					}
					srcCell := srcSnap.rawCells[suffix][plot][sKey][item.Field]
					tgtRow := tgtSnap.rawCells[suffix][plot][tKey]
					idCell := tgtRow["ID"]
					if idCell.storage != "integer" {
						return ThreeWayMergeResult{}, fmt.Errorf("target %s row in plot %s lacks integer ID for field merge", suffix, plot)
					}
					if err := validateMergedCell(suffix, item.Field, srcCell); err != nil {
						return ThreeWayMergeResult{}, fmt.Errorf("plot %s %s.%s: %w", plot, suffix, item.Field, err)
					}
					param := normalizeMergedParam(suffix, item.Field, srcCell)
					uRes, uErr := tx.ExecContext(ctx, `UPDATE `+quotedTbl+` SET `+vprocore.QuoteHeaderIdentifier(item.Field)+
						` = ? WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`,
						param, plot, idCell.intVal)
					if uErr != nil {
						return ThreeWayMergeResult{}, uErr
					}
					if n, _ := uRes.RowsAffected(); n != 1 {
						return ThreeWayMergeResult{}, fmt.Errorf("merge child update on %s.%s (plot %s, ID %d) matched %d rows", suffix, item.Field, plot, idCell.intVal, n)
					}
					var beforeVal, afterVal any
					if item.TargetVal != nil {
						beforeVal = *item.TargetVal
					}
					if item.SourceVal != nil {
						afterVal = *item.SourceVal
					}
					if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, plot, "_"+suffix, item.Field, now, beforeVal, afterVal, idCell.intVal); err != nil {
						return ThreeWayMergeResult{}, err
					}
					auditRows++
					plotModified = true
				}
				if plotModified {
					updatedPlots++
				} else {
					skippedPlots++
				}
			}
		}

		if err := applyThreeWayMergeMetadata(
			ctx, tx, auditStmt, tgtProj, actor, now, srcSnap, tgtSnap,
			preview.MetadataItems, resolveDecision, &allocatedIDs, &reservedDeletedIDs, &auditRows,
		); err != nil {
			return ThreeWayMergeResult{}, err
		}

		if err := ctx.Err(); err != nil {
			return ThreeWayMergeResult{}, err
		}
		if err := tx.Commit(); err != nil {
			return ThreeWayMergeResult{}, err
		}
		slices.Sort(allocatedIDs)
		slices.Sort(reservedDeletedIDs)
		reservedDeletedIDs = slices.Compact(reservedDeletedIDs)
		return ThreeWayMergeResult{
			SourceProject:      srcProj,
			TargetProject:      tgtProj,
			TargetPath:         tgtPath,
			AddedPlots:         addedPlots,
			UpdatedPlots:       updatedPlots,
			SkippedPlots:       skippedPlots,
			DeletedPlots:       deletedPlots,
			AllocatedChildIDs:  allocatedIDs,
			ReservedDeletedIDs: reservedDeletedIDs,
			AuditRowsWritten:   auditRows,
		}, txErr
	}

	// If merging into the active context's project database, acquire the ContextService writer lease!
	if s != nil && contextID != "" {
		snap, sErr := inspectContextSnapshot(ctx, s, contextID)
		if sErr == nil && vprocore.SameDesktopPath(tgtPath, snap.ProjectPath) {
			var res ThreeWayMergeResult
			editErr := s.Edit(contextID, func(plots *vprocore.PlotService) error {
				return plots.Projects.Sqlite.WithMetadataWriter(ctx, func(conn *sql.Conn) error {
					var mErr error
					res, mErr = runMergeOnConn(conn)
					return mErr
				})
			})
			return res, editErr
		}
	}

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tgtPath, "rw")+"&_foreign_keys=on&_busy_timeout=5000&_txlock=immediate&_journal_mode=WAL")
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	conn, err := db.Conn(ctx)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	defer conn.Close()
	return runMergeOnConn(conn)
}
