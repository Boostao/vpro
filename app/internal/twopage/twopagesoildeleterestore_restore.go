package twopage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// RestoreTwoPageSoilHorizon restores a previously deleted <Project>_Humus or <Project>_Mineral
// horizon from __VPRO_TwoPageSoilHistory inside an atomic BEGIN IMMEDIATE transaction,
// verifying permanent reservation in __VPRO_ChildIdentity, marking deletion audits Restored (-1),
// and appending a restoration receipt to __VPRO_TwoPageSoilHistory.
func RestoreTwoPageSoilHorizon(s *vprocore.ContextService, ctx context.Context, contextID string, req RestoreTwoPageSoilHorizonRequest) (RestoreTwoPageSoilHorizonResult, error) {
	if s == nil {
		return RestoreTwoPageSoilHorizonResult{}, errors.New("two-page soil context service is unavailable")
	}
	form, kind, err := normalizeTwoPageSoilForm(req.Form)
	if err != nil {
		return RestoreTwoPageSoilHorizonResult{}, err
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return RestoreTwoPageSoilHorizonResult{}, errors.New("soil horizon restoration requires a literal valid plotNumber")
	}
	deleteReqID := strings.TrimSpace(req.DeleteRequestID)
	if !vprocore.SiviDeletionUUID.MatchString(deleteReqID) {
		return RestoreTwoPageSoilHorizonResult{}, errors.New("deleteRequestId must be a lowercase UUIDv4")
	}
	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" {
		requestID, err = newUUIDv4()
		if err != nil {
			return RestoreTwoPageSoilHorizonResult{}, err
		}
	} else if !vprocore.SiviDeletionUUID.MatchString(requestID) {
		return RestoreTwoPageSoilHorizonResult{}, errors.New("requestId must be a lowercase UUIDv4")
	}
	if requestID == deleteReqID {
		return RestoreTwoPageSoilHorizonResult{}, errors.New("restoration requestId must differ from deleteRequestId")
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (RestoreTwoPageSoilHorizonResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return RestoreTwoPageSoilHorizonResult{}, err
		}
		owner := plots.Projects.Sqlite
		actor := strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		strength := plots.AuditStrength

		var out RestoreTwoPageSoilHorizonResult
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
				if err := vprocore.RequireRollbackJournalReadLock(ctx, tx, suAlias, "two-page soil restoration SU check"); err != nil {
					return err
				}
			}
			if err := twoPageSoilWriterSelectedParent(ctx, tx, owner, suAlias, req.PlotNumber); err != nil {
				return err
			}

			project := owner.Selection.Project
			tableName := project + "_" + kind
			quotedTbl := vprocore.QuoteHeaderIdentifier(tableName)
			quotedAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")

			if err := vprocore.ChildParent(tx, project, req.PlotNumber); err != nil {
				return err
			}

			var hasHistory bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, twoPageSoilHistoryTable).Scan(&hasHistory); err != nil {
				return err
			}
			if !hasHistory {
				return errors.New("no two-page soil deletion history exists in this project")
			}

			// Read all history entries to check idempotent replay and ensure deletion wasn't already restored.
			hRows, err := tx.QueryContext(ctx, `SELECT RequestID, Proposal FROM "__VPRO_TwoPageSoilHistory" ORDER BY rowid`)
			if err != nil {
				return err
			}
			var targetDeletion *twoPageSoilHistory
			alreadyConsumed := false
			var replayRestore *twoPageSoilHistory

			for hRows.Next() {
				var rID, rawProp string
				if err := hRows.Scan(&rID, &rawProp); err != nil {
					hRows.Close()
					return err
				}
				parsed, pErr := unmarshalAnyTwoPageSoilHistory(rawProp)
				if pErr != nil {
					hRows.Close()
					return pErr
				}
				if rID == requestID {
					if parsed.Action != "restore" || parsed.RestoreOfRequestID == nil || *parsed.RestoreOfRequestID != deleteReqID {
						hRows.Close()
						return errors.New("requestId already belongs to another soil history operation")
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

			if replayRestore != nil && targetDeletion != nil {
				hz := extractHorizonFromRow(targetDeletion.Request.Original.Records.Columns, *targetDeletion.DeletedRow)
				out = RestoreTwoPageSoilHorizonResult{
					RequestID:       requestID,
					DeleteRequestID: deleteReqID,
					ContextID:       contextID,
					Project:         project,
					PlotNumber:      req.PlotNumber,
					Form:            form,
					Kind:            kind,
					RestoredID:      *replayRestore.DeletedID,
					RestoredRowID:   *replayRestore.RestoredRowID,
					Horizon:         hz,
					AuditRowCount:   len(replayRestore.Audits),
					EditWhen:        replayRestore.EditWhen,
					Replayed:        true,
				}
				return nil
			}

			if targetDeletion == nil || targetDeletion.DeletedRow == nil || targetDeletion.DeletedID == nil {
				return fmt.Errorf("soil deletion receipt %s not found", deleteReqID)
			}
			if alreadyConsumed {
				return fmt.Errorf("soil deletion receipt %s has already been restored", deleteReqID)
			}
			if targetDeletion.Request.Original == nil ||
				targetDeletion.Request.Original.Project != project ||
				targetDeletion.Request.Original.Plot != req.PlotNumber ||
				targetDeletion.Request.Original.Form != form {
				return errors.New("soil deletion receipt belongs to another project, plot, or soil form")
			}

			restoredID := *targetDeletion.DeletedID
			// Verify ID is not currently occupied (table-wide for positive IDs, plot-scoped for legacy ID <= 0).
			var occupied int
			if restoredID > 0 {
				if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+quotedTbl+` WHERE "ID" = ?`, restoredID).Scan(&occupied); err != nil {
					return err
				}
			} else {
				if err := tx.QueryRowContext(ctx,
					`SELECT COUNT(*) FROM `+quotedTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`,
					req.PlotNumber, restoredID,
				).Scan(&occupied); err != nil {
					return err
				}
			}
			if occupied != 0 {
				return fmt.Errorf("cannot restore %s horizon ID %d because that ID is already occupied", kind, restoredID)
			}

			// Ensure permanent reservation in __VPRO_ChildIdentity remains intact!
			if restoredID >= 0 {
				var reserved int
				if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE "ChildTable" = ? AND "ID" = ?`,
					quotedTbl, restoredID).Scan(&reserved); err != nil {
					return err
				}
				if reserved != 1 {
					return fmt.Errorf("%s horizon ID %d lost its permanent reservation in __VPRO_ChildIdentity", kind, restoredID)
				}
			}

			beforeRecords, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "main", tableName, "PlotNumber", req.PlotNumber, "")
			if err != nil {
				return err
			}
			origCols := targetDeletion.Request.Original.Records.Columns
			if len(beforeRecords.Columns) != len(origCols) {
				return errors.New("soil table schema changed since deletion; restoration refused")
			}

			quotedCols := make([]string, len(origCols))
			marks := make([]string, len(origCols))
			args := make([]any, len(origCols))
			for i, col := range origCols {
				quotedCols[i] = vprocore.QuoteHeaderIdentifier(col.Name)
				marks[i] = "?"
				val, mErr := vprocore.MetadataCellValue(targetDeletion.DeletedRow.Cells[i])
				if mErr != nil {
					return mErr
				}
				args[i] = val
			}
			insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)", quotedTbl, strings.Join(quotedCols, ", "), strings.Join(marks, ", "))
			insRes, err := tx.ExecContext(ctx, insSQL, args...)
			if err != nil {
				return err
			}
			newRowID, err := insRes.LastInsertId()
			if err != nil {
				return err
			}

			// Mark original deletion audit rows with Restore = -1 (Access BOOLEAN true = -1) AND log restoration audit!
			for _, delAudit := range targetDeletion.Audits {
				if aRowID, pErr := strconv.ParseInt(delAudit.RowID, 10, 64); pErr == nil {
					if _, err := tx.ExecContext(ctx, `UPDATE `+quotedAudit+` SET "Restore" = -1 WHERE rowid = ? AND "PlotNumber" = ?`, aRowID, req.PlotNumber); err != nil {
						return fmt.Errorf("mark deletion audit restored: %w", err) // ENG-GO-004
					}
				}
			}

			now := time.Now().Format("2006-01-02 15:04:05")
			hz := extractHorizonFromRow(origCols, *targetDeletion.DeletedRow)
			var restoreAudits []vprocore.AuditEntry
			aIns, err := tx.ExecContext(ctx, `INSERT INTO `+quotedAudit+
				` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
				project, actor, req.PlotNumber, "_"+kind, "Horizon", now, nil, hz, restoredID)
			if err != nil {
				return err
			}
			aRowID, _ := aIns.LastInsertId()
			ids, _ := vprocore.AuditRowIDs([]string{strconv.FormatInt(aRowID, 10)})
			recs, _ := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
			if len(recs) == 1 {
				restoreAudits = append(restoreAudits, recs[0])
			}

			afterRecords, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "main", tableName, "PlotNumber", req.PlotNumber, "")
			if err != nil {
				return err
			}

			restoredRowIDStr := strconv.FormatInt(newRowID, 10)
			delIDCopy := restoredID
			delReqCopy := deleteReqID
			history := twoPageSoilHistory{
				Request: twoPageSoilRequest{
					RequestID: requestID,
					Original: &twoPageSoilOriginal{
						ContextID:    contextID,
						Project:      project,
						Plot:         req.PlotNumber,
						Form:         form,
						RecordSource: "Usys" + kind,
						Table:        tableName,
						Records:      beforeRecords,
					},
					Edits: []twoPageSoilEdit{},
				},
				Committed:          afterRecords,
				Actor:              actor,
				AuditStrength:      strength,
				EditWhen:           now,
				Audits:             restoreAudits,
				Action:             "restore",
				DeletedID:          &delIDCopy,
				RestoreOfRequestID: &delReqCopy,
				RestoredRowID:      &restoredRowIDStr,
			}
			proposalJSON, err := marshalDeleteRestoreHistory(history)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO "__VPRO_TwoPageSoilHistory" VALUES(?,?,?)`,
				requestID, now, proposalJSON); err != nil {
				return err
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}

			out = RestoreTwoPageSoilHorizonResult{
				RequestID:       requestID,
				DeleteRequestID: deleteReqID,
				ContextID:       contextID,
				Project:         project,
				PlotNumber:      req.PlotNumber,
				Form:            form,
				Kind:            kind,
				RestoredID:      restoredID,
				RestoredRowID:   restoredRowIDStr,
				Horizon:         hz,
				AuditRowCount:   len(restoreAudits),
				EditWhen:        now,
				Replayed:        false,
			}
			return nil
		})
		if wErr != nil {
			return RestoreTwoPageSoilHorizonResult{}, wErr
		}
		return out, nil
	})
}

// ListTwoPageSoilDeletedHorizons lists deleted horizons recorded in __VPRO_TwoPageSoilHistory
// for the specified plotNumber and soil form (SoilHumusXL or SoilMineralXL).
func ListTwoPageSoilDeletedHorizons(s *vprocore.ContextService, ctx context.Context, contextID, plotNumber, formReq string) ([]DeletedTwoPageSoilHorizonEntry, error) {
	if s == nil {
		return nil, errors.New("two-page soil context service is unavailable")
	}
	form, kind, err := normalizeTwoPageSoilForm(formReq)
	if err != nil {
		return nil, err
	}
	if plotNumber == "" || !utf8.ValidString(plotNumber) || strings.ContainsRune(plotNumber, 0) {
		return nil, errors.New("plotNumber must be a valid literal string")
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (entries []DeletedTwoPageSoilHorizonEntry, resultErr error) {
		owner := plots.Projects.Sqlite
		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return nil, err
		}
		defer owner.Mu.Unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		if err := twoPageSoilSelectedParent(ctx, owner, plotNumber); err != nil {
			return nil, err
		}

		var exists bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM project.sqlite_master WHERE type='table' AND name=?)`, twoPageSoilHistoryTable).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			if err := tx.Commit(); err != nil {
				return nil, err
			}
			return []DeletedTwoPageSoilHorizonEntry{}, nil
		}

		rows, err := tx.QueryContext(ctx, `SELECT RequestID, Proposal FROM project."__VPRO_TwoPageSoilHistory" ORDER BY rowid DESC`)
		if err != nil {
			return nil, err
		}
		var parsedList []twoPageSoilHistory
		restoredSet := map[string]bool{}
		for rows.Next() {
			var reqID, raw string
			if err := rows.Scan(&reqID, &raw); err != nil {
				rows.Close()
				return nil, err
			}
			h, pErr := unmarshalAnyTwoPageSoilHistory(raw)
			if pErr != nil {
				rows.Close()
				return nil, pErr
			}
			if h.Action == "restore" && h.RestoreOfRequestID != nil {
				restoredSet[*h.RestoreOfRequestID] = true
			}
			if h.Action == "delete" && h.Request.Original != nil &&
				h.Request.Original.Project == owner.Selection.Project &&
				h.Request.Original.Plot == plotNumber &&
				h.Request.Original.Form == form {
				parsedList = append(parsedList, h)
			}
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}

		entries = make([]DeletedTwoPageSoilHorizonEntry, 0, len(parsedList))
		for _, h := range parsedList {
			if h.DeletedID == nil || h.DeletedRow == nil {
				continue
			}
			cols := h.Request.Original.Records.Columns
			hz := extractHorizonFromRow(cols, *h.DeletedRow)
			upper := extractFloatFromRow(cols, *h.DeletedRow, "UpperDepth")
			lower := extractFloatFromRow(cols, *h.DeletedRow, "LowerDepth")
			entries = append(entries, DeletedTwoPageSoilHorizonEntry{
				DeleteRequestID: h.Request.RequestID,
				PlotNumber:      plotNumber,
				Form:            form,
				Kind:            kind,
				DeletedID:       *h.DeletedID,
				Horizon:         hz,
				UpperDepth:      upper,
				LowerDepth:      lower,
				DeletedBy:       h.Actor,
				DeletedAt:       h.EditWhen,
				Restored:        restoredSet[h.Request.RequestID],
			})
		}
		return entries, nil
	})
}

func extractHorizonFromRow(cols []vprocore.ProjectMetadataColumn, row vprocore.ProjectMetadataRow) string {
	for i, c := range cols {
		if c.Name == "Horizon" && i < len(row.Cells) && row.Cells[i].Text != nil {
			return *row.Cells[i].Text
		}
	}
	return ""
}

func extractFloatFromRow(cols []vprocore.ProjectMetadataColumn, row vprocore.ProjectMetadataRow, colName string) *float64 {
	for i, c := range cols {
		if c.Name == colName && i < len(row.Cells) && row.Cells[i].Real != nil {
			v := *row.Cells[i].Real
			return &v
		}
	}
	return nil
}

func (s *TwoPageSoilService) DeleteHorizon(ctx context.Context, contextID string, req DeleteTwoPageSoilHorizonRequest) (DeleteTwoPageSoilHorizonResult, error) {
	if err := s.require(ctx, true); err != nil {
		return DeleteTwoPageSoilHorizonResult{}, err
	}
	return DeleteTwoPageSoilHorizon(s.contexts, ctx, contextID, req)
}

func (s *TwoPageSoilService) RestoreHorizon(ctx context.Context, contextID string, req RestoreTwoPageSoilHorizonRequest) (RestoreTwoPageSoilHorizonResult, error) {
	if err := s.require(ctx, true); err != nil {
		return RestoreTwoPageSoilHorizonResult{}, err
	}
	return RestoreTwoPageSoilHorizon(s.contexts, ctx, contextID, req)
}
