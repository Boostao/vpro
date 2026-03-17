-- ============================================================
CREATE VIEW "UsysAuditTrail" AS
SELECT DISTINCT
  "Audit".*
FROM "Audit"
ORDER BY "EditWhen";


-- ============================================================
CREATE VIEW "UsysEnv" AS
SELECT DISTINCT
  "Env".*,
  "Admin".*
FROM "Env"
INNER JOIN "Admin"
  ON "Env"."PlotNumber" = "Admin"."Plot";


-- ============================================================
CREATE VIEW "Filtered_Env" AS
SELECT DISTINCT
  "Env".*,
  "Admin".*
FROM "Env"
INNER JOIN "SU"
  ON "Env"."PlotNumber" = "SU"."PlotNumber"
INNER JOIN "Admin"
  ON "Env"."PlotNumber" = "Admin"."Plot"
WHERE "SU"."PlotNumber" IS NOT NULL;


-- ============================================================
CREATE VIEW "UsysHumus" AS
SELECT DISTINCT
  "Humus".*
FROM "Humus";


-- ============================================================
CREATE VIEW "UsysMetadata" AS
SELECT DISTINCT
  "Metadata".*
FROM "Metadata";


-- ============================================================
CREATE VIEW "UsysMineral" AS
SELECT DISTINCT
  "Mineral".*
FROM "Mineral";


-- ============================================================
CREATE VIEW "UsysOther" AS
SELECT DISTINCT
  "Other".*
FROM "Other";


-- ============================================================
CREATE VIEW "UsysVeg" AS
SELECT DISTINCT
  "Veg".*
FROM "Veg";


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
FROM "Veg"
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
FROM "Veg"
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
FROM "Veg"
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
FROM "Veg"
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
FROM "Herbarium";


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