create_quality_project <- function(path, project = "Alpha") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  env <- paste0(project, "_Env")
  admin <- paste0(project, "_Admin")
  DBI::dbExecute(con, paste0('CREATE TABLE "', env, '" ("PlotNumber" TEXT PRIMARY KEY)'))
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      admin,
      '" ("Plot" TEXT PRIMARY KEY,',
      '"SitePlotQuality" TEXT, "VegPlotQuality" TEXT,',
      '"SoilPlotQuality" TEXT, "BEC_Use" TEXT)'
    )
  )
  DBI::dbExecute(con, paste0('CREATE TABLE "', project, '_Audit" ("EditWhen" TEXT)'))
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "', project, "_", suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      project,
      '_Veg" ("ID" INTEGER, "PlotNumber" TEXT, "Species" TEXT, ',
      '"Cover1" REAL, "Cover2" REAL, "Cover3" REAL, "TotalA" REAL, "HeightA" REAL, ',
      '"Cover4" REAL, "Cover5" REAL, "Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, ',
      '"TotalB" REAL, "HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, ',
      '"Cover8" REAL, "Cover9" REAL, "Collected" TEXT)'
    )
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
  )
  DBI::dbExecute(con, "INSERT INTO _table_metadata VALUES (?, 'VP08')", params = list(env))
  DBI::dbAppendTable(con, env, data.frame(PlotNumber = paste0("P", 1:8)))
  DBI::dbAppendTable(
    con,
    admin,
    data.frame(
      Plot = paste0("P", 1:7),
      SitePlotQuality = c("Excellent", "Good", "Fair", NA, "Unknown", "Good", "Good"),
      VegPlotQuality = c("Good", "Fair", "Good", "Good", "Good", "Good", "Good"),
      SoilPlotQuality = c("Good", "Good", "Poor", "Good", "Good", "Good", "Good"),
      BEC_Use = c("2", "3", "4.1", NA, "5", "10", "1"),
      stringsAsFactors = FALSE
    )
  )
  invisible(path)
}

create_quality_reference <- function(path, duplicate = FALSE) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(
    con,
    'CREATE TABLE "USysTableOfLists" ("ListName" TEXT, "Item" TEXT, "ItemOrder" REAL)'
  )
  quality <- data.frame(
    ListName = c("dataquality", "DataQuality", "DATAQUALITY", "DataQuality"),
    Item = c("Poor", "Fair", "Good", "Excellent"),
    ItemOrder = 1:4,
    stringsAsFactors = FALSE
  )
  quality <- rbind(
    quality,
    data.frame(ListName = "AnotherList", Item = "Unknown", ItemOrder = 1)
  )
  if (duplicate) {
    quality <- rbind(
      quality,
      data.frame(ListName = "DataQuality", Item = "good", ItemOrder = 9)
    )
  }
  DBI::dbAppendTable(con, "USysTableOfLists", quality)
  invisible(path)
}

create_quality_su <- function(path, su = "Subset") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- paste0(su, "_SU")
  DBI::dbExecute(
    con,
    paste0('CREATE TABLE "', table, '" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  )
  DBI::dbAppendTable(
    con,
    table,
    data.frame(
      PlotNumber = c(paste0("P", 1:8), "ORPHAN"),
      SiteUnit = c(rep("A", 4), rep("B", 4), "C"),
      stringsAsFactors = FALSE
    )
  )
  DBI::dbExecute(
    con,
    paste0('CREATE INDEX "idx_', table, '_SiteUnit" ON "', table, '" ("SiteUnit")')
  )
  DBI::dbExecute(
    con,
    "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO _table_metadata VALUES (?, 'VP04')",
    params = list(table)
  )
  invisible(path)
}

local_quality_context <- function(project_path, su_path = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  if (!is.null(su_path)) {
    vpro_su_attach(context, su_path, "Subset")
    vpro_su_activate(context, "Subset")
  }
  context
}

test_that("long-report quality filtering applies inclusive ordered thresholds", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_su(su_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path, su_path)

  result <- vpro_filter_plot_quality(
    context,
    reference_path,
    site_min = "good",
    veg_min = "GOOD",
    soil_min = "Good",
    include_site_missing = FALSE,
    include_veg_missing = FALSE,
    include_soil_missing = FALSE
  )

  expect_identical(result$selected$PlotNumber, c("P1", "P6", "P7"))
  expect_identical(result$thresholds$site, list(label = "Good", order = 3))
  expect_identical(
    result$removed[c("PlotNumber", "removed_by", "failed_criteria")],
    data.frame(
      PlotNumber = c("ORPHAN", "P2", "P3", "P4", "P5", "P8"),
      removed_by = c("Project", "Veg", "Mixed", "Site", "Site", "Project"),
      failed_criteria = c(
        "Project",
        "Veg",
        "Site,Soil",
        "Site",
        "Site",
        "Project"
      ),
      stringsAsFactors = FALSE
    )
  )
})

test_that("missing and unmatched quality labels follow Access joins", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_su(su_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path, su_path)

  result <- vpro_filter_plot_quality(
    context,
    reference_path,
    site_min = "Good",
    veg_min = "Good",
    soil_min = "Good"
  )

  expect_identical(result$selected$PlotNumber, c("P1", "P4", "P6", "P7"))
  expect_identical(result$removed$PlotNumber, c("ORPHAN", "P2", "P3", "P5", "P8"))
  expect_identical(result$removed$removed_by[[4]], "Site")
})

test_that("long-report filtering does not require a BEC field", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  project_con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(project_con, 'ALTER TABLE "Alpha_Admin" DROP COLUMN "BEC_Use"')
  DBI::dbDisconnect(project_con)
  create_quality_su(su_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path, su_path)

  result <- vpro_filter_plot_quality(context, reference_path)

  expect_true(nrow(result$selected) > 0L)
  expect_true(all(is.na(result$removed$BEC_Use)))
  expect_snapshot(
    error = TRUE,
    vpro_filter_plot_quality(context, reference_path, bec_min = "1")
  )
})

test_that("short-report filtering preserves lexical BEC comparison", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_su(su_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path, su_path)

  result <- vpro_filter_plot_quality(
    context,
    reference_path,
    bec_min = "2",
    include_bec_missing = TRUE
  )

  expect_identical(result$selected$PlotNumber, c("P1", "P2", "P3", "P4"))
  expect_identical(
    result$removed[c("PlotNumber", "removed_by")],
    data.frame(
      PlotNumber = c("ORPHAN", "P5", "P6", "P7", "P8"),
      removed_by = c("Project", "Site", "BEC", "BEC", "Project"),
      stringsAsFactors = FALSE
    )
  )
})

test_that("disabled quality filtering returns the complete active SU", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_su(su_path)
  context <- local_quality_context(project_path, su_path)

  result <- vpro_filter_plot_quality(
    context,
    reference_path = "missing.db",
    enforce = FALSE
  )

  expect_identical(result$selected$PlotNumber, c("ORPHAN", paste0("P", 1:8)))
  expect_identical(result$removed, vpro:::vpro_quality_empty_removed())
  expect_null(result$thresholds)
})

test_that("quality filtering is read-only across project, SU, and reference files", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_su(su_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path, su_path)
  before <- tools::md5sum(c(project_path, su_path, reference_path))

  vpro_filter_plot_quality(context, reference_path, bec_min = "1")

  expect_identical(
    unname(tools::md5sum(c(project_path, su_path, reference_path))),
    unname(before)
  )
})

test_that("quality filtering validates context, options, and reference metadata", {
  project_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_quality_project(project_path)
  create_quality_reference(reference_path)
  context <- local_quality_context(project_path)

  expect_snapshot(error = TRUE, vpro_filter_plot_quality(context, reference_path))

  su_path <- tempfile(fileext = ".db")
  create_quality_su(su_path)
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")
  expect_snapshot(
    error = TRUE,
    vpro_filter_plot_quality(context, reference_path, site_min = "Unknown")
  )
  expect_snapshot(
    error = TRUE,
    vpro_filter_plot_quality(context, reference_path, include_bec_missing = NA)
  )
  expect_snapshot(
    error = TRUE,
    vpro_filter_plot_quality(context, "missing.db")
  )

  duplicate_path <- tempfile(fileext = ".db")
  create_quality_reference(duplicate_path, duplicate = TRUE)
  expect_snapshot(
    error = TRUE,
    vpro_filter_plot_quality(context, duplicate_path)
  )
})
