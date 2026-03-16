CREATE TABLE "Herbarium" (
  "RecID" INTEGER,
  "AccessionNumber" VARCHAR,
  "AccessionDate" TIMESTAMP,
  "PlotNumber" VARCHAR,
  "Species" VARCHAR,
  "ScientificNameRich" TEXT,
  "SpecimenPreviousName" VARCHAR,
  "Identifier" VARCHAR,
  "Habitat" TEXT,
  "CountryOfOrigin" VARCHAR,
  "ProvinceOfOrigin" VARCHAR,
  "CollectionNumber" VARCHAR,
  "LocationDescription" VARCHAR,
  "Collectors" VARCHAR,
  "DateOfCollection" TIMESTAMP,
  "GeneralRemarks" TEXT,
  "PermanentStorageLocation" VARCHAR,
  "EntryOperator" VARCHAR,
  "EntryOperatorDate" TIMESTAMP,
  "Comments" VARCHAR,
  "Photo" BLOB,
  "Flag01" BOOLEAN,
  "Flag02" BOOLEAN,
  "LongitudeDegrees" REAL,
  "LongitudeMinutes" REAL,
  "LongitudeSeconds" REAL,
  "LatitudeDegrees" REAL,
  "LatitudeMinutes" REAL,
  "LatitudeSeconds" REAL,
  "DuplicateSentTo" VARCHAR,
  "OnLoanTo" VARCHAR,
  "LoanDate" TIMESTAMP,
  "Print" BOOLEAN DEFAULT FALSE
);

CREATE INDEX "idx_Herbarium_Code" ON "Herbarium" ("Species");
CREATE INDEX "idx_Herbarium_Identifier" ON "Herbarium" ("Identifier");
CREATE UNIQUE INDEX "uidx_Herbarium_PrimaryKey" ON "Herbarium" ("RecID");
CREATE UNIQUE INDEX "uidx_Herbarium_RecID" ON "Herbarium" ("RecID");
