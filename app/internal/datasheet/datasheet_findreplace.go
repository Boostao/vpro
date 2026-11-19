package datasheet

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"
)

func replaceSubstringInsensitive(haystack, needle, replacement string) (string, bool) {
	if needle == "" {
		return haystack, false
	}
	lowerNeedle := strings.ToLower(needle)
	// Handle general UTF-8 case-folding slice-by-rune safely if lengths match, else fallback to index scan.
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
		// Determine byte length in original haystack matching lowerNeedle rune count.
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

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ *DatasheetFindReplacePreview, resultErr error) {
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

		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return nil, err
		}
		defer owner.Mu.Unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if err := tx.Rollback(); err != nil && !errors.Is(err, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, err)
			}
		}()

		rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, target.role, target.tableName)
		if err != nil {
			return nil, err
		}
		columns := make([]DatasheetColumnMeta, len(rawCols))
		colIndex := -1
		pinnedIndex := -1
		colMetaByLower := make(map[string]DatasheetColumnMeta, len(rawCols))
		for i, col := range rawCols {
			columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
			colMetaByLower[strings.ToLower(col.Name)] = columns[i]
			if strings.EqualFold(col.Name, strings.TrimSpace(request.Column)) {
				colIndex = i
			}
			if strings.EqualFold(col.Name, target.pinnedColumn) {
				pinnedIndex = i
			}
		}
		if colIndex < 0 {
			return nil, fmt.Errorf("unknown column %q on %s", request.Column, target.tableName)
		}
		colMeta := columns[colIndex]
		if target.key == "Admin" && colMeta.Name == "BECSiteUnit" && !canEditMaster {
			return nil, errors.New("BEC Master editing is restricted to the source-authorized user; use UserSiteUnit instead")
		}
		if isProtectedDatasheetColumn(target.key, colMeta, canEditMaster) {
			return nil, fmt.Errorf("column %s.%s is protected or read-only", target.key, colMeta.Name)
		}

		whereSQL, whereArgs, orderSQL, err := buildDatasheetWhereAndOrder(
			ctx, tx, target, columns, request.Filters, request.GlobalSearch, request.ScopeToActiveSU, owner, nil,
		)
		if err != nil {
			return nil, err
		}

		// Query target column, pinned column, plus extra sibling columns needed for row-level plot lock,
		// LMH25 soil depth-sign, and Hierarchy cycle validation during Find & Replace preview.
		scanCols := []DatasheetColumnMeta{colMeta}
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
			idx := len(scanCols)
			scanCols = append(scanCols, meta)
			scanIdxByLower[low] = idx
			return idx
		}
		scanPinnedIdx := -1
		if pinnedIndex >= 0 {
			scanPinnedIdx = ensureScanCol(columns[pinnedIndex].Name)
		}
		plotColIdx := -1
		plotColName := plotColNameForDatasheetKey(target.key)
		if plotColName != "" {
			plotColIdx = ensureScanCol(plotColName)
		}
		checkPlotLock := false
		lockedPlots := map[string]bool{}
		sameAsProject := owner.AttachmentInfo[target.role] != nil &&
			owner.AttachmentInfo["project"] != nil &&
			os.SameFile(owner.AttachmentInfo[target.role], owner.AttachmentInfo["project"])
		if sameAsProject && plotColIdx >= 0 &&
			(target.key == "Env" || target.key == "Admin" || target.key == "Veg" || target.key == "Humus" || target.key == "Mineral" || target.key == "Other") &&
			!(target.key == "Env" && colMeta.Name == "Flag") {
			checkPlotLock = true
			envRel := vprocore.QuoteHeaderIdentifier("project") + "." + vprocore.QuoteHeaderIdentifier(owner.Selection.Project+"_Env")
			lockRows, lockErr := tx.QueryContext(ctx,
				`SELECT CAST("PlotNumber" AS TEXT) FROM `+envRel+` WHERE typeof("PlotNumber")='text' AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
			)
			if lockErr != nil {
				return nil, lockErr
			}
			for lockRows.Next() {
				var p string
				if scanErr := lockRows.Scan(&p); scanErr != nil {
					lockRows.Close()
					return nil, scanErr
				}
				lockedPlots[p] = true
			}
			if closeErr := errors.Join(lockRows.Err(), lockRows.Close()); closeErr != nil {
				return nil, closeErr
			}
		}

		soilHorizonIdx, soilUpperIdx, soilLowerIdx := -1, -1, -1
		checkSoilDepth := (target.key == "Humus" || target.key == "Mineral") &&
			(colMeta.Name == "Horizon" || colMeta.Name == "UpperDepth" || colMeta.Name == "LowerDepth")
		if checkSoilDepth {
			soilHorizonIdx = ensureScanCol("Horizon")
			soilUpperIdx = ensureScanCol("UpperDepth")
			soilLowerIdx = ensureScanCol("LowerDepth")
		}
		cfGravelIdx, cfCobblesIdx, cfStonesIdx, cfTotalIdx := -1, -1, -1, -1
		checkMineralCF := target.key == "Mineral" && vprocore.MineralCoarseFragColumns[colMeta.Name]
		if checkMineralCF {
			cfGravelIdx = ensureScanCol("PercentCoarseFragsGravel")
			cfCobblesIdx = ensureScanCol("PercentCoarseFragsCobbles")
			cfStonesIdx = ensureScanCol("PercentCoarseFragsStones")
			cfTotalIdx = ensureScanCol("PercentCoarseFragsTotal")
		}

		hierIDIdx := -1
		var hierParents map[int64]*int64
		checkHierarchyCycle := target.key == "Hierarchy" && strings.EqualFold(colMeta.Name, "Parent")
		if checkHierarchyCycle {
			hierIDIdx = ensureScanCol("ID")
			var loadErr error
			hierParents, loadErr = loadHierarchyParentsMap(ctx, tx, target.role, target.tableName)
			if loadErr != nil {
				return nil, loadErr
			}
		}

		rows, err := queryDatasheetWindowRows(ctx, tx, target.role, target.tableName, scanCols, whereSQL, whereArgs, orderSQL, 0, 0)
		if err != nil {
			return nil, err
		}

		preview := &DatasheetFindReplacePreview{
			ContextID: contextID,
			TableKey:  target.key,
			TableName: target.tableName,
			Column:    colMeta.Name,
			Items:     []DatasheetFindReplaceItem{},
		}

		for _, row := range rows {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			beforeCell := row.Cells[0]
			pinnedVal := row.RowID
			if scanPinnedIdx >= 0 && scanPinnedIdx < len(row.Cells) {
				pinnedVal = cellToDisplayString(row.Cells[scanPinnedIdx], scanCols[scanPinnedIdx].IsBoolean)
			}

			beforeText := cellToDisplayString(beforeCell, colMeta.IsBoolean)
			var afterText string
			matched := false

			if request.FindText == "" {
				// Empty find matches empty/NULL cells when exactCell is true
				if request.ExactCell && beforeCell.Storage == "null" {
					afterText = request.ReplaceText
					matched = request.ReplaceText != ""
				}
			} else if request.ExactCell {
				if request.MatchCase {
					if beforeCell.Storage != "null" && beforeText == request.FindText {
						afterText = request.ReplaceText
						matched = beforeText != afterText || (afterText == "" && beforeCell.Storage != "null")
					}
				} else {
					if beforeCell.Storage != "null" && strings.EqualFold(beforeText, request.FindText) {
						afterText = request.ReplaceText
						matched = beforeText != afterText || (afterText == "" && beforeCell.Storage != "null")
					}
				}
			} else {
				if beforeCell.Storage != "null" {
					if request.MatchCase {
						if strings.Contains(beforeText, request.FindText) {
							afterText = strings.ReplaceAll(beforeText, request.FindText, request.ReplaceText)
							matched = true
						}
					} else {
						replaced, ok := replaceSubstringInsensitive(beforeText, request.FindText, request.ReplaceText)
						if ok {
							afterText = replaced
							matched = true
						}
					}
				}
			}

			if !matched {
				continue
			}
			preview.MatchedRows++

			candidateCell, buildErr := buildReplacedCellFromString(colMeta, afterText)
			var valErr string
			normalizedCell := candidateCell
			if buildErr != nil {
				valErr = buildErr.Error()
			} else {
				_, _, norm, vErr := validateAndNormalizeDatasheetCell(target.key, colMeta, candidateCell, canEditMaster)
				if vErr != nil {
					valErr = vErr.Error()
				} else {
					normalizedCell = norm
				}
			}
			if valErr == "" && checkPlotLock && plotColIdx >= 0 && plotColIdx < len(row.Cells) && row.Cells[plotColIdx].Text != nil {
				plotVal := *row.Cells[plotColIdx].Text
				if lockedPlots[plotVal] {
					valErr = fmt.Sprintf("plot %q is locked (Flag = -1); unlock the plot before editing its cells", plotVal)
				}
			}
			if valErr == "" && checkSoilDepth && (soilUpperIdx >= 0 || soilLowerIdx >= 0) {
				var effHorizon, effUpper, effLower vprocore.ProjectMetadataCell
				if soilHorizonIdx >= 0 {
					effHorizon = row.Cells[soilHorizonIdx]
				}
				if soilUpperIdx >= 0 {
					effUpper = row.Cells[soilUpperIdx]
				}
				if soilLowerIdx >= 0 {
					effLower = row.Cells[soilLowerIdx]
				}
				switch colMeta.Name {
				case "Horizon":
					effHorizon = normalizedCell
				case "UpperDepth":
					effUpper = normalizedCell
				case "LowerDepth":
					effLower = normalizedCell
				}
				if sErr := validateSoilHorizonDepthSign(target.key, cellTextPtr(effHorizon), cellFloat64Ptr(effUpper), cellFloat64Ptr(effLower)); sErr != nil {
					valErr = sErr.Error()
				}
			}
			if valErr == "" && checkMineralCF {
				cellOrNull := func(idx int) vprocore.ProjectMetadataCell {
					if idx >= 0 && idx < len(row.Cells) {
						return row.Cells[idx]
					}
					return vprocore.ProjectMetadataCell{Storage: "null"}
				}
				effG, effC, effS, effT := cellOrNull(cfGravelIdx), cellOrNull(cfCobblesIdx), cellOrNull(cfStonesIdx), cellOrNull(cfTotalIdx)
				switch colMeta.Name {
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
					valErr = cfErr.Error()
				}
			}
			if valErr == "" && checkHierarchyCycle && hierIDIdx >= 0 && hierIDIdx < len(row.Cells) && row.Cells[hierIDIdx].Integer != nil {
				if nodeID, idErr := strconv.ParseInt(*row.Cells[hierIDIdx].Integer, 10, 64); idErr == nil {
					if hErr := validateCandidateHierarchyParent(nodeID, normalizedCell, hierParents); hErr != nil {
						valErr = hErr.Error()
					}
				}
			}
			if valErr != "" {
				preview.InvalidCount++
			} else {
				preview.ValidCount++
			}

			if len(preview.Items) < maxPreview {
				preview.Items = append(preview.Items, DatasheetFindReplaceItem{
					RowID:           row.RowID,
					PinnedIdentity:  pinnedVal,
					Column:          colMeta.Name,
					BeforeText:      beforeText,
					AfterText:       afterText,
					BeforeCell:      vprocore.CloneSiteUnitCell(beforeCell),
					AfterCell:       vprocore.CloneSiteUnitCell(normalizedCell),
					ValidationError: valErr,
					Edit: DatasheetCellEdit{
						RowID:  row.RowID,
						Column: colMeta.Name,
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
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return preview, nil
	})
}
