package vprocore

import (
	"fmt"
	"math"
	"reflect"
	"strings"
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
		return ValidateSingleRangeChange(kind+"."+column, nil, &number)
	}
	if SoilChildIntegerColumns[kind][column] {
		if value == nil {
			return nil
		}
		number, ok := value.(int)
		if !ok {
			return fmt.Errorf("%s.%s requires a nullable integer", kind, column)
		}
		return ValidateOrdinaryInteger(kind+"."+column, &number)
	}
	return fmt.Errorf("unsupported %s value for %q", kind, column)
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
