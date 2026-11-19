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

const defaultAuditVerifyBatchSize = 50000

type auditRowScanner interface {
	Next() bool
	Values() ([]any, error)
	Err() error
	Close()
}

type auditChainStore interface {
	CountAuditRows(ctx context.Context) (int64, error)
	PredecessorBeforeOffset(ctx context.Context, offset int) (seq int64, rowHash string, err error)
	QueryAuditBatch(ctx context.Context, hasAfterSeq bool, afterSeq int64, batchLimit int) (auditRowScanner, error)
}

type pgAuditChainStore struct {
	tx pgx.Tx
}

func (s pgAuditChainStore) CountAuditRows(ctx context.Context) (int64, error) {
	var total int64
	err := s.tx.QueryRow(ctx, `SELECT COUNT(*) FROM becmaster.audit`).Scan(&total)
	return total, err
}

func (s pgAuditChainStore) PredecessorBeforeOffset(ctx context.Context, offset int) (int64, string, error) {
	var seq int64
	var rowHash string
	err := s.tx.QueryRow(ctx, `SELECT audit_seq, row_hash FROM becmaster.audit ORDER BY audit_seq DESC OFFSET $1 LIMIT 1`, offset).Scan(&seq, &rowHash)
	return seq, rowHash, err
}

func buildAuditBatchSelectSQL(hasAfterSeq bool) string {
	cols := quotedColumnCSV(VP08AuditColumns)
	if hasAfterSeq {
		return fmt.Sprintf(`
			SELECT audit_seq, %s, COALESCE(merge_tx_id::text, ''), prev_hash, row_hash
			FROM becmaster.audit
			WHERE audit_seq > $1
			ORDER BY audit_seq ASC
			LIMIT $2
		`, cols)
	}
	return fmt.Sprintf(`
		SELECT audit_seq, %s, COALESCE(merge_tx_id::text, ''), prev_hash, row_hash
		FROM becmaster.audit
		ORDER BY audit_seq ASC
		LIMIT $1
	`, cols)
}

func (s pgAuditChainStore) QueryAuditBatch(ctx context.Context, hasAfterSeq bool, afterSeq int64, batchLimit int) (auditRowScanner, error) {
	query := buildAuditBatchSelectSQL(hasAfterSeq)
	if hasAfterSeq {
		return s.tx.Query(ctx, query, afterSeq, batchLimit)
	}
	return s.tx.Query(ctx, query, batchLimit)
}

func coerceAuditSeq(raw any) (int64, error) {
	switch v := raw.(type) {
	case int64:
		return v, nil
	case int32:
		return int64(v), nil
	case int16:
		return int64(v), nil
	case int:
		return int64(v), nil
	default:
		return 0, fmt.Errorf("unexpected audit_seq type %T", raw)
	}
}

func coerceAuditString(raw any) string {
	switch v := raw.(type) {
	case nil:
		return ""
	case string:
		return v
	case []byte:
		return string(v)
	default:
		return fmt.Sprint(v)
	}
}

// VerifyBECMasterAuditChain verifies the SHA-256 hash chain in becmaster.audit.
// When limit == 0, every row from genesis (GenesisAuditHash) through head is streamed in bounded batches.
// When limit > 0, the latest limit rows are verified and anchored against their immediate predecessor
// (or GenesisAuditHash when limit >= totalRows).
func (m *Manager) VerifyBECMasterAuditChain(ctx context.Context, limit int) (AuditChainVerification, error) {
	if limit < 0 {
		return AuditChainVerification{}, errors.New("audit limit must be >= 0 (0 = full chain)")
	}
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return AuditChainVerification{}, err
	}
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.RepeatableRead,
		AccessMode: pgx.ReadOnly,
	})
	if err != nil {
		return AuditChainVerification{}, wrapRedactedError("begin read-only audit verification snapshot", err, creds)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	return verifyAuditChainWithStore(ctx, pgAuditChainStore{tx: tx}, creds, limit, defaultAuditVerifyBatchSize)
}

func verifyAuditChainWithStore(
	ctx context.Context,
	store auditChainStore,
	creds *ResolvedCredentials,
	limit int,
	batchSize int,
) (AuditChainVerification, error) {
	if limit < 0 {
		return AuditChainVerification{}, errors.New("audit limit must be >= 0 (0 = full chain)")
	}
	if batchSize <= 0 {
		batchSize = defaultAuditVerifyBatchSize
	}

	totalRows, err := store.CountAuditRows(ctx)
	if err != nil {
		return AuditChainVerification{}, wrapRedactedError("count becmaster.audit rows", err, creds)
	}
	if totalRows == 0 {
		return AuditChainVerification{
			VerifiedRows:  0,
			TotalRows:     0,
			Valid:         true,
			PartialWindow: false,
			TailHash:      GenesisAuditHash,
		}, nil
	}

	partialWindow := false
	hasAfterSeq := false
	var afterSeq int64
	expectedPrev := GenesisAuditHash

	if limit > 0 && int64(limit) < totalRows {
		predSeq, predHash, pErr := store.PredecessorBeforeOffset(ctx, limit)
		if errors.Is(pErr, pgx.ErrNoRows) {
			partialWindow = false
		} else if pErr != nil {
			return AuditChainVerification{}, wrapRedactedError("verify audit chain predecessor anchor", pErr, creds)
		} else {
			partialWindow = true
			hasAfterSeq = true
			afterSeq = predSeq
			expectedPrev = predHash
		}
	}

	var count int64
	tailHash := GenesisAuditHash
	if partialWindow {
		tailHash = expectedPrev
	}
	vp08Row := make([]any, len(VP08AuditColumns))
	expectedCols := 4 + len(VP08AuditColumns)

	for {
		if err := ctx.Err(); err != nil {
			return AuditChainVerification{}, wrapRedactedError("verify becmaster.audit hash chain", err, creds)
		}
		batchLimit := batchSize
		if partialWindow {
			remaining := int64(limit) - count
			if remaining <= 0 {
				break
			}
			if remaining < int64(batchLimit) {
				batchLimit = int(remaining)
			}
		}

		rows, qErr := store.QueryAuditBatch(ctx, hasAfterSeq, afterSeq, batchLimit)
		if qErr != nil {
			return AuditChainVerification{}, wrapRedactedError("verify becmaster.audit hash chain", qErr, creds)
		}

		var batchCount int
		for rows.Next() {
			vals, vErr := rows.Values()
			if vErr != nil {
				rows.Close()
				return AuditChainVerification{}, wrapRedactedError("scan becmaster.audit row", vErr, creds)
			}
			if len(vals) < expectedCols {
				rows.Close()
				return AuditChainVerification{}, fmt.Errorf("unexpected becmaster.audit column count %d (want %d)", len(vals), expectedCols)
			}
			seq, sErr := coerceAuditSeq(vals[0])
			if sErr != nil {
				rows.Close()
				return AuditChainVerification{}, sErr
			}
			for i, col := range VP08AuditColumns {
				cc := pgValueToCloudCell(col, vals[1+i])
				vp08Row[i] = cc.pgParam(col)
			}
			mergeTx := coerceAuditString(vals[1+len(VP08AuditColumns)])
			prevHash := coerceAuditString(vals[2+len(VP08AuditColumns)])
			rowHash := coerceAuditString(vals[3+len(VP08AuditColumns)])

			if count == 0 {
				computed := ComputeAuditRowHash(prevHash, mergeTx, vp08Row)
				if computed != rowHash {
					rows.Close()
					return AuditChainVerification{
						VerifiedRows:  count,
						TotalRows:     totalRows,
						Valid:         false,
						PartialWindow: partialWindow,
						TailHash:      tailHash,
					}, fmt.Errorf("audit row_hash tampered at seq=%d: computed=%s != stored=%s", seq, computed, rowHash)
				}
				if partialWindow {
					if prevHash != expectedPrev {
						rows.Close()
						return AuditChainVerification{
							VerifiedRows:  count,
							TotalRows:     totalRows,
							Valid:         false,
							PartialWindow: true,
							TailHash:      tailHash,
						}, fmt.Errorf("audit window boundary broken at seq=%d: prev_hash=%s != predecessor=%s", seq, prevHash, expectedPrev)
					}
				} else if prevHash != GenesisAuditHash {
					rows.Close()
					return AuditChainVerification{
						VerifiedRows:  count,
						TotalRows:     totalRows,
						Valid:         false,
						PartialWindow: false,
						TailHash:      tailHash,
					}, fmt.Errorf("initial audit row seq=%d does not anchor to GenesisAuditHash (deleted prefix detected)", seq)
				}
			} else {
				if prevHash != expectedPrev {
					rows.Close()
					return AuditChainVerification{
						VerifiedRows:  count,
						TotalRows:     totalRows,
						Valid:         false,
						PartialWindow: partialWindow,
						TailHash:      tailHash,
					}, fmt.Errorf("audit hash chain broken at seq=%d: prev_hash=%s != expected=%s", seq, prevHash, expectedPrev)
				}
				computed := ComputeAuditRowHash(prevHash, mergeTx, vp08Row)
				if computed != rowHash {
					rows.Close()
					return AuditChainVerification{
						VerifiedRows:  count,
						TotalRows:     totalRows,
						Valid:         false,
						PartialWindow: partialWindow,
						TailHash:      tailHash,
					}, fmt.Errorf("audit row_hash tampered at seq=%d: computed=%s != stored=%s", seq, computed, rowHash)
				}
			}

			expectedPrev = rowHash
			tailHash = rowHash
			afterSeq = seq
			hasAfterSeq = true
			count++
			batchCount++
		}
		if rErr := rows.Err(); rErr != nil {
			rows.Close()
			return AuditChainVerification{}, wrapRedactedError("iterate becmaster.audit chain", rErr, creds)
		}
		rows.Close()

		if batchCount < batchLimit {
			break
		}
	}

	if count > totalRows {
		totalRows = count
	}

	return AuditChainVerification{
		VerifiedRows:  count,
		TotalRows:     totalRows,
		Valid:         true,
		PartialWindow: partialWindow,
		TailHash:      tailHash,
	}, nil
}
