package main

import (
	"embed"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

//go:embed all:static
var embeddedStaticFS embed.FS

// newSPAHandler serves the read-only web SPA from an optional filesystem override
// (VPRO_WEB_STATIC_DIR) or from the embedded static/ directory, with clean SPA
// fallback to index.html for client-side routes and strict 404 isolation for /api/
// and /internal/ paths.
func newSPAHandler(overrideDir string) http.Handler {
	var root fs.FS
	if trimmed := strings.TrimSpace(overrideDir); trimmed != "" {
		root = os.DirFS(trimmed)
	} else {
		sub, err := fs.Sub(embeddedStaticFS, "static")
		if err == nil {
			root = sub
		}
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		reqPath := r.URL.Path
		if strings.HasPrefix(reqPath, "/api/") || reqPath == "/api" ||
			strings.HasPrefix(reqPath, "/internal/") || reqPath == "/internal" {
			writeJSONError(w, http.StatusNotFound, "endpoint not found")
			return
		}
		if root == nil {
			http.NotFound(w, r)
			return
		}

		cleaned := strings.TrimPrefix(path.Clean("/"+reqPath), "/")
		if cleaned == "" || cleaned == "." {
			serveStaticFile(w, r, root, "index.html", false)
			return
		}
		// Never expose dotfiles like .gitkeep.
		for _, seg := range strings.Split(cleaned, "/") {
			if strings.HasPrefix(seg, ".") {
				http.NotFound(w, r)
				return
			}
		}

		if info, err := fs.Stat(root, cleaned); err == nil && !info.IsDir() {
			immutable := strings.HasPrefix(cleaned, "assets/")
			serveStaticFile(w, r, root, cleaned, immutable)
			return
		}

		// If the path looks like a missing static asset (has a file extension), return 404
		// rather than returning HTML with a 200 status.
		if ext := filepath.Ext(cleaned); ext != "" && !strings.EqualFold(ext, ".html") {
			http.NotFound(w, r)
			return
		}

		// SPA fallback to index.html.
		serveStaticFile(w, r, root, "index.html", false)
	})
}

func serveStaticFile(w http.ResponseWriter, r *http.Request, root fs.FS, relPath string, immutable bool) {
	f, err := root.Open(relPath)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil || info.IsDir() {
		http.NotFound(w, r)
		return
	}

	if ext := filepath.Ext(relPath); ext != "" {
		if ct := mime.TypeByExtension(ext); ct != "" {
			w.Header().Set("Content-Type", ct)
		}
	}
	if immutable {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "no-cache")
	}
	w.Header().Set("X-Content-Type-Options", "nosniff")

	if rs, ok := f.(io.ReadSeeker); ok {
		http.ServeContent(w, r, info.Name(), info.ModTime(), rs)
		return
	}
	data, err := io.ReadAll(f)
	if err != nil {
		http.Error(w, "failed to read static asset", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = w.Write(data)
	}
}
