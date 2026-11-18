package projectops_test

import (
	"context"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/projectops"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestWave2_OptimizeVegPolicyAllFiveRules(t *testing.T) {
	ctx := context.Background()

	t.Run("RefusesInvalidOrDuplicate32BitIDsEvenOnSingletons", func(t *testing.T) {
		svc, state := vprotest.ContextServiceFixture(t)
		proj, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
			ProjectName:       "BadIDProj",
			ActivateOnSuccess: true,
		})
		if err != nil {
			t.Fatal(err)
		}
		cid := proj.State.ContextID

		// Duplicate IDs across two DIFFERENT species/plots (singletons) -> must refuse!
		vprotest.MutateContextFixture(t, proj.DestinationPath, `
			INSERT INTO BadIDProj_Env (PlotNumber, ProjectID, Zone) VALUES ('P01', 'B1', 'CWH');
			INSERT INTO BadIDProj_Env (PlotNumber, ProjectID, Zone) VALUES ('P02', 'B1', 'CWH');
			INSERT INTO BadIDProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'PSEUMEN', 777, 10, 0);
			INSERT INTO BadIDProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P02', 'TSUGHET', 777, 20, 0);
		`)
		if _, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{}); err == nil || !strings.Contains(err.Error(), "duplicate ID") {
			t.Fatalf("expected duplicate ID refusal, got %v", err)
		}

		// Fix duplicate ID, insert NULL ID -> must refuse!
		vprotest.MutateContextFixture(t, proj.DestinationPath, `
			UPDATE BadIDProj_Veg SET ID = 778 WHERE PlotNumber = 'P02';
			INSERT INTO BadIDProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'THUJPLI', NULL, 5, 0);
		`)
		if _, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{}); err == nil || !strings.Contains(err.Error(), "32-bit ID") {
			t.Fatalf("expected NULL ID refusal, got %v", err)
		}

		// Out-of-range 64-bit ID -> must refuse!
		vprotest.MutateContextFixture(t, proj.DestinationPath, `
			UPDATE BadIDProj_Veg SET ID = 3000000000 WHERE Species = 'THUJPLI';
		`)
		if _, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{}); err == nil || !strings.Contains(err.Error(), "32-bit ID") {
			t.Fatalf("expected >int32 ID refusal, got %v", err)
		}
	})

	t.Run("SmallestSignedIDSurvivorAndTotalAConsensusPreservesLayer", func(t *testing.T) {
		svc, state := vprotest.ContextServiceFixture(t)
		proj, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
			ProjectName:       "MinSignedProj",
			ActivateOnSuccess: true,
		})
		if err != nil {
			t.Fatal(err)
		}
		cid := proj.State.ContextID

		// Insert smaller positive ID AFTER larger negative ID is physically later in rowid:
		// smallest signed 32-bit ID is -42000 (not 100!).
		// Include TotalA alongside Cover1 & matching Layer 'A' -> Layer MUST survive!
		vprotest.MutateContextFixture(t, proj.DestinationPath, `
			INSERT INTO MinSignedProj_Env (PlotNumber, ProjectID, Zone) VALUES ('00337', 'MS1', 'CWH');
			INSERT INTO MinSignedProj_Veg (PlotNumber, Species, ID, Layer, Cover1, TotalA, Height1, Collected, LL, Flag)
				VALUES ('00337', 'PSEUMEN', 100, 'A', 40.0, 45.0, 22.0, 'V', NULL, 0);
			INSERT INTO MinSignedProj_Veg (PlotNumber, Species, ID, Layer, Cover1, TotalA, Height1, Collected, LL, Flag)
				VALUES ('00337', 'PSEUMEN', -42000, NULL, 35.0, 50.0, 28.0, NULL, 3, NULL);
			INSERT INTO MinSignedProj_Veg (PlotNumber, Species, ID, Layer, Cover1, Flag)
				VALUES ('00337', 'SINGLE', 500, '1', 15.0, 0);
		`)

		preview, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{})
		if err != nil {
			t.Fatalf("PreviewOptimizeVeg failed: %v", err)
		}
		if preview.HasBlockingConflicts || len(preview.Groups) != 1 {
			t.Fatalf("unexpected conflicts or groups: %+v", preview)
		}
		g := preview.Groups[0]
		if g.SurvivorID != -42000 {
			t.Fatalf("expected smallest signed ID -42000 as survivor, got %d", g.SurvivorID)
		}
		if g.OldToSurvivorIDMap[100] != -42000 {
			t.Fatalf("expected OldToSurvivorIDMap[100]=-42000, got %+v", g.OldToSurvivorIDMap)
		}
		if g.MergedCovers["Cover1"] != 40.0 || g.MergedCovers["TotalA"] != 50.0 || g.MergedHeights["Height1"] != 28.0 {
			t.Fatalf("expected independent MAX (40, 50, 28), got covers=%+v heights=%+v", g.MergedCovers, g.MergedHeights)
		}

		res, err := projectops.ApplyOptimizeVeg(svc, ctx, cid, projectops.ApplyOptimizeVegRequest{
			ExpectedDigest: preview.PreviewDigest,
		})
		if err != nil {
			t.Fatalf("ApplyOptimizeVeg failed: %v", err)
		}
		if res.ConsolidatedGroups != 1 || res.DeletedRows != 1 || res.AfterRowCount != 2 {
			t.Fatalf("unexpected apply result: %+v", res)
		}

		db, err := sqlutil.OpenReadOnly(proj.DestinationPath)
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		var id, ll, flag sql.NullInt64
		var layer, coll sql.NullString
		var c1, ta, h1 sql.NullFloat64
		if err := db.QueryRow(`SELECT ID, Layer, Cover1, TotalA, Height1, Collected, LL, CAST(Flag AS INTEGER) FROM MinSignedProj_Veg WHERE PlotNumber='00337' AND Species='PSEUMEN'`).
			Scan(&id, &layer, &c1, &ta, &h1, &coll, &ll, &flag); err != nil {
			t.Fatal(err)
		}
		if !id.Valid || id.Int64 != -42000 {
			t.Fatalf("expected survivor ID=-42000 preserved verbatim, got %#v", id)
		}
		if !layer.Valid || layer.String != "A" {
			t.Fatalf("expected Layer='A' preserved with TotalA present, got %#v", layer)
		}
		if !coll.Valid || coll.String != "V" || !ll.Valid || ll.Int64 != 3 || !flag.Valid || flag.Int64 != 0 {
			t.Fatalf("expected consensus Collected='V' LL=3 Flag=0, got coll=%#v ll=%#v flag=%#v", coll, ll, flag)
		}
		if !c1.Valid || c1.Float64 != 40.0 || !ta.Valid || ta.Float64 != 50.0 || !h1.Valid || h1.Float64 != 28.0 {
			t.Fatalf("expected independent MAX values, got c1=%#v ta=%#v h1=%#v", c1, ta, h1)
		}
	})

	t.Run("ConsensusConflictsAndLockedPlotAndAuditOverride", func(t *testing.T) {
		svc, state := vprotest.ContextServiceFixture(t)
		proj, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
			ProjectName:       "BlockVegProj",
			ActivateOnSuccess: true,
		})
		if err != nil {
			t.Fatal(err)
		}
		cid := proj.State.ContextID

		vprotest.MutateContextFixture(t, proj.DestinationPath, `
			INSERT INTO BlockVegProj_Env (PlotNumber, ProjectID, Zone, Flag) VALUES ('P01', 'BV1', 'CWH', 0);
			INSERT INTO BlockVegProj_Env (PlotNumber, ProjectID, Zone, Flag) VALUES ('P02', 'BV1', 'CWH', -1);
			-- Conflicting Layer, Collected, Flag, HeightB, Cultural1
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Layer, Collected, Flag, HeightB, Cultural1)
				VALUES ('P01', 'PSEUMEN', 10, '1', 'A', 0, '5.0', 1);
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Layer, Collected, Flag, HeightB, Cultural1)
				VALUES ('P01', 'PSEUMEN', 20, '2', 'B', -1, '6.0', 2);
			-- Audit-referenced retired ID on clean group on P01
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P01', 'THUJPLI', 30, 12, 0);
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Cover2, Flag) VALUES ('P01', 'THUJPLI', 40, 15, 0);
			INSERT INTO BlockVegProj_Audit (Project, User, PlotNumber, "Table", EditField, EditWhen, BeforeEdit, AfterEdit, Restore, Flag, ID)
				VALUES ('BlockVegProj', 'Analyst', 'P01', '_Veg', 'Cover2', '2026-11-01 10:00:00', '10', '15', 0, 0, 40);
			-- Locked plot group on P02
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES ('P02', 'ABIEAMA', 50, 10, 0);
			INSERT INTO BlockVegProj_Veg (PlotNumber, Species, ID, Cover2, Flag) VALUES ('P02', 'ABIEAMA', 60, 20, 0);
		`)

		prevAll, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{})
		if err != nil {
			t.Fatal(err)
		}
		if !prevAll.HasBlockingConflicts || prevAll.BlockedGroupCount != 3 {
			t.Fatalf("expected all 3 groups blocked initially, got %+v", prevAll)
		}
		if _, err := projectops.ApplyOptimizeVeg(svc, ctx, cid, projectops.ApplyOptimizeVegRequest{
			ExpectedDigest: prevAll.PreviewDigest,
		}); err == nil {
			t.Fatalf("expected ApplyOptimizeVeg to refuse blocked preview")
		}

		// Verify P01 THUJPLI is still blocked with CustodianAuditOverride:false, but unblocked with true.
		prevNoOverride, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{
			PlotNumbers: []string{"P01"},
		})
		if err != nil {
			t.Fatal(err)
		}
		var thujGrp *projectops.OptimizeVegGroup
		var pseuGrp *projectops.OptimizeVegGroup
		for i := range prevNoOverride.Groups {
			if prevNoOverride.Groups[i].Species == "THUJPLI" {
				thujGrp = &prevNoOverride.Groups[i]
			} else if prevNoOverride.Groups[i].Species == "PSEUMEN" {
				pseuGrp = &prevNoOverride.Groups[i]
			}
		}
		if thujGrp == nil || !thujGrp.Blocked || len(thujGrp.AuditReferences) != 1 {
			t.Fatalf("expected THUJPLI blocked by 1 AuditReference, got %+v", thujGrp)
		}
		if pseuGrp == nil || !pseuGrp.Blocked || len(pseuGrp.Conflicts) < 5 {
			t.Fatalf("expected PSEUMEN blocked by 5 field conflicts, got %+v", pseuGrp)
		}

		// Even with CustodianAuditOverride=true, P02 locked plot stays blocked.
		prevLocked, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{
			PlotNumbers:            []string{"P02"},
			CustodianAuditOverride: true,
		})
		if err != nil {
			t.Fatal(err)
		}
		if !prevLocked.HasBlockingConflicts || prevLocked.BlockedGroupCount != 1 {
			t.Fatalf("expected locked plot P02 to remain blocked under CustodianAuditOverride, got %+v", prevLocked)
		}

		// Delete conflicting PSEUMEN group so P01 only has audit-referenced THUJPLI, then apply with CustodianAuditOverride=true.
		vprotest.MutateContextFixture(t, proj.DestinationPath, `DELETE FROM BlockVegProj_Veg WHERE PlotNumber='P01' AND Species='PSEUMEN';`)
		prevOverride, err := projectops.PreviewOptimizeVeg(svc, ctx, cid, projectops.OptimizeVegOptions{
			PlotNumbers:            []string{"P01"},
			CustodianAuditOverride: true,
		})
		if err != nil {
			t.Fatal(err)
		}
		if prevOverride.HasBlockingConflicts || len(prevOverride.AuditReferences) != 1 {
			t.Fatalf("expected THUJPLI unblocked with CustodianAuditOverride=true, got %+v", prevOverride)
		}
		res, err := projectops.ApplyOptimizeVeg(svc, ctx, cid, projectops.ApplyOptimizeVegRequest{
			PlotNumbers:            []string{"P01"},
			ExpectedDigest:         prevOverride.PreviewDigest,
			CustodianAuditOverride: true,
		})
		if err != nil {
			t.Fatalf("ApplyOptimizeVeg with CustodianAuditOverride failed: %v", err)
		}
		if res.OldToSurvivorIDMap[40] != 30 {
			t.Fatalf("expected OldToSurvivorIDMap[40]=30, got %+v", res.OldToSurvivorIDMap)
		}
	})
}

func TestWave2_PresetsTruncatedProjectIDSaveAsHierarchyAndSplinterCase(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	// S2.5 / S2.11 / S2.17: Long ProjectName (21..31 chars) triggers ProjectIDDerived + notice; NAD83 + 6 metadata fields populated.
	longName := "LongBritishColumbiaProj25"
	proj, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName:       longName,
		PresetID:          "LMH25_2023_FS882",
		ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !proj.ProjectIDDerived || len(proj.ProjectID) != 20 || !strings.Contains(proj.ProjectIDNotice, "20") {
		t.Fatalf("expected ProjectIDDerived notice and 20-char ID, got derived=%v id=%q notice=%q",
			proj.ProjectIDDerived, proj.ProjectID, proj.ProjectIDNotice)
	}

	db, err := sqlutil.OpenReadOnly(proj.DestinationPath)
	if err != nil {
		t.Fatal(err)
	}
	var datum, coord, funder, fieldCo, area, method, csys sql.NullString
	err = db.QueryRow(`SELECT Datum, CoordinatingAgency, ProponentFunder, FieldCompanyAgency, GeographicStudyArea, GeoRefMethod, CoordinateSystem FROM `+
		longName+`_Metadata LIMIT 1`).Scan(&datum, &coord, &funder, &fieldCo, &area, &method, &csys)
	db.Close()
	if err != nil {
		t.Fatal(err)
	}
	if datum.String != "NAD83" || coord.String != "MoF" || funder.String != "MoF" ||
		fieldCo.String != "Forests, Lands and Natural Resources" || area.String != "British Columbia" ||
		method.String != "GPS +/- 10m" || csys.String != "dd.mm.ss.s" {
		t.Fatalf("unexpected preset metadata fields: datum=%q coord=%q funder=%q fieldCo=%q area=%q method=%q csys=%q",
			datum.String, coord.String, funder.String, fieldCo.String, area.String, method.String, csys.String)
	}

	// Verify all 4 built-in presets use Datum = NAD83.
	for _, p := range projectops.ListProjectMetadataPresets() {
		if p.Datum != "NAD83" {
			t.Fatalf("expected preset %s Datum='NAD83', got %q", p.ID, p.Datum)
		}
	}

	// S2.12: Create companion <Old>_Hierarchy, make it active, SaveProjectAs with ActivateOnSuccess=true -> preserves <New>_Hierarchy.
	cid := proj.State.ContextID
	oldHierTable := longName + "_Hierarchy"
	vprotest.MutateContextFixture(t, proj.DestinationPath, `
		CREATE TABLE IF NOT EXISTS "`+oldHierTable+`" ("ID" INTEGER PRIMARY KEY, "Name" TEXT, "Parent" INTEGER, "Level" INTEGER, "Tag" TEXT, "MyOrder" TEXT, "ChildID" INTEGER, "Flag" INTEGER);
		INSERT INTO "`+oldHierTable+`" ("ID", "Name", "Parent", "Level") VALUES (1, 'Root', NULL, 1);
		CREATE TABLE IF NOT EXISTS "__VPRO_HierarchyIdentity" ("HierarchyTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("HierarchyTable", "ID"));
		INSERT INTO "__VPRO_HierarchyIdentity" ("HierarchyTable", "ID") VALUES ('`+oldHierTable+`', 1), ('`+oldHierTable+`', 3);
	`)
	switched, err := svc.SwitchContext(cid, vprocore.ContextSelection{
		Project:       longName,
		ProjectPath:   proj.DestinationPath,
		SU:            "None",
		Hierarchy:     longName,
		HierarchyPath: proj.DestinationPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext to active hierarchy failed: %v", err)
	}
	cid = switched.ContextID

	newDir := t.TempDir()
	saved, err := projectops.SaveProjectAs(svc, ctx, cid, projectops.SaveProjectAsRequest{
		NewProjectName:    "SavedHierProj",
		DestinationPath:   filepath.Join(newDir, "SavedHierProj.db"),
		ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatalf("SaveProjectAs failed: %v", err)
	}
	if saved.State == nil || saved.State.ActiveHierarchy != "SavedHierProj" || saved.State.HierarchyPath != saved.DestinationPath {
		t.Fatalf("expected active Hierarchy preserved as SavedHierProj at %s, got %+v", saved.DestinationPath, saved.State)
	}
	// ENG-GO-004: the reservation for deleted node ID 3 survives Save As under the new prefix, so
	// the next node created in the saved project cannot reuse ID 3.
	hdb, err := sqlutil.OpenReadOnly(saved.DestinationPath)
	if err != nil {
		t.Fatal(err)
	}
	var reservedMax sql.NullInt64
	err = hdb.QueryRow(`SELECT MAX("ID") FROM "__VPRO_HierarchyIdentity" WHERE "HierarchyTable" = 'SavedHierProj_Hierarchy'`).Scan(&reservedMax)
	hdb.Close()
	if err != nil || !reservedMax.Valid || reservedMax.Int64 != 3 {
		t.Fatalf("expected hierarchy reservation ID 3 carried into SavedHierProj_Hierarchy, got %v (%v)", reservedMax, err)
	}

	// S2.18: Seed mixed-case ProjectID in Env vs lowercase ProjectID in Metadata and splinter-export -> matches case-insensitively and preserves Metadata stored casing.
	vprotest.MutateContextFixture(t, saved.DestinationPath, `
		INSERT INTO "SavedHierProj_Env" ("PlotNumber", "ProjectID", "Zone") VALUES ('P100', 'MixCaseID', 'ICH');
		INSERT INTO "SavedHierProj_Metadata" ("ID", "ProjectID", "ProjectTitle") VALUES (99, 'mixcaseid', 'Mixed Case Title');
	`)
	splinterPath := filepath.Join(t.TempDir(), "SplinterOut.db")
	splinterRes, err := projectops.ExportSplinterProject(svc, ctx, saved.State.ContextID, projectops.ExportSplinterRequest{
		SplinterProject: "SplinterOut",
		DestinationPath: splinterPath,
		PlotNumbers:     []string{"P100"},
	})
	if err != nil {
		t.Fatalf("ExportSplinterProject failed: %v", err)
	}
	if splinterRes.ExportedPlotCount != 1 {
		t.Fatalf("expected 1 plot in splinter export, got %d", splinterRes.ExportedPlotCount)
	}
	sdb, err := sqlutil.OpenReadOnly(splinterPath)
	if err != nil {
		t.Fatal(err)
	}
	defer sdb.Close()
	var exportedPID, exportedTitle string
	if err := sdb.QueryRow(`SELECT "ProjectID", "ProjectTitle" FROM "SplinterOut_Metadata" LIMIT 1`).Scan(&exportedPID, &exportedTitle); err != nil {
		t.Fatalf("expected preserved metadata row in splinter export: %v", err)
	}
	if exportedPID != "mixcaseid" || exportedTitle != "Mixed Case Title" {
		t.Fatalf("expected stored casing preserved in splinter metadata, got id=%q title=%q", exportedPID, exportedTitle)
	}
}

func TestWave2_CompareAndMergeFixes(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	dir := t.TempDir()
	basePath := filepath.Join(dir, "BaseP.db")
	srcPath := filepath.Join(dir, "SrcP.db")
	if _, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName: "BaseP", DestinationPath: basePath,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName: "SrcP", DestinationPath: srcPath,
	}); err != nil {
		t.Fatal(err)
	}
	tgtRes, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName: "TgtP", ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	tgtPath := tgtRes.DestinationPath
	cid := tgtRes.State.ContextID

	// Seed Base, Src, Tgt:
	// - Plot 'DEL1': identical in Base and Tgt, deleted from Src -> SourceDelete!
	// - Plot 'CON1': deleted from Src, modified in Tgt (Zone CWH -> ICH) -> Conflict!
	// - Plot 'DUP1': duplicate natural mineral horizons differing only by ID in Src vs Tgt, plus case difference in Env.Zone when CaseInsensitiveText=true.
	// - Metadata change in Src.
	vprotest.MutateContextFixture(t, basePath, `
		UPDATE BaseP_Metadata SET ProjectID = 'P1' WHERE ID = 1;
		INSERT INTO BaseP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('DEL1', 'P1', 'CWH', '01');
		INSERT INTO BaseP_Admin (Plot, PlotType) VALUES ('DEL1', 'FS882');
		INSERT INTO BaseP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('CON1', 'P1', 'CWH', '01');
		INSERT INTO BaseP_Admin (Plot, PlotType) VALUES ('CON1', 'FS882');
		INSERT INTO BaseP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('DUP1', 'P1', 'CWH', '01');
		INSERT INTO BaseP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 1, 'Bf', 0, 15);
		INSERT INTO BaseP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 2, 'Bf', 0, 15);
	`)
	vprotest.MutateContextFixture(t, tgtPath, `
		UPDATE TgtP_Metadata SET ProjectID = 'P1' WHERE ID = 1;
		INSERT INTO TgtP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('DEL1', 'P1', 'CWH', '01');
		INSERT INTO TgtP_Admin (Plot, PlotType) VALUES ('DEL1', 'FS882');
		INSERT INTO TgtP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('CON1', 'P1', 'ICH', '01');
		INSERT INTO TgtP_Admin (Plot, PlotType) VALUES ('CON1', 'FS882');
		INSERT INTO TgtP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('DUP1', 'P1', 'cwh', '01');
		INSERT INTO TgtP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 501, 'Bf', 0, 15);
		INSERT INTO TgtP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 502, 'Bf', 0, 15);
	`)
	vprotest.MutateContextFixture(t, srcPath, `
		UPDATE SrcP_Metadata SET ProjectID = 'P1', ProjectTitle = 'Updated Source Title' WHERE ID = 1;
		INSERT INTO SrcP_Env (PlotNumber, ProjectID, Zone, MapUnit) VALUES ('DUP1', 'P1', 'CWH', 'MapUnit16CharsXX');
		INSERT INTO SrcP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 901, 'Bf', 0, 15);
		INSERT INTO SrcP_Mineral (PlotNumber, ID, Horizon, UpperDepth, LowerDepth) VALUES ('DUP1', 902, 'Bf', 0, 15);
	`)

	// S2.4 / S2.14: CaseInsensitiveText=true collapses DUP1 Env.Zone 'CWH' vs 'cwh' and duplicate Bf rows cleanly while surfacing MetadataDiffs + MapUnit diff!
	cmp, err := projectops.CompareProjects(svc, ctx, cid, projectops.CompareProjectsRequest{
		SourcePath:          srcPath,
		TargetPath:          tgtPath,
		CaseInsensitiveText: true,
	})
	if err != nil {
		t.Fatalf("CompareProjects failed: %v", err)
	}
	if cmp.MetadataDiffCount == 0 {
		t.Fatalf("expected MetadataDiffCount > 0, got %+v", cmp)
	}
	for _, p := range cmp.Plots {
		if p.PlotNumber == "DUP1" {
			for _, fd := range p.FieldDiffs {
				if fd.Table == "Mineral" || fd.Field == "Zone" {
					t.Fatalf("unexpected Mineral duplicate or case-only Zone diff under CaseInsensitiveText: %+v", fd)
				}
			}
		}
	}

	// S2.3 / S2.13: 3-Way Merge classifies DEL1 as SourceDelete, CON1 as Conflict, reconciles Metadata, and enforces MapUnit <= 15 UTF-16 code units.
	prevBad, err := projectops.PreviewThreeWayMerge(svc, ctx, cid, projectops.ThreeWayMergePreviewRequest{
		SourcePath:          srcPath,
		BasePath:            basePath,
		CaseInsensitiveText: true,
	})
	if err != nil {
		t.Fatalf("PreviewThreeWayMerge failed: %v", err)
	}
	var badMetaRes = map[string]string{}
	for _, m := range prevBad.MetadataItems {
		badMetaRes[m.ConflictID] = projectops.MergeResolutionAcceptSource
	}
	if _, err := projectops.ExecuteThreeWayMerge(svc, ctx, cid, projectops.ThreeWayMergeExecuteRequest{
		SourcePath:                srcPath,
		BasePath:                  basePath,
		ExpectedPreviewDigest:     prevBad.PreviewDigest,
		DefaultConflictResolution: projectops.MergeResolutionKeepTarget,
		FieldResolutions:          badMetaRes,
		CaseInsensitiveText:       true,
	}); err == nil || !strings.Contains(err.Error(), "MapUnit") {
		t.Fatalf("expected 16-char MapUnit to be rejected by ExecuteThreeWayMerge (max 15), got %v", err)
	}

	// Fix MapUnit to exact 15-char limit and re-preview/execute.
	vprotest.MutateContextFixture(t, srcPath, `UPDATE SrcP_Env SET MapUnit = 'Valid15MapUnitX' WHERE PlotNumber = 'DUP1';`)
	prev, err := projectops.PreviewThreeWayMerge(svc, ctx, cid, projectops.ThreeWayMergePreviewRequest{
		SourcePath:          srcPath,
		BasePath:            basePath,
		CaseInsensitiveText: true,
	})
	if err != nil {
		t.Fatalf("PreviewThreeWayMerge failed: %v", err)
	}
	if prev.SourceDeleteCount != 1 {
		t.Fatalf("expected SourceDeleteCount=1 for DEL1, got %+v", prev)
	}
	catByPlot := map[string]string{}
	for _, p := range prev.Plots {
		catByPlot[p.PlotNumber] = p.Category
	}
	if catByPlot["DEL1"] != "SourceDelete" {
		t.Fatalf("expected DEL1 category SourceDelete, got %q", catByPlot["DEL1"])
	}
	if catByPlot["CON1"] != "Conflict" {
		t.Fatalf("expected CON1 (delete vs modify) category Conflict, got %q", catByPlot["CON1"])
	}

	// Execute merge accepting DEL1 deletion (accept_source) and keeping CON1 (keep_target).
	var metaResolutions = map[string]string{}
	for _, m := range prev.MetadataItems {
		metaResolutions[m.ConflictID] = projectops.MergeResolutionAcceptSource
	}
	execRes, err := projectops.ExecuteThreeWayMerge(svc, ctx, cid, projectops.ThreeWayMergeExecuteRequest{
		SourcePath:                srcPath,
		BasePath:                  basePath,
		ExpectedPreviewDigest:     prev.PreviewDigest,
		DefaultConflictResolution: projectops.MergeResolutionKeepTarget,
		FieldResolutions:          metaResolutions,
		CaseInsensitiveText:       true,
	})
	if err != nil {
		t.Fatalf("ExecuteThreeWayMerge failed: %v", err)
	}
	if execRes.DeletedPlots != 1 {
		t.Fatalf("expected DeletedPlots=1, got %+v", execRes)
	}

	tdb, err := sqlutil.OpenReadOnly(tgtPath)
	if err != nil {
		t.Fatal(err)
	}
	defer tdb.Close()
	var delExists int
	_ = tdb.QueryRow(`SELECT COUNT(*) FROM TgtP_Env WHERE PlotNumber='DEL1'`).Scan(&delExists)
	if delExists != 0 {
		t.Fatalf("expected DEL1 deleted from TgtP_Env")
	}
	var auditCount int
	if err := tdb.QueryRow(`SELECT COUNT(*) FROM TgtP_Audit WHERE "Table"='_Env' AND EditField='PlotNumber' AND BeforeEdit='DEL1' AND PlotNumber IS NULL`).Scan(&auditCount); err != nil {
		t.Fatal(err)
	}
	if auditCount != 1 {
		t.Fatalf("expected 1 _Env delete audit row for DEL1 surviving ON DELETE CASCADE, got %d", auditCount)
	}
	var mapUnit, title string
	if err := tdb.QueryRow(`SELECT MapUnit FROM TgtP_Env WHERE PlotNumber='DUP1'`).Scan(&mapUnit); err != nil {
		t.Fatal(err)
	}
	if mapUnit != "Valid15MapUnitX" {
		t.Fatalf("expected exact 15-char MapUnit 'Valid15MapUnitX', got %q", mapUnit)
	}
	if err := tdb.QueryRow(`SELECT ProjectTitle FROM TgtP_Metadata WHERE ID=1`).Scan(&title); err != nil {
		t.Fatal(err)
	}
	if title != "Updated Source Title" {
		t.Fatalf("expected reconciled Metadata title 'Updated Source Title', got %q", title)
	}
}
