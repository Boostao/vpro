package sqlutil

import (
	"fmt"
	"math"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

// NarrowSingleCover narrows a float64 cover input to IEEE-754 float32 BEFORE
// evaluating < 100 (e.g., 99.999996 narrows to 99.99999 and passes; 99.999999
// narrows to 100 and fails).
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

// UTF16Len returns the exact number of UTF-16 code units needed to encode s
// without allocating a rune or uint16 slice.
func UTF16Len(s string) int {
	n := 0
	for _, r := range s {
		if r > 0xFFFF {
			n += 2
		} else {
			n++
		}
	}
	return n
}

// UTF16Within reports whether s requires at most maxUnits UTF-16 code units.
func UTF16Within(s string, maxUnits int) bool {
	if maxUnits < 0 {
		return false
	}
	if len(s) <= maxUnits {
		return true
	}
	return UTF16Len(s) <= maxUnits
}

// TruncateUTF16 truncates s on a rune boundary so that UTF16Len(result) <= maxUnits,
// never splitting surrogate pairs.
func TruncateUTF16(s string, maxUnits int) string {
	if maxUnits <= 0 || s == "" {
		if maxUnits <= 0 {
			return ""
		}
		return s
	}
	if len(s) <= maxUnits {
		return s
	}
	units := 0
	for idx, r := range s {
		cost := 1
		if r > 0xFFFF {
			cost = 2
		}
		if units+cost > maxUnits {
			return s[:idx]
		}
		units += cost
	}
	return s
}

// TruncateUTF16Ptr truncates a nullable string pointer to at most maxUnits UTF-16 code units.
func TruncateUTF16Ptr(p *string, maxUnits int) *string {
	if p == nil {
		return nil
	}
	t := TruncateUTF16(*p, maxUnits)
	if t == *p {
		return p
	}
	return &t
}

// FormatMaxLengthError builds a plain-language length error distinguishing visible
// character count from astral symbol width when surrogate pairs are present.
func FormatMaxLengthError(label, s string, maxUnits int) error {
	runeCount := utf8.RuneCountInString(s)
	if runeCount > maxUnits {
		return fmt.Errorf("%s cannot exceed %d characters", label, maxUnits)
	}
	return fmt.Errorf("%s exceeds the %d-character limit (symbols count as 2 characters)", label, maxUnits)
}

// ValidateUTF16Bound verifies that s is valid UTF-8 without NUL bytes and fits
// within maxUnits UTF-16 code units (when maxUnits > 0).
func ValidateUTF16Bound(label, s string, maxUnits int) error {
	if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
		return fmt.Errorf("%s contains invalid text characters", label)
	}
	if maxUnits > 0 && UTF16Len(s) > maxUnits {
		return FormatMaxLengthError(label, s, maxUnits)
	}
	return nil
}

// DecodeStrictUTF16Slice decodes a non-NUL-containing UTF-16 code-unit slice,
// rejecting unpaired surrogates and embedded NUL units.
func DecodeStrictUTF16Slice(units []uint16, label string) (string, error) {
	for index := 0; index < len(units); index++ {
		value := units[index]
		if value >= 0xd800 && value <= 0xdbff {
			if index+1 >= len(units) || units[index+1] < 0xdc00 || units[index+1] > 0xdfff {
				return "", fmt.Errorf("%s contains invalid text encoding", label)
			}
			index++
		} else if value >= 0xdc00 && value <= 0xdfff || value == 0 {
			return "", fmt.Errorf("%s contains invalid text encoding", label)
		}
	}
	return string(utf16.Decode(units)), nil
}
