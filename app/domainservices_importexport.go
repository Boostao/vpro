package main

import (
	"context"
	"errors"

	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/lumping"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type ImportExportService struct {
	runtime           *runtimeShutdownTracker
	contexts          *ContextService
	tableCSVArchive   *interchange.TableCSVArchiveService
	plotLabelRegional *interchange.PlotLabelRegionalService
	plotLabelPDF      *interchange.PlotLabelPDFExportService
}

func (s *ImportExportService) acquire() (*ImportExportService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.importExport, release
}

func NewImportExportService(
	contexts *ContextService,
	tableCSVArchive *interchange.TableCSVArchiveService,
	plotLabelRegional *interchange.PlotLabelRegionalService,
	plotLabelPDF *interchange.PlotLabelPDFExportService,
) *ImportExportService {
	return &ImportExportService{
		contexts:          contexts,
		tableCSVArchive:   tableCSVArchive,
		plotLabelRegional: plotLabelRegional,
		plotLabelPDF:      plotLabelPDF,
	}
}

func buildImportExportService(contexts *ContextService) (*ImportExportService, error) {
	core := unwrapContextService(contexts)
	plotLabelRegional, err := interchange.NewPlotLabelRegionalService(core)
	if err != nil {
		return nil, err
	}
	return NewImportExportService(
		contexts,
		interchange.NewTableCSVArchiveService(core),
		plotLabelRegional,
		interchange.NewPlotLabelPDFExportService(core),
	), nil
}

func (s *ImportExportService) ChooseAccessDatabaseFile(ctx context.Context, contextID string) (string, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return "", errors.New("import/export context is unavailable")
	}
	return s.contexts.ChooseAccessDatabaseFile(ctx, contextID)
}

// ChooseTableCSVArchiveFile opens a native OS save-file dialog for the project table CSV ZIP archive.
func (s *ImportExportService) ChooseTableCSVArchiveFile(ctx context.Context) (string, error) {
	return vprocorepkg.ChooseNativeSaveFile(
		ctx,
		"Select project table CSV archive destination",
		"project-tables.zip",
		"zip",
		"Project table CSV archive (.zip)",
		"*.zip",
	)
}

func (s *ImportExportService) InspectAccessDatabase(ctx context.Context, contextID, sourcePath string) (AccessDatabaseInspection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return AccessDatabaseInspection{}, errors.New("import/export context is unavailable")
	}
	return s.contexts.InspectAccessDatabase(ctx, contextID, sourcePath)
}

func (s *ImportExportService) ImportAccessProject(ctx context.Context, contextID string, request AccessProjectImportRequest) (AccessProjectImportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return AccessProjectImportResult{}, errors.New("import/export context is unavailable")
	}
	return s.contexts.ImportAccessProject(ctx, contextID, request)
}

func (s *ImportExportService) GetProjectTableCSVReview(ctx context.Context, contextID, table string) (*ProjectTableCSVReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("import/export context is unavailable")
	}
	return s.contexts.GetProjectTableCSVReview(ctx, contextID, table)
}

func (s *ImportExportService) GetTableCSVArchiveReview(ctx context.Context, contextID, requestJSON string) (*TableCSVArchiveReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.tableCSVArchive == nil {
		return nil, errors.New("table CSV archive service is unavailable")
	}
	return s.tableCSVArchive.GetTableCSVArchiveReview(ctx, contextID, requestJSON)
}

func (s *ImportExportService) ExportReviewedTableCSVArchive(ctx context.Context, contextID, requestJSON string) (*TableCSVArchiveOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.tableCSVArchive == nil {
		return nil, errors.New("table CSV archive service is unavailable")
	}
	return s.tableCSVArchive.ExportReviewedTableCSVArchive(ctx, contextID, requestJSON)
}

func (s *ImportExportService) GetPlotLabelRegionalPreview(ctx context.Context, contextID, plot string) (*PlotLabelRegionalPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plotLabelRegional == nil {
		return nil, errors.New("plot label regional service is unavailable")
	}
	return s.plotLabelRegional.GetPreview(ctx, contextID, plot)
}

func (s *ImportExportService) GetPlotLabelPDFReview(ctx context.Context, contextID, requestJSON string) (*PlotLabelPDFExportReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plotLabelPDF == nil {
		return nil, errors.New("plot label PDF export service is unavailable")
	}
	return s.plotLabelPDF.GetReview(ctx, contextID, requestJSON)
}

func (s *ImportExportService) ExportReviewedPlotLabelPDF(ctx context.Context, contextID, requestJSON string) (*PlotLabelPDFExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plotLabelPDF == nil {
		return nil, errors.New("plot label PDF export service is unavailable")
	}
	return s.plotLabelPDF.ExportReviewed(ctx, contextID, requestJSON)
}

func (s *ImportExportService) RecoverPlotLabelPDFOutcome(ctx context.Context, contextID, requestJSON string) (*PlotLabelPDFAttemptOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.plotLabelPDF == nil {
		return nil, errors.New("plot label PDF export service is unavailable")
	}
	return s.plotLabelPDF.RecoverOutcome(ctx, contextID, requestJSON)
}

// Combine Species (*_Lump) CRUD & Declarative LumpSpec Recipes (Auto-5)

func (s *ImportExportService) DiscoverLumpTables(ctx context.Context, contextID string, externalPaths []string) ([]lumping.LumpTableSummary, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return nil, errors.New("import/export context is unavailable")
	}
	return lumping.DiscoverLumpTables(unwrapContextService(s.contexts), ctx, contextID, externalPaths)
}

func (s *ImportExportService) CreateLumpTable(ctx context.Context, contextID, name string) (lumping.LumpTableSummary, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpTableSummary{}, errors.New("import/export context is unavailable")
	}
	return lumping.CreateLumpTable(unwrapContextService(s.contexts), ctx, contextID, name)
}

func (s *ImportExportService) SaveAsLumpTable(ctx context.Context, contextID, sourceTable, sourceDBPath, targetName string) (lumping.LumpTableSummary, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpTableSummary{}, errors.New("import/export context is unavailable")
	}
	return lumping.SaveAsLumpTable(unwrapContextService(s.contexts), ctx, contextID, sourceTable, sourceDBPath, targetName)
}

func (s *ImportExportService) DeleteLumpTable(ctx context.Context, contextID, name string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return errors.New("import/export context is unavailable")
	}
	return lumping.DeleteLumpTable(unwrapContextService(s.contexts), ctx, contextID, name)
}

func (s *ImportExportService) GetLumpTableRows(ctx context.Context, contextID, tableName, dbPath string) ([]lumping.LumpRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return nil, errors.New("import/export context is unavailable")
	}
	return lumping.GetLumpTableRows(unwrapContextService(s.contexts), ctx, contextID, tableName, dbPath)
}

func (s *ImportExportService) UpsertLumpRow(ctx context.Context, contextID, tableName string, input lumping.LumpRowInput) (lumping.LumpRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpRow{}, errors.New("import/export context is unavailable")
	}
	return lumping.UpsertLumpRow(unwrapContextService(s.contexts), ctx, contextID, tableName, input)
}

func (s *ImportExportService) UpdateLumpRow(ctx context.Context, contextID, tableName, existingSppCode string, input lumping.LumpRowInput) (lumping.LumpRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpRow{}, errors.New("import/export context is unavailable")
	}
	return lumping.UpdateLumpRow(unwrapContextService(s.contexts), ctx, contextID, tableName, existingSppCode, input)
}

func (s *ImportExportService) DeleteLumpRow(ctx context.Context, contextID, tableName, sppCode string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return errors.New("import/export context is unavailable")
	}
	return lumping.DeleteLumpRow(unwrapContextService(s.contexts), ctx, contextID, tableName, sppCode)
}

func (s *ImportExportService) ToggleLumpRow(ctx context.Context, contextID, tableName, sppCode string, use bool) (lumping.LumpRow, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpRow{}, errors.New("import/export context is unavailable")
	}
	return lumping.ToggleLumpRow(unwrapContextService(s.contexts), ctx, contextID, tableName, sppCode, use)
}

func (s *ImportExportService) SetAllLumpRowsUse(ctx context.Context, contextID, tableName string, use bool) (int, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return 0, errors.New("import/export context is unavailable")
	}
	return lumping.SetAllLumpRowsUse(unwrapContextService(s.contexts), ctx, contextID, tableName, use)
}

func (s *ImportExportService) PreviewLumpImpact(ctx context.Context, contextID, tableName, dbPath string) (lumping.LumpImpactPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpImpactPreview{}, errors.New("import/export context is unavailable")
	}
	return lumping.PreviewLumpImpact(unwrapContextService(s.contexts), ctx, contextID, tableName, dbPath)
}

func (s *ImportExportService) ListLumpPresets() []lumping.LumpPresetInfo {
	return lumping.ListLumpPresets()
}

func (s *ImportExportService) PreviewLumpSpec(ctx context.Context, contextID string, spec lumping.LumpSpec) (lumping.LumpSpecPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpSpecPreview{}, errors.New("import/export context is unavailable")
	}
	return lumping.PreviewLumpSpec(unwrapContextService(s.contexts), ctx, contextID, spec)
}

func (s *ImportExportService) MaterializeLumpSpec(ctx context.Context, contextID, targetName string, spec lumping.LumpSpec, replaceExisting bool) (lumping.LumpMaterializeResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return lumping.LumpMaterializeResult{}, errors.New("import/export context is unavailable")
	}
	return lumping.MaterializeLumpSpec(unwrapContextService(s.contexts), ctx, contextID, targetName, spec, replaceExisting)
}

// VENUS 5.0 (.mdb & .xml) Importer

func (s *ImportExportService) InspectVenusSource(ctx context.Context, contextID, sourcePath string) (interchange.VenusSourceInspection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.VenusSourceInspection{}, errors.New("import/export context is unavailable")
	}
	return interchange.InspectVenusSource(unwrapContextService(s.contexts), ctx, contextID, sourcePath)
}

func (s *ImportExportService) ImportVenusProject(ctx context.Context, contextID string, request interchange.VenusImportRequest) (interchange.VenusImportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.VenusImportResult{}, errors.New("import/export context is unavailable")
	}
	return interchange.ImportVenusProject(unwrapContextService(s.contexts), ctx, contextID, request)
}

// Official Alterra Turboveg 3 (31-table .sqlite) & <Plot_package> Standard XML Importer/Exporter

func (s *ImportExportService) ExportTurboVeg(ctx context.Context, contextID string, request interchange.TurboVegExportRequest) (interchange.TurboVegExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.TurboVegExportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportTurboVeg(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *ImportExportService) ImportTurboVeg(ctx context.Context, contextID string, request interchange.TurboVegImportRequest) (interchange.TurboVegImportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.TurboVegImportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ImportTurboVeg(unwrapContextService(s.contexts), ctx, contextID, request)
}

// User Species List (VUser.USysUserSpp) Export & Import

func (s *ImportExportService) ExportUserSpeciesList(ctx context.Context, contextID string, request interchange.UserSpeciesExportRequest) (interchange.UserSpeciesExportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.UserSpeciesExportResult{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportUserSpeciesList(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *ImportExportService) PreviewUserSpeciesImport(ctx context.Context, contextID string, request interchange.UserSpeciesImportRequest) (interchange.UserSpeciesImportPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.UserSpeciesImportPreview{}, errors.New("import/export context is unavailable")
	}
	return interchange.PreviewUserSpeciesImport(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *ImportExportService) ImportUserSpeciesList(ctx context.Context, contextID string, request interchange.UserSpeciesImportRequest) (interchange.UserSpeciesImportResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.UserSpeciesImportResult{}, errors.New("import/export context is unavailable")
	}
	return interchange.ImportUserSpeciesList(unwrapContextService(s.contexts), ctx, contextID, request)
}

// Long Tidy CSV, Wide Plot-by-Species Matrix CSV & R .rds Exporter

func (s *ImportExportService) ExportLongTidyCSV(ctx context.Context, contextID string, request interchange.LongTidyCSVRequest) (interchange.CSVExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.CSVExportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportLongTidyCSV(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *ImportExportService) ExportWideMatrixCSV(ctx context.Context, contextID string, request interchange.WideMatrixCSVRequest) (interchange.CSVExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.CSVExportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportWideMatrixCSV(unwrapContextService(s.contexts), ctx, contextID, request)
}

func (s *ImportExportService) ExportProjectRDS(ctx context.Context, contextID string, request interchange.RDSExportRequest) (interchange.RDSExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.RDSExportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportProjectRDS(unwrapContextService(s.contexts), ctx, contextID, request)
}

// OGC GeoPackage (.gpkg) EPSG:3005 / EPSG:4326 Exporter

func (s *ImportExportService) ExportGeoPackage(ctx context.Context, contextID string, request interchange.GeoPackageExportRequest) (interchange.GeoPackageExportOutcome, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || unwrapContextService(s.contexts) == nil {
		return interchange.GeoPackageExportOutcome{}, errors.New("import/export context is unavailable")
	}
	return interchange.ExportGeoPackage(unwrapContextService(s.contexts), ctx, contextID, request)
}
