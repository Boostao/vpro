-- Access table description: VP08
CREATE TABLE "Sample_Other" (
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
  "ID" INTEGER PRIMARY KEY,
  FOREIGN KEY ("PlotNumber") REFERENCES "Sample_Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Sample_Other_PlotNumber" ON "Sample_Other" ("PlotNumber");

/*
Access metadata notes for Sample_Other:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Sample_Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("DataName") <= 50)
*/
