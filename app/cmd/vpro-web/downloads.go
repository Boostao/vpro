package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	defaultDownloadTTL           = 5 * time.Minute
	defaultDownloadSweepInterval = 30 * time.Second
)

type downloadEntry struct {
	token       string
	filePath    string
	dirPath     string
	filename    string
	contentType string
	createdAt   time.Time
	expiresAt   time.Time
}

// DownloadStore manages single-use ephemeral export downloads strictly rooted
// inside VPRO_WEB_EXPORT_DIR/downloads, removing files immediately after serving
// or automatically when their TTL expires.
type DownloadStore struct {
	rootDir string
	ttl     time.Duration

	mu      sync.Mutex
	entries map[string]*downloadEntry
	stopCh  chan struct{}
	wg      sync.WaitGroup
	closed  bool
}

func NewDownloadStore(exportDir string, ttl time.Duration) (*DownloadStore, error) {
	if strings.TrimSpace(exportDir) == "" {
		return nil, errors.New("export directory is required")
	}
	if ttl <= 0 {
		ttl = defaultDownloadTTL
	}
	root := filepath.Join(exportDir, "downloads")
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("create download directory %q: %w", root, err)
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	store := &DownloadStore{
		rootDir: absRoot,
		ttl:     ttl,
		entries: make(map[string]*downloadEntry),
		stopCh:  make(chan struct{}),
	}
	sweepInterval := defaultDownloadSweepInterval
	if ttl < sweepInterval {
		sweepInterval = ttl
	}
	if sweepInterval < 100*time.Millisecond {
		sweepInterval = 100 * time.Millisecond
	}
	store.wg.Add(1)
	go store.sweepLoop(sweepInterval)
	return store, nil
}

func (s *DownloadStore) sweepLoop(interval time.Duration) {
	defer s.wg.Done()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			s.SweepExpired()
		case <-s.stopCh:
			return
		}
	}
}

func (s *DownloadStore) SweepExpired() int {
	now := time.Now()
	var expired []*downloadEntry

	s.mu.Lock()
	for token, entry := range s.entries {
		if !now.Before(entry.expiresAt) {
			delete(s.entries, token)
			expired = append(expired, entry)
		}
	}
	s.mu.Unlock()

	for _, entry := range expired {
		s.removeEntryFiles(entry)
	}
	return len(expired)
}

func (s *DownloadStore) Close() {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return
	}
	s.closed = true
	close(s.stopCh)
	remaining := make([]*downloadEntry, 0, len(s.entries))
	for token, entry := range s.entries {
		delete(s.entries, token)
		remaining = append(remaining, entry)
	}
	s.mu.Unlock()

	s.wg.Wait()
	for _, entry := range remaining {
		s.removeEntryFiles(entry)
	}
}

func (s *DownloadStore) ActiveCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.entries)
}

// MintTempPath allocates an isolated directory and file path strictly inside
// VPRO_WEB_EXPORT_DIR/downloads. Callers must call cleanup if Register is not called.
func (s *DownloadStore) MintTempPath(suggestedName string) (filePath, dirPath string, cleanup func(), err error) {
	if s == nil {
		return "", "", func() {}, errors.New("download store is unavailable")
	}
	safeName := sanitizeDownloadFilename(suggestedName)
	dirPath, err = os.MkdirTemp(s.rootDir, "vpro-dl-*")
	if err != nil {
		return "", "", func() {}, fmt.Errorf("mint temp export dir: %w", err)
	}
	filePath = filepath.Join(dirPath, safeName)
	cleanup = func() {
		_ = os.RemoveAll(dirPath)
	}
	return filePath, dirPath, cleanup, nil
}

// Register creates a single-use download token for filePath (which must reside inside rootDir).
func (s *DownloadStore) Register(filePath, dirPath, filename string) (token, downloadURL, safeFilename string, err error) {
	if s == nil {
		return "", "", "", errors.New("download store is unavailable")
	}
	absFile, err := filepath.Abs(filePath)
	if err != nil {
		return "", "", "", err
	}
	rel, err := filepath.Rel(s.rootDir, absFile)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", "", "", errors.New("download path escapes server export directory")
	}
	info, err := os.Stat(absFile)
	if err != nil {
		return "", "", "", fmt.Errorf("stat generated export artifact: %w", err)
	}
	if !info.Mode().IsRegular() {
		return "", "", "", errors.New("generated export artifact is not a regular file")
	}

	var buf [24]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", "", "", fmt.Errorf("generate download token: %w", err)
	}
	token = hex.EncodeToString(buf[:])
	safeFilename = sanitizeDownloadFilename(filename)
	now := time.Now()
	entry := &downloadEntry{
		token:       token,
		filePath:    absFile,
		dirPath:     dirPath,
		filename:    safeFilename,
		contentType: contentTypeForFilename(safeFilename),
		createdAt:   now,
		expiresAt:   now.Add(s.ttl),
	}

	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		s.removeEntryFiles(entry)
		return "", "", "", errors.New("download store is closed")
	}
	s.entries[token] = entry
	s.mu.Unlock()

	return token, "/api/downloads/" + token, safeFilename, nil
}

// ServeDownload streams the file for token with attachment headers and deletes
// the backing temp file immediately after serving.
func (s *DownloadStore) ServeDownload(w http.ResponseWriter, r *http.Request, token string) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	token = strings.TrimSpace(token)
	if len(token) != 48 || !isLowerHex(token) {
		writeJSONError(w, http.StatusNotFound, "download token not found or expired")
		return
	}

	s.mu.Lock()
	entry, ok := s.entries[token]
	if ok {
		delete(s.entries, token)
	}
	s.mu.Unlock()

	if !ok {
		writeJSONError(w, http.StatusNotFound, "download token not found or expired")
		return
	}
	defer s.removeEntryFiles(entry)

	if time.Now().After(entry.expiresAt) {
		writeJSONError(w, http.StatusGone, "download token expired")
		return
	}

	f, err := os.Open(entry.filePath)
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "download artifact is no longer available")
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to read download artifact metadata")
		return
	}

	w.Header().Set("Content-Type", entry.contentType)
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename=%q`, entry.filename))
	w.Header().Set("Content-Length", fmt.Sprintf("%d", info.Size()))
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = io.Copy(w, f)
	}
}

func (s *DownloadStore) removeEntryFiles(entry *downloadEntry) {
	if entry == nil {
		return
	}
	if entry.dirPath != "" {
		if rel, err := filepath.Rel(s.rootDir, entry.dirPath); err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			_ = os.RemoveAll(entry.dirPath)
			return
		}
	}
	if entry.filePath != "" {
		_ = os.Remove(entry.filePath)
	}
}

func sanitizeDownloadFilename(raw string) string {
	base := filepath.Base(strings.TrimSpace(raw))
	if base == "" || base == "." || base == ".." || base == string(filepath.Separator) {
		return "vpro-export.bin"
	}
	var b strings.Builder
	b.Grow(len(base))
	for _, r := range base {
		switch {
		case r >= 'a' && r <= 'z',
			r >= 'A' && r <= 'Z',
			r >= '0' && r <= '9',
			r == '.', r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	out := strings.TrimLeft(b.String(), ".")
	if out == "" {
		return "vpro-export.bin"
	}
	if len(out) > 128 {
		ext := filepath.Ext(out)
		stem := strings.TrimSuffix(out, ext)
		if len(stem) > 100 {
			stem = stem[:100]
		}
		out = stem + ext
	}
	return out
}

func contentTypeForFilename(filename string) string {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".xlsx":
		return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	case ".pdf":
		return "application/pdf"
	case ".kml":
		return "application/vnd.google-earth.kml+xml"
	case ".zip":
		return "application/zip"
	case ".csv":
		return "text/csv; charset=utf-8"
	case ".json":
		return "application/json; charset=utf-8"
	case ".gpkg":
		return "application/geopackage+sqlite3"
	case ".rds":
		return "application/octet-stream"
	case ".xml":
		return "application/xml; charset=utf-8"
	case ".sqlite", ".db":
		return "application/vnd.sqlite3"
	case ".html", ".htm":
		return "text/html; charset=utf-8"
	default:
		return "application/octet-stream"
	}
}

func isLowerHex(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return len(s) > 0
}
