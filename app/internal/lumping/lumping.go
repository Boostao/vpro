package lumping

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	LumpTableMetadataVersion = "VP05"
	MaxLumpCodeUTF16Units    = 50
	MaxSppCodeUTF16Units     = 8
	FoldedCoverCap           = 99.0
)

type LumpTableSummary struct {
	Name              string `json:"name"`
	TableName         string `json:"tableName"`
	DatabasePath      string `json:"databasePath"`
	IsActiveProject   bool   `json:"isActiveProject"`
	MetadataVersion   string `json:"metadataVersion"`
	RowCount          int    `json:"rowCount"`
	ActiveCount       int    `json:"activeCount"`
	DistinctLumpCodes int    `json:"distinctLumpCodes"`
}

type LumpRow struct {
	LumpCode       string `json:"lumpCode"`
	SppCode        string `json:"sppCode"`
	Use            bool   `json:"use"`
	ScientificName string `json:"scientificName"`
	EnglishName    string `json:"englishName"`
	Lifeform       *int   `json:"lifeform,omitempty"`
	SourceCatalog  string `json:"sourceCatalog"`
	LumpKnown      bool   `json:"lumpKnown"`
	RuleOrigin     string `json:"ruleOrigin,omitempty"`
}

type LumpRowInput struct {
	LumpCode      string `json:"lumpCode"`
	SppCode       string `json:"sppCode"`
	Use           bool   `json:"use"`
	AllowUnlisted bool   `json:"allowUnlisted,omitempty"`
}

func (r *LumpRowInput) UnmarshalJSON(data []byte) error {
	type plain LumpRowInput
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type LumpGroupImpact struct {
	LumpCode           string   `json:"lumpCode"`
	SourceSpecies      []string `json:"sourceSpecies"`
	PlotCount          int      `json:"plotCount"`
	RawObservations    int      `json:"rawObservations"`
	FoldedObservations int      `json:"foldedObservations"`
	MaxFoldedCover     float64  `json:"maxFoldedCover"`
	CappedCells        int      `json:"cappedCells"`
}

type LumpImpactPreview struct {
	TableName             string            `json:"tableName"`
	DatabasePath          string            `json:"databasePath"`
	TotalPlots            int               `json:"totalPlots"`
	DistinctRawSpecies    int               `json:"distinctRawSpecies"`
	DistinctFoldedSpecies int               `json:"distinctFoldedSpecies"`
	SpeciesFoldedCount    int               `json:"speciesFoldedCount"`
	RawObservations       int               `json:"rawObservations"`
	FoldedObservations    int               `json:"foldedObservations"`
	MergedCells           int               `json:"mergedCells"`
	CappedCells           int               `json:"cappedCells"`
	CoverCap              float64           `json:"coverCap"`
	Groups                []LumpGroupImpact `json:"groups"`
}

type speciesTaxonomyEntry struct {
	Code           string
	ScientificName string
	EnglishName    string
	Lifeform       *int
	Codetype       string
	TaxonLevel     string
	SourceCatalog  string
}

func accessBoolToInt(use bool) int {
	if use {
		return -1
	}
	return 0
}

func normalizeAccessBool(raw any) bool {
	switch v := raw.(type) {
	case nil:
		return false
	case bool:
		return v
	case int64:
		return v != 0
	case int:
		return v != 0
	case float64:
		return v != 0
	case []byte:
		return normalizeAccessBool(string(v))
	case string:
		trimmed := strings.TrimSpace(strings.ToLower(v))
		return trimmed == "-1" || trimmed == "1" || trimmed == "true" || trimmed == "yes"
	default:
		return false
	}
}

func ValidateLumpBaseName(name string) error {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" || !utf8.ValidString(trimmed) || strings.ContainsRune(trimmed, 0) {
		return errors.New("lump table name must be a non-empty valid UTF-8 identifier")
	}
	if strings.HasSuffix(strings.ToLower(trimmed), "_lump") {
		trimmed = trimmed[:len(trimmed)-len("_Lump")]
	}
	if !vprocore.ProjectNamePattern.MatchString(trimmed) {
		return fmt.Errorf("lump table name %q must start with a letter and use only letters, digits, or underscores (max 31 chars)", trimmed)
	}
	lower := strings.ToLower(trimmed)
	if lower == "none" || lower == "combinedspp" || lower == "attribute" || strings.HasPrefix(lower, "usys") {
		return fmt.Errorf("lump table name %q is reserved by VPro", trimmed)
	}
	return nil
}

func normalizeLumpBaseName(name string) (string, string, error) {
	trimmed := strings.TrimSpace(name)
	if strings.HasSuffix(strings.ToLower(trimmed), "_lump") {
		trimmed = trimmed[:len(trimmed)-len("_Lump")]
	}
	if err := ValidateLumpBaseName(trimmed); err != nil {
		return "", "", err
	}
	return trimmed, trimmed + "_Lump", nil
}

func ValidateLumpCodes(lumpCode, sppCode string) (string, string, error) {
	if !utf8.ValidString(lumpCode) || !utf8.ValidString(sppCode) {
		return "", "", errors.New("lump and species codes must contain valid UTF-8")
	}
	if strings.ContainsRune(lumpCode, 0) || strings.ContainsRune(sppCode, 0) {
		return "", "", errors.New("lump and species codes must not contain NUL characters")
	}
	cleanLump := strings.ToUpper(strings.TrimSpace(lumpCode))
	cleanSpp := strings.ToUpper(strings.TrimSpace(sppCode))
	if cleanLump == "" {
		return "", "", errors.New("LumpCode must not be empty")
	}
	if cleanSpp == "" {
		return "", "", errors.New("SppCode must not be empty")
	}
	if len(utf16.Encode([]rune(cleanLump))) > MaxLumpCodeUTF16Units {
		return "", "", fmt.Errorf("LumpCode %q exceeds %d UTF-16 code units", cleanLump, MaxLumpCodeUTF16Units)
	}
	if len(utf16.Encode([]rune(cleanSpp))) > MaxSppCodeUTF16Units {
		return "", "", fmt.Errorf("SppCode %q exceeds %d UTF-16 code units", cleanSpp, MaxSppCodeUTF16Units)
	}
	if strings.EqualFold(cleanLump, cleanSpp) {
		return "", "", fmt.Errorf("LumpCode and SppCode cannot be identical (%s)", cleanSpp)
	}
	return cleanLump, cleanSpp, nil
}

func loadTaxonomyCatalog(ctx context.Context, tx *sql.Tx) (map[string]speciesTaxonomyEntry, map[string]string, error) {
	byCode := make(map[string]speciesTaxonomyEntry, 16500)
	genusCodeByName := make(map[string]string, 1500)

	rows, err := tx.QueryContext(ctx, `
		SELECT Code, OldCode, ScientificName, EnglishName, Lifeform, Codetype, TaxonLevel
		FROM VLists.USysAllSpecs
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''
		ORDER BY CASE WHEN UPPER(COALESCE(Codetype,'')) = 'U' THEN 0 ELSE 1 END, rowid`)
	if err != nil {
		return nil, nil, fmt.Errorf("read VLists.USysAllSpecs: %w", err)
	}
	defer rows.Close()

	var synonyms [][2]string
	for rows.Next() {
		var code string
		var oldCode, sci, eng, codetype, taxonLevel sql.NullString
		var lifeform sql.NullInt64
		if err := rows.Scan(&code, &oldCode, &sci, &eng, &lifeform, &codetype, &taxonLevel); err != nil {
			return nil, nil, err
		}
		upper := strings.ToUpper(strings.TrimSpace(code))
		if upper == "" {
			continue
		}
		var lfPtr *int
		if lifeform.Valid {
			v := int(lifeform.Int64)
			lfPtr = &v
		}
		entry := speciesTaxonomyEntry{
			Code:           upper,
			ScientificName: strings.TrimSpace(sci.String),
			EnglishName:    strings.TrimSpace(eng.String),
			Lifeform:       lfPtr,
			Codetype:       strings.ToUpper(strings.TrimSpace(codetype.String)),
			TaxonLevel:     strings.ToLower(strings.TrimSpace(taxonLevel.String)),
			SourceCatalog:  "VLists",
		}
		if existing, exists := byCode[upper]; !exists || (existing.Codetype != "U" && entry.Codetype == "U") {
			byCode[upper] = entry
		}
		if (entry.TaxonLevel == "gen" || entry.TaxonLevel == "genus") && entry.ScientificName != "" {
			genusWord := strings.ToUpper(strings.Fields(entry.ScientificName)[0])
			if _, ok := genusCodeByName[genusWord]; !ok || entry.Codetype == "U" {
				genusCodeByName[genusWord] = upper
			}
		}
		if oldCode.Valid {
			oldUpper := strings.ToUpper(strings.TrimSpace(oldCode.String))
			if oldUpper != "" && oldUpper != upper {
				synonyms = append(synonyms, [2]string{oldUpper, upper})
			}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	for _, syn := range synonyms {
		if _, exists := byCode[syn[0]]; !exists {
			target := byCode[syn[1]]
			target.Code = syn[0]
			target.SourceCatalog = "Synonym"
			byCode[syn[0]] = target
		}
	}

	uRows, err := tx.QueryContext(ctx, `
		SELECT Code, ScientificName, EnglishName, LifeForm, Codetype
		FROM VUser.USysUserSpp
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''`)
	if err != nil {
		return nil, nil, fmt.Errorf("read VUser.USysUserSpp: %w", err)
	}
	defer uRows.Close()
	for uRows.Next() {
		var code string
		var sci, eng, codetype sql.NullString
		var lifeform sql.NullInt64
		if err := uRows.Scan(&code, &sci, &eng, &lifeform, &codetype); err != nil {
			return nil, nil, err
		}
		upper := strings.ToUpper(strings.TrimSpace(code))
		if upper == "" {
			continue
		}
		if _, exists := byCode[upper]; exists {
			continue
		}
		var lfPtr *int
		if lifeform.Valid {
			v := int(lifeform.Int64)
			lfPtr = &v
		}
		byCode[upper] = speciesTaxonomyEntry{
			Code:           upper,
			ScientificName: strings.TrimSpace(sci.String),
			EnglishName:    strings.TrimSpace(eng.String),
			Lifeform:       lfPtr,
			Codetype:       strings.ToUpper(strings.TrimSpace(codetype.String)),
			SourceCatalog:  "VUser",
		}
	}
	if err := uRows.Err(); err != nil {
		return nil, nil, err
	}
	return byCode, genusCodeByName, nil
}

func loadCatalogForContext(ctx context.Context, owner *vprocore.SqliteContext) (map[string]speciesTaxonomyEntry, map[string]string, error) {
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return nil, nil, err
	}
	defer owner.Mu.Unlock()
	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return nil, nil, err
	}
	defer func() { _ = tx.Rollback() }()
	catalog, genusMap, err := loadTaxonomyCatalog(ctx, tx)
	if err != nil {
		return nil, nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, nil, err
	}
	return catalog, genusMap, nil
}

func enrichLumpRow(row LumpRow, catalog map[string]speciesTaxonomyEntry) LumpRow {
	upperSpp := strings.ToUpper(strings.TrimSpace(row.SppCode))
	upperLump := strings.ToUpper(strings.TrimSpace(row.LumpCode))
	if entry, ok := catalog[upperSpp]; ok {
		row.ScientificName = entry.ScientificName
		row.EnglishName = entry.EnglishName
		row.Lifeform = entry.Lifeform
		row.SourceCatalog = entry.SourceCatalog
	} else {
		row.SourceCatalog = "Unlisted"
	}
	_, row.LumpKnown = catalog[upperLump]
	return row
}

func inspectDatabaseLumpTables(ctx context.Context, dbPath string, activeProjectPath string) ([]LumpTableSummary, error) {
	resolved, err := vprocore.ExistingDatabasePath(dbPath)
	if err != nil {
		return nil, err
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, resolved)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	metaVersions := map[string]string{}
	var hasMeta bool
	if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='_table_metadata')`).Scan(&hasMeta); err == nil && hasMeta {
		mRows, mErr := db.QueryContext(ctx, `SELECT table_name, COALESCE(description, '') FROM "_table_metadata"`)
		if mErr == nil {
			for mRows.Next() {
				var tName, desc string
				if err := mRows.Scan(&tName, &desc); err == nil {
					metaVersions[strings.ToLower(tName)] = desc
				}
			}
			mRows.Close()
		}
	}

	tRows, err := db.QueryContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' ORDER BY name COLLATE NOCASE`)
	if err != nil {
		return nil, err
	}
	var candidateTables []string
	for tRows.Next() {
		var name string
		if err := tRows.Scan(&name); err != nil {
			tRows.Close()
			return nil, err
		}
		if len(name) > 5 && strings.EqualFold(name[len(name)-5:], "_Lump") && !strings.HasPrefix(strings.ToUpper(name), "USYS") {
			candidateTables = append(candidateTables, name)
		}
	}
	if err := tRows.Close(); err != nil {
		return nil, err
	}

	isActive := resolved == activeProjectPath
	if !isActive {
		if aInfo, err1 := os.Stat(activeProjectPath); err1 == nil {
			if bInfo, err2 := os.Stat(resolved); err2 == nil && os.SameFile(aInfo, bInfo) {
				isActive = true
			}
		}
	}

	summaries := make([]LumpTableSummary, 0, len(candidateTables))
	for _, tbl := range candidateTables {
		cols, colErr := readTableColumnSet(ctx, db, tbl)
		if colErr != nil || !cols["lumpcode"] || !cols["sppcode"] || !cols["use"] {
			continue
		}
		base := tbl[:len(tbl)-5]
		quoted := vprocore.QuoteHeaderIdentifier(tbl)
		var rowCount, distinctLump int
		var activeCount int
		rows, qErr := db.QueryContext(ctx, `SELECT LumpCode, CASE WHEN "Use" IS NULL THEN NULL WHEN typeof("Use")='text' THEN "Use" ELSE CAST("Use" AS INTEGER) END FROM `+quoted)
		if qErr != nil {
			continue
		}
		lumpSet := map[string]struct{}{}
		for rows.Next() {
			var lc sql.NullString
			var rawUse any
			if sErr := rows.Scan(&lc, &rawUse); sErr != nil {
				continue
			}
			rowCount++
			if lc.Valid && strings.TrimSpace(lc.String) != "" {
				lumpSet[strings.ToUpper(strings.TrimSpace(lc.String))] = struct{}{}
			}
			if normalizeAccessBool(rawUse) {
				activeCount++
			}
		}
		rows.Close()
		distinctLump = len(lumpSet)
		summaries = append(summaries, LumpTableSummary{
			Name:              base,
			TableName:         tbl,
			DatabasePath:      resolved,
			IsActiveProject:   isActive,
			MetadataVersion:   metaVersions[strings.ToLower(tbl)],
			RowCount:          rowCount,
			ActiveCount:       activeCount,
			DistinctLumpCodes: distinctLump,
		})
	}
	return summaries, nil
}

func readTableColumnSet(ctx context.Context, db *sql.DB, table string) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+vprocore.QuoteHeaderIdentifier(table)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, ctype string
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[strings.ToLower(name)] = true
	}
	return cols, rows.Err()
}

func DiscoverLumpTables(s *vprocore.ContextService, ctx context.Context, contextID string, externalPaths []string) ([]LumpTableSummary, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) ([]LumpTableSummary, error) {
		projectPath := plots.Projects.Sqlite.Selection.ProjectPath
		seenFiles := []os.FileInfo{}
		var candidatePaths []string
		addPath := func(p string) {
			trimmed := strings.TrimSpace(p)
			if trimmed == "" {
				return
			}
			abs, err := filepath.Abs(trimmed)
			if err != nil {
				return
			}
			info, err := os.Stat(abs)
			if err != nil || !info.Mode().IsRegular() {
				return
			}
			for _, existing := range seenFiles {
				if os.SameFile(existing, info) {
					return
				}
			}
			seenFiles = append(seenFiles, info)
			candidatePaths = append(candidatePaths, abs)
		}

		addPath(projectPath)
		if entries, err := os.ReadDir(filepath.Dir(projectPath)); err == nil {
			for _, entry := range entries {
				if !entry.IsDir() && strings.EqualFold(filepath.Ext(entry.Name()), ".db") {
					addPath(filepath.Join(filepath.Dir(projectPath), entry.Name()))
				}
			}
		}
		for _, ext := range externalPaths {
			addPath(ext)
		}

		results := []LumpTableSummary{}
		for _, dbPath := range candidatePaths {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			items, err := inspectDatabaseLumpTables(ctx, dbPath, projectPath)
			if err != nil {
				if dbPath == projectPath {
					return nil, err
				}
				continue
			}
			results = append(results, items...)
		}
		slices.SortFunc(results, func(a, b LumpTableSummary) int {
			if a.IsActiveProject != b.IsActiveProject {
				if a.IsActiveProject {
					return -1
				}
				return 1
			}
			if c := strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name)); c != 0 {
				return c
			}
			return strings.Compare(a.DatabasePath, b.DatabasePath)
		})
		return results, nil
	})
}

func withImmediateProjectWriteTx(ctx context.Context, owner *vprocore.SqliteContext, fn func(*sql.Conn) error) (resultErr error) {
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return err
	}
	defer owner.Mu.Unlock()
	if owner.Conn == nil {
		return errors.New("project context is closed")
	}
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(owner.Selection.ProjectPath, "rw")+"&_foreign_keys=on&_busy_timeout=5000&_journal_mode=WAL&_txlock=immediate")
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, db.Close()) }()
	db.SetMaxOpenConns(1)
	conn, err := db.Conn(ctx)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, conn.Close()) }()
	if _, err := conn.ExecContext(ctx, "BEGIN IMMEDIATE"); err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			_, _ = conn.ExecContext(context.WithoutCancel(ctx), "ROLLBACK")
		}
	}()
	if err := fn(conn); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if _, err := conn.ExecContext(ctx, "COMMIT"); err != nil {
		return err
	}
	committed = true
	return nil
}

func createLumpTableInTx(ctx context.Context, conn *sql.Conn, baseName string) (string, error) {
	base, tableName, err := normalizeLumpBaseName(baseName)
	if err != nil {
		return "", err
	}
	var exists bool
	if err := conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name COLLATE NOCASE=?)`, tableName).Scan(&exists); err != nil {
		return "", err
	}
	if exists {
		return "", fmt.Errorf("lump table %s already exists in the active project", tableName)
	}
	quoted := vprocore.QuoteHeaderIdentifier(tableName)
	idxName := vprocore.QuoteHeaderIdentifier("idx_" + base + "_Lump_LumpCode")
	if _, err := conn.ExecContext(ctx, `CREATE TABLE `+quoted+` ("LumpCode" VARCHAR(50), "SppCode" VARCHAR(8) UNIQUE, "Use" BOOLEAN)`); err != nil {
		return "", fmt.Errorf("create %s: %w", tableName, err)
	}
	if _, err := conn.ExecContext(ctx, `CREATE INDEX `+idxName+` ON `+quoted+` ("LumpCode")`); err != nil {
		return "", fmt.Errorf("index %s: %w", tableName, err)
	}
	if _, err := conn.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
		return "", err
	}
	if _, err := conn.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, tableName, LumpTableMetadataVersion); err != nil {
		return "", err
	}
	return tableName, nil
}

func CreateLumpTable(s *vprocore.ContextService, ctx context.Context, contextID, name string) (LumpTableSummary, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpTableSummary, error) {
		owner := plots.Projects.Sqlite
		var created string
		if err := withImmediateProjectWriteTx(ctx, owner, func(conn *sql.Conn) error {
			var err error
			created, err = createLumpTableInTx(ctx, conn, name)
			return err
		}); err != nil {
			return LumpTableSummary{}, err
		}
		base, _, _ := normalizeLumpBaseName(name)
		return LumpTableSummary{
			Name:            base,
			TableName:       created,
			DatabasePath:    owner.Selection.ProjectPath,
			IsActiveProject: true,
			MetadataVersion: LumpTableMetadataVersion,
		}, nil
	})
}

func SaveAsLumpTable(s *vprocore.ContextService, ctx context.Context, contextID, sourceTable, sourceDBPath, targetName string) (LumpTableSummary, error) {
	sourceRows, err := GetLumpTableRows(s, ctx, contextID, sourceTable, sourceDBPath)
	if err != nil {
		return LumpTableSummary{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpTableSummary, error) {
		owner := plots.Projects.Sqlite
		base, _, err := normalizeLumpBaseName(targetName)
		if err != nil {
			return LumpTableSummary{}, err
		}
		var created string
		activeCount := 0
		lumpSet := map[string]struct{}{}
		if err := withImmediateProjectWriteTx(ctx, owner, func(conn *sql.Conn) error {
			var createErr error
			created, createErr = createLumpTableInTx(ctx, conn, base)
			if createErr != nil {
				return createErr
			}
			quoted := vprocore.QuoteHeaderIdentifier(created)
			stmt, prepErr := conn.PrepareContext(ctx, `INSERT INTO `+quoted+` ("LumpCode", "SppCode", "Use") VALUES (?, ?, ?)`)
			if prepErr != nil {
				return prepErr
			}
			defer stmt.Close()
			for _, r := range sourceRows {
				lumpCode, sppCode, vErr := ValidateLumpCodes(r.LumpCode, r.SppCode)
				if vErr != nil {
					return vErr
				}
				if _, execErr := stmt.ExecContext(ctx, lumpCode, sppCode, accessBoolToInt(r.Use)); execErr != nil {
					return fmt.Errorf("copy %s -> %s: %w", sppCode, lumpCode, execErr)
				}
				lumpSet[lumpCode] = struct{}{}
				if r.Use {
					activeCount++
				}
			}
			return nil
		}); err != nil {
			return LumpTableSummary{}, err
		}
		return LumpTableSummary{
			Name:              base,
			TableName:         created,
			DatabasePath:      owner.Selection.ProjectPath,
			IsActiveProject:   true,
			MetadataVersion:   LumpTableMetadataVersion,
			RowCount:          len(sourceRows),
			ActiveCount:       activeCount,
			DistinctLumpCodes: len(lumpSet),
		}, nil
	})
}

func DeleteLumpTable(s *vprocore.ContextService, ctx context.Context, contextID, name string) error {
	_, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		_, tableName, err := normalizeLumpBaseName(name)
		if err != nil {
			return struct{}{}, err
		}
		return struct{}{}, withImmediateProjectWriteTx(ctx, owner, func(conn *sql.Conn) error {
			var actualName string
			if err := conn.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name COLLATE NOCASE=?`, tableName).Scan(&actualName); err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return fmt.Errorf("lump table %s was not found in the active project", tableName)
				}
				return err
			}
			if _, err := conn.ExecContext(ctx, `DROP TABLE `+vprocore.QuoteHeaderIdentifier(actualName)); err != nil {
				return err
			}
			var hasMeta bool
			if err := conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='_table_metadata')`).Scan(&hasMeta); err == nil && hasMeta {
				_, _ = conn.ExecContext(ctx, `DELETE FROM "_table_metadata" WHERE table_name COLLATE NOCASE=?`, actualName)
			}
			return nil
		})
	})
	return err
}
