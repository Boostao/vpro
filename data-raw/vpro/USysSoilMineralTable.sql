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
  "PercentCoarseFragsShape" VARCHAR, -- code
  "RootsAbundance" VARCHAR, -- code
  "RootsSize" VARCHAR, -- code
  "MineralStructureClass" VARCHAR, -- code
  "MineralStructureKind" VARCHAR, -- code
  "MineralFormpH" REAL, -- code
  "MottlesAbundance" VARCHAR, -- code
  "MottlesSize" VARCHAR, -- code
  "MottlesContrast" VARCHAR, -- code
  "ClayFilmsFreq" VARCHAR, -- code
  "ClayFilmThickness" VARCHAR, -- code
  "Effervescence" VARCHAR, -- code
  "Porosity" VARCHAR, -- code
  "Comments" TEXT,
  "Flag" BOOLEAN, -- rk add field
  "ID" INTEGER PRIMARY KEY
);

CREATE INDEX "idx_USysSoilMineralTable_PlotNumber" ON "USysSoilMineralTable" ("PlotNumber");
