package spatial

import (
	"encoding/binary"
	"fmt"
	"io"
	"math"
)

// --- Pure-Go Mapbox Vector Tile (MVT v2.1) Protobuf Wire Decoder ---

func skipProtoField(buf []byte, pos int, wireType uint64) (int, error) {
	switch wireType {
	case 0:
		_, next, err := readProtoUvarint(buf, pos)
		return next, err
	case 1:
		if pos+8 > len(buf) {
			return pos, io.ErrUnexpectedEOF
		}
		return pos + 8, nil
	case 2:
		ln, next, err := readProtoUvarint(buf, pos)
		if err != nil {
			return pos, err
		}
		end := next + int(ln)
		if end < next || end > len(buf) {
			return pos, io.ErrUnexpectedEOF
		}
		return end, nil
	case 5:
		if pos+4 > len(buf) {
			return pos, io.ErrUnexpectedEOF
		}
		return pos + 4, nil
	default:
		return pos, fmt.Errorf("unsupported protobuf wire type %d", wireType)
	}
}

func decodeZigZagInt64(v uint64) int64 {
	return int64(v>>1) ^ -int64(v&1)
}

func decodeMVTValue(buf []byte) (any, error) {
	pos := 0
	var out any
	for pos < len(buf) {
		tag, next, err := readProtoUvarint(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = next
		fieldNum := tag >> 3
		wireType := tag & 0x7
		switch {
		case fieldNum == 1 && wireType == 2: // string_value
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			out = string(buf[p2 : p2+int(ln)])
			pos = p2 + int(ln)
		case fieldNum == 2 && wireType == 5: // float_value
			if pos+4 > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			out = float64(math.Float32frombits(binary.LittleEndian.Uint32(buf[pos : pos+4])))
			pos += 4
		case fieldNum == 3 && wireType == 1: // double_value
			if pos+8 > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			out = math.Float64frombits(binary.LittleEndian.Uint64(buf[pos : pos+8]))
			pos += 8
		case fieldNum == 4 && wireType == 0: // int_value
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return nil, err
			}
			out = int64(v)
			pos = p2
		case fieldNum == 5 && wireType == 0: // uint_value
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return nil, err
			}
			out = v
			pos = p2
		case fieldNum == 6 && wireType == 0: // sint_value
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return nil, err
			}
			out = decodeZigZagInt64(v)
			pos = p2
		case fieldNum == 7 && wireType == 0: // bool_value
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return nil, err
			}
			out = v != 0
			pos = p2
		default:
			p2, err := skipProtoField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			pos = p2
		}
	}
	return out, nil
}

func decodeMVTPolygonGeometry(cmds []uint32) ([][][2]float64, [4]float64) {
	var rings [][][2]float64
	var curRing [][2]float64
	var cx, cy int64
	bbox := [4]float64{math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)}

	updateBBox := func(x, y float64) {
		if x < bbox[0] {
			bbox[0] = x
		}
		if y < bbox[1] {
			bbox[1] = y
		}
		if x > bbox[2] {
			bbox[2] = x
		}
		if y > bbox[3] {
			bbox[3] = y
		}
	}

	i := 0
	for i < len(cmds) {
		cmdInt := cmds[i]
		i++
		cmdID := cmdInt & 0x7
		count := int(cmdInt >> 3)
		switch cmdID {
		case 1: // MoveTo
			for c := 0; c < count && i+1 < len(cmds); c++ {
				if len(curRing) >= 3 {
					rings = append(rings, curRing)
				}
				cx += decodeZigZagInt64(uint64(cmds[i]))
				cy += decodeZigZagInt64(uint64(cmds[i+1]))
				i += 2
				fx, fy := float64(cx), float64(cy)
				updateBBox(fx, fy)
				curRing = [][2]float64{{fx, fy}}
			}
		case 2: // LineTo
			for c := 0; c < count && i+1 < len(cmds); c++ {
				cx += decodeZigZagInt64(uint64(cmds[i]))
				cy += decodeZigZagInt64(uint64(cmds[i+1]))
				i += 2
				fx, fy := float64(cx), float64(cy)
				updateBBox(fx, fy)
				curRing = append(curRing, [2]float64{fx, fy})
			}
		case 7: // ClosePath
			if len(curRing) >= 3 {
				if curRing[len(curRing)-1] != curRing[0] {
					curRing = append(curRing, curRing[0])
				}
				rings = append(rings, curRing)
			}
			curRing = nil
		}
	}
	if len(curRing) >= 3 {
		rings = append(rings, curRing)
	}
	return rings, bbox
}

func decodeMVTFeature(buf []byte, keys []string, values []any) (mvtDecodedFeature, error) {
	var feat mvtDecodedFeature
	var rawTags []uint32
	var rawGeom []uint32

	pos := 0
	for pos < len(buf) {
		tag, next, err := readProtoUvarint(buf, pos)
		if err != nil {
			return feat, err
		}
		pos = next
		fieldNum := tag >> 3
		wireType := tag & 0x7
		switch {
		case fieldNum == 1 && wireType == 0: // id
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return feat, err
			}
			feat.id = v
			pos = p2
		case fieldNum == 2 && wireType == 2: // packed tags
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return feat, io.ErrUnexpectedEOF
			}
			end := p2 + int(ln)
			for p2 < end {
				tv, p3, err := readProtoUvarint(buf, p2)
				if err != nil {
					return feat, err
				}
				rawTags = append(rawTags, uint32(tv))
				p2 = p3
			}
			pos = end
		case fieldNum == 2 && wireType == 0: // unpacked tag
			tv, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return feat, err
			}
			rawTags = append(rawTags, uint32(tv))
			pos = p2
		case fieldNum == 3 && wireType == 0: // GeomType
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return feat, err
			}
			feat.geomType = uint32(v)
			pos = p2
		case fieldNum == 4 && wireType == 2: // packed geometry
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return feat, io.ErrUnexpectedEOF
			}
			end := p2 + int(ln)
			for p2 < end {
				gv, p3, err := readProtoUvarint(buf, p2)
				if err != nil {
					return feat, err
				}
				rawGeom = append(rawGeom, uint32(gv))
				p2 = p3
			}
			pos = end
		case fieldNum == 4 && wireType == 0: // unpacked geometry
			gv, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return feat, err
			}
			rawGeom = append(rawGeom, uint32(gv))
			pos = p2
		default:
			p2, err := skipProtoField(buf, pos, wireType)
			if err != nil {
				return feat, err
			}
			pos = p2
		}
	}

	if feat.geomType == 3 {
		feat.rings, feat.bbox = decodeMVTPolygonGeometry(rawGeom)
	}
	feat.properties = make(map[string]any, len(rawTags)/2)
	for i := 0; i+1 < len(rawTags); i += 2 {
		kIdx := int(rawTags[i])
		vIdx := int(rawTags[i+1])
		if kIdx >= 0 && kIdx < len(keys) && vIdx >= 0 && vIdx < len(values) {
			feat.properties[keys[kIdx]] = values[vIdx]
		}
	}
	return feat, nil
}

func decodeMVTLayer(buf []byte) (*mvtDecodedLayer, error) {
	layer := &mvtDecodedLayer{extent: 4096}
	var rawFeatures [][]byte
	var keys []string
	var values []any

	pos := 0
	for pos < len(buf) {
		tag, next, err := readProtoUvarint(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = next
		fieldNum := tag >> 3
		wireType := tag & 0x7
		switch {
		case fieldNum == 1 && wireType == 2: // name
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			layer.name = string(buf[p2 : p2+int(ln)])
			pos = p2 + int(ln)
		case fieldNum == 2 && wireType == 2: // features
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			rawFeatures = append(rawFeatures, buf[p2:p2+int(ln)])
			pos = p2 + int(ln)
		case fieldNum == 3 && wireType == 2: // keys
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			keys = append(keys, string(buf[p2:p2+int(ln)]))
			pos = p2 + int(ln)
		case fieldNum == 4 && wireType == 2: // values
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			v, err := decodeMVTValue(buf[p2 : p2+int(ln)])
			if err != nil {
				return nil, err
			}
			values = append(values, v)
			pos = p2 + int(ln)
		case fieldNum == 5 && wireType == 0: // extent
			v, p2, err := readProtoUvarint(buf, pos)
			if err != nil {
				return nil, err
			}
			if v > 0 {
				layer.extent = uint32(v)
			}
			pos = p2
		default:
			p2, err := skipProtoField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			pos = p2
		}
	}

	layer.features = make([]mvtDecodedFeature, 0, len(rawFeatures))
	for _, rf := range rawFeatures {
		feat, err := decodeMVTFeature(rf, keys, values)
		if err != nil {
			return nil, err
		}
		if feat.geomType == 3 && len(feat.rings) > 0 {
			layer.features = append(layer.features, feat)
		}
	}
	return layer, nil
}

func decodeMVTTile(buf []byte) (map[string]*mvtDecodedLayer, error) {
	layers := make(map[string]*mvtDecodedLayer)
	pos := 0
	for pos < len(buf) {
		tag, next, err := readProtoUvarint(buf, pos)
		if err != nil {
			return nil, err
		}
		pos = next
		fieldNum := tag >> 3
		wireType := tag & 0x7
		if fieldNum == 3 && wireType == 2 {
			ln, p2, err := readProtoUvarint(buf, pos)
			if err != nil || p2+int(ln) > len(buf) {
				return nil, io.ErrUnexpectedEOF
			}
			layer, err := decodeMVTLayer(buf[p2 : p2+int(ln)])
			if err != nil {
				return nil, err
			}
			layers[layer.name] = layer
			pos = p2 + int(ln)
		} else {
			p2, err := skipProtoField(buf, pos, wireType)
			if err != nil {
				return nil, err
			}
			pos = p2
		}
	}
	return layers, nil
}

// PointInMVTPolygonRings evaluates even-odd ray-casting across all rings of an MVT polygon/multipolygon feature.
func PointInMVTPolygonRings(px, py float64, rings [][][2]float64) bool {
	inside := false
	for _, ring := range rings {
		n := len(ring)
		if n < 3 {
			continue
		}
		j := n - 1
		for i := 0; i < n; i++ {
			xi, yi := ring[i][0], ring[i][1]
			xj, yj := ring[j][0], ring[j][1]
			if ((yi > py) != (yj > py)) && (px < (xj-xi)*(py-yi)/(yj-yi)+xi) {
				inside = !inside
			}
			j = i
		}
	}
	return inside
}

func queryLayerAtLatLon(reader *pmtilesReader, layerName string, lat, lon float64) (map[string]any, int, bool, error) {
	if reader == nil {
		return nil, 0, false, nil
	}
	for z := int(reader.header.maxZoom); z >= int(reader.header.minZoom); z-- {
		tx, ty, _, _ := LatLonToWebMercatorTile(lat, lon, z, 4096)
		tileID := ZXYToPMTilesHilbertID(z, tx, ty)
		layers, ok, err := reader.getDecodedTileByID(tileID)
		if err != nil {
			return nil, 0, false, err
		}
		if !ok {
			continue
		}
		layer := layers[layerName]
		if layer == nil || len(layer.features) == 0 {
			continue
		}
		_, _, px, py := LatLonToWebMercatorTile(lat, lon, z, layer.extent)
		for _, feat := range layer.features {
			if px < feat.bbox[0] || px > feat.bbox[2] || py < feat.bbox[1] || py > feat.bbox[3] {
				continue
			}
			if PointInMVTPolygonRings(px, py, feat.rings) {
				return feat.properties, z, true, nil
			}
		}
		// Sub-pixel shoreline fallback (±2 units) when point lands on coastal boundary
		offsets := [4][2]float64{{2, 0}, {-2, 0}, {0, 2}, {0, -2}}
		for _, off := range offsets {
			qx, qy := px+off[0], py+off[1]
			for _, feat := range layer.features {
				if qx < feat.bbox[0] || qx > feat.bbox[2] || qy < feat.bbox[1] || qy > feat.bbox[3] {
					continue
				}
				if PointInMVTPolygonRings(qx, qy, feat.rings) {
					return feat.properties, z, true, nil
				}
			}
		}
	}
	return nil, 0, false, nil
}
