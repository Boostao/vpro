local_plot_read_context <- function(path) {
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

local_plot_read_sample_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

test_that("plot list reads ordered numbers from canonical Env rows", {
  path <- local_plot_read_sample_copy()
  context <- local_plot_read_context(path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, "INSERT INTO Sample_Env (PlotNumber) VALUES ('ZZZ0001')")
  DBI::dbExecute(sqlite, "INSERT INTO Sample_Env (PlotNumber) VALUES ('AAA0001')")

  expected <- DBI::dbGetQuery(
    sqlite,
    "SELECT PlotNumber FROM Sample_Env ORDER BY PlotNumber"
  )$PlotNumber

  expect_identical(vpro_plot_list(context), expected)
  expect_true("AAA0001" %in% vpro_plot_list(context))
  expect_true("ZZZ0001" %in% vpro_plot_list(context))
})

test_that("plot list requires an active project", {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_error(vpro_plot_list(context), "must be active")
})

test_that("Other get uses vegetation identity ambiguity semantics", {
  path <- local_plot_read_sample_copy()
  context <- local_plot_read_context(path)
  plots <- DBI::dbGetQuery(
    context$con,
    "SELECT PlotNumber FROM USysEnv ORDER BY PlotNumber LIMIT 2"
  )$PlotNumber
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbAppendTable(
    sqlite,
    "Sample_Other",
    data.frame(
      PlotNumber = c(plots[[1L]], plots[[2L]]),
      DataName = c("Only", "Other plot"),
      ID = c(9701L, 9702L),
      stringsAsFactors = FALSE
    )
  )

  row <- vpro_plot_other_get(context, plots[[1L]], 9701L)

  expect_identical(row$DataName, "Only")
  expect_identical(row$ID, 9701L)
  expect_error(
    vpro_plot_other_get(context, plots[[2L]], 9701L),
    "does not exist"
  )

  DBI::dbExecute(sqlite, "ALTER TABLE Sample_Other RENAME TO Sample_Other_original")
  DBI::dbExecute(sqlite, "CREATE TABLE Sample_Other AS SELECT * FROM Sample_Other_original")
  DBI::dbExecute(
    sqlite,
    "INSERT INTO Sample_Other (PlotNumber, DataName, ID) VALUES (?, 'Duplicate', 9703), (?, 'Duplicate again', 9703)",
    params = list(plots[[1L]], plots[[1L]])
  )
  expect_error(
    vpro_plot_other_get(context, plots[[1L]], 9703L),
    "identity is not unique"
  )
  expect_error(
    vpro_plot_other_get(context, plots[[1L]], 2147483648),
    "signed 32-bit"
  )
})
