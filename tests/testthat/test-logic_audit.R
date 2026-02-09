# Tests for audit trail helpers

source(here::here("R", "logic_audit.R"))

setup_audit_env <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS user.USysAuditTrail (
      Project TEXT,
      \"User\" TEXT,
      PlotNumber TEXT,
      \"Table\" TEXT,
      EditField TEXT,
      EditWhen TIMESTAMP,
      BeforeEdit TEXT,
      AfterEdit TEXT
    )
  ")
}

test_that("log_audit_change writes entries", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_audit_env(con)

  log_audit_change(con, "PRJ", "tester", "P1", "Sample_Env", "latitude", 50, 51)

  rows <- DBI::dbGetQuery(con, "SELECT * FROM user.USysAuditTrail")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$Project[1], "PRJ")
  expect_equal(rows$PlotNumber[1], "P1")
  expect_equal(rows$EditField[1], "latitude")
  expect_equal(rows$BeforeEdit[1], "50")
  expect_equal(rows$AfterEdit[1], "51")
})
