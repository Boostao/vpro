CREATE TABLE "LifeformCodes" (
  "Lifeform" INTEGER,
  "LifeformTXT" TEXT,
  "Definition" TEXT,
  "Comments" TEXT,
  "ShortName" TEXT,
  "Vascular" BOOLEAN DEFAULT FALSE
);

CREATE UNIQUE INDEX "uidx_LifeformCodes_Lifeform" ON "LifeformCodes" ("Lifeform");
