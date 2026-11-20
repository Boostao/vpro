package spatial

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestBCGovMapProxy_RoutesAndValidation(t *testing.T) {
	pngBytes := []byte{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x01}
	jpegBytes := []byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F'}

	var lastMapsReqPath string
	mapsSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lastMapsReqPath = r.URL.Path
		switch r.URL.Path {
		case "/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/6/21/10":
			w.Header().Set("Content-Type", "image/jpeg")
			w.Header().Set("Set-Cookie", "session=secret")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(jpegBytes)
		case "/arcgis/rest/services/province/roads_wm/MapServer/tile/8/85/40":
			w.Header().Set("Content-Type", "image/jpeg")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(jpegBytes)
		case "/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/6/0/0":
			http.NotFound(w, r)
		case "/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/6/1/1":
			http.Redirect(w, r, "http://169.254.169.254/latest/meta-data/", http.StatusFound)
		case "/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/6/2/2":
			w.Header().Set("Content-Type", "image/png")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(bytes.Repeat([]byte{'A'}, 1024))
		default:
			w.Header().Set("Content-Type", "text/html")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("<html>unexpected</html>"))
		}
	}))
	defer mapsSrv.Close()

	var lastOpenMapsPath string
	var lastOpenMapsQuery url.Values
	openMapsSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lastOpenMapsPath = r.URL.Path
		lastOpenMapsQuery = r.URL.Query()
		if r.URL.Query().Get("layers") == BCGovWMSLayerHillshadeBW {
			w.Header().Set("Content-Type", "application/vnd.ogc.se_xml")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("<ServiceExceptionReport/>"))
			return
		}
		w.Header().Set("Content-Type", "image/png; charset=binary")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(pngBytes)
	}))
	defer openMapsSrv.Close()

	proxyHandler := newBCGovMapProxyHandler(bcGovProxyConfig{
		mapsBaseURL:     mapsSrv.URL,
		openMapsBaseURL: openMapsSrv.URL,
		client: &http.Client{
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		maxBodyBytes: 512,
	})

	t.Run("basemap tile proxies cleanly and strips sensitive upstream headers", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/basemap/6/21/10", nil)
		rec := httptest.NewRecorder()
		proxyHandler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body=%q)", rec.Code, rec.Body.String())
		}
		if lastMapsReqPath != "/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/6/21/10" {
			t.Fatalf("unexpected upstream path: %q", lastMapsReqPath)
		}
		if got := rec.Header().Get("Content-Type"); got != "image/jpeg" {
			t.Fatalf("Content-Type = %q, want image/jpeg", got)
		}
		if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
			t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
		}
		if rec.Header().Get("Set-Cookie") != "" || rec.Header().Get("Access-Control-Allow-Credentials") != "" {
			t.Fatalf("sensitive upstream headers leaked: %+v", rec.Header())
		}
		if !bytes.Equal(rec.Body.Bytes(), jpegBytes) {
			t.Fatalf("unexpected tile payload")
		}
	})

	t.Run("roads tile proxies cleanly", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/roads/8/85/40", nil)
		rec := httptest.NewRecorder()
		proxyHandler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		if lastMapsReqPath != "/arcgis/rest/services/province/roads_wm/MapServer/tile/8/85/40" {
			t.Fatalf("unexpected roads upstream path: %q", lastMapsReqPath)
		}
	})

	t.Run("OWS WMS reconstructs strict GetMap query and ignores arbitrary params", func(t *testing.T) {
		target := "/maps/bc-proxy/wms/ows?layers=" + url.QueryEscape(BCGovWMSLayerParks) +
			"&bbox=-13775786.98,6261721.35,-13149614.85,6887893.49&width=256&height=256&service=WFS&evil=1"
		req := httptest.NewRequest(http.MethodGet, target, nil)
		rec := httptest.NewRecorder()
		proxyHandler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body=%q)", rec.Code, rec.Body.String())
		}
		if lastOpenMapsPath != "/geo/pub/ows" {
			t.Fatalf("upstream path = %q, want /geo/pub/ows", lastOpenMapsPath)
		}
		if lastOpenMapsQuery.Get("service") != "WMS" || lastOpenMapsQuery.Get("version") != "1.3.0" || lastOpenMapsQuery.Get("crs") != "EPSG:3857" {
			t.Fatalf("unexpected WMS params: %v", lastOpenMapsQuery)
		}
		if lastOpenMapsQuery.Get("evil") != "" {
			t.Fatalf("unlisted query param forwarded: %v", lastOpenMapsQuery)
		}
		if got := rec.Header().Get("Content-Type"); got != "image/png" {
			t.Fatalf("Content-Type = %q, want image/png", got)
		}
		if !bytes.Equal(rec.Body.Bytes(), pngBytes) {
			t.Fatalf("unexpected PNG payload")
		}
	})

	t.Run("ImageX WMS reconstructs strict GetMap query", func(t *testing.T) {
		target := "/maps/bc-proxy/wms/imagex?layers=" + url.QueryEscape(BCGovWMSLayerPaintedRelief) +
			"&bbox=-13775786.98,6261721.35,-13149614.85,6887893.49"
		req := httptest.NewRequest(http.MethodGet, target, nil)
		rec := httptest.NewRecorder()
		proxyHandler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body=%q)", rec.Code, rec.Body.String())
		}
		if lastOpenMapsPath != "/imagex/ecw_wms.dll" {
			t.Fatalf("upstream path = %q, want /imagex/ecw_wms.dll", lastOpenMapsPath)
		}
		if lastOpenMapsQuery.Get("width") != "256" || lastOpenMapsQuery.Get("height") != "256" {
			t.Fatalf("expected default 256x256 dimensions, got %v", lastOpenMapsQuery)
		}
	})

	t.Run("rejects non-GET methods with 405", func(t *testing.T) {
		for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodHead} {
			req := httptest.NewRequest(method, "/maps/bc-proxy/basemap/6/21/10", nil)
			rec := httptest.NewRecorder()
			proxyHandler.ServeHTTP(rec, req)
			if rec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("%s status = %d, want 405", method, rec.Code)
			}
			if rec.Header().Get("Allow") != http.MethodGet {
				t.Fatalf("%s Allow = %q, want GET", method, rec.Header().Get("Allow"))
			}
		}
	})

	t.Run("rejects disallowed layers, invalid bbox, bad tile coords, and unknown routes", func(t *testing.T) {
		badRequests := []struct {
			path string
			want int
		}{
			{"/maps/bc-proxy/", http.StatusNotFound},
			{"/maps/bc-proxy/evil/1/2/3", http.StatusNotFound},
			{"/maps/bc-proxy/basemap/18/0/0", http.StatusBadRequest},
			{"/maps/bc-proxy/basemap/6/64/0", http.StatusBadRequest},
			{"/maps/bc-proxy/basemap/6/21/10/extra", http.StatusBadRequest},
			{"/maps/bc-proxy/basemap/-1/0/0", http.StatusBadRequest},
			{"/maps/bc-proxy/roads/24/0/0", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/ows?layers=pub:WHSE_BASEMAPPING.DRA_DGTL_ROAD_ATLAS_MPAR_SP&bbox=-13775786,6261721,-13149614,6887893", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/imagex?layers=arbitrary_layer&bbox=-13775786,6261721,-13149614,6887893", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/ows?layers=" + url.QueryEscape(BCGovWMSLayerParks) + "&bbox=100,100,50,200", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/ows?layers=" + url.QueryEscape(BCGovWMSLayerParks) + "&bbox=not,a,valid,bbox", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/ows?layers=" + url.QueryEscape(BCGovWMSLayerParks) + "&bbox=-99999999,0,0,100", http.StatusBadRequest},
			{"/maps/bc-proxy/wms/ows?layers=" + url.QueryEscape(BCGovWMSLayerParks) + "&bbox=-13775786,6261721,-13149614,6887893&width=4096", http.StatusBadRequest},
		}
		for _, tc := range badRequests {
			req := httptest.NewRequest(http.MethodGet, tc.path, nil)
			rec := httptest.NewRecorder()
			proxyHandler.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("GET %q status = %d, want %d (body=%q)", tc.path, rec.Code, tc.want, rec.Body.String())
			}
		}
	})

	t.Run("passes through 404, blocks redirects, blocks XML exceptions, and enforces body size cap", func(t *testing.T) {
		// Upstream 404 -> 404
		req404 := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/basemap/6/0/0", nil)
		rec404 := httptest.NewRecorder()
		proxyHandler.ServeHTTP(rec404, req404)
		if rec404.Code != http.StatusNotFound {
			t.Fatalf("upstream 404 -> %d, want 404", rec404.Code)
		}

		// Upstream 302 redirect -> 502 (never follows SSRF redirect)
		reqRedir := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/basemap/6/1/1", nil)
		recRedir := httptest.NewRecorder()
		proxyHandler.ServeHTTP(recRedir, reqRedir)
		if recRedir.Code != http.StatusBadGateway {
			t.Fatalf("upstream redirect -> %d, want 502", recRedir.Code)
		}

		// Upstream XML ServiceExceptionReport -> 502
		reqXML := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/wms/imagex?layers="+BCGovWMSLayerHillshadeBW+"&bbox=-13775786,6261721,-13149614,6887893", nil)
		recXML := httptest.NewRecorder()
		proxyHandler.ServeHTTP(recXML, reqXML)
		if recXML.Code != http.StatusBadGateway || !strings.Contains(recXML.Body.String(), "non-image") {
			t.Fatalf("upstream XML -> %d (%q), want 502 non-image", recXML.Code, recXML.Body.String())
		}

		// Oversized upstream body (> 512 bytes in test config) -> 502
		reqBig := httptest.NewRequest(http.MethodGet, "/maps/bc-proxy/basemap/6/2/2", nil)
		recBig := httptest.NewRecorder()
		proxyHandler.ServeHTTP(recBig, reqBig)
		if recBig.Code != http.StatusBadGateway || !strings.Contains(recBig.Body.String(), "exceeded maximum") {
			t.Fatalf("oversized body -> %d (%q), want 502 size limit", recBig.Code, recBig.Body.String())
		}
	})

	t.Run("PMTiles handler routes /maps/bc-proxy and blocks traversal and HEAD", func(t *testing.T) {
		h := NewPMTilesAssetHandler(nil, "")
		for _, tc := range []struct {
			method string
			path   string
			want   int
		}{
			{http.MethodGet, "/maps/bc-proxy/../Sample.db", http.StatusBadRequest},
			{http.MethodGet, "/maps/bc-proxy/%2e%2e/Sample.db", http.StatusBadRequest},
			{http.MethodHead, "/maps/bc-proxy/basemap/6/21/10", http.StatusMethodNotAllowed},
			{http.MethodPost, "/maps/bc-proxy/basemap/6/21/10", http.StatusMethodNotAllowed},
			{http.MethodGet, "/maps/bc-proxy/unknown", http.StatusNotFound},
		} {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("%s %q -> %d, want %d", tc.method, tc.path, rec.Code, tc.want)
			}
		}
	})
}
