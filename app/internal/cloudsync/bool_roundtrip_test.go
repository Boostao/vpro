package cloudsync

import (
	"database/sql"
	"fmt"
	"math"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	_ "github.com/mattn/go-sqlite3"
)

// UX-CLOUD-001 & ENG-R-003: Verify SQLite BOOLEAN-declared columns (-1, 0, 1, NULL, integer strings,
// true/false literals, and invalid boolean literals) scan via sqliteSelectColumnsCSV + mattn/go-sqlite3
// without flipping Access true (-1) to bool(false)/0, and round-trip back to SQLite VP08 as -1 / 0 / NULL.
func TestSQLiteBooleanSelectAndPGRoundTrip(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "bool_probe.db")
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	cols := []ColumnSpec{
		tCol("PlotNumber", "VARCHAR", 7),
		bCol("Flag"),
		bCol("SpeciesListComplete"),
		bCol("UpdatedFromCards"),
		bCol("Restore"),
		iCol("Validate", "BOOLEAN"),
	}

	if _, err := db.Exec(`
		CREATE TABLE "T_Bool" (
			"PlotNumber" TEXT,
			"Flag" BOOLEAN,
			"SpeciesListComplete" BOOLEAN,
			"UpdatedFromCards" BOOLEAN,
			"Restore" BOOLEAN,
			"Validate" BOOLEAN
		);
		INSERT INTO "T_Bool" VALUES
			('P_NEG1', -1, -1, -1, -1, -1),
			('P_ZERO',  0,  0,  0,  0,  0),
			('P_POS1',  1,  1,  1,  1,  1),
			('P_INT2',  2, -5,  7, -9,  1),
			('P_NULL', NULL, NULL, NULL, NULL, NULL),
			('P_TXT1', 'true', 'TRUE', '-1', '1', '1'),
			('P_TXT0', 'false', 'FALSE', '0', ' ', '');
	`); err != nil {
		t.Fatal(err)
	}

	query := fmt.Sprintf(`SELECT %s FROM "T_Bool" ORDER BY rowid`, sqliteSelectColumnsCSV(cols))
	rows, err := db.Query(query)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()

	type expectedRow struct {
		plot string
		b1   any
		b2   any
		b3   any
		b4   any
		val  any
	}
	want := []expectedRow{
		{"P_NEG1", int16(-1), int16(-1), int16(-1), int16(-1), int64(-1)},
		{"P_ZERO", int16(0), int16(0), int16(0), int16(0), int64(0)},
		{"P_POS1", int16(-1), int16(-1), int16(-1), int16(-1), int64(1)},
		{"P_INT2", int16(-1), int16(-1), int16(-1), int16(-1), int64(1)},
		{"P_NULL", nil, nil, nil, nil, nil},
		{"P_TXT1", int16(-1), int16(-1), int16(-1), int16(-1), int64(1)},
		{"P_TXT0", int16(0), int16(0), int16(0), nil, nil},
	}

	var pgRows [][]any
	idx := 0
	for rows.Next() {
		rawVals := make([]any, len(cols))
		scanDest := make([]any, len(cols))
		for i := range rawVals {
			scanDest[i] = &rawVals[i]
		}
		if err := rows.Scan(scanDest...); err != nil {
			t.Fatal(err)
		}
		canon := make([]any, len(cols))
		for i, col := range cols {
			v, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
			if cErr != nil {
				t.Fatalf("row %d col %s canonicalize error: %v", idx, col.Name, cErr)
			}
			canon[i] = v
		}
		exp := want[idx]
		if canon[0] != exp.plot || canon[1] != exp.b1 || canon[2] != exp.b2 || canon[3] != exp.b3 || canon[4] != exp.b4 || canon[5] != exp.val {
			t.Fatalf("row %d (%s) mismatch: got %#v, want %+v", idx, exp.plot, canon, exp)
		}
		pgRows = append(pgRows, canon)
		idx++
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if idx != len(want) {
		t.Fatalf("expected %d rows, got %d", len(want), idx)
	}

	// Write canonical PG values back into a SQLite VP08 BOOLEAN-declared table via CanonicalizePGToSQLite
	if _, err := db.Exec(`
		CREATE TABLE "T_RoundTrip" (
			"PlotNumber" TEXT,
			"Flag" BOOLEAN,
			"SpeciesListComplete" BOOLEAN,
			"UpdatedFromCards" BOOLEAN,
			"Restore" BOOLEAN,
			"Validate" BOOLEAN
		)
	`); err != nil {
		t.Fatal(err)
	}
	for _, pgRow := range pgRows {
		sqArgs := make([]any, len(cols))
		for i, col := range cols {
			sqArgs[i] = CanonicalizePGToSQLite(col, pgRow[i])
		}
		if _, err := db.Exec(`INSERT INTO "T_RoundTrip" VALUES (?, ?, ?, ?, ?, ?)`, sqArgs...); err != nil {
			t.Fatal(err)
		}
	}

	// Verify physical SQLite integer storage is strictly -1 / 0 / NULL
	checkRows, err := db.Query(`
		SELECT CAST("PlotNumber" AS TEXT), typeof("Flag"), CAST("Flag" AS INTEGER),
		       typeof("UpdatedFromCards"), CAST("UpdatedFromCards" AS INTEGER),
		       typeof("Restore"), CAST("Restore" AS INTEGER)
		FROM "T_RoundTrip" ORDER BY rowid
	`)
	if err != nil {
		t.Fatal(err)
	}
	defer checkRows.Close()

	type wantSQLite struct {
		plot  string
		fType string
		fVal  sql.NullInt64
		rType string
		rVal  sql.NullInt64
	}
	wantSQ := []wantSQLite{
		{"P_NEG1", "integer", sql.NullInt64{Int64: -1, Valid: true}, "integer", sql.NullInt64{Int64: -1, Valid: true}},
		{"P_ZERO", "integer", sql.NullInt64{Int64: 0, Valid: true}, "integer", sql.NullInt64{Int64: 0, Valid: true}},
		{"P_POS1", "integer", sql.NullInt64{Int64: -1, Valid: true}, "integer", sql.NullInt64{Int64: -1, Valid: true}},
		{"P_INT2", "integer", sql.NullInt64{Int64: -1, Valid: true}, "integer", sql.NullInt64{Int64: -1, Valid: true}},
		{"P_NULL", "null", sql.NullInt64{}, "null", sql.NullInt64{}},
		{"P_TXT1", "integer", sql.NullInt64{Int64: -1, Valid: true}, "integer", sql.NullInt64{Int64: -1, Valid: true}},
		{"P_TXT0", "integer", sql.NullInt64{Int64: 0, Valid: true}, "null", sql.NullInt64{}},
	}
	sqIdx := 0
	for checkRows.Next() {
		var plot, fType, uType, rType string
		var fVal, uVal, rVal sql.NullInt64
		if err := checkRows.Scan(&plot, &fType, &fVal, &uType, &uVal, &rType, &rVal); err != nil {
			t.Fatal(err)
		}
		w := wantSQ[sqIdx]
		if plot != w.plot || fType != w.fType || fVal != w.fVal || uType != w.fType || uVal != w.fVal || rType != w.rType || rVal != w.rVal {
			t.Fatalf("roundtrip row %d (%s) mismatch: got flag=(%s,%v) upd=(%s,%v) restore=(%s,%v), want %+v",
				sqIdx, plot, fType, fVal, uType, uVal, rType, rVal, w)
		}
		sqIdx++
	}
}

func TestParseBoolBytesAndInvalidLiteralsParity(t *testing.T) {
	col := bCol("Flag")
	validCases := []struct {
		in   string
		want any
	}{
		{"-1", int16(-1)},
		{"1", int16(-1)},
		{"2", int16(-1)},
		{"-5", int16(-1)},
		{"0", int16(0)},
		{"+0", int16(0)},
		{"-0", int16(0)},
		{"true", int16(-1)},
		{"TRUE", int16(-1)},
		{"false", int16(0)},
		{"FALSE", int16(0)},
		{"", nil},
		{"   ", nil},
	}
	for _, tc := range validCases {
		got, err := CanonicalizeSQLiteToPG(col, tc.in)
		if err != nil {
			t.Fatalf("CanonicalizeSQLiteToPG(%q) unexpected error: %v", tc.in, err)
		}
		if got != tc.want {
			t.Fatalf("CanonicalizeSQLiteToPG(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}

	invalidLiterals := []string{"yes", "no", "t", "f", "y", "n", "1.0", "0.0", "on", "off", "99999999999999999999"}
	for _, bad := range invalidLiterals {
		if got, err := CanonicalizeSQLiteToPG(col, bad); err == nil {
			t.Fatalf("CanonicalizeSQLiteToPG(%q) expected error, got %v", bad, got)
		}
	}
	if _, err := CanonicalizeSQLiteToPG(col, math.NaN()); err == nil {
		t.Fatal("expected NaN float64 boolean to return error")
	}
	if _, err := CanonicalizeSQLiteToPG(col, math.Inf(1)); err == nil {
		t.Fatal("expected +Inf float64 boolean to return error")
	}
}

func TestLoadSQLiteBaseSubsetSnapshotPreservesMinusOneBooleansAndLumpUse(t *testing.T) {
	svc, state, projPath := cleanComplianceProjectFixture(t)
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rw"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	stmts := []string{
		`UPDATE "Sample_Env" SET "Flag" = -1, "SpeciesListComplete" = -1, "SV_FloodPlain" = 0 WHERE "PlotNumber" = '00337'`,
		`UPDATE "Sample_Admin" SET "UpdatedFromCards" = -1 WHERE "Plot" = '00337'`,
		`INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover1", "Flag", "ID") VALUES ('00337', 'TSUGHET', 25.0, -1, 10)`,
		`UPDATE "Sample_Humus" SET "Flag" = -1 WHERE "PlotNumber" = '00337' AND "ID" = 1`,
		`CREATE TABLE IF NOT EXISTS "Sample_Lump" ("LumpCode" TEXT, "SppCode" TEXT, "Use" BOOLEAN)`,
		`DELETE FROM "Sample_Lump"`,
		`INSERT INTO "Sample_Lump" ("LumpCode", "SppCode", "Use") VALUES
			('ABIELAS', 'ABIE1', -1),
			('ABIELAS', 'ABIE2', 0),
			('ABIELAS', 'ABIE3', 'true'),
			('ABIELAS', 'ABIE4', NULL)`,
	}
	for _, q := range stmts {
		if _, err := db.Exec(q); err != nil {
			t.Fatalf("setup SQL (%s): %v", q, err)
		}
	}

	snap, proj, err := loadSQLiteBaseSubsetSnapshot(t.Context(), projPath, "Sample", []string{"00337"})
	if err != nil {
		t.Fatalf("loadSQLiteBaseSubsetSnapshot error: %v", err)
	}
	if proj != "Sample" {
		t.Fatalf("expected Sample project, got %q", proj)
	}

	envCells := snap.rawCells["Env"]["00337\x00Env"]
	if envCells["Flag"].kind != "int" || envCells["Flag"].intVal != -1 {
		t.Fatalf("expected Env.Flag = -1 in snapshot, got %+v", envCells["Flag"])
	}
	if envCells["SpeciesListComplete"].kind != "int" || envCells["SpeciesListComplete"].intVal != -1 {
		t.Fatalf("expected Env.SpeciesListComplete = -1 in snapshot, got %+v", envCells["SpeciesListComplete"])
	}
	if envCells["SV_FloodPlain"].kind != "int" || envCells["SV_FloodPlain"].intVal != 0 {
		t.Fatalf("expected Env.SV_FloodPlain = 0 in snapshot, got %+v", envCells["SV_FloodPlain"])
	}

	admCells := snap.rawCells["Admin"]["00337\x00Admin"]
	if admCells["UpdatedFromCards"].kind != "int" || admCells["UpdatedFromCards"].intVal != -1 {
		t.Fatalf("expected Admin.UpdatedFromCards = -1 in snapshot, got %+v", admCells["UpdatedFromCards"])
	}

	vegCells := snap.rawCells["Veg"]["00337\x00Species=TSUGHET"]
	if vegCells["Flag"].kind != "int" || vegCells["Flag"].intVal != -1 {
		t.Fatalf("expected Veg.Flag = -1 in snapshot, got %+v", vegCells["Flag"])
	}

	humusCells := snap.rawCells["Humus"]["00337\x00Horizon=Lv"]
	if humusCells["Flag"].kind != "int" || humusCells["Flag"].intVal != -1 {
		t.Fatalf("expected Humus.Flag = -1 in snapshot, got %+v", humusCells["Flag"])
	}

	// Verify PG int16(-1) produces the exact same cloudCell and comparableString ("-1") with zero spurious diff
	pgCell := pgValueToCloudCell(bCol("Flag"), int16(-1))
	if pgCell != envCells["Flag"] || !sameNullableStr(pgCell.comparableString(), snap.cells["Env"]["00337\x00Env"]["Flag"]) {
		t.Fatalf("SQLite -1 snapshot cell %+v diverged from PG int16(-1) cell %+v", envCells["Flag"], pgCell)
	}

	// Verify contributor_staging <Project>_Lump extraction handles -1, 0, 'true', and NULL
	_, _, _, _, _, _, _, _, _, _, lumpRows, _, err := extractActiveProjectSubmissionArtifacts(t.Context(), svc, state.ContextID, false)
	if err != nil {
		t.Fatalf("extractActiveProjectSubmissionArtifacts error: %v", err)
	}
	if len(lumpRows) != 4 {
		t.Fatalf("expected 4 lump rows, got %d", len(lumpRows))
	}
	wantUse := map[string]bool{
		"ABIE1": true,
		"ABIE2": false,
		"ABIE3": true,
		"ABIE4": false,
	}
	for _, lr := range lumpRows {
		if lr.Use != wantUse[lr.SppCode] {
			t.Fatalf("Lump SppCode %s Use = %v, want %v", lr.SppCode, lr.Use, wantUse[lr.SppCode])
		}
	}
}
