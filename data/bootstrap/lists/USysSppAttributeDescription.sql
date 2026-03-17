CREATE TABLE "USysSppAttributeDescription" (
  "IsAttribute" BOOLEAN DEFAULT FALSE,
  "Field" TEXT,
  "ShortName" TEXT,
  "Code" TEXT,
  "Definition" TEXT,
  "FieldDescription" TEXT
);

CREATE INDEX "idx_USysSppAttributeDescription_Code" ON "USysSppAttributeDescription" ("Code");

