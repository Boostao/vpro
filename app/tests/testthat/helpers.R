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
#' Creates full schema tables matching PostgreSQL for testing
#'
#' @param con DBI connection object
#'
initialize_test_schema <- function(con) {
  message("[test-helpers] Initializing test schema")
  
  # ==================== LISTS SCHEMA ====================
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  
  # lists.spplist
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.spplist (
      id INTEGER PRIMARY KEY,
      \"sppCode\" TEXT UNIQUE NOT NULL,
      \"sppName\" TEXT NOT NULL,
      \"sppScientific\" TEXT,
      \"isActive\" BOOLEAN DEFAULT TRUE
    )
  ")
  
  # lists.layercode
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.layercode (
      id INTEGER PRIMARY KEY,
      \"layerCode\" TEXT UNIQUE NOT NULL,
      \"layerName\" TEXT NOT NULL,
      \"sortOrder\" INTEGER
    )
  ")
  
  # lists.usyszonelist
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.usyszonelist (
      id INTEGER PRIMARY KEY,
      \"zoneCode\" TEXT UNIQUE NOT NULL,
      \"zoneName\" TEXT NOT NULL,
      province TEXT
    )
  ")
  
  # lists.usyssubzonelist
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.usyssubzonelist (
      id INTEGER PRIMARY KEY,
      \"zoneCode\" TEXT NOT NULL,
      \"subzoneCode\" TEXT NOT NULL,
      \"subzoneName\" TEXT NOT NULL,
      UNIQUE(\"zoneCode\", \"subzoneCode\")
    )
  ")
  
  # lists.usystableoflists
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.usystableoflists (
      id INTEGER PRIMARY KEY,
      \"listID\" TEXT NOT NULL,
      \"itemCode\" TEXT NOT NULL,
      \"itemName\" TEXT NOT NULL,
      \"itemSort\" INTEGER,
      UNIQUE(\"listID\", \"itemCode\")
    )
  ")
  
  # lists.usyssppattributes
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.usyssppattributes (
      id INTEGER PRIMARY KEY,
      \"sppCode\" TEXT UNIQUE NOT NULL,
      \"treeShrubHerb\" TEXT,
      \"nativeIntroduced\" TEXT
    )
  ")
  
  # ==================== CORE SCHEMA ====================
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS core")
  
  # core.env
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS core.env (
      id INTEGER PRIMARY KEY,
      \"PlotNumber\" TEXT NOT NULL UNIQUE,
      \"ProjectID\" TEXT NOT NULL,
      \"Latitude\" NUMERIC,
      \"Longitude\" NUMERIC,
      \"Elevation\" INTEGER,
      \"SurveyDate\" DATE,
      \"SurveyorName\" TEXT,
      \"PlotNotes\" TEXT,
      \"rowVersion\" INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ NOT NULL DEFAULT now(),
      \"modifiedBy\" TEXT
    )
  ")
  
  # core.veg
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS core.veg (
      id INTEGER PRIMARY KEY,
      \"PlotNumber\" TEXT NOT NULL,
      \"SpeciesCode\" TEXT NOT NULL,
      \"LayerCode\" TEXT,
      \"Cover1\" REAL,
      \"Height1\" TEXT,
      \"Cover2\" REAL,
      \"Height2\" TEXT,
      \"Cover3\" REAL,
      \"Height3\" TEXT,
      \"TotalA\" REAL,
      \"HeightA\" TEXT,
      \"Cover4\" REAL,
      \"Height4\" TEXT,
      \"Cover5\" REAL,
      \"Height5\" TEXT,
      \"Cover5a\" REAL,
      \"Height5a\" TEXT,
      \"Cover5b\" REAL,
      \"Height5b\" TEXT,
      \"Cover5c\" REAL,
      \"Height5c\" TEXT,
      \"TotalB\" REAL,
      \"HeightB\" TEXT,
      \"Cover6\" REAL,
      \"Height6\" REAL,
      \"Cover7\" REAL,
      \"Cover8\" REAL,
      \"Cover9\" REAL,
      \"Cover10\" TEXT,
      collected TEXT,
      flag BIGINT,
      ll BIGINT,
      af TEXT,
      dc BIGINT,
      ut BIGINT,
      vi BIGINT,
      pv BIGINT,
      pg BIGINT,
      ffa BIGINT,
      \"Cultural1\" TEXT,
      \"Cultural2\" TEXT,
      \"Other1\" TEXT,
      \"Other2\" TEXT,
      \"rowVersion\" INTEGER DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\" TEXT NOT NULL,
      UNIQUE(\"PlotNumber\", \"SpeciesCode\", \"LayerCode\")
    )
  ")
  
  # core.su
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS core.su (
      id INTEGER PRIMARY KEY,
      \"PlotNumber\" TEXT NOT NULL UNIQUE,
      \"SiteUnit\" TEXT,
      \"rowVersion\" INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ NOT NULL DEFAULT now(),
      \"modifiedBy\" TEXT
    )
  ")
  
  # ==================== STAGING SCHEMA ====================
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS staging")
  
  # staging.env
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS staging.env (
      id INTEGER PRIMARY KEY,
      \"mergeRequestID\" INTEGER NOT NULL,
      \"changeType\" TEXT NOT NULL CHECK (\"changeType\" IN ('I','U','D')),
      \"baseRowVersion\" INTEGER,
      \"PlotNumber\" TEXT NOT NULL,
      \"ProjectID\" TEXT NOT NULL,
      \"Latitude\" NUMERIC,
      \"Longitude\" NUMERIC,
      \"Elevation\" INTEGER,
      \"SurveyDate\" DATE,
      \"SurveyorName\" TEXT,
      \"PlotNotes\" TEXT,
      \"rowVersion\" INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ NOT NULL DEFAULT now(),
      \"modifiedBy\" TEXT
    )
  ")
  
  # staging.veg
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS staging.veg (
      id INTEGER PRIMARY KEY,
      \"mergeRequestID\" INTEGER NOT NULL,
      \"changeType\" TEXT NOT NULL CHECK (\"changeType\" IN ('I','U','D')),
      \"baseRowVersion\" INTEGER,
      \"PlotNumber\" TEXT NOT NULL,
      \"SpeciesCode\" TEXT NOT NULL,
      \"LayerCode\" TEXT,
      \"Cover1\" REAL,
      \"Height1\" TEXT,
      \"Cover2\" REAL,
      \"Height2\" TEXT,
      \"Cover3\" REAL,
      \"Height3\" TEXT,
      \"TotalA\" REAL,
      \"HeightA\" TEXT,
      \"Cover4\" REAL,
      \"Height4\" TEXT,
      \"Cover5\" REAL,
      \"Height5\" TEXT,
      \"Cover5a\" REAL,
      \"Height5a\" TEXT,
      \"Cover5b\" REAL,
      \"Height5b\" TEXT,
      \"Cover5c\" REAL,
      \"Height5c\" TEXT,
      \"TotalB\" REAL,
      \"HeightB\" TEXT,
      \"Cover6\" REAL,
      \"Height6\" REAL,
      \"Cover7\" REAL,
      \"Cover8\" REAL,
      \"Cover9\" REAL,
      \"Cover10\" TEXT,
      collected TEXT,
      flag BIGINT,
      ll BIGINT,
      af TEXT,
      dc BIGINT,
      ut BIGINT,
      vi BIGINT,
      pv BIGINT,
      pg BIGINT,
      ffa BIGINT,
      \"Cultural1\" TEXT,
      \"Cultural2\" TEXT,
      \"Other1\" TEXT,
      \"Other2\" TEXT,
      \"rowVersion\" INTEGER DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\" TEXT NOT NULL
    )
  ")
  
  # staging.su
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS staging.su (
      id INTEGER PRIMARY KEY,
      \"mergeRequestID\" INTEGER NOT NULL,
      \"changeType\" TEXT NOT NULL CHECK (\"changeType\" IN ('I','U','D')),
      \"baseRowVersion\" INTEGER,
      \"PlotNumber\" TEXT NOT NULL,
      \"SiteUnit\" TEXT,
      \"rowVersion\" INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ NOT NULL DEFAULT now(),
      \"modifiedBy\" TEXT
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
  
  # Only seed minimal test data - don't overwrite table structures
  # Insert species
  tryCatch({
    DBI::dbExecute(con,
      "INSERT INTO lists.spplist (\"sppCode\", \"sppName\", \"sppScientific\", \"isActive\")
       VALUES ('AB', 'Abies lasiocarpa', 'Subalpine Fir', TRUE),
              ('FD', 'Pseudotsuga menziesii', 'Douglas-fir', TRUE),
              ('HW', 'Tsuga heterophylla', 'Western Hemlock', TRUE),
              ('YC', 'Thuja plicata', 'Western Redcedar', TRUE),
              ('AT', 'Athyrium filix-femina', 'Lady Fern', TRUE)")
  }, error = function(e) {
    message("[test-helpers] Note: Could not seed spplist (may already exist)")
  })
  
  # Insert zones
  tryCatch({
    DBI::dbExecute(con,
      "INSERT INTO lists.usyszonelist (\"zoneCode\", \"zoneName\", province)
       VALUES ('CDF', 'Coastal Douglas-fir', 'BC'),
              ('ICH', 'Interior Cedar-Hemlock', 'BC'),
              ('IDF', 'Interior Douglas-fir', 'BC'),
              ('MH', 'Mountain Hemlock', 'BC'),
              ('SBPS', 'Sub-Boreal Pine-Spruce', 'BC')")
  }, error = function(e) {
    message("[test-helpers] Note: Could not seed usyszonelist (may already exist)")
  })
}

#' Check if PostgreSQL is Available
#'
#' Tests connection to Docker PostgreSQL instance
#'
#' @return Logical. TRUE if PostgreSQL is available
#'
pg_available <- function() {
  tryCatch({
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host     = Sys.getenv("PGHOST",     "localhost"),
      port     = as.integer(Sys.getenv("PGPORT", "5433")),
      user     = "vpro_app",
      password = "testpass",
      dbname   = Sys.getenv("PGDATABASE", "becmaster")
    )
    DBI::dbDisconnect(con)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get Test PostgreSQL Connection
#'
#' Creates connection to docker-compose postgres instance as superuser.
#' Used for setting up test fixtures and roles.
#'
#' @return DBI connection object
#'
get_test_pg_connection <- function() {
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PGHOST",     "localhost"),
    port     = as.integer(Sys.getenv("PGPORT", "5433")),
    user     = "vpro_app",
    password = "testpass",
    dbname   = Sys.getenv("PGDATABASE", "becmaster")
  )
  return(con)
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
  
  if (skip_if_unavailable && !pg_available()) {
    testthat::skip("PostgreSQL not available. Start with: docker-compose up -d")
  }
  
  message("[test-helpers] Creating PostgreSQL test connection")
  
  return(get_test_pg_connection())
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
    DBI::dbExecute(con, "TRUNCATE TABLE core.veg")
    DBI::dbExecute(con, "TRUNCATE TABLE core.env")
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
  
  DBI::dbAppendTable(con, DBI::Id(schema = "core", table = "env"), env_df)
  
  # Insert vegetation records
  veg_df <- data.frame(
    plot_number = rep(plot_number, length(species)),
    species_code = species,
    layer_code = rep("T", length(species)),
    cover_percent = cover_percents,
    project_id = project_id,
    modified_by = modified_by
  )
  
  DBI::dbAppendTable(con, DBI::Id(schema = "core", table = "veg"), veg_df)
  
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

#' Clear Core Tables
#'
#' Helper to clean up core.* tables for testing
#'
#' @param con DBI connection object (PostgreSQL)
#'
clear_core_tables <- function(con) {
  DBI::dbExecute(con, "DELETE FROM core.veg")
  DBI::dbExecute(con, "DELETE FROM core.env")
  DBI::dbExecute(con, "DELETE FROM core.su")
}

#' Clear Staging Tables
#'
#' Helper to clean up staging.* tables for testing
#'
#' @param con DBI connection object (PostgreSQL)
#'
clear_staging_tables <- function(con) {
  DBI::dbExecute(con, "DELETE FROM staging.veg")
  DBI::dbExecute(con, "DELETE FROM staging.env")
  DBI::dbExecute(con, "DELETE FROM staging.su")
  DBI::dbExecute(con, "DELETE FROM admin.merge_conflicts")
  DBI::dbExecute(con, "DELETE FROM admin.merge_requests")
}
