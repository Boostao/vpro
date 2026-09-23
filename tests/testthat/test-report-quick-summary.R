test_that("Quick Summary uses a distinct union and retains missing Admin labels", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY, "UserSiteUnit" TEXT, "BECSiteUnit" TEXT)')
  layers <- c(paste0("Cover", 1:7), "Cover5a", "Cover5b", "Cover5c", "TotalA", "TotalB", "Cover8")
  DBI::dbExecute(con, paste0(
    'CREATE TABLE "Alpha_Veg" ("PlotNumber" TEXT, "Species" TEXT, ',
    paste(paste0('"', layers, '" REAL'), collapse = ', '), ')'
  ))
  DBI::dbExecute(con, "INSERT INTO Alpha_Env VALUES ('P1'), ('P2'), ('P3')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Admin VALUES ('P1', 'User', 'BEC'), ('P3', '', 'BEC3')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Veg (PlotNumber, Species, Cover1, Cover5a, TotalA, Cover8) VALUES ('P1', 'X', 0, 3, 4, 8), ('P1', 'X', 0, 3, 4, 8), ('P2', 'Y', 2, NULL, NULL, 9), ('P3', 'Z', 1, NULL, NULL, NULL), ('ORPHAN', 'O', 10, NULL, NULL, NULL)")
  expected <- data.frame(
    PlotNumber = c('P1', 'P2', 'P3', 'P1', 'P1'),
    AssignedSiteUnit = c('User', NA, '', 'User', 'User'),
    MyLayer = c('1', '1', '1', '5a', 'A'),
    Species = c('X', 'Y', 'Z', 'X', 'X'),
    Cover = c(0, 2, 1, 3, 4)
  )
  expect_identical(vpro_report_quick_summary_rows(con, 'Alpha'), expected)
  DBI::dbExecute(con, 'DELETE FROM "Alpha_Veg"')
  empty <- vpro_report_quick_summary_rows(con, 'Alpha')
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), names(expected))
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Admin" DROP COLUMN "UserSiteUnit"')
  expect_error(vpro_report_quick_summary_rows(con, 'Alpha'), 'requires VP08 Env and Admin')
})

test_that("Quick Summary uses an activated context and ignores selected SU", {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, 'error')) testthat::skip(conditionMessage(con))
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  project_path <- system.file('extdata', 'projects', 'Sample.db', package = 'vpro')
  vpro_project_attach(context, project_path, 'Sample')
  vpro_project_activate(context, 'Sample')
  expected <- vpro_report_quick_summary(context)
  su_path <- project_path
  vpro_su_attach(context, su_path, 'Sample')
  vpro_su_activate(context, 'Sample')
  expect_identical(vpro_report_quick_summary(context), expected)
})

test_that("Quick Summary is project-wide and read-only on bundled VP08 Sample", {
  path <- system.file('extdata', 'projects', 'Sample.db', package = 'vpro')
  context <- vpro_project_context(con = DBI::dbConnect(duckdb::duckdb(), dbdir = ':memory:'))
  withr::defer(DBI::dbDisconnect(context$con, shutdown = TRUE))
  context$active <- list(path = path, project = 'Sample', version = 'VP08')
  context$active_su <- list(su = 'Subset')
  before <- unname(tools::md5sum(path))
  result <- vpro_report_quick_summary(context)
  expect_identical(nrow(result), 2026L)
  expect_identical(names(result), c('PlotNumber', 'AssignedSiteUnit', 'MyLayer', 'Species', 'Cover'))
  expect_identical(result[c('PlotNumber', 'MyLayer', 'Species', 'Cover')],
                   vpro_report_all_veg(context)[c('PlotNumber', 'MyLayer', 'Species', 'Cover')])
  expect_identical(unname(tools::md5sum(path)), before)
  context$active$version <- 'VP07'
  expect_error(vpro_report_quick_summary(context), 'requires an active VP08')
  context$active <- NULL
  expect_error(vpro_report_quick_summary(context), 'active')
})
