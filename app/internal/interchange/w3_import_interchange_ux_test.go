//go:build !vpro_headless

package interchange

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

type cancellableFakeAccessRowSource struct {
	cols     []accessreader.Column
	rows     []accessreader.Row
	pos      int
	cancelAt int
	cancelFn context.CancelFunc
}

func (f *cancellableFakeAccessRowSource) ColumnsList() []accessreader.Column { return f.cols }
func (f *cancellableFakeAccessRowSource) EnableRowQuarantine()               {}
func (f *cancellableFakeAccessRowSource) Next() bool {
	f.pos++
	if f.cancelAt > 0 && f.pos == f.cancelAt && f.cancelFn != nil {
		f.cancelFn()
	}
	return f.pos <= len(f.rows)
}
func (f *cancellableFakeAccessRowSource) Row() accessreader.Row { return f.rows[f.pos-1] }
func (f *cancellableFakeAccessRowSource) Err() error            { return nil }
func (f *cancellableFakeAccessRowSource) QuarantinedRows() []accessreader.QuarantinedRow {
	return nil
}
func (f *cancellableFakeAccessRowSource) Close() error { return nil }

func TestAccessStreamProgressEventsAndMidStreamCancellation(t *testing.T) {
	rows := make([]accessreader.Row, 6000)
	for i := range rows {
		rows[i] = accessreader.Row{"00337", "PSEUMEN", float64(15), int64(i + 1)}
	}

	// 1. Verify live progress events fire with table names and monotonic row counts.
	var mu sync.Mutex
	var events []AccessImportProgress
	progressCtx := WithAccessImportProgress(context.Background(), "ctx-progress", "import", func(ev AccessImportProgress) {
		mu.Lock()
		events = append(events, ev)
		mu.Unlock()
	})

	dbPath := filepath.Join(t.TempDir(), "ProgressTest.db")
	sqlDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	defer sqlDB.Close()

	tx, err := sqlDB.BeginTx(progressCtx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.ExecContext(progressCtx, `CREATE TABLE "Target_Veg" ("PlotNumber" VARCHAR, "Species" VARCHAR, "Cover1" DOUBLE, "ID" INTEGER)`); err != nil {
		_ = tx.Rollback()
		t.Fatal(err)
	}

	src := &cancellableFakeAccessRowSource{
		cols: []accessreader.Column{
			{Name: "PlotNumber", Type: "text"},
			{Name: "Species", Type: "text"},
			{Name: "Cover1", Type: "real"},
			{Name: "ID", Type: "integer"},
		},
		rows: rows,
	}
	metrics, err := streamAccessSourceIntoSQLite(progressCtx, src, tx, nil, nil, "Source_Veg", nil, []streamInsertSpec{
		{targetTable: "Target_Veg"},
	})
	_ = tx.Rollback()
	if err != nil {
		t.Fatalf("streamAccessSourceIntoSQLite failed: %v", err)
	}
	if metrics.importedRows != 6000 {
		t.Fatalf("importedRows = %d, want 6000", metrics.importedRows)
	}

	mu.Lock()
	gotEvents := append([]AccessImportProgress(nil), events...)
	mu.Unlock()
	if len(gotEvents) < 2 {
		t.Fatalf("expected at least begin and finish progress events, got %+v", gotEvents)
	}
	if gotEvents[0].ContextID != "ctx-progress" || gotEvents[0].SourceTable != "Source_Veg" || gotEvents[0].TargetTable != "Target_Veg" {
		t.Fatalf("unexpected initial progress event: %+v", gotEvents[0])
	}
	last := gotEvents[len(gotEvents)-1]
	if last.TableRowsProcessed != 6000 || last.TableRowsImported != 6000 || last.TotalRowsProcessed != 6000 {
		t.Fatalf("unexpected final progress event: %+v", last)
	}

	// 2. Verify mid-stream cancellation aborts promptly with context.Canceled before finishing all rows.
	cancelCtx, cancel := context.WithCancel(context.Background())
	txCancel, err := sqlDB.BeginTx(cancelCtx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = txCancel.Rollback() }()
	if _, err := txCancel.ExecContext(context.Background(), `CREATE TABLE "Cancel_Veg" ("PlotNumber" VARCHAR, "Species" VARCHAR, "Cover1" DOUBLE, "ID" INTEGER)`); err != nil {
		t.Fatal(err)
	}

	cancelSrc := &cancellableFakeAccessRowSource{
		cols:     src.cols,
		rows:     rows,
		cancelAt: 1500,
		cancelFn: cancel,
	}
	_, cancelErr := streamAccessSourceIntoSQLite(cancelCtx, cancelSrc, txCancel, nil, nil, "Source_Veg", nil, []streamInsertSpec{
		{targetTable: "Cancel_Veg"},
	})
	if !errors.Is(cancelErr, context.Canceled) {
		t.Fatalf("expected context.Canceled on mid-stream abort, got %v", cancelErr)
	}
	if cancelSrc.pos >= len(rows) {
		t.Fatalf("expected stream to stop early after cancellation, read %d / %d rows", cancelSrc.pos, len(rows))
	}
}

func TestImportAccessProjectCancellationLeavesZeroPartialOrStagedDBFiles(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	srcPath := firstExistingPath(`/home/bruno/Work/VPRO_ACCESS/VPro64/VPro64.accdb`, `C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64\VPro64.accdb`)
	if _, err := os.Stat(srcPath); err != nil {
		t.Skipf("fixture %s not present: %v", srcPath, err)
	}

	destDir := t.TempDir()
	destFile := filepath.Join(destDir, "CancelledImport.db")

	ctx, cancel := context.WithCancel(context.Background())
	var stages []string
	progressCtx := WithAccessImportProgress(ctx, state.ContextID, "import", func(ev AccessImportProgress) {
		stages = append(stages, ev.Phase+":"+ev.SourceTable)
		if ev.SourceTable != "" {
			// Cancel as soon as streaming the first source table begins.
			cancel()
		}
	})

	_, err := ImportAccessProject(service, progressCtx, state.ContextID, AccessProjectImportRequest{
		SourcePath:        srcPath,
		SourceProject:     "Sample",
		TargetProject:     "CancelledImport",
		DestinationPath:   destFile,
		ActivateOnSuccess: true,
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled on aborted Access import, got %v", err)
	}
	if len(stages) == 0 {
		t.Fatal("expected progress callback to fire before cancellation")
	}
	if _, statErr := os.Stat(destFile); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("cancelled import must not publish destination .db, statErr=%v", statErr)
	}
	entries, dirErr := os.ReadDir(destDir)
	if dirErr != nil {
		t.Fatal(dirErr)
	}
	if len(entries) != 0 {
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Fatalf("cancelled import left residual staged files in %s: %v", destDir, names)
	}
}

func TestInspectAccessDatabasePlainLanguageErrorsWithoutSyscallNoise(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	dir := t.TempDir()

	// 1. Nonexistent .accdb file
	missingPath := filepath.Join(dir, "does_not_exist_qa.accdb")
	_, err := InspectAccessDatabase(service, context.Background(), state.ContextID, missingPath)
	if err == nil {
		t.Fatal("expected error on missing Access file")
	}
	for _, banned := range []string{"lstat ", "stat ", "no such file or directory", "RuntimeError"} {
		if strings.Contains(err.Error(), banned) {
			t.Fatalf("missing Access file error leaked %q: %v", banned, err)
		}
	}
	if !strings.Contains(err.Error(), "was not found") {
		t.Fatalf("expected plain-language 'was not found' message, got %q", err.Error())
	}

	// 2. Folder named *.accdb
	folderAsAccdb := filepath.Join(dir, "directory.accdb")
	if err := os.MkdirAll(folderAsAccdb, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err = InspectAccessDatabase(service, context.Background(), state.ContextID, folderAsAccdb)
	if err == nil || !strings.Contains(err.Error(), "folder") {
		t.Fatalf("expected plain-language folder message, got %v", err)
	}

	// 3. Truncated / corrupt .accdb file
	truncPath := filepath.Join(dir, "truncated.accdb")
	if err := os.WriteFile(truncPath, []byte("not-a-jet-or-ace-header"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err = InspectAccessDatabase(service, context.Background(), state.ContextID, truncPath)
	if err == nil {
		t.Fatal("expected error on truncated Access file")
	}
	if strings.Contains(err.Error(), "Access source read error") {
		t.Fatalf("truncated Access file leaked raw C bridge error: %v", err)
	}
	if !strings.Contains(err.Error(), "could not be read") {
		t.Fatalf("expected plain-language unreadable Access message, got %q", err.Error())
	}
}

func TestOptionalLumpMapPlainLanguageErrorsAndExternalLumpDBPath(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	dir := t.TempDir()

	// 1. Missing lump table in active project must NOT leak "sql: no rows in result set" across any exporter!
	_, err := ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{
		LumpTable: "NonExistentLump",
	})
	if err == nil {
		t.Fatal("expected error for missing lump table")
	}
	if strings.Contains(err.Error(), "sql: no rows in result set") {
		t.Fatalf("missing lump table leaked sql.ErrNoRows: %v", err)
	}
	if !strings.Contains(err.Error(), `species lumping table "NonExistentLump_Lump" was not found`) {
		t.Fatalf("unexpected missing lump table message: %q", err.Error())
	}

	// 2. Missing external LumpDBPath must return plain-language message without lstat syscall text.
	_, err = ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{
		LumpTable:  "External_Lump",
		LumpDBPath: filepath.Join(dir, "missing_external.db"),
	})
	if err == nil || strings.Contains(err.Error(), "lstat") || !strings.Contains(err.Error(), "was not found") {
		t.Fatalf("expected plain-language missing lump file error, got %v", err)
	}

	// 3. External LumpDBPath folds species cleanly when exporting from another active project.
	var sppA, sppB string
	origDB, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	rSpp, err := origDB.QueryContext(ctx, `SELECT DISTINCT UPPER(TRIM("Species")) FROM "Sample_Veg" WHERE "Species" IS NOT NULL AND TRIM("Species") <> '' ORDER BY 1 LIMIT 2`)
	if err != nil {
		origDB.Close()
		t.Fatal(err)
	}
	if rSpp.Next() {
		_ = rSpp.Scan(&sppA)
	}
	if rSpp.Next() {
		_ = rSpp.Scan(&sppB)
	}
	_ = rSpp.Close()
	_ = origDB.Close()
	if sppA == "" || sppB == "" || sppA == sppB {
		t.Fatalf("expected at least 2 distinct species in Sample_Veg, got %q and %q", sppA, sppB)
	}

	extDBPath := filepath.Join(dir, "ExternalLumps.db")
	extDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(extDBPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := extDB.ExecContext(ctx, `
		CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT);
		INSERT INTO "_table_metadata" VALUES ('Crew2026_Lump', 'VP05');
		CREATE TABLE "Crew2026_Lump" ("LumpCode" VARCHAR, "SppCode" VARCHAR, "Use" BOOLEAN);
	`); err != nil {
		extDB.Close()
		t.Fatal(err)
	}
	if _, err := extDB.ExecContext(ctx, `INSERT INTO "Crew2026_Lump" ("LumpCode", "SppCode", "Use") VALUES ('FOLDED_GRP', ?, -1), ('FOLDED_GRP', ?, -1)`, sppA, sppB); err != nil {
		extDB.Close()
		t.Fatal(err)
	}
	if err := extDB.Close(); err != nil {
		t.Fatal(err)
	}

	unlumped, err := ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{})
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(unlumped): %v", err)
	}
	lumped, err := ExportLongTidyCSV(service, ctx, state.ContextID, LongTidyCSVRequest{
		LumpTable:  "Crew2026_Lump",
		LumpDBPath: extDBPath,
	})
	if err != nil {
		t.Fatalf("ExportLongTidyCSV(external LumpDBPath): %v", err)
	}
	if lumped.SpeciesCount >= unlumped.SpeciesCount {
		t.Fatalf("expected external lump table to fold species count below %d, got %d", unlumped.SpeciesCount, lumped.SpeciesCount)
	}
}
