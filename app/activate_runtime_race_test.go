package main

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func seedRecoveryBrokenConfig(t *testing.T, dataDir, configDir string) (samplePath string, baseConfig []byte) {
	t.Helper()
	refs := openReferenceCatalogBundle(dataDir)
	defer refs.Close()
	cloud := NewCloudSyncManager(configDir)
	defer cloud.Close()

	initAct, err := openActiveProjectContext(dataDir, configDir, refs, cloud)
	if err != nil {
		t.Fatalf("seed openActiveProjectContext failed: %v", err)
	}
	_ = initAct.projects.CloseSQLiteContext()

	cfgPath := filepath.Join(configDir, "config.yml")
	rawCfg, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatalf("read seeded config.yml: %v", err)
	}
	writeBrokenProjectConfig(t, cfgPath, rawCfg, filepath.Join(dataDir, "projects", "MissingProj.db"))
	return filepath.Join(dataDir, "projects", "Sample.db"), rawCfg
}

func writeBrokenProjectConfig(t *testing.T, cfgPath string, baseConfig []byte, missingPath string) {
	t.Helper()
	lines := strings.Split(string(baseConfig), "\n")
	replaced := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "ProjectPath:") {
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			lines[i] = indent + "ProjectPath: " + missingPath
			replaced = true
		}
	}
	out := strings.Join(lines, "\n")
	if !replaced {
		out += "\nCurrent:\n  CurrProject: MissingProj\n  ProjectPath: " + missingPath + "\n"
	}
	if err := vprocorepkg.WriteDesktopConfigAtomically(cfgPath, []byte(out)); err != nil {
		t.Fatalf("write broken config.yml: %v", err)
	}
}

func copyFileForTest(t *testing.T, src, dst string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(dst), err)
	}
	raw, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("read %s: %v", src, err)
	}
	if err := os.WriteFile(dst, raw, 0o600); err != nil {
		t.Fatalf("write %s: %v", dst, err)
	}
}

func TestReproActivateRuntimeHotSwapDataRace(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	samplePath, baseCfg := seedRecoveryBrokenConfig(t, dataDir, configDir)
	relocatedSamplePath := filepath.Join(t.TempDir(), "relocated", "Sample.db")
	copyFileForTest(t, samplePath, relocatedSamplePath)

	refs := openReferenceCatalogBundle(dataDir)
	defer refs.Close()
	cloud := NewCloudSyncManager(configDir)
	defer cloud.Close()
	closeSvc, err := lifecyclepkg.NewCloseService(func(string) bool { return false }, func() {})
	if err != nil {
		t.Fatalf("NewCloseService: %v", err)
	}

	var failMidActivation atomic.Bool
	var everPublished atomic.Bool
	missingPicPath := filepath.Join(t.TempDir(), "missing-vpics", "VPics.db")
	lookupEnv := func(key string) (string, bool) {
		if key == "VPRO_PICTURE_LIBRARY_PATH" && failMidActivation.Load() {
			return missingPicPath, true
		}
		return os.LookupEnv(key)
	}

	graph := newWailsServiceGraph(dataDir, configDir, refs, cloud, closeSvc, lookupEnv)
	defer graph.tracker.shutdown(refs, cloud)

	if graph.lifecycle.GetStartupState().Ready {
		t.Fatal("expected initial recovery state Ready=false")
	}

	ctx := context.Background()
	var latestContextID atomic.Value
	latestContextID.Store("stale")
	currentCID := func() string {
		if v, ok := latestContextID.Load().(string); ok && v != "" {
			return v
		}
		return "stale"
	}

	var failureChannel atomic.Value
	recordFailure := func(msg string) {
		failureChannel.CompareAndSwap(nil, msg)
	}

	var wg sync.WaitGroup
	stop := make(chan struct{})
	spawn := func(fn func()) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-stop:
					return
				default:
					fn()
				}
			}
		}()
	}

	// Hammer all 12 Wails service façades concurrently:
	// 1. LifecycleService
	spawn(func() {
		_ = graph.lifecycle.GetStartupState()
		_ = graph.lifecycle.GetPendingCloseRequest()
		_, _ = graph.lifecycle.GetUserLogReview(ctx, currentCID(), 0, 0, 5)
	})
	// 2. ContextService (core + delegates + cloud sync)
	spawn(func() {
		if st, sErr := graph.context.GetState(ctx); sErr == nil {
			if !everPublished.Load() {
				recordFailure("ContextService.GetState succeeded before any activation completed")
				return
			}
			if st.ContextID != "" {
				latestContextID.Store(st.ContextID)
			}
		}
		_, _ = graph.context.ListPlots(ctx, 0, 5)
		_, _ = graph.context.GetCloudSyncConfigStatus(ctx)
		_, _ = graph.context.ReviewSiteUnitEnvironment(ctx, currentCID())
	})
	// 3. PlotEntryService (FS882 + SIVI + Two-Page + picklists)
	spawn(func() {
		_, _ = graph.plotEntry.GetHeaderCapabilities(ctx)
		_, _ = graph.plotEntry.GetPlot(ctx, "00337")
		_, _ = graph.plotEntry.GetSIVICoverOriginal(ctx, currentCID(), "00337", false)
		_, _ = graph.plotEntry.ListPlotQualityChoices(ctx)
	})
	// 4. DatasheetService
	spawn(func() {
		_, _ = graph.datasheet.ListDatasheetTables(ctx, currentCID())
		_, _ = graph.datasheet.GetEnvironmentTableReview(ctx, currentCID(), "00337", 0, 5)
	})
	// 5. ClassificationService
	spawn(func() {
		_, _ = graph.classification.GetBECCatalogueStatus(ctx)
		_, _ = graph.classification.GetWorkingUnitMode(ctx)
		_, _ = graph.classification.GetSUPlotTree(ctx, currentCID(), "")
	})
	// 6. ValidationService
	spawn(func() {
		_, _ = graph.validation.CheckSpeciesCodes(ctx, currentCID())
	})
	// 7. ImportExportService
	spawn(func() {
		_, _ = graph.importExport.DiscoverLumpTables(ctx, currentCID(), nil)
		_, _ = graph.importExport.GetPlotLabelRegionalPreview(ctx, currentCID(), "00337")
	})
	// 8. VegetationReportService
	spawn(func() {
		_, _ = graph.vegReport.PreviewLongVegetation(ctx, currentCID())
		_, _ = graph.vegReport.PreviewSummaryVegetation(ctx, currentCID(), 0, 0)
		_, _ = graph.vegReport.GetLongVegetationReportScope(ctx, currentCID())
	})
	// 9. EnvironmentReportService
	spawn(func() {
		_, _ = graph.envReport.GetLongEnvironmentOptions(ctx, currentCID())
		_, _ = graph.envReport.GetSubzoneMatrixReview(ctx, currentCID())
	})
	// 10. SpatialService (including PMTilesAttributor intersection)
	spawn(func() {
		_, _ = graph.spatial.GetCoordinateMode(ctx)
		_, _ = graph.spatial.GetPMTilesManifest(ctx)
		_, _ = graph.spatial.SuggestSpatialAttributes(ctx, 54.0, -125.0)
		_, _ = graph.spatial.GetPlotLocationReview(ctx, currentCID())
	})
	// 11. PictureService
	spawn(func() {
		_, _ = graph.pictures.GetMetadata(ctx, currentCID(), "00337")
	})
	// 12. HelpService
	spawn(func() {
		_, _ = graph.help.GetAboutInfo(ctx)
		_, _ = graph.help.GetLibraryStamps(ctx)
		_, _ = graph.help.SearchHelp(ctx, "moisture")
	})
	// Cross-service atomic publication observer: once ContextService is live, downstream services must never be uninitialized.
	spawn(func() {
		if _, sErr := graph.context.GetState(ctx); sErr == nil {
			if _, cErr := graph.spatial.GetCoordinateMode(ctx); cErr != nil && strings.Contains(cErr.Error(), "unavailable") {
				recordFailure("partial service swap observed: ContextService ready while SpatialService.GetCoordinateMode returned: " + cErr.Error())
			}
			if _, hErr := graph.help.GetAboutInfo(ctx); hErr != nil && strings.Contains(hErr.Error(), "unavailable") {
				recordFailure("partial service swap observed: ContextService ready while HelpService.GetAboutInfo returned: " + hErr.Error())
			}
			if _, pErr := graph.plotEntry.GetHeaderCapabilities(ctx); pErr != nil && strings.Contains(pErr.Error(), "unavailable") {
				recordFailure("partial service swap observed: ContextService ready while PlotEntryService.GetHeaderCapabilities returned: " + pErr.Error())
			}
		}
	})

	cfgPath := filepath.Join(configDir, "config.yml")

	// Phase 1: Simulated failure mid-activation on both ResetStartupToSample and RecoverStartupWithPaths.
	failMidActivation.Store(true)
	if _, err := graph.lifecycle.ResetStartupToSample(ctx); err == nil {
		close(stop)
		wg.Wait()
		t.Fatal("expected ResetStartupToSample to fail when picture library initialization fails mid-activation")
	}
	if _, err := graph.lifecycle.RecoverStartupWithPaths(ctx, StartupRecoveryRequest{
		ProjectPath:    relocatedSamplePath,
		ProjectName:    "Sample",
		ClearSU:        true,
		ClearHierarchy: true,
	}); err == nil {
		close(stop)
		wg.Wait()
		t.Fatal("expected RecoverStartupWithPaths to fail when picture library initialization fails mid-activation")
	}
	if graph.lifecycle.GetStartupState().Ready {
		close(stop)
		wg.Wait()
		t.Fatal("expected Ready=false after aborted activations")
	}

	// Phase 2: Succeeding ResetStartupToSample under concurrent 12-service RPC load.
	everPublished.Store(true)
	failMidActivation.Store(false)
	resetState, err := graph.lifecycle.ResetStartupToSample(ctx)
	if err != nil || !resetState.Ready {
		close(stop)
		wg.Wait()
		t.Fatalf("ResetStartupToSample failed: state=%+v err=%v", resetState, err)
	}

	// Phase 3: Repeated RecoverStartupWithPaths + ResetStartupToSample hot-swaps (with mid-activation failure interleaved).
	for round := 0; round < 2; round++ {
		activeBeforeAbort, err := graph.context.GetState(ctx)
		if err != nil {
			close(stop)
			wg.Wait()
			t.Fatalf("GetState after activation failed (round %d): %v", round, err)
		}

		// Re-enter recovery mode while active runtime continues serving concurrent RPCs,
		// and verify a mid-activation failure preserves the existing live ContextService untouched.
		writeBrokenProjectConfig(t, cfgPath, baseCfg, filepath.Join(dataDir, "projects", "MissingAgain.db"))
		graph.lifecycle.startup.SetState(StartupState{
			Ready:          false,
			ConfigPath:     cfgPath,
			ReleaseChannel: vprocorepkg.ReleaseChannelStable,
		})

		failMidActivation.Store(true)
		if _, err := graph.lifecycle.RecoverStartupWithPaths(ctx, StartupRecoveryRequest{
			ProjectPath:    relocatedSamplePath,
			ProjectName:    "Sample",
			ClearSU:        true,
			ClearHierarchy: true,
		}); err == nil {
			close(stop)
			wg.Wait()
			t.Fatalf("expected simulated mid-activation failure on RecoverStartupWithPaths (round %d)", round)
		}
		stillActive, err := graph.context.GetState(ctx)
		if err != nil || stillActive.ContextID != activeBeforeAbort.ContextID {
			close(stop)
			wg.Wait()
			t.Fatalf("mid-activation abort mutated live ContextService: before=%q after=%q err=%v",
				activeBeforeAbort.ContextID, stillActive.ContextID, err)
		}

		// Now let RecoverStartupWithPaths succeed and hot-swap all 12 services atomically.
		failMidActivation.Store(false)
		recoveredState, err := graph.lifecycle.RecoverStartupWithPaths(ctx, StartupRecoveryRequest{
			ProjectPath:    relocatedSamplePath,
			ProjectName:    "Sample",
			ClearSU:        true,
			ClearHierarchy: true,
		})
		if err != nil || !recoveredState.Ready {
			close(stop)
			wg.Wait()
			t.Fatalf("RecoverStartupWithPaths failed (round %d): state=%+v err=%v", round, recoveredState, err)
		}

		// Hot-swap back via ResetStartupToSample as well.
		writeBrokenProjectConfig(t, cfgPath, baseCfg, filepath.Join(dataDir, "projects", "MissingReset.db"))
		graph.lifecycle.startup.SetState(StartupState{
			Ready:          false,
			ConfigPath:     cfgPath,
			ReleaseChannel: vprocorepkg.ReleaseChannelStable,
		})
		if st, err := graph.lifecycle.ResetStartupToSample(ctx); err != nil || !st.Ready {
			close(stop)
			wg.Wait()
			t.Fatalf("ResetStartupToSample hot-swap failed (round %d): state=%+v err=%v", round, st, err)
		}
	}

	close(stop)
	wg.Wait()

	if msg, ok := failureChannel.Load().(string); ok && msg != "" {
		t.Fatal(msg)
	}
}

func TestFailedActivateRuntimeNeverMutatesContextService(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	_, baseCfg := seedRecoveryBrokenConfig(t, dataDir, configDir)
	cfgPath := filepath.Join(configDir, "config.yml")

	refs := openReferenceCatalogBundle(dataDir)
	defer refs.Close()
	cloud := NewCloudSyncManager(configDir)
	defer cloud.Close()

	var failPic atomic.Bool
	var midActivationHook func()
	var hookMu sync.Mutex
	missingPicPath := filepath.Join(t.TempDir(), "unopenable", "VPics.db")
	lookupEnv := func(key string) (string, bool) {
		if key == "VPRO_PICTURE_LIBRARY_PATH" && failPic.Load() {
			hookMu.Lock()
			fn := midActivationHook
			hookMu.Unlock()
			if fn != nil {
				fn()
			}
			return missingPicPath, true
		}
		return os.LookupEnv(key)
	}

	graph := newWailsServiceGraph(dataDir, configDir, refs, cloud, nil, lookupEnv)
	defer graph.tracker.shutdown(refs, cloud)

	ctx := context.Background()

	// 1. Cold-boot recovery: inside buildPictureService (after openActiveProjectContext succeeded),
	// ContextService must still have nil core and must not transiently expose the unreferenced context.
	var sawMidActivationReady bool
	hookMu.Lock()
	midActivationHook = func() {
		if _, err := graph.context.GetState(ctx); err == nil {
			sawMidActivationReady = true
		}
		if unwrapContextService(graph.context) != nil {
			sawMidActivationReady = true
		}
	}
	hookMu.Unlock()
	failPic.Store(true)

	if _, err := graph.lifecycle.ResetStartupToSample(ctx); err == nil {
		t.Fatal("expected ResetStartupToSample to fail when buildPictureService fails")
	}
	if sawMidActivationReady {
		t.Fatal("activateRuntime mutated ContextService before all dependent services were constructed")
	}
	if unwrapContextService(graph.context) != nil {
		t.Fatal("expected ContextService core to remain nil after failed initial activation")
	}

	// 2. Activate cleanly once, then trigger a second activation that aborts mid-way:
	// ContextService must retain the original ContextID both mid-activation and after abort.
	failPic.Store(false)
	if _, err := graph.lifecycle.ResetStartupToSample(ctx); err != nil {
		t.Fatalf("ResetStartupToSample clean activation failed: %v", err)
	}
	origState, err := graph.context.GetState(ctx)
	if err != nil || origState.ContextID == "" {
		t.Fatalf("expected active ContextState, got %+v (%v)", origState, err)
	}

	var midActivationContextID string
	var midActivationErr error
	hookMu.Lock()
	midActivationHook = func() {
		st, gErr := graph.context.GetState(ctx)
		midActivationContextID = st.ContextID
		midActivationErr = gErr
	}
	hookMu.Unlock()

	writeBrokenProjectConfig(t, cfgPath, baseCfg, filepath.Join(dataDir, "projects", "Missing.db"))
	graph.lifecycle.startup.SetState(StartupState{
		Ready:          false,
		ConfigPath:     cfgPath,
		ReleaseChannel: vprocorepkg.ReleaseChannelStable,
	})
	failPic.Store(true)
	if _, err := graph.lifecycle.ResetStartupToSample(ctx); err == nil {
		t.Fatal("expected second ResetStartupToSample to fail mid-activation")
	}
	if midActivationErr != nil || midActivationContextID != origState.ContextID {
		t.Fatalf("ContextService mutated mid-activation: got (%q, %v), want (%q, nil)",
			midActivationContextID, midActivationErr, origState.ContextID)
	}
	afterAbort, err := graph.context.GetState(ctx)
	if err != nil || afterAbort.ContextID != origState.ContextID {
		t.Fatalf("ContextService mutated or wiped on abort: got (%q, %v), want (%q, nil)",
			afterAbort.ContextID, err, origState.ContextID)
	}
}

func TestInFlightSpatialAttributorNotClosedUntilRPCLeaseReleases(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	seedRecoveryBrokenConfig(t, dataDir, configDir)

	refs := openReferenceCatalogBundle(dataDir)
	defer refs.Close()
	cloud := NewCloudSyncManager(configDir)
	defer cloud.Close()

	graph := newWailsServiceGraph(dataDir, configDir, refs, cloud, nil, os.LookupEnv)
	defer graph.tracker.shutdown(refs, cloud)

	ctx := context.Background()
	// Warm up initialAttributor's embedded PMTiles overview reader.
	if _, err := graph.spatial.SuggestSpatialAttributes(ctx, 54.0, -125.0); err != nil {
		t.Fatalf("initial SuggestSpatialAttributes failed: %v", err)
	}

	// Simulate an in-flight SpatialService RPC holding a reference lease to the initial runtimeBundle.
	heldBundle, releaseHeld := graph.tracker.acquire()
	if heldBundle == nil || heldBundle.spatial == nil {
		t.Fatal("expected non-nil initial runtimeBundle")
	}

	// Hot-swap runtime via ResetStartupToSample while heldBundle still has refs == 1.
	if _, err := graph.lifecycle.ResetStartupToSample(ctx); err != nil {
		releaseHeld()
		t.Fatalf("ResetStartupToSample failed: %v", err)
	}

	graph.tracker.mu.Lock()
	retiredDuringLease := heldBundle.retired
	closedDuringLease := heldBundle.closed
	refsDuringLease := heldBundle.refs
	graph.tracker.mu.Unlock()
	if !retiredDuringLease || closedDuringLease || refsDuringLease != 1 {
		releaseHeld()
		t.Fatalf("expected retired=true closed=false refs=1 while RPC lease held; got retired=%v closed=%v refs=%d",
			retiredDuringLease, closedDuringLease, refsDuringLease)
	}

	// Both the in-flight old bundle and the newly published SpatialService must serve SuggestSpatialAttributes race-free.
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < 25; i++ {
			if _, err := heldBundle.spatial.SuggestSpatialAttributes(ctx, 54.0, -125.0); err != nil {
				t.Errorf("in-flight SuggestSpatialAttributes failed: %v", err)
				return
			}
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 25; i++ {
			if _, err := graph.spatial.SuggestSpatialAttributes(ctx, 54.0, -125.0); err != nil {
				t.Errorf("swapped SuggestSpatialAttributes failed: %v", err)
				return
			}
		}
	}()
	wg.Wait()

	// Releasing the last in-flight RPC lease must retire and close the previous bundle's owned resources.
	releaseHeld()
	releaseHeld() // idempotent via sync.Once

	graph.tracker.mu.Lock()
	closedAfterRelease := heldBundle.closed
	refsAfterRelease := heldBundle.refs
	graph.tracker.mu.Unlock()
	if !closedAfterRelease || refsAfterRelease != 0 {
		t.Fatalf("expected closed=true refs=0 after releasing last lease; got closed=%v refs=%d",
			closedAfterRelease, refsAfterRelease)
	}
}

func TestAllTwelveWailsServicesSafeAcrossEveryExportedRPCInRecoveryAndShutdown(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	seedRecoveryBrokenConfig(t, dataDir, configDir)

	refs := openReferenceCatalogBundle(dataDir)
	defer refs.Close()
	cloud := NewCloudSyncManager(configDir)
	defer cloud.Close()
	closeSvc, err := lifecyclepkg.NewCloseService(func(string) bool { return false }, func() {})
	if err != nil {
		t.Fatalf("NewCloseService: %v", err)
	}

	graph := newWailsServiceGraph(dataDir, configDir, refs, cloud, closeSvc, os.LookupEnv)

	services := []any{
		graph.lifecycle,
		graph.context,
		graph.plotEntry,
		graph.datasheet,
		graph.classification,
		graph.validation,
		graph.importExport,
		graph.vegReport,
		graph.envReport,
		graph.spatial,
		graph.pictures,
		graph.help,
	}

	ctxType := reflect.TypeOf((*context.Context)(nil)).Elem()
	bgCtx := context.Background()
	cancelledCtx, cancel := context.WithCancel(bgCtx)
	cancel()

	skipLifecycleMutators := map[string]bool{
		"ResetStartupToSample":    true,
		"RecoverStartupWithPaths": true,
		"ServiceShutdown":         true,
		"ConfirmClose":            true,
		"CancelClose":             true,
	}

	sweepAllMethods := func(phase string) int {
		invoked := 0
		for _, svc := range services {
			rv := reflect.ValueOf(svc)
			rt := rv.Type()
			isLifecycle := rt == reflect.TypeOf(graph.lifecycle)
			for i := 0; i < rt.NumMethod(); i++ {
				m := rt.Method(i)
				if isLifecycle && skipLifecycleMutators[m.Name] {
					continue
				}
				useCancelled := strings.HasPrefix(m.Name, "Choose") ||
					strings.HasPrefix(m.Name, "Reveal") ||
					strings.Contains(m.Name, "RRuntime") ||
					strings.Contains(m.Name, "Quarto") ||
					strings.Contains(m.Name, "Clustering") ||
					strings.Contains(m.Name, "Climate") ||
					strings.Contains(m.Name, "Cloud") ||
					strings.Contains(m.Name, "BECMaster") ||
					strings.Contains(m.Name, "Staging")
				mt := m.Type
				args := make([]reflect.Value, mt.NumIn()-1)
				for a := 1; a < mt.NumIn(); a++ {
					pt := mt.In(a)
					if pt == ctxType {
						if useCancelled {
							args[a-1] = reflect.ValueOf(cancelledCtx)
						} else {
							args[a-1] = reflect.ValueOf(bgCtx)
						}
					} else if pt == reflect.TypeOf("") {
						args[a-1] = reflect.ValueOf("stale-cid")
					} else {
						args[a-1] = reflect.Zero(pt)
					}
				}
				func() {
					defer func() {
						if r := recover(); r != nil {
							t.Fatalf("%s: %s.%s panicked with %v", phase, rt.Elem().Name(), m.Name, r)
						}
					}()
					_ = rv.Method(i).Call(args)
				}()
				invoked++
			}
		}
		return invoked
	}

	recoveryCount := sweepAllMethods("recovery")
	if recoveryCount < 550 {
		t.Fatalf("expected >= 550 exported Wails RPC methods across 12 services, invoked %d", recoveryCount)
	}

	graph.tracker.shutdown(refs, cloud)
	shutdownCount := sweepAllMethods("post-shutdown")
	if shutdownCount != recoveryCount {
		t.Fatalf("post-shutdown sweep count %d != recovery count %d", shutdownCount, recoveryCount)
	}
}
