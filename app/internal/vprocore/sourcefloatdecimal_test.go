package vprocore

import (
	"math"
	"testing"
)

func TestRoundCalibratedDecimalParity(t *testing.T) {
	cases := []struct {
		value    float64
		decimals int
		wantFmt  string
		wantNum  float64
	}{
		{1.005, 2, "1.01", 1.01},
		{-1.005, 2, "-1.01", -1.01},
		{35.855, 2, "35.86", 35.86},
		{2.675, 2, "2.68", 2.68},
		{0.285, 2, "0.29", 0.29},
		{1.4999999999995, 0, "1", 1},
		{-1.4999999999995, 0, "-1", -1},
		{99.995, 2, "100.00", 100},
		{1e15 + 0.5, 0, "1000000000000000", 1e15},
		{1e15 + 0.5, 2, "1000000000000000.00", 1e15},
		{100000000000.005, 6, "100000000000.005000", 100000000000.005},
		{-0.001, 2, "0.00", 0},
		{-0.005, 2, "-0.01", -0.01},
	}

	for _, tc := range cases {
		gotFmt := FormatCalibratedDecimal(tc.value, tc.decimals)
		if gotFmt != tc.wantFmt {
			t.Fatalf("FormatCalibratedDecimal(%v, %d) = %q, want %q", tc.value, tc.decimals, gotFmt, tc.wantFmt)
		}
		gotNum := RoundCalibratedDecimal(tc.value, tc.decimals)
		if gotNum != tc.wantNum {
			t.Fatalf("RoundCalibratedDecimal(%v, %d) = %.17g, want %.17g", tc.value, tc.decimals, gotNum, tc.wantNum)
		}
		if gotNum == 0 && math.Signbit(gotNum) {
			t.Fatalf("RoundCalibratedDecimal(%v, %d) returned negative zero (-0.0)", tc.value, tc.decimals)
		}
	}

	if got := RoundCalibratedDecimal(1e307, 2); got != 1e307 {
		t.Fatalf("RoundCalibratedDecimal(1e307, 2) = %.17g, want 1e307", got)
	}
	if got := RoundCalibratedDecimal(math.MaxFloat64, 2); got != math.MaxFloat64 {
		t.Fatalf("RoundCalibratedDecimal(MaxFloat64, 2) = %.17g, want MaxFloat64", got)
	}
	if got := RoundCalibratedDecimal(-math.MaxFloat64, 2); got != -math.MaxFloat64 {
		t.Fatalf("RoundCalibratedDecimal(-MaxFloat64, 2) = %.17g, want -MaxFloat64", got)
	}
	if got := RoundCalibratedDecimal(math.SmallestNonzeroFloat64, 323); got != 0 || math.Signbit(got) {
		t.Fatalf("RoundCalibratedDecimal(SmallestNonzeroFloat64, 323) = %.17g, want +0", got)
	}
	if got := RoundCalibratedDecimal(2*math.SmallestNonzeroFloat64, 323); got != 2*math.SmallestNonzeroFloat64 {
		t.Fatalf("RoundCalibratedDecimal(2*SmallestNonzeroFloat64, 323) = %.17g, want %.17g", got, 2*math.SmallestNonzeroFloat64)
	}
	if got := RoundCalibratedDecimal(1.005, 500); got != 1.005 {
		t.Fatalf("RoundCalibratedDecimal(1.005, 500) = %.17g, want 1.005", got)
	}
	if negZero := math.Copysign(0, -1); math.Signbit(RoundCalibratedDecimal(negZero, 2)) {
		t.Fatal("RoundCalibratedDecimal(-0.0, 2) should clear signbit to +0.0")
	}
	if !math.IsNaN(RoundCalibratedDecimal(math.NaN(), 2)) {
		t.Fatal("RoundCalibratedDecimal(NaN, 2) should preserve NaN")
	}
	if !math.IsInf(RoundCalibratedDecimal(math.Inf(1), 2), 1) {
		t.Fatal("RoundCalibratedDecimal(+Inf, 2) should preserve +Inf")
	}
}
