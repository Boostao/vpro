package spatial

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/boostao/vpro/app/resources"
)

func TestW3UXSpatial001_CorruptPMTilesHeaderAndRootDirFallback(t *testing.T) {
	dataDir := t.TempDir()
	mapsDir := filepath.Join(dataDir, "maps")
	if err := os.MkdirAll(mapsDir, 0o755); err != nil {
		t.Fatal(err)
	}

	// 1. Exact 560-byte non-PMTiles archive from UX-SPATIAL-001 repro
	corrupt560 := bytes.Repeat([]byte("NOT_A_VALID_PMTILES_ARCHIVE_"), 20)
	if len(corrupt560) != 560 {
		t.Fatalf("unexpected repro byte length %d", len(corrupt560))
	}
	bgcPath := filepath.Join(mapsDir, PMTilesBGCArchiveName)
	if err := os.WriteFile(bgcPath, corrupt560, 0o600); err != nil {
		t.Fatal(err)
	}

	// 2. Fake PMTiles v3 magic header (>= 127 bytes) with structurally invalid root directory range
	var fakeMagic [256]byte
	copy(fakeMagic[:7], "PMTiles")
	fakeMagic[7] = 3
	binary.LittleEndian.PutUint64(fakeMagic[8:16], 127)     // rootDirOffset
	binary.LittleEndian.PutUint64(fakeMagic[16:24], 999999) // rootDirBytes out of bounds
	binary.LittleEndian.PutUint64(fakeMagic[56:64], 200)    // tileDataOffset
	binary.LittleEndian.PutUint64(fakeMagic[64:72], 50)     // tileDataBytes
	fakeMagic[97] = 2                                       // gzip internal compression
	fakeMagic[98] = 2                                       // gzip tile compression
	fakeMagic[100] = 3                                      // minZoom
	fakeMagic[101] = 10                                     // maxZoom
	adminPath := filepath.Join(mapsDir, PMTilesAdminArchiveName)
	if err := os.WriteFile(adminPath, fakeMagic[:], 0o600); err != nil {
		t.Fatal(err)
	}

	// 3. Non-standard corrupt archive with no embedded fallback -> missing + warning
	customPath := filepath.Join(mapsDir, "custom-corrupt.pmtiles")
	if err := os.WriteFile(customPath, corrupt560, 0o600); err != nil {
		t.Fatal(err)
	}

	// Pass no extraDirs so resolution must fall back directly from dataDir to embedded-overview
	manifest := BuildPMTilesManifest(dataDir)
	bgcStatus, ok := manifest.Archives[PMTilesBGCArchiveName]
	if !ok {
		t.Fatalf("missing %s in manifest", PMTilesBGCArchiveName)
	}
	if bgcStatus.Source != "embedded-overview" || !bgcStatus.Available || !bgcStatus.FallbackOverview {
		t.Fatalf("expected embedded-overview fallback for corrupt %s, got %+v", PMTilesBGCArchiveName, bgcStatus)
	}
	if bgcStatus.MinZoom != 3 || bgcStatus.MaxZoom != 6 {
		t.Fatalf("expected embedded overview zoom bounds z3..6, got z%d..%d", bgcStatus.MinZoom, bgcStatus.MaxZoom)
	}
	if !strings.Contains(bgcStatus.Warning, PMTilesBGCArchiveName) || !strings.Contains(bgcStatus.Warning, "unreadable") {
		t.Fatalf("expected plain-language corrupt archive warning on %s, got %q", PMTilesBGCArchiveName, bgcStatus.Warning)
	}

	adminStatus := manifest.Archives[PMTilesAdminArchiveName]
	if adminStatus.Source != "embedded-overview" || !adminStatus.FallbackOverview || adminStatus.MaxZoom != 6 || adminStatus.Warning == "" {
		t.Fatalf("expected fake-magic %s rejected by structural validation, got %+v", PMTilesAdminArchiveName, adminStatus)
	}

	customStatus := manifest.Archives["custom-corrupt.pmtiles"]
	if customStatus.Source != "missing" || customStatus.Available || !strings.Contains(customStatus.Warning, "custom-corrupt.pmtiles") {
		t.Fatalf("expected custom corrupt archive marked missing with warning, got %+v", customStatus)
	}

	// Verify HTTP asset handler serves embedded bc-overview.pmtiles bytes instead of the corrupt 560-byte file
	handler := NewPMTilesAssetHandler(nil, dataDir)
	rangeReq := httptest.NewRequest(http.MethodGet, "/maps/"+PMTilesBGCArchiveName, nil)
	rangeReq.Header.Set("Range", "bytes=0-126")
	rangeRec := httptest.NewRecorder()
	handler.ServeHTTP(rangeRec, rangeReq)
	if rangeRec.Code != http.StatusPartialContent || rangeRec.Header().Get("X-VPro-PMTiles-Source") != "embedded-overview" {
		t.Fatalf("expected HTTP 206 from embedded-overview, got status=%d src=%q", rangeRec.Code, rangeRec.Header().Get("X-VPro-PMTiles-Source"))
	}
	if !bytes.Equal(rangeRec.Body.Bytes(), resources.BCOverviewPMTiles[:127]) {
		t.Fatalf("expected embedded bc-overview header bytes, got %x", rangeRec.Body.Bytes()[:16])
	}

	manReq := httptest.NewRequest(http.MethodGet, "/maps/manifest.json", nil)
	manRec := httptest.NewRecorder()
	handler.ServeHTTP(manRec, manReq)
	var httpManifest PMTilesManifest
	if err := json.Unmarshal(manRec.Body.Bytes(), &httpManifest); err != nil {
		t.Fatalf("unmarshal HTTP manifest: %v", err)
	}
	if httpManifest.Archives[PMTilesBGCArchiveName].Source != "embedded-overview" ||
		httpManifest.Archives[PMTilesBGCArchiveName].Warning == "" {
		t.Fatalf("expected HTTP /maps/manifest.json to report embedded-overview + warning, got %+v", httpManifest.Archives[PMTilesBGCArchiveName])
	}
}

func TestW3UXSpatial003_AntimeridianLongitudePreservedInPlotLocationsAndKML(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Latitude, Longitude) VALUES ('QAANT1', 'CWH', 'vh1', 52.5, 179.9);
		INSERT INTO Sample_Admin (Plot) VALUES ('QAANT1');
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Latitude, Longitude) VALUES ('QAANT2', 'CWH', 'vh1', 52.5, -179.9);
		INSERT INTO Sample_Admin (Plot) VALUES ('QAANT2');
	`)

	locReview, err := GetPlotLocationReview(service, context.Background(), state.ContextID)
	if err != nil {
		t.Fatalf("GetPlotLocationReview: %v", err)
	}
	gotLon := map[string]float64{}
	for _, row := range locReview.Report.Rows {
		if row.Values[0].Text != nil && row.Values[6].Real != nil {
			gotLon[*row.Values[0].Text] = *row.Values[6].Real
		}
	}
	if gotLon["QAANT1"] != 179.9 {
		t.Fatalf("expected Eastern Hemisphere QAANT1 preserved as +179.9, got %v", gotLon["QAANT1"])
	}
	if gotLon["QAANT2"] != -179.9 {
		t.Fatalf("expected Western Hemisphere QAANT2 preserved as -179.9, got %v", gotLon["QAANT2"])
	}

	kmlOwned, err := ReadGoogleEarthKML(service, context.Background(), state.ContextID, "Zone", "Antimeridian Check")
	if err != nil {
		t.Fatalf("ReadGoogleEarthKML: %v", err)
	}
	kmlStr := string(kmlOwned.Bytes)
	if !strings.Contains(kmlStr, "<name>QAANT1</name><description>CWH.</description><Point><coordinates>179.9,52.5,0</coordinates></Point>") {
		t.Fatalf("expected QAANT1 KML coordinates 179.9,52.5,0, got:\n%s", kmlStr)
	}
	if !strings.Contains(kmlStr, "<name>QAANT2</name><description>CWH.</description><Point><coordinates>-179.9,52.5,0</coordinates></Point>") {
		t.Fatalf("expected QAANT2 KML coordinates -179.9,52.5,0, got:\n%s", kmlStr)
	}
}

func TestW3UXSpatial004_UTMZone12ProjectionAndInvalidZeroCoordinateQAFlags(t *testing.T) {
	// 1. Direct NAD83 UTM Zone 12 round-trip & EvaluatePlotGeodesy for QAZ12
	lat12, lon12 := 50.0, -113.5
	z, e, n, err := ProjectNAD83LatLonToUTM(lat12, lon12)
	if err != nil {
		t.Fatalf("ProjectNAD83LatLonToUTM Zone 12 failed: %v", err)
	}
	if z != 12 {
		t.Fatalf("expected UTM Zone 12 for -113.5W, got %d", z)
	}
	rtLat, rtLon, err := ProjectNAD83UTMToLatLon(z, e, n)
	if err != nil {
		t.Fatalf("ProjectNAD83UTMToLatLon Zone 12 failed: %v", err)
	}
	if EllipsoidalDistanceNAD83(lat12, lon12, rtLat, rtLon) >= 0.01 {
		t.Fatalf("Zone 12 round-trip error >= 0.01 m")
	}

	utmZ := "12"
	exactEvalZ12 := EvaluatePlotGeodesy(PlotGeodesyInput{
		Latitude:    &lat12,
		Longitude:   &lon12,
		UTMZone:     &utmZ,
		UTMEasting:  &e,
		UTMNorthing: &n,
	})
	if !exactEvalZ12.HasLatLon || !exactEvalZ12.HasUTM || exactEvalZ12.ComputedUTMZone == nil || *exactEvalZ12.ComputedUTMZone != 12 {
		t.Fatalf("expected Zone 12 HasUTM=true and ComputedUTMZone=12, got %+v", exactEvalZ12)
	}
	if exactEvalZ12.DivergenceFlagged || exactEvalZ12.DivergenceMeters == nil || *exactEvalZ12.DivergenceMeters > 0.1 {
		t.Fatalf("expected matching Zone 12 UTM delta < 0.1m, got %+v", exactEvalZ12)
	}

	// Repro QAZ12 coordinates (320973.0, 5541502.0) project cleanly in Zone 12 and flag ~180.1m UTM divergence
	east := 320973.0
	north := 5541502.0
	evalZ12 := EvaluatePlotGeodesy(PlotGeodesyInput{
		Latitude:    &lat12,
		Longitude:   &lon12,
		UTMZone:     &utmZ,
		UTMEasting:  &east,
		UTMNorthing: &north,
	})
	if !evalZ12.HasLatLon || !evalZ12.HasUTM || evalZ12.ComputedUTMZone == nil || *evalZ12.ComputedUTMZone != 12 {
		t.Fatalf("expected QAZ12 HasUTM=true and ComputedUTMZone=12, got %+v", evalZ12)
	}
	if !evalZ12.DivergenceFlagged || evalZ12.DivergenceMeters == nil || *evalZ12.DivergenceMeters < 150.0 {
		t.Fatalf("expected QAZ12 ~180m Zone 12 UTM delta flagged, got %+v", evalZ12)
	}

	// 2. SuggestSpatialAttributes populates Zone 12 UTM coordinates instead of Zone 0: 0.0 E, 0.0 N
	attr := NewPMTilesAttributor("")
	defer attr.Close()
	sug12, err := attr.SuggestSpatialAttributes(lat12, lon12)
	if err != nil {
		t.Fatalf("SuggestSpatialAttributes Zone 12: %v", err)
	}
	if sug12.UTMZone != 12 || math.Abs(sug12.UTMEasting-e) > 0.01 || math.Abs(sug12.UTMNorthing-n) > 0.01 {
		t.Fatalf("expected Zone 12 UTM suggestion matching forward projection, got %+v", sug12)
	}

	// 3. BatchAuditSpatialQA flags QA0000 (0, 0) and QA9999 (95, 200) with clear diagnostics
	service, state := vprotest.ContextServiceFixture(t)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Latitude, Longitude, UTMZone, UTMEasting, UTMNorthing)
		VALUES ('QAZ12', 'IDF', 'dk5', 50.0, -113.5, '12', 320973.0, 5541502.0);
		INSERT INTO Sample_Admin (Plot) VALUES ('QAZ12');
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Latitude, Longitude)
		VALUES ('QA0000', 'CWH', 'vh1', 0.0, 0.0);
		INSERT INTO Sample_Admin (Plot) VALUES ('QA0000');
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Latitude, Longitude)
		VALUES ('QA9999', 'CWH', 'vh1', 95.0, 200.0);
		INSERT INTO Sample_Admin (Plot) VALUES ('QA9999');
	`)

	report, err := BatchAuditSpatialQA(context.Background(), service, state.ContextID, attr)
	if err != nil {
		t.Fatalf("BatchAuditSpatialQA: %v", err)
	}
	byPlot := map[string]SpatialPlotQARow{}
	for _, r := range report.Rows {
		byPlot[r.PlotNumber] = r
	}

	qa0, ok := byPlot["QA0000"]
	if !ok || len(qa0.Diagnostics) == 0 || !strings.Contains(strings.Join(qa0.Diagnostics, " "), "(0, 0)") {
		t.Fatalf("expected QA0000 to carry explicit (0, 0) coordinate diagnostic, got %+v", qa0)
	}
	if qa0.NormalizedLat != nil || qa0.NormalizedLon != nil {
		t.Fatalf("expected QA0000 (0, 0) not to normalize to a Null Island map pin, got %+v", qa0)
	}

	qa9, ok := byPlot["QA9999"]
	if !ok || len(qa9.Diagnostics) == 0 || !strings.Contains(strings.Join(qa9.Diagnostics, " "), "95.00000") {
		t.Fatalf("expected QA9999 to carry out-of-range coordinate diagnostic, got %+v", qa9)
	}

	qaz12, ok := byPlot["QAZ12"]
	if !ok || qaz12.ComputedUTMZone == nil || *qaz12.ComputedUTMZone != 12 || qaz12.DivergenceMeters == nil {
		t.Fatalf("expected QAZ12 to project Zone 12 in BatchAuditSpatialQA, got %+v", qaz12)
	}
}

func TestW3UXSpatial005_GoogleEarthKMLErrorsIdentifyPlotNumberWithoutRowID(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, PlotRepresenting, Latitude, Longitude)
		VALUES ('QA9999', 'Out of range test plot', 95.0, 200.0);
		INSERT INTO Sample_Admin (Plot) VALUES ('QA9999');
	`)

	kmlSvc := NewGoogleEarthKMLService(service)
	exportSvc := NewGoogleEarthKMLExportService(service)
	reqJSON := `{"descriptionField":"PlotRepresenting","title":"VPro Plot Locations"}`

	_, errPreview := kmlSvc.GetGoogleEarthKMLReview(context.Background(), state.ContextID, reqJSON)
	if errPreview == nil {
		t.Fatal("expected KML preview error for out-of-range plot QA9999")
	}
	msg := errPreview.Error()
	if !strings.Contains(msg, `"QA9999"`) || !strings.Contains(msg, "latitude 95") || !strings.Contains(msg, "longitude 200") {
		t.Fatalf("expected KML error to identify plot QA9999 and coordinates, got: %s", msg)
	}
	for _, forbidden := range []string{"Env row", "membership", "rowid", "point 4"} {
		if strings.Contains(msg, forbidden) {
			t.Fatalf("KML error leaked internal identifier %q: %s", forbidden, msg)
		}
	}

	_, errExport := exportSvc.GetGoogleEarthKMLExportReview(context.Background(), state.ContextID, reqJSON)
	if errExport == nil || !strings.Contains(errExport.Error(), `"QA9999"`) || strings.Contains(errExport.Error(), "Env row") {
		t.Fatalf("expected KML export review error to identify QA9999 without Env rowid, got: %v", errExport)
	}

	// Also verify direct prepareGoogleEarthKML error names PlotNumber
	_, errDirect := prepareGoogleEarthKML(context.Background(), "Title", []googleEarthKMLPoint{
		{Name: "QA9999", Description: "desc", Longitude: 200.0, Latitude: 95.0},
	})
	if errDirect == nil || !strings.Contains(errDirect.Error(), `"QA9999"`) || strings.Contains(errDirect.Error(), "point 0") {
		t.Fatalf("expected prepareGoogleEarthKML error to reference PlotNumber QA9999, got: %v", errDirect)
	}
	_ = vprocore.WesternBCMinLon
}
