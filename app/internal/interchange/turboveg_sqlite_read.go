package interchange

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type tv3SpeciesObsAttr struct {
	height    *float64
	collected string
	vproLayer string
	vproCode  string
}

type tv3HeaderRowValues struct {
	obsID     int
	fieldName string
	dtName    string
	valStr    string
	valInt    sql.NullInt64
	valFloat  sql.NullFloat64
	ldCode    string
	ldDesc    string
	strVal    string
}

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
	if err := verifyRequiredTV3Tables(tbls, resolved); err != nil {
		return nil, err
	}

	plots, plotIdxByObsID, wktByObsID, err := readTV3PlotObservations(ctx, db, tbls)
	if err != nil {
		return nil, err
	}
	releveFallbackByObsID, err := pivotTV3HeaderAttributes(ctx, db, tbls, plots, plotIdxByObsID)
	if err != nil {
		return nil, err
	}
	finalizeTV3PlotNumbersAndCoords(plots, plotIdxByObsID, releveFallbackByObsID, wktByObsID)

	attrsBySOID, err := loadTV3SpeciesObservationAttrs(ctx, db, tbls)
	if err != nil {
		return nil, err
	}
	return loadTV3SpeciesObservations(ctx, db, plots, plotIdxByObsID, attrsBySOID, resolver)
}

func verifyRequiredTV3Tables(tbls map[string]bool, resolvedPath string) error {
	for _, req := range []string{"plotobservations", "plots", "speciesobservations", "taxa", "covercodes", "vegetationlayers"} {
		if !tbls[req] {
			return fmt.Errorf("source SQLite file %s is missing official Turboveg 3 table %q", filepath.Base(resolvedPath), req)
		}
	}
	return nil
}

func readTV3PlotObservations(ctx context.Context, db *sql.DB, tbls map[string]bool) ([]tvImportPlot, map[int]int, map[int]string, error) {
	geomExpr, locJoin, err := buildTV3LocationJoinExpr(ctx, db, tbls)
	if err != nil {
		return nil, nil, nil, err
	}
	poQuery := `
		SELECT po.id, ` + geomExpr + `
		FROM plotobservations AS po
		INNER JOIN plots AS p ON p.id = po.plotid` + locJoin + `
		WHERE COALESCE(po.deleted, 0) = 0
		ORDER BY po.id`

	poRows, err := db.QueryContext(ctx, poQuery)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("read Turboveg 3 plotobservations: %w", err)
	}
	var plots []tvImportPlot
	plotIdxByObsID := map[int]int{}
	wktByObsID := map[int]string{}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, poRows.Close()) }()
		for poRows.Next() {
			var obsID int
			var wkt string
			if err := poRows.Scan(&obsID, &wkt); err != nil {
				return err
			}
			plotIdxByObsID[obsID] = len(plots)
			wktByObsID[obsID] = wkt
			plots = append(plots, tvImportPlot{Header: tvPlotHeader{PlotID: obsID}})
		}
		return poRows.Err()
	}(); err != nil {
		return nil, nil, nil, err
	}
	return plots, plotIdxByObsID, wktByObsID, nil
}

func buildTV3LocationJoinExpr(ctx context.Context, db *sql.DB, tbls map[string]bool) (string, string, error) {
	if !tbls["locations"] {
		return "''", "", nil
	}
	locCols, err := readSQLiteTableColumns(ctx, db, "locations")
	if err != nil {
		return "", "", err
	}
	locJoin := ` LEFT JOIN locations AS l ON l.id = p.locationid`
	switch {
	case locCols["the_geom"] && locCols["wkt"]:
		return `COALESCE(NULLIF(TRIM(CAST(l.the_geom AS TEXT)), ''), NULLIF(TRIM(CAST(l.wkt AS TEXT)), ''), '')`, locJoin, nil
	case locCols["the_geom"]:
		return `COALESCE(NULLIF(TRIM(CAST(l.the_geom AS TEXT)), ''), '')`, locJoin, nil
	case locCols["wkt"]:
		return `COALESCE(NULLIF(TRIM(CAST(l.wkt AS TEXT)), ''), '')`, locJoin, nil
	default:
		return "''", locJoin, nil
	}
}

func pivotTV3HeaderAttributes(
	ctx context.Context,
	db *sql.DB,
	tbls map[string]bool,
	plots []tvImportPlot,
	plotIdxByObsID map[int]int,
) (map[int]string, error) {
	releveFallbackByObsID := map[int]string{}
	if !tbls["plotobservationheaderdata"] || !tbls["fields"] {
		return releveFallbackByObsID, nil
	}
	hdrQuery := buildTV3HeaderPivotQuery(tbls)
	hRows, err := db.QueryContext(ctx, hdrQuery)
	if err != nil {
		return nil, fmt.Errorf("read Turboveg 3 plotobservationheaderdata: %w", err)
	}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, hRows.Close()) }()
		for hRows.Next() {
			var row tv3HeaderRowValues
			if err := hRows.Scan(
				&row.obsID, &row.fieldName, &row.dtName, &row.valStr,
				&row.valInt, &row.valFloat, &row.ldCode, &row.ldDesc,
			); err != nil {
				return err
			}
			idx, ok := plotIdxByObsID[row.obsID]
			if !ok {
				continue
			}
			row.strVal = resolveTV3HeaderTextValue(row)
			applyTV3HeaderRow(&plots[idx].Header, row, releveFallbackByObsID)
		}
		return hRows.Err()
	}(); err != nil {
		return nil, err
	}
	return releveFallbackByObsID, nil
}

func buildTV3HeaderPivotQuery(tbls map[string]bool) string {
	dtExpr, dtJoin := "''", ""
	if tbls["datatypes"] {
		dtExpr = `UPPER(COALESCE(dt.name, ''))`
		dtJoin = ` LEFT JOIN datatypes AS dt ON dt.id = f.datatypeid`
	}
	ldCodeExpr, ldDescExpr, ldJoin := "''", "''", ""
	if tbls["lookupdata"] {
		ldCodeExpr = `COALESCE(ld.code, '')`
		ldDescExpr = `COALESCE(ld.description1, '')`
		ldJoin = ` LEFT JOIN lookupdata AS ld ON ld.id = poh.lookupdataid`
	}
	return `
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
}

func resolveTV3HeaderTextValue(row tv3HeaderRowValues) string {
	for _, candidate := range []string{row.valStr, row.ldDesc, row.ldCode} {
		if trimmed := strings.TrimSpace(candidate); trimmed != "" {
			return trimmed
		}
	}
	if row.valInt.Valid {
		return strconv.FormatInt(row.valInt.Int64, 10)
	}
	if row.valFloat.Valid {
		return strconv.FormatFloat(row.valFloat.Float64, 'f', -1, 64)
	}
	return ""
}

func (r tv3HeaderRowValues) floatPtr() *float64 {
	if r.valFloat.Valid {
		v := r.valFloat.Float64
		return &v
	}
	if r.valInt.Valid {
		v := float64(r.valInt.Int64)
		return &v
	}
	if f, err := strconv.ParseFloat(strings.TrimSpace(r.valStr), 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
		return &f
	}
	return nil
}

func (r tv3HeaderRowValues) intPtr() *int {
	if r.valInt.Valid {
		v := int(r.valInt.Int64)
		return &v
	}
	if r.valFloat.Valid {
		v := int(math.Round(r.valFloat.Float64))
		return &v
	}
	if deg, ok := parseCompassAspectDegrees(r.strVal); ok {
		return &deg
	}
	return nil
}

func applyTV3HeaderRow(h *tvPlotHeader, row tv3HeaderRowValues, releveFallbackByObsID map[int]string) {
	if applyTV3IdentityAndDateField(h, row, releveFallbackByObsID) {
		return
	}
	if applyTV3NumericSiteField(h, row) {
		return
	}
	applyTV3ClassificationAndNoteField(h, row)
}

func applyTV3IdentityAndDateField(h *tvPlotHeader, row tv3HeaderRowValues, releveFallbackByObsID map[int]string) bool {
	switch row.fieldName {
	case "VPRO_PLOT", "PLOT_NUMBER", "PLOTNUMBER":
		if row.strVal != "" {
			h.PlotNumber = row.strVal
		}
	case "RELEVE_NR":
		if row.strVal != "" {
			releveFallbackByObsID[row.obsID] = row.strVal
		}
	case "FIELD_NR", "FIELD_NUMBER", "NR_IN_TAB":
		if h.FieldNumber == "" || row.fieldName == "FIELD_NR" {
			h.FieldNumber = row.strVal
		}
	case "PROJECT_ID", "PROJECT":
		if h.ProjectID == "" || row.fieldName == "PROJECT_ID" {
			if trimmed := strings.TrimSpace(row.valStr); trimmed != "" {
				h.ProjectID = trimmed
			} else {
				h.ProjectID = row.strVal
			}
		}
	case "DATE":
		h.Date = resolveTV3DateValue(row)
	case "AUTHOR", "SURVEYOR":
		if h.Surveyor == "" || row.fieldName == "SURVEYOR" {
			h.Surveyor = row.strVal
		}
	default:
		return false
	}
	return true
}

func resolveTV3DateValue(row tv3HeaderRowValues) string {
	if strings.TrimSpace(row.valStr) != "" {
		return normalizeTVDateString(row.valStr)
	}
	if row.valFloat.Valid {
		return delphiDateTimeToISODate(row.valFloat.Float64)
	}
	if row.valInt.Valid {
		if row.dtName != "DATE" && row.valInt.Int64 >= 10000101 && row.valInt.Int64 <= 99991231 {
			return normalizeTVDateString(strconv.FormatInt(row.valInt.Int64, 10))
		}
		return delphiDateTimeToISODate(float64(row.valInt.Int64))
	}
	return ""
}

func applyTV3NumericSiteField(h *tvPlotHeader, row tv3HeaderRowValues) bool {
	switch row.fieldName {
	case "SURF_AREA", "PLOT_SIZE":
		if v := row.floatPtr(); v != nil {
			h.PlotSize = v
		}
	case "ALTITUDE", "ELEVATION":
		if v := row.intPtr(); v != nil {
			h.Elevation = v
		}
	case "EXPOSITION", "ASPECT":
		if v := row.intPtr(); v != nil {
			h.Aspect = v
		}
	case "INCLINATIO", "INCLINATION", "SLOPE":
		if v := row.floatPtr(); v != nil {
			h.Slope = v
		}
	case "LATITUDE", "DEG_LAT":
		if v := row.floatPtr(); v != nil {
			h.Latitude = v
		}
	case "LONGITUDE", "DEG_LON":
		if v := row.floatPtr(); v != nil {
			h.Longitude = v
		}
	default:
		return false
	}
	return true
}

func applyTV3ClassificationAndNoteField(h *tvPlotHeader, row tv3HeaderRowValues) {
	switch row.fieldName {
	case "ZONE":
		h.Zone = row.strVal
	case "SUBZONE":
		h.SubZone = row.strVal
	case "SITE_SERIES":
		h.SiteSeries = row.strVal
	case "SITE_UNIT":
		h.SiteUnit = row.strVal
	case "SYNTAXON":
		if h.SiteUnit == "" {
			if trimmed := strings.TrimSpace(row.ldCode); trimmed != "" {
				h.SiteUnit = trimmed
			} else {
				h.SiteUnit = row.strVal
			}
		}
	case "MOISTURE", "MOISTURE_REGIME":
		h.MoistureRegime = row.strVal
	case "NUTRIENT", "NUTRIENT_REGIME":
		h.NutrientRegime = row.strVal
	case "MESO_SLOPE", "MESO_SLOPE_POSITION":
		h.MesoSlopePosition = row.strVal
	case "SURF_SHAPE", "SURFACE_SHAPE":
		h.SurfaceShape = row.strVal
	case "DRAINAGE", "SOIL_DRAINAGE":
		h.SoilDrainage = row.strVal
	case "HUMUS_FORM":
		h.HumusForm = row.strVal
	case "LOCATION", "LOCALITY":
		if h.Location == "" || row.fieldName == "LOCATION" {
			h.Location = row.strVal
		}
	case "SITE_NOTES":
		h.SiteNotes = row.strVal
	case "REMARKS":
		if h.SiteNotes == "" {
			h.SiteNotes = row.strVal
		}
	case "VEG_NOTES":
		h.VegNotes = row.strVal
	case "SOIL_NOTES":
		h.SoilNotes = row.strVal
	}
}

func finalizeTV3PlotNumbersAndCoords(
	plots []tvImportPlot,
	plotIdxByObsID map[int]int,
	releveFallbackByObsID map[int]string,
	wktByObsID map[int]string,
) {
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
}

func loadTV3SpeciesObservationAttrs(ctx context.Context, db *sql.DB, tbls map[string]bool) (map[int]*tv3SpeciesObsAttr, error) {
	attrsBySOID := map[int]*tv3SpeciesObsAttr{}
	if !tbls["speciesobservationdata"] || !tbls["fields"] {
		return attrsBySOID, nil
	}
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
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, sodRows.Close()) }()
		for sodRows.Next() {
			var soID int
			var fName, vStr string
			var vInt sql.NullInt64
			var vFloat sql.NullFloat64
			if err := sodRows.Scan(&soID, &fName, &vStr, &vInt, &vFloat); err != nil {
				return err
			}
			if attrsBySOID[soID] == nil {
				attrsBySOID[soID] = &tv3SpeciesObsAttr{}
			}
			applyTV3SpeciesObsAttr(attrsBySOID[soID], fName, vStr, vInt, vFloat)
		}
		return sodRows.Err()
	}(); err != nil {
		return nil, err
	}
	return attrsBySOID, nil
}

func applyTV3SpeciesObsAttr(a *tv3SpeciesObsAttr, fName, vStr string, vInt sql.NullInt64, vFloat sql.NullFloat64) {
	switch fName {
	case "HEIGHT":
		if vFloat.Valid {
			v := vFloat.Float64
			a.height = &v
		} else if vInt.Valid {
			v := float64(vInt.Int64)
			a.height = &v
		} else if f, err := strconv.ParseFloat(strings.TrimSpace(vStr), 64); err == nil {
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

func loadTV3SpeciesObservations(
	ctx context.Context,
	db *sql.DB,
	plots []tvImportPlot,
	plotIdxByObsID map[int]int,
	attrsBySOID map[int]*tv3SpeciesObsAttr,
	resolver *speciesImportResolver,
) ([]tvImportPlot, error) {
	soRows, err := db.QueryContext(ctx, tv3SpeciesObservationsSelectSQL)
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
		obs, keep, err := buildTV3ImportObservation(
			soID, vegLayerID, vlAbbr, ccMean, ccCode,
			sciName, validSciName, letterCode, taxaMetaRaw, soMetaRaw,
			attrsBySOID[soID], resolver,
		)
		if err != nil {
			return nil, err
		}
		if keep {
			plots[pIdx].Observations = append(plots[pIdx].Observations, obs)
		}
	}
	return plots, soRows.Err()
}

const tv3SpeciesObservationsSelectSQL = `
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
	ORDER BY so.plotobservationid, so.id`

func buildTV3ImportObservation(
	soID, vegLayerID int,
	vlAbbr string,
	ccMean sql.NullFloat64,
	ccCode, sciName, validSciName, letterCode, taxaMetaRaw, soMetaRaw string,
	attr *tv3SpeciesObsAttr,
	resolver *speciesImportResolver,
) (tvImportObs, bool, error) {
	cov, err := resolveTV3CoverPercent(soID, ccMean, ccCode)
	if err != nil {
		return tvImportObs{}, false, err
	}
	explicitVProCode, vproLayer, heightPtr, collected := resolveTV3ObservationMetadata(attr, soMetaRaw, taxaMetaRaw)
	vproCode, lf := resolver.resolveTaxon(explicitVProCode, sciName, validSciName, letterCode)
	if strings.TrimSpace(vproCode) == "" {
		return tvImportObs{}, false, nil
	}
	tvLayerRaw := strconv.Itoa(vegLayerID)
	if vegLayerID < 0 && strings.TrimSpace(vlAbbr) != "" {
		tvLayerRaw = vlAbbr
	}
	return tvImportObs{
		SpeciesCode: vproCode,
		TVLayerRaw:  tvLayerRaw,
		VProLayer:   vproLayer,
		IsWoody:     isWoodyVProLifeform(lf),
		Cover:       cov,
		Height:      heightPtr,
		Collected:   collected,
	}, true, nil
}

func resolveTV3CoverPercent(soID int, ccMean sql.NullFloat64, ccCode string) (float64, error) {
	if ccMean.Valid {
		return ccMean.Float64, nil
	}
	if parsed, err := strconv.ParseFloat(strings.TrimSpace(ccCode), 64); err == nil {
		return parsed, nil
	}
	if bb, ok := defaultBraunBlanquetMidpoint(ccCode); ok {
		return bb, nil
	}
	return 0, fmt.Errorf("unresolvable Turboveg 3 cover code %q on speciesobservation %d", ccCode, soID)
}

func resolveTV3ObservationMetadata(
	attr *tv3SpeciesObsAttr,
	soMetaRaw, taxaMetaRaw string,
) (explicitVProCode, vproLayer string, heightPtr *float64, collected string) {
	if attr != nil {
		explicitVProCode = attr.vproCode
		vproLayer = attr.vproLayer
		heightPtr = attr.height
		collected = attr.collected
	}
	if explicitVProCode != "" && vproLayer != "" {
		return explicitVProCode, vproLayer, heightPtr, collected
	}
	for _, rawJSON := range []string{soMetaRaw, taxaMetaRaw} {
		if strings.TrimSpace(rawJSON) == "" {
			continue
		}
		var m map[string]any
		if json.Unmarshal([]byte(rawJSON), &m) != nil {
			continue
		}
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
	return explicitVProCode, vproLayer, heightPtr, collected
}
