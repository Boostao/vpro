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
