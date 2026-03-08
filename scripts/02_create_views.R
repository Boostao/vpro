library(duckdb)
library(dplyr)
library(DBI)

# Configuration
db_path <- file.path(getwd(), "data/vpro.duckdb")
con <- dbConnect(duckdb(), db_path)
on.exit(dbDisconnect(con, shutdown = TRUE))

cat("Connected to database.\n")

# --- 1. vw_USysAllVeg (The Unpivot Logic) ---
# Replicates Queries/USysAllVeg.txt
# Unions specific Cover columns and Total strings to create a normalized list
cat("Creating View vw_USysAllVeg...\n")

sql_usysallveg <- "
CREATE OR REPLACE VIEW vw_USysAllVeg AS
SELECT PlotNumber, '1' AS MyLayer, Species, CAST(Cover1 AS VARCHAR) as Cover FROM Veg WHERE Cover1 IS NOT NULL
UNION ALL
SELECT PlotNumber, '2' AS MyLayer, Species, CAST(Cover2 AS VARCHAR) as Cover FROM Veg WHERE Cover2 IS NOT NULL
UNION ALL
SELECT PlotNumber, '3' AS MyLayer, Species, CAST(Cover3 AS VARCHAR) as Cover FROM Veg WHERE Cover3 IS NOT NULL
UNION ALL
SELECT PlotNumber, '4' AS MyLayer, Species, CAST(Cover4 AS VARCHAR) as Cover FROM Veg WHERE Cover4 IS NOT NULL
UNION ALL
SELECT PlotNumber, '5' AS MyLayer, Species, CAST(Cover5 AS VARCHAR) as Cover FROM Veg WHERE Cover5 IS NOT NULL
UNION ALL
SELECT PlotNumber, '5a' AS MyLayer, Species, CAST(Cover5a AS VARCHAR) as Cover FROM Veg WHERE Cover5a IS NOT NULL
UNION ALL
SELECT PlotNumber, '5b' AS MyLayer, Species, CAST(Cover5b AS VARCHAR) as Cover FROM Veg WHERE Cover5b IS NOT NULL
UNION ALL
SELECT PlotNumber, '5c' AS MyLayer, Species, CAST(Cover5c AS VARCHAR) as Cover FROM Veg WHERE Cover5c IS NOT NULL
UNION ALL
SELECT PlotNumber, '6' AS MyLayer, Species, CAST(Cover6 AS VARCHAR) as Cover FROM Veg WHERE Cover6 IS NOT NULL
UNION ALL
SELECT PlotNumber, '7' AS MyLayer, Species, CAST(Cover7 AS VARCHAR) as Cover FROM Veg WHERE Cover7 IS NOT NULL
UNION ALL
SELECT PlotNumber, '8' AS MyLayer, Species, CAST(Cover8 AS VARCHAR) as Cover FROM Veg WHERE Cover8 IS NOT NULL
UNION ALL
SELECT PlotNumber, '9' AS MyLayer, Species, CAST(Cover9 AS VARCHAR) as Cover FROM Veg WHERE Cover9 IS NOT NULL
UNION ALL
SELECT PlotNumber, '10' AS MyLayer, Species, CAST(Cover10 AS VARCHAR) as Cover FROM Veg WHERE Cover10 IS NOT NULL
UNION ALL
SELECT PlotNumber, 'A' AS MyLayer, Species, CAST(TotalA AS VARCHAR) as Cover FROM Veg WHERE TotalA IS NOT NULL
UNION ALL
SELECT PlotNumber, 'B' AS MyLayer, Species, CAST(TotalB AS VARCHAR) as Cover FROM Veg WHERE TotalB IS NOT NULL;
"

tryCatch({
  dbExecute(con, sql_usysallveg)
  cat("View vw_USysAllVeg created.\n")
}, error = function(e) {
  cat("Error creating vw_USysAllVeg: ", conditionMessage(e), "\n")
})

# --- 2. vw_USysEnv (The Master Site Record) ---
# Access-parity: Queries/USysEnv.txt
#   SELECT DISTINCTROW [Env].*, [Admin].*
#   FROM Env INNER JOIN Admin ON [Env].PlotNumber = [Admin].Plot
#
# Column audit (no collisions between Env and Admin confirmed):
#   Env  join key : plotnumber
#   Admin join key: plot  → aliased as admin_plot
#   Quality columns added: siteplotquality, vegplotquality, soilplotquality
cat("Creating View vw_USysEnv...\n")

tryCatch({
  dbExecute(con, "
    CREATE OR REPLACE VIEW vw_USysEnv AS
    SELECT
      e.*,
      a.plot               AS admin_plot,
      a.startdate,
      a.plottype,
      a.plotsize,
      a.provincestateterritory,
      a.siteplotquality,
      a.vegplotquality,
      a.soilplotquality,
      a.updatedfromcards,
      a.enteredby,
      a.usersiteunit,
      a.becsiteunit,
      a.siteunitshortname,
      a.siteunitlongname,
      a.officenotes,
      a.humusthickness,
      a.gis_bgc,
      a.gis_bgc_ver,
      a.bec_use,
      a.stratacovertotal
    FROM Env e
    INNER JOIN Admin a ON e.plotnumber = a.plot
  ")
  cat("View vw_USysEnv created (Access-parity: Env INNER JOIN Admin).\n")
}, error = function(e) {
  cat("Error creating vw_USysEnv: ", conditionMessage(e), "\n")
})

# Verify
cat("Verifying Views...\n")
if (dbExistsTable(con, "vw_USysAllVeg")) {
  print(dbGetQuery(con, "SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg LIMIT 5"))
}
if (dbExistsTable(con, "vw_USysEnv")) {
  cols <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'vw_USysEnv' ORDER BY ordinal_position")
  cat("vw_USysEnv columns (", nrow(cols), "):\n")
  cat(paste(cols$column_name, collapse = ", "), "\n")
  # Confirm quality cols present
  qc_present <- all(c("siteplotquality", "vegplotquality", "soilplotquality") %in% cols$column_name)
  cat("Quality columns present:", qc_present, "\n")
}
