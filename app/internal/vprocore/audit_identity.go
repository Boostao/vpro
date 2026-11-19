package vprocore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"
)

// ChildIdentityTable is the canonical monotonic child-ID reservation table in <Project>.db.
const ChildIdentityTable = "__VPRO_ChildIdentity"

// ChildIdentityTableDDL defines the canonical schema for __VPRO_ChildIdentity.
const ChildIdentityTableDDL = `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
	"ChildTable" TEXT NOT NULL,
	"ID" INTEGER NOT NULL,
	PRIMARY KEY ("ChildTable", "ID")
)`

// AuditSQLExecutor is satisfied by *sql.Tx, *sql.Conn, *sql.DB, and *WriteTx.
type AuditSQLExecutor interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// AuditSQLPreparer is satisfied by *sql.Tx, *sql.Conn, *sql.DB, and *WriteTx.
type AuditSQLPreparer interface {
	PrepareContext(ctx context.Context, query string) (*sql.Stmt, error)
}

// AuditSQLRowQueryer is satisfied by *sql.Tx, *sql.Conn, *sql.DB, and *WriteTx.
type AuditSQLRowQueryer interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// CanonicalChildIdentityTableKey normalizes any quoted or unquoted child table identifier
// into its canonical quoted storage key (e.g. `"Sample_Veg"`) and raw unquoted name (`Sample_Veg`).
func CanonicalChildIdentityTableKey(table string) (quoted string, unquoted string) {
	unquoted = strings.ReplaceAll(strings.Trim(strings.TrimSpace(table), `"`), `""`, `"`)
	quoted = QuoteHeaderIdentifier(unquoted)
	return quoted, unquoted
}

// EnsureChildIdentityTable creates __VPRO_ChildIdentity if it does not yet exist.
func EnsureChildIdentityTable(ctx context.Context, exec AuditSQLExecutor) error {
	_, err := exec.ExecContext(ctx, ChildIdentityTableDDL)
	return err
}

// ReserveChildID permanently reserves positive or imported child ID in __VPRO_ChildIdentity
// using the canonical quoted ChildTable key while avoiding duplicate rows on legacy PK-less tables.
// Uses exact binary IN (?, ?) so SQLite's covering primary-key index is always utilized.
func ReserveChildID(ctx context.Context, exec AuditSQLExecutor, childTable string, id int64) error {
	quoted, unquoted := CanonicalChildIdentityTableKey(childTable)
	_, err := exec.ExecContext(ctx, `INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID")
		SELECT ?, ? WHERE NOT EXISTS (
			SELECT 1 FROM "__VPRO_ChildIdentity" WHERE "ChildTable" IN (?, ?) AND "ID" = ?
		)`, quoted, id, quoted, unquoted, id)
	return err
}

// InsertStrictChildIDReservation inserts a new reservation row into __VPRO_ChildIdentity and returns its rowid.
func InsertStrictChildIDReservation(ctx context.Context, exec AuditSQLExecutor, childTable string, id any) (int64, error) {
	quoted, _ := CanonicalChildIdentityTableKey(childTable)
	res, err := exec.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)`, quoted, id)
	if err != nil {
		return 0, err
	}
	if count, err := res.RowsAffected(); err != nil || count != 1 {
		return 0, errors.Join(err, errors.New("child identity reservation did not insert exactly one entry"))
	}
	return res.LastInsertId()
}

// HasChildIDReservation reports whether (childTable, id) is reserved in __VPRO_ChildIdentity
// across either canonical quoted or historical unquoted ChildTable spellings.
func HasChildIDReservation(ctx context.Context, q AuditSQLRowQueryer, childTable string, id int64) (bool, error) {
	quoted, unquoted := CanonicalChildIdentityTableKey(childTable)
	var exists bool
	err := q.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM "__VPRO_ChildIdentity" WHERE "ChildTable" IN (?, ?) AND "ID" = ?)`,
		quoted, unquoted, id,
	).Scan(&exists)
	return exists, err
}

// SeedChildIdentityFromTable seeds __VPRO_ChildIdentity with all existing integer IDs in childTable
// using a singlecovering-index INSERT OR IGNORE ... SELECT pass suitable for 1.65M-row BECMaster tables.
func SeedChildIdentityFromTable(ctx context.Context, exec AuditSQLExecutor, childTable string, includeZero bool) error {
	quoted, unquoted := CanonicalChildIdentityTableKey(childTable)
	op := ">"
	if includeZero {
		op = ">="
	}
	query := fmt.Sprintf(
		`INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID")
		 SELECT ?, "ID" FROM %s
		 WHERE typeof("ID") = 'integer' AND "ID" %s 0
		   AND NOT EXISTS (
		       SELECT 1 FROM "__VPRO_ChildIdentity" AS ci
		       WHERE ci."ChildTable" IN (?, ?) AND ci."ID" = %s."ID"
		   )`,
		quoted, op, quoted,
	)
	_, err := exec.ExecContext(ctx, query, quoted, quoted, unquoted)
	return err
}

// PrepareChildIdentityInsertStmt prepares an idempotent bulk reservation statement for streaming importers.
func PrepareChildIdentityInsertStmt(ctx context.Context, prep AuditSQLPreparer) (*sql.Stmt, error) {
	return prep.PrepareContext(ctx, `INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)`)
}

// AllocateAndReserveChildID ensures __VPRO_ChildIdentity exists, allocates the next unused positive
// signed32 child ID for childTable, and reserves it atomically in tx.
func AllocateAndReserveChildID(ctx context.Context, tx *sql.Tx, childTable string) (int64, error) {
	if err := EnsureChildIdentityTable(ctx, tx); err != nil {
		return 0, err
	}
	quoted, _ := CanonicalChildIdentityTableKey(childTable)
	id, err := AllocateChildID(tx, quoted)
	if err != nil {
		return 0, err
	}
	if err := ReserveChildID(ctx, tx, quoted, id); err != nil {
		return 0, err
	}
	return id, nil
}

// SeedAndAllocateChildID seeds __VPRO_ChildIdentity with all existing positive IDs in <project>_<suffix>
// and <project>_Audit before allocating and reserving the next monotonic positive signed32 child ID.
func SeedAndAllocateChildID(ctx context.Context, tx *sql.Tx, project, suffix string) (int64, error) {
	if err := EnsureChildIdentityTable(ctx, tx); err != nil {
		return 0, err
	}
	plainSuffix := strings.TrimPrefix(suffix, "_")
	childTable := project + "_" + plainSuffix
	quotedChild := QuoteHeaderIdentifier(childTable)

	if err := SeedChildIdentityFromTable(ctx, tx, childTable, false); err != nil {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID")
		 SELECT ?, "ID" FROM "__VPRO_ChildIdentity" AS prev
		 WHERE prev."ChildTable" = ? AND typeof(prev."ID") = 'integer' AND prev."ID" > 0
		   AND NOT EXISTS (
		       SELECT 1 FROM "__VPRO_ChildIdentity" AS ci WHERE ci."ChildTable" = ? AND ci."ID" = prev."ID"
		   )`,
		quotedChild, childTable, quotedChild,
	); err != nil {
		return 0, err
	}

	if !strings.EqualFold(plainSuffix, "Audit") {
		var actualAudit string
		err := tx.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name=? COLLATE NOCASE LIMIT 1`, project+"_Audit").Scan(&actualAudit)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return 0, err
		}
		if actualAudit != "" {
			quotedAudit := QuoteHeaderIdentifier(actualAudit)
			if _, err := tx.ExecContext(ctx,
				`INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID")
				 SELECT ?, a."ID" FROM `+quotedAudit+` AS a
				 WHERE a."Table" COLLATE NOCASE IN (?, ?, ?) AND typeof(a."ID") = 'integer' AND a."ID" > 0
				   AND NOT EXISTS (
				       SELECT 1 FROM "__VPRO_ChildIdentity" AS ci WHERE ci."ChildTable" IN (?, ?) AND ci."ID" = a."ID"
				   )`,
				quotedChild, "_"+plainSuffix, childTable, plainSuffix, quotedChild, childTable,
			); err != nil {
				return 0, err
			}
		}
	}
	return AllocateAndReserveChildID(ctx, tx, quotedChild)
}

// SeedHierarchyNodeIDs ensures identityTable exists in main and permanently reserves all positive IDs
// currently stored in main.<tableName>.
func SeedHierarchyNodeIDs(ctx context.Context, tx *sql.Tx, identityTable, tableName string) error {
	qIdent := QuoteHeaderIdentifier(identityTable)
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+qIdent+` (
		"HierarchyTable" TEXT NOT NULL,
		"ID" INTEGER NOT NULL,
		PRIMARY KEY ("HierarchyTable", "ID")
	)`); err != nil {
		return err
	}
	qTable := QuoteHeaderIdentifier(tableName)
	_, err := tx.ExecContext(ctx,
		`INSERT OR IGNORE INTO main.`+qIdent+` ("HierarchyTable","ID")
		 SELECT ?, "ID" FROM main.`+qTable+` WHERE "ID" > 0`,
		tableName,
	)
	return err
}

// AllocateHierarchyNodeID ensures identityTable exists in main, allocates the next monotonic
// positive signed32 node ID across tableName and identityTable, and permanently reserves it.
func AllocateHierarchyNodeID(ctx context.Context, tx *sql.Tx, identityTable, tableName string) (int64, error) {
	if err := SeedHierarchyNodeIDs(ctx, tx, identityTable, tableName); err != nil {
		return 0, err
	}
	qIdent := QuoteHeaderIdentifier(identityTable)
	qTable := QuoteHeaderIdentifier(tableName)
	var maxID int64
	if err := tx.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(id_val), 0) FROM (
			SELECT "ID" AS id_val FROM main.`+qTable+` WHERE "ID" > 0
			UNION
			SELECT "ID" AS id_val FROM main.`+qIdent+` WHERE "HierarchyTable" = ? AND "ID" > 0
		)`,
		tableName,
	).Scan(&maxID); err != nil {
		return 0, err
	}
	if maxID >= math.MaxInt32 {
		return 0, errors.New("hierarchy node ID space exhausted")
	}
	nextID := maxID + 1
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO main.`+qIdent+` ("HierarchyTable", "ID") VALUES (?, ?)`,
		tableName, nextID,
	); err != nil {
		return 0, err
	}
	return nextID, nil
}

// CanonicalAuditTableName normalizes VP08 core table references to canonical VPro `_<Suffix>`
// spellings (e.g. "Environment" / "Env" / "Sample_Env" -> "_Env") while preserving explicit
// system/companion table stamps (e.g. "NewProject", "USysAllSpecs", "USysUserSpp", "__VPRO_Quarantine").
func CanonicalAuditTableName(project, table string) string {
	trimmed := strings.TrimSpace(table)
	if strings.EqualFold(trimmed, "Environment") {
		return "_Env"
	}
	for _, core := range []string{"Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Metadata", "SU"} {
		if strings.EqualFold(trimmed, core) || strings.EqualFold(trimmed, "_"+core) ||
			(project != "" && strings.EqualFold(trimmed, project+"_"+core)) {
			return "_" + core
		}
	}
	return trimmed
}

// AuditWriteEntry describes one row to append to <Project>_Audit or VUser.USysAuditTrail.
type AuditWriteEntry struct {
	Schema     string // optional schema qualifier (e.g. "main")
	AuditTable string // optional explicit audit table name; defaults to entry.Project + "_Audit"
	Project    string
	User       string
	PlotNumber *string // nil writes SQL NULL (required when PlotNumber is absent so _Env FK holds)
	Table      string
	EditField  *string // nil writes SQL NULL
	EditWhen   string  // defaults to local "2006-01-02 15:04:05" when empty
	BeforeEdit any
	AfterEdit  any
	Restore    int64 // Access BOOLEAN: 0 (false) or -1 (true)
	Flag       int64 // Access BOOLEAN: 0 (false) or -1 (true)
	ID         *int64
}

// AuditString returns a pointer to s for AuditWriteEntry fields.
func AuditString(s string) *string { return &s }

func normalizeAuditValueParam(value any) any {
	if value == nil {
		return nil
	}
	switch v := value.(type) {
	case *string:
		if v == nil {
			return nil
		}
		return *v
	case string:
		return v
	case sql.NullString:
		if !v.Valid {
			return nil
		}
		return v.String
	default:
		return HeaderAuditValue(value)
	}
}

func qualifiedAuditTableSQL(schema, auditTable string) string {
	quoted := QuoteHeaderIdentifier(auditTable)
	if strings.TrimSpace(schema) == "" {
		return quoted
	}
	return QuoteHeaderIdentifier(schema) + "." + quoted
}

func (e AuditWriteEntry) bindArgs() (tableSQL string, args []any, err error) {
	if strings.TrimSpace(e.Project) == "" && strings.TrimSpace(e.AuditTable) == "" {
		return "", nil, errors.New("audit entry requires a project or explicit audit table")
	}
	auditName := e.AuditTable
	if strings.TrimSpace(auditName) == "" {
		auditName = e.Project + "_Audit"
	}
	when := e.EditWhen
	if when == "" {
		when = time.Now().Format("2006-01-02 15:04:05")
	}
	var plotArg any
	if e.PlotNumber != nil {
		plotArg = *e.PlotNumber
	}
	var fieldArg any
	if e.EditField != nil {
		fieldArg = *e.EditField
	}
	var idArg any
	if e.ID != nil {
		idArg = *e.ID
	}
	canonTable := CanonicalAuditTableName(e.Project, e.Table)
	return qualifiedAuditTableSQL(e.Schema, auditName), []any{
		e.Project,
		e.User,
		plotArg,
		canonTable,
		fieldArg,
		when,
		normalizeAuditValueParam(e.BeforeEdit),
		normalizeAuditValueParam(e.AfterEdit),
		e.Restore,
		e.Flag,
		idArg,
	}, nil
}

// RecordAudit inserts a single canonical row into <Project>_Audit and returns its SQLite rowid.
func RecordAudit(ctx context.Context, exec AuditSQLExecutor, entry AuditWriteEntry) (int64, error) {
	targetSQL, args, err := entry.bindArgs()
	if err != nil {
		return 0, err
	}
	res, err := exec.ExecContext(ctx,
		`INSERT INTO `+targetSQL+
			` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
		args...,
	)
	if err != nil {
		return 0, err
	}
	if count, err := res.RowsAffected(); err != nil || count != 1 {
		return 0, errors.Join(err, errors.New("audit writer did not insert exactly one row"))
	}
	return res.LastInsertId()
}

// PrepareProjectAuditStmt prepares a reusable canonical <Project>_Audit INSERT statement for batch mutations.
func PrepareProjectAuditStmt(ctx context.Context, prep AuditSQLPreparer, schema, project string) (*sql.Stmt, error) {
	targetSQL := qualifiedAuditTableSQL(schema, project+"_Audit")
	return prep.PrepareContext(ctx,
		`INSERT INTO `+targetSQL+
			` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
	)
}

// ExecPreparedAudit executes a statement prepared by PrepareProjectAuditStmt with canonical table/value normalization.
func ExecPreparedAudit(ctx context.Context, stmt *sql.Stmt, entry AuditWriteEntry) (int64, error) {
	_, args, err := entry.bindArgs()
	if err != nil {
		return 0, err
	}
	res, err := stmt.ExecContext(ctx, args...)
	if err != nil {
		return 0, err
	}
	if count, err := res.RowsAffected(); err != nil || count != 1 {
		return 0, errors.Join(err, errors.New("prepared audit writer did not insert exactly one row"))
	}
	return res.LastInsertId()
}

// RecordUSysAudit inserts a single row into VUser.db's 8-column USysAuditTrail table.
func RecordUSysAudit(ctx context.Context, exec AuditSQLExecutor, entry AuditWriteEntry) (int64, error) {
	when := entry.EditWhen
	if when == "" {
		when = time.Now().Format("2006-01-02 15:04:05")
	}
	var plotArg any
	if entry.PlotNumber != nil {
		plotArg = *entry.PlotNumber
	}
	var fieldArg any
	if entry.EditField != nil {
		fieldArg = *entry.EditField
	}
	schema := entry.Schema
	if strings.TrimSpace(schema) == "" {
		schema = "main"
	}
	targetSQL := QuoteHeaderIdentifier(schema) + `."USysAuditTrail"`
	res, err := exec.ExecContext(ctx,
		`INSERT INTO `+targetSQL+
			` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit") VALUES (?,?,?,?,?,?,?,?)`,
		entry.Project,
		entry.User,
		plotArg,
		CanonicalAuditTableName(entry.Project, entry.Table),
		fieldArg,
		when,
		normalizeAuditValueParam(entry.BeforeEdit),
		normalizeAuditValueParam(entry.AfterEdit),
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}
