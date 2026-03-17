CREATE TABLE "USysJuice_SU" (
  "PlotNumber" TEXT,
  "SiteUnit" TEXT,
  "ID" INTEGER
);

CREATE UNIQUE INDEX "uidx_USysJuice_SU_PlotNumber" ON "USysJuice_SU" ("PlotNumber");
CREATE INDEX "idx_USysJuice_SU_SiteUnit" ON "USysJuice_SU" ("SiteUnit");
