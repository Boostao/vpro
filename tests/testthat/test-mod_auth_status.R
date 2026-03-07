testthat::context("mod_auth_status")

library(shiny)

source(here::here("tests", "testthat", "setup.R"))
source(here::here("tests", "testthat", "helpers.R"))
source(here::here("R", "db_connections.R"))
source(here::here("R", "logic_auth.R"))
source(here::here("R", "logic_sync.R"))
source(here::here("R", "mod_auth_status.R"))

# =============================================================================
# .format_time_ago
# =============================================================================

testthat::test_that(".format_time_ago returns 'never' for NULL", {
  testthat::expect_equal(.format_time_ago(NULL), "never")
})

testthat::test_that(".format_time_ago returns 'never' for NA", {
  testthat::expect_equal(.format_time_ago(NA), "never")
})

testthat::test_that(".format_time_ago returns 'just now' for timestamps within 60 seconds", {
  ts <- Sys.time() - 30
  testthat::expect_equal(.format_time_ago(ts), "just now")
})

testthat::test_that(".format_time_ago returns 'just now' for future timestamps", {
  ts <- Sys.time() + 10
  testthat::expect_equal(.format_time_ago(ts), "just now")
})

testthat::test_that(".format_time_ago returns minutes for timestamps 1-59 minutes ago", {
  ts <- Sys.time() - 150  # 2.5 minutes
  testthat::expect_equal(.format_time_ago(ts), "2 min ago")
})

testthat::test_that(".format_time_ago returns hours for timestamps 1-23 hours ago", {
  ts <- Sys.time() - 7200  # 2 hours
  testthat::expect_equal(.format_time_ago(ts), "2 hr ago")
})

testthat::test_that(".format_time_ago returns days for timestamps 1+ days ago", {
  ts <- Sys.time() - 86400 * 3  # 3 days
  testthat::expect_equal(.format_time_ago(ts), "3 days ago")
})

testthat::test_that(".format_time_ago floors partial units", {
  ts <- Sys.time() - (90 * 60)  # 90 minutes = 1.5 hours → "1 hr ago"
  testthat::expect_equal(.format_time_ago(ts), "1 hr ago")
})
