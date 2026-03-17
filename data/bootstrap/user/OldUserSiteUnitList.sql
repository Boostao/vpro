-- Access table description: VP05
CREATE TABLE "OldUserSiteUnitList" (
  "ID" INTEGER PRIMARY KEY,
  "ShortName" TEXT,
  "Name" TEXT, -- Unique Short name for Unit
  "UnitLongName" TEXT, -- Current site association name, site series phase name (if applicable)
  "PlantAssoc" TEXT, -- Plant association name; sub-association name
  "Parent" INTEGER, -- Node's parent
  "Level" INTEGER,
  "Date" TIMESTAMP,
  "Source" TEXT,
  "Locked" BOOLEAN,
  "nPlots" INTEGER,
  "SeralCode" TEXT
);

CREATE INDEX "idx_OldUserSiteUnitList_Level" ON "OldUserSiteUnitList" ("Level");
CREATE INDEX "idx_OldUserSiteUnitList_Parent" ON "OldUserSiteUnitList" ("Parent");
CREATE INDEX "idx_OldUserSiteUnitList_SeralCode" ON "OldUserSiteUnitList" ("SeralCode");
CREATE INDEX "idx_OldUserSiteUnitList_ShortName" ON "OldUserSiteUnitList" ("ShortName");
CREATE UNIQUE INDEX "uidx_OldUserSiteUnitList_Name" ON "OldUserSiteUnitList" ("Name");
