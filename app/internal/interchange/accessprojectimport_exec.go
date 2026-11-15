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

func ImportAccessProject(s *vprocore.ContextService, ctx context.Context, contextID string, request AccessProjectImportRequest) (_ AccessProjectImportResult, resultErr error) {
	targetProject := strings.TrimSpace(request.TargetProject)
	if !vprocore.ProjectNamePattern.MatchString(targetProject) || strings.EqualFold(targetProject, "None") ||
		strings.EqualFold(targetProject, "Sample") || strings.EqualFold(targetProject, "Master") {
		return AccessProjectImportResult{}, errors.New("target project name must start with a letter, use only letters/digits/underscore (max 31 chars), and not be None, Sample, or Master")
	}
	destPath := strings.TrimSpace(request.DestinationPath)
	if destPath != "" && !strings.EqualFold(filepath.Ext(destPath), ".db") {
		destPath += ".db"
	}
	resolvedDest, parentInfo, err := vprocore.FreshSQLiteDestination(destPath, "Project")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	resolvedSource, sourceDigestBefore, err := resolveAccessSourcePath(request.SourcePath)
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	review, err := s.ReadNewProjectTemplates(ctx, contextID)
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	ddlPlan, err := vprocore.PlanNewProjectDDL(ctx, targetProject, review)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	db, err := accessreader.Open(resolvedSource)
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	tables, err := db.Tables()
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	byLower := make(map[string]accessreader.Table, len(tables))
	for _, tbl := range tables {
		if !tbl.Linked {
			byLower[strings.ToLower(tbl.Name)] = tbl
		}
	}
	sourceProject := strings.TrimSpace(request.SourceProject)
	envTbl, ok := byLower[strings.ToLower(sourceProject+"_Env")]
	if !ok {
		return AccessProjectImportResult{}, fmt.Errorf("source project %q (_Env table) was not found in %s", sourceProject, filepath.Base(resolvedSource))
	}
	version := strings.TrimSpace(envTbl.Description)
	if version != "VP08" && version != "VP07" && version != "VP06" && version != "VP05" {
		return AccessProjectImportResult{}, fmt.Errorf("source project %s has unsupported version %q (supported: VP05, VP06, VP07, VP08)", sourceProject, version)
	}

	requireSourceTable := func(suffix string) (string, error) {
		tbl, exists := byLower[strings.ToLower(sourceProject+"_"+suffix)]
		if !exists {
			return "", fmt.Errorf("missing required table %s_%s", sourceProject, suffix)
		}
		return tbl.Name, nil
	}

	envActualName, err := requireSourceTable("Env")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	vegActualName, err := requireSourceTable("Veg")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	otherActualName, err := requireSourceTable("Other")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	humusActualName, err := requireSourceTable("Humus")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	mineralActualName, err := requireSourceTable("Mineral")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	auditActualName, err := requireSourceTable("Audit")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	var metaActualName, adminActualName string
	if version == "VP08" {
		if metaActualName, err = requireSourceTable("Metadata"); err != nil {
			return AccessProjectImportResult{}, err
		}
		if adminActualName, err = requireSourceTable("Admin"); err != nil {
			return AccessProjectImportResult{}, err
		}
	} else if version == "VP07" {
		if _, exists := byLower[strings.ToLower(sourceProject+"_Metadata")]; !exists {
			return AccessProjectImportResult{}, fmt.Errorf("VP07 import requires table %s_Metadata", sourceProject)
		}
	}

	type companionSourceTable struct {
		kind        string // "Hierarchy" | "Lump" | "Profile"
		prefix      string
		sourceTable string
		description string
	}
	var suSourceTables []struct {
		prefix      string
		table       string
		description string
	}
	var companionTables []companionSourceTable

	hasAllColumnsCI := func(cols []accessreader.Column, required ...string) bool {
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

	for _, tbl := range tables {
		if tbl.Linked || strings.HasPrefix(strings.ToUpper(tbl.Name), "USYS") {
			continue
		}
		upperName := strings.ToUpper(tbl.Name)
		switch {
		case len(tbl.Name) > 3 && strings.HasSuffix(upperName, "_SU"):
			suPrefix := tbl.Name[:len(tbl.Name)-3]
			if !vprocore.ProjectNamePattern.MatchString(suPrefix) {
				continue
			}
			r, rErr := db.Scan(tbl.Name)
			if rErr != nil {
				continue
			}
			ok := hasAllColumnsCI(r.Columns, "PlotNumber", "SiteUnit")
			_ = r.Close()
			if ok {
				desc := strings.TrimSpace(tbl.Description)
				if desc == "" {
					desc = "VP04"
				}
				suSourceTables = append(suSourceTables, struct {
					prefix      string
					table       string
					description string
				}{prefix: suPrefix, table: tbl.Name, description: desc})
			}

		case len(tbl.Name) > len("_Hierarchy") && strings.HasSuffix(upperName, "_HIERARCHY"):
			prefix := tbl.Name[:len(tbl.Name)-len("_Hierarchy")]
			if !vprocore.ProjectNamePattern.MatchString(prefix) {
				continue
			}
			r, rErr := db.Scan(tbl.Name)
			if rErr != nil {
				continue
			}
			colTypes := map[string]string{}
			for _, c := range r.Columns {
				colTypes[strings.ToLower(c.Name)] = c.Type
			}
			_ = r.Close()
			if colTypes["id"] == "integer" && colTypes["name"] == "text" && colTypes["parent"] == "integer" && colTypes["level"] == "integer" {
				desc := strings.TrimSpace(tbl.Description)
				if desc == "" {
					desc = "VP04"
				}
				companionTables = append(companionTables, companionSourceTable{
					kind: "Hierarchy", prefix: prefix, sourceTable: tbl.Name, description: desc,
				})
			}

		case len(tbl.Name) > len("_Lump") && strings.HasSuffix(upperName, "_LUMP"):
			prefix := tbl.Name[:len(tbl.Name)-len("_Lump")]
			if !vprocore.ProjectNamePattern.MatchString(prefix) {
				continue
			}
			r, rErr := db.Scan(tbl.Name)
			if rErr != nil {
				continue
			}
			ok := hasAllColumnsCI(r.Columns, "LumpCode", "SppCode")
			_ = r.Close()
			if ok {
				desc := strings.TrimSpace(tbl.Description)
				if desc == "" {
					desc = "VP05"
				}
				companionTables = append(companionTables, companionSourceTable{
					kind: "Lump", prefix: prefix, sourceTable: tbl.Name, description: desc,
				})
			}

		case len(tbl.Name) > len("_Profile") && strings.HasSuffix(upperName, "_PROFILE"):
			prefix := tbl.Name[:len(tbl.Name)-len("_Profile")]
			if !vprocore.ProjectNamePattern.MatchString(prefix) {
				continue
			}
			r, rErr := db.Scan(tbl.Name)
			if rErr != nil {
				continue
			}
			ok := hasAllColumnsCI(r.Columns, vprocore.PlotProfileColumns...)
			_ = r.Close()
			if ok {
				desc := strings.TrimSpace(tbl.Description)
				if desc == "" {
					desc = "VP05-2"
				}
				companionTables = append(companionTables, companionSourceTable{
					kind: "Profile", prefix: prefix, sourceTable: tbl.Name, description: desc,
				})
			}
		}
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-access-import-*.db")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = os.Remove(tmpPath)
			_ = os.Remove(tmpPath + "-wal")
			_ = os.Remove(tmpPath + "-shm")
		}
	}()
	if err := tmpFile.Chmod(0600); err != nil {
		tmpFile.Close()
		return AccessProjectImportResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return AccessProjectImportResult{}, err
	}

	sqlDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_foreign_keys=0&_journal_mode=MEMORY&_synchronous=OFF")
	if err != nil {
		return AccessProjectImportResult{}, err
	}
	sqlDB.SetMaxOpenConns(1)
	tx, err := sqlDB.BeginTx(ctx, nil)
	if err != nil {
		sqlDB.Close()
		return AccessProjectImportResult{}, err
	}

	var envM, vegM, otherM, humusM, mineralM, auditM, metaM, adminM streamTableMetrics
	var importedSUs []string
	totalMalformed := 0
	totalOrphan := 0

	writeTables := func() error {
		var deferredIndexes []string
		for _, tblPlan := range ddlPlan.Tables {
			for _, mapping := range tblPlan.Schema {
				if mapping.SQL != nil {
					stmtText := strings.TrimSpace(*mapping.SQL)
					if strings.HasPrefix(strings.ToUpper(stmtText), "CREATE INDEX") || strings.HasPrefix(strings.ToUpper(stmtText), "CREATE UNIQUE INDEX") {
						deferredIndexes = append(deferredIndexes, stmtText)
						continue
					}
					if _, err := tx.ExecContext(ctx, stmtText); err != nil {
						return fmt.Errorf("create schema for %s: %w", tblPlan.TargetTable, err)
					}
				}
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
		quarantineStmt, err := tx.PrepareContext(ctx, `INSERT INTO "__VPRO_ImportQuarantine" ("SourceTable","SourceRow","PlotNumber","Reason","PayloadJSON") VALUES (?,?,?,?,?)`)
		if err != nil {
			return err
		}
		defer quarantineStmt.Close()

		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
			"ChildTable" TEXT NOT NULL,
			"ID" INTEGER NOT NULL,
			PRIMARY KEY ("ChildTable", "ID")
		)`); err != nil {
			return err
		}
		childIdStmt, err := tx.PrepareContext(ctx, `INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)`)
		if err != nil {
			return err
		}
		defer childIdStmt.Close()

		coalesceFalseBool := func(v any) any {
			if v == nil {
				return int64(0)
			}
			return v
		}
		auditOverrides := map[string]func(any) any{
			"Project": func(any) any { return targetProject },
			"Restore": coalesceFalseBool,
			"Flag":    coalesceFalseBool,
		}
		auditComputed := map[string]func([]any, map[string]int) any{
			"Project": func([]any, map[string]int) any { return targetProject },
		}

		validEnvPlots := make(map[string]struct{}, 1024)
		accumulate := func(m streamTableMetrics) {
			totalMalformed += m.malformedRows
			totalOrphan += m.orphanRows
		}

		switch version {
		case "VP08":
			if envM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, envActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Env", dedupePlotKey: true, recordEnvPlots: validEnvPlots},
			}); err != nil {
				return err
			}
			accumulate(envM)
			if vegM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, vegActualName, validEnvPlots, []streamInsertSpec{
				{targetTable: targetProject + "_Veg", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Veg")},
			}); err != nil {
				return err
			}
			accumulate(vegM)
			if otherM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, otherActualName, validEnvPlots, []streamInsertSpec{
				{targetTable: targetProject + "_Other", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Other")},
			}); err != nil {
				return err
			}
			accumulate(otherM)
			if humusM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, humusActualName, validEnvPlots, []streamInsertSpec{
				{targetTable: targetProject + "_Humus", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Humus")},
			}); err != nil {
				return err
			}
			accumulate(humusM)
			if mineralM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, mineralActualName, validEnvPlots, []streamInsertSpec{
				{targetTable: targetProject + "_Mineral", requireEnvPlot: true, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Mineral")},
			}); err != nil {
				return err
			}
			accumulate(mineralM)
			if auditM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, auditActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Audit", computed: auditComputed, columnOverrides: auditOverrides, childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Audit")},
			}); err != nil {
				return err
			}
			accumulate(auditM)
			if metaM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, metaActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Metadata", childIdentityTable: vprocore.QuoteHeaderIdentifier(targetProject + "_Metadata")},
			}); err != nil {
				return err
			}
			accumulate(metaM)
			if adminM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, adminActualName, validEnvPlots, []streamInsertSpec{
				{targetTable: targetProject + "_Admin", requireEnvPlot: true, plotSourceCol: "Plot", dedupePlotKey: true},
			}); err != nil {
				return err
			}
			accumulate(adminM)
		case "VP07":
			if envM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, envActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Env", targetToSource: vp07EnvMapping, dedupePlotKey: true, recordEnvPlots: validEnvPlots},
				{targetTable: targetProject + "_Admin", targetToSource: vp07AdminFromEnvMapping},
			}); err != nil {
				return err
			}
			accumulate(envM)
			adminM = streamTableMetrics{actualSourceTable: envActualName, columnCount: 20, importedRows: envM.importedRows}
		case "VP06":
			if envM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, envActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Env", targetToSource: vp06EnvMapping, dedupePlotKey: true, recordEnvPlots: validEnvPlots},
				{targetTable: targetProject + "_Admin", targetToSource: vp06AdminFromEnvMapping},
			}); err != nil {
				return err
			}
			accumulate(envM)
			adminM = streamTableMetrics{actualSourceTable: envActualName, columnCount: 20, importedRows: envM.importedRows}
		case "VP05":
			rCheck, err := db.Scan(envActualName)
			if err != nil {
				return err
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
				return errors.New("VP05 Env table is missing LongitudeDegrees or LatitudeDegrees")
			}
			getCol := func(r []any, idx map[string]int, name string) any {
				if i, ok := idx[strings.ToLower(name)]; ok && i >= 0 && i < len(r) {
					return r[i]
				}
				return nil
			}
			computed := map[string]func([]any, map[string]int) any{
				"Longitude": func(r []any, idx map[string]int) any {
					return convertLongLatToDeg(getCol(r, idx, "LongitudeDegrees"), getCol(r, idx, "LongitudeMinutes"), getCol(r, idx, "LongitudeSeconds"))
				},
				"Latitude": func(r []any, idx map[string]int) any {
					return convertLongLatToDeg(getCol(r, idx, "LatitudeDegrees"), getCol(r, idx, "LatitudeMinutes"), getCol(r, idx, "LatitudeSeconds"))
				},
			}
			if envM, err = streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, envActualName, nil, []streamInsertSpec{
				{targetTable: targetProject + "_Env", targetToSource: vp05EnvMapping, computed: computed, dedupePlotKey: true, recordEnvPlots: validEnvPlots},
				{targetTable: targetProject + "_Admin", targetToSource: vp05AdminFromEnvMapping},
			}); err != nil {
				return err
			}
			accumulate(envM)
			adminM = streamTableMetrics{actualSourceTable: envActualName, columnCount: 20, importedRows: envM.importedRows}
		}

		if version != "VP08" {
			legacyPairs := []struct {
				suffix string
				src    string
				cols   []string
				reqEnv bool
				dst    *streamTableMetrics
			}{
				{"Veg", vegActualName, legacyVegColumns, true, &vegM},
				{"Other", otherActualName, legacyOtherColumns, true, &otherM},
				{"Humus", humusActualName, legacyHumusColumns, true, &humusM},
				{"Mineral", mineralActualName, legacyMineralColumns, true, &mineralM},
				{"Audit", auditActualName, legacyAuditColumns, false, &auditM},
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
				m, sErr := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, childIdStmt, item.src, envSet, []streamInsertSpec{spec})
				if sErr != nil {
					return sErr
				}
				*item.dst = m
				accumulate(m)
			}
		}

		tableExistsCI := func(name string) (bool, error) {
			var exists bool
			err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE)`, name).Scan(&exists)
			return exists, err
		}

		for _, su := range suSourceTables {
			targetName := su.prefix + "_SU"
			exists, exErr := tableExistsCI(targetName)
			if exErr != nil {
				return exErr
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
			suM, suErr := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, nil, su.table, validEnvPlots, []streamInsertSpec{
				{
					targetTable:    targetName,
					targetToSource: [][2]string{{"PlotNumber", "PlotNumber"}, {"SiteUnit", "SiteUnit"}},
					requireEnvPlot: true,
					dedupePlotKey:  true,
				},
			})
			if suErr != nil {
				return suErr
			}
			accumulate(suM)
			if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, targetName, su.description); err != nil {
				return err
			}
			importedSUs = append(importedSUs, su.prefix)
		}

		for _, comp := range companionTables {
			targetName := comp.prefix + "_" + comp.kind
			exists, exErr := tableExistsCI(targetName)
			if exErr != nil {
				return exErr
			}
			if exists {
				continue
			}
			qTbl := vprocore.QuoteHeaderIdentifier(targetName)
			switch comp.kind {
			case "Hierarchy":
				if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTbl+` (
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
				CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_Parent")+` ON `+qTbl+` ("Parent");
				CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_Level")+` ON `+qTbl+` ("Level")`); err != nil {
					return err
				}
			case "Lump":
				if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTbl+` (
					"LumpCode" VARCHAR,
					"SppCode" VARCHAR,
					"Use" BOOLEAN
				);
				CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_LumpCode")+` ON `+qTbl+` ("LumpCode");
				CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+targetName+"_SppCode")+` ON `+qTbl+` ("SppCode")`); err != nil {
					return err
				}
			case "Profile":
				if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTbl+` (
					"Order" SMALLINT,
					"Table" VARCHAR,
					"Field" VARCHAR,
					"Operator" VARCHAR,
					"Layer" VARCHAR,
					"Species" VARCHAR,
					"Criteria" VARCHAR,
					"Operation" VARCHAR,
					"PlotCount" INTEGER
				)`); err != nil {
					return err
				}
			}
			cM, cErr := streamAccessTableIntoSQLite(ctx, db, tx, quarantineStmt, nil, comp.sourceTable, nil, []streamInsertSpec{
				{targetTable: targetName},
			})
			if cErr != nil {
				return cErr
			}
			accumulate(cM)
			if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, targetName, comp.description); err != nil {
				return err
			}
		}

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
		if err := seedImportedChildIdentities(ctx, tx, sourceProject, targetProject); err != nil {
			return err
		}
		return nil
	}

	if err := writeTables(); err != nil {
		_ = tx.Rollback()
		_ = sqlDB.Close()
		return AccessProjectImportResult{}, err
	}
	if err := tx.Commit(); err != nil {
		_ = sqlDB.Close()
		return AccessProjectImportResult{}, err
	}
	_, _ = sqlDB.ExecContext(ctx, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode = DELETE;")
	if err := sqlDB.Close(); err != nil {
		return AccessProjectImportResult{}, err
	}

	// Verify source Access file was not mutated during import
	_, sourceDigestAfter, err := resolveAccessSourcePath(resolvedSource)
	if err != nil || sourceDigestAfter != sourceDigestBefore {
		return AccessProjectImportResult{}, errors.New("source Access database changed during import; publication aborted")
	}

	// Verify staged SQLite file passes VP08 inspection before linking
	inspected, err := vprocore.InspectFileContext(ctx, tmpPath)
	if err != nil {
		return AccessProjectImportResult{}, fmt.Errorf("verify staged SQLite project: %w", err)
	}
	compatible := false
	for _, p := range inspected {
		if p.Name == targetProject && p.Compatible {
			compatible = true
			break
		}
	}
	if !compatible {
		return AccessProjectImportResult{}, errors.New("staged SQLite database did not pass VP08 compatibility validation")
	}

	currentParent, err := os.Stat(filepath.Dir(resolvedDest))
	if err != nil || !os.SameFile(parentInfo, currentParent) {
		return AccessProjectImportResult{}, errors.New("destination parent directory changed during import; publication aborted")
	}
	if err := sqlutil.LinkOrCreateExclusive(tmpPath, resolvedDest); err != nil {
		return AccessProjectImportResult{}, fmt.Errorf("publish SQLite database %s: %w", resolvedDest, err)
	}
	published = true
	_ = os.Remove(tmpPath)

	if err := vprocore.InitializeSQLiteWAL(ctx, resolvedDest); err != nil {
		_ = os.Remove(resolvedDest + "-wal")
		_ = os.Remove(resolvedDest + "-shm")
		_ = os.Remove(resolvedDest)
		return AccessProjectImportResult{}, fmt.Errorf("initialize SQLite WAL on %s: %w", resolvedDest, err)
	}

	destDigestHex, err := streamFileSHA256(resolvedDest)
	if err != nil {
		return AccessProjectImportResult{}, err
	}

	summaries := []AccessImportTableSummary{
		{Suffix: "Env", SourceTable: envActualName, Description: "VP08", RowCount: envM.importedRows, ColumnCount: 112, Present: true, Action: "Imported"},
		{Suffix: "Veg", SourceTable: vegActualName, Description: "VP08", RowCount: vegM.importedRows, ColumnCount: 44, Present: true, Action: "Imported"},
		{Suffix: "Other", SourceTable: otherActualName, Description: "VP08", RowCount: otherM.importedRows, ColumnCount: 11, Present: true, Action: "Imported"},
		{Suffix: "Humus", SourceTable: humusActualName, Description: "VP08", RowCount: humusM.importedRows, ColumnCount: 18, Present: true, Action: "Imported"},
		{Suffix: "Mineral", SourceTable: mineralActualName, Description: "VP08", RowCount: mineralM.importedRows, ColumnCount: 28, Present: true, Action: "Imported"},
		{Suffix: "Audit", SourceTable: auditActualName, Description: "VP08", RowCount: auditM.importedRows, ColumnCount: 11, Present: true, Action: "Imported"},
		{Suffix: "Metadata", SourceTable: metaActualName, Description: "VP08", RowCount: metaM.importedRows, ColumnCount: 75, Present: version == "VP08", Action: "Imported"},
		{Suffix: "Admin", SourceTable: adminActualName, Description: "VP08", RowCount: adminM.importedRows, ColumnCount: 20, Present: true, Action: "Imported"},
	}

	result := AccessProjectImportResult{
		SourcePath:              resolvedSource,
		SourceProject:           sourceProject,
		SourceVersion:           version,
		ConversionMode:          fmt.Sprintf("%s -> VP08", version),
		TargetProject:           targetProject,
		DestinationPath:         resolvedDest,
		DestinationSHA:          destDigestHex,
		PlotCount:               envM.importedRows,
		QuarantinedMalformedRow: totalMalformed,
		QuarantinedOrphanRows:   totalOrphan,
		Tables:                  summaries,
		ImportedSUs:             importedSUs,
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
	} else {
		state, stateErr := s.Projects.GetState(ctx)
		if stateErr == nil {
			result.State = &state
		}
	}
	return result, nil
}
