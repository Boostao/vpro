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
	if subSnap.LumpCappedCells != 1 {
		t.Fatalf("Sample_Lump sublayer_sum LumpCappedCells = %d, want 1", subSnap.LumpCappedCells)
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

func TestSynthesisFoldedAndSingletonLumpCap99Parity(t *testing.T) {
	ctx := context.Background()
	contexts, initState := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, initState.ProjectPath, `
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_SU;
		INSERT INTO Sample_SU (PlotNumber, SiteUnit) VALUES ('108050', 'TEST_U1');
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover1) VALUES
			-- Singleton mapped species POA PRA2 -> POASPP at 99.5 -> capped at 99.0 (ENG-R-007)
			('108050', 9301, 'POA PRA2', 99.5),
			-- Unmapped singleton TSUGHET at 99.5 -> preserved at 99.5
			('108050', 9302, 'TSUGHET', 99.5),
			-- Duplicate observations of same species in Layer 1 (60 + 55 = 115) -> capped at 99.0 even without lump table
			('108050', 9303, 'PSEUMEN', 60.0),
			('108050', 9304, 'PSEUMEN', 55.0);
	`)

	state, err := contexts.SwitchContext(initState.ContextID, vprocore.ContextSelection{
		Project:       initState.ActiveProject,
		ProjectPath:   initState.ProjectPath,
		SU:            "Sample",
		SUPath:        initState.ProjectPath,
		Hierarchy:     initState.ActiveHierarchy,
		HierarchyPath: initState.HierarchyPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext failed: %v", err)
	}

	meanFor := func(snap *SynthesisSnapshot, spp string) float64 {
		for _, row := range snap.Species {
			if row.Species == spp && len(row.Cells) > 0 {
				return row.Cells[0].MeanCoverPresent
			}
		}
		t.Fatalf("species %s not found in snapshot", spp)
		return 0
	}

	lumpSnap, err := ComputeSynthesisSnapshot(ctx, contexts, state.ContextID, SynthesisOptions{
		UnitSource:      "su",
		LumpTable:       "Sample",
		CoverPrecedence: "sublayer_sum",
		Pairwise:        PairwiseParams{MinPlots: 1},
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot(Sample_Lump) failed: %v", err)
	}
	if got := meanFor(lumpSnap, "POASPP"); got != 99.0 {
		t.Fatalf("POASPP singleton lumped MeanCoverPresent = %v, want 99.0", got)
	}
	if got := meanFor(lumpSnap, "TSUGHET"); got != 99.5 {
		t.Fatalf("TSUGHET unlumped singleton MeanCoverPresent = %v, want 99.5", got)
	}
	if got := meanFor(lumpSnap, "PSEUMEN"); got != 99.0 {
		t.Fatalf("PSEUMEN folded MeanCoverPresent = %v, want 99.0", got)
	}

	noLumpSnap, err := ComputeSynthesisSnapshot(ctx, contexts, state.ContextID, SynthesisOptions{
		UnitSource:      "su",
		CoverPrecedence: "sublayer_sum",
		Pairwise:        PairwiseParams{MinPlots: 1},
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot(no lump) failed: %v", err)
	}
	if got := meanFor(noLumpSnap, "PSEUMEN"); got != 99.0 {
		t.Fatalf("PSEUMEN duplicate-row fold without lump table MeanCoverPresent = %v, want 99.0", got)
	}
	if got := meanFor(noLumpSnap, "POA PRA2"); got != 99.5 {
		t.Fatalf("POA PRA2 without lump table MeanCoverPresent = %v, want 99.5", got)
	}
}
