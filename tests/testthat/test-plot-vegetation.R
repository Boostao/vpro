local_vegetation_context <- function(path) {
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

local_vegetation_sample_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

vegetation_plot_number <- function(context) {
  DBI::dbGetQuery(
    context$con,
    'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 1'
  )$PlotNumber[[1L]]
}

test_that("vegetation creation generates a stable audited ID", {
  path <- local_vegetation_sample_copy()
  context <- local_vegetation_context(path)
  plot_number <- vegetation_plot_number(context)

  created <- vpro_plot_vegetation_create(
    context,
    plot_number,
    list(Species = "ORCLVEG", Cover1 = 1),
    user = "creator",
    audit_strength = 2
  )
  id <- created$vegetation$ID
  updated <- vpro_plot_vegetation_update(
    context,
    plot_number,
    id,
    list(Species = "ORCLVE2", Cover1 = 2),
    user = "editor",
    audit_strength = 1
  )

  expect_gte(id, -2147483648)
  expect_lte(id, 2147483647)
  expect_setequal(created$audit$EditField, c("Species", "Cover1"))
  expect_true(all(created$audit$ID == id))
  expect_identical(updated$vegetation$ID, id)
  expect_identical(updated$vegetation$Species, "ORCLVE2")
  expect_setequal(updated$audit$EditField, c("Species", "Cover1"))
  expect_identical(vpro_plot_vegetation_get(context, plot_number, id)$ID, id)
})

test_that("vegetation identity ambiguity is rejected without mutation", {
  path <- local_vegetation_sample_copy()
  context <- local_vegetation_context(path)
  plot_number <- vegetation_plot_number(context)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbAppendTable(
    con,
    "Sample_Veg",
    data.frame(
      PlotNumber = c(plot_number, plot_number),
      Species = c("DUPONE", "DUPTWO"),
      ID = c(2000000004, 2000000004),
      stringsAsFactors = FALSE
    )
  )

  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_get(context, plot_number, 2000000004)
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_update(
      context,
      plot_number,
      2000000004,
      list(Cover1 = 5),
      user = "editor"
    )
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_delete(context, plot_number, 2000000004)
  )
  expect_identical(
    DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM Sample_Veg WHERE PlotNumber = ? AND ID = ?",
      params = list(plot_number, 2000000004)
    )$n[[1L]],
    2L
  )
})

test_that("vegetation deletion adds no audit row", {
  path <- local_vegetation_sample_copy()
  context <- local_vegetation_context(path)
  plot_number <- vegetation_plot_number(context)
  initial_rows <- nrow(vpro_plot_vegetation_list(context, plot_number))
  created <- vpro_plot_vegetation_create(
    context,
    plot_number,
    list(Species = "DELETE", Cover6 = 1),
    user = "creator",
    audit_strength = 0
  )
  id <- created$vegetation$ID
  before_audit <- nrow(vpro_plot_audit_list(context, plot_number))

  deleted <- vpro_plot_vegetation_delete(context, plot_number, id)

  expect_identical(deleted$ID, id)
  expect_identical(nrow(vpro_plot_vegetation_list(context, plot_number)), initial_rows)
  expect_identical(nrow(vpro_plot_audit_list(context, plot_number)), before_audit)
})

test_that("vegetation values and species are validated", {
  path <- local_vegetation_sample_copy()
  context <- local_vegetation_context(path)
  plot_number <- vegetation_plot_number(context)

  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_create(
      context,
      plot_number,
      list(Cover1 = 1),
      user = "creator"
    )
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_create(
      context,
      plot_number,
      list(Species = "TOO-LONG-CODE", Cover1 = 1),
      user = "creator"
    )
  )
  created <- vpro_plot_vegetation_create(
    context,
    plot_number,
    list(Species = "VALID", Cover1 = 1),
    user = "creator",
    audit_strength = 0
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_vegetation_update(
      context,
      plot_number,
      created$vegetation$ID,
      list(Cover1 = "high"),
      user = "editor"
    )
  )
})
