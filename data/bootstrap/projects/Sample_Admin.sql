CREATE TABLE "Admin" (
  "Plot" VARCHAR NOT NULL,
  "StartDate" SMALLINT,
  "PlotType" VARCHAR,
  "PlotSize" REAL,
  "ProvinceStateTerritory" VARCHAR,
  "SitePlotQuality" VARCHAR,
  "VegPlotQuality" VARCHAR,
  "SoilPlotQuality" VARCHAR,
  "UpdatedFromCards" BOOLEAN,
  "EnteredBy" VARCHAR,
  "UserSiteUnit" VARCHAR,
  "BECSiteUnit" VARCHAR,
  "SiteUnitShortName" VARCHAR,
  "SiteUnitLongName" VARCHAR,
  "OfficeNotes" TEXT,
  "HumusThickness" REAL,
  "GIS_BGC" VARCHAR,
  "GIS_BGC_VER" SMALLINT,
  "BEC_Use" VARCHAR,
  "StrataCoverTotal" REAL
);

CREATE UNIQUE INDEX "uidx_Admin_PlotNumber" ON "Admin" ("Plot");
