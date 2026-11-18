package interchange

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestWave2S45VP06StartDateAndAccessUTF16Quarantine(t *testing.T) {
	ctx := context.Background()
	dbPath := filepath.Join(t.TempDir(), "AccessBounds.db")
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rwc"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback() }()

	for _, ddl := range []string{
		`CREATE TABLE "__VPRO_ImportQuarantine" ("ID" INTEGER PRIMARY KEY AUTOINCREMENT, "SourceTable" TEXT NOT NULL, "SourceRow" INTEGER NOT NULL, "PlotNumber" TEXT NOT NULL, "Reason" TEXT NOT NULL, "PayloadJSON" TEXT NOT NULL)`,
		`CREATE TABLE "__VPRO_ChildIdentity" ("ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable", "ID"))`,
		`CREATE TABLE "T_Admin" ("Plot" VARCHAR, "StartDate" TEXT, "SitePlotQuality" VARCHAR, "VegPlotQuality" VARCHAR, "SoilPlotQuality" VARCHAR, "UpdatedFromCards" BOOLEAN, "EnteredBy" VARCHAR, "UserSiteUnit" VARCHAR, "BECSiteUnit" VARCHAR, "SiteUnitShortName" VARCHAR, "SiteUnitLongName" VARCHAR, "OfficeNotes" VARCHAR, "HumusThickness" DOUBLE)`,
		`CREATE TABLE "T_Mineral" ("ID" INTEGER, "PlotNumber" VARCHAR, "Horizon" VARCHAR, "Texture" VARCHAR, "Colour" VARCHAR)`,
		`CREATE TABLE "T_Veg" ("ID" INTEGER, "PlotNumber" VARCHAR, "Species" VARCHAR)`,
	} {
		if _, err := tx.ExecContext(ctx, ddl); err != nil {
			t.Fatal(err)
		}
	}

	qStmt, err := tx.PrepareContext(ctx, `INSERT INTO "__VPRO_ImportQuarantine" ("SourceTable","SourceRow","PlotNumber","Reason","PayloadJSON") VALUES (?,?,?,?,?)`)
	if err != nil {
		t.Fatal(err)
	}
	defer qStmt.Close()
	cStmt, err := tx.PrepareContext(ctx, `INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable","ID") VALUES (?,?)`)
	if err != nil {
		t.Fatal(err)
	}
	defer cStmt.Close()

	// 1. Verify vp06AdminFromEnvMapping populates _Admin.StartDate from USysConvE.Date and enforces Plot <= 7 UTF-16 units.
	adminCols := []accessreader.Column{
		{Name: "PlotNumber", Type: "text"}, {Name: "Date", Type: "text"},
		{Name: "SitePlotQuality", Type: "text"}, {Name: "VegPlotQuality", Type: "text"},
		{Name: "SoilPlotQuality", Type: "text"}, {Name: "UpdatedFromCards", Type: "boolean"},
		{Name: "EnteredBy", Type: "text"}, {Name: "UserSiteUnit", Type: "text"},
		{Name: "BECSiteUnit", Type: "text"}, {Name: "SiteUnitShortName", Type: "text"},
		{Name: "SiteUnitLongName", Type: "text"}, {Name: "OfficeNotes", Type: "text"},
		{Name: "HumusThickness", Type: "real"},
	}
	envSrc := &fakeAccessRowSource{
		cols: adminCols,
		rows: []accessreader.Row{
			{"🌲🌲🌲", "2015-07-04", "Good", "Good", "Good", false, "tester", "SU1", "CWH", "short", "long", "note", 4.5},      // 6 UTF-16 units <= 7 -> pass
			{"🌲🌲🌲🌲", "2015-07-05", "Good", "Good", "Good", false, "tester", "SU1", "CWH", "short", "long", "note", 4.5},     // 8 UTF-16 units > 7 -> quarantine
		},
	}
	mAdmin, err := streamAccessSourceIntoSQLite(ctx, envSrc, tx, qStmt, cStmt, "VP06_Env", nil, []streamInsertSpec{
		{targetTable: "T_Admin", targetToSource: vp06AdminFromEnvMapping, plotSourceCol: "PlotNumber"},
	})
	if err != nil {
		t.Fatalf("VP06 Admin stream: %v", err)
	}
	if mAdmin.importedRows != 1 || mAdmin.malformedRows != 1 {
		t.Fatalf("expected 1 imported & 1 quarantined VP06 row, got %+v", mAdmin)
	}
	var gotStartDate string
	if err := tx.QueryRowContext(ctx, `SELECT "StartDate" FROM "T_Admin" WHERE "Plot"='🌲🌲🌲'`).Scan(&gotStartDate); err != nil || gotStartDate != "2015-07-04" {
		t.Fatalf("expected StartDate='2015-07-04' mapped from VP06 Date, got %q (err=%v)", gotStartDate, err)
	}

	// 2. Enforce UTF-16 code-unit bounds on _Veg (Species<=8) and _Mineral (Horizon<=8, Texture<=4, Colour<=14)
	validPlots := map[string]struct{}{"🌲🌲🌲": {}}
	vegSrc := &fakeAccessRowSource{
		cols: []accessreader.Column{{Name: "ID", Type: "integer"}, {Name: "PlotNumber", Type: "text"}, {Name: "Species", Type: "text"}},
		rows: []accessreader.Row{
			{int64(1), "🌲🌲🌲", "PSEUMEN"},
			{int64(2), "🌲🌲🌲", "🌲🌲🌲🌲🌲"}, // 10 UTF-16 units > 8 -> quarantine + reserve ID 2
		},
	}
	mVeg, err := streamAccessSourceIntoSQLite(ctx, vegSrc, tx, qStmt, cStmt, "VP06_Veg", validPlots, []streamInsertSpec{
		{targetTable: "T_Veg", requireEnvPlot: true, childIdentityTable: `"T_Veg"`},
	})
	if err != nil || mVeg.importedRows != 1 || mVeg.malformedRows != 1 {
		t.Fatalf("expected 1 imported & 1 quarantined _Veg row, got %+v (err=%v)", mVeg, err)
	}

	minSrc := &fakeAccessRowSource{
		cols: []accessreader.Column{
			{Name: "ID", Type: "integer"}, {Name: "PlotNumber", Type: "text"},
			{Name: "Horizon", Type: "text"}, {Name: "Texture", Type: "text"}, {Name: "Colour", Type: "text"},
		},
		rows: []accessreader.Row{
			{int64(10), "🌲🌲🌲", "Bm1", "SiCL", "10YR 4/4"},
			{int64(11), "🌲🌲🌲", "Horizon12", "SL", "10YR 4/4"},
			{int64(12), "🌲🌲🌲", "Bm2", "SiCLX", "10YR 4/4"},
			{int64(13), "🌲🌲🌲", "Bm3", "SL", "10YR 4/4 brownish"},
		},
	}
	mMin, err := streamAccessSourceIntoSQLite(ctx, minSrc, tx, qStmt, cStmt, "VP06_Mineral", validPlots, []streamInsertSpec{
		{targetTable: "T_Mineral", requireEnvPlot: true, childIdentityTable: `"T_Mineral"`},
	})
	if err != nil || mMin.importedRows != 1 || mMin.malformedRows != 3 {
		t.Fatalf("expected 1 imported & 3 quarantined _Mineral rows, got %+v (err=%v)", mMin, err)
	}

	var qCount, reservedID2 int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "__VPRO_ImportQuarantine" WHERE "Reason" LIKE 'utf16_length_bound:%'`).Scan(&qCount); err != nil || qCount != 5 {
		t.Fatalf("expected 5 utf16_length_bound quarantine rows, got %d (err=%v)", qCount, err)
	}
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE "ChildTable"='"T_Veg"' AND "ID"=2`).Scan(&reservedID2); err != nil || reservedID2 != 1 {
		t.Fatalf("expected quarantined Veg ID=2 reserved in __VPRO_ChildIdentity, got %d (err=%v)", reservedID2, err)
	}
}

func TestWave2S46AndS411VenusErrorsVersionAndTblEnvRejection(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	dir := t.TempDir()

	// 1. Access MDB child read error propagation must NOT silently discard errors
	_, err := parseVenusAccessTables(
		map[string]string{
			"usysversion":       "USysVersion",
			"tblprojectmanager": "tblProjectManager",
			"tblplotdata":       "tblPlotData",
			"tblsoil":           "tblSoil",
		},
		func(cands ...string) ([]map[string]string, bool, error) {
			switch cands[0] {
			case "USysVersion":
				return []map[string]string{{"version": "5", "beta": "0"}}, true, nil
			case "tblProjectManager":
				return []map[string]string{{"projectid": "P1", "projectname": "Proj1"}}, true, nil
			case "tblPlotData":
				return []map[string]string{{"plotid": "1", "projectid": "P1", "plotnumber": "P001"}}, true, nil
			case "tblSoil":
				return nil, false, errors.New("corrupt jet page in tblSoil")
			default:
				return nil, false, nil
			}
		},
		"deadbeef",
	)
	if err == nil || !strings.Contains(err.Error(), "tblSoil") {
		t.Fatalf("expected tblSoil error to propagate instead of silent discard, got %v", err)
	}

	// 2. Access MDB must reject VENUS < 5.0 and retired VENUS 4.2 tblEnv
	_, err = parseVenusAccessTables(
		map[string]string{"usysversion": "USysVersion", "tblplotdata": "tblPlotData"},
		func(cands ...string) ([]map[string]string, bool, error) {
			if cands[0] == "USysVersion" {
				return []map[string]string{{"version": "4", "beta": "2"}}, true, nil
			}
			return nil, false, nil
		},
		"deadbeef",
	)
	if err == nil || !strings.Contains(err.Error(), "< 5.0") {
		t.Fatalf("expected VENUS 4.2 USysVersion rejection, got %v", err)
	}

	_, err = parseVenusAccessTables(
		map[string]string{"usysversion": "USysVersion", "tblenv": "tblEnv"},
		func(cands ...string) ([]map[string]string, bool, error) {
			if cands[0] == "USysVersion" {
				return []map[string]string{{"version": "5", "beta": "0"}}, true, nil
			}
			return nil, false, nil
		},
		"deadbeef",
	)
	if err == nil || !strings.Contains(err.Error(), "tblEnv") {
		t.Fatalf("expected retired VENUS 4.2 tblEnv rejection, got %v", err)
	}

	// 3. XML archive must also reject VENUS < 5.0 and <tblEnv>
	for _, tc := range []struct {
		name, xmlBody, wantErr string
	}{
		{"old-ver", `<?xml version="1.0"?><dataroot><USysVersion><Version>4</Version><Beta>2</Beta></USysVersion><tblPlotData><PlotID>1</PlotID><PlotNumber>P1</PlotNumber></tblPlotData></dataroot>`, "< 5.0"},
		{"tblenv", `<?xml version="1.0"?><dataroot><USysVersion><Version>5</Version><Beta>0</Beta></USysVersion><tblEnv><PlotID>1</PlotID><PlotNumber>P1</PlotNumber></tblEnv></dataroot>`, "tblEnv"},
	} {
		xmlPath := filepath.Join(dir, tc.name+".xml")
		if err := os.WriteFile(xmlPath, []byte(tc.xmlBody), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := ImportVenusProject(service, ctx, state.ContextID, VenusImportRequest{
			SourcePath:      xmlPath,
			TargetProject:   "BadVenus",
			DestinationPath: filepath.Join(dir, tc.name+".db"),
		}); err == nil || !strings.Contains(err.Error(), tc.wantErr) {
			t.Fatalf("%s: expected error matching %q, got %v", tc.name, tc.wantErr, err)
		}
	}

	// 4. Child rows using untruncated >7 UTF-16 PlotNumber must still match parent plot & reserve __VPRO_ChildIdentity
	longPlotXML := filepath.Join(dir, "venus_longplot.xml")
	if err := os.WriteFile(longPlotXML, []byte(`<?xml version="1.0" encoding="UTF-8"?>
<dataroot>
  <USysVersion><Version>5</Version><Beta>0</Beta></USysVersion>
  <tblProjectManager><ProjectID>P1</ProjectID><ProjectName>LongPlotProj</ProjectName></tblProjectManager>
  <tblPlotData><PlotID>1</PlotID><ProjectID>P1</ProjectID><PlotNumber>PLOT123456</PlotNumber></tblPlotData>
  <tblVegLayer><VegLayerID>10</VegLayerID><PlotNumber>PLOT123456</PlotNumber><Layer>1</Layer></tblVegLayer>
  <tblVegSpecies><VegLayerID>10</VegLayerID><Species>PSEUMEN</Species><Cover>25.0</Cover></tblVegSpecies>
  <tblOrganicHorizons><PlotNumber>PLOT123456</PlotNumber><Horizon>Lh</Horizon><DepthUpper>4</DepthUpper><DepthLower>0</DepthLower></tblOrganicHorizons>
</dataroot>`), 0o600); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(dir, "LongPlotImp.db")
	res, err := ImportVenusProject(service, ctx, state.ContextID, VenusImportRequest{
		SourcePath:      longPlotXML,
		SourceProject:   "LongPlotProj",
		TargetProject:   "LongPlotImp",
		DestinationPath: dest,
	})
	if err != nil {
		t.Fatalf("ImportVenusProject(longPlot): %v", err)
	}
	if res.PlotCount != 1 || res.VegRowCount != 1 || res.HumusRowCount != 1 {
		t.Fatalf("expected child rows matched for >7-char PlotNumber, got %+v", res)
	}
	roDB, err := sqlutil.OpenReadOnly(dest)
	if err != nil {
		t.Fatal(err)
	}
	defer roDB.Close()
	var reserved int
	if err := roDB.QueryRow(`SELECT COUNT(*) FROM "__VPRO_ChildIdentity" WHERE "ChildTable" IN ('"LongPlotImp_Veg"','"LongPlotImp_Humus"')`).Scan(&reserved); err != nil || reserved != 2 {
		t.Fatalf("expected 2 __VPRO_ChildIdentity reservations after VENUS import, got %d (err=%v)", reserved, err)
	}
}

func TestWave2S47RDSFloat32CoverClampBelow100(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	vprotest.MutateContextFixture(t, state.ProjectPath, fmtInsertFloat32CoverSQL())

	rdsPath := filepath.Join(t.TempDir(), "float32_clamp.rds")
	out, err := ExportProjectRDS(service, ctx, state.ContextID, RDSExportRequest{
		DestinationPath: rdsPath,
	})
	if err != nil {
		t.Fatalf("ExportProjectRDS: %v", err)
	}
	if out.PlotCount < 1 {
		t.Fatalf("expected at least 1 plot in RDS export, got %+v", out)
	}

	// Directly inspect extractLongVegObservations so this test works regardless of whether R is installed.
	if err := sqlutil.AcquireMutexLease(ctx, &service.Projects.Sqlite.Mu); err != nil {
		t.Fatal(err)
	}
	tx, err := service.Projects.Sqlite.BeginReadSnapshot(ctx)
	service.Projects.Sqlite.Mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback() }()
	sppMeta, err := loadSpeciesLookupMeta(ctx, tx)
	if err != nil {
		t.Fatal(err)
	}
	_, suByPlot, err := loadScopedPlotSiteUnits(ctx, tx, service.Projects.Sqlite)
	if err != nil {
		t.Fatal(err)
	}
	obs, err := extractLongVegObservations(ctx, tx, service.Projects.Sqlite, suByPlot, sppMeta, nil)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, o := range obs {
		if o.PlotNumber == "CLAMP1" && o.Species == "PSEUMEN" {
			found = true
			if o.Cover >= 100.0 || math.Abs(o.Cover-99.9999) > 1e-6 {
				t.Fatalf("expected float32 99.999996 clamped strictly below 100.0 (99.9999), got %v", o.Cover)
			}
		}
	}
	if !found {
		t.Fatal("missing CLAMP1/PSEUMEN observation from extractLongVegObservations")
	}
}

func fmtInsertFloat32CoverSQL() string {
	return `
		INSERT INTO Sample_Env(PlotNumber) VALUES('CLAMP1');
		INSERT INTO Sample_Admin(Plot) VALUES('CLAMP1');
		INSERT INTO Sample_Veg(ID, PlotNumber, Species, Cover1) VALUES(990001, 'CLAMP1', 'PSEUMEN', 99.999996);
	`
}

func TestWave2S48TurboVegVProCodeSynonymOption(t *testing.T) {
	ctx := context.Background()
	service, state := vprotest.ContextServiceFixture(t)
	dir := t.TempDir()

	// Seed deterministic Codetype='S' synonym in VLists.USysAllSpecs:
	// canonical active code 'ABIEABI' ('U') <- synonym OldCode 'OLDSYNX' ('S').
	vprotest.MutateContextFixture(t, service.Projects.Sqlite.Attachments["VLists"], `
		INSERT INTO USysAllSpecs(Code, OldCode, ScientificName, Codetype, Lifeform) VALUES
			('ABIEABI', NULL, 'Abies testii', 'U', 1),
			('ABIEABI', 'OLDSYNX', 'Abies synonym', 'S', 1);
	`)

	xmlPath := filepath.Join(dir, "tv_syn_option.xml")
	xmlBody := `<?xml version="1.0" encoding="UTF-8"?>
<Plot_package UserName="VPro" TurbovegVersion="3.0">
  <Plots>
    <Plot releve_nr="1" guid="{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}">
      <header_data>
        <standard_record releve_nr="1" coverscale="00"/>
        <udf_record ispredefined="false" name="vpro_plot_number" type="C" len="7" dec="0" value="SYNT01"/>
      </header_data>
      <species_data>
        <species>
          <standard_record nr="1" cover="25.0" layer="1"/>
          <udf_record ispredefined="false" name="vpro_code" type="C" len="8" dec="0" value="OLDSYNX"/>
        </species>
      </species_data>
    </Plot>
  </Plots>
  <Lookup_tables>
    <Species_list>
      <species_record nr="1" code="OLDSYNX" name="Unknown foreign name" author="" valid_nr="1" valid_name="" valid_author="" synonym="no" nativename=""/>
    </Species_list>
  </Lookup_tables>
</Plot_package>`
	if err := os.WriteFile(xmlPath, []byte(xmlBody), 0o600); err != nil {
		t.Fatal(err)
	}

	// Default (ResolveVProCodeSynonyms=false): explicit vpro_code 'OLDSYNX' is preserved verbatim
	destDefault := filepath.Join(dir, "TVSynDefault.db")
	if _, err := ImportTurboVeg(service, ctx, state.ContextID, TurboVegImportRequest{
		SourcePath:      xmlPath,
		Format:          TurboVegFormatXML,
		TargetProject:   "TVSynDefault",
		DestinationPath: destDefault,
	}); err != nil {
		t.Fatalf("ImportTurboVeg(default): %v", err)
	}
	dbDefault, err := sqlutil.OpenReadOnly(destDefault)
	if err != nil {
		t.Fatal(err)
	}
	var gotDefault string
	if err := dbDefault.QueryRow(`SELECT Species FROM TVSynDefault_Veg WHERE PlotNumber='SYNT01'`).Scan(&gotDefault); err != nil {
		dbDefault.Close()
		t.Fatal(err)
	}
	// ENG-GO-004: every imported Veg and Metadata ID is reserved in __VPRO_ChildIdentity.
	var unreserved int
	if err := dbDefault.QueryRow(`SELECT
		(SELECT COUNT(*) FROM TVSynDefault_Veg v WHERE typeof(v.ID)='integer' AND v.ID > 0 AND NOT EXISTS (
			SELECT 1 FROM __VPRO_ChildIdentity c WHERE c.ChildTable = '"TVSynDefault_Veg"' AND c.ID = v.ID)) +
		(SELECT COUNT(*) FROM TVSynDefault_Metadata m WHERE typeof(m.ID)='integer' AND m.ID > 0 AND NOT EXISTS (
			SELECT 1 FROM __VPRO_ChildIdentity c WHERE c.ChildTable = '"TVSynDefault_Metadata"' AND c.ID = m.ID))`).Scan(&unreserved); err != nil || unreserved != 0 {
		dbDefault.Close()
		t.Fatalf("TurboVeg import left %d Veg/Metadata IDs unreserved (%v)", unreserved, err)
	}
	dbDefault.Close()
	if gotDefault != "OLDSYNX" {
		t.Fatalf("expected default ResolveVProCodeSynonyms=false to keep explicit vpro_code 'OLDSYNX', got %q", gotDefault)
	}

	// ResolveVProCodeSynonyms=true: explicit synonym vpro_code resolves to canonical 'ABIEABI'
	destResolved := filepath.Join(dir, "TVSynResolved.db")
	if _, err := ImportTurboVeg(service, ctx, state.ContextID, TurboVegImportRequest{
		SourcePath:              xmlPath,
		Format:                  TurboVegFormatXML,
		TargetProject:           "TVSynResolved",
		DestinationPath:         destResolved,
		ResolveVProCodeSynonyms: true,
	}); err != nil {
		t.Fatalf("ImportTurboVeg(resolveVProCodeSynonyms): %v", err)
	}
	dbResolved, err := sqlutil.OpenReadOnly(destResolved)
	if err != nil {
		t.Fatal(err)
	}
	defer dbResolved.Close()
	var gotResolved string
	if err := dbResolved.QueryRow(`SELECT Species FROM TVSynResolved_Veg WHERE PlotNumber='SYNT01'`).Scan(&gotResolved); err != nil {
		t.Fatal(err)
	}
	if gotResolved != "ABIEABI" {
		t.Fatalf("expected ResolveVProCodeSynonyms=true to map 'OLDSYNX' -> 'ABIEABI', got %q", gotResolved)
	}
}

func TestWave2S410PlotLabelServiceAndLocaleInvariantDecimals(t *testing.T) {
	service, state := plotLabelRegionalFixture(t)
	vprotest.MutateContextFixture(t, service.contexts.Projects.Sqlite.Attachments["project"],
		`UPDATE Sample_Env SET Zone=NULL,SubZone='dk',SiteSeries='01',PlotRepresenting='Forêt boréale' WHERE PlotNumber='LB001'`)
	service.format = func(time.Time) (plotLabelNativeDate, error) {
		return plotLabelNativeDate{"11 octobre 2026", "fr-CA", "d MMMM yyyy"}, nil
	}
	preview, err := service.GetPreview(t.Context(), state.ContextID, "LB001")
	if err != nil || preview == nil || preview.Header.Zone != nil {
		t.Fatalf("GetPreview with NULL Zone & fr-CA failed: preview=%+v err=%v", preview, err)
	}
	fonts, err := loadBundledPlotLabelPDFFonts(t.Context())
	if err != nil {
		t.Fatalf("loadBundledPlotLabelPDFFonts: %v", err)
	}
	// Simulate comma-decimal host environment variable while rendering PDF
	t.Setenv("LC_ALL", "fr_CA.UTF-8")
	t.Setenv("LC_NUMERIC", "fr_CA.UTF-8")
	pdfBytes, err := renderPlotLabelPDF(t.Context(), *preview, fonts)
	if err != nil {
		t.Fatalf("renderPlotLabelPDF(NULL Zone, fr-CA, accented): %v", err)
	}
	if !bytes.HasPrefix(pdfBytes, []byte("%PDF-1.")) {
		t.Fatalf("expected valid PDF header, got prefix %q", string(pdfBytes[:min(16, len(pdfBytes))]))
	}
	// fpdf PDF page geometry / MediaBox must remain dot-decimal formatted (612.00 / 792.00 or integer), never comma-decimal (e.g. 612,00)
	if bytes.Contains(pdfBytes, []byte("612,00")) || bytes.Contains(pdfBytes, []byte("792,00")) {
		t.Fatal("PDF contains comma-decimal coordinate formatting instead of invariant dot-decimal")
	}
}
