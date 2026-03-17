-- Access table description: VP08
CREATE TABLE "Mineral" (
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
  "ID" INTEGER PRIMARY KEY,
  FOREIGN KEY ("PlotNumber") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Mineral_PlotNumber" ON "Mineral" ("PlotNumber");

/*
Access metadata notes for Mineral:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("Horizon") <= 8)
- CHECK(length("Texture") <= 4)
*/
