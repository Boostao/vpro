CREATE TABLE "USysMetadataTable" (
  "ProjectID" VARCHAR, -- Links to VPRO project id field
  "StartDate" SMALLINT DEFAULT NULL, -- Added for two-field primary key in metadata
  "EndDate" SMALLINT,
  "ProjectTitle" VARCHAR,
  "CoordinatingAgency" VARCHAR,
  "ProponentFunder" VARCHAR, -- Funding agency/University
  "FieldCompanyAgency" VARCHAR,
  "FieldLeader" VARCHAR,
  "FieldDataCollectionTeam" VARCHAR,
  "ProjectPurpose" VARCHAR, -- Purpose of project
  "GeographicStudyArea" VARCHAR, -- Geographic area of study
  "GeographicStudyRegion" VARCHAR,
  "NumberOfFS882Plots" INTEGER,
  "NumberOfSiteVisits" SMALLINT,
  "ProjectType" VARCHAR, -- BEC, TEM, SIBEC, Other
  "ProjectTypeOther" VARCHAR,
  "EcosysCollectionStandard" VARCHAR, -- 1 = DIEF1980, 2 = DEIF1990, 3 = DTE1998, 4 = Other
  "EcosysCollectionStandardOther" VARCHAR,
  "VegCoverMethod" VARCHAR, -- 1 = Percent, 2 = Braun-Blanquet, 3 = Domin-Krajina, 4 = Other
  "VegCoverMethodOther" VARCHAR,
  "PlotMethod" VARCHAR, -- 1 = 20x20, 2 = Nested, 3 = 1x1, 4 = Transect, 5 = Frame
  "PlotMethodOther" VARCHAR,
  "MensurationMethod" VARCHAR, -- 1 = Fixed, 2 = Prism, 3 = Paired Prism, 4 = Other
  "MensurationMethodOther" VARCHAR,
  "ExtraVegFieldDescription" VARCHAR,
  "DataCustodian" VARCHAR,
  "StorageLocation" VARCHAR,
  "CollectedSite" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualitySite" VARCHAR,
  "CollectedVeg" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityVeg" VARCHAR,
  "CollectedSoil" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualitySoil" VARCHAR,
  "CollectedTerrain" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityTerrain" VARCHAR,
  "CollectedMens" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityMens" VARCHAR,
  "CollectedCWD" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityCWD" VARCHAR,
  "CollectedWildTree" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityWildTree" VARCHAR,
  "CollectedSoilChem" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualitySoilChem" VARCHAR,
  "CollectedWildlifeHabitatAssessment" SMALLINT, -- 1 = complete, 2 = partial, 3 = none
  "DataQualityWildlifeHabitatAssessment" VARCHAR,
  "CollectedCompleteOther" VARCHAR,
  "CollectedPartialOther" VARCHAR,
  "CollectedNoneOther" VARCHAR,
  "GeoRefMethod" VARCHAR, -- 1 = GPS, 2 = base correct, 3 = pre2000
  "GeoRefMethodOther" VARCHAR,
  "Datum" VARCHAR, -- 1 = NAD27, 2 = NAD83
  "DatumOther" VARCHAR,
  "CoordinateSystem" VARCHAR, -- 1 = UTM, 2 = dd.ddd, 3 = dd.mm.mmm, 4 = dd.mm.ss.s
  "CoordinateSystemOther" VARCHAR,
  "AllSpecs" VARCHAR,
  "TableOfLists" VARCHAR,
  "CoverA1Description" VARCHAR,
  "CoverA2Description" VARCHAR,
  "CoverA3Description" VARCHAR,
  "CoverADescription" VARCHAR,
  "CoverB1Description" VARCHAR,
  "CoverB2Description" VARCHAR,
  "CoverB2aDescription" VARCHAR,
  "CoverB2bDescription" VARCHAR,
  "CoverB2cDescription" VARCHAR,
  "CoverBDescription" VARCHAR,
  "CoverCDescription" VARCHAR,
  "CoverDDescription" VARCHAR,
  "Cover8Description" VARCHAR,
  "Cover9Description" VARCHAR,
  "Cover10Description" VARCHAR,
  "BAPID" INTEGER,
  "DateLastEdited" TIMESTAMP,
  "Notes" TEXT,
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysMetadataTable_BAPID" ON "USysMetadataTable" ("BAPID");
CREATE INDEX "idx_USysMetadataTable_NumberOfFS882Plots" ON "USysMetadataTable" ("NumberOfFS882Plots");
CREATE INDEX "idx_USysMetadataTable_NumberOfSiteVisits" ON "USysMetadataTable" ("NumberOfSiteVisits");
CREATE INDEX "idx_USysMetadataTable_ProjectID" ON "USysMetadataTable" ("ProjectID");
