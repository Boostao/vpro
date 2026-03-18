# Tests for preference storage helpers

source(here::here("R", "logic_state.R"))

test_that("get_pref returns defaults when missing", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")

  expect_equal(get_pref(con, "Current", "CurrProject", default = "Sample"), "Sample")
  expect_equal(get_pref(con, "Current", "CurrPlotList", default = "None"), "None")
})

test_that("set_pref stores and get_pref retrieves values", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")

  set_pref(con, "Current", "CurrProject", "P-123")
  set_pref(con, "ReportOptions", "cmbColourGreater", 10)

  expect_equal(get_pref(con, "Current", "CurrProject", default = NULL), "P-123")
  expect_equal(get_pref(con, "ReportOptions", "cmbColourGreater", default = 5L), 10L)
})

test_that("get_pref coerces values to requested type", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")

  set_pref(con, "ReportOptions", "cmbApplyTheme", 1)
  set_pref(con, "ReportOptions", "cmbGrayGreater", "65")

  expect_true(get_pref(con, "ReportOptions", "cmbApplyTheme", default = FALSE))
  expect_equal(get_pref(con, "ReportOptions", "cmbGrayGreater", default = 0L), 65L)
})
