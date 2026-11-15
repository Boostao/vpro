CREATE TABLE "USysPictureBlob" (
  "ID" INTEGER PRIMARY KEY,
  "FileName" TEXT NOT NULL,
  "PlotOrUnit" TEXT,
  "Owner" TEXT,
  "DateTaken" TIMESTAMP,
  "Caption" TEXT,
  "Blob" BLOB,
  "Comment" TEXT,
  "Other" TEXT
);

CREATE INDEX "idx_USysPictureBlob_ID" ON "USysPictureBlob" ("ID");
CREATE INDEX "idx_USysPictureBlob_PlotOrUnit" ON "USysPictureBlob" ("PlotOrUnit");
