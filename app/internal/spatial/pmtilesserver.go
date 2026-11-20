package spatial

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/boostao/vpro/app/resources"
)

const (
	PMTilesOverviewArchiveName = "bc-overview.pmtiles"
	PMTilesBGCArchiveName      = "bc-bgc-v13.pmtiles"
	PMTilesAdminArchiveName    = "bc-admin-ecosections-districts.pmtiles"
	PMTilesContentType         = "application/vnd.pmtiles"
)

var defaultKnownPMTilesArchives = []string{
	PMTilesOverviewArchiveName,
	PMTilesBGCArchiveName,
	PMTilesAdminArchiveName,
}

// PMTilesArchiveStatus describes the resolution state of a single .pmtiles archive.
type PMTilesArchiveStatus struct {
	Name             string `json:"name"`
	URL              string `json:"url"`
	Source           string `json:"source"` // "dataDir" | "extraDir" | "embedded-overview" | "missing"
	Available        bool   `json:"available"`
	FullResolution   bool   `json:"fullResolution"`
	FallbackOverview bool   `json:"fallbackOverview"`
	MinZoom          int    `json:"minZoom"`
	MaxZoom          int    `json:"maxZoom"`
	SizeBytes        int64  `json:"sizeBytes"`
	Warning          string `json:"warning,omitempty"`
}

// PMTilesManifest reports available offline PMTiles archives to the Svelte 5 MapLibre workbench.
type PMTilesManifest struct {
	SchemaVersion int                             `json:"schemaVersion"`
	Archives      map[string]PMTilesArchiveStatus `json:"archives"`
	Ordered       []PMTilesArchiveStatus          `json:"ordered"`
}

type resolvedPMTilesSource struct {
	filePath         string
	embedded         []byte
	modTime          time.Time
	sizeBytes        int64
	source           string
	fullResolution   bool
	fallbackOverview bool
	minZoom          int
	maxZoom          int
	warning          string
}

func validatePMTilesBasename(raw string) (string, bool) {
	if raw == "" || strings.ContainsAny(raw, "/\\\x00") || strings.Contains(raw, "..") {
		return "", false
	}
	base := filepath.Base(raw)
	if base != raw || base == "." || base == ".." || base == ".pmtiles" {
		return "", false
	}
	if !strings.HasSuffix(strings.ToLower(base), ".pmtiles") {
		return "", false
	}
	for _, r := range base {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.') {
			return "", false
		}
	}
	return base, true
}

const maxPMTilesRootDirBytes = 16 * 1024 * 1024

func validatePMTilesHeaderAndRootDir(
	hdr pmtilesHeaderV3,
	totalBytes int64,
	readChunk func(offset, length uint64) ([]byte, error),
) (minZ, maxZ int, err error) {
	if totalBytes < 127 {
		return 0, 0, errors.New("PMTiles archive is shorter than 127-byte header")
	}
	uSize := uint64(totalBytes)
	if hdr.minZoom > hdr.maxZoom || hdr.maxZoom > 30 {
		return 0, 0, fmt.Errorf("invalid PMTiles zoom bounds z%d..z%d", hdr.minZoom, hdr.maxZoom)
	}
	if hdr.internalCompression != 1 && hdr.internalCompression != 2 {
		return 0, 0, fmt.Errorf("unsupported PMTiles internal compression %d", hdr.internalCompression)
	}
	if hdr.tileCompression < 1 || hdr.tileCompression > 4 {
		return 0, 0, fmt.Errorf("unsupported PMTiles tile compression %d", hdr.tileCompression)
	}
	if hdr.rootDirOffset < 127 || hdr.rootDirBytes == 0 || hdr.rootDirBytes > maxPMTilesRootDirBytes ||
		hdr.rootDirOffset > uSize || hdr.rootDirBytes > uSize-hdr.rootDirOffset {
		return 0, 0, errors.New("PMTiles root directory range is out of bounds")
	}
	if hdr.jsonMetadataBytes > 0 && (hdr.jsonMetadataOffset < 127 || hdr.jsonMetadataOffset > uSize || hdr.jsonMetadataBytes > uSize-hdr.jsonMetadataOffset) {
		return 0, 0, errors.New("PMTiles metadata range is out of bounds")
	}
	if hdr.leafDirsBytes > 0 && (hdr.leafDirsOffset < 127 || hdr.leafDirsOffset > uSize || hdr.leafDirsBytes > uSize-hdr.leafDirsOffset) {
		return 0, 0, errors.New("PMTiles leaf directory range is out of bounds")
	}
	if hdr.tileDataBytes == 0 || hdr.tileDataOffset < 127 || hdr.tileDataOffset > uSize || hdr.tileDataBytes > uSize-hdr.tileDataOffset {
		return 0, 0, errors.New("PMTiles tile data range is out of bounds")
	}
	rootRaw, err := readChunk(hdr.rootDirOffset, hdr.rootDirBytes)
	if err != nil {
		return 0, 0, fmt.Errorf("read PMTiles root directory: %w", err)
	}
	rootDecomp, err := decompressPMTilesChunk(rootRaw, hdr.internalCompression)
	if err != nil {
		return 0, 0, fmt.Errorf("decompress PMTiles root directory: %w", err)
	}
	entries, err := parsePMTilesDirectory(rootDecomp)
	if err != nil {
		return 0, 0, fmt.Errorf("parse PMTiles root directory: %w", err)
	}
	if len(entries) == 0 {
		return 0, 0, errors.New("PMTiles root directory contains zero tile entries")
	}
	return int(hdr.minZoom), int(hdr.maxZoom), nil
}

func validatePMTilesArchiveBytes(data []byte) (minZ, maxZ int, err error) {
	if len(data) < 127 {
		return 0, 0, errors.New("PMTiles archive buffer is shorter than 127 bytes")
	}
	hdr, err := parsePMTilesHeaderV3(data[:127])
	if err != nil {
		return 0, 0, err
	}
	return validatePMTilesHeaderAndRootDir(hdr, int64(len(data)), func(offset, length uint64) ([]byte, error) {
		return data[offset : offset+length], nil
	})
}

func validatePMTilesArchiveFile(path string) (sizeBytes int64, modTime time.Time, minZ, maxZ int, err error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, time.Time{}, 0, 0, err
	}
	if !info.Mode().IsRegular() {
		return 0, time.Time{}, 0, 0, errors.New("PMTiles path is not a regular file")
	}
	if info.Size() < 127 {
		return info.Size(), info.ModTime().UTC(), 0, 0, errors.New("PMTiles file is shorter than 127 bytes")
	}
	f, err := os.Open(path)
	if err != nil {
		return info.Size(), info.ModTime().UTC(), 0, 0, err
	}
	defer f.Close()
	var hdrBuf [127]byte
	if _, err := io.ReadFull(f, hdrBuf[:]); err != nil {
		return info.Size(), info.ModTime().UTC(), 0, 0, err
	}
	hdr, err := parsePMTilesHeaderV3(hdrBuf[:])
	if err != nil {
		return info.Size(), info.ModTime().UTC(), 0, 0, err
	}
	minZ, maxZ, err = validatePMTilesHeaderAndRootDir(hdr, info.Size(), func(offset, length uint64) ([]byte, error) {
		buf := make([]byte, length)
		if _, rErr := f.ReadAt(buf, int64(offset)); rErr != nil {
			return nil, rErr
		}
		return buf, nil
	})
	if err != nil {
		return info.Size(), info.ModTime().UTC(), 0, 0, err
	}
	return info.Size(), info.ModTime().UTC(), minZ, maxZ, nil
}

// ResolveSpatialExtraDirs discovers optional offline PMTiles directories from
// VPRO_SPATIAL_ASSETS_DIR, optional configured paths (e.g. config.yml),
// sibling developer spatial_assets (when present), and read-only bundle resource
// locations adjacent to os.Executable().
func ResolveSpatialExtraDirs(configured ...string) []string {
	var candidates []string
	if envVal := strings.TrimSpace(os.Getenv(SpatialAssetsEnvVar)); envVal != "" {
		for _, item := range filepath.SplitList(envVal) {
			if trimmed := strings.TrimSpace(item); trimmed != "" {
				candidates = append(candidates, trimmed)
			}
		}
	}
	for _, raw := range configured {
		if trimmed := strings.TrimSpace(raw); trimmed != "" {
			candidates = append(candidates, trimmed)
		}
	}
	if def := ResolveDefaultSpatialAssetsDir(); def != "" {
		candidates = append(candidates, def)
	}
	if exePath, err := os.Executable(); err == nil && strings.TrimSpace(exePath) != "" {
		resolvedExe := exePath
		if eval, evalErr := filepath.EvalSymlinks(exePath); evalErr == nil && eval != "" {
			resolvedExe = eval
		}
		exeDir := filepath.Dir(resolvedExe)
		candidates = append(candidates,
			filepath.Join(exeDir, "maps"),
			filepath.Join(exeDir, "..", "Resources", "maps"),
			filepath.Join(exeDir, "..", "share", "vpro", "maps"),
		)
	}
	seen := make(map[string]struct{}, len(candidates))
	out := make([]string, 0, len(candidates))
	for _, c := range candidates {
		clean := filepath.Clean(c)
		if clean == "" || clean == "." {
			continue
		}
		if _, dup := seen[clean]; dup {
			continue
		}
		if info, err := os.Stat(clean); err == nil && info.IsDir() {
			seen[clean] = struct{}{}
			out = append(out, clean)
		}
	}
	return out
}

func resolvePMTilesArchive(name, dataDir string, extraDirs []string) (resolvedPMTilesSource, bool) {
	clean, ok := validatePMTilesBasename(name)
	if !ok {
		return resolvedPMTilesSource{}, false
	}
	isOverviewName := strings.EqualFold(clean, PMTilesOverviewArchiveName)
	hadCorruptLocal := false

	// 1. Check <dataDir>/maps/<name>.pmtiles
	if strings.TrimSpace(dataDir) != "" {
		candidate := filepath.Join(dataDir, "maps", clean)
		if info, err := os.Stat(candidate); err == nil && info.Mode().IsRegular() {
			if sizeBytes, modTime, minZ, maxZ, vErr := validatePMTilesArchiveFile(candidate); vErr == nil {
				return resolvedPMTilesSource{
					filePath:       candidate,
					modTime:        modTime,
					sizeBytes:      sizeBytes,
					source:         "dataDir",
					fullResolution: !isOverviewName && maxZ > 6,
					minZoom:        minZ,
					maxZoom:        maxZ,
				}, true
			}
			hadCorruptLocal = true
		}
	}

	// 2. Check extraDirs/<name>.pmtiles (and extraDirs/maps/<name>.pmtiles)
	for _, rawDir := range extraDirs {
		dir := strings.TrimSpace(rawDir)
		if dir == "" {
			continue
		}
		for _, candidate := range []string{filepath.Join(dir, clean), filepath.Join(dir, "maps", clean)} {
			if info, err := os.Stat(candidate); err == nil && info.Mode().IsRegular() {
				if sizeBytes, modTime, minZ, maxZ, vErr := validatePMTilesArchiveFile(candidate); vErr == nil {
					warn := ""
					if hadCorruptLocal {
						warn = fmt.Sprintf("Local map archive %s in your maps folder is unreadable or incomplete; loaded valid map archive from configured map assets instead.", clean)
					}
					return resolvedPMTilesSource{
						filePath:       candidate,
						modTime:        modTime,
						sizeBytes:      sizeBytes,
						source:         "extraDir",
						fullResolution: !isOverviewName && maxZ > 6,
						minZoom:        minZ,
						maxZoom:        maxZ,
						warning:        warn,
					}, true
				}
				hadCorruptLocal = true
			}
		}
	}

	// 3. Embedded overview fallback for bc-overview.pmtiles or absent/corrupt provincial archives
	canFallbackToEmbedded := isOverviewName ||
		strings.EqualFold(clean, PMTilesBGCArchiveName) ||
		strings.EqualFold(clean, PMTilesAdminArchiveName)
	if canFallbackToEmbedded {
		if minZ, maxZ, vErr := validatePMTilesArchiveBytes(resources.BCOverviewPMTiles); vErr == nil {
			warn := ""
			if hadCorruptLocal {
				warn = fmt.Sprintf("Local map archive %s is unreadable or incomplete; using the built-in BC overview map (z%d..%d) instead.", clean, minZ, maxZ)
			}
			return resolvedPMTilesSource{
				embedded:         resources.BCOverviewPMTiles,
				modTime:          time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
				sizeBytes:        int64(len(resources.BCOverviewPMTiles)),
				source:           "embedded-overview",
				fullResolution:   false,
				fallbackOverview: !isOverviewName,
				minZoom:          minZ,
				maxZoom:          maxZ,
				warning:          warn,
			}, true
		}
	}

	if hadCorruptLocal {
		return resolvedPMTilesSource{
			source:  "missing",
			warning: fmt.Sprintf("Local map archive %s is unreadable or incomplete.", clean),
		}, false
	}
	return resolvedPMTilesSource{}, false
}

// BuildPMTilesManifest inspects dataDir, extraDirs, and the embedded overview archive.
func BuildPMTilesManifest(dataDir string, extraDirs ...string) PMTilesManifest {
	names := make(map[string]struct{}, len(defaultKnownPMTilesArchives))
	for _, n := range defaultKnownPMTilesArchives {
		names[n] = struct{}{}
	}
	scanDir := func(dir string) {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return
		}
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			if clean, ok := validatePMTilesBasename(e.Name()); ok {
				names[clean] = struct{}{}
			}
		}
	}
	if strings.TrimSpace(dataDir) != "" {
		scanDir(filepath.Join(dataDir, "maps"))
	}
	for _, d := range extraDirs {
		if strings.TrimSpace(d) != "" {
			scanDir(d)
			scanDir(filepath.Join(d, "maps"))
		}
	}

	sortedNames := make([]string, 0, len(names))
	for n := range names {
		sortedNames = append(sortedNames, n)
	}
	sort.Strings(sortedNames)

	archives := make(map[string]PMTilesArchiveStatus, len(sortedNames))
	ordered := make([]PMTilesArchiveStatus, 0, len(sortedNames))
	for _, name := range sortedNames {
		resolved, ok := resolvePMTilesArchive(name, dataDir, extraDirs)
		status := PMTilesArchiveStatus{
			Name:    name,
			URL:     "/maps/" + name,
			Warning: resolved.warning,
		}
		if ok {
			status.Source = resolved.source
			status.Available = true
			status.FullResolution = resolved.fullResolution
			status.FallbackOverview = resolved.fallbackOverview
			status.MinZoom = resolved.minZoom
			status.MaxZoom = resolved.maxZoom
			status.SizeBytes = resolved.sizeBytes
		} else {
			status.Source = "missing"
		}
		archives[name] = status
		ordered = append(ordered, status)
	}
	return PMTilesManifest{
		SchemaVersion: 1,
		Archives:      archives,
		Ordered:       ordered,
	}
}

// NewPMTilesAssetHandler wraps Wails' asset file server to serve /maps/<name>.pmtiles
// with RFC 7233 HTTP Range (206 Partial Content) support and /maps/manifest.json.
func NewPMTilesAssetHandler(fallback http.Handler, dataDir string, extraDirs ...string) http.Handler {
	copiedExtra := append([]string(nil), extraDirs...)
	return NewDynamicPMTilesAssetHandler(fallback, dataDir, func() []string { return copiedExtra })
}

// NewDynamicPMTilesAssetHandler wraps Wails' asset file server using a dynamic extraDirs provider
// so config.yml Spatial.AssetsDir updates and startup recovery take effect immediately.
func NewDynamicPMTilesAssetHandler(fallback http.Handler, dataDir string, getExtraDirs func() []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var copiedExtra []string
		if getExtraDirs != nil {
			copiedExtra = getExtraDirs()
		}
		rawURI := r.URL.EscapedPath()
		if rawURI == "" {
			rawURI = r.URL.Path
		}
		lowerURI := strings.ToLower(rawURI)
		if strings.HasPrefix(rawURI, "/maps/") || rawURI == "/maps" {
			// Reject encoded traversal sequences before URL path normalization.
			if strings.Contains(lowerURI, "%2e") || strings.Contains(lowerURI, "%2f") || strings.Contains(lowerURI, "%5c") || strings.Contains(rawURI, "..") {
				http.Error(w, "invalid map archive path", http.StatusBadRequest)
				return
			}
			rel := strings.TrimPrefix(r.URL.Path, "/maps/")
			if rel == "bc-proxy" || strings.HasPrefix(rel, "bc-proxy/") {
				serveBCGovMapProxy(w, r, defaultBCGovProxyConfig())
				return
			}
			if r.Method != http.MethodGet && r.Method != http.MethodHead {
				w.Header().Set("Allow", "GET, HEAD")
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
				return
			}
			if rel == "manifest.json" {
				manifest := BuildPMTilesManifest(dataDir, copiedExtra...)
				payload, err := json.Marshal(manifest)
				if err != nil {
					http.Error(w, "failed to encode manifest", http.StatusInternalServerError)
					return
				}
				w.Header().Set("Content-Type", "application/json; charset=utf-8")
				w.Header().Set("Cache-Control", "no-cache")
				http.ServeContent(w, r, "manifest.json", time.Time{}, bytes.NewReader(payload))
				return
			}
			clean, valid := validatePMTilesBasename(rel)
			if !valid {
				http.Error(w, "invalid PMTiles archive basename", http.StatusBadRequest)
				return
			}
			resolved, found := resolvePMTilesArchive(clean, dataDir, copiedExtra)
			if !found {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", PMTilesContentType)
			w.Header().Set("X-VPro-PMTiles-Source", resolved.source)
			if resolved.filePath != "" {
				f, err := os.Open(resolved.filePath)
				if err != nil {
					http.NotFound(w, r)
					return
				}
				defer f.Close()
				http.ServeContent(w, r, clean, resolved.modTime, f)
				return
			}
			http.ServeContent(w, r, clean, resolved.modTime, bytes.NewReader(resolved.embedded))
			return
		}
		if fallback != nil {
			fallback.ServeHTTP(w, r)
			return
		}
		http.NotFound(w, r)
	})
}
