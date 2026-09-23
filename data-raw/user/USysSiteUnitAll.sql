-- Access table description: VP03
CREATE TABLE "USysSiteUnitAll" (
  "SiteUnit" TEXT,
  "GroupShortName" TEXT,
  "GroupLongName" TEXT,
  "Zone" TEXT,
  "Subzone" TEXT,
  "PlotVariant" TEXT,
  "Phase" TEXT,
  "SiteSeries" TEXT,
  "SeralCode" TEXT,
  "RegionCode" TEXT,
  "SiteType" TEXT,
  "Unique" INTEGER
);

CREATE UNIQUE INDEX "uidx_USysSiteUnitAll_Unique" ON "USysSiteUnitAll" ("Unique");
CREATE INDEX "idx_USysSiteUnitAll_GroupShortName" ON "USysSiteUnitAll" ("GroupShortName");
CREATE INDEX "idx_USysSiteUnitAll_SiteType" ON "USysSiteUnitAll" ("SiteType");
CREATE INDEX "idx_USysSiteUnitAll_SiteUnit" ON "USysSiteUnitAll" ("SiteUnit");
