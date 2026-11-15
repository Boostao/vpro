package classification

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestBECUnitPickerMappingMaskAndAllMasterSiteUnits(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	bec := vprotest.BecFixture(t)

	// Verify all 6,067 MasterSiteUnitList codes parse Zone/SubZone and pass BECUnitMaskValid!
	vlistsDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(service.Projects.Sqlite.Attachments["VLists"], "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer vlistsDB.Close()
	rows, err := vlistsDB.Query(`SELECT CAST("SiteSeries" AS TEXT) FROM "MasterSiteUnitList" WHERE "SiteSeries" IS NOT NULL AND TRIM("SiteSeries") <> ''`)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			rows.Close()
			t.Fatal(err)
		}
		count++
		if !BECUnitMaskValid(code) {
			rows.Close()
			t.Fatalf("MasterSiteUnitList code %q failed BECUnitMaskValid", code)
		}
		z, sz := splitZoneSubZoneFromUnitCode(code)
		if z == "" || sz == "" {
			rows.Close()
			t.Fatalf("splitZoneSubZoneFromUnitCode(%q) = (%q, %q)", code, z, sz)
		}
	}
	rows.Close()
	if count < 6000 {
		t.Fatalf("expected ~6067 MasterSiteUnitList codes, got %d", count)
	}

	// Verify spaced code parsing examples explicitly
	for _, sample := range []struct {
		code, wantZ, wantSZ string
	}{
		{"CWH vm 1 /01", "CWH", "vm1"},
		{"CWH vh 3 /Wf51", "CWH", "vh3"},
		{"MH  mm 1 /03", "MH", "mm1"},
		{"ESSFdc 2 /05", "ESSF", "dc2"},
		{"BWBSmw   /102$6B.1", "BWBS", "mw"},
	} {
		if !BECUnitMaskValid(sample.code) {
			t.Fatalf("expected %q valid", sample.code)
		}
		z, sz := splitZoneSubZoneFromUnitCode(sample.code)
		if z != sample.wantZ || sz != sample.wantSZ {
			t.Fatalf("splitZoneSubZoneFromUnitCode(%q) = (%q, %q), want (%q, %q)", sample.code, z, sz, sample.wantZ, sample.wantSZ)
		}
	}

	// S3.1 + S3.2: Zone-only BECUnitPicker query returns active BECdb v13 units mapped from MergedBGC + Description
	cwhChoices, err := SearchBECUnitPicker(ctx, service, bec, state.ContextID, BECUnitPickerRequest{
		Zone:  "CWH",
		Query: "Blueberry",
		Limit: 25,
	})
	if err != nil || len(cwhChoices) == 0 {
		t.Fatalf("zone-only BECUnitPicker failed: len=%d err=%v", len(cwhChoices), err)
	}
	foundBEC := false
	for _, c := range cwhChoices {
		if c.Source == "becdb_v13" && strings.Contains(c.SiteSeries, "/") && c.MaskValid && c.LongName != "CWH vm 1" && c.LongName != "" {
			foundBEC = true
			break
		}
	}
	if !foundBEC {
		t.Fatalf("expected active becdb_v13 choice with MergedBGC / Code and Description LongName, got %+v", cwhChoices[:min(5, len(cwhChoices))])
	}
}

func TestPlotInspectorSummaryFloat32And99CapFallback(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	// Inject a test plot with NULL TotalA/TotalB and fallback sums > 99 + explicit TotalA=100
	_, err = db.Exec(`
		INSERT INTO Sample_Env(PlotNumber) VALUES('99901');
		INSERT INTO Sample_Veg(PlotNumber, Species, TotalA, Cover1, Cover2, Cover3, TotalB, Cover4, Cover5, Cover5a)
		VALUES ('99901', 'TSUGHET', NULL, 60, 50, 15, NULL, 70, 40, 10),
		       ('99901', 'THUJPLI', 100, 10, 10, NULL, NULL, 99.999996, 0, NULL);
		PRAGMA wal_checkpoint(PASSIVE)`)
	release()
	if err != nil {
		t.Fatal(err)
	}
	summary, err := GetPlotInspectorSummary(ctx, service, state.ContextID, "99901")
	if err != nil {
		t.Fatalf("GetPlotInspectorSummary failed: %v", err)
	}
	bySp := map[string]PlotInspectorSpecies{}
	for _, sp := range summary.TopSpecies {
		bySp[sp.Species] = sp
	}
	if bySp["TSUGHET"].CoverA != "99.0" || bySp["TSUGHET"].CoverB != "99.0" {
		t.Fatalf("expected capped 99.0 fallback A/B on TSUGHET, got A=%q B=%q", bySp["TSUGHET"].CoverA, bySp["TSUGHET"].CoverB)
	}
	if bySp["THUJPLI"].CoverA != "100.0" || bySp["THUJPLI"].CoverB != "99.0" {
		t.Fatalf("expected explicit TotalA 100.0 preserved & 99.999996 fallback B capped to 99.0, got A=%q B=%q", bySp["THUJPLI"].CoverA, bySp["THUJPLI"].CoverB)
	}
}

func TestSaveFlatHierarchyRowsPreservesLegacyColumnsAndSaveHierarchyAs(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name: "HierWave2", Destination: "project", Activate: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	ctxID := created.ContextID
	nClass, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: "ClassOne", Level: 2})
	if err != nil {
		t.Fatal(err)
	}
	nSeries, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: "CWHvm1/01", ParentID: &nClass.NodeID, Level: 11})
	if err != nil {
		t.Fatal(err)
	}

	// Set legacy columns on surviving rows in HierWave2_Hierarchy
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`
		UPDATE HierWave2_Hierarchy SET MyOrder='ord-1', ChildID=7, StartChild=10, LastChild=20, Flag=-1 WHERE ID = ?;
		UPDATE HierWave2_Hierarchy SET MyOrder='ord-2', ChildID=9, StartChild=30, LastChild=40, Flag=0 WHERE ID = ?;
		PRAGMA wal_checkpoint(PASSIVE)`, nClass.NodeID, nSeries.NodeID)
	release()
	if err != nil {
		t.Fatal(err)
	}

	// Sync via SaveFlatHierarchyRows: add CWHvm1/05 while keeping ClassOne & ~CWHvm1/01
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{
		Rows: []FlatHierarchyRow{
			{Class: "ClassOne", SiteSeries: "~CWHvm1/01"},
			{Class: "ClassOne", SiteSeries: "CWHvm1/05"},
		},
	}); err != nil {
		t.Fatalf("SaveFlatHierarchyRows failed: %v", err)
	}

	db, _, release, err = service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	var myOrder string
	var childID, startChild, lastChild, flag int64
	err = db.QueryRow(`SELECT MyOrder, ChildID, StartChild, LastChild, CAST(Flag AS INTEGER) FROM HierWave2_Hierarchy WHERE ID = ?`, nSeries.NodeID).
		Scan(&myOrder, &childID, &startChild, &lastChild, &flag)
	release()
	if err != nil {
		t.Fatal(err)
	}
	if myOrder != "ord-2" || childID != 9 || startChild != 30 || lastChild != 40 || flag != 0 {
		t.Fatalf("legacy columns overwritten by SaveFlatHierarchyRows: got (%q,%d,%d,%d,%d)", myOrder, childID, startChild, lastChild, flag)
	}

	// S3.9: SaveHierarchyTableAs into external file and verify cloned rows + legacy columns
	extHierPath := filepath.Join(t.TempDir(), "copied_hier.db")
	savedAs, err := SaveHierarchyTableAs(ctx, service, ctxID, SaveHierarchyTableAsRequest{
		NewName:     "HierCopy",
		Destination: "new_file",
		FilePath:    extHierPath,
		Activate:    true,
	})
	if err != nil || !savedAs.Activated || savedAs.TableName != "HierCopy_Hierarchy" {
		t.Fatalf("SaveHierarchyTableAs failed: %+v %v", savedAs, err)
	}
	extDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extHierPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer extDB.Close()
	var clonedOrder string
	if err := extDB.QueryRow(`SELECT MyOrder FROM HierCopy_Hierarchy WHERE ID = ?`, nClass.NodeID).Scan(&clonedOrder); err != nil || clonedOrder != "ord-1" {
		t.Fatalf("cloned hierarchy lost legacy MyOrder: %q err=%v", clonedOrder, err)
	}
}

func TestProjectProfilingStartWithAllPlotsLumpChoiceNoneAndEquality(t *testing.T) {
	ctx := context.Background()
	service, state, request := profileRunFixture(t)

	// Verify ListProjectPlotProfileLumpTables includes "None" + default "Sample_Lump"
	choices, err := ListProjectPlotProfileLumpTables(service, ctx, state.ContextID)
	if err != nil || len(choices) < 2 || choices[0].Table != "None" {
		t.Fatalf("unexpected lump choices: %+v err=%v", choices, err)
	}

	// Add a custom lump table + test Lump/Any/=/Add plots and StartWithAllPlots (Common plots on Step 1)
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`
		CREATE TABLE Custom_Lump(LumpCode TEXT, SppCode TEXT, "Use" BOOLEAN);
		INSERT INTO Custom_Lump VALUES('CUSTOM', 'TSUGHET', -1);
		UPDATE Sample_Profile SET "Operation"='Common plots' WHERE "Order"=(SELECT MIN("Order") FROM Sample_Profile);
		DELETE FROM Sample_Profile WHERE "Order" > (SELECT MIN("Order") FROM Sample_Profile);
		UPDATE Sample_Profile SET "Table"='Lump', Field='LumpCode', Operator='=', Layer='Any', Species='CUSTOM', Criteria='0', "Operation"='Common plots';
		PRAGMA wal_checkpoint(PASSIVE)`)
	release()
	if err != nil {
		t.Fatal(err)
	}

	review, err := ReviewProjectPlotProfile(service, ctx, state.ContextID)
	if err != nil {
		t.Fatal(err)
	}
	customLump, err := ReviewProjectPlotProfileLumpTable(service, ctx, state.ContextID, "Custom_Lump")
	if err != nil {
		t.Fatal(err)
	}

	// Without StartWithAllPlots, Step 1 Common plots starts empty -> 0 plots.
	resEmpty, err := RunProjectPlotProfile(service, ctx, state.ContextID, ProjectPlotProfileRunRequest{
		OriginalRules: review.Rules,
		ProjectLump:   &customLump,
		LumpTable:     "Custom_Lump",
	})
	if err != nil || len(resEmpty.PlotNumbers) != 0 {
		t.Fatalf("expected 0 plots without StartWithAllPlots, got %+v err=%v", resEmpty, err)
	}

	// With StartWithAllPlots=true + Lump/Any/=/Add or Common against all 52 plots + Subvarieties=true + LumpTable="None":
	resAll, err := RunProjectPlotProfile(service, ctx, state.ContextID, ProjectPlotProfileRunRequest{
		OriginalRules:     review.Rules,
		ProjectLump:       &customLump,
		LumpTable:         "Custom_Lump",
		StartWithAllPlots: true,
	})
	if err != nil || resAll.TotalPlots != 52 {
		t.Fatalf("StartWithAllPlots run failed: %+v err=%v", resAll, err)
	}

	// Subvarieties + LumpTable="None" also allowed cleanly without ProjectLump snapshot
	requestNone := ProjectPlotProfileRunRequest{
		OriginalRules: review.Rules,
		ProjectLump:   nil,
		Subvarieties:  true,
		LumpTable:     "None",
	}
	if _, err := RunProjectPlotProfile(service, ctx, state.ContextID, requestNone); err != nil {
		t.Fatalf("Subvarieties + LumpTable=None should succeed, got %v", err)
	}
	// None + Subvarieties=false with Lump rules should cleanly explain why it cannot run
	if _, err := RunProjectPlotProfile(service, ctx, state.ContextID, ProjectPlotProfileRunRequest{
		OriginalRules: review.Rules,
		LumpTable:     "None",
	}); err == nil {
		t.Fatal("expected Lump rules with LumpTable=None and Subvarieties=false to return explicit error")
	}
	_ = request
}

func TestEnvironmentSiteUnitTransferExternalWritableSU(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	extSUPath := filepath.Join(t.TempDir(), "external_writable_su.db")
	created, err := CreateSUTable(ctx, service, state.ContextID, CreateSUTableRequest{
		Name:                    "ExtWrite",
		Destination:             "new_file",
		FilePath:                extSUPath,
		PopulateAllProjectPlots: true,
		Activate:                true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateSUTable(new_file) failed: %+v %v", created, err)
	}

	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`UPDATE Sample_Admin SET UserSiteUnit='CWHvm1/01' WHERE Plot='108050'; PRAGMA wal_checkpoint(PASSIVE)`)
	release()
	if err != nil {
		t.Fatal(err)
	}

	review, err := ReviewEnvironmentSiteUnits(service, ctx, created.ContextID)
	if err != nil || len(review.Changes) == 0 {
		t.Fatalf("ReviewEnvironmentSiteUnits on writable external SU failed: len=%d err=%v", len(review.Changes), err)
	}
	res, err := TransferEnvironmentSiteUnits(service, ctx, created.ContextID, EnvironmentSiteUnitTransfer{
		Review: review, Confirmed: true,
	})
	if err != nil || res.ChangedRows == 0 {
		t.Fatalf("TransferEnvironmentSiteUnits to external SU failed: %+v err=%v", res, err)
	}

	extDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extSUPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer extDB.Close()
	var got string
	if err := extDB.QueryRow(`SELECT SiteUnit FROM ExtWrite_SU WHERE PlotNumber='108050'`).Scan(&got); err != nil || got != "CWHvm1/01" {
		t.Fatalf("external SU row was not updated: got %q err=%v", got, err)
	}

	// Ensure aliasing a protected support DB or master SU table is explicitly rejected!
	fakeCtx := &vprocore.SqliteContext{
		Selection: vprocore.DesktopSelection{Project: state.ActiveProject, ProjectPath: state.ProjectPath, SU: "Fake", SUPath: service.Projects.Sqlite.Attachments["VLists"]},
		Attachments: map[string]string{
			"project": service.Projects.Sqlite.Attachments["project"],
			"su":      service.Projects.Sqlite.Attachments["VLists"],
			"VLists":  service.Projects.Sqlite.Attachments["VLists"],
		},
		AttachmentInfo: map[string]os.FileInfo{
			"project": service.Projects.Sqlite.AttachmentInfo["project"],
			"su":      service.Projects.Sqlite.AttachmentInfo["VLists"],
			"VLists":  service.Projects.Sqlite.AttachmentInfo["VLists"],
		},
	}
	if err := ValidateWritableSiteUnitTransferOwner(fakeCtx); err == nil {
		t.Fatal("expected aliasing protected support DB VLists to fail ValidateWritableSiteUnitTransferOwner")
	}
	masterCtx := &vprocore.SqliteContext{
		Selection:      vprocore.DesktopSelection{Project: state.ActiveProject, ProjectPath: state.ProjectPath, SU: "Master", SUPath: extSUPath},
		Attachments:    service.Projects.Sqlite.Attachments,
		AttachmentInfo: service.Projects.Sqlite.AttachmentInfo,
	}
	if err := ValidateWritableSiteUnitTransferOwner(masterCtx); err == nil {
		t.Fatal("expected Master SU table write to fail ValidateWritableSiteUnitTransferOwner")
	}
}

func TestUserSiteUnitListCRUDAndCSVImportExport(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	initial, err := ListUserSiteUnitList(ctx, service, state.ContextID)
	if err != nil {
		t.Fatalf("ListUserSiteUnitList failed: %v", err)
	}
	lvl := int64(11)
	created, err := SaveUserSiteUnitEntry(ctx, service, state.ContextID, UpsertUserSiteUnitRequest{
		SiteSeries:               "USR01/01",
		SiteSeriesLongName:       "User Custom Series",
		SiteSeriesScientificName: "Tsuga heterophylla",
		Level:                    &lvl,
	})
	if err != nil || created.ID <= 0 || created.SiteSeries != "USR01/01" {
		t.Fatalf("SaveUserSiteUnitEntry create failed: %+v err=%v", created, err)
	}
	updated, err := SaveUserSiteUnitEntry(ctx, service, state.ContextID, UpsertUserSiteUnitRequest{
		ID:                       &created.ID,
		SiteSeries:               "USR01/01a",
		SiteSeriesLongName:       "User Custom Series Amended",
		SiteSeriesScientificName: "Tsuga heterophylla var.",
		Level:                    &lvl,
	})
	if err != nil || updated.ID != created.ID || updated.SiteSeries != "USR01/01a" {
		t.Fatalf("SaveUserSiteUnitEntry update failed: %+v err=%v", updated, err)
	}

	csvText, err := ExportUserSiteUnitListCSV(ctx, service, state.ContextID)
	if err != nil || !strings.Contains(csvText, "USR01/01a") {
		t.Fatalf("ExportUserSiteUnitListCSV failed: %v\n%s", err, csvText)
	}

	if err := DeleteUserSiteUnitEntry(ctx, service, state.ContextID, DeleteUserSiteUnitRequest{ID: created.ID}); err != nil {
		t.Fatalf("DeleteUserSiteUnitEntry failed: %v", err)
	}

	// Deleted ID must never be reused!
	recreated, err := SaveUserSiteUnitEntry(ctx, service, state.ContextID, UpsertUserSiteUnitRequest{
		SiteSeries: "USR02/01",
	})
	if err != nil || recreated.ID <= created.ID {
		t.Fatalf("deleted UserSiteUnitList ID %d was reused: %+v err=%v", created.ID, recreated, err)
	}

	importCSV := "SiteSeries,SiteSeriesLongName,SiteSeriesScientificName,Level\nUSR02/01,Overwritten,Abies amabilis,11\nUSR03/02,Imported,Picea sitchensis,11\n"
	impRes, err := ImportUserSiteUnitListCSV(ctx, service, state.ContextID, importCSV, true)
	if err != nil || impRes.Updated != 1 || impRes.Inserted != 1 {
		t.Fatalf("ImportUserSiteUnitListCSV failed: %+v err=%v", impRes, err)
	}
	after, err := ListUserSiteUnitList(ctx, service, state.ContextID)
	if err != nil || len(after) != len(initial)+2 {
		t.Fatalf("unexpected UserSiteUnitList count: got %d want %d err=%v", len(after), len(initial)+2, err)
	}
	var seriesNames []string
	for _, item := range after {
		seriesNames = append(seriesNames, item.SiteSeries)
	}
	if !slices.Contains(seriesNames, "USR03/02") || !reflect.DeepEqual(len(after), impRes.Total) {
		t.Fatalf("imported unit missing from UserSiteUnitList: %v", seriesNames)
	}
}
