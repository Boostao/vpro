CREATE TABLE "USysExportSppList" (
  "SpeciesNumber" INTEGER,
  "Code" TEXT,
  "ScientificName" TEXT,
  "CodePlusStrata" TEXT,
  "CodePlusLayer" TEXT,
  "Temp" TEXT
);

CREATE INDEX "idx_USysExportSppList_Code" ON "USysExportSppList" ("Code");
CREATE INDEX "idx_USysExportSppList_CodePlusLayer" ON "USysExportSppList" ("CodePlusLayer");
CREATE INDEX "idx_USysExportSppList_CodePlusStrata" ON "USysExportSppList" ("CodePlusStrata");
CREATE UNIQUE INDEX "uidx_USysExportSppList_SpeciesNumber" ON "USysExportSppList" ("SpeciesNumber");
