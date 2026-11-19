//go:build linux || windows || darwin

package accessreader

import (
	"bytes"
	"compress/gzip"
	"embed"
	"encoding/binary"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

//go:embed testdata/*.gz
var committedSynthFixturesFS embed.FS

const committedSynthTable = "Sample_Env"

func committedFixtureCols() []synthColumnDef {
	return []synthColumnDef{
		{Name: "ID", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "SmallCode", Type: synthColByte, IsFixed: true, Size: 1},
		{Name: "Elevation", Type: synthColInt, IsFixed: true, Size: 2},
		{Name: "Slope", Type: synthColFloat, IsFixed: true, Size: 4},
		{Name: "Cover", Type: synthColDouble, IsFixed: true, Size: 8},
		{Name: "Fee", Type: synthColMoney, IsFixed: true, Size: 8},
		{Name: "ExactDec", Type: synthColNumeric, IsFixed: true, Size: 17, Scale: 10, Prec: 2},
		{Name: "ObservedAt", Type: synthColDateTime, IsFixed: true, Size: 8},
		{Name: "BEC_Use", Type: synthColBool, IsFixed: true, Size: 0},
		{Name: "PlotNumber", Type: synthColText, IsFixed: false, Size: 14},
		{Name: "Notes", Type: synthColMemo, IsFixed: false, Size: 0},
		{Name: "RawBytes", Type: synthColBinary, IsFixed: false, Size: 16},
		{Name: "PhotoBlob", Type: synthColOLE, IsFixed: false, Size: 0},
	}
}

func buildCanonicalSynthJet4FixtureBytes() []byte {
	cols := committedFixtureCols()
	row1 := packSynthJet4Row(cols, []synthCell{
		synthInt32Cell(101),
		synthByteCell(7),
		synthInt16Cell(1245),
		synthFloat32Cell(12.5),
		synthFloat64Cell(99.999996),
		synthMoneyCell(1234500),       // 123.4500
		synthNumericCell(false, 4250), // 42.50
		synthFloat64Cell(45292),       // 2024-01-01 00:00:00 UTC
		synthBoolCell(true),
		synthTextCell("00337"),
		synthInlineMemoCell("upland Tsuga plot"),
		synthBinaryCell([]byte{0xde, 0xad}),
		synthInlineOLECell([]byte{0xca, 0xfe, 0xba, 0xbe}),
	}, len(cols))

	row2 := packSynthJet4Row(cols, []synthCell{
		synthInt32Cell(102),
		synthNullCell(),
		synthInt16Cell(-15),
		synthNullCell(),
		synthFloat64Cell(0.5),
		synthMoneyCell(-50000),      // -5.0000
		synthNumericCell(true, 105), // -1.05
		synthFloat64Cell(45293.5),   // 2024-01-02 12:00:00 UTC
		synthBoolCell(false),
		synthTextCell("337"),
		synthNullCell(),
		synthNullCell(),
		synthNullCell(),
	}, len(cols))

	dataPage := buildSynthJet4DataPage(4, []synthPageRow{{Raw: row1}, {Raw: row2}})
	return buildSynthJet4DatabaseBytes(committedSynthTable, cols, [][]byte{dataPage}, nil)
}

func buildCanonicalSynthJet3FixtureBytes() []byte {
	cols := committedFixtureCols()
	row1 := packSynthJet3Row(cols, []synthCell{
		synthInt32Cell(101),
		synthByteCell(7),
		synthInt16Cell(1245),
		synthFloat32Cell(12.5),
		synthFloat64Cell(99.999996),
		synthMoneyCell(1234500),
		synthNumericCell(false, 4250),
		synthFloat64Cell(45292),
		synthBoolCell(true),
		synthJet3TextCell("00337"),
		synthJet3InlineMemoCell("upland Tsuga plot"),
		synthBinaryCell([]byte{0xde, 0xad}),
		synthInlineOLECell([]byte{0xca, 0xfe, 0xba, 0xbe}),
	}, len(cols))

	row2 := packSynthJet3Row(cols, []synthCell{
		synthInt32Cell(102),
		synthNullCell(),
		synthInt16Cell(-15),
		synthNullCell(),
		synthFloat64Cell(0.5),
		synthMoneyCell(-50000),
		synthNumericCell(true, 105),
		synthFloat64Cell(45293.5),
		synthBoolCell(false),
		synthJet3TextCell("337"),
		synthNullCell(),
		synthNullCell(),
		synthNullCell(),
	}, len(cols))

	dataPage := buildSynthJet3DataPage(4, []synthPageRow{{Raw: row1}, {Raw: row2}})
	return buildSynthJet3DatabaseBytes(committedSynthTable, cols, [][]byte{dataPage})
}

func materializeCommittedGzipFixture(t *testing.T, embeddedName, outName string) ([]byte, string) {
	t.Helper()
	gzBytes, err := committedSynthFixturesFS.ReadFile("testdata/" + embeddedName)
	if err != nil {
		t.Fatalf("read embedded testdata/%s: %v", embeddedName, err)
	}
	zr, err := gzip.NewReader(bytes.NewReader(gzBytes))
	if err != nil {
		t.Fatalf("gzip reader testdata/%s: %v", embeddedName, err)
	}
	raw, err := io.ReadAll(zr)
	closeErr := zr.Close()
	if err != nil || closeErr != nil {
		t.Fatalf("gunzip testdata/%s: %v / %v", embeddedName, err, closeErr)
	}
	dest := filepath.Join(t.TempDir(), outName)
	if err := os.WriteFile(dest, raw, 0o600); err != nil {
		t.Fatalf("write %s: %v", dest, err)
	}
	return raw, dest
}

func TestOpenInvalidAndMissing(t *testing.T) {
	if _, err := Open("missing-does-not-exist.accdb"); err == nil {
		t.Fatal("expected error for missing file")
	}
	if _, err := Open("invalid\x00path.accdb"); err == nil || !strings.Contains(err.Error(), "invalid Access path") {
		t.Fatalf("expected invalid path error, got %v", err)
	}
	dir := t.TempDir()
	shortFile := filepath.Join(dir, "short.mdb")
	if err := os.WriteFile(shortFile, []byte("not an access db"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(shortFile); err == nil {
		t.Fatal("expected error for invalid short file")
	}
}

func TestCommittedSyntheticJet3MDBAndJet4ACCDBHermeticScanSchemaAndQuarantine(t *testing.T) {
	if os.Getenv("VPRO_REGEN_ACCESS_TESTDATA") == "1" {
		writeGz := func(name string, payload []byte) {
			var buf bytes.Buffer
			zw, err := gzip.NewWriterLevel(&buf, gzip.BestCompression)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := zw.Write(payload); err != nil {
				t.Fatal(err)
			}
			if err := zw.Close(); err != nil {
				t.Fatal(err)
			}
			if err := os.MkdirAll("testdata", 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join("testdata", name), buf.Bytes(), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		writeGz("synthetic_jet3.mdb.gz", buildCanonicalSynthJet3FixtureBytes())
		writeGz("synthetic_jet4.accdb.gz", buildCanonicalSynthJet4FixtureBytes())
		return
	}

	formats := []struct {
		name         string
		embeddedGzip string
		outFile      string
		canonical    []byte
		isJet3       bool
	}{
		{
			name:         "Jet3_MDB",
			embeddedGzip: "synthetic_jet3.mdb.gz",
			outFile:      "synthetic_jet3.mdb",
			canonical:    buildCanonicalSynthJet3FixtureBytes(),
			isJet3:       true,
		},
		{
			name:         "Jet4_ACCDB",
			embeddedGzip: "synthetic_jet4.accdb.gz",
			outFile:      "synthetic_jet4.accdb",
			canonical:    buildCanonicalSynthJet4FixtureBytes(),
			isJet3:       false,
		},
	}

	wantColumns := []Column{
		{Name: "ID", Type: "integer"},
		{Name: "SmallCode", Type: "integer"},
		{Name: "Elevation", Type: "integer"},
		{Name: "Slope", Type: "real"},
		{Name: "Cover", Type: "real"},
		{Name: "Fee", Type: "decimal"},
		{Name: "ExactDec", Type: "decimal"},
		{Name: "ObservedAt", Type: "datetime"},
		{Name: "BEC_Use", Type: "boolean"},
		{Name: "PlotNumber", Type: "text"},
		{Name: "Notes", Type: "text"},
		{Name: "RawBytes", Type: "binary"},
		{Name: "PhotoBlob", Type: "binary"},
	}

	wantRows := []Row{
		{
			int64(101),
			int64(7),
			int64(1245),
			float64(12.5),
			float64(99.999996),
			"123.4500",
			"42.50",
			time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC),
			true,
			"00337",
			"upland Tsuga plot",
			[]byte{0xde, 0xad},
			[]byte{0xca, 0xfe, 0xba, 0xbe},
		},
		{
			int64(102),
			nil,
			int64(-15),
			nil,
			float64(0.5),
			"-5.0000",
			"-1.05",
			time.Date(2024, 1, 2, 12, 0, 0, 0, time.UTC),
			false,
			"337",
			nil,
			nil,
			nil,
		},
	}

	for _, tc := range formats {
		t.Run(tc.name, func(t *testing.T) {
			rawBytes, dbPath := materializeCommittedGzipFixture(t, tc.embeddedGzip, tc.outFile)
			if !bytes.Equal(rawBytes, tc.canonical) {
				t.Fatalf("committed testdata/%s drifted from canonical generator (%d vs %d bytes)", tc.embeddedGzip, len(rawBytes), len(tc.canonical))
			}

			db, err := Open(dbPath)
			if err != nil {
				t.Fatalf("Open(%s): %v", tc.outFile, err)
			}

			tables, err := db.Tables()
			if err != nil {
				t.Fatalf("Tables(): %v", err)
			}
			if len(tables) != 1 || tables[0].Name != committedSynthTable || tables[0].Linked {
				t.Fatalf("unexpected Tables(): %+v", tables)
			}

			descriptions, err := db.TableDescriptions()
			if err != nil || len(descriptions) != 1 || descriptions[0].Name != committedSynthTable {
				t.Fatalf("unexpected TableDescriptions(): %+v (err=%v)", descriptions, err)
			}

			nativeCols, err := db.NativeColumns(committedSynthTable)
			if err != nil || len(nativeCols) != len(wantColumns) {
				t.Fatalf("NativeColumns(): len=%d err=%v", len(nativeCols), err)
			}
			for i, nc := range nativeCols {
				if nc.Name != wantColumns[i].Name || nc.SourceColumnNumber != i {
					t.Fatalf("NativeColumns[%d] = %+v, want Name=%q colNum=%d", i, nc, wantColumns[i].Name, i)
				}
			}

			reader, err := db.Scan(committedSynthTable)
			if err != nil {
				t.Fatalf("Scan(%s): %v", committedSynthTable, err)
			}
			if reader.EstimatedRowCount() != 2 {
				reader.Close()
				t.Fatalf("EstimatedRowCount = %d, want 2", reader.EstimatedRowCount())
			}
			reader.Close()

			cols, rows, err := db.ReadAll(committedSynthTable)
			if err != nil {
				t.Fatalf("ReadAll(%s): %v", committedSynthTable, err)
			}
			if !reflect.DeepEqual(cols, wantColumns) {
				t.Fatalf("columns mismatch:\n got: %#v\nwant: %#v", cols, wantColumns)
			}
			if len(rows) != len(wantRows) {
				t.Fatalf("row count = %d, want %d", len(rows), len(wantRows))
			}
			for rIdx := range wantRows {
				for cIdx := range wantColumns {
					gotCell := rows[rIdx][cIdx]
					wantCell := wantRows[rIdx][cIdx]
					if cIdx == 4 {
						gotF, ok := gotCell.(float64)
						wantF := wantCell.(float64)
						if !ok || (gotF-wantF) > 1e-5 || (wantF-gotF) > 1e-5 {
							t.Fatalf("row %d Cover = %#v, want ~%v", rIdx, gotCell, wantF)
						}
						continue
					}
					if !reflect.DeepEqual(gotCell, wantCell) {
						t.Fatalf("row %d col %d (%s) = %#v (%T), want %#v (%T)",
							rIdx, cIdx, wantColumns[cIdx].Name, gotCell, gotCell, wantCell, wantCell)
					}
				}
			}

			// Verify both C-level (corrupt row offset -> GO_MDB_ERROR_ROW) and Go-level (oversized memo -> status==1)
			// row quarantine on this exact format preserve adjacent valid rows without skipping.
			corruptBytes := append([]byte(nil), rawBytes...)
			dataPgStart := 5 * synthPageSize
			rco := 0x0c
			if tc.isJet3 {
				dataPgStart = 5 * synthJet3PageSize
				rco = 0x08
			}
			// Corrupt row 0's internal row_cols header to 0xff (> row_size, leaving row 0's offset pointer intact
			// so row 1's end boundary is unaffected): mdb_crack_row triggers C-level GO_MDB_ERROR_ROW on row 0,
			// while row 1 ("337") decodes intact!
			row0Offset := int(binary.LittleEndian.Uint16(corruptBytes[dataPgStart+rco+2:]) & 0x1fff)
			corruptBytes[dataPgStart+row0Offset] = 0xff
			if !tc.isJet3 {
				corruptBytes[dataPgStart+row0Offset+1] = 0x00
			}
			corruptPath := filepath.Join(t.TempDir(), "corrupt_"+tc.outFile)
			if err := os.WriteFile(corruptPath, corruptBytes, 0o600); err != nil {
				t.Fatal(err)
			}
			cDB, err := Open(corruptPath)
			if err != nil {
				t.Fatal(err)
			}
			// Default fail-closed Scan must fail on row 1 without quarantine enabled.
			strictR, err := cDB.Scan(committedSynthTable)
			if err != nil {
				t.Fatal(err)
			}
			if strictR.Next() || strictR.Err() == nil {
				strictR.Close()
				t.Fatal("expected fail-closed Scan without EnableRowQuarantine to error on corrupt row 0")
			}
			strictR.Close()

			// With EnableRowQuarantine(), C-level corrupt row 1 is quarantined and row 2 ("337") is yielded intact.
			qR, err := cDB.Scan(committedSynthTable)
			if err != nil {
				t.Fatal(err)
			}
			qR.EnableRowQuarantine()
			var survivedPlots []string
			for qR.Next() {
				survivedPlots = append(survivedPlots, qR.Row()[9].(string))
			}
			if err := qR.Err(); err != nil {
				qR.Close()
				t.Fatalf("quarantined Scan Err() = %v", err)
			}
			qR.Close()
			if !reflect.DeepEqual(survivedPlots, []string{"337"}) || len(qR.Quarantined) != 1 || qR.Quarantined[0].RowNumber != 1 {
				t.Fatalf("C-level quarantine: survived=%v quarantined=%+v", survivedPlots, qR.Quarantined)
			}

			// Go-level post-fetch cell parse error on row 1 ("00337" parsed as integer) quarantines row 1 and yields row 2 ("337").
			goQR, err := db.Scan(committedSynthTable)
			if err != nil {
				t.Fatal(err)
			}
			goQR.EnableRowQuarantine()
			goQR.postFetchCheck = func(rowNumber int, _ Row) error {
				if rowNumber == 1 {
					return errors.New("synthetic Go-level cell failure")
				}
				return nil
			}
			var goSurvived []string
			for goQR.Next() {
				goSurvived = append(goSurvived, goQR.Row()[9].(string))
			}
			if err := goQR.Err(); err != nil {
				goQR.Close()
				t.Fatal(err)
			}
			goQR.Close()
			if !reflect.DeepEqual(goSurvived, []string{"337"}) || len(goQR.Quarantined) != 1 || goQR.Quarantined[0].RowNumber != 1 {
				t.Fatalf("Go-level quarantine: survived=%v quarantined=%+v", goSurvived, goQR.Quarantined)
			}
		})
	}
}

func TestOptionalLocalTemplatesScanWhenAvailable(t *testing.T) {
	workRoot := os.Getenv("VPRO_EXTERNAL_ARCHIVE_ROOT")
	if workRoot == "" {
		if home, err := os.UserHomeDir(); err == nil {
			workRoot = filepath.Join(home, "Work")
		}
	}
	if workRoot == "" {
		return
	}
	for _, candidate := range []struct {
		relPath string
		project string
		version string
	}{
		{filepath.Join("VPRO_ACCESS", "VPro64", "VPro64.accdb"), "Sample", "VP08"},
		{filepath.Join("VPRO_ACCESS", "VPro64", "Templates", "TemplateVPro15.accdb"), "VPro15", "VP07"},
		{filepath.Join("VPRO_ACCESS", "VPro64", "Templates", "TemplateVPro13.accdb"), "VPro13", "VP06"},
		{filepath.Join("VPRO_ACCESS", "VPro64", "Templates", "TemplateVPro03.mdb"), "VPro03", "VP05"},
		{filepath.Join("VPRO_ACCESS", "VPro64", "Templates", "TemplateVProXP.mdb"), "VProXP", "VP05"},
	} {
		fullPath := filepath.Join(workRoot, candidate.relPath)
		if _, err := os.Stat(fullPath); err != nil {
			continue
		}
		db, err := Open(fullPath)
		if err != nil {
			t.Fatalf("Open(%s): %v", fullPath, err)
		}
		tables, err := db.Tables()
		if err != nil {
			t.Fatalf("Tables(%s): %v", fullPath, err)
		}
		envName := candidate.project + "_Env"
		found := false
		for _, tbl := range tables {
			if strings.EqualFold(tbl.Name, envName) {
				found = true
				if tbl.Description != candidate.version {
					t.Fatalf("%s.%s description = %q, want %q", fullPath, tbl.Name, tbl.Description, candidate.version)
				}
				cols, rows, err := db.ReadAll(tbl.Name)
				if err != nil || len(cols) == 0 {
					t.Fatalf("ReadAll(%s.%s): cols=%d rows=%d err=%v", fullPath, tbl.Name, len(cols), len(rows), err)
				}
			}
		}
		if !found {
			t.Fatalf("%s missing expected table %s", fullPath, envName)
		}
	}
}
