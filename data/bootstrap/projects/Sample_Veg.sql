-- Access table description: VP08
CREATE TABLE "Veg" (
  "PlotNumber" VARCHAR NOT NULL, -- linked to env table
  "Species" VARCHAR NOT NULL, -- linked to species code library
  "Layer" VARCHAR,
  "Cover1" REAL, -- Dominant tree layer
  "Height1" REAL,
  "Cover2" REAL, -- Main canopy tree layer
  "Height2" REAL,
  "Cover3" REAL, -- Suppressed tree layer
  "Height3" REAL,
  "TotalA" REAL, -- rk added field
  "HeightA" REAL, -- added July 6, 2015
  "Cover4" REAL, -- Tall shrub layer
  "Height4" REAL,
  "Cover5" REAL, -- Short shrub layer
  "Height5" REAL,
  "Cover5a" REAL, -- Shrub layer added 14 Oct 2014
  "Height5a" REAL, -- Shrub layer added 14 Oct 2014
  "Cover5b" REAL, -- Shrub layer added 14 Oct 2014
  "Height5b" REAL, -- Shrub layer added 14 Oct 2014
  "Cover5c" REAL, -- Shrub layer added 14 Oct 2014
  "Height5c" REAL, -- Shrub layer added 14 Oct 2014
  "TotalB" REAL,
  "HeightB" VARCHAR, -- added July 6, 2015
  "Cover6" REAL, -- Herb layer
  "Height6" REAL,
  "Cover7" REAL, -- Moss layer
  "Cover8" REAL, -- Epixyls - species on downed wood
  "Cover9" REAL, -- Epiliths - species on rock
  "Cover10" REAL, -- Epiphytes - species on trees
  "Collected" VARCHAR,
  "Flag" BOOLEAN, -- rk added field
  "ID" INTEGER,
  "LL" INTEGER, -- Arboreal Lichen loading code
  "AF" SMALLINT, -- Available Forage Code
  "DC" SMALLINT, -- Distribution Code
  "UT" SMALLINT, -- Utilization Code
  "VI" SMALLINT, -- Vigour Code
  "PV" INTEGER, -- Phenology Code - Vegetative
  "PG" SMALLINT, -- Phenology Code - Generative
  "FFA" SMALLINT, -- Fruit/Flower abundance code
  "Cultural1" SMALLINT, -- User defined cultural use value code
  "Cultural2" SMALLINT, -- User defined cultural use value code
  "Other1" SMALLINT, -- User defined other value code
  "Other2" SMALLINT, -- User defined other value code
  FOREIGN KEY ("PlotNumber") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Veg_ID" ON "Veg" ("ID");
CREATE INDEX "idx_Veg_PlotNumber" ON "Veg" ("PlotNumber");
CREATE INDEX "idx_Veg_Species" ON "Veg" ("Species");

/*
Access metadata notes for Veg:
- Table Description: VP08
- PlotNumber: Field Size=7; Required=Yes; AllowZeroLength=No.
- Species: Field Size=8; Required=Yes; AllowZeroLength=No.
- HeightB: Access stores this as text with AllowZeroLength=Yes.
- Relationship: PlotNumber -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(trim("PlotNumber") <> '')
- CHECK(length("Species") <= 8)
- CHECK(trim("Species") <> '')
- CHECK(length("Layer") <= 2)
- CHECK(length("Collected") <= 1)
*/
