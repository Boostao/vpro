package datasheet

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

// ENG-GO-005 / UX-SOIL-002 / UX-SOIL-003 / UX-SOIL-004:
// Verifies Universal Datasheet soil validation across InsertDatasheetChildRow,
// ApplyDatasheetEdits, and PreviewDatasheetFindReplace, including NULL-horizon rows,
// single-sided negative depths, Hydric/Limno/Cumulo wetland horizons, numbered/Roman
// discontinuity prefixes (2Of1, 2L, IXAh, XAh), and untouched legacy negative rows.
func TestDatasheetSoilLMH25NullHorizonNegativeWetlandAndDiscontinuityRules(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)

	vprotest.MutateContextFixture(t, state.ProjectPath, `
		INSERT INTO Sample_Env (PlotNumber, Zone, Flag) VALUES ('DSLMH1', 'CWH', 0);
		INSERT INTO Sample_Admin (Plot) VALUES ('DSLMH1');
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Comment, Flag)
			VALUES (901, 'DSLMH1', 'L', -2.0, -5.0, 'legacy', 0),
			       (902, 'DSLMH1', NULL, 5.0, 2.0, 'null-hz-humus', 0);
		INSERT INTO Sample_Mineral (ID, PlotNumber, Horizon, UpperDepth, LowerDepth, Comments, Flag)
			VALUES (911, 'DSLMH1', NULL, 0.0, 10.0, 'null-hz-min', 0);
	`)
	var err error
	state, err = service.SwitchContext(state.ContextID, vprotest.ContextSelection(state))
	if err != nil {
		t.Fatalf("SwitchContext: %v", err)
	}

	// 1. InsertDatasheetChildRow rejects NULL-horizon inverted Mineral, NULL-horizon negative Humus,
	// single-sided negative depths, inverted Hydric/Limno/Cumulo, and inverted 2Of1/2L/IXAh/XAh.
	rejectInserts := []struct {
		name  string
		table string
		cells map[string]vprocore.ProjectMetadataCell
	}{
		{
			name:  "mineral_null_horizon_inverted",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": nullCell(), "UpperDepth": realCell(30), "LowerDepth": realCell(10),
			},
		},
		{
			name:  "mineral_omitted_horizon_inverted",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"UpperDepth": realCell(30), "LowerDepth": realCell(10),
			},
		},
		{
			name:  "mineral_empty_horizon_inverted",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell(""), "UpperDepth": realCell(30), "LowerDepth": realCell(10),
			},
		},
		{
			name:  "mineral_negative_depth",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("Ah"), "UpperDepth": realCell(-5), "LowerDepth": realCell(15),
			},
		},
		{
			name:  "mineral_IXAh_inverted",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("IXAh"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
		{
			name:  "mineral_XAh_inverted",
			table: "Mineral",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("XAh"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
		{
			name:  "humus_null_horizon_negative",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": nullCell(), "UpperDepth": realCell(-2), "LowerDepth": realCell(-5),
			},
		},
		{
			name:  "humus_single_sided_negative_upper",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("L"), "UpperDepth": realCell(-5), "LowerDepth": nullCell(),
			},
		},
		{
			name:  "humus_null_horizon_single_sided_negative_lower",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": nullCell(), "UpperDepth": nullCell(), "LowerDepth": realCell(-1),
			},
		},
		{
			name:  "humus_L_negative",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("L"), "UpperDepth": realCell(-2), "LowerDepth": realCell(-5),
			},
		},
		{
			name:  "humus_Of1_negative",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("Of1"), "UpperDepth": realCell(-10), "LowerDepth": realCell(-5),
			},
		},
		{
			name:  "humus_2Of1_inverted",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("2Of1"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
		{
			name:  "humus_2L_inverted",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("2L"), "UpperDepth": realCell(0), "LowerDepth": realCell(10),
			},
		},
		{
			name:  "humus_Hydric_inverted",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("Hydric"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
		{
			name:  "humus_Limno_inverted",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("Limno"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
		{
			name:  "humus_Cumulo_inverted",
			table: "Humus",
			cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell("Cumulo"), "UpperDepth": realCell(10), "LowerDepth": realCell(0),
			},
		},
	}
	for _, tc := range rejectInserts {
		res, err := InsertDatasheetChildRow(ctx, service, state.ContextID, DatasheetInsertChildRowRequest{
			TableKey:   tc.table,
			PlotNumber: "DSLMH1",
			Cells:      tc.cells,
		})
		if err == nil || res != nil {
			t.Fatalf("%s: expected InsertDatasheetChildRow rejection, got res=%+v err=%v", tc.name, res, err)
		}
	}

	// 2. InsertDatasheetChildRow accepts valid downward Hydric, Limno, Cumulo, 2Of1, IXAh, XAh and upward 2L.
	acceptInserts := []struct {
		table string
		hz    string
		up    float64
		lo    float64
	}{
		{"Humus", "Hydric", 0, 10},
		{"Humus", "Limno", 10, 20},
		{"Humus", "Cumulo", 20, 35},
		{"Humus", "2Of1", 35, 50},
		{"Humus", "2L", 8, 2},
		{"Mineral", "IXAh", 10, 20},
		{"Mineral", "XAh", 20, 30},
	}
	for _, tc := range acceptInserts {
		if _, err := InsertDatasheetChildRow(ctx, service, state.ContextID, DatasheetInsertChildRowRequest{
			TableKey:   tc.table,
			PlotNumber: "DSLMH1",
			Cells: map[string]vprocore.ProjectMetadataCell{
				"Horizon": textCell(tc.hz), "UpperDepth": realCell(tc.up), "LowerDepth": realCell(tc.lo),
			},
		}); err != nil {
			t.Fatalf("expected valid %s %s (%g..%g) insert to succeed, got %v", tc.table, tc.hz, tc.up, tc.lo, err)
		}
	}

	// 3. ApplyDatasheetEdits:
	// - rejects NULL-horizon Mineral (30..5) and NULL-horizon Humus (-2..-5);
	// - rejects reversing Hydric to 10..0;
	// - allows editing Comment on untouched legacy negative Humus row (ID=901, L -2..-5).
	minPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Mineral",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSLMH1"}},
	})
	if err != nil {
		t.Fatalf("GetDatasheetPage(Mineral): %v", err)
	}
	minIDIdx := findColIdx(minPage.Columns, "ID")
	minUpIdx := findColIdx(minPage.Columns, "UpperDepth")
	minLoIdx := findColIdx(minPage.Columns, "LowerDepth")
	var nullMinRow DatasheetRow
	for _, r := range minPage.Rows {
		if r.Cells[minIDIdx].Integer != nil && *r.Cells[minIDIdx].Integer == "911" {
			nullMinRow = r
			break
		}
	}
	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Mineral",
		Edits: []DatasheetCellEdit{
			{RowID: nullMinRow.RowID, Column: "UpperDepth", Before: nullMinRow.Cells[minUpIdx], After: realCell(30)},
			{RowID: nullMinRow.RowID, Column: "LowerDepth", Before: nullMinRow.Cells[minLoIdx], After: realCell(5)},
		},
	}); err == nil {
		t.Fatal("expected ApplyDatasheetEdits to reject NULL-horizon Mineral (30..5)")
	}

	humPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Humus",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSLMH1"}},
	})
	if err != nil {
		t.Fatalf("GetDatasheetPage(Humus): %v", err)
	}
	humIDIdx := findColIdx(humPage.Columns, "ID")
	humHzIdx := findColIdx(humPage.Columns, "Horizon")
	humUpIdx := findColIdx(humPage.Columns, "UpperDepth")
	humLoIdx := findColIdx(humPage.Columns, "LowerDepth")
	humCmtIdx := findColIdx(humPage.Columns, "Comment")
	var legacyNegRow, nullHumRow, hydricRow DatasheetRow
	for _, r := range humPage.Rows {
		if r.Cells[humIDIdx].Integer != nil {
			switch *r.Cells[humIDIdx].Integer {
			case "901":
				legacyNegRow = r
			case "902":
				nullHumRow = r
			}
		}
		if r.Cells[humHzIdx].Text != nil && *r.Cells[humHzIdx].Text == "Hydric" {
			hydricRow = r
		}
	}

	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Humus",
		Edits: []DatasheetCellEdit{
			{RowID: nullHumRow.RowID, Column: "UpperDepth", Before: nullHumRow.Cells[humUpIdx], After: realCell(-2)},
			{RowID: nullHumRow.RowID, Column: "LowerDepth", Before: nullHumRow.Cells[humLoIdx], After: realCell(-5)},
		},
	}); err == nil {
		t.Fatal("expected ApplyDatasheetEdits to reject NULL-horizon Humus (-2..-5)")
	}

	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Humus",
		Edits: []DatasheetCellEdit{
			{RowID: hydricRow.RowID, Column: "UpperDepth", Before: hydricRow.Cells[humUpIdx], After: realCell(10)},
			{RowID: hydricRow.RowID, Column: "LowerDepth", Before: hydricRow.Cells[humLoIdx], After: realCell(0)},
		},
	}); err == nil {
		t.Fatal("expected ApplyDatasheetEdits to reject reversed Hydric (10..0)")
	}

	// Untouched legacy negative row (901: L -2..-5) remains editable on Comment.
	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Humus",
		Edits: []DatasheetCellEdit{
			{RowID: legacyNegRow.RowID, Column: "Comment", Before: legacyNegRow.Cells[humCmtIdx], After: textCell("legacy preserved")},
		},
	}); err != nil {
		t.Fatalf("expected non-depth edit on untouched legacy negative row to succeed, got %v", err)
	}

	// 4. PreviewDatasheetFindReplace flags ValidationError on NULL-horizon Mineral (0 -> 30 vs LowerDepth 10)
	// and NULL-horizon Humus (5 -> -2).
	frMin, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Mineral",
		Column:      "UpperDepth",
		FindText:    "0",
		ReplaceText: "30",
		ExactCell:   true,
		Filters:     []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSLMH1"}},
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Mineral): %v", err)
	}
	foundNullMinErr := false
	for _, item := range frMin.Items {
		if item.RowID == nullMinRow.RowID && strings.Contains(item.ValidationError, "UpperDepth < LowerDepth") {
			foundNullMinErr = true
		}
	}
	if !foundNullMinErr {
		t.Fatalf("expected PreviewDatasheetFindReplace to flag NULL-horizon Mineral 30..10, got %+v", frMin.Items)
	}

	frHum, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Humus",
		Column:      "UpperDepth",
		FindText:    "5",
		ReplaceText: "-2",
		ExactCell:   true,
		Filters:     []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "DSLMH1"}},
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Humus): %v", err)
	}
	foundNullHumErr := false
	for _, item := range frHum.Items {
		if item.RowID == nullHumRow.RowID && strings.Contains(item.ValidationError, ">= 0 cm") {
			foundNullHumErr = true
		}
	}
	if !foundNullHumErr {
		t.Fatalf("expected PreviewDatasheetFindReplace to flag NULL-horizon Humus negative depth, got %+v", frHum.Items)
	}
}
