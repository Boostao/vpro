package main

import (
	"context"
	"encoding/json"
	"errors"
	cloudsyncpkg "github.com/boostao/vpro/app/internal/cloudsync"
	interchangepkg "github.com/boostao/vpro/app/internal/interchange"
	validationpkg "github.com/boostao/vpro/app/internal/validation"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

// Provincial Cloud BECMaster PostgreSQL Sync, Staging Queue, Standards Sync & Custodian 3-Way Merge RPCs

func buildCloudComplianceValidator() cloudsyncpkg.ComplianceValidatorFunc {
	return func(ctx context.Context, core *vprocorepkg.ContextService, contextID string, useActiveSU bool) (cloudsyncpkg.ComplianceGateResult, error) {
		rep, err := validationpkg.RunComplianceValidation(core, ctx, contextID, validationpkg.ComplianceOptions{UseActiveSU: useActiveSU})
		if err != nil {
			return cloudsyncpkg.ComplianceGateResult{}, err
		}
		raw, _ := json.Marshal(rep)
		blocking := rep.Summary.EnvCodeErrors +
			rep.Summary.BoundsErrors +
			rep.Summary.EnvAdminMismatches +
			rep.Summary.OrphanChildRows +
			rep.Summary.DuplicateSpeciesSplits +
			rep.Summary.UnlistedSpecies +
			rep.Summary.SynonymSpecies
		return cloudsyncpkg.ComplianceGateResult{
			Passed:        rep.Passed,
			BlockingCount: blocking,
			Summary: map[string]int{
				"envCodeErrors":          rep.Summary.EnvCodeErrors,
				"boundsErrors":           rep.Summary.BoundsErrors,
				"envAdminMismatches":     rep.Summary.EnvAdminMismatches,
				"orphanChildRows":        rep.Summary.OrphanChildRows,
				"duplicateSpeciesSplits": rep.Summary.DuplicateSpeciesSplits,
				"unlistedSpecies":        rep.Summary.UnlistedSpecies,
				"synonymSpecies":         rep.Summary.SynonymSpecies,
				"userSpecies":            rep.Summary.UserSpecies,
				"plotsWithoutVeg":        rep.Summary.PlotsWithoutVeg,
			},
			ReportJSON: raw,
		}, nil
	}
}

func (s *ContextService) buildSnapshotBundleExporter() cloudsyncpkg.SnapshotBundleExporterFunc {
	return func(ctx context.Context, sqlitePath, projectName, format, destinationPath string) (string, string, error) {
		core := unwrapContextService(s)
		if core == nil || core.Projects == nil {
			return "", "", errors.New("project context is unavailable")
		}
		sel := vprocorepkg.DesktopSelection{
			Project:     projectName,
			ProjectPath: sqlitePath,
			SU:          "None",
			Hierarchy:   "None",
		}
		ephSqlite, err := vprocorepkg.NewSQLiteContext(ctx, sel, core.Projects.SupportPaths)
		if err != nil {
			return "", "", err
		}
		defer ephSqlite.Close()
		ephID, err := vprocorepkg.NewContextIdentity()
		if err != nil {
			return "", "", err
		}
		ephProjects := &vprocorepkg.ProjectService{
			Root:         core.Projects.Root,
			Config:       core.Projects.Config,
			Active:       projectName,
			ActiveSU:     "None",
			Sqlite:       ephSqlite,
			ContextID:    ephID,
			Preferences:  core.Projects.Preferences,
			SupportPaths: core.Projects.SupportPaths,
		}
		ephPlots := &vprocorepkg.PlotService{Projects: ephProjects, CurrentUser: "Custodian"}
		ephCtx, err := vprocorepkg.NewContextService(ephProjects, ephPlots)
		if err != nil {
			return "", "", err
		}
		switch format {
		case "rds":
			res, rErr := interchangepkg.ExportProjectRDS(ephCtx, ctx, ephID, interchangepkg.RDSExportRequest{
				DestinationPath: destinationPath,
			})
			if rErr != nil {
				return "", "", rErr
			}
			return res.Path, res.SHA256, nil
		case "gpkg":
			res, gErr := interchangepkg.ExportGeoPackage(ephCtx, ctx, ephID, interchangepkg.GeoPackageExportRequest{
				DestinationPath:        destinationPath,
				CRS:                    "EPSG:3005",
				IncludeAttributeTables: true,
			})
			if gErr != nil {
				return "", "", gErr
			}
			return res.Path, res.SHA256, nil
		default:
			return "", "", errors.New("unsupported snapshot export format")
		}
	}
}

func (s *ContextService) GetCloudSyncConfigStatus(ctx context.Context) (cloudsyncpkg.CloudConfigStatus, error) {
	if err := ctx.Err(); err != nil {
		return cloudsyncpkg.CloudConfigStatus{}, err
	}
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.CloudConfigStatus{}, err
	}
	return mgr.GetConfigStatus()
}

func (s *ContextService) ConfigureCloudSyncSession(ctx context.Context, req cloudsyncpkg.SessionConfigRequest) (cloudsyncpkg.CloudConfigStatus, error) {
	if err := ctx.Err(); err != nil {
		return cloudsyncpkg.CloudConfigStatus{}, err
	}
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.CloudConfigStatus{}, err
	}
	return mgr.ConfigureSession(req)
}

func (s *ContextService) TestCloudConnection(ctx context.Context) (cloudsyncpkg.CloudConnectionReport, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.CloudConnectionReport{}, err
	}
	return mgr.TestCloudConnection(ctx)
}

func (s *ContextService) BootstrapCloudSchemas(ctx context.Context) (cloudsyncpkg.SchemaBootstrapResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.SchemaBootstrapResult{}, err
	}
	return mgr.BootstrapSchemas(ctx)
}

func (s *ContextService) PublishStandardsToCloud(ctx context.Context, contextID string, req cloudsyncpkg.PublishStandardsRequest) (cloudsyncpkg.PublishStandardsResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.PublishStandardsResult{}, err
	}
	return mgr.PublishStandardsToCloud(ctx, unwrapContextService(s), contextID, req)
}

func (s *ContextService) SeedBECMasterBaseline(ctx context.Context, req cloudsyncpkg.SeedBaselineRequest) (cloudsyncpkg.SeedBaselineResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.SeedBaselineResult{}, err
	}
	return mgr.SeedBECMasterBaseline(ctx, req)
}

func (s *ContextService) PullCloudStandards(ctx context.Context, contextID string) (cloudsyncpkg.PullStandardsResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.PullStandardsResult{}, err
	}
	return mgr.PullCloudStandards(ctx, unwrapContextService(s), contextID)
}

func (s *ContextService) PreviewBECMasterSubset(ctx context.Context, filter cloudsyncpkg.SubsetFilter) (cloudsyncpkg.SubsetPreview, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.SubsetPreview{}, err
	}
	return mgr.PreviewBECMasterSubset(ctx, filter)
}

func (s *ContextService) PullBECMasterSubset(ctx context.Context, contextID string, req cloudsyncpkg.PullSubsetRequest) (cloudsyncpkg.PullSubsetResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.PullSubsetResult{}, err
	}
	return mgr.PullBECMasterSubset(ctx, unwrapContextService(s), contextID, req)
}

func (s *ContextService) PreviewStagingSubmission(ctx context.Context, contextID string, useActiveSU bool) (cloudsyncpkg.StagingPreflightPreview, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.StagingPreflightPreview{}, err
	}
	return mgr.PreviewStagingSubmission(ctx, unwrapContextService(s), contextID, useActiveSU, buildCloudComplianceValidator())
}

func (s *ContextService) SubmitProjectToStaging(ctx context.Context, contextID string, req cloudsyncpkg.SubmitStagingRequest) (cloudsyncpkg.SubmitStagingResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.SubmitStagingResult{}, err
	}
	return mgr.SubmitProjectToStaging(ctx, unwrapContextService(s), contextID, req, buildCloudComplianceValidator())
}

func (s *ContextService) ListStagingSubmissions(ctx context.Context, filter cloudsyncpkg.ListSubmissionsFilter) ([]cloudsyncpkg.StagingSubmissionSummary, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return nil, err
	}
	return mgr.ListStagingSubmissions(ctx, filter)
}

func (s *ContextService) GetStagingSubmissionDetail(ctx context.Context, submissionID string) (cloudsyncpkg.StagingSubmissionDetail, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.StagingSubmissionDetail{}, err
	}
	return mgr.GetStagingSubmissionDetail(ctx, submissionID)
}

func (s *ContextService) PreviewStagingToMasterMerge(ctx context.Context, req cloudsyncpkg.StagingMergePreviewRequest) (cloudsyncpkg.StagingMergePreview, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.StagingMergePreview{}, err
	}
	return mgr.PreviewStagingToMasterMerge(ctx, req)
}

func (s *ContextService) ExecuteStagingToMasterMerge(ctx context.Context, req cloudsyncpkg.StagingMergeExecuteRequest) (cloudsyncpkg.StagingMergeResult, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.StagingMergeResult{}, err
	}
	return mgr.ExecuteStagingToMasterMerge(ctx, req)
}

func (s *ContextService) RejectStagingSubmission(ctx context.Context, req cloudsyncpkg.RejectSubmissionRequest) (cloudsyncpkg.StagingSubmissionSummary, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.StagingSubmissionSummary{}, err
	}
	return mgr.RejectStagingSubmission(ctx, req)
}

func (s *ContextService) CreateBECMasterSnapshot(ctx context.Context, contextID string, req cloudsyncpkg.CreateSnapshotRequest) (cloudsyncpkg.SnapshotRecord, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.SnapshotRecord{}, err
	}
	return mgr.CreateBECMasterSnapshot(ctx, unwrapContextService(s), contextID, req, s.buildSnapshotBundleExporter())
}

func (s *ContextService) ListBECMasterSnapshots(ctx context.Context) ([]cloudsyncpkg.SnapshotRecord, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return nil, err
	}
	return mgr.ListBECMasterSnapshots(ctx)
}

func (s *ContextService) ListBECMasterDownloadLog(ctx context.Context, limit int) ([]cloudsyncpkg.DownloadLogEntry, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return nil, err
	}
	return mgr.ListBECMasterDownloadLog(ctx, limit)
}

func (s *ContextService) VerifyBECMasterAuditChain(ctx context.Context, limit int) (cloudsyncpkg.AuditChainVerification, error) {
	mgr, err := s.cloudManager()
	if err != nil {
		return cloudsyncpkg.AuditChainVerification{}, err
	}
	return mgr.VerifyBECMasterAuditChain(ctx, limit)
}
