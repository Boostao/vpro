create_duplicate_fixture <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Audit" ("PlotNumber" TEXT, "EditWhen" TEXT)')
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  fields <- c("Cover1", "Cover2", "Cover3", "Cover4", "Cover5", "Cover5a",
              "Cover5b", "Cover5c", "Cover6", "Cover7", "Cover8", "Cover9", "TotalA", "TotalB", "Cover10")
  DBI::dbExecute(con, paste0(
    'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, ',
    '"HeightA" REAL, "HeightB" TEXT, "Height6" REAL, "Collected" TEXT, ', 
    paste(paste0('"', fields, '" REAL'), collapse = ', '), ')'
  ))
  DBI::dbExecute(con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Env VALUES ('P1'), ('P2'), ('P3')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Admin VALUES ('P1'), ('P2'), ('P3')")
}

local_duplicate_context <- function(path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) testthat::skip(conditionMessage(con))
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, "Alpha")
  vpro_project_activate(context, "Alpha")
  context
}

test_that("duplicate diagnosis follows the Access UNION and layer semantics", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  create_duplicate_fixture(project_path)
  su_con <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  DBI::dbExecute(su_con, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbExecute(su_con, 'CREATE INDEX "idx_su" ON "Subset_SU" ("SiteUnit")')
  DBI::dbExecute(su_con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(su_con, "INSERT INTO _table_metadata VALUES ('Subset_SU', 'VP04')")
  DBI::dbExecute(su_con, "INSERT INTO Subset_SU VALUES ('P1', 'A')")
  DBI::dbDisconnect(su_con)
  project_con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbAppendTable(project_con, "Alpha_Veg", data.frame(
    PlotNumber = c("P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2",
                   "P3", "P3", "P3", "P3", "P3", "P3", NA, NA),
    Species = c("X", "X", "X", "X", "Y", "Y", "Y", "Y",
                "Z", "Z", "Z", "Z", "Z", "Z", NA, NA),
    Cover1 = c(1, 1, 2, NA, rep(NA_real_, 10), 1, 2),
    Cover2 = c(rep(NA_real_, 4), 1, 2, NA, NA, rep(NA_real_, 8)),
    Cover5a = c(rep(NA_real_, 8), 1, 2, rep(NA_real_, 6)),
    TotalA = c(rep(NA_real_, 10), 1, 2, rep(NA_real_, 4)),
    Cover10 = c(rep(NA_real_, 12), 1, 2, NA, NA)
  ))
  DBI::dbDisconnect(project_con)
  context <- local_duplicate_context(project_path)
  before <- tools::md5sum(c(project_path, su_path))

  expected <- data.frame(
    PlotNumber = c(NA_character_, "P1", "P2", "P3", "P3"),
    Species = c(NA_character_, "X", "Y", "Z", "Z"),
    Layer = c("1", "1", "2", "5a", "A"),
    n_of_spp = rep(2L, 5)
  )
  expect_identical(vpro_vegetation_duplicates(context), expected)
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  expect_identical(vpro_vegetation_duplicates(context), expected)
  expect_identical(unname(tools::md5sum(c(project_path, su_path))), unname(before))
})

test_that("duplicate diagnosis returns typed empty results and requires an active project", {
  project_path <- tempfile(fileext = ".db")
  create_duplicate_fixture(project_path)
  context <- local_duplicate_context(project_path)
  expect_identical(
    vpro_vegetation_duplicates(context),
    data.frame(PlotNumber = character(), Species = character(),
               Layer = character(), n_of_spp = integer())
  )
  context$active <- NULL
  expect_error(vpro_vegetation_duplicates(context), "active")
})
