## ---------------------------------------------------------------------------
## Merge-request conflict workflow (current implementation)
##
## This block tests the merge-request conflict tracking introduced in
## R/logic_sync.R and surfaced in the Merge Review UI (R/mod_merge.R).
## It is DuckDB-only: we emulate the cloud catalog by ATTACHing a temporary
## DuckDB file as `master`.
## ---------------------------------------------------------------------------

library(testthat)
library(DBI)
library(duckdb)

find_repo_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  for (i in seq_len(12)) {
    if (dir.exists(file.path(current, "R")) && file.exists(file.path(current, "ui.R"))) {
      return(current)
    }
    parent <- normalizePath(file.path(current, ".."), winslash = "/", mustWork = FALSE)
    if (identical(parent, current)) break
    current <- parent
  }
  stop("Could not locate repo root (expected a folder containing 'R/' and 'ui.R').")
}

repo_root <- find_repo_root()
source(file.path(repo_root, "R", "db_connections.R"))
source(file.path(repo_root, "R", "logic_auth.R"))
source(file.path(repo_root, "R", "logic_sync.R"))
source(file.path(repo_root, "R", "mod_merge.R"))

create_master_fixture <- function() {
  master_path <- tempfile("vpro_master_", fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), master_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS core")
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS staging")
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS admin")

  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS core.sample_env (
       plot_number TEXT,
       project_id TEXT,
       latitude DOUBLE,
       longitude DOUBLE,
       elevation_m DOUBLE,
       survey_date DATE,
       surveyor_name TEXT,
       plot_notes TEXT,
       modified_by TEXT,
       last_modified_utc TIMESTAMPTZ,
       row_version INTEGER,
       PRIMARY KEY(plot_number, project_id)
     )"
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS core.sample_su (
       plot_number TEXT,
       project_id TEXT,
       su_number TEXT,
       bec_zone TEXT,
       bec_subzone TEXT,
       site_series TEXT,
       modified_by TEXT,
       last_modified_utc TIMESTAMPTZ,
       row_version INTEGER,
       PRIMARY KEY(plot_number, project_id)
     )"
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS core.sample_veg (
       plot_number TEXT,
       project_id TEXT,
       species_code TEXT,
       layer_code TEXT,
       cover1 TEXT,
       cover2 TEXT,
       cover3 TEXT,
       totala TEXT,
       totalb TEXT,
       flag TEXT,
       modified_by TEXT,
       last_modified_utc TIMESTAMPTZ,
       row_version INTEGER,
       PRIMARY KEY(plot_number, project_id, species_code, layer_code)
     )"
  )

  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS staging.sample_env (
       merge_request_id BIGINT,
       plot_number TEXT,
       project_id TEXT,
       latitude DOUBLE,
       longitude DOUBLE,
       elevation_m DOUBLE,
       survey_date DATE,
       surveyor_name TEXT,
       plot_notes TEXT,
       modified_by TEXT,
       base_row_version INTEGER
     )"
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS staging.sample_su (
       merge_request_id BIGINT,
       plot_number TEXT,
       project_id TEXT,
       su_number TEXT,
       bec_zone TEXT,
       bec_subzone TEXT,
       site_series TEXT,
       modified_by TEXT,
       base_row_version INTEGER
     )"
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS staging.sample_veg (
       merge_request_id BIGINT,
       plot_number TEXT,
       project_id TEXT,
       species_code TEXT,
       layer_code TEXT,
       cover1 TEXT,
       cover2 TEXT,
       cover3 TEXT,
       totala TEXT,
       totalb TEXT,
       flag TEXT,
       modified_by TEXT,
       base_row_version INTEGER
     )"
  )

  master_path
}

attach_master <- function(con_local, master_path) {
  DBI::dbExecute(con_local, sprintf("ATTACH '%s' AS master", master_path))
}

seed_merge_request_with_env_conflict <- function(master_path) {
  con <- DBI::dbConnect(duckdb::duckdb(), master_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE SEQUENCE IF NOT EXISTS admin.merge_requests_id_seq")
  DBI::dbExecute(
    con,
    "CREATE TABLE IF NOT EXISTS admin.merge_requests (
       id BIGINT PRIMARY KEY DEFAULT nextval('admin.merge_requests_id_seq'),
       project_id TEXT NOT NULL,
       submitter_user_id TEXT NOT NULL,
       submitted_utc TIMESTAMPTZ DEFAULT now(),
       status TEXT DEFAULT 'pending_review',
       reviewer_user_id TEXT,
       reviewed_utc TIMESTAMPTZ,
       review_notes TEXT,
       env_record_count INTEGER DEFAULT 0,
       su_record_count INTEGER DEFAULT 0,
       veg_record_count INTEGER DEFAULT 0,
       compliance_passed BOOLEAN,
       compliance_report TEXT
     )"
  )

  DBI::dbExecute(
    con,
    "INSERT INTO admin.merge_requests (project_id, submitter_user_id, status, compliance_passed)
     VALUES ('TEST', 'uploader', 'pending_review', TRUE)"
  )
  mr_id <- DBI::dbGetQuery(con, "SELECT max(id) AS id FROM admin.merge_requests")$id[1]

  DBI::dbExecute(
    con,
    "INSERT OR REPLACE INTO core.sample_env
       (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes,
        modified_by, last_modified_utc, row_version)
     VALUES ('P1', 'TEST', 51.0, -120.0, 1000, DATE '2024-01-01', 'core', 'core notes',
             'core', now(), 2)"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO staging.sample_env
       (merge_request_id, plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes,
        modified_by, base_row_version)
     VALUES (?, 'P1', 'TEST', 52.0, -121.0, 1100, DATE '2024-01-02', 'staged', 'staged notes',
             'staged', 1)",
    list(as.integer(mr_id))
  )
  DBI::dbExecute(con, "UPDATE admin.merge_requests SET env_record_count = 1 WHERE id = ?", list(as.integer(mr_id)))
  as.integer(mr_id)
}

test_that("merge_request_refresh_conflicts detects env optimistic concurrency conflicts", {
  master_path <- create_master_fixture()
  mr_id <- seed_merge_request_with_env_conflict(master_path)

  con_local <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con_local), add = TRUE)
  attach_master(con_local, master_path)

  merge_ensure_tables(con_local)
  merge_request_refresh_conflicts(con_local, mr_id)
  conflicts <- merge_request_get_conflicts(con_local, mr_id, unresolved_only = TRUE)

  expect_true(nrow(conflicts) >= 1)
  expect_true(any(conflicts$table_name == "sample_env"))
})

test_that("Merge Review UI can resolve a detected conflict", {
  skip_on_ci()
  skip_if_not(requireNamespace("shinytest2", quietly = TRUE), "shinytest2 not installed")
  skip_if_not(requireNamespace("shiny", quietly = TRUE), "shiny not installed")

  master_path <- create_master_fixture()
  mr_id <- seed_merge_request_with_env_conflict(master_path)

  app <- shiny::shinyApp(
    ui = shiny::fluidPage(mod_merge_ui("merge")),
    server = function(input, output, session) {
      con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
      attach_master(con, master_path)

      state <- shiny::reactiveValues(
        User = "tester",
        AuthAuthenticated = TRUE,
        AuthPermissions = "*"
      )
      mod_merge_server("merge", state = state, con = con)

      session$onSessionEnded(function() {
        DBI::dbDisconnect(con)
      })
    }
  )

  driver <- NULL
  tryCatch({
    driver <- shinytest2::AppDriver$new(app = app, name = "merge-conflict-resolve", timeout = 20000)
  }, error = function(e) {
    skip(paste("Unable to start AppDriver (Chrome/Chromote missing?):", conditionMessage(e)))
  })
  on.exit(tryCatch(driver$stop(), error = function(e) NULL), add = TRUE)

  driver$set_inputs(`merge-merge_request` = as.character(mr_id))
  driver$wait_for_idle()

  con_check <- DBI::dbConnect(duckdb::duckdb(), master_path)
  on.exit(DBI::dbDisconnect(con_check), add = TRUE)

  pre <- DBI::dbGetQuery(
    con_check,
    "SELECT COUNT(*) AS n FROM admin.merge_conflicts WHERE merge_request_id = ? AND resolution IS NULL",
    list(mr_id)
  )$n[1]
  expect_true(pre >= 1)

  driver$set_inputs(`merge-merge_conflicts_rows_selected` = 1)
  driver$click("merge-merge_conflict_keep_core")
  driver$wait_for_idle()

  post <- DBI::dbGetQuery(
    con_check,
    "SELECT COUNT(*) AS n FROM admin.merge_conflicts WHERE merge_request_id = ? AND resolution IS NULL",
    list(mr_id)
  )$n[1]
  expect_equal(post, 0)
})


# ---------------------------------------------------------------------------
# Legacy (pre-merge-request) conflict tests
#
# The remainder of this file tests an older, not-current `sync_conflicts` table
# and an `admin-*` UI that does not exist. Keep it for reference only.
# ---------------------------------------------------------------------------

if (FALSE) {
library(shinytest2)
library(testthat)
library(DBI)
library(duckdb)

# ============================================================================
# Conflict Resolution Workflow Tests
# ============================================================================
# Tests for local DuckDB ↔ cloud PostgreSQL sync conflict detection and 
# resolution. Conflicts occur when the same record is modified locally and
# remotely between sync operations.
#
# Architecture:
# - Local changes tracked via row_version in DuckDB
# - Cloud changes tracked via row_version in PostgreSQL
# - Conflicts logged to sync_conflicts table
# - Resolution options: keep_local, keep_cloud, dismiss
# - UI presents side-by-side diff viewer for manual resolution
#
# Test Strategy:
# - Mock cloud sync scenarios (no actual PostgreSQL required)
# - Simulate conflicts by direct DB manipulation
# - Verify conflict detection, UI presentation, and resolution outcomes
# - Test both single and batch conflict scenarios
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS - Conflict Simulation
# ============================================================================

# Setup test environment with sync infrastructure
setup_sync_environment <- function() {
  # Use existing database or create in-memory for testing
  db_path <- if (file.exists("data/vpro.duckdb")) {
    "data/vpro.duckdb"
  } else {
    ":memory:"
  }
  
  con <- dbConnect(duckdb(), db_path)
  
  # Ensure sync tables exist (from logic_sync.R)
  tryCatch({
    dbExecute(con, "
      CREATE TABLE IF NOT EXISTS sync_state (
        scope TEXT NOT NULL,
        value TEXT,
        updated_utc TIMESTAMPTZ DEFAULT now(),
        PRIMARY KEY (scope)
      )
    ")
    
    dbExecute(con, "
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY,
        table_name TEXT NOT NULL,
        plot_number TEXT,
        project_id TEXT,
        local_seen_utc TIMESTAMPTZ,
        cloud_seen_utc TIMESTAMPTZ,
        details TEXT,
        detected_utc TIMESTAMPTZ DEFAULT now()
      )
    ")
    
    # Add row_version to Sample_Env if missing
    columns <- dbListFields(con, "Sample_Env")
    if (!"row_version" %in% columns) {
      dbExecute(con, "ALTER TABLE Sample_Env ADD COLUMN row_version INTEGER DEFAULT 1")
    }
    
  }, error = function(e) {
    message("Sync setup note: ", conditionMessage(e))
  })
  
  dbDisconnect(con)
}

# Clean up sync infrastructure
cleanup_sync_environment <- function() {
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  tryCatch({
    dbExecute(con, "DELETE FROM sync_conflicts")
    dbExecute(con, "DELETE FROM sync_state")
  }, error = function(e) {
    message("Sync cleanup note: ", conditionMessage(e))
  })
}

# Create a test conflict in the sync_conflicts table
create_test_conflict <- function(plot_number, 
                                  project_id = "TEST",
                                  table_name = "Sample_Env",
                                  local_value = "Local Value",
                                  cloud_value = "Cloud Value",
                                  field_name = "SiteNotes") {
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Build conflict details JSON
  details <- sprintf(
    '{"%s": {"local": "%s", "cloud": "%s"}}',
    field_name, local_value, cloud_value
  )
  
  dbExecute(con, 
    "INSERT INTO sync_conflicts (table_name, plot_number, project_id, details, detected_utc)
     VALUES (?, ?, ?, ?, now())",
    list(table_name, plot_number, project_id, details)
  )
  
  # Get the ID of the created conflict
  id <- dbGetQuery(con, "SELECT MAX(id) AS id FROM sync_conflicts")$id[1]
  return(id)
}

# Create multiple test plots with different conflict types
create_conflict_scenario <- function(n_conflicts = 5) {
  conflict_ids <- integer(n_conflicts)
  
  # Conflict 1: Single field change (different fields)
  conflict_ids[1] <- create_test_conflict(
    plot_number = "CONF-001",
    field_name = "Latitude",
    local_value = "50.1234",
    cloud_value = "50.1234"  # Same - auto-mergeable
  )
  
  # Conflict 2: Same field conflict 
  conflict_ids[2] <- create_test_conflict(
    plot_number = "CONF-002",
    field_name = "SiteNotes",
    local_value = "Steep slope, north aspect",
    cloud_value = "Gentle slope, south aspect"
  )
  
  # Conflict 3: Numeric field conflict
  conflict_ids[3] <- create_test_conflict(
    plot_number = "CONF-003",
    field_name = "Elevation",
    local_value = "1250",
    cloud_value = "1255"
  )
  
  # Conflict 4: Cover value conflict (vegetation)
  conflict_ids[4] <- create_test_conflict(
    plot_number = "CONF-004",
    table_name = "Sample_Veg",
    field_name = "Cover",
    local_value = "25",
    cloud_value = "30"
  )
  
  # Conflict 5: Multiple fields in same record
  if (n_conflicts >= 5) {
    db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
    con <- dbConnect(duckdb(), db_path)
    details_multi <- '{"Latitude": {"local": "51.0", "cloud": "51.1"}, 
                       "Longitude": {"local": "-120.5", "cloud": "-120.6"}}'
    dbExecute(con, 
      "INSERT INTO sync_conflicts (table_name, plot_number, project_id, details, detected_utc)
       VALUES (?, ?, ?, ?, now())",
      list("Sample_Env", "CONF-005", "TEST", details_multi)
    )
    conflict_ids[5] <- dbGetQuery(con, "SELECT MAX(id) AS id FROM sync_conflicts")$id[1]
    dbDisconnect(con)
  }
  
  return(conflict_ids)
}

# Get conflict count from database
count_conflicts <- function(project_id = NULL) {
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  if (is.null(project_id)) {
    result <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM sync_conflicts")
  } else {
    result <- dbGetQuery(con, 
      "SELECT COUNT(*) AS n FROM sync_conflicts WHERE project_id = ?",
      list(project_id)
    )
  }
  
  return(result$n[1])
}

# Verify conflict was resolved
verify_conflict_resolved <- function(conflict_id) {
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  result <- dbGetQuery(con, 
    "SELECT COUNT(*) AS n FROM sync_conflicts WHERE id = ?",
    list(conflict_id)
  )
  
  return(result$n[1] == 0)
}

# Create test plot data for conflict resolution
create_plot_for_conflict_test <- function(plot_number, project_id = "TEST") {
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Create SiteUnit
  tryCatch({
    dbExecute(con, 
      "INSERT INTO Sample_SU (SiteUnit, ProjectID) VALUES (?, ?)",
      list(plot_number, project_id)
    )
  }, error = function(e) NULL)
  
  # Create Sample_Env with row_version
  tryCatch({
    dbExecute(con, 
      "INSERT INTO Sample_Env (PlotNumber, ProjectID, _Location, Date, row_version)
       VALUES (?, ?, ?, ?, 1)",
      list(plot_number, project_id, "Test Location", Sys.Date())
    )
  }, error = function(e) NULL)
}

# ============================================================================
# TESTS - Conflict Detection
# ============================================================================

test_that("sync infrastructure tables are created correctly", {
  skip_if_not(file.exists("data/vpro.duckdb"), 
              message = "Main database not found - run scripts/01_build_database.R first")
  
  setup_sync_environment()
  
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Verify sync_state table exists
  tables <- dbListTables(con)
  expect_true("sync_state" %in% tables, 
              info = "sync_state table should exist")
  
  # Verify sync_conflicts table exists
  expect_true("sync_conflicts" %in% tables,
              info = "sync_conflicts table should exist")
  
  # Verify sync_conflicts has correct columns
  conflict_cols <- dbListFields(con, "sync_conflicts")
  expect_true(all(c("id", "table_name", "plot_number", "project_id", "details") 
                  %in% conflict_cols),
              info = "sync_conflicts should have all required columns")
})

test_that("conflict creation helper works correctly", {
  skip_if_not(file.exists("data/vpro.duckdb"), 
              message = "Main database not found - run scripts/01_build_database.R first")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  conflict_id <- create_test_conflict(
    plot_number = "TEST-001",
    project_id = "DEMO",
    field_name = "Elevation",
    local_value = "1000",
    cloud_value = "1050"
  )
  
  expect_true(is.numeric(conflict_id) && conflict_id > 0,
              info = "Conflict creation should return valid ID")
  
  # Verify conflict was created
  count <- count_conflicts(project_id = "DEMO")
  expect_equal(count, 1, 
               info = "Should have exactly 1 conflict")
  
  cleanup_sync_environment()
})

test_that("multiple conflicts can be created and counted", {
  skip_if_not(file.exists("data/vpro.duckdb"), 
              message = "Main database not found - run scripts/01_build_database.R first")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  conflict_ids <- create_conflict_scenario(n_conflicts = 5)
  
  expect_length(conflict_ids, 5,
                info = "Should create 5 conflicts")
  
  total_count <- count_conflicts()
  expect_equal(total_count, 5,
               info = "Database should contain 5 conflicts")
  
  # Count by project
  test_count <- count_conflicts(project_id = "TEST")
  expect_equal(test_count, 5,
               info = "All test conflicts have TEST project_id")
  
  cleanup_sync_environment()
})

# ============================================================================
# TESTS - Conflict Resolution UI (Placeholder Tests)
# ============================================================================
# These tests document expected UI behavior for conflict resolution.
# They are skipped until the UI module is fully implemented.
# ============================================================================

test_that("conflict resolution UI appears when conflicts exist", {
  skip("Conflict resolution UI not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  create_conflict_scenario(n_conflicts = 3)
  
  app <- AppDriver$new(name = "conflicts-ui-visibility", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  # Navigate to admin/sync panel
  app$click("nav-admin")
  app$wait_for_idle(2000)
  
  # Should show conflict count badge
  conflict_badge <- app$get_value(output = "admin-conflict_count")
  expect_equal(conflict_badge, "3", 
               info = "Should display conflict count")
  
  # Click to open conflict resolution interface
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(2000)
  
  # Verify conflict list appears
  conflicts_table <- app$get_value(output = "admin-conflict_list")
  expect_true(!is.null(conflicts_table),
              info = "Conflict list table should be populated")
  
  cleanup_sync_environment()
})

test_that("single field conflict shows diff viewer", {
  skip("Diff viewer UI not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  conflict_id <- create_test_conflict(
    plot_number = "DIFF-001",
    field_name = "SiteNotes",
    local_value = "Rocky terrain, sparse vegetation",
    cloud_value = "Rocky terrain, dense canopy"
  )
  
  app <- AppDriver$new(name = "conflict-diff-viewer", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  # Navigate to conflict resolution
  app$click("nav-admin")
  app$wait_for_idle(1000)
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Select the conflict from list
  app$set_inputs(`admin-selected_conflict` = conflict_id)
  app$wait_for_idle(1000)
  
  # Verify diff viewer shows both values
  diff_display <- app$get_value(output = "admin-conflict_diff")
  expect_true(grepl("sparse vegetation", diff_display$local, fixed = TRUE),
              info = "Local value should be displayed")
  expect_true(grepl("dense canopy", diff_display$cloud, fixed = TRUE),
              info = "Cloud value should be displayed")
  
  # Verify field name is highlighted
  expect_true(grepl("SiteNotes", diff_display$field_name),
              info = "Field name should be shown")
  
  cleanup_sync_environment()
})

test_that("user can choose 'Keep Local' resolution", {
  skip("Resolution actions not yet wired in UI")
  
  setup_sync_environment()
  cleanup_sync_environment()
  create_plot_for_conflict_test("RES-001")
  
  conflict_id <- create_test_conflict(
    plot_number = "RES-001",
    field_name = "Elevation",
    local_value = "1250",
    cloud_value = "1200"
  )
  
  app <- AppDriver$new(name = "conflict-keep-local", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$wait_for_idle(1000)
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Select conflict
  app$set_inputs(`admin-selected_conflict` = conflict_id)
  app$wait_for_idle(500)
  
  # Click "Keep Local" button
  app$click("admin-keep_local")
  app$wait_for_idle(2000)
  
  # Verify success notification
  app$expect_values(output = "admin-resolution_status",
                    value = "✓ Conflict resolved (kept local)")
  
  # Verify conflict was removed from database
  expect_true(verify_conflict_resolved(conflict_id),
              info = "Conflict should be deleted after resolution")
  
  cleanup_sync_environment()
})

test_that("user can choose 'Keep Cloud' resolution", {
  skip("Resolution actions not yet wired in UI")
  
  setup_sync_environment()
  cleanup_sync_environment()
  create_plot_for_conflict_test("RES-002")
  
  conflict_id <- create_test_conflict(
    plot_number = "RES-002",
    field_name = "SiteSurveyor",
    local_value = "J. Smith",
    cloud_value = "Jane Smith"
  )
  
  app <- AppDriver$new(name = "conflict-keep-cloud", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$wait_for_idle(1000)
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  app$set_inputs(`admin-selected_conflict` = conflict_id)
  app$wait_for_idle(500)
  
  # Click "Keep Cloud" button
  app$click("admin-keep_cloud")
  app$wait_for_idle(2000)
  
  # Verify resolution
  expect_true(verify_conflict_resolved(conflict_id),
              info = "Conflict should be resolved")
  
  # Verify local data was updated (would require cloud mock)
  # This test would need PostgreSQL mock infrastructure
  
  cleanup_sync_environment()
})

test_that("user can dismiss conflicts", {
  skip("Dismiss action not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  conflict_id <- create_test_conflict(
    plot_number = "DIS-001",
    field_name = "Comments",
    local_value = "Review needed",
    cloud_value = "Review completed"
  )
  
  app <- AppDriver$new(name = "conflict-dismiss", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  app$set_inputs(`admin-selected_conflict` = conflict_id)
  app$wait_for_idle(500)
  
  # Click "Dismiss" button
  app$click("admin-dismiss_conflict")
  app$wait_for_idle(2000)
  
  # Verify conflict removed but no data changes made
  expect_true(verify_conflict_resolved(conflict_id),
              info = "Dismissed conflict should be removed from list")
  
  cleanup_sync_environment()
})

# ============================================================================
# TESTS - Batch Conflict Resolution
# ============================================================================

test_that("multiple conflicts can be displayed in list", {
  skip("Conflict list view not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 5)
  
  app <- AppDriver$new(name = "conflict-list-multiple", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1500)
  
  # Verify conflict list shows all 5
  conflict_table <- app$get_value(output = "admin-conflict_list")
  expect_equal(nrow(conflict_table), 5,
               info = "Should display all 5 conflicts")
  
  # Verify table columns
  expect_true(all(c("plot_number", "table_name", "detected_utc") %in% 
                  names(conflict_table)),
              info = "Conflict table should show key columns")
  
  cleanup_sync_environment()
})

test_that("Accept All Local batch action works", {
  skip("Batch resolution not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 3)
  
  app <- AppDriver$new(name = "batch-accept-local", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Click "Accept All Local" button
  app$click("admin-accept_all_local")
  app$wait_for_idle(3000)
  
  # Verify all conflicts resolved
  remaining <- count_conflicts(project_id = "TEST")
  expect_equal(remaining, 0,
               info = "All conflicts should be resolved")
  
  cleanup_sync_environment()
})

test_that("Accept All Cloud batch action works", {
  skip("Batch resolution not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 3)
  
  app <- AppDriver$new(name = "batch-accept-cloud", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Click "Accept All Cloud" button
  app$click("admin-accept_all_cloud")
  app$wait_for_idle(3000)
  
  # Verify all conflicts resolved
  remaining <- count_conflicts(project_id = "TEST")
  expect_equal(remaining, 0,
               info = "All conflicts should be resolved")
  
  cleanup_sync_environment()
})

test_that("selective resolution from list works", {
  skip("Selective multi-resolution not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 5)
  
  app <- AppDriver$new(name = "selective-resolution", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Select conflicts 1, 3, 5 via checkboxes
  app$set_inputs(`admin-conflict_selected_rows` = c(1, 3, 5))
  app$wait_for_idle(500)
  
  # Resolve selected with "Keep Local"
  app$click("admin-resolve_selected_local")
  app$wait_for_idle(2000)
  
  # Verify only 2 conflicts remain (2 and 4)
  remaining <- count_conflicts(project_id = "TEST")
  expect_equal(remaining, 2,
               info = "Should have 2 unresolved conflicts")
  
  cleanup_sync_environment()
})

# ============================================================================
# TESTS - Edge Cases
# ============================================================================

test_that("conflict on deleted record shows special UI", {
  skip("Delete conflict handling not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  # Create conflict where local deleted, cloud edited
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  details <- '{"_deleted": {"local": true, "cloud": false}, 
               "Elevation": {"local": null, "cloud": "1500"}}'
  dbExecute(con, 
    "INSERT INTO sync_conflicts (table_name, plot_number, project_id, details)
     VALUES (?, ?, ?, ?)",
    list("Sample_Env", "DEL-001", "TEST", details)
  )
  conflict_id <- dbGetQuery(con, "SELECT MAX(id) AS id FROM sync_conflicts")$id[1]
  dbDisconnect(con)
  
  app <- AppDriver$new(name = "conflict-deletion", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  app$set_inputs(`admin-selected_conflict` = conflict_id)
  app$wait_for_idle(1000)
  
  # Verify special "deletion conflict" badge
  diff_view <- app$get_value(output = "admin-conflict_diff")
  expect_true(grepl("DELETED LOCALLY", diff_view$status, ignore.case = TRUE),
              info = "Should indicate deletion conflict")
  
  # Verify options: "Restore Local" vs "Keep Cloud Edit"
  button_labels <- app$get_value(output = "admin-resolution_buttons")
  expect_true("restore_local" %in% names(button_labels),
              info = "Should offer restore option")
  
  cleanup_sync_environment()
})

test_that("UUID collision conflict is detected", {
  skip("UUID collision detection not yet implemented")
  
  # Rare edge case: two users create plots with same PlotNumber
  # Should detect during sync and flag as special conflict type
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  details <- '{"_conflict_type": "uuid_collision", 
               "PlotNumber": {"local": "NEW-001", "cloud": "NEW-001"},
               "message": "Plot number already exists in cloud with different UUID"}'
  dbExecute(con, 
    "INSERT INTO sync_conflicts (table_name, plot_number, project_id, details)
     VALUES (?, ?, ?, ?)",
    list("Sample_Env", "NEW-001", "TEST", details)
  )
  dbDisconnect(con)
  
  # Test that UI shows special warning and suggests renaming
  # Full implementation would test UUID-based resolution
  
  cleanup_sync_environment()
})

test_that("sync cancellation preserves local data", {
  skip("Sync cancellation not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 2)
  
  # Create test plot with known data
  create_plot_for_conflict_test("CANCEL-001")
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  initial_data <- dbGetQuery(con, 
    "SELECT * FROM Sample_Env WHERE PlotNumber = 'CANCEL-001'"
  )
  dbDisconnect(con)
  
  app <- AppDriver$new(name = "sync-cancel", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Start resolution then cancel
  app$set_inputs(`admin-selected_conflict` = conflict_ids[1])
  app$wait_for_idle(500)
  app$click("admin-cancel_resolution")
  app$wait_for_idle(1000)
  
  # Verify local data unchanged
  db_path <- if (file.exists("data/vpro.duckdb")) "data/vpro.duckdb" else ":memory:"
  con <- dbConnect(duckdb(), db_path)
  final_data <- dbGetQuery(con, 
    "SELECT * FROM Sample_Env WHERE PlotNumber = 'CANCEL-001'"
  )
  dbDisconnect(con)
  
  expect_equal(initial_data, final_data,
               info = "Cancellation should not modify local data")
  
  # Verify conflicts still exist
  remaining <- count_conflicts(project_id = "TEST")
  expect_equal(remaining, 2,
               info = "Conflicts should remain after cancellation")
  
  cleanup_sync_environment()
})

test_that("re-sync after partial resolution works correctly", {
  skip("Re-sync workflow not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 4)
  
  app <- AppDriver$new(name = "resync-partial", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  # Resolve 2 out of 4 conflicts
  app$set_inputs(`admin-selected_conflict` = conflict_ids[1])
  app$click("admin-keep_local")
  app$wait_for_idle(1000)
  
  app$set_inputs(`admin-selected_conflict` = conflict_ids[2])
  app$click("admin-keep_cloud")
  app$wait_for_idle(1000)
  
  # Verify 2 conflicts remain
  expect_equal(count_conflicts(project_id = "TEST"), 2,
               info = "Should have 2 unresolved conflicts")
  
  # Trigger sync again
  app$click("admin-sync_now")
  app$wait_for_idle(3000)
  
  # Verify:
  # 1. Resolved conflicts don't reappear
  # 2. Unresolved conflicts persist
  # 3. New conflicts (if any) are added
  
  final_count <- count_conflicts(project_id = "TEST")
  expect_gte(final_count, 2,
             info = "Unresolved conflicts should persist")
  
  cleanup_sync_environment()
})

# ============================================================================
# TESTS - Integration with Sync Engine
# ============================================================================

test_that("conflict detection runs during sync-pull", {
  skip("Sync engine integration not yet complete")
  
  # Test that sync_pull() from logic_sync.R triggers conflict detection
  # Requires mock PostgreSQL or in-memory cloud simulation
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  # Would need to:
  # 1. Create mock cloud data (in-memory DuckDB ATTACH)
  # 2. Modify local data to create conflict
  # 3. Run sync_pull()
  # 4. Verify conflicts were detected and logged
  
  cleanup_sync_environment()
})

test_that("no conflicts detected when changes are in different fields", {
  skip("Conflict detection logic needs refinement")
  
  # Auto-mergeable scenario:
  # Local changes: Latitude
  # Cloud changes: Longitude
  # Should merge automatically, no conflict
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  # Test would verify that sync engine merges without creating conflict
  
  cleanup_sync_environment()
})

test_that("conflict UI is hidden when no conflicts exist", {
  skip("Conflict UI visibility logic not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  app <- AppDriver$new(name = "no-conflicts", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$wait_for_idle(1000)
  
  # Verify conflict badge shows "0" or is hidden
  conflict_badge <- app$get_value(output = "admin-conflict_count")
  expect_true(is.null(conflict_badge) || conflict_badge == "0",
              info = "Should show no conflicts")
  
  # Verify "Resolve Conflicts" button is disabled or hidden
  button_state <- app$get_value(input = "admin-resolve_conflicts")
  expect_true(is.null(button_state) || !button_state$enabled,
              info = "Resolve button should be disabled when no conflicts")
  
  cleanup_sync_environment()
})

# ============================================================================
# TESTS - Performance & Usability
# ============================================================================

test_that("conflict list paginates for large conflict sets", {
  skip("Pagination not yet implemented")
  
  setup_sync_environment()
  cleanup_sync_environment()
  
  # Create 50+ conflicts
  for (i in 1:50) {
    create_test_conflict(
      plot_number = sprintf("PERF-%03d", i),
      field_name = "Elevation",
      local_value = as.character(1000 + i),
      cloud_value = as.character(1050 + i)
    )
  }
  
  app <- AppDriver$new(name = "conflict-pagination", timeout = 20000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(2000)
  
  # Verify pagination controls appear
  pagination <- app$get_value(output = "admin-conflict_pagination")
  expect_true(!is.null(pagination),
              info = "Pagination should appear for large conflict lists")
  
  # Verify initial page shows 25 conflicts (default page size)
  conflict_table <- app$get_value(output = "admin-conflict_list")
  expect_lte(nrow(conflict_table), 25,
             info = "Should limit initial display to page size")
  
  cleanup_sync_environment()
})

test_that("conflict resolution completes within reasonable time", {
  skip("Performance benchmarking not yet implemented")
  skip_on_ci()
  
  setup_sync_environment()
  cleanup_sync_environment()
  conflict_ids <- create_conflict_scenario(n_conflicts = 10)
  
  app <- AppDriver$new(name = "conflict-performance", timeout = 30000)
  on.exit(app$stop(), add = TRUE)
  
  app$click("nav-admin")
  app$click("admin-resolve_conflicts")
  app$wait_for_idle(1000)
  
  start_time <- Sys.time()
  
  # Batch resolve all conflicts
  app$click("admin-accept_all_local")
  app$wait_for_idle(5000)
  
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  expect_lt(elapsed, 10,
            info = paste("Batch resolution took", round(elapsed, 1), 
                        "seconds - should be < 10"))
  
  cleanup_sync_environment()
})

# ============================================================================
# CLEANUP
# ============================================================================

# Ensure sync environment is cleaned up after test run
withr::defer({
  cleanup_sync_environment()
}, teardown_env())

}
