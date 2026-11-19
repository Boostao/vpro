package cloudsync

import (
	"database/sql"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func cleanComplianceProjectFixture(t *testing.T) (*vprocore.ContextService, vprocore.ProjectState, string) {
	t.Helper()
	svc, state := vprotest.ContextServiceFixture(t)
	projPath := svc.Projects.Sqlite.Attachments["project"]
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rw"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Replace historical Sample_* rows with a clean, compliant single-plot baseline so Passed==true.
	stmts := []string{
		`DELETE FROM "Sample_Veg"`,
		`DELETE FROM "Sample_Humus"`,
		`DELETE FROM "Sample_Mineral"`,
		`DELETE FROM "Sample_Other"`,
		`DELETE FROM "Sample_Admin"`,
		`DELETE FROM "Sample_Env"`,
		`INSERT INTO "Sample_Env" ("PlotNumber", "Zone", "SubZone") VALUES ('00337', 'CWH', 'vm1')`,
		`INSERT INTO "Sample_Admin" ("Plot") VALUES ('00337')`,
		`INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES
			('00337', 'Lv', 6, 3, 1),
			('00337', '2Fm', 3, 0, 2),
			('00337', '2Of1', 0, 15, 3),
			('00337', 'Hydric', 15, 30, 4),
			('00337', 'L', 4, NULL, 5)`,
		`INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Texture", "Colour", "ID") VALUES
			('00337', 'Ah', 0, 12, 'SL', '10YR3/2', 1),
			('00337', 'XAh', 12, 30, 'FSL', '2.5Y4/2', 2),
			('00337', NULL, 30, 60, 'LS', '10YR5/3', 3)`,
	}
	for _, q := range stmts {
		if _, err := db.Exec(q); err != nil {
			t.Fatalf("seed clean baseline (%s): %v", q, err)
		}
	}
	return svc, state, projPath
}

// ENG-GO-004: runLayer1ComplianceFallback must enforce canonical vprocore.ValidateSoilHorizonDepthSign
// and UTF-16 soil bounds across <Project>_Humus and <Project>_Mineral, including single-sided
// negative depths, NULL-horizon rows, discontinuity prefixes, and non-numeric depth values.
func TestLayer1ComplianceFallbackEnforcesLMH25SoilBounds(t *testing.T) {
	t.Run("valid_upland_wetland_discontinuity_and_mineral_pass", func(t *testing.T) {
		svc, state, _ := cleanComplianceProjectFixture(t)
		res, err := runLayer1ComplianceFallback(t.Context(), svc, state.ContextID)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !res.Passed || res.BlockingCount != 0 {
			t.Fatalf("expected clean LMH25 baseline to pass, got %+v", res)
		}

		mgr := NewManager(t.TempDir(), nil)
		defer mgr.Close()
		preview, err := mgr.PreviewStagingSubmission(t.Context(), svc, state.ContextID, false, nil)
		if err != nil {
			t.Fatalf("PreviewStagingSubmission error: %v", err)
		}
		if !preview.CompliancePassed || preview.BlockingErrorCount != 0 {
			t.Fatalf("expected PreviewStagingSubmission fallback to pass, got %+v", preview)
		}
	})

	cases := []struct {
		name string
		sql  string
	}{
		{
			name: "upland_humus_inverted",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'L', 0, 5, 100)`,
		},
		{
			name: "discontinuity_upland_humus_equal_depths",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', '2L', 5, 5, 100)`,
		},
		{
			name: "wetland_discontinuity_humus_inverted",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', '2Of1', 20, 5, 100)`,
		},
		{
			name: "humus_single_sided_negative_upper",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'L', -5, NULL, 100)`,
		},
		{
			name: "humus_single_sided_negative_lower",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'Of', NULL, -2, 100)`,
		},
		{
			name: "humus_null_horizon_negative_depths",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', NULL, -2, -5, 100)`,
		},
		{
			name: "humus_non_numeric_depth_fails_closed",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'L', 'bad', 0, 100)`,
		},
		{
			name: "mineral_null_horizon_inverted",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', NULL, 30, 10, 100)`,
		},
		{
			name: "mineral_single_sided_negative",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', NULL, NULL, -1, 100)`,
		},
		{
			name: "mineral_roman_discontinuity_inverted",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'IXAh', 25, 10, 100)`,
		},
		{
			name: "mineral_non_numeric_depth_fails_closed",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', 'Ah', 0, 'bad', 100)`,
		},
		{
			name: "humus_horizon_utf16_overflow",
			sql:  `INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', '` + strings.Repeat("L", 9) + `', 5, 0, 100)`,
		},
		{
			name: "mineral_horizon_utf16_overflow",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES ('00337', '` + strings.Repeat("A", 9) + `', 0, 10, 100)`,
		},
		{
			name: "mineral_texture_utf16_overflow",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Texture", "ID") VALUES ('00337', 'Ah', 0, 10, 'ABCDE', 100)`,
		},
		{
			name: "mineral_colour_utf16_overflow",
			sql:  `INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Colour", "ID") VALUES ('00337', 'Ah', 0, 10, '` + strings.Repeat("1", 15) + `', 100)`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			svc, state, projPath := cleanComplianceProjectFixture(t)
			db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(projPath, "rw"))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := db.Exec(tc.sql); err != nil {
				_ = db.Close()
				t.Fatalf("inject %s: %v", tc.name, err)
			}
			if err := db.Close(); err != nil {
				t.Fatal(err)
			}

			got, err := runLayer1ComplianceFallback(t.Context(), svc, state.ContextID)
			if err != nil {
				t.Fatalf("unexpected fallback query error on %s: %v", tc.name, err)
			}
			if got.Passed || got.BlockingCount == 0 || got.Summary["boundsErrors"] == 0 {
				t.Fatalf("expected %s to fail compliance fallback bounds check, got %+v", tc.name, got)
			}
		})
	}
}
