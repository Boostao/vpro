package diagnostics

import (
	"database/sql"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func TestUndoSynthesisReassignmentWritesCompensatingAuditRow(t *testing.T) {
	env := buildSynthesisFixture(t, 0)

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(env.state.ProjectPath, "rw")+"&_busy_timeout=5000")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = db.Close() }()

	var initialAudit int
	if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Audit`).Scan(&initialAudit); err != nil {
		t.Fatal(err)
	}
	if initialAudit != 0 {
		t.Fatalf("expected clean Sample_Audit before test, got %d", initialAudit)
	}

	if _, err := ReassignSynthesisPlotUnit(env.ctx, env.service, env.state.ContextID, ReassignSynthesisPlotRequest{
		PlotNumber:     "00337",
		TargetSiteUnit: "CWHvm1/05",
		Options: SynthesisOptions{
			UnitSource:               "su",
			ExcludeStandardModifiers: true,
		},
	}); err != nil {
		t.Fatalf("ReassignSynthesisPlotUnit failed: %v", err)
	}

	if _, err := UndoSynthesisReassignment(env.ctx, env.service, env.state.ContextID, UndoSynthesisReassignmentRequest{
		Options: SynthesisOptions{
			UnitSource:               "su",
			ExcludeStandardModifiers: true,
		},
	}); err != nil {
		t.Fatalf("UndoSynthesisReassignment failed: %v", err)
	}

	rows, err := db.Query(`
		SELECT "PlotNumber", "Table", "EditField", COALESCE("BeforeEdit", ''), COALESCE("AfterEdit", ''), COALESCE(CAST("Restore" AS INTEGER), 0), COALESCE(CAST("Flag" AS INTEGER), 0)
		FROM Sample_Audit
		ORDER BY rowid ASC
	`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()

	type auditRow struct {
		plot, table, field, before, after string
		restore, flag                     int
	}
	var got []auditRow
	for rows.Next() {
		var r auditRow
		if err := rows.Scan(&r.plot, &r.table, &r.field, &r.before, &r.after, &r.restore, &r.flag); err != nil {
			t.Fatal(err)
		}
		got = append(got, r)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 Sample_Audit rows (assign + compensating undo), got %d: %+v", len(got), got)
	}
	if got[0].plot != "00337" || got[0].table != "_SU" || got[0].field != "SiteUnit" ||
		got[0].before != "CWHvm1/01" || got[0].after != "CWHvm1/05" || got[0].restore != 0 || got[0].flag != 0 {
		t.Fatalf("unexpected forward Sample_Audit row: %+v", got[0])
	}
	if got[1].plot != "00337" || got[1].table != "_SU" || got[1].field != "SiteUnit" ||
		got[1].before != "CWHvm1/05" || got[1].after != "CWHvm1/01" || got[1].restore != 0 || got[1].flag != 0 {
		t.Fatalf("unexpected compensating undo Sample_Audit row: %+v", got[1])
	}
}

func TestSynthesisAlignedRPairwiseAndOutlierDefaults(t *testing.T) {
	p := normalizePairwiseParams(PairwiseParams{})
	if p.MinConstancy != 60.0 || p.NoiseConstancy != 10.0 || p.MinPlots != 2 ||
		p.MinDiff != 0.5 || p.MinDD != 0.5 || p.MinorCover != 1.0 || p.DominantCover != 7.0 {
		t.Fatalf("unexpected R-aligned default PairwiseParams: %+v", p)
	}
	if normalizeOutlierThreshold(0) != 0.45 {
		t.Fatalf("expected default outlier threshold 0.45, got %v", normalizeOutlierThreshold(0))
	}

	env := buildSynthesisFixture(t, 0)
	snap, err := ComputeSynthesisSnapshot(env.ctx, env.service, env.state.ContextID, SynthesisOptions{
		UnitSource:               "su",
		ExcludeStandardModifiers: true,
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot with defaults failed: %v", err)
	}

	// Default MinPlots=2 excludes singleton CWHvm1/09 (1 plot), leaving CWHvm1/01 vs CWHvm1/05 -> 1 pair.
	if len(snap.PairwiseComparisons) != 1 ||
		snap.PairwiseComparisons[0].Unit1 != "CWHvm1/01" ||
		snap.PairwiseComparisons[0].Unit2 != "CWHvm1/05" {
		t.Fatalf("expected 1 pairwise comparison under R-aligned MinPlots=2, got %+v", snap.PairwiseComparisons)
	}

	var found00337, foundSingleton bool
	for _, cand := range snap.OutlierQueue {
		if cand.PlotNumber == "00337" {
			found00337 = true
			if !cand.Misplaced || !cand.BelowThreshold {
				t.Fatalf("expected plot '00337' (own=0 < 0.45) to be Misplaced & BelowThreshold, got %+v", cand)
			}
		}
		if cand.PlotNumber == "U09_01" {
			foundSingleton = true
			if !cand.SingletonUnit || cand.BelowThreshold {
				t.Fatalf("expected singleton plot U09_01 to have BelowThreshold=false, got %+v", cand)
			}
		}
	}
	if !found00337 || !foundSingleton {
		t.Fatalf("missing expected outlier queue plots (00337=%v U09_01=%v)", found00337, foundSingleton)
	}

	for _, badThreshold := range []float64{-0.1, 1.25} {
		if _, err := ComputeSynthesisSnapshot(env.ctx, env.service, env.state.ContextID, SynthesisOptions{
			UnitSource:       "su",
			OutlierThreshold: badThreshold,
		}); err == nil || !strings.Contains(err.Error(), "outlierThreshold") {
			t.Fatalf("expected error for invalid outlierThreshold=%v, got %v", badThreshold, err)
		}
	}
}

func TestSynthesisCoverPrecedenceSublayerSumVsStrataTotals(t *testing.T) {
	env := buildSynthesisFixture(t, 0)
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(env.state.ProjectPath, "rw")+"&_busy_timeout=5000")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = db.Close() }()

	for _, tbl := range []string{"Sample_Veg", "Working_SU", "Sample_Admin", "Sample_Env"} {
		if _, err := db.Exec(`DELETE FROM ` + vprocore.QuoteHeaderIdentifier(tbl)); err != nil {
			t.Fatal(err)
		}
	}

	plots := []struct {
		id     int
		plot   string
		sp     string
		c1, c2 any
		totA   any
		c4, c5 any
		totB   any
	}{
		// P1: TotalA=123 (>99) and Cover1=10, Cover2=20 -> sublayer_sum uses 30, strata_totals uses 123 (uncapped).
		{1, "P1", "ABIEAMA", 10.0, 20.0, 123.0, nil, nil, nil},
		// P2: TotalA=0 (authoritative zero) and Cover1=25 -> sublayer_sum uses 25, strata_totals suppresses ABIEGRA.
		{2, "P2", "ABIEGRA", 25.0, nil, 0.0, nil, nil, nil},
		// P3: TotalA=NULL and Cover1=60, Cover2=60 (120) -> sublayer_sum sums 120, strata_totals caps fallback at 99.
		{3, "P3", "THUJPLI", 60.0, 60.0, nil, nil, nil, nil},
		// P4: TotalB=NULL and Cover4=60, Cover5a=55 (115) -> strata_totals caps B fallback at 99.
		{4, "P4", "VACCMEM", nil, nil, nil, 60.0, 55.0, nil},
	}

	for _, p := range plots {
		if _, err := db.Exec(`INSERT INTO Sample_Env ("PlotNumber", "Zone", "SubZone", "SiteSeries") VALUES (?, 'CWH', 'vm1', '01')`, p.plot); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO Sample_Admin ("Plot", "UserSiteUnit") VALUES (?, 'CWHvm1/01')`, p.plot); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO Working_SU ("PlotNumber", "SiteUnit") VALUES (?, 'CWHvm1/01')`, p.plot); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`
			INSERT INTO Sample_Veg ("PlotNumber", "ID", "Species", "Cover1", "Cover2", "TotalA", "Cover4", "Cover5a", "TotalB")
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			p.plot, p.id, p.sp, p.c1, p.c2, p.totA, p.c4, p.c5, p.totB,
		); err != nil {
			t.Fatal(err)
		}
	}
	_ = db.Close()

	findMean := func(snap *SynthesisSnapshot, species string) (float64, bool) {
		for _, row := range snap.Species {
			if row.Species == species {
				for _, cell := range row.Cells {
					if cell.SiteUnit == "CWHvm1/01" && cell.PresentPlots > 0 {
						return cell.MeanCoverAll, true
					}
				}
				return 0, false
			}
		}
		return 0, false
	}

	if _, err := ComputeSynthesisSnapshot(env.ctx, env.service, env.state.ContextID, SynthesisOptions{
		UnitSource:      "su",
		CoverPrecedence: "bogus_mode",
	}); err == nil || !strings.Contains(err.Error(), "coverPrecedence") {
		t.Fatalf("expected invalid coverPrecedence rejection, got %v", err)
	}

	subSnap, err := ComputeSynthesisSnapshot(env.ctx, env.service, env.state.ContextID, SynthesisOptions{
		UnitSource:      "su",
		CoverPrecedence: "sublayer_sum",
	})
	if err != nil {
		t.Fatalf("sublayer_sum failed: %v", err)
	}
	if cov, ok := findMean(subSnap, "ABIEAMA"); !ok || cov != 7.5 { // (10+20)/4
		t.Fatalf("sublayer_sum ABIEAMA mean = %v (present=%v), want 7.5", cov, ok)
	}
	if cov, ok := findMean(subSnap, "ABIEGRA"); !ok || cov != 6.25 { // 25/4
		t.Fatalf("sublayer_sum ABIEGRA mean = %v (present=%v), want 6.25", cov, ok)
	}

	totSnap, err := ComputeSynthesisSnapshot(env.ctx, env.service, env.state.ContextID, SynthesisOptions{
		UnitSource:      "su",
		CoverPrecedence: "strata_totals",
	})
	if err != nil {
		t.Fatalf("strata_totals failed: %v", err)
	}
	if cov, ok := findMean(totSnap, "ABIEAMA"); !ok || cov != 30.75 { // 123/4 (uncapped TotalA)
		t.Fatalf("strata_totals ABIEAMA mean = %v (present=%v), want 30.75", cov, ok)
	}
	if cov, ok := findMean(totSnap, "ABIEGRA"); ok {
		t.Fatalf("strata_totals expected TotalA=0 to suppress ABIEGRA, got mean=%v", cov)
	}
	if cov, ok := findMean(totSnap, "THUJPLI"); !ok || cov != 24.75 { // capped 99/4
		t.Fatalf("strata_totals THUJPLI fallback cap mean = %v (present=%v), want 24.75", cov, ok)
	}
	if cov, ok := findMean(totSnap, "VACCMEM"); !ok || cov != 24.75 { // capped 99/4
		t.Fatalf("strata_totals VACCMEM fallback cap mean = %v (present=%v), want 24.75", cov, ok)
	}
}
