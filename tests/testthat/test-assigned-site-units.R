test_that("assigned choices use the active project view and physical SU rows", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), project_path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  withr::defer(DBI::dbDisconnect(sqlite))
  plots <- DBI::dbGetQuery(sqlite, 'SELECT "PlotNumber" FROM "Sample_Env" ORDER BY "PlotNumber" LIMIT 3')$PlotNumber
  DBI::dbExecute(sqlite, 'UPDATE "Sample_Admin" SET "UserSiteUnit" = NULL')
  for (i in seq_along(plots)) {
    DBI::dbExecute(sqlite, 'UPDATE "Sample_Admin" SET "UserSiteUnit" = ? WHERE "Plot" = ?', params = list(c("", "Zone", "Zone")[[i]], plots[[i]]))
  }
  su_db <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  withr::defer(DBI::dbDisconnect(su_db))
  DBI::dbExecute(su_db, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbAppendTable(
    su_db,
    "Subset_SU",
    data.frame(
      PlotNumber = c(plots, "Missing", "Missing", NA_character_),
      SiteUnit = c("A", "A", "B", "B", "", NA_character_)
    )
  )
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  vpro_project_attach(context, project_path, "Sample")
  vpro_project_activate(context, "Sample")
  before <- tools::md5sum(c(project_path, su_path))
  expect_identical(vpro_assigned_site_units(context), data.frame(UserSiteUnit = c("", "Zone")))
  expect_snapshot(error = TRUE, vpro_assigned_site_units(context, "su"))
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  expect_identical(vpro_assigned_site_units(context, "project"), data.frame(UserSiteUnit = c("", "Zone")))
  expect_identical(vpro_assigned_site_units(context, "su"), data.frame(SiteUnit = c("", "A", "B")))
  expect_identical(unname(tools::md5sum(c(project_path, su_path))), unname(before))
})

test_that("master choices use the level-11 canonical list and explicit reference", {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  path <- tempfile(fileext = ".db")
  db <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(db))
  DBI::dbExecute(db, 'CREATE TABLE "MasterSiteUnitList" ("SiteSeries" TEXT, "SiteSeriesLongName" TEXT, "Level" INTEGER)')
  DBI::dbExecute(db, paste('INSERT INTO "MasterSiteUnitList" VALUES', "('B', 'Bee', 11), ('A', 'Ay', 11), ('X', 'Excluded', 2), (NULL, 'Null', 11)"))
  before <- tools::md5sum(path)
  expect_identical(
    vpro_assigned_site_units(context, "master", path),
    data.frame(SiteSeries = c(NA_character_, "A", "B"), SiteSeriesLongName = c("Null", "Ay", "Bee"))
  )
  expect_identical(unname(tools::md5sum(path)), unname(before))
  expect_snapshot(error = TRUE, vpro_assigned_site_units(context, "other", path))
  expect_snapshot(error = TRUE, vpro_assigned_site_units(context, "master", tempfile()))
  expect_snapshot(error = TRUE, vpro_assigned_site_units(context, "project"))
})
