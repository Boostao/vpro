CREATE TABLE "USysLevelUnits_SU" (
  "PlotNumber" TEXT,
  "SiteUnit1" TEXT,
  "SiteUnit2" TEXT,
  "SiteUnit3" TEXT,
  "SiteUnit4" TEXT,
  "SiteUnit5" TEXT,
  "SiteUnit6" TEXT,
  "SiteUnit7" TEXT,
  "SiteUnit8" TEXT,
  "SiteUnit9" TEXT,
  "SiteUnit10" TEXT,
  "SiteUnit11" TEXT
);

CREATE UNIQUE INDEX "uidx_USysLevelUnits_SU_PlotNumber" ON "USysLevelUnits_SU" ("PlotNumber");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit1" ON "USysLevelUnits_SU" ("SiteUnit1");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit2" ON "USysLevelUnits_SU" ("SiteUnit2");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit11" ON "USysLevelUnits_SU" ("SiteUnit11");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit3" ON "USysLevelUnits_SU" ("SiteUnit3");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit4" ON "USysLevelUnits_SU" ("SiteUnit4");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit5" ON "USysLevelUnits_SU" ("SiteUnit5");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit6" ON "USysLevelUnits_SU" ("SiteUnit6");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit7" ON "USysLevelUnits_SU" ("SiteUnit7");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit8" ON "USysLevelUnits_SU" ("SiteUnit8");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit9" ON "USysLevelUnits_SU" ("SiteUnit9");
CREATE INDEX "idx_USysLevelUnits_SU_SiteUnit10" ON "USysLevelUnits_SU" ("SiteUnit10");
