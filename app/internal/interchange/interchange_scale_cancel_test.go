package interchange

import (
	"context"
	"database/sql"
	"encoding/csv"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func explainQueryPlanDetails(t *testing.T, tx *sql.Tx, query string) []string {
	t.Helper()
	rows, err := tx.Query(`EXPLAIN QUERY PLAN ` + query)
	if err != nil {
		t.Fatalf("EXPLAIN QUERY PLAN failed: %v\nSQL:\n%s", err, query)
	}
	defer rows.Close()

	var details []string
	for rows.Next() {
		var id, parent, notused int
		var detail string
		if err := rows.Scan(&id, &parent, &notused, &detail); err != nil {
			t.Fatalf("scan EXPLAIN QUERY PLAN: %v", err)
		}
		details = append(details, detail)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("rows EXPLAIN QUERY PLAN: %v", err)
	}
	return details
}

func assertIndexedScopedPlan(t *testing.T, label string, details []string) {
	t.Helper()
	joined := strings.Join(details, "\n")
	hasIndexSearch := false
	for _, d := range details {
		if strings.Contains(d, "SEARCH ") && strings.Contains(d, "INDEX") {
			hasIndexSearch = true
		}
		// Ensure we never regress to an unindexed full-table scan of USysEnv / Env / Admin / SU inside correlated subqueries.
		if strings.HasPrefix(d, "SCAN e") && !strings.Contains(d, "USING ") {
			t.Fatalf("%s regressed to unindexed SCAN on Env/USysEnv:\n%s", label, joined)
		}
		if strings.HasPrefix(d, "SCAN u") && !strings.Contains(d, "USING ") {
			t.Fatalf("%s regressed to unindexed SCAN on USysEnv:\n%s", label, joined)
		}
		if strings.HasPrefix(d, "SCAN a") && !strings.Contains(d, "USING ") {
			t.Fatalf("%s regressed to unindexed SCAN on Admin:\n%s", label, joined)
		}
	}
	if !hasIndexSearch {
		t.Fatalf("%s expected indexed SEARCH in EXPLAIN QUERY PLAN, got:\n%s", label, joined)
	}
}

func TestInterchangeExportsIndexedQueryPlanAndMultiThousandPlotScale(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	const numPlots = 4000
	const sppPerPlot = 8 // 32,000 _Veg rows + 4,000 _Humus + 4,000 _Mineral rows
	speciesPool := [sppPerPlot]string{
		"PSEUMEN", "TSUGHET", "THUJPLI", "VACCMEM",
		"CORNCAN", "LINNBOR", "HYLOSPL", "PLEUSCH",
	}

	// Seed 4,000 plots + 32,000 veg rows + soil rows + an unindexed 250-plot *_SU table in one transaction.
	func() {
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw"))
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		tx, err := db.Begin()
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = tx.Rollback() }()

		if _, err := tx.Exec(`
			DELETE FROM Sample_Veg;
			DELETE FROM Sample_Humus;
			DELETE FROM Sample_Mineral;
			DELETE FROM Sample_Admin;
			DELETE FROM Sample_Env;
			CREATE INDEX IF NOT EXISTS idx_scale_env_plot ON Sample_Env(PlotNumber);
			CREATE INDEX IF NOT EXISTS idx_scale_admin_plot ON Sample_Admin(Plot);
			CREATE INDEX IF NOT EXISTS idx_scale_veg_plot ON Sample_Veg(PlotNumber);
			CREATE INDEX IF NOT EXISTS idx_scale_humus_plot ON Sample_Humus(PlotNumber);
			CREATE INDEX IF NOT EXISTS idx_scale_mineral_plot ON Sample_Mineral(PlotNumber);
			CREATE TABLE IF NOT EXISTS UnindexedScale_SU (PlotNumber VARCHAR, SiteUnit VARCHAR);
			DELETE FROM UnindexedScale_SU;
			INSERT OR REPLACE INTO _table_metadata (table_name, description) VALUES ('UnindexedScale_SU', 'VP04');
		`); err != nil {
			t.Fatal(err)
		}

		envStmt, err := tx.Prepare(`INSERT INTO Sample_Env (PlotNumber, Latitude, Longitude, Elevation, "Zone", SubZone, SiteSeries, Flag) VALUES (?, ?, ?, ?, 'CWH', 'vm1', '01', 0)`)
		if err != nil {
			t.Fatal(err)
		}
		defer envStmt.Close()

		admStmt, err := tx.Prepare(`INSERT INTO Sample_Admin (Plot, PlotType, UserSiteUnit, UpdatedFromCards) VALUES (?, 'FS882', 'CWHvm1/01', 0)`)
		if err != nil {
			t.Fatal(err)
		}
		defer admStmt.Close()

		vegStmt, err := tx.Prepare(`INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1, Cover6, Flag) VALUES (?, ?, ?, ?, ?, 0)`)
		if err != nil {
			t.Fatal(err)
		}
		defer vegStmt.Close()

		humStmt, err := tx.Prepare(`INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES (?, ?, 'Fm', 6.0, 0.0, 0)`)
		if err != nil {
			t.Fatal(err)
		}
		defer humStmt.Close()

		minStmt, err := tx.Prepare(`INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Texture, Flag) VALUES (?, ?, 'Bm1', 0.0, 35.0, 'SL', 0)`)
		if err != nil {
			t.Fatal(err)
		}
		defer minStmt.Close()

		suStmt, err := tx.Prepare(`INSERT INTO UnindexedScale_SU (PlotNumber, SiteUnit) VALUES (?, 'CWHvm1/05')`)
		if err != nil {
			t.Fatal(err)
		}
		defer suStmt.Close()

		vegID := 1
		for i := 1; i <= numPlots; i++ {
			plot := fmt.Sprintf("P%06d", i)
			lat := 50.0 + float64(i%500)*0.005
			lon := -124.0 - float64(i%500)*0.005
			if _, err := envStmt.Exec(plot, lat, lon, 400+(i%800)); err != nil {
				t.Fatal(err)
			}
			if _, err := admStmt.Exec(plot); err != nil {
				t.Fatal(err)
			}
			if _, err := humStmt.Exec(i, plot); err != nil {
				t.Fatal(err)
			}
			if _, err := minStmt.Exec(i, plot); err != nil {
				t.Fatal(err)
			}
			if i <= 250 {
				if _, err := suStmt.Exec(plot); err != nil {
					t.Fatal(err)
				}
			}
			for s := 0; s < sppPerPlot; s++ {
				var c1, c6 any
				if s < 3 {
					c1 = float64(10 + s*5)
				} else {
					c6 = float64(4 + s*2)
				}
				if _, err := vegStmt.Exec(vegID, plot, speciesPool[s], c1, c6); err != nil {
					t.Fatal(err)
				}
				vegID++
			}
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}()

	// Re-switch context so SqliteContext views reflect fresh data
	selAll := vprotest.ContextSelection(state)
	state, err := service.SwitchContext(state.ContextID, selAll)
	if err != nil {
		t.Fatalf("SwitchContext(all): %v", err)
	}

	// 1. Verify EXPLAIN QUERY PLAN uses indexed SEARCH across all scoped tables (both SU="None" and unindexed SU!="None").
	checkPlans := func(label string) {
		owner := service.Projects.Sqlite
		if err := withScopedReadSnapshot(ctx, owner, func(tx *sql.Tx) error {
			for _, tbl := range []struct {
				table string
				expr  string
			}{
				{"Sample_Env", `t."PlotNumber"`},
				{"Sample_Admin", `t."Plot"`},
				{"Sample_Veg", `t."PlotNumber"`},
				{"Sample_Humus", `t."PlotNumber"`},
				{"Sample_Mineral", `t."PlotNumber"`},
			} {
				cte, pred := scopedPlotsCTEAndPredicate(owner, tbl.expr)
				q := cte + `SELECT 1 FROM project.` + vprocore.QuoteHeaderIdentifier(tbl.table) + ` AS t WHERE ` + pred
				details := explainQueryPlanDetails(t, tx, q)
				assertIndexedScopedPlan(t, label+"/"+tbl.table, details)
			}
			return nil
		}); err != nil {
			t.Fatalf("checkPlans(%s): %v", label, err)
		}
	}
	checkPlans("Unscoped_4000Plots")

	// 2. Verify all 4 Interchange exports complete rapidly on 4,000 plots / 32,000 veg rows.
	// Use a generous race-safe ceiling while logging sub-second non-race timings.
	dir := t.TempDir()

	t0 := time.Now()
	longOut, err := ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{
		DestinationPath: filepath.Join(dir, "scale_long.csv"),
	})
	longDur := time.Since(t0)
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(4000 plots): %v", err)
	}
	if longOut.PlotCount != numPlots || longOut.RowCount != numPlots*sppPerPlot {
		t.Fatalf("unexpected Long CSV counts: %+v", longOut)
	}

	t1 := time.Now()
	wideOut, err := ExportWideMatrixCSV(service, ctx, state.ContextID, WideMatrixCSVRequest{
		DestinationPath: filepath.Join(dir, "scale_wide.csv"),
		LayerMode:       "rollup_all",
		ZeroFill:        true,
		IncludeSiteUnit: true,
	})
	wideDur := time.Since(t1)
	if err != nil {
		t.Fatalf("ExportWideMatrixCSV(4000 plots): %v", err)
	}
	if wideOut.PlotCount != numPlots || wideOut.SpeciesCount != sppPerPlot {
		t.Fatalf("unexpected Wide CSV counts: %+v", wideOut)
	}

	t2 := time.Now()
	rdsOut, err := ExportProjectRDS(service, ctx, state.ContextID, RDSExportRequest{
		DestinationPath: filepath.Join(dir, "scale.rds"),
	})
	rdsDur := time.Since(t2)
	if err != nil {
		t.Fatalf("ExportProjectRDS(4000 plots): %v", err)
	}
	if rdsOut.PlotCount != numPlots {
		t.Fatalf("unexpected RDS plot count: %+v", rdsOut)
	}

	t3 := time.Now()
	gpkgOut, err := ExportGeoPackage(service, ctx, state.ContextID, GeoPackageExportRequest{
		DestinationPath:        filepath.Join(dir, "scale.gpkg"),
		CRS:                    CRSEPSG3005,
		IncludeAttributeTables: true,
	})
	gpkgDur := time.Since(t3)
	if err != nil {
		t.Fatalf("ExportGeoPackage(4000 plots): %v", err)
	}
	if gpkgOut.FeatureCount != numPlots || len(gpkgOut.AttributeTables) != 3 {
		t.Fatalf("unexpected GeoPackage outcome: %+v", gpkgOut)
	}

	t.Logf("4,000 plots / 32,000 veg rows timings: LongCSV=%v WideCSV=%v RDS=%v GPKG=%v", longDur, wideDur, rdsDur, gpkgDur)
	for _, item := range []struct {
		name string
		dur  time.Duration
		max  time.Duration
	}{
		{"ExportLongTidyCSV", longDur, 5 * time.Second},
		{"ExportWideMatrixCSV", wideDur, 5 * time.Second},
		{"ExportProjectRDS", rdsDur, 5 * time.Second},
		{"ExportGeoPackage", gpkgDur, 8 * time.Second},
	} {
		if item.dur > item.max {
			t.Fatalf("%s took %v (> %v budget) on 4,000 plots", item.name, item.dur, item.max)
		}
	}

	// 3. Switch to unindexed 250-plot SU and verify indexed query plan + fast subset export.
	selSU := vprotest.ContextSelection(state)
	selSU.SU = "UnindexedScale"
	selSU.SUPath = state.ProjectPath
	stateSU, err := service.SwitchContext(state.ContextID, selSU)
	if err != nil {
		t.Fatalf("SwitchContext(UnindexedScale): %v", err)
	}
	checkPlans("UnindexedSU_250Plots")

	t4 := time.Now()
	suLongOut, err := ExportLongTidyCSV(service, ctx, stateSU.ContextID, LongTidyCSVRequest{})
	suDur := time.Since(t4)
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(UnindexedScale SU): %v", err)
	}
	if suLongOut.PlotCount != 250 || suLongOut.RowCount != 250*sppPerPlot {
		t.Fatalf("expected 250 SU-scoped plots and %d rows, got %+v", 250*sppPerPlot, suLongOut)
	}
	if !strings.Contains(suLongOut.PreviewCSV, "CWHvm1/05") {
		t.Fatalf("expected SU SiteUnit CWHvm1/05 in Long CSV preview:\n%s", suLongOut.PreviewCSV)
	}
	t.Logf("250-plot unindexed SU over 32,000 veg rows: LongCSV=%v", suDur)
}

func TestInterchangeExportsLiteralPlotNonCollision(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	// Seed '00337', '337', 'ab1', and 'AB1' in Sample, plus an integer 337 orphan row in Sample_Humus.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		PRAGMA foreign_keys = OFF;
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_Humus;
		DELETE FROM Sample_Mineral;
		DELETE FROM Sample_Admin;
		DELETE FROM Sample_Env;

		INSERT INTO Sample_Env (PlotNumber, Latitude, Longitude, "Zone", Flag) VALUES
			('00337', 54.10, -126.10, 'CWH', 0),
			('337',   54.20, -126.20, 'IDF', 0),
			('ab1',   54.30, -126.30, 'SBS', 0),
			('AB1',   54.40, -126.40, 'ICH', 0);

		INSERT INTO Sample_Admin (Plot, PlotType, UserSiteUnit, UpdatedFromCards) VALUES
			('00337', 'FS882', 'UNIT_00337', 0),
			('337',   'FS882', 'UNIT_337',   0),
			('ab1',   'FS882', 'UNIT_ab1',   0),
			('AB1',   'FS882', 'UNIT_AB1',   0);

		INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1, Flag) VALUES
			(1, '00337', 'TSUGHET', 40.0, 0),
			(2, '337',   'PSEUMEN', 25.0, 0),
			(3, 'ab1',   'PICEMAR', 15.0, 0),
			(4, 'AB1',   'ABIEAMA', 30.0, 0);

		ALTER TABLE Sample_Humus RENAME TO Sample_Humus_Orig;
		CREATE TABLE Sample_Humus (
			PlotNumber BLOB, Horizon VARCHAR, UpperDepth DOUBLE, LowerDepth DOUBLE,
			HumusStructureDegree VARCHAR, HumusStructureKind VARCHAR, MycelAbundance VARCHAR,
			FecalAbundance VARCHAR, RootsAbundance VARCHAR, RootsSize VARCHAR,
			vonPost INTEGER, HumusFormpH DOUBLE, Consistence VARCHAR, Character VARCHAR,
			Fauna VARCHAR, Comment VARCHAR, Flag BOOLEAN, ID INTEGER
		);
		DROP TABLE Sample_Humus_Orig;
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(10, '00337', 'Fm', 5.0, 0.0, 0),
			(11, '337',   'Fh', 4.0, 0.0, 0),
			(12, 337,     'H',  2.0, 0.0, 0);
	`)

	// External SU database with:
	// 1. LitNoCase_SU (COLLATE NOCASE) containing ONLY '00337' and 'ab1' (must NOT match '337' or 'AB1')
	// 2. LitInt_SU (INT_TEXT) containing integer 337 (must NOT match text '337' or '00337')
	extSUPath := filepath.Join(t.TempDir(), "InterchangeLiteralSU.db")
	extDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extSUPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := extDB.Exec(`
		CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT);
		INSERT INTO _table_metadata (table_name, description) VALUES ('LitNoCase_SU', 'VP04'), ('LitInt_SU', 'VP04');
		CREATE TABLE LitNoCase_SU (PlotNumber VARCHAR COLLATE NOCASE, SiteUnit VARCHAR);
		CREATE INDEX idx_lit_nc ON LitNoCase_SU(PlotNumber COLLATE NOCASE);
		INSERT INTO LitNoCase_SU (PlotNumber, SiteUnit) VALUES ('00337', 'SU_LZ_00337'), ('ab1', 'SU_LOWER_ab1');
		CREATE TABLE LitInt_SU (PlotNumber INT_TEXT, SiteUnit VARCHAR);
		INSERT INTO LitInt_SU (PlotNumber, SiteUnit) VALUES (337, 'SU_INT_337');
	`); err != nil {
		extDB.Close()
		t.Fatal(err)
	}
	extDB.Close()

	// Case A: LitNoCase_SU must export strictly '00337' and 'ab1' (excluding '337', 'AB1', and integer 337).
	selNC := vprotest.ContextSelection(state)
	selNC.SU = "LitNoCase"
	selNC.SUPath = extSUPath
	stateNC, err := service.SwitchContext(state.ContextID, selNC)
	if err != nil {
		t.Fatalf("SwitchContext(LitNoCase): %v", err)
	}

	dir := t.TempDir()
	longCSVPath := filepath.Join(dir, "lit_long.csv")
	longOut, err := ExportLongTidyCSV(service, ctx, stateNC.ContextID, LongTidyCSVRequest{DestinationPath: longCSVPath})
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(LitNoCase): %v", err)
	}
	if longOut.PlotCount != 2 || longOut.RowCount != 2 {
		t.Fatalf("expected strictly 2 plots ('00337', 'ab1'), got %+v", longOut)
	}
	rawCSV, err := os.ReadFile(longCSVPath)
	if err != nil {
		t.Fatal(err)
	}
	recs, err := csv.NewReader(strings.NewReader(string(rawCSV))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 3 || recs[1][0] != "00337" || recs[1][1] != "SU_LZ_00337" || recs[2][0] != "ab1" || recs[2][1] != "SU_LOWER_ab1" {
		t.Fatalf("unexpected literal Long CSV rows: %+v", recs)
	}

	wideOut, err := ExportWideMatrixCSV(service, ctx, stateNC.ContextID, WideMatrixCSVRequest{
		LayerMode:       "rollup_all",
		ZeroFill:        true,
		IncludeSiteUnit: true,
	})
	if err != nil || wideOut.PlotCount != 2 || wideOut.SpeciesCount != 2 {
		t.Fatalf("unexpected Wide CSV outcome: %+v (err=%v)", wideOut, err)
	}

	rdsOut, err := ExportProjectRDS(service, ctx, stateNC.ContextID, RDSExportRequest{
		DestinationPath: filepath.Join(dir, "lit.rds"),
	})
	if err != nil || rdsOut.PlotCount != 2 {
		t.Fatalf("unexpected RDS outcome: %+v (err=%v)", rdsOut, err)
	}
	for _, tbl := range rdsOut.Tables {
		if tbl.Name == "humus" && tbl.RowCount != 1 { // Only '00337' humus row (neither '337' nor integer 337!)
			t.Fatalf("expected 1 humus row ('00337') in RDS, got %+v", tbl)
		}
	}

	gpkgPath := filepath.Join(dir, "lit.gpkg")
	gpkgOut, err := ExportGeoPackage(service, ctx, stateNC.ContextID, GeoPackageExportRequest{
		DestinationPath:        gpkgPath,
		CRS:                    CRSEPSG4326,
		IncludeAttributeTables: true,
	})
	if err != nil || gpkgOut.FeatureCount != 2 {
		t.Fatalf("unexpected GeoPackage outcome: %+v (err=%v)", gpkgOut, err)
	}
	gDB, err := sqlutil.OpenReadOnly(gpkgPath)
	if err != nil {
		t.Fatal(err)
	}
	var gHumusCount int
	if err := gDB.QueryRow(`SELECT COUNT(*) FROM "humus"`).Scan(&gHumusCount); err != nil || gHumusCount != 1 {
		gDB.Close()
		t.Fatalf("expected 1 humus row in GeoPackage ('00337' only), got %d (err=%v)", gHumusCount, err)
	}
	gDB.Close()

	// Case B: LitInt_SU containing integer 337 must match ZERO text plots.
	selInt := vprotest.ContextSelection(stateNC)
	selInt.SU = "LitInt"
	selInt.SUPath = extSUPath
	stateInt, err := service.SwitchContext(stateNC.ContextID, selInt)
	if err != nil {
		t.Fatalf("SwitchContext(LitInt): %v", err)
	}
	intOut, err := ExportLongTidyCSV(service, ctx, stateInt.ContextID, LongTidyCSVRequest{})
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(LitInt): %v", err)
	}
	if intOut.PlotCount != 0 || intOut.RowCount != 0 {
		t.Fatalf("integer 337 in LitInt_SU must not match text '337': %+v", intOut)
	}
}

func TestInterchangeContextCancellationReleasesOwnerMutexAndCleansTempFiles(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	owner := service.Projects.Sqlite
	dir := t.TempDir()

	// 1. Hold owner.Mu externally, start each export with a short-timeout context, and verify
	//    AcquireMutexLease aborts promptly without hanging or leaving staged temp files.
	owner.LockForTest()
	for _, tc := range []struct {
		name string
		run  func(ctx context.Context) error
	}{
		{
			name: "LongTidyCSV",
			run: func(ctx context.Context) error {
				_, err := ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{
					DestinationPath: filepath.Join(dir, "cancel_long.csv"),
				})
				return err
			},
		},
		{
			name: "WideMatrixCSV",
			run: func(ctx context.Context) error {
				_, err := ExportWideMatrixCSV(service, ctx, state.ContextID, WideMatrixCSVRequest{
					DestinationPath: filepath.Join(dir, "cancel_wide.csv"),
					LayerMode:       "rollup_all",
				})
				return err
			},
		},
		{
			name: "ProjectRDS",
			run: func(ctx context.Context) error {
				_, err := ExportProjectRDS(service, ctx, state.ContextID, RDSExportRequest{
					DestinationPath: filepath.Join(dir, "cancel.rds"),
				})
				return err
			},
		},
		{
			name: "GeoPackage",
			run: func(ctx context.Context) error {
				_, err := ExportGeoPackage(service, ctx, state.ContextID, GeoPackageExportRequest{
					DestinationPath:        filepath.Join(dir, "cancel.gpkg"),
					CRS:                    CRSEPSG3005,
					IncludeAttributeTables: true,
				})
				return err
			},
		},
	} {
		cctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
		t0 := time.Now()
		err := tc.run(cctx)
		cancel()
		elapsed := time.Since(t0)
		if !errors.Is(err, context.DeadlineExceeded) && !errors.Is(err, context.Canceled) {
			owner.UnlockForTest()
			t.Fatalf("%s: expected context cancellation error while owner.Mu held, got %v", tc.name, err)
		}
		if elapsed > 2*time.Second {
			owner.UnlockForTest()
			t.Fatalf("%s: hung for %v waiting on owner.Mu despite ctx cancellation", tc.name, elapsed)
		}
	}
	owner.UnlockForTest()

	// 2. Seed a multi-thousand-row fixture, cancel mid-flight during GeoPackage / CSV / RDS export,
	//    and verify owner.Mu is released immediately so ListPlots succeeds and zero temp files remain.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 1500)
		INSERT OR IGNORE INTO Sample_Env (PlotNumber, Latitude, Longitude, "Zone", Flag)
		SELECT printf('C%05d', n), 52.0 + (n % 100)*0.01, -125.0 - (n % 100)*0.01, 'SBS', 0 FROM seq;
		WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 1500)
		INSERT OR IGNORE INTO Sample_Admin (Plot, PlotType, UpdatedFromCards)
		SELECT printf('C%05d', n), 'FS882', 0 FROM seq;
		WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 1500)
		INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1, Cover6, Flag)
		SELECT 500000 + n, printf('C%05d', n), 'PSEUMEN', 35.0, 12.0, 0 FROM seq;
	`)

	cancelDir := filepath.Join(dir, "midflight")
	if err := os.MkdirAll(cancelDir, 0o755); err != nil {
		t.Fatal(err)
	}
	gpkgCancelDest := filepath.Join(cancelDir, "midflight.gpkg")
	midCtx, midCancel := context.WithCancel(context.Background())
	doneCh := make(chan error, 1)
	go func() {
		_, err := ExportGeoPackage(service, midCtx, state.ContextID, GeoPackageExportRequest{
			DestinationPath:        gpkgCancelDest,
			CRS:                    CRSEPSG3005,
			IncludeAttributeTables: true,
		})
		doneCh <- err
	}()
	time.Sleep(5 * time.Millisecond)
	midCancel()

	select {
	case err := <-doneCh:
		// Export either cancelled cleanly or (on a very fast machine) finished before 5ms; if cancelled, destination must not exist.
		if err != nil {
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("unexpected error from cancelled ExportGeoPackage: %v", err)
			}
			if _, statErr := os.Stat(gpkgCancelDest); !errors.Is(statErr, os.ErrNotExist) {
				t.Fatalf("cancelled ExportGeoPackage must not publish destination file %s", gpkgCancelDest)
			}
		}
	case <-time.After(5 * time.Second):
		t.Fatal("ExportGeoPackage did not abort within 5s after context cancellation")
	}

	// Verify zero leftover staged .vpro-gpkg-* or .vpro-export-* temporary files in cancelDir.
	entries, err := os.ReadDir(cancelDir)
	if err != nil {
		t.Fatal(err)
	}
	for _, ent := range entries {
		if strings.HasPrefix(ent.Name(), ".vpro-") {
			t.Fatalf("leftover temporary staging file after cancellation: %s", ent.Name())
		}
	}

	// Verify Plots browser RPC (ListPlots) acquires owner.Mu and responds immediately after cancel.
	listCtx, listCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer listCancel()
	page, err := service.Projects.ListPlots(listCtx, 0, 25)
	if err != nil {
		t.Fatalf("ListPlots blocked or failed after export cancellation: %v", err)
	}
	if page.Total < 1500 || len(page.Plots) == 0 {
		t.Fatalf("expected populated ListPlots page after export cancellation, got total=%d len=%d", page.Total, len(page.Plots))
	}
}
