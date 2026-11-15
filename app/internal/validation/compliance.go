package validation

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"slices"
	"strconv"
	"strings"
)

// RunComplianceValidation executes the unified Pre-Flight & Standards Compliance gate (Auto-4):
// 1. VLists.USysTableOfLists (Validate <> 0) code compliance
// 2. Numeric, IEEE-754 float32 <100 cover, LMH25 soil horizon sign, and UTF-16 length bounds
// 3. 1:1 _Env <-> _Admin completeness
// 4. 1:N foreign key integrity (_Veg, _Humus, _Mineral, _Other, _Audit, *_SU)
// 5. Duplicate (PlotNumber, Species) strata splits & same-layer cover duplicates
// 6. USysAllSpecs & USysUserSpp species code taxonomy checks (including OldCode -> Code synonyms).
func RunComplianceValidation(s *vprocore.ContextService, ctx context.Context, contextID string, opts ComplianceOptions) (ComplianceValidationReport, error) {
	if s == nil {
		return ComplianceValidationReport{}, errors.New("validation context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (report ComplianceValidationReport, resultErr error) {
		owner := plots.Projects.Sqlite
		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return report, err
		}
		defer owner.Mu.Unlock()
		if owner.Conn == nil {
			return report, errors.New("project context is closed")
		}

		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return report, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		project := owner.Selection.Project
		activeSU := owner.Selection.SU
		useSU := opts.UseActiveSU && activeSU != "None"

		report = ComplianceValidationReport{
			Project:                project,
			SU:                     activeSU,
			UseActiveSU:            useSU,
			EnvCodeFindings:        []EnvironmentCodeFinding{},
			SkippedDefinitions:     []SkippedListDefinition{},
			BoundsFindings:         []BoundsFinding{},
			EnvAdminFindings:       []EnvAdminCompletenessFinding{},
			OrphanFindings:         []OrphanChildFinding{},
			PlotsWithoutVegetation: []string{},
			DuplicateVegFindings:   []DuplicateVegSpeciesFinding{},
			TaxonomyFindings:       []TaxonomyComplianceFinding{},
		}

		envTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
		adminTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")

		type plotKeyEntry struct {
			isText  bool
			rawKey  string
			display string
		}
		var envOrdered []plotKeyEntry
		envTextPlots := map[string]struct{}{}

		envScanRows, err := tx.QueryContext(ctx, `SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>')
			FROM `+envTbl+`
			ORDER BY "PlotNumber"`)
		if err != nil {
			return report, err
		}
		for envScanRows.Next() {
			var pType, disp string
			var raw []byte
			if err := envScanRows.Scan(&pType, &raw, &disp); err != nil {
				envScanRows.Close()
				return report, err
			}
			isText := pType == "text"
			rawStr := string(raw)
			if isText {
				envTextPlots[rawStr] = struct{}{}
			}
			envOrdered = append(envOrdered, plotKeyEntry{isText: isText, rawKey: rawStr, display: disp})
		}
		if err := errors.Join(envScanRows.Err(), envScanRows.Close()); err != nil {
			return report, err
		}

		suTextPlots := map[string]struct{}{}
		var suPlotList []string
		suOrphanCounts := map[string]int{}
		if activeSU != "None" {
			suTbl := `"su".` + vprocore.QuoteHeaderIdentifier(activeSU+"_SU")
			suRows, suErr := tx.QueryContext(ctx, `SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>')
				FROM `+suTbl)
			if suErr != nil {
				return report, suErr
			}
			for suRows.Next() {
				var pType, disp string
				var raw []byte
				if err := suRows.Scan(&pType, &raw, &disp); err != nil {
					suRows.Close()
					return report, err
				}
				rawStr := string(raw)
				if pType == "text" {
					if _, seen := suTextPlots[rawStr]; !seen {
						suTextPlots[rawStr] = struct{}{}
						suPlotList = append(suPlotList, rawStr)
					}
					if _, ok := envTextPlots[rawStr]; !ok {
						suOrphanCounts[disp]++
					}
				} else {
					suOrphanCounts[disp]++
				}
			}
			if err := errors.Join(suRows.Err(), suRows.Close()); err != nil {
				return report, err
			}
		}

		// 1. 1:1 _Env <-> _Admin completeness (scoped by UseActiveSU when enabled).
		adminTextPlots := make(map[string]struct{}, len(envTextPlots))
		var orphanAdmins []plotKeyEntry
		adminScanRows, err := tx.QueryContext(ctx, `SELECT typeof("Plot"), CAST("Plot" AS BLOB), COALESCE(CAST("Plot" AS TEXT), '<NULL>')
			FROM `+adminTbl+`
			ORDER BY "Plot"`)
		if err != nil {
			return report, err
		}
		for adminScanRows.Next() {
			var pType, disp string
			var raw []byte
			if err := adminScanRows.Scan(&pType, &raw, &disp); err != nil {
				adminScanRows.Close()
				return report, err
			}
			rawStr := string(raw)
			if pType == "text" {
				adminTextPlots[rawStr] = struct{}{}
				if _, ok := envTextPlots[rawStr]; !ok {
					orphanAdmins = append(orphanAdmins, plotKeyEntry{isText: true, rawKey: rawStr, display: disp})
				}
			} else {
				orphanAdmins = append(orphanAdmins, plotKeyEntry{isText: false, rawKey: rawStr, display: disp})
			}
		}
		if err := errors.Join(adminScanRows.Err(), adminScanRows.Close()); err != nil {
			return report, err
		}

		for _, eRow := range envOrdered {
			if useSU {
				if !eRow.isText {
					continue
				}
				if _, inSU := suTextPlots[eRow.rawKey]; !inSU {
					continue
				}
			}
			if !eRow.isText {
				report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{
					PlotNumber: eRow.display,
					Issue:      "missing_admin",
				})
				continue
			}
			if _, ok := adminTextPlots[eRow.rawKey]; !ok {
				report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{
					PlotNumber: eRow.display,
					Issue:      "missing_admin",
				})
			}
		}
		for _, aRow := range orphanAdmins {
			if useSU {
				if !aRow.isText {
					continue
				}
				if _, inSU := suTextPlots[aRow.rawKey]; !inSU {
					continue
				}
			}
			report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{
				PlotNumber: aRow.display,
				Issue:      "orphan_admin",
			})
		}
		report.Summary.EnvAdminMismatches = len(report.EnvAdminFindings)

		// 2. 1:N Foreign Key Integrity across _Veg, _Humus, _Mineral, _Other, _Audit, and active *_SU.
		vegTextPlots := make(map[string]struct{}, len(envTextPlots))
		for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other", "Audit"} {
			childTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_"+suffix)
			whereClause := ""
			if suffix == "Audit" {
				// System-level audit entries (e.g. NewProject, USysAllSpecs) legitimately have NULL PlotNumber.
				whereClause = ` WHERE "PlotNumber" IS NOT NULL AND CAST("PlotNumber" AS TEXT) <> ''`
			}
			cRows, cErr := tx.QueryContext(ctx, `SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>'), COUNT(*)
				FROM `+childTbl+whereClause+`
				GROUP BY "PlotNumber", typeof("PlotNumber"), CAST("PlotNumber" AS BLOB)`)
			if cErr != nil {
				return report, cErr
			}
			orphanCounts := map[string]int{}
			for cRows.Next() {
				var pType, disp string
				var raw []byte
				var grpCnt int
				if err := cRows.Scan(&pType, &raw, &disp, &grpCnt); err != nil {
					cRows.Close()
					return report, err
				}
				rawStr := string(raw)
				if suffix == "Veg" && pType == "text" {
					vegTextPlots[rawStr] = struct{}{}
				}
				if pType != "text" {
					orphanCounts[disp] += grpCnt
				} else if _, ok := envTextPlots[rawStr]; !ok {
					orphanCounts[disp] += grpCnt
				}
			}
			if err := errors.Join(cRows.Err(), cRows.Close()); err != nil {
				return report, err
			}
			if len(orphanCounts) > 0 {
				keys := make([]string, 0, len(orphanCounts))
				for k := range orphanCounts {
					keys = append(keys, k)
				}
				slices.Sort(keys)
				for _, k := range keys {
					cnt := orphanCounts[k]
					report.OrphanFindings = append(report.OrphanFindings, OrphanChildFinding{
						Table:      suffix,
						PlotNumber: k,
						RowCount:   cnt,
					})
					if suffix != "Audit" {
						report.Summary.OrphanChildRows += cnt
					}
				}
			}
		}

		if len(suOrphanCounts) > 0 {
			keys := make([]string, 0, len(suOrphanCounts))
			for k := range suOrphanCounts {
				keys = append(keys, k)
			}
			slices.Sort(keys)
			for _, k := range keys {
				cnt := suOrphanCounts[k]
				report.OrphanFindings = append(report.OrphanFindings, OrphanChildFinding{
					Table:      "SU",
					PlotNumber: k,
					RowCount:   cnt,
				})
				report.Summary.OrphanChildRows += cnt
			}
		}

		// Plots without vegetation (respects UseActiveSU).
		for _, eRow := range envOrdered {
			if useSU {
				if !eRow.isText {
					continue
				}
				if _, inSU := suTextPlots[eRow.rawKey]; !inSU {
					continue
				}
			}
			if !eRow.isText {
				report.PlotsWithoutVegetation = append(report.PlotsWithoutVegetation, eRow.display)
				continue
			}
			if _, hasVeg := vegTextPlots[eRow.rawKey]; !hasVeg {
				report.PlotsWithoutVegetation = append(report.PlotsWithoutVegetation, eRow.display)
			}
		}
		report.Summary.PlotsWithoutVeg = len(report.PlotsWithoutVegetation)

		// 3. VLists.USysTableOfLists (Validate <> 0) code compliance.
		envCols, envTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Env")
		if err != nil {
			return report, err
		}
		adminCols, adminTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Admin")
		if err != nil {
			return report, err
		}

		defRows, err := tx.QueryContext(ctx, `SELECT COALESCE(MIN("ListName"), ''), COALESCE(MIN("FieldUsedIn"), ''), COALESCE(CAST("ValidateLoops" AS TEXT), '')
			FROM "VLists"."USysTableOfLists"
			WHERE "Validate" <> 0
			GROUP BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"
			ORDER BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"`)
		if err != nil {
			return report, err
		}
		type listDef struct {
			listName, fieldUsedIn, loops string
		}
		var defs []listDef
		for defRows.Next() {
			var d listDef
			if err := defRows.Scan(&d.listName, &d.fieldUsedIn, &d.loops); err != nil {
				defRows.Close()
				return report, err
			}
			defs = append(defs, d)
		}
		if err := errors.Join(defRows.Err(), defRows.Close()); err != nil {
			return report, err
		}

		validItemsByList := map[string]map[string]struct{}{}
		itemRows, err := tx.QueryContext(ctx, `SELECT COALESCE(CAST("ListName" AS TEXT), ''), COALESCE(CAST("Item" AS TEXT), '')
			FROM "VLists"."USysTableOfLists"
			WHERE "ListName" IS NOT NULL AND "Item" IS NOT NULL`)
		if err != nil {
			return report, err
		}
		for itemRows.Next() {
			var ln, it string
			if err := itemRows.Scan(&ln, &it); err != nil {
				itemRows.Close()
				return report, err
			}
			lnKey := asciiLower(ln)
			m := validItemsByList[lnKey]
			if m == nil {
				m = map[string]struct{}{}
				validItemsByList[lnKey] = m
			}
			m[asciiLower(it)] = struct{}{}
		}
		if err := errors.Join(itemRows.Err(), itemRows.Close()); err != nil {
			return report, err
		}

		type expandedCodeCheck struct {
			listName    string
			listLower   string
			field       string
			inAdmin     bool
			colActual   string
			colScanSlot int
			findingsSet map[[2]string]struct{}
		}
		var checks []*expandedCodeCheck
		var envCheckCols []string
		envColSlot := map[string]int{}
		var adminCheckCols []string
		adminColSlot := map[string]int{}

		for _, d := range defs {
			if err := ctx.Err(); err != nil {
				return report, err
			}
			if strings.TrimSpace(d.listName) == "" {
				report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, d.fieldUsedIn, "ListName is blank"})
				continue
			}
			if strings.TrimSpace(d.fieldUsedIn) == "" {
				report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, d.fieldUsedIn, "FieldUsedIn is blank"})
				continue
			}
			expandedFields := []string{d.fieldUsedIn}
			if strings.TrimSpace(d.loops) != "" {
				nLoops, pErr := strconv.Atoi(strings.TrimSpace(d.loops))
				if pErr != nil {
					report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, d.fieldUsedIn, "ValidateLoops is not an integer"})
					continue
				}
				if nLoops > 0 {
					expandedFields = make([]string, nLoops)
					for idx := 1; idx <= nLoops; idx++ {
						expandedFields[idx-1] = fmt.Sprintf("%s%d", d.fieldUsedIn, idx)
					}
				}
			}

			for _, field := range expandedFields {
				lowerF := strings.ToLower(field)
				envActual, inEnv := envCols[lowerF]
				adminActual, inAdmin := adminCols[lowerF]
				if inEnv && inAdmin {
					report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, field, "Field is ambiguous across Env and Admin"})
					continue
				}
				if !inEnv && !inAdmin {
					report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, field, "Field does not exist in active Env/Admin schema"})
					continue
				}
				chk := &expandedCodeCheck{
					listName:    d.listName,
					listLower:   asciiLower(d.listName),
					field:       field,
					inAdmin:     inAdmin,
					findingsSet: map[[2]string]struct{}{},
				}
				if inAdmin {
					chk.colActual = adminActual
					slot, ok := adminColSlot[adminActual]
					if !ok {
						slot = len(adminCheckCols)
						adminColSlot[adminActual] = slot
						adminCheckCols = append(adminCheckCols, adminActual)
					}
					chk.colScanSlot = slot
				} else {
					chk.colActual = envActual
					slot, ok := envColSlot[envActual]
					if !ok {
						slot = len(envCheckCols)
						envColSlot[envActual] = slot
						envCheckCols = append(envCheckCols, envActual)
					}
					chk.colScanSlot = slot
				}
				checks = append(checks, chk)
			}
		}

		qualifiesForEnvCodeCheck := func(rawPlot string) bool {
			if _, ok := envTextPlots[rawPlot]; !ok {
				return false
			}
			if _, ok := adminTextPlots[rawPlot]; !ok {
				return false
			}
			if useSU {
				if _, ok := suTextPlots[rawPlot]; !ok {
					return false
				}
			}
			return true
		}

		scanTableForCodeChecks := func(tblExpr, plotCol, plotDecl string, cols []string, wantAdmin bool) error {
			if len(cols) == 0 || (useSU && len(suTextPlots) == 0) {
				return nil
			}
			qPlot := vprocore.QuoteHeaderIdentifier(plotCol)
			selParts := make([]string, 0, 2+len(cols))
			selParts = append(selParts, `CAST(`+qPlot+` AS BLOB)`, `CAST(`+qPlot+` AS TEXT)`)
			for _, c := range cols {
				selParts = append(selParts, `CAST(`+vprocore.QuoteHeaderIdentifier(c)+` AS TEXT)`)
			}
			whereSQL := ` WHERE typeof(` + qPlot + `)='text'`
			var qArgs []any
			if useSU {
				if pre, args := buildSUPlotInPreFilter(qPlot, plotDecl, suPlotList); pre != "" {
					whereSQL += ` AND ` + pre
					qArgs = append(qArgs, args...)
				}
			}
			rows, err := tx.QueryContext(ctx, `SELECT `+strings.Join(selParts, ", ")+` FROM `+tblExpr+whereSQL, qArgs...)
			if err != nil {
				return err
			}
			defer rows.Close()

			vals := make([]sql.NullString, len(cols))
			var rawPlot []byte
			var plotStr string
			dest := make([]any, 2+len(cols))
			dest[0] = &rawPlot
			dest[1] = &plotStr
			for i := range vals {
				dest[2+i] = &vals[i]
			}

			for rows.Next() {
				if err := rows.Scan(dest...); err != nil {
					return err
				}
				if !qualifiesForEnvCodeCheck(string(rawPlot)) {
					continue
				}
				for _, chk := range checks {
					if chk.inAdmin != wantAdmin {
						continue
					}
					cell := vals[chk.colScanSlot]
					if !cell.Valid || cell.String == "" {
						continue
					}
					allowed := validItemsByList[chk.listLower]
					if _, ok := allowed[asciiLower(cell.String)]; !ok {
						chk.findingsSet[[2]string{plotStr, cell.String}] = struct{}{}
					}
				}
			}
			return rows.Err()
		}

		if err := scanTableForCodeChecks(envTbl, "PlotNumber", envTypes["plotnumber"], envCheckCols, false); err != nil {
			return report, err
		}
		if err := scanTableForCodeChecks(adminTbl, "Plot", adminTypes["plot"], adminCheckCols, true); err != nil {
			return report, err
		}

		for _, chk := range checks {
			if len(chk.findingsSet) == 0 {
				continue
			}
			pairs := make([][2]string, 0, len(chk.findingsSet))
			for pair := range chk.findingsSet {
				pairs = append(pairs, pair)
			}
			slices.SortFunc(pairs, func(a, b [2]string) int {
				if cmp := strings.Compare(a[0], b[0]); cmp != 0 {
					return cmp
				}
				return strings.Compare(a[1], b[1])
			})
			for _, pair := range pairs {
				report.EnvCodeFindings = append(report.EnvCodeFindings, EnvironmentCodeFinding{
					ListName:   chk.listName,
					Field:      chk.field,
					PlotNumber: pair[0],
					Value:      pair[1],
				})
			}
		}
		report.Summary.EnvCodeErrors = len(report.EnvCodeFindings)

		// 4. UTF-16, Numeric, IEEE-754 float32 <100 cover, and LMH25 soil horizon sign bounds.
		if err := checkProjectBounds(ctx, tx, project, useSU, suTextPlots, suPlotList, envCols, envTypes, adminCols, adminTypes, &report); err != nil {
			return report, err
		}
		report.Summary.BoundsErrors = len(report.BoundsFindings)

		// 5. Duplicate (PlotNumber, Species) strata splits & overlapping layer covers.
		if err := checkDuplicateVegSpecies(ctx, tx, project, useSU, suTextPlots, suPlotList, &report); err != nil {
			return report, err
		}
		report.Summary.DuplicateSpeciesSplits = len(report.DuplicateVegFindings)

		// 6. USysAllSpecs & USysUserSpp species taxonomy compliance.
		if err := checkTaxonomyCompliance(ctx, tx, project, useSU, suTextPlots, suPlotList, &report); err != nil {
			return report, err
		}

		// Passed is true when there are zero compliance violations.
		report.Passed = report.Summary.EnvCodeErrors == 0 &&
			report.Summary.BoundsErrors == 0 &&
			report.Summary.EnvAdminMismatches == 0 &&
			report.Summary.OrphanChildRows == 0 &&
			report.Summary.DuplicateSpeciesSplits == 0 &&
			report.Summary.UnlistedSpecies == 0 &&
			report.Summary.SynonymSpecies == 0

		if err := ctx.Err(); err != nil {
			return report, err
		}
		if err := tx.Commit(); err != nil {
			return report, err
		}
		return report, nil
	})
}
