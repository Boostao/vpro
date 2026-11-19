package vegreport

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strconv"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/xuri/excelize/v2"
)

type summaryVegetationWorkbookInput struct {
	Title       string                             `json:"title"`
	Vegetation  SummaryVegetationPreview           `json:"vegetation"`
	Environment *summaryEnvironmentalWorkbookInput `json:"environment"`
}

type summaryVegetationWorkbook struct {
	Bytes              []byte
	Sheet              string
	FirstVegetationRow int
	Ancillary          *summaryVegetationAncillaryPlan
}

type summaryWorkbookMode struct {
	constancy       bool
	unanimousCommon bool
	grouped         bool
	common          bool
	groupLabel      string
	sheet           string
}

func prepareSummaryVegetationWorkbook(ctx context.Context, input summaryVegetationWorkbookInput) (summaryVegetationWorkbook, error) {
	return prepareSummaryVegetationWorkbookWithSheets(ctx, input, input, nil)
}

func prepareSummaryVegetationWorkbookWithSheets(ctx context.Context, input summaryVegetationWorkbookInput,
	provenance any, writeSheets func(*excelize.File) error) (summaryVegetationWorkbook, error) {
	if ctx == nil {
		return summaryVegetationWorkbook{}, errors.New("Summary workbook requires a context")
	}
	preview := input.Vegetation
	mode, err := validateSummaryWorkbookPreview(ctx, preview)
	if err != nil {
		return summaryVegetationWorkbook{}, err
	}
	cells, first, separator, headerRow, leading, err := buildSummaryWorkbookHeaderCells(ctx, input, mode)
	if err != nil {
		return summaryVegetationWorkbook{}, err
	}
	if len(preview.Rows) > 32768-first {
		return summaryVegetationWorkbook{}, errors.New("Summary workbook body exceeds the qualified source Integer row frame")
	}
	if err := appendSummaryWorkbookBodyCells(ctx, preview, mode, first, leading, &cells); err != nil {
		return summaryVegetationWorkbook{}, err
	}
	realOrderFromRow, realOrderColumn := 0, 0
	if mode.grouped && preview.Display == 6 {
		realOrderFromRow, realOrderColumn = first, leading
	}
	data, err := renderSummaryWorkbookWithSheets(ctx, provenance, summaryWorkbookLayout{
		Sheet:            mode.sheet,
		Title:            input.Title,
		LastRow:          first + len(preview.Rows) - 1,
		LastColumn:       leading + len(preview.Columns),
		SeparatorRow:     separator,
		ItalicFromRow:    first,
		RealOrderFromRow: realOrderFromRow,
		RealOrderColumn:  realOrderColumn,
		HeaderRows:       []int{1, headerRow},
		Cells:            cells,
	}, writeSheets)
	if err != nil {
		return summaryVegetationWorkbook{}, err
	}
	return summaryVegetationWorkbook{Bytes: data, Sheet: mode.sheet, FirstVegetationRow: first}, nil
}

func validateSummaryWorkbookPreview(ctx context.Context, preview SummaryVegetationPreview) (summaryWorkbookMode, error) {
	var mode summaryWorkbookMode
	mode.constancy = preview.Source == summaryVegetationConstancySource
	mode.unanimousCommon = preview.Source == summaryVegetationUnanimousCommonSource
	if err := validateSummaryVegetationDisplayOptions(ctx, preview.Average, preview.Display, preview.ShowClass); err != nil {
		return mode, err
	}
	mode.grouped = mode.unanimousCommon || preview.Source == "literal-normal-su-grouped" || preview.GroupAndOrder != 0 && preview.GroupAndOrder != 11
	mode.groupLabel = "Layer"
	if mode.grouped {
		var err error
		if mode.groupLabel, err = summaryVegetationWorkbookGroup(ctx, preview); err != nil {
			return mode, err
		}
	}
	expectedSource, expectedOrdering, err := resolveExpectedSummarySourceAndOrdering(preview, &mode)
	if err != nil {
		return mode, err
	}
	if !hasValidSummaryPreviewFrame(preview, mode.grouped, expectedSource, expectedOrdering) {
		return mode, errors.New("Summary workbook requires a complete supported SU preview with aligned units and nonempty vegetation")
	}
	sheet, err := reportcore.EnvironmentWorkbookSheetName(preview.Project, 0)
	if err != nil {
		return mode, err
	}
	if sheet != preview.Project {
		return mode, errors.New("Summary workbook project worksheet identity requires alteration; no truncation or replacement")
	}
	mode.sheet = sheet
	if err := validateSummaryPreviewUnits(ctx, preview); err != nil {
		return mode, err
	}
	return mode, nil
}

func resolveExpectedSummarySourceAndOrdering(preview SummaryVegetationPreview, mode *summaryWorkbookMode) (string, string, error) {
	source, ordering := "literal-normal-su-layer", "literal-null-first-layer-species"
	if mode.grouped {
		source, ordering = "literal-normal-su-grouped", "literal-null-first-group-species"
	}
	if reference := preview.References; reference != nil {
		source = "literal-normal-su-effective-references"
		mode.common = reference.ShowCommon
		if !isConsistentEffectiveReferenceReview(*reference, mode.common) {
			return "", "", errors.New("Summary workbook effective reference metadata is inconsistent; no repairs applied")
		}
		if mode.common {
			ordering = "literal-null-first-layer-species-common"
		}
	}
	if mode.constancy {
		source, ordering = summaryVegetationConstancySource, summaryVegetationConstancyOrdering
	}
	if mode.unanimousCommon {
		source, ordering = summaryVegetationUnanimousCommonSource, summaryVegetationUnanimousCommonOrdering
	}
	return source, ordering, nil
}

func isConsistentEffectiveReferenceReview(reference SummaryVegetationReferenceReview, common bool) bool {
	if reference.UseGuideNames && !common {
		return false
	}
	if reference.MasterRows < 0 || reference.PersonalRows < 0 || reference.DescriptionRows < 0 ||
		reference.RemovedMasterRows < 0 || reference.DerivedRows < 0 || reference.UnionRows < 0 {
		return false
	}
	if reference.RemovedMasterRows > reference.MasterRows || reference.DerivedRows > reference.DescriptionRows {
		return false
	}
	maxUnion := int64(reference.MasterRows-reference.RemovedMasterRows) + int64(reference.PersonalRows) + int64(reference.DerivedRows)
	return int64(reference.UnionRows) <= maxUnion
}

func hasValidSummaryPreviewFrame(preview SummaryVegetationPreview, grouped bool, expectedSource, expectedOrdering string) bool {
	if preview.ContextID == "" || preview.ProjectPath == "" || preview.SUPath == "" || preview.Project == "" || preview.SU == "" {
		return false
	}
	if preview.Source != expectedSource || preview.Ordering != expectedOrdering {
		return false
	}
	if !grouped && ((preview.GroupAndOrder != 0 && preview.GroupAndOrder != 11) || preview.GroupField != nil || preview.OrderField != nil) {
		return false
	}
	if len(preview.Units) == 0 || len(preview.Units) > 250 || len(preview.Rows) == 0 || len(preview.Memberships) == 0 {
		return false
	}
	return len(preview.Columns) == len(preview.Units)
}

func validateSummaryPreviewUnits(ctx context.Context, preview SummaryVegetationPreview) error {
	for i, unit := range preview.Units {
		if err := ctx.Err(); err != nil {
			return err
		}
		if unit.NumPlots < 1 || len(unit.MembershipIDs) == 0 || len(unit.RawVegRowIDs) == 0 ||
			preview.Columns[i] != unit.Code || i > 0 && preview.Units[i-1].Code >= unit.Code {
			return errors.New("Summary workbook requires positive physical counts and exact ordered SV1/pivot alignment")
		}
	}
	return nil
}

func appendSummaryHeaderCell(cells *[]summaryEnvironmentalHeaderCell, row, column int, cell vprocore.ProjectMetadataCell) {
	copied := vprocore.CloneSiteUnitCell(cell)
	*cells = append(*cells, summaryEnvironmentalHeaderCell{
		Row:    row,
		Column: column,
		Value:  SummaryVegetationEnvironmentalValue{Kind: "cell", Cell: &copied},
	})
}

func appendSummaryHeaderText(cells *[]summaryEnvironmentalHeaderCell, row, column int, value string) {
	appendSummaryHeaderCell(cells, row, column, vprocore.ProjectMetadataCell{Storage: "text", Text: &value})
}

func buildSummaryWorkbookHeaderCells(
	ctx context.Context,
	input summaryVegetationWorkbookInput,
	mode summaryWorkbookMode,
) ([]summaryEnvironmentalHeaderCell, int, int, int, int, error) {
	preview := input.Vegetation
	cells := []summaryEnvironmentalHeaderCell{}
	first, separator, headerRow := 6, 0, 5
	leading := 3
	labels := []string{mode.groupLabel, "Spp", "Order"}
	if mode.common {
		leading = 4
		labels = []string{"Layer", "Spp", "Common Name", "Order"}
		if mode.unanimousCommon {
			labels[0] = mode.groupLabel
		}
	}
	caption := "Vegetation Table"
	if mode.constancy {
		caption = "Vegetation Table - Constancy Format"
	}
	if environment := input.Environment; environment != nil {
		if environment.FirstRow != 5 || environment.English != mode.common || !reflect.DeepEqual(environment.Units, summaryEnvironmentalPreviewUnits(preview)) {
			return nil, 0, 0, 0, 0, errors.New("Summary workbook environmental header requires row5, the same common-name layout and complete SV1 frame")
		}
		header, err := prepareSummaryEnvironmentalHeader(ctx, 5, mode.common, environment.FieldList, environment.Units, environment.Rows)
		if err != nil {
			return nil, 0, 0, 0, 0, err
		}
		cells = append(cells, header.Cells...)
		first, separator, headerRow = header.NextRow-1, header.NextRow-2, 4
		appendSummaryHeaderText(&cells, separator, 1, "StartVeg")
		caption = "Site Unit Summary Table"
	} else {
		for i, unit := range preview.Units {
			count := strconv.Itoa(unit.NumPlots)
			appendSummaryHeaderCell(&cells, 4, i+leading+1, vprocore.ProjectMetadataCell{Storage: "integer", Integer: &count})
			appendSummaryHeaderText(&cells, 5, i+leading+1, unit.Code)
		}
		appendSummaryHeaderText(&cells, 4, leading, "n Plots")
		for i, label := range labels {
			appendSummaryHeaderText(&cells, 5, i+1, label)
		}
	}
	appendSummaryHeaderText(&cells, 1, 1, input.Title)
	appendSummaryHeaderText(&cells, 2, 1, caption)
	if preview.HierarchyHeaderEnabled {
		appendSummaryHeaderText(&cells, 3, leading, "Hierarchy")
		for i, unit := range preview.Units {
			if unit.HierarchyHeader != nil && *unit.HierarchyHeader != "" {
				appendSummaryHeaderText(&cells, 3, i+leading+1, *unit.HierarchyHeader)
			}
		}
	}
	return cells, first, separator, headerRow, leading, nil
}

func appendSummaryWorkbookBodyCells(
	ctx context.Context,
	preview SummaryVegetationPreview,
	mode summaryWorkbookMode,
	first, leading int,
	cells *[]summaryEnvironmentalHeaderCell,
) error {
	var priorNumber *int
	for i, row := range preview.Rows {
		if err := ctx.Err(); err != nil {
			return err
		}
		number, err := validateSummaryWorkbookRow(row, i, preview, mode)
		if err != nil {
			return err
		}
		if err := emitSummaryWorkbookRowCells(row, i, first, leading, preview.Display, mode, cells); err != nil {
			return err
		}
		if i > 0 && !isSummaryWorkbookRowOrdered(preview.Rows[i-1], row, priorNumber, number, mode) {
			return errors.New("Summary workbook body groups are duplicated or outside the source literal ordering")
		}
		priorNumber = number
	}
	return nil
}

func validateSummaryWorkbookRow(
	row SummaryVegetationRow,
	rowIdx int,
	preview SummaryVegetationPreview,
	mode summaryWorkbookMode,
) (*int, error) {
	if len(row.Covers) != len(preview.Columns) || len(row.Witnesses) == 0 || (row.CommonName != nil) != mode.common {
		return nil, errors.New("Summary workbook body requires distinct source-ordered groups and complete pivot values")
	}
	if mode.unanimousCommon && row.CommonName.Text != nil && *row.CommonName.Text == "" {
		return nil, errors.New("Summary unanimous common-name workbook requires source First empty text projected as NULL")
	}
	var number *int
	if mode.constancy {
		var err error
		number, err = summaryVegetationMasterLongInteger(row.Layer)
		if err != nil {
			return nil, fmt.Errorf("Summary Constancy workbook row%d: %w", rowIdx+1, err)
		}
		if row.RawSpecies == nil {
			return nil, errors.New("Summary Constancy workbook requires the raw species grouping identity for every row")
		}
		if err := reportcore.LifeformSummaryText(*row.RawSpecies, 8); err != nil {
			return nil, fmt.Errorf("Summary Constancy workbook raw species row%d: %w", rowIdx+1, err)
		}
	} else if row.RawSpecies != nil {
		return nil, errors.New("Summary ordinary workbook cannot consume Constancy raw-species identity")
	}
	if mode.grouped && !mode.constancy {
		if err := reportcore.LifeformSummaryText(row.Layer, preview.GroupField.Size); err != nil {
			return nil, fmt.Errorf("Summary workbook grouped row%d: %w", rowIdx+1, err)
		}
		if preview.GroupAndOrder == 14 && row.Layer.Storage != "null" {
			return nil, errors.New("Summary workbook None grouping requires the original NULL group")
		}
	}
	return number, nil
}

func emitSummaryWorkbookRowCells(
	row SummaryVegetationRow,
	rowIdx, first, leading, display int,
	mode summaryWorkbookMode,
	cells *[]summaryEnvironmentalHeaderCell,
) error {
	values := []vprocore.ProjectMetadataCell{row.Layer, row.Species}
	if mode.common {
		values = append(values, *row.CommonName)
	}
	values = append(values, row.Order)
	for column, cell := range append(values, row.Covers...) {
		if err := validateSummaryBodyCellStorage(cell, rowIdx, column, leading, display, mode); err != nil {
			return err
		}
		if _, err := vprocore.MetadataCellValue(cell); err != nil {
			return fmt.Errorf("Summary workbook body row%d: %w", rowIdx+1, err)
		}
		appendSummaryHeaderCell(cells, first+rowIdx, column+1, cell)
	}
	return nil
}

func validateSummaryBodyCellStorage(
	cell vprocore.ProjectMetadataCell,
	rowIdx, column, leading, display int,
	mode summaryWorkbookMode,
) error {
	if mode.constancy && column == 0 {
		if cell.Storage != "integer" && cell.Storage != "null" {
			return fmt.Errorf("Summary Constancy workbook row%d requires original LONG/NULL lifeform", rowIdx+1)
		}
		return nil
	}
	if mode.grouped && display == 6 && column == leading-1 {
		if cell.Storage != "real" {
			return fmt.Errorf("Summary workbook grouped row%d requires original DOUBLE Order", rowIdx+1)
		}
		return nil
	}
	if cell.Storage != "text" && cell.Storage != "null" {
		return fmt.Errorf("Summary workbook body row%d requires original text/NULL output, not scalar conversion", rowIdx+1)
	}
	return nil
}

func summaryCellTextLess(left, right vprocore.ProjectMetadataCell) bool {
	if left.Text == nil || right.Text == nil {
		return left.Text == nil && right.Text != nil
	}
	return *left.Text < *right.Text
}

func isSummaryWorkbookRowOrdered(
	prior, row SummaryVegetationRow,
	priorNumber, number *int,
	mode summaryWorkbookMode,
) bool {
	if mode.constancy {
		sameGroup := priorNumber == nil && number == nil ||
			priorNumber != nil && number != nil && *priorNumber == *number
		return priorNumber == nil && number != nil ||
			priorNumber != nil && number != nil && *priorNumber < *number ||
			sameGroup && (summaryCellTextLess(prior.Species, row.Species) ||
				reflect.DeepEqual(prior.Species, row.Species) && summaryCellTextLess(*prior.RawSpecies, *row.RawSpecies))
	}
	return summaryCellTextLess(prior.Layer, row.Layer) || reflect.DeepEqual(prior.Layer, row.Layer) &&
		(summaryCellTextLess(prior.Species, row.Species) || reflect.DeepEqual(prior.Species, row.Species) &&
			mode.common && !mode.unanimousCommon && summaryCellTextLess(*prior.CommonName, *row.CommonName))
}

func summaryVegetationWorkbookGroup(ctx context.Context, preview SummaryVegetationPreview) (string, error) {
	if err := validateSummaryVegetationGroupedOptions(ctx, preview.Average, preview.GroupAndOrder, preview.Display, preview.ShowClass); err != nil {
		return "", err
	}
	unanimousCommon := preview.Source == summaryVegetationUnanimousCommonSource
	if unanimousCommon && (preview.ShowClass != 0 || preview.References == nil ||
		!summaryVegetationUnanimousCommonAvailable(preview.GroupAndOrder, preview.Display, preview.References.ShowCommon)) {
		return "", errors.New("Summary unanimous common-name workbook requires Group13/14 Display6 and effective common/guide references")
	}
	if !unanimousCommon && preview.References != nil && !summaryVegetationReferenceGroupingAvailable(preview.GroupAndOrder,
		preview.References.ShowCommon || preview.References.UseGuideNames) {
		return "", errors.New("Summary grouped common/guide references require Strata12; First(common name) for13/14 is not qualified")
	}
	group := SummaryVegetationField{Name: "Layer", DAOType: 10, Size: 1}
	switch preview.GroupAndOrder {
	case 13:
		group = SummaryVegetationField{Name: "LifeForm", DAOType: 10, Size: 3}
	case 14:
		group = SummaryVegetationField{Name: "Group", DAOType: 9}
	}
	if preview.Source == summaryVegetationConstancySource {
		if preview.GroupAndOrder != 13 || preview.Display != 1 || preview.ShowClass != 0 ||
			preview.References == nil || preview.References.ShowCommon || preview.References.UseGuideNames {
			return "", errors.New("Summary Constancy workbook requires numeric Group13/Display1 and effective references without common/guide names")
		}
		group = SummaryVegetationField{Name: "Lifeform", DAOType: 4, Size: 4}
	}
	order := SummaryVegetationField{Name: "Order", DAOType: 10}
	if preview.Display == 6 {
		order.DAOType, order.Size = 7, 8
	}
	if preview.GroupField == nil || *preview.GroupField != group || preview.OrderField == nil || *preview.OrderField != order {
		return "", errors.New("Summary grouped workbook requires exact original group and Order metadata")
	}
	return group.Name, nil
}
