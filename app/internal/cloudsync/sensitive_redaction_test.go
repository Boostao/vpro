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
	"github.com/boostao/vpro/app/resources"
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

	// Verify SQLite VLists conservation reader extracts 'R'/'B' non-synonyms and ignores 'Z'/'S'/''
	tmpDir := t.TempDir()
	vlistsPath := filepath.Join(tmpDir, "VLists.db")

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

	codes, hasTbl, err := readSensitiveSpeciesFromSQLiteVLists(ctx, vlistsPath)
	if err != nil || !hasTbl {
		t.Fatalf("readSensitiveSpeciesFromSQLiteVLists: hasTbl=%v err=%v", hasTbl, err)
	}
	if len(codes) != 2 {
		t.Fatalf("expected 2 Red/Blue species (RARESPP1, BLUESPP1), got %v", codes)
	}
	if _, ok := codes["RARESPP1"]; !ok {
		t.Fatal("missing RARESPP1")
	}
	if _, ok := codes["BLUESPP1"]; !ok {
		t.Fatal("missing BLUESPP1")
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

	bundledVLists := resources.Path("resources", "database-family", "VLists.db")
	noTblVLists := filepath.Join(tmpDir, "VLists_NoTable.db")
	ndb, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(noTblVLists, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ndb.Exec(`CREATE TABLE USysAllSpecs (Code TEXT);`); err != nil {
		t.Fatal(err)
	}
	_ = ndb.Close()

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

	// PostgreSQL subset/snapshot redaction (findSensitivePlotsForSubsetPG):
	// missing table or 0 Red/Blue rows in both PG and local VLists must fail closed.
	missingPG := &fakeSensitivePG{hasAttrTable: false}
	if _, err := findSensitivePlotsForSubsetPG(ctx, missingPG, []string{"P001"}, ""); err == nil || !strings.Contains(err.Error(), "is missing") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG on missing PG + blank local VLists to fail closed, got: %v", err)
	}
	if _, err := findSensitivePlotsForSubsetPG(ctx, missingPG, []string{"P001"}, noTblVLists); err == nil || !strings.Contains(err.Error(), "is missing") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG on missing PG + local tables to fail closed, got: %v", err)
	}

	emptyPG := &fakeSensitivePG{hasAttrTable: true, sensitiveCodes: nil}
	if _, err := findSensitivePlotsForSubsetPG(ctx, emptyPG, []string{"P001"}, zOnlyVLists); err == nil || !strings.Contains(err.Error(), "0 Red/Blue-listed species rows") {
		t.Fatalf("expected findSensitivePlotsForSubsetPG on empty PG + Z/Y/S-only local VLists to fail closed, got: %v", err)
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
