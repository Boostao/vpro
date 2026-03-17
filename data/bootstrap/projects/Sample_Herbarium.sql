-- Access table description: VP06
CREATE TABLE "Herbarium" (
  "RecID" INTEGER PRIMARY KEY, -- Y
  "AccessionNumber" VARCHAR, -- Y
  "AccessionDate" TIMESTAMP, -- Y
  "PlotNumber" VARCHAR, -- Y
  "Species" VARCHAR, -- Y
  "ScientificNameRich" TEXT,
  "SpecimenPreviousName" VARCHAR, -- Y
  "Identifier" VARCHAR, -- Y
  "Habitat" TEXT, -- Y
  "CountryOfOrigin" VARCHAR, -- Y
  "ProvinceOfOrigin" VARCHAR, -- Y
  "CollectionNumber" VARCHAR, -- Y
  "LocationDescription" VARCHAR, -- Y
  "Collectors" VARCHAR, -- Y
  "DateOfCollection" TIMESTAMP, -- Y
  "GeneralRemarks" TEXT, -- Y
  "PermanentStorageLocation" VARCHAR, -- Y
  "EntryOperator" VARCHAR, -- Y
  "EntryOperatorDate" TIMESTAMP, -- Y
  "Comments" VARCHAR, -- Y
  "Photo" BLOB, -- Y
  "Flag01" BOOLEAN, -- Y
  "Flag02" BOOLEAN, -- Y
  "LongitudeDegrees" REAL, -- Y
  "LongitudeMinutes" REAL, -- Y
  "LongitudeSeconds" REAL, -- Y
  "LatitudeDegrees" REAL, -- Y
  "LatitudeMinutes" REAL, -- Y
  "LatitudeSeconds" REAL, -- Y
  "DuplicateSentTo" VARCHAR, -- Y
  "OnLoanTo" VARCHAR, -- Y
  "LoanDate" TIMESTAMP, -- Y
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
