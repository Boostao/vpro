CREATE TABLE "tblMessageList" (
  "ID" INTEGER PRIMARY KEY,
  "MessageID" INTEGER,
  "Read" BOOLEAN
);

CREATE INDEX "idx_tblMessageList_ID" ON "tblMessageList" ("ID");
CREATE UNIQUE INDEX "uidx_tblMessageList_MessageID" ON "tblMessageList" ("MessageID");
