package spatial

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/resources"
)

func TestBGCMapSyncStatusAndAtomicSwap(t *testing.T) {
	ctx := context.Background()
	dataDir := t.TempDir()

	// 1. Fresh install falls back to embedded overview.
	initial := GetBGCMapSyncStatus(dataDir, nil, "https://example.org/bc-bgc-v13.pmtiles")
	if !initial.Available || initial.ActiveSource != "embedded-overview" || !initial.FallbackOverview {
		t.Fatalf("unexpected fresh BGC map sync status: %+v", initial)
	}
	if initial.DefaultSourceURL != "https://example.org/bc-bgc-v13.pmtiles" {
		t.Fatalf("unexpected default source URL: %q", initial.DefaultSourceURL)
	}

	validPayload := resources.BCOverviewPMTiles
	sum := sha256.Sum256(validPayload)
	validHash := hex.EncodeToString(sum[:])

	serveCompanion := false
	companionBody := fmt.Sprintf("%s  bc-bgc-v13.pmtiles\n", validHash)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/bc-bgc-v13.pmtiles":
			w.Header().Set("Content-Type", PMTilesContentType)
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(validPayload)
		case "/bc-bgc-v13.pmtiles.sha256":
			if !serveCompanion {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", "text/plain")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(companionBody))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	// 2. Sync with explicit SHA-256 over loopback HTTP (allowed for tests)
	resExplicit, err := SyncLatestBGCMap(ctx, dataDir, srv.URL+"/bc-bgc-v13.pmtiles", validHash)
	if err != nil {
		t.Fatalf("SyncLatestBGCMap explicit sha256 failed: %v", err)
	}
	if resExplicit.ChecksumSource != "explicit" || resExplicit.SHA256 != validHash || resExplicit.SizeBytes != int64(len(validPayload)) {
		t.Fatalf("unexpected explicit sync result: %+v", resExplicit)
	}
	targetPath := filepath.Join(dataDir, "maps", PMTilesBGCArchiveName)
	gotBytes, err := os.ReadFile(targetPath)
	if err != nil || !bytes.Equal(gotBytes, validPayload) {
		t.Fatalf("synced target file mismatch: err=%v len=%d", err, len(gotBytes))
	}

	// Status should now resolve from dataDir with matching SHA-256.
	after := GetBGCMapSyncStatus(dataDir, nil, "")
	if after.ActiveSource != "dataDir" || after.SHA256 != validHash || after.SizeBytes != int64(len(validPayload)) {
		t.Fatalf("unexpected post-sync status: %+v", after)
	}

	// 3. Sync with companion .sha256 auto-discovery
	serveCompanion = true
	resCompanion, err := SyncLatestBGCMap(ctx, dataDir, srv.URL+"/bc-bgc-v13.pmtiles", "")
	if err != nil {
		t.Fatalf("SyncLatestBGCMap companion sha256 failed: %v", err)
	}
	if resCompanion.ChecksumSource != "companion" || resCompanion.SHA256 != validHash {
		t.Fatalf("expected companion checksum verification, got %+v", resCompanion)
	}

	// 4. Sync with no explicit hash and 404 companion .sha256 still validates PMTiles v3 header & succeeds
	serveCompanion = false
	resNoHash, err := SyncLatestBGCMap(ctx, dataDir, srv.URL+"/bc-bgc-v13.pmtiles", "")
	if err != nil {
		t.Fatalf("SyncLatestBGCMap without checksum failed: %v", err)
	}
	if resNoHash.ChecksumSource != "none" || resNoHash.SHA256 != validHash {
		t.Fatalf("unexpected no-hash sync result: %+v", resNoHash)
	}
}

func TestBGCMapSyncSecurityAndAtomicRollback(t *testing.T) {
	ctx := context.Background()
	dataDir := t.TempDir()

	// Seed an existing valid bc-bgc-v13.pmtiles file so we can verify failed syncs never corrupt it.
	mapsDir := filepath.Join(dataDir, "maps")
	if err := os.MkdirAll(mapsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	targetPath := filepath.Join(mapsDir, PMTilesBGCArchiveName)
	if err := os.WriteFile(targetPath, resources.BCOverviewPMTiles, 0o644); err != nil {
		t.Fatal(err)
	}

	// 1. HTTPS-only enforcement (reject non-loopback HTTP & non-HTTP schemes)
	for _, badURL := range []string{
		"",
		"http://example.com/bc-bgc-v13.pmtiles",
		"http://192.168.1.5/bc-bgc-v13.pmtiles",
		"file:///etc/passwd",
		"ftp://example.com/bc-bgc-v13.pmtiles",
	} {
		if _, err := SyncLatestBGCMap(ctx, dataDir, badURL, ""); err == nil {
			t.Errorf("expected SyncLatestBGCMap to reject insecure URL %q", badURL)
		}
	}

	// 2. Reject redirect downgrade to plain HTTP non-loopback host
	redirSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://example.com/evil.pmtiles", http.StatusFound)
	}))
	defer redirSrv.Close()
	if _, err := SyncLatestBGCMap(ctx, dataDir, redirSrv.URL+"/bc-bgc-v13.pmtiles", ""); err == nil {
		t.Fatal("expected redirect to non-HTTPS non-loopback URL to be rejected")
	}

	// 3. Reject invalid PMTiles v3 payload & preserve existing file
	corruptSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".sha256") {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("NOT_A_VALID_PMTILES_ARCHIVE_AT_ALL"))
	}))
	defer corruptSrv.Close()
	if _, err := SyncLatestBGCMap(ctx, dataDir, corruptSrv.URL+"/bc-bgc-v13.pmtiles", ""); err == nil {
		t.Fatal("expected corrupt PMTiles payload to fail validation")
	}

	// 4. Reject SHA-256 mismatch (both explicit and companion .sha256)
	badHash := strings.Repeat("a", 64)
	validSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".sha256") {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(badHash + "  bc-bgc-v13.pmtiles\n"))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(resources.BCOverviewPMTiles)
	}))
	defer validSrv.Close()

	if _, err := SyncLatestBGCMap(ctx, dataDir, validSrv.URL+"/bc-bgc-v13.pmtiles", badHash); err == nil {
		t.Fatal("expected explicit SHA-256 mismatch error")
	}
	if _, err := SyncLatestBGCMap(ctx, dataDir, validSrv.URL+"/bc-bgc-v13.pmtiles", ""); err == nil {
		t.Fatal("expected companion .sha256 mismatch error")
	}
	if _, err := SyncLatestBGCMap(ctx, dataDir, validSrv.URL+"/bc-bgc-v13.pmtiles", "not-hex"); err == nil {
		t.Fatal("expected malformed expectedSHA256 error")
	}

	// Verify existing file remained completely untouched after all failed attempts.
	stillValid, err := os.ReadFile(targetPath)
	if err != nil || !bytes.Equal(stillValid, resources.BCOverviewPMTiles) {
		t.Fatalf("existing bc-bgc-v13.pmtiles was modified or corrupted after failed syncs: err=%v", err)
	}
}
