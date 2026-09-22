create_su_fixture <- function(
  path,
  su = "Subset",
  rows = data.frame(
    PlotNumber = c("P1", "Missing", "", "P1"),
    SiteUnit = c("A", "B", NA, "A"),
    stringsAsFactors = FALSE
  ),
  unique_plot = FALSE
) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- paste0(su, "_SU")
  DBI::dbExecute(
    con,
    paste0('CREATE TABLE "', table, '" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  )
  DBI::dbWriteTable(con, table, rows, append = TRUE)
  if (unique_plot) {
    DBI::dbExecute(
      con,
      paste0('CREATE UNIQUE INDEX "uidx_', table, '_PlotNumber" ON "', table, '" ("PlotNumber")')
    )
  }
  DBI::dbExecute(
    con,
    paste0('CREATE INDEX "idx_', table, '_SiteUnit" ON "', table, '" ("SiteUnit")')
  )
  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    DBI::dbExecute(
      con,
      "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
    )
  }
  DBI::dbExecute(
    con,
    "INSERT INTO _table_metadata VALUES (?, ?)",
    params = list(table, "VP04")
  )
  invisible(path)
}

create_su_project_fixture <- function(path, project = "Alpha") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  env <- paste0(project, "_Env")
  admin <- paste0(project, "_Admin")
  DBI::dbExecute(con, paste0('CREATE TABLE "', env, '" ("PlotNumber" TEXT PRIMARY KEY)'))
  DBI::dbExecute(con, paste0('CREATE TABLE "', admin, '" ("Plot" TEXT PRIMARY KEY)'))
  DBI::dbExecute(con, paste0('CREATE TABLE "', project, '_Audit" ("EditWhen" TEXT)'))
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "', project, "_", suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      project,
      '_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, ',
      '"Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, ',
      '"Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, ',
      '"TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, ',
      '"Cover8" REAL, "Cover9" REAL, "Collected" TEXT)'
    )
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
  )
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES (?, 'VP08')", params = list(env))
  DBI::dbExecute(con, paste0('INSERT INTO "', env, '" VALUES (\'P1\')'))
  DBI::dbExecute(con, paste0('INSERT INTO "', admin, '" VALUES (\'P1\')'))
  invisible(path)
}

local_su_context <- function(config = NULL, authorize = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, config = config, authorize = authorize)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  context
}

test_that("SU inspection validates fields, metadata, and indexes", {
  path <- tempfile(fileext = ".db")
  create_su_fixture(
    path,
    unique_plot = TRUE,
    rows = data.frame(
      PlotNumber = "P1",
      SiteUnit = "A"
    )
  )

  inspection <- vpro_su_inspect(path, "Subset")

  expect_identical(inspection$version, "VP04")
  expect_identical(inspection$compatible, TRUE)
  expect_identical(inspection$unique_plot_index, TRUE)
  expect_identical(inspection$site_unit_index, TRUE)
})

test_that("master SU policy is explicit and direct attachment is authorized", {
  path <- tempfile(fileext = ".db")
  create_su_fixture(path, su = "Reference", rows = data.frame(PlotNumber = "P1", SiteUnit = "A"))
  deny <- function(permission, inspection) FALSE
  allow <- function(permission, inspection) identical(permission, "manage_master_su")

  expect_snapshot(error = TRUE, vpro_su_mark_master(path, "Reference", deny))
  marked <- vpro_su_mark_master(path, "Reference", allow, created_by = "test-user")
  expect_identical(marked$kind, "master")
  expect_identical(marked$policy$created_by, "test-user")

  context <- local_su_context()
  expect_snapshot(error = TRUE, vpro_su_attach(context, path, "Reference"))
  authorized_context <- local_su_context(
    config = NULL,
    authorize = function(permission, inspection) identical(permission, "attach_master_su")
  )
  attached <- vpro_su_attach(authorized_context, path, "Reference")
  expect_identical(attached$kind, "master")
})

test_that("master working copies preserve data and provenance without attachment", {
  source_path <- tempfile(fileext = ".db")
  create_su_fixture(
    source_path,
    su = "Reference",
    unique_plot = TRUE,
    rows = data.frame(PlotNumber = c("P1", "P2"), SiteUnit = c("A", "B"))
  )
  vpro_su_mark_master(
    source_path,
    "Reference",
    authorize = function(permission, inspection) TRUE,
    created_by = "steward"
  )
  context <- local_su_context()

  vpro_su_create_working_copy(
    context,
    source_path,
    "Reference",
    source_path,
    "AnalystCopy",
    created_by = "analyst"
  )
  copy <- vpro_su_inspect(source_path, "AnalystCopy")
  target <- DBI::dbConnect(RSQLite::SQLite(), source_path)
  withr::defer(DBI::dbDisconnect(target))

  expect_identical(copy$kind, "working")
  expect_identical(copy$policy$source_path, normalizePath(source_path))
  expect_identical(copy$policy$source_table, "Reference_SU")
  expect_identical(copy$policy$created_by, "analyst")
  expect_identical(DBI::dbGetQuery(target, 'SELECT COUNT(*) AS n FROM "AnalystCopy_SU"')$n, 2L)
  expect_snapshot(
    error = TRUE,
    vpro_su_create_working_copy(context, source_path, "AnalystCopy", source_path, "SecondCopy")
  )
  expect_false("Reference" %in% names(context$sus))
  expect_null(context$active_su)
})

test_that("SU activation filters the project and returns diagnostics", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- file.path(root, "alpha.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  create_su_project_fixture(path)
  create_su_fixture(path)
  context <- local_su_context(accessor)

  project <- vpro_project_attach(context, path, "Alpha")
  su <- vpro_su_attach(context, path, "Subset")
  expect_identical(su$alias, project$alias)
  expect_identical(length(context$databases), 1L)
  vpro_project_activate(context, "Alpha")
  result <- vpro_su_activate(context, "Subset")

  expect_identical(DBI::dbGetQuery(context$con, "SELECT PlotNumber FROM USysEnv")$PlotNumber, "P1")
  expect_identical(result$diagnostics$total_rows, 4L)
  expect_identical(result$diagnostics$distinct_nonblank_plots, 2L)
  expect_identical(result$diagnostics$blank_plot_rows, 1L)
  expect_identical(result$diagnostics$orphan_plot_rows, 1L)
  expect_identical(result$diagnostics$active_project_plots, 1L)
  expect_identical(result$diagnostics$duplicate_plot_rows, 1L)
  expect_identical(accessor("Current", "CurrPlotlist"), "Subset")
  expect_identical(accessor("Current", "SUPath"), normalizePath(path))
  expect_snapshot(error = TRUE, vpro_su_detach(context, "Subset"))
})

test_that("SU deactivation restores project views and shared detach is safe", {
  path <- tempfile(fileext = ".db")
  create_su_project_fixture(path)
  create_su_fixture(path, rows = data.frame(PlotNumber = "P1", SiteUnit = "A"))
  context <- local_su_context()
  project <- vpro_project_attach(context, path, "Alpha")
  vpro_su_attach(context, path, "Subset")
  vpro_project_activate(context, "Alpha")
  vpro_su_activate(context, "Subset")

  expect_identical(vpro_su_deactivate(context), TRUE)
  expect_null(context$active_su)
  expect_identical(vpro_su_detach(context, "Subset"), TRUE)
  expect_identical(project$alias %in% vpro_db_list(context$con), TRUE)
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 1)
  expect_identical(vpro_su_detach(context, "Subset"), FALSE)
})

test_that("SU save-as preserves rows, indexes, and metadata without changing state", {
  source_path <- tempfile(fileext = ".db")
  target_path <- tempfile(fileext = ".db")
  unlink(target_path)
  create_su_fixture(
    source_path,
    unique_plot = TRUE,
    rows = data.frame(PlotNumber = c("P1", "P2"), SiteUnit = c("A", "B"))
  )
  context <- local_su_context()
  vpro_su_attach(context, source_path, "Subset")

  vpro_su_save_as(context, "Subset", target_path, "Copy")
  inspection <- vpro_su_inspect(target_path, "Copy")
  target <- DBI::dbConnect(RSQLite::SQLite(), target_path)
  withr::defer(DBI::dbDisconnect(target))

  expect_identical(inspection$version, "VP04")
  expect_identical(inspection$unique_plot_index, TRUE)
  expect_identical(inspection$site_unit_index, TRUE)
  expect_identical(DBI::dbGetQuery(target, 'SELECT COUNT(*) AS n FROM "Copy_SU"')$n, 2L)
  expect_identical(inspection$kind, "ordinary")
  expect_null(context$active_su)
  expect_snapshot(error = TRUE, vpro_su_save_as(context, "Subset", target_path, "Copy"))
  expect_snapshot(
    error = TRUE,
    vpro_su_save_as(context, "Subset", tempfile(fileext = ".db"), "NewMaster", kind = "master")
  )
})

test_that("bundled Sample SU activates the canonical subset", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  context <- local_su_context()
  vpro_project_attach(context, path, "Sample")
  vpro_su_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")

  result <- vpro_su_activate(context, "Sample")

  expect_identical(result$su$version, "VP04")
  expect_identical(result$diagnostics$total_rows, 51L)
  expect_identical(result$diagnostics$blank_plot_rows, 0L)
  expect_identical(result$diagnostics$orphan_plot_rows, 0L)
  expect_identical(result$diagnostics$active_project_plots, 51L)
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 51)
})

test_that("SU recovery restores valid state after project recovery", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- file.path(root, "alpha.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  create_su_project_fixture(path)
  create_su_fixture(path, rows = data.frame(PlotNumber = "P1", SiteUnit = "A"))
  accessor("Current", "CurrProject", "Alpha")
  accessor("Current", "ProjectPath", path)
  accessor("Current", "CurrPlotlist", "Subset")
  accessor("Current", "SUPath", path)
  context <- local_su_context(accessor)

  result <- vpro_project_recover(context, sample_path = file.path(root, "unused.db"))

  expect_identical(result$su$recovered, TRUE)
  expect_identical(context$active_su$su, "Subset")
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 1)
})

test_that("failed SU recovery keeps the recovered project unfiltered", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- file.path(root, "alpha.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  create_su_project_fixture(path)
  accessor("Current", "CurrProject", "Alpha")
  accessor("Current", "ProjectPath", path)
  accessor("Current", "CurrPlotlist", "Missing")
  accessor("Current", "SUPath", file.path(root, "missing.db"))
  context <- local_su_context(accessor)

  result <- vpro_project_recover(context, sample_path = file.path(root, "unused.db"))

  expect_identical(result$su$recovered, FALSE)
  expect_match(result$su$error, "does not exist", fixed = TRUE)
  expect_null(context$active_su)
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 1)
  expect_identical(accessor("Current", "CurrPlotlist"), "None")
  expect_identical(accessor("Current", "SUPath"), "")
})
