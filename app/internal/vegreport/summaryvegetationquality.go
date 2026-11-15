package vegreport

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// SummaryVegetationQualityThresholds records resolved QC thresholds used when DataQualityFilterEnforce is enabled.
type SummaryVegetationQualityThresholds struct {
	SiteMinimum      string `json:"siteMinimum"`
	VegMinimum       string `json:"vegMinimum"`
	SoilMinimum      string `json:"soilMinimum"`
	BECMinimum       string `json:"becMinimum"`
	SiteIncludeNulls bool   `json:"siteIncludeNulls"`
	VegIncludeNulls  bool   `json:"vegIncludeNulls"`
	SoilIncludeNulls bool   `json:"soilIncludeNulls"`
	BECIncludeNulls  bool   `json:"becIncludeNulls"`
}

// SummaryVegetationQualityRemovedPlot records an SU membership excluded by DataQuality + BEC_Use QC filtering.
type SummaryVegetationQualityRemovedPlot struct {
	RowID           string   `json:"rowId"`
	PlotNumber      string   `json:"plotNumber"`
	SiteUnit        string   `json:"siteUnit"`
	SitePlotQuality *string  `json:"sitePlotQuality,omitempty"`
	VegPlotQuality  *string  `json:"vegPlotQuality,omitempty"`
	SoilPlotQuality *string  `json:"soilPlotQuality,omitempty"`
	BECUse          *string  `json:"becUse,omitempty"`
	RemovedBy       string   `json:"removedBy"`
	FailedCriteria  []string `json:"failedCriteria"`
}

// SummaryVegetationQualityFilterResult summarizes QC + BEC_Use plot filtering on a Summary Vegetation preview.
type SummaryVegetationQualityFilterResult struct {
	Enforced     bool                                   `json:"enforced"`
	TotalBefore  int                                    `json:"totalBefore"`
	Retained     int                                    `json:"retained"`
	RemovedCount int                                    `json:"removedCount"`
	Removed      []SummaryVegetationQualityRemovedPlot  `json:"removed"`
	Thresholds   SummaryVegetationQualityThresholds     `json:"thresholds"`
}

// filterSummaryVegetationQuality filters an SU table per okf/02_present_state/oracles/REPORT_QUALITY_FILTER.md
// when quality.Enforce is true. It checks Site/Veg/Soil PlotQuality against VLists.USysTableOfLists
// (ListName='DataQuality', treating unlisted labels like NULL while rejecting labels belonging only to
// other lists) and evaluates BEC_Use >= BECMinimum via deterministic case-insensitive UTF-8 lexical order.
func filterSummaryVegetationQuality(
	ctx context.Context,
	su, env, admin, lists vprocore.ProjectMetadataTable,
	quality summaryVegetationQualityPreferenceValues,
) (vprocore.ProjectMetadataTable, *SummaryVegetationQualityFilterResult, error) {
	fail := func(err error) (vprocore.ProjectMetadataTable, *SummaryVegetationQualityFilterResult, error) {
		return vprocore.ProjectMetadataTable{}, nil, err
	}
	if ctx == nil {
		return fail(errors.New("Summary Vegetation quality filter requires a context"))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	if !quality.Enforce {
		return su, nil, nil
	}

	sc, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return fail(err)
	}
	ec, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return fail(fmt.Errorf("Summary Vegetation quality Env schema: %w", err))
	}
	fields := [3]string{"SitePlotQuality", "VegPlotQuality", "SoilPlotQuality"}
	ac, err := vprocore.SiteUnitTransferColumns(admin, "Plot", fields[0], fields[1], fields[2], "BEC_Use")
	if err != nil {
		return fail(fmt.Errorf("Summary Vegetation quality Admin schema: %w", err))
	}
	lc, err := vprocore.SiteUnitTransferColumns(lists, "ListName", "Item", "ItemOrder")
	if err != nil {
		return fail(fmt.Errorf("Summary Vegetation quality USysTableOfLists schema: %w", err))
	}

	envIndex, err := vprocore.SiteUnitTransferIndex(env, ec["PlotNumber"])
	if err != nil {
		return fail(fmt.Errorf("Summary Vegetation quality Env index: %w", err))
	}
	adminIndex, err := vprocore.SiteUnitTransferIndex(admin, ac["Plot"])
	if err != nil {
		return fail(fmt.Errorf("Summary Vegetation quality Admin index: %w", err))
	}

	// Build full case-insensitive item index across USysTableOfLists to match Access's full left join.
	itemsByFold := map[string][]vprocore.ProjectMetadataRow{}
	for _, row := range lists.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		item, err := vprocore.VegetationReportIdentity(row.Cells[lc["Item"]])
		if err != nil {
			return fail(fmt.Errorf("USysTableOfLists row %s Item: %w", row.RowID, err))
		}
		if item != nil {
			key := strings.ToLower(*item)
			itemsByFold[key] = append(itemsByFold[key], row)
		}
	}

	// Resolve inclusive rank thresholds from ListName='DataQuality' (case-insensitive).
	minLabels := [3]string{quality.SiteMinimum, quality.VegMinimum, quality.SoilMinimum}
	includeNulls := [3]bool{quality.SiteIncludeNulls, quality.VegIncludeNulls, quality.SoilIncludeNulls}
	criteriaNames := [3]string{"Site", "Veg", "Soil"}
	var thresholds [3]*big.Rat
	for i, minLabel := range minLabels {
		if minLabel == "" || strings.ContainsRune(minLabel, 0) {
			return fail(fmt.Errorf("Summary Vegetation %s minimum quality threshold requires a non-empty DataQuality label", criteriaNames[i]))
		}
		for _, row := range itemsByFold[strings.ToLower(minLabel)] {
			domain, err := vprocore.VegetationReportIdentity(row.Cells[lc["ListName"]])
			if err != nil {
				return fail(err)
			}
			if domain == nil || !strings.EqualFold(*domain, "DataQuality") {
				continue
			}
			value, err := vprocore.VegetationReportNumber(row.Cells[lc["ItemOrder"]])
			if err != nil {
				return fail(fmt.Errorf("DataQuality threshold %q row %s ItemOrder: %w", minLabel, row.RowID, err))
			}
			if value == nil {
				return fail(fmt.Errorf("DataQuality threshold %q row %s has NULL ItemOrder", minLabel, row.RowID))
			}
			if thresholds[i] != nil && thresholds[i].Cmp(value) != 0 {
				return fail(fmt.Errorf("DataQuality threshold %q has conflicting ItemOrder definitions", minLabel))
			}
			thresholds[i] = value
		}
		if thresholds[i] == nil {
			return fail(fmt.Errorf("Summary Vegetation %s threshold %q has no DataQuality definition in USysTableOfLists", criteriaNames[i], minLabel))
		}
	}

	if strings.ContainsRune(quality.BECMinimum, 0) {
		return fail(errors.New("Summary Vegetation BEC minimum threshold must not contain NUL"))
	}
	becThresholdFold := strings.ToLower(quality.BECMinimum)

	filtered := vprocore.ProjectMetadataTable{
		Columns: append([]vprocore.ProjectMetadataColumn{}, su.Columns...),
		Rows:    make([]vprocore.ProjectMetadataRow, 0, len(su.Rows)),
	}
	summary := &SummaryVegetationQualityFilterResult{
		Enforced:    true,
		TotalBefore: len(su.Rows),
		Removed:     []SummaryVegetationQualityRemovedPlot{},
		Thresholds: SummaryVegetationQualityThresholds{
			SiteMinimum:      quality.SiteMinimum,
			VegMinimum:       quality.VegMinimum,
			SoilMinimum:      quality.SoilMinimum,
			BECMinimum:       quality.BECMinimum,
			SiteIncludeNulls: quality.SiteIncludeNulls,
			VegIncludeNulls:  quality.VegIncludeNulls,
			SoilIncludeNulls: quality.SoilIncludeNulls,
			BECIncludeNulls:  quality.BECIncludeNulls,
		},
	}

	cloneCellPtr := func(c vprocore.ProjectMetadataCell) *string {
		if c.Storage == "null" || c.Text == nil {
			return nil
		}
		v := *c.Text
		return &v
	}

	for _, row := range su.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		plotCell := row.Cells[sc["PlotNumber"]]
		unitCell := row.Cells[sc["SiteUnit"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return fail(err)
		}
		unitStr, err := vprocore.VegetationReportIdentity(unitCell)
		if err != nil {
			return fail(err)
		}
		plotText := ""
		if plotStr != nil {
			plotText = *plotStr
		}
		unitText := ""
		if unitStr != nil {
			unitText = *unitStr
		}

		// Require complete Env -> Admin plot link; missing pair records "Project" removal per oracle.
		var envRows, adminRows []vprocore.ProjectMetadataRow
		if plotStr != nil && plotText != "" {
			envRows = envIndex[*plotStr]
			adminRows = adminIndex[*plotStr]
		}
		if len(envRows) > 1 || len(adminRows) > 1 {
			return fail(fmt.Errorf("Summary Vegetation QC plot %q has ambiguous Env/Admin rows", plotText))
		}
		if len(envRows) == 0 || len(adminRows) == 0 {
			summary.Removed = append(summary.Removed, SummaryVegetationQualityRemovedPlot{
				RowID:          row.RowID,
				PlotNumber:     plotText,
				SiteUnit:       unitText,
				RemovedBy:      "Project",
				FailedCriteria: []string{"Project"},
			})
			continue
		}

		adm := adminRows[0]
		var failed []string
		for i, fieldName := range fields {
			cell := adm.Cells[ac[fieldName]]
			label, err := vprocore.VegetationReportIdentity(cell)
			if err != nil {
				return fail(fmt.Errorf("Admin row %s %s: %w", adm.RowID, fieldName, err))
			}
			passed := false
			if label == nil {
				passed = includeNulls[i]
			} else {
				refs := itemsByFold[strings.ToLower(*label)]
				if len(refs) == 0 {
					// Absent from USysTableOfLists entirely -> follows the NULL branch in Access left join.
					passed = includeNulls[i]
				} else {
					for _, ref := range refs {
						domain, err := vprocore.VegetationReportIdentity(ref.Cells[lc["ListName"]])
						if err != nil {
							return fail(err)
						}
						// Belongs exclusively to another list -> excluded by ListName='DataQuality' OR ListName IS NULL.
						if domain != nil && !strings.EqualFold(*domain, "DataQuality") {
							continue
						}
						order, err := vprocore.VegetationReportNumber(ref.Cells[lc["ItemOrder"]])
						if err != nil {
							return fail(fmt.Errorf("USysTableOfLists row %s ItemOrder: %w", ref.RowID, err))
						}
						if (order == nil && includeNulls[i]) || (order != nil && order.Cmp(thresholds[i]) >= 0) {
							passed = true
							break
						}
					}
				}
			}
			if !passed {
				failed = append(failed, criteriaNames[i])
			}
		}

		// BEC_Use check: case-insensitive UTF-8 lexical comparison (>=), preserving exact Access text direction.
		becCell := adm.Cells[ac["BEC_Use"]]
		becLabel, err := vprocore.VegetationReportIdentity(becCell)
		if err != nil {
			return fail(fmt.Errorf("Admin row %s BEC_Use: %w", adm.RowID, err))
		}
		becPassed := false
		if becLabel == nil {
			becPassed = quality.BECIncludeNulls
		} else {
			becPassed = strings.ToLower(*becLabel) >= becThresholdFold
		}
		if !becPassed {
			failed = append(failed, "BEC")
		}

		if len(failed) > 0 {
			removedBy := failed[0]
			if len(failed) > 1 {
				removedBy = "Mixed"
			}
			summary.Removed = append(summary.Removed, SummaryVegetationQualityRemovedPlot{
				RowID:           row.RowID,
				PlotNumber:      plotText,
				SiteUnit:        unitText,
				SitePlotQuality: cloneCellPtr(adm.Cells[ac["SitePlotQuality"]]),
				VegPlotQuality:  cloneCellPtr(adm.Cells[ac["VegPlotQuality"]]),
				SoilPlotQuality: cloneCellPtr(adm.Cells[ac["SoilPlotQuality"]]),
				BECUse:          cloneCellPtr(becCell),
				RemovedBy:       removedBy,
				FailedCriteria:  failed,
			})
			continue
		}

		clonedCells := make([]vprocore.ProjectMetadataCell, len(row.Cells))
		for i, c := range row.Cells {
			clonedCells[i] = vprocore.CloneSiteUnitCell(c)
		}
		filtered.Rows = append(filtered.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: clonedCells,
		})
	}

	summary.Retained = len(filtered.Rows)
	summary.RemovedCount = len(summary.Removed)
	if summary.Retained == 0 {
		return fail(errors.New("Summary Vegetation quality filter retained no plots"))
	}
	return filtered, summary, nil
}
