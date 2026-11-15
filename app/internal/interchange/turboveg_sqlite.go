package interchange

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

var delphiEpochUTC = time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)

func timeToDelphiDateTime(t time.Time) float64 {
	u := t.UTC()
	y, m, d := u.Date()
	dayStart := time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
	days := math.Round(float64(dayStart.Unix()-delphiEpochUTC.Unix()) / 86400.0)
	dayFrac := float64(u.Hour()*3600+u.Minute()*60+u.Second()) / 86400.0
	if days < 0 && dayFrac > 0 {
		return days - dayFrac
	}
	return days + dayFrac
}

func parseISODateToDelphi(raw string) (delphiDays float64, exactISODate bool, ok bool) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return 0, false, false
	}
	for _, layout := range []string{"2006-01-02", "2006/01/02", "20060102", "2006-01-02 15:04:05", "2006/01/02 15:04:05", time.RFC3339} {
		if t, err := time.Parse(layout, s); err == nil {
			d := timeToDelphiDateTime(t)
			isExact := s == t.UTC().Format("2006-01-02") && t.Hour() == 0 && t.Minute() == 0 && t.Second() == 0
			return d, isExact, true
		}
	}
	return 0, false, false
}

func delphiDateTimeToISODate(days float64) string {
	if math.IsNaN(days) || math.IsInf(days, 0) {
		return ""
	}
	// Delphi TDateTime encodes pre-1899-12-30 dates as -(absDays + timeFraction),
	// so integer day offset is Trunc toward zero (with tiny epsilon for float rounding).
	eps := 1e-9
	if days < 0 {
		eps = -1e-9
	}
	wholeDays := int(math.Trunc(days + eps))
	return delphiEpochUTC.AddDate(0, 0, wholeDays).Format("2006-01-02")
}

func formatWKTPoint(lon, lat float64) string {
	return fmt.Sprintf("POINT(%s %s)",
		strconv.FormatFloat(lon, 'f', -1, 64),
		strconv.FormatFloat(lat, 'f', -1, 64),
	)
}

func parseWKTPointLonLat(raw string) (lon, lat float64, ok bool) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return 0, 0, false
	}
	if semi := strings.IndexByte(s, ';'); semi >= 0 {
		s = strings.TrimSpace(s[semi+1:])
	}
	upper := strings.ToUpper(s)
	if !strings.HasPrefix(upper, "POINT") {
		return 0, 0, false
	}
	openIdx := strings.IndexByte(s, '(')
	closeIdx := strings.LastIndexByte(s, ')')
	if openIdx < 0 || closeIdx <= openIdx+1 {
		return 0, 0, false
	}
	inner := strings.TrimSpace(s[openIdx+1 : closeIdx])
	if strings.EqualFold(inner, "EMPTY") {
		return 0, 0, false
	}
	parts := strings.Fields(strings.ReplaceAll(inner, ",", " "))
	if len(parts) < 2 {
		return 0, 0, false
	}
	x, errX := strconv.ParseFloat(parts[0], 64)
	y, errY := strconv.ParseFloat(parts[1], 64)
	if errX != nil || errY != nil || math.IsNaN(x) || math.IsNaN(y) || math.IsInf(x, 0) || math.IsInf(y, 0) {
		return 0, 0, false
	}
	return x, y, true
}

func parseCompassAspectDegrees(raw string) (int, bool) {
	s := strings.ToUpper(strings.TrimSpace(raw))
	if s == "" {
		return 0, false
	}
	if v, err := strconv.Atoi(s); err == nil {
		return v, true
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
		return int(math.Round(f)), true
	}
	compass := map[string]int{
		"N": 0, "NNE": 22, "NE": 45, "ENE": 68,
		"E": 90, "ESE": 112, "SE": 135, "SSE": 158,
		"S": 180, "SSW": 202, "SW": 225, "WSW": 248,
		"W": 270, "WNW": 292, "NW": 315, "NNW": 338,
		"O": 90, "NO": 45, "ZO": 135, "Z": 180, "ZW": 225,
	}
	if deg, ok := compass[s]; ok {
		return deg, true
	}
	return 0, false
}

// Official 31-table, 37-FK, 36-index Alterra Turboveg 3 SQLite schema.
const turboVeg3OfficialDDL = `
CREATE TABLE datatypes (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR NOT NULL
);

CREATE TABLE units (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	desciption VARCHAR
);

CREATE TABLE fielddomains (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50)
);

CREATE TABLE fieldgroups (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	"order" INTEGER,
	metadata VARCHAR
);

CREATE TABLE lookuptables (
	id INTEGER NOT NULL PRIMARY KEY,
	filename VARCHAR(50) NOT NULL,
	description VARCHAR
);

CREATE TABLE lookupcaptions (
	id INTEGER NOT NULL PRIMARY KEY,
	lookuptableid INTEGER NOT NULL,
	columnno INTEGER NOT NULL,
	caption VARCHAR(50) NOT NULL,
	CONSTRAINT lookupcaptions_fkey FOREIGN KEY (lookuptableid) REFERENCES lookuptables(id)
);

CREATE TABLE lookupdata (
	id INTEGER NOT NULL PRIMARY KEY,
	lookuptableid INTEGER NOT NULL,
	code VARCHAR(100) NOT NULL,
	uri VARCHAR,
	description1 VARCHAR(255) NOT NULL,
	description2 VARCHAR(255) NOT NULL,
	description3 VARCHAR(255) NOT NULL,
	description4 VARCHAR(255) NOT NULL,
	CONSTRAINT lookuptablesdata_fkey01 FOREIGN KEY (lookuptableid) REFERENCES lookuptables(id)
);

CREATE TABLE covercodes (
	id INTEGER NOT NULL PRIMARY KEY,
	lookupdataid INTEGER NOT NULL,
	code VARCHAR NOT NULL,
	uri VARCHAR,
	percentage_mean REAL NOT NULL,
	percentage_min REAL,
	percentage_max REAL,
	CONSTRAINT covercodes_fkey01 FOREIGN KEY (lookupdataid) REFERENCES lookupdata(id)
);

CREATE TABLE custodians (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR NOT NULL,
	institution VARCHAR,
	email VARCHAR,
	metadata VARCHAR
);

CREATE TABLE datasetgroups (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	metadata VARCHAR
);

CREATE TABLE profiles (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL
);

CREATE TABLE taxonlists (
	id INTEGER NOT NULL PRIMARY KEY,
	sbstaxonlistid INTEGER,
	name VARCHAR(50) NOT NULL,
	metadata VARCHAR
);

CREATE TABLE taxongroups (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	metadata VARCHAR
);

CREATE TABLE taxonranks (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(255) NOT NULL,
	metadata VARCHAR
);

CREATE TABLE vegetationlayers (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	abbreviation VARCHAR(50),
	description VARCHAR
);

CREATE TABLE metadata (
	"key" VARCHAR NOT NULL PRIMARY KEY,
	"value" VARCHAR NOT NULL
);

CREATE TABLE projects (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	metadata VARCHAR
);

CREATE TABLE datasets (
	id INTEGER NOT NULL PRIMARY KEY,
	name VARCHAR(50) NOT NULL,
	datasetgroupid INTEGER NOT NULL,
	profileid INTEGER NOT NULL,
	taxonlistid INTEGER NOT NULL,
	custodianid INTEGER,
	deputycustodianid INTEGER,
	givdid VARCHAR,
	guid VARCHAR,
	metadata VARCHAR,
	CONSTRAINT datasets_fkey01 FOREIGN KEY (datasetgroupid) REFERENCES datasetgroups(id),
	CONSTRAINT datasets_fkey02 FOREIGN KEY (taxonlistid) REFERENCES taxonlists(id),
	CONSTRAINT datasets_fkey03 FOREIGN KEY (profileid) REFERENCES profiles(id),
	CONSTRAINT datasets_fkey04 FOREIGN KEY (custodianid) REFERENCES custodians(id),
	CONSTRAINT datasets_fkey05 FOREIGN KEY (deputycustodianid) REFERENCES custodians(id)
);

CREATE TABLE projectdatasets (
	projectid INTEGER NOT NULL,
	datasetid INTEGER NOT NULL,
	CONSTRAINT projectdatasets_fkey01 FOREIGN KEY (projectid) REFERENCES projects(id),
	CONSTRAINT projectdatasets_fkey02 FOREIGN KEY (datasetid) REFERENCES datasets(id)
);

CREATE TABLE fields (
	id INTEGER NOT NULL PRIMARY KEY,
	fielddomainid INTEGER NOT NULL,
	fieldgroupid INTEGER,
	lookuptableid INTEGER,
	unitid INTEGER,
	fieldname VARCHAR(20) NOT NULL,
	fieldtype VARCHAR(1) NOT NULL,
	description VARCHAR,
	datatypeid INTEGER NOT NULL,
	width SMALLINT NOT NULL,
	decimals SMALLINT NOT NULL,
	mandatory BOOLEAN,
	readonly BOOLEAN,
	valmin REAL,
	valmax REAL,
	valin VARCHAR,
	hint VARCHAR,
	CONSTRAINT fields_fkey01 FOREIGN KEY (unitid) REFERENCES units(id),
	CONSTRAINT fields_fkey02 FOREIGN KEY (lookuptableid) REFERENCES lookuptables(id),
	CONSTRAINT fields_fkey03 FOREIGN KEY (fieldgroupid) REFERENCES fieldgroups(id),
	CONSTRAINT fields_fkey04 FOREIGN KEY (datatypeid) REFERENCES datatypes(id),
	CONSTRAINT fields_fkey05 FOREIGN KEY (fielddomainid) REFERENCES fielddomains(id)
);

CREATE TABLE profiledata (
	id INTEGER NOT NULL PRIMARY KEY,
	profileid INTEGER NOT NULL,
	fieldid INTEGER NOT NULL,
	"order" INTEGER,
	"show" BOOLEAN,
	mandatory BOOLEAN,
	readonly BOOLEAN,
	CONSTRAINT profiledata_fkey01 FOREIGN KEY (profileid) REFERENCES profiles(id),
	CONSTRAINT profiledata_fkey02 FOREIGN KEY (fieldid) REFERENCES fields(id)
);

CREATE TABLE locations (
	id INTEGER NOT NULL PRIMARY KEY,
	the_geom GEOMETRY NOT NULL
);

CREATE TABLE plots (
	id INTEGER NOT NULL PRIMARY KEY,
	datasetid INTEGER NOT NULL,
	locationid INTEGER,
	locationuncertainty INTEGER,
	metadata VARCHAR,
	CONSTRAINT plots_fkey01 FOREIGN KEY (datasetid) REFERENCES datasets(id),
	CONSTRAINT plots_fkey02 FOREIGN KEY (locationid) REFERENCES locations(id)
);

CREATE TABLE plotobservations (
	id INTEGER NOT NULL PRIMARY KEY,
	plotid INTEGER NOT NULL,
	guid VARCHAR NOT NULL,
	changedby VARCHAR(50),
	changedwhen DOUBLE,
	quality SMALLINT,
	deleted BOOLEAN,
	synoptic BOOLEAN,
	nrofplotobservations INTEGER,
	accessregime SMALLINT,
	CONSTRAINT plotobservations_fkey01 FOREIGN KEY (plotid) REFERENCES plots(id)
);

CREATE TABLE plotobservationheaderdata (
	id INTEGER NOT NULL PRIMARY KEY,
	plotobservationid INTEGER NOT NULL,
	fieldid INTEGER NOT NULL,
	lookupdataid INTEGER,
	valuestring VARCHAR,
	valueinteger INTEGER,
	valuefloat DOUBLE,
	deleted BOOLEAN,
	CONSTRAINT plotobservationheaderdata_fkey01 FOREIGN KEY (plotobservationid) REFERENCES plotobservations(id),
	CONSTRAINT plotobservationheaderdata_fkey02 FOREIGN KEY (fieldid) REFERENCES fields(id),
	CONSTRAINT plotobservationheaderdata_fkey03 FOREIGN KEY (lookupdataid) REFERENCES lookupdata(id)
);

CREATE TABLE pictures (
	id INTEGER NOT NULL PRIMARY KEY,
	plotobservationid INTEGER NOT NULL,
	url VARCHAR,
	author VARCHAR,
	date DOUBLE,
	longitude DOUBLE,
	latitude DOUBLE,
	description VARCHAR,
	CONSTRAINT pictures_fkey01 FOREIGN KEY (plotobservationid) REFERENCES plotobservations(id)
);

CREATE TABLE associa (
	id INTEGER NOT NULL PRIMARY KEY,
	plotobservationid INTEGER NOT NULL,
	lookupdataid INTEGER NOT NULL,
	combinedindex REAL NOT NULL,
	normalised_likelyhood REAL NOT NULL,
	incompleteness REAL NOT NULL,
	weirdness REAL NOT NULL,
	CONSTRAINT associa_fkey01 FOREIGN KEY (plotobservationid) REFERENCES plotobservations(id),
	CONSTRAINT associa_fkey02 FOREIGN KEY (lookupdataid) REFERENCES lookupdata(id)
);

CREATE TABLE taxa (
	id INTEGER NOT NULL PRIMARY KEY,
	taxonlistid INTEGER NOT NULL,
	taxongroupid INTEGER,
	taxonrankid INTEGER,
	parent INTEGER,
	scientificname VARCHAR NOT NULL,
	vernacularname VARCHAR,
	author VARCHAR,
	tv2speciesid INTEGER,
	tv2validid INTEGER,
	sbsspeciesid INTEGER,
	lettercode VARCHAR(7),
	issynonym INTEGER,
	uri VARCHAR,
	metadata VARCHAR,
	CONSTRAINT species_fkey01 FOREIGN KEY (taxonlistid) REFERENCES taxonlists(id),
	CONSTRAINT species_fkey02 FOREIGN KEY (taxongroupid) REFERENCES taxongroups(id),
	CONSTRAINT species_fkey03 FOREIGN KEY (taxonrankid) REFERENCES taxonranks(id)
);

CREATE TABLE traitdata (
	id INTEGER NOT NULL PRIMARY KEY,
	taxonid INTEGER NOT NULL,
	fieldid INTEGER NOT NULL,
	value VARCHAR NOT NULL,
	CONSTRAINT traitdata_fkey01 FOREIGN KEY (taxonid) REFERENCES taxa(id),
	CONSTRAINT traitdata_fkey02 FOREIGN KEY (fieldid) REFERENCES fields(id)
);

CREATE TABLE speciesobservations (
	id INTEGER NOT NULL PRIMARY KEY,
	plotobservationid INTEGER NOT NULL,
	taxonid INTEGER NOT NULL,
	vegetationlayerid INTEGER NOT NULL,
	covercodeid INTEGER NOT NULL,
	originaltaxonconcept VARCHAR,
	metadata VARCHAR,
	deleted BOOLEAN,
	CONSTRAINT speciesdata_fkey01 FOREIGN KEY (plotobservationid) REFERENCES plotobservations(id),
	CONSTRAINT speciesdata_fkey02 FOREIGN KEY (taxonid) REFERENCES taxa(id),
	CONSTRAINT speciesdata_fkey03 FOREIGN KEY (vegetationlayerid) REFERENCES vegetationlayers(id),
	CONSTRAINT speciesdata_fkey04 FOREIGN KEY (covercodeid) REFERENCES covercodes(id)
);

CREATE TABLE speciesobservationdata (
	id INTEGER NOT NULL PRIMARY KEY,
	speciesobservationid INTEGER NOT NULL,
	fieldid INTEGER NOT NULL,
	lookupdataid INTEGER,
	valuestring VARCHAR,
	valueinteger INTEGER,
	valuefloat REAL,
	deleted BOOLEAN,
	CONSTRAINT observationsspeciesdata_fkey01 FOREIGN KEY (speciesobservationid) REFERENCES speciesobservations(id),
	CONSTRAINT observationsspeciesdata_fkey02 FOREIGN KEY (fieldid) REFERENCES fields(id)
);

CREATE INDEX associa_index01 ON associa (plotobservationid);
CREATE UNIQUE INDEX associa_index02 ON associa (plotobservationid, lookupdataid);
CREATE UNIQUE INDEX covercodes_index01 ON covercodes (lookupdataid, code);
CREATE UNIQUE INDEX custodians_index01 ON custodians (name);
CREATE UNIQUE INDEX datasetgroups_index01 ON datasetgroups (name);
CREATE INDEX datasets_index01 ON datasets (datasetgroupid);
CREATE UNIQUE INDEX datasets_index02 ON datasets (name);
CREATE UNIQUE INDEX datasetgroups_index02 ON fieldgroups (name);
CREATE UNIQUE INDEX fields_index01 ON fields (fielddomainid, fieldname, fieldtype);
CREATE INDEX locations_index01 ON locations (the_geom);
CREATE UNIQUE INDEX lookupcaptions_index01 ON lookupcaptions (lookuptableid, columnno);
CREATE UNIQUE INDEX lookuptabledata_index01 ON lookupdata (lookuptableid, code, description1, description2, description3, description4);
CREATE UNIQUE INDEX lookuptables_index01 ON lookuptables (filename, description);
CREATE INDEX pictures_index01 ON pictures (plotobservationid);
CREATE INDEX plotobservationheaderdata_index01 ON plotobservationheaderdata (plotobservationid);
CREATE INDEX plotobservationheaderdata_index02 ON plotobservationheaderdata (fieldid);
CREATE INDEX plotobservations_index01 ON plotobservations (plotid);
CREATE UNIQUE INDEX plotobservations_index02 ON plotobservations (guid);
CREATE INDEX plots_index01 ON plots (datasetid);
CREATE INDEX profiledata_index01 ON profiledata (profileid, fieldid);
CREATE UNIQUE INDEX profiles_index01 ON profiles (name);
CREATE UNIQUE INDEX projects_index01 ON projects (name);
CREATE INDEX speciesobservationdata_index01 ON speciesobservationdata (speciesobservationid);
CREATE INDEX speciesobservationdata_index02 ON speciesobservationdata (fieldid);
CREATE INDEX observationsspecies_index01 ON speciesobservations (plotobservationid);
CREATE UNIQUE INDEX observationsspecies_index02 ON speciesobservations (plotobservationid, taxonid, vegetationlayerid, originaltaxonconcept);
CREATE INDEX observationsspecies_index03 ON speciesobservations (taxonid);
CREATE UNIQUE INDEX taxa_index01 ON taxa (taxonlistid, scientificname, tv2speciesid);
CREATE INDEX taxa_index02 ON taxa (tv2speciesid);
CREATE INDEX taxa_index03 ON taxa (taxonlistid);
CREATE INDEX taxa_index04 ON taxa (sbsspeciesid);
CREATE UNIQUE INDEX speciesgroups_index01 ON taxongroups (name);
CREATE UNIQUE INDEX floras_index01 ON taxonlists (name);
CREATE INDEX traitdata_index01 ON traitdata (taxonid);
CREATE UNIQUE INDEX traitdata_index02 ON traitdata (taxonid, fieldid);
CREATE UNIQUE INDEX units_index01 ON units (name);
`

type tv3FieldSeed struct {
	ID            int
	DomainID      int
	GroupID       any
	LookupTableID any
	UnitID        any
	Name          string
	FieldType     string
	Description   string
	DataTypeID    int
	Width         int
	Decimals      int
	Mandatory     int
}

const (
	tv3FieldReleveNR    = 1
	tv3FieldCountry     = 2
	tv3FieldCoverscale  = 3
	tv3FieldDate        = 4
	tv3FieldSurfArea    = 5
	tv3FieldAltitude    = 6
	tv3FieldExposition  = 7
	tv3FieldInclinatio  = 8
	tv3FieldAuthor      = 9
	tv3FieldRemarks     = 10
	tv3FieldLatitude    = 11
	tv3FieldLongitude   = 12
	tv3FieldVProPlot    = 13
	tv3FieldFieldNR     = 14
	tv3FieldProjectID   = 15
	tv3FieldZone        = 16
	tv3FieldSubzone     = 17
	tv3FieldSiteSeries  = 18
	tv3FieldSiteUnit    = 19
	tv3FieldMoisture    = 20
	tv3FieldNutrient    = 21
	tv3FieldMesoSlope   = 22
	tv3FieldSurfShape   = 23
	tv3FieldDrainage    = 24
	tv3FieldHumusForm   = 25
	tv3FieldLocation    = 26
	tv3FieldSiteNotes   = 27
	tv3FieldVegNotes    = 28
	tv3FieldSoilNotes   = 29
	tv3FieldSppHeight   = 30
	tv3FieldSppCollect  = 31
	tv3FieldSppVProLay  = 32
	tv3FieldSppVProCode = 33
)

var canonicalTV3Fields = []tv3FieldSeed{
	{tv3FieldReleveNR, 1, 1, nil, nil, "RELEVE_NR", "N", "Releve number", 2, 7, 0, 1},
	{tv3FieldCountry, 1, 1, 2, nil, "COUNTRY", "C", "Country code", 1, 2, 0, 0},
	{tv3FieldCoverscale, 1, 1, 1, nil, "COVERSCALE", "C", "Cover abundance scale", 1, 2, 0, 0},
	{tv3FieldDate, 1, 1, nil, nil, "DATE", "D", "Survey date", 4, 10, 0, 0},
	{tv3FieldSurfArea, 1, 2, nil, 4, "SURF_AREA", "N", "Plot surface area (m2)", 3, 8, 2, 0},
	{tv3FieldAltitude, 1, 2, nil, 2, "ALTITUDE", "N", "Elevation (m)", 2, 5, 0, 0},
	{tv3FieldExposition, 1, 2, nil, 3, "EXPOSITION", "N", "Aspect (degrees)", 2, 3, 0, 0},
	{tv3FieldInclinatio, 1, 2, nil, 3, "INCLINATIO", "N", "Slope gradient", 3, 5, 1, 0},
	{tv3FieldAuthor, 1, 1, nil, nil, "AUTHOR", "C", "Site surveyor", 1, 30, 0, 0},
	{tv3FieldRemarks, 1, 4, nil, nil, "REMARKS", "C", "General remarks", 1, 255, 0, 0},
	{tv3FieldLatitude, 1, 2, nil, 3, "LATITUDE", "N", "Latitude (decimal degrees)", 3, 13, 8, 0},
	{tv3FieldLongitude, 1, 2, nil, 3, "LONGITUDE", "N", "Longitude (decimal degrees)", 3, 13, 8, 0},
	{tv3FieldVProPlot, 1, 1, nil, nil, "VPRO_PLOT", "C", "VPro literal PlotNumber", 1, 7, 0, 0},
	{tv3FieldFieldNR, 1, 1, nil, nil, "FIELD_NR", "C", "VPro FieldNumber", 1, 50, 0, 0},
	{tv3FieldProjectID, 1, 1, nil, nil, "PROJECT_ID", "C", "VPro ProjectID", 1, 20, 0, 0},
	{tv3FieldZone, 1, 3, nil, nil, "ZONE", "C", "BEC Zone", 1, 4, 0, 0},
	{tv3FieldSubzone, 1, 3, nil, nil, "SUBZONE", "C", "BEC SubZone/Variant", 1, 8, 0, 0},
	{tv3FieldSiteSeries, 1, 3, nil, nil, "SITE_SERIES", "C", "BEC SiteSeries", 1, 5, 0, 0},
	{tv3FieldSiteUnit, 1, 3, nil, nil, "SITE_UNIT", "C", "Assigned SiteUnit", 1, 100, 0, 0},
	{tv3FieldMoisture, 1, 3, nil, nil, "MOISTURE", "C", "Relative soil moisture regime", 1, 3, 0, 0},
	{tv3FieldNutrient, 1, 3, nil, nil, "NUTRIENT", "C", "Relative soil nutrient regime", 1, 2, 0, 0},
	{tv3FieldMesoSlope, 1, 2, nil, nil, "MESO_SLOPE", "C", "Meso slope position", 1, 3, 0, 0},
	{tv3FieldSurfShape, 1, 2, nil, nil, "SURF_SHAPE", "C", "Surface shape", 1, 3, 0, 0},
	{tv3FieldDrainage, 1, 3, nil, nil, "DRAINAGE", "C", "Soil drainage", 1, 5, 0, 0},
	{tv3FieldHumusForm, 1, 3, nil, nil, "HUMUS_FORM", "C", "Humus form", 1, 4, 0, 0},
	{tv3FieldLocation, 1, 2, nil, nil, "LOCATION", "C", "Location description", 1, 255, 0, 0},
	{tv3FieldSiteNotes, 1, 4, nil, nil, "SITE_NOTES", "C", "VPro SiteNotes", 1, 255, 0, 0},
	{tv3FieldVegNotes, 1, 4, nil, nil, "VEG_NOTES", "C", "VPro VegNotes", 1, 255, 0, 0},
	{tv3FieldSoilNotes, 1, 4, nil, nil, "SOIL_NOTES", "C", "VPro SoilNotes", 1, 255, 0, 0},
	{tv3FieldSppHeight, 2, nil, nil, 2, "HEIGHT", "N", "Species stratum height (m)", 3, 6, 2, 0},
	{tv3FieldSppCollect, 2, nil, nil, nil, "COLLECTED", "C", "Voucher collection status", 1, 1, 0, 0},
	{tv3FieldSppVProLay, 2, nil, nil, nil, "VPRO_LAYER", "C", "VPro sublayer code", 1, 8, 0, 0},
	{tv3FieldSppVProCode, 2, nil, nil, nil, "VPRO_CODE", "C", "VPro 8-char species code", 1, 8, 0, 0},
}

func formatCoverCodeKey(cov float64) string {
	return strconv.FormatFloat(cov, 'f', -1, 64)
}
