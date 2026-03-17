-- Access table description: VP08
CREATE TABLE "Other" (
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
  "ID" INTEGER,
  FOREIGN KEY ("PlotNumber") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE UNIQUE INDEX "uidx_Other_ID" ON "Other" ("ID");
CREATE INDEX "idx_Other_PlotNumber" ON "Other" ("PlotNumber");

/*
Access metadata notes for Other:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("DataName") <= 50)
*/
