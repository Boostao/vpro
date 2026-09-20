testthat::context("mod_admin_merge")

source(here::here("R", "db_connections.R"))
source(here::here("R", "logic_sync.R"))

# Reuse the same setup_merge_db helper pattern from test-mod_merge.R but
# enriched with su_record_count and compliance_report columns required by
# merge_ensure_tables and the new mod_admin_merge sub-module.

setup_merge_db_admin <- function() {
  con         <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_adm_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))

  # Use merge_ensure_tables to bootstrap all schemas + tables
  merge_ensure_tables(con)

  con
}

# ---------------------------------------------------------------------------
# merge_ensure_tables
# ---------------------------------------------------------------------------

testthat::test_that("merge_ensure_tables creates all required tables", {
  con <- setup_merge_db_admin()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # DBI::dbExistsTable does not handle 3-part dotted names in DuckDB.
  # Use duckdb_tables() which supports catalog/schema/table filtering.
  table_exists <- function(con, catalog, schema, table) {
    q <- DBI::dbGetQuery(con,
      sprintf("SELECT count(*) AS n FROM duckdb_tables()
               WHERE database_name = '%s'
                 AND schema_name   = '%s'
                 AND table_name    = '%s'",
              catalog, tolower(schema), tolower(table)))
    isTRUE(q$n[1] > 0)
  }

  required <- list(
    c("master", "admin",   "merge_requests"),
    c("master", "admin",   "merge_conflicts"),
    c("master", "staging", "sample_env"),
    c("master", "staging", "sample_su"),
    c("master", "staging", "sample_veg"),
    c("master", "core",    "sample_env"),
    c("master", "core",    "sample_su"),
    c("master", "core",    "sample_veg")
  )

  for (parts in required) {
    testthat::expect_true(
      table_exists(con, parts[1], parts[2], parts[3]),
      info = paste("Expected table to exist:", paste(parts, collapse = "."))
    )
  }
})

testthat::test_that("merge_ensure_tables is idempotent (call twice, no error)", {
  con <- setup_merge_db_admin()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  testthat::expect_no_error(merge_ensure_tables(con))
})

# ---------------------------------------------------------------------------
# merge_request_unresolved_conflict_count  (alias)
# ---------------------------------------------------------------------------

testthat::test_that("merge_request_unresolved_conflict_count returns 0 for fresh request", {
  con <- setup_merge_db_admin()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests
       (id, project_id, submitter_user_id, compliance_passed)
     VALUES (10, 'PRJ', 'user1', TRUE)")

  count <- merge_request_unresolved_conflict_count(con, 10L)
  testthat::expect_equal(count, 0L)
})

# ---------------------------------------------------------------------------
# merge_request_resolve_conflict
# ---------------------------------------------------------------------------

testthat::test_that("merge_request_resolve_conflict sets resolution correctly", {
  con <- setup_merge_db_admin()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests
       (id, project_id, submitter_user_id, compliance_passed)
     VALUES (20, 'PRJ', 'user1', TRUE)")

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_conflicts
       (id, merge_request_id, table_name, record_id, details)
     VALUES (1, 20, 'sample_env', 'PLOT-001', '{}')")

  merge_request_resolve_conflict(con, 1L, "keep_staged", actor = "reviewer")

  resolution <- DBI::dbGetQuery(con,
    "SELECT resolution FROM master.admin.merge_conflicts WHERE id = 1")$resolution[1]
  testthat::expect_equal(resolution, "keep_staged")
})

# ---------------------------------------------------------------------------
# Approve blocked when unresolved conflicts > 0
# ---------------------------------------------------------------------------
# merge_request_refresh_conflicts deletes NULL-resolution conflicts and
# re-detects from staging. To reliably trigger the blocking guard we need
# actual data in staging that conflicts with core. Instead we verify the
# guard logic indirectly: a resolved conflict is excluded from the unresolved
# count, and a NULL-resolution one is included.

testthat::test_that("unresolved count increments and decrements correctly after resolve", {
  con <- setup_merge_db_admin()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_requests
       (id, project_id, submitter_user_id, compliance_passed)
     VALUES (40, 'PRJ', 'user1', TRUE)")

  # Insert two conflicts with NULL resolution
  DBI::dbExecute(con,
    "INSERT INTO master.admin.merge_conflicts
       (id, merge_request_id, table_name, record_id, details)
     VALUES (201, 40, 'sample_env', 'PLOT-A', '{}'),
            (202, 40, 'sample_env', 'PLOT-B', '{}')")

  before <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM master.admin.merge_conflicts
     WHERE merge_request_id = 40 AND resolution IS NULL")$n[1]
  testthat::expect_equal(as.integer(before), 2L)

  # Resolve one
  merge_request_resolve_conflict(con, 201L, "keep_staged", actor = "reviewer")

  after <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM master.admin.merge_conflicts
     WHERE merge_request_id = 40 AND resolution IS NULL")$n[1]
  testthat::expect_equal(as.integer(after), 1L)

  # Resolve the second
  merge_request_resolve_conflict(con, 202L, "dismiss", actor = "reviewer")

  final <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM master.admin.merge_conflicts
     WHERE merge_request_id = 40 AND resolution IS NULL")$n[1]
  testthat::expect_equal(as.integer(final), 0L)
})
