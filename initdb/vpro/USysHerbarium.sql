CREATE TABLE "USysHerbarium" (
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

CREATE INDEX "idx_USysHerbarium_Species" ON "USysHerbarium" ("Species");
CREATE INDEX "idx_USysHerbarium_Identifier" ON "USysHerbarium" ("Identifier");
