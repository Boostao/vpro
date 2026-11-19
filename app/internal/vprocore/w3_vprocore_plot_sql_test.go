package vprocore_test

import (
	"context"
	"database/sql"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func rebuildSampleProjectTablesWithCollateNocase(t *testing.T, projectPath string) {
	t.Helper()
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projectPath, "rw"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	if _, err := db.Exec(`PRAGMA foreign_keys = OFF; PRAGMA legacy_alter_table = ON;`); err != nil {
		t.Fatal(err)
	}

	fkPattern := regexp.MustCompile(`,(\s*(?:--[^\n]*\n\s*)*)FOREIGN KEY\s*\([^)]*\)\s*REFERENCES\s*"Sample_Env"\s*\([^)]*\)(?:\s+ON\s+(?:UPDATE|DELETE)\s+\w+)*`)
	tables := []struct {
		name    string
		plotCol string
	}{
		{"Sample_Env", "PlotNumber"},
		{"Sample_Admin", "Plot"},
		{"Sample_Veg", "PlotNumber"},
		{"Sample_Humus", "PlotNumber"},
		{"Sample_Mineral", "PlotNumber"},
		{"Sample_Other", "PlotNumber"},
		{"Sample_Audit", "PlotNumber"},
	}

	for _, tbl := range tables {
		var createSQL string
		if err := db.QueryRow(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?`, tbl.name).Scan(&createSQL); err != nil {
			t.Fatalf("read DDL for %s: %v", tbl.name, err)
		}
		idxRows, err := db.Query(`SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL`, tbl.name)
		if err != nil {
			t.Fatal(err)
		}
		var idxNames []string
		for idxRows.Next() {
			var idx string
			if err := idxRows.Scan(&idx); err != nil {
				idxRows.Close()
				t.Fatal(err)
			}
			idxNames = append(idxNames, idx)
		}
		idxRows.Close()
		for _, idx := range idxNames {
			if _, err := db.Exec(`DROP INDEX IF EXISTS "` + idx + `"`); err != nil {
				t.Fatal(err)
			}
		}

		updatedSQL := fkPattern.ReplaceAllString(createSQL, "$1")
		targetDecl := `"` + tbl.plotCol + `" VARCHAR`
		replacementDecl := `"` + tbl.plotCol + `" TEXT COLLATE NOCASE`
		if !strings.Contains(updatedSQL, targetDecl) {
			t.Fatalf("expected %s in %s DDL, got:\n%s", targetDecl, tbl.name, updatedSQL)
		}
		updatedSQL = strings.Replace(updatedSQL, targetDecl, replacementDecl, 1)

		tmpName := tbl.name + "_w3tmp"
		if _, err := db.Exec(`ALTER TABLE "` + tbl.name + `" RENAME TO "` + tmpName + `"`); err != nil {
			t.Fatalf("rename %s: %v", tbl.name, err)
		}
		if _, err := db.Exec(updatedSQL); err != nil {
			t.Fatalf("recreate %s with COLLATE NOCASE: %v\nSQL:\n%s", tbl.name, err, updatedSQL)
		}
		if _, err := db.Exec(`INSERT INTO "` + tbl.name + `" SELECT * FROM "` + tmpName + `"`); err != nil {
			t.Fatalf("copy %s: %v", tbl.name, err)
		}
		if _, err := db.Exec(`DROP TABLE "` + tmpName + `"`); err != nil {
			t.Fatalf("drop %s: %v", tmpName, err)
		}
		if _, err := db.Exec(`CREATE INDEX "idx_w3_` + tbl.name + `_plot" ON "` + tbl.name + `" ("` + tbl.plotCol + `" COLLATE NOCASE)`); err != nil {
			t.Fatalf("index %s: %v", tbl.name, err)
		}
	}
}

func TestEngGo007ExactTextPlotPredicatesAndUSysEnvUnderCollateNocaseAndNumericSU(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)
	rebuildSampleProjectTablesWithCollateNocase(t, state.ProjectPath)

	// Seed '00337' (already in Sample.db; normalize to deterministic test values), '337', '00337a', and '00337A'.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Sample_Veg WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Humus WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Mineral WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Other WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Audit WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Admin WHERE Plot IN ('00337', '337', '00337a', '00337A');
		DELETE FROM Sample_Env WHERE PlotNumber IN ('00337', '337', '00337a', '00337A');

		INSERT INTO Sample_Env (PlotNumber, Zone, Elevation, SiteNotes, Flag) VALUES
			('00337',  'CWH', 110, 'note-00337',  0),
			('337',    'ICH', 220, 'note-337',    0),
			('00337a', 'SBS', 330, 'note-lower',  0),
			('00337A', 'ESSF', 440, 'note-upper', 0);
		INSERT INTO Sample_Admin (Plot, StartDate, UserSiteUnit) VALUES
			('00337',  2020, 'CWH/01'),
			('337',    2021, 'ICH/02'),
			('00337a', 2022, 'SBS/03'),
			('00337A', 2023, 'ESSF/04');
		INSERT INTO Sample_Veg (ID, PlotNumber, Species, Layer, Cover1, Height1, LL, Flag) VALUES
			(9101, '00337',  'PSEUMEN', 'A', 10, 20, 1, 0),
			(9102, '337',    'TSUGHET', 'A', 15, 22, 2, 0),
			(9103, '00337a', 'THUJPIC', 'A', 25, 24, 3, 0),
			(9104, '00337A', 'ABIEAMA', 'A', 35, 26, 4, 0),
			(9105, '00337A', 'PINUCON', 'A', 12, 18, 5, 0);
	`)

	readCoordinatorViewPlots := func(viewName string) []string {
		t.Helper()
		out, err := vprocore.WithContextPlotRequest(ctx, svc, state.ContextID, func(plots *vprocore.PlotService) ([]string, error) {
			return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(_ *vprocore.SqliteContext, tx *sql.Tx) ([]string, error) {
				rows, err := tx.QueryContext(ctx, `SELECT PlotNumber FROM `+vprocore.QuoteHeaderIdentifier(viewName)+` ORDER BY CAST(PlotNumber AS BLOB)`)
				if err != nil {
					return nil, err
				}
				defer rows.Close()
				var got []string
				for rows.Next() {
					var p string
					if err := rows.Scan(&p); err != nil {
						return nil, err
					}
					got = append(got, p)
				}
				return got, rows.Err()
			})
		})
		if err != nil {
			t.Fatalf("query %s: %v", viewName, err)
		}
		return out
	}
	readUSysEnvPlots := func() []string { return readCoordinatorViewPlots("USysEnv") }

	// 1a. External _SU table with PlotNumber NUMERIC is rejected upfront by SwitchContext.
	numSUPath := filepath.Join(t.TempDir(), "numsu.db")
	numDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(numSUPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := numDB.Exec(`
		CREATE TABLE Num_SU (PlotNumber NUMERIC, SiteUnit TEXT);
		INSERT INTO Num_SU (PlotNumber, SiteUnit) VALUES ('00337', 'U1'), ('00337a', 'U2');
	`); err != nil {
		numDB.Close()
		t.Fatal(err)
	}
	numDB.Close()

	sel := vprotest.ContextSelection(state)
	sel.SU, sel.SUPath = "Num", numSUPath
	if _, err := svc.SwitchContext(state.ContextID, sel); err == nil {
		t.Fatal("expected SwitchContext to reject non-TEXT PlotNumber NUMERIC in Num_SU")
	}

	// 1b. External _SU table with PlotNumber INT_TEXT (SQLite INTEGER affinity due to INT rule, while containing "TEXT")
	// coerces '00337' to INTEGER 337: USysEnv must NOT conflate integer 337 with '00337' or '337', nor '00337a' with '00337A'!
	intTextSUPath := filepath.Join(t.TempDir(), "inttextsu.db")
	itDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(intTextSUPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := itDB.Exec(`
		CREATE TABLE IntText_SU (PlotNumber INT_TEXT, SiteUnit TEXT);
		INSERT INTO IntText_SU (PlotNumber, SiteUnit) VALUES ('00337', 'U1'), ('00337a', 'U2');
	`); err != nil {
		itDB.Close()
		t.Fatal(err)
	}
	itDB.Close()

	sel.SU, sel.SUPath = "IntText", intTextSUPath
	state, err = svc.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatalf("SwitchContext(IntText_SU): %v", err)
	}
	if got := readUSysEnvPlots(); !reflect.DeepEqual(got, []string{"00337a"}) {
		t.Fatalf("USysEnv with INT_TEXT _SU ('00337'->337, '00337a'->text) = %v, want [00337a]", got)
	}
	// Verify Filtered_Env also never cross-joins '00337a' with '00337A' under COLLATE NOCASE.
	filteredCounts := map[string]int{}
	for _, p := range readCoordinatorViewPlots("Filtered_Env") {
		filteredCounts[p]++
	}
	for _, p := range []string{"00337", "337", "00337a", "00337A"} {
		if filteredCounts[p] != 1 {
			t.Fatalf("Filtered_Env cross-joined or dropped %q: count=%d", p, filteredCounts[p])
		}
	}

	// 2. External _SU table with PlotNumber TEXT COLLATE NOCASE containing '00337' and '00337a':
	// USysEnv must return ONLY ['00337', '00337a'], never '337' or '00337A'.
	nocaseSUPath := filepath.Join(t.TempDir(), "nocasesu.db")
	ncDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(nocaseSUPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ncDB.Exec(`
		CREATE TABLE Nocase_SU (PlotNumber TEXT COLLATE NOCASE, SiteUnit TEXT);
		INSERT INTO Nocase_SU (PlotNumber, SiteUnit) VALUES ('00337', 'U1'), ('00337a', 'U2');
	`); err != nil {
		ncDB.Close()
		t.Fatal(err)
	}
	ncDB.Close()

	sel.SU, sel.SUPath = "Nocase", nocaseSUPath
	state, err = svc.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatalf("SwitchContext(Nocase_SU): %v", err)
	}
	if got := readUSysEnvPlots(); !reflect.DeepEqual(got, []string{"00337", "00337a"}) {
		t.Fatalf("USysEnv with TEXT COLLATE NOCASE _SU = %v, want [00337 00337a]", got)
	}

	// 3. GetPlot / ReadHeader isolates all 4 plots under COLLATE NOCASE without cross-plot leakage.
	for _, want := range []struct {
		plot  string
		elev  int
		start int
		notes string
	}{
		{"00337", 110, 2020, "note-00337"},
		{"337", 220, 2021, "note-337"},
		{"00337a", 330, 2022, "note-lower"},
		{"00337A", 440, 2023, "note-upper"},
	} {
		h, err := svc.GetPlot(ctx, state.ContextID, want.plot)
		if err != nil {
			t.Fatalf("GetPlot(%q): %v", want.plot, err)
		}
		if h.PlotNumber != want.plot || h.Elevation == nil || *h.Elevation != want.elev ||
			h.StartDate == nil || *h.StartDate != want.start || h.FieldNotes == nil || *h.FieldNotes != want.notes {
			t.Fatalf("GetPlot(%q) mismatch: got elev=%v start=%v notes=%v", want.plot, h.Elevation, h.StartDate, h.FieldNotes)
		}
	}

	// 4. SavePlot / UpdatePlot on '00337a' updates ONLY '00337a', leaving '00337A', '00337', and '337' untouched.
	hLower, err := svc.GetPlot(ctx, state.ContextID, "00337a")
	if err != nil {
		t.Fatal(err)
	}
	elev335 := 335
	notesEdited := "note-lower-edited"
	hLower.Elevation = &elev335
	hLower.FieldNotes = &notesEdited
	if err := svc.UpdatePlot(state.ContextID, *hLower); err != nil {
		t.Fatalf("UpdatePlot('00337a'): %v", err)
	}
	hUpper, err := svc.GetPlot(ctx, state.ContextID, "00337A")
	if err != nil {
		t.Fatal(err)
	}
	if hUpper.Elevation == nil || *hUpper.Elevation != 440 || hUpper.FieldNotes == nil || *hUpper.FieldNotes != "note-upper" {
		t.Fatalf("UpdatePlot('00337a') leaked onto '00337A': elev=%v notes=%v", hUpper.Elevation, hUpper.FieldNotes)
	}

	// Also change '00337A' Elevation so both '00337a' and '00337A' have audit rows in Sample_Audit!
	elev445 := 445
	hUpper.Elevation = &elev445
	if err := svc.UpdatePlot(state.ContextID, *hUpper); err != nil {
		t.Fatalf("UpdatePlot('00337A'): %v", err)
	}

	// 5. SaveChild / ListVegRecords / UpdateChildPatches / UpdateHeightRecords / DeleteVegRecord stay strictly isolated.
	cover8 := 8.0
	if err := svc.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "00337a",
		Species:    "PICEENG",
		Cover1:     &cover8,
	}); err != nil {
		t.Fatalf("SaveVegRecord('00337a'): %v", err)
	}
	vegLower, err := svc.ListVegRecords(ctx, state.ContextID, "00337a")
	if err != nil || len(vegLower) != 2 {
		t.Fatalf("ListVegRecords('00337a') = %d rows, err=%v; want 2", len(vegLower), err)
	}
	vegUpper, err := svc.ListVegRecords(ctx, state.ContextID, "00337A")
	if err != nil || len(vegUpper) != 2 {
		t.Fatalf("ListVegRecords('00337A') = %d rows, err=%v; want 2", len(vegUpper), err)
	}

	// Attempt to delete '00337A' row ID 9105 while passing plot '00337a': must NOT delete 9105 from '00337A'!
	_ = svc.DeleteVegRecord(state.ContextID, "00337a", 9105)
	vegUpperAfterCrossDelete, err := svc.ListVegRecords(ctx, state.ContextID, "00337A")
	if err != nil || len(vegUpperAfterCrossDelete) != 2 {
		t.Fatalf("DeleteVegRecord('00337a', 9105) cross-deleted '00337A' row: got %d rows, err=%v", len(vegUpperAfterCrossDelete), err)
	}

	// Delete the newly added PICEENG row from '00337a'.
	var piceID int64
	for _, v := range vegLower {
		if v.Species == "PICEENG" {
			piceID = v.ID
		}
	}
	if err := svc.DeleteVegRecord(state.ContextID, "00337a", piceID); err != nil {
		t.Fatalf("DeleteVegRecord('00337a', %d): %v", piceID, err)
	}

	// UpdateChildPatches & UpdateHeightRecords on '00337a' row 9103 must not touch '00337A' row 9104.
	if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		return plots.UpdateChildPatches("00337a", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			Id:   9103,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: 3, Value: 7, Scalar: reflect.Int},
			},
		}})
	}); err != nil {
		t.Fatalf("UpdateChildPatches('00337a'): %v", err)
	}
	expH := 24.0
	newH := 29.5
	if err := svc.UpdateHeightRecords(state.ContextID, "00337a", []vprocore.HeightRecordUpdate{{
		ID:       9103,
		Expected: map[string]*float64{"height1": &expH},
		Values:   map[string]*float64{"height1": &newH},
	}}); err != nil {
		t.Fatalf("UpdateHeightRecords('00337a'): %v", err)
	}

	// 6. Audit listing, selection, and RestoreSelectedAuditRecords operate strictly on '00337a' without touching '00337A'.
	auditsLower, err := svc.ListAuditEntries(ctx, state.ContextID, "00337a")
	if err != nil || len(auditsLower) == 0 {
		t.Fatalf("ListAuditEntries('00337a'): len=%d err=%v", len(auditsLower), err)
	}
	var elevRowID string
	for _, a := range auditsLower {
		if a.PlotNumber != "00337a" {
			t.Fatalf("ListAuditEntries('00337a') leaked cross-case audit row for %q", a.PlotNumber)
		}
		if a.EditField == "Elevation" {
			elevRowID = a.RowID
		}
	}
	if elevRowID == "" {
		t.Fatal("missing Elevation audit entry on '00337a'")
	}

	// Mark '00337A' audit rows Restore = -1 in SQLite and verify SetAuditRestoreSelection('00337a', ...) does NOT clear '00337A'!
	vprotest.MutateContextFixture(t, state.ProjectPath, `UPDATE Sample_Audit SET Restore = -1 WHERE CAST(PlotNumber AS BLOB) = CAST('00337A' AS BLOB)`)
	if err := svc.SetAuditRestoreSelection(state.ContextID, "00337a", []string{elevRowID}); err != nil {
		t.Fatalf("SetAuditRestoreSelection('00337a'): %v", err)
	}

	roDB, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()
	var upperRestoreCnt int
	if err := roDB.QueryRow(`SELECT COUNT(*) FROM Sample_Audit WHERE CAST(PlotNumber AS BLOB) = CAST('00337A' AS BLOB) AND Restore <> 0`).Scan(&upperRestoreCnt); err != nil {
		t.Fatal(err)
	}
	if upperRestoreCnt == 0 {
		t.Fatal("SetAuditRestoreSelection('00337a') cleared Restore flag on '00337A'")
	}

	res, err := svc.RestoreSelectedAuditRecords(state.ContextID, "00337a", []string{elevRowID}, vprocore.AuditRestorePrune)
	if err != nil || res.RestoredRows != 1 || res.PrunedAuditRows != 1 {
		t.Fatalf("RestoreSelectedAuditRecords('00337a') = %+v, err=%v", res, err)
	}

	restoredLower, err := svc.GetPlot(ctx, state.ContextID, "00337a")
	if err != nil || restoredLower.Elevation == nil || *restoredLower.Elevation != 330 {
		t.Fatalf("expected '00337a' Elevation restored to 330, got %+v err=%v", restoredLower, err)
	}
	unchangedUpper, err := svc.GetPlot(ctx, state.ContextID, "00337A")
	if err != nil || unchangedUpper.Elevation == nil || *unchangedUpper.Elevation != 445 {
		t.Fatalf("expected '00337A' Elevation to remain 445, got %+v err=%v", unchangedUpper, err)
	}
}

func TestUxEnv004SiteBoundsAndLegacyHistoricalTolerance(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	intP := func(v int) *int { return &v }
	fltP := func(v float64) *float64 { return &v }
	strP := func(v string) *string { return &v }

	// 1. Reject out-of-range LMH25 & Access site values on CreatePlot with zero DB writes.
	badCreateCases := []struct {
		name   string
		mutate func(*vprocore.FS882Header)
	}{
		{"date_non_iso", func(h *vprocore.FS882Header) { h.Date = strP("not-a-date") }},
		{"date_feb_30", func(h *vprocore.FS882Header) { h.Date = strP("2026-02-30") }},
		{"start_date_99999", func(h *vprocore.FS882Header) { h.StartDate = intP(99999) }},
		{"start_date_1899", func(h *vprocore.FS882Header) { h.StartDate = intP(1899) }},
		{"elevation_neg_500", func(h *vprocore.FS882Header) { h.Elevation = intP(-500) }},
		{"elevation_9001", func(h *vprocore.FS882Header) { h.Elevation = intP(9001) }},
		{"slope_neg_15", func(h *vprocore.FS882Header) { h.Slope = fltP(-15) }},
		{"aspect_500", func(h *vprocore.FS882Header) { h.Aspect = intP(500) }},
		{"aspect_neg_1", func(h *vprocore.FS882Header) { h.Aspect = intP(-1) }},
		{"stand_age_neg_1", func(h *vprocore.FS882Header) { h.StandAge = intP(-1) }},
		{"accuracy_neg_1", func(h *vprocore.FS882Header) { h.Accuracy = intP(-1) }},
		{"utm_zone_southern_9S", func(h *vprocore.FS882Header) { h.UTMZone = strP("9S") }},
		{"structural_stage_over_6", func(h *vprocore.FS882Header) { h.StructuralStage = strP("1234567") }},
		{"successional_over_3_BOGUS", func(h *vprocore.FS882Header) { h.Successional = strP("BOGUS") }},
		{"substrate_neg_5", func(h *vprocore.FS882Header) { h.SubstrateOrganicMatter = fltP(-5) }},
		{"substrate_150", func(h *vprocore.FS882Header) { h.SubstrateMineralSoil = fltP(150) }},
		{"latitude_95", func(h *vprocore.FS882Header) { h.Latitude = fltP(95) }},
		{"longitude_neg_190", func(h *vprocore.FS882Header) { h.Longitude = fltP(-190) }},
	}

	for _, tc := range badCreateCases {
		h := vprocore.FS882Header{PlotNumber: "QALMH1"}
		tc.mutate(&h)
		if err := svc.CreatePlot(state.ContextID, h); err == nil {
			t.Fatalf("%s: expected CreatePlot(QALMH1) to reject invalid value", tc.name)
		}
	}

	roDB, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()
	var qaCnt int
	if err := roDB.QueryRow(`SELECT COUNT(*) FROM Sample_Env WHERE PlotNumber = 'QALMH1'`).Scan(&qaCnt); err != nil {
		t.Fatal(err)
	}
	if qaCnt != 0 {
		t.Fatalf("expected 0 rows for rejected QALMH1, got %d", qaCnt)
	}

	// 2. Valid boundary values (including Aspect = 999 level ground, Elevation = 0, Slope = 0, StartDate = 2026, UTMZone = 10N) succeed.
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{
		PlotNumber:             "QALMHOK",
		Date:                   strP("2026-07-15"),
		StartDate:              intP(2026),
		Elevation:              intP(0),
		Slope:                  fltP(0),
		Aspect:                 intP(999),
		StandAge:               intP(120),
		Accuracy:               intP(10),
		UTMZone:                strP("10N"),
		StructuralStage:        strP("6"),
		Successional:           strP("MC"),
		SubstrateOrganicMatter: fltP(60),
		SubstrateMineralSoil:   fltP(40),
		Latitude:               fltP(54.5),
		Longitude:              fltP(-126.5),
	}); err != nil {
		t.Fatalf("CreatePlot(QALMHOK) with valid LMH25 values failed: %v", err)
	}

	// 3. Seed an existing plot with historical anomalies and verify unrelated edits succeed without rewriting legacy values.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (
			PlotNumber, Date, Elevation, SlopeGradient, Aspect, StandAge, LocationAccuracy,
			UTMZone, StructuralStage, SuccessionalStatus, SubstrateOrganicMatter, Latitude, Longitude, SiteNotes, Flag
		) VALUES (
			'LEGLMH', 'not-a-date', -500, -15.0, 500, -10, -5,
			'9S', '1234567', 'BOGUS', 150.0, 95.0, -195.0, 'Initial note', 0
		);
		INSERT INTO Sample_Admin (Plot, StartDate) VALUES ('LEGLMH', 99999);
	`)

	leg, err := svc.GetPlot(ctx, state.ContextID, "LEGLMH")
	if err != nil {
		t.Fatalf("GetPlot(LEGLMH): %v", err)
	}
	leg.FieldNotes = strP("Updated note preserving legacy anomalies")
	if err := svc.UpdatePlot(state.ContextID, *leg); err != nil {
		t.Fatalf("expected unrelated FieldNotes update on LEGLMH to succeed, got %v", err)
	}

	// Changing an anomalous field to ANOTHER invalid value must still be rejected!
	legBad := *leg
	legBad.Aspect = intP(450)
	if err := svc.UpdatePlot(state.ContextID, legBad); err == nil {
		t.Fatal("expected changing Aspect from 500 to 450 on LEGLMH to fail")
	}

	var storedDate, storedStage, storedSucc, storedZone, storedNotes string
	var storedElev, storedAspect, storedStart int
	var storedSlope, storedSub float64
	if err := roDB.QueryRow(`
		SELECT CAST(e.Date AS TEXT), e.Elevation, e.SlopeGradient, e.Aspect, e.UTMZone, e.StructuralStage, e.SuccessionalStatus,
		       e.SubstrateOrganicMatter, e.SiteNotes, a.StartDate
		FROM Sample_Env e JOIN Sample_Admin a ON e.PlotNumber = a.Plot
		WHERE e.PlotNumber = 'LEGLMH'
	`).Scan(&storedDate, &storedElev, &storedSlope, &storedAspect, &storedZone, &storedStage, &storedSucc, &storedSub, &storedNotes, &storedStart); err != nil {
		t.Fatal(err)
	}
	if storedDate != "not-a-date" || storedElev != -500 || storedSlope != -15.0 || storedAspect != 500 ||
		storedZone != "9S" || storedStage != "1234567" || storedSucc != "BOGUS" || storedSub != 150.0 ||
		storedStart != 99999 || storedNotes != "Updated note preserving legacy anomalies" {
		t.Fatalf("legacy plot columns unexpectedly mutated: date=%q elev=%d slope=%v aspect=%d start=%d notes=%q",
			storedDate, storedElev, storedSlope, storedAspect, storedStart, storedNotes)
	}
}

func TestUxEnv005PlotNumberWhitespaceRejectedOnCreatePreservedOnLegacyEdit(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	for _, padded := range []string{"00888 ", " 00887", "\t00886", "00885\n"} {
		if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: padded}); err == nil || !strings.Contains(err.Error(), "whitespace") {
			t.Fatalf("CreatePlot(%q): expected whitespace error, got %v", padded, err)
		}
		if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
			return plots.SavePlot(vprocore.FS882Header{PlotNumber: padded})
		}); err == nil || !strings.Contains(err.Error(), "whitespace") {
			t.Fatalf("SavePlot(%q) on new plot: expected whitespace error, got %v", padded, err)
		}
	}

	roDB, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()
	var cnt int
	if err := roDB.QueryRow(`SELECT COUNT(*) FROM Sample_Env WHERE PlotNumber LIKE '%0088%'`).Scan(&cnt); err != nil {
		t.Fatal(err)
	}
	if cnt != 0 {
		t.Fatalf("expected 0 rows written for whitespace-padded new plots, got %d", cnt)
	}

	// Seed legacy imported plots with leading and trailing spaces and verify read + edit remain non-bricking.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SiteNotes, Flag) VALUES
			(' 00337', 'CWH', 'leading-space-legacy', 0),
			('00888 ', 'ICH', 'trailing-space-legacy', 0);
		INSERT INTO Sample_Admin (Plot, StartDate) VALUES
			(' 00337', 2018),
			('00888 ', 2019);
	`)

	for _, legacyPlot := range []string{" 00337", "00888 "} {
		h, err := svc.GetPlot(ctx, state.ContextID, legacyPlot)
		if err != nil {
			t.Fatalf("GetPlot(%q): %v", legacyPlot, err)
		}
		updatedNote := "edited:" + legacyPlot
		h.FieldNotes = &updatedNote
		if err := svc.UpdatePlot(state.ContextID, *h); err != nil {
			t.Fatalf("UpdatePlot(%q) on existing legacy plot failed: %v", legacyPlot, err)
		}
		reread, err := svc.GetPlot(ctx, state.ContextID, legacyPlot)
		if err != nil || reread.FieldNotes == nil || *reread.FieldNotes != updatedNote {
			t.Fatalf("reread %q after UpdatePlot = %+v, err=%v", legacyPlot, reread, err)
		}
	}
}
