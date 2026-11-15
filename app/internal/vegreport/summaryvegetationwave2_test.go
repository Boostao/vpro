package vegreport

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/xuri/excelize/v2"
)

func wave2SummaryWorkbookService(t *testing.T, service *SummaryVegetationService) *SummaryVegetationWorkbookService {
	t.Helper()
	envSvc, err := NewSummaryVegetationEnvironmentalService(service)
	if err != nil {
		t.Fatal(err)
	}
	elSvc, err := NewSummaryVegetationEnvironmentalLifeformService(envSvc)
	if err != nil {
		t.Fatal(err)
	}
	wbSvc, err := NewSummaryVegetationWorkbookService(elSvc)
	if err != nil {
		t.Fatal(err)
	}
	return wbSvc
}

func TestSummaryVegetationWave2QualityFilterEnforceAndReasons(t *testing.T) {
	service, state := summaryVegetationServiceFixture(t, false)
	owner := service.contexts.Projects.Sqlite
	vprotest.MutateContextFixture(t, owner.Attachments["VLists"], `DELETE FROM USysTableOfLists WHERE ListName IN ('DataQuality', 'OtherList', 'BEC_Use');
		INSERT INTO USysTableOfLists(ListName, ItemOrder, Item) VALUES
			('DataQuality', 1, 'Poor'),
			('DataQuality', 2, 'Fair'),
			('DataQuality', 3, 'Good'),
			('DataQuality', 4, 'Excellent'),
			('OtherList', 99, 'GoodForOtherOnly')`)
	vprotest.MutateContextFixture(t, owner.Attachments["su"], `DELETE FROM Report_SU;
		INSERT INTO Report_SU VALUES
			('P1', 'Unit1'),
			('P2', 'Unit1'),
			('P3', 'Unit1'),
			('P4', 'Unit1'),
			('P5', 'Unit1'),
			('P6', 'Unit1'),
			('P7', 'Unit1')`)
	vprotest.MutateContextFixture(t, owner.Attachments["project"], `
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Veg")+`;
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`;
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Admin")+`;
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Veg")+`(PlotNumber, Species, Cover1) VALUES
			('P1', 'X', 10), ('P2', 'X', 20), ('P3', 'X', 30), ('P4', 'X', 40), ('P5', 'X', 50), ('P6', 'X', 60);
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`(PlotNumber) VALUES
			('P1'), ('P2'), ('P3'), ('P4'), ('P5'), ('P6');
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Admin")+`(Plot, SitePlotQuality, VegPlotQuality, SoilPlotQuality, BEC_Use) VALUES
			('P1', 'Good', 'Fair', 'Fair', 'Yes'),
			('P2', 'UnlistedLabel', 'Fair', NULL, 'yes'),
			('P3', 'GoodForOtherOnly', 'Fair', 'Fair', 'Yes'),
			('P4', 'Poor', 'Poor', 'Fair', 'Yes'),
			('P5', 'Good', 'Fair', 'Fair', 'Archive'),
			('P6', 'Poor', 'Fair', 'Fair', 'Archive')`)

	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{
		"DataQualityFilterEnforce":  true,
		"DataQualityFilterSite":     "Fair",
		"DataQualityFilterVeg":      "Fair",
		"DataQualityFilterSoil":     "Fair",
		"DataQualityFilterBECUseLV": "moderate",
		"DataQualityFilterSiteNull": true,
		"DataQualityFilterVegNull":  false,
		"DataQualityFilterSoilNull": true,
		"DataQualityFilterBECUse":   false,
	}); err != nil {
		t.Fatal(err)
	}

	preview, err := service.Preview(context.Background(), state.ContextID, 1, 6)
	if err != nil {
		t.Fatalf("QC-enforced preview failed: %v", err)
	}
	if preview.Quality == nil || !preview.Quality.Enforced || preview.Quality.TotalBefore != 7 || preview.Quality.Retained != 2 || preview.Quality.RemovedCount != 5 {
		t.Fatalf("unexpected QC filter summary: %+v", preview.Quality)
	}

	removedByPlot := map[string]SummaryVegetationQualityRemovedPlot{}
	for _, r := range preview.Quality.Removed {
		removedByPlot[r.PlotNumber] = r
	}
	// P3: GoodForOtherOnly belongs to OtherList -> excluded; P4: Site+Veg failed -> Mixed; P5: BEC Archive < moderate -> BEC;
	// P6: Site+BEC -> Mixed; P7: missing Env/Admin -> Project.
	if removedByPlot["P3"].RemovedBy != "Site" ||
		removedByPlot["P4"].RemovedBy != "Mixed" ||
		removedByPlot["P5"].RemovedBy != "BEC" ||
		removedByPlot["P6"].RemovedBy != "Mixed" ||
		removedByPlot["P7"].RemovedBy != "Project" {
		t.Fatalf("unexpected QC removal causes: %+v", removedByPlot)
	}

	// Verify QualityPrefsService unlocks DataQualityFilterEnforce toggling and Workbook exports under Enforce=true.
	qualSvc := NewSummaryVegetationQualityPreferencesService(service.contexts)
	qualReview, err := qualSvc.GetSummaryVegetationQualityPreferences(context.Background(), state.ContextID)
	if err != nil || !qualReview.Values.Enforce {
		t.Fatalf("expected Enforce=true in quality review, got %+v err=%v", qualReview, err)
	}
	wbSvc := wave2SummaryWorkbookService(t, service)
	wbOpts := SummaryVegetationWorkbookOptions{Average: 1, Display: 6}
	rawOpts, _ := json.Marshal(wbOpts)
	review, err := wbSvc.GetReview(context.Background(), state.ContextID, string(rawOpts))
	if err != nil || review.Preview.Quality == nil || review.Preview.Quality.Retained != 2 {
		t.Fatalf("expected QC-enforced workbook review to succeed with 2 retained plots, got err=%v review=%+v", err, review)
	}
	dest := filepath.Join(t.TempDir(), "qc_enforced.xlsx")
	expReq, _ := json.Marshal(map[string]any{
		"options":      wbOpts,
		"approvalHash": review.ApprovalHash,
		"destination":  dest,
	})
	outcome, err := wbSvc.ExportReviewed(context.Background(), state.ContextID, string(expReq))
	if err != nil || outcome == nil || outcome.Status != "published" {
		t.Fatalf("QC-enforced workbook export failed: outcome=%+v err=%v", outcome, err)
	}
}

func TestSummaryVegetationWave2UnitScopesAndHierarchyHeaderWorkbook(t *testing.T) {
	service, state := summaryVegetationServiceFixture(t, false)
	owner := service.contexts.Projects.Sqlite
	vprotest.MutateContextFixture(t, owner.Attachments["project"], `
		CREATE TABLE IF NOT EXISTS `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Hierarchy")+`(
			ID INTEGER PRIMARY KEY, Name TEXT, Parent INTEGER, MyOrder REAL, ChildID INTEGER, StartChild INTEGER, LastChild INTEGER, Flag INTEGER, Tag TEXT
		);
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Hierarchy")+`;
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Hierarchy")+`(ID, Name, Parent, MyOrder) VALUES
			(1, 'ForestGroup', 0, 1),
			(2, '~Subalpine', 1, 1),
			(3, 'A', 2, 1),
			(4, 'B', 2, 2);
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`;
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`(PlotNumber, Zone, SiteSeries) VALUES
			('P1', 'ESSF', 'A'),
			('P2', 'ESSF', 'A'),
			('P3', 'IDF', 'B');`)
	vprotest.MutateContextFixture(t, owner.Attachments["su"], `DELETE FROM Report_SU;
		INSERT INTO Report_SU VALUES('P1', 'A'), ('P2', 'A'), ('P3', 'B')`)

	// 1. Dynamic hierarchy ('~') scope + hierarchy headers in preview and Row 3 of workbook.
	prevSvc := NewSummaryVegetationPresentationPreferencesService(service.contexts)
	presReview, err := prevSvc.GetSummaryVegetationPresentationPreferences(context.Background(), state.ContextID)
	if err != nil {
		t.Fatal(err)
	}
	proposed := presReview.Values
	proposed.HierarchyHeader = true
	saveReq, _ := json.Marshal(map[string]any{"expected": presReview.Values, "proposed": proposed, "constancyApplied": false})
	saveOut := prevSvc.SaveSummaryVegetationPresentationPreferences(context.Background(), state.ContextID, string(saveReq))
	if !saveOut.Committed {
		t.Fatalf("unlocking SVShowHierarchyHeader failed: %+v", saveOut)
	}

	hierPrev, err := service.PreviewConfigured(context.Background(), state.ContextID, `{"unitScope":"hierarchy","hierarchyHeader":true,"breakpointPolicy":"lowest"}`)
	if err != nil {
		t.Fatalf("hierarchy breakpoint preview failed: %v", err)
	}
	if len(hierPrev.Units) != 1 || hierPrev.Units[0].Code != "Subalpine" ||
		hierPrev.Units[0].HierarchyHeader == nil || *hierPrev.Units[0].HierarchyHeader != "ForestGroup" {
		t.Fatalf("unexpected hierarchy unit/header resolution: %+v", hierPrev.Units)
	}

	wbSvc := wave2SummaryWorkbookService(t, service)
	hh := true
	wbOpts := SummaryVegetationWorkbookOptions{Average: 1, Display: 6, UnitScope: "hierarchy", HierarchyHeader: &hh}
	rawOpts, _ := json.Marshal(wbOpts)
	review, err := wbSvc.GetReview(context.Background(), state.ContextID, string(rawOpts))
	if err != nil {
		t.Fatalf("hierarchy header workbook review failed: %v", err)
	}
	dest := filepath.Join(t.TempDir(), "hier_header.xlsx")
	expReq, _ := json.Marshal(map[string]any{"options": wbOpts, "approvalHash": review.ApprovalHash, "destination": dest})
	if out, err := wbSvc.ExportReviewed(context.Background(), state.ContextID, string(expReq)); err != nil || out.Status != "published" {
		t.Fatalf("hierarchy header workbook export failed: out=%+v err=%v", out, err)
	}
	book, err := excelize.OpenFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = book.Close() }()
	hCell, err := book.GetCellValue(review.Sheet, "D3")
	if err != nil || hCell != "ForestGroup" {
		t.Fatalf("expected hierarchy group header 'ForestGroup' in %s!D3, got %q err=%v", review.Sheet, hCell, err)
	}

	// 2. Whole-project ("none") scope via PreviewConfigured.
	nonePrev, err := service.PreviewConfigured(context.Background(), state.ContextID, `{"unitScope":"none"}`)
	if err != nil || len(nonePrev.Units) != 1 || nonePrev.Units[0].Code != "All Plots" || nonePrev.Units[0].NumPlots != 3 {
		t.Fatalf("unexpected whole-project 'none' scope result: units=%+v err=%v", nonePrev.Units, err)
	}

	// 3. Field-derived ("field") grouping on Env.Zone.
	fieldPrev, err := service.PreviewConfigured(context.Background(), state.ContextID, `{"unitScope":"field","unitField":"Zone"}`)
	if err != nil || len(fieldPrev.Units) != 2 || fieldPrev.Units[0].Code != "ESSF" || fieldPrev.Units[1].Code != "IDF" {
		t.Fatalf("unexpected field-derived scope result: units=%+v err=%v", fieldPrev.Units, err)
	}

	// 4. USysSuTableDynamic selection via SwitchContext + '~' hierarchy breakpoints.
	vprotest.MutateContextFixture(t, owner.Attachments["su"], `CREATE TABLE IF NOT EXISTS USysSuTableDynamic_SU(PlotNumber TEXT, SiteUnit TEXT);
		DELETE FROM USysSuTableDynamic_SU;
		INSERT INTO USysSuTableDynamic_SU VALUES('P1', 'A'), ('P2', 'A'), ('P3', 'B')`)
	sel := vprotest.ContextSelection(state)
	sel.SU = "USysSuTableDynamic"
	dynState, err := service.contexts.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatal(err)
	}
	dynPrev, err := service.Preview(context.Background(), dynState.ContextID, 1, 6)
	if err != nil || dynPrev.UnitScope != "hierarchy" || len(dynPrev.Units) != 1 || dynPrev.Units[0].Code != "Subalpine" {
		t.Fatalf("expected USysSuTableDynamic preview to resolve '~' Subalpine unit, got %+v err=%v", dynPrev.Units, err)
	}
}

func TestSummaryVegetationWave2VariantsLumpGoldstreamAndPreferenceSync(t *testing.T) {
	service, state := summaryVegetationServiceFixture(t, false)
	owner := service.contexts.Projects.Sqlite
	vprotest.MutateContextFixture(t, owner.Attachments["VLists"], `DELETE FROM USysAllSpecs;
		INSERT INTO USysAllSpecs(Code, ScientificName, Lifeform, EnglishName, Codetype) VALUES
			('FD', 'Pseudotsuga menziesii', 1, 'Douglas-fir', 'U'),
			('FD1', 'Pseudotsuga menziesii var. menziesii', 1, 'Coast Douglas-fir', 'U'),
			('HW', 'Tsuga heterophylla', 1, 'Western hemlock', 'U')`)
	vprotest.MutateContextFixture(t, owner.Attachments["su"], `DELETE FROM Report_SU;
		INSERT INTO Report_SU VALUES('P1', 'UnitA')`)
	vprotest.MutateContextFixture(t, owner.Attachments["project"], `
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Veg")+`;
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Veg")+`(PlotNumber, Species, Cover1) VALUES
			('P1', 'FD', 60),
			('P1', 'FD1', 50),
			('P1', 'HW', 10);
		CREATE TABLE IF NOT EXISTS Custom_Lump(LumpCode TEXT, SppCode TEXT, "Use" INTEGER);
		DELETE FROM Custom_Lump;
		INSERT INTO Custom_Lump(LumpCode, SppCode, "Use") VALUES('FD', 'HW', -1);`)

	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{
		"SVSubSppAsSpp":         true,
		"SVGroupBy":             1,
		"SVAvgType":             1,
		"SVValue":               6,
		"SVShowClass":           1,
		"SVCreateSummary":       true,
		"SVShowHierarchyHeader": false,
	}); err != nil {
		t.Fatal(err)
	}
	if err := service.contexts.Projects.Preferences.Update("Current", map[string]any{
		"CurrLump": "Custom",
	}); err != nil {
		t.Fatal(err)
	}

	// Verify PreviewWithPreferences combines FD + FD1 (variant '1') + HW (lumped to FD) -> single FD row capped at 99%.
	prefPrev, err := service.PreviewWithPreferences(context.Background(), state.ContextID)
	if err != nil {
		t.Fatalf("PreviewWithPreferences failed: %v", err)
	}
	if !prefPrev.CombineVariants || prefPrev.LumpTable != "CombinedSpp_Lump" || len(prefPrev.Rows) != 1 ||
		prefPrev.Rows[0].Species.Text == nil || *prefPrev.Rows[0].Species.Text != "Pseudotsuga menziesii" {
		t.Fatalf("expected 1 lumped+variant-combined Pseudotsuga menziesii row, got lump=%q combine=%v rows=%+v",
			prefPrev.LumpTable, prefPrev.CombineVariants, prefPrev.Rows)
	}
	if prefPrev.Rows[0].Witnesses[0].Cover.Real == nil || *prefPrev.Rows[0].Witnesses[0].Cover.Real != 99 {
		t.Fatalf("expected summed cover capped at 99, got cover=%+v cell=%+v", prefPrev.Rows[0].Witnesses[0].Cover, prefPrev.Rows[0].Covers[0])
	}

	// Verify explicit Custom_Lump (without SVSubSppAsSpp) sets ReportSummary!B6 = Custom_Lump and merges HW into FD (60+10=70).
	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{"SVSubSppAsSpp": false}); err != nil {
		t.Fatal(err)
	}
	lumpOnlyPrev, err := service.PreviewWithPreferences(context.Background(), state.ContextID)
	if err != nil || lumpOnlyPrev.LumpTable != "Custom_Lump" || len(lumpOnlyPrev.Rows) != 2 {
		t.Fatalf("expected 2 rows (FD lumped=70, FD1=50) with LumpTable=Custom_Lump, got lump=%q rows=%+v err=%v",
			lumpOnlyPrev.LumpTable, lumpOnlyPrev.Rows, err)
	}

	// Verify GetReviewFromPreferences stays synchronized with PreviewWithPreferences and records ReportSummary!B6 = Custom_Lump.
	wbSvc := wave2SummaryWorkbookService(t, service)
	wbReview, err := wbSvc.GetReviewFromPreferences(context.Background(), state.ContextID)
	if err != nil {
		t.Fatalf("GetReviewFromPreferences failed: %v", err)
	}
	if len(wbReview.Preview.Rows) != len(lumpOnlyPrev.Rows) || wbReview.Preview.LumpTable != lumpOnlyPrev.LumpTable {
		t.Fatalf("workbook GetReviewFromPreferences drifted from PreviewWithPreferences")
	}
	dest := filepath.Join(t.TempDir(), "synced_lump.xlsx")
	rawOpts, _ := json.Marshal(wbReview.Options)
	var optsMap any
	_ = json.Unmarshal(rawOpts, &optsMap)
	expReq, _ := json.Marshal(map[string]any{
		"options":      optsMap,
		"createdAt":    wbReview.Ancillary.CreatedAt,
		"approvalHash": wbReview.ApprovalHash,
		"destination":  dest,
	})
	if out, err := wbSvc.ExportReviewed(context.Background(), state.ContextID, string(expReq)); err != nil || out.Status != "published" {
		t.Fatalf("synced workbook export failed: out=%+v err=%v", out, err)
	}
	rawBytes, err := excelize.OpenFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = rawBytes.Close() }()
	b6, err := rawBytes.GetCellValue("ReportSummary", "B6")
	if err != nil || b6 != "Custom_Lump" {
		t.Fatalf("expected ReportSummary!B6 = 'Custom_Lump', got %q err=%v", b6, err)
	}

	// Verify Goldstream score/class metadata calculation (display=5 class or IncludeGoldstreamMetadata: true).
	goldPrev, err := service.PreviewConfigured(context.Background(), state.ContextID, `{"useSavedPreferences":true,"combineVariants":true,"display":5,"showClass":1,"includeGoldstreamMetadata":true}`)
	if err != nil {
		t.Fatalf("Goldstream metadata preview failed: %v", err)
	}
	// presence=1.0, meanCover=99 -> score = 100 * sqrt(99) ~= 994.987 >= 500 -> Goldstream class 6.
	if goldPrev.Goldstream == nil || len(goldPrev.Goldstream.Rows) != 1 || len(goldPrev.Goldstream.Rows[0].Cells) != 1 {
		t.Fatalf("expected 1 Goldstream metadata row/cell, got %+v", goldPrev.Goldstream)
	}
	cell := goldPrev.Goldstream.Rows[0].Cells[0]
	if cell.Class == nil || *cell.Class != 6 || cell.Score == nil || *cell.Score < 994 || *cell.Score > 996 {
		t.Fatalf("unexpected Goldstream cell score/class: %+v", cell)
	}
}
