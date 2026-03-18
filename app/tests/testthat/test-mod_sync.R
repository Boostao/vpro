testthat::context("mod_sync — logic helpers")

library(DBI)
library(duckdb)
source(here::here("tests", "testthat", "setup.R"))
source(here::here("tests", "testthat", "helpers.R"))
source(here::here("R", "logic_sync.R"))

# =============================================================================
# Shared test infrastructure
# =============================================================================
# We reuse .make_test_con / .setup_master_db / .sync_test_setup from
# test-logic_sync.R (loaded by the same setup.R / helpers.R chain), but we
# re-declare a minimal version here so the file is self-contained.

.mk_local_con <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  DBI::dbExecute(con, "
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
      SiteSeries   TEXT,
      master_row_version  INTEGER,
      local_modified_utc  TIMESTAMPTZ
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE SU (
      PlotNumber TEXT,
      SiteUnit   TEXT,
      master_row_version  INTEGER,
      local_modified_utc  TIMESTAMPTZ
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE Veg (
      PlotNumber TEXT,
      Species    TEXT,
      Layer      TEXT,
      Cover1     TEXT,
      master_row_version  INTEGER,
      local_modified_utc  TIMESTAMPTZ
    )
  ")
  sync_ensure_local_tables(con)
  con
}

.mk_master_con <- function(local_con) {
  master_path <- tempfile(fileext = ".duckdb")
  mc <- DBI::dbConnect(duckdb::duckdb(), master_path)
  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS core")
  DBI::dbExecute(mc, "CREATE SCHEMA IF NOT EXISTS admin")
  DBI::dbExecute(mc, "CREATE SEQUENCE IF NOT EXISTS admin.mr_seq START 1")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.env (
      plot_number  TEXT NOT NULL,
      project_id   INTEGER NOT NULL,
      row_version  INTEGER NOT NULL DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now()
    )
  ")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.su (
      plot_number  TEXT NOT NULL,
      project_id   INTEGER NOT NULL,
      row_version  INTEGER NOT NULL DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now()
    )
  ")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS core.veg (
      plot_number  TEXT NOT NULL,
      project_id   INTEGER NOT NULL,
      species_code TEXT NOT NULL,
      layer_code   TEXT NOT NULL,
      row_version  INTEGER NOT NULL DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now()
    )
  ")
  DBI::dbExecute(mc, "
    CREATE TABLE IF NOT EXISTS admin.merge_requests (
      id               INTEGER PRIMARY KEY DEFAULT nextval('admin.mr_seq'),
      project_id       INTEGER NOT NULL,
      submitter_name   TEXT NOT NULL,
      submitted_utc    TIMESTAMPTZ DEFAULT now(),
      status           TEXT NOT NULL DEFAULT 'pending_review',
      review_notes     TEXT,
      reviewed_utc     TIMESTAMPTZ,
      env_record_count INTEGER DEFAULT 0,
      su_record_count  INTEGER DEFAULT 0,
      veg_record_count INTEGER DEFAULT 0
    )
  ")
  DBI::dbDisconnect(mc)
  DBI::dbExecute(local_con, paste0("ATTACH '", master_path, "' AS master"))
  master_path
}


# =============================================================================
# sync_get_local_changes() tests
# =============================================================================

testthat::test_that("sync_get_local_changes: empty tables → zero-row data.frames", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  result <- sync_get_local_changes(con)
  testthat::expect_true(is.list(result))
  testthat::expect_named(result, c("env", "su", "veg"))
  testthat::expect_equal(nrow(result$env), 0L)
  testthat::expect_equal(nrow(result$su),  0L)
  testthat::expect_equal(nrow(result$veg), 0L)
})

testthat::test_that("sync_get_local_changes: insert rows appear with change_type = 'insert'", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Insert = local_modified_utc IS NOT NULL, master_row_version IS NULL
  DBI::dbExecute(con,
    "INSERT INTO Env (PlotNumber, ProjectID, local_modified_utc)
     VALUES ('P1', '10', now()), ('P2', '10', now())")

  result <- sync_get_local_changes(con, project_id = "10")
  testthat::expect_equal(nrow(result$env), 2L)
  testthat::expect_true(all(result$env$change_type == "insert"))
})

testthat::test_that("sync_get_local_changes: update rows appear with change_type = 'update'", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Update = local_modified_utc IS NOT NULL, master_row_version IS NOT NULL
  DBI::dbExecute(con,
    "INSERT INTO Env (PlotNumber, ProjectID, master_row_version, local_modified_utc)
     VALUES ('P3', '10', 5, now())")

  result <- sync_get_local_changes(con, project_id = "10")
  testthat::expect_equal(nrow(result$env), 1L)
  testthat::expect_equal(result$env$change_type[1], "update")
})

testthat::test_that("sync_get_local_changes: rows with no dirty flag are excluded", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Clean row (local_modified_utc IS NULL)
  DBI::dbExecute(con,
    "INSERT INTO Env (PlotNumber, ProjectID, master_row_version, local_modified_utc)
     VALUES ('P4', '10', 3, NULL)")

  result <- sync_get_local_changes(con, project_id = "10")
  testthat::expect_equal(nrow(result$env), 0L)
})

testthat::test_that("sync_get_local_changes: project_id filter works", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO Env (PlotNumber, ProjectID, local_modified_utc) VALUES
       ('P1', '10', now()),
       ('P2', '20', now())")

  # Filter to project 10 only
  result <- sync_get_local_changes(con, project_id = "10")
  testthat::expect_equal(nrow(result$env), 1L)
  testthat::expect_equal(result$env$PlotNumber[1], "P1")
})

testthat::test_that("sync_get_local_changes: SU and Veg dirty rows appear", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO SU (PlotNumber, local_modified_utc) VALUES ('P1', now())")
  DBI::dbExecute(con, "INSERT INTO Veg (PlotNumber, Species, Layer, local_modified_utc) VALUES ('P1', 'ABIES', 'A', now())")

  result <- sync_get_local_changes(con)
  testthat::expect_equal(nrow(result$su),  1L)
  testthat::expect_equal(nrow(result$veg), 1L)
})


# =============================================================================
# sync_count_incoming() tests
# =============================================================================

testthat::test_that("sync_count_incoming: no cloud → available = FALSE, all counts 0", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  result <- sync_count_incoming(con)
  testthat::expect_false(result$available)
  testthat::expect_equal(result$env, 0L)
  testthat::expect_equal(result$su,  0L)
  testthat::expect_equal(result$veg, 0L)
})

testthat::test_that("sync_count_incoming: with mock master → counts rows since watermark", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  # Insert 2 env rows in master
  DBI::dbExecute(con,
    "INSERT INTO master.core.env (plot_number, project_id, last_modified_utc)
     VALUES ('M1', 10, now()), ('M2', 10, now())")

  result <- sync_count_incoming(con)
  testthat::expect_true(result$available)
  testthat::expect_equal(result$env, 2L)
  testthat::expect_equal(result$su,  0L)
  testthat::expect_equal(result$veg, 0L)
})

testthat::test_that("sync_count_incoming: watermark skips already-pulled rows", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  # Simulate a pull happened just now — set watermark to now + 5s
  sync_set_watermark(con, "env", "pull", ts = Sys.time() + 5)

  # Insert an env row with last_modified_utc 10s in the past (before watermark)
  old_ts <- format(Sys.time() - 10, "%Y-%m-%d %H:%M:%OS3")
  DBI::dbExecute(con,
    sprintf(
      "INSERT INTO master.core.env (plot_number, project_id, last_modified_utc)
       VALUES ('OLD', 10, TIMESTAMPTZ '%s')", old_ts
    )
  )

  result <- sync_count_incoming(con)
  testthat::expect_equal(result$env, 0L)
})


# =============================================================================
# sync_get_user_merge_requests() tests
# =============================================================================

testthat::test_that("sync_get_user_merge_requests: no cloud → empty data.frame", {
  con <- .mk_local_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  result <- sync_get_user_merge_requests(con, "alice@test.local")
  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_true("status" %in% names(result))
})

testthat::test_that("sync_get_user_merge_requests: filters by submitter_name", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests (project_id, submitter_name, status)
     VALUES
       (10, 'alice@test.local', 'pending_review'),
       (10, 'alice@test.local', 'merged'),
       (10, 'bob@test.local',   'pending_review')")

  result <- sync_get_user_merge_requests(con, "alice@test.local")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_true(all(result$status %in% c("pending_review", "merged")))
})

testthat::test_that("sync_get_user_merge_requests: show_approved = FALSE hides merged rows", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests (project_id, submitter_name, status)
     VALUES
       (10, 'alice@test.local', 'pending_review'),
       (10, 'alice@test.local', 'merged')")

  result <- sync_get_user_merge_requests(con, "alice@test.local", show_approved = FALSE)
  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$status[1], "pending_review")
})

testthat::test_that("sync_get_user_merge_requests: show_rejected = FALSE hides rejected rows", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests (project_id, submitter_name, status)
     VALUES
       (10, 'alice@test.local', 'pending_review'),
       (10, 'alice@test.local', 'rejected')")

  result <- sync_get_user_merge_requests(con, "alice@test.local", show_rejected = FALSE)
  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$status[1], "pending_review")
})

testthat::test_that("sync_get_user_merge_requests: both filters false → only pending returned", {
  con  <- .mk_local_con()
  path <- .mk_master_con(con)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    try(unlink(path), silent = TRUE)
  }, add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests (project_id, submitter_name, status)
     VALUES
       (10, 'alice@test.local', 'pending_review'),
       (10, 'alice@test.local', 'merged'),
       (10, 'alice@test.local', 'rejected')")

  result <- sync_get_user_merge_requests(
    con, "alice@test.local",
    show_approved = FALSE,
    show_rejected = FALSE
  )
  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$status[1], "pending_review")
})
