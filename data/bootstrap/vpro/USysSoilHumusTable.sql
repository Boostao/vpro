CREATE TABLE "USysSoilHumusTable" (
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
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysSoilHumusTable_PlotNumber" ON "USysSoilHumusTable" ("PlotNumber");
