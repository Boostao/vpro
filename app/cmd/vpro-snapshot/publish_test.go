package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
	_ "github.com/mattn/go-sqlite3"
)

func buildSyntheticVLists(t *testing.T, dir, name string, mutate func(db *sql.DB)) string {
	t.Helper()
	seedRoot := t.TempDir()
	seeds, err := vprocore.InstallDatabaseFamily(seedRoot)
	if err != nil {
		t.Fatalf("install embedded seeds: %v", err)
	}
	dst := filepath.Join(dir, name)
	if err := copyFileReadOnly(seeds["VLists"], dst, 0o644); err != nil {
		t.Fatalf("copy VLists seed: %v", err)
	}
	if mutate != nil {
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dst, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatalf("open synthetic VLists.db: %v", err)
		}
		mutate(db)
		if err := db.Close(); err != nil {
			t.Fatalf("close synthetic VLists.db: %v", err)
		}
	}
	return dst
}

func buildPopulatedRedBlueVLists(t *testing.T, dir string) string {
	t.Helper()
	return buildSyntheticVLists(t, dir, "VLists.db", func(db *sql.DB) {
		_, err := db.Exec(`
			INSERT INTO "USysSppAttributes" ("Code", "Codetype", "RedBlueList") VALUES
				('RARESPP1',  'U', 'R'),
				('BLUESPP1',  'U', 'Blue'),
				('SYNRARE',   'S', 'R'),
				('NODATASPP', 'U', 'Z'),
				('SECURESPP', 'U', 'Y');
		`)
		if err != nil {
			t.Fatalf("seed USysSppAttributes: %v", err)
		}
	})
}

func buildSyntheticSampleProject(t *testing.T, dir, fileName string, enableWAL bool) string {
	t.Helper()
	dst := filepath.Join(dir, fileName)
	if err := os.WriteFile(dst, resources.SampleDB, 0o644); err != nil {
		t.Fatalf("write Sample.db copy: %v", err)
	}

	dsn := sqlutil.SqliteFileURI(dst, "rw") + "&_busy_timeout=5000"
	if enableWAL {
		dsn += "&_journal_mode=WAL"
	}
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		t.Fatalf("open synthetic Sample.db: %v", err)
	}
	defer db.Close()

	// Set known high-precision coordinates on three plots (including leading-zero '00337').
	stmts := []struct {
		query string
		args  []any
	}{
		{
			// Sensitive plot '00337' (Red-listed species): geographic XCoord/YCoord + UTM + Lat/Lon.
			`UPDATE "Sample_Env"
			 SET "Latitude" = ?, "Longitude" = ?, "UTMEasting" = ?, "UTMNorthing" = ?, "XCoord" = ?, "YCoord" = ?
			 WHERE "PlotNumber" = '00337' AND typeof("PlotNumber") = 'text'`,
			[]any{49.6871, -125.4892, 466721.5, 5441234.8, -125.4892, 49.6871},
		},
		{
			// Sensitive plot '108050' (Blue-listed species): projected UTM XCoord/YCoord + UTM + Lat/Lon.
			`UPDATE "Sample_Env"
			 SET "Latitude" = ?, "Longitude" = ?, "UTMEasting" = ?, "UTMNorthing" = ?, "XCoord" = ?, "YCoord" = ?
			 WHERE "PlotNumber" = '108050' AND typeof("PlotNumber") = 'text'`,
			[]any{59.2999, -132.0983, 518999.9, 6579999.9, 518999.9, 6579999.9},
		},
		{
			// Non-sensitive plot '1976021' (only synonym + Z species): coordinates must remain untouched.
			`UPDATE "Sample_Env"
			 SET "Latitude" = ?, "Longitude" = ?, "UTMEasting" = ?, "UTMNorthing" = ?, "XCoord" = ?, "YCoord" = ?
			 WHERE "PlotNumber" = '1976021' AND typeof("PlotNumber") = 'text'`,
			[]any{55.180557, -124.420997, 412345.6, 6112345.6, -124.420997, 55.180557},
		},
		{
			`INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Layer", "Cover6", "ID") VALUES ('00337', 'rarespp1 ', '6', 5.0, 2144900001)`,
			nil,
		},
		{
			`INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Layer", "Cover6", "ID") VALUES ('108050', 'BLUESPP1', '6', 2.0, 2144900002)`,
			nil,
		},
		{
			`INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Layer", "Cover6", "ID") VALUES ('1976021', 'SYNRARE', '6', 1.0, 2144900003)`,
			nil,
		},
		{
			`INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Layer", "Cover6", "ID") VALUES ('1976021', 'NODATASPP', '6', 3.0, 2144900004)`,
			nil,
		},
		{
			`INSERT INTO "Sample_Audit" ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag", "ID")
			 VALUES ('Sample', 'TestUser', '00337', 'Sample_Env', 'Latitude', '2026-11-25', '49.0', '49.6871', 0, 0, 999999)`,
			nil,
		},
	}
	for _, s := range stmts {
		res, err := db.Exec(s.query, s.args...)
		if err != nil {
			t.Fatalf("seed Sample.db statement failed (%s): %v", s.query, err)
		}
		if n, _ := res.RowsAffected(); n == 0 {
			t.Fatalf("expected statement to affect at least 1 row: %s", s.query)
		}
	}
	return dst
}

func TestBuildFailClosedRedaction(t *testing.T) {
	ctx := context.Background()
	workDir := t.TempDir()
	srcDB := buildSyntheticSampleProject(t, workDir, "Sample.db", false)

	// 1. Bundled VLists.db has 0 Red/Blue rows -> default --redact=true must fail closed.
	outBundled := filepath.Join(workDir, "out-bundled")
	var stdout, stderr bytes.Buffer
	code := run([]string{"build", "--source", srcDB, "--out", outBundled}, &stdout, &stderr)
	if code == 0 {
		t.Fatalf("expected non-zero exit when bundled VLists.db has 0 Red/Blue species; stdout=%s", stdout.String())
	}
	if !strings.Contains(stderr.String(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected fail-closed 0 Red/Blue error, got: %s", stderr.String())
	}
	if _, err := os.Stat(outBundled); !os.IsNotExist(err) {
		t.Fatalf("failed build must not leave output directory behind: %v", err)
	}

	// 2. VLists.db missing USysSppAttributes -> fail closed.
	noAttrVLists := buildSyntheticVLists(t, workDir, "VLists_NoAttr.db", func(db *sql.DB) {
		if _, err := db.Exec(`DROP TABLE "USysSppAttributes"`); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := BuildSnapshot(ctx, BuildOptions{
		Source: srcDB,
		Out:    filepath.Join(workDir, "out-no-attr"),
		VLists: noAttrVLists,
		Redact: true,
	}); err == nil || !strings.Contains(err.Error(), "USysSppAttributes") {
		t.Fatalf("expected missing USysSppAttributes fail-closed error, got: %v", err)
	}

	// 3. VLists.db with only Z/Y/blank/synonym('S') rows -> fail closed.
	zOnlyVLists := buildSyntheticVLists(t, workDir, "VLists_ZOnly.db", func(db *sql.DB) {
		if _, err := db.Exec(`
			DELETE FROM "USysSppAttributes";
			INSERT INTO "USysSppAttributes" ("Code", "Codetype", "RedBlueList") VALUES
				('NODATA', 'U', 'Z'),
				('SAFE',   'U', 'Y'),
				('SYN_R',  'S', 'R'),
				('EMPTY',  'U', '');
		`); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := BuildSnapshot(ctx, BuildOptions{
		Source: srcDB,
		Out:    filepath.Join(workDir, "out-zonly"),
		VLists: zOnlyVLists,
		Redact: true,
	}); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected Z/S-only fail-closed error, got: %v", err)
	}

	// 4. --redact=false WITHOUT --confirm-unredacted -> fail closed.
	stdout.Reset()
	stderr.Reset()
	code = run([]string{"build", "--source", srcDB, "--out", filepath.Join(workDir, "out-unconfirmed"), "--redact=false"}, &stdout, &stderr)
	if code == 0 {
		t.Fatalf("expected non-zero exit when --redact=false passed without --confirm-unredacted")
	}
	if !strings.Contains(stderr.String(), "--confirm-unredacted") {
		t.Fatalf("expected error mentioning --confirm-unredacted, got: %s", stderr.String())
	}

	// 5. --redact=false WITH --confirm-unredacted -> succeeds, coordinates preserved, audit still stripped.
	outUnredacted := filepath.Join(workDir, "out-unredacted")
	stdout.Reset()
	stderr.Reset()
	code = run([]string{
		"build",
		"--source", srcDB,
		"--out", outUnredacted,
		"--snapshot-id", "unredacted-dev-1",
		"--redact=false",
		"--confirm-unredacted",
	}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected unredacted build with --confirm-unredacted to succeed, stderr=%s", stderr.String())
	}
	manifest, err := ReadManifest(filepath.Join(outUnredacted, ManifestFilename))
	if err != nil {
		t.Fatalf("read unredacted manifest: %v", err)
	}
	if manifest.Redacted || manifest.RedactedPlotCount != 0 {
		t.Fatalf("expected Redacted=false, RedactedPlotCount=0; got %+v", manifest)
	}

	// Confirm coordinates on '00337' were NOT truncated when unredacted.
	pubDB, err := openSQLiteReadOnly(ctx, filepath.Join(outUnredacted, "projects", "Sample.db"), true)
	if err != nil {
		t.Fatal(err)
	}
	defer pubDB.Close()
	var lat, lon float64
	if err := pubDB.QueryRow(`SELECT "Latitude", "Longitude" FROM "Sample_Env" WHERE "PlotNumber" = '00337'`).Scan(&lat, &lon); err != nil {
		t.Fatal(err)
	}
	if math.Abs(lat-49.6871) > 1e-9 || math.Abs(lon-(-125.4892)) > 1e-9 {
		t.Fatalf("expected unredacted coordinates preserved, got lat=%v lon=%v", lat, lon)
	}
	var auditCount int
	if err := pubDB.QueryRow(`SELECT COUNT(*) FROM "Sample_Audit"`).Scan(&auditCount); err != nil {
		t.Fatal(err)
	}
	if auditCount != 0 {
		t.Fatalf("expected Sample_Audit stripped to 0 rows even in unredacted build, got %d", auditCount)
	}
	if _, err := VerifyBundle(ctx, outUnredacted); err != nil {
		t.Fatalf("verify unredacted bundle failed: %v", err)
	}
}

func TestBuildRedactTruncateAuditStripAndNoSourceMutation(t *testing.T) {
	ctx := context.Background()
	workDir := t.TempDir()
	// Use WAL mode on source DB to confirm WAL frames are safely staged/checkpointed without mutating source.
	srcDB := buildSyntheticSampleProject(t, workDir, "Sample.db", true)
	vlistsDB := buildPopulatedRedBlueVLists(t, workDir)

	srcHashBefore, _, err := ComputeFileSHA256(srcDB)
	if err != nil {
		t.Fatal(err)
	}
	vlistsHashBefore, _, err := ComputeFileSHA256(vlistsDB)
	if err != nil {
		t.Fatal(err)
	}

	outDir := filepath.Join(workDir, "bundle-redacted")
	var stdout, stderr bytes.Buffer
	code := run([]string{
		"build",
		"--source", srcDB,
		"--out", outDir,
		"--vlists", vlistsDB,
		"--snapshot-id", "becmaster-2026-11",
		"--label", "Sample BECMaster Snapshot",
		"--redact=true",
	}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("vpro-snapshot build failed (exit %d): %s", code, stderr.String())
	}

	// Verify source files were NEVER mutated.
	srcHashAfter, _, err := ComputeFileSHA256(srcDB)
	if err != nil {
		t.Fatal(err)
	}
	vlistsHashAfter, _, err := ComputeFileSHA256(vlistsDB)
	if err != nil {
		t.Fatal(err)
	}
	if srcHashBefore != srcHashAfter {
		t.Fatalf("source project DB was mutated! before=%s after=%s", srcHashBefore, srcHashAfter)
	}
	if vlistsHashBefore != vlistsHashAfter {
		t.Fatalf("source VLists.db was mutated! before=%s after=%s", vlistsHashBefore, vlistsHashAfter)
	}

	// Validate stdout JSON manifest matches on-disk manifest.json.
	var printed Manifest
	if err := json.Unmarshal(stdout.Bytes(), &printed); err != nil {
		t.Fatalf("decode build stdout manifest JSON: %v", err)
	}
	manifest, err := ReadManifest(filepath.Join(outDir, ManifestFilename))
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	if manifest.SchemaVersion != 1 || manifest.SnapshotID != "becmaster-2026-11" || !manifest.Redacted || manifest.RedactedPlotCount != 2 {
		t.Fatalf("unexpected manifest header: %+v", manifest)
	}
	if manifest.Standards.RedBlueSpeciesCount != 2 {
		t.Fatalf("expected RedBlueSpeciesCount=2 (RARESPP1, BLUESPP1; excluding synonym SYNRARE), got %d", manifest.Standards.RedBlueSpeciesCount)
	}
	if len(manifest.SupportFiles) != 5 {
		t.Fatalf("expected 5 supportFiles, got %d", len(manifest.SupportFiles))
	}
	if len(manifest.Datasets) != 1 {
		t.Fatalf("expected 1 dataset, got %d", len(manifest.Datasets))
	}
	ds := manifest.Datasets[0]
	if ds.ID != "sample" || ds.Label != "Sample BECMaster Snapshot" || ds.Project != "Sample" || ds.PlotCount != 52 || ds.RedactedPlotCount != 2 {
		t.Fatalf("unexpected dataset metadata: %+v", ds)
	}
	if len(ds.SUs) != 1 || ds.SUs[0].Name != "Sample" || !ds.SUs[0].Compatible {
		t.Fatalf("expected compatible Sample SU, got %+v", ds.SUs)
	}
	if len(ds.Hierarchies) != 1 || ds.Hierarchies[0].Name != "Sample" || !ds.Hierarchies[0].Compatible {
		t.Fatalf("expected compatible Sample Hierarchy, got %+v", ds.Hierarchies)
	}

	// Verify exact coordinate truncation on '00337' (geographic), '108050' (projected), and untouched '1976021'.
	pubPath := filepath.Join(outDir, filepath.FromSlash(ds.File))
	pubDB, err := openSQLiteReadOnly(ctx, pubPath, true)
	if err != nil {
		t.Fatal(err)
	}
	defer pubDB.Close()

	checkCoords := func(plot string, wantLat, wantLon, wantE, wantN, wantX, wantY float64) {
		t.Helper()
		var lat, lon, utmE, utmN, xc, yc float64
		err := pubDB.QueryRow(
			`SELECT "Latitude", "Longitude", "UTMEasting", "UTMNorthing", "XCoord", "YCoord"
			 FROM "Sample_Env"
			 WHERE "PlotNumber" = ? AND typeof("PlotNumber") = 'text'`, plot,
		).Scan(&lat, &lon, &utmE, &utmN, &xc, &yc)
		if err != nil {
			t.Fatalf("query coords for plot %q: %v", plot, err)
		}
		for _, pair := range []struct {
			col       string
			got, want float64
		}{
			{"Latitude", lat, wantLat},
			{"Longitude", lon, wantLon},
			{"UTMEasting", utmE, wantE},
			{"UTMNorthing", utmN, wantN},
			{"XCoord", xc, wantX},
			{"YCoord", yc, wantY},
		} {
			if math.Abs(pair.got-pair.want) > 1e-9 {
				t.Fatalf("plot %q %s = %v, want %v", plot, pair.col, pair.got, pair.want)
			}
		}
	}

	// '00337' Red-listed -> 0.1 deg Lat/Lon/XCoord/YCoord, 10,000 m UTM
	checkCoords("00337", 49.6, -125.4, 460000.0, 5440000.0, -125.4, 49.6)
	// '108050' Blue-listed -> 0.1 deg Lat/Lon, 10,000 m UTM & projected XCoord/YCoord
	checkCoords("108050", 59.2, -132.0, 510000.0, 6570000.0, 510000.0, 6570000.0)
	// '1976021' non-sensitive (only synonym + Z) -> untouched exact coordinates
	checkCoords("1976021", 55.180557, -124.420997, 412345.6, 6112345.6, -124.420997, 55.180557)

	// Verify Sample_Audit exists with 0 rows.
	var auditRows int
	if err := pubDB.QueryRow(`SELECT COUNT(*) FROM "Sample_Audit"`).Scan(&auditRows); err != nil {
		t.Fatalf("Sample_Audit table must remain intact: %v", err)
	}
	if auditRows != 0 {
		t.Fatalf("expected 0 rows in Sample_Audit, got %d", auditRows)
	}

	// Verify CLI verify subcommand passes cleanly.
	stdout.Reset()
	stderr.Reset()
	code = run([]string{"verify", "--bundle", outDir}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("vpro-snapshot verify failed (exit %d): %s", code, stderr.String())
	}
	var vr VerifyResult
	if err := json.Unmarshal(stdout.Bytes(), &vr); err != nil {
		t.Fatalf("decode verify JSON: %v", err)
	}
	if vr.SnapshotID != "becmaster-2026-11" || vr.DatasetCount != 1 || vr.SupportFileCount != 5 || !vr.Redacted || vr.RedactedPlotCount != 2 {
		t.Fatalf("unexpected VerifyResult: %+v", vr)
	}
}

func TestVerifyOn0555ReadOnlyDirectory(t *testing.T) {
	ctx := context.Background()
	workDir := t.TempDir()
	srcDB := buildSyntheticSampleProject(t, workDir, "Sample.db", true)
	vlistsDB := buildPopulatedRedBlueVLists(t, workDir)
	bundleDir := filepath.Join(workDir, "ro-bundle")

	if _, err := BuildSnapshot(ctx, BuildOptions{
		Source:     srcDB,
		Out:        bundleDir,
		VLists:     vlistsDB,
		SnapshotID: "ro-mount-test",
		Redact:     true,
	}); err != nil {
		t.Fatalf("BuildSnapshot: %v", err)
	}

	// Lock down all files to 0444 and all directories to 0555 (simulating a read-only Docker mount).
	var dirs []string
	if err := filepath.WalkDir(bundleDir, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			dirs = append(dirs, p)
			return nil
		}
		return os.Chmod(p, 0o444)
	}); err != nil {
		t.Fatalf("chmod files 0444: %v", err)
	}
	// Chmod deepest directories first so parent remains traversable until last.
	for i := len(dirs) - 1; i >= 0; i-- {
		if err := os.Chmod(dirs[i], 0o555); err != nil {
			t.Fatalf("chmod dir %s 0555: %v", dirs[i], err)
		}
	}
	t.Cleanup(func() {
		for _, d := range dirs {
			_ = os.Chmod(d, 0o755)
		}
		_ = filepath.WalkDir(bundleDir, func(p string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() {
				_ = os.Chmod(p, 0o644)
			}
			return nil
		})
	})

	// VerifyBundle must pass with zero writes on 0555 directories / 0444 files.
	res, err := VerifyBundle(ctx, bundleDir)
	if err != nil {
		t.Fatalf("VerifyBundle on 0555 read-only directory failed: %v", err)
	}
	if res.SnapshotID != "ro-mount-test" || res.RedactedPlotCount != 2 {
		t.Fatalf("unexpected VerifyResult on 0555 bundle: %+v", res)
	}

	// Explicitly confirm mode=ro&immutable=1 query works directly on Sample.db and VLists.db inside 0555 mount.
	for _, rel := range []string{"projects/Sample.db", "database-family/VLists.db"} {
		db, err := openSQLiteReadOnly(ctx, filepath.Join(bundleDir, filepath.FromSlash(rel)), true)
		if err != nil {
			t.Fatalf("open %s with immutable=1 on 0555 dir: %v", rel, err)
		}
		var n int
		if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master`).Scan(&n); err != nil || n == 0 {
			_ = db.Close()
			t.Fatalf("query %s under immutable=1: n=%d err=%v", rel, n, err)
		}
		_ = db.Close()
	}
}

func cloneDirForTamper(t *testing.T, src string) string {
	t.Helper()
	dst := filepath.Join(t.TempDir(), "bundle")
	if err := filepath.WalkDir(src, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		return copyFileReadOnly(p, target, 0o644)
	}); err != nil {
		t.Fatalf("clone bundle dir: %v", err)
	}
	return dst
}

func rehashDatasetInManifest(t *testing.T, bundleDir string) {
	t.Helper()
	mPath := filepath.Join(bundleDir, ManifestFilename)
	m, err := ReadManifest(mPath)
	if err != nil {
		t.Fatalf("ReadManifest: %v", err)
	}
	for i := range m.Datasets {
		abs := filepath.Join(bundleDir, filepath.FromSlash(m.Datasets[i].File))
		sum, size, err := ComputeFileSHA256(abs)
		if err != nil {
			t.Fatalf("rehash dataset: %v", err)
		}
		m.Datasets[i].SHA256 = sum
		m.Datasets[i].SizeBytes = size
	}
	if err := WriteManifest(mPath, m); err != nil {
		t.Fatalf("WriteManifest: %v", err)
	}
}

func TestVerifyFailureModes(t *testing.T) {
	ctx := context.Background()
	workDir := t.TempDir()
	srcDB := buildSyntheticSampleProject(t, workDir, "Sample.db", false)
	vlistsDB := buildPopulatedRedBlueVLists(t, workDir)
	goodBundle := filepath.Join(workDir, "good-bundle")

	if _, err := BuildSnapshot(ctx, BuildOptions{
		Source:     srcDB,
		Out:        goodBundle,
		VLists:     vlistsDB,
		SnapshotID: "verify-fail-cases",
		Redact:     true,
	}); err != nil {
		t.Fatalf("BuildSnapshot: %v", err)
	}

	// Case 1: Tampered byte in project .db -> SHA-256 mismatch.
	t.Run("tampered-sha256", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		p := filepath.Join(b, "projects", "Sample.db")
		data, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		data[len(data)-1] ^= 0xFF
		if err := os.WriteFile(p, data, 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "SHA-256 mismatch") {
			t.Fatalf("expected SHA-256 mismatch error, got: %v", err)
		}
	})

	// Case 2: Stray -wal sidecar file -> rejected.
	t.Run("stray-wal-sidecar", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		if err := os.WriteFile(filepath.Join(b, "projects", "Sample.db-wal"), []byte("wal"), 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "sidecar") {
			t.Fatalf("expected sidecar rejection error, got: %v", err)
		}
	})

	// Case 3: Non-empty Sample_Audit (even after re-hashing manifest.json) -> rejected.
	t.Run("nonzero-audit-rows", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		p := filepath.Join(b, "projects", "Sample.db")
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO "Sample_Audit" ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES ('Sample','Leak','00337','Sample_Env','Zone','2026-11-25','a','b',0,0,1)`); err != nil {
			t.Fatal(err)
		}
		_ = db.Close()
		rehashDatasetInManifest(t, b)
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "Sample_Audit contains 1 rows") {
			t.Fatalf("expected Sample_Audit 0-row violation error, got: %v", err)
		}
	})

	// Case 4: Unredacted coordinate in sensitive plot (even after re-hashing manifest.json) -> rejected.
	t.Run("unredacted-sensitive-coordinate", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		p := filepath.Join(b, "projects", "Sample.db")
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`UPDATE "Sample_Env" SET "Latitude" = 49.6871 WHERE "PlotNumber" = '00337'`); err != nil {
			t.Fatal(err)
		}
		_ = db.Close()
		rehashDatasetInManifest(t, b)
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "unredacted sensitive coordinate") {
			t.Fatalf("expected unredacted coordinate error, got: %v", err)
		}
	})

	// Case 5: Broken VP08 _table_metadata tag (even after re-hashing manifest.json) -> rejected.
	t.Run("broken-vp08-metadata", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		p := filepath.Join(b, "projects", "Sample.db")
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`UPDATE "_table_metadata" SET "description" = 'VP07' WHERE "table_name" = 'Sample_Env'`); err != nil {
			t.Fatal(err)
		}
		_ = db.Close()
		rehashDatasetInManifest(t, b)
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "VP08") {
			t.Fatalf("expected VP08 schema error, got: %v", err)
		}
	})

	// Case 6: Path traversal in manifest.json -> rejected.
	t.Run("path-traversal-manifest", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		mPath := filepath.Join(b, ManifestFilename)
		raw, err := os.ReadFile(mPath)
		if err != nil {
			t.Fatal(err)
		}
		tampered := strings.Replace(string(raw), `"projects/Sample.db"`, `"../escape/Sample.db"`, 1)
		if err := os.WriteFile(mPath, []byte(tampered), 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "escapes bundle root") {
			t.Fatalf("expected path traversal rejection, got: %v", err)
		}
	})

	// Case 7: DB switched to WAL mode (even without leftover -wal/-shm sidecars and re-hashed) -> rejected.
	t.Run("wal-journal-mode", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		p := filepath.Join(b, "projects", "Sample.db")
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(p, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatal(err)
		}
		var mode string
		if err := db.QueryRow(`PRAGMA journal_mode = WAL;`).Scan(&mode); err != nil {
			t.Fatal(err)
		}
		if err := db.Close(); err != nil {
			t.Fatal(err)
		}
		_ = os.Remove(p + "-wal")
		_ = os.Remove(p + "-shm")
		rehashDatasetInManifest(t, b)
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "DELETE rollback mode") {
			t.Fatalf("expected WAL journal header rejection, got: %v", err)
		}
	})

	// Case 8: Redacted manifest paired with emptied VLists USysSppAttributes (re-hashed) -> fails closed.
	t.Run("redacted-manifest-empty-vlists", func(t *testing.T) {
		b := cloneDirForTamper(t, goodBundle)
		vp := filepath.Join(b, "database-family", "VLists.db")
		db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(vp, "rw")+"&_busy_timeout=5000")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`DELETE FROM "USysSppAttributes"`); err != nil {
			t.Fatal(err)
		}
		if err := db.Close(); err != nil {
			t.Fatal(err)
		}
		mPath := filepath.Join(b, ManifestFilename)
		m, err := ReadManifest(mPath)
		if err != nil {
			t.Fatal(err)
		}
		sum, size, err := ComputeFileSHA256(vp)
		if err != nil {
			t.Fatal(err)
		}
		spec := m.SupportFiles["VLists"]
		spec.SHA256 = sum
		spec.SizeBytes = size
		m.SupportFiles["VLists"] = spec
		m.Standards.VListsSHA256 = sum
		if err := WriteManifest(mPath, m); err != nil {
			t.Fatal(err)
		}
		if _, err := VerifyBundle(ctx, b); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
			t.Fatalf("expected fail-closed empty VLists redaction error, got: %v", err)
		}
	})
}

func TestBuildAndVerifySpecialCharPathEscaping(t *testing.T) {
	ctx := context.Background()
	workDir := t.TempDir()
	srcDB := buildSyntheticSampleProject(t, workDir, "Sample #1.db", false)
	vlistsDB := buildPopulatedRedBlueVLists(t, workDir)
	outDir := filepath.Join(workDir, "bundle #1 (ro)")

	manifest, err := BuildSnapshot(ctx, BuildOptions{
		Source:     srcDB,
		Out:        outDir,
		VLists:     vlistsDB,
		SnapshotID: "special-char-path",
		Redact:     true,
	})
	if err != nil {
		t.Fatalf("BuildSnapshot on path containing '#': %v", err)
	}
	if manifest.RedactedPlotCount != 2 {
		t.Fatalf("expected 2 redacted plots, got %d", manifest.RedactedPlotCount)
	}
	if _, err := VerifyBundle(ctx, outDir); err != nil {
		t.Fatalf("VerifyBundle on path containing '#': %v", err)
	}
}

func TestBuildDirectorySourceWithStandaloneHierarchy(t *testing.T) {
	ctx := context.Background()
	srcDir := t.TempDir()
	projectsDir := filepath.Join(srcDir, "projects")
	familyDir := filepath.Join(srcDir, vprocore.DatabaseFamilySubdir)
	if err := os.MkdirAll(projectsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(familyDir, 0o755); err != nil {
		t.Fatal(err)
	}

	_ = buildSyntheticSampleProject(t, projectsDir, "Sample.db", false)
	_ = buildPopulatedRedBlueVLists(t, familyDir)

	// Add a standalone hierarchy-only .db inside projects/
	extraHierPath := filepath.Join(projectsDir, "Province.db")
	hdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extraHierPath, "rwc")+"&_busy_timeout=5000")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := hdb.Exec(`
		CREATE TABLE "Province_Hierarchy" (
			"ID" INTEGER PRIMARY KEY,
			"Name" TEXT NOT NULL,
			"Parent" INTEGER,
			"Level" INTEGER
		);
		CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT);
		INSERT INTO "_table_metadata" VALUES ('Province_Hierarchy', 'VP04');
		INSERT INTO "Province_Hierarchy" VALUES (1, 'BC', NULL, 1), (2, 'CWH', 1, 2);
	`); err != nil {
		t.Fatal(err)
	}
	_ = hdb.Close()

	// Build into an existing empty directory (e.g., Docker volume mount target).
	outDir := t.TempDir()
	manifest, err := BuildSnapshot(ctx, BuildOptions{
		Source:     srcDir,
		Out:        outDir,
		SnapshotID: "dir-source-with-hier",
		Redact:     true,
	})
	if err != nil {
		t.Fatalf("BuildSnapshot(dir): %v", err)
	}
	if len(manifest.Datasets) != 1 {
		t.Fatalf("expected 1 dataset, got %d", len(manifest.Datasets))
	}
	if len(manifest.Datasets[0].Hierarchies) != 2 {
		t.Fatalf("expected 2 hierarchies (Province + Sample), got %+v", manifest.Datasets[0].Hierarchies)
	}
	if manifest.Datasets[0].Hierarchies[0].Name != "Province" || manifest.Datasets[0].Hierarchies[1].Name != "Sample" {
		t.Fatalf("unexpected hierarchies order/names: %+v", manifest.Datasets[0].Hierarchies)
	}
	if _, ok := manifest.AuxiliaryFiles["Province.db"]; !ok {
		t.Fatalf("expected Province.db tracked in manifest.AuxiliaryFiles, got %+v", manifest.AuxiliaryFiles)
	}

	if _, err := VerifyBundle(ctx, outDir); err != nil {
		t.Fatalf("VerifyBundle(dir source): %v", err)
	}
}
