CREATE TABLE "USysV2VegLF" (
  "ProjectID" TEXT,
  "Plotnumber" TEXT NOT NULL,
  "Layer" INTEGER,
  "Species" TEXT,
  "Cover" REAL,
  "Surveyor" TEXT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysV2VegLF_Layer" ON "USysV2VegLF" ("Layer");
CREATE INDEX "idx_USysV2VegLF_Plotnumber" ON "USysV2VegLF" ("Plotnumber");
CREATE INDEX "idx_USysV2VegLF_ProjectID" ON "USysV2VegLF" ("ProjectID");
CREATE INDEX "idx_USysV2VegLF_ProjectID_Plotnumber_Layer_Species" ON "USysV2VegLF" ("ProjectID", "Plotnumber", "Layer", "Species");
CREATE INDEX "idx_USysV2VegLF_ProjectID_Plotnumber" ON "USysV2VegLF" ("ProjectID", "Plotnumber");
CREATE INDEX "idx_USysV2VegLF_Species" ON "USysV2VegLF" ("Species");
