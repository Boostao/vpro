package datasheet

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestUniversalDatasheetOptionalMensurationDiscoveryAndEditing(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	if err := service.Plots.SetCurrentUser("DatasheetTester"); err != nil {
		t.Fatal(err)
	}

	// 1. Before mensuration tables exist: ListDatasheetTables still returns strictly 9 canonical tables.
	beforeTables, err := ListDatasheetTables(ctx, service, state.ContextID)
	if err != nil {
		t.Fatalf("ListDatasheetTables before mensuration failed: %v", err)
	}
	if len(beforeTables) != 9 {
		t.Fatalf("expected 9 canonical tables before mensuration creation, got %d", len(beforeTables))
	}

	// 2. Create optional Sample_TreePlot and Sample_Trees and seed rows for plot '00337'.
	owner := service.Projects.Sqlite
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		if _, _, err := vprocore.EnsureMensurationTablesTx(ctx, wtx.Tx, wtx.Project); err != nil {
			return err
		}
		zone := "CWH"
		baf := 6.0
		if _, err := vprocore.SaveTreePlotInTx(ctx, wtx, "Seed", 0, vprocore.TreePlotRecord{
			PlotNumber:    "00337",
			SubPlot:       "1",
			MeasurementID: 1,
			Zone:          &zone,
			CruisePlot:    false,
			BAF:           &baf,
		}); err != nil {
			return err
		}
		sub := "1"
		mid := 1
		tn := 1
		spp := "Hw"
		dbh := 32.5
		health := 1
		if _, err := vprocore.SaveTreeRowInTx(ctx, wtx, "Seed", 0, vprocore.TreeRowRecord{
			PlotNumber:    "00337",
			SubPlot:       &sub,
			MeasurementID: &mid,
			TreeNum:       &tn,
			TreeSpp:       &spp,
			DBH:           &dbh,
			TreeHealth:    &health,
		}); err != nil {
			return err
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}

	// 3. ListDatasheetTables now dynamically discovers TreePlot (26 cols) and Trees (43 cols).
	afterTables, err := ListDatasheetTables(ctx, service, state.ContextID)
	if err != nil {
		t.Fatalf("ListDatasheetTables after mensuration failed: %v", err)
	}
	if len(afterTables) != 11 {
		t.Fatalf("expected 11 datasheet tables (9 canonical + TreePlot + Trees), got %d", len(afterTables))
	}
	var tpInfo, treesInfo *DatasheetTableInfo
	for i := range afterTables {
		switch afterTables[i].Key {
		case "TreePlot":
			tpInfo = &afterTables[i]
		case "Trees":
			treesInfo = &afterTables[i]
		}
	}
	if tpInfo == nil || !tpInfo.Available || !tpInfo.Editable || len(tpInfo.Columns) != 26 || tpInfo.RowCount != 1 {
		t.Fatalf("unexpected TreePlot table info: %+v", tpInfo)
	}
	if treesInfo == nil || !treesInfo.Available || !treesInfo.Editable || len(treesInfo.Columns) != 43 || treesInfo.RowCount != 1 {
		t.Fatalf("unexpected Trees table info: %+v", treesInfo)
	}

	// 4. Page read + literal leading-zero PlotNumber filter.
	tpPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "TreePlot",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "00337"}},
	})
	if err != nil || tpPage.TotalRows != 1 || len(tpPage.Rows) != 1 {
		t.Fatalf("GetDatasheetPage(TreePlot, 00337) failed: page=%+v err=%v", tpPage, err)
	}
	tpPage337, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "TreePlot",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "337"}},
	})
	if err != nil || tpPage337.TotalRows != 0 {
		t.Fatalf("expected 0 TreePlot rows for '337', got %d (err=%v)", tpPage337.TotalRows, err)
	}

	// 5. Edit CruisePlot (Access bool -> -1) and BAF on TreePlot via ApplyDatasheetEdits.
	cruiseIdx := findColIdx(tpPage.Columns, "CruisePlot")
	bafIdx := findColIdx(tpPage.Columns, "BAF")
	editRes, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "TreePlot",
		Edits: []DatasheetCellEdit{
			{RowID: tpPage.Rows[0].RowID, Column: "CruisePlot", Before: tpPage.Rows[0].Cells[cruiseIdx], After: textCell("true")},
			{RowID: tpPage.Rows[0].RowID, Column: "BAF", Before: tpPage.Rows[0].Cells[bafIdx], After: realCell(8.5)},
		},
	})
	if err != nil {
		t.Fatalf("ApplyDatasheetEdits(TreePlot) failed: %v", err)
	}
	if editRes.UpdatedRows != 1 || editRes.UpdatedCells != 2 || editRes.AuditRows != 2 {
		t.Fatalf("unexpected TreePlot edit result: %+v", editRes)
	}

	roDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()

	var cruiseRaw int64
	if err := roDB.QueryRow(`SELECT CruisePlot FROM Sample_TreePlot WHERE PlotNumber='00337'`).Scan(&cruiseRaw); err != nil {
		t.Fatal(err)
	}
	if cruiseRaw != -1 {
		t.Fatalf("expected Access bool -1 stored in Sample_TreePlot.CruisePlot, got %d", cruiseRaw)
	}
	var auditAfter string
	if err := roDB.QueryRow(`SELECT AfterEdit FROM Sample_Audit WHERE PlotNumber='00337' AND "Table"='_TreePlot' AND EditField='CruisePlot'`).Scan(&auditAfter); err != nil {
		t.Fatal(err)
	}
	if auditAfter != "-1" {
		t.Fatalf("expected _TreePlot audit AfterEdit='-1', got %q", auditAfter)
	}

	// 6. Trees validation: reject TreeSpp > 3 UTF-16 chars and TreeHealth > 255; accept valid edit.
	treesPage, err := GetDatasheetPage(ctx, service, state.ContextID, DatasheetPageRequest{
		TableKey: "Trees",
		Filters:  []DatasheetFilterSpec{{Column: "PlotNumber", Op: "eq", Value: "00337"}},
	})
	if err != nil || len(treesPage.Rows) != 1 {
		t.Fatalf("GetDatasheetPage(Trees) failed: %v", err)
	}
	sppIdx := findColIdx(treesPage.Columns, "TreeSpp")
	healthIdx := findColIdx(treesPage.Columns, "TreeHealth")

	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Trees",
		Edits:    []DatasheetCellEdit{{RowID: treesPage.Rows[0].RowID, Column: "TreeSpp", Before: treesPage.Rows[0].Cells[sppIdx], After: textCell("TOOLONG")}},
	}); err == nil || !strings.Contains(err.Error(), "3") {
		t.Fatalf("expected UTF-16 <= 3 error on Trees.TreeSpp, got %v", err)
	}

	overByte := "256"
	if _, err := ApplyDatasheetEdits(ctx, service, state.ContextID, DatasheetEditRequest{
		TableKey: "Trees",
		Edits: []DatasheetCellEdit{{
			RowID:  treesPage.Rows[0].RowID,
			Column: "TreeHealth",
			Before: treesPage.Rows[0].Cells[healthIdx],
			After:  vprocore.ProjectMetadataCell{Storage: "integer", Integer: &overByte},
		}},
	}); err == nil || !strings.Contains(err.Error(), "255") {
		t.Fatalf("expected 0..255 byte range error on Trees.TreeHealth, got %v", err)
	}

	// Find/Replace preview on Trees.TreeSpp ('Hw' -> 'Cw').
	preview, err := PreviewDatasheetFindReplace(ctx, service, state.ContextID, DatasheetFindReplaceRequest{
		TableKey:    "Trees",
		Column:      "TreeSpp",
		FindText:    "Hw",
		ReplaceText: "Cw",
		ExactCell:   true,
	})
	if err != nil {
		t.Fatalf("PreviewDatasheetFindReplace(Trees) failed: %v", err)
	}
	if preview.MatchedRows != 1 || preview.ValidCount != 1 || preview.InvalidCount != 0 {
		t.Fatalf("unexpected Trees find/replace preview: %+v", preview)
	}
}
