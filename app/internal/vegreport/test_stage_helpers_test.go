package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// The caller owns the joined aggregates. This preserves the source Variant
// before the crosstab infers/coerces its column type.
func calculateSummaryVegetationCover(ctx context.Context, input summaryVegetationCellInput, average int) (vprocore.ProjectMetadataCell, error) {
	fail := func(err error) (vprocore.ProjectMetadataCell, error) { return vprocore.ProjectMetadataCell{}, err }
	if err := validateSummaryVegetationCellInput(ctx, input, average); err != nil {
		return fail(err)
	}
	if input.Count == 0 {
		return vprocore.ProjectMetadataCell{Storage: "null"}, nil
	}
	if reportcore.SiteUnitFixedNumber(float64(input.Count)/float64(input.NumPlots), 4, 1) == "0.0000" {
		return fail(errors.New("summary vegetation formatted cover count is empty; original numeric criteria comparison is unavailable"))
	}
	return formatSummaryVegetationCover(ctx, input, average)
}

func summaryVegetationEnvironmentalTextField(function string) (string, bool) {
	if function == "SVSmr" || function == "SVBioGeoClimaticUnit" || function == "SVAspect" {
		return "", false
	}
	return summaryVegetationEnvironmentalCategoryField(function)
}

func vegetationLifeformInsertionLayer(cell vprocore.ProjectMetadataCell) (vprocore.ProjectMetadataCell, error) {
	return vegetationLifeformInsertionLayerWithInteger(cell, vprocore.VegetationLifeformInteger)
}

func normalizeSummaryVegetationShowClass(display, showClass int) int {
	if display == 4 || display == 5 {
		if showClass == 0 {
			return 1
		}
		return showClass
	}
	return 0
}

func loadLongVegetationOptions(plots *vprocore.PlotService) (longVegetationOptions, error) {
	values, err := plots.Projects.Preferences.Snapshot()
	if err != nil {
		return longVegetationOptions{}, err
	}
	return decodeLongVegetationOptions(values)
}

func ReadLifeformWorkbookInput(c *vprocore.ContextService, ctx context.Context, contextID string, hooks vprocore.PublicationReadSnapshotHooks) (lifeformWorkbookInput, error) {
	if ctx == nil {
		return lifeformWorkbookInput{}, errors.New("Lifeform workbook requires a context")
	}
	if err := ctx.Err(); err != nil {
		return lifeformWorkbookInput{}, err
	}
	if c == nil || c.Projects == nil || c.Projects.Sqlite == nil || c.Plots == nil {
		return lifeformWorkbookInput{}, errors.New("Lifeform workbook context service is unavailable")
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return lifeformWorkbookInput{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, c, contextID, func(plots *vprocore.PlotService) (lifeformWorkbookInput, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (lifeformWorkbookInput, error) {
			return readLifeformWorkbookSource(ctx, owner, tx, contextID)
		})
	})
}

func NewSummaryVegetationEnvironmentalCountService(contexts *vprocore.ContextService) (*SummaryVegetationEnvironmentalCountService, error) {
	return &SummaryVegetationEnvironmentalCountService{contexts: contexts}, nil
}

func (s *SummaryVegetationEnvironmentalCountService) GetEnvironmentalPlotCount(ctx context.Context, contextID string,
	siteUnit *string) (*SummaryVegetationEnvironmentalCountReview, error) {
	if ctx == nil {
		return nil, errors.New("Summary environmental plot count requires a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if s == nil || s.contexts == nil || s.contexts.Projects == nil || s.contexts.Projects.Sqlite == nil || s.contexts.Plots == nil {
		return nil, errors.New("Summary environmental plot count context service is unavailable")
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return nil, err
	}
	if siteUnit == nil {
		return nil, errors.New("Summary environmental plot count requires a non-NULL Site Unit argument (source error94)")
	}
	if _, err := vprocore.VegetationReportIdentity(vprocore.ProjectMetadataCell{Storage: "text", Text: siteUnit}); err != nil {
		return nil, fmt.Errorf("Summary environmental plot count Site Unit: %w", err)
	}
	unit := *siteUnit
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*SummaryVegetationEnvironmentalCountReview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, s.snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*SummaryVegetationEnvironmentalCountReview, error) {
			if owner.Selection.SU == "None" || owner.Selection.SU == "USysSuTableDynamic" {
				return nil, errors.New("Summary environmental plot count requires selected normal SU; hierarchy/dynamic-break scope unavailable")
			}
			name := owner.Selection.SU + "_SU"
			var count int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM su.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`, name).Scan(&count); err != nil {
				return nil, fmt.Errorf("Summary environmental plot count physical SU lookup: %w", err)
			}
			if count != 1 {
				return nil, fmt.Errorf("Summary environmental plot count requires original physical su.%s table", name)
			}
			if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, "su", name, "Summary environmental plot count"); err != nil {
				return nil, err
			}
			physical, err := vprocore.ReadSQLiteStorageRows(ctx, tx, "su", name, "", nil, "")
			if err != nil {
				return nil, fmt.Errorf("Summary environmental plot count physical SU read: %w", err)
			}
			value, err := prepareSummaryVegetationEnvironmentalPlotCount(ctx, &unit, physical)
			if err != nil {
				return nil, err
			}
			return &SummaryVegetationEnvironmentalCountReview{
				ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
				SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, SourcePath: owner.Attachments["su"],
				SourceTable: name, SiteUnit: unit,
				Source:   "owned imported SQLite SU; literal SiteUnit count of nonNULL PlotNumber; no DISTINCT/Env join or Access collation claim",
				Physical: physical, Value: value,
			}, nil
		})
	})
}

func prepareLongVegetationProjectWorkbook(ctx context.Context, source vegetationLayerReport,
	scope LongVegetationReportScope, settings LongVegetationSettings, layout vegetationWorkbookLayout) (vegetationProjectWorkbook, error) {
	return prepareLongVegetationProjectWorkbookWithSummary(ctx, source, scope, settings, layout, nil)
}

// This private inspection preserves typed values, not Excel automation coercion.
func prepareSummaryEnvironmentalWorkbook(ctx context.Context, input summaryEnvironmentalWorkbookInput) (summaryEnvironmentalWorkbook, error) {
	if ctx == nil {
		return summaryEnvironmentalWorkbook{}, errors.New("Summary environmental workbook requires a context")
	}
	plan, err := prepareSummaryEnvironmentalHeader(ctx, input.FirstRow, input.English, input.FieldList, input.Units, input.Rows)
	if err != nil {
		return summaryEnvironmentalWorkbook{}, err
	}
	data, err := renderSummaryWorkbook(ctx, input, summaryWorkbookLayout{
		Sheet: "Summary Environment", Title: "Summary environmental inspection",
		LastRow: max(input.FirstRow-1, plan.LastDataRow), LastColumn: plan.LastValueColumn,
		HeaderRows: []int{input.FirstRow - 1}, Cells: plan.Cells,
	})
	if err != nil {
		return summaryEnvironmentalWorkbook{}, err
	}
	return summaryEnvironmentalWorkbook{Bytes: data, Header: plan}, nil
}

func renderSummaryWorkbook[T any](ctx context.Context, input T, layout summaryWorkbookLayout) (result []byte, resultErr error) {
	return renderSummaryWorkbookWithSheets(ctx, input, layout, nil)
}

func readSummaryVegetationAncillaryTables(ctx context.Context, owner *vprocore.SqliteContext,
	tx *sql.Tx) (summaryVegetationAncillaryTables, error) {
	return readSummaryVegetationAncillaryTablesWithEnv(ctx, owner, tx, nil)
}

func PreviewLongVegetationLayers(s *vprocore.ContextService, ctx context.Context, contextID string) (vegetationLayerReport, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (vegetationLayerReport, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (vegetationLayerReport, error) {
			values, err := plots.Projects.Preferences.Snapshot()
			if err != nil {
				return vegetationLayerReport{}, err
			}
			options, err := DecodeOwnedLongVegetationOptions(s, ctx, plots, tx, values)
			if err != nil {
				return vegetationLayerReport{}, err
			}
			if err := CheckLongVegetationGrouping(s, options); err != nil {
				return vegetationLayerReport{}, err
			}
			source, err := readLongVegetationReportSource(ctx, owner, tx, options)
			return source.Report, err
		})
	})
}

// EntryDat_Veg is a new typed read model, not a rewrite of the source table.
func prepareSummaryVegetationGroupedEntries(ctx context.Context, prepared VegetationReportPreparation,
	union vprocore.ProjectMetadataTable, grouping int) (vprocore.ProjectMetadataTable, error) {
	return prepareSummaryVegetationGroupedEntriesWithInteger(ctx, prepared, union, grouping, vprocore.VegetationLifeformInteger)
}

func prepareSummaryVegetationEnvironmentalLifeform(ctx context.Context, argument string, siteUnit *string,
	quick, master, su vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataCell, error) {
	return prepareSummaryEnvironmentalLifeformWithMasterInteger(ctx, argument, siteUnit, quick, master, su,
		vprocore.VegetationLifeformInteger)
}

func prepareSummaryVegetationGrouped(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average, grouping int) (summaryVegetationGroupedReport, error) {
	return prepareSummaryVegetationGroupedOptions(ctx, project, suName, veg, su, master, personal, layers, average, grouping, 6, 0)
}

func prepareSummaryVegetationGroupedOptions(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average, grouping, display, showClass int) (summaryVegetationGroupedReport, error) {
	return prepareSummaryVegetationGroupedReferences(ctx, project, suName, veg, su, master, personal, layers,
		average, grouping, display, showClass, nil)
}

func planSummaryVegetationGroupedStage(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, grouping int) (summaryVegetationGroupedReport, error) {
	return planSummaryVegetationGroupedStageOptions(ctx, raw, su, stage, master, personal, layers, average, grouping, 6, 0)
}

func planSummaryVegetationGroupedStageOptions(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, grouping, display, showClass int) (summaryVegetationGroupedReport, error) {
	return planSummaryVegetationGroupedStageReferences(ctx, raw, su, stage, master, personal, layers,
		average, grouping, display, showClass, nil)
}

func planSummaryVegetationGroupedStageReferences(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, grouping, display, showClass int,
	references *summaryVegetationReferencePlan) (summaryVegetationGroupedReport, error) {
	return planSummaryVegetationGroupedStageQuery(ctx, raw, su, stage, master, personal, layers,
		average, grouping, display, showClass, references, summaryVegetationGroupedOrdinary)
}

func planSummaryVegetationUnanimousCommonStage(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, grouping int,
	references *summaryVegetationReferencePlan) (summaryVegetationGroupedReport, error) {
	return planSummaryVegetationGroupedStageQuery(ctx, raw, su, stage, master, personal, layers,
		average, grouping, 6, 0, references, summaryVegetationGroupedUnanimousCommon)
}

// This literal read model deliberately excludes Access regional collation and
// options/callbacks. Raw preparation omits NULL covers before the source joins.
func prepareSummaryVegetationLayer(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average int) (summaryVegetationLayerReport, error) {
	return prepareSummaryVegetationLayerDisplay(ctx, project, suName, veg, su, master, personal, layers, average, 6)
}

func prepareSummaryVegetationLayerDisplay(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average, display int) (summaryVegetationLayerReport, error) {
	return prepareSummaryVegetationLayerOptions(ctx, project, suName, veg, su, master, personal, layers, average, display, 0)
}

func prepareSummaryVegetationLayerOptions(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average, display, showClass int) (summaryVegetationLayerReport, error) {
	return prepareSummaryVegetationLayerReferences(ctx, project, suName, veg, su, master, personal, layers,
		average, display, showClass, nil)
}

// Stage is the physical EntryDat_Veg boundary. Its NULL covers establish pivot
// columns, unlike NULL raw covers omitted by ConvertProVeg2V2.
func planSummaryVegetationLayer(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average int) (summaryVegetationLayerReport, error) {
	return planSummaryVegetationLayerDisplay(ctx, raw, su, stage, master, personal, layers, average, 6)
}

func planSummaryVegetationLayerDisplay(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, display int) (summaryVegetationLayerReport, error) {
	return planSummaryVegetationLayerOptions(ctx, raw, su, stage, master, personal, layers, average, display, 0)
}

func planSummaryVegetationLayerOptions(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, display, showClass int) (summaryVegetationLayerReport, error) {
	return planSummaryVegetationStage(ctx, raw, su, stage, master, personal, layers, average, display, showClass,
		summaryVegetationStageProjection{joinField: "Layer1234567", joinLimit: 2, labelField: "Layer", labelLimit: 3})
}
