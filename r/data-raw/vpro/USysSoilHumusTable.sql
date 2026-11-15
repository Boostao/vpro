CREATE TABLE "USysSoilHumusTable" (
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
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysSoilHumusTable_PlotNumber" ON "USysSoilHumusTable" ("PlotNumber");
