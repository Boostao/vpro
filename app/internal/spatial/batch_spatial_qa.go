package spatial

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"math"
	"strings"
)

// --- Batch Spatial QA Audit & Transactional Auto-1 Stamp ---

type SpatialPlotQARow struct {
	PlotNumber                string   `json:"plotNumber"`
	SiteUnit                  string   `json:"siteUnit"`
	Zone                      string   `json:"zone"`
	SubZone                   string   `json:"subZone"`
	FieldBGC                  string   `json:"fieldBgc"`
	StoredGISBGC              string   `json:"storedGisBgc"`
	StoredGISBGCVer           *int     `json:"storedGisBgcVer"`
	SuggestedGISBGC           string   `json:"suggestedGisBgc"`
	SuggestedBGCLabel         string   `json:"suggestedBgcLabel"`
	BGCMismatch               bool     `json:"bgcMismatch"`
	StoredEcosection          string   `json:"storedEcosection"`
	SuggestedEcosection       string   `json:"suggestedEcosection"`
	StoredFSRegionDistrict    string   `json:"storedFsRegionDistrict"`
	SuggestedFSRegionDistrict string   `json:"suggestedFsRegionDistrict"`
	StoredNtsMapSheet         string   `json:"storedNtsMapSheet"`
	SuggestedNtsMapSheet      string   `json:"suggestedNtsMapSheet"`
	Latitude                  *float64 `json:"latitude"`
	Longitude                 *float64 `json:"longitude"`
	NormalizedLat             *float64 `json:"normalizedLat"`
	NormalizedLon             *float64 `json:"normalizedLon"`
	LongitudeSignFlipped      bool     `json:"longitudeSignFlipped"`
	UTMZone                   *string  `json:"utmZone"`
	UTMEasting                *float64 `json:"utmEasting"`
	UTMNorthing               *float64 `json:"utmNorthing"`
	ComputedUTMZone           *int     `json:"computedUtmZone"`
	ComputedUTMEasting        *float64 `json:"computedUtmEasting"`
	ComputedUTMNorthing       *float64 `json:"computedUtmNorthing"`
	UTMDerivedLat             *float64 `json:"utmDerivedLat"`
	UTMDerivedLon             *float64 `json:"utmDerivedLon"`
	DivergenceMeters          *float64 `json:"divergenceMeters"`
	DivergenceFlagged         bool     `json:"divergenceFlagged"`
	Elevation                 *int     `json:"elevation"`
	ExpectedElevationMinM     *int     `json:"expectedElevationMinM"`
	ExpectedElevationMaxM     *int     `json:"expectedElevationMaxM"`
	ElevationFlagged          bool     `json:"elevationFlagged"`
	Diagnostics               []string `json:"diagnostics"`
}

type SpatialBatchAuditReport struct {
	ContextID           string             `json:"contextId"`
	Project             string             `json:"project"`
	SU                  string             `json:"su"`
	TotalPlots          int                `json:"totalPlots"`
	CoordinatizedPlots  int                `json:"coordinatizedPlots"`
	UnsignedLonCount    int                `json:"unsignedLonCount"`
	UTMDivergenceCount  int                `json:"utmDivergenceCount"`
	BGCMismatchCount    int                `json:"bgcMismatchCount"`
	MissingGISBGCCount  int                `json:"missingGisBgcCount"`
	ElevationIssueCount int                `json:"elevationIssueCount"`
	Rows                []SpatialPlotQARow `json:"rows"`
}

type ApplySpatialAttributesRequest struct {
	PlotNumbers            []string `json:"plotNumbers"`
	AllScopedPlots         bool     `json:"allScopedPlots"`
	StampGISBGC            bool     `json:"stampGisBgc"`
	StampAdminFields       bool     `json:"stampAdminFields"`
	OnlyWhenBlank          bool     `json:"onlyWhenBlank"`
	NormalizeLongitudeSign bool     `json:"normalizeLongitudeSign"`
	SyncUTMFromLatLon      bool     `json:"syncUtmFromLatLon"`
	SyncLatLonFromUTM      bool     `json:"syncLatLonFromUtm"`
}

func (r *ApplySpatialAttributesRequest) UnmarshalJSON(data []byte) error {
	type plain ApplySpatialAttributesRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type ApplySpatialAttributesResult struct {
	ContextID    string `json:"contextId"`
	Project      string `json:"project"`
	UpdatedPlots int    `json:"updatedPlots"`
	UpdatedCells int    `json:"updatedCells"`
	AuditRows    int    `json:"auditRows"`
}

type rawSpatialPlotRow struct {
	plotNumber       string
	siteUnit         string
	zone             string
	subZone          string
	ecosection       string
	fsRegionDistrict string
	ntsMapSheet      string
	latitude         *float64
	longitude        *float64
	utmZone          *string
	utmEasting       *float64
	utmNorthing      *float64
	locationAccuracy *int
	elevation        *int
	slope            *float64
	aspect           *int
	gisBGC           string
	gisBGCVer        *int
	province         string
}

func queryScopedSpatialPlotRows(ctx context.Context, owner *vprocore.SqliteContext) ([]rawSpatialPlotRow, error) {
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

	project := owner.Selection.Project
	qEnv := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	qAdmin := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	type adminInfo struct {
		gisBGC   string
		gisVer   sql.NullInt64
		province string
	}
	adminByPlot := make(map[string]adminInfo)
	adminRows, aErr := tx.QueryContext(ctx, `SELECT
		CAST("Plot" AS TEXT),
		COALESCE(CAST("GIS_BGC" AS TEXT), ''),
		"GIS_BGC_VER",
		COALESCE(CAST("ProvinceStateTerritory" AS TEXT), '')
	FROM `+qAdmin+` WHERE typeof("Plot")='text'`)
	if aErr == nil {
		for adminRows.Next() {
			var pKey string
			var info adminInfo
			if sErr := adminRows.Scan(&pKey, &info.gisBGC, &info.gisVer, &info.province); sErr == nil {
				if _, exists := adminByPlot[pKey]; !exists {
					adminByPlot[pKey] = info
				}
			}
		}
		_ = adminRows.Close()
	}

	hasActiveSU := owner.Selection.SU != "" && owner.Selection.SU != "None"
	var suByPlot map[string]string
	if hasActiveSU {
		suByPlot = make(map[string]string)
		qSU := `"su".` + vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU")
		suRows, sErr := tx.QueryContext(ctx, `SELECT
			CAST("PlotNumber" AS TEXT),
			COALESCE(CAST("SiteUnit" AS TEXT), '')
		FROM `+qSU+` WHERE typeof("PlotNumber")='text'`)
		if sErr != nil {
			return nil, sErr
		}
		for suRows.Next() {
			var pKey, suVal string
			if err := suRows.Scan(&pKey, &suVal); err != nil {
				_ = suRows.Close()
				return nil, err
			}
			if _, exists := suByPlot[pKey]; !exists {
				suByPlot[pKey] = suVal
			}
		}
		if err := suRows.Err(); err != nil {
			_ = suRows.Close()
			return nil, err
		}
		_ = suRows.Close()
	}

	query := `SELECT
		CAST(env."PlotNumber" AS TEXT),
		COALESCE(CAST(env."Zone" AS TEXT), ''),
		COALESCE(CAST(env."SubZone" AS TEXT), ''),
		COALESCE(CAST(env."Ecosection" AS TEXT), ''),
		COALESCE(CAST(env."FSRegionDistrict" AS TEXT), ''),
		COALESCE(CAST(env."NtsMapSheet" AS TEXT), ''),
		env."Latitude",
		env."Longitude",
		CAST(env."UTMZone" AS TEXT),
		env."UTMEasting",
		env."UTMNorthing",
		env."LocationAccuracy",
		env."Elevation",
		env."SlopeGradient",
		env."Aspect"
	FROM ` + qEnv + ` AS env
	WHERE typeof(env."PlotNumber")='text' AND TRIM(CAST(env."PlotNumber" AS TEXT)) <> ''
	ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`

	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []rawSpatialPlotRow
	seen := make(map[string]bool)
	for rows.Next() {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		var r rawSpatialPlotRow
		var lat, lon, east, north, slope sql.NullFloat64
		var utmZ sql.NullString
		var acc, elev, aspect sql.NullInt64
		if err := rows.Scan(
			&r.plotNumber,
			&r.zone,
			&r.subZone,
			&r.ecosection,
			&r.fsRegionDistrict,
			&r.ntsMapSheet,
			&lat, &lon, &utmZ, &east, &north, &acc, &elev, &slope, &aspect,
		); err != nil {
			return nil, err
		}
		if hasActiveSU {
			suVal, inSU := suByPlot[r.plotNumber]
			if !inSU {
				continue
			}
			r.siteUnit = suVal
		}
		if seen[r.plotNumber] {
			continue
		}
		seen[r.plotNumber] = true
		adm := adminByPlot[r.plotNumber]
		r.gisBGC = adm.gisBGC
		gisVer := adm.gisVer
		r.province = adm.province
		if lat.Valid && !math.IsNaN(lat.Float64) && !math.IsInf(lat.Float64, 0) {
			v := lat.Float64
			r.latitude = &v
		}
		if lon.Valid && !math.IsNaN(lon.Float64) && !math.IsInf(lon.Float64, 0) {
			v := lon.Float64
			r.longitude = &v
		}
		if utmZ.Valid && strings.TrimSpace(utmZ.String) != "" {
			v := strings.TrimSpace(utmZ.String)
			r.utmZone = &v
		}
		if east.Valid && !math.IsNaN(east.Float64) && !math.IsInf(east.Float64, 0) {
			v := east.Float64
			r.utmEasting = &v
		}
		if north.Valid && !math.IsNaN(north.Float64) && !math.IsInf(north.Float64, 0) {
			v := north.Float64
			r.utmNorthing = &v
		}
		if acc.Valid {
			v := int(acc.Int64)
			r.locationAccuracy = &v
		}
		if elev.Valid {
			v := int(elev.Int64)
			r.elevation = &v
		}
		if slope.Valid && !math.IsNaN(slope.Float64) && !math.IsInf(slope.Float64, 0) {
			v := slope.Float64
			r.slope = &v
		}
		if aspect.Valid {
			v := int(aspect.Int64)
			r.aspect = &v
		}
		if gisVer.Valid {
			v := int(gisVer.Int64)
			r.gisBGCVer = &v
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

func buildPlotQARow(r rawSpatialPlotRow, attr *PMTilesAttributor) SpatialPlotQARow {
	geod := EvaluatePlotGeodesy(PlotGeodesyInput{
		Latitude:         r.latitude,
		Longitude:        r.longitude,
		UTMZone:          r.utmZone,
		UTMEasting:       r.utmEasting,
		UTMNorthing:      r.utmNorthing,
		LocationAccuracy: r.locationAccuracy,
	})
	fieldBGC := NormalizeCompactBGCCode(strings.TrimSpace(r.zone) + strings.TrimSpace(r.subZone))
	qa := SpatialPlotQARow{
		PlotNumber:             r.plotNumber,
		SiteUnit:               r.siteUnit,
		Zone:                   strings.TrimSpace(r.zone),
		SubZone:                strings.TrimSpace(r.subZone),
		FieldBGC:               fieldBGC,
		StoredGISBGC:           strings.TrimSpace(r.gisBGC),
		StoredGISBGCVer:        r.gisBGCVer,
		StoredEcosection:       strings.TrimSpace(r.ecosection),
		StoredFSRegionDistrict: strings.TrimSpace(r.fsRegionDistrict),
		StoredNtsMapSheet:      strings.TrimSpace(r.ntsMapSheet),
		Latitude:               r.latitude,
		Longitude:              r.longitude,
		NormalizedLat:          geod.NormalizedLat,
		NormalizedLon:          geod.NormalizedLon,
		LongitudeSignFlipped:   geod.LongitudeSignFlipped,
		UTMZone:                r.utmZone,
		UTMEasting:             r.utmEasting,
		UTMNorthing:            r.utmNorthing,
		ComputedUTMZone:        geod.ComputedUTMZone,
		ComputedUTMEasting:     geod.ComputedUTMEasting,
		ComputedUTMNorthing:    geod.ComputedUTMNorthing,
		UTMDerivedLat:          geod.UTMDerivedLat,
		UTMDerivedLon:          geod.UTMDerivedLon,
		DivergenceMeters:       geod.DivergenceMeters,
		DivergenceFlagged:      geod.DivergenceFlagged,
		Elevation:              r.elevation,
		SuggestedNtsMapSheet:   geod.BCGSMapSheet,
		Diagnostics:            append([]string(nil), geod.Diagnostics...),
	}

	var queryLat, queryLon *float64
	if geod.NormalizedLat != nil && geod.NormalizedLon != nil {
		queryLat, queryLon = geod.NormalizedLat, geod.NormalizedLon
	} else if geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
		queryLat, queryLon = geod.UTMDerivedLat, geod.UTMDerivedLon
	}
	if queryLat != nil && queryLon != nil && attr != nil {
		if sug, err := attr.SuggestSpatialAttributes(*queryLat, *queryLon); err == nil && sug != nil {
			qa.SuggestedGISBGC = sug.GISBGC
			qa.SuggestedBGCLabel = sug.BGCLabel
			qa.SuggestedEcosection = sug.Ecosection
			qa.SuggestedFSRegionDistrict = sug.FSRegionDistrict
			if sug.NtsMapSheet != "" {
				qa.SuggestedNtsMapSheet = sug.NtsMapSheet
			}
			qa.ExpectedElevationMinM = sug.ExpectedElevationMinM
			qa.ExpectedElevationMaxM = sug.ExpectedElevationMaxM
			if r.elevation != nil && sug.ExpectedElevationMinM != nil && sug.ExpectedElevationMaxM != nil {
				if *r.elevation < *sug.ExpectedElevationMinM || *r.elevation > *sug.ExpectedElevationMaxM {
					qa.ElevationFlagged = true
					qa.Diagnostics = append(qa.Diagnostics,
						fmt.Sprintf("Card Elevation %d m lies outside %s envelope [%d..%d m]", *r.elevation, sug.GISBGC, *sug.ExpectedElevationMinM, *sug.ExpectedElevationMaxM))
				}
			}
		}
	}

	compareGIS := qa.SuggestedGISBGC
	if compareGIS == "" {
		compareGIS = NormalizeCompactBGCCode(qa.StoredGISBGC)
	}
	if fieldBGC != "" && compareGIS != "" && !strings.EqualFold(fieldBGC, NormalizeCompactBGCCode(compareGIS)) {
		qa.BGCMismatch = true
		qa.Diagnostics = append(qa.Diagnostics, fmt.Sprintf("Field BGC %q differs from GIS BGC %q", fieldBGC, compareGIS))
	}
	return qa
}

// BatchAuditSpatialQA runs Auto-1 geodetic + PMTiles BGC/Admin/Terrain QA across all plots in the active project/SU scope.
func BatchAuditSpatialQA(ctx context.Context, contexts *vprocore.ContextService, contextID string, attributors ...*PMTilesAttributor) (*SpatialBatchAuditReport, error) {
	if ctx == nil {
		return nil, errors.New("spatial QA requires a request context")
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

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*SpatialBatchAuditReport, error) {
		owner := plots.Projects.Sqlite
		rawRows, err := queryScopedSpatialPlotRows(ctx, owner)
		if err != nil {
			return nil, err
		}
		report := &SpatialBatchAuditReport{
			ContextID:  contextID,
			Project:    owner.Selection.Project,
			SU:         owner.Selection.SU,
			TotalPlots: len(rawRows),
			Rows:       make([]SpatialPlotQARow, 0, len(rawRows)),
		}
		for _, r := range rawRows {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			qa := buildPlotQARow(r, attr)
			if qa.NormalizedLat != nil || qa.UTMDerivedLat != nil {
				report.CoordinatizedPlots++
				if strings.TrimSpace(qa.StoredGISBGC) == "" && qa.SuggestedGISBGC != "" {
					report.MissingGISBGCCount++
				}
			}
			if qa.LongitudeSignFlipped {
				report.UnsignedLonCount++
			}
			if qa.DivergenceFlagged {
				report.UTMDivergenceCount++
			}
			if qa.BGCMismatch {
				report.BGCMismatchCount++
			}
			if qa.ElevationFlagged {
				report.ElevationIssueCount++
			}
			report.Rows = append(report.Rows, qa)
		}
		return report, nil
	})
}
