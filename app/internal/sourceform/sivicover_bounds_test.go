package sourceform

import (
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// ENG-GO-002: SIVI cover writes narrow to IEEE-754 SINGLE before the [0, 100) check.
func TestValidateSIVICoverCellNarrowsToSingleBeforeBounds(t *testing.T) {
	real := func(v float64) vprocore.ProjectMetadataCell {
		return vprocore.ProjectMetadataCell{Storage: "real", Real: &v}
	}
	integer := func(s string) vprocore.ProjectMetadataCell {
		return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &s}
	}
	for _, tc := range []struct {
		name string
		cell vprocore.ProjectMetadataCell
		ok   bool
	}{
		{"null", vprocore.ProjectMetadataCell{Storage: "null"}, true},
		{"zero", real(0), true},
		{"99.999996 narrows below 100", real(99.999996), true},
		{"99.999999 narrows to 100", real(99.999999), false},
		{"100", real(100), false},
		{"-0.01", real(-0.01), false},
		{"integer storage rejected", integer("99"), false},
		{"integer 100", integer("100"), false},
		{"integer -1", integer("-1"), false},
	} {
		for _, column := range []string{"Cover1", "Cover6", "TotalA"} {
			err := validateSIVICoverCell(column, tc.cell)
			if (err == nil) != tc.ok {
				t.Errorf("%s %s: err=%v, want ok=%v", column, tc.name, err, tc.ok)
			}
		}
	}
}
