package vegreport

import (
	"context"
	"errors"
	"fmt"
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
	Formula         string                           `json:"formula"`
	ShowClass       int                              `json:"showClass"`
	ClassThresholds []float64                        `json:"classThresholds"`
	ClassLabels     []int                            `json:"classLabels"`
	Rows            []SummaryVegetationGoldstreamRow `json:"rows"`
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
		if rawLimit, ok := section["SVShowValOpt"]; ok && rawLimit != nil {
			switch v := rawLimit.(type) {
			case int:
				if v >= 0 {
					out.ValueLimit = float64(v)
				}
			case int64:
				if v >= 0 {
					out.ValueLimit = float64(v)
				}
			case float64:
				if v >= 0 {
					out.ValueLimit = v
				}
			}
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
					if selectionSU == "" || selectionSU == "None" {
						out.UnitScope = "none"
					} else if selectionSU == "USysSuTableDynamic" {
						out.UnitScope = "hierarchy"
					} else {
						out.UnitScope = "su"
					}
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
