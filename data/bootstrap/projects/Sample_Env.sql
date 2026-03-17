-- Access table description: VP08
CREATE TABLE "Env" (
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
  "SiteModifier1" VARCHAR,
  "SiteModifier2" VARCHAR,
  "TransDistrib" VARCHAR,
  "RealmClass" VARCHAR,
  "MapUnit" VARCHAR,
  "SnowCoverregime" VARCHAR,
  "MoistureRegime" VARCHAR,
  "NutrientRegime" VARCHAR,
  "SuccessionalStatus" VARCHAR,
  "StructuralStage" VARCHAR,
  "StructuralStageMod" VARCHAR,
  "StandAge" SMALLINT,
  "Elevation" SMALLINT,
  "SlopeGradient" REAL, -- In percent
  "Aspect" SMALLINT, -- In degrees (999 = no slope)
  "MesoSlopePosition" VARCHAR,
  "SurfaceShape" VARCHAR,
  "SurfaceTopographyType" VARCHAR,
  "SurfaceTopographySize" VARCHAR,
  "WaterSource" VARCHAR,
  "Photo" VARCHAR, -- Link to photo file
  "Exposure1" VARCHAR,
  "Exposure2" VARCHAR,
  "SiteDisturbance1" VARCHAR,
  "SiteDisturbance2" VARCHAR,
  "SiteDisturbance3" VARCHAR,
  "SubstrateDecWood" REAL,
  "SubstrateBedRock" REAL,
  "SubstrateRocks" REAL,
  "SubstrateMineralSoil" REAL,
  "SubstrateOrganicMatter" REAL,
  "SubstrateWater" REAL,
  "SiteNotes" TEXT,
  "SoilSurveyor" VARCHAR,
  "BedrockGeology1" VARCHAR,
  "BedrockGeology2" VARCHAR,
  "BedrockGeology3" VARCHAR,
  "CoarseFragLith1" VARCHAR,
  "CoarseFragLith2" VARCHAR,
  "CoarseFragLith3" VARCHAR,
  "TerrainTextureSurf" VARCHAR,
  "SurficialMaterialSurf" VARCHAR,
  "SurfaceExpSurf" VARCHAR,
  "GeoMorProSurf" VARCHAR,
  "TerrainTextureSubSurf" VARCHAR,
  "SurficialMaterialSubSurf" VARCHAR,
  "SurfaceExpSubSurf" VARCHAR,
  "GeoMorProSubSurf" VARCHAR,
  "FloodingRegimeFreq" VARCHAR,
  "MoistureRegimeSub" VARCHAR,
  "FloodingRegimeDur" VARCHAR,
  "SoilDrainage" VARCHAR,
  "SeepageDepth" SMALLINT,
  "RootRestrictingType" VARCHAR,
  "RootRestrictingDepth" SMALLINT,
  "RootZoneParticleSize" VARCHAR,
  "RootingDepth" SMALLINT,
  "SoilClassSubGroup" VARCHAR,
  "SoilClassGroup" VARCHAR,
  "HumusForm" VARCHAR,
  "HumusFormPhase" VARCHAR,
  "pHMethodCodeMineral" VARCHAR,
  "pHMethodCodeOrganic" VARCHAR,
  "SoilNotes" TEXT,
  "VegSurveyor" VARCHAR,
  "StrataCoverTree" REAL,
  "StrataCoverShrub" REAL,
  "StrataCoverHerb" REAL,
  "StrataCoverMoss" REAL,
  "VegNotes" TEXT,
  "HydroGeoSystem" VARCHAR,
  "HydroGeoSubSystem" VARCHAR,
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

CREATE INDEX "idx_Env_AirPhotoNum" ON "Env" ("AirPhotoNum");
CREATE UNIQUE INDEX "uidx_Env_PlotNumber" ON "Env" ("PlotNumber");
CREATE INDEX "idx_Env_ProjectID" ON "Env" ("ProjectID");

/*
Access metadata notes for Env:
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
