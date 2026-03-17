CREATE TABLE "USysThemeTable" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "ScientificName" VARCHAR,
  "ColourCode" SMALLINT,
  "PatternCode" SMALLINT,
  "FontColour" SMALLINT,
  "Use" BOOLEAN
);

CREATE INDEX "idx_USysThemeTable_ColourCode" ON "USysThemeTable" ("ColourCode");
CREATE INDEX "idx_USysThemeTable_LumpCode" ON "USysThemeTable" ("LumpCode");
CREATE INDEX "idx_USysThemeTable_PatternCode" ON "USysThemeTable" ("PatternCode");
CREATE UNIQUE INDEX "uidx_USysThemeTable_ScientificName" ON "USysThemeTable" ("ScientificName");
CREATE UNIQUE INDEX "uidx_USysThemeTable_SppCode" ON "USysThemeTable" ("SppCode");
