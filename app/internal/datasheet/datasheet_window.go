package datasheet

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
)

func queryDatasheetWindowRows(
	ctx context.Context,
	tx *sql.Tx,
	role, tableName string,
	columns []DatasheetColumnMeta,
	whereSQL string,
	whereArgs []any,
	orderSQL string,
	offset, limit int,
) ([]DatasheetRow, error) {
	relation := vprocore.QuoteHeaderIdentifier(role) + "." + vprocore.QuoteHeaderIdentifier(tableName)

	selectFields := make([]string, 0, 1+len(columns)*2)
	selectFields = append(selectFields, "__t.rowid")
	for _, col := range columns {
		qCol := `__t.` + vprocore.QuoteHeaderIdentifier(col.Name)
		selectFields = append(selectFields,
			"typeof("+qCol+")",
			"CASE typeof("+qCol+") WHEN 'integer' THEN CAST("+qCol+" AS INTEGER) WHEN 'real' THEN CAST("+qCol+" AS REAL) ELSE CAST("+qCol+" AS BLOB) END",
		)
	}

	if limit <= 0 || limit > 900 {
		query := "SELECT " + strings.Join(selectFields, ",") + " FROM " + relation + " AS __t" + whereSQL + orderSQL
		args := append([]any{}, whereArgs...)
		if limit > 0 {
			query += " LIMIT ? OFFSET ?"
			args = append(args, limit, offset)
		}
		rows, err := tx.QueryContext(ctx, query, args...)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		result := []DatasheetRow{}
		storages := make([]string, len(columns))
		values := make([]any, len(columns))
		var rowID int64
		dest := make([]any, 0, 1+len(columns)*2)
		dest = append(dest, &rowID)
		for i := range columns {
			dest = append(dest, &storages[i], &values[i])
		}
		for rows.Next() {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			for i := range values {
				values[i] = nil
			}
			if err := rows.Scan(dest...); err != nil {
				return nil, err
			}
			cells := make([]vprocore.ProjectMetadataCell, len(columns))
			for i, val := range values {
				cell, err := vprocore.ProjectMetadataCellInternal(storages[i], val)
				if err != nil {
					return nil, fmt.Errorf("row %d column %s: %w", rowID, columns[i].Name, err)
				}
				cells[i] = cell
			}
			result = append(result, DatasheetRow{
				RowID: strconv.FormatInt(rowID, 10),
				Cells: cells,
			})
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, err
		}
		return result, nil
	}

	// Stage 1: fetch only the bounded window of rowids so SQLite's top-N sorter never materializes 88 cell expressions for non-window rows.
	idQuery := "SELECT __t.rowid FROM " + relation + " AS __t" + whereSQL + orderSQL + " LIMIT ? OFFSET ?"
	idArgs := append(append([]any{}, whereArgs...), limit, offset)
	idRows, err := tx.QueryContext(ctx, idQuery, idArgs...)
	if err != nil {
		return nil, err
	}
	var winRowIDs []int64
	for idRows.Next() {
		var rid int64
		if err := idRows.Scan(&rid); err != nil {
			idRows.Close()
			return nil, err
		}
		winRowIDs = append(winRowIDs, rid)
	}
	if err := errors.Join(idRows.Err(), idRows.Close()); err != nil {
		return nil, err
	}
	return fetchDatasheetRowsByRowIDs(ctx, tx, relation, selectFields, columns, winRowIDs)
}

type datasheetFileStamp struct {
	size         int64
	mtimeNano    int64
	dbHeader4    [4]byte
	walPresent   bool
	walSize      int64
	walMtimeNano int64
	shmHdr48     [48]byte
}

func statDatasheetFileWithWAL(dbPath string) (datasheetFileStamp, bool) {
	if strings.TrimSpace(dbPath) == "" {
		return datasheetFileStamp{}, false
	}
	info, err := os.Stat(dbPath)
	if err != nil {
		return datasheetFileStamp{}, false
	}
	st := datasheetFileStamp{size: info.Size(), mtimeNano: info.ModTime().UnixNano()}
	if info.Size() >= 28 {
		if f, oErr := os.Open(dbPath); oErr == nil {
			_, _ = f.ReadAt(st.dbHeader4[:], 24)
			_ = f.Close()
		}
	}
	if walInfo, walErr := os.Stat(dbPath + "-wal"); walErr == nil {
		st.walPresent = true
		st.walSize = walInfo.Size()
		st.walMtimeNano = walInfo.ModTime().UnixNano()
		if shmFile, sErr := os.Open(dbPath + "-shm"); sErr == nil {
			_, _ = shmFile.ReadAt(st.shmHdr48[:], 0)
			_ = shmFile.Close()
		}
	}
	return st, true
}

func queryFilteredDatasheetWindowAndCount(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	preTxStamp datasheetFileStamp,
	preTxOK bool,
	role, tableName string,
	columns []DatasheetColumnMeta,
	whereSQL string,
	whereArgs []any,
	orderSQL string,
	scopeToActiveSU bool,
	limit int,
) ([]DatasheetRow, int64, error) {
	relation := vprocore.QuoteHeaderIdentifier(role) + "." + vprocore.QuoteHeaderIdentifier(tableName)
	selectFields := make([]string, 0, 1+len(columns)*2)
	selectFields = append(selectFields, "__t.rowid")
	for _, col := range columns {
		qCol := `__t.` + vprocore.QuoteHeaderIdentifier(col.Name)
		selectFields = append(selectFields,
			"typeof("+qCol+")",
			"CASE typeof("+qCol+") WHEN 'integer' THEN CAST("+qCol+" AS INTEGER) WHEN 'real' THEN CAST("+qCol+" AS REAL) ELSE CAST("+qCol+" AS BLOB) END",
		)
	}

	if !scopeToActiveSU && owner != nil && preTxOK {
		if dbPath := strings.TrimSpace(owner.Attachments[role]); dbPath != "" {
			var minRowID, maxRowID sql.NullInt64
			if rErr := tx.QueryRowContext(ctx, "SELECT MIN(rowid), MAX(rowid) FROM "+relation).Scan(&minRowID, &maxRowID); rErr == nil &&
				minRowID.Valid && maxRowID.Valid && maxRowID.Int64-minRowID.Int64 >= 100000 {
				workers := min(max(runtime.NumCPU(), 2), 8)
				if workers*limit <= 900 {
					if pRows, pTotal, pOK, pErr := parallelRangeScanDatasheetWindow(
						ctx, tx, dbPath, preTxStamp, relation, tableName, selectFields, columns,
						whereSQL, whereArgs, orderSQL, minRowID.Int64, maxRowID.Int64, limit, workers,
					); pErr != nil {
						return nil, 0, pErr
					} else if pOK {
						return pRows, pTotal, nil
					}
				}
			}
		}
	}

	idQuery := "SELECT __t.rowid, COUNT(*) OVER () FROM " + relation + " AS __t" + whereSQL + orderSQL + " LIMIT ?"
	idArgs := append(append([]any{}, whereArgs...), limit)
	idRows, err := tx.QueryContext(ctx, idQuery, idArgs...)
	if err != nil {
		return nil, 0, err
	}
	var winRowIDs []int64
	var totalRows int64
	for idRows.Next() {
		var rid, cnt int64
		if err := idRows.Scan(&rid, &cnt); err != nil {
			idRows.Close()
			return nil, 0, err
		}
		winRowIDs = append(winRowIDs, rid)
		totalRows = cnt
	}
	if err := errors.Join(idRows.Err(), idRows.Close()); err != nil {
		return nil, 0, err
	}
	rows, err := fetchDatasheetRowsByRowIDs(ctx, tx, relation, selectFields, columns, winRowIDs)
	return rows, totalRows, err
}

func parallelRangeScanDatasheetWindow(
	ctx context.Context,
	tx *sql.Tx,
	dbPath string,
	preTxStamp datasheetFileStamp,
	relation, tableName string,
	selectFields []string,
	columns []DatasheetColumnMeta,
	whereSQL string,
	whereArgs []any,
	orderSQL string,
	minRowID, maxRowID int64,
	limit, workers int,
) ([]DatasheetRow, int64, bool, error) {
	roDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "ro")+"&_busy_timeout=5000")
	if err != nil {
		return nil, 0, false, nil
	}
	defer roDB.Close()
	roDB.SetMaxOpenConns(workers)
	roDB.SetMaxIdleConns(workers)

	whereBody := strings.TrimPrefix(whereSQL, " WHERE ")
	qTable := vprocore.QuoteHeaderIdentifier(tableName)
	chunkSQL := fmt.Sprintf(
		"SELECT __t.rowid, COUNT(*) OVER () FROM %s AS __t WHERE (%s) AND __t.rowid BETWEEN ? AND ?%s LIMIT ?",
		qTable, whereBody, orderSQL,
	)

	span := maxRowID - minRowID + 1
	step := (span + int64(workers) - 1) / int64(workers)

	type chunkResult struct {
		ids   []int64
		count int64
		err   error
	}
	results := make([]chunkResult, workers)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		lo := minRowID + int64(w)*step
		if lo > maxRowID {
			continue
		}
		hi := min(lo+step-1, maxRowID)
		wg.Add(1)
		go func(idx int, loID, hiID int64) {
			defer wg.Done()
			cArgs := make([]any, 0, len(whereArgs)+3)
			cArgs = append(cArgs, whereArgs...)
			cArgs = append(cArgs, loID, hiID, limit)
			conn, cErr := roDB.Conn(ctx)
			if cErr != nil {
				results[idx].err = cErr
				return
			}
			defer conn.Close()
			_, _ = conn.ExecContext(ctx, "PRAGMA mmap_size = 268435456")
			rRows, qErr := conn.QueryContext(ctx, chunkSQL, cArgs...)
			if qErr != nil {
				results[idx].err = qErr
				return
			}
			var ids []int64
			var cnt int64
			for rRows.Next() {
				var rid, c int64
				if sErr := rRows.Scan(&rid, &c); sErr != nil {
					rRows.Close()
					results[idx].err = sErr
					return
				}
				ids = append(ids, rid)
				cnt = c
			}
			results[idx].err = errors.Join(rRows.Err(), rRows.Close())
			results[idx].ids = ids
			results[idx].count = cnt
		}(w, lo, hi)
	}
	wg.Wait()

	// Verify the underlying SQLite file + WAL/SHM stamp did not advance relative to tx's snapshot
	// while workers executed on roDB; if a concurrent writer committed, fall back to tx's single snapshot.
	if postStamp, postOK := statDatasheetFileWithWAL(dbPath); !postOK || postStamp != preTxStamp {
		return nil, 0, false, nil
	}

	var totalRows int64
	var candidateIDs []int64
	for _, res := range results {
		if res.err != nil {
			if ctx.Err() != nil {
				return nil, 0, false, res.err
			}
			return nil, 0, false, nil
		}
		totalRows += res.count
		candidateIDs = append(candidateIDs, res.ids...)
	}
	if len(candidateIDs) == 0 {
		return []DatasheetRow{}, 0, true, nil
	}

	ph := make([]string, len(candidateIDs))
	mergeArgs := make([]any, len(candidateIDs)+1)
	for i, id := range candidateIDs {
		ph[i] = "?"
		mergeArgs[i] = id
	}
	mergeArgs[len(candidateIDs)] = limit
	mergeQuery := "SELECT __t.rowid FROM " + relation + " AS __t WHERE __t.rowid IN (" + strings.Join(ph, ",") + ")" + orderSQL + " LIMIT ?"
	mRows, err := tx.QueryContext(ctx, mergeQuery, mergeArgs...)
	if err != nil {
		return nil, 0, false, err
	}
	var winRowIDs []int64
	for mRows.Next() {
		var rid int64
		if err := mRows.Scan(&rid); err != nil {
			mRows.Close()
			return nil, 0, false, err
		}
		winRowIDs = append(winRowIDs, rid)
	}
	if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
		return nil, 0, false, err
	}
	rows, err := fetchDatasheetRowsByRowIDs(ctx, tx, relation, selectFields, columns, winRowIDs)
	return rows, totalRows, true, err
}

func fetchDatasheetRowsByRowIDs(
	ctx context.Context,
	tx *sql.Tx,
	relation string,
	selectFields []string,
	columns []DatasheetColumnMeta,
	winRowIDs []int64,
) ([]DatasheetRow, error) {
	if len(winRowIDs) == 0 {
		return []DatasheetRow{}, nil
	}

	// Stage 2: fetch full typed cell storage only for the winning window rowids and preserve window order.
	ph := make([]string, len(winRowIDs))
	fetchArgs := make([]any, len(winRowIDs))
	posByRowID := make(map[int64]int, len(winRowIDs))
	for i, rid := range winRowIDs {
		ph[i] = "?"
		fetchArgs[i] = rid
		posByRowID[rid] = i
	}
	fetchQuery := "SELECT " + strings.Join(selectFields, ",") + " FROM " + relation + " AS __t WHERE __t.rowid IN (" + strings.Join(ph, ",") + ")"
	rows, err := tx.QueryContext(ctx, fetchQuery, fetchArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make([]DatasheetRow, len(winRowIDs))
	storages := make([]string, len(columns))
	values := make([]any, len(columns))
	var rowID int64
	dest := make([]any, 0, 1+len(columns)*2)
	dest = append(dest, &rowID)
	for i := range columns {
		dest = append(dest, &storages[i], &values[i])
	}

	seen := 0
	for rows.Next() {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		for i := range values {
			values[i] = nil
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		cells := make([]vprocore.ProjectMetadataCell, len(columns))
		for i, val := range values {
			cell, err := vprocore.ProjectMetadataCellInternal(storages[i], val)
			if err != nil {
				return nil, fmt.Errorf("row %d column %s: %w", rowID, columns[i].Name, err)
			}
			cells[i] = cell
		}
		if idx, ok := posByRowID[rowID]; ok {
			result[idx] = DatasheetRow{
				RowID: strconv.FormatInt(rowID, 10),
				Cells: cells,
			}
			seen++
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	if seen != len(winRowIDs) {
		filtered := make([]DatasheetRow, 0, seen)
		for _, r := range result {
			if r.RowID != "" {
				filtered = append(filtered, r)
			}
		}
		return filtered, nil
	}
	return result, nil
}

func GetDatasheetPage(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetPageRequest) (*DatasheetPage, error) {
	if ctx == nil {
		return nil, errors.New("datasheet page read requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	if request.Offset < 0 {
		return nil, errors.New("datasheet offset must be non-negative")
	}
	limit := request.Limit
	if limit == 0 {
		limit = DatasheetDefaultLimit
	}
	if limit < 1 || limit > DatasheetMaxLimit {
		return nil, fmt.Errorf("datasheet limit must be between 1 and %d", DatasheetMaxLimit)
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ *DatasheetPage, resultErr error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		target, err := findDatasheetTarget(owner, request.TableKey)
		if err != nil {
			return nil, err
		}
		if !target.available {
			return nil, errors.New(target.unavailableReason)
		}

		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return nil, err
		}
		defer owner.Mu.Unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		preTxStamp, preTxOK := statDatasheetFileWithWAL(owner.Attachments[target.role])
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if err := tx.Rollback(); err != nil && !errors.Is(err, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, err)
			}
		}()

		exists, err := tableExistsInSnapshot(ctx, tx, target.role, target.tableName)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, fmt.Errorf("table %s does not exist in %s database", target.tableName, target.role)
		}
		rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, target.role, target.tableName)
		if err != nil {
			return nil, err
		}
		columns := make([]DatasheetColumnMeta, len(rawCols))
		for i, col := range rawCols {
			columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
		}

		whereSQL, whereArgs, orderSQL, err := buildDatasheetWhereAndOrder(
			ctx, tx, target, columns, request.Filters, request.GlobalSearch, request.ScopeToActiveSU, owner, request.Sort,
		)
		if err != nil {
			return nil, err
		}

		relation := vprocore.QuoteHeaderIdentifier(target.role) + "." + vprocore.QuoteHeaderIdentifier(target.tableName)
		var rows []DatasheetRow
		var totalRows int64
		if request.Offset == 0 && whereSQL != "" && limit > 0 && limit <= 900 {
			rows, totalRows, err = queryFilteredDatasheetWindowAndCount(
				ctx, tx, owner, preTxStamp, preTxOK, target.role, target.tableName, columns,
				whereSQL, whereArgs, orderSQL, request.ScopeToActiveSU, limit,
			)
			if err != nil {
				return nil, err
			}
		} else if request.Offset == 0 {
			rows, err = queryDatasheetWindowRows(ctx, tx, target.role, target.tableName, columns, whereSQL, whereArgs, orderSQL, 0, limit)
			if err != nil {
				return nil, err
			}
			if len(rows) < limit {
				totalRows = int64(len(rows))
			} else {
				if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+relation+" AS __t"+whereSQL, whereArgs...).Scan(&totalRows); err != nil {
					return nil, err
				}
			}
		} else {
			if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+relation+" AS __t"+whereSQL, whereArgs...).Scan(&totalRows); err != nil {
				return nil, err
			}
			if int64(request.Offset) < totalRows {
				rows, err = queryDatasheetWindowRows(ctx, tx, target.role, target.tableName, columns, whereSQL, whereArgs, orderSQL, request.Offset, limit)
				if err != nil {
					return nil, err
				}
			} else {
				rows = []DatasheetRow{}
			}
		}

		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}

		return &DatasheetPage{
			ContextID:       contextID,
			Project:         owner.Selection.Project,
			ProjectPath:     owner.Selection.ProjectPath,
			SU:              owner.Selection.SU,
			Hierarchy:       owner.Selection.Hierarchy,
			TableKey:        target.key,
			TableName:       target.tableName,
			PinnedColumn:    target.pinnedColumn,
			Columns:         columns,
			Rows:            rows,
			Offset:          request.Offset,
			Limit:           limit,
			TotalRows:       totalRows,
			CanEditMaster:   canEditMaster,
			ReadOnly:        target.readOnly,
			ScopeToActiveSU: request.ScopeToActiveSU,
		}, nil
	})
}
