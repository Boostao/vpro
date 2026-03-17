CREATE TABLE "USysTableOfLists" (
  "ListName" TEXT,
  "ListFilter" TEXT,
  "ItemOrder" REAL,
  "Item" TEXT,
  "ItemDescription" TEXT,
  "FieldUsedIn" TEXT,
  "ValidateLoops" TEXT,
  "Validate" BOOLEAN,
  "Note" TEXT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysTableOfLists_Item" ON "USysTableOfLists" ("Item");

