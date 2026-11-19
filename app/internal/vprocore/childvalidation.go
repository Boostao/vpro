package vprocore

import (
	"fmt"
	"math"
	"reflect"
	"regexp"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

var SoilChildTextMaximum = map[string]map[string]int{
	"Humus": {
		"Horizon": 8, "HumusStructureDegree": 1, "HumusStructureKind": 5,
		"MycelAbundance": 1, "FecalAbundance": 1, "RootsAbundance": 6, "RootsSize": 6, "Comment": 0,
	},
	"Mineral": {
		"Horizon": 8, "Texture": 4, "Colour": 14, "PitDepthLimit": 1, "PercentCoarseFragsShape": 1,
		"RootsAbundance": 6, "RootsSize": 6, "MineralStructureClass": 3, "MineralStructureKind": 7, "Comments": 0,
	},
}

var SoilChildSingleColumns = map[string]map[string]bool{
	"Humus":   {"UpperDepth": true, "LowerDepth": true, "HumusFormpH": true},
	"Mineral": {"UpperDepth": true, "LowerDepth": true, "MineralFormpH": true},
}

var SoilChildIntegerColumns = map[string]map[string]bool{
	"Humus": {"vonPost": true},
	"Mineral": {
		"ASP": true, "PercentCoarseFragsGravel": true, "PercentCoarseFragsCobbles": true,
		"PercentCoarseFragsStones": true, "PercentCoarseFragsTotal": true,
	},
}

func ValidateChildPhysicalText(name string, value any, maximum int) error {
	if value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok || !utf8.ValidString(text) {
		return fmt.Errorf("%s requires nullable valid Unicode text", name)
	}
	if maximum > 0 && len(utf16.Encode([]rune(text))) > maximum {
		return fmt.Errorf("%s exceeds %d UTF-16 units", name, maximum)
	}
	return nil
}

func SoilChildJSONTextNames(kind string, record any) map[string]string {
	names := make(map[string]string)
	value := reflect.ValueOf(record)
	for _, field := range ChildFields[kind] {
		if _, text := SoilChildTextMaximum[kind][field.Column]; text {
			names[strings.ToLower(ChildJSONKey(value, field))] = kind + "." + field.Column
		}
	}
	return names
}

func ValidateSoilChildField(kind, column string, value any) error {
	if maximum, text := SoilChildTextMaximum[kind][column]; text {
		return ValidateChildPhysicalText(kind+"."+column, value, maximum)
	}
	if SoilChildSingleColumns[kind][column] {
		if value == nil {
			return nil
		}
		number, ok := value.(float64)
		if !ok {
			return fmt.Errorf("%s.%s requires a nullable number", kind, column)
		}
		if err := ValidateSingleRangeChange(kind+"."+column, nil, &number); err != nil {
			return err
		}
		switch column {
		case "UpperDepth", "LowerDepth":
			if number < 0 {
				return fmt.Errorf("%s.%s must be >= 0 cm (got %v)", kind, column, number)
			}
		case "HumusFormpH", "MineralFormpH":
			if number < 0 || number > 14 {
				return fmt.Errorf("%s.%s must be between 0 and 14 on the pH scale (got %v)", kind, column, number)
			}
		}
		return nil
	}
	if SoilChildIntegerColumns[kind][column] {
		if value == nil {
			return nil
		}
		number, ok := value.(int)
		if !ok {
			return fmt.Errorf("%s.%s requires a nullable integer", kind, column)
		}
		if err := ValidateOrdinaryInteger(kind+"."+column, &number); err != nil {
			return err
		}
		switch {
		case kind == "Humus" && column == "vonPost":
			if number < 1 || number > 10 {
				return fmt.Errorf("Humus.vonPost must be an integer from 1 to 10 (got %d)", number)
			}
		case kind == "Mineral" && column == "ASP":
			if number < 1 || number > 8 {
				return fmt.Errorf("Mineral.ASP must be an integer from 1 to 8 (got %d)", number)
			}
		case kind == "Mineral" && MineralCoarseFragColumns[column]:
			if number < 0 || number > 100 {
				return fmt.Errorf("Mineral.%s must be between 0%% and 100%% (got %d%%)", column, number)
			}
		}
		return nil
	}
	return fmt.Errorf("unsupported %s value for %q", kind, column)
}

var MineralCoarseFragColumns = map[string]bool{
	"PercentCoarseFragsGravel":  true,
	"PercentCoarseFragsCobbles": true,
	"PercentCoarseFragsStones":  true,
	"PercentCoarseFragsTotal":   true,
}

// ValidateMineralCoarseFragments enforces LMH25 coarse-fragment component consistency
// when any coarse-fragment field on a Mineral row is created or edited (UX-SOIL-005):
// Gravel + Cobbles + Stones must not exceed 100%, and when Total is also recorded (>= 0),
// Gravel + Cobbles + Stones must not exceed Total.
func ValidateMineralCoarseFragments(gravel, cobbles, stones, total *int) error {
	sum := 0
	hasComponent := false
	for _, item := range []struct {
		name string
		val  *int
	}{
		{"PercentCoarseFragsGravel", gravel},
		{"PercentCoarseFragsCobbles", cobbles},
		{"PercentCoarseFragsStones", stones},
	} {
		if item.val != nil {
			if *item.val < 0 || *item.val > 100 {
				return fmt.Errorf("Mineral.%s must be between 0%% and 100%% (got %d%%)", item.name, *item.val)
			}
			sum += *item.val
			hasComponent = true
		}
	}
	if hasComponent && sum > 100 {
		return fmt.Errorf("Mineral coarse fragments Gravel + Cobbles + Stones (%d%%) cannot exceed 100%%", sum)
	}
	if hasComponent && total != nil && *total >= 0 && sum > *total {
		return fmt.Errorf("Mineral coarse fragments Gravel + Cobbles + Stones (%d%%) cannot exceed PercentCoarseFragsTotal (%d%%)", sum, *total)
	}
	return nil
}

var NonNegativeParentIntegerColumns = map[string]bool{
	"RootingDepth":         true,
	"RootRestrictingDepth": true,
	"SeepageDepth":         true,
}

var ParentSiteIntegerColumns = map[string]bool{
	"Aspect":           true,
	"StartDate":        true,
	"Elevation":        true,
	"StandAge":         true,
	"LocationAccuracy": true,
}

var ParentSubstrateSingleColumns = map[string]bool{
	"SubstrateBedRock":       true,
	"SubstrateDecWood":       true,
	"SubstrateMineralSoil":   true,
	"SubstrateOrganicMatter": true,
	"SubstrateRocks":         true,
	"SubstrateWater":         true,
}

var NonNegativeParentSingleColumns = map[string]bool{
	"HumusThickness":       true,
	"SV_SoilDepth":         true,
	"SV_WaterTableCM":      true,
	"SV_GleyingMottlingCM": true,
	"SV_AhorizonDepth":     true,
	"ActiveLayerDepth":     true,
}

var surveyDatePattern = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2})( \d{2}:\d{2}:\d{2}(\.\d{1,9})?)?$`)

// ValidateSurveyDateText validates new or edited Env.Date values as real calendar dates
// in YYYY-MM-DD format (optionally followed by wall-clock HH:MM:SS[.fraction] without timezone).
func ValidateSurveyDateText(value *string) error {
	if value == nil {
		return nil
	}
	raw := *value
	if !utf8.ValidString(raw) || strings.ContainsRune(raw, 0) {
		return fmt.Errorf("Date must be valid UTF-8 text without NUL bytes")
	}
	for _, r := range raw {
		if r >= 0xD800 && r <= 0xDFFF {
			return fmt.Errorf("Date contains an unpaired UTF-16 surrogate")
		}
	}
	m := surveyDatePattern.FindStringSubmatch(raw)
	if m == nil {
		return fmt.Errorf("Date must use YYYY-MM-DD calendar format (got %q)", raw)
	}
	var parsed time.Time
	var err error
	if m[2] == "" {
		parsed, err = time.Parse("2006-01-02", raw)
	} else {
		parsed, err = time.Parse("2006-01-02 15:04:05.999999999", raw)
	}
	if err != nil || parsed.Year() < 100 || parsed.Year() > 9999 {
		return fmt.Errorf("Date must be a valid calendar date in YYYY-MM-DD format (got %q)", raw)
	}
	return nil
}

func ValidateParentSoilInteger(column string, value *int) error {
	if err := ValidateOrdinaryInteger(column, value); err != nil {
		return err
	}
	if value == nil {
		return nil
	}
	if NonNegativeParentIntegerColumns[column] && *value < 0 {
		return fmt.Errorf("%s must be >= 0 cm (got %d)", column, *value)
	}
	switch column {
	case "Aspect":
		if *value != 999 && (*value < 0 || *value > 360) {
			return fmt.Errorf("Aspect must be between 0 and 360 degrees or 999 for level ground (got %d)", *value)
		}
	case "StartDate":
		if *value < 1900 || *value > 2500 {
			return fmt.Errorf("StartDate (survey year) must be between 1900 and 2500 (got %d)", *value)
		}
	case "Elevation":
		if *value < 0 || *value > 9000 {
			return fmt.Errorf("Elevation must be between 0 and 9000 m above sea level (got %d)", *value)
		}
	case "StandAge":
		if *value < 0 {
			return fmt.Errorf("StandAge must be >= 0 years (got %d)", *value)
		}
	case "LocationAccuracy":
		if *value < 0 {
			return fmt.Errorf("LocationAccuracy must be >= 0 m (got %d)", *value)
		}
	}
	return nil
}

func ValidateParentSoilSingle(column string, before, after *float64) error {
	if err := ValidateSingleRangeChange(column, before, after); err != nil {
		return err
	}
	if after == nil || SameHeightValue(before, after) {
		return nil
	}
	if (column == "SV_PercentCoarseFrags" || ParentSubstrateSingleColumns[column]) && (*after < 0 || *after > 100) {
		return fmt.Errorf("%s must be between 0%% and 100%% (got %v)", column, *after)
	}
	if column == "SlopeGradient" && *after < 0 {
		return fmt.Errorf("SlopeGradient must be >= 0%% (got %v)", *after)
	}
	if NonNegativeParentSingleColumns[column] && *after < 0 {
		return fmt.Errorf("%s must be >= 0 cm (got %v)", column, *after)
	}
	return nil
}

func validateChildField(kind, column string, value any) error {
	if kind == "Veg" {
		return ValidateVegetationField(column, value)
	}
	if kind == "Other" {
		return ValidateOtherField(column, value)
	}
	return ValidateSoilChildField(kind, column, value)
}

// Soil horizon classes used by the LMH25 (2023) depth-sign rule (AGENTS.md §3.4).
const (
	SoilHorizonUnknown = ""
	SoilHorizonUpland  = "upland"  // L/F/H: measured upward from 0 cm, UpperDepth > LowerDepth
	SoilHorizonWetland = "wetland" // O*/Hydric/Limno/Cumulo: measured downward, UpperDepth < LowerDepth
	SoilHorizonMineral = "mineral" // every SoilMineral row: measured downward, UpperDepth < LowerDepth
)

// stripSoilDiscontinuityPrefix removes a leading lithologic-discontinuity marker: Arabic digits
// (2Of, 3Ah) or a Roman numeral (IIOf, IXAh, XAh). No LMH25 horizon designation starts with I, V or X.
func stripSoilDiscontinuityPrefix(horizon string) string {
	return strings.TrimSpace(strings.TrimLeft(strings.ToUpper(strings.TrimSpace(horizon)), "0123456789IVX"))
}

// ClassifySoilHorizon is the single LMH25 horizon classifier shared by every write and read path.
func ClassifySoilHorizon(kind, horizon string) string {
	if kind == "Mineral" {
		return SoilHorizonMineral
	}
	if kind != "Humus" {
		return SoilHorizonUnknown
	}
	hz := stripSoilDiscontinuityPrefix(horizon)
	switch {
	case hz == "":
		return SoilHorizonUnknown
	case strings.HasPrefix(hz, "HYDRIC"), strings.HasPrefix(hz, "LIMNO"), strings.HasPrefix(hz, "CUMULO"), strings.HasPrefix(hz, "O"):
		return SoilHorizonWetland
	case strings.HasPrefix(hz, "L"), strings.HasPrefix(hz, "F"), strings.HasPrefix(hz, "H"):
		return SoilHorizonUpland
	}
	return SoilHorizonUnknown
}

// ValidateSoilHorizonDepthSign is the only LMH25 horizon depth rule in the app (ENG-GO-005):
//   - every non-NULL depth must be finite and >= 0 cm;
//   - upland L/F/H humus requires UpperDepth > LowerDepth;
//   - wetland O*/Hydric/Limno/Cumulo humus and every mineral row (including a blank
//     Horizon) require UpperDepth < LowerDepth.
//
// Discontinuity prefixes (2Of, IIOf, XAh) are stripped before classification.
func ValidateSoilHorizonDepthSign(kind string, horizon *string, upperDepth, lowerDepth *float64) error {
	label := ""
	if horizon != nil {
		label = strings.TrimSpace(*horizon)
	}
	for _, depth := range []*float64{upperDepth, lowerDepth} {
		if depth == nil {
			continue
		}
		if math.IsNaN(*depth) || math.IsInf(*depth, 0) || *depth < 0 {
			return fmt.Errorf("%s horizon %q depths must be finite and >= 0 cm", kind, label)
		}
	}
	if upperDepth == nil || lowerDepth == nil {
		return nil
	}
	class := SoilHorizonUnknown
	if kind == "Mineral" {
		class = SoilHorizonMineral
	} else if horizon != nil {
		class = ClassifySoilHorizon(kind, *horizon)
	}
	switch class {
	case SoilHorizonUpland:
		if !(*upperDepth > *lowerDepth) {
			return fmt.Errorf("Humus upland horizon %q is measured upward from 0 cm and requires UpperDepth > LowerDepth (got %v .. %v)", label, *upperDepth, *lowerDepth)
		}
	case SoilHorizonWetland:
		if !(*upperDepth < *lowerDepth) {
			return fmt.Errorf("Humus wetland horizon %q is measured downward and requires UpperDepth < LowerDepth (got %v .. %v)", label, *upperDepth, *lowerDepth)
		}
	case SoilHorizonMineral:
		if !(*upperDepth < *lowerDepth) {
			return fmt.Errorf("Mineral horizon %q is measured downward and requires UpperDepth < LowerDepth (got %v .. %v)", label, *upperDepth, *lowerDepth)
		}
	}
	return nil
}

// HumusOrderBySQL returns ORDER BY terms that list humus horizons the way LMH25 profiles are read
// top to bottom (AGENTS.md §3.4, ENG-GO-005): upland L/F/H first by UpperDepth DESC, then wetland
// O*/Hydric/Limno/Cumulo by UpperDepth ASC, with NULL depths last. The wetland test mirrors
// ClassifySoilHorizon, including discontinuity-prefix stripping. Arguments are SQL expressions.
func HumusOrderBySQL(horizonExpr, upperDepthExpr string) string {
	norm := `LTRIM(UPPER(TRIM(COALESCE(` + horizonExpr + `, ''))), '0123456789IVX ')`
	wetland := `(` + norm + ` LIKE 'O%' OR ` + norm + ` LIKE 'HYDRIC%' OR ` + norm + ` LIKE 'LIMNO%' OR ` + norm + ` LIKE 'CUMULO%')`
	return `CASE WHEN ` + wetland + ` THEN 1 ELSE 0 END ASC, ` +
		`CASE WHEN ` + upperDepthExpr + ` IS NULL THEN 1 ELSE 0 END ASC, ` +
		`CASE WHEN ` + wetland + ` THEN ` + upperDepthExpr + ` ELSE -` + upperDepthExpr + ` END ASC`
}
