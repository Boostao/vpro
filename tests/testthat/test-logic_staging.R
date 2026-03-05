# Tests for staging submission logic (Step 4)
# These tests validate data submission to staging tables and merge request creation

# Test setup ----
test_that("Test database connection available", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  expect_s4_class(con, "PqConnection")
  DBI::dbDisconnect(con)
})


# submit_changes tests ----
test_that("submit_changes creates merge request and inserts single table veg data", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up any existing staging data
  DBI::dbExecute(con, "DELETE FROM staging.veg")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  veg_data <- data.frame(
    plot_number = "TEST_STAGING_001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 30,
    height_cm = 1800,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  result <- submit_changes(con, list(veg = list(inserts = veg_data)),
                          "Test User", "test@example.com", 1)
  
  expect_type(result$merge_request_id, "integer")
  expect_true(result$merge_request_id > 0)
  
  # Verify merge request created
  mr <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.merge_requests WHERE id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(mr), 1)
  expect_equal(mr$submitter_name, "Test User")
  expect_equal(mr$submitter_email, "test@example.com")
  expect_equal(mr$status, "pending_review")
  expect_equal(mr$project_id, 1)
  
  # Verify data in staging table
  staging_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.veg WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(staging_rows), 1)
  expect_equal(staging_rows$plot_number, "TEST_STAGING_001")
  expect_equal(staging_rows$species_code, "TSUGHET")
  expect_equal(staging_rows$change_type, "I")
})

test_that("submit_changes validates data before submission", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  invalid_veg <- data.frame(
    plot_number = "TEST_INVALID",
    species_code = "INVALID_SPECIES",  # Not in reference data
    layer_code = "T1",
    cover_percent = 30,
    height_cm = 1800,
    project_id = 1,
    stringsAsFactors = FALSE
  )
  
  expect_error(
    submit_changes(con, list(veg = list(inserts = invalid_veg)),
                  "Test User", "test@example.com", 1),
    "validation failed"
  )
})

test_that("submit_changes rejects invalid table names", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  data <- data.frame(col1 = 1)
  
  expect_error(
    submit_changes(con, list(invalid_table = list(inserts = data)),
                  "Test User", "test@example.com", 1),
    "Invalid table name"
  )
})

test_that("submit_changes handles env data correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up
  DBI::dbExecute(con, "DELETE FROM staging.env")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  env_data <- data.frame(
    plot_number = "TEST_ENV_001",
    project_id = 1,
    latitude = 49.5,
    longitude = -123.5,
    elevation_m = 500,
    stringsAsFactors = FALSE
  )
  
  result <- submit_changes(con, list(env = list(inserts = env_data)),
                          "Test User", "test@example.com", 1)
  
  expect_type(result$merge_request_id, "integer")
  
  staging_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.env WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(staging_rows), 1)
  expect_equal(staging_rows$plot_number, "TEST_ENV_001")
  expect_equal(staging_rows$latitude, 49.5)
})

test_that("submit_changes handles su data correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up
  DBI::dbExecute(con, "DELETE FROM staging.su")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  su_data <- data.frame(
    plot_number = "TEST_SU_001",
    project_id = 1,
    bec_zone = "CWH",
    bec_subzone = "dm",
    stringsAsFactors = FALSE
  )
  
  result <- submit_changes(con, list(su = list(inserts = su_data)),
                          "Test User", "test@example.com", 1)
  
  expect_type(result$merge_request_id, "integer")
  
  staging_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.su WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(staging_rows), 1)
  expect_equal(staging_rows$plot_number, "TEST_SU_001")
  expect_equal(staging_rows$bec_zone, "CWH")
})
test_that("submit_changes handles multiple tables and change types", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up
  DBI::dbExecute(con, "DELETE FROM staging.veg")
  DBI::dbExecute(con, "DELETE FROM staging.env")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  changes <- list(
    veg = list(
      inserts = data.frame(
        plot_number = "MULTI_001",
        species_code = "TSUGHET",
        layer_code = "T1",
        cover_percent = 30,
        height_cm = 1800,
        project_id = 1,
        stringsAsFactors = FALSE
      ),
      updates = data.frame(
        plot_number = "MULTI_002",
        species_code = "THUJOCC",
        layer_code = "T2",
        cover_percent = 40,
        height_cm = 2000,
        project_id = 1,
        stringsAsFactors = FALSE
      )
    ),
    env = list(
      inserts = data.frame(
        plot_number = "MULTI_001",
        project_id = 1,
        latitude = 49.5,
        longitude = -123.5,
        elevation_m = 500,
        stringsAsFactors = FALSE
      )
    )
  )
  
  result <- submit_changes(con, changes, "Multi User", "multi@example.com", 1)
  
  expect_type(result$merge_request_id, "integer")
  expect_s3_class(result$summary, "data.frame")
  expect_equal(nrow(result$summary), 3)  # 2 veg + 1 env
  
  # Verify all data submitted under same merge request
  veg_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.veg 
    WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(veg_rows), 2)
  expect_true(all(c("I", "U") %in% veg_rows$change_type))
  
  env_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.env 
    WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(env_rows), 1)
  expect_equal(env_rows$change_type, "I")
})

test_that("submit_changes updates record_counts correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up
  DBI::dbExecute(con, "DELETE FROM staging.veg")
  DBI::dbExecute(con, "DELETE FROM staging.env")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  changes <- list(
    veg = list(
      inserts = data.frame(
        plot_number = c("COUNT_001", "COUNT_002"),
        species_code = c("TSUGHET", "THUJOCC"),
        layer_code = c("T1", "T2"),
        cover_percent = c(30, 40),
        height_cm = c(1800, 2000),
        project_id = c(1, 1),
        stringsAsFactors = FALSE
      )
    )
  )
  
  result <- submit_changes(con, changes, "Count User", "count@example.com", 1)
  
  # Check merge request record_counts
  mr <- DBI::dbGetQuery(con, sprintf("
    SELECT record_counts FROM staging.merge_requests WHERE id = %d
  ", result$merge_request_id))
  
  expect_true(grepl("veg", mr$record_counts))
  expect_true(grepl("inserts", mr$record_counts))
})

test_that("submit_changes handles deletes correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up
  DBI::dbExecute(con, "DELETE FROM staging.veg")
  DBI::dbExecute(con, "DELETE FROM staging.merge_requests")
  
  changes <- list(
    veg = list(
      deletes = data.frame(
        plot_number = "DELETE_001",
        species_code = "TSUGHET",
        layer_code = "T1",
        project_id = 1,
        stringsAsFactors = FALSE
      )
    )
  )
  
  result <- submit_changes(con, changes, "Delete User", "delete@example.com", 1)
  
  # Verify delete change_type
  veg_rows <- DBI::dbGetQuery(con, sprintf("
    SELECT * FROM staging.veg 
    WHERE merge_request_id = %d
  ", result$merge_request_id))
  
  expect_equal(nrow(veg_rows), 1)
  expect_equal(veg_rows$change_type, "D")
})

test_that("submit_changes validates all data before submission", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  changes <- list(
    veg = list(
      inserts = data.frame(
        plot_number = "INVALID",
        species_code = "INVALID_SPECIES",  # Bad species
        layer_code = "T1",
        cover_percent = 30,
        height_cm = 1800,
        project_id = 1,
        stringsAsFactors = FALSE
      )
    )
  )
  
  expect_error(
    submit_changes(con, changes, "Invalid User", "invalid@example.com", 1),
    "validation failed"
  )
  
  # Verify no merge request created (transaction rolled back)
  mr_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM staging.merge_requests 
    WHERE submitter_email = 'invalid@example.com'
  ")$cnt
  
  expect_equal(mr_count, 0)
})

test_that("submit_changes rejects empty changes", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  changes <- list(
    veg = list(
      inserts = data.frame(),
      updates = data.frame()
    )
  )
  
  expect_error(
    submit_changes(con, changes, "Empty User", "empty@example.com", 1),
    "No changes to submit"
  )
})

test_that("submit_changes rolls back on error", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Get initial counts
  initial_mr_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM staging.merge_requests
  ")$cnt
  
  initial_veg_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM staging.veg
  ")$cnt
  
  changes <- list(
    veg = list(
      inserts = data.frame(
        plot_number = "ROLLBACK_001",
        species_code = "INVALID_SPP",  # This will fail validation
        layer_code = "T1",
        cover_percent = 30,
        height_cm = 1800,
        project_id = 1,
        stringsAsFactors = FALSE
      )
    )
  )
  
  expect_error(
    submit_changes(con, changes, "Rollback User", "rollback@example.com", 1)
  )
  
  # Verify nothing was committed
  final_mr_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM staging.merge_requests
  ")$cnt
  
  final_veg_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM staging.veg
  ")$cnt
  
  expect_equal(final_mr_count, initial_mr_count)
  expect_equal(final_veg_count, initial_veg_count)
})
