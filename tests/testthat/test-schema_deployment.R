# Test: PostgreSQL Schema Deployment
# Tests the deployment of the comprehensive schema with audit triggers

library(testthat)
library(DBI)
library(RPostgres)

# Helper: Connect to Docker PostgreSQL
connect_pg <- function() {
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "localhost",
    port = 5433,
    dbname = "becmaster",
    user = "testuser",
    password = "testpass"
  )
  return(con)
}

test_that("Docker PostgreSQL is accessible", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(
    connect_pg(),
    error = function(e) NULL
  )
  
  expect_false(is.null(con), info = "Could not connect to Docker PostgreSQL. Make sure it's running: docker-compose up -d")
  
  if (!is.null(con)) {
    DBI::dbDisconnect(con)
  }
})

test_that("Schema file can be deployed to PostgreSQL", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Read schema file
  schema_file <- here::here("scripts", "00_schema_becmaster_test.sql")
  expect_true(file.exists(schema_file))
  
  # Schema is already deployed via docker-compose, just verify it worked
  # by checking if schemas exist
  schemas <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as n
    FROM information_schema.schemata 
    WHERE schema_name IN ('audit', 'core', 'lists', 'staging', 'admin')
  ")
  
  expect_equal(schemas$n, 5, info = "All 5 schemas should exist after deployment")
  
  DBI::dbDisconnect(con)
})

test_that("All schemas were created", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  schemas <- DBI::dbGetQuery(con, "
    SELECT schema_name 
    FROM information_schema.schemata 
    WHERE schema_name IN ('audit', 'core', 'lists', 'staging', 'admin')
    ORDER BY schema_name
  ")
  
  expect_equal(nrow(schemas), 5)
  expect_setequal(schemas$schema_name, c("admin", "audit", "core", "lists", "staging"))
  
  DBI::dbDisconnect(con)
})

test_that("Audit schema has logged_actions table and trigger function", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Check table exists
  table_exists <- DBI::dbExistsTable(con, DBI::Id(schema = "audit", table = "logged_actions"))
  expect_true(table_exists)
  
  # Check trigger function exists
  func_check <- DBI::dbGetQuery(con, "
    SELECT proname 
    FROM pg_proc 
    JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
    WHERE nspname = 'audit' AND proname = 'if_modified_func'
  ")
  expect_equal(nrow(func_check), 1)
  
  DBI::dbDisconnect(con)
})

test_that("Core schema has all expected tables", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  core_tables <- c("sample_veg", "sample_env", "sample_su", "sample_metadata")
  
  for (table in core_tables) {
    exists <- DBI::dbExistsTable(con, DBI::Id(schema = "core", table = table))
    expect_true(exists, info = paste("Table core.", table, "does not exist"))
  }
  
  DBI::dbDisconnect(con)
})

test_that("Lists schema has all reference tables", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  list_tables <- c("spplist", "layercode", "usyszonelist", "usyssubzonelist", "usystableoflists")
  
  for (table in list_tables) {
    exists <- DBI::dbExistsTable(con, DBI::Id(schema = "lists", table = table))
    expect_true(exists, info = paste("Table lists.", table, "does not exist"))
  }
  
  DBI::dbDisconnect(con)
})

test_that("Staging schema has all workflow tables", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  staging_tables <- c("merge_requests", "merge_conflicts", "sample_veg", "sample_env", "sample_su")
  
  for (table in staging_tables) {
    exists <- DBI::dbExistsTable(con, DBI::Id(schema = "staging", table = table))
    expect_true(exists, info = paste("Table staging.", table, "does not exist"))
  }
  
  DBI::dbDisconnect(con)
})

test_that("Seed data was inserted correctly", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Check species count
  spp_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM lists.spplist")
  expect_equal(spp_count$n, 10)
  
  # Check layer count
  layer_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM lists.layercode")
  expect_equal(layer_count$n, 5)
  
  # Check zone count
  zone_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM lists.usyszonelist")
  expect_equal(zone_count$n, 7)
  
  # Check users
  user_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM admin.users")
  expect_equal(user_count$n, 3)
  
  # Check vegetation observations (at least 5 from seed data)
  veg_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM core.sample_veg")
  expect_gte(veg_count$n, 5)
  
  DBI::dbDisconnect(con)
})

test_that("Row version trigger works on INSERT", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Insert a new veg observation
  DBI::dbExecute(con, "
    INSERT INTO core.sample_veg 
    (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
    VALUES ('TEST_PLOT', 'TSUGHET', 'T1', 50, 2000, 1, 'test_user')
  ")
  
  # Check row_version is 1
  result <- DBI::dbGetQuery(con, "
    SELECT row_version, last_modified_utc 
    FROM core.sample_veg 
    WHERE plot_number = 'TEST_PLOT'
  ")
  
  expect_equal(result$row_version, 1)
  expect_true(!is.na(result$last_modified_utc))
  
  # Cleanup
  DBI::dbExecute(con, "DELETE FROM core.sample_veg WHERE plot_number = 'TEST_PLOT'")
  DBI::dbDisconnect(con)
})

test_that("Row version trigger increments on UPDATE", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Insert test row
  DBI::dbExecute(con, "
    INSERT INTO core.sample_veg 
    (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
    VALUES ('TEST_PLOT', 'TSUGHET', 'T1', 50, 2000, 1, 'test_user')
  ")
  
  # Get initial timestamp
  before <- DBI::dbGetQuery(con, "
    SELECT row_version, last_modified_utc 
    FROM core.sample_veg 
    WHERE plot_number = 'TEST_PLOT'
  ")
  
  # Wait a moment to ensure timestamp difference
  Sys.sleep(0.1)
  
  # Update the row
  DBI::dbExecute(con, "
    UPDATE core.sample_veg 
    SET cover_percent = 60
    WHERE plot_number = 'TEST_PLOT'
  ")
  
  # Check row_version incremented
  after <- DBI::dbGetQuery(con, "
    SELECT row_version, last_modified_utc 
    FROM core.sample_veg 
    WHERE plot_number = 'TEST_PLOT'
  ")
  
  expect_equal(after$row_version, 2)
  expect_true(after$last_modified_utc > before$last_modified_utc)
  
  # Cleanup
  DBI::dbExecute(con, "DELETE FROM core.sample_veg WHERE plot_number = 'TEST_PLOT'")
  DBI::dbDisconnect(con)
})

test_that("Audit trigger captures INSERT", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Clear audit log for test
  audit_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM audit.logged_actions")
  
  # Insert test row
  DBI::dbExecute(con, "
    INSERT INTO core.sample_veg 
    (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
    VALUES ('AUDIT_TEST', 'PSEUMEN', 'T1', 40, 1800, 1, 'test_user')
  ")
  
  # Check audit log
  audit_entry <- DBI::dbGetQuery(con, "
    SELECT action, schema_name, table_name, new_data
    FROM audit.logged_actions 
    WHERE table_name = 'sample_veg' 
      AND new_data->>'plot_number' = 'AUDIT_TEST'
    ORDER BY id DESC
    LIMIT 1
  ")
  
  expect_equal(nrow(audit_entry), 1)
  expect_equal(audit_entry$action, "I")
  expect_equal(audit_entry$schema_name, "core")
  expect_equal(audit_entry$table_name, "sample_veg")
  
  # Verify JSONB data
  new_data <- jsonlite::fromJSON(audit_entry$new_data)
  expect_equal(new_data$species_code, "PSEUMEN")
  expect_equal(as.numeric(new_data$cover_percent), 40)
  
  # Cleanup
  DBI::dbExecute(con, "DELETE FROM core.sample_veg WHERE plot_number = 'AUDIT_TEST'")
  DBI::dbDisconnect(con)
})

test_that("Audit trigger captures UPDATE with old and new data", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Insert test row
  DBI::dbExecute(con, "
    INSERT INTO core.sample_veg 
    (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
    VALUES ('AUDIT_UPDATE', 'TSUGHET', 'T1', 30, 2000, 1, 'test_user')
  ")
  
  # Update the row
  DBI::dbExecute(con, "
    UPDATE core.sample_veg 
    SET cover_percent = 55
    WHERE plot_number = 'AUDIT_UPDATE'
  ")
  
  # Check audit log for UPDATE
  audit_entry <- DBI::dbGetQuery(con, "
    SELECT action, original_data, new_data
    FROM audit.logged_actions 
    WHERE table_name = 'sample_veg' 
      AND action = 'U'
      AND original_data->>'plot_number' = 'AUDIT_UPDATE'
    ORDER BY id DESC
    LIMIT 1
  ")
  
  expect_equal(nrow(audit_entry), 1)
  expect_equal(audit_entry$action, "U")
  
  # Verify old and new JSONB data
  old_data <- jsonlite::fromJSON(audit_entry$original_data)
  new_data <- jsonlite::fromJSON(audit_entry$new_data)
  
  expect_equal(as.numeric(old_data$cover_percent), 30)
  expect_equal(as.numeric(new_data$cover_percent), 55)
  expect_equal(as.numeric(old_data$row_version), 1)
  expect_equal(as.numeric(new_data$row_version), 2)
  
  # Cleanup
  DBI::dbExecute(con, "DELETE FROM core.sample_veg WHERE plot_number = 'AUDIT_UPDATE'")
  DBI::dbDisconnect(con)
})

test_that("Audit trigger captures DELETE", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Insert test row
  DBI::dbExecute(con, "
    INSERT INTO core.sample_veg 
    (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
    VALUES ('AUDIT_DELETE', 'ABIALAM', 'T1', 70, 1500, 1, 'test_user')
  ")
  
  # Delete the row
  DBI::dbExecute(con, "
    DELETE FROM core.sample_veg 
    WHERE plot_number = 'AUDIT_DELETE'
  ")
  
  # Check audit log for DELETE
  audit_entry <- DBI::dbGetQuery(con, "
    SELECT action, original_data
    FROM audit.logged_actions 
    WHERE table_name = 'sample_veg' 
      AND action = 'D'
      AND original_data->>'plot_number' = 'AUDIT_DELETE'
    ORDER BY id DESC
    LIMIT 1
  ")
  
  expect_equal(nrow(audit_entry), 1)
  expect_equal(audit_entry$action, "D")
  
  # Verify original JSONB data
  old_data <- jsonlite::fromJSON(audit_entry$original_data)
  expect_equal(old_data$species_code, "ABIALAM")
  expect_equal(as.numeric(old_data$cover_percent), 70)
  
  DBI::dbDisconnect(con)
})

test_that("All core and lists tables have audit triggers attached", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Query for unique audit trigger names (each trigger fires on 3 events: INSERT, UPDATE, DELETE)
  triggers <- DBI::dbGetQuery(con, "
    SELECT DISTINCT
      trigger_schema,
      event_object_table,
      trigger_name
    FROM information_schema.triggers
    WHERE trigger_name LIKE '%audit'
      AND trigger_schema IN ('core', 'lists')
    ORDER BY trigger_schema, event_object_table
  ")
  
  # Should have audit triggers on:
  # core: sample_metadata, sample_env, sample_su, sample_veg (4)
  # lists: spplist, layercode, usyszonelist, usyssubzonelist, usystableoflists (5)
  expect_equal(nrow(triggers), 9)
  
  DBI::dbDisconnect(con)
})

test_that("Check constraints work correctly", {
  skip_if_not(nzchar(Sys.which("docker")), "Docker not available")
  
  con <- tryCatch(connect_pg(), error = function(e) NULL)
  skip_if(is.null(con), "PostgreSQL not available")
  
  # Test cover_percent constraint (must be 0-100)
  expect_error(
    DBI::dbExecute(con, "
      INSERT INTO core.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
      VALUES ('CHECK_TEST', 'TSUGHET', 'T1', 150, 2000, 1, 'test_user')
    "),
    regexp = "violates check constraint"
  )
  
  # Test height_cm constraint (must be >= 0)
  expect_error(
    DBI::dbExecute(con, "
      INSERT INTO core.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
      VALUES ('CHECK_TEST', 'TSUGHET', 'T1', 50, -100, 1, 'test_user')
    "),
    regexp = "violates check constraint"
  )
  
  # Test latitude constraint (must be 48-60)
  expect_error(
    DBI::dbExecute(con, "
      INSERT INTO core.sample_env 
      (plot_number, project_id, latitude, longitude, elevation_m, modified_by)
      VALUES ('CHECK_TEST', 1, 999, -123, 100, 'test_user')
    "),
    regexp = "violates check constraint"
  )
  
  DBI::dbDisconnect(con)
})
