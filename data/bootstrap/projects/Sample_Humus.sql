-- Access table description: VP08
CREATE TABLE "Humus" (
  "PlotNumber" VARCHAR NOT NULL, -- Links to env table
  "Horizon" VARCHAR, -- Humus horizon code
  "UpperDepth" REAL, -- Depth of upper horizon boundary
  "LowerDepth" REAL, -- Depth of lower horizon boundary
  "HumusStructureDegree" VARCHAR,
  "HumusStructureKind" VARCHAR,
  "MycelAbundance" VARCHAR,
  "FecalAbundance" VARCHAR,
  "RootsAbundance" VARCHAR,
  "RootsSize" VARCHAR,
  "vonPost" SMALLINT,
  "HumusFormpH" REAL,
  "Consistence" VARCHAR,
  "Character" VARCHAR,
  "Fauna" VARCHAR,
  "Comment" TEXT,
  "Flag" BOOLEAN, -- rk add field
  "ID" INTEGER,
  FOREIGN KEY ("PlotNumber") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE UNIQUE INDEX "uidx_Humus_ID" ON "Humus" ("ID");
CREATE INDEX "idx_Humus_PlotNumber" ON "Humus" ("PlotNumber");

/*
Access metadata notes for Humus:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("Horizon") <= 8)
*/
