CREATE TABLE "USysLowestBreakpoints_Hierarchy" (
  "ID" INTEGER PRIMARY KEY,
  "Name" TEXT NOT NULL,
  "Parent" INTEGER,
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
