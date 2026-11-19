package twopage

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
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

type DeleteTwoPageSoilHorizonRequest struct {
	RequestID  string `json:"requestId,omitempty"`
	PlotNumber string `json:"plotNumber"`
	Form       string `json:"form"`
	ID         int64  `json:"id"`
	RowID      string `json:"rowId,omitempty"`
}

func (r *DeleteTwoPageSoilHorizonRequest) UnmarshalJSON(data []byte) error {
	type plain DeleteTwoPageSoilHorizonRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DeleteTwoPageSoilHorizonResult struct {
	RequestID        string `json:"requestId"`
	ContextID        string `json:"contextId"`
	Project          string `json:"project"`
	PlotNumber       string `json:"plotNumber"`
	Form             string `json:"form"`
	Kind             string `json:"kind"`
	DeletedID        int64  `json:"deletedId"`
	Horizon          string `json:"horizon"`
	ReservedInLedger bool   `json:"reservedInLedger"`
	AuditRowCount    int    `json:"auditRowCount"`
	EditWhen         string `json:"editWhen"`
	Replayed         bool   `json:"replayed"`
}

type DeletedTwoPageSoilHorizonEntry struct {
	DeleteRequestID string   `json:"deleteRequestId"`
	PlotNumber      string   `json:"plotNumber"`
	Form            string   `json:"form"`
	Kind            string   `json:"kind"`
	DeletedID       int64    `json:"deletedId"`
	Horizon         string   `json:"horizon"`
	UpperDepth      *float64 `json:"upperDepth,omitempty"`
	LowerDepth      *float64 `json:"lowerDepth,omitempty"`
	DeletedBy       string   `json:"deletedBy"`
	DeletedAt       string   `json:"deletedAt"`
	Restored        bool     `json:"restored"`
}

type RestoreTwoPageSoilHorizonRequest struct {
	RequestID       string `json:"requestId,omitempty"`
	PlotNumber      string `json:"plotNumber"`
	Form            string `json:"form"`
	DeleteRequestID string `json:"deleteRequestId"`
}

func (r *RestoreTwoPageSoilHorizonRequest) UnmarshalJSON(data []byte) error {
	type plain RestoreTwoPageSoilHorizonRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type RestoreTwoPageSoilHorizonResult struct {
	RequestID       string `json:"requestId"`
	DeleteRequestID string `json:"deleteRequestId"`
	ContextID       string `json:"contextId"`
	Project         string `json:"project"`
	PlotNumber      string `json:"plotNumber"`
	Form            string `json:"form"`
	Kind            string `json:"kind"`
	RestoredID      int64  `json:"restoredId"`
	RestoredRowID   string `json:"restoredRowId"`
	Horizon         string `json:"horizon"`
	AuditRowCount   int    `json:"auditRowCount"`
	EditWhen        string `json:"editWhen"`
	Replayed        bool   `json:"replayed"`
}

func newUUIDv4() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

func normalizeTwoPageSoilForm(raw string) (form, kind string, err error) {
	switch strings.TrimSpace(raw) {
	case "SoilHumusXL", "Humus":
		return "SoilHumusXL", "Humus", nil
	case "SoilMineralXL", "Mineral":
		return "SoilMineralXL", "Mineral", nil
	default:
		return "", "", fmt.Errorf("unsupported two-page soil form %q (expected SoilHumusXL or SoilMineralXL)", raw)
	}
}

func validateTwoPageSoilDeleteRestoreHistory(ctx context.Context, history twoPageSoilHistory) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if !vprocore.SiviDeletionUUID.MatchString(history.Request.RequestID) {
		return errors.New("two-page soil delete/restore history requires a lowercase UUIDv4 requestId")
	}
	if history.Request.Original == nil || history.Actor == "" || history.AuditStrength < 0 || history.AuditStrength > 3 {
		return errors.New("two-page soil delete/restore history lacks required original or actor provenance")
	}
	if _, err := time.Parse("2006-01-02 15:04:05", history.EditWhen); err != nil {
		return fmt.Errorf("two-page soil delete/restore history timestamp: %w", err)
	}
	switch history.Action {
	case "delete":
		if history.DeletedID == nil || history.DeletedRow == nil || len(history.DeletedRow.Cells) != len(history.Committed.Columns) {
			return errors.New("two-page soil delete history lacks complete deleted row or ID")
		}
	case "restore":
		if history.DeletedID == nil || history.RestoreOfRequestID == nil || !vprocore.SiviDeletionUUID.MatchString(*history.RestoreOfRequestID) || history.RestoredRowID == nil {
			return errors.New("two-page soil restore history lacks source deletion UUID or restored row ID")
		}
	default:
		return fmt.Errorf("unsupported two-page soil history action %q", history.Action)
	}
	return nil
}

func unmarshalAnyTwoPageSoilHistory(raw string) (twoPageSoilHistory, error) {
	// Note: twoPageSoilRequest has custom UnmarshalJSON requiring non-empty edits when Horizon is nil;
	// bypass twoPageSoilRequest.UnmarshalJSON for delete/restore entries where Edits is empty.
	var probe struct {
		Action string `json:"Action"`
	}
	if err := json.Unmarshal([]byte(raw), &probe); err != nil {
		return twoPageSoilHistory{}, err
	}
	if probe.Action == "delete" || probe.Action == "restore" {
		type plainReq struct {
			RequestID string               `json:"requestId"`
			Original  *twoPageSoilOriginal `json:"original"`
			Edits     []twoPageSoilEdit    `json:"edits"`
			Horizon   *string              `json:"horizon,omitempty"`
		}
		var envelope struct {
			Request            plainReq                      `json:"Request"`
			Committed          vprocore.ProjectMetadataTable `json:"Committed"`
			Actor              string                        `json:"Actor"`
			AuditStrength      int                           `json:"AuditStrength"`
			EditWhen           string                        `json:"EditWhen"`
			Audits             []vprocore.AuditEntry         `json:"Audits"`
			CreatedRowID       *string                       `json:"CreatedRowID,omitempty"`
			Action             string                        `json:"Action,omitempty"`
			DeletedID          *int64                        `json:"DeletedID,omitempty"`
			DeletedRow         *vprocore.ProjectMetadataRow  `json:"DeletedRow,omitempty"`
			RestoreOfRequestID *string                       `json:"RestoreOfRequestID,omitempty"`
			RestoredRowID      *string                       `json:"RestoredRowID,omitempty"`
		}
		if err := json.Unmarshal([]byte(raw), &envelope); err != nil {
			return twoPageSoilHistory{}, err
		}
		return twoPageSoilHistory{
			Request: twoPageSoilRequest{
				RequestID: envelope.Request.RequestID,
				Original:  envelope.Request.Original,
				Edits:     envelope.Request.Edits,
				Horizon:   envelope.Request.Horizon,
			},
			Committed:          envelope.Committed,
			Actor:              envelope.Actor,
			AuditStrength:      envelope.AuditStrength,
			EditWhen:           envelope.EditWhen,
			Audits:             envelope.Audits,
			CreatedRowID:       envelope.CreatedRowID,
			Action:             envelope.Action,
			DeletedID:          envelope.DeletedID,
			DeletedRow:         envelope.DeletedRow,
			RestoreOfRequestID: envelope.RestoreOfRequestID,
			RestoredRowID:      envelope.RestoredRowID,
		}, nil
	}
	var h twoPageSoilHistory
	if err := json.Unmarshal([]byte(raw), &h); err != nil {
		return twoPageSoilHistory{}, err
	}
	return h, nil
}

func marshalDeleteRestoreHistory(h twoPageSoilHistory) (string, error) {
	data, err := json.Marshal(h)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// DeleteTwoPageSoilHorizon deletes an owned <Project>_Humus or <Project>_Mineral row
// inside a single BEGIN IMMEDIATE transaction, permanently reserving its ID in
// __VPRO_ChildIdentity so it is never reused by new horizon creations, and recording
// full <Project>_Audit and __VPRO_TwoPageSoilHistory provenance.
func DeleteTwoPageSoilHorizon(s *vprocore.ContextService, ctx context.Context, contextID string, req DeleteTwoPageSoilHorizonRequest) (DeleteTwoPageSoilHorizonResult, error) {
	if s == nil {
		return DeleteTwoPageSoilHorizonResult{}, errors.New("two-page soil context service is unavailable")
	}
	form, kind, err := normalizeTwoPageSoilForm(req.Form)
	if err != nil {
		return DeleteTwoPageSoilHorizonResult{}, err
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return DeleteTwoPageSoilHorizonResult{}, errors.New("soil horizon deletion requires a literal valid plotNumber")
	}
	if err := vprocore.ValidateChildPhysicalText("PlotNumber", req.PlotNumber, 7); err != nil {
		return DeleteTwoPageSoilHorizonResult{}, err
	}
	if req.ID < -2147483648 || req.ID > 2147483647 {
		return DeleteTwoPageSoilHorizonResult{}, errors.New("soil horizon deletion requires a record ID")
	}
	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" {
		requestID, err = newUUIDv4()
		if err != nil {
			return DeleteTwoPageSoilHorizonResult{}, err
		}
	} else if !vprocore.SiviDeletionUUID.MatchString(requestID) {
		return DeleteTwoPageSoilHorizonResult{}, errors.New("requestId must be a lowercase UUIDv4")
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (DeleteTwoPageSoilHorizonResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return DeleteTwoPageSoilHorizonResult{}, err
		}
		owner := plots.Projects.Sqlite
		actor := strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		strength := plots.AuditStrength

		var out DeleteTwoPageSoilHorizonResult
		wErr := owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			suAlias, err := sourceform.SourceParentWriterSU(ctx, conn, owner)
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
				if err := vprocore.RequireRollbackJournalReadLock(ctx, tx, suAlias, "two-page soil deletion SU check"); err != nil {
					return err
				}
			}
			if err := twoPageSoilWriterSelectedParent(ctx, tx, owner, suAlias, req.PlotNumber); err != nil {
				return err
			}

			project := owner.Selection.Project
			tableName := project + "_" + kind
			quotedTbl := vprocore.QuoteHeaderIdentifier(tableName)

			// Check idempotent replay in __VPRO_TwoPageSoilHistory if table exists.
			var hasHistory bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, twoPageSoilHistoryTable).Scan(&hasHistory); err != nil {
				return err
			}
			if hasHistory {
				var rawProposal string
				rErr := tx.QueryRowContext(ctx, `SELECT Proposal FROM "__VPRO_TwoPageSoilHistory" WHERE RequestID = ?`, requestID).Scan(&rawProposal)
				if rErr == nil {
					prev, uErr := unmarshalAnyTwoPageSoilHistory(rawProposal)
					if uErr != nil {
						return uErr
					}
					if prev.Action != "delete" || prev.DeletedID == nil || *prev.DeletedID != req.ID ||
						prev.Request.Original == nil || prev.Request.Original.Plot != req.PlotNumber || prev.Request.Original.Form != form {
						return errors.New("requestId already belongs to a different two-page soil history entry")
					}
					hz := extractHorizonFromRow(prev.Committed.Columns, *prev.DeletedRow)
					out = DeleteTwoPageSoilHorizonResult{
						RequestID:        requestID,
						ContextID:        contextID,
						Project:          project,
						PlotNumber:       req.PlotNumber,
						Form:             form,
						Kind:             kind,
						DeletedID:        req.ID,
						Horizon:          hz,
						ReservedInLedger: true,
						AuditRowCount:    len(prev.Audits),
						EditWhen:         prev.EditWhen,
						Replayed:         true,
					}
					return nil
				} else if !errors.Is(rErr, sql.ErrNoRows) {
					return rErr
				}
			}

			// Verify 1:1 parent in Env and Admin.
			if err := vprocore.ChildParent(tx, project, req.PlotNumber); err != nil {
				return err
			}

			// Read plot rows before deletion.
			beforeRecords, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "main", tableName, "PlotNumber", req.PlotNumber, "")
			if err != nil {
				return err
			}
			colMap, err := vprocore.SiteUnitTransferColumns(beforeRecords, "ID", "PlotNumber", "Horizon")
			if err != nil {
				return err
			}

			targetIdx := -1
			idText := strconv.FormatInt(req.ID, 10)
			for i, r := range beforeRecords.Rows {
				if sourceform.SourceIdentityCellMatches(r.Cells[colMap["ID"]], idText) {
					if targetIdx >= 0 {
						return fmt.Errorf("ambiguous %s ID %d in plot %s; deletion refused", kind, req.ID, req.PlotNumber)
					}
					targetIdx = i
				}
			}
			if targetIdx < 0 {
				return fmt.Errorf("%s horizon ID %d not found on plot %s", kind, req.ID, req.PlotNumber)
			}
			deletedRow := beforeRecords.Rows[targetIdx]
			if strings.TrimSpace(req.RowID) != "" && deletedRow.RowID != strings.TrimSpace(req.RowID) {
				return fmt.Errorf("%s horizon record changed on disk (expected %s, found %s); reload before deleting", kind, req.RowID, deletedRow.RowID)
			}

			// Ensure __VPRO_ChildIdentity exists and permanently reserve all existing + deleted IDs!
			if err := vprocore.EnsureChildIdentityTable(ctx, tx); err != nil {
				return err
			}
			if err := vprocore.SeedChildIdentityFromTable(ctx, tx, quotedTbl, false); err != nil {
				return err
			}
			if req.ID >= 0 {
				if err := vprocore.ReserveChildID(ctx, tx, quotedTbl, req.ID); err != nil {
					return err
				}
			}

			// Delete the exact physical row.
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
				return errors.New("two-page soil deletion did not affect exactly 1 row")
			}

			now := time.Now().Format("2006-01-02 15:04:05")
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
				// Always record deletion audit for non-null cells so full audit trail exists.
				effectiveStrength := strength
				if effectiveStrength < 3 {
					effectiveStrength = 3
				}
				tracked, aErr := vprocore.AuditChildFieldsTracked(tx, project, kind, req.PlotNumber, req.ID,
					[]vprocore.ChildField{{Column: col.Name}}, []any{oldVal}, []any{nil}, actor, effectiveStrength, now)
				if aErr != nil {
					return aErr
				}
				for _, tr := range tracked {
					ids, _ := vprocore.AuditRowIDs([]string{tr.RowID})
					recs, sErr := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
					if sErr != nil || len(recs) != 1 {
						return errors.Join(sErr, errors.New("deleted soil audit lookup failed"))
					}
					auditEntries = append(auditEntries, recs[0])
				}
			}
			// If every non-identity cell was NULL, record at least Horizon/ID deletion audit row.
			if len(auditEntries) == 0 {
				aRowID, aErr := vprocore.RecordAudit(ctx, tx, vprocore.AuditWriteEntry{
					Project:    project,
					User:       actor,
					PlotNumber: &req.PlotNumber,
					Table:      "_" + kind,
					EditField:  vprocore.AuditString("Horizon"),
					EditWhen:   now,
					BeforeEdit: strconv.FormatInt(req.ID, 10),
					ID:         &req.ID,
				})
				if aErr != nil {
					return aErr
				}
				ids, _ := vprocore.AuditRowIDs([]string{strconv.FormatInt(aRowID, 10)})
				recs, _ := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
				if len(recs) == 1 {
					auditEntries = append(auditEntries, recs[0])
				}
			}

			afterRecords, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "main", tableName, "PlotNumber", req.PlotNumber, "")
			if err != nil {
				return err
			}

			delIDCopy := req.ID
			delRowCopy := deletedRow
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
				Committed:     afterRecords,
				Actor:         actor,
				AuditStrength: strength,
				EditWhen:      now,
				Audits:        auditEntries,
				Action:        "delete",
				DeletedID:     &delIDCopy,
				DeletedRow:    &delRowCopy,
			}
			proposalJSON, err := marshalDeleteRestoreHistory(history)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_TwoPageSoilHistory" (
				RequestID TEXT NOT NULL PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`); err != nil {
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

			hz := extractHorizonFromRow(beforeRecords.Columns, deletedRow)
			out = DeleteTwoPageSoilHorizonResult{
				RequestID:        requestID,
				ContextID:        contextID,
				Project:          project,
				PlotNumber:       req.PlotNumber,
				Form:             form,
				Kind:             kind,
				DeletedID:        req.ID,
				Horizon:          hz,
				ReservedInLedger: req.ID >= 0,
				AuditRowCount:    len(auditEntries),
				EditWhen:         now,
				Replayed:         false,
			}
			return nil
		})
		if wErr != nil {
			return DeleteTwoPageSoilHorizonResult{}, wErr
		}
		return out, nil
	})
}
