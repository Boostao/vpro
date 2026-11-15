package interchange

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func readSQLiteTableSet(ctx context.Context, db *sql.DB) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `SELECT LOWER(name) FROM sqlite_master WHERE type='table'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	set := map[string]bool{}
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		set[n] = true
	}
	return set, rows.Err()
}

func readSQLiteTableColumns(ctx context.Context, db *sql.DB, table string) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+vprocore.QuoteHeaderIdentifier(table)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, ctype string
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[strings.ToLower(name)] = true
	}
	return cols, rows.Err()
}

func readTurboVeg3SQLiteFile(ctx context.Context, path string, resolver *speciesImportResolver) ([]tvImportPlot, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	resolved, err := vprocore.ExistingDatabasePath(path)
	if err != nil {
		return nil, err
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, resolved)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	tbls, err := readSQLiteTableSet(ctx, db)
	if err != nil {
		return nil, err
	}
	for _, req := range []string{"plotobservations", "plots", "speciesobservations", "taxa", "covercodes", "vegetationlayers"} {
		if !tbls[req] {
			return nil, fmt.Errorf("source SQLite file %s is missing official Turboveg 3 table %q", filepath.Base(resolved), req)
		}
	}

	geomExpr := "''"
	locJoin := ""
	if tbls["locations"] {
		locCols, err := readSQLiteTableColumns(ctx, db, "locations")
		if err != nil {
			return nil, err
		}
		locJoin = ` LEFT JOIN locations AS l ON l.id = p.locationid`
		switch {
		case locCols["the_geom"] && locCols["wkt"]:
			geomExpr = `COALESCE(NULLIF(TRIM(CAST(l.the_geom AS TEXT)), ''), NULLIF(TRIM(CAST(l.wkt AS TEXT)), ''), '')`
		case locCols["the_geom"]:
			geomExpr = `COALESCE(NULLIF(TRIM(CAST(l.the_geom AS TEXT)), ''), '')`
		case locCols["wkt"]:
			geomExpr = `COALESCE(NULLIF(TRIM(CAST(l.wkt AS TEXT)), ''), '')`
		}
	}

	var plots []tvImportPlot
	poQuery := `
		SELECT po.id, ` + geomExpr + `
		FROM plotobservations AS po
		INNER JOIN plots AS p ON p.id = po.plotid` + locJoin + `
		WHERE COALESCE(po.deleted, 0) = 0
		ORDER BY po.id`

	poRows, err := db.QueryContext(ctx, poQuery)
	if err != nil {
		return nil, fmt.Errorf("read Turboveg 3 plotobservations: %w", err)
	}
	plotIdxByObsID := map[int]int{}
	wktByObsID := map[int]string{}
	releveFallbackByObsID := map[int]string{}
	for poRows.Next() {
		var obsID int
		var wkt string
		if err := poRows.Scan(&obsID, &wkt); err != nil {
			poRows.Close()
			return nil, err
		}
		plotIdxByObsID[obsID] = len(plots)
		wktByObsID[obsID] = wkt
		plots = append(plots, tvImportPlot{
			Header: tvPlotHeader{
				PlotID: obsID,
			},
		})
	}
	if err := poRows.Err(); err != nil {
		poRows.Close()
		return nil, err
	}
	if err := poRows.Close(); err != nil {
		return nil, err
	}

	// Pivot plotobservationheaderdata
	if tbls["plotobservationheaderdata"] && tbls["fields"] {
		dtExpr := "''"
		dtJoin := ""
		if tbls["datatypes"] {
			dtExpr = `UPPER(COALESCE(dt.name, ''))`
			dtJoin = ` LEFT JOIN datatypes AS dt ON dt.id = f.datatypeid`
		}
		ldCodeExpr := "''"
		ldDescExpr := "''"
		ldJoin := ""
		if tbls["lookupdata"] {
			ldCodeExpr = `COALESCE(ld.code, '')`
			ldDescExpr = `COALESCE(ld.description1, '')`
			ldJoin = ` LEFT JOIN lookupdata AS ld ON ld.id = poh.lookupdataid`
		}
		hdrQuery := `
			SELECT
				poh.plotobservationid,
				UPPER(TRIM(f.fieldname)),
				` + dtExpr + `,
				COALESCE(poh.valuestring, ''),
				poh.valueinteger,
				poh.valuefloat,
				` + ldCodeExpr + `,
				` + ldDescExpr + `
			FROM plotobservationheaderdata AS poh
			INNER JOIN plotobservations AS po ON po.id = poh.plotobservationid
			INNER JOIN fields AS f ON f.id = poh.fieldid` + dtJoin + ldJoin + `
			WHERE COALESCE(po.deleted, 0) = 0 AND COALESCE(poh.deleted, 0) = 0
			ORDER BY poh.plotobservationid, poh.id`
		hRows, err := db.QueryContext(ctx, hdrQuery)
		if err != nil {
			return nil, fmt.Errorf("read Turboveg 3 plotobservationheaderdata: %w", err)
		}
		for hRows.Next() {
			var obsID int
			var fieldName, dtName, valStr, ldCode, ldDesc string
			var valInt sql.NullInt64
			var valFloat sql.NullFloat64
			if err := hRows.Scan(&obsID, &fieldName, &dtName, &valStr, &valInt, &valFloat, &ldCode, &ldDesc); err != nil {
				hRows.Close()
				return nil, err
			}
			idx, ok := plotIdxByObsID[obsID]
			if !ok {
				continue
			}
			h := &plots[idx].Header

			strVal := strings.TrimSpace(valStr)
			if strVal == "" && strings.TrimSpace(ldDesc) != "" {
				strVal = strings.TrimSpace(ldDesc)
			} else if strVal == "" && strings.TrimSpace(ldCode) != "" {
				strVal = strings.TrimSpace(ldCode)
			}
			if strVal == "" && valInt.Valid {
				strVal = strconv.FormatInt(valInt.Int64, 10)
			} else if strVal == "" && valFloat.Valid {
				strVal = strconv.FormatFloat(valFloat.Float64, 'f', -1, 64)
			}

			floatPtr := func() *float64 {
				if valFloat.Valid {
					v := valFloat.Float64
					return &v
				}
				if valInt.Valid {
					v := float64(valInt.Int64)
					return &v
				}
				if f, pErr := strconv.ParseFloat(strings.TrimSpace(valStr), 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
					return &f
				}
				return nil
			}
			intPtr := func() *int {
				if valInt.Valid {
					v := int(valInt.Int64)
					return &v
				}
				if valFloat.Valid {
					v := int(math.Round(valFloat.Float64))
					return &v
				}
				if deg, ok := parseCompassAspectDegrees(strVal); ok {
					return &deg
				}
				return nil
			}

			switch fieldName {
			case "VPRO_PLOT", "PLOT_NUMBER", "PLOTNUMBER":
				if strVal != "" {
					h.PlotNumber = strVal
				}
			case "RELEVE_NR":
				if strVal != "" {
					releveFallbackByObsID[obsID] = strVal
				}
			case "FIELD_NR", "FIELD_NUMBER", "NR_IN_TAB":
				if h.FieldNumber == "" || fieldName == "FIELD_NR" {
					h.FieldNumber = strVal
				}
			case "PROJECT_ID", "PROJECT":
				if h.ProjectID == "" || fieldName == "PROJECT_ID" {
					if strings.TrimSpace(valStr) != "" {
						h.ProjectID = strings.TrimSpace(valStr)
					} else {
						h.ProjectID = strVal
					}
				}
			case "DATE":
				if strings.TrimSpace(valStr) != "" {
					h.Date = normalizeTVDateString(valStr)
				} else if valFloat.Valid {
					h.Date = delphiDateTimeToISODate(valFloat.Float64)
				} else if valInt.Valid {
					if dtName != "DATE" && valInt.Int64 >= 10000101 && valInt.Int64 <= 99991231 {
						h.Date = normalizeTVDateString(strconv.FormatInt(valInt.Int64, 10))
					} else {
						h.Date = delphiDateTimeToISODate(float64(valInt.Int64))
					}
				}
			case "SURF_AREA", "PLOT_SIZE":
				if v := floatPtr(); v != nil {
					h.PlotSize = v
				}
			case "ALTITUDE", "ELEVATION":
				if v := intPtr(); v != nil {
					h.Elevation = v
				}
			case "EXPOSITION", "ASPECT":
				if v := intPtr(); v != nil {
					h.Aspect = v
				}
			case "INCLINATIO", "INCLINATION", "SLOPE":
				if v := floatPtr(); v != nil {
					h.Slope = v
				}
			case "AUTHOR", "SURVEYOR":
				if h.Surveyor == "" || fieldName == "SURVEYOR" {
					h.Surveyor = strVal
				}
			case "LATITUDE", "DEG_LAT":
				if v := floatPtr(); v != nil {
					h.Latitude = v
				}
			case "LONGITUDE", "DEG_LON":
				if v := floatPtr(); v != nil {
					h.Longitude = v
				}
			case "ZONE":
				h.Zone = strVal
			case "SUBZONE":
				h.SubZone = strVal
			case "SITE_SERIES":
				h.SiteSeries = strVal
			case "SITE_UNIT":
				h.SiteUnit = strVal
			case "SYNTAXON":
				if h.SiteUnit == "" {
					if strings.TrimSpace(ldCode) != "" {
						h.SiteUnit = strings.TrimSpace(ldCode)
					} else {
						h.SiteUnit = strVal
					}
				}
			case "MOISTURE", "MOISTURE_REGIME":
				h.MoistureRegime = strVal
			case "NUTRIENT", "NUTRIENT_REGIME":
				h.NutrientRegime = strVal
			case "MESO_SLOPE", "MESO_SLOPE_POSITION":
				h.MesoSlopePosition = strVal
			case "SURF_SHAPE", "SURFACE_SHAPE":
				h.SurfaceShape = strVal
			case "DRAINAGE", "SOIL_DRAINAGE":
				h.SoilDrainage = strVal
			case "HUMUS_FORM":
				h.HumusForm = strVal
			case "LOCATION", "LOCALITY":
				if h.Location == "" || fieldName == "LOCATION" {
					h.Location = strVal
				}
			case "SITE_NOTES":
				h.SiteNotes = strVal
			case "REMARKS":
				if h.SiteNotes == "" {
					h.SiteNotes = strVal
				}
			case "VEG_NOTES":
				h.VegNotes = strVal
			case "SOIL_NOTES":
				h.SoilNotes = strVal
			}
		}
		if err := hRows.Err(); err != nil {
			hRows.Close()
			return nil, err
		}
		if err := hRows.Close(); err != nil {
			return nil, err
		}
	}

	// Finalize plot numbers and WKT POINT coordinate fallback
	for obsID, idx := range plotIdxByObsID {
		h := &plots[idx].Header
		if strings.TrimSpace(h.PlotNumber) == "" {
			if rel := strings.TrimSpace(releveFallbackByObsID[obsID]); rel != "" {
				h.PlotNumber = rel
			} else {
				h.PlotNumber = strconv.Itoa(obsID)
			}
		}
		if h.Latitude == nil || h.Longitude == nil {
			if lon, lat, ok := parseWKTPointLonLat(wktByObsID[obsID]); ok {
				if h.Longitude == nil {
					h.Longitude = &lon
				}
				if h.Latitude == nil {
					h.Latitude = &lat
				}
			}
		}
	}

	// Load speciesobservationdata attributes keyed by speciesobservationid
	type soAttr struct {
		height    *float64
		collected string
		vproLayer string
		vproCode  string
	}
	attrsBySOID := map[int]*soAttr{}
	if tbls["speciesobservationdata"] && tbls["fields"] {
		sodRows, err := db.QueryContext(ctx, `
			SELECT
				sod.speciesobservationid,
				UPPER(TRIM(f.fieldname)),
				COALESCE(sod.valuestring, ''),
				sod.valueinteger,
				sod.valuefloat
			FROM speciesobservationdata AS sod
			INNER JOIN fields AS f ON f.id = sod.fieldid
			WHERE COALESCE(sod.deleted, 0) = 0
			ORDER BY sod.speciesobservationid, sod.id`)
		if err != nil {
			return nil, fmt.Errorf("read Turboveg 3 speciesobservationdata: %w", err)
		}
		for sodRows.Next() {
			var soID int
			var fName, vStr string
			var vInt sql.NullInt64
			var vFloat sql.NullFloat64
			if err := sodRows.Scan(&soID, &fName, &vStr, &vInt, &vFloat); err != nil {
				sodRows.Close()
				return nil, err
			}
			a := attrsBySOID[soID]
			if a == nil {
				a = &soAttr{}
				attrsBySOID[soID] = a
			}
			switch fName {
			case "HEIGHT":
				if vFloat.Valid {
					v := vFloat.Float64
					a.height = &v
				} else if vInt.Valid {
					v := float64(vInt.Int64)
					a.height = &v
				} else if f, pErr := strconv.ParseFloat(strings.TrimSpace(vStr), 64); pErr == nil {
					a.height = &f
				}
			case "COLLECTED":
				a.collected = strings.TrimSpace(vStr)
			case "VPRO_LAYER":
				a.vproLayer = strings.TrimSpace(vStr)
			case "VPRO_CODE":
				a.vproCode = strings.TrimSpace(vStr)
			}
		}
		if err := sodRows.Err(); err != nil {
			sodRows.Close()
			return nil, err
		}
		if err := sodRows.Close(); err != nil {
			return nil, err
		}
	}

	// Read active speciesobservations joined with taxa, scalar synonym target lookup (never multiplying rows when tv2speciesid repeats), vegetationlayers, and covercodes
	soRows, err := db.QueryContext(ctx, `
		SELECT
			so.id,
			so.plotobservationid,
			so.vegetationlayerid,
			COALESCE(vl.abbreviation, ''),
			cc.percentage_mean,
			COALESCE(cc.code, ''),
			COALESCE(t.scientificname, ''),
			COALESCE((
				SELECT vt.scientificname
				FROM taxa AS vt
				WHERE t.issynonym IS NOT NULL AND t.issynonym <> 0
					AND t.tv2validid IS NOT NULL
					AND vt.taxonlistid = t.taxonlistid
					AND vt.tv2speciesid = t.tv2validid
					AND vt.id <> t.id
				ORDER BY CASE WHEN COALESCE(vt.issynonym, 0) = 0 THEN 0 ELSE 1 END, vt.id ASC
				LIMIT 1
			), ''),
			COALESCE(t.lettercode, ''),
			COALESCE(t.metadata, ''),
			COALESCE(so.metadata, '')
		FROM speciesobservations AS so
		INNER JOIN plotobservations AS po ON po.id = so.plotobservationid
		INNER JOIN taxa AS t ON t.id = so.taxonid
		LEFT JOIN vegetationlayers AS vl ON vl.id = so.vegetationlayerid
		INNER JOIN covercodes AS cc ON cc.id = so.covercodeid
		WHERE COALESCE(po.deleted, 0) = 0 AND COALESCE(so.deleted, 0) = 0
		ORDER BY so.plotobservationid, so.id`)
	if err != nil {
		return nil, fmt.Errorf("read Turboveg 3 speciesobservations: %w", err)
	}
	defer soRows.Close()

	for soRows.Next() {
		var soID, obsID, vegLayerID int
		var vlAbbr, ccCode, sciName, validSciName, letterCode, taxaMetaRaw, soMetaRaw string
		var ccMean sql.NullFloat64
		if err := soRows.Scan(
			&soID, &obsID, &vegLayerID, &vlAbbr,
			&ccMean, &ccCode, &sciName, &validSciName, &letterCode,
			&taxaMetaRaw, &soMetaRaw,
		); err != nil {
			return nil, err
		}
		pIdx, ok := plotIdxByObsID[obsID]
		if !ok {
			continue
		}

		var cov float64
		if ccMean.Valid {
			cov = ccMean.Float64
		} else if parsed, pErr := strconv.ParseFloat(strings.TrimSpace(ccCode), 64); pErr == nil {
			cov = parsed
		} else if bb, ok := defaultBraunBlanquetMidpoint(ccCode); ok {
			cov = bb
		} else {
			return nil, fmt.Errorf("unresolvable Turboveg 3 cover code %q on speciesobservation %d", ccCode, soID)
		}

		var explicitVProCode, vproLayer string
		var heightPtr *float64
		var collected string
		if a := attrsBySOID[soID]; a != nil {
			explicitVProCode = a.vproCode
			vproLayer = a.vproLayer
			heightPtr = a.height
			collected = a.collected
		}
		if explicitVProCode == "" || vproLayer == "" {
			for _, rawJSON := range []string{soMetaRaw, taxaMetaRaw} {
				if strings.TrimSpace(rawJSON) == "" {
					continue
				}
				var m map[string]any
				if json.Unmarshal([]byte(rawJSON), &m) == nil {
					if explicitVProCode == "" {
						if vc, ok := m["vpro_code"].(string); ok {
							explicitVProCode = strings.TrimSpace(vc)
						}
					}
					if vproLayer == "" {
						if vl, ok := m["vpro_layer"].(string); ok {
							vproLayer = strings.TrimSpace(vl)
						}
					}
				}
			}
		}

		vproCode, lf := resolver.resolveTaxon(explicitVProCode, sciName, validSciName, letterCode)
		if strings.TrimSpace(vproCode) == "" {
			continue
		}
		isWoody := isWoodyVProLifeform(lf)
		tvLayerRaw := strconv.Itoa(vegLayerID)
		if vegLayerID < 0 && strings.TrimSpace(vlAbbr) != "" {
			tvLayerRaw = vlAbbr
		}

		plots[pIdx].Observations = append(plots[pIdx].Observations, tvImportObs{
			SpeciesCode: vproCode,
			TVLayerRaw:  tvLayerRaw,
			VProLayer:   vproLayer,
			IsWoody:     isWoody,
			Cover:       cov,
			Height:      heightPtr,
			Collected:   collected,
		})
	}
	return plots, soRows.Err()
}
