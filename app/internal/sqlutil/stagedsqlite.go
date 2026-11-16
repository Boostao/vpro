package sqlutil

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"strings"
)

// SURowSeed represents one PlotNumber/SiteUnit assignment row in a *_SU table.
type SURowSeed struct {
	PlotNumber string
	SiteUnit   *string
	PlotNull   bool
}

// RemoveSQLiteWithSidecars removes a SQLite file and any -journal/-wal/-shm sidecars,
// ignoring missing-file errors.
func RemoveSQLiteWithSidecars(path string) error {
	if path == "" {
		return nil
	}
	var errs []error
	for _, target := range []string{path, path + "-journal", path + "-wal", path + "-shm"} {
		if err := os.Remove(target); err != nil && !errors.Is(err, os.ErrNotExist) {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// BeginStagedTx validates ctx before starting a non-cancelable database/sql transaction
// so deferred Rollback completes synchronously before db.Close and temp-file cleanup.
func BeginStagedTx(ctx context.Context, db *sql.DB) (*sql.Tx, error) {
	if ctx != nil {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
	}
	return db.Begin()
}

// CommitStagedTx ensures ctx has not been canceled before committing tx, rolling back
// synchronously if ctx is already done.
func CommitStagedTx(ctx context.Context, tx *sql.Tx) error {
	if ctx != nil {
		if err := ctx.Err(); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	return tx.Commit()
}

// InsertSURowsBatched inserts SU rows into main.<quotedTable> using 400-row multi-value
// INSERT statements, checking ctx between batches.
func InsertSURowsBatched(ctx context.Context, tx *sql.Tx, quotedTable string, rows []SURowSeed) error {
	if len(rows) == 0 {
		return nil
	}
	const batchSize = 400
	prefix := `INSERT INTO main.` + quotedTable + ` ("PlotNumber","SiteUnit") VALUES `
	for start := 0; start < len(rows); start += batchSize {
		if ctx != nil {
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		end := min(start+batchSize, len(rows))
		chunk := rows[start:end]
		placeholders := make([]string, len(chunk))
		args := make([]any, 0, len(chunk)*2)
		for i, row := range chunk {
			placeholders[i] = "(?,?)"
			var plotArg any = row.PlotNumber
			if row.PlotNull {
				plotArg = nil
			}
			args = append(args, plotArg, row.SiteUnit)
		}
		if _, err := tx.ExecContext(ctx, prefix+strings.Join(placeholders, ","), args...); err != nil {
			return err
		}
	}
	return nil
}
