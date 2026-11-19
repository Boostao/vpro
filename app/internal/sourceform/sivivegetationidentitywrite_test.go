package sourceform

import (
	"context"
	"database/sql"
	"strconv"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func siviIdentityWriteTestFixture(t *testing.T, strength int) (*vprocore.ContextService, vprocore.ProjectState, *sql.DB, string) {
	t.Helper()
	service, state := vprotest.ReportServiceFixture(t, false)
	if err := service.Plots.SetAuditStrength(strength); err != nil {
		t.Fatal(err)
	}
	if err := service.Plots.SetCurrentUser("QA_Auditor"); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(service.Projects.Sqlite.Attachments["project"], "rw"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := db.Close(); err != nil {
			t.Error(err)
		}
	})
	inserted, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID,Cover1,HeightA) VALUES ('108050','RAW',10000001,0,2)`)
	if err != nil {
		t.Fatal(err)
	}
	rid, err := inserted.LastInsertId()
	if err != nil {
		t.Fatal(err)
	}
	return service, state, db, strconv.FormatInt(rid, 10)
}

// ENG-GO-004: verify WriteSIVIIdentities and RestoreSIVIIdentities across NULL -> value,
// value -> value, and value -> NULL transitions under AuditStrength 0, 1, 2, and 3,
// and across both AuditRestoreRetain and AuditRestorePrune.
func TestWriteAndRestoreSIVIIdentitiesAuditMatrix(t *testing.T) {
	type transitionCase struct {
		name           string
		initialNull    bool
		expectedBefore vprocore.ProjectMetadataCell
		targetAfter    vprocore.ProjectMetadataCell
		wantBeforeEdit sql.NullString
		wantAfterEdit  sql.NullString
		wantAuditID    int64
		auditedAt      map[int]bool
	}
	cases := []transitionCase{
		{
			name:           "null_to_value",
			initialNull:    true,
			expectedBefore: vprocore.ProjectMetadataCell{Storage: "null"},
			targetAfter:    vprotest.MetadataInteger("42"),
			wantBeforeEdit: sql.NullString{Valid: false},
			wantAfterEdit:  sql.NullString{String: "42", Valid: true},
			wantAuditID:    42,
			auditedAt:      map[int]bool{2: true, 3: true},
		},
		{
			name:           "value_to_value",
			initialNull:    false,
			expectedBefore: vprotest.MetadataInteger("10000001"),
			targetAfter:    vprotest.MetadataInteger("-42"),
			wantBeforeEdit: sql.NullString{String: "10000001", Valid: true},
			wantAfterEdit:  sql.NullString{String: "-42", Valid: true},
			wantAuditID:    10000001,
			auditedAt:      map[int]bool{1: true, 2: true, 3: true},
		},
		{
			name:           "value_to_null",
			initialNull:    false,
			expectedBefore: vprotest.MetadataInteger("10000001"),
			targetAfter:    vprocore.ProjectMetadataCell{Storage: "null"},
			wantBeforeEdit: sql.NullString{String: "10000001", Valid: true},
			wantAfterEdit:  sql.NullString{Valid: false},
			wantAuditID:    10000001,
			auditedAt:      map[int]bool{3: true},
		},
	}

	for _, tc := range cases {
		for _, strength := range []int{0, 1, 2, 3} {
			for _, action := range []vprocore.AuditRestoreAction{vprocore.AuditRestoreRetain, vprocore.AuditRestorePrune} {
				name := tc.name + "/strength_" + strconv.Itoa(strength) + "/" + string(action)
				t.Run(name, func(t *testing.T) {
					service, state, db, rowID := siviIdentityWriteTestFixture(t, strength)
					if tc.initialNull {
						if _, err := db.Exec(`UPDATE Sample_Veg SET ID=NULL WHERE rowid=?`, rowID); err != nil {
							t.Fatal(err)
						}
					}
					original, err := ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
					if err != nil {
						t.Fatal(err)
					}
					auditBefore := vprotest.HeightTableSnapshot(t, db, "Sample_Audit")
					vegBefore := vprotest.HeightTableSnapshot(t, db, "Sample_Veg")

					res, err := WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []SiviHeightEdit{
						{RowID: rowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: tc.expectedBefore, Value: tc.targetAfter},
					})
					if err != nil || res == nil || res.ChangedCells != 1 || res.HistoryID == "" {
						t.Fatalf("WriteSIVIIdentities failed: res=%+v err=%v", res, err)
					}

					expectAudit := tc.auditedAt[strength]
					if !expectAudit {
						if got := vprotest.HeightTableSnapshot(t, db, "Sample_Audit"); got != auditBefore {
							t.Fatalf("expected zero Sample_Audit changes at strength %d for %s", strength, tc.name)
						}
					} else {
						var user, tbl, field string
						var beforeEdit, afterEdit sql.NullString
						var restoreFlag, flag int64
						var auditID sql.NullInt64
						if err := db.QueryRow(`SELECT "User","Table","EditField","BeforeEdit","AfterEdit",CAST("Restore" AS INTEGER),CAST("Flag" AS INTEGER),"ID"
							FROM Sample_Audit WHERE PlotNumber='108050' AND EditField='ID'`).
							Scan(&user, &tbl, &field, &beforeEdit, &afterEdit, &restoreFlag, &flag, &auditID); err != nil {
							t.Fatalf("query inserted ID audit row: %v", err)
						}
						if user != "QA_Auditor" || tbl != "_Veg" || field != "ID" ||
							beforeEdit != tc.wantBeforeEdit || afterEdit != tc.wantAfterEdit ||
							restoreFlag != 0 || flag != 0 || !auditID.Valid || auditID.Int64 != tc.wantAuditID {
							t.Fatalf("unexpected audit row: user=%q tbl=%q field=%q before=%+v after=%+v restore=%d flag=%d id=%+v",
								user, tbl, field, beforeEdit, afterEdit, restoreFlag, flag, auditID)
						}
					}

					wantPruned := 0
					if expectAudit && action == vprocore.AuditRestorePrune {
						wantPruned = 1
					}
					restored, err := RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", res.HistoryID, action)
					if err != nil || restored == nil || restored.RestoredRows != 1 || restored.PrunedAuditRows != wantPruned {
						t.Fatalf("RestoreSIVIIdentities failed: restored=%+v wantPruned=%d err=%v", restored, wantPruned, err)
					}
					if got := vprotest.HeightTableSnapshot(t, db, "Sample_Veg"); got != vegBefore {
						t.Fatalf("Sample_Veg did not round-trip back to original state")
					}
					if !expectAudit || action == vprocore.AuditRestorePrune {
						if got := vprotest.HeightTableSnapshot(t, db, "Sample_Audit"); got != auditBefore {
							t.Fatalf("expected Sample_Audit to match initial snapshot after %s", action)
						}
					} else {
						var restoreFlag int64
						if err := db.QueryRow(`SELECT CAST("Restore" AS INTEGER) FROM Sample_Audit WHERE PlotNumber='108050' AND EditField='ID'`).Scan(&restoreFlag); err != nil || restoreFlag != -1 {
							t.Fatalf("expected Restore=-1 on retained audit row, got %d (err=%v)", restoreFlag, err)
						}
					}
				})
			}
		}
	}
}

func TestRestoreSIVIIdentitiesRefusesTamperedAuditAndRollsBackTriggerFailure(t *testing.T) {
	service, state, db, rowID := siviIdentityWriteTestFixture(t, 3)
	original, err := ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
	if err != nil {
		t.Fatal(err)
	}
	res, err := WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []SiviHeightEdit{
		{RowID: rowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("77")},
	})
	if err != nil {
		t.Fatal(err)
	}

	// Abort trigger on Sample_Audit during retain must roll back physical Veg.ID restoration too.
	if _, err := db.Exec(`CREATE TRIGGER block_audit_retain BEFORE UPDATE OF Restore ON Sample_Audit BEGIN SELECT RAISE(ABORT,'audit locked'); END`); err != nil {
		t.Fatal(err)
	}
	beforeAbort := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if got, err := RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", res.HistoryID, vprocore.AuditRestoreRetain); err == nil || got != nil {
		t.Fatalf("expected audit trigger abort to roll back restoration, got=%+v err=%v", got, err)
	}
	vprotest.AssertProfileSUFiles(t, service, beforeAbort)
	if _, err := db.Exec(`DROP TRIGGER block_audit_retain`); err != nil {
		t.Fatal(err)
	}

	// Mutating AfterEdit in Sample_Audit must block restoration.
	if _, err := db.Exec(`UPDATE Sample_Audit SET AfterEdit='999' WHERE PlotNumber='108050' AND EditField='ID'`); err != nil {
		t.Fatal(err)
	}
	beforeTampered := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if got, err := RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", res.HistoryID, vprocore.AuditRestorePrune); err == nil || got != nil {
		t.Fatalf("expected tampered Sample_Audit row to block restoration, got=%+v err=%v", got, err)
	}
	vprotest.AssertProfileSUFiles(t, service, beforeTampered)

	// Restoring exact Sample_Audit row allows clean restoration.
	if _, err := db.Exec(`UPDATE Sample_Audit SET AfterEdit='77' WHERE PlotNumber='108050' AND EditField='ID'`); err != nil {
		t.Fatal(err)
	}
	if got, err := RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", res.HistoryID, vprocore.AuditRestorePrune); err != nil || got == nil || got.RestoredRows != 1 || got.PrunedAuditRows != 1 {
		t.Fatalf("expected clean retry after Sample_Audit repair, got=%+v err=%v", got, err)
	}
}
