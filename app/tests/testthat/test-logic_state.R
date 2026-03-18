# Tests for global state management

source(here::here("R", "logic_state.R"))

setup_test_metadata <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Metadata (
      ProjectID TEXT PRIMARY KEY,
      ProjectName TEXT
    )
  ")
  DBI::dbExecute(con, "DELETE FROM Metadata")
  DBI::dbExecute(
    con,
    "INSERT INTO Metadata (ProjectID, ProjectName) VALUES (?, ?)",
    list("P-001", "Test Project")
  )
}

test_that("init_sys_state includes VBA globals and aliases", {
  state <- init_sys_state()

  shiny::isolate({
    expect_true(is.null(state$CurrProject))
    expect_true(is.null(state$CurrSU))
    expect_true(is.null(state$CurrHierarchy))
    expect_true(is.null(state$sysCurrProject))
    expect_true(is.null(state$sysCurrSU))
    expect_true(is.list(state$CurrFormLoc))
    expect_equal(state$CancelEvent, 0L)
    expect_equal(state$sysCancelEvent, 0L)
    expect_equal(state$IncludeExisting, 0L)
    expect_equal(state$sysIncludeExisting, 0L)
  })
})

test_that("set_project sets project and metadata with aliases", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_test_metadata(con)

  state <- init_sys_state()
  set_project(state, "P-001", con)

  shiny::isolate({
    expect_equal(state$CurrProject, "P-001")
    expect_equal(state$sysCurrProject, "P-001")
    expect_equal(state$CurrProjectName, "P-001")
    expect_equal(state$ProjectMetadata$ProjectName, "Test Project")
    expect_true(is.null(state$CurrSU))
    expect_true(is.null(state$sysCurrSU))
  })
})

test_that("set_su updates plot number and aliases", {
  state <- init_sys_state()
  set_su(state, "SU-123")

  shiny::isolate({
    expect_equal(state$CurrSU, "SU-123")
    expect_equal(state$sysCurrSU, "SU-123")
    expect_equal(state$PlotNumber, "SU-123")
    expect_equal(state$sysplotnumber, "SU-123")
  })
})

test_that("create_project_table_set clones Sample_* schema", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_Env (PlotNumber TEXT, ProjectID TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Metadata (ProjectID TEXT, ProjectName TEXT)")

  create_project_table_set(con, "Alpha", template_prefix = "Sample")

  expect_true(DBI::dbExistsTable(con, "Alpha_Env"))
  expect_true(DBI::dbExistsTable(con, "Alpha_Metadata"))

  meta <- DBI::dbGetQuery(con, "SELECT ProjectID FROM Alpha_Metadata")
  expect_equal(meta$ProjectID[[1]], "Alpha")
})

test_that("unattach_project_table_set drops non-protected project tables", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Alpha_Env (PlotNumber TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Alpha_SU (PlotNumber TEXT)")

  dropped <- unattach_project_table_set(con, "Alpha")
  expect_equal(sort(tolower(dropped)), sort(c("alpha_env", "alpha_su")))
  expect_false(DBI::dbExistsTable(con, "Alpha_Env"))
  expect_false(DBI::dbExistsTable(con, "Alpha_SU"))
})

test_that("attach_project_table_set copies prefixed tables from source duckdb", {
  src_path <- tempfile(fileext = ".duckdb")
  src <- DBI::dbConnect(duckdb::duckdb(), src_path)
  DBI::dbExecute(src, "CREATE TABLE Alpha_Env (PlotNumber TEXT)")
  DBI::dbExecute(src, "INSERT INTO Alpha_Env VALUES ('P1')")
  DBI::dbExecute(src, "CREATE TABLE Ignore_Env (PlotNumber TEXT)")
  DBI::dbDisconnect(src, shutdown = TRUE)

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  copied <- attach_project_table_set(con, src_path, "Alpha", replace_existing = FALSE)
  expect_true("Alpha_Env" %in% copied)
  expect_true(DBI::dbExistsTable(con, "Alpha_Env"))
  expect_false(DBI::dbExistsTable(con, "Ignore_Env"))

  rows <- DBI::dbGetQuery(con, "SELECT PlotNumber FROM Alpha_Env")
  expect_equal(rows$PlotNumber[[1]], "P1")
})

test_that("create_prefixed_table_from_template clones a single suffixed table", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_SU (PlotNumber TEXT, ProjectID TEXT)")
  create_prefixed_table_from_template(con, "Beta", "_SU", template_prefix = "Sample")

  expect_true(DBI::dbExistsTable(con, "Beta_SU"))
  rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Beta_SU")
  expect_equal(rows$n[[1]], 0)
})

test_that("attach_prefixed_table and unattach_prefixed_table manage a single table", {
  src_path <- tempfile(fileext = ".duckdb")
  src <- DBI::dbConnect(duckdb::duckdb(), src_path)
  DBI::dbExecute(src, "CREATE TABLE Beta_SU (PlotNumber TEXT)")
  DBI::dbExecute(src, "INSERT INTO Beta_SU VALUES ('SU1')")
  DBI::dbDisconnect(src, shutdown = TRUE)

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  attach_prefixed_table(con, src_path, "Beta", "_SU")
  expect_true(DBI::dbExistsTable(con, "Beta_SU"))
  expect_equal(DBI::dbGetQuery(con, "SELECT PlotNumber FROM Beta_SU")$PlotNumber[[1]], "SU1")

  removed <- unattach_prefixed_table(con, "Beta", "_SU")
  expect_equal(tolower(removed), "beta_su")
  expect_false(DBI::dbExistsTable(con, "Beta_SU"))
})
