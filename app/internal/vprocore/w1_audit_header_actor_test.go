package vprocore_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/boostao/vpro/app/resources"
	"go.yaml.in/yaml/v3"
)

// UX-ADMIN-002 / UX-ENV-001: shipped defaults audit NULL<->value transitions.
func TestW1DefaultAuditStrengthIsThree(t *testing.T) {
	if got := vprocore.NewPlotService(nil).AuditStrength; got != 3 {
		t.Fatalf("NewPlotService AuditStrength = %d, want 3", got)
	}
	var config struct {
		Audit struct {
			AuditStrength int `yaml:"AuditStrength"`
		} `yaml:"Audit"`
	}
	if err := yaml.Unmarshal(resources.ConfigInitYML, &config); err != nil {
		t.Fatal(err)
	}
	if config.Audit.AuditStrength != 3 {
		t.Fatalf("config.init.yml Audit.AuditStrength = %d, want 3", config.Audit.AuditStrength)
	}
}

type w1AuditRow struct {
	User, Table, Field string
	Before, After      sql.NullString
}

func w1AuditRows(t *testing.T, path, project, plot string) []w1AuditRow {
	t.Helper()
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(path, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT "User","Table","EditField","BeforeEdit","AfterEdit" FROM "`+project+`_Audit"
		WHERE PlotNumber = ? ORDER BY rowid`, plot)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []w1AuditRow
	for rows.Next() {
		var row w1AuditRow
		if err := rows.Scan(&row.User, &row.Table, &row.Field, &row.Before, &row.After); err != nil {
			t.Fatal(err)
		}
		out = append(out, row)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

// UX-ADMIN-001 + UX-ENV-001: the actor chosen in User Setup is the actor on
// every later audit row, plot creation audits PlotNumber/Plot, and NULL->value
// header edits are audited under the shipped default strength.
func TestW1SetUserNameDrivesAuditActorAndCreationAudits(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()
	if err := svc.Plots.SetAuditStrength(3); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetUserName(ctx, state.ContextID, "QA_Ecologist_1"); err != nil {
		t.Fatalf("SetUserName: %v", err)
	}
	setup, err := svc.GetUserSetup(ctx, state.ContextID)
	if err != nil || setup.UserName != "QA_Ecologist_1" {
		t.Fatalf("GetUserSetup = %+v, %v; want QA_Ecologist_1", setup, err)
	}

	const plot = "QAUD01"
	surveyor := "Tester"
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: plot, Surveyor: &surveyor}); err != nil {
		t.Fatalf("CreatePlot: %v", err)
	}
	created := w1AuditRows(t, state.ProjectPath, state.ActiveProject, plot)
	seen := map[string]bool{}
	for _, row := range created {
		if row.User != "QA_Ecologist_1" {
			t.Fatalf("creation audit actor = %q, want QA_Ecologist_1", row.User)
		}
		seen[row.Table+"."+row.Field] = true
		if (row.Field == "PlotNumber" || row.Field == "Plot") && (row.Before.Valid || row.After.String != plot) {
			t.Fatalf("identity audit %+v; want NULL -> %s", row, plot)
		}
	}
	for _, key := range []string{"_Env.PlotNumber", "_Admin.Plot", "_Env.SiteSurveyor"} {
		if !seen[key] {
			t.Fatalf("plot creation missing audit %s; got %+v", key, created)
		}
	}

	header, err := svc.GetPlot(ctx, state.ContextID, plot)
	if err != nil {
		t.Fatal(err)
	}
	sheet := "093O"
	header.MapSheet = &sheet
	if err := svc.UpdatePlot(state.ContextID, *header); err != nil {
		t.Fatalf("UpdatePlot: %v", err)
	}
	updated := w1AuditRows(t, state.ProjectPath, state.ActiveProject, plot)
	if len(updated) != len(created)+1 {
		t.Fatalf("NULL -> value edit wrote %d audit rows, want 1", len(updated)-len(created))
	}
	last := updated[len(updated)-1]
	if last.Field != "NtsMapSheet" || last.Before.Valid || last.After.String != sheet || last.User != "QA_Ecologist_1" {
		t.Fatalf("NULL -> value audit = %+v", last)
	}
}
