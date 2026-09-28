.app_project_table_helpers <- function() {
  app_dir <- test_path("..", "..", "inst", "app")
  app_env <- new.env(parent = globalenv())
  withr::with_dir(app_dir, sys.source("global.R", envir = app_env))
  app_env
}

test_that("project table identifiers use the managed project alias", {
  app_env <- .app_project_table_helpers()
  project_path <- tempfile(fileext = ".sqlite")
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  on.exit(DBI::dbDisconnect(sqlite), add = TRUE)
  DBI::dbExecute(sqlite, "CREATE TABLE Sample_Env (id INTEGER)")

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con,
    paste(
      "ATTACH",
      DBI::dbQuoteLiteral(con, project_path),
      "AS vpro_project_sample (TYPE sqlite)"
    )
  )

  expect_identical(
    app_env$app_project_table_id(con, "Env", "Sample", prj = TRUE),
    DBI::Id(schema = "vpro_project_sample", table = "Sample_Env")
  )
  expect_identical(
    app_env$app_project_table_id(con, "USysVegC"),
    DBI::Id(table = "USysVegC")
  )
})

test_that("project table SQL finds an alternate alias for an attached project", {
  app_env <- .app_project_table_helpers()
  project_path <- tempfile(fileext = ".sqlite")
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  on.exit(DBI::dbDisconnect(sqlite), add = TRUE)
  DBI::dbExecute(sqlite, "CREATE TABLE Sample_Env (id INTEGER)")

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con,
    paste(
      "ATTACH",
      DBI::dbQuoteLiteral(con, project_path),
      "AS alternate_alias (TYPE sqlite)"
    )
  )

  table_id <- app_env$app_project_table_id(con, "Env", "Sample", prj = TRUE)
  relation <- app_env$app_project_table_sql(con, "Env", "Sample", prj = TRUE)
  expect_identical(
    table_id,
    DBI::Id(schema = "alternate_alias", table = "Sample_Env")
  )
  expect_identical(
    as.character(relation),
    as.character(DBI::dbQuoteIdentifier(con, table_id))
  )
  expect_equal(DBI::dbGetQuery(con, paste("SELECT * FROM", relation)), data.frame(id = integer()))
})

test_that("non-project table SQL remains connection-local", {
  app_env <- .app_project_table_helpers()
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE Sample_Admin (id INTEGER)")
  DBI::dbExecute(con, "CREATE TEMP VIEW USysVegC AS SELECT 1 AS id")

  admin <- app_env$app_project_table_sql(con, "Sample_Admin", "Sample")
  veg_c <- app_env$app_project_table_sql(con, "USysVegC", "Sample")
  expect_identical(
    as.character(admin),
    as.character(DBI::dbQuoteIdentifier(con, DBI::Id(table = "Sample_Admin")))
  )
  expect_identical(
    as.character(veg_c),
    as.character(DBI::dbQuoteIdentifier(con, DBI::Id(table = "USysVegC")))
  )
  expect_equal(DBI::dbGetQuery(con, paste("SELECT * FROM", admin)), data.frame(id = integer()))
  expect_equal(DBI::dbGetQuery(con, paste("SELECT * FROM", veg_c)), data.frame(id = 1))
})
