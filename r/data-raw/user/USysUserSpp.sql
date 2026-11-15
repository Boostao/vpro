-- Access table description: VP05
CREATE TABLE "USysUserSpp" (
  "Code" TEXT NOT NULL,
  "ScientificName" TEXT,
  "LifeForm" INTEGER,
  "EnglishName" TEXT,
  "Report" REAL DEFAULT 1,
  "SppNumber" INTEGER,
  "Codetype" TEXT
);

CREATE UNIQUE INDEX "uidx_USysUserSpp_Code" ON "USysUserSpp" ("Code");
CREATE INDEX "idx_USysUserSpp_Codetype" ON "USysUserSpp" ("Codetype");
