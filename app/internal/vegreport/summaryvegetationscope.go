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

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// SummaryVegetationConfiguredRequest parameterizes Summary Vegetation previews
// across unit scopes ("su", "hierarchy", "none", "field"), saved preferences,
// SVSubSppAsSpp variant rollup, project *_Lump tables, hierarchy group headers,
// and Goldstream metadata.
type SummaryVegetationConfiguredRequest struct {
	UseSavedPreferences       bool                               `json:"useSavedPreferences,omitempty"`
	UnitScope                 string                             `json:"unitScope,omitempty"`
	UnitField                 string                             `json:"unitField,omitempty"`
	HierarchyHeader           *bool                              `json:"hierarchyHeader,omitempty"`
	BreakpointPolicy          string                             `json:"breakpointPolicy,omitempty"`
	CombineVariants           *bool                              `json:"combineVariants,omitempty"`
	LumpTable                 *string                            `json:"lumpTable,omitempty"`
	Average                   *int                               `json:"average,omitempty"`
	Display                   *int                               `json:"display,omitempty"`
	ShowClass                 *int                               `json:"showClass,omitempty"`
	GroupAndOrder             *int                               `json:"groupAndOrder,omitempty"`
	References                *SummaryVegetationReferenceOptions `json:"references,omitempty"`
	Constancy                 *bool                              `json:"constancy,omitempty"`
	UnanimousCommon           *bool                              `json:"unanimousCommon,omitempty"`
	ValueLimit                *float64                           `json:"valueLimit,omitempty"`
	IncludeGoldstreamMetadata bool                               `json:"includeGoldstreamMetadata,omitempty"`
}

// SummaryVegetationGoldstreamCell records parsed Goldstream score and class values
// for a single species-group x site-unit cell when Display=5 is evaluated.
type SummaryVegetationGoldstreamCell struct {
	Unit  string   `json:"unit"`
	Score *float64 `json:"score,omitempty"`
	Class *int     `json:"class,omitempty"`
}

// SummaryVegetationGoldstreamRow captures Goldstream score/class metadata per species row.
type SummaryVegetationGoldstreamRow struct {
	Layer   string                            `json:"layer,omitempty"`
	Species string                            `json:"species"`
	Cells   []SummaryVegetationGoldstreamCell `json:"cells"`
}

// SummaryVegetationGoldstreamMetadata exposes the Goldstream scoring formula,
// class boundaries, and per-cell score/class breakdown alongside formatted cells.
type SummaryVegetationGoldstreamMetadata struct {
	Formula          string                           `json:"formula"`
	ShowClass        int                              `json:"showClass"`
	ClassThresholds  []float64                        `json:"classThresholds"`
	ClassLabels      []int                            `json:"classLabels"`
	Rows             []SummaryVegetationGoldstreamRow `json:"rows"`
}

// SummaryVegetationAppliedPreferences captures presentation preferences synced across preview and workbook.
type SummaryVegetationAppliedPreferences struct {
	Title           string  `json:"title"`
	ShowCommon      bool    `json:"showCommon"`
	ShowGuide       bool    `json:"showGuide"`
	HierarchyHeader bool    `json:"hierarchyHeader"`
	IncludeEnv      bool    `json:"includeEnv"`
	CreateSummary   bool    `json:"createSummary"`
	CombineVariants bool    `json:"combineVariants"`
	Constancy       bool    `json:"constancy"`
	GroupBy         int     `json:"groupBy"`
	Average         int     `json:"average"`
	Display         int     `json:"display"`
	ShowClass       int     `json:"showClass"`
	ValueLimit      float64 `json:"valueLimit"`
	LumpTable       string  `json:"lumpTable"`
	UnitScope       string  `json:"unitScope"`
	UnitField       string  `json:"unitField,omitempty"`
}

func summaryGroupByToGroupAndOrder(groupBy int) int {
	switch groupBy {
	case 1:
		return 11
	case 2:
		return 12
	case 3:
		return 13
	case 4:
		return 14
	default:
		return 11
	}
}

func readSummaryConfigBoolOptional(section map[string]any, key string, fallback bool) (bool, error) {
	raw, exists := section[key]
	if !exists || raw == nil {
		return fallback, nil
	}
	return longVegetationConfigBool(vprocore.ConfigValues{"ReportOptions": section}, key)
}

func readSummarySavedPresentationState(
	ctx context.Context,
	store *vprocore.DesktopConfig,
	selectionSU string,
) (SummaryVegetationAppliedPreferences, error) {
	if store == nil {
		return SummaryVegetationAppliedPreferences{}, errors.New("Summary Vegetation preferences store is unavailable")
	}
	corePrefs, coreErr := ReadSummaryVegetationPreferences(store, ctx)
	presPrefs, presErr := ReadSummaryVegetationPresentationPreferences(store, ctx)

	if err := sqlutil.AcquireMutexLease(ctx, &store.Mu); err != nil {
		return SummaryVegetationAppliedPreferences{}, err
	}
	values, readErr := store.ReadLocked()
	store.Mu.Unlock()
	if readErr != nil {
		return SummaryVegetationAppliedPreferences{}, readErr
	}

	out := SummaryVegetationAppliedPreferences{
		Average:   1,
		Display:   6,
		GroupBy:   1,
		UnitScope: "su",
	}
	switch selectionSU {
	case "None":
		out.UnitScope = "none"
	case "USysSuTableDynamic":
		out.UnitScope = "hierarchy"
	}

	if coreErr == nil {
		out.Average = corePrefs.Average
		out.Display = corePrefs.Display
		out.ShowClass = corePrefs.ShowClass
		out.GroupBy = corePrefs.GroupBy
		out.ValueLimit = corePrefs.ValueLimit
	}
	if presErr == nil {
		out.Title = presPrefs.Title
		out.ShowCommon = presPrefs.ShowCommon
		out.ShowGuide = presPrefs.ShowGuide
		out.HierarchyHeader = presPrefs.HierarchyHeader
		out.IncludeEnv = presPrefs.IncludeEnv
		out.CreateSummary = presPrefs.CreateSummary
		out.CombineVariants = presPrefs.CombineVariants
		out.Constancy = presPrefs.Constancy
		out.GroupBy = presPrefs.GroupBy
		out.Display = presPrefs.Display
		out.ValueLimit = presPrefs.ValueLimit
	} else if section, err := vprocore.ConfigSection(values, "ReportOptions"); err == nil {
		// Read individual presentation flags leniently when legacy section is partial.
		if t, ok := section["SVReportTitle"].(string); ok {
			out.Title = t
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVShowEnglishName", false); err == nil {
			out.ShowCommon = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVShowGuideName", false); err == nil {
			out.ShowGuide = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVShowHierarchyHeader", false); err == nil {
			out.HierarchyHeader = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVIncludeEnvFields", false); err == nil {
			out.IncludeEnv = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVReportSummary", false); err == nil {
			out.CreateSummary = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVSubSppAsSpp", false); err == nil {
			out.CombineVariants = v
		}
		if v, err := readSummaryConfigBoolOptional(section, "SVConstancyFormat", false); err == nil {
			out.Constancy = v
		}
	}

	if section, err := vprocore.ConfigSection(values, "ReportOptions"); err == nil {
		if rawUnits, ok := section["SVReportUnits"]; ok && rawUnits != nil {
			if code, cErr := vprocore.ConfigInt(values, "ReportOptions", "SVReportUnits", 1, 7); cErr == nil {
				switch code {
				case 2, 5, 6, 7:
					out.UnitScope = "hierarchy"
				case 3:
					out.UnitScope = "field"
				case 4:
					out.UnitScope = "none"
				default:
					out.UnitScope = "su"
				}
			}
		}
		if rawField, ok := section["SVUnitField"].(string); ok && strings.TrimSpace(rawField) != "" {
			out.UnitField = strings.TrimSpace(rawField)
		}
	}
	if current, err := vprocore.ConfigSection(values, "Current"); err == nil {
		if rawLump, ok := current["CurrLump"].(string); ok {
			trimmed := strings.TrimSpace(rawLump)
			if trimmed != "" && !strings.EqualFold(trimmed, "None") && !strings.EqualFold(trimmed, "None_Lump") {
				out.LumpTable = trimmed
			}
		}
	}
	return out, nil
}

func resolveEffectiveSummaryScope(explicitScope, selectionSU string) (string, error) {
	scope := strings.ToLower(strings.TrimSpace(explicitScope))
	if scope == "" {
		switch selectionSU {
		case "None":
			return "none", nil
		case "USysSuTableDynamic":
			return "hierarchy", nil
		default:
			return "su", nil
		}
	}
	switch scope {
	case "su", "hierarchy", "none", "field":
		return scope, nil
	default:
		return "", fmt.Errorf("Summary Vegetation unitScope %q must be 'su', 'hierarchy', 'none', or 'field'", explicitScope)
	}
}

func buildWholeProjectSUTable(ctx context.Context, env vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	ec, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Vegetation whole-project Env schema: %w", err)
	}
	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "VARCHAR"},
			{Name: "SiteUnit", DeclaredType: "VARCHAR"},
		},
		Rows: make([]vprocore.ProjectMetadataRow, 0, len(env.Rows)),
	}
	seen := map[string]bool{}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		plotCell := row.Cells[ec["PlotNumber"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		if plotStr == nil || strings.TrimSpace(*plotStr) == "" || seen[*plotStr] {
			continue
		}
		seen[*plotStr] = true
		unitLabel := "All Plots"
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{
				vprocore.CloneSiteUnitCell(plotCell),
				{Storage: "text", Text: &unitLabel},
			},
		})
	}
	if len(out.Rows) == 0 {
		return vprocore.ProjectMetadataTable{}, errors.New("Summary Vegetation whole-project scope ('None') found no plots in Env")
	}
	return out, nil
}

func buildFieldDerivedSUTable(ctx context.Context, env vprocore.ProjectMetadataTable, unitField string) (vprocore.ProjectMetadataTable, error) {
	field := strings.TrimSpace(unitField)
	if field == "" || strings.ContainsRune(field, 0) {
		return vprocore.ProjectMetadataTable{}, errors.New("Summary Vegetation field-derived unit scope requires a non-empty Env column name")
	}
	ec, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber", field)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Vegetation field-derived Env schema: %w", err)
	}
	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "VARCHAR"},
			{Name: "SiteUnit", DeclaredType: "VARCHAR"},
		},
		Rows: make([]vprocore.ProjectMetadataRow, 0, len(env.Rows)),
	}
	seen := map[string]bool{}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		plotCell := row.Cells[ec["PlotNumber"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		if plotStr == nil || strings.TrimSpace(*plotStr) == "" || seen[*plotStr] {
			continue
		}
		seen[*plotStr] = true
		valStr, err := summaryMetadataCellText(row.Cells[ec[field]])
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		trimmed := strings.TrimSpace(valStr)
		if trimmed == "" {
			continue
		}
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{
				vprocore.CloneSiteUnitCell(plotCell),
				{Storage: "text", Text: &trimmed},
			},
		})
	}
	if len(out.Rows) == 0 {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Vegetation field-derived unit scope on Env.%s retained no assigned plots", field)
	}
	return out, nil
}

func summaryMetadataCellText(cell vprocore.ProjectMetadataCell) (string, error) {
	val, err := vprocore.MetadataCellValue(cell)
	if err != nil {
		return "", err
	}
	switch v := val.(type) {
	case nil:
		return "", nil
	case string:
		return v, nil
	case []byte:
		return string(v), nil
	case int64:
		return strconv.FormatInt(v, 10), nil
	case float64:
		return strconv.FormatFloat(v, 'g', -1, 64), nil
	default:
		return "", fmt.Errorf("Summary Vegetation field value cannot be formatted as unit label (%T)", v)
	}
}

func buildDynamicHierarchySourceSUTable(ctx context.Context, env vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	// Resolve SiteUnit from UserSiteUnit, BECSiteUnit, or SiteSeries when USysSuTableDynamic_SU is not materialized.
	ec, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	userIdx, becIdx, ssIdx := -1, -1, -1
	for i, col := range env.Columns {
		switch col.Name {
		case "UserSiteUnit":
			userIdx = i
		case "BECSiteUnit":
			becIdx = i
		case "SiteSeries":
			ssIdx = i
		}
	}
	if userIdx < 0 && becIdx < 0 && ssIdx < 0 {
		return vprocore.ProjectMetadataTable{}, errors.New("Summary Vegetation dynamic hierarchy breakpoints require an SU table or Env UserSiteUnit/BECSiteUnit/SiteSeries columns")
	}
	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "VARCHAR"},
			{Name: "SiteUnit", DeclaredType: "VARCHAR"},
		},
		Rows: make([]vprocore.ProjectMetadataRow, 0, len(env.Rows)),
	}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		plotCell := row.Cells[ec["PlotNumber"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		if plotStr == nil || strings.TrimSpace(*plotStr) == "" {
			continue
		}
		var unitText string
		if userIdx >= 0 {
			u, err := vprocore.VegetationReportIdentity(row.Cells[userIdx])
			if err != nil {
				return vprocore.ProjectMetadataTable{}, err
			}
			if u != nil && strings.TrimSpace(*u) != "" {
				unitText = strings.TrimSpace(*u)
			}
		}
		if unitText == "" && becIdx >= 0 {
			b, err := vprocore.VegetationReportIdentity(row.Cells[becIdx])
			if err != nil {
				return vprocore.ProjectMetadataTable{}, err
			}
			if b != nil && strings.TrimSpace(*b) != "" {
				unitText = strings.TrimSpace(*b)
			}
		}
		if unitText == "" && ssIdx >= 0 {
			s, err := vprocore.VegetationReportIdentity(row.Cells[ssIdx])
			if err != nil {
				return vprocore.ProjectMetadataTable{}, err
			}
			if s != nil && strings.TrimSpace(*s) != "" {
				unitText = strings.TrimSpace(*s)
			}
		}
		if unitText == "" {
			continue
		}
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{
				vprocore.CloneSiteUnitCell(plotCell),
				{Storage: "text", Text: &unitText},
			},
		})
	}
	if len(out.Rows) == 0 {
		return vprocore.ProjectMetadataTable{}, errors.New("Summary Vegetation dynamic hierarchy breakpoints found no site-unit assignments")
	}
	return out, nil
}

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
