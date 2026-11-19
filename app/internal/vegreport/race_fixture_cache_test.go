package vegreport

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

type vegreportCachedDBSet struct {
	sampleNoReportSU   []byte
	sampleWithReportSU []byte
	sampleKML          []byte
	externalReportSU   []byte
	family             map[string][]byte

	summaryVegSampleInt  []byte
	summaryVegSampleExt  []byte
	summaryVegExtSU      []byte
	summaryVegVLists     []byte
	summaryVegVUser      []byte
	summaryVegVPro64     []byte
	summaryLifeSampleInt []byte
	summaryLifeSampleExt []byte
	summaryLifeVLists    []byte
	summaryLifeVPro64    []byte
}

var vegreportCachedDBSetOnce = sync.OnceValues(buildVegreportCachedDBSet)

func execTempSQLiteScript(dir, name string, seed []byte, attach map[string]string, query string) ([]byte, error) {
	dbPath := filepath.Join(dir, name)
	if seed != nil {
		if err := os.WriteFile(dbPath, seed, 0600); err != nil {
			return nil, err
		}
	}
	mode := "rw"
	if seed == nil {
		mode = "rwc"
	}
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, mode)+"&_journal_mode=DELETE&_synchronous=OFF")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	for alias, path := range attach {
		if _, err := db.Exec(`ATTACH DATABASE ? AS `+vprocore.QuoteHeaderIdentifier(alias), path); err != nil {
			_ = db.Close()
			return nil, err
		}
	}
	if _, err := db.Exec(query); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("%s exec: %w", name, err)
	}
	for alias := range attach {
		if _, err := db.Exec(`DETACH DATABASE ` + vprocore.QuoteHeaderIdentifier(alias)); err != nil {
			_ = db.Close()
			return nil, err
		}
	}
	if _, err := db.Exec(`VACUUM`); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("%s vacuum: %w", name, err)
	}
	if err := db.Close(); err != nil {
		return nil, err
	}
	return os.ReadFile(dbPath)
}

func buildVegreportCachedDBSet() (*vegreportCachedDBSet, error) {
	tmpDir, err := os.MkdirTemp("", "vpro-vegreport-template-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpDir)

	sampleRaw, err := vprocore.SampleFiles.ReadFile("resources/Sample.db")
	if err != nil {
		return nil, err
	}
	family := make(map[string][]byte, len(vprocore.DatabaseFamilySeeds)+1)
	for _, name := range []string{"VPro64", "VLists", "VUser", "VMetaData", "VMessageBoard", "VPics"} {
		data, err := vprocore.DatabaseFamilyFiles.ReadFile("resources/database-family/" + name + ".db")
		if err != nil {
			return nil, err
		}
		family[name] = data
	}

	// 1. Compact Sample.db preserving all 52 Env/Admin rows and schema, retaining Veg rows for active report test plots.
	sampleNoReportSU, err := execTempSQLiteScript(tmpDir, "Sample_no_report.db", sampleRaw, nil, `
		PRAGMA foreign_keys = OFF;
		DELETE FROM Sample_Veg WHERE PlotNumber NOT IN ('108050', '108050x', '00337');
	`)
	if err != nil {
		return nil, err
	}
	sampleNoReportPath := filepath.Join(tmpDir, "Sample_no_report.db")

	sampleWithReportSU, err := execTempSQLiteScript(tmpDir, "Sample_with_report.db", sampleNoReportSU, nil, `
		CREATE TABLE Report_SU(PlotNumber TEXT,SiteUnit TEXT);
		INSERT INTO Report_SU VALUES('108050','  Unit ''quoted''  '),('missing','Orphan'),('108050x',NULL);
	`)
	if err != nil {
		return nil, err
	}

	externalReportSU, err := execTempSQLiteScript(tmpDir, "external_report.db", nil, nil, `
		CREATE TABLE Report_SU(PlotNumber TEXT,SiteUnit TEXT);
		INSERT INTO Report_SU VALUES('108050','  Unit ''quoted''  '),('missing','Orphan'),('108050x',NULL);
	`)
	if err != nil {
		return nil, err
	}

	sampleKML, err := execTempSQLiteScript(tmpDir, "Sample_kml.db", sampleNoReportSU, nil, `
		UPDATE Sample_Env SET Longitude=123.25,Latitude=54.5,Zone=NULL
		WHERE Longitude IS NOT NULL AND Latitude IS NOT NULL;
	`)
	if err != nil {
		return nil, err
	}

	// 2. Compact VLists.db retaining 100% of species/attributes/units/quality lists referenced by active plots
	// (including variant-stripped base codes and OldCode synonyms) plus unjoined witness rows for drift tests.
	vlistsCompact, err := execTempSQLiteScript(tmpDir, "VLists_compact.db", family["VLists"], map[string]string{"s": sampleNoReportPath}, `
		CREATE TEMP TABLE keep_codes AS
		SELECT DISTINCT UPPER(TRIM(Species)) AS code
		FROM s.Sample_Veg
		WHERE Species IS NOT NULL
		UNION
		SELECT DISTINCT UPPER(substr(TRIM(Species), 1, length(TRIM(Species)) - 1)) AS code
		FROM s.Sample_Veg
		WHERE Species IS NOT NULL AND length(TRIM(Species)) > 1;

		DELETE FROM USysAllSpecs
		WHERE rowid NOT IN (
			SELECT rowid FROM USysAllSpecs
			WHERE UPPER(TRIM(Code)) IN (SELECT code FROM keep_codes)
			   OR UPPER(TRIM(COALESCE(OldCode, ''))) IN (SELECT code FROM keep_codes)
			UNION
			SELECT rowid FROM (
				SELECT rowid FROM USysAllSpecs
				WHERE Codetype = 'U' AND ScientificName IS NOT NULL AND EnglishName IS NOT NULL
				  AND UPPER(TRIM(Code)) NOT IN (SELECT code FROM keep_codes)
				ORDER BY rowid LIMIT 8
			)
		);

		DELETE FROM USysSppAttributes
		WHERE rowid NOT IN (
			SELECT rowid FROM USysSppAttributes
			WHERE UPPER(TRIM(Code)) IN (SELECT code FROM keep_codes)
			UNION
			SELECT rowid FROM (
				SELECT rowid FROM USysSppAttributes
				WHERE UPPER(TRIM(Code)) NOT IN (SELECT code FROM keep_codes)
				ORDER BY rowid LIMIT 5
			)
		);

		DELETE FROM MasterSiteUnitList
		WHERE rowid NOT IN (
			SELECT rowid FROM MasterSiteUnitList
			WHERE SiteSeries IN (SELECT DISTINCT SiteUnit FROM s.Sample_SU WHERE SiteUnit IS NOT NULL)
			   OR SiteSeries IN (SELECT DISTINCT UserSiteUnit FROM s.Sample_Admin WHERE UserSiteUnit IS NOT NULL)
			UNION
			SELECT rowid FROM (
				SELECT rowid FROM MasterSiteUnitList ORDER BY rowid LIMIT 8
			)
		);

		DELETE FROM USysTableOfLists
		WHERE rowid NOT IN (
			SELECT rowid FROM USysTableOfLists
			WHERE ListName LIKE '%Quality%'
			UNION
			SELECT rowid FROM (
				SELECT rowid FROM USysTableOfLists ORDER BY rowid LIMIT 10
			)
		);

		DELETE FROM USysSiteSeriesNames
		WHERE rowid NOT IN (SELECT rowid FROM USysSiteSeriesNames ORDER BY rowid LIMIT 10);

		DROP TABLE keep_codes;
	`)
	if err != nil {
		return nil, err
	}
	family["VLists"] = vlistsCompact

	// 3. Pre-seeded summaryVegetationServiceFixture templates.
	summaryVegSampleExt, err := execTempSQLiteScript(tmpDir, "sumveg_sample_ext.db", sampleNoReportSU, nil, `
		DELETE FROM Sample_Veg;
		INSERT INTO Sample_Veg(PlotNumber,Species,Cover1) VALUES('P1','X',10),('P2','X',20),('P3','X',5),('P2','S',2);
	`)
	if err != nil {
		return nil, err
	}
	summaryVegSampleInt, err := execTempSQLiteScript(tmpDir, "sumveg_sample_int.db", summaryVegSampleExt, nil, `
		CREATE TABLE Report_SU(PlotNumber TEXT,SiteUnit TEXT);
		INSERT INTO Report_SU VALUES('P1','A'),('P1','A'),('P2','A'),('P5','A'),('P3','B'),(NULL,'A'),('P9',NULL),('P6','Orphan');
	`)
	if err != nil {
		return nil, err
	}
	summaryVegExtSU, err := execTempSQLiteScript(tmpDir, "sumveg_ext_su.db", nil, nil, `
		CREATE TABLE Report_SU(PlotNumber TEXT,SiteUnit TEXT);
		INSERT INTO Report_SU VALUES('P1','A'),('P1','A'),('P2','A'),('P5','A'),('P3','B'),(NULL,'A'),('P9',NULL),('P6','Orphan');
	`)
	if err != nil {
		return nil, err
	}
	summaryVegVLists, err := execTempSQLiteScript(tmpDir, "sumveg_vlists.db", vlistsCompact, nil, `
		DELETE FROM USysAllSpecs;
		INSERT INTO USysAllSpecs(Code,ScientificName,Lifeform,EnglishName,Codetype) VALUES('X','Alpha',1,'x','U'),('S','Excluded',2,'s','s');
	`)
	if err != nil {
		return nil, err
	}
	summaryVegVUser, err := execTempSQLiteScript(tmpDir, "sumveg_vuser.db", family["VUser"], nil, `
		DELETE FROM USysUserSpp;
	`)
	if err != nil {
		return nil, err
	}
	summaryVegVPro64, err := execTempSQLiteScript(tmpDir, "sumveg_vpro64.db", family["VPro64"], nil, `
		DELETE FROM LayerCode;
		INSERT INTO LayerCode(LayerText,Layer1234567,Layer) VALUES('1','1','A1'),('10','10',NULL);
	`)
	if err != nil {
		return nil, err
	}

	// 4. Pre-seeded summaryEnvironmentalLifeformServiceFixture templates (eliminating 48 per-call SQLite connections).
	var lifeVegInserts, lifeSpecsInserts, lifeFieldInserts strings.Builder
	for form := 1; form <= 13; form++ {
		arg := strconv.Itoa(form)
		spp := "LF" + arg
		fmt.Fprintf(&lifeVegInserts, "INSERT INTO Sample_Veg(PlotNumber,Species,Cover1) VALUES('P1','%s',1.25),('P2','%s',3.75);", spp, spp)
		fmt.Fprintf(&lifeSpecsInserts, "INSERT INTO USysAllSpecs(Code,ScientificName,Lifeform,EnglishName,Codetype) VALUES('%s','Lifeform %s',%s,'%s','U');", spp, arg, arg, spp)
		fmt.Fprintf(&lifeFieldInserts, "INSERT INTO USysShortVegSummaryFieldList VALUES(%s,'Calc','Lifeform %s',NULL,-1,'SVLifeformCover','%s');", arg, arg, arg)
	}
	lifeVegInserts.WriteString("INSERT INTO Sample_Veg(PlotNumber,Species,Cover1) VALUES('P3','LF1',0);")

	lifeEnvSQL := `
		DELETE FROM Sample_Env;
		INSERT INTO Sample_Env(PlotNumber,NutrientRegime) VALUES('P1','M'),('P2','N'),('P3',NULL);
		UPDATE Sample_Env
		SET SeepageDepth=1,RootingDepth=2,StandAge=3,Elevation=4,SlopeGradient=1.25,
		SubstrateDecWood=1.25,SubstrateBedRock=2.5,SubstrateRocks=4,
		SubstrateMineralSoil=5,SubstrateOrganicMatter=6,SubstrateWater=7,
		StrataCoverTree=8,StrataCoverShrub=9,StrataCoverHerb=10,StrataCoverMoss=11 WHERE PlotNumber='P1';
		UPDATE Sample_Env
		SET SeepageDepth=5,RootingDepth=6,StandAge=7,Elevation=8,SlopeGradient=5.75,
		SubstrateDecWood=5.75,SubstrateBedRock=2.5,SubstrateRocks=4,
		SubstrateMineralSoil=5,SubstrateOrganicMatter=6,SubstrateWater=7,
		StrataCoverTree=8,StrataCoverShrub=9,StrataCoverHerb=10,StrataCoverMoss=11 WHERE PlotNumber='P2';
		DELETE FROM Sample_Veg;
	` + lifeVegInserts.String()

	summaryLifeSampleExt, err := execTempSQLiteScript(tmpDir, "sumlife_sample_ext.db", summaryVegSampleExt, nil, lifeEnvSQL)
	if err != nil {
		return nil, err
	}
	summaryLifeSampleInt, err := execTempSQLiteScript(tmpDir, "sumlife_sample_int.db", summaryVegSampleInt, nil, lifeEnvSQL)
	if err != nil {
		return nil, err
	}
	summaryLifeVLists, err := execTempSQLiteScript(tmpDir, "sumlife_vlists.db", summaryVegVLists, nil, `
		DELETE FROM USysAllSpecs;
	`+lifeSpecsInserts.String())
	if err != nil {
		return nil, err
	}
	summaryLifeVPro64, err := execTempSQLiteScript(tmpDir, "sumlife_vpro64.db", summaryVegVPro64, nil, `
		DROP TABLE IF EXISTS USysShortVegSummaryFieldList;
	`+strings.ReplaceAll(summaryFieldListTestSchema, "VPro64.", "")+`;
		INSERT INTO USysShortVegSummaryFieldList VALUES
		(0,'Env','n Plots',NULL,-1,'SVnPlots',NULL),
		(1,'Env','Nutrient','NutrientRegime',-1,'SVSnr',NULL),
		(-1,'Env','disabled',NULL,0,'unknown',NULL),
		(NULL,'Env','Seepage',NULL,-1,'SVSeepage',NULL),
		(2,'Env','Root',NULL,-1,'SVRootingDepth',NULL),
		(3,'Env','Age',NULL,-1,'SVStandAge',NULL),
		(4,'Env','Elevation',NULL,-1,'SVElevation',NULL),
		(5,'Env','Slope',NULL,-1,'SVSlope',NULL),
		(6,'Env','DecWood',NULL,-1,'SVSubstrate','DecWood'),
		(7,'Env','BedRock',NULL,-1,'SVSubstrate','BedRock'),
		(8,'Env','Rocks',NULL,-1,'SVSubstrate','Rocks'),
		(9,'Env','MineralSoil',NULL,-1,'SVSubstrate','MineralSoil'),
		(10,'Env','OrganicMatter',NULL,-1,'SVSubstrate','OrganicMatter'),
		(11,'Env','Water',NULL,-1,'SVSubstrate','Water'),
		(12,'Env','Tree',NULL,-1,'SVStrataCover','Tree'),
		(13,'Env','Shrub',NULL,-1,'SVStrataCover','Shrub'),
		(14,'Env','Herb',NULL,-1,'SVStrataCover','Herb'),
		(15,'Env','Moss',NULL,-1,'SVStrataCover','Moss');
	`+lifeFieldInserts.String())
	if err != nil {
		return nil, err
	}

	return &vegreportCachedDBSet{
		sampleNoReportSU:     sampleNoReportSU,
		sampleWithReportSU:   sampleWithReportSU,
		sampleKML:            sampleKML,
		externalReportSU:     externalReportSU,
		family:               family,
		summaryVegSampleInt:  summaryVegSampleInt,
		summaryVegSampleExt:  summaryVegSampleExt,
		summaryVegExtSU:      summaryVegExtSU,
		summaryVegVLists:     summaryVegVLists,
		summaryVegVUser:      summaryVegVUser,
		summaryVegVPro64:     summaryVegVPro64,
		summaryLifeSampleInt: summaryLifeSampleInt,
		summaryLifeSampleExt: summaryLifeSampleExt,
		summaryLifeVLists:    summaryLifeVLists,
		summaryLifeVPro64:    summaryLifeVPro64,
	}, nil
}

func newClonedContextService(t *testing.T, sampleBytes []byte, familyOverrides map[string][]byte) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		t.Fatal(err)
	}
	data, config := vprotest.ConfigFixture(t)
	projectsDir := filepath.Join(data, "projects")
	familyDir := filepath.Join(data, "database-family")
	picturesDir := filepath.Join(data, "pictures")
	for _, dir := range []string{projectsDir, familyDir, picturesDir} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(projectsDir, "Sample.db"), sampleBytes, 0600); err != nil {
		t.Fatal(err)
	}
	for name, bytes := range tpl.family {
		if override, ok := familyOverrides[name]; ok {
			bytes = override
		}
		if err := os.WriteFile(filepath.Join(familyDir, name+".db"), bytes, 0600); err != nil {
			t.Fatal(err)
		}
	}
	preferences, err := vprocore.OpenDesktopConfig(data, config)
	if err != nil {
		t.Fatal(err)
	}
	projects, err := vprocore.NewSQLiteProjectService(data, config, preferences)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := projects.CloseSQLiteContext(); err != nil {
			t.Error(err)
		}
	})
	plots, err := vprocore.NewPlotServiceWithPreferences(projects)
	if err != nil {
		t.Fatal(err)
	}
	service, err := vprocore.NewContextService(projects, plots)
	if err != nil {
		t.Fatal(err)
	}
	state, err := projects.GetState(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return service, state
}

func vegreportReportServiceFixture(t *testing.T, external bool) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		t.Fatal(err)
	}
	sampleBytes := tpl.sampleWithReportSU
	if external {
		sampleBytes = tpl.sampleNoReportSU
	}
	service, state := newClonedContextService(t, sampleBytes, nil)
	suPath := state.ProjectPath
	if external {
		suPath = filepath.Join(t.TempDir(), "external.db")
		if err := os.WriteFile(suPath, tpl.externalReportSU, 0600); err != nil {
			t.Fatal(err)
		}
	}
	selection := vprotest.ContextSelection(state)
	selection.SU, selection.SUPath = "Report", suPath
	next, err := service.SwitchContext(state.ContextID, selection)
	if err != nil {
		t.Fatal(err)
	}
	return service, next
}

func vegreportPrepareKMLContextFixture(t *testing.T) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		t.Fatal(err)
	}
	return newClonedContextService(t, tpl.sampleKML, nil)
}

func vegreportSummaryVegetationContextFixture(t *testing.T, external bool) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		t.Fatal(err)
	}
	sampleBytes := tpl.summaryVegSampleInt
	if external {
		sampleBytes = tpl.summaryVegSampleExt
	}
	service, state := newClonedContextService(t, sampleBytes, map[string][]byte{
		"VLists": tpl.summaryVegVLists,
		"VUser":  tpl.summaryVegVUser,
		"VPro64": tpl.summaryVegVPro64,
	})
	suPath := state.ProjectPath
	if external {
		suPath = filepath.Join(t.TempDir(), "external.db")
		if err := os.WriteFile(suPath, tpl.summaryVegExtSU, 0600); err != nil {
			t.Fatal(err)
		}
	}
	selection := vprotest.ContextSelection(state)
	selection.SU, selection.SUPath = "Report", suPath
	next, err := service.SwitchContext(state.ContextID, selection)
	if err != nil {
		t.Fatal(err)
	}
	return service, next
}

func vegreportSummaryLifeformContextFixture(t *testing.T, external bool) (*vprocore.ContextService, vprocore.ProjectState) {
	t.Helper()
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		t.Fatal(err)
	}
	sampleBytes := tpl.summaryLifeSampleInt
	if external {
		sampleBytes = tpl.summaryLifeSampleExt
	}
	service, state := newClonedContextService(t, sampleBytes, map[string][]byte{
		"VLists": tpl.summaryLifeVLists,
		"VUser":  tpl.summaryVegVUser,
		"VPro64": tpl.summaryLifeVPro64,
	})
	suPath := state.ProjectPath
	if external {
		suPath = filepath.Join(t.TempDir(), "external.db")
		if err := os.WriteFile(suPath, tpl.summaryVegExtSU, 0600); err != nil {
			t.Fatal(err)
		}
	}
	selection := vprotest.ContextSelection(state)
	selection.SU, selection.SUPath = "Report", suPath
	next, err := service.SwitchContext(state.ContextID, selection)
	if err != nil {
		t.Fatal(err)
	}
	return service, next
}

var cachedVegetationWorkbookPreviewJSON = sync.OnceValues(func() ([]byte, error) {
	tpl, err := vegreportCachedDBSetOnce()
	if err != nil {
		return nil, err
	}
	tmpRoot, err := os.MkdirTemp("", "vpro-vegreport-preview-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpRoot)

	data := filepath.Join(tmpRoot, "data")
	config := filepath.Join(tmpRoot, "config")
	for _, dir := range []string{
		config,
		filepath.Join(data, "projects"),
		filepath.Join(data, "database-family"),
		filepath.Join(data, "pictures"),
	} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return nil, err
		}
	}
	if err := os.WriteFile(filepath.Join(data, "projects", "Sample.db"), tpl.sampleWithReportSU, 0600); err != nil {
		return nil, err
	}
	for name, bytes := range tpl.family {
		if err := os.WriteFile(filepath.Join(data, "database-family", name+".db"), bytes, 0600); err != nil {
			return nil, err
		}
	}
	preferences, err := vprocore.OpenDesktopConfig(data, config)
	if err != nil {
		return nil, err
	}
	projects, err := vprocore.NewSQLiteProjectService(data, config, preferences)
	if err != nil {
		return nil, err
	}
	defer func() { _ = projects.CloseSQLiteContext() }()
	plots, err := vprocore.NewPlotServiceWithPreferences(projects)
	if err != nil {
		return nil, err
	}
	service, err := vprocore.NewContextService(projects, plots)
	if err != nil {
		return nil, err
	}
	state, err := projects.GetState(context.Background())
	if err != nil {
		return nil, err
	}
	selection := vprotest.ContextSelection(state)
	selection.SU, selection.SUPath = "Report", state.ProjectPath
	next, err := service.SwitchContext(state.ContextID, selection)
	if err != nil {
		return nil, err
	}
	preview, err := PreviewLongVegetation(service, context.Background(), next.ContextID)
	if err != nil {
		return nil, errors.Join(err, projects.CloseSQLiteContext())
	}
	raw, err := json.Marshal(preview)
	if err != nil {
		return nil, err
	}
	return raw, nil
})
