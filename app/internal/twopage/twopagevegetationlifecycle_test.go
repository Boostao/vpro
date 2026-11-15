package twopage

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestTwoPageVegetationCreateDeleteRestoreAndNegativeCoverBounds(t *testing.T) {
	contexts, state, db := vprotest.TwoPageSoilReadFixture(t, false, "TEXT")
	if err := contexts.Plots.SetAuditStrength(3); err != nil {
		t.Fatal(err)
	}
	svc, err := NewTwoPageVegetationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()

	// 1. Reject negative and >=100 cover on creation, plus unsupported Cover5a in SubVegAXL_BC.
	neg, c1, tooHigh := -0.5, 15.0, 100.0
	if _, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		PlotNumber: "108050", Form: "SubVegAXL_BC", Species: "PSEUMEN",
		Covers: map[string]*float64{"Cover1": &neg},
	}); err == nil {
		t.Fatal("expected CreateRow to reject negative cover")
	}
	if _, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		PlotNumber: "108050", Form: "SubVegAXL_BC", Species: "PSEUMEN",
		Covers: map[string]*float64{"Cover1": &tooHigh},
	}); err == nil {
		t.Fatal("expected CreateRow to reject >= 100 cover")
	}
	if _, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		PlotNumber: "108050", Form: "SubVegAXL_BC", Species: "PSEUMEN",
		Covers: map[string]*float64{"Cover5a": &c1},
	}); err == nil {
		t.Fatal("expected SubVegAXL_BC CreateRow to reject Cover5a")
	}

	// 2. Valid create + replay idempotency.
	reqID := "11111111-2222-4333-8444-555555555501"
	layer := "1"
	created, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		RequestID:  reqID,
		PlotNumber: "108050",
		Form:       "SubVegAXL",
		Species:    "PSEUMEN",
		Layer:      &layer,
		Covers:     map[string]*float64{"Cover1": &c1},
	})
	if err != nil || created.ID <= 0 || !created.ReservedInLedger || created.AuditRowCount == 0 || created.Replayed {
		t.Fatalf("CreateRow failed: %+v err=%v", created, err)
	}
	replayed, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		RequestID:  reqID,
		PlotNumber: "108050",
		Form:       "SubVegAXL",
		Species:    "PSEUMEN",
		Layer:      &layer,
		Covers:     map[string]*float64{"Cover1": &c1},
	})
	if err != nil || !replayed.Replayed || replayed.ID != created.ID {
		t.Fatalf("CreateRow replay failed: %+v err=%v", replayed, err)
	}

	// 3. Delete created row, inspect deleted list, and verify monotonic ID reservation.
	delReqID := "11111111-2222-4333-8444-555555555502"
	deleted, err := svc.DeleteRow(ctx, state.ContextID, DeleteTwoPageVegetationRequest{
		RequestID:  delReqID,
		PlotNumber: "108050",
		Form:       "SubVegAXL",
		ID:         created.ID,
		RowID:      created.RowID,
	})
	if err != nil || deleted.DeletedID != created.ID || !deleted.ReservedInLedger || deleted.AuditRowCount == 0 {
		t.Fatalf("DeleteRow failed: %+v err=%v", deleted, err)
	}

	deletedEntries, err := svc.ListDeletedRows(ctx, state.ContextID, "108050", "SubVegAXL")
	if err != nil || len(deletedEntries) != 1 || deletedEntries[0].Restored || deletedEntries[0].Species != "PSEUMEN" {
		t.Fatalf("ListDeletedRows unexpected: %+v err=%v", deletedEntries, err)
	}

	// Verify next allocation never reuses deleted ID even while row is gone.
	created2, err := svc.CreateRow(ctx, state.ContextID, CreateTwoPageVegetationRequest{
		RequestID:  "11111111-2222-4333-8444-555555555503",
		PlotNumber: "108050",
		Form:       "SubVegAXL",
		Species:    "TSUGHET",
		Covers:     map[string]*float64{"Cover2": &c1},
	})
	if err != nil || created2.ID == created.ID {
		t.Fatalf("expected new monotonic ID distinct from %d, got %+v err=%v", created.ID, created2, err)
	}

	// 4. Restore deleted row and verify row count and Restored=true.
	restored, err := svc.RestoreRow(ctx, state.ContextID, RestoreTwoPageVegetationRequest{
		RequestID:       "11111111-2222-4333-8444-555555555504",
		PlotNumber:      "108050",
		Form:            "SubVegAXL",
		DeleteRequestID: delReqID,
	})
	if err != nil || restored.RestoredID != created.ID || restored.AuditRowCount == 0 {
		t.Fatalf("RestoreRow failed: %+v err=%v", restored, err)
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Veg WHERE PlotNumber = '108050' AND ID = ?`, created.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("restored row missing: count=%d err=%v", count, err)
	}
	afterList, err := svc.ListDeletedRows(ctx, state.ContextID, "108050", "SubVegAXL")
	if err != nil || len(afterList) != 1 || !afterList[0].Restored {
		t.Fatalf("expected Restored=true after RestoreRow, got %+v err=%v", afterList, err)
	}
}

func TestTwoPageSourceAuditRestoreSelectionAndExecution(t *testing.T) {
	service, state, db := sourceAuditFixture(t, false, "TEXT")
	ctx := context.Background()

	// Seed parent plot field & matching audit row for Plot 108050.
	if _, err := db.Exec(`UPDATE Sample_Env SET SiteNotes = 'new note' WHERE PlotNumber = '108050';
		INSERT INTO Sample_Audit VALUES ('Sample','Will','108050','_Env','SiteNotes','2026-01-01 00:00:00','old note','new note',0,0,NULL);`); err != nil {
		t.Fatal(err)
	}
	orig, err := service.GetOriginal(ctx, state.ContextID, "108050", "FS882-8x6XL")
	if err != nil || len(orig.Records.Rows) != 1 {
		t.Fatalf("GetOriginal: %+v err=%v", orig, err)
	}
	rowID := orig.Records.Rows[0].RowID

	// Reject unsupported form / empty plot.
	if err := service.SetRestoreSelection(ctx, state.ContextID, "108050", "UnknownForm", []string{rowID}); err == nil || !strings.Contains(err.Error(), "does not support") {
		t.Fatalf("expected unsupported form error, got %v", err)
	}
	if err := service.SetRestoreSelection(ctx, state.ContextID, "108050", "FS882-8x6XL", []string{rowID}); err != nil {
		t.Fatalf("SetRestoreSelection: %v", err)
	}
	res, err := service.RestoreSelected(ctx, state.ContextID, "108050", "FS882-8x6XL", []string{rowID}, vprocore.AuditRestorePrune)
	if err != nil || res.RestoredRows != 1 || res.PrunedAuditRows != 1 {
		t.Fatalf("RestoreSelected: %+v err=%v", res, err)
	}
	var note string
	if err := db.QueryRow(`SELECT SiteNotes FROM Sample_Env WHERE PlotNumber = '108050'`).Scan(&note); err != nil || note != "old note" {
		t.Fatalf("expected restored SiteNotes='old note', got %q err=%v", note, err)
	}
}
