package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	picturespkg "github.com/boostao/vpro/app/internal/pictures"

	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	"github.com/boostao/vpro/app/internal/projectops"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
	"github.com/wailsapp/wails/v3/pkg/application"
)

func openTestDesktopServices(t *testing.T) ([]application.Service, wailsServiceGraph, string, string) {
	t.Helper()
	dataDir := t.TempDir()
	configDir := t.TempDir()
	refs := openReferenceCatalogBundle(dataDir)
	cloud := NewCloudSyncManager(configDir)
	closeSvc, err := lifecyclepkg.NewCloseService(func(string) bool { return false }, func() {})
	if err != nil {
		refs.Close()
		cloud.Close()
		t.Fatalf("NewCloseService: %v", err)
	}
	emptyEnv := func(string) (string, bool) { return "", false }
	services, graph := buildDesktopServices(dataDir, configDir, refs, cloud, closeSvc, emptyEnv)
	t.Cleanup(func() {
		graph.tracker.shutdown(refs, cloud)
	})
	return services, graph, dataDir, configDir
}

func findRegisteredService[T any](t *testing.T, services []application.Service) *T {
	t.Helper()
	wantType := reflect.TypeOf((*T)(nil))
	var found *T
	count := 0
	for _, svc := range services {
		if typed, ok := svc.Instance().(*T); ok {
			found = typed
			count++
		}
	}
	if count != 1 || found == nil {
		t.Fatalf("expected strictly 1 registered %s in desktopServices, got count=%d ptr=%v", wantType, count, found)
	}
	return found
}

func TestMainRegistersStrictlyTwelveCohesiveDomainServices(t *testing.T) {
	services, graph, dataDir, configDir := openTestDesktopServices(t)
	if len(services) != 12 {
		t.Fatalf("buildDesktopServices must register strictly 12 cohesive domain services; got len=%d", len(services))
	}

	wantTypes := []reflect.Type{
		reflect.TypeOf((*LifecycleService)(nil)),
		reflect.TypeOf((*ContextService)(nil)),
		reflect.TypeOf((*PlotEntryService)(nil)),
		reflect.TypeOf((*DatasheetService)(nil)),
		reflect.TypeOf((*ClassificationService)(nil)),
		reflect.TypeOf((*ValidationService)(nil)),
		reflect.TypeOf((*ImportExportService)(nil)),
		reflect.TypeOf((*VegetationReportService)(nil)),
		reflect.TypeOf((*EnvironmentReportService)(nil)),
		reflect.TypeOf((*SpatialService)(nil)),
		reflect.TypeOf((*PictureService)(nil)),
		reflect.TypeOf((*HelpService)(nil)),
	}

	seenPtrs := make(map[uintptr]bool, len(services))
	for idx, svc := range services {
		inst := svc.Instance()
		if inst == nil {
			t.Fatalf("service[%d] has nil Instance()", idx)
		}
		rv := reflect.ValueOf(inst)
		if rv.Kind() != reflect.Ptr || rv.IsNil() {
			t.Fatalf("service[%d] (%T) must be a non-nil struct pointer", idx, inst)
		}
		if rv.Type() != wantTypes[idx] {
			t.Fatalf("service[%d] type = %s, want %s", idx, rv.Type(), wantTypes[idx])
		}
		ptr := rv.Pointer()
		if seenPtrs[ptr] {
			t.Fatalf("service[%d] (%s) registered a duplicate service instance pointer", idx, rv.Type())
		}
		seenPtrs[ptr] = true

		// Every bound Wails RPC method must accept/return JSON-serializable types (zero func/chan parameters).
		rt := rv.Type()
		for mIdx := 0; mIdx < rt.NumMethod(); mIdx++ {
			m := rt.Method(mIdx)
			mt := m.Type
			for p := 1; p < mt.NumIn(); p++ {
				if kind := mt.In(p).Kind(); kind == reflect.Func || kind == reflect.Chan {
					t.Fatalf("%s.%s parameter %d has non-RPC kind %s (%s)", rt, m.Name, p, kind, mt.In(p))
				}
			}
			for r := 0; r < mt.NumOut(); r++ {
				if kind := mt.Out(r).Kind(); kind == reflect.Func || kind == reflect.Chan {
					t.Fatalf("%s.%s return %d has non-RPC kind %s (%s)", rt, m.Name, r, kind, mt.Out(r))
				}
			}
		}
	}

	ctx := context.Background()
	lifecycleSvc := findRegisteredService[LifecycleService](t, services)
	contextSvc := findRegisteredService[ContextService](t, services)
	plotEntrySvc := findRegisteredService[PlotEntryService](t, services)
	datasheetSvc := findRegisteredService[DatasheetService](t, services)
	classificationSvc := findRegisteredService[ClassificationService](t, services)
	validationSvc := findRegisteredService[ValidationService](t, services)
	importExportSvc := findRegisteredService[ImportExportService](t, services)
	vegReportSvc := findRegisteredService[VegetationReportService](t, services)
	envReportSvc := findRegisteredService[EnvironmentReportService](t, services)
	spatialSvc := findRegisteredService[SpatialService](t, services)
	pictureSvc := findRegisteredService[PictureService](t, services)
	helpSvc := findRegisteredService[HelpService](t, services)

	startup := lifecycleSvc.GetStartupState()
	if !startup.Ready || startup.ReleaseChannel != vprocorepkg.ReleaseChannelStable {
		t.Fatalf("expected cold-boot desktop services Ready=true in stable channel, got %+v", startup)
	}

	state, err := contextSvc.GetState(ctx)
	if err != nil || state.ContextID == "" || state.ActiveProject != "Sample" {
		t.Fatalf("ContextService.GetState failed: state=%+v err=%v", state, err)
	}

	// Verify real RPC dispatch across all 12 registered services, including TwoPageVegetationService on PlotEntryService.
	if orig, err := plotEntrySvc.GetTwoPageVegetationOriginal(ctx, state.ContextID, "108050", "SubVegAXL_BC"); err != nil || orig == nil {
		t.Fatalf("PlotEntryService.GetTwoPageVegetationOriginal failed: orig=%+v err=%v", orig, err)
	}
	if refs, err := plotEntrySvc.GetTwoPageVegetationSpeciesReferences(ctx, state.ContextID, "108050", "SubVegAXL_BC"); err != nil || refs == nil {
		t.Fatalf("PlotEntryService.GetTwoPageVegetationSpeciesReferences failed: refs=%+v err=%v", refs, err)
	}
	if tables, err := datasheetSvc.ListDatasheetTables(ctx, state.ContextID); err != nil || len(tables) == 0 {
		t.Fatalf("DatasheetService.ListDatasheetTables failed: len=%d err=%v", len(tables), err)
	}
	if becStatus, err := classificationSvc.GetBECCatalogueStatus(ctx); err != nil || becStatus.SiteSeriesRows == 0 {
		t.Fatalf("ClassificationService.GetBECCatalogueStatus failed: status=%+v err=%v", becStatus, err)
	}
	if _, err := validationSvc.CheckSpeciesCodes(ctx, state.ContextID); err != nil {
		t.Fatalf("ValidationService.CheckSpeciesCodes failed: %v", err)
	}
	if preview, err := importExportSvc.GetPlotLabelRegionalPreview(ctx, state.ContextID, "108050"); err != nil || preview == nil {
		t.Fatalf("ImportExportService.GetPlotLabelRegionalPreview failed: preview=%+v err=%v", preview, err)
	}
	if scope, err := vegReportSvc.GetLongVegetationReportScope(ctx, state.ContextID); err != nil || scope == nil || scope.Project != "Sample" {
		t.Fatalf("VegetationReportService.GetLongVegetationReportScope failed: scope=%+v err=%v", scope, err)
	}
	if _, err := envReportSvc.GetLongEnvironmentOptions(ctx, state.ContextID); err != nil {
		t.Fatalf("EnvironmentReportService.GetLongEnvironmentOptions failed: %v", err)
	}
	if _, err := spatialSvc.GetCoordinateMode(ctx); err != nil {
		t.Fatalf("SpatialService.GetCoordinateMode failed: %v", err)
	}
	if picMeta, err := pictureSvc.GetMetadata(ctx, state.ContextID, "108050"); err != nil || picMeta == nil {
		t.Fatalf("PictureService.GetMetadata failed: meta=%+v err=%v", picMeta, err)
	}
	if about, err := helpSvc.GetAboutInfo(ctx); err != nil || about.ProductName != "VPro" {
		t.Fatalf("HelpService.GetAboutInfo failed: about=%+v err=%v", about, err)
	}

	// Verify startup recovery RPCs hot-swap the bound service graph cleanly.
	cfgPath := filepath.Join(configDir, "config.yml")
	rawCfg, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatalf("read config.yml: %v", err)
	}
	writeBrokenProjectConfig(t, cfgPath, rawCfg, filepath.Join(dataDir, "projects", "Missing.db"))
	graph.lifecycle.startup.SetState(StartupState{
		Ready:          false,
		ConfigPath:     cfgPath,
		ReleaseChannel: vprocorepkg.ReleaseChannelStable,
	})
	recovered, err := lifecycleSvc.RecoverStartupWithPaths(ctx, StartupRecoveryRequest{
		ProjectPath:    filepath.Join(dataDir, "projects", "Sample.db"),
		ProjectName:    "Sample",
		ClearSU:        true,
		ClearHierarchy: true,
	})
	if err != nil || !recovered.Ready {
		t.Fatalf("LifecycleService.RecoverStartupWithPaths failed: state=%+v err=%v", recovered, err)
	}
	swappedState, err := contextSvc.GetState(ctx)
	if err != nil || swappedState.ContextID == "" || swappedState.ContextID == state.ContextID {
		t.Fatalf("expected fresh ContextID after RecoverStartupWithPaths, got before=%q after=%q err=%v",
			state.ContextID, swappedState.ContextID, err)
	}
	if orig, err := plotEntrySvc.GetTwoPageVegetationOriginal(ctx, swappedState.ContextID, "108050", "SubVegAXL_BC"); err != nil || orig == nil {
		t.Fatalf("PlotEntryService after hot-swap failed: orig=%+v err=%v", orig, err)
	}
}

func TestHelpServiceProvides2026LibraryStampsAboutAndReleaseChannel(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	preferences, err := vprocorepkg.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatal(err)
	}
	help, err := NewHelpService(preferences)
	if err != nil {
		t.Fatal(err)
	}
	stamps, err := help.GetLibraryStamps(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if stamps.SchemaVersion != 1 ||
		!strings.HasPrefix(stamps.BECVersion, "BECdb_v13_2026") ||
		len(stamps.BECArchiveSHA256) != 64 ||
		len(stamps.BECExtractedSHA256) != 64 ||
		!strings.HasPrefix(stamps.TaxonomyVersion, "BCPlantTaxa_v19_2025") ||
		len(stamps.TaxonomyArchiveSHA256) != 64 ||
		len(stamps.TaxonomyExtractedSHA256) != 64 ||
		stamps.LMH25Edition != "LMH25 (2023)" ||
		len(stamps.LMH25PDFSHA256) != 64 ||
		len(stamps.Artifacts) != 7 {
		t.Fatalf("unexpected 2026 library stamps: %+v", stamps)
	}
	stamps.Sources[0].Version = "mutated"
	stamps.Artifacts[0].Counts["MasterSiteUnitList"] = -1
	fresh, err := help.GetLibraryStamps(context.Background())
	if err != nil || fresh.Sources[0].Version == "mutated" || fresh.Artifacts[0].Counts["MasterSiteUnitList"] != 6067 {
		t.Fatalf("GetLibraryStamps aliased internal slice/map state: %+v %v", fresh, err)
	}

	channel, err := help.GetReleaseChannel(context.Background())
	if err != nil || channel != vprocorepkg.ReleaseChannelStable {
		t.Fatalf("expected default stable release channel, got %q (%v)", channel, err)
	}
	raw, err := os.ReadFile(filepath.Join(configDir, "config.yml"))
	if err != nil {
		t.Fatal(err)
	}
	updated := strings.Replace(string(raw), "release_channel: stable", "release_channel: experimental", 1)
	if err := os.WriteFile(filepath.Join(configDir, "config.yml"), []byte(updated), 0600); err != nil {
		t.Fatal(err)
	}
	about, err := help.GetAboutInfo(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if about.ProductName != "VPro" || about.SchemaVersion != "VP08" || about.ReleaseChannel != vprocorepkg.ReleaseChannelExperimental ||
		!strings.Contains(about.Organization, "Ministry of Forests") {
		t.Fatalf("unexpected AboutInfo: %+v", about)
	}

	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := help.GetLibraryStamps(cancelled); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled on GetLibraryStamps, got %v", err)
	}
	if _, err := help.GetReleaseChannel(cancelled); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled on GetReleaseChannel, got %v", err)
	}
}

func TestLifecycleServiceConsolidatesStartupAndCloseHandshake(t *testing.T) {
	var emitted string
	var quitCalled int
	closeSvc, err := lifecyclepkg.NewCloseService(
		func(nonce string) bool { emitted = nonce; return false },
		func() { quitCalled++ },
	)
	if err != nil {
		t.Fatal(err)
	}
	startupSvc := &lifecyclepkg.StartupService{State: StartupState{
		Ready:          true,
		ConfigPath:     `C:\config\config.yml`,
		ReleaseChannel: vprocorepkg.ReleaseChannelStable,
	}}
	lifecycle := NewLifecycleService(startupSvc, closeSvc, nil)
	state := lifecycle.GetStartupState()
	if !state.Ready || state.ReleaseChannel != vprocorepkg.ReleaseChannelStable {
		t.Fatalf("unexpected startup state: %+v", state)
	}
	if closeSvc.ShouldQuit() {
		t.Fatal("close should remain blocked until pending nonce is confirmed")
	}
	pending := lifecycle.GetPendingCloseRequest()
	if pending == "" || pending != emitted {
		t.Fatalf("expected emitted nonce %q to match pending %q", emitted, pending)
	}
	if err := lifecycle.CancelClose("forged"); !errors.Is(err, lifecyclepkg.ErrInvalidCloseRequest) {
		t.Fatalf("forged nonce must be rejected, got %v", err)
	}
	if err := lifecycle.CancelClose(pending); err != nil || lifecycle.GetPendingCloseRequest() != "" {
		t.Fatalf("CancelClose failed: %v", err)
	}
	if closeSvc.ShouldQuit() {
		t.Fatal("close should mint a fresh nonce after cancellation")
	}
	next := lifecycle.GetPendingCloseRequest()
	if next == "" || next == pending {
		t.Fatalf("expected fresh nonce after cancel, got %q vs %q", next, pending)
	}
	if err := lifecycle.ConfirmClose(next); err != nil || quitCalled != 1 || !closeSvc.ShouldQuit() {
		t.Fatalf("ConfirmClose did not approve native quit: err=%v quitCalled=%d", err, quitCalled)
	}
}

func resolveExternalArchiveRootForTest() string {
	if env, ok := os.LookupEnv("VPRO_EXTERNAL_ARCHIVE_ROOT"); ok {
		return strings.TrimSpace(env)
	}
	if repoRoot := resources.RepoRoot(); repoRoot != "" {
		return filepath.Dir(filepath.Dir(repoRoot))
	}
	return ""
}

func TestImportAccessProjectRenamedAuditAndChildLoadingViaPlotEntryService(t *testing.T) {
	ctx := context.Background()

	// 1. Always-run CI-hermetic renamed project audit + child loading verification via SaveProjectAs + PlotEntryService.
	services, _, dataDir, _ := openTestDesktopServices(t)
	contextSvc := findRegisteredService[ContextService](t, services)
	plotEntrySvc := findRegisteredService[PlotEntryService](t, services)
	importExportSvc := findRegisteredService[ImportExportService](t, services)

	initState, err := contextSvc.GetState(ctx)
	if err != nil {
		t.Fatal(err)
	}
	firstPlot := "108050"
	hdr, err := plotEntrySvc.GetPlot(ctx, firstPlot)
	if err != nil {
		t.Fatalf("PlotEntryService.GetPlot(%s): %v", firstPlot, err)
	}
	seedNote := "Hermetic pre-rename audit seed"
	hdr.OfficeNotes = &seedNote
	if err := contextSvc.UpdatePlot(ctx, initState.ContextID, *hdr); err != nil {
		t.Fatalf("UpdatePlot(%s) seed failed: %v", firstPlot, err)
	}

	renamedProject := "SampleRenamed"
	renamedDest := filepath.Join(dataDir, "projects", renamedProject+".db")
	savedRes, err := contextSvc.SaveProjectAs(ctx, initState.ContextID, projectops.SaveProjectAsRequest{
		NewProjectName:    renamedProject,
		DestinationPath:   renamedDest,
		ActivateOnSuccess: true,
	})
	if err != nil || !savedRes.Activated || savedRes.State == nil || savedRes.State.ActiveProject != renamedProject {
		t.Fatalf("SaveProjectAs(%s) failed: res=%+v err=%v", renamedProject, savedRes, err)
	}
	renamedCID := savedRes.State.ContextID
	auditEntries, err := plotEntrySvc.ListAuditReadEntries(ctx, firstPlot)
	if err != nil || len(auditEntries) == 0 {
		t.Fatalf("ListAuditReadEntries on %s failed: len=%d err=%v", renamedProject, len(auditEntries), err)
	}
	for _, entry := range auditEntries {
		if entry.Project != renamedProject {
			t.Fatalf("audit row %s retained foreign Project=%q instead of %q", entry.RowID, entry.Project, renamedProject)
		}
	}
	postRenameHdr, err := plotEntrySvc.GetPlot(ctx, firstPlot)
	if err != nil {
		t.Fatal(err)
	}
	afterNote := "Hermetic post-rename audit edit"
	postRenameHdr.OfficeNotes = &afterNote
	if err := contextSvc.UpdatePlot(ctx, renamedCID, *postRenameHdr); err != nil {
		t.Fatalf("UpdatePlot on renamed project failed: %v", err)
	}
	afterAudits, err := contextSvc.ListAuditReadEntries(ctx, renamedCID, firstPlot)
	if err != nil || len(afterAudits) <= len(auditEntries) {
		t.Fatalf("expected additional audit entry after UpdatePlot, before=%d after=%d err=%v", len(auditEntries), len(afterAudits), err)
	}

	// 2. Optional read-only sibling Access archive check when VPRO_EXTERNAL_ARCHIVE_ROOT / sibling archives exist on disk.
	archiveRoot := resolveExternalArchiveRootForTest()
	if archiveRoot == "" {
		return
	}
	candidates := []struct {
		relPath       string
		sourceProject string
		targetProject string
	}{
		{
			relPath:       filepath.Join("VPRO_ACCESS_1", "VPro64", "Haida_Gwaii_2019.accdb"),
			sourceProject: "Haida_Gwaii_VPro19_2019",
			targetProject: "Haida2019",
		},
		{
			relPath:       filepath.Join("VPRO_ACCESS", "VPro64", "VPro64.accdb"),
			sourceProject: "Sample",
			targetProject: "AccessRenamed",
		},
	}
	var chosenPath, sourceProject, targetProject string
	for _, cand := range candidates {
		full := filepath.Join(archiveRoot, cand.relPath)
		if _, statErr := os.Stat(full); statErr == nil {
			chosenPath = full
			sourceProject = cand.sourceProject
			targetProject = cand.targetProject
			break
		}
	}
	if chosenPath == "" {
		return
	}

	t.Run("OptionalLocalAccessArchive", func(t *testing.T) {
		curState, err := contextSvc.GetState(ctx)
		if err != nil {
			t.Fatal(err)
		}
		destPath := filepath.Join(dataDir, "projects", targetProject+".db")
		impRes, err := importExportSvc.ImportAccessProject(ctx, curState.ContextID, AccessProjectImportRequest{
			SourcePath:        chosenPath,
			SourceProject:     sourceProject,
			TargetProject:     targetProject,
			DestinationPath:   destPath,
			ActivateOnSuccess: true,
		})
		if err != nil {
			t.Fatalf("ImportAccessProject(%s -> %s) failed: %v", sourceProject, targetProject, err)
		}
		if !impRes.Activated || impRes.State == nil || impRes.State.ActiveProject != targetProject {
			t.Fatalf("expected activated %s state, got %+v", targetProject, impRes)
		}
		page, err := contextSvc.ListPlots(ctx, 0, 50)
		if err != nil || len(page.Plots) == 0 {
			t.Fatalf("ListPlots on renamed project failed: page=%+v err=%v", page, err)
		}
		totalAuditRows := 0
		for _, summary := range page.Plots {
			pNum := summary.PlotNumber
			if _, err := plotEntrySvc.GetPlot(ctx, pNum); err != nil {
				t.Fatalf("PlotEntryService.GetPlot(%s) failed: %v", pNum, err)
			}
			if _, err := plotEntrySvc.ListVegRecords(ctx, pNum); err != nil {
				t.Fatalf("PlotEntryService.ListVegRecords(%s) failed: %v", pNum, err)
			}
			if _, err := plotEntrySvc.ListHumusRecords(ctx, pNum); err != nil {
				t.Fatalf("PlotEntryService.ListHumusRecords(%s) failed: %v", pNum, err)
			}
			if _, err := plotEntrySvc.ListMineralRecords(ctx, pNum); err != nil {
				t.Fatalf("PlotEntryService.ListMineralRecords(%s) failed: %v", pNum, err)
			}
			if _, err := plotEntrySvc.ListOtherRecords(ctx, pNum); err != nil {
				t.Fatalf("PlotEntryService.ListOtherRecords(%s) failed: %v", pNum, err)
			}
			entries, err := plotEntrySvc.ListAuditReadEntries(ctx, pNum)
			if err != nil {
				t.Fatalf("PlotEntryService.ListAuditReadEntries(%s) failed: %v", pNum, err)
			}
			for _, entry := range entries {
				if entry.Project != targetProject {
					t.Fatalf("audit row %s for plot %s retained foreign Project=%q instead of %q", entry.RowID, pNum, entry.Project, targetProject)
				}
			}
			trail, err := plotEntrySvc.ListAuditEntries(ctx, pNum)
			if err != nil {
				t.Fatalf("PlotEntryService.ListAuditEntries(%s) failed: %v", pNum, err)
			}
			totalAuditRows += len(trail)
		}
		if totalAuditRows == 0 {
			t.Fatalf("expected non-zero audit trail rows across %s plots", targetProject)
		}
	})
}

func TestColdBootPictureLibraryWiringAndNilPictureServiceGuards(t *testing.T) {
	ctx := context.Background()

	var nilPic *PictureService
	if _, err := nilPic.GetMetadata(ctx, "cid", "00337"); err == nil {
		t.Fatal("expected nil PictureService.GetMetadata to return error without panic")
	}
	if _, err := nilPic.GetImage(ctx, "cid", "00337", "{}"); err == nil {
		t.Fatal("expected nil PictureService.GetImage to return error without panic")
	}

	dataDir := t.TempDir()
	configDir := t.TempDir()
	preferences, err := vprocorepkg.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatal(err)
	}
	projects, err := vprocorepkg.NewSQLiteProjectService(dataDir, configDir, preferences)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = projects.CloseSQLiteContext()
	})
	plots, err := vprocorepkg.NewPlotServiceWithPreferences(projects)
	if err != nil {
		t.Fatal(err)
	}
	contextSvc, err := NewContextService(projects, plots)
	if err != nil {
		t.Fatal(err)
	}
	state, err := projects.GetState(ctx)
	if err != nil {
		t.Fatal(err)
	}

	defaultVPicsPath, defaultImagesDir, err := vprocorepkg.EnsureDefaultPictureLibrary(dataDir)
	if err != nil {
		t.Fatalf("EnsureDefaultPictureLibrary failed: %v", err)
	}
	emptyEnv := func(string) (string, bool) { return "", false }
	picLookup := newDefaultPictureEnvLookup(emptyEnv, defaultVPicsPath, defaultImagesDir)

	picSvc, err := NewPictureService(contextSvc, picLookup)
	if err != nil {
		t.Fatalf("NewPictureService failed on cold boot: %v", err)
	}
	picMeta, err := NewPictureMetadataService(picSvc)
	if err != nil {
		t.Fatalf("NewPictureMetadataService failed on cold boot: %v", err)
	}
	picCreate, err := NewPictureCreationService(picSvc)
	if err != nil {
		t.Fatalf("NewPictureCreationService failed on cold boot: %v", err)
	}
	picDelete, err := NewPictureDeletionService(picSvc)
	if err != nil {
		t.Fatalf("NewPictureDeletionService failed on cold boot: %v", err)
	}
	picSvc.core.Metadata = picMeta
	picSvc.core.Creation = picCreate
	picSvc.core.Deletion = picDelete

	review, err := picSvc.GetMetadata(ctx, state.ContextID, "00337")
	if err != nil {
		t.Fatalf("GetMetadata on cold-boot seeded VPics.db failed: %v", err)
	}
	if review == nil || len(review.Records.Columns) != 5 || len(review.Records.Rows) != 0 {
		t.Fatalf("unexpected initial VPics metadata review: %+v", review)
	}

	missingLibrary := filepath.Join(t.TempDir(), "missing-vpics.db")
	overrideLookup := newDefaultPictureEnvLookup(func(key string) (string, bool) {
		if key == "VPRO_PICTURE_LIBRARY_PATH" {
			return missingLibrary, true
		}
		return "", false
	}, defaultVPicsPath, defaultImagesDir)
	if _, err := NewPictureService(contextSvc, overrideLookup); err == nil {
		t.Fatal("expected explicit VPRO_PICTURE_LIBRARY_PATH env override to take precedence over default")
	}
}

func TestContextServiceOmitsFuncParametersAndForwardsAllVProCoreRPCs(t *testing.T) {
	mainType := reflect.TypeOf(&ContextService{})
	coreType := reflect.TypeOf(&vprocorepkg.ContextService{})

	if _, hasEdit := mainType.MethodByName("Edit"); hasEdit {
		t.Fatal("main.ContextService must not expose Edit(string, func(*PlotService) error) error to Wails bindings")
	}
	for i := 0; i < mainType.NumMethod(); i++ {
		m := mainType.Method(i)
		mt := m.Type
		for p := 1; p < mt.NumIn(); p++ {
			if mt.In(p).Kind() == reflect.Func {
				t.Fatalf("main.ContextService.%s parameter %d is a func (%s), which triggers Wails JSON binding warning", m.Name, p, mt.In(p))
			}
		}
		for r := 0; r < mt.NumOut(); r++ {
			if mt.Out(r).Kind() == reflect.Func {
				t.Fatalf("main.ContextService.%s return %d is a func (%s)", m.Name, r, mt.Out(r))
			}
		}
	}

	ctxType := reflect.TypeOf((*context.Context)(nil)).Elem()
	for i := 0; i < coreType.NumMethod(); i++ {
		cm := coreType.Method(i)
		if cm.Name == "Edit" {
			continue
		}
		mm, ok := mainType.MethodByName(cm.Name)
		if !ok {
			t.Fatalf("main.ContextService is missing forwarded RPC method %s from vprocore.ContextService", cm.Name)
		}
		if mm.Type.NumIn() < 2 || mm.Type.In(1) != ctxType {
			t.Fatalf("main.ContextService.%s must accept context.Context as its first argument", cm.Name)
		}
		expectedIn := cm.Type.NumIn()
		if cm.Type.NumIn() < 2 || cm.Type.In(1) != ctxType {
			expectedIn++
		}
		if mm.Type.NumIn() != expectedIn || mm.Type.NumOut() != cm.Type.NumOut() {
			t.Fatalf("main.ContextService.%s arity (%d in, %d out) differs from expected (%d in, %d out)",
				cm.Name, mm.Type.NumIn(), mm.Type.NumOut(), expectedIn, cm.Type.NumOut())
		}
	}
}

func TestSpatialExtraDirsBehavioralResolutionAndDeduplication(t *testing.T) {
	existingDirA := t.TempDir()
	existingDirB := t.TempDir()
	configuredDir := t.TempDir()
	missingDir := filepath.Join(t.TempDir(), "does_not_exist")

	envList := strings.Join([]string{"", "   ", existingDirA, missingDir, existingDirB, existingDirA}, string(filepath.ListSeparator))
	dirs := resolveSpatialExtraDirs(func(key string) (string, bool) {
		if key == "VPRO_SPATIAL_ASSETS_DIR" {
			return envList, true
		}
		return "", false
	}, "", " . ", configuredDir, existingDirA, missingDir)

	seen := map[string]int{}
	for _, d := range dirs {
		seen[d]++
		if info, err := os.Stat(d); err != nil || !info.IsDir() {
			t.Fatalf("resolveSpatialExtraDirs returned non-existent or non-directory path %q: %v", d, err)
		}
	}
	for _, want := range []string{existingDirA, existingDirB, configuredDir} {
		if seen[want] != 1 {
			t.Fatalf("expected %q once in %v, got count=%d", want, dirs, seen[want])
		}
	}
	if seen[missingDir] != 0 {
		t.Fatalf("resolveSpatialExtraDirs must omit non-existent directory %q", missingDir)
	}
}

func newDefaultPictureEnvLookup(base func(string) (string, bool), defaultVPicsPath, defaultImagesDir string) func(string) (string, bool) {
	return func(key string) (string, bool) {
		if base != nil {
			if val, ok := base(key); ok {
				return val, true
			}
		}
		switch key {
		case "VPRO_PICTURE_LIBRARY_PATH":
			if defaultVPicsPath != "" {
				return defaultVPicsPath, true
			}
		case "VPRO_PICTURE_CHILD_DIRECTORY", "VPRO_PICTURE_MANAGER_DIRECTORY":
			if defaultImagesDir != "" {
				return defaultImagesDir, true
			}
		}
		return "", false
	}
}

func NewPictureService(contexts *ContextService, lookup func(string) (string, bool)) (*PictureService, error) {
	core, err := picturespkg.NewPictureService(unwrapContextService(contexts), lookup)
	if err != nil {
		return nil, err
	}
	return &PictureService{core: core}, nil
}
