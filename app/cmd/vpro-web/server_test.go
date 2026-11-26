package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newTestDevSampleServer(t *testing.T, mutateCfg func(*WebConfig)) *WebServer {
	t.Helper()
	exportDir := t.TempDir()
	cfg := WebConfig{
		Env:               "dev",
		ListenAddr:        ":0",
		InternalAddr:      "127.0.0.1:0",
		DevSample:         true,
		PMTilesDir:        t.TempDir(),
		ExportDir:         exportDir,
		ExportConcurrency: 3,
		ExportTimeout:     60 * time.Second,
		RConcurrency:      2,
		RTimeout:          60 * time.Second,
		PoolSlots:         6,
		MaxPools:          16,
		CacheMaxMB:        32,
	}
	if mutateCfg != nil {
		mutateCfg(&cfg)
	}
	srv, err := NewWebServer(context.Background(), cfg)
	if err != nil {
		t.Fatalf("NewWebServer failed: %v", err)
	}
	t.Cleanup(srv.Close)
	return srv
}

func doRPC(t *testing.T, handler http.Handler, sessionID, service, method string, args ...any) *httptest.ResponseRecorder {
	t.Helper()
	if args == nil {
		args = []any{}
	}
	body, err := json.Marshal(map[string]any{"args": args})
	if err != nil {
		t.Fatalf("marshal rpc args: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/rpc/"+service+"/"+method, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if sessionID != "" {
		req.Header.Set("X-VPro-Session", sessionID)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func decodeRPCResult[T any](t *testing.T, rec *httptest.ResponseRecorder) T {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var env struct {
		Result T `json:"result"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
		t.Fatalf("decode rpc result: %v (body=%s)", err, rec.Body.String())
	}
	return env.Result
}

func decodeDownloadResponse(t *testing.T, rec *httptest.ResponseRecorder) (outcome json.RawMessage, downloadURL, filename string) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 for download RPC, got %d: %s", rec.Code, rec.Body.String())
	}
	var env struct {
		Outcome     json.RawMessage `json:"outcome"`
		DownloadURL string          `json:"downloadUrl"`
		Filename    string          `json:"filename"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
		t.Fatalf("decode download response: %v (body=%s)", err, rec.Body.String())
	}
	if env.DownloadURL == "" || !strings.HasPrefix(env.DownloadURL, "/api/downloads/") {
		t.Fatalf("expected /api/downloads/... url, got %q", env.DownloadURL)
	}
	if env.Filename == "" {
		t.Fatalf("expected non-empty filename")
	}
	return env.Outcome, env.DownloadURL, env.Filename
}

func TestDirectImportsNoWailsOrAccessReader(t *testing.T) {
	listArgs := []string{"list"}
	if testBuildTags != "" {
		listArgs = append(listArgs, "-tags", testBuildTags)
	}
	listArgs = append(listArgs, "-f", `{{join .Imports "\n"}}`, "./cmd/vpro-web")
	cmd := exec.Command("go", listArgs...)
	cmd.Dir = "../.."
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go list imports failed: %v\n%s", err, string(out))
	}
	for _, line := range strings.Split(string(out), "\n") {
		imp := strings.TrimSpace(line)
		if strings.Contains(imp, "github.com/wailsapp/wails") ||
			strings.Contains(imp, "github.com/boostao/vpro/app/internal/accessreader") {
			t.Fatalf("cmd/vpro-web directly imports forbidden package %q", imp)
		}
	}
}

func TestConfigEnvContract(t *testing.T) {
	envMap := map[string]string{
		"VPRO_WEB_ENV":                 "prod",
		"VPRO_WEB_LISTEN_ADDR":         ":8081",
		"VPRO_WEB_INTERNAL_ADDR":       "127.0.0.1:9091",
		"VPRO_WEB_DATA_DIR":            "/srv/vpro/data/current",
		"VPRO_WEB_PMTILES_DIR":         "/pmtiles",
		"VPRO_WEB_PMTILES_CDN_BASE_URL": "https://cdn.example.com/pmtiles/",
		"VPRO_WEB_PICTURES_DIR":        "/pictures",
		"VPRO_WEB_VPICS_PATH":          "/pictures/VPics.db",
		"VPRO_WEB_EXPORT_DIR":          "/tmp/vpro-exports",
		"VPRO_WEB_EXPORT_CONCURRENCY":  "4",
		"VPRO_WEB_EXPORT_TIMEOUT":      "90s",
		"VPRO_WEB_R_CONCURRENCY":       "2",
		"VPRO_WEB_R_TIMEOUT":           "180s",
		"VPRO_WEB_POOL_SLOTS":          "8",
		"VPRO_WEB_MAX_POOLS":           "20",
		"VPRO_WEB_CACHE_MAX_MB":        "128",
	}
	lookup := func(k string) (string, bool) { v, ok := envMap[k]; return v, ok }
	cfg, err := LoadWebConfig(lookup, false)
	if err != nil {
		t.Fatalf("LoadWebConfig failed: %v", err)
	}
	if cfg.Env != "prod" || cfg.ListenAddr != ":8081" || cfg.InternalAddr != "127.0.0.1:9091" {
		t.Fatalf("unexpected addr/env config: %+v", cfg)
	}
	if cfg.PMTilesCDNBaseURL != "https://cdn.example.com/pmtiles" {
		t.Fatalf("expected trimmed CDN URL, got %q", cfg.PMTilesCDNBaseURL)
	}
	if cfg.ExportConcurrency != 4 || cfg.ExportTimeout != 90*time.Second ||
		cfg.RConcurrency != 2 || cfg.RTimeout != 180*time.Second ||
		cfg.PoolSlots != 8 || cfg.MaxPools != 20 || cfg.CacheMaxMB != 128 {
		t.Fatalf("unexpected concurrency/cache config: %+v", cfg)
	}

	// Missing VPRO_WEB_DATA_DIR without --dev-sample must fail.
	if _, err := LoadWebConfig(func(string) (string, bool) { return "", false }, false); err == nil {
		t.Fatal("expected error when VPRO_WEB_DATA_DIR is missing and devSample=false")
	}
	// With --dev-sample, defaults should succeed.
	devCfg, err := LoadWebConfig(func(string) (string, bool) { return "", false }, true)
	if err != nil {
		t.Fatalf("LoadWebConfig(devSample=true) failed: %v", err)
	}
	if devCfg.ListenAddr != ":8080" || devCfg.InternalAddr != "127.0.0.1:9090" ||
		devCfg.ExportConcurrency != 3 || devCfg.RConcurrency != 2 ||
		devCfg.PoolSlots != 6 || devCfg.MaxPools != 16 || devCfg.CacheMaxMB != 256 {
		t.Fatalf("unexpected default config: %+v", devCfg)
	}
	// Invalid env must fail.
	if _, err := LoadWebConfig(func(k string) (string, bool) {
		if k == "VPRO_WEB_ENV" {
			return "staging", true
		}
		return "", false
	}, true); err == nil {
		t.Fatal("expected error for invalid VPRO_WEB_ENV")
	}
}

func TestAllowlist100PercentCoverageAnd403Rejection(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	al, err := LoadWebRPCAllowlist()
	if err != nil {
		t.Fatalf("LoadWebRPCAllowlist: %v", err)
	}

	total := 0
	counts := map[string]int{}
	for svc, methods := range al.Services {
		for method, kind := range methods {
			total++
			counts[kind]++
			if !srv.router.HasHandler(svc, method) {
				t.Errorf("allowlisted method %s.%s (%s) has no registered handler", svc, method, kind)
			}
		}
	}
	if total != 300 {
		t.Fatalf("expected 300 allowlisted methods, got %d", total)
	}
	if srv.router.RegisteredCount() != total {
		t.Fatalf("registered count %d != allowlist total %d", srv.router.RegisteredCount(), total)
	}
	if counts["rpc"] != 229 || counts["prefs"] != 50 || counts["download"] != 21 {
		t.Fatalf("unexpected kind breakdown: %+v", counts)
	}

	pub := srv.PublicHandler()
	forbiddenRPCs := [][2]string{
		{"ContextService", "CreatePlot"},
		{"ContextService", "UpdatePlot"},
		{"ContextService", "SaveVegRecord"},
		{"ContextService", "DeleteVegRecord"},
		{"ContextService", "ListAuditEntries"},
		{"ContextService", "ListAuditReadEntries"},
		{"ContextService", "RestoreSelectedAuditRecords"},
		{"ContextService", "GetUserSetup"},
		{"ContextService", "SetUserName"},
		{"ContextService", "InspectExternalSQLiteFile"},
		{"ContextService", "ChooseAccessDatabaseFile"},
		{"ContextService", "RevealInFileExplorer"},
		{"ContextService", "SyncCloudProject"},
		{"ContextService", "CreateNewProject"},
		{"EnvironmentReportService", "PromoteClusterCandidateToSU"},
		{"VegetationReportService", "SaveSummaryVegetationFieldList"},
		{"ClassificationService", "AssignPlotsToSiteUnit"},
		{"ClassificationService", "CreateSUTable"},
		{"ClassificationService", "AddHierarchyNode"},
		{"ClassificationService", "ReassignSynthesisPlotUnit"},
		{"ClassificationService", "SaveUserSiteUnitEntry"},
		{"ImportExportService", "ImportAccessProject"},
		{"ImportExportService", "InspectAccessDatabase"},
		{"ImportExportService", "ImportTurboVeg"},
		{"ImportExportService", "CreateLumpTable"},
		{"ImportExportService", "DeleteLumpTable"},
		{"ImportExportService", "MaterializeLumpSpec"},
		{"DatasheetService", "ApplyDatasheetEdits"},
		{"DatasheetService", "InsertDatasheetChildRow"},
		{"DatasheetService", "DeleteDatasheetChildRow"},
		{"LifecycleService", "ResetStartupToSample"},
		{"LifecycleService", "ConfirmClose"},
		{"LifecycleService", "GetUserLogReview"},
		{"PictureService", "CreatePicture"},
		{"PictureService", "DeletePicture"},
		{"PictureService", "SaveMetadata"},
		{"SpatialService", "ApplySpatialAttributes"},
		{"SpatialService", "AssignSpatialAOIToSU"},
		{"ValidationService", "ApplyOptimizeVeg"},
		{"ValidationService", "QuarantineOrphanRecords"},
		{"HelpService", "ResetWorkspaceToSample"},
		{"CloseService", "ConfirmClose"},
		// Newly landed Wave 1 mutating, auth, workspace, spreadsheet-launch & dialog RPCs (strictly excluded)
		{"PlotEntryService", "EnsureMensurationTables"},
		{"PlotEntryService", "SaveTreePlot"},
		{"PlotEntryService", "DeleteTreePlot"},
		{"PlotEntryService", "SaveTreeRow"},
		{"PlotEntryService", "DeleteTreeRow"},
		{"ContextService", "AttachWorkspaceResource"},
		{"ContextService", "UnattachWorkspaceResource"},
		{"ContextService", "CreateWorkspaceResource"},
		{"ContextService", "ChooseAttachableFile"},
		{"ContextService", "BeginOIDCSignIn"},
		{"ContextService", "CompleteDevEvaluationSignIn"},
		{"ContextService", "SignOut"},
		{"ContextService", "RecordAppActivity"},
		{"ContextService", "SetSpreadsheetAppPreference"},
		{"ContextService", "OpenReportInSpreadsheet"},
		{"ImportExportService", "ChooseVPro64ExportFile"},
		{"SpatialService", "SyncLatestBGCMap"},
		{"VegetationReportService", "SetSpreadsheetAppPreference"},
		{"VegetationReportService", "OpenReportInSpreadsheet"},
		{"VegetationReportService", "QuickRunSummaryVegetationWorkbook"},
		{"VegetationReportService", "QuickRunLongVegetationWorkbook"},
		{"VegetationReportService", "QuickRunLifeformWorkbook"},
		{"EnvironmentReportService", "SetSpreadsheetAppPreference"},
		{"EnvironmentReportService", "OpenReportInSpreadsheet"},
		{"EnvironmentReportService", "QuickRunLongEnvironmentWorkbook"},
		{"EnvironmentReportService", "QuickRunSummaryEnvironmentWorkbook"},
		{"EnvironmentReportService", "QuickRunSubzoneMatrixWorkbook"},
	}

	for _, pair := range forbiddenRPCs {
		rec := doRPC(t, pub, "sec-sess", pair[0], pair[1])
		if rec.Code != http.StatusForbidden {
			t.Errorf("expected 403 Forbidden for %s.%s, got %d (%s)", pair[0], pair[1], rec.Code, rec.Body.String())
		}
		var errBody map[string]string
		if err := json.Unmarshal(rec.Body.Bytes(), &errBody); err != nil || errBody["error"] == "" {
			t.Errorf("expected JSON error body for %s.%s, got %q", pair[0], pair[1], rec.Body.String())
		}
	}
}

func TestExternalPathTraversalGuardsAndExportDestinationOverride(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	pub := srv.PublicHandler()

	// Acquire a valid contextID via ContextService.GetState.
	stateRec := doRPC(t, pub, "guard-sess", "ContextService", "GetState")
	state := decodeRPCResult[struct {
		ContextID string `json:"contextId"`
	}](t, stateRec)
	if state.ContextID == "" {
		t.Fatal("expected non-empty stateless contextId")
	}

	// 1. Reject external paths on ListPlotProfileSources, DiscoverLumpTables, GetLumpTableRows, PreviewLumpImpact.
	traversalChecks := []struct {
		service string
		method  string
		args    []any
	}{
		{"ContextService", "ListPlotProfileSources", []any{state.ContextID, "/etc/passwd"}},
		{"ClassificationService", "ListPlotProfileSources", []any{state.ContextID, "../../Sample.db"}},
		{"ImportExportService", "DiscoverLumpTables", []any{state.ContextID, []string{"/etc/passwd"}}},
		{"ImportExportService", "GetLumpTableRows", []any{state.ContextID, "Any_Lump", "/etc/passwd"}},
		{"ImportExportService", "PreviewLumpImpact", []any{state.ContextID, "Any_Lump", "../../evil.db"}},
		{"ContextService", "SwitchContext", []any{state.ContextID, map[string]any{"project": "Sample", "projectPath": "/etc/passwd", "su": "None", "hierarchy": "None"}}},
		{"ClassificationService", "ComputeSynthesisSnapshot", []any{state.ContextID, map[string]any{"lumpDbPath": "/etc/passwd"}}},
		{"ImportExportService", "ExportLongTidyCSV", []any{state.ContextID, map[string]any{"lumpDbPath": "/etc/passwd"}}},
	}
	for _, tc := range traversalChecks {
		rec := doRPC(t, pub, "guard-sess", tc.service, tc.method, tc.args...)
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s.%s with external path: expected 403, got %d (%s)", tc.service, tc.method, rec.Code, rec.Body.String())
		}
	}

	// 2. Client-supplied outputPath / destinationPath on export downloads MUST be ignored,
	// never written on disk, and served strictly via /api/downloads/{token} (single-use!).
	forbiddenTargetDir := t.TempDir()
	evilPath := filepath.Join(forbiddenTargetDir, "must-not-exist.csv")

	expRec := doRPC(t, pub, "guard-sess", "ImportExportService", "ExportLongTidyCSV",
		state.ContextID,
		map[string]any{"destinationPath": evilPath},
	)
	_, dlURL, filename := decodeDownloadResponse(t, expRec)
	if !strings.HasSuffix(filename, ".csv") {
		t.Fatalf("expected .csv filename, got %q", filename)
	}
	if _, err := os.Stat(evilPath); !os.IsNotExist(err) {
		t.Fatalf("SECURITY FAILURE: client-supplied destinationPath %q was created!", evilPath)
	}

	// Download succeeds once with attachment header & CSV content.
	dlReq := httptest.NewRequest(http.MethodGet, dlURL, nil)
	dlRec := httptest.NewRecorder()
	pub.ServeHTTP(dlRec, dlReq)
	if dlRec.Code != http.StatusOK {
		t.Fatalf("GET %s failed: %d %s", dlURL, dlRec.Code, dlRec.Body.String())
	}
	if cd := dlRec.Header().Get("Content-Disposition"); !strings.Contains(cd, "attachment") {
		t.Fatalf("expected Content-Disposition attachment, got %q", cd)
	}
	if ct := dlRec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/csv") {
		t.Fatalf("expected text/csv content type, got %q", ct)
	}
	if len(dlRec.Body.Bytes()) == 0 {
		t.Fatal("downloaded CSV was empty")
	}

	// Second fetch of the same single-use download token MUST return 404.
	dlRec2 := httptest.NewRecorder()
	pub.ServeHTTP(dlRec2, httptest.NewRequest(http.MethodGet, dlURL, nil))
	if dlRec2.Code != http.StatusNotFound {
		t.Fatalf("expected 404 on second download of single-use token, got %d", dlRec2.Code)
	}

	// Verify GeoPackage export also ignores malicious destinationPath & produces valid SQLite GeoPackage.
	evilGpkg := filepath.Join(forbiddenTargetDir, "must-not-exist.gpkg")
	gpkgRec := doRPC(t, pub, "guard-sess", "ImportExportService", "ExportGeoPackage",
		state.ContextID,
		map[string]any{"destinationPath": evilGpkg, "crs": "EPSG:3005", "includeAttributeTables": true, "includeUnlocatedPlots": true},
	)
	_, gpkgURL, _ := decodeDownloadResponse(t, gpkgRec)
	if _, err := os.Stat(evilGpkg); !os.IsNotExist(err) {
		t.Fatalf("SECURITY FAILURE: client-supplied GeoPackage path %q was created!", evilGpkg)
	}
	gpkgDL := httptest.NewRecorder()
	pub.ServeHTTP(gpkgDL, httptest.NewRequest(http.MethodGet, gpkgURL, nil))
	if gpkgDL.Code != http.StatusOK || !bytes.HasPrefix(gpkgDL.Body.Bytes(), []byte("SQLite format 3\x00")) {
		t.Fatalf("expected valid SQLite GeoPackage download, got status=%d len=%d", gpkgDL.Code, gpkgDL.Body.Len())
	}

	// Verify VPro64 SQLite export also ignores malicious destinationPath & produces valid SQLite database.
	evilVPro64 := filepath.Join(forbiddenTargetDir, "must-not-exist-vpro64.db")
	vpro64Rec := doRPC(t, pub, "guard-sess", "ImportExportService", "ExportVPro64Database",
		state.ContextID,
		map[string]any{"destinationPath": evilVPro64, "includeActiveSU": true},
	)
	_, vpro64URL, vpro64Filename := decodeDownloadResponse(t, vpro64Rec)
	if !strings.HasSuffix(vpro64Filename, ".db") {
		t.Fatalf("expected .db filename, got %q", vpro64Filename)
	}
	if _, err := os.Stat(evilVPro64); !os.IsNotExist(err) {
		t.Fatalf("SECURITY FAILURE: client-supplied VPro64 export path %q was created!", evilVPro64)
	}
	vpro64DL := httptest.NewRecorder()
	pub.ServeHTTP(vpro64DL, httptest.NewRequest(http.MethodGet, vpro64URL, nil))
	if vpro64DL.Code != http.StatusOK || !bytes.HasPrefix(vpro64DL.Body.Bytes(), []byte("SQLite format 3\x00")) {
		t.Fatalf("expected valid SQLite VPro64 download, got status=%d len=%d", vpro64DL.Code, vpro64DL.Body.Len())
	}

	// Verify newly allowlisted read-only Wave 1 RPCs execute cleanly on dev-sample snapshot.
	mensRec := doRPC(t, pub, "guard-sess", "PlotEntryService", "GetPlotMensuration", state.ContextID, "108050")
	if mensRec.Code != http.StatusOK {
		t.Fatalf("PlotEntryService.GetPlotMensuration failed: %d %s", mensRec.Code, mensRec.Body.String())
	}
	filterOptsRec := doRPC(t, pub, "guard-sess", "SpatialService", "GetBECMasterFilterOptions", state.ContextID)
	if filterOptsRec.Code != http.StatusOK {
		t.Fatalf("SpatialService.GetBECMasterFilterOptions failed: %d %s", filterOptsRec.Code, filterOptsRec.Body.String())
	}
	filterPlotsRec := doRPC(t, pub, "guard-sess", "SpatialService", "FilterBECMasterPlots", state.ContextID, map[string]any{})
	if filterPlotsRec.Code != http.StatusOK {
		t.Fatalf("SpatialService.FilterBECMasterPlots failed: %d %s", filterPlotsRec.Code, filterPlotsRec.Body.String())
	}
	for _, htmlCall := range []struct {
		service string
		method  string
		args    []any
	}{
		{"VegetationReportService", "RenderSummaryVegetationHTMLReport", []any{state.ContextID, map[string]any{}}},
		{"VegetationReportService", "RenderLongVegetationHTMLReport", []any{state.ContextID, map[string]any{}}},
		{"VegetationReportService", "RenderLifeformHTMLReport", []any{state.ContextID, map[string]any{}}},
		{"EnvironmentReportService", "RenderLongEnvironmentHTMLReport", []any{state.ContextID, map[string]any{}}},
		{"EnvironmentReportService", "RenderSummaryEnvironmentHTMLReport", []any{state.ContextID, map[string]any{}}},
	} {
		rec := doRPC(t, pub, "guard-sess", htmlCall.service, htmlCall.method, htmlCall.args...)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s.%s failed: %d %s", htmlCall.service, htmlCall.method, rec.Code, rec.Body.String())
		}
	}
}

func TestEndpointsMetaHealthReadyPMTilesSPAAndCacheETag(t *testing.T) {
	staticDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(staticDir, "index.html"), []byte("<!doctype html><title>VPro Web</title>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(staticDir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staticDir, "assets", "app.js"), []byte("console.log('vpro');"), 0o644); err != nil {
		t.Fatal(err)
	}

	srv := newTestDevSampleServer(t, func(c *WebConfig) {
		c.StaticDir = staticDir
		c.PMTilesCDNBaseURL = "https://tiles.example.org/pmtiles"
	})
	pub := srv.PublicHandler()
	internal := srv.InternalHandler()

	// /healthz & /readyz
	for _, ep := range []string{"/healthz", "/readyz"} {
		rec := httptest.NewRecorder()
		pub.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, ep, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s expected 200, got %d: %s", ep, rec.Code, rec.Body.String())
		}
	}

	// /api/meta
	metaRec := httptest.NewRecorder()
	pub.ServeHTTP(metaRec, httptest.NewRequest(http.MethodGet, "/api/meta", nil))
	if metaRec.Code != http.StatusOK {
		t.Fatalf("GET /api/meta expected 200, got %d: %s", metaRec.Code, metaRec.Body.String())
	}
	var meta MetaResponse
	if err := json.Unmarshal(metaRec.Body.Bytes(), &meta); err != nil {
		t.Fatalf("decode /api/meta: %v", err)
	}
	if !meta.ReadOnly || meta.SnapshotID != "dev-sample" || len(meta.Datasets) != 1 || meta.Datasets[0].PlotCount <= 0 {
		t.Fatalf("unexpected /api/meta payload: %+v", meta)
	}
	if meta.PMTilesBaseURL != "https://tiles.example.org/pmtiles" {
		t.Fatalf("expected CDN base URL in /api/meta, got %q", meta.PMTilesBaseURL)
	}

	// /pmtiles/bc-overview.pmtiles Range request (embedded overview fallback)
	pmReq := httptest.NewRequest(http.MethodGet, "/pmtiles/bc-overview.pmtiles", nil)
	pmReq.Header.Set("Range", "bytes=0-126")
	pmRec := httptest.NewRecorder()
	pub.ServeHTTP(pmRec, pmReq)
	if pmRec.Code != http.StatusPartialContent || pmRec.Body.Len() != 127 {
		t.Fatalf("expected 206 Partial Content (127 bytes) for /pmtiles/bc-overview.pmtiles, got %d (%d bytes)", pmRec.Code, pmRec.Body.Len())
	}
	if !strings.Contains(pmRec.Header().Get("Cache-Control"), "immutable") {
		t.Fatalf("expected immutable Cache-Control on /pmtiles, got %q", pmRec.Header().Get("Cache-Control"))
	}

	// SPA fallback & /api/ 404 isolation
	spaRec := httptest.NewRecorder()
	pub.ServeHTTP(spaRec, httptest.NewRequest(http.MethodGet, "/plots/00001", nil))
	if spaRec.Code != http.StatusOK || !strings.Contains(spaRec.Body.String(), "VPro Web") {
		t.Fatalf("expected SPA index.html fallback, got %d %q", spaRec.Code, spaRec.Body.String())
	}
	assetRec := httptest.NewRecorder()
	pub.ServeHTTP(assetRec, httptest.NewRequest(http.MethodGet, "/assets/app.js", nil))
	if assetRec.Code != http.StatusOK || !strings.Contains(assetRec.Header().Get("Cache-Control"), "immutable") {
		t.Fatalf("expected immutable asset response, got %d cc=%q", assetRec.Code, assetRec.Header().Get("Cache-Control"))
	}
	api404 := httptest.NewRecorder()
	pub.ServeHTTP(api404, httptest.NewRequest(http.MethodGet, "/api/unknown", nil))
	if api404.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for /api/unknown, got %d", api404.Code)
	}

	// PreviewCache ETag + 304 Not Modified on cacheable RPC
	req1 := httptest.NewRequest(http.MethodPost, "/api/rpc/HelpService/GetHelpBundle", strings.NewReader(`{"args":[]}`))
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	pub.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("GetHelpBundle failed: %d %s", rec1.Code, rec1.Body.String())
	}
	etag := rec1.Header().Get("ETag")
	if etag == "" || rec1.Header().Get("X-VPro-Cache") != "MISS" {
		t.Fatalf("expected ETag and MISS on first call, got etag=%q cache=%q", etag, rec1.Header().Get("X-VPro-Cache"))
	}

	req2 := httptest.NewRequest(http.MethodPost, "/api/rpc/HelpService/GetHelpBundle", strings.NewReader(`{"args":[]}`))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("If-None-Match", etag)
	rec2 := httptest.NewRecorder()
	pub.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusNotModified {
		t.Fatalf("expected 304 Not Modified on matching ETag, got %d", rec2.Code)
	}

	// /internal/stats
	statsRec := httptest.NewRecorder()
	internal.ServeHTTP(statsRec, httptest.NewRequest(http.MethodGet, "/internal/stats", nil))
	if statsRec.Code != http.StatusOK || !strings.Contains(statsRec.Body.String(), `"snapshotId":"dev-sample"`) {
		t.Fatalf("unexpected /internal/stats: %d %s", statsRec.Code, statsRec.Body.String())
	}
}

func TestSessionPreferenceIsolationAndDownloadSweeper(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	pub := srv.PublicHandler()

	// Session A sets coordinate mode to "dms"; Session B keeps default ("dd") / sets "dm".
	recSetA := doRPC(t, pub, "sess-alpha", "SpatialService", "SetCoordinateMode", "dms")
	if recSetA.Code != http.StatusNoContent {
		t.Fatalf("SetCoordinateMode(dms) expected 204, got %d: %s", recSetA.Code, recSetA.Body.String())
	}
	recSetB := doRPC(t, pub, "sess-beta", "SpatialService", "SetCoordinateMode", "dm")
	if recSetB.Code != http.StatusNoContent {
		t.Fatalf("SetCoordinateMode(dm) expected 204, got %d: %s", recSetB.Code, recSetB.Body.String())
	}

	modeA := decodeRPCResult[string](t, doRPC(t, pub, "sess-alpha", "SpatialService", "GetCoordinateMode"))
	modeB := decodeRPCResult[string](t, doRPC(t, pub, "sess-beta", "SpatialService", "GetCoordinateMode"))
	modeC := decodeRPCResult[string](t, doRPC(t, pub, "sess-gamma", "SpatialService", "GetCoordinateMode"))
	if modeA != "dms" || modeB != "dm" || modeC != "dd" {
		t.Fatalf("session preference leak detected: A=%q B=%q C=%q", modeA, modeB, modeC)
	}

	// Verify WorkingUnit master choices & per-session working unit mode work cleanly on read-only snapshot.
	masterChoices := decodeRPCResult[[]any](t, doRPC(t, pub, "sess-alpha", "ClassificationService", "GetMasterWorkingUnitChoices"))
	if len(masterChoices) == 0 {
		t.Fatal("expected non-empty master working unit choices")
	}
	wuMode := decodeRPCResult[struct {
		Mode string `json:"mode"`
	}](t, doRPC(t, pub, "sess-alpha", "ClassificationService", "SetWorkingUnitMode", "env"))
	if wuMode.Mode != "env" {
		t.Fatalf("expected WorkingUnitMode=env, got %q", wuMode.Mode)
	}

	// Verify DownloadStore sweeper deletes expired files.
	ds, err := NewDownloadStore(t.TempDir(), 120*time.Millisecond)
	if err != nil {
		t.Fatalf("NewDownloadStore: %v", err)
	}
	defer ds.Close()
	fp, dp, cleanup, err := ds.MintTempPath("ephemeral.txt")
	if err != nil {
		t.Fatalf("MintTempPath: %v", err)
	}
	if err := os.WriteFile(fp, []byte("hello"), 0o600); err != nil {
		cleanup()
		t.Fatal(err)
	}
	token, _, _, err := ds.Register(fp, dp, "ephemeral.txt")
	if err != nil {
		cleanup()
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(fp); os.IsNotExist(err) && ds.ActiveCount() == 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if _, err := os.Stat(fp); !os.IsNotExist(err) {
		t.Fatalf("expected expired download temp file %q to be swept", fp)
	}
	rec := httptest.NewRecorder()
	ds.ServeDownload(rec, httptest.NewRequest(http.MethodGet, "/api/downloads/"+token, nil), token)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after sweep, got %d", rec.Code)
	}
}

func TestSemaphoreBackpressureReturns503WithRetryAfter(t *testing.T) {
	srv := newTestDevSampleServer(t, func(c *WebConfig) {
		c.ExportConcurrency = 1
		c.ExportTimeout = 80 * time.Millisecond
		c.RConcurrency = 1
		c.RTimeout = 80 * time.Millisecond
	})
	pub := srv.PublicHandler()

	state := decodeRPCResult[struct {
		ContextID string `json:"contextId"`
	}](t, doRPC(t, pub, "bp-sess", "ContextService", "GetState"))

	// Saturate export semaphore.
	srv.exportSem <- struct{}{}
	defer func() { <-srv.exportSem }()

	rec := doRPC(t, pub, "bp-sess", "ImportExportService", "ExportLongTidyCSV",
		state.ContextID,
		map[string]any{},
	)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when export semaphore is saturated, got %d (%s)", rec.Code, rec.Body.String())
	}
	if ra := rec.Header().Get("Retry-After"); ra != "5" {
		t.Fatalf("expected Retry-After: 5, got %q", ra)
	}

	// Saturate R semaphore.
	srv.rSem <- struct{}{}
	defer func() { <-srv.rSem }()

	rRec := doRPC(t, pub, "bp-sess", "EnvironmentReportService", "DetectRRuntime")
	if rRec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when R semaphore is saturated, got %d (%s)", rRec.Code, rRec.Body.String())
	}
	if ra := rRec.Header().Get("Retry-After"); ra != "5" {
		t.Fatalf("expected Retry-After: 5 on R backpressure, got %q", ra)
	}
}

// Unused import safeguard for io if needed in future subtests.
var _ = io.Discard
