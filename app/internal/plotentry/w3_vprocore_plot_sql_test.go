package plotentry

import (
	"context"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestEngGo007ReviewedVegetationDeletionExactTextPlotUnderCollateNocase(t *testing.T) {
	s, db := vprotest.ChildFixture(t)
	s.SetAuditStrength(3)

	// Rebuild Sample_Veg with PlotNumber TEXT COLLATE NOCASE so '00337a' and '00337A' collide under bare `=`.
	if _, err := db.Exec(`
		PRAGMA foreign_keys = OFF;
		DROP TABLE Sample_Veg;
		CREATE TABLE Sample_Veg (
			PlotNumber TEXT COLLATE NOCASE NOT NULL,
			Species TEXT NOT NULL,
			Layer TEXT,
			Cover1 REAL, Height1 REAL,
			Cover2 REAL, Height2 REAL,
			Cover3 REAL, Height3 REAL,
			Cover4 REAL, Height4 REAL,
			Cover5 REAL, Height5 REAL,
			Cover5a REAL, Height5a REAL,
			Cover5b REAL, Height5b REAL,
			Cover5c REAL, Height5c REAL,
			Cover6 REAL, Height6 REAL,
			Cover7 REAL,
			Cover8 REAL,
			Cover9 REAL,
			Cover10 REAL,
			TotalA REAL, HeightA REAL,
			TotalB REAL, HeightB REAL,
			Collected TEXT,
			Flag BOOLEAN,
			ID INTEGER,
			LL SMALLINT, AF SMALLINT, DC SMALLINT, UT SMALLINT, VI SMALLINT,
			PV SMALLINT, PG SMALLINT, FFA SMALLINT, Cultural1 SMALLINT, Cultural2 SMALLINT, Other1 SMALLINT, Other2 SMALLINT
		);
		INSERT INTO Sample_Env (PlotNumber, Flag) VALUES ('00337a', 0), ('00337A', 0);
		INSERT INTO Sample_Admin (Plot) VALUES ('00337a'), ('00337A');
		INSERT INTO Sample_Veg (PlotNumber, Species, ID, Cover1, Flag) VALUES
			('00337a', 'PSEUMEN', 77, 15, 0),
			('00337A', 'ABIEAMA', 77, 40, 0);
	`); err != nil {
		t.Fatal(err)
	}

	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	snap, err := inspectVegetationDeletion(context.Background(), tx, `"Sample_Veg"`, "00337a", "SubVegAXL_BC", 77)
	tx.Rollback()
	if err != nil {
		t.Fatalf("inspectVegetationDeletion('00337a', 77) failed under COLLATE NOCASE: %v", err)
	}
	if snap.review.Species == nil || *snap.review.Species != "PSEUMEN" {
		t.Fatalf("expected PSEUMEN for '00337a', got %+v", snap.review)
	}

	if err := DeleteReviewedVegetation(s, "00337a", VegetationDeletionRequest{
		ID:       77,
		Form:     snap.review.Form,
		Expected: snap.review.Expected,
	}); err != nil {
		t.Fatalf("DeleteReviewedVegetation('00337a', 77): %v", err)
	}

	var lowerCnt, upperCnt int
	if err := db.QueryRow(`
		SELECT
			(SELECT COUNT(*) FROM Sample_Veg WHERE CAST(PlotNumber AS BLOB) = CAST('00337a' AS BLOB)),
			(SELECT COUNT(*) FROM Sample_Veg WHERE CAST(PlotNumber AS BLOB) = CAST('00337A' AS BLOB))
	`).Scan(&lowerCnt, &upperCnt); err != nil {
		t.Fatal(err)
	}
	if lowerCnt != 0 || upperCnt != 1 {
		t.Fatalf("expected '00337a' deleted (0) and '00337A' preserved (1), got lower=%d upper=%d", lowerCnt, upperCnt)
	}
}
