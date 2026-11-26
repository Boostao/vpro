package main

import (
	"context"
	"errors"
	"log"

	classificationpkg "github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/plotentry"
	referencespkg "github.com/boostao/vpro/app/internal/references"
	sivipkg "github.com/boostao/vpro/app/internal/sivi"
	sourceformpkg "github.com/boostao/vpro/app/internal/sourceform"
	twopagepkg "github.com/boostao/vpro/app/internal/twopage"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type CreateTwoPageVegetationRequest = twopagepkg.CreateTwoPageVegetationRequest
type CreateTwoPageVegetationResult = twopagepkg.CreateTwoPageVegetationResult
type DeleteTwoPageVegetationRequest = twopagepkg.DeleteTwoPageVegetationRequest
type DeleteTwoPageVegetationResult = twopagepkg.DeleteTwoPageVegetationResult
type DeletedTwoPageVegetationEntry = twopagepkg.DeletedTwoPageVegetationEntry
type RestoreTwoPageVegetationRequest = twopagepkg.RestoreTwoPageVegetationRequest
type RestoreTwoPageVegetationResult = twopagepkg.RestoreTwoPageVegetationResult
type TreePlotRecord = vprocorepkg.TreePlotRecord
type TreeRowRecord = vprocorepkg.TreeRowRecord
type PlotMensurationData = vprocorepkg.PlotMensurationData
type EnsureMensurationTablesResult = vprocorepkg.EnsureMensurationTablesResult

type referenceCatalogBundle struct {
	references     *referencespkg.ReferenceService
	bec            *referencespkg.BECService
	quality        *referencespkg.QualityService
	siteCodes      *referencespkg.SiteCodeService
	siteCodesErr   error
	regionCodes    *referencespkg.RegionCodeService
	soilCodes      *referencespkg.SoilCodeService
	geologyCodes   *referencespkg.GeologyCodeService
	parentCodes    *referencespkg.ParentCodeService
	parentCodesErr error
}

func openReferenceCatalogBundle(dataDir string) *referenceCatalogBundle {
	b := &referenceCatalogBundle{}
	var err error
	if b.references, err = referencespkg.NewReferenceService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize ReferenceService: %v", err)
	}
	if b.bec, err = referencespkg.NewBECService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize BECService: %v", err)
	}
	if b.quality, err = referencespkg.NewQualityService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize QualityService: %v", err)
	}
	if b.siteCodes, b.siteCodesErr = referencespkg.NewSiteCodeService(dataDir); b.siteCodesErr != nil {
		log.Printf("Warning: failed to initialize SiteCodeService: %v", b.siteCodesErr)
	}
	if b.regionCodes, err = referencespkg.NewRegionCodeService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize RegionCodeService: %v", err)
	}
	if b.soilCodes, err = referencespkg.NewSoilCodeService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize SoilCodeService: %v", err)
	}
	if b.geologyCodes, err = referencespkg.NewGeologyCodeService(dataDir); err != nil {
		log.Printf("Warning: failed to initialize GeologyCodeService: %v", err)
	}
	if b.parentCodes, b.parentCodesErr = referencespkg.NewParentCodeService(dataDir); b.parentCodesErr != nil {
		log.Printf("Warning: failed to initialize ParentCodeService: %v", b.parentCodesErr)
	}
	return b
}

func (b *referenceCatalogBundle) Close() {
	if b == nil {
		return
	}
	type namedCloser struct {
		name  string
		close func() error
	}
	var closers []namedCloser
	if b.references != nil {
		closers = append(closers, namedCloser{"ReferenceService", b.references.Close})
	}
	if b.parentCodes != nil {
		closers = append(closers, namedCloser{"ParentCodeService", b.parentCodes.Close})
	}
	if b.geologyCodes != nil {
		closers = append(closers, namedCloser{"GeologyCodeService", b.geologyCodes.Close})
	}
	if b.soilCodes != nil {
		closers = append(closers, namedCloser{"SoilCodeService", b.soilCodes.Close})
	}
	if b.regionCodes != nil {
		closers = append(closers, namedCloser{"RegionCodeService", b.regionCodes.Close})
	}
	if b.siteCodes != nil {
		closers = append(closers, namedCloser{"SiteCodeService", b.siteCodes.Close})
	}
	if b.bec != nil {
		closers = append(closers, namedCloser{"BECService", b.bec.Close})
	}
	for _, item := range closers {
		if err := item.close(); err != nil {
			log.Printf("Warning: failed to close %s: %v", item.name, err)
		}
	}
}

type PlotEntryService struct {
	runtime                      *runtimeShutdownTracker
	contexts                     *ContextService
	plots                        *vprocorepkg.PlotService
	siviParentShared             *sourceformpkg.SourceParentSharedService
	siviCovers                   *sivipkg.SIVICoverService
	siviCombined                 *sivipkg.SIVICombinedService
	siviCollected                *sivipkg.SIVICollectedService
	siviSpecies                  *sourceformpkg.SIVISpeciesService
	siviIdentity                 *sivipkg.SIVIIdentityService
	siviCreation                 *sivipkg.SIVICreationService
	siviCreationUndo             *sivipkg.SIVICreationUndoService
	siviDeletion                 *sivipkg.SIVIDeletionService
	twoPageParentExtra           *twopagepkg.TwoPageParentExtraService
	twoPageParentCommon          *twopagepkg.TwoPageParentCommonService
	twoPageParentEntry           *twopagepkg.TwoPageParentEntryService
	twoPageSoil                  *twopagepkg.TwoPageSoilService
	twoPageVegetation            *twopagepkg.TwoPageVegetationService
	twoPageVegetationSpeciesList *twopagepkg.TwoPageVegetationSpeciesListService
	twoPageSourceAudit           *twopagepkg.TwoPageSourceAuditService
	twoPageProjectMetadata       *classificationpkg.TwoPageProjectMetadataService
	mensuration                  *plotentry.MensurationService
	references                   *referencespkg.ReferenceService
	siteCodes                    *referencespkg.SiteCodeService
	soilCodes                    *referencespkg.SoilCodeService
	parentCodes                  *referencespkg.ParentCodeService
	geologyCodes                 *referencespkg.GeologyCodeService
	regionCodes                  *referencespkg.RegionCodeService
	quality                      *referencespkg.QualityService
}

func (s *PlotEntryService) acquire() (*PlotEntryService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.plotEntry, release
}

func buildPlotEntryService(contexts *ContextService, plots *vprocorepkg.PlotService, refs *referenceCatalogBundle) (PlotEntryService, error) {
	core := unwrapContextService(contexts)
	siviParentShared, err := sourceformpkg.NewSourceParentSharedService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviCovers, err := sivipkg.NewSIVICoverService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviCombined, err := sivipkg.NewSIVICombinedService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviCollected, err := sivipkg.NewSIVICollectedService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviSpecies, err := sourceformpkg.NewSIVISpeciesService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviIdentity, err := sivipkg.NewSIVIIdentityService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviCreation, err := sivipkg.NewSIVICreationService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviCreationUndo, err := sivipkg.NewSIVICreationUndoService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	siviDeletion, err := sivipkg.NewSIVIDeletionService(core)
	if err != nil {
		return PlotEntryService{}, err
	}

	var refBundle referenceCatalogBundle
	if refs != nil {
		refBundle = *refs
	}
	siviParentShared.References = sourceformpkg.SourceParentSharedReferenceReaders{
		Site:    refBundle.siteCodes,
		Region:  refBundle.regionCodes,
		Parent:  refBundle.parentCodes,
		Geology: refBundle.geologyCodes,
		Bec:     refBundle.bec,
	}
	entryReaders := twopagepkg.TwoPageEntryReferenceReaders{}
	if refBundle.siteCodes != nil {
		entryReaders.Shared.Site = refBundle.siteCodes
	}
	if refBundle.regionCodes != nil {
		entryReaders.Shared.Region = refBundle.regionCodes
		entryReaders.Ecosection = refBundle.regionCodes
	}
	if refBundle.parentCodes != nil {
		entryReaders.Shared.Parent = refBundle.parentCodes
	}
	if refBundle.geologyCodes != nil {
		entryReaders.Shared.Geology = refBundle.geologyCodes
	}
	if refBundle.bec != nil {
		entryReaders.Shared.Bec = refBundle.bec
		entryReaders.Series = refBundle.bec
	}
	if refBundle.quality != nil {
		entryReaders.Quality = refBundle.quality
	}
	if refBundle.soilCodes != nil {
		entryReaders.Soil = refBundle.soilCodes
	}

	twoPageParentExtra, err := twopagepkg.NewTwoPageParentExtraService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageParentCommon, err := twopagepkg.NewTwoPageParentCommonService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageParentEntry, err := twopagepkg.NewTwoPageParentEntryService(core, entryReaders)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageSoil, err := twopagepkg.NewTwoPageSoilService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageVegetation, err := twopagepkg.NewTwoPageVegetationService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageVegetationSpeciesList, err := twopagepkg.NewTwoPageVegetationSpeciesListService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageSourceAudit, err := twopagepkg.NewTwoPageSourceAuditService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	twoPageProjectMetadata, err := classificationpkg.NewTwoPageProjectMetadataService(core)
	if err != nil {
		return PlotEntryService{}, err
	}
	mensuration, err := plotentry.NewMensurationService(core)
	if err != nil {
		return PlotEntryService{}, err
	}

	return PlotEntryService{
		contexts:                     contexts,
		plots:                        plots,
		siviParentShared:             siviParentShared,
		siviCovers:                   siviCovers,
		siviCombined:                 siviCombined,
		siviCollected:                siviCollected,
		siviSpecies:                  siviSpecies,
		siviIdentity:                 siviIdentity,
		siviCreation:                 siviCreation,
		siviCreationUndo:             siviCreationUndo,
		siviDeletion:                 siviDeletion,
		twoPageParentExtra:           twoPageParentExtra,
		twoPageParentCommon:          twoPageParentCommon,
		twoPageParentEntry:           twoPageParentEntry,
		twoPageSoil:                  twoPageSoil,
		twoPageVegetation:            twoPageVegetation,
		twoPageVegetationSpeciesList: twoPageVegetationSpeciesList,
		twoPageSourceAudit:           twoPageSourceAudit,
		twoPageProjectMetadata:       twoPageProjectMetadata,
		mensuration:                  mensuration,
		references:                   refBundle.references,
		siteCodes:                    refBundle.siteCodes,
		soilCodes:                    refBundle.soilCodes,
		parentCodes:                  refBundle.parentCodes,
		geologyCodes:                 refBundle.geologyCodes,
		regionCodes:                  refBundle.regionCodes,
		quality:                      refBundle.quality,
	}, nil
}

// PlotService delegates

func (s *PlotEntryService) withPlots(ctx context.Context) (*vprocorepkg.PlotService, func(), error) {
	s, release := s.acquire()
	if s == nil || s.plots == nil {
		release()
		return nil, noopRelease, errors.New("plot service is unavailable")
	}
	plots, err := s.plots.WithRequestContext(ctx)
	if err != nil {
		release()
		return nil, noopRelease, err
	}
	return plots, release, nil
}

func (s *PlotEntryService) CanEditMasterBEC(ctx context.Context) bool {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return false
	}
	return plots.CanEditMasterBEC()
}

func (s *PlotEntryService) UserAccreditationStatus(ctx context.Context) (UserAccreditation, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return UserAccreditation{}, errors.New("plot service is unavailable")
	}
	return s.plots.UserAccreditationStatus(ctx)
}

func (s *PlotEntryService) CreatePlot(ctx context.Context, h FS882Header) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.CreatePlot(h)
}

func (s *PlotEntryService) CreateSourceVegetation(ctx context.Context, plot string, request VegetationCreationRequest) (int64, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return 0, err
	}
	return plots.CreateSourceVegetation(plot, request)
}

func (s *PlotEntryService) DeleteHumusRecord(ctx context.Context, plotNumber string, id int64) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.DeleteHumusRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteMineralRecord(ctx context.Context, plotNumber string, id int64) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.DeleteMineralRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteOtherRecord(ctx context.Context, plotNumber string, id int64) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.DeleteOtherRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteReviewedVegetation(ctx context.Context, plot string, request VegetationDeletionRequest) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plotentry.DeleteReviewedVegetation(plots, plot, request)
}

func (s *PlotEntryService) DeleteVegRecord(ctx context.Context, plotNumber string, id int64) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.DeleteVegRecord(plotNumber, id)
}

func (s *PlotEntryService) GetChildCapabilities(ctx context.Context, kind string) (map[string]bool, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.GetChildCapabilities(kind)
}

func (s *PlotEntryService) GetHeaderCapabilities(ctx context.Context) (map[string]bool, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.GetHeaderCapabilities()
}

func (s *PlotEntryService) GetPlot(ctx context.Context, plotNumber string) (*FS882Header, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.GetPlot(plotNumber)
}

func (s *PlotEntryService) ListAuditEntries(ctx context.Context, plotNumber string) ([]AuditEntry, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListAuditEntries(plotNumber)
}

func (s *PlotEntryService) ListAuditReadEntries(ctx context.Context, plot string) ([]OrdinaryAuditReadEntry, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListAuditReadEntries(plot)
}

func (s *PlotEntryService) ListHumusRecords(ctx context.Context, plotNumber string) ([]HumusRecord, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListHumusRecords(plotNumber)
}

func (s *PlotEntryService) ListMineralRecords(ctx context.Context, plotNumber string) ([]MineralRecord, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListMineralRecords(plotNumber)
}

func (s *PlotEntryService) ListOtherRecords(ctx context.Context, plotNumber string) ([]OtherRecord, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListOtherRecords(plotNumber)
}

func (s *PlotEntryService) ListVegRecords(ctx context.Context, plotNumber string) ([]VegRecord, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.ListVegRecords(plotNumber)
}

func (s *PlotEntryService) RestoreAuditRecords(ctx context.Context, plotNumber string, removeAuditRows bool) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.RestoreAuditRecords(plotNumber, removeAuditRows)
}

func (s *PlotEntryService) RestoreSelectedAuditRecords(ctx context.Context, plotNumber string, rowIDs []string, action AuditRestoreAction) (*AuditRestoreResult, error) {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return nil, err
	}
	return plots.RestoreSelectedAuditRecords(plotNumber, rowIDs, vprocorepkg.AuditRestoreAction(action))
}

func (s *PlotEntryService) SaveHumusRecord(ctx context.Context, r HumusRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SaveHumusRecord(r)
}

func (s *PlotEntryService) SaveMineralRecord(ctx context.Context, r MineralRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SaveMineralRecord(r)
}

func (s *PlotEntryService) SaveOtherRecord(ctx context.Context, r OtherRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SaveOtherRecord(r)
}

func (s *PlotEntryService) SavePlot(ctx context.Context, h FS882Header) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SavePlot(h)
}

func (s *PlotEntryService) SaveVegRecord(ctx context.Context, r VegRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SaveVegRecord(r)
}

func (s *PlotEntryService) SetAuditRestoreSelection(ctx context.Context, plotNumber string, rowIDs []string) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.SetAuditRestoreSelection(plotNumber, rowIDs)
}

func (s *PlotEntryService) SetAuditStrength(ctx context.Context, strength int) error {
	if err := requireContextArg(ctx); err != nil {
		return err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SetAuditStrength(strength)
}

func (s *PlotEntryService) SetCurrentUser(ctx context.Context, user string) error {
	if err := requireContextArg(ctx); err != nil {
		return err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SetCurrentUser(user)
}

func (s *PlotEntryService) UpdateCollectedRecords(ctx context.Context, plot string, updates []CollectedRecordUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateCollectedRecords(plot, updates)
}

func (s *PlotEntryService) UpdateHeightRecords(ctx context.Context, plotNumber string, updates []HeightRecordUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateHeightRecords(plotNumber, updates)
}

func (s *PlotEntryService) UpdateHumusRecord(ctx context.Context, r HumusRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateHumusRecord(r)
}

func (s *PlotEntryService) UpdateMineralRecord(ctx context.Context, r MineralRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateMineralRecord(r)
}

func (s *PlotEntryService) UpdateOtherRecord(ctx context.Context, r OtherRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateOtherRecord(r)
}

func (s *PlotEntryService) UpdateOtherRecords(ctx context.Context, plot string, updates []OtherRecordUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateOtherRecords(plot, updates)
}

func (s *PlotEntryService) UpdatePlot(ctx context.Context, h FS882Header) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdatePlot(h)
}

func (s *PlotEntryService) UpdateSoilRecords(ctx context.Context, plot string, updates []SoilRecordUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateSoilRecords(plot, updates)
}

func (s *PlotEntryService) UpdateVegRecord(ctx context.Context, r VegRecord) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateVegRecord(r)
}

func (s *PlotEntryService) UpdateVegetationAttributes(ctx context.Context, plot string, updates []VegetationAttributeUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plotentry.UpdateVegetationAttributes(plots, plot, updates)
}

func (s *PlotEntryService) UpdateVegetationNumbers(ctx context.Context, plot string, updates []VegetationNumberUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateVegetationNumbers(plot, updates)
}

func (s *PlotEntryService) UpdateVegetationSpecies(ctx context.Context, plot string, updates []VegetationSpeciesUpdate) error {
	plots, release, err := s.withPlots(ctx)
	defer release()
	if err != nil {
		return err
	}
	return plots.UpdateVegetationSpecies(plot, updates)
}

// Mensuration 4th FS882 Card delegates (_TreePlot & _Trees)

func (s *PlotEntryService) GetPlotMensuration(ctx context.Context, contextID, plot string) (*PlotMensurationData, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return nil, errors.New("mensuration service is unavailable")
	}
	return s.mensuration.GetPlotMensuration(ctx, contextID, plot)
}

func (s *PlotEntryService) EnsureMensurationTables(ctx context.Context, contextID string) (*EnsureMensurationTablesResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return nil, errors.New("mensuration service is unavailable")
	}
	return s.mensuration.EnsureMensurationTables(ctx, contextID)
}

func (s *PlotEntryService) SaveTreePlot(ctx context.Context, contextID string, record TreePlotRecord) (*TreePlotRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return nil, errors.New("mensuration service is unavailable")
	}
	return s.mensuration.SaveTreePlot(ctx, contextID, record)
}

func (s *PlotEntryService) DeleteTreePlot(ctx context.Context, contextID, plot, subPlot string, measurementID int) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return errors.New("mensuration service is unavailable")
	}
	return s.mensuration.DeleteTreePlot(ctx, contextID, plot, subPlot, measurementID)
}

func (s *PlotEntryService) SaveTreeRow(ctx context.Context, contextID string, record TreeRowRecord) (*TreeRowRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return nil, errors.New("mensuration service is unavailable")
	}
	return s.mensuration.SaveTreeRow(ctx, contextID, record)
}

func (s *PlotEntryService) DeleteTreeRow(ctx context.Context, contextID, plot, subPlot string, measurementID, treeNum int) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.mensuration == nil {
		return errors.New("mensuration service is unavailable")
	}
	return s.mensuration.DeleteTreeRow(ctx, contextID, plot, subPlot, measurementID, treeNum)
}
