-- Access table description: VP03
CREATE TABLE "USysRegInfo" (
  "Subkey" TEXT,
  "Type" INTEGER,
  "ValName" TEXT,
  "Value" TEXT
);

CREATE INDEX "idx_USysRegInfo_Subkey" ON "USysRegInfo" ("Subkey");
