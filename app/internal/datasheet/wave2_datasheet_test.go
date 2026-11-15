package datasheet

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestDatasheetProtectedColumnsAuditMetadataReadOnlyAndChildLifecycle(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, SiteSeries, Elevation, Flag) VALUES ('DS002', 'CWH', 'vm1', '01', 420, 0);
		INSERT INTO Sample_Admin (Plot, HumusThickness, StrataCoverTotal, UserSiteUnit) VALUES ('DS002', 8.5, 65.0, 'CWHvm1/01');
		INSERT INTO Sample_Audit (Project, User, PlotNumber, "Table", EditField, EditWhen, BeforeEdit, AfterEdit, Restore, Flag)
			VALUES ('Sample', 'Admin', 'DS002', '_Env', 'Zone', '2026-01-01 00:00:00', 'ICH', 'CWH', 0, 0);
	`)

	// S2.1: HumusThickness & StrataCoverTotal must be Editable=false & Protected=true, and rejected by edit & find/replace.
	admPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Admin",
		Filters:  []DatasheetFilterSpec{{Column: "Plot", Op: "eq", Value: "DS002"}},
	})
	if err != nil {
		t.Fatalf("GetDatasheetPage(Admin): %v", err)
	}
	if admPage.ReadOnly {
		t.Fatal("expected Admin page ReadOnly=false")
	}
	for _, colName := range []string{"HumusThickness", "StrataCoverTotal"} {
		idx := findColIdx(admPage.Columns, colName)
		if idx < 0 {
			t.Fatalf("missing Admin column %s", colName)
		}
		meta := admPage.Columns[idx]
		if meta.Editable || !meta.Protected {
			t.Fatalf("expected Admin.%s editable=false protected=true, got editable=%v protected=%v", colName, meta.Editable, meta.Protected)
		}
		if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
			TableKey: "Admin",
			Edits:    []DatasheetCellEdit{{RowID: admPage.Rows[0].RowID, Column: colName, Before: admPage.Rows[0].Cells[idx], After: realCell(12.0)}},
		}); err == nil {
			t.Fatalf("expected ApplyDatasheetEdits to reject protected Admin.%s", colName)
		}
		if _, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
			TableKey: "Admin", Column: colName, FindText: "8.5", ReplaceText: "9.5",
		}); err == nil {
			t.Fatalf("expected PreviewDatasheetFindReplace to reject protected Admin.%s", colName)
		}
	}

	// S2.7: ListDatasheetAllTables + ReadOnly _Audit & _Metadata views.
	allTables, err := ListDatasheetAllTables(ctx, service, state.ContextID)
	if err != nil || len(allTables) != 11 {
		t.Fatalf("expected 11 tables in ListDatasheetAllTables, got %d err=%v", len(allTables), err)
	}
	for _, key := range []string{"Audit", "Metadata"} {
		page, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{TableKey: key})
		if err != nil {
			t.Fatalf("GetDatasheetPage(%s): %v", key, err)
		}
		if !page.ReadOnly {
			t.Fatalf("expected %s page ReadOnly=true", key)
		}
		for _, col := range page.Columns {
			if col.Editable || !col.Protected {
				t.Fatalf("expected %s.%s Editable=false Protected=true", key, col.Name)
			}
		}
		if len(page.Rows) > 0 {
			if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
				TableKey: key,
				Edits:    []DatasheetCellEdit{{RowID: page.Rows[0].RowID, Column: page.Columns[0].Name, Before: page.Rows[0].Cells[0], After: textCell("X")}},
			}); err == nil || !strings.Contains(err.Error(), "read-only") {
				t.Fatalf("expected ApplyDatasheetEdits(%s) to reject read-only table, got %v", key, err)
			}
			if _, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
				TableKey: key, Column: page.Columns[0].Name, FindText: "S", ReplaceText: "X",
			}); err == nil || !strings.Contains(err.Error(), "read-only") {
				t.Fatalf("expected PreviewDatasheetFindReplace(%s) to reject read-only table, got %v", key, err)
			}
		}
	}

	// S2.8: Child row insert/delete with monotonic __VPRO_ChildIdentity reservation and <P>_Audit logging.
	ins, err := InsertDatasheetChildRow(ctx, service, state.ContextID, DatasheetInsertChildRowRequest{
		TableKey:   "Veg",
		PlotNumber: "DS002",
		Cells: map[string]vprocore.ProjectMetadataCell{
			"Species": textCell("PSEUMEN"),
			"Layer":   textCell("A"),
			"Cover1":  realCell(25.0),
		},
	})
	if err != nil || ins.ID <= 0 || ins.AuditRows == 0 {
		t.Fatalf("InsertDatasheetChildRow(Veg) failed: %+v err=%v", ins, err)
	}
	delRes, err := DeleteDatasheetChildRow(ctx, service, state.ContextID, DatasheetDeleteChildRowRequest{
		TableKey:           "Veg",
		RowID:              ins.RowID,
		ExpectedPlotNumber: "DS002",
		ExpectedID:         &ins.ID,
	})
	if err != nil || delRes.DeletedID != ins.ID || delRes.AuditRows == 0 {
		t.Fatalf("DeleteDatasheetChildRow(Veg) failed: %+v err=%v", delRes, err)
	}
	ins2, err := InsertDatasheetChildRow(ctx, service, state.ContextID, DatasheetInsertChildRowRequest{
		TableKey:   "Veg",
		PlotNumber: "DS002",
		Cells: map[string]vprocore.ProjectMetadataCell{
			"Species": textCell("TSUGHET"),
			"Cover2":  realCell(10.0),
		},
	})
	if err != nil || ins2.ID == ins.ID {
		t.Fatalf("expected non-reused monotonic ID != %d, got %+v err=%v", ins.ID, ins2, err)
	}
}

func TestDatasheetFindReplacePreviewRowLockLMH25AndHierarchyCycle(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	sel := vprotest.ContextSelection(state)
	sel.Hierarchy = "Sample"
	sel.HierarchyPath = state.ProjectPath
	state, err := service.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatalf("SwitchContext: %v", err)
	}

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Flag) VALUES ('DSLOCK', 'CWH', 'vm1', -1);
		INSERT INTO Sample_Env (PlotNumber, Zone, SubZone, Flag) VALUES ('DSOPEN', 'CWH', 'vm1', 0);
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(8101, 'DSOPEN', 'Lv', 8.0, 4.0, 0),
			(8102, 'DSOPEN', 'Oh', 10.0, 30.0, 0);
		DELETE FROM Sample_Hierarchy;
		INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level, Tag, MyOrder, Flag) VALUES
			(1, 'Root', NULL, 1, 'R', '01', 0),
			(2, 'Child', 1, 2, 'C', '02', 0);
	`)

	// 1. Plot lock check in Find/Replace preview: DSLOCK invalid, DSOPEN valid.
	lockPreview, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Env",
		Column:      "Zone",
		FindText:    "CWH",
		ReplaceText: "ICH",
		ExactCell:   true,
		Filters:     []DatasheetFilterSpec{{Column: "PlotNumber", Op: "starts_with", Value: "DS"}},
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Env lock): %v", err)
	}
	if lockPreview.MatchedRows != 2 || lockPreview.InvalidCount != 1 || lockPreview.ValidCount != 1 {
		t.Fatalf("expected 1 locked invalid + 1 valid preview row, got %+v", lockPreview)
	}
	foundLockErr := false
	for _, it := range lockPreview.Items {
		if it.PinnedIdentity == "DSLOCK" && strings.Contains(it.ValidationError, "locked") {
			foundLockErr = true
		}
	}
	if !foundLockErr {
		t.Fatalf("expected DSLOCK preview item to carry lock ValidationError, got %+v", lockPreview.Items)
	}

	// 2. LMH25 depth-sign check in Find/Replace preview: raising Lv LowerDepth from 4 to 9 violates UpperDepth > LowerDepth.
	humPreview, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Humus",
		Column:      "LowerDepth",
		FindText:    "4",
		ReplaceText: "9",
		ExactCell:   true,
		Filters:     []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSOPEN"}},
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Humus depth): %v", err)
	}
	if humPreview.MatchedRows != 1 || humPreview.InvalidCount != 1 || !strings.Contains(humPreview.Items[0].ValidationError, "UpperDepth > LowerDepth") {
		t.Fatalf("expected LMH25 depth violation in Find/Replace preview, got %+v", humPreview)
	}

	// 3. Hierarchy cycle check in Find/Replace preview: setting Parent of Root (ID=1, Parent=NULL) to 2 creates cycle 1->2->1.
	hierPreview, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Hierarchy",
		Column:      "Parent",
		FindText:    "",
		ReplaceText: "2",
		ExactCell:   true,
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Hierarchy cycle): %v", err)
	}
	if hierPreview.MatchedRows != 1 || hierPreview.InvalidCount != 1 || !strings.Contains(strings.ToLower(hierPreview.Items[0].ValidationError), "cycle") {
		t.Fatalf("expected Hierarchy cycle error in Find/Replace preview, got %+v", hierPreview)
	}
}

func TestDatasheetHumusDefaultSortingUplandUpwardAndWetlandDownward(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		DELETE FROM Sample_Humus;
		INSERT INTO Sample_Env (PlotNumber, Zone) VALUES ('HUMUP', 'CWH'), ('HUMWET', 'CWH');
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Flag) VALUES
			(9001, 'HUMUP', 'H', 3.0, 0.0, 0),
			(9002, 'HUMUP', 'Lv', 12.0, 8.0, 0),
			(9003, 'HUMUP', 'Fm', 8.0, 3.0, 0),
			(9004, 'HUMWET', 'Oh', 45.0, 90.0, 0),
			(9005, 'HUMWET', 'Of', 0.0, 15.0, 0),
			(9006, 'HUMWET', '2Om', 15.0, 45.0, 0);
	`)

	// Upland L/F/H must sort UpperDepth DESC (Lv 12 -> Fm 8 -> H 3).
	upPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Humus",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "HUMUP"}},
	})
	if err != nil || len(upPage.Rows) != 3 {
		t.Fatalf("GetDatasheetPage(Humus upland): rows=%d err=%v", len(upPage.Rows), err)
	}
	hIdx := findColIdx(upPage.Columns, "Horizon")
	var gotUp []string
	for _, r := range upPage.Rows {
		gotUp = append(gotUp, *r.Cells[hIdx].Text)
	}
	if strings.Join(gotUp, ",") != "Lv,Fm,H" {
		t.Fatalf("expected upland Humus sort [Lv,Fm,H], got %v", gotUp)
	}

	// Wetland Of/Om/Oh must sort UpperDepth ASC (Of 0 -> 2Om 15 -> Oh 45).
	wetPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Humus",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "HUMWET"}},
	})
	if err != nil || len(wetPage.Rows) != 3 {
		t.Fatalf("GetDatasheetPage(Humus wetland): rows=%d err=%v", len(wetPage.Rows), err)
	}
	var gotWet []string
	for _, r := range wetPage.Rows {
		gotWet = append(gotWet, *r.Cells[hIdx].Text)
	}
	if strings.Join(gotWet, ",") != "Of,2Om,Oh" {
		t.Fatalf("expected wetland Humus sort [Of,2Om,Oh], got %v", gotWet)
	}
}
