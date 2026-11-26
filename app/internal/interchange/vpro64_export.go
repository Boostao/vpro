package interchange

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// VPro64ExportRequest configures a clean SQLite export targeting VPro64's
// VBA SQLite-ODBC importer (V7mdlImportSQLite.bas).
type VPro64ExportRequest struct {
	DestinationPath    string   `json:"destinationPath"`
	TargetProjectName  string   `json:"targetProjectName,omitempty"`
	IncludeActiveSU    bool     `json:"includeActiveSU"`
	IncludeHierarchy   bool     `json:"includeHierarchy"`
	IncludeMensuration bool     `json:"includeMensuration"`
	IncludeCompanions  bool     `json:"includeCompanions"`
	PlotNumbers        []string `json:"plotNumbers,omitempty"`
}

func (r *VPro64ExportRequest) UnmarshalJSON(data []byte) error {
	type plain VPro64ExportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type VPro64ExportTableSummary struct {
	SourceTable string `json:"sourceTable"`
	TargetTable string `json:"targetTable"`
	RowCount    int    `json:"rowCount"`
}

type VPro64ExportOutcome struct {
	SourceProject       string                     `json:"sourceProject"`
	TargetProject       string                     `json:"targetProject"`
	DestinationPath     string                     `json:"destinationPath"`
	SHA256              string                     `json:"sha256"`
	Bytes               int64                      `json:"bytes"`
	JournalMode         string                     `json:"journalMode"`
	PlotCount           int                        `json:"plotCount"`
	IncludedSU          string                     `json:"includedSU,omitempty"`
	IncludedHierarchy   string                     `json:"includedHierarchy,omitempty"`
	IncludedMensuration bool                       `json:"includedMensuration"`
	Tables              []VPro64ExportTableSummary `json:"tables"`
}

type vpro64TableSpec struct {
	role          string
	sourceTable   string
	targetTable   string
	plotKeyColumn string // "PlotNumber", "Plot", or ""
	metadataDesc  string
}

var knownAccessBoolColumns = map[string]bool{
	"flag":          true,
	"use":           true,
	"cruiseplot":    true,
	"cwdplot":       true,
	"wildlifeplot":  true,
	"informalplot":  true,
	"siteindexplot": true,
	"ismaster":      true,
	"verified":      true,
	"locked":        true,
	"deleteflag":    true,
	"active":        true,
	"restore":       true,
}

func isAccessBooleanColumn(name, declaredType string) bool {
	upperType := strings.ToUpper(strings.TrimSpace(declaredType))
	if strings.Contains(upperType, "BOOL") || upperType == "BIT" || strings.HasPrefix(upperType, "BIT(") {
		return true
	}
	return knownAccessBoolColumns[strings.ToLower(strings.TrimSpace(name))]
}

func normalizeAccessBooleanValue(raw any) any {
	if raw == nil {
		return nil
	}
	switch v := raw.(type) {
	case bool:
		if v {
			return int64(-1)
		}
		return int64(0)
	case int64:
		if v != 0 {
			return int64(-1)
		}
		return int64(0)
	case int:
		if v != 0 {
			return int64(-1)
		}
		return int64(0)
	case float64:
		if v != 0 {
			return int64(-1)
		}
		return int64(0)
	case []byte:
		return normalizeAccessBooleanString(string(v))
	case string:
		return normalizeAccessBooleanString(v)
	default:
		return raw
	}
}

func normalizeAccessBooleanString(s string) any {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "true", "yes", "t", "y", "1", "-1":
		return int64(-1)
	case "false", "no", "f", "n", "0", "":
		return int64(0)
	default:
		if n, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64); err == nil {
			if n != 0 {
				return int64(-1)
			}
			return int64(0)
		}
		return s
	}
}

func rewriteCreateTableSQL(rawSQL, sourceTable, targetTable string) string {
	if sourceTable == targetTable {
		return rawSQL
	}
	quotedSrc := vprocore.QuoteHeaderIdentifier(sourceTable)
	quotedDst := vprocore.QuoteHeaderIdentifier(targetTable)
	for _, prefix := range []string{
		"CREATE TABLE " + quotedSrc,
		"CREATE TABLE [" + sourceTable + "]",
		"CREATE TABLE `" + sourceTable + "`",
		"CREATE TABLE " + sourceTable,
	} {
		if strings.HasPrefix(rawSQL, prefix) {
			return "CREATE TABLE " + quotedDst + rawSQL[len(prefix):]
		}
	}
	return strings.Replace(rawSQL, sourceTable, targetTable, 1)
}

func rewriteCreateIndexSQL(rawSQL, sourceIdx, targetIdx, sourceTable, targetTable string) string {
	if sourceTable == targetTable && sourceIdx == targetIdx {
		return rawSQL
	}
	out := rawSQL
	// Replace index name first, then ON table reference.
	for _, oldIdx := range []string{
		vprocore.QuoteHeaderIdentifier(sourceIdx),
		"[" + sourceIdx + "]",
		"`" + sourceIdx + "`",
		sourceIdx,
	} {
		if idx := strings.Index(out, oldIdx); idx >= 0 {
			out = out[:idx] + vprocore.QuoteHeaderIdentifier(targetIdx) + out[idx+len(oldIdx):]
			break
		}
	}
	for _, oldTbl := range []string{
		" ON " + vprocore.QuoteHeaderIdentifier(sourceTable),
		" ON [" + sourceTable + "]",
		" ON `" + sourceTable + "`",
		" ON " + sourceTable,
	} {
		if idx := strings.Index(out, oldTbl); idx >= 0 {
			out = out[:idx] + " ON " + vprocore.QuoteHeaderIdentifier(targetTable) + out[idx+len(oldTbl):]
			break
		}
	}
	return out
}

func vpro64HasTable(ctx context.Context, tx *sql.Tx, role, table string) (bool, error) {
	var count int
	err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(role)+`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
		table,
	).Scan(&count)
	return count == 1, err
}

func vpro64ReadTableMetaDesc(ctx context.Context, tx *sql.Tx, role, table string) string {
	hasMeta, err := vpro64HasTable(ctx, tx, role, "_table_metadata")
	if err != nil || !hasMeta {
		return ""
	}
	var desc sql.NullString
	if err := tx.QueryRowContext(ctx,
		`SELECT description FROM `+vprocore.QuoteHeaderIdentifier(role)+`."_table_metadata" WHERE table_name = ?`,
		table,
	).Scan(&desc); err == nil && desc.Valid {
		return strings.TrimSpace(desc.String)
	}
	return ""
}

// ExportVPro64Database exports the active project (plus optional active SU,
// Hierarchy, Mensuration _TreePlot/_Trees, and companion tables) into a clean,
// un-WAL'd journal_mode=DELETE + VACUUM SQLite .db file with Access -1/0 booleans
// and zero -wal/-shm sidecars, ready for VPro64's VBA SQLite-ODBC importer.
func ExportVPro64Database(s *vprocore.ContextService, ctx context.Context, contextID string, req VPro64ExportRequest) (_ VPro64ExportOutcome, resultErr error) {
	if ctx == nil {
		return VPro64ExportOutcome{}, errors.New("VPro64 export requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return VPro64ExportOutcome{}, err
	}
	if s == nil {
		return VPro64ExportOutcome{}, errors.New("VPro64 export context service is unavailable")
	}

	destPath := strings.TrimSpace(req.DestinationPath)
	if destPath == "" || !utf8.ValidString(destPath) || strings.ContainsRune(destPath, 0) {
		return VPro64ExportOutcome{}, errors.New("VPro64 export requires an explicit destination .db path")
	}
	if !strings.EqualFold(filepath.Ext(destPath), ".db") {
		destPath += ".db"
	}
	resolvedDest, err := filepath.Abs(destPath)
	if err != nil {
		return VPro64ExportOutcome{}, fmt.Errorf("resolve VPro64 export destination: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(resolvedDest), 0o700); err != nil {
		return VPro64ExportOutcome{}, fmt.Errorf("prepare VPro64 export directory: %w", err)
	}

	var plotFilter map[string]bool
	if len(req.PlotNumbers) > 0 {
		plotFilter = make(map[string]bool, len(req.PlotNumbers))
		for _, p := range req.PlotNumbers {
			if p != "" {
				plotFilter[p] = true
			}
		}
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (VPro64ExportOutcome, error) {
		owner := plots.Projects.Sqlite
		srcProject := owner.Selection.Project
		targetProject := strings.TrimSpace(req.TargetProjectName)
		if targetProject == "" {
			targetProject = srcProject
		}
		if !vprocore.ProjectNamePattern.MatchString(targetProject) || strings.EqualFold(targetProject, "None") {
			return VPro64ExportOutcome{}, fmt.Errorf("target project name %q must be a valid VPro project identifier", targetProject)
		}

		// Prevent overwriting the currently active project/SU/hierarchy file in place.
		for _, activePath := range []string{owner.Selection.ProjectPath, owner.Selection.SUPath, owner.Selection.HierarchyPath} {
			if activePath != "" && vprocore.SameDesktopPath(activePath, resolvedDest) {
				return VPro64ExportOutcome{}, errors.New("VPro64 export destination cannot overwrite a currently active database file")
			}
		}

		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return VPro64ExportOutcome{}, err
		}
		defer unlock()

		srcTx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return VPro64ExportOutcome{}, err
		}
		defer srcTx.Rollback()

		// Build ordered table export plan.
		specs := make([]vpro64TableSpec, 0, 16)
		seenTargets := map[string]bool{}
		addSpec := func(sp vpro64TableSpec) {
			key := strings.ToLower(sp.targetTable)
			if seenTargets[key] {
				return
			}
			seenTargets[key] = true
			specs = append(specs, sp)
		}

		// 1. All 8 Core VP08 tables.
		for _, suffix := range vprocore.CoreTables {
			srcTbl := srcProject + "_" + suffix
			ok, err := vpro64HasTable(ctx, srcTx, "project", srcTbl)
			if err != nil {
				return VPro64ExportOutcome{}, err
			}
			if !ok {
				return VPro64ExportOutcome{}, fmt.Errorf("active project is missing required VP08 table %s", srcTbl)
			}
			plotKey := ""
			switch suffix {
			case "Env", "Veg", "Humus", "Mineral", "Other", "Audit":
				plotKey = "PlotNumber"
			case "Admin":
				plotKey = "Plot"
			}
			addSpec(vpro64TableSpec{
				role:          "project",
				sourceTable:   srcTbl,
				targetTable:   targetProject + "_" + suffix,
				plotKeyColumn: plotKey,
				metadataDesc:  "VP08",
			})
		}

		// 2. Optional Mensuration tables (_TreePlot & _Trees).
		includedMensuration := false
		if req.IncludeMensuration || req.IncludeCompanions {
			for _, suffix := range []string{"TreePlot", "Trees"} {
				srcTbl := srcProject + "_" + suffix
				ok, err := vpro64HasTable(ctx, srcTx, "project", srcTbl)
				if err != nil {
					return VPro64ExportOutcome{}, err
				}
				if ok {
					includedMensuration = true
					desc := vpro64ReadTableMetaDesc(ctx, srcTx, "project", srcTbl)
					if desc == "" {
						desc = "VP08"
					}
					addSpec(vpro64TableSpec{
						role:          "project",
						sourceTable:   srcTbl,
						targetTable:   targetProject + "_" + suffix,
						plotKeyColumn: "PlotNumber",
						metadataDesc:  desc,
					})
				}
			}
		}

		// 3. Optional Active SU.
		includedSU := ""
		if req.IncludeActiveSU && owner.Selection.SU != "" && owner.Selection.SU != "None" {
			suTable := owner.Selection.SU + "_SU"
			if _, ok := owner.Attachments["su"]; ok {
				exists, err := vpro64HasTable(ctx, srcTx, "su", suTable)
				if err != nil {
					return VPro64ExportOutcome{}, err
				}
				if exists {
					desc := vpro64ReadTableMetaDesc(ctx, srcTx, "su", suTable)
					if desc == "" {
						desc = "VP04"
					}
					addSpec(vpro64TableSpec{
						role:          "su",
						sourceTable:   suTable,
						targetTable:   suTable,
						plotKeyColumn: "PlotNumber",
						metadataDesc:  desc,
					})
					includedSU = owner.Selection.SU
				}
			}
		}

		// 4. Optional Active Hierarchy.
		includedHierarchy := ""
		if req.IncludeHierarchy && owner.Selection.Hierarchy != "" && owner.Selection.Hierarchy != "None" {
			hierTable := owner.Selection.Hierarchy + "_Hierarchy"
			if _, ok := owner.Attachments["hierarchy"]; ok {
				exists, err := vpro64HasTable(ctx, srcTx, "hierarchy", hierTable)
				if err != nil {
					return VPro64ExportOutcome{}, err
				}
				if exists {
					desc := vpro64ReadTableMetaDesc(ctx, srcTx, "hierarchy", hierTable)
					if desc == "" {
						desc = "VP04"
					}
					addSpec(vpro64TableSpec{
						role:         "hierarchy",
						sourceTable:  hierTable,
						targetTable:  hierTable,
						metadataDesc: desc,
					})
					includedHierarchy = owner.Selection.Hierarchy
				}
			}
		}

		// 5. Optional Companion tables inside the active project DB (*_Lump, *_Profile, *_Theme, *_Herbarium).
		if req.IncludeCompanions {
			rows, err := srcTx.QueryContext(ctx, `SELECT name FROM "project".sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__VPRO_%' ORDER BY name`)
			if err != nil {
				return VPro64ExportOutcome{}, err
			}
			var candidates []string
			for rows.Next() {
				var name string
				if err := rows.Scan(&name); err != nil {
					rows.Close()
					return VPro64ExportOutcome{}, err
				}
				for _, suf := range []string{"_Lump", "_Profile", "_Theme", "_Herbarium"} {
					if strings.HasSuffix(name, suf) {
						candidates = append(candidates, name)
						break
					}
				}
			}
			if err := rows.Err(); err != nil {
				rows.Close()
				return VPro64ExportOutcome{}, err
			}
			rows.Close()
			slices.Sort(candidates)
			for _, tbl := range candidates {
				desc := vpro64ReadTableMetaDesc(ctx, srcTx, "project", tbl)
				addSpec(vpro64TableSpec{
					role:         "project",
					sourceTable:  tbl,
					targetTable:  tbl,
					metadataDesc: desc,
				})
			}
		}

		// Stage clean un-WAL'd SQLite database file in the target directory.
		tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro64-export-*.db")
		if err != nil {
			return VPro64ExportOutcome{}, fmt.Errorf("create staged VPro64 export file: %w", err)
		}
		tmpPath := tmpFile.Name()
		published := false
		defer func() {
			if !published {
				_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
			}
		}()
		if err := tmpFile.Chmod(0o600); err != nil {
			_ = tmpFile.Close()
			return VPro64ExportOutcome{}, err
		}
		if err := tmpFile.Close(); err != nil {
			return VPro64ExportOutcome{}, err
		}

		dstDB, err := sqlutil.OpenSQLiteMode(tmpPath, "rwc")
		if err != nil {
			return VPro64ExportOutcome{}, fmt.Errorf("open staged VPro64 SQLite file: %w", err)
		}
		dstDB.SetMaxOpenConns(1)

		var (
			tableSummaries []VPro64ExportTableSummary
			plotCount      int
			journalMode    string
		)
		buildErr := func() error {
			if _, err := dstDB.ExecContext(ctx, "PRAGMA journal_mode = DELETE;"); err != nil {
				return err
			}
			if _, err := dstDB.ExecContext(ctx, "PRAGMA foreign_keys = OFF;"); err != nil {
				return err
			}
			dstTx, err := dstDB.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			if _, err := dstTx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
				_ = dstTx.Rollback()
				return err
			}

			for _, sp := range specs {
				if err := ctx.Err(); err != nil {
					_ = dstTx.Rollback()
					return err
				}
				copied, err := copyTableForVPro64(ctx, srcTx, dstTx, sp, plotFilter)
				if err != nil {
					_ = dstTx.Rollback()
					return fmt.Errorf("export table %s -> %s: %w", sp.sourceTable, sp.targetTable, err)
				}
				if sp.metadataDesc != "" {
					if _, err := dstTx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, sp.targetTable, sp.metadataDesc); err != nil {
						_ = dstTx.Rollback()
						return err
					}
				}
				if sp.targetTable == targetProject+"_Env" {
					plotCount = copied
				}
				tableSummaries = append(tableSummaries, VPro64ExportTableSummary{
					SourceTable: sp.sourceTable,
					TargetTable: sp.targetTable,
					RowCount:    copied,
				})
			}

			if err := dstTx.Commit(); err != nil {
				return err
			}
			// Enforce clean un-WAL'd journal_mode=DELETE + VACUUM + integrity check.
			if err := dstDB.QueryRowContext(ctx, "PRAGMA journal_mode = DELETE;").Scan(&journalMode); err != nil {
				return err
			}
			if !strings.EqualFold(journalMode, "delete") {
				return fmt.Errorf("expected journal_mode=delete on VPro64 export, got %q", journalMode)
			}
			if _, err := dstDB.ExecContext(ctx, "VACUUM;"); err != nil {
				return fmt.Errorf("VACUUM VPro64 export: %w", err)
			}
			var integrity string
			if err := dstDB.QueryRowContext(ctx, "PRAGMA integrity_check;").Scan(&integrity); err != nil {
				return err
			}
			if !strings.EqualFold(integrity, "ok") {
				return fmt.Errorf("VPro64 export integrity check failed: %s", integrity)
			}
			return nil
		}()

		closeErr := dstDB.Close()
		if err := errors.Join(buildErr, closeErr); err != nil {
			return VPro64ExportOutcome{}, err
		}

		// Commit read snapshot on source DB.
		if err := srcTx.Commit(); err != nil {
			return VPro64ExportOutcome{}, err
		}

		// Verify zero WAL/SHM sidecars exist on staged output.
		for _, suffix := range []string{"-wal", "-shm", "-journal"} {
			if _, statErr := os.Stat(tmpPath + suffix); statErr == nil {
				_ = os.Remove(tmpPath + suffix)
			}
		}

		// Compute SHA-256 and byte length before atomic rename.
		shaHex, sizeBytes, err := fileSHA256AndSize(tmpPath)
		if err != nil {
			return VPro64ExportOutcome{}, err
		}

		// Remove any stale sidecars at destination before/after replacing.
		for _, suffix := range []string{"-wal", "-shm", "-journal"} {
			_ = os.Remove(resolvedDest + suffix)
		}
		if err := os.Rename(tmpPath, resolvedDest); err != nil {
			return VPro64ExportOutcome{}, fmt.Errorf("publish VPro64 export %q: %w", resolvedDest, err)
		}
		published = true

		return VPro64ExportOutcome{
			SourceProject:       srcProject,
			TargetProject:       targetProject,
			DestinationPath:     resolvedDest,
			SHA256:              shaHex,
			Bytes:               sizeBytes,
			JournalMode:         strings.ToLower(journalMode),
			PlotCount:           plotCount,
			IncludedSU:          includedSU,
			IncludedHierarchy:   includedHierarchy,
			IncludedMensuration: includedMensuration,
			Tables:              tableSummaries,
		}, nil
	})
}

func copyTableForVPro64(ctx context.Context, srcTx, dstTx *sql.Tx, sp vpro64TableSpec, plotFilter map[string]bool) (int, error) {
	objects, err := vprocore.ReadSQLiteSchemaObjects(ctx, srcTx, sp.role, sp.sourceTable)
	if err != nil {
		return 0, err
	}
	var tableSQL string
	var indexObjs []vprocore.SqliteSchemaObject
	for _, obj := range objects {
		switch obj.Type {
		case "table":
			if obj.SQL != nil {
				tableSQL = rewriteCreateTableSQL(*obj.SQL, sp.sourceTable, sp.targetTable)
			}
		case "index":
			if obj.SQL != nil && strings.TrimSpace(*obj.SQL) != "" {
				indexObjs = append(indexObjs, obj)
			}
		}
	}
	if tableSQL == "" {
		return 0, fmt.Errorf("missing CREATE TABLE DDL for %s.%s", sp.role, sp.sourceTable)
	}
	if _, err := dstTx.ExecContext(ctx, tableSQL); err != nil {
		return 0, fmt.Errorf("execute DDL: %w", err)
	}

	// Inspect columns to detect boolean columns and plot key column index.
	colRows, err := srcTx.QueryContext(ctx, `PRAGMA `+vprocore.QuoteHeaderIdentifier(sp.role)+`.table_info(`+vprocore.QuoteHeaderIdentifier(sp.sourceTable)+`)`)
	if err != nil {
		return 0, err
	}
	type colMeta struct {
		name   string
		isBool bool
	}
	var cols []colMeta
	plotColIdx := -1
	for colRows.Next() {
		var cid, notNull, pk int
		var name, declType string
		var dflt sql.NullString
		if err := colRows.Scan(&cid, &name, &declType, &notNull, &dflt, &pk); err != nil {
			colRows.Close()
			return 0, err
		}
		if sp.plotKeyColumn != "" && strings.EqualFold(name, sp.plotKeyColumn) {
			plotColIdx = len(cols)
		}
		cols = append(cols, colMeta{
			name:   name,
			isBool: isAccessBooleanColumn(name, declType),
		})
	}
	if err := colRows.Err(); err != nil {
		colRows.Close()
		return 0, err
	}
	colRows.Close()

	if len(cols) == 0 {
		return 0, nil
	}

	colNames := make([]string, len(cols))
	placeholders := make([]string, len(cols))
	for i, c := range cols {
		colNames[i] = vprocore.QuoteHeaderIdentifier(c.name)
		placeholders[i] = "?"
	}
	colList := strings.Join(colNames, ", ")
	selectSQL := `SELECT ` + colList + ` FROM ` + vprocore.QuoteHeaderIdentifier(sp.role) + `.` + vprocore.QuoteHeaderIdentifier(sp.sourceTable)
	insertSQL := `INSERT INTO ` + vprocore.QuoteHeaderIdentifier(sp.targetTable) + ` (` + colList + `) VALUES (` + strings.Join(placeholders, ", ") + `)`

	stmt, err := dstTx.PrepareContext(ctx, insertSQL)
	if err != nil {
		return 0, err
	}
	defer stmt.Close()

	rows, err := srcTx.QueryContext(ctx, selectSQL)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	scanDest := make([]any, len(cols))
	rawVals := make([]any, len(cols))
	for i := range cols {
		scanDest[i] = &rawVals[i]
	}

	copied := 0
	for rows.Next() {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		if err := rows.Scan(scanDest...); err != nil {
			return 0, err
		}
		if len(plotFilter) > 0 && plotColIdx >= 0 {
			var plotKey string
			switch v := rawVals[plotColIdx].(type) {
			case string:
				plotKey = v
			case []byte:
				plotKey = string(v)
			}
			if !plotFilter[plotKey] {
				continue
			}
		}
		args := make([]any, len(cols))
		for i, c := range cols {
			val := rawVals[i]
			if c.isBool {
				val = normalizeAccessBooleanValue(val)
			}
			args[i] = val
		}
		if _, err := stmt.ExecContext(ctx, args...); err != nil {
			return 0, err
		}
		copied++
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}

	for _, idx := range indexObjs {
		targetIdxName := idx.Name
		if sp.sourceTable != sp.targetTable {
			targetIdxName = sp.targetTable + "__" + idx.Name
		}
		idxSQL := rewriteCreateIndexSQL(*idx.SQL, idx.Name, targetIdxName, sp.sourceTable, sp.targetTable)
		if _, err := dstTx.ExecContext(ctx, idxSQL); err != nil {
			return 0, fmt.Errorf("create index %s: %w", targetIdxName, err)
		}
	}
	return copied, nil
}

func fileSHA256AndSize(path string) (string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}
