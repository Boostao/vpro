CREATE TABLE "USysMasterAudit" (
  "User" TEXT,
  "Action" TEXT,
  "NodeName" TEXT,
  "NodeID" INTEGER,
  "Parent" TEXT,
  "EditField" TEXT,
  "EditWhen" TIMESTAMP,
  "BeforeEdit" TEXT,
  "AfterEdit" TEXT,
  "Restore" BOOLEAN,
  "Flag" BOOLEAN,
  "ID" INTEGER
);

CREATE INDEX "idx_USysMasterAudit_ID" ON "USysMasterAudit" ("ID");
CREATE INDEX "idx_USysMasterAudit_NodeID" ON "USysMasterAudit" ("NodeID");

