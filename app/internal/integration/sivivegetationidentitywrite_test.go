package integration

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/projectops"
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSIVIIdentityOwnedSaveUnauditedAtEveryStrengthAndTypedRestoration(t *testing.T) {
	for strength := 0; strength <= 3; strength++ {
		t.Run(strconv.Itoa(strength), func(t *testing.T) {
			service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, strength%2 == 0, strength)
			rowID := heightEdits[0].RowID
			var physicalBefore string
			if err := db.QueryRow(`SELECT CAST(rowid AS TEXT) FROM Sample_Veg WHERE ID=10000001`).Scan(&physicalBefore); err != nil {
				t.Fatal(err)
			}
			audit := vprotest.HeightTableSnapshot(t, db, "Sample_Audit")
			veg := vprotest.HeightTableSnapshot(t, db, "Sample_Veg")
			edits := []sourceform.SiviHeightEdit{{RowID: rowID, Form: "SubVegC-SIVI", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-2147483648")}}
			result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, edits)
			if err != nil || result == nil || result.ChangedCells != 1 || result.HistoryID == "" {
				t.Fatal("private identity save failed", result, err)
			}
			var id int64
			var physicalAfter string
			if err := db.QueryRow(`SELECT ID,CAST(rowid AS TEXT) FROM Sample_Veg WHERE rowid=?`, rowID).Scan(&id, &physicalAfter); err != nil ||
				id != -2147483648 || physicalBefore != physicalAfter {
				t.Fatal("application ID assignment changed physical row", id, physicalBefore, physicalAfter, err)
			}
			if strength == 0 {
				if got := vprotest.HeightTableSnapshot(t, db, "Sample_Audit"); got != audit {
					t.Fatal("strength 0 identity save wrote an unexpected audit row")
				}
			} else {
				var count int
				var beforeEdit, afterEdit string
				var restoreFlag, auditID int64
				if err := db.QueryRow(`SELECT COUNT(*), COALESCE(MAX(BeforeEdit),''), COALESCE(MAX(AfterEdit),''), COALESCE(MAX(CAST(Restore AS INTEGER)),-99), COALESCE(MAX(ID),0)
					FROM Sample_Audit WHERE PlotNumber='108050' AND "Table"='_Veg' AND EditField='ID'`).
					Scan(&count, &beforeEdit, &afterEdit, &restoreFlag, &auditID); err != nil ||
					count != 1 || beforeEdit != "10000001" || afterEdit != "-2147483648" || restoreFlag != 0 || auditID != 10000001 {
					t.Fatal("audited identity save did not record exact _Veg.ID provenance", count, beforeEdit, afterEdit, restoreFlag, auditID, err)
				}
			}
			var reservations int
			if err := db.QueryRow(`SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE ChildTable='"Sample_Veg"' AND ID IN (10000001,-2147483648)`).Scan(&reservations); err != nil || reservations != 2 {
				t.Fatal("old/new identities were not permanently reserved", reservations, err)
			}
			action := vprocore.AuditRestoreRetain
			expectedPruned := 0
			if strength%2 == 0 {
				action = vprocore.AuditRestorePrune
				if strength > 0 {
					expectedPruned = 1
				}
			}
			restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, action)
			if err != nil || restored == nil || restored.RestoredRows != 1 || restored.PrunedAuditRows != expectedPruned || restored.CleanedVegRows != 0 {
				t.Fatal("identity restoration returned unexpected audit/row counts", restored, expectedPruned, err)
			}
			if got := vprotest.HeightTableSnapshot(t, db, "Sample_Veg"); got != veg {
				t.Fatal("typed identity restoration did not preserve the complete original table")
			}
			if strength == 0 || action == vprocore.AuditRestorePrune {
				if got := vprotest.HeightTableSnapshot(t, db, "Sample_Audit"); got != audit {
					t.Fatal("unaudited or pruned identity restoration left residual audit changes")
				}
			} else {
				var restoreFlag int64
				if err := db.QueryRow(`SELECT CAST(Restore AS INTEGER) FROM Sample_Audit WHERE PlotNumber='108050' AND "Table"='_Veg' AND EditField='ID'`).Scan(&restoreFlag); err != nil || restoreFlag != -1 {
					t.Fatal("retained identity restoration did not mark Restore=-1", restoreFlag, err)
				}
			}
			beforeRetry := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
			if again, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, action); err == nil || again != nil {
				t.Fatal("completed identity restoration replayed", again, err)
			}
			vprotest.AssertProfileSUFiles(t, service, beforeRetry)
		})
	}
}

func TestSIVIIdentityOwnedNULLAndHistoricalDuplicateRestoration(t *testing.T) {
	for _, target := range []vprocore.ProjectMetadataCell{{Storage: "null"}, vprotest.MetadataInteger("2147483647")} {
		service, state, db, _, heightEdits := sftest.SiviWriteFixture(t, false, 3)
		rowID := heightEdits[0].RowID
		if _, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID,Cover9) VALUES('108050','DUP',10000001,0)`); err != nil {
			t.Fatal(err)
		}
		original, err := sourceform.ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
		if err != nil {
			t.Fatal(err)
		}
		veg := vprotest.HeightTableSnapshot(t, db, "Sample_Veg")
		result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
			[]sourceform.SiviHeightEdit{{RowID: rowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: target}})
		if err != nil || result == nil {
			t.Fatal("physical identity editor inherited ambiguous application-ID targeting", result, err)
		}
		var storage string
		if err := db.QueryRow(`SELECT typeof(ID) FROM Sample_Veg WHERE rowid=?`, rowID).Scan(&storage); err != nil || storage != target.Storage {
			t.Fatal("nullable identity storage changed", storage, err)
		}
		restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune)
		if err != nil || restored == nil || restored.RestoredRows != 1 || vprotest.HeightTableSnapshot(t, db, "Sample_Veg") != veg {
			t.Fatal("unchanged historical duplicate could not be safely restored", restored, err)
		}
	}
}

func TestSIVIIdentityOwnedRejectsStaleCollisionReservationAndCancelledRequests(t *testing.T) {
	service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	rowID := heightEdits[0].RowID
	valid := sourceform.SiviHeightEdit{RowID: rowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("2147483647")}
	// Both aliases are reserved, including an ID belonging only to a deleted row.
	if _, err := db.Exec(`INSERT INTO Sample_Audit("Table",ID) VALUES('_vEg',2147483647),('SAMPLE_VEG',-2147483648)`); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"2147483647", "-2147483648"} {
		edit := valid
		edit.Value = vprotest.MetadataInteger(id)
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []sourceform.SiviHeightEdit{edit}); err == nil || result != nil {
			t.Fatal("deleted/audited ID was reassigned", result, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
	}
	if _, err := db.Exec(`DELETE FROM Sample_Audit WHERE ID IN (2147483647,-2147483648)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID) VALUES('outside','COLLIDE',2147483647)`); err != nil {
		t.Fatal(err)
	}
	before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []sourceform.SiviHeightEdit{valid}); err == nil || result != nil {
		t.Fatal("outside-plot/hidden collision was accepted", result, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	if _, err := db.Exec(`DELETE FROM Sample_Veg WHERE Species='COLLIDE'; UPDATE Sample_Veg SET HeightA=9 WHERE rowid=?`, rowID); err != nil {
		t.Fatal(err)
	}
	before = vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []sourceform.SiviHeightEdit{valid}); err == nil || result != nil {
		t.Fatal("complete source CAS overlooked a non-ID drift", result, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if result, err := sourceform.WriteSIVIIdentities(service, ctx, state.ContextID, "108050", false, original, []sourceform.SiviHeightEdit{valid}); result != nil || !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled identity save returned success", result, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), "stale", "108050", false, original, []sourceform.SiviHeightEdit{valid}); err == nil || result != nil {
		t.Fatal("stale owner was granted identity authority", result, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
}

func TestSIVIIdentityOwnedNoopHasNoLedgerHistoryOrAudit(t *testing.T) {
	service, state, _, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
		[]sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("10000001")}})
	if err != nil || result == nil || result.ChangedCells != 0 || result.HistoryID != "" {
		t.Fatal("unchanged identity created a mutation-shaped result", result, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
}

func TestSIVIIdentityOwnedRollsBackTriggerDriftAndRetries(t *testing.T) {
	for _, trigger := range []string{
		`CREATE TRIGGER fail_id AFTER UPDATE OF ID ON Sample_Veg BEGIN UPDATE Sample_Veg SET Species='SIDE' WHERE rowid=NEW.rowid; END`,
		`CREATE TRIGGER fail_id AFTER UPDATE OF ID ON Sample_Veg BEGIN INSERT INTO Sample_Audit("Table",ID) VALUES('_Veg',NEW.ID); END`,
		`CREATE TRIGGER fail_id AFTER UPDATE OF ID ON Sample_Veg BEGIN SELECT RAISE(ABORT,'blocked identity'); END`,
	} {
		service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
		if _, err := db.Exec(trigger); err != nil {
			t.Fatal(err)
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		edits := []sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}}
		if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, edits); err == nil || result != nil {
			t.Fatal("trigger escaped the complete unaudited plan", result, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
		if _, err := db.Exec(`DROP TRIGGER fail_id`); err != nil {
			t.Fatal(err)
		}
		if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, edits); err != nil || result == nil || result.ChangedCells != 1 {
			t.Fatal("rolled-back identity intent could not retry", result, err)
		}
	}
}

func TestSIVIIdentityOwnedRestorationRefusesPeerOccupancyAndFullRowDrift(t *testing.T) {
	for _, mutation := range []string{
		`UPDATE Sample_Veg SET HeightA=99 WHERE ID=-1`,
		`INSERT INTO Sample_Veg(PlotNumber,Species,ID) VALUES('outside','NEWOWNER',10000001)`,
		`UPDATE "__VPRO_SIVIIdentityHistory" SET Proposal=replace(Proposal,'SubVegA-SIVI_BC','SubVegD-SIVI')`,
	} {
		service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
		result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
			[]sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(mutation); err != nil {
			t.Fatal(err)
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune); err == nil || restored != nil {
			t.Fatal("drifted identity history/row/return occupancy was restored", restored, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
	}
}

func TestSIVIIdentityOwnedHistoryStrictTransportAndCancellation(t *testing.T) {
	service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
		[]sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}})
	if err != nil {
		t.Fatal(err)
	}
	var proposal string
	if err := db.QueryRow(`SELECT Proposal FROM "__VPRO_SIVIIdentityHistory" WHERE ID=?`, result.HistoryID).Scan(&proposal); err != nil {
		t.Fatal(err)
	}
	var event sourceform.SiviIdentityHistory
	if err := json.Unmarshal([]byte(proposal), &event); err != nil || len(event.Edits) != 1 {
		t.Fatal("complete typed source plan was not recorded", event, err)
	}
	before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if restored, err := sourceform.RestoreSIVIIdentities(service, ctx, state.ContextID, "108050", result.HistoryID, vprocore.AuditRestoreRetain); restored != nil || !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled restoration returned success", restored, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestoreCancel); err != nil || restored == nil || !restored.Cancelled {
		t.Fatal("explicit restoration cancel failed", restored, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	for _, broken := range []string{
		strings.Replace(proposal, `"Extended":false`, `"Extended":false,"Unknown":true`, 1),
		strings.Replace(proposal, `"rowId":`, `"rowId":null,"missing":`, 1),
		strings.Replace(proposal, `"Plot":"108050"`, `"Plot":"\ud800"`, 1),
	} {
		if broken == proposal {
			t.Fatal("strict history test failed to mutate its actual wire shape")
		}
		if _, err := db.Exec(`UPDATE "__VPRO_SIVIIdentityHistory" SET Proposal=? WHERE ID=?`, broken, result.HistoryID); err != nil {
			t.Fatal(err)
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune); err == nil || restored != nil {
			t.Fatal("malformed/unknown history transport was repaired", restored, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
	}
}

func TestSIVIIdentityOwnedReservationsCannotBeReassignedAfterRestore(t *testing.T) {
	service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	edits := []sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("1")}}
	result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, edits)
	if err != nil {
		t.Fatal(err)
	}

	if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestoreRetain); err != nil || restored == nil {
		t.Fatal(restored, err)
	}
	reloaded, err := sourceform.ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
	if err != nil || !reflect.DeepEqual(reloaded, original) {
		t.Fatal("restored source differs from the original", reloaded, err)
	}
	before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if again, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, reloaded, edits); err == nil || again != nil {
		t.Fatal("restored/released ID was granted to a fresh intent", again, err)
	}
	vprotest.AssertProfileSUFiles(t, service, before)
	var ledger int
	if err := db.QueryRow(`SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE ChildTable='"Sample_Veg"' AND ID=1`).Scan(&ledger); err != nil || ledger != 1 {
		t.Fatal("permanent identity reservation was pruned", ledger, err)
	}
}

func TestSIVIIdentityOwnedBlockedWriteAndRestorationCancellationRetry(t *testing.T) {
	service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	edits := []sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}}
	var historyID string
	for _, restoring := range []bool{false, true} {
		conn, err := db.Conn(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if _, err := conn.ExecContext(context.Background(), "BEGIN EXCLUSIVE"); err != nil {
			conn.Close()
			t.Fatal(err)
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		if restoring {
			result, err := sourceform.RestoreSIVIIdentities(service, ctx, state.ContextID, "108050", historyID, vprocore.AuditRestorePrune)
			if result != nil || !errors.Is(err, context.DeadlineExceeded) {
				t.Error("blocked restoration returned partial/success-shaped result", result, err)
			}
		} else {
			result, err := sourceform.WriteSIVIIdentities(service, ctx, state.ContextID, "108050", false, original, edits)
			if result != nil || !errors.Is(err, context.DeadlineExceeded) {
				t.Error("blocked identity save returned partial/success-shaped result", result, err)
			}
		}
		cancel()
		if _, err := conn.ExecContext(context.Background(), "ROLLBACK"); err != nil {
			t.Error(err)
		}
		if err := conn.Close(); err != nil {
			t.Error(err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
		if restoring {
			if result, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", historyID, vprocore.AuditRestorePrune); err != nil || result == nil {
				t.Fatal("cancelled restoration discarded owner/retry", result, err)
			}
		} else {
			result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, edits)
			if err != nil || result == nil {
				t.Fatal("cancelled save discarded owner/retry", result, err)
			}
			historyID = result.HistoryID
		}
	}
}

func TestSIVIIdentityOwnedOriginalNULLAndExtendedSourceRoundTrip(t *testing.T) {
	service, state, db, _, heightEdits := sftest.SiviWriteFixture(t, false, 0)
	rowID := heightEdits[0].RowID
	if _, err := db.Exec(`UPDATE Sample_Veg SET ID=NULL WHERE rowid=?`, rowID); err != nil {
		t.Fatal(err)
	}
	original, err := sourceform.ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", true)
	if err != nil {
		t.Fatal(err)
	}
	veg := vprotest.HeightTableSnapshot(t, db, "Sample_Veg")
	result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", true, original,
		[]sourceform.SiviHeightEdit{{RowID: rowID, Form: "SubVegA-SIVI", Column: "ID", Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.MetadataInteger("0")}})
	if err != nil || result == nil || result.HistoryID == "" {
		t.Fatal("nullable source ID required an invented old identity", result, err)
	}
	if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestoreRetain); err != nil || restored == nil {
		t.Fatal("original NULL identity did not restore", restored, err)
	}
	if vprotest.HeightTableSnapshot(t, db, "Sample_Veg") != veg {
		t.Fatal("original NULL was replaced by zero or a new physical row")
	}
}

func TestSIVIIdentityOwnedLateHistoryFailureAndLedgerTriggerRollBack(t *testing.T) {
	for _, setup := range []string{
		`CREATE TABLE "__VPRO_SIVIIdentityHistory"(ID INTEGER PRIMARY KEY,Created TEXT,Proposal TEXT,Restored TEXT)`,
		sourceform.SiviIdentityHistorySQL + `; CREATE TRIGGER fail_history BEFORE INSERT ON "__VPRO_SIVIIdentityHistory" BEGIN SELECT RAISE(ABORT,'stop history'); END`,
		`CREATE TABLE "__VPRO_ChildIdentity"(ChildTable TEXT NOT NULL,ID INTEGER NOT NULL,PRIMARY KEY(ChildTable,ID));
			 CREATE TRIGGER fail_reservation AFTER INSERT ON "__VPRO_ChildIdentity" BEGIN UPDATE Sample_Veg SET HeightA=99 WHERE ID=10000001; END`,
	} {
		service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
		if _, err := db.Exec(setup); err != nil {
			t.Fatal(err)
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		if result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
			[]sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}}); err == nil || result != nil {
			t.Fatal("late history/ledger failure escaped rollback", result, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
	}
}

func TestSIVIIdentityOwnedMixedBatchAndUnaffectedAuditedHistory(t *testing.T) {
	service, state, db, original, heightEdits := sftest.SiviWriteFixture(t, false, 3)
	rowID := heightEdits[0].RowID
	// A completed height audit remains owned by that editor, not ID history.
	height, err := sourceform.WriteSIVIHeights(service, context.Background(), state.ContextID, "108050", false, original, heightEdits[:1])
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID,Cover9) VALUES('108050','SECOND',10000002,0)`); err != nil {
		t.Fatal(err)
	}
	original, err = sourceform.ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
	if err != nil {
		t.Fatal(err)
	}
	var second string
	if err := db.QueryRow(`SELECT CAST(rowid AS TEXT) FROM Sample_Veg WHERE ID=10000002`).Scan(&second); err != nil {
		t.Fatal(err)
	}
	audit := vprotest.HeightTableSnapshot(t, db, "Sample_Audit")
	veg := vprotest.HeightTableSnapshot(t, db, "Sample_Veg")
	heightHistory := vprotest.HeightTableSnapshot(t, db, sourceform.SiviHeightHistoryTable)
	result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original, []sourceform.SiviHeightEdit{
		{RowID: rowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")},
		{RowID: second, Form: "SubVegD-SIVI", Column: "ID", Expected: vprotest.MetadataInteger("10000002"), Value: vprocore.ProjectMetadataCell{Storage: "null"}},
	})
	if err != nil || result == nil || result.ChangedCells != 2 {
		t.Fatal("mixed nullable/integer identities were not atomic", result, err)
	}
	blocked := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
	if restored, err := sourceform.RestoreSIVIHeights(service, context.Background(), state.ContextID, "108050", height.HistoryID, vprocore.AuditRestorePrune); err == nil || restored != nil {
		t.Fatal("old editor restored across a changed identity", restored, err)
	}
	vprotest.AssertProfileSUFiles(t, service, blocked)
	if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune); err != nil || restored == nil || restored.RestoredRows != 2 {
		t.Fatal("mixed identities did not restore atomically", restored, err)
	}
	if vprotest.HeightTableSnapshot(t, db, "Sample_Audit") != audit || vprotest.HeightTableSnapshot(t, db, "Sample_Veg") != veg ||
		vprotest.HeightTableSnapshot(t, db, sourceform.SiviHeightHistoryTable) != heightHistory {
		t.Fatal("identity restoration inherited peer audit/history mutations")
	}
	if restored, err := sourceform.RestoreSIVIHeights(service, context.Background(), state.ContextID, "108050", height.HistoryID, vprocore.AuditRestorePrune); err != nil || restored == nil {
		t.Fatal("restored identity prevented separately owned height recovery", restored, err)
	}
}

func TestSIVIIdentityOwnedRestorationRejectsChangedOrReplacedDuplicatePeer(t *testing.T) {
	for _, replace := range []bool{false, true} {
		service, state, db, _, heightEdits := sftest.SiviWriteFixture(t, false, 3)
		inserted, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID,Cover9) VALUES('108050','DUP',10000001,0)`)
		if err != nil {
			t.Fatal(err)
		}
		peer, err := inserted.LastInsertId()
		if err != nil {
			t.Fatal(err)
		}
		original, err := sourceform.ReadSIVIVegetation(service, context.Background(), state.ContextID, "108050", false)
		if err != nil {
			t.Fatal(err)
		}
		result, err := sourceform.WriteSIVIIdentities(service, context.Background(), state.ContextID, "108050", false, original,
			[]sourceform.SiviHeightEdit{{RowID: heightEdits[0].RowID, Form: "SubVegA-SIVI_BC", Column: "ID", Expected: vprotest.MetadataInteger("10000001"), Value: vprotest.MetadataInteger("-1")}})
		if err != nil {
			t.Fatal(err)
		}
		if replace {
			if _, err := db.Exec(`DELETE FROM Sample_Veg WHERE rowid=?`, peer); err != nil {
				t.Fatal(err)
			}
			replacement, err := db.Exec(`INSERT INTO Sample_Veg(PlotNumber,Species,ID,Cover9) VALUES('108050','REPLACEMENT',10000001,0)`)
			if err != nil {
				t.Fatal(err)
			}
			reused, err := replacement.LastInsertId()
			if err != nil || reused != peer {
				t.Fatal("acceptance fixture did not exercise automatic physical-rowid reuse", reused, peer, err)
			}
		} else {
			if _, err := db.Exec(`UPDATE Sample_Veg SET Species='CHANGED' WHERE rowid=?`, peer); err != nil {
				t.Fatal(err)
			}
		}
		before := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
		if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune); err == nil || restored != nil {
			t.Fatal("changed or replacement duplicate peer authorized restoration", restored, err)
		}
		vprotest.AssertProfileSUFiles(t, service, before)
		if _, err := db.Exec(`UPDATE Sample_Veg SET Species='DUP' WHERE rowid=?`, peer); err != nil {
			t.Fatal(err)
		}
		if restored, err := sourceform.RestoreSIVIIdentities(service, context.Background(), state.ContextID, "108050", result.HistoryID, vprocore.AuditRestorePrune); err != nil || restored == nil {
			t.Fatal("restored exact peer source did not allow explicit retry", restored, err)
		}
	}
}

// ENG-GO-004 Acceptance #4: deleting max hierarchy node ID=3, running SaveProjectAs, and
// inserting a new node in the saved project allocates ID=4 (never reuses deleted ID=3).
func TestSaveProjectAsHierarchyDeleteThreeAllocatesNodeFour(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := t.Context()

	created, err := projectops.CreateNewProject(svc, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName:       "HierSrcProj",
		PresetID:          "LMH25_2023_FS882",
		ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatalf("CreateNewProject: %v", err)
	}
	cid := created.State.ContextID

	hierCreated, err := classification.CreateHierarchyTable(ctx, svc, cid, classification.CreateHierarchyTableRequest{
		Name:        "HierSrcProj",
		Destination: "project",
		Activate:    true,
	})
	if err != nil {
		t.Fatalf("CreateHierarchyTable: %v", err)
	}
	cid = hierCreated.ContextID

	for wantID, name := range []string{"NodeOne", "NodeTwo", "NodeThree"} {
		added, err := classification.AddHierarchyNode(ctx, svc, cid, classification.HierarchyAddNodeRequest{
			Name:  name,
			Level: 1,
		})
		if err != nil {
			t.Fatalf("AddHierarchyNode(%s): %v", name, err)
		}
		if added.NodeID != int64(wantID+1) {
			t.Fatalf("expected node %s ID=%d, got %d", name, wantID+1, added.NodeID)
		}
		cid = added.ContextID
	}

	deleted, err := classification.DeleteHierarchyNode(ctx, svc, cid, classification.HierarchyDeleteNodeRequest{
		NodeID: 3,
	})
	if err != nil {
		t.Fatalf("DeleteHierarchyNode(3): %v", err)
	}
	cid = deleted.ContextID

	dstDir := t.TempDir()
	saved, err := projectops.SaveProjectAs(svc, ctx, cid, projectops.SaveProjectAsRequest{
		NewProjectName:    "HierDstProj",
		DestinationPath:   filepath.Join(dstDir, "HierDstProj.db"),
		ActivateOnSuccess: true,
	})
	if err != nil {
		t.Fatalf("SaveProjectAs: %v", err)
	}

	afterSaveAdded, err := classification.AddHierarchyNode(ctx, svc, saved.State.ContextID, classification.HierarchyAddNodeRequest{
		Name:  "NodeAfterSaveAs",
		Level: 1,
	})
	if err != nil {
		t.Fatalf("AddHierarchyNode after SaveProjectAs: %v", err)
	}
	if afterSaveAdded.NodeID != 4 {
		t.Fatalf("expected new hierarchy node after SaveProjectAs to allocate ID=4 (never reuse deleted ID=3), got ID=%d", afterSaveAdded.NodeID)
	}
}
