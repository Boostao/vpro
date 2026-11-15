package cloudsync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"slices"
	"strings"
	"time"
)

// ExecuteStagingToMasterMerge commits selective staging -> becmaster changes inside a single
// SERIALIZABLE PostgreSQL transaction with optimistic preview digest lock and hash-chained audit provenance.
func (m *Manager) ExecuteStagingToMasterMerge(ctx context.Context, req StagingMergeExecuteRequest) (StagingMergeResult, error) {
	subID := strings.TrimSpace(req.SubmissionID)
	if _, err := uuid.Parse(subID); err != nil {
		return StagingMergeResult{}, errors.New("submissionId must be a valid UUID")
	}
	if strings.TrimSpace(req.ExpectedPreviewDigest) == "" {
		return StagingMergeResult{}, errors.New("expectedPreviewDigest is required; run PreviewStagingToMasterMerge first")
	}
	defaultRes := strings.TrimSpace(req.DefaultConflictResolution)
	if defaultRes == "" {
		defaultRes = MergeResolutionKeepTarget
	}
	checkChoice := func(c string) error {
		if c != MergeResolutionKeepTarget && c != MergeResolutionAcceptSource {
			return fmt.Errorf("invalid merge resolution %q (expected %q or %q)", c, MergeResolutionKeepTarget, MergeResolutionAcceptSource)
		}
		return nil
	}
	if err := checkChoice(defaultRes); err != nil {
		return StagingMergeResult{}, err
	}
	for k, v := range req.PlotResolutions {
		if k == "" {
			return StagingMergeResult{}, errors.New("plotResolutions key must not be empty")
		}
		if err := checkChoice(v); err != nil {
			return StagingMergeResult{}, err
		}
	}
	for k, v := range req.FieldResolutions {
		if k == "" {
			return StagingMergeResult{}, errors.New("fieldResolutions key must not be empty")
		}
		if err := checkChoice(v); err != nil {
			return StagingMergeResult{}, err
		}
	}

	resolveChoice := func(item CloudMergeConflictItem) string {
		if c, ok := req.FieldResolutions[item.ConflictID]; ok {
			return c
		}
		// Custodian-protected fields (BECSiteUnit, BEC_Use, GIS_BGC) require explicit per-field acceptance!
		if item.CustodianProtected {
			return MergeResolutionKeepTarget
		}
		if c, ok := req.PlotResolutions[item.PlotNumber]; ok {
			return c
		}
		if item.Kind == "FastForward" || item.Kind == "TargetModifiedOnly" {
			return item.DefaultResolution
		}
		return defaultRes
	}

	conn, creds, err := m.OpenDedicatedConn(ctx, RoleModeCustodian)
	if err != nil {
		return StagingMergeResult{}, err
	}
	defer conn.Close(ctx)

	tx, err := conn.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return StagingMergeResult{}, wrapRedactedError("begin SERIALIZABLE merge transaction", err, creds)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var curStatus, currentDBUser string
	if err := tx.QueryRow(ctx, `SELECT status, current_user FROM staging.submissions WHERE submission_id = $1 FOR UPDATE`, subID).Scan(&curStatus, &currentDBUser); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return StagingMergeResult{}, fmt.Errorf("staging submission %s not found", subID)
		}
		return StagingMergeResult{}, wrapRedactedError("lock staging submission", err, creds)
	}
	if curStatus != "pending" {
		return StagingMergeResult{}, fmt.Errorf("staging submission %s has status %q (only 'pending' submissions can be merged)", subID, curStatus)
	}

	actor := strings.TrimSpace(req.Actor)
	if actor == "" {
		actor = currentDBUser
	}

	preview, srcSnap, tgtSnap, srcSHA, err := buildStagingMergePreviewOnQueryer(ctx, tx, subID, req.BaseDBPath, req.BaseProject)
	if err != nil {
		return StagingMergeResult{}, wrapRedactedError("re-verify merge preview inside SERIALIZABLE transaction", err, creds)
	}
	if preview.PreviewDigest != strings.TrimSpace(req.ExpectedPreviewDigest) {
		return StagingMergeResult{}, errors.New("staging or BECMaster plots changed since preview; re-run PreviewStagingToMasterMerge before merging")
	}

	mergeTxID := uuid.NewString()
	nowEditStr := time.Now().UTC().Format("2006-01-02 15:04:05")
	nowUTC := time.Now().UTC()

	var pendingAudits [][]any // each entry is 11 VP08AuditColumns values
	recordAudit := func(plot, tableSuffix, field string, beforeVal, afterVal *string, childID *int64) {
		var bAny, aAny, idAny any
		if beforeVal != nil {
			bAny = *beforeVal
		}
		if afterVal != nil {
			aAny = *afterVal
		}
		if childID != nil {
			idAny = *childID
		}
		pendingAudits = append(pendingAudits, []any{
			"BECMaster", actor, plot, "_" + tableSuffix, field, nowEditStr,
			bAny, aAny, int16(0), int16(0), idAny,
		})
	}

	allocatedIDs := []int64{}
	reservedDeletedIDs := []int64{}
	addedPlots, updatedPlots, skippedPlots := 0, 0, 0

	pgTblName := map[string]string{
		"Env": "env", "Admin": "admin", "Veg": "veg",
		"Humus": "humus", "Mineral": "mineral", "Other": "other",
	}

	insertChildRow := func(suffix, plot string, srcRow map[string]cloudCell) error {
		if err := validateHorizonRowDepth(suffix, srcRow); err != nil {
			return fmt.Errorf("plot %s %s: %w", plot, suffix, err)
		}
		cols := VP08ColumnsBySuffix(suffix)
		childTbl := pgTblName[suffix]
		newID, aErr := allocateMasterChildID(ctx, tx, childTbl)
		if aErr != nil {
			return aErr
		}
		allocatedIDs = append(allocatedIDs, newID)

		placeholders := make([]string, len(cols))
		args := make([]any, len(cols))
		for i, col := range cols {
			placeholders[i] = fmt.Sprintf("$%d", i+1)
			switch col.Name {
			case "PlotNumber":
				args[i] = plot
			case "ID":
				args[i] = newID
			default:
				c := srcRow[col.Name]
				if vErr := validateCloudMergeCell(suffix, col, c); vErr != nil {
					return fmt.Errorf("plot %s: %w", plot, vErr)
				}
				args[i] = c.pgParam(col)
			}
		}
		insSQL := fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
			quotePGIdent(childTbl), quotedColumnCSV(cols), strings.Join(placeholders, ", "))
		if _, err := tx.Exec(ctx, insSQL, args...); err != nil {
			return err
		}
		for _, col := range cols {
			if col.Name == "PlotNumber" || col.Name == "ID" {
				continue
			}
			c := srcRow[col.Name]
			if c.kind == "null" || (col.Name == "Flag" && c.kind == "int" && c.intVal == 0) {
				continue
			}
			recordAudit(plot, suffix, col.Name, nil, c.comparableString(), &newID)
		}
		return nil
	}

	insertWholePlot := func(plot string) error {
		if err := ValidateUTF16Bound("PlotNumber", plot, 7); err != nil {
			return err
		}
		for _, suffix := range []string{"Env", "Admin"} {
			srcMap := plotRawRowsFromSnap(srcSnap, suffix, plot)
			srcRow, ok := srcMap[suffix]
			if !ok {
				return fmt.Errorf("staging plot %s is missing required %s row", plot, suffix)
			}
			cols := VP08ColumnsBySuffix(suffix)
			keyCol := "PlotNumber"
			if suffix == "Admin" {
				keyCol = "Plot"
			}
			placeholders := make([]string, len(cols))
			args := make([]any, len(cols))
			for i, col := range cols {
				placeholders[i] = fmt.Sprintf("$%d", i+1)
				if col.Name == keyCol {
					args[i] = plot
				} else {
					c := srcRow[col.Name]
					if vErr := validateCloudMergeCell(suffix, col, c); vErr != nil {
						return fmt.Errorf("plot %s: %w", plot, vErr)
					}
					args[i] = c.pgParam(col)
				}
			}
			insSQL := fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
				quotePGIdent(pgTblName[suffix]), quotedColumnCSV(cols), strings.Join(placeholders, ", "))
			if _, err := tx.Exec(ctx, insSQL, args...); err != nil {
				return err
			}
			pCopy := plot
			recordAudit(plot, suffix, keyCol, nil, &pCopy, nil)
			for _, col := range cols {
				if col.Name == keyCol {
					continue
				}
				c := srcRow[col.Name]
				if c.kind == "null" {
					continue
				}
				recordAudit(plot, suffix, col.Name, nil, c.comparableString(), nil)
			}
		}
		for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other"} {
			childMap := plotRawRowsFromSnap(srcSnap, suffix, plot)
			keys := make([]string, 0, len(childMap))
			for k := range childMap {
				keys = append(keys, k)
			}
			slices.Sort(keys)
			for _, rk := range keys {
				if err := insertChildRow(suffix, plot, childMap[rk]); err != nil {
					return err
				}
			}
		}
		return nil
	}

	colSpecLookup := func(suffix, field string) (ColumnSpec, bool) {
		for _, c := range VP08ColumnsBySuffix(suffix) {
			if c.Name == field {
				return c, true
			}
		}
		return ColumnSpec{}, false
	}

	for _, plotPlan := range preview.Plots {
		if err := ctx.Err(); err != nil {
			return StagingMergeResult{}, err
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
			if err := insertWholePlot(plot); err != nil {
				return StagingMergeResult{}, wrapRedactedError("insert added plot "+plot, err, creds)
			}
			addedPlots++
		case "FastForward", "Conflict":
			if len(plotPlan.Items) == 1 && plotPlan.Items[0].Key == "Plot" && !tgtSnap.plots[plot] && srcSnap.plots[plot] {
				if resolveChoice(plotPlan.Items[0]) == MergeResolutionAcceptSource {
					if err := insertWholePlot(plot); err != nil {
						return StagingMergeResult{}, wrapRedactedError("re-insert plot "+plot, err, creds)
					}
					addedPlots++
				} else {
					skippedPlots++
				}
				continue
			}

			plotModified := false
			touchedChildRows := map[string]struct{ suffix, plot, rowKey string }{}

			for _, item := range plotPlan.Items {
				if resolveChoice(item) != MergeResolutionAcceptSource {
					continue
				}
				suffix := item.Table
				pgTbl := pgTblName[suffix]

				if suffix == "Env" || suffix == "Admin" {
					keyCol := "PlotNumber"
					if suffix == "Admin" {
						keyCol = "Plot"
					}
					if item.Field == "*" {
						if item.SourceVal != nil && item.TargetVal == nil {
							srcRow := srcSnap.rawCells[suffix][plot+"\x00"+suffix]
							cols := VP08ColumnsBySuffix(suffix)
							placeholders := make([]string, len(cols))
							args := make([]any, len(cols))
							for i, col := range cols {
								placeholders[i] = fmt.Sprintf("$%d", i+1)
								if col.Name == keyCol {
									args[i] = plot
								} else {
									c := srcRow[col.Name]
									if vErr := validateCloudMergeCell(suffix, col, c); vErr != nil {
										return StagingMergeResult{}, fmt.Errorf("plot %s: %w", plot, vErr)
									}
									args[i] = c.pgParam(col)
								}
							}
							if _, iErr := tx.Exec(ctx, fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
								quotePGIdent(pgTbl), quotedColumnCSV(cols), strings.Join(placeholders, ", ")), args...); iErr != nil {
								return StagingMergeResult{}, wrapRedactedError("insert missing "+suffix, iErr, creds)
							}
							pCopy := plot
							recordAudit(plot, suffix, keyCol, nil, &pCopy, nil)
							plotModified = true
						}
						continue
					}
					colSpec, ok := colSpecLookup(suffix, item.Field)
					if !ok {
						return StagingMergeResult{}, fmt.Errorf("unknown column %s.%s", suffix, item.Field)
					}
					srcCell := srcSnap.rawCells[suffix][plot+"\x00"+suffix][item.Field]
					if err := validateCloudMergeCell(suffix, colSpec, srcCell); err != nil {
						return StagingMergeResult{}, fmt.Errorf("plot %s: %w", plot, err)
					}
					tag, uErr := tx.Exec(ctx, fmt.Sprintf(
						`UPDATE becmaster.%s SET %s = $1 WHERE %s = $2`,
						quotePGIdent(pgTbl), quotePGIdent(item.Field), quotePGIdent(keyCol),
					), srcCell.pgParam(colSpec), plot)
					if uErr != nil {
						return StagingMergeResult{}, wrapRedactedError("update "+suffix+"."+item.Field, uErr, creds)
					}
					if tag.RowsAffected() != 1 {
						return StagingMergeResult{}, fmt.Errorf("merge update on %s.%s for plot %s matched %d rows", suffix, item.Field, plot, tag.RowsAffected())
					}
					recordAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, nil)
					plotModified = true
					continue
				}

				// Child table addition / deletion
				if item.Field == "*" {
					if item.SourceVal != nil && item.TargetVal == nil {
						srcRow := srcSnap.rawCells[suffix][plot+"\x00"+item.Key]
						if err := insertChildRow(suffix, plot, srcRow); err != nil {
							return StagingMergeResult{}, wrapRedactedError("insert child row", err, creds)
						}
						plotModified = true
					} else if item.SourceVal == nil && item.TargetVal != nil {
						tgtRow := tgtSnap.rawCells[suffix][plot+"\x00"+item.Key]
						idCell := tgtRow["ID"]
						if idCell.kind != "int" {
							return StagingMergeResult{}, fmt.Errorf("target %s row in plot %s lacks integer ID", suffix, plot)
						}
						tgtID := idCell.intVal
						if err := reserveMasterChildID(ctx, tx, pgTbl, tgtID); err != nil {
							return StagingMergeResult{}, wrapRedactedError("reserve deleted child ID", err, creds)
						}
						reservedDeletedIDs = append(reservedDeletedIDs, tgtID)

						tag, dErr := tx.Exec(ctx, fmt.Sprintf(
							`DELETE FROM becmaster.%s WHERE "PlotNumber" = $1 AND "ID" = $2`,
							quotePGIdent(pgTbl),
						), plot, tgtID)
						if dErr != nil {
							return StagingMergeResult{}, wrapRedactedError("delete child row", dErr, creds)
						}
						if tag.RowsAffected() != 1 {
							return StagingMergeResult{}, fmt.Errorf("child delete on %s (plot %s, ID %d) matched %d rows", suffix, plot, tgtID, tag.RowsAffected())
						}
						for _, col := range VP08ColumnsBySuffix(suffix) {
							if col.Name == "PlotNumber" || col.Name == "ID" {
								continue
							}
							oldCell := tgtRow[col.Name]
							if oldCell.kind == "null" || (col.Name == "Flag" && oldCell.kind == "int" && oldCell.intVal == 0) {
								continue
							}
							recordAudit(plot, suffix, col.Name, oldCell.comparableString(), nil, &tgtID)
						}
						plotModified = true
					}
					continue
				}

				// Field-level update on an existing child row
				dotIdx := strings.LastIndex(item.Key, ".")
				if dotIdx <= 0 {
					return StagingMergeResult{}, fmt.Errorf("malformed child conflict key %q", item.Key)
				}
				rowKey := item.Key[:dotIdx]
				colSpec, ok := colSpecLookup(suffix, item.Field)
				if !ok {
					return StagingMergeResult{}, fmt.Errorf("unknown child column %s.%s", suffix, item.Field)
				}
				srcCell := srcSnap.rawCells[suffix][plot+"\x00"+rowKey][item.Field]
				if err := validateCloudMergeCell(suffix, colSpec, srcCell); err != nil {
					return StagingMergeResult{}, fmt.Errorf("plot %s: %w", plot, err)
				}
				tgtRow := tgtSnap.rawCells[suffix][plot+"\x00"+rowKey]
				idCell := tgtRow["ID"]
				if idCell.kind != "int" {
					return StagingMergeResult{}, fmt.Errorf("target %s row in plot %s lacks integer ID", suffix, plot)
				}
				tgtID := idCell.intVal
				tag, uErr := tx.Exec(ctx, fmt.Sprintf(
					`UPDATE becmaster.%s SET %s = $1 WHERE "PlotNumber" = $2 AND "ID" = $3`,
					quotePGIdent(pgTbl), quotePGIdent(item.Field),
				), srcCell.pgParam(colSpec), plot, tgtID)
				if uErr != nil {
					return StagingMergeResult{}, wrapRedactedError("update child field", uErr, creds)
				}
				if tag.RowsAffected() != 1 {
					return StagingMergeResult{}, fmt.Errorf("child update on %s.%s (plot %s, ID %d) matched %d rows", suffix, item.Field, plot, tgtID, tag.RowsAffected())
				}
				recordAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, &tgtID)
				if suffix == "Humus" || suffix == "Mineral" {
					touchedChildRows[suffix+"\x00"+plot+"\x00"+rowKey] = struct{ suffix, plot, rowKey string }{suffix, plot, rowKey}
				}
				plotModified = true
			}

			// Verify LMH25 horizon depth sign invariant on any updated Humus/Mineral rows!
			for _, tr := range touchedChildRows {
				tgtID := tgtSnap.rawCells[tr.suffix][tr.plot+"\x00"+tr.rowKey]["ID"].intVal
				var hz *string
				var up, lo *float64
				if err := tx.QueryRow(ctx, fmt.Sprintf(
					`SELECT "Horizon", "UpperDepth", "LowerDepth" FROM becmaster.%s WHERE "PlotNumber" = $1 AND "ID" = $2`,
					quotePGIdent(pgTblName[tr.suffix]),
				), tr.plot, tgtID).Scan(&hz, &up, &lo); err != nil {
					return StagingMergeResult{}, wrapRedactedError("verify merged horizon depth", err, creds)
				}
				hzStr := ""
				if hz != nil {
					hzStr = *hz
				}
				if err := ValidateLMH25HorizonDepth(tr.suffix, hzStr, up, lo); err != nil {
					return StagingMergeResult{}, fmt.Errorf("plot %s: %w", tr.plot, err)
				}
			}

			if plotModified {
				updatedPlots++
			} else {
				skippedPlots++
			}
		}
	}

	// Insert genuinely new ProjectID metadata rows into becmaster.metadata (never overwriting existing curated master metadata without review)
	if addedPlots > 0 || updatedPlots > 0 {
		newMetaRows, mErr := tx.Query(ctx, fmt.Sprintf(`
			SELECT %s FROM staging.metadata s
			WHERE s.submission_id = $1
			  AND NOT EXISTS (SELECT 1 FROM becmaster.metadata m WHERE m."ProjectID" = s."ProjectID")
		`, quotedColumnCSV(VP08MetadataColumns)), subID)
		if mErr != nil {
			return StagingMergeResult{}, wrapRedactedError("query new staging.metadata rows", mErr, creds)
		}
		var metaPayloads [][]any
		for newMetaRows.Next() {
			vals, vErr := newMetaRows.Values()
			if vErr != nil {
				newMetaRows.Close()
				return StagingMergeResult{}, wrapRedactedError("scan staging.metadata row", vErr, creds)
			}
			cp := make([]any, len(vals))
			copy(cp, vals)
			metaPayloads = append(metaPayloads, cp)
		}
		newMetaRows.Close()
		if err := newMetaRows.Err(); err != nil {
			return StagingMergeResult{}, wrapRedactedError("iterate staging.metadata rows", err, creds)
		}

		metaIDColIdx := len(VP08MetadataColumns) - 1
		placeholders := make([]string, len(VP08MetadataColumns))
		for i := range placeholders {
			placeholders[i] = fmt.Sprintf("$%d", i+1)
		}
		insMetaSQL := fmt.Sprintf("INSERT INTO becmaster.metadata (%s) VALUES (%s) ON CONFLICT (\"ProjectID\") DO NOTHING",
			quotedColumnCSV(VP08MetadataColumns), strings.Join(placeholders, ", "))
		for _, rowVals := range metaPayloads {
			newMetaID, aErr := allocateMasterChildID(ctx, tx, "metadata")
			if aErr != nil {
				return StagingMergeResult{}, wrapRedactedError("allocate metadata ID", aErr, creds)
			}
			rowVals[metaIDColIdx] = newMetaID
			tag, iErr := tx.Exec(ctx, insMetaSQL, rowVals...)
			if iErr != nil {
				return StagingMergeResult{}, wrapRedactedError("insert becmaster.metadata", iErr, creds)
			}
			if tag.RowsAffected() == 1 {
				if pid, ok := rowVals[0].(string); ok {
					pidCopy := pid
					recordAudit("", "Metadata", "ProjectID", nil, &pidCopy, &newMetaID)
				}
			}
		}
	}

	// Append hash-chained audit trail rows into becmaster.audit
	prevHash := GenesisAuditHash
	_ = tx.QueryRow(ctx, `SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1`).Scan(&prevHash)
	if len(pendingAudits) > 0 {
		copyCols := append(columnNames(VP08AuditColumns), "merge_tx_id", "prev_hash", "row_hash")
		idx := 0
		_, cErr := tx.CopyFrom(
			ctx,
			pgx.Identifier{"becmaster", "audit"},
			copyCols,
			pgx.CopyFromFunc(func() ([]any, error) {
				if idx >= len(pendingAudits) {
					return nil, nil
				}
				vp08Row := pendingAudits[idx]
				idx++
				rowHash := ComputeAuditRowHash(prevHash, mergeTxID, vp08Row)
				out := make([]any, len(copyCols))
				copy(out, vp08Row)
				out[len(VP08AuditColumns)] = mergeTxID
				out[len(VP08AuditColumns)+1] = prevHash
				out[len(VP08AuditColumns)+2] = rowHash
				prevHash = rowHash
				return out, nil
			}),
		)
		if cErr != nil {
			return StagingMergeResult{}, wrapRedactedError("append hash-chained becmaster.audit rows", cErr, creds)
		}
	}

	summaryPayload, _ := json.Marshal(map[string]any{
		"sourceProject":      preview.SourceProject,
		"previewDigest":      preview.PreviewDigest,
		"addedPlots":         addedPlots,
		"updatedPlots":       updatedPlots,
		"skippedPlots":       skippedPlots,
		"auditRowsWritten":   len(pendingAudits),
		"allocatedChildIds":  len(allocatedIDs),
		"reservedDeletedIds": len(reservedDeletedIDs),
		"tailAuditHash":      prevHash,
	})

	if _, err := tx.Exec(ctx, `
		INSERT INTO becmaster.merge_ledger (
			merge_tx_id, submission_id, actor, merged_at, source_sha256,
			added_plots, updated_plots, summary_json
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
	`, mergeTxID, subID, actor, nowUTC, srcSHA, addedPlots, updatedPlots, string(summaryPayload)); err != nil {
		return StagingMergeResult{}, wrapRedactedError("insert becmaster.merge_ledger", err, creds)
	}

	var revNotesPtr *string
	if rn := strings.TrimSpace(req.ReviewerNotes); rn != "" {
		revNotesPtr = &rn
	}
	if _, err := tx.Exec(ctx, `
		UPDATE staging.submissions
		SET status = 'merged',
		    reviewed_by = $2,
		    reviewed_at = $3,
		    reviewer_notes = COALESCE($4, reviewer_notes),
		    merged_tx_id = $5
		WHERE submission_id = $1
	`, subID, actor, nowUTC, revNotesPtr, mergeTxID); err != nil {
		return StagingMergeResult{}, wrapRedactedError("mark staging submission merged", err, creds)
	}

	if err := tx.Commit(ctx); err != nil {
		return StagingMergeResult{}, wrapRedactedError("commit SERIALIZABLE merge transaction", err, creds)
	}

	slices.Sort(allocatedIDs)
	slices.Sort(reservedDeletedIDs)
	reservedDeletedIDs = slices.Compact(reservedDeletedIDs)

	return StagingMergeResult{
		MergeTxID:          mergeTxID,
		SubmissionID:       subID,
		SourceProject:      preview.SourceProject,
		AddedPlots:         addedPlots,
		UpdatedPlots:       updatedPlots,
		SkippedPlots:       skippedPlots,
		AllocatedChildIDs:  allocatedIDs,
		ReservedDeletedIDs: reservedDeletedIDs,
		AuditRowsWritten:   len(pendingAudits),
		TailAuditHash:      prevHash,
		MergedAt:           nowUTC.Format(time.RFC3339),
	}, nil
}
