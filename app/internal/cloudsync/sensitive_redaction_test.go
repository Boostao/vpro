package cloudsync

import (
	"context"
	"database/sql"
	"errors"
	"math"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/jackc/pgx/v5"
)

func TestWave2LMH25DepthNonNegativeAndNumericPrefixes(t *testing.T) {
	pos := func(v float64) *float64 { return &v }

	// Valid numeric-prefixed horizons >= 0 cm
	if err := ValidateLMH25HorizonDepth("Humus", "2Of", pos(0), pos(5)); err != nil {
		t.Fatalf("expected valid numeric-prefixed wetland 2Of (0..5), got %v", err)
	}
	if err := ValidateLMH25HorizonDepth("Humus", "1F", pos(6), pos(2)); err != nil {
		t.Fatalf("expected valid numeric-prefixed upland 1F (6..2), got %v", err)
	}

	// Reject negative depths even when direction matches
	if err := ValidateLMH25HorizonDepth("Humus", "2Of", pos(-1), pos(4)); err == nil {
		t.Fatal("expected negative UpperDepth in wetland Humus to fail")
	}
	if err := ValidateLMH25HorizonDepth("Humus", "1F", pos(4), pos(-1)); err == nil {
		t.Fatal("expected negative LowerDepth in upland Humus to fail")
	}
	if err := ValidateLMH25HorizonDepth("Mineral", "Bm", pos(-2), pos(10)); err == nil {
		t.Fatal("expected negative UpperDepth in Mineral to fail")
	}

	// Reject inverted numeric-prefixed horizons
	if err := ValidateLMH25HorizonDepth("Humus", "3Oh", pos(8), pos(3)); err == nil {
		t.Fatal("expected inverted wetland 3Oh (8..3) to fail")
	}
	if err := ValidateLMH25HorizonDepth("Humus", "2L", pos(1), pos(5)); err == nil {
		t.Fatal("expected inverted upland 2L (1..5) to fail")
	}
}

func TestWave2RedBlueListCoordinateRedactionAndStandardsDDL(t *testing.T) {
	ctx := context.Background()
	if len(StandardsUSysSppAttributesColumns) != 29 {
		t.Fatalf("expected 29 StandardsUSysSppAttributesColumns matching VLists.USysSppAttributes, got %d", len(StandardsUSysSppAttributesColumns))
	}
	ddlJoined := ""
	for _, s := range buildV1MigrationStatements(true) {
		ddlJoined += s + "\n"
	}
	if !containsString(ddlJoined, `"usys_spp_attributes"`) {
		t.Fatal("expected BootstrapSchemaSQL to create standards.usys_spp_attributes")
	}

	for _, tc := range []struct {
		code string
		want bool
	}{
		{"R", true},
		{"B", true},
		{"Red", true},
		{" blue ", true},
		{"Z", false},
		{"", false},
		{"Yellow", false},
	} {
		if got := IsSensitiveRedBlueList(tc.code); got != tc.want {
			t.Fatalf("IsSensitiveRedBlueList(%q) = %v, want %v", tc.code, got, tc.want)
		}
	}

	// Verify MaskSensitiveEnvRow preserves western negative sign while truncating to 0.1 deg and 10 km UTM
	row := make([]any, len(VP08EnvColumns))
	for i, col := range VP08EnvColumns {
		switch col.Name {
		case "Longitude":
			row[i] = -125.4892
		case "Latitude":
			row[i] = 49.6871
		case "UTMEasting":
			row[i] = 466721.5
		case "UTMNorthing":
			row[i] = 5441234.8
		case "XCoord":
			row[i] = -125.4892
		case "YCoord":
			row[i] = 49.6871
		}
	}
	MaskSensitiveEnvRow(VP08EnvColumns, row)
	for i, col := range VP08EnvColumns {
		switch col.Name {
		case "Longitude", "XCoord":
			if got := row[i].(float64); math.Abs(got-(-125.4)) > 1e-9 {
				t.Fatalf("%s masked = %v, want -125.4", col.Name, got)
			}
		case "Latitude", "YCoord":
			if got := row[i].(float64); math.Abs(got-49.6) > 1e-9 {
				t.Fatalf("%s masked = %v, want 49.6", col.Name, got)
			}
		case "UTMEasting":
			if got := row[i].(float64); got != 460000.0 {
				t.Fatalf("UTMEasting masked = %v, want 460000", got)
			}
		case "UTMNorthing":
			if got := row[i].(float64); got != 5440000.0 {
				t.Fatalf("UTMNorthing masked = %v, want 5440000", got)
			}
		}
	}

	// Verify SQLite project redaction joins USysSppAttributes.RedBlueList, ignores 'Z'/'S', and leaves safe plots untouched
	tmpDir := t.TempDir()
	vlistsPath := filepath.Join(tmpDir, "VLists.db")
	projPath := filepath.Join(tmpDir, "Snap.db")

	vdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(vlistsPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := vdb.Exec(`
		CREATE TABLE USysSppAttributes (Code TEXT, Codetype TEXT, RedBlueList TEXT);
		INSERT INTO USysSppAttributes (Code, Codetype, RedBlueList) VALUES
			('RARESPP1', 'U', 'R'),
			('BLUESPP1', 'U', 'B'),
			('SYNRARE',  'S', 'R'),
			('NODATA',   'U', 'Z'),
			('COMMON',   'U', '');
	`); err != nil {
		t.Fatal(err)
	}
	_ = vdb.Close()

	pdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pdb.Exec(`
		CREATE TABLE Snap_Env (PlotNumber TEXT, Longitude REAL, Latitude REAL, UTMEasting REAL, UTMNorthing REAL, XCoord REAL, YCoord REAL);
		CREATE TABLE Snap_Veg (PlotNumber TEXT, Species TEXT);
		INSERT INTO Snap_Env VALUES
			('P001', -123.4567, 49.2891, 466721.0, 5441234.0, 466721.0, 5441234.0),
			('P002', -124.9876, 50.1234, 358123.0, 5554321.0, NULL, NULL),
			('P003', -122.1111, 48.9999, 512345.0, 5423456.0, NULL, NULL);
		INSERT INTO Snap_Veg VALUES
			('P001', 'RARESPP1'),
			('P002', 'COMMON'),
			('P003', 'SYNRARE'),
			('P003', 'NODATA');
	`); err != nil {
		t.Fatal(err)
	}
	_ = pdb.Close()

	maskedCount, err := RedactSensitiveSQLiteProjectCoordinates(ctx, projPath, "Snap", vlistsPath)
	if err != nil {
		t.Fatalf("RedactSensitiveSQLiteProjectCoordinates: %v", err)
	}
	if maskedCount != 1 {
		t.Fatalf("expected exactly 1 masked sensitive plot (P001), got %d", maskedCount)
	}

	chk, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer chk.Close()

	var lon, lat, e, n float64
	if err := chk.QueryRow(`SELECT Longitude, Latitude, UTMEasting, UTMNorthing FROM Snap_Env WHERE PlotNumber='P001'`).Scan(&lon, &lat, &e, &n); err != nil {
		t.Fatal(err)
	}
	if math.Abs(lon-(-123.4)) > 1e-9 || math.Abs(lat-49.2) > 1e-9 || e != 460000.0 || n != 5440000.0 {
		t.Fatalf("P001 masked coords unexpected: lon=%v lat=%v e=%v n=%v", lon, lat, e, n)
	}
	if err := chk.QueryRow(`SELECT Longitude, Latitude FROM Snap_Env WHERE PlotNumber='P002'`).Scan(&lon, &lat); err != nil {
		t.Fatal(err)
	}
	if lon != -124.9876 || lat != 50.1234 {
		t.Fatalf("P002 non-sensitive coords mutated unexpectedly: lon=%v lat=%v", lon, lat)
	}
}

type fakePGScanRow struct {
	scanFn func(dest ...any) error
}

func (r fakePGScanRow) Scan(dest ...any) error {
	return r.scanFn(dest...)
}

type fakePGStringRows struct {
	pgx.Rows
	values []string
	idx    int
	err    error
}

func (r *fakePGStringRows) Close() {}

func (r *fakePGStringRows) Err() error { return r.err }

func (r *fakePGStringRows) Next() bool {
	if r.err != nil || r.idx >= len(r.values) {
		return false
	}
	r.idx++
	return true
}

func (r *fakePGStringRows) Scan(dest ...any) error {
	if len(dest) != 1 {
		return errors.New("expected 1 scan destination")
	}
	ptr, ok := dest[0].(*string)
	if !ok {
		return errors.New("expected *string scan destination")
	}
	*ptr = r.values[r.idx-1]
	return nil
}

type fakeSensitivePG struct {
	hasAttrTable   bool
	attrCheckErr   error
	sensitiveCodes []string
	sensitivePlots []string
}

func (f *fakeSensitivePG) QueryRow(_ context.Context, sqlText string, _ ...any) pgx.Row {
	if strings.Contains(sqlText, "to_regclass('standards.usys_spp_attributes')") {
		return fakePGScanRow{
			scanFn: func(dest ...any) error {
				if f.attrCheckErr != nil {
					return f.attrCheckErr
				}
				*(dest[0].(*bool)) = f.hasAttrTable
				return nil
			},
		}
	}
	return fakePGScanRow{scanFn: func(...any) error { return errors.New("unexpected QueryRow: " + sqlText) }}
}

func (f *fakeSensitivePG) Query(_ context.Context, sqlText string, _ ...any) (pgx.Rows, error) {
	if strings.Contains(sqlText, "FROM standards.usys_spp_attributes") {
		return &fakePGStringRows{values: f.sensitiveCodes}, nil
	}
	if strings.Contains(sqlText, "FROM becmaster.veg") {
		return &fakePGStringRows{values: f.sensitivePlots}, nil
	}
	return nil, errors.New("unexpected Query: " + sqlText)
}

func TestSensitiveRedactionFailsClosedWhenConservationMetadataEmptyOrMissing(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	projPath := filepath.Join(tmpDir, "UnredactedGuard.db")
	pdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pdb.Exec(`
		CREATE TABLE UnredactedGuard_Env (PlotNumber TEXT, Longitude REAL, Latitude REAL, UTMEasting REAL, UTMNorthing REAL, XCoord REAL, YCoord REAL);
		CREATE TABLE UnredactedGuard_Veg (PlotNumber TEXT, Species TEXT);
		INSERT INTO UnredactedGuard_Env VALUES ('P001', -123.4567, 49.2891, 466721.0, 5441234.0, 466721.0, 5441234.0);
		INSERT INTO UnredactedGuard_Veg VALUES ('P001', 'ABIELAS');
	`); err != nil {
		t.Fatal(err)
	}
	_ = pdb.Close()

	// 1. Shipped VLists.db has 8,262 USysSppAttributes rows with 0 RedBlueList codes -> must fail loud!
	bundledVLists := filepath.Join("..", "..", "resources", "database-family", "VLists.db")
	if _, err := loadSensitiveSpeciesFromSQLiteVLists(ctx, bundledVLists); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected loadSensitiveSpeciesFromSQLiteVLists on unpopulated bundled VLists.db to fail loud, got: %v", err)
	}
	if n, err := RedactSensitiveSQLiteProjectCoordinates(ctx, projPath, "UnredactedGuard", bundledVLists); err == nil || n != 0 || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected RedactSensitiveSQLiteProjectCoordinates on bundled VLists.db to fail closed, got n=%d err=%v", n, err)
	}

	// 2. Blank path, missing USysSppAttributes table, and Z/Y/S-synonym-only USysSppAttributes must all fail loud.
	if _, err := RedactSensitiveSQLiteProjectCoordinates(ctx, projPath, "UnredactedGuard", ""); err == nil {
		t.Fatal("expected empty vlistsPath to fail closed")
	}

	noTblVLists := filepath.Join(tmpDir, "VLists_NoTable.db")
	ndb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(noTblVLists, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ndb.Exec(`CREATE TABLE USysAllSpecs (Code TEXT);`); err != nil {
		t.Fatal(err)
	}
	_ = ndb.Close()
	if _, err := RedactSensitiveSQLiteProjectCoordinates(ctx, projPath, "UnredactedGuard", noTblVLists); err == nil || !strings.Contains(err.Error(), "USysSppAttributes is missing") {
		t.Fatalf("expected missing USysSppAttributes table to fail closed, got: %v", err)
	}

	zOnlyVLists := filepath.Join(tmpDir, "VLists_ZOnly.db")
	zdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(zOnlyVLists, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := zdb.Exec(`
		CREATE TABLE USysSppAttributes (Code TEXT, Codetype TEXT, RedBlueList TEXT);
		INSERT INTO USysSppAttributes VALUES
			('NODATA_Z', 'V', 'Z'),
			('SECURE_Y', 'V', 'Y'),
			('SYN_R',    'S', 'R'),
			('BLANK',    'V', '');
	`); err != nil {
		t.Fatal(err)
	}
	_ = zdb.Close()
	if _, err := RedactSensitiveSQLiteProjectCoordinates(ctx, projPath, "UnredactedGuard", zOnlyVLists); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected Z/Y/S-only USysSppAttributes to fail closed, got: %v", err)
	}

	// Verify UnredactedGuard_Env was not partially mutated when redaction aborted.
	chk, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer chk.Close()
	var lon, lat float64
	if err := chk.QueryRow(`SELECT Longitude, Latitude FROM UnredactedGuard_Env WHERE PlotNumber='P001'`).Scan(&lon, &lat); err != nil {
		t.Fatal(err)
	}
	if lon != -123.4567 || lat != 49.2891 {
		t.Fatalf("expected failed redaction to leave database untouched, got lon=%v lat=%v", lon, lat)
	}

	// 3. PostgreSQL subset/snapshot redaction (findSensitivePlotsForSubsetPG & loadSensitiveSpeciesFromPG):
	//    missing table or 0 Red/Blue rows in both PG and local VLists must fail closed.
	missingPG := &fakeSensitivePG{hasAttrTable: false}
	if _, err := loadSensitiveSpeciesFromPG(ctx, missingPG); err == nil || !strings.Contains(err.Error(), "standards.usys_spp_attributes is missing") {
		t.Fatalf("expected loadSensitiveSpeciesFromPG on missing table to fail closed, got: %v", err)
	}
	if _, err := findSensitivePlotsForSubsetPG(ctx, missingPG, []string{"P001"}, noTblVLists); err == nil || !strings.Contains(err.Error(), "is missing") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG on missing PG + local tables to fail closed, got: %v", err)
	}

	emptyPG := &fakeSensitivePG{hasAttrTable: true, sensitiveCodes: nil}
	if _, err := loadSensitiveSpeciesFromPG(ctx, emptyPG); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected loadSensitiveSpeciesFromPG on empty table to fail closed, got: %v", err)
	}
	if _, err := findSensitivePlotsForSubsetPG(ctx, emptyPG, []string{"P001"}, bundledVLists); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG on empty PG + bundled VLists to fail closed, got: %v", err)
	}
	if _, err := findSensitivePlotsForSubsetPG(ctx, emptyPG, nil, bundledVLists); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG to fail closed even with empty plotList when metadata is unpopulated, got: %v", err)
	}

	// 4. When EITHER PostgreSQL standards.usys_spp_attributes OR local VLists.db has Red/Blue rows, redaction succeeds.
	populatedPG := &fakeSensitivePG{
		hasAttrTable:   true,
		sensitiveCodes: []string{"ABIELAS"},
		sensitivePlots: []string{"P001"},
	}
	gotPlots, err := findSensitivePlotsForSubsetPG(ctx, populatedPG, []string{"P001", "P002"}, bundledVLists)
	if err != nil {
		t.Fatalf("expected populated PG standards.usys_spp_attributes to succeed even when local VLists is unpopulated, got: %v", err)
	}
	if _, ok := gotPlots["P001"]; !ok || len(gotPlots) != 1 {
		t.Fatalf("expected sensitive plot P001 from populated PG metadata, got: %+v", gotPlots)
	}

	popVLists := filepath.Join(tmpDir, "VLists_Populated.db")
	pvdb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(popVLists, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pvdb.Exec(`
		CREATE TABLE USysSppAttributes (Code TEXT, Codetype TEXT, RedBlueList TEXT);
		INSERT INTO USysSppAttributes VALUES ('ABIELAS', 'V', 'Red');
	`); err != nil {
		t.Fatal(err)
	}
	_ = pvdb.Close()

	emptyPGWithPlotHit := &fakeSensitivePG{
		hasAttrTable:   true,
		sensitiveCodes: nil,
		sensitivePlots: []string{"P001"},
	}
	gotLocalPlots, err := findSensitivePlotsForSubsetPG(ctx, emptyPGWithPlotHit, []string{"P001"}, popVLists)
	if err != nil {
		t.Fatalf("expected populated local VLists.db to satisfy findSensitivePlotsForSubsetPG when PG table is empty, got: %v", err)
	}
	if _, ok := gotLocalPlots["P001"]; !ok || len(gotLocalPlots) != 1 {
		t.Fatalf("expected sensitive plot P001 from populated local VLists.db, got: %+v", gotLocalPlots)
	}
}

func containsString(haystack, needle string) bool {
	return len(needle) == 0 || (len(haystack) >= len(needle) && indexString(haystack, needle) >= 0)
}

func indexString(haystack, needle string) int {
	for i := 0; i <= len(haystack)-len(needle); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}
