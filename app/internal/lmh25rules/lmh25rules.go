package lmh25rules

import (
	"context"
	"fmt"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type DiagnosticSeverity string

const (
	SeverityInfo    DiagnosticSeverity = "info"
	SeverityWarning DiagnosticSeverity = "warning"
	SeverityError   DiagnosticSeverity = "error"
)

type DiagnosticIssue struct {
	Code      string             `json:"code"`
	Severity  DiagnosticSeverity `json:"severity"`
	Category  string             `json:"category"`
	Field     string             `json:"field,omitempty"`
	HorizonID *int64             `json:"horizonId,omitempty"`
	Horizon   string             `json:"horizon,omitempty"`
	Message   string             `json:"message"`
	Suggested string             `json:"suggested,omitempty"`
	LMH25Ref  string             `json:"lmh25Ref"`
}

type KeyTraceStep struct {
	Key       string `json:"key"`
	Step      string `json:"step"`
	Condition string `json:"condition"`
	Outcome   string `json:"outcome"`
}

type PlotDiagnosticsResult struct {
	PlotNumber            string            `json:"plotNumber"`
	DerivedHumusThickness *float64          `json:"derivedHumusThickness"`
	HeaderHumusThickness  *float64          `json:"headerHumusThickness"`
	HumusThicknessDiff    *float64          `json:"humusThicknessDiff"`
	SubstratePopulated    int               `json:"substratePopulated"`
	SubstrateSum          *float64          `json:"substrateSum"`
	SubstrateValid        bool              `json:"substrateValid"`
	IsOrganicSoilOrder    bool              `json:"isOrganicSoilOrder"`
	KeyedSMR              string            `json:"keyedSmr"`
	KeyedSMRClass         *int              `json:"keyedSmrClass"`
	FieldSMR              string            `json:"fieldSmr"`
	FieldSMRClass         *int              `json:"fieldSmrClass"`
	SMRDivergence         *int              `json:"smrDivergence"`
	SMRDivergent          bool              `json:"smrDivergent"`
	SMRTrace              []KeyTraceStep    `json:"smrTrace"`
	KeyedSNR              string            `json:"keyedSnr"`
	KeyedSNRClass         *int              `json:"keyedSnrClass"`
	FieldSNR              string            `json:"fieldSnr"`
	FieldSNRClass         *int              `json:"fieldSnrClass"`
	SNRDivergence         *int              `json:"snrDivergence"`
	SNRDivergent          bool              `json:"snrDivergent"`
	SNRTrace              []KeyTraceStep    `json:"snrTrace"`
	Issues                []DiagnosticIssue `json:"issues"`
}

type humusEvaluationMetrics struct {
	uplandTotalThickness float64
	uplandHThickness     float64
	peatTotalThickness   float64
	peatUpper40Total     float64
	peatOfUpper40        float64
	peatOmUpper40        float64
	hasPeatyHorizons     bool
}

type mineralEvaluationMetrics struct {
	ahDepth          float64
	aeDepth          float64
	bDark            bool
	bLight           bool
	hasGleying       bool
	minGleyDepth     float64
	lithicDepth      float64
	maxMineralLower  float64
	weightedCF       float64
	cfWeight         float64
	dominantTexture  string
	maxThickForTex   float64
	hasTurbation     bool
	hasSalineHorizon bool
}

func roundACE2(val float64) float64 {
	// ACE 15-significant-digit decimal calibration before half-away rounding to 2 decimals
	formatted := vprocore.FormatCalibratedDecimal(val, 2)
	parsed, err := strconv.ParseFloat(formatted, 64)
	if err != nil {
		return val
	}
	return parsed
}

func trimUpper(s *string) string {
	if s == nil {
		return ""
	}
	return strings.ToUpper(strings.TrimSpace(*s))
}

func isOrganicOrderGroup(code string) bool {
	switch strings.ToUpper(strings.TrimSpace(code)) {
	case "F", "M", "H", "FO":
		return true
	default:
		return false
	}
}

func stripDiscontinuityRaw(raw string) string {
	return strings.TrimSpace(strings.TrimLeft(strings.TrimSpace(raw), "0123456789IVXivx"))
}

func stripDiscontinuityPrefix(code string) string {
	return strings.ToUpper(stripDiscontinuityRaw(code))
}

func classifyHumusHorizon(h string, organicSoilOrder bool, soilClassGroup string) (isUpland, isWetland, isSurface bool) {
	// Strip a lithologic-discontinuity prefix (2L, 2Of, IIOf) before classifying, matching
	// vprocore.ClassifySoilHorizon and the R validator (ENG-XCUT-005).
	u := stripDiscontinuityPrefix(h)
	if u == "" {
		return false, false, false
	}
	if strings.HasPrefix(u, "OF") || strings.HasPrefix(u, "OM") || strings.HasPrefix(u, "OH") ||
		strings.HasPrefix(u, "LIMNO") || strings.HasPrefix(u, "CUMULO") || strings.HasPrefix(u, "HYDRIC") {
		return false, true, false
	}
	if u == "S" {
		return false, false, true
	}
	if strings.HasPrefix(u, "O") {
		return false, true, false
	}
	if strings.HasPrefix(u, "L") || strings.HasPrefix(u, "F") || strings.HasPrefix(u, "H") {
		// Folisols (FO) are upland LFH organic soils; F/M/H great groups measure downward only for O horizons
		if organicSoilOrder && strings.ToUpper(strings.TrimSpace(soilClassGroup)) != "FO" && strings.HasPrefix(u, "O") {
			return false, true, false
		}
		return true, false, false
	}
	return false, false, false
}

var munsellValuePattern = regexp.MustCompile(`(?i)(?:[0-9.]+(?:YR|Y|R|GY|G|BG|B|PB)|N)\s*([0-9]+(?:\.[0-9]+)?)\s*(?:/|$)`)

func parseMunsellValue(colour string) (float64, bool) {
	trimmed := strings.TrimSpace(colour)
	if trimmed == "" {
		return 0, false
	}
	if matches := munsellValuePattern.FindStringSubmatch(trimmed); len(matches) == 2 {
		if v, err := strconv.ParseFloat(matches[1], 64); err == nil {
			return v, true
		}
	}
	// Fallback: format like "3/2" without hue
	if slash := strings.IndexByte(trimmed, '/'); slash > 0 {
		fields := strings.Fields(trimmed[:slash])
		if len(fields) > 0 {
			if v, err := strconv.ParseFloat(fields[len(fields)-1], 64); err == nil {
				return v, true
			}
		}
	}
	return 0, false
}

func parseFieldSMRClass(raw string) (*int, bool) {
	t := strings.TrimSpace(raw)
	if t == "" {
		return nil, false
	}
	for i := 0; i < len(t); i++ {
		if t[i] >= '0' && t[i] <= '8' {
			v := int(t[i] - '0')
			return &v, true
		}
	}
	return nil, false
}

func parseFieldSNRClass(raw string) (*int, bool) {
	t := strings.ToUpper(strings.TrimSpace(raw))
	if t == "" {
		return nil, false
	}
	for i := 0; i < len(t); i++ {
		if t[i] >= 'A' && t[i] <= 'F' {
			v := int(t[i] - 'A')
			return &v, true
		}
	}
	return nil, false
}

func snrClassLetter(c int) string {
	if c < 0 {
		c = 0
	}
	if c > 5 {
		c = 5
	}
	return string(rune('A' + c))
}

func EvaluatePlotDiagnostics(header vprocore.FS882Header, humus []vprocore.HumusRecord, mineral []vprocore.MineralRecord) PlotDiagnosticsResult {
	res := PlotDiagnosticsResult{
		PlotNumber:           header.PlotNumber,
		HeaderHumusThickness: header.HumusThickness,
		SubstrateValid:       true,
		FieldSMR:             trimUpper(header.MoistureRegime),
		FieldSNR:             trimUpper(header.NutrientRegime),
		SMRTrace:             []KeyTraceStep{},
		SNRTrace:             []KeyTraceStep{},
		Issues:               []DiagnosticIssue{},
	}

	soilGroup := trimUpper(header.SoilClassGroup)
	res.IsOrganicSoilOrder = isOrganicOrderGroup(soilGroup)

	evaluateSubstrateBounds(&res, header)
	effectiveHeader := evaluateHeaderDepthBounds(&res, header)
	hm := evaluateHumusHorizons(&res, header, effectiveHeader, soilGroup, humus, len(mineral) > 0)
	mm := evaluateMineralHorizons(&res, mineral)

	inferSMRAndSNR(
		&res, effectiveHeader, soilGroup, hm.hasPeatyHorizons,
		hm.peatTotalThickness, hm.peatUpper40Total, hm.peatOfUpper40, hm.peatOmUpper40,
		hm.uplandTotalThickness, hm.uplandHThickness,
		mm.ahDepth, mm.aeDepth, mm.bDark, mm.bLight, mm.hasGleying,
		mm.minGleyDepth, mm.lithicDepth, mm.maxMineralLower,
		mm.weightedCF, mm.cfWeight, mm.dominantTexture, mm.hasTurbation, mm.hasSalineHorizon,
	)
	return res
}

func evaluateSubstrateBounds(res *PlotDiagnosticsResult, header vprocore.FS882Header) {
	substrates := []struct {
		name string
		val  *float64
	}{
		{"SubstrateDecWood", header.SubstrateDecWood},
		{"SubstrateBedRock", header.SubstrateBedRock},
		{"SubstrateRocks", header.SubstrateRocks},
		{"SubstrateMineralSoil", header.SubstrateMineralSoil},
		{"SubstrateOrganicMatter", header.SubstrateOrganicMatter},
		{"SubstrateWater", header.SubstrateWater},
	}
	var subSum float64
	for _, sub := range substrates {
		if sub.val == nil {
			continue
		}
		res.SubstratePopulated++
		v := *sub.val
		subSum += v
		if v < 0 || v > 100 {
			res.SubstrateValid = false
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:     "SUBSTRATE_VALUE_OUT_OF_BOUNDS",
				Severity: SeverityError,
				Category: "substrate",
				Field:    sub.name,
				Message:  fmt.Sprintf("%s (%.2f%%) must be between 0%% and 100%%.", sub.name, v),
				LMH25Ref: "LMH25 (2023) Sec. 1 Item 36 pp. 40-41",
			})
		}
	}
	if res.SubstratePopulated > 0 {
		roundedSum := roundACE2(subSum)
		res.SubstrateSum = &roundedSum
		if math.Abs(subSum-100.0) > 1.0 {
			res.SubstrateValid = false
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "SUBSTRATE_SUM_NOT_100",
				Severity:  SeverityWarning,
				Category:  "substrate",
				Field:     "SubstrateSum",
				Message:   fmt.Sprintf("Surface substrates sum to %.2f%% across %d populated field(s); LMH25 requires 100%% total.", roundedSum, res.SubstratePopulated),
				Suggested: "100",
				LMH25Ref:  "LMH25 (2023) Sec. 1 Item 36 pp. 40-41",
			})
		}
	}
}

func evaluateHeaderDepthBounds(res *PlotDiagnosticsResult, header vprocore.FS882Header) vprocore.FS882Header {
	effectiveHeader := header
	if isNegativeOrNonFinite(header.HumusThickness) {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code:     "SOIL_DEPTH_NEGATIVE",
			Severity: SeverityError,
			Category: "soil_depth",
			Field:    "HumusThickness",
			Message:  fmt.Sprintf("HumusThickness (%.1f cm) must be 0 cm or greater.", *header.HumusThickness),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
		})
		effectiveHeader.HumusThickness = nil
	}
	for _, intDepth := range []struct {
		name string
		val  *int
		ref  string
	}{
		{"RootingDepth", header.RootingDepth, "LMH25 (2023) Sec. 2 Item 7 p. 65"},
		{"RootRestrictingDepth", header.RootRestrictingDepth, "LMH25 (2023) Sec. 2 Item 9 p. 66"},
		{"SeepageDepth", header.SeepageDepth, "LMH25 (2023) Sec. 2 Item 5 p. 64"},
	} {
		if intDepth.val != nil && *intDepth.val < 0 {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:     "SOIL_DEPTH_NEGATIVE",
				Severity: SeverityError,
				Category: "soil_depth",
				Field:    intDepth.name,
				Message:  fmt.Sprintf("%s (%d cm) must be 0 cm or greater.", intDepth.name, *intDepth.val),
				LMH25Ref: intDepth.ref,
			})
		}
	}
	if header.RootRestrictingDepth != nil && *header.RootRestrictingDepth < 0 {
		effectiveHeader.RootRestrictingDepth = nil
	}
	if isNegativeOrNonFinite(header.ActiveLayerDepth) {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code:     "SOIL_DEPTH_NEGATIVE",
			Severity: SeverityError,
			Category: "soil_depth",
			Field:    "ActiveLayerDepth",
			Message:  fmt.Sprintf("ActiveLayerDepth (%.1f cm) must be 0 cm or greater.", *header.ActiveLayerDepth),
			LMH25Ref: "LMH25 (2023) Sec. 1 Item 36 p. 58",
		})
		effectiveHeader.ActiveLayerDepth = nil
	}
	return effectiveHeader
}

func isNegativeOrNonFinite(v *float64) bool {
	return v != nil && (math.IsNaN(*v) || math.IsInf(*v, 0) || *v < 0)
}

func evaluateHumusHorizons(
	res *PlotDiagnosticsResult,
	header, effectiveHeader vprocore.FS882Header,
	soilGroup string,
	humus []vprocore.HumusRecord,
	hasMineral bool,
) humusEvaluationMetrics {
	var hm humusEvaluationMetrics
	var uplandHorizons, wetlandHorizons []vprocore.HumusRecord
	var maxUplandUpper, minUplandLower float64
	hasUplandDepths := false

	for _, hr := range humus {
		hCode := trimUpper(hr.Horizon)
		hBase := stripDiscontinuityPrefix(hCode)
		idCopy := hr.ID
		isUpland, isWetland, _ := classifyHumusHorizon(hCode, res.IsOrganicSoilOrder, soilGroup)

		checkHumusVonPostAndPH(res, hr, hCode, hBase, &idCopy)
		if hr.UpperDepth == nil || hr.LowerDepth == nil {
			checkPartialHorizonDepths(res, "Humus", hCode, &idCopy, hr.UpperDepth, hr.LowerDepth, "LMH25 (2023) Sec. 2 Item 17 p. 71")
			continue
		}
		up, lo := *hr.UpperDepth, *hr.LowerDepth
		if isUpland {
			processUplandHumusHorizon(res, hr, hCode, hBase, &idCopy, up, lo, &uplandHorizons, &hasUplandDepths, &maxUplandUpper, &minUplandLower, &hm)
		} else if isWetland {
			processWetlandHumusHorizon(res, hr, hCode, hBase, &idCopy, up, lo, &wetlandHorizons, &hm)
		}
	}

	if hasUplandDepths {
		recordDerivedHumusThickness(res, header, effectiveHeader, maxUplandUpper, minUplandLower)
	}
	checkUplandHumusContiguity(res, uplandHorizons, hasMineral)
	checkWetlandHumusContiguity(res, wetlandHorizons)
	return hm
}

func checkHumusVonPostAndPH(res *PlotDiagnosticsResult, hr vprocore.HumusRecord, hCode, hBase string, idCopy *int64) {
	if hr.VonPost != nil {
		vp := *hr.VonPost
		switch {
		case vp < 1 || vp > 10:
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "VONPOST_INVALID_SCALE", Severity: SeverityError, Category: "soil_vonpost",
				Field: "vonPost", HorizonID: idCopy, Horizon: hCode,
				Message:  fmt.Sprintf("Horizon %s has von Post = %d; valid von Post scale is 1..10.", hCode, vp),
				LMH25Ref: "LMH25 (2023) Table 2.23 p. 73",
			})
		case strings.HasPrefix(hBase, "OF") && (vp < 1 || vp > 4):
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "VONPOST_OUT_OF_RANGE_OF", Severity: SeverityWarning, Category: "soil_vonpost",
				Field: "vonPost", HorizonID: idCopy, Horizon: hCode,
				Message:   fmt.Sprintf("Fibric horizon %s has von Post = %d; Table 2.23 specifies 1..4 for Of.", hCode, vp),
				Suggested: "1..4", LMH25Ref: "LMH25 (2023) Table 2.23 p. 73",
			})
		case strings.HasPrefix(hBase, "OM") && (vp < 5 || vp > 6):
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "VONPOST_OUT_OF_RANGE_OM", Severity: SeverityWarning, Category: "soil_vonpost",
				Field: "vonPost", HorizonID: idCopy, Horizon: hCode,
				Message:   fmt.Sprintf("Mesic peat horizon %s has von Post = %d; Table 2.23 specifies 5..6 for Om.", hCode, vp),
				Suggested: "5..6", LMH25Ref: "LMH25 (2023) Table 2.23 p. 73",
			})
		case strings.HasPrefix(hBase, "OH") && (vp < 7 || vp > 10):
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "VONPOST_OUT_OF_RANGE_OH", Severity: SeverityWarning, Category: "soil_vonpost",
				Field: "vonPost", HorizonID: idCopy, Horizon: hCode,
				Message:   fmt.Sprintf("Humic peat horizon %s has von Post = %d; Table 2.23 specifies 7..10 for Oh.", hCode, vp),
				Suggested: "7..10", LMH25Ref: "LMH25 (2023) Table 2.23 p. 73",
			})
		}
	}
	if hr.PH != nil && (math.IsNaN(*hr.PH) || math.IsInf(*hr.PH, 0) || *hr.PH < 0 || *hr.PH > 14) {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "SOIL_PH_OUT_OF_BOUNDS", Severity: SeverityError, Category: "soil_ph",
			Field: "HumusFormpH", HorizonID: idCopy, Horizon: hCode,
			Message:  fmt.Sprintf("Humus horizon %s has pH = %.2f; valid soil pH range is 0..14.", hCode, *hr.PH),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 21 p. 76",
		})
	}
}

func checkPartialHorizonDepths(res *PlotDiagnosticsResult, kind, hCode string, idCopy *int64, upper, lower *float64, ref string) {
	for _, d := range []struct {
		field string
		val   *float64
	}{{"UpperDepth", upper}, {"LowerDepth", lower}} {
		if isNegativeOrNonFinite(d.val) {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "HORIZON_DEPTH_NEGATIVE", Severity: SeverityError, Category: "soil_horizon",
				Field: d.field, HorizonID: idCopy, Horizon: hCode,
				Message:  fmt.Sprintf("%s horizon %s %s (%.1f cm) must be finite and >= 0 cm.", kind, hCode, d.field, *d.val),
				LMH25Ref: ref,
			})
		}
	}
}

func processUplandHumusHorizon(
	res *PlotDiagnosticsResult,
	hr vprocore.HumusRecord,
	hCode, hBase string,
	idCopy *int64,
	up, lo float64,
	uplandHorizons *[]vprocore.HumusRecord,
	hasUplandDepths *bool,
	maxUplandUpper, minUplandLower *float64,
	hm *humusEvaluationMetrics,
) {
	if up <= lo || lo < 0 {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "HORIZON_SIGN_UPLAND_LFH", Severity: SeverityError, Category: "soil_horizon",
			Field: "UpperDepth", HorizonID: idCopy, Horizon: hCode,
			Message:  fmt.Sprintf("Upland humus horizon %s (%.1f to %.1f cm) must measure upward from 0 cm with UpperDepth > LowerDepth >= 0.", hCode, up, lo),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
		})
		return
	}
	*uplandHorizons = append(*uplandHorizons, hr)
	if !*hasUplandDepths {
		*maxUplandUpper, *minUplandLower, *hasUplandDepths = up, lo, true
	} else {
		if up > *maxUplandUpper {
			*maxUplandUpper = up
		}
		if lo < *minUplandLower {
			*minUplandLower = lo
		}
	}
	thick := up - lo
	hm.uplandTotalThickness += thick
	if strings.HasPrefix(hBase, "H") {
		hm.uplandHThickness += thick
	}
}

func processWetlandHumusHorizon(
	res *PlotDiagnosticsResult,
	hr vprocore.HumusRecord,
	hCode, hBase string,
	idCopy *int64,
	up, lo float64,
	wetlandHorizons *[]vprocore.HumusRecord,
	hm *humusEvaluationMetrics,
) {
	if up >= lo || up < 0 {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "HORIZON_SIGN_WETLAND_O", Severity: SeverityError, Category: "soil_horizon",
			Field: "UpperDepth", HorizonID: idCopy, Horizon: hCode,
			Message:  fmt.Sprintf("Wetland organic horizon %s (%.1f to %.1f cm) must measure downward from 0 cm with 0 <= UpperDepth < LowerDepth.", hCode, up, lo),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
		})
		return
	}
	hm.hasPeatyHorizons = true
	*wetlandHorizons = append(*wetlandHorizons, hr)
	hm.peatTotalThickness += (lo - up)
	tStart := math.Max(0, up)
	tEnd := math.Min(40, lo)
	if tEnd > tStart {
		span := tEnd - tStart
		hm.peatUpper40Total += span
		if strings.HasPrefix(hBase, "OF") {
			hm.peatOfUpper40 += span
		} else if strings.HasPrefix(hBase, "OM") {
			hm.peatOmUpper40 += span
		}
	}
}

func recordDerivedHumusThickness(
	res *PlotDiagnosticsResult,
	header, effectiveHeader vprocore.FS882Header,
	maxUplandUpper, minUplandLower float64,
) {
	derived := roundACE2(maxUplandUpper - minUplandLower)
	res.DerivedHumusThickness = &derived
	if effectiveHeader.HumusThickness == nil {
		if header.HumusThickness == nil {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "HUMUS_THICKNESS_SUGGESTED", Severity: SeverityInfo, Category: "humus_thickness",
				Field:     "HumusThickness",
				Message:   fmt.Sprintf("Derived upland L/F/H HumusThickness is %.1f cm (%.1f to %.1f cm); header HumusThickness is currently empty.", derived, maxUplandUpper, minUplandLower),
				Suggested: strconv.FormatFloat(derived, 'f', -1, 64),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
		return
	}
	diff := roundACE2(*effectiveHeader.HumusThickness - derived)
	res.HumusThicknessDiff = &diff
	if math.Abs(diff) > 2.0 {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "HUMUS_THICKNESS_MISMATCH", Severity: SeverityWarning, Category: "humus_thickness",
			Field:     "HumusThickness",
			Message:   fmt.Sprintf("Header HumusThickness (%.1f cm) differs from upland L/F/H horizon span (%.1f cm) by %+.1f cm.", *effectiveHeader.HumusThickness, derived, diff),
			Suggested: strconv.FormatFloat(derived, 'f', -1, 64),
			LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
		})
	}
}

func checkUplandHumusContiguity(res *PlotDiagnosticsResult, uplandHorizons []vprocore.HumusRecord, hasMineral bool) {
	slices.SortFunc(uplandHorizons, func(a, b vprocore.HumusRecord) int {
		if *a.UpperDepth > *b.UpperDepth {
			return -1
		}
		if *a.UpperDepth < *b.UpperDepth {
			return 1
		}
		return int(a.ID - b.ID)
	})
	for i := 0; i+1 < len(uplandHorizons); i++ {
		curr, next := uplandHorizons[i], uplandHorizons[i+1]
		diff := *curr.LowerDepth - *next.UpperDepth
		if math.Abs(diff) > 0.01 {
			nextID := next.ID
			code, desc := contiguityCodeAndDesc(diff)
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: code, Severity: SeverityWarning, Category: "soil_contiguity",
				Field: "UpperDepth", HorizonID: &nextID, Horizon: trimUpper(next.Horizon),
				Message:  fmt.Sprintf("Upland humus contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}
	if len(uplandHorizons) > 0 && hasMineral {
		last := uplandHorizons[len(uplandHorizons)-1]
		if *last.LowerDepth > 0.01 {
			lastID := last.ID
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "HORIZON_CONTIGUITY_GAP", Severity: SeverityWarning, Category: "soil_contiguity",
				Field: "LowerDepth", HorizonID: &lastID, Horizon: trimUpper(last.Horizon),
				Message:   fmt.Sprintf("Lowest upland humus horizon %s ends at %.1f cm instead of 0 cm mineral interface.", trimUpper(last.Horizon), *last.LowerDepth),
				Suggested: "0", LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}
}

func checkWetlandHumusContiguity(res *PlotDiagnosticsResult, wetlandHorizons []vprocore.HumusRecord) {
	slices.SortFunc(wetlandHorizons, func(a, b vprocore.HumusRecord) int {
		if *a.UpperDepth < *b.UpperDepth {
			return -1
		}
		if *a.UpperDepth > *b.UpperDepth {
			return 1
		}
		return int(a.ID - b.ID)
	})
	for i := 0; i+1 < len(wetlandHorizons); i++ {
		curr, next := wetlandHorizons[i], wetlandHorizons[i+1]
		diff := *next.UpperDepth - *curr.LowerDepth
		if math.Abs(diff) > 0.01 {
			nextID := next.ID
			code, desc := contiguityCodeAndDesc(diff)
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: code, Severity: SeverityWarning, Category: "soil_contiguity",
				Field: "UpperDepth", HorizonID: &nextID, Horizon: trimUpper(next.Horizon),
				Message:  fmt.Sprintf("Wetland organic horizon %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref: "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}
}

func contiguityCodeAndDesc(diff float64) (string, string) {
	if diff < 0 {
		return "HORIZON_CONTIGUITY_OVERLAP", "overlap"
	}
	return "HORIZON_CONTIGUITY_GAP", "gap"
}

func evaluateMineralHorizons(res *PlotDiagnosticsResult, mineral []vprocore.MineralRecord) mineralEvaluationMetrics {
	mm := mineralEvaluationMetrics{minGleyDepth: -1, lithicDepth: -1}
	var validMinerals []vprocore.MineralRecord

	for _, mr := range mineral {
		mCode := trimUpper(mr.Horizon)
		mStripped := stripDiscontinuityRaw(derefStr(mr.Horizon))
		mBase := strings.ToUpper(mStripped)
		mLower := strings.ToLower(mStripped)
		idCopy := mr.ID

		observeMineralIndicators(mr, mBase, mLower, &mm)
		checkMineralASPAndPH(res, mr, mCode, &idCopy, &mm)
		checkMineralCoarseFragments(res, mr, mCode, &idCopy)

		if mr.UpperDepth == nil || mr.LowerDepth == nil {
			checkPartialHorizonDepths(res, "Mineral", mCode, &idCopy, mr.UpperDepth, mr.LowerDepth, "LMH25 (2023) Sec. 2 Item 25 p. 79")
			continue
		}
		up, lo := *mr.UpperDepth, *mr.LowerDepth
		if up >= lo || up < 0 {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "HORIZON_SIGN_MINERAL", Severity: SeverityError, Category: "soil_horizon",
				Field: "UpperDepth", HorizonID: &idCopy, Horizon: mCode,
				Message:  fmt.Sprintf("Mineral horizon %s (%.1f to %.1f cm) must measure downward from 0 cm with 0 <= UpperDepth < LowerDepth.", mCode, up, lo),
				LMH25Ref: "LMH25 (2023) Sec. 2 Item 25 p. 79",
			})
			continue
		}
		validMinerals = append(validMinerals, mr)
		accumulateValidMineralMetrics(mr, mBase, up, lo, &mm)
	}

	checkMineralContiguity(res, validMinerals)
	return mm
}

func observeMineralIndicators(mr vprocore.MineralRecord, mBase, mLower string, mm *mineralEvaluationMetrics) {
	if strings.Contains(mLower, "g") || strings.HasPrefix(mBase, "W") {
		mm.hasGleying = true
		if mr.UpperDepth != nil && (mm.minGleyDepth < 0 || *mr.UpperDepth < mm.minGleyDepth) {
			mm.minGleyDepth = *mr.UpperDepth
		}
	}
	if strings.Contains(mLower, "u") || strings.Contains(mLower, "b") && strings.HasPrefix(mBase, "A") {
		mm.hasTurbation = true
	}
	if strings.Contains(mLower, "sa") || (strings.HasPrefix(mBase, "B") && strings.Contains(mLower, "n")) {
		mm.hasSalineHorizon = true
	}
	if strings.HasPrefix(mBase, "R") && mr.UpperDepth != nil && *mr.UpperDepth >= 0 {
		if mm.lithicDepth < 0 || *mr.UpperDepth < mm.lithicDepth {
			mm.lithicDepth = *mr.UpperDepth
		}
	}
	if strings.HasPrefix(mBase, "B") && mr.Colour != nil {
		if val, ok := parseMunsellValue(*mr.Colour); ok {
			if val <= 3.0 {
				mm.bDark = true
			}
			if val >= 7.0 {
				mm.bLight = true
			}
		}
	}
}

func checkMineralASPAndPH(res *PlotDiagnosticsResult, mr vprocore.MineralRecord, mCode string, idCopy *int64, mm *mineralEvaluationMetrics) {
	if mr.ASP != nil && (*mr.ASP < 1 || *mr.ASP > 8) {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "MINERAL_ASP_OUT_OF_BOUNDS", Severity: SeverityError, Category: "soil_colour",
			Field: "ASP", HorizonID: idCopy, Horizon: mCode,
			Message:  fmt.Sprintf("Mineral horizon %s has ASP = %d; LMH25 Table 2.30 colour aspect codes are 1..8.", mCode, *mr.ASP),
			LMH25Ref: "LMH25 (2023) Table 2.30 p. 80",
		})
	}
	if mr.MineralFormpH == nil {
		return
	}
	if math.IsNaN(*mr.MineralFormpH) || math.IsInf(*mr.MineralFormpH, 0) || *mr.MineralFormpH < 0 || *mr.MineralFormpH > 14 {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "SOIL_PH_OUT_OF_BOUNDS", Severity: SeverityError, Category: "soil_ph",
			Field: "MineralFormpH", HorizonID: idCopy, Horizon: mCode,
			Message:  fmt.Sprintf("Mineral horizon %s has pH = %.2f; valid soil pH range is 0..14.", mCode, *mr.MineralFormpH),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 34 p. 91",
		})
	} else if *mr.MineralFormpH > 8.2 {
		mm.hasSalineHorizon = true
	}
}

func checkMineralCoarseFragments(res *PlotDiagnosticsResult, mr vprocore.MineralRecord, mCode string, idCopy *int64) {
	cfCompSum := 0
	hasValidCFComp := false
	allCFCompInBounds := true
	for _, cf := range []struct {
		field  string
		val    *int
		isComp bool
	}{
		{"PercentCoarseFragsGravel", mr.PercentCoarseFragsGravel, true},
		{"PercentCoarseFragsCobbles", mr.PercentCoarseFragsCobbles, true},
		{"PercentCoarseFragsStones", mr.PercentCoarseFragsStones, true},
		{"PercentCoarseFragsTotal", mr.PercentCoarseFragsTotal, false},
	} {
		if cf.val == nil {
			continue
		}
		if *cf.val < 0 || *cf.val > 100 {
			if cf.isComp {
				allCFCompInBounds = false
			}
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: "COARSE_FRAGS_OUT_OF_BOUNDS", Severity: SeverityError, Category: "soil_coarse_frags",
				Field: cf.field, HorizonID: idCopy, Horizon: mCode,
				Message:  fmt.Sprintf("Mineral horizon %s has %s = %d%%; coarse fragments must be between 0%% and 100%%.", mCode, cf.field, *cf.val),
				LMH25Ref: "LMH25 (2023) Sec. 2 Item 28 p. 83",
			})
		} else if cf.isComp {
			cfCompSum += *cf.val
			hasValidCFComp = true
		}
	}
	if !hasValidCFComp || !allCFCompInBounds {
		return
	}
	if cfCompSum > 100 {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "COARSE_FRAGS_SUM_EXCEEDS_100", Severity: SeverityError, Category: "soil_coarse_frags",
			Field: "PercentCoarseFragsTotal", HorizonID: idCopy, Horizon: mCode,
			Message:  fmt.Sprintf("Mineral horizon %s coarse fragment components Gravel + Cobbles + Stones sum to %d%% (cannot exceed 100%%).", mCode, cfCompSum),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 28 p. 83",
		})
	} else if mr.PercentCoarseFragsTotal != nil && *mr.PercentCoarseFragsTotal >= 0 && *mr.PercentCoarseFragsTotal <= 100 && cfCompSum > *mr.PercentCoarseFragsTotal {
		res.Issues = append(res.Issues, DiagnosticIssue{
			Code: "COARSE_FRAGS_COMPONENTS_EXCEED_TOTAL", Severity: SeverityError, Category: "soil_coarse_frags",
			Field: "PercentCoarseFragsTotal", HorizonID: idCopy, Horizon: mCode,
			Message:  fmt.Sprintf("Mineral horizon %s coarse fragment components Gravel + Cobbles + Stones (%d%%) exceed PercentCoarseFragsTotal (%d%%).", mCode, cfCompSum, *mr.PercentCoarseFragsTotal),
			LMH25Ref: "LMH25 (2023) Sec. 2 Item 28 p. 83",
		})
	}
}

func accumulateValidMineralMetrics(mr vprocore.MineralRecord, mBase string, up, lo float64, mm *mineralEvaluationMetrics) {
	thick := lo - up
	if lo > mm.maxMineralLower {
		mm.maxMineralLower = lo
	}
	if strings.HasPrefix(mBase, "AH") || strings.HasPrefix(mBase, "AP") {
		mm.ahDepth += thick
	}
	if strings.HasPrefix(mBase, "AE") {
		mm.aeDepth += thick
	}
	if mr.PercentCoarseFragsTotal != nil && *mr.PercentCoarseFragsTotal >= 0 && *mr.PercentCoarseFragsTotal <= 100 && up < 100 {
		mm.weightedCF += float64(*mr.PercentCoarseFragsTotal) * thick
		mm.cfWeight += thick
	}
	if mr.Texture != nil && strings.TrimSpace(*mr.Texture) != "" && thick > mm.maxThickForTex {
		mm.maxThickForTex = thick
		mm.dominantTexture = strings.ToUpper(strings.TrimSpace(*mr.Texture))
	}
}

func checkMineralContiguity(res *PlotDiagnosticsResult, validMinerals []vprocore.MineralRecord) {
	slices.SortFunc(validMinerals, func(a, b vprocore.MineralRecord) int {
		if *a.UpperDepth < *b.UpperDepth {
			return -1
		}
		if *a.UpperDepth > *b.UpperDepth {
			return 1
		}
		return int(a.ID - b.ID)
	})
	for i := 0; i+1 < len(validMinerals); i++ {
		curr, next := validMinerals[i], validMinerals[i+1]
		diff := *next.UpperDepth - *curr.LowerDepth
		if math.Abs(diff) > 0.01 {
			nextID := next.ID
			code, desc := contiguityCodeAndDesc(diff)
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code: code, Severity: SeverityWarning, Category: "soil_contiguity",
				Field: "UpperDepth", HorizonID: &nextID, Horizon: trimUpper(next.Horizon),
				Message:  fmt.Sprintf("Mineral horizon contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref: "LMH25 (2023) Sec. 2 Item 25 p. 79",
			})
		}
	}
}

func derefStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func EvaluateStoredPlotDiagnostics(s *vprocore.ContextService, ctx context.Context, contextID, plotNumber string) (PlotDiagnosticsResult, error) {
	header, err := s.GetPlot(ctx, contextID, plotNumber)
	if err != nil {
		return PlotDiagnosticsResult{}, err
	}
	humus, err := s.ListHumusRecords(ctx, contextID, plotNumber)
	if err != nil {
		return PlotDiagnosticsResult{}, err
	}
	mineral, err := s.ListMineralRecords(ctx, contextID, plotNumber)
	if err != nil {
		return PlotDiagnosticsResult{}, err
	}
	return EvaluatePlotDiagnostics(*header, humus, mineral), nil
}
