# test-logic_merge.R
# Tests for admin merge workflow

test_that("list_pending_merges returns empty when no pending requests", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean slate
  clear_staging_tables(con)
  
  result <- list_pending_merges(con)
  
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})

test_that("list_pending_merges returns pending requests with record counts", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_staging_tables(con)
  
  # Create a merge request with veg data
  veg_data <- data.frame(
    plot_number = "TEST001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)), 
                          "test_user", "test@example.com", 1L)$merge_request_id
  
  result <- list_pending_merges(con)
  
  expect_equal(nrow(result), 1)
  expect_equal(result$id, mr_id)
  expect_equal(result$submitter_name, "test_user")
  expect_equal(result$submitter_email, "test@example.com")
  expect_equal(result$status, "pending_review")
  expect_type(result$record_counts, "list")
  expect_equal(result$record_counts[[1]]$veg$inserts, 1)
})

test_that("get_merge_details returns empty for non-existent request", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  result <- get_merge_details(con, 99999)
  
  expect_type(result, "list")
  expect_equal(length(result), 3)
  expect_equal(nrow(result$veg), 0)
  expect_equal(nrow(result$env), 0)
  expect_equal(nrow(result$su), 0)
})

test_that("get_merge_details validates input", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  expect_error(get_merge_details(con, -1), "positive integer")
  expect_error(get_merge_details(con, "abc"), "positive integer")
})

test_that("get_merge_details returns staging data for valid request", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_staging_tables(con)
  
  veg_data <- data.frame(
    plot_number = "TEST001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  env_data <- data.frame(
    plot_number = "TEST001",
    project_id = 1L,
    latitude = 50.5,
    longitude = -120.5,
    elevation_m = 800L,
    survey_date = as.Date("2023-06-15"),
    surveyor_name = "J. Smith",
    plot_notes = NA_character_,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, 
                         list(veg = list(inserts = veg_data), 
                              env = list(inserts = env_data)),
                         "test_user", "test@example.com", 1L)$merge_request_id
  
  result <- get_merge_details(con, mr_id)
  
  expect_equal(nrow(result$veg), 1)
  expect_equal(nrow(result$env), 1)
  expect_equal(nrow(result$su), 0)
  expect_equal(result$veg$plot_number, "TEST001")
  expect_equal(result$env$plot_number, "TEST001")
})

test_that("detect_conflicts identifies insert collisions", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Insert a row into core
  DBI::dbExecute(con, "
    INSERT INTO core.veg 
      (plot_number, species_code, layer_code, cover_percent, 
       height_cm, project_id, modified_by)
    VALUES ('PLOT001', 'TSUGHET', 'T1', 30, 1200, 1, 'seeder')
  ")
  
  # Try to insert the same key via staging
  veg_data <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  conflicts <- detect_conflicts(con, mr_id)
  
  expect_equal(nrow(conflicts), 1)
  expect_equal(conflicts$table_name, "veg")
  expect_true(conflicts$conflict_count > 0)
  
  # Check merge_conflicts table
  conflict_rows <- DBI::dbGetQuery(con, "
    SELECT * FROM staging.merge_conflicts WHERE merge_request_id = $1
  ", params = list(mr_id))
  
  expect_true(nrow(conflict_rows) > 0)
  expect_false(conflict_rows$resolved[1])
})

test_that("detect_conflicts identifies update target missing", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Try to update a non-existent row
  DBI::dbExecute(con, "
    INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
    VALUES (1, 'user', 'user@example.com', 'pending_review')
    RETURNING id
  ") -> mr_id_query
  
  mr_id <- DBI::dbGetQuery(con, "SELECT lastval()")[[1]]
  
  DBI::dbExecute(con, "
    INSERT INTO staging.veg 
      (merge_request_id, plot_number, species_code, layer_code,
       cover_percent, height_cm, project_id, change_type)
    VALUES ($1, 'PLOT999', 'TSUGHET', 'T1', 40, 1300, 1, 'U')
  ", params = list(mr_id))
  
  conflicts <- detect_conflicts(con, mr_id)
  
  expect_true(nrow(conflicts) > 0)
  expect_equal(conflicts$table_name, "veg")
})

test_that("detect_conflicts identifies cross-request conflicts", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Submit first merge request
  veg_data1 <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 30L,
    height_cm = 1200L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id1 <- submit_changes(con, list(veg = list(inserts = veg_data1)),
                          "user1", "user1@example.com", 1L)$merge_request_id
  
  # Submit second merge request with same key
  veg_data2 <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id2 <- submit_changes(con, list(veg = list(inserts = veg_data2)),
                          "user2", "user2@example.com", 1L)$merge_request_id
  
  # Detect conflicts in second request
  conflicts <- detect_conflicts(con, mr_id2)
  
  expect_true(nrow(conflicts) > 0)
  expect_true(conflicts$conflict_count > 0)
})

test_that("detect_conflicts handles env and su tables", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Insert core data
  DBI::dbExecute(con, "
    INSERT INTO core.env 
      (plot_number, project_id, latitude, longitude, elevation_m, modified_by)
    VALUES ('ENV001', 1, 50.0, -120.0, 500, 'seeder')
  ")
  
  # Try to insert same plot via staging
  env_data <- data.frame(
    plot_number = "ENV001",
    project_id = 1L,
    latitude = 51.0,
    longitude = -121.0,
    elevation_m = 600L,
    survey_date = as.Date("2023-06-15"),
    surveyor_name = "J. Smith",
    plot_notes = NA_character_,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(env = list(inserts = env_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  conflicts <- detect_conflicts(con, mr_id)
  
  expect_equal(nrow(conflicts), 1)
  expect_equal(conflicts$table_name, "env")
})

test_that("resolve_conflict validates inputs", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  expect_error(resolve_conflict(con, -1, "keep_incoming"), "positive integer")
  expect_error(resolve_conflict(con, 1, "invalid"), "must be one of")
  expect_error(resolve_conflict(con, 99999, "keep_incoming"), "not found")
})

test_that("resolve_conflict marks conflict as resolved", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Create a conflict
  DBI::dbExecute(con, "
    INSERT INTO core.veg 
      (plot_number, species_code, layer_code, cover_percent,
       height_cm, project_id, modified_by)
    VALUES ('PLOT001', 'TSUGHET', 'T1', 30, 1200, 1, 'seeder')
  ")
  
  veg_data <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  detect_conflicts(con, mr_id)
  
  # Get conflict ID
  conflict <- DBI::dbGetQuery(con, "
    SELECT id FROM staging.merge_conflicts 
    WHERE merge_request_id = $1 LIMIT 1
  ", params = list(mr_id))
  
  expect_true(nrow(conflict) > 0)
  
  # Resolve it
  resolve_conflict(con, conflict$id, "keep_incoming")
  
  # Verify resolution
  resolved <- DBI::dbGetQuery(con, "
    SELECT resolved, resolution FROM staging.merge_conflicts WHERE id = $1
  ", params = list(conflict$id))
  
  expect_true(resolved$resolved)
  expect_equal(resolved$resolution, "keep_incoming")
})

test_that("approve_merge validates inputs", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  expect_error(approve_merge(con, -1, "admin"), "positive integer")
  expect_error(approve_merge(con, 1, ""), "non-empty string")
  expect_error(approve_merge(con, 99999, "admin"), "not found")
})

test_that("approve_merge rejects request with unresolved conflicts", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Create conflict
  DBI::dbExecute(con, "
    INSERT INTO core.veg 
      (plot_number, species_code, layer_code, cover_percent,
       height_cm, project_id, modified_by)
    VALUES ('PLOT001', 'TSUGHET', 'T1', 30, 1200, 1, 'seeder')
  ")
  
  veg_data <- data.frame(
    plot_number = "PLOT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 50L,
    height_cm = 1500L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  detect_conflicts(con, mr_id)
  
  # Try to approve without resolving
  expect_error(approve_merge(con, mr_id, "admin"), "unresolved conflicts")
})

test_that("approve_merge processes INSERT operations correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  veg_data <- data.frame(
    plot_number = "INSERT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 40L,
    height_cm = 1300L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  # No conflicts for new insert
  conflicts <- detect_conflicts(con, mr_id)
  expect_equal(nrow(conflicts), 0)
  
  # Approve merge
  summary <- approve_merge(con, mr_id, "admin@example.com")
  
  expect_equal(summary$rows_inserted, 1)
  expect_equal(summary$rows_updated, 0)
  expect_equal(summary$rows_deleted, 0)
  expect_true("veg" %in% summary$tables_merged)
  
  # Verify data in core
  core_data <- DBI::dbGetQuery(con, "
    SELECT * FROM core.veg WHERE plot_number = 'INSERT001'
  ")
  
  expect_equal(nrow(core_data), 1)
  expect_equal(core_data$cover_percent, 40)
  expect_equal(core_data$row_version, 1)
  expect_equal(core_data$modified_by, "admin@example.com")
  
  # Verify merge request status
  mr <- DBI::dbGetQuery(con, "
    SELECT status, reviewer FROM staging.merge_requests WHERE id = $1
  ", params = list(mr_id))
  
  expect_equal(mr$status, "merged")
  expect_equal(mr$reviewer, "admin@example.com")
})

test_that("approve_merge processes UPDATE operations correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Insert initial data
  DBI::dbExecute(con, "
    INSERT INTO core.veg 
      (plot_number, species_code, layer_code, cover_percent,
       height_cm, project_id, modified_by)
    VALUES ('UPDATE001', 'TSUGHET', 'T1', 30, 1200, 1, 'initial')
  ")
  
  # Submit update via staging
  DBI::dbExecute(con, "
    INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
    VALUES (1, 'user', 'user@example.com', 'pending_review')
  ")
  mr_id <- DBI::dbGetQuery(con, "SELECT lastval()")[[1]]
  
  DBI::dbExecute(con, "
    INSERT INTO staging.veg 
      (merge_request_id, plot_number, species_code, layer_code,
       cover_percent, height_cm, project_id, change_type)
    VALUES ($1, 'UPDATE001', 'TSUGHET', 'T1', 60, 1800, 1, 'U')
  ", params = list(mr_id))
  
  # No conflicts for valid update
  conflicts <- detect_conflicts(con, mr_id)
  expect_equal(nrow(conflicts), 0)
  
  # Approve merge
  summary <- approve_merge(con, mr_id, "admin@example.com")
  
  expect_equal(summary$rows_inserted, 0)
  expect_equal(summary$rows_updated, 1)
  expect_equal(summary$rows_deleted, 0)
  
  # Verify update in core
  core_data <- DBI::dbGetQuery(con, "
    SELECT * FROM core.veg WHERE plot_number = 'UPDATE001'
  ")
  
  expect_equal(nrow(core_data), 1)
  expect_equal(core_data$cover_percent, 60)
  expect_equal(core_data$height_cm, 1800)
  expect_equal(core_data$row_version, 2)  # Should be incremented
  expect_equal(core_data$modified_by, "admin@example.com")
})

test_that("approve_merge processes DELETE operations correctly", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Insert data to delete
  DBI::dbExecute(con, "
    INSERT INTO core.veg 
      (plot_number, species_code, layer_code, cover_percent,
       height_cm, project_id, modified_by)
    VALUES ('DELETE001', 'TSUGHET', 'T1', 30, 1200, 1, 'initial')
  ")
  
  # Submit delete via staging
  DBI::dbExecute(con, "
    INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
    VALUES (1, 'user', 'user@example.com', 'pending_review')
  ")
  mr_id <- DBI::dbGetQuery(con, "SELECT lastval()")[[1]]
  
  DBI::dbExecute(con, "
    INSERT INTO staging.veg 
      (merge_request_id, plot_number, species_code, layer_code,
       cover_percent, height_cm, project_id, change_type)
    VALUES ($1, 'DELETE001', 'TSUGHET', 'T1', 30, 1200, 1, 'D')
  ", params = list(mr_id))
  
  # Approve merge
  summary <- approve_merge(con, mr_id, "admin@example.com")
  
  expect_equal(summary$rows_inserted, 0)
  expect_equal(summary$rows_updated, 0)
  expect_equal(summary$rows_deleted, 1)
  
  # Verify deletion from core
  core_data <- DBI::dbGetQuery(con, "
    SELECT * FROM core.veg WHERE plot_number = 'DELETE001'
  ")
  
  expect_equal(nrow(core_data), 0)
})

test_that("approve_merge triggers audit logging", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Clear audit log for clean test
  DBI::dbExecute(con, "TRUNCATE audit.logged_actions RESTART IDENTITY")
  
  veg_data <- data.frame(
    plot_number = "AUDIT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 45L,
    height_cm = 1400L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  summary <- approve_merge(con, mr_id, "admin@example.com")
  
  expect_true(summary$audit_entries_created > 0)
  
  # Verify audit log entry
  audit_entries <- DBI::dbGetQuery(con, "
    SELECT * FROM audit.logged_actions 
    WHERE table_name = 'veg'
    ORDER BY action_tstamp DESC
  ")
  
  expect_true(nrow(audit_entries) > 0)
  expect_equal(audit_entries$action[1], "I")
  expect_equal(audit_entries$schema_name[1], "core")
  
  # Verify JSONB structure
  expect_type(audit_entries$new_data[1], "character")
  new_data <- jsonlite::fromJSON(audit_entries$new_data[1])
  expect_equal(new_data$plot_number, "AUDIT001")
})

test_that("approve_merge handles multiple tables in one transaction", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  veg_data <- data.frame(
    plot_number = "MULTI001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 35L,
    height_cm = 1250L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  env_data <- data.frame(
    plot_number = "MULTI001",
    project_id = 1L,
    latitude = 49.5,
    longitude = -119.5,
    elevation_m = 750L,
    survey_date = as.Date("2023-07-20"),
    surveyor_name = "A. Botanist",
    plot_notes = NA_character_,
    stringsAsFactors = FALSE
  )
  
  su_data <- data.frame(
    plot_number = "MULTI001",
    project_id = 1L,
    su_number = 1L,
    bec_zone = "IDF",
    bec_subzone = "dk",
    site_series = "01",
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, 
                         list(veg = list(inserts = veg_data), 
                              env = list(inserts = env_data),
                              su = list(inserts = su_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  summary <- approve_merge(con, mr_id, "admin@example.com")
  
  expect_equal(summary$rows_inserted, 3)
  expect_equal(length(summary$tables_merged), 3)
  expect_true(all(c("veg", "env", "su") %in% 
                  summary$tables_merged))
  
  # Verify all tables have data
  veg_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM core.veg WHERE plot_number = 'MULTI001'
  ")$cnt
  env_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM core.env WHERE plot_number = 'MULTI001'
  ")$cnt
  su_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM core.su WHERE plot_number = 'MULTI001'
  ")$cnt
  
  expect_equal(veg_count, 1)
  expect_equal(env_count, 1)
  expect_equal(su_count, 1)
})

test_that("approve_merge rolls back on error", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  # Create staging data with invalid foreign key reference
  DBI::dbExecute(con, "
    INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
    VALUES (1, 'user', 'user@example.com', 'pending_review')
  ")
  mr_id <- DBI::dbGetQuery(con, "SELECT lastval()")[[1]]
  
  # Insert veg row with invalid cover_percent (violates CHECK constraint)
  DBI::dbExecute(con, "
    INSERT INTO staging.veg 
      (merge_request_id, plot_number, species_code, layer_code,
       cover_percent, height_cm, project_id, change_type)
    VALUES ($1, 'FAIL001', 'TSUGHET', 'T1', 150, 1200, 1, 'I')
  ", params = list(mr_id))
  
  # Merge should fail and rollback due to CHECK constraint violation
  expect_error(approve_merge(con, mr_id, "admin"), "Merge failed")
  
  # Verify merge request status unchanged
  mr <- DBI::dbGetQuery(con, "
    SELECT status FROM staging.merge_requests WHERE id = $1
  ", params = list(mr_id))
  
  expect_equal(mr$status, "pending_review")
  
  # Verify no data in core
  core_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt FROM core.veg WHERE plot_number = 'FAIL001'
  ")$cnt
  
  expect_equal(core_count, 0)
})

test_that("reject_merge validates inputs", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  expect_error(reject_merge(con, -1, "admin", "reason"), "positive integer")
  expect_error(reject_merge(con, 1, "", "reason"), "non-empty string")
  expect_error(reject_merge(con, 1, "admin", ""), "non-empty string")
  expect_error(reject_merge(con, 99999, "admin", "reason"), "not found")
})

test_that("reject_merge marks request as rejected", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_staging_tables(con)
  
  veg_data <- data.frame(
    plot_number = "REJECT001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 25L,
    height_cm = 1100L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  reject_merge(con, mr_id, "admin@example.com", 
               "Insufficient documentation")
  
  # Verify status
  mr <- DBI::dbGetQuery(con, "
    SELECT status, reviewer, review_notes 
    FROM staging.merge_requests 
    WHERE id = $1
  ", params = list(mr_id))
  
  expect_equal(mr$status, "rejected")
  expect_equal(mr$reviewer, "admin@example.com")
  expect_equal(mr$review_notes, "Insufficient documentation")
  
  # Verify staging data remains
  staging_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as cnt 
    FROM staging.veg 
    WHERE merge_request_id = $1
  ", params = list(mr_id))$cnt
  
  expect_equal(staging_count, 1)
})

test_that("reject_merge prevents rejection of non-pending requests", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  clear_core_tables(con)
  clear_staging_tables(con)
  
  veg_data <- data.frame(
    plot_number = "DONE001",
    species_code = "TSUGHET",
    layer_code = "T1",
    cover_percent = 20L,
    height_cm = 1000L,
    cover_code = NA_character_,
    project_id = 1L,
    stringsAsFactors = FALSE
  )
  
  mr_id <- submit_changes(con, list(veg = list(inserts = veg_data)),
                         "user", "user@example.com", 1L)$merge_request_id
  
  # Approve it first
  approve_merge(con, mr_id, "admin@example.com")
  
  # Try to reject already-merged request
  expect_error(reject_merge(con, mr_id, "admin", "too late"),
               "expected 'pending_review'")
})
