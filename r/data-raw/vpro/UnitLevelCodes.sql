CREATE TABLE "UnitLevelCodes" (
  "ID" INTEGER,
  "Level" INTEGER,
  "Description" TEXT
);

CREATE INDEX "idx_UnitLevelCodes_ID" ON "UnitLevelCodes" ("ID");
CREATE UNIQUE INDEX "uidx_UnitLevelCodes_Level" ON "UnitLevelCodes" ("Level");
