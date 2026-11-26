package spatial

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// BECMasterCodedOption represents a code + human-readable label pair for BECMaster filter dropdowns.
type BECMasterCodedOption struct {
	Code  string `json:"code"`
	Label string `json:"label"`
}

// BECMasterProjectOption summarizes a distinct ProjectID discovered in Metadata/Env tables.
type BECMasterProjectOption struct {
	ProjectID string `json:"projectId"`
	Title     string `json:"title,omitempty"`
	PlotCount int    `json:"plotCount,omitempty"`
}

// BECMasterPublicationOption represents an optional BEC publication reference when linked in the database.
type BECMasterPublicationOption struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

// BECMasterFilterOptions provides all BEC_plots_Shiny-parity filter choices for the active project context.
type BECMasterFilterOptions struct {
	ContextID            string                       `json:"contextId"`
	Project              string                       `json:"project"`
	TotalPlots           int                          `json:"totalPlots"`
	Regions              []BECMasterCodedOption       `json:"regions"`
	Projects             []BECMasterProjectOption     `json:"projects"`
	ProjectIDs           []string                     `json:"projectIds"`
	Publications         []BECMasterPublicationOption `json:"publications"`
	HasPublicationLinks  bool                         `json:"hasPublicationLinks"`
	Zones                []string                     `json:"zones"`
	SubzonesByZone       map[string][]string          `json:"subzonesByZone"`
	MinYear              int                          `json:"minYear"`
	MaxYear              int                          `json:"maxYear"`
	SuccessionalStatuses []BECMasterCodedOption       `json:"successionalStatuses"`
	StructuralStages     []BECMasterCodedOption       `json:"structuralStages"`
	SitePlotQualities    []BECMasterCodedOption       `json:"sitePlotQualities"`
	VegPlotQualities     []BECMasterCodedOption       `json:"vegPlotQualities"`
	SoilPlotQualities    []BECMasterCodedOption       `json:"soilPlotQualities"`
	LocationAccuracies   []BECMasterCodedOption       `json:"locationAccuracies"`
}

// BECMasterFilterRequest mirrors MoF-Skeena-Research/BEC_plots_Shiny primary + attribute + quality filters.
type BECMasterFilterRequest struct {
	Mode                 string   `json:"mode"` // "all" | "region" | "project" | "bbox"
	Regions              []string `json:"regions,omitempty"`
	ProjectIDs           []string `json:"projectIds,omitempty"`
	PublicationIDs       []string `json:"publicationIds,omitempty"`
	NWLat                *float64 `json:"nwLat,omitempty"`
	NWLon                *float64 `json:"nwLon,omitempty"`
	SELat                *float64 `json:"seLat,omitempty"`
	SELon                *float64 `json:"seLon,omitempty"`
	Zones                []string `json:"zones,omitempty"`
	Subzones             []string `json:"subzones,omitempty"`
	MinYear              *int     `json:"minYear,omitempty"`
	MaxYear              *int     `json:"maxYear,omitempty"`
	SuccessionalStatuses []string `json:"successionalStatuses,omitempty"`
	StructuralStages     []string `json:"structuralStages,omitempty"`
	InPublicationsOnly   bool     `json:"inPublicationsOnly,omitempty"`
	SitePlotQualities    []string `json:"sitePlotQualities,omitempty"`
	VegPlotQualities     []string `json:"vegPlotQualities,omitempty"`
	SoilPlotQualities    []string `json:"soilPlotQualities,omitempty"`
	LocationAccuracy     string   `json:"locationAccuracy,omitempty"`
}

func (r *BECMasterFilterRequest) UnmarshalJSON(data []byte) error {
	type plain BECMasterFilterRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// BECMasterMapPoint is the compact coordinate/attribute payload returned for filtered BECMaster map rendering.
type BECMasterMapPoint struct {
	PlotNumber string  `json:"plotNumber"`
	Lat        float64 `json:"lat"`
	Lon        float64 `json:"lon"`
	Zone       string  `json:"zone"`
	SubZone    string  `json:"subZone"`
	SiteSeries string  `json:"siteSeries"`
	ProjectID  string  `json:"projectId"`
	Region     string  `json:"region"`
}

// BECMasterFilterResult returns matched plot numbers and compact plottable map points.
type BECMasterFilterResult struct {
	ContextID    string              `json:"contextId"`
	Project      string              `json:"project"`
	TotalPlots   int                 `json:"totalPlots"`
	MatchedCount int                 `json:"matchedCount"`
	PlotNumbers  []string            `json:"plotNumbers"`
	Points       []BECMasterMapPoint `json:"points"`
}

var canonicalBCForestRegions = []BECMasterCodedOption{
	{Code: "RCB", Label: "Cariboo-Chilcotin"},
	{Code: "RKB", Label: "Kootenay-Boundary"},
	{Code: "RNO", Label: "Northeast"},
	{Code: "ROM", Label: "Omineca"},
	{Code: "RSC", Label: "South Coast"},
	{Code: "RSK", Label: "Skeena"},
	{Code: "RTO", Label: "Thompson-Okanagan"},
	{Code: "RWC", Label: "West Coast"},
}

var canonicalSuccessionalStatuses = []BECMasterCodedOption{
	{Code: "OC", Label: "Old Climax"},
	{Code: "MC", Label: "Maturing Climax"},
	{Code: "DC", Label: "Disclimax"},
	{Code: "YC", Label: "Young Climax"},
	{Code: "OS", Label: "Overmature Seral"},
	{Code: "MS", Label: "Maturing Seral"},
	{Code: "YS", Label: "Young Seral"},
	{Code: "PS", Label: "Pioneer Seral"},
}

var canonicalLocationAccuracies = []BECMasterCodedOption{
	{Code: "<=1", Label: "<1m"},
	{Code: "<=5", Label: "<5m"},
	{Code: "<=10", Label: "<10m"},
	{Code: "<=30", Label: "<30m"},
	{Code: "<=100", Label: "<100m"},
	{Code: "<=1000", Label: "<1000m"},
	{Code: ">1000", Label: ">1000m"},
}

var fallbackStructuralStages = []BECMasterCodedOption{
	{Code: "1", Label: "Non-vegetated/Sparse"},
	{Code: "1a", Label: "Sparse"},
	{Code: "1b", Label: "Bryoid"},
	{Code: "1c", Label: "Lichen"},
	{Code: "2", Label: "Herb"},
	{Code: "2a", Label: "Forb-dominated"},
	{Code: "2b", Label: "Graminoid-dominated"},
	{Code: "2c", Label: "Aquatic"},
	{Code: "2d", Label: "Dwarf shrub-dominated"},
	{Code: "3", Label: "Shrub/Stunted trees"},
	{Code: "3a", Label: "Low Shrub"},
	{Code: "3b", Label: "Tall Shrub"},
	{Code: "3c", Label: "Short stunted trees"},
	{Code: "3d", Label: "Tall stunted trees"},
	{Code: "4", Label: "Pole/Sapling"},
	{Code: "5", Label: "Young Forest"},
	{Code: "6", Label: "Mature Forest"},
	{Code: "7", Label: "Old Forest"},
	{Code: "7a", Label: "Old Forest"},
	{Code: "7b", Label: "Very Old Forest"},
}

var fallbackPlotQualities = []BECMasterCodedOption{
	{Code: "Excellent", Label: "Excellent - FS882 Full detail"},
	{Code: "Good", Label: "Good - FS882 Partial or Lower quality"},
	{Code: "Fair", Label: "Fair - Ground Call / SIVI"},
	{Code: "Poor", Label: "Poor - Visuals, Notes, Low quality"},
}

func cloneCodedOptions(src []BECMasterCodedOption) []BECMasterCodedOption {
	out := make([]BECMasterCodedOption, len(src))
	copy(out, src)
	return out
}

// extractBECMasterRegionPrefix computes UPPER(SUBSTR(TRIM(FSRegionDistrict), 1, 3)).
func extractBECMasterRegionPrefix(fsRegionDistrict string) string {
	trimmed := strings.TrimSpace(fsRegionDistrict)
	if trimmed == "" {
		return ""
	}
	runes := []rune(trimmed)
	if len(runes) > 3 {
		runes = runes[:3]
	}
	return strings.ToUpper(string(runes))
}

// extractBECMasterSubzoneKey computes UPPER(TRIM(Zone) || TRIM(SubZone)).
func extractBECMasterSubzoneKey(zone, subZone string) string {
	z := strings.TrimSpace(zone)
	sz := strings.TrimSpace(subZone)
	if z == "" && sz == "" {
		return ""
	}
	return strings.ToUpper(z + sz)
}

// extractBECMasterStructuralStageCode computes LOWER(SUBSTR(TRIM(StructuralStage), 1, 2)).
func extractBECMasterStructuralStageCode(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	runes := []rune(trimmed)
	if len(runes) > 2 {
		runes = runes[:2]
	}
	return strings.ToLower(string(runes))
}

// parseBECMasterPlotYear extracts a 4-digit field survey year from USysEnv.Date,
// ignoring Access OLE zero sentinel dates (1899-12-30) and implausible years outside [1901, 2100].
func parseBECMasterPlotYear(raw string) (int, bool) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return 0, false
	}
	// Fast path: ISO YYYY-... or YYYY/... or bare YYYY
	if len(s) >= 4 && isAllDigits(s[:4]) {
		if y, err := strconv.Atoi(s[:4]); err == nil && y >= 1901 && y <= 2100 {
			return y, true
		}
	}
	// Fallback: scan slash/dash/space separated tokens for a 4-digit year (e.g. MM/DD/YYYY)
	fields := strings.FieldsFunc(s, func(r rune) bool {
		return r == '-' || r == '/' || r == ' ' || r == 'T' || r == '.' || r == ','
	})
	for _, tok := range fields {
		if len(tok) == 4 && isAllDigits(tok) {
			if y, err := strconv.Atoi(tok); err == nil && y >= 1901 && y <= 2100 {
				return y, true
			}
		}
	}
	return 0, false
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// normalizeBECMasterBBoxLongitude normalizes BC/Western North America longitudes so both
// signed (-125.4) and legacy positive West (125.4) values map cleanly to signed Western degrees.
func normalizeBECMasterBBoxLongitude(lon float64) float64 {
	if lon > 100.0 && lon <= 180.0 {
		return -lon
	}
	return lon
}

func matchLocationAccuracy(acc *int, rule string) (bool, error) {
	switch strings.TrimSpace(rule) {
	case "":
		return true, nil
	case "<=1":
		return acc != nil && *acc <= 1, nil
	case "<=5":
		return acc != nil && *acc <= 5, nil
	case "<=10":
		return acc != nil && *acc <= 10, nil
	case "<=30":
		return acc != nil && *acc <= 30, nil
	case "<=100":
		return acc != nil && *acc <= 100, nil
	case "<=1000":
		return acc != nil && *acc <= 1000, nil
	case ">1000":
		return acc != nil && *acc > 1000, nil
	default:
		return false, fmt.Errorf("unsupported locationAccuracy %q (supported: <=1, <=5, <=10, <=30, <=100, <=1000, >1000)", rule)
	}
}

type rawBECMasterPlotRow struct {
	plotNumber         string
	projectID          string
	fsRegionDistrict   string
	dateStr            string
	zone               string
	subZone            string
	siteSeries         string
	successionalStatus string
	structuralStage    string
	latitude           *float64
	longitude          *float64
	utmZone            *string
	utmEasting         *float64
	utmNorthing        *float64
	locationAccuracy   *int
	sitePlotQuality    string
	vegPlotQuality     string
	soilPlotQuality    string
	becSiteUnit        string
}

type becMasterPublicationIndex struct {
	available     bool
	options       []BECMasterPublicationOption
	pubToProjects map[string]map[string]bool // upper(pubID) -> upper(projectID)
	pubToPlots    map[string]map[string]bool // upper(pubID) -> exact plotNumber
	allPubProj    map[string]bool            // upper(projectID) linked to any publication
	allPubPlots   map[string]bool            // exact plotNumber linked to any publication
}

func discoverBECMasterPublications(ctx context.Context, tx *sql.Tx, project string) becMasterPublicationIndex {
	idx := becMasterPublicationIndex{
		options:       []BECMasterPublicationOption{},
		pubToProjects: map[string]map[string]bool{},
		pubToPlots:    map[string]map[string]bool{},
		allPubProj:    map[string]bool{},
		allPubPlots:   map[string]bool{},
	}

	rows, err := tx.QueryContext(ctx, `SELECT name FROM "project".sqlite_master WHERE type IN ('table', 'view')`)
	if err != nil {
		return idx
	}
	var tableNames []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err == nil {
			tableNames = append(tableNames, name)
		}
	}
	_ = rows.Close()

	// Find candidate publication / publication-link tables (gracefully optional).
	var linkTables []string
	var pubCatalogTables []string
	for _, tbl := range tableNames {
		lower := strings.ToLower(tbl)
		if !strings.Contains(lower, "pub") {
			continue
		}
		if strings.Contains(lower, "link") || strings.Contains(lower, "plot") || strings.Contains(lower, "project") {
			linkTables = append(linkTables, tbl)
		} else {
			pubCatalogTables = append(pubCatalogTables, tbl)
		}
	}

	inspectCols := func(tbl string) map[string]string {
		colMap := map[string]string{}
		pRows, pErr := tx.QueryContext(ctx, `PRAGMA "project".table_info(`+vprocore.QuoteHeaderIdentifier(tbl)+`)`)
		if pErr != nil {
			return colMap
		}
		defer pRows.Close()
		for pRows.Next() {
			var cid, notNull, pk int
			var name, ctype string
			var dflt any
			if sErr := pRows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); sErr == nil {
				colMap[strings.ToLower(name)] = name
			}
		}
		return colMap
	}

	pickCol := func(cols map[string]string, candidates ...string) string {
		for _, c := range candidates {
			if actual, ok := cols[strings.ToLower(c)]; ok {
				return actual
			}
		}
		return ""
	}

	pubTitles := map[string]string{} // upper(id) -> title
	pubIDCase := map[string]string{} // upper(id) -> original id

	readTable := func(tbl string) {
		cols := inspectCols(tbl)
		idCol := pickCol(cols, "PublicationID", "PubID", "Publication_ID", "Pub_ID", "ID", "Code", "Publication")
		titleCol := pickCol(cols, "Title", "PublicationTitle", "Citation", "Publication", "Name", "Description")
		plotCol := pickCol(cols, "PlotNumber", "Plot")
		projCol := pickCol(cols, "ProjectID", "Project")
		if idCol == "" {
			return
		}
		if plotCol == "" && projCol == "" && titleCol == "" {
			return
		}
		selectExprs := []string{`COALESCE(CAST(` + vprocore.QuoteHeaderIdentifier(idCol) + ` AS TEXT), '')`}
		if titleCol != "" {
			selectExprs = append(selectExprs, `COALESCE(CAST(`+vprocore.QuoteHeaderIdentifier(titleCol)+` AS TEXT), '')`)
		} else {
			selectExprs = append(selectExprs, `''`)
		}
		if plotCol != "" {
			selectExprs = append(selectExprs, `COALESCE(CAST(`+vprocore.QuoteHeaderIdentifier(plotCol)+` AS TEXT), '')`)
		} else {
			selectExprs = append(selectExprs, `''`)
		}
		if projCol != "" {
			selectExprs = append(selectExprs, `COALESCE(CAST(`+vprocore.QuoteHeaderIdentifier(projCol)+` AS TEXT), '')`)
		} else {
			selectExprs = append(selectExprs, `''`)
		}
		q := `SELECT ` + strings.Join(selectExprs, ", ") + ` FROM "project".` + vprocore.QuoteHeaderIdentifier(tbl)
		qRows, qErr := tx.QueryContext(ctx, q)
		if qErr != nil {
			return
		}
		defer qRows.Close()
		for qRows.Next() {
			var pubID, title, plotNum, projID string
			if sErr := qRows.Scan(&pubID, &title, &plotNum, &projID); sErr != nil {
				continue
			}
			pubID = strings.TrimSpace(pubID)
			title = strings.TrimSpace(title)
			projID = strings.TrimSpace(projID)
			if pubID == "" {
				continue
			}
			key := strings.ToUpper(pubID)
			if _, ok := pubIDCase[key]; !ok {
				pubIDCase[key] = pubID
			}
			if title != "" && pubTitles[key] == "" {
				pubTitles[key] = title
			}
			if plotNum != "" {
				idx.available = true
				if idx.pubToPlots[key] == nil {
					idx.pubToPlots[key] = map[string]bool{}
				}
				idx.pubToPlots[key][plotNum] = true
				idx.allPubPlots[plotNum] = true
			}
			if projID != "" {
				idx.available = true
				uProj := strings.ToUpper(projID)
				if idx.pubToProjects[key] == nil {
					idx.pubToProjects[key] = map[string]bool{}
				}
				idx.pubToProjects[key][uProj] = true
				idx.allPubProj[uProj] = true
			}
		}
	}

	for _, tbl := range pubCatalogTables {
		readTable(tbl)
	}
	for _, tbl := range linkTables {
		readTable(tbl)
	}
	// Also check explicit <Project>_Publications if named without "pub" prefix variations
	_ = project

	if len(pubIDCase) > 0 {
		keys := make([]string, 0, len(pubIDCase))
		for k := range pubIDCase {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			id := pubIDCase[k]
			title := pubTitles[k]
			if title == "" {
				title = id
			}
			idx.options = append(idx.options, BECMasterPublicationOption{ID: id, Title: title})
		}
	}
	return idx
}

func queryVListsOptions(ctx context.Context, tx *sql.Tx, listName string, maxLen int, excludeNA bool) []BECMasterCodedOption {
	query := `SELECT COALESCE(CAST("Item" AS TEXT), ''), COALESCE(CAST("ItemDescription" AS TEXT), '')
		FROM "VLists"."USysTableOfLists"
		WHERE "ListName" = ? AND "Item" IS NOT NULL AND TRIM(CAST("Item" AS TEXT)) <> ''
		ORDER BY "ItemOrder" ASC, "Item" COLLATE NOCASE ASC`
	rows, err := tx.QueryContext(ctx, query, listName)
	if err != nil {
		return nil
	}
	defer rows.Close()

	seen := make(map[string]bool)
	var out []BECMasterCodedOption
	for rows.Next() {
		var item, desc string
		if err := rows.Scan(&item, &desc); err != nil {
			continue
		}
		item = strings.TrimSpace(item)
		desc = strings.TrimSpace(desc)
		if item == "" {
			continue
		}
		if excludeNA && strings.EqualFold(item, "NA") {
			continue
		}
		if maxLen > 0 && len([]rune(item)) > maxLen {
			continue
		}
		key := strings.ToLower(item)
		if seen[key] {
			continue
		}
		seen[key] = true
		label := desc
		if label == "" || strings.EqualFold(label, "null") {
			label = item
		}
		out = append(out, BECMasterCodedOption{Code: item, Label: label})
	}
	return out
}

func queryScopedBECMasterPlotRows(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext) ([]rawBECMasterPlotRow, error) {
	project := owner.Selection.Project
	qEnv := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	qAdmin := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	type adminMeta struct {
		siteQuality string
		vegQuality  string
		soilQuality string
		becSiteUnit string
	}
	adminByPlot := make(map[string]adminMeta)
	if aRows, aErr := tx.QueryContext(ctx, `SELECT
		CAST("Plot" AS TEXT),
		COALESCE(CAST("SitePlotQuality" AS TEXT), ''),
		COALESCE(CAST("VegPlotQuality" AS TEXT), ''),
		COALESCE(CAST("SoilPlotQuality" AS TEXT), ''),
		COALESCE(CAST("BECSiteUnit" AS TEXT), '')
	FROM `+qAdmin+` WHERE typeof("Plot")='text'`); aErr == nil {
		func() {
			defer aRows.Close()
			for aRows.Next() {
				var plot string
				var m adminMeta
				if sErr := aRows.Scan(&plot, &m.siteQuality, &m.vegQuality, &m.soilQuality, &m.becSiteUnit); sErr == nil {
					if _, exists := adminByPlot[plot]; !exists {
						adminByPlot[plot] = m
					}
				}
			}
		}()
	}

	hasActiveSU := owner.Selection.SU != "" && owner.Selection.SU != "None"
	var suPlots map[string]bool
	if hasActiveSU {
		suPlots = make(map[string]bool)
		qSU := `"su".` + vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU")
		suRows, sErr := tx.QueryContext(ctx, `SELECT CAST("PlotNumber" AS TEXT) FROM `+qSU+` WHERE typeof("PlotNumber")='text'`)
		if sErr != nil {
			return nil, sErr
		}
		defer suRows.Close()
		for suRows.Next() {
			var p string
			if err := suRows.Scan(&p); err != nil {
				return nil, err
			}
			suPlots[p] = true
		}
		if err := suRows.Err(); err != nil {
			return nil, err
		}
	}

	query := `SELECT
		CAST(env."PlotNumber" AS TEXT),
		COALESCE(CAST(env."ProjectID" AS TEXT), ''),
		COALESCE(CAST(env."FSRegionDistrict" AS TEXT), ''),
		COALESCE(CAST(env."Date" AS TEXT), ''),
		COALESCE(CAST(env."Zone" AS TEXT), ''),
		COALESCE(CAST(env."SubZone" AS TEXT), ''),
		COALESCE(CAST(env."SiteSeries" AS TEXT), ''),
		COALESCE(CAST(env."SuccessionalStatus" AS TEXT), ''),
		COALESCE(CAST(env."StructuralStage" AS TEXT), ''),
		env."Latitude",
		env."Longitude",
		CAST(env."UTMZone" AS TEXT),
		env."UTMEasting",
		env."UTMNorthing",
		env."LocationAccuracy"
	FROM ` + qEnv + ` AS env
	WHERE typeof(env."PlotNumber")='text' AND TRIM(CAST(env."PlotNumber" AS TEXT)) <> ''
	ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`

	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []rawBECMasterPlotRow
	seen := make(map[string]bool)
	rowIdx := 0
	for rows.Next() {
		if rowIdx&511 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		rowIdx++
		var r rawBECMasterPlotRow
		var lat, lon, east, north sql.NullFloat64
		var utmZ sql.NullString
		var acc sql.NullInt64
		if err := rows.Scan(
			&r.plotNumber,
			&r.projectID,
			&r.fsRegionDistrict,
			&r.dateStr,
			&r.zone,
			&r.subZone,
			&r.siteSeries,
			&r.successionalStatus,
			&r.structuralStage,
			&lat, &lon, &utmZ, &east, &north, &acc,
		); err != nil {
			return nil, err
		}
		if hasActiveSU && !suPlots[r.plotNumber] {
			continue
		}
		if seen[r.plotNumber] {
			continue
		}
		seen[r.plotNumber] = true

		adm := adminByPlot[r.plotNumber]
		r.sitePlotQuality = adm.siteQuality
		r.vegPlotQuality = adm.vegQuality
		r.soilPlotQuality = adm.soilQuality
		r.becSiteUnit = adm.becSiteUnit

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
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

// GetBECMasterFilterOptions computes all BEC_plots_Shiny-parity filter choices for the active project context.
func GetBECMasterFilterOptions(ctx context.Context, contexts *vprocore.ContextService, contextID string) (*BECMasterFilterOptions, error) {
	if ctx == nil {
		return nil, errors.New("BECMaster filter options require a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("spatial context service is unavailable")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*BECMasterFilterOptions, error) {
		owner := plots.Projects.Sqlite
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

		rawRows, err := queryScopedBECMasterPlotRows(ctx, tx, owner)
		if err != nil {
			return nil, err
		}

		// Collect ProjectIDs & titles from Metadata + Env
		projMap := make(map[string]*BECMasterProjectOption) // upper(ProjectID) -> option
		qMeta := `"project".` + vprocore.QuoteHeaderIdentifier(owner.Selection.Project+"_Metadata")
		if mRows, mErr := tx.QueryContext(ctx, `SELECT COALESCE(CAST("ProjectID" AS TEXT), ''), COALESCE(CAST("ProjectTitle" AS TEXT), '') FROM `+qMeta); mErr == nil {
			func() {
				defer mRows.Close()
				for mRows.Next() {
					var pid, title string
					if sErr := mRows.Scan(&pid, &title); sErr == nil {
						pid = strings.TrimSpace(pid)
						title = strings.TrimSpace(title)
						if pid == "" {
							continue
						}
						key := strings.ToUpper(pid)
						opt, ok := projMap[key]
						if !ok {
							projMap[key] = &BECMasterProjectOption{ProjectID: pid, Title: title}
						} else if opt.Title == "" && title != "" {
							opt.Title = title
						}
					}
				}
			}()
		}

		zoneSet := make(map[string]struct{})
		subzonesByZoneSet := make(map[string]map[string]struct{})
		minYear, maxYear := 0, 0

		for _, r := range rawRows {
			if pid := strings.TrimSpace(r.projectID); pid != "" {
				key := strings.ToUpper(pid)
				opt, ok := projMap[key]
				if !ok {
					opt = &BECMasterProjectOption{ProjectID: pid}
					projMap[key] = opt
				}
				opt.PlotCount++
			}
			if z := strings.ToUpper(strings.TrimSpace(r.zone)); z != "" {
				zoneSet[z] = struct{}{}
				if subzonesByZoneSet[z] == nil {
					subzonesByZoneSet[z] = make(map[string]struct{})
				}
				if sz := strings.TrimSpace(r.subZone); sz != "" {
					subzonesByZoneSet[z][extractBECMasterSubzoneKey(z, sz)] = struct{}{}
				}
			}
			if y, ok := parseBECMasterPlotYear(r.dateStr); ok {
				if minYear == 0 || y < minYear {
					minYear = y
				}
				if y > maxYear {
					maxYear = y
				}
			}
		}

		projects := make([]BECMasterProjectOption, 0, len(projMap))
		for _, opt := range projMap {
			projects = append(projects, *opt)
		}
		sort.Slice(projects, func(i, j int) bool {
			li := strings.ToLower(projects[i].ProjectID)
			lj := strings.ToLower(projects[j].ProjectID)
			if li != lj {
				return li < lj
			}
			return projects[i].ProjectID < projects[j].ProjectID
		})
		projectIDs := make([]string, len(projects))
		for i, p := range projects {
			projectIDs[i] = p.ProjectID
		}

		zones := make([]string, 0, len(zoneSet))
		for z := range zoneSet {
			zones = append(zones, z)
		}
		sort.Strings(zones)

		subzonesByZone := make(map[string][]string, len(zones))
		for _, z := range zones {
			szSet := subzonesByZoneSet[z]
			list := make([]string, 0, len(szSet))
			for sz := range szSet {
				list = append(list, sz)
			}
			sort.Strings(list)
			subzonesByZone[z] = list
		}

		pubIdx := discoverBECMasterPublications(ctx, tx, owner.Selection.Project)

		structStages := queryVListsOptions(ctx, tx, "StructuralStage", 2, false)
		if len(structStages) == 0 {
			structStages = cloneCodedOptions(fallbackStructuralStages)
		}
		qualities := queryVListsOptions(ctx, tx, "PlotQualitySite", 0, true)
		if len(qualities) == 0 {
			qualities = cloneCodedOptions(fallbackPlotQualities)
		}

		return &BECMasterFilterOptions{
			ContextID:            contextID,
			Project:              owner.Selection.Project,
			TotalPlots:           len(rawRows),
			Regions:              cloneCodedOptions(canonicalBCForestRegions),
			Projects:             projects,
			ProjectIDs:           projectIDs,
			Publications:         pubIdx.options,
			HasPublicationLinks:  pubIdx.available,
			Zones:                zones,
			SubzonesByZone:       subzonesByZone,
			MinYear:              minYear,
			MaxYear:              maxYear,
			SuccessionalStatuses: cloneCodedOptions(canonicalSuccessionalStatuses),
			StructuralStages:     structStages,
			SitePlotQualities:    cloneCodedOptions(qualities),
			VegPlotQualities:     cloneCodedOptions(qualities),
			SoilPlotQualities:    cloneCodedOptions(qualities),
			LocationAccuracies:   cloneCodedOptions(canonicalLocationAccuracies),
		}, nil
	})
}

func makeNormalizedUpperSet(items []string) map[string]bool {
	if len(items) == 0 {
		return nil
	}
	out := make(map[string]bool, len(items))
	for _, item := range items {
		if t := strings.ToUpper(strings.TrimSpace(item)); t != "" {
			out[t] = true
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func makeNormalizedLowerSet(items []string) map[string]bool {
	if len(items) == 0 {
		return nil
	}
	out := make(map[string]bool, len(items))
	for _, item := range items {
		if t := strings.ToLower(strings.TrimSpace(item)); t != "" {
			out[t] = true
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func resolveBECMasterPlotLatLon(r rawBECMasterPlotRow) (lat, lon float64, ok bool) {
	geod := EvaluatePlotGeodesy(PlotGeodesyInput{
		Latitude:         r.latitude,
		Longitude:        r.longitude,
		UTMZone:          r.utmZone,
		UTMEasting:       r.utmEasting,
		UTMNorthing:      r.utmNorthing,
		LocationAccuracy: r.locationAccuracy,
	})
	if geod.NormalizedLat != nil && geod.NormalizedLon != nil {
		lat, lon = *geod.NormalizedLat, *geod.NormalizedLon
		ok = true
	} else if geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
		lat, lon = *geod.UTMDerivedLat, *geod.UTMDerivedLon
		ok = true
	}
	if !ok || math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) {
		return 0, 0, false
	}
	if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0 {
		return 0, 0, false
	}
	return lat, lon, true
}

// FilterBECMasterPlots executes MoF-Skeena-Research/BEC_plots_Shiny-parity filtering over the active context.
func FilterBECMasterPlots(ctx context.Context, contexts *vprocore.ContextService, contextID string, req BECMasterFilterRequest) (*BECMasterFilterResult, error) {
	if ctx == nil {
		return nil, errors.New("BECMaster filter requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("spatial context service is unavailable")
	}

	mode := strings.ToLower(strings.TrimSpace(req.Mode))
	if mode == "" {
		mode = "all"
	}
	switch mode {
	case "all", "region", "project", "bbox":
	default:
		return nil, fmt.Errorf("unsupported BECMaster filter mode %q (supported: all, region, project, bbox)", req.Mode)
	}

	var bboxMinLat, bboxMaxLat, bboxMinLon, bboxMaxLon float64
	if mode == "bbox" {
		if req.NWLat == nil || req.NWLon == nil || req.SELat == nil || req.SELon == nil {
			return nil, errors.New("bbox filter mode requires nwLat, nwLon, seLat, and seLon")
		}
		nwLat, nwLon, seLat, seLon := *req.NWLat, *req.NWLon, *req.SELat, *req.SELon
		for _, v := range []float64{nwLat, nwLon, seLat, seLon} {
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return nil, errors.New("bbox coordinates must be finite numbers")
			}
		}
		if nwLat < -90.0 || nwLat > 90.0 || seLat < -90.0 || seLat > 90.0 {
			return nil, errors.New("bbox latitudes must be within [-90, 90]")
		}
		if nwLon < -180.0 || nwLon > 180.0 || seLon < -180.0 || seLon > 180.0 {
			return nil, errors.New("bbox longitudes must be within [-180, 180]")
		}
		nwLon = normalizeBECMasterBBoxLongitude(nwLon)
		seLon = normalizeBECMasterBBoxLongitude(seLon)
		bboxMinLat = math.Min(nwLat, seLat)
		bboxMaxLat = math.Max(nwLat, seLat)
		bboxMinLon = math.Min(nwLon, seLon)
		bboxMaxLon = math.Max(nwLon, seLon)
	}

	if req.MinYear != nil && req.MaxYear != nil && *req.MinYear > *req.MaxYear {
		return nil, fmt.Errorf("minYear (%d) cannot exceed maxYear (%d)", *req.MinYear, *req.MaxYear)
	}
	if _, err := matchLocationAccuracy(nil, req.LocationAccuracy); err != nil {
		return nil, err
	}

	regionSet := makeNormalizedUpperSet(req.Regions)
	projectSet := makeNormalizedUpperSet(req.ProjectIDs)
	pubIDSet := makeNormalizedUpperSet(req.PublicationIDs)
	zoneSet := makeNormalizedUpperSet(req.Zones)
	subzoneSet := makeNormalizedUpperSet(req.Subzones)
	succSet := makeNormalizedUpperSet(req.SuccessionalStatuses)
	stageSet := makeNormalizedLowerSet(req.StructuralStages)
	siteQualSet := makeNormalizedLowerSet(req.SitePlotQualities)
	vegQualSet := makeNormalizedLowerSet(req.VegPlotQualities)
	soilQualSet := makeNormalizedLowerSet(req.SoilPlotQualities)

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*BECMasterFilterResult, error) {
		owner := plots.Projects.Sqlite
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

		rawRows, err := queryScopedBECMasterPlotRows(ctx, tx, owner)
		if err != nil {
			return nil, err
		}

		var pubIdx becMasterPublicationIndex
		if req.InPublicationsOnly || (mode == "project" && len(pubIDSet) > 0) {
			pubIdx = discoverBECMasterPublications(ctx, tx, owner.Selection.Project)
		}

		res := &BECMasterFilterResult{
			ContextID:   contextID,
			Project:     owner.Selection.Project,
			TotalPlots:  len(rawRows),
			PlotNumbers: []string{},
			Points:      []BECMasterMapPoint{},
		}

		for i, r := range rawRows {
			if i&511 == 0 {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
			}

			region := extractBECMasterRegionPrefix(r.fsRegionDistrict)
			projTrim := strings.TrimSpace(r.projectID)
			projUpper := strings.ToUpper(projTrim)
			zoneTrim := strings.TrimSpace(r.zone)
			zoneUpper := strings.ToUpper(zoneTrim)
			subZoneTrim := strings.TrimSpace(r.subZone)
			subzoneKey := extractBECMasterSubzoneKey(zoneTrim, subZoneTrim)

			var lat, lon float64
			var hasCoord bool
			coordResolved := false
			ensureCoord := func() (float64, float64, bool) {
				if !coordResolved {
					lat, lon, hasCoord = resolveBECMasterPlotLatLon(r)
					coordResolved = true
				}
				return lat, lon, hasCoord
			}

			// 1. Primary filter mode
			switch mode {
			case "region":
				if len(regionSet) > 0 && !regionSet[region] {
					continue
				}
			case "project":
				if len(projectSet) > 0 || len(pubIDSet) > 0 {
					matchedPrimary := false
					if len(projectSet) > 0 && projectSet[projUpper] {
						matchedPrimary = true
					}
					if !matchedPrimary && len(pubIDSet) > 0 && pubIdx.available {
						for pid := range pubIDSet {
							if pubIdx.pubToPlots[pid][r.plotNumber] || (projUpper != "" && pubIdx.pubToProjects[pid][projUpper]) {
								matchedPrimary = true
								break
							}
						}
					}
					if !matchedPrimary {
						continue
					}
				}
			case "bbox":
				pLat, pLon, ok := ensureCoord()
				if !ok || pLat < bboxMinLat || pLat > bboxMaxLat || pLon < bboxMinLon || pLon > bboxMaxLon {
					continue
				}
			}

			// 2. Composable AND attribute & quality filters
			if len(zoneSet) > 0 && !zoneSet[zoneUpper] {
				continue
			}
			if len(subzoneSet) > 0 && !subzoneSet[subzoneKey] {
				continue
			}
			if req.MinYear != nil || req.MaxYear != nil {
				year, ok := parseBECMasterPlotYear(r.dateStr)
				if !ok {
					continue
				}
				if req.MinYear != nil && year < *req.MinYear {
					continue
				}
				if req.MaxYear != nil && year > *req.MaxYear {
					continue
				}
			}
			if len(succSet) > 0 {
				if !succSet[strings.ToUpper(strings.TrimSpace(r.successionalStatus))] {
					continue
				}
			}
			if len(stageSet) > 0 {
				if !stageSet[extractBECMasterStructuralStageCode(r.structuralStage)] {
					continue
				}
			}
			if req.InPublicationsOnly {
				if pubIdx.available {
					if !pubIdx.allPubPlots[r.plotNumber] && (projUpper == "" || !pubIdx.allPubProj[projUpper]) {
						continue
					}
				} else if strings.TrimSpace(r.becSiteUnit) == "" {
					continue
				}
			}
			if len(siteQualSet) > 0 && !siteQualSet[strings.ToLower(strings.TrimSpace(r.sitePlotQuality))] {
				continue
			}
			if len(vegQualSet) > 0 && !vegQualSet[strings.ToLower(strings.TrimSpace(r.vegPlotQuality))] {
				continue
			}
			if len(soilQualSet) > 0 && !soilQualSet[strings.ToLower(strings.TrimSpace(r.soilPlotQuality))] {
				continue
			}
			if req.LocationAccuracy != "" {
				matchedAcc, err := matchLocationAccuracy(r.locationAccuracy, req.LocationAccuracy)
				if err != nil {
					return nil, err
				}
				if !matchedAcc {
					continue
				}
			}

			res.PlotNumbers = append(res.PlotNumbers, r.plotNumber)
			if pLat, pLon, ok := ensureCoord(); ok {
				res.Points = append(res.Points, BECMasterMapPoint{
					PlotNumber: r.plotNumber,
					Lat:        pLat,
					Lon:        pLon,
					Zone:       zoneTrim,
					SubZone:    subZoneTrim,
					SiteSeries: strings.TrimSpace(r.siteSeries),
					ProjectID:  projTrim,
					Region:     region,
				})
			}
		}

		res.MatchedCount = len(res.PlotNumbers)
		return res, nil
	})
}
