package vegreport

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/xuri/excelize/v2"
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
