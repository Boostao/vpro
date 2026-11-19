package classification

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func w1FlatNodeIDs(t *testing.T, view *HierarchyExplorerView) map[int64]HierarchyExplorerNode {
	t.Helper()
	out := map[int64]HierarchyExplorerNode{}
	for _, node := range view.FlatNodes {
		out[node.ID] = node
	}
	return out
}

func TestW1PhytosociologicalRanksIncludesSuperclassAndSubclass(t *testing.T) {
	want := []struct {
		key   string
		level int64
	}{
		{"Superclass", 1},
		{"Class", 2},
		{"Subclass", 3},
		{"Order", 4},
		{"SubOrder", 5},
		{"Alliance", 6},
		{"SubAlliance", 7},
		{"Association", 8},
		{"SubAssociation", 9},
		{"Facies", 10},
		{"WorkingUnit", 10},
		{"SiteSeries", 11},
	}
	if len(PhytosociologicalRanks) != len(want) {
		t.Fatalf("len(PhytosociologicalRanks) = %d, want %d", len(PhytosociologicalRanks), len(want))
	}
	for i, w := range want {
		got := PhytosociologicalRanks[i]
		if got.Key != w.key || got.Label != w.key || got.Level != w.level {
			t.Fatalf("PhytosociologicalRanks[%d] = %+v, want key/label=%q level=%d", i, got, w.key, w.level)
		}
	}
}

func TestW1TreeMutationsRejectBreakpointPrefixDuplicateTwins(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name: "QA_DupGuard", Destination: "project", Activate: true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID

	dupNode, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{
		Name: "DupUnit", Level: 11,
	})
	if err != nil {
		t.Fatalf("AddHierarchyNode(DupUnit): %v", err)
	}

	for _, attempt := range []HierarchyAddNodeRequest{
		{Name: "~DupUnit", Level: 11},
		{Name: "DupUnit", Level: 11, IsBreakpoint: true},
		{Name: " ~ dupunit ", Level: 2},
		{Name: "~~DupUnit", Level: 6},
	} {
		if _, err := AddHierarchyNode(ctx, service, ctxID, attempt); err == nil || !strings.Contains(err.Error(), "duplicate hierarchy node name") {
			t.Fatalf("expected AddHierarchyNode(%+v) to reject duplicate clean name, got %v", attempt, err)
		}
	}

	otherNode, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{
		Name: "DistinctUnit", Level: 11,
	})
	if err != nil {
		t.Fatalf("AddHierarchyNode(DistinctUnit): %v", err)
	}
	for _, badRename := range []string{"~DupUnit", "dupunit", "~~DUPUNIT"} {
		if _, err := RenameHierarchyNode(ctx, service, ctxID, HierarchyRenameNodeRequest{
			NodeID:  otherNode.NodeID,
			NewName: badRename,
		}); err == nil || !strings.Contains(err.Error(), "duplicate hierarchy node name") {
			t.Fatalf("expected RenameHierarchyNode(%q) to reject duplicate clean name, got %v", badRename, err)
		}
	}

	// Toggling ~ on DupUnit itself updates ID in place and must still succeed cleanly.
	toggled, err := ToggleHierarchyBreakpoint(ctx, service, ctxID, dupNode.NodeID)
	if err != nil || toggled.NodeName != "~DupUnit" {
		t.Fatalf("ToggleHierarchyBreakpoint on DupUnit failed: %+v %v", toggled, err)
	}
	if _, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{
		Name: "DupUnit", Level: 11,
	}); err == nil || !strings.Contains(err.Error(), "duplicate hierarchy node name") {
		t.Fatalf("expected non-~ DupUnit after toggle to ~DupUnit to be rejected, got %v", err)
	}
}

func TestW1RealSampleHierarchyFlatExplorerAndSavePreservesInvertedSubtree(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	before, err := GetHierarchyExplorer(ctx, service, state.ContextID)
	if err != nil {
		t.Fatalf("GetHierarchyExplorer(Sample_Hierarchy): %v", err)
	}
	if before.TableName != "Sample_Hierarchy" || before.Diagnostics.TotalNodes != 43 || len(before.FlatRankRows) != 11 {
		t.Fatalf("unexpected Sample_Hierarchy explorer view: table=%q nodes=%d flatRows=%d", before.TableName, before.Diagnostics.TotalNodes, len(before.FlatRankRows))
	}

	classARows := 0
	for i, r := range before.FlatRankRows {
		if r.Superclass != "Conifer Forests" {
			t.Fatalf("Sample_Hierarchy flat row %d Superclass = %q, want %q (row=%+v)", i, r.Superclass, "Conifer Forests", r)
		}
		if r.Class == "ClassA" {
			classARows++
			if r.Subclass != "SubClassA" || r.Order != "ORDER Tsugmer" || r.SubOrder != "SUBORDER Tsugmer-Coptasp" {
				t.Fatalf("Sample_Hierarchy ClassA row %d lost upper chain: %+v", i, r)
			}
		}
	}
	if classARows != 2 {
		t.Fatalf("Sample_Hierarchy ClassA rows = %d, want 2", classARows)
	}

	// Acceptance #1: adding Superclass="Conifer Forests", Class="ClassA", SiteSeries="QA_NEW_SERIES"
	// on freshly seeded Sample_Hierarchy succeeds and preserves inverted Level-1 node -2146566547 ("CDFmm/Rock bluff complex").
	addedRows := append(
		append([]FlatHierarchyRow{}, before.FlatRankRows...),
		FlatHierarchyRow{Superclass: "Conifer Forests", Class: "ClassA", SiteSeries: "QA_NEW_SERIES"},
		FlatHierarchyRow{Superclass: "Conifer Forests", Class: "ClassB", SiteSeries: "QA_NEW_B"},
	)
	saveRes, err := SaveFlatHierarchyRows(ctx, service, state.ContextID, SaveFlatHierarchyRequest{Rows: addedRows})
	if err != nil {
		t.Fatalf("SaveFlatHierarchyRows on Sample_Hierarchy failed: %v", err)
	}
	if saveRes.AffectedRows != 45 {
		t.Fatalf("SaveFlatHierarchyRows AffectedRows = %d, want 45", saveRes.AffectedRows)
	}

	after, err := GetHierarchyExplorer(ctx, service, state.ContextID)
	if err != nil {
		t.Fatalf("GetHierarchyExplorer after Sample_Hierarchy save: %v", err)
	}
	if after.Diagnostics.TotalNodes != 45 || len(after.FlatRankRows) != 13 {
		t.Fatalf("Sample_Hierarchy after save: nodes=%d flatRows=%d, want 45 and 13", after.Diagnostics.TotalNodes, len(after.FlatRankRows))
	}

	beforeIDs := w1FlatNodeIDs(t, before)
	afterIDs := w1FlatNodeIDs(t, after)
	for id, orig := range beforeIDs {
		got, ok := afterIDs[id]
		if !ok {
			t.Fatalf("original Sample_Hierarchy node %d (%q) lost after flat save", id, orig.Name)
		}
		if got.Name != orig.Name || !sameInt64Ptr(got.Parent, orig.Parent) || got.Level != orig.Level || got.Tag != orig.Tag {
			t.Fatalf("original Sample_Hierarchy node %d changed: got %+v, want %+v", id, got, orig)
		}
	}

	// Verify legacy columns (Tag='1', MyOrder='00032') on inverted node -2146566547 and Tag='1' on ClassA survived untouched.
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	var rockName, rockTag, rockOrder, classATag string
	var rockParent, rockLevel int64
	qErr := db.QueryRow(`SELECT Name, Parent, Level, COALESCE(Tag,''), COALESCE(MyOrder,'') FROM Sample_Hierarchy WHERE ID = -2146566547`).
		Scan(&rockName, &rockParent, &rockLevel, &rockTag, &rockOrder)
	qErr2 := db.QueryRow(`SELECT COALESCE(Tag,'') FROM Sample_Hierarchy WHERE ID = 1963243167`).Scan(&classATag)
	release()
	if qErr != nil || qErr2 != nil {
		t.Fatalf("query Sample_Hierarchy preserved metadata: %v / %v", qErr, qErr2)
	}
	if rockName != "CDFmm/Rock bluff complex" || rockParent != 248865285 || rockLevel != 1 || rockTag != "1" || rockOrder != "00032" || classATag != "1" {
		t.Fatalf("unexpected Sample_Hierarchy metadata: rock=(%q,%d,%d,%q,%q) classATag=%q", rockName, rockParent, rockLevel, rockTag, rockOrder, classATag)
	}

	// Second round-trip: adding a new SiteSeries under FaciesA (inside the CDFmm/Rock bluff complex subtree) also succeeds.
	var faciesARow FlatHierarchyRow
	for _, r := range after.FlatRankRows {
		if r.Facies == "FaciesA" {
			faciesARow = r
			break
		}
	}
	faciesARow.LeafID = 0
	faciesARow.SiteSeries = "MH  whp  /03"
	secondRows := append(append([]FlatHierarchyRow{}, after.FlatRankRows...), faciesARow)
	if _, err := SaveFlatHierarchyRows(ctx, service, state.ContextID, SaveFlatHierarchyRequest{Rows: secondRows}); err != nil {
		t.Fatalf("second SaveFlatHierarchyRows under FaciesA failed: %v", err)
	}

	// Genuinely lossy edit on Sample_Hierarchy: inserting an Alliance between SUBORDER Tsugmer-Coptasp
	// and SubAllianceA would bypass hidden node "CDFmm/Rock bluff complex" and must be refused cleanly.
	afterSecond, err := GetHierarchyExplorer(ctx, service, state.ContextID)
	if err != nil {
		t.Fatal(err)
	}
	lossyRows := append([]FlatHierarchyRow{}, afterSecond.FlatRankRows...)
	for i := range lossyRows {
		if lossyRows[i].SubAlliance == "SubAllianceA" {
			lossyRows[i].Alliance = "BypassAlliance"
		}
	}
	if _, err := SaveFlatHierarchyRows(ctx, service, state.ContextID, SaveFlatHierarchyRequest{Rows: lossyRows}); err == nil ||
		!strings.Contains(err.Error(), "Flat Rank Table") || !strings.Contains(err.Error(), "CDFmm/Rock bluff complex") {
		t.Fatalf("expected bypassing CDFmm/Rock bluff complex to be refused, got %v", err)
	}
}

// UX-CLASS-001: QA_FlatLoss deep same-rank chains preserve ParentUnit -> ChildUnit -> LeafUnit
// when adding unrelated rows, and refuse genuinely lossy edits or legacy twin-name tables without deleting.
func TestW1FlatSavePreservesSameRankChainsAndRefusesLossyOrTwinEdits(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name: "QA_FlatLoss", Destination: "project", Activate: true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID
	add := func(name string, parent *int64) int64 {
		t.Helper()
		res, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: name, ParentID: parent, Level: 11})
		if err != nil {
			t.Fatalf("AddHierarchyNode %s: %v", name, err)
		}
		return res.NodeID
	}
	dupID := add("DupUnit", nil)
	parentID := add("ParentUnit", nil)
	childID := add("ChildUnit", int64PtrTest(parentID))
	leafID := add("LeafUnit", int64PtrTest(childID))

	before, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if before.Diagnostics.TotalNodes != 4 || len(before.FlatRankRows) != 2 {
		t.Fatalf("QA_FlatLoss fixture: nodes=%d flatRows=%d, want 4 and 2", before.Diagnostics.TotalNodes, len(before.FlatRankRows))
	}

	// Adding HarmlessUnit in Flat Rank Table must preserve DupUnit + ParentUnit -> ChildUnit -> LeafUnit intact!
	addHarmless := append(append([]FlatHierarchyRow{}, before.FlatRankRows...), FlatHierarchyRow{SiteSeries: "HarmlessUnit"})
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: addHarmless}); err != nil {
		t.Fatalf("SaveFlatHierarchyRows(+HarmlessUnit) on QA_FlatLoss failed: %v", err)
	}
	afterAdd, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if afterAdd.Diagnostics.TotalNodes != 5 {
		t.Fatalf("nodes after +HarmlessUnit = %d, want 5", afterAdd.Diagnostics.TotalNodes)
	}
	afterIDs := w1FlatNodeIDs(t, afterAdd)
	if afterIDs[dupID].Parent != nil ||
		afterIDs[parentID].Parent != nil ||
		afterIDs[childID].Parent == nil || *afterIDs[childID].Parent != parentID ||
		afterIDs[leafID].Parent == nil || *afterIDs[leafID].Parent != childID {
		t.Fatalf("same-rank chain was altered by +HarmlessUnit: %+v", afterIDs)
	}

	// Genuinely lossy edit 1: removing LeafUnit row would orphan/drop hidden ParentUnit -> ChildUnit and must be refused.
	var withoutLeaf []FlatHierarchyRow
	for _, r := range afterAdd.FlatRankRows {
		if r.SiteSeries != "LeafUnit" {
			withoutLeaf = append(withoutLeaf, r)
		}
	}
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: withoutLeaf}); err == nil ||
		!strings.Contains(err.Error(), "Flat Rank Table") {
		t.Fatalf("expected deleting LeafUnit under hidden same-rank chain to be refused, got %v", err)
	}

	// Genuinely lossy edit 2: reparenting LeafUnit under a new Class in Flat Rank Table must be refused without mutating.
	reparentLeaf := append([]FlatHierarchyRow{}, afterAdd.FlatRankRows...)
	for i := range reparentLeaf {
		if reparentLeaf[i].SiteSeries == "LeafUnit" {
			reparentLeaf[i].Class = "NewClass"
		}
	}
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: reparentLeaf}); err == nil ||
		!strings.Contains(err.Error(), "Flat Rank Table") {
		t.Fatalf("expected reparenting LeafUnit across hidden same-rank chain to be refused, got %v", err)
	}

	// Legacy imported SQLite tables containing raw "~DupUnit"/"DupUnit" twins OR case-folded "DupUnit"/"dupunit" non-~ twins
	// must refuse flat-sync without deleting any rows.
	for _, tc := range []struct {
		hierName string
		twinA    string
		twinB    string
	}{
		{"QA_BreakTwins", "DupUnit", "~DupUnit"},
		{"QA_CaseTwins", "DupUnit", "dupunit"},
	} {
		twCreated, err := CreateHierarchyTable(ctx, service, ctxID, CreateHierarchyTableRequest{
			Name: tc.hierName, Destination: "project", Activate: true,
		})
		if err != nil || !twCreated.Activated {
			t.Fatalf("CreateHierarchyTable(%s): %+v %v", tc.hierName, twCreated, err)
		}
		ctxID = twCreated.ContextID
		db, _, release, err := service.Plots.GetActiveDB()
		if err != nil {
			t.Fatal(err)
		}
		_, execErr := db.Exec(
			`INSERT INTO `+tc.hierName+`_Hierarchy (ID, Name, Parent, Level) VALUES (1, ?, NULL, 11), (2, ?, NULL, 11); PRAGMA wal_checkpoint(PASSIVE)`,
			tc.twinA, tc.twinB,
		)
		release()
		if execErr != nil {
			t.Fatal(execErr)
		}

		twBefore, err := GetHierarchyExplorer(ctx, service, ctxID)
		if err != nil {
			t.Fatal(err)
		}
		twRows := append(append([]FlatHierarchyRow{}, twBefore.FlatRankRows...), FlatHierarchyRow{SiteSeries: "HarmlessUnit"})
		if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: twRows}); err == nil ||
			!strings.Contains(err.Error(), "Flat Rank Table") {
			t.Fatalf("%s: expected twin flat save to be refused, got %v", tc.hierName, err)
		}
		twAfter, err := GetHierarchyExplorer(ctx, service, ctxID)
		if err != nil {
			t.Fatal(err)
		}
		if twAfter.Diagnostics.TotalNodes != 2 {
			t.Fatalf("%s: refused flat save changed node count to %d", tc.hierName, twAfter.Diagnostics.TotalNodes)
		}
	}
}

// Superclass (1) and Subclass (3) round-trip through the flat table and new rows
// can be added under them without false parent conflicts or node loss.
func TestW1FlatSaveRoundTripsSuperclassAndSubclass(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name: "QA_Ranks", Destination: "project", Activate: true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID
	addAt := func(name string, parent *int64, level int64) int64 {
		t.Helper()
		res, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: name, ParentID: parent, Level: level})
		if err != nil {
			t.Fatalf("AddHierarchyNode %s: %v", name, err)
		}
		return res.NodeID
	}
	super := addAt("Conifer Forests", nil, 1)
	class := addAt("ClassA", int64PtrTest(super), 2)
	sub := addAt("SubclassA", int64PtrTest(class), 3)
	addAt("SS01", int64PtrTest(sub), 11)

	view, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil || len(view.FlatRankRows) != 1 {
		t.Fatalf("flat rows: %+v %v", view, err)
	}
	row := view.FlatRankRows[0]
	if row.Superclass != "Conifer Forests" || row.Class != "ClassA" || row.Subclass != "SubclassA" || row.SiteSeries != "SS01" {
		t.Fatalf("flat row lost Superclass/Subclass: %+v", row)
	}
	rows := []FlatHierarchyRow{row, {Superclass: "Conifer Forests", Class: "ClassA", SiteSeries: "QA_NEW_SERIES"}}
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: rows}); err != nil {
		t.Fatalf("flat save under existing Superclass/Class failed: %v", err)
	}
	after, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if after.Diagnostics.TotalNodes != 5 {
		t.Fatalf("nodes after flat add = %d, want 5", after.Diagnostics.TotalNodes)
	}
	ids := w1FlatNodeIDs(t, after)
	for _, id := range []int64{super, class, sub} {
		if _, ok := ids[id]; !ok {
			t.Fatalf("existing node %d lost after flat save", id)
		}
	}
}
