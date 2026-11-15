package diagnostics

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	synthesisSUHistoryTable = "__VPRO_SynthesisSUHistory"
	synthesisSUHistorySQL   = `CREATE TABLE "__VPRO_SynthesisSUHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type synthesisSUHistoryReceipt struct {
	Kind            string  `json:"kind"` // "synthesis_su_reassignment" | "synthesis_su_reassignment_undo"
	ContextID       string  `json:"contextId"`
	Project         string  `json:"project"`
	SU              string  `json:"su"`
	PlotNumber      string  `json:"plotNumber"`
	ExistedBefore   bool    `json:"existedBefore"`
	BeforeSiteUnit  *string `json:"beforeSiteUnit"`
	ExistedAfter    bool    `json:"existedAfter"`
	AfterSiteUnit   *string `json:"afterSiteUnit"`
	UndoneHistoryID int64   `json:"undoneHistoryId,omitempty"`
}

func validateWritableSUTarget(owner *vprocore.SqliteContext) (string, string, error) {
	if owner == nil || owner.Conn == nil {
		return "", "", errors.New("classification context is closed")
	}
	suName := strings.TrimSpace(owner.Selection.SU)
	if suName == "" || strings.EqualFold(suName, "None") {
		return "", "", errors.New("an active Site Unit (SU) table must be selected before reassigning plots")
	}
	lowerSU := strings.ToLower(suName)
	if lowerSU == "master" ||
		strings.HasPrefix(lowerSU, "master_") ||
		strings.HasSuffix(lowerSU, "_master") ||
		strings.EqualFold(suName, "MasterSiteUnitList") ||
		strings.HasPrefix(lowerSU, "usys") {
		return "", "", fmt.Errorf("SU table %q is a protected master or system table; writes are prohibited", suName+"_SU")
	}
	if err := owner.ValidateMetadataWriterFiles(); err != nil {
		return "", "", err
	}
	suInfo := owner.AttachmentInfo["su"]
	if suInfo == nil {
		return "", "", errors.New("active SU database is not attached")
	}
	for role, info := range owner.AttachmentInfo {
		if strings.HasPrefix(role, "V") && info != nil && os.SameFile(suInfo, info) {
			return "", "", fmt.Errorf("SU database aliases protected support database %s; writes are prohibited", role)
		}
	}
	suTable := suName + "_SU"
	for _, row := range owner.Descriptions["su"] {
		if tName, ok := row["table_name"].(string); ok && strings.EqualFold(tName, suTable) {
			if desc, ok := row["description"].(string); ok && strings.Contains(strings.ToLower(desc), "master") {
				return "", "", fmt.Errorf("SU table %s is marked as master in _table_metadata; writes are prohibited", suTable)
			}
		}
	}
	return suName, suTable, nil
}

func readSynthesisUndoStatus(ctx context.Context, tx *sql.Tx, suName string) (bool, int, *SynthesisUndoEntry) {
	if suName == "" || strings.EqualFold(suName, "None") {
		return false, 0, nil
	}
	var exists bool
	if err := tx.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM "su".sqlite_master WHERE type='table' AND name=?)`,
		synthesisSUHistoryTable,
	).Scan(&exists); err != nil || !exists {
		return false, 0, nil
	}

	rows, err := tx.QueryContext(ctx,
		`SELECT ID, Created, Proposal FROM "su".`+vprocore.QuoteHeaderIdentifier(synthesisSUHistoryTable)+` ORDER BY ID ASC`)
	if err != nil {
		return false, 0, nil
	}
	defer rows.Close()

	type stackItem struct {
		id      int64
		created string
		rec     synthesisSUHistoryReceipt
	}
	var items []stackItem
	undoneSet := map[int64]bool{}

	for rows.Next() {
		var id int64
		var created, proposal string
		if err := rows.Scan(&id, &created, &proposal); err != nil {
			continue
		}
		var rec synthesisSUHistoryReceipt
		if err := json.Unmarshal([]byte(proposal), &rec); err != nil {
			continue
		}
		if !strings.EqualFold(rec.SU, suName) {
			continue
		}
		switch rec.Kind {
		case "synthesis_su_reassignment":
			items = append(items, stackItem{id: id, created: created, rec: rec})
		case "synthesis_su_reassignment_undo":
			if rec.UndoneHistoryID > 0 {
				undoneSet[rec.UndoneHistoryID] = true
			}
		}
	}

	active := make([]stackItem, 0, len(items))
	for _, it := range items {
		if !undoneSet[it.id] {
			active = append(active, it)
		}
	}
	if len(active) == 0 {
		return false, 0, nil
	}
	top := active[len(active)-1]
	before := ""
	if top.rec.BeforeSiteUnit != nil {
		before = *top.rec.BeforeSiteUnit
	}
	after := ""
	if top.rec.AfterSiteUnit != nil {
		after = *top.rec.AfterSiteUnit
	}
	return true, len(active), &SynthesisUndoEntry{
		HistoryID:      top.id,
		PlotNumber:     top.rec.PlotNumber,
		BeforeSiteUnit: before,
		AfterSiteUnit:  after,
		Created:        top.created,
	}
}

func verifyPlotInProjectEnv(ctx context.Context, owner *vprocore.SqliteContext, plotNumber string) error {
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return err
	}
	defer owner.Mu.Unlock()
	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	project := owner.Selection.Project
	var exists bool
	err = tx.QueryRowContext(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Env")+`
			WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)
		)`,
		plotNumber, plotNumber,
	).Scan(&exists)
	if err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("plot %q does not exist in project %s", plotNumber, project)
	}
	return tx.Commit()
}

// ReassignSynthesisPlotUnit atomically updates <SU>_SU inside BEGIN IMMEDIATE, writes an undo receipt
// to __VPRO_SynthesisSUHistory, and immediately recomputes the updated SynthesisSnapshot (< 50 ms target).
func ReassignSynthesisPlotUnit(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	req ReassignSynthesisPlotRequest,
) (*ReassignSynthesisPlotResult, error) {
	started := time.Now()
	if ctx == nil {
		return nil, errors.New("synthesis plot reassignment requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if req.PlotNumber == "" || !utf8.ValidString(req.PlotNumber) || strings.ContainsRune(req.PlotNumber, 0) {
		return nil, errors.New("plotNumber must be valid non-empty UTF-8 without NUL")
	}
	if len(utf16.Encode([]rune(req.PlotNumber))) > 7 {
		return nil, fmt.Errorf("plotNumber %q exceeds 7 UTF-16 code units", req.PlotNumber)
	}

	targetUnit := strings.TrimSpace(req.TargetSiteUnit)
	if !utf8.ValidString(targetUnit) || strings.ContainsRune(targetUnit, 0) {
		return nil, errors.New("targetSiteUnit must be valid UTF-8 without NUL")
	}
	if len(utf16.Encode([]rune(targetUnit))) > 255 {
		return nil, errors.New("targetSiteUnit exceeds 255 UTF-16 code units")
	}
	if targetUnit == "" {
		return nil, errors.New("targetSiteUnit must not be empty")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ReassignSynthesisPlotResult, error) {
		owner := plots.Projects.Sqlite
		if err := verifyPlotInProjectEnv(ctx, owner, req.PlotNumber); err != nil {
			return nil, err
		}

		var suName, suTable string
		validateFiles := func() error {
			var err error
			suName, suTable, err = validateWritableSUTarget(owner)
			return err
		}

		var beforeUnit string
		var changed bool
		var historyID int64

		err := owner.WithSelectedFileWriter(ctx, "su", validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil) // BEGIN IMMEDIATE via _txlock=immediate holds SQLite write lock
			if bErr != nil {
				return bErr
			}
			preStamp, preOK := statDBFileWithWAL(owner.Selection.ProjectPath)
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			qTable := vprocore.QuoteHeaderIdentifier(suTable)
			var rowID int64
			var existing sql.NullString
			qErr := tx.QueryRowContext(ctx,
				`SELECT rowid, CAST("SiteUnit" AS TEXT) FROM main.`+qTable+
					` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
				req.PlotNumber, req.PlotNumber,
			).Scan(&rowID, &existing)

			existedBefore := qErr == nil
			if qErr != nil && !errors.Is(qErr, sql.ErrNoRows) {
				return qErr
			}
			var beforePtr *string
			if existedBefore && existing.Valid {
				v := existing.String
				beforeUnit = strings.TrimSpace(v)
				beforePtr = &v
			}

			afterCopy := targetUnit
			if existedBefore {
				if beforePtr != nil && *beforePtr == afterCopy {
					return tx.Commit()
				}
				if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "SiteUnit" = ? WHERE rowid = ?`, afterCopy, rowID); err != nil {
					return err
				}
				changed = true
			} else {
				if _, err := tx.ExecContext(ctx, `INSERT INTO main.`+qTable+` ("PlotNumber","SiteUnit") VALUES (?,?)`, req.PlotNumber, afterCopy); err != nil {
					return err
				}
				changed = true
			}

			receipt := synthesisSUHistoryReceipt{
				Kind:           "synthesis_su_reassignment",
				ContextID:      contextID,
				Project:        owner.Selection.Project,
				SU:             suName,
				PlotNumber:     req.PlotNumber,
				ExistedBefore:  existedBefore,
				BeforeSiteUnit: beforePtr,
				ExistedAfter:   true,
				AfterSiteUnit:  &afterCopy,
			}
			rawReceipt, mErr := json.Marshal(receipt)
			if mErr != nil {
				return mErr
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, synthesisSUHistoryTable, synthesisSUHistorySQL, string(rawReceipt), "synthesis SU reassignment"); err != nil {
				return err
			}
			_ = tx.QueryRowContext(ctx, `SELECT MAX(ID) FROM main.`+vprocore.QuoteHeaderIdentifier(synthesisSUHistoryTable)).Scan(&historyID)

			if changed {
				appendSynthesisSUAuditRow(ctx, tx, owner, plots, req.PlotNumber, beforePtr, afterCopy)
			}

			if err := validateFiles(); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			postStamp, postOK := statDBFileWithWAL(owner.Selection.ProjectPath)
			advanceProjectPlotsCacheStamp(owner.Selection.Project, preStamp, postStamp, preOK && postOK)
			return nil
		})
		if err != nil {
			return nil, err
		}

		recomputeOpts := req.Options
		if recomputeOpts.UnitSource == "" {
			recomputeOpts.UnitSource = "su"
		}
		snap, snapErr := computeSnapshotForPlots(ctx, owner, contextID, recomputeOpts)
		_ = snapErr // Commit already succeeded; return committed receipt even if optional refresh was cancelled.

		latencyMs := float64(time.Since(started).Microseconds()) / 1000.0
		return &ReassignSynthesisPlotResult{
			ContextID:      contextID,
			SU:             suName,
			TableName:      suTable,
			PlotNumber:     req.PlotNumber,
			BeforeSiteUnit: beforeUnit,
			AfterSiteUnit:  targetUnit,
			Changed:        changed,
			HistoryID:      historyID,
			LatencyMs:      RoundACE15(latencyMs, 2),
			Snapshot:       snap,
		}, nil
	})
}

// UndoSynthesisReassignment reverses the latest (or specified HistoryID) synthesis SU plot reassignment
// in __VPRO_SynthesisSUHistory and immediately recomputes the updated SynthesisSnapshot.
func UndoSynthesisReassignment(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	req UndoSynthesisReassignmentRequest,
) (*ReassignSynthesisPlotResult, error) {
	started := time.Now()
	if ctx == nil {
		return nil, errors.New("synthesis undo requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ReassignSynthesisPlotResult, error) {
		owner := plots.Projects.Sqlite
		var suName, suTable string
		validateFiles := func() error {
			var err error
			suName, suTable, err = validateWritableSUTarget(owner)
			return err
		}

		var undonePlot, beforeUnit, afterUnit string
		var undoHistoryID int64

		err := owner.WithSelectedFileWriter(ctx, "su", validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			preStamp, preOK := statDBFileWithWAL(owner.Selection.ProjectPath)
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			var hasHistory bool
			if err := tx.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM main.sqlite_master WHERE type='table' AND name=?)`,
				synthesisSUHistoryTable,
			).Scan(&hasHistory); err != nil || !hasHistory {
				return errors.New("no synthesis SU reassignment history exists for the active SU")
			}

			rows, err := tx.QueryContext(ctx,
				`SELECT ID, Proposal FROM main.`+vprocore.QuoteHeaderIdentifier(synthesisSUHistoryTable)+` ORDER BY ID ASC`)
			if err != nil {
				return err
			}
			type histRow struct {
				id  int64
				rec synthesisSUHistoryReceipt
			}
			var items []histRow
			undoneSet := map[int64]bool{}
			for rows.Next() {
				var id int64
				var prop string
				if sErr := rows.Scan(&id, &prop); sErr != nil {
					rows.Close()
					return sErr
				}
				var rec synthesisSUHistoryReceipt
				if err := json.Unmarshal([]byte(prop), &rec); err != nil || !strings.EqualFold(rec.SU, suName) {
					continue
				}
				switch rec.Kind {
				case "synthesis_su_reassignment":
					items = append(items, histRow{id: id, rec: rec})
				case "synthesis_su_reassignment_undo":
					if rec.UndoneHistoryID > 0 {
						undoneSet[rec.UndoneHistoryID] = true
					}
				}
			}
			if err := errors.Join(rows.Err(), rows.Close()); err != nil {
				return err
			}

			var target *histRow
			if req.HistoryID > 0 {
				for i := range items {
					if items[i].id == req.HistoryID {
						if undoneSet[items[i].id] {
							return fmt.Errorf("synthesis history #%d has already been undone", req.HistoryID)
						}
						target = &items[i]
						break
					}
				}
				if target == nil {
					return fmt.Errorf("synthesis history #%d not found for SU %s", req.HistoryID, suName)
				}
			} else {
				for i := len(items) - 1; i >= 0; i-- {
					if !undoneSet[items[i].id] {
						target = &items[i]
						break
					}
				}
				if target == nil {
					return errors.New("no reversible synthesis reassignment remaining on undo stack")
				}
			}

			qTable := vprocore.QuoteHeaderIdentifier(suTable)
			d := target.rec
			undonePlot = d.PlotNumber
			if d.AfterSiteUnit != nil {
				beforeUnit = *d.AfterSiteUnit
			}
			if d.BeforeSiteUnit != nil {
				afterUnit = *d.BeforeSiteUnit
			}

			var currentSU sql.NullString
			curErr := tx.QueryRowContext(ctx,
				`SELECT "SiteUnit" FROM main.`+qTable+` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
				d.PlotNumber, d.PlotNumber,
			).Scan(&currentSU)
			if curErr != nil && !errors.Is(curErr, sql.ErrNoRows) {
				return curErr
			}
			expectedAfter := ""
			if d.AfterSiteUnit != nil {
				expectedAfter = strings.TrimSpace(*d.AfterSiteUnit)
			}
			actualCurrent := ""
			if curErr == nil && currentSU.Valid {
				actualCurrent = strings.TrimSpace(currentSU.String)
			}
			if errors.Is(curErr, sql.ErrNoRows) || actualCurrent != expectedAfter {
				return fmt.Errorf("plot %q SiteUnit changed since reassignment (%q != %q); undo refused", d.PlotNumber, actualCurrent, expectedAfter)
			}

			if !d.ExistedBefore {
				if _, err := tx.ExecContext(ctx,
					`DELETE FROM main.`+qTable+` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
					d.PlotNumber, d.PlotNumber,
				); err != nil {
					return err
				}
			} else {
				var existingRowID int64
				rErr := tx.QueryRowContext(ctx,
					`SELECT rowid FROM main.`+qTable+` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
					d.PlotNumber, d.PlotNumber,
				).Scan(&existingRowID)
				if errors.Is(rErr, sql.ErrNoRows) {
					if _, err := tx.ExecContext(ctx,
						`INSERT INTO main.`+qTable+` ("PlotNumber","SiteUnit") VALUES (?,?)`,
						d.PlotNumber, d.BeforeSiteUnit,
					); err != nil {
						return err
					}
				} else if rErr != nil {
					return rErr
				} else {
					if _, err := tx.ExecContext(ctx,
						`UPDATE main.`+qTable+` SET "SiteUnit" = ? WHERE rowid = ?`,
						d.BeforeSiteUnit, existingRowID,
					); err != nil {
						return err
					}
				}
			}

			undoRec := synthesisSUHistoryReceipt{
				Kind:            "synthesis_su_reassignment_undo",
				ContextID:       contextID,
				Project:         owner.Selection.Project,
				SU:              suName,
				PlotNumber:      d.PlotNumber,
				ExistedBefore:   d.ExistedAfter,
				BeforeSiteUnit:  d.AfterSiteUnit,
				ExistedAfter:    d.ExistedBefore,
				AfterSiteUnit:   d.BeforeSiteUnit,
				UndoneHistoryID: target.id,
			}
			rawUndo, err := json.Marshal(undoRec)
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, synthesisSUHistoryTable, synthesisSUHistorySQL, string(rawUndo), "synthesis SU reassignment undo"); err != nil {
				return err
			}
			_ = tx.QueryRowContext(ctx, `SELECT MAX(ID) FROM main.`+vprocore.QuoteHeaderIdentifier(synthesisSUHistoryTable)).Scan(&undoHistoryID)

			if !d.ExistedAfter || !d.ExistedBefore || d.AfterSiteUnit != d.BeforeSiteUnit {
				var undoBeforePtr, undoAfterPtr any
				if d.ExistedAfter {
					v := d.AfterSiteUnit
					undoBeforePtr = v
				}
				if d.ExistedBefore {
					v := d.BeforeSiteUnit
					undoAfterPtr = v
				}
				appendSynthesisSUAuditRow(ctx, tx, owner, plots, d.PlotNumber, undoBeforePtr, undoAfterPtr)
			}

			if err := validateFiles(); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			postStamp, postOK := statDBFileWithWAL(owner.Selection.ProjectPath)
			advanceProjectPlotsCacheStamp(owner.Selection.Project, preStamp, postStamp, preOK && postOK)
			return nil
		})
		if err != nil {
			return nil, err
		}

		recomputeOpts := req.Options
		if recomputeOpts.UnitSource == "" {
			recomputeOpts.UnitSource = "su"
		}
		snap, err := computeSnapshotForPlots(ctx, owner, contextID, recomputeOpts)
		if err != nil {
			return nil, err
		}

		latencyMs := float64(time.Since(started).Microseconds()) / 1000.0
		return &ReassignSynthesisPlotResult{
			ContextID:      contextID,
			SU:             suName,
			TableName:      suTable,
			PlotNumber:     undonePlot,
			BeforeSiteUnit: beforeUnit,
			AfterSiteUnit:  afterUnit,
			Changed:        true,
			HistoryID:      undoHistoryID,
			LatencyMs:      RoundACE15(latencyMs, 2),
			Snapshot:       snap,
		}, nil
	})
}

func appendSynthesisSUAuditRow(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	plots *vprocore.PlotService,
	plotNumber string,
	before any,
	after any,
) {
	if !vprocore.SameDesktopPath(owner.Selection.ProjectPath, owner.Selection.SUPath) {
		return
	}
	actor := strings.TrimSpace(plots.CurrentUser)
	if actor == "" {
		actor = "VProUser"
	}
	qAudit := vprocore.QuoteHeaderIdentifier(owner.Selection.Project + "_Audit")
	_, _ = tx.ExecContext(ctx,
		`INSERT INTO main.`+qAudit+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag") VALUES (?,?,?,?,?,?,?,?,0,0)`,
		owner.Selection.Project, actor, plotNumber, "_SU", "SiteUnit", time.Now().Format("2006-01-02 15:04:05"), before, after,
	)
}
