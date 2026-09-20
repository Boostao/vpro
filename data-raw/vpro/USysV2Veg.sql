CREATE TABLE "USysV2Veg" (
  "ProjectID" TEXT,
  "Plotnumber" TEXT NOT NULL,
  "Layer" TEXT,
  "Species" TEXT,
  "Cover" REAL,
  "Surveyor" TEXT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysV2Veg_Layer" ON "USysV2Veg" ("Layer");
CREATE INDEX "idx_USysV2Veg_Plotnumber" ON "USysV2Veg" ("Plotnumber");
CREATE INDEX "idx_USysV2Veg_ProjectID" ON "USysV2Veg" ("ProjectID");
CREATE INDEX "idx_USysV2Veg_ProjectID_Plotnumber_Layer_Species" ON "USysV2Veg" ("ProjectID", "Plotnumber", "Layer", "Species");
CREATE INDEX "idx_USysV2Veg_ProjectID_Plotnumber" ON "USysV2Veg" ("ProjectID", "Plotnumber");
CREATE INDEX "idx_USysV2Veg_Species" ON "USysV2Veg" ("Species");
