package accessimport

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	_ "github.com/mattn/go-sqlite3"
)

var mensurationProjectPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{0,30}$`)

// MensurationSourceCandidate describes a discovered <Source>_TreePlot / <Source>_Trees
// table pair (or single table) inside an Access .accdb/.mdb database.
type MensurationSourceCandidate struct {
	SourceProject      string `json:"sourceProject"`
	TreePlotTable      string `json:"treePlotTable,omitempty"`
	TreesTable         string `json:"treesTable,omitempty"`
	HasTreePlot        bool   `json:"hasTreePlot"`
	HasTrees           bool   `json:"hasTrees"`
	HasEnvTable        bool   `json:"hasEnvTable"`
	StandaloneTreeOnly bool   `json:"standaloneTreeOnly"`
}

// ImportMensurationOptions configures auto-detected mensuration import from Access into SQLite.
type ImportMensurationOptions struct {
	SourceProject         string
	TargetProject         string
	CreateTablesIfMissing bool
	ReplaceExisting       bool
	RecordQuarantine      bool
}

// ImportMensurationResult summarizes an Access mensuration import operation.
type ImportMensurationResult struct {
	SourcePath            string `json:"sourcePath"`
	SourceProject         string `json:"sourceProject"`
	TargetProject         string `json:"targetProject"`
	StandaloneTreeOnly    bool   `json:"standaloneTreeOnly"`
	TreePlotSourceTable   string `json:"treePlotSourceTable,omitempty"`
	TreesSourceTable      string `json:"treesSourceTable,omitempty"`
	TreePlotTargetTable   string `json:"treePlotTargetTable,omitempty"`
	TreesTargetTable      string `json:"treesTargetTable,omitempty"`
	TreePlotRowsImported  int    `json:"treePlotRowsImported"`
	TreePlotMalformedRows int    `json:"treePlotMalformedRows"`
	TreesRowsImported     int    `json:"treesRowsImported"`
	TreesMalformedRows    int    `json:"treesMalformedRows"`
}

var treePlotUTF16Limits = map[string]int{
	"plotnumber":       7,
	"subplot":          30,
	"mensurationid":    255,
	"zone":             10,
	"subzone":          15,
	"fiz":              2,
	"treesurveyor":     30,
	"seralstage":       255,
	"fsregiondistrict": 7,
	"location":         255,
	"becsiteunit":      100,
	"siteseries":       5,
	"datasource":       255,
}

var treesUTF16Limits = map[string]int{
	"plotnumber":     7,
	"subplot":        30,
	"treespp":        3,
	"agenote":        255,
	"treeorigin":     1,
	"damagetype":     3,
	"damageseverity": 1,
	"crownclass":     1,
	"wildlifeuse":    17,
	"livedead":       255,
}

func quoteIdent(name string) string {
	return `"` + strings.ReplaceAll(name, `"`, `""`) + `"`
}

func hasRequiredColumnsCI(cols []accessreader.Column, required ...string) bool {
	seen := make(map[string]bool, len(cols))
	for _, c := range cols {
		seen[strings.ToLower(c.Name)] = true
	}
	for _, req := range required {
		if !seen[strings.ToLower(req)] {
			return false
		}
	}
	return true
}

// DiscoverMensurationTablesInFile opens an Access .accdb/.mdb file read-only and discovers
// all <Source>_TreePlot / <Source>_Trees table sets (both standalone tree-only files and
// full VPro+Mensuration project files).
func DiscoverMensurationTablesInFile(accessPath string) ([]MensurationSourceCandidate, error) {
	db, err := accessreader.Open(accessPath)
	if err != nil {
		return nil, err
	}
	return DiscoverMensurationTables(db)
}

// DiscoverMensurationTables inspects an opened Access DB for local <Source>_TreePlot and
// <Source>_Trees tables, validating their required identity columns.
func DiscoverMensurationTables(db *accessreader.DB) ([]MensurationSourceCandidate, error) {
	if db == nil {
		return nil, errors.New("Access database handle is required")
	}
	tables, err := db.Tables()
	if err != nil {
		return nil, err
	}

	envPrefixes := map[string]bool{}
	for _, tbl := range tables {
		if tbl.Linked || strings.HasPrefix(strings.ToUpper(tbl.Name), "USYS") {
			continue
		}
		upper := strings.ToUpper(tbl.Name)
		if len(tbl.Name) > 4 && strings.HasSuffix(upper, "_ENV") {
			envPrefixes[strings.ToLower(tbl.Name[:len(tbl.Name)-4])] = true
		}
	}

	byLowerPrefix := map[string]*MensurationSourceCandidate{}
	getOrCreate := func(prefix string) *MensurationSourceCandidate {
		key := strings.ToLower(prefix)
		if existing, ok := byLowerPrefix[key]; ok {
			return existing
		}
		hasEnv := envPrefixes[key]
		c := &MensurationSourceCandidate{
			SourceProject:      prefix,
			HasEnvTable:        hasEnv,
			StandaloneTreeOnly: !hasEnv,
		}
		byLowerPrefix[key] = c
		return c
	}

	for _, tbl := range tables {
		if tbl.Linked || strings.HasPrefix(strings.ToUpper(tbl.Name), "USYS") {
			continue
		}
		upper := strings.ToUpper(tbl.Name)
		switch {
		case len(tbl.Name) > len("_TreePlot") && strings.HasSuffix(upper, "_TREEPLOT"):
			prefix := tbl.Name[:len(tbl.Name)-len("_TreePlot")]
			r, scanErr := db.Scan(tbl.Name)
			if scanErr != nil {
				continue
			}
			ok := hasRequiredColumnsCI(r.Columns, "PlotNumber", "SubPlot", "MeasurementID")
			_ = r.Close()
			if ok {
				c := getOrCreate(prefix)
				c.TreePlotTable = tbl.Name
				c.HasTreePlot = true
			}
		case len(tbl.Name) > len("_Trees") && strings.HasSuffix(upper, "_TREES"):
			prefix := tbl.Name[:len(tbl.Name)-len("_Trees")]
			r, scanErr := db.Scan(tbl.Name)
			if scanErr != nil {
				continue
			}
			ok := hasRequiredColumnsCI(r.Columns, "PlotNumber")
			_ = r.Close()
			if ok {
				c := getOrCreate(prefix)
				c.TreesTable = tbl.Name
				c.HasTrees = true
			}
		}
	}

	result := make([]MensurationSourceCandidate, 0, len(byLowerPrefix))
	for _, c := range byLowerPrefix {
		result = append(result, *c)
	}
	slices.SortFunc(result, func(a, b MensurationSourceCandidate) int {
		return strings.Compare(strings.ToLower(a.SourceProject), strings.ToLower(b.SourceProject))
	})
	return result, nil
}

// MatchMensurationCandidate finds the mensuration candidate matching sourceProject (case-insensitively),
// or auto-selects the sole candidate when sourceProject is empty. Returns (nil, nil) if none exist.
func MatchMensurationCandidate(db *accessreader.DB, sourceProject string) (*MensurationSourceCandidate, error) {
	candidates, err := DiscoverMensurationTables(db)
	if err != nil {
		return nil, err
	}
	trimmed := strings.TrimSpace(sourceProject)
	if trimmed != "" {
		for i := range candidates {
			if strings.EqualFold(candidates[i].SourceProject, trimmed) {
				match := candidates[i]
				return &match, nil
			}
		}
		return nil, nil
	}
	switch len(candidates) {
	case 0:
		return nil, nil
	case 1:
		match := candidates[0]
		return &match, nil
	default:
		names := make([]string, len(candidates))
		for i, c := range candidates {
			names[i] = c.SourceProject
		}
		return nil, fmt.Errorf("multiple mensuration table sets found (%s); specify SourceProject explicitly", strings.Join(names, ", "))
	}
}

func createTreePlotDDL(project string) (string, []string) {
	tblName := project + "_TreePlot"
	tbl := quoteIdent(tblName)
	ddl := `CREATE TABLE IF NOT EXISTS ` + tbl + ` (
	"PlotNumber" TEXT NOT NULL,
	"SubPlot" TEXT NOT NULL,
	"MeasurementID" INTEGER NOT NULL,
	"MensurationID" TEXT,
	"Zone" TEXT,
	"SubZone" TEXT,
	"FIZ" TEXT,
	"TreeSurveyor" TEXT,
	"Date" TEXT,
	"CruisePlot" INTEGER NOT NULL DEFAULT 0,
	"CWDPlot" INTEGER NOT NULL DEFAULT 0,
	"WildlifePlot" INTEGER NOT NULL DEFAULT 0,
	"InformalPlot" INTEGER NOT NULL DEFAULT 0,
	"SiteIndexPlot" INTEGER NOT NULL DEFAULT 0,
	"BAF" REAL,
	"DBHLimit" REAL,
	"StandAge" INTEGER,
	"PlotSize" REAL,
	"SeralStage" TEXT,
	"FSRegionDistrict" TEXT,
	"Location" TEXT,
	"BECSiteUnit" TEXT,
	"StandAgeVPro" INTEGER,
	"SiteSeries" TEXT,
	"Comment" TEXT,
	"DataSource" TEXT,
	PRIMARY KEY ("PlotNumber", "SubPlot", "MeasurementID")
)`
	indexes := []string{
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_ID_idx") + ` ON ` + tbl + ` ("MensurationID")`,
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_MeasurementID_idx") + ` ON ` + tbl + ` ("MeasurementID")`,
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_PlotNumber_idx") + ` ON ` + tbl + ` ("PlotNumber")`,
	}
	return ddl, indexes
}

func createTreesDDL(project string) (string, []string) {
	tblName := project + "_Trees"
	tbl := quoteIdent(tblName)
	ddl := `CREATE TABLE IF NOT EXISTS ` + tbl + ` (
	"PlotNumber" TEXT NOT NULL,
	"SubPlot" TEXT,
	"MeasurementID" INTEGER,
	"TreeNum" INTEGER,
	"TreeSpp" TEXT,
	"DBH" REAL,
	"DBHClass" REAL,
	"TotalHtCalc" REAL,
	"HeightClass" REAL,
	"CountAge" INTEGER,
	"CountHT" REAL,
	"TotalAge" INTEGER,
	"AgeNote" TEXT,
	"TreeHealth" INTEGER,
	"TreeOrigin" TEXT,
	"Conks" INTEGER,
	"BlindConks" INTEGER,
	"Scars" INTEGER,
	"ForkOrCrook" INTEGER,
	"FrostCrack" INTEGER,
	"Mistletoe" INTEGER,
	"RottenBranch" INTEGER,
	"DeadOrBrokenTop" INTEGER,
	"DamageType" TEXT,
	"DamageSeverity" TEXT,
	"CrownClass" TEXT,
	"Ht2LiveCrown" REAL,
	"Appearance" INTEGER,
	"CrownCondition" INTEGER,
	"BarkRetention" INTEGER,
	"WoodCondition" INTEGER,
	"LichenLoading" INTEGER,
	"MossLoading" INTEGER,
	"WildLifeUse" TEXT,
	"TreeNotes" TEXT,
	"LiveDead" TEXT,
	"CuVolume" REAL,
	"SPH" REAL,
	"BasalArea" REAL,
	"SiteIndexID" INTEGER,
	"SiteIndex" REAL,
	"SiteIndex24" REAL,
	"SI50" REAL
)`
	indexes := []string{
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_MeasurementID_idx") + ` ON ` + tbl + ` ("MeasurementID")`,
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_PlotNumber_idx") + ` ON ` + tbl + ` ("PlotNumber")`,
		`CREATE INDEX IF NOT EXISTS ` + quoteIdent(tblName+"_TreeNum_idx") + ` ON ` + tbl + ` ("TreeNum")`,
	}
	return ddl, indexes
}

func ensureTargetMensurationTable(ctx context.Context, tx *sql.Tx, project, suffix string) error {
	var (
		ddl     string
		indexes []string
	)
	if suffix == "TreePlot" {
		ddl, indexes = createTreePlotDDL(project)
	} else {
		ddl, indexes = createTreesDDL(project)
	}
	if _, err := tx.ExecContext(ctx, ddl); err != nil {
		return err
	}
	for _, idxSQL := range indexes {
		if _, err := tx.ExecContext(ctx, idxSQL); err != nil {
			return err
		}
	}
	var hasMeta bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='_table_metadata')`).Scan(&hasMeta); err != nil {
		return err
	}
	if hasMeta {
		tblName := project + "_" + suffix
		var exists bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "_table_metadata" WHERE table_name=?)`, tblName).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			if _, err := tx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name","description") VALUES (?, 'VP08')`, tblName); err != nil {
				return err
			}
		}
	}
	return nil
}

func queryTargetColumns(ctx context.Context, tx *sql.Tx, tableName string) (map[string]string, error) {
	rows, err := tx.QueryContext(ctx, `PRAGMA table_info(`+quoteIdent(tableName)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]string{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, colType string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[strings.ToLower(name)] = name
	}
	return cols, rows.Err()
}

type mensurationRowSource interface {
	ColumnsList() []accessreader.Column
	EnableRowQuarantine()
	Next() bool
	Row() accessreader.Row
	Err() error
	QuarantinedRows() []accessreader.QuarantinedRow
	Close() error
}

type readerSourceAdapter struct {
	*accessreader.Reader
}

func (a readerSourceAdapter) ColumnsList() []accessreader.Column { return a.Reader.Columns }
func (a readerSourceAdapter) QuarantinedRows() []accessreader.QuarantinedRow {
	return a.Reader.Quarantined
}

func streamMensurationSourceIntoSQLite(
	ctx context.Context,
	source mensurationRowSource,
	tx *sql.Tx,
	quarantineStmt *sql.Stmt,
	sourceTable, targetTable string,
	utf16Limits map[string]int,
) (imported int, malformed int, err error) {
	if err := ctx.Err(); err != nil {
		return 0, 0, err
	}
	source.EnableRowQuarantine()
	cols := source.ColumnsList()
	srcCols := make([]SourceColumn, len(cols))
	for i, c := range cols {
		srcCols[i] = SourceColumn{Name: c.Name, Type: c.Type}
	}
	colPlan, err := PlanColumns(ctx, srcCols)
	if err != nil {
		return 0, 0, err
	}
	dstCols, err := queryTargetColumns(ctx, tx, targetTable)
	if err != nil {
		return 0, 0, err
	}

	var (
		targetQuoted   []string
		targetNames    []string
		targetLimits   []int
		sourceIndices  []int
		plotColIdx     = -1
		boolColIndices = map[int]bool{}
	)
	for i, c := range cols {
		low := strings.ToLower(c.Name)
		canonical, ok := dstCols[low]
		if !ok {
			continue
		}
		if low == "plotnumber" {
			plotColIdx = len(sourceIndices)
		}
		if colPlan[i].SourceType == "boolean" {
			boolColIndices[len(sourceIndices)] = true
		}
		targetQuoted = append(targetQuoted, quoteIdent(canonical))
		targetNames = append(targetNames, canonical)
		targetLimits = append(targetLimits, utf16Limits[low])
		sourceIndices = append(sourceIndices, i)
	}
	if len(sourceIndices) == 0 {
		return 0, 0, fmt.Errorf("source table %s shares no columns with target table %s", sourceTable, targetTable)
	}

	marks := make([]string, len(targetQuoted))
	for i := range marks {
		marks[i] = "?"
	}
	stmt, err := tx.PrepareContext(ctx,
		`INSERT INTO `+quoteIdent(targetTable)+` (`+strings.Join(targetQuoted, ", ")+`) VALUES (`+strings.Join(marks, ", ")+`)`,
	)
	if err != nil {
		return 0, 0, fmt.Errorf("prepare insert into %s: %w", targetTable, err)
	}
	defer stmt.Close()

	adapted := make([]any, len(colPlan))
	argsBuf := make([]any, len(sourceIndices))
	rowOrdinal := 0

	recordQuarantine := func(rowNum int, plotKey, reason string, raw any) {
		if quarantineStmt == nil {
			return
		}
		payload := "{}"
		if raw != nil {
			if b, jErr := json.Marshal(raw); jErr == nil {
				payload = string(b)
			}
		}
		_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowNum, plotKey, reason, payload)
	}

	for source.Next() {
		rowOrdinal++
		if rowOrdinal&1023 == 0 {
			if err := ctx.Err(); err != nil {
				return imported, malformed, err
			}
		}
		rawRow := source.Row()
		if len(rawRow) != len(colPlan) {
			malformed++
			recordQuarantine(rowOrdinal, "", fmt.Sprintf("column_count_mismatch: got %d want %d", len(rawRow), len(colPlan)), rawRow)
			continue
		}
		var adaptErr error
		for i, cell := range rawRow {
			adapted[i], adaptErr = SQLiteValue(cell)
			if adaptErr != nil {
				break
			}
		}
		if adaptErr != nil {
			malformed++
			recordQuarantine(rowOrdinal, "", "malformed_value: "+adaptErr.Error(), nil)
			continue
		}

		var violation string
		for i, srcIdx := range sourceIndices {
			v := adapted[srcIdx]
			if boolColIndices[i] && v == nil {
				v = int64(0)
			}
			argsBuf[i] = v
			if limit := targetLimits[i]; limit > 0 {
				if s, ok := v.(string); ok {
					if !utf8.ValidString(s) || strings.ContainsRune(s, 0) || sqlutil.UTF16Len(s) > limit {
						violation = fmt.Sprintf("%s.%s exceeds %d UTF-16 code units or has invalid UTF-8", targetTable, targetNames[i], limit)
						break
					}
				}
			}
		}
		plotKey := ""
		if plotColIdx >= 0 {
			if s, ok := argsBuf[plotColIdx].(string); ok {
				plotKey = s
			}
		}
		if violation != "" {
			malformed++
			recordQuarantine(rowOrdinal, plotKey, "utf16_length_bound: "+violation, adapted)
			continue
		}
		if plotColIdx >= 0 && strings.TrimSpace(plotKey) == "" {
			malformed++
			recordQuarantine(rowOrdinal, plotKey, "missing_plot_number", adapted)
			continue
		}

		if _, execErr := stmt.ExecContext(ctx, argsBuf...); execErr != nil {
			malformed++
			recordQuarantine(rowOrdinal, plotKey, "sqlite_insert_constraint: "+execErr.Error(), adapted)
			continue
		}
		imported++
	}
	if err := source.Err(); err != nil {
		return imported, malformed, fmt.Errorf("read Access table %s: %w", sourceTable, err)
	}
	for _, q := range source.QuarantinedRows() {
		malformed++
		recordQuarantine(q.RowNumber, "", "access_decode: "+q.Reason, nil)
	}
	return imported, malformed, nil
}

// ImportMensurationIntoTx auto-detects and imports <Source>_TreePlot and/or <Source>_Trees
// from db into an existing SQLite transaction tx. If no mensuration tables match, it is a
// no-op and returns a zero-row result with nil error.
func ImportMensurationIntoTx(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	opts ImportMensurationOptions,
) (ImportMensurationResult, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return ImportMensurationResult{}, err
	}
	if db == nil {
		return ImportMensurationResult{}, errors.New("Access database handle is required")
	}
	if tx == nil {
		return ImportMensurationResult{}, errors.New("SQLite transaction is required")
	}
	targetProject := strings.TrimSpace(opts.TargetProject)
	if !mensurationProjectPattern.MatchString(targetProject) {
		return ImportMensurationResult{}, fmt.Errorf("invalid target project name %q", opts.TargetProject)
	}

	candidate, err := MatchMensurationCandidate(db, opts.SourceProject)
	if err != nil {
		return ImportMensurationResult{}, err
	}
	if candidate == nil {
		return ImportMensurationResult{TargetProject: targetProject}, nil
	}

	res := ImportMensurationResult{
		SourceProject:      candidate.SourceProject,
		TargetProject:      targetProject,
		StandaloneTreeOnly: candidate.StandaloneTreeOnly,
	}

	var quarantineStmt *sql.Stmt
	if opts.RecordQuarantine {
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_Quarantine" (
			"ID" INTEGER PRIMARY KEY AUTOINCREMENT,
			"SourceTable" TEXT NOT NULL,
			"RowOrdinal" INTEGER NOT NULL,
			"PlotNumber" TEXT,
			"Reason" TEXT NOT NULL,
			"RawJSON" TEXT NOT NULL
		)`); err != nil {
			return res, fmt.Errorf("ensure quarantine table: %w", err)
		}
		quarantineStmt, err = tx.PrepareContext(ctx,
			`INSERT INTO "__VPRO_Quarantine" ("SourceTable","RowOrdinal","PlotNumber","Reason","RawJSON") VALUES (?,?,?,?,?)`)
		if err != nil {
			return res, err
		}
		defer quarantineStmt.Close()
	}

	if candidate.HasTreePlot {
		res.TreePlotSourceTable = candidate.TreePlotTable
		res.TreePlotTargetTable = targetProject + "_TreePlot"
		if opts.CreateTablesIfMissing {
			if err := ensureTargetMensurationTable(ctx, tx, targetProject, "TreePlot"); err != nil {
				return res, err
			}
		}
		if opts.ReplaceExisting {
			if _, err := tx.ExecContext(ctx, `DELETE FROM `+quoteIdent(res.TreePlotTargetTable)); err != nil {
				return res, err
			}
		}
		reader, err := db.Scan(candidate.TreePlotTable)
		if err != nil {
			return res, fmt.Errorf("open %s: %w", candidate.TreePlotTable, err)
		}
		imported, malformed, streamErr := streamMensurationSourceIntoSQLite(
			ctx, readerSourceAdapter{reader}, tx, quarantineStmt,
			candidate.TreePlotTable, res.TreePlotTargetTable, treePlotUTF16Limits,
		)
		closeErr := reader.Close()
		if streamErr != nil {
			return res, errors.Join(streamErr, closeErr)
		}
		if closeErr != nil {
			return res, closeErr
		}
		res.TreePlotRowsImported = imported
		res.TreePlotMalformedRows = malformed
	}

	if candidate.HasTrees {
		res.TreesSourceTable = candidate.TreesTable
		res.TreesTargetTable = targetProject + "_Trees"
		if opts.CreateTablesIfMissing {
			if err := ensureTargetMensurationTable(ctx, tx, targetProject, "Trees"); err != nil {
				return res, err
			}
		}
		if opts.ReplaceExisting {
			if _, err := tx.ExecContext(ctx, `DELETE FROM `+quoteIdent(res.TreesTargetTable)); err != nil {
				return res, err
			}
		}
		reader, err := db.Scan(candidate.TreesTable)
		if err != nil {
			return res, fmt.Errorf("open %s: %w", candidate.TreesTable, err)
		}
		imported, malformed, streamErr := streamMensurationSourceIntoSQLite(
			ctx, readerSourceAdapter{reader}, tx, quarantineStmt,
			candidate.TreesTable, res.TreesTargetTable, treesUTF16Limits,
		)
		closeErr := reader.Close()
		if streamErr != nil {
			return res, errors.Join(streamErr, closeErr)
		}
		if closeErr != nil {
			return res, closeErr
		}
		res.TreesRowsImported = imported
		res.TreesMalformedRows = malformed
	}

	return res, nil
}

// ImportMensurationFromAccess opens an Access .accdb/.mdb file and atomically imports any
// auto-detected <Source>_TreePlot and <Source>_Trees tables into sqliteProjectPath under
// a single BEGIN IMMEDIATE WAL transaction.
func ImportMensurationFromAccess(
	ctx context.Context,
	accessPath, sqliteProjectPath string,
	opts ImportMensurationOptions,
) (ImportMensurationResult, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return ImportMensurationResult{}, err
	}
	accessDB, err := accessreader.Open(accessPath)
	if err != nil {
		return ImportMensurationResult{}, err
	}
	sqliteDB, err := sqlutil.OpenWALCreateSQLite(sqliteProjectPath)
	if err != nil {
		return ImportMensurationResult{}, err
	}
	defer sqliteDB.Close()

	conn, err := sqliteDB.Conn(ctx)
	if err != nil {
		return ImportMensurationResult{}, err
	}
	defer conn.Close()

	tx, err := conn.BeginTx(context.WithoutCancel(ctx), nil)
	if err != nil {
		return ImportMensurationResult{}, err
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	res, err := ImportMensurationIntoTx(ctx, accessDB, tx, opts)
	if err != nil {
		return res, err
	}
	res.SourcePath = accessPath
	if err := ctx.Err(); err != nil {
		return res, err
	}
	if err := tx.Commit(); err != nil {
		return res, err
	}
	committed = true
	return res, nil
}
