package rsidecar_test

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/boostao/vpro/app/internal/rsidecar"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/boostao/vpro/app/resources"
)

func TestRSidecarReadOnlyCallsDoNotMutateProjectDatabase(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	beforeBytes, err := os.ReadFile(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}

	assertUntouched := func(step string, expected []byte) {
		t.Helper()
		afterBytes, err := os.ReadFile(state.ProjectPath)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(beforeBytes, afterBytes) && expected == nil {
			t.Fatalf("%s mutated untouched project .db bytes on disk", step)
		}
		if expected != nil && !bytes.Equal(expected, afterBytes) {
			t.Fatalf("%s mutated DELETE-mode project .db bytes on disk", step)
		}
		if _, walErr := os.Stat(state.ProjectPath + "-wal"); !os.IsNotExist(walErr) {
			t.Fatalf("%s created unexpected WAL file %s-wal", step, state.ProjectPath)
		}
	}

	// 1. Cold read-only GetCachedPlotClimate on untouched project .db MUST NOT open mode=rw+WAL!
	rows, err := rsidecar.GetCachedPlotClimate(ctx, svc, state.ContextID, "1961_1990")
	if err != nil {
		t.Fatalf("GetCachedPlotClimate failed: %v", err)
	}
	if len(rows) != 0 {
		t.Fatalf("expected 0 cached rows on cold project, got %d", len(rows))
	}
	assertUntouched("GetCachedPlotClimate (cold)", beforeBytes)

	// 2. Seed __VPRO_PlotClimate for plot '00337' in DELETE journal mode, then verify
	// GetCachedPlotClimate AND 100%-cache-hit ComputePlotClimateAndDualEdatopic AND
	// non-materializing RunMultivariateClustering leave the .db file 100% byte-identical!
	seedDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw")+"&_journal_mode=DELETE")
	if err != nil {
		t.Fatal(err)
	}
	hash := rsidecar.ComputeCoordElevHash(54.7804, 127.1743, 520, "1961_1990")
	_, err = seedDB.Exec(`
		UPDATE "Sample_Env"
		   SET "Zone"='SBS', "SubZone"='dk', "Latitude"=54.7804, "Longitude"=127.1743,
		       "Elevation"=520, "SlopeGradient"=10, "Aspect"=180, "MoistureRegime"='4', "NutrientRegime"='C'
		 WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST('00337' AS BLOB);
		CREATE TABLE "__VPRO_PlotClimate" (
			"PlotNumber" TEXT PRIMARY KEY,
			"CoordElevHash" TEXT NOT NULL,
			"RefPeriod" TEXT NOT NULL,
			"Source" TEXT NOT NULL,
			"MAT" REAL, "MWMT" REAL, "MCMT" REAL, "MAP" REAL, "MSP" REAL, "PAS" REAL, "CMD" REAL,
			"PPT_05" REAL, "PPT_06" REAL, "PPT_07" REAL, "PPT_08" REAL, "PPT_09" REAL,
			"PPT_at" REAL, "PPT_wt" REAL, "DD5" REAL, "NFFD" REAL,
			"ComputedAt" TEXT NOT NULL
		);
		INSERT INTO "__VPRO_PlotClimate" VALUES (
			'00337', ?, '1961_1990', 'bgc_lapse_model',
			3.2, 14.5, -9.8, 520, 240, 180, 210,
			40, 55, 50, 45, 50, 130, 150, 1100, 115, '2026-06-01T00:00:00Z'
		);
	`, hash)
	if err != nil {
		seedDB.Close()
		t.Fatal(err)
	}
	seedDB.Close()

	seededBytes, err := os.ReadFile(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}

	cachedRows, err := rsidecar.GetCachedPlotClimate(ctx, svc, state.ContextID, "1961_1990")
	if err != nil || len(cachedRows) != 1 || cachedRows[0].PlotNumber != "00337" {
		t.Fatalf("GetCachedPlotClimate seeded mismatch: rows=%+v err=%v", cachedRows, err)
	}
	assertUntouched("GetCachedPlotClimate (seeded)", seededBytes)

	hitRes, err := rsidecar.ComputePlotClimateAndDualEdatopic(ctx, svc, state.ContextID, rsidecar.ClimateEdatopicRequest{
		RefPeriod:   "1961_1990",
		PlotNumbers: []string{"00337"},
	}, rsidecar.RuntimeOptions{RscriptPath: "disabled"})
	if err != nil || hitRes.CacheHits != 1 || hitRes.CacheMisses != 0 {
		t.Fatalf("ComputePlotClimateAndDualEdatopic cache-hit failed: res=%+v err=%v", hitRes, err)
	}
	assertUntouched("ComputePlotClimateAndDualEdatopic (100% cache hit)", seededBytes)

	clustRes, err := rsidecar.RunMultivariateClustering(ctx, svc, state.ContextID, rsidecar.ClusteringRequest{
		Method:               "HCLUST",
		Distance:             "chord",
		Linkage:              "average",
		Transform:            "hellinger",
		K:                    3,
		MaterializeCandidate: false,
	})
	if err != nil || len(clustRes.Clusters) != 3 {
		t.Fatalf("RunMultivariateClustering (non-materializing) failed: res=%+v err=%v", clustRes, err)
	}
	assertUntouched("RunMultivariateClustering (MaterializeCandidate=false)", seededBytes)
}

func TestComputePlotClimateAndDualEdatopicReadOnlyContextSkipsWrites(t *testing.T) {
	ctx := context.Background()
	snapDir := t.TempDir()

	support, err := vprocore.InstallDatabaseFamily(snapDir)
	if err != nil {
		t.Fatalf("InstallDatabaseFamily: %v", err)
	}
	projPath := filepath.Join(snapDir, "Sample.db")
	if err := os.WriteFile(projPath, resources.SampleDB, 0o600); err != nil {
		t.Fatalf("write Sample.db: %v", err)
	}

	// Pick two real plots from Sample_Env, give both identical coordinates so plot2 hits normByHash
	// while still being a per-plot cache miss (which would trigger an upsert on a writable context),
	// and seed a third plot with distinct coordinates for live R computation when Rscript is present.
	seedDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rw")+"&_journal_mode=DELETE")
	if err != nil {
		t.Fatal(err)
	}
	rows, err := seedDB.Query(`SELECT CAST("PlotNumber" AS TEXT) FROM "Sample_Env" WHERE typeof("PlotNumber")='text' ORDER BY "PlotNumber" ASC LIMIT 3`)
	if err != nil {
		seedDB.Close()
		t.Fatal(err)
	}
	var plotNums []string
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			rows.Close()
			seedDB.Close()
			t.Fatal(err)
		}
		plotNums = append(plotNums, p)
	}
	rows.Close()
	if len(plotNums) < 3 {
		seedDB.Close()
		t.Fatalf("expected at least 3 plots in Sample_Env, got %d", len(plotNums))
	}

	hashShared := rsidecar.ComputeCoordElevHash(54.7804, 127.1743, 520, "1961_1990")
	_, err = seedDB.Exec(`
		UPDATE "Sample_Env"
		   SET "Zone"='SBS', "SubZone"='dk', "Latitude"=54.7804, "Longitude"=127.1743,
		       "Elevation"=520, "SlopeGradient"=10, "Aspect"=180, "MoistureRegime"='4', "NutrientRegime"='C'
		 WHERE typeof("PlotNumber")='text' AND (CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) OR CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB));

		UPDATE "Sample_Env"
		   SET "Zone"='ICH', "SubZone"='mc', "Latitude"=55.2500, "Longitude"=127.6500,
		       "Elevation"=640, "SlopeGradient"=15, "Aspect"=220, "MoistureRegime"='5', "NutrientRegime"='D'
		 WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB);

		CREATE TABLE "__VPRO_PlotClimate" (
			"PlotNumber" TEXT PRIMARY KEY,
			"CoordElevHash" TEXT NOT NULL,
			"RefPeriod" TEXT NOT NULL,
			"Source" TEXT NOT NULL,
			"MAT" REAL, "MWMT" REAL, "MCMT" REAL, "MAP" REAL, "MSP" REAL, "PAS" REAL, "CMD" REAL,
			"PPT_05" REAL, "PPT_06" REAL, "PPT_07" REAL, "PPT_08" REAL, "PPT_09" REAL,
			"PPT_at" REAL, "PPT_wt" REAL, "DD5" REAL, "NFFD" REAL,
			"ComputedAt" TEXT NOT NULL
		);
		INSERT INTO "__VPRO_PlotClimate" VALUES (
			?, ?, '1961_1990', 'bgc_lapse_model',
			3.2, 14.5, -9.8, 520, 240, 180, 210,
			40, 55, 50, 45, 50, 130, 150, 1100, 115, '2026-06-01T00:00:00Z'
		);
		PRAGMA journal_mode = DELETE;
	`, plotNums[0], plotNums[1], plotNums[2], plotNums[0], hashShared)
	if err != nil {
		seedDB.Close()
		t.Fatalf("seed read-only climate fixture: %v", err)
	}
	if err := seedDB.Close(); err != nil {
		t.Fatal(err)
	}
	_ = os.Remove(projPath + "-wal")
	_ = os.Remove(projPath + "-shm")

	// Finalize support DBs in DELETE mode as well so immutable=true is clean.
	for _, p := range support {
		sdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_journal_mode=DELETE")
		if err != nil {
			t.Fatal(err)
		}
		_, _ = sdb.Exec(`PRAGMA journal_mode = DELETE;`)
		_ = sdb.Close()
		_ = os.Remove(p + "-wal")
		_ = os.Remove(p + "-shm")
	}

	beforeBytes, err := os.ReadFile(projPath)
	if err != nil {
		t.Fatal(err)
	}

	// Lock the project database and directory read-only on non-Windows to emulate a read-only mount.
	if runtime.GOOS != "windows" {
		if err := os.Chmod(projPath, 0o444); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(snapDir, 0o555); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			_ = os.Chmod(snapDir, 0o700)
			_ = os.Chmod(projPath, 0o600)
		})
	}

	pool, err := vprocore.NewReadOnlyContextPool(vprocore.SnapshotCatalog{
		Generation:   "climate-ro-1",
		RootDir:      snapDir,
		SupportPaths: support,
		Immutable:    true,
		Datasets: []vprocore.SnapshotDataset{
			{
				ID:          "sample",
				Label:       "Sample",
				Project:     "Sample",
				ProjectPath: projPath,
			},
		},
	})
	if err != nil {
		t.Fatalf("NewReadOnlyContextPool: %v", err)
	}
	defer pool.Close()

	lease, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample"}, nil)
	if err != nil {
		t.Fatalf("pool.Acquire: %v", err)
	}
	defer lease.Release()

	// 1. Pre-populated cache hit (plot 0) + per-plot miss reusing normByHash (plot 1):
	//    Must succeed cleanly with zero SQLite writes even though cacheMisses == 1!
	res, err := rsidecar.ComputePlotClimateAndDualEdatopic(ctx, lease.Context, lease.ContextID, rsidecar.ClimateEdatopicRequest{
		RefPeriod:   "1961_1990",
		PlotNumbers: []string{plotNums[0], plotNums[1]},
	}, rsidecar.RuntimeOptions{RscriptPath: "disabled"})
	if err != nil {
		t.Fatalf("ComputePlotClimateAndDualEdatopic on read-only context failed: %v", err)
	}
	if res.CacheHits != 1 || res.CacheMisses != 1 || len(res.Plots) != 2 {
		t.Fatalf("unexpected read-only climate counts: hits=%d misses=%d plots=%d", res.CacheHits, res.CacheMisses, len(res.Plots))
	}
	if res.OverallRelative.TotalPlots != 2 || res.OverallActual.TotalPlots != 2 {
		t.Fatalf("expected dual edatopic grids with 2 plots, got rel=%d act=%d", res.OverallRelative.TotalPlots, res.OverallActual.TotalPlots)
	}

	// 2. When Rscript is available in this environment, verify live uncached computation on plot 2
	//    also succeeds cleanly on the read-only/immutable snapshot with zero DB writes!
	rt, rtErr := rsidecar.DetectRRuntime(ctx, rsidecar.RuntimeOptions{})
	if rtErr == nil && rt.Available {
		liveRes, err := rsidecar.ComputePlotClimateAndDualEdatopic(ctx, lease.Context, lease.ContextID, rsidecar.ClimateEdatopicRequest{
			RefPeriod:         "1961_1990",
			PlotNumbers:       []string{plotNums[0], plotNums[2]},
			ForceOfflineModel: true,
		})
		if err != nil {
			t.Fatalf("live ComputePlotClimateAndDualEdatopic on read-only immutable context failed: %v", err)
		}
		if liveRes.CacheHits != 1 || liveRes.CacheMisses != 1 || len(liveRes.Plots) != 2 {
			t.Fatalf("unexpected live read-only climate counts: hits=%d misses=%d plots=%d", liveRes.CacheHits, liveRes.CacheMisses, len(liveRes.Plots))
		}
	}

	// 3. Materializing clustering on a read-only context must fail closed with ErrReadOnlyContext.
	if _, err := rsidecar.RunMultivariateClustering(ctx, lease.Context, lease.ContextID, rsidecar.ClusteringRequest{
		Method:               "HCLUST",
		Distance:             "chord",
		Linkage:              "average",
		Transform:            "hellinger",
		K:                    2,
		MaterializeCandidate: true,
	}); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("expected ErrReadOnlyContext when MaterializeCandidate=true on read-only context, got %v", err)
	}

	// 4. Verify Sample.db bytes remain 100% identical, no WAL/SHM created, and __VPRO_PlotClimate still has only 1 row.
	afterBytes, err := os.ReadFile(projPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(beforeBytes, afterBytes) {
		t.Fatalf("read-only ComputePlotClimateAndDualEdatopic mutated Sample.db bytes on disk")
	}
	if _, err := os.Stat(projPath + "-wal"); !os.IsNotExist(err) {
		t.Fatalf("unexpected WAL file created on read-only snapshot")
	}
	cachedAfter, err := rsidecar.GetCachedPlotClimate(ctx, lease.Context, lease.ContextID, "1961_1990")
	if err != nil {
		t.Fatalf("GetCachedPlotClimate after read-only compute: %v", err)
	}
	if len(cachedAfter) != 1 || cachedAfter[0].PlotNumber != plotNums[0] {
		t.Fatalf("expected __VPRO_PlotClimate to retain only pre-populated plot %q, got %+v", plotNums[0], cachedAfter)
	}
}
