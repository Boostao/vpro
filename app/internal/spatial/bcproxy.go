package spatial

import (
	"context"
	"fmt"
	"io"
	"math"
	"mime"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	bcGovMapsHostBase      = "https://maps.gov.bc.ca"
	bcGovOpenMapsHostBase  = "https://openmaps.gov.bc.ca"
	bcGovProxyTimeout      = 15 * time.Second
	bcGovProxyMaxBodyBytes = 8 * 1024 * 1024 // 8 MiB per tile/WMS image
	bcGovProxyUserAgent    = "VPro/2.0 (BC Ministry of Forests BEC Desktop)"
	bcGovWebMercatorMax    = 20037509.0
)

const (
	BCGovWMSLayerParks         = "pub:WHSE_TANTALIS.TA_PARK_ECORES_PA_SVW"
	BCGovWMSLayerPaintedRelief = "hillshade_bc_bc_xc50m_bcalb_painted_relief"
	BCGovWMSLayerOrtho10m      = "bc_bc_bc_xc10m_bcalb_20070115"
	BCGovWMSLayerHillshadeBW   = "hillshade_bc_bcalb_hillshade_bw_315"
)

var bcGovAllowedOWSLayers = map[string]struct{}{
	BCGovWMSLayerParks: {},
}

var bcGovAllowedImageXLayers = map[string]struct{}{
	BCGovWMSLayerPaintedRelief: {},
	BCGovWMSLayerOrtho10m:      {},
	BCGovWMSLayerHillshadeBW:   {},
}

var bcGovAllowedImageMIME = map[string]string{
	"image/png":  "image/png",
	"image/jpeg": "image/jpeg",
	"image/jpg":  "image/jpeg",
	"image/webp": "image/webp",
}

type bcGovProxyConfig struct {
	mapsBaseURL     string
	openMapsBaseURL string
	client          *http.Client
	maxBodyBytes    int64
}

var defaultBCGovHTTPClient = &http.Client{
	Timeout: bcGovProxyTimeout,
	CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

func defaultBCGovProxyConfig() bcGovProxyConfig {
	return bcGovProxyConfig{
		mapsBaseURL:     bcGovMapsHostBase,
		openMapsBaseURL: bcGovOpenMapsHostBase,
		client:          defaultBCGovHTTPClient,
		maxBodyBytes:    bcGovProxyMaxBodyBytes,
	}
}

func parseStrictTileInt(raw string) (int, bool) {
	if raw == "" || len(raw) > 10 {
		return 0, false
	}
	for i := 0; i < len(raw); i++ {
		if raw[i] < '0' || raw[i] > '9' {
			return 0, false
		}
	}
	val, err := strconv.Atoi(raw)
	if err != nil || val < 0 {
		return 0, false
	}
	return val, true
}

func parseXYZTilePath(rest string, maxZoom int) (z, y, x int, ok bool) {
	parts := strings.Split(rest, "/")
	if len(parts) != 3 {
		return 0, 0, 0, false
	}
	z, ok = parseStrictTileInt(parts[0])
	if !ok || z > maxZoom {
		return 0, 0, 0, false
	}
	y, ok = parseStrictTileInt(parts[1])
	if !ok {
		return 0, 0, 0, false
	}
	x, ok = parseStrictTileInt(parts[2])
	if !ok {
		return 0, 0, 0, false
	}
	limit := 1 << z
	if y >= limit || x >= limit {
		return 0, 0, 0, false
	}
	return z, y, x, true
}

func parseStrictWMSBBox(raw string) (string, bool) {
	parts := strings.Split(strings.TrimSpace(raw), ",")
	if len(parts) != 4 {
		return "", false
	}
	var vals [4]float64
	for i, p := range parts {
		v, err := strconv.ParseFloat(strings.TrimSpace(p), 64)
		if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
			return "", false
		}
		if v < -bcGovWebMercatorMax || v > bcGovWebMercatorMax {
			return "", false
		}
		vals[i] = v
	}
	if vals[0] >= vals[2] || vals[1] >= vals[3] {
		return "", false
	}
	return fmt.Sprintf("%.6f,%.6f,%.6f,%.6f", vals[0], vals[1], vals[2], vals[3]), true
}

func parseWMSDimension(raw string, fallback int) (int, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return fallback, true
	}
	v, ok := parseStrictTileInt(trimmed)
	if !ok || v < 64 || v > 1024 {
		return 0, false
	}
	return v, true
}

func resolveBCGovProxyUpstreamURL(r *http.Request, cfg bcGovProxyConfig) (upstreamURL string, statusCode int, errMsg string) {
	rel := strings.TrimPrefix(r.URL.Path, "/maps/bc-proxy/")
	if rel == r.URL.Path || rel == "" {
		return "", http.StatusNotFound, "unknown BC Gov map proxy route"
	}

	mapsBase := strings.TrimRight(cfg.mapsBaseURL, "/")
	openMapsBase := strings.TrimRight(cfg.openMapsBaseURL, "/")

	switch {
	case strings.HasPrefix(rel, "basemap/"):
		z, y, x, ok := parseXYZTilePath(strings.TrimPrefix(rel, "basemap/"), 17)
		if !ok {
			return "", http.StatusBadRequest, "invalid BC Gov basemap tile coordinates"
		}
		return fmt.Sprintf("%s/arcgis/rest/services/province/web_mercator_cache/MapServer/tile/%d/%d/%d", mapsBase, z, y, x), 0, ""

	case strings.HasPrefix(rel, "roads/"):
		z, y, x, ok := parseXYZTilePath(strings.TrimPrefix(rel, "roads/"), 23)
		if !ok {
			return "", http.StatusBadRequest, "invalid BC Gov roads tile coordinates"
		}
		return fmt.Sprintf("%s/arcgis/rest/services/province/roads_wm/MapServer/tile/%d/%d/%d", mapsBase, z, y, x), 0, ""

	case rel == "wms/ows" || rel == "wms/imagex":
		q := r.URL.Query()
		layer := strings.TrimSpace(q.Get("layers"))
		if rel == "wms/ows" {
			if _, ok := bcGovAllowedOWSLayers[layer]; !ok {
				return "", http.StatusBadRequest, "disallowed BC OpenMaps OWS layer"
			}
		} else {
			if _, ok := bcGovAllowedImageXLayers[layer]; !ok {
				return "", http.StatusBadRequest, "disallowed BC OpenMaps ImageX layer"
			}
		}
		bbox, ok := parseStrictWMSBBox(q.Get("bbox"))
		if !ok {
			return "", http.StatusBadRequest, "invalid WMS EPSG:3857 bbox"
		}
		width, ok := parseWMSDimension(q.Get("width"), 256)
		if !ok {
			return "", http.StatusBadRequest, "invalid WMS tile width"
		}
		height, ok := parseWMSDimension(q.Get("height"), 256)
		if !ok {
			return "", http.StatusBadRequest, "invalid WMS tile height"
		}
		params := url.Values{}
		params.Set("service", "WMS")
		params.Set("version", "1.3.0")
		params.Set("request", "GetMap")
		params.Set("layers", layer)
		params.Set("styles", "")
		params.Set("crs", "EPSG:3857")
		params.Set("bbox", bbox)
		params.Set("width", strconv.Itoa(width))
		params.Set("height", strconv.Itoa(height))
		params.Set("format", "image/png")
		params.Set("transparent", "true")

		if rel == "wms/ows" {
			return openMapsBase + "/geo/pub/ows?" + params.Encode(), 0, ""
		}
		return openMapsBase + "/imagex/ecw_wms.dll?" + params.Encode(), 0, ""

	default:
		return "", http.StatusNotFound, "unknown BC Gov map proxy route"
	}
}

func serveBCGovMapProxy(w http.ResponseWriter, r *http.Request, cfg bcGovProxyConfig) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	upstreamURL, errStatus, errMsg := resolveBCGovProxyUpstreamURL(r, cfg)
	if errStatus != 0 {
		http.Error(w, errMsg, errStatus)
		return
	}

	client := cfg.client
	if client == nil {
		client = defaultBCGovHTTPClient
	}
	maxBytes := cfg.maxBodyBytes
	if maxBytes <= 0 {
		maxBytes = bcGovProxyMaxBodyBytes
	}

	ctx, cancel := context.WithTimeout(r.Context(), bcGovProxyTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, upstreamURL, nil)
	if err != nil {
		http.Error(w, "failed to construct upstream request", http.StatusInternalServerError)
		return
	}
	req.Header.Set("User-Agent", bcGovProxyUserAgent)
	req.Header.Set("Accept", "image/png,image/jpeg,image/webp,*/*;q=0.1")

	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "upstream BC Gov map service unreachable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		http.NotFound(w, r)
		return
	}
	if resp.StatusCode != http.StatusOK {
		http.Error(w, fmt.Sprintf("upstream BC Gov map service returned HTTP %d", resp.StatusCode), http.StatusBadGateway)
		return
	}

	mediaType, _, err := mime.ParseMediaType(resp.Header.Get("Content-Type"))
	if err != nil {
		http.Error(w, "upstream returned invalid content type", http.StatusBadGateway)
		return
	}
	safeMIME, allowed := bcGovAllowedImageMIME[strings.ToLower(mediaType)]
	if !allowed {
		http.Error(w, "upstream returned non-image response", http.StatusBadGateway)
		return
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		http.Error(w, "failed reading upstream map tile", http.StatusBadGateway)
		return
	}
	if int64(len(body)) > maxBytes {
		http.Error(w, "upstream map tile exceeded maximum allowed size", http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", safeMIME)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

func newBCGovMapProxyHandler(cfg bcGovProxyConfig) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		serveBCGovMapProxy(w, r, cfg)
	})
}
