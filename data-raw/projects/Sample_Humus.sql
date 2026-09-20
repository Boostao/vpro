-- Access table description: VP08
CREATE TABLE "Sample_Humus" (
  "PlotNumber" VARCHAR NOT NULL, -- Links to env table
  "Horizon" VARCHAR, -- Humus horizon code
  "UpperDepth" REAL, -- Depth of upper horizon boundary
  "LowerDepth" REAL, -- Depth of lower horizon boundary
  "HumusStructureDegree" VARCHAR, -- code
  "HumusStructureKind" VARCHAR, -- code
  "MycelAbundance" VARCHAR, -- code
  "FecalAbundance" VARCHAR, -- code
  "RootsAbundance" VARCHAR, -- code
  "RootsSize" VARCHAR, -- code
  "vonPost" SMALLINT, -- code
  "HumusFormpH" REAL, -- code
  "Consistence" VARCHAR, -- code
  "Character" VARCHAR, -- code
  "Fauna" VARCHAR, -- code
  "Comment" TEXT,
  "Flag" BOOLEAN, -- rk add field
  "ID" INTEGER PRIMARY KEY,
  FOREIGN KEY ("PlotNumber") REFERENCES "Sample_Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Sample_Humus_PlotNumber" ON "Sample_Humus" ("PlotNumber");

/*
Access metadata notes for Sample_Humus:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Sample_Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("Horizon") <= 8)
*/
