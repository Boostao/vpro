-- Access table description: VP08
CREATE TABLE "Sample_Env" (
  "PlotNumber" VARCHAR NOT NULL, -- unique plot number (7 char)
  "FieldNumber" VARCHAR, -- field plot number (50 char)
  "ProjectID" VARCHAR, -- ID for project for link to project metadata table ( changed to 30 char)- name change
  "FSRegionDistrict" VARCHAR, -- forest region.district code (changed name)
  "Date" TIMESTAMP, -- date of data collection
  "SiteSurveyor" VARCHAR, -- full name of site surveyor
  "PlotRepresenting" VARCHAR, -- brief description of plot including dominant species, site, and soils conditions
  "Location" VARCHAR, -- description of plot location
  "Ecosection" VARCHAR, -- ecosection code
  "NtsMapSheet" VARCHAR, -- For all mapsheet formats 104P, 104P/16, 104P.023
  "Longitude" DOUBLE, -- Decimal Degrees
  "Latitude" DOUBLE, -- Decimal degrees
  "UTMZone" VARCHAR,
  "UTMEasting" REAL,
  "UTMNorthing" REAL,
  "LocationAccuracy" SMALLINT, -- In metres
  "AirPhotoNum" VARCHAR,
  "XCoord" REAL,
  "YCoord" REAL,
  "Zone" VARCHAR, -- Biogeoclimatic zone Linked to standards linst
  "SubZone" VARCHAR, -- Biogeoclimatic subzone/variant. Linked to standards linst
  "SiteSeries" VARCHAR,
  "SiteModifier1" VARCHAR, -- From GIF 2018 addition
  "SiteModifier2" VARCHAR, -- From GIF 2018 addition
  "TransDistrib" VARCHAR,
  "RealmClass" VARCHAR, -- Changed to 5 character
  "MapUnit" VARCHAR, -- Changed to 30
  "SnowCoverregime" VARCHAR, -- CHARS
  "MoistureRegime" VARCHAR, -- code
  "NutrientRegime" VARCHAR, -- code
  "SuccessionalStatus" VARCHAR, -- Code
  "StructuralStage" VARCHAR, -- Code
  "StructuralStageMod" VARCHAR, -- Code
  "StandAge" SMALLINT,
  "Elevation" SMALLINT,
  "SlopeGradient" REAL, -- In percent
  "Aspect" SMALLINT, -- In degrees (999 = no slope)
  "MesoSlopePosition" VARCHAR, -- Code
  "SurfaceShape" VARCHAR, -- Code (Change name from Surface topography)
  "SurfaceTopographyType" VARCHAR, -- code
  "SurfaceTopographySize" VARCHAR, -- code
  "WaterSource" VARCHAR, -- Code
  "Photo" VARCHAR, -- Link to photo file
  "Exposure1" VARCHAR, -- code
  "Exposure2" VARCHAR, -- code
  "SiteDisturbance1" VARCHAR, -- code
  "SiteDisturbance2" VARCHAR, -- code
  "SiteDisturbance3" VARCHAR, -- code
  "SubstrateDecWood" REAL,
  "SubstrateBedRock" REAL,
  "SubstrateRocks" REAL,
  "SubstrateMineralSoil" REAL,
  "SubstrateOrganicMatter" REAL,
  "SubstrateWater" REAL,
  "SiteNotes" TEXT,
  "SoilSurveyor" VARCHAR,
  "BedrockGeology1" VARCHAR, -- code
  "BedrockGeology2" VARCHAR, -- code
  "BedrockGeology3" VARCHAR, -- code
  "CoarseFragLith1" VARCHAR, -- code
  "CoarseFragLith2" VARCHAR, -- code
  "CoarseFragLith3" VARCHAR, -- code
  "TerrainTextureSurf" VARCHAR, -- code
  "SurficialMaterialSurf" VARCHAR, -- code
  "SurfaceExpSurf" VARCHAR, -- code
  "GeoMorProSurf" VARCHAR, -- code
  "TerrainTextureSubSurf" VARCHAR, -- code
  "SurficialMaterialSubSurf" VARCHAR, -- code
  "SurfaceExpSubSurf" VARCHAR, -- code
  "GeoMorProSubSurf" VARCHAR, -- code
  "FloodingRegimeFreq" VARCHAR, -- code
  "MoistureRegimeSub" VARCHAR, -- code
  "FloodingRegimeDur" VARCHAR, -- code
  "SoilDrainage" VARCHAR, -- code
  "SeepageDepth" SMALLINT,
  "RootRestrictingType" VARCHAR, -- code
  "RootRestrictingDepth" SMALLINT, -- code
  "RootZoneParticleSize" VARCHAR, -- code
  "RootingDepth" SMALLINT,
  "SoilClassSubGroup" VARCHAR, -- code
  "SoilClassGroup" VARCHAR, -- code
  "HumusForm" VARCHAR, -- code
  "HumusFormPhase" VARCHAR,
  "pHMethodCodeMineral" VARCHAR, -- code
  "pHMethodCodeOrganic" VARCHAR, -- code
  "SoilNotes" TEXT,
  "VegSurveyor" VARCHAR,
  "StrataCoverTree" REAL,
  "StrataCoverShrub" REAL,
  "StrataCoverHerb" REAL,
  "StrataCoverMoss" REAL,
  "VegNotes" TEXT,
  "HydroGeoSystem" VARCHAR, -- code
  "HydroGeoSubSystem" VARCHAR, -- code
  "SpeciesListComplete" BOOLEAN, -- partial or complete species list
  "Temporary" VARCHAR, -- For users
  "Flag" BOOLEAN,
  "SV_PolygonNumber" VARCHAR, -- from SIVI
  "SV_FloodPlain" BOOLEAN DEFAULT FALSE, -- from SIVI
  "SV_StandAgeEstMeas" VARCHAR, -- from SIVI
  "SV_StandHeight" REAL, -- from SIVI
  "SV_StandHeightEstMeas" VARCHAR, -- from SIVI
  "SV_CanopyComposition" VARCHAR, -- from SIVI
  "SV_SoilDepth" REAL, -- from SIVI
  "SV_RootZoneTexture" VARCHAR, -- from SIVI
  "SV_PercentCoarseFrags" REAL, -- from SIVI
  "SV_GleyingMottlingCM" REAL, -- from SIVI
  "SV_WaterTableCM" REAL, -- from SIVI
  "SV_FullCruiseCard" VARCHAR, -- from SIVI
  "SV_AhorizonType" VARCHAR, -- from SIVI
  "SV_AhorizonDepth" REAL, -- from SIVI
  "ActiveLayerDepth" REAL -- CHARS
);

CREATE INDEX "idx_Sample_Env_AirPhotoNum" ON "Sample_Env" ("AirPhotoNum");
CREATE UNIQUE INDEX "uidx_Sample_Env_PlotNumber" ON "Sample_Env" ("PlotNumber");
CREATE INDEX "idx_Sample_Env_ProjectID" ON "Sample_Env" ("ProjectID");

/*
Access metadata notes for Sample_Env:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- FieldNumber: Field Size=50; AllowZeroLength=No.
- ProjectID: Field Size=30; AllowZeroLength=No.
- SV_FloodPlain: Default=0 in Access.
- Access retained one unique index on PlotNumber; the duplicate generated unique index was removed.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("FieldNumber") <= 50)
- CHECK(length("ProjectID") <= 30)
- CHECK(length("Ecosection") <= 3)
- CHECK(length("NtsMapSheet") <= 8)
*/
