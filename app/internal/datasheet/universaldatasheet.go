package datasheet

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"
)

func readSinglePhysicalRowByRowID(ctx context.Context, tx *sql.Tx, tableName string, columns []DatasheetColumnMeta, rowID int64) ([]vprocore.ProjectMetadataCell, error) {
	selectFields := make([]string, 0, len(columns)*2)
	for _, col := range columns {
		qCol := vprocore.QuoteHeaderIdentifier(col.Name)
		selectFields = append(selectFields,
			"typeof("+qCol+")",
			"CASE typeof("+qCol+") WHEN 'integer' THEN CAST("+qCol+" AS INTEGER) WHEN 'real' THEN CAST("+qCol+" AS REAL) ELSE CAST("+qCol+" AS BLOB) END",
		)
	}
	query := "SELECT " + strings.Join(selectFields, ",") + " FROM main." + vprocore.QuoteHeaderIdentifier(tableName) + " WHERE rowid = ?"
	storages := make([]string, len(columns))
	values := make([]any, len(columns))
	dest := make([]any, 0, len(columns)*2)
	for i := range columns {
		dest = append(dest, &storages[i], &values[i])
	}
	if err := tx.QueryRowContext(ctx, query, rowID).Scan(dest...); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("row %d no longer exists in %s; reload before saving", rowID, tableName)
		}
		return nil, err
	}
	cells := make([]vprocore.ProjectMetadataCell, len(columns))
	for i, val := range values {
		cell, err := vprocore.ProjectMetadataCellInternal(storages[i], val)
		if err != nil {
			return nil, fmt.Errorf("row %d column %s: %w", rowID, columns[i].Name, err)
		}
		cells[i] = cell
	}
	return cells, nil
}

// ApplyDatasheetEdits validates and commits a batch of cell edits inside a single
// atomic SQLite BEGIN IMMEDIATE transaction, omitting unchanged historical columns
// and writing one <Project>_Audit row per mutated project cell.
func ApplyDatasheetEdits(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetEditRequest) (*DatasheetEditResult, error) {
	if ctx == nil {
		return nil, errors.New("datasheet edit requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	if len(request.Edits) == 0 {
		return nil, errors.New("datasheet edit requires at least one cell edit")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*DatasheetEditResult, error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		plots.Mu.RLock()
		currentUser := plots.CurrentUser
		plots.Mu.RUnlock()
		if strings.TrimSpace(currentUser) == "" {
			currentUser = "VPro"
		}

		target, err := findDatasheetTarget(owner, request.TableKey)
		if err != nil {
			return nil, err
		}
		if !target.available {
			return nil, errors.New(target.unavailableReason)
		}
		if target.readOnly {
			return nil, fmt.Errorf("table %s (%s) is read-only in datasheet mode", target.key, target.tableName)
		}

		// Group edits by rowID in deterministic submission order, rejecting duplicate (rowId, column).
		type orderedRowEdits struct {
			rowID int64
			edits []DatasheetCellEdit
		}
		rowOrder := []int64{}
		byRow := map[int64]*orderedRowEdits{}
		seenCell := map[string]bool{}
		for _, edit := range request.Edits {
			rid, parseErr := strconv.ParseInt(strings.TrimSpace(edit.RowID), 10, 64)
			if parseErr != nil {
				return nil, fmt.Errorf("invalid datasheet rowId %q", edit.RowID)
			}
			colKey := fmt.Sprintf("%d:%s", rid, strings.ToLower(strings.TrimSpace(edit.Column)))
			if seenCell[colKey] {
				return nil, fmt.Errorf("duplicate datasheet edit for row %d column %q in one batch", rid, edit.Column)
			}
			seenCell[colKey] = true
			bucket := byRow[rid]
			if bucket == nil {
				bucket = &orderedRowEdits{rowID: rid}
				byRow[rid] = bucket
				rowOrder = append(rowOrder, rid)
			}
			bucket.edits = append(bucket.edits, edit)
		}

		validateFiles := func() error {
			if err := owner.ValidateMetadataWriterFiles(); err != nil {
				return err
			}
			roleInfo := owner.AttachmentInfo[target.role]
			if roleInfo == nil {
				return fmt.Errorf("datasheet role %s is not attached", target.role)
			}
			for supportRole, info := range owner.AttachmentInfo {
				if strings.HasPrefix(supportRole, "V") && os.SameFile(roleInfo, info) {
					return fmt.Errorf("datasheet target %s shares a file with support database %s; writes are prohibited", target.tableName, supportRole)
				}
			}
			return nil
		}

		result := &DatasheetEditResult{
			ContextID: contextID,
			TableKey:  target.key,
			TableName: target.tableName,
		}
		sameAsProject := owner.AttachmentInfo[target.role] != nil &&
			owner.AttachmentInfo["project"] != nil &&
			os.SameFile(owner.AttachmentInfo[target.role], owner.AttachmentInfo["project"])

		err = owner.WithSelectedFileWriter(ctx, target.role, validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, err := conn.BeginTx(ctx, nil) // _txlock=immediate -> BEGIN IMMEDIATE
			if err != nil {
				return err
			}
			defer func() {
				if rbErr := tx.Rollback(); rbErr != nil && !errors.Is(rbErr, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rbErr)
				}
			}()

			var physicalExists bool
			if err := tx.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM main.sqlite_master WHERE type='table' AND name COLLATE BINARY=?)", target.tableName).Scan(&physicalExists); err != nil {
				return err
			}
			if !physicalExists {
				return fmt.Errorf("datasheet target %s must be a physical table, not a view", target.tableName)
			}

			rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, "main", target.tableName)
			if err != nil {
				return err
			}
			columns := make([]DatasheetColumnMeta, len(rawCols))
			colIndexByLower := make(map[string]int, len(rawCols))
			for i, col := range rawCols {
				columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
				colIndexByLower[strings.ToLower(col.Name)] = i
			}

			project := owner.Selection.Project
			auditTable := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			now := time.Now().Format("2006-01-02 15:04:05")

			// For Hierarchy edits, load full hierarchy map if Parent or Name changes so we enforce cycle & uniqueness invariants.
			var hierarchyParentCheck bool
			if target.key == "Hierarchy" {
				for _, ed := range request.Edits {
					if strings.EqualFold(ed.Column, "Parent") {
						hierarchyParentCheck = true
					}
				}
			}

			for _, rid := range rowOrder {
				if err := ctx.Err(); err != nil {
					return err
				}
				bucket := byRow[rid]
				currentCells, err := readSinglePhysicalRowByRowID(ctx, tx, target.tableName, columns, rid)
				if err != nil {
					return err
				}

				type preparedCellMutation struct {
					colIndex   int
					colMeta    DatasheetColumnMeta
					beforeCell vprocore.ProjectMetadataCell
					afterCell  vprocore.ProjectMetadataCell
					driverVal  any
					beforeText *string
					afterText  *string
				}
				var mutations []preparedCellMutation

				for _, edit := range bucket.edits {
					idx, ok := colIndexByLower[strings.ToLower(strings.TrimSpace(edit.Column))]
					if !ok {
						return fmt.Errorf("unknown column %q on %s", edit.Column, target.tableName)
					}
					colMeta := columns[idx]
					storedCell := currentCells[idx]

					// Optimistic concurrency check against expected Before cell
					if !datasheetCellsSemanticallyEqual(storedCell, edit.Before, colMeta) {
						return fmt.Errorf("concurrency conflict on %s row %d column %s: stored value changed; reload before saving",
							target.tableName, rid, colMeta.Name)
					}

					driverVal, afterAudit, normalizedCell, err := validateAndNormalizeDatasheetCell(target.key, colMeta, edit.After, canEditMaster)
					if err != nil {
						return err
					}

					// Omit unchanged cells so untouched / no-op cells never trigger spurious updates or audit rows!
					if datasheetCellsSemanticallyEqual(storedCell, normalizedCell, colMeta) {
						continue
					}

					mutations = append(mutations, preparedCellMutation{
						colIndex:   idx,
						colMeta:    colMeta,
						beforeCell: storedCell,
						afterCell:  normalizedCell,
						driverVal:  driverVal,
						beforeText: auditTextForStoredCell(storedCell, colMeta.IsBoolean),
						afterText:  afterAudit,
					})
				}

				if len(mutations) == 0 {
					continue
				}

				// Determine plot identity & child ID before/after mutation for plot-lock check and <Project>_Audit logging.
				var plotBefore, plotAfter string
				var childID *int64
				plotColName := ""
				switch target.key {
				case "Env", "Veg", "Humus", "Mineral", "Other", "SU":
					plotColName = "PlotNumber"
				case "Admin":
					plotColName = "Plot"
				}
				if plotColName != "" {
					if pIdx, ok := colIndexByLower[strings.ToLower(plotColName)]; ok && currentCells[pIdx].Text != nil {
						plotBefore = *currentCells[pIdx].Text
						plotAfter = plotBefore
					}
				}
				if idIdx, ok := colIndexByLower["id"]; ok && (target.key == "Veg" || target.key == "Humus" || target.key == "Mineral" || target.key == "Other") {
					if currentCells[idIdx].Integer != nil {
						if parsedID, pErr := strconv.ParseInt(*currentCells[idIdx].Integer, 10, 64); pErr == nil {
							childID = &parsedID
						}
					}
				}

				// Apply candidate post-edit row projection for cross-column soil depth sign check and plot rename tracking.
				projectedCells := slices.Clone(currentCells)
				togglingEnvFlag := false
				for _, m := range mutations {
					projectedCells[m.colIndex] = m.afterCell
					if strings.EqualFold(m.colMeta.Name, plotColName) && m.afterCell.Text != nil {
						plotAfter = *m.afterCell.Text
					}
					if target.key == "Env" && m.colMeta.Name == "Flag" {
						togglingEnvFlag = true
					}
				}

				// Check locked plot guard on project plot tables unless the user is explicitly toggling _Env.Flag.
				if sameAsProject && plotBefore != "" && !togglingEnvFlag &&
					(target.key == "Env" || target.key == "Admin" || target.key == "Veg" || target.key == "Humus" || target.key == "Mineral" || target.key == "Other") {
					var lockedCount int
					if err := tx.QueryRowContext(ctx,
						`SELECT COUNT(*) FROM main.`+vprocore.QuoteHeaderIdentifier(project+"_Env")+
							` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
						plotBefore,
					).Scan(&lockedCount); err != nil {
						return err
					}
					if lockedCount > 0 {
						return fmt.Errorf("plot %q is locked (Flag = -1); unlock the plot before editing its cells", plotBefore)
					}
				}

				// Soil horizon LMH25 depth sign check ONLY when Horizon, UpperDepth, or LowerDepth is part of this row's mutations!
				if target.key == "Humus" || target.key == "Mineral" {
					soilDepthTouched := false
					for _, m := range mutations {
						if m.colMeta.Name == "Horizon" || m.colMeta.Name == "UpperDepth" || m.colMeta.Name == "LowerDepth" {
							soilDepthTouched = true
							break
						}
					}
					if soilDepthTouched {
						hIdx, hasH := colIndexByLower["horizon"]
						uIdx, hasU := colIndexByLower["upperdepth"]
						lIdx, hasL := colIndexByLower["lowerdepth"]
						if hasH && hasU && hasL && projectedCells[hIdx].Text != nil {
							if err := validateSoilHorizonDepthSign(
								target.key,
								*projectedCells[hIdx].Text,
								cellFloat64Ptr(projectedCells[uIdx]),
								cellFloat64Ptr(projectedCells[lIdx]),
							); err != nil {
								return err
							}
						}
					}
				}

				// Execute UPDATE touching ONLY mutated columns (preserving untouched historical out-of-rule columns).
				assignments := make([]string, len(mutations))
				updateArgs := make([]any, 0, len(mutations)+1)
				for i, m := range mutations {
					assignments[i] = vprocore.QuoteHeaderIdentifier(m.colMeta.Name) + " = ?"
					updateArgs = append(updateArgs, m.driverVal)
				}
				updateArgs = append(updateArgs, rid)
				updateSQL := "UPDATE main." + vprocore.QuoteHeaderIdentifier(target.tableName) +
					" SET " + strings.Join(assignments, ", ") + " WHERE rowid = ?"
				execRes, err := tx.ExecContext(ctx, updateSQL, updateArgs...)
				if err != nil {
					return fmt.Errorf("update %s row %d: %w", target.tableName, rid, err)
				}
				if affected, aErr := execRes.RowsAffected(); aErr != nil || affected != 1 {
					return errors.Join(aErr, fmt.Errorf("update %s row %d affected %d rows (expected 1)", target.tableName, rid, affected))
				}

				result.UpdatedRows++
				result.UpdatedCells += len(mutations)

				// Write one <Project>_Audit row per mutated project cell inside the same BEGIN IMMEDIATE transaction!
				if sameAsProject && plotAfter != "" {
					canAudit := target.key == "Env" || target.key == "Admin" ||
						target.key == "Veg" || target.key == "Humus" || target.key == "Mineral" || target.key == "Other"
					if target.key == "SU" {
						var envMatch int
						if err := tx.QueryRowContext(ctx,
							`SELECT COUNT(*) FROM main.`+vprocore.QuoteHeaderIdentifier(project+"_Env")+
								` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
							plotAfter,
						).Scan(&envMatch); err != nil {
							return err
						}
						canAudit = envMatch == 1
					}
					if canAudit {
						tableSuffix := "_" + target.key
						for _, m := range mutations {
							if childID != nil {
								if _, err := tx.ExecContext(ctx,
									`INSERT INTO main.`+auditTable+
										` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
									project, currentUser, plotAfter, tableSuffix, m.colMeta.Name, now, m.beforeText, m.afterText, *childID,
								); err != nil {
									return fmt.Errorf("write child audit for %s.%s: %w", target.tableName, m.colMeta.Name, err)
								}
							} else {
								if _, err := tx.ExecContext(ctx,
									`INSERT INTO main.`+auditTable+
										` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag") VALUES (?,?,?,?,?,?,?,?,0,0)`,
									project, currentUser, plotAfter, tableSuffix, m.colMeta.Name, now, m.beforeText, m.afterText,
								); err != nil {
									return fmt.Errorf("write parent audit for %s.%s: %w", target.tableName, m.colMeta.Name, err)
								}
							}
							result.AuditRows++
						}
					}
				}
			}

			if hierarchyParentCheck {
				if err := verifyHierarchyAcyclicInTx(ctx, tx, target.tableName); err != nil {
					return err
				}
			}

			if result.UpdatedCells > 0 {
				proposalBytes, err := json.Marshal(struct {
					ContextID string               `json:"contextId"`
					User      string               `json:"user"`
					Request   DatasheetEditRequest `json:"request"`
				}{contextID, currentUser, request})
				if err != nil {
					return err
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, tx, datasheetHistoryTable, datasheetHistorySQL, string(proposalBytes), "datasheet edit"); err != nil {
					return err
				}
			}

			if err := validateFiles(); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			return tx.Commit()
		})
		if err != nil {
			return nil, err
		}
		return result, nil
	})
}

func plotColNameForDatasheetKey(tableKey string) string {
	switch tableKey {
	case "Env", "Veg", "Humus", "Mineral", "Other", "SU":
		return "PlotNumber"
	case "Admin":
		return "Plot"
	default:
		return ""
	}
}

func loadHierarchyParentsMap(ctx context.Context, tx *sql.Tx, schema, tableName string) (map[int64]*int64, error) {
	rel := vprocore.QuoteHeaderIdentifier(schema) + "." + vprocore.QuoteHeaderIdentifier(tableName)
	rows, err := tx.QueryContext(ctx, "SELECT ID, Parent FROM "+rel)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	parents := map[int64]*int64{}
	for rows.Next() {
		var id int64
		var parent sql.NullInt64
		if err := rows.Scan(&id, &parent); err != nil {
			return nil, err
		}
		if parent.Valid {
			p := parent.Int64
			parents[id] = &p
		} else {
			parents[id] = nil
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return parents, nil
}

func validateCandidateHierarchyParent(nodeID int64, candidate vprocore.ProjectMetadataCell, parents map[int64]*int64) error {
	if candidate.Storage == "null" || candidate.Integer == nil {
		return nil
	}
	parentID, err := strconv.ParseInt(*candidate.Integer, 10, 64)
	if err != nil {
		return fmt.Errorf("Hierarchy node %d has invalid Parent %q", nodeID, *candidate.Integer)
	}
	if _, ok := parents[parentID]; !ok {
		return fmt.Errorf("Hierarchy node %d references non-existent Parent %d", nodeID, parentID)
	}
	visited := map[int64]bool{nodeID: true}
	curr := &parentID
	for curr != nil {
		if visited[*curr] {
			return fmt.Errorf("Hierarchy edit introduces a cycle involving node %d", *curr)
		}
		visited[*curr] = true
		curr = parents[*curr]
	}
	return nil
}

func verifyHierarchyAcyclicInTx(ctx context.Context, tx *sql.Tx, tableName string) error {
	parents, err := loadHierarchyParentsMap(ctx, tx, "main", tableName)
	if err != nil {
		return err
	}
	for id, p := range parents {
		if p != nil {
			if _, ok := parents[*p]; !ok {
				return fmt.Errorf("Hierarchy node %d references non-existent Parent %d", id, *p)
			}
		}
		visited := map[int64]bool{id: true}
		curr := p
		for curr != nil {
			if visited[*curr] {
				return fmt.Errorf("Hierarchy edit introduces a cycle involving node %d", *curr)
			}
			visited[*curr] = true
			curr = parents[*curr]
		}
	}
	return nil
}
