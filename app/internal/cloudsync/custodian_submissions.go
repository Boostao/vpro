package cloudsync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"strings"
	"time"
)

const (
	MergeResolutionKeepTarget   = "keep_target"
	MergeResolutionAcceptSource = "accept_source"
)

var mergeTableSuffixes = []string{"Env", "Admin", "Veg", "Humus", "Mineral", "Other"}

// ListSubmissionsFilter filters staging.submissions rows.
type ListSubmissionsFilter struct {
	Status      string `json:"status,omitempty"`
	SubmittedBy string `json:"submittedBy,omitempty"`
	Limit       int    `json:"limit,omitempty"`
}

func (r *ListSubmissionsFilter) UnmarshalJSON(data []byte) error {
	type plain ListSubmissionsFilter
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// StagingSubmissionSummary represents one queue item in staging.submissions.
type StagingSubmissionSummary struct {
	SubmissionID     string `json:"submissionId"`
	ProjectName      string `json:"projectName"`
	ProjectID        string `json:"projectId,omitempty"`
	SubmittedBy      string `json:"submittedBy"`
	DBRole           string `json:"dbRole"`
	SubmittedAt      string `json:"submittedAt"`
	Status           string `json:"status"`
	PlotCount        int    `json:"plotCount"`
	VegRowCount      int    `json:"vegRowCount"`
	SourceDBSHA256   string `json:"sourceDbSha256"`
	CompliancePassed bool   `json:"compliancePassed"`
	UserSpeciesCount int    `json:"userSpeciesCount"`
	LumpRowCount     int    `json:"lumpRowCount"`
	SURowCount       int    `json:"suRowCount"`
	SubmitterNotes   string `json:"submitterNotes,omitempty"`
	BaseSnapshotTag  string `json:"baseSnapshotTag,omitempty"`
	ReviewerNotes    string `json:"reviewerNotes,omitempty"`
	ReviewedBy       string `json:"reviewedBy,omitempty"`
	ReviewedAt       string `json:"reviewedAt,omitempty"`
	MergedTxID       string `json:"mergedTxId,omitempty"`
}

// ProvisionalSpeciesDiff compares a personal species in user_species_manifest against standards.usys_all_specs.
type ProvisionalSpeciesDiff struct {
	Code               string  `json:"code"`
	ScientificName     *string `json:"scientificName,omitempty"`
	LifeForm           *int    `json:"lifeForm,omitempty"`
	Status             string  `json:"status"` // "new_provisional" | "matches_official" | "matches_synonym"
	OfficialCode       string  `json:"officialCode,omitempty"`
	OfficialScientific string  `json:"officialScientific,omitempty"`
}

// StagingSubmissionDetail provides full custodian review payloads for a submission.
type StagingSubmissionDetail struct {
	Summary                 StagingSubmissionSummary `json:"summary"`
	ComplianceReport        json.RawMessage          `json:"complianceReport"`
	UserSpeciesManifest     CloudUserSpeciesManifest `json:"userSpeciesManifest"`
	ProvisionalSpeciesDiffs []ProvisionalSpeciesDiff `json:"provisionalSpeciesDiffs"`
	LumpRows                []StagingLumpRow         `json:"lumpRows"`
	SURows                  []StagingSURow           `json:"suRows"`
}

// CloudMergeConflictItem mirrors ThreeWayMergePreview's MergeConflictItem with custodian protection metadata.
type CloudMergeConflictItem struct {
	ConflictID         string  `json:"conflictId"`
	PlotNumber         string  `json:"plotNumber"`
	Table              string  `json:"table"`
	Key                string  `json:"key"`
	Field              string  `json:"field"`
	BaseVal            *string `json:"baseVal,omitempty"`
	SourceVal          *string `json:"sourceVal"`
	TargetVal          *string `json:"targetVal"`
	Kind               string  `json:"kind"`              // "FastForward" | "Conflict" | "TargetModifiedOnly"
	DefaultResolution  string  `json:"defaultResolution"` // "accept_source" | "keep_target"
	CustodianProtected bool    `json:"custodianProtected"`
}

// CloudMergePlotPreview summarizes per-plot merge status and field/child conflicts.
type CloudMergePlotPreview struct {
	PlotNumber string                   `json:"plotNumber"`
	Category   string                   `json:"category"` // "Added" | "Identical" | "FastForward" | "Conflict" | "TargetOnly"
	Items      []CloudMergeConflictItem `json:"items"`
}

// StagingMergePreviewRequest configures 3-way diffing of staging.<submission> vs becmaster.
type StagingMergePreviewRequest struct {
	SubmissionID string `json:"submissionId"`
	BaseDBPath   string `json:"baseDbPath,omitempty"`
	BaseProject  string `json:"baseProject,omitempty"`
}

func (r *StagingMergePreviewRequest) UnmarshalJSON(data []byte) error {
	type plain StagingMergePreviewRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// StagingMergePreview is ThreeWayMergePreview-compatible for Custodian staging -> becmaster review.
type StagingMergePreview struct {
	SubmissionID            string                   `json:"submissionId"`
	SourceProject           string                   `json:"sourceProject"`
	TargetProject           string                   `json:"targetProject"`
	BaseDBPath              string                   `json:"baseDbPath,omitempty"`
	BaseProject             string                   `json:"baseProject,omitempty"`
	PreviewDigest           string                   `json:"previewDigest"`
	AddedCount              int                      `json:"addedCount"`
	IdenticalCount          int                      `json:"identicalCount"`
	FastForwardCount        int                      `json:"fastForwardCount"`
	ConflictCount           int                      `json:"conflictCount"`
	TargetOnlyCount         int                      `json:"targetOnlyCount"`
	ElapsedMs               int64                    `json:"elapsedMs"`
	Plots                   []CloudMergePlotPreview  `json:"plots"`
	Conflicts               []CloudMergeConflictItem `json:"conflicts"`
	CustodianProtectedDiffs []CloudMergeConflictItem `json:"custodianProtectedDiffs"`
}

// StagingMergeExecuteRequest commits selective plot/field resolutions into becmaster atomically.
type StagingMergeExecuteRequest struct {
	SubmissionID              string            `json:"submissionId"`
	BaseDBPath                string            `json:"baseDbPath,omitempty"`
	BaseProject               string            `json:"baseProject,omitempty"`
	ExpectedPreviewDigest     string            `json:"expectedPreviewDigest"`
	DefaultConflictResolution string            `json:"defaultConflictResolution,omitempty"`
	PlotResolutions           map[string]string `json:"plotResolutions,omitempty"`
	FieldResolutions          map[string]string `json:"fieldResolutions,omitempty"`
	ReviewerNotes             string            `json:"reviewerNotes,omitempty"`
	Actor                     string            `json:"actor,omitempty"`
}

func (r *StagingMergeExecuteRequest) UnmarshalJSON(data []byte) error {
	type plain StagingMergeExecuteRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// StagingMergeResult summarizes atomic Custodian merge provenance and child ID allocations.
type StagingMergeResult struct {
	MergeTxID          string  `json:"mergeTxId"`
	SubmissionID       string  `json:"submissionId"`
	SourceProject      string  `json:"sourceProject"`
	AddedPlots         int     `json:"addedPlots"`
	UpdatedPlots       int     `json:"updatedPlots"`
	SkippedPlots       int     `json:"skippedPlots"`
	AllocatedChildIDs  []int64 `json:"allocatedChildIds"`
	ReservedDeletedIDs []int64 `json:"reservedDeletedIds"`
	AuditRowsWritten   int     `json:"auditRowsWritten"`
	TailAuditHash      string  `json:"tailAuditHash"`
	MergedAt           string  `json:"mergedAt"`
}

// RejectSubmissionRequest marks a pending staging submission as rejected with reviewer notes.
type RejectSubmissionRequest struct {
	SubmissionID  string `json:"submissionId"`
	ReviewerNotes string `json:"reviewerNotes"`
	Actor         string `json:"actor,omitempty"`
}

func (r *RejectSubmissionRequest) UnmarshalJSON(data []byte) error {
	type plain RejectSubmissionRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// CreateSnapshotRequest cuts a dated BECMaster snapshot record and optional local export bundle.
type CreateSnapshotRequest struct {
	SnapshotTag                 string `json:"snapshotTag"`
	Notes                       string `json:"notes,omitempty"`
	ExportFormat                string `json:"exportFormat,omitempty"` // "" | "sqlite" | "rds" | "gpkg"
	DestinationPath             string `json:"destinationPath,omitempty"`
	ZoneFilter                  string `json:"zoneFilter,omitempty"`
	IncludeSensitiveCoordinates bool   `json:"includeSensitiveCoordinates,omitempty"`
}

func (r *CreateSnapshotRequest) UnmarshalJSON(data []byte) error {
	type plain CreateSnapshotRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// SnapshotBundleExporterFunc allows Layer 3 (main) to export optional .rds / .gpkg snapshot bundles
// from a staged VP08 SQLite file without Layer-2 sibling imports.
type SnapshotBundleExporterFunc func(ctx context.Context, sqlitePath, projectName, format, destinationPath string) (exportedPath string, sha256Hex string, err error)

// SnapshotRecord represents a row in becmaster.snapshots (Schedule A 1.iii).
type SnapshotRecord struct {
	SnapshotTag          string `json:"snapshotTag"`
	CreatedAt            string `json:"createdAt"`
	CreatedBy            string `json:"createdBy"`
	PlotCount            int    `json:"plotCount"`
	VegCount             int64  `json:"vegCount"`
	BECVersion           string `json:"becVersion"`
	TaxonomyVersion      string `json:"taxonomyVersion"`
	ManifestSHA256       string `json:"manifestSha256"`
	Notes                string `json:"notes,omitempty"`
	ExportedPath         string `json:"exportedPath,omitempty"`
	MaskedSensitivePlots int    `json:"maskedSensitivePlots,omitempty"`
}

// DownloadLogEntry represents a row in becmaster.download_log (Schedule A 1.v).
type DownloadLogEntry struct {
	ID           int64           `json:"id"`
	DownloadedAt string          `json:"downloadedAt"`
	Actor        string          `json:"actor"`
	RoleTier     string          `json:"roleTier"`
	FilterJSON   json.RawMessage `json:"filterJson"`
	Format       string          `json:"format"`
	PlotCount    int             `json:"plotCount"`
}

// AuditChainVerification reports cryptographic verification of becmaster.audit hash chaining.
type AuditChainVerification struct {
	VerifiedRows  int64  `json:"verifiedRows"`
	TotalRows     int64  `json:"totalRows"`
	Valid         bool   `json:"valid"`
	PartialWindow bool   `json:"partialWindow"`
	TailHash      string `json:"tailHash"`
}

type pgQueryer interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	SendBatch(ctx context.Context, b *pgx.Batch) pgx.BatchResults
}

// ListStagingSubmissions lists staging queue entries ordered newest-first.
func (m *Manager) ListStagingSubmissions(ctx context.Context, filter ListSubmissionsFilter) ([]StagingSubmissionSummary, error) {
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return nil, err
	}
	limit := filter.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	var clauses []string
	var args []any
	if st := strings.TrimSpace(filter.Status); st != "" {
		args = append(args, st)
		clauses = append(clauses, fmt.Sprintf("status = $%d", len(args)))
	}
	if sb := strings.TrimSpace(filter.SubmittedBy); sb != "" {
		args = append(args, sb)
		clauses = append(clauses, fmt.Sprintf("submitted_by = $%d", len(args)))
	}
	whereSQL := ""
	if len(clauses) > 0 {
		whereSQL = "WHERE " + strings.Join(clauses, " AND ")
	}
	args = append(args, limit)
	query := fmt.Sprintf(`
		SELECT
			submission_id::text,
			project_name,
			COALESCE(project_id, ''),
			submitted_by,
			db_role,
			submitted_at,
			status,
			plot_count,
			veg_row_count,
			source_db_sha256,
			compliance_passed,
			COALESCE((user_species_manifest->>'rowCount')::int, 0),
			COALESCE(jsonb_array_length(lump_rows), 0),
			COALESCE(jsonb_array_length(su_rows), 0),
			COALESCE(submitter_notes, ''),
			COALESCE(base_snapshot_tag, ''),
			COALESCE(reviewer_notes, ''),
			COALESCE(reviewed_by, ''),
			reviewed_at,
			COALESCE(merged_tx_id::text, '')
		FROM staging.submissions
		%s
		ORDER BY submitted_at DESC
		LIMIT $%d
	`, whereSQL, len(args))

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, wrapRedactedError("list staging submissions", err, creds)
	}
	defer rows.Close()

	out := []StagingSubmissionSummary{}
	for rows.Next() {
		var item StagingSubmissionSummary
		var subAt time.Time
		var revAt *time.Time
		if err := rows.Scan(
			&item.SubmissionID,
			&item.ProjectName,
			&item.ProjectID,
			&item.SubmittedBy,
			&item.DBRole,
			&subAt,
			&item.Status,
			&item.PlotCount,
			&item.VegRowCount,
			&item.SourceDBSHA256,
			&item.CompliancePassed,
			&item.UserSpeciesCount,
			&item.LumpRowCount,
			&item.SURowCount,
			&item.SubmitterNotes,
			&item.BaseSnapshotTag,
			&item.ReviewerNotes,
			&item.ReviewedBy,
			&revAt,
			&item.MergedTxID,
		); err != nil {
			return nil, wrapRedactedError("scan staging submission row", err, creds)
		}
		item.SubmittedAt = subAt.UTC().Format(time.RFC3339)
		if revAt != nil {
			item.ReviewedAt = revAt.UTC().Format(time.RFC3339)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, wrapRedactedError("iterate staging submissions", err, creds)
	}
	return out, nil
}

// GetStagingSubmissionDetail returns full compliance report and provisional species diffs for a submission.
func (m *Manager) GetStagingSubmissionDetail(ctx context.Context, submissionID string) (StagingSubmissionDetail, error) {
	if _, err := uuid.Parse(strings.TrimSpace(submissionID)); err != nil {
		return StagingSubmissionDetail{}, errors.New("submissionId must be a valid UUID")
	}
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return StagingSubmissionDetail{}, err
	}

	var detail StagingSubmissionDetail
	var subAt time.Time
	var revAt *time.Time
	var compRaw, manifestRaw, lumpRaw, suRaw []byte
	err = pool.QueryRow(ctx, `
		SELECT
			submission_id::text,
			project_name,
			COALESCE(project_id, ''),
			submitted_by,
			db_role,
			submitted_at,
			status,
			plot_count,
			veg_row_count,
			source_db_sha256,
			compliance_passed,
			COALESCE(submitter_notes, ''),
			COALESCE(base_snapshot_tag, ''),
			COALESCE(reviewer_notes, ''),
			COALESCE(reviewed_by, ''),
			reviewed_at,
			COALESCE(merged_tx_id::text, ''),
			compliance_report::text,
			user_species_manifest::text,
			lump_rows::text,
			su_rows::text
		FROM staging.submissions
		WHERE submission_id = $1
	`, strings.TrimSpace(submissionID)).Scan(
		&detail.Summary.SubmissionID,
		&detail.Summary.ProjectName,
		&detail.Summary.ProjectID,
		&detail.Summary.SubmittedBy,
		&detail.Summary.DBRole,
		&subAt,
		&detail.Summary.Status,
		&detail.Summary.PlotCount,
		&detail.Summary.VegRowCount,
		&detail.Summary.SourceDBSHA256,
		&detail.Summary.CompliancePassed,
		&detail.Summary.SubmitterNotes,
		&detail.Summary.BaseSnapshotTag,
		&detail.Summary.ReviewerNotes,
		&detail.Summary.ReviewedBy,
		&revAt,
		&detail.Summary.MergedTxID,
		&compRaw,
		&manifestRaw,
		&lumpRaw,
		&suRaw,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return StagingSubmissionDetail{}, fmt.Errorf("staging submission %s not found", submissionID)
		}
		return StagingSubmissionDetail{}, wrapRedactedError("get staging submission detail", err, creds)
	}
	detail.Summary.SubmittedAt = subAt.UTC().Format(time.RFC3339)
	if revAt != nil {
		detail.Summary.ReviewedAt = revAt.UTC().Format(time.RFC3339)
	}
	detail.ComplianceReport = json.RawMessage(compRaw)
	_ = json.Unmarshal(manifestRaw, &detail.UserSpeciesManifest)
	if detail.UserSpeciesManifest.Species == nil {
		detail.UserSpeciesManifest.Species = []CloudUserSpeciesRecord{}
	}
	_ = json.Unmarshal(lumpRaw, &detail.LumpRows)
	if detail.LumpRows == nil {
		detail.LumpRows = []StagingLumpRow{}
	}
	_ = json.Unmarshal(suRaw, &detail.SURows)
	if detail.SURows == nil {
		detail.SURows = []StagingSURow{}
	}
	detail.Summary.UserSpeciesCount = len(detail.UserSpeciesManifest.Species)
	detail.Summary.LumpRowCount = len(detail.LumpRows)
	detail.Summary.SURowCount = len(detail.SURows)

	detail.ProvisionalSpeciesDiffs = []ProvisionalSpeciesDiff{}
	for _, sp := range detail.UserSpeciesManifest.Species {
		diff := ProvisionalSpeciesDiff{
			Code:           sp.Code,
			ScientificName: sp.ScientificName,
			LifeForm:       sp.LifeForm,
			Status:         "new_provisional",
		}
		var offCode, offSci string
		if qErr := pool.QueryRow(ctx, `SELECT COALESCE("Code",''), COALESCE("ScientificName",'') FROM standards.usys_all_specs WHERE UPPER("Code") = UPPER($1) LIMIT 1`, sp.Code).Scan(&offCode, &offSci); qErr == nil && offCode != "" {
			diff.Status = "matches_official"
			diff.OfficialCode = offCode
			diff.OfficialScientific = offSci
		} else if qErr := pool.QueryRow(ctx, `SELECT COALESCE("Code",''), COALESCE("ScientificName",'') FROM standards.usys_all_specs WHERE UPPER("OldCode") = UPPER($1) LIMIT 1`, sp.Code).Scan(&offCode, &offSci); qErr == nil && offCode != "" {
			diff.Status = "matches_synonym"
			diff.OfficialCode = offCode
			diff.OfficialScientific = offSci
		}
		detail.ProvisionalSpeciesDiffs = append(detail.ProvisionalSpeciesDiffs, diff)
	}

	return detail, nil
}
