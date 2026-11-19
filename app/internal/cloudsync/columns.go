package cloudsync

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// ColumnSpec defines a canonical column across VP08 SQLite and PostgreSQL schemas.
type ColumnSpec struct {
	Name           string
	PGType         string // "TEXT" | "BIGINT" | "DOUBLE PRECISION" | "SMALLINT"
	SQLiteType     string
	IsAccessBool   bool
	IsSingleCover  bool
	UTF16MaxLength int
}

func quotePGIdent(name string) string {
	return `"` + strings.ReplaceAll(name, `"`, `""`) + `"`
}

func columnDDL(col ColumnSpec) string {
	ddl := quotePGIdent(col.Name) + " " + col.PGType
	if col.IsAccessBool {
		ddl += fmt.Sprintf(" CHECK (%s IN (-1, 0))", quotePGIdent(col.Name))
	}
	return ddl
}

func columnNames(cols []ColumnSpec) []string {
	names := make([]string, len(cols))
	for i, c := range cols {
		names[i] = c.Name
	}
	return names
}

func quotedColumnCSV(cols []ColumnSpec) string {
	parts := make([]string, len(cols))
	for i, c := range cols {
		parts[i] = quotePGIdent(c.Name)
	}
	return strings.Join(parts, ", ")
}

// sqliteSelectColumnsCSV wraps PGType=="TEXT" columns in CAST(... AS BLOB) when typeof='text'
// so mattn/go-sqlite3 never parses TIMESTAMP-declared text cells into Go time.Time (+0000 UTC / 0001-01-01),
// and wraps BOOLEAN-declared / IsAccessBool columns in an expression so mattn/go-sqlite3 never evaluates
// sqlite3_column_decltype == "BOOLEAN" via `val == 1` (which turns Access -1 true and text 'true' into bool(false)).
func sqliteSelectColumnsCSV(cols []ColumnSpec) string {
	parts := make([]string, len(cols))
	for i, c := range cols {
		q := quotePGIdent(c.Name)
		if c.PGType == "TEXT" || c.IsAccessBool || strings.EqualFold(c.SQLiteType, "BOOLEAN") {
			parts[i] = fmt.Sprintf("CASE WHEN typeof(%s) = 'text' THEN CAST(%s AS BLOB) ELSE %s END", q, q, q)
		} else {
			parts[i] = q
		}
	}
	return strings.Join(parts, ", ")
}

// NarrowSingleCover narrows float64 to IEEE-754 float32 BEFORE evaluating < 100.
func NarrowSingleCover(value float64) (float32, bool) {
	if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 || math.Abs(value) > math.MaxFloat32 {
		return 0, false
	}
	narrowed := float32(value)
	if narrowed < 0 || narrowed >= 100 {
		return narrowed, false
	}
	return narrowed, true
}

func utf16CodeUnits(s string) int {
	return len(utf16.Encode([]rune(s)))
}

func ValidateUTF16Bound(label, s string, maxUnits int) error {
	if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
		return fmt.Errorf("%s contains malformed UTF-8 or NUL byte", label)
	}
	if maxUnits > 0 && utf16CodeUnits(s) > maxUnits {
		return fmt.Errorf("%s exceeds %d UTF-16 code units", label, maxUnits)
	}
	return nil
}

// ValidateLMH25HorizonDepth enforces LMH25 directional soil horizon depth rules
// via canonical vprocore.ValidateSoilHorizonDepthSign (stripping 0-9/I/V/X
// discontinuity prefixes case-insensitively; upland L/F/H require
// UpperDepth > LowerDepth >= 0, while wetland O*/Hydric/Limno/Cumulo and all
// Mineral horizons require 0 <= UpperDepth < LowerDepth).
func ValidateLMH25HorizonDepth(tableSuffix, horizon string, upper, lower *float64) error {
	return vprocore.ValidateSoilHorizonDepthSign(tableSuffix, &horizon, upper, lower) // single LMH25 rule (ENG-GO-005 / ENG-R-006)
}

// CanonicalizeSQLiteToPG converts a dynamic SQLite value into a typed PostgreSQL parameter
// preserving byte-exact text, IEEE-754 float64 bit identity, 64-bit integers, and Access -1/0 booleans.
func CanonicalizeSQLiteToPG(col ColumnSpec, raw any) (any, error) {
	if raw == nil {
		return nil, nil
	}
	if col.IsAccessBool {
		switch v := raw.(type) {
		case int64:
			if v != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case int32:
			if v != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case int16:
			if v != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case int:
			if v != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case float64:
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return nil, fmt.Errorf("non-finite boolean float %v for %s", v, col.Name)
			}
			if v != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case float32:
			f := float64(v)
			if math.IsNaN(f) || math.IsInf(f, 0) {
				return nil, fmt.Errorf("non-finite boolean float %v for %s", v, col.Name)
			}
			if f != 0 {
				return int16(-1), nil
			}
			return int16(0), nil
		case bool:
			if v {
				return int16(-1), nil
			}
			return int16(0), nil
		case []byte:
			return parseBoolBytes(string(v))
		case string:
			return parseBoolBytes(v)
		default:
			return nil, fmt.Errorf("unsupported boolean value %T for %s", raw, col.Name)
		}
	}

	switch col.PGType {
	case "TEXT":
		switch v := raw.(type) {
		case string:
			if !utf8.ValidString(v) || strings.ContainsRune(v, 0) {
				return nil, fmt.Errorf("column %s contains invalid UTF-8", col.Name)
			}
			return v, nil
		case []byte:
			s := string(v)
			if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
				return nil, fmt.Errorf("column %s contains invalid UTF-8 bytes", col.Name)
			}
			return s, nil
		case time.Time:
			if v.IsZero() {
				return nil, nil
			}
			if v.Hour() == 0 && v.Minute() == 0 && v.Second() == 0 && v.Nanosecond() == 0 {
				return v.Format("2006-01-02"), nil
			}
			return v.Format("2006-01-02 15:04:05"), nil
		case int64:
			return strconv.FormatInt(v, 10), nil
		case float64:
			return strconv.FormatFloat(v, 'g', -1, 64), nil
		case bool:
			if v {
				return "-1", nil
			}
			return "0", nil
		default:
			return fmt.Sprint(v), nil
		}

	case "BIGINT", "SMALLINT":
		var iv int64
		switch v := raw.(type) {
		case int64:
			iv = v
		case int:
			iv = int64(v)
		case int16:
			iv = int64(v)
		case int32:
			iv = int64(v)
		case float64:
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return nil, nil
			}
			iv = int64(math.Round(v))
		case bool:
			if v {
				iv = -1
			}
		case []byte:
			s := strings.TrimSpace(string(v))
			if s == "" {
				return nil, nil
			}
			parsed, err := strconv.ParseInt(s, 10, 64)
			if err != nil {
				f, ferr := strconv.ParseFloat(s, 64)
				if ferr != nil {
					return nil, nil
				}
				iv = int64(math.Round(f))
			} else {
				iv = parsed
			}
		case string:
			s := strings.TrimSpace(v)
			if s == "" {
				return nil, nil
			}
			parsed, err := strconv.ParseInt(s, 10, 64)
			if err != nil {
				f, ferr := strconv.ParseFloat(s, 64)
				if ferr != nil {
					return nil, nil
				}
				iv = int64(math.Round(f))
			} else {
				iv = parsed
			}
		default:
			return nil, fmt.Errorf("unsupported integer value %T for %s", raw, col.Name)
		}
		if col.PGType == "SMALLINT" {
			if iv < math.MinInt16 || iv > math.MaxInt16 {
				return nil, fmt.Errorf("column %s value %d overflows SMALLINT", col.Name, iv)
			}
			return int16(iv), nil
		}
		return iv, nil

	case "DOUBLE PRECISION":
		switch v := raw.(type) {
		case float64:
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return nil, nil
			}
			return v, nil
		case float32:
			f := float64(v)
			if math.IsNaN(f) || math.IsInf(f, 0) {
				return nil, nil
			}
			return f, nil
		case int64:
			return float64(v), nil
		case int:
			return float64(v), nil
		case []byte:
			s := strings.TrimSpace(string(v))
			if s == "" {
				return nil, nil
			}
			f, err := strconv.ParseFloat(s, 64)
			if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
				return nil, nil
			}
			return f, nil
		case string:
			s := strings.TrimSpace(v)
			if s == "" {
				return nil, nil
			}
			f, err := strconv.ParseFloat(s, 64)
			if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
				return nil, nil
			}
			return f, nil
		default:
			return nil, fmt.Errorf("unsupported float value %T for %s", raw, col.Name)
		}
	}
	return raw, nil
}

func parseBoolBytes(raw string) (any, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return nil, nil
	}
	if strings.EqualFold(s, "true") || s == "-1" || s == "1" {
		return int16(-1), nil
	}
	if strings.EqualFold(s, "false") || s == "0" {
		return int16(0), nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid boolean literal %q", raw)
	}
	if n != 0 {
		return int16(-1), nil
	}
	return int16(0), nil
}

// CanonicalizePGToSQLite normalizes a value scanned from PostgreSQL for insertion into SQLite VP08.
func CanonicalizePGToSQLite(col ColumnSpec, raw any) any {
	if raw == nil {
		return nil
	}
	if col.IsAccessBool {
		switch v := raw.(type) {
		case int16:
			if v != 0 {
				return int64(-1)
			}
			return int64(0)
		case int32:
			if v != 0 {
				return int64(-1)
			}
			return int64(0)
		case int64:
			if v != 0 {
				return int64(-1)
			}
			return int64(0)
		case int:
			if v != 0 {
				return int64(-1)
			}
			return int64(0)
		case bool:
			if v {
				return int64(-1)
			}
			return int64(0)
		case string:
			if parsed, err := parseBoolBytes(v); err == nil {
				if parsed == nil {
					return nil
				}
				return int64(parsed.(int16))
			}
		case []byte:
			if parsed, err := parseBoolBytes(string(v)); err == nil {
				if parsed == nil {
					return nil
				}
				return int64(parsed.(int16))
			}
		}
	}
	switch v := raw.(type) {
	case int16:
		return int64(v)
	case int32:
		return int64(v)
	case float32:
		return float64(v)
	default:
		return raw
	}
}

const GenesisAuditHash = "0000000000000000000000000000000000000000000000000000000000000000"

// ComputeAuditRowHash computes a deterministic tamper-evident SHA-256 chain link over a VP08 Audit record.
func ComputeAuditRowHash(prevHash, mergeTxID string, values []any) string {
	h := sha256.New()
	writePart := func(s string) {
		_, _ = h.Write([]byte(strconv.Itoa(len(s))))
		_, _ = h.Write([]byte(":"))
		_, _ = h.Write([]byte(s))
		_, _ = h.Write([]byte("|"))
	}
	writePart(prevHash)
	writePart(mergeTxID)
	for _, val := range values {
		if val == nil {
			writePart("<NULL>")
			continue
		}
		switch v := val.(type) {
		case string:
			writePart("S:" + v)
		case int16:
			writePart("I:" + strconv.FormatInt(int64(v), 10))
		case int32:
			writePart("I:" + strconv.FormatInt(int64(v), 10))
		case int64:
			writePart("I:" + strconv.FormatInt(v, 10))
		case int:
			writePart("I:" + strconv.Itoa(v))
		default:
			writePart("V:" + fmt.Sprint(v))
		}
	}
	return hex.EncodeToString(h.Sum(nil))
}

func tCol(name, sqliteType string, maxUTF16 int) ColumnSpec {
	return ColumnSpec{Name: name, PGType: "TEXT", SQLiteType: sqliteType, UTF16MaxLength: maxUTF16}
}

func iCol(name, sqliteType string) ColumnSpec {
	return ColumnSpec{Name: name, PGType: "BIGINT", SQLiteType: sqliteType}
}

func fCol(name, sqliteType string, isCover bool) ColumnSpec {
	return ColumnSpec{Name: name, PGType: "DOUBLE PRECISION", SQLiteType: sqliteType, IsSingleCover: isCover}
}

func bCol(name string) ColumnSpec {
	return ColumnSpec{Name: name, PGType: "SMALLINT", SQLiteType: "BOOLEAN", IsAccessBool: true}
}
