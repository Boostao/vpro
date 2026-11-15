CREATE TABLE "TVHierarchy" (
  "ID" INTEGER PRIMARY KEY, -- Number automatically assigned to new node
  "Name" TEXT NOT NULL, -- Node's label
  "LongCommonName" TEXT,
  "LongScientificName" TEXT,
  "Parent" INTEGER, -- Node's parent
  "Level" INTEGER,
  "Tag" TEXT,
  "MyOrder" TEXT,
  "ChildID" INTEGER,
  "StartChild" INTEGER,
  "LastChild" INTEGER,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_TVHierarchy_ChildID" ON "TVHierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_TVHierarchy_Name" ON "TVHierarchy" ("Name");
CREATE INDEX "idx_TVHierarchy_Level" ON "TVHierarchy" ("Level");
CREATE INDEX "idx_TVHierarchy_Parent" ON "TVHierarchy" ("Parent");
