package diagnostics

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type diagnosticWorkbookStyles struct {
	title         int
	subtitle      int
	header        int
	headerLeft    int
	sectionBanner int
	unitBanner    int
	centerCell    int
	italicSci     int
	diagFills     map[string]int
	warnRow       int
	highSim       int
	medSim        int
	edatopicCore  int
	edatopicSub   int
}

// ResolveDiagnosticWorkbookSheets validates Excel worksheet names (31 UTF-16 units, XML safety)
// and enforces case-insensitive uniqueness via strings.EqualFold matching excelize/v2 (§4.3).
func ResolveDiagnosticWorkbookSheets(rawNames []string) ([]string, error) {
	if len(rawNames) == 0 {
		return nil, errors.New("workbook requires at least one worksheet")
	}
	resolved := make([]string, 0, len(rawNames))
	for i, raw := range rawNames {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			return nil, fmt.Errorf("worksheet #%d name must not be empty", i+1)
		}
		clean, err := reportcore.EnvironmentWorkbookSheetName(trimmed, i+1)
		if err != nil {
			return nil, fmt.Errorf("worksheet %q: %w", raw, err)
		}
		for _, prev := range resolved {
			if strings.EqualFold(prev, clean) {
				return nil, fmt.Errorf("worksheet name collision between %q and %q (case-insensitive Excel match)", prev, clean)
			}
		}
		resolved = append(resolved, clean)
	}
	return resolved, nil
}

func primaryDiagFillKey(codes []string) string {
	if slices.Contains(codes, "d") && (slices.Contains(codes, "cd") || slices.Contains(codes, "dd")) {
		return "d_dom"
	}
	if slices.Contains(codes, "dd") {
		return "dd"
	}
	if slices.Contains(codes, "d") {
		return "d"
	}
	if slices.Contains(codes, "cd") {
		return "cd"
	}
	if slices.Contains(codes, "c") {
		return "c"
	}
	if slices.Contains(codes, "ic") {
		return "ic"
	}
	return ""
}

func setCellChecked(f *excelize.File, sheet string, col, row int, val any) error {
	coord, err := excelize.CoordinatesToCellName(col, row)
	if err != nil {
		return err
	}
	if str, ok := val.(string); ok {
		if err := reportcore.EnvironmentWorkbookText(str); err != nil {
			return err
		}
	}
	return f.SetCellValue(sheet, coord, val)
}

func styleRangeChecked(f *excelize.File, sheet string, c1, r1, c2, r2, styleID int) error {
	start, err := excelize.CoordinatesToCellName(c1, r1)
	if err != nil {
		return err
	}
	end, err := excelize.CoordinatesToCellName(c2, r2)
	if err != nil {
		return err
	}
	return f.SetCellStyle(sheet, start, end, styleID)
}

func encodeDiagnosticWorkbookBytes(
	ctx context.Context,
	snap *SynthesisSnapshot,
	req ExportDiagnosticWorkbookRequest,
	sheetNames []string,
) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	f := excelize.NewFile()
	defer func() { _ = f.Close() }()

	if err := f.SetSheetName("Sheet1", sheetNames[0]); err != nil {
		return nil, err
	}
	for _, name := range sheetNames[1:] {
		if _, err := f.NewSheet(name); err != nil {
			return nil, err
		}
	}

	styles, err := initDiagnosticWorkbookStyles(f)
	if err != nil {
		return nil, err
	}
	if err := writeDiagnosticSummarySheet(ctx, f, sheetNames[0], snap, req, styles); err != nil {
		return nil, err
	}
	if err := writePairwiseSimilaritySheet(f, sheetNames[1], snap, styles); err != nil {
		return nil, err
	}
	if err := writeOutlierQueueSheet(f, sheetNames[2], snap, styles); err != nil {
		return nil, err
	}
	if err := writeEdatopicGridsSheet(f, sheetNames, snap, req.IncludeUnitEdatopicTabs, styles); err != nil {
		return nil, err
	}

	var buf bytes.Buffer
	if _, err := f.WriteTo(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func initDiagnosticWorkbookStyles(f *excelize.File) (diagnosticWorkbookStyles, error) {
	var st diagnosticWorkbookStyles
	var err error
	if st.title, err = f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 13, Color: "#003366", Family: "Calibri"},
	}); err != nil {
		return st, err
	}
	if st.subtitle, err = f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Italic: true, Size: 10, Color: "#334155", Family: "Calibri"},
	}); err != nil {
		return st, err
	}
	if st.header, err = newNavyHeaderStyle(f, "center", true); err != nil {
		return st, err
	}
	if st.headerLeft, err = newNavyHeaderStyle(f, "left", false); err != nil {
		return st, err
	}
	if st.sectionBanner, err = newBannerStyle(f, "#003366", "#EBF1F8", "#9EC3E6"); err != nil {
		return st, err
	}
	if st.unitBanner, err = newBannerStyle(f, "#1E5128", "#E9F1EB", "#B7CFC0"); err != nil {
		return st, err
	}
	if st.centerCell, err = f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Size: 10, Family: "Calibri"},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	}); err != nil {
		return st, err
	}
	if st.italicSci, err = f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Italic: true, Size: 10, Family: "Calibri"},
	}); err != nil {
		return st, err
	}
	return populateDiagnosticFillStyles(f, st)
}

func newNavyHeaderStyle(f *excelize.File, horizontal string, wrap bool) (int, error) {
	return f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 10, Color: "#FFFFFF", Family: "Calibri"},
		Fill:      excelize.Fill{Type: "pattern", Pattern: 1, Color: []string{"#003366"}},
		Alignment: &excelize.Alignment{Horizontal: horizontal, Vertical: "center", WrapText: wrap},
		Border:    []excelize.Border{{Type: "bottom", Color: "#FCBA19", Style: 2}},
	})
}

func newBannerStyle(f *excelize.File, textHex, fillHex, borderHex string) (int, error) {
	return f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 10, Color: textHex, Family: "Calibri"},
		Fill: excelize.Fill{Type: "pattern", Pattern: 1, Color: []string{fillHex}},
		Border: []excelize.Border{
			{Type: "top", Color: borderHex, Style: 1},
			{Type: "bottom", Color: borderHex, Style: 1},
		},
	})
}

func newDiagFillStyle(f *excelize.File, hexColor string, bold bool) (int, error) {
	return f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: bold, Size: 10, Color: "#313132", Family: "Calibri"},
		Fill:      excelize.Fill{Type: "pattern", Pattern: 1, Color: []string{hexColor}},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
		Border: []excelize.Border{
			{Type: "left", Color: "#D1D5DB", Style: 1},
			{Type: "right", Color: "#D1D5DB", Style: 1},
			{Type: "top", Color: "#D1D5DB", Style: 1},
			{Type: "bottom", Color: "#D1D5DB", Style: 1},
		},
	})
}

func populateDiagnosticFillStyles(f *excelize.File, st diagnosticWorkbookStyles) (diagnosticWorkbookStyles, error) {
	st.diagFills = map[string]int{}
	for k, spec := range map[string]struct {
		hex  string
		bold bool
	}{
		"d_dom": {"#FCBA19", true},  // Differential + Dominant / Constant Dominant (BC Gold)
		"dd":    {"#FEF6E0", true},  // Dominant Differential (BC Advisory Gold tint)
		"d":     {"#E9F1EB", true},  // Differential (BEC Forest tint)
		"cd":    {"#D6E6F5", true},  // Constant Dominant (BC Navy tint)
		"c":     {"#EBF1F8", false}, // Constant (Subtle BC Navy tint)
		"ic":    {"#F4F6F8", false}, // Important Companion (Neutral canvas)
	} {
		stID, err := newDiagFillStyle(f, spec.hex, spec.bold)
		if err != nil {
			return st, err
		}
		st.diagFills[k] = stID
	}
	var err error
	if st.warnRow, err = newDiagFillStyle(f, "#FEF6E0", true); err != nil {
		return st, err
	}
	if st.highSim, err = newDiagFillStyle(f, "#D6E6F5", true); err != nil {
		return st, err
	}
	if st.medSim, err = newDiagFillStyle(f, "#EBF1F8", false); err != nil {
		return st, err
	}
	if st.edatopicCore, err = newDiagFillStyle(f, "#FCBA19", true); err != nil {
		return st, err
	}
	if st.edatopicSub, err = newDiagFillStyle(f, "#E9F1EB", false); err != nil {
		return st, err
	}
	return st, nil
}

func writeDiagnosticSummarySheet(
	ctx context.Context,
	f *excelize.File,
	diagSheet string,
	snap *SynthesisSnapshot,
	req ExportDiagnosticWorkbookRequest,
	styles diagnosticWorkbookStyles,
) error {
	if err := writeDiagnosticSummaryBanner(f, diagSheet, snap, req.ReportTitle, styles); err != nil {
		return err
	}
	baseCols, totalDiagCols, err := writeDiagnosticSummaryHeaders(f, diagSheet, snap.Units, req.IncludeCommonNames, styles)
	if err != nil {
		return err
	}

	diagByUnit := map[string][]SynthesisSpeciesRow{}
	var nonDiagSpecies []SynthesisSpeciesRow
	for _, sp := range snap.Species {
		if sp.DiagnosticUnit != "" {
			diagByUnit[sp.DiagnosticUnit] = append(diagByUnit[sp.DiagnosticUnit], sp)
		} else {
			nonDiagSpecies = append(nonDiagSpecies, sp)
		}
	}

	curRow := 6
	for _, u := range snap.Units {
		unitHeader := "~" + u.SiteUnit
		if u.LongName != "" {
			unitHeader = fmt.Sprintf("~%s — %s (n=%d)", u.SiteUnit, u.LongName, u.PlotCount)
		}
		if err := setCellChecked(f, diagSheet, 2, curRow, unitHeader); err != nil {
			return err
		}
		_ = styleRangeChecked(f, diagSheet, 1, curRow, totalDiagCols, curRow, styles.unitBanner)
		curRow++
		for _, sp := range diagByUnit[u.SiteUnit] {
			if err := writeDiagnosticSpeciesRow(ctx, f, diagSheet, curRow, baseCols, sp, snap.SignificanceBasis, req.IncludeCommonNames, styles); err != nil {
				return err
			}
			curRow++
		}
	}

	if err := setCellChecked(f, diagSheet, 2, curRow, "Non-Diagnostic Species"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, 1, curRow, totalDiagCols, curRow, styles.sectionBanner)
	curRow++
	for _, sp := range nonDiagSpecies {
		if err := writeDiagnosticSpeciesRow(ctx, f, diagSheet, curRow, baseCols, sp, snap.SignificanceBasis, req.IncludeCommonNames, styles); err != nil {
			return err
		}
		curRow++
	}

	_ = f.AutoFitColWidth(diagSheet, "A:C")
	if topLeft, err := excelize.CoordinatesToCellName(baseCols+1, 6); err == nil {
		_ = f.SetPanes(diagSheet, &excelize.Panes{
			Freeze:      true,
			XSplit:      baseCols,
			YSplit:      5,
			TopLeftCell: topLeft,
			ActivePane:  "bottomRight",
		})
	}
	return nil
}

func writeDiagnosticSummaryBanner(
	f *excelize.File,
	diagSheet string,
	snap *SynthesisSnapshot,
	reportTitle string,
	styles diagnosticWorkbookStyles,
) error {
	title := strings.TrimSpace(reportTitle)
	if title == "" {
		suLabel := snap.SU
		if suLabel == "" || strings.EqualFold(suLabel, "None") {
			suLabel = "UserSiteUnit"
		}
		title = fmt.Sprintf("VPro BEC Diagnostic Summary Vegetation Report — %s (%s)", snap.Project, suLabel)
	}
	if err := setCellChecked(f, diagSheet, 1, 1, title); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, 1, 1, 1, 1, styles.title)

	subMeta := fmt.Sprintf("Vegetation Table | Classified Plots: %d across %d Site Units | Significance Basis: %s",
		snap.ClassifiedPlotCount, len(snap.Units), snap.SignificanceBasis)
	if err := setCellChecked(f, diagSheet, 1, 2, subMeta); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, 1, 2, 1, 2, styles.subtitle)

	lumpComment := ""
	if snap.LumpTableUsed != "" {
		lumpComment = fmt.Sprintf("Vegetation was lumped using %s table (99%% cover cap)", snap.LumpTableUsed)
	}
	if err := setCellChecked(f, diagSheet, 1, 3, lumpComment); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, 1, 3, 1, 3, styles.subtitle)
	return nil
}

func writeDiagnosticSummaryHeaders(
	f *excelize.File,
	diagSheet string,
	units []SynthesisUnitSummary,
	includeCommonNames bool,
	styles diagnosticWorkbookStyles,
) (int, int, error) {
	fixedHeaders := []string{"Lifeform", "Species", "ScientificName"}
	if includeCommonNames {
		fixedHeaders = append(fixedHeaders, "EnglishName")
	}
	fixedHeaders = append(fixedHeaders, "DiagnosticUnit", "Diagnostic")
	baseCols := len(fixedHeaders)

	if err := setCellChecked(f, diagSheet, 2, 4, "nPlots"); err != nil {
		return 0, 0, err
	}
	_ = styleRangeChecked(f, diagSheet, 1, 4, baseCols, 4, styles.subtitle)

	for cIdx, h := range fixedHeaders {
		if err := setCellChecked(f, diagSheet, cIdx+1, 5, h); err != nil {
			return 0, 0, err
		}
		st := styles.headerLeft
		if h == "Lifeform" || h == "Diagnostic" {
			st = styles.header
		}
		_ = styleRangeChecked(f, diagSheet, cIdx+1, 5, cIdx+1, 5, st)
	}

	for uIdx, u := range units {
		colStart := baseCols + uIdx*3 + 1
		if err := setCellChecked(f, diagSheet, colStart, 4, u.PlotCount); err != nil {
			return 0, 0, err
		}
		_ = styleRangeChecked(f, diagSheet, colStart, 4, colStart+2, 4, styles.centerCell)

		for offset, label := range []string{u.SiteUnit, u.SiteUnit + " Pres (I-V / %)", u.SiteUnit + " Cov (+..9 / %)"} {
			if err := setCellChecked(f, diagSheet, colStart+offset, 5, label); err != nil {
				return 0, 0, err
			}
		}
		_ = styleRangeChecked(f, diagSheet, colStart, 5, colStart+2, 5, styles.header)
	}
	return baseCols, max(baseCols+len(units)*3, baseCols), nil
}

func writeDiagnosticSpeciesRow(
	ctx context.Context,
	f *excelize.File,
	diagSheet string,
	excelRow, baseCols int,
	sp SynthesisSpeciesRow,
	significanceBasis string,
	includeCommonNames bool,
	styles diagnosticWorkbookStyles,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	lfVal := ""
	if sp.Lifeform != nil {
		lfVal = fmt.Sprintf("%d (%s)", *sp.Lifeform, sp.StratumGroup)
	}
	col := 1
	if err := setCellChecked(f, diagSheet, col, excelRow, lfVal); err != nil {
		return err
	}
	col++
	if err := setCellChecked(f, diagSheet, col, excelRow, sp.Species); err != nil {
		return err
	}
	col++
	if err := setCellChecked(f, diagSheet, col, excelRow, sp.ScientificName); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, col, excelRow, col, excelRow, styles.italicSci)
	col++
	if includeCommonNames {
		if err := setCellChecked(f, diagSheet, col, excelRow, sp.EnglishName); err != nil {
			return err
		}
		col++
	}
	if err := setCellChecked(f, diagSheet, col, excelRow, sp.DiagnosticUnit); err != nil {
		return err
	}
	_ = styleRangeChecked(f, diagSheet, col, excelRow, col, excelRow, styles.centerCell)
	col++
	if err := setCellChecked(f, diagSheet, col, excelRow, sp.Diagnosis); err != nil {
		return err
	}
	diagColStyle := styles.centerCell
	if fk := primaryDiagFillKey(sp.DiagnosticCodes); fk != "" {
		diagColStyle = styles.diagFills[fk]
	}
	_ = styleRangeChecked(f, diagSheet, col, excelRow, col, excelRow, diagColStyle)

	return writeDiagnosticSpeciesUnitCells(f, diagSheet, excelRow, baseCols, sp.Cells, significanceBasis, styles)
}

func writeDiagnosticSpeciesUnitCells(
	f *excelize.File,
	diagSheet string,
	excelRow, baseCols int,
	cells []SynthesisUnitSpeciesCell,
	significanceBasis string,
	styles diagnosticWorkbookStyles,
) error {
	for uIdx, cell := range cells {
		if cell.PresentPlots <= 0 {
			continue
		}
		cStart := baseCols + uIdx*3 + 1
		presDisplay := fmt.Sprintf("%s (%s%%)", cell.PresenceRoman, cell.PresencePctText)
		meanText := cell.MeanCoverAllText
		if significanceBasis == "present_plots" {
			meanText = cell.MeanCoverPresentText
		}
		covDisplay := fmt.Sprintf("%s (%s%%)", cell.SignifClass, meanText)
		for offset, val := range []any{cell.CrosstabCode, presDisplay, covDisplay} {
			if err := setCellChecked(f, diagSheet, cStart+offset, excelRow, val); err != nil {
				return err
			}
		}
		cellStyle := styles.centerCell
		if fk := primaryDiagFillKey(cell.CellDiagnosticCodes); fk != "" {
			cellStyle = styles.diagFills[fk]
		}
		_ = styleRangeChecked(f, diagSheet, cStart, excelRow, cStart+2, excelRow, cellStyle)
	}
	return nil
}

func writePairwiseSimilaritySheet(
	f *excelize.File,
	simSheet string,
	snap *SynthesisSnapshot,
	styles diagnosticWorkbookStyles,
) error {
	if err := setCellChecked(f, simSheet, 1, 1, "Pairwise Unit Similarity Matrix (Sorensen / Bray-Curtis & BEC Differential Similarity)"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, simSheet, 1, 1, 1, 1, styles.title)
	if err := setCellChecked(f, simSheet, 1, 2, "Formula: 2 * sum(min(MeanCover_u1, MeanCover_u2)) / sum(MeanCover_u1 + MeanCover_u2)"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, simSheet, 1, 2, 1, 2, styles.subtitle)

	if err := setCellChecked(f, simSheet, 1, 4, "SiteUnit"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, simSheet, 1, 4, 1, 4, styles.headerLeft)
	for j, u := range snap.Units {
		if err := setCellChecked(f, simSheet, j+2, 4, u.SiteUnit); err != nil {
			return err
		}
		_ = styleRangeChecked(f, simSheet, j+2, 4, j+2, 4, styles.header)
	}

	for i, row := range snap.SimilarityMatrix {
		if err := writeSimilarityMatrixRow(f, simSheet, i, row, styles); err != nil {
			return err
		}
	}
	if err := writePairwiseDifferentialTable(f, simSheet, 7+len(snap.SimilarityMatrix), snap.PairwiseComparisons, styles); err != nil {
		return err
	}
	_ = f.AutoFitColWidth(simSheet, "A:L")
	return nil
}

func writeSimilarityMatrixRow(
	f *excelize.File,
	simSheet string,
	rowIndex int,
	row PairwiseMatrixRow,
	styles diagnosticWorkbookStyles,
) error {
	rIdx := 5 + rowIndex
	if err := setCellChecked(f, simSheet, 1, rIdx, row.Unit); err != nil {
		return err
	}
	_ = styleRangeChecked(f, simSheet, 1, rIdx, 1, rIdx, styles.sectionBanner)
	for j, cell := range row.Cells {
		if err := setCellChecked(f, simSheet, j+2, rIdx, cell.SimilarityPct); err != nil {
			return err
		}
		st := styles.centerCell
		if rowIndex != j {
			if cell.SimilarityPct >= 70.0 {
				st = styles.highSim
			} else if cell.SimilarityPct >= 50.0 {
				st = styles.medSim
			}
		}
		_ = styleRangeChecked(f, simSheet, j+2, rIdx, j+2, rIdx, st)
	}
	return nil
}

func writePairwiseDifferentialTable(
	f *excelize.File,
	simSheet string,
	pairStartRow int,
	comparisons []PairwiseUnitComparison,
	styles diagnosticWorkbookStyles,
) error {
	if err := setCellChecked(f, simSheet, 1, pairStartRow, "Pairwise BEC Differential Potential Summary (do_pairwise)"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, simSheet, 1, pairStartRow, 1, pairStartRow, styles.title)

	pairHeaders := []string{
		"Unit1", "Unit2", "nPlots1", "nPlots2",
		"SorensenSim (%)", "BEC.sim.mean (%)", "BEC.sim.min (%)", "BEC.sim.max (%)",
		"SharedDiagPot", "DiffPts Unit1", "DiffPts Unit2", "Top Diff Taxa",
	}
	pairHeaderRow := pairStartRow + 1
	for cIdx, h := range pairHeaders {
		if err := setCellChecked(f, simSheet, cIdx+1, pairHeaderRow, h); err != nil {
			return err
		}
		_ = styleRangeChecked(f, simSheet, cIdx+1, pairHeaderRow, cIdx+1, pairHeaderRow, styles.header)
	}
	for idx, comp := range comparisons {
		r := pairHeaderRow + 1 + idx
		topNames := make([]string, 0, min(5, len(comp.DifferentialTaxa)))
		for k := 0; k < len(comp.DifferentialTaxa) && k < 5; k++ {
			dt := comp.DifferentialTaxa[k]
			topNames = append(topNames, fmt.Sprintf("%s (%s)", dt.Species, dt.FavoursUnit))
		}
		vals := []any{
			comp.Unit1, comp.Unit2, comp.PlotsUnit1, comp.PlotsUnit2,
			comp.SorensenPct, RoundACE15(comp.BECSimMean*100.0, 1),
			RoundACE15(comp.BECSimMin*100.0, 1), RoundACE15(comp.BECSimMax*100.0, 1),
			comp.SharedDiagPotential, comp.DiffTotalUnit1, comp.DiffTotalUnit2,
			strings.Join(topNames, "; "),
		}
		for cIdx, v := range vals {
			if err := setCellChecked(f, simSheet, cIdx+1, r, v); err != nil {
				return err
			}
		}
	}
	return nil
}

func writeOutlierQueueSheet(
	f *excelize.File,
	outSheet string,
	snap *SynthesisSnapshot,
	styles diagnosticWorkbookStyles,
) error {
	if err := setCellChecked(f, outSheet, 1, 1, "Candidate Misplaced Plots Queue (Leave-One-Out Centroid Similarity)"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, outSheet, 1, 1, 1, 1, styles.title)
	if err := setCellChecked(f, outSheet, 1, 2, "Sorted by RivalSimilarity - OwnLOOSimilarity descending; top 5% anomalous and misplaced plots highlighted"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, outSheet, 1, 2, 1, 2, styles.subtitle)

	outHeaders := []string{
		"Rank", "PlotNumber", "AssignedUnit", "UnitPlots",
		"OwnLOOSim (%)", "NearestRivalUnit", "RivalSim (%)", "DeltaSim (%)",
		"Status", "rSMR", "rSNR", "Zone", "SubZone", "SiteSeries",
	}
	for cIdx, h := range outHeaders {
		if err := setCellChecked(f, outSheet, cIdx+1, 4, h); err != nil {
			return err
		}
		_ = styleRangeChecked(f, outSheet, cIdx+1, 4, cIdx+1, 4, styles.header)
	}

	for idx, cand := range snap.OutlierQueue {
		r := 5 + idx
		vals := []any{
			cand.Rank, cand.PlotNumber, cand.AssignedUnit, cand.AssignedUnitPlots,
			cand.OwnSimilarityPct, cand.NearestRivalUnit, cand.RivalSimilarityPct, cand.DeltaSimilarityPct,
			outlierCandidateStatusLabel(cand), cand.MoistureRegime, cand.NutrientRegime, cand.Zone, cand.SubZone, cand.SiteSeries,
		}
		for cIdx, v := range vals {
			if err := setCellChecked(f, outSheet, cIdx+1, r, v); err != nil {
				return err
			}
		}
		if cand.Misplaced || cand.Top5PercentAnomaly {
			_ = styleRangeChecked(f, outSheet, 1, r, len(outHeaders), r, styles.warnRow)
		}
	}
	_ = f.AutoFitColWidth(outSheet, "A:N")
	return nil
}

func outlierCandidateStatusLabel(cand OutlierPlotCandidate) string {
	switch {
	case cand.Misplaced && cand.Top5PercentAnomaly:
		return "Candidate Misplaced (Top 5%)"
	case cand.Misplaced:
		return "Candidate Misplaced"
	case cand.SingletonUnit:
		return "Singleton Unit"
	case cand.Top5PercentAnomaly:
		return "Top 5% Anomaly"
	default:
		return "Consistent"
	}
}

func writeEdatopicGridsSheet(
	f *excelize.File,
	sheetNames []string,
	snap *SynthesisSnapshot,
	includeUnitTabs bool,
	styles diagnosticWorkbookStyles,
) error {
	edaSheet := sheetNames[3]
	if err := setCellChecked(f, edaSheet, 1, 1, "Relative Edatopic Grids (rSMR 0..8 x rSNR A..F) — Plot Counts & % Prominence"); err != nil {
		return err
	}
	_ = styleRangeChecked(f, edaSheet, 1, 1, 1, 1, styles.title)

	nextEdaRow, err := writeEdatopicBlock(f, edaSheet, 3, snap.OverallEdatopicGrid, styles)
	if err != nil {
		return err
	}
	for uIdx, uGrid := range snap.UnitEdatopicGrids {
		nextEdaRow, err = writeEdatopicBlock(f, edaSheet, nextEdaRow, uGrid, styles)
		if err != nil {
			return err
		}
		if includeUnitTabs && 4+uIdx < len(sheetNames) {
			uTab := sheetNames[4+uIdx]
			if _, err := writeEdatopicBlock(f, uTab, 2, uGrid, styles); err != nil {
				return err
			}
			_ = f.AutoFitColWidth(uTab, "A:G")
		}
	}
	_ = f.AutoFitColWidth(edaSheet, "A:G")
	return nil
}

func writeEdatopicBlock(
	f *excelize.File,
	targetSheet string,
	startRow int,
	grid EdatopicUnitGrid,
	styles diagnosticWorkbookStyles,
) (int, error) {
	hdr := fmt.Sprintf("%s (Plotted: %d / %d, Missing Edatopic: %d)",
		grid.Label, grid.PlottedEdatopicCount, grid.TotalPlots, grid.MissingEdatopicCount)
	if err := setCellChecked(f, targetSheet, 1, startRow, hdr); err != nil {
		return startRow, err
	}
	_ = styleRangeChecked(f, targetSheet, 1, startRow, 7, startRow, styles.sectionBanner)

	colHdrRow := startRow + 1
	if err := setCellChecked(f, targetSheet, 1, colHdrRow, "rSMR \\ rSNR"); err != nil {
		return startRow, err
	}
	_ = styleRangeChecked(f, targetSheet, 1, colHdrRow, 1, colHdrRow, styles.header)
	for cIdx, snr := range SNRCols {
		if err := setCellChecked(f, targetSheet, cIdx+2, colHdrRow, snr); err != nil {
			return startRow, err
		}
		_ = styleRangeChecked(f, targetSheet, cIdx+2, colHdrRow, cIdx+2, colHdrRow, styles.header)
	}

	for rIdx, smr := range SMRRows {
		rowNum := colHdrRow + 1 + rIdx
		if err := setCellChecked(f, targetSheet, 1, rowNum, smr); err != nil {
			return startRow, err
		}
		_ = styleRangeChecked(f, targetSheet, 1, rowNum, 1, rowNum, styles.sectionBanner)

		for cIdx := range SNRCols {
			cell := grid.Cells[rIdx*len(SNRCols)+cIdx]
			display := ""
			if cell.PlotCount > 0 {
				display = fmt.Sprintf("%d (%.0f%%)", cell.PlotCount, cell.Prominence)
			}
			if err := setCellChecked(f, targetSheet, cIdx+2, rowNum, display); err != nil {
				return startRow, err
			}
			st := styles.centerCell
			if cell.Prominence >= 25.0 {
				st = styles.edatopicCore
			} else if cell.PlotCount > 0 {
				st = styles.edatopicSub
			}
			_ = styleRangeChecked(f, targetSheet, cIdx+2, rowNum, cIdx+2, rowNum, st)
		}
	}
	return colHdrRow + len(SMRRows) + 2, nil
}

func validateEncodedDiagnosticWorkbook(ctx context.Context, data []byte, expectedSheets []string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	opened, err := excelize.OpenReader(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("open staged diagnostic workbook: %w", err)
	}
	defer func() { _ = opened.Close() }()

	actualSheets := opened.GetSheetList()
	if len(actualSheets) != len(expectedSheets) {
		return fmt.Errorf("expected %d sheets in diagnostic workbook, got %d", len(expectedSheets), len(actualSheets))
	}
	for i := range expectedSheets {
		if actualSheets[i] != expectedSheets[i] {
			return fmt.Errorf("sheet #%d mismatch: expected %q, got %q", i+1, expectedSheets[i], actualSheets[i])
		}
		for j := range i {
			if strings.EqualFold(actualSheets[j], actualSheets[i]) {
				return fmt.Errorf("case-folded worksheet collision detected in staged workbook: %q vs %q", actualSheets[j], actualSheets[i])
			}
		}
	}
	return nil
}

// ExportDiagnosticWorkbook atomically publishes a Diagnostic10.xla-compatible 4-sheet .xlsx workbook
// using vprocore.PublishArtifactChecked (staged temp file + os.Link no-overwrite) and strings.EqualFold
// worksheet collision guards.
func ExportDiagnosticWorkbook(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	req ExportDiagnosticWorkbookRequest,
) (*ExportDiagnosticWorkbookResult, error) {
	started := time.Now()
	outPath, baseSheets, err := validateExportDiagnosticWorkbookRequest(ctx, contexts, req)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ExportDiagnosticWorkbookResult, error) {
		owner := plots.Projects.Sqlite
		snap, err := computeSnapshotForPlots(ctx, owner, contextID, req.Options)
		if err != nil {
			return nil, err
		}

		rawSheets := append([]string(nil), baseSheets...)
		if req.IncludeUnitEdatopicTabs {
			for _, u := range snap.Units {
				rawSheets = append(rawSheets, "Eda_"+u.SiteUnit)
			}
		}
		sheetNames, err := ResolveDiagnosticWorkbookSheets(rawSheets)
		if err != nil {
			return nil, err
		}

		pub, err := vprocore.PublishArtifactChecked(
			ctx,
			outPath,
			vprocore.ArtifactPublicationFormat{
				Label:        "diagnostic synthesis workbook",
				Artifact:     "workbook",
				CommitLabel:  "diagnostic synthesis workbook",
				StagePattern: ".vpro-diagnostic-*.xlsx.tmp",
				Encode: func(encodeCtx context.Context) ([]byte, error) {
					return encodeDiagnosticWorkbookBytes(encodeCtx, snap, req, sheetNames)
				},
				Validate: func(valCtx context.Context, data []byte) error {
					return validateEncodedDiagnosticWorkbook(valCtx, data, sheetNames)
				},
			},
			func() error {
				return vprocore.ProfileOwnedFiles(owner)
			},
			vprocore.ArtifactPublicationHooks{},
		)
		if err != nil {
			return nil, err
		}

		latencyMs := float64(time.Since(started).Microseconds()) / 1000.0
		return &ExportDiagnosticWorkbookResult{
			Path:        pub.Path,
			SHA256:      pub.SHA256,
			SheetNames:  sheetNames,
			UnitCount:   len(snap.Units),
			SpeciesRows: len(snap.Species),
			OutlierRows: len(snap.OutlierQueue),
			LatencyMs:   RoundACE15(latencyMs, 2),
		}, nil
	})
}

func validateExportDiagnosticWorkbookRequest(
	ctx context.Context,
	contexts *vprocore.ContextService,
	req ExportDiagnosticWorkbookRequest,
) (string, []string, error) {
	if ctx == nil {
		return "", nil, errors.New("diagnostic workbook export requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return "", nil, err
	}
	if contexts == nil {
		return "", nil, errors.New("classification context service is unavailable")
	}
	outPath := strings.TrimSpace(req.OutputPath)
	if outPath == "" {
		return "", nil, errors.New("outputPath is required for diagnostic workbook export")
	}
	if !strings.EqualFold(filepathExt(outPath), ".xlsx") {
		return "", nil, errors.New("diagnostic workbook outputPath must end with .xlsx")
	}
	return outPath, []string{
		defaultSheetName(req.DiagnosticSheetName, "Diagnostic Summary"),
		defaultSheetName(req.SimilaritySheetName, "Pairwise Similarity"),
		defaultSheetName(req.OutlierSheetName, "Outlier Queue"),
		defaultSheetName(req.EdatopicSheetName, "Edatopic Grid"),
	}, nil
}

func defaultSheetName(raw, fallback string) string {
	if trimmed := strings.TrimSpace(raw); trimmed != "" {
		return trimmed
	}
	return fallback
}

func filepathExt(p string) string {
	for i := len(p) - 1; i >= 0; i-- {
		if p[i] == '/' || p[i] == '\\' {
			break
		}
		if p[i] == '.' {
			return p[i:]
		}
	}
	return ""
}
