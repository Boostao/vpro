CREATE TABLE "USysSppAttributeDescription" (
  "IsAttribute" BOOLEAN DEFAULT FALSE,
  "Field" TEXT, -- Field name in table USysSppAttributes
  "ShortName" TEXT, -- Short name matching short names in table USysSppAttributeFieldList
  "Code" TEXT, -- Attribute code
  "Definition" TEXT, -- Definition of the code
  "FieldDescription" TEXT -- Description of the data field
);

CREATE INDEX "idx_USysSppAttributeDescription_Code" ON "USysSppAttributeDescription" ("Code");

