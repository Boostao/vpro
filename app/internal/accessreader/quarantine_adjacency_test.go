//go:build linux || windows || darwin

package accessreader

import (
	"archive/zip"
	"encoding/binary"
	"errors"
	"io"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

const synthQuarantineTable = "QuarantineTest"

func defaultSynthCols() []synthColumnDef {
	return []synthColumnDef{
		{Name: "ID", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "PlotNumber", Type: synthColText, IsFixed: false, Size: 14},
		{Name: "Notes", Type: synthColMemo, IsFixed: false, Size: 0},
		{Name: "ObservedAt", Type: synthColDateTime, IsFixed: true, Size: 8},
		{Name: "Payload", Type: synthColOLE, IsFixed: false, Size: 0},
		{Name: "Active", Type: synthColBool, IsFixed: true, Size: 0},
	}
}

func validSynthCells(id int32, plot, note string, days float64, blob []byte, active bool) []synthCell {
	return []synthCell{
		synthInt32Cell(id),
		synthTextCell(plot),
		synthInlineMemoCell(note),
		synthFloat64Cell(days),
		synthInlineOLECell(blob),
		synthBoolCell(active),
	}
}

func standardFourValidCellSets() [][]synthCell {
	// 45292 = 2024-01-01 00:00:00 UTC in Access epoch days (from 1899-12-30).
	return [][]synthCell{
		validSynthCells(1, "00337", "alpha plot", 45292, []byte{0x01, 0x02}, true),
		validSynthCells(2, "00338", "bravo plot", 45293, []byte{0x03, 0x04}, false),
		validSynthCells(3, "00339", "charlie plot", 45294, []byte{0x05, 0x06}, true),
		validSynthCells(4, "00340", "delta plot", 45295, []byte{0x07, 0x08}, false),
	}
}

func expectedStandardRows() []Row {
	return []Row{
		{int64(1), "00337", "alpha plot", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), []byte{0x01, 0x02}, true},
		{int64(2), "00338", "bravo plot", time.Date(2024, 1, 2, 0, 0, 0, 0, time.UTC), []byte{0x03, 0x04}, false},
		{int64(3), "00339", "charlie plot", time.Date(2024, 1, 3, 0, 0, 0, 0, time.UTC), []byte{0x05, 0x06}, true},
		{int64(4), "00340", "delta plot", time.Date(2024, 1, 4, 0, 0, 0, 0, time.UTC), []byte{0x07, 0x08}, false},
	}
}

// ENG-GO-001: CI-hermetic test exercising Go-level post-fetch quarantine (status == 1) across all
// row positions without external fixtures or t.Skip.
func TestPostFetchQuarantinePreservesAdjacentRows(t *testing.T) {
	cols := defaultSynthCols()
	baseCells := standardFourValidCellSets()
	wantAll := expectedStandardRows()

	// Verify baseline uncorrupted synthetic database decodes all 4 rows cleanly.
	var cleanPageRows []synthPageRow
	for _, cells := range baseCells {
		cleanPageRows = append(cleanPageRows, synthPageRow{Raw: packSynthJet4Row(cols, cells, len(cols))})
	}
	cleanPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{
		buildSynthJet4DataPage(4, cleanPageRows),
	}, nil)
	cleanDB, err := Open(cleanPath)
	if err != nil {
		t.Fatalf("Open synthetic .accdb: %v", err)
	}
	_, gotClean, err := cleanDB.ReadAll(synthQuarantineTable)
	if err != nil {
		t.Fatalf("ReadAll synthetic .accdb: %v", err)
	}
	if !reflect.DeepEqual(gotClean, wantAll) {
		t.Fatalf("baseline rows mismatch:\n got: %#v\nwant: %#v", gotClean, wantAll)
	}

	type postFetchCase struct {
		name      string
		mutateRow func(cells []synthCell) []synthCell
		configure func(r *Reader, badRow int)
	}

	cases := []postFetchCase{
		{
			name: "PostFetchCheckHook",
			mutateRow: func(cells []synthCell) []synthCell {
				return cells
			},
			configure: func(r *Reader, badRow int) {
				r.postFetchCheck = func(rowNumber int, _ Row) error {
					if rowNumber == badRow {
						return errors.New("forced post-fetch quarantine")
					}
					return nil
				}
			},
		},
		{
			name: "OversizedOLEBlob",
			mutateRow: func(cells []synthCell) []synthCell {
				hdr := make([]byte, 12)
				// > 32 MiB inline/header length passes mdb_xfer_bound_ole (status==1) and fails go_mdb_blob.
				binary.LittleEndian.PutUint32(hdr[0:4], 0x80000000|(33*1024*1024))
				cells[4] = synthCell{Raw: hdr}
				return cells
			},
		},
		{
			name: "CorruptOLELvalPointer",
			mutateRow: func(cells []synthCell) []synthCell {
				hdr := make([]byte, 12)
				// Single-page OLE pointing to page 1 row 99 (invalid row index on page 1 -> GO_MDB_ERROR_ROW in go_mdb_blob).
				binary.LittleEndian.PutUint32(hdr[0:4], 0x40000004)
				binary.LittleEndian.PutUint32(hdr[4:8], (1<<8)|99)
				cells[4] = synthCell{Raw: hdr}
				return cells
			},
		},
		{
			name: "DateTimeLayoutParseFailure",
			mutateRow: func(cells []synthCell) []synthCell {
				cells[1] = synthTextCell("not-a-datetime")
				return cells
			},
			configure: func(r *Reader, _ int) {
				r.Columns[1].Type = "datetime"
			},
		},
		{
			name: "StrconvParseIntFailure",
			mutateRow: func(cells []synthCell) []synthCell {
				cells[1] = synthTextCell("2019pb")
				return cells
			},
			configure: func(r *Reader, _ int) {
				// Valid rows have "00337".."00340" which parse as int64; "2019pb" fails strconv.ParseInt.
				r.Columns[1].Type = "integer"
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			for bad := 1; bad <= len(baseCells); bad++ {
				pageRows := make([]synthPageRow, len(baseCells))
				for i, orig := range baseCells {
					copied := append([]synthCell(nil), orig...)
					if tc.name == "DateTimeLayoutParseFailure" && i+1 != bad {
						copied[1] = synthTextCell("2024-01-0" + string(rune('1'+i)) + " 00:00:00")
					}
					if i+1 == bad {
						copied = tc.mutateRow(copied)
					}
					pageRows[i] = synthPageRow{Raw: packSynthJet4Row(cols, copied, len(cols))}
				}
				dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{
					buildSynthJet4DataPage(4, pageRows),
				}, nil)
				db, err := Open(dbPath)
				if err != nil {
					t.Fatal(err)
				}

				// 1. Default fail-closed Reader must surface the error rather than skipping.
				failReader, err := db.Scan(synthQuarantineTable)
				if err != nil {
					t.Fatal(err)
				}
				if tc.configure != nil {
					tc.configure(failReader, bad)
				}
				for failReader.Next() {
				}
				if failReader.Err() == nil {
					failReader.Close()
					t.Fatalf("row %d: expected fail-closed Reader error without EnableRowQuarantine", bad)
				}
				failReader.Close()

				// 2. Quarantine-enabled Reader must quarantine ONLY row `bad` and preserve row `bad+1`.
				reader, err := db.Scan(synthQuarantineTable)
				if err != nil {
					t.Fatal(err)
				}
				reader.EnableRowQuarantine()
				if tc.configure != nil {
					tc.configure(reader, bad)
				}
				var got []Row
				for reader.Next() {
					got = append(got, append(Row(nil), reader.Row()...))
				}
				if err := reader.Err(); err != nil {
					reader.Close()
					t.Fatalf("row %d: unexpected Err() with quarantine enabled: %v", bad, err)
				}
				reader.Close()

				want := make([]Row, 0, len(wantAll)-1)
				for i, r := range wantAll {
					if i+1 == bad {
						continue
					}
					expectedRow := append(Row(nil), r...)
					switch tc.name {
					case "StrconvParseIntFailure":
						expectedRow[1] = int64(337 + i)
					case "DateTimeLayoutParseFailure":
						expectedRow[1] = time.Date(2024, 1, 1+i, 0, 0, 0, 0, time.UTC)
					}
					want = append(want, expectedRow)
				}
				if !reflect.DeepEqual(got, want) {
					t.Fatalf("quarantining row %d:\n got: %#v\nwant: %#v", bad, got, want)
				}
				if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != bad {
					t.Fatalf("quarantining row %d: Quarantined = %+v", bad, reader.Quarantined)
				}
				if len(got)+len(reader.Quarantined) != len(wantAll) {
					t.Fatalf("imported (%d) + quarantined (%d) != total (%d)", len(got), len(reader.Quarantined), len(wantAll))
				}
			}
		})
	}
}

// ENG-GO-001: CI-hermetic test exercising C-level quarantine (status < 0: GO_MDB_ERROR_TEXT &
// GO_MDB_ERROR_ROW) across all row positions, multi-page boundaries, deleted slots, and pre-row state.
func TestCLevelQuarantinePreservesAdjacentRowsAndBounds(t *testing.T) {
	cols := defaultSynthCols()
	baseCells := standardFourValidCellSets()
	wantAll := expectedStandardRows()

	type cLevelCase struct {
		name        string
		buildBadRaw func(cols []synthColumnDef, orig []synthCell) []byte
		wantReason  string
	}

	cases := []cLevelCase{
		{
			name: "Text_OddByteUCS2",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				cells[1] = synthCell{Raw: []byte{'A'}}
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid, incomplete, or oversized Access text encoding",
		},
		{
			name: "Text_IncompleteCompressedUnicode",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				cells[1] = synthCell{Raw: []byte{0xff, 0xfe, 0x00, 0x41}}
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid, incomplete, or oversized Access text encoding",
		},
		{
			name: "Text_EmbeddedNUL",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				cells[1] = synthCell{Raw: []byte{'A', 0x00, 0x00, 0x00}}
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid, incomplete, or oversized Access text encoding",
		},
		{
			name: "Text_OversizedMemoHeader",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				hdr := make([]byte, 16)
				// > GO_MDB_BIND_SIZE / 2 (32768) triggers GO_MDB_ERROR_TEXT in mdb_memo_to_string.
				binary.LittleEndian.PutUint32(hdr[0:4], 0x80000000|40000)
				cells[2] = synthCell{Raw: hdr}
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid, incomplete, or oversized Access text encoding",
		},
		{
			name: "Row_CrackBitmaskLargerThanRowSize",
			buildBadRaw: func(_ []synthColumnDef, _ []synthCell) []byte {
				// 4-byte row claiming row_cols=200 (bitmask_sz=25 > row_size=4, even when row_end ~4095).
				raw := make([]byte, 4)
				binary.LittleEndian.PutUint16(raw[0:2], 200)
				return raw
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_CrackVarColsExceedRowSpan",
			buildBadRaw: func(_ []synthColumnDef, _ []synthCell) []byte {
				// 12-byte row with row_cols=6 (bitmask_sz=1) and row_var_cols=100 (100*2 < row_end, but > row_end-row_start).
				raw := make([]byte, 12)
				binary.LittleEndian.PutUint16(raw[0:2], 6)
				binary.LittleEndian.PutUint16(raw[9:11], 100)
				raw[11] = 0x3f
				return raw
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_CrackVarColsGreaterThanRowCols",
			buildBadRaw: func(_ []synthColumnDef, _ []synthCell) []byte {
				// Enough bytes for mdb_crack_row4 (row_var_cols=2), but row_cols=1 < row_var_cols=2.
				raw := make([]byte, 24)
				binary.LittleEndian.PutUint16(raw[0:2], 1)
				binary.LittleEndian.PutUint16(raw[21:23], 2)
				return raw
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_CrackReversedVarColOffsets",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				raw := packSynthJet4Row(cols, orig, len(cols))
				// Corrupt EOD / var_col_offsets so var_col_offsets[1] < var_col_offsets[0] (negative siz).
				bitmaskSz := (len(cols) + 7) / 8
				rowEnd := len(raw) - 1
				// var_col_offsets[0] at rowEnd - bitmaskSz - 3; var_col_offsets[1] at rowEnd - bitmaskSz - 5.
				binary.LittleEndian.PutUint16(raw[rowEnd-bitmaskSz-3:], 20)
				binary.LittleEndian.PutUint16(raw[rowEnd-bitmaskSz-5:], 14)
				return raw
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_CrackSpanPastRowEnd",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				raw := packSynthJet4Row(cols, orig, len(cols))
				bitmaskSz := (len(cols) + 7) / 8
				rowEnd := len(raw) - 1
				// Set EOD (var_col_offsets[3]) past len(raw).
				binary.LittleEndian.PutUint16(raw[rowEnd-bitmaskSz-3-3*2:], uint16(len(raw)+64))
				return raw
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_InvalidDateTimeNaN",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				cells[3] = synthFloat64Cell(math.NaN())
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_InvalidInlineMemoLengthMismatch",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				hdr := make([]byte, 16)
				binary.LittleEndian.PutUint32(hdr[0:4], 0x80000000|99) // claims 99 bytes, only 4 present
				cells[2] = synthCell{Raw: hdr}
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid Access source row metadata",
		},
		{
			name: "Row_ShortOLEHeader",
			buildBadRaw: func(cols []synthColumnDef, orig []synthCell) []byte {
				cells := append([]synthCell(nil), orig...)
				cells[4] = synthCell{Raw: []byte{1, 2, 3, 4, 5, 6}} // < MDB_MEMO_OVERHEAD (12)
				return packSynthJet4Row(cols, cells, len(cols))
			},
			wantReason: "invalid Access source row metadata",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			for bad := 1; bad <= len(baseCells); bad++ {
				pageRows := make([]synthPageRow, len(baseCells))
				for i, orig := range baseCells {
					if i+1 == bad {
						pageRows[i] = synthPageRow{Raw: tc.buildBadRaw(cols, orig)}
					} else {
						pageRows[i] = synthPageRow{Raw: packSynthJet4Row(cols, orig, len(cols))}
					}
				}
				dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{
					buildSynthJet4DataPage(4, pageRows),
				}, nil)
				db, err := Open(dbPath)
				if err != nil {
					t.Fatal(err)
				}

				// Fail-closed check when quarantine is disabled.
				failReader, err := db.Scan(synthQuarantineTable)
				if err != nil {
					t.Fatal(err)
				}
				for failReader.Next() {
				}
				if failReader.Err() == nil {
					failReader.Close()
					t.Fatalf("row %d: expected error without EnableRowQuarantine", bad)
				}
				failReader.Close()

				// Quarantine check: ONLY row `bad` is quarantined; row `bad+1` is never skipped.
				reader, err := db.Scan(synthQuarantineTable)
				if err != nil {
					t.Fatal(err)
				}
				reader.EnableRowQuarantine()
				var got []Row
				for reader.Next() {
					got = append(got, append(Row(nil), reader.Row()...))
				}
				if err := reader.Err(); err != nil {
					reader.Close()
					t.Fatalf("row %d: unexpected Err(): %v", bad, err)
				}
				reader.Close()

				want := append(append([]Row(nil), wantAll[:bad-1]...), wantAll[bad:]...)
				if !reflect.DeepEqual(got, want) {
					t.Fatalf("quarantining row %d:\n got: %#v\nwant: %#v", bad, got, want)
				}
				if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != bad || reader.Quarantined[0].Reason != tc.wantReason {
					t.Fatalf("quarantining row %d: Quarantined = %+v, want row %d reason %q", bad, reader.Quarantined, bad, tc.wantReason)
				}
			}
		})
	}

	t.Run("FindRowInvalidOffsetPreservesNextRow", func(t *testing.T) {
		// Construct a 3-row page where:
		// - Row 0 spans [3700..4095] with data at [3700..3760] and trailer at [4075..4095], leaving [3800..4050] unused.
		// - Row 1 has start offset 4000 (> Row 0's start 3700), so mdb_find_row returns -1 on Row 1.
		// - Row 2 spans [3900..3999] (next_start = Row 1's start = 4000) inside the unused middle region and decodes cleanly.
		pg := make([]byte, synthPageSize)
		pg[0] = synthPageData
		binary.LittleEndian.PutUint32(pg[4:8], 4)
		binary.LittleEndian.PutUint16(pg[0x0c:0x0e], 3)

		row0Packed := packSynthJet4Row(cols, baseCells[0], len(cols))
		row2Packed := packSynthJet4Row(cols, baseCells[2], len(cols))

		// Expand Row 0 to 396 bytes [3700..4095] by inserting unused gap between EOD and trailer.
		const trailerLen = 2 + 3*2 + 2 + 1 // EOD + 3 var_col_offsets + row_var_cols + 1-byte nullmask = 11 bytes
		row0DataPart := row0Packed[:len(row0Packed)-trailerLen]
		row0Trailer := row0Packed[len(row0Packed)-trailerLen:]
		copy(pg[3700:], row0DataPart)
		copy(pg[4096-trailerLen:], row0Trailer)

		// Place Row 2 at [4000-len(row2Packed) .. 3999] so next_start=4000 yields exact row2Packed.
		row2Start := 4000 - len(row2Packed)
		copy(pg[row2Start:4000], row2Packed)

		binary.LittleEndian.PutUint16(pg[0x0e:], 3700)              // Row 0 start = 3700, next_start = 4096
		binary.LittleEndian.PutUint16(pg[0x10:], 4000)              // Row 1 start = 4000 > next_start(3700) -> mdb_find_row < 0
		binary.LittleEndian.PutUint16(pg[0x12:], uint16(row2Start)) // Row 2 start = row2Start, next_start = 4000

		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, nil)
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			reader.Close()
			t.Fatal(err)
		}
		reader.Close()

		want := []Row{wantAll[0], wantAll[2]}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("FindRow quarantine:\n got: %#v\nwant: %#v", got, want)
		}
		if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != 2 {
			t.Fatalf("FindRow Quarantined = %+v", reader.Quarantined)
		}
	})

	t.Run("MultiPageAndEmptyPageBoundaryQuarantine", func(t *testing.T) {
		// Page 5: Row 1 valid, Row 2 C-level corrupt (last row on page 5).
		// Page 6: 0 rows (empty data page).
		// Page 7: Row 3 C-level corrupt (first row on page 7), Row 4 valid.
		badRow2 := append([]synthCell(nil), baseCells[1]...)
		badRow2[1] = synthCell{Raw: []byte{'X'}} // odd UCS-2 byte -> GO_MDB_ERROR_TEXT
		badRow3 := append([]synthCell(nil), baseCells[2]...)
		badRow3[3] = synthFloat64Cell(math.Inf(1)) // +Inf datetime -> GO_MDB_ERROR_ROW

		pg5 := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, baseCells[0], len(cols))},
			{Raw: packSynthJet4Row(cols, badRow2, len(cols))},
		})
		pg6Empty := buildSynthJet4DataPage(4, nil)
		pg7 := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, badRow3, len(cols))},
			{Raw: packSynthJet4Row(cols, baseCells[3], len(cols))},
		})

		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg5, pg6Empty, pg7}, nil)
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			reader.Close()
			t.Fatal(err)
		}
		reader.Close()

		want := []Row{wantAll[0], wantAll[3]}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("multi-page quarantine:\n got: %#v\nwant: %#v", got, want)
		}
		if len(reader.Quarantined) != 2 || reader.Quarantined[0].RowNumber != 2 || reader.Quarantined[1].RowNumber != 3 {
			t.Fatalf("multi-page Quarantined = %+v", reader.Quarantined)
		}
	})

	t.Run("DeletedRowBeforeCorruptRowDoesNotSkipValidRow", func(t *testing.T) {
		badCells := append([]synthCell(nil), baseCells[1]...)
		badCells[1] = synthCell{Raw: []byte{'Z'}}
		pg := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, baseCells[0], len(cols)), Flags: 0x4000}, // deleted slot
			{Raw: packSynthJet4Row(cols, badCells, len(cols))},                    // RowNumber 1 (quarantined)
			{Raw: packSynthJet4Row(cols, baseCells[2], len(cols))},                // RowNumber 2 (valid)
		})
		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, nil)
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			reader.Close()
			t.Fatal(err)
		}
		reader.Close()

		if !reflect.DeepEqual(got, []Row{wantAll[2]}) {
			t.Fatalf("got %#v, want %#v", got, []Row{wantAll[2]})
		}
		if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != 1 {
			t.Fatalf("Quarantined = %+v", reader.Quarantined)
		}
	})

	t.Run("PreRowErrorAtCurRowZeroDoesNotSkipRowZero", func(t *testing.T) {
		pg := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, baseCells[0], len(cols))},
			{Raw: packSynthJet4Row(cols, baseCells[1], len(cols))},
		})
		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, nil)
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		if cur := nativeCurRowForTest(reader); cur != 0 {
			reader.Close()
			t.Fatalf("initial cur_row = %d, want 0", cur)
		}
		// Simulate mdb->go_error occurring before mdb_read_row when cur_row == 0 (ENG-GO-001 Defect 3.1).
		injectPreRowErrorForTest(reader)

		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			reader.Close()
			t.Fatal(err)
		}
		reader.Close()

		want := []Row{wantAll[0], wantAll[1]}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("pre-row error skipped row 0:\n got: %#v\nwant: %#v", got, want)
		}
	})

	t.Run("ConsecutiveMixedCAndGoQuarantines", func(t *testing.T) {
		cTextBad := append([]synthCell(nil), baseCells[1]...)
		cTextBad[1] = synthCell{Raw: []byte{'Q'}} // C-level GO_MDB_ERROR_TEXT (row 2)

		goBlobBad := append([]synthCell(nil), baseCells[2]...)
		oleHdr := make([]byte, 12)
		binary.LittleEndian.PutUint32(oleHdr[0:4], 0x80000000|(33*1024*1024))
		goBlobBad[4] = synthCell{Raw: oleHdr} // Go-level post-fetch oversized OLE (row 3)

		cRowBad := make([]byte, 4)
		binary.LittleEndian.PutUint16(cRowBad[0:2], 200) // C-level mdb_crack_row GO_MDB_ERROR_ROW (row 4)

		row5Valid := validSynthCells(5, "00341", "echo plot", 45296, []byte{0x09, 0x0a}, true)
		wantRow5 := Row{int64(5), "00341", "echo plot", time.Date(2024, 1, 5, 0, 0, 0, 0, time.UTC), []byte{0x09, 0x0a}, true}

		pg := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, baseCells[0], len(cols))},
			{Raw: packSynthJet4Row(cols, cTextBad, len(cols))},
			{Raw: packSynthJet4Row(cols, goBlobBad, len(cols))},
			{Raw: cRowBad},
			{Raw: packSynthJet4Row(cols, row5Valid, len(cols))},
		})
		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, nil)
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			reader.Close()
			t.Fatal(err)
		}
		reader.Close()

		want := []Row{wantAll[0], wantRow5}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("consecutive mixed quarantines:\n got: %#v\nwant: %#v", got, want)
		}
		if len(reader.Quarantined) != 3 ||
			reader.Quarantined[0].RowNumber != 2 ||
			reader.Quarantined[1].RowNumber != 3 ||
			reader.Quarantined[2].RowNumber != 4 {
			t.Fatalf("Quarantined = %+v", reader.Quarantined)
		}
		if len(got)+len(reader.Quarantined) != 5 {
			t.Fatalf("imported + quarantined = %d, want 5", len(got)+len(reader.Quarantined))
		}
	})

	t.Run("FatalIOErrorIsNotQuarantined", func(t *testing.T) {
		pg := buildSynthJet4DataPage(4, []synthPageRow{
			{Raw: packSynthJet4Row(cols, baseCells[0], len(cols))},
		})
		// Usage map advertises page 5 (valid) and page 20 (beyond EOF -> GO_MDB_ERROR_READ).
		dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, []int{5, 20})
		db, err := Open(dbPath)
		if err != nil {
			t.Fatal(err)
		}
		reader, err := db.Scan(synthQuarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		scanErr := reader.Err()
		reader.Close()
		if scanErr == nil || !strings.Contains(scanErr.Error(), "Access source read error") {
			t.Fatalf("expected fatal Access source read error, got %v", scanErr)
		}
		if len(reader.Quarantined) != 0 {
			t.Fatalf("I/O error must not be quarantined, got %+v", reader.Quarantined)
		}
		if !reflect.DeepEqual(got, []Row{wantAll[0]}) {
			t.Fatalf("got rows before I/O failure = %#v, want %#v", got, []Row{wantAll[0]})
		}
	})
}

// ENG-GO-001 Acceptance #3: rows written prior to ALTER TABLE ADD COLUMN have row_cols < num_cols
// and bitmask_sz < (num_cols+7)/8; trailing columns must decode as NULL without indexing past row_end.
func TestPreAlterTableShortNullmaskDoesNotReadOutOfBounds(t *testing.T) {
	cols := []synthColumnDef{
		{Name: "ID", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "Code", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added2", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added3", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added4", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added5", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added6", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added7", Type: synthColText, IsFixed: false, Size: 16},
		{Name: "Added8", Type: synthColText, IsFixed: false, Size: 16},  // col_num=8 -> byte_num=1 >= bitmask_sz=1
		{Name: "Added9", Type: synthColLongInt, IsFixed: true, Size: 4}, // col_num=9 -> byte_num=1 >= bitmask_sz=1
	}

	// Row 0 is placed at the very end of the 4096-byte page (row_end = 4095) with rowCols = 2 (bitmask_sz = 1).
	legacyRow := packSynthJet4Row(cols, []synthCell{
		synthInt32Cell(101),
		synthTextCell("00337"),
	}, 2)
	fullRow := packSynthJet4Row(cols, []synthCell{
		synthInt32Cell(102),
		synthTextCell("00338"),
		synthTextCell("v2"),
		synthTextCell("v3"),
		synthTextCell("v4"),
		synthTextCell("v5"),
		synthTextCell("v6"),
		synthTextCell("v7"),
		synthTextCell("v8"),
		synthInt32Cell(999),
	}, len(cols))

	pg := buildSynthJet4DataPage(4, []synthPageRow{
		{Raw: legacyRow},
		{Raw: fullRow},
	})
	dbPath := writeSynthJet4Database(t, synthQuarantineTable, cols, [][]byte{pg}, nil)
	db, err := Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	_, rows, err := db.ReadAll(synthQuarantineTable)
	if err != nil {
		t.Fatal(err)
	}
	want := []Row{
		{int64(101), "00337", nil, nil, nil, nil, nil, nil, nil, nil},
		{int64(102), "00338", "v2", "v3", "v4", "v5", "v6", "v7", "v8", int64(999)},
	}
	if !reflect.DeepEqual(rows, want) {
		t.Fatalf("short nullmask rows mismatch:\n got: %#v\nwant: %#v", rows, want)
	}
}

func extractZipMemberReadOnly(t *testing.T, zipPath, memberSuffix string) string {
	t.Helper()
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	defer zr.Close()
	for _, f := range zr.File {
		if strings.HasSuffix(strings.ToLower(f.Name), strings.ToLower(memberSuffix)) {
			rc, err := f.Open()
			if err != nil {
				t.Fatal(err)
			}
			defer rc.Close()
			dst := filepath.Join(t.TempDir(), filepath.Base(f.Name))
			out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o400)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := io.Copy(out, rc); err != nil {
				out.Close()
				t.Fatal(err)
			}
			if err := out.Close(); err != nil {
				t.Fatal(err)
			}
			return dst
		}
	}
	t.Fatalf("member %q not found in %s", memberSuffix, zipPath)
	return ""
}

// Optional read-only verification against local developer reference archives when present on disk.
// Never calls t.Skip when external archives are absent (e.g. in CI or when VPRO_EXTERNAL_ARCHIVE_ROOT
// points to an empty directory).
func TestOptionalLocalReferenceArchivesQuarantineAdjacency(t *testing.T) {
	workRoot := os.Getenv("VPRO_EXTERNAL_ARCHIVE_ROOT")
	if workRoot == "" {
		if home, err := os.UserHomeDir(); err == nil {
			workRoot = filepath.Join(home, "Work")
		}
	}
	if workRoot == "" {
		return
	}

	templatePath := filepath.Join(workRoot, "VPRO_ACCESS", "VPro64", "Templates", "TemplateVPro15.accdb")
	if _, err := os.Stat(templatePath); err == nil {
		t.Run("TemplateVPro15", func(t *testing.T) {
			db, err := Open(templatePath)
			if err != nil {
				t.Fatal(err)
			}
			_, all, err := db.ReadAll("VPro15_Audit")
			if err != nil {
				t.Fatal(err)
			}
			if len(all) != 3 {
				t.Fatalf("want 3 rows in VPro15_Audit, got %d", len(all))
			}
			for bad := 1; bad <= len(all); bad++ {
				reader, err := db.Scan("VPro15_Audit")
				if err != nil {
					t.Fatal(err)
				}
				reader.EnableRowQuarantine()
				reader.postFetchCheck = func(rowNumber int, _ Row) error {
					if rowNumber == bad {
						return errors.New("forced post-fetch quarantine")
					}
					return nil
				}
				var got []Row
				for reader.Next() {
					got = append(got, append(Row(nil), reader.Row()...))
				}
				if err := reader.Err(); err != nil {
					reader.Close()
					t.Fatal(err)
				}
				reader.Close()
				want := append(append([]Row(nil), all[:bad-1]...), all[bad:]...)
				if !reflect.DeepEqual(got, want) {
					t.Fatalf("quarantining row %d: got %d rows, want %d", bad, len(got), len(want))
				}
				if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != bad {
					t.Fatalf("Quarantined = %+v", reader.Quarantined)
				}
			}
		})
	}

	taxaZip := filepath.Join(workRoot, "becweb_standards_2025_2026", "BCPlantTaxa2025_access.zip")
	if _, err := os.Stat(taxaZip); err == nil {
		t.Run("BCPlantTaxonomy", func(t *testing.T) {
			accdbPath := extractZipMemberReadOnly(t, taxaZip, ".accdb")
			db, err := Open(accdbPath)
			if err != nil {
				t.Fatal(err)
			}
			rCheck, err := db.Scan("USysAllSpecs")
			if err != nil {
				t.Fatal(err)
			}
			sciCol := 0
			for i, c := range rCheck.Columns {
				if c.Name == "ScientificName" {
					sciCol = i
				}
			}
			var scis []any
			for i := 0; i < 6 && rCheck.Next(); i++ {
				scis = append(scis, rCheck.Row()[sciCol])
			}
			if err := rCheck.Err(); err != nil {
				rCheck.Close()
				t.Fatal(err)
			}
			rCheck.Close()

			r4, err := db.Scan("USysAllSpecs")
			if err != nil {
				t.Fatal(err)
			}
			defer r4.Close()
			r4.EnableRowQuarantine()
			r4.Columns[0].Type = "integer"
			var gotScis []any
			for i := 0; i < 4 && r4.Next(); i++ {
				gotScis = append(gotScis, r4.Row()[sciCol])
			}
			// scis[2] ("Abies bifolia") is 1-based RowNumber 3; scis[3] ("Abies excelsior") is 1-based RowNumber 4.
			if gotScis[2] != scis[3] {
				t.Fatalf("post-fetch quarantine of 0-based row 2 (%q) skipped valid row 3 (%q) and jumped to (%q)",
					scis[2], scis[3], gotScis[2])
			}
			if len(r4.Quarantined) != 1 || r4.Quarantined[0].RowNumber != 3 {
				t.Fatalf("Quarantined = %+v", r4.Quarantined)
			}
		})
	}

	becMasterPath := filepath.Join(workRoot, "VPRO_ACCESS_1", "VPro64", "BECMaster_fixing.accdb")
	if _, err := os.Stat(becMasterPath); err == nil {
		t.Run("BECMasterFixing", func(t *testing.T) {
			db, err := Open(becMasterPath)
			if err != nil {
				t.Fatal(err)
			}
			baseReader, err := db.Scan("BECMaster_fixing_Env")
			if err != nil {
				t.Fatal(err)
			}
			var firstFivePlots []any
			total := 0
			for baseReader.Next() {
				total++
				if total <= 5 {
					firstFivePlots = append(firstFivePlots, baseReader.Row()[0])
				}
			}
			if err := baseReader.Err(); err != nil {
				baseReader.Close()
				t.Fatal(err)
			}
			baseReader.Close()

			qReader, err := db.Scan("BECMaster_fixing_Env")
			if err != nil {
				t.Fatal(err)
			}
			defer qReader.Close()
			qReader.EnableRowQuarantine()
			qReader.postFetchCheck = func(rowNumber int, _ Row) error {
				if rowNumber == 2 || rowNumber == 500 {
					return errors.New("forced quarantine")
				}
				return nil
			}
			imported := 0
			var gotAfterRow2 any
			for qReader.Next() {
				imported++
				if imported == 2 {
					gotAfterRow2 = qReader.Row()[0]
				}
			}
			if err := qReader.Err(); err != nil {
				t.Fatal(err)
			}
			if imported+len(qReader.Quarantined) != total || len(qReader.Quarantined) != 2 {
				t.Fatalf("imported=%d quarantined=%d total=%d", imported, len(qReader.Quarantined), total)
			}
			if gotAfterRow2 != firstFivePlots[2] {
				t.Fatalf("row after quarantined row 2 = %v, want %v", gotAfterRow2, firstFivePlots[2])
			}
		})
	}
}
