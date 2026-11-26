package accessimport

import (
	"archive/zip"
	"context"
	"database/sql"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
)

type fakeMensurationSource struct {
	cols        []accessreader.Column
	rows        []accessreader.Row
	idx         int
	quarantined []accessreader.QuarantinedRow
	err         error
}

func (f *fakeMensurationSource) ColumnsList() []accessreader.Column { return f.cols }
func (f *fakeMensurationSource) EnableRowQuarantine()               {}
func (f *fakeMensurationSource) Next() bool {
	if f.idx >= len(f.rows) {
		return false
	}
	f.idx++
	return true
}
func (f *fakeMensurationSource) Row() accessreader.Row { return f.rows[f.idx-1] }
func (f *fakeMensurationSource) Err() error            { return f.err }
func (f *fakeMensurationSource) QuarantinedRows() []accessreader.QuarantinedRow {
	return f.quarantined
}
func (f *fakeMensurationSource) Close() error { return nil }

func TestStreamMensurationSourceAdaptationBooleansAndQuarantine(t *testing.T) {
	ctx := context.Background()
	dbPath := filepath.Join(t.TempDir(), "mens.db")
	db, err := sqlutil.OpenWALCreateSQLite(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()

	if err := ensureTargetMensurationTable(ctx, tx, "Demo", "TreePlot"); err != nil {
		t.Fatal(err)
	}
	if err := ensureTargetMensurationTable(ctx, tx, "Demo", "Trees"); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE "__VPRO_Quarantine" (
		"ID" INTEGER PRIMARY KEY AUTOINCREMENT,
		"SourceTable" TEXT NOT NULL,
		"RowOrdinal" INTEGER NOT NULL,
		"PlotNumber" TEXT,
		"Reason" TEXT NOT NULL,
		"RawJSON" TEXT NOT NULL
	)`); err != nil {
		t.Fatal(err)
	}
	qStmt, err := tx.PrepareContext(ctx, `INSERT INTO "__VPRO_Quarantine" ("SourceTable","RowOrdinal","PlotNumber","Reason","RawJSON") VALUES (?,?,?,?,?)`)
	if err != nil {
		t.Fatal(err)
	}
	defer qStmt.Close()

	tpSrc := &fakeMensurationSource{
		cols: []accessreader.Column{
			{Name: "PlotNumber", Type: "text"},
			{Name: "SubPlot", Type: "text"},
			{Name: "MeasurementID", Type: "integer"},
			{Name: "Date", Type: "datetime"},
			{Name: "CruisePlot", Type: "boolean"},
			{Name: "CWDPlot", Type: "boolean"},
			{Name: "WildlifePlot", Type: "boolean"},
			{Name: "InformalPlot", Type: "boolean"},
			{Name: "SiteIndexPlot", Type: "boolean"},
			{Name: "BAF", Type: "real"},
		},
		rows: []accessreader.Row{
			{"0002801", "1", int64(1), time.Date(2000, 9, 19, 0, 0, 0, 0, time.UTC), true, false, true, false, true, 8.0},
			// Overlong PlotNumber (> 7 UTF-16 chars) should be quarantined.
			{"OVERLONG8", "1", int64(1), nil, false, false, false, false, false, 4.0},
		},
	}
	imported, malformed, err := streamMensurationSourceIntoSQLite(ctx, tpSrc, tx, qStmt, "Src_TreePlot", "Demo_TreePlot", treePlotUTF16Limits)
	if err != nil {
		t.Fatalf("stream TreePlot failed: %v", err)
	}
	if imported != 1 || malformed != 1 {
		t.Fatalf("expected imported=1 malformed=1 for TreePlot, got %d/%d", imported, malformed)
	}

	treesSrc := &fakeMensurationSource{
		cols: []accessreader.Column{
			{Name: "PlotNumber", Type: "text"},
			{Name: "SubPlot", Type: "text"},
			{Name: "MeasurementID", Type: "integer"},
			{Name: "TreeNum", Type: "integer"},
			{Name: "TreeSpp", Type: "text"},
			{Name: "DBH", Type: "real"},
			{Name: "SI50", Type: "real"},
		},
		rows: []accessreader.Row{
			{"0002801", "1", int64(1), int64(1), "Pl", 16.1, 21.2},
			// Overlong TreeSpp (> 3 UTF-16 chars) should be quarantined.
			{"0002801", "1", int64(1), int64(2), "TOOLONG", 14.0, 20.0},
		},
	}
	tImported, tMalformed, err := streamMensurationSourceIntoSQLite(ctx, treesSrc, tx, qStmt, "Src_Trees", "Demo_Trees", treesUTF16Limits)
	if err != nil {
		t.Fatalf("stream Trees failed: %v", err)
	}
	if tImported != 1 || tMalformed != 1 {
		t.Fatalf("expected imported=1 malformed=1 for Trees, got %d/%d", tImported, tMalformed)
	}

	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	var plotType string
	var plotNum string
	var cruise, cwd int64
	if err := db.QueryRow(`SELECT typeof(PlotNumber), PlotNumber, CruisePlot, CWDPlot FROM Demo_TreePlot`).Scan(&plotType, &plotNum, &cruise, &cwd); err != nil {
		t.Fatal(err)
	}
	if plotType != "text" || plotNum != "0002801" || cruise != -1 || cwd != 0 {
		t.Fatalf("unexpected Demo_TreePlot row: type=%s plot=%q cruise=%d cwd=%d", plotType, plotNum, cruise, cwd)
	}

	var qCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM "__VPRO_Quarantine"`).Scan(&qCount); err != nil {
		t.Fatal(err)
	}
	if qCount != 2 {
		t.Fatalf("expected 2 quarantined rows, got %d", qCount)
	}
}

func TestImportMensurationFromRealClientSIBECArchive(t *testing.T) {
	const zipPath = "/home/bruno/.gemini/antigravity/brain/9194dc2b-818c-4d35-a8e4-9896e64ca479/.user_uploaded/media_1795650659121_6cc58cd3.zip"
	if _, err := os.Stat(zipPath); err != nil {
		t.Skipf("client SIBEC archive not present in this environment: %v", err)
	}

	tmpDir := t.TempDir()
	accdbPath := filepath.Join(tmpDir, "sibec_trees.accdb")
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		t.Fatalf("open zip: %v", err)
	}
	defer zr.Close()
	if len(zr.File) == 0 {
		t.Fatal("zip archive is empty")
	}
	rc, err := zr.File[0].Open()
	if err != nil {
		t.Fatalf("open zip entry: %v", err)
	}
	outFile, err := os.Create(accdbPath)
	if err != nil {
		rc.Close()
		t.Fatalf("create temp accdb: %v", err)
	}
	if _, err := io.Copy(outFile, rc); err != nil {
		rc.Close()
		outFile.Close()
		t.Fatalf("extract accdb: %v", err)
	}
	rc.Close()
	if err := outFile.Close(); err != nil {
		t.Fatal(err)
	}

	// 1. Discover standalone tree-only candidate.
	candidates, err := DiscoverMensurationTablesInFile(accdbPath)
	if err != nil {
		t.Fatalf("DiscoverMensurationTablesInFile failed: %v", err)
	}
	if len(candidates) != 1 {
		t.Fatalf("expected 1 mensuration candidate, got %+v", candidates)
	}
	c := candidates[0]
	if c.SourceProject != "SIBEC_All_2026" || !c.HasTreePlot || !c.HasTrees || !c.StandaloneTreeOnly || c.HasEnvTable {
		t.Fatalf("unexpected candidate metadata: %+v", c)
	}

	// 2. Import all 7,101 TreePlot rows and 11,849 Trees rows into a fresh SQLite DB.
	ctx := context.Background()
	destDB := filepath.Join(tmpDir, "SIBEC_Imported.db")
	res, err := ImportMensurationFromAccess(ctx, accdbPath, destDB, ImportMensurationOptions{
		TargetProject:         "SIBEC2026",
		CreateTablesIfMissing: true,
		RecordQuarantine:      true,
	})
	if err != nil {
		t.Fatalf("ImportMensurationFromAccess failed: %v", err)
	}
	// Row 2395 in the real SIBEC archive has a legacy 3-digit year ("713-07-01") which accessreader quarantines.
	if res.TreePlotRowsImported+res.TreePlotMalformedRows != 7101 || res.TreePlotRowsImported < 7100 {
		t.Fatalf("expected 7101 total TreePlot rows (>=7100 imported), got %+v", res)
	}
	if res.TreesRowsImported != 11849 || res.TreesMalformedRows != 0 {
		t.Fatalf("expected 11849 imported / 0 malformed Trees rows, got %+v", res)
	}
	if !res.StandaloneTreeOnly {
		t.Fatalf("expected StandaloneTreeOnly=true, got %+v", res)
	}

	// 3. Verify leading-zero PlotNumber '0002801', quarantine ledger, and Access -1/0 booleans in SQLite.
	checkDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(destDB, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer checkDB.Close()

	var tpCount, treesCount, qCount int
	if err := checkDB.QueryRow(`SELECT COUNT(*) FROM SIBEC2026_TreePlot`).Scan(&tpCount); err != nil {
		t.Fatal(err)
	}
	if err := checkDB.QueryRow(`SELECT COUNT(*) FROM SIBEC2026_Trees`).Scan(&treesCount); err != nil {
		t.Fatal(err)
	}
	if err := checkDB.QueryRow(`SELECT COUNT(*) FROM "__VPRO_Quarantine"`).Scan(&qCount); err != nil {
		t.Fatal(err)
	}
	if tpCount != res.TreePlotRowsImported || treesCount != 11849 || qCount != res.TreePlotMalformedRows {
		t.Fatalf("SQLite row counts mismatch: tp=%d (want %d) trees=%d q=%d (want %d)", tpCount, res.TreePlotRowsImported, treesCount, qCount, res.TreePlotMalformedRows)
	}

	var plotType, zone string
	if err := checkDB.QueryRow(`SELECT typeof(PlotNumber), Zone FROM SIBEC2026_TreePlot WHERE PlotNumber = '0002801' AND typeof(PlotNumber)='text'`).Scan(&plotType, &zone); err != nil {
		t.Fatalf("leading-zero plot '0002801' lookup failed: %v", err)
	}
	if plotType != "text" || zone != "CWH" {
		t.Fatalf("unexpected row for '0002801': type=%s zone=%q", plotType, zone)
	}

	var trueCruiseCount, invalidBoolCount int
	if err := checkDB.QueryRow(`SELECT COUNT(*) FROM SIBEC2026_TreePlot WHERE CruisePlot = -1`).Scan(&trueCruiseCount); err != nil {
		t.Fatal(err)
	}
	if err := checkDB.QueryRow(`SELECT COUNT(*) FROM SIBEC2026_TreePlot WHERE CruisePlot NOT IN (-1, 0)`).Scan(&invalidBoolCount); err != nil {
		t.Fatal(err)
	}
	if trueCruiseCount == 0 || invalidBoolCount != 0 {
		t.Fatalf("expected Access -1/0 booleans on CruisePlot, got true=%d invalid=%d", trueCruiseCount, invalidBoolCount)
	}
}
