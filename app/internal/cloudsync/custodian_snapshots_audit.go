package cloudsync

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// RejectStagingSubmission marks a pending staging submission as rejected with reviewer notes.
func (m *Manager) RejectStagingSubmission(ctx context.Context, req RejectSubmissionRequest) (StagingSubmissionSummary, error) {
	subID := strings.TrimSpace(req.SubmissionID)
	if _, err := uuid.Parse(subID); err != nil {
		return StagingSubmissionSummary{}, errors.New("submissionId must be a valid UUID")
	}
	notes := strings.TrimSpace(req.ReviewerNotes)
	if notes == "" {
		return StagingSubmissionSummary{}, errors.New("reviewerNotes are required when rejecting a staging submission")
	}

	pool, creds, err := m.AcquirePool(ctx, RoleModeCustodian)
	if err != nil {
		return StagingSubmissionSummary{}, err
	}
	actor := strings.TrimSpace(req.Actor)
	nowUTC := time.Now().UTC()
	tag, err := pool.Exec(ctx, `
		UPDATE staging.submissions
		SET status = 'rejected',
		    reviewer_notes = $2,
		    reviewed_by = COALESCE(NULLIF($3, ''), current_user),
		    reviewed_at = $4
		WHERE submission_id = $1 AND status = 'pending'
	`, subID, notes, actor, nowUTC)
	if err != nil {
		return StagingSubmissionSummary{}, wrapRedactedError("reject staging submission", err, creds)
	}
	if tag.RowsAffected() == 0 {
		return StagingSubmissionSummary{}, fmt.Errorf("staging submission %s is not in 'pending' status or does not exist", subID)
	}

	list, err := m.ListStagingSubmissions(ctx, ListSubmissionsFilter{Limit: 200})
	if err == nil {
		for _, item := range list {
			if item.SubmissionID == subID {
				return item, nil
			}
		}
	}
	return StagingSubmissionSummary{
		SubmissionID:  subID,
		Status:        "rejected",
		ReviewerNotes: notes,
		ReviewedAt:    nowUTC.Format(time.RFC3339),
	}, nil
}

// CreateBECMasterSnapshot cuts a named read-only snapshot record in becmaster.snapshots (Schedule A 1.iii)
// and optionally exports a local .db / .rds / .gpkg snapshot bundle.
func (m *Manager) CreateBECMasterSnapshot(
	ctx context.Context,
	s *vprocore.ContextService,
	contextID string,
	req CreateSnapshotRequest,
	bundleExporter SnapshotBundleExporterFunc,
) (SnapshotRecord, error) {
	tag := strings.TrimSpace(req.SnapshotTag)
	if tag == "" || len(tag) > 80 {
		return SnapshotRecord{}, errors.New("snapshotTag must be 1..80 characters")
	}
	for _, r := range tag {
		if !((r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' || r == '.') {
			return SnapshotRecord{}, errors.New("snapshotTag may contain only ASCII letters, digits, '_', '-', or '.'")
		}
	}
	format := strings.ToLower(strings.TrimSpace(req.ExportFormat))
	if format != "" && format != "sqlite" && format != "rds" && format != "gpkg" {
		return SnapshotRecord{}, fmt.Errorf("unsupported snapshot exportFormat %q (expected sqlite, rds, or gpkg)", format)
	}

	pool, creds, err := m.AcquirePool(ctx, RoleModeCustodian)
	if err != nil {
		return SnapshotRecord{}, err
	}

	var plotCount int
	var vegCount int64
	var tailHash string
	if err := pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM becmaster.env),
			(SELECT COUNT(*) FROM becmaster.veg),
			COALESCE((SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1), $1)
	`, GenesisAuditHash).Scan(&plotCount, &vegCount, &tailHash); err != nil {
		return SnapshotRecord{}, wrapRedactedError("read BECMaster snapshot counts", err, creds)
	}

	becVer, taxVer := readBundledStandardsVersions()
	_ = pool.QueryRow(ctx, `
		SELECT bec_version, taxonomy_version FROM standards.library_releases
		WHERE is_current = TRUE ORDER BY published_at DESC LIMIT 1
	`).Scan(&becVer, &taxVer)

	var exportedPath, manifestSHA string
	var maskedSensitive int
	if format != "" {
		if s == nil || contextID == "" {
			return SnapshotRecord{}, errors.New("active context is required when exporting a local snapshot file")
		}
		destPath := strings.TrimSpace(req.DestinationPath)
		if destPath == "" {
			return SnapshotRecord{}, errors.New("destinationPath is required when exportFormat is specified")
		}
		filter := SubsetFilter{AllowFullCheckout: true}
		if z := strings.TrimSpace(req.ZoneFilter); z != "" {
			filter = SubsetFilter{Zones: []string{z}}
		}
		stageSQLitePath := destPath
		var cleanupTemp func()
		if format != "sqlite" {
			tmpDir, tErr := os.MkdirTemp("", "vpro-snap-bundle-*")
			if tErr != nil {
				return SnapshotRecord{}, tErr
			}
			cleanupTemp = func() { _ = os.RemoveAll(tmpDir) }
			stageSQLitePath = filepath.Join(tmpDir, "SnapStage.db")
		}
		if cleanupTemp != nil {
			defer cleanupTemp()
		}

		subRes, pErr := m.PullBECMasterSubset(ctx, s, contextID, PullSubsetRequest{
			Filter:                   filter,
			TargetProject:            "SnapExport",
			DestinationPath:          stageSQLitePath,
			ActivateOnSuccess:        false,
			MaskSensitiveCoordinates: !req.IncludeSensitiveCoordinates,
		})
		if pErr != nil {
			return SnapshotRecord{}, pErr
		}
		maskedSensitive = subRes.MaskedSensitivePlots
		if format == "sqlite" {
			exportedPath = subRes.DestinationPath
			manifestSHA = subRes.DestinationSHA
		} else {
			if bundleExporter == nil {
				return SnapshotRecord{}, fmt.Errorf("snapshot exporter for format %q is not wired", format)
			}
			expP, expSHA, bErr := bundleExporter(ctx, subRes.DestinationPath, "SnapExport", format, destPath)
			if bErr != nil {
				return SnapshotRecord{}, bErr
			}
			exportedPath = expP
			manifestSHA = expSHA
		}
	}

	if manifestSHA == "" {
		sum := sha256.Sum256([]byte(fmt.Sprintf("%s|%d|%d|%s|%s|%s", tag, plotCount, vegCount, becVer, taxVer, tailHash)))
		manifestSHA = hex.EncodeToString(sum[:])
	}

	nowUTC := time.Now().UTC()
	var notesPtr *string
	if n := strings.TrimSpace(req.Notes); n != "" {
		notesPtr = &n
	}
	var createdBy string
	if err := pool.QueryRow(ctx, `
		INSERT INTO becmaster.snapshots (
			snapshot_tag, created_at, created_by, plot_count, veg_count,
			bec_version, taxonomy_version, manifest_sha256, notes
		) VALUES ($1, $2, current_user, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (snapshot_tag) DO UPDATE SET
			created_at = EXCLUDED.created_at,
			created_by = EXCLUDED.created_by,
			plot_count = EXCLUDED.plot_count,
			veg_count = EXCLUDED.veg_count,
			bec_version = EXCLUDED.bec_version,
			taxonomy_version = EXCLUDED.taxonomy_version,
			manifest_sha256 = EXCLUDED.manifest_sha256,
			notes = EXCLUDED.notes
		RETURNING created_by
	`, tag, nowUTC, plotCount, vegCount, becVer, taxVer, manifestSHA, notesPtr).Scan(&createdBy); err != nil {
		return SnapshotRecord{}, wrapRedactedError("insert becmaster.snapshots", err, creds)
	}

	return SnapshotRecord{
		SnapshotTag:          tag,
		CreatedAt:            nowUTC.Format(time.RFC3339),
		CreatedBy:            createdBy,
		PlotCount:            plotCount,
		VegCount:             vegCount,
		BECVersion:           becVer,
		TaxonomyVersion:      taxVer,
		ManifestSHA256:       manifestSHA,
		Notes:                strings.TrimSpace(req.Notes),
		ExportedPath:         exportedPath,
		MaskedSensitivePlots: maskedSensitive,
	}, nil
}

// ListBECMasterSnapshots lists dated snapshots newest-first.
func (m *Manager) ListBECMasterSnapshots(ctx context.Context) ([]SnapshotRecord, error) {
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return nil, err
	}
	rows, err := pool.Query(ctx, `
		SELECT snapshot_tag, created_at, created_by, plot_count, veg_count,
		       bec_version, taxonomy_version, manifest_sha256, COALESCE(notes, '')
		FROM becmaster.snapshots
		ORDER BY created_at DESC
		LIMIT 100
	`)
	if err != nil {
		return nil, wrapRedactedError("list becmaster.snapshots", err, creds)
	}
	defer rows.Close()

	out := []SnapshotRecord{}
	for rows.Next() {
		var r SnapshotRecord
		var ts time.Time
		if err := rows.Scan(&r.SnapshotTag, &ts, &r.CreatedBy, &r.PlotCount, &r.VegCount, &r.BECVersion, &r.TaxonomyVersion, &r.ManifestSHA256, &r.Notes); err != nil {
			return nil, wrapRedactedError("scan becmaster.snapshots row", err, creds)
		}
		r.CreatedAt = ts.UTC().Format(time.RFC3339)
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, wrapRedactedError("iterate becmaster.snapshots", err, creds)
	}
	return out, nil
}

// ListBECMasterDownloadLog lists download_log audit records (Schedule A 1.v).
func (m *Manager) ListBECMasterDownloadLog(ctx context.Context, limit int) ([]DownloadLogEntry, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	pool, creds, err := m.AcquirePool(ctx, RoleModeCustodian)
	if err != nil {
		return nil, err
	}
	rows, err := pool.Query(ctx, `
		SELECT id, downloaded_at, actor, role_tier, filter_json::text, format, plot_count
		FROM becmaster.download_log
		ORDER BY id DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, wrapRedactedError("list becmaster.download_log", err, creds)
	}
	defer rows.Close()

	out := []DownloadLogEntry{}
	for rows.Next() {
		var e DownloadLogEntry
		var ts time.Time
		var rawFilter string
		if err := rows.Scan(&e.ID, &ts, &e.Actor, &e.RoleTier, &rawFilter, &e.Format, &e.PlotCount); err != nil {
			return nil, wrapRedactedError("scan becmaster.download_log row", err, creds)
		}
		e.DownloadedAt = ts.UTC().Format(time.RFC3339)
		e.FilterJSON = json.RawMessage(rawFilter)
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, wrapRedactedError("iterate becmaster.download_log", err, creds)
	}
	return out, nil
}

// VerifyBECMasterAuditChain verifies the SHA-256 hash chain over the most recent limit rows in becmaster.audit,
// anchoring the window's first row against either GenesisAuditHash (at the start of the ledger) or its immediate predecessor.
func (m *Manager) VerifyBECMasterAuditChain(ctx context.Context, limit int) (AuditChainVerification, error) {
	if limit <= 0 {
		limit = 1000
	}
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return AuditChainVerification{}, err
	}
	query := fmt.Sprintf(`
		SELECT * FROM (
			SELECT audit_seq, %s, COALESCE(merge_tx_id::text, ''), prev_hash, row_hash
			FROM becmaster.audit
			ORDER BY audit_seq DESC
			LIMIT $1
		) sub
		ORDER BY audit_seq ASC
	`, quotedColumnCSV(VP08AuditColumns))

	rows, err := pool.Query(ctx, query, limit)
	if err != nil {
		return AuditChainVerification{}, wrapRedactedError("verify becmaster.audit hash chain", err, creds)
	}
	defer rows.Close()

	var count int64
	var firstSeq int64
	var firstPrevHash string
	expectedPrev := ""
	tailHash := GenesisAuditHash
	for rows.Next() {
		vals, vErr := rows.Values()
		if vErr != nil {
			return AuditChainVerification{}, wrapRedactedError("scan becmaster.audit row", vErr, creds)
		}
		seq, _ := vals[0].(int64)
		vp08Row := make([]any, len(VP08AuditColumns))
		for i, col := range VP08AuditColumns {
			cc := pgValueToCloudCell(col, vals[1+i])
			vp08Row[i] = cc.pgParam(col)
		}
		mergeTx, _ := vals[12].(string)
		prevHash, _ := vals[13].(string)
		rowHash, _ := vals[14].(string)

		if count == 0 {
			firstSeq = seq
			firstPrevHash = prevHash
		} else if prevHash != expectedPrev {
			return AuditChainVerification{VerifiedRows: count, Valid: false, TailHash: tailHash}, fmt.Errorf("audit hash chain broken at seq=%d: prev_hash=%s != expected=%s", seq, prevHash, expectedPrev)
		}
		computed := ComputeAuditRowHash(prevHash, mergeTx, vp08Row)
		if computed != rowHash {
			return AuditChainVerification{VerifiedRows: count, Valid: false, TailHash: tailHash}, fmt.Errorf("audit row_hash tampered at seq=%d: computed=%s != stored=%s", seq, computed, rowHash)
		}
		expectedPrev = rowHash
		tailHash = rowHash
		count++
	}
	if err := rows.Err(); err != nil {
		return AuditChainVerification{}, wrapRedactedError("iterate becmaster.audit chain", err, creds)
	}
	rows.Close()

	partialWindow := false
	if count > 0 {
		var predHash string
		pErr := pool.QueryRow(ctx, `SELECT row_hash FROM becmaster.audit WHERE audit_seq < $1 ORDER BY audit_seq DESC LIMIT 1`, firstSeq).Scan(&predHash)
		if errors.Is(pErr, pgx.ErrNoRows) {
			// Window starts at the first surviving row in becmaster.audit -> must anchor to GenesisAuditHash!
			if firstPrevHash != GenesisAuditHash {
				return AuditChainVerification{VerifiedRows: count, Valid: false, TailHash: tailHash}, fmt.Errorf("initial audit row seq=%d does not anchor to GenesisAuditHash (deleted prefix detected)", firstSeq)
			}
		} else if pErr != nil {
			return AuditChainVerification{}, wrapRedactedError("verify audit chain predecessor anchor", pErr, creds)
		} else {
			partialWindow = true
			if firstPrevHash != predHash {
				return AuditChainVerification{VerifiedRows: count, Valid: false, PartialWindow: true, TailHash: tailHash}, fmt.Errorf("audit window boundary broken at seq=%d: prev_hash=%s != predecessor=%s", firstSeq, firstPrevHash, predHash)
			}
		}
	}

	return AuditChainVerification{
		VerifiedRows:  count,
		Valid:         true,
		PartialWindow: partialWindow,
		TailHash:      tailHash,
	}, nil
}
