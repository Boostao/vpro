CREATE TABLE "USysSoilMineralTable" (
  "PlotNumber" VARCHAR NOT NULL, -- links to env table
  "Horizon" VARCHAR, -- Mineral horizon designation
  "UpperDepth" REAL, -- Upper depth of horizon (cm)
  "LowerDepth" REAL, -- Lower depth of horizon (cm)
  "PitDepthLimit" VARCHAR, -- for '+'
  "Colour" VARCHAR, -- Munsell colour type
  "ASP" SMALLINT, -- code - aspect (moisture) at time of colour
  "Texture" VARCHAR, -- horizon soil texture code
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
  "Flag" BOOLEAN, -- rk add field
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysSoilMineralTable_PlotNumber" ON "USysSoilMineralTable" ("PlotNumber");
