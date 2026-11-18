package twopage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// DeleteTwoPageVegetationRow deletes a <Project>_Veg row scoped to Two-Page entry,
// permanently reserving the row ID in __VPRO_ChildIdentity, recording <Project>_Audit provenance,
// and archiving a restoration snapshot in __VPRO_TwoPageVegetationLifecycleHistory.
func DeleteTwoPageVegetationRow(s *vprocore.ContextService, ctx context.Context, contextID string, req DeleteTwoPageVegetationRequest) (DeleteTwoPageVegetationResult, error) {
	if s == nil {
		return DeleteTwoPageVegetationResult{}, errors.New("two-page vegetation context service is unavailable")
	}
	if ctx == nil {
		return DeleteTwoPageVegetationResult{}, errors.New("two-page vegetation deletion requires a context")
	}
	if err := ctx.Err(); err != nil {
		return DeleteTwoPageVegetationResult{}, err
	}
	if _, err := twoPageVegetationCreateCovers(req.Form); err != nil {
		return DeleteTwoPageVegetationResult{}, err
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return DeleteTwoPageVegetationResult{}, errors.New("two-page vegetation deletion requires a literal valid plotNumber")
	}
	if err := vprocore.ValidateChildPhysicalText("PlotNumber", req.PlotNumber, 7); err != nil {
		return DeleteTwoPageVegetationResult{}, err
	}
	if req.ID < -2147483648 || req.ID > 2147483647 {
		return DeleteTwoPageVegetationResult{}, errors.New("two-page vegetation deletion requires a signed32 child ID")
	}
	requestID, err := normalizeTwoPageVegRequestID(req.RequestID)
	if err != nil {
		return DeleteTwoPageVegetationResult{}, err
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (DeleteTwoPageVegetationResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return DeleteTwoPageVegetationResult{}, err
		}
		owner := plots.Projects.Sqlite
		actor := strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		strength := plots.AuditStrength

		var out DeleteTwoPageVegetationResult
		wErr := owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			suAlias, err := sourceform.SiviParentWriterSU(ctx, conn, owner)
			if err != nil {
				return err
			}
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			if suAlias == "sivi_su" {
				if err := vprocore.RequireRollbackJournalReadLock(ctx, tx, suAlias, "two-page vegetation deletion SU check"); err != nil {
					return err
				}
			}
			if err := twoPageChildWriterSelectedParent(ctx, tx, owner, suAlias, req.PlotNumber, "vegetation"); err != nil {
				return err
			}

			project := owner.Selection.Project
			tableName := project + "_Veg"
			quotedTbl := vprocore.QuoteHeaderIdentifier(tableName)
			quotedAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")

			var hasHistory bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, twoPageVegetationLifecycleHistoryTable).Scan(&hasHistory); err != nil {
				return err
			}
			if hasHistory {
				var rawProposal string
				rErr := tx.QueryRowContext(ctx, `SELECT Proposal FROM "`+twoPageVegetationLifecycleHistoryTable+`" WHERE RequestID = ?`, requestID).Scan(&rawProposal)
				if rErr == nil {
					var prev twoPageVegLifecycleHistory
					if err := json.Unmarshal([]byte(rawProposal), &prev); err != nil {
						return err
					}
					if prev.Action != "delete" || prev.Project != project || prev.ID != req.ID || prev.PlotNumber != req.PlotNumber || prev.Form != req.Form {
						return errors.New("requestId already belongs to a different two-page vegetation history entry")
					}
					out = DeleteTwoPageVegetationResult{
						RequestID:        requestID,
						ContextID:        contextID,
						Project:          project,
						PlotNumber:       req.PlotNumber,
						Form:             req.Form,
						DeletedID:        req.ID,
						Species:          prev.Species,
						ReservedInLedger: req.ID >= 0,
						AuditRowCount:    len(prev.Audits),
						EditWhen:         prev.EditWhen,
						Replayed:         true,
					}
					return nil
				} else if !errors.Is(rErr, sql.ErrNoRows) {
					return rErr
				}
			}

			if err := vprocore.ChildParent(tx, project, req.PlotNumber); err != nil {
				return err
			}
			beforeRecords, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "main", tableName, "PlotNumber", req.PlotNumber, "")
			if err != nil {
				return err
			}
			colMap, err := vprocore.SiteUnitTransferColumns(beforeRecords, "ID", "PlotNumber", "Species")
			if err != nil {
				return err
			}

			targetIdx := -1
			idText := strconv.FormatInt(req.ID, 10)
			for i, r := range beforeRecords.Rows {
				if sourceform.SiviIdentityCellMatches(r.Cells[colMap["ID"]], idText) {
					if targetIdx >= 0 {
						return fmt.Errorf("ambiguous Veg ID %d in plot %s; deletion refused", req.ID, req.PlotNumber)
					}
					targetIdx = i
				}
			}
			if targetIdx < 0 {
				return fmt.Errorf("Veg row ID %d not found on plot %s", req.ID, req.PlotNumber)
			}
			deletedRow := beforeRecords.Rows[targetIdx]
			if strings.TrimSpace(req.RowID) != "" && deletedRow.RowID != strings.TrimSpace(req.RowID) {
				return fmt.Errorf("Veg physical rowId changed (expected %s, found %s); reload before deleting", req.RowID, deletedRow.RowID)
			}

			if err := reserveTwoPageVegChildIDs(ctx, tx, quotedTbl, tableName, &req.ID); err != nil {
				return err
			}
			physRowID, err := strconv.ParseInt(deletedRow.RowID, 10, 64)
			if err != nil {
				return err
			}
			dRes, err := tx.ExecContext(ctx, `DELETE FROM `+quotedTbl+` WHERE rowid = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`,
				physRowID, req.PlotNumber, req.ID)
			if err != nil {
				return err
			}
			if n, _ := dRes.RowsAffected(); n != 1 {
				return errors.New("two-page vegetation deletion did not affect exactly 1 row")
			}

			now := time.Now().Format("2006-01-02 15:04:05")
			effectiveStrength := strength
			if effectiveStrength < 3 {
				effectiveStrength = 3
			}
			var auditEntries []vprocore.AuditEntry
			for cIdx, col := range beforeRecords.Columns {
				if col.Name == "ID" || col.Name == "PlotNumber" {
					continue
				}
				cell := deletedRow.Cells[cIdx]
				if cell.Storage == "null" || (col.Name == "Flag" && cell.Storage == "integer" && cell.Integer != nil && *cell.Integer == "0") {
					continue
				}
				oldVal, mErr := vprocore.MetadataCellValue(cell)
				if mErr != nil {
					return mErr
				}
				tracked, aErr := vprocore.AuditChildFieldsTracked(tx, project, "Veg", req.PlotNumber, req.ID,
					[]vprocore.ChildField{{Column: col.Name}}, []any{oldVal}, []any{nil}, actor, effectiveStrength, now)
				if aErr != nil {
					return aErr
				}
				for _, tr := range tracked {
					ids, _ := vprocore.AuditRowIDs([]string{tr.RowID})
					recs, sErr := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
					if sErr == nil && len(recs) == 1 {
						auditEntries = append(auditEntries, recs[0])
					}
				}
			}
			species := extractVegTextFromRow(beforeRecords.Columns, deletedRow, "Species")
			if len(auditEntries) == 0 {
				ins, aErr := tx.ExecContext(ctx, `INSERT INTO `+quotedAudit+
					` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
					project, actor, req.PlotNumber, "_Veg", "Species", now, strconv.FormatInt(req.ID, 10), nil, req.ID)
				if aErr != nil {
					return aErr
				}
				aRowID, _ := ins.LastInsertId()
				ids, _ := vprocore.AuditRowIDs([]string{strconv.FormatInt(aRowID, 10)})
				recs, _ := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
				if len(recs) == 1 {
					auditEntries = append(auditEntries, recs[0])
				}
			}

			delRowCopy := deletedRow
			history := twoPageVegLifecycleHistory{
				RequestID:     requestID,
				Action:        "delete",
				ContextID:     contextID,
				Project:       project,
				PlotNumber:    req.PlotNumber,
				Form:          req.Form,
				ID:            req.ID,
				RowID:         deletedRow.RowID,
				Species:       species,
				Actor:         actor,
				AuditStrength: strength,
				EditWhen:      now,
				Audits:        auditEntries,
				Columns:       beforeRecords.Columns,
				DeletedRow:    &delRowCopy,
			}
			proposalJSON, err := json.Marshal(history)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "`+twoPageVegetationLifecycleHistoryTable+`" (
				RequestID TEXT NOT NULL PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO "`+twoPageVegetationLifecycleHistoryTable+`" VALUES(?,?,?)`,
				requestID, now, string(proposalJSON)); err != nil {
				return err
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			out = DeleteTwoPageVegetationResult{
				RequestID:        requestID,
				ContextID:        contextID,
				Project:          project,
				PlotNumber:       req.PlotNumber,
				Form:             req.Form,
				DeletedID:        req.ID,
				Species:          species,
				ReservedInLedger: req.ID >= 0,
				AuditRowCount:    len(auditEntries),
				EditWhen:         now,
				Replayed:         false,
			}
			return nil
		})
		if wErr != nil {
			return DeleteTwoPageVegetationResult{}, wErr
		}
		return out, nil
	})
}

// RestoreTwoPageVegetationRow restores a previously deleted <Project>_Veg row recorded
// in __VPRO_TwoPageVegetationLifecycleHistory inside an atomic BEGIN IMMEDIATE transaction.
func RestoreTwoPageVegetationRow(s *vprocore.ContextService, ctx context.Context, contextID string, req RestoreTwoPageVegetationRequest) (RestoreTwoPageVegetationResult, error) {
	if s == nil {
		return RestoreTwoPageVegetationResult{}, errors.New("two-page vegetation context service is unavailable")
	}
	if ctx == nil {
		return RestoreTwoPageVegetationResult{}, errors.New("two-page vegetation restoration requires a context")
	}
	if err := ctx.Err(); err != nil {
		return RestoreTwoPageVegetationResult{}, err
	}
	if _, err := twoPageVegetationCreateCovers(req.Form); err != nil {
		return RestoreTwoPageVegetationResult{}, err
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return RestoreTwoPageVegetationResult{}, errors.New("two-page vegetation restoration requires a literal valid plotNumber")
	}
	deleteReqID := strings.TrimSpace(req.DeleteRequestID)
	if !vprocore.SiviDeletionUUID.MatchString(deleteReqID) {
		return RestoreTwoPageVegetationResult{}, errors.New("deleteRequestId must be a lowercase UUIDv4")
	}
	requestID, err := normalizeTwoPageVegRequestID(req.RequestID)
	if err != nil {
		return RestoreTwoPageVegetationResult{}, err
	}
	if requestID == deleteReqID {
		return RestoreTwoPageVegetationResult{}, errors.New("restoration requestId must differ from deleteRequestId")
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (RestoreTwoPageVegetationResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return RestoreTwoPageVegetationResult{}, err
		}
		owner := plots.Projects.Sqlite
		actor := strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		strength := plots.AuditStrength

		var out RestoreTwoPageVegetationResult
		wErr := owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			suAlias, err := sourceform.SiviParentWriterSU(ctx, conn, owner)
			if err != nil {
				return err
			}
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			if suAlias == "sivi_su" {
				if err := vprocore.RequireRollbackJournalReadLock(ctx, tx, suAlias, "two-page vegetation restoration SU check"); err != nil {
					return err
				}
			}
			if err := twoPageChildWriterSelectedParent(ctx, tx, owner, suAlias, req.PlotNumber, "vegetation"); err != nil {
				return err
			}

			project := owner.Selection.Project
			tableName := project + "_Veg"
			quotedTbl := vprocore.QuoteHeaderIdentifier(tableName)
			quotedAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")

			if err := vprocore.ChildParent(tx, project, req.PlotNumber); err != nil {
				return err
			}
			var hasHistory bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, twoPageVegetationLifecycleHistoryTable).Scan(&hasHistory); err != nil {
				return err
			}
			if !hasHistory {
				return errors.New("no two-page vegetation deletion history exists in this project")
			}

			hRows, err := tx.QueryContext(ctx, `SELECT RequestID, Proposal FROM "`+twoPageVegetationLifecycleHistoryTable+`" ORDER BY rowid`)
			if err != nil {
				return err
			}
			var targetDeletion, replayRestore *twoPageVegLifecycleHistory
			alreadyConsumed := false
			for hRows.Next() {
				var rID, rawProp string
				if err := hRows.Scan(&rID, &rawProp); err != nil {
					hRows.Close()
					return err
				}
				var parsed twoPageVegLifecycleHistory
				if uErr := json.Unmarshal([]byte(rawProp), &parsed); uErr != nil {
					hRows.Close()
					return uErr
				}
				if rID == requestID {
					if parsed.Action != "restore" || parsed.RestoreOfRequestID == nil || *parsed.RestoreOfRequestID != deleteReqID {
						hRows.Close()
						return errors.New("requestId already belongs to another vegetation history operation")
					}
					cp := parsed
					replayRestore = &cp
				}
				if rID == deleteReqID && parsed.Action == "delete" {
					cp := parsed
					targetDeletion = &cp
				}
				if parsed.Action == "restore" && parsed.RestoreOfRequestID != nil && *parsed.RestoreOfRequestID == deleteReqID && rID != requestID {
					alreadyConsumed = true
				}
			}
			if err := errors.Join(hRows.Err(), hRows.Close()); err != nil {
				return err
			}

			if replayRestore != nil {
				out = RestoreTwoPageVegetationResult{
					RequestID:       requestID,
					DeleteRequestID: deleteReqID,
					ContextID:       contextID,
					Project:         project,
					PlotNumber:      req.PlotNumber,
					Form:            req.Form,
					RestoredID:      replayRestore.ID,
					RestoredRowID:   replayRestore.RowID,
					Species:         replayRestore.Species,
					AuditRowCount:   len(replayRestore.Audits),
					EditWhen:        replayRestore.EditWhen,
					Replayed:        true,
				}
				return nil
			}
			if targetDeletion == nil {
				return fmt.Errorf("deleted vegetation snapshot %s not found in lifecycle history", deleteReqID)
			}
			if targetDeletion.Project != project || targetDeletion.PlotNumber != req.PlotNumber || targetDeletion.Form != req.Form {
				return errors.New("deleted vegetation snapshot belongs to a different project/plot/form")
			}
			if alreadyConsumed {
				return fmt.Errorf("deleted vegetation snapshot %s has already been restored", deleteReqID)
			}
			if targetDeletion.DeletedRow == nil || len(targetDeletion.Columns) == 0 {
				return errors.New("corrupt deleted vegetation snapshot lacks row data")
			}

			restoredID := targetDeletion.ID
			var existingCount int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+quotedTbl+` WHERE "ID" = ?`, restoredID).Scan(&existingCount); err != nil {
				return err
			}
			if existingCount > 0 {
				return fmt.Errorf("vegetation ID %d already exists in %s; restoration refused", restoredID, tableName)
			}

			names := make([]string, len(targetDeletion.Columns))
			marks := make([]string, len(targetDeletion.Columns))
			vals := make([]any, len(targetDeletion.Columns))
			for i, col := range targetDeletion.Columns {
				names[i] = vprocore.QuoteHeaderIdentifier(col.Name)
				marks[i] = "?"
				if i < len(targetDeletion.DeletedRow.Cells) {
					v, cErr := vprocore.MetadataCellValue(targetDeletion.DeletedRow.Cells[i])
					if cErr != nil {
						return cErr
					}
					vals[i] = v
				}
			}
			insRes, err := tx.ExecContext(ctx, `INSERT INTO `+quotedTbl+` (`+strings.Join(names, ",")+`) VALUES (`+strings.Join(marks, ",")+`)`, vals...)
			if err != nil {
				return err
			}
			newRowID, err := insRes.LastInsertId()
			if err != nil {
				return err
			}
			newRowIDStr := strconv.FormatInt(newRowID, 10)

			for _, delAudit := range targetDeletion.Audits {
				if aRowID, pErr := strconv.ParseInt(delAudit.RowID, 10, 64); pErr == nil {
					if _, err := tx.ExecContext(ctx, `UPDATE `+quotedAudit+` SET "Restore" = -1 WHERE rowid = ? AND "PlotNumber" = ?`, aRowID, req.PlotNumber); err != nil {
						return fmt.Errorf("mark deletion audit restored: %w", err) // ENG-GO-004
					}
				}
			}

			now := time.Now().Format("2006-01-02 15:04:05")
			var restoreAudits []vprocore.AuditEntry
			aIns, err := tx.ExecContext(ctx, `INSERT INTO `+quotedAudit+
				` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
				project, actor, req.PlotNumber, "_Veg", "Species", now, nil, targetDeletion.Species, restoredID)
			if err != nil {
				return err
			}
			aRowID, _ := aIns.LastInsertId()
			ids, _ := vprocore.AuditRowIDs([]string{strconv.FormatInt(aRowID, 10)})
			recs, _ := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
			if len(recs) == 1 {
				restoreAudits = append(restoreAudits, recs[0])
			}

			delReqCopy := deleteReqID
			history := twoPageVegLifecycleHistory{
				RequestID:          requestID,
				Action:             "restore",
				ContextID:          contextID,
				Project:            project,
				PlotNumber:         req.PlotNumber,
				Form:               req.Form,
				ID:                 restoredID,
				RowID:              newRowIDStr,
				Species:            targetDeletion.Species,
				Actor:              actor,
				AuditStrength:      strength,
				EditWhen:           now,
				Audits:             restoreAudits,
				RestoreOfRequestID: &delReqCopy,
			}
			proposalJSON, err := json.Marshal(history)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO "`+twoPageVegetationLifecycleHistoryTable+`" VALUES(?,?,?)`,
				requestID, now, string(proposalJSON)); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			out = RestoreTwoPageVegetationResult{
				RequestID:       requestID,
				DeleteRequestID: deleteReqID,
				ContextID:       contextID,
				Project:         project,
				PlotNumber:      req.PlotNumber,
				Form:            req.Form,
				RestoredID:      restoredID,
				RestoredRowID:   newRowIDStr,
				Species:         targetDeletion.Species,
				AuditRowCount:   len(restoreAudits),
				EditWhen:        now,
				Replayed:        false,
			}
			return nil
		})
		if wErr != nil {
			return RestoreTwoPageVegetationResult{}, wErr
		}
		return out, nil
	})
}

// ListTwoPageVegetationDeletedRows lists deleted vegetation rows recorded in
// __VPRO_TwoPageVegetationLifecycleHistory for the specified plotNumber and form.
func ListTwoPageVegetationDeletedRows(s *vprocore.ContextService, ctx context.Context, contextID, plotNumber, form string) ([]DeletedTwoPageVegetationEntry, error) {
	if s == nil {
		return nil, errors.New("two-page vegetation context service is unavailable")
	}
	if ctx == nil {
		return nil, errors.New("two-page vegetation list requires a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if _, err := twoPageVegetationCreateCovers(form); err != nil {
		return nil, err
	}
	if plotNumber == "" || !utf8.ValidString(plotNumber) || strings.ContainsRune(plotNumber, 0) {
		return nil, errors.New("plotNumber must be a valid literal string")
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) ([]DeletedTwoPageVegetationEntry, error) {
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) ([]DeletedTwoPageVegetationEntry, error) {
			project := owner.Selection.Project
			if err := sourceform.RequireTwoPageChildReadScope(ctx, tx, project, project+"_Veg", plotNumber, "vegetation"); err != nil {
				return nil, err
			}
			var hasHistory bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM project.sqlite_master WHERE type='table' AND name=?)`, twoPageVegetationLifecycleHistoryTable).Scan(&hasHistory); err != nil {
				return nil, err
			}
			if !hasHistory {
				return []DeletedTwoPageVegetationEntry{}, nil
			}
			rows, err := tx.QueryContext(ctx, `SELECT Proposal FROM project."`+twoPageVegetationLifecycleHistoryTable+`" ORDER BY rowid DESC`)
			if err != nil {
				return nil, err
			}
			restoredSet := make(map[string]bool)
			var parsedList []twoPageVegLifecycleHistory
			for rows.Next() {
				var raw string
				if err := rows.Scan(&raw); err != nil {
					rows.Close()
					return nil, err
				}
				var h twoPageVegLifecycleHistory
				if uErr := json.Unmarshal([]byte(raw), &h); uErr != nil {
					rows.Close()
					return nil, uErr
				}
				if h.Action == "restore" && h.RestoreOfRequestID != nil {
					restoredSet[*h.RestoreOfRequestID] = true
				}
				if h.Action == "delete" && h.Project == project && h.PlotNumber == plotNumber && h.Form == form {
					parsedList = append(parsedList, h)
				}
			}
			if err := errors.Join(rows.Err(), rows.Close()); err != nil {
				return nil, err
			}
			entries := make([]DeletedTwoPageVegetationEntry, 0, len(parsedList))
			for _, h := range parsedList {
				layer := ""
				if h.DeletedRow != nil && len(h.Columns) > 0 {
					layer = extractVegTextFromRow(h.Columns, *h.DeletedRow, "Layer")
				}
				entries = append(entries, DeletedTwoPageVegetationEntry{
					DeleteRequestID: h.RequestID,
					PlotNumber:      plotNumber,
					Form:            form,
					DeletedID:       h.ID,
					Species:         h.Species,
					Layer:           layer,
					DeletedBy:       h.Actor,
					DeletedAt:       h.EditWhen,
					Restored:        restoredSet[h.RequestID],
				})
			}
			return entries, nil
		})
	})
}

func (s *TwoPageVegetationService) CreateRow(ctx context.Context, contextID string, req CreateTwoPageVegetationRequest) (CreateTwoPageVegetationResult, error) {
	if err := s.require(ctx, true); err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	return CreateTwoPageVegetationRow(s.contexts, ctx, contextID, req)
}

func (s *TwoPageVegetationService) DeleteRow(ctx context.Context, contextID string, req DeleteTwoPageVegetationRequest) (DeleteTwoPageVegetationResult, error) {
	if err := s.require(ctx, true); err != nil {
		return DeleteTwoPageVegetationResult{}, err
	}
	return DeleteTwoPageVegetationRow(s.contexts, ctx, contextID, req)
}

func (s *TwoPageVegetationService) RestoreRow(ctx context.Context, contextID string, req RestoreTwoPageVegetationRequest) (RestoreTwoPageVegetationResult, error) {
	if err := s.require(ctx, true); err != nil {
		return RestoreTwoPageVegetationResult{}, err
	}
	return RestoreTwoPageVegetationRow(s.contexts, ctx, contextID, req)
}

func (s *TwoPageVegetationService) ListDeletedRows(ctx context.Context, contextID, plot, form string) ([]DeletedTwoPageVegetationEntry, error) {
	if err := s.require(ctx, false); err != nil {
		return nil, err
	}
	return ListTwoPageVegetationDeletedRows(s.contexts, ctx, contextID, plot, form)
}
