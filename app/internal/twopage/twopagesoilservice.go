package twopage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"slices"
	"strconv"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func twoPageChildWriterSelectedParent(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, suAlias, plot, child string) error {
	project := owner.Selection.Project
	query := `SELECT EXISTS(SELECT 1 FROM main.` + vprocore.QuoteHeaderIdentifier(project+"_Env") +
		` AS e INNER JOIN main.` + vprocore.QuoteHeaderIdentifier(project+"_Admin") + ` AS a ON e.PlotNumber=a.Plot
		WHERE typeof(e.PlotNumber)='text' AND CAST(e.PlotNumber AS BLOB)=CAST(? AS BLOB)`
	if suAlias != "" {
		query += ` AND EXISTS(SELECT 1 FROM ` + vprocore.QuoteHeaderIdentifier(suAlias) + "." +
			vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU") + ` AS su WHERE su.PlotNumber=e.PlotNumber)`
	}
	query += `)`
	var selected bool
	if err := tx.QueryRowContext(ctx, query, plot).Scan(&selected); err != nil {
		return fmt.Errorf("two-page %s selected parent: %w", child, err)
	}
	if !selected {
		return fmt.Errorf("two-page %s parent is outside the selected context", child)
	}
	return nil
}

type TwoPageSoilAttemptOutcome struct {
	ContextID   string                  `json:"contextId"`
	RequestID   string                  `json:"requestId"`
	RequestJSON string                  `json:"requestJSON"`
	Status      string                  `json:"status"`
	Reason      string                  `json:"reason"`
	Receipt     *TwoPageSoilWriteResult `json:"receipt"`
}

func BeginTwoPageSoilAttempt(s *vprocore.ContextService, ctx context.Context, request twoPageSoilRequest) (bool, error) {
	ledger := twoPageSoilAttempts(s)
	if err := sqlutil.AcquireMutexLease(ctx, &ledger.Mu); err != nil {
		return false, err
	}
	defer ledger.Mu.Unlock()
	entry, err := ledger.Entry(request.RequestID, request)
	if err != nil {
		return false, err
	}
	if entry.Sealed {
		return false, nil
	}
	entry.Active++
	return true, nil
}

func FinishTwoPageSoilAttempt(s *vprocore.ContextService, requestID string) {
	ledger := twoPageSoilAttempts(s)
	ledger.Mu.Lock()
	defer ledger.Mu.Unlock()
	ledger.Requests[requestID].Active--
}

func (s *TwoPageSoilService) RecoverOutcome(ctx context.Context, contextID, requestJSON string) (*TwoPageSoilAttemptOutcome, error) {
	return s.recoverTwoPageSoilOutcome(ctx, contextID, requestJSON, nil)
}

func (s *TwoPageSoilService) recoverTwoPageSoilOutcome(ctx context.Context, contextID, requestJSON string,
	afterSeal func()) (*TwoPageSoilAttemptOutcome, error) {
	if err := s.require(ctx, false); err != nil {
		return nil, err
	}
	var request twoPageSoilRequest
	if err := json.Unmarshal([]byte(requestJSON), &request); err != nil {
		return nil, err
	}
	ledger := twoPageSoilAttempts(s.contexts)
	if err := sqlutil.AcquireMutexLease(ctx, &ledger.Mu); err != nil {
		return nil, err
	}
	defer ledger.Mu.Unlock()
	entry, err := ledger.Entry(request.RequestID, request)
	if err != nil {
		return nil, err
	}
	outcome := &TwoPageSoilAttemptOutcome{ContextID: contextID, RequestID: request.RequestID, RequestJSON: requestJSON}
	if entry.Active != 0 {
		outcome.Status, outcome.Reason = "running", "An owned Save attempt is still active; retain the original request."
		return outcome, nil
	}
	// Sealing also prevents an unseen, late RPC from dispatching after this read.
	entry.Sealed = true
	if afterSeal != nil {
		afterSeal()
	}
	receipt, err := LookupTwoPageSoilReceipt(s.contexts, ctx, contextID, request)
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if receipt != nil {
		outcome.Status, outcome.Reason, outcome.Receipt = "committed", "Exact durable history proves the committed source plan.", receipt
	} else if contextID != request.Original.ContextID {
		outcome.Status, outcome.Reason = "unknown", "Absent history in another context cannot certify the original attempt."
	} else {
		outcome.Status, outcome.Reason = "notCommitted", "No active or future matching Save can commit; the original owned history is absent."
	}
	return outcome, nil
}

type twoPageSoilOriginal struct {
	ContextID    string                        `json:"contextId"`
	Project      string                        `json:"project"`
	Plot         string                        `json:"plot"`
	Form         string                        `json:"form"`
	RecordSource string                        `json:"recordSource"`
	Table        string                        `json:"table"`
	Records      vprocore.ProjectMetadataTable `json:"records"`
}

func ReadTwoPageSoilOriginal(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string) (*twoPageSoilOriginal, error) {
	if ctx == nil || s == nil {
		return nil, errors.New("two-page soil original requires an owned context")
	}
	if plot == "" || !utf8.ValidString(plot) {
		return nil, errors.New("two-page soil original requires an exact valid literal parent")
	}
	var kind, source string
	switch form {
	case "SoilHumusXL":
		kind, source = "Humus", "UsysHumus"
	case "SoilMineralXL":
		kind, source = "Mineral", "UsysMineral"
	default:
		return nil, fmt.Errorf("two-page soil original does not support source form %q", form)
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*twoPageSoilOriginal, error) {
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*twoPageSoilOriginal, error) {
			project := owner.Selection.Project
			table := project + "_" + kind
			if err := requireTwoPageSoilReadScope(ctx, tx, project, table, plot); err != nil {
				return nil, err
			}
			if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, "project", table, "two-page soil originals"); err != nil {
				return nil, fmt.Errorf("two-page soil original %s schema: %w", kind, err)
			}
			records, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "project", table, "PlotNumber", plot, "")
			if err != nil {
				return nil, fmt.Errorf("two-page soil original %s storage: %w", kind, err)
			}
			records = orderTwoPageSoilRecords(kind, records)
			return &twoPageSoilOriginal{ContextID: contextID, Project: project, Plot: plot, Form: form,
				RecordSource: source, Table: table, Records: records}, nil
		})
	})
}

type twoPageNumericDepth struct {
	isNull  bool
	isInt   bool
	intVal  int64
	realVal float64
}

func parseTwoPageNumericDepth(cell vprocore.ProjectMetadataCell) (twoPageNumericDepth, bool) {
	switch cell.Storage {
	case "null":
		return twoPageNumericDepth{isNull: true}, true
	case "integer":
		if cell.Integer == nil {
			return twoPageNumericDepth{}, false
		}
		v, err := strconv.ParseInt(*cell.Integer, 10, 64)
		if err != nil {
			return twoPageNumericDepth{}, false
		}
		return twoPageNumericDepth{isInt: true, intVal: v}, true
	case "real":
		if cell.Real == nil || math.IsNaN(*cell.Real) || math.IsInf(*cell.Real, 0) {
			return twoPageNumericDepth{}, false
		}
		return twoPageNumericDepth{realVal: *cell.Real}, true
	default:
		return twoPageNumericDepth{}, false
	}
}

func compareTwoPageNonNullDepth(a, b twoPageNumericDepth) int {
	if a.isInt && b.isInt {
		if a.intVal < b.intVal {
			return -1
		}
		if a.intVal > b.intVal {
			return 1
		}
		return 0
	}
	if !a.isInt && !b.isInt {
		if a.realVal < b.realVal {
			return -1
		}
		if a.realVal > b.realVal {
			return 1
		}
		return 0
	}
	ra := new(big.Rat)
	if a.isInt {
		ra.SetInt64(a.intVal)
	} else {
		ra.SetFloat64(a.realVal)
	}
	rb := new(big.Rat)
	if b.isInt {
		rb.SetInt64(b.intVal)
	} else {
		rb.SetFloat64(b.realVal)
	}
	return ra.Cmp(rb)
}

// orderTwoPageSoilRecords orders soil rows in canonical LMH25 top-to-bottom profile order
// (AGENTS.md §3.4, ENG-GO-005): upland L/F/H humus UpperDepth DESC, wetland O*/Hydric/Limno/Cumulo
// humus UpperDepth ASC, and mineral UpperDepth ASC, with NULL depths last and ties preserving rowid.
// If UpperDepth is absent or contains historical non-numeric text/blob cells, physical rowid order is preserved.
func orderTwoPageSoilRecords(kind string, records vprocore.ProjectMetadataTable) vprocore.ProjectMetadataTable {
	if len(records.Rows) <= 1 {
		return records
	}
	upperIdx, horizonIdx := -1, -1
	for i, col := range records.Columns {
		switch col.Name {
		case "UpperDepth":
			upperIdx = i
		case "Horizon":
			horizonIdx = i
		}
	}
	if upperIdx < 0 {
		return records
	}
	type rowSortMeta struct {
		row     vprocore.ProjectMetadataRow
		depth   twoPageNumericDepth
		wetland bool
	}
	meta := make([]rowSortMeta, len(records.Rows))
	for i, row := range records.Rows {
		d, ok := parseTwoPageNumericDepth(row.Cells[upperIdx])
		if !ok {
			return records
		}
		wetland := false
		if kind == "Humus" && horizonIdx >= 0 {
			hCell := row.Cells[horizonIdx]
			if hCell.Storage == "text" && hCell.Text != nil {
				wetland = vprocore.ClassifySoilHorizon("Humus", *hCell.Text) == vprocore.SoilHorizonWetland
			}
		}
		meta[i] = rowSortMeta{row: row, depth: d, wetland: wetland}
	}
	slices.SortStableFunc(meta, func(a, b rowSortMeta) int {
		if kind == "Humus" && a.wetland != b.wetland {
			if a.wetland {
				return 1
			}
			return -1
		}
		if a.depth.isNull || b.depth.isNull {
			if a.depth.isNull && b.depth.isNull {
				return 0
			}
			if a.depth.isNull {
				return 1
			}
			return -1
		}
		cmp := compareTwoPageNonNullDepth(a.depth, b.depth)
		if kind == "Humus" && !a.wetland {
			return -cmp
		}
		return cmp
	})
	ordered := make([]vprocore.ProjectMetadataRow, len(meta))
	for i := range meta {
		ordered[i] = meta[i].row
	}
	records.Rows = ordered
	return records
}

func requireTwoPageSoilReadScope(ctx context.Context, tx *sql.Tx, project, table, plot string) error {
	return sourceform.RequireTwoPageChildReadScope(ctx, tx, project, table, plot, "soil")
}

type twoPageSoilReference struct {
	Column      string                        `json:"column"`
	ListName    string                        `json:"listName"`
	Definitions vprocore.ProjectMetadataTable `json:"definitions"`
}

type twoPageSoilReferences struct {
	ContextID string                 `json:"contextId"`
	Project   string                 `json:"project"`
	Plot      string                 `json:"plot"`
	Form      string                 `json:"form"`
	Source    string                 `json:"source"`
	Fields    []twoPageSoilReference `json:"fields"`
}

func twoPageSoilReferenceFields(form string) (string, []twoPageSoilReference, error) {
	switch form {
	case "SoilHumusXL":
		return "Humus", []twoPageSoilReference{
			{Column: "Horizon", ListName: "HumusHorizon"},
			{Column: "HumusStructureKind", ListName: "HumusStructureKind"},
			{Column: "HumusStructureDegree", ListName: "HumusStructureDegree"},
			{Column: "vonPost", ListName: "vonPost"},
			{Column: "MycelAbundance", ListName: "MycelAbundance"},
			{Column: "FecalAbundance", ListName: "MycelAbundance"},
		}, nil
	case "SoilMineralXL":
		return "Mineral", []twoPageSoilReference{
			{Column: "ASP", ListName: "MinSoilAspect"},
			{Column: "Texture", ListName: "SoilTexture"},
			{Column: "MineralStructureClass", ListName: "MineralStructureClass"},
			{Column: "MineralStructureKind", ListName: "MineralStructureKind"},
		}, nil
	default:
		return "", nil, fmt.Errorf("two-page soil references do not support source form %q", form)
	}
}

func ReadTwoPageSoilReferences(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string) (*twoPageSoilReferences, error) {
	if ctx == nil || s == nil {
		return nil, errors.New("two-page soil references require an owned context")
	}
	if plot == "" || !utf8.ValidString(plot) {
		return nil, errors.New("two-page soil references require an exact valid literal parent")
	}
	kind, fields, err := twoPageSoilReferenceFields(form)
	if err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*twoPageSoilReferences, error) {
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*twoPageSoilReferences, error) {
			project := owner.Selection.Project
			if err := requireTwoPageSoilReadScope(ctx, tx, project, project+"_"+kind, plot); err != nil {
				return nil, fmt.Errorf("two-page soil reference scope: %w", err)
			}
			for i := range fields {
				definitions, err := sourceform.ReadSourceSharedFamilyReference(ctx, tx, "VLists", fields[i].ListName)
				if err != nil {
					return nil, fmt.Errorf("two-page soil reference %s.%s: %w", form, fields[i].Column, err)
				}
				fields[i].Definitions = definitions
			}
			return &twoPageSoilReferences{
				ContextID: contextID, Project: project, Plot: plot, Form: form,
				Source: "configured-owned-imported-SQLite VLists.USysTableOfLists; physical rowid; ItemOrder then rowid",
				Fields: fields,
			}, nil
		})
	})
}

type TwoPageSoilOriginal = twoPageSoilOriginal
type TwoPageSoilWriteResult = twoPageSoilWriteResult
type TwoPageSoilReference = twoPageSoilReference
type TwoPageSoilReferences = twoPageSoilReferences

type TwoPageSoilService struct {
	contexts *vprocore.ContextService
}

func NewTwoPageSoilService(contexts *vprocore.ContextService) (*TwoPageSoilService, error) {
	if contexts == nil {
		return nil, errors.New("two-page soil service requires owned contexts")
	}
	return &TwoPageSoilService{contexts: contexts}, nil
}

func (s *TwoPageSoilService) require(ctx context.Context, _ bool) error {
	if ctx == nil {
		return errors.New("two-page soil service requires a context")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if s == nil || s.contexts == nil {
		return errors.New("two-page soil service requires owned contexts")
	}
	return nil
}

func (s *TwoPageSoilService) GetOriginal(ctx context.Context, contextID, plot, form string) (*TwoPageSoilOriginal, error) {
	if err := s.require(ctx, false); err != nil {
		return nil, err
	}
	return ReadTwoPageSoilOriginal(s.contexts, ctx, contextID, plot, form)
}

func (s *TwoPageSoilService) GetReferences(ctx context.Context, contextID, plot, form string) (*TwoPageSoilReferences, error) {
	if err := s.require(ctx, false); err != nil {
		return nil, err
	}
	return ReadTwoPageSoilReferences(s.contexts, ctx, contextID, plot, form)
}

func (s *TwoPageSoilService) Save(ctx context.Context, contextID, requestJSON string) (*TwoPageSoilWriteResult, error) {
	return s.saveTwoPageSoilObserved(ctx, contextID, requestJSON, nil, nil)
}

func (s *TwoPageSoilService) saveTwoPageSoilObserved(ctx context.Context, contextID, requestJSON string,
	beforeCommit func(*sql.Tx) error, afterCommit func(*twoPageSoilWriteResult) error) (*TwoPageSoilWriteResult, error) {
	return s.dispatchTwoPageSoilObserved(ctx, contextID, requestJSON, false, beforeCommit, afterCommit)
}

func (s *TwoPageSoilService) CreateHorizon(ctx context.Context, contextID, requestJSON string) (*TwoPageSoilWriteResult, error) {
	return s.dispatchTwoPageSoilObserved(ctx, contextID, requestJSON, true, nil, nil)
}

func (s *TwoPageSoilService) dispatchTwoPageSoilObserved(ctx context.Context, contextID, requestJSON string, creation bool,
	beforeCommit func(*sql.Tx) error, afterCommit func(*twoPageSoilWriteResult) error) (*TwoPageSoilWriteResult, error) {
	if err := s.require(ctx, true); err != nil {
		return nil, err
	}
	var request twoPageSoilRequest
	if err := json.Unmarshal([]byte(requestJSON), &request); err != nil {
		return nil, err
	}
	if creation != (request.Horizon != nil) {
		return nil, errors.New("soil horizon creation requires its explicit action; ordinary Save cannot create records")
	}
	started, err := BeginTwoPageSoilAttempt(s.contexts, ctx, request)
	if err != nil {
		return nil, err
	}
	if !started {
		receipt, err := LookupTwoPageSoilReceipt(s.contexts, ctx, contextID, request)
		if err != nil {
			return nil, err
		}
		if receipt == nil {
			return nil, errors.New("two-page soil request was sealed without a commit; review a fresh original and use a new UUID")
		}
		return receipt, nil
	}
	defer FinishTwoPageSoilAttempt(s.contexts, request.RequestID)
	return WriteTwoPageSoilObserved(s.contexts, ctx, contextID, request, beforeCommit, afterCommit)
}
