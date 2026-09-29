test_that("FS1333 startup selection preserves server-side ProjectID choices", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("RSQLite")

  app <- new.env(parent = globalenv())
  app$`%||%` <- function(x, y) if (is.null(x)) y else x
  sys.source(test_path("..", "..", "inst", "app", "modules", "mod_fs1333.R"), envir = app)
  app$app_config_get <- function(section, key, ...) if (key == "ProjectIdSource") "1" else ""
  app$app_config_set <- function(...) invisible(NULL)
  app$app_project_table_sql <- function(con, tb, ...) DBI::dbQuoteIdentifier(con, paste0("Demo_", tb))
  app$mod_fs882_6x4_server <- function(...) invisible(NULL)

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "CREATE TABLE Demo_Metadata (projectid TEXT, projecttitle TEXT)")
  DBI::dbExecute(con, "INSERT INTO Demo_Metadata VALUES ('P1', 'First'), ('P2', 'Second')")
  DBI::dbExecute(con, "CREATE TABLE Demo_Env (plotnumber TEXT, projectid TEXT, plottype TEXT, specieslistcomplete INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Demo_Env VALUES ('1', 'P1', 'Ground', 1)")

  state <- shiny::reactiveValues(CurrProject = "Demo", PrefProject = "Demo", CurrSU = "1")
  registrations <- list()
  messages <- list()
  session <- shiny:::MockShinySession$new()
  session$registerDataObj <- function(name, data, filterFunc) {
    registrations[[length(registrations) + 1L]] <<- list(name = name, data = data)
    "mock-url"
  }
  session$sendInputMessage <- function(inputId, message) {
    messages[[length(messages) + 1L]] <<- list(id = inputId, message = message)
  }

  shiny::testServer(
    app$mod_fs1333_server,
    args = list(state = state, con = con, context = NULL),
    session = session,
    {
      session$flushReact()
    }
  )

  expect_length(registrations, 1L)
  expect_identical(registrations[[1L]]$name, "ProjectID")
  expect_identical(registrations[[1L]]$data$value, c("P1", "P2"))
  expect_true(any(vapply(
    messages,
    function(x) {
      identical(x$id, "ProjectID") &&
        identical(x$message$value, "P1") &&
        is.null(x$message$url)
    },
    logical(1)
  )))
})
