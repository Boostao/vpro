package vegreport

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"strconv"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func calculateSummaryVegetationEnvironmentalPlotCount(ctx context.Context, siteUnit *string,
	groupPresent bool, nonNullPlotCount int64) (vprocore.ProjectMetadataCell, error) {
	if err := ctx.Err(); err != nil {
		return vprocore.ProjectMetadataCell{}, fmt.Errorf("SVnPlots environmental count: %w", err)
	}
	if siteUnit == nil {
		return vprocore.ProjectMetadataCell{}, errors.New("SVnPlots environmental count requires a non-NULL Site Unit argument (source error94)")
	}
	if !groupPresent {
		return vprocore.ProjectMetadataCell{}, errors.New("SVnPlots environmental count has no grouped source record (source error3021)")
	}
	if nonNullPlotCount < 0 {
		return vprocore.ProjectMetadataCell{}, errors.New("SVnPlots environmental count requires a nonnegative prepared Count(PlotNumber)")
	}
	if nonNullPlotCount > 32767 {
		return vprocore.ProjectMetadataCell{}, errors.New("SVnPlots environmental count exceeds the source Integer range (source overflow6)")
	}
	integer := strconv.FormatInt(nonNullPlotCount, 10)
	return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &integer}, nil
}

func prepareSummaryVegetationEnvironmentalPlotCount(ctx context.Context, siteUnit *string,
	su vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataCell, error) {
	fail := func(err error) (vprocore.ProjectMetadataCell, error) {
		return vprocore.ProjectMetadataCell{}, fmt.Errorf("SVnPlots literal SU source preparation: %w", err)
	}
	if ctx == nil {
		return fail(errors.New("requires a context"))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	if siteUnit == nil {
		return calculateSummaryVegetationEnvironmentalPlotCount(ctx, nil, false, 0)
	}
	if _, err := vprocore.VegetationReportIdentity(vprocore.ProjectMetadataCell{Storage: "text", Text: siteUnit}); err != nil {
		return fail(err)
	}
	columns, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return fail(err)
	}
	var count int64
	present := false
	for _, row := range su.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		unit, err := vprocore.VegetationReportIdentity(row.Cells[columns["SiteUnit"]])
		if err != nil {
			return fail(fmt.Errorf("row %s SiteUnit: %w", row.RowID, err))
		}
		plot, err := vprocore.VegetationReportIdentity(row.Cells[columns["PlotNumber"]])
		if err != nil {
			return fail(fmt.Errorf("row %s PlotNumber: %w", row.RowID, err))
		}
		if unit != nil && *unit == *siteUnit {
			present = true
			if plot != nil {
				count++
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	return calculateSummaryVegetationEnvironmentalPlotCount(ctx, siteUnit, present, count)
}

type SummaryVegetationEnvironmentalCountReview struct {
	ContextID   string                        `json:"contextId"`
	Project     string                        `json:"project"`
	ProjectPath string                        `json:"projectPath"`
	SU          string                        `json:"su"`
	SUPath      string                        `json:"suPath"`
	SourcePath  string                        `json:"sourcePath"`
	SourceTable string                        `json:"sourceTable"`
	SiteUnit    string                        `json:"siteUnit"`
	Source      string                        `json:"source"`
	Physical    vprocore.ProjectMetadataTable `json:"physical"`
	Value       vprocore.ProjectMetadataCell  `json:"value"`
}

type SummaryVegetationEnvironmentalCountService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
}

func prepareSummaryEnvironmentalQuickVeg(ctx context.Context, project, suName string,
	veg, su vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	fail := func(err error) (vprocore.ProjectMetadataTable, error) {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary environmental raw QuickVeg: %w", err)
	}
	if ctx == nil {
		return fail(errors.New("requires a context"))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	names := []string{"PlotNumber", "Species"}
	for layer := 1; layer <= 9; layer++ {
		names = append(names, "Cover"+strconv.Itoa(layer))
	}
	columns, err := vprocore.SiteUnitTransferColumns(veg, names...)
	if err != nil {
		return fail(err)
	}
	for _, row := range veg.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		for _, name := range []string{"PlotNumber", "Species"} {
			cell := row.Cells[columns[name]]
			limit := 8
			if name == "PlotNumber" {
				limit = 7
			}
			if err := reportcore.LifeformSummaryText(cell, limit); err != nil {
				return fail(fmt.Errorf("Veg row %s %s: %w", row.RowID, name, err))
			}
			if cell.Storage != "text" || cell.Text == nil || *cell.Text == "" {
				return fail(fmt.Errorf("Veg row %s %s requires original nonempty TEXT", row.RowID, name))
			}
		}
		for _, name := range names[2:] {
			number, err := vprocore.VegetationReportNumber(row.Cells[columns[name]])
			if err != nil {
				return fail(fmt.Errorf("Veg row %s %s: %w", row.RowID, name, err))
			}
			if number == nil {
				continue
			}
			single, err := reportcore.LifeformSummarySingle(number)
			if err != nil {
				return fail(fmt.Errorf("Veg row %s %s: %w", row.RowID, name, err))
			}
			if new(big.Rat).SetFloat64(single).Cmp(number) != 0 {
				return fail(fmt.Errorf("Veg row %s %s requires exactly assigned finite SINGLE", row.RowID, name))
			}
		}
	}
	prepared, err := reportcore.PrepareSiteUnitQuickVegetation(ctx, project, suName, 1, veg, su)
	if err != nil {
		return fail(err)
	}
	result := vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{
		{Name: "Plotnumber", DeclaredType: "TEXT"}, {Name: "Species", DeclaredType: "TEXT"}, {Name: "Cover", DeclaredType: "REAL"},
	}, Rows: make([]vprocore.ProjectMetadataRow, 0, len(prepared.Entries))}
	for i, entry := range prepared.Entries {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		plot, cover := entry.PlotNumber, entry.Cover
		result.Rows = append(result.Rows, vprocore.ProjectMetadataRow{RowID: strconv.Itoa(i + 1), Cells: []vprocore.ProjectMetadataCell{
			{Storage: "text", Text: &plot}, vprocore.CloneSiteUnitCell(entry.Species), {Storage: "real", Real: &cover},
		}})
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	return result, nil
}
