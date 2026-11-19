package rsidecar

import (
	"context"
	"database/sql"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/boostao/vpro/app/resources"
)

func TestResolveCandidateSUNameTruncationAndParity(t *testing.T) {
	cases := []struct {
		name      string
		rawPrefix string
		project   string
		want      string
		wantErr   bool
	}{
		{
			name:      "truncates >14 char explicit prefix Haida_Gwaii_2019",
			rawPrefix: "Haida_Gwaii_2019",
			project:   "Sample",
			want:      "Haida_Gwaii_20_ClusterCandidate",
		},
		{
			name:      "truncates 20 char default project name",
			rawPrefix: "",
			project:   "TwentyCharProjectNam",
			want:      "TwentyCharProj_ClusterCandidate",
		},
		{
			name:      "strips case-insensitive _su and _clustercandidate suffixes",
			rawPrefix: "Haida_Gwaii_2019_clustercandidate_su",
			project:   "Sample",
			want:      "Haida_Gwaii_20_ClusterCandidate",
		},
		{
			name:      "maps master project substring to Proj",
			rawPrefix: "",
			project:   "BECMaster_Subset",
			want:      "Proj_ClusterCandidate",
		},
		{
			name:      "rejects invalid characters beyond 14th position instead of truncating away",
			rawPrefix: "GoodPrefix12345$bad",
			project:   "Sample",
			wantErr:   true,
		},
		{
			name:      "rejects reserved None and USys prefixes",
			rawPrefix: "None",
			project:   "Sample",
			wantErr:   true,
		},
		{
			name:      "rejects USys prefix",
			rawPrefix: "USysCustom",
			project:   "Sample",
			wantErr:   true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := resolveCandidateSUName(tc.rawPrefix, tc.project)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error for rawPrefix=%q project=%q, got %q", tc.rawPrefix, tc.project, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("resolveCandidateSUName(%q, %q) unexpected error: %v", tc.rawPrefix, tc.project, err)
			}
			if got != tc.want {
				t.Fatalf("resolveCandidateSUName(%q, %q) = %q, want %q", tc.rawPrefix, tc.project, got, tc.want)
			}
			if !vprocore.ProjectNamePattern.MatchString(got) {
				t.Fatalf("resolved candidate SU %q (len=%d) rejected by ProjectNamePattern", got, len(got))
			}
		})
	}
}

func TestRWriteSUCandidate20CharProjectPromotedByGo(t *testing.T) {
	ctx := context.Background()
	status, err := DetectRRuntime(ctx)
	if err != nil || !status.Available {
		t.Skipf("Rscript unavailable: %v", err)
	}

	svc, state := vprotest.ContextServiceFixture(t)
	project20 := "TwentyCharProjectNam"
	if len(project20) != 20 {
		t.Fatalf("expected 20-char project name, got %d", len(project20))
	}

	// Build a 20-char VP08 project database inside the fixture projects root and switch active context to it.
	destDB := filepath.Join(filepath.Dir(state.ProjectPath), project20+".db")
	review, err := svc.ReadNewProjectTemplates(ctx, state.ContextID)
	if err != nil {
		t.Fatalf("ReadNewProjectTemplates: %v", err)
	}
	ddlPlan, err := vprocore.PlanNewProjectDDL(ctx, project20, review)
	if err != nil {
		t.Fatalf("PlanNewProjectDDL: %v", err)
	}
	rwDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(destDB, "rwc")+"&_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		t.Fatal(err)
	}
	for _, tblPlan := range ddlPlan.Tables {
		for _, m := range tblPlan.Schema {
			if m.SQL != nil {
				if _, err := rwDB.ExecContext(ctx, *m.SQL); err != nil {
					rwDB.Close()
					t.Fatalf("create %s: %v", tblPlan.TargetTable, err)
				}
			}
		}
	}
	if _, err := rwDB.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
		rwDB.Close()
		t.Fatal(err)
	}
	for _, sfx := range vprocore.CoreTables {
		if _, err := rwDB.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, project20+"_"+sfx); err != nil {
			rwDB.Close()
			t.Fatal(err)
		}
	}
	if _, err := rwDB.ExecContext(ctx,
		`INSERT INTO "`+project20+`_Env" ("PlotNumber", "Zone", "SubZone") VALUES ('00337', 'SBS', 'dk'), ('108050', 'SBS', 'dk');
		 INSERT INTO "`+project20+`_Admin" ("Plot") VALUES ('00337'), ('108050');
		 INSERT INTO "`+project20+`_Metadata" ("ID", "ProjectID", "ProjectTitle") VALUES (1, 'TWENTY20', 'Twenty Char Roundtrip');`,
	); err != nil {
		rwDB.Close()
		t.Fatal(err)
	}
	rwDB.Close()

	state20, err := svc.SwitchContext(state.ContextID, vprocore.ContextSelection{
		Project:       project20,
		ProjectPath:   destDB,
		SU:            "None",
		SUPath:        "",
		Hierarchy:     "None",
		HierarchyPath: "",
	})
	if err != nil {
		t.Fatalf("SwitchContext to 20-char project: %v", err)
	}

	// Invoke R vpro_write_su(..., candidate = TRUE) on the 20-char project.
	rPkgDir := filepath.Clean(filepath.Join(resources.RepoRoot(), "..", "r"))
	tmpData := t.TempDir()
	tmpCfg := t.TempDir()
	rExpr := `pkgload::load_all(commandArgs(TRUE)[[1]], quiet = TRUE); ` +
		`ws <- vpro_connect(commandArgs(TRUE)[[2]], data_dir = commandArgs(TRUE)[[3]], config_dir = commandArgs(TRUE)[[4]]); ` +
		`df <- data.frame(PlotNumber = c("00337", "108050"), SiteUnit = c("CL_01", "CL_02"), stringsAsFactors = FALSE); ` +
		`res <- vpro_write_su(ws, df, candidate = TRUE, actor = "r_roundtrip"); ` +
		`cat(res$table)`
	cmd := exec.CommandContext(ctx, status.RscriptPath, "--vanilla", "-e", rExpr, rPkgDir, destDB, tmpData, tmpCfg)
	cmd.Env = append(os.Environ(), "VPRO_DATA_DIR="+tmpData, "VPRO_CONFIG_DIR="+tmpCfg)
	outBytes, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("R vpro_write_su failed: %v\noutput:\n%s", err, string(outBytes))
	}

	const wantCandTable = "TwentyCharProj_ClusterCandidate_SU"
	const wantCandPrefix = "TwentyCharProj_ClusterCandidate"
	if string(outBytes) != wantCandTable {
		t.Fatalf("R wrote candidate table %q, want %q", string(outBytes), wantCandTable)
	}
	if !vprocore.ProjectNamePattern.MatchString(wantCandPrefix) {
		t.Fatalf("ProjectNamePattern rejected %q", wantCandPrefix)
	}

	// Verify R did not create __VPRO_IdentitySeq and recorded NULL in <Project>_Audit.ID.
	roDB, err := sqlutil.OpenReadOnly(destDB)
	if err != nil {
		t.Fatal(err)
	}
	var seqCount int
	if err := roDB.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name = '__VPRO_IdentitySeq'`).Scan(&seqCount); err != nil || seqCount != 0 {
		roDB.Close()
		t.Fatalf("expected 0 __VPRO_IdentitySeq tables, got %d (err=%v)", seqCount, err)
	}
	var auditID sql.NullInt64
	if err := roDB.QueryRow(`SELECT "ID" FROM "` + project20 + `_Audit" WHERE "EditField" = 'MaterializeClusterCandidate'`).Scan(&auditID); err != nil {
		roDB.Close()
		t.Fatalf("query audit row: %v", err)
	}
	roDB.Close()
	if auditID.Valid {
		t.Fatalf("expected NULL Audit.ID on R MaterializeClusterCandidate row, got %d", auditID.Int64)
	}

	// Verify Go PromoteClusterCandidateToSU accepts, promotes, and activates the R-written candidate SU table!
	promoted, err := PromoteClusterCandidateToSU(ctx, svc, state20.ContextID, PromoteCandidateSURequest{
		CandidateSUName:  wantCandTable,
		TargetSUName:     "TwentyCharPromoted",
		ExcludeNoise:     true,
		ConfirmOverwrite: false,
		Activate:         true,
	})
	if err != nil {
		t.Fatalf("PromoteClusterCandidateToSU rejected R candidate table %s: %v", wantCandTable, err)
	}
	if !promoted.Activated || promoted.PromotedRows != 2 || promoted.TargetTableName != "TwentyCharPromoted_SU" {
		t.Fatalf("unexpected promotion result: %+v", promoted)
	}
}
