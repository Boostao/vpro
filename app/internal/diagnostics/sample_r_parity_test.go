package diagnostics

import (
	"context"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSampleDBParityWithVProR(t *testing.T) {
	ctx := context.Background()
	contexts, initState := vprotest.ContextServiceFixture(t)
	state, err := contexts.SwitchContext(initState.ContextID, vprocore.ContextSelection{
		Project:       initState.ActiveProject,
		ProjectPath:   initState.ProjectPath,
		SU:            "Sample",
		SUPath:        initState.ProjectPath,
		Hierarchy:     initState.ActiveHierarchy,
		HierarchyPath: initState.HierarchyPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext(Sample_SU) failed: %v", err)
	}

	findCell := func(snap *SynthesisSnapshot, species, unit string) (SynthesisUnitSpeciesCell, bool) {
		for _, row := range snap.Species {
			if row.Species == species {
				for _, cell := range row.Cells {
					if cell.SiteUnit == unit {
						return cell, true
					}
				}
			}
		}
		return SynthesisUnitSpeciesCell{}, false
	}

	subSnap, err := ComputeSynthesisSnapshot(ctx, contexts, state.ContextID, SynthesisOptions{
		UnitSource:               "su",
		LumpTable:                "Sample",
		ExcludeStandardModifiers: true,
		CoverPrecedence:          "sublayer_sum",
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot(sublayer_sum) failed: %v", err)
	}
	if len(subSnap.PairwiseComparisons) != 36 {
		t.Fatalf("default MinPlots=2 PairwiseComparisons = %d, want 36", len(subSnap.PairwiseComparisons))
	}
	subCell, ok := findCell(subSnap, "ABIE_RK", "MH  whp  /01")
	if !ok || subCell.PresentPlots != 1 || subCell.MeanCoverPresent != 20.0 {
		t.Fatalf("sublayer_sum ABIE_RK in MH  whp  /01 = (%+v, ok=%v), want PresentPlots=1 MeanCoverPresent=20.0", subCell, ok)
	}

	strataSnap, err := ComputeSynthesisSnapshot(ctx, contexts, state.ContextID, SynthesisOptions{
		UnitSource:               "su",
		LumpTable:                "Sample",
		ExcludeStandardModifiers: true,
		CoverPrecedence:          "strata_totals",
		Pairwise:                 PairwiseParams{MinPlots: 1},
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot(strata_totals, MinPlots=1) failed: %v", err)
	}
	if len(strataSnap.PairwiseComparisons) != 55 {
		t.Fatalf("MinPlots=1 PairwiseComparisons = %d, want 55", len(strataSnap.PairwiseComparisons))
	}
	strataCell, ok := findCell(strataSnap, "ABIE_RK", "MH  whp  /01")
	if !ok || strataCell.PresentPlots != 1 || strataCell.MeanCoverPresent != 15.0 {
		t.Fatalf("strata_totals ABIE_RK in MH  whp  /01 = (%+v, ok=%v), want PresentPlots=1 MeanCoverPresent=15.0", strataCell, ok)
	}
}
