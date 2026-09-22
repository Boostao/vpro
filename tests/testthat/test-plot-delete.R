local_plot_delete_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

local_plot_delete_context <- function(path) {
  con <- tryCatch(vpro::vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro::vpro_project_context(con = con)
  withr::defer(vpro::vpro_db_disconnect(context$con), envir = parent.frame())
  vpro::vpro_project_attach(context, path, "Sample")
  vpro::vpro_project_activate(context, "Sample")
  context
}

plot_delete_counts <- function(path, plot_number) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- c(
    Env = "Sample_Env",
    Admin = "Sample_Admin",
    Audit = "Sample_Audit",
    Veg = "Sample_Veg",
    Humus = "Sample_Humus",
    Mineral = "Sample_Mineral",
    Other = "Sample_Other"
  )
  keys <- c(Env = "PlotNumber", Admin = "Plot", Audit = "PlotNumber", Veg = "PlotNumber", Humus = "PlotNumber", Mineral = "PlotNumber", Other = "PlotNumber")
  vapply(
    names(tables),
    function(kind) {
      DBI::dbGetQuery(
        con,
        paste0(
          "SELECT COUNT(*) AS n FROM ",
          DBI::dbQuoteIdentifier(con, tables[[kind]]),
          " WHERE ",
          DBI::dbQuoteIdentifier(con, keys[[kind]]),
          " = ?"
        ),
        params = list(plot_number)
      )$n[[1L]]
    },
    integer(1)
  )
}

plot_delete_source <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(
    con,
    paste(
      "SELECT env.PlotNumber FROM Sample_Env AS env",
      "INNER JOIN Sample_Admin AS admin ON env.PlotNumber = admin.Plot",
      "INNER JOIN Sample_SU AS su ON env.PlotNumber = su.PlotNumber",
      "ORDER BY (SELECT COUNT(*) FROM Sample_Audit AS audit WHERE audit.PlotNumber = env.PlotNumber) DESC,",
      "(SELECT COUNT(*) FROM Sample_Veg AS veg WHERE veg.PlotNumber = env.PlotNumber) DESC",
      "LIMIT 1"
    )
  )$PlotNumber[[1L]]
}

local_plot_delete_external_su <- function(source_plot) {
  path <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE External_SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE UNIQUE INDEX uidx_external_su_plot ON External_SU (PlotNumber)")
  DBI::dbExecute(
    con,
    "INSERT INTO External_SU (PlotNumber, SiteUnit) VALUES (?, 'A')",
    params = list(source_plot)
  )
  path
}

test_that("plot deletion cascades the complete project family and attached SUs", {
  path <- local_plot_delete_copy()
  context <- local_plot_delete_context(path)
  source <- plot_delete_source(path)
  before <- plot_delete_counts(path, source)
  expect_gt(before[["Audit"]], 0L)
  expect_gt(before[["Veg"]], 0L)

  external_path <- local_plot_delete_external_su(source)
  vpro_su_attach(context, path, "Sample")
  vpro_su_attach(context, external_path, "External")
  vpro_su_activate(context, "Sample")
  active_project <- context$active$project
  active_su <- context$active_su$su
  active_hierarchy <- context$active_hierarchy

  result <- vpro_plot_delete(context, source)

  expect_identical(result$plot_number, source)
  expect_identical(result$project_rows, before)
  expect_identical(plot_delete_counts(path, source), stats::setNames(integer(7), names(before)))
  expect_snapshot(error = TRUE, vpro_plot_get(context, source))
  expect_identical(context$active$project, active_project)
  expect_identical(context$active_su$su, active_su)
  expect_identical(context$active_hierarchy, active_hierarchy)

  same_file <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(same_file))
  expect_identical(
    DBI::dbGetQuery(same_file, "SELECT COUNT(*) AS n FROM Sample_SU WHERE PlotNumber = ?", params = list(source))$n[[1L]],
    0L
  )
  external <- DBI::dbConnect(RSQLite::SQLite(), external_path)
  withr::defer(DBI::dbDisconnect(external))
  expect_identical(DBI::dbGetQuery(external, "SELECT COUNT(*) AS n FROM External_SU")$n[[1L]], 0L)
  expect_equal(
    DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv WHERE PlotNumber = ?", params = list(source))$n[[1L]],
    0
  )
  expect_identical(context$active_su$diagnostics$orphan_plot_rows, 0L)
})

test_that("plot deletion rejects missing and incomplete plot pairs", {
  path <- local_plot_delete_copy()
  context <- local_plot_delete_context(path)
  source <- plot_delete_source(path)
  before <- plot_delete_counts(path, source)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, "INSERT INTO Sample_Admin (Plot) VALUES ('DEL0001')")

  expect_snapshot(error = TRUE, vpro_plot_delete(context, "MISSING"))
  expect_snapshot(error = TRUE, vpro_plot_delete(context, "DEL0001"))
  expect_identical(plot_delete_counts(path, source), before)
  expect_identical(plot_delete_counts(path, "DEL0001")[["Admin"]], 1L)
})

test_that("external SU failure rolls back the project deletion cascade", {
  path <- local_plot_delete_copy()
  context <- local_plot_delete_context(path)
  source <- plot_delete_source(path)
  external_path <- local_plot_delete_external_su(source)
  external <- DBI::dbConnect(RSQLite::SQLite(), external_path)
  DBI::dbExecute(
    external,
    "CREATE TRIGGER prevent_su_delete BEFORE DELETE ON External_SU BEGIN SELECT RAISE(ABORT, 'SU delete blocked'); END"
  )
  DBI::dbDisconnect(external)
  vpro_su_attach(context, external_path, "External")
  before <- plot_delete_counts(path, source)

  expect_error(
    vpro_plot_delete(context, source),
    "SU delete blocked",
    fixed = TRUE
  )
  expect_identical(plot_delete_counts(path, source), before)
  external <- DBI::dbConnect(RSQLite::SQLite(), external_path)
  withr::defer(DBI::dbDisconnect(external))
  expect_identical(DBI::dbGetQuery(external, "SELECT COUNT(*) AS n FROM External_SU")$n[[1L]], 1L)
})
