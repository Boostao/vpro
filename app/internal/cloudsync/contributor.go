package cloudsync

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/jackc/pgx/v5"
	"os"
	"strings"
	"time"
	"unicode/utf8"
)

// PullStandardsResult reports whether local VLists.db was already current or atomically updated.
type PullStandardsResult struct {
	Updated         bool                   `json:"updated"`
	AlreadyCurrent  bool                   `json:"alreadyCurrent"`
	ReleaseID       string                 `json:"releaseId"`
	BECVersion      string                 `json:"becVersion"`
	TaxonomyVersion string                 `json:"taxonomyVersion"`
	LocalSHA256     string                 `json:"localSha256"`
	CloudSHA256     string                 `json:"cloudSha256"`
	PublishedAt     string                 `json:"publishedAt,omitempty"`
	State           *vprocore.ProjectState `json:"state,omitempty"`
}

// SubsetFilter specifies criteria for querying/pulling a regional BECMaster subset.
type SubsetFilter struct {
	Zones             []string  `json:"zones,omitempty"`
	SubZones          []string  `json:"subzones,omitempty"`
	ProjectIDs        []string  `json:"projectIds,omitempty"`
	PlotNumbers       []string  `json:"plotNumbers,omitempty"`
	BBox              []float64 `json:"bbox,omitempty"` // [minLon, minLat, maxLon, maxLat]
	Limit             int       `json:"limit,omitempty"`
	AllowFullCheckout bool      `json:"allowFullCheckout,omitempty"`
}

func (r *SubsetFilter) UnmarshalJSON(data []byte) error {
	type plain SubsetFilter
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// SubsetPreview summarizes matching plot counts before downloading a local splinter .db.
type SubsetPreview struct {
	MatchingPlots     int            `json:"matchingPlots"`
	MatchingVeg       int64          `json:"matchingVeg"`
	SensitivePlots    int            `json:"sensitivePlots,omitempty"`
	CoordinatesMasked bool           `json:"coordinatesMasked,omitempty"`
	SamplePlots       []string       `json:"samplePlots"`
	ZoneBreakdown     map[string]int `json:"zoneBreakdown"`
}

// PullSubsetRequest downloads a filtered BECMaster subset into a fresh local VP08 SQLite .db.
type PullSubsetRequest struct {
	Filter                   SubsetFilter `json:"filter"`
	TargetProject            string       `json:"targetProject"`
	DestinationPath          string       `json:"destinationPath,omitempty"`
	ActivateOnSuccess        bool         `json:"activateOnSuccess"`
	MaskSensitiveCoordinates bool         `json:"maskSensitiveCoordinates,omitempty"`
}

func (r *PullSubsetRequest) UnmarshalJSON(data []byte) error {
	type plain PullSubsetRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// PullSubsetResult summarizes a completed regional subset download and download_log receipt.
type PullSubsetResult struct {
	TargetProject        string                 `json:"targetProject"`
	DestinationPath      string                 `json:"destinationPath"`
	DestinationSHA       string                 `json:"destinationSha256"`
	PlotCount            int                    `json:"plotCount"`
	VegCount             int                    `json:"vegCount"`
	HumusCount           int                    `json:"humusCount"`
	MineralCount         int                    `json:"mineralCount"`
	OtherCount           int                    `json:"otherCount"`
	MetadataCount        int                    `json:"metadataCount"`
	MaskedSensitivePlots int                    `json:"maskedSensitivePlots,omitempty"`
	DownloadLogID        int64                  `json:"downloadLogId"`
	Activated            bool                   `json:"activated"`
	State                *vprocore.ProjectState `json:"state,omitempty"`
}

// CloudUserSpeciesRecord mirrors VUser.USysUserSpp entries packaged with staging uploads.
type CloudUserSpeciesRecord struct {
	Code           string   `json:"code"`
	ScientificName *string  `json:"scientificName"`
	LifeForm       *int     `json:"lifeForm"`
	EnglishName    *string  `json:"englishName"`
	Report         *float64 `json:"report,omitempty"`
	SppNumber      *int     `json:"sppNumber,omitempty"`
	Codetype       *string  `json:"codetype,omitempty"`
}

// CloudUserSpeciesManifest packages personal species referenced by a submitted project.
type CloudUserSpeciesManifest struct {
	SchemaVersion string                   `json:"schemaVersion"`
	ExportedAt    string                   `json:"exportedAt"`
	SourceProject string                   `json:"sourceProject"`
	RowCount      int                      `json:"rowCount"`
	PayloadSHA256 string                   `json:"payloadSha256"`
	Species       []CloudUserSpeciesRecord `json:"species"`
}

// ComplianceGateResult decouples internal/cloudsync (Layer 2) from internal/validation (Layer 2).
type ComplianceGateResult struct {
	Passed        bool            `json:"passed"`
	BlockingCount int             `json:"blockingCount"`
	Summary       map[string]int  `json:"summary"`
	ReportJSON    json.RawMessage `json:"report"`
}

// ComplianceValidatorFunc runs compliance pre-flight validation against the active SQLite context.
type ComplianceValidatorFunc func(ctx context.Context, s *vprocore.ContextService, contextID string, useActiveSU bool) (ComplianceGateResult, error)

// StagingLumpRow captures an active <Project>_Lump row packaged in staging.submissions.
type StagingLumpRow struct {
	LumpCode string `json:"lumpCode"`
	SppCode  string `json:"sppCode"`
	Use      bool   `json:"use"`
}

// StagingSURow captures an active *_SU assignment packaged in staging.submissions.
type StagingSURow struct {
	PlotNumber string  `json:"plotNumber"`
	SiteUnit   *string `json:"siteUnit"`
}

// StagingPreflightPreview summarizes compliance, personal species, Lump, and SU counts prior to upload.
type StagingPreflightPreview struct {
	Project             string                   `json:"project"`
	ProjectID           string                   `json:"projectId"`
	PlotCount           int                      `json:"plotCount"`
	VegRowCount         int                      `json:"vegRowCount"`
	SourceDBSHA256      string                   `json:"sourceDbSha256"`
	CompliancePassed    bool                     `json:"compliancePassed"`
	BlockingErrorCount  int                      `json:"blockingErrorCount"`
	ComplianceSummary   map[string]int           `json:"complianceSummary"`
	ComplianceReport    json.RawMessage          `json:"complianceReport"`
	UserSpeciesManifest CloudUserSpeciesManifest `json:"userSpeciesManifest"`
	LumpRowCount        int                      `json:"lumpRowCount"`
	SURowCount          int                      `json:"suRowCount"`
}

// SubmitStagingRequest uploads the active local VP08 project to staging.submissions.
type SubmitStagingRequest struct {
	UseActiveSU       bool   `json:"useActiveSu,omitempty"`
	SubmitterNotes    string `json:"submitterNotes,omitempty"`
	SubmittedBy       string `json:"submittedBy,omitempty"`
	BaseSnapshotTag   string `json:"baseSnapshotTag,omitempty"`
	CustodianOverride bool   `json:"custodianOverride,omitempty"`
}

func (r *SubmitStagingRequest) UnmarshalJSON(data []byte) error {
	type plain SubmitStagingRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// SubmitStagingResult confirms atomic staging upload into PostgreSQL.
type SubmitStagingResult struct {
	SubmissionID     string `json:"submissionId"`
	ProjectName      string `json:"projectName"`
	ProjectID        string `json:"projectId"`
	SubmittedBy      string `json:"submittedBy"`
	DBRole           string `json:"dbRole"`
	Status           string `json:"status"`
	PlotCount        int    `json:"plotCount"`
	VegRowCount      int    `json:"vegRowCount"`
	UserSpeciesCount int    `json:"userSpeciesCount"`
	SourceDBSHA256   string `json:"sourceDbSha256"`
	CompliancePassed bool   `json:"compliancePassed"`
	SubmittedAt      string `json:"submittedAt"`
}

func validateSplinterProjectName(raw string) (string, error) {
	if !utf8.ValidString(raw) || strings.ContainsRune(raw, 0) {
		return "", errors.New("target project name must be valid UTF-8 without NUL")
	}
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || trimmed != raw {
		return "", errors.New("target project name must not be empty or contain leading/trailing whitespace")
	}
	if !vprocore.ProjectNamePattern.MatchString(trimmed) {
		return "", errors.New("target project name must start with a letter and use only ASCII letters, digits, or underscores (max 31 chars)")
	}
	lower := strings.ToLower(trimmed)
	if lower == "none" || lower == "sample" || strings.Contains(lower, "master") {
		return "", fmt.Errorf("target project name %q is reserved (None, Sample, and master names are not permitted)", trimmed)
	}
	return trimmed, nil
}

// PullCloudStandards compares standards.library_releases SHA-256 against local VLists.db
// and atomically swaps + reloads local VLists.db when a newer cloud release is active.
func (m *Manager) PullCloudStandards(ctx context.Context, s *vprocore.ContextService, contextID string) (PullStandardsResult, error) {
	if s == nil {
		return PullStandardsResult{}, errors.New("project context service is unavailable")
	}
	var localVListsPath string
	if _, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		localVListsPath = plots.Projects.SupportPaths["VLists"]
		if localVListsPath == "" && plots.Projects.Sqlite != nil {
			localVListsPath = plots.Projects.Sqlite.Attachments["VLists"]
		}
		return struct{}{}, nil
	}); err != nil {
		return PullStandardsResult{}, err
	}
	if strings.TrimSpace(localVListsPath) == "" {
		return PullStandardsResult{}, errors.New("active context has no attached VLists.db path")
	}

	localBytes, err := os.ReadFile(localVListsPath)
	if err != nil {
		return PullStandardsResult{}, fmt.Errorf("read local VLists.db: %w", err)
	}
	localSum := sha256.Sum256(localBytes)
	localSHA := hex.EncodeToString(localSum[:])

	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return PullStandardsResult{}, err
	}

	var releaseID, becVer, taxVer, cloudSHA string
	var pubAt time.Time
	var gzBytes []byte
	err = pool.QueryRow(ctx, `
		SELECT release_id, bec_version, taxonomy_version, vlists_sha256, published_at, vlists_gzip
		FROM standards.library_releases
		WHERE is_current = TRUE
		ORDER BY published_at DESC
		LIMIT 1
	`).Scan(&releaseID, &becVer, &taxVer, &cloudSHA, &pubAt, &gzBytes)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return PullStandardsResult{}, errors.New("no active provincial standards release has been published in standards.library_releases")
		}
		return PullStandardsResult{}, wrapRedactedError("query cloud standards release", err, creds)
	}

	if strings.EqualFold(localSHA, cloudSHA) {
		return PullStandardsResult{
			Updated:         false,
			AlreadyCurrent:  true,
			ReleaseID:       releaseID,
			BECVersion:      becVer,
			TaxonomyVersion: taxVer,
			LocalSHA256:     localSHA,
			CloudSHA256:     cloudSHA,
			PublishedAt:     pubAt.UTC().Format(time.RFC3339),
		}, nil
	}

	var stagedBytes []byte
	if len(gzBytes) > 0 {
		decompressed, dErr := decompressGzip(gzBytes)
		if dErr != nil {
			return PullStandardsResult{}, fmt.Errorf("decompress cloud VLists snapshot: %w", dErr)
		}
		gotSum := sha256.Sum256(decompressed)
		gotSHA := hex.EncodeToString(gotSum[:])
		if !strings.EqualFold(gotSHA, cloudSHA) {
			return PullStandardsResult{}, fmt.Errorf("cloud VLists SHA-256 mismatch (expected %s, got %s)", cloudSHA, gotSHA)
		}
		stagedBytes = decompressed
	} else {
		rebuilt, rErr := materializeVListsFromRelationalStandards(ctx, pool, localBytes, becVer, taxVer)
		if rErr != nil {
			return PullStandardsResult{}, wrapRedactedError("rebuild VLists.db from cloud standards tables", rErr, creds)
		}
		stagedBytes = rebuilt
	}

	newState, err := vprocore.ReplaceActiveVListsCatalogue(ctx, s, contextID, stagedBytes)
	if err != nil {
		return PullStandardsResult{}, err
	}
	finalSum := sha256.Sum256(stagedBytes)
	finalSHA := hex.EncodeToString(finalSum[:])

	return PullStandardsResult{
		Updated:         true,
		AlreadyCurrent:  false,
		ReleaseID:       releaseID,
		BECVersion:      becVer,
		TaxonomyVersion: taxVer,
		LocalSHA256:     finalSHA,
		CloudSHA256:     cloudSHA,
		PublishedAt:     pubAt.UTC().Format(time.RFC3339),
		State:           &newState,
	}, nil
}

func materializeVListsFromRelationalStandards(ctx context.Context, pool interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}, baseVListsBytes []byte, becVer, taxVer string) ([]byte, error) {
	tmpFile, err := os.CreateTemp("", "vpro-vlists-rebuild-*.db")
	if err != nil {
		return nil, err
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)
	if _, err := tmpFile.Write(baseVListsBytes); err != nil {
		_ = tmpFile.Close()
		return nil, err
	}
	if err := tmpFile.Close(); err != nil {
		return nil, err
	}

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		_ = db.Close()
		return nil, err
	}

	syncTable := func(pgTable, sqliteTable string, cols []ColumnSpec) error {
		if _, err := tx.ExecContext(ctx, "DELETE FROM "+quotePGIdent(sqliteTable)); err != nil {
			return err
		}
		pRows, qErr := pool.Query(ctx, fmt.Sprintf("SELECT %s FROM standards.%s ORDER BY row_seq", quotedColumnCSV(cols), quotePGIdent(pgTable)))
		if qErr != nil {
			return qErr
		}
		defer pRows.Close()

		marks := make([]string, len(cols))
		for i := range marks {
			marks[i] = "?"
		}
		stmt, sErr := tx.PrepareContext(ctx, fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
			quotePGIdent(sqliteTable), quotedColumnCSV(cols), strings.Join(marks, ", ")))
		if sErr != nil {
			return sErr
		}
		defer stmt.Close()

		for pRows.Next() {
			vals, vErr := pRows.Values()
			if vErr != nil {
				return vErr
			}
			args := make([]any, len(cols))
			for i, col := range cols {
				args[i] = CanonicalizePGToSQLite(col, vals[i])
			}
			if _, eErr := stmt.ExecContext(ctx, args...); eErr != nil {
				return eErr
			}
		}
		return pRows.Err()
	}

	for _, item := range []struct {
		pgTbl     string
		sqliteTbl string
		cols      []ColumnSpec
		optional  bool
	}{
		{"usys_all_specs", "USysAllSpecs", StandardsUSysAllSpecsColumns, false},
		{"usys_table_of_lists", "USysTableOfLists", StandardsUSysTableOfListsColumns, false},
		{"master_site_unit_list", "MasterSiteUnitList", StandardsMasterSiteUnitListColumns, false},
		{"usys_zone_list", "USysZoneList", StandardsUSysZoneListColumns, false},
		{"usys_spp_attributes", "USysSppAttributes", StandardsUSysSppAttributesColumns, true},
	} {
		if item.optional {
			chkRows, qErr := pool.Query(ctx, `SELECT to_regclass($1) IS NOT NULL`, "standards."+item.pgTbl)
			if qErr != nil {
				continue
			}
			var hasPG bool
			if chkRows.Next() {
				_ = chkRows.Scan(&hasPG)
			}
			chkRows.Close()
			if !hasPG {
				continue
			}
		}
		if err := syncTable(item.pgTbl, item.sqliteTbl, item.cols); err != nil {
			_ = tx.Rollback()
			_ = db.Close()
			return nil, err
		}
	}
	_, _ = tx.ExecContext(ctx, `UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = 'USysAllSpecs'`, taxVer)
	_, _ = tx.ExecContext(ctx, `UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = 'USysTableOfLists'`, becVer)
	if err := tx.Commit(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := db.Close(); err != nil {
		return nil, err
	}
	return os.ReadFile(tmpPath)
}
