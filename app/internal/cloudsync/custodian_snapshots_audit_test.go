package cloudsync

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/jackc/pgx/v5"
	_ "github.com/mattn/go-sqlite3"
)

type sqliteAuditScanner struct {
	rows    *sql.Rows
	colLen  int
	lastErr error
	curr    []any
}

func (s *sqliteAuditScanner) Next() bool {
	if !s.rows.Next() {
		return false
	}
	raw := make([]any, s.colLen)
	dest := make([]any, s.colLen)
	for i := range raw {
		dest[i] = &raw[i]
	}
	if err := s.rows.Scan(dest...); err != nil {
		s.lastErr = err
		return false
	}
	s.curr = raw
	return true
}

func (s *sqliteAuditScanner) Values() ([]any, error) {
	if s.lastErr != nil {
		return nil, s.lastErr
	}
	return s.curr, nil
}

func (s *sqliteAuditScanner) Err() error {
	if s.lastErr != nil {
		return s.lastErr
	}
	return s.rows.Err()
}

func (s *sqliteAuditScanner) Close() {
	_ = s.rows.Close()
}

type sqliteAuditChainStore struct {
	db      *sql.DB
	batches int
}

func newSQLiteAuditChainStore(t *testing.T) *sqliteAuditChainStore {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "audit_chain_test.db")
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })

	if _, err := db.Exec(`
		CREATE TABLE audit (
			audit_seq INTEGER PRIMARY KEY,
			"Project" TEXT,
			"User" TEXT,
			"PlotNumber" TEXT,
			"Table" TEXT,
			"EditField" TEXT,
			"EditWhen" TEXT,
			"BeforeEdit" TEXT,
			"AfterEdit" TEXT,
			"Restore" INTEGER,
			"Flag" INTEGER,
			"ID" INTEGER,
			merge_tx_id TEXT,
			prev_hash TEXT NOT NULL,
			row_hash TEXT NOT NULL
		)
	`); err != nil {
		t.Fatal(err)
	}
	return &sqliteAuditChainStore{db: db}
}

func (s *sqliteAuditChainStore) CountAuditRows(ctx context.Context) (int64, error) {
	var total int64
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM audit`).Scan(&total)
	return total, err
}

func (s *sqliteAuditChainStore) PredecessorBeforeOffset(ctx context.Context, offset int) (int64, string, error) {
	var seq int64
	var rowHash string
	err := s.db.QueryRowContext(ctx, `SELECT audit_seq, row_hash FROM audit ORDER BY audit_seq DESC LIMIT 1 OFFSET ?`, offset).Scan(&seq, &rowHash)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, "", pgx.ErrNoRows
	}
	return seq, rowHash, err
}

func (s *sqliteAuditChainStore) QueryAuditBatch(ctx context.Context, hasAfterSeq bool, afterSeq int64, batchLimit int) (auditRowScanner, error) {
	s.batches++
	cols := sqliteSelectColumnsCSV(VP08AuditColumns)
	var (
		rows *sql.Rows
		err  error
	)
	if hasAfterSeq {
		q := fmt.Sprintf(`
			SELECT audit_seq, %s, COALESCE(merge_tx_id, ''), prev_hash, row_hash
			FROM audit
			WHERE audit_seq > ?
			ORDER BY audit_seq ASC
			LIMIT ?
		`, cols)
		rows, err = s.db.QueryContext(ctx, q, afterSeq, batchLimit)
	} else {
		q := fmt.Sprintf(`
			SELECT audit_seq, %s, COALESCE(merge_tx_id, ''), prev_hash, row_hash
			FROM audit
			ORDER BY audit_seq ASC
			LIMIT ?
		`, cols)
		rows, err = s.db.QueryContext(ctx, q, batchLimit)
	}
	if err != nil {
		return nil, err
	}
	return &sqliteAuditScanner{rows: rows, colLen: 4 + len(VP08AuditColumns)}, nil
}

func seedValidAuditRows(t *testing.T, store *sqliteAuditChainStore, count int) (tailHash string, seqs []int64) {
	t.Helper()
	tx, err := store.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	stmt, err := tx.Prepare(`
		INSERT INTO audit (
			audit_seq, "Project", "User", "PlotNumber", "Table", "EditField",
			"EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag", "ID",
			merge_tx_id, prev_hash, row_hash
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`)
	if err != nil {
		_ = tx.Rollback()
		t.Fatal(err)
	}
	defer stmt.Close()

	prev := GenesisAuditHash
	var seq int64 = 1
	seqs = make([]int64, 0, count)
	for i := 0; i < count; i++ {
		if i > 0 {
			// Include realistic sequence gaps from aborted/rolled-back transactions.
			seq += int64(1 + (i % 3))
		}
		plot := fmt.Sprintf("%05d", (i%999)+1)
		var beforeVal any
		if i%2 == 0 {
			beforeVal = "IDF"
		}
		afterVal := fmt.Sprintf("CWH_%d", i)
		restoreFlag := int16(0)
		if i%7 == 0 {
			restoreFlag = -1
		}
		var childID any
		if i%3 == 0 {
			childID = int64(1000 + i)
		}
		mergeTx := ""
		if i >= 10 {
			mergeTx = "11111111-2222-3333-4444-555555555555"
		}
		vp08Row := []any{
			"BECMaster",
			"Will MacKenzie",
			plot,
			"_Env",
			"Zone",
			"2026-11-17 09:30:00",
			beforeVal,
			afterVal,
			restoreFlag,
			int16(0),
			childID,
		}
		rowHash := ComputeAuditRowHash(prev, mergeTx, vp08Row)
		var mergeTxDB any
		if mergeTx != "" {
			mergeTxDB = mergeTx
		}
		if _, err := stmt.Exec(
			seq,
			vp08Row[0], vp08Row[1], vp08Row[2], vp08Row[3], vp08Row[4],
			vp08Row[5], vp08Row[6], vp08Row[7], vp08Row[8], vp08Row[9], vp08Row[10],
			mergeTxDB, prev, rowHash,
		); err != nil {
			_ = tx.Rollback()
			t.Fatal(err)
		}
		seqs = append(seqs, seq)
		prev = rowHash
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	return prev, seqs
}

func TestUXCloud004VerifyAuditChainFullLedgerVsPartialWindow(t *testing.T) {
	ctx := t.Context()

	// 1. Negative limit is rejected immediately without touching any database pool.
	mgr := NewManager(t.TempDir(), func(string) (string, bool) { return "", false })
	defer mgr.Close()
	if _, err := mgr.VerifyBECMasterAuditChain(ctx, -1); err == nil || !strings.Contains(err.Error(), ">= 0") {
		t.Fatalf("expected negative limit error, got %v", err)
	}

	// 2. SQL builder emits bounded keyset cursor queries (never silently capping at 1000).
	initialSQL := buildAuditBatchSelectSQL(false)
	cursorSQL := buildAuditBatchSelectSQL(true)
	if strings.Contains(initialSQL, "WHERE audit_seq >") || !strings.Contains(initialSQL, "ORDER BY audit_seq ASC") || !strings.Contains(initialSQL, "LIMIT $1") {
		t.Fatalf("unexpected initial batch SQL: %s", initialSQL)
	}
	if !strings.Contains(cursorSQL, "WHERE audit_seq > $1") || !strings.Contains(cursorSQL, "ORDER BY audit_seq ASC") || !strings.Contains(cursorSQL, "LIMIT $2") {
		t.Fatalf("unexpected keyset cursor batch SQL: %s", cursorSQL)
	}

	// 3. Empty ledger returns 0 verified/total rows, valid=true, partialWindow=false, GenesisAuditHash.
	emptyStore := newSQLiteAuditChainStore(t)
	emptyRes, err := verifyAuditChainWithStore(ctx, emptyStore, nil, 0, 400)
	if err != nil {
		t.Fatalf("empty ledger limit=0 error: %v", err)
	}
	if !emptyRes.Valid || emptyRes.VerifiedRows != 0 || emptyRes.TotalRows != 0 || emptyRes.PartialWindow || emptyRes.TailHash != GenesisAuditHash {
		t.Fatalf("unexpected empty ledger result: %+v", emptyRes)
	}

	// 4. Seed 2,505 rows (> 1,000 old cap) with sequence gaps and verify limit=0 streams ALL rows across batches.
	store := newSQLiteAuditChainStore(t)
	wantTail, seqs := seedValidAuditRows(t, store, 2505)

	store.batches = 0
	fullRes, err := verifyAuditChainWithStore(ctx, store, nil, 0, 400)
	if err != nil {
		t.Fatalf("full chain limit=0 error: %v", err)
	}
	if !fullRes.Valid || fullRes.VerifiedRows != 2505 || fullRes.TotalRows != 2505 || fullRes.PartialWindow || fullRes.TailHash != wantTail {
		t.Fatalf("limit=0 must verify all 2505 rows from genesis without partialWindow: got %+v", fullRes)
	}
	if store.batches < 7 {
		t.Fatalf("expected multi-batch streaming (>= 7 batches at batchSize=400 for 2505 rows), got %d", store.batches)
	}

	// 5. Partial tail window (limit=100 < 2505) verifies latest 100 of 2505 rows and sets PartialWindow=true.
	tailRes, err := verifyAuditChainWithStore(ctx, store, nil, 100, 40)
	if err != nil {
		t.Fatalf("partial window limit=100 error: %v", err)
	}
	if !tailRes.Valid || tailRes.VerifiedRows != 100 || tailRes.TotalRows != 2505 || !tailRes.PartialWindow || tailRes.TailHash != wantTail {
		t.Fatalf("unexpected limit=100 partial window result: %+v", tailRes)
	}

	// 6. limit >= totalRows (limit=5000 on 2505 rows) verifies full chain from genesis with PartialWindow=false.
	wideRes, err := verifyAuditChainWithStore(ctx, store, nil, 5000, 1000)
	if err != nil {
		t.Fatalf("limit=5000 >= totalRows error: %v", err)
	}
	if !wideRes.Valid || wideRes.VerifiedRows != 2505 || wideRes.TotalRows != 2505 || wideRes.PartialWindow || wideRes.TailHash != wantTail {
		t.Fatalf("expected limit>=totalRows to verify full chain with PartialWindow=false, got %+v", wideRes)
	}

	// 7. UX-CLOUD-004 core regression check: tamper with an early row (row index 49, >2,450 rows before head).
	// A partial window of limit=1000 does NOT reach row 49 (reports PartialWindow=true, 1000 of 2505),
	// whereas limit=0 MUST detect the tampering at seqs[49]!
	earlySeq := seqs[49]
	if _, err := store.db.Exec(`UPDATE audit SET "AfterEdit" = 'TAMPERED_EARLY' WHERE audit_seq = ?`, earlySeq); err != nil {
		t.Fatal(err)
	}
	window1000, err := verifyAuditChainWithStore(ctx, store, nil, 1000, 400)
	if err != nil || !window1000.Valid || !window1000.PartialWindow || window1000.VerifiedRows != 1000 || window1000.TotalRows != 2505 {
		t.Fatalf("expected limit=1000 tail window to report PartialWindow=true (1000 of 2505), got %+v err=%v", window1000, err)
	}
	tamperedFull, err := verifyAuditChainWithStore(ctx, store, nil, 0, 400)
	if err == nil || tamperedFull.Valid || !strings.Contains(err.Error(), fmt.Sprintf("seq=%d", earlySeq)) {
		t.Fatalf("expected limit=0 to catch early row tampering at seq=%d, got res=%+v err=%v", earlySeq, tamperedFull, err)
	}
	// Restore AfterEdit on earlySeq
	if _, err := store.db.Exec(`UPDATE audit SET "AfterEdit" = 'CWH_49' WHERE audit_seq = ?`, earlySeq); err != nil {
		t.Fatal(err)
	}

	// 8. Cross-batch prev_hash break right at batch boundary (row index 400 -> 401 with batchSize=400).
	boundarySeq := seqs[400]
	var origBoundaryPrev string
	if err := store.db.QueryRow(`SELECT prev_hash FROM audit WHERE audit_seq = ?`, boundarySeq).Scan(&origBoundaryPrev); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.Exec(`UPDATE audit SET prev_hash = 'deadbeef' WHERE audit_seq = ?`, boundarySeq); err != nil {
		t.Fatal(err)
	}
	brokenBatch, err := verifyAuditChainWithStore(ctx, store, nil, 0, 400)
	if err == nil || brokenBatch.Valid || !strings.Contains(err.Error(), fmt.Sprintf("audit hash chain broken at seq=%d", boundarySeq)) {
		t.Fatalf("expected cross-batch chain break at seq=%d, got res=%+v err=%v", boundarySeq, brokenBatch, err)
	}
	if _, err := store.db.Exec(`UPDATE audit SET prev_hash = ? WHERE audit_seq = ?`, origBoundaryPrev, boundarySeq); err != nil {
		t.Fatal(err)
	}

	// 9. Window predecessor boundary break when limit=100 (tamper predecessor row_hash at index 2505-101 = 2404).
	predSeq := seqs[2505-101]
	var origPredRowHash string
	if err := store.db.QueryRow(`SELECT row_hash FROM audit WHERE audit_seq = ?`, predSeq).Scan(&origPredRowHash); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.Exec(`UPDATE audit SET row_hash = 'cafebabe' WHERE audit_seq = ?`, predSeq); err != nil {
		t.Fatal(err)
	}
	brokenWindow, err := verifyAuditChainWithStore(ctx, store, nil, 100, 40)
	if err == nil || brokenWindow.Valid || !brokenWindow.PartialWindow || !strings.Contains(err.Error(), fmt.Sprintf("audit window boundary broken at seq=%d", seqs[2505-100])) {
		t.Fatalf("expected partial window boundary break at seq=%d, got res=%+v err=%v", seqs[2505-100], brokenWindow, err)
	}
	if _, err := store.db.Exec(`UPDATE audit SET row_hash = ? WHERE audit_seq = ?`, origPredRowHash, predSeq); err != nil {
		t.Fatal(err)
	}

	// 10. Deleted prefix (delete row 0 so surviving row 1 has prev_hash != GenesisAuditHash) caught by limit=0.
	if _, err := store.db.Exec(`DELETE FROM audit WHERE audit_seq = ?`, seqs[0]); err != nil {
		t.Fatal(err)
	}
	deletedPrefix, err := verifyAuditChainWithStore(ctx, store, nil, 0, 400)
	if err == nil || deletedPrefix.Valid || !strings.Contains(err.Error(), "GenesisAuditHash") {
		t.Fatalf("expected deleted prefix error on limit=0, got res=%+v err=%v", deletedPrefix, err)
	}
}
