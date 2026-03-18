-- Access table description: VP04
CREATE TABLE "Sample_SU" (
  "PlotNumber" VARCHAR,
  "SiteUnit" VARCHAR
);

CREATE UNIQUE INDEX "uidx_Sample_SU_PlotNumber" ON "Sample_SU" ("PlotNumber");
CREATE INDEX "idx_Sample_SU_SiteUnit" ON "Sample_SU" ("SiteUnit");

/*
Access metadata notes for Sample_SU:
- Table Description: VP04
- Access exported PlotNumber as unique but not required.
- The SU -> Env relationship was not enforced in Access, so no foreign key was added here.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(length("SiteUnit") <= 255)
*/
