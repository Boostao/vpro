CREATE TABLE "USysSortingTable" (
  "Group" TEXT,
  "GroupShortName" TEXT,
  "GroupLongName" TEXT,
  "Zone" TEXT,
  "SubZone" TEXT,
  "PlotVariant" TEXT,
  "Phase" TEXT,
  "SiteSeries" TEXT,
  "SeralCode" TEXT,
  "RegionCode" TEXT,
  "SiteType" TEXT,
  "NumberOfPlots" DOUBLE,
  "PlotNumber" TEXT
);

CREATE INDEX "idx_USysSortingTable_NumberOfPlots" ON "USysSortingTable" ("NumberOfPlots");
CREATE INDEX "idx_USysSortingTable_RegionCode" ON "USysSortingTable" ("RegionCode");
CREATE INDEX "idx_USysSortingTable_SeralCode" ON "USysSortingTable" ("SeralCode");
