package cloudsync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var cloudMergePGTableBySuffix = map[string]string{
	"Env":     "env",
	"Admin":   "admin",
	"Veg":     "veg",
	"Humus":   "humus",
	"Mineral": "mineral",
	"Other":   "other",
}

type touchedCloudHorizonKey struct {
	suffix string
	plot   string
	rowKey string
}

type cloudStagingMergeExecutor struct {
	ctx                context.Context
	tx                 pgx.Tx
	creds              *ResolvedCredentials
	req                StagingMergeExecuteRequest
	subID              string
	actor              string
	mergeTxID          string
	nowEditStr         string
	nowUTC             time.Time
	preview            StagingMergePreview
	srcSnap            *cloudSnapshot
	tgtSnap            *cloudSnapshot
	srcSHA             string
	resolveChoice      func(CloudMergeConflictItem) string
	pendingAudits      [][]any
	allocatedIDs       []int64
	reservedDeletedIDs []int64
	addedPlots         int
	updatedPlots       int
	skippedPlots       int
}

// ExecuteStagingToMasterMerge commits selective staging -> becmaster changes inside a single
// SERIALIZABLE PostgreSQL transaction with optimistic preview digest lock and hash-chained audit provenance.
func (m *Manager) ExecuteStagingToMasterMerge(ctx context.Context, req StagingMergeExecuteRequest) (StagingMergeResult, error) {
	subID, defaultRes, err := validateStagingMergeRequest(req)
	if err != nil {
		return StagingMergeResult{}, err
	}
	resolveChoice := buildCloudMergeChoiceResolver(req, defaultRes)

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

	actor, err := lockPendingStagingSubmission(ctx, tx, subID, req.Actor, creds)
	if err != nil {
		return StagingMergeResult{}, err
	}

	preview, srcSnap, tgtSnap, srcSHA, err := buildStagingMergePreviewOnQueryer(ctx, tx, subID, req.BaseDBPath, req.BaseProject)
	if err != nil {
		return StagingMergeResult{}, wrapRedactedError("re-verify merge preview inside SERIALIZABLE transaction", err, creds)
	}
	if preview.PreviewDigest != strings.TrimSpace(req.ExpectedPreviewDigest) {
		return StagingMergeResult{}, errors.New("staging or BECMaster plots changed since preview; re-run PreviewStagingToMasterMerge before merging")
	}

	exec := &cloudStagingMergeExecutor{
		ctx:                ctx,
		tx:                 tx,
		creds:              creds,
		req:                req,
		subID:              subID,
		actor:              actor,
		mergeTxID:          uuid.NewString(),
		nowEditStr:         time.Now().UTC().Format("2006-01-02 15:04:05"),
		nowUTC:             time.Now().UTC(),
		preview:            preview,
		srcSnap:            srcSnap,
		tgtSnap:            tgtSnap,
		srcSHA:             srcSHA,
		resolveChoice:      resolveChoice,
		allocatedIDs:       []int64{},
		reservedDeletedIDs: []int64{},
	}

	return exec.executeAndCommit()
}

func validateStagingMergeRequest(req StagingMergeExecuteRequest) (string, string, error) {
	subID := strings.TrimSpace(req.SubmissionID)
	if _, err := uuid.Parse(subID); err != nil {
		return "", "", errors.New("submissionId must be a valid UUID")
	}
	if strings.TrimSpace(req.ExpectedPreviewDigest) == "" {
		return "", "", errors.New("expectedPreviewDigest is required; run PreviewStagingToMasterMerge first")
	}
	defaultRes := strings.TrimSpace(req.DefaultConflictResolution)
	if defaultRes == "" {
		defaultRes = MergeResolutionKeepTarget
	}
	if err := validateCloudMergeResolution(defaultRes); err != nil {
		return "", "", err
	}
	if err := validateCloudResolutionMap(req.PlotResolutions, "plotResolutions key must not be empty"); err != nil {
		return "", "", err
	}
	if err := validateCloudResolutionMap(req.FieldResolutions, "fieldResolutions key must not be empty"); err != nil {
		return "", "", err
	}
	return subID, defaultRes, nil
}

func validateCloudMergeResolution(c string) error {
	if c != MergeResolutionKeepTarget && c != MergeResolutionAcceptSource {
		return fmt.Errorf("invalid merge resolution %q (expected %q or %q)", c, MergeResolutionKeepTarget, MergeResolutionAcceptSource)
	}
	return nil
}

func validateCloudResolutionMap(m map[string]string, emptyKeyMsg string) error {
	for k, v := range m {
		if k == "" {
			return errors.New(emptyKeyMsg)
		}
		if err := validateCloudMergeResolution(v); err != nil {
			return err
		}
	}
	return nil
}

func buildCloudMergeChoiceResolver(req StagingMergeExecuteRequest, defaultRes string) func(CloudMergeConflictItem) string {
	return func(item CloudMergeConflictItem) string {
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
}

func lockPendingStagingSubmission(
	ctx context.Context,
	tx pgx.Tx,
	subID, requestedActor string,
	creds *ResolvedCredentials,
) (string, error) {
	var curStatus, currentDBUser string
	if err := tx.QueryRow(ctx, `SELECT status, current_user FROM staging.submissions WHERE submission_id = $1 FOR UPDATE`, subID).Scan(&curStatus, &currentDBUser); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", fmt.Errorf("staging submission %s not found", subID)
		}
		return "", wrapRedactedError("lock staging submission", err, creds)
	}
	if curStatus != "pending" {
		return "", fmt.Errorf("staging submission %s has status %q (only 'pending' submissions can be merged)", subID, curStatus)
	}
	if actor := strings.TrimSpace(requestedActor); actor != "" {
		return actor, nil
	}
	return currentDBUser, nil
}

func (e *cloudStagingMergeExecutor) recordAudit(plot, tableSuffix, field string, beforeVal, afterVal *string, childID *int64) {
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
	e.pendingAudits = append(e.pendingAudits, []any{
		"BECMaster", e.actor, plot, "_" + tableSuffix, field, e.nowEditStr,
		bAny, aAny, int16(0), int16(0), idAny,
	})
}

func (e *cloudStagingMergeExecutor) executeAndCommit() (StagingMergeResult, error) {
	for _, plotPlan := range e.preview.Plots {
		if err := e.ctx.Err(); err != nil {
			return StagingMergeResult{}, err
		}
		if err := e.applyPlotPlan(plotPlan); err != nil {
			return StagingMergeResult{}, err
		}
	}

	if e.addedPlots > 0 || e.updatedPlots > 0 {
		if err := e.insertNewMasterMetadata(); err != nil {
			return StagingMergeResult{}, err
		}
	}

	tailHash, err := e.appendHashChainedAudits()
	if err != nil {
		return StagingMergeResult{}, err
	}
	if err := e.recordLedgerAndMarkSubmissionMerged(tailHash); err != nil {
		return StagingMergeResult{}, err
	}
	if err := e.tx.Commit(e.ctx); err != nil {
		return StagingMergeResult{}, wrapRedactedError("commit SERIALIZABLE merge transaction", err, e.creds)
	}

	slices.Sort(e.allocatedIDs)
	slices.Sort(e.reservedDeletedIDs)
	e.reservedDeletedIDs = slices.Compact(e.reservedDeletedIDs)

	return StagingMergeResult{
		MergeTxID:          e.mergeTxID,
		SubmissionID:       e.subID,
		SourceProject:      e.preview.SourceProject,
		AddedPlots:         e.addedPlots,
		UpdatedPlots:       e.updatedPlots,
		SkippedPlots:       e.skippedPlots,
		AllocatedChildIDs:  e.allocatedIDs,
		ReservedDeletedIDs: e.reservedDeletedIDs,
		AuditRowsWritten:   len(e.pendingAudits),
		TailAuditHash:      tailHash,
		MergedAt:           e.nowUTC.Format(time.RFC3339),
	}, nil
}

func (e *cloudStagingMergeExecutor) applyPlotPlan(plotPlan CloudMergePlotPreview) error {
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
		if err := e.insertWholePlot(plot); err != nil {
			return wrapRedactedError("insert added plot "+plot, err, e.creds)
		}
		e.addedPlots++
		return nil
	case "FastForward", "Conflict":
		return e.applyPlotConflictItems(plot, plotPlan.Items)
	default:
		return nil
	}
}

func (e *cloudStagingMergeExecutor) applyPlotConflictItems(plot string, items []CloudMergeConflictItem) error {
	if len(items) == 1 && items[0].Key == "Plot" && !e.tgtSnap.plots[plot] && e.srcSnap.plots[plot] {
		if e.resolveChoice(items[0]) == MergeResolutionAcceptSource {
			if err := e.insertWholePlot(plot); err != nil {
				return wrapRedactedError("re-insert plot "+plot, err, e.creds)
			}
			e.addedPlots++
		} else {
			e.skippedPlots++
		}
		return nil
	}

	plotModified := false
	touchedHorizons := map[string]touchedCloudHorizonKey{}

	for _, item := range items {
		if e.resolveChoice(item) != MergeResolutionAcceptSource {
			continue
		}
		changed, err := e.applyAcceptedCloudItem(plot, item, touchedHorizons)
		if err != nil {
			return err
		}
		if changed {
			plotModified = true
		}
	}

	if err := e.verifyTouchedHorizonDepths(touchedHorizons); err != nil {
		return err
	}
	if plotModified {
		e.updatedPlots++
	} else {
		e.skippedPlots++
	}
	return nil
}

func (e *cloudStagingMergeExecutor) applyAcceptedCloudItem(
	plot string,
	item CloudMergeConflictItem,
	touchedHorizons map[string]touchedCloudHorizonKey,
) (bool, error) {
	suffix := item.Table
	if suffix == "Env" || suffix == "Admin" {
		return e.applyHeaderMergeItem(plot, suffix, item)
	}
	if item.Field == "*" {
		return e.applyChildWildcardMergeItem(plot, suffix, item)
	}
	return true, e.applyChildFieldMergeItem(plot, suffix, item, touchedHorizons)
}

func (e *cloudStagingMergeExecutor) applyHeaderMergeItem(plot, suffix string, item CloudMergeConflictItem) (bool, error) {
	pgTbl := cloudMergePGTableBySuffix[suffix]
	keyCol := "PlotNumber"
	if suffix == "Admin" {
		keyCol = "Plot"
	}
	if item.Field == "*" {
		if item.SourceVal == nil || item.TargetVal != nil {
			return false, nil
		}
		srcRow := e.srcSnap.rawCells[suffix][plot+"\x00"+suffix]
		if err := e.execHeaderRowInsert(suffix, pgTbl, keyCol, plot, srcRow); err != nil {
			return false, err
		}
		pCopy := plot
		e.recordAudit(plot, suffix, keyCol, nil, &pCopy, nil)
		return true, nil
	}
	colSpec, ok := lookupVP08ColumnSpec(suffix, item.Field)
	if !ok {
		return false, fmt.Errorf("unknown column %s.%s", suffix, item.Field)
	}
	srcCell := e.srcSnap.rawCells[suffix][plot+"\x00"+suffix][item.Field]
	if err := validateCloudMergeCell(suffix, colSpec, srcCell); err != nil {
		return false, fmt.Errorf("plot %s: %w", plot, err)
	}
	tag, err := e.tx.Exec(e.ctx, fmt.Sprintf(
		`UPDATE becmaster.%s SET %s = $1 WHERE %s = $2`,
		quotePGIdent(pgTbl), quotePGIdent(item.Field), quotePGIdent(keyCol),
	), srcCell.pgParam(colSpec), plot)
	if err != nil {
		return false, wrapRedactedError("update "+suffix+"."+item.Field, err, e.creds)
	}
	if tag.RowsAffected() != 1 {
		return false, fmt.Errorf("merge update on %s.%s for plot %s matched %d rows", suffix, item.Field, plot, tag.RowsAffected())
	}
	e.recordAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, nil)
	return true, nil
}

func (e *cloudStagingMergeExecutor) execHeaderRowInsert(
	suffix, pgTbl, keyCol, plot string,
	srcRow map[string]cloudCell,
) error {
	cols := VP08ColumnsBySuffix(suffix)
	placeholders := make([]string, len(cols))
	args := make([]any, len(cols))
	for i, col := range cols {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
		if col.Name == keyCol {
			args[i] = plot
		} else {
			c := srcRow[col.Name]
			if err := validateCloudMergeCell(suffix, col, c); err != nil {
				return fmt.Errorf("plot %s: %w", plot, err)
			}
			args[i] = c.pgParam(col)
		}
	}
	_, err := e.tx.Exec(e.ctx, fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
		quotePGIdent(pgTbl), quotedColumnCSV(cols), strings.Join(placeholders, ", ")), args...)
	if err != nil {
		return wrapRedactedError("insert missing "+suffix, err, e.creds)
	}
	return nil
}

func (e *cloudStagingMergeExecutor) applyChildWildcardMergeItem(plot, suffix string, item CloudMergeConflictItem) (bool, error) {
	if item.SourceVal != nil && item.TargetVal == nil {
		srcRow := e.srcSnap.rawCells[suffix][plot+"\x00"+item.Key]
		if err := e.insertChildRow(suffix, plot, srcRow); err != nil {
			return false, wrapRedactedError("insert child row", err, e.creds)
		}
		return true, nil
	}
	if item.SourceVal == nil && item.TargetVal != nil {
		tgtRow := e.tgtSnap.rawCells[suffix][plot+"\x00"+item.Key]
		if err := e.deleteChildRow(suffix, plot, tgtRow); err != nil {
			return false, err
		}
		return true, nil
	}
	return false, nil
}

func (e *cloudStagingMergeExecutor) deleteChildRow(suffix, plot string, tgtRow map[string]cloudCell) error {
	pgTbl := cloudMergePGTableBySuffix[suffix]
	idCell := tgtRow["ID"]
	if idCell.kind != "int" {
		return fmt.Errorf("target %s row in plot %s lacks integer ID", suffix, plot)
	}
	tgtID := idCell.intVal
	if err := reserveMasterChildID(e.ctx, e.tx, pgTbl, tgtID); err != nil {
		return wrapRedactedError("reserve deleted child ID", err, e.creds)
	}
	e.reservedDeletedIDs = append(e.reservedDeletedIDs, tgtID)

	tag, err := e.tx.Exec(e.ctx, fmt.Sprintf(
		`DELETE FROM becmaster.%s WHERE "PlotNumber" = $1 AND "ID" = $2`,
		quotePGIdent(pgTbl),
	), plot, tgtID)
	if err != nil {
		return wrapRedactedError("delete child row", err, e.creds)
	}
	if tag.RowsAffected() != 1 {
		return fmt.Errorf("child delete on %s (plot %s, ID %d) matched %d rows", suffix, plot, tgtID, tag.RowsAffected())
	}
	for _, col := range VP08ColumnsBySuffix(suffix) {
		if col.Name == "PlotNumber" || col.Name == "ID" {
			continue
		}
		oldCell := tgtRow[col.Name]
		if oldCell.kind == "null" || (col.Name == "Flag" && oldCell.kind == "int" && oldCell.intVal == 0) {
			continue
		}
		e.recordAudit(plot, suffix, col.Name, oldCell.comparableString(), nil, &tgtID)
	}
	return nil
}

func (e *cloudStagingMergeExecutor) applyChildFieldMergeItem(
	plot, suffix string,
	item CloudMergeConflictItem,
	touchedHorizons map[string]touchedCloudHorizonKey,
) error {
	dotIdx := strings.LastIndex(item.Key, ".")
	if dotIdx <= 0 {
		return fmt.Errorf("malformed child conflict key %q", item.Key)
	}
	rowKey := item.Key[:dotIdx]
	colSpec, ok := lookupVP08ColumnSpec(suffix, item.Field)
	if !ok {
		return fmt.Errorf("unknown child column %s.%s", suffix, item.Field)
	}
	srcCell := e.srcSnap.rawCells[suffix][plot+"\x00"+rowKey][item.Field]
	if err := validateCloudMergeCell(suffix, colSpec, srcCell); err != nil {
		return fmt.Errorf("plot %s: %w", plot, err)
	}
	tgtRow := e.tgtSnap.rawCells[suffix][plot+"\x00"+rowKey]
	idCell := tgtRow["ID"]
	if idCell.kind != "int" {
		return fmt.Errorf("target %s row in plot %s lacks integer ID", suffix, plot)
	}
	tgtID := idCell.intVal
	pgTbl := cloudMergePGTableBySuffix[suffix]
	tag, err := e.tx.Exec(e.ctx, fmt.Sprintf(
		`UPDATE becmaster.%s SET %s = $1 WHERE "PlotNumber" = $2 AND "ID" = $3`,
		quotePGIdent(pgTbl), quotePGIdent(item.Field),
	), srcCell.pgParam(colSpec), plot, tgtID)
	if err != nil {
		return wrapRedactedError("update child field", err, e.creds)
	}
	if tag.RowsAffected() != 1 {
		return fmt.Errorf("child update on %s.%s (plot %s, ID %d) matched %d rows", suffix, item.Field, plot, tgtID, tag.RowsAffected())
	}
	e.recordAudit(plot, suffix, item.Field, item.TargetVal, item.SourceVal, &tgtID)
	if suffix == "Humus" || suffix == "Mineral" {
		touchedHorizons[suffix+"\x00"+plot+"\x00"+rowKey] = touchedCloudHorizonKey{suffix: suffix, plot: plot, rowKey: rowKey}
	}
	return nil
}

func (e *cloudStagingMergeExecutor) verifyTouchedHorizonDepths(touchedHorizons map[string]touchedCloudHorizonKey) error {
	for _, tr := range touchedHorizons {
		tgtID := e.tgtSnap.rawCells[tr.suffix][tr.plot+"\x00"+tr.rowKey]["ID"].intVal
		var hz *string
		var up, lo *float64
		if err := e.tx.QueryRow(e.ctx, fmt.Sprintf(
			`SELECT "Horizon", "UpperDepth", "LowerDepth" FROM becmaster.%s WHERE "PlotNumber" = $1 AND "ID" = $2`,
			quotePGIdent(cloudMergePGTableBySuffix[tr.suffix]),
		), tr.plot, tgtID).Scan(&hz, &up, &lo); err != nil {
			return wrapRedactedError("verify merged horizon depth", err, e.creds)
		}
		hzStr := ""
		if hz != nil {
			hzStr = *hz
		}
		if err := ValidateLMH25HorizonDepth(tr.suffix, hzStr, up, lo); err != nil {
			return fmt.Errorf("plot %s: %w", tr.plot, err)
		}
	}
	return nil
}

func lookupVP08ColumnSpec(suffix, field string) (ColumnSpec, bool) {
	for _, c := range VP08ColumnsBySuffix(suffix) {
		if c.Name == field {
			return c, true
		}
	}
	return ColumnSpec{}, false
}

func (e *cloudStagingMergeExecutor) insertWholePlot(plot string) error {
	if err := ValidateUTF16Bound("PlotNumber", plot, 7); err != nil {
		return err
	}
	for _, suffix := range []string{"Env", "Admin"} {
		if err := e.insertWholePlotHeaderRow(suffix, plot); err != nil {
			return err
		}
	}
	for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other"} {
		childMap := plotRawRowsFromSnap(e.srcSnap, suffix, plot)
		keys := make([]string, 0, len(childMap))
		for k := range childMap {
			keys = append(keys, k)
		}
		slices.Sort(keys)
		for _, rk := range keys {
			if err := e.insertChildRow(suffix, plot, childMap[rk]); err != nil {
				return err
			}
		}
	}
	return nil
}

func (e *cloudStagingMergeExecutor) insertWholePlotHeaderRow(suffix, plot string) error {
	srcMap := plotRawRowsFromSnap(e.srcSnap, suffix, plot)
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
			if err := validateCloudMergeCell(suffix, col, c); err != nil {
				return fmt.Errorf("plot %s: %w", plot, err)
			}
			args[i] = c.pgParam(col)
		}
	}
	insSQL := fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
		quotePGIdent(cloudMergePGTableBySuffix[suffix]), quotedColumnCSV(cols), strings.Join(placeholders, ", "))
	if _, err := e.tx.Exec(e.ctx, insSQL, args...); err != nil {
		return err
	}
	pCopy := plot
	e.recordAudit(plot, suffix, keyCol, nil, &pCopy, nil)
	for _, col := range cols {
		if col.Name == keyCol {
			continue
		}
		c := srcRow[col.Name]
		if c.kind == "null" {
			continue
		}
		e.recordAudit(plot, suffix, col.Name, nil, c.comparableString(), nil)
	}
	return nil
}

func (e *cloudStagingMergeExecutor) insertChildRow(suffix, plot string, srcRow map[string]cloudCell) error {
	if err := validateHorizonRowDepth(suffix, srcRow); err != nil {
		return fmt.Errorf("plot %s %s: %w", plot, suffix, err)
	}
	cols := VP08ColumnsBySuffix(suffix)
	childTbl := cloudMergePGTableBySuffix[suffix]
	newID, err := allocateMasterChildID(e.ctx, e.tx, childTbl)
	if err != nil {
		return err
	}
	e.allocatedIDs = append(e.allocatedIDs, newID)

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
			if err := validateCloudMergeCell(suffix, col, c); err != nil {
				return fmt.Errorf("plot %s: %w", plot, err)
			}
			args[i] = c.pgParam(col)
		}
	}
	insSQL := fmt.Sprintf("INSERT INTO becmaster.%s (%s) VALUES (%s)",
		quotePGIdent(childTbl), quotedColumnCSV(cols), strings.Join(placeholders, ", "))
	if _, err := e.tx.Exec(e.ctx, insSQL, args...); err != nil {
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
		e.recordAudit(plot, suffix, col.Name, nil, c.comparableString(), &newID)
	}
	return nil
}

func (e *cloudStagingMergeExecutor) insertNewMasterMetadata() error {
	metaPayloads, err := e.queryUnseenStagingMetadataRows()
	if err != nil {
		return err
	}
	metaIDColIdx := len(VP08MetadataColumns) - 1
	placeholders := make([]string, len(VP08MetadataColumns))
	for i := range placeholders {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
	}
	insMetaSQL := fmt.Sprintf("INSERT INTO becmaster.metadata (%s) VALUES (%s) ON CONFLICT (\"ProjectID\") DO NOTHING",
		quotedColumnCSV(VP08MetadataColumns), strings.Join(placeholders, ", "))

	for _, rowVals := range metaPayloads {
		newMetaID, err := allocateMasterChildID(e.ctx, e.tx, "metadata")
		if err != nil {
			return wrapRedactedError("allocate metadata ID", err, e.creds)
		}
		rowVals[metaIDColIdx] = newMetaID
		tag, err := e.tx.Exec(e.ctx, insMetaSQL, rowVals...)
		if err != nil {
			return wrapRedactedError("insert becmaster.metadata", err, e.creds)
		}
		if tag.RowsAffected() == 1 {
			if pid, ok := rowVals[0].(string); ok {
				pidCopy := pid
				e.recordAudit("", "Metadata", "ProjectID", nil, &pidCopy, &newMetaID)
			}
		}
	}
	return nil
}

func (e *cloudStagingMergeExecutor) queryUnseenStagingMetadataRows() ([][]any, error) {
	newMetaRows, err := e.tx.Query(e.ctx, fmt.Sprintf(`
		SELECT %s FROM staging.metadata s
		WHERE s.submission_id = $1
		  AND NOT EXISTS (SELECT 1 FROM becmaster.metadata m WHERE m."ProjectID" = s."ProjectID")
	`, quotedColumnCSV(VP08MetadataColumns)), e.subID)
	if err != nil {
		return nil, wrapRedactedError("query new staging.metadata rows", err, e.creds)
	}
	var metaPayloads [][]any
	for newMetaRows.Next() {
		vals, vErr := newMetaRows.Values()
		if vErr != nil {
			newMetaRows.Close()
			return nil, wrapRedactedError("scan staging.metadata row", vErr, e.creds)
		}
		cp := make([]any, len(vals))
		copy(cp, vals)
		metaPayloads = append(metaPayloads, cp)
	}
	newMetaRows.Close()
	if err := newMetaRows.Err(); err != nil {
		return nil, wrapRedactedError("iterate staging.metadata rows", err, e.creds)
	}
	return metaPayloads, nil
}

func (e *cloudStagingMergeExecutor) appendHashChainedAudits() (string, error) {
	prevHash := GenesisAuditHash
	_ = e.tx.QueryRow(e.ctx, `SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1`).Scan(&prevHash)
	if len(e.pendingAudits) == 0 {
		return prevHash, nil
	}
	copyCols := append(columnNames(VP08AuditColumns), "merge_tx_id", "prev_hash", "row_hash")
	idx := 0
	_, err := e.tx.CopyFrom(
		e.ctx,
		pgx.Identifier{"becmaster", "audit"},
		copyCols,
		pgx.CopyFromFunc(func() ([]any, error) {
			if idx >= len(e.pendingAudits) {
				return nil, nil
			}
			vp08Row := e.pendingAudits[idx]
			idx++
			rowHash := ComputeAuditRowHash(prevHash, e.mergeTxID, vp08Row)
			out := make([]any, len(copyCols))
			copy(out, vp08Row)
			out[len(VP08AuditColumns)] = e.mergeTxID
			out[len(VP08AuditColumns)+1] = prevHash
			out[len(VP08AuditColumns)+2] = rowHash
			prevHash = rowHash
			return out, nil
		}),
	)
	if err != nil {
		return "", wrapRedactedError("append hash-chained becmaster.audit rows", err, e.creds)
	}
	return prevHash, nil
}

func (e *cloudStagingMergeExecutor) recordLedgerAndMarkSubmissionMerged(tailHash string) error {
	summaryPayload, _ := json.Marshal(map[string]any{
		"sourceProject":      e.preview.SourceProject,
		"previewDigest":      e.preview.PreviewDigest,
		"addedPlots":         e.addedPlots,
		"updatedPlots":       e.updatedPlots,
		"skippedPlots":       e.skippedPlots,
		"auditRowsWritten":   len(e.pendingAudits),
		"allocatedChildIds":  len(e.allocatedIDs),
		"reservedDeletedIds": len(e.reservedDeletedIDs),
		"tailAuditHash":      tailHash,
	})
	if _, err := e.tx.Exec(e.ctx, `
		INSERT INTO becmaster.merge_ledger (
			merge_tx_id, submission_id, actor, merged_at, source_sha256,
			added_plots, updated_plots, summary_json
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
	`, e.mergeTxID, e.subID, e.actor, e.nowUTC, e.srcSHA, e.addedPlots, e.updatedPlots, string(summaryPayload)); err != nil {
		return wrapRedactedError("insert becmaster.merge_ledger", err, e.creds)
	}

	var revNotesPtr *string
	if rn := strings.TrimSpace(e.req.ReviewerNotes); rn != "" {
		revNotesPtr = &rn
	}
	if _, err := e.tx.Exec(e.ctx, `
		UPDATE staging.submissions
		SET status = 'merged',
		    reviewed_by = $2,
		    reviewed_at = $3,
		    reviewer_notes = COALESCE($4, reviewer_notes),
		    merged_tx_id = $5
		WHERE submission_id = $1
	`, e.subID, e.actor, e.nowUTC, revNotesPtr, e.mergeTxID); err != nil {
		return wrapRedactedError("mark staging submission merged", err, e.creds)
	}
	return nil
}
