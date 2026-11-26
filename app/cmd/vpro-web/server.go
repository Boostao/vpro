package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/boostao/vpro/app/internal/lifecycle"
	"github.com/boostao/vpro/app/internal/pictures"
	"github.com/boostao/vpro/app/internal/references"
	"github.com/boostao/vpro/app/internal/rsidecar"
	"github.com/boostao/vpro/app/internal/spatial"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type webReferenceCatalogs struct {
	refDir       string
	configDir    string
	references   *references.ReferenceService
	bec          *references.BECService
	quality      *references.QualityService
	siteCodes    *references.SiteCodeService
	regionCodes  *references.RegionCodeService
	soilCodes    *references.SoilCodeService
	geologyCodes *references.GeologyCodeService
	parentCodes  *references.ParentCodeService
	masterWU     *vprocore.WorkingUnitService
}

func openWebReferenceCatalogs(exportDir string) (*webReferenceCatalogs, error) {
	refDir := filepath.Join(exportDir, "ref-catalogs")
	configDir := filepath.Join(exportDir, "ref-config")
	if err := os.MkdirAll(refDir, 0o750); err != nil {
		return nil, fmt.Errorf("create reference catalog dir: %w", err)
	}
	if err := os.MkdirAll(configDir, 0o750); err != nil {
		return nil, fmt.Errorf("create reference config dir: %w", err)
	}

	b := &webReferenceCatalogs{refDir: refDir, configDir: configDir}
	var err error
	if b.references, err = references.NewReferenceService(refDir); err != nil {
		log.Printf("vpro-web warning: ReferenceService unavailable: %v", err)
	}
	if b.bec, err = references.NewBECService(refDir); err != nil {
		log.Printf("vpro-web warning: BECService unavailable: %v", err)
	}
	if b.quality, err = references.NewQualityService(refDir); err != nil {
		log.Printf("vpro-web warning: QualityService unavailable: %v", err)
	}
	if b.siteCodes, err = references.NewSiteCodeService(refDir); err != nil {
		log.Printf("vpro-web warning: SiteCodeService unavailable: %v", err)
	}
	if b.regionCodes, err = references.NewRegionCodeService(refDir); err != nil {
		log.Printf("vpro-web warning: RegionCodeService unavailable: %v", err)
	}
	if b.soilCodes, err = references.NewSoilCodeService(refDir); err != nil {
		log.Printf("vpro-web warning: SoilCodeService unavailable: %v", err)
	}
	if b.geologyCodes, err = references.NewGeologyCodeService(refDir); err != nil {
		log.Printf("vpro-web warning: GeologyCodeService unavailable: %v", err)
	}
	if b.parentCodes, err = references.NewParentCodeService(refDir); err != nil {
		log.Printf("vpro-web warning: ParentCodeService unavailable: %v", err)
	}
	return b, nil
}

func (b *webReferenceCatalogs) initMasterWorkingUnits(ctx context.Context, pool *vprocore.ReadOnlyContextPool, defaultSel vprocore.SelectionKey) {
	if b == nil || pool == nil || b.masterWU != nil {
		return
	}
	basePrefs, err := vprocore.NewInMemoryDesktopConfig(nil)
	if err != nil {
		return
	}
	lease, err := pool.Acquire(ctx, defaultSel, basePrefs)
	if err != nil {
		return
	}
	defer lease.Release()
	p := lease.Context.Projects
	proxy := &vprocore.ProjectService{
		Root:         b.refDir,
		Active:       p.Active,
		ActiveSU:     p.ActiveSU,
		Preferences:  basePrefs,
		Sqlite:       p.Sqlite,
		SupportPaths: p.SupportPaths,
		ContextID:    p.ContextID,
	}
	wu, err := vprocore.NewWorkingUnitService(proxy, b.configDir)
	if err != nil {
		log.Printf("vpro-web warning: master WorkingUnitService unavailable: %v", err)
		return
	}
	b.masterWU = wu
}

func (b *webReferenceCatalogs) Close() {
	if b == nil {
		return
	}
	if b.masterWU != nil {
		_ = b.masterWU.Close()
	}
	if b.references != nil {
		_ = b.references.Close()
	}
	if b.parentCodes != nil {
		_ = b.parentCodes.Close()
	}
	if b.geologyCodes != nil {
		_ = b.geologyCodes.Close()
	}
	if b.soilCodes != nil {
		_ = b.soilCodes.Close()
	}
	if b.regionCodes != nil {
		_ = b.regionCodes.Close()
	}
	if b.siteCodes != nil {
		_ = b.siteCodes.Close()
	}
	if b.bec != nil {
		_ = b.bec.Close()
	}
}

// WebServer owns the read-only snapshot pool, ephemeral session store, download store,
// bounded LRU preview cache, RPC router, PMTiles handler, and reload/stats endpoints.
type WebServer struct {
	cfg        WebConfig
	startedAt  time.Time
	refs       *webReferenceCatalogs
	pool       *vprocore.ReadOnlyContextPool
	sessions   *SessionPrefsStore
	downloads  *DownloadStore
	cache      *PreviewCache
	router     *RPCRouter
	attributor *spatial.PMTilesAttributor
	pmtilesHdl http.Handler
	spaHdl     http.Handler

	exportSem       chan struct{}
	rSem            chan struct{}
	exportInFlight  atomic.Int64
	rInFlight       atomic.Int64
	reloadCount     atomic.Int64

	snapMu        sync.RWMutex
	snapshot      *LoadedSnapshot
	vpicsPath     string
	picturesDir   string
	picturesAvail bool
	rAvailable    bool
	rCheckedOnce  bool

	reloadMu sync.Mutex
}

func NewWebServer(ctx context.Context, cfg WebConfig) (*WebServer, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := os.MkdirAll(cfg.ExportDir, 0o750); err != nil {
		return nil, fmt.Errorf("create export dir %q: %w", cfg.ExportDir, err)
	}

	var (
		snap *LoadedSnapshot
		err  error
	)
	if cfg.DevSample && cfg.DataDir == "" {
		snap, err = ProvisionDevSampleSnapshot(ctx, cfg.ExportDir)
	} else {
		snap, err = LoadVerifiedSnapshot(cfg.DataDir)
	}
	if err != nil {
		return nil, fmt.Errorf("load snapshot: %w", err)
	}

	refs, err := openWebReferenceCatalogs(cfg.ExportDir)
	if err != nil {
		return nil, err
	}

	pool, err := vprocore.NewReadOnlyContextPool(snap.Catalog, vprocore.ReadOnlyPoolOptions{
		SlotsPerKey: cfg.PoolSlots,
		MaxPools:    cfg.MaxPools,
		SiteCodes:   refs.siteCodes,
		ParentCodes: refs.parentCodes,
	})
	if err != nil {
		refs.Close()
		return nil, fmt.Errorf("init read-only context pool: %w", err)
	}
	refs.initMasterWorkingUnits(ctx, pool, snap.DefaultSelection())

	sessions, err := NewSessionPrefsStore(defaultMaxSessions, defaultSessionIdleTTL)
	if err != nil {
		_ = pool.Close()
		refs.Close()
		return nil, fmt.Errorf("init session store: %w", err)
	}

	downloads, err := NewDownloadStore(cfg.ExportDir, defaultDownloadTTL)
	if err != nil {
		_ = pool.Close()
		refs.Close()
		return nil, fmt.Errorf("init download store: %w", err)
	}

	cache := NewPreviewCache(cfg.CacheMaxMB)

	var extraDirs []string
	if strings.TrimSpace(cfg.PMTilesDir) != "" {
		if info, statErr := os.Stat(cfg.PMTilesDir); statErr == nil && info.IsDir() {
			extraDirs = append(extraDirs, cfg.PMTilesDir)
		}
	}
	attributor := spatial.NewPMTilesAttributor(cfg.PMTilesDir, extraDirs...)
	spaHdl := newSPAHandler(cfg.StaticDir)
	pmtilesHdl := spatial.NewDynamicPMTilesAssetHandler(nil, cfg.PMTilesDir, func() []string { return extraDirs })

	srv := &WebServer{
		cfg:        cfg,
		startedAt:  time.Now().UTC(),
		refs:       refs,
		pool:       pool,
		sessions:   sessions,
		downloads:  downloads,
		cache:      cache,
		attributor: attributor,
		pmtilesHdl: pmtilesHdl,
		spaHdl:     spaHdl,
		exportSem:  make(chan struct{}, cfg.ExportConcurrency),
		rSem:       make(chan struct{}, cfg.RConcurrency),
		snapshot:   snap,
	}

	srv.refreshPicturesStateLocked(snap)
	srv.probeRRuntime(ctx)

	router, err := NewRPCRouter(srv)
	if err != nil {
		srv.Close()
		return nil, fmt.Errorf("init RPC router: %w", err)
	}
	srv.router = router

	return srv, nil
}

func (s *WebServer) Close() {
	if s == nil {
		return
	}
	if s.downloads != nil {
		s.downloads.Close()
	}
	if s.pool != nil {
		_ = s.pool.Close()
	}
	if s.attributor != nil {
		_ = s.attributor.Close()
	}
	if s.refs != nil {
		s.refs.Close()
	}
}

func (s *WebServer) currentSnapshot() *LoadedSnapshot {
	s.snapMu.RLock()
	defer s.snapMu.RUnlock()
	return s.snapshot
}

func (s *WebServer) refreshPicturesStateLocked(snap *LoadedSnapshot) {
	vpics := strings.TrimSpace(s.cfg.VPicsPath)
	if vpics == "" && snap != nil {
		for _, candidate := range []string{
			filepath.Join(snap.ResolvedRoot, "database-family", "VPics.db"),
			filepath.Join(snap.ResolvedRoot, "VPics.db"),
		} {
			if info, err := os.Stat(candidate); err == nil && info.Mode().IsRegular() {
				vpics = candidate
				break
			}
		}
	}
	if vpics != "" {
		if info, err := os.Stat(vpics); err != nil || !info.Mode().IsRegular() {
			vpics = ""
		}
	}

	picDir := strings.TrimSpace(s.cfg.PicturesDir)
	if picDir != "" {
		if info, err := os.Stat(picDir); err != nil || !info.IsDir() {
			picDir = ""
		}
	}

	s.vpicsPath = vpics
	s.picturesDir = picDir
	s.picturesAvail = vpics != ""
}

func (s *WebServer) pictureAvailability() (vpicsPath, picturesDir string, available bool) {
	s.snapMu.RLock()
	defer s.snapMu.RUnlock()
	return s.vpicsPath, s.picturesDir, s.picturesAvail
}

func (s *WebServer) buildReadOnlyPictureService(ctxSvc *vprocore.ContextService) (*pictures.PictureService, error) {
	vpicsPath, picturesDir, available := s.pictureAvailability()
	if !available || vpicsPath == "" {
		return nil, errors.New("plot picture library is not configured in this read-only deployment")
	}
	lookup := func(key string) (string, bool) {
		switch key {
		case "VPRO_PICTURE_LIBRARY_PATH":
			return vpicsPath, true
		case "VPRO_PICTURE_CHILD_DIRECTORY":
			if picturesDir != "" {
				return picturesDir, true
			}
			return "", false
		case "VPRO_PICTURE_MANAGER_DIRECTORY":
			if picturesDir != "" {
				return picturesDir, true
			}
			return "", false
		default:
			return "", false
		}
	}
	return pictures.NewPictureServiceWithDefaults(ctxSvc, lookup, vpicsPath, picturesDir)
}

func (s *WebServer) probeRRuntime(ctx context.Context) {
	probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	status, err := rsidecar.DetectRRuntime(probeCtx, s.rRuntimeOptions()...)
	avail := err == nil && status != nil && status.Available
	s.snapMu.Lock()
	s.rAvailable = avail
	s.rCheckedOnce = true
	s.snapMu.Unlock()
}

func (s *WebServer) isRAvailable() bool {
	s.snapMu.RLock()
	defer s.snapMu.RUnlock()
	return s.rAvailable
}

func (s *WebServer) rRuntimeOptions() []rsidecar.RuntimeOptions {
	return []rsidecar.RuntimeOptions{{DataDir: s.cfg.ExportDir}}
}

func (s *WebServer) pmtilesExtraDirs() []string {
	if strings.TrimSpace(s.cfg.PMTilesDir) == "" {
		return nil
	}
	if info, err := os.Stat(s.cfg.PMTilesDir); err == nil && info.IsDir() {
		return []string{s.cfg.PMTilesDir}
	}
	return nil
}

func (s *WebServer) pmtilesBaseURL() string {
	if s.cfg.PMTilesCDNBaseURL != "" {
		return s.cfg.PMTilesCDNBaseURL
	}
	return "/pmtiles"
}

func (s *WebServer) buildHelpServiceForSession(prefs *vprocore.DesktopConfig, ctxSvc *vprocore.ContextService) (*lifecycle.HelpService, error) {
	svc, err := lifecycle.NewHelpService(prefs)
	if err != nil {
		return nil, err
	}
	if ctxSvc != nil {
		svc.SetContext(ctxSvc)
	}
	if snap := s.currentSnapshot(); snap != nil {
		svc.SetDataDir(snap.ResolvedRoot)
	}
	return svc, nil
}

// PublicHandler returns the HTTP handler mounted on VPRO_WEB_LISTEN_ADDR.
func (s *WebServer) PublicHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/readyz", s.handleReadyz)
	mux.HandleFunc("/api/meta", s.handleMeta)
	mux.HandleFunc("/api/becmaster/filter-options", s.handleBECMasterFilterOptions)
	mux.HandleFunc("/api/becmaster/filter", s.handleBECMasterFilter)
	mux.HandleFunc("/api/becmaster/download", s.handleBECMasterDownload)
	mux.HandleFunc("/api/rpc/", s.router.ServeHTTP)
	mux.HandleFunc("/api/downloads/", s.handleDownloads)
	mux.HandleFunc("/pmtiles/", s.handlePMTiles)
	mux.HandleFunc("/maps/", s.handleMaps)
	mux.Handle("/", s.spaHdl)
	return securityHeadersMiddleware(mux)
}

// InternalHandler returns the loopback-only HTTP handler mounted on VPRO_WEB_INTERNAL_ADDR.
func (s *WebServer) InternalHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/readyz", s.handleReadyz)
	mux.HandleFunc("/internal/reload", s.handleInternalReload)
	mux.HandleFunc("/internal/stats", s.handleInternalStats)
	return securityHeadersMiddleware(mux)
}

func securityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		next.ServeHTTP(w, r)
	})
}

func (s *WebServer) handleHealthz(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *WebServer) handleReadyz(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	snap := s.currentSnapshot()
	stats := s.pool.Stats()
	if snap == nil || stats.Closed || len(snap.Catalog.Datasets) == 0 {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"status": "not_ready",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":     "ready",
		"snapshotId": snap.Manifest.SnapshotID,
		"generation": stats.Generation,
		"datasets":   len(snap.Catalog.Datasets),
	})
}

// MetaResponse is the JSON payload returned by GET /api/meta.
type MetaResponse struct {
	Env               string                 `json:"env"`
	ReadOnly          bool                   `json:"readOnly"`
	SnapshotID        string                 `json:"snapshotId"`
	Generation        string                 `json:"generation"`
	PublishedAt       string                 `json:"publishedAt"`
	Redacted          bool                   `json:"redacted"`
	RedactedPlotCount int                    `json:"redactedPlotCount"`
	Standards         SnapshotStandardsStamp `json:"standards"`
	Datasets          []MetaDatasetSummary   `json:"datasets"`
	PicturesAvailable bool                   `json:"picturesAvailable"`
	PMTilesBaseURL    string                 `json:"pmtilesBaseUrl"`
	RAvailable        bool                   `json:"rAvailable"`
	ExternalLinks     []ExternalLink         `json:"externalLinks"`
	LicenceName       string                 `json:"licenceName"`
	LicenceURL        string                 `json:"licenceUrl"`
	Citation          string                 `json:"citation"`
}

type MetaDatasetSummary struct {
	ID                string                  `json:"id"`
	Label             string                  `json:"label"`
	Project           string                  `json:"project"`
	PlotCount         int                     `json:"plotCount"`
	RedactedPlotCount int                     `json:"redactedPlotCount"`
	DefaultSU         string                  `json:"defaultSu"`
	DefaultHierarchy  string                  `json:"defaultHierarchy"`
	SUs               []SnapshotSUEntry       `json:"sus"`
	Hierarchies       []SnapshotHierarchySpec `json:"hierarchies"`
}

func (s *WebServer) handleMeta(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	snap := s.currentSnapshot()
	if snap == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "snapshot catalog is unavailable")
		return
	}

	dsByID := make(map[string]vprocore.SnapshotDataset, len(snap.Catalog.Datasets))
	for _, ds := range snap.Catalog.Datasets {
		dsByID[ds.ID] = ds
	}
	datasets := make([]MetaDatasetSummary, 0, len(snap.Manifest.Datasets))
	for _, mds := range snap.Manifest.Datasets {
		catDS := dsByID[mds.ID]
		sus := mds.SUs
		if sus == nil {
			sus = []SnapshotSUEntry{}
		}
		hiers := mds.Hierarchies
		if hiers == nil {
			hiers = []SnapshotHierarchySpec{}
		}
		datasets = append(datasets, MetaDatasetSummary{
			ID:                mds.ID,
			Label:             mds.Label,
			Project:           mds.Project,
			PlotCount:         mds.PlotCount,
			RedactedPlotCount: mds.RedactedPlotCount,
			DefaultSU:         catDS.DefaultSU,
			DefaultHierarchy:  catDS.DefaultHierarchy,
			SUs:               sus,
			Hierarchies:       hiers,
		})
	}

	_, _, picAvail := s.pictureAvailability()
	externalLinks := s.cfg.ExternalLinks
	if externalLinks == nil {
		externalLinks = defaultExternalLinks()
	} else {
		externalLinks = append([]ExternalLink(nil), externalLinks...)
	}
	resp := MetaResponse{
		Env:               s.cfg.Env,
		ReadOnly:          true,
		SnapshotID:        snap.Manifest.SnapshotID,
		Generation:        snap.Catalog.Generation,
		PublishedAt:       snap.Manifest.PublishedAt,
		Redacted:          snap.Manifest.Redacted,
		RedactedPlotCount: snap.Manifest.RedactedPlotCount,
		Standards:         snap.Manifest.Standards,
		Datasets:          datasets,
		PicturesAvailable: picAvail,
		PMTilesBaseURL:    s.pmtilesBaseURL(),
		RAvailable:        s.isRAvailable(),
		ExternalLinks:     externalLinks,
		LicenceName:       defaultLicenceName,
		LicenceURL:        defaultLicenceURL,
		Citation:          defaultBECMasterCitation,
	}
	w.Header().Set("Cache-Control", "no-cache")
	writeJSON(w, http.StatusOK, resp)
}

func (s *WebServer) handleDownloads(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.URL.Path, "/api/downloads/")
	if token == "" || strings.Contains(token, "/") {
		writeJSONError(w, http.StatusNotFound, "download token not found")
		return
	}
	s.downloads.ServeDownload(w, r, token)
}

func (s *WebServer) handlePMTiles(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/pmtiles/")
	if strings.HasSuffix(strings.ToLower(name), ".pmtiles") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	}
	cloned := r.Clone(r.Context())
	cloned.URL.Path = "/maps/" + name
	cloned.URL.RawPath = ""
	s.pmtilesHdl.ServeHTTP(w, cloned)
}

func (s *WebServer) handleMaps(w http.ResponseWriter, r *http.Request) {
	if strings.HasSuffix(strings.ToLower(r.URL.Path), ".pmtiles") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	}
	s.pmtilesHdl.ServeHTTP(w, r)
}

// ReloadSnapshot re-reads manifest.json from VPRO_WEB_DATA_DIR (resolving symlinks),
// verifies all SHA-256 checksums, atomically swaps ReadOnlyContextPool, and clears
// the LRU preview cache. If validation fails, the existing active snapshot stays live.
func (s *WebServer) ReloadSnapshot() (*LoadedSnapshot, error) {
	s.reloadMu.Lock()
	defer s.reloadMu.Unlock()

	if s.cfg.DataDir == "" {
		return nil, errors.New("live reload requires VPRO_WEB_DATA_DIR (unavailable in --dev-sample mode)")
	}
	nextSnap, err := LoadVerifiedSnapshot(s.cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("reload snapshot verification failed: %w", err)
	}
	if err := s.pool.Reload(nextSnap.Catalog); err != nil {
		return nil, fmt.Errorf("atomic pool reload failed: %w", err)
	}

	s.snapMu.Lock()
	s.snapshot = nextSnap
	s.refreshPicturesStateLocked(nextSnap)
	s.snapMu.Unlock()

	s.cache.Clear()
	s.reloadCount.Add(1)
	return nextSnap, nil
}

func (s *WebServer) handleInternalReload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	snap, err := s.ReloadSnapshot()
	if err != nil {
		log.Printf("vpro-web reload failed: %v", err)
		writeJSONError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":      "reloaded",
		"snapshotId":  snap.Manifest.SnapshotID,
		"generation":  snap.Catalog.Generation,
		"publishedAt": snap.Manifest.PublishedAt,
		"datasets":    len(snap.Catalog.Datasets),
		"reloadCount": s.reloadCount.Load(),
	})
}

func (s *WebServer) handleInternalStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	snap := s.currentSnapshot()
	snapshotID := ""
	if snap != nil {
		snapshotID = snap.Manifest.SnapshotID
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"env":               s.cfg.Env,
		"snapshotId":        snapshotID,
		"uptimeSeconds":     int64(time.Since(s.startedAt).Seconds()),
		"reloadCount":       s.reloadCount.Load(),
		"pool":              s.pool.Stats(),
		"cache":             s.cache.Stats(),
		"sessions":          s.sessions.Count(),
		"activeDownloads":   s.downloads.ActiveCount(),
		"exportConcurrency": s.cfg.ExportConcurrency,
		"exportInFlight":    s.exportInFlight.Load(),
		"rConcurrency":      s.cfg.RConcurrency,
		"rInFlight":         s.rInFlight.Load(),
		"rAvailable":        s.isRAvailable(),
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	data, err := json.Marshal(payload)
	if err != nil {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"failed to encode JSON response"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(data)
}

func writeJSONError(w http.ResponseWriter, status int, message string) {
	msg := strings.TrimSpace(message)
	if msg == "" {
		msg = http.StatusText(status)
	}
	writeJSON(w, status, map[string]string{"error": msg})
}
