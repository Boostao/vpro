CREATE TABLE "Hierarchy" (
  "ID" INTEGER,
  "Name" VARCHAR NOT NULL,
  "Parent" INTEGER,
  "Level" SMALLINT,
  "Tag" VARCHAR,
  "MyOrder" VARCHAR,
  "ChildID" SMALLINT,
  "StartChild" SMALLINT,
  "LastChild" SMALLINT,
  "Flag" BOOLEAN
);

CREATE INDEX "idx_Hierarchy_ChildID" ON "Hierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_Hierarchy_LastName" ON "Hierarchy" ("Name");
CREATE INDEX "idx_Hierarchy_Level" ON "Hierarchy" ("Level");
CREATE INDEX "idx_Hierarchy_Parent" ON "Hierarchy" ("Parent");
CREATE UNIQUE INDEX "uidx_Hierarchy_PrimaryKey" ON "Hierarchy" ("ID");
