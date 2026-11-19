package vprocore_test

import (
	"context"
	"database/sql"
	"errors"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestW2ChildPatchesDefaultConfigAndAuditStrengthMatrix(t *testing.T) {
	// 1. Default PlotService / ContextService configuration (AuditStrength == 3 without SetAuditStrength).
	svc, state := vprotest.ContextServiceFixture(t)
	if svc.Plots.AuditStrength != 3 {
		t.Fatalf("default ContextService.Plots.AuditStrength = %d, want 3", svc.Plots.AuditStrength)
	}
	standalone := vprocore.NewPlotService(nil)
	if standalone.AuditStrength != 3 {
		t.Fatalf("NewPlotService(nil).AuditStrength = %d, want 3", standalone.AuditStrength)
	}
	if err := standalone.SetAuditStrength(1); err != nil || standalone.AuditStrength != 1 {
		t.Fatalf("SetAuditStrength on nil-Projects PlotService failed: %v", err)
	}
	if err := standalone.SetCurrentUser("Tester"); err != nil || standalone.CurrentUser != "Tester" {
		t.Fatalf("SetCurrentUser on nil-Projects PlotService failed: %v", err)
	}

	// Seed a Veg row on 00337 with LL = NULL, mimicking UX-VEG-002 Repro step 4.
	var vegID int
	err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		if err := plots.SaveVegRecord(vprocore.VegRecord{PlotNumber: "00337", Species: "ABIEAMA"}); err != nil {
			return err
		}
		records, err := plots.ListVegRecords("00337")
		if err != nil {
			return err
		}
		for _, r := range records {
			if r.Species == "ABIEAMA" {
				vegID = int(r.ID)
			}
		}
		return nil
	})
	if err != nil || vegID <= 0 {
		t.Fatalf("seed ABIEAMA on 00337 failed: vegID=%d, err=%v", vegID, err)
	}

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	countLLAudits := func() (int, sql.NullString, sql.NullString) {
		t.Helper()
		var cnt int
		var before, after sql.NullString
		if err := db.QueryRow(
			`SELECT COUNT(*) FROM Sample_Audit WHERE PlotNumber='00337' AND "Table"='_Veg' AND ID=? AND EditField='LL'`,
			vegID,
		).Scan(&cnt); err != nil {
			t.Fatal(err)
		}
		if cnt > 0 {
			if err := db.QueryRow(
				`SELECT BeforeEdit, AfterEdit FROM Sample_Audit WHERE PlotNumber='00337' AND "Table"='_Veg' AND ID=? AND EditField='LL' ORDER BY rowid DESC LIMIT 1`,
				vegID,
			).Scan(&before, &after); err != nil {
				t.Fatal(err)
			}
		}
		return cnt, before, after
	}

	// NULL -> 1 under default config (AuditStrength == 3).
	if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		return plots.UpdateChildPatches("00337", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			ID:   vegID,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: nil, Value: 1, Scalar: reflect.Int},
			},
		}})
	}); err != nil {
		t.Fatalf("UpdateChildPatches NULL -> 1 failed: %v", err)
	}
	cnt, before, after := countLLAudits()
	if cnt != 1 || before.Valid || !after.Valid || after.String != "1" {
		t.Fatalf("NULL -> 1 audit = cnt:%d before:%+v after:%+v; want cnt:1 NULL->'1'", cnt, before, after)
	}

	// 1 -> 2 under default config.
	if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		return plots.UpdateChildPatches("00337", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			ID:   vegID,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: 1, Value: 2, Scalar: reflect.Int},
			},
		}})
	}); err != nil {
		t.Fatalf("UpdateChildPatches 1 -> 2 failed: %v", err)
	}
	cnt, before, after = countLLAudits()
	if cnt != 2 || before.String != "1" || after.String != "2" {
		t.Fatalf("1 -> 2 audit = cnt:%d before:%+v after:%+v; want cnt:2 '1'->'2'", cnt, before, after)
	}

	// 2 -> NULL under default config.
	if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		return plots.UpdateChildPatches("00337", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			ID:   vegID,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: 2, Value: nil, Scalar: reflect.Int},
			},
		}})
	}); err != nil {
		t.Fatalf("UpdateChildPatches 2 -> NULL failed: %v", err)
	}
	cnt, before, after = countLLAudits()
	if cnt != 3 || before.String != "2" || after.Valid {
		t.Fatalf("2 -> NULL audit = cnt:%d before:%+v after:%+v; want cnt:3 '2'->NULL", cnt, before, after)
	}

	// 2. Explicit AuditStrength matrix (0, 1, 2, 3) across NULL->val, val->val, val->NULL.
	expectedCounts := map[int][3]int{
		0: {0, 0, 0},
		1: {0, 1, 1}, // NULL->1 (0), 1->2 (+1=1), 2->NULL (+0=1)
		2: {1, 2, 2}, // NULL->1 (+1=1), 1->2 (+1=2), 2->NULL (+0=2)
		3: {1, 2, 3}, // NULL->1 (+1=1), 1->2 (+1=2), 2->NULL (+1=3)
	}
	for _, strength := range []int{0, 1, 2, 3} {
		t.Run("strength_"+strconv.Itoa(strength), func(t *testing.T) {
			childSvc, childDB := vprotest.ChildFixture(t)
			if err := childSvc.SetAuditStrength(strength); err != nil {
				t.Fatal(err)
			}
			if _, err := childDB.Exec(`INSERT INTO Sample_Veg(PlotNumber, Species, ID, LL) VALUES ('CHILD1', 'ABIEAMA', 77, NULL)`); err != nil {
				t.Fatal(err)
			}
			transitions := []struct {
				exp, val any
			}{
				{nil, 1},
				{1, 2},
				{2, nil},
			}
			for step, tr := range transitions {
				if err := childSvc.UpdateChildPatches("CHILD1", []vprocore.ChildRecordPatch{{
					Kind: "Veg",
					ID:   77,
					Cells: map[string]vprocore.ChildExpectedValue{
						"ll": {Expected: tr.exp, Value: tr.val, Scalar: reflect.Int},
					},
				}}); err != nil {
					t.Fatalf("strength=%d step=%d error: %v", strength, step, err)
				}
				got := vprotest.AuditCount(t, childDB, "CHILD1")
				want := expectedCounts[strength][step]
				if got != want {
					t.Fatalf("strength=%d step=%d AuditCount = %d, want %d", strength, step, got, want)
				}
			}
		})
	}
}

func TestW2UpdateChildPlotPatchesAcquiresBeginImmediateAndHonorsContext(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	var vegID int
	if err := svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		if err := plots.SaveVegRecord(vprocore.VegRecord{PlotNumber: "00337", Species: "TSUGHET"}); err != nil {
			return err
		}
		records, err := plots.ListVegRecords("00337")
		if err != nil {
			return err
		}
		for _, r := range records {
			if r.Species == "TSUGHET" {
				vegID = int(r.ID)
			}
		}
		return nil
	}); err != nil || vegID <= 0 {
		t.Fatalf("seed TSUGHET failed: vegID=%d, err=%v", vegID, err)
	}

	// Proof 1: Inside Validate (before any UPDATE statement runs), a second connection
	// attempting BEGIN IMMEDIATE with a 1ms busy_timeout MUST fail with SQLITE_BUSY
	// ("database is locked"). Under a deferred BEGIN, SQLite WAL allows a second
	// connection to BEGIN IMMEDIATE until the first connection executes UPDATE/INSERT.
	probeDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw")+"&_busy_timeout=1")
	if err != nil {
		t.Fatal(err)
	}
	defer probeDB.Close()

	validateCalled := false
	err = svc.Edit(state.ContextID, func(plots *vprocore.PlotService) error {
		return plots.UpdateChildPatches("00337", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			ID:   vegID,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: nil, Value: 5, Scalar: reflect.Int},
			},
			Validate: func(_ *sql.Tx, _, _ string) error {
				validateCalled = true
				probeConn, cErr := probeDB.Conn(ctx)
				if cErr != nil {
					return cErr
				}
				defer probeConn.Close()
				_, lockErr := probeConn.ExecContext(ctx, "BEGIN IMMEDIATE")
				if lockErr == nil {
					_, _ = probeConn.ExecContext(ctx, "ROLLBACK")
					return errors.New("expected BEGIN IMMEDIATE lock to already be held before UPDATE, but probe succeeded")
				}
				if !strings.Contains(strings.ToLower(lockErr.Error()), "locked") && !strings.Contains(strings.ToLower(lockErr.Error()), "busy") {
					return lockErr
				}
				return nil
			},
		}})
	})
	if err != nil || !validateCalled {
		t.Fatalf("UpdateChildPatches BEGIN IMMEDIATE verification failed: validateCalled=%v, err=%v", validateCalled, err)
	}

	// Verify the write lock and pooled connection were cleanly released after Commit.
	probeConn, err := probeDB.Conn(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := probeConn.ExecContext(ctx, "BEGIN IMMEDIATE"); err != nil {
		probeConn.Close()
		t.Fatalf("write lock remained held after UpdateChildPatches commit: %v", err)
	}

	// Proof 2: While probeConn holds BEGIN IMMEDIATE, UpdateChildPatches under a short
	// timeout aborts cleanly at BeginImmediateActiveTx with context.DeadlineExceeded
	// without invoking Validate or mutating Sample_Veg / Sample_Audit.
	shortCtx, cancel := context.WithTimeout(ctx, 60*time.Millisecond)
	defer cancel()
	contendedValidateCalled := false
	_, contendedErr := vprocore.WithContextPlotRequest(shortCtx, svc, state.ContextID, func(plots *vprocore.PlotService) (struct{}, error) {
		return struct{}{}, plots.UpdateChildPatches("00337", []vprocore.ChildRecordPatch{{
			Kind: "Veg",
			ID:   vegID,
			Cells: map[string]vprocore.ChildExpectedValue{
				"ll": {Expected: 5, Value: 9, Scalar: reflect.Int},
			},
			Validate: func(_ *sql.Tx, _, _ string) error {
				contendedValidateCalled = true
				return nil
			},
		}})
	})
	_, _ = probeConn.ExecContext(ctx, "ROLLBACK")
	probeConn.Close()

	if !errors.Is(contendedErr, context.DeadlineExceeded) || contendedValidateCalled {
		t.Fatalf("contended UpdateChildPatches = %v (validateCalled=%v), want context.DeadlineExceeded and false", contendedErr, contendedValidateCalled)
	}
}
