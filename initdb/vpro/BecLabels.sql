CREATE TABLE "BecLabels" (
  "RecID" INTEGER,
  "PlotNumber1" TEXT,
  "Zone1" TEXT,
  "Representing1" TEXT,
  "ProjectID1" TEXT,
  "PlotNumber2" TEXT,
  "Zone2" TEXT,
  "Representing2" TEXT,
  "ProjectID2" TEXT,
  "PlotNumber3" TEXT,
  "Zone3" TEXT,
  "Representing3" TEXT,
  "ProjectID3" TEXT,
  "PlotNumber4" TEXT,
  "Zone4" TEXT,
  "Representing4" TEXT,
  "ProjectID4" TEXT,
  "PlotNumber5" TEXT,
  "Zone5" TEXT,
  "Representing5" TEXT,
  "ProjectID5" TEXT,
  "PlotNumber6" TEXT,
  "Zone6" TEXT,
  "Representing6" TEXT,
  "ProjectID6" TEXT,
  "PlotNumber7" TEXT,
  "Zone7" TEXT,
  "Representing7" TEXT,
  "ProjectID7" TEXT,
  "PlotNumber8" TEXT,
  "Zone8" TEXT,
  "Representing8" TEXT,
  "ProjectID8" TEXT,
  "PlotNumber9" TEXT,
  "Zone9" TEXT,
  "Representing9" TEXT,
  "ProjectID9" TEXT,
  "PlotNumber10" TEXT,
  "Zone10" TEXT,
  "Representing10" TEXT,
  "ProjectID10" TEXT,
  "PlotNumber11" TEXT,
  "Zone11" TEXT,
  "Representing11" TEXT,
  "ProjectID11" TEXT,
  "PlotNumber12" TEXT,
  "Zone12" TEXT,
  "Representing12" TEXT,
  "ProjectID12" TEXT
);

CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber1" ON "BecLabels" ("PlotNumber1");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber2" ON "BecLabels" ("PlotNumber2");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber11" ON "BecLabels" ("PlotNumber11");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber12" ON "BecLabels" ("PlotNumber12");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber3" ON "BecLabels" ("PlotNumber3");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber4" ON "BecLabels" ("PlotNumber4");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber5" ON "BecLabels" ("PlotNumber5");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber6" ON "BecLabels" ("PlotNumber6");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber7" ON "BecLabels" ("PlotNumber7");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber8" ON "BecLabels" ("PlotNumber8");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber9" ON "BecLabels" ("PlotNumber9");
CREATE UNIQUE INDEX "uidx_BecLabels_PlotNumber10" ON "BecLabels" ("PlotNumber10");
CREATE INDEX "idx_BecLabels_ProjectID1" ON "BecLabels" ("ProjectID1");
CREATE INDEX "idx_BecLabels_ProjectID2" ON "BecLabels" ("ProjectID2");
CREATE INDEX "idx_BecLabels_ProjectID11" ON "BecLabels" ("ProjectID11");
CREATE INDEX "idx_BecLabels_ProjectID12" ON "BecLabels" ("ProjectID12");
CREATE INDEX "idx_BecLabels_ProjectID3" ON "BecLabels" ("ProjectID3");
CREATE INDEX "idx_BecLabels_ProjectID4" ON "BecLabels" ("ProjectID4");
CREATE INDEX "idx_BecLabels_ProjectID5" ON "BecLabels" ("ProjectID5");
CREATE INDEX "idx_BecLabels_ProjectID6" ON "BecLabels" ("ProjectID6");
CREATE INDEX "idx_BecLabels_ProjectID7" ON "BecLabels" ("ProjectID7");
CREATE INDEX "idx_BecLabels_ProjectID8" ON "BecLabels" ("ProjectID8");
CREATE INDEX "idx_BecLabels_ProjectID9" ON "BecLabels" ("ProjectID9");
CREATE INDEX "idx_BecLabels_ProjectID10" ON "BecLabels" ("ProjectID10");
CREATE INDEX "idx_BecLabels_RecID" ON "BecLabels" ("RecID");
