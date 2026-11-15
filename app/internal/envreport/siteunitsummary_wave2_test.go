package envreport

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/xuri/excelize/v2"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func fullSummaryPreferenceRequest(t *testing.T, expected, proposed SiteUnitSummaryFullPreferenceValues) string {
	t.Helper()
	data, err := json.Marshal(SiteUnitSummaryFullPreferencesRequest{Expected: expected, Proposed: proposed})
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestSiteUnitSummaryHierarchyBreakpointsAndFieldDerivedS514AndS517(t *testing.T) {
	service, state := vprotest.ReportServiceFixture(t, false)

	// Setup multi-plot dataset with ascending/descending code separation ('Alpha' vs 'Zeta')
	// and '~' hierarchy breakpoints in Sample_Hierarchy.
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw")+"&_busy_timeout=5000")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		DELETE FROM Report_SU;
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, SiteSeries) VALUES
			('W2A', 'AAA', '01', '01'),
			('W2Z', 'ZZZ', '09', '02');
		INSERT INTO Sample_Admin (Plot) VALUES ('W2A'), ('W2Z');
		INSERT INTO Report_SU (PlotNumber, SiteUnit) VALUES
			('W2Z', 'LeafZ'),
			('W2A', 'LeafA');
		DELETE FROM Sample_Hierarchy;
		INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level) VALUES
			(1, 'Root', 0, 0),
			(2, '~BP_Zeta', 1, 1),
			(3, 'LeafZ', 2, 2),
			(4, '~BP_Alpha', 1, 1),
			(5, 'LeafA', 4, 2);
	`); err != nil {
		_ = db.Close()
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	// Verify SESuType = 2 ('~' hierarchy breakpoints) via preview + workbook service + ascending tabs (S5.17)
	if err := service.Projects.Preferences.Update("ReportOptions", map[string]any{"SESuType": 2, "SEOrderBy": 1}); err != nil {
		t.Fatal(err)
	}
	preview, err := PreviewSiteUnitSummary(service, context.Background(), state.ContextID, SiteUnitSummaryRequest{1})
	if err != nil {
		t.Fatalf("SESuType=2 preview failed: %v", err)
	}
	if preview.Report.QuerySource != string(siteUnitDetailHierarchyBreakpoints) {
		t.Fatalf("expected hierarchy breakpoints query source, got %q", preview.Report.QuerySource)
	}
	if len(preview.Report.Units) != 2 || preview.Report.Units[0].Code != "BP_Zeta" || preview.Report.Units[1].Code != "BP_Alpha" {
		t.Fatalf("expected BP_Zeta & BP_Alpha units (descending report order), got %+v", preview.Report.Units)
	}

	wbService, err := NewSiteUnitSummaryWorkbookService(service)
	if err != nil {
		t.Fatal(err)
	}
	review, err := wbService.GetReview(context.Background(), state.ContextID, `{"method":1}`)
	if err != nil {
		t.Fatalf("SESuType=2 workbook GetReview failed: %v", err)
	}
	wantTabs := []string{"BP_Alpha", "BP_Zeta"}
	if len(review.Sheets) != 2 || review.Sheets[0].Name != wantTabs[0] || review.Sheets[1].Name != wantTabs[1] {
		t.Fatalf("expected ascending review sheets %v, got %+v", wantTabs, review.Sheets)
	}
	dest := filepath.Join(t.TempDir(), "breakpoints.xlsx")
	out, err := wbService.ExportReviewed(context.Background(), state.ContextID, summaryWorkbookExportJSON(t, 1, review.ApprovalHash, dest))
	if err != nil || out.Status == "" {
		t.Fatalf("ExportReviewed failed: out=%+v err=%v", out, err)
	}
	xl, err := excelize.OpenFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	gotTabs := xl.GetSheetList()
	_ = xl.Close()
	if !reflect.DeepEqual(gotTabs, []string{"BP_Alpha", "BP_Zeta", "_VPRO_Source"}) {
		t.Fatalf("expected ascending Excel tabs [BP_Alpha BP_Zeta _VPRO_Source], got %v", gotTabs)
	}

	// Verify SESuType = 3 (field-derived grouping Zone+SubZone+SiteSeries) works even with SU == "None"
	if err := service.Projects.Preferences.Update("ReportOptions", map[string]any{"SESuType": 3}); err != nil {
		t.Fatal(err)
	}
	noneSel := vprotest.ContextSelection(state)
	noneSel.SU, noneSel.SUPath = "None", ""
	noneState, err := service.SwitchContext(state.ContextID, noneSel)
	if err != nil {
		t.Fatal(err)
	}
	fieldPreview, err := PreviewSiteUnitSummary(service, context.Background(), noneState.ContextID, SiteUnitSummaryRequest{1})
	if err != nil {
		t.Fatalf("SESuType=3 preview with SU=None failed: %v", err)
	}
	if fieldPreview.Report.QuerySource != string(siteUnitDetailFieldDerived) {
		t.Fatalf("expected field-derived query source, got %q", fieldPreview.Report.QuerySource)
	}
	foundAAA, foundZZZ := false, false
	for _, u := range fieldPreview.Report.Units {
		if u.Code == "AAA0101" {
			foundAAA = true
		}
		if u.Code == "ZZZ0902" {
			foundZZZ = true
		}
	}
	if !foundAAA || !foundZZZ {
		t.Fatalf("expected Zone+SubZone+SiteSeries derived units AAA0101 & ZZZ0902, got %+v", fieldPreview.Report.Units)
	}

	// Verify hierarchy without '~' breakpoints fails explicitly
	vprotest.MutateContextFixture(t, state.ProjectPath, `DELETE FROM Sample_Hierarchy; INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level) VALUES (1, 'NoBreak', 0, 0)`)
	if err := service.Projects.Preferences.Update("ReportOptions", map[string]any{"SESuType": 2}); err != nil {
		t.Fatal(err)
	}
	if _, err := PreviewSiteUnitSummary(service, context.Background(), state.ContextID, SiteUnitSummaryRequest{1}); err == nil {
		t.Fatal("expected error when active hierarchy has no '~' breakpoints")
	}
}

func TestSiteUnitSpeciesStrataOrderBy3ViaLayerCodeS515(t *testing.T) {
	service, state := vprotest.ReportServiceFixture(t, false)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Report_SU;
		DELETE FROM Sample_Veg WHERE PlotNumber = 'W3P1';
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, SiteSeries) VALUES ('W3P1', 'CWH', 'vm1', '01');
		INSERT INTO Sample_Admin (Plot) VALUES ('W3P1');
		INSERT INTO Report_SU (PlotNumber, SiteUnit) VALUES ('W3P1', 'StrataUnit');
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover1, Cover2, Cover6) VALUES ('W3P1', 9001, 'ABIEAMA', 60, 60, 15);
	`)

	input, err := ReadSiteUnitQuickVegetationInput(service, context.Background(), state.ContextID, 1, vprocore.PublicationReadSnapshotHooks{})
	if err != nil {
		t.Fatal(err)
	}
	if len(input.Tables) != 7 || len(input.LayerCode.Rows) == 0 {
		t.Fatalf("expected 7 core tables plus LayerCode table, got tables=%d layerCodeRows=%d", len(input.Tables), len(input.LayerCode.Rows))
	}

	speciesPreview, err := PreviewSiteUnitSummarySpecies(service, context.Background(), state.ContextID, SiteUnitSpeciesListRequest{
		Method: 1, OrderBy: 3, CoverCalculation: 1, AndOr: 1, PresenceGreaterThan: 0, CoverGreaterThan: 0,
	})
	if err != nil {
		t.Fatalf("OrderBy=3 PreviewSiteUnitSummarySpecies failed: %v", err)
	}
	if len(speciesPreview.Environment.Report.Fields) != 39 {
		t.Fatalf("expected 39 standard Env fields for OrderBy=3, got %d", len(speciesPreview.Environment.Report.Fields))
	}
	if len(speciesPreview.Units) != 1 || len(speciesPreview.Units[0].Groups) != 2 {
		t.Fatalf("expected 2 strata groups (Strata A & Strata C), got %+v", speciesPreview.Units)
	}
	g0, g1 := speciesPreview.Units[0].Groups[0], speciesPreview.Units[0].Groups[1]
	if g0.Caption != "Strata A" || g0.Rows[0].Species != "ABIEAMA" || g0.Rows[0].Cover != "99.00" || g0.Rows[0].Presence != "100.0" {
		t.Fatalf("expected Strata A ABIEAMA capped at 99.00 & presence 100.0, got %+v", g0)
	}
	if g1.Caption != "Strata C" || g1.Rows[0].Species != "ABIEAMA" || g1.Rows[0].Cover != "15.00" {
		t.Fatalf("expected Strata C ABIEAMA cover 15.00, got %+v", g1)
	}

	extSvc, err := NewSiteUnitSummaryExtendedWorkbookService(service)
	if err != nil {
		t.Fatal(err)
	}
	extReq := SiteUnitSummaryExtendedWorkbookOptions{
		Method: 1, OrderBy: 3, IncludeSpecies: 1, CoverCalculation: 1, AndOr: 1, PresenceGreaterThan: 0, CoverGreaterThan: 0,
	}
	extRaw, err := json.Marshal(extReq)
	if err != nil {
		t.Fatal(err)
	}
	review, err := extSvc.GetReview(context.Background(), state.ContextID, string(extRaw))
	if err != nil {
		t.Fatalf("ExtendedWorkbookService OrderBy=3 GetReview failed: %v", err)
	}
	exportDest := filepath.Join(t.TempDir(), "strata_extended.xlsx")
	exportRaw, err := json.Marshal(struct {
		Method              int    `json:"method"`
		OrderBy             int    `json:"orderBy"`
		IncludeSpecies      int    `json:"includeSpecies"`
		CoverCalculation    int    `json:"coverCalculation"`
		AndOr               int    `json:"andOr"`
		PresenceGreaterThan int    `json:"presenceGreaterThan"`
		CoverGreaterThan    int    `json:"coverGreaterThan"`
		ApprovalHash        string `json:"approvalHash"`
		Destination         string `json:"destination"`
	}{1, 3, 1, 1, 1, 0, 0, review.ApprovalHash, exportDest})
	if err != nil {
		t.Fatal(err)
	}
	if out, err := extSvc.ExportReviewed(context.Background(), state.ContextID, string(exportRaw)); err != nil || out == nil {
		t.Fatalf("ExtendedWorkbookService OrderBy=3 ExportReviewed failed: out=%+v err=%v", out, err)
	}
	xl, err := excelize.OpenFile(exportDest)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = xl.Close() }()
	sheet := review.Sheets[0].Name
	if val, err := xl.GetCellValue(sheet, "A5"); err != nil || val != "Strata A" {
		t.Fatalf("expected Strata A group header in A5, got %q (err=%v)", val, err)
	}
	styleID, err := xl.GetCellStyle(sheet, "A5")
	if err != nil {
		t.Fatal(err)
	}
	style, err := xl.GetStyle(styleID)
	if err != nil || style.Font == nil || !style.Font.Bold {
		t.Fatalf("expected bold font style on Strata A header, got %+v err=%v", style, err)
	}
}

func TestSiteUnitSummaryFullPreferencesCASAndBoundsS516(t *testing.T) {
	contexts, state := vprotest.ReportServiceFixture(t, false)
	svc := NewSiteUnitSummaryPreferencesService(contexts)

	got, err := svc.GetFullSiteUnitSummaryPreferences(context.Background(), state.ContextID)
	if err != nil {
		t.Fatalf("GetFullSiteUnitSummaryPreferences failed: %v", err)
	}
	expected := got.Values
	proposed := SiteUnitSummaryFullPreferenceValues{
		Method:              2,
		SiteUnitType:        3,
		IncludeSpecies:      1,
		OrderBy:             3,
		CoverCalculation:    2,
		AndOr:               2,
		PresenceGreaterThan: 20,
		CoverGreaterThan:    5,
	}

	// Verify no-op leaves config.yml untouched byte-for-byte
	rawBefore, err := os.ReadFile(contexts.Projects.Preferences.Path)
	if err != nil {
		t.Fatal(err)
	}
	noop := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), state.ContextID, fullSummaryPreferenceRequest(t, expected, expected))
	rawAfterNoop, err := os.ReadFile(contexts.Projects.Preferences.Path)
	if err != nil || noop.Changed || noop.Committed || noop.ErrorMessage != "" || !bytes.Equal(rawBefore, rawAfterNoop) {
		t.Fatalf("full preference no-op rewrote file: %+v err=%v", noop, err)
	}

	// Save full updated preferences
	saved := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), state.ContextID, fullSummaryPreferenceRequest(t, expected, proposed))
	if !saved.Changed || !saved.Committed || saved.ErrorMessage != "" {
		t.Fatalf("SaveFullSiteUnitSummaryPreferences failed: %+v", saved)
	}
	reloaded, err := svc.GetFullSiteUnitSummaryPreferences(context.Background(), state.ContextID)
	if err != nil || reloaded.Values != proposed {
		t.Fatalf("reloaded full preferences mismatch: got=%+v want=%+v err=%v", reloaded, proposed, err)
	}

	// Verify stale expected detects CAS collision
	collision := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), state.ContextID, fullSummaryPreferenceRequest(t, expected, expected))
	if collision.Committed || collision.ErrorMessage == "" {
		t.Fatalf("expected CAS collision for stale expected, got %+v", collision)
	}

	// Verify out-of-range fields are rejected cleanly
	invalidCases := []SiteUnitSummaryFullPreferenceValues{
		{0, 3, 1, 3, 2, 2, 20, 5},
		{2, 4, 1, 3, 2, 2, 20, 5},
		{2, 3, 2, 3, 2, 2, 20, 5},
		{2, 3, 1, 4, 2, 2, 20, 5},
		{2, 3, 1, 3, 3, 2, 20, 5},
		{2, 3, 1, 3, 2, 3, 20, 5},
		{2, 3, 1, 3, 2, 2, 32768, 5},
		{2, 3, 1, 3, 2, 2, 20, -1},
	}
	for _, bad := range invalidCases {
		res := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), state.ContextID, fullSummaryPreferenceRequest(t, proposed, bad))
		if res.Committed || res.ErrorMessage == "" {
			t.Fatalf("expected out-of-range full preferences %+v to fail, got %+v", bad, res)
		}
	}

	// Verify SiteUnitType=3 succeeds even when SU == "None", while SiteUnitType=1 rejects SU == "None"
	noneSel := vprotest.ContextSelection(state)
	noneSel.SU, noneSel.SUPath = "None", ""
	noneState, err := contexts.SwitchContext(state.ContextID, noneSel)
	if err != nil {
		t.Fatal(err)
	}
	type1Bad := proposed
	type1Bad.SiteUnitType = 1
	if res := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), noneState.ContextID, fullSummaryPreferenceRequest(t, proposed, type1Bad)); res.Committed || res.ErrorMessage == "" {
		t.Fatalf("expected SiteUnitType=1 with SU=None to fail, got %+v", res)
	}
	type3Updated := proposed
	type3Updated.CoverGreaterThan = 10
	if res := svc.SaveFullSiteUnitSummaryPreferences(context.Background(), noneState.ContextID, fullSummaryPreferenceRequest(t, proposed, type3Updated)); !res.Committed || res.ErrorMessage != "" {
		t.Fatalf("expected SiteUnitType=3 with SU=None to save cleanly, got %+v", res)
	}
}
