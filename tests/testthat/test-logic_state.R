# Tests for global state management

source(here::here("R", "logic_state.R"))

setup_test_metadata <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Sample_Metadata (
      ProjectID TEXT PRIMARY KEY,
      ProjectName TEXT
    )
  ")
  DBI::dbExecute(con, "DELETE FROM Sample_Metadata")
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Metadata (ProjectID, ProjectName) VALUES (?, ?)",
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
