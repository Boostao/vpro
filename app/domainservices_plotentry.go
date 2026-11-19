package main

import (
	"context"
	"errors"
	classificationpkg "github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/plotentry"
	referencespkg "github.com/boostao/vpro/app/internal/references"
	sivipkg "github.com/boostao/vpro/app/internal/sivi"
	sourceformpkg "github.com/boostao/vpro/app/internal/sourceform"
	twopagepkg "github.com/boostao/vpro/app/internal/twopage"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
	"log"
)

type CreateTwoPageVegetationRequest = twopagepkg.CreateTwoPageVegetationRequest
type CreateTwoPageVegetationResult = twopagepkg.CreateTwoPageVegetationResult
type DeleteTwoPageVegetationRequest = twopagepkg.DeleteTwoPageVegetationRequest
type DeleteTwoPageVegetationResult = twopagepkg.DeleteTwoPageVegetationResult
type DeletedTwoPageVegetationEntry = twopagepkg.DeletedTwoPageVegetationEntry
type RestoreTwoPageVegetationRequest = twopagepkg.RestoreTwoPageVegetationRequest
type RestoreTwoPageVegetationResult = twopagepkg.RestoreTwoPageVegetationResult

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
	siviParentShared             *sourceformpkg.SIVIParentSharedService
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
	siviParentShared, err := sourceformpkg.NewSIVIParentSharedService(core)
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
	siviParentShared.References = sourceformpkg.SiviParentSharedReferenceReaders{
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

func (s *PlotEntryService) CanEditMasterBEC() bool {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return false
	}
	return s.plots.CanEditMasterBEC()
}

func (s *PlotEntryService) UserAccreditationStatus(ctx context.Context) (UserAccreditation, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return UserAccreditation{}, errors.New("plot service is unavailable")
	}
	return s.plots.UserAccreditationStatus(ctx)
}

func (s *PlotEntryService) CreatePlot(h FS882Header) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.CreatePlot(h)
}

func (s *PlotEntryService) CreateSourceVegetation(plot string, request VegetationCreationRequest) (int64, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return 0, errors.New("plot service is unavailable")
	}
	return s.plots.CreateSourceVegetation(plot, request)
}

func (s *PlotEntryService) DeleteHumusRecord(plotNumber string, id int64) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.DeleteHumusRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteMineralRecord(plotNumber string, id int64) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.DeleteMineralRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteOtherRecord(plotNumber string, id int64) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.DeleteOtherRecord(plotNumber, id)
}

func (s *PlotEntryService) DeleteReviewedVegetation(plot string, request VegetationDeletionRequest) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return plotentry.DeleteReviewedVegetation(s.plots, plot, request)
}

func (s *PlotEntryService) DeleteVegRecord(plotNumber string, id int64) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.DeleteVegRecord(plotNumber, id)
}

func (s *PlotEntryService) GetChildCapabilities(kind string) (map[string]bool, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.GetChildCapabilities(kind)
}

func (s *PlotEntryService) GetHeaderCapabilities() (map[string]bool, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.GetHeaderCapabilities()
}

func (s *PlotEntryService) GetPlot(plotNumber string) (*FS882Header, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.GetPlot(plotNumber)
}

func (s *PlotEntryService) ListAuditEntries(plotNumber string) ([]AuditEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListAuditEntries(plotNumber)
}

func (s *PlotEntryService) ListAuditReadEntries(plot string) ([]OrdinaryAuditReadEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListAuditReadEntries(plot)
}

func (s *PlotEntryService) ListHumusRecords(plotNumber string) ([]HumusRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListHumusRecords(plotNumber)
}

func (s *PlotEntryService) ListMineralRecords(plotNumber string) ([]MineralRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListMineralRecords(plotNumber)
}

func (s *PlotEntryService) ListOtherRecords(plotNumber string) ([]OtherRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListOtherRecords(plotNumber)
}

func (s *PlotEntryService) ListVegRecords(plotNumber string) ([]VegRecord, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.ListVegRecords(plotNumber)
}

func (s *PlotEntryService) RestoreAuditRecords(plotNumber string, removeAuditRows bool) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.RestoreAuditRecords(plotNumber, removeAuditRows)
}

func (s *PlotEntryService) RestoreSelectedAuditRecords(plotNumber string, rowIDs []string, action AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return nil, errors.New("plot service is unavailable")
	}
	return s.plots.RestoreSelectedAuditRecords(plotNumber, rowIDs, vprocorepkg.AuditRestoreAction(action))
}

func (s *PlotEntryService) SaveHumusRecord(r HumusRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SaveHumusRecord(r)
}

func (s *PlotEntryService) SaveMineralRecord(r MineralRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SaveMineralRecord(r)
}

func (s *PlotEntryService) SaveOtherRecord(r OtherRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SaveOtherRecord(r)
}

func (s *PlotEntryService) SavePlot(h FS882Header) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SavePlot(h)
}

func (s *PlotEntryService) SaveVegRecord(r VegRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SaveVegRecord(r)
}

func (s *PlotEntryService) SetAuditRestoreSelection(plotNumber string, rowIDs []string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SetAuditRestoreSelection(plotNumber, rowIDs)
}

func (s *PlotEntryService) SetAuditStrength(strength int) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SetAuditStrength(strength)
}

func (s *PlotEntryService) SetCurrentUser(user string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.SetCurrentUser(user)
}

func (s *PlotEntryService) UpdateCollectedRecords(plot string, updates []CollectedRecordUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateCollectedRecords(plot, updates)
}

func (s *PlotEntryService) UpdateHeightRecords(plotNumber string, updates []HeightRecordUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateHeightRecords(plotNumber, updates)
}

func (s *PlotEntryService) UpdateHumusRecord(r HumusRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateHumusRecord(r)
}

func (s *PlotEntryService) UpdateMineralRecord(r MineralRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateMineralRecord(r)
}

func (s *PlotEntryService) UpdateOtherRecord(r OtherRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateOtherRecord(r)
}

func (s *PlotEntryService) UpdateOtherRecords(plot string, updates []OtherRecordUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateOtherRecords(plot, updates)
}

func (s *PlotEntryService) UpdatePlot(h FS882Header) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdatePlot(h)
}

func (s *PlotEntryService) UpdateSoilRecords(plot string, updates []SoilRecordUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateSoilRecords(plot, updates)
}

func (s *PlotEntryService) UpdateVegRecord(r VegRecord) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateVegRecord(r)
}

func (s *PlotEntryService) UpdateVegetationAttributes(plot string, updates []VegetationAttributeUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return plotentry.UpdateVegetationAttributes(s.plots, plot, updates)
}

func (s *PlotEntryService) UpdateVegetationNumbers(plot string, updates []VegetationNumberUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateVegetationNumbers(plot, updates)
}

func (s *PlotEntryService) UpdateVegetationSpecies(plot string, updates []VegetationSpeciesUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plots == nil {
		return errors.New("plot service is unavailable")
	}
	return s.plots.UpdateVegetationSpecies(plot, updates)
}
