package projectops

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type sqliteMergeExecutor struct {
	ctx                context.Context
	tx                 *sql.Tx
	auditStmt          *sql.Stmt
	req                ThreeWayMergeExecuteRequest
	srcProj            string
	tgtProj            string
	tgtPath            string
	actor              string
	now                string
	srcSnap            *loadedProjectSnapshot
	tgtSnap            *loadedProjectSnapshot
	resolveDecision    func(MergeConflictItem) string
	allocatedIDs       []int64
	reservedDeletedIDs []int64
	addedPlots         int
	updatedPlots       int
	skippedPlots       int
	deletedPlots       int
	auditRows          int
}

// ExecuteThreeWayMerge applies Staging.db -> Target.db changes inside a single atomic
// BEGIN IMMEDIATE transaction on Target.db, honoring per-plot and per-field conflict
// resolutions ('keep_target' | 'accept_source'), allocating monotonic child IDs via
// __VPRO_ChildIdentity without reusing deleted IDs, and recording full <Target>_Audit entries.
func ExecuteThreeWayMerge(s *vprocore.ContextService, ctx context.Context, contextID string, req ThreeWayMergeExecuteRequest) (ThreeWayMergeResult, error) {
	defaultRes, err := validateThreeWayMergeRequest(req)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}

	srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor, err := resolveMergeEndpoints(
		ctx, s, contextID,
		req.SourcePath, req.SourceProject,
		req.TargetPath, req.TargetProject,
		req.BasePath, req.BaseProject,
	)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}

	resolveDecision := buildThreeWayDecisionResolver(req, defaultRes)
	runOnConn := func(conn *sql.Conn) (ThreeWayMergeResult, error) {
		return runThreeWayMergeOnConn(ctx, conn, req, srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor, resolveDecision)
	}

	if s != nil {
		if contextID != "" {
			if _, lockErr := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
				return struct{}{}, plots.CheckEditLockForProject(tgtProj)
			}); lockErr != nil {
				return ThreeWayMergeResult{}, lockErr
			}
		} else if s.Plots != nil {
			if lockErr := s.Plots.CheckEditLockForProject(tgtProj); lockErr != nil {
				return ThreeWayMergeResult{}, lockErr
			}
		}
	}

	// If merging into the active context's project database, acquire the ContextService writer lease!
	if s != nil && contextID != "" {
		snap, sErr := inspectContextSnapshot(ctx, s, contextID)
		if sErr == nil && vprocore.SameDesktopPath(tgtPath, snap.ProjectPath) {
			var res ThreeWayMergeResult
			editErr := s.Edit(contextID, func(plots *vprocore.PlotService) error {
				return plots.Projects.Sqlite.WithMetadataWriter(ctx, func(conn *sql.Conn) error {
					var mErr error
					res, mErr = runOnConn(conn)
					return mErr
				})
			})
			return res, editErr
		}
	}

	db, err := sqlutil.OpenWALWriteSQLite(tgtPath)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	defer db.Close()
	conn, err := db.Conn(ctx)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	defer conn.Close()
	return runOnConn(conn)
}

func validateThreeWayMergeRequest(req ThreeWayMergeExecuteRequest) (string, error) {
	defaultRes := strings.TrimSpace(req.DefaultConflictResolution)
	if defaultRes == "" {
		defaultRes = MergeResolutionKeepTarget
	}
	if err := validateMergeResolutionChoice(defaultRes); err != nil {
		return "", err
	}
	if err := validateResolutionMap(req.PlotResolutions, "plot resolution key must not be empty"); err != nil {
		return "", err
	}
	if err := validateResolutionMap(req.FieldResolutions, "field resolution key must not be empty"); err != nil {
		return "", err
	}
	return defaultRes, nil
}

func validateResolutionMap(m map[string]string, emptyKeyMsg string) error {
	for k, v := range m {
		if k == "" {
			return errors.New(emptyKeyMsg)
		}
		if err := validateMergeResolutionChoice(v); err != nil {
			return err
		}
	}
	return nil
}

func buildThreeWayDecisionResolver(req ThreeWayMergeExecuteRequest, defaultRes string) func(MergeConflictItem) string {
	return func(item MergeConflictItem) string {
		if choice, ok := req.FieldResolutions[item.ConflictID]; ok {
			return choice
		}
		if choice, ok := req.PlotResolutions[item.PlotNumber]; ok {
			return choice
		}
		if item.Kind == "FastForward" || item.Kind == "TargetModifiedOnly" || item.Kind == "SourceDelete" {
			return item.DefaultResolution
		}
		return defaultRes
	}
}

func runThreeWayMergeOnConn(
	ctx context.Context,
	conn *sql.Conn,
	req ThreeWayMergeExecuteRequest,
	srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor string,
	resolveDecision func(MergeConflictItem) string,
) (ThreeWayMergeResult, error) {
	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	var txErr error
	defer func() {
		if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
			txErr = errors.Join(txErr, rb)
		}
	}()

	preview, srcSnap, tgtSnap, _, pErr := buildThreeWayMergePreviewInternal(ctx, srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, tx, req.CaseInsensitiveText)
	if pErr != nil {
		return ThreeWayMergeResult{}, pErr
	}
	if exp := strings.TrimSpace(req.ExpectedPreviewDigest); exp != "" && exp != preview.PreviewDigest {
		return ThreeWayMergeResult{}, errors.New("source or target database changed since preview; re-run PreviewThreeWayMerge before executing")
	}
	if err := ensureChildIdentityTable(ctx, tx); err != nil {
		return ThreeWayMergeResult{}, err
	}

	auditTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_Audit")
	auditStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+auditTbl+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`)
	if err != nil {
		return ThreeWayMergeResult{}, err
	}
	defer auditStmt.Close()

	exec := &sqliteMergeExecutor{
		ctx:             ctx,
		tx:              tx,
		auditStmt:       auditStmt,
		req:             req,
		srcProj:         srcProj,
		tgtProj:         tgtProj,
		tgtPath:         tgtPath,
		actor:           actor,
		now:             time.Now().Format("2006-01-02 15:04:05"),
		srcSnap:         srcSnap,
		tgtSnap:         tgtSnap,
		resolveDecision: resolveDecision,
	}

	for _, plotPlan := range preview.Plots {
		if err := ctx.Err(); err != nil {
			return ThreeWayMergeResult{}, err
		}
		if err := exec.applyPlotPlan(plotPlan); err != nil {
			return ThreeWayMergeResult{}, err
		}
	}

	if err := applyThreeWayMergeMetadata(
		ctx, tx, auditStmt, tgtProj, actor, exec.now, srcSnap, tgtSnap,
		preview.MetadataItems, resolveDecision, &exec.allocatedIDs, &exec.reservedDeletedIDs, &exec.auditRows,
	); err != nil {
		return ThreeWayMergeResult{}, err
	}

	if err := ctx.Err(); err != nil {
		return ThreeWayMergeResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return ThreeWayMergeResult{}, err
	}
	return exec.buildResult(), txErr
}

func (e *sqliteMergeExecutor) buildResult() ThreeWayMergeResult {
	slices.Sort(e.allocatedIDs)
	slices.Sort(e.reservedDeletedIDs)
	e.reservedDeletedIDs = slices.Compact(e.reservedDeletedIDs)
	return ThreeWayMergeResult{
		SourceProject:      e.srcProj,
		TargetProject:      e.tgtProj,
		TargetPath:         e.tgtPath,
		AddedPlots:         e.addedPlots,
		UpdatedPlots:       e.updatedPlots,
		SkippedPlots:       e.skippedPlots,
		DeletedPlots:       e.deletedPlots,
		AllocatedChildIDs:  e.allocatedIDs,
		ReservedDeletedIDs: e.reservedDeletedIDs,
		AuditRowsWritten:   e.auditRows,
	}
}

func (e *sqliteMergeExecutor) applyPlotPlan(plotPlan MergePlotPreview) error {
	plot := plotPlan.PlotNumber
	switch plotPlan.Category {
	case "Identical", "TargetOnly":
		e.skippedPlots++
		return nil
	case "Added":
		if choice, ok := e.req.PlotResolutions[plot]; ok && choice == MergeResolutionKeepTarget {
			e.skippedPlots++
			return nil
		}
		if err := e.insertWholePlotFromSource(plot); err != nil {
			return err
		}
		e.addedPlots++
		return nil
	case "SourceDelete":
		if len(plotPlan.Items) == 1 && e.resolveDecision(plotPlan.Items[0]) == MergeResolutionAcceptSource {
			if err := e.deleteWholePlotFromTarget(plot); err != nil {
				return err
			}
			e.deletedPlots++
		} else {
			e.skippedPlots++
		}
		return nil
	case "FastForward", "Conflict":
		return e.applyPlotItems(plot, plotPlan.Items)
	default:
		return nil
	}
}

func (e *sqliteMergeExecutor) applyPlotItems(plot string, items []MergeConflictItem) error {
	handled, err := e.tryApplyWholePlotMembershipDelta(plot, items)
	if handled || err != nil {
		return err
	}
	plotModified := false
	for _, item := range items {
		if e.resolveDecision(item) != MergeResolutionAcceptSource {
			continue
		}
		if err := e.applyAcceptedMergeItem(plot, item); err != nil {
			return err
		}
		plotModified = true
	}
	if plotModified {
		e.updatedPlots++
	} else {
		e.skippedPlots++
	}
	return nil
}

func (e *sqliteMergeExecutor) tryApplyWholePlotMembershipDelta(plot string, items []MergeConflictItem) (bool, error) {
	if len(items) != 1 || items[0].Key != "Plot" {
		return false, nil
	}
	if !e.tgtSnap.plots[plot] && e.srcSnap.plots[plot] {
		if e.resolveDecision(items[0]) == MergeResolutionAcceptSource {
			if err := e.insertWholePlotFromSource(plot); err != nil {
				return true, err
			}
			e.addedPlots++
		} else {
			e.skippedPlots++
		}
		return true, nil
	}
	if e.tgtSnap.plots[plot] && !e.srcSnap.plots[plot] {
		if e.resolveDecision(items[0]) == MergeResolutionAcceptSource {
			if err := e.deleteWholePlotFromTarget(plot); err != nil {
				return true, err
			}
			e.deletedPlots++
		} else {
			e.skippedPlots++
		}
		return true, nil
	}
	return false, nil
}

func (e *sqliteMergeExecutor) applyAcceptedMergeItem(plot string, item MergeConflictItem) error {
	suffix := item.Table
	if suffix == "Env" || suffix == "Admin" {
		return e.applyHeaderFieldUpdate(plot, suffix, item)
	}
	if item.Field == "*" {
		return e.applyChildWildcardChange(plot, suffix, item)
	}
	return e.applyChildFieldUpdate(plot, suffix, item)
}

func (e *sqliteMergeExecutor) applyHeaderFieldUpdate(plot, suffix string, item MergeConflictItem) error {
	quotedTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_" + suffix)
	keyCol := "PlotNumber"
	if suffix == "Admin" {
		keyCol = "Plot"
	}
	srcCell := e.srcSnap.rawCells[suffix][plot][suffix][item.Field]
	if err := validateMergedCell(suffix, item.Field, srcCell); err != nil {
		return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, item.Field, err)
	}
	param := normalizeMergedParam(suffix, item.Field, srcCell)
	qKey := vprocore.QuoteHeaderIdentifier(keyCol)
	uRes, err := e.tx.ExecContext(e.ctx, `UPDATE `+quotedTbl+` SET `+vprocore.QuoteHeaderIdentifier(item.Field)+
		` = ? WHERE typeof(`+qKey+`)='text' AND CAST(`+qKey+` AS BLOB)=CAST(? AS BLOB)`,
		param, plot)
	if err != nil {
		return err
	}
	if n, _ := uRes.RowsAffected(); n != 1 {
		return fmt.Errorf("merge update on %s.%s for plot %s matched %d rows", suffix, item.Field, plot, n)
	}
	return e.recordFieldAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, nil)
}

func (e *sqliteMergeExecutor) applyChildWildcardChange(plot, suffix string, item MergeConflictItem) error {
	if item.SourceVal != nil && item.TargetVal == nil {
		sKey := item.srcRowKey
		if sKey == "" {
			sKey = item.Key
		}
		return e.insertPlotChildRow(suffix, plot, e.srcSnap.rawCells[suffix][plot][sKey])
	}
	if item.SourceVal == nil && item.TargetVal != nil {
		tKey := item.tgtRowKey
		if tKey == "" {
			tKey = item.Key
		}
		return e.deletePlotChildRow(suffix, plot, e.tgtSnap.rawCells[suffix][plot][tKey])
	}
	return nil
}

func (e *sqliteMergeExecutor) deletePlotChildRow(suffix, plot string, tgtRow map[string]rawSQLiteCell) error {
	idCell := tgtRow["ID"]
	if idCell.storage != "integer" {
		return fmt.Errorf("cannot delete target %s row in plot %s without integer ID", suffix, plot)
	}
	targetID := idCell.intVal
	if targetID > 0 {
		if err := reserveChildID(e.ctx, e.tx, e.tgtProj+"_"+suffix, targetID); err != nil {
			return err
		}
		e.reservedDeletedIDs = append(e.reservedDeletedIDs, targetID)
	}
	quotedTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_" + suffix)
	dRes, err := e.tx.ExecContext(e.ctx, `DELETE FROM `+quotedTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`, plot, targetID)
	if err != nil {
		return err
	}
	if n, _ := dRes.RowsAffected(); n != 1 {
		return fmt.Errorf("merge child delete on %s (plot %s, ID %d) matched %d rows", suffix, plot, targetID, n)
	}
	for _, col := range e.tgtSnap.columns[suffix] {
		if col == "PlotNumber" || col == "ID" {
			continue
		}
		oldCell := tgtRow[col]
		if oldCell.storage == "null" || (col == "Flag" && oldCell.storage == "integer" && oldCell.intVal == 0) {
			continue
		}
		if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, plot, "_"+suffix, col, e.now, auditTextForRawCell(oldCell), nil, targetID); err != nil {
			return err
		}
		e.auditRows++
	}
	return nil
}

func (e *sqliteMergeExecutor) applyChildFieldUpdate(plot, suffix string, item MergeConflictItem) error {
	idx := strings.LastIndex(item.Key, ".")
	if idx <= 0 {
		return fmt.Errorf("malformed child diff key %q", item.Key)
	}
	rowKey := item.Key[:idx]
	sKey := item.srcRowKey
	if sKey == "" {
		sKey = rowKey
	}
	tKey := item.tgtRowKey
	if tKey == "" {
		tKey = rowKey
	}
	srcCell := e.srcSnap.rawCells[suffix][plot][sKey][item.Field]
	tgtRow := e.tgtSnap.rawCells[suffix][plot][tKey]
	idCell := tgtRow["ID"]
	if idCell.storage != "integer" {
		return fmt.Errorf("target %s row in plot %s lacks integer ID for field merge", suffix, plot)
	}
	if err := validateMergedCell(suffix, item.Field, srcCell); err != nil {
		return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, item.Field, err)
	}
	param := normalizeMergedParam(suffix, item.Field, srcCell)
	quotedTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_" + suffix)
	uRes, err := e.tx.ExecContext(e.ctx, `UPDATE `+quotedTbl+` SET `+vprocore.QuoteHeaderIdentifier(item.Field)+
		` = ? WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "ID" = ?`,
		param, plot, idCell.intVal)
	if err != nil {
		return err
	}
	if n, _ := uRes.RowsAffected(); n != 1 {
		return fmt.Errorf("merge child update on %s.%s (plot %s, ID %d) matched %d rows", suffix, item.Field, plot, idCell.intVal, n)
	}
	idCopy := idCell.intVal
	return e.recordFieldAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, &idCopy)
}

func (e *sqliteMergeExecutor) recordFieldAudit(plot, suffix, field string, targetVal, sourceVal *string, childID *int64) error {
	var beforeVal, afterVal, idAny any
	if targetVal != nil {
		beforeVal = *targetVal
	}
	if sourceVal != nil {
		afterVal = *sourceVal
	}
	if childID != nil {
		idAny = *childID
	}
	if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, plot, "_"+suffix, field, e.now, beforeVal, afterVal, idAny); err != nil {
		return err
	}
	e.auditRows++
	return nil
}

func (e *sqliteMergeExecutor) deleteWholePlotFromTarget(plot string) error {
	// Reserve child IDs before deleting rows in FK order (children -> Admin -> Env).
	for _, suffix := range []string{"Other", "Mineral", "Humus", "Veg"} {
		if err := e.reserveAndDeletePlotChildren(suffix, plot); err != nil {
			return err
		}
	}
	adminTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_Admin")
	if _, err := e.tx.ExecContext(e.ctx, `DELETE FROM `+adminTbl+` WHERE typeof("Plot")='text' AND CAST("Plot" AS BLOB)=CAST(? AS BLOB)`, plot); err != nil {
		return err
	}
	envTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_Env")
	dRes, err := e.tx.ExecContext(e.ctx, `DELETE FROM `+envTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`, plot)
	if err != nil {
		return err
	}
	if n, _ := dRes.RowsAffected(); n != 1 {
		return fmt.Errorf("merge plot delete on %s matched %d Env rows", plot, n)
	}
	// Record deletion provenance with PlotNumber=NULL so ON DELETE CASCADE on _Env neither
	// cascades out the deletion audit trail nor triggers FK error after _Env removal.
	if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, nil, "_Env", "PlotNumber", e.now, plot, nil, nil); err != nil {
		return err
	}
	e.auditRows++
	return nil
}

func (e *sqliteMergeExecutor) reserveAndDeletePlotChildren(suffix, plot string) error {
	tgtChildRows := e.tgtSnap.rawCells[suffix][plot]
	keys := make([]string, 0, len(tgtChildRows))
	for k := range tgtChildRows {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	for _, rk := range keys {
		if idCell := tgtChildRows[rk]["ID"]; idCell.storage == "integer" && idCell.intVal > 0 {
			if err := reserveChildID(e.ctx, e.tx, e.tgtProj+"_"+suffix, idCell.intVal); err != nil {
				return err
			}
			e.reservedDeletedIDs = append(e.reservedDeletedIDs, idCell.intVal)
		}
	}
	qTbl := vprocore.QuoteHeaderIdentifier(e.tgtProj + "_" + suffix)
	_, err := e.tx.ExecContext(e.ctx, `DELETE FROM `+qTbl+` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`, plot)
	return err
}

func (e *sqliteMergeExecutor) insertWholePlotFromSource(plot string) error {
	if err := sqlutil.ValidateUTF16Bound("PlotNumber", plot, 7); err != nil {
		return err
	}
	for _, suffix := range []string{"Env", "Admin"} {
		if err := e.insertPlotHeaderTableRow(suffix, plot); err != nil {
			return err
		}
	}
	for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other"} {
		srcChildRows := e.srcSnap.rawCells[suffix][plot]
		keys := make([]string, 0, len(srcChildRows))
		for k := range srcChildRows {
			keys = append(keys, k)
		}
		slices.Sort(keys)
		for _, rk := range keys {
			if err := e.insertPlotChildRow(suffix, plot, srcChildRows[rk]); err != nil {
				return err
			}
		}
	}
	return nil
}

func (e *sqliteMergeExecutor) insertPlotHeaderTableRow(suffix, plot string) error {
	srcRaw, ok := e.srcSnap.rawCells[suffix][plot][suffix]
	if !ok {
		return fmt.Errorf("source plot %s is missing required %s row", plot, suffix)
	}
	cols := e.tgtSnap.columns[suffix]
	quotedCols := make([]string, len(cols))
	marks := make([]string, len(cols))
	args := make([]any, len(cols))
	keyCol := "PlotNumber"
	if suffix == "Admin" {
		keyCol = "Plot"
	}
	for i, col := range cols {
		quotedCols[i] = vprocore.QuoteHeaderIdentifier(col)
		marks[i] = "?"
		if col == keyCol {
			args[i] = plot
		} else {
			cell := srcRaw[col]
			if err := validateMergedCell(suffix, col, cell); err != nil {
				return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, col, err)
			}
			args[i] = normalizeMergedParam(suffix, col, cell)
		}
	}
	insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
		vprocore.QuoteHeaderIdentifier(e.tgtProj+"_"+suffix),
		strings.Join(quotedCols, ", "),
		strings.Join(marks, ", "),
	)
	if _, err := e.tx.ExecContext(e.ctx, insSQL, args...); err != nil {
		return err
	}
	for _, col := range cols {
		if col == keyCol {
			if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, plot, "_"+suffix, col, e.now, nil, plot, nil); err != nil {
				return err
			}
			e.auditRows++
			continue
		}
		c := srcRaw[col]
		if c.storage == "null" {
			continue
		}
		if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, plot, "_"+suffix, col, e.now, nil, auditTextForRawCell(c), nil); err != nil {
			return err
		}
		e.auditRows++
	}
	return nil
}

func (e *sqliteMergeExecutor) insertPlotChildRow(suffix, plot string, srcRaw map[string]rawSQLiteCell) error {
	cols := e.tgtSnap.columns[suffix]
	newID, err := allocateSafeChildID(e.ctx, e.tx, e.tgtProj, suffix)
	if err != nil {
		return err
	}
	e.allocatedIDs = append(e.allocatedIDs, newID)

	quotedCols := make([]string, len(cols))
	marks := make([]string, len(cols))
	args := make([]any, len(cols))
	for i, col := range cols {
		quotedCols[i] = vprocore.QuoteHeaderIdentifier(col)
		marks[i] = "?"
		switch col {
		case "PlotNumber":
			args[i] = plot
		case "ID":
			args[i] = newID
		default:
			cell := srcRaw[col]
			if err := validateMergedCell(suffix, col, cell); err != nil {
				return fmt.Errorf("plot %s %s.%s: %w", plot, suffix, col, err)
			}
			args[i] = normalizeMergedParam(suffix, col, cell)
		}
	}
	insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
		vprocore.QuoteHeaderIdentifier(e.tgtProj+"_"+suffix),
		strings.Join(quotedCols, ", "),
		strings.Join(marks, ", "),
	)
	if _, err := e.tx.ExecContext(e.ctx, insSQL, args...); err != nil {
		return err
	}
	for _, col := range cols {
		if col == "PlotNumber" || col == "ID" {
			continue
		}
		c := srcRaw[col]
		if c.storage == "null" || (col == "Flag" && c.storage == "integer" && c.intVal == 0) {
			continue
		}
		if _, err := e.auditStmt.ExecContext(e.ctx, e.tgtProj, e.actor, plot, "_"+suffix, col, e.now, nil, auditTextForRawCell(c), newID); err != nil {
			return err
		}
		e.auditRows++
	}
	return nil
}
