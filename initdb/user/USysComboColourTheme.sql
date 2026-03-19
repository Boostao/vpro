-- Access table description: VP05
CREATE TABLE "USysComboColourTheme" (
  "LumpCode" TEXT,
  "SppCode" TEXT,
  "ScientificName" TEXT,
  "ColourCode" INTEGER,
  "PatternCode" INTEGER,
  "FontColour" INTEGER,
  "Use" BOOLEAN
);

CREATE INDEX "idx_USysComboColourTheme_LumpCode" ON "USysComboColourTheme" ("LumpCode");
CREATE UNIQUE INDEX "uidx_USysComboColourTheme_ScientificName" ON "USysComboColourTheme" ("ScientificName");
CREATE UNIQUE INDEX "uidx_USysComboColourTheme_SppCode" ON "USysComboColourTheme" ("SppCode");
