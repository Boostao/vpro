package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/cloudsync"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	_ "github.com/mattn/go-sqlite3"
)

// EnvCoordColumns lists the six VP08 _Env coordinate columns subject to Red/Blue redaction.
var EnvCoordColumns = []string{
	"Latitude",
	"Longitude",
	"UTMEasting",
	"UTMNorthing",
	"XCoord",
	"YCoord",
}

// SensitiveSpeciesMetadata holds BC CDC Red/Blue-listed species codes loaded from VLists.db.
type SensitiveSpeciesMetadata struct {
	Codes    map[string]struct{}
	HasTable bool
}

func openSQLiteReadOnly(ctx context.Context, dbPath string, immutable bool) (*sql.DB, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	dsn := sqlutil.SqliteFileURI(dbPath, "ro")
	if immutable {
		dsn += "&immutable=1"
	} else {
		dsn += "&_busy_timeout=5000"
	}
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

// LoadSensitiveSpecies reads USysSppAttributes.RedBlueList from VLists.db using the same
// rules as cloudsync (skipping synonym Codetype='S' and matching cloudsync.IsSensitiveRedBlueList).
func LoadSensitiveSpecies(ctx context.Context, vlistsPath string, immutable bool) (*SensitiveSpeciesMetadata, error) {
	meta := &SensitiveSpeciesMetadata{
		Codes: map[string]struct{}{},
	}
	if strings.TrimSpace(vlistsPath) == "" {
		return meta, errors.New("VLists.db path must not be empty")
	}
	db, err := openSQLiteReadOnly(ctx, vlistsPath, immutable)
	if err != nil {
		return meta, fmt.Errorf("open VLists.db %q: %w", vlistsPath, err)
	}
	defer db.Close()

	var hasTbl int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='USysSppAttributes'`,
	).Scan(&hasTbl); err != nil {
		return meta, fmt.Errorf("check USysSppAttributes in VLists.db: %w", err)
	}
	if hasTbl == 0 {
		return meta, nil
	}
	meta.HasTable = true

	cols, err := tableColumns(ctx, db, "USysSppAttributes")
	if err != nil {
		return meta, fmt.Errorf("inspect USysSppAttributes columns: %w", err)
	}
	if !cols["Code"] || !cols["RedBlueList"] {
		return meta, errors.New("VLists.db USysSppAttributes is missing required Code or RedBlueList column")
	}

	var query string
	if cols["Codetype"] {
		query = `
			SELECT UPPER(TRIM(CAST("Code" AS TEXT))),
			       COALESCE(CAST("RedBlueList" AS TEXT), ''),
			       COALESCE(CAST("Codetype" AS TEXT), '')
			FROM "USysSppAttributes"
			WHERE "Code" IS NOT NULL AND TRIM(CAST("Code" AS TEXT)) <> ''
			  AND "RedBlueList" IS NOT NULL AND TRIM(CAST("RedBlueList" AS TEXT)) <> ''
		`
	} else {
		query = `
			SELECT UPPER(TRIM(CAST("Code" AS TEXT))),
			       COALESCE(CAST("RedBlueList" AS TEXT), ''),
			       ''
			FROM "USysSppAttributes"
			WHERE "Code" IS NOT NULL AND TRIM(CAST("Code" AS TEXT)) <> ''
			  AND "RedBlueList" IS NOT NULL AND TRIM(CAST("RedBlueList" AS TEXT)) <> ''
		`
	}

	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return meta, fmt.Errorf("query USysSppAttributes: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var code, rbl, codeType string
		if err := rows.Scan(&code, &rbl, &codeType); err != nil {
			return meta, fmt.Errorf("scan USysSppAttributes: %w", err)
		}
		if strings.EqualFold(strings.TrimSpace(codeType), "S") {
			continue
		}
		if cloudsync.IsSensitiveRedBlueList(rbl) {
			if trimmed := strings.ToUpper(strings.TrimSpace(code)); trimmed != "" {
				meta.Codes[trimmed] = struct{}{}
			}
		}
	}
	if err := rows.Err(); err != nil {
		return meta, err
	}
	return meta, nil
}

// RequireSensitiveSpecies enforces fail-closed conservation metadata loading:
// refuses to proceed if USysSppAttributes is missing or yields zero Red/Blue species.
func RequireSensitiveSpecies(ctx context.Context, vlistsPath string, immutable bool) (map[string]struct{}, error) {
	meta, err := LoadSensitiveSpecies(ctx, vlistsPath, immutable)
	if err != nil {
		return nil, err
	}
	if !meta.HasTable {
		return nil, errors.New("conservation status table USysSppAttributes is missing from VLists.db; refusing to publish unredacted plot coordinates without BC CDC Red/Blue status metadata")
	}
	if len(meta.Codes) == 0 {
		return nil, errors.New("conservation status metadata (VLists.db USysSppAttributes.RedBlueList) contains 0 Red/Blue-listed species rows; refusing to publish unredacted plot coordinates when redaction is enabled (populate BC CDC Red/Blue status codes or pass both --redact=false and --confirm-unredacted)")
	}
	return meta.Codes, nil
}

func tableColumns(ctx context.Context, db *sql.DB, table string) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+vprocore.QuoteHeaderIdentifier(table)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, colType string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[name] = true
	}
	return cols, rows.Err()
}

// FindSensitivePlots scans <project>_Veg and returns every PlotNumber containing a
// Red/Blue-listed species code in sensitiveSpecies.
func FindSensitivePlots(ctx context.Context, db *sql.DB, project string, sensitiveSpecies map[string]struct{}) (map[string]struct{}, error) {
	out := map[string]struct{}{}
	if len(sensitiveSpecies) == 0 {
		return out, nil
	}
	vegTable := vprocore.QuoteHeaderIdentifier(project + "_Veg")
	rows, err := db.QueryContext(ctx, `
		SELECT DISTINCT CAST("PlotNumber" AS TEXT), UPPER(TRIM(CAST("Species" AS TEXT)))
		FROM `+vegTable+`
		WHERE "PlotNumber" IS NOT NULL
		  AND "Species" IS NOT NULL
		  AND TRIM(CAST("Species" AS TEXT)) <> ''
	`)
	if err != nil {
		return nil, fmt.Errorf("scan %s_Veg for sensitive species: %w", project, err)
	}
	defer rows.Close()

	for rows.Next() {
		var plotNum, species string
		if err := rows.Scan(&plotNum, &species); err != nil {
			return nil, fmt.Errorf("scan %s_Veg row: %w", project, err)
		}
		if _, isSensitive := sensitiveSpecies[species]; isSensitive && plotNum != "" {
			out[plotNum] = struct{}{}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

// normalizeCoordCell converts numeric SQLite cells (including numeric TEXT/[]byte representations)
// to float64 so cloudsync.MaskSensitiveEnvRow truncates them consistently.
func normalizeCoordCell(raw any) (val any, isNum bool) {
	if raw == nil {
		return nil, false
	}
	switch v := raw.(type) {
	case float64:
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return raw, false
		}
		return v, true
	case float32:
		f := float64(v)
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return raw, false
		}
		return f, true
	case int64:
		return float64(v), true
	case int32:
		return float64(v), true
	case int:
		return float64(v), true
	case string:
		trimmed := strings.TrimSpace(v)
		if trimmed == "" {
			return raw, false
		}
		if f, err := strconv.ParseFloat(trimmed, 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
			return f, true
		}
		return raw, false
	case []byte:
		trimmed := strings.TrimSpace(string(v))
		if trimmed == "" {
			return raw, false
		}
		if f, err := strconv.ParseFloat(trimmed, 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
			return f, true
		}
		return raw, false
	default:
		return raw, false
	}
}

func presentEnvCoordSpecs(ctx context.Context, db *sql.DB, project string) ([]cloudsync.ColumnSpec, error) {
	cols, err := tableColumns(ctx, db, project+"_Env")
	if err != nil {
		return nil, fmt.Errorf("inspect %s_Env columns: %w", project, err)
	}
	specs := make([]cloudsync.ColumnSpec, 0, len(EnvCoordColumns))
	for _, name := range EnvCoordColumns {
		if cols[name] {
			specs = append(specs, cloudsync.ColumnSpec{Name: name})
		}
	}
	return specs, nil
}

// maskCoordRow applies cloudsync.MaskSensitiveEnvRow (0.1 deg Lat/Lon, 10,000 m UTM,
// and bounded XCoord/YCoord detection) to a single Env row's coordinate values.
func maskCoordRow(coordSpecs []cloudsync.ColumnSpec, rawValues []any) ([]any, bool) {
	masked := make([]any, len(rawValues))
	origNums := make([]float64, len(rawValues))
	isNum := make([]bool, len(rawValues))

	for i, raw := range rawValues {
		norm, ok := normalizeCoordCell(raw)
		masked[i] = norm
		isNum[i] = ok
		if ok {
			origNums[i] = norm.(float64)
		}
	}

	cloudsync.MaskSensitiveEnvRow(coordSpecs, masked)

	changed := false
	for i := range masked {
		if !isNum[i] {
			continue
		}
		after, ok := masked[i].(float64)
		if !ok {
			continue
		}
		// Double-check against cloudsync truncation functions explicitly for consistency.
		if math.Abs(origNums[i]-after) > 1e-9 {
			changed = true
		}
	}
	return masked, changed
}

// RedactProjectDatabase truncates Latitude, Longitude, UTMEasting, UTMNorthing, XCoord, YCoord
// on <Project>_Env for every plot containing a Red/Blue-listed species in <Project>_Veg.
// Must only be called on a staged copy (never on source files).
func RedactProjectDatabase(ctx context.Context, dbPath string, projects []string, sensitiveSpecies map[string]struct{}) (map[string]int, error) {
	counts := make(map[string]int, len(projects))
	if len(projects) == 0 {
		return counts, nil
	}
	if len(sensitiveSpecies) == 0 {
		return nil, errors.New("sensitiveSpecies map is empty; refusing to redact with empty conservation list")
	}

	db, err := sqlutil.OpenImmediateLockSQLite(dbPath)
	if err != nil {
		return nil, fmt.Errorf("open staged project DB %q for redaction: %w", dbPath, err)
	}
	defer db.Close()

	for _, project := range projects {
		sensitivePlots, err := FindSensitivePlots(ctx, db, project, sensitiveSpecies)
		if err != nil {
			return nil, err
		}
		if len(sensitivePlots) == 0 {
			counts[project] = 0
			continue
		}
		coordSpecs, err := presentEnvCoordSpecs(ctx, db, project)
		if err != nil {
			return nil, err
		}

		envTable := vprocore.QuoteHeaderIdentifier(project + "_Env")
		selectCols := make([]string, 0, len(coordSpecs)+2)
		selectCols = append(selectCols, `rowid`, `CAST("PlotNumber" AS TEXT)`)
		setClauses := make([]string, 0, len(coordSpecs))
		for _, spec := range coordSpecs {
			q := vprocore.QuoteHeaderIdentifier(spec.Name)
			selectCols = append(selectCols, q)
			setClauses = append(setClauses, q+` = ?`)
		}

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return nil, fmt.Errorf("begin redaction transaction for %s: %w", project, err)
		}

		type pendingUpdate struct {
			rowID  int64
			values []any
		}
		var updates []pendingUpdate
		redactedPlotSet := map[string]struct{}{}

		rows, err := tx.QueryContext(ctx, `SELECT `+strings.Join(selectCols, `, `)+` FROM `+envTable)
		if err != nil {
			_ = tx.Rollback()
			return nil, fmt.Errorf("query %s_Env for redaction: %w", project, err)
		}

		for rows.Next() {
			var rowID int64
			var plotNum sql.NullString
			rawCoords := make([]any, len(coordSpecs))
			dest := make([]any, len(coordSpecs)+2)
			dest[0] = &rowID
			dest[1] = &plotNum
			for i := range coordSpecs {
				dest[i+2] = &rawCoords[i]
			}
			if err := rows.Scan(dest...); err != nil {
				_ = rows.Close()
				_ = tx.Rollback()
				return nil, fmt.Errorf("scan %s_Env row: %w", project, err)
			}
			if !plotNum.Valid {
				continue
			}
			if _, sensitive := sensitivePlots[plotNum.String]; !sensitive {
				continue
			}
			redactedPlotSet[plotNum.String] = struct{}{}
			if len(coordSpecs) == 0 {
				continue
			}
			masked, _ := maskCoordRow(coordSpecs, rawCoords)
			updates = append(updates, pendingUpdate{rowID: rowID, values: masked})
		}
		if err := rows.Err(); err != nil {
			_ = rows.Close()
			_ = tx.Rollback()
			return nil, fmt.Errorf("iterate %s_Env rows: %w", project, err)
		}
		if err := rows.Close(); err != nil {
			_ = tx.Rollback()
			return nil, err
		}

		if len(updates) > 0 {
			stmt, err := tx.PrepareContext(ctx, `UPDATE `+envTable+` SET `+strings.Join(setClauses, `, `)+` WHERE rowid = ?`)
			if err != nil {
				_ = tx.Rollback()
				return nil, fmt.Errorf("prepare %s_Env redaction update: %w", project, err)
			}
			for _, u := range updates {
				args := make([]any, 0, len(u.values)+1)
				args = append(args, u.values...)
				args = append(args, u.rowID)
				if _, err := stmt.ExecContext(ctx, args...); err != nil {
					_ = stmt.Close()
					_ = tx.Rollback()
					return nil, fmt.Errorf("update redacted %s_Env rowid %d: %w", project, u.rowID, err)
				}
			}
			if err := stmt.Close(); err != nil {
				_ = tx.Rollback()
				return nil, err
			}
		}

		if err := tx.Commit(); err != nil {
			return nil, fmt.Errorf("commit redaction for %s: %w", project, err)
		}
		counts[project] = len(redactedPlotSet)
	}
	return counts, nil
}

// StripProjectAudit deletes all rows from <Project>_Audit while preserving the VP08 table schema.
// Must only be called on a staged copy (never on source files).
func StripProjectAudit(ctx context.Context, dbPath string, projects []string) (map[string]int64, error) {
	stripped := make(map[string]int64, len(projects))
	if len(projects) == 0 {
		return stripped, nil
	}

	db, err := sqlutil.OpenImmediateLockSQLite(dbPath)
	if err != nil {
		return nil, fmt.Errorf("open staged project DB %q for audit strip: %w", dbPath, err)
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin audit strip transaction: %w", err)
	}
	for _, project := range projects {
		auditTable := vprocore.QuoteHeaderIdentifier(project + "_Audit")
		res, err := tx.ExecContext(ctx, `DELETE FROM `+auditTable)
		if err != nil {
			_ = tx.Rollback()
			return nil, fmt.Errorf("strip rows from %s_Audit: %w", project, err)
		}
		n, _ := res.RowsAffected()
		stripped[project] = n
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit audit strip: %w", err)
	}
	return stripped, nil
}

// VerifyProjectRedaction checks that zero unredacted sensitive coordinates remain on <Project>_Env
// for any plot containing a Red/Blue-listed species in <Project>_Veg.
// Returns the count of distinct sensitive plots present in <Project>_Env.
func VerifyProjectRedaction(ctx context.Context, db *sql.DB, project string, sensitiveSpecies map[string]struct{}) (int, error) {
	sensitivePlots, err := FindSensitivePlots(ctx, db, project, sensitiveSpecies)
	if err != nil {
		return 0, err
	}
	if len(sensitivePlots) == 0 {
		return 0, nil
	}
	coordSpecs, err := presentEnvCoordSpecs(ctx, db, project)
	if err != nil {
		return 0, err
	}

	envTable := vprocore.QuoteHeaderIdentifier(project + "_Env")
	selectCols := make([]string, 0, len(coordSpecs)+1)
	selectCols = append(selectCols, `CAST("PlotNumber" AS TEXT)`)
	for _, spec := range coordSpecs {
		selectCols = append(selectCols, vprocore.QuoteHeaderIdentifier(spec.Name))
	}

	rows, err := db.QueryContext(ctx, `SELECT `+strings.Join(selectCols, `, `)+` FROM `+envTable)
	if err != nil {
		return 0, fmt.Errorf("verify redaction query on %s_Env: %w", project, err)
	}
	defer rows.Close()

	observedSensitivePlots := map[string]struct{}{}
	for rows.Next() {
		var plotNum sql.NullString
		rawCoords := make([]any, len(coordSpecs))
		dest := make([]any, len(coordSpecs)+1)
		dest[0] = &plotNum
		for i := range coordSpecs {
			dest[i+1] = &rawCoords[i]
		}
		if err := rows.Scan(dest...); err != nil {
			return 0, fmt.Errorf("verify redaction scan on %s_Env: %w", project, err)
		}
		if !plotNum.Valid {
			continue
		}
		if _, isSensitive := sensitivePlots[plotNum.String]; !isSensitive {
			continue
		}
		observedSensitivePlots[plotNum.String] = struct{}{}

		masked, changed := maskCoordRow(coordSpecs, rawCoords)
		if changed {
			for i, spec := range coordSpecs {
				orig, ok := normalizeCoordCell(rawCoords[i])
				if !ok {
					continue
				}
				origF := orig.(float64)
				maskedF, mOk := masked[i].(float64)
				if mOk && math.Abs(origF-maskedF) > 1e-9 {
					return 0, fmt.Errorf("unredacted sensitive coordinate detected in %s_Env plot %q column %s: got %v, expected %v (truncation rules: lat/lon=%.1f deg, utm=%.0f m)",
						project, plotNum.String, spec.Name, origF, maskedF,
						math.Abs(cloudsync.TruncateSensitiveLatLon(0.1)),
						math.Abs(cloudsync.TruncateSensitiveUTM(10000)))
				}
			}
			return 0, fmt.Errorf("unredacted sensitive coordinates detected in %s_Env plot %q", project, plotNum.String)
		}
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	return len(observedSensitivePlots), nil
}
