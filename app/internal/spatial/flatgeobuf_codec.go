package spatial

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
)

type fgbColumnDef struct {
	name    string
	colType uint8
}

var spatialFGBColumns = []fgbColumnDef{
	{"PlotNumber", fgbColumnTypeString},       // 0
	{"Lat", fgbColumnTypeDouble},              // 1
	{"Lon", fgbColumnTypeDouble},              // 2
	{"UTMDerivedLat", fgbColumnTypeDouble},    // 3
	{"UTMDerivedLon", fgbColumnTypeDouble},    // 4
	{"DivergenceMeters", fgbColumnTypeDouble}, // 5
	{"Elevation", fgbColumnTypeDouble},        // 6
	{"Slope", fgbColumnTypeDouble},            // 7
	{"Aspect", fgbColumnTypeDouble},           // 8
	{"FieldBGC", fgbColumnTypeString},         // 9
	{"GIS_BGC", fgbColumnTypeString},          // 10
	{"BGCMismatch", fgbColumnTypeBool},        // 11
	{"SiteUnit", fgbColumnTypeString},         // 12
}

// --- Pure-Go FlatBuffers Builder & OGC FlatGeobuf v3 Point Encoder / Decoder ---

type flatBufBuilder struct {
	buf []byte
	pos int // writes grow downward from len(buf) toward 0
}

func newFlatBufBuilder(initialCap int) *flatBufBuilder {
	if initialCap < 256 {
		initialCap = 256
	}
	b := make([]byte, initialCap)
	return &flatBufBuilder{buf: b, pos: initialCap}
}

func (b *flatBufBuilder) used() int {
	return len(b.buf) - b.pos
}

func (b *flatBufBuilder) grow(need int) {
	if b.pos >= need {
		return
	}
	newCap := len(b.buf) * 2
	for newCap-b.used() < need {
		newCap *= 2
	}
	nb := make([]byte, newCap)
	used := b.used()
	copy(nb[newCap-used:], b.buf[b.pos:])
	b.buf = nb
	b.pos = newCap - used
}

func (b *flatBufBuilder) align(size, additionalBytes int) {
	alignSize := ((^(b.used() + additionalBytes)) + 1) & (size - 1)
	b.grow(alignSize)
	for i := 0; i < alignSize; i++ {
		b.pos--
		b.buf[b.pos] = 0
	}
}

func (b *flatBufBuilder) placeUint8(v uint8) int {
	b.grow(1)
	b.pos--
	b.buf[b.pos] = v
	return b.used()
}

func (b *flatBufBuilder) placeUint16(v uint16) int {
	b.align(2, 0)
	b.grow(2)
	b.pos -= 2
	binary.LittleEndian.PutUint16(b.buf[b.pos:], v)
	return b.used()
}

func (b *flatBufBuilder) placeUint32(v uint32) int {
	b.align(4, 0)
	b.grow(4)
	b.pos -= 4
	binary.LittleEndian.PutUint32(b.buf[b.pos:], v)
	return b.used()
}

func (b *flatBufBuilder) placeUint64(v uint64) int {
	b.align(8, 0)
	b.grow(8)
	b.pos -= 8
	binary.LittleEndian.PutUint64(b.buf[b.pos:], v)
	return b.used()
}

func (b *flatBufBuilder) placeUOffset(targetOffsetFromEnd int) int {
	b.align(4, 0)
	b.grow(4)
	b.pos -= 4
	slotFromEnd := b.used()
	rel := uint32(slotFromEnd - targetOffsetFromEnd)
	binary.LittleEndian.PutUint32(b.buf[b.pos:], rel)
	return slotFromEnd
}

func (b *flatBufBuilder) createString(s string) int {
	b.align(4, len(s)+1)
	b.grow(len(s) + 1)
	b.pos--
	b.buf[b.pos] = 0
	b.pos -= len(s)
	copy(b.buf[b.pos:], s)
	return b.placeUint32(uint32(len(s)))
}

func (b *flatBufBuilder) createByteVector(data []byte) int {
	b.align(4, len(data))
	b.grow(len(data))
	b.pos -= len(data)
	copy(b.buf[b.pos:], data)
	return b.placeUint32(uint32(len(data)))
}

func (b *flatBufBuilder) createFloat64Vector(vals []float64) int {
	b.align(8, len(vals)*8)
	for i := len(vals) - 1; i >= 0; i-- {
		b.grow(8)
		b.pos -= 8
		binary.LittleEndian.PutUint64(b.buf[b.pos:], math.Float64bits(vals[i]))
	}
	// Note: vector length prefix is 4 bytes immediately preceding the 8-byte aligned elements
	b.grow(4)
	b.pos -= 4
	binary.LittleEndian.PutUint32(b.buf[b.pos:], uint32(len(vals)))
	return b.used()
}

func (b *flatBufBuilder) createOffsetVector(elemOffsetsFromEnd []int) int {
	b.align(4, len(elemOffsetsFromEnd)*4)
	for i := len(elemOffsetsFromEnd) - 1; i >= 0; i-- {
		b.placeUOffset(elemOffsetsFromEnd[i])
	}
	return b.placeUint32(uint32(len(elemOffsetsFromEnd)))
}

func (b *flatBufBuilder) finishTable(tableEndFromEnd int, fieldSlotsFromEnd []int) int {
	// Ensure 4-byte alignment for soffset_t at start of table
	b.align(4, 4)
	b.grow(4)
	b.pos -= 4
	tableStartFromEnd := b.used()
	objectSize := tableStartFromEnd - tableEndFromEnd

	vtableLen := 4 + 2*len(fieldSlotsFromEnd)
	// Write vtable immediately before tableStart in final byte order
	for i := len(fieldSlotsFromEnd) - 1; i >= 0; i-- {
		slot := fieldSlotsFromEnd[i]
		var rel uint16
		if slot != 0 {
			rel = uint16(tableStartFromEnd - slot)
		}
		b.placeUint16(rel)
	}
	b.placeUint16(uint16(objectSize))
	vtableStartFromEnd := b.placeUint16(uint16(vtableLen))

	// Patch soffset_t at tableStart: tablePos - vtablePos = vtableStartFromEnd - tableStartFromEnd
	soffset := int32(vtableStartFromEnd - tableStartFromEnd)
	tableStartIdx := len(b.buf) - tableStartFromEnd
	binary.LittleEndian.PutUint32(b.buf[tableStartIdx:tableStartIdx+4], uint32(soffset))
	return tableStartFromEnd
}

func (b *flatBufBuilder) reset() {
	b.pos = len(b.buf)
}

func (b *flatBufBuilder) finishRootView(rootTableFromEnd int) []byte {
	b.align(4, 4)
	b.placeUOffset(rootTableFromEnd)
	return b.buf[b.pos:]
}

func (b *flatBufBuilder) finishRoot(rootTableFromEnd int) []byte {
	view := b.finishRootView(rootTableFromEnd)
	out := make([]byte, len(view))
	copy(out, view)
	return out
}

func buildFGBHeaderFlatBuffer(layerName string, envelope [4]float64, cols []fgbColumnDef, featuresCount uint64) []byte {
	b := newFlatBufBuilder(1024)
	nameOff := b.createString(layerName)
	var envOff int
	if featuresCount > 0 {
		envOff = b.createFloat64Vector(envelope[:])
	}

	colTableOffsets := make([]int, len(cols))
	for i, col := range cols {
		cNameOff := b.createString(col.name)
		tEnd := b.used()
		var slots [2]int // Column table: 0=name:string, 1=type:ubyte
		slots[0] = b.placeUOffset(cNameOff)
		slots[1] = b.placeUint8(col.colType)
		colTableOffsets[i] = b.finishTable(tEnd, slots[:])
	}
	colsVecOff := b.createOffsetVector(colTableOffsets)

	// Header table (fields 0..9):
	// 0: name (string)
	// 1: envelope ([double])
	// 2: geometry_type (ubyte)
	// 3..6: has_z, has_m, has_t, has_tm (omitted = false)
	// 7: columns ([Column])
	// 8: features_count (ulong)
	// 9: index_node_size (ushort = 0 -> explicitly stored or omitted = 0)
	hEnd := b.used()
	var hSlots [10]int
	hSlots[8] = b.placeUint64(featuresCount)
	hSlots[0] = b.placeUOffset(nameOff)
	if envOff != 0 {
		hSlots[1] = b.placeUOffset(envOff)
	}
	hSlots[7] = b.placeUOffset(colsVecOff)
	hSlots[9] = b.placeUint16(0)
	hSlots[2] = b.placeUint8(fgbGeometryTypePoint)
	root := b.finishTable(hEnd, hSlots[:])
	return b.finishRoot(root)
}

func appendFGBStringProp(buf []byte, colIdx uint16, val string) []byte {
	var tmp [6]byte
	binary.LittleEndian.PutUint16(tmp[0:2], colIdx)
	binary.LittleEndian.PutUint32(tmp[2:6], uint32(len(val)))
	buf = append(buf, tmp[:]...)
	buf = append(buf, val...)
	return buf
}

func appendFGBDoubleProp(buf []byte, colIdx uint16, val float64) []byte {
	var tmp [10]byte
	binary.LittleEndian.PutUint16(tmp[0:2], colIdx)
	binary.LittleEndian.PutUint64(tmp[2:10], math.Float64bits(val))
	return append(buf, tmp[:]...)
}

func appendFGBBoolProp(buf []byte, colIdx uint16, val bool) []byte {
	var b uint8
	if val {
		b = 1
	}
	return append(buf, byte(colIdx), byte(colIdx>>8), b)
}

func encodeFGBPointFeatureIntoBuilder(b *flatBufBuilder, props []byte, rec SpatialPlotRecord) ([]byte, []byte) {
	props = props[:0]
	props = appendFGBStringProp(props, 0, rec.PlotNumber)
	props = appendFGBDoubleProp(props, 1, rec.Lat)
	props = appendFGBDoubleProp(props, 2, rec.Lon)
	if rec.UTMDerivedLat != nil {
		props = appendFGBDoubleProp(props, 3, *rec.UTMDerivedLat)
	}
	if rec.UTMDerivedLon != nil {
		props = appendFGBDoubleProp(props, 4, *rec.UTMDerivedLon)
	}
	if rec.DivergenceMeters != nil {
		props = appendFGBDoubleProp(props, 5, *rec.DivergenceMeters)
	}
	if rec.Elevation != nil {
		props = appendFGBDoubleProp(props, 6, *rec.Elevation)
	}
	if rec.Slope != nil {
		props = appendFGBDoubleProp(props, 7, *rec.Slope)
	}
	if rec.Aspect != nil {
		props = appendFGBDoubleProp(props, 8, *rec.Aspect)
	}
	if rec.FieldBGC != "" {
		props = appendFGBStringProp(props, 9, rec.FieldBGC)
	}
	if rec.GISBGC != "" {
		props = appendFGBStringProp(props, 10, rec.GISBGC)
	}
	props = appendFGBBoolProp(props, 11, rec.BGCMismatch)
	if rec.SiteUnit != "" {
		props = appendFGBStringProp(props, 12, rec.SiteUnit)
	}

	b.reset()
	var xy [2]float64
	xy[0], xy[1] = rec.Lon, rec.Lat
	xyVecOff := b.createFloat64Vector(xy[:])
	gEnd := b.used()
	// Geometry table: field 1 = xy ([double]), field 7 = type (ubyte)
	var gSlots [8]int
	gSlots[1] = b.placeUOffset(xyVecOff)
	gSlots[7] = b.placeUint8(fgbGeometryTypePoint)
	geomOff := b.finishTable(gEnd, gSlots[:])

	propsVecOff := b.createByteVector(props)
	fEnd := b.used()
	// Feature table: field 0 = geometry (Geometry), field 1 = properties ([ubyte])
	var fSlots [2]int
	fSlots[0] = b.placeUOffset(geomOff)
	fSlots[1] = b.placeUOffset(propsVecOff)
	featRoot := b.finishTable(fEnd, fSlots[:])
	return b.finishRootView(featRoot), props
}

// EncodeSpatialPlotsFlatGeobuf encodes plot records into a valid OGC FlatGeobuf v3 binary buffer.
func EncodeSpatialPlotsFlatGeobuf(layerName string, records []SpatialPlotRecord) ([]byte, error) {
	if layerName == "" {
		layerName = "vpro_plots"
	}
	var env [4]float64
	approxPropsBytes := 0
	if len(records) > 0 {
		env = [4]float64{math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)}
		for i := range records {
			r := &records[i]
			if r.Lon < env[0] {
				env[0] = r.Lon
			}
			if r.Lat < env[1] {
				env[1] = r.Lat
			}
			if r.Lon > env[2] {
				env[2] = r.Lon
			}
			if r.Lat > env[3] {
				env[3] = r.Lat
			}
			approxPropsBytes += len(r.PlotNumber) + len(r.FieldBGC) + len(r.GISBGC) + len(r.SiteUnit)
		}
	}

	headerFB := buildFGBHeaderFlatBuffer(layerName, env, spatialFGBColumns, uint64(len(records)))
	estimatedBytes := 16 + len(headerFB) + len(records)*224 + approxPropsBytes
	out := make([]byte, 0, estimatedBytes)
	out = append(out, FlatGeobufMagicV3[:]...)

	var lenBuf [4]byte
	binary.LittleEndian.PutUint32(lenBuf[:], uint32(len(headerFB)))
	out = append(out, lenBuf[:]...)
	out = append(out, headerFB...)

	featBuilder := newFlatBufBuilder(512)
	propsBuf := make([]byte, 0, 256)
	for i := range records {
		var featView []byte
		featView, propsBuf = encodeFGBPointFeatureIntoBuilder(featBuilder, propsBuf, records[i])
		binary.LittleEndian.PutUint32(lenBuf[:], uint32(len(featView)))
		out = append(out, lenBuf[:]...)
		out = append(out, featView...)
	}
	return out, nil
}

func fbFieldPos(buf []byte, tablePos int, fieldIdx int) (int, bool) {
	if tablePos < 0 || tablePos+4 > len(buf) {
		return 0, false
	}
	soffset := int32(binary.LittleEndian.Uint32(buf[tablePos : tablePos+4]))
	vtPos := tablePos - int(soffset)
	if vtPos < 0 || vtPos+4 > len(buf) {
		return 0, false
	}
	vtLen := int(binary.LittleEndian.Uint16(buf[vtPos : vtPos+2]))
	slotOff := 4 + 2*fieldIdx
	if slotOff+2 > vtLen || vtPos+slotOff+2 > len(buf) {
		return 0, false
	}
	rel := int(binary.LittleEndian.Uint16(buf[vtPos+slotOff : vtPos+slotOff+2]))
	if rel == 0 || tablePos+rel > len(buf) {
		return 0, false
	}
	return tablePos + rel, true
}

func fbDeref(buf []byte, slotPos int) (int, bool) {
	if slotPos < 0 || slotPos+4 > len(buf) {
		return 0, false
	}
	uoff := int(binary.LittleEndian.Uint32(buf[slotPos : slotPos+4]))
	target := slotPos + uoff
	if target < 0 || target > len(buf) {
		return 0, false
	}
	return target, true
}

func fbReadString(buf []byte, slotPos int) (string, bool) {
	strPos, ok := fbDeref(buf, slotPos)
	if !ok || strPos+4 > len(buf) {
		return "", false
	}
	n := int(binary.LittleEndian.Uint32(buf[strPos : strPos+4]))
	if n < 0 || strPos+4+n > len(buf) {
		return "", false
	}
	return string(buf[strPos+4 : strPos+4+n]), true
}

// DecodeSpatialPlotsFlatGeobuf decodes an OGC FlatGeobuf v3 Point stream back into SpatialPlotRecord values.
func DecodeSpatialPlotsFlatGeobuf(data []byte) ([]SpatialPlotRecord, error) {
	if len(data) < 12 {
		return nil, errors.New("FlatGeobuf buffer shorter than 12 bytes")
	}
	var magic [8]byte
	copy(magic[:], data[:8])
	if magic != FlatGeobufMagicV3 {
		return nil, fmt.Errorf("invalid FlatGeobuf v3 magic %x", data[:8])
	}
	pos := 8
	hdrLen := int(binary.LittleEndian.Uint32(data[pos : pos+4]))
	pos += 4
	if hdrLen < 8 || pos+hdrLen > len(data) {
		return nil, errors.New("FlatGeobuf header length out of bounds")
	}
	hdrBuf := data[pos : pos+hdrLen]
	pos += hdrLen

	hdrRoot, ok := fbDeref(hdrBuf, 0)
	if !ok {
		return nil, errors.New("invalid FlatGeobuf header root offset")
	}

	var colDefs []fgbColumnDef
	if colsSlot, ok := fbFieldPos(hdrBuf, hdrRoot, 7); ok {
		colsVec, ok := fbDeref(hdrBuf, colsSlot)
		if ok && colsVec+4 <= len(hdrBuf) {
			nCols := int(binary.LittleEndian.Uint32(hdrBuf[colsVec : colsVec+4]))
			colDefs = make([]fgbColumnDef, 0, nCols)
			for i := 0; i < nCols; i++ {
				elemSlot := colsVec + 4 + i*4
				colTbl, ok := fbDeref(hdrBuf, elemSlot)
				if !ok {
					return nil, errors.New("invalid FlatGeobuf column table offset")
				}
				var cd fgbColumnDef
				if nameSlot, ok := fbFieldPos(hdrBuf, colTbl, 0); ok {
					cd.name, _ = fbReadString(hdrBuf, nameSlot)
				}
				if typeSlot, ok := fbFieldPos(hdrBuf, colTbl, 1); ok && typeSlot+1 <= len(hdrBuf) {
					cd.colType = hdrBuf[typeSlot]
				}
				colDefs = append(colDefs, cd)
			}
		}
	}

	var featCount uint64
	if fcSlot, ok := fbFieldPos(hdrBuf, hdrRoot, 8); ok && fcSlot+8 <= len(hdrBuf) {
		featCount = binary.LittleEndian.Uint64(hdrBuf[fcSlot : fcSlot+8])
	}

	records := make([]SpatialPlotRecord, 0, int(featCount))
	for pos < len(data) {
		if pos+4 > len(data) {
			return nil, errors.New("truncated FlatGeobuf feature size prefix")
		}
		fLen := int(binary.LittleEndian.Uint32(data[pos : pos+4]))
		pos += 4
		if fLen < 4 || pos+fLen > len(data) {
			return nil, errors.New("FlatGeobuf feature length out of bounds")
		}
		fBuf := data[pos : pos+fLen]
		pos += fLen

		fRoot, ok := fbDeref(fBuf, 0)
		if !ok {
			return nil, errors.New("invalid FlatGeobuf feature root")
		}
		var rec SpatialPlotRecord
		if geomSlot, ok := fbFieldPos(fBuf, fRoot, 0); ok {
			if geomTbl, ok := fbDeref(fBuf, geomSlot); ok {
				if xySlot, ok := fbFieldPos(fBuf, geomTbl, 1); ok {
					if xyVec, ok := fbDeref(fBuf, xySlot); ok && xyVec+4 <= len(fBuf) {
						nDoubles := int(binary.LittleEndian.Uint32(fBuf[xyVec : xyVec+4]))
						if nDoubles >= 2 && xyVec+4+16 <= len(fBuf) {
							rec.Lon = math.Float64frombits(binary.LittleEndian.Uint64(fBuf[xyVec+4 : xyVec+12]))
							rec.Lat = math.Float64frombits(binary.LittleEndian.Uint64(fBuf[xyVec+12 : xyVec+20]))
						}
					}
				}
			}
		}

		if propSlot, ok := fbFieldPos(fBuf, fRoot, 1); ok {
			if propVec, ok := fbDeref(fBuf, propSlot); ok && propVec+4 <= len(fBuf) {
				pLen := int(binary.LittleEndian.Uint32(fBuf[propVec : propVec+4]))
				if propVec+4+pLen <= len(fBuf) {
					pBytes := fBuf[propVec+4 : propVec+4+pLen]
					pIdx := 0
					for pIdx+2 <= len(pBytes) {
						colIdx := int(binary.LittleEndian.Uint16(pBytes[pIdx : pIdx+2]))
						pIdx += 2
						if colIdx < 0 || colIdx >= len(colDefs) {
							break
						}
						col := colDefs[colIdx]
						switch col.colType {
						case fgbColumnTypeString:
							if pIdx+4 > len(pBytes) {
								pIdx = len(pBytes)
								break
							}
							sLen := int(binary.LittleEndian.Uint32(pBytes[pIdx : pIdx+4]))
							pIdx += 4
							if pIdx+sLen > len(pBytes) {
								pIdx = len(pBytes)
								break
							}
							sv := string(pBytes[pIdx : pIdx+sLen])
							pIdx += sLen
							switch col.name {
							case "PlotNumber":
								rec.PlotNumber = sv
							case "FieldBGC":
								rec.FieldBGC = sv
							case "GIS_BGC":
								rec.GISBGC = sv
							case "SiteUnit":
								rec.SiteUnit = sv
							}
						case fgbColumnTypeDouble:
							if pIdx+8 > len(pBytes) {
								pIdx = len(pBytes)
								break
							}
							dv := math.Float64frombits(binary.LittleEndian.Uint64(pBytes[pIdx : pIdx+8]))
							pIdx += 8
							switch col.name {
							case "Lat":
								rec.Lat = dv
							case "Lon":
								rec.Lon = dv
							case "UTMDerivedLat":
								v := dv
								rec.UTMDerivedLat = &v
							case "UTMDerivedLon":
								v := dv
								rec.UTMDerivedLon = &v
							case "DivergenceMeters":
								v := dv
								rec.DivergenceMeters = &v
							case "Elevation":
								v := dv
								rec.Elevation = &v
							case "Slope":
								v := dv
								rec.Slope = &v
							case "Aspect":
								v := dv
								rec.Aspect = &v
							}
						case fgbColumnTypeBool:
							if pIdx+1 > len(pBytes) {
								pIdx = len(pBytes)
								break
							}
							bv := pBytes[pIdx] != 0
							pIdx++
							if col.name == "BGCMismatch" {
								rec.BGCMismatch = bv
							}
						default:
							pIdx = len(pBytes)
						}
					}
				}
			}
		}
		records = append(records, rec)
	}
	return records, nil
}
