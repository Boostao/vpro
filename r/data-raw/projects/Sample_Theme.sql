-- Access table description: VP05
CREATE TABLE "Sample_Theme" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "ScientificName" VARCHAR,
  "ColourCode" SMALLINT,
  "PatternCode" SMALLINT,
  "FontColour" SMALLINT,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Sample_Theme_ColourCode" ON "Sample_Theme" ("ColourCode");
CREATE INDEX "idx_Sample_Theme_LumpCode" ON "Sample_Theme" ("LumpCode");
CREATE INDEX "idx_Sample_Theme_PatternCode" ON "Sample_Theme" ("PatternCode");
CREATE UNIQUE INDEX "uidx_Sample_Theme_ScientificName" ON "Sample_Theme" ("ScientificName");
CREATE UNIQUE INDEX "uidx_Sample_Theme_SppCode" ON "Sample_Theme" ("SppCode");

/*
Access metadata notes for Sample_Theme:
- Table Description: VP05
- SppCode and ScientificName are unique in Access.
Potential write constraints to consider later:
- CHECK(length("LumpCode") <= 8)
- CHECK(length("SppCode") <= 8)
*/
