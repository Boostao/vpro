CREATE TABLE "ProjectMetaData" (
  "ProjectID" TEXT, -- Links to VPRO project id field
  "ProponentFunder" TEXT, -- Funding agency/University
  "FieldDataCollection" TEXT, -- Company/Individual coordinating field work
  "PlotQualityVegetation" TEXT, -- General plot quality for project - vegetation
  "PlotQualitySoils" TEXT, -- General plot quality for project - env.
  "ProjectPurpose" TEXT, -- Purpose of project
  "StudyArea" TEXT, -- Geographic area of study
  "Datum" TEXT, -- NAD 27/NAD83
  "CoordinateSystemCollected" TEXT, -- UTM, Lat/Long
  "GeoreferenceMethod" TEXT, -- Codes
  "FieldCollectionStds" TEXT, -- Collection standards reference
  "VegCoverClassType" TEXT,
  "ExtraVegFieldType" TEXT,
  "CardStorageLocation" TEXT,
  "Notes" TEXT
);

CREATE UNIQUE INDEX "uidx_ProjectMetaData_ProjectID" ON "ProjectMetaData" ("ProjectID");
