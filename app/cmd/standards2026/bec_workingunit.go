package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
)

type wuCopy struct {
	Path string `json:"Path"`
	Hash string `json:"Hash"`
}

type wuSchema struct {
	Kind            string   `json:"kind"`
	Table           string   `json:"table"`
	Name            string   `json:"name"`
	Connect         string   `json:"connect"`
	SourceTable     string   `json:"sourceTable"`
	Type            int      `json:"type"`
	Size            int      `json:"size"`
	Required        bool     `json:"required"`
	AllowZeroLength bool     `json:"allowZeroLength"`
	Default         string   `json:"default"`
	Unique          bool     `json:"unique"`
	Primary         bool     `json:"primary"`
	Fields          []string `json:"fields"`
}

type wuRow struct {
	SourceOrdinal            string  `json:"sourceOrdinal"`
	ID                       *string `json:"id"`
	SiteSeries               *string `json:"siteSeries"`
	SiteSeriesLongName       *string `json:"siteSeriesLongName"`
	SiteSeriesScientificName *string `json:"siteSeriesScientificName"`
	Level                    *int    `json:"level"`
}

type wuSnapDoc struct {
	Version                       int                   `json:"version"`
	Exporter                      string                `json:"exporter"`
	ReadOnlyNativeReferenceAccess bool                  `json:"readOnlyNativeReferenceAccess"`
	SourceCopies                  []wuCopy              `json:"sourceCopies"`
	Schema                        map[string][]wuSchema `json:"schema"`
	Tables                        map[string][]wuRow    `json:"tables"`
	IdentityEncoding              string                `json:"identityEncoding"`
	SourceContext                 string                `json:"sourceContext"`
}

type wuProvDoc struct {
	Version          int                   `json:"version"`
	Exporter         string                `json:"exporter"`
	SnapshotSHA256   string                `json:"snapshotSha256"`
	DatabaseSHA256   string                `json:"databaseSha256"`
	MasterSHA256     string                `json:"masterSha256"`
	UserSHA256       string                `json:"userSha256"`
	MasterRows       int                   `json:"masterRows"`
	UserRows         int                   `json:"userRows"`
	MasterDuplicates int                   `json:"masterDuplicates"`
	UserDuplicates   int                   `json:"userDuplicates"`
	TypedCellsSHA256 string                `json:"typedCellsSha256"`
	SourceCopies     []wuCopy              `json:"sourceCopies"`
	SourceSchema     map[string][]wuSchema `json:"sourceSchema"`
	IdentityEncoding string                `json:"identityEncoding"`
	SourceContext    string                `json:"sourceContext"`
}

func writeBECDatabase(dbPath, provPath string, zones []becZoneRow, series []becSeriesRow, prov becProvDoc) (becProvDoc, error) {
	tmpFile, err := os.CreateTemp(filepath.Dir(dbPath), ".bec2026-*.db")
	if err != nil {
		return prov, err
	}
	tmpPath := tmpFile.Name()
	tmpFile.Close()
	defer os.Remove(tmpPath)

	db, err := sql.Open("sqlite3", tmpPath)
	if err != nil {
		return prov, err
	}
	db.SetMaxOpenConns(1)

	schemaSQL := `
CREATE TABLE BECZoneList (RowID TEXT PRIMARY KEY NOT NULL, Zone TEXT, SubZone TEXT, ZoneDescription TEXT, Description TEXT);
CREATE TABLE BECSiteSeries (
 RowID TEXT PRIMARY KEY NOT NULL, SourceID TEXT, SSCode TEXT, Name TEXT, Region TEXT, Zone TEXT, SubZone TEXT,
 BaseSubZone TEXT, Variant TEXT, Phase TEXT, SiteSeries TEXT, SiteSeriesPhase TEXT, Variation TEXT, Seral TEXT,
 Description TEXT, PlantAssociation TEXT, Comments TEXT, ReferenceID REAL, AddedDate TEXT, ExpiredDate TEXT,
 OriginalSourceID TEXT, MergedBGC TEXT, Suballiance TEXT, Alliance TEXT, MissingNpeNa TEXT, TransferID TEXT,
 Flag BOOLEAN CHECK (Flag IS NULL OR Flag IN (0,1)));
CREATE INDEX BECZoneLookup ON BECZoneList(Zone COLLATE NOCASE, SubZone COLLATE NOCASE);
CREATE INDEX BECSiteSeriesLookup ON BECSiteSeries(Zone COLLATE NOCASE, SubZone COLLATE NOCASE);
CREATE TABLE BECProvenance (Version INTEGER NOT NULL, Exporter TEXT NOT NULL, SourceSHA256 TEXT NOT NULL, SnapshotSHA256 TEXT NOT NULL);
`
	tx, err := db.Begin()
	if err != nil {
		db.Close()
		return prov, err
	}
	if _, err := tx.Exec(schemaSQL); err != nil {
		tx.Rollback()
		db.Close()
		return prov, err
	}
	zStmt, err := tx.Prepare(`INSERT INTO BECZoneList VALUES (?,?,?,?,?)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return prov, err
	}
	for _, r := range zones {
		if _, err := zStmt.Exec(r.RowID, r.Zone, r.SubZone, r.ZoneDescription, r.Description); err != nil {
			zStmt.Close()
			tx.Rollback()
			db.Close()
			return prov, err
		}
	}
	zStmt.Close()

	sStmt, err := tx.Prepare(`INSERT INTO BECSiteSeries VALUES (` + strings.TrimSuffix(strings.Repeat("?,", 27), ",") + `)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return prov, err
	}
	for _, r := range series {
		v := reflect.ValueOf(r)
		args := make([]any, 27)
		for i := range args {
			args[i] = v.Field(i).Interface()
		}
		if _, err := sStmt.Exec(args...); err != nil {
			sStmt.Close()
			tx.Rollback()
			db.Close()
			return prov, err
		}
	}
	sStmt.Close()

	if _, err := tx.Exec(`INSERT INTO BECProvenance VALUES (?,?,?,?)`,
		prov.Version, prov.Exporter, prov.SourceSHA256, prov.SnapshotSHA256); err != nil {
		tx.Rollback()
		db.Close()
		return prov, err
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM (SELECT Zone,SubZone,SiteSeries FROM BECSiteSeries GROUP BY Zone,SubZone,SiteSeries HAVING COUNT(*)>1)`).Scan(&prov.DuplicateKeys); err != nil {
		tx.Rollback()
		db.Close()
		return prov, err
	}
	if err := tx.Commit(); err != nil {
		db.Close()
		return prov, err
	}
	if _, err := db.Exec(`VACUUM`); err != nil {
		db.Close()
		return prov, err
	}
	if err := db.Close(); err != nil {
		return prov, err
	}

	rawDB, err := os.ReadFile(tmpPath)
	if err != nil {
		return prov, err
	}
	prov.DatabaseSHA256 = sha256Hex(rawDB)
	if err := os.Chmod(tmpPath, 0644); err != nil {
		return prov, err
	}
	if err := os.Rename(tmpPath, dbPath); err != nil {
		return prov, err
	}

	provBytes, err := json.MarshalIndent(prov, "", "  ")
	if err != nil {
		return prov, err
	}
	provBytes = append(provBytes, '\n')
	if err := atomicWriteFile(provPath, provBytes, 0644); err != nil {
		return prov, err
	}
	return prov, nil
}

func buildAndWriteWorkingUnitv13(becAccdb *accessreader.DB, becAccdbSHA, existingWUPath, existingWUProvPath, outDBPath, outProvPath string) ([]wuRow, wuProvDoc, error) {
	rawProv, err := os.ReadFile(existingWUProvPath)
	if err != nil {
		return nil, wuProvDoc{}, err
	}
	var oldProv wuProvDoc
	dec := json.NewDecoder(bytes.NewReader(rawProv))
	if err := dec.Decode(&oldProv); err != nil {
		return nil, wuProvDoc{}, err
	}

	oldDB, err := sqlutil.OpenReadOnly(existingWUPath)
	if err != nil {
		return nil, wuProvDoc{}, err
	}

	// Load historical master rows (excluding reserved 13000001..13999999 so re-runs are idempotent!)
	mRows, err := oldDB.Query(`SELECT RowID, SourceID, Code, Description, ScientificName, Level
		FROM WorkingUnits WHERE Origin='master' ORDER BY CAST(RowID AS INTEGER)`)
	if err != nil {
		oldDB.Close()
		return nil, wuProvDoc{}, err
	}
	var masterRows []wuRow
	histLabels := map[string]int{} // SU_Label -> index in masterRows
	for mRows.Next() {
		var r wuRow
		if err := mRows.Scan(&r.SourceOrdinal, &r.ID, &r.SiteSeries, &r.SiteSeriesLongName, &r.SiteSeriesScientificName, &r.Level); err != nil {
			mRows.Close()
			oldDB.Close()
			return nil, wuProvDoc{}, err
		}
		if r.ID != nil {
			idVal, _ := strconv.ParseInt(*r.ID, 10, 64)
			if idVal >= 13000001 && idVal <= 13999999 {
				continue
			}
		}
		idx := len(masterRows)
		masterRows = append(masterRows, r)
		if r.SiteSeries != nil {
			if _, seen := histLabels[*r.SiteSeries]; !seen {
				histLabels[*r.SiteSeries] = idx
			}
		}
	}
	mRows.Close()

	uRows, err := oldDB.Query(`SELECT RowID, SourceID, Code, Description, ScientificName, Level
		FROM WorkingUnits WHERE Origin='user' ORDER BY CAST(RowID AS INTEGER)`)
	if err != nil {
		oldDB.Close()
		return nil, wuProvDoc{}, err
	}
	var userRows []wuRow
	for uRows.Next() {
		var r wuRow
		if err := uRows.Scan(&r.SourceOrdinal, &r.ID, &r.SiteSeries, &r.SiteSeriesLongName, &r.SiteSeriesScientificName, &r.Level); err != nil {
			uRows.Close()
			oldDB.Close()
			return nil, wuProvDoc{}, err
		}
		userRows = append(userRows, r)
	}
	uRows.Close()
	if err := oldDB.Close(); err != nil {
		return nil, wuProvDoc{}, err
	}

	_, uniqSU, err := becAccdb.ReadAll("Current_Unique_SiteUnits_v13")
	if err != nil {
		return nil, wuProvDoc{}, err
	}

	type uniqCandidate struct {
		label, noSpace string
		longName, sci  *string
	}
	candidates := make([]uniqCandidate, 0, len(uniqSU))
	for _, r := range uniqSU {
		lbl := strVal(optStr(r[3]))
		ns := strVal(optStr(r[1]))
		if lbl == "" {
			continue
		}
		candidates = append(candidates, uniqCandidate{
			label:    lbl,
			noSpace:  ns,
			longName: truncateUTF16(optStr(r[4]), 120),
			sci:      truncateUTF16(optStr(r[5]), 255),
		})
	}
	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].label != candidates[j].label {
			return candidates[i].label < candidates[j].label
		}
		return candidates[i].noSpace < candidates[j].noSpace
	})

	nextID := int64(13000001)
	seenNewLabels := map[string]bool{}
	lvl11 := 11
	for _, c := range candidates {
		if idx, exists := histLabels[c.label]; exists {
			if c.longName != nil {
				masterRows[idx].SiteSeriesLongName = c.longName
			}
			if c.sci != nil {
				masterRows[idx].SiteSeriesScientificName = c.sci
			}
			continue
		}
		if seenNewLabels[c.label] {
			continue
		}
		seenNewLabels[c.label] = true
		idStr := strconv.FormatInt(nextID, 10)
		nextID++
		lblCopy := c.label
		masterRows = append(masterRows, wuRow{
			ID:                       &idStr,
			SiteSeries:               truncateUTF16(&lblCopy, 50),
			SiteSeriesLongName:       c.longName,
			SiteSeriesScientificName: c.sci,
			Level:                    &lvl11,
		})
	}

	for i := range masterRows {
		masterRows[i].SourceOrdinal = strconv.Itoa(i + 1)
	}
	for i := range userRows {
		userRows[i].SourceOrdinal = strconv.Itoa(i + 1)
	}

	// Build sourceCopies ensuring BECdb_v13_2026.accdb and VUser.accda are recorded with portable basenames
	copies := []wuCopy{
		{Path: "BECdb_v13_2026.accdb", Hash: strings.ToUpper(becAccdbSHA)},
	}
	seenCopy := map[string]bool{"becdb_v13_2026.accdb": true}
	for _, sc := range oldProv.SourceCopies {
		portableName := filepath.Base(strings.ReplaceAll(sc.Path, `\`, `/`))
		base := strings.ToLower(portableName)
		if seenCopy[base] {
			continue
		}
		seenCopy[base] = true
		copies = append(copies, wuCopy{Path: portableName, Hash: sc.Hash})
	}

	tables := map[string][]wuRow{
		"MasterSiteUnitList": masterRows,
		"UserSiteUnitList":   userRows,
	}
	cellsJSON, err := json.Marshal(tables)
	if err != nil {
		return nil, wuProvDoc{}, err
	}

	srcContext := "BECdb_v13_2026.accdb Current_Unique_SiteUnits_v13 merged with historical VLists.MasterSiteUnitList; VUser.UserSiteUnitList preserved"
	snap := wuSnapDoc{
		Version:                       2,
		Exporter:                      "accessreader-becdb-v13-working-unit-v2",
		ReadOnlyNativeReferenceAccess: true,
		SourceCopies:                  copies,
		Schema:                        oldProv.SourceSchema,
		Tables:                        tables,
		IdentityEncoding:              oldProv.IdentityEncoding,
		SourceContext:                 srcContext,
	}
	snapBytes, err := json.Marshal(snap)
	if err != nil {
		return nil, wuProvDoc{}, err
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(outDBPath), ".wu2026-*.db")
	if err != nil {
		return nil, wuProvDoc{}, err
	}
	tmpPath := tmpFile.Name()
	tmpFile.Close()
	defer os.Remove(tmpPath)

	db, err := sql.Open("sqlite3", tmpPath)
	if err != nil {
		return nil, wuProvDoc{}, err
	}
	db.SetMaxOpenConns(1)

	wuSchemaSQL := `
CREATE TABLE WorkingUnits(
 Origin TEXT NOT NULL CHECK(Origin IN ('master','user')),
 RowID TEXT NOT NULL,
 SourceID TEXT,
 Code TEXT,
 Description TEXT,
 ScientificName TEXT,
 Level INTEGER CHECK(Level IS NULL OR Level BETWEEN -32768 AND 32767),
 PRIMARY KEY(Origin,RowID), UNIQUE(Origin,SourceID));
CREATE INDEX WorkingUnitChoices ON WorkingUnits(Origin,Level,Code COLLATE NOCASE);
CREATE TABLE WorkingUnitProvenance(Version INTEGER NOT NULL, Exporter TEXT NOT NULL,
 SnapshotSHA256 TEXT NOT NULL, MasterSHA256 TEXT NOT NULL, UserSHA256 TEXT NOT NULL);
`
	tx, err := db.Begin()
	if err != nil {
		db.Close()
		return nil, wuProvDoc{}, err
	}
	if _, err := tx.Exec(wuSchemaSQL); err != nil {
		tx.Rollback()
		db.Close()
		return nil, wuProvDoc{}, err
	}
	stmt, err := tx.Prepare(`INSERT INTO WorkingUnits VALUES(?,?,?,?,?,?,?)`)
	if err != nil {
		tx.Rollback()
		db.Close()
		return nil, wuProvDoc{}, err
	}
	for _, r := range masterRows {
		if _, err := stmt.Exec("master", r.SourceOrdinal, r.ID, r.SiteSeries, r.SiteSeriesLongName, r.SiteSeriesScientificName, r.Level); err != nil {
			stmt.Close()
			tx.Rollback()
			db.Close()
			return nil, wuProvDoc{}, err
		}
	}
	for _, r := range userRows {
		if _, err := stmt.Exec("user", r.SourceOrdinal, r.ID, r.SiteSeries, r.SiteSeriesLongName, r.SiteSeriesScientificName, r.Level); err != nil {
			stmt.Close()
			tx.Rollback()
			db.Close()
			return nil, wuProvDoc{}, err
		}
	}
	stmt.Close()

	snapSHA := sha256Hex(snapBytes)
	if _, err := tx.Exec(`INSERT INTO WorkingUnitProvenance VALUES(?,?,?,?,?)`,
		2, "accessreader-becdb-v13-working-unit-v2", snapSHA, becAccdbSHA, oldProv.UserSHA256); err != nil {
		tx.Rollback()
		db.Close()
		return nil, wuProvDoc{}, err
	}
	var masterDups, userDups int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM (SELECT Code FROM WorkingUnits WHERE Origin='master' GROUP BY Code HAVING COUNT(*)>1)`).Scan(&masterDups); err != nil {
		tx.Rollback()
		db.Close()
		return nil, wuProvDoc{}, err
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM (SELECT Code FROM WorkingUnits WHERE Origin='user' GROUP BY Code HAVING COUNT(*)>1)`).Scan(&userDups); err != nil {
		tx.Rollback()
		db.Close()
		return nil, wuProvDoc{}, err
	}
	if err := tx.Commit(); err != nil {
		db.Close()
		return nil, wuProvDoc{}, err
	}
	if _, err := db.Exec(`VACUUM`); err != nil {
		db.Close()
		return nil, wuProvDoc{}, err
	}
	if err := db.Close(); err != nil {
		return nil, wuProvDoc{}, err
	}

	rawDB, err := os.ReadFile(tmpPath)
	if err != nil {
		return nil, wuProvDoc{}, err
	}
	newProv := wuProvDoc{
		Version:          2,
		Exporter:         "accessreader-becdb-v13-working-unit-v2",
		SnapshotSHA256:   snapSHA,
		DatabaseSHA256:   sha256Hex(rawDB),
		MasterSHA256:     becAccdbSHA,
		UserSHA256:       oldProv.UserSHA256,
		MasterRows:       len(masterRows),
		UserRows:         len(userRows),
		MasterDuplicates: masterDups,
		UserDuplicates:   userDups,
		TypedCellsSHA256: sha256Hex(cellsJSON),
		SourceCopies:     copies,
		SourceSchema:     oldProv.SourceSchema,
		IdentityEncoding: oldProv.IdentityEncoding,
		SourceContext:    srcContext,
	}
	if err := os.Chmod(tmpPath, 0644); err != nil {
		return nil, wuProvDoc{}, err
	}
	if err := os.Rename(tmpPath, outDBPath); err != nil {
		return nil, wuProvDoc{}, err
	}
	provBytes, err := json.MarshalIndent(newProv, "", "  ")
	if err != nil {
		return nil, wuProvDoc{}, err
	}
	provBytes = append(provBytes, '\n')
	if err := atomicWriteFile(outProvPath, provBytes, 0644); err != nil {
		return nil, wuProvDoc{}, err
	}
	return masterRows, newProv, nil
}
