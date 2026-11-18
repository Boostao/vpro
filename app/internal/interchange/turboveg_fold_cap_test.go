package interchange

import "testing"

// ENG-GO-002 / AGENTS.md §3.3: summed (lumped) imported covers cap at 99%.
func TestAccumulateImportedSingleCoverCapsSumAt99(t *testing.T) {
	for _, tc := range []struct{ a, b, want float64 }{
		{50, 49.5, 99}, {50, 50, 99}, {60, 39.9, 99}, {40, 39, 79},
	} {
		covers := map[string]float64{}
		if err := accumulateImportedSingleCover(covers, "Cover1", tc.a, "P1", "SP"); err != nil {
			t.Fatal(err)
		}
		if err := accumulateImportedSingleCover(covers, "Cover1", tc.b, "P1", "SP"); err != nil {
			t.Fatal(err)
		}
		if got := covers["Cover1"]; got != float64(float32(tc.want)) {
			t.Errorf("%v + %v folded to %v, want %v", tc.a, tc.b, got, tc.want)
		}
	}
	if err := accumulateImportedSingleCover(map[string]float64{}, "Cover1", 99.999999, "P1", "SP"); err == nil {
		t.Error("99.999999 narrows to 100 and must be rejected")
	}
}
