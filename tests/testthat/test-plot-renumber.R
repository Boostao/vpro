local_plot_renumber_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

local_plot_renumber_context <- function(path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  context
}

plot_renumber_counts <- function(path, plot_number) {
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

plot_renumber_source <- function(path) {
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

local_external_su <- function(project_path, source_plot, target_plot = NULL) {
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
  if (!is.null(target_plot)) {
    DBI::dbExecute(
      con,
      "INSERT INTO External_SU (PlotNumber, SiteUnit) VALUES (?, 'B')",
      params = list(target_plot)
    )
  }
  path
}

test_that("plot renumbering cascades the complete project family and attached SUs", {
  path <- local_plot_renumber_copy()
  context <- local_plot_renumber_context(path)
  source <- plot_renumber_source(path)
  target <- "RNP0001"
  before <- plot_renumber_counts(path, source)
  expect_gt(before[["Audit"]], 0L)
  expect_gt(before[["Veg"]], 0L)

  external_path <- local_external_su(path, source)
  vpro_su_attach(context, path, "Sample")
  vpro_su_attach(context, external_path, "External")
  vpro_su_activate(context, "Sample")

  result <- vpro_plot_renumber(context, source, target)

  expect_identical(result$plot_number, source)
  expect_identical(result$new_plot_number, target)
  expect_identical(result$project_rows, before)
  expect_identical(result$env$PlotNumber, target)
  expect_identical(result$admin$Plot, target)
  expect_identical(plot_renumber_counts(path, source), setNames(integer(7), names(before)))
  expect_identical(plot_renumber_counts(path, target), before)
  expect_identical(vpro_plot_get(context, target)$env$PlotNumber, target)
  expect_snapshot(error = TRUE, vpro_plot_get(context, source))

  same_file <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(same_file))
  expect_identical(
    DBI::dbGetQuery(same_file, "SELECT COUNT(*) AS n FROM Sample_SU WHERE PlotNumber = ?", params = list(source))$n[[1L]],
    0L
  )
  expect_identical(
    DBI::dbGetQuery(same_file, "SELECT COUNT(*) AS n FROM Sample_SU WHERE PlotNumber = ?", params = list(target))$n[[1L]],
    1L
  )
  external <- DBI::dbConnect(RSQLite::SQLite(), external_path)
  withr::defer(DBI::dbDisconnect(external))
  expect_identical(
    DBI::dbGetQuery(external, "SELECT PlotNumber FROM External_SU")$PlotNumber,
    target
  )
  expect_equal(
    DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv WHERE PlotNumber = ?", params = list(target))$n[[1L]],
    1
  )
  expect_identical(context$active_su$diagnostics$orphan_plot_rows, 0L)
})

test_that("plot renumbering rejects invalid sources and target collisions", {
  path <- local_plot_renumber_copy()
  context <- local_plot_renumber_context(path)
  source <- plot_renumber_source(path)
  existing <- DBI::dbGetQuery(
    context$con,
    "SELECT PlotNumber FROM USysEnv WHERE PlotNumber <> ? ORDER BY PlotNumber LIMIT 1",
    params = list(source)
  )$PlotNumber[[1L]]
  before <- plot_renumber_counts(path, source)

  expect_snapshot(error = TRUE, vpro_plot_renumber(context, source, source))
  expect_snapshot(error = TRUE, vpro_plot_renumber(context, "MISSING", "RNP0002"))
  expect_snapshot(error = TRUE, vpro_plot_renumber(context, source, existing))
  expect_identical(plot_renumber_counts(path, source), before)
})

test_that("plot renumbering rejects incomplete and orphan target families", {
  path <- local_plot_renumber_copy()
  context <- local_plot_renumber_context(path)
  source <- plot_renumber_source(path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, "INSERT INTO Sample_Admin (Plot) VALUES ('RNP0003')")
  DBI::dbExecute(
    sqlite,
    "INSERT INTO Sample_Audit (Project, PlotNumber, \"Table\", EditField) VALUES ('Sample', 'RNP0004', '_Env', 'Location')"
  )

  expect_snapshot(error = TRUE, vpro_plot_renumber(context, source, "RNP0003"))
  expect_snapshot(error = TRUE, vpro_plot_renumber(context, source, "RNP0004"))
  expect_identical(plot_renumber_counts(path, source)[["Env"]], 1L)
})

test_that("attached SU collisions fail before project mutation", {
  path <- local_plot_renumber_copy()
  context <- local_plot_renumber_context(path)
  source <- plot_renumber_source(path)
  target <- "RNP0005"
  external_path <- local_external_su(path, source, target)
  vpro_su_attach(context, external_path, "External")
  before <- plot_renumber_counts(path, source)

  expect_snapshot(error = TRUE, vpro_plot_renumber(context, source, target))
  expect_identical(plot_renumber_counts(path, source), before)
})

test_that("external SU failure rolls back the project cascade", {
  path <- local_plot_renumber_copy()
  context <- local_plot_renumber_context(path)
  source <- plot_renumber_source(path)
  target <- "RNP0006"
  external_path <- local_external_su(path, source)
  external <- DBI::dbConnect(RSQLite::SQLite(), external_path)
  DBI::dbExecute(
    external,
    "CREATE TRIGGER prevent_su_renumber BEFORE UPDATE ON External_SU BEGIN SELECT RAISE(ABORT, 'SU renumber blocked'); END"
  )
  DBI::dbDisconnect(external)
  vpro_su_attach(context, external_path, "External")
  before <- plot_renumber_counts(path, source)

  expect_error(
    vpro_plot_renumber(context, source, target),
    "SU renumber blocked",
    fixed = TRUE
  )
  expect_identical(plot_renumber_counts(path, source), before)
  expect_identical(plot_renumber_counts(path, target), setNames(integer(7), names(before)))
})
