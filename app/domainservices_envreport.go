package main

import (
	"context"
	"errors"

	envreportpkg "github.com/boostao/vpro/app/internal/envreport"
	rsidecarpkg "github.com/boostao/vpro/app/internal/rsidecar"
)

type QuickEnvReportExportResult = envreportpkg.QuickEnvReportExportResult
type QuickLongEnvironmentRequest = envreportpkg.QuickLongEnvironmentRequest
type QuickSummaryEnvironmentRequest = envreportpkg.QuickSummaryEnvironmentRequest
type QuickSubzoneMatrixRequest = envreportpkg.QuickSubzoneMatrixRequest

type RPackageStatus = rsidecarpkg.RPackageStatus
type RRuntimeStatus = rsidecarpkg.RRuntimeStatus
type PlotClimateRow = rsidecarpkg.PlotClimateRow
type EdatopicGridCell = rsidecarpkg.EdatopicGridCell
type EdatopicGridMatrix = rsidecarpkg.EdatopicGridMatrix
type DualUnitEdatopicSummary = rsidecarpkg.DualUnitEdatopicSummary
type ClimateEdatopicRequest = rsidecarpkg.ClimateEdatopicRequest
type ClimateEdatopicResult = rsidecarpkg.ClimateEdatopicResult
type ClusterIndicatorSpecies = rsidecarpkg.ClusterIndicatorSpecies
type ClusterUnitSummary = rsidecarpkg.ClusterUnitSummary
type ClusterPlotMembership = rsidecarpkg.ClusterPlotMembership
type DendrogramSegment = rsidecarpkg.DendrogramSegment
type DendrogramLeaf = rsidecarpkg.DendrogramLeaf
type DendrogramGeometry = rsidecarpkg.DendrogramGeometry
type ClusteringRequest = rsidecarpkg.ClusteringRequest
type ClusteringResult = rsidecarpkg.ClusteringResult
type PromoteCandidateSURequest = rsidecarpkg.PromoteCandidateSURequest
type PromoteCandidateSUResult = rsidecarpkg.PromoteCandidateSUResult
type QuartoVegSummaryRow = rsidecarpkg.QuartoVegSummaryRow
type QuartoGuideRequest = rsidecarpkg.QuartoGuideRequest
type QuartoGuideResult = rsidecarpkg.QuartoGuideResult
type SiteUnitSummaryFullPreferenceValues = envreportpkg.SiteUnitSummaryFullPreferenceValues
type SiteUnitSummaryFullPreferences = envreportpkg.SiteUnitSummaryFullPreferences

type EnvironmentReportService struct {
	runtime                         *runtimeShutdownTracker
	contexts                        *ContextService
	environmentWorkbook             *envreportpkg.EnvironmentWorkbookService
	longEnvironmentPreferences      *envreportpkg.LongEnvironmentPreferencesService
	siteUnitSummaryPreferences      *envreportpkg.SiteUnitSummaryPreferencesService
	siteUnitSummaryWorkbook         *envreportpkg.SiteUnitSummaryWorkbookService
	siteUnitSummaryExtendedWorkbook *envreportpkg.SiteUnitSummaryExtendedWorkbookService
	subzoneMatrix                   *envreportpkg.SubzoneMatrixService
	dataDir                         string
}

func (s *EnvironmentReportService) acquire() (*EnvironmentReportService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.envReport, release
}

func buildEnvironmentReportService(contexts *ContextService, dataDir string) (EnvironmentReportService, error) {
	core := unwrapContextService(contexts)
	environmentWorkbook, err := envreportpkg.NewEnvironmentWorkbookService(core)
	if err != nil {
		return EnvironmentReportService{}, err
	}
	siteUnitSummaryWorkbook, err := envreportpkg.NewSiteUnitSummaryWorkbookService(core)
	if err != nil {
		return EnvironmentReportService{}, err
	}
	siteUnitSummaryExtendedWorkbook, err := envreportpkg.NewSiteUnitSummaryExtendedWorkbookService(core)
	if err != nil {
		return EnvironmentReportService{}, err
	}
	subzoneMatrix, err := envreportpkg.NewSubzoneMatrixService(core)
	if err != nil {
		return EnvironmentReportService{}, err
	}
	return EnvironmentReportService{
		contexts:                        contexts,
		environmentWorkbook:             environmentWorkbook,
		longEnvironmentPreferences:      envreportpkg.NewLongEnvironmentPreferencesService(core),
		siteUnitSummaryPreferences:      envreportpkg.NewSiteUnitSummaryPreferencesService(core),
		siteUnitSummaryWorkbook:         siteUnitSummaryWorkbook,
		siteUnitSummaryExtendedWorkbook: siteUnitSummaryExtendedWorkbook,
		subzoneMatrix:                   subzoneMatrix,
		dataDir:                         dataDir,
	}, nil
}

func (s *EnvironmentReportService) rRuntimeOptions() []rsidecarpkg.RuntimeOptions {
	if s == nil || s.dataDir == "" {
		return nil
	}
	return []rsidecarpkg.RuntimeOptions{{DataDir: s.dataDir}}
}

func (s *EnvironmentReportService) GetLongEnvironmentOptions(ctx context.Context, contextID string) (LongEnvironmentOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return LongEnvironmentOptions{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.GetLongEnvironmentOptions(ctx, contextID)
}

func (s *EnvironmentReportService) PreviewLongEnvironment(ctx context.Context, contextID string, request LongEnvironmentRequest) (LongEnvironmentPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return LongEnvironmentPreview{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.PreviewLongEnvironment(ctx, contextID, request)
}

func (s *EnvironmentReportService) GetLongEnvironmentPreferences(ctx context.Context, contextID string) (*LongEnvironmentPreferencesReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longEnvironmentPreferences == nil {
		return nil, errors.New("long environment preferences service is unavailable")
	}
	return s.longEnvironmentPreferences.GetLongEnvironmentPreferences(ctx, contextID)
}

func (s *EnvironmentReportService) SaveLongEnvironmentPreferences(ctx context.Context, contextID, requestJSON string) *LongEnvironmentPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.longEnvironmentPreferences == nil {
		return &LongEnvironmentPreferencesOutcome{ContextID: contextID, ErrorMessage: "long environment preferences service is unavailable"}
	}
	return s.longEnvironmentPreferences.SaveLongEnvironmentPreferences(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetEnvironmentWorkbookReview(ctx context.Context, contextID, requestJSON string) (*EnvironmentWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.environmentWorkbook == nil {
		return nil, errors.New("environment workbook service is unavailable")
	}
	return s.environmentWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) ExportReviewedEnvironmentWorkbook(ctx context.Context, contextID, requestJSON string) (*EnvironmentWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.environmentWorkbook == nil {
		return nil, errors.New("environment workbook service is unavailable")
	}
	return s.environmentWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetSiteUnitSummaryOptions(ctx context.Context, contextID string) (SiteUnitSummaryOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return SiteUnitSummaryOptions{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.GetSiteUnitSummaryOptions(ctx, contextID)
}

func (s *EnvironmentReportService) PreviewSiteUnitSummary(ctx context.Context, contextID string, request SiteUnitSummaryRequest) (SiteUnitSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return SiteUnitSummaryPreview{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.PreviewSiteUnitSummary(ctx, contextID, request)
}

func (s *EnvironmentReportService) PreviewSiteUnitSummaryLifeforms(ctx context.Context, contextID string, request SiteUnitSummaryRequest) (SiteUnitSummaryPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return SiteUnitSummaryPreview{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.PreviewSiteUnitSummaryLifeforms(ctx, contextID, request)
}

func (s *EnvironmentReportService) PreviewSiteUnitSummarySpecies(ctx context.Context, contextID string, request SiteUnitSpeciesListRequest) (SiteUnitSpeciesListPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return SiteUnitSpeciesListPreview{}, errors.New("environment report context is unavailable")
	}
	return s.contexts.PreviewSiteUnitSummarySpecies(ctx, contextID, request)
}

func (s *EnvironmentReportService) GetSiteUnitSummaryPreferences(ctx context.Context, contextID string) (*SiteUnitSummaryOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryPreferences == nil {
		return nil, errors.New("site unit summary preferences service is unavailable")
	}
	return s.siteUnitSummaryPreferences.GetSiteUnitSummaryPreferences(ctx, contextID)
}

func (s *EnvironmentReportService) SaveSiteUnitSummaryPreferences(ctx context.Context, contextID, requestJSON string) *SiteUnitSummaryPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryPreferences == nil {
		return &SiteUnitSummaryPreferencesOutcome{ContextID: contextID, ErrorMessage: "site unit summary preferences service is unavailable"}
	}
	return s.siteUnitSummaryPreferences.SaveSiteUnitSummaryPreferences(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetFullSiteUnitSummaryPreferences(ctx context.Context, contextID string) (*SiteUnitSummaryFullPreferences, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryPreferences == nil {
		return nil, errors.New("site unit summary preferences service is unavailable")
	}
	return s.siteUnitSummaryPreferences.GetFullSiteUnitSummaryPreferences(ctx, contextID)
}

func (s *EnvironmentReportService) SaveFullSiteUnitSummaryPreferences(ctx context.Context, contextID, requestJSON string) *SiteUnitSummaryPreferencesOutcome {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryPreferences == nil {
		return &SiteUnitSummaryPreferencesOutcome{ContextID: contextID, ErrorMessage: "site unit summary preferences service is unavailable"}
	}
	return s.siteUnitSummaryPreferences.SaveFullSiteUnitSummaryPreferences(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetSiteUnitSummaryWorkbookReview(ctx context.Context, contextID, requestJSON string) (*SiteUnitSummaryWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryWorkbook == nil {
		return nil, errors.New("site unit summary workbook service is unavailable")
	}
	return s.siteUnitSummaryWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) ExportReviewedSiteUnitSummaryWorkbook(ctx context.Context, contextID, requestJSON string) (*SiteUnitSummaryWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryWorkbook == nil {
		return nil, errors.New("site unit summary workbook service is unavailable")
	}
	return s.siteUnitSummaryWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetSiteUnitSummaryExtendedWorkbookReview(ctx context.Context, contextID, requestJSON string) (*SiteUnitSummaryExtendedWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryExtendedWorkbook == nil {
		return nil, errors.New("site unit summary extended workbook service is unavailable")
	}
	return s.siteUnitSummaryExtendedWorkbook.GetReview(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) ExportReviewedSiteUnitSummaryExtendedWorkbook(ctx context.Context, contextID, requestJSON string) (*SiteUnitSummaryWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.siteUnitSummaryExtendedWorkbook == nil {
		return nil, errors.New("site unit summary extended workbook service is unavailable")
	}
	return s.siteUnitSummaryExtendedWorkbook.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetSubzoneMatrixPreview(ctx context.Context, contextID, requestJSON string) (*SubzoneMatrixPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.subzoneMatrix == nil {
		return nil, errors.New("subzone matrix service is unavailable")
	}
	return s.subzoneMatrix.GetPreview(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) GetSubzoneMatrixReview(ctx context.Context, contextID string) (*SubzoneMatrixWorkbookReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.subzoneMatrix == nil {
		return nil, errors.New("subzone matrix service is unavailable")
	}
	return s.subzoneMatrix.GetReview(ctx, contextID)
}

func (s *EnvironmentReportService) ExportReviewedSubzoneMatrix(ctx context.Context, contextID, requestJSON string) (*SubzoneMatrixWorkbookOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.subzoneMatrix == nil {
		return nil, errors.New("subzone matrix service is unavailable")
	}
	return s.subzoneMatrix.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *EnvironmentReportService) DetectRRuntime(ctx context.Context) (*RRuntimeStatus, error) {
	s, release := s.acquire()
	defer release()
	return rsidecarpkg.DetectRRuntime(ctx, s.rRuntimeOptions()...)
}

func (s *EnvironmentReportService) GetCachedPlotClimate(ctx context.Context, contextID, refPeriod string) ([]PlotClimateRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return rsidecarpkg.GetCachedPlotClimate(ctx, unwrapContextService(s.contexts), contextID, refPeriod)
}

func (s *EnvironmentReportService) ComputePlotClimateAndDualEdatopic(ctx context.Context, contextID string, request ClimateEdatopicRequest) (*ClimateEdatopicResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return rsidecarpkg.ComputePlotClimateAndDualEdatopic(ctx, unwrapContextService(s.contexts), contextID, request, s.rRuntimeOptions()...)
}

func (s *EnvironmentReportService) RunMultivariateClustering(ctx context.Context, contextID string, request ClusteringRequest) (*ClusteringResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return rsidecarpkg.RunMultivariateClustering(ctx, unwrapContextService(s.contexts), contextID, request, s.rRuntimeOptions()...)
}

func (s *EnvironmentReportService) PromoteClusterCandidateToSU(ctx context.Context, contextID string, request PromoteCandidateSURequest) (*PromoteCandidateSUResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return rsidecarpkg.PromoteClusterCandidateToSU(ctx, unwrapContextService(s.contexts), contextID, request)
}

func (s *EnvironmentReportService) RenderQuartoGuide(ctx context.Context, contextID string, request QuartoGuideRequest) (*QuartoGuideResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return rsidecarpkg.RenderQuartoGuide(ctx, unwrapContextService(s.contexts), contextID, request, s.rRuntimeOptions()...)
}

// Streamlined one-step QuickRun, Quarto-style HTML display & Spreadsheet Launcher delegates

func (s *EnvironmentReportService) QuickRunLongEnvironmentWorkbook(ctx context.Context, contextID string, request QuickLongEnvironmentRequest) (*QuickEnvReportExportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.QuickExportLongEnvironmentWorkbook(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *EnvironmentReportService) RenderLongEnvironmentHTMLReport(ctx context.Context, contextID string, request QuickLongEnvironmentRequest) (*HTMLReportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.RenderLongEnvironmentHTMLReport(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *EnvironmentReportService) QuickRunSummaryEnvironmentWorkbook(ctx context.Context, contextID string, request QuickSummaryEnvironmentRequest) (*QuickEnvReportExportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.QuickExportSummaryEnvironmentWorkbook(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *EnvironmentReportService) RenderSummaryEnvironmentHTMLReport(ctx context.Context, contextID string, request QuickSummaryEnvironmentRequest) (*HTMLReportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.RenderSummaryEnvironmentHTMLReport(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *EnvironmentReportService) QuickRunSubzoneMatrixWorkbook(ctx context.Context, contextID string, request QuickSubzoneMatrixRequest) (*QuickEnvReportExportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.QuickExportSubzoneMatrixWorkbook(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *EnvironmentReportService) RenderSubzoneMatrixHTMLReport(ctx context.Context, contextID string) (*HTMLReportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("environment report context is unavailable")
	}
	return envreportpkg.RenderSubzoneMatrixHTMLReport(unwrapContextService(s.contexts), ctx, contextID)
}

func (s *EnvironmentReportService) GetSpreadsheetAppPreference(ctx context.Context, contextID string) (SpreadsheetAppPreference, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return SpreadsheetAppPreference{}, errors.New("environment report context is unavailable")
	}
	return unwrapContextService(s.contexts).GetSpreadsheetAppPreference(ctx, contextID)
}

func (s *EnvironmentReportService) SetSpreadsheetAppPreference(ctx context.Context, contextID string, pref SpreadsheetAppPreference) (SpreadsheetAppPreference, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return SpreadsheetAppPreference{}, errors.New("environment report context is unavailable")
	}
	return unwrapContextService(s.contexts).SetSpreadsheetAppPreference(ctx, contextID, pref)
}

func (s *EnvironmentReportService) OpenReportInSpreadsheet(ctx context.Context, contextID, filePath string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return errors.New("environment report context is unavailable")
	}
	return unwrapContextService(s.contexts).OpenReportInSpreadsheet(ctx, contextID, filePath)
}
