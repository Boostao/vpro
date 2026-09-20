CREATE TABLE "USysSuTableDynamic_SU" (
  "PlotNumber" TEXT,
  "SiteUnit" TEXT,
  "Group" TEXT,
  "Level" INTEGER
);

CREATE INDEX "idx_USysSuTableDynamic_SU_PlotNumber" ON "USysSuTableDynamic_SU" ("PlotNumber");
CREATE INDEX "idx_USysSuTableDynamic_SU_SiteUnit" ON "USysSuTableDynamic_SU" ("SiteUnit");
