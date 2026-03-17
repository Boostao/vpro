-- Access table description: VP04
CREATE TABLE "SU" (
  "PlotNumber" VARCHAR,
  "SiteUnit" VARCHAR
);

CREATE UNIQUE INDEX "uidx_SU_PlotNumber" ON "SU" ("PlotNumber");
CREATE INDEX "idx_SU_SiteUnit" ON "SU" ("SiteUnit");

/*
Access metadata notes for SU:
- Table Description: VP04
- Access exported PlotNumber as unique but not required.
- The SU -> Env relationship was not enforced in Access, so no foreign key was added here.
Potential write constraints to consider later:
- CHECK(length("PlotNumber") <= 7)
- CHECK(length("SiteUnit") <= 255)
*/
