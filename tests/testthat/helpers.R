# Test Helpers - Common utilities for all tests

#' Create Test DuckDB Connection
#'
#' Creates a fresh DuckDB connection from local test data.
#' Uses temporary file to avoid polluting dev database.
#'
#' @return DBI connection object
#'
test_connect_duckdb <- function() {
  message("[test-helpers] Creating DuckDB test connection")
  
  # Use in-memory DuckDB for fast tests (no persistence needed)
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  
  # Initialize schema by running SQL statements
  initialize_test_schema(con)
  
  return(con)
}

#' Initialize Test Schema in DuckDB
#'
#' Creates minimal tables for testing without full postgres dependency
#'
#' @param con DBI connection object
#'
initialize_test_schema <- function(con) {
  message("[test-helpers] Initializing test schema")
  
  # Create minimal schema for testing
  DBI::dbExecute(con, "
    CREATE SCHEMA IF NOT EXISTS lists
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.spplist (
      spp_code TEXT PRIMARY KEY,
      spp_name TEXT NOT NULL,
      spp_scientific TEXT,
      is_active BOOLEAN DEFAULT TRUE
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.usyszonelist (
      zone_code TEXT PRIMARY KEY,
      zone_name TEXT NOT NULL,
      province TEXT
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE SCHEMA IF NOT EXISTS core
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS core.sample_veg (
      plot_number TEXT NOT NULL,
      species_code TEXT NOT NULL,
      layer_code TEXT NOT NULL,
      cover_percent INTEGER,
      project_id INTEGER,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      modified_by TEXT NOT NULL
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS core.sample_env (
      plot_number TEXT NOT NULL UNIQUE,
      project_id INTEGER,
      latitude NUMERIC,
      longitude NUMERIC,
      elevation_m INTEGER,
      survey_date DATE,
      surveyor_name TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      modified_by TEXT NOT NULL
    )
  ")
  
  # Seed minimal reference data
  seed_test_reference_data(con)
}

#' Seed Test Reference Data
#'
#' Populates lists tables with minimal valid test data
#'
#' @param con DBI connection object
#'
seed_test_reference_data <- function(con) {
  message("[test-helpers] Seeding reference data")
  
  # Species
  species_df <- data.frame(
    spp_code = c("AB", "FD", "HW", "YC", "AT"),
    spp_name = c("Abies lasiocarpa", "Pseudotsuga menziesii", "Tsuga heterophylla", 
                 "Thuja plicata", "Athyrium filix-femina"),
    spp_scientific = c("Subalpine Fir", "Douglas-fir", "Western Hemlock", 
                       "Western Redcedar", "Lady Fern"),
    is_active = c(TRUE, TRUE, TRUE, TRUE, TRUE)
  )
  
  DBI::dbWriteTable(con, DBI::Id(schema = "lists", table = "spplist"), 
                    species_df, overwrite = TRUE)
  
  # Zones
  zones_df <- data.frame(
    zone_code = c("CDF", "ICH", "IDF", "MH", "SBPS"),
    zone_name = c("Coastal Douglas-fir", "Interior Cedar-Hemlock", "Interior Douglas-fir",
                  "Mountain Hemlock", "Sub-Boreal Pine-Spruce"),
    province = c("BC", "BC", "BC", "BC", "BC")
  )
  
  DBI::dbWriteTable(con, DBI::Id(schema = "lists", table = "usyszonelist"),
                    zones_df, overwrite = TRUE)
}

#' Create Test Postgres Connection
#'
#' Attempts to connect to docker-compose postgres instance.
#' Skips test if postgres unavailable.
#'
#' @param skip_if_unavailable Logical. If TRUE, skip test if postgres not available.
#'
#' @return DBI connection object (if available)
#'
test_connect_postgres <- function(skip_if_unavailable = TRUE) {
  
  if (skip_if_unavailable && !pg_available) {
    testthat::skip("PostgreSQL not available. Start with: docker-compose up -d")
  }
  
  message("[test-helpers] Creating PostgreSQL test connection")
  
  # This requires RPostgres - would need to add to renv
  # For now, this is a placeholder
  tryCatch({
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = "localhost",
      port = 5433,
      user = "testuser",
      password = "testpass",
      dbname = "becmaster"
    )
    return(con)
  }, error = function(e) {
    if (skip_if_unavailable) {
      testthat::skip("Could not connect to PostgreSQL: ", e$message)
    } else {
      stop(e)
    }
  })
}

#' Reset Database to Clean State
#'
#' Truncates test tables and reseeds reference data
#'
#' @param con DBI connection object
#'
reset_test_db <- function(con) {
  message("[test-helpers] Resetting test database")
  
  # Truncate data tables (keep reference data)
  tryCatch({
    DBI::dbExecute(con, "TRUNCATE TABLE core.sample_veg")
    DBI::dbExecute(con, "TRUNCATE TABLE core.sample_env")
  }, error = function(e) {
    warning("Could not truncate tables: ", e$message)
  })
}

#' Insert Test Plot Data
#'
#' Helper to insert sample vegetation and environment records for testing
#'
#' @param con DBI connection object
#' @param plot_number Character. Plot identifier.
#' @param species Character vector. Species codes.
#' @param cover_percents Integer vector. Cover percentages.
#' @param project_id Integer. Project identifier.
#' @param modified_by Character. User making the change.
#'
insert_test_plot <- function(con, plot_number = "TEST-001", 
                             species = c("AB", "FD"),
                             cover_percents = c(25, 50),
                             project_id = 1,
                             modified_by = "test_user") {
  
  message("[test-helpers] Inserting test plot: ", plot_number)
  
  # Insert environment record
  env_df <- data.frame(
    plot_number = plot_number,
    project_id = project_id,
    latitude = 53.5,
    longitude = -119.5,
    elevation_m = 1500,
    survey_date = Sys.Date(),
    surveyor_name = "Test Surveyor",
    modified_by = modified_by
  )
  
  DBI::dbAppendTable(con, DBI::Id(schema = "core", table = "sample_env"), env_df)
  
  # Insert vegetation records
  veg_df <- data.frame(
    plot_number = rep(plot_number, length(species)),
    species_code = species,
    layer_code = rep("T", length(species)),
    cover_percent = cover_percents,
    project_id = project_id,
    modified_by = modified_by
  )
  
  DBI::dbAppendTable(con, DBI::Id(schema = "core", table = "sample_veg"), veg_df)
  
  message("[test-helpers] Inserted ", nrow(veg_df), " vegetation records")
}

#' Expect DBI Query Result
#'
#' Assertion helper for query results
#'
#' @param con DBI connection object
#' @param sql Character. SQL query.
#' @param expected_rows Integer. Expected number of rows.
#' @param label Character. Test label.
#'
expect_query_result <- function(con, sql, expected_rows = NULL, label = "query") {
  result <- DBI::dbGetQuery(con, sql)
  
  if (!is.null(expected_rows)) {
    testthat::expect_equal(nrow(result), expected_rows, 
                          label = paste0(label, " row count"))
  }
  
  return(result)
}
