package validation_test

import (
	"context"
	"testing"

	"github.com/boostao/vpro/app/internal/validation"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

// ENG-GO-005 / UX-SOIL-002 / UX-SOIL-003 / UX-SOIL-004:
// Ensures RunComplianceValidation delegates both Humus and Mineral horizon depth checks
// to vprocore.ValidateSoilHorizonDepthSign, catching single-sided negative depths,
// NULL-horizon Mineral inversions, numbered/Roman discontinuity prefixes, and wetland
// Hydric/Limno/Cumulo horizons.
func TestComplianceLMH25SingleSidedNegativeNullHorizonAndWetlandRules(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		PRAGMA foreign_keys = OFF;
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_Humus;
		DELETE FROM Sample_Mineral;
		DELETE FROM Sample_Other;
		DELETE FROM Sample_Env;
		DELETE FROM Sample_Admin;

		INSERT INTO Sample_Env (PlotNumber, Zone) VALUES ('OK01', 'CWH'), ('BAD01', 'CWH');
		INSERT INTO Sample_Admin (Plot, PlotType) VALUES ('OK01', 'FS882'), ('BAD01', 'FS882');

		-- Valid horizons on OK01 (including Hydric/Limno/Cumulo, 2Of1, 2L, IXAh, XAh, NULL-depth rows, and single-sided >= 0)
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(1, 'OK01', '2L', 10.0, 4.0, 0),
			(2, 'OK01', 'Fm', 4.0, 0.0, 0),
			(3, 'OK01', '2Of1', 0.0, 10.0, 0),
			(4, 'OK01', 'Hydric', 10.0, 20.0, 0),
			(5, 'OK01', 'Limno', 20.0, 30.0, 0),
			(6, 'OK01', 'Cumulo', 30.0, 45.0, 0),
			(7, 'OK01', 'L', 5.0, NULL, 0),
			(8, 'OK01', NULL, NULL, NULL, 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(11, 'OK01', 'IXAh', 0.0, 12.0, 0),
			(12, 'OK01', 'XAh', 12.0, 25.0, 0),
			(13, 'OK01', NULL, 25.0, 40.0, 0),
			(14, 'OK01', 'R', 40.0, NULL, 0);

		-- Invalid horizons on BAD01 (each must produce exactly 1 BoundsFinding)
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(101, 'BAD01', 'L', -5.0, NULL, 0),
			(102, 'BAD01', 'L', NULL, -2.0, 0),
			(103, 'BAD01', NULL, -2.0, -5.0, 0),
			(104, 'BAD01', '2Of1', 10.0, 0.0, 0),
			(105, 'BAD01', '2L', 0.0, 10.0, 0),
			(106, 'BAD01', 'Hydric', 10.0, 0.0, 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(201, 'BAD01', NULL, 30.0, 10.0, 0),
			(202, 'BAD01', 'Ah', -5.0, NULL, 0),
			(203, 'BAD01', NULL, NULL, -1.0, 0),
			(204, 'BAD01', 'IXAh', 10.0, 0.0, 0),
			(205, 'BAD01', 'XAh', 10.0, 0.0, 0);
	`)

	var err error
	state, err = svc.SwitchContext(state.ContextID, vprotest.ContextSelection(state))
	if err != nil {
		t.Fatalf("SwitchContext: %v", err)
	}

	rep, err := validation.RunComplianceValidation(svc, ctx, state.ContextID, validation.ComplianceOptions{UseActiveSU: false})
	if err != nil {
		t.Fatalf("RunComplianceValidation: %v", err)
	}
	if rep.Passed {
		t.Fatal("expected Passed=false for BAD01 LMH25 violations")
	}

	var okFindings, badHumus, badMineral int
	for _, f := range rep.BoundsFindings {
		if f.PlotNumber == "OK01" {
			okFindings++
		}
		if f.PlotNumber == "BAD01" && f.Table == "Humus" {
			badHumus++
		}
		if f.PlotNumber == "BAD01" && f.Table == "Mineral" {
			badMineral++
		}
	}
	if okFindings != 0 {
		t.Fatalf("expected 0 findings on OK01, got %d: %+v", okFindings, rep.BoundsFindings)
	}
	if badHumus != 6 {
		t.Fatalf("expected 6 Humus findings on BAD01, got %d: %+v", badHumus, rep.BoundsFindings)
	}
	if badMineral != 5 {
		t.Fatalf("expected 5 Mineral findings on BAD01, got %d: %+v", badMineral, rep.BoundsFindings)
	}
}
