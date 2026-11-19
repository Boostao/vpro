package classification

import (
	"context"
	"slices"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestUXClass004DoubleTildeNormalizationAndToggle(t *testing.T) {
	for _, tc := range []struct {
		raw       string
		wantClean string
		wantBreak bool
	}{
		{"DoubleTilde", "DoubleTilde", false},
		{"~DoubleTilde", "DoubleTilde", true},
		{"~~DoubleTilde", "DoubleTilde", true},
		{"~~~DoubleTilde", "DoubleTilde", true},
		{"~ ~DoubleTilde", "DoubleTilde", true},
		{"  ~~  ~  DoubleTilde  ", "DoubleTilde", true},
		{"~", "", true},
		{"~~", "", true},
		{"~ ~", "", true},
		{"   ", "", false},
	} {
		gotClean, gotBreak := SplitBreakpointPrefix(tc.raw)
		if gotClean != tc.wantClean || gotBreak != tc.wantBreak {
			t.Fatalf("SplitBreakpointPrefix(%q) = (%q, %v), want (%q, %v)", tc.raw, gotClean, gotBreak, tc.wantClean, tc.wantBreak)
		}
	}

	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name:        "QA_DoubleTilde",
		Destination: "project",
		Activate:    true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID

	// Adding "~~DoubleTilde" (with or without IsBreakpoint) must store "~DoubleTilde".
	added, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{
		Name:  "~~DoubleTilde",
		Level: 11,
	})
	if err != nil {
		t.Fatalf("AddHierarchyNode(~~DoubleTilde): %v", err)
	}
	if added.NodeName != "~DoubleTilde" {
		t.Fatalf("AddHierarchyNode(~~DoubleTilde) NodeName = %q, want %q", added.NodeName, "~DoubleTilde")
	}

	addedSpaced, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{
		Name:         "~ ~SpacedBreak",
		Level:        8,
		IsBreakpoint: true,
	})
	if err != nil || addedSpaced.NodeName != "~SpacedBreak" {
		t.Fatalf("AddHierarchyNode(~ ~SpacedBreak) = %+v %v, want ~SpacedBreak", addedSpaced, err)
	}

	// Blank tilde-only names ("~~", "~ ~") must be rejected on Add and Rename.
	for _, blank := range []string{"~", "~~", "~~~", "~ ~"} {
		if _, err := AddHierarchyNode(ctx, service, ctxID, HierarchyAddNodeRequest{Name: blank, Level: 11}); err == nil {
			t.Fatalf("expected AddHierarchyNode(%q) to fail", blank)
		}
		if _, err := RenameHierarchyNode(ctx, service, ctxID, HierarchyRenameNodeRequest{NodeID: added.NodeID, NewName: blank}); err == nil {
			t.Fatalf("expected RenameHierarchyNode(%q) to fail", blank)
		}
	}

	// Toggling ~ Break once on "~DoubleTilde" must remove the breakpoint cleanly -> "DoubleTilde".
	toggledOff, err := ToggleHierarchyBreakpoint(ctx, service, ctxID, added.NodeID)
	if err != nil || toggledOff.NodeName != "DoubleTilde" {
		t.Fatalf("ToggleHierarchyBreakpoint off = %+v %v, want DoubleTilde", toggledOff, err)
	}

	// Renaming to "~~~TripleRename" normalizes to "~TripleRename".
	renamed, err := RenameHierarchyNode(ctx, service, ctxID, HierarchyRenameNodeRequest{
		NodeID:  added.NodeID,
		NewName: "~~~TripleRename",
	})
	if err != nil || renamed.NodeName != "~TripleRename" {
		t.Fatalf("RenameHierarchyNode(~~~TripleRename) = %+v %v, want ~TripleRename", renamed, err)
	}

	// Legacy imported row with raw "~~LegacyDouble" toggles off in a single click to "LegacyDouble".
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, execErr := db.Exec(`INSERT INTO QA_DoubleTilde_Hierarchy (ID, Name, Parent, Level) VALUES (900, '~~LegacyDouble', NULL, 6); PRAGMA wal_checkpoint(PASSIVE)`)
	release()
	if execErr != nil {
		t.Fatal(execErr)
	}
	legacyToggled, err := ToggleHierarchyBreakpoint(ctx, service, ctxID, 900)
	if err != nil || legacyToggled.NodeName != "LegacyDouble" {
		t.Fatalf("ToggleHierarchyBreakpoint on legacy ~~ row = %+v %v, want LegacyDouble", legacyToggled, err)
	}
}

func collectTreeIDs(nodes []HierarchyExplorerNode) []int64 {
	var ids []int64
	var walk func(list []HierarchyExplorerNode)
	walk = func(list []HierarchyExplorerNode) {
		for _, n := range list {
			ids = append(ids, n.ID)
			walk(n.Children)
		}
	}
	walk(nodes)
	return ids
}

func TestUXClass005SurfacesExistingCyclesAndAllowsTreeRepair(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name:        "QA_CycleHier",
		Destination: "project",
		Activate:    true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable(QA_CycleHier): %+v %v", created, err)
	}
	ctxID := created.ContextID

	// Seed legacy/imported cycle topology from UX-CLASS-005 plus a tail child under CycleB:
	//   1 ('CycleA', Parent=2, Level=2) <-> 2 ('CycleB', Parent=1, Level=4) <- 6 ('CycleTail', Parent=2, Level=11)
	//   3 ('SelfCycle', Parent=3, Level=6)
	//   4 ('ValidRoot', Parent=NULL, Level=2) <- 5 ('ValidLeaf', Parent=4, Level=11)
	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, seedErr := db.Exec(`
		INSERT INTO QA_CycleHier_Hierarchy (ID, Name, Parent, Level, Tag) VALUES
			(1, 'CycleA', 2, 2, NULL),
			(2, 'CycleB', 1, 4, NULL),
			(3, 'SelfCycle', 3, 6, NULL),
			(4, 'ValidRoot', NULL, 2, NULL),
			(5, 'ValidLeaf', 4, 11, NULL),
			(6, 'CycleTail', 2, 11, NULL);
		PRAGMA wal_checkpoint(PASSIVE);
	`)
	release()
	if seedErr != nil {
		t.Fatalf("seed QA_CycleHier_Hierarchy: %v", seedErr)
	}

	view, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatalf("GetHierarchyExplorer(QA_CycleHier): %v", err)
	}
	if view.Diagnostics.TotalNodes != 6 {
		t.Fatalf("TotalNodes = %d, want 6", view.Diagnostics.TotalNodes)
	}
	if !slices.Equal(view.Diagnostics.CycleNodeIDs, []int64{1, 2, 3}) {
		t.Fatalf("CycleNodeIDs = %v, want [1 2 3]", view.Diagnostics.CycleNodeIDs)
	}
	if len(view.FlatNodes) != 6 {
		t.Fatalf("len(FlatNodes) = %d, want all 6 nodes surfaced (got %+v)", len(view.FlatNodes), view.FlatNodes)
	}
	treeIDs := collectTreeIDs(view.Roots)
	slices.Sort(treeIDs)
	if !slices.Equal(treeIDs, []int64{1, 2, 3, 4, 5, 6}) {
		t.Fatalf("tree reachable IDs = %v, want [1 2 3 4 5 6]", treeIDs)
	}

	// Introducing a new cycle or keeping a reparented node inside a cycle must still be rejected.
	for _, badReparent := range []HierarchyReparentNodeRequest{
		{NodeID: 4, NewParentID: int64PtrTest(5)}, // ValidRoot under ValidLeaf (new cycle)
		{NodeID: 4, NewParentID: int64PtrTest(3)}, // ValidRoot under SelfCycle
		{NodeID: 1, NewParentID: int64PtrTest(2)}, // CycleA kept under CycleB
		{NodeID: 1, NewParentID: int64PtrTest(6)}, // CycleA under its descendant CycleTail
		{NodeID: 1, NewParentID: int64PtrTest(3)}, // CycleA under SelfCycle
	} {
		if _, err := ReparentHierarchyNode(ctx, service, ctxID, badReparent); err == nil || !strings.Contains(err.Error(), "cycle") {
			t.Fatalf("expected ReparentHierarchyNode(%+v) to reject cycle, got %v", badReparent, err)
		}
	}

	// Toggling ~ Break on unrelated ValidRoot succeeds without being blocked by pre-existing cycles.
	if _, err := ToggleHierarchyBreakpoint(ctx, service, ctxID, 4); err != nil {
		t.Fatalf("ToggleHierarchyBreakpoint on ValidRoot while cycles exist failed: %v", err)
	}

	// Step 1 repair: reparent CycleA (1) to Root (nil) while SelfCycle (3) still exists!
	if _, err := ReparentHierarchyNode(ctx, service, ctxID, HierarchyReparentNodeRequest{
		NodeID:      1,
		NewParentID: nil,
	}); err != nil {
		t.Fatalf("ReparentHierarchyNode(CycleA -> Root) failed: %v", err)
	}
	afterStep1, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(afterStep1.Diagnostics.CycleNodeIDs, []int64{3}) {
		t.Fatalf("CycleNodeIDs after CycleA -> Root = %v, want [3]", afterStep1.Diagnostics.CycleNodeIDs)
	}

	// Step 2 repair: delete SelfCycle (3) -> Cycles drops to 0!
	if _, err := DeleteHierarchyNode(ctx, service, ctxID, HierarchyDeleteNodeRequest{
		NodeID:          3,
		CascadeChildren: false,
	}); err != nil {
		t.Fatalf("DeleteHierarchyNode(SelfCycle) failed: %v", err)
	}
	afterStep2, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if len(afterStep2.Diagnostics.CycleNodeIDs) != 0 || afterStep2.Diagnostics.TotalNodes != 5 {
		t.Fatalf("expected 0 cycles and 5 nodes after full repair, got %+v", afterStep2.Diagnostics)
	}
}

func TestUXClass005DeleteAndPromoteKidsBreaksCyclesWithoutOrphaning(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	created, err := CreateHierarchyTable(ctx, service, state.ContextID, CreateHierarchyTableRequest{
		Name:        "QA_CyclePromote",
		Destination: "project",
		Activate:    true,
	})
	if err != nil || !created.Activated {
		t.Fatalf("CreateHierarchyTable: %+v %v", created, err)
	}
	ctxID := created.ContextID

	db, _, release, err := service.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	// 1 <-> 2 (2-cycle) and 3 -> 3 with child 7 -> 3 (self-cycle with child)
	_, seedErr := db.Exec(`
		INSERT INTO QA_CyclePromote_Hierarchy (ID, Name, Parent, Level) VALUES
			(1, 'CycleA', 2, 2),
			(2, 'CycleB', 1, 4),
			(3, 'SelfCycle', 3, 6),
			(7, 'ChildOfSelf', 3, 11);
		PRAGMA wal_checkpoint(PASSIVE);
	`)
	release()
	if seedErr != nil {
		t.Fatal(seedErr)
	}

	// Delete & Promote Kids on CycleA (1): CycleB (2) must be promoted to Root (NULL), not self-parented (2->2)!
	if _, err := DeleteHierarchyNode(ctx, service, ctxID, HierarchyDeleteNodeRequest{
		NodeID:          1,
		CascadeChildren: false,
	}); err != nil {
		t.Fatalf("DeleteHierarchyNode(CycleA, promote): %v", err)
	}

	// Delete & Promote Kids on SelfCycle (3): ChildOfSelf (7) must be promoted to Root (NULL), not orphaned (7->3)!
	if _, err := DeleteHierarchyNode(ctx, service, ctxID, HierarchyDeleteNodeRequest{
		NodeID:          3,
		CascadeChildren: false,
	}); err != nil {
		t.Fatalf("DeleteHierarchyNode(SelfCycle, promote): %v", err)
	}

	repaired, err := GetHierarchyExplorer(ctx, service, ctxID)
	if err != nil {
		t.Fatal(err)
	}
	if len(repaired.Diagnostics.CycleNodeIDs) != 0 || len(repaired.Diagnostics.OrphanNodes) != 0 || repaired.Diagnostics.TotalNodes != 2 {
		t.Fatalf("expected 0 cycles, 0 orphans, and 2 surviving nodes, got %+v", repaired.Diagnostics)
	}
	byID := w1FlatNodeIDs(t, repaired)
	if byID[2].Parent != nil || byID[7].Parent != nil {
		t.Fatalf("expected CycleB (2) and ChildOfSelf (7) to be promoted to Root, got 2=%+v 7=%+v", byID[2], byID[7])
	}
}
