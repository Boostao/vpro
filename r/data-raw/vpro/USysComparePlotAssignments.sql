CREATE TABLE "USysComparePlotAssignments" (
  "PlotNumber" TEXT,
  "SiteUnit1" TEXT, -- historical
  "SiteUnit2" TEXT, -- present
  "Change" TEXT,
  "PlantAssoc1" TEXT,
  "PlantAssoc2" TEXT,
  "AssocChange" TEXT
);

CREATE UNIQUE INDEX "uidx_USysComparePlotAssignments_PlotNumber" ON "USysComparePlotAssignments" ("PlotNumber");
CREATE INDEX "idx_USysComparePlotAssignments_SiteUnit1" ON "USysComparePlotAssignments" ("SiteUnit1");
CREATE INDEX "idx_USysComparePlotAssignments_SiteUnit2" ON "USysComparePlotAssignments" ("SiteUnit2");
