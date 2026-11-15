package datasheet

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"strconv"
	"strings"
	"unicode/utf8"
)

func tableExistsInSnapshot(ctx context.Context, tx *sql.Tx, role, table string) (bool, error) {
	if role == "" || table == "" {
		return false, nil
	}
	var exists bool
	err := tx.QueryRowContext(ctx,
		"SELECT EXISTS(SELECT 1 FROM "+vprocore.QuoteHeaderIdentifier(role)+".sqlite_master WHERE type='table' AND name COLLATE BINARY=?)",
		table,
	).Scan(&exists)
	return exists, err
}

func ListDatasheetTables(ctx context.Context, contexts *vprocore.ContextService, contextID string) ([]DatasheetTableInfo, error) {
	return listDatasheetTablesFiltered(ctx, contexts, contextID, false)
}

// ListDatasheetAllTables returns the 9 canonical datasheet tables plus read-only _Audit and _Metadata views.
func ListDatasheetAllTables(ctx context.Context, contexts *vprocore.ContextService, contextID string) ([]DatasheetTableInfo, error) {
	return listDatasheetTablesFiltered(ctx, contexts, contextID, true)
}

func listDatasheetTablesFiltered(ctx context.Context, contexts *vprocore.ContextService, contextID string, includeSystem bool) ([]DatasheetTableInfo, error) {
	if ctx == nil {
		return nil, errors.New("datasheet table listing requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ []DatasheetTableInfo, resultErr error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return nil, err
		}
		defer owner.Mu.Unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if err := tx.Rollback(); err != nil && !errors.Is(err, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, err)
			}
		}()

		var targets []resolvedDatasheetTarget
		if includeSystem {
			targets = resolveExtendedDatasheetTargets(owner)
		} else {
			targets = resolveDatasheetTargets(owner)
		}
		out := make([]DatasheetTableInfo, 0, len(targets))
		for _, target := range targets {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			info := DatasheetTableInfo{
				Key:               target.key,
				Label:             target.label,
				Role:              target.role,
				TableName:         target.tableName,
				PinnedColumn:      target.pinnedColumn,
				Available:         target.available,
				UnavailableReason: target.unavailableReason,
				Editable:          target.available && !target.readOnly,
				ReadOnly:          !target.available || target.readOnly,
				Columns:           []DatasheetColumnMeta{},
			}
			if !target.available {
				out = append(out, info)
				continue
			}
			exists, err := tableExistsInSnapshot(ctx, tx, target.role, target.tableName)
			if err != nil {
				return nil, err
			}
			if !exists {
				info.Available = false
				info.Editable = false
				info.ReadOnly = true
				info.UnavailableReason = fmt.Sprintf("Table %s does not exist in %s database", target.tableName, target.role)
				out = append(out, info)
				continue
			}
			rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, target.role, target.tableName)
			if err != nil {
				return nil, err
			}
			for _, col := range rawCols {
				info.Columns = append(info.Columns, classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster))
			}
			relation := vprocore.QuoteHeaderIdentifier(target.role) + "." + vprocore.QuoteHeaderIdentifier(target.tableName)
			if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+relation).Scan(&info.RowCount); err != nil {
				return nil, err
			}
			out = append(out, info)
		}
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return out, nil
	})
}

func escapeSQLiteLike(raw string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return replacer.Replace(raw)
}

func isDatasheetTextOrNoneAffinity(declType string) bool {
	u := strings.ToUpper(strings.TrimSpace(declType))
	if u == "" {
		return true
	}
	if strings.Contains(u, "INT") {
		return false
	}
	return strings.Contains(u, "CHAR") || strings.Contains(u, "CLOB") || strings.Contains(u, "TEXT") || strings.Contains(u, "BLOB")
}

func canMatchFormattedNumeric(needle string) bool {
	for _, r := range needle {
		switch {
		case r >= '0' && r <= '9':
		case r == '.' || r == '-' || r == '+' || r == 'e' || r == 'E':
		default:
			return false
		}
	}
	return needle != ""
}

func canMatchFormattedBoolean(needle string) bool {
	if canMatchFormattedNumeric(needle) {
		return true
	}
	lower := strings.ToLower(needle)
	return strings.Contains("true", lower) || strings.Contains("false", lower)
}

func buildDatasheetWhereAndOrder(
	ctx context.Context,
	tx *sql.Tx,
	target resolvedDatasheetTarget,
	columns []DatasheetColumnMeta,
	filters []DatasheetFilterSpec,
	globalSearch string,
	scopeToActiveSU bool,
	owner *vprocore.SqliteContext,
	sortSpecs []DatasheetSortSpec,
) (string, []any, string, error) {
	colLookup := make(map[string]DatasheetColumnMeta, len(columns))
	for _, c := range columns {
		colLookup[strings.ToLower(c.Name)] = c
	}

	var clauses []string
	var args []any

	if scopeToActiveSU && owner.Selection.SU != "None" && owner.Selection.SU != "" {
		var plotCol string
		switch target.key {
		case "Env", "Veg", "Humus", "Mineral", "Other":
			plotCol = "PlotNumber"
		case "Admin":
			plotCol = "Plot"
		}
		if plotCol != "" {
			suTableName := owner.Selection.SU + "_SU"
			suRel := `"su".` + vprocore.QuoteHeaderIdentifier(suTableName)
			qPlot := `__t.` + vprocore.QuoteHeaderIdentifier(plotCol)
			outerMeta := colLookup[strings.ToLower(plotCol)]

			suCols, suColErr := vprocore.ReadSQLiteStorageColumns(ctx, tx, "su", suTableName)
			if suColErr != nil {
				return "", nil, "", suColErr
			}
			suPlotDecl := ""
			for _, sc := range suCols {
				if strings.EqualFold(sc.Name, "PlotNumber") {
					suPlotDecl = sc.DeclaredType
					break
				}
			}
			suHasTextAffinity := isDatasheetTextOrNoneAffinity(suPlotDecl)

			// Probe up to 901 distinct typeof='text' SU plot numbers for fast IN pushdown on large child tables.
			var suPlots []string
			allValidUTF8 := true
			suRows, suErr := tx.QueryContext(ctx, `SELECT DISTINCT CAST("PlotNumber" AS BLOB) FROM `+suRel+` WHERE typeof("PlotNumber")='text' LIMIT 901`)
			if suErr != nil {
				return "", nil, "", suErr
			}
			for suRows.Next() {
				var raw []byte
				if err := suRows.Scan(&raw); err != nil {
					suRows.Close()
					return "", nil, "", err
				}
				s := string(raw)
				if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
					allValidUTF8 = false
				}
				suPlots = append(suPlots, s)
			}
			if err := errors.Join(suRows.Err(), suRows.Close()); err != nil {
				return "", nil, "", err
			}

			if len(suPlots) == 0 {
				clauses = append(clauses, "1=0")
			} else {
				idxEq := ""
				if suHasTextAffinity {
					idxEq = `__su."PlotNumber" COLLATE BINARY = ` + qPlot + ` COLLATE BINARY AND `
				}
				existsSQL := `EXISTS(SELECT 1 FROM ` + suRel + ` AS __su WHERE typeof(__su."PlotNumber")='text' AND typeof(` + qPlot + `)='text' AND ` + idxEq + `CAST(__su."PlotNumber" AS BLOB)=CAST(` + qPlot + ` AS BLOB))`
				if len(suPlots) <= 900 && allValidUTF8 && isDatasheetTextOrNoneAffinity(outerMeta.DeclaredType) {
					ph := make([]string, len(suPlots))
					for i, p := range suPlots {
						ph[i] = "?"
						args = append(args, p)
					}
					clauses = append(clauses, "("+qPlot+" IN ("+strings.Join(ph, ",")+") AND "+existsSQL+")")
				} else {
					clauses = append(clauses, existsSQL)
				}
			}
		}
	}

	for _, f := range filters {
		colMeta, ok := colLookup[strings.ToLower(strings.TrimSpace(f.Column))]
		if !ok {
			return "", nil, "", fmt.Errorf("unknown filter column %q on %s", f.Column, target.tableName)
		}
		if !utf8.ValidString(f.Value) || strings.ContainsRune(f.Value, 0) {
			return "", nil, "", fmt.Errorf("filter value for %q must be valid UTF-8 without NUL", colMeta.Name)
		}
		qCol := `__t.` + vprocore.QuoteHeaderIdentifier(colMeta.Name)
		op := strings.ToLower(strings.TrimSpace(f.Op))
		if op == "" {
			op = "contains"
		}
		switch op {
		case "is_null":
			clauses = append(clauses, "("+qCol+" IS NULL OR CAST("+qCol+" AS TEXT) = '')")
		case "not_null":
			clauses = append(clauses, "("+qCol+" IS NOT NULL AND CAST("+qCol+" AS TEXT) <> '')")
		case "eq":
			if f.Value == "" {
				continue
			}
			if colMeta.Name == "PlotNumber" || colMeta.Name == "Plot" {
				if isDatasheetTextOrNoneAffinity(colMeta.DeclaredType) {
					clauses = append(clauses, "("+qCol+" = ? AND typeof("+qCol+")='text' AND CAST("+qCol+" AS BLOB)=CAST(? AS BLOB))")
					args = append(args, f.Value, f.Value)
				} else {
					clauses = append(clauses, "(typeof("+qCol+")='text' AND CAST("+qCol+" AS BLOB)=CAST(? AS BLOB))")
					args = append(args, f.Value)
				}
			} else if colMeta.IsBoolean {
				bVal, err := parseFlexibleBoolean(f.Value)
				if err != nil {
					clauses = append(clauses, "CAST("+qCol+" AS TEXT) = ?")
					args = append(args, f.Value)
				} else if bVal {
					clauses = append(clauses, "CAST("+qCol+" AS INTEGER) <> 0")
				} else {
					clauses = append(clauses, "CAST("+qCol+" AS INTEGER) = 0")
				}
			} else {
				clauses = append(clauses, "CAST("+qCol+" AS TEXT) = ?")
				args = append(args, f.Value)
			}
		case "starts_with":
			if f.Value == "" {
				continue
			}
			clauses = append(clauses, "CAST("+qCol+" AS TEXT) LIKE ? ESCAPE '\\'")
			args = append(args, escapeSQLiteLike(f.Value)+"%")
		case "ends_with":
			if f.Value == "" {
				continue
			}
			clauses = append(clauses, "CAST("+qCol+" AS TEXT) LIKE ? ESCAPE '\\'")
			args = append(args, "%"+escapeSQLiteLike(f.Value))
		case "contains":
			if f.Value == "" {
				continue
			}
			clauses = append(clauses, "CAST("+qCol+" AS TEXT) LIKE ? ESCAPE '\\'")
			args = append(args, "%"+escapeSQLiteLike(f.Value)+"%")
		default:
			return "", nil, "", fmt.Errorf("unsupported filter operator %q", f.Op)
		}
	}

	trimmedGlobal := strings.TrimSpace(globalSearch)
	if trimmedGlobal != "" {
		if !utf8.ValidString(trimmedGlobal) || strings.ContainsRune(trimmedGlobal, 0) {
			return "", nil, "", errors.New("global search must be valid UTF-8 without NUL")
		}
		likeArg := "%" + escapeSQLiteLike(trimmedGlobal) + "%"
		matchNum := canMatchFormattedNumeric(trimmedGlobal)
		matchBool := canMatchFormattedBoolean(trimmedGlobal)
		paramIdx := len(args) + 1
		paramRef := "?" + strconv.Itoa(paramIdx)
		likeExpr := " LIKE " + paramRef
		if strings.ContainsAny(trimmedGlobal, `%_\`) {
			likeExpr = " LIKE " + paramRef + " ESCAPE '\\'"
		}
		var orParts []string
		for _, colMeta := range columns {
			qCol := `__t.` + vprocore.QuoteHeaderIdentifier(colMeta.Name)
			if colMeta.Kind == "text" {
				orParts = append(orParts, qCol+likeExpr)
				continue
			}
			if colMeta.Kind == "boolean" {
				if !matchBool {
					orParts = append(orParts, "(+"+qCol+" >= '' AND typeof("+qCol+") = 'text' AND "+qCol+likeExpr+")")
					continue
				}
			} else if !matchNum {
				orParts = append(orParts, "(+"+qCol+" >= '' AND typeof("+qCol+") = 'text' AND "+qCol+likeExpr+")")
				continue
			}
			orParts = append(orParts, "CAST("+qCol+" AS TEXT)"+likeExpr)
		}
		if len(orParts) > 0 {
			args = append(args, likeArg)
			clauses = append(clauses, "("+strings.Join(orParts, " OR ")+")")
		} else {
			clauses = append(clauses, "1=0")
		}
	}

	whereSQL := ""
	if len(clauses) > 0 {
		whereSQL = " WHERE " + strings.Join(clauses, " AND ")
	}

	orderPrefix := ""
	if trimmedGlobal != "" && len(filters) == 0 && !scopeToActiveSU {
		// Prevent SQLite from scanning 1M rows in random index->rowid order to satisfy ORDER BY during an unindexed full-table GlobalSearch!
		orderPrefix = "+"
	}
	var orderParts []string
	seenSort := map[string]bool{}
	for _, s := range sortSpecs {
		colMeta, ok := colLookup[strings.ToLower(strings.TrimSpace(s.Column))]
		if !ok {
			return "", nil, "", fmt.Errorf("unknown sort column %q on %s", s.Column, target.tableName)
		}
		lower := strings.ToLower(colMeta.Name)
		if seenSort[lower] {
			continue
		}
		seenSort[lower] = true
		dir := "ASC"
		if strings.EqualFold(strings.TrimSpace(s.Direction), "desc") {
			dir = "DESC"
		}
		qCol := orderPrefix + `__t.` + vprocore.QuoteHeaderIdentifier(colMeta.Name)
		// NULLs always sort last for predictable spreadsheet ergonomics, with case-insensitive text ordering.
		if colMeta.Kind == "text" {
			orderParts = append(orderParts, "CASE WHEN "+qCol+" IS NULL THEN 1 ELSE 0 END ASC", qCol+" COLLATE NOCASE "+dir, qCol+" COLLATE BINARY "+dir)
		} else {
			orderParts = append(orderParts, "CASE WHEN "+qCol+" IS NULL THEN 1 ELSE 0 END ASC", qCol+" "+dir)
		}
	}
	if len(orderParts) == 0 {
		if pinned, ok := colLookup[strings.ToLower(target.pinnedColumn)]; ok {
			qPin := orderPrefix + `__t.` + vprocore.QuoteHeaderIdentifier(pinned.Name)
			if target.key == "Env" || target.key == "Veg" {
				orderParts = append(orderParts, qPin+" COLLATE NOCASE ASC", qPin+" COLLATE BINARY ASC")
			} else {
				orderParts = append(orderParts, "CASE WHEN "+qPin+" IS NULL THEN 1 ELSE 0 END ASC", qPin+" COLLATE NOCASE ASC", qPin+" COLLATE BINARY ASC")
			}
		}
		if target.key == "Humus" {
			if _, ok := colLookup["upperdepth"]; ok {
				if _, hasHorizon := colLookup["horizon"]; hasHorizon {
					qHor := orderPrefix + `__t."Horizon"`
					qUp := orderPrefix + `__t."UpperDepth"`
					normHor := `LTRIM(UPPER(TRIM(COALESCE(` + qHor + `, ''))), '0123456789IVX ')`
					wetlandPred := `(` + normHor + ` LIKE 'OF%' OR ` + normHor + ` LIKE 'OM%' OR ` + normHor + ` LIKE 'OH%')`
					orderParts = append(orderParts,
						`CASE WHEN `+wetlandPred+` THEN 1 ELSE 0 END ASC`,
						`CASE WHEN `+qUp+` IS NULL THEN 1 ELSE 0 END ASC`,
						`CASE WHEN `+wetlandPred+` THEN `+qUp+` ELSE -`+qUp+` END ASC`,
					)
				} else {
					qUp := orderPrefix + `__t."UpperDepth"`
					orderParts = append(orderParts, `CASE WHEN `+qUp+` IS NULL THEN 1 ELSE 0 END ASC`, qUp+` DESC`)
				}
			}
		} else if target.key == "Mineral" {
			if _, ok := colLookup["upperdepth"]; ok {
				orderParts = append(orderParts, `CASE WHEN __t."UpperDepth" IS NULL THEN 1 ELSE 0 END ASC`, `__t."UpperDepth" ASC`)
			}
		}
	}
	orderParts = append(orderParts, "__t.rowid ASC")
	orderSQL := " ORDER BY " + strings.Join(orderParts, ", ")

	return whereSQL, args, orderSQL, nil
}
