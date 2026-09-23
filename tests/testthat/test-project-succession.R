test_that("succession detection checks the physical vegetation schema without mutation", {
  path <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "Species" TEXT)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("SuccessionYear" INTEGER)')
  DBI::dbDisconnect(con)
  before <- unname(tools::md5sum(path))

  expect_identical(vpro_project_is_successional(path, "Alpha"), FALSE)
  expect_identical(unname(tools::md5sum(path)), before)

  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Veg" ADD COLUMN "successionyear" INTEGER')
  DBI::dbDisconnect(con)
  before <- unname(tools::md5sum(path))

  expect_identical(vpro_project_is_successional(path, "Alpha"), TRUE)
  expect_identical(unname(tools::md5sum(path)), before)
})

test_that("succession detection rejects missing inputs rather than misclassifying", {
  path <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, 'CREATE TABLE "Other_Veg" ("SuccessionYear" INTEGER)')
  DBI::dbDisconnect(con)

  expect_snapshot(error = TRUE, vpro_project_is_successional(path, "Alpha"))
  expect_snapshot(error = TRUE, vpro_project_is_successional("missing.db", "Alpha"))
  expect_snapshot(error = TRUE, vpro_project_is_successional(path, "not valid"))
})
