testthat::context("staging_compliance_checks")

source(here::here("R", "logic_compliance.R"))
source(here::here("R", "logic_sync.R"))

setup_staging_compliance_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_compliance_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))
  DBI::dbExecute(con, "CREATE SCHEMA master.staging")
  DBI::dbExecute(con, "CREATE SCHEMA lists")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.sample_env (
      plot_number TEXT,
      project_id TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation_m DOUBLE,
      merge_request_id INTEGER
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.staging.sample_veg (
      plot_number TEXT,
      project_id TEXT,
      species_code TEXT,
      layer_code TEXT,
      merge_request_id INTEGER
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE lists.SppList (
      spp_code TEXT
    )
  ")

  con
}

testthat::test_that("staging compliance passes for valid data", {
  con <- setup_staging_compliance_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO lists.SppList (spp_code) VALUES ('AB')")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.sample_env
      (plot_number, project_id, latitude, longitude, elevation_m, merge_request_id)
    VALUES ('P-1', 'PRJ', 52.1, -118.5, 500, 1)
  ")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.sample_veg
      (plot_number, project_id, species_code, layer_code, merge_request_id)
    VALUES ('P-1', 'PRJ', 'AB', 'T', 1)
  ")

  result <- staging_compliance_checks(con, 1, "PRJ")
  testthat::expect_true(isTRUE(result$passed))
})

testthat::test_that("staging compliance flags invalid species", {
  con <- setup_staging_compliance_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO lists.SppList (spp_code) VALUES ('AB')")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.sample_env
      (plot_number, project_id, latitude, longitude, elevation_m, merge_request_id)
    VALUES ('P-2', 'PRJ', 52.1, -118.5, 500, 2)
  ")

  DBI::dbExecute(con, "
    INSERT INTO master.staging.sample_veg
      (plot_number, project_id, species_code, layer_code, merge_request_id)
    VALUES ('P-2', 'PRJ', 'ZZ', 'T', 2)
  ")

  result <- staging_compliance_checks(con, 2, "PRJ")
  testthat::expect_false(isTRUE(result$passed))
  testthat::expect_true("fk_species" %in% result$detail_tibble$rule)
})
