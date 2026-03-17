CREATE TABLE "ProjectMetadata" (
  "ProjectID" TEXT PRIMARY KEY,
  "ProjectTitle" TEXT,
  "CoordinatingAgency" TEXT,
  "ProponentFunder" TEXT,
  "FieldCompanyAgency" TEXT,
  "FieldLeader" TEXT,
  "FieldDataCollectionTeam" TEXT,
  "ProjectPurpose" TEXT,
  "GeographicStudyArea" TEXT,
  "GeographicStudyRegion" TEXT,
  "GeographicStudyDistrict" TEXT,
  "StartDate" TIMESTAMP,
  "EndDate" TIMESTAMP,
  "NumberOfFS882Plots" INTEGER,
  "NumberOfSiteVisits" INTEGER,
  "CollectedSite" INTEGER,
  "CollectedVeg" INTEGER,
  "CollectedSoil" INTEGER,
  "CollectedTerrain" INTEGER,
  "CollectedMens" INTEGER,
  "CollectedCWD" INTEGER,
  "CollectedWildTree" INTEGER,
  "CollectedSoilChem" INTEGER,
  "CollectedOther" INTEGER,
  "CollectedCompleteOtherName" TEXT,
  "CollectedPartialOtherName" TEXT,
  "CollectedNoneOtherName" TEXT,
  "GeoRefMethod" INTEGER,
  "Map" INTEGER,
  "Datum" INTEGER,
  "CoordinateSystem" INTEGER,
  "EcosysCollectionStandard" INTEGER,
  "EcosysCollectionStandardOtherName" TEXT,
  "VegCoverMethod" INTEGER,
  "VegCoverMethodOtherName" TEXT,
  "MensurationMethod" INTEGER,
  "MensurationMethodOtherName" TEXT,
  "ExtraVegFieldDescription" TEXT,
  "PlotMethod" INTEGER,
  "DataCustodian" TEXT,
  "StorageLocation" TEXT,
  "Notes" TEXT
);

CREATE INDEX "idx_ProjectMetadata_NumberOfFS882Plots" ON "ProjectMetadata" ("NumberOfFS882Plots");
CREATE INDEX "idx_ProjectMetadata_NumberOfSiteVisits" ON "ProjectMetadata" ("NumberOfSiteVisits");

/*
Access metadata notes for ProjectMetadata:
- ProjectID is the Access primary key and links to the VPRO project id field.
- NumberOfFS882Plots and NumberOfSiteVisits are indexed with duplicates allowed in Access.
*/