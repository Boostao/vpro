package envreport

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/xuri/excelize/v2"
)

func TestQuickEnvironmentReportsWorkWhenActiveSUIsNone(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	if state.ActiveSU != "None" {
		t.Fatalf("expected default Sample fixture ActiveSU=None, got %q", state.ActiveSU)
	}

	// 1. Long Environment Quick Export & HTML Render with ActiveSU=="None"!
	leTitle := "Client Long Env 2026"
	lePath := filepath.Join(t.TempDir(), "long_env.xlsx")
	leRes, err := QuickExportLongEnvironmentWorkbook(service, ctx, state.ContextID, QuickLongEnvironmentRequest{
		Title:           &leTitle,
		DestinationPath: lePath,
	})
	if err != nil {
		t.Fatalf("QuickExportLongEnvironmentWorkbook: %v", err)
	}
	if leRes.UnitCount == 0 || leRes.PlotCount == 0 || leRes.Bytes == 0 || !leRes.PreferencesSaved {
		t.Fatalf("unexpected Long Environment quick export result: %+v", leRes)
	}
	if leRes.FallbackNotice == "" {
		t.Fatalf("expected clear FallbackNotice when ActiveSU=None, got %+v", leRes)
	}
	if book, err := excelize.OpenFile(leRes.Path); err != nil {
		t.Fatalf("reopen long env xlsx: %v", err)
	} else {
		_ = book.Close()
	}

	leHTML, err := RenderLongEnvironmentHTMLReport(service, ctx, state.ContextID, QuickLongEnvironmentRequest{})
	if err != nil {
		t.Fatalf("RenderLongEnvironmentHTMLReport: %v", err)
	}
	if leHTML.TableCount == 0 || !strings.Contains(leHTML.HTML, leTitle) || !strings.Contains(leHTML.HTML, "GENERAL LOCATION") {
		t.Fatalf("unexpected Long Environment HTML output: tables=%d", leHTML.TableCount)
	}

	// 2. Summary Environment Quick Export & HTML Render with ActiveSU=="None" (both standard & extended lifeform/species!).
	sePath := filepath.Join(t.TempDir(), "summary_env.xlsx")
	method := 1
	seRes, err := QuickExportSummaryEnvironmentWorkbook(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		Method:          &method,
		DestinationPath: sePath,
	})
	if err != nil {
		t.Fatalf("QuickExportSummaryEnvironmentWorkbook(standard): %v", err)
	}
	if seRes.UnitCount == 0 || seRes.PlotCount == 0 || seRes.FallbackNotice == "" {
		t.Fatalf("unexpected Summary Environment quick export result: %+v", seRes)
	}
	if _, err := os.Stat(seRes.Path); err != nil {
		t.Fatalf("missing summary env xlsx: %v", err)
	}

	// Verify extended options (OrderBy=2, IncludeSpecies=1) also export cleanly in one step!
	orderBy := 2
	incSpp := 1
	seExtPath := filepath.Join(t.TempDir(), "summary_env_ext.xlsx")
	seExtRes, err := QuickExportSummaryEnvironmentWorkbook(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		Method:          &method,
		OrderBy:         &orderBy,
		IncludeSpecies:  &incSpp,
		DestinationPath: seExtPath,
	})
	if err != nil {
		t.Fatalf("QuickExportSummaryEnvironmentWorkbook(extended): %v", err)
	}
	if seExtRes.Bytes == 0 {
		t.Fatalf("expected non-empty extended workbook bytes, got %+v", seExtRes)
	}

	// Verify Summary Environment HTML without species renders strictly the 1 environmental table.
	noSpp := 0
	saveFalse := false
	seHTMLNoSpp, err := RenderSummaryEnvironmentHTMLReport(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		IncludeSpecies:  &noSpp,
		SavePreferences: &saveFalse,
	})
	if err != nil {
		t.Fatalf("RenderSummaryEnvironmentHTMLReport(IncludeSpecies=0): %v", err)
	}
	if seHTMLNoSpp.TableCount != 1 || !strings.Contains(seHTMLNoSpp.HTML, "Site Unit Environmental Summary") {
		t.Fatalf("unexpected Summary Environment HTML without species: tables=%d", seHTMLNoSpp.TableCount)
	}

	// P2 #6: Verify Summary Environment HTML with saved/requested IncludeSpecies=1 appends species summary tables!
	seHTMLWithSpp, err := RenderSummaryEnvironmentHTMLReport(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		SavePreferences: &saveFalse,
	})
	if err != nil {
		t.Fatalf("RenderSummaryEnvironmentHTMLReport(IncludeSpecies=1): %v", err)
	}
	if seHTMLWithSpp.TableCount <= 1 || !strings.Contains(seHTMLWithSpp.HTML, "Species Summary") {
		t.Fatalf("expected species summary tables in HTML when IncludeSpecies=1, got tables=%d", seHTMLWithSpp.TableCount)
	}

	// 3. Subzone Matrix Quick Export & HTML Render (uses Sample default ActiveHierarchy="Sample").
	if state.ActiveHierarchy != "None" {
		smPath := filepath.Join(t.TempDir(), "subzone_matrix.xlsx")
		smRes, err := QuickExportSubzoneMatrixWorkbook(service, ctx, state.ContextID, QuickSubzoneMatrixRequest{
			DestinationPath: smPath,
		})
		if err != nil {
			t.Fatalf("QuickExportSubzoneMatrixWorkbook: %v", err)
		}
		if smRes.Bytes == 0 {
			t.Fatalf("expected non-empty subzone matrix xlsx, got %+v", smRes)
		}
		smHTML, err := RenderSubzoneMatrixHTMLReport(service, ctx, state.ContextID)
		if err != nil {
			t.Fatalf("RenderSubzoneMatrixHTMLReport: %v", err)
		}
		if smHTML.TableCount != 1 || !strings.Contains(smHTML.HTML, "Biogeoclimatic Subzone Matrix") {
			t.Fatalf("unexpected Subzone Matrix HTML: tables=%d", smHTML.TableCount)
		}
	}
}

func TestQuickEnvironmentReportsHandleEmptyActiveSUTable(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	created, err := service.CreateWorkspaceResource(ctx, state.ContextID, vprocore.CreateWorkspaceResourceRequest{
		Kind:            vprocore.WorkspaceResourceSU,
		Name:            "EmptyEnvSU",
		DestinationMode: "active_project",
		PopulatePlots:   false,
		Activate:        true,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(EmptyEnvSU): %v", err)
	}
	state = created.State
	if state.ActiveSU != "EmptyEnvSU" {
		t.Fatalf("expected ActiveSU=EmptyEnvSU, got %q", state.ActiveSU)
	}

	saveFalse := false
	// Auto mode falls back cleanly with FallbackNotice naming EmptyEnvSU.
	leRes, err := QuickExportLongEnvironmentWorkbook(service, ctx, state.ContextID, QuickLongEnvironmentRequest{
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "empty_su_long_env.xlsx"),
	})
	if err != nil {
		t.Fatalf("LongEnv QuickExport on EmptyEnvSU (auto): %v", err)
	}
	if !strings.Contains(leRes.FallbackNotice, "EmptyEnvSU") || leRes.PlotCount == 0 {
		t.Fatalf("expected EmptyEnvSU fallback notice and plots for LongEnv, got %+v", leRes)
	}
	seRes, err := QuickExportSummaryEnvironmentWorkbook(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "empty_su_sum_env.xlsx"),
	})
	if err != nil {
		t.Fatalf("SummaryEnv QuickExport on EmptyEnvSU (auto): %v", err)
	}
	if !strings.Contains(seRes.FallbackNotice, "EmptyEnvSU") || seRes.PlotCount == 0 {
		t.Fatalf("expected EmptyEnvSU fallback notice and plots for SummaryEnv, got %+v", seRes)
	}

	// Explicitly pinned SU mode returns a clear plain-language error naming EmptyEnvSU.
	if _, err := QuickExportLongEnvironmentWorkbook(service, ctx, state.ContextID, QuickLongEnvironmentRequest{
		ScopeMode:       "su",
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "pinned_long_env.xlsx"),
	}); err == nil || !strings.Contains(err.Error(), "EmptyEnvSU") || !strings.Contains(err.Error(), "no assigned plots") {
		t.Fatalf("expected plain-language empty SU error for pinned LongEnv, got: %v", err)
	}
	normalSU := 1
	if _, err := QuickExportSummaryEnvironmentWorkbook(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{
		SiteUnitType:    &normalSU,
		SavePreferences: &saveFalse,
		DestinationPath: filepath.Join(t.TempDir(), "pinned_sum_env.xlsx"),
	}); err == nil || !strings.Contains(err.Error(), "EmptyEnvSU") || !strings.Contains(err.Error(), "no assigned plots") {
		t.Fatalf("expected plain-language empty SU error for pinned SummaryEnv, got: %v", err)
	}
}
