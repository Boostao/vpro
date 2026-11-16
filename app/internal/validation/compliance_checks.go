package validation

import (
	"context"
	"database/sql"
	"errors"
	"github.com/boostao/vpro/app/internal/vprocore"
	"slices"
	"strings"
)

func checkDuplicateVegSpecies(ctx context.Context, tx *sql.Tx, project string, useSU bool, suTextPlots map[string]struct{}, suPlotList []string, report *ComplianceValidationReport) error {
	if useSU && len(suPlotList) == 0 {
		return nil
	}
	vegTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Veg")
	_, vegTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Veg")
	if err != nil {
		return err
	}

	// Pre-filter duplicate (PlotNumber, Species) plots in C-level SQLite
	// so clean 1.65M-row datasets never materialize per-row layer bitmasks in Go.
	// Group by CAST("PlotNumber" AS TEXT), CAST("Species" AS TEXT) so mixed-storage integer 337 + text '337'
	// duplicates match the exact final duplicate-grouping semantics.
	dupWhere := ` WHERE "PlotNumber" IS NOT NULL AND "Species" IS NOT NULL`
	var dupArgs []any
	if useSU {
		var hasNonTextVegPlot bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM `+vegTbl+` WHERE "PlotNumber" IS NOT NULL AND typeof("PlotNumber") <> 'text' LIMIT 1)`).Scan(&hasNonTextVegPlot); err != nil {
			return err
		}
		if !hasNonTextVegPlot {
			if pre, args := buildSUPlotInPreFilter(`"PlotNumber"`, vegTypes["plotnumber"], suPlotList); pre != "" {
				dupWhere += ` AND ` + pre
				dupArgs = append(dupArgs, args...)
			}
		}
	}
	dupPlotRows, err := tx.QueryContext(ctx, `SELECT COALESCE(CAST("PlotNumber" AS TEXT), ''),
		       MAX(CASE WHEN typeof("PlotNumber") <> 'text' THEN 1 ELSE 0 END)
		FROM `+vegTbl+dupWhere+`
		GROUP BY CAST("PlotNumber" AS TEXT), CAST("Species" AS TEXT)
		HAVING COUNT(*) > 1`, dupArgs...)
	if err != nil {
		return err
	}
	var candidatePlots []string
	seenCandPlot := map[string]struct{}{}
	anyNonTextCandidate := false
	for dupPlotRows.Next() {
		var p string
		var nonText int
		if err := dupPlotRows.Scan(&p, &nonText); err != nil {
			dupPlotRows.Close()
			return err
		}
		if useSU {
			if _, inSU := suTextPlots[p]; !inSU {
				continue
			}
		}
		if nonText != 0 {
			anyNonTextCandidate = true
		}
		if _, exists := seenCandPlot[p]; !exists {
			seenCandPlot[p] = struct{}{}
			candidatePlots = append(candidatePlots, p)
		}
	}
	if err := errors.Join(dupPlotRows.Err(), dupPlotRows.Close()); err != nil {
		return err
	}
	if len(candidatePlots) == 0 {
		return nil
	}

	layerCols := []struct {
		code string
		col  string
	}{
		{"1", "Cover1"}, {"2", "Cover2"}, {"3", "Cover3"}, {"A", "TotalA"},
		{"4", "Cover4"}, {"5", "Cover5"}, {"5a", "Cover5a"}, {"5b", "Cover5b"}, {"5c", "Cover5c"}, {"B", "TotalB"},
		{"6", "Cover6"}, {"7", "Cover7"}, {"8", "Cover8"}, {"9", "Cover9"}, {"10", "Cover10"},
	}

	var colExprs []string
	for _, lc := range layerCols {
		colExprs = append(colExprs, `CASE WHEN `+vprocore.QuoteHeaderIdentifier(lc.col)+` IS NOT NULL THEN 1 ELSE 0 END`)
	}

	whereExtra := ""
	var qArgs []any
	plotFilterCol := `"PlotNumber"`
	plotFilterType := vegTypes["plotnumber"]
	uDecl := strings.ToUpper(strings.TrimSpace(plotFilterType))
	isStrictTextCol := uDecl != "" && !strings.Contains(uDecl, "INT") && !strings.Contains(uDecl, "BLOB") &&
		(strings.Contains(uDecl, "CHAR") || strings.Contains(uDecl, "CLOB") || strings.Contains(uDecl, "TEXT"))
	if anyNonTextCandidate || !isStrictTextCol {
		plotFilterCol = `CAST("PlotNumber" AS TEXT)`
		plotFilterType = "TEXT"
	}
	if pre, args := buildSUPlotInPreFilter(plotFilterCol, plotFilterType, candidatePlots); pre != "" {
		whereExtra = ` AND ` + pre
		qArgs = append(qArgs, args...)
	}

	q := `SELECT COALESCE(CAST("PlotNumber" AS TEXT), ''), COALESCE(CAST("Species" AS TEXT), ''), ` + strings.Join(colExprs, ", ") + `
		FROM ` + vegTbl + `
		WHERE "PlotNumber" IS NOT NULL AND "Species" IS NOT NULL` + whereExtra

	rows, err := tx.QueryContext(ctx, q, qArgs...)
	if err != nil {
		return err
	}
	defer rows.Close()

	type grpKey struct{ plot, spp string }
	type grpStat struct {
		count       int
		layerCounts []int
	}
	stats := map[grpKey]*grpStat{}
	var dupKeys []grpKey

	var plot, spp string
	flags := make([]int, len(layerCols))
	dest := make([]any, 2+len(layerCols))
	dest[0], dest[1] = &plot, &spp
	for i := range flags {
		dest[2+i] = &flags[i]
	}

	for rows.Next() {
		if err := rows.Scan(dest...); err != nil {
			return err
		}
		k := grpKey{plot, spp}
		st, exists := stats[k]
		if !exists {
			st = &grpStat{layerCounts: make([]int, len(layerCols))}
			stats[k] = st
		} else if st.count == 1 {
			dupKeys = append(dupKeys, k)
		}
		st.count++
		for i, f := range flags {
			st.layerCounts[i] += f
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}

	slices.SortFunc(dupKeys, func(a, b grpKey) int {
		if cmp := strings.Compare(a.plot, b.plot); cmp != 0 {
			return cmp
		}
		return strings.Compare(a.spp, b.spp)
	})
	for _, k := range dupKeys {
		st := stats[k]
		var overlaps []string
		for i, lc := range layerCols {
			if st.layerCounts[i] > 1 {
				overlaps = append(overlaps, lc.code)
			}
		}
		report.DuplicateVegFindings = append(report.DuplicateVegFindings, DuplicateVegSpeciesFinding{
			PlotNumber:        k.plot,
			Species:           k.spp,
			RowCount:          st.count,
			OverlappingLayers: overlaps,
		})
	}
	return nil
}

func checkTaxonomyCompliance(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	useSU bool,
	suTextPlots map[string]struct{},
	suPlotList []string,
	report *ComplianceValidationReport,
) error {
	if useSU && len(suTextPlots) == 0 {
		return nil
	}
	vegTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Veg")
	_, vegTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Veg")
	if err != nil {
		return err
	}

	// Build fast lookup maps from USysAllSpecs and USysUserSpp.
	acceptedMaster := map[string]bool{}
	synonymToAccepted := map[string]string{}

	specRows, err := tx.QueryContext(ctx, `SELECT COALESCE(CAST("Code" AS TEXT), ''), COALESCE(CAST("OldCode" AS TEXT), ''), COALESCE(LOWER(CAST("Codetype" AS TEXT)), '') FROM "VLists"."USysAllSpecs"`)
	if err != nil {
		return err
	}
	for specRows.Next() {
		var code, oldCode, codeType string
		if err := specRows.Scan(&code, &oldCode, &codeType); err != nil {
			specRows.Close()
			return err
		}
		if code != "" && codeType != "s" {
			acceptedMaster[code] = true
		}
		if oldCode != "" && code != "" && oldCode != code {
			if _, exists := synonymToAccepted[oldCode]; !exists {
				synonymToAccepted[oldCode] = code
			}
		}
	}
	if err := errors.Join(specRows.Err(), specRows.Close()); err != nil {
		return err
	}

	userSpecies := map[string]bool{}
	uRows, err := tx.QueryContext(ctx, `SELECT COALESCE(CAST("Code" AS TEXT), '') FROM "VUser"."USysUserSpp"`)
	if err != nil {
		return err
	}
	for uRows.Next() {
		var code string
		if err := uRows.Scan(&code); err != nil {
			uRows.Close()
			return err
		}
		if code != "" {
			userSpecies[code] = true
		}
	}
	if err := errors.Join(uRows.Err(), uRows.Close()); err != nil {
		return err
	}

	whereSQL := ""
	var qArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`v."PlotNumber"`, vegTypes["plotnumber"], suPlotList); pre != "" {
			whereSQL = ` WHERE ` + pre
			qArgs = append(qArgs, args...)
		}
	}

	vRows, err := tx.QueryContext(ctx, `SELECT v.rowid, COALESCE(v."ID", 0), typeof(v."PlotNumber"), CAST(v."PlotNumber" AS BLOB), COALESCE(CAST(v."PlotNumber" AS TEXT), ''), v."Species"
		FROM `+vegTbl+` v`+whereSQL, qArgs...)
	if err != nil {
		return err
	}
	defer vRows.Close()

	for vRows.Next() {
		var rid, id int64
		var plotType, plot string
		var rawPlot []byte
		var spp sql.NullString
		if err := vRows.Scan(&rid, &id, &plotType, &rawPlot, &plot, &spp); err != nil {
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
		if !spp.Valid || strings.TrimSpace(spp.String) == "" {
			report.TaxonomyFindings = append(report.TaxonomyFindings, TaxonomyComplianceFinding{
				RowID: rid, ID: id, PlotNumber: plot, Species: "", Status: "missing",
			})
			report.Summary.UnlistedSpecies++
			continue
		}
		code := spp.String
		if acceptedMaster[code] {
			continue
		}
		if target, isSyn := synonymToAccepted[code]; isSyn {
			tCopy := target
			report.TaxonomyFindings = append(report.TaxonomyFindings, TaxonomyComplianceFinding{
				RowID: rid, ID: id, PlotNumber: plot, Species: code, Status: "synonym", SuggestedCode: &tCopy,
			})
			report.Summary.SynonymSpecies++
			continue
		}
		if userSpecies[code] {
			report.TaxonomyFindings = append(report.TaxonomyFindings, TaxonomyComplianceFinding{
				RowID: rid, ID: id, PlotNumber: plot, Species: code, Status: "user",
			})
			report.Summary.UserSpecies++
			continue
		}
		report.TaxonomyFindings = append(report.TaxonomyFindings, TaxonomyComplianceFinding{
			RowID: rid, ID: id, PlotNumber: plot, Species: code, Status: "unlisted",
		})
		report.Summary.UnlistedSpecies++
	}
	if err := vRows.Err(); err != nil {
		return err
	}
	slices.SortFunc(report.TaxonomyFindings, func(a, b TaxonomyComplianceFinding) int {
		if cmp := strings.Compare(a.PlotNumber, b.PlotNumber); cmp != 0 {
			return cmp
		}
		if a.RowID < b.RowID {
			return -1
		}
		if a.RowID > b.RowID {
			return 1
		}
		return 0
	})
	return nil
}
