CREATE TABLE "Lump" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Lump_LumpCode" ON "Lump" ("LumpCode");
CREATE UNIQUE INDEX "uidx_Lump_SppCode" ON "Lump" ("SppCode");
