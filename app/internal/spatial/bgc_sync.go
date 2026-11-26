package spatial

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	// DefaultBGCMapSyncURLEnvVar optionally configures the default HTTPS URL for BGC v13 PMTiles sync.
	DefaultBGCMapSyncURLEnvVar = "VPRO_BGC_MAP_URL"

	// DefaultBGCMapArchiveName is the canonical provincial BGC v13 PMTiles archive filename.
	DefaultBGCMapArchiveName = PMTilesBGCArchiveName

	bgcMapSyncMaxBytes       = 2 * 1024 * 1024 * 1024 // 2 GiB safety ceiling
	bgcMapSyncMaxChecksumLen = 4096
	bgcMapSyncUserAgent      = "VPro/2.0 (BC Ministry of Forests BEC Map Sync)"
	bgcMapSyncTimeout        = 15 * time.Minute
	bgcMapSyncMaxRedirects   = 5
)

// BGCMapSyncStatus reports the active resolution state and local target for bc-bgc-v13.pmtiles.
type BGCMapSyncStatus struct {
	ArchiveName      string `json:"archiveName"`
	TargetPath       string `json:"targetPath"`
	ActiveSource     string `json:"activeSource"` // "dataDir" | "extraDir" | "embedded-overview" | "missing"
	ActivePath       string `json:"activePath,omitempty"`
	Available        bool   `json:"available"`
	FullResolution   bool   `json:"fullResolution"`
	FallbackOverview bool   `json:"fallbackOverview"`
	MinZoom          int    `json:"minZoom"`
	MaxZoom          int    `json:"maxZoom"`
	SizeBytes        int64  `json:"sizeBytes"`
	ModTime          string `json:"modTime,omitempty"`
	SHA256           string `json:"sha256,omitempty"`
	DefaultSourceURL string `json:"defaultSourceUrl,omitempty"`
	Warning          string `json:"warning,omitempty"`
}

// BGCMapSyncResult summarizes an atomic bc-bgc-v13.pmtiles sync outcome.
type BGCMapSyncResult struct {
	ArchiveName    string           `json:"archiveName"`
	TargetPath     string           `json:"targetPath"`
	SourceURL      string           `json:"sourceUrl"`
	SizeBytes      int64            `json:"sizeBytes"`
	SHA256         string           `json:"sha256"`
	ChecksumSource string           `json:"checksumSource"` // "explicit" | "companion" | "none"
	MinZoom        int              `json:"minZoom"`
	MaxZoom        int              `json:"maxZoom"`
	SyncedAt       string           `json:"syncedAt"`
	Status         BGCMapSyncStatus `json:"status"`
}

func isLoopbackHost(host string) bool {
	h := strings.TrimSpace(strings.ToLower(host))
	if h == "" {
		return false
	}
	if h == "localhost" {
		return true
	}
	ip := net.ParseIP(h)
	return ip != nil && ip.IsLoopback()
}

func validateBGCMapSourceURL(raw string) (*url.URL, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil, errors.New("BGC map sync requires a non-empty HTTPS source URL")
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return nil, fmt.Errorf("invalid BGC map source URL %q: %w", trimmed, err)
	}
	if parsed.Host == "" || parsed.Hostname() == "" {
		return nil, fmt.Errorf("BGC map source URL %q is missing a host", trimmed)
	}
	scheme := strings.ToLower(parsed.Scheme)
	switch scheme {
	case "https":
		return parsed, nil
	case "http":
		if isLoopbackHost(parsed.Hostname()) {
			return parsed, nil
		}
		return nil, fmt.Errorf("BGC map sync requires HTTPS (plain HTTP is only allowed for loopback testing; got %q)", trimmed)
	default:
		return nil, fmt.Errorf("BGC map sync requires HTTPS (unsupported scheme %q)", parsed.Scheme)
	}
}

func normalizeSHA256Hex(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", nil
	}
	lower := strings.ToLower(trimmed)
	lower = strings.TrimPrefix(lower, "sha256:")
	lower = strings.TrimSpace(lower)
	if len(lower) != 64 {
		return "", fmt.Errorf("expectedSHA256 must be a 64-character hexadecimal SHA-256 digest (got %d chars)", len(lower))
	}
	if _, err := hex.DecodeString(lower); err != nil {
		return "", fmt.Errorf("expectedSHA256 is not valid hexadecimal: %w", err)
	}
	return lower, nil
}

func parseCompanionSHA256Body(body []byte) (string, error) {
	text := strings.TrimSpace(string(body))
	if text == "" {
		return "", errors.New("companion .sha256 file is empty")
	}
	// Accept either "<64-hex>  filename" or bare "<64-hex>" (first non-empty line, first field).
	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		digest, err := normalizeSHA256Hex(fields[0])
		if err != nil {
			return "", fmt.Errorf("companion .sha256 file contains invalid digest: %w", err)
		}
		return digest, nil
	}
	return "", errors.New("companion .sha256 file contained no digest")
}

func readFileSHA256Sidecar(path string) string {
	raw, err := os.ReadFile(path + ".sha256")
	if err != nil {
		return ""
	}
	digest, err := parseCompanionSHA256Body(raw)
	if err != nil {
		return ""
	}
	return digest
}

func computeFileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// GetBGCMapSyncStatus reports the active BGC v13 PMTiles archive status and local sync target.
func GetBGCMapSyncStatus(dataDir string, extraDirs []string, defaultURL string) BGCMapSyncStatus {
	resolvedDefault := strings.TrimSpace(defaultURL)
	if resolvedDefault == "" {
		resolvedDefault = strings.TrimSpace(os.Getenv(DefaultBGCMapSyncURLEnvVar))
	}

	targetPath := ""
	if strings.TrimSpace(dataDir) != "" {
		targetPath = filepath.Join(dataDir, "maps", PMTilesBGCArchiveName)
	}

	resolved, found := resolvePMTilesArchive(PMTilesBGCArchiveName, dataDir, extraDirs)
	status := BGCMapSyncStatus{
		ArchiveName:      PMTilesBGCArchiveName,
		TargetPath:       targetPath,
		DefaultSourceURL: resolvedDefault,
		Warning:          resolved.warning,
	}
	if !found {
		status.ActiveSource = "missing"
		return status
	}

	status.ActiveSource = resolved.source
	status.ActivePath = resolved.filePath
	status.Available = true
	status.FullResolution = resolved.fullResolution
	status.FallbackOverview = resolved.fallbackOverview
	status.MinZoom = resolved.minZoom
	status.MaxZoom = resolved.maxZoom
	status.SizeBytes = resolved.sizeBytes
	if !resolved.modTime.IsZero() {
		status.ModTime = resolved.modTime.UTC().Format(time.RFC3339)
	}

	if resolved.filePath != "" {
		if sidecar := readFileSHA256Sidecar(resolved.filePath); sidecar != "" {
			status.SHA256 = sidecar
		} else if resolved.sizeBytes > 0 && resolved.sizeBytes <= 64*1024*1024 {
			if sum, err := computeFileSHA256(resolved.filePath); err == nil {
				status.SHA256 = sum
			}
		}
	}
	return status
}

func newBGCMapSyncHTTPClient() *http.Client {
	return &http.Client{
		Timeout: bgcMapSyncTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= bgcMapSyncMaxRedirects {
				return fmt.Errorf("BGC map sync exceeded maximum redirect limit (%d)", bgcMapSyncMaxRedirects)
			}
			if _, err := validateBGCMapSourceURL(req.URL.String()); err != nil {
				return fmt.Errorf("redirect blocked: %w", err)
			}
			return nil
		},
	}
}

func fetchCompanionSHA256(ctx context.Context, client *http.Client, sourceURL *url.URL) (string, bool, error) {
	companion := *sourceURL
	companion.Path = companion.Path + ".sha256"
	companion.RawPath = ""

	reqCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, companion.String(), nil)
	if err != nil {
		return "", false, nil
	}
	req.Header.Set("User-Agent", bgcMapSyncUserAgent)
	req.Header.Set("Accept", "text/plain, */*;q=0.1")

	resp, err := client.Do(req)
	if err != nil {
		// Companion checksum is optional if server rejects or does not serve it; only fail if ctx canceled.
		if ctx.Err() != nil {
			return "", false, ctx.Err()
		}
		return "", false, nil
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusMethodNotAllowed {
		return "", false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return "", false, nil
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, bgcMapSyncMaxChecksumLen+1))
	if err != nil {
		return "", false, fmt.Errorf("read companion .sha256: %w", err)
	}
	if len(body) > bgcMapSyncMaxChecksumLen {
		return "", false, errors.New("companion .sha256 response exceeded maximum allowed size")
	}
	digest, err := parseCompanionSHA256Body(body)
	if err != nil {
		return "", false, err
	}
	return digest, true, nil
}

func atomicWriteFile(path string, content []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".vpro-bgc-sidecar-*.tmp")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	success := false
	defer func() {
		if !success {
			_ = os.Remove(tmpPath)
		}
	}()
	if _, err := tmp.Write(content); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmpPath, perm); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return err
	}
	success = true
	return nil
}

// SyncLatestBGCMap downloads a provincial BGC v13 PMTiles archive over HTTPS (or loopback for tests),
// validates its PMTiles v3 header and root directory, verifies SHA-256 (explicit or companion .sha256),
// and atomically swaps <dataDir>/maps/bc-bgc-v13.pmtiles.
func SyncLatestBGCMap(ctx context.Context, dataDir, sourceURL, expectedSHA256 string) (*BGCMapSyncResult, error) {
	if ctx == nil {
		return nil, errors.New("BGC map sync requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	dataDir = strings.TrimSpace(dataDir)
	if dataDir == "" {
		return nil, errors.New("BGC map sync requires a non-empty dataDir")
	}

	resolvedURLStr := strings.TrimSpace(sourceURL)
	if resolvedURLStr == "" {
		resolvedURLStr = strings.TrimSpace(os.Getenv(DefaultBGCMapSyncURLEnvVar))
	}
	parsedURL, err := validateBGCMapSourceURL(resolvedURLStr)
	if err != nil {
		return nil, err
	}

	wantSHA256, err := normalizeSHA256Hex(expectedSHA256)
	if err != nil {
		return nil, err
	}
	checksumSource := "none"
	if wantSHA256 != "" {
		checksumSource = "explicit"
	}

	client := newBGCMapSyncHTTPClient()
	if wantSHA256 == "" {
		companionHash, found, cErr := fetchCompanionSHA256(ctx, client, parsedURL)
		if cErr != nil {
			return nil, cErr
		}
		if found {
			wantSHA256 = companionHash
			checksumSource = "companion"
		}
	}

	mapsDir := filepath.Join(dataDir, "maps")
	if err := os.MkdirAll(mapsDir, 0o755); err != nil {
		return nil, fmt.Errorf("create maps directory %q: %w", mapsDir, err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, parsedURL.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("construct BGC map sync request: %w", err)
	}
	req.Header.Set("User-Agent", bgcMapSyncUserAgent)
	req.Header.Set("Accept", PMTilesContentType+", application/octet-stream, */*;q=0.1")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download BGC map archive: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("BGC map server returned HTTP %d", resp.StatusCode)
	}

	tmpFile, err := os.CreateTemp(mapsDir, ".bc-bgc-v13-*.pmtiles.tmp")
	if err != nil {
		return nil, fmt.Errorf("stage temp PMTiles file: %w", err)
	}
	tmpPath := tmpFile.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(tmpPath)
		}
	}()

	hasher := sha256.New()
	limitedReader := io.LimitReader(resp.Body, bgcMapSyncMaxBytes+1)
	written, copyErr := io.Copy(io.MultiWriter(tmpFile, hasher), limitedReader)
	if copyErr != nil {
		_ = tmpFile.Close()
		return nil, fmt.Errorf("stream BGC map archive to disk: %w", copyErr)
	}
	if written > bgcMapSyncMaxBytes {
		_ = tmpFile.Close()
		return nil, fmt.Errorf("BGC map archive exceeded maximum allowed size (%d bytes)", bgcMapSyncMaxBytes)
	}
	if err := tmpFile.Sync(); err != nil {
		_ = tmpFile.Close()
		return nil, fmt.Errorf("sync staged BGC map archive: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return nil, fmt.Errorf("close staged BGC map archive: %w", err)
	}

	actualSHA256 := hex.EncodeToString(hasher.Sum(nil))
	if wantSHA256 != "" && actualSHA256 != wantSHA256 {
		return nil, fmt.Errorf("BGC map SHA-256 checksum mismatch (%s): got %s, expected %s", checksumSource, actualSHA256, wantSHA256)
	}

	// Validate PMTiles v3 header & root directory before swapping into place.
	sizeBytes, _, minZ, maxZ, vErr := validatePMTilesArchiveFile(tmpPath)
	if vErr != nil {
		return nil, fmt.Errorf("downloaded BGC map failed PMTiles v3 validation: %w", vErr)
	}

	if err := os.Chmod(tmpPath, 0o644); err != nil {
		return nil, fmt.Errorf("set permissions on staged BGC map: %w", err)
	}

	targetPath := filepath.Join(mapsDir, PMTilesBGCArchiveName)
	if err := os.Rename(tmpPath, targetPath); err != nil {
		return nil, fmt.Errorf("atomically swap %s: %w", targetPath, err)
	}
	committed = true

	// Best-effort atomic sidecar .sha256 so GetBGCMapSyncStatus reports the digest instantaneously.
	_ = atomicWriteFile(targetPath+".sha256", []byte(fmt.Sprintf("%s  %s\n", actualSHA256, PMTilesBGCArchiveName)), 0o644)

	status := GetBGCMapSyncStatus(dataDir, nil, parsedURL.String())
	return &BGCMapSyncResult{
		ArchiveName:    PMTilesBGCArchiveName,
		TargetPath:     targetPath,
		SourceURL:      parsedURL.String(),
		SizeBytes:      sizeBytes,
		SHA256:         actualSHA256,
		ChecksumSource: checksumSource,
		MinZoom:        minZ,
		MaxZoom:        maxZ,
		SyncedAt:       time.Now().UTC().Format(time.RFC3339),
		Status:         status,
	}, nil
}
