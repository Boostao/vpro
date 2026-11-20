package main

import (
	"context"
	"errors"
	"log"
	"os"

	cloudsyncpkg "github.com/boostao/vpro/app/internal/cloudsync"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type ContextService struct {
	runtime *runtimeShutdownTracker
	core    *vprocorepkg.ContextService
	cloud   *cloudsyncpkg.Manager
}

func (s *ContextService) acquire() (*ContextService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.context, release
}

func NewCloudSyncManager(configDir string) *cloudsyncpkg.Manager {
	return cloudsyncpkg.NewManager(configDir, os.LookupEnv)
}

func (s *ContextService) cloudManager() (*cloudsyncpkg.Manager, error) {
	s, release := s.acquire()
	defer release()
	if s == nil {
		return nil, errors.New("project context is unavailable")
	}
	if s.cloud != nil {
		return s.cloud, nil
	}
	cfgDir := ""
	if s.core != nil && s.core.Projects != nil {
		cfgDir = s.core.Projects.Config
	}
	return cloudsyncpkg.NewManager(cfgDir, os.LookupEnv), nil
}

func unwrapContextService(s *ContextService) *vprocorepkg.ContextService {
	if s == nil {
		return nil
	}
	if s.runtime != nil {
		snap, release := s.runtime.acquire()
		defer release()
		if snap == nil || snap.context == nil {
			return nil
		}
		return snap.context.core
	}
	return s.core
}

func NewContextService(projects *vprocorepkg.ProjectService, plots *vprocorepkg.PlotService) (*ContextService, error) {
	core, err := vprocorepkg.NewContextService(projects, plots)
	if err != nil {
		return nil, err
	}
	cfgDir := ""
	if projects != nil {
		cfgDir = projects.Config
	}
	return &ContextService{
		core:  core,
		cloud: cloudsyncpkg.NewManager(cfgDir, os.LookupEnv),
	}, nil
}

type activatedProjectContext struct {
	preferences          *vprocorepkg.DesktopConfig
	releaseChannel       string
	configuredSpatialDir string
	projects             *vprocorepkg.ProjectService
	plots                *vprocorepkg.PlotService
	contextSvc           *ContextService
}

func openActiveProjectContext(
	dataDir, configDir string,
	refs *referenceCatalogBundle,
	cloud *cloudsyncpkg.Manager,
) (*activatedProjectContext, error) {
	preferences, err := vprocorepkg.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		return nil, err
	}
	releaseChannel, err := preferences.ReleaseChannel()
	if err != nil {
		return nil, err
	}
	projects, err := vprocorepkg.NewSQLiteProjectService(dataDir, configDir, preferences)
	if err != nil {
		return nil, err
	}
	if err := projects.EnsureActiveProjectWAL(context.Background()); err != nil {
		log.Printf("Warning: failed to initialize active project WAL mode: %v", err)
	}
	configuredSpatialDir := ""
	if snap, snapErr := preferences.Snapshot(); snapErr == nil {
		if spSec, secErr := vprocorepkg.ConfigSection(snap, "Spatial"); secErr == nil {
			configuredSpatialDir, _ = spSec["AssetsDir"].(string)
		}
	}
	plots, err := vprocorepkg.NewPlotServiceWithPreferences(projects)
	if err != nil {
		_ = projects.CloseSQLiteContext()
		return nil, err
	}
	if refs != nil {
		plots.SiteCodes, plots.SiteCodesError = refs.siteCodes, refs.siteCodesErr
		plots.ParentCodes, plots.ParentCodesError = refs.parentCodes, refs.parentCodesErr
	}
	builtContext, err := NewContextService(projects, plots)
	if err != nil {
		_ = projects.CloseSQLiteContext()
		return nil, err
	}
	builtContext.cloud = cloud
	return &activatedProjectContext{
		preferences:          preferences,
		releaseChannel:       releaseChannel,
		configuredSpatialDir: configuredSpatialDir,
		projects:             projects,
		plots:                plots,
		contextSvc:           builtContext,
	}, nil
}

func (s *ContextService) GetState(ctx context.Context) (ProjectState, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.GetState(ctx)
}

func (s *ContextService) ListPlots(ctx context.Context, offset, limit int) (PlotPage, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return PlotPage{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.ListPlots(ctx, offset, limit)
}

func (s *ContextService) GetHierarchyNodes(ctx context.Context) ([]HierarchyNode, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.Projects.GetHierarchyNodes(ctx)
}

func requireContextArg(ctx context.Context) error {
	if ctx == nil {
		return errors.New("project context operation requires a context")
	}
	return ctx.Err()
}

func (s *ContextService) SelectProject(ctx context.Context, name string) (ProjectState, error) {
	if err := requireContextArg(ctx); err != nil {
		return ProjectState{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectProject(name)
}

func (s *ContextService) SelectSU(ctx context.Context, name string) (ProjectState, error) {
	if err := requireContextArg(ctx); err != nil {
		return ProjectState{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectSU(name)
}

func (s *ContextService) SelectHierarchy(ctx context.Context, name, file string) (ProjectState, error) {
	if err := requireContextArg(ctx); err != nil {
		return ProjectState{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectHierarchy(name, file)
}

func (s *ContextService) SwitchContext(ctx context.Context, expectedID string, requested vprocorepkg.ContextSelection) (vprocorepkg.ProjectState, error) {
	if err := requireContextArg(ctx); err != nil {
		return vprocorepkg.ProjectState{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.SwitchContext(expectedID, requested)
}

func (s *ContextService) GetPlot(ctx context.Context, contextID, plot string) (*vprocorepkg.FS882Header, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetPlot(ctx, contextID, plot)
}

func (s *ContextService) GetPlotBundle(ctx context.Context, contextID, plot string, includeCapabilities bool) (*vprocorepkg.PlotBundle, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetPlotBundle(ctx, contextID, plot, includeCapabilities)
}

func (s *ContextService) GetHeaderCapabilities(ctx context.Context, contextID string) (map[string]bool, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetHeaderCapabilities(ctx, contextID)
}

func (s *ContextService) CanEditMasterBEC(ctx context.Context, contextID string) (bool, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return false, errors.New("project context is unavailable")
	}
	return s.core.CanEditMasterBEC(ctx, contextID)
}

func (s *ContextService) GetUserSetup(ctx context.Context, contextID string) (UserAccreditation, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return UserAccreditation{}, errors.New("project context is unavailable")
	}
	return s.core.GetUserSetup(ctx, contextID)
}

func (s *ContextService) SetUserName(ctx context.Context, contextID, user string) (UserAccreditation, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return UserAccreditation{}, errors.New("project context is unavailable")
	}
	return s.core.SetUserName(ctx, contextID, user)
}

func (s *ContextService) GetChildCapabilities(ctx context.Context, contextID, kind string) (map[string]bool, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetChildCapabilities(ctx, contextID, kind)
}

func (s *ContextService) ListVegRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.VegRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegRecords(ctx, contextID, plot)
}

func (s *ContextService) ListHumusRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.HumusRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListHumusRecords(ctx, contextID, plot)
}

func (s *ContextService) ListMineralRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.MineralRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListMineralRecords(ctx, contextID, plot)
}

func (s *ContextService) ListOtherRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.OtherRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListOtherRecords(ctx, contextID, plot)
}

func (s *ContextService) ListAuditEntries(ctx context.Context, contextID, plot string) ([]vprocorepkg.AuditEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListAuditEntries(ctx, contextID, plot)
}

func (s *ContextService) ListAuditReadEntries(ctx context.Context, contextID, plot string) ([]vprocorepkg.OrdinaryAuditReadEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListAuditReadEntries(ctx, contextID, plot)
}

func (s *ContextService) editPlot(ctx context.Context, contextID string, op func(*vprocorepkg.PlotService) error) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return vprocorepkg.EditContext(ctx, s.core, contextID, op)
}

func (s *ContextService) CreatePlot(ctx context.Context, contextID string, header vprocorepkg.FS882Header) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.CreatePlot(header) })
}

func (s *ContextService) UpdatePlot(ctx context.Context, contextID string, header vprocorepkg.FS882Header) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdatePlot(header) })
}

func (s *ContextService) SaveVegRecord(ctx context.Context, contextID string, record vprocorepkg.VegRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.SaveVegRecord(record) })
}

func (s *ContextService) UpdateVegRecord(ctx context.Context, contextID string, record vprocorepkg.VegRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateVegRecord(record) })
}

func (s *ContextService) DeleteVegRecord(ctx context.Context, contextID, plot string, id int64) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.DeleteVegRecord(plot, id) })
}

func (s *ContextService) SaveHumusRecord(ctx context.Context, contextID string, record vprocorepkg.HumusRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.SaveHumusRecord(record) })
}

func (s *ContextService) UpdateHumusRecord(ctx context.Context, contextID string, record vprocorepkg.HumusRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateHumusRecord(record) })
}

func (s *ContextService) DeleteHumusRecord(ctx context.Context, contextID, plot string, id int64) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.DeleteHumusRecord(plot, id) })
}

func (s *ContextService) SaveMineralRecord(ctx context.Context, contextID string, record vprocorepkg.MineralRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.SaveMineralRecord(record) })
}

func (s *ContextService) UpdateMineralRecord(ctx context.Context, contextID string, record vprocorepkg.MineralRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateMineralRecord(record) })
}

func (s *ContextService) DeleteMineralRecord(ctx context.Context, contextID, plot string, id int64) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.DeleteMineralRecord(plot, id) })
}

func (s *ContextService) SaveOtherRecord(ctx context.Context, contextID string, record vprocorepkg.OtherRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.SaveOtherRecord(record) })
}

func (s *ContextService) UpdateOtherRecord(ctx context.Context, contextID string, record vprocorepkg.OtherRecord) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateOtherRecord(record) })
}

func (s *ContextService) UpdateOtherRecords(ctx context.Context, contextID, plot string, updates []vprocorepkg.OtherRecordUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateOtherRecords(plot, updates) })
}

func (s *ContextService) UpdateSoilRecords(ctx context.Context, contextID, plot string, updates []vprocorepkg.SoilRecordUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateSoilRecords(plot, updates) })
}

func (s *ContextService) DeleteOtherRecord(ctx context.Context, contextID, plot string, id int64) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.DeleteOtherRecord(plot, id) })
}

func (s *ContextService) UpdateHeightRecords(ctx context.Context, contextID, plot string, updates []vprocorepkg.HeightRecordUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateHeightRecords(plot, updates) })
}

func (s *ContextService) SetAuditRestoreSelection(ctx context.Context, contextID, plot string, rowIDs []string) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.SetAuditRestoreSelection(plot, rowIDs) })
}

func (s *ContextService) UpdateCollectedRecords(ctx context.Context, contextID, plot string, updates []vprocorepkg.CollectedRecordUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateCollectedRecords(plot, updates) })
}

func (s *ContextService) UpdateVegetationSpecies(ctx context.Context, contextID, plot string, updates []vprocorepkg.VegetationSpeciesUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateVegetationSpecies(plot, updates) })
}

func (s *ContextService) ListVegetationSpecies(ctx context.Context, contextID, form string) ([]vprocorepkg.VegetationSpeciesOption, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpecies(ctx, contextID, form)
}

func (s *ContextService) ListVegetationSpeciesAliases(ctx context.Context, contextID string, lookup vprocorepkg.VegetationSpeciesLookup) ([]vprocorepkg.VegetationSpeciesAlias, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpeciesAliases(ctx, contextID, lookup)
}

func (s *ContextService) ListVegetationSpeciesUsers(ctx context.Context, contextID string, lookup vprocorepkg.VegetationSpeciesLookup) ([]vprocorepkg.VegetationSpeciesOption, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpeciesUsers(ctx, contextID, lookup)
}

func (s *ContextService) GetVegetationReadAvailability(ctx context.Context, contextID, plot string) (*vprocorepkg.VegetationReadAvailability, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetVegetationReadAvailability(ctx, contextID, plot)
}

func (s *ContextService) UpdateVegetationNumbers(ctx context.Context, contextID, plot string, updates []vprocorepkg.VegetationNumberUpdate) error {
	return s.editPlot(ctx, contextID, func(plots *vprocorepkg.PlotService) error { return plots.UpdateVegetationNumbers(plot, updates) })
}

func (s *ContextService) CreateSourceVegetation(ctx context.Context, contextID, plot string, request vprocorepkg.VegetationCreationRequest) (int64, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return 0, errors.New("project context is unavailable")
	}
	return vprocorepkg.WithContextPlotRequest(ctx, s.core, contextID, func(plots *vprocorepkg.PlotService) (int64, error) {
		return plots.CreateSourceVegetation(plot, request)
	})
}

func (s *ContextService) LookupScopedPlot(ctx context.Context, contextID string, request vprocorepkg.ScopedPlotLookup) (vprocorepkg.ScopedPlotLookupResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ScopedPlotLookupResult{}, errors.New("project context is unavailable")
	}
	return s.core.LookupScopedPlot(ctx, contextID, request)
}

func (s *ContextService) SaveProjectMetadata(ctx context.Context, contextID string, request vprocorepkg.ProjectMetadataEdit) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveProjectMetadata(ctx, contextID, request)
}

func (s *ContextService) ReviewProjectMetadata(ctx context.Context, contextID, plot string) (vprocorepkg.ProjectMetadataReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectMetadataReview{}, errors.New("project context is unavailable")
	}
	return s.core.ReviewProjectMetadata(ctx, contextID, plot)
}

func (s *ContextService) InspectExternalSQLiteFile(ctx context.Context, contextID, path string) (vprocorepkg.ExternalSQLiteFileInspection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ExternalSQLiteFileInspection{}, errors.New("project context is unavailable")
	}
	return s.core.InspectExternalSQLiteFile(ctx, contextID, path)
}

func (s *ContextService) ChooseExternalSQLiteFile(ctx context.Context, contextID string) (vprocorepkg.ExternalSQLiteFileInspection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ExternalSQLiteFileInspection{}, errors.New("project context is unavailable")
	}
	return s.core.ChooseExternalSQLiteFile(ctx, contextID)
}

func (s *ContextService) ChooseAccessDatabaseFile(ctx context.Context, contextID string) (string, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.ChooseAccessDatabaseFile(ctx, contextID)
}

func (s *ContextService) ChooseNewSQLiteProjectFile(ctx context.Context, contextID, suggestedProject string) (string, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.ChooseNewSQLiteProjectFile(ctx, contextID, suggestedProject)
}

func (s *ContextService) RevealInFileExplorer(ctx context.Context, contextID, target string) (string, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.RevealInFileExplorer(ctx, contextID, target)
}

func (s *ContextService) ReadNewProjectTemplates(ctx context.Context, contextID string) (*vprocorepkg.NewProjectTemplateReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ReadNewProjectTemplates(ctx, contextID)
}

func (s *ContextService) SelectPlotProfile(ctx context.Context, expectedID string, requested vprocorepkg.PlotProfileSource) (vprocorepkg.ProjectState, error) {
	if err := requireContextArg(ctx); err != nil {
		return vprocorepkg.ProjectState{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.SelectPlotProfile(expectedID, requested)
}

func (s *ContextService) ListPlotProfileSources(ctx context.Context, contextID, path string) ([]vprocorepkg.PlotProfileSourceInfo, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListPlotProfileSources(ctx, contextID, path)
}

func (s *ContextService) ReadPlotLocations(ctx context.Context, contextID string) (*vprocorepkg.PlotLocationReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ReadPlotLocations(ctx, contextID)
}

func (s *ContextService) RequireSelectedListReportScope(ctx context.Context, contextID string) error {
	if err := requireContextArg(ctx); err != nil {
		return err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.RequireSelectedListReportScope(contextID)
}
