package vegreport

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/xuri/excelize/v2"
	"go.yaml.in/yaml/v3"
)

func TestQuickVegetationReportsWorkWhenActiveSUIsNone(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	if state.ActiveSU != "None" {
		t.Fatalf("expected default Sample fixture ActiveSU=None, got %q", state.ActiveSU)
	}

	sumSvc, err := NewSummaryVegetationService(service)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvSvc, err := NewSummaryVegetationEnvironmentalService(sumSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvLfSvc, err := NewSummaryVegetationEnvironmentalLifeformService(sumEnvSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumWbSvc, err := NewSummaryVegetationWorkbookService(sumEnvLfSvc)
	if err != nil {
		t.Fatal(err)
	}

	// 1. Existing PreviewWithPreferences & GetReviewFromPreferences must no longer crash on ActiveSU=="None"!
	prefPrev, err := sumSvc.PreviewWithPreferences(ctx, state.ContextID)
	if err != nil {
		t.Fatalf("PreviewWithPreferences with ActiveSU=None failed: %v", err)
	}
	if len(prefPrev.Units) == 0 || len(prefPrev.Rows) == 0 {
		t.Fatalf("expected non-empty summary vegetation preview with ActiveSU=None, got units=%d rows=%d", len(prefPrev.Units), len(prefPrev.Rows))
	}
	if _, err := sumWbSvc.GetReviewFromPreferences(ctx, state.ContextID); err != nil {
		t.Fatalf("GetReviewFromPreferences with ActiveSU=None failed: %v", err)
	}

	// 2. QuickExportWorkbook for Summary Vegetation (persists title, writes .xlsx, handles ActiveSU=="None").
	customTitle := "Client Summary Veg 2026"
	sumOutPath := filepath.Join(t.TempDir(), "summary_veg.xlsx")
	sumRes, err := sumWbSvc.QuickExportWorkbook(ctx, state.ContextID, QuickSummaryVegetationRequest{
		Title:           &customTitle,
		DestinationPath: sumOutPath,
	})
	if err != nil {
		t.Fatalf("Summary QuickExportWorkbook: %v", err)
	}
	if sumRes.UnitCount == 0 || sumRes.PlotCount == 0 || sumRes.Bytes == 0 || !sumRes.PreferencesSaved {
		t.Fatalf("unexpected Summary QuickExportWorkbook result: %+v", sumRes)
	}
	if sumRes.FallbackNotice == "" {
		t.Fatalf("expected clear FallbackNotice when ActiveSU=None, got %+v", sumRes)
	}
	if book, err := excelize.OpenFile(sumRes.Path); err != nil {
		t.Fatalf("reopen summary veg xlsx: %v", err)
	} else {
		_ = book.Close()
	}

	// 3. RenderHTMLReport for Summary Vegetation.
	sumHTML, err := sumSvc.RenderHTMLReport(ctx, state.ContextID, QuickSummaryVegetationRequest{})
	if err != nil {
		t.Fatalf("Summary RenderHTMLReport: %v", err)
	}
	if !strings.Contains(sumHTML.HTML, customTitle) || !strings.Contains(sumHTML.HTML, "@media print") {
		t.Fatalf("expected saved title and print CSS in Summary Vegetation HTML")
	}

	// 4. QuickExportLongVegetationWorkbook + RenderLongVegetationHTMLReport with ActiveSU=="None"!
	lvTitle := "Quick Long Veg"
	lvOutPath := filepath.Join(t.TempDir(), "long_veg.xlsx")
	lvRes, err := QuickExportLongVegetationWorkbook(service, ctx, state.ContextID, QuickLongVegetationRequest{
		Title:           &lvTitle,
		DestinationPath: lvOutPath,
	})
	if err != nil {
		t.Fatalf("QuickExportLongVegetationWorkbook: %v", err)
	}
	if lvRes.UnitCount == 0 || lvRes.PlotCount == 0 || lvRes.FallbackNotice == "" {
		t.Fatalf("unexpected Long Vegetation quick export result: %+v", lvRes)
	}
	if _, err := os.Stat(lvRes.Path); err != nil {
		t.Fatalf("missing long veg xlsx: %v", err)
	}

	lvHTML, err := RenderLongVegetationHTMLReport(service, ctx, state.ContextID, QuickLongVegetationRequest{})
	if err != nil {
		t.Fatalf("RenderLongVegetationHTMLReport: %v", err)
	}
	if lvHTML.TableCount == 0 || !strings.Contains(lvHTML.HTML, lvTitle) {
		t.Fatalf("unexpected Long Vegetation HTML result: tables=%d", lvHTML.TableCount)
	}

	// 5. QuickExportLifeformWorkbook + RenderLifeformHTMLReport with ActiveSU=="None"!
	lfOutPath := filepath.Join(t.TempDir(), "lifeform.xlsx")
	lfRes, err := QuickExportLifeformWorkbook(service, ctx, state.ContextID, QuickLifeformReportRequest{
		DestinationPath: lfOutPath,
	})
	if err != nil {
		t.Fatalf("QuickExportLifeformWorkbook: %v", err)
	}
	if lfRes.UnitCount == 0 || lfRes.PlotCount == 0 || lfRes.FallbackNotice == "" {
		t.Fatalf("unexpected Lifeform quick export result: %+v", lfRes)
	}
	lfHTML, err := RenderLifeformHTMLReport(service, ctx, state.ContextID, QuickLifeformReportRequest{})
	if err != nil {
		t.Fatalf("RenderLifeformHTMLReport: %v", err)
	}
	if lfHTML.TableCount != 1 || !strings.Contains(lfHTML.HTML, "Mean Cover by Lifeform") {
		t.Fatalf("unexpected Lifeform HTML result: %+v", lfHTML)
	}
}

func TestSummaryVegetationQuickRunAndHTMLMissingReportOptionsAndSavedValueLimit(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	// Strip only the ReportOptions section from config.yml (keeping Desktop/Current) to simulate a minimal/upgraded config.
	cfgValues, err := service.Projects.Preferences.Snapshot()
	if err != nil {
		t.Fatalf("read config.yml snapshot: %v", err)
	}
	delete(cfgValues, "ReportOptions")
	rawCfg, err := yaml.Marshal(cfgValues)
	if err != nil {
		t.Fatalf("marshal config.yml without ReportOptions: %v", err)
	}
	if err := os.WriteFile(service.Projects.Preferences.Path, rawCfg, 0o600); err != nil {
		t.Fatalf("write config.yml without ReportOptions: %v", err)
	}

	sumSvc, err := NewSummaryVegetationService(service)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvSvc, err := NewSummaryVegetationEnvironmentalService(sumSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvLfSvc, err := NewSummaryVegetationEnvironmentalLifeformService(sumEnvSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumWbSvc, err := NewSummaryVegetationWorkbookService(sumEnvLfSvc)
	if err != nil {
		t.Fatal(err)
	}

	// P1 #2: Both QuickExportWorkbook and RenderHTMLReport must succeed cleanly when ReportOptions is missing.
	saveFalse := false
	res, err := sumWbSvc.QuickExportWorkbook(ctx, state.ContextID, QuickSummaryVegetationRequest{
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "missing_report_opts.xlsx"),
	})
	if err != nil {
		t.Fatalf("QuickExportWorkbook with missing ReportOptions failed: %v", err)
	}
	if res.Bytes == 0 || res.UnitCount == 0 {
		t.Fatalf("unexpected export result with missing ReportOptions: %+v", res)
	}
	htmlRes, err := sumSvc.RenderHTMLReport(ctx, state.ContextID, QuickSummaryVegetationRequest{
		SavePreferences: &saveFalse,
	})
	if err != nil {
		t.Fatalf("RenderHTMLReport with missing ReportOptions failed: %v", err)
	}
	if htmlRes.TableCount == 0 {
		t.Fatalf("expected non-empty HTML report with missing ReportOptions")
	}

	// P2 #5: RenderHTMLReport with req.ValueLimit == nil must honor saved SVShowValOpt.
	baselineHTML, err := sumSvc.RenderHTMLReport(ctx, state.ContextID, QuickSummaryVegetationRequest{
		SavePreferences: &saveFalse,
	})
	if err != nil {
		t.Fatalf("baseline RenderHTMLReport: %v", err)
	}
	highLimit := 95.0
	if _, err := sumSvc.RenderHTMLReport(ctx, state.ContextID, QuickSummaryVegetationRequest{
		ValueLimit: &highLimit,
	}); err != nil {
		t.Fatalf("save ValueLimit via RenderHTMLReport: %v", err)
	}
	// Now omit req.ValueLimit and verify saved SVShowValOpt (95) filters out lower-value rows.
	savedLimitHTML, err := sumSvc.RenderHTMLReport(ctx, state.ContextID, QuickSummaryVegetationRequest{
		SavePreferences: &saveFalse,
	})
	if err != nil {
		t.Fatalf("RenderHTMLReport with saved SVShowValOpt: %v", err)
	}
	if len(savedLimitHTML.HTML) >= len(baselineHTML.HTML) {
		t.Fatalf("expected saved SVShowValOpt=95 to filter rows (saved len=%d >= baseline len=%d)", len(savedLimitHTML.HTML), len(baselineHTML.HTML))
	}
}

func TestQuickVegetationReportsHandleEmptyActiveSUTable(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	// Create and activate an empty SU table (0 assigned plots).
	created, err := service.CreateWorkspaceResource(ctx, state.ContextID, vprocore.CreateWorkspaceResourceRequest{
		Kind:            vprocore.WorkspaceResourceSU,
		Name:            "EmptyVegSU",
		DestinationMode: "active_project",
		PopulatePlots:   false,
		Activate:        true,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(EmptyVegSU): %v", err)
	}
	state = created.State
	if state.ActiveSU != "EmptyVegSU" {
		t.Fatalf("expected ActiveSU=EmptyVegSU, got %q", state.ActiveSU)
	}

	sumSvc, err := NewSummaryVegetationService(service)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvSvc, err := NewSummaryVegetationEnvironmentalService(sumSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumEnvLfSvc, err := NewSummaryVegetationEnvironmentalLifeformService(sumEnvSvc)
	if err != nil {
		t.Fatal(err)
	}
	sumWbSvc, err := NewSummaryVegetationWorkbookService(sumEnvLfSvc)
	if err != nil {
		t.Fatal(err)
	}

	saveFalse := false
	// Auto mode falls back cleanly with FallbackNotice naming EmptyVegSU.
	sumRes, err := sumWbSvc.QuickExportWorkbook(ctx, state.ContextID, QuickSummaryVegetationRequest{
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "empty_su_sum.xlsx"),
	})
	if err != nil {
		t.Fatalf("Summary QuickExportWorkbook on EmptyVegSU (auto): %v", err)
	}
	if !strings.Contains(sumRes.FallbackNotice, "EmptyVegSU") || sumRes.PlotCount == 0 {
		t.Fatalf("expected EmptyVegSU fallback notice and plots, got %+v", sumRes)
	}
	lvRes, err := QuickExportLongVegetationWorkbook(service, ctx, state.ContextID, QuickLongVegetationRequest{
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "empty_su_lv.xlsx"),
	})
	if err != nil {
		t.Fatalf("LongVeg QuickExport on EmptyVegSU (auto): %v", err)
	}
	if !strings.Contains(lvRes.FallbackNotice, "EmptyVegSU") || lvRes.PlotCount == 0 {
		t.Fatalf("expected EmptyVegSU fallback notice and plots for LongVeg, got %+v", lvRes)
	}
	lfRes, err := QuickExportLifeformWorkbook(service, ctx, state.ContextID, QuickLifeformReportRequest{
		DestinationPath: filepath.Join(t.TempDir(), "empty_su_lf.xlsx"),
	})
	if err != nil {
		t.Fatalf("Lifeform QuickExport on EmptyVegSU (auto): %v", err)
	}
	if !strings.Contains(lfRes.FallbackNotice, "EmptyVegSU") || lfRes.PlotCount == 0 {
		t.Fatalf("expected EmptyVegSU fallback notice and plots for Lifeform, got %+v", lfRes)
	}

	// Explicitly pinned "su" mode returns a clear plain-language error naming EmptyVegSU.
	if _, err := sumWbSvc.QuickExportWorkbook(ctx, state.ContextID, QuickSummaryVegetationRequest{
		UnitScope:       "su",
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "pinned_sum.xlsx"),
	}); err == nil || !strings.Contains(err.Error(), "EmptyVegSU") || !strings.Contains(err.Error(), "no assigned plots") {
		t.Fatalf("expected plain-language empty SU error for pinned Summary Veg, got: %v", err)
	}
	if _, err := QuickExportLongVegetationWorkbook(service, ctx, state.ContextID, QuickLongVegetationRequest{
		ScopeMode:       "su",
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "pinned_lv.xlsx"),
	}); err == nil || !strings.Contains(err.Error(), "EmptyVegSU") || !strings.Contains(err.Error(), "no assigned plots") {
		t.Fatalf("expected plain-language empty SU error for pinned Long Veg, got: %v", err)
	}
	if _, err := QuickExportLifeformWorkbook(service, ctx, state.ContextID, QuickLifeformReportRequest{
		ScopeMode:       "su",
		DestinationPath: filepath.Join(t.TempDir(), "pinned_lf.xlsx"),
	}); err == nil || !strings.Contains(err.Error(), "EmptyVegSU") || !strings.Contains(err.Error(), "no assigned plots") {
		t.Fatalf("expected plain-language empty SU error for pinned Lifeform, got: %v", err)
	}
}
