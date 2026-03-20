# Tests for validation logic (Step 3)
# These tests validate business rules and reference data checks
library(testthat)
library(DBI)
source(here::here("R", "logic_validation.R"))
source(here::here("tests", "testthat", "helpers.R"))

# Test setup ----
test_that("Test database connection available", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  expect_s4_class(con, "PqConnection")
  DBI::dbDisconnect(con)
})


# validate_veg_row tests ----
test_that("validate_veg_row accepts valid vegetation row", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(valid_row, con, "postgres")
  
  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_veg_row rejects invalid cover1", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 150,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("cover1 must be numeric between 0 and 100", result$errors)))
})

test_that("validate_veg_row rejects negative height1", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = -100,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("height1 must be numeric >= 0", result$errors)))
})

test_that("validate_veg_row rejects unknown species_code", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "INVALID_SPP",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("species_code .* not found in reference data", result$errors)))
})

test_that("validate_veg_row rejects unknown layer_code", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "INVALID",
    cover1 = 25,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("layer_code .* not found in reference data", result$errors)))
})

test_that("validate_veg_row rejects empty plot_number", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "",  # Empty
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("plot_number must be non-empty text", result$errors)))
})

test_that("validate_veg_row rejects invalid project_id", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    project_id = -1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("project_id must be a positive integer", result$errors)))
})

test_that("validate_veg_row validates all cover fields (cover2-10, totala, totalb, cover5a/b/c)", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Test invalid cover2
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    cover2 = 105,
    height1 = 1500,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("cover2 must be numeric between 0 and 100", result$errors)))
  
  # Test invalid totala
  invalid_row$cover2 <- 50
  invalid_row$totala <- -10
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("totala must be numeric between 0 and 100", result$errors)))
  
  # Test invalid cover5a
  invalid_row$totala <- 75
  invalid_row$cover5a <- 150
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("cover5a must be numeric between 0 and 100", result$errors)))
})

test_that("validate_veg_row validates all height fields", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Test invalid height2
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    height2 = -50,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("height2 must be numeric >= 0", result$errors)))
  
  # Test invalid height5a
  invalid_row$height2 <- 1200
  invalid_row$height5a <- -100
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("height5a must be numeric >= 0", result$errors)))
})

test_that("validate_veg_row validates metric fields as non-negative integers", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Test invalid veg_id (negative)
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    veg_id = -1,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("veg_id must be a non-negative integer", result$errors)))
  
  # Test invalid ll (non-integer)
  invalid_row$veg_id <- 10
  invalid_row$ll <- 3.5
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("ll must be a non-negative integer", result$errors)))
  
  # Test cultural1 valid
  invalid_row$ll <- 5
  invalid_row$cultural1 <- 0
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_true(result$valid)
})

test_that("validate_veg_row validates collected as text", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    collected = "yes",
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(valid_row, con, "postgres")
  expect_true(result$valid)
})

test_that("validate_veg_row validates flag as boolean", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Valid: flag = TRUE
  valid_row <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover1 = 25,
    height1 = 1500,
    flag = TRUE,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- validate_veg_row(valid_row, con, "postgres")
  expect_true(result$valid)
  
  # Invalid: flag = 1 (not boolean)
  invalid_row <- valid_row
  invalid_row$flag <- 1
  result <- validate_veg_row(invalid_row, con, "postgres")
  expect_false(result$valid)
  expect_true(any(grepl("flag must be TRUE/FALSE", result$errors)))
})


# validate_env_row tests ----
test_that("validate_env_row accepts valid environment row", {
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 500,
    survey_date = "2024-06-15",
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(valid_row)
  
  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_env_row rejects invalid latitude", {
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 999,  # Invalid: out of BC range
    longitude = -123.5,
    elevation_m = 500,
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(invalid_row)
  
  expect_false(result$valid)
  expect_true(any(grepl("latitude must be numeric between 48 and 60", result$errors)))
})

test_that("validate_env_row rejects invalid longitude", {
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = 50,  # Invalid: out of BC range (should be negative)
    elevation_m = 500,
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(invalid_row)
  
  expect_false(result$valid)
  expect_true(any(grepl("longitude must be numeric between -140 and -114", result$errors)))
})

test_that("validate_env_row rejects invalid elevation_m", {
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 5000,  # Invalid: too high for BC
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(invalid_row)
  
  expect_false(result$valid)
  expect_true(any(grepl("elevation_m must be numeric between 0 and 4000", result$errors)))
})

test_that("validate_env_row accepts NULL optional fields", {
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = NA,
    longitude = NA,
    elevation_m = NA,
    survey_date = NA,
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(valid_row)
  
  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_env_row validates surveyor_name as text", {
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 500,
    surveyor_name = "John Doe",
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(valid_row)
  expect_true(result$valid)
})

test_that("validate_env_row validates plot_notes as text", {
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 500,
    plot_notes = "Sample notes for this plot",
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(valid_row)
  expect_true(result$valid)
})

test_that("validate_env_row rejects invalid survey_date format", {
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 500,
    survey_date = "not-a-date",
    stringsAsFactors = FALSE
  )
  
  result <- validate_env_row(invalid_row)
  
  expect_false(result$valid)
  expect_true(any(grepl("survey_date must be a valid date", result$errors)))
})


# validate_su_row tests ----
test_that("validate_su_row accepts valid site unit row", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    bec_zone = "CWH",
    bec_subzone = "dm",
    site_series = "01",
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(valid_row, con, "postgres")
  
  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_su_row rejects unknown bec_zone", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    bec_zone = "INVALID",  # Not in seed data
    bec_subzone = "dm",
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("bec_zone .* not found in reference data", result$errors)))
})

test_that("validate_su_row rejects invalid zone/subzone combo", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    bec_zone = "CWH",
    bec_subzone = "xx",  # Invalid combo (CWH/xx doesn't exist)
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("bec_subzone .* not found for bec_zone", result$errors)))
})

test_that("validate_su_row accepts NULL zone/subzone", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    bec_zone = NA,
    bec_subzone = NA,
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(valid_row, con, "postgres")
  
  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_su_row validates su_number as text", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    su_number = "SU001",
    bec_zone = "CWH",
    bec_subzone = "dm",
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(valid_row, con, "postgres")
  
  expect_true(result$valid)
})

test_that("validate_su_row validates site_series as text", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  valid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    site_series = "CWHdm/01",
    bec_zone = "CWH",
    bec_subzone = "dm",
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(valid_row, con, "postgres")
  
  expect_true(result$valid)
})

test_that("validate_su_row rejects orphaned subzone (no zone)", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_row <- data.frame(
    plot_number = "PLOT001",
    project_id = 1,
    bec_zone = NA,
    bec_subzone = "dm",  # Subzone without zone
    stringsAsFactors = FALSE
  )
  
  result <- validate_su_row(invalid_row, con, "postgres")
  
  expect_false(result$valid)
  expect_true(any(grepl("bec_zone must be provided if bec_subzone is specified", result$errors)))
})


# validate_submission tests ----
test_that("validate_submission validates multiple tables correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  data_list <- list(
    veg = data.frame(
      plot_number = c("PLOT001", "PLOT002"),
      species_code = c("TSUGHET", "THUJOCC"),
      layer_code = c("T1", "T2"),
      cover1 = c(25, 30),
      height1 = c(1500, 1200),
      project_id = c(1, 1),
      stringsAsFactors = FALSE
    ),
    env = data.frame(
      plot_number = c("PLOT001", "PLOT002"),
      project_id = c(1, 1),
      latitude = c(49.5, 50.0),
      longitude = c(-123.5, -124.0),
      elevation_m = c(500, 600),
      stringsAsFactors = FALSE
    ),
    su = data.frame(
      plot_number = c("PLOT001", "PLOT002"),
      project_id = c(1, 1),
      bec_zone = c("CWH", "CWH"),
      bec_subzone = c("dm", "vm"),
      stringsAsFactors = FALSE
    )
  )
  
  result <- validate_submission(data_list, con, "postgres")
  
  expect_true(result$valid)
  expect_equal(nrow(result$summary), 3)
  expect_equal(result$summary$invalid_rows, c(0, 0, 0))
})

test_that("validate_submission detects errors across multiple tables", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  data_list <- list(
    veg = data.frame(
      plot_number = c("TEST_VALID_PLOT", "TEST_INVALID_PLOT"),
      species_code = c("TSUGHET", "INVALID_SPP"),
      layer_code = c("T1", "T2"),
      cover1 = c(25, 30),
      height1 = c(1500, 1200),
      project_id = c(1, 1),
      stringsAsFactors = FALSE
    ),
    env = data.frame(
      plot_number = c("TEST_VALID_PLOT", "TEST_INVALID_PLOT"),
      project_id = c(1, 1),
      latitude = c(49.5, 999),  # Second row invalid
      longitude = c(-123.5, -124.0),
      elevation_m = c(500, 600),
      stringsAsFactors = FALSE
    )
  )
  
  result <- validate_submission(data_list, con, "postgres")
  
  expect_false(result$valid)
  expect_equal(nrow(result$summary), 2)
  expect_equal(result$summary$invalid_rows[1], 1)  # 1 invalid veg row
  expect_equal(result$summary$invalid_rows[2], 1)  # 1 invalid env row
  expect_true(!is.null(result$errors$veg))
  expect_true(!is.null(result$errors$env))
})

test_that("validate_submission returns proper summary structure", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  data_list <- list(
    veg = data.frame(
      plot_number = "PLOT001",
      species_code = "TSUGHET",
      layer_code = "T1",
      cover1 = 25,
      height1 = 1500,
      project_id = 1,
      stringsAsFactors = FALSE
    )
  )
  
  result <- validate_submission(data_list, con, "postgres")
  
  expect_true(result$valid)
  expect_s3_class(result$summary, "data.frame")
  expect_named(result$summary, c("table", "total_rows", "valid_rows", "invalid_rows"))
  expect_equal(result$summary$table, "veg")
  expect_equal(result$summary$total_rows, 1)
  expect_equal(result$summary$valid_rows, 1)
  expect_equal(result$summary$invalid_rows, 0)
})
