-- Access table description: VP06
CREATE TABLE "Herbarium" (
  "RecID" INTEGER PRIMARY KEY,
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

/*
Access metadata notes for Herbarium:
- Table Description: VP06
- RecID: Access AutoNumber primary key.
- PlotNumber: Field Size=7.
- Species: Field Size=8.
- Print: Default=0 in Access.
- No enforced Access relationship for Herbarium was present in the exported relationship set, so no foreign key was added here.
Potential write constraints to consider later:
- CHECK(length("AccessionNumber") <= 10)
- CHECK(length("PlotNumber") <= 7)
- CHECK(length("Species") <= 8)
*/
