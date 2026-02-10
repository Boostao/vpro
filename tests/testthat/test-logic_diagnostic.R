# Tests for diagnostic helpers

source(here::here("R", "logic_diagnostic.R"))

test_that("parse_presence_significance parses codes", {
  parsed <- parse_presence_significance("53")
  expect_equal(parsed$presence, 5)
  expect_equal(parsed$significance, 3)

  parsed_single <- parse_presence_significance("5")
  expect_equal(parsed_single$presence, 5)
  expect_equal(parsed_single$significance, 5)
})

test_that("compute_diagnostic_flags finds differential and constant", {
  codes <- c(UnitA = "53", UnitB = "12")
  result <- compute_diagnostic_flags(codes)
  expect_equal(result$unit, "UnitA")
  expect_true(grepl("d", result$diagnosis))
  expect_true(grepl("c", result$diagnosis))
})

test_that("compute_diagnostic_row returns dd", {
  row <- data.frame(
    Species = "SP1",
    UnitA = "45",
    UnitB = "32",
    stringsAsFactors = FALSE
  )

  result <- compute_diagnostic_row(row)
  expect_equal(result$species, "SP1")
  expect_equal(result$unit, "UnitA")
  expect_equal(result$diagnosis, "dd")
})

test_that("diagnostic_from_matrix returns table", {
  df <- data.frame(
    Species = c("SP1", "SP2"),
    UnitA = c("45", "12"),
    UnitB = c("32", "53"),
    stringsAsFactors = FALSE
  )

  result <- diagnostic_from_matrix(df)
  expect_equal(nrow(result), 2)
  expect_equal(result$Species, c("SP1", "SP2"))
  expect_true(all(nzchar(result$Diagnosis)))
})

test_that("build_diagnostic_matrix returns matrix", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE TABLE vw_USysAllVeg (plotnumber TEXT, species_code TEXT, cover_value TEXT, projectid TEXT)")

  DBI::dbExecute(con, "INSERT INTO Sample_SU VALUES ('P1', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO Sample_SU VALUES ('P2', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('P1', 'SP1', '20', 'PRJ')")
  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('P2', 'SP1', '30', 'PRJ')")

  result <- build_diagnostic_matrix(con, project_id = "PRJ")
  expect_true(nrow(result$matrix) >= 1)
  expect_true("SU1" %in% names(result$matrix))
  expect_true(any(result$matrix$Species == "SP1"))
  expect_true(any(nzchar(result$matrix$SU1)))
})

test_that("build_diagnostic_matrix filters by project via Sample_Env", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Env (PlotNumber TEXT, ProjectID TEXT)")
  DBI::dbExecute(con, "CREATE TABLE vw_USysAllVeg (plotnumber TEXT, species_code TEXT, cover_value TEXT)")

  DBI::dbExecute(con, "INSERT INTO Sample_SU VALUES ('P1', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO Sample_SU VALUES ('P2', 'SU2')")
  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P1', 'PRJ1')")
  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P2', 'PRJ2')")
  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('P1', 'SP1', '20')")
  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('P2', 'SP1', '30')")

  result <- build_diagnostic_matrix(con, project_id = "PRJ1")
  expect_true("SU1" %in% names(result$matrix))
  expect_false("SU2" %in% names(result$matrix))
})
