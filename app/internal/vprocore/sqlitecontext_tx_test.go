package vprocore_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSqliteContextEncapsulatedTransactionsAndAuditIdentity(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	owner := service.Projects.Sqlite
	if !owner.IsOpen() {
		t.Fatal("expected open SqliteContext")
	}

	// 1. WithReadSnapshotValue reads attached tables and rejects mutations.
	plotCount, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (int, error) {
		var n int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "project"."Sample_Env"`).Scan(&n); err != nil {
			return 0, err
		}
		if _, wErr := tx.ExecContext(ctx, `DELETE FROM "project"."Sample_Env"`); wErr == nil {
			return 0, errors.New("expected read-only snapshot to reject DELETE")
		}
		return n, nil
	})
	if err != nil {
		t.Fatalf("WithReadSnapshotValue: %v", err)
	}
	if plotCount < 1 {
		t.Fatalf("expected at least 1 plot in Sample_Env, got %d", plotCount)
	}

	// 2. WithImmediateWriteTx reuses pooled ProjectDB, normalizes Table in RecordAudit,
	// and rolls back atomically on error.
	var firstDB *sql.DB
	sentinelErr := errors.New("intentional rollback")
	err = owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		firstDB = owner.ProjectDB
		id, aErr := wtx.AllocateChildID(ctx, "Sample_Other")
		if aErr != nil {
			return aErr
		}
		if _, iErr := wtx.ExecContext(ctx, `INSERT INTO "Sample_Other" ("PlotNumber","ID","DataItem") VALUES ('108050', ?, 'ROLLBACK_ME')`, id); iErr != nil {
			return iErr
		}
		return sentinelErr
	})
	if !errors.Is(err, sentinelErr) {
		t.Fatalf("expected sentinelErr rollback, got %v", err)
	}

	rolledBackCount, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (int, error) {
		var n int
		err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "project"."Sample_Other" WHERE "DataItem" = 'ROLLBACK_ME'`).Scan(&n)
		return n, err
	})
	if err != nil || rolledBackCount != 0 {
		t.Fatalf("expected rolled-back insert count 0, got %d (err=%v)", rolledBackCount, err)
	}

	// 3. Successful WithImmediateWriteTx reuses the exact same pooled *sql.DB, allocates monotonic non-reused IDs,
	// and normalizes "Environment" -> "_Env" in <Project>_Audit.
	var alloc1, alloc2 int64
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		if firstDB != nil && owner.ProjectDB != firstDB {
			t.Fatalf("expected pooled ProjectDB reuse across WithImmediateWriteTx calls")
		}
		var aErr error
		alloc1, aErr = wtx.AllocateChildID(ctx, "Sample_Other")
		if aErr != nil {
			return aErr
		}
		if _, err := wtx.ExecContext(ctx, `INSERT INTO "Sample_Other" ("PlotNumber","ID","DataItem") VALUES ('108050', ?, 'FIRST')`, alloc1); err != nil {
			return err
		}
		if _, err := wtx.ExecContext(ctx, `DELETE FROM "Sample_Other" WHERE "ID" = ?`, alloc1); err != nil {
			return err
		}
		alloc2, aErr = wtx.AllocateChildID(ctx, "Sample_Other")
		if aErr != nil {
			return aErr
		}
		plot := "108050"
		_, err := wtx.RecordAudit(ctx, vprocore.AuditWriteEntry{
			User:       "Tester",
			PlotNumber: &plot,
			Table:      "Environment",
			EditField:  vprocore.AuditString("SiteNotes"),
			AfterEdit:  "canonical",
		})
		return err
	}); err != nil {
		t.Fatalf("WithImmediateWriteTx commit: %v", err)
	}
	if alloc2 <= alloc1 {
		t.Fatalf("expected monotonic child ID after delete (%d > %d)", alloc2, alloc1)
	}

	storedTable, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (string, error) {
		var tbl string
		err := tx.QueryRowContext(ctx,
			`SELECT "Table" FROM "project"."Sample_Audit" WHERE "User" = 'Tester' AND "EditField" = 'SiteNotes' ORDER BY rowid DESC LIMIT 1`,
		).Scan(&tbl)
		return tbl, err
	})
	if err != nil {
		t.Fatalf("read audit row: %v", err)
	}
	if storedTable != "_Env" {
		t.Fatalf("expected canonical Table '_Env', got %q", storedTable)
	}

	// 4. ContextState + OnContextSwitch invalidates Layer-2 ledgers automatically on SwitchContext.
	type testScopedLedger struct {
		entries map[string]string
	}
	ledger := vprocore.ContextState(service, func() *testScopedLedger {
		l := &testScopedLedger{entries: map[string]string{}}
		vprocore.OnContextSwitch(service, func() {
			l.entries = map[string]string{}
		})
		return l
	})
	ledger.entries[state.ContextID] = "cached-for-old-context"
	if got := vprocore.ContextState(service, func() *testScopedLedger { return &testScopedLedger{} }).entries[state.ContextID]; got != "cached-for-old-context" {
		t.Fatalf("expected ContextState hit before SwitchContext, got %q", got)
	}

	nextState, err := service.SwitchContext(state.ContextID, vprocore.ContextSelection{
		Project:     owner.Selection.Project,
		ProjectPath: owner.Selection.ProjectPath,
		SU:          "None",
		Hierarchy:   "None",
	})
	if err != nil {
		t.Fatalf("SwitchContext: %v", err)
	}
	if _, ok := ledger.entries[state.ContextID]; ok {
		t.Fatalf("expected old ContextID entry to be cleared on SwitchContext")
	}
	if _, ok := ledger.entries[nextState.ContextID]; ok {
		t.Fatalf("expected new ContextID to start empty after SwitchContext")
	}
}
