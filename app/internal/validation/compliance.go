package validation

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type compliancePlotKeyEntry struct {
	isText  bool
	rawKey  string
	display string
}

type compliancePlotKeySets struct {
	envOrdered     []compliancePlotKeyEntry
	envTextPlots   map[string]struct{}
	suTextPlots    map[string]struct{}
	suPlotList     []string
	suOrphanCounts map[string]int
	adminTextPlots map[string]struct{}
	orphanAdmins   []compliancePlotKeyEntry
}

type complianceListDef struct {
	listName, fieldUsedIn, loops string
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

		return runComplianceValidationSnapshot(ctx, tx, owner.Selection.Project, owner.Selection.SU, opts)
	})
}

func runComplianceValidationSnapshot(
	ctx context.Context,
	tx *sql.Tx,
	project, activeSU string,
	opts ComplianceOptions,
) (ComplianceValidationReport, error) {
	useSU := opts.UseActiveSU && activeSU != "None"
	report := newEmptyComplianceReport(project, activeSU, useSU)

	envTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	adminTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	keys, err := scanCompliancePlotKeys(ctx, tx, envTbl, adminTbl, activeSU)
	if err != nil {
		return report, err
	}
	populateEnvAdminCompleteness(keys, useSU, &report)

	envCols, envTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Env")
	if err != nil {
		return report, err
	}
	adminCols, adminTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Admin")
	if err != nil {
		return report, err
	}

	if err := checkOrphanChildAndSURows(ctx, tx, project, envTbl, envTypes["plotnumber"], keys.suOrphanCounts, &report); err != nil {
		return report, err
	}
	if err := checkPlotsWithoutVegetation(ctx, tx, project, useSU, keys, &report); err != nil {
		return report, err
	}
	if err := checkVListsEnvCodeCompliance(ctx, tx, envTbl, adminTbl, useSU, keys, envCols, envTypes, adminCols, adminTypes, &report); err != nil {
		return report, err
	}
	if err := checkProjectBounds(ctx, tx, project, useSU, keys.suTextPlots, keys.suPlotList, envCols, envTypes, adminCols, adminTypes, &report); err != nil {
		return report, err
	}
	report.Summary.BoundsErrors = len(report.BoundsFindings)

	if err := checkDuplicateVegSpecies(ctx, tx, project, useSU, keys.suTextPlots, keys.suPlotList, &report); err != nil {
		return report, err
	}
	report.Summary.DuplicateSpeciesSplits = len(report.DuplicateVegFindings)

	if err := checkTaxonomyCompliance(ctx, tx, project, useSU, keys.suTextPlots, keys.suPlotList, &report); err != nil {
		return report, err
	}

	report.Passed = isComplianceReportClean(report.Summary)
	if err := ctx.Err(); err != nil {
		return report, err
	}
	if err := tx.Commit(); err != nil {
		return report, err
	}
	return report, nil
}

func newEmptyComplianceReport(project, activeSU string, useSU bool) ComplianceValidationReport {
	return ComplianceValidationReport{
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
}

func isComplianceReportClean(s ComplianceSummaryCounts) bool {
	return s.EnvCodeErrors == 0 &&
		s.BoundsErrors == 0 &&
		s.EnvAdminMismatches == 0 &&
		s.OrphanChildRows == 0 &&
		s.DuplicateSpeciesSplits == 0 &&
		s.UnlistedSpecies == 0 &&
		s.SynonymSpecies == 0
}

func scanCompliancePlotKeys(
	ctx context.Context,
	tx *sql.Tx,
	envTbl, adminTbl, activeSU string,
) (compliancePlotKeySets, error) {
	keys := compliancePlotKeySets{
		envTextPlots:   map[string]struct{}{},
		suTextPlots:    map[string]struct{}{},
		suOrphanCounts: map[string]int{},
	}
	if err := scanEnvPlotKeys(ctx, tx, envTbl, &keys); err != nil {
		return keys, err
	}
	if activeSU != "None" {
		if err := scanSUPlotKeys(ctx, tx, activeSU, &keys); err != nil {
			return keys, err
		}
	}
	if err := scanAdminPlotKeys(ctx, tx, adminTbl, &keys); err != nil {
		return keys, err
	}
	return keys, nil
}

func scanEnvPlotKeys(ctx context.Context, tx *sql.Tx, envTbl string, keys *compliancePlotKeySets) error {
	rows, err := tx.QueryContext(ctx, `SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>')
		FROM `+envTbl+`
		ORDER BY "PlotNumber"`)
	if err != nil {
		return err
	}
	for rows.Next() {
		var pType, disp string
		var raw []byte
		if err := rows.Scan(&pType, &raw, &disp); err != nil {
			rows.Close()
			return err
		}
		isText := pType == "text"
		rawStr := string(raw)
		if isText {
			keys.envTextPlots[rawStr] = struct{}{}
		}
		keys.envOrdered = append(keys.envOrdered, compliancePlotKeyEntry{isText: isText, rawKey: rawStr, display: disp})
	}
	return errors.Join(rows.Err(), rows.Close())
}

func scanSUPlotKeys(ctx context.Context, tx *sql.Tx, activeSU string, keys *compliancePlotKeySets) error {
	suTbl := `"su".` + vprocore.QuoteHeaderIdentifier(activeSU+"_SU")
	rows, err := tx.QueryContext(ctx, `SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>')
		FROM `+suTbl)
	if err != nil {
		return err
	}
	for rows.Next() {
		var pType, disp string
		var raw []byte
		if err := rows.Scan(&pType, &raw, &disp); err != nil {
			rows.Close()
			return err
		}
		rawStr := string(raw)
		if pType != "text" {
			keys.suOrphanCounts[disp]++
			continue
		}
		if _, seen := keys.suTextPlots[rawStr]; !seen {
			keys.suTextPlots[rawStr] = struct{}{}
			keys.suPlotList = append(keys.suPlotList, rawStr)
		}
		if _, ok := keys.envTextPlots[rawStr]; !ok {
			keys.suOrphanCounts[disp]++
		}
	}
	return errors.Join(rows.Err(), rows.Close())
}

func scanAdminPlotKeys(ctx context.Context, tx *sql.Tx, adminTbl string, keys *compliancePlotKeySets) error {
	keys.adminTextPlots = make(map[string]struct{}, len(keys.envTextPlots))
	rows, err := tx.QueryContext(ctx, `SELECT typeof("Plot"), CAST("Plot" AS BLOB), COALESCE(CAST("Plot" AS TEXT), '<NULL>')
		FROM `+adminTbl+`
		ORDER BY "Plot"`)
	if err != nil {
		return err
	}
	for rows.Next() {
		var pType, disp string
		var raw []byte
		if err := rows.Scan(&pType, &raw, &disp); err != nil {
			rows.Close()
			return err
		}
		rawStr := string(raw)
		if pType == "text" {
			keys.adminTextPlots[rawStr] = struct{}{}
			if _, ok := keys.envTextPlots[rawStr]; !ok {
				keys.orphanAdmins = append(keys.orphanAdmins, compliancePlotKeyEntry{isText: true, rawKey: rawStr, display: disp})
			}
		} else {
			keys.orphanAdmins = append(keys.orphanAdmins, compliancePlotKeyEntry{isText: false, rawKey: rawStr, display: disp})
		}
	}
	return errors.Join(rows.Err(), rows.Close())
}

func populateEnvAdminCompleteness(keys compliancePlotKeySets, useSU bool, report *ComplianceValidationReport) {
	for _, eRow := range keys.envOrdered {
		if !rowInComplianceScope(eRow, useSU, keys.suTextPlots) {
			continue
		}
		if !eRow.isText {
			report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{PlotNumber: eRow.display, Issue: "missing_admin"})
			continue
		}
		if _, ok := keys.adminTextPlots[eRow.rawKey]; !ok {
			report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{PlotNumber: eRow.display, Issue: "missing_admin"})
		}
	}
	for _, aRow := range keys.orphanAdmins {
		if !rowInComplianceScope(aRow, useSU, keys.suTextPlots) {
			continue
		}
		report.EnvAdminFindings = append(report.EnvAdminFindings, EnvAdminCompletenessFinding{PlotNumber: aRow.display, Issue: "orphan_admin"})
	}
	report.Summary.EnvAdminMismatches = len(report.EnvAdminFindings)
}

func rowInComplianceScope(row compliancePlotKeyEntry, useSU bool, suTextPlots map[string]struct{}) bool {
	if !useSU {
		return true
	}
	if !row.isText {
		return false
	}
	_, inSU := suTextPlots[row.rawKey]
	return inSU
}

func checkOrphanChildAndSURows(
	ctx context.Context,
	tx *sql.Tx,
	project, envTbl, envPlotType string,
	suOrphanCounts map[string]int,
	report *ComplianceValidationReport,
) error {
	envIdxEq := ""
	if isTextOrNoneAffinityType(envPlotType) {
		envIdxEq = `e."PlotNumber" = c."PlotNumber" AND `
	}
	for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other", "Audit"} {
		orphanCounts, err := queryOrphanChildCounts(ctx, tx, project, suffix, envTbl, envIdxEq)
		if err != nil {
			return err
		}
		appendSortedOrphanFindings(suffix, orphanCounts, suffix != "Audit", report)
	}
	appendSortedOrphanFindings("SU", suOrphanCounts, true, report)
	return nil
}

func queryOrphanChildCounts(
	ctx context.Context,
	tx *sql.Tx,
	project, suffix, envTbl, envIdxEq string,
) (map[string]int, error) {
	childTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_"+suffix)
	auditFilter := ""
	if suffix == "Audit" {
		// System-level audit entries (e.g. NewProject, USysAllSpecs) legitimately have NULL PlotNumber.
		auditFilter = `c."PlotNumber" IS NOT NULL AND CAST(c."PlotNumber" AS TEXT) <> '' AND `
	}
	orphanQuery := `SELECT COALESCE(CAST(c."PlotNumber" AS TEXT), '<NULL>'), COUNT(*)
		FROM ` + childTbl + ` c
		WHERE ` + auditFilter + `(
			typeof(c."PlotNumber") <> 'text'
			OR NOT EXISTS (
				SELECT 1 FROM ` + envTbl + ` e
				WHERE ` + envIdxEq + `typeof(e."PlotNumber") = 'text'
					AND CAST(e."PlotNumber" AS BLOB) = CAST(c."PlotNumber" AS BLOB)
			)
		)
		GROUP BY COALESCE(CAST(c."PlotNumber" AS TEXT), '<NULL>')`
	cRows, err := tx.QueryContext(ctx, orphanQuery)
	if err != nil {
		return nil, err
	}
	orphanCounts := map[string]int{}
	for cRows.Next() {
		var disp string
		var grpCnt int
		if err := cRows.Scan(&disp, &grpCnt); err != nil {
			cRows.Close()
			return nil, err
		}
		orphanCounts[disp] += grpCnt
	}
	return orphanCounts, errors.Join(cRows.Err(), cRows.Close())
}

func appendSortedOrphanFindings(table string, orphanCounts map[string]int, countTowardSummary bool, report *ComplianceValidationReport) {
	if len(orphanCounts) == 0 {
		return
	}
	keys := make([]string, 0, len(orphanCounts))
	for k := range orphanCounts {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	for _, k := range keys {
		cnt := orphanCounts[k]
		report.OrphanFindings = append(report.OrphanFindings, OrphanChildFinding{
			Table:      table,
			PlotNumber: k,
			RowCount:   cnt,
		})
		if countTowardSummary {
			report.Summary.OrphanChildRows += cnt
		}
	}
}

func checkPlotsWithoutVegetation(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	useSU bool,
	keys compliancePlotKeySets,
	report *ComplianceValidationReport,
) error {
	vegTextPlots := map[string]struct{}{}
	if !useSU || len(keys.suPlotList) > 0 {
		if err := loadVegTextPlots(ctx, tx, project, useSU, keys.suPlotList, vegTextPlots); err != nil {
			return err
		}
	}
	for _, eRow := range keys.envOrdered {
		if !rowInComplianceScope(eRow, useSU, keys.suTextPlots) {
			continue
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
	return nil
}

func loadVegTextPlots(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	useSU bool,
	suPlotList []string,
	vegTextPlots map[string]struct{},
) error {
	vegTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Veg")
	_, vegTypes, err := readTableColumnTypes(ctx, tx, "project", project+"_Veg")
	if err != nil {
		return err
	}
	vegPlotWhere := ` WHERE typeof("PlotNumber") = 'text'`
	var vegPlotArgs []any
	if useSU {
		if pre, args := buildSUPlotInPreFilter(`"PlotNumber"`, vegTypes["plotnumber"], suPlotList); pre != "" {
			vegPlotWhere += ` AND ` + pre
			vegPlotArgs = append(vegPlotArgs, args...)
		}
	}
	rows, err := tx.QueryContext(ctx, `SELECT DISTINCT CAST("PlotNumber" AS BLOB) FROM `+vegTbl+vegPlotWhere, vegPlotArgs...)
	if err != nil {
		return err
	}
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			rows.Close()
			return err
		}
		vegTextPlots[string(raw)] = struct{}{}
	}
	return errors.Join(rows.Err(), rows.Close())
}

func checkVListsEnvCodeCompliance(
	ctx context.Context,
	tx *sql.Tx,
	envTbl, adminTbl string,
	useSU bool,
	keys compliancePlotKeySets,
	envCols, envTypes, adminCols, adminTypes map[string]string,
	report *ComplianceValidationReport,
) error {
	defs, validItemsByList, err := loadVListsCodeDefinitions(ctx, tx)
	if err != nil {
		return err
	}
	checks, envCheckCols, adminCheckCols, err := expandCodeCheckDefinitions(ctx, defs, envCols, adminCols, report)
	if err != nil {
		return err
	}
	if err := scanTableForCodeChecks(ctx, tx, envTbl, "PlotNumber", envTypes["plotnumber"], envCheckCols, false, useSU, keys, checks, validItemsByList); err != nil {
		return err
	}
	if err := scanTableForCodeChecks(ctx, tx, adminTbl, "Plot", adminTypes["plot"], adminCheckCols, true, useSU, keys, checks, validItemsByList); err != nil {
		return err
	}
	appendCodeCheckFindings(checks, report)
	return nil
}

func loadVListsCodeDefinitions(
	ctx context.Context,
	tx *sql.Tx,
) ([]complianceListDef, map[string]map[string]struct{}, error) {
	defRows, err := tx.QueryContext(ctx, `SELECT COALESCE(MIN("ListName"), ''), COALESCE(MIN("FieldUsedIn"), ''), COALESCE(CAST("ValidateLoops" AS TEXT), '')
		FROM "VLists"."USysTableOfLists"
		WHERE "Validate" <> 0
		GROUP BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"
		ORDER BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"`)
	if err != nil {
		return nil, nil, err
	}
	var defs []complianceListDef
	for defRows.Next() {
		var d complianceListDef
		if err := defRows.Scan(&d.listName, &d.fieldUsedIn, &d.loops); err != nil {
			defRows.Close()
			return nil, nil, err
		}
		defs = append(defs, d)
	}
	if err := errors.Join(defRows.Err(), defRows.Close()); err != nil {
		return nil, nil, err
	}

	validItemsByList := map[string]map[string]struct{}{}
	itemRows, err := tx.QueryContext(ctx, `SELECT COALESCE(CAST("ListName" AS TEXT), ''), COALESCE(CAST("Item" AS TEXT), '')
		FROM "VLists"."USysTableOfLists"
		WHERE "ListName" IS NOT NULL AND "Item" IS NOT NULL`)
	if err != nil {
		return nil, nil, err
	}
	for itemRows.Next() {
		var ln, it string
		if err := itemRows.Scan(&ln, &it); err != nil {
			itemRows.Close()
			return nil, nil, err
		}
		lnKey := asciiLower(ln)
		if validItemsByList[lnKey] == nil {
			validItemsByList[lnKey] = map[string]struct{}{}
		}
		validItemsByList[lnKey][asciiLower(it)] = struct{}{}
	}
	return defs, validItemsByList, errors.Join(itemRows.Err(), itemRows.Close())
}

func expandCodeCheckDefinitions(
	ctx context.Context,
	defs []complianceListDef,
	envCols, adminCols map[string]string,
	report *ComplianceValidationReport,
) ([]*expandedCodeCheck, []string, []string, error) {
	var checks []*expandedCodeCheck
	var envCheckCols, adminCheckCols []string
	envColSlot := map[string]int{}
	adminColSlot := map[string]int{}

	for _, d := range defs {
		if err := ctx.Err(); err != nil {
			return nil, nil, nil, err
		}
		expandedFields, skipReason := expandValidateLoopFields(d)
		if skipReason != "" {
			report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, d.fieldUsedIn, skipReason})
			continue
		}
		for _, field := range expandedFields {
			chk, fieldSkip := buildFieldCodeCheck(d.listName, field, envCols, adminCols, envColSlot, &envCheckCols, adminColSlot, &adminCheckCols)
			if fieldSkip != "" {
				report.SkippedDefinitions = append(report.SkippedDefinitions, SkippedListDefinition{d.listName, field, fieldSkip})
				continue
			}
			checks = append(checks, chk)
		}
	}
	return checks, envCheckCols, adminCheckCols, nil
}

func expandValidateLoopFields(d complianceListDef) ([]string, string) {
	if strings.TrimSpace(d.listName) == "" {
		return nil, "ListName is blank"
	}
	if strings.TrimSpace(d.fieldUsedIn) == "" {
		return nil, "FieldUsedIn is blank"
	}
	trimmedLoops := strings.TrimSpace(d.loops)
	if trimmedLoops == "" {
		return []string{d.fieldUsedIn}, ""
	}
	nLoops, err := strconv.Atoi(trimmedLoops)
	if err != nil {
		return nil, "ValidateLoops is not an integer"
	}
	if nLoops <= 0 {
		return []string{d.fieldUsedIn}, ""
	}
	fields := make([]string, nLoops)
	for idx := 1; idx <= nLoops; idx++ {
		fields[idx-1] = fmt.Sprintf("%s%d", d.fieldUsedIn, idx)
	}
	return fields, ""
}

func buildFieldCodeCheck(
	listName, field string,
	envCols, adminCols map[string]string,
	envColSlot map[string]int, envCheckCols *[]string,
	adminColSlot map[string]int, adminCheckCols *[]string,
) (*expandedCodeCheck, string) {
	lowerF := strings.ToLower(field)
	envActual, inEnv := envCols[lowerF]
	adminActual, inAdmin := adminCols[lowerF]
	if inEnv && inAdmin {
		return nil, "Field is ambiguous across Env and Admin"
	}
	if !inEnv && !inAdmin {
		return nil, "Field does not exist in active Env/Admin schema"
	}
	chk := &expandedCodeCheck{
		listName:    listName,
		listLower:   asciiLower(listName),
		field:       field,
		inAdmin:     inAdmin,
		findingsSet: map[[2]string]struct{}{},
	}
	if inAdmin {
		chk.colActual = adminActual
		chk.colScanSlot = ensureScanColumnSlot(adminActual, adminColSlot, adminCheckCols)
	} else {
		chk.colActual = envActual
		chk.colScanSlot = ensureScanColumnSlot(envActual, envColSlot, envCheckCols)
	}
	return chk, ""
}

func ensureScanColumnSlot(actual string, slots map[string]int, cols *[]string) int {
	slot, ok := slots[actual]
	if !ok {
		slot = len(*cols)
		slots[actual] = slot
		*cols = append(*cols, actual)
	}
	return slot
}

func qualifiesForEnvCodeCheck(rawPlot string, useSU bool, keys compliancePlotKeySets) bool {
	if _, ok := keys.envTextPlots[rawPlot]; !ok {
		return false
	}
	if _, ok := keys.adminTextPlots[rawPlot]; !ok {
		return false
	}
	if useSU {
		if _, ok := keys.suTextPlots[rawPlot]; !ok {
			return false
		}
	}
	return true
}

func scanTableForCodeChecks(
	ctx context.Context,
	tx *sql.Tx,
	tblExpr, plotCol, plotDecl string,
	cols []string,
	wantAdmin, useSU bool,
	keys compliancePlotKeySets,
	checks []*expandedCodeCheck,
	validItemsByList map[string]map[string]struct{},
) error {
	if len(cols) == 0 || (useSU && len(keys.suTextPlots) == 0) {
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
		if pre, args := buildSUPlotInPreFilter(qPlot, plotDecl, keys.suPlotList); pre != "" {
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
	dest[0], dest[1] = &rawPlot, &plotStr
	for i := range vals {
		dest[2+i] = &vals[i]
	}

	for rows.Next() {
		if err := rows.Scan(dest...); err != nil {
			return err
		}
		if !qualifiesForEnvCodeCheck(string(rawPlot), useSU, keys) {
			continue
		}
		recordRowCodeViolations(plotStr, vals, wantAdmin, checks, validItemsByList)
	}
	return rows.Err()
}

func recordRowCodeViolations(
	plotStr string,
	vals []sql.NullString,
	wantAdmin bool,
	checks []*expandedCodeCheck,
	validItemsByList map[string]map[string]struct{},
) {
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

func appendCodeCheckFindings(checks []*expandedCodeCheck, report *ComplianceValidationReport) {
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
}
