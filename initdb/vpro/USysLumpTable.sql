CREATE TABLE "USysLumpTable" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "Use" BOOLEAN
);

CREATE INDEX "idx_USysLumpTable_LumpCode" ON "USysLumpTable" ("LumpCode");
CREATE INDEX "idx_USysLumpTable_SppCode" ON "USysLumpTable" ("SppCode");
