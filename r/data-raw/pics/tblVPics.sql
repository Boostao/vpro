CREATE TABLE "tblVPics" (
  "ID" INTEGER PRIMARY KEY,
  "PicDir" VARCHAR,
  "PicName" VARCHAR,
  "PlotNumber" VARCHAR,
  "PicComment" VARCHAR
);

CREATE INDEX "idx_tblVPics_PlotNumber" ON "tblVPics" ("PlotNumber");