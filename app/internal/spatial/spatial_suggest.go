package spatial

import (
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/resources"
	"math"
	"strings"
	"sync"
)

// ZoneElevationBounds returns BEC v13 / LMH25 expected elevation bounds (m) for BC biogeoclimatic zones.
func ZoneElevationBounds(zone string) (minM, maxM int, ok bool) {
	switch strings.ToUpper(strings.TrimSpace(zone)) {
	case "CDF":
		return 0, 350, true
	case "CWH":
		return 0, 1250, true
	case "MH":
		return 500, 1950, true
	case "CMA", "IMA", "BAFA":
		return 850, 3400, true
	case "BG":
		return 180, 1050, true
	case "PP":
		return 220, 1150, true
	case "IDF":
		return 250, 1650, true
	case "ICH":
		return 300, 1750, true
	case "MS":
		return 1050, 1900, true
	case "SBPS":
		return 800, 1550, true
	case "SBS":
		return 420, 1500, true
	case "BWBS":
		return 180, 1400, true
	case "SWB":
		return 800, 1850, true
	case "ESSF":
		return 850, 2500, true
	default:
		return 0, 0, false
	}
}

// NormalizeCompactBGCCode strips spaces to compare field Zone+SubZone (e.g. "SBSmk1") with GIS_BGC ("SBS mk 1" or "SBSmk1").
func NormalizeCompactBGCCode(raw string) string {
	var b strings.Builder
	for _, r := range strings.TrimSpace(raw) {
		if r != ' ' && r != '\t' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func stringProp(props map[string]any, key string) string {
	if props == nil {
		return ""
	}
	v, ok := props[key]
	if !ok || v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return strings.TrimSpace(s)
	}
	return strings.TrimSpace(fmt.Sprint(v))
}

// SpatialAttributeSuggestion holds the complete Auto-1 coordinate-driven geodetic, BGC v13, administrative, and terrain result.
type SpatialAttributeSuggestion struct {
	NormalizedLat          float64  `json:"normalizedLat"`
	NormalizedLon          float64  `json:"normalizedLon"`
	LongitudeSignFlipped   bool     `json:"longitudeSignFlipped"`
	UTMZone                int      `json:"utmZone"`
	UTMEasting             float64  `json:"utmEasting"`
	UTMNorthing            float64  `json:"utmNorthing"`
	NtsMapSheet            string   `json:"ntsMapSheet"`
	GISBGC                 string   `json:"gisBgc"`
	GISBGCVer              int      `json:"gisBgcVer"`
	BGCLabel               string   `json:"bgcLabel"`
	MapLabel               string   `json:"mapLabel"`
	Zone                   string   `json:"zone"`
	SubZone                string   `json:"subZone"`
	Variant                string   `json:"variant"`
	Phase                  string   `json:"phase"`
	VProSubZone            string   `json:"vproSubZone"`
	ZoneName               string   `json:"zoneName"`
	BGCZoom                int      `json:"bgcZoom"`
	BGCSource              string   `json:"bgcSource"`
	Ecosection             string   `json:"ecosection"`
	EcosectionName         string   `json:"ecosectionName"`
	ParentEcoregion        string   `json:"parentEcoregion"`
	FSRegionDistrict       string   `json:"fsRegionDistrict"`
	DistrictName           string   `json:"districtName"`
	RegionOrgUnit          string   `json:"regionOrgUnit"`
	OrgUnit                string   `json:"orgUnit"`
	AdminZoom              int      `json:"adminZoom"`
	AdminSource            string   `json:"adminSource"`
	ProvinceStateTerritory string   `json:"provinceStateTerritory"`
	ExpectedElevationMinM  *int     `json:"expectedElevationMinM"`
	ExpectedElevationMaxM  *int     `json:"expectedElevationMaxM"`
	ExpectedSlopeRangePct  string   `json:"expectedSlopeRangePct"`
	ExpectedAspectRangeDeg string   `json:"expectedAspectRangeDeg"`
	TerrainSanityNote      string   `json:"terrainSanityNote"`
	Diagnostics            []string `json:"diagnostics"`
}

// PMTilesAttributor manages cached PMTiles v3 readers for BGC v13, Admin boundaries, and embedded overview fallback.
type PMTilesAttributor struct {
	dataDir   string
	extraDirs []string

	mu       sync.Mutex
	loaded   bool
	bgcRdr   *pmtilesReader
	adminRdr *pmtilesReader
	ovwRdr   *pmtilesReader
}

// NewPMTilesAttributor constructs a cached spatial attributor searching <dataDir>/maps, extraDirs, and embedded overview.
func NewPMTilesAttributor(dataDir string, extraDirs ...string) *PMTilesAttributor {
	return &PMTilesAttributor{
		dataDir:   dataDir,
		extraDirs: append([]string(nil), extraDirs...),
	}
}

func (a *PMTilesAttributor) Close() error {
	if a == nil {
		return nil
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	var err error
	if a.bgcRdr != nil {
		err = errors.Join(err, a.bgcRdr.Close())
		a.bgcRdr = nil
	}
	if a.adminRdr != nil {
		err = errors.Join(err, a.adminRdr.Close())
		a.adminRdr = nil
	}
	if a.ovwRdr != nil {
		err = errors.Join(err, a.ovwRdr.Close())
		a.ovwRdr = nil
	}
	a.loaded = false
	return err
}

func (a *PMTilesAttributor) ensureLoaded() error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.ovwRdr == nil && len(resources.BCOverviewPMTiles) >= 127 {
		if rdr, err := openPMTilesReaderFromBytes("embedded:bc-overview.pmtiles", resources.BCOverviewPMTiles); err == nil {
			a.ovwRdr = rdr
		}
	}
	if a.bgcRdr == nil {
		if resolved, ok := resolvePMTilesArchive(PMTilesBGCArchiveName, a.dataDir, a.extraDirs); ok && resolved.filePath != "" {
			if rdr, err := openPMTilesReaderFromFile(resolved.filePath); err == nil {
				a.bgcRdr = rdr
			}
		}
	}
	if a.adminRdr == nil {
		if resolved, ok := resolvePMTilesArchive(PMTilesAdminArchiveName, a.dataDir, a.extraDirs); ok && resolved.filePath != "" {
			if rdr, err := openPMTilesReaderFromFile(resolved.filePath); err == nil {
				a.adminRdr = rdr
			}
		}
	}
	a.loaded = a.ovwRdr != nil || a.bgcRdr != nil || a.adminRdr != nil
	return nil
}

// SuggestSpatialAttributes intersects (lat, lon) against local PMTiles v3 archives and projects NAD83 UTM + BCGS map sheet.
func (a *PMTilesAttributor) SuggestSpatialAttributes(lat, lon float64) (*SpatialAttributeSuggestion, error) {
	if math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) {
		return nil, errors.New("latitude and longitude must be finite numbers")
	}
	normLat, normLon, flipped, inBounds := NormalizeBCWesternCoordinates(lat, lon)
	if normLat < -90.0 || normLat > 90.0 || normLon < -180.0 || normLon > 180.0 {
		return nil, fmt.Errorf("coordinates (%.6f, %.6f) are out of geographic range", lat, lon)
	}
	if err := a.ensureLoaded(); err != nil {
		return nil, err
	}

	out := &SpatialAttributeSuggestion{
		NormalizedLat:          normLat,
		NormalizedLon:          normLon,
		LongitudeSignFlipped:   flipped,
		NtsMapSheet:            ComputeBCGSMapSheet(normLat, normLon),
		GISBGCVer:              CurrentBECGISVersion,
		ExpectedSlopeRangePct:  "0–120%",
		ExpectedAspectRangeDeg: "0–359 deg (999 level)",
		Diagnostics:            []string{},
	}
	if flipped {
		out.Diagnostics = append(out.Diagnostics, fmt.Sprintf("Normalized positive West longitude %.5f to %.5f", lon, normLon))
	}
	if !inBounds {
		out.Diagnostics = append(out.Diagnostics, "Coordinates lie outside standard BC / Canadian North bounds")
	}
	if z, e, n, err := ProjectNAD83LatLonToUTM(normLat, normLon); err == nil {
		out.UTMZone = z
		out.UTMEasting = e
		out.UTMNorthing = n
	}

	// 1. BGC v13 lookup (full-res z=10 first, then embedded overview z=6 fallback)
	var bgcProps map[string]any
	if a.bgcRdr != nil {
		if p, z, hit, err := queryLayerAtLatLon(a.bgcRdr, "bgc", normLat, normLon); err == nil && hit {
			bgcProps = p
			out.BGCZoom = z
			out.BGCSource = PMTilesBGCArchiveName
		}
	}
	if bgcProps == nil && a.ovwRdr != nil {
		if p, z, hit, err := queryLayerAtLatLon(a.ovwRdr, "bgc", normLat, normLon); err == nil && hit {
			bgcProps = p
			out.BGCZoom = z
			out.BGCSource = PMTilesOverviewArchiveName
		}
	}
	if bgcProps != nil {
		out.BGCLabel = stringProp(bgcProps, "BGC_LABEL")
		out.MapLabel = stringProp(bgcProps, "MAP_LABEL")
		out.Zone = stringProp(bgcProps, "ZONE")
		out.SubZone = stringProp(bgcProps, "SUBZONE")
		out.Variant = stringProp(bgcProps, "VARIANT")
		out.Phase = stringProp(bgcProps, "PHASE")
		out.ZoneName = stringProp(bgcProps, "ZONE_NAME")
		out.VProSubZone = out.SubZone + out.Variant + out.Phase
		if out.MapLabel != "" {
			out.GISBGC = out.MapLabel
		} else {
			out.GISBGC = NormalizeCompactBGCCode(out.BGCLabel)
		}
		out.ProvinceStateTerritory = "BC"
		if minM, maxM, ok := ZoneElevationBounds(out.Zone); ok {
			out.ExpectedElevationMinM = &minM
			out.ExpectedElevationMaxM = &maxM
			out.TerrainSanityNote = fmt.Sprintf("BEC %s (%s) expected elevation envelope: %d–%d m", out.GISBGC, out.ZoneName, minM, maxM)
		}
	}

	// 2. Ecosections & NR Districts lookup (full-res z=10 first, then embedded overview z=6 fallback)
	var ecoProps, distProps map[string]any
	if a.adminRdr != nil {
		if p, z, hit, err := queryLayerAtLatLon(a.adminRdr, "ecosections", normLat, normLon); err == nil && hit {
			ecoProps = p
			out.AdminZoom = z
			out.AdminSource = PMTilesAdminArchiveName
		}
		if p, z, hit, err := queryLayerAtLatLon(a.adminRdr, "nr_districts", normLat, normLon); err == nil && hit {
			distProps = p
			if out.AdminZoom == 0 {
				out.AdminZoom = z
				out.AdminSource = PMTilesAdminArchiveName
			}
		}
	}
	if ecoProps == nil && a.ovwRdr != nil {
		if p, z, hit, err := queryLayerAtLatLon(a.ovwRdr, "ecosections", normLat, normLon); err == nil && hit {
			ecoProps = p
			if out.AdminZoom == 0 {
				out.AdminZoom = z
				out.AdminSource = PMTilesOverviewArchiveName
			}
		}
	}
	if distProps == nil && a.ovwRdr != nil {
		if p, z, hit, err := queryLayerAtLatLon(a.ovwRdr, "nr_districts", normLat, normLon); err == nil && hit {
			distProps = p
			if out.AdminZoom == 0 {
				out.AdminZoom = z
				out.AdminSource = PMTilesOverviewArchiveName
			}
		}
	}
	if ecoProps != nil {
		out.Ecosection = stringProp(ecoProps, "ECOSECTION_CODE")
		out.EcosectionName = stringProp(ecoProps, "ECOSECTION_NAME")
		out.ParentEcoregion = stringProp(ecoProps, "PARENT_ECOREGION_CODE")
		if out.ProvinceStateTerritory == "" {
			out.ProvinceStateTerritory = "BC"
		}
	}
	if distProps != nil {
		out.OrgUnit = stringProp(distProps, "ORG_UNIT")
		out.RegionOrgUnit = stringProp(distProps, "REGION_ORG_UNIT")
		out.DistrictName = stringProp(distProps, "DISTRICT_NAME")
		if out.DistrictName == "" {
			out.DistrictName = stringProp(distProps, "ORG_UNIT_NAME")
		}
		if out.RegionOrgUnit != "" && out.OrgUnit != "" {
			out.FSRegionDistrict = out.RegionOrgUnit + "." + out.OrgUnit
		}
		if out.ProvinceStateTerritory == "" {
			out.ProvinceStateTerritory = "BC"
		}
	}

	return out, nil
}

var (
	defaultAttributorOnce sync.Once
	defaultAttributorInst *PMTilesAttributor
)

func getDefaultPMTilesAttributor() *PMTilesAttributor {
	defaultAttributorOnce.Do(func() {
		dataDir, _ := sqlutil.UserDataDir()
		defaultAttributorInst = NewPMTilesAttributor(dataDir, ResolveSpatialExtraDirs()...)
	})
	return defaultAttributorInst
}

// SuggestSpatialAttributes is the package-level Auto-1 attribution entry point using default spatial asset paths.
func SuggestSpatialAttributes(lat, lon float64) (*SpatialAttributeSuggestion, error) {
	return getDefaultPMTilesAttributor().SuggestSpatialAttributes(lat, lon)
}
