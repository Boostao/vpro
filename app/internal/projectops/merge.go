package projectops

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	MergeResolutionKeepTarget   = "keep_target"
	MergeResolutionAcceptSource = "accept_source"
)

type ThreeWayMergePreviewRequest struct {
	SourcePath          string `json:"sourcePath"`
	SourceProject       string `json:"sourceProject,omitempty"`
	TargetPath          string `json:"targetPath,omitempty"`
	TargetProject       string `json:"targetProject,omitempty"`
	BasePath            string `json:"basePath,omitempty"`
	BaseProject         string `json:"baseProject,omitempty"`
	CaseInsensitiveText bool   `json:"caseInsensitiveText,omitempty"`
}

func (r *ThreeWayMergePreviewRequest) UnmarshalJSON(data []byte) error {
	type plain ThreeWayMergePreviewRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type MergeConflictItem struct {
	ConflictID        string  `json:"conflictId"`
	PlotNumber        string  `json:"plotNumber"`
	Table             string  `json:"table"`
	Key               string  `json:"key"`
	Field             string  `json:"field"`
	BaseVal           *string `json:"baseVal,omitempty"`
	SourceVal         *string `json:"sourceVal"`
	TargetVal         *string `json:"targetVal"`
	Kind              string  `json:"kind"`              // "FastForward" | "Conflict" | "TargetModifiedOnly" | "SourceDelete"
	DefaultResolution string  `json:"defaultResolution"` // "accept_source" | "keep_target"
	srcRowKey         string
	tgtRowKey         string
}

type MergePlotPreview struct {
	PlotNumber string              `json:"plotNumber"`
	Category   string              `json:"category"` // "Added" | "Identical" | "FastForward" | "Conflict" | "TargetOnly" | "SourceDelete"
	Items      []MergeConflictItem `json:"items"`
}

type ThreeWayMergePreview struct {
	SourcePath            string              `json:"sourcePath"`
	SourceProject         string              `json:"sourceProject"`
	TargetPath            string              `json:"targetPath"`
	TargetProject         string              `json:"targetProject"`
	BasePath              string              `json:"basePath,omitempty"`
	BaseProject           string              `json:"baseProject,omitempty"`
	PreviewDigest         string              `json:"previewDigest"`
	AddedCount            int                 `json:"addedCount"`
	IdenticalCount        int                 `json:"identicalCount"`
	FastForwardCount      int                 `json:"fastForwardCount"`
	ConflictCount         int                 `json:"conflictCount"`
	TargetOnlyCount       int                 `json:"targetOnlyCount"`
	SourceDeleteCount     int                 `json:"sourceDeleteCount"`
	MetadataConflictCount int                 `json:"metadataConflictCount,omitempty"`
	Plots                 []MergePlotPreview  `json:"plots"`
	Conflicts             []MergeConflictItem `json:"conflicts"`
	MetadataItems         []MergeConflictItem `json:"metadataItems,omitempty"`
}

type ThreeWayMergeExecuteRequest struct {
	SourcePath                string            `json:"sourcePath"`
	SourceProject             string            `json:"sourceProject,omitempty"`
	TargetPath                string            `json:"targetPath,omitempty"`
	TargetProject             string            `json:"targetProject,omitempty"`
	BasePath                  string            `json:"basePath,omitempty"`
	BaseProject               string            `json:"baseProject,omitempty"`
	ExpectedPreviewDigest     string            `json:"expectedPreviewDigest,omitempty"`
	DefaultConflictResolution string            `json:"defaultConflictResolution,omitempty"`
	PlotResolutions           map[string]string `json:"plotResolutions,omitempty"`
	FieldResolutions          map[string]string `json:"fieldResolutions,omitempty"`
	CaseInsensitiveText       bool              `json:"caseInsensitiveText,omitempty"`
}

func (r *ThreeWayMergeExecuteRequest) UnmarshalJSON(data []byte) error {
	type plain ThreeWayMergeExecuteRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type ThreeWayMergeResult struct {
	SourceProject      string  `json:"sourceProject"`
	TargetProject      string  `json:"targetProject"`
	TargetPath         string  `json:"targetPath"`
	AddedPlots         int     `json:"addedPlots"`
	UpdatedPlots       int     `json:"updatedPlots"`
	SkippedPlots       int     `json:"skippedPlots"`
	DeletedPlots       int     `json:"deletedPlots,omitempty"`
	AllocatedChildIDs  []int64 `json:"allocatedChildIds"`
	ReservedDeletedIDs []int64 `json:"reservedDeletedIds"`
	AuditRowsWritten   int     `json:"auditRowsWritten"`
}

func makeConflictID(plot, table, key string) string {
	return plot + "::" + table + "::" + key
}

func validateMergeResolutionChoice(choice string) error {
	switch choice {
	case MergeResolutionKeepTarget, MergeResolutionAcceptSource:
		return nil
	default:
		return fmt.Errorf("invalid merge resolution %q (expected %q or %q)", choice, MergeResolutionKeepTarget, MergeResolutionAcceptSource)
	}
}

func resolveMergeEndpoints(ctx context.Context, s *vprocore.ContextService, contextID string, srcPathReq, srcProjReq, tgtPathReq, tgtProjReq, basePathReq, baseProjReq string) (srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor string, err error) {
	if strings.TrimSpace(srcPathReq) == "" {
		return "", "", "", "", "", "", "", errors.New("sourcePath (staging .db) is required for 3-way merge")
	}
	actor = "VProUser"
	var activePath, activeProj string
	if s != nil && contextID != "" {
		snap, sErr := inspectContextSnapshot(ctx, s, contextID)
		if sErr != nil {
			return "", "", "", "", "", "", "", sErr
		}
		activePath = snap.ProjectPath
		activeProj = snap.Project
		actor = snap.CurrentUser
	}
	srcPath, srcProj, err = resolveProjectInDatabase(ctx, srcPathReq, srcProjReq)
	if err != nil {
		return "", "", "", "", "", "", "", fmt.Errorf("source staging database: %w", err)
	}
	if strings.TrimSpace(tgtPathReq) == "" {
		if activePath == "" {
			return "", "", "", "", "", "", "", errors.New("targetPath is required when no active project context is provided")
		}
		tgtPath = activePath
		tgtProj = activeProj
		if strings.TrimSpace(tgtProjReq) != "" {
			tgtPath, tgtProj, err = resolveProjectInDatabase(ctx, tgtPath, tgtProjReq)
			if err != nil {
				return "", "", "", "", "", "", "", err
			}
		}
	} else {
		tgtPath, tgtProj, err = resolveProjectInDatabase(ctx, tgtPathReq, tgtProjReq)
		if err != nil {
			return "", "", "", "", "", "", "", fmt.Errorf("target database: %w", err)
		}
	}
	if vprocore.SameDesktopPath(srcPath, tgtPath) && srcProj == tgtProj {
		return "", "", "", "", "", "", "", errors.New("source and target refer to the same project in the same database file")
	}
	if strings.TrimSpace(basePathReq) != "" {
		basePath, baseProj, err = resolveProjectInDatabase(ctx, basePathReq, baseProjReq)
		if err != nil {
			return "", "", "", "", "", "", "", fmt.Errorf("base ancestor database: %w", err)
		}
	}
	return srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, actor, nil
}

func buildThreeWayMergePreviewInternal(ctx context.Context, srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj string, tgtQueryer sqliteQueryer, caseInsensitive bool) (ThreeWayMergePreview, *loadedProjectSnapshot, *loadedProjectSnapshot, *loadedProjectSnapshot, error) {
	srcSnap, err := loadProjectSnapshotForDiff(ctx, srcPath, srcProj)
	if err != nil {
		return ThreeWayMergePreview{}, nil, nil, nil, err
	}
	var tgtSnap *loadedProjectSnapshot
	if tgtQueryer != nil {
		tgtSnap, err = loadProjectSnapshotFromQueryer(ctx, tgtQueryer, tgtPath, tgtProj)
	} else {
		tgtSnap, err = loadProjectSnapshotForDiff(ctx, tgtPath, tgtProj)
	}
	if err != nil {
		return ThreeWayMergePreview{}, nil, nil, nil, err
	}
	var baseSnap *loadedProjectSnapshot
	if basePath != "" {
		baseSnap, err = loadProjectSnapshotForDiff(ctx, basePath, baseProj)
		if err != nil {
			return ThreeWayMergePreview{}, nil, nil, nil, err
		}
	}
	digest := computeMergeSnapshotDigest(srcSnap, tgtSnap, baseSnap)

	diff := diffLoadedSnapshotsWithOptions(srcSnap, tgtSnap, caseInsensitive)
	preview := ThreeWayMergePreview{
		SourcePath:    srcPath,
		SourceProject: srcProj,
		TargetPath:    tgtPath,
		TargetProject: tgtProj,
		BasePath:      basePath,
		BaseProject:   baseProj,
		PreviewDigest: digest,
		Plots:         make([]MergePlotPreview, 0, len(diff.Plots)),
		Conflicts:     []MergeConflictItem{},
		MetadataItems: []MergeConflictItem{},
	}

	skipPlotCols := map[string]bool{"ID": true, "PlotNumber": true, "Plot": true}
	lookupBaseVal := func(fd FieldDiff, plot string) (*string, bool) {
		if baseSnap == nil || !baseSnap.plots[plot] {
			return nil, false
		}
		if fd.Table == "Env" || fd.Table == "Admin" {
			rowMap, hasRow := baseSnap.cells[fd.Table][plot][fd.Table]
			if !hasRow {
				return nil, true
			}
			return rowMap[fd.Field], true
		}

		// Child table (Veg, Humus, Mineral, Other): match canonically against Base rows
		// belonging to the same natural baseGroupKey (supporting multiset additions/deletes).
		bRows := baseSnap.cells[fd.Table][plot]
		var groupKeys []string
		for bk := range bRows {
			rawG := baseSnap.baseKeys[fd.Table][plot][bk]
			if rawG == "" {
				rawG = bk
			}
			cg := rawG
			if caseInsensitive {
				cg = strings.ToLower(rawG)
			}
			if fd.baseGroupKey == "" || cg == fd.baseGroupKey || bk == fd.Key {
				groupKeys = append(groupKeys, bk)
			}
		}
		slices.Sort(groupKeys)

		if fd.Field == "*" {
			colOrder := append([]string(nil), baseSnap.columns[fd.Table]...)
			if fd.SourceVal != nil && fd.TargetVal == nil {
				// Source has row; check if Base had an exact matching row.
				sRow := srcSnap.cells[fd.Table][plot][fd.srcRowKey]
				sSig := rowMatchSignature(colOrder, sRow, skipPlotCols, caseInsensitive)
				for _, bk := range groupKeys {
					if rowMatchSignature(colOrder, bRows[bk], skipPlotCols, caseInsensitive) == sSig {
						summary := summarizeRowMap(colOrder, bRows[bk])
						return &summary, true
					}
				}
				return nil, true
			}
			if fd.SourceVal == nil && fd.TargetVal != nil {
				// Target has row; check if Base had an exact matching row.
				tRow := tgtSnap.cells[fd.Table][plot][fd.tgtRowKey]
				tSig := rowMatchSignature(colOrder, tRow, skipPlotCols, caseInsensitive)
				for _, bk := range groupKeys {
					if rowMatchSignature(colOrder, bRows[bk], skipPlotCols, caseInsensitive) == tSig {
						summary := summarizeRowMap(colOrder, bRows[bk])
						return &summary, true
					}
				}
				if len(groupKeys) > 0 {
					summary := summarizeRowMap(colOrder, bRows[groupKeys[0]])
					return &summary, true
				}
				return nil, true
			}
			return nil, true
		}

		var bRow map[string]*string
		if fd.srcRowKey != "" {
			if r, ok := bRows[fd.srcRowKey]; ok {
				bRow = r
			}
		}
		if bRow == nil && fd.tgtRowKey != "" {
			if r, ok := bRows[fd.tgtRowKey]; ok {
				bRow = r
			}
		}
		if bRow == nil && len(groupKeys) == 1 {
			bRow = bRows[groupKeys[0]]
		}
		if bRow == nil {
			return nil, true
		}
		return bRow[fd.Field], true
	}

	for _, pd := range diff.Plots {
		switch pd.Status {
		case "Added":
			// If Base had this plot and Target deleted it while Source kept it, classify as Conflict!
			if baseSnap != nil && baseSnap.plots[pd.PlotNumber] {
				cid := makeConflictID(pd.PlotNumber, "Env", "Plot")
				present := "Present"
				item := MergeConflictItem{
					ConflictID:        cid,
					PlotNumber:        pd.PlotNumber,
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
				preview.Plots = append(preview.Plots, MergePlotPreview{
					PlotNumber: pd.PlotNumber,
					Category:   "Conflict",
					Items:      []MergeConflictItem{item},
				})
				preview.Conflicts = append(preview.Conflicts, item)
			} else {
				preview.AddedCount++
				preview.Plots = append(preview.Plots, MergePlotPreview{
					PlotNumber: pd.PlotNumber,
					Category:   "Added",
					Items:      []MergeConflictItem{},
				})
			}
		case "Removed":
			if baseSnap != nil && baseSnap.plots[pd.PlotNumber] {
				// Source deleted a plot that existed in Base & Target:
				// unchanged vs Base -> SourceDelete (fast-forward delete); modified vs Base -> Conflict.
				tgtVsBase := diffSinglePlotSnapshots(tgtSnap, baseSnap, pd.PlotNumber, caseInsensitive)
				cid := makeConflictID(pd.PlotNumber, "Env", "Plot")
				present := "Present"
				if len(tgtVsBase) == 0 {
					item := MergeConflictItem{
						ConflictID:        cid,
						PlotNumber:        pd.PlotNumber,
						Table:             "Env",
						Key:               "Plot",
						Field:             "PlotNumber",
						BaseVal:           &present,
						SourceVal:         nil,
						TargetVal:         &present,
						Kind:              "SourceDelete",
						DefaultResolution: MergeResolutionAcceptSource,
					}
					preview.SourceDeleteCount++
					preview.Plots = append(preview.Plots, MergePlotPreview{
						PlotNumber: pd.PlotNumber,
						Category:   "SourceDelete",
						Items:      []MergeConflictItem{item},
					})
				} else {
					item := MergeConflictItem{
						ConflictID:        cid,
						PlotNumber:        pd.PlotNumber,
						Table:             "Env",
						Key:               "Plot",
						Field:             "PlotNumber",
						BaseVal:           &present,
						SourceVal:         nil,
						TargetVal:         &present,
						Kind:              "Conflict",
						DefaultResolution: MergeResolutionKeepTarget,
					}
					preview.ConflictCount++
					preview.Plots = append(preview.Plots, MergePlotPreview{
						PlotNumber: pd.PlotNumber,
						Category:   "Conflict",
						Items:      []MergeConflictItem{item},
					})
					preview.Conflicts = append(preview.Conflicts, item)
				}
			} else {
				preview.TargetOnlyCount++
				preview.Plots = append(preview.Plots, MergePlotPreview{
					PlotNumber: pd.PlotNumber,
					Category:   "TargetOnly",
					Items:      []MergeConflictItem{},
				})
			}
		case "Identical":
			preview.IdenticalCount++
			preview.Plots = append(preview.Plots, MergePlotPreview{
				PlotNumber: pd.PlotNumber,
				Category:   "Identical",
				Items:      []MergeConflictItem{},
			})
		case "Modified":
			var items []MergeConflictItem
			hasRealConflict := false
			hasFastForward := false
			for _, fd := range pd.FieldDiffs {
				bVal, inBase := lookupBaseVal(fd, pd.PlotNumber)
				kind := "Conflict"
				defRes := MergeResolutionKeepTarget
				if baseSnap != nil && inBase {
					if sameNullableText(fd.TargetVal, bVal, caseInsensitive) && !sameNullableText(fd.SourceVal, bVal, caseInsensitive) {
						kind = "FastForward"
						defRes = MergeResolutionAcceptSource
						hasFastForward = true
					} else if sameNullableText(fd.SourceVal, bVal, caseInsensitive) && !sameNullableText(fd.TargetVal, bVal, caseInsensitive) {
						kind = "TargetModifiedOnly"
						defRes = MergeResolutionKeepTarget
					} else {
						hasRealConflict = true
					}
				} else {
					hasRealConflict = true
				}
				item := MergeConflictItem{
					ConflictID:        makeConflictID(pd.PlotNumber, fd.Table, fd.Key),
					PlotNumber:        pd.PlotNumber,
					Table:             fd.Table,
					Key:               fd.Key,
					Field:             fd.Field,
					BaseVal:           bVal,
					SourceVal:         fd.SourceVal,
					TargetVal:         fd.TargetVal,
					Kind:              kind,
					DefaultResolution: defRes,
					srcRowKey:         fd.srcRowKey,
					tgtRowKey:         fd.tgtRowKey,
				}
				items = append(items, item)
				if kind == "Conflict" {
					preview.Conflicts = append(preview.Conflicts, item)
				}
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
			preview.Plots = append(preview.Plots, MergePlotPreview{
				PlotNumber: pd.PlotNumber,
				Category:   category,
				Items:      items,
			})
		}
	}

	// Reconcile <Project>_Metadata differences using Base snapshot when present.
	if len(diff.MetadataDiffs) > 0 {
		for _, fd := range diff.MetadataDiffs {
			var bVal *string
			inBase := false
			if baseSnap != nil && len(baseSnap.metaRows) > 0 {
				inBase = true
				if fd.Field == "*" {
					skipID := map[string]bool{"ID": true}
					if fd.SourceVal != nil && fd.TargetVal == nil {
						sSig := rowMatchSignature(srcSnap.metaColumns, srcSnap.metaRows[fd.srcRowKey], skipID, caseInsensitive)
						for _, bRow := range baseSnap.metaRows {
							if rowMatchSignature(baseSnap.metaColumns, bRow, skipID, caseInsensitive) == sSig {
								summary := summarizeRowMap(baseSnap.metaColumns, bRow)
								bVal = &summary
								break
							}
						}
					} else if fd.SourceVal == nil && fd.TargetVal != nil {
						tSig := rowMatchSignature(tgtSnap.metaColumns, tgtSnap.metaRows[fd.tgtRowKey], skipID, caseInsensitive)
						for _, bRow := range baseSnap.metaRows {
							if rowMatchSignature(baseSnap.metaColumns, bRow, skipID, caseInsensitive) == tSig {
								summary := summarizeRowMap(baseSnap.metaColumns, bRow)
								bVal = &summary
								break
							}
						}
					}
				} else {
					var bRow map[string]*string
					if fd.srcRowKey != "" {
						bRow = baseSnap.metaRows[fd.srcRowKey]
					}
					if bRow == nil && fd.tgtRowKey != "" {
						bRow = baseSnap.metaRows[fd.tgtRowKey]
					}
					if bRow == nil && fd.baseGroupKey != "" {
						for mk, cand := range baseSnap.metaRows {
							if strings.EqualFold(mk, fd.baseGroupKey) {
								bRow = cand
								break
							}
						}
					}
					if bRow != nil {
						bVal = bRow[fd.Field]
					}
				}
			}

			kind := "Conflict"
			defRes := MergeResolutionKeepTarget
			if inBase {
				if sameNullableText(fd.TargetVal, bVal, caseInsensitive) && !sameNullableText(fd.SourceVal, bVal, caseInsensitive) {
					kind = "FastForward"
					defRes = MergeResolutionAcceptSource
				} else if sameNullableText(fd.SourceVal, bVal, caseInsensitive) && !sameNullableText(fd.TargetVal, bVal, caseInsensitive) {
					kind = "TargetModifiedOnly"
					defRes = MergeResolutionKeepTarget
				}
			}
			item := MergeConflictItem{
				ConflictID:        makeConflictID("METADATA", "Metadata", fd.Key),
				PlotNumber:        "",
				Table:             "Metadata",
				Key:               fd.Key,
				Field:             fd.Field,
				BaseVal:           bVal,
				SourceVal:         fd.SourceVal,
				TargetVal:         fd.TargetVal,
				Kind:              kind,
				DefaultResolution: defRes,
				srcRowKey:         fd.srcRowKey,
				tgtRowKey:         fd.tgtRowKey,
			}
			preview.MetadataItems = append(preview.MetadataItems, item)
			if kind == "Conflict" {
				preview.MetadataConflictCount++
				preview.Conflicts = append(preview.Conflicts, item)
			}
		}
	}

	return preview, srcSnap, tgtSnap, baseSnap, nil
}

// PreviewThreeWayMerge inspects Source (Staging.db), Target (active or Master.db),
// and optional Base ancestor .db, categorizing every plot and field-level conflict.
func PreviewThreeWayMerge(s *vprocore.ContextService, ctx context.Context, contextID string, req ThreeWayMergePreviewRequest) (ThreeWayMergePreview, error) {
	srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, _, err := resolveMergeEndpoints(
		ctx, s, contextID,
		req.SourcePath, req.SourceProject,
		req.TargetPath, req.TargetProject,
		req.BasePath, req.BaseProject,
	)
	if err != nil {
		return ThreeWayMergePreview{}, err
	}
	preview, _, _, _, err := buildThreeWayMergePreviewInternal(ctx, srcPath, srcProj, tgtPath, tgtProj, basePath, baseProj, nil, req.CaseInsensitiveText)
	return preview, err
}
