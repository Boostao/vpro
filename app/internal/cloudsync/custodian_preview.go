package cloudsync

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"slices"
	"strings"
	"time"
)

func buildStagingMergePreviewOnQueryer(
	ctx context.Context,
	q pgQueryer,
	submissionID string,
	baseDBPath string,
	baseProjectReq string,
) (StagingMergePreview, *cloudSnapshot, *cloudSnapshot, string, error) {
	t0 := time.Now()
	var projName, srcSHA string
	if err := q.QueryRow(ctx, `SELECT project_name, source_db_sha256 FROM staging.submissions WHERE submission_id = $1`, submissionID).Scan(&projName, &srcSHA); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return StagingMergePreview{}, nil, nil, "", fmt.Errorf("staging submission %s not found", submissionID)
		}
		return StagingMergePreview{}, nil, nil, "", err
	}

	srcSnap, err := loadPGSubsetSnapshot(ctx, q, "staging", projName, submissionID, nil)
	if err != nil {
		return StagingMergePreview{}, nil, nil, "", err
	}

	plotSet := map[string]bool{}
	for p := range srcSnap.plots {
		plotSet[p] = true
	}

	var baseSnap *cloudSnapshot
	var baseProj string
	if strings.TrimSpace(baseDBPath) != "" {
		// Load base plots matching source plots (or any base plots so target-deleted plots are detected)
		resolvedBase, bp, bErr := resolveProjectInSQLiteFile(ctx, baseDBPath, baseProjectReq)
		if bErr != nil {
			return StagingMergePreview{}, nil, nil, "", fmt.Errorf("base snapshot database: %w", bErr)
		}
		baseProj = bp
		bdb, oErr := sqlutil.OpenReadOnlyContext(ctx, resolvedBase)
		if oErr != nil {
			return StagingMergePreview{}, nil, nil, "", oErr
		}
		pRows, pErr := bdb.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS TEXT) FROM %s WHERE typeof("PlotNumber")='text'`, quotePGIdent(bp+"_Env")))
		if pErr == nil {
			for pRows.Next() {
				var p string
				if pRows.Scan(&p) == nil && p != "" {
					plotSet[p] = true
				}
			}
			pRows.Close()
		}
		_ = bdb.Close()
	}

	overlapPlots := make([]string, 0, len(plotSet))
	for p := range plotSet {
		overlapPlots = append(overlapPlots, p)
	}
	slices.Sort(overlapPlots)

	if strings.TrimSpace(baseDBPath) != "" {
		baseSnap, baseProj, err = loadSQLiteBaseSubsetSnapshot(ctx, baseDBPath, baseProjectReq, overlapPlots)
		if err != nil {
			return StagingMergePreview{}, nil, nil, "", err
		}
	}

	tgtSnap, err := loadPGSubsetSnapshot(ctx, q, "becmaster", "BECMaster", "", overlapPlots)
	if err != nil {
		return StagingMergePreview{}, nil, nil, "", err
	}

	dh := sha256.New()
	writeDigestItem(dh, submissionID)
	writeDigestItem(dh, hashCloudSnapshot(srcSnap))
	writeDigestItem(dh, hashCloudSnapshot(tgtSnap))
	writeDigestItem(dh, hashCloudSnapshot(baseSnap))
	digest := hex.EncodeToString(dh.Sum(nil))

	preview := StagingMergePreview{
		SubmissionID:            submissionID,
		SourceProject:           projName,
		TargetProject:           "BECMaster",
		BaseDBPath:              strings.TrimSpace(baseDBPath),
		BaseProject:             baseProj,
		PreviewDigest:           digest,
		Plots:                   make([]CloudMergePlotPreview, 0, len(overlapPlots)),
		Conflicts:               []CloudMergeConflictItem{},
		CustodianProtectedDiffs: []CloudMergeConflictItem{},
	}

	lookupBase := func(suffix, plot, rowKey, field string) (*string, bool) {
		if baseSnap == nil || !baseSnap.plots[plot] {
			return nil, false
		}
		rm, has := baseSnap.cells[suffix][plot+"\x00"+rowKey]
		if !has {
			return nil, true
		}
		if field == "*" {
			s := summarizeCloudRow(VP08ColumnsBySuffix(suffix), rm)
			return &s, true
		}
		return rm[field], true
	}

	for _, plot := range overlapPlots {
		inSrc := srcSnap.plots[plot]
		inTgt := tgtSnap.plots[plot]

		if inSrc && !inTgt {
			if baseSnap != nil && baseSnap.plots[plot] {
				cid := makeCloudConflictID(plot, "Env", "Plot")
				present := "Present"
				item := CloudMergeConflictItem{
					ConflictID:        cid,
					PlotNumber:        plot,
					Table:             "Env",
					Key:               "Plot",
					Field:             "PlotNumber",
					BaseVal:           &present,
					SourceVal:         &present,
					TargetVal:         nil,
					Kind:              "Conflict",
					DefaultResolution: MergeResolutionKeepTarget,
				}
				preview.ConflictCount++
				preview.Plots = append(preview.Plots, CloudMergePlotPreview{
					PlotNumber: plot,
					Category:   "Conflict",
					Items:      []CloudMergeConflictItem{item},
				})
				preview.Conflicts = append(preview.Conflicts, item)
			} else {
				preview.AddedCount++
				preview.Plots = append(preview.Plots, CloudMergePlotPreview{
					PlotNumber: plot,
					Category:   "Added",
					Items:      []CloudMergeConflictItem{},
				})
			}
			continue
		}

		if !inSrc && inTgt {
			preview.TargetOnlyCount++
			preview.Plots = append(preview.Plots, CloudMergePlotPreview{
				PlotNumber: plot,
				Category:   "TargetOnly",
				Items:      []CloudMergeConflictItem{},
			})
			continue
		}
		if !inSrc && !inTgt {
			continue
		}

		// Both staging and becmaster contain this PlotNumber — diff all 6 plot tables!
		var items []CloudMergeConflictItem
		hasRealConflict := false
		hasFastForward := false

		for _, suffix := range mergeTableSuffixes {
			cols := VP08ColumnsBySuffix(suffix)
			srcRows := plotRowsFromSnap(srcSnap, suffix, plot)
			tgtRows := plotRowsFromSnap(tgtSnap, suffix, plot)

			rowKeySet := map[string]bool{}
			for rk := range srcRows {
				rowKeySet[rk] = true
			}
			for rk := range tgtRows {
				rowKeySet[rk] = true
			}
			rowKeys := make([]string, 0, len(rowKeySet))
			for rk := range rowKeySet {
				rowKeys = append(rowKeys, rk)
			}
			slices.Sort(rowKeys)

			isAmbiguousKey := func(rowKey string) bool {
				baseK := rowKey
				if hashIdx := strings.IndexByte(rowKey, '#'); hashIdx >= 0 {
					baseK = rowKey[:hashIdx]
				}
				return strings.Contains(rowKey, "#") || srcRows[baseK+"#2"] != nil || tgtRows[baseK+"#2"] != nil
			}

			for _, rk := range rowKeys {
				sRow, hasS := srcRows[rk]
				tRow, hasT := tgtRows[rk]
				ambiguous := suffix != "Env" && suffix != "Admin" && isAmbiguousKey(rk)
				if hasS && !hasT {
					sSum := summarizeCloudRow(cols, sRow)
					bVal, inBase := lookupBase(suffix, plot, rk, "*")
					kind, defRes := "Conflict", MergeResolutionKeepTarget
					if !ambiguous && baseSnap != nil && inBase && bVal == nil {
						kind = "FastForward"
						defRes = MergeResolutionAcceptSource
						hasFastForward = true
					} else {
						hasRealConflict = true
					}
					item := CloudMergeConflictItem{
						ConflictID:        makeCloudConflictID(plot, suffix, rk),
						PlotNumber:        plot,
						Table:             suffix,
						Key:               rk,
						Field:             "*",
						BaseVal:           bVal,
						SourceVal:         &sSum,
						TargetVal:         nil,
						Kind:              kind,
						DefaultResolution: defRes,
					}
					items = append(items, item)
					if kind == "Conflict" {
						preview.Conflicts = append(preview.Conflicts, item)
					}
					continue
				}
				if !hasS && hasT {
					tSum := summarizeCloudRow(cols, tRow)
					bVal, inBase := lookupBase(suffix, plot, rk, "*")
					kind, defRes := "Conflict", MergeResolutionKeepTarget
					if !ambiguous && baseSnap != nil && inBase {
						if sameNullableStr(&tSum, bVal) {
							kind = "FastForward"
							defRes = MergeResolutionAcceptSource
							hasFastForward = true
						} else {
							hasRealConflict = true
						}
					} else {
						hasRealConflict = true
					}
					item := CloudMergeConflictItem{
						ConflictID:        makeCloudConflictID(plot, suffix, rk),
						PlotNumber:        plot,
						Table:             suffix,
						Key:               rk,
						Field:             "*",
						BaseVal:           bVal,
						SourceVal:         nil,
						TargetVal:         &tSum,
						Kind:              kind,
						DefaultResolution: defRes,
					}
					items = append(items, item)
					if kind == "Conflict" {
						preview.Conflicts = append(preview.Conflicts, item)
					}
					continue
				}

				for _, col := range cols {
					if col.Name == "ID" || col.Name == "PlotNumber" || col.Name == "Plot" {
						continue
					}
					sv := sRow[col.Name]
					tv := tRow[col.Name]
					if sameNullableStr(sv, tv) {
						continue
					}
					fieldKey := col.Name
					if suffix != "Env" && suffix != "Admin" {
						fieldKey = rk + "." + col.Name
					}
					bVal, inBase := lookupBase(suffix, plot, rk, col.Name)
					isProtected := suffix == "Admin" && CustodianProtectedAdminFields[col.Name]
					kind, defRes := "Conflict", MergeResolutionKeepTarget
					if !isProtected && !ambiguous && baseSnap != nil && inBase {
						if sameNullableStr(tv, bVal) && !sameNullableStr(sv, bVal) {
							kind = "FastForward"
							defRes = MergeResolutionAcceptSource
							hasFastForward = true
						} else if sameNullableStr(sv, bVal) && !sameNullableStr(tv, bVal) {
							kind = "TargetModifiedOnly"
							defRes = MergeResolutionKeepTarget
						} else {
							hasRealConflict = true
						}
					} else {
						hasRealConflict = true
					}
					item := CloudMergeConflictItem{
						ConflictID:         makeCloudConflictID(plot, suffix, fieldKey),
						PlotNumber:         plot,
						Table:              suffix,
						Key:                fieldKey,
						Field:              col.Name,
						BaseVal:            bVal,
						SourceVal:          sv,
						TargetVal:          tv,
						Kind:               kind,
						DefaultResolution:  defRes,
						CustodianProtected: isProtected,
					}
					items = append(items, item)
					if kind == "Conflict" {
						preview.Conflicts = append(preview.Conflicts, item)
					}
					if isProtected {
						preview.CustodianProtectedDiffs = append(preview.CustodianProtectedDiffs, item)
					}
				}
			}
		}

		if len(items) == 0 {
			preview.IdenticalCount++
			preview.Plots = append(preview.Plots, CloudMergePlotPreview{
				PlotNumber: plot,
				Category:   "Identical",
				Items:      []CloudMergeConflictItem{},
			})
			continue
		}

		category := "Conflict"
		if !hasRealConflict && hasFastForward {
			category = "FastForward"
			preview.FastForwardCount++
		} else if !hasRealConflict {
			category = "TargetOnly"
			preview.TargetOnlyCount++
		} else {
			preview.ConflictCount++
		}
		preview.Plots = append(preview.Plots, CloudMergePlotPreview{
			PlotNumber: plot,
			Category:   category,
			Items:      items,
		})
	}

	preview.ElapsedMs = time.Since(t0).Milliseconds()
	return preview, srcSnap, tgtSnap, srcSHA, nil
}

// PreviewStagingToMasterMerge computes a fast (<500ms) indexed 3-way merge preview
// of staging.<submission> against overlapping plots in becmaster.
func (m *Manager) PreviewStagingToMasterMerge(ctx context.Context, req StagingMergePreviewRequest) (StagingMergePreview, error) {
	subID := strings.TrimSpace(req.SubmissionID)
	if _, err := uuid.Parse(subID); err != nil {
		return StagingMergePreview{}, errors.New("submissionId must be a valid UUID")
	}
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return StagingMergePreview{}, err
	}
	preview, _, _, _, err := buildStagingMergePreviewOnQueryer(ctx, pool, subID, req.BaseDBPath, req.BaseProject)
	if err != nil {
		return StagingMergePreview{}, wrapRedactedError("preview staging-to-BECMaster merge", err, creds)
	}
	return preview, nil
}

func validateCloudMergeCell(suffix string, col ColumnSpec, cell cloudCell) error {
	if cell.kind == "null" {
		return nil
	}
	if cell.kind == "text" {
		if err := ValidateUTF16Bound(suffix+"."+col.Name, cell.textVal, col.UTF16MaxLength); err != nil {
			return err
		}
	}
	if col.IsSingleCover && (cell.kind == "float" || cell.kind == "int") {
		v := cell.fltVal
		if cell.kind == "int" {
			v = float64(cell.intVal)
		}
		if _, ok := NarrowSingleCover(v); !ok {
			return fmt.Errorf("%s.%s cover=%v must be >= 0 and < 100 in IEEE-754 SINGLE", suffix, col.Name, v)
		}
	}
	return nil
}

func validateHorizonRowDepth(suffix string, row map[string]cloudCell) error {
	if suffix != "Humus" && suffix != "Mineral" {
		return nil
	}
	hz := ""
	if row["Horizon"].kind == "text" {
		hz = row["Horizon"].textVal
	}
	var uPtr, lPtr *float64
	if uc := row["UpperDepth"]; uc.kind == "float" {
		v := uc.fltVal
		uPtr = &v
	} else if uc.kind == "int" {
		v := float64(uc.intVal)
		uPtr = &v
	}
	if lc := row["LowerDepth"]; lc.kind == "float" {
		v := lc.fltVal
		lPtr = &v
	} else if lc.kind == "int" {
		v := float64(lc.intVal)
		lPtr = &v
	}
	return ValidateLMH25HorizonDepth(suffix, hz, uPtr, lPtr)
}

func allocateMasterChildID(ctx context.Context, tx pgx.Tx, childTable string) (int64, error) {
	var nextID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO becmaster.child_identity_watermark (child_table, max_id)
		VALUES ($1, COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0) + 1)
		ON CONFLICT (child_table) DO UPDATE SET
			max_id = GREATEST(
				becmaster.child_identity_watermark.max_id + 1,
				COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0) + 1
			)
		RETURNING max_id
	`, childTable).Scan(&nextID); err != nil {
		return 0, err
	}
	for {
		tag, err := tx.Exec(ctx, `INSERT INTO becmaster.child_identity (child_table, id) VALUES ($1, $2) ON CONFLICT (child_table, id) DO NOTHING`, childTable, nextID)
		if err != nil {
			return 0, err
		}
		if tag.RowsAffected() == 1 {
			_, _ = tx.Exec(ctx, `UPDATE becmaster.child_identity_watermark SET max_id = GREATEST(max_id, $2) WHERE child_table = $1`, childTable, nextID)
			return nextID, nil
		}
		nextID++
	}
}

func reserveMasterChildID(ctx context.Context, tx pgx.Tx, childTable string, id int64) error {
	if _, err := tx.Exec(ctx, `INSERT INTO becmaster.child_identity (child_table, id) VALUES ($1, $2) ON CONFLICT (child_table, id) DO NOTHING`, childTable, id); err != nil {
		return err
	}
	if id > 0 {
		_, _ = tx.Exec(ctx, `
			INSERT INTO becmaster.child_identity_watermark (child_table, max_id)
			VALUES ($1, $2)
			ON CONFLICT (child_table) DO UPDATE SET max_id = GREATEST(becmaster.child_identity_watermark.max_id, EXCLUDED.max_id)
		`, childTable, id)
	}
	return nil
}
