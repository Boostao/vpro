package integration

import (
	"bytes"
	"compress/gzip"
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/cloudsync"
	"github.com/boostao/vpro/app/internal/datasheet"
	"github.com/boostao/vpro/app/internal/diagnostics"
	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/lumping"
	"github.com/boostao/vpro/app/internal/plotentry"
	"github.com/boostao/vpro/app/internal/projectops"
	"github.com/boostao/vpro/app/internal/sivi"
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/twopage"
	"github.com/boostao/vpro/app/internal/validation"
	"github.com/boostao/vpro/app/internal/vegreport"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

var s0MatrixUUIDCounter atomic.Uint64

func nextS0UUID() string {
	n := s0MatrixUUIDCounter.Add(1)
	return fmt.Sprintf("a0b1c2d3-e4f5-4678-89ab-%012x", n)
}

func openS0MatrixContext(t *testing.T) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	dataDir, configDir := vprotest.ConfigFixture(t)
	prefs, err := vprocore.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatalf("OpenDesktopConfig: %v", err)
	}
	projects, err := vprocore.NewSQLiteProjectService(dataDir, configDir, prefs)
	if err != nil {
		t.Fatalf("NewSQLiteProjectService: %v", err)
	}
	t.Cleanup(func() {
		_ = projects.CloseSQLiteContext()
	})
	plots, err := vprocore.NewPlotServiceWithPreferences(projects)
	if err != nil {
		t.Fatalf("NewPlotServiceWithPreferences: %v", err)
	}
	plots.AuditStrength = 3
	contexts, err := vprocore.NewContextService(projects, plots)
	if err != nil {
		t.Fatalf("NewContextService: %v", err)
	}
	state, err := projects.GetState(context.Background())
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}
	return contexts, state
}

func s0OpenRW(t *testing.T, dbPath string) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rw"))
	if err != nil {
		t.Fatalf("open sqlite rw %s: %v", dbPath, err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func s0TableCount(t *testing.T, dbPath, table string) int {
	t.Helper()
	db := s0OpenRW(t, dbPath)
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM ` + vprocore.QuoteHeaderIdentifier(table)).Scan(&n); err != nil {
		t.Fatalf("count %s: %v", table, err)
	}
	return n
}

func ptrFloat64(v float64) *float64 { return &v }
func ptrInt(v int) *int             { return &v }
func ptrString(v string) *string    { return &v }
func ptrBool(v bool) *bool          { return &v }

func realCell(v float64) vprocore.ProjectMetadataCell {
	return vprocore.ProjectMetadataCell{Storage: "real", Real: &v}
}

func textCell(v string) vprocore.ProjectMetadataCell {
	return vprocore.ProjectMetadataCell{Storage: "text", Text: &v}
}

func nullCell() vprocore.ProjectMetadataCell {
	return vprocore.ProjectMetadataCell{Storage: "null"}
}

// 1. AGENTS.md §3.1 & §3.2: VP08 family metadata, WAL mode, and byte-exact literal Text 7 PlotNumber
// ('00337' vs '337', '00337a' vs '00337A', including TEXT COLLATE NOCASE) across all 8 subsystems.
func TestS0Matrix_VP08FamilyAndLiteralText7PlotNumberAcrossSubsystems(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	contexts, state := openS0MatrixContext(t)

	// Verify VP08 _table_metadata on Sample.db plot tables and across all 8 canonical tables of CreateNewProject.
	rawDB := s0OpenRW(t, state.ProjectPath)
	for _, suffix := range []string{"Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit"} {
		var desc string
		tbl := "Sample_" + suffix
		if err := rawDB.QueryRow(`SELECT description FROM _table_metadata WHERE table_name = ?`, tbl).Scan(&desc); err != nil || desc != "VP08" {
			t.Fatalf("expected _table_metadata %s = 'VP08', got %q (%v)", tbl, desc, err)
		}
	}
	freshProjPath := filepath.Join(t.TempDir(), "FreshVP08.db")
	freshRes, err := projectops.CreateNewProject(contexts, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName:       "FreshVP08",
		DestinationPath:   freshProjPath,
		ActivateOnSuccess: true,
	})
	if err != nil || freshRes.State == nil {
		t.Fatalf("CreateNewProject(FreshVP08): %+v (%v)", freshRes, err)
	}
	state = *freshRes.State
	freshDB := s0OpenRW(t, freshProjPath)
	for _, suffix := range []string{"Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata"} {
		var desc string
		tbl := "FreshVP08_" + suffix
		if err := freshDB.QueryRow(`SELECT description FROM _table_metadata WHERE table_name = ?`, tbl).Scan(&desc); err != nil || desc != "VP08" {
			t.Fatalf("expected _table_metadata %s = 'VP08', got %q (%v)", tbl, desc, err)
		}
	}

	// Seed 4 near-colliding PlotNumber values ('00337', '337', '00337a', '00337A') with distinct elevations and species.
	seedPlots := []struct {
		plot string
		elev int
		spp  string
		cov  float64
	}{
		{"00337", 337, "TSUGHET", 25.0},
		{"337", 1337, "PSEUMEN", 35.0},
		{"00337a", 410, "THUJPLI", 45.0},
		{"00337A", 820, "ABIEAMA", 55.0},
	}
	for _, sp := range seedPlots {
		loc := "Loc-" + sp.plot
		if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{
			PlotNumber:      sp.plot,
			GeneralLocation: &loc,
			Elevation:       ptrInt(sp.elev),
		}); err != nil {
			t.Fatalf("CreatePlot(%q): %v", sp.plot, err)
		}
		layer := "1"
		if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
			PlotNumber: sp.plot,
			Species:    sp.spp,
			Layer:      &layer,
			Cover1:     ptrFloat64(sp.cov),
		}); err != nil {
			t.Fatalf("SaveVegRecord(%q): %v", sp.plot, err)
		}
	}

	// Verify typeof(PlotNumber) == 'text' across _Env, _Admin, and _Veg.
	var nonText int
	if err := freshDB.QueryRow(`
		SELECT (SELECT COUNT(*) FROM FreshVP08_Env WHERE typeof(PlotNumber) != 'text') +
		       (SELECT COUNT(*) FROM FreshVP08_Admin WHERE typeof(Plot) != 'text') +
		       (SELECT COUNT(*) FROM FreshVP08_Veg WHERE typeof(PlotNumber) != 'text')
	`).Scan(&nonText); err != nil || nonText != 0 {
		t.Fatalf("found %d non-text PlotNumber/Plot cells (err=%v)", nonText, err)
	}

	// (a) PlotService & PlotEntry: update only '00337a' and verify '00337A', '00337', '337' remain untouched.
	hdrA, err := contexts.GetPlot(ctx, state.ContextID, "00337a")
	if err != nil || hdrA == nil || hdrA.Elevation == nil || *hdrA.Elevation != 410 {
		t.Fatalf("GetPlot(00337a) = %+v, %v", hdrA, err)
	}
	hdrA.Elevation = ptrInt(415)
	if err := contexts.UpdatePlot(state.ContextID, *hdrA); err != nil {
		t.Fatalf("UpdatePlot(00337a): %v", err)
	}
	if hdrUpper, err := contexts.GetPlot(ctx, state.ContextID, "00337A"); err != nil || *hdrUpper.Elevation != 820 {
		t.Fatalf("UpdatePlot(00337a) leaked into 00337A: %+v (%v)", hdrUpper, err)
	}
	if hdrZero, err := contexts.GetPlot(ctx, state.ContextID, "00337"); err != nil || *hdrZero.Elevation != 337 {
		t.Fatalf("GetPlot(00337) = %+v (%v)", hdrZero, err)
	}
	if hdrPlain, err := contexts.GetPlot(ctx, state.ContextID, "337"); err != nil || *hdrPlain.Elevation != 1337 {
		t.Fatalf("GetPlot(337) = %+v (%v)", hdrPlain, err)
	}

	// (b) SIVI & TwoPage readers isolate '00337' from '337' and '00337a' from '00337A'.
	siviCoverSvc, err := sivi.NewSIVICoverService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	siviOrig, err := siviCoverSvc.GetOriginal(ctx, state.ContextID, "00337", false)
	if err != nil || len(siviOrig) != 3 || len(siviOrig[0].Rows) != 1 {
		t.Fatalf("SIVICoverService.GetOriginal(00337): len=%d rows=%v err=%v", len(siviOrig), siviOrig, err)
	}
	tpVegSvc, err := twopage.NewTwoPageVegetationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	tpOrig, err := tpVegSvc.GetOriginal(ctx, state.ContextID, "00337a", "SubVegAXL_BC")
	if err != nil || tpOrig == nil || len(tpOrig.Records.Rows) != 1 {
		t.Fatalf("TwoPageVegetationService.GetOriginal(00337a): orig=%+v err=%v", tpOrig, err)
	}

	// (c) Datasheet filter/edit isolates '00337' from '337'.
	dsPage, err := datasheet.GetDatasheetPage(ctx, contexts, state.ContextID, datasheet.DatasheetPageRequest{
		TableKey: "Env",
		Limit:    200,
	})
	if err != nil {
		t.Fatalf("GetDatasheetPage(Env): %v", err)
	}
	plotColIdx := -1
	for i, c := range dsPage.Columns {
		if c.Name == "PlotNumber" {
			plotColIdx = i
			break
		}
	}
	seenExact := map[string]bool{}
	for _, r := range dsPage.Rows {
		if plotColIdx >= 0 && r.Cells[plotColIdx].Text != nil {
			seenExact[*r.Cells[plotColIdx].Text] = true
		}
	}
	for _, wantPlot := range []string{"00337", "337", "00337a", "00337A"} {
		if !seenExact[wantPlot] {
			t.Fatalf("Datasheet Env page missing exact literal plot %q", wantPlot)
		}
	}

	// (d) Classification SU assignment isolates '00337' and '00337a' from '337' and '00337A'.
	suCreated, err := classification.CreateSUTable(ctx, contexts, state.ContextID, classification.CreateSUTableRequest{
		Name:                    "S0Units",
		Destination:             "project",
		PopulateAllProjectPlots: true,
		Activate:                true,
	})
	if err != nil || suCreated == nil || suCreated.NewState == nil {
		t.Fatalf("CreateSUTable: %+v (%v)", suCreated, err)
	}
	state = *suCreated.NewState
	if _, err := classification.AssignPlotsToSiteUnit(ctx, contexts, state.ContextID, classification.AssignPlotsToSiteUnitRequest{
		PlotNumbers:    []string{"00337", "00337a"},
		TargetSiteUnit: ptrString("CWHvm1/01"),
	}); err != nil {
		t.Fatalf("AssignPlotsToSiteUnit: %v", err)
	}
	tree, err := classification.GetSUPlotTree(ctx, contexts, state.ContextID, "")
	if err != nil {
		t.Fatalf("GetSUPlotTree: %v", err)
	}
	assignedSet := map[string]bool{}
	for _, b := range tree.Units {
		if b.SiteUnit == "CWHvm1/01" {
			for _, leaf := range b.Plots {
				assignedSet[leaf.PlotNumber] = true
			}
		}
	}
	if !assignedSet["00337"] || !assignedSet["00337a"] || assignedSet["337"] || assignedSet["00337A"] {
		t.Fatalf("SU bucket CWHvm1/01 leaked across near-colliding PlotNumbers: %v", assignedSet)
	}

	// (e) ProjectOps.ExportSplinterProject extracts strictly '00337' and '00337a' (never '337' or '00337A').
	splinterPath := filepath.Join(t.TempDir(), "SplinterExact.db")
	splinterRes, err := projectops.ExportSplinterProject(contexts, ctx, state.ContextID, projectops.ExportSplinterRequest{
		SplinterProject:   "SplinterExact",
		DestinationPath:   splinterPath,
		PlotNumbers:       []string{"00337", "00337a"},
		ActivateOnSuccess: false,
	})
	if err != nil || splinterRes.ExportedPlotCount != 2 {
		t.Fatalf("ExportSplinterProject: res=%+v err=%v", splinterRes, err)
	}
	splinterDB := s0OpenRW(t, splinterPath)
	rows, err := splinterDB.Query(`SELECT PlotNumber, typeof(PlotNumber) FROM SplinterExact_Env ORDER BY CAST(PlotNumber AS BLOB)`)
	if err != nil {
		t.Fatal(err)
	}
	var splinterPlots []string
	for rows.Next() {
		var p, tp string
		if err := rows.Scan(&p, &tp); err != nil {
			rows.Close()
			t.Fatal(err)
		}
		if tp != "text" {
			rows.Close()
			t.Fatalf("SplinterExact_Env PlotNumber %q stored as %q instead of 'text'", p, tp)
		}
		splinterPlots = append(splinterPlots, p)
	}
	rows.Close()
	if !reflect.DeepEqual(splinterPlots, []string{"00337", "00337a"}) {
		t.Fatalf("SplinterExact_Env plots = %v, want [00337 00337a]", splinterPlots)
	}
	var walMode string
	if err := splinterDB.QueryRow(`PRAGMA journal_mode=WAL`).Scan(&walMode); err != nil || !strings.EqualFold(walMode, "wal") {
		t.Fatalf("expected WAL journal_mode on SplinterExact.db, got %q (%v)", walMode, err)
	}

	// (f) Interchange CSV + TurboVeg XML round-trip preserves leading zero '00337' distinct from '337' as TEXT.
	tidyCSVPath := filepath.Join(t.TempDir(), "tidy.csv")
	if _, err := interchange.ExportLongTidyCSV(contexts, ctx, state.ContextID, interchange.LongTidyCSVRequest{
		DestinationPath: tidyCSVPath,
	}); err != nil {
		t.Fatalf("ExportLongTidyCSV: %v", err)
	}
	csvRaw, err := os.ReadFile(tidyCSVPath)
	if err != nil {
		t.Fatal(err)
	}
	records, err := csv.NewReader(strings.NewReader(string(csvRaw))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	csvPlots := map[string]bool{}
	for _, rec := range records[1:] {
		csvPlots[rec[0]] = true
	}
	if !csvPlots["00337"] || !csvPlots["337"] || !csvPlots["00337a"] || !csvPlots["00337A"] {
		t.Fatalf("ExportLongTidyCSV lost literal PlotNumber distinction: %v", csvPlots)
	}

	tvXMLPath := filepath.Join(t.TempDir(), "plots.xml")
	if _, err := interchange.ExportTurboVeg(contexts, ctx, state.ContextID, interchange.TurboVegExportRequest{
		Format:          "xml",
		DestinationPath: tvXMLPath,
	}); err != nil {
		t.Fatalf("ExportTurboVeg: %v", err)
	}
	tvDestDB := filepath.Join(t.TempDir(), "TVRoundTrip.db")
	if _, err := interchange.ImportTurboVeg(contexts, ctx, state.ContextID, interchange.TurboVegImportRequest{
		SourcePath:        tvXMLPath,
		TargetProject:     "TVRoundTrip",
		DestinationPath:   tvDestDB,
		ActivateOnSuccess: false,
	}); err != nil {
		t.Fatalf("ImportTurboVeg: %v", err)
	}
	tvDB := s0OpenRW(t, tvDestDB)
	var tvTextCount int
	if err := tvDB.QueryRow(`SELECT COUNT(*) FROM TVRoundTrip_Env WHERE typeof(PlotNumber) = 'text' AND CAST(PlotNumber AS BLOB) IN (CAST('00337' AS BLOB), CAST('337' AS BLOB))`).Scan(&tvTextCount); err != nil || tvTextCount != 2 {
		t.Fatalf("TurboVeg round-trip did not preserve distinct text '00337' and '337': count=%d err=%v", tvTextCount, err)
	}

	// (g) CloudSync canonicalization & offline preflight submission preserve literal '00337'.
	pgPlot, err := cloudsync.CanonicalizeSQLiteToPG(cloudsync.ColumnSpec{Name: "PlotNumber", PGType: "TEXT"}, "00337")
	if err != nil || pgPlot != "00337" {
		t.Fatalf("CanonicalizeSQLiteToPG('00337') = %#v (%v)", pgPlot, err)
	}
	cloudMgr := cloudsync.NewManager(t.TempDir(), nil)
	defer cloudMgr.Close()
	preflight, err := cloudMgr.PreviewStagingSubmission(ctx, contexts, state.ContextID, false, nil)
	if err != nil || !preflight.CompliancePassed {
		t.Fatalf("CloudSync PreviewStagingSubmission failed on valid literal plots: %+v (%v)", preflight, err)
	}

	// (h) PlotEntry reviewed vegetation deletion under COLLATE NOCASE isolates '00337a' from '00337A'.
	vegRowsLower, err := contexts.ListVegRecords(ctx, state.ContextID, "00337a")
	if err != nil || len(vegRowsLower) != 1 {
		t.Fatalf("ListVegRecords(00337a): %+v (%v)", vegRowsLower, err)
	}
	delRev, err := plotentry.ReviewVegetationDeletion(contexts, ctx, state.ContextID, "00337a", "SubVegAXL_BC", vegRowsLower[0].ID)
	if err != nil {
		t.Fatalf("ReviewVegetationDeletion(00337a): %v", err)
	}
	if err := plotentry.CtxDeleteReviewedVegetation(contexts, state.ContextID, "00337a", plotentry.VegetationDeletionRequest{
		ID:       delRev.ID,
		Form:     delRev.Form,
		Expected: delRev.Expected,
	}); err != nil {
		t.Fatalf("CtxDeleteReviewedVegetation(00337a): %v", err)
	}
	if remUpper, err := contexts.ListVegRecords(ctx, state.ContextID, "00337A"); err != nil || len(remUpper) != 1 {
		t.Fatalf("CtxDeleteReviewedVegetation(00337a) leaked into 00337A: %+v (%v)", remUpper, err)
	}
}

// 2. AGENTS.md §3.3: float32 < 100 cover narrowing (99.999996 passes; 99.999999/100/-0.01/-1 reject),
// 99% lumped/fallback cap without mutating raw _Veg, Access BOOLEAN (-1/0/NULL), and 15-sig-digit ACE rounding.
func TestS0Matrix_CoverFloat32Narrowing99CapAccessBoolAndACERounding(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	contexts, state := openS0MatrixContext(t)

	loc := "CoverMatrix"
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "CV001", GeneralLocation: &loc}); err != nil {
		t.Fatal(err)
	}

	siviCreateSvc, err := sivi.NewSIVICreationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	siviCoverSvc, err := sivi.NewSIVICoverService(contexts)
	if err != nil {
		t.Fatal(err)
	}

	invalidCovers := []float64{99.999999, 100.0, -0.01, -1.0}
	validBoundary := 99.999996
	expectedNarrowed := float64(float32(validBoundary))

	// Reject every invalid boundary across PlotService, SIVICreation, TwoPage, and Datasheet with 0 rows/audits written!
	for _, bad := range invalidCovers {
		beforeVeg := s0TableCount(t, state.ProjectPath, "Sample_Veg")
		beforeAudit := s0TableCount(t, state.ProjectPath, "Sample_Audit")

		layer := "1"
		if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
			PlotNumber: "CV001",
			Species:    "TSUGHET",
			Layer:      &layer,
			Cover1:     ptrFloat64(bad),
		}); err == nil {
			t.Fatalf("PlotService.SaveVegRecord accepted invalid cover %.8f", bad)
		}

		siviReq, _ := json.Marshal(sourceform.SiviCreationRequest{
			RequestID: nextS0UUID(),
			ContextID: state.ContextID,
			Project:   "Sample",
			Plot:      "CV001",
			Form:      "SubVegA-SIVI_BC",
			Species:   "PSEUMEN",
			Covers:    []sourceform.SiviCreationCover{{Column: "Cover1", Value: realCell(bad)}},
		})
		if _, err := siviCreateSvc.Create(ctx, state.ContextID, string(siviReq)); err == nil {
			t.Fatalf("SIVICreationService.Create accepted invalid cover %.8f", bad)
		}

		if _, err := twopage.CreateTwoPageVegetationRow(contexts, ctx, state.ContextID, twopage.CreateTwoPageVegetationRequest{
			RequestID:  nextS0UUID(),
			PlotNumber: "CV001",
			Form:       "SubVegAXL_BC",
			Species:    "THUJPLI",
			Covers:     map[string]*float64{"Cover1": ptrFloat64(bad)},
		}); err == nil {
			t.Fatalf("CreateTwoPageVegetationRow accepted invalid cover %.8f", bad)
		}

		if _, err := datasheet.InsertDatasheetChildRow(ctx, contexts, state.ContextID, datasheet.DatasheetInsertChildRowRequest{
			TableKey:   "Veg",
			PlotNumber: "CV001",
			Cells: map[string]vprocore.ProjectMetadataCell{
				"Species": textCell("ABIEAMA"),
				"Cover1":  realCell(bad),
			},
		}); err == nil {
			t.Fatalf("Datasheet.InsertDatasheetChildRow accepted invalid cover %.8f", bad)
		}

		if gotVeg := s0TableCount(t, state.ProjectPath, "Sample_Veg"); gotVeg != beforeVeg {
			t.Fatalf("rejected cover %.8f mutated Sample_Veg count (%d -> %d)", bad, beforeVeg, gotVeg)
		}
		if gotAudit := s0TableCount(t, state.ProjectPath, "Sample_Audit"); gotAudit != beforeAudit {
			t.Fatalf("rejected cover %.8f mutated Sample_Audit count (%d -> %d)", bad, beforeAudit, gotAudit)
		}
	}

	// Accept 99.999996 across PlotService, SIVI (Create + SaveReviewed), TwoPage, and Datasheet, narrowed to float32 < 100!
	layer := "1"
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "CV001",
		Species:    "TSUGHET",
		Layer:      &layer,
		Cover1:     ptrFloat64(validBoundary),
	}); err != nil {
		t.Fatalf("PlotService.SaveVegRecord rejected 99.999996: %v", err)
	}

	siviValidReq, _ := json.Marshal(sourceform.SiviCreationRequest{
		RequestID: nextS0UUID(),
		ContextID: state.ContextID,
		Project:   "Sample",
		Plot:      "CV001",
		Form:      "SubVegA-SIVI_BC",
		Species:   "PSEUMEN",
		Covers:    []sourceform.SiviCreationCover{{Column: "Cover2", Value: realCell(validBoundary)}},
	})
	if _, err := siviCreateSvc.Create(ctx, state.ContextID, string(siviValidReq)); err != nil {
		t.Fatalf("SIVICreationService.Create rejected 99.999996: %v", err)
	}

	// Also verify SIVICoverService.SaveReviewed rejects 99.999999 and accepts 99.999996.
	siviOrig, err := siviCoverSvc.GetOriginal(ctx, state.ContextID, "CV001", false)
	if err != nil || len(siviOrig) != 3 || len(siviOrig[0].Rows) == 0 {
		t.Fatalf("SIVICoverService.GetOriginal(CV001): %v", err)
	}
	targetRow := siviOrig[0].Rows[0]
	cover3Idx := -1
	for i, c := range siviOrig[0].Columns {
		if c == "Cover3" {
			cover3Idx = i
			break
		}
	}
	badSiviEdit, _ := json.Marshal(sivi.SIVICoverWrite{
		Original: siviOrig,
		Edits: []sivi.SIVICoverEdit{{
			RowID:    targetRow.RowID,
			Form:     siviOrig[0].Form,
			Column:   "Cover3",
			Expected: targetRow.Cells[cover3Idx],
			Value:    realCell(99.999999),
		}},
	})
	if _, err := siviCoverSvc.SaveReviewed(ctx, state.ContextID, "CV001", false, string(badSiviEdit)); err == nil {
		t.Fatal("SIVICoverService.SaveReviewed accepted 99.999999")
	}
	okSiviEdit, _ := json.Marshal(sivi.SIVICoverWrite{
		Original: siviOrig,
		Edits: []sivi.SIVICoverEdit{{
			RowID:    targetRow.RowID,
			Form:     siviOrig[0].Form,
			Column:   "Cover3",
			Expected: targetRow.Cells[cover3Idx],
			Value:    realCell(validBoundary),
		}},
	})
	if _, err := siviCoverSvc.SaveReviewed(ctx, state.ContextID, "CV001", false, string(okSiviEdit)); err != nil {
		t.Fatalf("SIVICoverService.SaveReviewed rejected 99.999996: %v", err)
	}

	if _, err := twopage.CreateTwoPageVegetationRow(contexts, ctx, state.ContextID, twopage.CreateTwoPageVegetationRequest{
		RequestID:  nextS0UUID(),
		PlotNumber: "CV001",
		Form:       "SubVegAXL_BC",
		Species:    "THUJPLI",
		Covers:     map[string]*float64{"Cover1": ptrFloat64(validBoundary)},
	}); err != nil {
		t.Fatalf("CreateTwoPageVegetationRow rejected 99.999996: %v", err)
	}

	if _, err := datasheet.InsertDatasheetChildRow(ctx, contexts, state.ContextID, datasheet.DatasheetInsertChildRowRequest{
		TableKey:   "Veg",
		PlotNumber: "CV001",
		Cells: map[string]vprocore.ProjectMetadataCell{
			"Species": textCell("ABIEAMA"),
			"Cover1":  realCell(validBoundary),
		},
	}); err != nil {
		t.Fatalf("Datasheet.InsertDatasheetChildRow rejected 99.999996: %v", err)
	}

	// Verify persisted CV001 covers are strictly < 100 in float32 and pass Validation!
	cvRows, err := contexts.ListVegRecords(ctx, state.ContextID, "CV001")
	if err != nil || len(cvRows) != 4 {
		t.Fatalf("ListVegRecords(CV001): len=%d err=%v", len(cvRows), err)
	}
	for _, r := range cvRows {
		if r.Cover1 != nil && (float32(*r.Cover1) >= 100 || float32(*r.Cover1) != float32(validBoundary) || *r.Cover1 < expectedNarrowed-1e-6) {
			t.Fatalf("row %s Cover1 = %.9f (float32=%.7f), want float32 %.7f < 100", r.Species, *r.Cover1, float32(*r.Cover1), float32(validBoundary))
		}
	}
	compReport, err := validation.RunComplianceValidation(contexts, ctx, state.ContextID, validation.ComplianceOptions{})
	if err != nil {
		t.Fatalf("RunComplianceValidation: %v", err)
	}
	for _, f := range compReport.BoundsFindings {
		if f.PlotNumber == "CV001" {
			t.Fatalf("unexpected compliance bounds error on valid narrowed 99.999996 plot CV001: %+v", f)
		}
	}

	// Verify OptimizeVeg blocks mixed negative covers (-5, 10) injected directly on disk.
	db := s0OpenRW(t, state.ProjectPath)
	if _, err := db.Exec(`INSERT INTO Sample_Veg (ID, PlotNumber, Species, Cover1) VALUES (999901, 'CV001', 'PICEENG', -5.0), (999902, 'CV001', 'PICEENG', 10.0)`); err != nil {
		t.Fatal(err)
	}
	optPreview, err := projectops.PreviewOptimizeVeg(contexts, ctx, state.ContextID, projectops.OptimizeVegOptions{})
	if err != nil {
		t.Fatalf("PreviewOptimizeVeg: %v", err)
	}
	foundBlocked := false
	for _, g := range optPreview.Groups {
		if g.PlotNumber == "CV001" && g.Species == "PICEENG" && g.Blocked {
			foundBlocked = true
		}
	}
	if !foundBlocked {
		t.Fatalf("expected OptimizeVeg to block mixed (-5, 10) group on CV001, got %+v", optPreview.Groups)
	}
	if _, err := db.Exec(`DELETE FROM Sample_Veg WHERE ID IN (999901, 999902)`); err != nil {
		t.Fatal(err)
	}

	// Verify 99% lumped/folded cover cap without mutating raw <Project>_Veg, plus Access BOOLEAN (-1/0/NULL) on _Env, _Admin, and *_Lump!
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{
		PlotNumber:          "LP001",
		SpeciesListComplete: ptrBool(true),
		UpdatedFromCards:    ptrBool(false),
	}); err != nil {
		t.Fatal(err)
	}
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{
		PlotNumber: "LP002",
	}); err != nil {
		t.Fatal(err)
	}
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{PlotNumber: "LP001", Species: "RUBUSPE", Layer: &layer, Cover6: ptrFloat64(50.0)}); err != nil {
		t.Fatal(err)
	}
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{PlotNumber: "LP001", Species: "RUBUPAR", Layer: &layer, Cover6: ptrFloat64(49.5)}); err != nil {
		t.Fatal(err)
	}
	if _, err := lumping.CreateLumpTable(contexts, ctx, state.ContextID, "S0Cap"); err != nil {
		t.Fatal(err)
	}
	if _, err := lumping.UpsertLumpRow(contexts, ctx, state.ContextID, "S0Cap_Lump", lumping.LumpRowInput{
		LumpCode: "RUBUSPP",
		SppCode:  "RUBUSPE",
		Use:      true,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := lumping.UpsertLumpRow(contexts, ctx, state.ContextID, "S0Cap_Lump", lumping.LumpRowInput{
		LumpCode: "RUBUSPP",
		SppCode:  "RUBUPAR",
		Use:      false,
	}); err != nil {
		t.Fatal(err)
	}

	// Verify disk Access BOOLEAN values (true = -1, false = 0, NULL = unset) across _Env, _Admin, and *_Lump
	// using CAST(... AS INTEGER) + typeof(...) so go-sqlite3 does not coerce BOOLEAN column affinity to Go bool.
	var envBoolTrue, adminBoolFalse, lumpTrueInt, lumpFalseInt int64
	var envBoolType, adminBoolType, envNullType string
	var envBoolNull sql.NullInt64
	if err := db.QueryRow(`SELECT CAST(SpeciesListComplete AS INTEGER), typeof(SpeciesListComplete) FROM Sample_Env WHERE CAST(PlotNumber AS BLOB) = CAST('LP001' AS BLOB)`).Scan(&envBoolTrue, &envBoolType); err != nil || envBoolTrue != -1 || envBoolType != "integer" {
		t.Fatalf("expected Sample_Env.SpeciesListComplete = -1 (integer) for true, got %d/%q (%v)", envBoolTrue, envBoolType, err)
	}
	if err := db.QueryRow(`SELECT CAST(UpdatedFromCards AS INTEGER), typeof(UpdatedFromCards) FROM Sample_Admin WHERE CAST(Plot AS BLOB) = CAST('LP001' AS BLOB)`).Scan(&adminBoolFalse, &adminBoolType); err != nil || adminBoolFalse != 0 || adminBoolType != "integer" {
		t.Fatalf("expected Sample_Admin.UpdatedFromCards = 0 (integer) for false, got %d/%q (%v)", adminBoolFalse, adminBoolType, err)
	}
	if err := db.QueryRow(`SELECT CAST(SpeciesListComplete AS INTEGER), typeof(SpeciesListComplete) FROM Sample_Env WHERE CAST(PlotNumber AS BLOB) = CAST('LP002' AS BLOB)`).Scan(&envBoolNull, &envNullType); err != nil || envBoolNull.Valid || envNullType != "null" {
		t.Fatalf("expected Sample_Env.SpeciesListComplete = NULL for unset LP002, got %+v/%q (%v)", envBoolNull, envNullType, err)
	}
	if err := db.QueryRow(`SELECT CAST("Use" AS INTEGER) FROM S0Cap_Lump WHERE SppCode = 'RUBUSPE'`).Scan(&lumpTrueInt); err != nil || lumpTrueInt != -1 {
		t.Fatalf("expected S0Cap_Lump.Use = -1 for true, got %d (%v)", lumpTrueInt, err)
	}
	if err := db.QueryRow(`SELECT CAST("Use" AS INTEGER) FROM S0Cap_Lump WHERE SppCode = 'RUBUPAR'`).Scan(&lumpFalseInt); err != nil || lumpFalseInt != 0 {
		t.Fatalf("expected S0Cap_Lump.Use = 0 for false, got %d (%v)", lumpFalseInt, err)
	}

	// Enable RUBUPAR -> Use = true (-1) and verify Wide Matrix CSV + Diagnostics Synthesis cap 50.0 + 49.5 at 99.0 while raw Sample_Veg stays 50.0 & 49.5!
	if _, err := lumping.ToggleLumpRow(contexts, ctx, state.ContextID, "S0Cap_Lump", "RUBUPAR", true); err != nil {
		t.Fatal(err)
	}
	wideCSVPath := filepath.Join(t.TempDir(), "wide_lumped.csv")
	if _, err := interchange.ExportWideMatrixCSV(contexts, ctx, state.ContextID, interchange.WideMatrixCSVRequest{
		DestinationPath: wideCSVPath,
		LumpTable:       "S0Cap_Lump",
	}); err != nil {
		t.Fatalf("ExportWideMatrixCSV: %v", err)
	}
	wideRaw, err := os.ReadFile(wideCSVPath)
	if err != nil {
		t.Fatal(err)
	}
	wideRecs, err := csv.NewReader(strings.NewReader(string(wideRaw))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	rubuCol := -1
	for idx, h := range wideRecs[0] {
		if h == "RUBUSPP" {
			rubuCol = idx
			break
		}
	}
	if rubuCol < 0 {
		t.Fatalf("RUBUSPP lumped column missing from wide matrix header: %v", wideRecs[0])
	}
	foundLP001 := false
	for _, row := range wideRecs[1:] {
		if row[0] == "LP001" {
			foundLP001 = true
			if row[rubuCol] != "99" && row[rubuCol] != "99.0" {
				t.Fatalf("expected LP001 lumped RUBUSPP cover capped at 99%%, got %q", row[rubuCol])
			}
		}
	}
	if !foundLP001 {
		t.Fatal("LP001 row missing from wide matrix CSV")
	}

	// Raw Sample_Veg rows on LP001 must remain unmutated (50.0 and 49.5)!
	rawLP, err := contexts.ListVegRecords(ctx, state.ContextID, "LP001")
	if err != nil || len(rawLP) != 2 || *rawLP[0].Cover6+*rawLP[1].Cover6 != 99.5 {
		t.Fatalf("lumped export mutated raw Sample_Veg rows: %+v (%v)", rawLP, err)
	}

	// Verify Diagnostics Synthesis also caps lumped cover at <= 99.0, and ReassignSynthesisPlotUnit writes to Sample_Audit.
	suRes, err := classification.CreateSUTable(ctx, contexts, state.ContextID, classification.CreateSUTableRequest{
		Name:                    "LumpSU",
		Destination:             "project",
		PopulateAllProjectPlots: true,
		Activate:                true,
	})
	if err != nil || suRes.NewState == nil {
		t.Fatal(err)
	}
	state = *suRes.NewState
	if _, err := classification.AssignPlotsToSiteUnit(ctx, contexts, state.ContextID, classification.AssignPlotsToSiteUnitRequest{
		PlotNumbers:    []string{"LP001"},
		TargetSiteUnit: ptrString("CWHvm1/05"),
	}); err != nil {
		t.Fatal(err)
	}
	synthSnap, err := diagnostics.ComputeSynthesisSnapshot(ctx, contexts, state.ContextID, diagnostics.SynthesisOptions{
		LumpTable: "S0Cap_Lump",
	})
	if err != nil {
		t.Fatalf("ComputeSynthesisSnapshot: %v", err)
	}
	if synthSnap.LumpCappedCells < 1 {
		t.Fatalf("expected LumpCappedCells >= 1 for 50.0 + 49.5 RUBUSPP, got %d", synthSnap.LumpCappedCells)
	}
	foundSynthCap := false
	for _, sp := range synthSnap.Species {
		if sp.Species == "RUBUSPP" {
			foundSynthCap = true
			if sp.MaxMeanCover > 99.0001 || math.Abs(sp.MaxMeanCover-99.0) > 0.01 {
				t.Fatalf("Synthesis lumped RUBUSPP MaxMeanCover = %.4f, want 99.0", sp.MaxMeanCover)
			}
		}
	}
	if !foundSynthCap {
		t.Fatal("expected RUBUSPP in synthesis snapshot species")
	}

	auditBeforeReassign := s0TableCount(t, state.ProjectPath, "Sample_Audit")
	if _, err := diagnostics.ReassignSynthesisPlotUnit(ctx, contexts, state.ContextID, diagnostics.ReassignSynthesisPlotRequest{
		PlotNumber:     "LP001",
		TargetSiteUnit: "CWHvm1/07",
		Options:        diagnostics.SynthesisOptions{LumpTable: "S0Cap_Lump"},
	}); err != nil {
		t.Fatalf("ReassignSynthesisPlotUnit: %v", err)
	}
	if auditAfterReassign := s0TableCount(t, state.ProjectPath, "Sample_Audit"); auditAfterReassign <= auditBeforeReassign {
		t.Fatalf("expected ReassignSynthesisPlotUnit to write Sample_Audit row (%d -> %d)", auditBeforeReassign, auditAfterReassign)
	}

	// Also verify VegReport SummaryVegetationService runs cleanly on active SU.
	sumSvc, err := vegreport.NewSummaryVegetationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	if sumPrev, err := sumSvc.Preview(ctx, state.ContextID, 1, 1); err != nil || len(sumPrev.Rows) == 0 {
		t.Fatalf("SummaryVegetationService.Preview: rows=%d err=%v", len(sumPrev.Rows), err)
	}

	// Verify 15-significant-digit half-away ACE rounding (VALUE_CONVERSIONS.md).
	roundingCases := []struct {
		in       float64
		decimals int
		want     float64
	}{
		{1.005, 2, 1.01},
		{2.675, 2, 2.68},
		{-1.005, 2, -1.01},
		{35.855, 2, 35.86},
	}
	for _, rc := range roundingCases {
		if got := vprocore.RoundCalibratedDecimal(rc.in, rc.decimals); math.Abs(got-rc.want) > 1e-12 {
			t.Fatalf("RoundCalibratedDecimal(%v, %d) = %.15f, want %.15f", rc.in, rc.decimals, got, rc.want)
		}
	}
}

// 3. AGENTS.md §3.4: LMH25 (2023) soil horizon depth sign & ordering across all 5 writers/validators and all 5 readers/exporters.
func TestS0Matrix_LMH25SoilHorizonDepthSignAndProfileOrderingAcrossSubsystems(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	contexts, state := openS0MatrixContext(t)

	for _, p := range []string{"SLVAL", "WET01", "UP01"} {
		if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: p}); err != nil {
			t.Fatal(err)
		}
	}

	tpSoilSvc, err := twopage.NewTwoPageSoilService(contexts)
	if err != nil {
		t.Fatal(err)
	}

	type soilCase struct {
		name      string
		kind      string // "Humus" | "Mineral"
		horizon   *string
		upper     *float64
		lower     *float64
		wantValid bool
	}
	matrix := []soilCase{
		{"upland_Lv_valid", "Humus", ptrString("Lv"), ptrFloat64(6), ptrFloat64(2), true},
		{"upland_2Lv_valid", "Humus", ptrString("2Lv"), ptrFloat64(4), ptrFloat64(1), true},
		{"wetland_Of_valid", "Humus", ptrString("Of"), ptrFloat64(0), ptrFloat64(15), true},
		{"wetland_2Of1_valid", "Humus", ptrString("2Of1"), ptrFloat64(15), ptrFloat64(40), true},
		{"mineral_Ah_valid", "Mineral", ptrString("Ah"), ptrFloat64(0), ptrFloat64(12), true},
		{"mineral_IIBm_valid", "Mineral", ptrString("IIBm"), ptrFloat64(12), ptrFloat64(45), true},
		{"upland_Lv_inverted", "Humus", ptrString("Lv"), ptrFloat64(0), ptrFloat64(6), false},
		{"upland_2L_inverted", "Humus", ptrString("2L"), ptrFloat64(0), ptrFloat64(10), false},
		{"wetland_Of_inverted", "Humus", ptrString("Of"), ptrFloat64(15), ptrFloat64(5), false},
		{"wetland_2Of1_inverted", "Humus", ptrString("2Of1"), ptrFloat64(10), ptrFloat64(0), false},
		{"mineral_IXAh_inverted", "Mineral", ptrString("IXAh"), ptrFloat64(10), ptrFloat64(0), false},
		{"mineral_blank_inverted", "Mineral", ptrString(""), ptrFloat64(30), ptrFloat64(10), false},
		{"mineral_null_inverted", "Mineral", nil, ptrFloat64(30), ptrFloat64(10), false},
		{"upland_Lv_negative", "Humus", ptrString("Lv"), ptrFloat64(-1), ptrFloat64(-5), false},
		{"wetland_Of_negative", "Humus", ptrString("Of"), ptrFloat64(-10), ptrFloat64(-5), false},
		{"mineral_Ah_negative", "Mineral", ptrString("Ah"), ptrFloat64(-5), ptrFloat64(15), false},
		{"upland_single_sided_negative", "Humus", ptrString("Lv"), ptrFloat64(-5), nil, false},
	}

	for idx, tc := range matrix {
		t.Run(tc.name, func(t *testing.T) {
			// (1) Canonical vprocore + cloudsync validator parity
			hStr := ""
			if tc.horizon != nil {
				hStr = *tc.horizon
			}
			vErr := vprocore.ValidateSoilHorizonDepthSign(tc.kind, tc.horizon, tc.upper, tc.lower)
			cErr := cloudsync.ValidateLMH25HorizonDepth(tc.kind, hStr, tc.upper, tc.lower)
			if (vErr == nil) != tc.wantValid || (cErr == nil) != tc.wantValid {
				t.Fatalf("validator parity mismatch: wantValid=%v vprocore=%v cloudsync=%v", tc.wantValid, vErr, cErr)
			}

			// (2) PlotService writer (via ContextService)
			if tc.kind == "Humus" {
				err := contexts.SaveHumusRecord(state.ContextID, vprocore.HumusRecord{
					PlotNumber: "SLVAL",
					Horizon:    tc.horizon,
					UpperDepth: tc.upper,
					LowerDepth: tc.lower,
				})
				if tc.horizon != nil && hStr != "" && (err == nil) != tc.wantValid {
					t.Fatalf("ContextService.SaveHumusRecord(%s): err=%v wantValid=%v", tc.name, err, tc.wantValid)
				}
			} else {
				err := contexts.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
					PlotNumber: "SLVAL",
					Horizon:    tc.horizon,
					UpperDepth: tc.upper,
					LowerDepth: tc.lower,
				})
				if tc.horizon != nil && hStr != "" && (err == nil) != tc.wantValid {
					t.Fatalf("ContextService.SaveMineralRecord(%s): err=%v wantValid=%v", tc.name, err, tc.wantValid)
				}
			}

			// (3) Datasheet InsertDatasheetChildRow (including NULL/blank Horizon!)
			cells := map[string]vprocore.ProjectMetadataCell{}
			if tc.horizon == nil || *tc.horizon == "" {
				cells["Horizon"] = nullCell()
			} else {
				cells["Horizon"] = textCell(*tc.horizon)
			}
			if tc.upper != nil {
				cells["UpperDepth"] = realCell(*tc.upper)
			}
			if tc.lower != nil {
				cells["LowerDepth"] = realCell(*tc.lower)
			}
			_, dsErr := datasheet.InsertDatasheetChildRow(ctx, contexts, state.ContextID, datasheet.DatasheetInsertChildRowRequest{
				TableKey:   tc.kind,
				PlotNumber: "SLVAL",
				Cells:      cells,
			})
			if tc.horizon != nil && *tc.horizon != "" {
				if (dsErr == nil) != tc.wantValid {
					t.Fatalf("Datasheet.InsertDatasheetChildRow(%s): err=%v wantValid=%v", tc.name, dsErr, tc.wantValid)
				}
			} else if !tc.wantValid && dsErr == nil {
				t.Fatalf("Datasheet.InsertDatasheetChildRow(%s) accepted invalid NULL/blank horizon depths", tc.name)
			}

			// (4) TwoPageSoilService.CreateHorizon + Save (for non-empty Horizon)
			runTwoPageSoil := !testing.Short() ||
				tc.name == "upland_Lv_valid" ||
				tc.name == "wetland_2Of1_valid" ||
				tc.name == "mineral_Ah_valid" ||
				tc.name == "upland_Lv_inverted" ||
				tc.name == "wetland_Of_negative"
			if runTwoPageSoil && tc.horizon != nil && strings.TrimSpace(*tc.horizon) != "" {
				form := "SoilHumusXL"
				if tc.kind == "Mineral" {
					form = "SoilMineralXL"
				}
				origCreate, gErr := tpSoilSvc.GetOriginal(ctx, state.ContextID, "SLVAL", form)
				if gErr != nil {
					t.Fatalf("TwoPageSoilService.GetOriginal: %v", gErr)
				}
				createBytes, _ := json.Marshal(map[string]any{
					"requestId": fmt.Sprintf("b1c2d3e4-f5a6-4789-8abc-%012x", idx*2+1),
					"original":  origCreate,
					"horizon":   *tc.horizon,
					"edits":     []any{},
				})
				createdHorizon, cHzErr := tpSoilSvc.CreateHorizon(ctx, state.ContextID, string(createBytes))
				if cHzErr != nil || createdHorizon == nil || createdHorizon.History.CreatedRowID == nil {
					t.Fatalf("TwoPageSoilService.CreateHorizon(%s): res=%+v err=%v", tc.name, createdHorizon, cHzErr)
				}
				newRowID := *createdHorizon.History.CreatedRowID

				origSave, gErr := tpSoilSvc.GetOriginal(ctx, state.ContextID, "SLVAL", form)
				if gErr != nil {
					t.Fatalf("TwoPageSoilService.GetOriginal after CreateHorizon: %v", gErr)
				}
				var edits []map[string]any
				if tc.upper != nil {
					edits = append(edits, map[string]any{
						"contextId": state.ContextID,
						"form":      form,
						"rowId":     newRowID,
						"column":    "UpperDepth",
						"expected":  nullCell(),
						"value":     realCell(*tc.upper),
					})
				}
				if tc.lower != nil {
					edits = append(edits, map[string]any{
						"contextId": state.ContextID,
						"form":      form,
						"rowId":     newRowID,
						"column":    "LowerDepth",
						"expected":  nullCell(),
						"value":     realCell(*tc.lower),
					})
				}
				if len(edits) > 0 {
					saveBytes, _ := json.Marshal(map[string]any{
						"requestId": fmt.Sprintf("b1c2d3e4-f5a6-4789-8abc-%012x", idx*2+2),
						"original":  origSave,
						"edits":     edits,
					})
					_, tpErr := tpSoilSvc.Save(ctx, state.ContextID, string(saveBytes))
					if (tpErr == nil) != tc.wantValid {
						t.Fatalf("TwoPageSoilService.Save(%s): err=%v wantValid=%v", tc.name, tpErr, tc.wantValid)
					}
				}
			}
		})
	}

	// Clean SLVAL and verify invalid row injected on disk is caught by BOTH Validation.RunComplianceValidation and CloudSync.PreviewStagingSubmission!
	db := s0OpenRW(t, state.ProjectPath)
	if _, err := db.Exec(`DELETE FROM Sample_Humus WHERE PlotNumber = 'SLVAL'; DELETE FROM Sample_Mineral WHERE PlotNumber = 'SLVAL'`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth) VALUES (888001, 'SLVAL', 'Lv', -5.0, NULL)`); err != nil {
		t.Fatal(err)
	}
	compRep, err := validation.RunComplianceValidation(contexts, ctx, state.ContextID, validation.ComplianceOptions{})
	if err != nil {
		t.Fatal(err)
	}
	caughtCompliance := false
	for _, f := range compRep.BoundsFindings {
		if f.PlotNumber == "SLVAL" {
			caughtCompliance = true
		}
	}
	if !caughtCompliance {
		t.Fatalf("RunComplianceValidation missed single-sided negative Humus Lv (-5..NULL) on SLVAL: %+v", compRep.BoundsFindings)
	}
	cloudMgr := cloudsync.NewManager(t.TempDir(), nil)
	defer cloudMgr.Close()
	preflightBad, err := cloudMgr.PreviewStagingSubmission(ctx, contexts, state.ContextID, false, nil)
	if err != nil || preflightBad.CompliancePassed || preflightBad.BlockingErrorCount == 0 {
		t.Fatalf("CloudSync PreviewStagingSubmission failed to block corrupt LMH25 row: %+v (%v)", preflightBad, err)
	}
	if _, err := db.Exec(`DELETE FROM Sample_Humus WHERE PlotNumber = 'SLVAL'`); err != nil {
		t.Fatal(err)
	}

	// Profile ordering matrix across ALL 5 readers/exporters:
	// Insert discontinuity-prefixed wetland horizons in scrambled rowid order [7Oh (45..80), 7Of (0..15), 7Om (15..45)]
	// and upland horizons in scrambled rowid order [7Fm (2..0), 7Lv (6..2)] (distinct from preexisting Sample_Humus horizons).
	if _, err := db.Exec(`
		INSERT INTO Sample_Humus (ID, PlotNumber, Horizon, UpperDepth, LowerDepth) VALUES
		(7001, 'WET01', '7Oh', 45.0, 80.0),
		(7002, 'WET01', '7Of', 0.0, 15.0),
		(7003, 'WET01', '7Om', 15.0, 45.0),
		(7004, 'UP01', '7Fm', 2.0, 0.0),
		(7005, 'UP01', '7Lv', 6.0, 2.0);
		UPDATE Sample_Env SET Latitude = 54.1, Longitude = 126.2 WHERE PlotNumber IN ('WET01', 'UP01');
	`); err != nil {
		t.Fatal(err)
	}

	wantWet := []string{"7Of", "7Om", "7Oh"}
	wantUp := []string{"7Lv", "7Fm"}

	// Reader 1: ContextService.ListHumusRecords (PlotService)
	derefHz := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	wetList, err := contexts.ListHumusRecords(ctx, state.ContextID, "WET01")
	if err != nil || len(wetList) != 3 || !reflect.DeepEqual([]string{derefHz(wetList[0].Horizon), derefHz(wetList[1].Horizon), derefHz(wetList[2].Horizon)}, wantWet) {
		t.Fatalf("ListHumusRecords(WET01) = %+v (%v), want %v", wetList, err, wantWet)
	}
	upList, err := contexts.ListHumusRecords(ctx, state.ContextID, "UP01")
	if err != nil || len(upList) != 2 || !reflect.DeepEqual([]string{derefHz(upList[0].Horizon), derefHz(upList[1].Horizon)}, wantUp) {
		t.Fatalf("ListHumusRecords(UP01) = %+v (%v), want %v", upList, err, wantUp)
	}

	// Reader 2: twopage.ReadTwoPageSoilOriginal
	tpWet, err := tpSoilSvc.GetOriginal(ctx, state.ContextID, "WET01", "SoilHumusXL")
	if err != nil || len(tpWet.Records.Rows) != 3 {
		t.Fatalf("TwoPageSoilService.GetOriginal(WET01): %v", err)
	}
	tpUp, err := tpSoilSvc.GetOriginal(ctx, state.ContextID, "UP01", "SoilHumusXL")
	if err != nil || len(tpUp.Records.Rows) != 2 {
		t.Fatalf("TwoPageSoilService.GetOriginal(UP01): %v", err)
	}
	hzCol := -1
	for i, c := range tpWet.Records.Columns {
		if c.Name == "Horizon" {
			hzCol = i
			break
		}
	}
	gotTPWet := []string{*tpWet.Records.Rows[0].Cells[hzCol].Text, *tpWet.Records.Rows[1].Cells[hzCol].Text, *tpWet.Records.Rows[2].Cells[hzCol].Text}
	gotTPUp := []string{*tpUp.Records.Rows[0].Cells[hzCol].Text, *tpUp.Records.Rows[1].Cells[hzCol].Text}
	if !reflect.DeepEqual(gotTPWet, wantWet) || !reflect.DeepEqual(gotTPUp, wantUp) {
		t.Fatalf("TwoPageSoil ordering = wet %v / up %v, want %v / %v", gotTPWet, gotTPUp, wantWet, wantUp)
	}

	// Reader 3: DatasheetService.GetDatasheetPage
	dsHumus, err := datasheet.GetDatasheetPage(ctx, contexts, state.ContextID, datasheet.DatasheetPageRequest{
		TableKey: "Humus",
		Limit:    500,
	})
	if err != nil {
		t.Fatal(err)
	}
	dsPlotIdx, dsHzIdx := -1, -1
	for i, c := range dsHumus.Columns {
		if c.Name == "PlotNumber" {
			dsPlotIdx = i
		}
		if c.Name == "Horizon" {
			dsHzIdx = i
		}
	}
	var dsWet, dsUp []string
	for _, r := range dsHumus.Rows {
		if r.Cells[dsPlotIdx].Text == nil || r.Cells[dsHzIdx].Text == nil {
			continue
		}
		switch *r.Cells[dsPlotIdx].Text {
		case "WET01":
			dsWet = append(dsWet, *r.Cells[dsHzIdx].Text)
		case "UP01":
			dsUp = append(dsUp, *r.Cells[dsHzIdx].Text)
		}
	}
	if !reflect.DeepEqual(dsWet, wantWet) || !reflect.DeepEqual(dsUp, wantUp) {
		t.Fatalf("Datasheet Humus ordering = wet %v / up %v, want %v / %v", dsWet, dsUp, wantWet, wantUp)
	}

	// Reader 4: interchange.ExportGeoPackage (with IncludeAttributeTables: true)
	gpkgPath := filepath.Join(t.TempDir(), "soil_order.gpkg")
	if _, err := interchange.ExportGeoPackage(contexts, ctx, state.ContextID, interchange.GeoPackageExportRequest{
		DestinationPath:        gpkgPath,
		IncludeAttributeTables: true,
	}); err != nil {
		t.Fatalf("ExportGeoPackage: %v", err)
	}
	gpkgDB := s0OpenRW(t, gpkgPath)
	queryGpkgHorizons := func(plot string) []string {
		r, qErr := gpkgDB.Query(`SELECT Horizon FROM humus WHERE PlotNumber = ? ORDER BY fid`, plot)
		if qErr != nil {
			t.Fatalf("query gpkg humus: %v", qErr)
		}
		defer r.Close()
		var out []string
		for r.Next() {
			var h string
			if err := r.Scan(&h); err != nil {
				t.Fatal(err)
			}
			out = append(out, h)
		}
		return out
	}
	if got := queryGpkgHorizons("WET01"); !reflect.DeepEqual(got, wantWet) {
		t.Fatalf("ExportGeoPackage WET01 order = %v, want %v", got, wantWet)
	}
	if got := queryGpkgHorizons("UP01"); !reflect.DeepEqual(got, wantUp) {
		t.Fatalf("ExportGeoPackage UP01 order = %v, want %v", got, wantUp)
	}

	// Reader 5: interchange.ExportProjectRDS (pure-Go RDS v3 serializer; verify humus table row count & serialized CHARSXP order!)
	rdsPath := filepath.Join(t.TempDir(), "soil_order.rds")
	rdsOut, err := interchange.ExportProjectRDS(contexts, ctx, state.ContextID, interchange.RDSExportRequest{
		DestinationPath: rdsPath,
	})
	if err != nil {
		t.Fatalf("ExportProjectRDS: %v", err)
	}
	foundHumusDF := false
	for _, tbl := range rdsOut.Tables {
		if tbl.Name == "humus" && tbl.RowCount >= 5 {
			foundHumusDF = true
		}
	}
	if !foundHumusDF {
		t.Fatalf("ExportProjectRDS missing humus table >= 5 rows: %+v", rdsOut.Tables)
	}
	rdsGz, err := os.Open(rdsPath)
	if err != nil {
		t.Fatal(err)
	}
	gzReader, err := gzip.NewReader(rdsGz)
	if err != nil {
		_ = rdsGz.Close()
		t.Fatal(err)
	}
	rdsPayload, err := io.ReadAll(gzReader)
	_ = gzReader.Close()
	_ = rdsGz.Close()
	if err != nil {
		t.Fatal(err)
	}
	// In R XDR v3 CHARSXP vectors, each 3-byte ASCII string is preceded by 4-byte length 0x00000003.
	idxLv := bytes.Index(rdsPayload, []byte{0, 0, 0, 3, '7', 'L', 'v'})
	idxFm := bytes.Index(rdsPayload, []byte{0, 0, 0, 3, '7', 'F', 'm'})
	idxOf := bytes.Index(rdsPayload, []byte{0, 0, 0, 3, '7', 'O', 'f'})
	idxOm := bytes.Index(rdsPayload, []byte{0, 0, 0, 3, '7', 'O', 'm'})
	idxOh := bytes.Index(rdsPayload, []byte{0, 0, 0, 3, '7', 'O', 'h'})
	if idxLv < 0 || idxFm < 0 || !(idxLv < idxFm) {
		t.Fatalf("ExportProjectRDS UP01 horizon order violated (idxLv=%d idxFm=%d)", idxLv, idxFm)
	}
	if idxOf < 0 || idxOm < 0 || idxOh < 0 || !(idxOf < idxOm && idxOm < idxOh) {
		t.Fatalf("ExportProjectRDS WET01 horizon order violated (idxOf=%d idxOm=%d idxOh=%d)", idxOf, idxOm, idxOh)
	}
}

// 4. AGENTS.md §3.5: UTF-16 code-unit bounds (including supplementary-plane surrogate pairs),
// atomic <Project>_Audit provenance, and monotonic __VPRO_* child/hierarchy ID non-reuse.
func TestS0Matrix_UTF16BoundsAuditProvenanceAndMonotonicIdentityNonReuse(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	contexts, state := openS0MatrixContext(t)

	// (a) UTF-16 code-unit bounds with supplementary-plane rune '🌿' (U+1F33F = 1 UTF-8 rune, 2 UTF-16 code units!)
	// PlotNumber <= 7 UTF-16 code units: "ABCDEF🌿" = 7 runes / 8 UTF-16 units (rejected!).
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "ABCDEF🌿"}); err == nil {
		t.Fatal("CreatePlot accepted 8-UTF16-unit PlotNumber 'ABCDEF🌿' (> 7)")
	}
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "U16PLT1"}); err != nil {
		t.Fatalf("CreatePlot(U16PLT1): %v", err)
	}

	// Species <= 8, Horizon <= 8, Texture <= 4, Colour <= 14 UTF-16 code units across PlotService, SIVI, TwoPage, Datasheet!
	layer := "1"
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "U16PLT1",
		Species:    "ABCDEFG🌿", // 8 runes = 9 UTF-16 code units (> 8)
		Layer:      &layer,
		Cover1:     ptrFloat64(10),
	}); err == nil {
		t.Fatal("SaveVegRecord accepted 9-UTF16-unit Species")
	}

	siviCreateSvc, err := sivi.NewSIVICreationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	badSiviSpp, _ := json.Marshal(sourceform.SiviCreationRequest{
		RequestID: nextS0UUID(),
		ContextID: state.ContextID,
		Project:   "Sample",
		Plot:      "U16PLT1",
		Form:      "SubVegA-SIVI_BC",
		Species:   "ABCDEFG🌿",
		Covers:    []sourceform.SiviCreationCover{{Column: "Cover1", Value: realCell(10)}},
	})
	if _, err := siviCreateSvc.Create(ctx, state.ContextID, string(badSiviSpp)); err == nil {
		t.Fatal("SIVICreationService.Create accepted 9-UTF16-unit Species")
	}

	if _, err := twopage.CreateTwoPageVegetationRow(contexts, ctx, state.ContextID, twopage.CreateTwoPageVegetationRequest{
		RequestID:  nextS0UUID(),
		PlotNumber: "U16PLT1",
		Form:       "SubVegAXL_BC",
		Species:    "ABCDEFG🌿",
		Covers:     map[string]*float64{"Cover1": ptrFloat64(10)},
	}); err == nil {
		t.Fatal("CreateTwoPageVegetationRow accepted 9-UTF16-unit Species")
	}

	if err := contexts.SaveHumusRecord(state.ContextID, vprocore.HumusRecord{
		PlotNumber: "U16PLT1",
		Horizon:    ptrString("LvABCDE🌿"), // 9 UTF-16 code units (> 8)
		UpperDepth: ptrFloat64(5),
		LowerDepth: ptrFloat64(0),
	}); err == nil {
		t.Fatal("SaveHumusRecord accepted 9-UTF16-unit Horizon")
	}
	if err := contexts.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
		PlotNumber: "U16PLT1",
		Horizon:    ptrString("Bm"),
		UpperDepth: ptrFloat64(0),
		LowerDepth: ptrFloat64(20),
		Texture:    ptrString("ABC🌿"), // 4 runes = 5 UTF-16 code units (> 4)
	}); err == nil {
		t.Fatal("SaveMineralRecord accepted 5-UTF16-unit Texture")
	}
	if err := contexts.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{
		PlotNumber: "U16PLT1",
		Horizon:    ptrString("Bm"),
		UpperDepth: ptrFloat64(0),
		LowerDepth: ptrFloat64(20),
		Colour:     ptrString("10YR 4/3 ABCD🌿"), // 15 UTF-16 code units (> 14)
	}); err == nil {
		t.Fatal("SaveMineralRecord accepted 15-UTF16-unit Colour")
	}
	if _, err := datasheet.InsertDatasheetChildRow(ctx, contexts, state.ContextID, datasheet.DatasheetInsertChildRowRequest{
		TableKey:   "Mineral",
		PlotNumber: "U16PLT1",
		Cells: map[string]vprocore.ProjectMetadataCell{
			"Horizon": textCell("Bm"),
			"Texture": textCell("ABC🌿"),
		},
	}); err == nil {
		t.Fatal("Datasheet.InsertDatasheetChildRow accepted 5-UTF16-unit Texture")
	}

	// (b) Monotonic __VPRO_ChildIdentity non-reuse after deletion + <Project>_Audit provenance across PlotService, SIVI, TwoPage, Datasheet!
	auditBefore := s0TableCount(t, state.ProjectPath, "Sample_Audit")
	for _, spp := range []string{"TSUGHET", "PSEUMEN", "THUJPLI"} {
		if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
			PlotNumber: "U16PLT1",
			Species:    spp,
			Layer:      &layer,
			Cover1:     ptrFloat64(12.0),
		}); err != nil {
			t.Fatal(err)
		}
	}
	initialVeg, err := contexts.ListVegRecords(ctx, state.ContextID, "U16PLT1")
	if err != nil || len(initialVeg) != 3 {
		t.Fatalf("ListVegRecords(U16PLT1): %+v (%v)", initialVeg, err)
	}
	maxInitialID := initialVeg[0].ID
	for _, r := range initialVeg[1:] {
		if r.ID > maxInitialID {
			maxInitialID = r.ID
		}
	}
	// Delete the highest ID row, then insert new rows via PlotService, Datasheet, SIVI, and TwoPage:
	// NONE of them may reuse deleted maxInitialID!
	if err := contexts.DeleteVegRecord(state.ContextID, "U16PLT1", maxInitialID); err != nil {
		t.Fatalf("DeleteVegRecord(%d): %v", maxInitialID, err)
	}
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "U16PLT1",
		Species:    "ABIEAMA",
		Layer:      &layer,
		Cover1:     ptrFloat64(8.0),
	}); err != nil {
		t.Fatal(err)
	}
	dsIns, err := datasheet.InsertDatasheetChildRow(ctx, contexts, state.ContextID, datasheet.DatasheetInsertChildRowRequest{
		TableKey:   "Veg",
		PlotNumber: "U16PLT1",
		Cells: map[string]vprocore.ProjectMetadataCell{
			"Species": textCell("PICEENG"),
			"Cover1":  realCell(6.0),
		},
	})
	if err != nil || dsIns == nil {
		t.Fatalf("Datasheet.InsertDatasheetChildRow: %+v (%v)", dsIns, err)
	}
	siviAfterDelReq, _ := json.Marshal(sourceform.SiviCreationRequest{
		RequestID: nextS0UUID(),
		ContextID: state.ContextID,
		Project:   "Sample",
		Plot:      "U16PLT1",
		Form:      "SubVegA-SIVI_BC",
		Species:   "ALNURUB",
		Covers:    []sourceform.SiviCreationCover{{Column: "Cover1", Value: realCell(5.0)}},
	})
	if _, err := siviCreateSvc.Create(ctx, state.ContextID, string(siviAfterDelReq)); err != nil {
		t.Fatalf("SIVICreationService.Create after delete: %v", err)
	}
	if _, err := twopage.CreateTwoPageVegetationRow(contexts, ctx, state.ContextID, twopage.CreateTwoPageVegetationRequest{
		RequestID:  nextS0UUID(),
		PlotNumber: "U16PLT1",
		Form:       "SubVegAXL_BC",
		Species:    "PINUCON",
		Covers:     map[string]*float64{"Cover1": ptrFloat64(4.0)},
	}); err != nil {
		t.Fatalf("CreateTwoPageVegetationRow after delete: %v", err)
	}

	afterVeg, err := contexts.ListVegRecords(ctx, state.ContextID, "U16PLT1")
	if err != nil {
		t.Fatal(err)
	}
	var newIDs []int64
	for _, r := range afterVeg {
		switch r.Species {
		case "ABIEAMA", "PICEENG", "ALNURUB", "PINUCON":
			newIDs = append(newIDs, r.ID)
			if r.ID <= maxInitialID {
				t.Fatalf("child ID %d for %s reused or regressed below deleted max ID %d!", r.ID, r.Species, maxInitialID)
			}
		}
	}
	if len(newIDs) != 4 {
		t.Fatalf("expected 4 newly inserted veg rows across PlotService/Datasheet/SIVI/TwoPage, got %v", newIDs)
	}

	auditAfter := s0TableCount(t, state.ProjectPath, "Sample_Audit")
	if auditAfter <= auditBefore {
		t.Fatalf("expected Sample_Audit row count to advance on child writes/deletes (%d -> %d)", auditBefore, auditAfter)
	}

	// (c) Hierarchy monotonic ID non-reuse across DeleteHierarchyNode + ProjectOps.SaveProjectAs (prefix-renamed HierSrcProj_Hierarchy -> SavedAfterDel_Hierarchy)!
	hierSrcPath := filepath.Join(t.TempDir(), "HierSrcProj.db")
	hierSrcRes, err := projectops.CreateNewProject(contexts, ctx, state.ContextID, projectops.NewProjectRequest{
		ProjectName:       "HierSrcProj",
		DestinationPath:   hierSrcPath,
		ActivateOnSuccess: true,
	})
	if err != nil || hierSrcRes.State == nil {
		t.Fatalf("CreateNewProject(HierSrcProj): %+v (%v)", hierSrcRes, err)
	}
	state = *hierSrcRes.State
	if err := contexts.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "HS001"}); err != nil {
		t.Fatal(err)
	}
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: "HS001",
		Species:    "TSUGHET",
		Layer:      &layer,
		Cover1:     ptrFloat64(20.0),
	}); err != nil {
		t.Fatal(err)
	}
	hCreated, err := classification.CreateHierarchyTable(ctx, contexts, state.ContextID, classification.CreateHierarchyTableRequest{
		Name:        "HierSrcProj",
		Destination: "project",
		Activate:    true,
	})
	if err != nil || hCreated == nil || hCreated.NewState == nil {
		t.Fatalf("CreateHierarchyTable: %+v (%v)", hCreated, err)
	}
	state = *hCreated.NewState
	var addedNodeIDs []int64
	for i, nm := range []string{"OrderA", "SuborderB", "AllianceC"} {
		res, err := classification.AddHierarchyNode(ctx, contexts, state.ContextID, classification.HierarchyAddNodeRequest{
			Name:  nm,
			Level: int64(i + 4),
		})
		if err != nil || res == nil {
			t.Fatalf("AddHierarchyNode(%s): %+v (%v)", nm, res, err)
		}
		addedNodeIDs = append(addedNodeIDs, res.NodeID)
	}
	deletedNodeID := addedNodeIDs[len(addedNodeIDs)-1] // node 3
	if _, err := classification.DeleteHierarchyNode(ctx, contexts, state.ContextID, classification.HierarchyDeleteNodeRequest{
		NodeID:          deletedNodeID,
		CascadeChildren: false,
	}); err != nil {
		t.Fatalf("DeleteHierarchyNode(%d): %v", deletedNodeID, err)
	}

	savedPath := filepath.Join(t.TempDir(), "SavedAfterDel.db")
	savedProj, err := projectops.SaveProjectAs(contexts, ctx, state.ContextID, projectops.SaveProjectAsRequest{
		NewProjectName:    "SavedAfterDel",
		DestinationPath:   savedPath,
		ActivateOnSuccess: true,
	})
	if err != nil || savedProj.State == nil {
		t.Fatalf("SaveProjectAs: %+v (%v)", savedProj, err)
	}
	state, err = contexts.SwitchContext(savedProj.State.ContextID, vprocore.ContextSelection{
		Project:       "SavedAfterDel",
		ProjectPath:   savedPath,
		SU:            "None",
		Hierarchy:     "SavedAfterDel",
		HierarchyPath: savedPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext(S0Hier after SaveProjectAs): %v", err)
	}
	nextNode, err := classification.AddHierarchyNode(ctx, contexts, state.ContextID, classification.HierarchyAddNodeRequest{
		Name:  "AssociationD",
		Level: 8,
	})
	if err != nil || nextNode == nil {
		t.Fatalf("AddHierarchyNode after SaveProjectAs: %+v (%v)", nextNode, err)
	}
	if nextNode.NodeID <= deletedNodeID {
		t.Fatalf("AddHierarchyNode after SaveProjectAs reused deleted ID %d (got %d)", deletedNodeID, nextNode.NodeID)
	}

	// (d) TurboVeg import seeds __VPRO_ChildIdentity so deleting max imported _Veg ID never reuses it!
	tvXML := filepath.Join(t.TempDir(), "seed_id.xml")
	if _, err := interchange.ExportTurboVeg(contexts, ctx, state.ContextID, interchange.TurboVegExportRequest{
		Format:          "xml",
		DestinationPath: tvXML,
	}); err != nil {
		t.Fatalf("ExportTurboVeg: %v", err)
	}
	tvProjPath := filepath.Join(t.TempDir(), "TVSeeded.db")
	tvImported, err := interchange.ImportTurboVeg(contexts, ctx, state.ContextID, interchange.TurboVegImportRequest{
		SourcePath:        tvXML,
		TargetProject:     "TVSeeded",
		DestinationPath:   tvProjPath,
		ActivateOnSuccess: true,
	})
	if err != nil || tvImported.State == nil {
		t.Fatalf("ImportTurboVeg(ActivateOnSuccess): %+v (%v)", tvImported, err)
	}
	state = *tvImported.State
	tvDB := s0OpenRW(t, tvProjPath)
	var maxTVVegID int64
	var maxTVPlot string
	if err := tvDB.QueryRow(`SELECT ID, PlotNumber FROM TVSeeded_Veg ORDER BY ID DESC LIMIT 1`).Scan(&maxTVVegID, &maxTVPlot); err != nil {
		t.Fatalf("query max TVSeeded_Veg ID: %v", err)
	}
	if err := contexts.DeleteVegRecord(state.ContextID, maxTVPlot, maxTVVegID); err != nil {
		t.Fatalf("DeleteVegRecord on TVSeeded (%s, %d): %v", maxTVPlot, maxTVVegID, err)
	}
	if err := contexts.SaveVegRecord(state.ContextID, vprocore.VegRecord{
		PlotNumber: maxTVPlot,
		Species:    "TSUGHET",
		Layer:      &layer,
		Cover1:     ptrFloat64(15.0),
	}); err != nil {
		t.Fatalf("SaveVegRecord after delete on TVSeeded: %v", err)
	}
	var newMaxTVVegID int64
	if err := tvDB.QueryRow(`SELECT MAX(ID) FROM TVSeeded_Veg`).Scan(&newMaxTVVegID); err != nil {
		t.Fatal(err)
	}
	if newMaxTVVegID <= maxTVVegID {
		t.Fatalf("TurboVeg-imported project reused deleted max Veg ID %d (got %d)", maxTVVegID, newMaxTVVegID)
	}
}
