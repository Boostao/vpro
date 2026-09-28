test_that("FS882 and sidebar coordinate project switches without losing drafts", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("RSQLite")

  root <- test_path("..", "..")
  source_db <- file.path(root, "inst", "extdata", "projects", "Sample.db")
  if (!file.exists(source_db)) skip("Bundled Sample.db is unavailable.")
  scratch <- withr::local_tempdir()
  withr::local_options(vpro.data_dir = file.path(scratch, "data"),
                       vpro.config_dir = file.path(scratch, "config"))
  sample_copy <- file.path(scratch, "Sample.db")
  expect_true(file.copy(source_db, sample_copy))
  field_path <- vpro::vpro_db_path("Field", "projects")
  dir.create(dirname(field_path), recursive = TRUE)
  vpro::vpro_project_create(field_path, "Field", "SwitchTest")
  import_path <- file.path(scratch, "Imported.db")
  vpro::vpro_project_create(import_path, "Imported", "SwitchTest")
  config_path <- file.path(scratch, "config.yml")
  vpro::vpro_config_install(config_path)
  config <- vpro::config_init(config_path)
  config("Current", "User", "SwitchTest")
  con <- tryCatch(vpro::vpro_db_connect(), error = identity)
  if (inherits(con, "error")) skip(conditionMessage(con))
  withr::defer(vpro::vpro_db_disconnect(con))
  context <- vpro::vpro_project_context(con = con, config = config)
  withr::defer(vpro::vpro_project_close(context))
  vpro::vpro_db_attach(con, file.path(root, "inst", "extdata", "VLists.db"))
  vpro::vpro_project_attach(context, sample_copy, "Sample")
  vpro::vpro_project_attach(context, field_path, "Field")
  vpro::vpro_project_activate(context, "Sample")

  app_env <- new.env(parent = globalenv())
  withr::with_dir(file.path(root, "inst", "app"), sys.source("global.R", envir = app_env))
  app_env$app_config_get <- function(section, key, session = NULL) config(section, key)
  app_env$app_config_set <- function(section, key, value, session = NULL) config(section, key, value)
  messages <- new.env(parent = emptyenv())
  messages$modal <- NULL
  messages$notifications <- character()
  messages$toasts <- character()
  app_env$showModal <- function(ui, ...) { messages$modal <- as.character(ui); invisible(NULL) }
  app_env$removeModal <- function(...) { messages$modal <- NULL; invisible(NULL) }
  app_env$showNotification <- function(ui, ...) {
    messages$notifications <- c(messages$notifications, as.character(ui))
    invisible(NULL)
  }
  app_env$toast <- function(message, ...) message
  app_env$show_toast <- function(message, ...) {
    messages$toasts <- c(messages$toasts, as.character(message))
    invisible(NULL)
  }
  state <- shiny::reactiveValues(CurrProject = "Sample", PrefProject = "Sample",
                                 PrefSUTable = "None", User = "SwitchTest", CurrSU = NULL)
  original <- vpro::vpro_plot_list(context)
  expect_gt(length(original), 0L)
  first <- original[[1L]]
  initial <- vpro::vpro_plot_get(context, first)
  original_location <- initial$env$Location[[1L]]
  original_bec <- initial$admin$BECSiteUnit[[1L]]
  different_location <- function(tag) paste0("Switch test ", tag)
  server <- function(input, output, session) {
    editor <- app_env$mod_fs882_6x4_server("fs882", state, con, context)
    app_env$mod_sidebar_server("sidebar", context, state, "SwitchTest", fs882 = editor)
  }

  shiny::testServer(server, {
    session$flushReact()
    expect_identical(context$active$project, "Sample")
    expect_identical(state$CurrSU, first)
    expect_false(editor$status()$dirty)

    # A clean picker change activates Field and loads its empty recordset.
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    expect_identical(context$active$project, "Field")
    expect_identical(state$CurrProject, "Field")
    expect_identical(state$PrefProject, "Field")
    expect_null(state$CurrSU)
    expect_false(editor$status()$dirty)
    expect_null(messages$modal)
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(context$active$project, "Sample")
    expect_identical(state$CurrSU, first)

    # An open child editor blocks a picker request. testServer does not emit the
    # Bootstrap modal lifecycle event, so explicitly mark it shown; the child
    # server state remains the authority for the switch guard.
    session$setInputs(`fs882-btnAddSpp` = 1, fs882_modal_shown = TRUE)
    session$flushReact()
    expect_true(editor$status()$blocked)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    expect_identical(context$active$project, "Sample")
    expect_identical(state$CurrProject, "Sample")
    expect_identical(state$PrefProject, "Sample")
    expect_true(any(grepl("Close the open dialog", messages$notifications)))
    session$setInputs(`fs882-child_cancel` = 1)
    session$flushReact()
    expect_false(editor$status()$blocked)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    expect_identical(context$active$project, "Field")
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(context$active$project, "Sample")

    # Stay keeps both the active project and the unsaved draft.
    session$setInputs(`fs882-Location` = different_location("stay"))
    expect_true(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    expect_match(messages$modal, "Unsaved changes")
    expect_identical(context$active$project, "Sample")
    session$setInputs(`sidebar-switchStay` = 1)
    expect_null(messages$modal)
    expect_true(editor$status()$dirty)
    expect_identical(context$active$project, "Sample")
    expect_identical(vpro::vpro_plot_get(context, first)$env$Location[[1L]], original_location)

    # Discard switches, but does not persist the draft to the old project.
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchDiscard` = 1)
    expect_identical(context$active$project, "Field")
    expect_null(state$CurrSU)
    expect_false(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(vpro::vpro_plot_get(context, first)$env$Location[[1L]], original_location)

    # Save writes to Sample before activation of Field; returning reloads the saved plot.
    saved <- different_location("saved")
    session$setInputs(`fs882-Location` = saved)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchSave` = 1)
    expect_identical(context$active$project, "Field")
    expect_false(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(vpro::vpro_plot_get(context, first)$env$Location[[1L]], saved)
    expect_identical(state$CurrSU, first)

    # An invalid numeric draft cannot be saved or switched away from.
    session$setInputs(`fs882-Elevation` = "not a number")
    expect_true(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchSave` = 2)
    expect_identical(context$active$project, "Sample")
    expect_true(editor$status()$dirty)
    expect_match(messages$modal, "Unsaved changes")
    expect_true(any(grepl("Invalid numeric", messages$toasts)))
    session$setInputs(`sidebar-switchDiscard` = 2)
    expect_identical(context$active$project, "Field")
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")

    # Protected Admin updates require authorization; failed Save retains the draft.
    replacement_bec <- if (identical(original_bec, "ZZZ")) "YYY" else "ZZZ"
    session$setInputs(`fs882-BECSiteUnit` = replacement_bec)
    expect_true(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchSave` = 3)
    expect_identical(context$active$project, "Sample")
    expect_true(editor$status()$dirty)
    expect_match(messages$modal, "Unsaved changes")
    expect_true(any(grepl("protected VPRO Admin field", messages$toasts)))
    expect_identical(vpro::vpro_plot_get(context, first)$admin$BECSiteUnit[[1L]], original_bec)
    session$setInputs(`sidebar-switchStay` = 2)
    session$setInputs(`fs882-btnDiscardRecord` = 1)
    expect_false(editor$status()$dirty)

    # Other drafts use the same project-switch preflight.  The detail editor
    # requires its dynamically rendered controls to report their blank baseline.
    set_other_inputs <- function(data_name = "") {
      session$setInputs(
        `fs882-other_DataName` = data_name,
        `fs882-other_DataItem` = "",
        `fs882-other_UserItem1` = "",
        `fs882-other_UserItem2` = "",
        `fs882-other_UserItem3` = "",
        `fs882-other_UserFlag1` = FALSE,
        `fs882-other_UserFlag2` = FALSE,
        `fs882-other_UserFlag3` = FALSE
      )
      session$flushReact()
    }
    other_before <- nrow(vpro::vpro_plot_other_list(context, first))
    session$setInputs(`fs882-btnOtherNew` = 1)
    session$flushReact()
    set_other_inputs()
    set_other_inputs("stay other")
    expect_true(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    expect_match(messages$modal, "Unsaved changes")
    session$setInputs(`sidebar-switchStay` = 3)
    expect_null(messages$modal)
    expect_true(editor$status()$dirty)
    expect_identical(context$active$project, "Sample")

    # Discarding an Other draft switches without creating its child row.
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchDiscard` = 3)
    expect_identical(context$active$project, "Field")
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(nrow(vpro::vpro_plot_other_list(context, first)), other_before)

    # Saving an Other draft writes it before the switch, using its own CRUD API.
    session$setInputs(`fs882-btnOtherNew` = 2)
    session$flushReact()
    set_other_inputs()
    set_other_inputs("saved other")
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchSave` = 4)
    expect_identical(context$active$project, "Field")
    expect_false(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    other_after <- vpro::vpro_plot_other_list(context, first)
    expect_identical(nrow(other_after), other_before + 1L)
    expect_true("saved other" %in% other_after$DataName)

    # Dirty New/Open requests do not create or copy files until their preflight
    # is confirmed. Staying leaves the current draft and project untouched.
    session$setInputs(`fs882-Location` = different_location("new preflight"))
    blocked_new <- vpro::vpro_db_path("BlockedNew", "projects")
    expect_false(file.exists(blocked_new))
    session$setInputs(`sidebar-btnNewProject` = 1)
    expect_match(messages$modal, "New project")
    session$setInputs(`sidebar-newProjectName` = "BlockedNew", `sidebar-confirmNew` = 1)
    expect_match(messages$modal, "Unsaved changes")
    expect_false(file.exists(blocked_new))
    session$setInputs(`sidebar-switchStay` = 4)
    expect_null(messages$modal)
    expect_true(editor$status()$dirty)
    expect_identical(context$active$project, "Sample")

    blocked_open <- vpro::vpro_db_path("Imported", "projects")
    expect_false(file.exists(blocked_open))
    session$setInputs(`sidebar-btnOpenProject` = 1)
    expect_match(messages$modal, "Open a VPRO project")
    session$setInputs(`sidebar-projectFile` = list(datapath = import_path, name = "Imported.db"))
    session$setInputs(`sidebar-projectName` = "Imported", `sidebar-confirmOpen` = 1)
    expect_match(messages$modal, "Unsaved changes")
    expect_false(file.exists(blocked_open))
    session$setInputs(`sidebar-switchStay` = 5)
    expect_null(messages$modal)
    expect_true(editor$status()$dirty)
    # Sidebar discard clears both plot and child-editor drafts before mutation.
    session$setInputs(`sidebar-cmbCurrProject` = "Field")
    session$setInputs(`sidebar-switchDiscard` = 4)
    expect_identical(context$active$project, "Field")
    expect_false(editor$status()$dirty)
    session$setInputs(`sidebar-cmbCurrProject` = "Sample")
    expect_identical(context$active$project, "Sample")
    expect_false(editor$status()$dirty)

    # Cancelling either file-operation modal has no side effects.
    session$setInputs(`sidebar-btnNewProject` = 2)
    expect_match(messages$modal, "New project")
    session$setInputs(`sidebar-cancelProjectDialog` = 1)
    expect_null(messages$modal)
    expect_identical(context$active$project, "Sample")
    session$setInputs(`sidebar-btnOpenProject` = 2)
    expect_match(messages$modal, "Open a VPRO project")
    session$setInputs(`sidebar-cancelProjectDialog` = 2)
    expect_null(messages$modal)
    expect_identical(context$active$project, "Sample")

    # Clean New preflight creates and activates a distinct project in temp storage.
    session$setInputs(`sidebar-btnNewProject` = 3)
    expect_match(messages$modal, "New project")
    session$setInputs(`sidebar-newProjectName` = "NewField", `sidebar-confirmNew` = 2)
    expect_identical(context$active$project, "NewField")
    expect_identical(state$CurrProject, "NewField")
    expect_true(file.exists(vpro::vpro_db_path("NewField", "projects")))
    expect_null(messages$modal)

    # Clean Open preflight copies an uploaded VP08 family to managed temp storage.
    session$setInputs(`sidebar-btnOpenProject` = 3)
    expect_match(messages$modal, "Open a VPRO project")
    session$setInputs(`sidebar-projectFile` = list(datapath = import_path, name = "Imported.db"))
    session$setInputs(`sidebar-projectName` = "Imported", `sidebar-confirmOpen` = 2)
    expect_identical(context$active$project, "Imported")
    expect_identical(state$CurrProject, "Imported")
    expect_true(file.exists(vpro::vpro_db_path("Imported", "projects")))
    expect_false(editor$status()$dirty)
    expect_null(messages$modal)
  })

  # Only the disposable copy was modified, not the bundled Sample database.
  canonical <- DBI::dbConnect(RSQLite::SQLite(), source_db, flags = RSQLite::SQLITE_RO)
  withr::defer(DBI::dbDisconnect(canonical))
  expect_identical(DBI::dbGetQuery(canonical,
    "SELECT Location FROM Sample_Env WHERE PlotNumber = ?", params = list(first))$Location[[1L]],
    original_location)
})
