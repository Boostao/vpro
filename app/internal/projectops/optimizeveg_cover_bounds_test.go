package projectops

import (
	"context"
	"database/sql"
	"encoding/json"
	"math"
	"slices"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func optimizeVegCoverGroupWithIDs(ids []int64, col string, cells ...rawSQLiteCell) []vegRowWithRowID {
	members := make([]vegRowWithRowID, len(cells))
	for i, c := range cells {
		rowCells := map[string]rawSQLiteCell{
			"ID":         {storage: "integer", intVal: ids[i]},
			"PlotNumber": {storage: "text", bytes: []byte("P1")},
			"Species":    {storage: "text", bytes: []byte("SP")},
			col:          c,
		}
		members[i] = vegRowWithRowID{rowID: int64(i + 1), cells: rowCells}
	}
	return members
}

func optimizeVegCoverGroup(covers ...float64) []vegRowWithRowID {
	ids := make([]int64, len(covers))
	cells := make([]rawSQLiteCell, len(covers))
	for i, c := range covers {
		ids[i] = int64(i + 1)
		cells[i] = rawSQLiteCell{storage: "real", realVal: c}
	}
	return optimizeVegCoverGroupWithIDs(ids, "Cover1", cells...)
}

func resolveSingleColGroup(col string, members []vegRowWithRowID) (plannedVegConsolidation, *OptimizeVegPreview) {
	gk := vegGroupKey{plot: "P1", species: "SP"}
	cols := []string{"ID", "PlotNumber", "Species", col}
	preview := &OptimizeVegPreview{OldToSurvivorIDMap: map[int64]int64{}}
	covered := map[string]bool{"PlotNumber": true, "Species": true, "ID": true, col: true}
	plan := resolveOptimizeVegGroup(gk, members, cols, covered, map[string]bool{}, nil, false, preview)
	return plan, preview
}

// ENG-GO-002: OptimizeVeg validates EVERY source row's cover/height cell BEFORE maxVal
// aggregation, blocking negative, >=100 SINGLE-narrowed, non-numeric, and non-finite cells
// while attributing exact offending row IDs in SourceIDs and conflict reasons.
func TestOptimizeVegCoverBoundsAndSingleNarrowing(t *testing.T) {
	t.Run("SingletonNegativeAndSingleNonNullNegativeInDisjointGroup", func(t *testing.T) {
		// 1-row unit group with negative cover
		singleNeg, prev := resolveSingleColGroup("Cover1", optimizeVegCoverGroupWithIDs(
			[]int64{101}, "Cover1",
			rawSQLiteCell{storage: "real", realVal: -5},
		))
		if !singleNeg.group.Blocked || !prev.HasBlockingConflicts {
			t.Fatalf("singleton negative cover must block: group=%+v preview=%+v", singleNeg.group, prev)
		}
		if len(singleNeg.group.Conflicts) != 1 {
			t.Fatalf("expected 1 conflict, got %+v", singleNeg.group.Conflicts)
		}
		c := singleNeg.group.Conflicts[0]
		if !slices.Equal(c.SourceIDs, []int64{101}) || !strings.Contains(c.Reason, "negative Cover1") || !strings.Contains(c.Reason, "ID 101") {
			t.Fatalf("unexpected conflict attribution: %+v", c)
		}
		if _, exists := singleNeg.group.MergedCovers["Cover1"]; exists {
			t.Fatalf("blocked Cover1 must not appear in MergedCovers: %+v", singleNeg.group.MergedCovers)
		}

		// 2-row disjoint-layer group where Cover1 has only one non-null cell (-5 on non-survivor ID=25)
		gk := vegGroupKey{plot: "P1", species: "SP"}
		cols := []string{"ID", "PlotNumber", "Species", "Cover1", "Cover2"}
		covered := map[string]bool{"ID": true, "PlotNumber": true, "Species": true, "Cover1": true, "Cover2": true}
		preview := &OptimizeVegPreview{OldToSurvivorIDMap: map[int64]int64{}}
		disjointMembers := []vegRowWithRowID{
			{rowID: 1, cells: map[string]rawSQLiteCell{
				"ID": {storage: "integer", intVal: 10}, "PlotNumber": {storage: "text", bytes: []byte("P1")},
				"Species": {storage: "text", bytes: []byte("SP")},
				"Cover1":  {storage: "null"}, "Cover2": {storage: "real", realVal: 25},
			}},
			{rowID: 2, cells: map[string]rawSQLiteCell{
				"ID": {storage: "integer", intVal: 25}, "PlotNumber": {storage: "text", bytes: []byte("P1")},
				"Species": {storage: "text", bytes: []byte("SP")},
				"Cover1":  {storage: "real", realVal: -5}, "Cover2": {storage: "null"},
			}},
		}
		disjointPlan := resolveOptimizeVegGroup(gk, disjointMembers, cols, covered, map[string]bool{}, nil, false, preview)
		if !disjointPlan.group.Blocked || len(disjointPlan.group.Conflicts) != 1 {
			t.Fatalf("expected disjoint singleton negative Cover1 to block, got %+v", disjointPlan.group)
		}
		dc := disjointPlan.group.Conflicts[0]
		if dc.Field != "Cover1" || !slices.Equal(dc.SourceIDs, []int64{25}) || !strings.Contains(dc.Reason, "ID 25") {
			t.Fatalf("expected exact non-survivor SourceIDs=[25], got %+v", dc)
		}
		if disjointPlan.group.MergedCovers["Cover2"] != 25 {
			t.Fatalf("expected valid Cover2=25 preserved alongside Cover1 conflict, got %+v", disjointPlan.group.MergedCovers)
		}
	})

	t.Run("AllNegativeAndMixedNegativeGroupsNeverMaskBehindMaxVal", func(t *testing.T) {
		cases := []struct {
			name    string
			ids     []int64
			covers  []float64
			wantIDs []int64
			wantVal []string
		}{
			{
				name:    "all_negative_pair",
				ids:     []int64{11, 22},
				covers:  []float64{-0.5, -2},
				wantIDs: []int64{11, 22},
				wantVal: []string{"-0.5", "-2"},
			},
			{
				name:    "mixed_minus5_and_10_survivor_negative",
				ids:     []int64{10, 25},
				covers:  []float64{-5, 10},
				wantIDs: []int64{10},
				wantVal: []string{"-5"},
			},
			{
				name:    "mixed_10_and_minus5_duplicate_negative",
				ids:     []int64{10, 25},
				covers:  []float64{10, -5},
				wantIDs: []int64{25},
				wantVal: []string{"-5"},
			},
			{
				name:    "mixed_minus001_and_0_negative_signed_id",
				ids:     []int64{-42000, 15},
				covers:  []float64{-0.01, 0},
				wantIDs: []int64{-42000},
				wantVal: []string{"-0.01"},
			},
			{
				name:    "mixed_0_and_minus001_zero_survivor_id",
				ids:     []int64{0, 15},
				covers:  []float64{0, -0.01},
				wantIDs: []int64{15},
				wantVal: []string{"-0.01"},
			},
			{
				name:    "mixed_minus001_on_id_zero",
				ids:     []int64{0, 15},
				covers:  []float64{-0.01, 0},
				wantIDs: []int64{0},
				wantVal: []string{"-0.01"},
			},
		}

		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				cells := make([]rawSQLiteCell, len(tc.covers))
				for i, v := range tc.covers {
					cells[i] = rawSQLiteCell{storage: "real", realVal: v}
				}
				plan, prev := resolveSingleColGroup("Cover1", optimizeVegCoverGroupWithIDs(tc.ids, "Cover1", cells...))
				if !plan.group.Blocked || !prev.HasBlockingConflicts {
					t.Fatalf("%s: expected Blocked=true, got group=%+v", tc.name, plan.group)
				}
				if _, ok := plan.group.MergedCovers["Cover1"]; ok {
					t.Fatalf("%s: expected Cover1 omitted from MergedCovers, got %+v", tc.name, plan.group.MergedCovers)
				}
				if len(plan.group.Conflicts) != 1 {
					t.Fatalf("%s: expected 1 conflict, got %+v", tc.name, plan.group.Conflicts)
				}
				got := plan.group.Conflicts[0]
				if got.Field != "Cover1" || !slices.Equal(got.SourceIDs, tc.wantIDs) || !slices.Equal(got.Values, tc.wantVal) {
					t.Fatalf("%s: got SourceIDs=%v Values=%v, want SourceIDs=%v Values=%v (conflict=%+v)",
						tc.name, got.SourceIDs, got.Values, tc.wantIDs, tc.wantVal, got)
				}
				if !strings.Contains(got.Reason, "negative Cover1") {
					t.Fatalf("%s: expected reason to mention 'negative Cover1', got %q", tc.name, got.Reason)
				}
			})
		}
	})

	t.Run("Float32UpperBoundary99999996ValidVs99999999Blocked", func(t *testing.T) {
		// 99.999996 narrows to float32 99.99999237060547 (< 100) -> valid!
		okPlan, okPrev := resolveSingleColGroup("Cover1", optimizeVegCoverGroup(10, 99.999996))
		if okPlan.group.Blocked || okPrev.HasBlockingConflicts || len(okPlan.group.Conflicts) != 0 {
			t.Fatalf("99.999996 is a valid SINGLE cover, got blocked=%v reasons=%v", okPlan.group.Blocked, okPlan.group.BlockedReasons)
		}
		wantNarrowed := float64(float32(99.999996))
		if got := okPlan.group.MergedCovers["Cover1"]; got != wantNarrowed {
			t.Fatalf("merged cover = %.10f, want SINGLE-narrowed %.10f", got, wantNarrowed)
		}
		if len(okPlan.group.CappedCoverColumns) != 0 {
			t.Fatalf("valid cover 99.999996 must not report CappedCoverColumns: %v", okPlan.group.CappedCoverColumns)
		}

		// -0.0 and 0 are valid zero covers and normalize to +0.0.
		zeroPlan, _ := resolveSingleColGroup("Cover1", optimizeVegCoverGroup(math.Copysign(0, -1), 0))
		if zeroPlan.group.Blocked || math.Signbit(zeroPlan.group.MergedCovers["Cover1"]) {
			t.Fatalf("expected clean +0.0 merged cover, got blocked=%v cover=%v", zeroPlan.group.Blocked, zeroPlan.group.MergedCovers["Cover1"])
		}

		// 99.999999 narrows to float32 100.0 (>= 100) -> MUST block (never cap to 99 or mask behind sibling)!
		badUpperCases := []struct {
			name    string
			ids     []int64
			cells   []rawSQLiteCell
			wantIDs []int64
		}{
			{
				name: "99.999999_on_retired_row",
				ids:  []int64{10, 20},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 10},
					{storage: "real", realVal: 99.999999},
				},
				wantIDs: []int64{20},
			},
			{
				name: "99.999999_on_survivor_row_with_larger_double",
				ids:  []int64{10, 20},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 99.999999},
					{storage: "real", realVal: 25},
				},
				wantIDs: []int64{10},
			},
			{
				name: "nextafter_100_below_100",
				ids:  []int64{5, 9},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 99.999996},
					{storage: "real", realVal: math.Nextafter(100, 0)},
				},
				wantIDs: []int64{9},
			},
			{
				name: "integer_100_cover",
				ids:  []int64{3, 7},
				cells: []rawSQLiteCell{
					{storage: "integer", intVal: 50},
					{storage: "integer", intVal: 100},
				},
				wantIDs: []int64{7},
			},
			{
				name: "overflow_above_max_float32",
				ids:  []int64{4, 8},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 25},
					{storage: "real", realVal: 1e40},
				},
				wantIDs: []int64{8},
			},
			{
				name: "multiple_offenders_skipping_valid_middle_row",
				ids:  []int64{10, 20, 30},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: -5},
					{storage: "real", realVal: 15},
					{storage: "real", realVal: 99.999999},
				},
				wantIDs: []int64{10, 30},
			},
		}

		for _, tc := range badUpperCases {
			t.Run(tc.name, func(t *testing.T) {
				plan, prev := resolveSingleColGroup("Cover1", optimizeVegCoverGroupWithIDs(tc.ids, "Cover1", tc.cells...))
				if !plan.group.Blocked || !prev.HasBlockingConflicts {
					t.Fatalf("%s: expected Blocked=true, got group=%+v", tc.name, plan.group)
				}
				if len(plan.group.CappedCoverColumns) != 0 {
					t.Fatalf("%s: invalid >=100 SINGLE cover must block rather than cap at 99: %v", tc.name, plan.group.CappedCoverColumns)
				}
				if _, exists := plan.group.MergedCovers["Cover1"]; exists {
					t.Fatalf("%s: blocked Cover1 must not appear in MergedCovers: %+v", tc.name, plan.group.MergedCovers)
				}
				if len(plan.group.Conflicts) != 1 || !slices.Equal(plan.group.Conflicts[0].SourceIDs, tc.wantIDs) {
					t.Fatalf("%s: got conflicts=%+v, want SourceIDs=%v", tc.name, plan.group.Conflicts, tc.wantIDs)
				}
			})
		}
	})

	t.Run("NonNumericAndNonFiniteCoverCellsBlockAndSerializeCleanly", func(t *testing.T) {
		corruptCases := []struct {
			name       string
			ids        []int64
			cells      []rawSQLiteCell
			wantIDs    []int64
			wantSubstr string
		}{
			{
				name: "text_alpha_on_survivor",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "text", bytes: []byte("abc")},
					{storage: "real", realVal: 10},
				},
				wantIDs:    []int64{100},
				wantSubstr: "non-numeric",
			},
			{
				name: "text_empty_on_duplicate",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 10},
					{storage: "text", bytes: []byte("")},
				},
				wantIDs:    []int64{200},
				wantSubstr: "non-numeric",
			},
			{
				name: "text_nan_on_duplicate",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 10},
					{storage: "text", bytes: []byte("NaN")},
				},
				wantIDs:    []int64{200},
				wantSubstr: "non-numeric/non-finite",
			},
			{
				name: "text_inf_on_survivor",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "text", bytes: []byte("-Inf")},
					{storage: "real", realVal: 10},
				},
				wantIDs:    []int64{100},
				wantSubstr: "non-numeric/non-finite",
			},
			{
				name: "blob_cover_cell",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 10},
					{storage: "blob", bytes: []byte{0xca, 0xfe}},
				},
				wantIDs:    []int64{200},
				wantSubstr: "non-numeric",
			},
			{
				name: "real_nan_cell",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 10},
					{storage: "real", realVal: math.NaN()},
				},
				wantIDs:    []int64{200},
				wantSubstr: "non-finite",
			},
			{
				name: "real_pos_inf_cell",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: math.Inf(1)},
					{storage: "real", realVal: 10},
				},
				wantIDs:    []int64{100},
				wantSubstr: "non-finite",
			},
			{
				name: "real_neg_inf_cell",
				ids:  []int64{100, 200},
				cells: []rawSQLiteCell{
					{storage: "real", realVal: 0},
					{storage: "real", realVal: math.Inf(-1)},
				},
				wantIDs:    []int64{200},
				wantSubstr: "non-finite",
			},
		}

		for _, tc := range corruptCases {
			t.Run(tc.name, func(t *testing.T) {
				plan, prev := resolveSingleColGroup("Cover1", optimizeVegCoverGroupWithIDs(tc.ids, "Cover1", tc.cells...))
				if !plan.group.Blocked || !prev.HasBlockingConflicts {
					t.Fatalf("%s: expected Blocked=true, got %+v", tc.name, plan.group)
				}
				if len(plan.group.Conflicts) != 1 {
					t.Fatalf("%s: expected 1 conflict, got %+v", tc.name, plan.group.Conflicts)
				}
				c := plan.group.Conflicts[0]
				if !slices.Equal(c.SourceIDs, tc.wantIDs) || !strings.Contains(c.Reason, tc.wantSubstr) {
					t.Fatalf("%s: got conflict=%+v, want SourceIDs=%v substr=%q", tc.name, c, tc.wantIDs, tc.wantSubstr)
				}
				if _, err := json.Marshal(prev); err != nil {
					t.Fatalf("%s: preview JSON marshal failed (NaN/Inf leaked into float map?): %v", tc.name, err)
				}
			})
		}
	})

	t.Run("NumericHeightBoundsValidateEverySourceRowBeforeMax", func(t *testing.T) {
		// Tall valid tree height (>= 100 m) is allowed on Height1 (unlike Cover1 < 100%).
		tallPlan, _ := resolveSingleColGroup("Height1", optimizeVegCoverGroupWithIDs(
			[]int64{1, 2}, "Height1",
			rawSQLiteCell{storage: "real", realVal: 35.0},
			rawSQLiteCell{storage: "real", realVal: 115.75},
		))
		if tallPlan.group.Blocked || tallPlan.group.MergedHeights["Height1"] != 115.75 {
			t.Fatalf("expected valid tall Height1=115.75, got %+v", tallPlan.group)
		}

		// Mixed negative height (10.0, -2.5) must block and attribute ID=44.
		negHeightPlan, _ := resolveSingleColGroup("Height1", optimizeVegCoverGroupWithIDs(
			[]int64{31, 44}, "Height1",
			rawSQLiteCell{storage: "real", realVal: 10.0},
			rawSQLiteCell{storage: "real", realVal: -2.5},
		))
		if !negHeightPlan.group.Blocked || len(negHeightPlan.group.Conflicts) != 1 ||
			!slices.Equal(negHeightPlan.group.Conflicts[0].SourceIDs, []int64{44}) {
			t.Fatalf("expected negative Height1 on ID=44 to block, got %+v", negHeightPlan.group)
		}

		// Non-numeric text and NaN/Inf height cells must block rather than being skipped.
		for _, badCell := range []rawSQLiteCell{
			{storage: "text", bytes: []byte("tall")},
			{storage: "text", bytes: []byte("NaN")},
			{storage: "real", realVal: math.NaN()},
			{storage: "real", realVal: math.Inf(1)},
			{storage: "real", realVal: 1e40},
		} {
			p, prev := resolveSingleColGroup("Height6", optimizeVegCoverGroupWithIDs(
				[]int64{50, 60}, "Height6",
				rawSQLiteCell{storage: "real", realVal: 1.5},
				badCell,
			))
			if !p.group.Blocked || !prev.HasBlockingConflicts || !slices.Equal(p.group.Conflicts[0].SourceIDs, []int64{60}) {
				t.Fatalf("expected corrupt Height6 (%+v) to block with SourceIDs=[60], got %+v", badCell, p.group)
			}
		}
	})
}

func TestOptimizeVegSQLiteEndToEndBlocksInvalidCoversAndPreservesRows(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	proj, err := CreateNewProject(svc, ctx, state.ContextID, NewProjectRequest{
		ProjectName:       "OptBoundsProj",
		ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	cid := proj.State.ContextID

	vprotest.MutateContextFixture(t, proj.DestinationPath, `
		INSERT INTO OptBoundsProj_Env (PlotNumber, ProjectID, Zone) VALUES ('P01', 'OB1', 'CWH'), ('P02', 'OB1', 'CWH');
		-- P01 mixed negative (10, -5)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_MIXN', 10, 10, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_MIXN', 25, -5, 0);
		-- P01 mixed (-0.01, 0)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_NEGZ', 30, -0.01, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_NEGZ', 35, 0, 0);
		-- P01 float32 >= 100 narrowing (10, 99.999999)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_F100', 40, 10, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_F100', 45, 99.999999, 0);
		-- P01 non-numeric text ('abc', 12)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_TEXT', 50, 'abc', 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_TEXT', 55, 12, 0);
		-- P01 'NaN' text (8, 'NaN')
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_NANT', 60, 8, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_NANT', 65, 'NaN', 0);
		-- P01 IEEE-754 +Inf real in SQLite (8, 9e999)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_INFR', 70, 8, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'SP_INFR', 75, 9e999, 0);
		-- P01 negative Height1 (12, -1.5)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Height1, Flag) VALUES ('P01', 'SP_NEGH', 80, 5, 12.0, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Height1, Flag) VALUES ('P01', 'SP_NEGH', 85, 10, -1.5, 0);
		-- P02 valid SINGLE boundary (10, 99.999996)
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P02', 'SP_OK32', 90, 10, 0);
		INSERT INTO OptBoundsProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P02', 'SP_OK32', 95, 99.999996, 0);
	`)

	prev, err := PreviewOptimizeVeg(svc, ctx, cid, OptimizeVegOptions{})
	if err != nil {
		t.Fatalf("PreviewOptimizeVeg failed: %v", err)
	}
	if !prev.HasBlockingConflicts || prev.BlockedGroupCount != 7 || len(prev.Groups) != 8 {
		t.Fatalf("expected 7 blocked groups and 1 valid group, got blocked=%d groups=%d conflicts=%+v",
			prev.BlockedGroupCount, len(prev.Groups), prev.Conflicts)
	}

	wantOffenderBySpecies := map[string][]int64{
		"SP_MIXN": {25},
		"SP_NEGZ": {30},
		"SP_F100": {45},
		"SP_TEXT": {50},
		"SP_NANT": {65},
		"SP_INFR": {75},
		"SP_NEGH": {85},
	}
	for _, g := range prev.Groups {
		if g.Species == "SP_OK32" {
			if g.Blocked || g.MergedCovers["Cover1"] != float64(float32(99.999996)) {
				t.Fatalf("expected SP_OK32 unblocked with SINGLE-narrowed 99.999996, got %+v", g)
			}
			continue
		}
		wantIDs, ok := wantOffenderBySpecies[g.Species]
		if !ok {
			t.Fatalf("unexpected group %+v", g)
		}
		if !g.Blocked || len(g.Conflicts) != 1 || !slices.Equal(g.Conflicts[0].SourceIDs, wantIDs) {
			t.Fatalf("species %s: expected Blocked=true with SourceIDs=%v, got %+v", g.Species, wantIDs, g)
		}
	}

	// ApplyOptimizeVeg across all plots MUST refuse and leave all 16 _Veg rows untouched.
	if _, err := ApplyOptimizeVeg(svc, ctx, cid, ApplyOptimizeVegRequest{
		ExpectedDigest: prev.PreviewDigest,
	}); err == nil || !strings.Contains(err.Error(), "blocking conflict") {
		t.Fatalf("expected ApplyOptimizeVeg to refuse blocked preview, got %v", err)
	}

	db, err := sqlutil.OpenReadOnly(proj.DestinationPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	var rowCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM OptBoundsProj_Veg`).Scan(&rowCount); err != nil {
		t.Fatal(err)
	}
	if rowCount != 16 {
		t.Fatalf("expected all 16 _Veg rows untouched after refused ApplyOptimizeVeg, got %d", rowCount)
	}

	// Applying ONLY clean plot P02 succeeds and persists SINGLE-narrowed 99.999996.
	prevP02, err := PreviewOptimizeVeg(svc, ctx, cid, OptimizeVegOptions{PlotNumbers: []string{"P02"}})
	if err != nil {
		t.Fatalf("PreviewOptimizeVeg(P02) failed: %v", err)
	}
	if prevP02.HasBlockingConflicts {
		t.Fatalf("expected P02 unblocked, got %+v", prevP02)
	}
	appliedP02, err := ApplyOptimizeVeg(svc, ctx, cid, ApplyOptimizeVegRequest{
		PlotNumbers:    []string{"P02"},
		ExpectedDigest: prevP02.PreviewDigest,
	})
	if err != nil {
		t.Fatalf("ApplyOptimizeVeg(P02) failed: %v", err)
	}
	if appliedP02.ConsolidatedGroups != 1 || appliedP02.DeletedRows != 1 || appliedP02.AfterRowCount != 15 {
		t.Fatalf("unexpected P02 apply result: %+v", appliedP02)
	}

	var stored sql.NullFloat64
	if err := db.QueryRow(`SELECT Cover1 FROM OptBoundsProj_Veg WHERE PlotNumber='P02' AND Species='SP_OK32' AND ID=90`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if !stored.Valid || stored.Float64 != float64(float32(99.999996)) {
		t.Fatalf("stored Cover1 = %#v, want %v", stored, float64(float32(99.999996)))
	}
}
