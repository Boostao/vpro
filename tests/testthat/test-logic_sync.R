testthat::context("logic_sync")

library(DBI)
library(duckdb)
source(here::here("tests", "testthat", "setup.R"))
source(here::here("tests", "testthat", "helpers.R"))
source(here::here("R", "logic_sync.R"))

# =============================================================================
# Test infrastructure
# =============================================================================
#
# We simulate the cloud PostgreSQL master using a second DuckDB file attached
# as the `master` catalog. This avoids any live-database dependency and keeps
# tests fast and reproducible.
#
# Layout:
#   local_con (in-memory DuckDB)  — field user's working copy
#   master_path (temp DuckDB file) — simulates master.core / staging / admin
# =============================================================================

# Build the master DuckDB schema (mirrors the PostgreSQL layout without triggers)
.setup_master_db <- function(master_path) {
  mc <- DBI::dbConnect(duckdb::duckdb(), master_path)
  on.exit(DBI::dbDisconnect(mc), add = TRUE)

  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS core")
  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS staging")
  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS admin")
  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS lists")

  # lists tables (mirror local vpro_lists.duckdb structure for test purposes)
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS lists.USysTableOfLists (
      listname        TEXT,
      item            TEXT,
      itemorder       DOUBLE,
      itemdescription TEXT
    )
  ")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS lists.USysZoneList (
      _zone                TEXT,
      subzone              TEXT,
      zonedescription      TEXT,
      subzonevardescription TEXT
    )
  ")

  # core.env
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.env (
      id            INTEGER,
      \"PlotNumber\"   TEXT NOT NULL UNIQUE,
      \"ProjectID\"    INTEGER NOT NULL,
      \"Latitude\"      DOUBLE,
      \"Longitude\"     DOUBLE,
      \"Elevation\"   INTEGER,
      \"SurveyDate\"   DATE,
      \"SurveyorName\" TEXT,
      \"PlotNotes\"    TEXT,
      \"Zone\"         TEXT,
      \"SubZone\"      TEXT,
      \"SiteSeries\"   TEXT,
      \"rowVersion\"   INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"   TEXT
    )
  ")

  # core.su
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.su (
      id            INTEGER,
      \"PlotNumber\"   TEXT NOT NULL UNIQUE,
      \"ProjectID\"    INTEGER NOT NULL,
      \"SiteUnit\"     TEXT,
      \"BecZone\"      TEXT,
      \"BecSubzone\"   TEXT,
      \"SiteSeries\"   TEXT,
      \"rowVersion\"   INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"   TEXT
    )
  ")

  # core.veg
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.veg (
      id            INTEGER,
      \"PlotNumber\"   TEXT NOT NULL,
      \"SpeciesCode\"  TEXT NOT NULL,
      \"LayerCode\"    TEXT NOT NULL,
      \"Cover1\"  REAL, \"Height1\" REAL,
      \"Cover2\"  REAL, \"Height2\" REAL,
      \"Cover3\"  REAL, \"Height3\" REAL,
      \"TotalA\"  REAL, \"HeightA\" REAL,
      \"Cover4\"  REAL, \"Height4\" REAL,
      \"Cover5\"  REAL, \"Height5\" REAL,
      \"Cover5a\" REAL, \"Height5a\" REAL,
      \"Cover5b\" REAL, \"Height5b\" REAL,
      \"Cover5c\" REAL, \"Height5c\" REAL,
      \"TotalB\"  REAL, \"HeightB\" TEXT,
      \"Cover6\"  REAL, \"Height6\" REAL,
      \"Cover7\"  REAL, \"Cover8\"  REAL,
      \"Cover9\"  REAL, \"Cover10\" REAL,
      \"Collected\" TEXT,
      \"Flag\"      BOOLEAN,
      \"vegId\"    INTEGER,
      ll INTEGER, af INTEGER, dc INTEGER, ut INTEGER, vi INTEGER,
      pv INTEGER, pg INTEGER, ffa INTEGER,
      cultural1 INTEGER, cultural2 INTEGER,
      other1 INTEGER, other2 INTEGER,
      \"ProjectID\" INTEGER NOT NULL,
      \"rowVersion\" INTEGER NOT NULL DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\" TEXT,
      UNIQUE(\"PlotNumber\", \"SpeciesCode\", \"LayerCode\", \"ProjectID\")
    )
  ")

  # staging.env
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS staging.env_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS staging.env (
      id                INTEGER PRIMARY KEY DEFAULT nextval('staging.env_seq'),
      \"mergeRequestID\"  INTEGER NOT NULL,
      \"changeType\"       TEXT NOT NULL,
      \"baseRowVersion\"  INTEGER,
      \"PlotNumber\"       TEXT NOT NULL,
      \"ProjectID\"        INTEGER NOT NULL,
      \"Latitude\"          DOUBLE,
      \"Longitude\"         DOUBLE,
      \"Elevation\"       INTEGER,
      \"SurveyDate\"       DATE,
      \"SurveyorName\"     TEXT,
      \"PlotNotes\"        TEXT,
      \"Zone\"             TEXT,
      \"SubZone\"          TEXT,
      \"SiteSeries\"       TEXT,
      \"modifiedBy\"       TEXT,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now()
    )
  ")

  # staging.su
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS staging.su_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS staging.su (
      id                INTEGER PRIMARY KEY DEFAULT nextval('staging.su_seq'),
      \"mergeRequestID\"  INTEGER NOT NULL,
      \"changeType\"       TEXT NOT NULL,
      \"baseRowVersion\"  INTEGER,
      \"PlotNumber\"       TEXT NOT NULL,
      \"ProjectID\"        INTEGER NOT NULL,
      \"SiteUnit\"         TEXT,
      \"BecZone\"          TEXT,
      \"BecSubzone\"       TEXT,
      \"SiteSeries\"       TEXT,
      \"modifiedBy\"       TEXT,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now()
    )
  ")

  # staging.veg
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS staging.veg_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS staging.veg (
      id                INTEGER PRIMARY KEY DEFAULT nextval('staging.veg_seq'),
      \"mergeRequestID\"  INTEGER NOT NULL,
      \"changeType\"       TEXT NOT NULL,
      \"baseRowVersion\"  INTEGER,
      \"PlotNumber\"       TEXT NOT NULL,
      \"SpeciesCode\"      TEXT NOT NULL,
      \"LayerCode\"        TEXT,
      \"Cover1\" REAL, \"Height1\" REAL, \"Cover2\" REAL, \"Height2\" REAL,
      \"Cover3\" REAL, \"Height3\" REAL, \"TotalA\" REAL, \"HeightA\" REAL,
      \"Cover4\" REAL, \"Height4\" REAL, \"Cover5\" REAL, \"Height5\" REAL,
      \"Cover5a\" REAL, \"Height5a\" REAL, \"Cover5b\" REAL, \"Height5b\" REAL,
      \"Cover5c\" REAL, \"Height5c\" REAL, \"TotalB\" REAL, \"HeightB\" TEXT,
      \"Cover6\" REAL, \"Height6\" REAL, \"Cover7\" REAL, \"Cover8\" REAL,
      \"Cover9\" REAL, \"Cover10\" REAL, \"Collected\" TEXT, \"Flag\" BOOLEAN,
      \"vegId\" INTEGER, ll INTEGER, af INTEGER, dc INTEGER, ut INTEGER,
      vi INTEGER, pv INTEGER, pg INTEGER, ffa INTEGER,
      cultural1 INTEGER, cultural2 INTEGER, other1 INTEGER, other2 INTEGER,
      \"ProjectID\"        INTEGER NOT NULL,
      \"modifiedBy\"       TEXT,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now()
    )
  ")

  # admin.merge_requests (sequence + table)
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mr_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS admin.merge_requests (
      id                 INTEGER PRIMARY KEY DEFAULT nextval('admin.mr_seq'),
      project_id         INTEGER NOT NULL,
      submitter_user_id  INTEGER,
      submitter_name     TEXT NOT NULL,
      submitted_utc      TIMESTAMPTZ DEFAULT now(),
      status             TEXT NOT NULL DEFAULT 'pending_review',
      reviewer_user_id   INTEGER,
      reviewer           TEXT,
      review_notes       TEXT,
      reviewed_utc       TIMESTAMPTZ,
      env_record_count   INTEGER DEFAULT 0,
      su_record_count    INTEGER DEFAULT 0,
      veg_record_count   INTEGER DEFAULT 0,
      compliance_passed  BOOLEAN,
      compliance_report  TEXT
    )
  ")

  # admin.users (minimal seed; used for merge_history approved_by_user_id lookup)
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.users_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS admin.users (
      id        INTEGER PRIMARY KEY DEFAULT nextval('admin.users_seq'),
      email     TEXT UNIQUE NOT NULL,
      full_name TEXT NOT NULL DEFAULT '',
      app_role  TEXT DEFAULT 'guest',
      is_active BOOLEAN DEFAULT TRUE
    )
  ")
  # Seed all test actors so submitter_user_id / reviewer_user_id can be resolved.
  # admin@test.local is seeded first so it reliably receives id = 1.
  DBI::dbExecute(mc, "
    INSERT INTO admin.users (email, full_name, app_role) VALUES
      ('admin@test.local', 'Test Admin',  'admin'),
      ('alice@test.local', 'Alice',        'guest'),
      ('bob@test.local',   'Bob',          'guest'),
      ('carol@test.local', 'Carol',        'guest'),
      ('dave@test.local',  'Dave',         'guest'),
      ('auto@test.local',  'Auto',         'guest'),
      ('eve@test.local',   'Eve',          'guest'),
      ('frank@test.local', 'Frank',        'guest'),
      ('grace@test.local', 'Grace',        'guest'),
      ('hank@test.local',  'Hank',         'guest'),
      ('ivy@test.local',   'Ivy',          'guest'),
      ('jack@test.local',  'Jack',         'guest'),
      ('kim@test.local',   'Kim',          'guest')
    ON CONFLICT DO NOTHING
  ")

  # admin.merge_history
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mh_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS admin.merge_history (
      id                  INTEGER PRIMARY KEY DEFAULT nextval('admin.mh_seq'),
      merge_request_id    INTEGER NOT NULL,
      merged_utc          TIMESTAMPTZ DEFAULT now(),
      approved_by_user_id INTEGER,
      record_count        INTEGER,
      merge_summary       TEXT
    )
  ")

  # admin.merge_conflicts (sequence + table)
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mc_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS admin.merge_conflicts (
      id                 INTEGER PRIMARY KEY DEFAULT nextval('admin.mc_seq'),
      merge_request_id   INTEGER NOT NULL,
      table_name         TEXT NOT NULL,
      plot_number        TEXT,
      project_id         TEXT,
      species_code       TEXT NOT NULL DEFAULT '',
      layer_code         TEXT NOT NULL DEFAULT '',
      details            TEXT,
      resolution         TEXT,
      resolved_by        TEXT,
      resolved_utc       TIMESTAMPTZ,
      created_utc        TIMESTAMPTZ DEFAULT now(),
      UNIQUE(merge_request_id, table_name, plot_number, project_id, species_code, layer_code)
    )
  ")
}

# Create a local DuckDB connection with Env / SU / Veg field tables and the
# master DuckDB file attached as catalog `master`.
.make_test_con <- function(master_path) {
  local_con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")

  # Local field tables (PascalCase, minimal for tests)
  DBI::dbExecute(local_con, "
    CREATE TABLE Env (
      PlotNumber   TEXT,
      ProjectID    TEXT,
      Latitude     DOUBLE,
      Longitude    DOUBLE,
      Elevation    DOUBLE,
      Date         DATE,
      SiteSurveyor TEXT,
      SiteNotes    TEXT,
      Zone         TEXT,
      SubZone      TEXT,
      SiteSeries   TEXT
    )
  ")
  DBI::dbExecute(local_con, "
    CREATE TABLE SU (
      PlotNumber TEXT,
      SiteUnit   TEXT
    )
  ")
  DBI::dbExecute(local_con, "
    CREATE TABLE Veg (
      PlotNumber TEXT,
      Species    TEXT,
      Layer      TEXT,
      Cover1     TEXT,
      Height1    TEXT,
      Cover2     TEXT,
      Height2    TEXT,
      Cover3     TEXT,
      Height3    TEXT,
      TotalA     TEXT,
      HeightA    TEXT,
      Cover4     TEXT,
      Height4    TEXT,
      Cover5     TEXT,
      Height5    TEXT,
      Cover5a    TEXT,
      Height5a   TEXT,
      Cover5b    TEXT,
      Height5b   TEXT,
      Cover5c    TEXT,
      Height5c   TEXT,
      TotalB     TEXT,
      HeightB    TEXT,
      Cover6     TEXT,
      Height6    TEXT,
      Cover7     TEXT,
      Cover8     TEXT,
      Cover9     TEXT,
      Cover10    TEXT,
      Collected  TEXT,
      Flag       TEXT,
      ID         INTEGER,
      LL TEXT, AF TEXT, DC TEXT, UT TEXT, VI TEXT,
      PV TEXT, PG TEXT, FFA TEXT,
      Cultural1 TEXT, Cultural2 TEXT, Other1 TEXT, Other2 TEXT
    )
  ")

  # Attach the master DuckDB file
  DBI::dbExecute(local_con, paste0("ATTACH '", master_path, "' AS master"))

  local_con
}

# Convenience: build a fresh pair (local, master) and run a test body.
# Returns list(con, master_path); caller is responsible for cleanup.
.sync_test_setup <- function() {
  master_path <- tempfile(fileext = ".duckdb")
  .setup_master_db(master_path)
  con         <- .make_test_con(master_path)
  list(con = con, master_path = master_path)
}

.sync_test_teardown <- function(setup) {
  tryCatch(DBI::dbDisconnect(setup$con, shutdown = TRUE), error = function(e) NULL)
  tryCatch(unlink(setup$master_path), error = function(e) NULL)
  if (!is.null(setup$lists_path)) tryCatch(unlink(setup$lists_path), error = function(e) NULL)
}


# =============================================================================
# Tests — Local infrastructure
# =============================================================================

testthat::test_that("sync_ensure_local_tables creates sync schema and tables", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  sync_ensure_local_tables(con)

  testthat::expect_true(
    DBI::dbExistsTable(con, DBI::Id(schema = "sync", table = "watermarks"))
  )
  testthat::expect_true(
    DBI::dbExistsTable(con, DBI::Id(schema = "sync", table = "conflict_queue"))
  )
  # master_row_version should be added to Env and SU
  env_cols <- DBI::dbListFields(con, "Env")
  testthat::expect_true("master_row_version" %in% env_cols)
  su_cols  <- DBI::dbListFields(con, "SU")
  testthat::expect_true("master_row_version" %in% su_cols)
})

testthat::test_that("watermark round-trip stores and retrieves timestamp", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con
  sync_ensure_local_tables(con)

  ts <- as.POSIXct("2026-01-15 08:00:00", tz = "UTC")
  sync_set_watermark(con, "env", "pull", ts)
  got <- sync_get_watermark(con, "env", "pull")

  testthat::expect_false(is.null(got))
  # Flexible comparison: allow sub-second rounding
  testthat::expect_equal(as.numeric(as.POSIXct(got, tz = "UTC")),
                         as.numeric(ts), tolerance = 2)
})

testthat::test_that("sync_get_watermark returns NULL when no record exists", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con
  sync_ensure_local_tables(con)

  testthat::expect_null(sync_get_watermark(con, "env",  "pull"))
  testthat::expect_null(sync_get_watermark(con, "veg", "push"))
})


# =============================================================================
# Tests — Pull: master.core -> local
# =============================================================================

testthat::test_that("sync_pull inserts new master env record locally (fast-forward)", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Seed master with one env row
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-001', 1, 53.1, -120.2, 950, DATE '2026-01-01', 'Field A', 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  local_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Env")$n[1]
  testthat::expect_equal(local_count, 1L)
  testthat::expect_equal(result$env$pulled, 1L)
  testthat::expect_equal(result$env$fast_forwarded, 1L)
  testthat::expect_equal(result$env$conflicts, 0L)

  # master_row_version should be set to 1
  mrv <- DBI::dbGetQuery(con, "SELECT master_row_version FROM Env WHERE PlotNumber = 'P-001'")$master_row_version[1]
  testthat::expect_equal(as.integer(mrv), 1L)
})

testthat::test_that("sync_pull fast-forwards when master updated but local unchanged", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # The local row already matches the initial master values; master_row_version = 1
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-010', 1, 50.0, -119.0, 800, 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Now master gets updated (row_version -> 2, new elevation)
  DBI::dbExecute(
    con,
    "UPDATE master.core.env
     SET \"Elevation\" = 900, \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-010'"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Should fast-forward (local was never modified by user — still has original values)
  local <- DBI::dbGetQuery(con, "SELECT Elevation, master_row_version FROM Env WHERE PlotNumber = 'P-010'")
  testthat::expect_equal(as.integer(local$Elevation[1]), 900L)
  testthat::expect_equal(as.integer(local$master_row_version[1]), 2L)
  testthat::expect_equal(result$env$conflicts, 0L)
})

testthat::test_that("sync_pull detects true conflict when both sides diverged", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Initial pull: plant the row locally with master_row_version = 1
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-020', 1, 50.0, -119.0, 800, 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # User edits the local copy (different elevation) — mark the row dirty
  DBI::dbExecute(
    con,
    "UPDATE Env SET Elevation = 1200, local_modified_utc = now() WHERE PlotNumber = 'P-020'"
  )
  # master_row_version is still 1 (user edit doesn't change it)

  # Master also updates (row_version -> 2, different elevation)
  DBI::dbExecute(
    con,
    "UPDATE master.core.env
     SET \"Elevation\" = 600, \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-020'"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Should detect a conflict, NOT overwrite local
  testthat::expect_equal(result$env$conflicts, 1L)
  local_elev <- DBI::dbGetQuery(con, "SELECT Elevation FROM Env WHERE PlotNumber = 'P-020'")$Elevation[1]
  testthat::expect_equal(as.numeric(local_elev), 1200)   # local value preserved

  queue <- sync_get_local_conflicts(con, project_id = "1")
  testthat::expect_equal(nrow(queue), 1L)
  testthat::expect_equal(queue$table_name[1], "env")
})

testthat::test_that("sync_pull inserts new master su record locally", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.su
       (\"PlotNumber\", \"ProjectID\", \"SiteUnit\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-030', 1, 'SU-Alpha', 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "su", allow_attach = FALSE)

  row <- DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU WHERE PlotNumber = 'P-030'")
  testthat::expect_equal(nrow(row), 1L)
  testthat::expect_equal(row$SiteUnit[1], "SU-Alpha")
  testthat::expect_equal(result$su$fast_forwarded, 1L)
})

# =============================================================================
# Tests — Column coverage (comprehensive field sync)
# =============================================================================

testthat::test_that("sync_pull env includes Zone/SubZone/SiteSeries columns", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Seed master with all env columns including Zone, SubZone, SiteSeries
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"PlotNotes\",
        \"Zone\", \"SubZone\", \"SiteSeries\",
        \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-ZONE-001', 1, 53.1, -120.2, 950, DATE '2026-01-01', 'Field A', 'Test plot',
             'CWH', 'dm', 'CWHdm09', 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Verify all columns were synced including Zone/SubZone/SiteSeries
  row <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber, Zone, SubZone, SiteSeries FROM Env WHERE PlotNumber = 'P-ZONE-001'"
  )
  testthat::expect_equal(nrow(row), 1L)
  testthat::expect_equal(row$Zone[1], "CWH")
  testthat::expect_equal(row$SubZone[1], "dm")
  testthat::expect_equal(row$SiteSeries[1], "CWHdm09")
  testthat::expect_equal(result$env$fast_forwarded, 1L)
})

testthat::test_that("sync_pull detects env conflict when Zone/SubZone/SiteSeries differs", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Insert master record
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"PlotNotes\",
        \"Zone\", \"SubZone\", \"SiteSeries\",
        \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-ZONE-002', 1, 53.1, -120.2, 950, DATE '2026-01-01', 'Field A', 'Test',
             'CWH', 'dm', 'CWHdm09', 1, now())"
  )

  # Insert local record with different Zone
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)
  DBI::dbExecute(
    con,
    "UPDATE Env SET Zone = 'IDF', local_modified_utc = now() WHERE PlotNumber = 'P-ZONE-002'"
  )

  # Update master Zone (now both sides differ)
  DBI::dbExecute(
    con,
    "UPDATE master.core.env
     SET \"Zone\" = 'ESSF', \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-ZONE-002'"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Should detect conflict on Zone
  testthat::expect_equal(result$env$conflicts, 1L)
})

testthat::test_that("sync_pull veg includes all Height and supplemental columns", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # First, insert env record so veg pull can find the project
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-VEG-001', 1, 53.1, -120.2, 950, DATE '2026-01-01', 'Field A', 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Now seed master.veg with all column values including Height3-6, ID, AF-FFA, Cultural1-2, Other1-2
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.veg
       (\"PlotNumber\", \"SpeciesCode\", \"LayerCode\",
        \"Cover1\", \"Height1\", \"Cover2\", \"Height2\", \"Cover3\", \"Height3\",
        \"TotalA\", \"HeightA\", \"Cover4\", \"Height4\", \"Cover5\", \"Height5\",
        \"Cover5a\", \"Height5a\", \"Cover5b\", \"Height5b\", \"Cover5c\", \"Height5c\",
        \"TotalB\", \"HeightB\", \"Cover6\", \"Height6\",
        \"Cover7\", \"Cover8\", \"Cover9\", \"Cover10\",
        collected, flag, ll, af, dc, ut, vi, pv, pg, ffa,
        \"Cultural1\", \"Cultural2\", \"Other1\", \"Other2\",
        \"ProjectID\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-VEG-001', 'TSUGHET', '1',
             25, 15.5, 20, 12.0, 15, 10.5,
             60, 14.0, 10, 8.0, 5, 6.5,
             2, 5.0, 2, 5.0, 1, 4.5,
             50, 8.0, 5, 4.0,
             0, 0, 0, 0,
             'Y', 0, 1, 1, 2, 1, 2, 3, 2, 1,
             'C1Value', 'C2Value', 'O1Value', 'O2Value',
             1, 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "veg", allow_attach = FALSE)

  # Verify comprehensive column coverage
  row <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber, Height3, Height6, ID, AF, FFA, Cultural1, Other2
     FROM Veg WHERE PlotNumber = 'P-VEG-001'"
  )
  testthat::expect_equal(nrow(row), 1L)
  testthat::expect_equal(as.numeric(row$Height3[1]), 10.5)
  testthat::expect_equal(as.numeric(row$Height6[1]), 4.0)
  testthat::expect_equal(as.integer(row$ID[1]), 1L)
  testthat::expect_equal(as.integer(row$AF[1]), 1L)
  testthat::expect_equal(as.integer(row$FFA[1]), 1L)
  testthat::expect_equal(row$Cultural1[1], "C1Value")
  testthat::expect_equal(row$Other2[1], "O2Value")
  testthat::expect_equal(result$veg$fast_forwarded, 1L)
})

testthat::test_that("sync_push detects env changes in Zone/SubZone/SiteSeries", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Insert master env record
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"PlotNotes\",
        \"Zone\", \"SubZone\", \"SiteSeries\",
        \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-PUSH-ZONE', 1, 53.1, -120.2, 950, DATE '2026-01-01', 'Field A', 'Test',
             'CWH', 'dm', 'CWHdm09', 1, now())"
  )

  # Pull it locally
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Update local Zone (trigger delta detection)
  DBI::dbExecute(
    con,
    "UPDATE Env SET Zone = 'IDF', local_modified_utc = now() WHERE PlotNumber = 'P-PUSH-ZONE'"
  )

  # Push should detect the change and create a staging row
  result <- sync_push(con, project_id = 1, tables = "env", submitter = "test_user")

  # Verify merge request was created
  testthat::expect_true(result$mr_id > 0)

  # Verify staging.env contains the Zone change
  staging <- DBI::dbGetQuery(
    con,
    "SELECT \"PlotNumber\", \"Zone\" FROM master.staging.env WHERE \"PlotNumber\" = 'P-PUSH-ZONE'"
  )
  testthat::expect_equal(nrow(staging), 1L)
  testthat::expect_equal(staging$Zone[1], "IDF")
})

testthat::test_that("sync_pull fresh empty local DB populates all env columns including Zone/SubZone/SiteSeries", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Create a completely fresh local Env table without any seed data
  DBI::dbExecute(con, "DELETE FROM Env")

  # Seed master with a complete env record including all optional columns
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"PlotNotes\",
        \"Zone\", \"SubZone\", \"SiteSeries\",
        \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-FRESH-001', 1, 54.5, -121.0, 1200, DATE '2026-02-01', 'Fresh Field', 'New plot',
             'ESSF', 'xc', 'ESSFxc19', 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Verify all columns populated including optional ones
  row <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes,
            Zone, SubZone, SiteSeries, master_row_version
     FROM Env WHERE PlotNumber = 'P-FRESH-001'"
  )

  testthat::expect_equal(nrow(row), 1L)
  testthat::expect_equal(row$Latitude[1], 54.5)
  testthat::expect_equal(row$Zone[1], "ESSF")
  testthat::expect_equal(row$SubZone[1], "xc")
  testthat::expect_equal(row$SiteSeries[1], "ESSFxc19")
  testthat::expect_equal(as.integer(row$master_row_version[1]), 1L)
  testthat::expect_equal(result$env$pulled, 1L)
  testthat::expect_equal(result$env$fast_forwarded, 1L)
})

testthat::test_that("sync_pull fresh empty local Veg table populates all columns", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Prepare env record first
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
        \"SurveyDate\", \"SurveyorName\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-VEG-FRESH', 1, 54.5, -121.0, 1200, DATE '2026-02-01', 'Fresh Field', 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  # Delete local veg to simulate fresh database
  DBI::dbExecute(con, "DELETE FROM Veg")

  # Seed comprehensive veg record
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.veg
       (\"PlotNumber\", \"SpeciesCode\", \"LayerCode\",
        \"Cover1\", \"Height1\", \"Cover2\", \"Height2\", \"Cover3\", \"Height3\",
        \"TotalA\", \"HeightA\", \"Cover4\", \"Height4\", \"Cover5\", \"Height5\",
        \"Cover5a\", \"Height5a\", \"Cover5b\", \"Height5b\", \"Cover5c\", \"Height5c\",
        \"TotalB\", \"HeightB\", \"Cover6\", \"Height6\",
        \"Cover7\", \"Cover8\", \"Cover9\", \"Cover10\",
        collected, flag, ll, af, dc, ut, vi, pv, pg, ffa,
        \"Cultural1\", \"Cultural2\", \"Other1\", \"Other2\",
        \"ProjectID\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-VEG-FRESH', 'PICEAEN', '2',
             35, 18.5, 25, 14.0, 18, 11.5,
             70, 16.0, 12, 9.0, 8, 7.5,
             3, 6.0, 2, 5.5, 1, 5.0,
             45, 9.0, 3, 3.5,
             0, 0, 0, 0,
             'Y', 1, 0, 2, 1, 0, 1, 2, 1, 2,
             'Fresh1', 'Fresh2', 'Other1Fresh', 'Other2Fresh',
             1, 1, now())"
  )

  result <- sync_pull(con, project_id = 1, tables = "veg", allow_attach = FALSE)

  # Verify comprehensive column population
  row <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber, Species, Layer, Cover1, Height3, Height6, ID, AF, FFA,
            Cultural1, Other1, master_row_version
     FROM Veg WHERE PlotNumber = 'P-VEG-FRESH'"
  )

  testthat::expect_equal(nrow(row), 1L)
  testthat::expect_equal(row$Species[1], "PICEAEN")
  testthat::expect_equal(row$Layer[1], "2")
  testthat::expect_equal(as.numeric(row$Cover1[1]), 35)
  testthat::expect_equal(as.numeric(row$Height3[1]), 11.5)
  testthat::expect_equal(as.numeric(row$Height6[1]), 3.5)
  testthat::expect_equal(as.integer(row$ID[1]), 1L)
  testthat::expect_equal(as.integer(row$AF[1]), 2L)
  testthat::expect_equal(as.integer(row$FFA[1]), 2L)
  testthat::expect_equal(row$Cultural1[1], "Fresh1")
  testthat::expect_equal(row$Other1[1], "Other1Fresh")
  testthat::expect_equal(as.integer(row$master_row_version[1]), 1L)
  testthat::expect_equal(result$veg$pulled, 1L)
})

testthat::test_that("sync_count_local_conflicts returns 0 when queue is empty", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  sync_ensure_local_tables(s$con)
  testthat::expect_equal(sync_count_local_conflicts(s$con), 0L)
})

testthat::test_that("sync_resolve_local_conflict keep_local marks resolved without touching local", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-040', 1, 50.0, 800, 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)
  DBI::dbExecute(con, "UPDATE Env SET Elevation = 1000, local_modified_utc = now() WHERE PlotNumber = 'P-040'")
  DBI::dbExecute(
    con,
    "UPDATE master.core.env SET \"Elevation\" = 600, \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-040'"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  conflicts <- sync_get_local_conflicts(con)
  testthat::expect_equal(nrow(conflicts), 1L)

  sync_resolve_local_conflict(con, conflicts$id[1], "keep_local")

  # Local elevation unchanged
  elev <- DBI::dbGetQuery(con, "SELECT Elevation FROM Env WHERE PlotNumber = 'P-040'")$Elevation[1]
  testthat::expect_equal(as.numeric(elev), 1000)

  # Queue entry no longer in unresolved
  testthat::expect_equal(sync_count_local_conflicts(con), 0L)
})

testthat::test_that("sync_resolve_local_conflict accept_master overwrites local env", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-050', 1, 50.0, 800, 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)
  DBI::dbExecute(con, "UPDATE Env SET Elevation = 1000, local_modified_utc = now() WHERE PlotNumber = 'P-050'")
  DBI::dbExecute(
    con,
    "UPDATE master.core.env
     SET \"Elevation\" = 300, \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-050'"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)

  conflicts <- sync_get_local_conflicts(con)
  sync_resolve_local_conflict(con, conflicts$id[1], "accept_master")

  elev <- DBI::dbGetQuery(con, "SELECT Elevation FROM Env WHERE PlotNumber = 'P-050'")$Elevation[1]
  testthat::expect_equal(as.numeric(elev), 300)
  testthat::expect_equal(sync_count_local_conflicts(con), 0L)
})


# =============================================================================
# Tests — Push: local -> master.staging
# =============================================================================

testthat::test_that("sync_push creates merge request and stages new env row", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-101', '1', 52.7, -118.9, 1234, DATE '2026-02-01', 'Alice', 'notes')"
  )

  results <- sync_push(con, project_id = 1, submitter = "alice@test.local", tables = "env",
                       allow_attach = FALSE)

  testthat::expect_true(!is.null(results$merge_request_id))
  testthat::expect_equal(results$env, 1L)

  staged <- DBI::dbGetQuery(
    con,
    "SELECT \"changeType\", \"baseRowVersion\" FROM master.staging.env
     WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )
  testthat::expect_equal(nrow(staged), 1L)
  testthat::expect_equal(staged$changeType[1], "I")       # new row
  testthat::expect_true(is.na(staged$baseRowVersion[1]))  # no prior master version

  mr <- DBI::dbGetQuery(
    con,
    "SELECT env_record_count, status FROM master.admin.merge_requests WHERE id = ?",
    list(results$merge_request_id)
  )
  testthat::expect_equal(mr$env_record_count[1], 1L)
  testthat::expect_equal(mr$status[1], "pending_review")
})

testthat::test_that("sync_push captures base_row_version for existing master row", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Existing master row at version 3
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\", \"modifiedBy\")
     VALUES ('P-110', 1, 50.0, 800, 3, now(), 'master_user')"
  )

  # Local version differs (elevation changed by user)
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-110', '1', 50.0, -120.0, 999, DATE '2026-02-01', 'Bob', '')"
  )

  results <- sync_push(con, project_id = 1, submitter = "bob@test.local", tables = "env",
                       allow_attach = FALSE)

  staged <- DBI::dbGetQuery(
    con,
    "SELECT \"changeType\", \"baseRowVersion\" FROM master.staging.env WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )
  testthat::expect_equal(staged$changeType[1], "U")
  testthat::expect_equal(staged$baseRowVersion[1], 3L)  # captured at push time
})

testthat::test_that("sync_push stages su and veg rows in the same merge request", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes, Zone, SubZone, SiteSeries)
     VALUES ('P-120', '1', 52.0, -119.0, 1000, DATE '2026-02-01', 'Carol', '', 'ICH', 'mk', '01')"
  )
  DBI::dbExecute(con, "INSERT INTO SU (PlotNumber, SiteUnit) VALUES ('P-120', 'ICH mk 01')")
  DBI::dbExecute(
    con,
    "INSERT INTO Veg (PlotNumber, Species, Layer, Cover1) VALUES ('P-120', 'TSUGHET', 'T1', '30')"
  )

  results <- sync_push(con, project_id = 1, submitter = "carol@test.local",
                       tables = c("env", "su", "veg"), allow_attach = FALSE)

  testthat::expect_equal(results$env, 1L)
  testthat::expect_equal(results$su,  1L)
  testthat::expect_equal(results$veg, 1L)

  env_staged <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.env WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )$n[1]
  su_staged  <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.su  WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )$n[1]
  veg_staged <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.veg WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )$n[1]

  testthat::expect_equal(env_staged, 1L)
  testthat::expect_equal(su_staged,  1L)
  testthat::expect_equal(veg_staged, 1L)
})

testthat::test_that("sync_push is blocked when unresolved pull conflicts exist", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Create a pull conflict
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\")
     VALUES ('P-130', 1, 50.0, 800, 1, now())"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)
  DBI::dbExecute(con, "UPDATE Env SET Elevation = 999, local_modified_utc = now() WHERE PlotNumber = 'P-130'")
  DBI::dbExecute(
    con,
    "UPDATE master.core.env SET \"Elevation\" = 100, \"rowVersion\" = 2, \"lastModifiedUTC\" = now()
     WHERE \"PlotNumber\" = 'P-130'"
  )
  sync_pull(con, project_id = 1, tables = "env", allow_attach = FALSE)
  testthat::expect_equal(sync_count_local_conflicts(con, project_id = "1"), 1L)

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-131', '1', 55.0, -120.0, 500, DATE '2026-01-01', 'Dave', '')"
  )

  testthat::expect_error(
    sync_push(con, project_id = 1, submitter = "dave@test.local", allow_attach = FALSE),
    "Push blocked"
  )
})

testthat::test_that("sync_push skips unchanged rows (no delta = no staging row)", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Identical data in both master and local
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\", \"modifiedBy\")
     VALUES ('P-140', 1, 53.0, -120.0, 700, 1, now(), 'system')"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-140', '1', 53.0, -120.0, 700, NULL, NULL, NULL)"
  )

  results <- sync_push(con, project_id = 1, submitter = "auto@test.local", tables = "env",
                       allow_attach = FALSE)
  testthat::expect_equal(results$env, 0L)

  n_staged <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.env WHERE \"mergeRequestID\" = ?",
    list(results$merge_request_id)
  )$n[1]
  testthat::expect_equal(n_staged, 0L)
})


# =============================================================================
# Tests — Server-side merge management
# =============================================================================

testthat::test_that("merge_request_refresh_conflicts detects row_version mismatch", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # User pushes based on master at row_version = 1
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (\"PlotNumber\", \"ProjectID\", \"Latitude\", \"Elevation\", \"rowVersion\", \"lastModifiedUTC\", \"modifiedBy\")
     VALUES ('P-200', 1, 50.0, 800, 1, now(), 'original')"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-200', '1', 50.0, -120.0, 900, DATE '2026-01-01', 'Eve', '')"
  )
  results <- sync_push(con, project_id = 1, submitter = "eve@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  # Simulate concurrent master edit AFTER push (row_version advances to 2)
  DBI::dbExecute(
    con,
    "UPDATE master.core.env SET \"Elevation\" = 500, \"rowVersion\" = 2 WHERE \"PlotNumber\" = 'P-200'"
  )

  merge_request_refresh_conflicts(con, mr_id)

  conflicts <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
  testthat::expect_equal(nrow(conflicts), 1L)
  testthat::expect_equal(conflicts$table_name[1], "env")
  testthat::expect_equal(conflicts$plot_number[1], "P-200")
})

testthat::test_that("merge_request_refresh_conflicts finds no conflict when master unchanged", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Push with base_row_version = 2; master still at 2 → no conflict
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (plot_number, project_id, latitude, elevation_m, row_version, last_modified_utc, modified_by)
     VALUES ('P-210', 1, 50.0, 800, 2, now(), 'admin')"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-210', '1', 50.0, -120.0, 900, DATE '2026-01-01', 'Frank', '')"
  )
  results <- sync_push(con, project_id = 1, submitter = "frank@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  # No concurrent master changes
  merge_request_refresh_conflicts(con, mr_id)

  conflicts <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
  testthat::expect_equal(nrow(conflicts), 0L)
})

testthat::test_that("merge_approve_request applies staged rows to core", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # No existing master row → new insert
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-300', '1', 54.0, -121.0, 1500, DATE '2026-03-01', 'Grace', 'summit plot')"
  )
  results <- sync_push(con, project_id = 1, submitter = "grace@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  merge_approve_request(con, mr_id, reviewer = "admin@test.local", review_notes = "looks good")

  # Row should be in core
  core_row <- DBI::dbGetQuery(
    con, "SELECT \"PlotNumber\", \"Elevation\" FROM master.core.env WHERE \"PlotNumber\" = 'P-300'"
  )
  testthat::expect_equal(nrow(core_row), 1L)
  testthat::expect_equal(core_row$Elevation[1], 1500L)

  # Staging should be cleaned up
  staged <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.env WHERE \"mergeRequestID\" = ?",
    list(mr_id)
  )
  testthat::expect_equal(staged$n[1], 0L)

  # Merge request status
  mr <- merge_request_get(con, mr_id)
  testthat::expect_equal(mr$status[1], "merged")
  testthat::expect_equal(mr$reviewer[1], "admin@test.local")

  # merge_history should have exactly one row for this merge request
  hist <- DBI::dbGetQuery(
    con, "SELECT * FROM master.admin.merge_history WHERE merge_request_id = ?",
    list(mr_id)
  )
  testthat::expect_equal(nrow(hist), 1L)
  testthat::expect_equal(hist$record_count[1], 1L)   # 1 env row pushed
  testthat::expect_equal(hist$approved_by_user_id[1], 1L)  # admin user id = 1
})

testthat::test_that("merge_approve_request respects keep_core resolution", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Existing master row at row_version = 1
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (plot_number, project_id, latitude, elevation_m, row_version, last_modified_utc, modified_by)
     VALUES ('P-310', 1, 50.0, 800, 1, now(), 'original')"
  )

  # User pushes different elevation
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-310', '1', 50.0, -120.0, 1200, DATE '2026-01-01', 'Hank', '')"
  )
  results <- sync_push(con, project_id = 1, submitter = "hank@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  # Admin updates master concurrently (row_version -> 2)
  DBI::dbExecute(
    con,
    "UPDATE master.core.env SET \"Elevation\" = 600, \"rowVersion\" = 2 WHERE \"PlotNumber\" = 'P-310'"
  )

  merge_request_refresh_conflicts(con, mr_id)
  conflicts <- merge_request_get_conflicts(con, mr_id)
  testthat::expect_equal(nrow(conflicts), 1L)

  # Admin chooses to keep master (core) value
  merge_request_resolve_conflict(con, conflicts$id[1], "keep_core", actor = "admin@test.local")
  testthat::expect_equal(merge_request_unresolved_count(con, mr_id), 0L)

  merge_approve_request(con, mr_id, reviewer = "admin@test.local")

  # Core value should still be 600 (keep_core was chosen)
  core_elev <- DBI::dbGetQuery(
    con, "SELECT \"Elevation\" FROM master.core.env WHERE \"PlotNumber\" = 'P-310'"
  )$elevation_m[1]
  testthat::expect_equal(core_elev, 600L)

  # merge_history should still record the merge outcome even when keep_core is chosen
  hist <- DBI::dbGetQuery(
    con, "SELECT * FROM master.admin.merge_history WHERE merge_request_id = ?",
    list(mr_id)
  )
  testthat::expect_equal(nrow(hist), 1L)
})

testthat::test_that("merge_approve_request blocks with unresolved conflicts", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (plot_number, project_id, latitude, elevation_m, row_version, last_modified_utc, modified_by)
     VALUES ('P-320', 1, 50.0, 800, 1, now(), 'original')"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-320', '1', 50.0, -120.0, 999, DATE '2026-01-01', 'Ivy', '')"
  )
  results <- sync_push(con, project_id = 1, submitter = "ivy@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  # Advance master row_version to force conflict
  DBI::dbExecute(
    con,
    "UPDATE master.core.env SET \"Elevation\" = 300, \"rowVersion\" = 2 WHERE \"PlotNumber\" = 'P-320'"
  )
  merge_request_refresh_conflicts(con, mr_id)

  # Attempt approve without resolving
  testthat::expect_error(
    merge_approve_request(con, mr_id, reviewer = "admin@test.local"),
    "unresolved conflict"
  )
})

testthat::test_that("merge_reject_request removes staging rows and updates status", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-400', '1', 55.0, -122.0, 200, DATE '2026-01-01', 'Jack', '')"
  )
  results <- sync_push(con, project_id = 1, submitter = "jack@test.local", tables = "env",
                       allow_attach = FALSE)
  mr_id <- as.integer(results$merge_request_id)

  merge_reject_request(con, mr_id, reviewer = "admin@test.local", review_notes = "bad data")

  mr <- merge_request_get(con, mr_id)
  testthat::expect_equal(mr$status[1], "rejected")

  staged <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.staging.env WHERE \"mergeRequestID\" = ?",
    list(mr_id)
  )
  testthat::expect_equal(staged$n[1], 0L)

  # Core should NOT have received the data
  core_row <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) AS n FROM master.core.env WHERE \"PlotNumber\" = 'P-400'"
  )
  testthat::expect_equal(core_row$n[1], 0L)
})

testthat::test_that("merge_request_list returns pending requests with conflict count", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes)
     VALUES ('P-500', '1', 51.0, -118.0, 700, DATE '2026-01-01', 'Kim', '')"
  )
  sync_push(con, project_id = 1, submitter = "kim@test.local", tables = "env", allow_attach = FALSE)

  listing <- merge_request_list(con)
  testthat::expect_true(nrow(listing) >= 1L)
  testthat::expect_true("unresolved_conflicts" %in% names(listing))
})


# =============================================================================
# Tests — Lists pull
# =============================================================================

# Helper: create a temp DuckDB file for the local lists attachment.
.make_local_lists_db <- function() {
  lists_path <- tempfile(fileext = ".duckdb")
  lc <- DBI::dbConnect(duckdb::duckdb(), lists_path)
  tryCatch({
    DBI::dbExecute(lc, "
      CREATE TABLE USysTableOfLists (
        listname        TEXT,
        item            TEXT,
        itemorder       DOUBLE,
        itemdescription TEXT
      )
    ")
    DBI::dbExecute(lc, "
      CREATE TABLE USysZoneList (
        _zone                TEXT,
        subzone              TEXT,
        zonedescription      TEXT,
        subzonevardescription TEXT
      )
    ")
    # Seed one stale row so we can confirm it gets replaced
    DBI::dbExecute(lc, "INSERT INTO USysTableOfLists VALUES ('SLOPE', 'FLAT', 1, 'Old description')")
    DBI::dbExecute(lc, "INSERT INTO USysZoneList VALUES ('CWH', 'dm', 'Old zone name', 'dry maritime')")
  }, error = function(e) NULL)
  DBI::dbDisconnect(lc, shutdown = TRUE)
  lists_path
}

testthat::test_that("sync_pull lists: replaces local lists tables with master content", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # Build and attach a local lists database
  lists_path <- .make_local_lists_db()
  s$lists_path <- lists_path  # register for teardown
  DBI::dbExecute(con, paste0("ATTACH '", lists_path, "' AS lists"))

  # Seed master.lists with updated/expanded data
  DBI::dbExecute(con, "INSERT INTO master.lists.USysTableOfLists VALUES
    ('SLOPE', 'FLAT',   1, 'Flat (updated)'),
    ('SLOPE', 'GENTLE', 2, 'Gentle slope')")
  DBI::dbExecute(con, "INSERT INTO master.lists.USysZoneList VALUES
    ('CWH', 'dm', 'Coastal Western Hemlock', 'dry maritime'),
    ('IDF', 'dk', 'Interior Douglas-fir',    'dry cool')")

  result <- sync_pull(con, tables = "lists", allow_attach = FALSE)

  # Both tables synced
  testthat::expect_equal(result$lists$synced_tables, 2L)
  testthat::expect_equal(length(result$lists$skipped), 0L)

  # USysTableOfLists: stale row replaced, new row added
  tol_rows <- DBI::dbGetQuery(con, "SELECT * FROM lists.USysTableOfLists ORDER BY itemorder")
  testthat::expect_equal(nrow(tol_rows), 2L)
  testthat::expect_equal(tol_rows$itemdescription[1], "Flat (updated)")
  testthat::expect_equal(tol_rows$item[2], "GENTLE")

  # USysZoneList: stale row replaced, new row added
  zone_rows <- DBI::dbGetQuery(con, "SELECT * FROM lists.USysZoneList ORDER BY \"_zone\"")
  testthat::expect_equal(nrow(zone_rows), 2L)
  testthat::expect_equal(zone_rows$zonedescription[zone_rows$`_zone` == 'CWH'], "Coastal Western Hemlock")

  # Watermark for lists was updated
  wm <- sync_get_watermark(con, "lists", "pull")
  testthat::expect_false(is.null(wm))
})

testthat::test_that("sync_pull lists: skips local tables absent from master", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  lists_path <- tempfile(fileext = ".duckdb")
  s$lists_path <- lists_path
  lc <- DBI::dbConnect(duckdb::duckdb(), lists_path)
  DBI::dbExecute(lc, "CREATE TABLE USysTableOfLists (listname TEXT, item TEXT, itemorder DOUBLE, itemdescription TEXT)")
  DBI::dbExecute(lc, "CREATE TABLE USysLocalOnly (val TEXT)")
  DBI::dbDisconnect(lc, shutdown = TRUE)

  DBI::dbExecute(con, paste0("ATTACH '", lists_path, "' AS lists"))

  # Only USysTableOfLists exists in master; USysLocalOnly does not
  DBI::dbExecute(con, "INSERT INTO master.lists.USysTableOfLists VALUES ('X', 'A', 1, 'desc')")

  result <- sync_pull(con, tables = "lists", allow_attach = FALSE)

  testthat::expect_equal(result$lists$synced_tables, 1L)
  testthat::expect_true("USysLocalOnly" %in% result$lists$skipped)
})

testthat::test_that("sync_pull lists: returns zero synced when no lists catalog is attached", {
  s <- .sync_test_setup(); on.exit(.sync_test_teardown(s), add = TRUE)
  con <- s$con

  # No local lists attachment — should not error, just return 0
  result <- sync_pull(con, tables = "lists", allow_attach = FALSE)

  testthat::expect_equal(result$lists$synced_tables, 0L)
})
