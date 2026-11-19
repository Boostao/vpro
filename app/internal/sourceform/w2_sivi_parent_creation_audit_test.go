package sourceform_test

import (
	"context"
	"database/sql"
	"strconv"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestW2ValidateSIVIPlotIdentityAndLiteralWriteJoin(t *testing.T) {
	validPlots := []string{
		"00337",
		"337",
		"PLOT-01",
		"P_01",
		"😀😀😀A", // 3*2 + 1 = 7 UTF-16 code units
		"é",
		"e\u0301",
		" 00337", // leading space
		"A B",
		"a1",
		"A1",
		"108050X",
	}
	for _, plot := range validPlots {
		if err := sourceform.ValidateSIVIPlotIdentity(plot); err != nil {
			t.Fatalf("ValidateSIVIPlotIdentity(%q) unexpected error: %v", plot, err)
		}
	}

	invalidPlots := []string{
		"",
		"   ",
		"12345678",   // 8 ASCII UTF-16 units
		"😀😀😀😀",       // 4*2 = 8 UTF-16 units
		"PLOT\x0001", // NUL byte
		"PLOT\n01",   // newline control rune
		"PLOT\t01",   // tab control rune
		"PLOT\x7f",   // DEL control rune
		string([]byte{0xff, 0xfe}),
	}
	for _, plot := range invalidPlots {
		if err := sourceform.ValidateSIVIPlotIdentity(plot); err == nil {
			t.Fatalf("ValidateSIVIPlotIdentity(%q) unexpectedly succeeded", plot)
		}
	}

	service, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env(PlotNumber) VALUES ('PLOT-01'),('P_01'),('😀😀😀A'),(' 00337'),('337'),('a1'),('A1');
		INSERT INTO Sample_Admin(Plot) VALUES ('PLOT-01'),('P_01'),('😀😀😀A'),(' 00337'),('337'),('a1'),('A1');
	`)

	for _, plot := range []string{"00337", "337", "PLOT-01", "P_01", "😀😀😀A", " 00337", "a1", "A1"} {
		join, err := vprocore.WithContextPlotRequest(ctx, service, state.ContextID, func(plots *vprocore.PlotService) (*sourceform.SIVIParentJoinReview, error) {
			return sourceform.ReadOwnedSIVIParentWriteJoin(ctx, plots, state.ContextID, plot)
		})
		if err != nil {
			t.Fatalf("ReadOwnedSIVIParentWriteJoin(%q) error: %v", plot, err)
		}
		if !join.Verified || len(join.EnvRowIDs) != 1 || len(join.AdminRowIDs) != 1 {
			t.Fatalf("ReadOwnedSIVIParentWriteJoin(%q) not verified: %+v", plot, join)
		}
	}

	for _, bad := range invalidPlots {
		join, err := vprocore.WithContextPlotRequest(ctx, service, state.ContextID, func(plots *vprocore.PlotService) (*sourceform.SIVIParentJoinReview, error) {
			return sourceform.ReadOwnedSIVIParentWriteJoin(ctx, plots, state.ContextID, bad)
		})
		if err != nil {
			t.Fatalf("ReadOwnedSIVIParentWriteJoin(%q) unexpected hard error: %v", bad, err)
		}
		if join.Verified {
			t.Fatalf("ReadOwnedSIVIParentWriteJoin(%q) unexpectedly verified: %+v", bad, join)
		}
	}

	// Trailing-space alias on PLOT-01 rejects PLOT-01 without breaking 00337.
	vprotest.MutateContextFixture(t, state.ProjectPath, `DROP INDEX IF EXISTS uidx_Sample_Admin_PlotNumber; INSERT INTO Sample_Admin(Plot) VALUES ('P_01 ')`)
	aliasJoin, err := vprocore.WithContextPlotRequest(ctx, service, state.ContextID, func(plots *vprocore.PlotService) (*sourceform.SIVIParentJoinReview, error) {
		return sourceform.ReadOwnedSIVIParentWriteJoin(ctx, plots, state.ContextID, "P_01")
	})
	if err != nil || aliasJoin.Verified {
		t.Fatalf("trailing-space alias 'P_01 ' was not rejected: %+v, err=%v", aliasJoin, err)
	}
	unrelatedJoin, err := vprocore.WithContextPlotRequest(ctx, service, state.ContextID, func(plots *vprocore.PlotService) (*sourceform.SIVIParentJoinReview, error) {
		return sourceform.ReadOwnedSIVIParentWriteJoin(ctx, plots, state.ContextID, "00337")
	})
	if err != nil || !unrelatedJoin.Verified {
		t.Fatalf("trailing-space alias on P_01 broke unrelated 00337: %+v, err=%v", unrelatedJoin, err)
	}
}

func TestW2SIVIParentWriteHyphenUnicodeLeadingSpaceAndCaseVariants(t *testing.T) {
	service, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw")+"&_busy_timeout=5000&_txlock=immediate")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	specialPlots := []string{"PLOT-01", "P_01", "😀😀😀A", "é", " 00337", "337", "a1", "A1"}
	for _, p := range specialPlots {
		if _, err := db.Exec(`INSERT INTO Sample_Env(PlotNumber, SV_FloodPlain) VALUES (?, 0)`, p); err != nil {
			t.Fatalf("insert Sample_Env(%q): %v", p, err)
		}
		if _, err := db.Exec(`INSERT INTO Sample_Admin(Plot, PlotType) VALUES (?, 'Ground')`, p); err != nil {
			t.Fatalf("insert Sample_Admin(%q): %v", p, err)
		}
		if state.ActiveSU != "" && state.ActiveSU != "None" {
			suTable := vprocore.QuoteHeaderIdentifier(state.ActiveSU + "_SU")
			if _, err := db.Exec(`INSERT INTO `+suTable+`(PlotNumber, SiteUnit) VALUES (?, '01')`, p); err != nil {
				t.Fatalf("insert %s(%q): %v", suTable, p, err)
			}
		}
	}
	// Ensure 00337 is in active SU if an SU is active so we test the exact UX-ENV-002 repro on 00337 too.
	if state.ActiveSU != "" && state.ActiveSU != "None" {
		suTable := vprocore.QuoteHeaderIdentifier(state.ActiveSU + "_SU")
		var inSU bool
		if err := db.QueryRow(`SELECT EXISTS(SELECT 1 FROM ` + suTable + ` WHERE typeof(PlotNumber)='text' AND CAST(PlotNumber AS BLOB)=CAST('00337' AS BLOB))`).Scan(&inSU); err != nil {
			t.Fatal(err)
		}
		if !inSU {
			if _, err := db.Exec(`INSERT INTO ` + suTable + `(PlotNumber, SiteUnit) VALUES ('00337', '01')`); err != nil {
				t.Fatal(err)
			}
		}
	}

	targets := []string{"00337", "PLOT-01", "P_01", "😀😀😀A", "é", " 00337", "a1", "A1"}
	for _, target := range targets {
		parent, err := sourceform.ReadSIVIParent(service, ctx, state.ContextID, target)
		if err != nil {
			t.Fatalf("ReadSIVIParent(%q): %v", target, err)
		}
		if len(parent.Rows) != 1 {
			t.Fatalf("ReadSIVIParent(%q) rows = %d, want 1", target, len(parent.Rows))
		}
		drafts := sourceform.SiviParentDirectEdits{
			Scalars: []sourceform.SourceParentScalarEdit{
				sftest.SiviParentEdit(t, parent, "SV_FloodPlain", vprotest.MetadataInteger("-1")),
			},
		}
		res, err := sourceform.WriteSIVIParentDirect(service, ctx, state.ContextID, target, parent, drafts)
		if err != nil {
			t.Fatalf("WriteSIVIParentDirect(%q): %v", target, err)
		}
		if res == nil || res.ChangedCells != 1 || res.HistoryID == "" {
			t.Fatalf("WriteSIVIParentDirect(%q) unexpected result: %+v", target, res)
		}

		// Verify exact literal persistence in Sample_Env and Sample_Audit.
		var floodPlain int64
		if err := db.QueryRow(
			`SELECT CAST(SV_FloodPlain AS INTEGER) FROM Sample_Env WHERE typeof(PlotNumber)='text' AND CAST(PlotNumber AS BLOB)=CAST(? AS BLOB)`,
			target,
		).Scan(&floodPlain); err != nil || floodPlain != -1 {
			t.Fatalf("Sample_Env(%q).SV_FloodPlain = %d, err=%v; want -1", target, floodPlain, err)
		}

		var auditCount int
		if err := db.QueryRow(
			`SELECT COUNT(*) FROM Sample_Audit WHERE typeof(PlotNumber)='text' AND CAST(PlotNumber AS BLOB)=CAST(? AS BLOB)
			 AND "Table"='_Env' AND EditField='SV_FloodPlain' AND AfterEdit='-1' AND ID IS NULL`,
			target,
		).Scan(&auditCount); err != nil || auditCount != 1 {
			t.Fatalf("Sample_Audit(%q) SV_FloodPlain count = %d, err=%v; want 1", target, auditCount, err)
		}

		// Verify "337" remained untouched when "00337" (and " 00337") were edited!
		if target == "00337" || target == " 00337" {
			var plain337 int64
			if err := db.QueryRow(
				`SELECT CAST(SV_FloodPlain AS INTEGER) FROM Sample_Env WHERE typeof(PlotNumber)='text' AND CAST(PlotNumber AS BLOB)=CAST('337' AS BLOB)`,
			).Scan(&plain337); err != nil || plain337 != 0 {
				t.Fatalf("editing %q mutated '337': SV_FloodPlain=%d, err=%v", target, plain337, err)
			}
		}

		// Verify typed SIVI parent restoration also succeeds on literal Text-7 identities.
		restored, err := sourceform.CtxRestoreSIVIParentDirect(service, ctx, state.ContextID, target, res.HistoryID, vprocore.AuditRestoreRetain)
		if err != nil || restored == nil || restored.RestoredRows != 1 {
			t.Fatalf("CtxRestoreSIVIParentDirect(%q): res=%+v, err=%v", target, restored, err)
		}
	}
}

func TestW2SIVICreationDefaultConfigAndAuditStrengthMatrix(t *testing.T) {
	ctx := context.Background()

	// 1. Default ContextServiceFixture config (verifies fresh config.yml AuditStrength == 3 without SetAuditStrength).
	defaultSvc, defaultState := vprotest.ContextServiceFixture(t)
	if defaultSvc.Plots.AuditStrength != 3 {
		t.Fatalf("default ContextServiceFixture AuditStrength = %d, want 3", defaultSvc.Plots.AuditStrength)
	}
	selection := vprotest.ContextSelection(defaultState)
	selection.SU, selection.SUPath = "None", ""
	unfiltered, err := defaultSvc.SwitchContext(defaultState.ContextID, selection)
	if err != nil {
		t.Fatal(err)
	}
	req := sourceform.SiviCreationRequest{
		RequestID: "00000000-0000-4000-8000-000000000201",
		ContextID: unfiltered.ContextID,
		Project:   unfiltered.ActiveProject,
		Plot:      "00337",
		Form:      "SubVegA-SIVI_BC",
		Species:   "ABIEAMA",
		Covers:    []sourceform.SiviCreationCover{{Column: "Cover1", Value: vprotest.SiviReal(15)}},
	}
	created, err := sourceform.CreateSIVIVegetation(defaultSvc, ctx, unfiltered.ContextID, req)
	if err != nil || created == nil || !created.DidCommit || created.AuditStrength != 3 {
		t.Fatalf("default CreateSIVIVegetation failed: res=%+v, err=%v", created, err)
	}

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(unfiltered.ProjectPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	rows, err := db.Query(
		`SELECT EditField, BeforeEdit, AfterEdit FROM Sample_Audit
		 WHERE typeof(PlotNumber)='text' AND CAST(PlotNumber AS BLOB)=CAST('00337' AS BLOB)
		 AND "Table"='_Veg' AND ID=? ORDER BY rowid`,
		created.ID,
	)
	if err != nil {
		t.Fatal(err)
	}
	gotFields := map[string]string{}
	for rows.Next() {
		var field string
		var before, after sql.NullString
		if err := rows.Scan(&field, &before, &after); err != nil {
			rows.Close()
			t.Fatal(err)
		}
		if before.Valid {
			rows.Close()
			t.Fatalf("creation audit %s BeforeEdit = %q, want NULL", field, before.String)
		}
		gotFields[field] = after.String
	}
	if err := rows.Close(); err != nil {
		t.Fatal(err)
	}
	if len(gotFields) != 2 || gotFields["Species"] != "ABIEAMA" || gotFields["Cover1"] != "15" {
		t.Fatalf("default SIVI creation Sample_Audit fields = %+v, want Species=ABIEAMA and Cover1=15", gotFields)
	}

	// 2. Explicit AuditStrength matrix (0 -> 0 audits; 1, 2, 3 -> creation audits for Species + Cover1).
	for _, strength := range []int{0, 1, 2, 3} {
		t.Run("strength_"+strconv.Itoa(strength), func(t *testing.T) {
			svc, state, projDB, fixtureReq := sftest.SiviCreationFixture(t, false, strength)
			fixtureReq.RequestID = "00000000-0000-4000-8000-00000000030" + strconv.Itoa(strength)
			fixtureReq.Covers = []sourceform.SiviCreationCover{{Column: "Cover1", Value: vprotest.SiviReal(15)}}
			res, err := sourceform.CreateSIVIVegetation(svc, ctx, state.ContextID, fixtureReq)
			if err != nil || res == nil || res.AuditStrength != strength {
				t.Fatalf("CreateSIVIVegetation(strength=%d): res=%+v, err=%v", strength, res, err)
			}
			var count int
			var fieldsCSV sql.NullString
			if err := projDB.QueryRow(
				`SELECT COUNT(*), GROUP_CONCAT(EditField, ',') FROM Sample_Audit WHERE "Table"='_Veg' AND ID=?`,
				res.ID,
			).Scan(&count, &fieldsCSV); err != nil {
				t.Fatal(err)
			}
			wantCount := 2
			if strength == 0 {
				wantCount = 0
			}
			if count != wantCount {
				t.Fatalf("strength=%d Sample_Audit count = %d (%q), want %d", strength, count, fieldsCSV.String, wantCount)
			}
			if strength >= 1 && (!strings.Contains(fieldsCSV.String, "Species") || !strings.Contains(fieldsCSV.String, "Cover1")) {
				t.Fatalf("strength=%d Sample_Audit fields = %q, want Species and Cover1", strength, fieldsCSV.String)
			}
			// Verify LookupSIVICreationReceipt & idempotent replay verify audit completeness cleanly.
			lookup, err := sourceform.LookupSIVICreationReceipt(svc, ctx, state.ContextID, fixtureReq)
			if err != nil || lookup == nil || !lookup.Replayed || lookup.ID != res.ID {
				t.Fatalf("LookupSIVICreationReceipt(strength=%d): lookup=%+v, err=%v", strength, lookup, err)
			}
		})
	}
}
