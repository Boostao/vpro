package main

import (
	"embed"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	cloudsyncpkg "github.com/boostao/vpro/app/internal/cloudsync"
	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	referencespkg "github.com/boostao/vpro/app/internal/references"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

func resolveSpatialExtraDirs(lookup func(string) (string, bool), configured ...string) []string {
	var candidates []string
	if lookup != nil {
		if envDir, ok := lookup("VPRO_SPATIAL_ASSETS_DIR"); ok && strings.TrimSpace(envDir) != "" {
			for _, item := range filepath.SplitList(envDir) {
				if trimmed := strings.TrimSpace(item); trimmed != "" {
					candidates = append(candidates, trimmed)
				}
			}
		}
	}
	for _, raw := range configured {
		if trimmed := strings.TrimSpace(raw); trimmed != "" {
			candidates = append(candidates, trimmed)
		}
	}
	if repoRoot := resources.RepoRoot(); strings.TrimSpace(repoRoot) != "" {
		candidates = append(candidates, filepath.Join(filepath.Dir(repoRoot), "spatial_assets"))
	}
	if exePath, err := os.Executable(); err == nil && strings.TrimSpace(exePath) != "" {
		resolvedExe := exePath
		if eval, evalErr := filepath.EvalSymlinks(exePath); evalErr == nil && eval != "" {
			resolvedExe = eval
		}
		exeDir := filepath.Dir(resolvedExe)
		candidates = append(candidates,
			filepath.Join(exeDir, "maps"),
			filepath.Join(exeDir, "..", "Resources", "maps"),
			filepath.Join(exeDir, "..", "share", "vpro", "maps"),
		)
	}
	seen := make(map[string]bool, len(candidates))
	var out []string
	for _, dir := range candidates {
		cleaned := filepath.Clean(dir)
		if cleaned == "" || cleaned == "." || seen[cleaned] {
			continue
		}
		if info, err := os.Stat(cleaned); err == nil && info.IsDir() {
			seen[cleaned] = true
			out = append(out, cleaned)
		}
	}
	return out
}

//go:embed all:frontend/dist
var assets embed.FS

type wailsServiceGraph struct {
	lifecycle      *LifecycleService
	context        *ContextService
	plotEntry      *PlotEntryService
	datasheet      *DatasheetService
	classification *ClassificationService
	validation     *ValidationService
	importExport   *ImportExportService
	vegReport      *VegetationReportService
	envReport      *EnvironmentReportService
	spatial        *SpatialService
	pictures       *PictureService
	help           *HelpService
	tracker        *runtimeShutdownTracker
}

func newWailsServiceGraph(
	dataDir, configDir string,
	refs *referenceCatalogBundle,
	cloudSyncManager *cloudsyncpkg.Manager,
	closeService *lifecyclepkg.CloseService,
	lookupEnv func(string) (string, bool),
) wailsServiceGraph {
	return newWailsServiceGraphWithAuthLock(dataDir, configDir, refs, cloudSyncManager, closeService, lookupEnv, false)
}

func newWailsServiceGraphWithAuthLock(
	dataDir, configDir string,
	refs *referenceCatalogBundle,
	cloudSyncManager *cloudsyncpkg.Manager,
	closeService *lifecyclepkg.CloseService,
	lookupEnv func(string) (string, bool),
	enforceAuthLock bool,
) wailsServiceGraph {
	if lookupEnv == nil {
		lookupEnv = os.LookupEnv
	}
	var becSvc *referencespkg.BECService
	if refs != nil {
		becSvc = refs.bec
	}
	spatialExtraDirs := resolveSpatialExtraDirs(lookupEnv)
	initialAttributor := NewPMTilesAttributor(dataDir, spatialExtraDirs...)
	initialBundle := &runtimeBundle{
		attributor:     initialAttributor,
		context:        &ContextService{cloud: cloudSyncManager},
		plotEntry:      &PlotEntryService{},
		datasheet:      &DatasheetService{},
		classification: &ClassificationService{bec: becSvc},
		validation:     &ValidationService{},
		importExport:   &ImportExportService{},
		vegReport:      &VegetationReportService{},
		envReport:      &EnvironmentReportService{dataDir: dataDir},
		spatial: &SpatialService{
			dataDir:    dataDir,
			extraDirs:  append([]string(nil), spatialExtraDirs...),
			attributor: initialAttributor,
		},
		pictures: &PictureService{},
		help:     &HelpService{},
	}
	runtimeTracker := newRuntimeShutdownTracker(initialBundle, spatialExtraDirs)

	lifecycleService := NewLifecycleService(nil, closeService, nil)
	lifecycleService.runtime = runtimeTracker
	lifecycleService.onShutdown = func() { runtimeTracker.shutdown(refs, cloudSyncManager) }

	activateRuntime := func() (StartupState, error) {
		active, err := openActiveProjectContext(dataDir, configDir, refs, cloudSyncManager)
		if err != nil {
			return StartupState{}, err
		}
		plots := active.plots
		contextService := active.contextSvc
		if enforceAuthLock {
			if mgr, core, authErr := contextService.authManager(); authErr != nil {
				log.Printf("Warning: failed to initialize desktop auth edit-lock: %v", authErr)
			} else if mgr != nil {
				syncAuthActorToPlots(core, mgr.CachedSessionSummary())
			}
		}

		var workingUnits *vprocorepkg.WorkingUnitService
		abort := func(cause error) (StartupState, error) {
			if workingUnits != nil {
				_ = workingUnits.Close()
			}
			_ = active.projects.CloseSQLiteContext()
			return StartupState{}, cause
		}

		builtPlotEntry, err := buildPlotEntryService(contextService, plots, refs)
		if err != nil {
			return abort(err)
		}
		builtPictures, err := buildPictureService(contextService, dataDir, lookupEnv)
		if err != nil {
			return abort(err)
		}
		builtDatasheet, err := buildDatasheetService(contextService)
		if err != nil {
			return abort(err)
		}
		builtImportExport, err := buildImportExportService(contextService)
		if err != nil {
			return abort(err)
		}
		builtVegReport, err := buildVegetationReportService(contextService)
		if err != nil {
			return abort(err)
		}
		builtEnvReport, err := buildEnvironmentReportService(contextService, dataDir)
		if err != nil {
			return abort(err)
		}
		userLog, err := lifecyclepkg.NewUserLogService(unwrapContextService(contextService))
		if err != nil {
			return abort(err)
		}
		if workingUnits, err = vprocorepkg.NewWorkingUnitService(active.projects, configDir); err != nil {
			log.Printf("Warning: failed to initialize WorkingUnitService: %v", err)
		}
		builtClassification, err := buildClassificationService(contextService, becSvc, workingUnits)
		if err != nil {
			return abort(err)
		}
		builtHelp, err := buildHelpService(active.preferences, contextService, dataDir)
		if err != nil {
			return abort(err)
		}
		effectiveExtraDirs := resolveSpatialExtraDirs(lookupEnv, active.configuredSpatialDir)
		nextAttributor := NewPMTilesAttributor(dataDir, effectiveExtraDirs...)
		builtSpatial, err := buildSpatialService(contextService, configDir, active.preferences, dataDir, effectiveExtraDirs, nextAttributor)
		if err != nil {
			if nextAttributor != nil {
				_ = nextAttributor.Close()
			}
			return abort(err)
		}

		runtimeTracker.publish(&runtimeBundle{
			projects:       active.projects,
			working:        workingUnits,
			attributor:     nextAttributor,
			userLog:        userLog,
			context:        contextService,
			plotEntry:      &builtPlotEntry,
			datasheet:      builtDatasheet,
			classification: builtClassification,
			validation:     NewValidationService(contextService),
			importExport:   builtImportExport,
			vegReport:      &builtVegReport,
			envReport:      &builtEnvReport,
			spatial:        &builtSpatial,
			pictures:       builtPictures,
			help:           builtHelp,
		}, effectiveExtraDirs)

		nextState := StartupState{Ready: true, ConfigPath: active.preferences.Path, ReleaseChannel: active.releaseChannel}
		lifecyclepkg.PopulateRecoveryHints(&nextState)
		return nextState, nil
	}

	lifecycleService.startup = newStartupServiceWithInitialActivation(dataDir, configDir, activateRuntime)

	return wailsServiceGraph{
		lifecycle:      lifecycleService,
		context:        &ContextService{runtime: runtimeTracker},
		plotEntry:      &PlotEntryService{runtime: runtimeTracker},
		datasheet:      &DatasheetService{runtime: runtimeTracker},
		classification: &ClassificationService{runtime: runtimeTracker},
		validation:     &ValidationService{runtime: runtimeTracker},
		importExport:   &ImportExportService{runtime: runtimeTracker},
		vegReport:      &VegetationReportService{runtime: runtimeTracker},
		envReport:      &EnvironmentReportService{runtime: runtimeTracker},
		spatial:        &SpatialService{runtime: runtimeTracker},
		pictures:       &PictureService{runtime: runtimeTracker},
		help:           &HelpService{runtime: runtimeTracker},
		tracker:        runtimeTracker,
	}
}

func buildDesktopServices(
	dataDir, configDir string,
	refs *referenceCatalogBundle,
	cloudSyncManager *cloudsyncpkg.Manager,
	closeService *lifecyclepkg.CloseService,
	lookupEnv func(string) (string, bool),
) ([]application.Service, wailsServiceGraph) {
	return buildDesktopServicesWithAuthLock(dataDir, configDir, refs, cloudSyncManager, closeService, lookupEnv, false)
}

func buildDesktopServicesWithAuthLock(
	dataDir, configDir string,
	refs *referenceCatalogBundle,
	cloudSyncManager *cloudsyncpkg.Manager,
	closeService *lifecyclepkg.CloseService,
	lookupEnv func(string) (string, bool),
	enforceAuthLock bool,
) ([]application.Service, wailsServiceGraph) {
	wailsGraph := newWailsServiceGraphWithAuthLock(dataDir, configDir, refs, cloudSyncManager, closeService, lookupEnv, enforceAuthLock)
	services := []application.Service{
		application.NewService(wailsGraph.lifecycle),
		application.NewService(wailsGraph.context),
		application.NewService(wailsGraph.plotEntry),
		application.NewService(wailsGraph.datasheet),
		application.NewService(wailsGraph.classification),
		application.NewService(wailsGraph.validation),
		application.NewService(wailsGraph.importExport),
		application.NewService(wailsGraph.vegReport),
		application.NewService(wailsGraph.envReport),
		application.NewService(wailsGraph.spatial),
		application.NewService(wailsGraph.pictures),
		application.NewService(wailsGraph.help),
	}
	return services, wailsGraph
}

func main() {
	dataDir, configDir, windows, err := resolveHostEnvironment()
	if err != nil {
		log.Fatal(err)
	}

	refs := openReferenceCatalogBundle(dataDir)
	var app *application.App
	closeService, err := lifecyclepkg.NewCloseService(
		func(nonce string) bool { return app.Event.Emit(lifecyclepkg.CloseRequestEvent, nonce) },
		func() { app.Quit() },
	)
	if err != nil {
		log.Fatal(err)
	}

	cloudSyncManager := NewCloudSyncManager(configDir)
	services, wailsGraph := buildDesktopServicesWithAuthLock(dataDir, configDir, refs, cloudSyncManager, closeService, os.LookupEnv, true)
	runtimeTracker := wailsGraph.tracker

	var window *application.WebviewWindow
	app = application.New(application.Options{
		Name:        "VPro",
		Description: "VENUS (Vegetation and Environment NexUS) Professional — B.C. Ministry of Forests, Research Branch (BEC Program)",
		Services:    services,
		Windows:     windows,
		ShouldQuit:  closeService.ShouldQuit,
		OnShutdown:  func() { runtimeTracker.shutdown(refs, cloudSyncManager) },
		SingleInstance: &application.SingleInstanceOptions{
			UniqueID: "ca.bc.gov.for.bec.vpro",
			OnSecondInstanceLaunch: func(_ application.SecondInstanceData) {
				if window != nil {
					window.Show()
					window.Focus()
				}
			},
		},
		Server: application.ServerOptions{
			ReadTimeout:             5 * time.Minute,
			WriteTimeout:            15 * time.Minute,
			WebSocketOriginPatterns: parseWebSocketOriginPatterns(os.Getenv("VPRO_SERVER_WS_ORIGINS")),
		},
		Assets: application.AssetOptions{
			Handler: NewDynamicPMTilesAssetHandler(application.AssetFileServerFS(assets), dataDir, runtimeTracker.currentExtraDirs),
		},
		Mac: application.MacOptions{ApplicationShouldTerminateAfterLastWindowClosed: true},
	})

	window = app.Window.NewWithOptions(application.WebviewWindowOptions{
		Name: "main", Title: "VPro", Width: 1400, Height: 900, MinWidth: 560, MinHeight: 520,
		BackgroundColour: application.NewRGB(242, 242, 242), URL: "/",
	})
	var layoutOnce sync.Once
	window.OnWindowEvent(events.Common.WindowRuntimeReady, func(_ *application.WindowEvent) {
		layoutOnce.Do(func() {
			screen := app.Screen.GetPrimary()
			if screen == nil {
				log.Fatal("Cannot size the application: primary display is unavailable")
			}
			dimensions, err := vprocorepkg.InitialWindowDimensions(screen.WorkArea.Width, screen.WorkArea.Height)
			if err != nil {
				log.Fatal(err)
			}
			window.SetMinSize(dimensions.MinWidth, dimensions.MinHeight)
			window.SetSize(dimensions.Width, dimensions.Height)
			window.Center()
		})
	})
	window.RegisterHook(events.Common.WindowClosing, closeService.HandleWindowClosing)
	if err = app.Run(); err != nil {
		log.Fatal(err)
	}
}

func parseWebSocketOriginPatterns(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	var out []string
	for _, part := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
