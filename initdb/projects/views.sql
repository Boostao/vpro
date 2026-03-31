-- ============================================================
CREATE VIEW "UsysAuditTrail" AS
SELECT DISTINCT
  "Sample_Audit".*
FROM "Sample_Audit"
ORDER BY "EditWhen";


-- ============================================================
CREATE VIEW "UsysEnv" AS
SELECT DISTINCT
  "Sample_Env".*,
  "Sample_Admin".*
FROM "Sample_Env"
INNER JOIN "Sample_Admin"
  ON "Sample_Env"."PlotNumber" = "Sample_Admin"."Plot"
ORDER BY "UsysEnv"."PlotNumber";


-- ============================================================
CREATE VIEW "Filtered_Env" AS
SELECT DISTINCT
  "Sample_Env".*,
  "Sample_Admin".*
FROM "Sample_Env"
INNER JOIN "Sample_SU"
  ON "Sample_Env"."PlotNumber" = "Sample_SU"."PlotNumber"
INNER JOIN "Sample_Admin"
  ON "Sample_Env"."PlotNumber" = "Sample_Admin"."Plot"
WHERE "Sample_SU"."PlotNumber" IS NOT NULL;


-- ============================================================
CREATE VIEW "UsysHumus" AS
SELECT DISTINCT
  "Sample_Humus".*
FROM "Sample_Humus";


-- ============================================================
CREATE VIEW "UsysMetadata" AS
SELECT DISTINCT
  "Sample_Metadata".*
FROM "Sample_Metadata";


-- ============================================================
CREATE VIEW "UsysMineral" AS
SELECT DISTINCT
  "Sample_Mineral".*
FROM "Sample_Mineral";


-- ============================================================
CREATE VIEW "UsysOther" AS
SELECT DISTINCT
  "Sample_Other".*
FROM "Sample_Other";


-- ============================================================
CREATE VIEW "UsysVeg" AS
SELECT DISTINCT
  "Sample_Veg".*
FROM "Sample_Veg";


-- ============================================================
CREATE VIEW "USysVegA" AS
SELECT DISTINCT
  "ID",
  "PlotNumber",
  "Species",
  "Cover1",
  "Cover2",
  "Cover3",
  "TotalA",
  "HeightA",
  "Cover4",
  "Cover5",
  "Cover5a",
  "Cover5b",
  "Cover5c",
  "TotalB",
  "HeightB",
  "Collected"
FROM "Sample_Veg"
WHERE "Cover1" IS NOT NULL
   OR "Cover2" IS NOT NULL
   OR "Cover3" IS NOT NULL
   OR "TotalA" IS NOT NULL
   OR "Cover4" IS NOT NULL
   OR "Cover5" IS NOT NULL
   OR "TotalB" IS NOT NULL
   OR "Cover5a" IS NOT NULL
   OR "Cover5b" IS NOT NULL
   OR "Cover5c" IS NOT NULL;


-- ============================================================
CREATE VIEW "USysVegB" AS
SELECT DISTINCT
  "ID",
  "PlotNumber",
  "Species",
  "Cover4",
  "Cover5",
  "Cover5a",
  "Cover5b",
  "Cover5c",
  "TotalB",
  "Collected"
FROM "Sample_Veg"
WHERE "Cover4" IS NOT NULL
   OR "Cover5" IS NOT NULL
   OR "TotalB" IS NOT NULL
   OR "Cover5a" IS NOT NULL
   OR "Cover5b" IS NOT NULL
   OR "Cover5c" IS NOT NULL;


-- ============================================================
CREATE VIEW "USysVegC" AS
SELECT DISTINCT
  "ID",
  "PlotNumber",
  "Species",
  "Cover6",
  "Height6",
  "Collected"
FROM "Sample_Veg"
WHERE "Cover6" IS NOT NULL;


-- ============================================================
CREATE VIEW "USysVegD" AS
SELECT DISTINCT
  "ID",
  "PlotNumber",
  "Species",
  "Cover7",
  "Cover8",
  "Cover9",
  "Collected"
FROM "Sample_Veg"
WHERE "Cover7" IS NOT NULL
   OR "Cover8" IS NOT NULL
   OR "Cover9" IS NOT NULL;


-- ============================================================
CREATE VIEW "USysVegOther" AS
SELECT
  "PlotNumber",
  "Species",
  "LL",
  "AF",
  "DC",
  "UT",
  "VI",
  "PV",
  "PG",
  "FFA",
  "Cultural1",
  "Cultural2",
  "Other1",
  "Other2"
FROM "UsysVeg";


-- ============================================================
CREATE VIEW "USysAllVeg" AS
SELECT "PlotNumber", '1' AS "MyLayer", "Species", "Cover1" AS "Cover" FROM "UsysVeg" WHERE "Cover1" IS NOT NULL
UNION
SELECT "PlotNumber", '2' AS "MyLayer", "Species", "Cover2" AS "Cover" FROM "UsysVeg" WHERE "Cover2" IS NOT NULL
UNION
SELECT "PlotNumber", '3' AS "MyLayer", "Species", "Cover3" AS "Cover" FROM "UsysVeg" WHERE "Cover3" IS NOT NULL
UNION
SELECT "PlotNumber", '4' AS "MyLayer", "Species", "Cover4" AS "Cover" FROM "UsysVeg" WHERE "Cover4" IS NOT NULL
UNION
SELECT "PlotNumber", '5' AS "MyLayer", "Species", "Cover5" AS "Cover" FROM "UsysVeg" WHERE "Cover5" IS NOT NULL
UNION
SELECT "PlotNumber", '5a' AS "MyLayer", "Species", "Cover5a" AS "Cover" FROM "UsysVeg" WHERE "Cover5a" IS NOT NULL
UNION
SELECT "PlotNumber", '5b' AS "MyLayer", "Species", "Cover5b" AS "Cover" FROM "UsysVeg" WHERE "Cover5b" IS NOT NULL
UNION
SELECT "PlotNumber", '5c' AS "MyLayer", "Species", "Cover5c" AS "Cover" FROM "UsysVeg" WHERE "Cover5c" IS NOT NULL
UNION
SELECT "PlotNumber", '6' AS "MyLayer", "Species", "Cover6" AS "Cover" FROM "UsysVeg" WHERE "Cover6" IS NOT NULL
UNION
SELECT "PlotNumber", '7' AS "MyLayer", "Species", "Cover7" AS "Cover" FROM "UsysVeg" WHERE "Cover7" IS NOT NULL
UNION
SELECT "PlotNumber", 'A' AS "MyLayer", "Species", "TotalA" AS "Cover" FROM "UsysVeg" WHERE "TotalA" IS NOT NULL
UNION
SELECT "PlotNumber", 'B' AS "MyLayer", "Species", "TotalB" AS "Cover" FROM "UsysVeg" WHERE "TotalB" IS NOT NULL
ORDER BY "MyLayer";


-- ============================================================
CREATE VIEW "USysTVeg" AS
SELECT "PlotNumber", '1' AS "MyLayer", "Species", "Cover1" AS "Cover" FROM "UsysVeg" WHERE "Cover1" IS NOT NULL
UNION
SELECT "PlotNumber", '2' AS "MyLayer", "Species", "Cover2" AS "Cover" FROM "UsysVeg" WHERE "Cover2" IS NOT NULL
UNION
SELECT "PlotNumber", '3' AS "MyLayer", "Species", "Cover3" AS "Cover" FROM "UsysVeg" WHERE "Cover3" IS NOT NULL
UNION
SELECT "PlotNumber", '4' AS "MyLayer", "Species", "Cover4" AS "Cover" FROM "UsysVeg" WHERE "Cover4" IS NOT NULL
UNION
SELECT "PlotNumber", '5' AS "MyLayer", "Species", "Cover5" AS "Cover" FROM "UsysVeg" WHERE "Cover5" IS NOT NULL
UNION
SELECT "PlotNumber", '6' AS "MyLayer", "Species", "Cover6" AS "Cover" FROM "UsysVeg" WHERE "Cover6" IS NOT NULL
UNION
SELECT "PlotNumber", '7' AS "MyLayer", "Species", "Cover7" AS "Cover" FROM "UsysVeg" WHERE "Cover7" IS NOT NULL
UNION
SELECT "PlotNumber", 'A' AS "MyLayer", "Species", "TotalA" AS "Cover" FROM "UsysVeg" WHERE "TotalA" IS NOT NULL
UNION
SELECT "PlotNumber", 'B' AS "MyLayer", "Species", "TotalB" AS "Cover" FROM "UsysVeg" WHERE "TotalB" IS NOT NULL
ORDER BY "PlotNumber", "MyLayer";


-- ============================================================
CREATE VIEW "qryHerbarium" AS
SELECT *
FROM "Sample_Herbarium";


-- ============================================================
CREATE VIEW "qryHerbariumReportData" AS
SELECT
  "qryHerbarium"."Species",
  "qryHerbarium"."ScientificNameRich",
  "qryHerbarium"."Habitat",
  "qryHerbarium"."Comments",
  "qryHerbarium"."LocationDescription",
  "UsysEnv"."Latitude",
  "UsysEnv"."Longitude",
  "UsysEnv"."Elevation",
  "qryHerbarium"."Collectors",
  "qryHerbarium"."DateOfCollection",
  "qryHerbarium"."CollectionNumber",
  "qryHerbarium"."Identifier",
  "qryHerbarium"."Print"
FROM "UsysEnv"
INNER JOIN "qryHerbarium"
  ON "UsysEnv"."PlotNumber" = "qryHerbarium"."PlotNumber"
WHERE "qryHerbarium"."Print" = 1;