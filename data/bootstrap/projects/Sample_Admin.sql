-- Access table description: VP08
CREATE TABLE "Admin" (
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
  "StrataCoverTotal" REAL,
  FOREIGN KEY ("Plot") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE UNIQUE INDEX "uidx_Admin_PlotNumber" ON "Admin" ("Plot");

/*
Access metadata notes for Admin:
- Table Description: VP08
- Plot: Field Size=255; Required=Yes; AllowZeroLength=No.
- StartDate: ValidationRule=Between 1900 And 2500; ValidationText=Please enter a year between 1900 and 2500.
- Relationship: Plot -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("Plot") <= 255)
- CHECK(trim("Plot") <> '')
- CHECK("StartDate" BETWEEN 1900 AND 2500 OR "StartDate" IS NULL)
*/
