package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type listUpsert struct {
	ListName      string
	ListFilter    *string
	ItemOrder     float64
	Item          string
	Description   string
	FieldUsedIn   *string
	ValidateLoops *string
	Validate      int64
	Note          *string
	Flag          int64
}

func lmh25ListAdditions() []listUpsert {
	sDist := "SiteDisturbance"
	exp := "Exposure"
	floodDur := "FloodingRegimeDur"
	floodFreq := "FloodingRegimeFreq"
	loops3 := "3"
	loops2 := "2"
	return []listUpsert{
		// StructuralStage 3c & 3d (verify/ensure present)
		{ListName: "StructuralStage", ItemOrder: 14.0, Item: "3c", Description: "Short stunted trees", FieldUsedIn: strPtrLocal("StructuralStage"), Validate: 1, Flag: 0},
		{ListName: "StructuralStage", ItemOrder: 15.0, Item: "3d", Description: "Tall stunted trees", FieldUsedIn: strPtrLocal("StructuralStage"), Validate: 1, Flag: 0},
		// SiviStructuralStage 3c & 3d
		{ListName: "SiviStructuralStage", ItemOrder: 8.1, Item: "3c", Description: "3c", Validate: 0, Flag: 0},
		{ListName: "SiviStructuralStage", ItemOrder: 8.2, Item: "3d", Description: "3d", Validate: 0, Flag: 0},
		// StructuralStageMod v & k
		{ListName: "StructuralStageMod", ItemOrder: 7.0, Item: "v", Description: "veteran canopy", Validate: 0, Flag: 0},
		{ListName: "StructuralStageMod", ItemOrder: 8.0, Item: "k", Description: "krummholz", Validate: 0, Flag: 0},
		// SiteDisturbance A.w.th & A.w.br
		{ListName: "SiteDisturbance", ItemOrder: 12.1, Item: "A.w.th", Description: "Windthrow (uprooting)", FieldUsedIn: &sDist, ValidateLoops: &loops3, Validate: 1, Flag: 0},
		{ListName: "SiteDisturbance", ItemOrder: 12.2, Item: "A.w.br", Description: "Windbreak (stem snap)", FieldUsedIn: &sDist, ValidateLoops: &loops3, Validate: 1, Flag: 0},
		// Exposure CO
		{ListName: "Exposure", ItemOrder: 3.5, Item: "CO", Description: "Cold aspect", FieldUsedIn: &exp, ValidateLoops: &loops2, Validate: 0, Flag: 0},
		// FloodingRegimeDur S & FloodingRegimeFreq S
		{ListName: "FloodingRegimeDur", ItemOrder: 7.0, Item: "S", Description: "Semi-permanent / Merely subirrigated during flood events", FieldUsedIn: &floodDur, Validate: 1, Flag: 0},
		{ListName: "FloodingRegimeFreq", ItemOrder: 5.5, Item: "S", Description: "Subirrigated / Seasonal seepage", FieldUsedIn: &floodFreq, Validate: 1, Flag: 0},
	}
}

func strPtrLocal(s string) *string { return &s }

func upgradeVListsFamilyAndReadModel(
	vlistsFamilyPath, vlistsReadModelPath string,
	specs []specsRow,
	zones []becZoneRow,
	series []becSeriesRow,
	masterUnits []wuRow,
) (string, string, int, int, error) {
	// Work on a deterministic clean copy of VLists.db
	srcBytes, err := os.ReadFile(vlistsFamilyPath)
	if err != nil {
		return "", "", 0, 0, err
	}
	tmpFamily, err := os.CreateTemp(filepath.Dir(vlistsFamilyPath), ".vlists-family-2026-*.db")
	if err != nil {
		return "", "", 0, 0, err
	}
	tmpFamilyPath := tmpFamily.Name()
	if _, err := tmpFamily.Write(srcBytes); err != nil {
		tmpFamily.Close()
		os.Remove(tmpFamilyPath)
		return "", "", 0, 0, err
	}
	tmpFamily.Close()
	defer os.Remove(tmpFamilyPath)

	db, err := sql.Open("sqlite3", tmpFamilyPath)
	if err != nil {
		return "", "", 0, 0, err
	}
	db.SetMaxOpenConns(1)

	tx, err := db.Begin()
	if err != nil {
		db.Close()
		return "", "", 0, 0, err
	}

	// 1. Replace USysAllSpecs (preserving exact 26-column schema & INTEGER Lifeform)
	if _, err := tx.Exec(`DELETE FROM "USysAllSpecs"`); err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	spStmt, err := tx.Prepare(`INSERT INTO "USysAllSpecs" VALUES (` + strings.TrimSuffix(strings.Repeat("?,", 26), ",") + `)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	for _, r := range specs {
		if _, err := spStmt.Exec(
			r.YearOfChange, r.ChangeDescription, r.APCFamily, r.FamilyCode, r.OldCode, r.Code, r.SplCode, r.TreeCode,
			r.ScientificName, r.Lifeform, r.Authority, r.EnglishNameOld, r.EnglishName, r.CommonNamePB,
			r.NotesOnNames, r.ShortenedGuideName, r.Native, r.Codetype, r.Province, r.ID, r.TaxonLevel,
			r.IsAttribute, r.Report, r.SplCodeCalc, r.Codelength, r.CombinedEnglishName,
		); err != nil {
			spStmt.Close()
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
	}
	spStmt.Close()

	// 2. Replace USysZoneList
	if _, err := tx.Exec(`DELETE FROM "USysZoneList"`); err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	zStmt, err := tx.Prepare(`INSERT INTO "USysZoneList" ("Zone","SubZone","ZoneDescription","SubZoneVarDescription") VALUES (?,?,?,?)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	for _, z := range zones {
		if _, err := zStmt.Exec(z.Zone, z.SubZone, z.ZoneDescription, z.Description); err != nil {
			zStmt.Close()
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
	}
	zStmt.Close()

	// 3. Replace USysSiteSeriesNames
	if _, err := tx.Exec(`DELETE FROM "USysSiteSeriesNames"`); err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	ssStmt, err := tx.Prepare(`INSERT INTO "USysSiteSeriesNames" VALUES (` + strings.TrimSuffix(strings.Repeat("?,", 26), ",") + `)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	for _, s := range series {
		var ssID, oSSID any
		if s.SourceID != nil {
			if f, err := strconv.ParseFloat(*s.SourceID, 64); err == nil {
				ssID = f
			}
		}
		if s.OriginalSourceID != nil {
			if f, err := strconv.ParseFloat(*s.OriginalSourceID, 64); err == nil {
				oSSID = f
			}
		}
		var added any
		if s.AddedDate != nil {
			added = strings.TrimSuffix(*s.AddedDate, "T00:00:00")
		}
		var flagVal any
		if s.Flag != nil {
			if *s.Flag {
				flagVal = 1
			} else {
				flagVal = 0
			}
		}
		if _, err := ssStmt.Exec(
			ssID, s.SSCode, s.Name, s.Region, s.Zone, s.SubZone, s.BaseSubZone, s.Variant,
			s.Phase, s.SiteSeries, s.SiteSeriesPhase, s.Variation, s.Seral, s.Description,
			s.PlantAssociation, s.Comments, s.ReferenceID, added, s.ExpiredDate, oSSID,
			s.MergedBGC, s.Suballiance, s.Alliance, s.MissingNpeNa, s.TransferID, flagVal,
		); err != nil {
			ssStmt.Close()
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
	}
	ssStmt.Close()

	// 4. Replace MasterSiteUnitList
	if _, err := tx.Exec(`DELETE FROM "MasterSiteUnitList"`); err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	msuStmt, err := tx.Prepare(`INSERT INTO "MasterSiteUnitList" ("ID","SiteSeries","SiteSeriesLongName","SiteSeriesScientificName","Level") VALUES (?,?,?,?,?)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}
	for _, m := range masterUnits {
		idInt, err := strconv.ParseInt(strVal(m.ID), 10, 64)
		if err != nil {
			msuStmt.Close()
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
		if _, err := msuStmt.Exec(idInt, m.SiteSeries, m.SiteSeriesLongName, m.SiteSeriesScientificName, m.Level); err != nil {
			msuStmt.Close()
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
	}
	msuStmt.Close()

	// 5. Upsert LMH25 (2023) vocabulary extensions in USysTableOfLists without changing existing row count on StructuralStage (21)!
	for _, up := range lmh25ListAdditions() {
		var exists int
		if err := tx.QueryRow(`SELECT COUNT(*) FROM "USysTableOfLists" WHERE ListName=? AND Item=?`, up.ListName, up.Item).Scan(&exists); err != nil {
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
		if exists > 0 {
			if up.ListName == "FloodingRegimeDur" && up.Item == "S" {
				if _, err := tx.Exec(`UPDATE "USysTableOfLists" SET ItemDescription=? WHERE ListName=? AND Item=?`,
					up.Description, up.ListName, up.Item); err != nil {
					tx.Rollback()
					db.Close()
					return "", "", 0, 0, err
				}
			}
			continue
		}
		if _, err := tx.Exec(`INSERT INTO "USysTableOfLists"
			("ListName","ListFilter","ItemOrder","Item","ItemDescription","FieldUsedIn","ValidateLoops","Validate","Note","Flag")
			VALUES (?,?,?,?,?,?,?,?,?,?)`,
			up.ListName, up.ListFilter, up.ItemOrder, up.Item, up.Description,
			up.FieldUsedIn, up.ValidateLoops, up.Validate, up.Note, up.Flag); err != nil {
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
	}

	// 6. Stamp _table_metadata in VLists.db
	metaStamps := [][2]string{
		{"MasterSiteUnitList", "BECdb_v13_2026 (2026-05-28)"},
		{"USysSiteSeriesNames", "BECdb_v13_2026 (2026-05-28)"},
		{"USysZoneList", "BECdb_v13_2026 (2026-05-28)"},
		{"USysAllSpecs", "BCPlantTaxa_v19_2025 (2026-02-09)"},
		{"USysTableOfLists", "LMH25_2023 + BECdb_v13_2026"},
	}
	for _, st := range metaStamps {
		res, err := tx.Exec(`UPDATE "_table_metadata" SET "description"=? WHERE "table_name"=?`, st[1], st[0])
		if err != nil {
			tx.Rollback()
			db.Close()
			return "", "", 0, 0, err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			if _, err := tx.Exec(`INSERT INTO "_table_metadata" ("table_name","description") VALUES (?,?)`, st[0], st[1]); err != nil {
				tx.Rollback()
				db.Close()
				return "", "", 0, 0, err
			}
		}
	}

	var listTotal int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM "USysTableOfLists"`).Scan(&listTotal); err != nil {
		tx.Rollback()
		db.Close()
		return "", "", 0, 0, err
	}

	if err := tx.Commit(); err != nil {
		db.Close()
		return "", "", 0, 0, err
	}
	freshFamily, err := os.CreateTemp(filepath.Dir(vlistsFamilyPath), ".vlists-family-clean-*.db")
	if err != nil {
		db.Close()
		return "", "", 0, 0, err
	}
	freshFamilyPath := freshFamily.Name()
	freshFamily.Close()
	defer os.Remove(freshFamilyPath)
	if err := cloneSQLiteDeterministic(db, freshFamilyPath); err != nil {
		db.Close()
		return "", "", 0, 0, err
	}

	// Build resources/vlists.db read-model deterministically from upgraded VLists.db
	tmpRead, err := os.CreateTemp(filepath.Dir(vlistsReadModelPath), ".vlists-read-2026-*.db")
	if err != nil {
		db.Close()
		return "", "", 0, 0, err
	}
	tmpReadPath := tmpRead.Name()
	tmpRead.Close()
	defer os.Remove(tmpReadPath)

	rmDB, err := sql.Open("sqlite3", tmpReadPath)
	if err != nil {
		db.Close()
		return "", "", 0, 0, err
	}
	rmDB.SetMaxOpenConns(1)
	rmTx, err := rmDB.Begin()
	if err != nil {
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	if _, err := rmTx.Exec(`
CREATE TABLE Species (
    Code TEXT PRIMARY KEY,
    ScientificName TEXT,
    EnglishName TEXT,
    Lifeform INTEGER,
    FamilyCode TEXT,
    Authority TEXT,
    Native TEXT,
    Codetype TEXT
);
CREATE TABLE Lists (
    ListName TEXT,
    Item TEXT,
    ItemDescription TEXT,
    ItemOrder REAL,
    FieldUsedIn TEXT,
    PRIMARY KEY (ListName, Item)
);
CREATE INDEX idx_species_name ON Species(ScientificName);
CREATE INDEX idx_species_eng ON Species(EnglishName);
CREATE INDEX idx_lists_name ON Lists(ListName);
`); err != nil {
		rmTx.Rollback()
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}

	// Populate Species (distinct non-synonym codes, preferring U > D/I > X/XX, non-null strings for ReferenceService.Scan)
	speciesRank := func(ct string) int {
		switch strings.ToUpper(ct) {
		case "U":
			return 0
		case "D", "I":
			return 1
		case "X":
			return 2
		case "XX":
			return 3
		default:
			return 4
		}
	}
	bestByCode := map[string]specsRow{}
	for _, r := range specs {
		c := strings.TrimSpace(strVal(r.Code))
		if c == "" || strings.EqualFold(strVal(r.Codetype), "S") {
			continue
		}
		cu := strings.ToUpper(c)
		if prev, exists := bestByCode[cu]; !exists || speciesRank(strVal(r.Codetype)) < speciesRank(strVal(prev.Codetype)) {
			bestByCode[cu] = r
		}
	}
	spCodes := make([]string, 0, len(bestByCode))
	for cu := range bestByCode {
		spCodes = append(spCodes, cu)
	}
	sort.Strings(spCodes)

	rmSpStmt, err := rmTx.Prepare(`INSERT INTO Species VALUES (?,?,?,?,?,?,?,?)`)
	if err != nil {
		rmTx.Rollback()
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	for _, cu := range spCodes {
		r := bestByCode[cu]
		if _, err := rmSpStmt.Exec(
			cu,
			strVal(r.ScientificName),
			strVal(r.EnglishName),
			r.Lifeform,
			strVal(r.FamilyCode),
			strVal(r.Authority),
			strVal(r.Native),
			strVal(r.Codetype),
		); err != nil {
			rmSpStmt.Close()
			rmTx.Rollback()
			rmDB.Close()
			db.Close()
			return "", "", 0, 0, err
		}
	}
	rmSpStmt.Close()

	// Populate Lists from VLists.USysTableOfLists (non-null ListName and non-null, non-empty Item)
	lRows, err := db.Query(`SELECT ListName, Item, COALESCE(ItemDescription,''), ItemOrder, COALESCE(FieldUsedIn,'')
		FROM "USysTableOfLists"
		WHERE ListName IS NOT NULL AND ListName <> '' AND Item IS NOT NULL AND Item <> ''
		ORDER BY ListName COLLATE BINARY, ItemOrder, rowid`)
	if err != nil {
		rmTx.Rollback()
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	rmLStmt, err := rmTx.Prepare(`INSERT OR IGNORE INTO Lists VALUES (?,?,?,?,?)`)
	if err != nil {
		lRows.Close()
		rmTx.Rollback()
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	rmListCount := 0
	for lRows.Next() {
		var ln, it, desc, fui string
		var ord sql.NullFloat64
		if err := lRows.Scan(&ln, &it, &desc, &ord, &fui); err != nil {
			lRows.Close()
			rmLStmt.Close()
			rmTx.Rollback()
			rmDB.Close()
			db.Close()
			return "", "", 0, 0, err
		}
		var ordAny any
		if ord.Valid {
			ordAny = ord.Float64
		}
		res, err := rmLStmt.Exec(ln, it, desc, ordAny, fui)
		if err != nil {
			lRows.Close()
			rmLStmt.Close()
			rmTx.Rollback()
			rmDB.Close()
			db.Close()
			return "", "", 0, 0, err
		}
		if n, _ := res.RowsAffected(); n > 0 {
			rmListCount++
		}
	}
	lRows.Close()
	rmLStmt.Close()

	if err := rmTx.Commit(); err != nil {
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	if _, err := rmDB.Exec(`VACUUM`); err != nil {
		rmDB.Close()
		db.Close()
		return "", "", 0, 0, err
	}
	if err := rmDB.Close(); err != nil {
		db.Close()
		return "", "", 0, 0, err
	}
	if err := db.Close(); err != nil {
		return "", "", 0, 0, err
	}

	familyBytes, err := os.ReadFile(freshFamilyPath)
	if err != nil {
		return "", "", 0, 0, err
	}
	readBytes, err := os.ReadFile(tmpReadPath)
	if err != nil {
		return "", "", 0, 0, err
	}
	familySHA := sha256Hex(familyBytes)
	readSHA := sha256Hex(readBytes)

	if err := os.Chmod(freshFamilyPath, 0644); err != nil {
		return "", "", 0, 0, err
	}
	if err := os.Rename(freshFamilyPath, vlistsFamilyPath); err != nil {
		return "", "", 0, 0, err
	}
	if err := os.Chmod(tmpReadPath, 0644); err != nil {
		return "", "", 0, 0, err
	}
	if err := os.Rename(tmpReadPath, vlistsReadModelPath); err != nil {
		return "", "", 0, 0, err
	}
	_ = rmListCount
	return familySHA, readSHA, listTotal, len(spCodes), nil
}

func cloneSQLiteDeterministic(srcDB *sql.DB, dstPath string) error {
	type ddlObj struct {
		kind, name, sql string
	}
	rows, err := srcDB.Query(`SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name COLLATE BINARY`)
	if err != nil {
		return err
	}
	var objs []ddlObj
	for rows.Next() {
		var o ddlObj
		if err := rows.Scan(&o.kind, &o.name, &o.sql); err != nil {
			rows.Close()
			return err
		}
		objs = append(objs, o)
	}
	rows.Close()

	dstDB, err := sql.Open("sqlite3", dstPath)
	if err != nil {
		return err
	}
	defer dstDB.Close()
	dstDB.SetMaxOpenConns(1)

	tx, err := dstDB.Begin()
	if err != nil {
		return err
	}
	for _, o := range objs {
		if o.kind == "table" {
			if _, err := tx.Exec(o.sql); err != nil {
				tx.Rollback()
				return err
			}
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	// Copy rows preserving rowid when no explicit integer PK aliases rowid, or full columns
	for _, o := range objs {
		if o.kind != "table" {
			continue
		}
		qName := `"` + strings.ReplaceAll(o.name, `"`, `""`) + `"`
		// Check if table has INTEGER PRIMARY KEY (which already aliases rowid)
		hasIPK := strings.Contains(strings.ToUpper(o.sql), "INTEGER PRIMARY KEY")
		var selectSQL, insertSQL string
		cRows, err := srcDB.Query(`PRAGMA table_info(` + qName + `)`)
		if err != nil {
			return err
		}
		var cols []string
		for cRows.Next() {
			var cid, notnull, pk int
			var cname, ctype string
			var dflt any
			if err := cRows.Scan(&cid, &cname, &ctype, &notnull, &dflt, &pk); err != nil {
				cRows.Close()
				return err
			}
			cols = append(cols, `"`+strings.ReplaceAll(cname, `"`, `""`)+`"`)
		}
		cRows.Close()

		colList := strings.Join(cols, ",")
		placeholders := strings.TrimSuffix(strings.Repeat("?,", len(cols)), ",")
		if hasIPK {
			selectSQL = `SELECT ` + colList + ` FROM ` + qName + ` ORDER BY rowid`
			insertSQL = `INSERT INTO ` + qName + ` (` + colList + `) VALUES (` + placeholders + `)`
		} else {
			selectSQL = `SELECT rowid,` + colList + ` FROM ` + qName + ` ORDER BY rowid`
			insertSQL = `INSERT INTO ` + qName + ` (rowid,` + colList + `) VALUES (?,` + placeholders + `)`
		}

		dataRows, err := srcDB.Query(selectSQL)
		if err != nil {
			return err
		}
		dTx, err := dstDB.Begin()
		if err != nil {
			dataRows.Close()
			return err
		}
		stmt, err := dTx.Prepare(insertSQL)
		if err != nil {
			dataRows.Close()
			dTx.Rollback()
			return err
		}
		nCols := len(cols)
		if !hasIPK {
			nCols++
		}
		for dataRows.Next() {
			vals := make([]any, nCols)
			ptrs := make([]any, nCols)
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if err := dataRows.Scan(ptrs...); err != nil {
				stmt.Close()
				dataRows.Close()
				dTx.Rollback()
				return err
			}
			if _, err := stmt.Exec(vals...); err != nil {
				stmt.Close()
				dataRows.Close()
				dTx.Rollback()
				return err
			}
		}
		dataRows.Close()
		stmt.Close()
		if err := dTx.Commit(); err != nil {
			return err
		}
	}

	idxTx, err := dstDB.Begin()
	if err != nil {
		return err
	}
	for _, o := range objs {
		if o.kind != "table" {
			if _, err := idxTx.Exec(o.sql); err != nil {
				idxTx.Rollback()
				return err
			}
		}
	}
	if err := idxTx.Commit(); err != nil {
		return err
	}
	_, err = dstDB.Exec(`VACUUM`)
	return err
}

func atomicWriteFile(dest string, data []byte, perm os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(dest), ".std2026-*.tmp")
	if err != nil {
		return fmt.Errorf("create temp for %s: %w", dest, err)
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if err := f.Chmod(perm); err != nil {
		f.Close()
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, dest)
}
