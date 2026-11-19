package vegreport

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/xuri/excelize/v2"
)

type vegetationWorkbookLayout struct {
	QuickReport        bool
	SpaceBetweenGroups bool
	ReportSummary      bool
	Summary            *vegetationWorkbookSummary
}

type vegetationWorkbookSkippedUnit struct {
	Unit   vprocore.ProjectMetadataCell
	Reason string
}

type vegetationWorkbook struct {
	Bytes        []byte
	Sheets       []reportcore.VegetationWorkbookSheetInternal
	SkippedUnits []vegetationWorkbookSkippedUnit
}

type longVegWorkbookStyles struct {
	heading       int
	percent       int
	cover         int
	lifeformStyle int
}

type longVegWorkbookWriter struct {
	ctx        context.Context
	book       *excelize.File
	preview    LongVegetationPreview
	layout     vegetationWorkbookLayout
	groupLabel string
	styles     longVegWorkbookStyles
	identities map[string]bool
}

func prepareLongVegetationWorkbook(ctx context.Context, preview LongVegetationPreview, layout vegetationWorkbookLayout) (result vegetationWorkbook, resultErr error) {
	if preview.SUPath == "" || preview.Report.SourceKind != "" || preview.Report.ProjectUnits != nil ||
		preview.Report.ExcludedProjectUnitIndexes != nil {
		return result, errors.New("Long Vegetation selected-list workbook requires its original SU path and cannot consume project provenance")
	}
	return renderLongVegetationWorkbook(ctx, preview, layout, nil)
}

func renderLongVegetationWorkbook(ctx context.Context, preview LongVegetationPreview, layout vegetationWorkbookLayout,
	project *vegetationProjectWorkbookEvidence) (result vegetationWorkbook, resultErr error) {
	groupLabel, projectSummary, err := validateLongVegWorkbookRequest(ctx, preview, layout, project)
	if err != nil {
		return result, err
	}
	book := excelize.NewFile()
	defer func() {
		resultErr = errors.Join(resultErr, book.Close())
		if resultErr != nil {
			result = vegetationWorkbook{}
		}
	}()
	if err := book.SetDocProps(&excelize.DocProperties{Title: preview.Report.Title, Creator: "VPRO",
		Created: "2000-01-01T00:00:00Z", Modified: "2000-01-01T00:00:00Z"}); err != nil {
		return result, err
	}
	styles, err := initLongVegWorkbookStyles(book, preview.Settings.Grouping)
	if err != nil {
		return result, err
	}
	if err := preflightLongVegWorkbookUnits(ctx, book, preview, layout, projectSummary); err != nil {
		return result, err
	}

	writer := &longVegWorkbookWriter{
		ctx:        ctx,
		book:       book,
		preview:    preview,
		layout:     layout,
		groupLabel: groupLabel,
		styles:     styles,
		identities: map[string]bool{},
	}
	for index := range preview.Report.Units {
		if err := writer.renderUnitSheet(index, &result); err != nil {
			return result, err
		}
	}
	if len(result.Sheets) == 0 {
		return result, errors.New("There isn't any data to form a Long Vegetation workbook")
	}
	if err := appendLongVegHiddenSourceSheet(ctx, book, preview, layout, project, result.Sheets); err != nil {
		return result, err
	}
	buffer, err := book.WriteToBuffer()
	if err != nil {
		return result, err
	}
	if err := ctx.Err(); err != nil {
		return result, err
	}
	result.Bytes = bytes.Clone(buffer.Bytes())
	return result, nil
}

func validateLongVegWorkbookRequest(
	ctx context.Context,
	preview LongVegetationPreview,
	layout vegetationWorkbookLayout,
	project *vegetationProjectWorkbookEvidence,
) (string, *vegetationProjectWorkbookSummary, error) {
	if ctx == nil {
		return "", nil, errors.New("Long Vegetation workbook requires a context")
	}
	if err := ctx.Err(); err != nil {
		return "", nil, err
	}
	var projectSummary *vegetationProjectWorkbookSummary
	if project != nil {
		projectSummary = project.Summary
	}
	if layout.ReportSummary != (layout.Summary != nil || projectSummary != nil) || layout.Summary != nil && projectSummary != nil {
		return "", nil, errors.New("Long Vegetation ReportSummary requires captured summary evidence; no omitted requested summary")
	}
	if !hasValidLongVegWorkbookIdentity(preview) {
		return "", nil, errors.New("Long Vegetation workbook requires complete owned report/settings identity")
	}
	if err := validateLongVegSelectedField(preview.Settings, preview.Report); err != nil {
		return "", nil, err
	}
	groupLabel, err := resolveLongVegGroupingLabel(preview.Settings.Grouping)
	if err != nil {
		return "", nil, err
	}
	for _, value := range []string{preview.Report.Title, preview.Report.Project, preview.Report.SU} {
		if err := reportcore.EnvironmentWorkbookText(value); err != nil {
			return "", nil, err
		}
	}
	return groupLabel, projectSummary, nil
}

func hasValidLongVegWorkbookIdentity(preview LongVegetationPreview) bool {
	settings, report := preview.Settings, preview.Report
	if preview.ContextID == "" || preview.ProjectPath == "" || report.Project == "" || report.SU == "" ||
		settings.Title != report.Title || len(report.Units) == 0 {
		return false
	}
	if settings.ShowEnglishName && settings.ShowSpeciesCode ||
		settings.SelectedField != "" && (settings.ShowEnglishName || settings.ShowSpeciesCode) ||
		settings.SelectedField == "" && report.SelectedFieldType != "" {
		return false
	}
	if settings.Average != "all-plots" && settings.Average != "observations" ||
		settings.Order != "species" && settings.Order != "presence" {
		return false
	}
	return !math.IsNaN(settings.PresenceGreaterThan) && !math.IsInf(settings.PresenceGreaterThan, 0) &&
		!math.IsNaN(settings.MeanCoverGreaterThan) && !math.IsInf(settings.MeanCoverGreaterThan, 0)
}

func validateLongVegSelectedField(settings LongVegetationSettings, report LongVegetationReport) error {
	if settings.SelectedField == "" {
		return nil
	}
	if err := reportcore.EnvironmentWorkbookText(settings.SelectedField); err != nil {
		return err
	}
	_, err := longVegetationSelectedScalarValue(report.SelectedFieldType, vprocore.ProjectMetadataCell{Storage: "null"})
	return err
}

func resolveLongVegGroupingLabel(grouping string) (string, error) {
	switch grouping {
	case "layer", "none":
		return "Layer", nil
	case "lifeform":
		return "Lifeform", nil
	case "strata":
		return "Strata", nil
	default:
		return "", errors.New("Long Vegetation workbook grouping is unavailable")
	}
}

func initLongVegWorkbookStyles(book *excelize.File, grouping string) (longVegWorkbookStyles, error) {
	var styles longVegWorkbookStyles
	var err error
	styles.heading, err = book.NewStyle(&excelize.Style{Font: &excelize.Font{Bold: true},
		Fill: excelize.Fill{Type: "pattern", Pattern: 1, Color: []string{"E5E7EB"}}})
	if err != nil {
		return styles, err
	}
	percentFormat, coverFormat := "0.0%", "0.0"
	styles.percent, err = book.NewStyle(&excelize.Style{CustomNumFmt: &percentFormat})
	if err != nil {
		return styles, err
	}
	styles.cover, err = book.NewStyle(&excelize.Style{CustomNumFmt: &coverFormat})
	if err != nil {
		return styles, err
	}
	if grouping == "lifeform" {
		styles.lifeformStyle, err = book.NewStyle(&excelize.Style{NumFmt: 1})
		if err != nil {
			return styles, err
		}
	}
	return styles, nil
}

func preflightLongVegWorkbookUnits(
	ctx context.Context,
	book *excelize.File,
	preview LongVegetationPreview,
	layout vegetationWorkbookLayout,
	projectSummary *vegetationProjectWorkbookSummary,
) error {
	identities := map[string]bool{}
	var sheets []reportcore.VegetationWorkbookSheetInternal
	firstInitialized := false
	for index, unit := range preview.Report.Units {
		if err := ctx.Err(); err != nil {
			return err
		}
		shortName, skip, err := inspectLongVegWorkbookUnit(unit, index, identities)
		if err != nil {
			return err
		}
		if skip {
			continue
		}
		name, err := resolveUniqueLongVegSheetName(shortName, index, layout.ReportSummary, sheets)
		if err != nil {
			return err
		}
		if !firstInitialized {
			firstInitialized = true
			if err := book.SetSheetName("Sheet1", name); err != nil {
				return err
			}
			if err := writeLongVegOptionalSummary(ctx, book, preview, layout.Summary, projectSummary); err != nil {
				return err
			}
		}
		sheets = append(sheets, reportcore.VegetationWorkbookSheetInternal{Unit: vprocore.CloneSiteUnitCell(unit.Code), Name: name})
	}
	return nil
}

func writeLongVegOptionalSummary(
	ctx context.Context,
	book *excelize.File,
	preview LongVegetationPreview,
	summary *vegetationWorkbookSummary,
	projectSummary *vegetationProjectWorkbookSummary,
) error {
	if summary != nil {
		return writeVegetationWorkbookSummary(ctx, book, preview, *summary)
	}
	if projectSummary != nil {
		return writeVegetationProjectWorkbookSummary(ctx, book, preview, *projectSummary)
	}
	return nil
}

func inspectLongVegWorkbookUnit(unit LongVegetationUnit, index int, identities map[string]bool) (string, bool, error) {
	code, err := vprocore.VegetationReportIdentity(unit.Code)
	if err != nil {
		return "", false, err
	}
	identity := reportcore.VegetationTextKey(unit.Code)
	if identities[identity] || unit.NumPlots < 0 {
		return "", false, errors.New("Long Vegetation workbook requires distinct unit identities and valid plot counts")
	}
	identities[identity] = true
	if unit.NumPlots == 0 {
		return "", true, nil
	}
	if unit.NumPlots > 16000 {
		return "", false, errors.New("Long Vegetation workbook unit exceeds 16,000 plots (Excel .xlsx column limit); split the selected data explicitly")
	}
	if len(unit.Rows) == 0 {
		return "", false, errors.New("Long Vegetation workbook lacks row/pivot evidence for a selected unit; empty-row output remains unavailable")
	}
	shortName := "Unassigned"
	if code != nil {
		shortName = *code
		if shortName == "" {
			shortName = fmt.Sprintf("NoName%d", index)
		}
	}
	return shortName, false, nil
}

func resolveUniqueLongVegSheetName(
	shortName string,
	index int,
	hasReportSummary bool,
	existing []reportcore.VegetationWorkbookSheetInternal,
) (string, error) {
	name, err := reportcore.EnvironmentWorkbookSheetName(shortName, index)
	if err != nil {
		return "", err
	}
	if hasReportSummary && strings.EqualFold(name, "ReportSummary") {
		return "", errors.New("Long Vegetation worksheet names collide; no suffix or overwrite")
	}
	for _, sheet := range existing {
		if strings.EqualFold(sheet.Name, name) {
			return "", errors.New("Long Vegetation worksheet names collide; no suffix or overwrite")
		}
	}
	return name, nil
}

func (w *longVegWorkbookWriter) renderUnitSheet(index int, result *vegetationWorkbook) error {
	unit := w.preview.Report.Units[index]
	if err := w.ctx.Err(); err != nil {
		return err
	}
	shortName, skip, err := inspectLongVegWorkbookUnit(unit, index, w.identities)
	if err != nil {
		return err
	}
	if skip {
		result.SkippedUnits = append(result.SkippedUnits, vegetationWorkbookSkippedUnit{
			vprocore.CloneSiteUnitCell(unit.Code), "source NumPlots < 1",
		})
		return nil
	}
	name, err := resolveUniqueLongVegSheetName(shortName, index, w.layout.ReportSummary, result.Sheets)
	if err != nil {
		return err
	}
	if len(result.Sheets) > 0 {
		if _, err := w.book.NewSheet(name); err != nil {
			return err
		}
	}
	result.Sheets = append(result.Sheets, reportcore.VegetationWorkbookSheetInternal{Unit: vprocore.CloneSiteUnitCell(unit.Code), Name: name})

	if err := w.writeUnitTitleBlock(name, shortName, unit); err != nil {
		return err
	}
	plotColumns, presenceCol, meanCol, firstPlotCol, lastCol, err := w.writeUnitColumnHeaders(name, unit)
	if err != nil {
		return err
	}
	if err := w.writeUnitRows(name, unit, plotColumns, presenceCol, meanCol, firstPlotCol); err != nil {
		return err
	}
	return w.configureSheetPanesAndPage(name, lastCol, firstPlotCol)
}

func (w *longVegWorkbookWriter) writeUnitTitleBlock(sheetName, shortName string, unit LongVegetationUnit) error {
	if unit.NameStatus == "conflicting" || unit.NameStatus == "unsupported_storage" {
		return errors.New("Long Vegetation workbook refuses unresolved original unit names")
	}
	unitTitle := shortName
	if unit.LongName != nil && *unit.LongName != "" {
		unitTitle += " - [" + *unit.LongName + "]"
	}
	lumpLine := " "
	if w.preview.Settings.LumpTable != "" {
		lumpLine = "Vegetation was lumped using " + w.preview.Settings.LumpTable + " table"
	}
	for row, value := range []string{w.preview.Report.Title, unitTitle, lumpLine} {
		if err := w.setText(sheetName, "A"+strconv.Itoa(row+1), value); err != nil {
			return err
		}
	}
	return nil
}

func (w *longVegWorkbookWriter) writeUnitColumnHeaders(sheetName string, unit LongVegetationUnit) ([]string, int, int, int, string, error) {
	plotColumns, err := collectDistinctUnitPlotColumns(unit.Rows)
	if err != nil {
		return nil, 0, 0, 0, "", err
	}
	settings := w.preview.Settings
	labels := []string{w.groupLabel, "Spp"}
	switch {
	case settings.ShowEnglishName:
		labels = append(labels, "English Name")
	case settings.ShowSpeciesCode:
		labels = append(labels, "Code")
	case settings.SelectedField != "":
		labels = append(labels, settings.SelectedField)
	}
	presenceColumn, meanColumn := len(labels)+1, len(labels)+2
	labels = append(labels, "P", "MC")
	firstPlotColumn := len(labels) + 1
	labels = append(labels, plotColumns...)
	if len(labels) > 16384 {
		return nil, 0, 0, 0, "", errors.New("Long Vegetation workbook exceeds Excel's column limit")
	}
	for column, label := range labels {
		address, err := excelize.CoordinatesToCellName(column+1, 4)
		if err != nil {
			return nil, 0, 0, 0, "", err
		}
		if err := w.setText(sheetName, address, label); err != nil {
			return nil, 0, 0, 0, "", err
		}
	}
	lastColumn, err := excelize.ColumnNumberToName(len(labels))
	if err != nil {
		return nil, 0, 0, 0, "", err
	}
	if err := w.book.SetCellStyle(sheetName, "A4", lastColumn+"4", w.styles.heading); err != nil {
		return nil, 0, 0, 0, "", err
	}
	return plotColumns, presenceColumn, meanColumn, firstPlotColumn, lastColumn, nil
}

func collectDistinctUnitPlotColumns(rows []LongVegetationRow) ([]string, error) {
	plots := map[string]bool{}
	for _, row := range rows {
		seen := map[string]bool{}
		for _, plot := range row.Plots {
			if seen[plot.PlotNumber] {
				return nil, errors.New("Long Vegetation row repeats a pivot plot")
			}
			seen[plot.PlotNumber], plots[plot.PlotNumber] = true, true
		}
	}
	plotColumns := make([]string, 0, len(plots))
	for plot := range plots {
		plotColumns = append(plotColumns, plot)
	}
	sort.Strings(plotColumns)
	return plotColumns, nil
}

func (w *longVegWorkbookWriter) writeUnitRows(
	sheetName string,
	unit LongVegetationUnit,
	plotColumns []string,
	presenceColumn, meanColumn, firstPlotColumn int,
) error {
	outputRow, previousGroup := 5, ""
	// Source starts at worksheet row 7 and stops at the next blank group.
	gapScans, scanGaps := 0, true
	for index, row := range unit.Rows {
		if err := w.ctx.Err(); err != nil {
			return err
		}
		group, lifeform, err := w.resolveRowGroup(row)
		if err != nil {
			return err
		}
		if w.layout.SpaceBetweenGroups && index >= 2 && scanGaps && gapScans < 1000 {
			if group != previousGroup {
				outputRow++
			}
			gapScans++
			if index+1 < len(unit.Rows) && isBlankLayerCell(unit.Rows[index+1].Layer) {
				scanGaps = false
			}
		}
		previousGroup = group
		if outputRow > 1048576 {
			return errors.New("Long Vegetation workbook exceeds Excel's row limit")
		}
		if err := w.writeSingleDataRow(sheetName, outputRow, row, lifeform, plotColumns, presenceColumn, meanColumn, firstPlotColumn); err != nil {
			return err
		}
		outputRow++
	}
	return nil
}

func isBlankLayerCell(cell vprocore.ProjectMetadataCell) bool {
	return cell.Storage == "null" || (cell.Text != nil && *cell.Text == "")
}

func (w *longVegWorkbookWriter) resolveRowGroup(row LongVegetationRow) (string, *int, error) {
	if w.preview.Settings.Grouping == "lifeform" {
		lifeform, err := vprocore.VegetationLifeformInteger(row.Layer)
		if err != nil {
			return "", nil, err
		}
		if lifeform != nil {
			return strconv.Itoa(*lifeform), lifeform, nil
		}
		return "", nil, nil
	}
	if row.Layer.Text != nil {
		return *row.Layer.Text, nil, nil
	}
	return "", nil, nil
}

func (w *longVegWorkbookWriter) writeSingleDataRow(
	sheetName string,
	outputRow int,
	row LongVegetationRow,
	lifeform *int,
	plotColumns []string,
	presenceColumn, meanColumn, firstPlotColumn int,
) error {
	rowStr := strconv.Itoa(outputRow)
	groupAddress := "A" + rowStr
	if lifeform != nil {
		if err := w.book.SetCellInt(sheetName, groupAddress, int64(*lifeform)); err != nil {
			return err
		}
		if err := w.book.SetCellStyle(sheetName, groupAddress, groupAddress, w.styles.lifeformStyle); err != nil {
			return err
		}
	} else if err := w.setCell(sheetName, groupAddress, row.Layer); err != nil {
		return err
	}
	if err := w.setCell(sheetName, "B"+rowStr, row.Species); err != nil {
		return err
	}
	settings := w.preview.Settings
	if settings.SelectedField != "" {
		if err := w.setSelectedCell(sheetName, "C"+rowStr, row.EnglishName); err != nil {
			return err
		}
	} else if settings.ShowEnglishName || settings.ShowSpeciesCode {
		if err := w.setCell(sheetName, "C"+rowStr, row.EnglishName); err != nil {
			return err
		}
	}
	if err := w.setCoordNumber(sheetName, presenceColumn, outputRow, row.Presence, w.styles.percent); err != nil {
		return err
	}
	if err := w.setCoordNumber(sheetName, meanColumn, outputRow, row.MeanCover, w.styles.cover); err != nil {
		return err
	}
	for _, plot := range row.Plots {
		column := sort.SearchStrings(plotColumns, plot.PlotNumber) + firstPlotColumn
		if err := w.setCoordNumber(sheetName, column, outputRow, plot.Cover, w.styles.cover); err != nil {
			return err
		}
	}
	return nil
}

func (w *longVegWorkbookWriter) configureSheetPanesAndPage(sheetName, lastColumn string, firstPlotColumn int) error {
	if err := w.book.AutoFitColWidth(sheetName, "A:"+lastColumn); err != nil {
		return err
	}
	firstPlot, err := excelize.CoordinatesToCellName(firstPlotColumn, 5)
	if err != nil {
		return err
	}
	if err := w.book.SetPanes(sheetName, &excelize.Panes{Freeze: true, XSplit: firstPlotColumn - 1,
		YSplit: 4, TopLeftCell: firstPlot, ActivePane: "bottomRight"}); err != nil {
		return err
	}
	if w.layout.QuickReport {
		return nil
	}
	orientation, side, top := "landscape", .75, .5
	if err := w.book.SetPageLayout(sheetName, &excelize.PageLayoutOptions{Orientation: &orientation}); err != nil {
		return err
	}
	if err := w.book.SetPageMargins(sheetName, &excelize.PageLayoutMarginsOptions{
		Left: &side, Right: &side, Top: &top, Bottom: &side,
	}); err != nil {
		return err
	}
	return w.book.SetHeaderFooter(sheetName, &excelize.HeaderFooterOptions{OddFooter: "&LPage &P of &N&R&D"})
}

func (w *longVegWorkbookWriter) setText(sheet, address, value string) error {
	if err := reportcore.EnvironmentWorkbookText(value); err != nil {
		return err
	}
	return w.book.SetCellStr(sheet, address, value)
}

func (w *longVegWorkbookWriter) setCell(sheet, address string, cell vprocore.ProjectMetadataCell) error {
	value, err := vprocore.MetadataCellValue(cell)
	if err != nil || value == nil {
		return err
	}
	text, ok := value.(string)
	if !ok {
		return errors.New("Long Vegetation workbook identities require original text/NULL storage")
	}
	return w.setText(sheet, address, text)
}

func (w *longVegWorkbookWriter) setSelectedCell(sheet, address string, cell vprocore.ProjectMetadataCell) error {
	value, err := longVegetationSelectedScalarValue(w.preview.Report.SelectedFieldType, cell)
	if err != nil || value == nil {
		return err
	}
	switch value := value.(type) {
	case string:
		err = w.setText(sheet, address, value)
	case int64:
		if w.preview.Report.SelectedFieldType == "boolean" {
			err = w.book.SetCellBool(sheet, address, value == -1)
		} else {
			err = w.book.SetCellInt(sheet, address, value)
		}
	case float64:
		err = w.book.SetCellFloat(sheet, address, value, -1, 64)
	default:
		return errors.New("Long Vegetation selected worksheet scalar lost its typed value")
	}
	if err != nil {
		return err
	}
	return w.book.SetCellStyle(sheet, address, address, w.styles.cover)
}

func (w *longVegWorkbookWriter) setCoordNumber(sheet string, column, row int, value *float64, style int) error {
	address, err := excelize.CoordinatesToCellName(column, row)
	if err != nil {
		return err
	}
	if value == nil {
		return nil
	}
	if math.IsNaN(*value) || math.IsInf(*value, 0) {
		return errors.New("Long Vegetation workbook requires finite typed numeric results")
	}
	if err := w.book.SetCellFloat(sheet, address, *value, -1, 64); err != nil {
		return err
	}
	return w.book.SetCellStyle(sheet, address, address, style)
}

func appendLongVegHiddenSourceSheet(
	ctx context.Context,
	book *excelize.File,
	preview LongVegetationPreview,
	layout vegetationWorkbookLayout,
	project *vegetationProjectWorkbookEvidence,
	sheets []reportcore.VegetationWorkbookSheetInternal,
) error {
	if _, err := book.NewSheet("_VPRO_Source"); err != nil {
		return err
	}
	for _, sheet := range sheets {
		if err := book.MoveSheet(sheet.Name, "_VPRO_Source"); err != nil {
			return err
		}
	}
	if layout.ReportSummary {
		if err := book.MoveSheet("ReportSummary", "_VPRO_Source"); err != nil {
			return err
		}
	}
	book.SetActiveSheet(0)
	source, err := json.Marshal(struct {
		Preview LongVegetationPreview
		Layout  vegetationWorkbookLayout
		Project *vegetationProjectWorkbookEvidence `json:"Project,omitempty"`
	}{preview, layout, project})
	if err != nil {
		return err
	}
	encoded := hex.EncodeToString(source)
	for offset, row := 0, 1; offset < len(encoded); offset, row = offset+30000, row+1 {
		if err := ctx.Err(); err != nil {
			return err
		}
		if row > 1048576 {
			return errors.New("Long Vegetation lossless source metadata exceeds Excel's row limit")
		}
		if err := book.SetCellStr("_VPRO_Source", "A"+strconv.Itoa(row), encoded[offset:min(offset+30000, len(encoded))]); err != nil {
			return err
		}
	}
	return book.SetSheetVisible("_VPRO_Source", false, true)
}
