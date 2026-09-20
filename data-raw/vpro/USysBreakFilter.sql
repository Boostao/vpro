CREATE TABLE "USysBreakFilter" (
  "Level" TEXT,
  "Parent" TEXT,
  "Unit" TEXT
);

CREATE INDEX "idx_USysBreakFilter_Parent" ON "USysBreakFilter" ("Parent");
CREATE INDEX "idx_USysBreakFilter_Unit" ON "USysBreakFilter" ("Unit");
