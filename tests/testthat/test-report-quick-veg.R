quick_veg_fixture <- function(project_path, su_path = NULL) {
  con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Audit" ("EditWhen" TEXT)')
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, "Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, "Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, "TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, "Cover8" REAL, "Cover9" REAL, "Collected" TEXT)')
  DBI::dbExecute(con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  DBI::dbDisconnect(con)
  if (!is.null(su_path)) {
    su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
    DBI::dbExecute(su, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
    DBI::dbExecute(su, "INSERT INTO Subset_SU VALUES ('P1', 'A'), ('P2', 'A'), ('P8', 'A')")
    DBI::dbDisconnect(su)
  }
  db <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(db, "error")) testthat::skip(conditionMessage(db))
  withr::defer(vpro_db_disconnect(db), envir = parent.frame())
  context <- vpro_project_context(con = db)
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  if (!is.null(su_path)) {
    vpro_su_attach(context, su_path, "Subset")
    vpro_su_activate(context, "Subset")
  }
  context
}

test_that("quick vegetation SQL preserves layers, nulls and join multiplicity", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(con, 'CREATE TABLE veg ("PlotNumber" TEXT, "Species" TEXT, "Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "Cover4" REAL, "Cover5" REAL, "Cover6" REAL, "Cover7" REAL, "Cover8" REAL, "Cover9" REAL, "Cover10" REAL)')
  DBI::dbExecute(con, 'CREATE TABLE su ("PlotNumber" TEXT)')
  DBI::dbExecute(con, "INSERT INTO veg (PlotNumber, Species, Cover1, Cover9, Cover10) VALUES ('P1', 'A', 0, 9, 10), ('P2', 'B', NULL, 8, NULL), ('P3', 'C', 5, NULL, NULL)")
  DBI::dbExecute(con, "INSERT INTO su VALUES ('P1'), ('P1'), ('P2')")
  result <- vpro_quick_veg_rows(con, 'veg', 'su')
  expect_identical(result$PlotNumber, c('P1', 'P1', 'P1', 'P1', 'P2'))
  expect_identical(result$Layer, c(1L, 1L, 9L, 9L, 9L))
  expect_identical(result$Cover, c(0, 0, 9, 9, 8))
  expect_identical(names(result), c('PlotNumber', 'Layer', 'Species', 'Cover'))
})

test_that("quick vegetation rows preserve layers, non-null covers and SU joins", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  context <- quick_veg_fixture(project_path, su_path)
  project <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  veg <- data.frame(
    ID = 1:3, PlotNumber = c("P1", "P2", "P8"),
    Species = c("A", "B", "C"), Cover1 = c(0, NA, 5),
    Cover9 = c(9, 8, NA), stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(project, "Alpha_Veg", veg)
  DBI::dbDisconnect(project)
  before <- unname(tools::md5sum(project_path))
  result <- vpro_report_quick_veg(context)
  expect_identical(result$Layer, c(1L, 1L, 9L, 9L))
  expect_identical(result$PlotNumber, c("P1", "P8", "P1", "P2"))
  expect_identical(result$Cover, c(0, 5, 9, 8))
  expect_identical(unname(tools::md5sum(project_path)), before)

  su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  DBI::dbExecute(su, "INSERT INTO Subset_SU VALUES ('P1', 'D')")
  DBI::dbDisconnect(su)
  expect_identical(sum(vpro_report_quick_veg(context)$PlotNumber == "P1"), 4L)
})

test_that("quick vegetation rows require active SU and required fields", {
  project_path <- tempfile(fileext = ".db")
  context <- quick_veg_fixture(project_path)
  expect_error(vpro_report_quick_veg(context), "active VPRO SU")
  su_path <- tempfile(fileext = ".db")
  su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  DBI::dbExecute(su, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbDisconnect(su)
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  expect_identical(nrow(vpro_report_quick_veg(context)), 0L)
  con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Veg" DROP COLUMN "Cover9"')
  DBI::dbDisconnect(con)
  expect_error(vpro_report_quick_veg(context), "lacks required")
})
