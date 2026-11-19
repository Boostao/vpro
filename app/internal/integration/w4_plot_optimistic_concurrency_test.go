package integration

import (
	"context"
	"encoding/json"
	"math"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

// TestW4ConcurrentSavePlotRejectsStaleBaseline verifies UX-ADMIN-004:
// two concurrent app instances sharing VPRO_DATA_DIR load plot 00337, Instance A
// commits a header edit, and Instance B's stale SavePlot / UpdatePlot (both via
// WithBaseline and Wails JSON {"original": ...} wire payloads) fails inside
// BEGIN IMMEDIATE without overwriting Instance A's committed values or writing
// spurious audit rows.
func TestW4ConcurrentSavePlotRejectsStaleBaseline(t *testing.T) {
	root := t.TempDir()
	sharedDataDir := filepath.Join(root, "shared-data")
	configDirA := filepath.Join(root, "config-a")
	configDirB := filepath.Join(root, "config-b")

	prefsA, err := vprocore.OpenDesktopConfig(sharedDataDir, configDirA)
	if err != nil {
		t.Fatalf("OpenDesktopConfig A: %v", err)
	}
	projectsA, err := vprocore.NewSQLiteProjectService(sharedDataDir, configDirA, prefsA)
	if err != nil {
		t.Fatalf("NewSQLiteProjectService A: %v", err)
	}
	t.Cleanup(func() { _ = projectsA.CloseSQLiteContext() })
	plotsA, err := vprocore.NewPlotServiceWithPreferences(projectsA)
	if err != nil {
		t.Fatalf("NewPlotServiceWithPreferences A: %v", err)
	}

	prefsB, err := vprocore.OpenDesktopConfig(sharedDataDir, configDirB)
	if err != nil {
		t.Fatalf("OpenDesktopConfig B: %v", err)
	}
	projectsB, err := vprocore.NewSQLiteProjectService(sharedDataDir, configDirB, prefsB)
	if err != nil {
		t.Fatalf("NewSQLiteProjectService B: %v", err)
	}
	t.Cleanup(func() { _ = projectsB.CloseSQLiteContext() })
	plotsB, err := vprocore.NewPlotServiceWithPreferences(projectsB)
	if err != nil {
		t.Fatalf("NewPlotServiceWithPreferences B: %v", err)
	}

	ctxSvcA, err := vprocore.NewContextService(projectsA, plotsA)
	if err != nil {
		t.Fatalf("NewContextService A: %v", err)
	}
	ctxSvcB, err := vprocore.NewContextService(projectsB, plotsB)
	if err != nil {
		t.Fatalf("NewContextService B: %v", err)
	}

	ctx := context.Background()
	stateA, err := projectsA.GetState(ctx)
	if err != nil {
		t.Fatalf("GetState A: %v", err)
	}
	stateB, err := projectsB.GetState(ctx)
	if err != nil {
		t.Fatalf("GetState B: %v", err)
	}

	// Both instances open plot "00337" and read the identical initial SoilNotes.
	loadedA, err := ctxSvcA.GetPlot(ctx, stateA.ContextID, "00337")
	if err != nil {
		t.Fatalf("Instance A GetPlot(00337): %v", err)
	}
	loadedB, err := ctxSvcB.GetPlot(ctx, stateB.ContextID, "00337")
	if err != nil {
		t.Fatalf("Instance B GetPlot(00337): %v", err)
	}
	if loadedA.SoilNotes == nil || loadedB.SoilNotes == nil || *loadedA.SoilNotes != *loadedB.SoilNotes {
		t.Fatalf("expected matching initial SoilNotes on 00337, got A=%v B=%v", loadedA.SoilNotes, loadedB.SoilNotes)
	}

	// Instance A saves "Instance A committed value" with its loaded baseline.
	aCommitted := "Instance A committed value"
	editA := loadedA.WithBaseline(*loadedA)
	editA.SoilNotes = &aCommitted
	if err := ctxSvcA.UpdatePlot(stateA.ContextID, editA); err != nil {
		t.Fatalf("Instance A UpdatePlot failed: %v", err)
	}

	auditsAfterA, err := ctxSvcA.ListAuditEntries(ctx, stateA.ContextID, "00337")
	if err != nil {
		t.Fatalf("ListAuditEntries after A: %v", err)
	}

	// Instance B attempts SavePlot with stale Go baseline -> must reject!
	bStale := "Instance B stale overwrite"
	staleGo := loadedB.WithBaseline(*loadedB)
	staleGo.SoilNotes = &bStale
	plotSvcB := vprocore.NewPlotService(projectsB)
	plotSvcB.ContextScoped = true
	if err := plotSvcB.SavePlot(staleGo); err == nil || !strings.Contains(err.Error(), "plot changed since it was loaded; reload before saving") {
		t.Fatalf("expected stale SavePlot conflict error, got: %v", err)
	}

	// Instance B attempts UpdatePlot over the Wails JSON wire carrying {"original": loadedB} -> must also reject!
	draftWire, err := json.Marshal(func() vprocore.FS882Header {
		cp := *loadedB
		cp.SoilNotes = &bStale
		return cp
	}())
	if err != nil {
		t.Fatalf("marshal draft: %v", err)
	}
	origWire, err := json.Marshal(*loadedB)
	if err != nil {
		t.Fatalf("marshal original: %v", err)
	}
	var payloadMap map[string]json.RawMessage
	if err := json.Unmarshal(draftWire, &payloadMap); err != nil {
		t.Fatalf("unmarshal map: %v", err)
	}
	payloadMap["original"] = origWire
	combinedWire, err := json.Marshal(payloadMap)
	if err != nil {
		t.Fatalf("marshal combined wire: %v", err)
	}
	var decodedWireHeader vprocore.FS882Header
	if err := json.Unmarshal(combinedWire, &decodedWireHeader); err != nil {
		t.Fatalf("unmarshal FS882Header with original: %v", err)
	}
	if decodedWireHeader.Baseline() == nil {
		t.Fatal("expected UnmarshalJSON to populate FS882Header.Baseline()")
	}
	if err := ctxSvcB.UpdatePlot(stateB.ContextID, decodedWireHeader); err == nil || !strings.Contains(err.Error(), "plot changed since it was loaded; reload before saving") {
		t.Fatalf("expected stale Wails wire UpdatePlot conflict error, got: %v", err)
	}

	// Verify Instance A's committed SoilNotes and audit count were NOT overwritten!
	persisted, err := ctxSvcA.GetPlot(ctx, stateA.ContextID, "00337")
	if err != nil {
		t.Fatalf("GetPlot after rejected B save: %v", err)
	}
	if persisted.SoilNotes == nil || *persisted.SoilNotes != aCommitted {
		t.Fatalf("Sample_Env.SoilNotes = %v, want %q", persisted.SoilNotes, aCommitted)
	}
	auditsAfterRejectedB, err := ctxSvcA.ListAuditEntries(ctx, stateA.ContextID, "00337")
	if err != nil {
		t.Fatalf("ListAuditEntries after rejected B: %v", err)
	}
	if len(auditsAfterRejectedB) != len(auditsAfterA) {
		t.Fatalf("stale SavePlot/UpdatePlot wrote spurious audit rows: got %d, want %d", len(auditsAfterRejectedB), len(auditsAfterA))
	}

	// Cross-field conflict: Instance A updates Elevation while Instance B only edits VegNotes on a stale baseline.
	reloadedB, err := ctxSvcB.GetPlot(ctx, stateB.ContextID, "00337")
	if err != nil {
		t.Fatalf("Instance B reload GetPlot: %v", err)
	}
	newElev := 945
	elevEditA := persisted.WithBaseline(*persisted)
	elevEditA.Elevation = &newElev
	if err := ctxSvcA.UpdatePlot(stateA.ContextID, elevEditA); err != nil {
		t.Fatalf("Instance A Elevation UpdatePlot: %v", err)
	}
	bVegNote := "Instance B veg note with stale elevation"
	crossStaleB := reloadedB.WithBaseline(*reloadedB)
	crossStaleB.VegNotes = &bVegNote
	if err := ctxSvcB.UpdatePlot(stateB.ContextID, crossStaleB); err == nil || !strings.Contains(err.Error(), "Elevation") {
		t.Fatalf("expected cross-field Elevation conflict error, got: %v", err)
	}

	// After Instance B reloads the latest plot state, its save succeeds cleanly.
	freshB, err := ctxSvcB.GetPlot(ctx, stateB.ContextID, "00337")
	if err != nil {
		t.Fatalf("Instance B second reload: %v", err)
	}
	bResolved := "Instance B merged after reload"
	validEditB := freshB.WithBaseline(*freshB)
	validEditB.SoilNotes = &bResolved
	if err := ctxSvcB.UpdatePlot(stateB.ContextID, validEditB); err != nil {
		t.Fatalf("Instance B UpdatePlot after reload failed: %v", err)
	}
	finalHdr, err := ctxSvcA.GetPlot(ctx, stateA.ContextID, "00337")
	if err != nil {
		t.Fatalf("final GetPlot: %v", err)
	}
	if finalHdr.SoilNotes == nil || *finalHdr.SoilNotes != bResolved || finalHdr.Elevation == nil || *finalHdr.Elevation != newElev {
		t.Fatalf("unexpected final header: SoilNotes=%v Elevation=%v", finalHdr.SoilNotes, finalHdr.Elevation)
	}
}

func TestW4SavePlotBaselineDeletedPlotAndNegativeZeroFloat(t *testing.T) {
	s, db := vprotest.HeaderFixture(t)
	negZero := math.Copysign(0, -1)
	posZero := 0.0
	h := vprocore.FS882Header{PlotNumber: "OPTZERO", Slope: &negZero}
	if err := s.CreatePlot(h); err != nil {
		t.Fatalf("CreatePlot: %v", err)
	}
	loaded, err := s.GetPlot("OPTZERO")
	if err != nil {
		t.Fatalf("GetPlot: %v", err)
	}
	// JSON stringify in JS turns -0.0 into +0.0; baseline comparison must treat -0.0 and +0.0 as equal.
	jsBaseline := *loaded
	jsBaseline.Slope = &posZero
	note := "Updated with +0.0 JS baseline"
	edit := loaded.WithBaseline(jsBaseline)
	edit.SoilNotes = &note
	if err := s.SavePlot(edit); err != nil {
		t.Fatalf("expected -0.0/+0.0 baseline to pass without false conflict, got: %v", err)
	}

	// Deleting the plot externally and calling SavePlot with a non-nil baseline must reject instead of re-inserting.
	afterSave, err := s.GetPlot("OPTZERO")
	if err != nil {
		t.Fatalf("GetPlot after save: %v", err)
	}
	if _, err := db.Exec(`DELETE FROM Sample_Admin WHERE Plot = 'OPTZERO'; DELETE FROM Sample_Env WHERE PlotNumber = 'OPTZERO'`); err != nil {
		t.Fatalf("external delete: %v", err)
	}
	staleUpsert := afterSave.WithBaseline(*afterSave)
	staleNote := "Should not resurrect deleted plot"
	staleUpsert.SoilNotes = &staleNote
	if err := s.SavePlot(staleUpsert); err == nil || !strings.Contains(err.Error(), "no longer exists; reload before saving") {
		t.Fatalf("expected deleted plot SavePlot with baseline to fail, got: %v", err)
	}
}
