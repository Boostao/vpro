CREATE TABLE "LayerCode" (
  "LayerCode" TEXT,
  "Layer1234567" TEXT,
  "LayerCompact" TEXT,
  "Layer" TEXT,
  "LayerText" TEXT,
  "Strata" TEXT,
  "StrataNum" INTEGER,
  "Lifeform" TEXT
);

CREATE UNIQUE INDEX "uidx_LayerCode_Layer1234567" ON "LayerCode" ("Layer1234567");
CREATE UNIQUE INDEX "uidx_LayerCode_LayerCode" ON "LayerCode" ("LayerCode");
CREATE INDEX "idx_LayerCode_StrataNum" ON "LayerCode" ("StrataNum");
