package diagnostics

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
)

var pow10Uint64 = [20]uint64{
	1, 10, 100, 1000, 10000,
	100000, 1000000, 10000000, 100000000, 1000000000,
	10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000,
	1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000, 10000000000000000000,
}

var crosstabCodeTable = [6][10]string{
	{},
	{"1 - +", "1 - 1", "1 - 2", "1 - 3", "1 - 4", "1 - 5", "1 - 6", "1 - 7", "1 - 8", "1 - 9"},
	{"2 - +", "2 - 1", "2 - 2", "2 - 3", "2 - 4", "2 - 5", "2 - 6", "2 - 7", "2 - 8", "2 - 9"},
	{"3 - +", "3 - 1", "3 - 2", "3 - 3", "3 - 4", "3 - 5", "3 - 6", "3 - 7", "3 - 8", "3 - 9"},
	{"4 - +", "4 - 1", "4 - 2", "4 - 3", "4 - 4", "4 - 5", "4 - 6", "4 - 7", "4 - 8", "4 - 9"},
	{"5 - +", "5 - 1", "5 - 2", "5 - 3", "5 - 4", "5 - 5", "5 - 6", "5 - 7", "5 - 8", "5 - 9"},
}

// ace15ScaledUint64 computes round_half_away(15_sig_digits(|value|) * 10^decimals) on the stack
// without allocating math/big objects when the scaled integer fits comfortably in uint64.
func ace15ScaledUint64(value float64, decimals int) (scaled uint64, negative bool, ok bool) {
	if decimals < 0 || decimals > 9 || math.IsNaN(value) || math.IsInf(value, 0) {
		return 0, false, false
	}
	if value == 0 {
		return 0, false, true
	}
	negative = value < 0
	absVal := math.Abs(value)

	var sci [32]byte
	b := strconv.AppendFloat(sci[:0], absVal, 'e', 14, 64)
	// Format is d.ddddddddddddddE±dd (e.g. "1.00500000000000e+00", len >= 20)
	eIdx := -1
	for i := 0; i < len(b); i++ {
		if b[i] == 'e' || b[i] == 'E' {
			eIdx = i
			break
		}
	}
	if eIdx != 16 || b[1] != '.' {
		return 0, false, false
	}
	mant := uint64(b[0] - '0')
	for i := 2; i < 16; i++ {
		mant = mant*10 + uint64(b[i]-'0')
	}
	expSign := 1
	expPos := eIdx + 1
	if expPos >= len(b) {
		return 0, false, false
	}
	if b[expPos] == '-' {
		expSign = -1
		expPos++
	} else if b[expPos] == '+' {
		expPos++
	}
	expVal := 0
	for ; expPos < len(b); expPos++ {
		if b[expPos] < '0' || b[expPos] > '9' {
			return 0, false, false
		}
		expVal = expVal*10 + int(b[expPos]-'0')
	}
	exp := expSign * expVal

	k := exp - 14 + decimals
	if k >= 0 {
		if k > 4 {
			return 0, false, false
		}
		return mant * pow10Uint64[k], negative, true
	}
	negK := -k
	if negK > 16 {
		return 0, false, true
	}
	div := pow10Uint64[negK]
	q := mant / div
	rem := mant % div
	if rem >= (div+1)/2 && (div%2 == 0 && rem*2 >= div || div%2 != 0) {
		q++
	}
	if q == 0 {
		negative = false
	}
	return q, negative, true
}

func formatScaledDecimalBytes(dst []byte, scaled uint64, negative bool, decimals int) []byte {
	if negative && scaled != 0 {
		dst = append(dst, '-')
	}
	if decimals == 0 {
		return strconv.AppendUint(dst, scaled, 10)
	}
	var digits [24]byte
	raw := strconv.AppendUint(digits[:0], scaled, 10)
	if len(raw) <= decimals {
		dst = append(dst, '0', '.')
		for i := 0; i < decimals-len(raw); i++ {
			dst = append(dst, '0')
		}
		dst = append(dst, raw...)
		return dst
	}
	split := len(raw) - decimals
	dst = append(dst, raw[:split]...)
	dst = append(dst, '.')
	dst = append(dst, raw[split:]...)
	return dst
}

// FormatACE15 formats a float64 via Access/DAO 15-significant-digit half-away rounding.
func FormatACE15(value float64, decimals int) string {
	if scaled, neg, ok := ace15ScaledUint64(value, decimals); ok {
		var buf [32]byte
		return string(formatScaledDecimalBytes(buf[:0], scaled, neg, decimals))
	}
	return reportcore.SiteUnitFixedNumber(value, decimals, 1)
}

// RoundACE15 returns the numeric float64 value after ACE 15-significant-digit half-away rounding.
func RoundACE15(value float64, decimals int) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return 0
	}
	if scaled, neg, ok := ace15ScaledUint64(value, decimals); ok {
		if scaled == 0 {
			return 0
		}
		if decimals == 0 {
			res := float64(scaled)
			if neg {
				return -res
			}
			return res
		}
		var buf [32]byte
		s := formatScaledDecimalBytes(buf[:0], scaled, neg, decimals)
		if parsed, err := strconv.ParseFloat(string(s), 64); err == nil {
			return parsed
		}
	}
	parsed, err := strconv.ParseFloat(FormatACE15(value, decimals), 64)
	if err != nil {
		return value
	}
	return parsed
}

// DiagnosticPresenceClass maps a unit presence ratio in [0, 1] to (1..5, "I".."V")
// matching V7mdlDiagnostic.DiagnosticPresenceClass & V7mdlValueConversions.Presence2Class.
func DiagnosticPresenceClass(ratio float64) (int, string) {
	if ratio <= 0.2 {
		return 1, "I"
	}
	if ratio <= 0.4 {
		return 2, "II"
	}
	if ratio <= 0.6 {
		return 3, "III"
	}
	if ratio <= 0.8 {
		return 4, "IV"
	}
	return 5, "V"
}

// DominKrajinaSignifClass maps a mean cover percentage to Domin-Krajina Significance Class
// ("+", "1".."9") and its numeric Diagnostic weight (0 for "+", 1..9 otherwise),
// matching V7mdlValueConversions.SignifClass.
func DominKrajinaSignifClass(signif float64) (string, int) {
	switch {
	case signif <= 0.3:
		return "+", 0
	case signif <= 1.0:
		return "1", 1
	case signif <= 2.2:
		return "2", 2
	case signif <= 5.0:
		return "3", 3
	case signif <= 10.0:
		return "4", 4
	case signif <= 20.0:
		return "5", 5
	case signif <= 33.0:
		return "6", 6
	case signif <= 50.0:
		return "7", 7
	case signif <= 75.0:
		return "8", 8
	default:
		return "9", 9
	}
}

// FormatUnitCrosstabCode formats the Access MyRS5 crosstab string ("1 - +" .. "5 - 9").
func FormatUnitCrosstabCode(presenceClass int, signifClass string) string {
	if presenceClass < 1 || presenceClass > 5 || len(signifClass) != 1 {
		if presenceClass < 1 || presenceClass > 5 || signifClass == "" {
			return ""
		}
		return fmt.Sprintf("%d - %s", presenceClass, signifClass)
	}
	c := signifClass[0]
	if c == '+' {
		return crosstabCodeTable[presenceClass][0]
	}
	if c >= '1' && c <= '9' {
		return crosstabCodeTable[presenceClass][c-'0']
	}
	return fmt.Sprintf("%d - %s", presenceClass, signifClass)
}

func parseCrosstabCodeFast(raw string) (pres int, sig int, ok bool) {
	if len(raw) != 5 || raw[1] != ' ' || raw[2] != '-' || raw[3] != ' ' {
		return 0, 0, false
	}
	if raw[0] < '1' || raw[0] > '5' {
		return 0, 0, false
	}
	pres = int(raw[0] - '0')
	if raw[4] == '+' {
		return pres, 0, true
	}
	if raw[4] >= '1' && raw[4] <= '9' {
		return pres, int(raw[4] - '0'), true
	}
	return 0, 0, false
}

// ClassifySpeciesDiagnostic evaluates BEC differential & diagnostic categories across ordered units,
// matching V7mdlDiagnostic.Diagnostic and vpro_diagnostic_classify(unit_codes) exactly.
func ClassifySpeciesDiagnostic(orderedUnits []OrderedUnitCode) (DiagnosticClassification, error) {
	if len(orderedUnits) == 0 {
		return DiagnosticClassification{}, errors.New("ordered unit codes must be non-empty")
	}
	seenUnits := make(map[string]struct{}, len(orderedUnits))
	type presentEntry struct {
		unit         string
		presence     int
		significance int
	}
	present := make([]presentEntry, 0, len(orderedUnits))

	for _, item := range orderedUnits {
		if item.Unit == "" {
			return DiagnosticClassification{}, errors.New("ordered unit codes must have non-empty unit names")
		}
		if _, dup := seenUnits[item.Unit]; dup {
			return DiagnosticClassification{}, fmt.Errorf("duplicate unit %q in ordered unit codes", item.Unit)
		}
		seenUnits[item.Unit] = struct{}{}
		if item.Code == nil {
			continue
		}
		raw := *item.Code
		pres, sig, valid := parseCrosstabCodeFast(raw)
		if !valid {
			return DiagnosticClassification{}, fmt.Errorf("invalid unit crosstab code %q for unit %q; expected '1 - +' through '5 - 9'", raw, item.Unit)
		}
		present = append(present, presentEntry{
			unit:         item.Unit,
			presence:     pres,
			significance: sig,
		})
	}

	if len(present) == 0 {
		return DiagnosticClassification{}, nil
	}

	maximum := 0
	selected := 0
	for i, p := range present {
		if p.presence > maximum {
			maximum = p.presence
			selected = i
		}
	}
	selectedSignificance := present[selected].significance

	countPresence := 0
	countFive := 0
	countSignificance := 0
	for _, p := range present {
		if p.presence > maximum-2 {
			countPresence++
		}
		if p.presence == 5 {
			countFive++
		}
		if p.significance > selectedSignificance-2 {
			countSignificance++
		}
	}

	differential := countPresence == 1 && maximum >= 3
	dominantDifferential := countSignificance == 1 && !differential && selectedSignificance >= 5
	constantDominant := maximum == 5 && countPresence == 1 && selectedSignificance >= 5
	constant := maximum == 5 && countFive == 1 && selectedSignificance < 5
	importantCompanion := !differential && !dominantDifferential && !constantDominant && !constant && maximum >= 2 && countPresence == 1

	var codes []string
	if differential {
		codes = append(codes, "d")
	}
	if dominantDifferential {
		codes = append(codes, "dd")
	}
	if constantDominant {
		codes = append(codes, "cd")
	}
	if constant {
		codes = append(codes, "c")
	}
	if importantCompanion {
		codes = append(codes, "ic")
	}
	if len(codes) == 0 {
		return DiagnosticClassification{}, nil
	}
	return DiagnosticClassification{
		Unit:      present[selected].unit,
		Diagnosis: strings.Join(codes, ", "),
		Codes:     codes,
	}, nil
}

// LifeformLabel maps a VPro numeric Lifeform code (1..13) to its BEC display name and 4-stratum group.
func LifeformLabel(code *int) (string, string) {
	if code == nil {
		return "Unclassified", "Unclassified"
	}
	switch *code {
	case 1:
		return "Conifer Tree", "Tree"
	case 2:
		return "Deciduous Tree", "Tree"
	case 3:
		return "Evergreen Shrub", "Shrub"
	case 4:
		return "Deciduous Shrub", "Shrub"
	case 5:
		return "Fern", "Herb"
	case 6:
		return "Graminoid", "Herb"
	case 7:
		return "Forb", "Herb"
	case 8:
		return "Parasitic", "Herb"
	case 9:
		return "Moss", "Moss"
	case 10:
		return "Liverwort", "Moss"
	case 11:
		return "Lichen", "Moss"
	case 12:
		return "Dwarf Woody Plant", "Shrub"
	case 13:
		return "Macro Algae", "Moss"
	default:
		return fmt.Sprintf("Lifeform %d", *code), "Unclassified"
	}
}

func stratumSortRank(stratum string) int {
	switch stratum {
	case "Tree":
		return 1
	case "Shrub":
		return 2
	case "Herb":
		return 3
	case "Moss":
		return 4
	default:
		return 5
	}
}

func wildcardMatchLower(pattern, target string) bool {
	p := []rune(pattern)
	s := []rune(target)
	pi, si := 0, 0
	starIdx, matchIdx := -1, 0
	for si < len(s) {
		if pi < len(p) && (p[pi] == '?' || p[pi] == s[si]) {
			pi++
			si++
		} else if pi < len(p) && p[pi] == '*' {
			starIdx = pi
			matchIdx = si
			pi++
		} else if starIdx != -1 {
			pi = starIdx + 1
			matchIdx++
			si = matchIdx
		} else {
			return false
		}
	}
	for pi < len(p) && p[pi] == '*' {
		pi++
	}
	return pi == len(p)
}

// MatchUnitExcluded checks whether a SiteUnit matches BEC standard exclusions (.support/.poor/.nudum)
// or custom exclusion patterns.
func MatchUnitExcluded(siteUnit string, excludeStandard bool, customPatterns []string) (bool, string) {
	trimmed := strings.TrimSpace(siteUnit)
	if trimmed == "" {
		return false, ""
	}
	lowerUnit := strings.ToLower(trimmed)

	var patterns []string
	if excludeStandard {
		patterns = append(patterns, DefaultExcludedUnitModifiers...)
	}
	patterns = append(patterns, customPatterns...)

	for _, rawPat := range patterns {
		pat := strings.TrimSpace(rawPat)
		if pat == "" {
			continue
		}
		lowerPat := strings.ToLower(pat)
		if strings.ContainsAny(lowerPat, "*?") {
			if wildcardMatchLower(lowerPat, lowerUnit) {
				return true, rawPat
			}
			continue
		}
		if strings.HasPrefix(lowerPat, ".") {
			if strings.HasSuffix(lowerUnit, lowerPat) ||
				strings.Contains(lowerUnit, lowerPat+".") ||
				strings.Contains(lowerUnit, lowerPat+"-") ||
				strings.Contains(lowerUnit, lowerPat+"_") ||
				strings.Contains(lowerUnit, lowerPat+" ") {
				return true, rawPat
			}
			continue
		}
		if strings.Contains(lowerUnit, lowerPat) {
			return true, rawPat
		}
	}
	return false, ""
}
