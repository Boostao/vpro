create_integrity_fixture <- function(project_path, su_path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Env" ("PlotNumber" TEXT PRIMARY KEY)')
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Admin" ("Plot" TEXT PRIMARY KEY)')
  for (suffix in c("Humus", "Other", "Mineral", "Metadata")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(con, 'CREATE TABLE "Alpha_Audit" ("PlotNumber" TEXT, "EditWhen" TEXT)')
  DBI::dbExecute(con, paste0(
    'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, ',
    '"Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, ',
    '"Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, ',
    '"TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, ',
    '"Cover8" REAL, "Cover9" REAL, "Collected" TEXT)'
  ))
  DBI::dbExecute(con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Env VALUES ('P1'), ('P2'), ('P3'), ('P4')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Admin VALUES ('P1'), ('P2'), ('P3'), ('P4')")
  DBI::dbExecute(con, "INSERT INTO Alpha_Veg (PlotNumber, Species) VALUES ('P1', 'ABC'), ('P2', 'DEF')")
  for (suffix in c("Humus", "Other", "Mineral", "Audit")) {
    DBI::dbExecute(
      con,
      paste0('INSERT INTO "Alpha_', suffix, '" ("PlotNumber") VALUES (?), (?), (?), (?)'),
      params = list("Missing", "Missing", "", NA_character_)
    )
  }
  DBI::dbExecute(
    con,
    'INSERT INTO "Alpha_Veg" ("PlotNumber", "Species") VALUES (?, ?), (?, ?), (?, ?)',
    params = list("Missing", "X", "Missing", "Y", "", "Z")
  )
  su_con <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  on.exit(DBI::dbDisconnect(su_con), add = TRUE)
  DBI::dbExecute(su_con, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbExecute(su_con, 'CREATE INDEX "idx_su_site" ON "Subset_SU" ("SiteUnit")')
  DBI::dbExecute(su_con, 'CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
  DBI::dbExecute(su_con, "INSERT INTO _table_metadata VALUES ('Subset_SU', 'VP04')")
  DBI::dbAppendTable(
    su_con, "Subset_SU", data.frame(PlotNumber = c("P1", "P3", "", NA), SiteUnit = "A")
  )
  DBI::dbAppendTable(
    su_con,
    "Subset_SU",
    data.frame(PlotNumber = c("Missing", "Missing", "", NA), SiteUnit = c("B", "B", "B", "B"))
  )
}

test_that("integrity queries preserve legacy project and active-SU scopes", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  create_integrity_fixture(project_path, su_path)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) skip(conditionMessage(con))
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(con))
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  before <- tools::md5sum(c(project_path, su_path))

  full <- vpro_validate_project_integrity(context)
  expect_identical(full$orphan_children$Table, rep(c("Humus", "Other", "Mineral", "Vegetation", "Audit"), each = 2L))
  expect_identical(full$orphan_children$PlotNumber, rep(c("", "Missing"), 5L))
  expect_identical(full$orphan_su, data.frame(PlotNumber = character(), SiteUnit = character()))
  expect_identical(full$plots_without_vegetation, data.frame(PlotNumber = c("P3", "P4")))

  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  active <- vpro_validate_project_integrity(context)
  expect_identical(active$orphan_children, full$orphan_children)
  expect_identical(active$orphan_su$PlotNumber, c(NA_character_, NA_character_, "", "", "Missing"))
  expect_identical(active$orphan_su$SiteUnit, c("A", "B", "A", "B", "B"))
  expect_identical(active$plots_without_vegetation, data.frame(PlotNumber = "P3"))
  expect_identical(
    vpro_validate_project_integrity(context, use_active_su = FALSE)$plots_without_vegetation,
    full$plots_without_vegetation
  )
  expect_identical(unname(tools::md5sum(c(project_path, su_path))), unname(before))
})

test_that("integrity validation requires an active project and a logical flag", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  create_integrity_fixture(project_path, su_path)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) skip(conditionMessage(con))
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(con))
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  expect_error(vpro_validate_project_integrity(context, use_active_su = NA), "TRUE or FALSE")
  context$active <- NULL
  expect_error(vpro_validate_project_integrity(context), "active")
})
