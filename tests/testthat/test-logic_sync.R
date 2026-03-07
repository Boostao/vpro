# =============================================================================
# tests/testthat/test-logic_sync.R
# Infrastructure helpers and connectivity smoke tests for the push-only engine.
# =============================================================================

library(DBI)
library(duckdb)
library(testthat)

# Source the module under test
source(here::here("R", "logic_sync.R"))

# =============================================================================
# Shared setup helpers
# =============================================================================

#' Build a minimal master DuckDB that mimics the PostgreSQL layout.
#' Returns a named list: con (master-path DuckDB conn), path.
#' Caller must disconnect and unlink the file.
.make_master <- function() {
  path <- tempfile(fileext = ".duckdb")
  mc   <- DBI::dbConnect(duckdb::duckdb(), path)

  DBI::dbExecute(mc, "CREATE SCHEMA admin")
  DBI::dbExecute(mc, "CREATE SCHEMA core")
  DBI::dbExecute(mc, "CREATE SCHEMA staging")

  # admin.users
  DBI::dbExecute(mc, "
    CREATE TABLE admin.users (
      id    INTEGER PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      full_name TEXT
    )
  ")
  DBI::dbExecute(mc, "
    INSERT INTO admin.users VALUES (1, 'test@example.com', 'Test User')
  ")

  # admin.merge_requests  (record_counts as VARCHAR for DuckDB compat)
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mr_id_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE admin.merge_requests (
      id                INTEGER PRIMARY KEY DEFAULT nextval('admin.mr_id_seq'),
      project_id        TEXT NOT NULL,
      submitter_user_id INTEGER,
      submitter_name    TEXT NOT NULL,
      submitted_utc     TIMESTAMPTZ DEFAULT now(),
      status            TEXT NOT NULL DEFAULT 'pending_review',
      reviewer          TEXT,
      reviewer_user_id  INTEGER,
      review_notes      TEXT,
      reviewed_utc      TIMESTAMPTZ,
      record_counts     VARCHAR DEFAULT '{}',
      compliance_passed BOOLEAN,
      compliance_report TEXT
    )
  ")

  # admin.merge_conflicts  (record_id TEXT, UNIQUE on 3 cols)
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mc_id_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE admin.merge_conflicts (
      id               INTEGER PRIMARY KEY DEFAULT nextval('admin.mc_id_seq'),
      merge_request_id INTEGER NOT NULL,
      table_name       TEXT NOT NULL,
      record_id        TEXT NOT NULL DEFAULT '',
      details          VARCHAR,
      resolution       TEXT CHECK (resolution IN ('keep_staged', 'keep_core', 'dismiss')),
      resolved_by      TEXT,
      resolved_utc     TIMESTAMPTZ,
      created_utc      TIMESTAMPTZ DEFAULT now(),
      UNIQUE (merge_request_id, table_name, record_id)
    )
  ")

  # admin.merge_history
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mh_id_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE admin.merge_history (
      id                     INTEGER PRIMARY KEY DEFAULT nextval('admin.mh_id_seq'),
      merge_request_id       INTEGER NOT NULL,
      merged_utc             TIMESTAMPTZ DEFAULT now(),
      approved_by_user_id    INTEGER,
      record_count           INTEGER,
      merge_summary          VARCHAR
    )
  ")

  # core.env (lowercase columns)
  DBI::dbExecute(mc, "
    CREATE TABLE core.env (
      plotnumber  TEXT PRIMARY KEY,
      fieldnumber TEXT,
      projectid   TEXT,
      latitude    DOUBLE,
      longitude   DOUBLE,
      elevation   INTEGER,
      date        TEXT,
      sitesurveyor TEXT,
      sitenotes   TEXT,
      \"rowVersion\"       INTEGER DEFAULT 1,
      \"lastModifiedUTC\"  TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"       TEXT
    )
  ")

  # staging.env (composite PK: merge_request_id + plotnumber)
  DBI::dbExecute(mc, "
    CREATE TABLE staging.env (
      merge_request_id  INTEGER NOT NULL,
      plotnumber        TEXT NOT NULL,
      fieldnumber       TEXT,
      projectid         TEXT,
      latitude          DOUBLE,
      longitude         DOUBLE,
      elevation         INTEGER,
      date              TEXT,
      sitesurveyor      TEXT,
      sitenotes         TEXT,
      \"baseRowVersion\"   INTEGER,
      \"changeType\"       TEXT,
      \"rowVersion\"       INTEGER DEFAULT 1,
      \"lastModifiedUTC\"  TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"       TEXT,
      PRIMARY KEY (merge_request_id, plotnumber)
    )
  ")

  # core.veg (id PK)
  DBI::dbExecute(mc, "
    CREATE TABLE core.veg (
      id           BIGINT PRIMARY KEY,
      plotnumber   TEXT,
      species      TEXT,
      layer        TEXT,
      cover1       DOUBLE,
      \"rowVersion\"      INTEGER DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"      TEXT
    )
  ")

  # staging.veg (composite PK: merge_request_id + id)
  DBI::dbExecute(mc, "
    CREATE TABLE staging.veg (
      merge_request_id INTEGER NOT NULL,
      id               BIGINT NOT NULL,
      plotnumber       TEXT,
      species          TEXT,
      layer            TEXT,
      cover1           DOUBLE,
      \"baseRowVersion\"  INTEGER,
      \"changeType\"      TEXT,
      \"rowVersion\"      INTEGER DEFAULT 1,
      \"lastModifiedUTC\" TIMESTAMPTZ DEFAULT now(),
      \"modifiedBy\"      TEXT,
      PRIMARY KEY (merge_request_id, id)
    )
  ")

  list(con = mc, path = path)
}

#' Create a local in-memory DuckDB with minimal Env and Veg tables.
.make_local <- function() {
  lc <- DBI::dbConnect(duckdb::duckdb(), ":memory:")

  DBI::dbExecute(lc, "
    CREATE TABLE Env (
      plotnumber   TEXT PRIMARY KEY,
      fieldnumber  TEXT,
      projectid    TEXT,
      latitude     DOUBLE,
      longitude    DOUBLE,
      elevation    INTEGER,
      date         TEXT,
      sitesurveyor TEXT,
      sitenotes    TEXT,
      local_modified_utc TIMESTAMPTZ
    )
  ")

  DBI::dbExecute(lc, "
    CREATE TABLE Veg (
      id         BIGINT PRIMARY KEY,
      plotnumber TEXT,
      species    TEXT,
      layer      TEXT,
      cover1     DOUBLE,
      local_modified_utc TIMESTAMPTZ
    )
  ")

  lc
}

#' Attach the master temp DuckDB to a local connection as catalog 'master'.
.attach_master <- function(local_con, master_path) {
  DBI::dbExecute(
    local_con,
    sprintf("ATTACH '%s' AS master (READ_WRITE)", master_path)
  )
  invisible(local_con)
}


# =============================================================================
# Connectivity smoke tests
# =============================================================================

test_that("sync_cloud_connected returns FALSE when master not attached", {
  lc <- .make_local()
  on.exit(DBI::dbDisconnect(lc), add = TRUE)
  expect_false(sync_cloud_connected(lc))
})

test_that("sync_cloud_connected returns TRUE when master is attached", {
  m  <- .make_master()
  on.exit({
    DBI::dbDisconnect(m$con)
    try(unlink(m$path), silent = TRUE)
  }, add = TRUE)

  lc <- .make_local()
  on.exit(DBI::dbDisconnect(lc), add = TRUE)
  .attach_master(lc, m$path)
  expect_true(sync_cloud_connected(lc))
})

test_that("sync_require_cloud stops when master not attached", {
  lc <- .make_local()
  on.exit(DBI::dbDisconnect(lc), add = TRUE)
  expect_error(sync_require_cloud(lc), "not attached")
})

test_that("sync_ensure_local_tables adds local_modified_utc to Env and Veg", {
  lc <- .make_local()
  on.exit(DBI::dbDisconnect(lc), add = TRUE)

  # Remove the column first so we can test it gets added
  DBI::dbExecute(lc, "ALTER TABLE Env DROP COLUMN IF EXISTS local_modified_utc")
  DBI::dbExecute(lc, "ALTER TABLE Veg DROP COLUMN IF EXISTS local_modified_utc")

  sync_ensure_local_tables(lc)

  env_cols <- tolower(DBI::dbListFields(lc, "Env"))
  veg_cols <- tolower(DBI::dbListFields(lc, "Veg"))
  expect_true("local_modified_utc" %in% env_cols)
  expect_true("local_modified_utc" %in% veg_cols)
})

test_that(".get_shared_columns returns intersection excluding metadata", {
  m  <- .make_master()
  on.exit({
    DBI::dbDisconnect(m$con)
    try(unlink(m$path), silent = TRUE)
  }, add = TRUE)

  lc <- .make_local()
  on.exit(DBI::dbDisconnect(lc), add = TRUE)
  .attach_master(lc, m$path)

  cols <- .get_shared_columns(lc, "Env", "env")
  expect_true("plotnumber" %in% cols)
  expect_true("projectid"  %in% cols)
  expect_false("local_modified_utc" %in% cols)
  expect_false("merge_request_id"   %in% cols)
  expect_false("baserowversion"     %in% cols)
})
