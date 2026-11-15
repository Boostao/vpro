package cloudsync

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
	"github.com/jackc/pgx/v5"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// PublishStandardsRequest configures custodian publication of 2026 VLists + BECdb + VMetaData standards.
type PublishStandardsRequest struct {
	ReleaseID       string `json:"releaseId,omitempty"`
	BECVersion      string `json:"becVersion,omitempty"`
	TaxonomyVersion string `json:"taxonomyVersion,omitempty"`
	VListsPath      string `json:"vlistsPath,omitempty"`
	BECDBPath       string `json:"becDbPath,omitempty"`
	VMetaDataPath   string `json:"vmetaDataPath,omitempty"`
	Notes           string `json:"notes,omitempty"`
}

func (r *PublishStandardsRequest) UnmarshalJSON(data []byte) error {
	type plain PublishStandardsRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// PublishStandardsResult summarizes published reference library counts and digests.
type PublishStandardsResult struct {
	ReleaseID       string         `json:"releaseId"`
	BECVersion      string         `json:"becVersion"`
	TaxonomyVersion string         `json:"taxonomyVersion"`
	VListsSHA256    string         `json:"vlistsSha256"`
	BECDBSHA256     string         `json:"becDbSha256"`
	VMetaDataSHA256 string         `json:"vmetaDataSha256"`
	TableCounts     map[string]int `json:"tableCounts"`
	ElapsedMs       int64          `json:"elapsedMs"`
	PublishedAt     string         `json:"publishedAt"`
}

// SeedBaselineRequest configures streaming VP08 SQLite -> PostgreSQL becmaster.* baseline seeding.
type SeedBaselineRequest struct {
	SourceDBPath    string `json:"sourceDbPath"`
	SourceProject   string `json:"sourceProject,omitempty"`
	SnapshotTag     string `json:"snapshotTag,omitempty"`
	ReplaceExisting bool   `json:"replaceExisting"`
	SkipAudit       bool   `json:"skipAudit,omitempty"`
	Notes           string `json:"notes,omitempty"`
}

func (r *SeedBaselineRequest) UnmarshalJSON(data []byte) error {
	type plain SeedBaselineRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// SeedBaselineResult summarizes row counts and snapshot provenance from SeedBECMasterBaseline.
type SeedBaselineResult struct {
	SourceProject     string           `json:"sourceProject"`
	SourceSHA256      string           `json:"sourceSha256"`
	SnapshotTag       string           `json:"snapshotTag"`
	PlotCount         int              `json:"plotCount"`
	AdminCount        int              `json:"adminCount"`
	VegCount          int64            `json:"vegCount"`
	HumusCount        int64            `json:"humusCount"`
	MineralCount      int64            `json:"mineralCount"`
	OtherCount        int64            `json:"otherCount"`
	MetadataCount     int              `json:"metadataCount"`
	AuditCount        int64            `json:"auditCount"`
	ChildIdentityRows int64            `json:"childIdentityRows"`
	TailAuditHash     string           `json:"tailAuditHash"`
	ElapsedMs         int64            `json:"elapsedMs"`
	SeededAt          string           `json:"seededAt"`
	TableCounts       map[string]int64 `json:"tableCounts"`
}

func readBundledStandardsVersions() (becVer, taxVer string) {
	becVer = "BECdb_v13_2026"
	taxVer = "BCPlantTaxa_v19_2025"
	var parsed struct {
		Sources []struct {
			Version string `json:"version"`
		} `json:"sources"`
	}
	if err := json.Unmarshal(resources.Standards2026ProvenanceJSON, &parsed); err == nil {
		for _, src := range parsed.Sources {
			switch {
			case strings.HasPrefix(src.Version, "BECdb_v13"):
				becVer = src.Version
			case strings.HasPrefix(src.Version, "BCPlantTaxa_v19"):
				taxVer = src.Version
			}
		}
	}
	return becVer, taxVer
}

func compressGzipFast(raw []byte) ([]byte, error) {
	var buf bytes.Buffer
	gw, err := gzip.NewWriterLevel(&buf, gzip.BestSpeed)
	if err != nil {
		return nil, err
	}
	if _, err := gw.Write(raw); err != nil {
		_ = gw.Close()
		return nil, err
	}
	if err := gw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func decompressGzip(compressed []byte) ([]byte, error) {
	gr, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return nil, err
	}
	defer gr.Close()
	return io.ReadAll(gr)
}

func streamFileSHA256Hex(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// createConsistentSQLiteSnapshot uses SQLite VACUUM INTO to capture an atomic, standalone
// WAL-merged snapshot of an active SQLite database so hashing and streaming observe identical rows.
func createConsistentSQLiteSnapshot(ctx context.Context, srcPath string) (snapPath string, cleanup func(), err error) {
	cleanup = func() {}
	tmpDir, err := os.MkdirTemp("", "vpro-sqlsnap-*")
	if err != nil {
		return "", cleanup, err
	}
	cleanup = func() { _ = os.RemoveAll(tmpDir) }
	snapPath = filepath.Join(tmpDir, "snapshot.db")

	db, err := sqlutil.OpenReadOnlyContext(ctx, srcPath)
	if err != nil {
		cleanup()
		return "", func() {}, err
	}
	defer db.Close()

	escaped := strings.ReplaceAll(snapPath, "'", "''")
	if _, err := db.ExecContext(ctx, fmt.Sprintf("VACUUM INTO '%s'", escaped)); err != nil {
		cleanup()
		return "", func() {}, err
	}
	return snapPath, cleanup, nil
}

func materializeTempSQLiteIfNeeded(ctx context.Context, explicitPath string, fallbackBytes []byte, label string) (path string, rawBytes []byte, shaHex string, cleanup func(), err error) {
	cleanup = func() {}
	if trimmed := strings.TrimSpace(explicitPath); trimmed != "" {
		resolved, rErr := vprocore.ExistingDatabasePath(trimmed)
		if rErr != nil {
			return "", nil, "", cleanup, fmt.Errorf("%s database: %w", label, rErr)
		}
		targetPath := resolved
		if walInfo, wErr := os.Stat(resolved + "-wal"); wErr == nil && walInfo.Size() > 0 {
			snapPath, snapClean, sErr := createConsistentSQLiteSnapshot(ctx, resolved)
			if sErr != nil {
				return "", nil, "", cleanup, fmt.Errorf("snapshot WAL-backed %s database: %w", label, sErr)
			}
			targetPath = snapPath
			cleanup = snapClean
		}
		data, rErr := os.ReadFile(targetPath)
		if rErr != nil {
			cleanup()
			return "", nil, "", func() {}, rErr
		}
		sum := sha256.Sum256(data)
		return targetPath, data, hex.EncodeToString(sum[:]), cleanup, nil
	}
	if len(fallbackBytes) == 0 {
		return "", nil, "", cleanup, fmt.Errorf("missing %s database bytes", label)
	}
	tmp, tErr := os.CreateTemp("", "vpro-std-*.db")
	if tErr != nil {
		return "", nil, "", cleanup, tErr
	}
	tmpName := tmp.Name()
	cleanup = func() { _ = os.Remove(tmpName) }
	if _, wErr := tmp.Write(fallbackBytes); wErr != nil {
		_ = tmp.Close()
		cleanup()
		return "", nil, "", func() {}, wErr
	}
	if cErr := tmp.Close(); cErr != nil {
		cleanup()
		return "", nil, "", func() {}, cErr
	}
	sum := sha256.Sum256(fallbackBytes)
	return tmpName, fallbackBytes, hex.EncodeToString(sum[:]), cleanup, nil
}

func copySQLiteTableToPG(
	ctx context.Context,
	tx pgx.Tx,
	sqliteDB *sql.DB,
	sqliteTable string,
	pgSchema string,
	pgTable string,
	cols []ColumnSpec,
) (int64, error) {
	selectCols := sqliteSelectColumnsCSV(cols)
	query := fmt.Sprintf("SELECT %s FROM %s", selectCols, quotePGIdent(sqliteTable))
	rows, err := sqliteDB.QueryContext(ctx, query)
	if err != nil {
		return 0, fmt.Errorf("query SQLite %s: %w", sqliteTable, err)
	}
	defer rows.Close()

	rawVals := make([]any, len(cols))
	scanDest := make([]any, len(cols))
	for i := range rawVals {
		scanDest[i] = &rawVals[i]
	}

	var streamErr error
	copied, copyErr := tx.CopyFrom(
		ctx,
		pgx.Identifier{pgSchema, pgTable},
		columnNames(cols),
		pgx.CopyFromFunc(func() ([]any, error) {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			if !rows.Next() {
				return nil, rows.Err()
			}
			if err := rows.Scan(scanDest...); err != nil {
				return nil, err
			}
			out := make([]any, len(cols))
			for i, col := range cols {
				conv, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
				if cErr != nil {
					streamErr = fmt.Errorf("%s.%s: %w", sqliteTable, col.Name, cErr)
					return nil, streamErr
				}
				out[i] = conv
			}
			return out, nil
		}),
	)
	if streamErr != nil {
		return 0, streamErr
	}
	if copyErr != nil {
		return 0, copyErr
	}
	return copied, rows.Close()
}

// PublishStandardsToCloud streams VLists.db + bec.db + VMetaData.db into standards.* via pgx.CopyFrom.
func (m *Manager) PublishStandardsToCloud(ctx context.Context, s *vprocore.ContextService, contextID string, req PublishStandardsRequest) (PublishStandardsResult, error) {
	t0 := time.Now()
	defaultBECVer, defaultTaxVer := readBundledStandardsVersions()
	becVer := strings.TrimSpace(req.BECVersion)
	if becVer == "" {
		becVer = defaultBECVer
	}
	taxVer := strings.TrimSpace(req.TaxonomyVersion)
	if taxVer == "" {
		taxVer = defaultTaxVer
	}

	vlistsExplicit := strings.TrimSpace(req.VListsPath)
	vmetaExplicit := strings.TrimSpace(req.VMetaDataPath)
	actor := "Custodian"
	if s != nil && contextID != "" {
		_, _ = vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
			if vlistsExplicit == "" {
				vlistsExplicit = plots.Projects.SupportPaths["VLists"]
			}
			if vmetaExplicit == "" {
				vmetaExplicit = plots.Projects.SupportPaths["VMetaData"]
			}
			if u := strings.TrimSpace(plots.CurrentUser); u != "" {
				actor = u
			}
			return struct{}{}, nil
		})
	}

	var bundledVLists, bundledVMeta []byte
	if vlistsExplicit == "" {
		bundledVLists, _ = resources.DatabaseFamilyFS.ReadFile("resources/database-family/VLists.db")
	}
	if vmetaExplicit == "" {
		bundledVMeta, _ = resources.DatabaseFamilyFS.ReadFile("resources/database-family/VMetaData.db")
	}

	vlistsPath, vlistsBytes, vlistsSHA, cleanVLists, err := materializeTempSQLiteIfNeeded(ctx, vlistsExplicit, bundledVLists, "VLists")
	if err != nil {
		return PublishStandardsResult{}, err
	}
	defer cleanVLists()

	becPath, _, becSHA, cleanBEC, err := materializeTempSQLiteIfNeeded(ctx, req.BECDBPath, resources.BECDB, "BEC")
	if err != nil {
		return PublishStandardsResult{}, err
	}
	defer cleanBEC()

	vmetaPath, _, vmetaSHA, cleanVMeta, err := materializeTempSQLiteIfNeeded(ctx, vmetaExplicit, bundledVMeta, "VMetaData")
	if err != nil {
		return PublishStandardsResult{}, err
	}
	defer cleanVMeta()

	vlistsGzip, err := compressGzipFast(vlistsBytes)
	if err != nil {
		return PublishStandardsResult{}, fmt.Errorf("compress VLists.db snapshot: %w", err)
	}

	releaseID := strings.TrimSpace(req.ReleaseID)
	if releaseID == "" {
		releaseID = fmt.Sprintf("%s__%s__%s", becVer, taxVer, vlistsSHA[:12])
	}

	vlistsSQLite, err := sqlutil.OpenReadOnlyContext(ctx, vlistsPath)
	if err != nil {
		return PublishStandardsResult{}, fmt.Errorf("open VLists.db: %w", err)
	}
	defer vlistsSQLite.Close()

	becSQLite, err := sqlutil.OpenReadOnlyContext(ctx, becPath)
	if err != nil {
		return PublishStandardsResult{}, fmt.Errorf("open bec.db: %w", err)
	}
	defer becSQLite.Close()

	vmetaSQLite, err := sqlutil.OpenReadOnlyContext(ctx, vmetaPath)
	if err != nil {
		return PublishStandardsResult{}, fmt.Errorf("open VMetaData.db: %w", err)
	}
	defer vmetaSQLite.Close()

	conn, creds, err := m.OpenDedicatedConn(ctx, RoleModeCustodian)
	if err != nil {
		return PublishStandardsResult{}, err
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		return PublishStandardsResult{}, wrapRedactedError("begin standards publish transaction", err, creds)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `
		TRUNCATE TABLE
			standards.usys_all_specs,
			standards.usys_table_of_lists,
			standards.bec_site_series,
			standards.master_site_unit_list,
			standards.usys_zone_list,
			standards.usys_spp_attributes,
			standards.project_metadata
		RESTART IDENTITY
	`); err != nil {
		return PublishStandardsResult{}, wrapRedactedError("truncate standards tables", err, creds)
	}

	counts := make(map[string]int, 7)
	type copyJob struct {
		db       *sql.DB
		srcTable string
		pgTable  string
		cols     []ColumnSpec
	}
	jobs := []copyJob{
		{vlistsSQLite, "USysAllSpecs", "usys_all_specs", StandardsUSysAllSpecsColumns},
		{vlistsSQLite, "USysTableOfLists", "usys_table_of_lists", StandardsUSysTableOfListsColumns},
		{becSQLite, "BECSiteSeries", "bec_site_series", StandardsBECSiteSeriesColumns},
		{vlistsSQLite, "MasterSiteUnitList", "master_site_unit_list", StandardsMasterSiteUnitListColumns},
		{vlistsSQLite, "USysZoneList", "usys_zone_list", StandardsUSysZoneListColumns},
		{vlistsSQLite, "USysSppAttributes", "usys_spp_attributes", StandardsUSysSppAttributesColumns},
		{vmetaSQLite, "ProjectMetadata", "project_metadata", StandardsProjectMetadataColumns},
	}
	for _, job := range jobs {
		n, cErr := copySQLiteTableToPG(ctx, tx, job.db, job.srcTable, "standards", job.pgTable, job.cols)
		if cErr != nil {
			return PublishStandardsResult{}, wrapRedactedError("copy "+job.pgTable, cErr, creds)
		}
		counts[job.pgTable] = int(n)
	}

	nowUTC := time.Now().UTC()
	if _, err := tx.Exec(ctx, `UPDATE standards.library_releases SET is_current = FALSE WHERE is_current = TRUE`); err != nil {
		return PublishStandardsResult{}, wrapRedactedError("retire prior current release", err, creds)
	}
	var notesPtr *string
	if n := strings.TrimSpace(req.Notes); n != "" {
		notesPtr = &n
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO standards.library_releases (
			release_id, published_at, published_by, bec_version, taxonomy_version,
			vlists_sha256, bec_db_sha256, vmetadata_sha256, notes, is_current, vlists_gzip
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, TRUE, $10)
		ON CONFLICT (release_id) DO UPDATE SET
			published_at = EXCLUDED.published_at,
			published_by = EXCLUDED.published_by,
			bec_version = EXCLUDED.bec_version,
			taxonomy_version = EXCLUDED.taxonomy_version,
			vlists_sha256 = EXCLUDED.vlists_sha256,
			bec_db_sha256 = EXCLUDED.bec_db_sha256,
			vmetadata_sha256 = EXCLUDED.vmetadata_sha256,
			notes = EXCLUDED.notes,
			is_current = TRUE,
			vlists_gzip = EXCLUDED.vlists_gzip
	`, releaseID, nowUTC, actor, becVer, taxVer, vlistsSHA, becSHA, vmetaSHA, notesPtr, vlistsGzip); err != nil {
		return PublishStandardsResult{}, wrapRedactedError("record standards release", err, creds)
	}

	if err := tx.Commit(ctx); err != nil {
		return PublishStandardsResult{}, wrapRedactedError("commit standards release", err, creds)
	}

	return PublishStandardsResult{
		ReleaseID:       releaseID,
		BECVersion:      becVer,
		TaxonomyVersion: taxVer,
		VListsSHA256:    vlistsSHA,
		BECDBSHA256:     becSHA,
		VMetaDataSHA256: vmetaSHA,
		TableCounts:     counts,
		ElapsedMs:       time.Since(t0).Milliseconds(),
		PublishedAt:     nowUTC.Format(time.RFC3339),
	}, nil
}

func resolveProjectInSQLiteFile(ctx context.Context, dbPath, requestedProject string) (string, string, error) {
	resolved, err := vprocore.ExistingDatabasePath(dbPath)
	if err != nil {
		return "", "", err
	}
	projects, err := vprocore.InspectFileContext(ctx, resolved)
	if err != nil {
		return "", "", err
	}
	reqProj := strings.TrimSpace(requestedProject)
	if reqProj != "" {
		for _, p := range projects {
			if p.Name == reqProj && p.Compatible {
				return resolved, p.Name, nil
			}
		}
		return "", "", fmt.Errorf("compatible VP08 project %q not found in %s", reqProj, resolved)
	}
	var compatible []string
	for _, p := range projects {
		if p.Compatible {
			compatible = append(compatible, p.Name)
		}
	}
	if len(compatible) == 0 {
		return "", "", fmt.Errorf("no compatible VP08 project found in %s", resolved)
	}
	if len(compatible) > 1 {
		return "", "", fmt.Errorf("multiple compatible projects (%s) found in %s; specify sourceProject explicitly", strings.Join(compatible, ", "), resolved)
	}
	return resolved, compatible[0], nil
}
