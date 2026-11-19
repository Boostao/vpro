package lmh25rules

import (
	"context"
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"
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

	// 1. 6-Field Substrate Sum Check (LMH25 2023 pp. 40-41)
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
		if sub.val != nil {
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

	// 1b. Quantitative Pit & Soil Header Depth Bounds (UX-SOIL-005; LMH25 Sec. 2)
	effectiveHeader := header
	if header.HumusThickness != nil && (math.IsNaN(*header.HumusThickness) || math.IsInf(*header.HumusThickness, 0) || *header.HumusThickness < 0) {
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
	if header.ActiveLayerDepth != nil && (math.IsNaN(*header.ActiveLayerDepth) || math.IsInf(*header.ActiveLayerDepth, 0) || *header.ActiveLayerDepth < 0) {
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

	// 2. Humus Horizons: DerivedHumusThickness, Directional Sign, Contiguity, and Table 2.23 von Post
	var uplandHorizons []vprocore.HumusRecord
	var wetlandHorizons []vprocore.HumusRecord
	var maxUplandUpper float64
	var minUplandLower float64
	hasUplandDepths := false
	var uplandHThickness, uplandTotalThickness float64
	var peatTotalThickness, peatOfUpper40, peatOmUpper40, peatUpper40Total float64
	hasPeatyHorizons := false

	for _, hr := range humus {
		hCode := trimUpper(hr.Horizon)
		hBase := stripDiscontinuityPrefix(hCode)
		idCopy := hr.ID
		isUpland, isWetland, _ := classifyHumusHorizon(hCode, res.IsOrganicSoilOrder, soilGroup)

		// Table 2.23 von Post check (LMH25 p. 73)
		if hr.VonPost != nil {
			vp := *hr.VonPost
			if vp < 1 || vp > 10 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "VONPOST_INVALID_SCALE",
					Severity:  SeverityError,
					Category:  "soil_vonpost",
					Field:     "vonPost",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Horizon %s has von Post = %d; valid von Post scale is 1..10.", hCode, vp),
					LMH25Ref:  "LMH25 (2023) Table 2.23 p. 73",
				})
			} else if strings.HasPrefix(hBase, "OF") && (vp < 1 || vp > 4) {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "VONPOST_OUT_OF_RANGE_OF",
					Severity:  SeverityWarning,
					Category:  "soil_vonpost",
					Field:     "vonPost",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Fibric horizon %s has von Post = %d; Table 2.23 specifies 1..4 for Of.", hCode, vp),
					Suggested: "1..4",
					LMH25Ref:  "LMH25 (2023) Table 2.23 p. 73",
				})
			} else if strings.HasPrefix(hBase, "OM") && (vp < 5 || vp > 6) {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "VONPOST_OUT_OF_RANGE_OM",
					Severity:  SeverityWarning,
					Category:  "soil_vonpost",
					Field:     "vonPost",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Mesic peat horizon %s has von Post = %d; Table 2.23 specifies 5..6 for Om.", hCode, vp),
					Suggested: "5..6",
					LMH25Ref:  "LMH25 (2023) Table 2.23 p. 73",
				})
			} else if strings.HasPrefix(hBase, "OH") && (vp < 7 || vp > 10) {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "VONPOST_OUT_OF_RANGE_OH",
					Severity:  SeverityWarning,
					Category:  "soil_vonpost",
					Field:     "vonPost",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Humic peat horizon %s has von Post = %d; Table 2.23 specifies 7..10 for Oh.", hCode, vp),
					Suggested: "7..10",
					LMH25Ref:  "LMH25 (2023) Table 2.23 p. 73",
				})
			}
		}

		if hr.PH != nil && (math.IsNaN(*hr.PH) || math.IsInf(*hr.PH, 0) || *hr.PH < 0 || *hr.PH > 14) {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "SOIL_PH_OUT_OF_BOUNDS",
				Severity:  SeverityError,
				Category:  "soil_ph",
				Field:     "HumusFormpH",
				HorizonID: &idCopy,
				Horizon:   hCode,
				Message:   fmt.Sprintf("Humus horizon %s has pH = %.2f; valid soil pH range is 0..14.", hCode, *hr.PH),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 21 p. 76",
			})
		}

		if hr.UpperDepth == nil || hr.LowerDepth == nil {
			for _, d := range []struct {
				field string
				val   *float64
			}{{"UpperDepth", hr.UpperDepth}, {"LowerDepth", hr.LowerDepth}} {
				if d.val != nil && (math.IsNaN(*d.val) || math.IsInf(*d.val, 0) || *d.val < 0) {
					res.Issues = append(res.Issues, DiagnosticIssue{
						Code:      "HORIZON_DEPTH_NEGATIVE",
						Severity:  SeverityError,
						Category:  "soil_horizon",
						Field:     d.field,
						HorizonID: &idCopy,
						Horizon:   hCode,
						Message:   fmt.Sprintf("Humus horizon %s %s (%.1f cm) must be finite and >= 0 cm.", hCode, d.field, *d.val),
						LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
					})
				}
			}
			continue
		}
		up, lo := *hr.UpperDepth, *hr.LowerDepth

		if isUpland {
			if up <= lo || lo < 0 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "HORIZON_SIGN_UPLAND_LFH",
					Severity:  SeverityError,
					Category:  "soil_horizon",
					Field:     "UpperDepth",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Upland humus horizon %s (%.1f to %.1f cm) must measure upward from 0 cm with UpperDepth > LowerDepth >= 0.", hCode, up, lo),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
				})
			} else {
				uplandHorizons = append(uplandHorizons, hr)
				if !hasUplandDepths {
					maxUplandUpper = up
					minUplandLower = lo
					hasUplandDepths = true
				} else {
					if up > maxUplandUpper {
						maxUplandUpper = up
					}
					if lo < minUplandLower {
						minUplandLower = lo
					}
				}
				thick := up - lo
				uplandTotalThickness += thick
				if strings.HasPrefix(hBase, "H") {
					uplandHThickness += thick
				}
			}
		} else if isWetland {
			if up >= lo || up < 0 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "HORIZON_SIGN_WETLAND_O",
					Severity:  SeverityError,
					Category:  "soil_horizon",
					Field:     "UpperDepth",
					HorizonID: &idCopy,
					Horizon:   hCode,
					Message:   fmt.Sprintf("Wetland organic horizon %s (%.1f to %.1f cm) must measure downward from 0 cm with 0 <= UpperDepth < LowerDepth.", hCode, up, lo),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
				})
			} else {
				hasPeatyHorizons = true
				wetlandHorizons = append(wetlandHorizons, hr)
				peatTotalThickness += (lo - up)
				// Compute overlap with upper 40 cm tier (0..40 cm)
				tStart := math.Max(0, up)
				tEnd := math.Min(40, lo)
				if tEnd > tStart {
					span := tEnd - tStart
					peatUpper40Total += span
					if strings.HasPrefix(hBase, "OF") {
						peatOfUpper40 += span
					} else if strings.HasPrefix(hBase, "OM") {
						peatOmUpper40 += span
					}
				}
			}
		}
	}

	if hasUplandDepths {
		derived := roundACE2(maxUplandUpper - minUplandLower)
		res.DerivedHumusThickness = &derived
		if effectiveHeader.HumusThickness == nil {
			if header.HumusThickness == nil {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "HUMUS_THICKNESS_SUGGESTED",
					Severity:  SeverityInfo,
					Category:  "humus_thickness",
					Field:     "HumusThickness",
					Message:   fmt.Sprintf("Derived upland L/F/H HumusThickness is %.1f cm (%.1f to %.1f cm); header HumusThickness is currently empty.", derived, maxUplandUpper, minUplandLower),
					Suggested: strconv.FormatFloat(derived, 'f', -1, 64),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
				})
			}
		} else {
			diff := roundACE2(*effectiveHeader.HumusThickness - derived)
			res.HumusThicknessDiff = &diff
			if math.Abs(diff) > 2.0 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "HUMUS_THICKNESS_MISMATCH",
					Severity:  SeverityWarning,
					Category:  "humus_thickness",
					Field:     "HumusThickness",
					Message:   fmt.Sprintf("Header HumusThickness (%.1f cm) differs from upland L/F/H horizon span (%.1f cm) by %+.1f cm.", *effectiveHeader.HumusThickness, derived, diff),
					Suggested: strconv.FormatFloat(derived, 'f', -1, 64),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
				})
			}
		}
	}

	// Upland contiguity check (ordered UpperDepth DESC)
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
			code := "HORIZON_CONTIGUITY_GAP"
			desc := "gap"
			if diff < 0 {
				code = "HORIZON_CONTIGUITY_OVERLAP"
				desc = "overlap"
			}
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      code,
				Severity:  SeverityWarning,
				Category:  "soil_contiguity",
				Field:     "UpperDepth",
				HorizonID: &nextID,
				Horizon:   trimUpper(next.Horizon),
				Message:   fmt.Sprintf("Upland humus contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}
	if len(uplandHorizons) > 0 && len(mineral) > 0 {
		last := uplandHorizons[len(uplandHorizons)-1]
		if *last.LowerDepth > 0.01 {
			lastID := last.ID
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "HORIZON_CONTIGUITY_GAP",
				Severity:  SeverityWarning,
				Category:  "soil_contiguity",
				Field:     "LowerDepth",
				HorizonID: &lastID,
				Horizon:   trimUpper(last.Horizon),
				Message:   fmt.Sprintf("Lowest upland humus horizon %s ends at %.1f cm instead of 0 cm mineral interface.", trimUpper(last.Horizon), *last.LowerDepth),
				Suggested: "0",
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}

	// Wetland O contiguity check (ordered UpperDepth ASC)
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
			code := "HORIZON_CONTIGUITY_GAP"
			desc := "gap"
			if diff < 0 {
				code = "HORIZON_CONTIGUITY_OVERLAP"
				desc = "overlap"
			}
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      code,
				Severity:  SeverityWarning,
				Category:  "soil_contiguity",
				Field:     "UpperDepth",
				HorizonID: &nextID,
				Horizon:   trimUpper(next.Horizon),
				Message:   fmt.Sprintf("Wetland organic horizon %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 17 p. 71",
			})
		}
	}

	// 3. Mineral Horizons: Directional Sign, Contiguity, Texture, Coarse Frags, Ah/Ae, Gleying & Munsell Value
	var validMinerals []vprocore.MineralRecord
	var ahDepth, aeDepth float64
	var bDark, bLight bool
	var hasGleying bool
	var minGleyDepth float64 = -1
	var lithicDepth float64 = -1
	var maxMineralLower float64
	var weightedCF, cfWeight float64
	var dominantTexture string
	var maxThickForTex float64
	var hasTurbation, hasSalineHorizon bool

	for _, mr := range mineral {
		mCode := trimUpper(mr.Horizon)
		mStripped := stripDiscontinuityRaw(derefStr(mr.Horizon))
		mBase := strings.ToUpper(mStripped)
		mLower := strings.ToLower(mStripped)
		idCopy := mr.ID
		if strings.Contains(mLower, "g") || strings.HasPrefix(mBase, "W") {
			hasGleying = true
			if mr.UpperDepth != nil && (minGleyDepth < 0 || *mr.UpperDepth < minGleyDepth) {
				minGleyDepth = *mr.UpperDepth
			}
		}
		if strings.Contains(mLower, "u") || strings.Contains(mLower, "b") && strings.HasPrefix(mBase, "A") {
			hasTurbation = true
		}
		if strings.Contains(mLower, "sa") || (strings.HasPrefix(mBase, "B") && strings.Contains(mLower, "n")) {
			hasSalineHorizon = true
		}
		if mr.ASP != nil && (*mr.ASP < 1 || *mr.ASP > 8) {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "MINERAL_ASP_OUT_OF_BOUNDS",
				Severity:  SeverityError,
				Category:  "soil_colour",
				Field:     "ASP",
				HorizonID: &idCopy,
				Horizon:   mCode,
				Message:   fmt.Sprintf("Mineral horizon %s has ASP = %d; LMH25 Table 2.30 colour aspect codes are 1..8.", mCode, *mr.ASP),
				LMH25Ref:  "LMH25 (2023) Table 2.30 p. 80",
			})
		}
		if mr.MineralFormpH != nil {
			if math.IsNaN(*mr.MineralFormpH) || math.IsInf(*mr.MineralFormpH, 0) || *mr.MineralFormpH < 0 || *mr.MineralFormpH > 14 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "SOIL_PH_OUT_OF_BOUNDS",
					Severity:  SeverityError,
					Category:  "soil_ph",
					Field:     "MineralFormpH",
					HorizonID: &idCopy,
					Horizon:   mCode,
					Message:   fmt.Sprintf("Mineral horizon %s has pH = %.2f; valid soil pH range is 0..14.", mCode, *mr.MineralFormpH),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 34 p. 91",
				})
			} else if *mr.MineralFormpH > 8.2 {
				hasSalineHorizon = true
			}
		}
		cfCompSum := 0
		hasValidCFComp := false
		allCFCompInBounds := true
		for _, cf := range []struct {
			field string
			val   *int
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
					Code:      "COARSE_FRAGS_OUT_OF_BOUNDS",
					Severity:  SeverityError,
					Category:  "soil_coarse_frags",
					Field:     cf.field,
					HorizonID: &idCopy,
					Horizon:   mCode,
					Message:   fmt.Sprintf("Mineral horizon %s has %s = %d%%; coarse fragments must be between 0%% and 100%%.", mCode, cf.field, *cf.val),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 28 p. 83",
				})
			} else if cf.isComp {
				cfCompSum += *cf.val
				hasValidCFComp = true
			}
		}
		if hasValidCFComp && allCFCompInBounds {
			if cfCompSum > 100 {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "COARSE_FRAGS_SUM_EXCEEDS_100",
					Severity:  SeverityError,
					Category:  "soil_coarse_frags",
					Field:     "PercentCoarseFragsTotal",
					HorizonID: &idCopy,
					Horizon:   mCode,
					Message:   fmt.Sprintf("Mineral horizon %s coarse fragment components Gravel + Cobbles + Stones sum to %d%% (cannot exceed 100%%).", mCode, cfCompSum),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 28 p. 83",
				})
			} else if mr.PercentCoarseFragsTotal != nil && *mr.PercentCoarseFragsTotal >= 0 && *mr.PercentCoarseFragsTotal <= 100 && cfCompSum > *mr.PercentCoarseFragsTotal {
				res.Issues = append(res.Issues, DiagnosticIssue{
					Code:      "COARSE_FRAGS_COMPONENTS_EXCEED_TOTAL",
					Severity:  SeverityError,
					Category:  "soil_coarse_frags",
					Field:     "PercentCoarseFragsTotal",
					HorizonID: &idCopy,
					Horizon:   mCode,
					Message:   fmt.Sprintf("Mineral horizon %s coarse fragment components Gravel + Cobbles + Stones (%d%%) exceed PercentCoarseFragsTotal (%d%%).", mCode, cfCompSum, *mr.PercentCoarseFragsTotal),
					LMH25Ref:  "LMH25 (2023) Sec. 2 Item 28 p. 83",
				})
			}
		}
		if strings.HasPrefix(mBase, "R") && mr.UpperDepth != nil && *mr.UpperDepth >= 0 {
			if lithicDepth < 0 || *mr.UpperDepth < lithicDepth {
				lithicDepth = *mr.UpperDepth
			}
		}
		if strings.HasPrefix(mBase, "B") && mr.Colour != nil {
			if val, ok := parseMunsellValue(*mr.Colour); ok {
				if val <= 3.0 {
					bDark = true
				}
				if val >= 7.0 {
					bLight = true
				}
			}
		}

		if mr.UpperDepth == nil || mr.LowerDepth == nil {
			for _, d := range []struct {
				field string
				val   *float64
			}{{"UpperDepth", mr.UpperDepth}, {"LowerDepth", mr.LowerDepth}} {
				if d.val != nil && (math.IsNaN(*d.val) || math.IsInf(*d.val, 0) || *d.val < 0) {
					res.Issues = append(res.Issues, DiagnosticIssue{
						Code:      "HORIZON_DEPTH_NEGATIVE",
						Severity:  SeverityError,
						Category:  "soil_horizon",
						Field:     d.field,
						HorizonID: &idCopy,
						Horizon:   mCode,
						Message:   fmt.Sprintf("Mineral horizon %s %s (%.1f cm) must be finite and >= 0 cm.", mCode, d.field, *d.val),
						LMH25Ref:  "LMH25 (2023) Sec. 2 Item 25 p. 79",
					})
				}
			}
			continue
		}
		up, lo := *mr.UpperDepth, *mr.LowerDepth
		if up >= lo || up < 0 {
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "HORIZON_SIGN_MINERAL",
				Severity:  SeverityError,
				Category:  "soil_horizon",
				Field:     "UpperDepth",
				HorizonID: &idCopy,
				Horizon:   mCode,
				Message:   fmt.Sprintf("Mineral horizon %s (%.1f to %.1f cm) must measure downward from 0 cm with 0 <= UpperDepth < LowerDepth.", mCode, up, lo),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 25 p. 79",
			})
			continue
		}
		validMinerals = append(validMinerals, mr)
		thick := lo - up
		if lo > maxMineralLower {
			maxMineralLower = lo
		}
		if strings.HasPrefix(mBase, "AH") || strings.HasPrefix(mBase, "AP") {
			ahDepth += thick
		}
		if strings.HasPrefix(mBase, "AE") {
			aeDepth += thick
		}
		if mr.PercentCoarseFragsTotal != nil && *mr.PercentCoarseFragsTotal >= 0 && *mr.PercentCoarseFragsTotal <= 100 && up < 100 {
			weightedCF += float64(*mr.PercentCoarseFragsTotal) * thick
			cfWeight += thick
		}
		if mr.Texture != nil && strings.TrimSpace(*mr.Texture) != "" && thick > maxThickForTex {
			maxThickForTex = thick
			dominantTexture = strings.ToUpper(strings.TrimSpace(*mr.Texture))
		}
	}

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
			code := "HORIZON_CONTIGUITY_GAP"
			desc := "gap"
			if diff < 0 {
				code = "HORIZON_CONTIGUITY_OVERLAP"
				desc = "overlap"
			}
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      code,
				Severity:  SeverityWarning,
				Category:  "soil_contiguity",
				Field:     "UpperDepth",
				HorizonID: &nextID,
				Horizon:   trimUpper(next.Horizon),
				Message:   fmt.Sprintf("Mineral horizon contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", desc, trimUpper(curr.Horizon), *curr.LowerDepth, trimUpper(next.Horizon), *next.UpperDepth),
				LMH25Ref:  "LMH25 (2023) Sec. 2 Item 25 p. 79",
			})
		}
	}

	// 4. LMH25 (2023) Keys 9.3, 9.4 (rSMR 0..8) & 9.6 / 9.7 (rSNR A..F) Inference
	inferSMRAndSNR(&res, effectiveHeader, soilGroup, hasPeatyHorizons, peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40,
		uplandTotalThickness, uplandHThickness, ahDepth, aeDepth, bDark, bLight, hasGleying, minGleyDepth, lithicDepth,
		maxMineralLower, weightedCF, cfWeight, dominantTexture, hasTurbation, hasSalineHorizon)

	return res
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
