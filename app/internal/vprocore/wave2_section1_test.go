package vprocore_test

import (
	"context"
	"database/sql"
	"os"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
	"github.com/boostao/vpro/app/resources"
)

func TestSqliteContextProjectDatabaseUsesBeginImmediate(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	db1, err := svc.Projects.Sqlite.ProjectDatabase(ctx)
	if err != nil {
		t.Fatalf("ProjectDatabase: %v", err)
	}
	tx1, err := db1.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("tx1.BeginTx: %v", err)
	}
	defer tx1.Rollback()

	// Because ProjectDatabase uses &_txlock=immediate, tx1 already holds a RESERVED lock
	// on BeginTx() before executing any statement. A second RW connection must fail
	// immediately at BeginTx() rather than deferring lock acquisition to INSERT.
	db2, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw")+"&_busy_timeout=10&_txlock=immediate")
	if err != nil {
		t.Fatalf("open db2: %v", err)
	}
	defer db2.Close()

	tx2, err := db2.BeginTx(ctx, nil)
	if err == nil {
		_ = tx2.Rollback()
		t.Fatal("expected second immediate BeginTx to collide with tx1 RESERVED lock")
	}
}

func TestUpdateSoilRecordsValidatesLMH25HorizonDepthSign(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// Seed a valid plot and Humus/Mineral horizons including a legacy bad Humus row.
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "SOILV1"}); err != nil {
		t.Fatalf("CreatePlot: %v", err)
	}
	u0, u5, l0, l10 := 0.0, 5.0, 0.0, 10.0
	lHz, ofHz, bmHz, tex := "L", "Of", "Bm", "SL"
	if err := svc.SaveHumusRecord(state.ContextID, vprocore.HumusRecord{
		PlotNumber: "SOILV1", Horizon: &lHz, UpperDepth: &u5, LowerDepth: &l0,
	}); err != nil {
		t.Fatalf("SaveHumusRecord upland L: %v", err)
	}
	if err := svc.SaveHumusRecord(state.ContextID, vprocore.HumusRecord{
		PlotNumber: "SOILV1", Horizon: &ofHz, UpperDepth: &u0, LowerDepth: &l10,
	}); err != nil {
		t.Fatalf("SaveHumusRecord wetland Of: %v", err)
	}
	if err := svc.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
		PlotNumber: "SOILV1", Horizon: &bmHz, UpperDepth: &u0, LowerDepth: &l10, Texture: &tex,
	}); err != nil {
		t.Fatalf("SaveMineralRecord Bm: %v", err)
	}
	// Inject a legacy inverted Humus row to verify non-depth field edits are tolerated.
	db, _, release, err := svc.Plots.GetActiveDB()
	if err != nil {
		t.Fatalf("GetActiveDB: %v", err)
	}
	_, err = db.Exec(`INSERT INTO Sample_Humus (PlotNumber, Horizon, UpperDepth, LowerDepth, ID, Flag) VALUES ('SOILV1','L',0,5,999001,0)`)
	release()
	if err != nil {
		t.Fatalf("seed legacy humus: %v", err)
	}

	humusRows, err := svc.ListHumusRecords(ctx, state.ContextID, "SOILV1")
	if err != nil || len(humusRows) != 3 {
		t.Fatalf("ListHumusRecords: %+v %v", humusRows, err)
	}
	mineralRows, err := svc.ListMineralRecords(ctx, state.ContextID, "SOILV1")
	if err != nil || len(mineralRows) != 1 {
		t.Fatalf("ListMineralRecords: %+v %v", mineralRows, err)
	}
	uplandID := int(humusRows[0].ID)
	wetlandID := int(humusRows[1].ID)
	var legacyID int
	for _, r := range humusRows {
		if r.ID == 999001 {
			legacyID = int(r.ID)
		} else if r.Horizon != nil && *r.Horizon == "L" {
			uplandID = int(r.ID)
		} else if r.Horizon != nil && *r.Horizon == "Of" {
			wetlandID = int(r.ID)
		}
	}
	mineralID := int(mineralRows[0].ID)

	// 1. Cross-field edit: lowering Upland L LowerDepth from 0 to 10 while UpperDepth=5 violates Upper > Lower.
	badLower := 10.0
	if err := svc.UpdateSoilRecords(state.ContextID, "SOILV1", []vprocore.SoilRecordUpdate{{
		Kind: "Humus",
		ID:   uplandID,
		Numbers: map[string]vprocore.SoilNumberUpdate{
			"lowerDepth": {Expected: &l0, Value: &badLower},
		},
	}}); err == nil || !strings.Contains(err.Error(), "UpperDepth > LowerDepth") {
		t.Fatalf("expected upland L depth sign error, got %v", err)
	}

	// 2. Wetland Of changed to Upper=15 while Lower=10 violates Upper < Lower.
	badUpper := 15.0
	if err := svc.UpdateSoilRecords(state.ContextID, "SOILV1", []vprocore.SoilRecordUpdate{{
		Kind: "Humus",
		ID:   wetlandID,
		Numbers: map[string]vprocore.SoilNumberUpdate{
			"upperDepth": {Expected: &u0, Value: &badUpper},
		},
	}}); err == nil || !strings.Contains(err.Error(), "UpperDepth < LowerDepth") {
		t.Fatalf("expected wetland Of depth sign error, got %v", err)
	}

	// 3. Mineral Bm UpperDepth changed to 20 while Lower=10 violates Upper < Lower.
	if err := svc.UpdateSoilRecords(state.ContextID, "SOILV1", []vprocore.SoilRecordUpdate{{
		Kind: "Mineral",
		ID:   mineralID,
		Numbers: map[string]vprocore.SoilNumberUpdate{
			"upperDepth": {Expected: &u0, Value: &badUpper},
		},
	}}); err == nil || !strings.Contains(err.Error(), "UpperDepth < LowerDepth") {
		t.Fatalf("expected mineral depth sign error, got %v", err)
	}

	// 4. Editing a non-depth field on legacy invalid row succeeds (tolerant read/edit).
	newComment := "legacy retained"
	if err := svc.UpdateSoilRecords(state.ContextID, "SOILV1", []vprocore.SoilRecordUpdate{{
		Kind: "Humus",
		ID:   legacyID,
		Text: map[string]vprocore.SoilTextUpdate{
			"comment": {Expected: nil, Value: &newComment},
		},
	}}); err != nil {
		t.Fatalf("expected unrelated field edit on legacy soil row to pass, got %v", err)
	}

	// 5. Clearing depth to NULL succeeds cleanly.
	if err := svc.UpdateSoilRecords(state.ContextID, "SOILV1", []vprocore.SoilRecordUpdate{{
		Kind: "Humus",
		ID:   uplandID,
		Numbers: map[string]vprocore.SoilNumberUpdate{
			"lowerDepth": {Expected: &l0, Value: nil},
		},
	}}); err != nil {
		t.Fatalf("clearing LowerDepth to NULL failed: %v", err)
	}
}

func TestNegativeVegCoverRejectedOnWriteButHistoricalTolerated(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "VEGN1"}); err != nil {
		t.Fatalf("CreatePlot: %v", err)
	}
	neg := -1.5
	pos := 12.0
	if err := svc.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "VEGN1", Species: "PSEUMEN", Cover7: &neg,
	}); err == nil {
		t.Fatal("expected SaveVegRecord to reject negative Cover7")
	}
	if err := svc.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "VEGN1", Species: "PSEUMEN", Cover1: &pos,
	}); err != nil {
		t.Fatalf("SaveVegRecord valid failed: %v", err)
	}
	rows, err := svc.ListVegRecords(ctx, state.ContextID, "VEGN1")
	if err != nil || len(rows) != 1 {
		t.Fatalf("ListVegRecords: %+v %v", rows, err)
	}
	rec := rows[0]
	rec.Cover7 = &neg
	if err := svc.UpdateVegRecord(state.ContextID, rec); err == nil {
		t.Fatal("expected UpdateVegRecord to reject new negative Cover7")
	}
	if err := svc.UpdateVegetationNumbers(state.ContextID, "VEGN1", []vprocore.VegetationNumberUpdate{{
		ID:       int(rec.ID),
		Values:   map[string]*float64{"cover1": &neg},
		Expected: map[string]*float64{"cover1": &pos},
		Forms:    map[string]string{"cover1": "SubVegAXL_BC"},
	}}); err == nil {
		t.Fatal("expected UpdateVegetationNumbers to reject negative cover1")
	}

	// Inject historical negative cover directly, verify updating a different field tolerates it.
	db, _, release, err := svc.Plots.GetActiveDB()
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`UPDATE Sample_Veg SET Cover7 = -2 WHERE ID = ?`, rec.ID)
	release()
	if err != nil {
		t.Fatal(err)
	}
	rows, err = svc.ListVegRecords(ctx, state.ContextID, "VEGN1")
	if err != nil || len(rows) != 1 || rows[0].Cover7 == nil || *rows[0].Cover7 != -2 {
		t.Fatalf("historical negative Cover7 not preserved on read: %+v %v", rows, err)
	}
	updatedPos := 25.0
	rows[0].Cover1 = &updatedPos
	if err := svc.UpdateVegRecord(state.ContextID, rows[0]); err != nil {
		t.Fatalf("expected UpdateVegRecord to tolerate unchanged historical negative Cover7: %v", err)
	}
}

func TestDesktopConfigUserSetupAccreditationAndUserLogLifecycle(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// Config user_name helpers + USysUserRestrictions accreditation status.
	setup, err := svc.GetUserSetup(ctx, state.ContextID)
	if err != nil {
		t.Fatalf("GetUserSetup: %v", err)
	}
	if setup.UserName == "" || setup.CanEditBECSiteUnit {
		t.Fatalf("expected default Admin user without BECSiteUnit edit access, got %+v", setup)
	}

	// Accredited master-SU restriction user ("Tina Lee") without Will MacKenzie BECSiteUnit unlock.
	tina, err := svc.SetUserName(ctx, state.ContextID, "Tina Lee")
	if err != nil {
		t.Fatalf("SetUserName Tina Lee: %v", err)
	}
	if !tina.InUserRestrictions || !tina.Accredited || tina.CanEditBECSiteUnit || tina.MasterBECAllowed {
		t.Fatalf("unexpected Tina Lee accreditation: %+v", tina)
	}

	// Will MacKenzie is both in USysUserRestrictions and MasterBECAllowed.
	will, err := svc.SetUserName(ctx, state.ContextID, "Will MacKenzie")
	if err != nil {
		t.Fatalf("SetUserName Will MacKenzie: %v", err)
	}
	if !will.InUserRestrictions || !will.Accredited || !will.CanEditBECSiteUnit || !will.MasterBECAllowed {
		t.Fatalf("unexpected Will MacKenzie accreditation: %+v", will)
	}
	persisted, err := svc.Projects.Preferences.UserName()
	if err != nil || persisted != "Will MacKenzie" {
		t.Fatalf("DesktopConfig.UserName=%q err=%v", persisted, err)
	}

	// Verify VPro64.USysUserLog received InTime entries and OutTime on CloseSQLiteContext.
	vpro64Path := svc.Projects.Sqlite.Attachments["VPro64"]
	if err := svc.Projects.CloseSQLiteContext(); err != nil {
		t.Fatalf("CloseSQLiteContext: %v", err)
	}
	roDB, err := sqlutil.OpenReadOnly(vpro64Path)
	if err != nil {
		t.Fatalf("OpenReadOnly VPro64: %v", err)
	}
	defer roDB.Close()

	var totalRows, closedRows int
	if err := roDB.QueryRow(`SELECT COUNT(*), COUNT(CASE WHEN "InTime" IS NOT NULL AND "OutTime" IS NOT NULL THEN 1 END) FROM "USysUserLog"`).
		Scan(&totalRows, &closedRows); err != nil {
		t.Fatalf("query USysUserLog: %v", err)
	}
	if totalRows == 0 || closedRows == 0 {
		t.Fatalf("expected recorded USysUserLog session InTime/OutTime rows, total=%d closed=%d", totalRows, closedRows)
	}

	// Verify read-only VPro64.db does not break startup or close.
	dataDir, configDir := vprotest.ConfigFixture(t)
	if _, err := vprocore.InstallDatabaseFamily(dataDir); err != nil {
		t.Fatalf("InstallDatabaseFamily: %v", err)
	}
	roVPro64 := dataDir + "/database-family/VPro64.db"
	if err := os.Chmod(roVPro64, 0444); err != nil {
		t.Fatalf("chmod 0444 VPro64.db: %v", err)
	}
	t.Cleanup(func() { _ = os.Chmod(roVPro64, 0600) })

	prefs, err := vprocore.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatalf("OpenDesktopConfig: %v", err)
	}
	roProjSvc, err := vprocore.NewSQLiteProjectService(dataDir, configDir, prefs)
	if err != nil {
		t.Fatalf("expected NewSQLiteProjectService to succeed with read-only VPro64.db, got %v", err)
	}
	if err := roProjSvc.CloseSQLiteContext(); err != nil {
		t.Fatalf("expected CloseSQLiteContext to succeed with read-only VPro64.db, got %v", err)
	}
}

func TestConfigInitYAMLHasNoStalePcOrdKeys(t *testing.T) {
	decoded, err := vprocore.DecodeConfig(resources.ConfigInitYML)
	if err != nil {
		t.Fatalf("DecodeConfig(ConfigInitYML): %v", err)
	}
	if _, err := vprocore.ConfigString(decoded, "Current", "User"); err != nil {
		t.Fatalf("expected Current.User in ConfigInitYML: %v", err)
	}
	store, err := vprocore.OpenDesktopConfig(t.TempDir(), t.TempDir())
	if err != nil {
		t.Fatalf("OpenDesktopConfig from ConfigInitYML: %v", err)
	}
	values, err := store.Snapshot()
	if err != nil {
		t.Fatalf("Snapshot: %v", err)
	}
	if err := vprocore.ValidateDesktopConfig(values); err != nil {
		t.Fatalf("ValidateDesktopConfig(ConfigInitYML): %v", err)
	}
	if strings.Contains(string(resources.ConfigInitYML), "PcOrd") {
		t.Fatal("stale PcOrd* keys still present in config.init.yml")
	}
}
