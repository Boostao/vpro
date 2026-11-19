//go:build linux || windows || darwin

package accessreader

import (
	"crypto/rc4"
	"encoding/binary"
	"math"
	"os"
	"path/filepath"
	"testing"
	"unicode/utf16"
)

const (
	synthPageSize     = 4096
	synthJet3PageSize = 2048

	synthPageDB    = 0x00
	synthPageData  = 0x01
	synthPageTable = 0x02

	synthColBool     = 0x01
	synthColByte     = 0x02
	synthColInt      = 0x03
	synthColLongInt  = 0x04
	synthColMoney    = 0x05
	synthColFloat    = 0x06
	synthColDouble   = 0x07
	synthColDateTime = 0x08
	synthColBinary   = 0x09
	synthColText     = 0x0a
	synthColOLE      = 0x0b
	synthColMemo     = 0x0c
	synthColNumeric  = 0x10
)

type synthColumnDef struct {
	Name    string
	Type    byte
	IsFixed bool
	Size    uint16
	Scale   byte
	Prec    byte
}

type synthCell struct {
	IsNull bool
	Bool   bool
	Raw    []byte
}

type synthPageRow struct {
	Raw          []byte
	Flags        uint16
	HasRawOffset bool
	RawOffset    uint16
}

func encodeUCS2LE(s string) []byte {
	u16 := utf16.Encode([]rune(s))
	out := make([]byte, len(u16)*2)
	for i, v := range u16 {
		binary.LittleEndian.PutUint16(out[i*2:], v)
	}
	return out
}

func synthByteCell(v byte) synthCell {
	return synthCell{Raw: []byte{v}}
}

func synthInt16Cell(v int16) synthCell {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, uint16(v))
	return synthCell{Raw: b}
}

func synthInt32Cell(v int32) synthCell {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, uint32(v))
	return synthCell{Raw: b}
}

func synthFloat32Cell(v float32) synthCell {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, math.Float32bits(v))
	return synthCell{Raw: b}
}

func synthFloat64Cell(v float64) synthCell {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, math.Float64bits(v))
	return synthCell{Raw: b}
}

func synthMoneyCell(scaledBy10000 int64) synthCell {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, uint64(scaledBy10000))
	return synthCell{Raw: b}
}

// synthNumericCell encodes a 17-byte Access MDB_NUMERIC cell (byte 0 = 0x80 when negative,
// followed by 4 uint32 little-endian limbs stored in most-significant-word-first order).
func synthNumericCell(negative bool, lowWord uint64) synthCell {
	raw := make([]byte, 17)
	if negative {
		raw[0] = 0x80
	}
	binary.LittleEndian.PutUint32(raw[9:13], uint32(lowWord>>32))
	binary.LittleEndian.PutUint32(raw[13:17], uint32(lowWord))
	return synthCell{Raw: raw}
}

func synthBoolCell(v bool) synthCell {
	return synthCell{Bool: v}
}

func synthNullCell() synthCell {
	return synthCell{IsNull: true}
}

func synthTextCell(s string) synthCell {
	return synthCell{Raw: encodeUCS2LE(s)}
}

func synthJet3TextCell(s string) synthCell {
	return synthCell{Raw: []byte(s)}
}

func synthBinaryCell(payload []byte) synthCell {
	return synthCell{Raw: append([]byte(nil), payload...)}
}

func synthInlineMemoCell(s string) synthCell {
	payload := encodeUCS2LE(s)
	raw := make([]byte, 12+len(payload))
	binary.LittleEndian.PutUint32(raw[0:4], 0x80000000|uint32(len(payload)))
	copy(raw[12:], payload)
	return synthCell{Raw: raw}
}

func synthJet3InlineMemoCell(s string) synthCell {
	payload := []byte(s)
	raw := make([]byte, 12+len(payload))
	binary.LittleEndian.PutUint32(raw[0:4], 0x80000000|uint32(len(payload)))
	copy(raw[12:], payload)
	return synthCell{Raw: raw}
}

func synthInlineOLECell(payload []byte) synthCell {
	raw := make([]byte, 12+len(payload))
	binary.LittleEndian.PutUint32(raw[0:4], 0x80000000|uint32(len(payload)))
	copy(raw[12:], payload)
	return synthCell{Raw: raw}
}

// packSynthJet4Row encodes a physical Jet4/ACE row matching mdb_crack_row / mdb_crack_row4.
// rowCols may be smaller than len(cols) to simulate rows written prior to ALTER TABLE ADD COLUMN.
func packSynthJet4Row(cols []synthColumnDef, cells []synthCell, rowCols int) []byte {
	numTableVarCols := 0
	for _, c := range cols {
		if !c.IsFixed {
			numTableVarCols++
		}
	}

	buf := make([]byte, 2)
	binary.LittleEndian.PutUint16(buf[0:2], uint16(rowCols))

	for i := 0; i < rowCols; i++ {
		if !cols[i].IsFixed {
			continue
		}
		if cols[i].Type == synthColBool || cols[i].Size == 0 {
			continue
		}
		fixedBytes := make([]byte, cols[i].Size)
		if i < len(cells) && !cells[i].IsNull {
			copy(fixedBytes, cells[i].Raw)
		}
		buf = append(buf, fixedBytes...)
	}

	if numTableVarCols > 0 {
		var varOffsets []uint16
		for i := 0; i < rowCols; i++ {
			if cols[i].IsFixed {
				continue
			}
			varOffsets = append(varOffsets, uint16(len(buf)))
			if i < len(cells) && !cells[i].IsNull {
				buf = append(buf, cells[i].Raw...)
			}
		}
		eod := uint16(len(buf))
		var trailer [2]byte
		binary.LittleEndian.PutUint16(trailer[:], eod)
		buf = append(buf, trailer[:]...)
		for i := len(varOffsets) - 1; i >= 0; i-- {
			binary.LittleEndian.PutUint16(trailer[:], varOffsets[i])
			buf = append(buf, trailer[:]...)
		}
		binary.LittleEndian.PutUint16(trailer[:], uint16(len(varOffsets)))
		buf = append(buf, trailer[:]...)
	}

	bitmaskSz := (rowCols + 7) / 8
	nullmask := make([]byte, bitmaskSz)
	for i := 0; i < rowCols; i++ {
		var notNull bool
		if cols[i].Type == synthColBool {
			notNull = i < len(cells) && cells[i].Bool
		} else {
			notNull = i < len(cells) && !cells[i].IsNull
		}
		if notNull {
			nullmask[i/8] |= 1 << (uint(i) % 8)
		}
	}
	buf = append(buf, nullmask...)
	return buf
}

// packSynthJet3Row encodes a physical Jet3 (< 256 byte) row matching mdb_crack_row / mdb_crack_row3.
func packSynthJet3Row(cols []synthColumnDef, cells []synthCell, rowCols int) []byte {
	numTableVarCols := 0
	for _, c := range cols {
		if !c.IsFixed {
			numTableVarCols++
		}
	}

	buf := []byte{byte(rowCols)}
	for i := 0; i < rowCols; i++ {
		if !cols[i].IsFixed {
			continue
		}
		if cols[i].Type == synthColBool || cols[i].Size == 0 {
			continue
		}
		fixedBytes := make([]byte, cols[i].Size)
		if i < len(cells) && !cells[i].IsNull {
			copy(fixedBytes, cells[i].Raw)
		}
		buf = append(buf, fixedBytes...)
	}

	if numTableVarCols > 0 {
		var varOffsets []byte
		for i := 0; i < rowCols; i++ {
			if cols[i].IsFixed {
				continue
			}
			varOffsets = append(varOffsets, byte(len(buf)))
			if i < len(cells) && !cells[i].IsNull {
				buf = append(buf, cells[i].Raw...)
			}
		}
		eod := byte(len(buf))
		buf = append(buf, eod)
		for i := len(varOffsets) - 1; i >= 0; i-- {
			buf = append(buf, varOffsets[i])
		}
		buf = append(buf, byte(len(varOffsets)))
	}

	bitmaskSz := (rowCols + 7) / 8
	nullmask := make([]byte, bitmaskSz)
	for i := 0; i < rowCols; i++ {
		var notNull bool
		if cols[i].Type == synthColBool {
			notNull = i < len(cells) && cells[i].Bool
		} else {
			notNull = i < len(cells) && !cells[i].IsNull
		}
		if notNull {
			nullmask[i/8] |= 1 << (uint(i) % 8)
		}
	}
	buf = append(buf, nullmask...)
	if len(buf) >= 256 {
		panic("synthetic Jet3 row exceeded single-jump 255-byte test helper bound")
	}
	return buf
}

func buildSynthJet4DBPage() []byte {
	pg := make([]byte, synthPageSize)
	pg[0] = synthPageDB
	pg[0x14] = 0x02 // MDB_VER_ACCDB_2007 (Jet4/ACE 4096-byte page constants)
	binary.LittleEndian.PutUint16(pg[0x3c:], 1252)
	binary.LittleEndian.PutUint32(pg[0x3e:], 0) // db_key = 0 (unencrypted pages)
	binary.LittleEndian.PutUint16(pg[0x6e:], 0x0409)

	cipher, err := rc4.NewCipher([]byte{0xC7, 0xDA, 0x39, 0x6B})
	if err != nil {
		panic(err)
	}
	cipher.XORKeyStream(pg[0x18:0x18+128], pg[0x18:0x18+128])
	return pg
}

func buildSynthJet3DBPage() []byte {
	pg := make([]byte, synthJet3PageSize)
	pg[0] = synthPageDB
	pg[0x14] = 0x00 // MDB_VER_JET3 (2048-byte page constants)
	binary.LittleEndian.PutUint16(pg[0x3a:], 0x0409)
	binary.LittleEndian.PutUint16(pg[0x3c:], 1252)
	binary.LittleEndian.PutUint32(pg[0x3e:], 0)

	cipher, err := rc4.NewCipher([]byte{0xC7, 0xDA, 0x39, 0x6B})
	if err != nil {
		panic(err)
	}
	cipher.XORKeyStream(pg[0x18:0x18+126], pg[0x18:0x18+126])
	return pg
}

func buildSynthUsageMapRow(dataPages []int) []byte {
	// Type-0 inline usage map starting at page 0 with a 64-page (8-byte) bitmap.
	m := make([]byte, 5+8)
	m[0] = 0
	binary.LittleEndian.PutUint32(m[1:5], 0)
	for _, pg := range dataPages {
		m[5+pg/8] |= 1 << (uint(pg) % 8)
	}
	return m
}

func buildSynthJet4DataPage(tablePg uint32, rows []synthPageRow) []byte {
	pg := make([]byte, synthPageSize)
	pg[0] = synthPageData
	binary.LittleEndian.PutUint32(pg[4:8], tablePg)
	const rco = 0x0c
	binary.LittleEndian.PutUint16(pg[rco:rco+2], uint16(len(rows)))

	cursor := synthPageSize
	for i, r := range rows {
		cursor -= len(r.Raw)
		if cursor < rco+2+len(rows)*2 {
			panic("synthetic Jet4 data page overflow")
		}
		copy(pg[cursor:cursor+len(r.Raw)], r.Raw)
		entry := uint16(cursor) | r.Flags
		if r.HasRawOffset {
			entry = r.RawOffset
		}
		binary.LittleEndian.PutUint16(pg[rco+2+i*2:], entry)
	}
	return pg
}

func buildSynthJet3DataPage(tablePg uint32, rows []synthPageRow) []byte {
	pg := make([]byte, synthJet3PageSize)
	pg[0] = synthPageData
	binary.LittleEndian.PutUint32(pg[4:8], tablePg)
	const rco = 0x08
	binary.LittleEndian.PutUint16(pg[rco:rco+2], uint16(len(rows)))

	cursor := synthJet3PageSize
	for i, r := range rows {
		cursor -= len(r.Raw)
		if cursor < rco+2+len(rows)*2 {
			panic("synthetic Jet3 data page overflow")
		}
		copy(pg[cursor:cursor+len(r.Raw)], r.Raw)
		entry := uint16(cursor) | r.Flags
		if r.HasRawOffset {
			entry = r.RawOffset
		}
		binary.LittleEndian.PutUint16(pg[rco+2+i*2:], entry)
	}
	return pg
}

func buildSynthJet4TableDefPage(numRows uint32, usageMapPgRow, freeMapPgRow uint32, cols []synthColumnDef) []byte {
	pg := make([]byte, synthPageSize)
	pg[0] = synthPageTable

	var numVarCols uint16
	for _, c := range cols {
		if !c.IsFixed {
			numVarCols++
		}
	}
	binary.LittleEndian.PutUint32(pg[16:20], numRows)
	binary.LittleEndian.PutUint16(pg[43:45], numVarCols)
	binary.LittleEndian.PutUint16(pg[45:47], uint16(len(cols)))
	binary.LittleEndian.PutUint32(pg[47:51], 0) // num_idxs
	binary.LittleEndian.PutUint32(pg[51:55], 0) // num_real_idxs
	binary.LittleEndian.PutUint32(pg[55:59], usageMapPgRow)
	binary.LittleEndian.PutUint32(pg[59:63], freeMapPgRow)

	pos := 63
	var fixedOffset uint16
	var varIdx uint16
	for i, c := range cols {
		entry := pg[pos : pos+25]
		entry[0] = c.Type
		entry[5] = byte(i)
		if !c.IsFixed {
			binary.LittleEndian.PutUint16(entry[7:9], varIdx)
			varIdx++
		}
		binary.LittleEndian.PutUint16(entry[9:11], uint16(i))
		entry[11] = c.Scale
		entry[12] = c.Prec
		if c.IsFixed {
			entry[15] = 0x01
			binary.LittleEndian.PutUint16(entry[21:23], fixedOffset)
			if c.Type != synthColBool {
				binary.LittleEndian.PutUint16(entry[23:25], c.Size)
				fixedOffset += c.Size
			}
		} else {
			entry[15] = 0x00
			binary.LittleEndian.PutUint16(entry[23:25], c.Size)
		}
		pos += 25
	}
	for _, c := range cols {
		nameBytes := encodeUCS2LE(c.Name)
		binary.LittleEndian.PutUint16(pg[pos:pos+2], uint16(len(nameBytes)))
		pos += 2
		copy(pg[pos:pos+len(nameBytes)], nameBytes)
		pos += len(nameBytes)
	}
	return pg
}

func buildSynthJet3TableDefPage(numRows uint32, usageMapPgRow, freeMapPgRow uint32, cols []synthColumnDef) []byte {
	pg := make([]byte, synthJet3PageSize)
	pg[0] = synthPageTable

	var numVarCols uint16
	for _, c := range cols {
		if !c.IsFixed {
			numVarCols++
		}
	}
	binary.LittleEndian.PutUint32(pg[12:16], numRows)
	binary.LittleEndian.PutUint16(pg[23:25], numVarCols)
	binary.LittleEndian.PutUint16(pg[25:27], uint16(len(cols)))
	binary.LittleEndian.PutUint32(pg[27:31], 0)
	binary.LittleEndian.PutUint32(pg[31:35], 0)
	binary.LittleEndian.PutUint32(pg[35:39], usageMapPgRow)
	binary.LittleEndian.PutUint32(pg[39:43], freeMapPgRow)

	pos := 43
	var fixedOffset uint16
	var varIdx uint16
	for i, c := range cols {
		entry := pg[pos : pos+18]
		entry[0] = c.Type
		entry[1] = byte(i)
		if !c.IsFixed {
			binary.LittleEndian.PutUint16(entry[3:5], varIdx)
			varIdx++
		}
		binary.LittleEndian.PutUint16(entry[5:7], uint16(i))
		entry[9] = c.Scale
		entry[10] = c.Prec
		if c.IsFixed {
			entry[13] = 0x01
			binary.LittleEndian.PutUint16(entry[14:16], fixedOffset)
			if c.Type != synthColBool {
				binary.LittleEndian.PutUint16(entry[16:18], c.Size)
				fixedOffset += c.Size
			}
		} else {
			entry[13] = 0x00
			binary.LittleEndian.PutUint16(entry[16:18], c.Size)
		}
		pos += 18
	}
	for _, c := range cols {
		nameBytes := []byte(c.Name)
		pg[pos] = byte(len(nameBytes))
		pos++
		copy(pg[pos:pos+len(nameBytes)], nameBytes)
		pos += len(nameBytes)
	}
	return pg
}

func buildSynthJet4DatabaseBytes(
	tableName string,
	cols []synthColumnDef,
	dataPages [][]byte,
	usageMapOverride []int,
) []byte {
	var totalRows uint32
	userDataPgNums := make([]int, len(dataPages))
	for i, pg := range dataPages {
		userDataPgNums[i] = 5 + i
		totalRows += uint32(binary.LittleEndian.Uint16(pg[0x0c:0x0e]))
	}
	if usageMapOverride != nil {
		userDataPgNums = usageMapOverride
	}

	page1 := buildSynthJet4DataPage(0, []synthPageRow{
		{Raw: buildSynthUsageMapRow([]int{3})},
		{Raw: buildSynthUsageMapRow(nil)},
		{Raw: buildSynthUsageMapRow(userDataPgNums)},
		{Raw: buildSynthUsageMapRow(nil)},
	})

	msysCols := []synthColumnDef{
		{Name: "Id", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "Type", Type: synthColInt, IsFixed: true, Size: 2},
		{Name: "Flags", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "Name", Type: synthColText, IsFixed: false, Size: 255},
		{Name: "LvProp", Type: synthColOLE, IsFixed: false, Size: 0},
	}
	page2 := buildSynthJet4TableDefPage(1, (1<<8)|0, (1<<8)|1, msysCols)
	msysRow := packSynthJet4Row(msysCols, []synthCell{
		synthInt32Cell(4),
		synthInt16Cell(1),
		synthInt32Cell(0),
		synthTextCell(tableName),
		synthNullCell(),
	}, len(msysCols))
	page3 := buildSynthJet4DataPage(2, []synthPageRow{{Raw: msysRow}})
	page4 := buildSynthJet4TableDefPage(totalRows, (1<<8)|2, (1<<8)|3, cols)

	fileBytes := make([]byte, 0, (5+len(dataPages))*synthPageSize)
	fileBytes = append(fileBytes, buildSynthJet4DBPage()...)
	fileBytes = append(fileBytes, page1...)
	fileBytes = append(fileBytes, page2...)
	fileBytes = append(fileBytes, page3...)
	fileBytes = append(fileBytes, page4...)
	for _, pg := range dataPages {
		fileBytes = append(fileBytes, pg...)
	}
	return fileBytes
}

func buildSynthJet3DatabaseBytes(
	tableName string,
	cols []synthColumnDef,
	dataPages [][]byte,
) []byte {
	var totalRows uint32
	userDataPgNums := make([]int, len(dataPages))
	for i, pg := range dataPages {
		userDataPgNums[i] = 5 + i
		totalRows += uint32(binary.LittleEndian.Uint16(pg[0x08:0x0a]))
	}

	page1 := buildSynthJet3DataPage(0, []synthPageRow{
		{Raw: buildSynthUsageMapRow([]int{3})},
		{Raw: buildSynthUsageMapRow(nil)},
		{Raw: buildSynthUsageMapRow(userDataPgNums)},
		{Raw: buildSynthUsageMapRow(nil)},
	})

	msysCols := []synthColumnDef{
		{Name: "Id", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "Type", Type: synthColInt, IsFixed: true, Size: 2},
		{Name: "Flags", Type: synthColLongInt, IsFixed: true, Size: 4},
		{Name: "Name", Type: synthColText, IsFixed: false, Size: 255},
		{Name: "LvProp", Type: synthColOLE, IsFixed: false, Size: 0},
	}
	page2 := buildSynthJet3TableDefPage(1, (1<<8)|0, (1<<8)|1, msysCols)
	msysRow := packSynthJet3Row(msysCols, []synthCell{
		synthInt32Cell(4),
		synthInt16Cell(1),
		synthInt32Cell(0),
		synthJet3TextCell(tableName),
		synthNullCell(),
	}, len(msysCols))
	page3 := buildSynthJet3DataPage(2, []synthPageRow{{Raw: msysRow}})
	page4 := buildSynthJet3TableDefPage(totalRows, (1<<8)|2, (1<<8)|3, cols)

	fileBytes := make([]byte, 0, (5+len(dataPages))*synthJet3PageSize)
	fileBytes = append(fileBytes, buildSynthJet3DBPage()...)
	fileBytes = append(fileBytes, page1...)
	fileBytes = append(fileBytes, page2...)
	fileBytes = append(fileBytes, page3...)
	fileBytes = append(fileBytes, page4...)
	for _, pg := range dataPages {
		fileBytes = append(fileBytes, pg...)
	}
	return fileBytes
}

// writeSynthJet4Database writes a self-contained minimal Jet4/ACE .accdb file in t.TempDir()
// containing MSysObjects (table_pg=2, data_pg=3) and one user table (table_pg=4, data_pg=5..).
func writeSynthJet4Database(
	t *testing.T,
	tableName string,
	cols []synthColumnDef,
	dataPages [][]byte,
	usageMapOverride []int,
) string {
	t.Helper()
	fileBytes := buildSynthJet4DatabaseBytes(tableName, cols, dataPages, usageMapOverride)
	dbPath := filepath.Join(t.TempDir(), "synthetic_fixture.accdb")
	if err := os.WriteFile(dbPath, fileBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	return dbPath
}
