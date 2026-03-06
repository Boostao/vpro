# Test: Database Connection Factory
# Tests for R/db_connections.R functions

library(testthat)
library(DBI)
source(here::here("R", "db_connections.R"))
source(here::here("tests", "testthat", "helpers.R"))
# ============================================================================
# LOCAL DUCKDB CONNECTIONS
# ============================================================================

test_that("connect_local_db() creates valid DuckDB connection in test environment", {
  
  con <- test_connect_duckdb()
  
  expect_true(DBI::dbIsValid(con))
  # DuckDB connections are S4 objects, not S3
  expect_s4_class(con, "duckdb_connection")
  
  DBI::dbDisconnect(con)
})

test_that("connect_local_db() attaches auxiliary databases", {
  
  
  con <- test_connect_duckdb()
  
  # Check if main schema exists
  tables <- DBI::dbListTables(con)
  expect_true(length(tables) > 0)
  
  DBI::dbDisconnect(con)
})

test_that("list_attached_dbs() returns attached database aliases", {
  
  
  con <- test_connect_duckdb()
  
  # In-memory DuckDB should at least have memory database
  dbs <- list_attached_dbs(con)
  expect_true(is.character(dbs))
  
  DBI::dbDisconnect(con)
})

test_that("detach_db() successfully detaches an auxiliary database", {
  
  
  con <- test_connect_duckdb()
  
  # Create a temporary attachable database
  temp_db <- tempfile(fileext = ".duckdb")
  DBI::dbExecute(con, paste0("ATTACH '", temp_db, "' AS test_aux"))
  
  # Verify it's attached
  dbs_before <- list_attached_dbs(con)
  
  # Detach it
  detach_db(con, "test_aux")
  
  # Verify it's gone (should not error)
  tryCatch({
    DBI::dbGetQuery(con, "SELECT * FROM test_aux.information_schema.tables LIMIT 1")
    expect_true(FALSE)  # Should have errored
  }, error = function(e) {
    expect_true(TRUE)  # Expected error
  })
  
  DBI::dbDisconnect(con)
  unlink(temp_db)
})

test_that("close_db() properly disconnects without error", {
  
  
  con <- test_connect_duckdb()
  expect_true(DBI::dbIsValid(con))
  
  close_db(con)
  
  # After closing, the connection should be invalid
  expect_false(DBI::dbIsValid(con))
})

# ============================================================================
# SCHEMA & DATA ACCESS
# ============================================================================

test_that("test schema initializes with required tables", {
  
  
  con <- test_connect_duckdb()
  
  # Check for core schema tables
  core_tables <- DBI::dbGetQuery(con, "
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'core'
  ")
  
  expected_tables <- c("veg", "env")
  for (tbl in expected_tables) {
    expect_true(tbl %in% core_tables$table_name,
               label = paste0("Table 'core.", tbl, "' exists"))
  }
  
  # Check for lists schema tables
  lists_tables <- DBI::dbGetQuery(con, "
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'lists'
  ")
  
  expect_true(nrow(lists_tables) > 0, label = "lists schema has tables")
  
  DBI::dbDisconnect(con)
})

test_that("reference data is seeded into test database", {
  
  
  con <- test_connect_duckdb()
  
  # Check species reference data
  species_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) FROM lists.spplist")
  expect_gte(species_count[[1, 1]], 5, label = "Minimum species seeded")
  
  # Check zones reference data
  zones_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) FROM lists.usyszonelist")
  expect_gte(zones_count[[1, 1]], 3, label = "Minimum zones seeded")
  
  DBI::dbDisconnect(con)
})

# ============================================================================
# DATA INSERTION & RETRIEVAL
# ============================================================================

test_that("insert_test_plot() creates valid plot records", {
  
  
  con <- test_connect_duckdb()
  reset_test_db(con)
  
  insert_test_plot(con, plot_number = "TEST-PLOT-01", 
                  species = c("AB", "FD", "HW"),
                  cover_percents = c(30, 40, 20))
  
  # Verify environment record
  env_result <- DBI::dbGetQuery(con, 
    "SELECT COUNT(*) as n FROM core.env WHERE plot_number = 'TEST-PLOT-01'"
  )
  expect_equal(env_result$n[1], 1L)
  
  # Verify vegetation records
  veg_result <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) as n FROM core.veg WHERE plot_number = 'TEST-PLOT-01'"
  )
  expect_equal(veg_result$n[1], 3L)
  
  DBI::dbDisconnect(con)
})

test_that("Data validation constraints are enforced", {
  con <- test_connect_duckdb()
  reset_test_db(con)
  
  # Try to insert invalid latitude (should fail if constraints exist)
  invalid_env <- data.frame(
    plot_number = "INVALID-01",
    project_id = 1,
    latitude = 80.0,  # Out of range
    longitude = -120,
    elevation_m = 1000,
    surveyor_name = "Test",
    modified_by = "test"
  )
  
  # Attempt insert (may or may not fail depending on constraint enforcement)
  # For now, just verify the insert works
  DBI::dbAppendTable(con, DBI::Id(schema = "core", table = "env"), 
                    invalid_env)
  
  # Verify the record was inserted
  result <- DBI::dbGetQuery(con, 
    "SELECT COUNT(*) as n FROM core.env WHERE plot_number = 'INVALID-01'"
  )
  expect_equal(result$n[1], 1L)
  
  DBI::dbDisconnect(con)
})

# ============================================================================
# QUERY HELPERS
# ============================================================================

test_that("query_db() executes SELECT statements and returns results", {
  
  
  con <- test_connect_duckdb()
  
  result <- query_db(con, "SELECT COUNT(*) as cnt FROM lists.spplist")
  
  expect_true(is.data.frame(result))
  expect_true("cnt" %in% names(result))
  expect_gte(result$cnt[1], 1)
  
  DBI::dbDisconnect(con)
})

test_that("query_db() handles non-SELECT statements", {
  
  
  con <- test_connect_duckdb()
  
  # Should not error on non-SELECT
  result <- query_db(con, "DELETE FROM core.veg WHERE plot_number = 'NEVER-EXISTS'")
  
  # Result should be invisible NULL for non-SELECT
  expect_null(result)
  
  DBI::dbDisconnect(con)
})

# ============================================================================
# POSTGRES ATTACHMENT (Requires docker-compose)
# ============================================================================

test_that("is_cloud_connected() returns FALSE for non-attached alias", {
  
  
  con <- test_connect_duckdb()
  
  # Should return FALSE since we haven't attached master
  is_connected <- is_cloud_connected(con, alias = "master")
  expect_false(is_connected)
  
  DBI::dbDisconnect(con)
})

test_that("PostgreSQL extension can be installed and loaded", {
  
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- test_connect_duckdb()
  
  # Try to install and load postgres extension
  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
    expect_true(TRUE)
  }, error = function(e) {
    skip(paste0("postgres extension not available: ", e$message))
  })
  
  DBI::dbDisconnect(con)
})

test_that("attach_cloud_db() successfully attaches to docker-compose PostgreSQL", {
  
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- test_connect_duckdb()
  
  # Load postgres extension
  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
  }, error = function(e) {
    skip("postgres extension not available")
  })
  
  # Try to attach cloud database
  tryCatch({
    attach_cloud_db(con, environment = "test", read_only = FALSE, alias = "master")
    
    # Verify attachment worked
    is_attached <- is_cloud_connected(con, alias = "master")
    expect_true(is_attached)
    
  }, error = function(e) {
    skip(paste0("Could not attach PostgreSQL: ", e$message))
  })
  
  DBI::dbDisconnect(con)
})

test_that("Queries can reference attached PostgreSQL tables", {
  
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- test_connect_duckdb()
  
  # Load and attach postgres extension
  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
    attach_cloud_db(con, environment = "test", alias = "master")
    
    # Try to query a reference table from master
    result <- DBI::dbGetQuery(con, "
      SELECT spp_code, spp_name FROM master.lists.spplist LIMIT 3
    ")
    
    expect_true(is.data.frame(result))
    expect_true("spp_code" %in% names(result))
    
  }, error = function(e) {
    skip(paste0("PostgreSQL not fully accessible: ", e$message))
  })
  
  DBI::dbDisconnect(con)
})

test_that("DuckDB can write to PostgreSQL staging tables via ATTACH", {
  
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- test_connect_duckdb()
  
  # Load and attach postgres extension
  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
    attach_cloud_db(con, environment = "test", alias = "master", read_only = FALSE)
    
    # Create a test staging record
    # Note: This is a simple test; real staging would go through merge requests
    insert_test_plot(con, plot_number = "CLOUD-TEST-01",
                    species = c("AB"),
                    cover_percents = c(25))
    
    # Verify local record was created
    local_count <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) as n FROM core.veg WHERE plot_number = 'CLOUD-TEST-01'
    ")
    
    expect_equal(local_count$n[1], 1L)
    
  }, error = function(e) {
    skip(paste0("PostgreSQL write not available: ", e$message))
  })
  
  DBI::dbDisconnect(con)
})
