package interchange

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

// parseVenusXMLArchive parses both hierarchical VENUS 5.0 XML (<VenusArchive>/<VenusDataset>/<VENUS>)
// AND Access/ADO relational table-row XML (<dataroot><tblPlotData>...</tblPlotData>...</dataroot>).
func parseVenusXMLArchive(ctx context.Context, data []byte, shaHex string) (venusNormalizedArchive, error) {
	if !utf8.Valid(data) {
		return venusNormalizedArchive{}, errors.New("VENUS XML contains invalid UTF-8")
	}
	dec := xml.NewDecoder(strings.NewReader(string(data)))

	var (
		version      = "5.0"
		projRows     []map[string]string
		plotRows     []map[string]string
		soilRows     []map[string]string
		vegMainRows  []map[string]string
		vegLayerRows []map[string]string
		vegSppRows   []map[string]string
		humusRows    []map[string]string
		mineralRows  []map[string]string
		hierPlots    []venusPlotRecord
		curProjName  = "VENUS5"
	)

	for {
		if err := ctx.Err(); err != nil {
			return venusNormalizedArchive{}, err
		}
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return venusNormalizedArchive{}, fmt.Errorf("parse VENUS XML: %w", err)
		}
		se, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		tag := strings.ToLower(se.Name.Local)
		for _, attr := range se.Attr {
			al := strings.ToLower(attr.Name.Local)
			if al == "version" && strings.TrimSpace(attr.Value) != "" {
				version = strings.TrimSpace(attr.Value)
			}
			if (tag == "project" || tag == "venus" || tag == "venusdataset" || tag == "venusarchive") && (al == "name" || al == "projectname" || al == "projectid") {
				if strings.TrimSpace(attr.Value) != "" {
					curProjName = strings.TrimSpace(attr.Value)
				}
			}
		}

		switch tag {
		case "usysversion":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			if v := firstNonEmpty(m, "version"); v != "" {
				version = v
				if b := firstNonEmpty(m, "beta"); b != "" && b != "0" {
					version += "." + b
				}
			}
		case "tblprojectmanager", "tblproject":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			projRows = append(projRows, m)
		case "tblenv":
			return venusNormalizedArchive{}, errors.New("VENUS 4.2 (tblEnv) archives are retired; VENUS 5.0+ (tblPlotData) is required")
		case "tblplotdata", "tblplot":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			plotRows = append(plotRows, m)
		case "tblsoil":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			soilRows = append(soilRows, m)
		case "tblvegmain":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			vegMainRows = append(vegMainRows, m)
		case "tblveglayer":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			vegLayerRows = append(vegLayerRows, m)
		case "tblvegspecies":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			vegSppRows = append(vegSppRows, m)
		case "tblorganichorizons", "tblsoilhumus":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			humusRows = append(humusRows, m)
		case "tblmineralhorizons", "tblsoilmineral":
			m, err := decodeFlatXMLElement(dec, se)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			mineralRows = append(mineralRows, m)
		case "plot":
			hp, err := decodeHierarchicalVenusPlot(dec, se, curProjName, len(hierPlots)+1)
			if err != nil {
				return venusNormalizedArchive{}, err
			}
			hierPlots = append(hierPlots, hp)
		}
	}

	if err := validateVenus5PlusVersion(version); err != nil {
		return venusNormalizedArchive{}, err
	}
	if len(hierPlots) > 0 && len(plotRows) == 0 {
		projs := map[string]string{}
		for _, hp := range hierPlots {
			projs[hp.ProjectName] = hp.ProjectName
		}
		return venusNormalizedArchive{
			Format:   "xml",
			Version:  version,
			SHA256:   shaHex,
			Projects: projs,
			Plots:    hierPlots,
		}, nil
	}
	if len(plotRows) == 0 {
		return venusNormalizedArchive{}, errors.New("VENUS XML contains no Plot / tblPlotData records")
	}
	return assembleRelationalVenusArchive("xml", version, shaHex, projRows, plotRows, soilRows, vegMainRows, vegLayerRows, vegSppRows, humusRows, mineralRows), nil
}

func decodeFlatXMLElement(dec *xml.Decoder, start xml.StartElement) (map[string]string, error) {
	m := map[string]string{}
	for _, a := range start.Attr {
		m[strings.ToLower(a.Name.Local)] = strings.TrimSpace(a.Value)
	}
	var currentField string
	var textBuf strings.Builder
	depth := 1
	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			depth++
			if depth == 2 {
				currentField = strings.ToLower(t.Name.Local)
				textBuf.Reset()
			}
		case xml.CharData:
			if depth == 2 {
				textBuf.Write(t)
			}
		case xml.EndElement:
			if depth == 2 && currentField != "" {
				m[currentField] = strings.TrimSpace(textBuf.String())
				currentField = ""
			}
			depth--
		}
	}
	return m, nil
}

func decodeHierarchicalVenusPlot(dec *xml.Decoder, start xml.StartElement, defaultProj string, index int) (venusPlotRecord, error) {
	rec := venusPlotRecord{
		ProjectName: defaultProj,
		ProjectKey:  defaultProj,
		Fields:      map[string]string{},
	}
	for _, a := range start.Attr {
		rec.Fields[strings.ToLower(a.Name.Local)] = strings.TrimSpace(a.Value)
	}

	depth := 1
	var curLayerCode string
	var curLayerHeight *float64
	for depth > 0 {
		tok, err := dec.Token()
		if err != nil {
			return rec, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			sub := strings.ToLower(t.Name.Local)
			switch sub {
			case "env", "site", "soil", "vegmain", "header":
				subMap, sErr := decodeFlatXMLElement(dec, t)
				if sErr != nil {
					return rec, sErr
				}
				for k, v := range subMap {
					rec.Fields[k] = v
				}
			case "veglayer", "layer":
				curLayerCode = ""
				curLayerHeight = nil
				for _, a := range t.Attr {
					al := strings.ToLower(a.Name.Local)
					if al == "layer" || al == "code" || al == "id" {
						curLayerCode = strings.TrimSpace(a.Value)
					} else if al == "height" {
						if hv, pErr := strconv.ParseFloat(strings.TrimSpace(a.Value), 64); pErr == nil {
							curLayerHeight = &hv
						}
					}
				}
				depth++
			case "vegspecies", "species", "observation":
				m, sErr := decodeFlatXMLElement(dec, t)
				if sErr != nil {
					return rec, sErr
				}
				spp := strings.ToUpper(firstNonEmpty(m, "species", "code", "speciescode"))
				cov, cErr := strconv.ParseFloat(firstNonEmpty(m, "cover", "percentcover"), 64)
				if spp != "" && cErr == nil && cov != 0 {
					lyr := firstNonEmpty(m, "layer", "layercode")
					if lyr == "" {
						lyr = curLayerCode
					}
					var ht *float64
					if hs := firstNonEmpty(m, "height"); hs != "" {
						if hv, hErr := strconv.ParseFloat(hs, 64); hErr == nil {
							ht = &hv
						}
					} else {
						ht = curLayerHeight
					}
					rec.VegObservations = append(rec.VegObservations, venusVegObs{
						Species:   spp,
						Layer:     lyr,
						Cover:     cov,
						Height:    ht,
						Collected: firstNonEmpty(m, "collected", "voucher"),
					})
				}
			case "humus", "organichorizon", "humushorizon", "tblsoilhumus", "tblorganichorizons":
				m, sErr := decodeFlatXMLElement(dec, t)
				if sErr != nil {
					return rec, sErr
				}
				if firstNonEmpty(m, "horizon") != "" {
					rec.HumusRows = append(rec.HumusRows, m)
				}
			case "mineral", "mineralhorizon", "tblsoilmineral", "tblmineralhorizons":
				m, sErr := decodeFlatXMLElement(dec, t)
				if sErr != nil {
					return rec, sErr
				}
				if firstNonEmpty(m, "horizon") != "" {
					rec.MineralRows = append(rec.MineralRows, m)
				}
			case "veglayers", "vegetation", "humushorizons", "mineralhorizons", "organichorizons", "soils":
				depth++
			default:
				// Direct scalar child element of <Plot>
				m, sErr := decodeFlatXMLElement(dec, t)
				if sErr != nil {
					return rec, sErr
				}
				for k, v := range m {
					rec.Fields[sub+"_"+k] = v
				}
			}
		case xml.EndElement:
			if strings.EqualFold(t.Name.Local, "veglayer") || strings.EqualFold(t.Name.Local, "layer") {
				curLayerCode = ""
				curLayerHeight = nil
			}
			depth--
		}
	}

	pNum := firstNonEmpty(rec.Fields, "plotnumber", "plot", "id")
	if pNum == "" {
		pNum = fmt.Sprintf("VP%05d", index)
	}
	pNum = sqlutil.TruncateUTF16(pNum, 7)
	rec.PlotNumber = pNum
	rec.PlotID = pNum
	if pName := firstNonEmpty(rec.Fields, "projectname", "projectid"); pName != "" {
		rec.ProjectName = pName
		rec.ProjectKey = pName
	}
	rec.PlotQuality = firstNonEmpty(rec.Fields, "siteplotquality", "plotquality")
	rec.Graviti = isAccessTruthy(firstNonEmpty(rec.Fields, "graviti"))
	return rec, nil
}

// VENUS 5.0 domain code converters (matching V7mdlImportVenus.txt)
func venusOrgSoilTexture(code string) string {
	switch strings.TrimSpace(code) {
	case "1":
		return "Fi"
	case "2":
		return "Me"
	case "3":
		return "Hu"
	default:
		return ""
	}
}

func venusHumusThickness(code string) *float64 {
	switch strings.TrimSpace(code) {
	case "0":
		v := 0.0
		return &v
	case "1":
		v := 10.0
		return &v
	case "2":
		v := 40.0
		return &v
	default:
		return nil
	}
}

func venusCoarseFrags(code string) *float64 {
	switch strings.TrimSpace(code) {
	case "0":
		v := 0.0
		return &v
	case "1":
		v := 10.0
		return &v
	case "2":
		v := 27.0
		return &v
	case "3":
		v := 52.0
		return &v
	case "4":
		v := 85.0
		return &v
	default:
		return nil
	}
}

func combineVenusTerrain(maxUnits int, a, b, c string) any {
	joined := strings.TrimSpace(a) + strings.TrimSpace(b) + strings.TrimSpace(c)
	if maxUnits > 0 {
		joined = sqlutil.TruncateUTF16(joined, maxUnits)
	}
	if joined == "" {
		return nil
	}
	return joined
}

func parseVenusCoordDMSOrDD(f map[string]string, ddKey, degKey, minKey, secKey string, isWestLon bool) *float64 {
	if dd := firstNonEmpty(f, ddKey); dd != "" {
		if v, err := strconv.ParseFloat(dd, 64); err == nil && v != 0 {
			if isWestLon && v >= 100 && v <= 170 {
				v = -v
			}
			return &v
		}
	}
	degStr := firstNonEmpty(f, degKey)
	if degStr == "" {
		return nil
	}
	deg, err := strconv.ParseFloat(degStr, 64)
	if err != nil || deg == 0 {
		return nil
	}
	min, _ := strconv.ParseFloat(firstNonEmpty(f, minKey), 64)
	sec, _ := strconv.ParseFloat(firstNonEmpty(f, secKey), 64)
	sign := 1.0
	if deg < 0 {
		sign = -1.0
		deg = -deg
	}
	val := sign * (deg + math.Abs(min)/60.0 + math.Abs(sec)/3600.0)
	if isWestLon && val > 0 && val >= 100 && val <= 170 {
		val = -val
	}
	return &val
}

func optFltField(f map[string]string, keys ...string) *float64 {
	s := firstNonEmpty(f, keys...)
	if s == "" {
		return nil
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return nil
	}
	return &v
}

func optIntField(f map[string]string, keys ...string) *int {
	s := firstNonEmpty(f, keys...)
	if s == "" {
		return nil
	}
	if iv, err := strconv.Atoi(s); err == nil {
		return &iv
	}
	if fv, err := strconv.ParseFloat(s, 64); err == nil {
		iv := int(math.Round(fv))
		return &iv
	}
	return nil
}

func optStrField(f map[string]string, maxUTF16 int, keys ...string) any {
	s := firstNonEmpty(f, keys...)
	if s == "" {
		return nil
	}
	if maxUTF16 > 0 {
		s = sqlutil.TruncateUTF16(s, maxUTF16)
		if s == "" {
			return nil
		}
	}
	return s
}

func optSingleCoverField(f map[string]string, plotNum, label string, keys ...string) (*float64, error) {
	raw := optFltField(f, keys...)
	if raw == nil {
		return nil, nil
	}
	v := *raw
	if math.IsNaN(v) || math.IsInf(v, 0) || v < 0 || math.Abs(v) > math.MaxFloat32 || float32(v) >= 100 {
		return nil, fmt.Errorf("VENUS plot %s %s %v must be from 0 to under 100%% (e.g. 99.9%%)", plotNum, label, v)
	}
	narrowed := float64(float32(v))
	return &narrowed, nil
}

func normalizeLMH25HorizonDepths(horizon string, isMineral bool, upper, lower *float64) (normUpper, normLower *float64, quarantineReason string) {
	if upper == nil || lower == nil {
		return upper, lower, ""
	}
	u, l := *upper, *lower
	if math.IsNaN(u) || math.IsInf(u, 0) || math.IsNaN(l) || math.IsInf(l, 0) {
		return upper, lower, "non-finite horizon depth"
	}
	if u < 0 || l < 0 {
		u = math.Abs(u)
		l = math.Abs(l)
	}
	if u == l {
		return upper, lower, "degenerate zero-thickness horizon (UpperDepth == LowerDepth)"
	}
	upward := false
	if !isMineral {
		hz := strings.ToUpper(strings.TrimSpace(horizon))
		if !strings.HasPrefix(hz, "OF") && !strings.HasPrefix(hz, "OM") && !strings.HasPrefix(hz, "OH") &&
			(strings.HasPrefix(hz, "L") || strings.HasPrefix(hz, "F") || strings.HasPrefix(hz, "H")) {
			upward = true
		}
	}
	if upward {
		if u < l {
			u, l = l, u
		}
	} else {
		if u > l {
			u, l = l, u
		}
	}
	return &u, &l, ""
}
