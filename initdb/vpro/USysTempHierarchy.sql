CREATE TABLE "USysTempHierarchy" (
  "ID" INTEGER PRIMARY KEY, -- Number automatically assigned to new node
  "Name" TEXT NOT NULL, -- Node's label
  "Parent" INTEGER, -- Node's parent
  "Level" INTEGER,
  "Tag" TEXT,
  "MyOrder" TEXT,
  "ChildID" INTEGER,
  "StartChild" INTEGER,
  "LastChild" INTEGER
);

CREATE INDEX "idx_USysTempHierarchy_ChildID" ON "USysTempHierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_USysTempHierarchy_Name" ON "USysTempHierarchy" ("Name");
CREATE INDEX "idx_USysTempHierarchy_Level" ON "USysTempHierarchy" ("Level");
CREATE INDEX "idx_USysTempHierarchy_Parent" ON "USysTempHierarchy" ("Parent");
