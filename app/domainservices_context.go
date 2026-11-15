package main

import (
	"context"
	"errors"
	cloudsyncpkg "github.com/boostao/vpro/app/internal/cloudsync"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
	"log"
	"os"
)

type ContextService struct {
	core  *vprocorepkg.ContextService
	cloud *cloudsyncpkg.Manager
}

func NewCloudSyncManager(configDir string) *cloudsyncpkg.Manager {
	return cloudsyncpkg.NewManager(configDir, os.LookupEnv)
}

func (s *ContextService) cloudManager() (*cloudsyncpkg.Manager, error) {
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
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.GetState(ctx)
}

func (s *ContextService) ListPlots(ctx context.Context, offset, limit int) (PlotPage, error) {
	if s == nil || s.core == nil || s.core.Projects == nil {
		return PlotPage{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.ListPlots(ctx, offset, limit)
}

func (s *ContextService) GetHierarchyNodes(ctx context.Context) ([]HierarchyNode, error) {
	if s == nil || s.core == nil || s.core.Projects == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.Projects.GetHierarchyNodes(ctx)
}

func (s *ContextService) SelectProject(name string) (ProjectState, error) {
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectProject(name)
}

func (s *ContextService) SelectSU(name string) (ProjectState, error) {
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectSU(name)
}

func (s *ContextService) SelectHierarchy(name, file string) (ProjectState, error) {
	if s == nil || s.core == nil || s.core.Projects == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.Projects.SelectHierarchy(name, file)
}

func (s *ContextService) SwitchContext(expectedID string, requested vprocorepkg.ContextSelection) (vprocorepkg.ProjectState, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.SwitchContext(expectedID, requested)
}

func (s *ContextService) GetPlot(ctx context.Context, contextID, plot string) (*vprocorepkg.FS882Header, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetPlot(ctx, contextID, plot)
}

func (s *ContextService) GetHeaderCapabilities(ctx context.Context, contextID string) (map[string]bool, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetHeaderCapabilities(ctx, contextID)
}

func (s *ContextService) CanEditMasterBEC(ctx context.Context, contextID string) (bool, error) {
	if s == nil || s.core == nil {
		return false, errors.New("project context is unavailable")
	}
	return s.core.CanEditMasterBEC(ctx, contextID)
}

func (s *ContextService) GetUserSetup(ctx context.Context, contextID string) (UserAccreditation, error) {
	if s == nil || s.core == nil {
		return UserAccreditation{}, errors.New("project context is unavailable")
	}
	return s.core.GetUserSetup(ctx, contextID)
}

func (s *ContextService) SetUserName(ctx context.Context, contextID, user string) (UserAccreditation, error) {
	if s == nil || s.core == nil {
		return UserAccreditation{}, errors.New("project context is unavailable")
	}
	return s.core.SetUserName(ctx, contextID, user)
}

func (s *ContextService) GetChildCapabilities(ctx context.Context, contextID, kind string) (map[string]bool, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetChildCapabilities(ctx, contextID, kind)
}

func (s *ContextService) ListVegRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.VegRecord, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegRecords(ctx, contextID, plot)
}

func (s *ContextService) ListHumusRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.HumusRecord, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListHumusRecords(ctx, contextID, plot)
}

func (s *ContextService) ListMineralRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.MineralRecord, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListMineralRecords(ctx, contextID, plot)
}

func (s *ContextService) ListOtherRecords(ctx context.Context, contextID, plot string) ([]vprocorepkg.OtherRecord, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListOtherRecords(ctx, contextID, plot)
}

func (s *ContextService) ListAuditEntries(ctx context.Context, contextID, plot string) ([]vprocorepkg.AuditEntry, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListAuditEntries(ctx, contextID, plot)
}

func (s *ContextService) ListAuditReadEntries(ctx context.Context, contextID, plot string) ([]vprocorepkg.OrdinaryAuditReadEntry, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListAuditReadEntries(ctx, contextID, plot)
}

func (s *ContextService) CreatePlot(contextID string, header vprocorepkg.FS882Header) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.CreatePlot(contextID, header)
}

func (s *ContextService) UpdatePlot(contextID string, header vprocorepkg.FS882Header) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdatePlot(contextID, header)
}

func (s *ContextService) SaveVegRecord(contextID string, record vprocorepkg.VegRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveVegRecord(contextID, record)
}

func (s *ContextService) UpdateVegRecord(contextID string, record vprocorepkg.VegRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateVegRecord(contextID, record)
}

func (s *ContextService) DeleteVegRecord(contextID, plot string, id int64) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.DeleteVegRecord(contextID, plot, id)
}

func (s *ContextService) SaveHumusRecord(contextID string, record vprocorepkg.HumusRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveHumusRecord(contextID, record)
}

func (s *ContextService) UpdateHumusRecord(contextID string, record vprocorepkg.HumusRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateHumusRecord(contextID, record)
}

func (s *ContextService) DeleteHumusRecord(contextID, plot string, id int64) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.DeleteHumusRecord(contextID, plot, id)
}

func (s *ContextService) SaveMineralRecord(contextID string, record vprocorepkg.MineralRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveMineralRecord(contextID, record)
}

func (s *ContextService) UpdateMineralRecord(contextID string, record vprocorepkg.MineralRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateMineralRecord(contextID, record)
}

func (s *ContextService) DeleteMineralRecord(contextID, plot string, id int64) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.DeleteMineralRecord(contextID, plot, id)
}

func (s *ContextService) SaveOtherRecord(contextID string, record vprocorepkg.OtherRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveOtherRecord(contextID, record)
}

func (s *ContextService) UpdateOtherRecord(contextID string, record vprocorepkg.OtherRecord) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateOtherRecord(contextID, record)
}

func (s *ContextService) UpdateOtherRecords(contextID, plot string, updates []vprocorepkg.OtherRecordUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateOtherRecords(contextID, plot, updates)
}

func (s *ContextService) UpdateSoilRecords(contextID, plot string, updates []vprocorepkg.SoilRecordUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateSoilRecords(contextID, plot, updates)
}

func (s *ContextService) DeleteOtherRecord(contextID, plot string, id int64) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.DeleteOtherRecord(contextID, plot, id)
}

func (s *ContextService) UpdateHeightRecords(contextID, plot string, updates []vprocorepkg.HeightRecordUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateHeightRecords(contextID, plot, updates)
}

func (s *ContextService) SetAuditRestoreSelection(contextID, plot string, rowIDs []string) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SetAuditRestoreSelection(contextID, plot, rowIDs)
}

func (s *ContextService) UpdateCollectedRecords(contextID, plot string, updates []vprocorepkg.CollectedRecordUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateCollectedRecords(contextID, plot, updates)
}

func (s *ContextService) UpdateVegetationSpecies(contextID, plot string, updates []vprocorepkg.VegetationSpeciesUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateVegetationSpecies(contextID, plot, updates)
}

func (s *ContextService) ListVegetationSpecies(ctx context.Context, contextID, form string) ([]vprocorepkg.VegetationSpeciesOption, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpecies(ctx, contextID, form)
}

func (s *ContextService) ListVegetationSpeciesAliases(ctx context.Context, contextID string, lookup vprocorepkg.VegetationSpeciesLookup) ([]vprocorepkg.VegetationSpeciesAlias, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpeciesAliases(ctx, contextID, lookup)
}

func (s *ContextService) ListVegetationSpeciesUsers(ctx context.Context, contextID string, lookup vprocorepkg.VegetationSpeciesLookup) ([]vprocorepkg.VegetationSpeciesOption, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListVegetationSpeciesUsers(ctx, contextID, lookup)
}

func (s *ContextService) GetVegetationReadAvailability(ctx context.Context, contextID, plot string) (*vprocorepkg.VegetationReadAvailability, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.GetVegetationReadAvailability(ctx, contextID, plot)
}

func (s *ContextService) UpdateVegetationNumbers(contextID, plot string, updates []vprocorepkg.VegetationNumberUpdate) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.UpdateVegetationNumbers(contextID, plot, updates)
}

func (s *ContextService) CreateSourceVegetation(contextID, plot string, request vprocorepkg.VegetationCreationRequest) (int64, error) {
	if s == nil || s.core == nil {
		return 0, errors.New("project context is unavailable")
	}
	return s.core.CreateSourceVegetation(contextID, plot, request)
}

func (s *ContextService) LookupScopedPlot(ctx context.Context, contextID string, request vprocorepkg.ScopedPlotLookup) (vprocorepkg.ScopedPlotLookupResult, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ScopedPlotLookupResult{}, errors.New("project context is unavailable")
	}
	return s.core.LookupScopedPlot(ctx, contextID, request)
}

func (s *ContextService) SaveProjectMetadata(ctx context.Context, contextID string, request vprocorepkg.ProjectMetadataEdit) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.SaveProjectMetadata(ctx, contextID, request)
}

func (s *ContextService) ReviewProjectMetadata(ctx context.Context, contextID, plot string) (vprocorepkg.ProjectMetadataReview, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectMetadataReview{}, errors.New("project context is unavailable")
	}
	return s.core.ReviewProjectMetadata(ctx, contextID, plot)
}

func (s *ContextService) InspectExternalSQLiteFile(ctx context.Context, contextID, path string) (vprocorepkg.ExternalSQLiteFileInspection, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ExternalSQLiteFileInspection{}, errors.New("project context is unavailable")
	}
	return s.core.InspectExternalSQLiteFile(ctx, contextID, path)
}

func (s *ContextService) ChooseExternalSQLiteFile(ctx context.Context, contextID string) (vprocorepkg.ExternalSQLiteFileInspection, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ExternalSQLiteFileInspection{}, errors.New("project context is unavailable")
	}
	return s.core.ChooseExternalSQLiteFile(ctx, contextID)
}

func (s *ContextService) ChooseAccessDatabaseFile(ctx context.Context, contextID string) (string, error) {
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.ChooseAccessDatabaseFile(ctx, contextID)
}

func (s *ContextService) ChooseNewSQLiteProjectFile(ctx context.Context, contextID, suggestedProject string) (string, error) {
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.ChooseNewSQLiteProjectFile(ctx, contextID, suggestedProject)
}

func (s *ContextService) RevealInFileExplorer(ctx context.Context, contextID, target string) (string, error) {
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	return s.core.RevealInFileExplorer(ctx, contextID, target)
}

func (s *ContextService) ReadNewProjectTemplates(ctx context.Context, contextID string) (*vprocorepkg.NewProjectTemplateReview, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ReadNewProjectTemplates(ctx, contextID)
}

func (s *ContextService) SelectPlotProfile(expectedID string, requested vprocorepkg.PlotProfileSource) (vprocorepkg.ProjectState, error) {
	if s == nil || s.core == nil {
		return vprocorepkg.ProjectState{}, errors.New("project context is unavailable")
	}
	return s.core.SelectPlotProfile(expectedID, requested)
}

func (s *ContextService) ListPlotProfileSources(ctx context.Context, contextID, path string) ([]vprocorepkg.PlotProfileSourceInfo, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListPlotProfileSources(ctx, contextID, path)
}

func (s *ContextService) ReadPlotLocations(ctx context.Context, contextID string) (*vprocorepkg.PlotLocationReview, error) {
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ReadPlotLocations(ctx, contextID)
}

func (s *ContextService) RequireSelectedListReportScope(contextID string) error {
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.RequireSelectedListReportScope(contextID)
}
