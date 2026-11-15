package twopage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const twoPageVegetationLifecycleHistoryTable = "__VPRO_TwoPageVegetationLifecycleHistory"

type CreateTwoPageVegetationRequest struct {
	RequestID  string              `json:"requestId,omitempty"`
	PlotNumber string              `json:"plotNumber"`
	Form       string              `json:"form"`
	Species    string              `json:"species"`
	Layer      *string             `json:"layer,omitempty"`
	Collected  *string             `json:"collected,omitempty"`
	Decision   string              `json:"decision,omitempty"`
	Entered    *string             `json:"entered,omitempty"`
	Selected   *string             `json:"selected,omitempty"`
	Covers     map[string]*float64 `json:"covers"`
}

func (r *CreateTwoPageVegetationRequest) UnmarshalJSON(data []byte) error {
	type plain CreateTwoPageVegetationRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type CreateTwoPageVegetationResult struct {
	RequestID        string `json:"requestId"`
	ContextID        string `json:"contextId"`
	Project          string `json:"project"`
	PlotNumber       string `json:"plotNumber"`
	Form             string `json:"form"`
	RowID            string `json:"rowId"`
	ID               int64  `json:"id"`
	Species          string `json:"species"`
	ReservedInLedger bool   `json:"reservedInLedger"`
	AuditRowCount    int    `json:"auditRowCount"`
	EditWhen         string `json:"editWhen"`
	Replayed         bool   `json:"replayed"`
}

type DeleteTwoPageVegetationRequest struct {
	RequestID  string `json:"requestId,omitempty"`
	PlotNumber string `json:"plotNumber"`
	Form       string `json:"form"`
	ID         int64  `json:"id"`
	RowID      string `json:"rowId,omitempty"`
}

func (r *DeleteTwoPageVegetationRequest) UnmarshalJSON(data []byte) error {
	type plain DeleteTwoPageVegetationRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DeleteTwoPageVegetationResult struct {
	RequestID        string `json:"requestId"`
	ContextID        string `json:"contextId"`
	Project          string `json:"project"`
	PlotNumber       string `json:"plotNumber"`
	Form             string `json:"form"`
	DeletedID        int64  `json:"deletedId"`
	Species          string `json:"species"`
	ReservedInLedger bool   `json:"reservedInLedger"`
	AuditRowCount    int    `json:"auditRowCount"`
	EditWhen         string `json:"editWhen"`
	Replayed         bool   `json:"replayed"`
}

type DeletedTwoPageVegetationEntry struct {
	DeleteRequestID string `json:"deleteRequestId"`
	PlotNumber      string `json:"plotNumber"`
	Form            string `json:"form"`
	DeletedID       int64  `json:"deletedId"`
	Species         string `json:"species"`
	Layer           string `json:"layer"`
	DeletedBy       string `json:"deletedBy"`
	DeletedAt       string `json:"deletedAt"`
	Restored        bool   `json:"restored"`
}

type RestoreTwoPageVegetationRequest struct {
	RequestID       string `json:"requestId,omitempty"`
	PlotNumber      string `json:"plotNumber"`
	Form            string `json:"form"`
	DeleteRequestID string `json:"deleteRequestId"`
}

func (r *RestoreTwoPageVegetationRequest) UnmarshalJSON(data []byte) error {
	type plain RestoreTwoPageVegetationRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type RestoreTwoPageVegetationResult struct {
	RequestID       string `json:"requestId"`
	DeleteRequestID string `json:"deleteRequestId"`
	ContextID       string `json:"contextId"`
	Project         string `json:"project"`
	PlotNumber      string `json:"plotNumber"`
	Form            string `json:"form"`
	RestoredID      int64  `json:"restoredId"`
	RestoredRowID   string `json:"restoredRowId"`
	Species         string `json:"species"`
	AuditRowCount   int    `json:"auditRowCount"`
	EditWhen        string `json:"editWhen"`
	Replayed        bool   `json:"replayed"`
}

type twoPageVegLifecycleHistory struct {
	RequestID          string                           `json:"requestId"`
	Action             string                           `json:"action"` // "create" | "delete" | "restore"
	ContextID          string                           `json:"contextId"`
	Project            string                           `json:"project"`
	PlotNumber         string                           `json:"plotNumber"`
	Form               string                           `json:"form"`
	ID                 int64                            `json:"id"`
	RowID              string                           `json:"rowId,omitempty"`
	Species            string                           `json:"species"`
	Actor              string                           `json:"actor"`
	AuditStrength      int                              `json:"auditStrength"`
	EditWhen           string                           `json:"editWhen"`
	Audits             []vprocore.AuditEntry            `json:"audits"`
	Columns            []vprocore.ProjectMetadataColumn `json:"columns,omitempty"`
	DeletedRow         *vprocore.ProjectMetadataRow     `json:"deletedRow,omitempty"`
	RestoreOfRequestID *string                          `json:"restoreOfRequestId,omitempty"`
}

func twoPageVegetationCreateCovers(form string) ([]string, error) {
	switch form {
	case "SubVegAXL_BC":
		return []string{"Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB"}, nil
	case "SubVegAXL":
		return []string{"Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB", "Cover5a", "Cover5b", "Cover5c"}, nil
	case "SubVegCXL":
		return []string{"Cover6"}, nil
	case "SubVegDXL":
		return []string{"Cover7", "Cover8", "Cover9"}, nil
	default:
		return nil, fmt.Errorf("two-page vegetation does not support source form %q", form)
	}
}

func normalizeTwoPageVegRequestID(raw string) (string, error) {
	requestID := strings.TrimSpace(raw)
	if requestID == "" {
		return newUUIDv4()
	}
	if !vprocore.SiviDeletionUUID.MatchString(requestID) {
		return "", errors.New("requestId must be a lowercase UUIDv4")
	}
	return requestID, nil
}

func extractVegTextFromRow(cols []vprocore.ProjectMetadataColumn, row vprocore.ProjectMetadataRow, name string) string {
	for i, c := range cols {
		if c.Name == name && i < len(row.Cells) && row.Cells[i].Text != nil {
			return *row.Cells[i].Text
		}
	}
	return ""
}

func reserveTwoPageVegChildIDs(ctx context.Context, tx *sql.Tx, quotedTbl, unquotedTbl string, extraID *int64) error {
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
		"ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable","ID"))`); err != nil {
		return err
	}
	idScan, err := tx.QueryContext(ctx, `SELECT "ID" FROM `+quotedTbl+` WHERE typeof("ID")='integer' AND "ID" > 0`)
	if err != nil {
		return err
	}
	var idsToReserve []int64
	for idScan.Next() {
		var v int64
		if err := idScan.Scan(&v); err != nil {
			idScan.Close()
			return err
		}
		idsToReserve = append(idsToReserve, v)
	}
	if err := errors.Join(idScan.Err(), idScan.Close()); err != nil {
		return err
	}
	if extraID != nil && *extraID >= 0 && !slices.Contains(idsToReserve, *extraID) {
		idsToReserve = append(idsToReserve, *extraID)
	}
	for _, v := range idsToReserve {
		if _, err := tx.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("ChildTable","ID") VALUES (?,?) ON CONFLICT DO NOTHING`,
			unquotedTbl, v); err != nil {
			return err
		}
	}
	return nil
}

// CreateTwoPageVegetationRow inserts a new <Project>_Veg row scoped to an active Two-Page form,
// validating positive/zero IEEE-754 SINGLE covers (< 100), allocating a monotonic signed32 ID,
// reserving it in __VPRO_ChildIdentity, and recording <Project>_Audit provenance.
func CreateTwoPageVegetationRow(s *vprocore.ContextService, ctx context.Context, contextID string, req CreateTwoPageVegetationRequest) (CreateTwoPageVegetationResult, error) {
	if s == nil {
		return CreateTwoPageVegetationResult{}, errors.New("two-page vegetation context service is unavailable")
	}
	if ctx == nil {
		return CreateTwoPageVegetationResult{}, errors.New("two-page vegetation creation requires a context")
	}
	if err := ctx.Err(); err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	allowedCols, err := twoPageVegetationCreateCovers(req.Form)
	if err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return CreateTwoPageVegetationResult{}, errors.New("two-page vegetation creation requires a literal valid plotNumber")
	}
	if err := vprocore.ValidateChildPhysicalText("PlotNumber", req.PlotNumber, 7); err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	if err := vprocore.ValidateVegetationSpeciesLookup(req.Species); err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	if err := vprocore.ValidateVegetationSpeciesDecision(vprocore.VegetationSpeciesUpdate{
		Form: req.Form, Value: req.Species, Decision: req.Decision, Entered: req.Entered, Selected: req.Selected,
	}); err != nil {
		return CreateTwoPageVegetationResult{}, err
	}
	if req.Layer != nil {
		if err := vprocore.ValidateChildPhysicalText("Veg.Layer", *req.Layer, 2); err != nil {
			return CreateTwoPageVegetationResult{}, err
		}
	}
	if req.Collected != nil {
		if err := vprocore.ValidateChildPhysicalText("Veg.Collected", *req.Collected, 1); err != nil {
			return CreateTwoPageVegetationResult{}, err
		}
	}
	allowedSet := make(map[string]bool, len(allowedCols))
	for _, col := range allowedCols {
		allowedSet[col] = true
	}
	if len(req.Covers) == 0 {
		return CreateTwoPageVegetationResult{}, fmt.Errorf("two-page vegetation creation requires at least one cover column for %s", req.Form)
	}
	hasNonNullCover := false
	coverKeys := make([]string, 0, len(req.Covers))
	for col, val := range req.Covers {
		if !allowedSet[col] {
			return CreateTwoPageVegetationResult{}, fmt.Errorf("vegetation cover %q is unavailable in two-page form %q", col, req.Form)
		}
		if err := vprocore.ValidateSingleCoverChange("Veg."+col, nil, val); err != nil {
			return CreateTwoPageVegetationResult{}, err
		}
		if val != nil {
			hasNonNullCover = true
		}
		coverKeys = append(coverKeys, col)
	}
	sort.Strings(coverKeys)
	if !hasNonNullCover {
		return CreateTwoPageVegetationResult{}, fmt.Errorf("two-page vegetation creation requires a non-NULL cover belonging to %s", req.Form)
	}
	requestID, err := normalizeTwoPageVegRequestID(req.RequestID)
	if err != nil {
		return CreateTwoPageVegetationResult{}, err
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (CreateTwoPageVegetationResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return CreateTwoPageVegetationResult{}, err
		}
		owner := plots.Projects.Sqlite
		actor := strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		strength := plots.AuditStrength

		var out CreateTwoPageVegetationResult
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
				if err := vprocore.RequireRollbackJournalReadLock(ctx, tx, suAlias, "two-page vegetation creation SU check"); err != nil {
					return err
				}
			}
			if err := twoPageChildWriterSelectedParent(ctx, tx, owner, suAlias, req.PlotNumber, "vegetation"); err != nil {
				return err
			}

			project := owner.Selection.Project
			tableName := project + "_Veg"
			quotedTbl := vprocore.QuoteHeaderIdentifier(tableName)

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
					if prev.Action != "create" || prev.Project != project || prev.PlotNumber != req.PlotNumber || prev.Form != req.Form || prev.Species != req.Species {
						return errors.New("requestId already belongs to a different two-page vegetation lifecycle operation")
					}
					out = CreateTwoPageVegetationResult{
						RequestID:        requestID,
						ContextID:        contextID,
						Project:          project,
						PlotNumber:       req.PlotNumber,
						Form:             req.Form,
						RowID:            prev.RowID,
						ID:               prev.ID,
						Species:          prev.Species,
						ReservedInLedger: prev.ID >= 0,
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
			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
				"ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable","ID"))`); err != nil {
				return err
			}
			newID, err := vprocore.AllocateChildID(tx, quotedTbl)
			if err != nil {
				return err
			}
			if err := reserveTwoPageVegChildIDs(ctx, tx, quotedTbl, tableName, &newID); err != nil {
				return err
			}

			insertCols := []string{`"PlotNumber"`, `"Species"`, `"ID"`, `"Flag"`}
			insertVals := []any{req.PlotNumber, req.Species, newID, int64(0)}
			auditFields := []vprocore.ChildField{{Column: "Species"}}
			beforeVals := []any{nil}
			afterVals := []any{req.Species}

			if req.Layer != nil {
				insertCols = append(insertCols, `"Layer"`)
				insertVals = append(insertVals, *req.Layer)
				auditFields = append(auditFields, vprocore.ChildField{Column: "Layer"})
				beforeVals = append(beforeVals, nil)
				afterVals = append(afterVals, *req.Layer)
			}
			if req.Collected != nil {
				insertCols = append(insertCols, `"Collected"`)
				insertVals = append(insertVals, *req.Collected)
				auditFields = append(auditFields, vprocore.ChildField{Column: "Collected"})
				beforeVals = append(beforeVals, nil)
				afterVals = append(afterVals, *req.Collected)
			}
			for _, col := range coverKeys {
				val := req.Covers[col]
				if val == nil {
					continue
				}
				stored := float64(float32(*val))
				insertCols = append(insertCols, vprocore.QuoteHeaderIdentifier(col))
				insertVals = append(insertVals, stored)
				auditFields = append(auditFields, vprocore.ChildField{Column: col})
				beforeVals = append(beforeVals, nil)
				afterVals = append(afterVals, stored)
			}

			marks := make([]string, len(insertCols))
			for i := range marks {
				marks[i] = "?"
			}
			insRes, err := tx.ExecContext(ctx, `INSERT INTO `+quotedTbl+` (`+strings.Join(insertCols, ",")+`) VALUES (`+strings.Join(marks, ",")+`)`, insertVals...)
			if err != nil {
				return err
			}
			newRowID, err := insRes.LastInsertId()
			if err != nil {
				return err
			}
			newRowIDStr := strconv.FormatInt(newRowID, 10)

			now := time.Now().Format("2006-01-02 15:04:05")
			var audits []vprocore.AuditEntry
			tracked, err := vprocore.AuditChildFieldsTracked(tx, project, "Veg", req.PlotNumber, newID, auditFields, beforeVals, afterVals, actor, strength, now)
			if err != nil {
				return err
			}
			for _, tr := range tracked {
				ids, _ := vprocore.AuditRowIDs([]string{tr.RowID})
				recs, sErr := vprocore.SelectedAuditEntries(tx, project, req.PlotNumber, ids)
				if sErr == nil && len(recs) == 1 {
					audits = append(audits, recs[0])
				}
			}

			history := twoPageVegLifecycleHistory{
				RequestID:     requestID,
				Action:        "create",
				ContextID:     contextID,
				Project:       project,
				PlotNumber:    req.PlotNumber,
				Form:          req.Form,
				ID:            newID,
				RowID:         newRowIDStr,
				Species:       req.Species,
				Actor:         actor,
				AuditStrength: strength,
				EditWhen:      now,
				Audits:        audits,
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
			out = CreateTwoPageVegetationResult{
				RequestID:        requestID,
				ContextID:        contextID,
				Project:          project,
				PlotNumber:       req.PlotNumber,
				Form:             req.Form,
				RowID:            newRowIDStr,
				ID:               newID,
				Species:          req.Species,
				ReservedInLedger: newID >= 0,
				AuditRowCount:    len(audits),
				EditWhen:         now,
				Replayed:         false,
			}
			return nil
		})
		if wErr != nil {
			return CreateTwoPageVegetationResult{}, wErr
		}
		return out, nil
	})
}

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
					_, _ = tx.ExecContext(ctx, `UPDATE `+quotedAudit+` SET "Restore" = -1 WHERE rowid = ? AND "PlotNumber" = ?`, aRowID, req.PlotNumber)
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
