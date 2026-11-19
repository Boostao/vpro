package main

import (
	"context"
	"errors"
	classificationpkg "github.com/boostao/vpro/app/internal/classification"
	envreportpkg "github.com/boostao/vpro/app/internal/envreport"
	interchangepkg "github.com/boostao/vpro/app/internal/interchange"
	plotentrypkg "github.com/boostao/vpro/app/internal/plotentry"
	projectopspkg "github.com/boostao/vpro/app/internal/projectops"
	sivipkg "github.com/boostao/vpro/app/internal/sivi"
	sourceformpkg "github.com/boostao/vpro/app/internal/sourceform"
	spatialpkg "github.com/boostao/vpro/app/internal/spatial"
	twopagepkg "github.com/boostao/vpro/app/internal/twopage"
	validationpkg "github.com/boostao/vpro/app/internal/validation"
	vegreportpkg "github.com/boostao/vpro/app/internal/vegreport"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func (s *ContextService) CreateBlankProjectMetadata(p0 context.Context, p1 string, p2 ProjectMetadataCreate) (ProjectMetadataRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataRow{}, errors.New("project context is unavailable")
	}
	return classificationpkg.CreateBlankProjectMetadata(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) CreatePersonalSpeciesDefinition(p0 context.Context, p1 string, p2 PersonalSpeciesDefinitionRequest) (VegetationSpeciesOption, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return VegetationSpeciesOption{}, errors.New("project context is unavailable")
	}
	return plotentrypkg.CtxCreatePersonalSpeciesDefinition(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) CreatePlotProfileFile(p0 context.Context, p1 string, p2 PlotProfileFileCreation) (PlotProfileFileCreated, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return PlotProfileFileCreated{}, errors.New("project context is unavailable")
	}
	return classificationpkg.CreatePlotProfileFile(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) CreatePlotProfileTable(p0 context.Context, p1 string, p2 PlotProfileTableCreation) (PlotProfileFileCreated, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return PlotProfileFileCreated{}, errors.New("project context is unavailable")
	}
	return classificationpkg.CreatePlotProfileTable(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) CreateProjectMetadataFromTemplate(p0 context.Context, p1 string, p2 ProjectMetadataTemplateCreate) (ProjectMetadataRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataRow{}, errors.New("project context is unavailable")
	}
	return classificationpkg.CreateProjectMetadataFromTemplate(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) CreateProjectPlotProfileRule(p0 context.Context, p1 string, p2 ProjectPlotProfileCreation) (ProjectMetadataRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataRow{}, errors.New("project context is unavailable")
	}
	return classificationpkg.CreateProjectPlotProfileRule(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) DeleteProjectPlotProfileRule(p0 context.Context, p1 string, p2 ProjectPlotProfileDeletion) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return classificationpkg.DeleteProjectPlotProfileRule(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) DeleteReviewedVegetation(p0 string, p1 string, p2 VegetationDeletionRequest) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return plotentrypkg.CtxDeleteReviewedVegetation(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetLongEnvironmentOptions(p0 context.Context, p1 string) (LongEnvironmentOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return LongEnvironmentOptions{}, errors.New("project context is unavailable")
	}
	return envreportpkg.GetLongEnvironmentOptions(unwrapContextService(s), p0, p1)
}

func (s *ContextService) GetLongVegetationOptions(p0 context.Context, p1 string) (LongVegetationOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return LongVegetationOptions{}, errors.New("project context is unavailable")
	}
	return vegreportpkg.GetLongVegetationOptions(unwrapContextService(s), p0, p1)
}

func (s *ContextService) GetPlotLocationReview(p0 context.Context, p1 string) (*PlotLocationReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return spatialpkg.GetPlotLocationReview(unwrapContextService(s), p0, p1)
}

func (s *ContextService) GetProjectTableCSVReview(p0 context.Context, p1 string, p2 string) (*ProjectTableCSVReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return interchangepkg.GetProjectTableCSVReview(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIParentActionOriginal(p0 context.Context, p1 string, p2 string) (*SIVIParentProjection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.GetSIVIParentActionOriginal(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIParentDirectOriginal(p0 context.Context, p1 string, p2 string) (*SIVIParentProjection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.GetSIVIParentDirectOriginal(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIParentJoinReview(p0 context.Context, p1 string, p2 string) (*SIVIParentJoinReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.GetSIVIParentJoinReview(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIParentOriginal(p0 context.Context, p1 string, p2 string) (*SIVIParentProjection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.GetSIVIParentOriginal(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIProjectAssignmentOriginal(p0 context.Context, p1 string, p2 string) (*SIVIProjectAssignmentOriginal, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.GetSIVIProjectAssignmentOriginal(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) GetSIVIProjectIDChoices(p0 context.Context, p1 string) (*SIVIProjectChoices, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.GetSIVIProjectIDChoices(unwrapContextService(s), p0, p1)
}

func (s *ContextService) GetSIVIVegetation(p0 context.Context, p1 string, p2 string, p3 bool) ([]SIVIVegetationProjection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.GetSIVIVegetation(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) GetSiteUnitSummaryOptions(p0 context.Context, p1 string) (SiteUnitSummaryOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SiteUnitSummaryOptions{}, errors.New("project context is unavailable")
	}
	return envreportpkg.GetSiteUnitSummaryOptions(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ImportAccessProject(p0 context.Context, p1 string, p2 AccessProjectImportRequest) (AccessProjectImportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return AccessProjectImportResult{}, errors.New("project context is unavailable")
	}
	return interchangepkg.ImportAccessProject(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) InspectAccessDatabase(p0 context.Context, p1 string, p2 string) (AccessDatabaseInspection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return AccessDatabaseInspection{}, errors.New("project context is unavailable")
	}
	return interchangepkg.InspectAccessDatabase(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) ListProjectMetadataFields(p0 context.Context, p1 string) ([]ProjectMetadataEditorField, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return classificationpkg.ListProjectMetadataFields(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ListProjectMetadataRestoreHistory(p0 context.Context, p1 string, p2 string) (ProjectMetadataRestoreHistory, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataRestoreHistory{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ListProjectMetadataRestoreHistory(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) ListProjectPlotProfileChoices(p0 context.Context, p1 string) (ProjectPlotProfileChoices, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectPlotProfileChoices{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ListProjectPlotProfileChoices(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ListSoilSuggestions(p0 context.Context, p1 string) ([]SoilSuggestion, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return plotentrypkg.ListSoilSuggestions(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ListVegetationAttributeSuggestions(p0 context.Context, p1 string) ([]SoilSuggestion, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return plotentrypkg.ListVegetationAttributeSuggestions(unwrapContextService(s), p0, p1)
}

func (s *ContextService) LookupSpeciesCodeCheckTarget(p0 context.Context, p1 string, p2 VegetationSpeciesLookup) ([]SpeciesCodeCheckOption, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return validationpkg.LookupSpeciesCodeCheckTarget(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) PreviewLongEnvironment(p0 context.Context, p1 string, p2 LongEnvironmentRequest) (LongEnvironmentPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return LongEnvironmentPreview{}, errors.New("project context is unavailable")
	}
	return envreportpkg.PreviewLongEnvironment(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) PreviewLongVegetation(p0 context.Context, p1 string) (LongVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return LongVegetationPreview{}, errors.New("project context is unavailable")
	}
	return vegreportpkg.PreviewLongVegetation(unwrapContextService(s), p0, p1)
}

func (s *ContextService) PreviewSiteUnitSummary(p0 context.Context, p1 string, p2 SiteUnitSummaryRequest) (SiteUnitSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SiteUnitSummaryPreview{}, errors.New("project context is unavailable")
	}
	return envreportpkg.PreviewSiteUnitSummary(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) PreviewSiteUnitSummaryLifeforms(p0 context.Context, p1 string, p2 SiteUnitSummaryRequest) (SiteUnitSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SiteUnitSummaryPreview{}, errors.New("project context is unavailable")
	}
	return envreportpkg.PreviewSiteUnitSummaryLifeforms(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) PreviewSiteUnitSummarySpecies(p0 context.Context, p1 string, p2 SiteUnitSpeciesListRequest) (SiteUnitSpeciesListPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SiteUnitSpeciesListPreview{}, errors.New("project context is unavailable")
	}
	return envreportpkg.PreviewSiteUnitSummarySpecies(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) ResolveProjectPlotProfileNavigation(p0 context.Context, p1 string, p2 ProjectPlotProfileFilterRequest) (ProjectPlotProfileNavigation, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectPlotProfileNavigation{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ResolveProjectPlotProfileNavigation(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) RestoreProjectMetadata(p0 context.Context, p1 string, p2 ProjectMetadataRestore) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return classificationpkg.RestoreProjectMetadata(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) RestoreSIVIHeights(p0 context.Context, p1 string, p2 string, p3 string, p4 AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.RestoreSIVIHeights(unwrapContextService(s), p0, p1, p2, p3, vprocorepkg.AuditRestoreAction(p4))
}

func (s *ContextService) RestoreSIVIParentActions(p0 context.Context, p1 string, p2 string, p3 string, p4 AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.RestoreSIVIParentActions(unwrapContextService(s), p0, p1, p2, p3, vprocorepkg.AuditRestoreAction(p4))
}

func (s *ContextService) RestoreSIVIParentDirect(p0 context.Context, p1 string, p2 string, p3 string, p4 AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.RestoreSIVIParentDirect(unwrapContextService(s), p0, p1, p2, p3, vprocorepkg.AuditRestoreAction(p4))
}

func (s *ContextService) RestoreSIVIProjectAssignment(p0 context.Context, p1 string, p2 string, p3 string, p4 AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.RestoreSIVIProjectAssignment(unwrapContextService(s), p0, p1, p2, p3, vprocorepkg.AuditRestoreAction(p4))
}

func (s *ContextService) ReviewEnvironmentSiteUnits(p0 context.Context, p1 string) (EnvironmentSiteUnitReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return EnvironmentSiteUnitReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewEnvironmentSiteUnits(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewPlotProfileFileCreation(p0 context.Context, p1 string) (PlotProfileFileReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return PlotProfileFileReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewPlotProfileFileCreation(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewPlotProfileTableCreation(p0 context.Context, p1 string) (PlotProfileTableReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return PlotProfileTableReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewPlotProfileTableCreation(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewProjectMetadataRestoration(p0 context.Context, p1 string, p2 string, p3 string) (ProjectMetadataRestoreReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataRestoreReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewProjectMetadataRestoration(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) ReviewProjectPlotProfile(p0 context.Context, p1 string) (ProjectPlotProfileReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectPlotProfileReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewProjectPlotProfile(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewProjectPlotProfileLump(p0 context.Context, p1 string) (ProjectMetadataTable, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectMetadataTable{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewProjectPlotProfileLump(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewProjectPlotProfileSU(p0 context.Context, p1 string, p2 ProjectPlotProfileFilterRequest) (ProfileSUReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProfileSUReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewProjectPlotProfileSU(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) ReviewProjectPlotProfileSUInProject(p0 context.Context, p1 string, p2 ProjectPlotProfileFilterRequest) (ProfileSUProjectReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProfileSUProjectReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewProjectPlotProfileSUInProject(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) ReviewSiteUnitEnvironment(p0 context.Context, p1 string) (SiteUnitEnvironmentReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SiteUnitEnvironmentReview{}, errors.New("project context is unavailable")
	}
	return classificationpkg.ReviewSiteUnitEnvironment(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewSpeciesCodes(p0 context.Context, p1 string) (SpeciesCodeCheckReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SpeciesCodeCheckReview{}, errors.New("project context is unavailable")
	}
	return validationpkg.ReviewSpeciesCodes(unwrapContextService(s), p0, p1)
}

func (s *ContextService) ReviewVegetationDeletion(p0 context.Context, p1 string, p2 string, p3 string, p4 int64) (VegetationDeletionReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return VegetationDeletionReview{}, errors.New("project context is unavailable")
	}
	return plotentrypkg.ReviewVegetationDeletion(unwrapContextService(s), p0, p1, p2, p3, p4)
}

func (s *ContextService) RunProjectPlotProfile(p0 context.Context, p1 string, p2 ProjectPlotProfileRunRequest) (ProjectPlotProfileResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectPlotProfileResult{}, errors.New("project context is unavailable")
	}
	return classificationpkg.RunProjectPlotProfile(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) SaveProjectPlotProfile(p0 context.Context, p1 string, p2 ProjectPlotProfileEdit) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return classificationpkg.SaveProjectPlotProfile(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) SaveProjectPlotProfileSU(p0 context.Context, p1 string, p2 ProfileSUCreation) (ProfileSUCreated, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProfileSUCreated{}, errors.New("project context is unavailable")
	}
	return classificationpkg.SaveProjectPlotProfileSU(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) SaveProjectPlotProfileSUInProject(p0 context.Context, p1 string, p2 ProfileSUProjectCreation) (ProfileSUCreated, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProfileSUCreated{}, errors.New("project context is unavailable")
	}
	return classificationpkg.SaveProjectPlotProfileSUInProject(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) SaveSIVIHeights(p0 context.Context, p1 string, p2 string, p3 bool, p4 []SIVIVegetationProjection, p5 []SIVIHeightEdit) (*SIVIHeightWriteResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.SaveSIVIHeights(unwrapContextService(s), p0, p1, p2, p3, p4, p5)
}

func (s *ContextService) SaveSIVIParentActions(p0 context.Context, p1 string, p2 string, p3 SIVIParentActionWrite) (*SIVIParentActionSaveResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.SaveSIVIParentActions(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) SaveSIVIParentDirect(p0 context.Context, p1 string, p2 string, p3 SIVIParentDirectWrite) (*SIVIParentWriteResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.SaveSIVIParentDirect(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) SaveSIVIProjectAssignment(p0 context.Context, p1 string, p2 string, p3 SIVIProjectAssignmentWrite) (*SIVIParentWriteResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sourceformpkg.SaveSIVIProjectAssignment(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) SaveSpeciesCodeCheck(p0 string, p1 []SpeciesCodeCheckUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return validationpkg.SaveSpeciesCodeCheck(unwrapContextService(s), p0, p1)
}

func (s *ContextService) SetPlotProfileEditing(p0 context.Context, p1 string, p2 PlotProfileWriteRequest) (ProjectState, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return ProjectState{}, errors.New("project context is unavailable")
	}
	return classificationpkg.SetPlotProfileEditing(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) SetSIVIProjectIDSource(p0 context.Context, p1 string, p2 int, p3 int) (*SIVIProjectChoices, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.SetSIVIProjectIDSource(unwrapContextService(s), p0, p1, p2, p3)
}

func (s *ContextService) TransferEnvironmentSiteUnits(p0 context.Context, p1 string, p2 EnvironmentSiteUnitTransfer) (*EnvironmentSiteUnitResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return classificationpkg.TransferEnvironmentSiteUnits(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) TransferSiteUnitEnvironment(p0 context.Context, p1 string, p2 SiteUnitEnvironmentTransfer) (*SiteUnitEnvironmentResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return classificationpkg.TransferSiteUnitEnvironment(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) UpdateVegetationAttributes(p0 string, p1 string, p2 []VegetationAttributeUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return plotentrypkg.CtxUpdateVegetationAttributes(unwrapContextService(s), p0, p1, p2)
}

func (s *ContextService) RestoreSelectedAuditRecords(contextID, plot string, rowIDs []string, action AuditRestoreAction) (*AuditRestoreResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.RestoreSelectedAuditRecords(contextID, plot, rowIDs, vprocorepkg.AuditRestoreAction(action))
}

func (s *ContextService) CreateNewProject(ctx context.Context, contextID string, req projectopspkg.NewProjectRequest) (projectopspkg.NewProjectResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.NewProjectResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.CreateNewProject(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) SaveProjectAs(ctx context.Context, contextID string, req projectopspkg.SaveProjectAsRequest) (projectopspkg.SaveProjectAsResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.SaveProjectAsResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.SaveProjectAs(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) ExportSplinterProject(ctx context.Context, contextID string, req projectopspkg.ExportSplinterRequest) (projectopspkg.ExportSplinterResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.ExportSplinterResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.ExportSplinterProject(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) CompareProjects(ctx context.Context, contextID string, req projectopspkg.CompareProjectsRequest) (projectopspkg.CompareProjectsResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.CompareProjectsResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.CompareProjects(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) PreviewOptimizeVeg(ctx context.Context, contextID string, opts projectopspkg.OptimizeVegOptions) (projectopspkg.OptimizeVegPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.OptimizeVegPreview{}, errors.New("project context is unavailable")
	}
	return projectopspkg.PreviewOptimizeVeg(unwrapContextService(s), ctx, contextID, opts)
}

func (s *ContextService) ApplyOptimizeVeg(ctx context.Context, contextID string, req projectopspkg.ApplyOptimizeVegRequest) (projectopspkg.OptimizeVegResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.OptimizeVegResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.ApplyOptimizeVeg(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) PreviewThreeWayMerge(ctx context.Context, contextID string, req projectopspkg.ThreeWayMergePreviewRequest) (projectopspkg.ThreeWayMergePreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.ThreeWayMergePreview{}, errors.New("project context is unavailable")
	}
	return projectopspkg.PreviewThreeWayMerge(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) ExecuteThreeWayMerge(ctx context.Context, contextID string, req projectopspkg.ThreeWayMergeExecuteRequest) (projectopspkg.ThreeWayMergeResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.ThreeWayMergeResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.ExecuteThreeWayMerge(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) DeriveProjectMetadataFromPlots(ctx context.Context, contextID, projectID string) (projectopspkg.DerivedProjectMetadata, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.DerivedProjectMetadata{}, errors.New("project context is unavailable")
	}
	return projectopspkg.DeriveProjectMetadataFromPlots(unwrapContextService(s), ctx, contextID, projectID)
}

func (s *ContextService) ListProjectMetadataPresets() []projectopspkg.ProjectMetadataPreset {
	return projectopspkg.ListProjectMetadataPresets()
}

func (s *ContextService) ApplyProjectMetadataAutomation(ctx context.Context, contextID string, req projectopspkg.ApplyProjectMetadataAutomationRequest) (projectopspkg.ApplyProjectMetadataAutomationResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return projectopspkg.ApplyProjectMetadataAutomationResult{}, errors.New("project context is unavailable")
	}
	return projectopspkg.ApplyProjectMetadataAutomation(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) RunComplianceValidation(ctx context.Context, contextID string, opts validationpkg.ComplianceOptions) (validationpkg.ComplianceValidationReport, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return validationpkg.ComplianceValidationReport{}, errors.New("project context is unavailable")
	}
	return validationpkg.RunComplianceValidation(unwrapContextService(s), ctx, contextID, opts)
}

func (s *ContextService) QuarantineOrphanRecords(ctx context.Context, contextID string, req validationpkg.QuarantineOrphanRequest) (validationpkg.QuarantineOrphanResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return validationpkg.QuarantineOrphanResult{}, errors.New("project context is unavailable")
	}
	return validationpkg.QuarantineOrphanRecords(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) DeleteTwoPageSoilHorizon(ctx context.Context, contextID string, req twopagepkg.DeleteTwoPageSoilHorizonRequest) (twopagepkg.DeleteTwoPageSoilHorizonResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return twopagepkg.DeleteTwoPageSoilHorizonResult{}, errors.New("project context is unavailable")
	}
	return twopagepkg.DeleteTwoPageSoilHorizon(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) RestoreTwoPageSoilHorizon(ctx context.Context, contextID string, req twopagepkg.RestoreTwoPageSoilHorizonRequest) (twopagepkg.RestoreTwoPageSoilHorizonResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return twopagepkg.RestoreTwoPageSoilHorizonResult{}, errors.New("project context is unavailable")
	}
	return twopagepkg.RestoreTwoPageSoilHorizon(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) ListTwoPageSoilDeletedHorizons(ctx context.Context, contextID, plotNumber, form string) ([]twopagepkg.DeletedTwoPageSoilHorizonEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return twopagepkg.ListTwoPageSoilDeletedHorizons(unwrapContextService(s), ctx, contextID, plotNumber, form)
}

func (s *ContextService) CreateSIVIPlot(ctx context.Context, contextID string, req sivipkg.CreateSIVIPlotRequest) (sivipkg.CreateSIVIPlotResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return sivipkg.CreateSIVIPlotResult{}, errors.New("project context is unavailable")
	}
	return sivipkg.CreateSIVIPlot(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) UndoCreateSIVIPlot(ctx context.Context, contextID string, req sivipkg.UndoCreateSIVIPlotRequest) (sivipkg.UndoCreateSIVIPlotResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return sivipkg.UndoCreateSIVIPlotResult{}, errors.New("project context is unavailable")
	}
	return sivipkg.UndoCreateSIVIPlot(unwrapContextService(s), ctx, contextID, req)
}

func (s *ContextService) ListCreatedSIVIPlots(ctx context.Context, contextID string) ([]sivipkg.SIVICreatedPlotEntry, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return sivipkg.ListCreatedSIVIPlots(unwrapContextService(s), ctx, contextID)
}
