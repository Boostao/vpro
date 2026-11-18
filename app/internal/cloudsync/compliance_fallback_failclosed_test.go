package cloudsync

import (
	"database/sql"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

// ENG-GO-004: a non-numeric value in a cover column must fail the upload gate, never pass it.
func TestLayer1ComplianceFallbackFailsClosedOnNonNumericCover(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	baseline, err := runLayer1ComplianceFallback(t.Context(), svc, state.ContextID)
	if err != nil {
		t.Fatal(err)
	}

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(svc.Projects.Sqlite.Attachments["project"], "rw"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE Sample_Veg SET Cover1 = 'bad' WHERE rowid = (SELECT MIN(rowid) FROM Sample_Veg)`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	got, err := runLayer1ComplianceFallback(t.Context(), svc, state.ContextID)
	if err == nil && got.Passed {
		t.Fatalf("non-numeric Cover1 passed the compliance gate: %+v", got.Summary)
	}
	if err == nil && got.Summary["boundsErrors"] <= baseline.Summary["boundsErrors"] {
		t.Fatalf("non-numeric Cover1 was not counted: before=%d after=%d", baseline.Summary["boundsErrors"], got.Summary["boundsErrors"])
	}
}
