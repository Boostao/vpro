package vegreport

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// applySummaryVegetationLumpAndVariants folds raw Veg rows according to the
// active *_Lump table and/or SVSubSppAsSpp (CombineVariants) by summing layer
// covers per (PlotNumber, MappedSpecies) and capping sums at 99% without mutating SQLite.
func applySummaryVegetationLumpAndVariants(
	ctx context.Context,
	tx *sql.Tx,
	veg, species vprocore.ProjectMetadataTable,
	rawLumpTable string,
	combineVariants bool,
) (vprocore.ProjectMetadataTable, string, []longVegetationLumpRow, error) {
	if strings.TrimSpace(rawLumpTable) == "" && !combineVariants {
		return veg, "", nil, nil
	}
	plan, err := loadLongVegetationLumpPlan(ctx, tx, species, rawLumpTable, combineVariants)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, "", nil, err
	}
	if len(plan.ActiveMap) == 0 {
		return veg, plan.TableLabel, plan.Rows, nil
	}

	vc, err := vprocore.SiteUnitTransferColumns(veg, "PlotNumber", "Species")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, "", nil, err
	}
	coverNames := append(append([]string{}, longVegetationCoverColumns()...), "TotalA", "TotalB")
	coverCols := make([]int, 0, len(coverNames))
	for _, name := range coverNames {
		idx := -1
		for i, col := range veg.Columns {
			if col.Name == name {
				idx = i
				break
			}
		}
		coverCols = append(coverCols, idx)
	}

	type mergeKey struct{ plot, species string }
	type accum struct {
		row      vprocore.ProjectMetadataRow
		sums     []*big.Rat
		hasValue []bool
	}
	groups := map[mergeKey]*accum{}
	order := make([]mergeKey, 0, len(veg.Rows))
	passthrough := make([]vprocore.ProjectMetadataRow, 0)
	max99 := big.NewRat(99, 1)

	for _, row := range veg.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, "", nil, err
		}
		plotCell := row.Cells[vc["PlotNumber"]]
		sppCell := row.Cells[vc["Species"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, "", nil, err
		}
		sppStr, err := vprocore.VegetationReportIdentity(sppCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, "", nil, err
		}
		if plotStr == nil || sppStr == nil {
			passthrough = append(passthrough, row)
			continue
		}
		mapped := *sppStr
		if target, ok := plan.ActiveMap[strings.ToUpper(strings.TrimSpace(mapped))]; ok {
			mapped = target
		}
		k := mergeKey{plot: *plotStr, species: mapped}
		entry, exists := groups[k]
		if !exists {
			clonedCells := make([]vprocore.ProjectMetadataCell, len(row.Cells))
			for i, c := range row.Cells {
				clonedCells[i] = vprocore.CloneSiteUnitCell(c)
			}
			mCopy := mapped
			clonedCells[vc["Species"]] = vprocore.ProjectMetadataCell{Storage: "text", Text: &mCopy}
			entry = &accum{
				row:      vprocore.ProjectMetadataRow{RowID: row.RowID, Cells: clonedCells},
				sums:     make([]*big.Rat, len(coverCols)),
				hasValue: make([]bool, len(coverCols)),
			}
			for i := range coverCols {
				entry.sums[i] = new(big.Rat)
			}
			groups[k] = entry
			order = append(order, k)
		}
		for i, cIdx := range coverCols {
			if cIdx < 0 {
				continue
			}
			num, err := vprocore.VegetationReportNumber(row.Cells[cIdx])
			if err != nil {
				return vprocore.ProjectMetadataTable{}, "", nil, err
			}
			if num == nil {
				continue
			}
			entry.hasValue[i] = true
			entry.sums[i].Add(entry.sums[i], num)
		}
	}

	out := vprocore.ProjectMetadataTable{
		Columns: append([]vprocore.ProjectMetadataColumn{}, veg.Columns...),
		Rows:    make([]vprocore.ProjectMetadataRow, 0, len(order)+len(passthrough)),
	}
	for _, k := range order {
		entry := groups[k]
		for i, cIdx := range coverCols {
			if cIdx < 0 {
				continue
			}
			if !entry.hasValue[i] {
				entry.row.Cells[cIdx] = vprocore.ProjectMetadataCell{Storage: "null"}
				continue
			}
			sum := entry.sums[i]
			if sum.Cmp(max99) > 0 {
				sum = max99
			}
			f64, _ := sum.Float64()
			entry.row.Cells[cIdx] = vprocore.ProjectMetadataCell{Storage: "real", Real: &f64}
		}
		out.Rows = append(out.Rows, entry.row)
	}
	out.Rows = append(out.Rows, passthrough...)
	return out, plan.TableLabel, plan.Rows, nil
}

func populateSummaryHierarchyHeaders(
	ctx context.Context,
	tx *sql.Tx,
	hierName string,
	preview *SummaryVegetationPreview,
) error {
	if preview == nil || hierName == "" || strings.EqualFold(hierName, "None") {
		return nil
	}
	nodes, err := loadHierarchyNodesFromTx(ctx, tx, hierName)
	if err != nil {
		return err
	}
	byID := make(map[int64]hierarchyBreakNode, len(nodes))
	byCleanLower := make(map[string]hierarchyBreakNode, len(nodes))
	for _, n := range nodes {
		byID[n.id] = n
		clean, _ := cleanBreakNodeName(n.name)
		if clean != "" {
			if _, exists := byCleanLower[strings.ToLower(clean)]; !exists {
				byCleanLower[strings.ToLower(clean)] = n
			}
		}
	}
	for i := range preview.Units {
		cleanUnit, _ := cleanBreakNodeName(preview.Units[i].Code)
		node, ok := byCleanLower[strings.ToLower(cleanUnit)]
		if !ok || node.parent == nil {
			continue
		}
		parent, ok := byID[*node.parent]
		if !ok {
			continue
		}
		parentClean, _ := cleanBreakNodeName(parent.name)
		if parentClean != "" {
			preview.Units[i].HierarchyHeader = &parentClean
		}
	}
	preview.HierarchyHeaderEnabled = true
	return nil
}

func buildSummaryGoldstreamMetadata(preview SummaryVegetationPreview) *SummaryVegetationGoldstreamMetadata {
	if preview.Display != 5 {
		return nil
	}
	meta := &SummaryVegetationGoldstreamMetadata{
		Formula:         "(presence * 100) * sqrt(meanCover)",
		ShowClass:       preview.ShowClass,
		ClassThresholds: []float64{5, 25, 75, 150, 300, 500},
		ClassLabels:     []int{0, 1, 2, 3, 4, 5, 6},
		Rows:            make([]SummaryVegetationGoldstreamRow, 0, len(preview.Rows)),
	}
	goldstreamClass := func(score float64) int {
		class := 0
		for _, limit := range meta.ClassThresholds {
			if score <= limit {
				break
			}
			class++
		}
		return class
	}
	for _, row := range preview.Rows {
		layerText := ""
		if row.Layer.Text != nil {
			layerText = *row.Layer.Text
		}
		sppText := ""
		if row.Species.Text != nil {
			sppText = *row.Species.Text
		}
		gRow := SummaryVegetationGoldstreamRow{
			Layer:   layerText,
			Species: sppText,
			Cells:   make([]SummaryVegetationGoldstreamCell, 0, len(preview.Units)),
		}
		type unitAgg struct {
			plots map[string]struct{}
			sum   float64
			has   bool
		}
		byUnit := map[string]*unitAgg{}
		for _, w := range row.Witnesses {
			agg := byUnit[w.Unit]
			if agg == nil {
				agg = &unitAgg{plots: map[string]struct{}{}}
				byUnit[w.Unit] = agg
			}
			agg.plots[w.MembershipID] = struct{}{}
			if num, nErr := vprocore.VegetationReportNumber(w.Cover); nErr == nil && num != nil {
				f, _ := num.Float64()
				agg.sum += f
				agg.has = true
			}
		}
		for i, u := range preview.Units {
			if i >= len(row.Covers) {
				break
			}
			cell := row.Covers[i]
			entry := SummaryVegetationGoldstreamCell{Unit: u.Code}
			if agg := byUnit[u.Code]; agg != nil && agg.has && u.NumPlots > 0 {
				meanCover := agg.sum / float64(u.NumPlots)
				presence := float64(len(agg.plots)) / float64(u.NumPlots)
				if meanCover >= 0 {
					score := (presence * 100) * math.Sqrt(meanCover)
					if !math.IsNaN(score) && !math.IsInf(score, 0) {
						cls := goldstreamClass(score)
						entry.Score = &score
						entry.Class = &cls
					}
				}
			}
			if entry.Score == nil || entry.Class == nil {
				switch {
				case cell.Storage == "real" && cell.Real != nil:
					score := *cell.Real
					cls := goldstreamClass(score)
					entry.Score = &score
					entry.Class = &cls
				case cell.Storage == "integer" && cell.Integer != nil:
					if cls, err := strconv.Atoi(*cell.Integer); err == nil {
						entry.Class = &cls
					}
				case cell.Storage == "text" && cell.Text != nil:
					text := strings.TrimSpace(*cell.Text)
					if preview.ShowClass == 20 {
						if score, err := strconv.ParseFloat(text, 64); err == nil && !math.IsNaN(score) && !math.IsInf(score, 0) {
							cls := goldstreamClass(score)
							entry.Score = &score
							entry.Class = &cls
						}
					} else if cls, err := strconv.Atoi(text); err == nil {
						entry.Class = &cls
					}
				}
			}
			gRow.Cells = append(gRow.Cells, entry)
		}
		meta.Rows = append(meta.Rows, gRow)
	}
	return meta
}

func filterSummaryRowsByValueLimit(rows []SummaryVegetationRow, limit float64) []SummaryVegetationRow {
	if limit <= 0 || math.IsNaN(limit) || math.IsInf(limit, 0) {
		return rows
	}
	filtered := make([]SummaryVegetationRow, 0, len(rows))
	for _, row := range rows {
		var orderVal *float64
		switch {
		case row.Order.Storage == "real" && row.Order.Real != nil:
			v := *row.Order.Real
			orderVal = &v
		case row.Order.Storage == "text" && row.Order.Text != nil:
			if v, err := strconv.ParseFloat(strings.TrimSpace(*row.Order.Text), 64); err == nil {
				orderVal = &v
			}
		case row.Order.Storage == "integer" && row.Order.Integer != nil:
			if v, err := strconv.ParseFloat(strings.TrimSpace(*row.Order.Integer), 64); err == nil {
				orderVal = &v
			}
		}
		if orderVal != nil && *orderVal > limit {
			filtered = append(filtered, row)
		}
	}
	return filtered
}

// PreviewWithPreferences executes Summary Vegetation preview reading all saved presentation,
// quality, lumping, hierarchy header, and unit-scope preferences so preview stays synchronized with workbook.
func (s *SummaryVegetationService) PreviewWithPreferences(ctx context.Context, contextID string) (SummaryVegetationPreview, error) {
	return s.PreviewConfigured(ctx, contextID, `{"useSavedPreferences":true}`)
}

// PreviewConfigured executes Summary Vegetation preview with explicit or saved unit scopes,
// hierarchy breakpoints/headers, SVSubSppAsSpp/lump tables, quality filtering, and Goldstream metadata.
func (s *SummaryVegetationService) PreviewConfigured(ctx context.Context, contextID, requestJSON string) (SummaryVegetationPreview, error) {
	fail := func(err error) (SummaryVegetationPreview, error) { return SummaryVegetationPreview{}, err }
	if s == nil || s.contexts == nil || ctx == nil {
		return fail(errors.New("Summary Vegetation service requires contexts and context"))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	var req SummaryVegetationConfiguredRequest
	if strings.TrimSpace(requestJSON) != "" {
		if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
			return fail(fmt.Errorf("Summary Vegetation configured preview JSON: %w", err))
		}
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (SummaryVegetationPreview, error) {
		var saved *SummaryVegetationAppliedPreferences
		if req.UseSavedPreferences {
			prefs, err := readSummarySavedPresentationState(ctx, plots.Projects.Preferences, plots.Projects.Sqlite.Selection.SU)
			if err != nil {
				return SummaryVegetationPreview{}, err
			}
			saved = &prefs
		}
		average := 1
		display := 6
		showClass := 0
		groupAndOrder := 11
		var refs *SummaryVegetationReferenceOptions
		mode := summaryVegetationGroupedOrdinary
		var valueLimit float64
		if saved != nil {
			average = saved.Average
			display = saved.Display
			showClass = saved.ShowClass
			groupAndOrder = summaryGroupByToGroupAndOrder(saved.GroupBy)
			valueLimit = saved.ValueLimit
			if saved.Constancy {
				mode = summaryVegetationGroupedConstancy
				groupAndOrder, display, showClass = 13, 1, 0
				refs = &SummaryVegetationReferenceOptions{}
			} else if saved.ShowCommon || saved.ShowGuide {
				refs = &SummaryVegetationReferenceOptions{
					ShowCommon:    saved.ShowCommon || saved.ShowGuide,
					UseGuideNames: saved.ShowGuide,
				}
				if groupAndOrder != 11 && groupAndOrder != 12 {
					if display == 6 {
						mode = summaryVegetationGroupedUnanimousCommon
					} else {
						refs.ShowCommon = false
						refs.UseGuideNames = false
					}
				}
			}
			if (display == 4 || display == 5) && showClass == 0 {
				showClass = 1
			}
		}
		if req.Average != nil {
			average = *req.Average
		}
		if req.Display != nil {
			display = *req.Display
		}
		if req.ShowClass != nil {
			showClass = *req.ShowClass
		}
		if req.GroupAndOrder != nil {
			groupAndOrder = *req.GroupAndOrder
		}
		if req.References != nil {
			refs = req.References
		}
		if req.Constancy != nil && *req.Constancy {
			mode = summaryVegetationGroupedConstancy
		}
		if req.UnanimousCommon != nil && *req.UnanimousCommon {
			mode = summaryVegetationGroupedUnanimousCommon
		}
		if req.ValueLimit != nil {
			valueLimit = *req.ValueLimit
		}
		if req.ShowClass == nil && display != 4 && display != 5 {
			showClass = 0
		}
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, s.snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SummaryVegetationPreview, error) {
			snap, err := s.readSnapshotConfigured(ctx, contextID, plots, owner, tx,
				average, display, showClass, groupAndOrder, refs, mode, req, saved, valueLimit)
			if err != nil {
				return SummaryVegetationPreview{}, err
			}
			return snap.Preview, nil
		})
	})
}

// SummaryVegetationWorkbookOptionsFromPreferences derives synchronized SummaryVegetationWorkbookOptions
// from saved ReportOptions/Current preferences so workbook exports match Summary Vegetation preview.
func SummaryVegetationWorkbookOptionsFromPreferences(ctx context.Context, contexts *vprocore.ContextService, contextID string) (SummaryVegetationWorkbookOptions, error) {
	if contexts == nil || ctx == nil {
		return SummaryVegetationWorkbookOptions{}, errors.New("Summary Vegetation workbook preference lookup requires context")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (SummaryVegetationWorkbookOptions, error) {
		saved, err := readSummarySavedPresentationState(ctx, plots.Projects.Preferences, plots.Projects.Sqlite.Selection.SU)
		if err != nil {
			return SummaryVegetationWorkbookOptions{}, err
		}
		group := summaryGroupByToGroupAndOrder(saved.GroupBy)
		showClass := saved.ShowClass
		if (saved.Display == 4 || saved.Display == 5) && showClass == 0 {
			showClass = 1
		}
		if saved.Display != 4 && saved.Display != 5 {
			showClass = 0
		}
		opts := SummaryVegetationWorkbookOptions{
			Title:      saved.Title,
			Average:    saved.Average,
			Display:    saved.Display,
			ShowClass:  showClass,
			IncludeEnv: saved.IncludeEnv,
		}
		if saved.CreateSummary {
			opts.Ancillary = &SummaryVegetationWorkbookAncillaryOptions{CreateSummary: true}
		}
		if group != 11 {
			opts.GroupAndOrder = &group
		}
		if saved.Constancy {
			g := 13
			opts.GroupAndOrder = &g
			opts.Display = 1
			opts.ShowClass = 0
			opts.Constancy = true
			opts.References = &SummaryVegetationReferenceOptions{}
		} else if saved.ShowCommon || saved.ShowGuide {
			if group == 11 || group == 12 {
				opts.References = &SummaryVegetationReferenceOptions{
					ShowCommon:    saved.ShowCommon || saved.ShowGuide,
					UseGuideNames: saved.ShowGuide,
				}
			} else if saved.Display == 6 {
				opts.UnanimousCommon = true
				opts.References = &SummaryVegetationReferenceOptions{
					ShowCommon:    saved.ShowCommon || saved.ShowGuide,
					UseGuideNames: saved.ShowGuide,
				}
			}
		}
		if saved.UnitScope != "" {
			opts.UnitScope = saved.UnitScope
		}
		if saved.UnitField != "" {
			opts.UnitField = saved.UnitField
		}
		if saved.HierarchyHeader {
			hh := true
			opts.HierarchyHeader = &hh
		}
		if saved.CombineVariants {
			cv := true
			opts.CombineVariants = &cv
		}
		if saved.LumpTable != "" {
			opts.LumpTable = saved.LumpTable
		}
		return opts, nil
	})
}
