-- Access table description: VP08
CREATE TABLE "Sample_Mineral" (
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
  "ID" INTEGER PRIMARY KEY,
  FOREIGN KEY ("PlotNumber") REFERENCES "Sample_Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Sample_Mineral_PlotNumber" ON "Sample_Mineral" ("PlotNumber");

/*
Access metadata notes for Sample_Mineral:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Relationship: PlotNumber -> Sample_Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("Horizon") <= 8)
- CHECK(length("Texture") <= 4)
*/
