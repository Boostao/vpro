test_that("FS882 starts, navigates, and saves a plot in an isolated Sample copy", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("RSQLite")

  root <- test_path("..", "..")
  sample_source <- file.path(root, "inst", "extdata", "projects", "Sample.db")
  if (!file.exists(sample_source)) {
    skip("Bundled Sample.db is unavailable.")
  }

  scratch <- withr::local_tempdir()
  sample_copy <- file.path(scratch, "Sample.db")
  expect_true(file.copy(sample_source, sample_copy))
  config_path <- file.path(scratch, "config.yml")
  vpro::vpro_config_install(config_path)
  config <- vpro::config_init(config_path)
  config("Current", "User", "FS882Test")

  con <- tryCatch(vpro::vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro::vpro_db_disconnect(con))
  context <- vpro::vpro_project_context(con = con, config = config)
  withr::defer(vpro::vpro_project_close(context))
  vpro::vpro_project_attach(context, sample_copy, "Sample")
  vpro::vpro_project_activate(context, "Sample")

  app_dir <- file.path(root, "inst", "app")
  app_env <- new.env(parent = globalenv())
  withr::with_dir(app_dir, sys.source("global.R", envir = app_env))
  # The test accessor is confined to the temporary configuration file.  Stubbing
  # notifications also makes the server runnable without a browser session.
  app_env$app_config_get <- function(section, key, session = NULL) config(section, key)
  app_env$app_config_set <- function(section, key, value, session = NULL) config(section, key, value)
  app_env$toast <- function(message, ...) message
  app_env$show_toast <- function(...) invisible(NULL)

  state <- shiny::reactiveValues(
    CurrProject = "Sample",
    PrefSUTable = "None",
    User = "FS882Test",
    CurrSU = NULL
  )
  original <- vpro::vpro_plot_list(context)
  expect_gte(length(original), 2L)
  first_plot <- original[[1L]]
  second_plot <- original[[2L]]
  old_location <- vpro::vpro_plot_get(context, second_plot)$env$Location[[1L]]
  saved_location <- paste0("FS882 test ", as.integer(Sys.time()))

  shiny::testServer(
    app_env$mod_fs882_6x4_server,
    args = list(state = state, con = con, context = context),
    {
      session$flushReact()
      # Startup loads the first record without requiring a scanner or network service.
      expect_identical(rv$current_plot, first_plot)
      expect_identical(state$CurrSU, first_plot)
      expect_true(!is.null(baseline()))

      session$setInputs(btnNavNext = 1)
      expect_identical(rv$current_plot, second_plot)
      expect_identical(state$CurrSU, second_plot)

      session$setInputs(Location = saved_location)
      expect_true("Location" %in% touched())
      session$setInputs(btnSaveRecord = 1)
      expect_length(dirty_ids(), 0L)
      expect_identical(
        vpro::vpro_plot_get(context, second_plot)$env$Location[[1L]],
        saved_location
      )

      # Exercise one child-create path against the same temporary project copy.
      before <- nrow(vpro::vpro_plot_humus_list(context, second_plot))
      session$setInputs(humus_add = 1)
      expect_identical(child_modal()$kind, "humus")
      session$setInputs(
        child_Horizon = "Test",
        child_UpperDepth = "1",
        child_LowerDepth = "2",
        child_save = 1
      )
      expect_null(child_modal())
      expect_equal(nrow(vpro::vpro_plot_humus_list(context, second_plot)), before + 1L)

      # Changing dropdown dependencies exercises the observers' project guard.
      session$setInputs(optAssignedSuSource = 1, Zone = "CWH", SubZone = "vm")
      expect_identical(project_matches(), TRUE)
    }
  )

  # The FS1333 route embeds FS882 and must pass its project context through.
  received <- new.env(parent = emptyenv())
  fs882_server <- app_env$mod_fs882_6x4_server
  app_env$mod_fs882_6x4_server <- function(id, state, con, context) {
    received$context <- context
    fs882_server(id, state, con, context)
  }
  shiny::testServer(
    app_env$mod_fs1333_server,
    args = list(state = state, con = con, context = context),
    {
      session$flushReact()
    }
  )
  expect_identical(received$context, context)

  # Assert the canonical packaged database was never opened for writing.
  source_db <- DBI::dbConnect(RSQLite::SQLite(), sample_source)
  withr::defer(DBI::dbDisconnect(source_db))
  expect_identical(
    DBI::dbGetQuery(
      source_db,
      "SELECT Location FROM Sample_Env WHERE PlotNumber = ?",
      params = list(second_plot)
    )$Location[[1L]],
    old_location
  )
})
