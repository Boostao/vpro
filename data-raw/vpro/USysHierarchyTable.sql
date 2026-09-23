CREATE TABLE "USysHierarchyTable" (
  "ID" INTEGER PRIMARY KEY, -- Number automatically assigned to new node
  "Name" VARCHAR NOT NULL, -- Node's label
  "Parent" INTEGER, -- Node's parent
  "Level" SMALLINT,
  "Tag" VARCHAR,
  "MyOrder" VARCHAR,
  "ChildID" SMALLINT,
  "StartChild" SMALLINT,
  "LastChild" SMALLINT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysHierarchyTable_ChildID" ON "USysHierarchyTable" ("ChildID");
CREATE UNIQUE INDEX "uidx_USysHierarchyTable_Name" ON "USysHierarchyTable" ("Name");
CREATE INDEX "idx_USysHierarchyTable_Level" ON "USysHierarchyTable" ("Level");
CREATE INDEX "idx_USysHierarchyTable_MyOrder" ON "USysHierarchyTable" ("MyOrder");
CREATE INDEX "idx_USysHierarchyTable_Parent" ON "USysHierarchyTable" ("Parent");
