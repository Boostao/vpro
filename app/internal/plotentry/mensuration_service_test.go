package plotentry_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/plotentry"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func strPtrM(s string) *string    { return &s }
func intPtrM(n int) *int          { return &n }
func floatPtrM(f float64) *float64 { return &f }

func TestMensurationServiceEndToEndAndReadOnlyGuard(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)
	if err := contexts.Plots.SetCurrentUser("MensUser"); err != nil {
		t.Fatal(err)
	}
	svc, err := plotentry.NewMensurationService(contexts)
	if err != nil {
		t.Fatalf("NewMensurationService failed: %v", err)
	}

	// 1. Existing 8-table project without mensuration tables returns hasTables=false, empty slices.
	initial, err := svc.GetPlotMensuration(ctx, state.ContextID, "00337")
	if err != nil {
		t.Fatalf("GetPlotMensuration failed: %v", err)
	}
	if initial.HasTables || len(initial.TreePlots) != 0 || len(initial.Trees) != 0 {
		t.Fatalf("expected hasTables=false and empty slices, got %+v", initial)
	}

	// 2. Stale contextID is rejected.
	if _, err := svc.GetPlotMensuration(ctx, "stale-id", "00337"); err == nil || !strings.Contains(err.Error(), "stale") {
		t.Fatalf("expected stale context error, got %v", err)
	}

	// 3. EnsureMensurationTables creates both tables and exposes temp views.
	ensured, err := svc.EnsureMensurationTables(ctx, state.ContextID)
	if err != nil {
		t.Fatalf("EnsureMensurationTables failed: %v", err)
	}
	if !ensured.CreatedTreePlot || !ensured.CreatedTrees || !ensured.HasTables {
		t.Fatalf("unexpected EnsureMensurationTables result: %+v", ensured)
	}

	// 4. SaveTreePlot + SaveTreeRow + GetPlotMensuration round-trip.
	savedTP, err := svc.SaveTreePlot(ctx, state.ContextID, vprocore.TreePlotRecord{
		PlotNumber:    "00337",
		SubPlot:       "1",
		MeasurementID: 1,
		Zone:          strPtrM("CWH"),
		CruisePlot:    true,
		SiteIndexPlot: true,
		BAF:           floatPtrM(6.0),
	})
	if err != nil {
		t.Fatalf("SaveTreePlot failed: %v", err)
	}
	if !savedTP.CruisePlot || !savedTP.SiteIndexPlot || savedTP.CWDPlot {
		t.Fatalf("unexpected boolean values on saved TreePlot: %+v", savedTP)
	}

	savedTree, err := svc.SaveTreeRow(ctx, state.ContextID, vprocore.TreeRowRecord{
		PlotNumber:    "00337",
		SubPlot:       strPtrM("1"),
		MeasurementID: intPtrM(1),
		TreeNum:       intPtrM(1),
		TreeSpp:       strPtrM("Cw"),
		DBH:           floatPtrM(42.5),
		TotalHtCalc:   floatPtrM(31.2),
		SI50:          floatPtrM(24.1),
	})
	if err != nil {
		t.Fatalf("SaveTreeRow failed: %v", err)
	}
	if savedTree.RowID <= 0 {
		t.Fatalf("expected assigned RowID, got %d", savedTree.RowID)
	}

	loaded, err := svc.GetPlotMensuration(ctx, state.ContextID, "00337")
	if err != nil {
		t.Fatalf("GetPlotMensuration after save failed: %v", err)
	}
	if !loaded.HasTables || len(loaded.TreePlots) != 1 || len(loaded.Trees) != 1 {
		t.Fatalf("expected 1 TreePlot and 1 Tree row, got %+v", loaded)
	}
	if loaded.Trees[0].TreeSpp == nil || *loaded.Trees[0].TreeSpp != "Cw" {
		t.Fatalf("expected TreeSpp='Cw', got %+v", loaded.Trees[0].TreeSpp)
	}

	// 5. ReadOnly guard: fail closed with ErrReadOnlyContext on all mutations, reads still succeed.
	contexts.Projects.Sqlite.ReadOnly = true
	roData, err := svc.GetPlotMensuration(ctx, state.ContextID, "00337")
	if err != nil || !roData.ReadOnly || len(roData.TreePlots) != 1 {
		t.Fatalf("expected ReadOnly GetPlotMensuration to succeed, got data=%+v err=%v", roData, err)
	}
	if _, err := svc.EnsureMensurationTables(ctx, state.ContextID); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("EnsureMensurationTables expected ErrReadOnlyContext, got %v", err)
	}
	if _, err := svc.SaveTreePlot(ctx, state.ContextID, *savedTP); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("SaveTreePlot expected ErrReadOnlyContext, got %v", err)
	}
	if err := svc.DeleteTreePlot(ctx, state.ContextID, "00337", "1", 1); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("DeleteTreePlot expected ErrReadOnlyContext, got %v", err)
	}
	if _, err := svc.SaveTreeRow(ctx, state.ContextID, *savedTree); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("SaveTreeRow expected ErrReadOnlyContext, got %v", err)
	}
	if err := svc.DeleteTreeRow(ctx, state.ContextID, "00337", "1", 1, 1); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("DeleteTreeRow expected ErrReadOnlyContext, got %v", err)
	}
	contexts.Projects.Sqlite.ReadOnly = false

	// 6. Delete tree row and tree plot cleanly.
	if err := svc.DeleteTreeRow(ctx, state.ContextID, "00337", "1", 1, 1); err != nil {
		t.Fatalf("DeleteTreeRow failed: %v", err)
	}
	if err := svc.DeleteTreePlot(ctx, state.ContextID, "00337", "1", 1); err != nil {
		t.Fatalf("DeleteTreePlot failed: %v", err)
	}

	final, err := svc.GetPlotMensuration(ctx, state.ContextID, "00337")
	if err != nil {
		t.Fatal(err)
	}
	if len(final.TreePlots) != 0 || len(final.Trees) != 0 {
		t.Fatalf("expected empty rows after delete, got %+v", final)
	}
}
