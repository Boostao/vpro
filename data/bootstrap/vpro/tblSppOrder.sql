CREATE TABLE "tblSppOrder" (
  "SppID" INTEGER,
  "SppOrder" INTEGER,
  "Layer" TEXT
);

CREATE UNIQUE INDEX "uidx_tblSppOrder_SppID_SppOrder_Layer" ON "tblSppOrder" ("SppID", "SppOrder", "Layer");
CREATE INDEX "idx_tblSppOrder_SppID" ON "tblSppOrder" ("SppID");
