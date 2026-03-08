library(duckdb)
library(dplyr)
library(DBI)

# This script creates main tables (without Sample prefix) from their Sample_* counterparts
# Should be run after 01_build_database.R and before 02_create_views.R

db_path <- file.path(getwd(), "data/vpro.duckdb")

cat("\n=== Creating Main Tables (from Sample_* prefix) ===\n")

con <- dbConnect(duckdb(), db_path)
on.exit(dbDisconnect(con, shutdown = TRUE))

# Mapping of Sample_* tables to their main table names
table_mappings <- list(
  list(from = "Admin", to = "Admin"),
  list(from = "Audit", to = "Audit"),
  list(from = "Env", to = "Env"),
  list(from = "Herbarium", to = "Herbarium"),
  list(from = "Hierarchy", to = "Hierarchy"),
  list(from = "Humus", to = "Humus"),
  list(from = "Lump", to = "Lump"),
  list(from = "Metadata", to = "Metadata"),
  list(from = "Mineral", to = "Mineral"),
  list(from = "Other", to = "Other"),
  list(from = "Profile", to = "Profile"),
  list(from = "SU", to = "SU"),
  list(from = "Theme", to = "Theme"),
  list(from = "Veg", to = "Veg"),
  list(from = "SampleVeg_Profile", to = "Veg_Profile")
)

for (mapping in table_mappings) {
  from_table <- mapping$from
  to_table <- mapping$to
  
  tryCatch({
    # Check if source table exists
    if (!dbExistsTable(con, from_table)) {
      cat("  [SKIP] Source table", from_table, "does not exist.\n")
      next
    }
    
    # Drop target table if it exists
    dbExecute(con, paste0("DROP TABLE IF EXISTS ", to_table))
    
    # Create table as copy
    query <- paste0("CREATE TABLE ", to_table, " AS SELECT * FROM ", from_table)
    dbExecute(con, query)
    
    # Get row count
    rows <- dbGetQuery(con, paste0("SELECT COUNT(*) as n FROM ", to_table))$n
    cat("  [OK] Created", to_table, "from", from_table, ":", rows, "rows\n")
    
  }, error = function(e) {
    cat("  [ERROR] Creating", to_table, "from", from_table, ":", e$message, "\n")
  })
}

cat("Main tables created successfully.\n")
