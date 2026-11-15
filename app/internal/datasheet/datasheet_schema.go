package datasheet

import (
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"strings"
)

const (
	DatasheetDefaultLimit = 100
	DatasheetMaxLimit     = 1000
	datasheetHistoryTable = "__VPRO_DatasheetEditHistory"
	datasheetHistorySQL   = `CREATE TABLE "__VPRO_DatasheetEditHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

// Canonical 9 table keys supported by the Universal Project Datasheet Grid.
var canonicalDatasheetKeys = []string{
	"Env", "Admin", "Veg", "Humus", "Mineral", "Other", "SU", "Lump", "Hierarchy",
}

type DatasheetColumnMeta struct {
	Name          string `json:"name"`
	DeclaredType  string `json:"declaredType"`
	Kind          string `json:"kind"` // "text" | "integer" | "single" | "double" | "boolean"
	Pinned        bool   `json:"pinned"`
	Editable      bool   `json:"editable"`
	Protected     bool   `json:"protected"`
	MaxUTF16      int    `json:"maxUtf16"`
	IsCoverSingle bool   `json:"isCoverSingle"`
	IsBoolean     bool   `json:"isBoolean"`
}

type DatasheetTableInfo struct {
	Key               string                `json:"key"`
	Label             string                `json:"label"`
	Role              string                `json:"role"`
	TableName         string                `json:"tableName"`
	PinnedColumn      string                `json:"pinnedColumn"`
	Available         bool                  `json:"available"`
	UnavailableReason string                `json:"unavailableReason,omitempty"`
	Editable          bool                  `json:"editable"`
	ReadOnly          bool                  `json:"readOnly"`
	RowCount          int64                 `json:"rowCount"`
	Columns           []DatasheetColumnMeta `json:"columns"`
}

type DatasheetSortSpec struct {
	Column    string `json:"column"`
	Direction string `json:"direction"` // "asc" | "desc"
}

func (r *DatasheetSortSpec) UnmarshalJSON(data []byte) error {
	type plain DatasheetSortSpec
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetFilterSpec struct {
	Column string `json:"column"`
	Op     string `json:"op"` // "contains" | "eq" | "starts_with" | "ends_with" | "is_null" | "not_null"
	Value  string `json:"value"`
}

func (r *DatasheetFilterSpec) UnmarshalJSON(data []byte) error {
	type plain DatasheetFilterSpec
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetPageRequest struct {
	TableKey        string                `json:"tableKey"`
	Offset          int                   `json:"offset"`
	Limit           int                   `json:"limit"`
	Sort            []DatasheetSortSpec   `json:"sort"`
	Filters         []DatasheetFilterSpec `json:"filters"`
	GlobalSearch    string                `json:"globalSearch"`
	ScopeToActiveSU bool                  `json:"scopeToActiveSU"`
}

func (r *DatasheetPageRequest) UnmarshalJSON(data []byte) error {
	type plain DatasheetPageRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetRow struct {
	RowID string                         `json:"rowId"`
	Cells []vprocore.ProjectMetadataCell `json:"cells"`
}

type DatasheetPage struct {
	ContextID       string                `json:"contextId"`
	Project         string                `json:"project"`
	ProjectPath     string                `json:"projectPath"`
	SU              string                `json:"su"`
	Hierarchy       string                `json:"hierarchy"`
	TableKey        string                `json:"tableKey"`
	TableName       string                `json:"tableName"`
	PinnedColumn    string                `json:"pinnedColumn"`
	Columns         []DatasheetColumnMeta `json:"columns"`
	Rows            []DatasheetRow        `json:"rows"`
	Offset          int                   `json:"offset"`
	Limit           int                   `json:"limit"`
	TotalRows       int64                 `json:"totalRows"`
	CanEditMaster   bool                  `json:"canEditMaster"`
	ReadOnly        bool                  `json:"readOnly"`
	ScopeToActiveSU bool                  `json:"scopeToActiveSU"`
}

type DatasheetCellEdit struct {
	RowID  string                       `json:"rowId"`
	Column string                       `json:"column"`
	Before vprocore.ProjectMetadataCell `json:"before"`
	After  vprocore.ProjectMetadataCell `json:"after"`
}

func (r *DatasheetCellEdit) UnmarshalJSON(data []byte) error {
	type plain DatasheetCellEdit
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetEditRequest struct {
	TableKey string              `json:"tableKey"`
	Edits    []DatasheetCellEdit `json:"edits"`
}

func (r *DatasheetEditRequest) UnmarshalJSON(data []byte) error {
	type plain DatasheetEditRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetEditResult struct {
	ContextID    string `json:"contextId"`
	TableKey     string `json:"tableKey"`
	TableName    string `json:"tableName"`
	UpdatedRows  int    `json:"updatedRows"`
	UpdatedCells int    `json:"updatedCells"`
	AuditRows    int    `json:"auditRows"`
}

type DatasheetFindReplaceRequest struct {
	TableKey        string                `json:"tableKey"`
	Column          string                `json:"column"`
	FindText        string                `json:"findText"`
	ReplaceText     string                `json:"replaceText"`
	MatchCase       bool                  `json:"matchCase"`
	ExactCell       bool                  `json:"exactCell"`
	Filters         []DatasheetFilterSpec `json:"filters"`
	GlobalSearch    string                `json:"globalSearch"`
	ScopeToActiveSU bool                  `json:"scopeToActiveSU"`
	MaxPreview      int                   `json:"maxPreview"`
}

func (r *DatasheetFindReplaceRequest) UnmarshalJSON(data []byte) error {
	type plain DatasheetFindReplaceRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetFindReplaceItem struct {
	RowID           string                       `json:"rowId"`
	PinnedIdentity  string                       `json:"pinnedIdentity"`
	Column          string                       `json:"column"`
	BeforeText      string                       `json:"beforeText"`
	AfterText       string                       `json:"afterText"`
	Edit            DatasheetCellEdit            `json:"edit"`
	ValidationError string                       `json:"validationError,omitempty"`
	BeforeCell      vprocore.ProjectMetadataCell `json:"beforeCell"`
	AfterCell       vprocore.ProjectMetadataCell `json:"afterCell"`
}

type DatasheetFindReplacePreview struct {
	ContextID    string                     `json:"contextId"`
	TableKey     string                     `json:"tableKey"`
	TableName    string                     `json:"tableName"`
	Column       string                     `json:"column"`
	MatchedRows  int                        `json:"matchedRows"`
	ValidCount   int                        `json:"validCount"`
	InvalidCount int                        `json:"invalidCount"`
	Items        []DatasheetFindReplaceItem `json:"items"`
	Truncated    bool                       `json:"truncated"`
}

type resolvedDatasheetTarget struct {
	key               string
	label             string
	role              string
	tableName         string
	pinnedColumn      string
	available         bool
	readOnly          bool
	unavailableReason string
}

func resolveDatasheetTargets(owner *vprocore.SqliteContext) []resolvedDatasheetTarget {
	p := owner.Selection.Project
	suAvail := owner.Selection.SU != "None" && owner.Selection.SU != ""
	suTable := ""
	suReason := ""
	if suAvail {
		suTable = owner.Selection.SU + "_SU"
	} else {
		suReason = "No active Site Unit (SU) table is selected in the current context"
	}
	hierAvail := owner.Selection.Hierarchy != "None" && owner.Selection.Hierarchy != ""
	hierTable := ""
	hierReason := ""
	if hierAvail {
		hierTable = owner.Selection.Hierarchy + "_Hierarchy"
	} else {
		hierReason = "No active Hierarchy table is selected in the current context"
	}
	return []resolvedDatasheetTarget{
		{key: "Env", label: p + "_Env (Site & Soil Header)", role: "project", tableName: p + "_Env", pinnedColumn: "PlotNumber", available: true},
		{key: "Admin", label: p + "_Admin (Admin & QA)", role: "project", tableName: p + "_Admin", pinnedColumn: "Plot", available: true},
		{key: "Veg", label: p + "_Veg (Vegetation Strata)", role: "project", tableName: p + "_Veg", pinnedColumn: "PlotNumber", available: true},
		{key: "Humus", label: p + "_Humus (Humus Horizons)", role: "project", tableName: p + "_Humus", pinnedColumn: "PlotNumber", available: true},
		{key: "Mineral", label: p + "_Mineral (Mineral Horizons)", role: "project", tableName: p + "_Mineral", pinnedColumn: "PlotNumber", available: true},
		{key: "Other", label: p + "_Other (Other Attributes)", role: "project", tableName: p + "_Other", pinnedColumn: "PlotNumber", available: true},
		{key: "SU", label: suLabel(owner.Selection.SU), role: "su", tableName: suTable, pinnedColumn: "PlotNumber", available: suAvail, unavailableReason: suReason},
		{key: "Lump", label: p + "_Lump (Combine Species)", role: "project", tableName: p + "_Lump", pinnedColumn: "SppCode", available: true},
		{key: "Hierarchy", label: hierLabel(owner.Selection.Hierarchy), role: "hierarchy", tableName: hierTable, pinnedColumn: "Name", available: hierAvail, unavailableReason: hierReason},
	}
}

func suLabel(su string) string {
	if su == "" || su == "None" {
		return "Active _SU (None Selected)"
	}
	return su + "_SU (Site Units)"
}

func hierLabel(h string) string {
	if h == "" || h == "None" {
		return "Active _Hierarchy (None Selected)"
	}
	return h + "_Hierarchy (Classification Hierarchy)"
}

func resolveExtendedDatasheetTargets(owner *vprocore.SqliteContext) []resolvedDatasheetTarget {
	p := owner.Selection.Project
	targets := resolveDatasheetTargets(owner)
	return append(targets,
		resolvedDatasheetTarget{key: "Audit", label: p + "_Audit (Change Audit Log)", role: "project", tableName: p + "_Audit", pinnedColumn: "PlotNumber", available: true, readOnly: true},
		resolvedDatasheetTarget{key: "Metadata", label: p + "_Metadata (Project Metadata)", role: "project", tableName: p + "_Metadata", pinnedColumn: "ProjectID", available: true, readOnly: true},
	)
}

func findDatasheetTarget(owner *vprocore.SqliteContext, tableKey string) (resolvedDatasheetTarget, error) {
	trimmed := strings.TrimPrefix(strings.TrimSpace(tableKey), "_")
	for _, target := range resolveExtendedDatasheetTargets(owner) {
		if strings.EqualFold(target.key, trimmed) {
			return target, nil
		}
	}
	return resolvedDatasheetTarget{}, fmt.Errorf("unsupported datasheet table key %q; expected one of %s, Audit, Metadata", tableKey, strings.Join(canonicalDatasheetKeys, ", "))
}

// Known Access VP08 UTF-16 text field widths across all 9 canonical tables.
var datasheetUTF16Limits = map[string]map[string]int{
	"Env": {
		"PlotNumber": 7, "FieldNumber": 50, "ProjectID": 30, "FSRegionDistrict": 7,
		"SiteSurveyor": 30, "PlotRepresenting": 255, "Location": 255, "Ecosection": 3, "NtsMapSheet": 8,
		"UTMZone": 2, "AirPhotoNum": 20, "Zone": 4, "SubZone": 8, "SiteSeries": 5,
		"SiteModifier1": 5, "SiteModifier2": 5, "TransDistrib": 3, "RealmClass": 5, "MapUnit": 15,
		"SnowCoverregime": 1, "MoistureRegime": 3, "NutrientRegime": 2, "SuccessionalStatus": 3,
		"StructuralStage": 6, "StructuralStageMod": 1, "MesoSlopePosition": 3, "SurfaceShape": 3,
		"SurfaceTopographyType": 3, "SurfaceTopographySize": 2, "WaterSource": 5, "Photo": 50,
		"Exposure1": 2, "Exposure2": 2, "SiteDisturbance1": 8, "SiteDisturbance2": 8, "SiteDisturbance3": 8,
		"SoilSurveyor": 30, "BedrockGeology1": 4, "BedrockGeology2": 4, "BedrockGeology3": 4,
		"CoarseFragLith1": 12, "CoarseFragLith2": 12, "CoarseFragLith3": 12,
		"TerrainTextureSurf": 3, "SurficialMaterialSurf": 6, "SurfaceExpSurf": 3, "GeoMorProSurf": 3,
		"TerrainTextureSubSurf": 3, "SurficialMaterialSubSurf": 6, "SurfaceExpSubSurf": 3, "GeoMorProSubSurf": 3,
		"FloodingRegimeFreq": 7, "MoistureRegimeSub": 3, "FloodingRegimeDur": 2, "SoilDrainage": 5,
		"RootRestrictingType": 1, "RootZoneParticleSize": 6, "SoilClassSubGroup": 4, "SoilClassGroup": 4,
		"HumusForm": 4, "HumusFormPhase": 50, "pHMethodCodeMineral": 3, "pHMethodCodeOrganic": 3,
		"HydroGeoSystem": 3, "HydroGeoSubSystem": 2, "VegSurveyor": 30, "Temporary": 100,
		"SV_PolygonNumber": 25, "SV_StandAgeEstMeas": 2, "SV_StandHeightEstMeas": 2,
		"SV_CanopyComposition": 50, "SV_RootZoneTexture": 100, "SV_FullCruiseCard": 50, "SV_AhorizonType": 5,
	},
	"Admin": {
		"Plot": 7, "PlotType": 10, "ProvinceStateTerritory": 255,
		"SitePlotQuality": 15, "VegPlotQuality": 15, "SoilPlotQuality": 15,
		"EnteredBy": 50, "UserSiteUnit": 100, "BECSiteUnit": 100,
		"SiteUnitShortName": 50, "SiteUnitLongName": 100, "GIS_BGC": 255, "BEC_Use": 255,
	},
	"Veg": {
		"PlotNumber": 7, "Species": 8, "Layer": 2, "HeightB": 255, "Collected": 1,
	},
	"Humus": {
		"PlotNumber": 7, "Horizon": 8, "HumusStructureDegree": 1, "HumusStructureKind": 5,
		"MycelAbundance": 1, "FecalAbundance": 1, "RootsAbundance": 6, "RootsSize": 6,
		"Consistence": 2, "Character": 2, "Fauna": 4,
	},
	"Mineral": {
		"PlotNumber": 7, "Horizon": 8, "PitDepthLimit": 1, "Colour": 14, "Texture": 4,
		"PercentCoarseFragsShape": 1, "RootsAbundance": 6, "RootsSize": 6,
		"MineralStructureClass": 3, "MineralStructureKind": 7,
		"MottlesAbundance": 1, "MottlesSize": 1, "MottlesContrast": 1,
		"ClayFilmsFreq": 2, "ClayFilmThickness": 3, "Effervescence": 2, "Porosity": 1,
	},
	"Other": {
		"PlotNumber": 7, "DataName": 50, "DataItem": 255, "UserItem1": 255, "UserItem2": 255, "UserItem3": 255,
	},
	"SU": {
		"PlotNumber": 7, "SiteUnit": 255,
	},
	"Lump": {
		"LumpCode": 50, "SppCode": 8,
	},
	"Hierarchy": {
		"Name": 255, "Tag": 255, "MyOrder": 255,
	},
}

// Cover columns subject to IEEE-754 SINGLE (float32) narrowing before `< 100 Or Is Null`.
var datasheetCoverSingleColumns = map[string]map[string]bool{
	"Env": {
		"StrataCoverTree": true, "StrataCoverShrub": true, "StrataCoverHerb": true, "StrataCoverMoss": true,
	},
	"Admin": {
		"StrataCoverTotal": true,
	},
	"Veg": {
		"Cover1": true, "Cover2": true, "Cover3": true, "TotalA": true,
		"Cover4": true, "Cover5": true, "Cover5a": true, "Cover5b": true, "Cover5c": true, "TotalB": true,
		"Cover6": true, "Cover7": true, "Cover8": true, "Cover9": true, "Cover10": true,
	},
}

// Access BOOLEAN columns stored as -1 (true) / 0 (false).
var datasheetBooleanColumns = map[string]map[string]bool{
	"Env":       {"SpeciesListComplete": true, "Flag": true, "SV_FloodPlain": true},
	"Admin":     {"UpdatedFromCards": true},
	"Veg":       {"Flag": true},
	"Humus":     {"Flag": true},
	"Mineral":   {"Flag": true},
	"Other":     {"UserFlag1": true, "UserFlag2": true, "UserFlag3": true, "Flag": true},
	"Lump":      {"Use": true},
	"Hierarchy": {"Flag": true},
}

// Double-precision columns (not narrowed to float32).
var datasheetDoubleColumns = map[string]map[string]bool{
	"Env": {"Latitude": true, "Longitude": true},
}

// 32-bit integer columns (default integer columns are INT16 unless listed here or declared INTEGER).
var datasheetInt32Columns = map[string]map[string]bool{
	"Veg":       {"ID": true, "LL": true, "PV": true},
	"Humus":     {"ID": true},
	"Mineral":   {"ID": true},
	"Other":     {"ID": true},
	"Hierarchy": {"ID": true, "Parent": true},
}

func classifyColumnMeta(tableKey string, col vprocore.ProjectMetadataColumn, pinnedColumn string, canEditMaster bool) DatasheetColumnMeta {
	upperType := strings.ToUpper(col.DeclaredType)
	isBool := datasheetBooleanColumns[tableKey][col.Name] || strings.Contains(upperType, "BOOL")
	isCover := datasheetCoverSingleColumns[tableKey][col.Name]
	isDouble := datasheetDoubleColumns[tableKey][col.Name] || strings.Contains(upperType, "DOUBLE")
	maxUTF16 := datasheetUTF16Limits[tableKey][col.Name]

	kind := "text"
	switch {
	case isBool:
		kind = "boolean"
	case isCover:
		kind = "single"
	case isDouble:
		kind = "double"
	case strings.Contains(upperType, "REAL") || strings.Contains(upperType, "FLOA") || strings.Contains(upperType, "SING"):
		kind = "single"
	case strings.Contains(upperType, "INT"):
		kind = "integer"
	}

	editable := true
	protected := false
	// Child row surrogate IDs, Hierarchy auto-IDs, and relational PlotNumber/Plot/SppCode keys are immutable in single-table grid mode.
	if col.Name == "ID" && (tableKey == "Veg" || tableKey == "Humus" || tableKey == "Mineral" || tableKey == "Other" || tableKey == "Hierarchy") {
		editable = false
		protected = true
	}
	if (col.Name == "PlotNumber" && (tableKey == "Env" || tableKey == "Veg" || tableKey == "Humus" || tableKey == "Mineral" || tableKey == "Other" || tableKey == "SU")) ||
		(col.Name == "Plot" && tableKey == "Admin") ||
		(col.Name == "SppCode" && tableKey == "Lump") {
		editable = false
		protected = true
	}
	// Audit and Metadata tables are strictly read-only in datasheet mode.
	if tableKey == "Audit" || tableKey == "Metadata" {
		editable = false
		protected = true
	}
	// Calculated Admin fields and custodian-locked BECSiteUnit protection.
	if tableKey == "Admin" && (col.Name == "HumusThickness" || col.Name == "StrataCoverTotal") {
		editable = false
		protected = true
	}
	if tableKey == "Admin" && col.Name == "BECSiteUnit" {
		protected = true
		if !canEditMaster {
			editable = false
		}
	}

	return DatasheetColumnMeta{
		Name:          col.Name,
		DeclaredType:  col.DeclaredType,
		Kind:          kind,
		Pinned:        strings.EqualFold(col.Name, pinnedColumn),
		Editable:      editable,
		Protected:     protected,
		MaxUTF16:      maxUTF16,
		IsCoverSingle: isCover,
		IsBoolean:     isBool,
	}
}
