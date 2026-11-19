package projectops

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

func TestAllocateSafeChildIDWithoutAuditAndNoDoubleQuote(t *testing.T) {
	ctx := context.Background()
	dbPath := filepath.Join(t.TempDir(), "MiniProj.db")
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rwc")+"&_txlock=immediate")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	if _, err := db.ExecContext(ctx, `
		CREATE TABLE "MiniProj_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT);
		INSERT INTO "MiniProj_Veg" ("ID", "PlotNumber", "Species") VALUES (1, '00001', 'PSEUMEN');
	`); err != nil {
		t.Fatal(err)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()

	if err := ensureChildIdentityTable(ctx, tx); err != nil {
		t.Fatal(err)
	}
	// Passing an already-quoted table name must not double-quote ""MiniProj_Veg""
	if err := reserveChildID(ctx, tx, `"MiniProj_Veg"`, 2); err != nil {
		t.Fatalf("reserveChildID: %v", err)
	}

	// MiniProj_Audit does not exist; allocateSafeChildID must still succeed and skip 1 & 2 -> 3.
	nextID, err := allocateSafeChildID(ctx, tx, "MiniProj", "Veg")
	if err != nil {
		t.Fatalf("allocateSafeChildID without _Audit failed: %v", err)
	}
	if nextID != 3 {
		t.Fatalf("allocateSafeChildID = %d, want 3", nextID)
	}

	var doubleQuoted int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE "ChildTable" LIKE '""%'`).Scan(&doubleQuoted); err != nil {
		t.Fatal(err)
	}
	if doubleQuoted != 0 {
		t.Fatalf("expected 0 double-quoted ChildTable entries, got %d", doubleQuoted)
	}
}
