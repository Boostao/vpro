package datasheet

import (
	"context"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestUxEnv004AndUxEnv005DatasheetSiteBoundsAndWhitespaceGuards(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Date, Elevation, SlopeGradient, Aspect, StandAge, LocationAccuracy, SubstrateOrganicMatter, Latitude, Longitude, Flag)
		VALUES ('DSW3', '2026-07-15', 450, 12.0, 180, 80, 10, 40.0, 54.0, -126.0, 0);
		INSERT INTO Sample_Admin (Plot, StartDate) VALUES ('DSW3', 2026);
	`)

	envPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Env",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSW3"}},
	})
	if err != nil || len(envPage.Rows) != 1 {
		t.Fatalf("GetDatasheetPage(Env, DSW3): rows=%d err=%v", len(envPage.Rows), err)
	}
	admPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Admin",
		Filters:  []DatasheetFilterSpec{{Column: "Plot", Op: "eq", Value: "DSW3"}},
	})
	if err != nil || len(admPage.Rows) != 1 {
		t.Fatalf("GetDatasheetPage(Admin, DSW3): rows=%d err=%v", len(admPage.Rows), err)
	}

	intCell := func(s string) vprocore.ProjectMetadataCell {
		return vprocore.ProjectMetadataCell{Storage: "integer", Integer: &s}
	}

	badEnvEdits := []struct {
		col   string
		after vprocore.ProjectMetadataCell
	}{
		{"Date", textCell("not-a-date")},
		{"Date", textCell("2026-02-30")},
		{"Elevation", intCell("-500")},
		{"Elevation", intCell("9001")},
		{"SlopeGradient", realCell(-15.0)},
		{"Aspect", intCell("500")},
		{"StandAge", intCell("-1")},
		{"LocationAccuracy", intCell("-1")},
		{"SubstrateOrganicMatter", realCell(150.0)},
		{"SubstrateOrganicMatter", realCell(-5.0)},
		{"Latitude", realCell(95.0)},
		{"Longitude", realCell(-190.0)},
	}
	for _, tc := range badEnvEdits {
		idx := findColIdx(envPage.Columns, tc.col)
		if idx < 0 {
			t.Fatalf("missing Env.%s", tc.col)
		}
		if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
			TableKey: "Env",
			Edits: []DatasheetCellEdit{{
				RowID:  envPage.Rows[0].RowID,
				Column: tc.col,
				Before: envPage.Rows[0].Cells[idx],
				After:  tc.after,
			}},
		}); err == nil {
			t.Fatalf("expected ApplyDatasheetEdits(Env.%s = %+v) to fail", tc.col, tc.after)
		}
	}

	startIdx := findColIdx(admPage.Columns, "StartDate")
	if startIdx < 0 {
		t.Fatal("missing Admin.StartDate")
	}
	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Admin",
		Edits: []DatasheetCellEdit{{
			RowID:  admPage.Rows[0].RowID,
			Column: "StartDate",
			Before: admPage.Rows[0].Cells[startIdx],
			After:  intCell("99999"),
		}},
	}); err == nil {
		t.Fatal("expected ApplyDatasheetEdits(Admin.StartDate = 99999) to fail")
	}

	// Valid Aspect = 999 (level ground) must succeed in Datasheet!
	aspectIdx := findColIdx(envPage.Columns, "Aspect")
	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Env",
		Edits: []DatasheetCellEdit{{
			RowID:  envPage.Rows[0].RowID,
			Column: "Aspect",
			Before: envPage.Rows[0].Cells[aspectIdx],
			After:  intCell("999"),
		}},
	}); err != nil {
		t.Fatalf("expected ApplyDatasheetEdits(Env.Aspect = 999) to succeed, got %v", err)
	}

	// Direct cell validation of PlotNumber rejects leading/trailing whitespace when editable metadata is supplied.
	if _, _, _, err := validateAndNormalizeDatasheetCell(
		"Env",
		DatasheetColumnMeta{Name: "PlotNumber", Kind: "text", MaxUTF16: 7, Editable: true},
		textCell("00888 "),
		false,
	); err == nil {
		t.Fatal("expected validateAndNormalizeDatasheetCell(PlotNumber='00888 ') to reject trailing space")
	}
}
