# Tests for core views

library(DBI)
library(duckdb)

test_that("core views exist and are queryable", {
  db_path <- file.path(getwd(), "data", "vpro.duckdb")
  if (!file.exists(db_path)) {
    testthat::skip("Local duckdb not found. Run scripts/01_build_database.R first.")
  }

  con <- dbConnect(duckdb::duckdb(), db_path)
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  expect_true(DBI::dbExistsTable(con, "vw_USysAllVeg"))
  expect_true(DBI::dbExistsTable(con, "vw_USysEnv"))

  veg_cols <- names(DBI::dbGetQuery(con, "SELECT * FROM vw_USysAllVeg LIMIT 1"))
  env_cols <- names(DBI::dbGetQuery(con, "SELECT * FROM vw_USysEnv LIMIT 1"))

  expect_true("plotnumber" %in% veg_cols)
  expect_true("cover_value" %in% veg_cols)
  expect_true("plotnumber" %in% env_cols)
})
