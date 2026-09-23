local_location_fixture <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Audit" ("EditWhen" TEXT)')
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(
    con,
    'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, "Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, "Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, "TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, "Cover8" REAL, "Cover9" REAL, "Collected" TEXT)'
  )
  DBI::dbExecute(con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Env VALUES ('P1')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Admin VALUES ('P1')")
}

local_location_context <- function() {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con), envir = parent.frame())
  vpro_project_context(con = con)
}

test_that("location report uses active USysEnv and excludes missing coordinates", {
  path <- tempfile(fileext = ".db")
  local_location_fixture(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "Zone" TEXT')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "SubZone" TEXT')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "SiteSeries" TEXT')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "LocationAccuracy" INTEGER')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "Latitude" REAL')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "Longitude" REAL')
  DBI::dbExecute(con, 'ALTER TABLE "Alpha_Env" ADD COLUMN "Elevation" INTEGER')
  DBI::dbExecute(
    con,
    'UPDATE "Alpha_Env" SET "Zone" = ?, "SiteSeries" = ?, "LocationAccuracy" = 5, "Latitude" = 49.5, "Longitude" = -123.5, "Elevation" = 120 WHERE "PlotNumber" = ?',
    params = list("CWH", "01", "P1")
  )
  DBI::dbExecute(con, 'INSERT INTO "Alpha_Env" ("PlotNumber", "Latitude", "Longitude") VALUES ("P2", 50, -124), ("P3", NULL, -120), ("P4", 48, NULL), ("P5", 49, -122)')
  DBI::dbExecute(con, 'INSERT INTO "Alpha_Admin" ("Plot") VALUES ("P2"), ("P3"), ("P4")')
  DBI::dbDisconnect(con)

  su_path <- tempfile(fileext = ".db")
  su_con <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  DBI::dbExecute(su_con, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbExecute(su_con, "INSERT INTO Subset_SU VALUES ('P1', 'A'), ('P3', 'A'), ('P5', 'A')")
  DBI::dbDisconnect(su_con)
  context <- local_location_context()
  vpro_project_attach(context, path, "Alpha")
  vpro_project_activate(context, "Alpha")
  result <- vpro_report_location(context)
  expect_identical(names(result), c("PlotNumber", "Zone", "SubZone", "SiteSeries", "LocationAccuracy", "Latitude", "Longitude", "Elevation"))
  expect_identical(result$PlotNumber, c("P1", "P2"))
  expect_identical(result$Longitude, c(123.5, 124))
  expect_identical(result$Latitude, c(49.5, 50))
  expect_identical(result$SiteSeries, c("01", NA_character_))
  expect_identical(result$LocationAccuracy, c(5, NA_real_))
  expect_identical(result$Elevation, c(120, NA_real_))

  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  expect_identical(vpro_report_location(context)$PlotNumber, "P1")
})

test_that("location report returns an empty table when coordinates are absent", {
  path <- tempfile(fileext = ".db")
  local_location_fixture(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  for (column in c("Zone", "SubZone", "SiteSeries")) {
    DBI::dbExecute(con, paste0('ALTER TABLE "Alpha_Env" ADD COLUMN "', column, '" TEXT'))
  }
  for (column in c("LocationAccuracy", "Latitude", "Longitude", "Elevation")) {
    DBI::dbExecute(con, paste0('ALTER TABLE "Alpha_Env" ADD COLUMN "', column, '" REAL'))
  }
  DBI::dbDisconnect(con)
  context <- local_location_context()
  vpro_project_attach(context, path, "Alpha")
  vpro_project_activate(context, "Alpha")
  expect_identical(nrow(vpro_report_location(context)), 0L)
})

test_that("location report requires an active project", {
  context <- local_location_context()
  expect_snapshot(error = TRUE, vpro_report_location(context))
})
