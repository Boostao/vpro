package main

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	defaultWebEnv            = "dev"
	defaultListenAddr        = ":8080"
	defaultInternalAddr      = "127.0.0.1:9090"
	defaultPMTilesDir        = "/pmtiles"
	defaultExportDir         = "/tmp/vpro-exports"
	defaultExportConcurrency = 3
	defaultExportTimeout     = 120 * time.Second
	defaultRConcurrency      = 2
	defaultRTimeout          = 180 * time.Second
	defaultPoolSlots         = 6
	defaultMaxPools          = 16
	defaultCacheMaxMB        = 256
)

// WebConfig captures the complete VPRO_WEB_* environment and flag contract.
type WebConfig struct {
	Env               string
	ListenAddr        string
	InternalAddr      string
	DataDir           string
	DevSample         bool
	PMTilesDir        string
	PMTilesCDNBaseURL string
	PicturesDir       string
	VPicsPath         string
	ExportDir         string
	ExportConcurrency int
	ExportTimeout     time.Duration
	RConcurrency      int
	RTimeout          time.Duration
	PoolSlots         int
	MaxPools          int
	CacheMaxMB        int
	StaticDir         string
}

// LoadWebConfig reads configuration from lookupEnv (defaulting to os.LookupEnv)
// and validates all VPRO_WEB_* environment values.
func LoadWebConfig(lookupEnv func(string) (string, bool), devSample bool) (WebConfig, error) {
	if lookupEnv == nil {
		lookupEnv = os.LookupEnv
	}
	getStr := func(key, fallback string) string {
		if raw, ok := lookupEnv(key); ok {
			if trimmed := strings.TrimSpace(raw); trimmed != "" {
				return trimmed
			}
		}
		return fallback
	}
	getInt := func(key string, fallback, minVal int) (int, error) {
		raw, ok := lookupEnv(key)
		if !ok || strings.TrimSpace(raw) == "" {
			return fallback, nil
		}
		v, err := strconv.Atoi(strings.TrimSpace(raw))
		if err != nil || v < minVal {
			return 0, fmt.Errorf("%s must be an integer >= %d (got %q)", key, minVal, raw)
		}
		return v, nil
	}
	getDuration := func(key string, fallback time.Duration) (time.Duration, error) {
		raw, ok := lookupEnv(key)
		if !ok || strings.TrimSpace(raw) == "" {
			return fallback, nil
		}
		trimmed := strings.TrimSpace(raw)
		if secs, err := strconv.Atoi(trimmed); err == nil {
			if secs <= 0 {
				return 0, fmt.Errorf("%s must be positive (got %q)", key, raw)
			}
			return time.Duration(secs) * time.Second, nil
		}
		d, err := time.ParseDuration(trimmed)
		if err != nil || d <= 0 {
			return 0, fmt.Errorf("%s must be a positive duration (got %q)", key, raw)
		}
		return d, nil
	}

	env := strings.ToLower(getStr("VPRO_WEB_ENV", defaultWebEnv))
	if env != "dev" && env != "prod" {
		return WebConfig{}, fmt.Errorf("VPRO_WEB_ENV must be \"dev\" or \"prod\" (got %q)", env)
	}

	exportConc, err := getInt("VPRO_WEB_EXPORT_CONCURRENCY", defaultExportConcurrency, 1)
	if err != nil {
		return WebConfig{}, err
	}
	exportTimeout, err := getDuration("VPRO_WEB_EXPORT_TIMEOUT", defaultExportTimeout)
	if err != nil {
		return WebConfig{}, err
	}
	rConc, err := getInt("VPRO_WEB_R_CONCURRENCY", defaultRConcurrency, 1)
	if err != nil {
		return WebConfig{}, err
	}
	rTimeout, err := getDuration("VPRO_WEB_R_TIMEOUT", defaultRTimeout)
	if err != nil {
		return WebConfig{}, err
	}
	poolSlots, err := getInt("VPRO_WEB_POOL_SLOTS", defaultPoolSlots, 1)
	if err != nil {
		return WebConfig{}, err
	}
	maxPools, err := getInt("VPRO_WEB_MAX_POOLS", defaultMaxPools, 1)
	if err != nil {
		return WebConfig{}, err
	}
	cacheMaxMB, err := getInt("VPRO_WEB_CACHE_MAX_MB", defaultCacheMaxMB, 0)
	if err != nil {
		return WebConfig{}, err
	}

	cdnBase := strings.TrimRight(getStr("VPRO_WEB_PMTILES_CDN_BASE_URL", ""), "/")
	if cdnBase != "" {
		parsed, err := url.Parse(cdnBase)
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
			return WebConfig{}, fmt.Errorf("VPRO_WEB_PMTILES_CDN_BASE_URL must be an http(s) URL (got %q)", cdnBase)
		}
	}

	exportDir := getStr("VPRO_WEB_EXPORT_DIR", defaultExportDir)
	absExportDir, err := filepath.Abs(exportDir)
	if err != nil {
		return WebConfig{}, fmt.Errorf("resolve VPRO_WEB_EXPORT_DIR: %w", err)
	}

	cfg := WebConfig{
		Env:               env,
		ListenAddr:        getStr("VPRO_WEB_LISTEN_ADDR", defaultListenAddr),
		InternalAddr:      getStr("VPRO_WEB_INTERNAL_ADDR", defaultInternalAddr),
		DataDir:           getStr("VPRO_WEB_DATA_DIR", ""),
		DevSample:         devSample,
		PMTilesDir:        getStr("VPRO_WEB_PMTILES_DIR", defaultPMTilesDir),
		PMTilesCDNBaseURL: cdnBase,
		PicturesDir:       getStr("VPRO_WEB_PICTURES_DIR", ""),
		VPicsPath:         getStr("VPRO_WEB_VPICS_PATH", ""),
		ExportDir:         absExportDir,
		ExportConcurrency: exportConc,
		ExportTimeout:     exportTimeout,
		RConcurrency:      rConc,
		RTimeout:          rTimeout,
		PoolSlots:         poolSlots,
		MaxPools:          maxPools,
		CacheMaxMB:        cacheMaxMB,
		StaticDir:         getStr("VPRO_WEB_STATIC_DIR", ""),
	}

	if cfg.DataDir == "" && !cfg.DevSample {
		return WebConfig{}, fmt.Errorf("VPRO_WEB_DATA_DIR is required unless --dev-sample is enabled")
	}

	return cfg, nil
}
