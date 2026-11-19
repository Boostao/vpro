package sqlutil

import (
	"strings"
	"testing"
)

func TestNarrowSingleCoverAndUTF16Bounds(t *testing.T) {
	if got, ok := NarrowSingleCover(99.999996); !ok || got >= 100 {
		t.Fatalf("expected 99.999996 to narrow below 100, got (%v, %v)", got, ok)
	}
	if got, ok := NarrowSingleCover(99.999999); ok || got != 100 {
		t.Fatalf("expected 99.999999 to narrow to 100 and fail, got (%v, %v)", got, ok)
	}
	if _, ok := NarrowSingleCover(-0.01); ok {
		t.Fatal("expected negative cover to fail")
	}

	if n := UTF16Len("Si😀L"); n != 5 {
		t.Fatalf("expected UTF16Len(Si😀L)=5, got %d", n)
	}
	if !UTF16Within("12345🌲", 7) || UTF16Within("123456🌲", 7) {
		t.Fatal("unexpected UTF16Within boundary result")
	}
	if got := TruncateUTF16("AB🌲CD", 3); got != "AB" {
		t.Fatalf("expected surrogate-safe truncation to AB, got %q", got)
	}
	if got := TruncateUTF16("AB🌲CD", 4); got != "AB🌲" {
		t.Fatalf("expected surrogate-safe truncation to AB🌲, got %q", got)
	}

	errASCII := ValidateUTF16Bound("PlotNumber", "12345678", 7)
	if errASCII == nil || !strings.Contains(errASCII.Error(), "cannot exceed 7 characters") {
		t.Fatalf("unexpected ASCII bound error: %v", errASCII)
	}
	errSymbol := ValidateUTF16Bound("Texture", "Si😀L", 4)
	if errSymbol == nil || !strings.Contains(errSymbol.Error(), "symbols count as 2 characters") {
		t.Fatalf("unexpected symbol bound error: %v", errSymbol)
	}
	s := "A"
	if got := TruncateUTF16Ptr(&s, 4); got == nil || *got != "A" {
		t.Fatalf("unexpected TruncateUTF16Ptr: %v", got)
	}
	if decoded, err := DecodeStrictUTF16Slice([]uint16{'O', 'K'}, "test"); err != nil || decoded != "OK" {
		t.Fatalf("unexpected DecodeStrictUTF16Slice valid: %q %v", decoded, err)
	}
	if _, err := DecodeStrictUTF16Slice([]uint16{0xD800}, "test"); err == nil {
		t.Fatal("expected lone high surrogate to be rejected by DecodeStrictUTF16Slice")
	}
}
