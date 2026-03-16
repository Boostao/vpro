CREATE TABLE "SU" (
  "PlotNumber" VARCHAR,
  "SiteUnit" VARCHAR
);

CREATE UNIQUE INDEX "uidx_SU_PlotNumber" ON "SU" ("PlotNumber");
CREATE INDEX "idx_SU_SiteUnit" ON "SU" ("SiteUnit");
