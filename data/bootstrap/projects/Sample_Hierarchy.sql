-- Access table description: VP04
CREATE TABLE "Hierarchy" (
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

CREATE INDEX "idx_Hierarchy_ChildID" ON "Hierarchy" ("ChildID");
CREATE UNIQUE INDEX "uidx_Hierarchy_Name" ON "Hierarchy" ("Name");
CREATE INDEX "idx_Hierarchy_Level" ON "Hierarchy" ("Level");
CREATE INDEX "idx_Hierarchy_Parent" ON "Hierarchy" ("Parent");

/*
Access metadata notes for Hierarchy:
- Table Description: VP04
- ID: Access AutoNumber primary key.
- Name: Required=Yes; unique in Access.
- Parent: Stored as a long integer pointing to the parent node; Access did not export a formal self-referential relationship here.
Potential write constraints to consider later:
- CHECK(trim("Name") <> '')
- CHECK(length("Name") <= 100)
*/
