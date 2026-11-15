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

func decodeRawXMLPlot(dec *xml.Decoder, se xml.StartElement, plotSeq int) (rawXMLPlot, error) {
	pAttrs := attrMapFromElement(se)
	releveNR, _ := strconv.Atoi(pAttrs["releve_nr"])
	if releveNR <= 0 {
		releveNR = plotSeq
	}
	rp := rawXMLPlot{
		coverscale: "00",
		header: tvPlotHeader{
			PlotID: releveNR,
		},
	}
	if dbName := pAttrs["database"]; dbName != "" {
		rp.projectCode = dbName
	}

	depth := 1
	inHeaderData := false
	inSpeciesData := false
	var curSpp *rawXMLSpeciesObs

	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return rawXMLPlot{}, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			depth++
			tag := strings.ToLower(t.Name.Local)
			switch {
			case tag == "header_data":
				inHeaderData = true
			case tag == "species_data":
				inSpeciesData = true
			case inHeaderData && tag == "standard_record":
				a := attrMapFromElement(t)
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
				if sa := a["surf_area"]; sa != "" {
					if f, pErr := strconv.ParseFloat(sa, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.PlotSize = &f
					}
				}
				if alt := a["altitude"]; alt != "" {
					if f, pErr := strconv.ParseFloat(alt, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						iv := int(math.Round(f))
						rp.header.Elevation = &iv
					}
				}
				if exp := a["exposition"]; exp != "" {
					rp.expositionRaw = exp
					if deg, ok := parseCompassAspectDegrees(exp); ok {
						rp.header.Aspect = &deg
					}
				}
				if inc := a["inclinatio"]; inc != "" {
					if f, pErr := strconv.ParseFloat(inc, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Slope = &f
					}
				}
				if lat := a["latitude"]; lat != "" {
					if f, pErr := strconv.ParseFloat(lat, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Latitude = &f
					}
				}
				if lon := a["longitude"]; lon != "" {
					if f, pErr := strconv.ParseFloat(lon, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Longitude = &f
					}
				}
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
			case inHeaderData && tag == "udf_record":
				a := attrMapFromElement(t)
				uName := strings.ToLower(strings.TrimSpace(a["name"]))
				uVal := a["value"]
				if uName == "" || uVal == "" {
					break
				}
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
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Latitude = &f
					}
				case "longitude", "deg_lon":
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Longitude = &f
					}
				case "elevation", "altitude":
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						iv := int(math.Round(f))
						rp.header.Elevation = &iv
					}
				case "slope", "slope_gradient":
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.Slope = &f
					}
				case "aspect", "exposition":
					if deg, ok := parseCompassAspectDegrees(uVal); ok {
						rp.header.Aspect = &deg
					}
				case "plot_size", "surf_area":
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						rp.header.PlotSize = &f
					}
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
			case inSpeciesData && tag == "species":
				curSpp = &rawXMLSpeciesObs{}
			case inSpeciesData && curSpp != nil && tag == "standard_record":
				a := attrMapFromElement(t)
				curSpp.nr, _ = strconv.Atoi(a["nr"])
				curSpp.rawCover = a["cover"]
				curSpp.rawLayer = a["layer"]
			case inSpeciesData && curSpp != nil && tag == "udf_record":
				a := attrMapFromElement(t)
				uName := strings.ToLower(strings.TrimSpace(a["name"]))
				uVal := a["value"]
				switch uName {
				case "vpro_code":
					curSpp.vproCode = uVal
				case "vpro_layer":
					curSpp.vproLayer = uVal
				case "height":
					if f, pErr := strconv.ParseFloat(uVal, 64); pErr == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
						curSpp.height = &f
					}
				case "collected":
					curSpp.collected = uVal
				}
			}
		case xml.EndElement:
			tag := strings.ToLower(t.Name.Local)
			switch tag {
			case "header_data":
				inHeaderData = false
			case "species_data":
				inSpeciesData = false
			case "species":
				if curSpp != nil {
					rp.observations = append(rp.observations, *curSpp)
					curSpp = nil
				}
			}
			depth--
		}
	}

	if !rp.hasExplicitPlot && strings.TrimSpace(rp.header.PlotNumber) == "" && releveNR > 0 {
		rp.header.PlotNumber = strconv.Itoa(releveNR)
	}
	return rp, nil
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

	var rawPlots []rawXMLPlot
	sppLookup := map[int]rawXMLSpeciesLookup{}
	var sppOrder []int
	coverscales := map[string]map[string]float64{}
	authors := map[string]string{}
	projects := map[string]string{}
	expositions := map[string]int{}

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

		switch strings.ToLower(se.Name.Local) {
		case "plot":
			plotCounter++
			if plotCounter == 1 || plotCounter%128 == 0 {
				runtime.Gosched()
				if err := ctx.Err(); err != nil {
					return nil, err
				}
			}
			rp, pErr := decodeRawXMLPlot(dec, se, plotCounter)
			if pErr != nil {
				return nil, fmt.Errorf("decode <Plot> #%d: %w", plotCounter, pErr)
			}
			rawPlots = append(rawPlots, rp)

		case "coverscale_record":
			var cs xmlCoverscaleRecord
			if err := dec.DecodeElement(&cs, &se); err != nil {
				return nil, err
			}
			scaleCode := strings.TrimSpace(cs.Code)
			if scaleCode == "" {
				scaleCode = "00"
			}
			if coverscales[scaleCode] == nil {
				coverscales[scaleCode] = map[string]float64{}
			}
			for _, dr := range cs.DataRecords {
				if pct, pErr := strconv.ParseFloat(strings.TrimSpace(dr.Percentage), 64); pErr == nil && !math.IsNaN(pct) && !math.IsInf(pct, 0) {
					coverscales[scaleCode][strings.TrimSpace(dr.Code)] = pct
					coverscales[scaleCode][strings.ToLower(strings.TrimSpace(dr.Code))] = pct
				}
			}

		case "species_list":
			depth := 1
			sppTokSeq := 0
			for depth > 0 {
				sppTokSeq++
				if sppTokSeq%512 == 0 {
					runtime.Gosched()
					if err := ctx.Err(); err != nil {
						return nil, err
					}
				}
				sTok, sErr := dec.Token()
				if sErr != nil {
					return nil, sErr
				}
				switch st := sTok.(type) {
				case xml.StartElement:
					depth++
					rTag := strings.ToLower(st.Name.Local)
					if rTag == "species_record" || rTag == "record" {
						a := attrMapFromElement(st)
						nr, _ := strconv.Atoi(a["nr"])
						valNR, _ := strconv.Atoi(a["valid_nr"])
						syn := strings.EqualFold(a["synonym"], "yes") || strings.EqualFold(a["synonym"], "true") || a["synonym"] == "1"
						if nr > 0 {
							if _, exists := sppLookup[nr]; !exists {
								sppOrder = append(sppOrder, nr)
							}
							sppLookup[nr] = rawXMLSpeciesLookup{
								nr:        nr,
								code:      a["code"],
								name:      a["name"],
								validNR:   valNR,
								validName: a["valid_name"],
								synonym:   syn,
								vproCode:  a["vpro_code"],
							}
						}
					}
				case xml.EndElement:
					depth--
				}
			}

		case "author_record":
			a := attrMapFromElement(se)
			if a["code"] != "" && a["description"] != "" {
				authors[a["code"]] = a["description"]
			}
		case "project_record":
			a := attrMapFromElement(se)
			if a["code"] != "" && a["description"] != "" {
				projects[a["code"]] = a["description"]
			}
		case "exposition_record":
			a := attrMapFromElement(se)
			if a["code"] != "" {
				if deg, ok := parseCompassAspectDegrees(a["description"]); ok {
					expositions[strings.ToUpper(a["code"])] = deg
				}
			}
		}
	}

	if !sawRoot {
		return nil, errors.New("TurboVeg XML file is empty")
	}

	// Post-stream resolution pass: resolve <Species_list>, <Coverscale_list>, and lookup references across all plots.
	type resolvedXMLTaxon struct {
		code  string
		woody bool
	}
	resolvedByNR := make(map[int]resolvedXMLTaxon, len(sppLookup))

	for idx, nr := range sppOrder {
		if idx%512 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		sp := sppLookup[nr]
		validSci := sp.validName
		if sp.synonym && validSci == "" && sp.validNR > 0 {
			if target, ok := sppLookup[sp.validNR]; ok {
				validSci = target.name
			}
		}
		code, lf := resolver.resolveTaxon(sp.vproCode, sp.name, validSci, sp.code)
		resolvedByNR[nr] = resolvedXMLTaxon{
			code:  code,
			woody: isWoodyVProLifeform(lf),
		}
	}

	plots := make([]tvImportPlot, len(rawPlots))
	for i, rp := range rawPlots {
		if i%128 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		h := rp.header
		if !rp.hasExplicitAuth && h.Surveyor == "" && rp.authorCode != "" {
			if full, ok := authors[rp.authorCode]; ok {
				h.Surveyor = full
			} else {
				h.Surveyor = rp.authorCode
			}
		}
		if !rp.hasExplicitProj && h.ProjectID == "" && rp.projectCode != "" {
			if full, ok := projects[rp.projectCode]; ok {
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
			if deg, ok := expositions[strings.ToUpper(rp.expositionRaw)]; ok {
				h.Aspect = &deg
			}
		}

		scale := strings.TrimSpace(rp.coverscale)
		if scale == "" {
			scale = "00"
		}
		scaleMap := coverscales[scale]

		obsOut := make([]tvImportObs, 0, len(rp.observations))
		for _, ro := range rp.observations {
			rawCov := strings.TrimSpace(ro.rawCover)
			if rawCov == "" {
				continue
			}
			var cov float64
			var haveCov bool
			if scale != "00" && scaleMap != nil {
				if v, ok := scaleMap[rawCov]; ok {
					cov, haveCov = v, true
				} else if v, ok := scaleMap[strings.ToLower(rawCov)]; ok {
					cov, haveCov = v, true
				}
			}
			if !haveCov {
				if f, pErr := strconv.ParseFloat(rawCov, 64); pErr == nil {
					if scale != "00" {
						if bb, ok := defaultBraunBlanquetMidpoint(rawCov); ok {
							cov, haveCov = bb, true
						} else {
							cov, haveCov = f, true
						}
					} else {
						cov, haveCov = f, true
					}
				} else if scaleMap != nil {
					if v, ok := scaleMap[rawCov]; ok {
						cov, haveCov = v, true
					} else if v, ok := scaleMap[strings.ToLower(rawCov)]; ok {
						cov, haveCov = v, true
					}
				}
			}
			if !haveCov {
				if bb, ok := defaultBraunBlanquetMidpoint(rawCov); ok {
					cov, haveCov = bb, true
				}
			}
			if !haveCov {
				return nil, fmt.Errorf("plot %s species nr=%d has unresolvable cover code %q in coverscale %q", h.PlotNumber, ro.nr, rawCov, scale)
			}

			var code string
			var woody bool
			if strings.TrimSpace(ro.vproCode) != "" {
				c, lf := resolver.resolveTaxon(ro.vproCode, "", "", "")
				code = c
				woody = isWoodyVProLifeform(lf)
				if lk, ok := resolvedByNR[ro.nr]; ok && lf == nil {
					woody = lk.woody
				}
			} else if lk, ok := resolvedByNR[ro.nr]; ok {
				code = lk.code
				woody = lk.woody
			}
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

		plots[i] = tvImportPlot{
			Header:       h,
			Observations: obsOut,
		}
	}

	return plots, nil
}
