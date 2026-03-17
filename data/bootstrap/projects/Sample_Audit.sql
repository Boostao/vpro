-- Access table description: VP08
CREATE TABLE "Audit" (
  "Project" VARCHAR,
  "User" VARCHAR,
  "PlotNumber" VARCHAR,
  "Table" VARCHAR,
  "EditField" VARCHAR,
  "EditWhen" TIMESTAMP,
  "BeforeEdit" TEXT,
  "AfterEdit" TEXT,
  "Restore" BOOLEAN,
  "Flag" BOOLEAN,
  "ID" INTEGER,
  FOREIGN KEY ("PlotNumber") REFERENCES "Env" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX "idx_Audit_EditWhen" ON "Audit" ("EditWhen");
CREATE INDEX "idx_Audit_ID" ON "Audit" ("ID");

/*
Access metadata notes for Audit:
- Table Description: VP08
- PlotNumber: Field Size=7; AllowZeroLength=No.
- Project: Field Size=100.
- User: Field Size=100.
- Table: Field Size=50.
- EditField: Field Size=100.
- Relationship: PlotNumber -> Env(PlotNumber), enforced in Access with ON UPDATE CASCADE and ON DELETE CASCADE.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(length("Project") <= 100)
- CHECK(length("User") <= 100)
- CHECK(length("Table") <= 50)
- CHECK(length("EditField") <= 100)
*/
