CREATE TABLE "tblHelpSubjects" (
  "Order" INTEGER,
  "Topic" TEXT,
  "File" TEXT
);

CREATE INDEX "idx_tblHelpSubjects_Order" ON "tblHelpSubjects" ("Order");
