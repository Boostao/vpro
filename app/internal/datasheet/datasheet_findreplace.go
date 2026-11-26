package datasheet

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func replaceSubstringInsensitive(haystack, needle, replacement string) (string, bool) {
	if needle == "" {
		return haystack, false
	}
	lowerNeedle := strings.ToLower(needle)
	var out strings.Builder
	changed := false
	i := 0
	for i < len(haystack) {
		idx := strings.Index(strings.ToLower(haystack[i:]), lowerNeedle)
		if idx < 0 {
			out.WriteString(haystack[i:])
			break
		}
		out.WriteString(haystack[i : i+idx])
		needleRunes := []rune(needle)
		restRunes := []rune(haystack[i+idx:])
		if len(restRunes) < len(needleRunes) {
			out.WriteString(haystack[i+idx:])
			break
		}
		matchedOriginal := string(restRunes[:len(needleRunes)])
		if strings.EqualFold(matchedOriginal, needle) {
			out.WriteString(replacement)
			changed = true
			i += idx + len(matchedOriginal)
		} else {
			_, width := utf8.DecodeRuneInString(haystack[i+idx:])
			out.WriteString(haystack[i+idx : i+idx+width])
			i += idx + width
		}
	}
	return out.String(), changed
}

type findReplaceScanPlan struct {
	columns             []DatasheetColumnMeta
	colMeta             DatasheetColumnMeta
	scanCols            []DatasheetColumnMeta
	scanPinnedIdx       int
	plotColIdx          int
	checkPlotLock       bool
	lockedPlots         map[string]bool
	checkSoilDepth      bool
	soilHorizonIdx      int
	soilUpperIdx        int
	soilLowerIdx        int
	checkMineralCF      bool
	cfGravelIdx         int
	cfCobblesIdx        int
	cfStonesIdx         int
	cfTotalIdx          int
	checkHierarchyCycle bool
	hierIDIdx           int
	hierParents         map[int64]*int64
}

func loadLockedPlotsForFindReplace(ctx context.Context, tx *sql.Tx, project string) (map[string]bool, error) {
	lockedPlots := map[string]bool{}
	envRel := vprocore.QuoteHeaderIdentifier("project") + "." + vprocore.QuoteHeaderIdentifier(project+"_Env")
	lockRows, err := tx.QueryContext(ctx,
		`SELECT CAST("PlotNumber" AS TEXT) FROM `+envRel+` WHERE typeof("PlotNumber")='text' AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
	)
	if err != nil {
		return nil, err
	}
	if closeErr := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, lockRows.Close()) }()
		for lockRows.Next() {
			var p string
			if scanErr := lockRows.Scan(&p); scanErr != nil {

				return scanErr
			}
			lockedPlots[p] = true
		}
		return lockRows.Err()
	}(); closeErr != nil {
		return nil, closeErr
	}
	return lockedPlots, nil
}

func isProjectPlotFindReplaceTable(key string) bool {
	switch key {
	case "Env", "Admin", "Veg", "Humus", "Mineral", "Other", "TreePlot", "Trees":
		return true
	default:
		return false
	}
}

func prepareFindReplaceScanPlan(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	target resolvedDatasheetTarget,
	columnName string,
	canEditMaster bool,
) (*findReplaceScanPlan, error) {
	rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, target.role, target.tableName)
	if err != nil {
		return nil, err
	}
	columns := make([]DatasheetColumnMeta, len(rawCols))
	colIndex, pinnedIndex := -1, -1
	colMetaByLower := make(map[string]DatasheetColumnMeta, len(rawCols))
	trimmedCol := strings.TrimSpace(columnName)
	for i, col := range rawCols {
		columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
		colMetaByLower[strings.ToLower(col.Name)] = columns[i]
		if strings.EqualFold(col.Name, trimmedCol) {
			colIndex = i
		}
		if strings.EqualFold(col.Name, target.pinnedColumn) {
			pinnedIndex = i
		}
	}
	if colIndex < 0 {
		return nil, fmt.Errorf("unknown column %q on %s", columnName, target.tableName)
	}
	colMeta := columns[colIndex]
	if target.key == "Admin" && colMeta.Name == "BECSiteUnit" && !canEditMaster {
		return nil, errors.New("BEC Master editing is restricted to the source-authorized user; use UserSiteUnit instead")
	}
	if isProtectedDatasheetColumn(target.key, colMeta, canEditMaster) {
		return nil, fmt.Errorf("column %s.%s is protected or read-only", target.key, colMeta.Name)
	}

	plan := &findReplaceScanPlan{
		columns:        columns,
		colMeta:        colMeta,
		scanCols:       []DatasheetColumnMeta{colMeta},
		scanPinnedIdx:  -1,
		plotColIdx:     -1,
		soilHorizonIdx: -1,
		soilUpperIdx:   -1,
		soilLowerIdx:   -1,
		cfGravelIdx:    -1,
		cfCobblesIdx:   -1,
		cfStonesIdx:    -1,
		cfTotalIdx:     -1,
		hierIDIdx:      -1,
	}
	scanIdxByLower := map[string]int{strings.ToLower(colMeta.Name): 0}
	ensureScanCol := func(name string) int {
		low := strings.ToLower(name)
		if idx, ok := scanIdxByLower[low]; ok {
			return idx
		}
		meta, ok := colMetaByLower[low]
		if !ok {
			return -1
		}
		idx := len(plan.scanCols)
		plan.scanCols = append(plan.scanCols, meta)
		scanIdxByLower[low] = idx
		return idx
	}
	if pinnedIndex >= 0 {
		plan.scanPinnedIdx = ensureScanCol(columns[pinnedIndex].Name)
	}
	if plotColName := plotColNameForDatasheetKey(target.key); plotColName != "" {
		plan.plotColIdx = ensureScanCol(plotColName)
	}
	sameAsProject := owner.AttachmentInfo[target.role] != nil &&
		owner.AttachmentInfo["project"] != nil &&
		os.SameFile(owner.AttachmentInfo[target.role], owner.AttachmentInfo["project"])
	if sameAsProject && plan.plotColIdx >= 0 && isProjectPlotFindReplaceTable(target.key) && !(target.key == "Env" && colMeta.Name == "Flag") {
		plan.checkPlotLock = true
		locked, lockErr := loadLockedPlotsForFindReplace(ctx, tx, owner.Selection.Project)
		if lockErr != nil {
			return nil, lockErr
		}
		plan.lockedPlots = locked
	}

	plan.checkSoilDepth = (target.key == "Humus" || target.key == "Mineral") &&
		(colMeta.Name == "Horizon" || colMeta.Name == "UpperDepth" || colMeta.Name == "LowerDepth")
	if plan.checkSoilDepth {
		plan.soilHorizonIdx = ensureScanCol("Horizon")
		plan.soilUpperIdx = ensureScanCol("UpperDepth")
		plan.soilLowerIdx = ensureScanCol("LowerDepth")
	}
	plan.checkMineralCF = target.key == "Mineral" && vprocore.MineralCoarseFragColumns[colMeta.Name]
	if plan.checkMineralCF {
		plan.cfGravelIdx = ensureScanCol("PercentCoarseFragsGravel")
		plan.cfCobblesIdx = ensureScanCol("PercentCoarseFragsCobbles")
		plan.cfStonesIdx = ensureScanCol("PercentCoarseFragsStones")
		plan.cfTotalIdx = ensureScanCol("PercentCoarseFragsTotal")
	}
	plan.checkHierarchyCycle = target.key == "Hierarchy" && strings.EqualFold(colMeta.Name, "Parent")
	if plan.checkHierarchyCycle {
		plan.hierIDIdx = ensureScanCol("ID")
		parents, loadErr := loadHierarchyParentsMap(ctx, tx, target.role, target.tableName)
		if loadErr != nil {
			return nil, loadErr
		}
		plan.hierParents = parents
	}
	return plan, nil
}

func matchDatasheetFindReplaceCell(beforeCell vprocore.ProjectMetadataCell, beforeText string, req DatasheetFindReplaceRequest) (string, bool) {
	if req.FindText == "" {
		if req.ExactCell && beforeCell.Storage == "null" {
			return req.ReplaceText, req.ReplaceText != ""
		}
		return "", false
	}
	if beforeCell.Storage == "null" {
		return "", false
	}
	if req.ExactCell {
		eq := strings.EqualFold(beforeText, req.FindText)
		if req.MatchCase {
			eq = beforeText == req.FindText
		}
		if !eq {
			return "", false
		}
		return req.ReplaceText, beforeText != req.ReplaceText || req.ReplaceText == ""
	}
	if req.MatchCase {
		if strings.Contains(beforeText, req.FindText) {
			return strings.ReplaceAll(beforeText, req.FindText, req.ReplaceText), true
		}
		return "", false
	}
	return replaceSubstringInsensitive(beforeText, req.FindText, req.ReplaceText)
}

func validateFindReplaceRowCandidate(
	targetKey string,
	plan *findReplaceScanPlan,
	row DatasheetRow,
	afterText string,
	canEditMaster bool,
) (vprocore.ProjectMetadataCell, string) {
	candidateCell, buildErr := buildReplacedCellFromString(plan.colMeta, afterText)
	if buildErr != nil {
		return candidateCell, buildErr.Error()
	}
	_, _, normalizedCell, vErr := validateAndNormalizeDatasheetCell(targetKey, plan.colMeta, candidateCell, canEditMaster)
	if vErr != nil {
		return candidateCell, vErr.Error()
	}
	if plan.checkPlotLock && plan.plotColIdx >= 0 && plan.plotColIdx < len(row.Cells) && row.Cells[plan.plotColIdx].Text != nil {
		plotVal := *row.Cells[plan.plotColIdx].Text
		if plan.lockedPlots[plotVal] {
			return normalizedCell, fmt.Sprintf("plot %q is locked (Flag = -1); unlock the plot before editing its cells", plotVal)
		}
	}
	if plan.checkSoilDepth && (plan.soilUpperIdx >= 0 || plan.soilLowerIdx >= 0) {
		if errStr := validateFindReplaceSoilDepth(targetKey, plan, row, normalizedCell); errStr != "" {
			return normalizedCell, errStr
		}
	}
	if plan.checkMineralCF {
		if errStr := validateFindReplaceMineralCF(plan, row, normalizedCell); errStr != "" {
			return normalizedCell, errStr
		}
	}
	if plan.checkHierarchyCycle && plan.hierIDIdx >= 0 && plan.hierIDIdx < len(row.Cells) && row.Cells[plan.hierIDIdx].Integer != nil {
		if nodeID, idErr := strconv.ParseInt(*row.Cells[plan.hierIDIdx].Integer, 10, 64); idErr == nil {
			if hErr := validateCandidateHierarchyParent(nodeID, normalizedCell, plan.hierParents); hErr != nil {
				return normalizedCell, hErr.Error()
			}
		}
	}
	return normalizedCell, ""
}

func validateFindReplaceSoilDepth(targetKey string, plan *findReplaceScanPlan, row DatasheetRow, normalizedCell vprocore.ProjectMetadataCell) string {
	var effHorizon, effUpper, effLower vprocore.ProjectMetadataCell
	if plan.soilHorizonIdx >= 0 {
		effHorizon = row.Cells[plan.soilHorizonIdx]
	}
	if plan.soilUpperIdx >= 0 {
		effUpper = row.Cells[plan.soilUpperIdx]
	}
	if plan.soilLowerIdx >= 0 {
		effLower = row.Cells[plan.soilLowerIdx]
	}
	switch plan.colMeta.Name {
	case "Horizon":
		effHorizon = normalizedCell
	case "UpperDepth":
		effUpper = normalizedCell
	case "LowerDepth":
		effLower = normalizedCell
	}
	if sErr := validateSoilHorizonDepthSign(targetKey, cellTextPtr(effHorizon), cellFloat64Ptr(effUpper), cellFloat64Ptr(effLower)); sErr != nil {
		return sErr.Error()
	}
	return ""
}

func validateFindReplaceMineralCF(plan *findReplaceScanPlan, row DatasheetRow, normalizedCell vprocore.ProjectMetadataCell) string {
	cellOrNull := func(idx int) vprocore.ProjectMetadataCell {
		if idx >= 0 && idx < len(row.Cells) {
			return row.Cells[idx]
		}
		return vprocore.ProjectMetadataCell{Storage: "null"}
	}
	effG := cellOrNull(plan.cfGravelIdx)
	effC := cellOrNull(plan.cfCobblesIdx)
	effS := cellOrNull(plan.cfStonesIdx)
	effT := cellOrNull(plan.cfTotalIdx)
	switch plan.colMeta.Name {
	case "PercentCoarseFragsGravel":
		effG = normalizedCell
	case "PercentCoarseFragsCobbles":
		effC = normalizedCell
	case "PercentCoarseFragsStones":
		effS = normalizedCell
	case "PercentCoarseFragsTotal":
		effT = normalizedCell
	}
	if cfErr := validateMineralCoarseFragsCells(effG, effC, effS, effT); cfErr != nil {
		return cfErr.Error()
	}
	return ""
}

func PreviewDatasheetFindReplace(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetFindReplaceRequest) (*DatasheetFindReplacePreview, error) {
	if ctx == nil {
		return nil, errors.New("datasheet find/replace preview requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	if !utf8.ValidString(request.FindText) || !utf8.ValidString(request.ReplaceText) ||
		strings.ContainsRune(request.FindText, 0) || strings.ContainsRune(request.ReplaceText, 0) {
		return nil, errors.New("find/replace text must be valid UTF-8 without NUL")
	}
	maxPreview := request.MaxPreview
	if maxPreview <= 0 || maxPreview > 2000 {
		maxPreview = 500
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*DatasheetFindReplacePreview, error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
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

		return vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*DatasheetFindReplacePreview, error) {
			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			plan, err := prepareFindReplaceScanPlan(ctx, tx, owner, target, request.Column, canEditMaster)
			if err != nil {
				return nil, err
			}
			whereSQL, whereArgs, orderSQL, err := buildDatasheetWhereAndOrder(
				ctx, tx, target, plan.columns, request.Filters, request.GlobalSearch, request.ScopeToActiveSU, owner, nil,
			)
			if err != nil {
				return nil, err
			}
			rows, err := queryDatasheetWindowRows(ctx, tx, target.role, target.tableName, plan.scanCols, whereSQL, whereArgs, orderSQL, 0, 0)
			if err != nil {
				return nil, err
			}

			preview := &DatasheetFindReplacePreview{
				ContextID: contextID,
				TableKey:  target.key,
				TableName: target.tableName,
				Column:    plan.colMeta.Name,
				Items:     []DatasheetFindReplaceItem{},
			}
			for _, row := range rows {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
				beforeCell := row.Cells[0]
				beforeText := cellToDisplayString(beforeCell, plan.colMeta.IsBoolean)
				afterText, matched := matchDatasheetFindReplaceCell(beforeCell, beforeText, request)
				if !matched {
					continue
				}
				preview.MatchedRows++

				pinnedVal := row.RowID
				if plan.scanPinnedIdx >= 0 && plan.scanPinnedIdx < len(row.Cells) {
					pinnedVal = cellToDisplayString(row.Cells[plan.scanPinnedIdx], plan.scanCols[plan.scanPinnedIdx].IsBoolean)
				}
				normalizedCell, valErr := validateFindReplaceRowCandidate(target.key, plan, row, afterText, canEditMaster)
				if valErr != "" {
					preview.InvalidCount++
				} else {
					preview.ValidCount++
				}
				if len(preview.Items) < maxPreview {
					preview.Items = append(preview.Items, DatasheetFindReplaceItem{
						RowID:           row.RowID,
						PinnedIdentity:  pinnedVal,
						Column:          plan.colMeta.Name,
						BeforeText:      beforeText,
						AfterText:       afterText,
						BeforeCell:      vprocore.CloneSiteUnitCell(beforeCell),
						AfterCell:       vprocore.CloneSiteUnitCell(normalizedCell),
						ValidationError: valErr,
						Edit: DatasheetCellEdit{
							RowID:  row.RowID,
							Column: plan.colMeta.Name,
							Before: vprocore.CloneSiteUnitCell(beforeCell),
							After:  vprocore.CloneSiteUnitCell(normalizedCell),
						},
					})
				} else {
					preview.Truncated = true
				}
			}
			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			return preview, nil
		})
	})
}
