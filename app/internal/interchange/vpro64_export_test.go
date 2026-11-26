package interchange

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestExportVPro64DatabaseCleanDeleteJournalAndAccessBooleans(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	// Switch to Sample with Sample SU and Sample Hierarchy active so all optional companions are exercised.
	var suPath string
	for _, su := range state.SUs {
		if su.Name == "Sample" {
			suPath = su.Path
			break
		}
	}
	var hierPath string
	for _, h := range state.Hierarchies {
		if h.Name == "Sample" {
			hierPath = h.Path
			break
		}
	}
	if suPath != "" {
		var err error
		state, err = service.SwitchContext(state.ContextID, vprocore.ContextSelection{
			Project:       state.ActiveProject,
			ProjectPath:   state.ProjectPath,
			SU:            "Sample",
			SUPath:        suPath,
			Hierarchy:     state.ActiveHierarchy,
			HierarchyPath: hierPath,
		})
		if err != nil {
			t.Fatalf("SwitchContext: %v", err)
		}
	}

	// Add optional _TreePlot and _Trees tables with boolean = 1 (to verify normalization to Access -1!)
	// and a leading-zero PlotNumber '00337'.
	db, err := sqlutil.OpenImmediateWriteSQLite(state.ProjectPath)
	if err != nil {
		t.Fatalf("open project db for mensuration setup: %v", err)
	}
	_, err = db.ExecContext(ctx, `
		CREATE TABLE "Sample_TreePlot" (
			"PlotNumber" TEXT NOT NULL,
			"SubPlot" TEXT NOT NULL,
			"MeasurementID" INTEGER NOT NULL,
			"CruisePlot" INTEGER NOT NULL,
			"CWDPlot" INTEGER NOT NULL,
			"WildlifePlot" INTEGER NOT NULL
		);
		INSERT INTO "Sample_TreePlot" VALUES ('00337', 'Main', 1, 1, 0, -1);
		CREATE TABLE "Sample_Trees" (
			"PlotNumber" TEXT NOT NULL,
			"TreeNum" INTEGER,
			"TreeSpp" TEXT,
			"DBH" REAL
		);
		INSERT INTO "Sample_Trees" VALUES ('00337', 1, 'FD', 42.5);
	`)
	_ = db.Close()
	if err != nil {
		t.Fatalf("seed mensuration tables: %v", err)
	}

	outPath := filepath.Join(t.TempDir(), "ExportedForVPro64.db")
	outcome, err := ExportVPro64Database(service, ctx, state.ContextID, VPro64ExportRequest{
		DestinationPath:    outPath,
		TargetProjectName:  "VPro64Export",
		IncludeActiveSU:    true,
		IncludeHierarchy:   true,
		IncludeMensuration: true,
		IncludeCompanions:  true,
	})
	if err != nil {
		t.Fatalf("ExportVPro64Database: %v", err)
	}
	if outcome.JournalMode != "delete" {
		t.Fatalf("expected journal_mode=delete, got %q", outcome.JournalMode)
	}
	if outcome.PlotCount == 0 || outcome.Bytes == 0 || outcome.SHA256 == "" {
		t.Fatalf("unexpected export outcome metadata: %+v", outcome)
	}
	if !outcome.IncludedMensuration {
		t.Fatalf("expected IncludedMensuration=true, got %+v", outcome)
	}

	// Verify zero -wal / -shm / -journal sidecars exist!
	for _, suf := range []string{"-wal", "-shm", "-journal"} {
		if _, statErr := os.Stat(outPath + suf); !os.IsNotExist(statErr) {
			t.Fatalf("unexpected SQLite sidecar %s exists after VPro64 export", outPath+suf)
		}
	}

	// Inspect the exported SQLite database directly.
	outDB, err := sqlutil.OpenReadOnlyContext(ctx, outPath)
	if err != nil {
		t.Fatalf("open exported db: %v", err)
	}
	defer outDB.Close()

	var jm string
	if err := outDB.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&jm); err != nil {
		t.Fatal(err)
	}
	if !strings.EqualFold(jm, "delete") {
		t.Fatalf("expected PRAGMA journal_mode=delete in exported file, got %q", jm)
	}

	// Verify all 8 core tables are tagged VP08 in _table_metadata under TargetProjectName.
	for _, suf := range vprocore.CoreTables {
		var desc string
		if err := outDB.QueryRowContext(ctx, `SELECT description FROM "_table_metadata" WHERE table_name = ?`, "VPro64Export_"+suf).Scan(&desc); err != nil {
			t.Fatalf("missing _table_metadata for VPro64Export_%s: %v", suf, err)
		}
		if desc != "VP08" {
			t.Fatalf("expected VP08 metadata for VPro64Export_%s, got %q", suf, desc)
		}
	}

	// Verify Access -1/0 boolean normalization and leading-zero literal text PlotNumber in _TreePlot!
	var plotNum string
	var plotType string
	var cruise, cwd, wildlife int64
	if err := outDB.QueryRowContext(ctx, `SELECT PlotNumber, typeof(PlotNumber), CruisePlot, CWDPlot, WildlifePlot FROM "VPro64Export_TreePlot"`).
		Scan(&plotNum, &plotType, &cruise, &cwd, &wildlife); err != nil {
		t.Fatalf("query exported TreePlot: %v", err)
	}
	if plotNum != "00337" || plotType != "text" {
		t.Fatalf("leading-zero PlotNumber was not preserved as literal text: %q (%s)", plotNum, plotType)
	}
	if cruise != -1 || cwd != 0 || wildlife != -1 {
		t.Fatalf("expected Access booleans (-1, 0, -1), got (%d, %d, %d)", cruise, cwd, wildlife)
	}

	// Verify _Trees exported cleanly.
	var treeCount int
	if err := outDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM "VPro64Export_Trees"`).Scan(&treeCount); err != nil {
		t.Fatalf("query exported Trees: %v", err)
	}
	if treeCount != 1 {
		t.Fatalf("expected 1 exported tree row, got %d", treeCount)
	}

	// Verify optional PlotNumbers subset export works too.
	var firstPlot string
	if err := outDB.QueryRowContext(ctx, `SELECT PlotNumber FROM "VPro64Export_Env" ORDER BY PlotNumber LIMIT 1`).Scan(&firstPlot); err != nil {
		t.Fatalf("read first plot: %v", err)
	}
	subsetPath := filepath.Join(t.TempDir(), "SubsetVPro64.db")
	subOut, err := ExportVPro64Database(service, ctx, state.ContextID, VPro64ExportRequest{
		DestinationPath: subsetPath,
		PlotNumbers:     []string{firstPlot},
	})
	if err != nil {
		t.Fatalf("subset ExportVPro64Database: %v", err)
	}
	if subOut.PlotCount != 1 {
		t.Fatalf("expected 1 plot in subset export, got %d", subOut.PlotCount)
	}
	subDB, err := sql.Open("sqlite3", subsetPath)
	if err != nil {
		t.Fatal(err)
	}
	defer subDB.Close()
	var envCount int
	if err := subDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM "Sample_Env"`).Scan(&envCount); err != nil {
		t.Fatal(err)
	}
	if envCount != 1 {
		t.Fatalf("expected 1 row in subset Sample_Env, got %d", envCount)
	}
}

func TestRewriteCreateIndexSQLCaseInsensitiveON(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "lowercase on unquoted",
			raw:  `CREATE INDEX idx_Sample_Env_Plot on Sample_Env (PlotNumber)`,
			want: `CREATE INDEX "idx_Target_Env_Plot" ON "Target_Env" (PlotNumber)`,
		},
		{
			name: "mixed-case On double-quoted no space before paren",
			raw:  `CREATE UNIQUE INDEX "idx_Sample_Env_Plot" On "Sample_Env"(PlotNumber)`,
			want: `CREATE UNIQUE INDEX "idx_Target_Env_Plot" ON "Target_Env"(PlotNumber)`,
		},
		{
			name: "lowercase on bracketed",
			raw:  `CREATE INDEX [idx_Sample_Env_Plot] on [Sample_Env] ("PlotNumber")`,
			want: `CREATE INDEX "idx_Target_Env_Plot" ON "Target_Env" ("PlotNumber")`,
		},
		{
			name: "mixed-case oN backticked",
			raw:  "CREATE INDEX `idx_Sample_Env_Plot` oN `Sample_Env` (`PlotNumber`)",
			want: "CREATE INDEX \"idx_Target_Env_Plot\" ON \"Target_Env\" (`PlotNumber`)",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := rewriteCreateIndexSQL(tc.raw, "idx_Sample_Env_Plot", "idx_Target_Env_Plot", "Sample_Env", "Target_Env")
			if got != tc.want {
				t.Fatalf("rewriteCreateIndexSQL:\n  got:  %s\n  want: %s", got, tc.want)
			}
		})
	}
}
