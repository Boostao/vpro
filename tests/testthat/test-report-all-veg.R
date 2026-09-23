test_that("USysAllVeg query uses a distinct project-wide layer union", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  covers <- c(paste0("Cover", 1:7), "Cover5a", "Cover5b", "Cover5c", "TotalA", "TotalB", "Cover8", "Cover9", "Cover10")
  DBI::dbExecute(con, paste0(
    'CREATE TABLE "Veg" ("PlotNumber" TEXT, "Species" TEXT, ',
    paste(paste0('"', covers, '" REAL'), collapse = ', '), ')'
  ))
  DBI::dbExecute(con, "INSERT INTO Veg (PlotNumber, Species, Cover1, Cover5a, TotalA, Cover8) VALUES ('P1', 'X', 0, 3, 7, 8), ('P1', 'X', 0, 3, 7, 8), ('P2', 'Y', NULL, NULL, NULL, 2), (NULL, 'Z', 4, NULL, NULL, NULL)")
  result <- vpro_report_all_veg_rows(con, "Veg")
  expect_identical(names(result), c("PlotNumber", "MyLayer", "Species", "Cover"))
  expect_identical(result$MyLayer, c("1", "1", "5a", "A"))
  expect_identical(result$PlotNumber, c(NA_character_, "P1", "P1", "P1"))
  expect_identical(result$Cover, c(4, 0, 3, 7))
  expect_identical(nrow(result), 4L)
  DBI::dbExecute(con, 'DELETE FROM "Veg"')
  expect_identical(nrow(vpro_report_all_veg_rows(con, "Veg")), 0L)
  DBI::dbExecute(con, 'ALTER TABLE "Veg" DROP COLUMN "Cover5a"')
  expect_error(vpro_report_all_veg_rows(con, "Veg"), "lacks required")
})

test_that("USysAllVeg report reads the whole active project despite an SU", {
  path <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  fields <- c(paste0("Cover", 1:7), "Cover5a", "Cover5b", "Cover5c", "TotalA", "TotalB")
  DBI::dbExecute(con, paste0(
    'CREATE TABLE "Sample_Veg" ("PlotNumber" TEXT, "Species" TEXT, ',
    paste(paste0('"', fields, '" REAL'), collapse = ', '), ')'
  ))
  DBI::dbExecute(con, "INSERT INTO Sample_Veg (PlotNumber, Species, Cover1) VALUES ('P1', 'X', 1), ('P2', 'Y', 2)")
  DBI::dbDisconnect(con)
  context <- vpro_project_context(con = DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:"))
  withr::defer(DBI::dbDisconnect(context$con, shutdown = TRUE))
  context$active <- list(path = path, project = "Sample")
  context$active_su <- list(su = "Subset")
  before <- unname(tools::md5sum(path))
  expect_identical(vpro_report_all_veg(context)$PlotNumber, c("P1", "P2"))
  expect_identical(unname(tools::md5sum(path)), before)
  context$active <- NULL
  expect_error(vpro_report_all_veg(context), "active")
})
