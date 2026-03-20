CREATE TABLE "USysLowestBreakpoints_Hierarchy" (
  "ID" INTEGER PRIMARY KEY, -- Number automatically assigned to new node
  "Name" TEXT NOT NULL, -- Node's label
  "Parent" INTEGER, -- Node's parent
  "Level" INTEGER,
  "Tag" TEXT,
  "MyOrder" TEXT,
  "ChildID" INTEGER,
  "StartChild" INTEGER,
  "LastChild" INTEGER,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_USysLowestBreakpoints_Hierarchy_ChildID" ON "USysLowestBreakpoints_Hierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_USysLowestBreakpoints_Hierarchy_Name" ON "USysLowestBreakpoints_Hierarchy" ("Name");
CREATE INDEX "idx_USysLowestBreakpoints_Hierarchy_Level" ON "USysLowestBreakpoints_Hierarchy" ("Level");
CREATE INDEX "idx_USysLowestBreakpoints_Hierarchy_MyOrder" ON "USysLowestBreakpoints_Hierarchy" ("MyOrder");
CREATE INDEX "idx_USysLowestBreakpoints_Hierarchy_Parent" ON "USysLowestBreakpoints_Hierarchy" ("Parent");
