package cloudsync

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/jackc/pgx/v5"
	"math"
	"os"
	"path/filepath"
	"strings"
)

func cleanTokens(items []string) []string {
	var out []string
	seen := map[string]struct{}{}
	for _, raw := range items {
		t := strings.TrimSpace(raw)
		if t == "" {
			continue
		}
		if _, dup := seen[t]; !dup {
			seen[t] = struct{}{}
			out = append(out, t)
		}
	}
	return out
}

func buildSubsetWhereClause(filter SubsetFilter, hasPostGISGeom bool) (whereSQL string, args []any, err error) {
	zones := cleanTokens(filter.Zones)
	subzones := cleanTokens(filter.SubZones)
	projectIDs := cleanTokens(filter.ProjectIDs)
	plots := cleanTokens(filter.PlotNumbers)

	if len(filter.BBox) != 0 && len(filter.BBox) != 4 {
		return "", nil, errors.New("bbox filter must contain exactly 4 numbers [minLon, minLat, maxLon, maxLat]")
	}
	var clauses []string
	nextArg := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}

	if len(zones) > 0 {
		clauses = append(clauses, fmt.Sprintf(`"Zone" = ANY(%s)`, nextArg(zones)))
	}
	if len(subzones) > 0 {
		clauses = append(clauses, fmt.Sprintf(`"SubZone" = ANY(%s)`, nextArg(subzones)))
	}
	if len(projectIDs) > 0 {
		clauses = append(clauses, fmt.Sprintf(`"ProjectID" = ANY(%s)`, nextArg(projectIDs)))
	}
	if len(plots) > 0 {
		// Byte-exact TEXT array match in PostgreSQL preserves leading-zero PlotNumbers ('00337' != '337')
		clauses = append(clauses, fmt.Sprintf(`"PlotNumber" = ANY(%s)`, nextArg(plots)))
	}
	if len(filter.BBox) == 4 {
		minLon, minLat, maxLon, maxLat := filter.BBox[0], filter.BBox[1], filter.BBox[2], filter.BBox[3]
		for _, f := range filter.BBox {
			if math.IsNaN(f) || math.IsInf(f, 0) {
				return "", nil, errors.New("bbox coordinates must be finite numbers")
			}
		}
		if minLon > maxLon || minLat > maxLat {
			return "", nil, errors.New("bbox requires minLon <= maxLon and minLat <= maxLat")
		}
		pMinLon := nextArg(minLon)
		pMinLat := nextArg(minLat)
		pMaxLon := nextArg(maxLon)
		pMaxLat := nextArg(maxLat)
		if hasPostGISGeom {
			clauses = append(clauses, fmt.Sprintf(
				`(geom && public.ST_MakeEnvelope(%s, %s, %s, %s, 4326) AND "Longitude" BETWEEN %s AND %s AND "Latitude" BETWEEN %s AND %s)`,
				pMinLon, pMinLat, pMaxLon, pMaxLat, pMinLon, pMaxLon, pMinLat, pMaxLat,
			))
		} else {
			clauses = append(clauses, fmt.Sprintf(
				`("Longitude" BETWEEN %s AND %s AND "Latitude" BETWEEN %s AND %s)`,
				pMinLon, pMaxLon, pMinLat, pMaxLat,
			))
		}
	}

	if len(clauses) == 0 && !filter.AllowFullCheckout {
		return "", nil, errors.New("at least one subset filter (Zone, SubZone, ProjectID, PlotNumber, or BBox) is required")
	}
	if filter.Limit < 0 {
		return "", nil, errors.New("subset limit must be >= 0")
	}
	if len(clauses) == 0 {
		return "", args, nil
	}
	return "WHERE " + strings.Join(clauses, " AND "), args, nil
}

func hasEnvGeomColumn(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}) bool {
	var ok bool
	_ = q.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM information_schema.columns
			WHERE table_schema = 'becmaster' AND table_name = 'env' AND column_name = 'geom'
		)
	`).Scan(&ok)
	return ok
}

// PreviewBECMasterSubset previews matching plot and vegetation row counts for a regional checkout filter.
func (m *Manager) PreviewBECMasterSubset(ctx context.Context, filter SubsetFilter) (SubsetPreview, error) {
	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return SubsetPreview{}, err
	}
	hasGeom := hasEnvGeomColumn(ctx, pool)
	whereSQL, args, err := buildSubsetWhereClause(filter, hasGeom)
	if err != nil {
		return SubsetPreview{}, err
	}

	limitClause := ""
	if filter.Limit > 0 {
		limitClause = fmt.Sprintf(" LIMIT %d", filter.Limit)
	}
	cte := fmt.Sprintf(`WITH matched AS (SELECT "PlotNumber", COALESCE("Zone", '(Unassigned)') AS z FROM becmaster.env %s ORDER BY "PlotNumber"%s)`, whereSQL, limitClause)

	var plotCount int
	var vegCount int64
	if err := pool.QueryRow(ctx, cte+`
		SELECT
			(SELECT COUNT(*) FROM matched),
			(SELECT COUNT(*) FROM becmaster.veg v WHERE v."PlotNumber" IN (SELECT "PlotNumber" FROM matched))
	`, args...).Scan(&plotCount, &vegCount); err != nil {
		return SubsetPreview{}, wrapRedactedError("preview BECMaster subset", err, creds)
	}

	zones := map[string]int{}
	zRows, err := pool.Query(ctx, cte+` SELECT z, COUNT(*) FROM matched GROUP BY z ORDER BY z`, args...)
	if err != nil {
		return SubsetPreview{}, wrapRedactedError("preview BECMaster zone breakdown", err, creds)
	}
	for zRows.Next() {
		var z string
		var c int
		if sErr := zRows.Scan(&z, &c); sErr == nil {
			zones[z] = c
		}
	}
	zRows.Close()

	samplePlots := []string{}
	sRows, err := pool.Query(ctx, cte+` SELECT "PlotNumber" FROM matched ORDER BY "PlotNumber" LIMIT 20`, args...)
	if err == nil {
		for sRows.Next() {
			var p string
			if sRows.Scan(&p) == nil {
				samplePlots = append(samplePlots, p)
			}
		}
		sRows.Close()
	}

	sensitivePlots := 0
	var hasSppAttr bool
	if qErr := pool.QueryRow(ctx, `SELECT to_regclass('standards.usys_spp_attributes') IS NOT NULL`).Scan(&hasSppAttr); qErr == nil && hasSppAttr {
		_ = pool.QueryRow(ctx, cte+`
			SELECT COUNT(DISTINCT v."PlotNumber")
			FROM becmaster.veg v
			INNER JOIN standards.usys_spp_attributes a ON UPPER(TRIM(v."Species")) = UPPER(TRIM(a."Code"))
			WHERE v."PlotNumber" IN (SELECT "PlotNumber" FROM matched)
			  AND COALESCE(UPPER(TRIM(a."Codetype")), '') <> 'S'
			  AND UPPER(TRIM(COALESCE(a."RedBlueList", ''))) IN ('R', 'B', 'RED', 'BLUE')
		`, args...).Scan(&sensitivePlots)
	}

	return SubsetPreview{
		MatchingPlots:     plotCount,
		MatchingVeg:       vegCount,
		SensitivePlots:    sensitivePlots,
		CoordinatesMasked: creds.ActiveRoleMode != RoleModeCustodian && sensitivePlots > 0,
		SamplePlots:       samplePlots,
		ZoneBreakdown:     zones,
	}, nil
}

// PullBECMasterSubset streams a filtered BECMaster subset into a fresh local VP08 SQLite .db
// (WAL mode, _table_metadata 'VP08', __VPRO_ChildIdentity seeded) and logs to becmaster.download_log.
func (m *Manager) PullBECMasterSubset(ctx context.Context, s *vprocore.ContextService, contextID string, req PullSubsetRequest) (PullSubsetResult, error) {
	if s == nil {
		return PullSubsetResult{}, errors.New("project context service is unavailable")
	}
	targetProject, err := validateSplinterProjectName(req.TargetProject)
	if err != nil {
		return PullSubsetResult{}, err
	}

	var projectsDir, vlistsPath string
	actor := "VProUser"
	if _, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		projectsDir = filepath.Join(plots.Projects.Root, "projects")
		vlistsPath = plots.Projects.SupportPaths["VLists"]
		if u := strings.TrimSpace(plots.CurrentUser); u != "" {
			actor = u
		}
		return struct{}{}, nil
	}); err != nil {
		return PullSubsetResult{}, err
	}

	destReq := strings.TrimSpace(req.DestinationPath)
	if destReq == "" {
		destReq = filepath.Join(projectsDir, targetProject+".db")
	} else if !strings.EqualFold(filepath.Ext(destReq), ".db") {
		destReq += ".db"
	}
	resolvedDest, parentInfo, err := vprocore.FreshSQLiteDestination(destReq, "Project")
	if err != nil {
		return PullSubsetResult{}, err
	}

	review, err := s.ReadNewProjectTemplates(ctx, contextID)
	if err != nil {
		return PullSubsetResult{}, err
	}
	ddlPlan, err := vprocore.PlanNewProjectDDL(ctx, targetProject, review)
	if err != nil {
		return PullSubsetResult{}, err
	}

	pool, creds, err := m.AcquirePool(ctx, "")
	if err != nil {
		return PullSubsetResult{}, err
	}
	hasGeom := hasEnvGeomColumn(ctx, pool)
	whereSQL, args, err := buildSubsetWhereClause(req.Filter, hasGeom)
	if err != nil {
		return PullSubsetResult{}, err
	}
	limitClause := ""
	if req.Filter.Limit > 0 {
		limitClause = fmt.Sprintf(" LIMIT %d", req.Filter.Limit)
	}

	// Fetch matched plot list inside a REPEATABLE READ PostgreSQL read transaction so parent & child tables are snapshot-consistent.
	pgTx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return PullSubsetResult{}, wrapRedactedError("begin subset snapshot", err, creds)
	}
	defer func() { _ = pgTx.Rollback(ctx) }()

	pRows, err := pgTx.Query(ctx, fmt.Sprintf(`SELECT "PlotNumber" FROM becmaster.env %s ORDER BY "PlotNumber"%s`, whereSQL, limitClause), args...)
	if err != nil {
		return PullSubsetResult{}, wrapRedactedError("query matching BECMaster plots", err, creds)
	}
	var plotList []string
	for pRows.Next() {
		var p string
		if err := pRows.Scan(&p); err != nil {
			pRows.Close()
			return PullSubsetResult{}, wrapRedactedError("scan matching BECMaster plot", err, creds)
		}
		plotList = append(plotList, p)
	}
	pRows.Close()
	if err := pRows.Err(); err != nil {
		return PullSubsetResult{}, wrapRedactedError("read matching BECMaster plots", err, creds)
	}
	if len(plotList) == 0 {
		return PullSubsetResult{}, errors.New("subset filter matched 0 plots in BECMaster")
	}

	maskSensitive := creds.ActiveRoleMode != RoleModeCustodian || req.MaskSensitiveCoordinates
	sensitivePlots := map[string]struct{}{}
	if maskSensitive {
		sensitivePlots, err = findSensitivePlotsForSubsetPG(ctx, pgTx, plotList, vlistsPath)
		if err != nil {
			return PullSubsetResult{}, wrapRedactedError("identify RedBlueList sensitive plots", err, creds)
		}
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-pgsubset-*.db")
	if err != nil {
		return PullSubsetResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0o600); err != nil {
		_ = tmpFile.Close()
		return PullSubsetResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return PullSubsetResult{}, err
	}

	sqlDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL")
	if err != nil {
		return PullSubsetResult{}, err
	}
	sqlDB.SetMaxOpenConns(1)
	sqTx, err := sqlDB.BeginTx(ctx, nil)
	if err != nil {
		_ = sqlDB.Close()
		return PullSubsetResult{}, err
	}

	var vegN, humusN, mineralN, otherN, metaN int
	populate := func() error {
		for _, tblPlan := range ddlPlan.Tables {
			for _, mapping := range tblPlan.Schema {
				if mapping.SQL != nil {
					if _, err := sqTx.ExecContext(ctx, *mapping.SQL); err != nil {
						return fmt.Errorf("create SQLite DDL for %s: %w", tblPlan.TargetTable, err)
					}
				}
			}
		}
		if _, err := sqTx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		for _, suffix := range vprocore.CoreTables {
			if _, err := sqTx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, targetProject+"_"+suffix); err != nil {
				return err
			}
		}
		if _, err := sqTx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" ("ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable", "ID"))`); err != nil {
			return err
		}

		streamPGToSQLite := func(pgTbl, plotCol, sqliteSuffix string, cols []ColumnSpec) (int, error) {
			sqlQuery := fmt.Sprintf(`SELECT %s FROM becmaster.%s WHERE %s = ANY($1)`, quotedColumnCSV(cols), quotePGIdent(pgTbl), quotePGIdent(plotCol))
			rows, qErr := pgTx.Query(ctx, sqlQuery, plotList)
			if qErr != nil {
				return 0, qErr
			}
			defer rows.Close()

			marks := make([]string, len(cols))
			idColIdx, sppColIdx, plotColIdx := -1, -1, -1
			for i, col := range cols {
				marks[i] = "?"
				if col.Name == "ID" {
					idColIdx = i
				} else if sqliteSuffix == "Veg" && col.Name == "Species" {
					sppColIdx = i
				} else if sqliteSuffix == "Env" && col.Name == "PlotNumber" {
					plotColIdx = i
				}
			}
			enforceUniqueID := sqliteSuffix == "Humus" || sqliteSuffix == "Mineral" || sqliteSuffix == "Other" || sqliteSuffix == "Veg"
			usedIDs := map[int64]bool{}
			nextSyntheticID := int64(100000000)

			stmt, sErr := sqTx.PrepareContext(ctx, fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
				quotePGIdent(targetProject+"_"+sqliteSuffix), quotedColumnCSV(cols), strings.Join(marks, ", ")))
			if sErr != nil {
				return 0, sErr
			}
			defer stmt.Close()

			count := 0
			for rows.Next() {
				vals, vErr := rows.Values()
				if vErr != nil {
					return 0, vErr
				}
				rowArgs := make([]any, len(cols))
				for i, col := range cols {
					rowArgs[i] = CanonicalizePGToSQLite(col, vals[i])
				}
				if sppColIdx >= 0 && rowArgs[sppColIdx] == nil {
					rowArgs[sppColIdx] = ""
				}
				if sqliteSuffix == "Env" && len(sensitivePlots) > 0 && plotColIdx >= 0 {
					if plotNum, ok := rowArgs[plotColIdx].(string); ok {
						if _, isSens := sensitivePlots[plotNum]; isSens {
							MaskSensitiveEnvRow(cols, rowArgs)
						}
					}
				}
				if enforceUniqueID && idColIdx >= 0 {
					var idVal int64
					hasID := false
					if iv, ok := rowArgs[idColIdx].(int64); ok {
						idVal = iv
						hasID = true
					}
					if !hasID || usedIDs[idVal] {
						for usedIDs[nextSyntheticID] {
							nextSyntheticID++
						}
						idVal = nextSyntheticID
						nextSyntheticID++
						rowArgs[idColIdx] = idVal
					}
					usedIDs[idVal] = true
				}
				if _, eErr := stmt.ExecContext(ctx, rowArgs...); eErr != nil {
					return 0, eErr
				}
				count++
			}
			return count, rows.Err()
		}

		if _, err := streamPGToSQLite("env", "PlotNumber", "Env", VP08EnvColumns); err != nil {
			return fmt.Errorf("stream env: %w", err)
		}
		if _, err := streamPGToSQLite("admin", "Plot", "Admin", VP08AdminColumns); err != nil {
			return fmt.Errorf("stream admin: %w", err)
		}
		if vegN, err = streamPGToSQLite("veg", "PlotNumber", "Veg", VP08VegColumns); err != nil {
			return fmt.Errorf("stream veg: %w", err)
		}
		if humusN, err = streamPGToSQLite("humus", "PlotNumber", "Humus", VP08HumusColumns); err != nil {
			return fmt.Errorf("stream humus: %w", err)
		}
		if mineralN, err = streamPGToSQLite("mineral", "PlotNumber", "Mineral", VP08MineralColumns); err != nil {
			return fmt.Errorf("stream mineral: %w", err)
		}
		if otherN, err = streamPGToSQLite("other", "PlotNumber", "Other", VP08OtherColumns); err != nil {
			return fmt.Errorf("stream other: %w", err)
		}
		if _, err := streamPGToSQLite("audit", "PlotNumber", "Audit", VP08AuditColumns); err != nil {
			return fmt.Errorf("stream audit: %w", err)
		}

		// Normalize imported Audit Project column to targetProject so PlotEntryService audit ownership checks pass cleanly!
		if _, err := sqTx.ExecContext(ctx, fmt.Sprintf(`UPDATE %s SET "Project" = ?`, quotePGIdent(targetProject+"_Audit")), targetProject); err != nil {
			return err
		}

		// Stream matching Metadata rows by ProjectIDs referenced in <Target>_Env
		projIDRows, pErr := sqTx.QueryContext(ctx, fmt.Sprintf(`SELECT DISTINCT "ProjectID" FROM %s WHERE typeof("ProjectID") = 'text' AND "ProjectID" <> ''`, quotePGIdent(targetProject+"_Env")))
		if pErr != nil {
			return pErr
		}
		var refProjIDs []string
		for projIDRows.Next() {
			var pid string
			if projIDRows.Scan(&pid) == nil {
				refProjIDs = append(refProjIDs, pid)
			}
		}
		projIDRows.Close()

		if len(refProjIDs) > 0 {
			mRows, mErr := pgTx.Query(ctx, fmt.Sprintf(`SELECT %s FROM becmaster.metadata WHERE "ProjectID" = ANY($1)`, quotedColumnCSV(VP08MetadataColumns)), refProjIDs)
			if mErr != nil {
				return mErr
			}
			defer mRows.Close()
			marks := make([]string, len(VP08MetadataColumns))
			metaIDIdx := -1
			for i, col := range VP08MetadataColumns {
				marks[i] = "?"
				if col.Name == "ID" {
					metaIDIdx = i
				}
			}
			usedMetaIDs := map[int64]bool{}
			nextMetaID := int64(1)
			mStmt, sErr := sqTx.PrepareContext(ctx, fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
				quotePGIdent(targetProject+"_Metadata"), quotedColumnCSV(VP08MetadataColumns), strings.Join(marks, ", ")))
			if sErr != nil {
				return sErr
			}
			defer mStmt.Close()
			for mRows.Next() {
				vals, vErr := mRows.Values()
				if vErr != nil {
					return vErr
				}
				rowArgs := make([]any, len(VP08MetadataColumns))
				for i, col := range VP08MetadataColumns {
					rowArgs[i] = CanonicalizePGToSQLite(col, vals[i])
				}
				if metaIDIdx >= 0 {
					var mid int64
					hasMID := false
					if iv, ok := rowArgs[metaIDIdx].(int64); ok && iv > 0 {
						mid = iv
						hasMID = true
					}
					if !hasMID || usedMetaIDs[mid] {
						for usedMetaIDs[nextMetaID] {
							nextMetaID++
						}
						mid = nextMetaID
						nextMetaID++
						rowArgs[metaIDIdx] = mid
					}
					usedMetaIDs[mid] = true
				}
				if _, eErr := mStmt.ExecContext(ctx, rowArgs...); eErr != nil {
					return eErr
				}
				metaN++
			}
			if err := mRows.Err(); err != nil {
				return err
			}
		}
		if metaN == 0 {
			// Seed default metadata row so VP08 project metadata panels always have >=1 row
			if _, err := sqTx.ExecContext(ctx, fmt.Sprintf(`INSERT INTO %s ("ProjectID", "ProjectTitle", "ID") VALUES (?, ?, 1)`, quotePGIdent(targetProject+"_Metadata")), targetProject, targetProject+" BECMaster Subset"); err != nil {
				return err
			}
			metaN = 1
		}

		// Seed __VPRO_ChildIdentity for all child tables in local splinter .db
		for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other", "Metadata", "Audit"} {
			fullTbl := targetProject + "_" + suffix
			qFull := quotePGIdent(fullTbl)
			if _, err := sqTx.ExecContext(ctx, fmt.Sprintf(
				`INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") SELECT ?, "ID" FROM %s WHERE typeof("ID") = 'integer' AND "ID" >= 0`,
				qFull,
			), qFull); err != nil {
				return err
			}
		}
		return nil
	}

	if err := populate(); err != nil {
		_ = sqTx.Rollback()
		_ = sqlDB.Close()
		return PullSubsetResult{}, wrapRedactedError("populate local subset SQLite database", err, creds)
	}
	if err := sqTx.Commit(); err != nil {
		_ = sqlDB.Close()
		return PullSubsetResult{}, err
	}
	if err := sqlDB.Close(); err != nil {
		return PullSubsetResult{}, err
	}
	_ = pgTx.Rollback(ctx) // Close read-only snapshot cleanly

	inspected, err := vprocore.InspectFileContext(ctx, tmpPath)
	if err != nil {
		return PullSubsetResult{}, fmt.Errorf("inspect staged subset SQLite file: %w", err)
	}
	compatible := false
	for _, p := range inspected {
		if p.Name == targetProject && p.Compatible {
			compatible = true
			break
		}
	}
	if !compatible {
		return PullSubsetResult{}, errors.New("staged subset SQLite file did not pass VP08 compatibility verification")
	}

	curParent, err := os.Stat(filepath.Dir(resolvedDest))
	if err != nil || !os.SameFile(parentInfo, curParent) {
		return PullSubsetResult{}, errors.New("destination parent directory changed during subset pull")
	}
	if err := sqlutil.LinkOrCreateExclusive(tmpPath, resolvedDest); err != nil {
		return PullSubsetResult{}, err
	}
	published = true
	_ = os.Remove(tmpPath)

	if err := vprocore.InitializeSQLiteWAL(ctx, resolvedDest); err != nil {
		_ = os.Remove(resolvedDest + "-wal")
		_ = os.Remove(resolvedDest + "-shm")
		_ = os.Remove(resolvedDest)
		return PullSubsetResult{}, err
	}

	destSHA, err := streamFileSHA256Hex(resolvedDest)
	if err != nil {
		return PullSubsetResult{}, err
	}

	// Record download activity in becmaster.download_log (Schedule A 1.v)
	filterRaw, _ := json.Marshal(req.Filter)
	roleTier := creds.ActiveRoleMode
	if roleTier == "" {
		roleTier = RoleModeContributor
	}
	var logID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO becmaster.download_log (actor, role_tier, filter_json, format, plot_count)
		VALUES ($1, $2, $3::jsonb, 'VP08_SQLite', $4)
		RETURNING id
	`, actor, roleTier, string(filterRaw), len(plotList)).Scan(&logID); err != nil {
		return PullSubsetResult{}, wrapRedactedError("record download_log entry", err, creds)
	}

	var activated bool
	var newState *vprocore.ProjectState
	if req.ActivateOnSuccess {
		st, swErr := s.SwitchContext(contextID, vprocore.ContextSelection{
			Project:     targetProject,
			ProjectPath: resolvedDest,
			SU:          "None",
			Hierarchy:   "None",
		})
		if swErr == nil {
			_ = s.Projects.EnsureActiveProjectWAL(ctx)
			activated = true
			newState = &st
		}
	}

	return PullSubsetResult{
		TargetProject:        targetProject,
		DestinationPath:      resolvedDest,
		DestinationSHA:       destSHA,
		PlotCount:            len(plotList),
		VegCount:             vegN,
		HumusCount:           humusN,
		MineralCount:         mineralN,
		OtherCount:           otherN,
		MetadataCount:        metaN,
		MaskedSensitivePlots: len(sensitivePlots),
		DownloadLogID:        logID,
		Activated:            activated,
		State:                newState,
	}, nil
}
