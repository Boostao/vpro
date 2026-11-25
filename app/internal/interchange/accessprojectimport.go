//go:build !vpro_headless

package interchange

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type AccessImportTableSummary struct {
	Suffix      string `json:"suffix"`
	SourceTable string `json:"sourceTable"`
	Description string `json:"description"`
	RowCount    int    `json:"rowCount"`
	ColumnCount int    `json:"columnCount"`
	Action      string `json:"action"`
	Present     bool   `json:"present"`
}

type AccessProjectCandidate struct {
	SourceProject     string                     `json:"sourceProject"`
	SuggestedTarget   string                     `json:"suggestedTarget"`
	SuggestedDestPath string                     `json:"suggestedDestPath"`
	SourceVersion     string                     `json:"sourceVersion"`
	ConversionMode    string                     `json:"conversionMode"`
	Compatible        bool                       `json:"compatible"`
	StatusMessage     string                     `json:"statusMessage"`
	PlotCount         int                        `json:"plotCount"`
	Tables            []AccessImportTableSummary `json:"tables"`
	OptionalSUs       []string                   `json:"optionalSUs"`
}

type AccessDatabaseInspection struct {
	SourcePath   string                   `json:"sourcePath"`
	SourceSHA256 string                   `json:"sourceSha256"`
	Projects     []AccessProjectCandidate `json:"projects"`
}

type AccessProjectImportRequest struct {
	SourcePath        string `json:"sourcePath"`
	SourceProject     string `json:"sourceProject"`
	TargetProject     string `json:"targetProject"`
	DestinationPath   string `json:"destinationPath"`
	ActivateOnSuccess bool   `json:"activateOnSuccess"`
}

func (r *AccessProjectImportRequest) UnmarshalJSON(data []byte) error {
	type plain AccessProjectImportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type AccessProjectImportResult struct {
	SourcePath              string                     `json:"sourcePath"`
	SourceProject           string                     `json:"sourceProject"`
	SourceVersion           string                     `json:"sourceVersion"`
	ConversionMode          string                     `json:"conversionMode"`
	TargetProject           string                     `json:"targetProject"`
	DestinationPath         string                     `json:"destinationPath"`
	DestinationSHA          string                     `json:"destinationSha256"`
	PlotCount               int                        `json:"plotCount"`
	QuarantinedMalformedRow int                        `json:"quarantinedMalformedRows"`
	QuarantinedOrphanRows   int                        `json:"quarantinedOrphanRows"`
	Tables                  []AccessImportTableSummary `json:"tables"`
	ImportedSUs             []string                   `json:"importedSUs"`
	Activated               bool                       `json:"activated"`
	State                   *vprocore.ProjectState     `json:"state,omitempty"`
}

var vp07EnvMapping = [][2]string{
	{"PlotNumber", "PlotNumber"}, {"FieldNumber", "FieldNumber"}, {"ProjectID", "ProjectID"},
	{"FSRegionDistrict", "FSRegionDistrict"}, {"Date", "Date"}, {"SiteSurveyor", "SiteSurveyor"},
	{"PlotRepresenting", "PlotRepresenting"}, {"Location", "Location"}, {"Ecosection", "Ecosection"},
	{"NtsMapSheet", "NtsMapSheet"}, {"Longitude", "Longitude"}, {"Latitude", "Latitude"},
	{"UTMZone", "UTMZone"}, {"UTMEasting", "UTMEasting"}, {"UTMNorthing", "UTMNorthing"},
	{"LocationAccuracy", "LocationAccuracy"}, {"AirPhotoNum", "AirPhotoNum"}, {"XCoord", "XCoord"},
	{"YCoord", "YCoord"}, {"Zone", "Zone"}, {"SubZone", "SubZone"}, {"SiteSeries", "SiteSeries"},
	{"SiteModifier1", "SiteModifier1"}, {"SiteModifier2", "SiteModifier2"}, {"TransDistrib", "TransDistrib"},
	{"RealmClass", "RealmClass"}, {"MapUnit", "MapUnit"}, {"SnowCoverregime", "SnowCoverregime"},
	{"MoistureRegime", "MoistureRegime"}, {"NutrientRegime", "NutrientRegime"},
	{"SuccessionalStatus", "SuccessionalStatus"}, {"StructuralStage", "StructuralStage"},
	{"StructuralStageMod", "StructuralStageMod"}, {"StandAge", "StandAge"}, {"Elevation", "Elevation"},
	{"SlopeGradient", "SlopeGradient"}, {"Aspect", "Aspect"}, {"MesoSlopePosition", "MesoSlopePosition"},
	{"SurfaceShape", "SurfaceShape"}, {"SurfaceTopographyType", "SurfaceTopographyType"},
	{"SurfaceTopographySize", "SurfaceTopographySize"}, {"WaterSource", "WaterSource"}, {"Photo", "Photo"},
	{"Exposure1", "Exposure1"}, {"Exposure2", "Exposure2"}, {"SiteDisturbance1", "SiteDisturbance1"},
	{"SiteDisturbance2", "SiteDisturbance2"}, {"SiteDisturbance3", "SiteDisturbance3"},
	{"SubstrateDecWood", "SubstrateDecWood"}, {"SubstrateBedRock", "SubstrateBedRock"},
	{"SubstrateRocks", "SubstrateRocks"}, {"SubstrateMineralSoil", "SubstrateMineralSoil"},
	{"SubstrateOrganicMatter", "SubstrateOrganicMatter"}, {"SubstrateWater", "SubstrateWater"},
	{"SiteNotes", "SiteNotes"}, {"SoilSurveyor", "SoilSurveyor"}, {"BedrockGeology1", "BedrockGeology1"},
	{"BedrockGeology2", "BedrockGeology2"}, {"BedrockGeology3", "BedrockGeology3"},
	{"CoarseFragLith1", "CoarseFragLith1"}, {"CoarseFragLith2", "CoarseFragLith2"},
	{"CoarseFragLith3", "CoarseFragLith3"}, {"TerrainTextureSurf", "TerrainTextureSurf"},
	{"SurficialMaterialSurf", "SurficialMaterialSurf"}, {"SurfaceExpSurf", "SurfaceExpSurf"},
	{"GeoMorProSurf", "GeoMorProSurf"}, {"TerrainTextureSubSurf", "TerrainTextureSubSurf"},
	{"SurficialMaterialSubSurf", "SurficialMaterialSubSurf"}, {"SurfaceExpSubSurf", "SurfaceExpSubSurf"},
	{"GeoMorProSubSurf", "GeoMorProSubSurf"}, {"FloodingRegimeFreq", "FloodingRegimeFreq"},
	{"MoistureRegimeSub", "MoistureRegimeSub"}, {"FloodingRegimeDur", "FloodingRegimeDur"},
	{"SoilDrainage", "SoilDrainage"}, {"SeepageDepth", "SeepageDepth"},
	{"RootRestrictingType", "RootRestrictingType"}, {"RootRestrictingDepth", "RootRestrictingDepth"},
	{"RootZoneParticleSize", "RootZoneParticleSize"}, {"RootingDepth", "RootingDepth"},
	{"SoilClassSubGroup", "SoilClassSubGroup"}, {"SoilClassGroup", "SoilClassGroup"},
	{"HumusForm", "HumusForm"}, {"HumusFormPhase", "HumusFormPhase"},
	{"pHMethodCodeMineral", "pHMethodCodeMineral"}, {"pHMethodCodeOrganic", "pHMethodCodeOrganic"},
	{"SoilNotes", "SoilNotes"}, {"VegSurveyor", "VegSurveyor"}, {"StrataCoverTree", "StrataCoverTree"},
	{"StrataCoverShrub", "StrataCoverShrub"}, {"StrataCoverHerb", "StrataCoverHerb"},
	{"StrataCoverMoss", "StrataCoverMoss"}, {"VegNotes", "VegNotes"},
	{"HydroGeoSystem", "HydroGeoSystem"}, {"HydroGeoSubSystem", "HydroGeoSubSystem"},
	{"SpeciesListComplete", "SpeciesListComplete"}, {"Temporary", "Temporary"}, {"Flag", "Flag"},
	{"SV_PolygonNumber", "PolygonNumber"}, {"SV_FloodPlain", "FloodPlain"},
	{"SV_StandAgeEstMeas", "StandAgeEstMeas"}, {"SV_StandHeight", "StandHeight"},
	{"SV_StandHeightEstMeas", "StandHeightEstMeas"}, {"SV_CanopyComposition", "CanopyComposition"},
	{"SV_SoilDepth", "SoilDepth"}, {"SV_RootZoneTexture", "RootZoneTexture"},
	{"SV_PercentCoarseFrags", "PercentCoarseFrags"}, {"SV_GleyingMottlingCM", "GleyingMottlingCM"},
	{"SV_WaterTableCM", "WaterTableCM"}, {"SV_FullCruiseCard", "FullCruiseCard"},
	{"SV_AhorizonType", "AhorizonType"}, {"SV_AhorizonDepth", "AhorizonDepth"},
	{"ActiveLayerDepth", "ActiveLayerDepth"},
}

var vp07AdminFromEnvMapping = [][2]string{
	{"Plot", "PlotNumber"}, {"StartDate", "StartDate"}, {"PlotType", "PlotType"},
	{"PlotSize", "PlotSize"}, {"ProvinceStateTerritory", "ProvinceStateTerritory"},
	{"SitePlotQuality", "SitePlotQuality"}, {"VegPlotQuality", "VegPlotQuality"},
	{"SoilPlotQuality", "SoilPlotQuality"}, {"UpdatedFromCards", "UpdatedFromCards"},
	{"EnteredBy", "EnteredBy"}, {"UserSiteUnit", "UserSiteUnit"}, {"BECSiteUnit", "BECSiteUnit"},
	{"SiteUnitShortName", "SiteUnitShortName"}, {"SiteUnitLongName", "SiteUnitLongName"},
	{"OfficeNotes", "OfficeNotes"}, {"HumusThickness", "HumusThickness"},
	{"GIS_BGC", "GIS_BGC"}, {"GIS_BGC_ver", "GIS_BGC_ver"},
	{"StrataCoverTotal", "StrataCoverTotal"},
}

var vp06EnvMapping = [][2]string{
	{"PlotNumber", "PlotNumber"}, {"FieldNumber", "FieldNumber"}, {"ProjectID", "ProjectID"},
	{"FSRegionDistrict", "FSRegionDistrict"}, {"Date", "Date"}, {"SiteSurveyor", "SiteSurveyor"},
	{"PlotRepresenting", "PlotRepresenting"}, {"Location", "Location"}, {"Ecosection", "Ecosection"},
	{"NtsMapSheet", "NtsMapSheet"}, {"Longitude", "Longitude"}, {"Latitude", "Latitude"},
	{"UTMZone", "UTMZone"}, {"UTMEasting", "UTMEasting"}, {"UTMNorthing", "UTMNorthing"},
	{"LocationAccuracy", "LocationAccuracy"}, {"AirPhotoNum", "AirPhotoNum"}, {"XCoord", "XCoord"},
	{"YCoord", "YCoord"}, {"Zone", "Zone"}, {"SubZone", "SubZone"}, {"SiteSeries", "SiteSeries"},
	{"TransDistrib", "TransDistrib"}, {"RealmClass", "RealmClass"}, {"MapUnit", "MapUnit"},
	{"MoistureRegime", "MoistureRegime"}, {"NutrientRegime", "NutrientRegime"},
	{"SuccessionalStatus", "SuccessionalStatus"}, {"StructuralStage", "StructuralStage"},
	{"StructuralStageMod", "StructuralStageMod"}, {"StandAge", "StandAge"}, {"Elevation", "Elevation"},
	{"SlopeGradient", "SlopeGradient"}, {"Aspect", "Aspect"}, {"MesoSlopePosition", "MesoSlopePosition"},
	{"SurfaceShape", "SurfaceShape"}, {"SurfaceTopographyType", "SurfaceTopographyType"},
	{"SurfaceTopographySize", "SurfaceTopographySize"}, {"WaterSource", "WaterSource"}, {"Photo", "Photo"},
	{"Exposure1", "Exposure1"}, {"Exposure2", "Exposure2"}, {"SiteDisturbance1", "SiteDisturbance1"},
	{"SiteDisturbance2", "SiteDisturbance2"}, {"SiteDisturbance3", "SiteDisturbance3"},
	{"SubstrateDecWood", "SubstrateDecWood"}, {"SubstrateBedRock", "SubstrateBedRock"},
	{"SubstrateRocks", "SubstrateRocks"}, {"SubstrateMineralSoil", "SubstrateMineralSoil"},
	{"SubstrateOrganicMatter", "SubstrateOrganicMatter"}, {"SubstrateWater", "SubstrateWater"},
	{"SiteNotes", "SiteNotes"}, {"SoilSurveyor", "SoilSurveyor"}, {"BedrockGeology1", "BedrockGeology1"},
	{"BedrockGeology2", "BedrockGeology2"}, {"BedrockGeology3", "BedrockGeology3"},
	{"CoarseFragLith1", "CoarseFragLith1"}, {"CoarseFragLith2", "CoarseFragLith2"},
	{"CoarseFragLith3", "CoarseFragLith3"}, {"TerrainTextureSurf", "TerrainTextureSurf"},
	{"SurficialMaterialSurf", "SurficialMaterialSurf"}, {"SurfaceExpSurf", "SurfaceExpSurf"},
	{"GeoMorProSurf", "GeoMorProSurf"}, {"TerrainTextureSubSurf", "TerrainTextureSubSurf"},
	{"SurficialMaterialSubSurf", "SurficialMaterialSubSurf"}, {"SurfaceExpSubSurf", "SurfaceExpSubSurf"},
	{"GeoMorProSubSurf", "GeoMorProSubSurf"}, {"FloodingRegimeFreq", "FloodingRegimeFreq"},
	{"MoistureRegimeSub", "MoistureRegimeSub"}, {"FloodingRegimeDur", "FloodingRegimeDur"},
	{"SoilDrainage", "SoilDrainage"}, {"SeepageDepth", "SeepageDepth"},
	{"RootRestrictingType", "RootRestrictingType"}, {"RootRestrictingDepth", "RootRestrictingDepth"},
	{"RootZoneParticleSize", "RootZoneParticleSize"}, {"RootingDepth", "RootingDepth"},
	{"SoilClassSubGroup", "SoilClassSubGroup"}, {"SoilClassGroup", "SoilClassGroup"},
	{"HumusForm", "HumusForm"}, {"HumusFormPhase", "HumusFormPhase"},
	{"pHMethodCodeMineral", "pHMethodCodeMineral"}, {"pHMethodCodeOrganic", "pHMethodCodeOrganic"},
	{"SoilNotes", "SoilNotes"}, {"VegSurveyor", "VegSurveyor"}, {"StrataCoverTree", "StrataCoverTree"},
	{"StrataCoverShrub", "StrataCoverShrub"}, {"StrataCoverHerb", "StrataCoverHerb"},
	{"StrataCoverMoss", "StrataCoverMoss"}, {"VegNotes", "VegNotes"},
	{"HydroGeoSystem", "HydroGeoSystem"}, {"HydroGeoSubSystem", "HydroGeoSubSystem"},
	{"SpeciesListComplete", "SpeciesListComplete"}, {"Temporary", "Temporary"}, {"Flag", "Flag"},
}

// vp06AdminFromEnvMapping maps VP06 _Env columns onto VP08 _Admin, including
// USysConvE.Date -> _Admin.StartDate per V7mdlImportVProVer06.txt:47-49.
var vp06AdminFromEnvMapping = [][2]string{
	{"Plot", "PlotNumber"}, {"StartDate", "Date"},
	{"SitePlotQuality", "SitePlotQuality"}, {"VegPlotQuality", "VegPlotQuality"},
	{"SoilPlotQuality", "SoilPlotQuality"}, {"UpdatedFromCards", "UpdatedFromCards"},
	{"EnteredBy", "EnteredBy"}, {"UserSiteUnit", "UserSiteUnit"}, {"BECSiteUnit", "BECSiteUnit"},
	{"SiteUnitShortName", "SiteUnitShortName"}, {"SiteUnitLongName", "SiteUnitLongName"},
	{"OfficeNotes", "OfficeNotes"}, {"HumusThickness", "HumusThickness"},
}

func accessColumnUTF16Limit(targetTable, colName string) int {
	upperTable := strings.ToUpper(targetTable)
	switch strings.ToLower(colName) {
	case "plotnumber", "plot":
		return 7
	case "species":
		if strings.HasSuffix(upperTable, "_VEG") {
			return 8
		}
	case "horizon":
		if strings.HasSuffix(upperTable, "_HUMUS") || strings.HasSuffix(upperTable, "_MINERAL") {
			return 8
		}
	case "texture":
		if strings.HasSuffix(upperTable, "_MINERAL") {
			return 4
		}
	case "colour":
		if strings.HasSuffix(upperTable, "_MINERAL") {
			return 14
		}
	}
	return 0
}

var vp05EnvMapping = [][2]string{
	{"PlotNumber", "PlotNumber"}, {"FieldNumber", "SiteNumber"}, {"ProjectID", "ProjectName"},
	{"FSRegionDistrict", "Region"}, {"Date", "Date"},
	{"SiteSurveyor", "SiteSurveyor"}, {"PlotRepresenting", "PlotRepresenting"},
	{"Location", "Location"}, {"Ecosection", "Ecosection"}, {"NtsMapSheet", "NtsMapSheet"},
	{"UTMZone", "UTMZone"}, {"UTMEasting", "UTMEasting"}, {"UTMNorthing", "UTMNorthing"},
	{"LocationAccuracy", "LocationAccuracy"}, {"AirPhotoNum", "AirPhotoNum"},
	{"XCoord", "XCoord"}, {"YCoord", "YCoord"}, {"Zone", "Zone"}, {"SubZone", "SubZone"},
	{"SiteSeries", "SiteSeries"}, {"TransDistrib", "TransDistrib"}, {"RealmClass", "RealmClass"},
	{"MapUnit", "MapUnit"}, {"MoistureRegime", "MoistureRegime"}, {"NutrientRegime", "NutrientRegime"},
	{"SuccessionalStatus", "SuccessionalStatus"}, {"StructuralStage", "StructuralStage"},
	{"StructuralStageMod", "StructuralStageMod"}, {"StandAge", "StandAge"}, {"Elevation", "Elevation"},
	{"SlopeGradient", "SlopeGradient"}, {"Aspect", "Aspect"}, {"MesoSlopePosition", "MesoSlopePosition"},
	{"SurfaceShape", "SurfaceTopography"}, {"WaterSource", "WaterSource"},
	{"Exposure1", "Exposure1"}, {"Exposure2", "Exposure2"},
	{"SiteDisturbance1", "SiteDisturbance1"}, {"SiteDisturbance2", "SiteDisturbance2"},
	{"SubstrateDecWood", "SubstrateDecWood"}, {"SubstrateBedRock", "SubstrateBedRock"},
	{"SubstrateRocks", "SubstrateRocks"}, {"SubstrateMineralSoil", "SubstrateMineralSoil"},
	{"SubstrateOrganicMatter", "SubstrateOrganicMatter"}, {"SubstrateWater", "SubstrateWater"},
	{"SurfaceTopographyType", "SurfaceTopographyType"}, {"SiteNotes", "SiteNotes"},
	{"SoilSurveyor", "SoilSurveyor"}, {"BedrockGeology1", "BedrockGeology"},
	{"CoarseFragLith1", "CoarseFragLith"}, {"TerrainTextureSurf", "TerrainTextureSurf"},
	{"SurficialMaterialSurf", "SurficialMaterialSurf"}, {"SurfaceExpSurf", "SurfaceExpSurf"},
	{"GeoMorProSurf", "GeoMorProSurf"}, {"TerrainTextureSubSurf", "TerrainTextureSubSurf"},
	{"SurficialMaterialSubSurf", "SurficialMaterialSubSurf"}, {"SurfaceExpSubSurf", "SurfaceExpSubSurf"},
	{"GeoMorProSubSurf", "GeoMorProSubSurf"}, {"FloodingRegimeFreq", "FloodingRegimeFreq"},
	{"MoistureRegimeSub", "MoistureRegimeSub"}, {"FloodingRegimeDur", "FloodingRegimeDur"},
	{"SurfaceTopographySize", "SurfaceTopographySize"}, {"SoilDrainage", "SoilDrainage"},
	{"SeepageDepth", "SeepageDepth"}, {"RootRestrictingType", "RootRestrictingType"},
	{"RootRestrictingDepth", "RootRestrictingDepth"}, {"RootZoneParticleSize", "RootZoneParticleSize"},
	{"RootingDepth", "RootingDepth"}, {"SoilClassSubGroup", "SoilClassSubGroup"},
	{"SoilClassGroup", "SoilClassGroup"}, {"HumusForm", "HumusForm"},
	{"HumusFormPhase", "HumusFormPhase"},
	{"pHMethodCodeMineral", "pHMethodCodeMineral"}, {"pHMethodCodeOrganic", "pHMethodCodeOrganic"},
	{"SoilNotes", "SoilNotes"}, {"VegSurveyor", "VegSurveyor"},
	{"StrataCoverTree", "StrataCoverTree"}, {"StrataCoverShrub", "StrataCoverShrub"},
	{"StrataCoverHerb", "StrataCoverHerb"}, {"StrataCoverMoss", "StrataCoverMoss"},
	{"VegNotes", "VegNotes"}, {"Photo", "PhotoRollNum"},
	{"HydroGeoSystem", "HydroGeoSystem"}, {"HydroGeoSubSystem", "HydroGeoSubSystem"},
	{"Flag", "Flag"},
}

var vp05AdminFromEnvMapping = [][2]string{
	{"Plot", "PlotNumber"},
	{"SitePlotQuality", "PlotQuality"}, {"UserSiteUnit", "AssignedSiteUnit"},
	{"SiteUnitShortName", "SiteUnitShortName"}, {"SiteUnitLongName", "SiteUnitLongName"},
	{"HumusThickness", "HumusThickness"},
}

var legacyAuditColumns = []string{
	"Project", "User", "PlotNumber", "Table", "EditField", "EditWhen",
	"BeforeEdit", "AfterEdit", "Restore", "Flag", "ID",
}

var legacyHumusColumns = []string{
	"PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HumusStructureDegree",
	"HumusStructureKind", "MycelAbundance", "FecalAbundance", "RootsAbundance",
	"RootsSize", "vonPost", "HumusFormpH", "Consistence", "Character", "Fauna",
	"Comment", "Flag", "ID",
}

var legacyMineralColumns = []string{
	"PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "PitDepthLimit", "Colour",
	"ASP", "Texture", "PercentCoarseFragsGravel", "PercentCoarseFragsCobbles",
	"PercentCoarseFragsStones", "PercentCoarseFragsTotal", "PercentCoarseFragsShape",
	"RootsAbundance", "RootsSize", "MineralStructureClass", "MineralStructureKind",
	"MineralFormpH", "MottlesAbundance", "MottlesSize", "MottlesContrast",
	"ClayFilmsFreq", "ClayFilmThickness", "Effervescence", "Porosity",
	"Comments", "Flag", "ID",
}

var legacyOtherColumns = []string{
	"PlotNumber", "DataName", "DataItem", "UserItem1", "UserItem2", "UserItem3",
	"UserFlag1", "UserFlag2", "UserFlag3", "Flag", "ID",
}

var legacyVegColumns = []string{
	"PlotNumber", "Species", "Cover1", "Height1", "Cover2", "Height2", "Cover3",
	"Height3", "Cover4", "Height4", "Cover5", "Height5", "Cover6", "Height6",
	"Cover7", "Cover8", "Cover9", "Cover10", "TotalA", "TotalB", "Collected",
	"Flag", "ID",
}

func convertLongLatToDeg(degVal, minVal, secVal any) any {
	deg, ok := toFloat64(degVal)
	if !ok {
		return nil
	}
	minutes, _ := toFloat64(minVal)
	seconds, _ := toFloat64(secVal)
	return deg + ((minutes + (seconds / 60.0)) / 60.0)
}

func toFloat64(value any) (float64, bool) {
	switch v := value.(type) {
	case float64:
		return v, true
	case int64:
		return float64(v), true
	default:
		return 0, false
	}
}

const AccessImportProgressEvent = "vpro:access-import-progress"

type AccessImportProgress struct {
	ContextID          string `json:"contextId"`
	Operation          string `json:"operation"` // "inspect" | "import"
	Phase              string `json:"phase"`     // "starting" | "inspecting" | "streaming" | "finalizing"
	SourceTable        string `json:"sourceTable,omitempty"`
	TargetTable        string `json:"targetTable,omitempty"`
	TableIndex         int    `json:"tableIndex,omitempty"`
	TableRowsProcessed int    `json:"tableRowsProcessed"`
	TableRowsImported  int    `json:"tableRowsImported"`
	TotalRowsProcessed int    `json:"totalRowsProcessed"`
	Message            string `json:"message"`
}

type accessImportProgressCtxKey struct{}

type accessImportProgressTracker struct {
	mu            sync.Mutex
	contextID     string
	operation     string
	tableIndex    int
	completedRows int
	lastEmit      time.Time
	emit          func(AccessImportProgress)
}

func WithAccessImportProgress(ctx context.Context, contextID, operation string, emit func(AccessImportProgress)) context.Context {
	if ctx == nil || emit == nil {
		return ctx
	}
	return context.WithValue(ctx, accessImportProgressCtxKey{}, &accessImportProgressTracker{
		contextID: contextID,
		operation: operation,
		emit:      emit,
	})
}

func accessImportProgressFromContext(ctx context.Context) *accessImportProgressTracker {
	if ctx == nil {
		return nil
	}
	t, _ := ctx.Value(accessImportProgressCtxKey{}).(*accessImportProgressTracker)
	return t
}

func (t *accessImportProgressTracker) emitStage(phase, message string) {
	if t == nil || t.emit == nil {
		return
	}
	t.mu.Lock()
	ev := AccessImportProgress{
		ContextID:          t.contextID,
		Operation:          t.operation,
		Phase:              phase,
		TableIndex:         t.tableIndex,
		TotalRowsProcessed: t.completedRows,
		Message:            message,
	}
	t.lastEmit = time.Now()
	t.mu.Unlock()
	t.emit(ev)
}

func (t *accessImportProgressTracker) beginTable(sourceTable, targetTable string) {
	if t == nil || t.emit == nil {
		return
	}
	t.mu.Lock()
	t.tableIndex++
	phase := "streaming"
	verb := "Importing"
	if t.operation == "inspect" {
		phase = "inspecting"
		verb = "Scanning"
	}
	ev := AccessImportProgress{
		ContextID:          t.contextID,
		Operation:          t.operation,
		Phase:              phase,
		SourceTable:        sourceTable,
		TargetTable:        targetTable,
		TableIndex:         t.tableIndex,
		TableRowsProcessed: 0,
		TableRowsImported:  0,
		TotalRowsProcessed: t.completedRows,
		Message:            fmt.Sprintf("%s %s…", verb, sourceTable),
	}
	t.lastEmit = time.Now()
	t.mu.Unlock()
	t.emit(ev)
}

func (t *accessImportProgressTracker) updateTableRows(sourceTable, targetTable string, rowsProcessed, rowsImported int, force bool) {
	if t == nil || t.emit == nil {
		return
	}
	now := time.Now()
	t.mu.Lock()
	if !force && !t.lastEmit.IsZero() && now.Sub(t.lastEmit) < 100*time.Millisecond {
		t.mu.Unlock()
		return
	}
	phase := "streaming"
	verb := "Importing"
	if t.operation == "inspect" {
		phase = "inspecting"
		verb = "Scanning"
	}
	ev := AccessImportProgress{
		ContextID:          t.contextID,
		Operation:          t.operation,
		Phase:              phase,
		SourceTable:        sourceTable,
		TargetTable:        targetTable,
		TableIndex:         t.tableIndex,
		TableRowsProcessed: rowsProcessed,
		TableRowsImported:  rowsImported,
		TotalRowsProcessed: t.completedRows + rowsProcessed,
		Message:            fmt.Sprintf("%s %s…", verb, sourceTable),
	}
	t.lastEmit = now
	t.mu.Unlock()
	t.emit(ev)
}

func (t *accessImportProgressTracker) finishTable(sourceTable, targetTable string, rowsProcessed, rowsImported int) {
	if t == nil || t.emit == nil {
		return
	}
	t.mu.Lock()
	t.completedRows += rowsProcessed
	phase := "streaming"
	verb := "Imported"
	if t.operation == "inspect" {
		phase = "inspecting"
		verb = "Scanned"
	}
	ev := AccessImportProgress{
		ContextID:          t.contextID,
		Operation:          t.operation,
		Phase:              phase,
		SourceTable:        sourceTable,
		TargetTable:        targetTable,
		TableIndex:         t.tableIndex,
		TableRowsProcessed: rowsProcessed,
		TableRowsImported:  rowsImported,
		TotalRowsProcessed: t.completedRows,
		Message:            fmt.Sprintf("%s %s", verb, sourceTable),
	}
	t.lastEmit = time.Now()
	t.mu.Unlock()
	t.emit(ev)
}

func formatAccessReaderError(label string, err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	base := filepath.Base(label)
	if base == "" || base == "." {
		base = label
	}
	msg := err.Error()
	switch {
	case errors.Is(err, os.ErrNotExist):
		return fmt.Errorf("Access file %q was not found. Check the file path and try again", label)
	case errors.Is(err, os.ErrPermission):
		return fmt.Errorf("Access file %q could not be opened due to file permissions", label)
	case strings.Contains(msg, "Access source read error"),
		strings.Contains(msg, "unsupported or unreadable file"),
		strings.Contains(msg, "cannot read Access catalog"),
		strings.Contains(msg, "cannot reopen Access database"):
		return fmt.Errorf("Access file %q could not be read. It may be incomplete, damaged, or in an unsupported format", base)
	case strings.Contains(msg, "unsupported Access character encoding"),
		strings.Contains(msg, "invalid, incomplete, or oversized Access text encoding"):
		return fmt.Errorf("Access file %q contains damaged or unsupported text encoding", base)
	case strings.Contains(msg, "invalid Access source row metadata"),
		strings.Contains(msg, "unsupported or malformed Access property sequence"),
		strings.Contains(msg, "unsupported, incomplete, or malformed Access native column schema"),
		strings.Contains(msg, "incomplete Access native column schema"):
		return fmt.Errorf("Access file %q has a damaged or incomplete table structure and could not be read", base)
	default:
		return err
	}
}

func streamFileSHA256(path string) (string, error) {
	return streamFileSHA256Context(context.Background(), path)
}

func streamFileSHA256Context(ctx context.Context, path string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	buf := make([]byte, 1<<20)
	for {
		if err := ctx.Err(); err != nil {
			return "", err
		}
		n, rErr := f.Read(buf)
		if n > 0 {
			_, _ = h.Write(buf[:n])
		}
		if rErr != nil {
			if errors.Is(rErr, io.EOF) {
				break
			}
			return "", rErr
		}
	}
	return hex.EncodeToString(h.Sum(nil)), ctx.Err()
}

func resolveAccessSourcePath(requested string) (string, string, error) {
	return resolveAccessSourcePathContext(context.Background(), requested)
}

func resolveAccessSourcePathContext(ctx context.Context, requested string) (string, string, error) {
	if requested == "" || !utf8.ValidString(requested) || strings.ContainsRune(requested, 0) || !filepath.IsAbs(requested) {
		return "", "", errors.New("Access database path must be an explicit absolute path")
	}
	ext := strings.ToLower(filepath.Ext(requested))
	if ext != ".mdb" && ext != ".accdb" {
		return "", "", errors.New("Access database path must end in .mdb or .accdb")
	}
	cleaned := filepath.Clean(requested)
	info, err := os.Stat(cleaned)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", "", fmt.Errorf("Access file %q was not found. Check the file path and try again", cleaned)
		}
		if errors.Is(err, os.ErrPermission) {
			return "", "", fmt.Errorf("Access file %q could not be opened due to file permissions", cleaned)
		}
		return "", "", fmt.Errorf("Access file %q could not be accessed", cleaned)
	}
	if info.IsDir() || !info.Mode().IsRegular() {
		return "", "", fmt.Errorf("Access path %q is a folder, not an Access (.mdb or .accdb) file", cleaned)
	}
	resolved, err := filepath.EvalSymlinks(cleaned)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", "", fmt.Errorf("Access file %q was not found. Check the file path and try again", cleaned)
		}
		if errors.Is(err, os.ErrPermission) {
			return "", "", fmt.Errorf("Access file %q could not be opened due to file permissions", cleaned)
		}
		return "", "", fmt.Errorf("Access file %q could not be accessed", cleaned)
	}
	digest, err := streamFileSHA256Context(ctx, resolved)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return "", "", err
		}
		if errors.Is(err, os.ErrPermission) {
			return "", "", fmt.Errorf("Access file %q could not be read due to file permissions", resolved)
		}
		return "", "", fmt.Errorf("Access file %q could not be read", filepath.Base(resolved))
	}
	return resolved, digest, nil
}

func InspectAccessDatabase(s *vprocore.ContextService, ctx context.Context, contextID, sourcePath string) (AccessDatabaseInspection, error) {
	var projectsDir string
	if _, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		projectsDir = filepath.Join(plots.Projects.Root, "projects")
		return struct{}{}, nil
	}); err != nil {
		return AccessDatabaseInspection{}, err
	}
	tracker := accessImportProgressFromContext(ctx)
	tracker.emitStage("starting", "Verifying Access file…")
	resolved, digest, err := resolveAccessSourcePathContext(ctx, sourcePath)
	if err != nil {
		return AccessDatabaseInspection{}, err
	}
	db, err := accessreader.Open(resolved)
	if err != nil {
		return AccessDatabaseInspection{}, formatAccessReaderError(resolved, err)
	}
	tables, err := db.Tables()
	if err != nil {
		return AccessDatabaseInspection{}, formatAccessReaderError(resolved, err)
	}
	byLower := make(map[string]accessreader.Table, len(tables))
	var optionalSUs []string
	for _, tbl := range tables {
		if tbl.Linked {
			continue
		}
		byLower[strings.ToLower(tbl.Name)] = tbl
		if len(tbl.Name) > 3 && strings.EqualFold(tbl.Name[len(tbl.Name)-3:], "_SU") &&
			!strings.HasPrefix(strings.ToUpper(tbl.Name), "USYS") {
			prefix := tbl.Name[:len(tbl.Name)-3]
			if vprocore.ProjectNamePattern.MatchString(prefix) {
				optionalSUs = append(optionalSUs, prefix)
			}
		}
	}
	slices.Sort(optionalSUs)

	var candidates []AccessProjectCandidate
	for _, tbl := range tables {
		if err := ctx.Err(); err != nil {
			return AccessDatabaseInspection{}, err
		}
		if tbl.Linked || len(tbl.Name) <= 4 || !strings.EqualFold(tbl.Name[len(tbl.Name)-4:], "_Env") {
			continue
		}
		if strings.EqualFold(tbl.Name, "Filtered_Env") || strings.EqualFold(tbl.Name, "USysEnv") {
			continue
		}
		prefix := tbl.Name[:len(tbl.Name)-4]
		version := strings.TrimSpace(tbl.Description)
		if version == "" {
			version = "Unknown"
		}
		suggested := sanitizeProjectSuggestion(prefix)
		destPath := filepath.Join(projectsDir, suggested+".db")
		for idx := 2; ; idx++ {
			if _, statErr := os.Stat(destPath); errors.Is(statErr, os.ErrNotExist) {
				break
			}
			suffix := fmt.Sprintf("_%d", idx)
			base := suggested
			if len(base)+len(suffix) > 31 {
				base = base[:31-len(suffix)]
			}
			suggested = base + suffix
			destPath = filepath.Join(projectsDir, suggested+".db")
		}

		candidate := AccessProjectCandidate{
			SourceProject:     prefix,
			SuggestedTarget:   suggested,
			SuggestedDestPath: destPath,
			SourceVersion:     version,
			OptionalSUs:       optionalSUs,
		}
		var requiredSuffixes []string
		switch version {
		case "VP08":
			candidate.ConversionMode = "Direct VP08 8-table import (lossless VPro 19/64 schema)"
			requiredSuffixes = []string{"Env", "Veg", "Other", "Humus", "Mineral", "Audit", "Metadata", "Admin"}
		case "VP07":
			candidate.ConversionMode = "Autoconvert VP07 (VPro 15) -> VP08 (ImportVPro07 SV_* rename + Admin split)"
			requiredSuffixes = []string{"Env", "Veg", "Other", "Humus", "Mineral", "Audit", "Metadata"}
		case "VP06":
			candidate.ConversionMode = "Autoconvert VP06 (VPro 07/13) -> VP08 (ImportVPro06 Env/Admin split)"
			requiredSuffixes = []string{"Env", "Veg", "Other", "Humus", "Mineral", "Audit"}
		case "VP05":
			candidate.ConversionMode = "Autoconvert VP05 (VPro XP/03) -> VP08 (ImportVPro05 DMS->Decimal Deg + column mapping + Admin synthesis)"
			requiredSuffixes = []string{"Env", "Veg", "Other", "Humus", "Mineral", "Audit"}
		default:
			candidate.ConversionMode = fmt.Sprintf("Unsupported legacy version %q (supported: VP05, VP06, VP07, VP08)", version)
			candidate.Compatible = false
			candidate.StatusMessage = candidate.ConversionMode
			candidates = append(candidates, candidate)
			continue
		}

		allPresent := true
		for _, suffix := range []string{"Env", "Veg", "Other", "Humus", "Mineral", "Audit", "Metadata", "Admin"} {
			srcTbl, exists := byLower[strings.ToLower(prefix+"_"+suffix)]
			required := slices.Contains(requiredSuffixes, suffix)
			summary := AccessImportTableSummary{
				Suffix:      suffix,
				SourceTable: prefix + "_" + suffix,
				Present:     exists,
			}
			if exists {
				summary.SourceTable = srcTbl.Name
				summary.Description = srcTbl.Description
				reader, readErr := db.Scan(srcTbl.Name)
				if readErr != nil {
					allPresent = false
					candidate.StatusMessage = fmt.Sprintf("Could not open %s: %v", srcTbl.Name, formatAccessReaderError(resolved, readErr))
				} else {
					tracker.beginTable(srcTbl.Name, "")
					reader.EnableRowQuarantine()
					rowCnt := 0
					for reader.Next() {
						rowCnt++
						if rowCnt&1023 == 0 {
							if err := ctx.Err(); err != nil {
								_ = reader.Close()
								return AccessDatabaseInspection{}, err
							}
						}
						if rowCnt&4095 == 0 {
							tracker.updateTableRows(srcTbl.Name, "", rowCnt, rowCnt, false)
						}
					}
					iterErr := reader.Err()
					colCnt := len(reader.Columns)
					_ = reader.Close()
					tracker.finishTable(srcTbl.Name, "", rowCnt, rowCnt)
					if iterErr != nil {
						allPresent = false
						candidate.StatusMessage = fmt.Sprintf("Could not read %s: %v", srcTbl.Name, formatAccessReaderError(resolved, iterErr))
					} else {
						summary.ColumnCount = colCnt
						summary.RowCount = rowCnt
						if suffix == "Env" {
							candidate.PlotCount = rowCnt
						}
					}
				}
				if version == "VP08" {
					summary.Action = "Copy rows directly"
				} else if suffix == "Env" {
					summary.Action = fmt.Sprintf("Convert %s Env -> VP08 Env + Admin", version)
				} else if suffix == "Metadata" && version == "VP07" {
					summary.Action = "Create empty VP08 Metadata table (ImportVPro07 contract)"
				} else {
					summary.Action = fmt.Sprintf("Map %s %s columns -> VP08 %s", version, suffix, suffix)
				}
			} else if !required {
				if suffix == "Admin" {
					summary.Action = fmt.Sprintf("Synthesize VP08 Admin from %s_Env (%d plots)", prefix, candidate.PlotCount)
				} else if suffix == "Metadata" {
					summary.Action = "Create empty VP08 Metadata table"
				}
			} else {
				allPresent = false
				summary.Action = "Missing required source table"
				if candidate.StatusMessage == "" {
					candidate.StatusMessage = fmt.Sprintf("Missing required table %s_%s", prefix, suffix)
				}
			}
			candidate.Tables = append(candidate.Tables, summary)
		}
		candidate.Compatible = allPresent && candidate.StatusMessage == ""
		if candidate.Compatible {
			candidate.StatusMessage = fmt.Sprintf("Ready to import (%d plots)", candidate.PlotCount)
		}
		candidates = append(candidates, candidate)
	}
	slices.SortFunc(candidates, func(a, b AccessProjectCandidate) int {
		return strings.Compare(a.SourceProject, b.SourceProject)
	})
	return AccessDatabaseInspection{
		SourcePath:   resolved,
		SourceSHA256: digest,
		Projects:     candidates,
	}, nil
}
