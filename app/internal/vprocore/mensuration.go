package vprocore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

const (
	// MensurationTreePlotSuffix is the VP08 table suffix for plot-level mensuration headers.
	MensurationTreePlotSuffix = "TreePlot"
	// MensurationTreesSuffix is the VP08 table suffix for tree-level mensuration measurements.
	MensurationTreesSuffix = "Trees"
)

// ErrMensurationTablesNotFound is returned when a mensuration mutation is attempted on a project
// that has not yet initialized its optional <Project>_TreePlot / <Project>_Trees tables.
var ErrMensurationTablesNotFound = errors.New("mensuration tables (_TreePlot/_Trees) do not exist in this project; initialize them first")

// TreePlotColumns lists the 26 canonical columns of <Project>_TreePlot in Access schema order.
var TreePlotColumns = []string{
	"PlotNumber", "SubPlot", "MeasurementID", "MensurationID",
	"Zone", "SubZone", "FIZ", "TreeSurveyor", "Date",
	"CruisePlot", "CWDPlot", "WildlifePlot", "InformalPlot", "SiteIndexPlot",
	"BAF", "DBHLimit", "StandAge", "PlotSize",
	"SeralStage", "FSRegionDistrict", "Location", "BECSiteUnit",
	"StandAgeVPro", "SiteSeries", "Comment", "DataSource",
}

// TreesColumns lists the 43 canonical columns of <Project>_Trees in Access schema order.
var TreesColumns = []string{
	"PlotNumber", "SubPlot", "MeasurementID", "TreeNum", "TreeSpp",
	"DBH", "DBHClass", "TotalHtCalc", "HeightClass",
	"CountAge", "CountHT", "TotalAge", "AgeNote",
	"TreeHealth", "TreeOrigin",
	"Conks", "BlindConks", "Scars", "ForkOrCrook", "FrostCrack",
	"Mistletoe", "RottenBranch", "DeadOrBrokenTop",
	"DamageType", "DamageSeverity", "CrownClass", "Ht2LiveCrown",
	"Appearance", "CrownCondition", "BarkRetention", "WoodCondition",
	"LichenLoading", "MossLoading", "WildLifeUse", "TreeNotes", "LiveDead",
	"CuVolume", "SPH", "BasalArea",
	"SiteIndexID", "SiteIndex", "SiteIndex24", "SI50",
}

// TreePlotTextMaximum holds Access UTF-16 character width limits for <Project>_TreePlot text columns.
// Zero indicates an unbounded Memo/TEXT column.
var TreePlotTextMaximum = map[string]int{
	"PlotNumber":       7,
	"SubPlot":          30,
	"MensurationID":    255,
	"Zone":             10,
	"SubZone":          15,
	"FIZ":              2,
	"TreeSurveyor":     30,
	"Date":             0,
	"SeralStage":       255,
	"FSRegionDistrict": 7,
	"Location":         255,
	"BECSiteUnit":      100,
	"SiteSeries":       5,
	"Comment":          0,
	"DataSource":       255,
}

// TreesTextMaximum holds Access UTF-16 character width limits for <Project>_Trees text columns.
// Zero indicates an unbounded Memo/TEXT column.
var TreesTextMaximum = map[string]int{
	"PlotNumber":     7,
	"SubPlot":        30,
	"TreeSpp":        3,
	"AgeNote":        255,
	"TreeOrigin":     1,
	"DamageType":     3,
	"DamageSeverity": 1,
	"CrownClass":     1,
	"WildLifeUse":    17,
	"TreeNotes":      0,
	"LiveDead":       255,
}

// TreePlotBooleanColumns identifies the 5 Access BOOLEAN (-1/0) columns on <Project>_TreePlot.
var TreePlotBooleanColumns = map[string]bool{
	"CruisePlot":    true,
	"CWDPlot":       true,
	"WildlifePlot":  true,
	"InformalPlot":  true,
	"SiteIndexPlot": true,
}

// TreesByteColumns identifies the 15 Access Byte (0..255) columns on <Project>_Trees.
var TreesByteColumns = map[string]bool{
	"TreeHealth":      true,
	"Conks":           true,
	"BlindConks":      true,
	"Scars":           true,
	"ForkOrCrook":     true,
	"FrostCrack":      true,
	"Mistletoe":       true,
	"RottenBranch":    true,
	"DeadOrBrokenTop": true,
	"Appearance":      true,
	"CrownCondition":  true,
	"BarkRetention":   true,
	"WoodCondition":   true,
	"LichenLoading":   true,
	"MossLoading":     true,
}

// TreesDoubleColumns identifies the 5 Double-precision columns on <Project>_Trees.
var TreesDoubleColumns = map[string]bool{
	"CuVolume":    true,
	"SPH":         true,
	"BasalArea":   true,
	"SiteIndex24": true,
	"SI50":        true,
}

// TreePlotRecord represents one row in <Project>_TreePlot (26 columns).
type TreePlotRecord struct {
	PlotNumber       string   `json:"plotNumber"`
	SubPlot          string   `json:"subPlot"`
	MeasurementID    int      `json:"measurementId"`
	MensurationID    *string  `json:"mensurationId"`
	Zone             *string  `json:"zone"`
	SubZone          *string  `json:"subZone"`
	FIZ              *string  `json:"fiz"`
	TreeSurveyor     *string  `json:"treeSurveyor"`
	Date             *string  `json:"date"`
	CruisePlot       bool     `json:"cruisePlot"`
	CWDPlot          bool     `json:"cwdPlot"`
	WildlifePlot     bool     `json:"wildlifePlot"`
	InformalPlot     bool     `json:"informalPlot"`
	SiteIndexPlot    bool     `json:"siteIndexPlot"`
	BAF              *float64 `json:"baf"`
	DBHLimit         *float64 `json:"dbhLimit"`
	StandAge         *int     `json:"standAge"`
	PlotSize         *float64 `json:"plotSize"`
	SeralStage       *string  `json:"seralStage"`
	FSRegionDistrict *string  `json:"fsRegionDistrict"`
	Location         *string  `json:"location"`
	BECSiteUnit      *string  `json:"becSiteUnit"`
	StandAgeVPro     *int     `json:"standAgeVPro"`
	SiteSeries       *string  `json:"siteSeries"`
	Comment          *string  `json:"comment"`
	DataSource       *string  `json:"dataSource"`
}

func (r *TreePlotRecord) UnmarshalJSON(data []byte) error {
	type plain TreePlotRecord
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// TreeRowRecord represents one row in <Project>_Trees (43 columns plus SQLite rowid).
type TreeRowRecord struct {
	RowID           int64    `json:"rowId,omitempty"`
	PlotNumber      string   `json:"plotNumber"`
	SubPlot         *string  `json:"subPlot"`
	MeasurementID   *int     `json:"measurementId"`
	TreeNum         *int     `json:"treeNum"`
	TreeSpp         *string  `json:"treeSpp"`
	DBH             *float64 `json:"dbh"`
	DBHClass        *float64 `json:"dbhClass"`
	TotalHtCalc     *float64 `json:"totalHtCalc"`
	HeightClass     *float64 `json:"heightClass"`
	CountAge        *int     `json:"countAge"`
	CountHT         *float64 `json:"countHt"`
	TotalAge        *int     `json:"totalAge"`
	AgeNote         *string  `json:"ageNote"`
	TreeHealth      *int     `json:"treeHealth"`
	TreeOrigin      *string  `json:"treeOrigin"`
	Conks           *int     `json:"conks"`
	BlindConks      *int     `json:"blindConks"`
	Scars           *int     `json:"scars"`
	ForkOrCrook     *int     `json:"forkOrCrook"`
	FrostCrack      *int     `json:"frostCrack"`
	Mistletoe       *int     `json:"mistletoe"`
	RottenBranch    *int     `json:"rottenBranch"`
	DeadOrBrokenTop *int     `json:"deadOrBrokenTop"`
	DamageType      *string  `json:"damageType"`
	DamageSeverity  *string  `json:"damageSeverity"`
	CrownClass      *string  `json:"crownClass"`
	Ht2LiveCrown    *float64 `json:"ht2LiveCrown"`
	Appearance      *int     `json:"appearance"`
	CrownCondition  *int     `json:"crownCondition"`
	BarkRetention   *int     `json:"barkRetention"`
	WoodCondition   *int     `json:"woodCondition"`
	LichenLoading   *int     `json:"lichenLoading"`
	MossLoading     *int     `json:"mossLoading"`
	WildLifeUse     *string  `json:"wildLifeUse"`
	TreeNotes       *string  `json:"treeNotes"`
	LiveDead        *string  `json:"liveDead"`
	CuVolume        *float64 `json:"cuVolume"`
	SPH             *float64 `json:"sph"`
	BasalArea       *float64 `json:"basalArea"`
	SiteIndexID     *int64   `json:"siteIndexId"`
	SiteIndex       *float64 `json:"siteIndex"`
	SiteIndex24     *float64 `json:"siteIndex24"`
	SI50            *float64 `json:"si50"`
}

func (r *TreeRowRecord) UnmarshalJSON(data []byte) error {
	type plain TreeRowRecord
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// PlotMensurationData is the complete FS882 4th-card mensuration payload for one plot.
type PlotMensurationData struct {
	PlotNumber  string           `json:"plotNumber"`
	HasTables   bool             `json:"hasTables"`
	HasTreePlot bool             `json:"hasTreePlot"`
	HasTrees    bool             `json:"hasTrees"`
	TreePlots   []TreePlotRecord `json:"treePlots"`
	Trees       []TreeRowRecord  `json:"trees"`
	ReadOnly    bool             `json:"readOnly"`
}

// EnsureMensurationTablesResult reports the outcome of initializing optional mensuration tables.
type EnsureMensurationTablesResult struct {
	Project         string `json:"project"`
	TreePlotTable   string `json:"treePlotTable"`
	TreesTable      string `json:"treesTable"`
	CreatedTreePlot bool   `json:"createdTreePlot"`
	CreatedTrees    bool   `json:"createdTrees"`
	HasTables       bool   `json:"hasTables"`
}

// CreateTreePlotTableDDL returns the canonical CREATE TABLE IF NOT EXISTS DDL for <project>_TreePlot.
func CreateTreePlotTableDDL(project string) string {
	tbl := QuoteHeaderIdentifier(project + "_" + MensurationTreePlotSuffix)
	return `CREATE TABLE IF NOT EXISTS ` + tbl + ` (
	"PlotNumber" TEXT NOT NULL,
	"SubPlot" TEXT NOT NULL,
	"MeasurementID" INTEGER NOT NULL,
	"MensurationID" TEXT,
	"Zone" TEXT,
	"SubZone" TEXT,
	"FIZ" TEXT,
	"TreeSurveyor" TEXT,
	"Date" TEXT,
	"CruisePlot" INTEGER NOT NULL DEFAULT 0,
	"CWDPlot" INTEGER NOT NULL DEFAULT 0,
	"WildlifePlot" INTEGER NOT NULL DEFAULT 0,
	"InformalPlot" INTEGER NOT NULL DEFAULT 0,
	"SiteIndexPlot" INTEGER NOT NULL DEFAULT 0,
	"BAF" REAL,
	"DBHLimit" REAL,
	"StandAge" INTEGER,
	"PlotSize" REAL,
	"SeralStage" TEXT,
	"FSRegionDistrict" TEXT,
	"Location" TEXT,
	"BECSiteUnit" TEXT,
	"StandAgeVPro" INTEGER,
	"SiteSeries" TEXT,
	"Comment" TEXT,
	"DataSource" TEXT,
	PRIMARY KEY ("PlotNumber", "SubPlot", "MeasurementID")
)`
}

// CreateTreePlotIndexesDDL returns the canonical index DDL statements for <project>_TreePlot.
func CreateTreePlotIndexesDDL(project string) []string {
	tblName := project + "_" + MensurationTreePlotSuffix
	tbl := QuoteHeaderIdentifier(tblName)
	return []string{
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_ID_idx") + ` ON ` + tbl + ` ("MensurationID")`,
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_MeasurementID_idx") + ` ON ` + tbl + ` ("MeasurementID")`,
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_PlotNumber_idx") + ` ON ` + tbl + ` ("PlotNumber")`,
	}
}

// CreateTreesTableDDL returns the canonical CREATE TABLE IF NOT EXISTS DDL for <project>_Trees.
// Matches Access SIBEC schema without a UNIQUE key on (PlotNumber, SubPlot, MeasurementID, TreeNum)
// so legacy records with nullable SubPlot/MeasurementID or duplicate TreeNum import losslessly.
func CreateTreesTableDDL(project string) string {
	tbl := QuoteHeaderIdentifier(project + "_" + MensurationTreesSuffix)
	return `CREATE TABLE IF NOT EXISTS ` + tbl + ` (
	"PlotNumber" TEXT NOT NULL,
	"SubPlot" TEXT,
	"MeasurementID" INTEGER,
	"TreeNum" INTEGER,
	"TreeSpp" TEXT,
	"DBH" REAL,
	"DBHClass" REAL,
	"TotalHtCalc" REAL,
	"HeightClass" REAL,
	"CountAge" INTEGER,
	"CountHT" REAL,
	"TotalAge" INTEGER,
	"AgeNote" TEXT,
	"TreeHealth" INTEGER,
	"TreeOrigin" TEXT,
	"Conks" INTEGER,
	"BlindConks" INTEGER,
	"Scars" INTEGER,
	"ForkOrCrook" INTEGER,
	"FrostCrack" INTEGER,
	"Mistletoe" INTEGER,
	"RottenBranch" INTEGER,
	"DeadOrBrokenTop" INTEGER,
	"DamageType" TEXT,
	"DamageSeverity" TEXT,
	"CrownClass" TEXT,
	"Ht2LiveCrown" REAL,
	"Appearance" INTEGER,
	"CrownCondition" INTEGER,
	"BarkRetention" INTEGER,
	"WoodCondition" INTEGER,
	"LichenLoading" INTEGER,
	"MossLoading" INTEGER,
	"WildLifeUse" TEXT,
	"TreeNotes" TEXT,
	"LiveDead" TEXT,
	"CuVolume" REAL,
	"SPH" REAL,
	"BasalArea" REAL,
	"SiteIndexID" INTEGER,
	"SiteIndex" REAL,
	"SiteIndex24" REAL,
	"SI50" REAL
)`
}

// CreateTreesIndexesDDL returns the canonical index DDL statements for <project>_Trees.
func CreateTreesIndexesDDL(project string) []string {
	tblName := project + "_" + MensurationTreesSuffix
	tbl := QuoteHeaderIdentifier(tblName)
	return []string{
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_MeasurementID_idx") + ` ON ` + tbl + ` ("MeasurementID")`,
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_PlotNumber_idx") + ` ON ` + tbl + ` ("PlotNumber")`,
		`CREATE INDEX IF NOT EXISTS ` + QuoteHeaderIdentifier(tblName+"_TreeNum_idx") + ` ON ` + tbl + ` ("TreeNum")`,
	}
}

// HasMensurationTables checks whether <project>_TreePlot and <project>_Trees exist in schema.
func HasMensurationTables(ctx context.Context, q AuditSQLRowQueryer, schema, project string) (hasTreePlot, hasTrees bool, err error) {
	if strings.TrimSpace(project) == "" {
		return false, false, errors.New("project name is required")
	}
	master := "sqlite_master"
	if strings.TrimSpace(schema) != "" {
		master = QuoteHeaderIdentifier(schema) + ".sqlite_master"
	}
	if err := q.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM `+master+` WHERE type='table' AND name COLLATE BINARY=?)`,
		project+"_"+MensurationTreePlotSuffix,
	).Scan(&hasTreePlot); err != nil {
		return false, false, err
	}
	if err := q.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM `+master+` WHERE type='table' AND name COLLATE BINARY=?)`,
		project+"_"+MensurationTreesSuffix,
	).Scan(&hasTrees); err != nil {
		return false, false, err
	}
	return hasTreePlot, hasTrees, nil
}

// EnsureMensurationTablesTx idempotently creates <project>_TreePlot and <project>_Trees
// (with their canonical indexes and _table_metadata entries) inside tx.
func EnsureMensurationTablesTx(ctx context.Context, tx *sql.Tx, project string) (createdTreePlot, createdTrees bool, err error) {
	if !ProjectNamePattern.MatchString(project) {
		return false, false, fmt.Errorf("invalid project name %q", project)
	}
	hasTP, hasT, err := HasMensurationTables(ctx, tx, "main", project)
	if err != nil {
		return false, false, err
	}
	if !hasTP {
		if _, err := tx.ExecContext(ctx, CreateTreePlotTableDDL(project)); err != nil {
			return false, false, fmt.Errorf("create %s_TreePlot: %w", project, err)
		}
		for _, idxSQL := range CreateTreePlotIndexesDDL(project) {
			if _, err := tx.ExecContext(ctx, idxSQL); err != nil {
				return false, false, fmt.Errorf("create index on %s_TreePlot: %w", project, err)
			}
		}
		createdTreePlot = true
	}
	if !hasT {
		if _, err := tx.ExecContext(ctx, CreateTreesTableDDL(project)); err != nil {
			return false, false, fmt.Errorf("create %s_Trees: %w", project, err)
		}
		for _, idxSQL := range CreateTreesIndexesDDL(project) {
			if _, err := tx.ExecContext(ctx, idxSQL); err != nil {
				return false, false, fmt.Errorf("create index on %s_Trees: %w", project, err)
			}
		}
		createdTrees = true
	}
	if createdTreePlot || createdTrees {
		var hasMeta bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM main.sqlite_master WHERE type='table' AND name='_table_metadata')`).Scan(&hasMeta); err != nil {
			return createdTreePlot, createdTrees, err
		}
		if hasMeta {
			for _, tbl := range []struct {
				created bool
				name    string
			}{
				{createdTreePlot, project + "_" + MensurationTreePlotSuffix},
				{createdTrees, project + "_" + MensurationTreesSuffix},
			} {
				if !tbl.created {
					continue
				}
				var exists bool
				if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM main."_table_metadata" WHERE table_name=?)`, tbl.name).Scan(&exists); err != nil {
					return createdTreePlot, createdTrees, err
				}
				if !exists {
					if _, err := tx.ExecContext(ctx, `INSERT INTO main."_table_metadata" ("table_name","description") VALUES (?, 'VP08')`, tbl.name); err != nil {
						return createdTreePlot, createdTrees, err
					}
				}
			}
		}
	}
	return createdTreePlot, createdTrees, nil
}

// ensureOptionalMensurationViewsLocked creates optional USysTreePlot and USysTrees temp views
// on the coordinator connection whenever the corresponding physical tables exist in "project".
// Must be called during NewSQLiteContext setup or while c.mu is held.
func (c *SqliteContext) ensureOptionalMensurationViewsLocked(ctx context.Context) error {
	if c == nil || c.conn == nil {
		return nil
	}
	hasTP, hasT, err := HasMensurationTables(ctx, c.conn, "project", c.Selection.Project)
	if err != nil {
		return err
	}
	projectRel := func(suffix string) string {
		return QuoteHeaderIdentifier("project") + "." + QuoteHeaderIdentifier(c.Selection.Project+"_"+suffix)
	}
	ensureView := func(viewName, suffix string) error {
		var viewExists bool
		if err := c.conn.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM sqlite_temp_master WHERE type='view' AND name=?)`,
			viewName,
		).Scan(&viewExists); err != nil {
			return err
		}
		if viewExists {
			return nil
		}
		return c.createView(ctx, viewName, "SELECT DISTINCT * FROM "+projectRel(suffix))
	}
	if hasTP {
		if err := ensureView("USysTreePlot", MensurationTreePlotSuffix); err != nil {
			return err
		}
	}
	if hasT {
		if err := ensureView("USysTrees", MensurationTreesSuffix); err != nil {
			return err
		}
	}
	return nil
}

// EnsureMensurationViews refreshes optional USysTreePlot and USysTrees temp views on the coordinator
// after mensuration tables are dynamically created on an open context.
func (c *SqliteContext) EnsureMensurationViews(ctx context.Context) error {
	return c.WithLease(ctx, func() error {
		return c.ensureOptionalMensurationViewsLocked(ctx)
	})
}

func validateMensurationPlotNumber(plot string) error {
	if plot == "" || strings.TrimSpace(plot) == "" {
		return errors.New("PlotNumber is required")
	}
	if plot != strings.TrimSpace(plot) {
		return errors.New("PlotNumber must not have leading or trailing whitespace")
	}
	if !utf8.ValidString(plot) || strings.ContainsRune(plot, 0) {
		return errors.New("PlotNumber requires valid UTF-8 text without NUL")
	}
	if sqlutil.UTF16Len(plot) > 7 {
		return sqlutil.FormatMaxLengthError("PlotNumber", plot, 7)
	}
	return nil
}

func validateMensurationTextPtr(field string, val *string, maxUTF16 int) error {
	if val == nil {
		return nil
	}
	s := *val
	if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
		return fmt.Errorf("%s requires valid UTF-8 text without NUL", field)
	}
	if maxUTF16 > 0 && sqlutil.UTF16Len(s) > maxUTF16 {
		return sqlutil.FormatMaxLengthError(field, s, maxUTF16)
	}
	return nil
}

func validateMensurationSinglePtr(field string, val *float64) error {
	if val == nil {
		return nil
	}
	v := *val
	if math.IsNaN(v) || math.IsInf(v, 0) || math.Abs(v) > math.MaxFloat32 {
		return fmt.Errorf("%s must be a finite single-precision number", field)
	}
	if v == 0 {
		*val = 0
	}
	return nil
}

func validateMensurationDoublePtr(field string, val *float64) error {
	if val == nil {
		return nil
	}
	v := *val
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return fmt.Errorf("%s must be a finite number", field)
	}
	if v == 0 {
		*val = 0
	}
	return nil
}

func validateMensurationInt32Ptr(field string, val *int) error {
	if val == nil {
		return nil
	}
	if *val < math.MinInt32 || *val > math.MaxInt32 {
		return fmt.Errorf("%s is outside signed 32-bit integer range", field)
	}
	return nil
}

func validateMensurationBytePtr(field string, val *int) error {
	if val == nil {
		return nil
	}
	if *val < 0 || *val > 255 {
		return fmt.Errorf("%s must be between 0 and 255 (got %d)", field, *val)
	}
	return nil
}

// ValidateTreePlotRecord validates all UTF-16 bounds, required keys, and numeric ranges on TreePlotRecord.
func ValidateTreePlotRecord(rec *TreePlotRecord) error {
	if rec == nil {
		return errors.New("TreePlot record is required")
	}
	if err := validateMensurationPlotNumber(rec.PlotNumber); err != nil {
		return err
	}
	if strings.TrimSpace(rec.SubPlot) == "" {
		return errors.New("TreePlot.SubPlot is required")
	}
	if !utf8.ValidString(rec.SubPlot) || strings.ContainsRune(rec.SubPlot, 0) {
		return errors.New("TreePlot.SubPlot requires valid UTF-8 text without NUL")
	}
	if sqlutil.UTF16Len(rec.SubPlot) > TreePlotTextMaximum["SubPlot"] {
		return sqlutil.FormatMaxLengthError("TreePlot.SubPlot", rec.SubPlot, TreePlotTextMaximum["SubPlot"])
	}
	if rec.MeasurementID < math.MinInt32 || rec.MeasurementID > math.MaxInt32 {
		return errors.New("TreePlot.MeasurementID is outside signed 32-bit integer range")
	}
	textChecks := []struct {
		name string
		val  *string
	}{
		{"MensurationID", rec.MensurationID},
		{"Zone", rec.Zone},
		{"SubZone", rec.SubZone},
		{"FIZ", rec.FIZ},
		{"TreeSurveyor", rec.TreeSurveyor},
		{"Date", rec.Date},
		{"SeralStage", rec.SeralStage},
		{"FSRegionDistrict", rec.FSRegionDistrict},
		{"Location", rec.Location},
		{"BECSiteUnit", rec.BECSiteUnit},
		{"SiteSeries", rec.SiteSeries},
		{"Comment", rec.Comment},
		{"DataSource", rec.DataSource},
	}
	for _, tc := range textChecks {
		if err := validateMensurationTextPtr("TreePlot."+tc.name, tc.val, TreePlotTextMaximum[tc.name]); err != nil {
			return err
		}
	}
	for _, fc := range []struct {
		name string
		val  *float64
	}{
		{"BAF", rec.BAF},
		{"DBHLimit", rec.DBHLimit},
		{"PlotSize", rec.PlotSize},
	} {
		if err := validateMensurationSinglePtr("TreePlot."+fc.name, fc.val); err != nil {
			return err
		}
	}
	for _, ic := range []struct {
		name string
		val  *int
	}{
		{"StandAge", rec.StandAge},
		{"StandAgeVPro", rec.StandAgeVPro},
	} {
		if err := validateMensurationInt32Ptr("TreePlot."+ic.name, ic.val); err != nil {
			return err
		}
	}
	return nil
}

// ValidateTreeRowRecord validates all UTF-16 bounds, required keys, and numeric ranges on TreeRowRecord.
func ValidateTreeRowRecord(rec *TreeRowRecord) error {
	if rec == nil {
		return errors.New("Trees record is required")
	}
	if err := validateMensurationPlotNumber(rec.PlotNumber); err != nil {
		return err
	}
	textChecks := []struct {
		name string
		val  *string
	}{
		{"SubPlot", rec.SubPlot},
		{"TreeSpp", rec.TreeSpp},
		{"AgeNote", rec.AgeNote},
		{"TreeOrigin", rec.TreeOrigin},
		{"DamageType", rec.DamageType},
		{"DamageSeverity", rec.DamageSeverity},
		{"CrownClass", rec.CrownClass},
		{"WildLifeUse", rec.WildLifeUse},
		{"TreeNotes", rec.TreeNotes},
		{"LiveDead", rec.LiveDead},
	}
	for _, tc := range textChecks {
		if err := validateMensurationTextPtr("Trees."+tc.name, tc.val, TreesTextMaximum[tc.name]); err != nil {
			return err
		}
	}
	for _, ic := range []struct {
		name string
		val  *int
	}{
		{"MeasurementID", rec.MeasurementID},
		{"TreeNum", rec.TreeNum},
		{"CountAge", rec.CountAge},
		{"TotalAge", rec.TotalAge},
	} {
		if err := validateMensurationInt32Ptr("Trees."+ic.name, ic.val); err != nil {
			return err
		}
	}
	if rec.SiteIndexID != nil && (*rec.SiteIndexID < math.MinInt32 || *rec.SiteIndexID > math.MaxInt32) {
		return errors.New("Trees.SiteIndexID is outside signed 32-bit integer range")
	}
	for _, bc := range []struct {
		name string
		val  *int
	}{
		{"TreeHealth", rec.TreeHealth},
		{"Conks", rec.Conks},
		{"BlindConks", rec.BlindConks},
		{"Scars", rec.Scars},
		{"ForkOrCrook", rec.ForkOrCrook},
		{"FrostCrack", rec.FrostCrack},
		{"Mistletoe", rec.Mistletoe},
		{"RottenBranch", rec.RottenBranch},
		{"DeadOrBrokenTop", rec.DeadOrBrokenTop},
		{"Appearance", rec.Appearance},
		{"CrownCondition", rec.CrownCondition},
		{"BarkRetention", rec.BarkRetention},
		{"WoodCondition", rec.WoodCondition},
		{"LichenLoading", rec.LichenLoading},
		{"MossLoading", rec.MossLoading},
	} {
		if err := validateMensurationBytePtr("Trees."+bc.name, bc.val); err != nil {
			return err
		}
	}
	for _, sc := range []struct {
		name string
		val  *float64
	}{
		{"DBH", rec.DBH},
		{"DBHClass", rec.DBHClass},
		{"TotalHtCalc", rec.TotalHtCalc},
		{"HeightClass", rec.HeightClass},
		{"CountHT", rec.CountHT},
		{"Ht2LiveCrown", rec.Ht2LiveCrown},
		{"SiteIndex", rec.SiteIndex},
	} {
		if err := validateMensurationSinglePtr("Trees."+sc.name, sc.val); err != nil {
			return err
		}
	}
	for _, dc := range []struct {
		name string
		val  *float64
	}{
		{"CuVolume", rec.CuVolume},
		{"SPH", rec.SPH},
		{"BasalArea", rec.BasalArea},
		{"SiteIndex24", rec.SiteIndex24},
		{"SI50", rec.SI50},
	} {
		if err := validateMensurationDoublePtr("Trees."+dc.name, dc.val); err != nil {
			return err
		}
	}
	return nil
}

func accessBoolToInt64(b bool) int64 {
	if b {
		return -1
	}
	return 0
}

func scanNullableStringPtr(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	s := ns.String
	return &s
}

func scanNullableIntPtr(ni sql.NullInt64) *int {
	if !ni.Valid {
		return nil
	}
	v := int(ni.Int64)
	return &v
}

func scanNullableInt64Ptr(ni sql.NullInt64) *int64 {
	if !ni.Valid {
		return nil
	}
	v := ni.Int64
	return &v
}

func scanNullableFloat64Ptr(nf sql.NullFloat64) *float64 {
	if !nf.Valid {
		return nil
	}
	v := nf.Float64
	return &v
}

func buildMensurationSelectList(ctx context.Context, tx *sql.Tx, schema, tableName string, expected []string) ([]string, error) {
	cols, err := ReadSQLiteStorageColumns(ctx, tx, schema, tableName)
	if err != nil {
		return nil, err
	}
	actualByLower := make(map[string]string, len(cols))
	for _, c := range cols {
		actualByLower[strings.ToLower(c.Name)] = c.Name
	}
	exprs := make([]string, len(expected))
	for i, col := range expected {
		if actual, ok := actualByLower[strings.ToLower(col)]; ok {
			exprs[i] = QuoteHeaderIdentifier(actual)
		} else {
			exprs[i] = "NULL"
		}
	}
	return exprs, nil
}

func scanTreePlotRow(scanner interface{ Scan(dest ...any) error }) (TreePlotRecord, error) {
	var (
		rec              TreePlotRecord
		mensID           sql.NullString
		zone             sql.NullString
		subZone          sql.NullString
		fiz              sql.NullString
		surveyor         sql.NullString
		date             sql.NullString
		cruisePlot       sql.NullInt64
		cwdPlot          sql.NullInt64
		wildlifePlot     sql.NullInt64
		informalPlot     sql.NullInt64
		siteIndexPlot    sql.NullInt64
		baf              sql.NullFloat64
		dbhLimit         sql.NullFloat64
		standAge         sql.NullInt64
		plotSize         sql.NullFloat64
		seralStage       sql.NullString
		fsRegionDistrict sql.NullString
		location         sql.NullString
		becSiteUnit      sql.NullString
		standAgeVPro     sql.NullInt64
		siteSeries       sql.NullString
		comment          sql.NullString
		dataSource       sql.NullString
	)
	if err := scanner.Scan(
		&rec.PlotNumber, &rec.SubPlot, &rec.MeasurementID, &mensID,
		&zone, &subZone, &fiz, &surveyor, &date,
		&cruisePlot, &cwdPlot, &wildlifePlot, &informalPlot, &siteIndexPlot,
		&baf, &dbhLimit, &standAge, &plotSize,
		&seralStage, &fsRegionDistrict, &location, &becSiteUnit,
		&standAgeVPro, &siteSeries, &comment, &dataSource,
	); err != nil {
		return TreePlotRecord{}, err
	}
	rec.MensurationID = scanNullableStringPtr(mensID)
	rec.Zone = scanNullableStringPtr(zone)
	rec.SubZone = scanNullableStringPtr(subZone)
	rec.FIZ = scanNullableStringPtr(fiz)
	rec.TreeSurveyor = scanNullableStringPtr(surveyor)
	rec.Date = scanNullableStringPtr(date)
	rec.CruisePlot = cruisePlot.Valid && cruisePlot.Int64 != 0
	rec.CWDPlot = cwdPlot.Valid && cwdPlot.Int64 != 0
	rec.WildlifePlot = wildlifePlot.Valid && wildlifePlot.Int64 != 0
	rec.InformalPlot = informalPlot.Valid && informalPlot.Int64 != 0
	rec.SiteIndexPlot = siteIndexPlot.Valid && siteIndexPlot.Int64 != 0
	rec.BAF = scanNullableFloat64Ptr(baf)
	rec.DBHLimit = scanNullableFloat64Ptr(dbhLimit)
	rec.StandAge = scanNullableIntPtr(standAge)
	rec.PlotSize = scanNullableFloat64Ptr(plotSize)
	rec.SeralStage = scanNullableStringPtr(seralStage)
	rec.FSRegionDistrict = scanNullableStringPtr(fsRegionDistrict)
	rec.Location = scanNullableStringPtr(location)
	rec.BECSiteUnit = scanNullableStringPtr(becSiteUnit)
	rec.StandAgeVPro = scanNullableIntPtr(standAgeVPro)
	rec.SiteSeries = scanNullableStringPtr(siteSeries)
	rec.Comment = scanNullableStringPtr(comment)
	rec.DataSource = scanNullableStringPtr(dataSource)
	return rec, nil
}

func scanTreeRow(scanner interface{ Scan(dest ...any) error }) (TreeRowRecord, error) {
	var (
		rec             TreeRowRecord
		subPlot         sql.NullString
		measurementID   sql.NullInt64
		treeNum         sql.NullInt64
		treeSpp         sql.NullString
		dbh             sql.NullFloat64
		dbhClass        sql.NullFloat64
		totalHtCalc     sql.NullFloat64
		heightClass     sql.NullFloat64
		countAge        sql.NullInt64
		countHT         sql.NullFloat64
		totalAge        sql.NullInt64
		ageNote         sql.NullString
		treeHealth      sql.NullInt64
		treeOrigin      sql.NullString
		conks           sql.NullInt64
		blindConks      sql.NullInt64
		scars           sql.NullInt64
		forkOrCrook     sql.NullInt64
		frostCrack      sql.NullInt64
		mistletoe       sql.NullInt64
		rottenBranch    sql.NullInt64
		deadOrBrokenTop sql.NullInt64
		damageType      sql.NullString
		damageSeverity  sql.NullString
		crownClass      sql.NullString
		ht2LiveCrown    sql.NullFloat64
		appearance      sql.NullInt64
		crownCondition  sql.NullInt64
		barkRetention   sql.NullInt64
		woodCondition   sql.NullInt64
		lichenLoading   sql.NullInt64
		mossLoading     sql.NullInt64
		wildLifeUse     sql.NullString
		treeNotes       sql.NullString
		liveDead        sql.NullString
		cuVolume        sql.NullFloat64
		sph             sql.NullFloat64
		basalArea       sql.NullFloat64
		siteIndexID     sql.NullInt64
		siteIndex       sql.NullFloat64
		siteIndex24     sql.NullFloat64
		si50            sql.NullFloat64
	)
	if err := scanner.Scan(
		&rec.RowID,
		&rec.PlotNumber, &subPlot, &measurementID, &treeNum, &treeSpp,
		&dbh, &dbhClass, &totalHtCalc, &heightClass,
		&countAge, &countHT, &totalAge, &ageNote,
		&treeHealth, &treeOrigin,
		&conks, &blindConks, &scars, &forkOrCrook, &frostCrack,
		&mistletoe, &rottenBranch, &deadOrBrokenTop,
		&damageType, &damageSeverity, &crownClass, &ht2LiveCrown,
		&appearance, &crownCondition, &barkRetention, &woodCondition,
		&lichenLoading, &mossLoading, &wildLifeUse, &treeNotes, &liveDead,
		&cuVolume, &sph, &basalArea,
		&siteIndexID, &siteIndex, &siteIndex24, &si50,
	); err != nil {
		return TreeRowRecord{}, err
	}
	rec.SubPlot = scanNullableStringPtr(subPlot)
	rec.MeasurementID = scanNullableIntPtr(measurementID)
	rec.TreeNum = scanNullableIntPtr(treeNum)
	rec.TreeSpp = scanNullableStringPtr(treeSpp)
	rec.DBH = scanNullableFloat64Ptr(dbh)
	rec.DBHClass = scanNullableFloat64Ptr(dbhClass)
	rec.TotalHtCalc = scanNullableFloat64Ptr(totalHtCalc)
	rec.HeightClass = scanNullableFloat64Ptr(heightClass)
	rec.CountAge = scanNullableIntPtr(countAge)
	rec.CountHT = scanNullableFloat64Ptr(countHT)
	rec.TotalAge = scanNullableIntPtr(totalAge)
	rec.AgeNote = scanNullableStringPtr(ageNote)
	rec.TreeHealth = scanNullableIntPtr(treeHealth)
	rec.TreeOrigin = scanNullableStringPtr(treeOrigin)
	rec.Conks = scanNullableIntPtr(conks)
	rec.BlindConks = scanNullableIntPtr(blindConks)
	rec.Scars = scanNullableIntPtr(scars)
	rec.ForkOrCrook = scanNullableIntPtr(forkOrCrook)
	rec.FrostCrack = scanNullableIntPtr(frostCrack)
	rec.Mistletoe = scanNullableIntPtr(mistletoe)
	rec.RottenBranch = scanNullableIntPtr(rottenBranch)
	rec.DeadOrBrokenTop = scanNullableIntPtr(deadOrBrokenTop)
	rec.DamageType = scanNullableStringPtr(damageType)
	rec.DamageSeverity = scanNullableStringPtr(damageSeverity)
	rec.CrownClass = scanNullableStringPtr(crownClass)
	rec.Ht2LiveCrown = scanNullableFloat64Ptr(ht2LiveCrown)
	rec.Appearance = scanNullableIntPtr(appearance)
	rec.CrownCondition = scanNullableIntPtr(crownCondition)
	rec.BarkRetention = scanNullableIntPtr(barkRetention)
	rec.WoodCondition = scanNullableIntPtr(woodCondition)
	rec.LichenLoading = scanNullableIntPtr(lichenLoading)
	rec.MossLoading = scanNullableIntPtr(mossLoading)
	rec.WildLifeUse = scanNullableStringPtr(wildLifeUse)
	rec.TreeNotes = scanNullableStringPtr(treeNotes)
	rec.LiveDead = scanNullableStringPtr(liveDead)
	rec.CuVolume = scanNullableFloat64Ptr(cuVolume)
	rec.SPH = scanNullableFloat64Ptr(sph)
	rec.BasalArea = scanNullableFloat64Ptr(basalArea)
	rec.SiteIndexID = scanNullableInt64Ptr(siteIndexID)
	rec.SiteIndex = scanNullableFloat64Ptr(siteIndex)
	rec.SiteIndex24 = scanNullableFloat64Ptr(siteIndex24)
	rec.SI50 = scanNullableFloat64Ptr(si50)
	return rec, nil
}

// ReadPlotMensurationTx loads all <project>_TreePlot and <project>_Trees rows for plotNumber
// inside an active read snapshot or transaction. Missing optional tables return HasTables=false
// with empty non-nil slices and nil error.
func ReadPlotMensurationTx(ctx context.Context, tx *sql.Tx, schema, project, plotNumber string, readOnly bool) (*PlotMensurationData, error) {
	if err := validateMensurationPlotNumber(plotNumber); err != nil {
		return nil, err
	}
	hasTP, hasT, err := HasMensurationTables(ctx, tx, schema, project)
	if err != nil {
		return nil, err
	}
	out := &PlotMensurationData{
		PlotNumber:  plotNumber,
		HasTables:   hasTP || hasT,
		HasTreePlot: hasTP,
		HasTrees:    hasT,
		TreePlots:   []TreePlotRecord{},
		Trees:       []TreeRowRecord{},
		ReadOnly:    readOnly,
	}
	qual := func(tbl string) string {
		if strings.TrimSpace(schema) == "" {
			return QuoteHeaderIdentifier(tbl)
		}
		return QuoteHeaderIdentifier(schema) + "." + QuoteHeaderIdentifier(tbl)
	}
	if hasTP {
		tblName := project + "_" + MensurationTreePlotSuffix
		exprs, err := buildMensurationSelectList(ctx, tx, schema, tblName, TreePlotColumns)
		if err != nil {
			return nil, err
		}
		query := `SELECT ` + strings.Join(exprs, ", ") + ` FROM ` + qual(tblName) +
			` WHERE ` + ExactTextPlotPredicate(`"PlotNumber"`) +
			` ORDER BY "SubPlot" COLLATE NOCASE ASC, "SubPlot" COLLATE BINARY ASC, "MeasurementID" ASC`
		rows, err := tx.QueryContext(ctx, query, plotNumber, plotNumber)
		if err != nil {
			return nil, err
		}
		if scanErr := func() (closeErr error) {
			defer func() { closeErr = errors.Join(closeErr, rows.Close()) }()
			for rows.Next() {
				rec, err := scanTreePlotRow(rows)
				if err != nil {
					return err
				}
				out.TreePlots = append(out.TreePlots, rec)
			}
			return rows.Err()
		}(); scanErr != nil {
			return nil, scanErr
		}
	}
	if hasT {
		tblName := project + "_" + MensurationTreesSuffix
		exprs, err := buildMensurationSelectList(ctx, tx, schema, tblName, TreesColumns)
		if err != nil {
			return nil, err
		}
		query := `SELECT rowid, ` + strings.Join(exprs, ", ") + ` FROM ` + qual(tblName) +
			` WHERE ` + ExactTextPlotPredicate(`"PlotNumber"`) +
			` ORDER BY CASE WHEN "SubPlot" IS NULL THEN 1 ELSE 0 END ASC, "SubPlot" COLLATE NOCASE ASC, ` +
			`CASE WHEN "MeasurementID" IS NULL THEN 1 ELSE 0 END ASC, "MeasurementID" ASC, ` +
			`CASE WHEN "TreeNum" IS NULL THEN 1 ELSE 0 END ASC, "TreeNum" ASC, rowid ASC`
		rows, err := tx.QueryContext(ctx, query, plotNumber, plotNumber)
		if err != nil {
			return nil, err
		}
		if scanErr := func() (closeErr error) {
			defer func() { closeErr = errors.Join(closeErr, rows.Close()) }()
			for rows.Next() {
				rec, err := scanTreeRow(rows)
				if err != nil {
					return err
				}
				out.Trees = append(out.Trees, rec)
			}
			return rows.Err()
		}(); scanErr != nil {
			return nil, scanErr
		}
	}
	return out, nil
}

func requireMensurationPlotUnlocked(ctx context.Context, tx *sql.Tx, project, plotNumber string) error {
	var lockedCount int
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM `+QuoteHeaderIdentifier(project+"_Env")+
			` WHERE `+ExactTextPlotPredicate(`"PlotNumber"`)+
			` AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
		plotNumber, plotNumber,
	).Scan(&lockedCount); err != nil {
		return err
	}
	if lockedCount > 0 {
		return fmt.Errorf("plot %q is locked (Flag = -1); unlock the plot before editing mensuration data", plotNumber)
	}
	return nil
}

func nullableStringParam(s *string) any {
	if s == nil {
		return nil
	}
	return *s
}

func nullableIntParam(n *int) any {
	if n == nil {
		return nil
	}
	return *n
}

func nullableInt64Param(n *int64) any {
	if n == nil {
		return nil
	}
	return *n
}

func nullableFloatParam(f *float64) any {
	if f == nil {
		return nil
	}
	return *f
}

func mensurationAuditValue(v any) any {
	if v == nil {
		return nil
	}
	switch x := v.(type) {
	case float64:
		return SourceDoubleDecimalString(x)
	case bool:
		return HeaderAuditValue(x)
	default:
		return HeaderAuditValue(v)
	}
}

func treePlotFieldValues(r TreePlotRecord) []any {
	return []any{
		r.PlotNumber, r.SubPlot, r.MeasurementID, nullableStringParam(r.MensurationID),
		nullableStringParam(r.Zone), nullableStringParam(r.SubZone), nullableStringParam(r.FIZ),
		nullableStringParam(r.TreeSurveyor), nullableStringParam(r.Date),
		r.CruisePlot, r.CWDPlot, r.WildlifePlot, r.InformalPlot, r.SiteIndexPlot,
		nullableFloatParam(r.BAF), nullableFloatParam(r.DBHLimit), nullableIntParam(r.StandAge),
		nullableFloatParam(r.PlotSize), nullableStringParam(r.SeralStage), nullableStringParam(r.FSRegionDistrict),
		nullableStringParam(r.Location), nullableStringParam(r.BECSiteUnit), nullableIntParam(r.StandAgeVPro),
		nullableStringParam(r.SiteSeries), nullableStringParam(r.Comment), nullableStringParam(r.DataSource),
	}
}

func treePlotSQLArgs(r TreePlotRecord) []any {
	return []any{
		r.PlotNumber, r.SubPlot, r.MeasurementID, nullableStringParam(r.MensurationID),
		nullableStringParam(r.Zone), nullableStringParam(r.SubZone), nullableStringParam(r.FIZ),
		nullableStringParam(r.TreeSurveyor), nullableStringParam(r.Date),
		accessBoolToInt64(r.CruisePlot), accessBoolToInt64(r.CWDPlot),
		accessBoolToInt64(r.WildlifePlot), accessBoolToInt64(r.InformalPlot),
		accessBoolToInt64(r.SiteIndexPlot),
		nullableFloatParam(r.BAF), nullableFloatParam(r.DBHLimit), nullableIntParam(r.StandAge),
		nullableFloatParam(r.PlotSize), nullableStringParam(r.SeralStage), nullableStringParam(r.FSRegionDistrict),
		nullableStringParam(r.Location), nullableStringParam(r.BECSiteUnit), nullableIntParam(r.StandAgeVPro),
		nullableStringParam(r.SiteSeries), nullableStringParam(r.Comment), nullableStringParam(r.DataSource),
	}
}

func treeRowFieldValues(r TreeRowRecord) []any {
	return []any{
		r.PlotNumber, nullableStringParam(r.SubPlot), nullableIntParam(r.MeasurementID),
		nullableIntParam(r.TreeNum), nullableStringParam(r.TreeSpp),
		nullableFloatParam(r.DBH), nullableFloatParam(r.DBHClass),
		nullableFloatParam(r.TotalHtCalc), nullableFloatParam(r.HeightClass),
		nullableIntParam(r.CountAge), nullableFloatParam(r.CountHT),
		nullableIntParam(r.TotalAge), nullableStringParam(r.AgeNote),
		nullableIntParam(r.TreeHealth), nullableStringParam(r.TreeOrigin),
		nullableIntParam(r.Conks), nullableIntParam(r.BlindConks), nullableIntParam(r.Scars),
		nullableIntParam(r.ForkOrCrook), nullableIntParam(r.FrostCrack), nullableIntParam(r.Mistletoe),
		nullableIntParam(r.RottenBranch), nullableIntParam(r.DeadOrBrokenTop),
		nullableStringParam(r.DamageType), nullableStringParam(r.DamageSeverity),
		nullableStringParam(r.CrownClass), nullableFloatParam(r.Ht2LiveCrown),
		nullableIntParam(r.Appearance), nullableIntParam(r.CrownCondition),
		nullableIntParam(r.BarkRetention), nullableIntParam(r.WoodCondition),
		nullableIntParam(r.LichenLoading), nullableIntParam(r.MossLoading),
		nullableStringParam(r.WildLifeUse), nullableStringParam(r.TreeNotes), nullableStringParam(r.LiveDead),
		nullableFloatParam(r.CuVolume), nullableFloatParam(r.SPH), nullableFloatParam(r.BasalArea),
		nullableInt64Param(r.SiteIndexID), nullableFloatParam(r.SiteIndex),
		nullableFloatParam(r.SiteIndex24), nullableFloatParam(r.SI50),
	}
}

func auditMensurationDiff(
	ctx context.Context,
	wtx *WriteTx,
	tableSuffix, plotNumber string,
	rowRefID *int64,
	columns []string,
	before, after []any,
	user string,
	auditStrength int,
	when string,
) error {
	if auditStrength <= 0 {
		return nil
	}
	if strings.TrimSpace(user) == "" {
		user = "User"
	}
	for i, col := range columns {
		var bVal, aVal any
		if before != nil {
			bVal = before[i]
		}
		if after != nil {
			aVal = after[i]
		}
		if !AuditHeaderChange(bVal, aVal, auditStrength) {
			continue
		}
		colCopy := col
		plotCopy := plotNumber
		if _, err := wtx.RecordAudit(ctx, AuditWriteEntry{
			Project:    wtx.Project,
			User:       user,
			PlotNumber: &plotCopy,
			Table:      tableSuffix,
			EditField:  &colCopy,
			EditWhen:   when,
			BeforeEdit: mensurationAuditValue(bVal),
			AfterEdit:  mensurationAuditValue(aVal),
			ID:         rowRefID,
		}); err != nil {
			return err
		}
	}
	return nil
}

// SaveTreePlotInTx atomically inserts or updates one <project>_TreePlot row inside an active
// BEGIN IMMEDIATE WriteTx and writes canonical <project>_Audit entries.
func SaveTreePlotInTx(ctx context.Context, wtx *WriteTx, user string, auditStrength int, rec TreePlotRecord) (*TreePlotRecord, error) {
	if err := ValidateTreePlotRecord(&rec); err != nil {
		return nil, err
	}
	hasTP, _, err := HasMensurationTables(ctx, wtx, "main", wtx.Project)
	if err != nil {
		return nil, err
	}
	if !hasTP {
		return nil, ErrMensurationTablesNotFound
	}
	if err := ChildParent(wtx.Tx, wtx.Project, rec.PlotNumber); err != nil {
		return nil, err
	}
	if err := requireMensurationPlotUnlocked(ctx, wtx.Tx, wtx.Project, rec.PlotNumber); err != nil {
		return nil, err
	}

	tblName := wtx.Project + "_" + MensurationTreePlotSuffix
	qTbl := QuoteHeaderIdentifier(tblName)
	exprs, err := buildMensurationSelectList(ctx, wtx.Tx, "main", tblName, TreePlotColumns)
	if err != nil {
		return nil, err
	}

	whereKey := ExactTextPlotPredicate(`"PlotNumber"`) + ` AND ` + ExactTextPlotPredicate(`"SubPlot"`) + ` AND "MeasurementID" = ?`
	existingRow := wtx.QueryRowContext(ctx,
		`SELECT `+strings.Join(exprs, ", ")+` FROM `+qTbl+` WHERE `+whereKey,
		rec.PlotNumber, rec.PlotNumber, rec.SubPlot, rec.SubPlot, rec.MeasurementID,
	)
	var beforeVals []any
	existing, scanErr := scanTreePlotRow(existingRow)
	creating := false
	if errors.Is(scanErr, sql.ErrNoRows) {
		creating = true
	} else if scanErr != nil {
		return nil, scanErr
	} else {
		beforeVals = treePlotFieldValues(existing)
	}

	args := treePlotSQLArgs(rec)
	if creating {
		quotedCols := make([]string, len(TreePlotColumns))
		marks := make([]string, len(TreePlotColumns))
		for i, c := range TreePlotColumns {
			quotedCols[i] = QuoteHeaderIdentifier(c)
			marks[i] = "?"
		}
		if _, err := wtx.ExecContext(ctx,
			`INSERT INTO `+qTbl+` (`+strings.Join(quotedCols, ", ")+`) VALUES (`+strings.Join(marks, ", ")+`)`,
			args...,
		); err != nil {
			return nil, fmt.Errorf("insert %s: %w", tblName, err)
		}
	} else {
		setClauses := make([]string, 0, len(TreePlotColumns)-3)
		updateArgs := make([]any, 0, len(TreePlotColumns)+2)
		for i := 3; i < len(TreePlotColumns); i++ {
			setClauses = append(setClauses, QuoteHeaderIdentifier(TreePlotColumns[i])+` = ?`)
			updateArgs = append(updateArgs, args[i])
		}
		updateArgs = append(updateArgs, rec.PlotNumber, rec.PlotNumber, rec.SubPlot, rec.SubPlot, rec.MeasurementID)
		res, err := wtx.ExecContext(ctx,
			`UPDATE `+qTbl+` SET `+strings.Join(setClauses, ", ")+` WHERE `+whereKey,
			updateArgs...,
		)
		if err != nil {
			return nil, fmt.Errorf("update %s: %w", tblName, err)
		}
		if n, aErr := res.RowsAffected(); aErr != nil || n != 1 {
			return nil, errors.Join(aErr, fmt.Errorf("update %s affected %d rows (expected 1)", tblName, n))
		}
	}

	mid64 := int64(rec.MeasurementID)
	now := time.Now().Format("2006-01-02 15:04:05")
	if err := auditMensurationDiff(ctx, wtx, "_"+MensurationTreePlotSuffix, rec.PlotNumber, &mid64,
		TreePlotColumns, beforeVals, treePlotFieldValues(rec), user, auditStrength, now); err != nil {
		return nil, err
	}
	saved := rec
	return &saved, nil
}

// DeleteTreePlotInTx atomically deletes one <project>_TreePlot row by composite key and audits it.
func DeleteTreePlotInTx(ctx context.Context, wtx *WriteTx, user string, auditStrength int, plotNumber, subPlot string, measurementID int) error {
	if err := validateMensurationPlotNumber(plotNumber); err != nil {
		return err
	}
	if strings.TrimSpace(subPlot) == "" {
		return errors.New("TreePlot.SubPlot is required")
	}
	hasTP, _, err := HasMensurationTables(ctx, wtx, "main", wtx.Project)
	if err != nil {
		return err
	}
	if !hasTP {
		return ErrMensurationTablesNotFound
	}
	if err := requireMensurationPlotUnlocked(ctx, wtx.Tx, wtx.Project, plotNumber); err != nil {
		return err
	}

	tblName := wtx.Project + "_" + MensurationTreePlotSuffix
	qTbl := QuoteHeaderIdentifier(tblName)
	exprs, err := buildMensurationSelectList(ctx, wtx.Tx, "main", tblName, TreePlotColumns)
	if err != nil {
		return err
	}
	whereKey := ExactTextPlotPredicate(`"PlotNumber"`) + ` AND ` + ExactTextPlotPredicate(`"SubPlot"`) + ` AND "MeasurementID" = ?`
	existing, err := scanTreePlotRow(wtx.QueryRowContext(ctx,
		`SELECT `+strings.Join(exprs, ", ")+` FROM `+qTbl+` WHERE `+whereKey,
		plotNumber, plotNumber, subPlot, subPlot, measurementID,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("TreePlot record (%s, %s, %d) was not found", plotNumber, subPlot, measurementID)
	}
	if err != nil {
		return err
	}

	res, err := wtx.ExecContext(ctx, `DELETE FROM `+qTbl+` WHERE `+whereKey,
		plotNumber, plotNumber, subPlot, subPlot, measurementID)
	if err != nil {
		return err
	}
	if n, aErr := res.RowsAffected(); aErr != nil || n != 1 {
		return errors.Join(aErr, fmt.Errorf("delete %s affected %d rows (expected 1)", tblName, n))
	}

	mid64 := int64(measurementID)
	now := time.Now().Format("2006-01-02 15:04:05")
	return auditMensurationDiff(ctx, wtx, "_"+MensurationTreePlotSuffix, plotNumber, &mid64,
		TreePlotColumns, treePlotFieldValues(existing), nil, user, auditStrength, now)
}

// SaveTreeRowInTx atomically inserts or updates one <project>_Trees row inside an active
// BEGIN IMMEDIATE WriteTx and writes canonical <project>_Audit entries.
func SaveTreeRowInTx(ctx context.Context, wtx *WriteTx, user string, auditStrength int, rec TreeRowRecord) (*TreeRowRecord, error) {
	if err := ValidateTreeRowRecord(&rec); err != nil {
		return nil, err
	}
	_, hasT, err := HasMensurationTables(ctx, wtx, "main", wtx.Project)
	if err != nil {
		return nil, err
	}
	if !hasT {
		return nil, ErrMensurationTablesNotFound
	}
	if err := ChildParent(wtx.Tx, wtx.Project, rec.PlotNumber); err != nil {
		return nil, err
	}
	if err := requireMensurationPlotUnlocked(ctx, wtx.Tx, wtx.Project, rec.PlotNumber); err != nil {
		return nil, err
	}

	tblName := wtx.Project + "_" + MensurationTreesSuffix
	qTbl := QuoteHeaderIdentifier(tblName)
	exprs, err := buildMensurationSelectList(ctx, wtx.Tx, "main", tblName, TreesColumns)
	if err != nil {
		return nil, err
	}

	var (
		creating   bool
		targetRID  int64
		beforeVals []any
	)
	if rec.RowID > 0 {
		existing, scanErr := scanTreeRow(wtx.QueryRowContext(ctx,
			`SELECT rowid, `+strings.Join(exprs, ", ")+` FROM `+qTbl+` WHERE rowid = ? AND `+ExactTextPlotPredicate(`"PlotNumber"`),
			rec.RowID, rec.PlotNumber, rec.PlotNumber,
		))
		if errors.Is(scanErr, sql.ErrNoRows) {
			return nil, fmt.Errorf("Trees row %d for plot %s no longer exists; reload before saving", rec.RowID, rec.PlotNumber)
		}
		if scanErr != nil {
			return nil, scanErr
		}
		targetRID = existing.RowID
		beforeVals = treeRowFieldValues(existing)
	} else if rec.SubPlot != nil && rec.MeasurementID != nil && rec.TreeNum != nil {
		rows, err := wtx.QueryContext(ctx,
			`SELECT rowid, `+strings.Join(exprs, ", ")+` FROM `+qTbl+
				` WHERE `+ExactTextPlotPredicate(`"PlotNumber"`)+` AND `+ExactTextPlotPredicate(`"SubPlot"`)+
				` AND "MeasurementID" = ? AND "TreeNum" = ?`,
			rec.PlotNumber, rec.PlotNumber, *rec.SubPlot, *rec.SubPlot, *rec.MeasurementID, *rec.TreeNum,
		)
		if err != nil {
			return nil, err
		}
		var matches []TreeRowRecord
		if scanErr := func() (closeErr error) {
			defer func() { closeErr = errors.Join(closeErr, rows.Close()) }()
			for rows.Next() {
				m, err := scanTreeRow(rows)
				if err != nil {
					return err
				}
				matches = append(matches, m)
			}
			return rows.Err()
		}(); scanErr != nil {
			return nil, scanErr
		}
		switch len(matches) {
		case 0:
			creating = true
		case 1:
			targetRID = matches[0].RowID
			beforeVals = treeRowFieldValues(matches[0])
		default:
			return nil, fmt.Errorf("multiple Trees rows match (%s, %s, %d, %d); supply rowId to update a specific row",
				rec.PlotNumber, *rec.SubPlot, *rec.MeasurementID, *rec.TreeNum)
		}
	} else {
		creating = true
	}

	args := treeRowFieldValues(rec)
	if creating {
		quotedCols := make([]string, len(TreesColumns))
		marks := make([]string, len(TreesColumns))
		for i, c := range TreesColumns {
			quotedCols[i] = QuoteHeaderIdentifier(c)
			marks[i] = "?"
		}
		res, err := wtx.ExecContext(ctx,
			`INSERT INTO `+qTbl+` (`+strings.Join(quotedCols, ", ")+`) VALUES (`+strings.Join(marks, ", ")+`)`,
			args...,
		)
		if err != nil {
			return nil, fmt.Errorf("insert %s: %w", tblName, err)
		}
		rid, err := res.LastInsertId()
		if err != nil {
			return nil, err
		}
		targetRID = rid
	} else {
		setClauses := make([]string, 0, len(TreesColumns)-1)
		updateArgs := make([]any, 0, len(TreesColumns)+2)
		for i := 1; i < len(TreesColumns); i++ {
			setClauses = append(setClauses, QuoteHeaderIdentifier(TreesColumns[i])+` = ?`)
			updateArgs = append(updateArgs, args[i])
		}
		updateArgs = append(updateArgs, targetRID, rec.PlotNumber, rec.PlotNumber)
		res, err := wtx.ExecContext(ctx,
			`UPDATE `+qTbl+` SET `+strings.Join(setClauses, ", ")+` WHERE rowid = ? AND `+ExactTextPlotPredicate(`"PlotNumber"`),
			updateArgs...,
		)
		if err != nil {
			return nil, fmt.Errorf("update %s: %w", tblName, err)
		}
		if n, aErr := res.RowsAffected(); aErr != nil || n != 1 {
			return nil, errors.Join(aErr, fmt.Errorf("update %s row %d affected %d rows (expected 1)", tblName, targetRID, n))
		}
	}

	var refID *int64
	if rec.TreeNum != nil {
		tn := int64(*rec.TreeNum)
		refID = &tn
	} else {
		rid := targetRID
		refID = &rid
	}
	now := time.Now().Format("2006-01-02 15:04:05")
	if err := auditMensurationDiff(ctx, wtx, "_"+MensurationTreesSuffix, rec.PlotNumber, refID,
		TreesColumns, beforeVals, args, user, auditStrength, now); err != nil {
		return nil, err
	}
	saved := rec
	saved.RowID = targetRID
	return &saved, nil
}

// DeleteTreeRowInTx atomically deletes matching <project>_Trees row(s) by
// (plotNumber, subPlot, measurementID, treeNum) and audits each deleted row.
func DeleteTreeRowInTx(ctx context.Context, wtx *WriteTx, user string, auditStrength int, plotNumber, subPlot string, measurementID, treeNum int) error {
	if err := validateMensurationPlotNumber(plotNumber); err != nil {
		return err
	}
	_, hasT, err := HasMensurationTables(ctx, wtx, "main", wtx.Project)
	if err != nil {
		return err
	}
	if !hasT {
		return ErrMensurationTablesNotFound
	}
	if err := requireMensurationPlotUnlocked(ctx, wtx.Tx, wtx.Project, plotNumber); err != nil {
		return err
	}

	tblName := wtx.Project + "_" + MensurationTreesSuffix
	qTbl := QuoteHeaderIdentifier(tblName)
	exprs, err := buildMensurationSelectList(ctx, wtx.Tx, "main", tblName, TreesColumns)
	if err != nil {
		return err
	}

	var (
		whereSQL  string
		whereArgs []any
	)
	if subPlot == "" {
		whereSQL = ExactTextPlotPredicate(`"PlotNumber"`) + ` AND ("SubPlot" IS NULL OR "SubPlot" = '') AND "MeasurementID" = ? AND "TreeNum" = ?`
		whereArgs = []any{plotNumber, plotNumber, measurementID, treeNum}
	} else {
		whereSQL = ExactTextPlotPredicate(`"PlotNumber"`) + ` AND ` + ExactTextPlotPredicate(`"SubPlot"`) + ` AND "MeasurementID" = ? AND "TreeNum" = ?`
		whereArgs = []any{plotNumber, plotNumber, subPlot, subPlot, measurementID, treeNum}
	}

	rows, err := wtx.QueryContext(ctx, `SELECT rowid, `+strings.Join(exprs, ", ")+` FROM `+qTbl+` WHERE `+whereSQL, whereArgs...)
	if err != nil {
		return err
	}
	var targets []TreeRowRecord
	if scanErr := func() (closeErr error) {
		defer func() { closeErr = errors.Join(closeErr, rows.Close()) }()
		for rows.Next() {
			rec, err := scanTreeRow(rows)
			if err != nil {
				return err
			}
			targets = append(targets, rec)
		}
		return rows.Err()
	}(); scanErr != nil {
		return scanErr
	}
	if len(targets) == 0 {
		return fmt.Errorf("Trees record (%s, %s, %d, %d) was not found", plotNumber, subPlot, measurementID, treeNum)
	}

	now := time.Now().Format("2006-01-02 15:04:05")
	tn64 := int64(treeNum)
	for _, target := range targets {
		res, err := wtx.ExecContext(ctx, `DELETE FROM `+qTbl+` WHERE rowid = ?`, target.RowID)
		if err != nil {
			return err
		}
		if n, aErr := res.RowsAffected(); aErr != nil || n != 1 {
			return errors.Join(aErr, fmt.Errorf("delete %s row %d affected %d rows (expected 1)", tblName, target.RowID, n))
		}
		if err := auditMensurationDiff(ctx, wtx, "_"+MensurationTreesSuffix, plotNumber, &tn64,
			TreesColumns, treeRowFieldValues(target), nil, user, auditStrength, now); err != nil {
			return err
		}
	}
	return nil
}
