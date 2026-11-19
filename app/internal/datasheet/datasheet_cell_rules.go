package datasheet

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func parseFlexibleBoolean(raw string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "true", "-1", "1", "yes", "y":
		return true, nil
	case "false", "0", "no", "n":
		return false, nil
	default:
		return false, fmt.Errorf("invalid Access boolean value %q", raw)
	}
}

func cellToDisplayString(cell vprocore.ProjectMetadataCell, isBool bool) string {
	switch cell.Storage {
	case "null":
		return ""
	case "text":
		if cell.Text != nil {
			return *cell.Text
		}
	case "integer":
		if cell.Integer != nil {
			if isBool {
				if *cell.Integer == "0" {
					return "false"
				}
				return "true"
			}
			return *cell.Integer
		}
	case "real":
		if cell.Real != nil {
			return vprocore.SourceDoubleDecimalString(*cell.Real)
		}
	case "blob":
		if cell.BlobHex != nil {
			return *cell.BlobHex
		}
	}
	return ""
}

func buildReplacedCellFromString(colMeta DatasheetColumnMeta, replaced string) (vprocore.ProjectMetadataCell, error) {
	if replaced == "" {
		return vprocore.ProjectMetadataCell{Storage: "null"}, nil
	}
	switch colMeta.Kind {
	case "boolean":
		b, err := parseFlexibleBoolean(replaced)
		if err != nil {
			return vprocore.ProjectMetadataCell{}, err
		}
		stored := "0"
		if b {
			stored = "-1"
		}
		return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &stored}, nil
	case "integer":
		n, err := strconv.ParseInt(strings.TrimSpace(replaced), 10, 64)
		if err != nil {
			return vprocore.ProjectMetadataCell{}, fmt.Errorf("%s requires an integer value, got %q", colMeta.Name, replaced)
		}
		stored := strconv.FormatInt(n, 10)
		return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &stored}, nil
	case "single", "double":
		f, err := strconv.ParseFloat(strings.TrimSpace(replaced), 64)
		if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
			return vprocore.ProjectMetadataCell{}, fmt.Errorf("%s requires a finite number, got %q", colMeta.Name, replaced)
		}
		return vprocore.ProjectMetadataCell{Storage: "real", Real: &f}, nil
	default:
		val := replaced
		return vprocore.ProjectMetadataCell{Storage: "text", Text: &val}, nil
	}
}

func isProtectedDatasheetColumn(tableKey string, colMeta DatasheetColumnMeta, canEditMaster bool) bool {
	if !colMeta.Editable {
		return true
	}
	if colMeta.Protected && !(tableKey == "Admin" && colMeta.Name == "BECSiteUnit" && canEditMaster) {
		return true
	}
	return false
}

// validateAndNormalizeDatasheetCell validates a proposed cell value against VP08 rules
// (UTF-16 bounds, IEEE-754 float32 <100 cover narrowing, Access BOOLEAN -1/0, integer ranges)
// and returns the SQLite driver storage value plus canonical audit string.
func validateAndNormalizeDatasheetCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	after vprocore.ProjectMetadataCell,
	canEditMaster bool,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	if err := checkDatasheetColumnEditPermission(tableKey, colMeta, canEditMaster); err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	rawVal, err := vprocore.MetadataCellValue(after)
	if err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s: %w", tableKey, colMeta.Name, err)
	}
	if rawVal == nil {
		if isRequiredNonNullDatasheetColumn(tableKey, colMeta.Name) {
			return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s cannot be NULL", tableKey, colMeta.Name)
		}
		return nil, nil, vprocore.ProjectMetadataCell{Storage: "null"}, nil
	}
	if colMeta.IsBoolean {
		return normalizeDatasheetBooleanCell(tableKey, colMeta, rawVal)
	}
	switch colMeta.Kind {
	case "text":
		return normalizeDatasheetTextCell(tableKey, colMeta, rawVal)
	case "integer":
		return normalizeDatasheetIntegerCell(tableKey, colMeta, rawVal)
	case "single":
		return normalizeDatasheetSingleCell(tableKey, colMeta, rawVal)
	case "double":
		return normalizeDatasheetDoubleCell(tableKey, colMeta, rawVal)
	default:
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("unsupported column kind %q for %s.%s", colMeta.Kind, tableKey, colMeta.Name)
	}
}

func checkDatasheetColumnEditPermission(tableKey string, colMeta DatasheetColumnMeta, canEditMaster bool) error {
	if tableKey == "Admin" && colMeta.Name == "BECSiteUnit" && !canEditMaster {
		return errors.New("BEC Master editing is restricted to the source-authorized user; use UserSiteUnit instead")
	}
	if isProtectedDatasheetColumn(tableKey, colMeta, canEditMaster) {
		return fmt.Errorf("column %s.%s is protected or read-only in datasheet mode", tableKey, colMeta.Name)
	}
	return nil
}

func isRequiredNonNullDatasheetColumn(tableKey, colName string) bool {
	switch tableKey {
	case "Env", "Humus", "Mineral", "Other":
		return colName == "PlotNumber"
	case "Admin":
		return colName == "Plot"
	case "Veg":
		return colName == "PlotNumber" || colName == "Species"
	case "Hierarchy":
		return colName == "Name"
	default:
		return false
	}
}

func normalizeDatasheetBooleanCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	rawVal any,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	var flag bool
	switch v := rawVal.(type) {
	case int64:
		flag = v != 0
	case string:
		parsed, err := parseFlexibleBoolean(v)
		if err != nil {
			return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s: %w", tableKey, colMeta.Name, err)
		}
		flag = parsed
	default:
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s requires Access BOOLEAN (-1 or 0)", tableKey, colMeta.Name)
	}
	var stored int64
	auditText := "0"
	if flag {
		stored = -1
		auditText = "-1"
	}
	s := strconv.FormatInt(stored, 10)
	return stored, &auditText, vprocore.ProjectMetadataCell{Storage: "integer", Integer: &s}, nil
}

func normalizeDatasheetTextCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	rawVal any,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	text, err := coerceDatasheetText(tableKey, colMeta.Name, rawVal)
	if err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	if err := validateDatasheetTextConstraints(tableKey, colMeta, text); err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	auditCopy := text
	cellCopy := text
	return text, &auditCopy, vprocore.ProjectMetadataCell{Storage: "text", Text: &cellCopy}, nil
}

func coerceDatasheetText(tableKey, colName string, rawVal any) (string, error) {
	switch v := rawVal.(type) {
	case string:
		return v, nil
	case int64:
		return strconv.FormatInt(v, 10), nil
	case float64:
		return vprocore.SourceDoubleDecimalString(v), nil
	default:
		return "", fmt.Errorf("%s.%s requires valid Unicode text", tableKey, colName)
	}
}

func validateDatasheetTextConstraints(tableKey string, colMeta DatasheetColumnMeta, text string) error {
	if !utf8.ValidString(text) || strings.ContainsRune(text, 0) {
		return fmt.Errorf("%s.%s requires valid UTF-8 text without NUL", tableKey, colMeta.Name)
	}
	for _, r := range text {
		if r >= 0xD800 && r <= 0xDFFF {
			return fmt.Errorf("%s.%s contains unpaired UTF-16 surrogate", tableKey, colMeta.Name)
		}
	}
	if strings.TrimSpace(text) == "" && isRequiredNonBlankDatasheetText(tableKey, colMeta.Name) {
		return fmt.Errorf("%s.%s cannot be blank", tableKey, colMeta.Name)
	}
	if (colMeta.Name == "PlotNumber" || colMeta.Name == "Plot") && text != strings.TrimSpace(text) {
		return fmt.Errorf("%s.%s must not have leading or trailing whitespace", tableKey, colMeta.Name)
	}
	if colMeta.MaxUTF16 > 0 && len(utf16.Encode([]rune(text))) > colMeta.MaxUTF16 {
		return fmt.Errorf("%s.%s cannot exceed %d characters", tableKey, colMeta.Name, colMeta.MaxUTF16)
	}
	if tableKey == "Env" && colMeta.Name == "Date" {
		if err := vprocore.ValidateSurveyDateText(&text); err != nil {
			return fmt.Errorf("Env.%s", err.Error())
		}
	}
	return nil
}

func isRequiredNonBlankDatasheetText(tableKey, colName string) bool {
	return colName == "PlotNumber" || colName == "Plot" ||
		(tableKey == "Veg" && colName == "Species") ||
		(tableKey == "Hierarchy" && colName == "Name")
}

func normalizeDatasheetIntegerCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	rawVal any,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	num, err := coerceDatasheetInt64(tableKey, colMeta.Name, rawVal)
	if err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	if err := validateDatasheetIntegerBounds(tableKey, colMeta, num); err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	s := strconv.FormatInt(num, 10)
	auditCopy := s
	return num, &auditCopy, vprocore.ProjectMetadataCell{Storage: "integer", Integer: &s}, nil
}

func coerceDatasheetInt64(tableKey, colName string, rawVal any) (int64, error) {
	switch v := rawVal.(type) {
	case int64:
		return v, nil
	case float64:
		if math.Trunc(v) != v || v < math.MinInt32 || v > math.MaxInt32 {
			return 0, fmt.Errorf("%s.%s requires a whole integer", tableKey, colName)
		}
		return int64(v), nil
	case string:
		parsed, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		if err != nil {
			return 0, fmt.Errorf("%s.%s requires an integer", tableKey, colName)
		}
		return parsed, nil
	default:
		return 0, fmt.Errorf("%s.%s requires an integer", tableKey, colName)
	}
}

func validateDatasheetIntegerBounds(tableKey string, colMeta DatasheetColumnMeta, num int64) error {
	if datasheetInt32Columns[tableKey][colMeta.Name] || strings.EqualFold(colMeta.DeclaredType, "INTEGER") {
		if num < math.MinInt32 || num > math.MaxInt32 {
			return fmt.Errorf("%s.%s exceeds Access Long range (-2147483648..2147483647)", tableKey, colMeta.Name)
		}
	} else if num < -32768 || num > 32767 {
		return fmt.Errorf("%s.%s exceeds Access Integer range (-32768..32767)", tableKey, colMeta.Name)
	}
	if tableKey == "Hierarchy" && colMeta.Name == "Level" && (num < 1 || num > 11) {
		return fmt.Errorf("Hierarchy.Level must be between 1 and 11, got %d", num)
	}
	if vprocore.SoilChildIntegerColumns[tableKey][colMeta.Name] {
		if err := vprocore.ValidateSoilChildField(tableKey, colMeta.Name, int(num)); err != nil {
			return err
		}
	}
	if (tableKey == "Env" || tableKey == "Admin") && (vprocore.NonNegativeParentIntegerColumns[colMeta.Name] || vprocore.ParentSiteIntegerColumns[colMeta.Name]) {
		intVal := int(num)
		if err := vprocore.ValidateParentSoilInteger(colMeta.Name, &intVal); err != nil {
			return fmt.Errorf("%s.%s", tableKey, err.Error())
		}
	}
	return nil
}

func coerceDatasheetFloat64(tableKey, colName string, rawVal any) (float64, error) {
	switch v := rawVal.(type) {
	case float64:
		return v, nil
	case int64:
		return float64(v), nil
	case string:
		parsed, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err != nil {
			return 0, fmt.Errorf("%s.%s requires a finite number", tableKey, colName)
		}
		return parsed, nil
	default:
		return 0, fmt.Errorf("%s.%s requires a finite number", tableKey, colName)
	}
}

func normalizeDatasheetSingleCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	rawVal any,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	num, err := coerceDatasheetFloat64(tableKey, colMeta.Name, rawVal)
	if err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	if math.IsNaN(num) || math.IsInf(num, 0) || math.Abs(num) > math.MaxFloat32 {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s is outside the supported numeric range", tableKey, colMeta.Name)
	}
	// Narrow float64 to float32 BEFORE evaluating `< 100 Or Is Null`!
	narrowed32 := float32(num)
	if math.IsNaN(float64(narrowed32)) || math.IsInf(float64(narrowed32), 0) {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s is too large for a numeric field", tableKey, colMeta.Name)
	}
	if colMeta.IsCoverSingle {
		if narrowed32 >= 100 {
			return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s must be from 0 to under 100%% (e.g. 99.9%%) or blank", tableKey, colMeta.Name)
		}
		if narrowed32 < 0 {
			return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s cover cannot be negative", tableKey, colMeta.Name)
		}
	}
	stored := float64(narrowed32)
	if stored == 0 {
		stored = 0 // normalize -0 to +0
	}
	if err := validateDatasheetSingleDomainBounds(tableKey, colMeta.Name, stored); err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	auditCopy := vprocore.SourceDoubleDecimalString(stored)
	cellVal := stored
	return stored, &auditCopy, vprocore.ProjectMetadataCell{Storage: "real", Real: &cellVal}, nil
}

func validateDatasheetSingleDomainBounds(tableKey, colName string, stored float64) error {
	if vprocore.SoilChildSingleColumns[tableKey][colName] {
		if err := vprocore.ValidateSoilChildField(tableKey, colName, stored); err != nil {
			return err
		}
	}
	if tableKey == "Env" || tableKey == "Admin" {
		if err := vprocore.ValidateParentSoilSingle(colName, nil, &stored); err != nil {
			return fmt.Errorf("%s.%s", tableKey, err.Error())
		}
	}
	return nil
}

func normalizeDatasheetDoubleCell(
	tableKey string,
	colMeta DatasheetColumnMeta,
	rawVal any,
) (any, *string, vprocore.ProjectMetadataCell, error) {
	num, err := coerceDatasheetFloat64(tableKey, colMeta.Name, rawVal)
	if err != nil {
		return nil, nil, vprocore.ProjectMetadataCell{}, err
	}
	if math.IsNaN(num) || math.IsInf(num, 0) {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("%s.%s must be finite", tableKey, colMeta.Name)
	}
	if tableKey == "Env" && colMeta.Name == "Latitude" && (num < -90 || num > 90) {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("Env.Latitude must be between -90 and 90 degrees (got %v)", num)
	}
	if tableKey == "Env" && colMeta.Name == "Longitude" && (num < -180 || num > 180) {
		return nil, nil, vprocore.ProjectMetadataCell{}, fmt.Errorf("Env.Longitude must be between -180 and 180 degrees (got %v)", num)
	}
	if num == 0 {
		num = 0
	}
	auditCopy := vprocore.SourceDoubleDecimalString(num)
	cellVal := num
	return num, &auditCopy, vprocore.ProjectMetadataCell{Storage: "real", Real: &cellVal}, nil
}

func auditTextForStoredCell(cell vprocore.ProjectMetadataCell, isBool bool) *string {
	switch cell.Storage {
	case "null":
		return nil
	case "text":
		if cell.Text == nil {
			return nil
		}
		s := *cell.Text
		return &s
	case "integer":
		if cell.Integer == nil {
			return nil
		}
		if isBool {
			if *cell.Integer == "0" {
				s := "0"
				return &s
			}
			s := "-1"
			return &s
		}
		s := *cell.Integer
		return &s
	case "real":
		if cell.Real == nil {
			return nil
		}
		s := vprocore.SourceDoubleDecimalString(*cell.Real)
		return &s
	case "blob":
		if cell.BlobHex == nil {
			return nil
		}
		s := *cell.BlobHex
		return &s
	}
	return nil
}

func datasheetCellsSemanticallyEqual(a, b vprocore.ProjectMetadataCell, colMeta DatasheetColumnMeta) bool {
	if a.Storage == "null" && b.Storage == "null" {
		return true
	}
	if colMeta.IsBoolean && a.Storage == "integer" && b.Storage == "integer" && a.Integer != nil && b.Integer != nil {
		aTrue := *a.Integer != "0"
		bTrue := *b.Integer != "0"
		return aTrue == bTrue
	}
	if colMeta.Kind == "single" && a.Storage == "real" && b.Storage == "real" && a.Real != nil && b.Real != nil {
		return float32(*a.Real) == float32(*b.Real) && math.Signbit(*a.Real) == math.Signbit(*b.Real)
	}
	return vprocore.MetadataCellEqual(a, b)
}

// validateSoilHorizonDepthSign delegates to the single LMH25 rule in vprocore (ENG-GO-005).
func validateSoilHorizonDepthSign(tableKey string, horizon *string, upper, lower *float64) error {
	return vprocore.ValidateSoilHorizonDepthSign(tableKey, horizon, upper, lower)
}

func cellTextPtr(cell vprocore.ProjectMetadataCell) *string {
	if cell.Storage == "null" || cell.Text == nil {
		return nil
	}
	s := *cell.Text
	return &s
}

func cellFloat64Ptr(cell vprocore.ProjectMetadataCell) *float64 {
	if cell.Storage == "null" {
		return nil
	}
	if cell.Real != nil {
		v := *cell.Real
		return &v
	}
	if cell.Integer != nil {
		if n, err := strconv.ParseFloat(*cell.Integer, 64); err == nil {
			return &n
		}
	}
	return nil
}

func cellIntPtr(cell vprocore.ProjectMetadataCell) *int {
	if cell.Storage == "null" {
		return nil
	}
	if cell.Integer != nil {
		if n, err := strconv.Atoi(strings.TrimSpace(*cell.Integer)); err == nil {
			return &n
		}
	}
	if cell.Real != nil && math.Trunc(*cell.Real) == *cell.Real && math.Abs(*cell.Real) <= 32767 {
		v := int(*cell.Real)
		return &v
	}
	return nil
}

func validateMineralCoarseFragsCells(gravel, cobbles, stones, total vprocore.ProjectMetadataCell) error {
	return vprocore.ValidateMineralCoarseFragments(
		cellIntPtr(gravel),
		cellIntPtr(cobbles),
		cellIntPtr(stones),
		cellIntPtr(total),
	)
}
