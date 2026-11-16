package sqlutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func TestRemoveSQLiteWithSidecars(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "staged.db")
	for _, target := range []string{dbPath, dbPath + "-journal", dbPath + "-wal", dbPath + "-shm"} {
		if err := os.WriteFile(target, []byte("bytes"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := RemoveSQLiteWithSidecars(""); err != nil {
		t.Fatalf("empty path failed: %v", err)
	}
	if err := RemoveSQLiteWithSidecars(dbPath); err != nil {
		t.Fatalf("RemoveSQLiteWithSidecars failed: %v", err)
	}
	if err := RemoveSQLiteWithSidecars(dbPath); err != nil {
		t.Fatalf("idempotent RemoveSQLiteWithSidecars failed: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("expected 0 remaining files, got %v", entries)
	}
}

func TestBeginAndCommitStagedTxCancellationLeavesZeroSidecars(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "cancel.db")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	db, err := sql.Open("sqlite3", SqliteFileURI(dbPath, "rwc")+"&_journal_mode=DELETE&_synchronous=FULL")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)

	tx, err := BeginStagedTx(ctx, db)
	if err != nil {
		_ = db.Close()
		t.Fatal(err)
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE t (x TEXT); INSERT INTO t VALUES ('a');`); err != nil {
		_ = tx.Rollback()
		_ = db.Close()
		t.Fatal(err)
	}

	cancel()
	if err := CommitStagedTx(ctx, tx); !errors.Is(err, context.Canceled) {
		_ = db.Close()
		t.Fatalf("expected context.Canceled from CommitStagedTx, got %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	if err := RemoveSQLiteWithSidecars(dbPath); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("expected zero leftover files/journals after cancellation, got %v", entries)
	}
}

func TestInsertSURowsBatched(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "su.db")
	db, err := sql.Open("sqlite3", SqliteFileURI(dbPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	if _, err := db.Exec(`CREATE TABLE "Batch_SU" ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)`); err != nil {
		t.Fatal(err)
	}

	const totalRows = 950 // exercises 3 batches (400 + 400 + 150)
	seeds := make([]SURowSeed, totalRows)
	for i := range totalRows {
		plot := fmt.Sprintf("%05d", i)
		var unit *string
		if i%2 == 0 {
			u := fmt.Sprintf("CWHvm1/%02d", (i%9)+1)
			unit = &u
		}
		seeds[i] = SURowSeed{PlotNumber: plot, SiteUnit: unit, PlotNull: i == totalRows-1}
	}

	tx, err := BeginStagedTx(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	if err := InsertSURowsBatched(context.Background(), tx, `"Batch_SU"`, seeds); err != nil {
		_ = tx.Rollback()
		t.Fatal(err)
	}
	if err := CommitStagedTx(context.Background(), tx); err != nil {
		t.Fatal(err)
	}

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM "Batch_SU"`).Scan(&count); err != nil || count != totalRows {
		t.Fatalf("count = %d (err=%v), want %d", count, err, totalRows)
	}

	var plot0 string
	var unit0 sql.NullString
	if err := db.QueryRow(`SELECT "PlotNumber", "SiteUnit" FROM "Batch_SU" WHERE rowid = 1`).Scan(&plot0, &unit0); err != nil {
		t.Fatal(err)
	}
	if plot0 != "00000" || !unit0.Valid || unit0.String != "CWHvm1/01" {
		t.Fatalf("unexpected row 1: plot=%q unit=%+v", plot0, unit0)
	}

	var plot1 string
	var unit1 sql.NullString
	if err := db.QueryRow(`SELECT "PlotNumber", "SiteUnit" FROM "Batch_SU" WHERE rowid = 2`).Scan(&plot1, &unit1); err != nil {
		t.Fatal(err)
	}
	if plot1 != "00001" || unit1.Valid {
		t.Fatalf("unexpected row 2: plot=%q unit=%+v", plot1, unit1)
	}

	var plotLast sql.NullString
	if err := db.QueryRow(`SELECT "PlotNumber" FROM "Batch_SU" WHERE rowid = ?`, totalRows).Scan(&plotLast); err != nil {
		t.Fatal(err)
	}
	if plotLast.Valid {
		t.Fatalf("expected NULL PlotNumber for final row, got %q", plotLast.String)
	}
}

func TestGoSQLite3DSNQueryParametersSupported(t *testing.T) {
	supported := map[string]bool{
		"_auth":                     true,
		"_auth_crypt":               true,
		"_auth_pass":                true,
		"_auth_salt":                true,
		"_auth_user":                true,
		"_auto_vacuum":              true,
		"_busy_timeout":             true,
		"_cache_size":               true,
		"_case_sensitive_like":      true,
		"_cslike":                   true,
		"_defer_foreign_keys":       true,
		"_defer_fk":                 true,
		"_fk":                       true,
		"_foreign_keys":             true,
		"_ignore_check_constraints": true,
		"_journal":                  true,
		"_journal_mode":             true,
		"_loc":                      true,
		"_locking":                  true,
		"_locking_mode":             true,
		"_mutex":                    true,
		"_query_only":               true,
		"_recursive_triggers":       true,
		"_rt":                       true,
		"_secure_delete":            true,
		"_stmt_cache_size":          true,
		"_sync":                     true,
		"_synchronous":              true,
		"_timeout":                  true,
		"_txlock":                   true,
		"_vacuum":                   true,
		"_writable_schema":          true,
	}

	appRoot := filepath.Join("..", "..")
	dsnParamRe := regexp.MustCompile(`[?&](_[A-Za-z0-9_]+)=`)
	var unsupported []string

	err := filepath.WalkDir(appRoot, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "frontend", "build", "bin", "dist-artifacts":
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, m := range dsnParamRe.FindAllStringSubmatch(string(data), -1) {
			param := m[1]
			if !supported[param] {
				unsupported = append(unsupported, fmt.Sprintf("%s: %s", path, param))
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(unsupported) > 0 {
		t.Fatalf("unsupported go-sqlite3 DSN parameters (silently ignored by driver; use PRAGMA instead):\n  %s",
			strings.Join(unsupported, "\n  "))
	}
}
