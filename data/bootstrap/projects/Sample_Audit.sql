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
  "ID" INTEGER
);

CREATE INDEX "idx_Audit_EditWhen" ON "Audit" ("EditWhen");
CREATE INDEX "idx_Audit_ID" ON "Audit" ("ID");
