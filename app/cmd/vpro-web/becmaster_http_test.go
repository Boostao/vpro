package main

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/spatial"
	_ "github.com/mattn/go-sqlite3"
)

func TestBECMasterMetaExternalLinksLicenceAndCitation(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	pub := srv.PublicHandler()

	rec := httptest.NewRecorder()
	pub.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/meta", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/meta expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var meta MetaResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &meta); err != nil {
		t.Fatalf("decode /api/meta: %v", err)
	}
	if len(meta.ExternalLinks) != 2 {
		t.Fatalf("expected 2 default externalLinks, got %+v", meta.ExternalLinks)
	}
	if meta.ExternalLinks[0].Label != "BECweb" || meta.ExternalLinks[0].URL != "https://www.for.gov.bc.ca/hre/becweb/" {
		t.Fatalf("unexpected first external link: %+v", meta.ExternalLinks[0])
	}
	if meta.ExternalLinks[1].Label != "byBEC" || meta.ExternalLinks[1].URL != "https://thebeczone.ca/shiny/bybecmap/" {
		t.Fatalf("unexpected second external link: %+v", meta.ExternalLinks[1])
	}
	if meta.LicenceName != "Open Government Licence – British Columbia" {
		t.Fatalf("unexpected licenceName: %q", meta.LicenceName)
	}
	if meta.LicenceURL != "https://www2.gov.bc.ca/gov/content/data/open-data/open-government-licence-bc" {
		t.Fatalf("unexpected licenceUrl: %q", meta.LicenceURL)
	}
	if !strings.Contains(meta.Citation, "BECMaster") || !strings.Contains(meta.Citation, "Open Government Licence") {
		t.Fatalf("unexpected citation: %q", meta.Citation)
	}

	// Custom VPRO_WEB_EXTERNAL_LINKS_JSON override
	customEnv := map[string]string{
		"VPRO_WEB_EXTERNAL_LINKS_JSON": `[{"label":"BC Data Catalogue","url":"https://catalogue.data.gov.bc.ca/","description":"Provincial data catalog"}]`,
	}
	cfg, err := LoadWebConfig(func(k string) (string, bool) { v, ok := customEnv[k]; return v, ok }, true)
	if err != nil {
		t.Fatalf("LoadWebConfig custom external links: %v", err)
	}
	if len(cfg.ExternalLinks) != 1 || cfg.ExternalLinks[0].Label != "BC Data Catalogue" {
		t.Fatalf("unexpected parsed ExternalLinks: %+v", cfg.ExternalLinks)
	}

	// Reject dangerous non-http(s) URL schemes in VPRO_WEB_EXTERNAL_LINKS_JSON
	badEnv := map[string]string{
		"VPRO_WEB_EXTERNAL_LINKS_JSON": `[{"label":"XSS","url":"javascript:alert(1)"}]`,
	}
	if _, err := LoadWebConfig(func(k string) (string, bool) { v, ok := badEnv[k]; return v, ok }, true); err == nil {
		t.Fatal("expected LoadWebConfig to reject javascript: external link URL")
	}
}

func TestBECMasterHTTPFilterOptionsAndFilter(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	pub := srv.PublicHandler()

	stateRec := doRPC(t, pub, "bm-sess", "ContextService", "GetState")
	state := decodeRPCResult[struct {
		ContextID string `json:"contextId"`
	}](t, stateRec)

	// 1. GET /api/becmaster/filter-options?contextId=...
	optRec := httptest.NewRecorder()
	pub.ServeHTTP(optRec, httptest.NewRequest(http.MethodGet, "/api/becmaster/filter-options?contextId="+state.ContextID, nil))
	if optRec.Code != http.StatusOK {
		t.Fatalf("GET /api/becmaster/filter-options status=%d body=%s", optRec.Code, optRec.Body.String())
	}
	var opts spatial.BECMasterFilterOptions
	if err := json.Unmarshal(optRec.Body.Bytes(), &opts); err != nil {
		t.Fatalf("decode filter options: %v", err)
	}
	if len(opts.Regions) != 8 || len(opts.Zones) == 0 || opts.TotalPlots <= 0 {
		t.Fatalf("unexpected filter options: regions=%d zones=%d total=%d", len(opts.Regions), len(opts.Zones), opts.TotalPlots)
	}

	// 2. POST /api/becmaster/filter (flat request)
	flatBody, _ := json.Marshal(map[string]any{
		"contextId": state.ContextID,
		"mode":      "all",
		"zones":     []string{opts.Zones[0]},
	})
	filterRec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/becmaster/filter", bytes.NewReader(flatBody))
	req.Header.Set("Content-Type", "application/json")
	pub.ServeHTTP(filterRec, req)
	if filterRec.Code != http.StatusOK {
		t.Fatalf("POST /api/becmaster/filter status=%d body=%s", filterRec.Code, filterRec.Body.String())
	}
	var res spatial.BECMasterFilterResult
	if err := json.Unmarshal(filterRec.Body.Bytes(), &res); err != nil {
		t.Fatalf("decode filter result: %v", err)
	}
	if res.MatchedCount == 0 || res.MatchedCount != len(res.PlotNumbers) {
		t.Fatalf("unexpected filter result: matched=%d plots=%d", res.MatchedCount, len(res.PlotNumbers))
	}

	// 3. POST /api/becmaster/filter (nested filter object)
	nestedBody, _ := json.Marshal(map[string]any{
		"contextId": state.ContextID,
		"filter": map[string]any{
			"mode":  "all",
			"zones": []string{opts.Zones[0]},
		},
	})
	nestedRec := httptest.NewRecorder()
	nestedReq := httptest.NewRequest(http.MethodPost, "/api/becmaster/filter", bytes.NewReader(nestedBody))
	nestedReq.Header.Set("Content-Type", "application/json")
	pub.ServeHTTP(nestedRec, nestedReq)
	if nestedRec.Code != http.StatusOK {
		t.Fatalf("nested POST /api/becmaster/filter status=%d body=%s", nestedRec.Code, nestedRec.Body.String())
	}
	var nestedRes spatial.BECMasterFilterResult
	if err := json.Unmarshal(nestedRec.Body.Bytes(), &nestedRes); err != nil {
		t.Fatalf("decode nested filter result: %v", err)
	}
	if nestedRes.MatchedCount != res.MatchedCount {
		t.Fatalf("nested matched=%d != flat matched=%d", nestedRes.MatchedCount, res.MatchedCount)
	}

	// 4. Method enforcement (405)
	badMethodRec := httptest.NewRecorder()
	pub.ServeHTTP(badMethodRec, httptest.NewRequest(http.MethodGet, "/api/becmaster/filter", nil))
	if badMethodRec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 for GET /api/becmaster/filter, got %d", badMethodRec.Code)
	}
}

func TestBECMasterHTTPFilteredDownloadsAllFormatsAndBackpressure(t *testing.T) {
	srv := newTestDevSampleServer(t, nil)
	pub := srv.PublicHandler()

	stateRec := doRPC(t, pub, "dl-sess", "ContextService", "GetState")
	state := decodeRPCResult[struct {
		ContextID string `json:"contextId"`
	}](t, stateRec)

	// Find all plots that have valid coordinates so KML/GPKG also verify located points.
	allReqBody, _ := json.Marshal(map[string]any{
		"contextId": state.ContextID,
		"mode":      "all",
	})
	allRec := httptest.NewRecorder()
	pub.ServeHTTP(allRec, httptest.NewRequest(http.MethodPost, "/api/becmaster/filter", bytes.NewReader(allReqBody)))
	if allRec.Code != http.StatusOK {
		t.Fatalf("filter all failed: %d %s", allRec.Code, allRec.Body.String())
	}
	var allRes spatial.BECMasterFilterResult
	if err := json.Unmarshal(allRec.Body.Bytes(), &allRes); err != nil {
		t.Fatal(err)
	}
	if len(allRes.Points) < 2 {
		t.Fatalf("expected at least 2 located plots in dev-sample, got %d", len(allRes.Points))
	}
	subsetPlots := []string{allRes.Points[0].PlotNumber, allRes.Points[1].PlotNumber}

	postDownload := func(payload map[string]any) (becmasterDownloadHTTPResponse, []byte) {
		t.Helper()
		body, _ := json.Marshal(payload)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/becmaster/download", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		pub.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("POST /api/becmaster/download (%v) failed: %d %s", payload["format"], rec.Code, rec.Body.String())
		}
		var dlMeta becmasterDownloadHTTPResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &dlMeta); err != nil {
			t.Fatalf("decode download response: %v", err)
		}
		if !strings.HasPrefix(dlMeta.DownloadURL, "/api/downloads/") || dlMeta.Bytes <= 0 || dlMeta.PlotCount != len(subsetPlots) {
			t.Fatalf("unexpected download response metadata: %+v", dlMeta)
		}

		// Fetch one-time download token
		getRec := httptest.NewRecorder()
		pub.ServeHTTP(getRec, httptest.NewRequest(http.MethodGet, dlMeta.DownloadURL, nil))
		if getRec.Code != http.StatusOK {
			t.Fatalf("GET %s failed: %d %s", dlMeta.DownloadURL, getRec.Code, getRec.Body.String())
		}
		if int64(getRec.Body.Len()) != dlMeta.Bytes {
			t.Fatalf("downloaded bytes=%d != reported bytes=%d", getRec.Body.Len(), dlMeta.Bytes)
		}

		// Second fetch MUST return 404 (single-use!)
		getRec2 := httptest.NewRecorder()
		pub.ServeHTTP(getRec2, httptest.NewRequest(http.MethodGet, dlMeta.DownloadURL, nil))
		if getRec2.Code != http.StatusNotFound {
			t.Fatalf("expected 404 on second download of %s, got %d", dlMeta.DownloadURL, getRec2.Code)
		}
		return dlMeta, getRec.Body.Bytes()
	}

	// 1. vpro64 -> clean SQLite VP08 .db with journal_mode=DELETE & strictly 2 filtered plots
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "vpro64",
			"plotNumbers": subsetPlots,
		})
		if !strings.HasSuffix(meta.Filename, ".db") {
			t.Fatalf("expected .db filename, got %q", meta.Filename)
		}
		if !bytes.HasPrefix(raw, []byte("SQLite format 3\x00")) {
			t.Fatal("vpro64 download is not a valid SQLite file")
		}
		tmpDB := filepath.Join(t.TempDir(), "subset.db")
		if err := os.WriteFile(tmpDB, raw, 0o600); err != nil {
			t.Fatal(err)
		}
		db, err := sql.Open("sqlite3", tmpDB)
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		var jm string
		if err := db.QueryRow(`PRAGMA journal_mode`).Scan(&jm); err != nil || !strings.EqualFold(jm, "delete") {
			t.Fatalf("expected journal_mode=delete, got %q (err=%v)", jm, err)
		}
		var envCount, adminCount, auditCount, metaTotalCount, vp08MetaCount int
		if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Env`).Scan(&envCount); err != nil {
			t.Fatal(err)
		}
		if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Admin`).Scan(&adminCount); err != nil {
			t.Fatal(err)
		}
		if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Audit`).Scan(&auditCount); err != nil {
			t.Fatal(err)
		}
		if err := db.QueryRow(`SELECT COUNT(*) FROM _table_metadata`).Scan(&metaTotalCount); err != nil {
			t.Fatal(err)
		}
		if err := db.QueryRow(`SELECT COUNT(*) FROM _table_metadata WHERE description='VP08'`).Scan(&vp08MetaCount); err != nil {
			t.Fatal(err)
		}
		if envCount != 2 || adminCount != 2 || auditCount != 0 || metaTotalCount != 8 || vp08MetaCount < 7 {
			t.Fatalf("unexpected vpro64 subset counts: env=%d admin=%d audit=%d metaTotal=%d vp08meta=%d", envCount, adminCount, auditCount, metaTotalCount, vp08MetaCount)
		}
	}

	// 2. csv -> filtered CSV .zip bundle with Env/Admin/Veg/Humus/Mineral/Other/Metadata + README.txt
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "csv",
			"plotNumbers": subsetPlots,
		})
		if !strings.HasSuffix(meta.Filename, ".zip") {
			t.Fatalf("expected .zip filename for csv, got %q", meta.Filename)
		}
		zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
		if err != nil {
			t.Fatalf("open csv zip: %v", err)
		}
		foundFiles := map[string]*zip.File{}
		for _, f := range zr.File {
			foundFiles[f.Name] = f
		}
		for _, reqName := range []string{"Sample_Env.csv", "Sample_Admin.csv", "Sample_Veg.csv", "Sample_Humus.csv", "Sample_Mineral.csv", "Sample_Other.csv", "Sample_Metadata.csv", "README.txt"} {
			if _, ok := foundFiles[reqName]; !ok {
				t.Fatalf("CSV zip missing expected entry %q", reqName)
			}
		}
		rc, err := foundFiles["Sample_Env.csv"].Open()
		if err != nil {
			t.Fatal(err)
		}
		rows, err := csv.NewReader(rc).ReadAll()
		_ = rc.Close()
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) != 3 { // 1 header + 2 filtered plots
			t.Fatalf("expected 3 rows (header+2 plots) in Sample_Env.csv, got %d", len(rows))
		}
		readmeRC, _ := foundFiles["README.txt"].Open()
		readmeBytes, _ := io.ReadAll(readmeRC)
		_ = readmeRC.Close()
		if !strings.Contains(string(readmeBytes), "Open Government Licence") {
			t.Fatalf("README.txt missing OGL-BC attribution: %s", string(readmeBytes))
		}
	}

	// 3. gpkg -> filtered OGC GeoPackage 1.3.1
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "gpkg",
			"plotNumbers": subsetPlots,
		})
		if !strings.HasSuffix(meta.Filename, ".gpkg") || !bytes.HasPrefix(raw, []byte("SQLite format 3\x00")) {
			t.Fatalf("unexpected gpkg output: file=%q len=%d", meta.Filename, len(raw))
		}
		tmpGpkg := filepath.Join(t.TempDir(), "subset.gpkg")
		if err := os.WriteFile(tmpGpkg, raw, 0o600); err != nil {
			t.Fatal(err)
		}
		db, err := sql.Open("sqlite3", tmpGpkg)
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		var featCount int
		if err := db.QueryRow(`SELECT COUNT(*) FROM plots`).Scan(&featCount); err != nil {
			t.Fatalf("query gpkg plots table: %v", err)
		}
		if featCount != 2 {
			t.Fatalf("expected 2 features in filtered gpkg, got %d", featCount)
		}
	}

	// 4. rds -> filtered native R .rds (gzipped XDR v2)
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "rds",
			"plotNumbers": subsetPlots,
		})
		if !strings.HasSuffix(meta.Filename, ".rds") {
			t.Fatalf("expected .rds filename, got %q", meta.Filename)
		}
		gr, err := gzip.NewReader(bytes.NewReader(raw))
		if err != nil {
			t.Fatalf("rds is not valid gzip: %v", err)
		}
		hdr := make([]byte, 2)
		_, err = io.ReadFull(gr, hdr)
		_ = gr.Close()
		if err != nil || string(hdr) != "X\n" {
			t.Fatalf("expected RDS XDR header 'X\\n', got %q (err=%v)", string(hdr), err)
		}
	}

	// 5. turboveg -> filtered TurboVeg XML
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "turboveg",
			"plotNumbers": subsetPlots,
		})
		if !strings.HasSuffix(meta.Filename, ".xml") || !strings.Contains(string(raw), "<Plots") {
			t.Fatalf("unexpected turboveg xml output: file=%q len=%d", meta.Filename, len(raw))
		}
	}

	// 6. kml -> filtered Google Earth KML 2.2
	{
		meta, raw := postDownload(map[string]any{
			"contextId":   state.ContextID,
			"format":      "kml",
			"plotNumbers": subsetPlots,
		})
		kmlStr := string(raw)
		if !strings.HasSuffix(meta.Filename, ".kml") || !strings.Contains(kmlStr, "<kml ") || strings.Count(kmlStr, "<Placemark>") != 2 {
			t.Fatalf("expected 2 Placemarks in filtered KML, got file=%q count=%d", meta.Filename, strings.Count(kmlStr, "<Placemark>"))
		}
	}

	// 7. Download using filter object instead of explicit plotNumbers
	{
		body, _ := json.Marshal(map[string]any{
			"contextId": state.ContextID,
			"format":    "csv",
			"filter": map[string]any{
				"mode": "all",
			},
		})
		rec := httptest.NewRecorder()
		pub.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/becmaster/download", bytes.NewReader(body)))
		if rec.Code != http.StatusOK {
			t.Fatalf("download via filter failed: %d %s", rec.Code, rec.Body.String())
		}
		var dlMeta becmasterDownloadHTTPResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &dlMeta); err != nil {
			t.Fatal(err)
		}
		if dlMeta.PlotCount != allRes.MatchedCount {
			t.Fatalf("filter-driven download plotCount=%d, want %d", dlMeta.PlotCount, allRes.MatchedCount)
		}
	}

	// 8. Export semaphore backpressure returns 503 + Retry-After: 5
	{
		bpSrv := newTestDevSampleServer(t, func(c *WebConfig) {
			c.ExportConcurrency = 1
			c.ExportTimeout = 80 * time.Millisecond
		})
		bpPub := bpSrv.PublicHandler()
		bpSrv.exportSem <- struct{}{}
		defer func() { <-bpSrv.exportSem }()

		body, _ := json.Marshal(map[string]any{
			"format": "vpro64",
			"filter": map[string]any{"mode": "all"},
		})
		rec := httptest.NewRecorder()
		bpPub.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/becmaster/download", bytes.NewReader(body)))
		if rec.Code != http.StatusServiceUnavailable || rec.Header().Get("Retry-After") != "5" {
			t.Fatalf("expected 503 + Retry-After: 5 on export semaphore saturation, got %d ra=%q body=%s",
				rec.Code, rec.Header().Get("Retry-After"), rec.Body.String())
		}
	}

	// 9. Validation errors (400)
	for _, badPayload := range []string{
		`{"format":"bogus","plotNumbers":["00337"]}`,
		`{"format":"vpro64"}`,
		`{"format":"vpro64","plotNumbers":["NO_SUCH_PLOT"]}`,
	} {
		rec := httptest.NewRecorder()
		pub.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/becmaster/download", strings.NewReader(badPayload)))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 for %s, got %d (%s)", badPayload, rec.Code, rec.Body.String())
		}
	}
}
