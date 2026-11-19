package vprocore_test

import (
	"math"
	"strconv"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func TestW3UXSpatial003_NegateLocationLongitudeAlignsWithWesternBCMagnitudeBounds(t *testing.T) {
	realCell := func(v float64) vprocore.ProjectMetadataCell {
		return vprocore.ProjectMetadataCell{Storage: "real", Real: &v}
	}
	intCell := func(s string) vprocore.ProjectMetadataCell {
		return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &s}
	}

	realCases := []struct {
		name string
		in   float64
		want float64
	}{
		{"Western BC unsigned 123.62903", 123.62903, -123.62903},
		{"Western BC already-signed -123.62903", -123.62903, -123.62903},
		{"Lower BC/Prairie bound 100.0", 100.0, -100.0},
		{"Upper Alaska bound 170.0", 170.0, -170.0},
		{"Eastern Hemisphere antimeridian +179.9 preserved", 179.9, 179.9},
		{"Western Hemisphere antimeridian -179.9 preserved", -179.9, -179.9},
		{"Eastern Hemisphere +99.999 preserved", 99.999, 99.999},
		{"Eastern Hemisphere +170.001 preserved", 170.001, 170.001},
		{"Zero preserved", 0.0, 0.0},
		{"Out-of-range +200.0 preserved without clamping", 200.0, 200.0},
	}

	for _, tc := range realCases {
		got, err := vprocore.NegateLocationLongitude(realCell(tc.in))
		if err != nil || got.Storage != "real" || got.Real == nil || *got.Real != tc.want {
			t.Fatalf("%s: got %+v (%v), want %v", tc.name, got, err, tc.want)
		}
	}

	negZero, err := vprocore.NegateLocationLongitude(realCell(math.Copysign(0, -1)))
	if err != nil || negZero.Real == nil || !math.Signbit(*negZero.Real) {
		t.Fatalf("expected -0 signbit preserved, got %+v (%v)", negZero, err)
	}

	intCases := []struct {
		in, want string
	}{
		{"100", "-100"},
		{"125", "-125"},
		{"170", "-170"},
		{"-125", "-125"},
		{"179", "179"},
		{"-179", "-179"},
		{"0", "0"},
		{strconv.FormatInt(math.MaxInt64, 10), strconv.FormatInt(math.MaxInt64, 10)},
	}
	for _, tc := range intCases {
		got, err := vprocore.NegateLocationLongitude(intCell(tc.in))
		if err != nil || got.Storage != "integer" || got.Integer == nil || *got.Integer != tc.want {
			t.Fatalf("integer %s: got %+v (%v), want %s", tc.in, got, err, tc.want)
		}
	}
}
