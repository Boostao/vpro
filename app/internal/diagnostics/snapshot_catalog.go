package diagnostics

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"os"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func normalizeAccessBooleanValue(raw any) bool {
	switch v := raw.(type) {
	case nil:
		return false
	case bool:
		return v
	case int64:
		return v != 0
	case int:
		return v != 0
	case float64:
		return v != 0
	case []byte:
		return normalizeAccessBooleanValue(string(v))
	case string:
		trimmed := strings.ToLower(strings.TrimSpace(v))
		return trimmed == "-1" || trimmed == "1" || trimmed == "true" || trimmed == "yes"
	default:
		return false
	}
}

// ListSynthesisLumpTables discovers *_Lump tables in the active project database for synthesis folding.
func ListSynthesisLumpTables(ctx context.Context, contexts *vprocore.ContextService, contextID string) ([]SynthesisLumpTableOption, error) {
	if ctx == nil {
		return nil, errors.New("lump table discovery requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ []SynthesisLumpTableOption, resultErr error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		rows, err := tx.QueryContext(ctx,
			`SELECT name FROM "project".sqlite_master WHERE type='table' AND LOWER(name) LIKE '%\_lump' ESCAPE '\' ORDER BY name COLLATE NOCASE ASC`)
		if err != nil {
			return nil, err
		}
		var names []string
		for rows.Next() {
			var n string
			if err := rows.Scan(&n); err != nil {
				rows.Close()
				return nil, err
			}
			names = append(names, n)
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, err
		}

		out := make([]SynthesisLumpTableOption, 0, len(names))
		for _, tbl := range names {
			qTbl := vprocore.QuoteHeaderIdentifier(tbl)
			rRows, qErr := tx.QueryContext(ctx, `SELECT COALESCE(CAST("Use" AS TEXT), '0') FROM "project".`+qTbl)
			if qErr != nil {
				continue
			}
			total, active := 0, 0
			for rRows.Next() {
				var rawUse string
				if err := rRows.Scan(&rawUse); err == nil {
					total++
					if normalizeAccessBooleanValue(rawUse) {
						active++
					}
				}
			}
			rRows.Close()
			baseName := tbl
			if len(baseName) > 5 && strings.EqualFold(baseName[len(baseName)-5:], "_Lump") {
				baseName = baseName[:len(baseName)-5]
			}
			out = append(out, SynthesisLumpTableOption{
				Name:        baseName,
				TableName:   tbl,
				DBPath:      owner.Selection.ProjectPath,
				RowCount:    total,
				ActiveCount: active,
			})
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

func loadActiveLumpMap(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, rawLumpName, rawDBPath string) (map[string]string, string, error) {
	trimmed := strings.TrimSpace(rawLumpName)
	if trimmed == "" || strings.EqualFold(trimmed, "None") || strings.EqualFold(trimmed, "None_Lump") {
		return nil, "", nil
	}
	if !utf8.ValidString(trimmed) || strings.ContainsRune(trimmed, 0) {
		return nil, "", errors.New("lump table name must be valid UTF-8 without NUL")
	}
	base := trimmed
	if len(base) > 5 && strings.EqualFold(base[len(base)-5:], "_Lump") {
		base = base[:len(base)-5]
	}
	if !vprocore.ProjectNamePattern.MatchString(base) {
		return nil, "", fmt.Errorf("invalid lump table name %q", rawLumpName)
	}
	targetTable := base + "_Lump"

	scanLumpRows := func(rows *sql.Rows) (map[string]string, error) {
		defer rows.Close()
		mapping := map[string]string{}
		for rows.Next() {
			var lumpCode, sppCode sql.NullString
			var useRaw any
			if err := rows.Scan(&lumpCode, &sppCode, &useRaw); err != nil {
				return nil, err
			}
			if !normalizeAccessBooleanValue(useRaw) || !lumpCode.Valid || !sppCode.Valid {
				continue
			}
			cleanLump := strings.ToUpper(strings.TrimSpace(lumpCode.String))
			cleanSpp := strings.ToUpper(strings.TrimSpace(sppCode.String))
			if cleanLump != "" && cleanSpp != "" && cleanLump != cleanSpp {
				mapping[cleanSpp] = cleanLump
			}
		}
		return mapping, rows.Err()
	}

	dbPath := strings.TrimSpace(rawDBPath)
	if dbPath == "" || vprocore.SameDesktopPath(dbPath, owner.Selection.ProjectPath) {
		var actual string
		err := tx.QueryRowContext(ctx,
			`SELECT name FROM "project".sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`,
			targetTable,
		).Scan(&actual)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, "", fmt.Errorf("lump table %s does not exist in project %s", targetTable, owner.Selection.Project)
		}
		if err != nil {
			return nil, "", err
		}
		rows, err := tx.QueryContext(ctx,
			`SELECT CAST("LumpCode" AS TEXT), CAST("SppCode" AS TEXT), COALESCE(CAST("Use" AS TEXT), '0') FROM "project".`+vprocore.QuoteHeaderIdentifier(actual))
		if err != nil {
			return nil, "", err
		}
		mapping, err := scanLumpRows(rows)
		return mapping, actual, err
	}

	resolvedPath, err := vprocore.ExistingDatabasePath(dbPath)
	if err != nil {
		return nil, "", err
	}
	extDB, err := sqlutil.OpenReadOnly(resolvedPath)
	if err != nil {
		return nil, "", err
	}
	defer extDB.Close()

	var actual string
	if err := extDB.QueryRowContext(ctx,
		`SELECT name FROM sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`,
		targetTable,
	).Scan(&actual); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, "", fmt.Errorf("lump table %s does not exist in %s", targetTable, resolvedPath)
		}
		return nil, "", err
	}
	rows, err := extDB.QueryContext(ctx,
		`SELECT CAST("LumpCode" AS TEXT), CAST("SppCode" AS TEXT), COALESCE(CAST("Use" AS TEXT), '0') FROM `+vprocore.QuoteHeaderIdentifier(actual))
	if err != nil {
		return nil, "", err
	}
	mapping, err := scanLumpRows(rows)
	return mapping, actual, err
}

type dbFileStamp struct {
	path         string
	size         int64
	mtimeNano    int64
	dbHeader4    [4]byte
	walPresent   bool
	walSize      int64
	walMtimeNano int64
	shmHdr48     [48]byte
}

func statDBFileWithWAL(dbPath string) (dbFileStamp, bool) {
	if strings.TrimSpace(dbPath) == "" {
		return dbFileStamp{}, false
	}
	info, err := os.Stat(dbPath)
	if err != nil {
		return dbFileStamp{}, false
	}
	stamp := dbFileStamp{
		path:      dbPath,
		size:      info.Size(),
		mtimeNano: info.ModTime().UnixNano(),
	}
	if info.Size() >= 28 {
		if f, oErr := os.Open(dbPath); oErr == nil {
			_, _ = f.ReadAt(stamp.dbHeader4[:], 24)
			_ = f.Close()
		}
	}
	if walInfo, walErr := os.Stat(dbPath + "-wal"); walErr == nil {
		stamp.walPresent = true
		stamp.walSize = walInfo.Size()
		stamp.walMtimeNano = walInfo.ModTime().UnixNano()
		if shmFile, sErr := os.Open(dbPath + "-shm"); sErr == nil {
			_, _ = shmFile.ReadAt(stamp.shmHdr48[:], 0)
			_ = shmFile.Close()
		}
	}
	return stamp, true
}

type supportFileStampKey struct {
	vlists dbFileStamp
	vuser  dbFileStamp
}

type projectPlotsCacheKey struct {
	stamp   dbFileStamp
	project string
}

var (
	diagCatalogCacheMu     sync.Mutex
	cachedTaxonKey         supportFileStampKey
	cachedTaxonMap         map[string]SpeciesTaxonMeta
	cachedUnitNamesKey     supportFileStampKey
	cachedUnitNamesMap     map[string]string
	cachedProjectPlotsKey  projectPlotsCacheKey
	cachedProjectPlotsList []SynthesisUnitPlot
	cachedProjectPlotsIdx  map[string]int
	cachedProjectPlotsOK   bool
)

func advanceProjectPlotsCacheStamp(project string, preStamp, postStamp dbFileStamp, ok bool) {
	if !ok {
		return
	}
	diagCatalogCacheMu.Lock()
	if cachedProjectPlotsOK && cachedProjectPlotsKey.project == project && cachedProjectPlotsKey.stamp == preStamp {
		cachedProjectPlotsKey.stamp = postStamp
	}
	diagCatalogCacheMu.Unlock()
}

func buildSupportStampKey(owner *vprocore.SqliteContext) (supportFileStampKey, bool) {
	if owner == nil {
		return supportFileStampKey{}, false
	}
	vlStamp, vlOK := statDBFileWithWAL(owner.Attachments["VLists"])
	vuStamp, vuOK := statDBFileWithWAL(owner.Attachments["VUser"])
	if !vlOK || !vuOK {
		return supportFileStampKey{}, false
	}
	return supportFileStampKey{
		vlists: vlStamp,
		vuser:  vuStamp,
	}, true
}

func loadOrderedProjectPlots(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	project string,
	preTxStamp dbFileStamp,
	preTxOK bool,
) ([]SynthesisUnitPlot, map[string]int, error) {
	if preTxOK {
		curStamp, curOK := statDBFileWithWAL(owner.Selection.ProjectPath)
		if curOK && curStamp == preTxStamp {
			wantKey := projectPlotsCacheKey{stamp: preTxStamp, project: project}
			diagCatalogCacheMu.Lock()
			if cachedProjectPlotsOK && cachedProjectPlotsKey == wantKey {
				list := cachedProjectPlotsList
				idx := cachedProjectPlotsIdx
				diagCatalogCacheMu.Unlock()
				return list, idx, nil
			}
			diagCatalogCacheMu.Unlock()
		}
	}

	qEnvTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	qAdmTbl := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	adminMap := map[string]string{}
	adminRows, aErr := tx.QueryContext(ctx,
		`SELECT CAST("Plot" AS TEXT), COALESCE(CAST("UserSiteUnit" AS TEXT), '')
		 FROM `+qAdmTbl+`
		 WHERE typeof("Plot")='text'`)
	if aErr != nil {
		return nil, nil, aErr
	}
	for adminRows.Next() {
		var pNum, uSU string
		if err := adminRows.Scan(&pNum, &uSU); err != nil {
			adminRows.Close()
			return nil, nil, err
		}
		if _, dup := adminMap[pNum]; !dup {
			adminMap[pNum] = uSU
		}
	}
	if err := errors.Join(adminRows.Err(), adminRows.Close()); err != nil {
		return nil, nil, err
	}

	envRows, err := tx.QueryContext(ctx,
		`SELECT CAST(env."PlotNumber" AS TEXT),
		        COALESCE(CAST(env."FieldNumber" AS TEXT), ''),
		        COALESCE(CAST(env."Zone" AS TEXT), ''),
		        COALESCE(CAST(env."SubZone" AS TEXT), ''),
		        COALESCE(CAST(env."SiteSeries" AS TEXT), ''),
		        COALESCE(CAST(env."MoistureRegime" AS TEXT), ''),
		        COALESCE(CAST(env."NutrientRegime" AS TEXT), '')
		 FROM `+qEnvTbl+` AS env
		 WHERE typeof(env."PlotNumber")='text' AND TRIM(CAST(env."PlotNumber" AS TEXT)) <> ''
		 ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`)
	if err != nil {
		return nil, nil, err
	}
	ordered := make([]SynthesisUnitPlot, 0, len(adminMap))
	idxByPlot := make(map[string]int, len(adminMap))
	for envRows.Next() {
		var rec SynthesisUnitPlot
		if err := envRows.Scan(
			&rec.PlotNumber, &rec.FieldNumber, &rec.Zone, &rec.SubZone, &rec.SiteSeries,
			&rec.MoistureRegime, &rec.NutrientRegime,
		); err != nil {
			envRows.Close()
			return nil, nil, err
		}
		uSU, inAdmin := adminMap[rec.PlotNumber]
		if !inAdmin {
			continue
		}
		if _, dup := idxByPlot[rec.PlotNumber]; !dup {
			rec.UserSiteUnit = uSU
			idxByPlot[rec.PlotNumber] = len(ordered)
			ordered = append(ordered, rec)
		}
	}
	if err := errors.Join(envRows.Err(), envRows.Close()); err != nil {
		return nil, nil, err
	}

	if preTxOK {
		postStamp, postOK := statDBFileWithWAL(owner.Selection.ProjectPath)
		if postOK && postStamp == preTxStamp {
			diagCatalogCacheMu.Lock()
			cachedProjectPlotsKey = projectPlotsCacheKey{stamp: preTxStamp, project: project}
			cachedProjectPlotsList = ordered
			cachedProjectPlotsIdx = idxByPlot
			cachedProjectPlotsOK = true
			diagCatalogCacheMu.Unlock()
		}
	}
	return ordered, idxByPlot, nil
}

func loadFullSpeciesCatalog(ctx context.Context, tx *sql.Tx) (map[string]SpeciesTaxonMeta, error) {
	catalog := make(map[string]SpeciesTaxonMeta, 18000)

	userLifeformCol := ""
	pRows, pErr := tx.QueryContext(ctx, `PRAGMA "VUser".table_info("USysUserSpp")`)
	if pErr == nil {
		for pRows.Next() {
			var cid, notNull, pk int
			var name, ctype string
			var dflt any
			if err := pRows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err == nil {
				if name == "LifeForm" || name == "Lifeform" {
					userLifeformCol = name
					break
				}
			}
		}
		pRows.Close()
	}

	mRows, err := tx.QueryContext(ctx,
		`SELECT UPPER(TRIM(CAST("Code" AS TEXT))),
		        COALESCE(CAST("ScientificName" AS TEXT), ''),
		        COALESCE(CAST("EnglishName" AS TEXT), ''),
		        "Lifeform",
		        UPPER(TRIM(COALESCE(CAST("Codetype" AS TEXT), '')))
		 FROM "VLists"."USysAllSpecs"
		 WHERE "Code" IS NOT NULL
		 ORDER BY CASE WHEN UPPER(COALESCE(CAST("Codetype" AS TEXT), '')) = 'S' THEN 1 ELSE 0 END ASC, rowid ASC`,
	)
	if err != nil {
		return nil, err
	}
	for mRows.Next() {
		var code, sci, eng, codetype string
		var lf sql.NullInt64
		if err := mRows.Scan(&code, &sci, &eng, &lf, &codetype); err != nil {
			mRows.Close()
			return nil, err
		}
		if code == "" {
			continue
		}
		if _, exists := catalog[code]; exists {
			continue
		}
		var lfPtr *int
		if lf.Valid && lf.Int64 >= math.MinInt32 && lf.Int64 <= math.MaxInt32 {
			v := int(lf.Int64)
			lfPtr = &v
		}
		lfName, stratum := LifeformLabel(lfPtr)
		catalog[code] = SpeciesTaxonMeta{
			Species:         code,
			ScientificName:  strings.TrimSpace(sci),
			EnglishName:     strings.TrimSpace(eng),
			Lifeform:        lfPtr,
			LifeformName:    lfName,
			StratumGroup:    stratum,
			SourceCatalogue: "VLists",
		}
	}
	if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
		return nil, err
	}

	if userLifeformCol != "" {
		qLF := vprocore.QuoteHeaderIdentifier(userLifeformCol)
		uRows, uErr := tx.QueryContext(ctx,
			`SELECT UPPER(TRIM(CAST("Code" AS TEXT))),
			        COALESCE(CAST("ScientificName" AS TEXT), ''),
			        COALESCE(CAST("EnglishName" AS TEXT), ''),
			        `+qLF+`
			 FROM "VUser"."USysUserSpp"
			 WHERE "Code" IS NOT NULL
			 ORDER BY rowid ASC`,
		)
		if uErr == nil {
			for uRows.Next() {
				var code, sci, eng string
				var lf sql.NullInt64
				if err := uRows.Scan(&code, &sci, &eng, &lf); err != nil {
					uRows.Close()
					return nil, err
				}
				if code == "" {
					continue
				}
				if _, exists := catalog[code]; exists {
					continue
				}
				var lfPtr *int
				if lf.Valid && lf.Int64 >= math.MinInt16 && lf.Int64 <= math.MaxInt16 {
					v := int(lf.Int64)
					lfPtr = &v
				}
				lfName, stratum := LifeformLabel(lfPtr)
				catalog[code] = SpeciesTaxonMeta{
					Species:         code,
					ScientificName:  strings.TrimSpace(sci),
					EnglishName:     strings.TrimSpace(eng),
					Lifeform:        lfPtr,
					LifeformName:    lfName,
					StratumGroup:    stratum,
					SourceCatalogue: "VUser",
				}
			}
			if err := errors.Join(uRows.Err(), uRows.Close()); err != nil {
				return nil, err
			}
		}
	}
	return catalog, nil
}

func loadSpeciesTaxonomyBatchForOwner(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, codes []string) (map[string]SpeciesTaxonMeta, error) {
	if len(codes) == 0 {
		return map[string]SpeciesTaxonMeta{}, nil
	}
	stamp, ok := buildSupportStampKey(owner)
	var cat map[string]SpeciesTaxonMeta
	if !ok {
		var err error
		cat, err = loadFullSpeciesCatalog(ctx, tx)
		if err != nil {
			return nil, err
		}
	} else {
		diagCatalogCacheMu.Lock()
		cat = cachedTaxonMap
		hit := cat != nil && cachedTaxonKey == stamp
		diagCatalogCacheMu.Unlock()

		if !hit {
			loaded, err := loadFullSpeciesCatalog(ctx, tx)
			if err != nil {
				return nil, err
			}
			diagCatalogCacheMu.Lock()
			cachedTaxonKey = stamp
			cachedTaxonMap = loaded
			cat = loaded
			diagCatalogCacheMu.Unlock()
		}
	}

	result := make(map[string]SpeciesTaxonMeta, len(codes))
	for _, c := range codes {
		upper := strings.ToUpper(c)
		if meta, found := cat[upper]; found {
			result[upper] = meta
		} else {
			lfName, stratum := LifeformLabel(nil)
			result[upper] = SpeciesTaxonMeta{
				Species:         upper,
				ScientificName:  upper,
				EnglishName:     "",
				Lifeform:        nil,
				LifeformName:    lfName,
				StratumGroup:    stratum,
				SourceCatalogue: "Unlisted",
			}
		}
	}
	return result, nil
}

func loadUnitLongNamesForOwner(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext) map[string]string {
	stamp, ok := buildSupportStampKey(owner)
	if ok {
		diagCatalogCacheMu.Lock()
		if cachedUnitNamesMap != nil && cachedUnitNamesKey == stamp {
			m := cachedUnitNamesMap
			diagCatalogCacheMu.Unlock()
			return m
		}
		diagCatalogCacheMu.Unlock()
	}

	unitLongNames := map[string]string{}
	for _, src := range []struct{ role, table string }{
		{"VLists", "MasterSiteUnitList"},
		{"VUser", "UserSiteUnitList"},
	} {
		uRows, uErr := tx.QueryContext(ctx,
			`SELECT COALESCE(CAST("SiteSeries" AS TEXT), ''), COALESCE(CAST("SiteSeriesLongName" AS TEXT), '')
			 FROM `+vprocore.QuoteHeaderIdentifier(src.role)+`.`+vprocore.QuoteHeaderIdentifier(src.table))
		if uErr == nil {
			for uRows.Next() {
				var code, lname string
				if err := uRows.Scan(&code, &lname); err == nil && strings.TrimSpace(code) != "" {
					unitLongNames[strings.TrimSpace(code)] = strings.TrimSpace(lname)
				}
			}
			uRows.Close()
		}
	}
	if ok {
		diagCatalogCacheMu.Lock()
		cachedUnitNamesKey = stamp
		cachedUnitNamesMap = unitLongNames
		diagCatalogCacheMu.Unlock()
	}
	return unitLongNames
}
