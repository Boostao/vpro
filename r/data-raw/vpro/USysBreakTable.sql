CREATE TABLE "USysBreakTable" (
  "Order" INTEGER,
  "Reference" TEXT,
  "BreakCode" TEXT,
  "PlotNumber" TEXT
);

CREATE INDEX "idx_USysBreakTable_BreakCode" ON "USysBreakTable" ("BreakCode");
