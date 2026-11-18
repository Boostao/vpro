package projectops

import (
	"strings"
	"testing"
)

func optimizeVegCoverGroup(covers ...float64) []vegRowWithRowID {
	var members []vegRowWithRowID
	for i, c := range covers {
		members = append(members, vegRowWithRowID{rowID: int64(i + 1), cells: map[string]rawSQLiteCell{
			"ID": {storage: "integer", intVal: int64(i + 1)}, "PlotNumber": {storage: "text", bytes: []byte("P1")},
			"Species": {storage: "text", bytes: []byte("SP")}, "Cover1": {storage: "real", realVal: c},
		}})
	}
	return members
}

// ENG-GO-002: OptimizeVeg blocks negative covers and stores the SINGLE-narrowed merged cover.
func TestOptimizeVegCoverBoundsAndSingleNarrowing(t *testing.T) {
	gk := vegGroupKey{plot: "P1", species: "SP"}
	cols := []string{"ID", "PlotNumber", "Species", "Cover1"}
	resolve := func(covers ...float64) plannedVegConsolidation {
		preview := &OptimizeVegPreview{OldToSurvivorIDMap: map[int64]int64{}}
		covered := map[string]bool{"PlotNumber": true, "Species": true, "ID": true, "Cover1": true}
		return resolveOptimizeVegGroup(gk, optimizeVegCoverGroup(covers...), cols, covered, map[string]bool{}, nil, false, preview)
	}

	neg := resolve(-0.5, -2)
	if !neg.group.Blocked || !strings.Contains(strings.Join(neg.group.BlockedReasons, ";"), "negative Cover1") {
		t.Fatalf("negative covers must block the group, got blocked=%v reasons=%v", neg.group.Blocked, neg.group.BlockedReasons)
	}

	ok := resolve(10, 99.999996)
	if ok.group.Blocked {
		t.Fatalf("99.999996 is a valid SINGLE cover, group blocked: %v", ok.group.BlockedReasons)
	}
	if got, want := ok.group.MergedCovers["Cover1"], float64(float32(99.999996)); got != want {
		t.Fatalf("merged cover = %v, want SINGLE-narrowed %v", got, want)
	}

	capped := resolve(10, 99.999999)
	if got := capped.group.MergedCovers["Cover1"]; got != 99 || len(capped.group.CappedCoverColumns) != 1 {
		t.Fatalf("99.999999 narrows to 100 and must cap at 99, got %v capped=%v", got, capped.group.CappedCoverColumns)
	}
}
