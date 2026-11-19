package spatial

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/boostao/vpro/app/resources"
)

const (
	SpatialAssetsEnvVar  = "VPRO_SPATIAL_ASSETS_DIR"
	CurrentBECGISVersion = 13
)

// DefaultSpatialAssetsDir resolves VPRO_SPATIAL_ASSETS_DIR or sibling spatial_assets dynamically across Linux, Windows, and macOS.
var DefaultSpatialAssetsDir = ResolveDefaultSpatialAssetsDir()

func resolveSpatialAssetsDir(getenv func(string) string, repoRoot string) string {
	if getenv != nil {
		if envDir := strings.TrimSpace(getenv(SpatialAssetsEnvVar)); envDir != "" {
			cleaned := filepath.Clean(envDir)
			if info, err := os.Stat(cleaned); err == nil && info.IsDir() {
				return cleaned
			}
		}
	}
	if strings.TrimSpace(repoRoot) != "" {
		parent := filepath.Dir(filepath.Clean(repoRoot))
		candidates := []string{filepath.Join(parent, "spatial_assets")}
		if strings.HasSuffix(strings.ToLower(filepath.Base(parent)), ".worktrees") {
			candidates = append(candidates, filepath.Join(filepath.Dir(parent), "spatial_assets"))
		}
		for _, cand := range candidates {
			if info, err := os.Stat(cand); err == nil && info.IsDir() {
				return cand
			}
		}
	}
	return ""
}

// ResolveDefaultSpatialAssetsDir resolves VPRO_SPATIAL_ASSETS_DIR, sibling spatial_assets, or ~/Work/spatial_assets.
func ResolveDefaultSpatialAssetsDir() string {
	if resolved := resolveSpatialAssetsDir(os.Getenv, resources.RepoRoot()); resolved != "" {
		return resolved
	}
	if home, err := os.UserHomeDir(); err == nil && strings.TrimSpace(home) != "" {
		cand := filepath.Join(home, "Work", "spatial_assets")
		if info, statErr := os.Stat(cand); statErr == nil && info.IsDir() {
			return cand
		}
	}
	return ""
}

type pmtilesHeaderV3 struct {
	rootDirOffset       uint64
	rootDirBytes        uint64
	jsonMetadataOffset  uint64
	jsonMetadataBytes   uint64
	leafDirsOffset      uint64
	leafDirsBytes       uint64
	tileDataOffset      uint64
	tileDataBytes       uint64
	addressedTilesCount uint64
	tileEntriesCount    uint64
	tileContentsCount   uint64
	clustered           uint8
	internalCompression uint8 // 1 = none, 2 = gzip
	tileCompression     uint8 // 1 = none, 2 = gzip
	tileType            uint8 // 1 = mvt
	minZoom             uint8
	maxZoom             uint8
}

type pmtilesDirEntry struct {
	tileID    uint64
	offset    uint64
	length    uint32
	runLength uint32
}

type mvtDecodedFeature struct {
	id         uint64
	geomType   uint32 // 1=Point, 2=LineString, 3=Polygon
	rings      [][][2]float64
	bbox       [4]float64 // minX, minY, maxX, maxY in tile coordinates
	properties map[string]any
}

type mvtDecodedLayer struct {
	name     string
	extent   uint32
	features []mvtDecodedFeature
}

type pmtilesReader struct {
	sourceLabel string
	readerAt    io.ReaderAt
	closer      io.Closer
	header      pmtilesHeaderV3
	rootEntries []pmtilesDirEntry

	mu        sync.Mutex
	leafCache map[uint64][]pmtilesDirEntry
	tileCache map[uint64]map[string]*mvtDecodedLayer
}

func parsePMTilesHeaderV3(buf []byte) (pmtilesHeaderV3, error) {
	if len(buf) < 127 || string(buf[:7]) != "PMTiles" || buf[7] != 3 {
		return pmtilesHeaderV3{}, errors.New("invalid PMTiles v3 header magic")
	}
	return pmtilesHeaderV3{
		rootDirOffset:       binary.LittleEndian.Uint64(buf[8:16]),
		rootDirBytes:        binary.LittleEndian.Uint64(buf[16:24]),
		jsonMetadataOffset:  binary.LittleEndian.Uint64(buf[24:32]),
		jsonMetadataBytes:   binary.LittleEndian.Uint64(buf[32:40]),
		leafDirsOffset:      binary.LittleEndian.Uint64(buf[40:48]),
		leafDirsBytes:       binary.LittleEndian.Uint64(buf[48:56]),
		tileDataOffset:      binary.LittleEndian.Uint64(buf[56:64]),
		tileDataBytes:       binary.LittleEndian.Uint64(buf[64:72]),
		addressedTilesCount: binary.LittleEndian.Uint64(buf[72:80]),
		tileEntriesCount:    binary.LittleEndian.Uint64(buf[80:88]),
		tileContentsCount:   binary.LittleEndian.Uint64(buf[88:96]),
		clustered:           buf[96],
		internalCompression: buf[97],
		tileCompression:     buf[98],
		tileType:            buf[99],
		minZoom:             buf[100],
		maxZoom:             buf[101],
	}, nil
}

// Wait — let's double-check header byte offsets [8..127]!
// Earlier we unpacked `hdr[8:127]` with `<11QBBBBBB4iB2i`:
// 11 * 8 = 88 bytes -> [8 .. 96)!
// So:
// [8..16]: root_off (1)
// [16..24]: root_len (2)
// [24..32]: meta_off (3)
// [32..40]: meta_len (4)
// [40..48]: leaf_off (5)
// [48..56]: leaf_len (6)
// [56..64]: data_off (7)
// [64..72]: data_len (8)
// [72..80]: addr_cnt (9)
// [80..88]: entry_cnt (10)
// [88..96]: cont_cnt (11)
// [96]: clustered
// [97]: int_comp
// [98]: tile_comp
// [99]: tile_type
// [100]: min_z
// [101]: max_z
// Notice in pmtilesserver.go we wrote header[99], header[100] — let's fix pmtilesserver.go to [100], [101] too!

func decompressPMTilesChunk(raw []byte, compression uint8) ([]byte, error) {
	switch compression {
	case 1:
		return raw, nil
	case 2:
		zr, err := gzip.NewReader(bytes.NewReader(raw))
		if err != nil {
			return nil, fmt.Errorf("gzip header error: %w", err)
		}
		defer zr.Close()
		out, err := io.ReadAll(zr)
		if err != nil {
			return nil, fmt.Errorf("gzip read error: %w", err)
		}
		return out, nil
	default:
		return nil, fmt.Errorf("unsupported PMTiles compression code %d", compression)
	}
}

func readProtoUvarint(buf []byte, pos int) (uint64, int, error) {
	var x uint64
	var s uint
	for i := 0; i < 10; i++ {
		if pos >= len(buf) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		b := buf[pos]
		pos++
		if b < 0x80 {
			if i == 9 && b > 1 {
				return 0, pos, errors.New("varint overflow")
			}
			return x | uint64(b)<<s, pos, nil
		}
		x |= uint64(b&0x7f) << s
		s += 7
	}
	return 0, pos, errors.New("varint too long")
}

func parsePMTilesDirectory(raw []byte) ([]pmtilesDirEntry, error) {
	n64, pos, err := readProtoUvarint(raw, 0)
	if err != nil {
		return nil, err
	}
	if n64 > 10_000_000 {
		return nil, fmt.Errorf("excessive PMTiles directory entry count %d", n64)
	}
	n := int(n64)
	entries := make([]pmtilesDirEntry, n)
	var lastID uint64
	for i := 0; i < n; i++ {
		delta, nextPos, err := readProtoUvarint(raw, pos)
		if err != nil {
			return nil, err
		}
		pos = nextPos
		lastID += delta
		entries[i].tileID = lastID
	}
	for i := 0; i < n; i++ {
		rl, nextPos, err := readProtoUvarint(raw, pos)
		if err != nil {
			return nil, err
		}
		pos = nextPos
		entries[i].runLength = uint32(rl)
	}
	for i := 0; i < n; i++ {
		ln, nextPos, err := readProtoUvarint(raw, pos)
		if err != nil {
			return nil, err
		}
		pos = nextPos
		entries[i].length = uint32(ln)
	}
	for i := 0; i < n; i++ {
		off, nextPos, err := readProtoUvarint(raw, pos)
		if err != nil {
			return nil, err
		}
		pos = nextPos
		if i > 0 && off == 0 {
			entries[i].offset = entries[i-1].offset + uint64(entries[i-1].length)
		} else if off > 0 {
			entries[i].offset = off - 1
		}
	}
	return entries, nil
}

func openPMTilesReaderFromBytes(label string, data []byte) (*pmtilesReader, error) {
	if len(data) < 127 {
		return nil, errors.New("PMTiles byte buffer shorter than 127 bytes")
	}
	hdr, err := parsePMTilesHeaderV3(data[:127])
	if err != nil {
		return nil, err
	}
	if hdr.rootDirOffset+hdr.rootDirBytes > uint64(len(data)) {
		return nil, errors.New("PMTiles root directory exceeds buffer bounds")
	}
	rootRaw := data[hdr.rootDirOffset : hdr.rootDirOffset+hdr.rootDirBytes]
	rootDecomp, err := decompressPMTilesChunk(rootRaw, hdr.internalCompression)
	if err != nil {
		return nil, err
	}
	entries, err := parsePMTilesDirectory(rootDecomp)
	if err != nil {
		return nil, err
	}
	return &pmtilesReader{
		sourceLabel: label,
		readerAt:    bytes.NewReader(data),
		header:      hdr,
		rootEntries: entries,
		leafCache:   make(map[uint64][]pmtilesDirEntry),
		tileCache:   make(map[uint64]map[string]*mvtDecodedLayer),
	}, nil
}

func openPMTilesReaderFromFile(path string) (*pmtilesReader, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	var hdrBuf [127]byte
	if _, err := io.ReadFull(f, hdrBuf[:]); err != nil {
		_ = f.Close()
		return nil, err
	}
	hdr, err := parsePMTilesHeaderV3(hdrBuf[:])
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	rootRaw := make([]byte, hdr.rootDirBytes)
	if _, err := f.ReadAt(rootRaw, int64(hdr.rootDirOffset)); err != nil {
		_ = f.Close()
		return nil, err
	}
	rootDecomp, err := decompressPMTilesChunk(rootRaw, hdr.internalCompression)
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	entries, err := parsePMTilesDirectory(rootDecomp)
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	return &pmtilesReader{
		sourceLabel: path,
		readerAt:    f,
		closer:      f,
		header:      hdr,
		rootEntries: entries,
		leafCache:   make(map[uint64][]pmtilesDirEntry),
		tileCache:   make(map[uint64]map[string]*mvtDecodedLayer),
	}, nil
}

func (r *pmtilesReader) Close() error {
	if r != nil && r.closer != nil {
		return r.closer.Close()
	}
	return nil
}

// ZXYToPMTilesHilbertID computes the PMTiles v3 Hilbert curve tile ID for (z, x, y).
func ZXYToPMTilesHilbertID(z int, x, y uint64) uint64 {
	if z <= 0 {
		return 0
	}
	acc := ((uint64(1) << (2 * uint(z))) - 1) / 3
	n := int64(1) << uint(z)
	tx := int64(x)
	ty := int64(y)
	var d int64
	for s := n >> 1; s > 0; s >>= 1 {
		var rx, ry int64
		if (tx & s) != 0 {
			rx = 1
		}
		if (ty & s) != 0 {
			ry = 1
		}
		d += s * s * ((3 * rx) ^ ry)
		if ry == 0 {
			if rx == 1 {
				tx = n - 1 - tx
				ty = n - 1 - ty
			}
			tx, ty = ty, tx
		}
	}
	return acc + uint64(d)
}

// LatLonToWebMercatorTile computes tile (x, y) and fractional pixel (px, py) within [0, extent) at zoom z.
func LatLonToWebMercatorTile(lat, lon float64, z int, extent uint32) (tx, ty uint64, px, py float64) {
	clampedLat := math.Max(-85.05112878, math.Min(85.05112878, lat))
	n := float64(uint64(1) << uint(z))
	fx := (lon + 180.0) / 360.0 * n
	latRad := clampedLat * math.Pi / 180.0
	fy := (1.0 - math.Asinh(math.Tan(latRad))/math.Pi) / 2.0 * n

	maxIdx := (uint64(1) << uint(z)) - 1
	var ix, iy uint64
	if fx <= 0 {
		ix = 0
		fx = 0
	} else if fx >= n {
		ix = maxIdx
		fx = n - 1e-9
	} else {
		ix = uint64(math.Floor(fx))
	}
	if fy <= 0 {
		iy = 0
		fy = 0
	} else if fy >= n {
		iy = maxIdx
		fy = n - 1e-9
	} else {
		iy = uint64(math.Floor(fy))
	}
	ext := float64(extent)
	return ix, iy, (fx - float64(ix)) * ext, (fy - float64(iy)) * ext
}

func findDirectoryEntry(entries []pmtilesDirEntry, tileID uint64) (pmtilesDirEntry, bool) {
	if len(entries) == 0 {
		return pmtilesDirEntry{}, false
	}
	// First index with entries[idx].tileID > tileID
	idx := sort.Search(len(entries), func(i int) bool {
		return entries[i].tileID > tileID
	})
	if idx == 0 {
		return pmtilesDirEntry{}, false
	}
	cand := entries[idx-1]
	if cand.runLength == 0 {
		return cand, true
	}
	if tileID < cand.tileID+uint64(cand.runLength) {
		return cand, true
	}
	return pmtilesDirEntry{}, false
}

func (r *pmtilesReader) getDecodedTileByID(tileID uint64) (map[string]*mvtDecodedLayer, bool, error) {
	r.mu.Lock()
	if cached, ok := r.tileCache[tileID]; ok {
		r.mu.Unlock()
		return cached, cached != nil, nil
	}
	r.mu.Unlock()

	entries := r.rootEntries
	var foundEntry pmtilesDirEntry
	matched := false
	for depth := 0; depth < 5; depth++ {
		cand, ok := findDirectoryEntry(entries, tileID)
		if !ok {
			break
		}
		if cand.runLength > 0 {
			foundEntry = cand
			matched = true
			break
		}
		// Leaf directory traversal
		r.mu.Lock()
		leaf, hasLeaf := r.leafCache[cand.offset]
		r.mu.Unlock()
		if !hasLeaf {
			leafRaw := make([]byte, cand.length)
			if _, err := r.readerAt.ReadAt(leafRaw, int64(r.header.leafDirsOffset+cand.offset)); err != nil {
				return nil, false, err
			}
			leafDecomp, err := decompressPMTilesChunk(leafRaw, r.header.internalCompression)
			if err != nil {
				return nil, false, err
			}
			parsedLeaf, err := parsePMTilesDirectory(leafDecomp)
			if err != nil {
				return nil, false, err
			}
			r.mu.Lock()
			if len(r.leafCache) > 64 {
				r.leafCache = make(map[uint64][]pmtilesDirEntry)
			}
			r.leafCache[cand.offset] = parsedLeaf
			r.mu.Unlock()
			leaf = parsedLeaf
		}
		entries = leaf
	}

	if !matched || foundEntry.length == 0 {
		return nil, false, nil
	}

	tileRaw := make([]byte, foundEntry.length)
	if _, err := r.readerAt.ReadAt(tileRaw, int64(r.header.tileDataOffset+foundEntry.offset)); err != nil {
		return nil, false, err
	}
	mvtBytes, err := decompressPMTilesChunk(tileRaw, r.header.tileCompression)
	if err != nil {
		return nil, false, err
	}
	layers, err := decodeMVTTile(mvtBytes)
	if err != nil {
		return nil, false, err
	}

	r.mu.Lock()
	if len(r.tileCache) > 256 {
		r.tileCache = make(map[uint64]map[string]*mvtDecodedLayer)
	}
	r.tileCache[tileID] = layers
	r.mu.Unlock()

	return layers, true, nil
}
