CREATE TABLE "USysRibbonDescriptions" (
  "ID" INTEGER,
  "ControlName" TEXT NOT NULL,
  "Description" TEXT
);

CREATE UNIQUE INDEX "uidx_USysRibbonDescriptions_ControlName" ON "USysRibbonDescriptions" ("ControlName");
CREATE INDEX "idx_USysRibbonDescriptions_ID" ON "USysRibbonDescriptions" ("ID");
