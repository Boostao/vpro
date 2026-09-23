-- Access table description: VP04
CREATE TABLE "Sample_Hierarchy" (
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

CREATE INDEX "idx_Sample_Hierarchy_ChildID" ON "Sample_Hierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_Sample_Hierarchy_Name" ON "Sample_Hierarchy" ("Name");
CREATE INDEX "idx_Sample_Hierarchy_Level" ON "Sample_Hierarchy" ("Level");
CREATE INDEX "idx_Sample_Hierarchy_Parent" ON "Sample_Hierarchy" ("Parent");

/*
Access metadata notes for Sample_Hierarchy:
- Table Description: VP04
- ID: Access AutoNumber primary key.
- Name: Required=Yes; unique in Access.
- Parent: Stored as a long integer pointing to the parent node; Access did not export a formal self-referential relationship here.
Potential write constraints to consider later:
- CHECK(trim("Name") <> '')
- CHECK(length("Name") <= 100)
*/
