create_vegetation_validation_project <- function(path, project = "Alpha") {
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
  DBI::dbAppendTable(con, env, data.frame(PlotNumber = c("P1", "P2", "P3")))
  DBI::dbAppendTable(con, admin, data.frame(Plot = c("P1", "P2", "P3")))
  DBI::dbAppendTable(
    con,
    paste0(project, "_Veg"),
    data.frame(
      ID = 1:7,
      PlotNumber = c("P1", "P1", "P1", "P1", "P1", "P2", "Orphan"),
      Species = c("abc", "BAD", "BAD", "", NA, "BAD2", "BAD3"),
      stringsAsFactors = FALSE
    )
  )
  invisible(path)
}

create_vegetation_reference <- function(path, codes = c("ABC", "OTHER")) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, 'CREATE TABLE "USysAllSpecs" ("Code" TEXT)')
  DBI::dbAppendTable(con, "USysAllSpecs", data.frame(Code = codes))
  invisible(path)
}

create_vegetation_validation_su <- function(path, su = "Subset") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- paste0(su, "_SU")
  DBI::dbExecute(con, paste0('CREATE TABLE "', table, '" ("PlotNumber" TEXT, "SiteUnit" TEXT)'))
  DBI::dbAppendTable(
    con,
    table,
    data.frame(
      PlotNumber = c("P1", "P1", "P3", "", NA),
      SiteUnit = "A",
      stringsAsFactors = FALSE
    )
  )
  DBI::dbExecute(con, paste0('CREATE INDEX "idx_', table, '_SiteUnit" ON "', table, '" ("SiteUnit")'))
  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    DBI::dbExecute(
      con,
      "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
    )
  }
  DBI::dbExecute(
    con,
    "INSERT INTO _table_metadata VALUES (?, 'VP04')",
    params = list(table)
  )
  invisible(path)
}

local_vegetation_validation_context <- function(project_path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  context
}

test_that("vegetation validation reports distinct unknown project codes", {
  project_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_vegetation_validation_project(project_path)
  create_vegetation_reference(reference_path, c("ABC", "ABC"))
  context <- local_vegetation_validation_context(project_path)

  result <- vpro_validate_vegetation_codes(context, reference_path)

  expect_identical(
    result,
    data.frame(
      PlotNumber = c("Orphan", "P1", "P1", "P1", "P2"),
      Species = c("BAD3", NA, "", "BAD", "BAD2"),
      stringsAsFactors = FALSE
    )
  )
})

test_that("active SU validation preserves the Access left-join scope", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_vegetation_validation_project(project_path)
  create_vegetation_validation_su(su_path)
  create_vegetation_reference(reference_path)
  context <- local_vegetation_validation_context(project_path)
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")

  result <- vpro_validate_vegetation_codes(context, reference_path)

  expect_identical(
    result,
    data.frame(
      PlotNumber = c(NA, "P1", "P1", "P1"),
      Species = c(NA, NA, "", "BAD"),
      stringsAsFactors = FALSE
    )
  )
  expect_identical(
    vpro_validate_vegetation_codes(context, reference_path, use_active_su = FALSE)$Species,
    c("BAD3", NA, "", "BAD", "BAD2")
  )
})

test_that("vegetation validation is read-only", {
  project_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_vegetation_validation_project(project_path)
  create_vegetation_reference(reference_path)
  context <- local_vegetation_validation_context(project_path)
  before <- tools::md5sum(c(project_path, reference_path))

  vpro_validate_vegetation_codes(context, reference_path)

  expect_identical(unname(tools::md5sum(c(project_path, reference_path))), unname(before))
})

test_that("vegetation validation checks context and reference inputs", {
  reference_path <- tempfile(fileext = ".db")
  create_vegetation_reference(reference_path)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_snapshot(error = TRUE, vpro_validate_vegetation_codes(context, reference_path))

  project_path <- tempfile(fileext = ".db")
  create_vegetation_validation_project(project_path)
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  expect_snapshot(error = TRUE, vpro_validate_vegetation_codes(context, "missing.db"))
  expect_snapshot(
    error = TRUE,
    vpro_validate_vegetation_codes(context, reference_path, use_active_su = NA)
  )

  invalid_reference <- tempfile(fileext = ".db")
  DBI::dbConnect(RSQLite::SQLite(), invalid_reference) |> DBI::dbDisconnect()
  expect_snapshot(
    error = TRUE,
    vpro_validate_vegetation_codes(context, invalid_reference)
  )
})
