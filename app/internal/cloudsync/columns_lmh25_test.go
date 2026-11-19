package cloudsync

import "testing"

func TestValidateLMH25HorizonDepthCanonicalParity(t *testing.T) {
	f := func(v float64) *float64 { return &v }

	cases := []struct {
		suffix  string
		horizon string
		upper   *float64
		lower   *float64
		wantErr bool
	}{
		// Upland L/F/H (including numeric/Roman discontinuities and case-insensitivity)
		{"Humus", "L", f(5), f(0), false},
		{"Humus", "2H", f(10), f(2), false},
		{"Humus", "2h", f(2), f(10), true},
		{"Humus", "Lv", f(3), f(3), true},

		// Wetland O / Oe / Op / Of / Om / Oh / Hydric / Limno / Cumulo + discontinuities
		{"Humus", "Of", f(0), f(15), false},
		{"Humus", "of", f(0), f(15), false},
		{"Humus", "2Of", f(0), f(15), false},
		{"Humus", "2of", f(0), f(15), false},
		{"Humus", "2Of", f(15), f(0), true},
		{"Humus", "2of", f(15), f(0), true},
		{"Humus", "IIOf", f(0), f(12), false},
		{"Humus", "iiof", f(12), f(0), true},
		{"Humus", "O", f(0), f(10), false},
		{"Humus", "O", f(10), f(0), true},
		{"Humus", "Oe", f(0), f(10), false},
		{"Humus", "Oe", f(10), f(0), true},
		{"Humus", "Op", f(0), f(10), false},
		{"Humus", "Op", f(10), f(0), true},
		{"Humus", "Hydric", f(0), f(20), false},
		{"Humus", "Hydric", f(20), f(0), true},
		{"Humus", "Limno", f(0), f(20), false},
		{"Humus", "Cumulo", f(20), f(0), true},

		// Mineral horizons (including Roman discontinuity IXAh and blank horizon)
		{"Mineral", "Ah", f(0), f(12), false},
		{"Mineral", "IXAh", f(0), f(12), false},
		{"Mineral", "IXAh", f(12), f(0), true},
		{"Mineral", "", f(0), f(10), false},
		{"Mineral", "", f(10), f(0), true},

		// Single-sided negative depths
		{"Humus", "L", f(-1), nil, true},
		{"Humus", "Of", nil, f(-1), true},
		{"Mineral", "Bm", f(-1), f(10), true},
	}

	for _, tc := range cases {
		err := ValidateLMH25HorizonDepth(tc.suffix, tc.horizon, tc.upper, tc.lower)
		if (err != nil) != tc.wantErr {
			t.Errorf("ValidateLMH25HorizonDepth(%q, %q, %v, %v) err=%v, wantErr=%v",
				tc.suffix, tc.horizon, tc.upper, tc.lower, err, tc.wantErr)
		}
	}
}
