CREATE TABLE "USysSiteSeriesNames" (
  "SiteSeries_ID" REAL,
  "SSCode" TEXT,
  "BGCName" TEXT,
  "BEC_Region" TEXT,
  "BGC_Zone" TEXT,
  "SubzVarPh" TEXT,
  "BGC_Subzone" TEXT,
  "BGC_Variant" TEXT,
  "BGC_Phase" TEXT,
  "SiteSeries" TEXT,
  "SSPhase" TEXT,
  "SSVariation" TEXT,
  "Seral" TEXT,
  "SiteSeriesDescription" TEXT,
  "PlantAssociation" TEXT,
  "Comments" TEXT,
  "Ref_ID" REAL,
  "AddedDate" TIMESTAMP,
  "ExpiredDate" TEXT,
  "O_SS_ID" REAL,
  "MergedBGC_SS" TEXT,
  "BECSuballiance" TEXT,
  "BECAlliance" TEXT,
  "MissingNpeNa" TEXT,
  "TransferID" TEXT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysSiteSeriesNames_O_SS_ID" ON "USysSiteSeriesNames" ("O_SS_ID");
CREATE INDEX "idx_USysSiteSeriesNames_Ref_ID" ON "USysSiteSeriesNames" ("Ref_ID");
CREATE INDEX "idx_USysSiteSeriesNames_SiteSeries_ID" ON "USysSiteSeriesNames" ("SiteSeries_ID");
CREATE INDEX "idx_USysSiteSeriesNames_SSCode" ON "USysSiteSeriesNames" ("SSCode");
CREATE INDEX "idx_USysSiteSeriesNames_TransferID" ON "USysSiteSeriesNames" ("TransferID");

