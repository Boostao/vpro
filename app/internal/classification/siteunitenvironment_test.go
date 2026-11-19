package classification

import (
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

import (
	"database/sql"
	"errors"
	"reflect"
	"strings"
	"testing"
)

func reverseSiteUnitFixture() (vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable) {
	env, _, su := siteUnitTransferFixture()
	env.Columns = append(env.Columns, vprocore.ProjectMetadataColumn{Name: "Flag", DeclaredType: "BOOLEAN"})
	for i := range env.Rows {
		env.Rows[i].Cells = append(env.Rows[i].Cells, vprocore.ProjectMetadataCell{Storage: "null"})
	}
	admin := vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{
		{Name: "Plot"}, {Name: "UserSiteUnit"}, {Name: "SiteUnitShortName"}, {Name: "SiteUnitLongName"}},
		Rows: []vprocore.ProjectMetadataRow{
			{RowID: "1", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("P1"), vprotest.MetadataText("Old"), vprotest.MetadataText("Short"), vprotest.MetadataText("Long")}},
			{RowID: "2", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("P2"), vprotest.MetadataText("Old"), vprotest.MetadataText("Preserve short"), vprotest.MetadataText("Preserve long")}},
			{RowID: "3", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("P3"), vprotest.MetadataText("Old"), vprotest.MetadataText("Preserve short"), vprotest.MetadataText("Preserve long")}},
		}}
	su.Rows = su.Rows[:3]
	su.Rows[0].Cells[1] = vprotest.MetadataText("Unit")
	su.Rows[1].Cells[1] = vprotest.MetadataText("")
	su.Rows[2].Cells[1] = vprocore.ProjectMetadataCell{Storage: "null"}
	master := vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{{Name: "SiteSeries"}, {Name: "SiteSeriesLongName"}},
		Rows: []vprocore.ProjectMetadataRow{{RowID: "1", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("Unit"), vprotest.MetadataText("Master long")}}}}
	personal := vprocore.ProjectMetadataTable{Columns: master.Columns, Rows: []vprocore.ProjectMetadataRow{
		{RowID: "1", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("Unit"), vprotest.MetadataText("Personal long")}}}}
	return env, admin, su, master, personal
}

func TestSiteUnitEnvironmentPlanOriginalLinksPersonalPrecedenceAndMissingNames(t *testing.T) {
	env, admin, su, master, personal := reverseSiteUnitFixture()
	changes, err := planSiteUnitEnvironment(env, admin, su, master, personal)
	if err != nil || len(changes) != 5 {
		t.Fatal("original reverse assignments not planned", changes, err)
	}
	if changes[1].Field != "SiteUnitShortName" || *changes[1].After.Text != "Unit" ||
		*changes[2].After.Text != "Personal long" || changes[2].Origin != "personal override" ||
		changes[3].After.Storage != "text" || *changes[3].After.Text != "" || changes[4].After.Storage != "null" {
		t.Fatal("literal NULL/empty/personal precedence lost", changes)
	}
	*changes[2].After.Text = "Mutated"
	if *personal.Rows[0].Cells[1].Text != "Personal long" {
		t.Fatal("plan aliases reference observations")
	}
	personal.Rows = nil
	changes, err = planSiteUnitEnvironment(env, admin, su, master, personal)
	if err != nil || *changes[2].After.Text != "Master long" {
		t.Fatal("unique master fallback failed", err)
	}
	master.Rows = nil
	changes, err = planSiteUnitEnvironment(env, admin, su, master, personal)
	if err != nil || len(changes) != 3 {
		t.Fatal("unmatched names were guessed or cleared", err)
	}
}

func TestSiteUnitEnvironmentPlanRejectsAmbiguityLocksAndDestinationBounds(t *testing.T) {
	for _, variant := range []string{"master-duplicate-conflicting", "personal-duplicate-conflicting",
		"duplicate-malformed-cell", "su-duplicate", "admin-duplicate",
		"env-duplicate", "locked", "malformed-lock", "unit-length", "name-length", "nul"} {
		t.Run(variant, func(t *testing.T) {
			env, admin, su, master, personal := reverseSiteUnitFixture()
			duplicate := func(table *vprocore.ProjectMetadataTable) {
				row := table.Rows[0]
				row.Cells = append([]vprocore.ProjectMetadataCell(nil), row.Cells...)
				row.RowID = "99"
				table.Rows = append(table.Rows, row)
			}
			switch variant {
			case "master-duplicate-conflicting":
				personal.Rows = nil
				duplicate(&master)
				master.Rows[1].Cells[1] = vprotest.MetadataText("Conflicting master long")
			case "personal-duplicate-conflicting":
				duplicate(&personal)
				personal.Rows[1].Cells[1] = vprotest.MetadataText("Conflicting personal long")
			case "duplicate-malformed-cell":
				duplicate(&personal)
				personal.Rows[1].Cells[1] = vprocore.ProjectMetadataCell{Storage: "text"}
			case "su-duplicate":
				duplicate(&su)
			case "admin-duplicate":
				duplicate(&admin)
			case "env-duplicate":
				duplicate(&env)
			case "locked":
				env.Rows[0].Cells[1] = vprotest.MetadataInteger("-1")
			case "malformed-lock":
				env.Rows[0].Cells[1].Integer = vprotest.MetadataInteger("0").Integer
			case "unit-length":
				su.Rows[0].Cells[1] = vprotest.MetadataText(strings.Repeat("\U0001f332", 51))
			case "name-length":
				personal.Rows[0].Cells[1] = vprotest.MetadataText(strings.Repeat("x", 101))
			case "nul":
				su.Rows[0].Cells[1] = vprotest.MetadataText("Unit\x00")
			}
			_, err := planSiteUnitEnvironment(env, admin, su, master, personal)
			if err == nil {
				t.Fatal("unsafe reverse assignment accepted")
			}
			if variant == "master-duplicate-conflicting" && (!strings.Contains(err.Error(), `"Unit"`) || !strings.Contains(err.Error(), "MasterSiteUnitList")) {
				t.Fatalf("master conflict error should name SiteUnit and MasterSiteUnitList: %v", err)
			}
			if variant == "personal-duplicate-conflicting" && (!strings.Contains(err.Error(), `"Unit"`) || !strings.Contains(err.Error(), "UserSiteUnitList")) {
				t.Fatalf("personal conflict error should name SiteUnit and UserSiteUnitList: %v", err)
			}
		})
	}
}

func TestSiteUnitEnvironmentPersonalPrecedenceOverDuplicateMasterAndIdenticalDeduplication(t *testing.T) {
	t.Run("personal-override-beats-conflicting-master-duplicates", func(t *testing.T) {
		env, admin, su, master, personal := reverseSiteUnitFixture()
		su.Rows = su.Rows[:1]
		su.Rows[0].Cells[1] = vprotest.MetadataText("CWH vm 2 /11")
		master.Rows = []vprocore.ProjectMetadataRow{
			{RowID: "1", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("CWH vm 2 /11"), vprotest.MetadataText("CwSs - Skunk cabbage")}},
			{RowID: "2", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("CWH vm 2 /11"), vprotest.MetadataText("CwYc - Skunk cabbage")}},
		}
		personal.Rows = []vprocore.ProjectMetadataRow{
			{RowID: "10", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("CWH vm 2 /11"), vprotest.MetadataText("Personal Skunk cabbage")}},
		}
		changes, err := planSiteUnitEnvironment(env, admin, su, master, personal)
		if err != nil || len(changes) != 3 {
			t.Fatalf("expected personal override to resolve conflicting master rows: changes=%v err=%v", changes, err)
		}
		if changes[1].Origin != "personal override" || *changes[1].After.Text != "CWH vm 2 /11" ||
			changes[2].Origin != "personal override" || *changes[2].After.Text != "Personal Skunk cabbage" {
			t.Fatalf("unexpected resolved override values: %+v", changes)
		}
	})

	t.Run("identical-personal-duplicates-and-null-row-collapse", func(t *testing.T) {
		env, admin, su, master, personal := reverseSiteUnitFixture()
		su.Rows = su.Rows[:1]
		su.Rows[0].Cells[1] = vprotest.MetadataText("BWBSdk 2 /06")
		master.Rows = nil
		personal.Rows = []vprocore.ProjectMetadataRow{
			{RowID: "-794782529", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("BWBSdk 2 /06"), vprotest.MetadataText("Sw - Currant - Horsetail")}},
			{RowID: "-664311298", Cells: []vprocore.ProjectMetadataCell{{Storage: "null"}, {Storage: "null"}}},
			{RowID: "1604326505", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("BWBSdk 2 /06"), vprotest.MetadataText("Sw - Currant - Horsetail")}},
			{RowID: "1857678454", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("BWBSdk 2 /06"), vprotest.MetadataText("Sw - Currant - Horsetail")}},
		}
		changes, err := planSiteUnitEnvironment(env, admin, su, master, personal)
		if err != nil || len(changes) != 3 {
			t.Fatalf("expected identical personal duplicates to collapse cleanly: changes=%v err=%v", changes, err)
		}
		if changes[2].Origin != "personal override" || *changes[2].After.Text != "Sw - Currant - Horsetail" {
			t.Fatalf("unexpected collapsed personal definition: %+v", changes)
		}
	})

	t.Run("identical-master-duplicates-collapse", func(t *testing.T) {
		env, admin, su, master, personal := reverseSiteUnitFixture()
		su.Rows = su.Rows[:1]
		su.Rows[0].Cells[1] = vprotest.MetadataText("MH  wh 1 /01")
		personal.Rows = nil
		master.Rows = []vprocore.ProjectMetadataRow{
			{RowID: "818247919", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("MH  wh 1 /01"), vprotest.MetadataText("HmSs - Blueberry")}},
			{RowID: "964013926", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("MH  wh 1 /01"), vprotest.MetadataText("HmSs - Blueberry")}},
		}
		changes, err := planSiteUnitEnvironment(env, admin, su, master, personal)
		if err != nil || len(changes) != 3 {
			t.Fatalf("expected identical master duplicates to collapse cleanly: changes=%v err=%v", changes, err)
		}
		if changes[2].Origin != "master" || *changes[2].After.Text != "HmSs - Blueberry" {
			t.Fatalf("unexpected collapsed master definition: %+v", changes)
		}
	})
}

func TestSiteUnitEnvironmentSampleProjectEndToEnd(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	state, err := service.SwitchContext(state.ContextID, vprocore.ContextSelection{
		Project: state.ActiveProject, ProjectPath: state.ProjectPath,
		SU: "Sample", SUPath: state.ProjectPath,
		Hierarchy: state.ActiveHierarchy, HierarchyPath: state.HierarchyPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext to Sample SU: %v", err)
	}

	// 1. Default Sample project with unmodified Sample_SU + bundled VLists.db + VUser.db must open review cleanly.
	initialReview, err := ReviewSiteUnitEnvironment(service, t.Context(), state.ContextID)
	if err != nil {
		t.Fatalf("ReviewSiteUnitEnvironment failed on default Sample project: %v", err)
	}
	if initialReview.Project != "Sample" || initialReview.SU != "Sample" {
		t.Fatalf("unexpected review scope: project=%q su=%q", initialReview.Project, initialReview.SU)
	}

	// Verify deduplicated single-row VUser.db (matching runs/_seed/data/VUser.db) also opens review cleanly.
	vuserDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(service.Projects.Sqlite.Attachments["VUser"], "rw"))
	if err != nil {
		t.Fatal(err)
	}
	_, vuserCleanErr := vuserDB.Exec(`DELETE FROM "UserSiteUnitList" WHERE "ID" IN (-794782529, -664311298, 1857678454)`)
	if err := errors.Join(vuserCleanErr, vuserDB.Close()); err != nil {
		t.Fatal(err)
	}
	if _, err := ReviewSiteUnitEnvironment(service, t.Context(), state.ContextID); err != nil {
		t.Fatalf("ReviewSiteUnitEnvironment failed on Sample with deduplicated VUser.db: %v", err)
	}

	// 2. Stage Sample_SU updates covering:
	//    - Plot 412150 ('BWBSdk 2 /06' from VUser.db, with Admin cleared to verify transfer)
	//    - Plot 108050 ('MH  wh 1 /01' with duplicate identical rows in VLists.MasterSiteUnitList)
	//    - Plot 202050 ('CWH vm 2 /11' with conflicting rows in VLists.MasterSiteUnitList)
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw"))
	if err != nil {
		t.Fatal(err)
	}
	_, writeErr := db.Exec(`
		UPDATE Sample_Admin SET UserSiteUnit=NULL, SiteUnitShortName=NULL, SiteUnitLongName=NULL WHERE Plot='412150';
		UPDATE Sample_SU SET SiteUnit='MH  wh 1 /01' WHERE PlotNumber='108050';
		UPDATE Sample_SU SET SiteUnit='CWH vm 2 /11' WHERE PlotNumber='202050';
	`)
	if err := errors.Join(writeErr, db.Close()); err != nil {
		t.Fatal(err)
	}

	// Without a personal override for 'CWH vm 2 /11', review must fail naming 'CWH vm 2 /11' and 'MasterSiteUnitList'.
	if _, err := ReviewSiteUnitEnvironment(service, t.Context(), state.ContextID); err == nil ||
		!strings.Contains(err.Error(), "CWH vm 2 /11") || !strings.Contains(err.Error(), "MasterSiteUnitList") {
		t.Fatalf("expected conflicting master error naming CWH vm 2 /11 and MasterSiteUnitList, got: %v", err)
	}

	// Adding a single personal override in UserSiteUnitList resolves 'CWH vm 2 /11' cleanly.
	if _, err := SaveUserSiteUnitEntry(t.Context(), service, state.ContextID, UpsertUserSiteUnitRequest{
		SiteSeries:         "CWH vm 2 /11",
		SiteSeriesLongName: "CwYc - Skunk cabbage (Personal)",
	}); err != nil {
		t.Fatalf("SaveUserSiteUnitEntry failed: %v", err)
	}

	review, err := ReviewSiteUnitEnvironment(service, t.Context(), state.ContextID)
	if err != nil {
		t.Fatalf("ReviewSiteUnitEnvironment failed after personal override: %v", err)
	}
	if len(review.Changes) != 9 {
		t.Fatalf("expected 9 changed Admin cells across 3 plots, got %d: %+v", len(review.Changes), review.Changes)
	}

	res, err := TransferSiteUnitEnvironment(service, t.Context(), state.ContextID, SiteUnitEnvironmentTransfer{
		Review:    review,
		Confirmed: true,
	})
	if err != nil || res == nil || res.ChangedRows != 3 || res.ChangedCells != 9 {
		t.Fatalf("TransferSiteUnitEnvironment failed: res=%+v err=%v", res, err)
	}

	for _, want := range []struct{ plot, unit, longName string }{
		{"412150", "BWBSdk 2 /06", "Sw - Currant - Horsetail"},
		{"108050", "MH  wh 1 /01", "HmSs – Blueberry"},
		{"202050", "CWH vm 2 /11", "CwYc - Skunk cabbage (Personal)"},
	} {
		var gotUnit, gotShort, gotLong string
		if err := service.Projects.Sqlite.CoordinatorWhileLocked().QueryRowContext(t.Context(),
			`SELECT UserSiteUnit, SiteUnitShortName, SiteUnitLongName FROM project.Sample_Admin WHERE Plot=?`, want.plot).
			Scan(&gotUnit, &gotShort, &gotLong); err != nil {
			t.Fatalf("query Sample_Admin for plot %s: %v", want.plot, err)
		}
		if gotUnit != want.unit || gotShort != want.unit || gotLong != want.longName {
			t.Fatalf("plot %s Admin = (%q, %q, %q), want (%q, %q, %q)",
				want.plot, gotUnit, gotShort, gotLong, want.unit, want.unit, want.longName)
		}
	}
}

func TestSiteUnitEnvironmentPlanHistoricalOmissionAndExactUTF16Bounds(t *testing.T) {
	env, admin, su, master, personal := reverseSiteUnitFixture()
	value := strings.Repeat("\U0001f332", 50)
	su.Rows[0].Cells[1] = vprotest.MetadataText(value)
	changes, err := planSiteUnitEnvironment(env, admin, su, master, personal)
	if err != nil || *changes[0].After.Text != value {
		t.Fatal("exact100 UTF16 destination rejected", err)
	}
	historical := vprotest.MetadataText(strings.Repeat("x", 101))
	su.Rows[0].Cells[1], admin.Rows[0].Cells[1] = historical, vprocore.CloneSiteUnitCell(historical)
	changes, err = planSiteUnitEnvironment(env, admin, su, master, personal)
	if err != nil || len(changes) != 2 || !reflect.DeepEqual(su.Rows[0].Cells[1], historical) {
		t.Fatal("unchanged historical invalid unit rewritten", err)
	}
}
