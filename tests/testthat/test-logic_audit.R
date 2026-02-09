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

test_that("log_audit_diff logs multiple field changes", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_audit_env(con)

  old_row <- data.frame(latitude = 50, longitude = -120, stringsAsFactors = FALSE)
  new_row <- data.frame(latitude = 51, longitude = -120, stringsAsFactors = FALSE)

  logged <- log_audit_diff(con, "PRJ", "tester", "P1", "Sample_Env", old_row, new_row)
  expect_equal(logged, 1L)

  rows <- DBI::dbGetQuery(con, "SELECT * FROM user.USysAuditTrail")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$EditField[1], "latitude")
})

test_that("log_audit_rows logs insert values", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_audit_env(con)

  rows <- data.frame(
    plotnumber = c("P1", "P2"),
    projectid = c("PRJ", "PRJ"),
    latitude = c(50, 51),
    stringsAsFactors = FALSE
  )

  logged <- log_audit_rows(con, "PRJ", "tester", "Sample_Env", rows)
  expect_true(logged >= 2)

  audit <- DBI::dbGetQuery(con, "SELECT * FROM user.USysAuditTrail")
  expect_true(nrow(audit) >= 2)
  expect_true(all(audit$Project == "PRJ"))
})

test_that("log_master_audit writes master audit entries", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  log_master_audit(con, "tester", "Delete", "UnitA", 10, "Name", "UnitA", "UnitB", parent = "Root")

  rows <- DBI::dbGetQuery(con, "SELECT * FROM user.USysMasterAudit")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$Action[1], "Delete")
  expect_equal(rows$NodeName[1], "UnitA")
  expect_equal(rows$Parent[1], "Root")
})

test_that("fetch_master_audit_entries filters entries", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  ensure_master_audit_table(con)
  log_master_audit(con, "tester", "Add", "UnitA", 10, "Name", NA, "UnitA")
  log_master_audit(con, "tester", "Edit", "UnitB", 11, "Name", "Old", "New")

  rows <- fetch_master_audit_entries(con, action = "Edit")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$NodeName[1], "UnitB")
})
