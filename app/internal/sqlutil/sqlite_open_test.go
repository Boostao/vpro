package sqlutil

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestSqliteDSNBuildersEscapeSpecialPathCharacters(t *testing.T) {
	specialDir := t.TempDir()
	dbPath := filepath.Join(specialDir, "weird#name?50%.db")

	roDSN := SqliteReadOnlyDSN(dbPath)
	if !strings.Contains(roDSN, "mode=ro") || !strings.Contains(roDSN, "_foreign_keys=on") || !strings.Contains(roDSN, "_busy_timeout=5000") {
		t.Fatalf("unexpected read-only DSN: %s", roDSN)
	}
	if strings.Contains(strings.SplitN(roDSN, "?", 2)[0], "#") {
		t.Fatalf("raw '#' leaked into URI path before query string: %s", roDSN)
	}

	walDSN := SqliteWALCreateWriteDSN(dbPath)
	if !strings.Contains(walDSN, "mode=rwc") || !strings.Contains(walDSN, "_journal_mode=WAL") || !strings.Contains(walDSN, "_txlock=immediate") {
		t.Fatalf("unexpected WAL create DSN: %s", walDSN)
	}

	db, err := OpenWALCreateSQLite(dbPath)
	if err != nil {
		t.Fatalf("OpenWALCreateSQLite failed on special path: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TABLE t (id INTEGER PRIMARY KEY)`); err != nil {
		t.Fatalf("create table on special path failed: %v", err)
	}

	roDB, err := OpenQueryOnlySQLite(dbPath)
	if err != nil {
		t.Fatalf("OpenQueryOnlySQLite failed: %v", err)
	}
	defer roDB.Close()
	if _, err := roDB.Exec(`INSERT INTO t (id) VALUES (1)`); err == nil {
		t.Fatal("expected OpenQueryOnlySQLite to reject writes")
	}
}

func TestOpenStagedSQLiteOptions(t *testing.T) {
	stagedPath := filepath.Join(t.TempDir(), "export.db")
	dsn := SqliteStagedDSN(stagedPath, StagedSQLiteOptions{
		ForeignKeys:     true,
		ImmediateTxLock: true,
		BusyTimeoutMs:   5000,
	})
	for _, want := range []string{"mode=rw", "_foreign_keys=on", "_busy_timeout=5000", "_journal_mode=DELETE", "_synchronous=FULL", "_txlock=immediate"} {
		if !strings.Contains(dsn, want) {
			t.Fatalf("SqliteStagedDSN(%q) missing %q", dsn, want)
		}
	}

	fastDSN := SqliteStagedDSN(stagedPath, StagedSQLiteOptions{FastMemoryJournal: true})
	for _, want := range []string{"_foreign_keys=0", "_journal_mode=MEMORY", "_synchronous=OFF"} {
		if !strings.Contains(fastDSN, want) {
			t.Fatalf("fast SqliteStagedDSN(%q) missing %q", fastDSN, want)
		}
	}
}
