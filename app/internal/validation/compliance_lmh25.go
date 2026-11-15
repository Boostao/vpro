package validation

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"strconv"
	"strings"
	"unicode/utf8"
)

func checkSingleCoverColumns(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	suffix string,
	plotCol string,
	plotDecl string,
	cols []string,
	useSU bool,
	suTextPlots map[string]struct{},
	suPlotList []string,
	report *ComplianceValidationReport,
) error {
	if len(cols) == 0 || (useSU && len(suTextPlots) == 0) {
		return nil
	}
	tbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_"+suffix)
	qPlot := vprocore.QuoteHeaderIdentifier(plotCol)

	selParts := make([]string, 0, 4+3*len(cols))
	selParts = append(selParts,
		`t.rowid`,
		`typeof(t.`+qPlot+`)`,
		`CAST(t.`+qPlot+` AS BLOB)`,
		`COALESCE(CAST(t.`+qPlot+` AS TEXT), '')`,
	)
	candClauses := make([]string, 0, len(cols))
	for _, col := range cols {
		qCol := vprocore.QuoteHeaderIdentifier(col)
		selParts = append(selParts,
			`typeof(t.`+qCol+`)`,
			`CAST(t.`+qCol+` AS REAL)`,
			`COALESCE(CAST(t.`+qCol+` AS TEXT), '')`,
		)
		// Any valid IEEE-754 float32 cover in [0, 100) has float64 < 99.99999618530273.
		// Pre-filtering candidates >= 99.9999 (or < 0 or non-numeric) in C-level SQLite avoids scanning clean cells into Go.
		candClauses = append(candClauses,
			`(t.`+qCol+` IS NOT NULL AND (typeof(t.`+qCol+`) NOT IN ('real','integer') OR t.`+qCol+` < 0 OR t.`+qCol+` >= 99.9999))`,
		)
	}

	whereSQL := ` WHERE (` + strings.Join(candClauses, " OR ") + `)`
	var qArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`t.`+qPlot, plotDecl, suPlotList); pre != "" {
			whereSQL += ` AND ` + pre
			qArgs = append(qArgs, args...)
		}
	}
	rows, err := tx.QueryContext(ctx, `SELECT `+strings.Join(selParts, ", ")+` FROM `+tbl+` t`+whereSQL+` ORDER BY t.rowid`, qArgs...)
	if err != nil {
		return err
	}
	defer rows.Close()

	perColFindings := make([][]BoundsFinding, len(cols))
	colTypes := make([]string, len(cols))
	colVals := make([]sql.NullFloat64, len(cols))
	colTexts := make([]string, len(cols))
	var rid int64
	var plotType, plotStr string
	var rawPlot []byte
	dest := make([]any, 4+3*len(cols))
	dest[0] = &rid
	dest[1] = &plotType
	dest[2] = &rawPlot
	dest[3] = &plotStr
	for i := range cols {
		dest[4+3*i] = &colTypes[i]
		dest[4+3*i+1] = &colVals[i]
		dest[4+3*i+2] = &colTexts[i]
	}

	for rows.Next() {
		if err := rows.Scan(dest...); err != nil {
			return err
		}
		if useSU {
			if plotType != "text" {
				continue
			}
			if _, ok := suTextPlots[string(rawPlot)]; !ok {
				continue
			}
		}
		for i, col := range cols {
			typ := colTypes[i]
			if typ == "null" {
				continue
			}
			fVal := colVals[i]
			if (typ != "real" && typ != "integer") || !fVal.Valid || !isValidSingleCover(fVal.Float64) {
				perColFindings[i] = append(perColFindings[i], BoundsFinding{
					Table:      suffix,
					PlotNumber: plotStr,
					RowID:      rid,
					Field:      col,
					Value:      colTexts[i],
					Rule:       "IEEE-754 SINGLE cover must be >= 0 and < 100",
				})
			}
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, list := range perColFindings {
		report.BoundsFindings = append(report.BoundsFindings, list...)
	}
	return nil
}

func checkProjectBounds(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	useSU bool,
	suTextPlots map[string]struct{},
	suPlotList []string,
	envCols, envTypes, adminCols, adminTypes map[string]string,
	report *ComplianceValidationReport,
) error {
	if useSU && len(suTextPlots) == 0 {
		return nil
	}

	_, vegTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Veg")
	if err != nil {
		return err
	}
	_, humusTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Humus")
	if err != nil {
		return err
	}
	_, minTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Mineral")
	if err != nil {
		return err
	}

	// Text UTF-16 length limits on core tables (grouped per table so each table is scanned at most once).
	type textColRule struct {
		col    string
		maxUTF int
	}
	type textTableGroup struct {
		suffix   string
		plotCol  string
		plotDecl string
		rules    []textColRule
	}
	textGroups := []textTableGroup{
		{"Env", "PlotNumber", envTypes["plotnumber"], []textColRule{
			{"PlotNumber", 7}, {"FieldNumber", 50}, {"ProjectID", 30},
			{"Zone", 4}, {"SubZone", 8}, {"SiteSeries", 5},
			{"Ecosection", 3}, {"NtsMapSheet", 8},
		}},
		{"Admin", "Plot", adminTypes["plot"], []textColRule{
			{"Plot", 7}, {"PlotType", 10},
		}},
		{"Veg", "PlotNumber", vegTypes["plotnumber"], []textColRule{
			{"PlotNumber", 7}, {"Species", 8}, {"Layer", 2}, {"Collected", 1},
		}},
		{"Humus", "PlotNumber", humusTypes["plotnumber"], []textColRule{
			{"PlotNumber", 7}, {"Horizon", 8},
		}},
		{"Mineral", "PlotNumber", minTypes["plotnumber"], []textColRule{
			{"PlotNumber", 7}, {"Horizon", 8}, {"Texture", 4}, {"Colour", 14},
		}},
	}

	for _, grp := range textGroups {
		tbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_"+grp.suffix)
		qPlot := vprocore.QuoteHeaderIdentifier(grp.plotCol)

		selParts := make([]string, 0, 4+len(grp.rules))
		selParts = append(selParts,
			`t.rowid`,
			`typeof(t.`+qPlot+`)`,
			`CAST(t.`+qPlot+` AS BLOB)`,
			`COALESCE(CAST(t.`+qPlot+` AS TEXT), '')`,
		)
		nonNullParts := make([]string, len(grp.rules))
		for i, r := range grp.rules {
			qCol := vprocore.QuoteHeaderIdentifier(r.col)
			selParts = append(selParts, `CAST(t.`+qCol+` AS BLOB)`)
			nonNullParts[i] = `t.` + qCol + ` IS NOT NULL`
		}
		whereSQL := ` WHERE (` + strings.Join(nonNullParts, " OR ") + `)`
		var qArgs []any
		if useSU {
			if pre, args := buildSUPlotInPreFilter(`t.`+qPlot, grp.plotDecl, suPlotList); pre != "" {
				whereSQL += ` AND ` + pre
				qArgs = append(qArgs, args...)
			}
		}

		rows, err := tx.QueryContext(ctx, `SELECT `+strings.Join(selParts, ", ")+` FROM `+tbl+` t`+whereSQL+` ORDER BY t.rowid`, qArgs...)
		if err != nil {
			return err
		}
		perRuleFindings := make([][]BoundsFinding, len(grp.rules))
		rawCells := make([][]byte, len(grp.rules))
		var rid int64
		var plotType, plotStr string
		var rawPlot []byte
		dest := make([]any, 4+len(grp.rules))
		dest[0] = &rid
		dest[1] = &plotType
		dest[2] = &rawPlot
		dest[3] = &plotStr
		for i := range rawCells {
			dest[4+i] = &rawCells[i]
		}

		for rows.Next() {
			if err := rows.Scan(dest...); err != nil {
				rows.Close()
				return err
			}
			if useSU {
				if plotType != "text" {
					continue
				}
				if _, ok := suTextPlots[string(rawPlot)]; !ok {
					continue
				}
			}
			for i, r := range grp.rules {
				raw := rawCells[i]
				if raw == nil {
					continue
				}
				if !utf8.Valid(raw) {
					perRuleFindings[i] = append(perRuleFindings[i], BoundsFinding{
						Table:      grp.suffix,
						PlotNumber: plotStr,
						RowID:      rid,
						Field:      r.col,
						Value:      fmt.Sprintf("0x%x", raw),
						Rule:       "Malformed UTF-8 byte sequence",
					})
					continue
				}
				s := string(raw)
				if utf16CodeUnitLen(s) > r.maxUTF {
					perRuleFindings[i] = append(perRuleFindings[i], BoundsFinding{
						Table:      grp.suffix,
						PlotNumber: plotStr,
						RowID:      rid,
						Field:      r.col,
						Value:      s,
						Rule:       fmt.Sprintf("Exceeds %d UTF-16 code units", r.maxUTF),
					})
				}
			}
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return err
		}
		for _, list := range perRuleFindings {
			report.BoundsFindings = append(report.BoundsFindings, list...)
		}
	}

	// Check IEEE-754 SINGLE (<100 and >=0) cover bounds in _Veg, _Env.StrataCover*, and _Admin.StrataCoverTotal.
	vegCoverCols := []string{
		"Cover1", "Cover2", "Cover3", "TotalA",
		"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
		"Cover6", "Cover7", "Cover8", "Cover9", "Cover10",
	}
	if err := checkSingleCoverColumns(ctx, tx, project, "Veg", "PlotNumber", vegTypes["plotnumber"], vegCoverCols, useSU, suTextPlots, suPlotList, report); err != nil {
		return err
	}

	var envStrataCols []string
	for _, col := range []string{"StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss"} {
		if actual, ok := envCols[strings.ToLower(col)]; ok {
			envStrataCols = append(envStrataCols, actual)
		}
	}
	if err := checkSingleCoverColumns(ctx, tx, project, "Env", "PlotNumber", envTypes["plotnumber"], envStrataCols, useSU, suTextPlots, suPlotList, report); err != nil {
		return err
	}

	var adminStrataCols []string
	if actual, ok := adminCols["stratacovertotal"]; ok {
		adminStrataCols = append(adminStrataCols, actual)
	}
	if err := checkSingleCoverColumns(ctx, tx, project, "Admin", "Plot", adminTypes["plot"], adminStrataCols, useSU, suTextPlots, suPlotList, report); err != nil {
		return err
	}

	// Check numeric bounds on _Env (Latitude, Longitude, Aspect, SlopeGradient) & _Admin (StartDate).
	envTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	envWhere := ` WHERE ("Latitude" IS NOT NULL OR "Longitude" IS NOT NULL OR "Aspect" IS NOT NULL OR "SlopeGradient" IS NOT NULL)`
	var envArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`t."PlotNumber"`, envTypes["plotnumber"], suPlotList); pre != "" {
			envWhere += ` AND ` + pre
			envArgs = append(envArgs, args...)
		}
	}
	envNumRows, err := tx.QueryContext(ctx, `SELECT t.rowid, typeof(t."PlotNumber"), CAST(t."PlotNumber" AS BLOB), COALESCE(CAST(t."PlotNumber" AS TEXT), ''),
		t."Latitude", t."Longitude", t."Aspect", t."SlopeGradient"
		FROM `+envTbl+` t`+envWhere+` ORDER BY t.rowid`, envArgs...)
	if err != nil {
		return err
	}
	for envNumRows.Next() {
		var rid int64
		var plotType, plot string
		var rawPlot []byte
		var lat, lon, slope sql.NullFloat64
		var aspect sql.NullInt64
		if err := envNumRows.Scan(&rid, &plotType, &rawPlot, &plot, &lat, &lon, &aspect, &slope); err != nil {
			envNumRows.Close()
			return err
		}
		if useSU {
			if plotType != "text" {
				continue
			}
			if _, ok := suTextPlots[string(rawPlot)]; !ok {
				continue
			}
		}
		if lat.Valid && (lat.Float64 < -90 || lat.Float64 > 90) {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Env", PlotNumber: plot, RowID: rid, Field: "Latitude",
				Value: vprocore.SourceDoubleDecimalString(lat.Float64), Rule: "Latitude must be between -90 and 90",
			})
		}
		if lon.Valid && (lon.Float64 < -180 || lon.Float64 > 180) {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Env", PlotNumber: plot, RowID: rid, Field: "Longitude",
				Value: vprocore.SourceDoubleDecimalString(lon.Float64), Rule: "Longitude must be between -180 and 180",
			})
		}
		if aspect.Valid && aspect.Int64 != 999 && (aspect.Int64 < 0 || aspect.Int64 > 359) {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Env", PlotNumber: plot, RowID: rid, Field: "Aspect",
				Value: strconv.FormatInt(aspect.Int64, 10), Rule: "Aspect must be 0..359 or 999 (level)",
			})
		}
		if slope.Valid && slope.Float64 < 0 {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Env", PlotNumber: plot, RowID: rid, Field: "SlopeGradient",
				Value: vprocore.SourceDoubleDecimalString(slope.Float64), Rule: "SlopeGradient must be >= 0",
			})
		}
	}
	if err := errors.Join(envNumRows.Err(), envNumRows.Close()); err != nil {
		return err
	}

	adminTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")
	adminWhere := ` WHERE t."StartDate" IS NOT NULL AND (typeof(t."StartDate") <> 'integer' OR t."StartDate" < 1900 OR t."StartDate" > 2500)`
	var adminArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`t."Plot"`, adminTypes["plot"], suPlotList); pre != "" {
			adminWhere += ` AND ` + pre
			adminArgs = append(adminArgs, args...)
		}
	}
	adminNumRows, err := tx.QueryContext(ctx, `SELECT t.rowid, typeof(t."Plot"), CAST(t."Plot" AS BLOB), COALESCE(CAST(t."Plot" AS TEXT), ''), t."StartDate"
		FROM `+adminTbl+` t`+adminWhere+` ORDER BY t.rowid`, adminArgs...)
	if err != nil {
		return err
	}
	for adminNumRows.Next() {
		var rid int64
		var plotType, plot string
		var rawPlot []byte
		var sd sql.NullInt64
		if err := adminNumRows.Scan(&rid, &plotType, &rawPlot, &plot, &sd); err != nil {
			adminNumRows.Close()
			return err
		}
		if useSU {
			if plotType != "text" {
				continue
			}
			if _, ok := suTextPlots[string(rawPlot)]; !ok {
				continue
			}
		}
		if sd.Valid && (sd.Int64 < 1900 || sd.Int64 > 2500) {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Admin", PlotNumber: plot, RowID: rid, Field: "StartDate",
				Value: strconv.FormatInt(sd.Int64, 10), Rule: "StartDate must be between 1900 and 2500",
			})
		}
	}
	if err := errors.Join(adminNumRows.Err(), adminNumRows.Close()); err != nil {
		return err
	}

	// Check LMH25 soil horizon directional depth signs:
	// Upland L/F/H humus horizons measure upward from 0 cm (UpperDepth > LowerDepth);
	// Wetland Of/Om/Oh and Mineral A/B/C/R/W measure downward (UpperDepth < LowerDepth).
	humusTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Humus")
	hWhere := ` WHERE t."UpperDepth" IS NOT NULL AND t."LowerDepth" IS NOT NULL`
	var hArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`t."PlotNumber"`, humusTypes["plotnumber"], suPlotList); pre != "" {
			hWhere += ` AND ` + pre
			hArgs = append(hArgs, args...)
		}
	}
	hRows, err := tx.QueryContext(ctx, `SELECT t.rowid, typeof(t."PlotNumber"), CAST(t."PlotNumber" AS BLOB), COALESCE(CAST(t."PlotNumber" AS TEXT), ''), COALESCE(CAST(t."Horizon" AS TEXT), ''), t."UpperDepth", t."LowerDepth"
		FROM `+humusTbl+` t`+hWhere+` ORDER BY t.rowid`, hArgs...)
	if err != nil {
		return err
	}
	for hRows.Next() {
		var rid int64
		var plotType, plot, hz string
		var rawPlot []byte
		var upper, lower float64
		if err := hRows.Scan(&rid, &plotType, &rawPlot, &plot, &hz, &upper, &lower); err != nil {
			hRows.Close()
			return err
		}
		if useSU {
			if plotType != "text" {
				continue
			}
			if _, ok := suTextPlots[string(rawPlot)]; !ok {
				continue
			}
		}
		if upper < 0 || lower < 0 {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Humus", PlotNumber: plot, RowID: rid, Field: "UpperDepth",
				Value: fmt.Sprintf("%g..%g (%s)", upper, lower, strings.TrimSpace(hz)),
				Rule:  "LMH25 soil horizon depths must be >= 0 cm",
			})
			continue
		}
		trimmedUpper := strings.TrimLeft(strings.ToUpper(strings.TrimSpace(hz)), "0123456789")
		if strings.HasPrefix(trimmedUpper, "OF") || strings.HasPrefix(trimmedUpper, "OM") || strings.HasPrefix(trimmedUpper, "OH") {
			if upper >= lower {
				report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
					Table: "Humus", PlotNumber: plot, RowID: rid, Field: "UpperDepth",
					Value: fmt.Sprintf("%g..%g (%s)", upper, lower, strings.TrimSpace(hz)),
					Rule:  "LMH25 wetland Of/Om/Oh horizons measure downward (0 <= UpperDepth < LowerDepth)",
				})
			}
		} else if strings.HasPrefix(trimmedUpper, "L") || strings.HasPrefix(trimmedUpper, "F") || strings.HasPrefix(trimmedUpper, "H") {
			if upper <= lower {
				report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
					Table: "Humus", PlotNumber: plot, RowID: rid, Field: "UpperDepth",
					Value: fmt.Sprintf("%g..%g (%s)", upper, lower, strings.TrimSpace(hz)),
					Rule:  "LMH25 upland L/F/H horizons measure upward from 0 cm (UpperDepth > LowerDepth >= 0)",
				})
			}
		}
	}
	if err := errors.Join(hRows.Err(), hRows.Close()); err != nil {
		return err
	}

	minTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Mineral")
	mWhere := ` WHERE t."UpperDepth" IS NOT NULL AND t."LowerDepth" IS NOT NULL AND (t."UpperDepth" < 0 OR t."LowerDepth" < 0 OR t."UpperDepth" >= t."LowerDepth")`
	var mArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`t."PlotNumber"`, minTypes["plotnumber"], suPlotList); pre != "" {
			mWhere += ` AND ` + pre
			mArgs = append(mArgs, args...)
		}
	}
	mRows, err := tx.QueryContext(ctx, `SELECT t.rowid, typeof(t."PlotNumber"), CAST(t."PlotNumber" AS BLOB), COALESCE(CAST(t."PlotNumber" AS TEXT), ''), COALESCE(CAST(t."Horizon" AS TEXT), ''), t."UpperDepth", t."LowerDepth"
		FROM `+minTbl+` t`+mWhere+` ORDER BY t.rowid`, mArgs...)
	if err != nil {
		return err
	}
	for mRows.Next() {
		var rid int64
		var plotType, plot, hz string
		var rawPlot []byte
		var upper, lower float64
		if err := mRows.Scan(&rid, &plotType, &rawPlot, &plot, &hz, &upper, &lower); err != nil {
			mRows.Close()
			return err
		}
		if useSU {
			if plotType != "text" {
				continue
			}
			if _, ok := suTextPlots[string(rawPlot)]; !ok {
				continue
			}
		}
		if upper < 0 || lower < 0 {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Mineral", PlotNumber: plot, RowID: rid, Field: "UpperDepth",
				Value: fmt.Sprintf("%g..%g (%s)", upper, lower, strings.TrimSpace(hz)),
				Rule:  "LMH25 mineral horizon depths must be >= 0 cm (0 <= UpperDepth < LowerDepth)",
			})
		} else if upper >= lower {
			report.BoundsFindings = append(report.BoundsFindings, BoundsFinding{
				Table: "Mineral", PlotNumber: plot, RowID: rid, Field: "UpperDepth",
				Value: fmt.Sprintf("%g..%g (%s)", upper, lower, strings.TrimSpace(hz)),
				Rule:  "LMH25 mineral horizons measure downward (UpperDepth < LowerDepth)",
			})
		}
	}
	return errors.Join(mRows.Err(), mRows.Close())
}
