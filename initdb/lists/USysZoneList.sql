CREATE TABLE "USysZoneList" (
  "Zone" TEXT,
  "SubZone" TEXT,
  "ZoneDescription" TEXT,
  "SubZoneVarDescription" TEXT
);

CREATE INDEX "idx_USysZoneList_SubZone" ON "USysZoneList" ("SubZone");
CREATE INDEX "idx_USysZoneList_Zone" ON "USysZoneList" ("Zone");

