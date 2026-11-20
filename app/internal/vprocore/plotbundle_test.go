package vprocore_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func assertJSONEqual(t *testing.T, label string, got, want any) {
	t.Helper()
	gotBytes, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("%s: marshal got: %v", label, err)
	}
	wantBytes, err := json.Marshal(want)
	if err != nil {
		t.Fatalf("%s: marshal want: %v", label, err)
	}
	if string(gotBytes) != string(wantBytes) {
		t.Fatalf("%s mismatch:\n got: %s\nwant: %s", label, gotBytes, wantBytes)
	}
}

func TestGetPlotBundleMatchesIndividualRPCs(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)

	page, err := contexts.Projects.ListPlots(ctx, 0, 5)
	if err != nil || len(page.Plots) == 0 {
		t.Fatalf("ListPlots failed: %v (len=%d)", err, len(page.Plots))
	}

	for i, summary := range page.Plots {
		if i >= 3 {
			break
		}
		plot := summary.PlotNumber
		bundle, err := contexts.GetPlotBundle(ctx, state.ContextID, plot, true)
		if err != nil {
			t.Fatalf("GetPlotBundle(%q, true) failed: %v", plot, err)
		}

		header, err := contexts.GetPlot(ctx, state.ContextID, plot)
		if err != nil {
			t.Fatalf("GetPlot(%q) failed: %v", plot, err)
		}
		headerCaps, err := contexts.GetHeaderCapabilities(ctx, state.ContextID)
		if err != nil {
			t.Fatalf("GetHeaderCapabilities failed: %v", err)
		}
		masterAllowed, err := contexts.CanEditMasterBEC(ctx, state.ContextID)
		if err != nil {
			t.Fatalf("CanEditMasterBEC failed: %v", err)
		}
		vegAvail, err := contexts.GetVegetationReadAvailability(ctx, state.ContextID, plot)
		if err != nil {
			t.Fatalf("GetVegetationReadAvailability(%q) failed: %v", plot, err)
		}
		humus, err := contexts.ListHumusRecords(ctx, state.ContextID, plot)
		if err != nil {
			t.Fatalf("ListHumusRecords(%q) failed: %v", plot, err)
		}
		mineral, err := contexts.ListMineralRecords(ctx, state.ContextID, plot)
		if err != nil {
			t.Fatalf("ListMineralRecords(%q) failed: %v", plot, err)
		}
		other, err := contexts.ListOtherRecords(ctx, state.ContextID, plot)
		if err != nil {
			t.Fatalf("ListOtherRecords(%q) failed: %v", plot, err)
		}

		expectedChildCaps := make(map[string]map[string]bool, 4)
		for _, kind := range []string{"Veg", "Humus", "Mineral", "Other"} {
			caps, err := contexts.GetChildCapabilities(ctx, state.ContextID, kind)
			if err != nil {
				t.Fatalf("GetChildCapabilities(%q) failed: %v", kind, err)
			}
			expectedChildCaps[kind] = caps
		}

		assertJSONEqual(t, plot+" header", bundle.Header, header)
		assertJSONEqual(t, plot+" headerCapabilities", bundle.HeaderCapabilities, headerCaps)
		if bundle.CanEditMasterBEC != masterAllowed {
			t.Fatalf("%s canEditMasterBEC = %v, want %v", plot, bundle.CanEditMasterBEC, masterAllowed)
		}
		assertJSONEqual(t, plot+" childCapabilities", bundle.ChildCapabilities, expectedChildCaps)
		assertJSONEqual(t, plot+" vegetation", bundle.Vegetation, vegAvail)
		assertJSONEqual(t, plot+" humus", bundle.Humus, humus)
		if bundle.HumusError != "" {
			t.Fatalf("%s unexpected humusError: %q", plot, bundle.HumusError)
		}
		assertJSONEqual(t, plot+" mineral", bundle.Mineral, mineral)
		if bundle.MineralError != "" {
			t.Fatalf("%s unexpected mineralError: %q", plot, bundle.MineralError)
		}
		assertJSONEqual(t, plot+" other", bundle.Other, other)

		// When includeCapabilities == false, capabilities are omitted while data stays identical.
		lightBundle, err := contexts.GetPlotBundle(ctx, state.ContextID, plot, false)
		if err != nil {
			t.Fatalf("GetPlotBundle(%q, false) failed: %v", plot, err)
		}
		if lightBundle.HeaderCapabilities != nil || lightBundle.ChildCapabilities != nil {
			t.Fatalf("includeCapabilities=false returned capabilities: header=%v child=%v",
				lightBundle.HeaderCapabilities != nil, lightBundle.ChildCapabilities != nil)
		}
		assertJSONEqual(t, plot+" light header", lightBundle.Header, header)
		assertJSONEqual(t, plot+" light vegetation", lightBundle.Vegetation, vegAvail)
		assertJSONEqual(t, plot+" light humus", lightBundle.Humus, humus)
		assertJSONEqual(t, plot+" light mineral", lightBundle.Mineral, mineral)
		assertJSONEqual(t, plot+" light other", lightBundle.Other, other)
	}

	// Master BEC policy propagates into bundle when user changes.
	if _, err := contexts.SetUserName(ctx, state.ContextID, "Will MacKenzie"); err != nil {
		t.Fatalf("SetUserName failed: %v", err)
	}
	masterBundle, err := contexts.GetPlotBundle(ctx, state.ContextID, page.Plots[0].PlotNumber, false)
	if err != nil {
		t.Fatalf("GetPlotBundle after SetUserName failed: %v", err)
	}
	if !masterBundle.CanEditMasterBEC {
		t.Fatal("expected CanEditMasterBEC=true for Will MacKenzie")
	}

	// Missing plot returns exact plot-not-found error matching GetPlot.
	_, wantMissingErr := contexts.GetPlot(ctx, state.ContextID, "NO_SUCH")
	_, gotMissingErr := contexts.GetPlotBundle(ctx, state.ContextID, "NO_SUCH", true)
	if wantMissingErr == nil || gotMissingErr == nil || gotMissingErr.Error() != wantMissingErr.Error() {
		t.Fatalf("missing plot error = %v, want %v", gotMissingErr, wantMissingErr)
	}

	// Stale or empty contextID is rejected.
	for _, badID := range []string{"", "stale-context-id"} {
		if got, err := contexts.GetPlotBundle(ctx, badID, page.Plots[0].PlotNumber, true); err == nil || got != nil {
			t.Fatalf("expected stale contextID %q to fail, got (%v, %v)", badID, got, err)
		}
	}
}

func TestGetPlotBundleHistoricalNullIDIsolation(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)
	projectPath := contexts.Projects.Sqlite.Attachments["project"]

	page, err := contexts.Projects.ListPlots(ctx, 0, 3)
	if err != nil || len(page.Plots) < 2 {
		t.Fatalf("ListPlots failed: %v", err)
	}
	plotA := page.Plots[0].PlotNumber
	plotB := page.Plots[1].PlotNumber

	// Inject historical NULL IDs in Veg, Humus, and Mineral for plotA (matching imported tables without PK on ID).
	vprotest.MutateContextFixture(t, projectPath, fmt.Sprintf(`
		PRAGMA legacy_alter_table = ON;
		CREATE TABLE "Sample_Humus_Legacy" AS SELECT * FROM "Sample_Humus";
		DROP TABLE "Sample_Humus";
		ALTER TABLE "Sample_Humus_Legacy" RENAME TO "Sample_Humus";
		CREATE TABLE "Sample_Mineral_Legacy" AS SELECT * FROM "Sample_Mineral";
		DROP TABLE "Sample_Mineral";
		ALTER TABLE "Sample_Mineral_Legacy" RENAME TO "Sample_Mineral";
		INSERT INTO "Sample_Veg" ("ID","PlotNumber","Species") VALUES (NULL, '%s', 'PSEUMEN');
		INSERT INTO "Sample_Humus" ("ID","PlotNumber","Horizon") VALUES (NULL, '%s', 'L');
		INSERT INTO "Sample_Mineral" ("ID","PlotNumber","Horizon") VALUES (NULL, '%s', 'Ah');
	`, plotA, plotA, plotA))

	bundle, err := contexts.GetPlotBundle(ctx, state.ContextID, plotA, true)
	if err != nil {
		t.Fatalf("GetPlotBundle must isolate historical NULL IDs instead of failing RPC: %v", err)
	}
	if bundle.Header == nil || bundle.Header.PlotNumber != plotA {
		t.Fatalf("expected Header for %q, got %+v", plotA, bundle.Header)
	}

	wantVeg, err := contexts.GetVegetationReadAvailability(ctx, state.ContextID, plotA)
	if err != nil {
		t.Fatalf("GetVegetationReadAvailability failed: %v", err)
	}
	if bundle.Vegetation == nil || bundle.Vegetation.Available || bundle.Vegetation.Reason != wantVeg.Reason {
		t.Fatalf("vegetation NULL-ID mismatch: got %+v, want %+v", bundle.Vegetation, wantVeg)
	}

	_, wantHumusErr := contexts.ListHumusRecords(ctx, state.ContextID, plotA)
	if wantHumusErr == nil || bundle.Humus != nil || bundle.HumusError != wantHumusErr.Error() {
		t.Fatalf("humus NULL-ID mismatch: got (%v, %q), want err %v", bundle.Humus, bundle.HumusError, wantHumusErr)
	}

	_, wantMineralErr := contexts.ListMineralRecords(ctx, state.ContextID, plotA)
	if wantMineralErr == nil || bundle.Mineral != nil || bundle.MineralError != wantMineralErr.Error() {
		t.Fatalf("mineral NULL-ID mismatch: got (%v, %q), want err %v", bundle.Mineral, bundle.MineralError, wantMineralErr)
	}

	// Duplicate Veg ID on plotB also isolates via Vegetation.Reason without failing the bundle.
	vprotest.MutateContextFixture(t, projectPath, fmt.Sprintf(`
		INSERT INTO "Sample_Veg" ("ID","PlotNumber","Species") VALUES (999001, '%s', 'PSEUMEN');
		INSERT INTO "Sample_Veg" ("ID","PlotNumber","Species") VALUES (999001, '%s', 'THUJPLI');
	`, plotB, plotB))

	dupBundle, err := contexts.GetPlotBundle(ctx, state.ContextID, plotB, false)
	if err != nil {
		t.Fatalf("GetPlotBundle failed on duplicate Veg ID: %v", err)
	}
	wantDupVeg, err := contexts.GetVegetationReadAvailability(ctx, state.ContextID, plotB)
	if err != nil {
		t.Fatalf("GetVegetationReadAvailability failed on duplicate Veg ID: %v", err)
	}
	if dupBundle.Vegetation == nil || dupBundle.Vegetation.Available || dupBundle.Vegetation.Reason != wantDupVeg.Reason {
		t.Fatalf("duplicate Veg ID mismatch: got %+v, want %+v", dupBundle.Vegetation, wantDupVeg)
	}
}

type countingHeaderDB struct {
	inner   sqlutil.HeaderDB
	queries atomic.Int64
}

func (c *countingHeaderDB) Query(query string, args ...any) (*sql.Rows, error) {
	c.queries.Add(1)
	return c.inner.Query(query, args...)
}

func (c *countingHeaderDB) QueryRow(query string, args ...any) *sql.Row {
	c.queries.Add(1)
	return c.inner.QueryRow(query, args...)
}

func TestSqliteContextSchemaCapabilityCacheDefensiveCloneAndLifecycle(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)
	owner := contexts.Projects.Sqlite

	readDB, err := owner.ProjectReadDatabase(ctx)
	if err != nil {
		t.Fatalf("ProjectReadDatabase failed: %v", err)
	}
	counter := &countingHeaderDB{inner: sqlutil.ContextPlotDB{DB: readDB, Ctx: ctx}}

	// First HeaderCapabilities call hits PRAGMA table_info (Env + Admin = 2 queries).
	h1, err := owner.CachedHeaderCapabilities(counter, state.ActiveProject)
	if err != nil {
		t.Fatalf("CachedHeaderCapabilities #1 failed: %v", err)
	}
	afterFirstHeader := counter.queries.Load()
	if afterFirstHeader != 2 {
		t.Fatalf("expected 2 PRAGMA queries on cold header cap load, got %d", afterFirstHeader)
	}

	// Mutating caller's returned map must never poison the cache.
	h1["zone"] = false
	h1["injectedKey"] = true

	// Second call hits cache with 0 queries and returns untouched values.
	h2, err := owner.CachedHeaderCapabilities(counter, state.ActiveProject)
	if err != nil {
		t.Fatalf("CachedHeaderCapabilities #2 failed: %v", err)
	}
	if counter.queries.Load() != afterFirstHeader {
		t.Fatalf("expected 0 PRAGMA queries on warm header cap hit, got %d", counter.queries.Load()-afterFirstHeader)
	}
	if !h2["zone"] || h2["injectedKey"] {
		t.Fatalf("cached headerCaps was mutated by caller: zone=%v injectedKey=%v", h2["zone"], h2["injectedKey"])
	}

	// ChildCapabilities caches per kind and defensively clones.
	c1, err := owner.CachedChildCapabilities(counter, state.ActiveProject, "Veg")
	if err != nil {
		t.Fatalf("CachedChildCapabilities #1 failed: %v", err)
	}
	afterFirstChild := counter.queries.Load()
	if afterFirstChild != afterFirstHeader+1 {
		t.Fatalf("expected 1 PRAGMA query on cold child cap load, got %d", afterFirstChild-afterFirstHeader)
	}
	c1["species"] = false
	c1["injectedChild"] = true

	c2, err := owner.CachedChildCapabilities(counter, state.ActiveProject, "Veg")
	if err != nil {
		t.Fatalf("CachedChildCapabilities #2 failed: %v", err)
	}
	if counter.queries.Load() != afterFirstChild {
		t.Fatalf("expected 0 PRAGMA queries on warm child cap hit, got %d", counter.queries.Load()-afterFirstChild)
	}
	if !c2["species"] || c2["injectedChild"] {
		t.Fatalf("cached childCaps was mutated by caller: species=%v injectedChild=%v", c2["species"], c2["injectedChild"])
	}

	// Concurrent reads on cached caps are race-free.
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if caps, err := owner.CachedHeaderCapabilities(counter, state.ActiveProject); err != nil || !caps["plotNumber"] {
				t.Errorf("concurrent CachedHeaderCapabilities failed: %v", err)
			}
			if caps, err := owner.CachedChildCapabilities(counter, state.ActiveProject, "Veg"); err != nil || !caps["species"] {
				t.Errorf("concurrent CachedChildCapabilities failed: %v", err)
			}
		}()
	}
	wg.Wait()
	if counter.queries.Load() != afterFirstChild {
		t.Fatalf("expected 0 additional queries under concurrent warm hits, got %d", counter.queries.Load()-afterFirstChild)
	}

	// InvalidateSchemaCache clears both header and child caches.
	owner.InvalidateSchemaCache()
	if _, err := owner.CachedHeaderCapabilities(counter, state.ActiveProject); err != nil {
		t.Fatalf("CachedHeaderCapabilities after InvalidateSchemaCache failed: %v", err)
	}
	if counter.queries.Load() != afterFirstChild+2 {
		t.Fatalf("expected 2 PRAGMA queries after InvalidateSchemaCache, got %d", counter.queries.Load()-afterFirstChild)
	}

	// Close clears caches, invokes OnClose hooks, and rejects further ProjectReadDatabase calls.
	var hookCalled atomic.Bool
	owner.OnClose(func() { hookCalled.Store(true) })
	if err := owner.Close(); err != nil {
		t.Fatalf("owner.Close failed: %v", err)
	}
	if !hookCalled.Load() {
		t.Fatal("expected OnClose hook to run on Close()")
	}
	if _, err := owner.ProjectReadDatabase(ctx); err == nil {
		t.Fatal("expected ProjectReadDatabase to fail after Close()")
	}
}

func TestWorkingUnitEnvReusesProjectReadDBConcurrently(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)
	wu, err := vprocore.NewWorkingUnitService(contexts.Projects, t.TempDir())
	if err != nil {
		t.Fatalf("NewWorkingUnitService failed: %v", err)
	}
	t.Cleanup(func() { _ = wu.Close() })

	baseline, err := wu.GetWorkingUnitChoices(ctx, "env")
	if err != nil {
		t.Fatalf("GetWorkingUnitChoices(env) failed: %v", err)
	}
	if contexts.Projects.Sqlite.ProjectReadDB == nil && contexts.Projects.Sqlite.ProjectDB == nil {
		t.Fatal("expected WorkingUnitService env mode to initialize/reuse SqliteContext ProjectReadDB")
	}

	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			got, err := wu.GetWorkingUnitChoices(ctx, "env")
			if err != nil {
				errs <- err
				return
			}
			if !reflect.DeepEqual(got, baseline) {
				errs <- fmt.Errorf("concurrent env choices diverged: got %d, want %d", len(got), len(baseline))
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}

	// Master mode remains functional and SU mode honors None-SU guard and SU selection.
	if master, err := wu.GetWorkingUnitChoices(ctx, "master"); err != nil || len(master) == 0 {
		t.Fatalf("GetWorkingUnitChoices(master) failed: len=%d err=%v", len(master), err)
	}
	if _, err := wu.GetWorkingUnitChoices(ctx, "su"); err == nil || !strings.Contains(err.Error(), "authorized SU") {
		t.Fatalf("expected SU guard error when SU is None, got %v", err)
	}
	sel := vprotest.ContextSelection(state)
	sel.SU, sel.SUPath = state.ActiveProject, state.ProjectPath
	if _, err := contexts.SwitchContext(state.ContextID, sel); err != nil {
		t.Fatalf("SwitchContext(Sample SU) failed: %v", err)
	}
	if _, err := wu.GetWorkingUnitChoices(ctx, "su"); err != nil {
		t.Fatalf("GetWorkingUnitChoices(su) with Sample SU failed: %v", err)
	}
}

func TestListVegetationSpeciesConcurrentCoordinatorSafety(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)

	forms := []string{"SubVegAXL_BC", "SubVegAXL", "SubVegAhtXL", "SubVegCXL", "SubVegChtXL", "SubVegDXL"}
	baseline := make(map[string][]vprocore.VegetationSpeciesOption, len(forms))
	for _, form := range forms {
		list, err := contexts.ListVegetationSpecies(ctx, state.ContextID, form)
		if err != nil || len(list) == 0 {
			t.Fatalf("baseline ListVegetationSpecies(%q) failed: len=%d err=%v", form, len(list), err)
		}
		baseline[form] = list
	}

	var wg sync.WaitGroup
	errs := make(chan error, 24)
	for _, form := range forms {
		for range 2 {
			wg.Add(1)
			go func(f string) {
				defer wg.Done()
				got, err := contexts.ListVegetationSpecies(ctx, state.ContextID, f)
				if err != nil {
					errs <- fmt.Errorf("ListVegetationSpecies(%q): %w", f, err)
					return
				}
				if !reflect.DeepEqual(got, baseline[f]) {
					errs <- fmt.Errorf("ListVegetationSpecies(%q) diverged: len %d vs %d", f, len(got), len(baseline[f]))
				}
			}(form)
		}
	}
	for range 4 {
		wg.Add(2)
		go func() {
			defer wg.Done()
			if _, err := contexts.ListVegetationSpeciesAliases(ctx, state.ContextID, vprocore.VegetationSpeciesLookup{Code: "PSEUMEN"}); err != nil {
				errs <- fmt.Errorf("ListVegetationSpeciesAliases: %w", err)
			}
		}()
		go func() {
			defer wg.Done()
			if _, err := contexts.ListVegetationSpeciesUsers(ctx, state.ContextID, vprocore.VegetationSpeciesLookup{Code: "PSEUMEN"}); err != nil {
				errs <- fmt.Errorf("ListVegetationSpeciesUsers: %w", err)
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}

	// Verify plot bundle on non-coordinator PlotService falls back cleanly to PRAGMA table_info.
	standalonePlots, _ := vprotest.ChildFixture(t)
	standaloneBundle, err := standalonePlots.GetPlotBundle("CHILD1", true)
	if err != nil {
		t.Fatalf("standalone GetPlotBundle failed: %v", err)
	}
	if standaloneBundle.Header == nil || standaloneBundle.Header.PlotNumber != "CHILD1" {
		t.Fatalf("unexpected standalone bundle header: %+v", standaloneBundle.Header)
	}
	if !standaloneBundle.HeaderCapabilities["plotNumber"] || !standaloneBundle.ChildCapabilities["Veg"]["species"] {
		t.Fatalf("unexpected standalone capabilities: header=%v veg=%v",
			standaloneBundle.HeaderCapabilities["plotNumber"], standaloneBundle.ChildCapabilities["Veg"]["species"])
	}
	if _, err := standalonePlots.GetPlotBundle("MISSING", false); err == nil || !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected missing plot error on standalone PlotService, got %v", err)
	}
}
