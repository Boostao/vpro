package lumping_test

import (
	"context"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/lumping"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestLumpCRUDValidationSaveAsAndImpactPreview(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// Seed controlled vegetation rows in Sample_Veg to test 99% cover cap and multi-species folding
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Sample_Veg WHERE PlotNumber='108050';
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover4, Cover6) VALUES
			('108050', 9001, 'SALIBEB', 62.5, NULL),
			('108050', 9002, 'SALISCO', 55.0, NULL),
			('108050', 9003, 'PSEUMEN1', NULL, 30.0),
			('108050', 9004, 'PSEUMEN2', NULL, 25.0);
	`)

	created, err := lumping.CreateLumpTable(service, ctx, state.ContextID, "TestCorr")
	if err != nil {
		t.Fatalf("CreateLumpTable failed: %v", err)
	}
	if created.TableName != "TestCorr_Lump" || created.MetadataVersion != "VP05" {
		t.Fatalf("unexpected created lump summary: %+v", created)
	}

	// Verify _table_metadata has 'VP05'
	db, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	var metaDesc string
	if err := db.QueryRow(`SELECT description FROM _table_metadata WHERE table_name='TestCorr_Lump'`).Scan(&metaDesc); err != nil {
		db.Close()
		t.Fatalf("missing _table_metadata entry: %v", err)
	}
	db.Close()
	if metaDesc != "VP05" {
		t.Fatalf("expected metadata VP05, got %q", metaDesc)
	}

	// Reject unknown species when AllowUnlisted is false
	if _, err := lumping.UpsertLumpRow(service, ctx, state.ContextID, "TestCorr", lumping.LumpRowInput{
		LumpCode: "SALIX",
		SppCode:  "ZZZZZZZ",
		Use:      true,
	}); err == nil {
		t.Fatal("expected unknown species code ZZZZZZZ to be rejected")
	}

	// Reject UTF-16 length overflow (SppCode > 8, LumpCode > 50)
	if _, err := lumping.UpsertLumpRow(service, ctx, state.ContextID, "TestCorr", lumping.LumpRowInput{
		LumpCode: "SALIX",
		SppCode:  "ABCDEFGHI",
		Use:      true,
	}); err == nil {
		t.Fatal("expected 9-char SppCode to be rejected")
	}

	// Add valid rows and verify Access BOOLEAN -1 / 0 storage
	r1, err := lumping.UpsertLumpRow(service, ctx, state.ContextID, "TestCorr", lumping.LumpRowInput{
		LumpCode: "SALIX",
		SppCode:  "SALIBEB",
		Use:      true,
	})
	if err != nil {
		t.Fatalf("UpsertLumpRow SALIBEB: %v", err)
	}
	if !r1.Use || r1.SourceCatalog != "VLists" {
		t.Fatalf("unexpected row metadata: %+v", r1)
	}

	if _, err := lumping.UpsertLumpRow(service, ctx, state.ContextID, "TestCorr", lumping.LumpRowInput{
		LumpCode: "SALIX",
		SppCode:  "SALISCO",
		Use:      true,
	}); err != nil {
		t.Fatalf("UpsertLumpRow SALISCO: %v", err)
	}

	// Verify physical SQLite storage uses -1 for Use=true
	dbCheck, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	var rawUse int
	if err := dbCheck.QueryRow(`SELECT CAST("Use" AS INTEGER) FROM TestCorr_Lump WHERE SppCode='SALIBEB'`).Scan(&rawUse); err != nil {
		dbCheck.Close()
		t.Fatal(err)
	}
	dbCheck.Close()
	if rawUse != -1 {
		t.Fatalf("expected Access BOOLEAN -1 in SQLite, got %d", rawUse)
	}

	// Preview impact: SALIBEB (62.5) + SALISCO (55.0) = 117.5 -> capped at 99.0!
	impact, err := lumping.PreviewLumpImpact(service, ctx, state.ContextID, "TestCorr_Lump", "")
	if err != nil {
		t.Fatalf("PreviewLumpImpact: %v", err)
	}
	if impact.CappedCells < 1 || impact.MergedCells < 1 {
		t.Fatalf("expected merged and 99%%-capped cells in impact preview, got %+v", impact)
	}
	foundSalix := false
	for _, g := range impact.Groups {
		if g.LumpCode == "SALIX" {
			foundSalix = true
			if g.MaxFoldedCover != 99.0 || g.CappedCells < 1 {
				t.Fatalf("expected SALIX MaxFoldedCover=99.0 and CappedCells>=1, got %+v", g)
			}
		}
	}
	if !foundSalix {
		t.Fatalf("expected SALIX group in impact preview, got %+v", impact.Groups)
	}

	// Toggle SALISCO off (Use = 0) and verify physical storage is 0 and cap no longer triggers
	toggled, err := lumping.ToggleLumpRow(service, ctx, state.ContextID, "TestCorr", "SALISCO", false)
	if err != nil {
		t.Fatalf("ToggleLumpRow: %v", err)
	}
	if toggled.Use {
		t.Fatalf("expected Use=false after toggle")
	}
	dbZero, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := dbZero.QueryRow(`SELECT CAST("Use" AS INTEGER) FROM TestCorr_Lump WHERE SppCode='SALISCO'`).Scan(&rawUse); err != nil {
		dbZero.Close()
		t.Fatal(err)
	}
	dbZero.Close()
	if rawUse != 0 {
		t.Fatalf("expected Access BOOLEAN 0 after toggle false, got %d", rawUse)
	}

	// SaveAs external & local discovery
	extPath := filepath.Join(t.TempDir(), "ExternalLumps.db")
	extDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := extDB.Exec(`
		CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT);
		INSERT INTO "_table_metadata" VALUES ('Regional_Lump', 'VP05');
		CREATE TABLE "Regional_Lump" ("LumpCode" VARCHAR(50), "SppCode" VARCHAR(8) UNIQUE, "Use" BOOLEAN);
		INSERT INTO "Regional_Lump" VALUES ('PSEUMEN', 'PSEUMEN1', -1), ('PSEUMEN', 'PSEUMEN2', -1);
	`); err != nil {
		extDB.Close()
		t.Fatal(err)
	}
	extDB.Close()

	discovered, err := lumping.DiscoverLumpTables(service, ctx, state.ContextID, []string{extPath})
	if err != nil {
		t.Fatalf("DiscoverLumpTables: %v", err)
	}
	hasLocal, hasExternal := false, false
	for _, d := range discovered {
		if d.TableName == "TestCorr_Lump" && d.IsActiveProject {
			hasLocal = true
		}
		if d.TableName == "Regional_Lump" && !d.IsActiveProject {
			hasExternal = true
		}
	}
	if !hasLocal || !hasExternal {
		t.Fatalf("expected both local TestCorr_Lump and external Regional_Lump, got %+v", discovered)
	}

	copied, err := lumping.SaveAsLumpTable(service, ctx, state.ContextID, "Regional_Lump", extPath, "CopiedReg")
	if err != nil {
		t.Fatalf("SaveAsLumpTable: %v", err)
	}
	if copied.RowCount != 2 || copied.ActiveCount != 2 || copied.TableName != "CopiedReg_Lump" {
		t.Fatalf("unexpected SaveAs summary: %+v", copied)
	}

	// Update and Delete row
	if _, err := lumping.UpdateLumpRow(service, ctx, state.ContextID, "CopiedReg", "PSEUMEN2", lumping.LumpRowInput{
		LumpCode: "PSEUMEN",
		SppCode:  "SALIBEB",
		Use:      true,
	}); err != nil {
		t.Fatalf("UpdateLumpRow: %v", err)
	}
	if err := lumping.DeleteLumpRow(service, ctx, state.ContextID, "CopiedReg", "SALIBEB"); err != nil {
		t.Fatalf("DeleteLumpRow: %v", err)
	}
	rowsAfter, err := lumping.GetLumpTableRows(service, ctx, state.ContextID, "CopiedReg", "")
	if err != nil || len(rowsAfter) != 1 {
		t.Fatalf("expected 1 row after delete, got %d (err=%v)", len(rowsAfter), err)
	}
}

func TestLumpSpecCompilerPresetAndMaterialize(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// Seed infraspecific (ABIEMAG1), Codetype='D' seedling/dead (ABIEAMAD, ABIEAMAX), Carex, Sphagnum, and liverwort (lifeform 10)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Sample_Veg WHERE PlotNumber='108050';
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover2, Cover6, Cover7) VALUES
			('108050', 9101, 'ABIEMAG1', 20.0, NULL, NULL),
			('108050', 9102, 'ABIEAMAD', NULL, NULL, 5.0),
			('108050', 9103, 'ABIEAMAX', 15.0, NULL, NULL),
			('108050', 9104, 'CARESIT', NULL, 40.0, NULL),
			('108050', 9105, 'CAREAQU', NULL, 35.0, NULL),
			('108050', 9106, 'SPHACAP', NULL, NULL, 60.0),
			('108050', 9107, 'PTILCIL', NULL, NULL, 12.0);
	`)

	presets := lumping.ListLumpPresets()
	if len(presets) == 0 || presets[0].ID != lumping.PresetBECProvincialCorrelation2026 {
		t.Fatalf("expected BEC_Provincial_Correlation_2026 preset, got %+v", presets)
	}

	preview, err := lumping.PreviewLumpSpec(service, ctx, state.ContextID, lumping.LumpSpec{
		Preset:                lumping.PresetBECProvincialCorrelation2026,
		NonVascularLifeforms:  []int{10},
		ScopeToProjectSpecies: true,
	})
	if err != nil {
		t.Fatalf("PreviewLumpSpec failed: %v", err)
	}

	bySpp := map[string]lumping.LumpRow{}
	for _, r := range preview.Rows {
		bySpp[r.SppCode] = r
	}

	expectMap := map[string]string{
		"ABIEMAG1": "ABIEMAG",
		"ABIEAMAD": "ABIEAMA",
		"ABIEAMAX": "ABIEAMA",
		"CARESIT":  "CAREX",
		"CAREAQU":  "CAREX",
		"SPHACAP":  "SPHAGNUM",
	}
	for spp, expectedLump := range expectMap {
		row, ok := bySpp[spp]
		if !ok {
			t.Fatalf("expected %s in compiled LumpSpec rows, got %+v", spp, preview.Rows)
		}
		if row.LumpCode != expectedLump {
			t.Fatalf("for %s expected LumpCode=%s, got %s (origin=%s)", spp, expectedLump, row.LumpCode, row.RuleOrigin)
		}
	}
	// Check liverwort PTILCIL (Ptilidium ciliare, Lifeform 10) rolled up to genus
	if r, ok := bySpp["PTILCIL"]; !ok || !strings.Contains(r.RuleOrigin, "lifeform_10_genus") {
		t.Fatalf("expected PTILCIL lifeform 10 genus rollup, got %+v", bySpp["PTILCIL"])
	}

	// Materialize into Provincial2026_Lump
	mat, err := lumping.MaterializeLumpSpec(service, ctx, state.ContextID, "Provincial2026", lumping.LumpSpec{
		Preset:                lumping.PresetBECProvincialCorrelation2026,
		ScopeToProjectSpecies: true,
	}, false)
	if err != nil {
		t.Fatalf("MaterializeLumpSpec: %v", err)
	}
	if mat.Table.TableName != "Provincial2026_Lump" || mat.RowsWritten < 6 {
		t.Fatalf("unexpected materialization result: %+v", mat)
	}
}

func TestPreviewLumpImpactSublayerPrecedenceAndSampleParity(t *testing.T) {
	service, initState := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// 1. Sample SU + Sample_Lump must report 1 capped cell (Plot 8428935 ABIESPP Layer 1: 90+30 -> 99%),
	// never double-counting populated TotalA alongside Cover1 (UX-CLASS-003).
	sampleSel := vprocore.ContextSelection{
		Project:       initState.ActiveProject,
		ProjectPath:   initState.ProjectPath,
		SU:            "Sample",
		SUPath:        initState.ProjectPath,
		Hierarchy:     initState.ActiveHierarchy,
		HierarchyPath: initState.HierarchyPath,
	}
	sampleState, err := service.SwitchContext(initState.ContextID, sampleSel)
	if err != nil {
		t.Fatalf("SwitchContext(Sample) failed: %v", err)
	}
	sampleImpact, err := lumping.PreviewLumpImpact(service, ctx, sampleState.ContextID, "Sample_Lump", "")
	if err != nil {
		t.Fatalf("PreviewLumpImpact(Sample_Lump) failed: %v", err)
	}
	if sampleImpact.TotalPlots != 51 {
		t.Fatalf("expected 51 scoped plots on Sample SU, got %d", sampleImpact.TotalPlots)
	}
	if sampleImpact.CappedCells != 1 {
		t.Fatalf("UX-CLASS-003: expected CappedCells=1 on Sample_Lump (matching Synthesis), got %+v", sampleImpact)
	}

	// 2. Controlled rows verifying Cover1..3 over TotalA, Cover4..5c over TotalB,
	// fallback TotalA/TotalB when sublayers are NULL, singleton lumped 99% cap, and unlumped 99.5% preservation.
	vprotest.MutateContextFixture(t, initState.ProjectPath, `
		DELETE FROM Sample_Veg;
		DELETE FROM Sample_SU;
		INSERT INTO Sample_SU (PlotNumber, SiteUnit) VALUES ('108050', 'U1');
		INSERT INTO Sample_Veg (PlotNumber, ID, Species, Cover1, Cover2, TotalA, Cover4, TotalB, Cover6) VALUES
			-- Both Cover1 and TotalA populated: TotalA must NOT be double-counted alongside Cover1
			('108050', 9201, 'ABIELAS',  90.0, NULL, 90.0, 60.0, 60.0, NULL),
			('108050', 9202, 'ABIEMAG1', 30.0, NULL, 30.0, 50.0, 50.0, NULL),
			-- Fallback TotalA when Cover1..Cover3 are all NULL
			('108050', 9203, 'SALIBEB',  NULL, NULL, 60.0, NULL, NULL, NULL),
			('108050', 9204, 'SALISCO',  NULL, NULL, 55.0, NULL, NULL, NULL),
			-- Singleton mapped species > 99% (capped at 99%) vs unmapped singleton > 99% (uncapped)
			('108050', 9205, 'CARESIT',  NULL, NULL, NULL, NULL, NULL, 99.5),
			('108050', 9206, 'TSUGHET',  NULL, NULL, NULL, NULL, NULL, 99.5);
	`)

	swState, err := service.SwitchContext(sampleState.ContextID, sampleSel)
	if err != nil {
		t.Fatalf("SwitchContext refresh failed: %v", err)
	}
	if _, err := lumping.CreateLumpTable(service, ctx, swState.ContextID, "PrecTest"); err != nil {
		t.Fatalf("CreateLumpTable(PrecTest): %v", err)
	}
	for _, row := range []lumping.LumpRowInput{
		{LumpCode: "ABIESPP", SppCode: "ABIELAS", Use: true},
		{LumpCode: "ABIESPP", SppCode: "ABIEMAG1", Use: true},
		{LumpCode: "SALIX", SppCode: "SALIBEB", Use: true},
		{LumpCode: "SALIX", SppCode: "SALISCO", Use: true},
		{LumpCode: "CAREX", SppCode: "CARESIT", Use: true},
	} {
		if _, err := lumping.UpsertLumpRow(service, ctx, swState.ContextID, "PrecTest", row); err != nil {
			t.Fatalf("UpsertLumpRow(%+v): %v", row, err)
		}
	}

	impact, err := lumping.PreviewLumpImpact(service, ctx, swState.ContextID, "PrecTest_Lump", "")
	if err != nil {
		t.Fatalf("PreviewLumpImpact(PrecTest_Lump): %v", err)
	}
	// Expected capped cells:
	// 1) ABIESPP Cover1 (90+30=120 -> 99; TotalA skipped!)
	// 2) ABIESPP Cover4 (60+50=110 -> 99; TotalB skipped!)
	// 3) SALIX fallback TotalA (60+55=115 -> 99; Cover1..3 NULL)
	// 4) CAREX singleton lumped Cover6 (99.5 -> 99)
	// TSUGHET unlumped Cover6=99.5 must NOT be capped!
	if impact.CappedCells != 4 {
		t.Fatalf("expected exactly 4 capped cells (no TotalA/TotalB double count, no unlumped 99.5 cap), got %+v", impact)
	}
	if impact.MergedCells != 3 {
		t.Fatalf("expected exactly 3 merged cells (ABIESPP Cover1, ABIESPP Cover4, SALIX TotalA), got %+v", impact)
	}
}
