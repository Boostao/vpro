package envreport

import (
	"bytes"
	"context"
	"encoding/json"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSiteUnitSummaryWorkbookDesktopWire(t *testing.T) {
	service, state := vprotest.ReportServiceFixture(t, false)
	ctx := context.Background()

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Report_SU;
		DELETE FROM Sample_Veg WHERE PlotNumber IN ('W2P1', 'W2P2');
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, SiteSeries, Elevation) VALUES
			('W2P1', 'CWH', 'vm1', '01', 120),
			('W2P2', 'IDF', 'dk1', '04', 840);
		INSERT INTO Sample_Admin (Plot) VALUES ('W2P1'), ('W2P2');
		INSERT INTO Report_SU (PlotNumber, SiteUnit) VALUES
			('W2P2', 'Unit:Zeta'),
			('W2P1', 'Unit:Alpha');
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover1, Cover2, Cover6) VALUES
			('W2P1', 9101, 'ABIEAMA', 40, 25, 10),
			('W2P2', 9102, 'PSEUMEN', 55, 0, 20);
		DELETE FROM Sample_Hierarchy;
		INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level) VALUES
			(1, 'Root', 0, 0),
			(2, '~BP_Zeta', 1, 1),
			(3, 'Unit:Zeta', 2, 2),
			(4, '~BP_Alpha', 1, 1),
			(5, 'Unit:Alpha', 4, 2);
	`)

	wbService, err := NewSiteUnitSummaryWorkbookService(service)
	if err != nil {
		t.Fatal(err)
	}
	extService, err := NewSiteUnitSummaryExtendedWorkbookService(service)
	if err != nil {
		t.Fatal(err)
	}

	standard, err := wbService.GetReview(ctx, state.ContextID, `{"method":1}`)
	if err != nil {
		t.Fatalf("standard GetReview failed: %v", err)
	}
	if len(standard.Preview.Report.Units) != 2 ||
		standard.Preview.Report.Units[0].Code != "Unit:Zeta" ||
		standard.Preview.Report.Units[1].Code != "Unit:Alpha" {
		t.Fatalf("expected descending report units [Unit:Zeta Unit:Alpha], got %+v", standard.Preview.Report.Units)
	}
	if len(standard.Sheets) != 2 ||
		standard.Sheets[0].Name != "Unit-Alpha" ||
		standard.Sheets[1].Name != "Unit-Zeta" {
		t.Fatalf("expected ascending review sheets [Unit-Alpha Unit-Zeta], got %+v", standard.Sheets)
	}

	published, err := wbService.ExportReviewed(ctx, state.ContextID,
		summaryWorkbookExportJSON(t, 1, standard.ApprovalHash, filepath.Join(t.TempDir(), "summary.xlsx")))
	if err != nil || published.Status != "published" {
		t.Fatalf("standard ExportReviewed failed: out=%+v err=%v", published, err)
	}
	published.RequestedDestination = `C:\fixture\summary.xlsx`
	published.Path = published.RequestedDestination

	extendedLifeformReq := SiteUnitSummaryExtendedWorkbookOptions{
		Method: 1, OrderBy: 2, IncludeSpecies: 0, CoverCalculation: 1, AndOr: 1, PresenceGreaterThan: 0, CoverGreaterThan: 0,
	}
	extendedLifeform, err := extService.GetReview(ctx, state.ContextID, summaryExtendedJSON(t, extendedLifeformReq))
	if err != nil {
		t.Fatalf("extendedLifeform GetReview failed: %v", err)
	}

	extendedLayerSpeciesReq := SiteUnitSummaryExtendedWorkbookOptions{
		Method: 1, OrderBy: 1, IncludeSpecies: 1, CoverCalculation: 1, AndOr: 1, PresenceGreaterThan: 0, CoverGreaterThan: 0,
	}
	extendedLayerSpecies, err := extService.GetReview(ctx, state.ContextID, summaryExtendedJSON(t, extendedLayerSpeciesReq))
	if err != nil {
		t.Fatalf("extendedLayerSpecies GetReview failed: %v", err)
	}

	extendedStrataSpeciesReq := SiteUnitSummaryExtendedWorkbookOptions{
		Method: 2, OrderBy: 3, IncludeSpecies: 1, CoverCalculation: 1, AndOr: 1, PresenceGreaterThan: 0, CoverGreaterThan: 0,
	}
	extendedStrataSpecies, err := extService.GetReview(ctx, state.ContextID, summaryExtendedJSON(t, extendedStrataSpeciesReq))
	if err != nil {
		t.Fatalf("extendedStrataSpecies GetReview failed: %v", err)
	}

	if err := service.Projects.Preferences.Update("ReportOptions", map[string]any{"SESuType": 2, "SEOrderBy": 3}); err != nil {
		t.Fatal(err)
	}
	breakpoints, err := wbService.GetReview(ctx, state.ContextID, `{"method":2}`)
	if err != nil {
		t.Fatalf("breakpoints GetReview failed: %v", err)
	}

	normalizePreview := func(preview *SiteUnitSummaryPreview) {
		preview.ContextID = "summary-wire-context"
		preview.ProjectPath = `C:\fixture\Sample.db`
		preview.SUPath = `C:\fixture\Sample.db`
	}
	normalizePreview(&standard.Preview)
	normalizePreview(&breakpoints.Preview)
	for _, ext := range []*SiteUnitSummaryExtendedWorkbookReview{extendedLifeform, extendedLayerSpecies, extendedStrataSpecies} {
		normalizePreview(&ext.Environment)
		if ext.Species != nil {
			normalizePreview(&ext.Species.Environment)
		}
	}

	fixtures := map[string]any{
		"standard":              standard,
		"breakpoints":           breakpoints,
		"extendedLifeform":      extendedLifeform,
		"extendedLayerSpecies":  extendedLayerSpecies,
		"extendedStrataSpecies": extendedStrataSpecies,
		"published":             published,
	}

	fixtureRelPath := filepath.Join("frontend", "tests", "fixtures", "siteUnitSummaryWorkbookWire.json")
	persisted, err := sqlutil.ReadWireFixture(fixtureRelPath)
	if err != nil {
		t.Fatal(err)
	}
	var wires map[string]json.RawMessage
	if err := json.Unmarshal(persisted, &wires); err != nil || len(wires) != len(fixtures) {
		t.Fatalf("shared summary workbook wire fixture shape changed: err=%v len=%d", err, len(wires))
	}

	for _, name := range []string{"standard", "breakpoints"} {
		expected := fixtures[name].(*SiteUnitSummaryWorkbookReview)
		var decoded SiteUnitSummaryWorkbookReview
		decoder := json.NewDecoder(bytes.NewReader(wires[name]))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&decoded); err != nil ||
			!reflect.DeepEqual(expected.Preview, decoded.Preview) ||
			expected.Scope != decoded.Scope ||
			!reflect.DeepEqual(expected.Sheets, decoded.Sheets) ||
			len(decoded.ApprovalHash) != 64 || len(decoded.WorkbookSHA256) != 64 || decoded.Bytes <= 0 {
			t.Fatalf("shared summary workbook wire %s differs from production shape: err=%v", name, err)
		}
	}

	for _, name := range []string{"extendedLifeform", "extendedLayerSpecies", "extendedStrataSpecies"} {
		expected := fixtures[name].(*SiteUnitSummaryExtendedWorkbookReview)
		var decoded SiteUnitSummaryExtendedWorkbookReview
		decoder := json.NewDecoder(bytes.NewReader(wires[name]))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&decoded); err != nil ||
			!reflect.DeepEqual(expected.Environment, decoded.Environment) ||
			!reflect.DeepEqual(expected.Species, decoded.Species) ||
			expected.Scope != decoded.Scope ||
			expected.Options != decoded.Options ||
			!reflect.DeepEqual(expected.Sheets, decoded.Sheets) ||
			len(decoded.ApprovalHash) != 64 || len(decoded.WorkbookSHA256) != 64 || decoded.Bytes <= 0 {
			t.Fatalf("shared extended summary workbook wire %s differs from production shape: err=%v", name, err)
		}
	}

	var decodedOutcome SiteUnitSummaryWorkbookOutcome
	decoder := json.NewDecoder(bytes.NewReader(wires["published"]))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&decodedOutcome); err != nil ||
		decodedOutcome.Status != "published" ||
		decodedOutcome.RequestedDestination != `C:\fixture\summary.xlsx` ||
		len(decodedOutcome.SHA256) != 64 {
		t.Fatalf("shared summary workbook outcome wire differs: %+v err=%v", decodedOutcome, err)
	}
}
