package vprocore_test

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestUXSoil005SoilChildAndHeaderBoundsWithLegacyTolerance(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	// Seed legacy rows matching Sample.db:
	// - Plot LEG822: SeepageDepth = -60, RootingDepth = 30
	// - Plot LEG202: Mineral row with PercentCoarseFragsTotal = 100 (components NULL)
	// - Plot LEG999: Mineral row with historical ASP = 12, Gravel = 60, Cobbles = 60, Total = 150, MineralFormpH = 16
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SeepageDepth, RootingDepth, Flag) VALUES
			('UX005A', 'CWH', 40, 35, 0),
			('LEG822', 'ICH', -60, 30, 0),
			('LEG202', 'SBS', NULL, 25, 0),
			('LEG999', 'IDF', NULL, 20, 0);
		INSERT INTO Sample_Admin (Plot, HumusThickness) VALUES
			('UX005A', 5.0),
			('LEG822', 6.0),
			('LEG202', 4.0),
			('LEG999', 3.0);
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, vonPost, HumusFormpH, Flag) VALUES
			(501, 'UX005A', 'L', 5.0, 0.0, 2, 4.5, 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, ASP, Texture, PercentCoarseFragsGravel, PercentCoarseFragsCobbles, PercentCoarseFragsStones, PercentCoarseFragsTotal, MineralFormpH, Flag) VALUES
			(601, 'UX005A', 'Ah', 0.0, 15.0, 1, 'SL', 20, 10, 5, 40, 5.2, 0),
			(602, 'LEG202', 'Ah', 0.0, 15.0, 1, 'L', NULL, NULL, NULL, 100, 5.5, 0),
			(603, 'LEG999', 'Bm', 0.0, 20.0, 12, 'SL', 60, 60, NULL, 150, 16.0, 0);
	`)
	var err error
	state, err = service.SwitchContext(state.ContextID, vprotest.ContextSelection(state))
	if err != nil {
		t.Fatalf("SwitchContext: %v", err)
	}

	flt := func(v float64) *float64 { return &v }
	str := func(v string) *string { return &v }
	intP := func(v int) *int { return &v }

	// 1. Exact UX-SOIL-005 soil child repro edits must fail with zero DB writes.
	badSoilCases := []struct {
		name    string
		updates []vprocore.SoilRecordUpdate
		wantSub string
	}{
		{
			name: "humus_vonPost_15",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Humus", ID: 501,
				Numbers: map[string]vprocore.SoilNumberUpdate{"vonPost": {Expected: flt(2), Value: flt(15)}},
			}},
			wantSub: "1 to 10",
		},
		{
			name: "humus_pH_20",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Humus", ID: 501,
				Numbers: map[string]vprocore.SoilNumberUpdate{"ph": {Expected: flt(4.5), Value: flt(20)}},
			}},
			wantSub: "0 and 14",
		},
		{
			name: "mineral_ASP_99",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Mineral", ID: 601,
				Numbers: map[string]vprocore.SoilNumberUpdate{"asp": {Expected: flt(1), Value: flt(99)}},
			}},
			wantSub: "1 to 8",
		},
		{
			name: "mineral_total_150",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Mineral", ID: 601,
				Numbers: map[string]vprocore.SoilNumberUpdate{"percentCoarseFragsTotal": {Expected: flt(40), Value: flt(150)}},
			}},
			wantSub: "0% and 100%",
		},
		{
			name: "mineral_pH_20",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Mineral", ID: 601,
				Numbers: map[string]vprocore.SoilNumberUpdate{"mineralFormpH": {Expected: flt(5.2), Value: flt(20)}},
			}},
			wantSub: "0 and 14",
		},
		{
			name: "mineral_60_60_60_sum_overflow",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Mineral", ID: 601,
				Numbers: map[string]vprocore.SoilNumberUpdate{
					"percentCoarseFragsGravel":  {Expected: flt(20), Value: flt(60)},
					"percentCoarseFragsCobbles": {Expected: flt(10), Value: flt(60)},
					"percentCoarseFragsStones":  {Expected: flt(5), Value: flt(60)},
				},
			}},
			wantSub: "cannot exceed 100%",
		},
		{
			name: "mineral_partial_component_exceeds_stored_total",
			updates: []vprocore.SoilRecordUpdate{{
				Kind: "Mineral", ID: 601,
				Numbers: map[string]vprocore.SoilNumberUpdate{
					"percentCoarseFragsCobbles": {Expected: flt(10), Value: flt(25)}, // 20 + 25 + 5 = 50 > stored Total 40
				},
			}},
			wantSub: "PercentCoarseFragsTotal",
		},
	}
	for _, tc := range badSoilCases {
		err := service.UpdateSoilRecords(state.ContextID, "UX005A", tc.updates)
		if err == nil || !strings.Contains(err.Error(), tc.wantSub) {
			t.Fatalf("%s: expected error containing %q, got %v", tc.name, tc.wantSub, err)
		}
	}

	// 2. Exact UX-SOIL-005 pit-header negative depth edits on UX005A must fail with zero DB writes.
	header00337, err := service.GetPlot(ctx, state.ContextID, "UX005A")
	if err != nil {
		t.Fatalf("GetPlot(UX005A): %v", err)
	}
	for _, mutate := range []struct {
		name string
		fn   func(*vprocore.FS882Header)
	}{
		{"HumusThickness_-12", func(h *vprocore.FS882Header) { h.HumusThickness = flt(-12) }},
		{"RootingDepth_-5", func(h *vprocore.FS882Header) { h.RootingDepth = intP(-5) }},
		{"SeepageDepth_-3", func(h *vprocore.FS882Header) { h.SeepageDepth = intP(-3) }},
		{"RootRestrictingDepth_-2", func(h *vprocore.FS882Header) { h.RootRestrictingDepth = intP(-2) }},
	} {
		draft := *header00337
		mutate.fn(&draft)
		if err := service.UpdatePlot(state.ContextID, draft); err == nil || !strings.Contains(err.Error(), ">= 0 cm") {
			t.Fatalf("%s: expected >= 0 cm error, got %v", mutate.name, err)
		}
	}
	if err := service.CreatePlot(state.ContextID, vprocore.FS882Header{
		PlotNumber:   "NEWNEG",
		RootingDepth: intP(-5),
	}); err == nil || !strings.Contains(err.Error(), ">= 0 cm") {
		t.Fatalf("CreatePlot with negative RootingDepth should fail, got %v", err)
	}

	// Verify UX005A SQLite values remained completely unmutated.
	db, err := sql.Open("sqlite3", state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var vp, asp, tot, root, seep int
	var hph, mph, hthick float64
	if err := db.QueryRow(`SELECT vonPost, HumusFormpH FROM Sample_Humus WHERE ID = 501`).Scan(&vp, &hph); err != nil {
		t.Fatal(err)
	}
	if vp != 2 || hph != 4.5 {
		t.Fatalf("Humus 501 mutated: vonPost=%d pH=%v", vp, hph)
	}
	if err := db.QueryRow(`SELECT ASP, PercentCoarseFragsTotal, MineralFormpH FROM Sample_Mineral WHERE ID = 601`).Scan(&asp, &tot, &mph); err != nil {
		t.Fatal(err)
	}
	if asp != 1 || tot != 40 || mph != 5.2 {
		t.Fatalf("Mineral 601 mutated: ASP=%d Total=%d pH=%v", asp, tot, mph)
	}
	if err := db.QueryRow(`SELECT e.RootingDepth, e.SeepageDepth, a.HumusThickness FROM Sample_Env e JOIN Sample_Admin a ON e.PlotNumber = a.Plot WHERE e.PlotNumber = 'UX005A'`).Scan(&root, &seep, &hthick); err != nil {
		t.Fatal(err)
	}
	if root != 35 || seep != 40 || hthick != 5.0 {
		t.Fatalf("Header UX005A mutated: Rooting=%d Seepage=%d HumusThickness=%v", root, seep, hthick)
	}

	// 3. Legacy plots:
	// - LEG822 has SeepageDepth = -60: loading & saving an unrelated RootingDepth = 45 succeeds and keeps SeepageDepth = -60!
	leg822, err := service.GetPlot(ctx, state.ContextID, "LEG822")
	if err != nil {
		t.Fatalf("GetPlot(LEG822): %v", err)
	}
	leg822.RootingDepth = intP(45)
	if err := service.UpdatePlot(state.ContextID, *leg822); err != nil {
		t.Fatalf("expected unrelated RootingDepth update on LEG822 (SeepageDepth=-60) to succeed, got %v", err)
	}
	leg822Bad := *leg822
	leg822Bad.SeepageDepth = intP(-10)
	if err := service.UpdatePlot(state.ContextID, leg822Bad); err == nil {
		t.Fatal("expected changing SeepageDepth from -60 to -10 to fail")
	}

	// - LEG202 (PercentCoarseFragsTotal = 100) and LEG999 (ASP=12, 60+60/150, pH=16) allow unrelated Texture edits!
	if err := service.UpdateSoilRecords(state.ContextID, "LEG202", []vprocore.SoilRecordUpdate{{
		Kind: "Mineral", ID: 602,
		Text: map[string]vprocore.SoilTextUpdate{"texture": {Expected: str("L"), Value: str("SiL")}},
	}}); err != nil {
		t.Fatalf("expected unrelated Texture edit on LEG202 (Total=100) to succeed, got %v", err)
	}
	if err := service.UpdateSoilRecords(state.ContextID, "LEG999", []vprocore.SoilRecordUpdate{{
		Kind: "Mineral", ID: 603,
		Text: map[string]vprocore.SoilTextUpdate{"texture": {Expected: str("SL"), Value: str("LS")}},
	}}); err != nil {
		t.Fatalf("expected unrelated Texture edit on LEG999 (legacy out-of-range soil row) to succeed, got %v", err)
	}

	// 4. Direct ContextService.SaveMineralRecord & UpdateMineralRecord (saveChildWithChecks) coarse-fragment consistency:
	if err := service.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
		PlotNumber:               "UX005A",
		Horizon:                  str("BC"),
		UpperDepth:               flt(30),
		LowerDepth:               flt(50),
		PercentCoarseFragsGravel: intP(60),
		PercentCoarseFragsCobbles: intP(60),
		PercentCoarseFragsStones: intP(60),
		PercentCoarseFragsTotal:  intP(80),
	}); err == nil || !strings.Contains(err.Error(), "cannot exceed 100%") {
		t.Fatalf("SaveMineralRecord with 60+60+60/80 should fail, got %v", err)
	}
	if err := service.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
		PlotNumber:               "UX005A",
		Horizon:                  str("BC"),
		UpperDepth:               flt(30),
		LowerDepth:               flt(50),
		PercentCoarseFragsGravel: intP(30),
		PercentCoarseFragsCobbles: intP(30),
		PercentCoarseFragsTotal:  intP(50),
	}); err == nil || !strings.Contains(err.Error(), "PercentCoarseFragsTotal") {
		t.Fatalf("SaveMineralRecord with 30+30 > Total 50 should fail, got %v", err)
	}
	// Partial UpdateMineralRecord merging against stored row 601 (Gravel=20, Stones=5, Total=40): Cobbles=25 -> sum=50 > Total 40
	if err := service.UpdateMineralRecord(state.ContextID, vprocore.MineralRecord{
		ID:                        601,
		PlotNumber:                "UX005A",
		Horizon:                   str("Ah"),
		UpperDepth:                flt(0),
		LowerDepth:                flt(15),
		PercentCoarseFragsGravel:  intP(20),
		PercentCoarseFragsCobbles: intP(25),
		PercentCoarseFragsStones:  intP(5),
		PercentCoarseFragsTotal:   intP(40),
	}); err == nil || !strings.Contains(err.Error(), "PercentCoarseFragsTotal") {
		t.Fatalf("UpdateMineralRecord exceeding stored Total should fail, got %v", err)
	}
	// Unchanged legacy coarse fragments on LEG999 (60+60/150, ASP=12, pH=16) allow unrelated Texture edit via UpdateMineralRecord
	if err := service.UpdateMineralRecord(state.ContextID, vprocore.MineralRecord{
		ID:                        603,
		PlotNumber:                "LEG999",
		Horizon:                   str("Bm"),
		UpperDepth:                flt(0),
		LowerDepth:                flt(20),
		ASP:                       intP(12),
		Texture:                   str("SCL"),
		PercentCoarseFragsGravel:  intP(60),
		PercentCoarseFragsCobbles: intP(60),
		PercentCoarseFragsTotal:   intP(150),
		MineralFormpH:             flt(16),
	}); err != nil {
		t.Fatalf("expected UpdateMineralRecord unrelated Texture edit on LEG999 to succeed, got %v", err)
	}

	// 5. Non-ContextScoped PlotService also enforces parent soil quantitative bounds while preserving unchanged legacy rows.
	nonScopedPlots, _ := vprotest.HeaderFixture(t)
	if err := nonScopedPlots.CreatePlot(vprocore.FS882Header{
		PlotNumber:   "NSNEG",
		RootingDepth: intP(-5),
	}); err == nil || !strings.Contains(err.Error(), ">= 0 cm") {
		t.Fatalf("non-ContextScoped CreatePlot with negative RootingDepth should fail, got %v", err)
	}
}
