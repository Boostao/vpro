package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
	_ "github.com/mattn/go-sqlite3"
)

func buildSeededRedBlueVLists(t *testing.T, dir string) string {
	t.Helper()
	raw, err := resources.DatabaseFamilyFS.ReadFile("database-family/VLists.db")
	if err != nil {
		t.Fatalf("read embedded VLists.db: %v", err)
	}
	dst := filepath.Join(dir, "VLists.db")
	if err := os.WriteFile(dst, raw, 0o644); err != nil {
		t.Fatalf("write seeded VLists.db: %v", err)
	}
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dst, "rw")+"&_busy_timeout=5000")
	if err != nil {
		t.Fatalf("open seeded VLists.db: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(`INSERT INTO "USysSppAttributes" ("Code", "Codetype", "RedBlueList") VALUES ('RARESPP1', 'U', 'R')`); err != nil {
		t.Fatalf("seed USysSppAttributes: %v", err)
	}
	return dst
}

func buildReadOnlySnapshotBundle(t *testing.T, vproSnapshotBin, releasesDir, snapshotID string) string {
	t.Helper()
	sourceDir := t.TempDir()
	sampleDB := filepath.Join(sourceDir, "Sample.db")
	if err := os.WriteFile(sampleDB, resources.SampleDB, 0o644); err != nil {
		t.Fatalf("write source Sample.db: %v", err)
	}
	vlistsPath := buildSeededRedBlueVLists(t, sourceDir)
	outDir := filepath.Join(releasesDir, snapshotID)
	cmd := exec.Command(
		vproSnapshotBin,
		"build",
		"--source", sampleDB,
		"--vlists", vlistsPath,
		"--out", outDir,
		"--snapshot-id", snapshotID,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("vpro-snapshot build %s failed: %v\n%s", snapshotID, err, string(out))
	}
	// Verify with vpro-snapshot verify before chmodding read-only.
	verifyCmd := exec.Command(vproSnapshotBin, "verify", "--bundle", outDir)
	if out, err := verifyCmd.CombinedOutput(); err != nil {
		t.Fatalf("vpro-snapshot verify %s failed: %v\n%s", snapshotID, err, string(out))
	}

	// Mount strictly read-only: 0444 files, 0555 directories (bottom-up).
	var dirs []string
	err := filepath.Walk(outDir, func(p string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			dirs = append(dirs, p)
			return nil
		}
		return os.Chmod(p, 0o444)
	})
	if err != nil {
		t.Fatalf("chmod files 0444: %v", err)
	}
	for i := len(dirs) - 1; i >= 0; i-- {
		if err := os.Chmod(dirs[i], 0o555); err != nil {
			t.Fatalf("chmod dir 0555 %q: %v", dirs[i], err)
		}
	}
	t.Cleanup(func() {
		for _, d := range dirs {
			_ = os.Chmod(d, 0o755)
		}
		_ = filepath.Walk(outDir, func(p string, info os.FileInfo, walkErr error) error {
			if walkErr == nil && !info.IsDir() {
				_ = os.Chmod(p, 0o644)
			}
			return nil
		})
	})
	return outDir
}

func httpPostRPC(t *testing.T, client *http.Client, baseURL, sessionID, service, method string, args ...any) (int, []byte) {
	t.Helper()
	if args == nil {
		args = []any{}
	}
	raw, err := json.Marshal(map[string]any{"args": args})
	if err != nil {
		t.Fatalf("marshal args: %v", err)
	}
	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/rpc/"+service+"/"+method, bytes.NewReader(raw))
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-VPro-Session", sessionID)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("POST %s.%s failed: %v", service, method, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read response body: %v", err)
	}
	return resp.StatusCode, body
}

func Test25ConcurrentClientsReadOnlySnapshotAndLiveReload(t *testing.T) {
	// Build vpro-snapshot CLI once into temp dir so we test against real vpro-snapshot bundles.
	binDir := t.TempDir()
	snapshotBin := filepath.Join(binDir, "vpro-snapshot")
	buildArgs := []string{"build"}
	if testBuildTags != "" {
		buildArgs = append(buildArgs, "-tags", testBuildTags)
	}
	buildArgs = append(buildArgs, "-o", snapshotBin, "./cmd/vpro-snapshot")
	buildCmd := exec.Command("go", buildArgs...)
	buildCmd.Dir = "../.."
	if out, err := buildCmd.CombinedOutput(); err != nil {
		t.Fatalf("build vpro-snapshot failed: %v\n%s", err, string(out))
	}

	dataRoot := t.TempDir()
	releasesDir := filepath.Join(dataRoot, "releases")
	if err := os.MkdirAll(releasesDir, 0o755); err != nil {
		t.Fatal(err)
	}

	buildReadOnlySnapshotBundle(t, snapshotBin, releasesDir, "snap-v1")
	buildReadOnlySnapshotBundle(t, snapshotBin, releasesDir, "snap-v2")

	currentLink := filepath.Join(dataRoot, "current")
	if err := os.Symlink(filepath.Join("releases", "snap-v1"), currentLink); err != nil {
		t.Fatalf("create current symlink: %v", err)
	}

	cfg := WebConfig{
		Env:               "prod",
		ListenAddr:        ":0",
		InternalAddr:      "127.0.0.1:0",
		DataDir:           currentLink,
		PMTilesDir:        t.TempDir(),
		ExportDir:         t.TempDir(),
		ExportConcurrency: 4,
		ExportTimeout:     60 * time.Second,
		RConcurrency:      2,
		RTimeout:          60 * time.Second,
		PoolSlots:         6,
		MaxPools:          16,
		CacheMaxMB:        64,
	}
	srv, err := NewWebServer(context.Background(), cfg)
	if err != nil {
		t.Fatalf("NewWebServer on 0555/0444 snapshot failed: %v", err)
	}
	defer srv.Close()

	pubTS := httptest.NewServer(srv.PublicHandler())
	defer pubTS.Close()
	intTS := httptest.NewServer(srv.InternalHandler())
	defer intTS.Close()

	httpClient := &http.Client{Timeout: 60 * time.Second}

	// Verify initial /api/meta reports snap-v1.
	metaResp, err := httpClient.Get(pubTS.URL + "/api/meta")
	if err != nil {
		t.Fatalf("GET /api/meta: %v", err)
	}
	var meta1 MetaResponse
	if err := json.NewDecoder(metaResp.Body).Decode(&meta1); err != nil {
		t.Fatalf("decode /api/meta: %v", err)
	}
	metaResp.Body.Close()
	if meta1.SnapshotID != "snap-v1" || len(meta1.Datasets) != 1 || meta1.Datasets[0].PlotCount == 0 {
		t.Fatalf("unexpected initial meta: %+v", meta1)
	}

	// Launch 25 concurrent HTTP clients exercising SUs/hierarchies, plot bundles,
	// datasheets, spatial payloads, veg/env report previews, per-session prefs, and
	// concurrent .xlsx / .pdf / .kml / .zip downloads, while triggering live /internal/reload mid-flight!
	const clientCount = 25
	var (
		wg               sync.WaitGroup
		errMu            sync.Mutex
		errs             []string
		v1RequestsDone   atomic.Int32
		reloadedCh       = make(chan struct{})
		downloadSuccess  atomic.Int32
		staleContextSeen atomic.Int32
	)
	recordErr := func(format string, args ...any) {
		errMu.Lock()
		errs = append(errs, fmt.Sprintf(format, args...))
		errMu.Unlock()
	}

	// Helper to run one full read/preview/download pass for a client.
	runClientWorkload := func(idx int, sessID string, afterReload bool) {
		// 1. GetState
		code, body := httpPostRPC(t, httpClient, pubTS.URL, sessID, "ContextService", "GetState")
		if code != http.StatusOK {
			recordErr("client %d GetState failed: %d %s", idx, code, string(body))
			return
		}
		var stateEnv struct {
			Result vprocore.ProjectState `json:"result"`
		}
		if err := json.Unmarshal(body, &stateEnv); err != nil {
			recordErr("client %d decode GetState: %v", idx, err)
			return
		}
		st := stateEnv.Result

		// 2. SwitchContext alternating SUs & Hierarchies across clients.
		// Clients with idx%4 == 0 or 1 select a compatible SU (needed for Env/Veg SU reports & workbooks);
		// clients with idx%4 == 2 or 3 keep SU="None" to exercise project-wide views concurrently.
		targetSU := "None"
		if idx%4 < 2 && len(st.SUs) > 0 {
			for _, su := range st.SUs {
				if su.Compatible {
					targetSU = su.Name
					break
				}
			}
		}
		targetHier := "None"
		if idx%3 != 0 && len(st.Hierarchies) > 0 {
			for _, h := range st.Hierarchies {
				if h.Compatible {
					targetHier = h.Name
					break
				}
			}
		}
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ContextService", "SwitchContext",
			st.ContextID,
			vprocore.ContextSelection{
				Project:   st.ActiveProject,
				SU:        targetSU,
				Hierarchy: targetHier,
			},
		)
		if code != http.StatusOK {
			recordErr("client %d SwitchContext(su=%s,h=%s) failed: %d %s", idx, targetSU, targetHier, code, string(body))
			return
		}
		if err := json.Unmarshal(body, &stateEnv); err != nil {
			recordErr("client %d decode SwitchContext: %v", idx, err)
			return
		}
		ctxID := stateEnv.Result.ContextID

		// Helper that accepts 409 Conflict during the mid-flight reload window before afterReload.
		checkOKOrReloadStale := func(op string, sc int, b []byte) bool {
			if sc == http.StatusOK {
				return true
			}
			if !afterReload && sc == http.StatusConflict {
				staleContextSeen.Add(1)
				return false
			}
			recordErr("client %d %s failed: %d %s", idx, op, sc, string(b))
			return false
		}

		// 3. ListPlots & GetPlotBundle
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ContextService", "ListPlots", 0, 10)
		if !checkOKOrReloadStale("ListPlots", code, body) {
			return
		}
		var plotPageEnv struct {
			Result vprocore.PlotPage `json:"result"`
		}
		if err := json.Unmarshal(body, &plotPageEnv); err != nil || len(plotPageEnv.Result.Plots) == 0 {
			recordErr("client %d ListPlots empty or invalid: %v", idx, err)
			return
		}
		firstPlot := plotPageEnv.Result.Plots[0].PlotNumber

		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ContextService", "GetPlotBundle", ctxID, firstPlot, true)
		if !checkOKOrReloadStale("GetPlotBundle", code, body) {
			return
		}

		// 4. Datasheet page
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "DatasheetService", "GetDatasheetPage",
			ctxID,
			map[string]any{"tableKey": "Env", "offset": 0, "limit": 20},
		)
		if !checkOKOrReloadStale("GetDatasheetPage", code, body) {
			return
		}

		// 5. Spatial workbench payload
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "SpatialService", "GetSpatialWorkbenchPayload", ctxID)
		if !checkOKOrReloadStale("GetSpatialWorkbenchPayload", code, body) {
			return
		}

		// 6. Veg & Env report previews (SU-scoped reports when SU != None; compliance/species lookup when SU == None)
		if targetSU != "None" {
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "EnvironmentReportService", "PreviewLongEnvironment",
				ctxID,
				map[string]any{"title": fmt.Sprintf("Client %d Env", idx)},
			)
			if !checkOKOrReloadStale("PreviewLongEnvironment", code, body) {
				return
			}
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "VegetationReportService", "PreviewSummaryVegetation", ctxID, 1, 1)
			if !checkOKOrReloadStale("PreviewSummaryVegetation", code, body) {
				return
			}
		} else {
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ValidationService", "RunComplianceValidation", ctxID, map[string]any{})
			if !checkOKOrReloadStale("RunComplianceValidation", code, body) {
				return
			}
		}

		// 7. Per-session preference isolation
		modes := []string{"dd", "dm", "dms"}
		expectedMode := modes[idx%len(modes)]
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "SpatialService", "SetCoordinateMode", expectedMode)
		if code != http.StatusNoContent {
			recordErr("client %d SetCoordinateMode(%s) failed: %d %s", idx, expectedMode, code, string(body))
			return
		}
		code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "SpatialService", "GetCoordinateMode")
		if code != http.StatusOK {
			recordErr("client %d GetCoordinateMode failed: %d %s", idx, code, string(body))
			return
		}
		var modeEnv struct {
			Result string `json:"result"`
		}
		if err := json.Unmarshal(body, &modeEnv); err != nil || modeEnv.Result != expectedMode {
			recordErr("client %d coord mode isolation mismatch: want %q got %q", idx, expectedMode, modeEnv.Result)
			return
		}

		// 8. Concurrent artifact downloads across formats (.xlsx, .pdf, .kml, .zip)
		downloadArtifact := func(dlURL string, expectedPrefix []byte, label string) {
			resp, err := httpClient.Get(pubTS.URL + dlURL)
			if err != nil {
				recordErr("client %d GET %s (%s): %v", idx, dlURL, label, err)
				return
			}
			defer resp.Body.Close()
			data, _ := io.ReadAll(resp.Body)
			if resp.StatusCode != http.StatusOK {
				recordErr("client %d GET %s (%s): status %d", idx, dlURL, label, resp.StatusCode)
				return
			}
			if !bytes.HasPrefix(data, expectedPrefix) {
				recordErr("client %d %s unexpected file header (len=%d)", idx, label, len(data))
				return
			}
			downloadSuccess.Add(1)
		}

		switch idx % 4 {
		case 0:
			// .xlsx Environment Workbook (Review -> ExportReviewed)
			revReq, _ := json.Marshal(map[string]any{"title": fmt.Sprintf("Env %d", idx)})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "EnvironmentReportService", "GetEnvironmentWorkbookReview", ctxID, string(revReq))
			if !checkOKOrReloadStale("GetEnvironmentWorkbookReview", code, body) {
				return
			}
			var revEnv struct {
				Result struct {
					ApprovalHash string `json:"approvalHash"`
				} `json:"result"`
			}
			if err := json.Unmarshal(body, &revEnv); err != nil || revEnv.Result.ApprovalHash == "" {
				recordErr("client %d decode Env review: %v", idx, err)
				return
			}
			expReq, _ := json.Marshal(map[string]any{
				"title":        fmt.Sprintf("Env %d", idx),
				"approvalHash": revEnv.Result.ApprovalHash,
				"destination":  "/should/be/ignored.xlsx",
			})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "EnvironmentReportService", "ExportReviewedEnvironmentWorkbook", ctxID, string(expReq))
			if !checkOKOrReloadStale("ExportReviewedEnvironmentWorkbook", code, body) {
				return
			}
			var dlEnv struct {
				DownloadURL string `json:"downloadUrl"`
			}
			if err := json.Unmarshal(body, &dlEnv); err == nil && dlEnv.DownloadURL != "" {
				downloadArtifact(dlEnv.DownloadURL, []byte("PK\x03\x04"), "xlsx")
			}

		case 1:
			// .pdf Plot Label PDF (Review -> ExportReviewed)
			revReq, _ := json.Marshal(map[string]any{"plotNumber": firstPlot})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ImportExportService", "GetPlotLabelPDFReview", ctxID, string(revReq))
			if !checkOKOrReloadStale("GetPlotLabelPDFReview", code, body) {
				return
			}
			var revEnv struct {
				Result struct {
					ApprovalHash string `json:"approvalHash"`
					SessionID    string `json:"sessionId"`
				} `json:"result"`
			}
			if err := json.Unmarshal(body, &revEnv); err != nil || revEnv.Result.ApprovalHash == "" {
				recordErr("client %d decode PDF review: %v", idx, err)
				return
			}
			uuid := fmt.Sprintf("11111111-2222-4333-8444-%012d", idx+1000)
			if afterReload {
				uuid = fmt.Sprintf("22222222-2222-4333-8444-%012d", idx+2000)
			}
			expReq, _ := json.Marshal(map[string]any{
				"plotNumber":   firstPlot,
				"approvalHash": revEnv.Result.ApprovalHash,
				"destination":  "/should/be/ignored.pdf",
				"requestId":    uuid,
				"sessionId":    revEnv.Result.SessionID,
			})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ImportExportService", "ExportReviewedPlotLabelPDF", ctxID, string(expReq))
			if !checkOKOrReloadStale("ExportReviewedPlotLabelPDF", code, body) {
				return
			}
			var dlEnv struct {
				DownloadURL string `json:"downloadUrl"`
			}
			if err := json.Unmarshal(body, &dlEnv); err == nil && dlEnv.DownloadURL != "" {
				downloadArtifact(dlEnv.DownloadURL, []byte("%PDF-"), "pdf")
			}

		case 2:
			// .kml Google Earth KML (Review -> ExportReviewed)
			revReq, _ := json.Marshal(map[string]any{
				"descriptionField": "PlotRepresenting",
				"title":            fmt.Sprintf("KML %d", idx),
			})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "SpatialService", "GetGoogleEarthKMLExportReview", ctxID, string(revReq))
			if !checkOKOrReloadStale("GetGoogleEarthKMLExportReview", code, body) {
				return
			}
			var revEnv struct {
				Result struct {
					ApprovalHash string `json:"approvalHash"`
				} `json:"result"`
			}
			if err := json.Unmarshal(body, &revEnv); err != nil || revEnv.Result.ApprovalHash == "" {
				recordErr("client %d decode KML review: %v", idx, err)
				return
			}
			expReq, _ := json.Marshal(map[string]any{
				"descriptionField": "PlotRepresenting",
				"title":            fmt.Sprintf("KML %d", idx),
				"approvalHash":     revEnv.Result.ApprovalHash,
				"destination":      "/should/be/ignored.kml",
			})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "SpatialService", "ExportReviewedGoogleEarthKML", ctxID, string(expReq))
			if !checkOKOrReloadStale("ExportReviewedGoogleEarthKML", code, body) {
				return
			}
			var dlEnv struct {
				DownloadURL string `json:"downloadUrl"`
			}
			if err := json.Unmarshal(body, &dlEnv); err == nil && dlEnv.DownloadURL != "" {
				downloadArtifact(dlEnv.DownloadURL, []byte("<?xml"), "kml")
			}

		case 3:
			// .zip Table CSV Archive (Review -> ExportReviewed)
			coreTable := st.ActiveProject + "_Env"
			revReq, _ := json.Marshal(map[string]any{"table": coreTable})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ImportExportService", "GetTableCSVArchiveReview", ctxID, string(revReq))
			if !checkOKOrReloadStale("GetTableCSVArchiveReview", code, body) {
				return
			}
			var revEnv struct {
				Result struct {
					ApprovalHash string `json:"approvalHash"`
				} `json:"result"`
			}
			if err := json.Unmarshal(body, &revEnv); err != nil || revEnv.Result.ApprovalHash == "" {
				recordErr("client %d decode ZIP review: %v", idx, err)
				return
			}
			expReq, _ := json.Marshal(map[string]any{
				"table":        coreTable,
				"approvalHash": revEnv.Result.ApprovalHash,
				"destination":  "/should/be/ignored.zip",
			})
			code, body = httpPostRPC(t, httpClient, pubTS.URL, sessID, "ImportExportService", "ExportReviewedTableCSVArchive", ctxID, string(expReq))
			if !checkOKOrReloadStale("ExportReviewedTableCSVArchive", code, body) {
				return
			}
			var dlEnv struct {
				DownloadURL string `json:"downloadUrl"`
			}
			if err := json.Unmarshal(body, &dlEnv); err == nil && dlEnv.DownloadURL != "" {
				downloadArtifact(dlEnv.DownloadURL, []byte("PK\x03\x04"), "zip")
			}
		}
	}

	// Capture a snap-v1 token before reload so we can prove stale-context fencing after reload.
	_, preBody := httpPostRPC(t, httpClient, pubTS.URL, "fence-sess", "ContextService", "GetState")
	var preState struct {
		Result vprocore.ProjectState `json:"result"`
	}
	if err := json.Unmarshal(preBody, &preState); err != nil {
		t.Fatalf("decode pre-reload state: %v", err)
	}
	v1ContextID := preState.Result.ContextID

	// Start 25 concurrent clients!
	for i := 0; i < clientCount; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			sessID := fmt.Sprintf("concurrent-client-%02d", idx)
			runClientWorkload(idx, sessID, false)
			v1RequestsDone.Add(1)
			<-reloadedCh
			runClientWorkload(idx, sessID, true)
		}(i)
	}

	// Wait until several clients have completed or are in-flight on snap-v1, then atomically flip symlink and reload!
	deadline := time.Now().Add(30 * time.Second)
	for v1RequestsDone.Load() < 5 && time.Now().Before(deadline) {
		time.Sleep(15 * time.Millisecond)
	}

	// Atomic symlink flip: current.next -> releases/snap-v2, rename over current.
	tmpLink := filepath.Join(dataRoot, "current.next")
	if err := os.Symlink(filepath.Join("releases", "snap-v2"), tmpLink); err != nil {
		t.Fatalf("symlink current.next: %v", err)
	}
	if err := os.Rename(tmpLink, currentLink); err != nil {
		t.Fatalf("atomic rename symlink: %v", err)
	}

	reloadResp, err := httpClient.Post(intTS.URL+"/internal/reload", "application/json", nil)
	if err != nil {
		t.Fatalf("POST /internal/reload: %v", err)
	}
	reloadBody, _ := io.ReadAll(reloadResp.Body)
	reloadResp.Body.Close()
	if reloadResp.StatusCode != http.StatusOK || !strings.Contains(string(reloadBody), `"snapshotId":"snap-v2"`) {
		t.Fatalf("POST /internal/reload failed: %d %s", reloadResp.StatusCode, string(reloadBody))
	}

	// Unblock phase 2 for all 25 clients on snap-v2.
	close(reloadedCh)
	wg.Wait()

	if len(errs) > 0 {
		t.Fatalf("concurrent workload had %d error(s):\n%s", len(errs), strings.Join(errs, "\n"))
	}
	if downloadSuccess.Load() < clientCount {
		t.Fatalf("expected at least %d successful artifact downloads across .xlsx/.pdf/.kml/.zip, got %d", clientCount, downloadSuccess.Load())
	}

	// Verify old snap-v1 contextID is strictly rejected with 409 Conflict after reload.
	staleCode, staleBody := httpPostRPC(t, httpClient, pubTS.URL, "fence-sess", "ContextService", "GetPlot", v1ContextID, "00001")
	if staleCode != http.StatusConflict {
		t.Fatalf("expected 409 Conflict for stale snap-v1 contextID after reload, got %d (%s)", staleCode, string(staleBody))
	}

	// Verify /api/meta now advertises snap-v2.
	meta2Resp, err := httpClient.Get(pubTS.URL + "/api/meta")
	if err != nil {
		t.Fatalf("GET /api/meta after reload: %v", err)
	}
	var meta2 MetaResponse
	if err := json.NewDecoder(meta2Resp.Body).Decode(&meta2); err != nil {
		t.Fatalf("decode /api/meta after reload: %v", err)
	}
	meta2Resp.Body.Close()
	if meta2.SnapshotID != "snap-v2" {
		t.Fatalf("expected /api/meta snapshotId=snap-v2 after reload, got %q", meta2.SnapshotID)
	}

	// Verify failed reload (pointing symlink to a tampered bundle) returns 422 AND preserves snap-v2 live!
	badDir := filepath.Join(releasesDir, "snap-bad")
	if err := os.MkdirAll(badDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(badDir, "manifest.json"), []byte(`{"schemaVersion":1,"snapshotId":"snap-bad"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	badLink := filepath.Join(dataRoot, "current.bad")
	if err := os.Symlink(filepath.Join("releases", "snap-bad"), badLink); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(badLink, currentLink); err != nil {
		t.Fatal(err)
	}
	badReloadResp, err := httpClient.Post(intTS.URL+"/internal/reload", "application/json", nil)
	if err != nil {
		t.Fatalf("POST /internal/reload (bad): %v", err)
	}
	badReloadResp.Body.Close()
	if badReloadResp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for invalid reload bundle, got %d", badReloadResp.StatusCode)
	}
	// snap-v2 must still be served!
	stillReady, err := httpClient.Get(pubTS.URL + "/readyz")
	if err != nil {
		t.Fatal(err)
	}
	stillBody, _ := io.ReadAll(stillReady.Body)
	stillReady.Body.Close()
	if stillReady.StatusCode != http.StatusOK || !strings.Contains(string(stillBody), `"snapshotId":"snap-v2"`) {
		t.Fatalf("expected snap-v2 to remain live after failed reload, got %d %s", stillReady.StatusCode, string(stillBody))
	}

	// Wait for drained old snap-v1 pools cleanly.
	drainCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.pool.WaitDrained(drainCtx); err != nil {
		t.Fatalf("WaitDrained failed: %v", err)
	}
}
