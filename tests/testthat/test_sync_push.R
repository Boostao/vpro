# =============================================================================
# tests/testthat/test_sync_push.R
# Four scenario tests for the push-only sync engine:
#   1. Push creates MR + staging rows
#   2. Admin approve merges to core
#   3. Conflict detection (rowVersion bump)
#   4. Conflict resolution: keep_staged vs keep_core
# =============================================================================

library(DBI)
library(duckdb)
library(testthat)
library(jsonlite)

source(here::here("R", "logic_sync.R"))
# Re-use shared helpers from test-logic_sync.R (loaded via setup.R / testthat)
source(here::here("tests", "testthat", "test-logic_sync.R"))

# ── helper: fully wired test environment ─────────────────────────────────────
.make_env <- function() {
  m  <- .make_master()
  lc <- .make_local()
  .attach_master(lc, m$path)

  # Seed one dirty Env row in local
  DBI::dbExecute(lc, "
    INSERT INTO Env (plotnumber, fieldnumber, projectid, latitude,
                     longitude, elevation, local_modified_utc)
    VALUES ('P001', 'F001', 'PROJ1', 49.1, -121.5, 800, now())
  ")

  list(local = lc, master_con = m$con, master_path = m$path)
}

.teardown_env <- function(e) {
  try(DBI::dbDisconnect(e$local),      silent = TRUE)
  try(DBI::dbDisconnect(e$master_con), silent = TRUE)
  try(unlink(e$master_path),           silent = TRUE)
}


# =============================================================================
# Test 1: Push creates MR + staging rows
# =============================================================================

test_that("sync_push creates a pending_review MR and inserts staging rows", {
  e <- .make_env()
  on.exit(.teardown_env(e), add = TRUE)

  result <- sync_push(e$local, project_id = "PROJ1", submitter = "test@example.com")

  # MR created
  expect_true(!is.null(result$merge_request_id))
  mr_id <- result$merge_request_id

  # MR status = pending_review
  mr <- DBI::dbGetQuery(
    e$local,
    "SELECT status, record_counts FROM master.admin.merge_requests WHERE id = ?",
    list(as.integer(mr_id))
  )
  expect_equal(nrow(mr), 1L)
  expect_equal(mr$status[1], "pending_review")

  # Staging env has 1 row for this MR
  stg <- DBI::dbGetQuery(
    e$local,
    "SELECT * FROM master.staging.env WHERE merge_request_id = ?",
    list(as.integer(mr_id))
  )
  expect_equal(nrow(stg), 1L)
  expect_equal(stg$plotnumber[1], "P001")

  # record_counts JSON includes env > 0
  rc <- tryCatch(jsonlite::fromJSON(mr$record_counts[1]), error = function(e) list())
  expect_true(isTRUE((rc$env %||% 0L) >= 1L))

  # result$counts$env == 1
  expect_equal(result$counts[["env"]], 1L)
})


# =============================================================================
# Test 2: Admin approve merges staging to core
# =============================================================================

test_that("merge_approve_request moves staging rows to core and sets status merged", {
  e <- .make_env()
  on.exit(.teardown_env(e), add = TRUE)

  result <- sync_push(e$local, project_id = "PROJ1", submitter = "test@example.com")
  mr_id  <- result$merge_request_id

  # Core.env is empty before approval
  pre <- DBI::dbGetQuery(e$local, "SELECT COUNT(*) AS n FROM master.core.env")
  expect_equal(pre$n[1], 0L)

  merge_approve_request(e$local, mr_id, reviewer = "admin@example.com",
                        review_notes = "LGTM")

  # Core.env now has the row
  post <- DBI::dbGetQuery(e$local, "SELECT * FROM master.core.env")
  expect_equal(nrow(post), 1L)
  expect_equal(post$plotnumber[1], "P001")

  # MR status is merged
  mr <- DBI::dbGetQuery(
    e$local,
    "SELECT status FROM master.admin.merge_requests WHERE id = ?",
    list(as.integer(mr_id))
  )
  expect_equal(mr$status[1], "merged")

  # Staging rows cleaned up
  stg <- DBI::dbGetQuery(
    e$local,
    "SELECT COUNT(*) AS n FROM master.staging.env WHERE merge_request_id = ?",
    list(as.integer(mr_id))
  )
  expect_equal(stg$n[1], 0L)
})


# =============================================================================
# Test 3: Conflict detection when rowVersion bumped in core
# =============================================================================

test_that("merge_request_refresh_conflicts detects rowVersion conflicts", {
  e <- .make_env()
  on.exit(.teardown_env(e), add = TRUE)

  # First push
  result <- sync_push(e$local, project_id = "PROJ1", submitter = "test@example.com")
  mr_id  <- result$merge_request_id

  # Manually insert a core.env row with baseRowVersion lower than staged
  # (simulates: someone else updated the row after this user's push)
  DBI::dbExecute(e$local, "
    INSERT INTO master.core.env (plotnumber, projectid, \"rowVersion\")
    VALUES ('P001', 'PROJ1', 5)
  ")

  # Staged row has baseRowVersion = NULL (new row), so no conflict from rowVersion
  # To trigger conflict: set baseRowVersion on staging row to 1, then bump core
  DBI::dbExecute(
    e$local,
    "UPDATE master.staging.env SET \"baseRowVersion\" = 1 WHERE merge_request_id = ?",
    list(as.integer(mr_id))
  )
  # Core rowVersion = 5 > staged baseRowVersion = 1 => conflict
  # Note: core.env already has rowVersion=5 from INSERT above

  merge_request_refresh_conflicts(e$local, mr_id)

  n <- merge_request_unresolved_count(e$local, mr_id)
  expect_equal(n, 1L)

  conflicts <- merge_request_get_conflicts(e$local, mr_id)
  expect_equal(nrow(conflicts), 1L)
  expect_equal(conflicts$table_name[1], "env")
  expect_equal(conflicts$record_id[1], "P001")
})


# =============================================================================
# Test 4a: Conflict resolution — keep_staged applies the row
# =============================================================================

test_that("keep_staged resolution allows row to be applied to core", {
  e <- .make_env()
  on.exit(.teardown_env(e), add = TRUE)

  result <- sync_push(e$local, project_id = "PROJ1", submitter = "test@example.com")
  mr_id  <- result$merge_request_id

  # Seed core + force conflict (same as Test 3)
  DBI::dbExecute(e$local, "
    INSERT INTO master.core.env (plotnumber, projectid, \"rowVersion\")
    VALUES ('P001', 'PROJ1', 5)
  ")
  DBI::dbExecute(
    e$local,
    "UPDATE master.staging.env SET \"baseRowVersion\" = 1 WHERE merge_request_id = ?",
    list(as.integer(mr_id))
  )
  merge_request_refresh_conflicts(e$local, mr_id)

  conflict_id <- merge_request_get_conflicts(e$local, mr_id)$id[1]
  merge_request_resolve_conflict(e$local, conflict_id, "keep_staged",
                                 actor = "admin@example.com")

  # Now approve — no unresolved conflicts remain
  expect_silent(
    merge_approve_request(e$local, mr_id, reviewer = "admin@example.com")
  )

  # Core should have the staged row (updated)
  core_row <- DBI::dbGetQuery(e$local, "SELECT * FROM master.core.env WHERE plotnumber = 'P001'")
  expect_equal(nrow(core_row), 1L)
})


# =============================================================================
# Test 4b: Conflict resolution — keep_core skips the staged row
# =============================================================================

test_that("keep_core resolution excludes staged row from approval", {
  e <- .make_env()
  on.exit(.teardown_env(e), add = TRUE)

  result <- sync_push(e$local, project_id = "PROJ1", submitter = "test@example.com")
  mr_id  <- result$merge_request_id

  # Seed core with a different elevation
  DBI::dbExecute(e$local, "
    INSERT INTO master.core.env (plotnumber, projectid, elevation, \"rowVersion\")
    VALUES ('P001', 'PROJ1', 999, 5)
  ")
  DBI::dbExecute(
    e$local,
    "UPDATE master.staging.env SET \"baseRowVersion\" = 1 WHERE merge_request_id = ?",
    list(as.integer(mr_id))
  )
  merge_request_refresh_conflicts(e$local, mr_id)

  conflict_id <- merge_request_get_conflicts(e$local, mr_id)$id[1]
  merge_request_resolve_conflict(e$local, conflict_id, "keep_core",
                                 actor = "admin@example.com")

  expect_silent(
    merge_approve_request(e$local, mr_id, reviewer = "admin@example.com")
  )

  # Core row should still have elevation = 999 (staged row was excluded)
  core_row <- DBI::dbGetQuery(e$local, "SELECT elevation FROM master.core.env WHERE plotnumber = 'P001'")
  expect_equal(nrow(core_row), 1L)
  expect_equal(core_row$elevation[1], 999L)
})
