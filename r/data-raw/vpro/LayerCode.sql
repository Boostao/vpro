CREATE TABLE "LayerCode" (
  "LayerCode" TEXT, -- 1 2 3 4 5 6 7 8 9 10 11 12 13
  "Layer1234567" TEXT,
  "LayerCompact" TEXT, -- Apr. 7, 2020 RK
  "Layer" TEXT, -- A1, A2, A3, B1, B2, C, D
  "LayerText" TEXT,
  "Strata" TEXT, -- A, B, C, D
  "StrataNum" INTEGER, -- 1, 2, 3, 4
  "Lifeform" TEXT
);

CREATE UNIQUE INDEX "uidx_LayerCode_Layer1234567" ON "LayerCode" ("Layer1234567");
CREATE UNIQUE INDEX "uidx_LayerCode_LayerCode" ON "LayerCode" ("LayerCode");
CREATE INDEX "idx_LayerCode_StrataNum" ON "LayerCode" ("StrataNum");
