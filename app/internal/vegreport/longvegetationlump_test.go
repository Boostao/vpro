package vegreport

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/xuri/excelize/v2"
)

func TestLongVegetationOver250PlotsAndSingleSummaryPerWorkbook(t *testing.T) {
	preview := vegetationWorkbookFixture(t)
	preview.Settings.ShowEnglishName, preview.Settings.ShowSpeciesCode = false, false

	// Build 251 plots for unit 0 and a 2nd unit so ReportSummary is exercised across multiple units.
	const numPlots = 251
	plots := make([]LongVegetationPlot, numPlots)
	for i := 0; i < numPlots; i++ {
		name := fmt.Sprintf("P%03d", i+1)
		cover := 10.0
		plots[i] = LongVegetationPlot{PlotNumber: name, Cover: &cover}
	}
	baseRow := preview.Report.Units[0].Rows[0]
	baseRow.Layer = vprotest.MetadataText("A1")
	baseRow.Species = vprotest.MetadataText("Pseudotsuga menziesii")
	baseRow.Plots = plots

	u1Code := "UnitA"
	u2Code := "UnitB"
	c5 := 5.0
	unit2Row := baseRow
	unit2Row.Plots = []LongVegetationPlot{{PlotNumber: "Q1", Cover: &c5}}

	preview.Report.Units = []LongVegetationUnit{
		{
			Code:          vprotest.MetadataText(u1Code),
			NumPlots:      numPlots,
			MembershipIDs: []string{"1"},
			Rows:          []LongVegetationRow{baseRow},
		},
		{
			Code:          vprotest.MetadataText(u2Code),
			NumPlots:      1,
			MembershipIDs: []string{"2"},
			Rows:          []LongVegetationRow{unit2Row},
		},
	}

	env, su, metadata := vegetationSummaryFixture()
	summary, err := prepareVegetationWorkbookSummary(context.Background(), "2026-10-10", env, su, metadata)
	if err != nil {
		t.Fatal(err)
	}
	got, err := prepareLongVegetationWorkbook(context.Background(), preview, vegetationWorkbookLayout{
		ReportSummary: true,
		Summary:       &summary,
	})
	if err != nil {
		t.Fatalf("251-plot multi-unit workbook failed: %v", err)
	}
	book, err := excelize.OpenReader(bytes.NewReader(got.Bytes))
	if err != nil {
		t.Fatal(err)
	}
	wantSheets := []string{"UnitA", "UnitB", "ReportSummary", "_VPRO_Source"}
	sheets := book.GetSheetList()
	if len(sheets) != len(wantSheets) {
		t.Fatalf("unexpected sheets: got %v want %v", sheets, wantSheets)
	}
	for i, w := range wantSheets {
		if sheets[i] != w {
			t.Fatalf("sheet[%d] = %q, want %q (all=%v)", i, sheets[i], w, sheets)
		}
	}
	summaryCount := 0
	for _, s := range sheets {
		if s == "ReportSummary" {
			summaryCount++
		}
	}
	if summaryCount != 1 {
		t.Fatalf("expected 1 ReportSummary sheet, got %d", summaryCount)
	}
	if b6, err := book.GetCellValue("ReportSummary", "B6"); err != nil || b6 != "None_Lump" {
		t.Fatalf("ReportSummary B6 = %q, %v; want None_Lump", b6, err)
	}

	// Still enforces Excel 16,000-plot safety bound.
	preview.Report.Units[0].NumPlots = 16001
	if _, err := prepareLongVegetationWorkbook(context.Background(), preview, vegetationWorkbookLayout{}); err == nil {
		t.Fatal("expected error when NumPlots exceeds 16000")
	}
}

func TestLongVegetationLumpTableAndCombineVariantsPreviewAndWorkbook(t *testing.T) {
	service, state := vegetationWorkbookServiceFixture(t, false)
	owner := service.contexts.Projects.Sqlite
	mutate := func(role, stmt string) {
		t.Helper()
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(owner.Attachments[role], "rw"))
		if err != nil {
			t.Fatal(err)
		}
		_, err = db.Exec(stmt)
		if err = errors.Join(err, db.Close()); err != nil {
			t.Fatal(err)
		}
	}

	// Seed clean species rows and Sample_Veg rows in plot '108050' (which belongs to Sample/Report_SU).
	mutate("VLists", `DELETE FROM USysAllSpecs WHERE Code IN ('TSUGHET', 'PSEUMEN', 'PSEUMEN2');
		INSERT INTO USysAllSpecs(ID, Code, ScientificName, EnglishName, Lifeform, Codetype)
		VALUES (90001, 'TSUGHET', 'Tsuga heterophylla', 'western hemlock', 1, 'U'),
		       (90002, 'PSEUMEN', 'Pseudotsuga menziesii', 'Douglas-fir', 1, 'U'),
		       (90003, 'PSEUMEN2', 'Pseudotsuga menziesii var. glauca', 'interior Douglas-fir', 1, 'U')`)
	mutate("project", `DELETE FROM Sample_Veg WHERE PlotNumber = '108050';
		INSERT INTO Sample_Veg(PlotNumber, ID, Species, Cover1) VALUES
			('108050', 9101, 'PSEUMEN', 60),
			('108050', 9102, 'TSUGHET', 55),
			('108050', 9103, 'PSEUMEN2', 12);
		CREATE TABLE Regional_Lump(LumpCode TEXT, SppCode TEXT, "Use" INTEGER);
		INSERT INTO Regional_Lump(LumpCode, SppCode, "Use") VALUES
			('PSEUMEN', 'TSUGHET', -1),
			('IGNORED', 'PSEUMEN2', 0);`)

	// 1. Project *_Lump via Current.CurrLump -> sums PSEUMEN(60)+TSUGHET(55)=115 capped at 99, while PSEUMEN2 stays separate (12).
	if err := service.contexts.Projects.Preferences.Update("Current", map[string]any{"CurrLump": "Regional_Lump"}); err != nil {
		t.Fatal(err)
	}
	preview, err := PreviewLongVegetation(service.contexts, context.Background(), state.ContextID)
	if err != nil {
		t.Fatalf("PreviewLongVegetation with CurrLump failed: %v", err)
	}
	if preview.Settings.LumpTable != "Regional_Lump" {
		t.Fatalf("Settings.LumpTable = %q, want Regional_Lump", preview.Settings.LumpTable)
	}
	coversBySci := map[string]float64{}
	var quotedUnit *LongVegetationUnit
	for i := range preview.Report.Units {
		u := &preview.Report.Units[i]
		if u.Code.Text != nil && *u.Code.Text == "  Unit 'quoted'  " {
			quotedUnit = u
			break
		}
	}
	if quotedUnit == nil {
		t.Fatalf("missing quoted unit in %+v", preview.Report.Units)
	}
	for _, r := range quotedUnit.Rows {
		if r.Species.Text != nil && r.Plots[0].Cover != nil {
			coversBySci[*r.Species.Text] = *r.Plots[0].Cover
		}
	}
	if coversBySci["Pseudotsuga menziesii"] != 99 {
		t.Fatalf("lumped Pseudotsuga cover = %v, want 99 (60+55 capped at 99); map=%v", coversBySci["Pseudotsuga menziesii"], coversBySci)
	}
	if coversBySci["Pseudotsuga menziesii var. glauca"] != 12 {
		t.Fatalf("un-lumped variant cover = %v, want 12; map=%v", coversBySci["Pseudotsuga menziesii var. glauca"], coversBySci)
	}

	review, err := service.GetReview(context.Background(), state.ContextID, `{"scope":"unlumped"}`)
	if err != nil {
		t.Fatalf("GetReview with CurrLump failed: %v", err)
	}
	dest1 := filepath.Join(t.TempDir(), "lumped.xlsx")
	if out, err := service.ExportReviewed(context.Background(), state.ContextID,
		vprotest.WorkbookRequest(t, vegetationWorkbookExportRequest{"unlumped", review.CreatedDate, review.ApprovalHash, dest1})); err != nil || out.Status != "published" {
		t.Fatalf("ExportReviewed lumped failed: out=%+v err=%v", out, err)
	}
	book1, err := excelize.OpenFile(dest1)
	if err != nil {
		t.Fatal(err)
	}
	var unitSheet string
	for _, s := range review.Sheets {
		if s.Unit.Text != nil && *s.Unit.Text == "  Unit 'quoted'  " {
			unitSheet = s.Name
			break
		}
	}
	if unitSheet == "" {
		t.Fatalf("missing sheet for quoted unit in %+v", review.Sheets)
	}
	if a3, err := book1.GetCellValue(unitSheet, "A3"); err != nil || a3 != "Vegetation was lumped using Regional_Lump table" {
		t.Fatalf("%s A3 = %q, %v", unitSheet, a3, err)
	}
	if b6, err := book1.GetCellValue("ReportSummary", "B6"); err != nil || b6 != "Regional_Lump" {
		t.Fatalf("ReportSummary B6 = %q, %v", b6, err)
	}
	if a15, err := book1.GetCellValue("ReportSummary", "A15"); err != nil || a15 != "PSEUMEN" {
		t.Fatalf("ReportSummary A15 = %q, %v", a15, err)
	}
	if b15, err := book1.GetCellValue("ReportSummary", "B15"); err != nil || b15 != "TSUGHET" {
		t.Fatalf("ReportSummary B15 = %q, %v", b15, err)
	}

	// 2. Clear CurrLump and test explicit workbook scope "lump:Regional" AND LVUseSppCodesOnly = -1.
	if err := service.contexts.Projects.Preferences.Update("Current", map[string]any{"CurrLump": ""}); err != nil {
		t.Fatal(err)
	}
	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{"LVUseSppCodesOnly": -1}); err != nil {
		t.Fatal(err)
	}
	review2, err := service.GetReview(context.Background(), state.ContextID, `{"scope":"lump:Regional"}`)
	if err != nil {
		t.Fatalf("GetReview lump:Regional + LVUseSppCodesOnly failed: %v", err)
	}
	if !review2.Preview.Settings.CombineVariants || review2.Preview.Settings.LumpTable != "CombinedSpp_Lump" {
		t.Fatalf("expected CombineVariants=true and CombinedSpp_Lump, got %+v", review2.Preview.Settings)
	}
	var quoted2 *LongVegetationUnit
	for i := range review2.Preview.Report.Units {
		u := &review2.Preview.Report.Units[i]
		if u.Code.Text != nil && *u.Code.Text == "  Unit 'quoted'  " {
			quoted2 = u
			break
		}
	}
	if quoted2 == nil {
		t.Fatalf("expected quoted unit in lump:Regional review")
	}
	nonNilCount := 0
	var combinedRow LongVegetationRow
	for _, row := range quoted2.Rows {
		for _, cell := range row.Plots {
			if cell.Cover != nil {
				nonNilCount++
				combinedRow = row
			}
		}
	}
	if nonNilCount != 1 || combinedRow.Species.Text == nil || *combinedRow.Species.Text != "Pseudotsuga menziesii" || combinedRow.Plots[0].Cover == nil || *combinedRow.Plots[0].Cover != 99 {
		t.Fatalf("expected all 3 rows in quoted unit combined into 1 non-nil Pseudotsuga menziesii row capped at 99, got nonNil=%d species=%v cover=%v", nonNilCount, combinedRow.Species.Text, combinedRow.Plots[0].Cover)
	}
}
