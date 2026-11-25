package vprocore_test

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
)

func prepareReadOnlySnapshotFixture(t *testing.T, dirName string) (dir string, projectPath string, support map[string]string) {
	t.Helper()
	base := t.TempDir()
	dir = filepath.Join(base, dirName)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}

	support, err := vprocore.InstallDatabaseFamily(dir)
	if err != nil {
		t.Fatalf("InstallDatabaseFamily: %v", err)
	}

	projectPath = filepath.Join(dir, "Sample.db")
	if err := os.WriteFile(projectPath, resources.SampleDB, 0o600); err != nil {
		t.Fatalf("write Sample.db: %v", err)
	}

	// Ensure Sample.db has an authorized SU table and Hierarchy table and is finalized in DELETE mode.
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projectPath, "rw")+"&_journal_mode=DELETE")
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS "TestUnit_SU" (
			"PlotNumber" TEXT,
			"SiteUnit" TEXT
		);
		INSERT INTO "TestUnit_SU" ("PlotNumber", "SiteUnit")
		SELECT "PlotNumber", 'SBSdk/01' FROM "Sample_Env" LIMIT 3;

		CREATE TABLE IF NOT EXISTS "TestTree_Hierarchy" (
			"ID" INTEGER PRIMARY KEY,
			"Name" TEXT,
			"Parent" INTEGER,
			"Level" INTEGER
		);
		INSERT INTO "TestTree_Hierarchy" ("ID", "Name", "Parent", "Level")
		VALUES (1, 'SBSdk', NULL, 1), (2, 'SBSdk/01', 1, 2);

		PRAGMA journal_mode = DELETE;
	`)
	if err != nil {
		_ = db.Close()
		t.Fatalf("seed Sample.db SU/Hierarchy: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	_ = os.Remove(projectPath + "-wal")
	_ = os.Remove(projectPath + "-shm")

	// Ensure all support DBs are in DELETE journal mode with no WAL sidecars.
	for role, p := range support {
		sdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_journal_mode=DELETE")
		if err != nil {
			t.Fatalf("open support %s: %v", role, err)
		}
		if role == "VPro64" {
			_, _ = sdb.Exec(`CREATE TABLE IF NOT EXISTS "USysUserLog" ("User" TEXT, "InTime" TEXT, "OutTime" TEXT, "LocalMachine" TEXT)`)
		}
		_, _ = sdb.Exec(`PRAGMA journal_mode = DELETE;`)
		if err := sdb.Close(); err != nil {
			t.Fatalf("close support %s: %v", role, err)
		}
		_ = os.Remove(p + "-wal")
		_ = os.Remove(p + "-shm")
	}

	return dir, projectPath, support
}

func TestInMemoryDesktopConfigIsolationAndNoDiskWrites(t *testing.T) {
	ctx := context.Background()

	// 1. Default in-memory config never touches disk.
	cfg, err := vprocore.NewInMemoryDesktopConfig(nil)
	if err != nil {
		t.Fatalf("NewInMemoryDesktopConfig(nil): %v", err)
	}
	if !cfg.IsMemoryOnly() {
		t.Fatalf("expected IsMemoryOnly() == true")
	}
	if cfg.Path != "" {
		t.Fatalf("expected empty disk Path on in-memory config, got %q", cfg.Path)
	}

	// Update report options and verify Snapshot reflects them.
	update, err := cfg.CompareAndSetReportStrings(ctx, "test report", []vprocore.ReportStringPreferenceChange{
		{Key: "GoogleEarthDescField", Expected: "Zone", Proposed: "SubZone"},
	})
	if err != nil {
		// Read current expected value first in case default differs.
		snap, snapErr := cfg.Snapshot()
		if snapErr != nil {
			t.Fatalf("Snapshot: %v", snapErr)
		}
		cur, curErr := vprocore.ConfigString(snap, "ReportOptions", "GoogleEarthDescField")
		if curErr != nil {
			t.Fatalf("ConfigString: %v", curErr)
		}
		update, err = cfg.CompareAndSetReportStrings(ctx, "test report", []vprocore.ReportStringPreferenceChange{
			{Key: "GoogleEarthDescField", Expected: cur, Proposed: "SiteSeries"},
		})
		if err != nil {
			t.Fatalf("CompareAndSetReportStrings failed: %v", err)
		}
	}
	if !update.Changed || !update.Committed {
		t.Fatalf("expected in-memory CAS update to commit: %+v", update)
	}

	// 2. CloneInMemory creates isolated per-session configs.
	cloneA, err := cfg.CloneInMemory()
	if err != nil {
		t.Fatalf("CloneInMemory A: %v", err)
	}
	cloneB, err := cfg.CloneInMemory()
	if err != nil {
		t.Fatalf("CloneInMemory B: %v", err)
	}
	if err := cloneA.Update("Current", map[string]any{"CoordMethod": 2}); err != nil {
		t.Fatalf("cloneA Update: %v", err)
	}
	if err := cloneB.Update("Current", map[string]any{"CoordMethod": 3}); err != nil {
		t.Fatalf("cloneB Update: %v", err)
	}
	modeOrig, err := cfg.CoordinateMode()
	if err != nil {
		t.Fatal(err)
	}
	modeA, err := cloneA.CoordinateMode()
	if err != nil {
		t.Fatal(err)
	}
	modeB, err := cloneB.CoordinateMode()
	if err != nil {
		t.Fatal(err)
	}
	if modeOrig != vprocore.CoordinateModeDD || modeA != vprocore.CoordinateModeDM || modeB != vprocore.CoordinateModeDMS {
		t.Fatalf("session isolation broken: orig=%q A=%q B=%q", modeOrig, modeA, modeB)
	}

	// 3. Cloning a disk-backed DesktopConfig produces an in-memory clone that never writes disk.
	diskRoot := t.TempDir()
	diskCfg, err := vprocore.OpenDesktopConfig(diskRoot, diskRoot)
	if err != nil {
		t.Fatalf("OpenDesktopConfig: %v", err)
	}
	if diskCfg.IsMemoryOnly() {
		t.Fatalf("expected disk-backed DesktopConfig IsMemoryOnly() == false")
	}
	beforeDisk, err := os.ReadFile(diskCfg.Path)
	if err != nil {
		t.Fatal(err)
	}
	diskClone, err := diskCfg.CloneInMemory()
	if err != nil {
		t.Fatalf("diskCfg.CloneInMemory: %v", err)
	}
	if !diskClone.IsMemoryOnly() || diskClone.Path != "" {
		t.Fatalf("expected memory-only clone without disk Path")
	}
	if err := diskClone.Update("Current", map[string]any{"CoordMethod": 3}); err != nil {
		t.Fatalf("diskClone.Update: %v", err)
	}
	afterDisk, err := os.ReadFile(diskCfg.Path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(beforeDisk, afterDisk) {
		t.Fatalf("mutating in-memory clone modified disk config.yml")
	}

	// 4. Invalid YAML is rejected.
	if _, err := vprocore.NewInMemoryDesktopConfig([]byte("Current:\n  CoordMethod: 999\n")); err == nil {
		t.Fatalf("expected invalid YAML to fail ValidateDesktopConfig")
	}
}

func TestReadOnlySQLiteContextGuardsPrewarmAndImmutableURI(t *testing.T) {
	ctx := context.Background()

	// Verify net/url escaping is preserved with &immutable=1.
	uri := vprocore.SqliteReadOnlyFileURI("/tmp/dir#1/bec?v=2 name.db", true)
	if !strings.Contains(uri, "%23") || !strings.Contains(uri, "%3F") || !strings.Contains(uri, "%20") {
		t.Fatalf("expected net/url percent-escaping in URI, got %q", uri)
	}
	if !strings.Contains(uri, "mode=ro") || !strings.HasSuffix(uri, "&immutable=1") {
		t.Fatalf("expected mode=ro and &immutable=1 in URI, got %q", uri)
	}
	uriNonImm := vprocore.SqliteReadOnlyFileURI("/tmp/dir#1/sample.db", false)
	if strings.Contains(uriNonImm, "immutable=1") {
		t.Fatalf("unexpected immutable=1 when immutable=false: %q", uriNonImm)
	}

	// Place databases inside a directory with '#' and spaces to test URI escaping end-to-end.
	dir, projectPath, support := prepareReadOnlySnapshotFixture(t, "snap #1 query?test")

	beforeProject, err := os.ReadFile(projectPath)
	if err != nil {
		t.Fatal(err)
	}
	beforeVPro64, err := os.ReadFile(support["VPro64"])
	if err != nil {
		t.Fatal(err)
	}

	// Lock files and directory read-only on non-Windows to emulate a read-only container mount.
	if runtime.GOOS != "windows" {
		if err := os.Chmod(projectPath, 0o444); err != nil {
			t.Fatal(err)
		}
		for _, p := range support {
			if err := os.Chmod(p, 0o444); err != nil {
				t.Fatal(err)
			}
		}
		familyDir := filepath.Dir(support["VPro64"])
		if err := os.Chmod(familyDir, 0o555); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(dir, 0o555); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			_ = os.Chmod(dir, 0o700)
			_ = os.Chmod(familyDir, 0o700)
			_ = os.Chmod(projectPath, 0o600)
			for _, p := range support {
				_ = os.Chmod(p, 0o600)
			}
		})
	}

	sel := vprocore.DesktopSelection{
		Project:       "Sample",
		ProjectPath:   projectPath,
		SU:            "TestUnit",
		SUPath:        projectPath,
		Hierarchy:     "TestTree",
		HierarchyPath: projectPath,
	}
	sc, err := vprocore.NewReadOnlySQLiteContext(ctx, sel, support, nil, true)
	if err != nil {
		t.Fatalf("NewReadOnlySQLiteContext(immutable=true): %v", err)
	}
	defer sc.Close()

	if !sc.ReadOnly || !sc.Immutable {
		t.Fatalf("expected ReadOnly=true and Immutable=true, got ReadOnly=%v Immutable=%v", sc.ReadOnly, sc.Immutable)
	}
	if sc.ProjectReadDB == nil {
		t.Fatalf("expected pre-warmed ProjectReadDB")
	}

	// Verify pre-warmed headerCaps and childCaps work even with a nil HeaderDB (pure cache hit!).
	hCaps, err := sc.CachedHeaderCapabilities(nil, "Sample")
	if err != nil || !hCaps["plotNumber"] {
		t.Fatalf("expected pre-warmed headerCaps cache hit, got caps=%v err=%v", hCaps, err)
	}
	for _, kind := range []string{"Veg", "Humus", "Mineral", "Other"} {
		cCaps, err := sc.CachedChildCapabilities(nil, "Sample", kind)
		if err != nil || !cCaps["id"] || !cCaps["plotnumber"] {
			t.Fatalf("expected pre-warmed childCaps[%s] cache hit, got caps=%v err=%v", kind, cCaps, err)
		}
	}

	// Verify canonical temp views work in read snapshot.
	var envCount, suCount, hierCount int
	if err := sc.WithReadSnapshot(ctx, func(tx *sql.Tx) error {
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM USysEnv`).Scan(&envCount); err != nil {
			return err
		}
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM USysSU`).Scan(&suCount); err != nil {
			return err
		}
		return tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM USysHierarchy`).Scan(&hierCount)
	}); err != nil {
		t.Fatalf("read snapshot on immutable context: %v", err)
	}
	if envCount != 3 || suCount != 3 || hierCount != 2 {
		t.Fatalf("unexpected view counts env=%d su=%d hier=%d", envCount, suCount, hierCount)
	}

	// Verify ALL write paths fail closed with ErrReadOnlyContext.
	if _, err := sc.ProjectDatabase(ctx); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("ProjectDatabase expected ErrReadOnlyContext, got %v", err)
	}
	if err := sc.WithImmediateWriteTx(ctx, func(*vprocore.WriteTx) error { return nil }); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("WithImmediateWriteTx expected ErrReadOnlyContext, got %v", err)
	}
	if err := sc.WithMetadataWriter(ctx, func(*sql.Conn) error { return nil }); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("WithMetadataWriter expected ErrReadOnlyContext, got %v", err)
	}
	if err := sc.WithSelectedFileWriter(ctx, "project", func() error { return nil }, func(*sql.Conn) error { return nil }); !errors.Is(err, vprocore.ErrReadOnlyContext) {
		t.Fatalf("WithSelectedFileWriter expected ErrReadOnlyContext, got %v", err)
	}

	// Verify StartUserLogSession / RotateUserLogSession / EndUserLogSession cleanly no-op.
	if err := sc.StartUserLogSession(ctx, "WebGuest"); err != nil {
		t.Fatalf("StartUserLogSession should no-op on ReadOnly, got %v", err)
	}
	sc.RotateUserLogSession(ctx, "OtherGuest")
	if err := sc.EndUserLogSession(); err != nil {
		t.Fatalf("EndUserLogSession should no-op on ReadOnly, got %v", err)
	}

	// Verify disk files remained byte-identical and no WAL/SHM sidecars were created.
	afterProject, err := os.ReadFile(projectPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(beforeProject, afterProject) {
		t.Fatalf("Sample.db bytes changed during read-only operations")
	}
	afterVPro64, err := os.ReadFile(support["VPro64"])
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(beforeVPro64, afterVPro64) {
		t.Fatalf("VPro64.db bytes changed during read-only operations")
	}
	if _, err := os.Stat(projectPath + "-wal"); !os.IsNotExist(err) {
		t.Fatalf("unexpected WAL file created on read-only project")
	}
}

func TestEncodeDecodeWebContextID(t *testing.T) {
	id := vprocore.EncodeWebContextID("snap-2026-11-25/rev#1", "bec:master/v13", "TestUnit", "TestTree")
	gen, ds, su, hier, err := vprocore.DecodeWebContextID(id)
	if err != nil {
		t.Fatalf("DecodeWebContextID: %v", err)
	}
	if gen != "snap-2026-11-25/rev#1" || ds != "bec:master/v13" || su != "TestUnit" || hier != "TestTree" {
		t.Fatalf("round-trip mismatch: gen=%q ds=%q su=%q hier=%q", gen, ds, su, hier)
	}

	// Empty SU and Hierarchy normalize to "None".
	idNorm := vprocore.EncodeWebContextID("g1", "ds1", "", "")
	if idNorm != vprocore.EncodeWebContextID("g1", "ds1", "None", "None") {
		t.Fatalf("empty SU/Hierarchy did not normalize identically")
	}
	_, _, su, hier, err = vprocore.DecodeWebContextID(idNorm)
	if err != nil || su != "None" || hier != "None" {
		t.Fatalf("normalized decode mismatch: su=%q hier=%q err=%v", su, hier, err)
	}

	// Invalid tokens fail closed.
	for _, bad := range []string{
		"",
		"deadbeef0123456789abcdef01234567",
		"vproweb1:not-valid-base64!!!",
		vprocore.EncodeWebContextID("", "ds1", "None", "None"),
		vprocore.EncodeWebContextID("g1", "", "None", "None"),
		vprocore.EncodeWebContextID("g1", "ds1", "bad su!", "None"),
		vprocore.EncodeWebContextID("g1", "ds1", "None", "123bad"),
		"vproweb1:" + strings.Repeat("A", 3000),
	} {
		if _, _, _, _, err := vprocore.DecodeWebContextID(bad); err == nil {
			t.Fatalf("expected DecodeWebContextID(%q) to fail", bad)
		}
	}
}

func TestReadOnlyContextPoolConcurrencyLRUAndReload(t *testing.T) {
	ctx := context.Background()
	dir1, proj1, support1 := prepareReadOnlySnapshotFixture(t, "gen1")
	dir2, proj2, support2 := prepareReadOnlySnapshotFixture(t, "gen2")

	before1, err := os.ReadFile(proj1)
	if err != nil {
		t.Fatal(err)
	}

	cat1 := vprocore.SnapshotCatalog{
		Generation:   "gen-1",
		SnapshotID:   "gen-1",
		Redacted:     true,
		RootDir:      dir1,
		SupportPaths: support1,
		Immutable:    true,
		Datasets: []vprocore.SnapshotDataset{
			{
				ID:          "sample",
				Label:       "Sample Snapshot",
				Project:     "Sample",
				ProjectPath: proj1,
			},
		},
	}

	pool, err := vprocore.NewReadOnlyContextPool(cat1, vprocore.ReadOnlyPoolOptions{
		SlotsPerKey: 4,
		MaxPools:    2,
	})
	if err != nil {
		t.Fatalf("NewReadOnlyContextPool: %v", err)
	}
	defer pool.Close()

	// 1. Read-only SU & Hierarchy discovery.
	sus, hiers, err := pool.DiscoverDatasetSelections(ctx, "sample")
	if err != nil {
		t.Fatalf("DiscoverDatasetSelections: %v", err)
	}
	foundTestUnit := false
	for _, su := range sus {
		if !su.Compatible {
			t.Fatalf("unexpected incompatible SU returned: %+v", su)
		}
		if su.Name == "TestUnit" {
			foundTestUnit = true
		}
	}
	if !foundTestUnit {
		t.Fatalf("expected TestUnit in discovered SUs, got: %+v", sus)
	}
	foundTestTree := false
	for _, h := range hiers {
		if !h.Compatible {
			t.Fatalf("unexpected incompatible Hierarchy returned: %+v", h)
		}
		if h.Name == "TestTree" {
			foundTestTree = true
		}
	}
	if !foundTestTree {
		t.Fatalf("expected TestTree in discovered Hierarchies, got: %+v", hiers)
	}

	// 2. Reject disk-backed DesktopConfig cleanly.
	diskCfg, err := vprocore.OpenDesktopConfig(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample"}, diskCfg); err == nil {
		t.Fatalf("expected Acquire to reject disk-backed DesktopConfig")
	}

	// 3. True parallel execution on the SAME SelectionKey across 4 independent slots
	//    (if serialized on one global mutex/slot, the barrier would deadlock).
	basePrefs, err := vprocore.NewInMemoryDesktopConfig(nil)
	if err != nil {
		t.Fatal(err)
	}
	const workers = 4
	allAcquired := make(chan struct{})
	var acquiredCount int
	var barrierMu sync.Mutex
	var wg sync.WaitGroup
	errCh := make(chan error, workers)
	leases := make([]*vprocore.ReadOnlyLease, workers)

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			sessionPrefs, err := basePrefs.CloneInMemory()
			if err != nil {
				errCh <- err
				return
			}
			lease, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample", SU: "None", Hierarchy: "None"}, sessionPrefs)
			if err != nil {
				errCh <- err
				return
			}
			leases[idx] = lease

			// Execute a real read while holding the slot.
			page, err := lease.Context.Projects.ListPlots(ctx, 0, 5)
			if err != nil || page.Total == 0 {
				errCh <- errors.New("ListPlots failed on leased read-only context")
				return
			}
			if _, err := lease.Context.GetPlot(ctx, lease.ContextID, page.Plots[0].PlotNumber); err != nil {
				errCh <- err
				return
			}
			// Verify mutations fail closed on leased ContextService too.
			if err := lease.Context.CreatePlot(lease.ContextID, vprocore.FS882Header{PlotNumber: "NEW001"}); !errors.Is(err, vprocore.ErrReadOnlyContext) {
				errCh <- errors.New("CreatePlot did not fail with ErrReadOnlyContext")
				return
			}
			// Mutate isolated session preference without affecting other workers.
			coordMethod := (idx % 3) + 1
			if err := lease.Context.Projects.Preferences.Update("Current", map[string]any{"CoordMethod": coordMethod}); err != nil {
				errCh <- err
				return
			}

			barrierMu.Lock()
			acquiredCount++
			if acquiredCount == workers {
				close(allAcquired)
			}
			barrierMu.Unlock()

			select {
			case <-allAcquired:
			case <-time.After(5 * time.Second):
				errCh <- errors.New("timed out waiting for all 4 slots to run concurrently")
				return
			}
		}(i)
	}

	wg.Wait()
	close(errCh)
	for err := range errCh {
		t.Fatalf("concurrent worker error: %v", err)
	}

	// Verify 4 distinct SqliteContext pointers were leased concurrently!
	seenCtx := map[*vprocore.SqliteContext]bool{}
	for _, l := range leases {
		if l == nil {
			t.Fatalf("nil lease")
		}
		seenCtx[l.Context.Projects.Sqlite] = true
	}
	if len(seenCtx) != workers {
		t.Fatalf("expected %d distinct SqliteContext slots, got %d", workers, len(seenCtx))
	}

	// 4. Slot backpressure & ctx cancellation when all 4/4 slots are busy.
	shortCtx, cancel := context.WithTimeout(ctx, 40*time.Millisecond)
	defer cancel()
	if _, err := pool.Acquire(shortCtx, vprocore.SelectionKey{DatasetID: "sample"}, nil); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected DeadlineExceeded when all slots are busy, got %v", err)
	}

	// Release all 4 leases and verify they stay warm as idle slots.
	for _, l := range leases {
		l.Release()
		l.Release() // idempotent
	}
	stats := pool.Stats()
	if stats.ActivePools != 1 || stats.IdleSlots != workers || stats.InFlightLeases != 0 {
		t.Fatalf("unexpected warm stats: %+v", stats)
	}

	// 5. Bounded LRU eviction (MaxPools=2): access 3 distinct SelectionKeys.
	lA, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample", SU: "TestUnit", Hierarchy: "None"}, nil)
	if err != nil {
		t.Fatalf("Acquire SU: %v", err)
	}
	lA.Release()
	lB, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample", SU: "None", Hierarchy: "TestTree"}, nil)
	if err != nil {
		t.Fatalf("Acquire Hierarchy: %v", err)
	}
	lB.Release()

	if st := pool.Stats(); st.ActivePools != 2 {
		t.Fatalf("expected LRU bounded to MaxPools=2, got %+v", st)
	}

	// 6. Atomic Reload(newCatalog) without dropping in-flight reads!
	inFlightLease, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample", SU: "TestUnit", Hierarchy: "TestTree"}, nil)
	if err != nil {
		t.Fatalf("Acquire before reload: %v", err)
	}
	oldContextID := inFlightLease.ContextID

	cat2 := vprocore.SnapshotCatalog{
		Generation:   "gen-2",
		SnapshotID:   "gen-2",
		Redacted:     true,
		RootDir:      dir2,
		SupportPaths: support2,
		Immutable:    true,
		Datasets: []vprocore.SnapshotDataset{
			{
				ID:          "sample",
				Label:       "Sample Snapshot v2",
				Project:     "Sample",
				ProjectPath: proj2,
			},
		},
	}
	if err := pool.Reload(cat2); err != nil {
		t.Fatalf("Reload(cat2): %v", err)
	}
	if pool.Generation() != "gen-2" {
		t.Fatalf("expected generation gen-2 after Reload, got %q", pool.Generation())
	}

	// Old token must be rejected as stale for NEW acquires.
	if _, err := pool.AcquireByContextID(ctx, oldContextID, nil); !errors.Is(err, vprocore.ErrStaleWebContext) {
		t.Fatalf("expected ErrStaleWebContext for gen-1 token after reload, got %v", err)
	}

	// New generation acquires immediately while gen-1 lease is still in flight.
	newLease, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample"}, nil)
	if err != nil {
		t.Fatalf("Acquire gen-2: %v", err)
	}
	if newLease.Generation != "gen-2" {
		t.Fatalf("expected gen-2 lease, got %q", newLease.Generation)
	}
	if _, err := newLease.Context.Projects.ListPlots(ctx, 0, 5); err != nil {
		t.Fatalf("gen-2 ListPlots failed: %v", err)
	}
	// AcquireByContextID with new token succeeds.
	newLeaseByID, err := pool.AcquireByContextID(ctx, newLease.ContextID, nil)
	if err != nil {
		t.Fatalf("AcquireByContextID gen-2: %v", err)
	}
	newLeaseByID.Release()
	newLease.Release()

	// Verify in-flight gen-1 lease STILL completes its read cleanly!
	pageOld, err := inFlightLease.Context.Projects.ListPlots(ctx, 0, 5)
	if err != nil || pageOld.Total != 3 {
		t.Fatalf("in-flight gen-1 read dropped during Reload: page=%+v err=%v", pageOld, err)
	}
	if st := pool.Stats(); st.DrainingPools != 1 {
		t.Fatalf("expected 1 draining pool while gen-1 lease in-flight, got %+v", st)
	}

	// Release gen-1 lease and verify drain completes cleanly.
	inFlightLease.Release()
	drainCtx, drainCancel := context.WithTimeout(ctx, 2*time.Second)
	defer drainCancel()
	if err := pool.WaitDrained(drainCtx); err != nil {
		t.Fatalf("WaitDrained: %v", err)
	}
	if st := pool.Stats(); st.DrainingPools != 0 {
		t.Fatalf("expected 0 draining pools after release, got %+v", st)
	}

	// Verify gen-1 project file remained 100% byte-identical.
	after1, err := os.ReadFile(proj1)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before1, after1) {
		t.Fatalf("gen-1 Sample.db mutated during pool lifecycle")
	}

	if err := pool.Close(); err != nil {
		t.Fatalf("pool.Close: %v", err)
	}
	if _, err := pool.Acquire(ctx, vprocore.SelectionKey{DatasetID: "sample"}, nil); !errors.Is(err, vprocore.ErrPoolClosed) {
		t.Fatalf("expected ErrPoolClosed after Close, got %v", err)
	}
}
