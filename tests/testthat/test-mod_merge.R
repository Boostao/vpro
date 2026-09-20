testthat::context("mod_merge")

source(here::here("R", "logic_sync.R"))
source(here::here("R", "mod_merge.R"))

setup_merge_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_merge_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))

  DBI::dbExecute(con, "CREATE SCHEMA master.admin")
  DBI::dbExecute(con, "CREATE SCHEMA master.staging")
  DBI::dbExecute(con, "CREATE SCHEMA master.core")

  # Local table matching cfg$local = "Env" so .get_shared_columns() finds columns
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT,
      project_id TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation_m DOUBLE,
      survey_date DATE,
      surveyor_name TEXT,
      plot_notes TEXT,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.admin.merge_requests (
      id INTEGER PRIMARY KEY,
      project_id TEXT NOT NULL,
      submitter_user_id TEXT NOT NULL,
      submitted_utc TIMESTAMPTZ DEFAULT now(),
      status TEXT DEFAULT 'pending_review',
      reviewer TEXT,
      reviewer_user_id TEXT,
      review_notes TEXT,
      reviewed_utc TIMESTAMPTZ,
      veg_record_count INTEGER DEFAULT 0,
      env_record_count INTEGER DEFAULT 0,
      record_counts TEXT,
      compliance_passed BOOLEAN DEFAULT FALSE
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.env (
      plotnumber TEXT,
      project_id TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation_m DOUBLE,
      survey_date DATE,
      surveyor_name TEXT,
      plot_notes TEXT,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.su (
      plotnumber TEXT,
      project_id TEXT,
      su_number TEXT,
      bec_zone TEXT,
      bec_subzone TEXT,
      site_series TEXT,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.veg (
      plotnumber TEXT,
      project_id TEXT,
      species_code TEXT,
      layer_code TEXT,
      cover1 REAL,
      height1 REAL,
      cover2 REAL,
      height2 REAL,
      cover3 REAL,
      height3 REAL,
      totala REAL,
      heighta REAL,
      cover4 REAL,
      height4 REAL,
      cover5 REAL,
      height5 REAL,
      cover5a REAL,
      height5a REAL,
      cover5b REAL,
      height5b REAL,
      cover5c REAL,
      height5c REAL,
      totalb REAL,
      heightb TEXT,
      cover6 REAL,
      height6 REAL,
      cover7 REAL,
      cover8 REAL,
      cover9 REAL,
      cover10 REAL,
      collected TEXT,
      flag BOOLEAN,
      veg_id INTEGER,
      ll INTEGER,
      af INTEGER,
      dc INTEGER,
      ut INTEGER,
      vi INTEGER,
      pv INTEGER,
      pg INTEGER,
      ffa INTEGER,
      cultural1 INTEGER,
      cultural2 INTEGER,
      other1 INTEGER,
      other2 INTEGER,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.env (
      plotnumber TEXT,
      project_id TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation_m DOUBLE,
      survey_date DATE,
      surveyor_name TEXT,
      plot_notes TEXT,
      modified_by TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      UNIQUE(plotnumber)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.su (
      plotnumber TEXT,
      project_id TEXT,
      su_number TEXT,
      bec_zone TEXT,
      bec_subzone TEXT,
      site_series TEXT,
      modified_by TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      UNIQUE(plotnumber)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.veg (
      plotnumber TEXT,
      species_code TEXT,
      layer_code TEXT,
      cover1 REAL,
      height1 REAL,
      cover2 REAL,
      height2 REAL,
      cover3 REAL,
      height3 REAL,
      totala REAL,
      heighta REAL,
      cover4 REAL,
      height4 REAL,
      cover5 REAL,
      height5 REAL,
      cover5a REAL,
      height5a REAL,
      cover5b REAL,
      height5b REAL,
      cover5c REAL,
      height5c REAL,
      totalb REAL,
      heightb TEXT,
      cover6 REAL,
      height6 REAL,
      cover7 REAL,
      cover8 REAL,
      cover9 REAL,
      cover10 REAL,
      collected TEXT,
      flag BOOLEAN,
      veg_id INTEGER,
      ll INTEGER,
      af INTEGER,
      dc INTEGER,
      ut INTEGER,
      vi INTEGER,
      pv INTEGER,
      pg INTEGER,
      ffa INTEGER,
      cultural1 INTEGER,
      cultural2 INTEGER,
      other1 INTEGER,
      other2 INTEGER,
      project_id TEXT,
      modified_by TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      UNIQUE(plotnumber, species_code, layer_code, project_id)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.admin.merge_conflicts (
      id                INTEGER PRIMARY KEY,
      merge_request_id  INTEGER NOT NULL,
      table_name        TEXT NOT NULL,
      record_id         TEXT NOT NULL,
      details           TEXT,
      resolution        TEXT,
      resolved_by       TEXT,
      resolved_utc      TIMESTAMPTZ,
      created_utc       TIMESTAMPTZ DEFAULT now()
    )
  ")

  con
}

testthat::test_that("merge is blocked when compliance fails", {
  con <- setup_merge_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    INSERT INTO master.admin.merge_requests (id, project_id, submitter_user_id, compliance_passed)
    VALUES (1, 'PRJ', 'user1', FALSE)
  ")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.env
      (plotnumber, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, merge_request_id, modified_by)
    VALUES ('P-1', 'PRJ', 52.1, -118.5, 500, DATE '2026-02-01', 'Tester', 'notes', 1, 'user1')
  ")

  testthat::expect_error(
    merge_approve_request(con, 1, "reviewer"),
    "compliance failed"
  )

  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.core.env")$n[1]
  status <- DBI::dbGetQuery(con, "SELECT status FROM master.admin.merge_requests WHERE id = 1")$status[1]

  testthat::expect_equal(count, 0)
  testthat::expect_equal(status, "pending_review")
})

testthat::test_that("merge succeeds when compliance passes", {
  con <- setup_merge_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    INSERT INTO master.admin.merge_requests (id, project_id, submitter_user_id, compliance_passed)
    VALUES (2, 'PRJ', 'user1', TRUE)
  ")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.env
      (plotnumber, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, merge_request_id, modified_by)
    VALUES ('P-2', 'PRJ', 52.1, -118.5, 500, DATE '2026-02-01', 'Tester', 'notes', 2, 'user1')
  ")

  merge_approve_request(con, 2, "reviewer")

  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.core.env")$n[1]
  status <- DBI::dbGetQuery(con, "SELECT status FROM master.admin.merge_requests WHERE id = 2")$status[1]

  testthat::expect_equal(count, 1)
  testthat::expect_equal(status, "merged")
})
