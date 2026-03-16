CREATE TABLE "Humus" (
  "PlotNumber" VARCHAR NOT NULL,
  "Horizon" VARCHAR,
  "UpperDepth" REAL,
  "LowerDepth" REAL,
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
  "Flag" BOOLEAN,
  "ID" INTEGER
);

CREATE UNIQUE INDEX "uidx_Humus_ID" ON "Humus" ("ID");
CREATE INDEX "idx_Humus_PlotNumber" ON "Humus" ("PlotNumber");
