package projectops

import (
	"context"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type OptimizeVegOptions struct {
	PlotNumbers            []string `json:"plotNumbers,omitempty"`
	CustodianAuditOverride bool     `json:"custodianAuditOverride,omitempty"`
}

func (r *OptimizeVegOptions) UnmarshalJSON(data []byte) error {
	type plain OptimizeVegOptions
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type OptimizeVegConflict struct {
	PlotNumber   string   `json:"plotNumber"`
	Species      string   `json:"species"`
	Field        string   `json:"field"`
	Reason       string   `json:"reason"`
	Values       []string `json:"values,omitempty"`
	SourceIDs    []int64  `json:"sourceIds,omitempty"`
	Overrideable bool     `json:"overrideable,omitempty"`
}

type OptimizeVegAuditRef struct {
	PlotNumber string `json:"plotNumber"`
	Species    string `json:"species"`
	RetiredID  int64  `json:"retiredId"`
	Table      string `json:"table"`
	EditField  string `json:"editField"`
	EditWhen   string `json:"editWhen"`
}

type OptimizeVegFieldDiff struct {
	Field    string            `json:"field"`
	Proposed *string           `json:"proposed,omitempty"`
	Before   map[int64]*string `json:"before,omitempty"`
}

type OptimizeVegGroup struct {
	PlotNumber                string                 `json:"plotNumber"`
	Species                   string                 `json:"species"`
	SourceRowCount            int                    `json:"sourceRowCount"`
	SurvivorID                int64                  `json:"survivorId"`
	RetiredIDs                []int64                `json:"retiredIds"`
	OldToSurvivorIDMap        map[int64]int64        `json:"oldToSurvivorIdMap,omitempty"`
	HasOverlappingLayerCovers bool                   `json:"hasOverlappingLayerCovers"`
	CappedCoverColumns        []string               `json:"cappedCoverColumns"`
	MergedCovers              map[string]float64     `json:"mergedCovers"`
	MergedHeights             map[string]float64     `json:"mergedHeights"`
	MergedHeightB             *string                `json:"mergedHeightB,omitempty"`
	FieldDiffs                []OptimizeVegFieldDiff `json:"fieldDiffs,omitempty"`
	Conflicts                 []OptimizeVegConflict  `json:"conflicts,omitempty"`
	AuditReferences           []OptimizeVegAuditRef  `json:"auditReferences,omitempty"`
	Blocked                   bool                   `json:"blocked,omitempty"`
	BlockedReasons            []string               `json:"blockedReasons,omitempty"`
}

type OptimizeVegPreview struct {
	Project               string                `json:"project"`
	BeforeRowCount        int                   `json:"beforeRowCount"`
	AfterRowCount         int                   `json:"afterRowCount"`
	RowsToConsolidate     int                   `json:"rowsToConsolidate"`
	DuplicateSpeciesCount int                   `json:"duplicateSpeciesCount"`
	OverlappingGroupCount int                   `json:"overlappingGroupCount"`
	CappedCoverCount      int                   `json:"cappedCoverCount"`
	BlockedGroupCount     int                   `json:"blockedGroupCount"`
	HasBlockingConflicts  bool                  `json:"hasBlockingConflicts"`
	PreviewDigest         string                `json:"previewDigest"`
	OldToSurvivorIDMap    map[int64]int64       `json:"oldToSurvivorIdMap,omitempty"`
	Conflicts             []OptimizeVegConflict `json:"conflicts,omitempty"`
	AuditReferences       []OptimizeVegAuditRef `json:"auditReferences,omitempty"`
	Groups                []OptimizeVegGroup    `json:"groups"`
}

type ApplyOptimizeVegRequest struct {
	PlotNumbers            []string `json:"plotNumbers,omitempty"`
	ExpectedDigest         string   `json:"expectedDigest,omitempty"`
	CustodianAuditOverride bool     `json:"custodianAuditOverride,omitempty"`
}

func (r *ApplyOptimizeVegRequest) UnmarshalJSON(data []byte) error {
	type plain ApplyOptimizeVegRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type OptimizeVegResult struct {
	Project            string             `json:"project"`
	BeforeRowCount     int                `json:"beforeRowCount"`
	AfterRowCount      int                `json:"afterRowCount"`
	ConsolidatedGroups int                `json:"consolidatedGroups"`
	DeletedRows        int                `json:"deletedRows"`
	ReservedDeletedIDs []int64            `json:"reservedDeletedIds"`
	OldToSurvivorIDMap map[int64]int64    `json:"oldToSurvivorIdMap,omitempty"`
	AuditRowsWritten   int                `json:"auditRowsWritten"`
	Groups             []OptimizeVegGroup `json:"groups"`
}

var vegCoverCols = []string{
	"Cover1", "Cover2", "Cover3", "TotalA",
	"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
	"Cover6", "Cover7", "Cover8", "Cover9", "Cover10",
}

var vegNumericHeightCols = []string{
	"Height1", "Height2", "Height3", "HeightA",
	"Height4", "Height5", "Height5a", "Height5b", "Height5c",
	"Height6",
}

var vegFirstIntCols = []string{
	"LL", "AF", "DC", "UT", "VI", "PV", "PG", "FFA",
	"Cultural1", "Cultural2", "Other1", "Other2",
}

const (
	vegSignedInt32Min = int64(-2147483648)
	vegSignedInt32Max = int64(2147483647)
)

type plannedVegConsolidation struct {
	group          OptimizeVegGroup
	survivorRowID  int64
	deletedRowIDs  []int64
	deletedPhysIDs []int64
	survivorBefore map[string]rawSQLiteCell
	survivorAfter  map[string]rawSQLiteCell
	deletedBefore  []map[string]rawSQLiteCell
}

type vegRowWithRowID struct {
	rowID int64
	cells map[string]rawSQLiteCell
}

func validateOptimizeVegProjectSchema(ctx context.Context, db sqliteQueryer, project string) error {
	envTable := project + "_Env"
	vegTable := project + "_Veg"
	auditTable := project + "_Audit"
	existing := map[string]bool{}
	tRows, err := db.QueryContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?, ?, '_table_metadata')`,
		envTable, vegTable, auditTable)
	if err != nil {
		return err
	}
	for tRows.Next() {
		var name string
		if err := tRows.Scan(&name); err != nil {
			_ = tRows.Close()
			return err
		}
		existing[name] = true
	}
	if err := errors.Join(tRows.Err(), tRows.Close()); err != nil {
		return err
	}
	for _, req := range []string{envTable, vegTable, auditTable} {
		if !existing[req] {
			return fmt.Errorf("OptimizeVeg refused: required VP08 table %s is missing", req)
		}
	}
	if existing["_table_metadata"] {
		for _, req := range []string{envTable, vegTable, auditTable} {
			mRows, mErr := db.QueryContext(ctx, `SELECT COALESCE(description, '') FROM "_table_metadata" WHERE table_name = ? LIMIT 1`, req)
			if mErr != nil {
				return mErr
			}
			var desc string
			found := mRows.Next()
			if found {
				if err := mRows.Scan(&desc); err != nil {
					_ = mRows.Close()
					return err
				}
			}
			if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
				return err
			}
			if !found {
				return fmt.Errorf("OptimizeVeg refused: table %s lacks VP08 version stamp in _table_metadata", req)
			}
			if strings.TrimSpace(desc) != "VP08" {
				return fmt.Errorf("OptimizeVeg refused: table %s has version %q in _table_metadata; expected VP08", req, desc)
			}
		}
	}

	quotedVeg := vprocore.QuoteHeaderIdentifier(vegTable)
	badRows, err := db.QueryContext(ctx, `SELECT rowid, typeof("ID"), COALESCE(CAST("ID" AS TEXT), '<null>') FROM `+quotedVeg+`
		WHERE typeof("ID") <> 'integer' OR "ID" < ? OR "ID" > ? LIMIT 1`,
		vegSignedInt32Min, vegSignedInt32Max)
	if err != nil {
		return err
	}
	if badRows.Next() {
		var rid int64
		var typ, raw string
		scanErr := badRows.Scan(&rid, &typ, &raw)
		_ = badRows.Close()
		if scanErr != nil {
			return scanErr
		}
		return fmt.Errorf("OptimizeVeg refused: rowid %d in %s has invalid or non-32-bit ID (%s=%s); all vegetation rows must carry non-null unique signed 32-bit IDs",
			rid, vegTable, typ, raw)
	}
	if err := errors.Join(badRows.Err(), badRows.Close()); err != nil {
		return err
	}

	dupIDRows, err := db.QueryContext(ctx, `SELECT "ID", COUNT(*) FROM `+quotedVeg+` GROUP BY "ID" HAVING COUNT(*) > 1 LIMIT 1`)
	if err != nil {
		return err
	}
	if dupIDRows.Next() {
		var dupID int64
		var cnt int
		scanErr := dupIDRows.Scan(&dupID, &cnt)
		_ = dupIDRows.Close()
		if scanErr != nil {
			return scanErr
		}
		return fmt.Errorf("OptimizeVeg refused: duplicate ID %d appears %d times in %s; every row must have a unique signed 32-bit ID",
			dupID, cnt, vegTable)
	}
	if err := errors.Join(dupIDRows.Err(), dupIDRows.Close()); err != nil {
		return err
	}
	return nil
}

// PreviewOptimizeVeg computes a non-destructive preview of consolidating split/duplicate
// (PlotNumber, Species) rows in <Project>_Veg.
func PreviewOptimizeVeg(s *vprocore.ContextService, ctx context.Context, contextID string, opts OptimizeVegOptions) (OptimizeVegPreview, error) {
	snap, err := inspectContextSnapshot(ctx, s, contextID)
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, snap.ProjectPath)
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	defer db.Close()
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	defer func() { _ = tx.Rollback() }()

	preview, _, _, err := buildOptimizeVegPlan(ctx, tx, snap.Project, opts.PlotNumbers, opts.CustodianAuditOverride)
	return preview, err
}

func rawCellsEqual(a, b rawSQLiteCell) bool {
	if a.storage != b.storage {
		return false
	}
	switch a.storage {
	case "null":
		return true
	case "integer":
		return a.intVal == b.intVal
	case "real":
		return math.Float64bits(a.realVal) == math.Float64bits(b.realVal)
	case "text", "blob":
		return string(a.bytes) == string(b.bytes)
	default:
		return false
	}
}

func auditTextForRawCell(c rawSQLiteCell) any {
	switch c.storage {
	case "null":
		return nil
	case "integer":
		return strconv.FormatInt(c.intVal, 10)
	case "real":
		return vprocore.SourceDoubleDecimalString(c.realVal)
	case "text":
		return string(c.bytes)
	case "blob":
		return hex.EncodeToString(c.bytes)
	default:
		return nil
	}
}

// ApplyOptimizeVeg executes multi-row (PlotNumber, Species) consolidation inside a single
// BEGIN IMMEDIATE transaction, reserving all retired child IDs in __VPRO_ChildIdentity
// and writing full <Project>_Audit records.
func ApplyOptimizeVeg(s *vprocore.ContextService, ctx context.Context, contextID string, req ApplyOptimizeVegRequest) (OptimizeVegResult, error) {
	if s == nil {
		return OptimizeVegResult{}, errors.New("project context service is unavailable")
	}
	var out OptimizeVegResult
	err := s.Edit(contextID, func(plots *vprocore.PlotService) error {
		owner := plots.Projects.Sqlite
		user := strings.TrimSpace(plots.CurrentUser)
		if user == "" {
			user = "VProUser"
		}
		return owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			project := owner.Selection.Project
			preview, plans, cols, err := buildOptimizeVegPlan(ctx, tx, project, req.PlotNumbers, req.CustodianAuditOverride)
			if err != nil {
				return err
			}
			if expected := strings.TrimSpace(req.ExpectedDigest); expected != "" && expected != preview.PreviewDigest {
				return errors.New("vegetation table changed since preview; re-run PreviewOptimizeVeg before applying")
			}
			if preview.HasBlockingConflicts || len(preview.Conflicts) > 0 {
				return fmt.Errorf("OptimizeVeg refused: %d blocking conflict(s) across %d group(s); first: %s",
					len(preview.Conflicts), preview.BlockedGroupCount, preview.Conflicts[0].Reason)
			}
			if len(plans) == 0 {
				out = OptimizeVegResult{
					Project:            project,
					BeforeRowCount:     preview.BeforeRowCount,
					AfterRowCount:      preview.AfterRowCount,
					ReservedDeletedIDs: []int64{},
					OldToSurvivorIDMap: map[int64]int64{},
					Groups:             []OptimizeVegGroup{},
				}
				return nil
			}

			if err := ensureChildIdentityTable(ctx, tx); err != nil {
				return err
			}

			vegTable := project + "_Veg"
			quotedVeg := vprocore.QuoteHeaderIdentifier(vegTable)
			quotedAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			now := time.Now().Format("2006-01-02 15:04:05")

			auditStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+quotedAudit+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`)
			if err != nil {
				return err
			}
			defer auditStmt.Close()

			var allReserved []int64
			oldToSurvivorAll := map[int64]int64{}
			deletedCount := 0
			auditCount := 0

			for i := range plans {
				if err := ctx.Err(); err != nil {
					return err
				}
				plan := &plans[i]
				survivorID := plan.group.SurvivorID
				if err := reserveChildID(ctx, tx, vegTable, survivorID); err != nil {
					return err
				}

				// Update changed columns on survivor row using explicit column names.
				var setParts []string
				var updateArgs []any
				for _, col := range cols {
					if col == "PlotNumber" || col == "Species" || col == "ID" {
						continue
					}
					beforeCell := plan.survivorBefore[col]
					afterCell := plan.survivorAfter[col]
					if rawCellsEqual(beforeCell, afterCell) {
						continue
					}
					setParts = append(setParts, vprocore.QuoteHeaderIdentifier(col)+" = ?")
					updateArgs = append(updateArgs, afterCell.sqlParam())
					if _, err := auditStmt.ExecContext(ctx, project, user, plan.group.PlotNumber, "_Veg", col, now,
						auditTextForRawCell(beforeCell), auditTextForRawCell(afterCell), survivorID); err != nil {
						return err
					}
					auditCount++
				}
				if len(setParts) > 0 {
					updateArgs = append(updateArgs, plan.survivorRowID)
					uRes, uErr := tx.ExecContext(ctx, "UPDATE "+quotedVeg+" SET "+strings.Join(setParts, ", ")+" WHERE rowid = ?", updateArgs...)
					if uErr != nil {
						return uErr
					}
					if n, _ := uRes.RowsAffected(); n != 1 {
						return errors.New("OptimizeVeg survivor row update did not match 1 row")
					}
				}

				// Delete duplicate rows and permanently reserve their IDs in __VPRO_ChildIdentity.
				for dIdx, dupRowID := range plan.deletedRowIDs {
					dupCells := plan.deletedBefore[dIdx]
					dupID := dupCells["ID"].intVal
					if dupID != survivorID {
						if err := reserveChildID(ctx, tx, vegTable, dupID); err != nil {
							return err
						}
						allReserved = append(allReserved, dupID)
						oldToSurvivorAll[dupID] = survivorID
					}
					for _, col := range cols {
						if col == "ID" || col == "PlotNumber" {
							continue
						}
						beforeCell := dupCells[col]
						if beforeCell.storage == "null" || (col == "Flag" && beforeCell.storage == "integer" && beforeCell.intVal == 0) {
							continue
						}
						if _, err := auditStmt.ExecContext(ctx, project, user, plan.group.PlotNumber, "_Veg", col, now,
							auditTextForRawCell(beforeCell), nil, dupID); err != nil {
							return err
						}
						auditCount++
					}
					dRes, dErr := tx.ExecContext(ctx, "DELETE FROM "+quotedVeg+" WHERE rowid = ?", dupRowID)
					if dErr != nil {
						return dErr
					}
					if n, _ := dRes.RowsAffected(); n != 1 {
						return errors.New("OptimizeVeg duplicate row delete did not match 1 row")
					}
					deletedCount++
				}
			}

			// Verify post-mutation row count matches preview plan before commit.
			var actualAfterCount int
			if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+quotedVeg).Scan(&actualAfterCount); err != nil {
				return err
			}
			if actualAfterCount != preview.AfterRowCount {
				return fmt.Errorf("OptimizeVeg row count check failed: got %d, expected %d", actualAfterCount, preview.AfterRowCount)
			}

			// Record a project-level OptimizeVeg provenance receipt in Audit (with old-to-survivor ID map).
			summaryJSON, _ := json.Marshal(map[string]any{
				"consolidatedGroups":     len(plans),
				"deletedRows":            deletedCount,
				"oldToSurvivorIdMap":     oldToSurvivorAll,
				"custodianAuditOverride": req.CustodianAuditOverride,
			})
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+quotedAudit+` ("Project","User","Table","EditField","EditWhen","AfterEdit","Restore","Flag") VALUES (?,?,?,?,?,?,0,0)`,
				project, user, "_Veg", "OptimizeVeg", now, string(summaryJSON)); err != nil {
				return err
			}
			auditCount++

			// Verify foreign key integrity on mutated tables inside the transaction.
			for _, tbl := range []string{vegTable, project + "_Audit"} {
				fkRows, fkErr := tx.QueryContext(ctx, "PRAGMA foreign_key_check("+vprocore.QuoteHeaderIdentifier(tbl)+")")
				if fkErr != nil {
					return fkErr
				}
				hasFKViolation := fkRows.Next()
				if err := errors.Join(fkRows.Err(), fkRows.Close()); err != nil {
					return err
				}
				if hasFKViolation {
					return fmt.Errorf("OptimizeVeg foreign_key_check failed for %s", tbl)
				}
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}

			groups := make([]OptimizeVegGroup, len(plans))
			for i, p := range plans {
				groups[i] = p.group
			}
			slices.Sort(allReserved)
			allReserved = slices.Compact(allReserved)
			out = OptimizeVegResult{
				Project:            project,
				BeforeRowCount:     preview.BeforeRowCount,
				AfterRowCount:      preview.AfterRowCount,
				ConsolidatedGroups: len(plans),
				DeletedRows:        deletedCount,
				ReservedDeletedIDs: allReserved,
				OldToSurvivorIDMap: oldToSurvivorAll,
				AuditRowsWritten:   auditCount,
				Groups:             groups,
			}
			return nil
		})
	})
	if err != nil {
		return OptimizeVegResult{}, err
	}
	return out, nil
}
