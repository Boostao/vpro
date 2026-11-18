package classification

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func w1FlatNodeIDs(t *testing.T, ctx context.Context, view *HierarchyExplorerView) map[int64]HierarchyExplorerNode {
	t.Helper()
	out := map[int64]HierarchyExplorerNode{}
	for _, node := range view.FlatNodes {
		out[node.ID] = node
	}
	return out
}

// UX-CLASS-001: a flat save must never silently delete or reparent nodes the
// flat rank table cannot represent (same-rank chains, "~X"/"X" twins).
func TestW1FlatSaveRefusesUnrepresentableHierarchyWithoutDeleting(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name: "QA_FlatLoss", Destination: "project", Activate: true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID
	add := func(name string, parent *int64, breakpoint bool) int64 {
		t.Helper()
		res, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: name, ParentID: parent, Level: 11, IsBreakpoint: breakpoint})
		if err != nil {
			t.Fatalf("AddHierarchyNode %s: %v", name, err)
		}
		return res.NodeID
	}
	add("DupUnit", nil, false)
	add("DupUnit", nil, true)
	parent := add("ParentUnit", nil, false)
	child := add("ChildUnit", int64PtrTest(parent), false)
	add("LeafUnit", int64PtrTest(child), false)

	before, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if before.Diagnostics.TotalNodes != 5 {
		t.Fatalf("fixture nodes = %d, want 5", before.Diagnostics.TotalNodes)
	}
	rows := append(append([]FlatHierarchyRow{}, before.FlatRankRows...), FlatHierarchyRow{SiteSeries: "HarmlessUnit"})
	if _, err := SaveFlatHierarchyRows(ctx, service, ctxID, SaveFlatHierarchyRequest{Rows: rows}); err == nil ||
		!strings.Contains(err.Error(), "Flat Rank Table") {
		t.Fatalf("unrepresentable flat save was not refused: %v", err)
	}
	after, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if after.Diagnostics.TotalNodes != 5 {
		t.Fatalf("refused flat save changed node count: %d", after.Diagnostics.TotalNodes)
	}
	beforeIDs, afterIDs := w1FlatNodeIDs(t, ctx, before), w1FlatNodeIDs(t, ctx, after)
	for id, node := range beforeIDs {
		got, ok := afterIDs[id]
		if !ok || got.Name != node.Name || (got.Parent == nil) != (node.Parent == nil) ||
			(got.Parent != nil && *got.Parent != *node.Parent) {
			t.Fatalf("node %d (%s) changed by refused flat save: %+v", id, node.Name, got)
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
	ids := w1FlatNodeIDs(t, ctx, after)
	for _, id := range []int64{super, class, sub} {
		if _, ok := ids[id]; !ok {
			t.Fatalf("existing node %d lost after flat save", id)
		}
	}
}
