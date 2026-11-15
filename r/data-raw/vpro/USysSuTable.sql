CREATE TABLE "USysSuTable" (
  "PlotNumber" VARCHAR,
  "SiteUnit" VARCHAR
);

CREATE UNIQUE INDEX "uidx_USysSuTable_PlotNumber" ON "USysSuTable" ("PlotNumber");
CREATE INDEX "idx_USysSuTable_SiteUnit" ON "USysSuTable" ("SiteUnit");
