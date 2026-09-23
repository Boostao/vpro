create_su_hierarchy_validation_fixture <- function(su_path, hierarchy_path) {
  su_con <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  on.exit(DBI::dbDisconnect(su_con), add = TRUE)
  DBI::dbExecute(su_con, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbAppendTable(
    su_con,
    "Subset_SU",
    data.frame(
      PlotNumber = paste0("P", 1:8),
      SiteUnit = c("Shared", "shared", "Orphan", "Orphan", "", NA, "Other", "Alpha")
    )
  )

  hierarchy_con <- DBI::dbConnect(RSQLite::SQLite(), hierarchy_path)
  on.exit(DBI::dbDisconnect(hierarchy_con), add = TRUE)
  DBI::dbExecute(
    hierarchy_con,
    paste(
      'CREATE TABLE "Tree_Hierarchy"',
      '("ID" INTEGER, "Name" TEXT, "Parent" INTEGER, "Level" INTEGER)'
    )
  )
  DBI::dbAppendTable(
    hierarchy_con,
    "Tree_Hierarchy",
    data.frame(
      ID = 1:8,
      Name = c("SHARED", "Missing", "Missing", "", NA, "Other", "LevelTwo", "alpha"),
      Parent = NA_integer_,
      Level = c(11L, 11L, 11L, 11L, 11L, 2L, 2L, 11L)
    )
  )
}

test_that("SU and hierarchy reconciliation preserves direction and level scope", {
  su_path <- tempfile(fileext = ".db")
  hierarchy_path <- tempfile(fileext = ".db")
  create_su_hierarchy_validation_fixture(su_path, hierarchy_path)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  sample_path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  vpro_project_attach(context, sample_path, "Sample")
  vpro_project_activate(context, "Sample")
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  vpro_hierarchy_attach(context, hierarchy_path, "Tree")
  vpro_hierarchy_activate(context, "Tree")
  before <- tools::md5sum(c(su_path, hierarchy_path))

  findings <- vpro_validate_su_hierarchy(context)
  expect_identical(
    findings$su_without_hierarchy,
    data.frame(SiteUnit = c(NA_character_, "Orphan"))
  )
  expect_identical(
    findings$hierarchy_without_su$Name,
    c(NA_character_, "Missing")
  )
  expect_equal(findings$hierarchy_without_su$Level, c(11, 11))
  expect_identical(unname(tools::md5sum(c(su_path, hierarchy_path))), unname(before))
})

test_that("SU and hierarchy reconciliation requires both selections", {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  expect_snapshot(error = TRUE, vpro_validate_su_hierarchy(context))
  context$active_su <- list()
  expect_snapshot(error = TRUE, vpro_validate_su_hierarchy(context))
})
