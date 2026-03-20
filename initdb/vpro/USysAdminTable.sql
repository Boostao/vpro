CREATE TABLE "USysAdminTable" (
  "Plot" VARCHAR NOT NULL, -- unique plot number (7 char)
  "StartDate" SMALLINT, -- Added for two-field primary key in metadata
  "PlotType" VARCHAR, -- 1 ground, 2 visual, 3 note, 4 FS882, 5 other
  "PlotSize" REAL, -- added for VPro 15, metres squared
  "ProvinceStateTerritory" VARCHAR,
  "SitePlotQuality" VARCHAR, -- defined plot quality code
  "VegPlotQuality" VARCHAR, -- defined plot quality code
  "SoilPlotQuality" VARCHAR, -- defined plot quality code
  "UpdatedFromCards" BOOLEAN, -- data entry and check complete? (changed name form Complete?) changed field type
  "EnteredBy" VARCHAR, -- person entering or updating record from cards (added field)
  "UserSiteUnit" VARCHAR, -- Updateable from current site unit table
  "BECSiteUnit" VARCHAR, -- Updateable from corporate master siteunit table only (restricted access)
  "SiteUnitShortName" VARCHAR, -- From user site unit table (should be carried forward when importing exporting)
  "SiteUnitLongName" VARCHAR, -- From user site unit table
  "OfficeNotes" TEXT,
  "HumusThickness" REAL, -- calculated from humus horizons
  "GIS_BGC" VARCHAR, -- Will - Dec. 8, 2017
  "GIS_BGC_VER" SMALLINT, -- Will - Dec. 8, 2017
  "BEC_Use" VARCHAR, -- Will - Oct. 16, 2019
  "StrataCoverTotal" REAL
);

CREATE UNIQUE INDEX "uidx_USysAdminTable_Plot" ON "USysAdminTable" ("Plot");
