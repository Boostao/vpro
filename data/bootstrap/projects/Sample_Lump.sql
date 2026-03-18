-- Access table description: VP05
CREATE TABLE "Sample_Lump" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Sample_Lump_LumpCode" ON "Sample_Lump" ("LumpCode");
CREATE UNIQUE INDEX "uidx_Sample_Lump_SppCode" ON "Sample_Lump" ("SppCode");

/*
Access metadata notes for Sample_Lump:
- Table Description: VP05
- SppCode: Unique in Access.
- Access exported the Lump -> Veg species relationship as unenforced, so no foreign key was added here.
Potential write constraints to consider later:
- CHECK(length("LumpCode") <= 50)
- CHECK(length("SppCode") <= 8)
*/
