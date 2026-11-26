package vprocore_test

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func mensInt64Ptr(n int64) *int64      { return &n }
func mensFloatPtr(f float64) *float64  { return &f }

func TestMensurationBackwardsCompatibilityAndOptionalViews(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	owner := service.Projects.Sqlite

	// Sample.db has NO _TreePlot/_Trees tables: temp views must NOT exist.
	err := owner.WithCoordinatorConn(ctx, func(conn *sql.Conn) error {
		for _, view := range []string{"USysTreePlot", "USysTrees"} {
			var exists bool
			if err := conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_temp_master WHERE type='view' AND name=?)`, view).Scan(&exists); err != nil {
				return err
			}
			if exists {
				t.Fatalf("did not expect temp view %s on 8-table project without mensuration tables", view)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	// ReadPlotMensurationTx on existing leading-zero plot '00337' returns hasTables=false and non-nil empty slices.
	data, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*vprocore.PlotMensurationData, error) {
		return vprocore.ReadPlotMensurationTx(ctx, tx, "project", state.ActiveProject, "00337", owner.ReadOnly)
	})
	if err != nil {
		t.Fatalf("ReadPlotMensurationTx failed: %v", err)
	}
	if data.HasTables || data.HasTreePlot || data.HasTrees {
		t.Fatalf("expected hasTables=false on Sample.db, got %+v", data)
	}
	if data.TreePlots == nil || len(data.TreePlots) != 0 || data.Trees == nil || len(data.Trees) != 0 {
		t.Fatalf("expected non-nil empty slices, got treePlots=%#v trees=%#v", data.TreePlots, data.Trees)
	}

	// Mutating before tables exist must fail cleanly with ErrMensurationTablesNotFound.
	err = owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		_, err := vprocore.SaveTreePlotInTx(ctx, wtx, "Tester", 3, vprocore.TreePlotRecord{
			PlotNumber: "00337", SubPlot: "1", MeasurementID: 1,
		})
		return err
	})
	if !errors.Is(err, vprocore.ErrMensurationTablesNotFound) {
		t.Fatalf("expected ErrMensurationTablesNotFound, got %v", err)
	}

	// EnsureMensurationTablesTx creates both tables idempotently, and EnsureMensurationViews exposes USysTreePlot/USysTrees.
	var createdTP, createdT bool
	err = owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		var e error
		createdTP, createdT, e = vprocore.EnsureMensurationTablesTx(ctx, wtx.Tx, wtx.Project)
		return e
	})
	if err != nil {
		t.Fatalf("EnsureMensurationTablesTx failed: %v", err)
	}
	if !createdTP || !createdT {
		t.Fatalf("expected both tables created, got tp=%v t=%v", createdTP, createdT)
	}
	// Second call is idempotent.
	err = owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		var e error
		createdTP, createdT, e = vprocore.EnsureMensurationTablesTx(ctx, wtx.Tx, wtx.Project)
		return e
	})
	if err != nil || createdTP || createdT {
		t.Fatalf("expected idempotent second EnsureMensurationTablesTx, got tp=%v t=%v err=%v", createdTP, createdT, err)
	}

	if err := owner.EnsureMensurationViews(ctx); err != nil {
		t.Fatalf("EnsureMensurationViews failed: %v", err)
	}
	err = owner.WithCoordinatorConn(ctx, func(conn *sql.Conn) error {
		for _, view := range []string{"USysTreePlot", "USysTrees"} {
			var exists bool
			if err := conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_temp_master WHERE type='view' AND name=?)`, view).Scan(&exists); err != nil {
				return err
			}
			if !exists {
				t.Fatalf("expected temp view %s after EnsureMensurationViews", view)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	// Verify newly opened SqliteContext on the project automatically creates USysTreePlot and USysTrees.
	freshCtx, err := vprocore.NewSQLiteContext(ctx, owner.Selection, service.Projects.SupportPaths)
	if err != nil {
		t.Fatalf("NewSQLiteContext with mensuration tables failed: %v", err)
	}
	defer freshCtx.Close()
	err = freshCtx.WithCoordinatorConn(ctx, func(conn *sql.Conn) error {
		for _, view := range []string{"USysTreePlot", "USysTrees"} {
			var count int
			if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(view)).Scan(&count); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("querying auto-created temp views failed: %v", err)
	}
}

func TestMensurationCRUDValidationAuditAndExactTextPlot(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	owner := service.Projects.Sqlite

	// Ensure mensuration tables exist.
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		_, _, err := vprocore.EnsureMensurationTablesTx(ctx, wtx.Tx, wtx.Project)
		return err
	}); err != nil {
		t.Fatal(err)
	}

	// Save a TreePlot record on leading-zero plot '00337' with Access booleans.
	tpIn := vprocore.TreePlotRecord{
		PlotNumber:       "00337",
		SubPlot:          "1",
		MeasurementID:    1,
		MensurationID:    strPtr("MENS-001"),
		Zone:             strPtr("CWH"),
		SubZone:          strPtr("vm1"),
		FIZ:              strPtr("B"),
		TreeSurveyor:     strPtr("J. Doe"),
		Date:             strPtr("2026-07-15"),
		CruisePlot:       true,
		CWDPlot:          false,
		WildlifePlot:     true,
		InformalPlot:     false,
		SiteIndexPlot:    true,
		BAF:              mensFloatPtr(8.0),
		DBHLimit:         mensFloatPtr(7.5),
		StandAge:         intPtr(110),
		PlotSize:         mensFloatPtr(0.04),
		SeralStage:       strPtr("Mature"),
		FSRegionDistrict: strPtr("DCK"),
		Location:         strPtr("Tuck Inlet"),
		BECSiteUnit:      strPtr("CWHvm1/01"),
		StandAgeVPro:     intPtr(112),
		SiteSeries:       strPtr("01"),
		Comment:          strPtr("SIBEC sample plot"),
		DataSource:       strPtr("SIBEC_2026"),
	}
	var savedTP *vprocore.TreePlotRecord
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		var err error
		savedTP, err = vprocore.SaveTreePlotInTx(ctx, wtx, "ForestAnalyst", 3, tpIn)
		return err
	}); err != nil {
		t.Fatalf("SaveTreePlotInTx insert failed: %v", err)
	}
	if savedTP == nil || savedTP.PlotNumber != "00337" || !savedTP.CruisePlot || savedTP.CWDPlot {
		t.Fatalf("unexpected saved TreePlot: %+v", savedTP)
	}

	// Verify raw SQLite storage uses Access booleans (-1/0) and exact text PlotNumber.
	roDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "ro"))
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()

	var plotType string
	var cruiseRaw, cwdRaw, siRaw int64
	if err := roDB.QueryRow(`SELECT typeof(PlotNumber), CruisePlot, CWDPlot, SiteIndexPlot FROM Sample_TreePlot WHERE PlotNumber = '00337'`).Scan(&plotType, &cruiseRaw, &cwdRaw, &siRaw); err != nil {
		t.Fatalf("inspect Sample_TreePlot failed: %v", err)
	}
	if plotType != "text" || cruiseRaw != -1 || cwdRaw != 0 || siRaw != -1 {
		t.Fatalf("expected text/-1/0/-1 in SQLite, got %s/%d/%d/%d", plotType, cruiseRaw, cwdRaw, siRaw)
	}

	// Verify literal '337' does NOT match '00337'.
	data337, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*vprocore.PlotMensurationData, error) {
		return vprocore.ReadPlotMensurationTx(ctx, tx, "project", state.ActiveProject, "337", false)
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(data337.TreePlots) != 0 {
		t.Fatalf("expected 0 TreePlot rows for '337', got %d", len(data337.TreePlots))
	}

	// Verify Audit recorded Access boolean '-1' for CruisePlot under Table='_TreePlot'.
	var auditAfter string
	if err := roDB.QueryRow(`SELECT AfterEdit FROM Sample_Audit WHERE PlotNumber='00337' AND "Table"='_TreePlot' AND EditField='CruisePlot'`).Scan(&auditAfter); err != nil {
		t.Fatalf("expected _TreePlot CruisePlot audit entry: %v", err)
	}
	if auditAfter != "-1" {
		t.Fatalf("expected CruisePlot audit AfterEdit='-1', got %q", auditAfter)
	}

	// Save two TreeRowRecords on '00337', update one, then delete one.
	tree1 := vprocore.TreeRowRecord{
		PlotNumber:      "00337",
		SubPlot:         strPtr("1"),
		MeasurementID:   intPtr(1),
		TreeNum:         intPtr(1),
		TreeSpp:         strPtr("Hw"),
		DBH:             mensFloatPtr(36.3),
		TotalHtCalc:     mensFloatPtr(26.5),
		CountAge:        intPtr(87),
		CountHT:         mensFloatPtr(1.3),
		TreeHealth:      intPtr(1),
		TreeOrigin:      strPtr("N"),
		Conks:           intPtr(0),
		DamageType:      strPtr("P"),
		DamageSeverity:  strPtr("L"),
		CrownClass:      strPtr("C"),
		WildLifeUse:     strPtr("Cavity"),
		TreeNotes:       strPtr("Healthy codominant"),
		LiveDead:        strPtr("L"),
		CuVolume:        mensFloatPtr(1.2345),
		SPH:             mensFloatPtr(250.5),
		BasalArea:       mensFloatPtr(0.1035),
		SiteIndexID:     mensInt64Ptr(42001),
		SiteIndex:       mensFloatPtr(22.4),
		SiteIndex24:     mensFloatPtr(21.8),
		SI50:            mensFloatPtr(21.8),
	}
	var savedTree *vprocore.TreeRowRecord
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		var err error
		savedTree, err = vprocore.SaveTreeRowInTx(ctx, wtx, "ForestAnalyst", 3, tree1)
		return err
	}); err != nil {
		t.Fatalf("SaveTreeRowInTx insert failed: %v", err)
	}
	if savedTree.RowID <= 0 {
		t.Fatalf("expected positive RowID after insert, got %d", savedTree.RowID)
	}

	// Upsert same composite key updates DBH and writes BeforeEdit -> AfterEdit audit row.
	tree1.DBH = mensFloatPtr(38.1)
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		var err error
		savedTree, err = vprocore.SaveTreeRowInTx(ctx, wtx, "ForestAnalyst", 3, tree1)
		return err
	}); err != nil {
		t.Fatalf("SaveTreeRowInTx update failed: %v", err)
	}

	var dbhBefore, dbhAfter string
	if err := roDB.QueryRow(`SELECT BeforeEdit, AfterEdit FROM Sample_Audit WHERE PlotNumber='00337' AND "Table"='_Trees' AND EditField='DBH' AND BeforeEdit IS NOT NULL`).Scan(&dbhBefore, &dbhAfter); err != nil {
		t.Fatalf("expected DBH update audit entry: %v", err)
	}
	if dbhBefore != "36.3" || dbhAfter != "38.1" {
		t.Fatalf("expected DBH audit 36.3 -> 38.1, got %q -> %q", dbhBefore, dbhAfter)
	}

	// Validation: UTF-16 bounds (PlotNumber > 7, TreeSpp > 3) and Byte bounds (> 255).
	if err := vprocore.ValidateTreePlotRecord(&vprocore.TreePlotRecord{PlotNumber: "12345678", SubPlot: "1", MeasurementID: 1}); err == nil {
		t.Fatal("expected PlotNumber > 7 UTF-16 error")
	}
	if err := vprocore.ValidateTreeRowRecord(&vprocore.TreeRowRecord{PlotNumber: "00337", TreeSpp: strPtr("ABCD")}); err == nil {
		t.Fatal("expected TreeSpp > 3 UTF-16 error")
	}
	if err := vprocore.ValidateTreeRowRecord(&vprocore.TreeRowRecord{PlotNumber: "00337", TreeHealth: intPtr(300)}); err == nil {
		t.Fatal("expected TreeHealth > 255 error")
	}

	// Plot lock check: locking plot '00337' (Flag = -1) blocks SaveTreeRowInTx and DeleteTreePlotInTx.
	vprotest.MutateContextFixture(t, state.ProjectPath, `UPDATE Sample_Env SET Flag = -1 WHERE PlotNumber = '00337'`)
	err = owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		return vprocore.DeleteTreeRowInTx(ctx, wtx, "ForestAnalyst", 3, "00337", "1", 1, 1)
	})
	if err == nil || !strings.Contains(err.Error(), "locked") {
		t.Fatalf("expected plot locked error, got %v", err)
	}

	// Unlock and delete tree row and tree plot.
	vprotest.MutateContextFixture(t, state.ProjectPath, `UPDATE Sample_Env SET Flag = 0 WHERE PlotNumber = '00337'`)
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		return vprocore.DeleteTreeRowInTx(ctx, wtx, "ForestAnalyst", 3, "00337", "1", 1, 1)
	}); err != nil {
		t.Fatalf("DeleteTreeRowInTx failed: %v", err)
	}
	if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
		return vprocore.DeleteTreePlotInTx(ctx, wtx, "ForestAnalyst", 3, "00337", "1", 1)
	}); err != nil {
		t.Fatalf("DeleteTreePlotInTx failed: %v", err)
	}

	// Verify both tables are now empty for '00337'.
	afterData, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*vprocore.PlotMensurationData, error) {
		return vprocore.ReadPlotMensurationTx(ctx, tx, "project", state.ActiveProject, "00337", false)
	})
	if err != nil {
		t.Fatal(err)
	}
	if !afterData.HasTables || len(afterData.TreePlots) != 0 || len(afterData.Trees) != 0 {
		t.Fatalf("expected empty mensuration slices after delete, got %+v", afterData)
	}
}
