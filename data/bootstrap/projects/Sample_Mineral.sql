CREATE TABLE "Mineral" (
  "PlotNumber" VARCHAR NOT NULL,
  "Horizon" VARCHAR,
  "UpperDepth" REAL,
  "LowerDepth" REAL,
  "PitDepthLimit" VARCHAR,
  "Colour" VARCHAR,
  "ASP" SMALLINT,
  "Texture" VARCHAR,
  "PercentCoarseFragsGravel" SMALLINT,
  "PercentCoarseFragsCobbles" SMALLINT,
  "PercentCoarseFragsStones" SMALLINT,
  "PercentCoarseFragsTotal" SMALLINT,
  "PercentCoarseFragsShape" VARCHAR,
  "RootsAbundance" VARCHAR,
  "RootsSize" VARCHAR,
  "MineralStructureClass" VARCHAR,
  "MineralStructureKind" VARCHAR,
  "MineralFormpH" REAL,
  "MottlesAbundance" VARCHAR,
  "MottlesSize" VARCHAR,
  "MottlesContrast" VARCHAR,
  "ClayFilmsFreq" VARCHAR,
  "ClayFilmThickness" VARCHAR,
  "Effervescence" VARCHAR,
  "Porosity" VARCHAR,
  "Comments" TEXT,
  "Flag" BOOLEAN,
  "ID" INTEGER
);

CREATE UNIQUE INDEX "uidx_Mineral_ID" ON "Mineral" ("ID");
CREATE INDEX "idx_Mineral_PlotNumber" ON "Mineral" ("PlotNumber");
