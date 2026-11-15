CREATE TABLE "SppListUnique" (
  "SpeciesNumber" INTEGER,
  "Code" TEXT,
  "ScientificName" TEXT,
  "CodePlusStrata" TEXT,
  "CodePlusLayer" TEXT,
  "Temp" TEXT
);

CREATE INDEX "idx_SppListUnique_Code" ON "SppListUnique" ("Code");
CREATE INDEX "idx_SppListUnique_CodePlusLayer" ON "SppListUnique" ("CodePlusLayer");
CREATE INDEX "idx_SppListUnique_CodePlusStrata" ON "SppListUnique" ("CodePlusStrata");
CREATE UNIQUE INDEX "uidx_SppListUnique_SpeciesNumber" ON "SppListUnique" ("SpeciesNumber");
