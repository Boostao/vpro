package interchange

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"

	"golang.org/x/text/encoding/charmap"
)

func normalizeTVDateString(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" || strings.EqualFold(s, "null") {
		return ""
	}
	if len(s) == 8 {
		allDigits := true
		for i := 0; i < 8; i++ {
			if s[i] < '0' || s[i] > '9' {
				allDigits = false
				break
			}
		}
		if allDigits {
			y := s[0:4]
			m := s[4:6]
			d := s[6:8]
			if m == "00" {
				return y
			}
			if d == "00" {
				return y + "-" + m
			}
			return y + "-" + m + "-" + d
		}
	}
	if len(s) == 10 && s[4] == '/' && s[7] == '/' {
		return strings.ReplaceAll(s, "/", "-")
	}
	return s
}

func formatTVStandardDateAttr(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" {
		return ""
	}
	for _, layout := range []string{"2006-01-02", "2006/01/02", "2006-01-02 15:04:05", time.RFC3339} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.Format("20060102")
		}
	}
	if len(s) <= 8 {
		return s
	}
	return sqlutil.TruncateUTF16(s, 8)
}

func defaultBraunBlanquetMidpoint(code string) (float64, bool) {
	switch strings.ToLower(strings.TrimSpace(code)) {
	case "r":
		return 0.1, true
	case "+":
		return 0.5, true
	case "x":
		return 1.0, true
	case "1":
		return 3.0, true
	case "2m":
		return 4.0, true
	case "2a":
		return 8.75, true
	case "2", "2b":
		return 18.75, true
	case "3":
		return 37.5, true
	case "4":
		return 62.5, true
	case "5":
		return 87.5, true
	default:
		return 0, false
	}
}

func turboVegXMLCharsetReader(charset string, input io.Reader) (io.Reader, error) {
	norm := strings.ToLower(strings.TrimSpace(charset))
	norm = strings.ReplaceAll(norm, "_", "-")
	switch norm {
	case "", "utf-8", "utf8", "us-ascii", "ascii":
		return input, nil
	case "windows-1252", "cp1252", "ansi":
		return charmap.Windows1252.NewDecoder().Reader(input), nil
	case "windows-1250", "cp1250":
		return charmap.Windows1250.NewDecoder().Reader(input), nil
	case "iso-8859-1", "iso8859-1", "latin1", "latin-1":
		return charmap.ISO8859_1.NewDecoder().Reader(input), nil
	case "iso-8859-15", "iso8859-15", "latin9":
		return charmap.ISO8859_15.NewDecoder().Reader(input), nil
	default:
		return nil, fmt.Errorf("unsupported TurboVeg XML charset %q", charset)
	}
}

// Wire structs for official Turboveg <Plot_package> Standard XML.

type xmlPlotPackageDoc struct {
	XMLName              xml.Name              `xml:"Plot_package"`
	UserName             string                `xml:"UserName,attr"`
	EmailAddress         string                `xml:"EmailAddress,attr"`
	TurbovegVersion      string                `xml:"TurbovegVersion,attr"`
	Dictionary           string                `xml:"Dictionary,attr"`
	SpeciesList          string                `xml:"SpeciesList,attr"`
	Description          string                `xml:"Description,attr"`
	ShareWithMembersOnly string                `xml:"ShareWithMembersOnly,attr"`
	CreationDate         string                `xml:"CreationDate,attr"`
	Plots                xmlPlotPackagePlots   `xml:"Plots"`
	LookupTables         xmlPlotPackageLookups `xml:"Lookup_tables"`
	Template             xmlPlotPackageTmpl    `xml:"Template"`
	Metadata             xmlPlotPackageMeta    `xml:"Metadata"`
}

type xmlPlotPackagePlots struct {
	Plot []xmlPkgPlot `xml:"Plot"`
}

type xmlPkgPlot struct {
	Database   string            `xml:"database,attr"`
	ReleveNR   int               `xml:"releve_nr,attr"`
	GUID       string            `xml:"guid,attr"`
	CreateUser string            `xml:"create_user,attr"`
	CreateDate string            `xml:"create_date,attr"`
	ModifyUser string            `xml:"modify_user,attr"`
	ModifyDate string            `xml:"modify_date,attr"`
	NDFFQual   string            `xml:"ndff_qual,attr"`
	HeaderData xmlPkgHeaderData  `xml:"header_data"`
	SpeciesDat xmlPkgSpeciesData `xml:"species_data"`
}

type xmlPkgHeaderData struct {
	Standard xmlPkgHeaderStd `xml:"standard_record"`
	UDFs     []xmlPkgUDF     `xml:"udf_record"`
}

type xmlPkgHeaderStd struct {
	ReleveNR   int    `xml:"releve_nr,attr"`
	Country    string `xml:"country,attr,omitempty"`
	Coverscale string `xml:"coverscale,attr"`
	Date       string `xml:"date,attr,omitempty"`
	SurfArea   string `xml:"surf_area,attr,omitempty"`
	Altitude   string `xml:"altitude,attr,omitempty"`
	Exposition string `xml:"exposition,attr,omitempty"`
	Inclinatio string `xml:"inclinatio,attr,omitempty"`
	Author     string `xml:"author,attr,omitempty"`
	Project    string `xml:"project,attr,omitempty"`
	Syntaxon   string `xml:"syntaxon,attr,omitempty"`
	Remarks    string `xml:"remarks,attr,omitempty"`
}

type xmlPkgUDF struct {
	IsPredefined string `xml:"ispredefined,attr"`
	Name         string `xml:"name,attr"`
	Type         string `xml:"type,attr"`
	Len          int    `xml:"len,attr"`
	Dec          int    `xml:"dec,attr"`
	Value        string `xml:"value,attr"`
}

type xmlPkgSpeciesData struct {
	Species []xmlPkgSpeciesEntry `xml:"species"`
}

type xmlPkgSpeciesEntry struct {
	Standard xmlPkgSpeciesStd `xml:"standard_record"`
	UDFs     []xmlPkgUDF      `xml:"udf_record"`
}

type xmlPkgSpeciesStd struct {
	NR    int    `xml:"nr,attr"`
	Cover string `xml:"cover,attr"`
	Layer int    `xml:"layer,attr"`
}

type xmlPlotPackageLookups struct {
	CoverscaleList []xmlCoverscaleRecord `xml:"Coverscale_list>coverscale_record"`
	CountryList    []xmlSimpleLookupRec  `xml:"Country_list>country_record"`
	AuthorList     []xmlSimpleLookupRec  `xml:"Author_list>author_record"`
	ProjectList    []xmlSimpleLookupRec  `xml:"Project_list>project_record"`
	SyntaxonList   []xmlSimpleLookupRec  `xml:"Syntaxon_list>syntaxon_record"`
	SpeciesList    []xmlSpeciesRecord    `xml:"Species_list>species_record"`
}

type xmlCoverscaleRecord struct {
	Code        string              `xml:"code"`
	Description string              `xml:"description"`
	DataRecords []xmlCoverscaleData `xml:"data_record"`
}

type xmlCoverscaleData struct {
	Code       string `xml:"code,attr"`
	Percentage string `xml:"percentage,attr"`
}

type xmlSimpleLookupRec struct {
	Code        string `xml:"code,attr"`
	Description string `xml:"description,attr"`
}

type xmlSpeciesRecord struct {
	NR          int    `xml:"nr,attr"`
	Code        string `xml:"code,attr"`
	Name        string `xml:"name,attr"`
	Author      string `xml:"author,attr"`
	ValidNR     string `xml:"valid_nr,attr"`
	ValidName   string `xml:"valid_name,attr"`
	ValidAuthor string `xml:"valid_author,attr"`
	Synonym     string `xml:"synonym,attr"`
	NativeName  string `xml:"nativename,attr"`
	VProCode    string `xml:"vpro_code,attr,omitempty"`
}

type xmlPlotPackageTmpl struct {
	Files    []xmlTemplateFileRec `xml:"Files>record"`
	Dbasedic []xmlDbasedicRec     `xml:"Dbasedic>record"`
}

type xmlTemplateFileRec struct {
	FileNR     int    `xml:"file_nr,attr"`
	FileName   string `xml:"file_name,attr"`
	FileDesc   string `xml:"file_desc,attr"`
	FieldIndex int    `xml:"fieldindex,attr"`
	FileEdit   string `xml:"file_edit,attr"`
	ArrayPos   int    `xml:"array_pos,attr"`
	ProgPath   string `xml:"progpath,attr"`
	PrintIt    string `xml:"print_it,attr"`
}

type xmlDbasedicRec struct {
	FileNR    int    `xml:"file_nr,attr"`
	FieldName string `xml:"field_name,attr"`
	FieldType string `xml:"field_type,attr"`
	FieldLen  int    `xml:"field_len,attr"`
	FieldDec  int    `xml:"field_dec,attr"`
	FieldPict string `xml:"field_pict,attr"`
	FieldTran string `xml:"field_tran,attr"`
	FieldEval string `xml:"field_eval,attr"`
	FieldEsel string `xml:"field_esel,attr"`
	FieldWhen string `xml:"field_when,attr"`
	FieldCarg string `xml:"field_carg,attr"`
	FieldDesc string `xml:"field_desc,attr"`
	FieldMenu string `xml:"field_menu,attr"`
	FieldSel  int    `xml:"field_sel,attr"`
	FieldList int    `xml:"field_list,attr"`
}

type xmlPlotPackageMeta struct {
	Records []string `xml:"record"`
}

var canonicalTemplateFiles = []xmlTemplateFileRec{
	{1, "tvflora", "FLORA", 0, "false", 0, "false", "false"},
	{2, "tvhabita", "HEADER DATA", 0, "false", 0, "false", "false"},
	{3, "tvabund", "SPECIES DATA", 0, "false", 0, "false", "false"},
	{4, "remarks", "REMARKS", 1, "false", 0, "false", "false"},
	{5, "tvrefenc", "REFERENCES", 1, "true", 0, "true", "false"},
	{6, "tvscale", "COVER SCALES", 1, "true", 1, "true", "true"},
	{7, "country", "COUNTRIES", 2, "true", 2, "true", "true"},
	{8, "tvauthor", "AUTHORS", 2, "true", 3, "true", "true"},
	{9, "tvprojct", "PROJECTS", 1, "true", 4, "true", "true"},
	{10, "syntaxa", "SYNTAXA", 1, "true", 5, "true", "true"},
	{11, "exposit", "ASPECT", 0, "true", 6, "true", "true"},
}

var canonicalDbasedicRecords = []xmlDbasedicRec{
	{1, "SPECIES_NR", "N", 5, 0, "@ 99999", "", "", "", "", "", "Species number code", "", 0, 0},
	{1, "LETTERCODE", "C", 7, 0, "", "", "", "", "", "", "Species letter code", "", 0, 0},
	{1, "SHORTNAME", "C", 22, 0, "", "", "", "", "", "", "Short name (correct)", "", 0, 0},
	{1, "ABBREVIAT", "C", 37, 0, "", "", "", "", "", "", "Species name", "", 0, 0},
	{1, "SYNONYM", "L", 1, 0, "", "", "", "", "", "", "", "", 0, 0},
	{2, "RELEVE_NR", "N", 6, 0, "@ 999999", "", "", "", "", "", "Releve number", "Releve number", 3, 0},
	{2, "COUNTRY", "C", 2, 0, "@ !!", "", "", "", "", "", "Country code", "Country code", 2, 2},
	{2, "REFERENCE", "C", 6, 0, "@ ######", "", "", "", "", "", "Biblio reference", "Biblioreferen.", 3, -1},
	{2, "COVERSCALE", "C", 2, 0, "@ ##", "", "", "", "", "", "Cover abundance scale", "Cover scale", 2, 1},
	{2, "PROJECT", "C", 3, 0, "@ ###", "", "", "", "", "", "Project code", "Project code", 2, 4},
	{2, "AUTHOR", "C", 4, 0, "@ ####", "", "", "", "", "", "Author code", "Author code", 2, 3},
	{2, "DATE", "C", 8, 0, "@R ####/##/##", "@R ####/##/##", "", "", "", "", "Date (year/month/day)", "Date", 3, 0},
	{2, "SYNTAXON", "C", 7, 0, "@ ##!!##X", "", "", "", "", "", "Syntaxon code", "Syntaxon code", 2, 5},
	{2, "SURF_AREA", "N", 8, 2, "@Z 99999.99", "", "", "", "", "", "Releve area (m2)", "Releve area", 1, 0},
	{2, "ALTITUDE", "C", 4, 0, "@ ####", "", "", "", "", "", "Altitude (m)", "Altitude", 1, 0},
	{2, "EXPOSITION", "C", 3, 0, "@ ###", "", "", "", "", "", "Aspect (degrees)", "Aspect", 1, 6},
	{2, "INCLINATIO", "C", 2, 0, "@ ##", "", "", "", "", "", "Slope (degrees)", "Slope", 1, 0},
	{2, "REMARKS", "C", 56, 0, "@S56", "", "", "", "", "", "Remarks", "Remarks", 4, 0},
	{3, "RELEVE_NR", "N", 6, 0, "", "", "", "", "", "", "", "", 0, 0},
	{3, "SPECIES_NR", "N", 5, 0, "", "", "", "", "", "", "", "", 0, 0},
	{3, "COVER_CODE", "C", 2, 0, "", "", "", "", "", "", "", "", 0, 0},
	{3, "LAYER", "N", 1, 0, "", "", "", "", "", "", "", "", 0, 0},
	{4, "RELEVE_NR", "N", 6, 0, "", "", "", "", "", "", "", "", 0, 0},
	{4, "REMARKS", "C", 25, 0, "", "", "", "", "", "", "", "", 0, 0},
	{5, "REFERENCE", "C", 6, 0, "@ 999999", "", "", "", "", "", "Reference", "", 0, 0},
	{5, "AUTHOR", "C", 80, 0, "@S59", "", "", "", "", "", "Author of publication", "", 0, 0},
	{5, "YEAR", "C", 4, 0, "@ 9999", "", "", "", "", "", "Year", "", 0, 0},
	{5, "TITLE", "C", 200, 0, "@S59", "", "", "", "", "", "Title", "", 0, 0},
	{5, "PUBLISHED", "C", 200, 0, "@S59", "", "", "", "", "", "Published in...", "", 0, 0},
	{6, "SCALE_NR", "C", 2, 0, "@ ##", "", "", "", "", "", "Cover scale code", "", 0, 0},
	{6, "SCALE_NAME", "C", 22, 0, "", "", "", "", "", "", "Cover scale name", "", 0, 0},
	{6, "SCALE_CODE", "C", 6, 0, "", "", "", "", "", "", "Cover scale abbr.", "", 0, 0},
	{7, "CODE", "C", 2, 0, "@ !!", "", "", "", "", "", "Country code", "", 0, 0},
	{7, "COUNTRY", "C", 25, 0, "", "", "", "", "", "", "Country name", "", 0, 0},
	{8, "AUTH_CODE", "C", 4, 0, "@ ####", "", "", "", "", "", "Author code", "", 0, 0},
	{8, "AUTH_NAME", "C", 30, 0, "", "", "", "", "", "", "Author name", "", 0, 0},
	{9, "PROJECT", "C", 3, 0, "@ ###", "", "", "", "", "", "Project code", "", 0, 0},
	{9, "PROJ_NAME", "C", 30, 0, "", "", "", "", "", "", "Project name", "", 0, 0},
	{10, "CODE", "C", 7, 0, "@ ##!!99!", "", "", "", "", "", "Syntaxon code", "", 0, 0},
	{10, "SYNTAXON", "C", 56, 0, "", "", "", "", "", "", "Syntaxon name", "", 0, 0},
	{11, "EXPOSITION", "C", 3, 0, "@ ###", "", "", "", "", "", "Exposition (degrees)", "", 0, 0},
	{11, "CODE", "C", 3, 0, "@ !!!", "", "", "", "", "", "Exposition", "", 0, 0},
}

func makeStringUDF(name, val string, maxLen int) (xmlPkgUDF, bool) {
	if strings.TrimSpace(val) == "" {
		return xmlPkgUDF{}, false
	}
	l := len(val)
	if l < maxLen {
		l = maxLen
	}
	return xmlPkgUDF{
		IsPredefined: "false",
		Name:         name,
		Type:         "C",
		Len:          l,
		Dec:          0,
		Value:        val,
	}, true
}

func makeFloatUDF(name string, val *float64, width, dec int) (xmlPkgUDF, bool) {
	if val == nil {
		return xmlPkgUDF{}, false
	}
	return xmlPkgUDF{
		IsPredefined: "false",
		Name:         name,
		Type:         "N",
		Len:          width,
		Dec:          dec,
		Value:        strconv.FormatFloat(*val, 'f', -1, 64),
	}, true
}

func allocateUniqueLookupCode(fullValue, baseSeed string, maxUnits int, codeByValue, descByCode map[string]string) string {
	normFull := strings.TrimSpace(fullValue)
	if existing, ok := codeByValue[normFull]; ok {
		return existing
	}
	cand := sqlutil.TruncateUTF16(strings.TrimSpace(baseSeed), maxUnits)
	if cand != "" {
		if prevDesc, used := descByCode[cand]; !used || prevDesc == normFull {
			codeByValue[normFull] = cand
			descByCode[cand] = normFull
			return cand
		}
	}
	for seq := 1; ; seq++ {
		suffix := strconv.FormatInt(int64(seq), 36)
		suffix = strings.ToUpper(suffix)
		var disambig string
		if maxPrefix := maxUnits - len(suffix); maxPrefix > 0 {
			prefix := sqlutil.TruncateUTF16(strings.TrimSpace(baseSeed), maxPrefix)
			disambig = prefix + suffix
		} else {
			disambig = sqlutil.TruncateUTF16(strings.Repeat("0", max(0, maxUnits-len(suffix)))+suffix, maxUnits)
		}
		if disambig == "" {
			continue
		}
		if prevDesc, used := descByCode[disambig]; !used || prevDesc == normFull {
			codeByValue[normFull] = disambig
			descByCode[disambig] = normFull
			return disambig
		}
	}
}

func encodeTurboVegXML(ctx context.Context, ds tvDataset) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	projName := strings.TrimSpace(ds.ProjectName)
	if projName == "" {
		projName = "VProExport"
	}
	todayStr := time.Now().UTC().Format("02/01/2006")
	projCode := strings.ToUpper(sqlutil.TruncateUTF16(projName, 3))
	if projCode == "" {
		projCode = "VPR"
	}

	doc := xmlPlotPackageDoc{
		UserName:             "VPro",
		EmailAddress:         "",
		TurbovegVersion:      "3.0",
		Dictionary:           "vpro_bec_dict",
		SpeciesList:          "BCPlantTaxonomy",
		Description:          "VPro BEC Export",
		ShareWithMembersOnly: "no",
		CreationDate:         todayStr,
		Plots: xmlPlotPackagePlots{
			Plot: make([]xmlPkgPlot, len(ds.Plots)),
		},
		Template: xmlPlotPackageTmpl{
			Files:    canonicalTemplateFiles,
			Dbasedic: canonicalDbasedicRecords,
		},
		Metadata: xmlPlotPackageMeta{
			Records: []string{"Generated by VPro (B.C. Ministry of Forests BEC Program)"},
		},
	}

	coverSet := map[string]float64{"r": 0.05, "+": 0.50}
	authorCodeByFull := map[string]string{}
	authorSet := map[string]string{}
	syntaxonCodeByFull := map[string]string{}
	syntaxonSet := map[string]string{}

	for i, pb := range ds.Plots {
		if i%128 == 0 {
			runtime.Gosched()
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		h := pb.Header
		releveNR := h.PlotID
		if releveNR <= 0 {
			releveNR = i + 1
		}
		guid := strings.ToUpper(strings.Trim(strings.TrimSpace(h.GUID), "{}"))
		if guid == "" {
			guid = strings.ToUpper(newTurboVegUUID())
		}

		dbName := strings.TrimSpace(h.ProjectID)
		if dbName == "" {
			dbName = projName
		}

		std := xmlPkgHeaderStd{
			ReleveNR:   releveNR,
			Country:    "CA",
			Coverscale: "00",
			Date:       formatTVStandardDateAttr(h.Date),
			Project:    projCode,
		}
		if h.PlotSize != nil {
			std.SurfArea = strconv.FormatFloat(*h.PlotSize, 'f', 2, 64)
		}
		if h.Elevation != nil {
			std.Altitude = strconv.Itoa(*h.Elevation)
		}
		if h.Aspect != nil {
			std.Exposition = strconv.Itoa(*h.Aspect)
		}
		if h.Slope != nil {
			std.Inclinatio = strconv.FormatFloat(*h.Slope, 'f', -1, 64)
		}
		if surv := strings.TrimSpace(h.Surveyor); surv != "" {
			seed := strings.ToUpper(strings.Join(strings.Fields(surv), ""))
			std.Author = allocateUniqueLookupCode(surv, seed, 4, authorCodeByFull, authorSet)
		}
		if su := strings.TrimSpace(h.SiteUnit); su != "" {
			seed := strings.Join(strings.Fields(su), "")
			std.Syntaxon = allocateUniqueLookupCode(su, seed, 7, syntaxonCodeByFull, syntaxonSet)
		}
		if strings.TrimSpace(h.SiteNotes) != "" {
			std.Remarks = sqlutil.TruncateUTF16(strings.TrimSpace(h.SiteNotes), 56)
		}

		udfs := make([]xmlPkgUDF, 0, 20)
		appendStr := func(name, val string, maxLen int) {
			if u, ok := makeStringUDF(name, val, maxLen); ok {
				udfs = append(udfs, u)
			}
		}
		appendFlt := func(name string, val *float64, width, dec int) {
			if u, ok := makeFloatUDF(name, val, width, dec); ok {
				udfs = append(udfs, u)
			}
		}

		appendStr("vpro_plot_number", h.PlotNumber, 7)
		appendStr("vpro_date", h.Date, 40)
		appendStr("field_number", h.FieldNumber, 50)
		appendStr("project_id", h.ProjectID, 20)
		appendStr("surveyor", h.Surveyor, 30)
		appendFlt("latitude", h.Latitude, 13, 8)
		appendFlt("longitude", h.Longitude, 13, 8)
		appendStr("zone", h.Zone, 4)
		appendStr("subzone", h.SubZone, 8)
		appendStr("site_series", h.SiteSeries, 5)
		appendStr("site_unit", h.SiteUnit, 100)
		appendStr("moisture_regime", h.MoistureRegime, 3)
		appendStr("nutrient_regime", h.NutrientRegime, 2)
		appendStr("meso_slope_position", h.MesoSlopePosition, 3)
		appendStr("surface_shape", h.SurfaceShape, 3)
		appendStr("soil_drainage", h.SoilDrainage, 5)
		appendStr("humus_form", h.HumusForm, 4)
		appendStr("location", h.Location, 255)
		appendStr("site_notes", h.SiteNotes, 255)
		appendStr("veg_notes", h.VegNotes, 255)
		appendStr("soil_notes", h.SoilNotes, 255)

		sppEntries := make([]xmlPkgSpeciesEntry, len(pb.Observations))
		for j, o := range pb.Observations {
			tvLayer := o.TVLayerID
			if tvLayer < 0 || tvLayer > 10 {
				tvLayer = 6
			}
			covStr := formatCoverCodeKey(o.Cover)
			coverSet[covStr] = o.Cover

			sUDFs := make([]xmlPkgUDF, 0, 4)
			if u, ok := makeStringUDF("vpro_code", o.SpeciesCode, 8); ok {
				sUDFs = append(sUDFs, u)
			}
			if u, ok := makeStringUDF("vpro_layer", o.VProLayer, 8); ok {
				sUDFs = append(sUDFs, u)
			}
			if u, ok := makeFloatUDF("height", o.Height, 6, 2); ok {
				sUDFs = append(sUDFs, u)
			}
			if u, ok := makeStringUDF("collected", o.Collected, 1); ok {
				sUDFs = append(sUDFs, u)
			}

			sppEntries[j] = xmlPkgSpeciesEntry{
				Standard: xmlPkgSpeciesStd{
					NR:    o.SpeciesNR,
					Cover: covStr,
					Layer: tvLayer,
				},
				UDFs: sUDFs,
			}
		}

		doc.Plots.Plot[i] = xmlPkgPlot{
			Database:   dbName,
			ReleveNR:   releveNR,
			GUID:       "{" + guid + "}",
			CreateUser: "VPro",
			CreateDate: todayStr,
			ModifyUser: "",
			ModifyDate: "",
			NDFFQual:   "0",
			HeaderData: xmlPkgHeaderData{
				Standard: std,
				UDFs:     udfs,
			},
			SpeciesDat: xmlPkgSpeciesData{
				Species: sppEntries,
			},
		}
	}

	// Build Lookup_tables
	covKeys := make([]string, 0, len(coverSet))
	for k := range coverSet {
		covKeys = append(covKeys, k)
	}
	slices.SortFunc(covKeys, func(a, b string) int {
		va, vb := coverSet[a], coverSet[b]
		if va < vb {
			return -1
		}
		if va > vb {
			return 1
		}
		return strings.Compare(a, b)
	})
	covData := make([]xmlCoverscaleData, len(covKeys))
	for i, k := range covKeys {
		covData[i] = xmlCoverscaleData{
			Code:       k,
			Percentage: strconv.FormatFloat(coverSet[k], 'f', -1, 64),
		}
	}
	doc.LookupTables.CoverscaleList = []xmlCoverscaleRecord{
		{
			Code:        "00",
			Description: "Percentage (%)",
			DataRecords: covData,
		},
	}
	doc.LookupTables.CountryList = []xmlSimpleLookupRec{
		{Code: "CA", Description: "Canada"},
	}
	doc.LookupTables.ProjectList = []xmlSimpleLookupRec{
		{Code: projCode, Description: projName},
	}
	authorKeys := make([]string, 0, len(authorSet))
	for k := range authorSet {
		authorKeys = append(authorKeys, k)
	}
	slices.Sort(authorKeys)
	for _, k := range authorKeys {
		doc.LookupTables.AuthorList = append(doc.LookupTables.AuthorList, xmlSimpleLookupRec{Code: k, Description: authorSet[k]})
	}
	sxKeys := make([]string, 0, len(syntaxonSet))
	for k := range syntaxonSet {
		sxKeys = append(sxKeys, k)
	}
	slices.Sort(sxKeys)
	for _, k := range sxKeys {
		doc.LookupTables.SyntaxonList = append(doc.LookupTables.SyntaxonList, xmlSimpleLookupRec{Code: k, Description: syntaxonSet[k]})
	}

	doc.LookupTables.SpeciesList = make([]xmlSpeciesRecord, len(ds.Species))
	for i, sp := range ds.Species {
		sci := strings.TrimSpace(sp.ScientificName)
		if sci == "" {
			sci = sp.SpeciesCode
		}
		letter := sqlutil.TruncateUTF16(strings.TrimSpace(sp.LetterCode), 7)
		if letter == "" {
			letter = sqlutil.TruncateUTF16(strings.TrimSpace(sp.SpeciesCode), 7)
		}
		doc.LookupTables.SpeciesList[i] = xmlSpeciesRecord{
			NR:         sp.SpeciesNR,
			Code:       letter,
			Name:       sci,
			Author:     sp.Authority,
			ValidNR:    strconv.Itoa(sp.SpeciesNR),
			Synonym:    "no",
			NativeName: sp.EnglishName,
			VProCode:   sp.SpeciesCode,
		}
	}

	var buf bytes.Buffer
	buf.WriteString(xml.Header)
	enc := xml.NewEncoder(&buf)
	enc.Indent("", "  ")
	if err := enc.Encode(doc); err != nil {
		return nil, err
	}
	buf.WriteByte('\n')
	return buf.Bytes(), nil
}
