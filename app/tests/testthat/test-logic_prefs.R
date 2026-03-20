# Tests for config-backed current settings and preference storage helpers

source(here::here("app", "R", "logic", "01.state.R"))
source(here::here("app", "R", "logic", "logic_state.R"))

test_that("get_current_setting returns defaults when missing", {
  cfg_path <- tempfile(fileext = ".yml")
  yaml::write_yaml(list(Current = list()), cfg_path)

  expect_equal(get_current_setting("CurrProject", default = "Sample", conf = cfg_path), "Sample")
  expect_equal(get_current_setting("CurrPlotList", default = NULL, conf = cfg_path), NULL)
})

test_that("set_current_setting stores and normalizes current values", {
  cfg_path <- tempfile(fileext = ".yml")
  yaml::write_yaml(list(Current = list()), cfg_path)

  set_current_setting("CurrProject", "P-123", conf = cfg_path)
  expect_equal(get_current_setting("CurrProject", default = NULL, conf = cfg_path), "P-123")

  set_current_setting("CurrProject", "None", conf = cfg_path)
  expect_null(get_current_setting("CurrProject", default = NULL, conf = cfg_path))

  set_current_setting("CurrProject", NULL, conf = cfg_path)
  expect_null(get_current_setting("CurrProject", default = NULL, conf = cfg_path))
})

test_that("get_pref returns defaults when missing for non-current settings", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")

  expect_equal(get_pref(con, "ReportOptions", "cmbColourGreater", default = 5L), 5L)
  expect_equal(get_pref(con, "Message", "ShowWhatsNew", default = TRUE), TRUE)
})

test_that("set_pref stores and get_pref retrieves non-current values", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")

  set_pref(con, "ReportOptions", "cmbColourGreater", 10)

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
