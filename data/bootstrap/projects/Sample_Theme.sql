-- Access table description: VP05
CREATE TABLE "Theme" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "ScientificName" VARCHAR,
  "ColourCode" SMALLINT,
  "PatternCode" SMALLINT,
  "FontColour" SMALLINT,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Theme_ColourCode" ON "Theme" ("ColourCode");
CREATE INDEX "idx_Theme_LumpCode" ON "Theme" ("LumpCode");
CREATE INDEX "idx_Theme_PatternCode" ON "Theme" ("PatternCode");
CREATE UNIQUE INDEX "uidx_Theme_ScientificName" ON "Theme" ("ScientificName");
CREATE UNIQUE INDEX "uidx_Theme_SppCode" ON "Theme" ("SppCode");

/*
Access metadata notes for Theme:
- Table Description: VP05
- SppCode and ScientificName are unique in Access.
Potential write constraints to consider later:
- CHECK(length("LumpCode") <= 8)
- CHECK(length("SppCode") <= 8)
*/
