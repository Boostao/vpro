package envreport

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

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

	seHTML, err := RenderSummaryEnvironmentHTMLReport(service, ctx, state.ContextID, QuickSummaryEnvironmentRequest{})
	if err != nil {
		t.Fatalf("RenderSummaryEnvironmentHTMLReport: %v", err)
	}
	if seHTML.TableCount != 1 || !strings.Contains(seHTML.HTML, "Site Unit Environmental Summary") {
		t.Fatalf("unexpected Summary Environment HTML: tables=%d", seHTML.TableCount)
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
