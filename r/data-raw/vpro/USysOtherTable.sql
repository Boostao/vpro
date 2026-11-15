CREATE TABLE "USysOtherTable" (
  "PlotNumber" VARCHAR NOT NULL,
  "DataName" VARCHAR,
  "DataItem" VARCHAR,
  "UserItem1" VARCHAR,
  "UserItem2" VARCHAR,
  "UserItem3" VARCHAR,
  "UserFlag1" BOOLEAN,
  "UserFlag2" BOOLEAN,
  "UserFlag3" BOOLEAN,
  "Flag" BOOLEAN,
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysOtherTable_PlotNumber" ON "USysOtherTable" ("PlotNumber");
