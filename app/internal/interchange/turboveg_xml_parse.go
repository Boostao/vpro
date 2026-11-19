package interchange

import (
	"bufio"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"runtime"
	"strconv"
	"strings"
)

func cleanTVXMLAttr(val string) string {
	t := strings.TrimSpace(val)
	if strings.EqualFold(t, "null") {
		return ""
	}
	return t
}

func attrMapFromElement(se xml.StartElement) map[string]string {
	m := make(map[string]string, len(se.Attr))
	for _, a := range se.Attr {
		m[strings.ToLower(a.Name.Local)] = cleanTVXMLAttr(a.Value)
	}
	return m
}

type rawXMLSpeciesObs struct {
	nr        int
	rawCover  string
	rawLayer  string
	vproCode  string
	vproLayer string
	height    *float64
	collected string
}

type rawXMLPlot struct {
	header          tvPlotHeader
	coverscale      string
	authorCode      string
	projectCode     string
	syntaxonCode    string
	expositionRaw   string
	hasExplicitPlot bool
	hasExplicitAuth bool
	hasExplicitProj bool
	hasExplicitSU   bool
	hasExplicitNote bool
	remarksFallback string
	observations    []rawXMLSpeciesObs
}

type rawXMLSpeciesLookup struct {
	nr        int
	code      string
	name      string
	validNR   int
	validName string
	synonym   bool
	vproCode  string
}

type rawXMLPackageLookups struct {
	rawPlots    []rawXMLPlot
	sppLookup   map[int]rawXMLSpeciesLookup
	sppOrder    []int
	coverscales map[string]map[string]float64
	authors     map[string]string
	projects    map[string]string
	expositions map[string]int
}

type resolvedXMLTaxon struct {
	code  string
	woody bool
}

func parseFiniteXMLFloatPtr(raw string) *float64 {
	if raw == "" {
		return nil
	}
	if f, err := strconv.ParseFloat(raw, 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
		return &f
	}
	return nil
}

func parseRoundedXMLIntPtr(raw string) *int {
	if f := parseFiniteXMLFloatPtr(raw); f != nil {
		iv := int(math.Round(*f))
		return &iv
	}
	return nil
}

func decodeRawXMLPlot(dec *xml.Decoder, se xml.StartElement, plotSeq int) (rawXMLPlot, error) {
	pAttrs := attrMapFromElement(se)
	releveNR, _ := strconv.Atoi(pAttrs["releve_nr"])
	if releveNR <= 0 {
		releveNR = plotSeq
	}
	rp := rawXMLPlot{
		coverscale:  "00",
		projectCode: pAttrs["database"],
		header:      tvPlotHeader{PlotID: releveNR},
	}

	depth := 1
	inHeaderData, inSpeciesData := false, false
	var curSpp *rawXMLSpeciesObs

	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return rawXMLPlot{}, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			depth++
			applyPlotStartElement(t, &rp, &inHeaderData, &inSpeciesData, &curSpp)
		case xml.EndElement:
			applyPlotEndElement(t, &rp, &inHeaderData, &inSpeciesData, &curSpp)
			depth--
		}
	}

	if !rp.hasExplicitPlot && strings.TrimSpace(rp.header.PlotNumber) == "" && releveNR > 0 {
		rp.header.PlotNumber = strconv.Itoa(releveNR)
	}
	return rp, nil
}

func applyPlotStartElement(
	t xml.StartElement,
	rp *rawXMLPlot,
	inHeaderData, inSpeciesData *bool,
	curSpp **rawXMLSpeciesObs,
) {
	tag := strings.ToLower(t.Name.Local)
	switch {
	case tag == "header_data":
		*inHeaderData = true
	case tag == "species_data":
		*inSpeciesData = true
	case *inHeaderData && tag == "standard_record":
		applyXMLHeaderStandardRecord(rp, attrMapFromElement(t))
	case *inHeaderData && tag == "udf_record":
		applyXMLHeaderUDFRecord(rp, attrMapFromElement(t))
	case *inSpeciesData && tag == "species":
		*curSpp = &rawXMLSpeciesObs{}
	case *inSpeciesData && *curSpp != nil && tag == "standard_record":
		a := attrMapFromElement(t)
		(*curSpp).nr, _ = strconv.Atoi(a["nr"])
		(*curSpp).rawCover = a["cover"]
		(*curSpp).rawLayer = a["layer"]
	case *inSpeciesData && *curSpp != nil && tag == "udf_record":
		applyXMLSpeciesUDFRecord(*curSpp, attrMapFromElement(t))
	}
}

func applyPlotEndElement(
	t xml.EndElement,
	rp *rawXMLPlot,
	inHeaderData, inSpeciesData *bool,
	curSpp **rawXMLSpeciesObs,
) {
	switch strings.ToLower(t.Name.Local) {
	case "header_data":
		*inHeaderData = false
	case "species_data":
		*inSpeciesData = false
	case "species":
		if *curSpp != nil {
			rp.observations = append(rp.observations, **curSpp)
			*curSpp = nil
		}
	}
}

func applyXMLHeaderStandardRecord(rp *rawXMLPlot, a map[string]string) {
	if rStr := a["releve_nr"]; rStr != "" && rp.header.PlotNumber == "" {
		rp.header.PlotNumber = rStr
	}
	if cs := a["coverscale"]; cs != "" {
		rp.coverscale = cs
	} else if cs2 := a["cover_scale"]; cs2 != "" {
		rp.coverscale = cs2
	}
	if d := a["date"]; d != "" && rp.header.Date == "" {
		rp.header.Date = normalizeTVDateString(d)
	}
	if f := parseFiniteXMLFloatPtr(a["surf_area"]); f != nil {
		rp.header.PlotSize = f
	}
	if iv := parseRoundedXMLIntPtr(a["altitude"]); iv != nil {
		rp.header.Elevation = iv
	}
	if exp := a["exposition"]; exp != "" {
		rp.expositionRaw = exp
		if deg, ok := parseCompassAspectDegrees(exp); ok {
			rp.header.Aspect = &deg
		}
	}
	if f := parseFiniteXMLFloatPtr(a["inclinatio"]); f != nil {
		rp.header.Slope = f
	}
	if f := parseFiniteXMLFloatPtr(a["latitude"]); f != nil {
		rp.header.Latitude = f
	}
	if f := parseFiniteXMLFloatPtr(a["longitude"]); f != nil {
		rp.header.Longitude = f
	}
	applyXMLHeaderStandardTextCodes(rp, a)
}

func applyXMLHeaderStandardTextCodes(rp *rawXMLPlot, a map[string]string) {
	if nrTab := a["nr_in_tab"]; nrTab != "" && rp.header.FieldNumber == "" {
		rp.header.FieldNumber = nrTab
	}
	if auth := a["author"]; auth != "" {
		rp.authorCode = auth
	}
	if prj := a["project"]; prj != "" {
		rp.projectCode = prj
	}
	if sx := a["syntaxon"]; sx != "" {
		rp.syntaxonCode = sx
	}
	if rem := a["remarks"]; rem != "" {
		rp.remarksFallback = rem
	}
}

func applyXMLHeaderUDFRecord(rp *rawXMLPlot, a map[string]string) {
	uName := strings.ToLower(strings.TrimSpace(a["name"]))
	uVal := a["value"]
	if uName == "" || uVal == "" {
		return
	}
	if applyXMLHeaderUDFIdentityAndNumeric(rp, uName, uVal) {
		return
	}
	applyXMLHeaderUDFEcologicalText(rp, uName, uVal)
}

func applyXMLHeaderUDFIdentityAndNumeric(rp *rawXMLPlot, uName, uVal string) bool {
	switch uName {
	case "vpro_plot_number", "vpro_plot", "plot_number":
		rp.header.PlotNumber = uVal
		rp.hasExplicitPlot = true
	case "vpro_date":
		rp.header.Date = uVal
	case "date":
		rp.header.Date = normalizeTVDateString(uVal)
	case "field_number", "field_nr":
		rp.header.FieldNumber = uVal
	case "project_id":
		rp.header.ProjectID = uVal
		rp.hasExplicitProj = true
	case "surveyor", "site_surveyor":
		rp.header.Surveyor = uVal
		rp.hasExplicitAuth = true
	case "latitude", "deg_lat":
		if f := parseFiniteXMLFloatPtr(uVal); f != nil {
			rp.header.Latitude = f
		}
	case "longitude", "deg_lon":
		if f := parseFiniteXMLFloatPtr(uVal); f != nil {
			rp.header.Longitude = f
		}
	case "elevation", "altitude":
		if iv := parseRoundedXMLIntPtr(uVal); iv != nil {
			rp.header.Elevation = iv
		}
	case "slope", "slope_gradient":
		if f := parseFiniteXMLFloatPtr(uVal); f != nil {
			rp.header.Slope = f
		}
	case "aspect", "exposition":
		if deg, ok := parseCompassAspectDegrees(uVal); ok {
			rp.header.Aspect = &deg
		}
	case "plot_size", "surf_area":
		if f := parseFiniteXMLFloatPtr(uVal); f != nil {
			rp.header.PlotSize = f
		}
	default:
		return false
	}
	return true
}

func applyXMLHeaderUDFEcologicalText(rp *rawXMLPlot, uName, uVal string) {
	switch uName {
	case "zone":
		rp.header.Zone = uVal
	case "subzone":
		rp.header.SubZone = uVal
	case "site_series":
		rp.header.SiteSeries = uVal
	case "site_unit":
		rp.header.SiteUnit = uVal
		rp.hasExplicitSU = true
	case "moisture_regime", "moisture":
		rp.header.MoistureRegime = uVal
	case "nutrient_regime", "nutrient":
		rp.header.NutrientRegime = uVal
	case "meso_slope_position", "meso_slope":
		rp.header.MesoSlopePosition = uVal
	case "surface_shape", "surf_shape":
		rp.header.SurfaceShape = uVal
	case "soil_drainage", "drainage":
		rp.header.SoilDrainage = uVal
	case "humus_form":
		rp.header.HumusForm = uVal
	case "location", "locality":
		rp.header.Location = uVal
	case "site_notes":
		rp.header.SiteNotes = uVal
		rp.hasExplicitNote = true
	case "veg_notes":
		rp.header.VegNotes = uVal
	case "soil_notes":
		rp.header.SoilNotes = uVal
	}
}

func applyXMLSpeciesUDFRecord(curSpp *rawXMLSpeciesObs, a map[string]string) {
	uName := strings.ToLower(strings.TrimSpace(a["name"]))
	uVal := a["value"]
	switch uName {
	case "vpro_code":
		curSpp.vproCode = uVal
	case "vpro_layer":
		curSpp.vproLayer = uVal
	case "height":
		if f := parseFiniteXMLFloatPtr(uVal); f != nil {
			curSpp.height = f
		}
	case "collected":
		curSpp.collected = uVal
	}
}

func parseTurboVegXMLFile(ctx context.Context, path string, resolver *speciesImportResolver) ([]tvImportPlot, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 64*1024)
	if bom, peekErr := br.Peek(3); peekErr == nil && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF {
		_, _ = br.Discard(3)
	}

	dec := xml.NewDecoder(br)
	dec.CharsetReader = turboVegXMLCharsetReader

	pkg, err := streamXMLPlotPackage(ctx, dec)
	if err != nil {
		return nil, err
	}
	resolvedByNR, err := resolveXMLSpeciesLookupMap(ctx, pkg, resolver)
	if err != nil {
		return nil, err
	}
	return materializeXMLImportPlots(ctx, pkg, resolvedByNR, resolver)
}

func streamXMLPlotPackage(ctx context.Context, dec *xml.Decoder) (*rawXMLPackageLookups, error) {
	pkg := &rawXMLPackageLookups{
		sppLookup:   map[int]rawXMLSpeciesLookup{},
		coverscales: map[string]map[string]float64{},
		authors:     map[string]string{},
		projects:    map[string]string{},
		expositions: map[string]int{},
	}
	sawRoot := false
	plotCounter := 0

	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("parse TurboVeg Plot_package XML: %w", err)
		}
		se, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		if !sawRoot {
			sawRoot = true
			if !strings.EqualFold(se.Name.Local, "Plot_package") {
				return nil, fmt.Errorf("expected Turboveg standard XML root <Plot_package>, got <%s>", se.Name.Local)
			}
			continue
		}
		if err := pkg.consumePackageElement(ctx, dec, se, &plotCounter); err != nil {
			return nil, err
		}
	}
	if !sawRoot {
		return nil, errors.New("TurboVeg XML file is empty")
	}
	return pkg, nil
}

func (pkg *rawXMLPackageLookups) consumePackageElement(ctx context.Context, dec *xml.Decoder, se xml.StartElement, plotCounter *int) error {
	switch strings.ToLower(se.Name.Local) {
	case "plot":
		*plotCounter++
		if *plotCounter == 1 || *plotCounter%128 == 0 {
			runtime.Gosched()
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		rp, err := decodeRawXMLPlot(dec, se, *plotCounter)
		if err != nil {
			return fmt.Errorf("decode <Plot> #%d: %w", *plotCounter, err)
		}
		pkg.rawPlots = append(pkg.rawPlots, rp)
	case "coverscale_record":
		return pkg.decodeCoverscaleElement(dec, se)
	case "species_list":
		return pkg.decodeSpeciesListElement(ctx, dec)
	case "author_record":
		a := attrMapFromElement(se)
		if a["code"] != "" && a["description"] != "" {
			pkg.authors[a["code"]] = a["description"]
		}
	case "project_record":
		a := attrMapFromElement(se)
		if a["code"] != "" && a["description"] != "" {
			pkg.projects[a["code"]] = a["description"]
		}
	case "exposition_record":
		a := attrMapFromElement(se)
		if a["code"] != "" {
			if deg, ok := parseCompassAspectDegrees(a["description"]); ok {
				pkg.expositions[strings.ToUpper(a["code"])] = deg
			}
		}
	}
	return nil
}

func (pkg *rawXMLPackageLookups) decodeCoverscaleElement(dec *xml.Decoder, se xml.StartElement) error {
	var cs xmlCoverscaleRecord
	if err := dec.DecodeElement(&cs, &se); err != nil {
		return err
	}
	scaleCode := strings.TrimSpace(cs.Code)
	if scaleCode == "" {
		scaleCode = "00"
	}
	if pkg.coverscales[scaleCode] == nil {
		pkg.coverscales[scaleCode] = map[string]float64{}
	}
	for _, dr := range cs.DataRecords {
		if pct := parseFiniteXMLFloatPtr(strings.TrimSpace(dr.Percentage)); pct != nil {
			code := strings.TrimSpace(dr.Code)
			pkg.coverscales[scaleCode][code] = *pct
			pkg.coverscales[scaleCode][strings.ToLower(code)] = *pct
		}
	}
	return nil
}

func (pkg *rawXMLPackageLookups) decodeSpeciesListElement(ctx context.Context, dec *xml.Decoder) error {
	depth := 1
	sppTokSeq := 0
	for depth > 0 {
		sppTokSeq++
		if sppTokSeq%512 == 0 {
			runtime.Gosched()
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		sTok, err := dec.Token()
		if err != nil {
			return err
		}
		switch st := sTok.(type) {
		case xml.StartElement:
			depth++
			rTag := strings.ToLower(st.Name.Local)
			if rTag == "species_record" || rTag == "record" {
				pkg.recordSpeciesLookupAttr(attrMapFromElement(st))
			}
		case xml.EndElement:
			depth--
		}
	}
	return nil
}

func (pkg *rawXMLPackageLookups) recordSpeciesLookupAttr(a map[string]string) {
	nr, _ := strconv.Atoi(a["nr"])
	if nr <= 0 {
		return
	}
	valNR, _ := strconv.Atoi(a["valid_nr"])
	syn := strings.EqualFold(a["synonym"], "yes") || strings.EqualFold(a["synonym"], "true") || a["synonym"] == "1"
	if _, exists := pkg.sppLookup[nr]; !exists {
		pkg.sppOrder = append(pkg.sppOrder, nr)
	}
	pkg.sppLookup[nr] = rawXMLSpeciesLookup{
		nr:        nr,
		code:      a["code"],
		name:      a["name"],
		validNR:   valNR,
		validName: a["valid_name"],
		synonym:   syn,
		vproCode:  a["vpro_code"],
	}
}

func resolveXMLSpeciesLookupMap(
	ctx context.Context,
	pkg *rawXMLPackageLookups,
	resolver *speciesImportResolver,
) (map[int]resolvedXMLTaxon, error) {
	resolvedByNR := make(map[int]resolvedXMLTaxon, len(pkg.sppLookup))
	for idx, nr := range pkg.sppOrder {
		if idx%512 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		sp := pkg.sppLookup[nr]
		validSci := sp.validName
		if sp.synonym && validSci == "" && sp.validNR > 0 {
			if target, ok := pkg.sppLookup[sp.validNR]; ok {
				validSci = target.name
			}
		}
		code, lf := resolver.resolveTaxon(sp.vproCode, sp.name, validSci, sp.code)
		resolvedByNR[nr] = resolvedXMLTaxon{code: code, woody: isWoodyVProLifeform(lf)}
	}
	return resolvedByNR, nil
}

func materializeXMLImportPlots(
	ctx context.Context,
	pkg *rawXMLPackageLookups,
	resolvedByNR map[int]resolvedXMLTaxon,
	resolver *speciesImportResolver,
) ([]tvImportPlot, error) {
	plots := make([]tvImportPlot, len(pkg.rawPlots))
	for i, rp := range pkg.rawPlots {
		if i%128 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		h := finalizeXMLPlotHeader(rp, pkg)
		scale := strings.TrimSpace(rp.coverscale)
		if scale == "" {
			scale = "00"
		}
		obsOut, err := resolveXMLPlotObservations(h.PlotNumber, rp.observations, scale, pkg.coverscales[scale], resolvedByNR, resolver)
		if err != nil {
			return nil, err
		}
		plots[i] = tvImportPlot{Header: h, Observations: obsOut}
	}
	return plots, nil
}

func finalizeXMLPlotHeader(rp rawXMLPlot, pkg *rawXMLPackageLookups) tvPlotHeader {
	h := rp.header
	if !rp.hasExplicitAuth && h.Surveyor == "" && rp.authorCode != "" {
		if full, ok := pkg.authors[rp.authorCode]; ok {
			h.Surveyor = full
		} else {
			h.Surveyor = rp.authorCode
		}
	}
	if !rp.hasExplicitProj && h.ProjectID == "" && rp.projectCode != "" {
		if full, ok := pkg.projects[rp.projectCode]; ok {
			h.ProjectID = full
		} else {
			h.ProjectID = rp.projectCode
		}
	}
	if !rp.hasExplicitSU && h.SiteUnit == "" && rp.syntaxonCode != "" {
		h.SiteUnit = rp.syntaxonCode
	}
	if !rp.hasExplicitNote && h.SiteNotes == "" && rp.remarksFallback != "" {
		h.SiteNotes = rp.remarksFallback
	}
	if h.Aspect == nil && rp.expositionRaw != "" {
		if deg, ok := pkg.expositions[strings.ToUpper(rp.expositionRaw)]; ok {
			h.Aspect = &deg
		}
	}
	return h
}

func resolveXMLPlotObservations(
	plotNumber string,
	observations []rawXMLSpeciesObs,
	scale string,
	scaleMap map[string]float64,
	resolvedByNR map[int]resolvedXMLTaxon,
	resolver *speciesImportResolver,
) ([]tvImportObs, error) {
	obsOut := make([]tvImportObs, 0, len(observations))
	for _, ro := range observations {
		rawCov := strings.TrimSpace(ro.rawCover)
		if rawCov == "" {
			continue
		}
		cov, ok := lookupXMLObservationCover(rawCov, scale, scaleMap)
		if !ok {
			return nil, fmt.Errorf("plot %s species nr=%d has unresolvable cover code %q in coverscale %q", plotNumber, ro.nr, rawCov, scale)
		}
		code, woody := lookupXMLObservationTaxon(ro, resolvedByNR, resolver)
		if code == "" {
			continue
		}
		obsOut = append(obsOut, tvImportObs{
			SpeciesCode: code,
			TVLayerRaw:  ro.rawLayer,
			VProLayer:   ro.vproLayer,
			IsWoody:     woody,
			Cover:       cov,
			Height:      ro.height,
			Collected:   ro.collected,
		})
	}
	return obsOut, nil
}

func lookupXMLObservationCover(rawCov, scale string, scaleMap map[string]float64) (float64, bool) {
	if scale != "00" {
		if v, ok := lookupScaleCodeCI(scaleMap, rawCov); ok {
			return v, true
		}
	}
	if f, err := strconv.ParseFloat(rawCov, 64); err == nil {
		if scale != "00" {
			if bb, ok := defaultBraunBlanquetMidpoint(rawCov); ok {
				return bb, true
			}
		}
		return f, true
	}
	if v, ok := lookupScaleCodeCI(scaleMap, rawCov); ok {
		return v, true
	}
	return defaultBraunBlanquetMidpoint(rawCov)
}

func lookupScaleCodeCI(scaleMap map[string]float64, rawCov string) (float64, bool) {
	if scaleMap == nil {
		return 0, false
	}
	if v, ok := scaleMap[rawCov]; ok {
		return v, true
	}
	v, ok := scaleMap[strings.ToLower(rawCov)]
	return v, ok
}

func lookupXMLObservationTaxon(
	ro rawXMLSpeciesObs,
	resolvedByNR map[int]resolvedXMLTaxon,
	resolver *speciesImportResolver,
) (string, bool) {
	if strings.TrimSpace(ro.vproCode) != "" {
		c, lf := resolver.resolveTaxon(ro.vproCode, "", "", "")
		woody := isWoodyVProLifeform(lf)
		if lk, ok := resolvedByNR[ro.nr]; ok && lf == nil {
			woody = lk.woody
		}
		return c, woody
	}
	if lk, ok := resolvedByNR[ro.nr]; ok {
		return lk.code, lk.woody
	}
	return "", false
}
