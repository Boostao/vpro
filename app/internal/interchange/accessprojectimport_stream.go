package interchange

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/accessimport"
	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func adaptAccessRows(ctx context.Context, cols []accessreader.Column, rows []accessreader.Row) (map[string]int, [][]any, error) {
	srcCols := make([]accessimport.SourceColumn, len(cols))
	colIndex := make(map[string]int, len(cols))
	for i, c := range cols {
		srcCols[i] = accessimport.SourceColumn{Name: c.Name, Type: c.Type}
		colIndex[strings.ToLower(c.Name)] = i
	}
	adapted := make([][]any, len(rows))
	for rIdx, rawRow := range rows {
		vals, err := accessimport.SQLiteRow(ctx, srcCols, []any(rawRow))
		if err != nil {
			return nil, nil, fmt.Errorf("row %d: %w", rIdx+1, err)
		}
		adapted[rIdx] = vals
	}
	return colIndex, adapted, nil
}

func querySQLiteTableColumns(ctx context.Context, tx *sql.Tx, tableName string) (map[string]string, error) {
	rows, err := tx.QueryContext(ctx, fmt.Sprintf("PRAGMA table_info(%s)", vprocore.QuoteHeaderIdentifier(tableName)))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := make(map[string]string)
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

type streamInsertSpec struct {
	targetTable        string
	targetToSource     [][2]string // nil means intersect source columns with target SQLite columns
	computed           map[string]func([]any, map[string]int) any
	columnOverrides    map[string]func(any) any
	requireEnvPlot     bool
	plotSourceCol      string
	dedupePlotKey      bool
	recordEnvPlots     map[string]struct{}
	childIdentityTable string
}

type streamTableMetrics struct {
	actualSourceTable string
	columnCount       int
	importedRows      int
	malformedRows     int
	orphanRows        int
}

func adaptedPlotKey(v any) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return fmt.Sprint(v)
}

type accessRowSource interface {
	ColumnsList() []accessreader.Column
	EnableRowQuarantine()
	Next() bool
	Row() accessreader.Row
	Err() error
	QuarantinedRows() []accessreader.QuarantinedRow
	Close() error
}

type accessReaderAdapter struct {
	*accessreader.Reader
}

func (a accessReaderAdapter) ColumnsList() []accessreader.Column { return a.Reader.Columns }
func (a accessReaderAdapter) QuarantinedRows() []accessreader.QuarantinedRow {
	return a.Reader.Quarantined
}

func streamAccessTableIntoSQLite(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt *sql.Stmt,
	childIdStmt *sql.Stmt,
	sourceTable string,
	validEnvPlots map[string]struct{},
	specs []streamInsertSpec,
) (streamTableMetrics, error) {
	reader, err := db.Scan(sourceTable)
	if err != nil {
		return streamTableMetrics{}, fmt.Errorf("open %s: %w", sourceTable, err)
	}
	defer reader.Close()
	return streamAccessSourceIntoSQLite(ctx, accessReaderAdapter{reader}, tx, quarantineStmt, childIdStmt, sourceTable, validEnvPlots, specs)
}

func streamAccessSourceIntoSQLite(
	ctx context.Context,
	reader accessRowSource,
	tx *sql.Tx,
	quarantineStmt *sql.Stmt,
	childIdStmt *sql.Stmt,
	sourceTable string,
	validEnvPlots map[string]struct{},
	specs []streamInsertSpec,
) (streamTableMetrics, error) {
	var metrics streamTableMetrics
	reader.EnableRowQuarantine()
	cols := reader.ColumnsList()
	metrics.actualSourceTable = sourceTable
	metrics.columnCount = len(cols)

	srcCols := make([]accessimport.SourceColumn, len(cols))
	colIndex := make(map[string]int, len(cols))
	for i, c := range cols {
		srcCols[i] = accessimport.SourceColumn{Name: c.Name, Type: c.Type}
		colIndex[strings.ToLower(c.Name)] = i
	}
	colPlan, err := accessimport.PlanColumns(ctx, srcCols)
	if err != nil {
		return metrics, err
	}
	idIdx, hasIDCol := colIndex["id"]
	if !hasIDCol {
		idIdx = -1
	}

	type preparedTarget struct {
		spec           streamInsertSpec
		stmt           *sql.Stmt
		sourceIndices  []int
		overrides      []func(any) any
		computedKeys   []string
		targetColNames []string
		targetLimits   []int
		argsBuf        []any
		seenPlots      map[string]struct{}
		plotIdx        int
	}
	targets := make([]preparedTarget, len(specs))
	for sIdx, spec := range specs {
		mapping := spec.targetToSource
		if mapping == nil {
			dstCols, err := querySQLiteTableColumns(ctx, tx, spec.targetTable)
			if err != nil {
				return metrics, err
			}
			for _, c := range cols {
				if canonical, ok := dstCols[strings.ToLower(c.Name)]; ok {
					mapping = append(mapping, [2]string{canonical, c.Name})
				}
			}
		}
		if len(spec.computed) > 0 {
			computedLower := make(map[string]struct{}, len(spec.computed))
			for k := range spec.computed {
				computedLower[strings.ToLower(k)] = struct{}{}
			}
			filtered := make([][2]string, 0, len(mapping))
			for _, pair := range mapping {
				if _, overridden := computedLower[strings.ToLower(pair[0])]; overridden {
					continue
				}
				filtered = append(filtered, pair)
			}
			mapping = filtered
		}
		overrideByLower := make(map[string]func(any) any, len(spec.columnOverrides))
		for k, fn := range spec.columnOverrides {
			overrideByLower[strings.ToLower(k)] = fn
		}
		targetCols := make([]string, 0, len(mapping)+len(spec.computed))
		targetColNames := make([]string, 0, len(mapping)+len(spec.computed))
		targetLimits := make([]int, 0, len(mapping)+len(spec.computed))
		sourceIndices := make([]int, len(mapping))
		overrides := make([]func(any) any, len(mapping))
		for i, pair := range mapping {
			overrideFn := overrideByLower[strings.ToLower(pair[0])]
			idx, ok := colIndex[strings.ToLower(pair[1])]
			if !ok {
				if strings.EqualFold(pair[1], "Collected") || (strings.EqualFold(pair[0], "Project") && overrideFn != nil) {
					sourceIndices[i] = -1
				} else {
					return metrics, fmt.Errorf("source table %s for %s is missing column %q", sourceTable, spec.targetTable, pair[1])
				}
			} else {
				sourceIndices[i] = idx
			}
			overrides[i] = overrideFn
			targetCols = append(targetCols, vprocore.QuoteHeaderIdentifier(pair[0]))
			targetColNames = append(targetColNames, pair[0])
			targetLimits = append(targetLimits, accessColumnUTF16Limit(spec.targetTable, pair[0]))
		}
		var computedKeys []string
		for k := range spec.computed {
			computedKeys = append(computedKeys, k)
		}
		slices.Sort(computedKeys)
		for _, k := range computedKeys {
			targetCols = append(targetCols, vprocore.QuoteHeaderIdentifier(k))
			targetColNames = append(targetColNames, k)
			targetLimits = append(targetLimits, accessColumnUTF16Limit(spec.targetTable, k))
		}
		marks := make([]string, len(targetCols))
		for i := range marks {
			marks[i] = "?"
		}
		stmtSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
			vprocore.QuoteHeaderIdentifier(spec.targetTable),
			strings.Join(targetCols, ", "),
			strings.Join(marks, ", "))
		stmt, err := tx.PrepareContext(ctx, stmtSQL)
		if err != nil {
			return metrics, fmt.Errorf("prepare insert into %s: %w", spec.targetTable, err)
		}
		defer stmt.Close()

		plotCol := spec.plotSourceCol
		if plotCol == "" {
			plotCol = "PlotNumber"
		}
		pIdx, hasPlot := colIndex[strings.ToLower(plotCol)]
		if !hasPlot {
			pIdx = -1
		}
		var seen map[string]struct{}
		if spec.dedupePlotKey || spec.recordEnvPlots != nil {
			seen = make(map[string]struct{})
		}
		targets[sIdx] = preparedTarget{
			spec:           spec,
			stmt:           stmt,
			sourceIndices:  sourceIndices,
			overrides:      overrides,
			computedKeys:   computedKeys,
			targetColNames: targetColNames,
			targetLimits:   targetLimits,
			argsBuf:        make([]any, len(sourceIndices)+len(computedKeys)),
			seenPlots:      seen,
			plotIdx:        pIdx,
		}
	}

	reserveQuarantinedID := func(tg *preparedTarget, row []any) {
		if childIdStmt == nil || tg.spec.childIdentityTable == "" || idIdx < 0 || idIdx >= len(row) {
			return
		}
		if idVal, ok := row[idIdx].(int64); ok && idVal > 0 {
			_, _ = childIdStmt.ExecContext(ctx, tg.spec.childIdentityTable, idVal)
		}
	}

	adapted := make([]any, len(colPlan))
	rowOrdinal := 0
	for reader.Next() {
		rowOrdinal++
		if rowOrdinal&4095 == 0 {
			if err := ctx.Err(); err != nil {
				return metrics, err
			}
		}
		rawRow := reader.Row()
		var adaptErr error
		for cIdx, cellVal := range rawRow {
			adapted[cIdx], adaptErr = accessimport.SQLiteValue(cellVal)
			if adaptErr != nil {
				break
			}
		}
		if adaptErr != nil {
			metrics.malformedRows++
			if quarantineStmt != nil {
				_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowOrdinal, "", "malformed_value: "+adaptErr.Error(), "{}")
			}
			continue
		}

		skipRow := false
		for tIdx := range targets {
			tg := &targets[tIdx]
			plotKey := ""
			if tg.plotIdx >= 0 && adapted[tg.plotIdx] != nil {
				plotKey = adaptedPlotKey(adapted[tg.plotIdx])
			}
			if tg.spec.requireEnvPlot && validEnvPlots != nil {
				if _, ok := validEnvPlots[plotKey]; !ok {
					metrics.orphanRows++
					reserveQuarantinedID(tg, adapted)
					if quarantineStmt != nil {
						payload, _ := json.Marshal(adapted)
						_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowOrdinal, plotKey, "orphan_missing_env_plot", string(payload))
					}
					skipRow = true
					break
				}
			}
			if tg.seenPlots != nil && plotKey != "" {
				if _, dup := tg.seenPlots[plotKey]; dup {
					metrics.malformedRows++
					reserveQuarantinedID(tg, adapted)
					if quarantineStmt != nil {
						payload, _ := json.Marshal(adapted)
						_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowOrdinal, plotKey, "duplicate_plot_key", string(payload))
					}
					skipRow = true
					break
				}
			}
		}
		if skipRow {
			continue
		}

		var utf16Violation string
		for tIdx := range targets {
			tg := &targets[tIdx]
			args := tg.argsBuf
			nSrc := len(tg.sourceIndices)
			for i, idx := range tg.sourceIndices {
				var v any
				if idx >= 0 {
					v = adapted[idx]
				}
				if fn := tg.overrides[i]; fn != nil {
					v = fn(v)
				}
				args[i] = v
			}
			for i, k := range tg.computedKeys {
				args[nSrc+i] = tg.spec.computed[k](adapted, colIndex)
			}
			if utf16Violation == "" {
				for i, limit := range tg.targetLimits {
					if limit <= 0 {
						continue
					}
					if s, ok := args[i].(string); ok {
						if !utf8.ValidString(s) || strings.ContainsRune(s, 0) || len(utf16.Encode([]rune(s))) > limit {
							utf16Violation = fmt.Sprintf("%s.%s exceeds %d UTF-16 code units or invalid UTF-8", tg.spec.targetTable, tg.targetColNames[i], limit)
							break
						}
					}
				}
			}
		}
		if utf16Violation != "" {
			metrics.malformedRows++
			for tIdx := range targets {
				reserveQuarantinedID(&targets[tIdx], adapted)
			}
			if quarantineStmt != nil {
				plotKey := ""
				if len(targets) > 0 && targets[0].plotIdx >= 0 && adapted[targets[0].plotIdx] != nil {
					plotKey = adaptedPlotKey(adapted[targets[0].plotIdx])
				}
				payload, _ := json.Marshal(adapted)
				_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowOrdinal, plotKey, "utf16_length_bound: "+utf16Violation, string(payload))
			}
			continue
		}

		insertedPrimary := false
		for tIdx := range targets {
			tg := &targets[tIdx]
			if _, execErr := tg.stmt.ExecContext(ctx, tg.argsBuf...); execErr != nil {
				metrics.malformedRows++
				reserveQuarantinedID(tg, adapted)
				if quarantineStmt != nil {
					payload, _ := json.Marshal(adapted)
					_, _ = quarantineStmt.ExecContext(ctx, sourceTable, rowOrdinal, "", "sqlite_insert_constraint: "+execErr.Error(), string(payload))
				}
				break
			}
			if tg.plotIdx >= 0 && adapted[tg.plotIdx] != nil {
				pk := adaptedPlotKey(adapted[tg.plotIdx])
				if tg.seenPlots != nil && pk != "" {
					tg.seenPlots[pk] = struct{}{}
				}
				if tg.spec.recordEnvPlots != nil && pk != "" {
					tg.spec.recordEnvPlots[pk] = struct{}{}
				}
			}
			if tIdx == 0 {
				insertedPrimary = true
			}
		}
		if insertedPrimary {
			metrics.importedRows++
		}
	}
	if err := reader.Err(); err != nil {
		return metrics, fmt.Errorf("scan %s: %w", sourceTable, err)
	}
	for _, q := range reader.QuarantinedRows() {
		metrics.malformedRows++
		if quarantineStmt != nil {
			_, _ = quarantineStmt.ExecContext(ctx, sourceTable, q.RowNumber, "", "access_decode: "+q.Reason, "{}")
		}
	}
	return metrics, nil
}

func resolveAuditChildSuffixes(rawTable, sourceProject, targetProject string) []string {
	t := strings.ToLower(strings.TrimSpace(rawTable))
	if t == "" {
		return []string{"Veg", "Humus", "Mineral", "Other", "Metadata"}
	}
	for _, pfx := range []string{strings.ToLower(sourceProject) + "_", strings.ToLower(targetProject) + "_", "_"} {
		if strings.HasPrefix(t, pfx) {
			t = strings.TrimPrefix(t, pfx)
			break
		}
	}
	switch t {
	case "veg", "vegetation":
		return []string{"Veg"}
	case "humus", "soilhumus", "organic":
		return []string{"Humus"}
	case "mineral", "soilmineral":
		return []string{"Mineral"}
	case "other", "vegother":
		return []string{"Other"}
	case "metadata", "projectmetadata":
		return []string{"Metadata"}
	case "env", "environment", "admin", "su", "hierarchy", "lump", "profile",
		"open", "close", "on", "off", "usysallspecs", "usystableoflists":
		return nil
	default:
		// Unrecognized legacy audit labels (e.g. 'Unknown') with positive IDs reserve across child tables conservatively.
		return []string{"Veg", "Humus", "Mineral", "Other", "Metadata"}
	}
}

func seedImportedChildIdentities(ctx context.Context, tx *sql.Tx, sourceProject, targetProject string) error {
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
		"ChildTable" TEXT NOT NULL,
		"ID" INTEGER NOT NULL,
		PRIMARY KEY ("ChildTable", "ID")
	)`); err != nil {
		return err
	}

	for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other", "Metadata", "Audit"} {
		qChild := vprocore.QuoteHeaderIdentifier(targetProject + "_" + suffix)
		if _, err := tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID")
			 SELECT ?, "ID" FROM `+qChild+` WHERE typeof("ID") = 'integer' AND "ID" > 0`,
			qChild,
		); err != nil {
			return err
		}
	}

	qAudit := vprocore.QuoteHeaderIdentifier(targetProject + "_Audit")
	rows, err := tx.QueryContext(ctx,
		`SELECT DISTINCT COALESCE(CAST("Table" AS TEXT), ''), "ID"
		 FROM `+qAudit+`
		 WHERE typeof("ID") = 'integer' AND "ID" > 0`)
	if err != nil {
		return err
	}
	type auditIDPair struct {
		tbl string
		id  int64
	}
	var pairs []auditIDPair
	for rows.Next() {
		var tbl string
		var id int64
		if err := rows.Scan(&tbl, &id); err != nil {
			rows.Close()
			return err
		}
		pairs = append(pairs, auditIDPair{tbl: tbl, id: id})
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return err
	}

	if len(pairs) > 0 {
		stmt, err := tx.PrepareContext(ctx, `INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)`)
		if err != nil {
			return err
		}
		defer stmt.Close()
		for _, p := range pairs {
			for _, suffix := range resolveAuditChildSuffixes(p.tbl, sourceProject, targetProject) {
				qChild := vprocore.QuoteHeaderIdentifier(targetProject + "_" + suffix)
				if _, err := stmt.ExecContext(ctx, qChild, p.id); err != nil {
					return err
				}
			}
		}
	}
	return nil
}
