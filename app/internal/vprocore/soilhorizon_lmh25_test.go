package vprocore

import (
	"database/sql"
	"math"
	"reflect"
	"testing"
)

// ENG-GO-005 / UX-SOIL-002/003/004: the single LMH25 horizon depth rule.
func TestValidateSoilHorizonDepthSignLMH25(t *testing.T) {
	f := func(v float64) *float64 { return &v }
	s := func(v string) *string { return &v }
	cases := []struct {
		kind    string
		horizon *string
		up, lo  *float64
		ok      bool
	}{
		{"Humus", s("Lv"), f(6), f(2), true},
		{"Humus", s("Fm"), f(2), f(0), true},
		{"Humus", s("Lv"), f(2), f(6), false},
		{"Humus", s("Of"), f(0), f(15), true},
		{"Humus", s("Of"), f(15), f(5), false},
		{"Humus", s("Hydric"), f(0), f(10), true}, // UX-SOIL-002: wetland, not upland "H"
		{"Humus", s("Hydric"), f(10), f(0), false},
		{"Humus", s("Limno"), f(0), f(10), true},
		{"Humus", s("Cumulo"), f(10), f(0), false},
		{"Humus", s("2Of"), f(15), f(5), false},  // discontinuity prefix stripped
		{"Humus", s("2Of1"), f(10), f(0), false}, // UX-SOIL-003
		{"Humus", s("2L"), f(0), f(10), false},
		{"Humus", s("IIOf"), f(0), f(10), true},
		{"Humus", s("Lv"), f(-1), f(-5), false}, // UX-SOIL-004: negative depths
		{"Humus", s("L"), f(-2), nil, false},
		{"Humus", s("Of1"), f(-10), f(-5), false},
		{"Humus", s("Lv"), f(math.NaN()), f(1), false},
		{"Humus", s(""), f(3), f(9), true}, // blank humus horizon: only the sign rule applies
		{"Humus", nil, f(9), f(3), true},
		{"Mineral", s("Ah"), f(0), f(15), true},
		{"Mineral", s("Ah"), f(-5), f(15), false},
		{"Mineral", s("IXAh"), f(10), f(0), false},
		{"Mineral", s("XAh"), f(10), f(0), false},
		{"Mineral", s(""), f(30), f(10), false}, // every mineral row measures downward
		{"Mineral", nil, f(30), f(10), false},
		{"Mineral", s("Bm"), f(10), f(10), false},
		{"Mineral", s("Bm"), nil, nil, true},
	}
	for _, tc := range cases {
		err := ValidateSoilHorizonDepthSign(tc.kind, tc.horizon, tc.up, tc.lo)
		if (err == nil) != tc.ok {
			name := "<nil>"
			if tc.horizon != nil {
				name = *tc.horizon
			}
			t.Errorf("%s %q %v..%v: err=%v, want ok=%v", tc.kind, name, tc.up, tc.lo, err, tc.ok)
		}
	}
}

// UX-SOIL-001 / ENG-XCUT-005: upland L/F/H top-down (UpperDepth DESC), then wetland ASC.
func TestHumusOrderBySQLListsProfilesTopDown(t *testing.T) {
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TABLE h (Horizon TEXT, UpperDepth REAL);
		INSERT INTO h VALUES ('Oh',45),('Fm',2),('Of',0),('Lv',6),('Om',15),('2Of',80),('Hydric',90),(NULL,NULL)`); err != nil {
		t.Fatal(err)
	}
	rows, err := db.Query(`SELECT COALESCE(Horizon,'NULL') FROM h ORDER BY ` + HumusOrderBySQL(`Horizon`, `UpperDepth`))
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var got []string
	for rows.Next() {
		var hz string
		if err := rows.Scan(&hz); err != nil {
			t.Fatal(err)
		}
		got = append(got, hz)
	}
	want := []string{"Lv", "Fm", "NULL", "Of", "Om", "Oh", "2Of", "Hydric"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("humus order = %v, want %v", got, want)
	}
}
