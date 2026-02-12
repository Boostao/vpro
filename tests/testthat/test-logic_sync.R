testthat::context("logic_sync")

source(here::here("R", "db_connections.R"))
source(here::here("R", "logic_sync.R"))

# Deterministic compliance for unit tests (avoid pulling full lists/validation dependencies)
assign(
  "run_compliance_checks",
  function(con, project_id = NULL, ...) {
    list(passed = TRUE, summary_tibble = data.frame(), detail_tibble = data.frame())
  },
  envir = environment(staging_compliance_checks)
)

assign(
  "sync_cloud_connected",
  function(con) {
    "master" %in% DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
  },
  envir = environment(sync_require_cloud)
)

setup_sync_test_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))


  DBI::dbExecute(con, "CREATE SCHEMA master.core")
  DBI::dbExecute(con, "CREATE SCHEMA master.staging")
  DBI::dbExecute(con, "CREATE SCHEMA master.admin")

  DBI::dbExecute(con, "CREATE SEQUENCE master.admin.merge_requests_id_seq")
  DBI::dbExecute(con, "
    CREATE TABLE master.admin.merge_requests (
      id BIGINT PRIMARY KEY DEFAULT nextval('master.admin.merge_requests_id_seq'),
      project_id TEXT NOT NULL,
      submitter_user_id TEXT NOT NULL,
      env_record_count INTEGER DEFAULT 0,
      su_record_count INTEGER DEFAULT 0,
      veg_record_count INTEGER DEFAULT 0
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.sample_env (
      plot_number TEXT,
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
      PRIMARY KEY (plot_number, project_id)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.sample_su (
      plot_number TEXT,
      project_id TEXT,
      su_number TEXT,
      bec_zone TEXT,
      bec_subzone TEXT,
      site_series TEXT,
      modified_by TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      PRIMARY KEY (plot_number, project_id)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.core.sample_veg (
      plot_number TEXT,
      project_id TEXT,
      species_code TEXT,
      layer_code TEXT,
      cover1 TEXT,
      height1 TEXT,
      cover2 TEXT,
      height2 TEXT,
      cover3 TEXT,
      height3 TEXT,
      totala TEXT,
      heighta TEXT,
      cover4 TEXT,
      height4 TEXT,
      cover5 TEXT,
      height5 TEXT,
      cover5a TEXT,
      height5a TEXT,
      cover5b TEXT,
      height5b TEXT,
      cover5c TEXT,
      height5c TEXT,
      totalb TEXT,
      heightb TEXT,
      cover6 TEXT,
      height6 TEXT,
      cover7 TEXT,
      cover8 TEXT,
      cover9 TEXT,
      cover10 TEXT,
      collected TEXT,
      flag TEXT,
      veg_id INTEGER,
      ll TEXT,
      af TEXT,
      dc TEXT,
      ut TEXT,
      vi TEXT,
      pv TEXT,
      pg TEXT,
      ffa TEXT,
      cultural1 TEXT,
      cultural2 TEXT,
      other1 TEXT,
      other2 TEXT,
      modified_by TEXT,
      row_version INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      PRIMARY KEY (plot_number, project_id, species_code, layer_code)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.sample_env (
      plot_number TEXT,
      project_id TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation_m DOUBLE,
      survey_date DATE,
      surveyor_name TEXT,
      plot_notes TEXT,
      base_row_version INTEGER,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.sample_su (
      plot_number TEXT,
      project_id TEXT,
      su_number TEXT,
      bec_zone TEXT,
      bec_subzone TEXT,
      site_series TEXT,
      base_row_version INTEGER,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.sample_veg (
      plot_number TEXT,
      project_id TEXT,
      species_code TEXT,
      layer_code TEXT,
      cover1 TEXT,
      height1 TEXT,
      cover2 TEXT,
      height2 TEXT,
      cover3 TEXT,
      height3 TEXT,
      totala TEXT,
      heighta TEXT,
      cover4 TEXT,
      height4 TEXT,
      cover5 TEXT,
      height5 TEXT,
      cover5a TEXT,
      height5a TEXT,
      cover5b TEXT,
      height5b TEXT,
      cover5c TEXT,
      height5c TEXT,
      totalb TEXT,
      heightb TEXT,
      cover6 TEXT,
      height6 TEXT,
      cover7 TEXT,
      cover8 TEXT,
      cover9 TEXT,
      cover10 TEXT,
      collected TEXT,
      flag TEXT,
      veg_id INTEGER,
      ll TEXT,
      af TEXT,
      dc TEXT,
      ut TEXT,
      vi TEXT,
      pv TEXT,
      pg TEXT,
      ffa TEXT,
      cultural1 TEXT,
      cultural2 TEXT,
      other1 TEXT,
      other2 TEXT,
      base_row_version INTEGER,
      merge_request_id INTEGER,
      modified_by TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE Sample_Env (
      PlotNumber TEXT,
      ProjectID TEXT,
      Latitude DOUBLE,
      Longitude DOUBLE,
      Elevation DOUBLE,
      Date DATE,
      SiteSurveyor TEXT,
      SiteNotes TEXT,
      Zone TEXT,
      SubZone TEXT,
      SiteSeries TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE Sample_SU (
      PlotNumber TEXT,
      SiteUnit TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE Sample_Veg (
      PlotNumber TEXT,
      Species TEXT,
      Layer TEXT,
      Cover1 TEXT,
      Height1 TEXT,
      Cover2 TEXT,
      Height2 TEXT,
      Cover3 TEXT,
      Height3 TEXT,
      TotalA TEXT,
      HeightA TEXT,
      Cover4 TEXT,
      Height4 TEXT,
      Cover5 TEXT,
      Height5 TEXT,
      Cover5a TEXT,
      Height5a TEXT,
      Cover5b TEXT,
      Height5b TEXT,
      Cover5c TEXT,
      Height5c TEXT,
      TotalB TEXT,
      HeightB TEXT,
      Cover6 TEXT,
      Height6 TEXT,
      Cover7 TEXT,
      Cover8 TEXT,
      Cover9 TEXT,
      Cover10 TEXT,
      Collected TEXT,
      Flag TEXT,
      ID INTEGER,
      LL TEXT,
      AF TEXT,
      DC TEXT,
      UT TEXT,
      VI TEXT,
      PV TEXT,
      PG TEXT,
      FFA TEXT,
      Cultural1 TEXT,
      Cultural2 TEXT,
      Other1 TEXT,
      Other2 TEXT
    )
  ")

  list(con = con, master_path = master_path)
}

testthat::test_that("sync state tables store values", {
  setup <- setup_sync_test_db()
  con <- setup$con
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  sync_ensure_state_tables(con)
  sync_set_state(con, "last_pull:sample_env:all", "2026-02-01 10:00:00")
  value <- sync_get_state(con, "last_pull:sample_env:all")

  testthat::expect_equal(value, "2026-02-01 10:00:00")
})

testthat::test_that("sync_pull copies sample_env rows", {
  setup <- setup_sync_test_db()
  con <- setup$con
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    INSERT INTO master.core.sample_env
      (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes)
    VALUES
      ('P-001', 'PRJ', 53.1, -120.2, 950, DATE '2026-02-01', 'Tester', 'notes')
  ")

  results <- sync_pull(con, project_id = "PRJ", tables = c("sample_env"), allow_attach = FALSE)

  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Sample_Env")$n[1]
  testthat::expect_equal(count, 1)
  testthat::expect_equal(results$sample_env$pulled, 1)
})

testthat::test_that("sync_push stages env, su, and veg rows", {
  setup <- setup_sync_test_db()
  con <- setup$con
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    INSERT INTO Sample_Env
      (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes, Zone, SubZone, SiteSeries)
    VALUES
      ('P-101', 'PRJ', 52.7, -118.9, 1234, DATE '2026-02-01', 'Tester', 'notes', 'ICH', 'dw', '01')
  ")

  DBI::dbExecute(con, "
    INSERT INTO Sample_SU (PlotNumber, SiteUnit)
    VALUES ('P-101', 'SU1')
  ")

  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg
      (PlotNumber, Species, Layer, Cover1, Height1, ID)
    VALUES
      ('P-101', 'AB', 'T', '10', '5', 1)
  ")

  results <- sync_push(
    con,
    project_id = "PRJ",
    tables = c("sample_env", "sample_su", "sample_veg"),
    allow_attach = FALSE,
    submitter = "tester"
  )

  env_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_env")$n[1]
  su_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_su")$n[1]
  veg_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_veg")$n[1]

  testthat::expect_equal(env_rows, 1)
  testthat::expect_equal(su_rows, 1)
  testthat::expect_equal(veg_rows, 1)
  testthat::expect_true(is.numeric(results$merge_request_id))

  mr_counts <- DBI::dbGetQuery(
    con,
    "SELECT env_record_count, veg_record_count FROM master.admin.merge_requests WHERE id = ?",
    list(results$merge_request_id)
  )
  testthat::expect_equal(mr_counts$env_record_count[1], 1)
  testthat::expect_equal(mr_counts$veg_record_count[1], 1)
})

testthat::test_that("merge request conflicts are detected and resolvable", {
  setup <- setup_sync_test_db()
  con <- setup$con
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Seed an existing core row (row_version 1 at time of submit)
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.sample_env
      (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, modified_by, row_version)
     VALUES ('P-201', 'PRJ', 50.0, -120.0, 900, DATE '2026-02-01', 'CoreUser', 'core', 'core', 1)"
  )

  # Local edit that will be staged
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Env
      (PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes, Zone, SubZone, SiteSeries)
     VALUES
      ('P-201', 'PRJ', 51.0, -121.0, 950, DATE '2026-02-02', 'LocalUser', 'staged', 'ICH', 'dw', '01')"
  )

  results <- sync_push(
    con,
    project_id = "PRJ",
    tables = c("sample_env"),
    allow_attach = FALSE,
    submitter = "tester"
  )

  mr_id <- as.integer(results$merge_request_id)
  staged <- DBI::dbGetQuery(con, "SELECT base_row_version FROM master.staging.sample_env WHERE merge_request_id = ?", list(mr_id))
  testthat::expect_equal(staged$base_row_version[1], 1)

  # Simulate a concurrent core change after submission
  DBI::dbExecute(
    con,
    "UPDATE master.core.sample_env
     SET latitude = 49.5, row_version = 2
     WHERE plot_number = 'P-201' AND project_id = 'PRJ'"
  )

  merge_request_refresh_conflicts(con, mr_id)
  conflicts <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
  testthat::expect_equal(nrow(conflicts), 1)
  testthat::expect_equal(conflicts$table_name[1], "sample_env")

  # Resolve by keeping core (skip applying staged env row)
  merge_request_resolve_conflict(con, conflicts$id[1], "keep_core", actor = "reviewer")
  testthat::expect_equal(merge_request_unresolved_conflict_count(con, mr_id), 0)

  # Merge should now succeed and preserve the core value
  merge_approve_request(con, mr_id, reviewer = "reviewer", review_notes = "ok")

  env <- DBI::dbGetQuery(con, "SELECT latitude, row_version FROM master.core.sample_env WHERE plot_number = 'P-201' AND project_id = 'PRJ'")
  testthat::expect_equal(env$latitude[1], 49.5)
  testthat::expect_equal(env$row_version[1], 2)

  mr <- DBI::dbGetQuery(con, "SELECT status FROM master.admin.merge_requests WHERE id = ?", list(mr_id))
  testthat::expect_equal(mr$status[1], "merged")
})
