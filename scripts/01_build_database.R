library(duckdb)
library(dplyr)
library(fs)
library(stringr)

# Configuration mapping: Source Dir -> Target DB
config <- list(
  list(src = "VPRO_ACCESS/VPro64_forAI/Tables_Data", db = "data/vpro.duckdb"),
  list(src = "VPRO_ACCESS/VLists/Tables_Data", db = "data/vpro_lists.duckdb"),
  list(src = "VPRO_ACCESS/VMetaData/Tables_Data", db = "data/vpro_metadata.duckdb"),
  list(src = "VPRO_ACCESS/VUser/Tables_Data", db = "data/vpro_user.duckdb"),
  list(src = "VPRO_ACCESS/VMessageBoard/Tables_Data", db = "data/vpro_messages.duckdb")
)

clean_colnames <- function(names) {
  names %>%
    str_replace_all("[^[:alnum:]_]", "_") %>% # Replace non-alphanumeric with _
    str_replace_all("_+", "_") %>%           # Deduplicate _
    str_remove_all("^_|_$") %>%              # Remove leading/trailing _
    tolower()                                # Lowercase
}

# Create data directory if it doesn't exist
if (!dir.exists("data")) {
  dir.create("data", recursive = TRUE)
}

for (cfg in config) {
  source_dir <- file.path(getwd(), cfg$src)
  db_path <- file.path(getwd(), cfg$db)
  
  cat("\n=== Building Database:", cfg$db, "===\n")
  cat("Source:", source_dir, "\n")
  
  if (!dir.exists(source_dir)) {
    cat("WARNING: Source directory does not exist. Skipping.\n")
    next
  }

  con <- dbConnect(duckdb(), db_path)
  
  csv_files <- list.files(source_dir, pattern = "\\.csv$", full.names = TRUE)
  cat("Found", length(csv_files), "CSV files.\n")
  
  if (length(csv_files) > 0) {
    for (file_path in csv_files) {
      table_name <- tools::file_path_sans_ext(basename(file_path))
      
      tryCatch({
          # Write table
          # We use read_csv_auto for robust type inference
          # and immediately create the table
          
          # Drop if exists
          dbExecute(con, paste0("DROP TABLE IF EXISTS ", table_name))
          
          # Read and Write
          # Note: DuckDB's read_csv_auto is very powerful
          # Fallback to LATIN1 for Access exports if clean UTF8 fails.
          query <- sprintf("CREATE TABLE %s AS SELECT * FROM read_csv_auto('%s', normalize_names=TRUE, ignore_errors=TRUE)", 
                           table_name, file_path)
          dbExecute(con, query)
          
          rows <- dbGetQuery(con, paste0("SELECT COUNT(*) as n FROM ", table_name))$n
          cat("  [OK] ", table_name, ": ", rows, " rows\n")
          
      }, error = function(e) {
          cat("  [ERROR] ", table_name, ": ", e$message, "\n")
      })
    }
  }
  
  dbDisconnect(con, shutdown = TRUE)
}
