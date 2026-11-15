package validation_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/boostao/vpro/app/internal/validation"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestWave2SpeciesCodeCheckExcludesSynonymOnlyMasterAndResolvesOldCode(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	// Confirm ARTHDIF is S-only and THUIABI is an OldCode -> ABIEABI in embedded VLists.db
	var sCount, oldCount int
	if err := svc.Projects.Sqlite.Conn.QueryRowContext(ctx, `
		SELECT
			(SELECT COUNT(*) FROM USysAllSpecs WHERE Code COLLATE BINARY='ARTHDIF' AND LOWER(COALESCE(CAST(Codetype AS TEXT),''))='s'),
			(SELECT COUNT(*) FROM USysAllSpecs WHERE OldCode COLLATE BINARY='THUIABI' AND Code COLLATE BINARY='ABIEABI')
	`).Scan(&sCount, &oldCount); err != nil {
		t.Fatal(err)
	}
	if sCount == 0 || oldCount == 0 {
		t.Fatalf("expected VLists fixture to contain ARTHDIF (Codetype='S') and THUIABI -> ABIEABI, got sCount=%d oldCount=%d", sCount, oldCount)
	}

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		PRAGMA foreign_keys = OFF;
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_Env;
		DELETE FROM Sample_Admin;
		INSERT INTO Sample_Env (PlotNumber, Zone) VALUES ('00001', 'CWH');
		INSERT INTO Sample_Admin (Plot, PlotType) VALUES ('00001', 'FS882');
		INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1, Flag) VALUES
			(-201, '00001', 'ABIEABI', 10.0, 0),
			(-202, '00001', 'ARTHDIF', 5.0, 0),
			(-203, '00001', 'THUIABI', 2.0, 0),
			(-204, '00001', 'ZZNOPE9', 1.0, 0);
	`)
	var err error
	state, err = svc.SwitchContext(state.ContextID, vprotest.ContextSelection(state))
	if err != nil {
		t.Fatal(err)
	}

	review, err := validation.ReviewSpeciesCodes(svc, ctx, state.ContextID)
	if err != nil {
		t.Fatalf("ReviewSpeciesCodes: %v", err)
	}
	byID := map[int]validation.SpeciesCodeCheckRow{}
	for _, r := range review.Rows {
		byID[r.ID] = r
	}
	if byID[-201].Status != "master" {
		t.Fatalf("expected ABIEABI status 'master', got %+v", byID[-201])
	}
	if byID[-202].Status != "unlisted" {
		t.Fatalf("expected S-only ARTHDIF status 'unlisted' (not 'master'), got %+v", byID[-202])
	}
	if byID[-203].Status != "synonym" || byID[-203].SuggestedCode == nil || *byID[-203].SuggestedCode != "ABIEABI" {
		t.Fatalf("expected THUIABI status 'synonym' with suggestedCode='ABIEABI', got %+v", byID[-203])
	}
	if byID[-204].Status != "unlisted" {
		t.Fatalf("expected ZZNOPE9 status 'unlisted', got %+v", byID[-204])
	}

	// LookupSpeciesCodeCheckTarget must exclude Codetype='S' master codes
	sOpts, err := validation.LookupSpeciesCodeCheckTarget(svc, ctx, state.ContextID, vprocore.VegetationSpeciesLookup{Code: "ARTHDIF"})
	if err != nil {
		t.Fatalf("LookupSpeciesCodeCheckTarget(ARTHDIF): %v", err)
	}
	if len(sOpts) != 0 {
		t.Fatalf("expected zero master target options for S-only ARTHDIF, got %+v", sOpts)
	}

	// SaveSpeciesCodeCheck must reject S-only replacement and accept canonical ABIEABI replacement
	synCode := "THUIABI"
	if err := validation.SaveSpeciesCodeCheck(svc, state.ContextID, []validation.SpeciesCodeCheckUpdate{
		{ID: -203, PlotNumber: "00001", Expected: &synCode, Value: "ARTHDIF"},
	}); err == nil {
		t.Fatal("expected SaveSpeciesCodeCheck to reject S-only ARTHDIF target")
	}
	if err := validation.SaveSpeciesCodeCheck(svc, state.ContextID, []validation.SpeciesCodeCheckUpdate{
		{ID: -203, PlotNumber: "00001", Expected: &synCode, Value: "ABIEABI"},
	}); err != nil {
		t.Fatalf("SaveSpeciesCodeCheck to ABIEABI failed: %v", err)
	}
}

func TestWave2ComplianceUseActiveSUOrphansAndLMH25NegativeAndPrefixedHorizons(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		PRAGMA foreign_keys = OFF;
		DELETE FROM Sample_SU;
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_Humus;
		DELETE FROM Sample_Mineral;
		DELETE FROM Sample_Other;
		DELETE FROM Sample_Audit;
		DELETE FROM Sample_Env;
		DELETE FROM Sample_Admin;

		-- Plot SU01 is in active SU and completely clean (even with numeric-prefixed valid LMH25 horizons!)
		INSERT INTO Sample_Env (PlotNumber, Zone) VALUES
			('SU01', 'CWH'),
			('OUT1', 'CWH');
		-- OUT1 intentionally lacks Sample_Admin (out-of-SU env/admin mismatch) + has an out-of-SU duplicate veg row
		INSERT INTO Sample_Admin (Plot, PlotType) VALUES
			('SU01', 'FS882'),
			('ADM_OUT', 'FS882');

		INSERT INTO Sample_SU (PlotNumber, SiteUnit) VALUES ('SU01', 'CWHvm1/01');

		INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1, Flag) VALUES
			(1, 'SU01', 'ABIEAMA', 15.0, 0),
			(2, 'OUT1', 'ABIEAMA', 10.0, 0),
			(3, 'OUT1', 'ABIEAMA', 20.0, 0);

		-- Valid numeric-prefixed wetland 2Of (0..5) and upland 1F (5..0), plus clean Mineral (0..10)
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(1, 'SU01', '2Of', 0.0, 5.0, 0),
			(2, 'SU01', '1F', 5.0, 0.0, 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(1, 'SU01', 'Bm', 0.0, 10.0, 0);
	`)
	sel := vprotest.ContextSelection(state)
	sel.SU = "Sample"
	sel.SUPath = state.ProjectPath
	var err error
	state, err = svc.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatal(err)
	}

	// Scoped to active SU: SU01 is clean even though OUT1/ADM_OUT have issues
	scopedRep, err := validation.RunComplianceValidation(svc, ctx, state.ContextID, validation.ComplianceOptions{UseActiveSU: true})
	if err != nil {
		t.Fatalf("RunComplianceValidation(UseActiveSU=true): %v", err)
	}
	if !scopedRep.Passed || scopedRep.Summary.EnvAdminMismatches != 0 || scopedRep.Summary.DuplicateSpeciesSplits != 0 || scopedRep.Summary.BoundsErrors != 0 {
		t.Fatalf("expected UseActiveSU=true to pass cleanly on SU01, got passed=%v summary=%+v bounds=%+v", scopedRep.Passed, scopedRep.Summary, scopedRep.BoundsFindings)
	}

	// Unscoped: OUT1 missing_admin, ADM_OUT orphan_admin, and OUT1 duplicate veg must appear
	fullRep, err := validation.RunComplianceValidation(svc, ctx, state.ContextID, validation.ComplianceOptions{UseActiveSU: false})
	if err != nil {
		t.Fatalf("RunComplianceValidation(UseActiveSU=false): %v", err)
	}
	if fullRep.Passed || fullRep.Summary.EnvAdminMismatches != 2 || fullRep.Summary.DuplicateSpeciesSplits != 1 {
		t.Fatalf("expected UseActiveSU=false to detect OUT1 env/admin & dup veg, got passed=%v summary=%+v", fullRep.Passed, fullRep.Summary)
	}

	// Add SU orphan + invalid negative/inverted numeric-prefixed LMH25 depths inside SU01
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		PRAGMA foreign_keys = OFF;
		INSERT INTO Sample_SU (PlotNumber, SiteUnit) VALUES ('ORPH_SU', 'CWHvm1/01');
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(3, 'SU01', '2Of', -1.0, 4.0, 0),
			(4, 'SU01', '2Of', 5.0, 1.0, 0),
			(5, 'SU01', '1F', 1.0, 5.0, 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(2, 'SU01', 'Ah', -2.0, 5.0, 0);
	`)
	state, err = svc.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatal(err)
	}
	badRep, err := validation.RunComplianceValidation(svc, ctx, state.ContextID, validation.ComplianceOptions{UseActiveSU: true})
	if err != nil {
		t.Fatalf("RunComplianceValidation(SU orphan + bad LMH25): %v", err)
	}
	if badRep.Passed {
		t.Fatalf("expected compliance failure with SU orphan and bad LMH25 depths, got Passed=true")
	}
	if badRep.Summary.OrphanChildRows != 1 {
		t.Fatalf("expected Summary.OrphanChildRows=1 for SU orphan, got %d (findings=%+v)", badRep.Summary.OrphanChildRows, badRep.OrphanFindings)
	}
	if badRep.Summary.BoundsErrors != 4 {
		t.Fatalf("expected 4 LMH25 BoundsFindings (-1 2Of, inverted 2Of, inverted 1F, -2 Mineral), got %d: %+v", badRep.Summary.BoundsErrors, badRep.BoundsFindings)
	}

	_ = sql.ErrNoRows
}
