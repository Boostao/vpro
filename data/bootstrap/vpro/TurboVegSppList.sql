CREATE TABLE "TurboVegSppList" (
  "SppID" INTEGER,
  "SppCode" TEXT,
  "SppLongName" TEXT,
  "SppList" TEXT
);

CREATE INDEX "idx_TurboVegSppList_SppCode" ON "TurboVegSppList" ("SppCode");
CREATE UNIQUE INDEX "uidx_TurboVegSppList_SppID" ON "TurboVegSppList" ("SppID");
