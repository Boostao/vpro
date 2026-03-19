CREATE TABLE "USysProjectMetadata" (
  "ProjectID" TEXT, -- Links to VPRO project id field
  "ProjectTitle" TEXT,
  "DateLastEdited" TIMESTAMP,
  "LastEditedBy" TEXT,
  "CoordinatingAgency" TEXT,
  "ProponentFunder" TEXT, -- Funding agency/University
  "FieldCompanyAgency" TEXT,
  "FieldLeader" TEXT,
  "FieldDataCollectionTeam" TEXT,
  "ProjectPurpose" TEXT, -- Purpose of project
  "GeographicStudyArea" TEXT, -- Geographic area of study
  "GeographicStudyRegion" TEXT,
  "GeographicStudyDistrict" TEXT,
  "StartDate" TIMESTAMP,
  "EndDate" TIMESTAMP,
  "NumberOfFS882Plots" INTEGER,
  "NumberOfSiteVisits" INTEGER,
  "CollectedSite" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedVeg" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedSoil" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedTerrain" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedMens" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedCWD" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedWildTree" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedSoilChem" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedOther" INTEGER, -- 1 = complete, 2 = partial, 3 = none
  "CollectedCompleteOtherName" TEXT,
  "CollectedPartialOtherName" TEXT,
  "CollectedNoneOtherName" TEXT,
  "GeoRefMethod" INTEGER, -- 1 = GPS, 2 = base correct, 3 = pre2000
  "Map" INTEGER, -- 1 = 10K, 2 = 50K, 3 = 250K
  "Datum" INTEGER, -- 1 = NAD27, 2 = NAD83
  "CoordinateSystem" INTEGER, -- 1 = UTM, 2 = dd.ddd, 3 = dd.mm.mmm, 4 = dd.mm.ss.s
  "EcosysCollectionStandard" INTEGER, -- 1 = DIEF1980, 2 = DEIF1990, 3 = DTE1998, 4 = Other
  "EcosysCollectionStandardOtherName" TEXT,
  "VegCoverMethod" INTEGER, -- 1 = Percent, 2 = Braun-Blanquet, 3 = Domin-Krajina, 4 = Other
  "VegCoverMethodOtherName" TEXT,
  "MensurationMethod" INTEGER, -- 1 = Fixed, 2 = Prism, 3 = Paired Prism, 4 = Other
  "MensurationMethodOtherName" TEXT,
  "ExtraVegFieldDescription" TEXT,
  "PlotMethod" INTEGER, -- 1 = 20x20, 2 = Nested, 3 = 1x1, 4 = Transect, 5 = Frame
  "DataCustodian" TEXT,
  "StorageLocation" TEXT,
  "Notes" TEXT,
  "AllSpecs" TEXT,
  "TableOfLists" TEXT,
  "CoverA1Description" TEXT,
  "CoverA2Description" TEXT,
  "CoverA3Description" TEXT,
  "CoverADescription" TEXT,
  "CoverB1Description" TEXT,
  "CoverB2Description" TEXT,
  "CoverB2aDescription" TEXT,
  "CoverB2bDescription" TEXT,
  "CoverB2cDescription" TEXT,
  "CoverCDescription" TEXT,
  "CoverDDescription" TEXT,
  "Cover8Description" TEXT,
  "Cover9Description" TEXT,
  "Cover10Description" TEXT,
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysProjectMetadata_NumberOfFS882Plots" ON "USysProjectMetadata" ("NumberOfFS882Plots");
CREATE INDEX "idx_USysProjectMetadata_NumberOfSiteVisits" ON "USysProjectMetadata" ("NumberOfSiteVisits");
CREATE UNIQUE INDEX "uidx_USysProjectMetadata_ProjectID" ON "USysProjectMetadata" ("ProjectID");
