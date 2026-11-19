package interchange

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type accessSourceSUEntry struct {
	prefix      string
	table       string
	description string
}

type accessCompanionSourceTable struct {
	kind        string // "Hierarchy" | "Lump" | "Profile"
	prefix      string
	sourceTable string
	description string
}

type accessSourceInventory struct {
	sourceProject     string
	version           string
	envActualName     string
	vegActualName     string
	otherActualName   string
	humusActualName   string
	mineralActualName string
	auditActualName   string
	metaActualName    string
	adminActualName   string
	suSourceTables    []accessSourceSUEntry
	companionTables   []accessCompanionSourceTable
}

type accessStagedMetrics struct {
	envM           streamTableMetrics
	vegM           streamTableMetrics
	otherM         streamTableMetrics
	humusM         streamTableMetrics
	mineralM       streamTableMetrics
	auditM         streamTableMetrics
	metaM          streamTableMetrics
	adminM         streamTableMetrics
	importedSUs    []string
	totalMalformed int
	totalOrphan    int
}

func (m *accessStagedMetrics) accumulate(t streamTableMetrics) {
	m.totalMalformed += t.malformedRows
	m.totalOrphan += t.orphanRows
}

type accessTableDDLStmt struct {
	targetTable string
	sql         string
}

type accessPlannedProjectDDL struct {
	tableStmts      []accessTableDDLStmt
	deferredIndexes []string
}

func ImportAccessProject(s *vprocore.ContextService, ctx context.Context, contextID string, request AccessProjectImportRequest) (_ AccessProjectImportResult, resultErr error) {
	targetProject, resolvedDest, parentInfo, resolvedSource, sourceDigestBefore, ddlPlan, err := prepareAccessImportEndpoints(s, ctx, contextID, request)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	db, inv, err := inspectAccessSourceInventory(resolvedSource, request.SourceProject)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-access-import-*.db")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0600); err != nil {
		tmpFile.Close()
		return AccessProjectImportResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return AccessProjectImportResult{}, err
	}

	staged, err := stageAccessTablesIntoTempSQLite(ctx, db, tmpPath, targetProject, ddlPlan, inv)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	destDigestHex, err := verifyAndPublishStagedAccessDB(
		ctx, tmpPath, resolvedDest, parentInfo, resolvedSource, sourceDigestBefore, targetProject, &published,
	)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	return finalizeAccessImportResult(s, ctx, contextID, request, inv, staged, resolvedSource, targetProject, resolvedDest, destDigestHex)
}

func prepareAccessImportEndpoints(
	s *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	request AccessProjectImportRequest,
) (string, string, os.FileInfo, string, string, accessPlannedProjectDDL, error) {
	targetProject := strings.TrimSpace(request.TargetProject)
	if !vprocore.ProjectNamePattern.MatchString(targetProject) || strings.EqualFold(targetProject, "None") ||
		strings.EqualFold(targetProject, "Sample") || strings.EqualFold(targetProject, "Master") {
		return "", "", nil, "", "", accessPlannedProjectDDL{}, errors.New("target project name must start with a letter, use only letters/digits/underscore (max 31 chars), and not be None, Sample, or Master")
	}
	destPath := strings.TrimSpace(request.DestinationPath)
	if destPath != "" && !strings.EqualFold(filepath.Ext(destPath), ".db") {
		destPath += ".db"
	}
	resolvedDest, parentInfo, err := vprocore.FreshSQLiteDestination(destPath, "Project")
	if err != nil {
		return "", "", nil, "", "", accessPlannedProjectDDL{}, err
	}
	resolvedSource, sourceDigestBefore, err := resolveAccessSourcePath(request.SourcePath)
	if err != nil {
		return "", "", nil, "", "", accessPlannedProjectDDL{}, err
	}
	review, err := s.ReadNewProjectTemplates(ctx, contextID)
	if err != nil {
		return "", "", nil, "", "", accessPlannedProjectDDL{}, err
	}
	rawPlan, err := vprocore.PlanNewProjectDDL(ctx, targetProject, review)
	if err != nil {
		return "", "", nil, "", "", accessPlannedProjectDDL{}, err
	}
	var ddlPlan accessPlannedProjectDDL
	for _, tblPlan := range rawPlan.Tables {
		for _, mapping := range tblPlan.Schema {
			if mapping.SQL == nil {
				continue
			}
			stmtText := strings.TrimSpace(*mapping.SQL)
			upper := strings.ToUpper(stmtText)
			if strings.HasPrefix(upper, "CREATE INDEX") || strings.HasPrefix(upper, "CREATE UNIQUE INDEX") {
				ddlPlan.deferredIndexes = append(ddlPlan.deferredIndexes, stmtText)
			} else {
				ddlPlan.tableStmts = append(ddlPlan.tableStmts, accessTableDDLStmt{targetTable: tblPlan.TargetTable, sql: stmtText})
			}
		}
	}
	return targetProject, resolvedDest, parentInfo, resolvedSource, sourceDigestBefore, ddlPlan, nil
}

func inspectAccessSourceInventory(resolvedSource, rawSourceProject string) (*accessreader.DB, accessSourceInventory, error) {
	var inv accessSourceInventory
	db, err := accessreader.Open(resolvedSource)
	if err != nil {
		return nil, inv, err
	}
	tables, err := db.Tables()
	if err != nil {
		return nil, inv, err
	}
	byLower := make(map[string]accessreader.Table, len(tables))
	for _, tbl := range tables {
		if !tbl.Linked {
			byLower[strings.ToLower(tbl.Name)] = tbl
		}
	}
	inv.sourceProject = strings.TrimSpace(rawSourceProject)
	envTbl, ok := byLower[strings.ToLower(inv.sourceProject+"_Env")]
	if !ok {
		return nil, inv, fmt.Errorf("source project %q (_Env table) was not found in %s", inv.sourceProject, filepath.Base(resolvedSource))
	}
	inv.version = strings.TrimSpace(envTbl.Description)
	if inv.version != "VP08" && inv.version != "VP07" && inv.version != "VP06" && inv.version != "VP05" {
		return nil, inv, fmt.Errorf("source project %s has unsupported version %q (supported: VP05, VP06, VP07, VP08)", inv.sourceProject, inv.version)
	}
	if err := resolveRequiredAccessTableNames(byLower, &inv); err != nil {
		return nil, inv, err
	}
	inv.suSourceTables, inv.companionTables = discoverAccessCompanions(db, tables)
	return db, inv, nil
}

func resolveRequiredAccessTableNames(byLower map[string]accessreader.Table, inv *accessSourceInventory) error {
	requireTbl := func(suffix string) (string, error) {
		tbl, exists := byLower[strings.ToLower(inv.sourceProject+"_"+suffix)]
		if !exists {
			return "", fmt.Errorf("missing required table %s_%s", inv.sourceProject, suffix)
		}
		return tbl.Name, nil
	}
	var err error
	for _, pair := range []struct {
		suffix string
		dst    *string
	}{
		{"Env", &inv.envActualName},
		{"Veg", &inv.vegActualName},
		{"Other", &inv.otherActualName},
		{"Humus", &inv.humusActualName},
		{"Mineral", &inv.mineralActualName},
		{"Audit", &inv.auditActualName},
	} {
		if *pair.dst, err = requireTbl(pair.suffix); err != nil {
			return err
		}
	}
	if inv.version == "VP08" {
		if inv.metaActualName, err = requireTbl("Metadata"); err != nil {
			return err
		}
		if inv.adminActualName, err = requireTbl("Admin"); err != nil {
			return err
		}
	} else if inv.version == "VP07" {
		if _, exists := byLower[strings.ToLower(inv.sourceProject+"_Metadata")]; !exists {
			return fmt.Errorf("VP07 import requires table %s_Metadata", inv.sourceProject)
		}
	}
	return nil
}

func discoverAccessCompanions(db *accessreader.DB, tables []accessreader.Table) ([]accessSourceSUEntry, []accessCompanionSourceTable) {
	var suTables []accessSourceSUEntry
	var companions []accessCompanionSourceTable
	for _, tbl := range tables {
		if tbl.Linked || strings.HasPrefix(strings.ToUpper(tbl.Name), "USYS") {
			continue
		}
		upperName := strings.ToUpper(tbl.Name)
		switch {
		case len(tbl.Name) > 3 && strings.HasSuffix(upperName, "_SU"):
			if su, ok := inspectAccessSUTable(db, tbl); ok {
				suTables = append(suTables, su)
			}
		case len(tbl.Name) > len("_Hierarchy") && strings.HasSuffix(upperName, "_HIERARCHY"):
			if comp, ok := inspectAccessHierarchyTable(db, tbl); ok {
				companions = append(companions, comp)
			}
		case len(tbl.Name) > len("_Lump") && strings.HasSuffix(upperName, "_LUMP"):
			if comp, ok := inspectAccessColumnCompanion(db, tbl, "Lump", "_Lump", "VP05", "LumpCode", "SppCode"); ok {
				companions = append(companions, comp)
			}
		case len(tbl.Name) > len("_Profile") && strings.HasSuffix(upperName, "_PROFILE"):
			if comp, ok := inspectAccessColumnCompanion(db, tbl, "Profile", "_Profile", "VP05-2", vprocore.PlotProfileColumns...); ok {
				companions = append(companions, comp)
			}
		}
	}
	return suTables, companions
}

func hasAllAccessColumnsCI(cols []accessreader.Column, required ...string) bool {
	colMap := make(map[string]string, len(cols))
	for _, c := range cols {
		colMap[strings.ToLower(c.Name)] = c.Type
	}
	for _, req := range required {
		if _, ok := colMap[strings.ToLower(req)]; !ok {
			return false
		}
	}
	return true
}

func defaultDescription(raw, fallback string) string {
	if trimmed := strings.TrimSpace(raw); trimmed != "" {
		return trimmed
	}
	return fallback
}

func inspectAccessSUTable(db *accessreader.DB, tbl accessreader.Table) (accessSourceSUEntry, bool) {
	suPrefix := tbl.Name[:len(tbl.Name)-3]
	if !vprocore.ProjectNamePattern.MatchString(suPrefix) {
		return accessSourceSUEntry{}, false
	}
	r, err := db.Scan(tbl.Name)
	if err != nil {
		return accessSourceSUEntry{}, false
	}
	ok := hasAllAccessColumnsCI(r.Columns, "PlotNumber", "SiteUnit")
	_ = r.Close()
	if !ok {
		return accessSourceSUEntry{}, false
	}
	return accessSourceSUEntry{
		prefix:      suPrefix,
		table:       tbl.Name,
		description: defaultDescription(tbl.Description, "VP04"),
	}, true
}

func inspectAccessHierarchyTable(db *accessreader.DB, tbl accessreader.Table) (accessCompanionSourceTable, bool) {
	prefix := tbl.Name[:len(tbl.Name)-len("_Hierarchy")]
	if !vprocore.ProjectNamePattern.MatchString(prefix) {
		return accessCompanionSourceTable{}, false
	}
	r, err := db.Scan(tbl.Name)
	if err != nil {
		return accessCompanionSourceTable{}, false
	}
	colTypes := map[string]string{}
	for _, c := range r.Columns {
		colTypes[strings.ToLower(c.Name)] = c.Type
	}
	_ = r.Close()
	if colTypes["id"] != "integer" || colTypes["name"] != "text" || colTypes["parent"] != "integer" || colTypes["level"] != "integer" {
		return accessCompanionSourceTable{}, false
	}
	return accessCompanionSourceTable{
		kind:        "Hierarchy",
		prefix:      prefix,
		sourceTable: tbl.Name,
		description: defaultDescription(tbl.Description, "VP04"),
	}, true
}

func inspectAccessColumnCompanion(
	db *accessreader.DB,
	tbl accessreader.Table,
	kind, suffix, defaultDesc string,
	requiredCols ...string,
) (accessCompanionSourceTable, bool) {
	prefix := tbl.Name[:len(tbl.Name)-len(suffix)]
	if !vprocore.ProjectNamePattern.MatchString(prefix) {
		return accessCompanionSourceTable{}, false
	}
	r, err := db.Scan(tbl.Name)
	if err != nil {
		return accessCompanionSourceTable{}, false
	}
	ok := hasAllAccessColumnsCI(r.Columns, requiredCols...)
	_ = r.Close()
	if !ok {
		return accessCompanionSourceTable{}, false
	}
	return accessCompanionSourceTable{
		kind:        kind,
		prefix:      prefix,
		sourceTable: tbl.Name,
		description: defaultDescription(tbl.Description, defaultDesc),
	}, true
}

func stageAccessTablesIntoTempSQLite(
	ctx context.Context,
	db *accessreader.DB,
	tmpPath, targetProject string,
	ddlPlan accessPlannedProjectDDL,
	inv accessSourceInventory,
) (accessStagedMetrics, error) {
	var metrics accessStagedMetrics
	sqlDB, err := sqlutil.OpenStagedSQLite(tmpPath, sqlutil.StagedSQLiteOptions{FastMemoryJournal: true})
	if err != nil {
		return metrics, err
	}
		tx, err := sqlutil.BeginStagedTx(ctx, sqlDB)
	if err != nil {
		sqlDB.Close()
		return metrics, err
	}

	if err := executeStagedAccessImportTx(ctx, db, tx, targetProject, ddlPlan, inv, &metrics); err != nil {
		_ = tx.Rollback()
		_ = sqlDB.Close()
		return metrics, err
	}
	if err := sqlutil.CommitStagedTx(ctx, tx); err != nil {
		_ = sqlDB.Close()
		return metrics, err
	}
	_, _ = sqlDB.ExecContext(ctx, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode = DELETE;")
	if err := sqlDB.Close(); err != nil {
		return metrics, err
	}
	return metrics, nil
}

func executeStagedAccessImportTx(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	targetProject string,
	ddlPlan accessPlannedProjectDDL,
	inv accessSourceInventory,
	metrics *accessStagedMetrics,
) error {
	if err := createStagedCoreSchemaAndSupportTables(ctx, tx, targetProject, ddlPlan); err != nil {
		return err
	}
	quarantineStmt, err := tx.PrepareContext(ctx, `INSERT INTO "__VPRO_ImportQuarantine" ("SourceTable","SourceRow","PlotNumber","Reason","PayloadJSON") VALUES (?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer quarantineStmt.Close()

	childIdStmt, err := vprocore.PrepareChildIdentityInsertStmt(ctx, tx)
	if err != nil {
		return err
	}
	defer childIdStmt.Close()

	validEnvPlots, err := streamAccessCoreVersionTables(ctx, db, tx, quarantineStmt, childIdStmt, targetProject, inv, metrics)
	if err != nil {
		return err
	}
	if err := streamAccessDiscoveredSUs(ctx, db, tx, quarantineStmt, validEnvPlots, inv.suSourceTables, metrics); err != nil {
		return err
	}
	if err := streamAccessDiscoveredCompanions(ctx, db, tx, quarantineStmt, inv.companionTables, metrics); err != nil {
		return err
	}
	return finalizeStagedIndexesAndIdentities(ctx, tx, ddlPlan.deferredIndexes, inv.sourceProject, targetProject)
}

func createStagedCoreSchemaAndSupportTables(
	ctx context.Context,
	tx *sql.Tx,
	targetProject string,
	ddlPlan accessPlannedProjectDDL,
) error {
	for _, stmt := range ddlPlan.tableStmts {
		if _, err := tx.ExecContext(ctx, stmt.sql); err != nil {
			return fmt.Errorf("create schema for %s: %w", stmt.targetTable, err)
		}
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
		return err
	}
	for _, suffix := range vprocore.CoreTables {
		if _, err := tx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, targetProject+"_"+suffix); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ImportQuarantine" (
		"ID" INTEGER PRIMARY KEY AUTOINCREMENT,
		"SourceTable" TEXT NOT NULL,
		"SourceRow" INTEGER NOT NULL,
		"PlotNumber" TEXT NOT NULL,
		"Reason" TEXT NOT NULL,
		"PayloadJSON" TEXT NOT NULL
	)`); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
		"ChildTable" TEXT NOT NULL,
		"ID" INTEGER NOT NULL,
		PRIMARY KEY ("ChildTable", "ID")
	)`)
	return err
}

func buildAuditStreamTransforms(targetProject string) (map[string]func([]any, map[string]int) any, map[string]func(any) any) {
	coalesceFalseBool := func(v any) any {
		if v == nil {
			return int64(0)
		}
		return v
	}
	overrides := map[string]func(any) any{
		"Project": func(any) any { return targetProject },
		"Restore": coalesceFalseBool,
		"Flag":    coalesceFalseBool,
	}
	computed := map[string]func([]any, map[string]int) any{
		"Project": func([]any, map[string]int) any { return targetProject },
	}
	return computed, overrides
}

func streamAccessCoreVersionTables(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt, childIdStmt *sql.Stmt,
	targetProject string,
	inv accessSourceInventory,
	metrics *accessStagedMetrics,
) (map[string]struct{}, error) {
	validEnvPlots := make(map[string]struct{}, 1024)
	auditComputed, auditOverrides := buildAuditStreamTransforms(targetProject)

	if inv.version == "VP08" {
		err := streamVP08CoreTables(ctx, db, tx, quarantineStmt, childIdStmt, targetProject, inv, validEnvPlots, auditComputed, auditOverrides, metrics)
		return validEnvPlots, err
	}
	if err := streamLegacyEnvAndAdmin(ctx, db, tx, quarantineStmt, childIdStmt, targetProject, inv, validEnvPlots, metrics); err != nil {
		return nil, err
	}
	err := streamLegacyChildAndAuditTables(ctx, db, tx, quarantineStmt, childIdStmt, targetProject, inv, validEnvPlots, auditComputed, auditOverrides, metrics)
	return validEnvPlots, err
}

func streamVP08CoreTables(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt, childIdStmt *sql.Stmt,
	targetProject string,
	inv accessSourceInventory,
	validEnvPlots map[string]struct{},
	auditComputed map[string]func([]any, map[string]int) any,
	auditOverrides map[string]func(any) any,
	metrics *accessStagedMetrics,
) error {
	steps := []struct {
		src  string
		env  map[string]struct{}
		spec streamInsertSpec
		dst  *streamTableMetrics
	}{
		{inv.envActualName, nil, streamInsertSpec{targetTable: targetProject + "_Env", dedupePlotKey: true, recordEnvPlots: validEnvPlots}, &metrics.envM},
		{inv.vegActualName, validEnvPlots, streamInsertSpec{targetTable: targetProject + "_Veg", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Veg")}, &metrics.vegM},
		{inv.otherActualName, validEnvPlots, streamInsertSpec{targetTable: targetProject + "_Other", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Other")}, &metrics.otherM},
		{inv.humusActualName, validEnvPlots, streamInsertSpec{targetTable: targetProject + "_Humus", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Humus")}, &metrics.humusM},
		{inv.mineralActualName, validEnvPlots, streamInsertSpec{targetTable: targetProject + "_Mineral", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Mineral")}, &metrics.mineralM},
		{inv.auditActualName, nil, streamInsertSpec{targetTable: targetProject + "_Audit", computed: auditComputed, columnOverrides: auditOverrides, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Audit")}, &metrics.auditM},
		{inv.metaActualName, nil, streamInsertSpec{targetTable: targetProject + "_Metadata", childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Metadata")}, &metrics.metaM},
		{inv.adminActualName, validEnvPlots, streamInsertSpec{targetTable: targetProject + "_Admin", requireEnvPlot: true, plotSourceCol: "Plot", dedupePlotKey: true}, &metrics.adminM},
	}
	for _, st := range steps {
		m, err := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, st.src, st.env, []streamInsertSpec{st.spec})
		if err != nil {
			return err
		}
		*st.dst = m
		metrics.accumulate(m)
	}
	return nil
}

func streamLegacyEnvAndAdmin(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt, childIdStmt *sql.Stmt,
	targetProject string,
	inv accessSourceInventory,
	validEnvPlots map[string]struct{},
	metrics *accessStagedMetrics,
) error {
	var envMap, adminMap [][2]string
	var computed map[string]func([]any, map[string]int) any

	switch inv.version {
	case "VP07":
		envMap, adminMap = vp07EnvMapping, vp07AdminFromEnvMapping
	case "VP06":
		envMap, adminMap = vp06EnvMapping, vp06AdminFromEnvMapping
	case "VP05":
		var err error
		if computed, err = buildVP05CoordinateComputedMap(db, inv.envActualName); err != nil {
			return err
		}
		envMap, adminMap = vp05EnvMapping, vp05AdminFromEnvMapping
	}

	envM, err := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, inv.envActualName, nil, []streamInsertSpec{
		{targetTable: targetProject + "_Env", targetToSource: envMap, computed: computed, dedupePlotKey: true, recordEnvPlots: validEnvPlots},
		{targetTable: targetProject + "_Admin", targetToSource: adminMap},
	})
	if err != nil {
		return err
	}
	metrics.envM = envM
	metrics.accumulate(envM)
	metrics.adminM = streamTableMetrics{actualSourceTable: inv.envActualName, columnCount: 20, importedRows: envM.importedRows}
	return nil
}

func buildVP05CoordinateComputedMap(db *accessreader.DB, envActualName string) (map[string]func([]any, map[string]int) any, error) {
	rCheck, err := db.Scan(envActualName)
	if err != nil {
		return nil, err
	}
	hasLonDeg, hasLatDeg := false, false
	for _, c := range rCheck.Columns {
		if strings.EqualFold(c.Name, "LongitudeDegrees") {
			hasLonDeg = true
		} else if strings.EqualFold(c.Name, "LatitudeDegrees") {
			hasLatDeg = true
		}
	}
	_ = rCheck.Close()
	if !hasLonDeg || !hasLatDeg {
		return nil, errors.New("VP05 Env table is missing LongitudeDegrees or LatitudeDegrees")
	}
	getCol := func(r []any, idx map[string]int, name string) any {
		if i, ok := idx[strings.ToLower(name)]; ok && i >= 0 && i < len(r) {
			return r[i]
		}
		return nil
	}
	return map[string]func([]any, map[string]int) any{
		"Longitude": func(r []any, idx map[string]int) any {
			return convertLongLatToDeg(getCol(r, idx, "LongitudeDegrees"), getCol(r, idx, "LongitudeMinutes"), getCol(r, idx, "LongitudeSeconds"))
		},
		"Latitude": func(r []any, idx map[string]int) any {
			return convertLongLatToDeg(getCol(r, idx, "LatitudeDegrees"), getCol(r, idx, "LatitudeMinutes"), getCol(r, idx, "LatitudeSeconds"))
		},
	}, nil
}

func streamLegacyChildAndAuditTables(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt, childIdStmt *sql.Stmt,
	targetProject string,
	inv accessSourceInventory,
	validEnvPlots map[string]struct{},
	auditComputed map[string]func([]any, map[string]int) any,
	auditOverrides map[string]func(any) any,
	metrics *accessStagedMetrics,
) error {
	legacyPairs := []struct {
		suffix string
		src    string
		cols   []string
		reqEnv bool
		dst    *streamTableMetrics
	}{
		{"Veg", inv.vegActualName, legacyVegColumns, true, &metrics.vegM},
		{"Other", inv.otherActualName, legacyOtherColumns, true, &metrics.otherM},
		{"Humus", inv.humusActualName, legacyHumusColumns, true, &metrics.humusM},
		{"Mineral", inv.mineralActualName, legacyMineralColumns, true, &metrics.mineralM},
		{"Audit", inv.auditActualName, legacyAuditColumns, false, &metrics.auditM},
	}
	for _, item := range legacyPairs {
		pairs := make([][2]string, len(item.cols))
		for i, c := range item.cols {
			pairs[i] = [2]string{c, c}
		}
		var envSet map[string]struct{}
		if item.reqEnv {
			envSet = validEnvPlots
		}
		spec := streamInsertSpec{
			targetTable:        targetProject + "_" + item.suffix,
			targetToSource:     pairs,
			requireEnvPlot:     item.reqEnv,
			childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_" + item.suffix),
		}
		if item.suffix == "Audit" {
			spec.computed = auditComputed
			spec.columnOverrides = auditOverrides
		}
		m, err := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, item.src, envSet, []streamInsertSpec{spec})
		if err != nil {
			return err
		}
		*item.dst = m
		metrics.accumulate(m)
	}
	return nil
}

func stagedTableExistsCI(ctx context.Context, tx *sql.Tx, name string) (bool, error) {
	var exists bool
	err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE)`, name).Scan(&exists)
	return exists, err
}

func streamAccessDiscoveredSUs(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt *sql.Stmt,
	validEnvPlots map[string]struct{},
	suSourceTables []accessSourceSUEntry,
	metrics *accessStagedMetrics,
) error {
	for _, su := range suSourceTables {
		targetName := su.prefix + "_SU"
		exists, err := stagedTableExistsCI(ctx, tx, targetName)
		if err != nil {
			return err
		}
		if exists {
			continue
		}
		suTable := vprocore.QuoteHeaderIdentifier(targetName)
		if _, err := tx.ExecContext(ctx, `CREATE TABLE `+suTable+`("PlotNumber" VARCHAR,"SiteUnit" VARCHAR);
			CREATE UNIQUE INDEX `+vprocore.QuoteHeaderIdentifier("uidx_"+su.prefix+"_SU_PlotNumber")+` ON `+suTable+`("PlotNumber");
			CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+su.prefix+"_SU_SiteUnit")+` ON `+suTable+`("SiteUnit")`); err != nil {
			return err
		}
		suM, err := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, nil, su.table, validEnvPlots, []streamInsertSpec{
			{
				targetTable:    targetName,
				targetToSource: [][2]string{{"PlotNumber", "PlotNumber"}, {"SiteUnit", "SiteUnit"}},
				requireEnvPlot: true,
				dedupePlotKey:  true,
			},
		})
		if err != nil {
			return err
		}
		metrics.accumulate(suM)
		if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, targetName, su.description); err != nil {
			return err
		}
		metrics.importedSUs = append(metrics.importedSUs, su.prefix)
	}
	return nil
}

func streamAccessDiscoveredCompanions(
	ctx context.Context,
	db *accessreader.DB,
	tx *sql.Tx,
	quarantineStmt *sql.Stmt,
	companionTables []accessCompanionSourceTable,
	metrics *accessStagedMetrics,
) error {
	for _, comp := range companionTables {
		targetName := comp.prefix + "_" + comp.kind
		exists, err := stagedTableExistsCI(ctx, tx, targetName)
		if err != nil {
			return err
		}
		if exists {
			continue
		}
		if err := createCompanionTableSchema(ctx, tx, targetName, comp.kind); err != nil {
			return err
		}
		cM, err := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, nil, comp.sourceTable, nil, []streamInsertSpec{{targetTable: targetName}})
		if err != nil {
			return err
		}
		metrics.accumulate(cM)
		if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, targetName, comp.description); err != nil {
			return err
		}
	}
	return nil
}

func createCompanionTableSchema(ctx context.Context, tx *sql.Tx, targetName, kind string) error {
	qTbl := vprocore.QuoteHeaderIdentifier(targetName)
	var ddl string
	switch kind {
	case "Hierarchy":
		ddl = `CREATE TABLE ` + qTbl + ` (
			"ID" INTEGER PRIMARY KEY,
			"Name" VARCHAR,
			"Parent" INTEGER,
			"Level" SMALLINT,
			"Tag" VARCHAR,
			"MyOrder" VARCHAR,
			"ChildID" SMALLINT,
			"StartChild" SMALLINT,
			"LastChild" SMALLINT,
			"Flag" BOOLEAN
		);
		CREATE INDEX ` + vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_Parent") + ` ON ` + qTbl + ` ("Parent");
		CREATE INDEX ` + vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_Level") + ` ON ` + qTbl + ` ("Level")`
	case "Lump":
		ddl = `CREATE TABLE ` + qTbl + ` (
			"LumpCode" VARCHAR,
			"SppCode" VARCHAR,
			"Use" BOOLEAN
		);
		CREATE INDEX ` + vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_LumpCode") + ` ON ` + qTbl + ` ("LumpCode");
		CREATE INDEX ` + vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_SppCode") + ` ON ` + qTbl + ` ("SppCode")`
	case "Profile":
		ddl = `CREATE TABLE ` + qTbl + ` (
			"Order" SMALLINT,
			"Table" VARCHAR,
			"Field" VARCHAR,
			"Operator" VARCHAR,
			"Layer" VARCHAR,
			"Species" VARCHAR,
			"Criteria" VARCHAR,
			"Operation" VARCHAR,
			"PlotCount" INTEGER
		)`
	default:
		return nil
	}
	_, err := tx.ExecContext(ctx, ddl)
	return err
}

func finalizeStagedIndexesAndIdentities(
	ctx context.Context,
	tx *sql.Tx,
	deferredIndexes []string,
	sourceProject, targetProject string,
) error {
	for _, idxSQL := range deferredIndexes {
		if _, err := tx.ExecContext(ctx, idxSQL); err != nil {
			return fmt.Errorf("create deferred index: %w", err)
		}
	}
	for _, suffix := range []string{"Env", "Veg"} {
		qTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_" + suffix)
		qIdx := vprocore.QuoteHeaderIdentifier("idx_vpro_nocase_" + targetProject + "_" + suffix + "_PlotNumber")
		_, _ = tx.ExecContext(ctx, fmt.Sprintf(`CREATE INDEX IF NOT EXISTS %s ON %s ("PlotNumber" COLLATE NOCASE ASC, "PlotNumber" COLLATE BINARY ASC)`, qIdx, qTbl))
		qBin := vprocore.QuoteHeaderIdentifier("idx_vpro_bin_" + targetProject + "_" + suffix + "_PlotNumber")
		_, _ = tx.ExecContext(ctx, fmt.Sprintf(`CREATE INDEX IF NOT EXISTS %s ON %s ("PlotNumber")`, qBin, qTbl))
	}
	qAdm := vprocore.QuoteHeaderIdentifier(targetProject + "_Admin")
	qAdmIdx := vprocore.QuoteHeaderIdentifier("idx_vpro_bin_" + targetProject + "_Admin_Plot")
	if _, err := tx.ExecContext(ctx, fmt.Sprintf(`CREATE INDEX IF NOT EXISTS %s ON %s ("Plot")`, qAdmIdx, qAdm)); err != nil {
		return err
	}
	qAud := vprocore.QuoteHeaderIdentifier(targetProject + "_Audit")
	qAudIdx := vprocore.QuoteHeaderIdentifier("idx_vpro_bin_" + targetProject + "_Audit_PlotNumber")
	if _, err := tx.ExecContext(ctx, fmt.Sprintf(`CREATE INDEX IF NOT EXISTS %s ON %s ("PlotNumber")`, qAudIdx, qAud)); err != nil {
		return err
	}
	return seedImportedChildIdentities(ctx, tx, sourceProject, targetProject)
}

func verifyAndPublishStagedAccessDB(
	ctx context.Context,
	tmpPath, resolvedDest string,
	parentInfo os.FileInfo,
	resolvedSource, sourceDigestBefore, targetProject string,
	published *bool,
) (string, error) {
	_, sourceDigestAfter, err := resolveAccessSourcePath(resolvedSource)
	if err != nil || sourceDigestAfter != sourceDigestBefore {
		return "", errors.New("source Access database changed during import; publication aborted")
	}

	inspected, err := vprocore.InspectFileContext(ctx, tmpPath)
	if err != nil {
		return "", fmt.Errorf("verify staged SQLite project: %w", err)
	}
	compatible := false
	for _, p := range inspected {
		if p.Name == targetProject && p.Compatible {
			compatible = true
			break
		}
	}
	if !compatible {
		return "", errors.New("staged SQLite database did not pass VP08 compatibility validation")
	}

	currentParent, err := os.Stat(filepath.Dir(resolvedDest))
	if err != nil || !os.SameFile(parentInfo, currentParent) {
		return "", errors.New("destination parent directory changed during import; publication aborted")
	}
	if err := sqlutil.LinkOrCreateExclusive(tmpPath, resolvedDest); err != nil {
		return "", fmt.Errorf("publish SQLite database %s: %w", resolvedDest, err)
	}
	*published = true
	_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)

	if err := vprocore.InitializeSQLiteWAL(ctx, resolvedDest); err != nil {
		_ = sqlutil.RemoveSQLiteWithSidecars(resolvedDest)
		return "", fmt.Errorf("initialize SQLite WAL on %s: %w", resolvedDest, err)
	}
	return streamFileSHA256(resolvedDest)
}

func finalizeAccessImportResult(
	s *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	request AccessProjectImportRequest,
	inv accessSourceInventory,
	staged accessStagedMetrics,
	resolvedSource, targetProject, resolvedDest, destDigestHex string,
) (AccessProjectImportResult, error) {
	summaries := []AccessImportTableSummary{
		{Suffix: "Env", SourceTable: inv.envActualName, Description: "VP08", RowCount: staged.envM.importedRows, ColumnCount: 112, Present: true, Action: "Imported"},
		{Suffix: "Veg", SourceTable: inv.vegActualName, Description: "VP08", RowCount: staged.vegM.importedRows, ColumnCount: 44, Present: true, Action: "Imported"},
		{Suffix: "Other", SourceTable: inv.otherActualName, Description: "VP08", RowCount: staged.otherM.importedRows, ColumnCount: 11, Present: true, Action: "Imported"},
		{Suffix: "Humus", SourceTable: inv.humusActualName, Description: "VP08", RowCount: staged.humusM.importedRows, ColumnCount: 18, Present: true, Action: "Imported"},
		{Suffix: "Mineral", SourceTable: inv.mineralActualName, Description: "VP08", RowCount: staged.mineralM.importedRows, ColumnCount: 28, Present: true, Action: "Imported"},
		{Suffix: "Audit", SourceTable: inv.auditActualName, Description: "VP08", RowCount: staged.auditM.importedRows, ColumnCount: 11, Present: true, Action: "Imported"},
		{Suffix: "Metadata", SourceTable: inv.metaActualName, Description: "VP08", RowCount: staged.metaM.importedRows, ColumnCount: 75, Present: inv.version == "VP08", Action: "Imported"},
		{Suffix: "Admin", SourceTable: inv.adminActualName, Description: "VP08", RowCount: staged.adminM.importedRows, ColumnCount: 20, Present: true, Action: "Imported"},
	}

	result := AccessProjectImportResult{
		SourcePath:              resolvedSource,
		SourceProject:           inv.sourceProject,
		SourceVersion:           inv.version,
		ConversionMode:          fmt.Sprintf("%s -> VP08", inv.version),
		TargetProject:           targetProject,
		DestinationPath:         resolvedDest,
		DestinationSHA:          destDigestHex,
		PlotCount:               staged.envM.importedRows,
		QuarantinedMalformedRow: staged.totalMalformed,
		QuarantinedOrphanRows:   staged.totalOrphan,
		Tables:                  summaries,
		ImportedSUs:             staged.importedSUs,
	}

	if request.ActivateOnSuccess {
		state, switchErr := s.SwitchContext(contextID, vprocore.ContextSelection{
			Project:       targetProject,
			ProjectPath:   resolvedDest,
			SU:            "None",
			SUPath:        "",
			Hierarchy:     "None",
			HierarchyPath: "",
		})
		if switchErr != nil {
			return result, fmt.Errorf("project imported to %s, but switching context failed: %w", resolvedDest, switchErr)
		}
		_ = s.Projects.EnsureActiveProjectWAL(ctx)
		result.Activated = true
		result.State = &state
	} else if state, stateErr := s.Projects.GetState(ctx); stateErr == nil {
		result.State = &state
	}
	return result, nil
}
