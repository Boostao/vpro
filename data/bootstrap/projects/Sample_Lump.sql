-- Access table description: VP05
CREATE TABLE "Lump" (
  "LumpCode" VARCHAR,
  "SppCode" VARCHAR,
  "Use" BOOLEAN
);

CREATE INDEX "idx_Lump_LumpCode" ON "Lump" ("LumpCode");
CREATE UNIQUE INDEX "uidx_Lump_SppCode" ON "Lump" ("SppCode");

/*
Access metadata notes for Lump:
- Table Description: VP05
- SppCode: Unique in Access.
- Access exported the Lump -> Veg species relationship as unenforced, so no foreign key was added here.
Potential write constraints to consider later:
- CHECK(length("LumpCode") <= 50)
- CHECK(length("SppCode") <= 8)
*/
