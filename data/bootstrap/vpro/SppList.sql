CREATE TABLE "SppList" (
  "SpeciesNumber" INTEGER,
  "Code" TEXT,
  "ScientificName" TEXT,
  "CodePlusStrata" TEXT,
  "CodePlusLayer" TEXT,
  "Temp" TEXT
);

CREATE INDEX "idx_SppList_Code" ON "SppList" ("Code");
CREATE INDEX "idx_SppList_CodePlusLayer" ON "SppList" ("CodePlusLayer");
CREATE INDEX "idx_SppList_CodePlusStrata" ON "SppList" ("CodePlusStrata");
CREATE UNIQUE INDEX "uidx_SppList_SpeciesNumber" ON "SppList" ("SpeciesNumber");
