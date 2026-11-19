package spatial

import (
	"context"
	"errors"
	"math"
	"sort"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// FlatGeobufMagicV3 is the canonical 8-byte OGC FlatGeobuf v3.0.1 signature: "fgb\x03fgb\x01".
var FlatGeobufMagicV3 = [8]byte{'f', 'g', 'b', 0x03, 'f', 'g', 'b', 0x01}

const (
	fgbGeometryTypePoint uint8 = 1

	fgbColumnTypeBool   uint8 = 5
	fgbColumnTypeDouble uint8 = 8
	fgbColumnTypeString uint8 = 11
)

// SpatialPlotRecord represents one plottable plot point for FlatGeobuf and GeoArrow serialization.
type SpatialPlotRecord struct {
	PlotNumber        string   `json:"plotNumber"`
	Lat               float64  `json:"lat"`
	Lon               float64  `json:"lon"`
	UTMDerivedLat     *float64 `json:"utmDerivedLat"`
	UTMDerivedLon     *float64 `json:"utmDerivedLon"`
	DivergenceMeters  *float64 `json:"divergenceMeters"`
	DivergenceFlagged bool     `json:"divergenceFlagged"`
	LongitudeFlipped  bool     `json:"longitudeFlipped"`
	Elevation         *float64 `json:"elevation"`
	Slope             *float64 `json:"slope"`
	Aspect            *float64 `json:"aspect"`
	Zone              string   `json:"zone"`
	SubZone           string   `json:"subZone"`
	FieldBGC          string   `json:"fieldBgc"`
	GISBGC            string   `json:"gisBgc"`
	BGCMismatch       bool     `json:"bgcMismatch"`
	SiteUnit          string   `json:"siteUnit"`
	Ecosection        string   `json:"ecosection"`
	FSRegionDistrict  string   `json:"fsRegionDistrict"`
}

// SpatialGeoArrowColumns provides compact columnar SOA arrays for zero-parse WebGPU / Deck.gl transfer.
type SpatialGeoArrowColumns struct {
	Count             int       `json:"count"`
	PlotNumber        []string  `json:"plotNumber"`
	Lon               []float64 `json:"lon"`
	Lat               []float64 `json:"lat"`
	HasUTM            []bool    `json:"hasUtm"`
	UTMDerivedLon     []float64 `json:"utmDerivedLon"`
	UTMDerivedLat     []float64 `json:"utmDerivedLat"`
	DivergenceMeters  []float64 `json:"divergenceMeters"`
	DivergenceFlagged []bool    `json:"divergenceFlagged"`
	LongitudeFlipped  []bool    `json:"longitudeFlipped"`
	HasElevation      []bool    `json:"hasElevation"`
	Elevation         []float64 `json:"elevation"`
	HasSlope          []bool    `json:"hasSlope"`
	Slope             []float64 `json:"slope"`
	HasAspect         []bool    `json:"hasAspect"`
	Aspect            []float64 `json:"aspect"`
	Zone              []string  `json:"zone"`
	SubZone           []string  `json:"subZone"`
	FieldBGC          []string  `json:"fieldBgc"`
	GISBGC            []string  `json:"gisBgc"`
	BGCMismatch       []bool    `json:"bgcMismatch"`
	SiteUnit          []string  `json:"siteUnit"`
	Ecosection        []string  `json:"ecosection"`
	FSRegionDistrict  []string  `json:"fsRegionDistrict"`
}

// SpatialWorkbenchPayload bundles context metadata, PMTiles manifest, and GeoArrow plot columns for GeospatialWorkbench.svelte.
type SpatialWorkbenchPayload struct {
	ContextID          string                 `json:"contextId"`
	Project            string                 `json:"project"`
	ProjectPath        string                 `json:"projectPath"`
	SU                 string                 `json:"su"`
	SUPath             string                 `json:"suPath"`
	TotalPlots         int                    `json:"totalPlots"`
	PlottableCount     int                    `json:"plottableCount"`
	BGCMismatchCount   int                    `json:"bgcMismatchCount"`
	UTMDivergenceCount int                    `json:"utmDivergenceCount"`
	UnsignedLonCount   int                    `json:"unsignedLonCount"`
	BoundingBox        [4]float64             `json:"boundingBox"` // [minLon, minLat, maxLon, maxLat]
	AvailableSUs       []string               `json:"availableSus"`
	SiteUnits          []string               `json:"siteUnits"`
	Manifest           PMTilesManifest        `json:"manifest"`
	GeoArrow           SpatialGeoArrowColumns `json:"geoArrow"`
}

func extractSpatialPlotRecords(ctx context.Context, owner *vprocore.SqliteContext, attr *PMTilesAttributor) ([]SpatialPlotRecord, int, error) {
	return extractSpatialPlotRecordsWithOptions(ctx, owner, attr, true)
}

func extractSpatialPlotRecordsWithOptions(ctx context.Context, owner *vprocore.SqliteContext, attr *PMTilesAttributor, needEcoAndDist bool) ([]SpatialPlotRecord, int, error) {
	rawRows, err := queryScopedSpatialPlotRows(ctx, owner)
	if err != nil {
		return nil, 0, err
	}
	records := make([]SpatialPlotRecord, 0, len(rawRows))
	for _, r := range rawRows {
		if err := ctx.Err(); err != nil {
			return nil, 0, err
		}
		geod := EvaluatePlotGeodesy(PlotGeodesyInput{
			Latitude:         r.latitude,
			Longitude:        r.longitude,
			UTMZone:          r.utmZone,
			UTMEasting:       r.utmEasting,
			UTMNorthing:      r.utmNorthing,
			LocationAccuracy: r.locationAccuracy,
		})
		var lat, lon float64
		hasCoord := false
		if geod.NormalizedLat != nil && geod.NormalizedLon != nil {
			lat, lon = *geod.NormalizedLat, *geod.NormalizedLon
			hasCoord = true
		} else if geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
			lat, lon = *geod.UTMDerivedLat, *geod.UTMDerivedLon
			hasCoord = true
		}
		if !hasCoord || math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) {
			continue
		}
		if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0 {
			continue
		}

		fieldBGC := NormalizeCompactBGCCode(strings.TrimSpace(r.zone) + strings.TrimSpace(r.subZone))
		gisBGC := strings.TrimSpace(r.gisBGC)
		eco := strings.TrimSpace(r.ecosection)
		dist := strings.TrimSpace(r.fsRegionDistrict)
		if (gisBGC == "" || (needEcoAndDist && (eco == "" || dist == ""))) && attr != nil {
			if sug, sErr := attr.SuggestSpatialAttributes(lat, lon); sErr == nil && sug != nil {
				if gisBGC == "" {
					gisBGC = sug.GISBGC
				}
				if eco == "" {
					eco = sug.Ecosection
				}
				if dist == "" {
					dist = sug.FSRegionDistrict
				}
			}
		}
		bgcMismatch := fieldBGC != "" && gisBGC != "" && !strings.EqualFold(fieldBGC, NormalizeCompactBGCCode(gisBGC))

		var elevPtr *float64
		if r.elevation != nil {
			ev := float64(*r.elevation)
			elevPtr = &ev
		}
		var aspPtr *float64
		if r.aspect != nil {
			av := float64(*r.aspect)
			aspPtr = &av
		}

		records = append(records, SpatialPlotRecord{
			PlotNumber:        r.plotNumber,
			Lat:               lat,
			Lon:               lon,
			UTMDerivedLat:     geod.UTMDerivedLat,
			UTMDerivedLon:     geod.UTMDerivedLon,
			DivergenceMeters:  geod.DivergenceMeters,
			DivergenceFlagged: geod.DivergenceFlagged,
			LongitudeFlipped:  geod.LongitudeSignFlipped,
			Elevation:         elevPtr,
			Slope:             r.slope,
			Aspect:            aspPtr,
			Zone:              strings.TrimSpace(r.zone),
			SubZone:           strings.TrimSpace(r.subZone),
			FieldBGC:          fieldBGC,
			GISBGC:            gisBGC,
			BGCMismatch:       bgcMismatch,
			SiteUnit:          strings.TrimSpace(r.siteUnit),
			Ecosection:        eco,
			FSRegionDistrict:  dist,
		})
	}
	return records, len(rawRows), nil
}

func listProjectSUTables(ctx context.Context, owner *vprocore.SqliteContext) ([]string, error) {
	unlock, err := owner.AcquireMutex(ctx)
	if err != nil {
		return nil, err
	}
	defer unlock()
	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	rows, err := tx.QueryContext(ctx, `SELECT name FROM "project".sqlite_master WHERE type='table' AND name LIKE '%\_SU' ESCAPE '\' ORDER BY name COLLATE NOCASE ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var tbl string
		if err := rows.Scan(&tbl); err != nil {
			return nil, err
		}
		if strings.HasSuffix(strings.ToUpper(tbl), "_SU") && len(tbl) > 3 {
			out = append(out, tbl[:len(tbl)-3])
		}
	}
	return out, rows.Err()
}

// GetSpatialWorkbenchPayload builds the columnar GeoArrow plot stream and PMTiles manifest for the active context.
func GetSpatialWorkbenchPayload(ctx context.Context, contexts *vprocore.ContextService, contextID, dataDir string, extraDirs []string, attr *PMTilesAttributor) (*SpatialWorkbenchPayload, error) {
	if ctx == nil {
		return nil, errors.New("spatial workbench requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("spatial context service is unavailable")
	}
	if attr == nil {
		attr = getDefaultPMTilesAttributor()
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*SpatialWorkbenchPayload, error) {
		owner := plots.Projects.Sqlite
		records, totalPlots, err := extractSpatialPlotRecordsWithOptions(ctx, owner, attr, true)
		if err != nil {
			return nil, err
		}
		availSUs, _ := listProjectSUTables(ctx, owner)
		if availSUs == nil {
			availSUs = []string{}
		}

		n := len(records)
		cols := SpatialGeoArrowColumns{
			Count:             n,
			PlotNumber:        make([]string, n),
			Lon:               make([]float64, n),
			Lat:               make([]float64, n),
			HasUTM:            make([]bool, n),
			UTMDerivedLon:     make([]float64, n),
			UTMDerivedLat:     make([]float64, n),
			DivergenceMeters:  make([]float64, n),
			DivergenceFlagged: make([]bool, n),
			LongitudeFlipped:  make([]bool, n),
			HasElevation:      make([]bool, n),
			Elevation:         make([]float64, n),
			HasSlope:          make([]bool, n),
			Slope:             make([]float64, n),
			HasAspect:         make([]bool, n),
			Aspect:            make([]float64, n),
			Zone:              make([]string, n),
			SubZone:           make([]string, n),
			FieldBGC:          make([]string, n),
			GISBGC:            make([]string, n),
			BGCMismatch:       make([]bool, n),
			SiteUnit:          make([]string, n),
			Ecosection:        make([]string, n),
			FSRegionDistrict:  make([]string, n),
		}

		bbox := [4]float64{-139.06, 48.20, -114.05, 60.00}
		if n > 0 {
			bbox = [4]float64{math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)}
		}
		unitSet := make(map[string]struct{})
		var bgcMisCnt, utmDivCnt, flipCnt int

		for i, rec := range records {
			cols.PlotNumber[i] = rec.PlotNumber
			cols.Lon[i] = rec.Lon
			cols.Lat[i] = rec.Lat
			if rec.Lon < bbox[0] {
				bbox[0] = rec.Lon
			}
			if rec.Lat < bbox[1] {
				bbox[1] = rec.Lat
			}
			if rec.Lon > bbox[2] {
				bbox[2] = rec.Lon
			}
			if rec.Lat > bbox[3] {
				bbox[3] = rec.Lat
			}
			if rec.UTMDerivedLon != nil && rec.UTMDerivedLat != nil {
				cols.HasUTM[i] = true
				cols.UTMDerivedLon[i] = *rec.UTMDerivedLon
				cols.UTMDerivedLat[i] = *rec.UTMDerivedLat
			}
			if rec.DivergenceMeters != nil {
				cols.DivergenceMeters[i] = *rec.DivergenceMeters
			}
			cols.DivergenceFlagged[i] = rec.DivergenceFlagged
			if rec.DivergenceFlagged {
				utmDivCnt++
			}
			cols.LongitudeFlipped[i] = rec.LongitudeFlipped
			if rec.LongitudeFlipped {
				flipCnt++
			}
			if rec.Elevation != nil {
				cols.HasElevation[i] = true
				cols.Elevation[i] = *rec.Elevation
			}
			if rec.Slope != nil {
				cols.HasSlope[i] = true
				cols.Slope[i] = *rec.Slope
			}
			if rec.Aspect != nil {
				cols.HasAspect[i] = true
				cols.Aspect[i] = *rec.Aspect
			}
			cols.Zone[i] = rec.Zone
			cols.SubZone[i] = rec.SubZone
			cols.FieldBGC[i] = rec.FieldBGC
			cols.GISBGC[i] = rec.GISBGC
			cols.BGCMismatch[i] = rec.BGCMismatch
			if rec.BGCMismatch {
				bgcMisCnt++
			}
			cols.SiteUnit[i] = rec.SiteUnit
			if rec.SiteUnit != "" {
				unitSet[rec.SiteUnit] = struct{}{}
			}
			cols.Ecosection[i] = rec.Ecosection
			cols.FSRegionDistrict[i] = rec.FSRegionDistrict
		}

		siteUnits := make([]string, 0, len(unitSet))
		for u := range unitSet {
			siteUnits = append(siteUnits, u)
		}
		sort.Strings(siteUnits)

		return &SpatialWorkbenchPayload{
			ContextID:          contextID,
			Project:            owner.Selection.Project,
			ProjectPath:        owner.Selection.ProjectPath,
			SU:                 owner.Selection.SU,
			SUPath:             owner.Selection.SUPath,
			TotalPlots:         totalPlots,
			PlottableCount:     n,
			BGCMismatchCount:   bgcMisCnt,
			UTMDivergenceCount: utmDivCnt,
			UnsignedLonCount:   flipCnt,
			BoundingBox:        bbox,
			AvailableSUs:       availSUs,
			SiteUnits:          siteUnits,
			Manifest:           BuildPMTilesManifest(dataDir, extraDirs...),
			GeoArrow:           cols,
		}, nil
	})
}

// GetSpatialPlotsFlatGeobuf streams all plottable plots in the active context as a binary OGC FlatGeobuf v3 buffer.
func GetSpatialPlotsFlatGeobuf(ctx context.Context, contexts *vprocore.ContextService, contextID string, attributors ...*PMTilesAttributor) ([]byte, error) {
	if ctx == nil {
		return nil, errors.New("FlatGeobuf stream requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("spatial context service is unavailable")
	}
	attr := getDefaultPMTilesAttributor()
	if len(attributors) > 0 && attributors[0] != nil {
		attr = attributors[0]
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) ([]byte, error) {
		owner := plots.Projects.Sqlite
		records, _, err := extractSpatialPlotRecordsWithOptions(ctx, owner, attr, false)
		if err != nil {
			return nil, err
		}
		return EncodeSpatialPlotsFlatGeobuf(owner.Selection.Project+"_Plots", records)
	})
}
