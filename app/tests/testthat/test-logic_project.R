# Tests for logic_project.R

source(here::here("R", "logic_state.R"))
source(here::here("R", "db_connections.R"))
source(here::here("R", "logic_project.R"))

# Helper: create an in-memory DuckDB with the main table set
make_main_con <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  DBI::dbExecute(con, "CREATE TABLE Metadata (projectid TEXT PRIMARY KEY, projecttitle TEXT, projectname TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Env (id INTEGER, plotnumber TEXT, projectid TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Veg (id INTEGER, plotnumber TEXT, projectid TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU  (id INTEGER, plotnumber TEXT, projectid TEXT)")
  con
}

# Helper: write a minimal project .duckdb file
make_project_file <- function(project_id, plots = c("P1", "P2")) {
  path <- tempfile(fileext = ".duckdb")
  src  <- DBI::dbConnect(duckdb::duckdb(), path)
  on.exit(DBI::dbDisconnect(src, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(src, "CREATE TABLE Metadata (projectid TEXT PRIMARY KEY, projecttitle TEXT)")
  DBI::dbExecute(src, "CREATE TABLE Env (id INTEGER, plotnumber TEXT, projectid TEXT)")
  DBI::dbExecute(src, "CREATE TABLE Veg (id INTEGER, plotnumber TEXT, projectid TEXT)")
  DBI::dbExecute(src, "INSERT INTO Metadata VALUES (?, ?)", list(project_id, paste0(project_id, " Title")))
  for (i in seq_along(plots)) {
    DBI::dbExecute(src, "INSERT INTO Env VALUES (?, ?, ?)", list(i, plots[[i]], project_id))
  }
  path
}

# ============================================================

test_that("list_open_projects returns empty when Metadata missing", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_equal(list_open_projects(con), character(0))
})

test_that("list_open_projects returns distinct projectids", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO Metadata (projectid) VALUES ('A'), ('B')")
  out <- list_open_projects(con)
  expect_setequal(out, c("A", "B"))
})

test_that("project_exists returns FALSE when not present", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_false(project_exists(con, "X"))
})

test_that("project_exists returns TRUE after new_project", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  new_project(con, "BCGov2025", "BCGov 2025 Alpine")
  expect_true(project_exists(con, "BCGov2025"))
})

test_that("new_project errors on duplicate", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  new_project(con, "Dup", "Duplicate Project")
  expect_error(new_project(con, "Dup", "Duplicate Again"), "already exists")
})

test_that("new_project errors on blank id or title", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_error(new_project(con, "", "Title"), "required")
  expect_error(new_project(con, "MyID", ""), "required")
})

test_that("open_project loads rows into main tables", {
  path <- make_project_file("AlpineBC", plots = c("AP1", "AP2"))

  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  pid <- open_project(con, path)
  expect_equal(pid, "AlpineBC")

  env_rows <- DBI::dbGetQuery(con, "SELECT plotnumber FROM Env WHERE projectid = 'AlpineBC' ORDER BY plotnumber")
  expect_equal(env_rows$plotnumber, c("AP1", "AP2"))

  meta_rows <- DBI::dbGetQuery(con, "SELECT projectid FROM Metadata WHERE projectid = 'AlpineBC'")
  expect_equal(meta_rows$projectid[[1]], "AlpineBC")
})

test_that("open_project errors on missing file", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  expect_error(open_project(con, "/nonexistent/foo.duckdb"), "not found")
})

test_that("close_project removes rows from all tables", {
  path <- make_project_file("CloseMe", plots = c("CP1"))
  con  <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  open_project(con, path)
  n_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Env WHERE projectid = 'CloseMe'")$n[[1]]
  expect_equal(n_before, 1L)

  close_project(con, "CloseMe")
  n_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Env WHERE projectid = 'CloseMe'")$n[[1]]
  expect_equal(n_after, 0L)
})

test_that("save_project writes rows to file", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO Metadata (projectid, projecttitle) VALUES ('Saved', 'Saved Project')")
  DBI::dbExecute(con, "INSERT INTO Env (id, plotnumber, projectid) VALUES (1, 'SP1', 'Saved')")

  dest <- tempfile(fileext = ".duckdb")
  save_project(con, "Saved", dest)

  verify <- DBI::dbConnect(duckdb::duckdb(), dest)
  on.exit(DBI::dbDisconnect(verify, shutdown = TRUE), add = TRUE)
  rows <- DBI::dbGetQuery(verify, "SELECT plotnumber FROM Env WHERE projectid = 'Saved'")
  expect_equal(rows$plotnumber[[1]], "SP1")
})

test_that("project_capture_baseline writes baseline metadata and file", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO Metadata (projectid, projecttitle) VALUES ('BaseProj', 'Baseline Project')")
  DBI::dbExecute(con, "INSERT INTO Env (id, plotnumber, projectid) VALUES (1, 'BP1', 'BaseProj')")

  baseline <- project_capture_baseline(con, "BaseProj", source_kind = "test")

  expect_false(is.null(baseline))
  expect_true(file.exists(baseline$baseline_path[[1]]))
  expect_equal(baseline$project_id[[1]], "BaseProj")
  expect_equal(baseline$source_kind[[1]], "test")
})

test_that("project_read_baseline_rows returns baseline table rows", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO Metadata (projectid, projecttitle) VALUES ('ReadBase', 'Read Baseline')")
  DBI::dbExecute(con, "INSERT INTO Env (id, plotnumber, projectid) VALUES (1, 'RB1', 'ReadBase')")
  project_capture_baseline(con, "ReadBase", source_kind = "test")

  rows <- project_read_baseline_rows(con, "ReadBase", "Env", "plotnumber", "RB1")
  expect_equal(rows$plotnumber[[1]], "RB1")
  expect_equal(rows$projectid[[1]], "ReadBase")
})

test_that("save_project includes via-env SU rows without projectid column", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "DROP TABLE SU")
  DBI::dbExecute(con, "CREATE TABLE SU (plotnumber TEXT, siteunit TEXT)")
  DBI::dbExecute(con, "INSERT INTO Metadata (projectid, projecttitle) VALUES ('Scoped', 'Scoped Project')")
  DBI::dbExecute(con, "INSERT INTO Env (id, plotnumber, projectid) VALUES (1, 'SC1', 'Scoped')")
  DBI::dbExecute(con, "INSERT INTO SU (plotnumber, siteunit) VALUES ('SC1', 'BWBSwk 1/06')")

  dest <- tempfile(fileext = ".duckdb")
  save_project(con, "Scoped", dest)

  verify <- DBI::dbConnect(duckdb::duckdb(), dest, read_only = TRUE)
  on.exit(DBI::dbDisconnect(verify, shutdown = TRUE), add = TRUE)
  rows <- DBI::dbGetQuery(verify, "SELECT plotnumber, siteunit FROM SU")
  expect_equal(rows$plotnumber[[1]], "SC1")
  expect_equal(rows$siteunit[[1]], "BWBSwk 1/06")
})

test_that("project baseline captures via-env SU rows", {
  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "DROP TABLE SU")
  DBI::dbExecute(con, "CREATE TABLE SU (plotnumber TEXT, siteunit TEXT)")
  DBI::dbExecute(con, "INSERT INTO Metadata (projectid, projecttitle) VALUES ('BaseSU', 'Baseline SU Project')")
  DBI::dbExecute(con, "INSERT INTO Env (id, plotnumber, projectid) VALUES (1, 'BS1', 'BaseSU')")
  DBI::dbExecute(con, "INSERT INTO SU (plotnumber, siteunit) VALUES ('BS1', 'BWBSwk 1/06')")

  project_capture_baseline(con, "BaseSU", source_kind = "test", force = TRUE)
  rows <- project_read_baseline_rows(con, "BaseSU", "SU", "plotnumber", "BS1")

  expect_equal(rows$plotnumber[[1]], "BS1")
  expect_equal(rows$siteunit[[1]], "BWBSwk 1/06")
})

test_that("multiple projects coexist in main tables", {
  path1 <- make_project_file("ProjA", plots = c("A1", "A2"))
  path2 <- make_project_file("ProjB", plots = c("B1"))

  con <- make_main_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  open_project(con, path1)
  open_project(con, path2)

  all_pids <- sort(list_open_projects(con))
  expect_setequal(all_pids, c("ProjA", "ProjB"))

  a_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Env WHERE projectid = 'ProjA'")$n[[1]]
  b_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Env WHERE projectid = 'ProjB'")$n[[1]]
  expect_equal(a_rows, 2L)
  expect_equal(b_rows, 1L)
})
