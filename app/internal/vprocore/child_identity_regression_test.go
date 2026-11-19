package vprocore_test

import (
	"database/sql"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestAllocateChildIDUnquotedMissingLedgerAndAuditVariants(t *testing.T) {
	_, db := vprotest.ChildFixture(t)

	// 1. Works cleanly even when __VPRO_ChildIdentity does not exist yet and table is passed unquoted.
	tx1, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	id1, err := vprocore.AllocateChildID(tx1, "Sample_Veg")
	_ = tx1.Rollback()
	if err != nil || id1 != 1 {
		t.Fatalf("AllocateChildID without __VPRO_ChildIdentity = (%d, %v), want (1, nil)", id1, err)
	}

	// 2. Honors quoted and unquoted ChildTable reservations (case-insensitively) plus bare 'Veg' Audit rows.
	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
			"ChildTable" TEXT NOT NULL,
			"ID" INTEGER NOT NULL,
			PRIMARY KEY ("ChildTable", "ID")
		);
		INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES ('"sample_veg"', 1), ('Sample_Veg', 2);
		INSERT INTO "Sample_Audit" ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "Restore", "Flag", "ID")
		VALUES ('Sample', 'Importer', 'CHILD1', 'Veg', 'Delete record', '2025-01-01 00:00:00', 0, 0, 3);
	`); err != nil {
		t.Fatal(err)
	}

	tx2, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	id2, err := vprocore.AllocateChildID(tx2, "Sample_Veg")
	_ = tx2.Rollback()
	if err != nil || id2 != 4 {
		t.Fatalf("AllocateChildID with mixed-case reservations & bare Veg audit = (%d, %v), want (4, nil)", id2, err)
	}

	// 3. Passing Sample_Audit directly never queries nonexistent bare table "Sample".
	if _, err := db.Exec(`INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES ('Sample_Audit', 1)`); err != nil {
		t.Fatal(err)
	}
	tx3, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	id3, err := vprocore.AllocateChildID(tx3, `"Sample_Audit"`)
	_ = tx3.Rollback()
	if err != nil || id3 < 2 {
		t.Fatalf("AllocateChildID on Sample_Audit = (%d, %v), want (>=2, nil)", id3, err)
	}

	// 4. Legacy PK-less __VPRO_ChildIdentity table still supports SaveVegRecord without ON CONFLICT failure.
	s2, db2 := vprotest.ChildFixture(t)
	if _, err := db2.Exec(`
		CREATE TABLE "__VPRO_ChildIdentity" ("ChildTable" TEXT, "ID" INTEGER);
		INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES ('Sample_Veg', 1);
	`); err != nil {
		t.Fatal(err)
	}
	if err := s2.SaveVegRecord(vprocore.VegRecord{PlotNumber: "CHILD1", Species: "PSEUMEN"}); err != nil {
		t.Fatalf("SaveVegRecord on PK-less __VPRO_ChildIdentity failed: %v", err)
	}
	var savedID sql.NullInt64
	if err := db2.QueryRow(`SELECT "ID" FROM "Sample_Veg" WHERE "PlotNumber" = 'CHILD1' AND "Species" = 'PSEUMEN'`).Scan(&savedID); err != nil {
		t.Fatal(err)
	}
	if !savedID.Valid || savedID.Int64 != 2 {
		t.Fatalf("expected allocated ID = 2 skipping reserved ID = 1, got %+v", savedID)
	}
}
