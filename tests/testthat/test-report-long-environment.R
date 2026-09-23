local_long_env_fixture <- function(project_path, su_path, reference_path, rows, master) {
  fields <- vpro_report_long_environment_fields()
  env_fields <- unique(c("PlotNumber", fields$field[fields$source == "Env"]))
  admin_fields <- unique(c("Plot", fields$field[fields$source == "Admin"]))
  project <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  on.exit(DBI::dbDisconnect(project), add = TRUE)
  make_columns <- function(fields) paste(paste(DBI::dbQuoteIdentifier(project, fields), "TEXT"), collapse = ", ")
  DBI::dbExecute(project, paste0('CREATE TABLE "Alpha_Env" (', make_columns(env_fields), ')'))
  DBI::dbExecute(project, paste0('CREATE TABLE "Alpha_Admin" (', make_columns(admin_fields), ')'))
  DBI::dbExecute(project, 'CREATE TABLE "Alpha_Audit" ("EditWhen" TEXT)')
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(project, paste0('CREATE TABLE "Alpha_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(
    project,
    'CREATE TABLE "Alpha_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, "Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, "Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, "TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, "Cover8" REAL, "Cover9" REAL, "Collected" TEXT)'
  )
  DBI::dbExecute(project, 'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)')
  DBI::dbExecute(project, "INSERT INTO _table_metadata VALUES ('Alpha_Env', 'VP08')")
  for (plot in unique(rows$env)) {
    DBI::dbExecute(project, 'INSERT INTO "Alpha_Env" ("PlotNumber", "FieldNumber") VALUES (?, ?)', params = list(plot, paste0("field-", plot)))
  }
  for (plot in unique(rows$admin)) {
    DBI::dbExecute(project, 'INSERT INTO "Alpha_Admin" ("Plot", "SitePlotQuality") VALUES (?, ?)', params = list(plot, paste0("quality-", plot)))
  }
  su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  on.exit(DBI::dbDisconnect(su), add = TRUE)
  DBI::dbExecute(su, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  for (i in seq_len(nrow(rows$su))) {
    DBI::dbExecute(su, 'INSERT INTO "Subset_SU" VALUES (?, ?)', params = unname(as.list(rows$su[i, ])))
  }
  reference <- DBI::dbConnect(RSQLite::SQLite(), reference_path)
  on.exit(DBI::dbDisconnect(reference), add = TRUE)
  DBI::dbExecute(reference, 'CREATE TABLE "MasterSiteUnitList" ("SiteSeries" TEXT, "SiteSeriesLongName" TEXT, "Level" INTEGER)')
  for (i in seq_len(nrow(master))) {
    DBI::dbExecute(reference, 'INSERT INTO "MasterSiteUnitList" VALUES (?, ?, ?)', params = unname(as.list(master[i, ])))
  }
}

local_long_env_context <- function(project_path, su_path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con), envir = parent.frame())
  context <- vpro_project_context(con = con)
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  context
}

test_that("long environment report preserves bounded membership and diagnostics", {
  project <- tempfile(fileext = ".db")
  su <- tempfile(fileext = ".db")
  reference <- tempfile(fileext = ".db")
  rows <- list(
    env = c("P1", "P2", "P5"),
    admin = c("P1", "P5"),
    su = data.frame(PlotNumber = c("P1", "P1", "P2", "P3", "P4", "", NA), SiteUnit = c("U", "U", "U", "U", "V", "", "W"))
  )
  master <- data.frame(SiteSeries = c("U", "U", "U", "V", "V"), SiteSeriesLongName = c("Unit U", "Unit U", NA, "Beta", "Alpha"), Level = c(1L, 11L, 9L, 1L, 11L))
  local_long_env_fixture(project, su, reference, rows, master)
  context <- local_long_env_context(project, su)
  before <- unname(tools::md5sum(c(project, su, reference)))
  result <- vpro_report_long_environment(context, reference)
  expect_identical(names(result$fields), c("position", "source", "field", "label", "heading"))
  expect_gte(nrow(result$fields), 60L)
  expect_identical(result$plots$PlotNumber, c("", "P1", "P2", "P3", "P4"))
  expect_identical(result$plots$status, c("missing_env", "ok", "missing_admin", "missing_env", "missing_env"))
  expect_identical(result$plots$duplicate_membership_count[result$plots$PlotNumber == "P1"], 2L)
  expect_identical(result$plots$Plot[result$plots$PlotNumber == "P2"], NA_character_)
  expect_identical(result$plots$`Site Number`[result$plots$PlotNumber == "P2"], NA_character_)
  expect_identical(result$plots$`Site Number`[result$plots$PlotNumber == "P1"], "field-P1")
  expect_identical(result$plots$`Plot Quality`[result$plots$PlotNumber == "P1"], "quality-P1")
  expect_identical(result$plots$Plot[result$plots$PlotNumber == "P1"], "P1")
  expect_identical(result$plots$Plot[result$plots$PlotNumber == "P3"], NA_character_)
  expect_identical(result$fields$label[result$fields$heading], c("GENERAL LOCATION", "SITE", "SOIL", "VEGETATION", "OTHER"))
  expect_identical(result$fields$field[result$fields$label == "Assigned Site Unit"], "UserSiteUnit")
  expect_identical(result$fields$source[result$fields$label == "Humus Thickness"], "Admin")
  expect_identical(result$units$SiteUnit, c("", "U", "V"))
  expect_identical(result$units$title, c("", "Unit U", "V"))
  expect_identical(result$units$name_status, c("missing_unit_name", "ok", "conflicting_unit_names"))
  expect_identical(result$names$candidate_names[[3]], c("Alpha", "Beta"))
  expect_identical(result$diagnostics$eligible_memberships, 5L)
  expect_identical(result$diagnostics$duplicate_membership_rows, 1L)
  expect_identical(unname(tools::md5sum(c(project, su, reference))), before)
})

test_that("long environment report validates active scope, empty membership, and schemas", {
  project <- tempfile(fileext = ".db")
  su <- tempfile(fileext = ".db")
  reference <- tempfile(fileext = ".db")
  rows <- list(env = character(), admin = character(), su = data.frame(PlotNumber = c(NA_character_), SiteUnit = c("U")))
  master <- data.frame(SiteSeries = "U", SiteSeriesLongName = "Unit U", Level = 11L)
  local_long_env_fixture(project, su, reference, rows, master)
  context <- local_long_env_context(project, su)
  empty <- vpro_report_long_environment(context, reference)
  expect_identical(nrow(empty$plots), 0L)
  expect_identical(nrow(empty$units), 0L)
  vpro_su_deactivate(context)
  expect_snapshot(error = TRUE, vpro_report_long_environment(context, reference))
  vpro_su_activate(context, "Subset")
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), project)
  on.exit(DBI::dbDisconnect(sqlite), add = TRUE)
  DBI::dbExecute(sqlite, 'ALTER TABLE "Alpha_Env" RENAME COLUMN "FieldNumber" TO "MissingField"')
  expect_snapshot(error = TRUE, vpro_report_long_environment(context, reference))
})

test_that("long environment report rejects ambiguous Env and Admin keys", {
  for (duplicate_table in c("Alpha_Env", "Alpha_Admin")) {
    project <- tempfile(fileext = ".db")
    su <- tempfile(fileext = ".db")
    reference <- tempfile(fileext = ".db")
    rows <- list(
      env = "P1",
      admin = "P1",
      su = data.frame(PlotNumber = "P1", SiteUnit = "U")
    )
    master <- data.frame(SiteSeries = "U", SiteSeriesLongName = "Unit U", Level = 11L)
    local_long_env_fixture(project, su, reference, rows, master)
    sqlite <- DBI::dbConnect(RSQLite::SQLite(), project)
    key <- if (identical(duplicate_table, "Alpha_Env")) "PlotNumber" else "Plot"
    DBI::dbExecute(
      sqlite,
      paste0('INSERT INTO "', duplicate_table, '" ("', key, '") VALUES (\'P1\')')
    )
    DBI::dbDisconnect(sqlite)
    context <- local_long_env_context(project, su)
    expect_snapshot(error = TRUE, vpro_report_long_environment(context, reference))
  }
})

test_that("long environment report validates the reference table and path", {
  project <- tempfile(fileext = ".db")
  su <- tempfile(fileext = ".db")
  reference <- tempfile(fileext = ".db")
  rows <- list(env = "P1", admin = "P1", su = data.frame(PlotNumber = "P1", SiteUnit = "U"))
  master <- data.frame(SiteSeries = "U", SiteSeriesLongName = "Unit U", Level = 11L)
  local_long_env_fixture(project, su, reference, rows, master)
  context <- local_long_env_context(project, su)
  expect_snapshot(error = TRUE, vpro_report_long_environment(context, tempfile(fileext = ".db")))
  expect_snapshot(error = TRUE, vpro_report_long_environment(context, dirname(reference)))
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), reference)
  DBI::dbExecute(sqlite, 'ALTER TABLE "MasterSiteUnitList" RENAME COLUMN "SiteSeriesLongName" TO "OtherName"')
  DBI::dbDisconnect(sqlite)
  expect_snapshot(error = TRUE, vpro_report_long_environment(context, reference))
})
