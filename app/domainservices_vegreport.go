package main

import (
	"context"
	"errors"

	vegreportpkg "github.com/boostao/vpro/app/internal/vegreport"
)

type SiteUnitExclusionRule = vegreportpkg.SiteUnitExclusionRule
type ExcludedSiteUnitInfo = vegreportpkg.ExcludedSiteUnitInfo
type RetainedSiteUnitInfo = vegreportpkg.RetainedSiteUnitInfo
type SiteUnitExclusionSummary = vegreportpkg.SiteUnitExclusionSummary
type HierarchyBreakpointOptions = vegreportpkg.HierarchyBreakpointOptions
type HierarchyBreakpointUnitMapping = vegreportpkg.HierarchyBreakpointUnitMapping
type HierarchyBreakpointBucket = vegreportpkg.HierarchyBreakpointBucket
type HierarchyBreakpointResolution = vegreportpkg.HierarchyBreakpointResolution
type HierarchyBreakpointRequest = vegreportpkg.HierarchyBreakpointRequest
type SiteUnitExclusionPreviewRequest = vegreportpkg.SiteUnitExclusionPreviewRequest
type SiteUnitExclusionPreview = vegreportpkg.SiteUnitExclusionPreview
type SummaryVegetationExclusionRequest = vegreportpkg.SummaryVegetationExclusionRequest
type SummaryVegetationExclusionPreview = vegreportpkg.SummaryVegetationExclusionPreview
type LongVegetationExclusionRequest = vegreportpkg.LongVegetationExclusionRequest
type LongVegetationExclusionPreview = vegreportpkg.LongVegetationExclusionPreview
type SummaryVegetationFieldListRequest = vegreportpkg.SummaryVegetationFieldListRequest
type LongVegetationProjectReadRequest = vegreportpkg.LongVegetationProjectReadRequest
type LongVegetationScopeRequest = vegreportpkg.LongVegetationScopeRequest
type LongVegetationSelectedUnitFieldsRequest = vegreportpkg.LongVegetationSelectedUnitFieldsRequest
type LongVegetationProjectUnitRequest = vegreportpkg.LongVegetationProjectUnitRequest
type LongVegetationProjectWorkbookReadRequest = vegreportpkg.LongVegetationProjectWorkbookReadRequest
type LongVegetationProjectWorkbookExportRequest = vegreportpkg.LongVegetationProjectWorkbookExportRequest
type LongVegetationTabPreferencesBundle = vegreportpkg.LongVegetationTabPreferencesBundle
type LongVegetationTabPreferencesSaveRequest = vegreportpkg.LongVegetationTabPreferencesSaveRequest

type VegetationReportService struct {
	runtime                        *runtimeShutdownTracker
	contexts                       *ContextService
	summary                        *vegreportpkg.SummaryVegetationService
	summaryEnvironment             *vegreportpkg.SummaryVegetationEnvironmentalService
	summaryEnvironmentLifeform     *vegreportpkg.SummaryVegetationEnvironmentalLifeformService
	summaryWorkbook                *vegreportpkg.SummaryVegetationWorkbookService
	summaryPreferences             *vegreportpkg.SummaryVegetationPreferencesService
	summaryQualityPreferences      *vegreportpkg.SummaryVegetationQualityPreferencesService
	summaryPresentationPreferences *vegreportpkg.SummaryVegetationPresentationPreferencesService
	summaryFieldList               *vegreportpkg.SummaryVegetationFieldListService
	longPreferences                *vegreportpkg.LongVegetationAllPreferencesService
	longSelectedUnitSelection      *vegreportpkg.LongVegetationSelectedUnitSelectionService
	longReportScope                *vegreportpkg.LongVegetationReportScopeService
	longProjectWorkbook            *vegreportpkg.LongVegetationProjectWorkbookService
	vegetationWorkbook             *vegreportpkg.VegetationWorkbookService
	lifeformSummary                *vegreportpkg.LifeformSummaryService
	lifeformWorkbook               *vegreportpkg.LifeformWorkbookService
	speciesAttributeSummary        *vegreportpkg.SpeciesAttributeSummaryService
}

func (s *VegetationReportService) acquire() (*VegetationReportService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.vegReport, release
}

func buildVegetationReportService(contexts *ContextService) (VegetationReportService, error) {
	core := unwrapContextService(contexts)
	summary, err := vegreportpkg.NewSummaryVegetationService(core)
	if err != nil {
		return VegetationReportService{}, err
	}
	summaryEnvironment, err := vegreportpkg.NewSummaryVegetationEnvironmentalService(summary)
	if err != nil {
		return VegetationReportService{}, err
	}
	summaryEnvironmentLifeform, err := vegreportpkg.NewSummaryVegetationEnvironmentalLifeformService(summaryEnvironment)
	if err != nil {
		return VegetationReportService{}, err
	}
	summaryWorkbook, err := vegreportpkg.NewSummaryVegetationWorkbookService(summaryEnvironmentLifeform)
	if err != nil {
		return VegetationReportService{}, err
	}
	lifeformSummary, err := vegreportpkg.NewLifeformSummaryService(core)
	if err != nil {
		return VegetationReportService{}, err
	}
	lifeformWorkbook, err := vegreportpkg.NewLifeformWorkbookService(core)
	if err != nil {
		return VegetationReportService{}, err
	}
	speciesAttributeSummary, err := vegreportpkg.NewSpeciesAttributeSummaryService(core)
	if err != nil {
		return VegetationReportService{}, err
	}
	vegetationWorkbook, err := vegreportpkg.NewVegetationWorkbookService(core)
	if err != nil {
		return VegetationReportService{}, err
	}
	return VegetationReportService{
		contexts:                       contexts,
		summary:                        summary,
		summaryEnvironment:             summaryEnvironment,
		summaryEnvironmentLifeform:     summaryEnvironmentLifeform,
		summaryWorkbook:                summaryWorkbook,
		summaryPreferences:             vegreportpkg.NewSummaryVegetationPreferencesService(core),
		summaryQualityPreferences:      vegreportpkg.NewSummaryVegetationQualityPreferencesService(core),
		summaryPresentationPreferences: vegreportpkg.NewSummaryVegetationPresentationPreferencesService(core),
		summaryFieldList:               vegreportpkg.NewSummaryVegetationFieldListService(core),
		longPreferences:                vegreportpkg.NewLongVegetationAllPreferencesService(core),
		longSelectedUnitSelection:      vegreportpkg.NewLongVegetationSelectedUnitSelectionService(core),
		longReportScope:                vegreportpkg.NewLongVegetationReportScopeService(core),
		longProjectWorkbook:            vegreportpkg.NewLongVegetationProjectWorkbookService(core),
		vegetationWorkbook:             vegetationWorkbook,
		lifeformSummary:                lifeformSummary,
		lifeformWorkbook:               lifeformWorkbook,
		speciesAttributeSummary:        speciesAttributeSummary,
	}, nil
}

// Summary Vegetation report & workbook delegates

func (s *VegetationReportService) PreviewSummaryVegetation(ctx context.Context, contextID string, average, display int) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.Preview(ctx, contextID, average, display)
}

func (s *VegetationReportService) PreviewSummaryVegetationClass(ctx context.Context, contextID string, average, display, showClass int) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.PreviewClass(ctx, contextID, average, display, showClass)
}

func (s *VegetationReportService) PreviewSummaryVegetationGrouped(ctx context.Context, contextID string, average, groupAndOrder int) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.PreviewGrouped(ctx, contextID, average, groupAndOrder)
}

func (s *VegetationReportService) PreviewSummaryVegetationGroupedDisplay(ctx context.Context, contextID string, average, groupAndOrder, display, showClass int) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.PreviewGroupedDisplay(ctx, contextID, average, groupAndOrder, display, showClass)
}

func (s *VegetationReportService) PreviewSummaryVegetationWithPreferences(ctx context.Context, contextID string) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.PreviewWithPreferences(ctx, contextID)
}

func (s *VegetationReportService) PreviewSummaryVegetationConfigured(ctx context.Context, contextID, requestJSON string) (SummaryVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summary == nil {
		return SummaryVegetationPreview{}, errors.New("summary vegetation service is unavailable")
	}
	return s.summary.PreviewConfigured(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) PreviewSummaryVegetationEnvironmental(ctx context.Context, contextID string, average, display, showClass int) (*SummaryVegetationEnvironmentalPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryEnvironment == nil {
		return nil, errors.New("summary vegetation environmental service is unavailable")
	}
	return s.summaryEnvironment.PreviewEnvironmental(ctx, contextID, average, display, showClass)
}

func (s *VegetationReportService) PreviewSummaryVegetationEnvironmentalNumeric(ctx context.Context, contextID string, average, display, showClass int) (*SummaryVegetationEnvironmentalNumericPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryEnvironment == nil {
		return nil, errors.New("summary vegetation environmental service is unavailable")
	}
	return s.summaryEnvironment.PreviewEnvironmentalNumeric(ctx, contextID, average, display, showClass)
}

func (s *VegetationReportService) PreviewSummaryVegetationEnvironmentalLifeform(ctx context.Context, contextID string, average, display, showClass int) (*SummaryVegetationEnvironmentalLifeformPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryEnvironmentLifeform == nil {
		return nil, errors.New("summary vegetation environmental lifeform service is unavailable")
	}
	return s.summaryEnvironmentLifeform.PreviewEnvironmentalLifeform(ctx, contextID, average, display, showClass)
}

func (s *VegetationReportService) GetSummaryVegetationWorkbookReview(ctx context.Context, contextID, requestJSON string) (*SummaryVegetationWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryWorkbook == nil {
		return nil, errors.New("summary vegetation workbook service is unavailable")
	}
	return s.summaryWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetSummaryVegetationWorkbookReviewFromPreferences(ctx context.Context, contextID string) (*SummaryVegetationWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryWorkbook == nil {
		return nil, errors.New("summary vegetation workbook service is unavailable")
	}
	return s.summaryWorkbook.GetReviewFromPreferences(ctx, contextID)
}

func (s *VegetationReportService) ExportReviewedSummaryVegetationWorkbook(ctx context.Context, contextID, requestJSON string) (*VegetationWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryWorkbook == nil {
		return nil, errors.New("summary vegetation workbook service is unavailable")
	}
	return s.summaryWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetSummaryVegetationPreferences(ctx context.Context, contextID string) (*SummaryVegetationPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryPreferences == nil {
		return nil, errors.New("summary vegetation preferences service is unavailable")
	}
	return s.summaryPreferences.GetSummaryVegetationPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveSummaryVegetationPreferences(ctx context.Context, contextID, requestJSON string) *SummaryVegetationPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryPreferences == nil {
		return &SummaryVegetationPreferencesOutcome{ContextID: contextID, ErrorMessage: "summary vegetation preferences service is unavailable"}
	}
	return s.summaryPreferences.SaveSummaryVegetationPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetSummaryVegetationQualityPreferences(ctx context.Context, contextID string) (*SummaryVegetationQualityPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryQualityPreferences == nil {
		return nil, errors.New("summary vegetation quality preferences service is unavailable")
	}
	return s.summaryQualityPreferences.GetSummaryVegetationQualityPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveSummaryVegetationQualityPreferences(ctx context.Context, contextID, requestJSON string) *SummaryVegetationQualityPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryQualityPreferences == nil {
		return &SummaryVegetationQualityPreferencesOutcome{ContextID: contextID, ErrorMessage: "summary vegetation quality preferences service is unavailable"}
	}
	return s.summaryQualityPreferences.SaveSummaryVegetationQualityPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetSummaryVegetationPresentationPreferences(ctx context.Context, contextID string) (*SummaryVegetationPresentationPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryPresentationPreferences == nil {
		return nil, errors.New("summary vegetation presentation preferences service is unavailable")
	}
	return s.summaryPresentationPreferences.GetSummaryVegetationPresentationPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveSummaryVegetationPresentationPreferences(ctx context.Context, contextID, requestJSON string) *SummaryVegetationPresentationPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryPresentationPreferences == nil {
		return &SummaryVegetationPresentationPreferencesOutcome{ContextID: contextID, ErrorMessage: "summary vegetation presentation preferences service is unavailable"}
	}
	return s.summaryPresentationPreferences.SaveSummaryVegetationPresentationPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetSummaryVegetationFieldList(ctx context.Context, contextID string) (*SummaryVegetationFieldListReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryFieldList == nil {
		return nil, errors.New("summary vegetation field list service is unavailable")
	}
	return s.summaryFieldList.GetSummaryVegetationFieldList(ctx, contextID)
}

func (s *VegetationReportService) GetSummaryVegetationFieldListIndex(ctx context.Context, contextID string) (*SummaryVegetationFieldListSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryFieldList == nil {
		return nil, errors.New("summary vegetation field list service is unavailable")
	}
	return s.summaryFieldList.GetSummaryVegetationFieldListIndex(ctx, contextID)
}

func (s *VegetationReportService) SaveSummaryVegetationFieldList(ctx context.Context, contextID string, request SummaryVegetationFieldListRequest) *SummaryVegetationFieldListOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.summaryFieldList == nil {
		return &SummaryVegetationFieldListOutcome{ContextID: contextID, ErrorMessage: "summary vegetation field list service is unavailable"}
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return &SummaryVegetationFieldListOutcome{ContextID: contextID, RequestID: request.RequestID, ErrorMessage: err.Error()}
	}
	return s.summaryFieldList.SaveSummaryVegetationFieldList(ctx, contextID, raw)
}

// Long Vegetation report, preferences, scope & workbook delegates

func (s *VegetationReportService) GetLongVegetationOptions(ctx context.Context, contextID string) (LongVegetationOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return LongVegetationOptions{}, errors.New("vegetation report context is unavailable")
	}
	return s.contexts.GetLongVegetationOptions(ctx, contextID)
}

func (s *VegetationReportService) PreviewLongVegetation(ctx context.Context, contextID string) (LongVegetationPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return LongVegetationPreview{}, errors.New("vegetation report context is unavailable")
	}
	return s.contexts.PreviewLongVegetation(ctx, contextID)
}

func (s *VegetationReportService) GetLongVegetationTabPreferences(ctx context.Context, contextID string) (*LongVegetationTabPreferencesBundle, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil {
		return nil, errors.New("long vegetation preferences service is unavailable")
	}
	return s.longPreferences.GetAll(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationTabPreferences(ctx context.Context, contextID string, request LongVegetationTabPreferencesSaveRequest) *LongVegetationPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil {
		return &LongVegetationPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation preferences service is unavailable"}
	}
	return s.longPreferences.SaveTab(ctx, contextID, request)
}

func (s *VegetationReportService) GetLongVegetationPreferences(ctx context.Context, contextID string) (*LongVegetationPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Title == nil {
		return nil, errors.New("long vegetation preferences service is unavailable")
	}
	return s.longPreferences.Title.GetLongVegetationPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Title == nil {
		return &LongVegetationPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation preferences service is unavailable"}
	}
	return s.longPreferences.Title.SaveLongVegetationPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationStatisticsPreferences(ctx context.Context, contextID string) (*LongVegetationStatisticsPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Statistics == nil {
		return nil, errors.New("long vegetation statistics preferences service is unavailable")
	}
	return s.longPreferences.Statistics.GetLongVegetationStatisticsPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationStatisticsPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationStatisticsPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Statistics == nil {
		return &LongVegetationStatisticsPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation statistics preferences service is unavailable"}
	}
	return s.longPreferences.Statistics.SaveLongVegetationStatisticsPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationSwitchPreferences(ctx context.Context, contextID string) (*LongVegetationSwitchPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Switch == nil {
		return nil, errors.New("long vegetation switch preferences service is unavailable")
	}
	return s.longPreferences.Switch.GetLongVegetationSwitchPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationSwitchPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationSwitchPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Switch == nil {
		return &LongVegetationSwitchPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation switch preferences service is unavailable"}
	}
	return s.longPreferences.Switch.SaveLongVegetationSwitchPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationThresholdPreferences(ctx context.Context, contextID string) (*LongVegetationThresholdPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Threshold == nil {
		return nil, errors.New("long vegetation threshold preferences service is unavailable")
	}
	return s.longPreferences.Threshold.GetLongVegetationThresholdPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationThresholdPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationThresholdPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Threshold == nil {
		return &LongVegetationThresholdPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation threshold preferences service is unavailable"}
	}
	return s.longPreferences.Threshold.SaveLongVegetationThresholdPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationGroupPreferences(ctx context.Context, contextID string) (*LongVegetationGroupPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Group == nil {
		return nil, errors.New("long vegetation group preferences service is unavailable")
	}
	return s.longPreferences.Group.GetLongVegetationGroupPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationGroupPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationGroupPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Group == nil {
		return &LongVegetationGroupPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation group preferences service is unavailable"}
	}
	return s.longPreferences.Group.SaveLongVegetationGroupPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationQualityNullPreferences(ctx context.Context, contextID string) (*LongVegetationQualityNullPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.QualityNull == nil {
		return nil, errors.New("long vegetation quality null preferences service is unavailable")
	}
	return s.longPreferences.QualityNull.GetLongVegetationQualityNullPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationQualityNullPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationQualityNullPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.QualityNull == nil {
		return &LongVegetationQualityNullPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation quality null preferences service is unavailable"}
	}
	return s.longPreferences.QualityNull.SaveLongVegetationQualityNullPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationQualityMinimumPreferences(ctx context.Context, contextID string) (*LongVegetationQualityMinimumPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.QualityMin == nil {
		return nil, errors.New("long vegetation quality minimum preferences service is unavailable")
	}
	return s.longPreferences.QualityMin.GetLongVegetationQualityMinimumPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationQualityMinimumPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationQualityMinimumPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.QualityMin == nil {
		return &LongVegetationQualityMinimumPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation quality minimum preferences service is unavailable"}
	}
	return s.longPreferences.QualityMin.SaveLongVegetationQualityMinimumPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationNamingPreferences(ctx context.Context, contextID string) (*LongVegetationNamingPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Naming == nil {
		return nil, errors.New("long vegetation naming preferences service is unavailable")
	}
	return s.longPreferences.Naming.GetLongVegetationNamingPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationNamingPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationNamingPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Naming == nil {
		return &LongVegetationNamingPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation naming preferences service is unavailable"}
	}
	return s.longPreferences.Naming.SaveLongVegetationNamingPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationSelectedFieldPreferences(ctx context.Context, contextID string) (*LongVegetationSelectedFieldPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.SelectedField == nil {
		return nil, errors.New("long vegetation selected field preferences service is unavailable")
	}
	return s.longPreferences.SelectedField.GetLongVegetationSelectedFieldPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationSelectedFieldPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationSelectedFieldPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.SelectedField == nil {
		return &LongVegetationSelectedFieldPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation selected field preferences service is unavailable"}
	}
	return s.longPreferences.SelectedField.SaveLongVegetationSelectedFieldPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationEnforcementPreferences(ctx context.Context, contextID string) (*LongVegetationEnforcementPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Enforcement == nil {
		return nil, errors.New("long vegetation enforcement preferences service is unavailable")
	}
	return s.longPreferences.Enforcement.GetLongVegetationEnforcementPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationEnforcementPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationEnforcementPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Enforcement == nil {
		return &LongVegetationEnforcementPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation enforcement preferences service is unavailable"}
	}
	return s.longPreferences.Enforcement.SaveLongVegetationEnforcementPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) GetLongVegetationUnitPreferences(ctx context.Context, contextID string) (*LongVegetationUnitPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Unit == nil {
		return nil, errors.New("long vegetation unit preferences service is unavailable")
	}
	return s.longPreferences.Unit.GetLongVegetationUnitPreferences(ctx, contextID)
}

func (s *VegetationReportService) SaveLongVegetationUnitPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationUnitPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longPreferences == nil || s.longPreferences.Unit == nil {
		return &LongVegetationUnitPreferencesOutcome{ContextID: contextID, ErrorMessage: "long vegetation unit preferences service is unavailable"}
	}
	return s.longPreferences.Unit.SaveLongVegetationUnitPreferences(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) BuildLongVegetationSelectedUnitSelection(ctx context.Context, contextID, revision string) (*LongVegetationSelectedUnitSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longSelectedUnitSelection == nil {
		return nil, errors.New("long vegetation selected unit selection service is unavailable")
	}
	return s.longSelectedUnitSelection.BuildLongVegetationSelectedUnitSelection(ctx, contextID, revision)
}

func (s *VegetationReportService) GetLongVegetationSelectedUnitSelection(ctx context.Context, contextID string) (*LongVegetationSelectedUnitSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longSelectedUnitSelection == nil {
		return nil, errors.New("long vegetation selected unit selection service is unavailable")
	}
	return s.longSelectedUnitSelection.GetLongVegetationSelectedUnitSelection(ctx, contextID)
}

func (s *VegetationReportService) SetLongVegetationSelectedUnitFields(ctx context.Context, contextID, requestJSON string) (*LongVegetationSelectedUnitSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longSelectedUnitSelection == nil {
		return nil, errors.New("long vegetation selected unit selection service is unavailable")
	}
	return s.longSelectedUnitSelection.SetLongVegetationSelectedUnitFields(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) BuildLongVegetationProjectScope(ctx context.Context, contextID, revision string) (*LongVegetationReportScope, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return nil, errors.New("long vegetation report scope service is unavailable")
	}
	return s.longReportScope.BuildLongVegetationProjectScope(ctx, contextID, revision)
}

func (s *VegetationReportService) GetLongVegetationProjectFieldDefinitions(ctx context.Context, contextID string) (*LongVegetationProjectFieldDefinitions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return nil, errors.New("long vegetation report scope service is unavailable")
	}
	return s.longReportScope.GetLongVegetationProjectFieldDefinitions(ctx, contextID)
}

func (s *VegetationReportService) GetLongVegetationProjectOptions(ctx context.Context, contextID string, request LongVegetationProjectReadRequest) (LongVegetationProjectOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return LongVegetationProjectOptions{}, errors.New("long vegetation report scope service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return LongVegetationProjectOptions{}, err
	}
	return s.longReportScope.GetLongVegetationProjectOptions(ctx, contextID, raw)
}

func (s *VegetationReportService) GetLongVegetationProjectUnitPreferences(ctx context.Context, contextID string, request LongVegetationProjectReadRequest) (LongVegetationProjectUnitPreferences, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return LongVegetationProjectUnitPreferences{}, errors.New("long vegetation report scope service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return LongVegetationProjectUnitPreferences{}, err
	}
	return s.longReportScope.GetLongVegetationProjectUnitPreferences(ctx, contextID, raw)
}

func (s *VegetationReportService) GetLongVegetationReportScope(ctx context.Context, contextID string) (*LongVegetationReportScope, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return nil, errors.New("long vegetation report scope service is unavailable")
	}
	return s.longReportScope.GetLongVegetationReportScope(ctx, contextID)
}

func (s *VegetationReportService) PreviewLongVegetationProject(ctx context.Context, contextID string, request LongVegetationProjectReadRequest) (LongVegetationProjectPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return LongVegetationProjectPreview{}, errors.New("long vegetation report scope service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return LongVegetationProjectPreview{}, err
	}
	return s.longReportScope.PreviewLongVegetationProject(ctx, contextID, raw)
}

func (s *VegetationReportService) SaveLongVegetationProjectUnits(ctx context.Context, contextID string, request LongVegetationProjectUnitRequest) LongVegetationProjectUnitOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return LongVegetationProjectUnitOutcome{
			Outcome: LongVegetationUnitPreferencesOutcome{
				ContextID:    contextID,
				ErrorMessage: "long vegetation report scope service is unavailable",
			},
		}
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return LongVegetationProjectUnitOutcome{
			Revision: request.Revision,
			Outcome: LongVegetationUnitPreferencesOutcome{
				ContextID:    contextID,
				ErrorMessage: err.Error(),
			},
		}
	}
	return s.longReportScope.SaveLongVegetationProjectUnits(ctx, contextID, raw)
}

func (s *VegetationReportService) SetLongVegetationProjectFields(ctx context.Context, contextID string, request LongVegetationSelectedUnitFieldsRequest) (*LongVegetationReportScope, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return nil, errors.New("long vegetation report scope service is unavailable")
	}
	if request.Fields == nil {
		request.Fields = []string{}
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.longReportScope.SetLongVegetationProjectFields(ctx, contextID, raw)
}

func (s *VegetationReportService) SetLongVegetationReportScope(ctx context.Context, contextID string, request LongVegetationScopeRequest) (*LongVegetationReportScope, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longReportScope == nil {
		return nil, errors.New("long vegetation report scope service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.longReportScope.SetLongVegetationReportScope(ctx, contextID, raw)
}

func (s *VegetationReportService) GetLongVegetationProjectWorkbookReview(ctx context.Context, contextID string, request LongVegetationProjectWorkbookReadRequest) (*LongVegetationProjectWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longProjectWorkbook == nil {
		return nil, errors.New("long vegetation project workbook service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.longProjectWorkbook.GetReview(ctx, contextID, raw)
}

func (s *VegetationReportService) ExportReviewedLongVegetationProjectWorkbook(ctx context.Context, contextID string, request LongVegetationProjectWorkbookExportRequest) (*VegetationWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longProjectWorkbook == nil {
		return nil, errors.New("long vegetation project workbook service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.longProjectWorkbook.ExportReviewed(ctx, contextID, raw)
}

func (s *VegetationReportService) GetVegetationWorkbookReview(ctx context.Context, contextID, requestJSON string) (*VegetationWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.vegetationWorkbook == nil {
		return nil, errors.New("vegetation workbook service is unavailable")
	}
	return s.vegetationWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) ExportReviewedVegetationWorkbook(ctx context.Context, contextID, requestJSON string) (*VegetationWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.vegetationWorkbook == nil {
		return nil, errors.New("vegetation workbook service is unavailable")
	}
	return s.vegetationWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

// Lifeform & Species Attribute Summary delegates

func (s *VegetationReportService) PreviewLifeformSummary(ctx context.Context, contextID string) (LifeformSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.lifeformSummary == nil {
		return LifeformSummaryPreview{}, errors.New("lifeform summary service is unavailable")
	}
	return s.lifeformSummary.Preview(ctx, contextID)
}

func (s *VegetationReportService) PreviewLifeformSummaryWithHierarchyBreakpoints(ctx context.Context, contextID, breakpointPolicy string) (LifeformSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.lifeformSummary == nil {
		return LifeformSummaryPreview{}, errors.New("lifeform summary service is unavailable")
	}
	return s.lifeformSummary.PreviewWithHierarchyBreakpoints(ctx, contextID, breakpointPolicy)
}

func (s *VegetationReportService) GetLifeformWorkbookReview(ctx context.Context, contextID, requestJSON string) (*LifeformWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.lifeformWorkbook == nil {
		return nil, errors.New("lifeform workbook service is unavailable")
	}
	return s.lifeformWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) ExportReviewedLifeformWorkbook(ctx context.Context, contextID, requestJSON string) (*LifeformWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.lifeformWorkbook == nil {
		return nil, errors.New("lifeform workbook service is unavailable")
	}
	return s.lifeformWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *VegetationReportService) PreviewSpeciesAttributeSummary(ctx context.Context, contextID string) (SpeciesAttributeSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.speciesAttributeSummary == nil {
		return SpeciesAttributeSummaryPreview{}, errors.New("species attribute summary service is unavailable")
	}
	return s.speciesAttributeSummary.Preview(ctx, contextID)
}

func (s *VegetationReportService) PreviewSpeciesAttributeSummaryWithHierarchyBreakpoints(ctx context.Context, contextID, breakpointPolicy string) (SpeciesAttributeSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.speciesAttributeSummary == nil {
		return SpeciesAttributeSummaryPreview{}, errors.New("species attribute summary service is unavailable")
	}
	return s.speciesAttributeSummary.PreviewWithHierarchyBreakpoints(ctx, contextID, breakpointPolicy)
}

// SiteUnit Exclusion Filters (.support, .poor, .nudum) & Dynamic Hierarchy Breakpoint (~) delegates

func (s *VegetationReportService) GetDefaultSiteUnitExclusions() []string {
	return vegreportpkg.DefaultSiteUnitExclusionPatterns()
}

func (s *VegetationReportService) PreviewSiteUnitExclusions(ctx context.Context, contextID string, request SiteUnitExclusionPreviewRequest) (*SiteUnitExclusionPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("vegetation report context is unavailable")
	}
	return vegreportpkg.PreviewSiteUnitExclusions(ctx, unwrapContextService(s.contexts), contextID, request)
}

func (s *VegetationReportService) ResolveHierarchyBreakpointUnits(ctx context.Context, contextID string, request HierarchyBreakpointRequest) (*HierarchyBreakpointResolution, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("vegetation report context is unavailable")
	}
	return vegreportpkg.ResolveHierarchyBreakpointUnits(ctx, unwrapContextService(s.contexts), contextID, request)
}

func (s *VegetationReportService) PreviewSummaryVegetationWithExclusions(ctx context.Context, contextID string, request SummaryVegetationExclusionRequest) (*SummaryVegetationExclusionPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("vegetation report context is unavailable")
	}
	return vegreportpkg.PreviewSummaryVegetationWithExclusions(ctx, unwrapContextService(s.contexts), contextID, request)
}

func (s *VegetationReportService) PreviewLongVegetationWithExclusions(ctx context.Context, contextID string, request LongVegetationExclusionRequest) (*LongVegetationExclusionPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("vegetation report context is unavailable")
	}
	return vegreportpkg.PreviewLongVegetationWithExclusions(ctx, unwrapContextService(s.contexts), contextID, request)
}
