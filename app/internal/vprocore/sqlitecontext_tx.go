package vprocore

import (
	"context"
	"database/sql"
	"errors"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

// LockForTest acquires c's internal mutex in fault-injection tests.
func (c *SqliteContext) LockForTest() { c.mu.Lock() }

// TryLockForTest tries to acquire c's internal mutex in fault-injection tests.
func (c *SqliteContext) TryLockForTest() bool { return c.mu.TryLock() }

// UnlockForTest releases c's internal mutex in fault-injection tests.
func (c *SqliteContext) UnlockForTest() { c.mu.Unlock() }

// IsOpen reports whether c is non-nil and its pinned coordinator connection is open.
func (c *SqliteContext) IsOpen() bool {
	return c != nil && c.conn != nil
}

// LockBlocking acquires c's internal mutex synchronously without context cancellation
// and returns an idempotent unlock function. Prefer WithReadSnapshot, WithImmediateWriteTx,
// or WithLease for request-scoped operations.
func (c *SqliteContext) LockBlocking() func() {
	c.mu.Lock()
	unlocked := false
	return func() {
		if !unlocked {
			unlocked = true
			c.mu.Unlock()
		}
	}
}

// AcquireMutex acquires c's internal mutex honoring ctx cancellation and returns an idempotent unlock function.
func (c *SqliteContext) AcquireMutex(ctx context.Context) (func(), error) {
	if c == nil {
		return nil, errors.New("project context is closed")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := sqlutil.AcquireMutexLease(ctx, &c.mu); err != nil {
		return nil, err
	}
	unlocked := false
	return func() {
		if !unlocked {
			unlocked = true
			c.mu.Unlock()
		}
	}, nil
}

// WithLease acquires c's mutex lease honoring ctx cancellation, verifies c is open, and runs fn.
func (c *SqliteContext) WithLease(ctx context.Context, fn func() error) error {
	unlock, err := c.AcquireMutex(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	if c.conn == nil {
		return errors.New("project context is closed")
	}
	return fn()
}

// CoordinatorWhileLocked returns the pinned coordinator *sql.Conn for callers already
// executing inside WithLease, WithMetadataWriter, WithSelectedFileWriter, or WriteTx.
func (c *SqliteContext) CoordinatorWhileLocked() *sql.Conn {
	if c == nil {
		return nil
	}
	return c.conn
}

// WithCoordinatorConn acquires c's mutex lease, verifies c is open, and passes the pinned
// :memory: coordinator connection to fn.
func (c *SqliteContext) WithCoordinatorConn(ctx context.Context, fn func(conn *sql.Conn) error) error {
	return c.WithLease(ctx, func() error {
		return fn(c.conn)
	})
}

// WithCoordinatorConnValue acquires c's mutex lease, verifies c is open, and evaluates fn on the coordinator connection.
func WithCoordinatorConnValue[T any](ctx context.Context, c *SqliteContext, fn func(conn *sql.Conn) (T, error)) (T, error) {
	var out T
	err := c.WithCoordinatorConn(ctx, func(conn *sql.Conn) error {
		var callErr error
		out, callErr = fn(conn)
		return callErr
	})
	if err != nil {
		var zero T
		return zero, err
	}
	return out, nil
}

// WithReadSnapshot acquires c's mutex lease, opens a caller-owned read-only snapshot transaction
// on the pinned :memory: coordinator, runs fn, and commits cleanly (or rolls back on error/cancellation).
func (c *SqliteContext) WithReadSnapshot(ctx context.Context, fn func(tx *sql.Tx) error) (resultErr error) {
	if c == nil {
		return errors.New("project context is closed")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	unlock, err := c.AcquireMutex(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	if c.conn == nil {
		return errors.New("project context is closed")
	}
	tx, err := c.BeginReadSnapshot(ctx)
	if err != nil {
		return err
	}
	defer func() {
		if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
			resultErr = errors.Join(resultErr, rb)
		}
	}()
	if err := fn(tx); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	return tx.Commit()
}

// WithReadSnapshotValue runs fn inside c.WithReadSnapshot and returns the typed result.
func WithReadSnapshotValue[T any](ctx context.Context, c *SqliteContext, fn func(tx *sql.Tx) (T, error)) (T, error) {
	var out T
	err := c.WithReadSnapshot(ctx, func(tx *sql.Tx) error {
		var callErr error
		out, callErr = fn(tx)
		return callErr
	})
	if err != nil {
		var zero T
		return zero, err
	}
	return out, nil
}

// WithOwnedPublicationSnapshot acquires c's mutex lease, verifies c is open, and delegates
// to WithPublicationReadSnapshot for workbook/artifact publication services.
func WithOwnedPublicationSnapshot[T any](ctx context.Context, c *SqliteContext, hooks PublicationReadSnapshotHooks, fn func(tx *sql.Tx) (T, error)) (T, error) {
	var zero T
	if c == nil {
		return zero, errors.New("project context is closed")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	unlock, err := c.AcquireMutex(ctx)
	if err != nil {
		return zero, err
	}
	defer unlock()
	if c.conn == nil {
		return zero, errors.New("project context is closed")
	}
	return WithPublicationReadSnapshot(ctx, c, hooks, fn)
}

// WriteTx wraps an atomic BEGIN IMMEDIATE SQLite transaction owned by SqliteContext,
// bundling canonical <Project>_Audit emission and monotonic __VPRO_ChildIdentity helpers.
type WriteTx struct {
	Tx      *sql.Tx
	Conn    *sql.Conn
	Owner   *SqliteContext
	Project string
}

func (w *WriteTx) ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error) {
	return w.Tx.ExecContext(ctx, query, args...)
}

func (w *WriteTx) QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error) {
	return w.Tx.QueryContext(ctx, query, args...)
}

func (w *WriteTx) QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row {
	return w.Tx.QueryRowContext(ctx, query, args...)
}

func (w *WriteTx) PrepareContext(ctx context.Context, query string) (*sql.Stmt, error) {
	return w.Tx.PrepareContext(ctx, query)
}

// CoordinatorConn returns the pinned :memory: coordinator connection while WriteTx holds Owner's mutex lease.
func (w *WriteTx) CoordinatorConn() *sql.Conn {
	if w.Owner == nil {
		return nil
	}
	return w.Owner.conn
}

// RecordAudit appends one canonical audit row to <Project>_Audit inside this WriteTx.
func (w *WriteTx) RecordAudit(ctx context.Context, entry AuditWriteEntry) (int64, error) {
	if entry.Project == "" {
		entry.Project = w.Project
	}
	return RecordAudit(ctx, w.Tx, entry)
}

// EnsureChildIdentityTable creates __VPRO_ChildIdentity if absent inside this WriteTx.
func (w *WriteTx) EnsureChildIdentityTable(ctx context.Context) error {
	return EnsureChildIdentityTable(ctx, w.Tx)
}

// ReserveChildID reserves (childTable, id) in __VPRO_ChildIdentity inside this WriteTx.
func (w *WriteTx) ReserveChildID(ctx context.Context, childTable string, id int64) error {
	return ReserveChildID(ctx, w.Tx, childTable, id)
}

// AllocateChildID allocates and reserves the next monotonic positive signed32 ID for childTable.
func (w *WriteTx) AllocateChildID(ctx context.Context, childTable string) (int64, error) {
	return AllocateAndReserveChildID(ctx, w.Tx, childTable)
}

// SeedAndAllocateChildID seeds __VPRO_ChildIdentity from existing rows/audits and allocates the next monotonic ID.
func (w *WriteTx) SeedAndAllocateChildID(ctx context.Context, suffix string) (int64, error) {
	return SeedAndAllocateChildID(ctx, w.Tx, w.Project, suffix)
}

// WithImmediateWriteTx acquires c's mutex lease, reuses c's pooled WAL ProjectDatabase
// (avoiding per-write sql.Open/Close churn), starts an immediate write transaction,
// rolls back automatically on error or context cancellation, and commits cleanly.
func (c *SqliteContext) WithImmediateWriteTx(ctx context.Context, fn func(wtx *WriteTx) error) (resultErr error) {
	if c == nil {
		return errors.New("project context is closed")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	unlock, err := c.AcquireMutex(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	if c.conn == nil {
		return errors.New("project context is closed")
	}
	db, err := c.projectDatabaseLocked(ctx)
	if err != nil {
		return err
	}
	conn, err := db.Conn(ctx)
	if err != nil {
		return err
	}
	defer func() {
		resultErr = errors.Join(resultErr, conn.Close())
	}()
	tx, err := conn.BeginTx(context.WithoutCancel(ctx), nil)
	if err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}
	}()
	wtx := &WriteTx{
		Tx:      tx,
		Conn:    conn,
		Owner:   c,
		Project: c.Selection.Project,
	}
	if err := fn(wtx); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	committed = true
	return nil
}

// WithImmediateProjectWriteTx is an alias for WithImmediateWriteTx on the active project database.
func (c *SqliteContext) WithImmediateProjectWriteTx(ctx context.Context, fn func(wtx *WriteTx) error) error {
	return c.WithImmediateWriteTx(ctx, fn)
}

// WithImmediateRoleWriteTx runs fn inside an atomic BEGIN IMMEDIATE transaction on the
// attached database for role ("project", "su", "hierarchy", "VUser", etc.) with VLists attached as "reference".
func (c *SqliteContext) WithImmediateRoleWriteTx(ctx context.Context, role string, validate func() error, fn func(wtx *WriteTx) error) error {
	if validate == nil {
		validate = func() error { return nil }
	}
	return c.WithSelectedFileWriter(ctx, role, validate, func(conn *sql.Conn) (txErr error) {
		tx, err := conn.BeginTx(context.WithoutCancel(ctx), nil)
		if err != nil {
			return err
		}
		committed := false
		defer func() {
			if !committed {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}
		}()
		wtx := &WriteTx{
			Tx:      tx,
			Conn:    conn,
			Owner:   c,
			Project: c.Selection.Project,
		}
		if err := fn(wtx); err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		committed = true
		return nil
	})
}
