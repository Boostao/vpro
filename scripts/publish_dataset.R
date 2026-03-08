# BEC Web Map - Public Data Publishing
#
# This script demonstrates how to publish datasets for the BEC Map Explorer
# Published datasets are stored in data/published/ and consumed by the 
# mod_becweb_map module for public browsing.
#
# Dataset Format:
#   - <project_id>_environment.rds: Plot location + environmental data
#   - <project_id>_vegetation.rds: Species cover data
#   - <project_id>_metadata.rds: Project metadata (title, is_public flag)
#
# Usage:
#   Rscript scripts/publish_dataset.R <project_id>
#
# Example:
#   Rscript scripts/publish_dataset.R TEST001

library(duckdb)
library(dplyr)

# Get project ID from command line
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript scripts/publish_dataset.R <project_id>")
}

project_id <- args[1]
cat("Publishing dataset for project:", project_id, "\n")

# Connect to VPRO databases
con <- dbConnect(duckdb(), "data/vpro.duckdb")
dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
dbExecute(con, "ATTACH 'data/vpro_metadata.duckdb' AS metadata_db")

# Create output directory
pub_dir <- "data/published"
if (!dir.exists(pub_dir)) {
  dir.create(pub_dir, recursive = TRUE)
}

# --- 1. Extract Environment Data ---
cat("Extracting environment data...\n")

env_sql <- "
  SELECT 
    e.plotnumber,
    e.date_sampled,
    e.latitude,
    e.longitude,
    e.bec_zone,
    e.bec_subzone,
    e.bec_site_series,
    e._location,
    s.dataquality AS data_quality
  FROM Env e
  LEFT JOIN SU s ON e.plotnumber = s.plotnumber
  WHERE e.projectid = ?
    AND e.latitude IS NOT NULL 
    AND e.longitude IS NOT NULL
"

env_data <- dbGetQuery(con, env_sql, list(project_id))
cat("  Found", nrow(env_data), "plots with coordinates\n")

if (nrow(env_data) > 0) {
  env_path <- file.path(pub_dir, paste0(project_id, "_environment.rds"))
  saveRDS(env_data, env_path)
  cat("  Saved:", env_path, "\n")
}

# --- 2. Extract Vegetation Data ---
cat("Extracting vegetation data...\n")

veg_sql <- "
  SELECT 
    plotnumber AS plot_id,
    code AS species_code,
    layer,
    cover
  FROM vw_USysAllVeg
  WHERE projectid = ?
    AND code IS NOT NULL
"

veg_data <- dbGetQuery(con, veg_sql, list(project_id))
cat("  Found", nrow(veg_data), "vegetation records\n")

if (nrow(veg_data) > 0) {
  veg_path <- file.path(pub_dir, paste0(project_id, "_vegetation.rds"))
  saveRDS(veg_data, veg_path)
  cat("  Saved:", veg_path, "\n")
}

# --- 3. Extract Project Metadata ---
cat("Extracting project metadata...\n")

meta_sql <- "
  SELECT 
    projectid AS project_id,
    projecttitle AS project_name,
    CASE WHEN ispublic = 'True' THEN TRUE ELSE FALSE END AS is_public,
    beczone AS primary_bec_zone,
    description
  FROM metadata_db.tbl_Projects
  WHERE projectid = ?
"

meta_data <- dbGetQuery(con, meta_sql, list(project_id))

if (nrow(meta_data) == 0) {
  # Fallback: create minimal metadata
  meta_data <- data.frame(
    project_id = project_id,
    project_name = project_id,
    is_public = TRUE,
    primary_bec_zone = NA,
    description = "Published dataset",
    stringsAsFactors = FALSE
  )
}

meta_path <- file.path(pub_dir, paste0(project_id, "_metadata.rds"))
saveRDS(meta_data, meta_path)
cat("  Saved:", meta_path, "\n")

# Close connection
dbDisconnect(con, shutdown = TRUE)

cat("\n✅ Dataset published successfully!\n")
cat("Files created in", pub_dir, ":\n")
cat("  •", paste0(project_id, "_environment.rds\n"))
cat("  •", paste0(project_id, "_vegetation.rds\n"))
cat("  •", paste0(project_id, "_metadata.rds\n"))
cat("\nThe BEC Map Explorer will now include this dataset.\n")
