CREATE TABLE "Attribute_Lump" (
  "LumpCode" TEXT,
  "SppCode" TEXT,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Attribute_Lump_LumpCode" ON "Attribute_Lump" ("LumpCode");
CREATE INDEX "idx_Attribute_Lump_SppCode" ON "Attribute_Lump" ("SppCode");
