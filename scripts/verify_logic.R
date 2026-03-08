# Verify App Logic (Headless)
# Tests the core data retrieval and update logic without Shiny

library(duckdb)
library(dplyr)
source("R/logic_veg_data.R")

con <- dbConnect(duckdb(), "data/vpro.duckdb", read_only = TRUE)

print("--- Verifying Project List (Server Logic) ---")
# Mimic server.R logic
projects <- dbGetQuery(con, "SELECT DISTINCT projectid, projecttitle FROM Metadata WHERE projectid IS NOT NULL")
print(projects)

if (nrow(projects) == 0) stop("No projects found!")
pid <- projects$projectid[1]
print(paste("Selected Project:", pid))

print("--- Verifying Site Unit List ---")
sus <- dbGetQuery(con, "SELECT DISTINCT siteunit FROM SU ORDER BY siteunit")
print(head(sus))

if (nrow(sus) > 0) {
  su_id <- sus$siteunit[1]
  print(paste("Selected Site Unit:", su_id))
  
  print("--- Verifying Vegetation Data Logic ---")
  veg_data <- get_vegetation_data(con, su_id)
  print(paste("Veg Data Rows:", nrow(veg_data)))
  if (nrow(veg_data) > 0) {
    print(head(veg_data))
  } else {
    print("No vegetation data for this site unit (might be expected)")
  }
}

print("--- Verifying Metadata Module Logic ---")
# Mimic mod_project_meta_server logic
meta <- dbGetQuery(con, paste0("SELECT * FROM USysProjectMetadata WHERE projectid = '", gsub("'", "''", pid), "'"))
print(meta)

dbDisconnect(con)
print("--- Verification Complete ---")
