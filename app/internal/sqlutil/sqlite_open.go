package sqlutil

import (
	"database/sql"
	"strconv"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

const DefaultSQLiteBusyTimeoutMs = 5000

// StagedSQLiteOptions configures isolated temporary/export SQLite files opened via OpenStagedSQLite.
type StagedSQLiteOptions struct {
	ForeignKeys       bool
	ImmediateTxLock   bool
	BusyTimeoutMs     int
	FastMemoryJournal bool
}

// SqliteReadOnlyDSN builds a canonical read-only SQLite file URI with foreign keys and busy timeout.
func SqliteReadOnlyDSN(path string) string {
	return SqliteFileURI(path, "ro") + "&_foreign_keys=on&_busy_timeout=5000"
}

// SqliteQueryOnlyDSN builds a canonical read-only SQLite file URI with _query_only=on and busy timeout.
func SqliteQueryOnlyDSN(path string) string {
	return SqliteFileURI(path, "ro") + "&_query_only=on&_busy_timeout=5000"
}

// SqliteImmediateWriteDSN builds a canonical read-write SQLite file URI with foreign keys, busy timeout, and immediate transaction lock.
func SqliteImmediateWriteDSN(path string) string {
	return SqliteFileURI(path, "rw") + "&_foreign_keys=on&_busy_timeout=5000&_txlock=immediate"
}

// SqliteImmediateLockDSN builds a read-write SQLite file URI with busy timeout and immediate transaction lock (without changing journal mode).
func SqliteImmediateLockDSN(path string) string {
	return SqliteFileURI(path, "rw") + "&_busy_timeout=5000&_txlock=immediate"
}

// SqliteWALWriteDSN builds the canonical WAL read-write SQLite file URI for VPro project databases.
func SqliteWALWriteDSN(path string) string {
	return SqliteFileURI(path, "rw") + "&_foreign_keys=on&_busy_timeout=5000&_journal_mode=WAL&_txlock=immediate"
}

// SqliteWALCreateWriteDSN builds a canonical WAL create-or-open read-write SQLite file URI.
func SqliteWALCreateWriteDSN(path string) string {
	return SqliteFileURI(path, "rwc") + "&_foreign_keys=on&_busy_timeout=5000&_journal_mode=WAL&_txlock=immediate"
}

// SqliteStagedDSN builds a canonical SQLite file URI for isolated staged/export temporary databases.
func SqliteStagedDSN(path string, opts ...StagedSQLiteOptions) string {
	var opt StagedSQLiteOptions
	if len(opts) > 0 {
		opt = opts[0]
	}
	var b strings.Builder
	b.WriteString(SqliteFileURI(path, "rw"))
	if opt.FastMemoryJournal {
		b.WriteString("&_foreign_keys=0&_journal_mode=MEMORY&_synchronous=OFF")
	} else {
		if opt.ForeignKeys {
			b.WriteString("&_foreign_keys=on")
		}
		if opt.BusyTimeoutMs > 0 {
			b.WriteString("&_busy_timeout=")
			b.WriteString(strconv.Itoa(opt.BusyTimeoutMs))
		}
		b.WriteString("&_journal_mode=DELETE&_synchronous=FULL")
	}
	if opt.ImmediateTxLock {
		b.WriteString("&_txlock=immediate")
	}
	return b.String()
}

func openSingleConnSQLite(dsn string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	return db, nil
}

// OpenMemorySQLite opens a single-connection in-memory SQLite coordinator/staging database.
func OpenMemorySQLite() (*sql.DB, error) {
	return openSingleConnSQLite(":memory:")
}

// OpenPrivateMemoryImmediateSQLite opens an isolated private in-memory SQLite database with immediate locking and foreign keys.
func OpenPrivateMemoryImmediateSQLite() (*sql.DB, error) {
	return openSingleConnSQLite("file::memory:?cache=private&_txlock=immediate&_busy_timeout=5000&_foreign_keys=on")
}

// OpenReadOnlyBusySQLite opens a read-only SQLite handle configured with _foreign_keys=on and _busy_timeout=5000.
func OpenReadOnlyBusySQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteReadOnlyDSN(path))
}

// OpenQueryOnlySQLite opens a read-only SQLite handle configured with _query_only=on and _busy_timeout=5000.
func OpenQueryOnlySQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteQueryOnlyDSN(path))
}

// OpenImmediateWriteSQLite opens a read-write SQLite handle configured with _foreign_keys=on, _busy_timeout=5000, and _txlock=immediate.
func OpenImmediateWriteSQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteImmediateWriteDSN(path))
}

// OpenImmediateLockSQLite opens a read-write SQLite handle configured with _busy_timeout=5000 and _txlock=immediate.
func OpenImmediateLockSQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteImmediateLockDSN(path))
}

// OpenWALWriteSQLite opens a canonical WAL read-write SQLite handle configured with _foreign_keys=on, _busy_timeout=5000, _journal_mode=WAL, and _txlock=immediate.
func OpenWALWriteSQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteWALWriteDSN(path))
}

// OpenWALCreateSQLite opens or creates a canonical WAL read-write SQLite handle.
func OpenWALCreateSQLite(path string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteWALCreateWriteDSN(path))
}

// OpenStagedSQLite opens an isolated staged/export SQLite file using DELETE+FULL durability (or explicit StagedSQLiteOptions).
func OpenStagedSQLite(path string, opts ...StagedSQLiteOptions) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteStagedDSN(path, opts...))
}

// OpenSQLiteMode opens a SQLite file URI with the explicit mode ("ro", "rw", "rwc") and busy timeout.
func OpenSQLiteMode(path, mode string) (*sql.DB, error) {
	return openSingleConnSQLite(SqliteFileURI(path, mode) + "&_busy_timeout=5000")
}
