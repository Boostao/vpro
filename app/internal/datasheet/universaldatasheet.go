package datasheet

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func readSinglePhysicalRowByRowID(ctx context.Context, tx *sql.Tx, tableName string, columns []DatasheetColumnMeta, rowID int64) ([]vprocore.ProjectMetadataCell, error) {
	selectFields := make([]string, 0, len(columns)*2)
	for _, col := range columns {
		qCol := vprocore.QuoteHeaderIdentifier(col.Name)
		selectFields = append(selectFields,
			"typeof("+qCol+")",
			"CASE typeof("+qCol+") WHEN 'integer' THEN CAST("+qCol+" AS INTEGER) WHEN 'real' THEN CAST("+qCol+" AS REAL) ELSE CAST("+qCol+" AS BLOB) END",
		)
	}
	query := "SELECT " + strings.Join(selectFields, ",") + " FROM main." + vprocore.QuoteHeaderIdentifier(tableName) + " WHERE rowid = ?"
	storages := make([]string, len(columns))
	values := make([]any, len(columns))
	dest := make([]any, 0, len(columns)*2)
	for i := range columns {
		dest = append(dest, &storages[i], &values[i])
	}
	if err := tx.QueryRowContext(ctx, query, rowID).Scan(dest...); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("row %d no longer exists in %s; reload before saving", rowID, tableName)
		}
		return nil, err
	}
	cells := make([]vprocore.ProjectMetadataCell, len(columns))
	for i, val := range values {
		cell, err := vprocore.ProjectMetadataCellInternal(storages[i], val)
		if err != nil {
			return nil, fmt.Errorf("row %d column %s: %w", rowID, columns[i].Name, err)
		}
		cells[i] = cell
	}
	return cells, nil
}

type orderedDatasheetRowEdits struct {
	rowID int64
	edits []DatasheetCellEdit
}

type preparedDatasheetCellMutation struct {
	colIndex   int
	colMeta    DatasheetColumnMeta
	beforeCell vprocore.ProjectMetadataCell
	afterCell  vprocore.ProjectMetadataCell
	driverVal  any
	beforeText *string
	afterText  *string
}

func groupDatasheetEditsByRow(edits []DatasheetCellEdit) ([]int64, map[int64]*orderedDatasheetRowEdits, error) {
	rowOrder := []int64{}
	byRow := map[int64]*orderedDatasheetRowEdits{}
	seenCell := map[string]bool{}
	for _, edit := range edits {
		rid, parseErr := strconv.ParseInt(strings.TrimSpace(edit.RowID), 10, 64)
		if parseErr != nil {
			return nil, nil, fmt.Errorf("invalid datasheet rowId %q", edit.RowID)
		}
		colKey := fmt.Sprintf("%d:%s", rid, strings.ToLower(strings.TrimSpace(edit.Column)))
		if seenCell[colKey] {
			return nil, nil, fmt.Errorf("duplicate datasheet edit for row %d column %q in one batch", rid, edit.Column)
		}
		seenCell[colKey] = true
		bucket := byRow[rid]
		if bucket == nil {
			bucket = &orderedDatasheetRowEdits{rowID: rid}
			byRow[rid] = bucket
			rowOrder = append(rowOrder, rid)
		}
		bucket.edits = append(bucket.edits, edit)
	}
	return rowOrder, byRow, nil
}

func prepareDatasheetRowMutations(
	target resolvedDatasheetTarget,
	rid int64,
	edits []DatasheetCellEdit,
	columns []DatasheetColumnMeta,
	colIndexByLower map[string]int,
	currentCells []vprocore.ProjectMetadataCell,
	canEditMaster bool,
) ([]preparedDatasheetCellMutation, error) {
	var mutations []preparedDatasheetCellMutation
	for _, edit := range edits {
		idx, ok := colIndexByLower[strings.ToLower(strings.TrimSpace(edit.Column))]
		if !ok {
			return nil, fmt.Errorf("unknown column %q on %s", edit.Column, target.tableName)
		}
		colMeta := columns[idx]
		storedCell := currentCells[idx]
		if !datasheetCellsSemanticallyEqual(storedCell, edit.Before, colMeta) {
			return nil, fmt.Errorf("concurrency conflict on %s row %d column %s: stored value changed; reload before saving",
				target.tableName, rid, colMeta.Name)
		}
		if !isProtectedDatasheetColumn(target.key, colMeta, canEditMaster) {
			if _, cellErr := vprocore.MetadataCellValue(edit.After); cellErr == nil && datasheetCellsSemanticallyEqual(storedCell, edit.After, colMeta) {
				continue
			}
		}
		driverVal, afterAudit, normalizedCell, err := validateAndNormalizeDatasheetCell(target.key, colMeta, edit.After, canEditMaster)
		if err != nil {
			return nil, err
		}
		if datasheetCellsSemanticallyEqual(storedCell, normalizedCell, colMeta) {
			continue
		}
		mutations = append(mutations, preparedDatasheetCellMutation{
			colIndex:   idx,
			colMeta:    colMeta,
			beforeCell: storedCell,
			afterCell:  normalizedCell,
			driverVal:  driverVal,
			beforeText: auditTextForStoredCell(storedCell, colMeta.IsBoolean),
			afterText:  afterAudit,
		})
	}
	return mutations, nil
}

func extractDatasheetRowIdentity(
	targetKey string,
	colIndexByLower map[string]int,
	currentCells []vprocore.ProjectMetadataCell,
	mutations []preparedDatasheetCellMutation,
) (plotBefore, plotAfter string, childID *int64, projected []vprocore.ProjectMetadataCell, togglingEnvFlag bool) {
	plotColName := plotColNameForDatasheetKey(targetKey)
	if plotColName != "" {
		if pIdx, ok := colIndexByLower[strings.ToLower(plotColName)]; ok && currentCells[pIdx].Text != nil {
			plotBefore = *currentCells[pIdx].Text
			plotAfter = plotBefore
		}
	}
	if idIdx, ok := colIndexByLower["id"]; ok && isEditableDatasheetChildTable(targetKey) {
		if currentCells[idIdx].Integer != nil {
			if parsedID, pErr := strconv.ParseInt(*currentCells[idIdx].Integer, 10, 64); pErr == nil {
				childID = &parsedID
			}
		}
	}
	projected = slices.Clone(currentCells)
	for _, m := range mutations {
		projected[m.colIndex] = m.afterCell
		if strings.EqualFold(m.colMeta.Name, plotColName) && m.afterCell.Text != nil {
			plotAfter = *m.afterCell.Text
		}
		if targetKey == "Env" && m.colMeta.Name == "Flag" {
			togglingEnvFlag = true
		}
	}
	return plotBefore, plotAfter, childID, projected, togglingEnvFlag
}

func validateDatasheetProjectedSoilCells(
	targetKey string,
	colIndexByLower map[string]int,
	projectedCells []vprocore.ProjectMetadataCell,
	mutations []preparedDatasheetCellMutation,
) error {
	if targetKey != "Humus" && targetKey != "Mineral" {
		return nil
	}
	soilDepthTouched := false
	cfTouched := false
	for _, m := range mutations {
		if m.colMeta.Name == "Horizon" || m.colMeta.Name == "UpperDepth" || m.colMeta.Name == "LowerDepth" {
			soilDepthTouched = true
		}
		if vprocore.MineralCoarseFragColumns[m.colMeta.Name] {
			cfTouched = true
		}
	}
	if soilDepthTouched {
		var effHz *string
		if hIdx, hasH := colIndexByLower["horizon"]; hasH {
			effHz = cellTextPtr(projectedCells[hIdx])
		}
		var effUp, effLo *float64
		if uIdx, hasU := colIndexByLower["upperdepth"]; hasU {
			effUp = cellFloat64Ptr(projectedCells[uIdx])
		}
		if lIdx, hasL := colIndexByLower["lowerdepth"]; hasL {
			effLo = cellFloat64Ptr(projectedCells[lIdx])
		}
		if err := validateSoilHorizonDepthSign(targetKey, effHz, effUp, effLo); err != nil {
			return err
		}
	}
	if targetKey == "Mineral" && cfTouched {
		cellAt := func(low string) vprocore.ProjectMetadataCell {
			if idx, ok := colIndexByLower[low]; ok {
				return projectedCells[idx]
			}
			return vprocore.ProjectMetadataCell{Storage: "null"}
		}
		return validateMineralCoarseFragsCells(
			cellAt("percentcoarsefragsgravel"),
			cellAt("percentcoarsefragscobbles"),
			cellAt("percentcoarsefragsstones"),
			cellAt("percentcoarsefragstotal"),
		)
	}
	return nil
}

func recordDatasheetRowAudits(
	ctx context.Context,
	wtx *vprocore.WriteTx,
	target resolvedDatasheetTarget,
	sameAsProject bool,
	currentUser, plotAfter, now string,
	childID *int64,
	mutations []preparedDatasheetCellMutation,
) (int, error) {
	if !sameAsProject || plotAfter == "" {
		return 0, nil
	}
	canAudit := isProjectPlotFindReplaceTable(target.key)
	if target.key == "SU" {
		var envMatch int
		if err := wtx.QueryRowContext(ctx,
			`SELECT COUNT(*) FROM main.`+vprocore.QuoteHeaderIdentifier(wtx.Project+"_Env")+
				` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
			plotAfter,
		).Scan(&envMatch); err != nil {
			return 0, err
		}
		canAudit = envMatch == 1
	}
	if !canAudit {
		return 0, nil
	}
	tableSuffix := "_" + target.key
	auditCount := 0
	for _, m := range mutations {
		colCopy := m.colMeta.Name
		plotCopy := plotAfter
		if _, err := wtx.RecordAudit(ctx, vprocore.AuditWriteEntry{
			Schema:     "main",
			Project:    wtx.Project,
			User:       currentUser,
			PlotNumber: &plotCopy,
			Table:      tableSuffix,
			EditField:  &colCopy,
			EditWhen:   now,
			BeforeEdit: m.beforeText,
			AfterEdit:  m.afterText,
			ID:         childID,
		}); err != nil {
			return 0, fmt.Errorf("write audit for %s.%s: %w", target.tableName, m.colMeta.Name, err)
		}
		auditCount++
	}
	return auditCount, nil
}

func applySingleDatasheetRowEdits(
	ctx context.Context,
	wtx *vprocore.WriteTx,
	target resolvedDatasheetTarget,
	sameAsProject, canEditMaster bool,
	currentUser, now string,
	columns []DatasheetColumnMeta,
	colIndexByLower map[string]int,
	bucket *orderedDatasheetRowEdits,
	result *DatasheetEditResult,
) error {
	rid := bucket.rowID
	currentCells, err := readSinglePhysicalRowByRowID(ctx, wtx.Tx, target.tableName, columns, rid)
	if err != nil {
		return err
	}
	mutations, err := prepareDatasheetRowMutations(target, rid, bucket.edits, columns, colIndexByLower, currentCells, canEditMaster)
	if err != nil || len(mutations) == 0 {
		return err
	}
	plotBefore, plotAfter, childID, projectedCells, togglingEnvFlag := extractDatasheetRowIdentity(target.key, colIndexByLower, currentCells, mutations)
	if sameAsProject && plotBefore != "" && !togglingEnvFlag && isProjectPlotFindReplaceTable(target.key) {
		var lockedCount int
		if err := wtx.QueryRowContext(ctx,
			`SELECT COUNT(*) FROM main.`+vprocore.QuoteHeaderIdentifier(wtx.Project+"_Env")+
				` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
			plotBefore,
		).Scan(&lockedCount); err != nil {
			return err
		}
		if lockedCount > 0 {
			return fmt.Errorf("plot %q is locked (Flag = -1); unlock the plot before editing its cells", plotBefore)
		}
	}
	if err := validateDatasheetProjectedSoilCells(target.key, colIndexByLower, projectedCells, mutations); err != nil {
		return err
	}

	assignments := make([]string, len(mutations))
	updateArgs := make([]any, 0, len(mutations)+1)
	for i, m := range mutations {
		assignments[i] = vprocore.QuoteHeaderIdentifier(m.colMeta.Name) + " = ?"
		updateArgs = append(updateArgs, m.driverVal)
	}
	updateArgs = append(updateArgs, rid)
	updateSQL := "UPDATE main." + vprocore.QuoteHeaderIdentifier(target.tableName) +
		" SET " + strings.Join(assignments, ", ") + " WHERE rowid = ?"
	execRes, err := wtx.ExecContext(ctx, updateSQL, updateArgs...)
	if err != nil {
		return fmt.Errorf("update %s row %d: %w", target.tableName, rid, err)
	}
	if affected, aErr := execRes.RowsAffected(); aErr != nil || affected != 1 {
		return errors.Join(aErr, fmt.Errorf("update %s row %d affected %d rows (expected 1)", target.tableName, rid, affected))
	}

	result.UpdatedRows++
	result.UpdatedCells += len(mutations)
	auditRows, err := recordDatasheetRowAudits(ctx, wtx, target, sameAsProject, currentUser, plotAfter, now, childID, mutations)
	if err != nil {
		return err
	}
	result.AuditRows += auditRows
	return nil
}

// ApplyDatasheetEdits validates and commits a batch of cell edits inside a single
// atomic SQLite BEGIN IMMEDIATE transaction, omitting unchanged historical columns
// and writing one <Project>_Audit row per mutated project cell.
func ApplyDatasheetEdits(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetEditRequest) (*DatasheetEditResult, error) {
	if ctx == nil {
		return nil, errors.New("datasheet edit requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	if len(request.Edits) == 0 {
		return nil, errors.New("datasheet edit requires at least one cell edit")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*DatasheetEditResult, error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		plots.Mu.RLock()
		currentUser := plots.CurrentUser
		plots.Mu.RUnlock()
		if strings.TrimSpace(currentUser) == "" {
			currentUser = "VPro"
		}

		target, err := findDatasheetTarget(owner, request.TableKey)
		if err != nil {
			return nil, err
		}
		if !target.available {
			return nil, errors.New(target.unavailableReason)
		}
		if target.readOnly {
			return nil, fmt.Errorf("table %s (%s) is read-only in datasheet mode", target.key, target.tableName)
		}

		rowOrder, byRow, err := groupDatasheetEditsByRow(request.Edits)
		if err != nil {
			return nil, err
		}
		validateFiles := validateDatasheetTargetFiles(owner, target)
		result := &DatasheetEditResult{
			ContextID: contextID,
			TableKey:  target.key,
			TableName: target.tableName,
		}
		sameAsProject := owner.AttachmentInfo[target.role] != nil &&
			owner.AttachmentInfo["project"] != nil &&
			os.SameFile(owner.AttachmentInfo[target.role], owner.AttachmentInfo["project"])

		err = owner.WithImmediateRoleWriteTx(ctx, target.role, validateFiles, func(wtx *vprocore.WriteTx) error {
			var physicalExists bool
			if err := wtx.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM main.sqlite_master WHERE type='table' AND name COLLATE BINARY=?)", target.tableName).Scan(&physicalExists); err != nil {
				return err
			}
			if !physicalExists {
				return fmt.Errorf("datasheet target %s must be a physical table, not a view", target.tableName)
			}

			rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, wtx.Tx, "main", target.tableName)
			if err != nil {
				return err
			}
			columns := make([]DatasheetColumnMeta, len(rawCols))
			colIndexByLower := make(map[string]int, len(rawCols))
			for i, col := range rawCols {
				columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
				colIndexByLower[strings.ToLower(col.Name)] = i
			}

			now := time.Now().Format("2006-01-02 15:04:05")
			hierarchyParentCheck := false
			if target.key == "Hierarchy" {
				for _, ed := range request.Edits {
					if strings.EqualFold(ed.Column, "Parent") {
						hierarchyParentCheck = true
					}
				}
			}

			for _, rid := range rowOrder {
				if err := ctx.Err(); err != nil {
					return err
				}
				if err := applySingleDatasheetRowEdits(
					ctx, wtx, target, sameAsProject, canEditMaster, currentUser, now,
					columns, colIndexByLower, byRow[rid], result,
				); err != nil {
					return err
				}
			}

			if hierarchyParentCheck {
				if err := verifyHierarchyAcyclicInTx(ctx, wtx.Tx, target.tableName); err != nil {
					return err
				}
			}
			if result.UpdatedCells > 0 {
				proposalBytes, err := json.Marshal(struct {
					ContextID string               `json:"contextId"`
					User      string               `json:"user"`
					Request   DatasheetEditRequest `json:"request"`
				}{contextID, currentUser, request})
				if err != nil {
					return err
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, wtx.Tx, datasheetHistoryTable, datasheetHistorySQL, string(proposalBytes), "datasheet edit"); err != nil {
					return err
				}
			}
			return validateFiles()
		})
		if err != nil {
			return nil, err
		}
		return result, nil
	})
}

func plotColNameForDatasheetKey(tableKey string) string {
	switch tableKey {
	case "Env", "Veg", "Humus", "Mineral", "Other", "SU":
		return "PlotNumber"
	case "Admin":
		return "Plot"
	default:
		return ""
	}
}

func loadHierarchyParentsMap(ctx context.Context, tx *sql.Tx, schema, tableName string) (map[int64]*int64, error) {
	rel := vprocore.QuoteHeaderIdentifier(schema) + "." + vprocore.QuoteHeaderIdentifier(tableName)
	rows, err := tx.QueryContext(ctx, "SELECT ID, Parent FROM "+rel)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	parents := map[int64]*int64{}
	for rows.Next() {
		var id int64
		var parent sql.NullInt64
		if err := rows.Scan(&id, &parent); err != nil {
			return nil, err
		}
		if parent.Valid {
			p := parent.Int64
			parents[id] = &p
		} else {
			parents[id] = nil
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return parents, nil
}

func validateCandidateHierarchyParent(nodeID int64, candidate vprocore.ProjectMetadataCell, parents map[int64]*int64) error {
	if candidate.Storage == "null" || candidate.Integer == nil {
		return nil
	}
	parentID, err := strconv.ParseInt(*candidate.Integer, 10, 64)
	if err != nil {
		return fmt.Errorf("Hierarchy node %d has invalid Parent %q", nodeID, *candidate.Integer)
	}
	if _, ok := parents[parentID]; !ok {
		return fmt.Errorf("Hierarchy node %d references non-existent Parent %d", nodeID, parentID)
	}
	visited := map[int64]bool{nodeID: true}
	curr := &parentID
	for curr != nil {
		if visited[*curr] {
			return fmt.Errorf("Hierarchy edit introduces a cycle involving node %d", *curr)
		}
		visited[*curr] = true
		curr = parents[*curr]
	}
	return nil
}

func verifyHierarchyAcyclicInTx(ctx context.Context, tx *sql.Tx, tableName string) error {
	parents, err := loadHierarchyParentsMap(ctx, tx, "main", tableName)
	if err != nil {
		return err
	}
	for id, p := range parents {
		if p != nil {
			if _, ok := parents[*p]; !ok {
				return fmt.Errorf("Hierarchy node %d references non-existent Parent %d", id, *p)
			}
		}
		visited := map[int64]bool{id: true}
		curr := p
		for curr != nil {
			if visited[*curr] {
				return fmt.Errorf("Hierarchy edit introduces a cycle involving node %d", *curr)
			}
			visited[*curr] = true
			curr = parents[*curr]
		}
	}
	return nil
}
