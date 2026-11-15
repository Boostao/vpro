CREATE TABLE "USysAudit" (
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

CREATE INDEX "idx_USysAudit_ID" ON "USysAudit" ("ID");
