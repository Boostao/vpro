local_environment_fixture <- function(project_path, su_path = NULL) {
  project <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(project, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(project, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY)')
  DBI::dbExecute(project, 'CREATE TABLE "Alpha_Audit" ("EditWhen" TEXT)')
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(project, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(
    project,
    paste0(
      'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, ',
      '"Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, ',
      '"HeightA" REAL, "Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, ',
      '"Cover5b" REAL, "Cover5c" REAL, "TotalB" REAL, "HeightB" TEXT, ',
      '"Cover6" REAL, "Height6" REAL, "Cover7" REAL, "Cover8" REAL, ',
      '"Cover9" REAL, "Collected" TEXT)'
    )
  )
  DBI::dbExecute(project, 'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)')
  DBI::dbExecute(project, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  DBI::dbExecute(project, "INSERT INTO Alpha_Env VALUES ('P1')")
  DBI::dbExecute(project, "INSERT INTO Alpha_Admin VALUES ('P1')")
  on.exit(DBI::dbDisconnect(project), add = TRUE)
  DBI::dbExecute(project, 'ALTER TABLE "Alpha_Env" ADD COLUMN "Value" TEXT')
  DBI::dbExecute(project, "INSERT INTO Alpha_Env VALUES ('P2', 'two'), ('P10', 'ten')")
  DBI::dbExecute(project, "INSERT INTO Alpha_Admin VALUES ('P2'), ('P10')")
  if (!is.null(su_path)) {
    su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
    on.exit(DBI::dbDisconnect(su), add = TRUE)
    DBI::dbExecute(su, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
    DBI::dbExecute(
      su,
      "INSERT INTO Subset_SU VALUES ('P2', 'A'), ('P2', 'B'), ('P10', 'A'), ('ORPHAN', 'Z')"
    )
  }
}

local_environment_context <- function() {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con), envir = parent.frame())
  vpro_project_context(con = con)
}

test_that("environment report uses project and active-SU USysEnv scopes", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  local_environment_fixture(project_path, su_path)
  context <- local_environment_context()
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")

  project_rows <- vpro_report_environment(context)
  expect_identical(project_rows$PlotNumber, c("P1", "P10", "P2"))
  expect_identical(names(project_rows), c("PlotNumber", "Value", "Plot"))

  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  su_rows <- vpro_report_environment(context)
  expect_identical(su_rows$PlotNumber, c("P10", "P2"))
  expect_identical(sum(su_rows$PlotNumber == "P2"), 1L)
  expect_identical(any(su_rows$PlotNumber == "ORPHAN"), FALSE)
})

test_that("environment report applies exact plot filters and typed empty rows", {
  project_path <- tempfile(fileext = ".db")
  local_environment_fixture(project_path)
  context <- local_environment_context()
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")

  filtered <- vpro_report_environment(context, c("P2", "P1"))
  expect_identical(filtered$PlotNumber, c("P1", "P2"))
  empty <- vpro_report_environment(context, character())
  expect_identical(names(empty), c("PlotNumber", "Value", "Plot"))
  expect_identical(nrow(empty), 0L)
  expect_identical(unname(vapply(empty, typeof, character(1))), c("character", "character", "character"))
})

test_that("environment report validates inputs, active context, and source immutability", {
  project_path <- tempfile(fileext = ".db")
  local_environment_fixture(project_path)
  context <- local_environment_context()
  expect_snapshot(error = TRUE, vpro_report_environment(context))
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  before <- unname(tools::md5sum(project_path))
  expect_snapshot(error = TRUE, vpro_report_environment(context, c("P1", NA_character_)))
  expect_snapshot(error = TRUE, vpro_report_environment(context, ""))
  expect_snapshot(error = TRUE, vpro_report_environment(context, 1))
  vpro_report_environment(context, "P1")
  expect_identical(unname(tools::md5sum(project_path)), before)
})
