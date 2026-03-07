testthat::context("mod_admin_projects")

source(here::here("R", "logic_state.R"))
source(here::here("R", "logic_audit.R"))
source(here::here("R", "logic_auth.R"))
source(here::here("R", "db_connections.R"))

setup_projects_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  DBI::dbExecute(con, "
    CREATE TABLE USysProjectMetadata (
      projectid          TEXT PRIMARY KEY,
      projecttitle       TEXT,
      coordinatingagency TEXT,
      startdate          TEXT,
      enddate            TEXT,
      notes              TEXT
    )
  ")
  con
}

testthat::test_that("insert new project - row exists", {
  con <- setup_projects_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes)
     VALUES (?, ?, ?, ?, ?, ?)",
    list("PROJ-001", "Test Project", "BC Gov", "2025-01-01", "2026-12-31", "Notes"))

  rows <- DBI::dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = 'PROJ-001'")
  testthat::expect_equal(nrow(rows), 1)
  testthat::expect_equal(rows$projecttitle[1], "Test Project")
})

testthat::test_that("update project title - reflected in query", {
  con <- setup_projects_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes)
     VALUES ('P2', 'Original Title', 'Org', '', '', '')")

  DBI::dbExecute(con,
    "UPDATE USysProjectMetadata SET projecttitle = ? WHERE projectid = ?",
    list("Updated Title", "P2"))

  title <- DBI::dbGetQuery(con, "SELECT projecttitle FROM USysProjectMetadata WHERE projectid = 'P2'")$projecttitle[1]
  testthat::expect_equal(title, "Updated Title")
})

testthat::test_that("delete project - row gone", {
  con <- setup_projects_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes)
     VALUES ('P3', 'To Delete', '', '', '', '')")

  before <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM USysProjectMetadata WHERE projectid = 'P3'")$n[1]
  testthat::expect_equal(before, 1L)

  DBI::dbExecute(con, "DELETE FROM USysProjectMetadata WHERE projectid = ?", list("P3"))

  after <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM USysProjectMetadata WHERE projectid = 'P3'")$n[1]
  testthat::expect_equal(after, 0L)
})

testthat::test_that("duplicate project ID - error handled gracefully", {
  con <- setup_projects_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes)
     VALUES ('DUP', 'First', '', '', '', '')")

  testthat::expect_error(
    DBI::dbExecute(con,
      "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes)
       VALUES ('DUP', 'Second', '', '', '', '')"),
    regexp = NULL
  )

  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM USysProjectMetadata WHERE projectid = 'DUP'")$n[1]
  testthat::expect_equal(count, 1L)
})
