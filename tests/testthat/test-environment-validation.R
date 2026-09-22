create_environment_validation_project <- function(path, project = "Alpha") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  env <- paste0(project, "_Env")
  admin <- paste0(project, "_Admin")
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      env,
      '" ("PlotNumber" TEXT PRIMARY KEY, "Zone" TEXT, "SoilClassSubGroup" TEXT, ',
      '"SiteDisturbance1" TEXT, "SiteDisturbance2" TEXT, "SiteDisturbance3" TEXT)'
    )
  )
  DBI::dbExecute(
    con,
    paste0('CREATE TABLE "', admin, '" ("Plot" TEXT PRIMARY KEY, "Region" TEXT)')
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
  DBI::dbAppendTable(
    con,
    env,
    data.frame(
      PlotNumber = c("P1", "P2", "P3", "P4", "Orphan"),
      Zone = c("abc", "BAD", "", NA, "ORPHAN"),
      SoilClassSubGroup = c("A", "BADSOIL", "A", "A", "A"),
      SiteDisturbance1 = c("Fire", "Unknown", NA, "", "Fire"),
      SiteDisturbance2 = c("Wind", "Wind", "Wind", " Wind ", "Wind"),
      SiteDisturbance3 = c("Flood", "Flood", "BAD3", "Flood", "Flood"),
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    con,
    admin,
    data.frame(
      Plot = c("P1", "P2", "P3", "P4"),
      Region = c("North", "BADREG", "North", "North"),
      stringsAsFactors = FALSE
    )
  )
  invisible(path)
}

create_environment_reference <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(
    con,
    paste(
      'CREATE TABLE "USysTableOfLists" (',
      '"ListName" TEXT, "Item" TEXT, "FieldUsedIn" TEXT,',
      '"ValidateLoops" TEXT, "Validate" INTEGER)'
    )
  )
  DBI::dbAppendTable(
    con,
    "USysTableOfLists",
    data.frame(
      ListName = c(
        "ZoneList",
        "zonelist",
        "Disturbance",
        "Disturbance",
        "Disturbance",
        "RegionList",
        "SoilList",
        "MissingList",
        "Malformed",
        "Disabled"
      ),
      Item = c("OTHER", "ABC", "Fire", "Wind", "Flood", "North", "A", "X", "X", "BAD"),
      FieldUsedIn = c(
        "Zone",
        "zone",
        "SiteDisturbance",
        "SiteDisturbance",
        "SiteDisturbance",
        "Region",
        "SoilClassSubgroup",
        "MissingField",
        "Zone",
        "Zone"
      ),
      ValidateLoops = c(NA, NA, "3", "3", "3", "0", "-1", NA, "not-a-number", NA),
      Validate = c(1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 0L),
      stringsAsFactors = FALSE
    )
  )
  invisible(path)
}

create_environment_validation_su <- function(path, su = "Subset") {
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
    data.frame(PlotNumber = c("P2", "P3"), SiteUnit = "A")
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

local_environment_validation_context <- function(project_path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  context
}

test_that("environment validation expands loops and reports unknown codes", {
  project_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_environment_validation_project(project_path)
  create_environment_reference(reference_path)
  context <- local_environment_validation_context(project_path)

  result <- vpro_validate_environment_codes(context, reference_path)

  expect_identical(
    result$findings,
    data.frame(
      list_name = c(
        "Disturbance",
        "Disturbance",
        "Disturbance",
        "RegionList",
        "SoilList",
        "ZoneList"
      ),
      field = c(
        "SiteDisturbance1",
        "SiteDisturbance2",
        "SiteDisturbance3",
        "Region",
        "SoilClassSubgroup",
        "Zone"
      ),
      PlotNumber = c("P2", "P4", "P3", "P2", "P2", "P2"),
      value = c("Unknown", " Wind ", "BAD3", "BADREG", "BADSOIL", "BAD"),
      stringsAsFactors = FALSE
    )
  )
  expect_identical(
    result$skipped,
    data.frame(
      list_name = c("Malformed", "MissingList"),
      field = c("Zone", "MissingField"),
      reason = c(
        "ValidateLoops is not an integer.",
        "Field does not exist in the active environment schema."
      ),
      stringsAsFactors = FALSE
    )
  )
})

test_that("active SU validation follows the current USysEnv scope", {
  project_path <- tempfile(fileext = ".db")
  su_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_environment_validation_project(project_path)
  create_environment_validation_su(su_path)
  create_environment_reference(reference_path)
  context <- local_environment_validation_context(project_path)
  vpro_su_attach(context, su_path, "Subset")
  vpro_su_activate(context, "Subset")

  before <- tools::md5sum(c(project_path, su_path, reference_path))
  result <- vpro_validate_environment_codes(context, reference_path)

  expect_identical(result$findings$PlotNumber, c("P2", "P3", "P2", "P2", "P2"))
  expect_identical(
    result$findings$field,
    c("SiteDisturbance1", "SiteDisturbance3", "Region", "SoilClassSubgroup", "Zone")
  )
  expect_identical(
    result$findings$value,
    c("Unknown", "BAD3", "BADREG", "BADSOIL", "BAD")
  )
  expect_identical(
    unname(tools::md5sum(c(project_path, su_path, reference_path))),
    unname(before)
  )
  expect_identical(
    vpro_validate_environment_codes(
      context,
      reference_path,
      use_active_su = FALSE
    )$findings$PlotNumber,
    c("P2", "P4", "P3", "P2", "P2", "P2")
  )
})

test_that("environment validation returns empty findings and is read-only", {
  project_path <- tempfile(fileext = ".db")
  reference_path <- tempfile(fileext = ".db")
  create_environment_validation_project(project_path)
  create_environment_reference(reference_path)
  context <- local_environment_validation_context(project_path)
  project_con <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(
    project_con,
    paste(
      'UPDATE "Alpha_Env" SET "Zone" = \'ABC\', "SoilClassSubGroup" = \'A\',',
      '"SiteDisturbance1" = \'Fire\', "SiteDisturbance2" = \'Wind\',',
      '"SiteDisturbance3" = \'Flood\''
    )
  )
  DBI::dbExecute(project_con, 'UPDATE "Alpha_Admin" SET "Region" = \'North\'')
  DBI::dbDisconnect(project_con)
  before <- tools::md5sum(c(project_path, reference_path))

  result <- vpro_validate_environment_codes(context, reference_path)

  expect_identical(result$findings, vpro:::vpro_environment_validation_empty())
  expect_identical(unname(tools::md5sum(c(project_path, reference_path))), unname(before))
})

test_that("environment validation checks context and reference inputs", {
  reference_path <- tempfile(fileext = ".db")
  create_environment_reference(reference_path)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_snapshot(error = TRUE, vpro_validate_environment_codes(context, reference_path))

  project_path <- tempfile(fileext = ".db")
  create_environment_validation_project(project_path)
  vpro_project_attach(context, project_path, "Alpha")
  vpro_project_activate(context, "Alpha")
  expect_snapshot(error = TRUE, vpro_validate_environment_codes(context, "missing.db"))
  expect_snapshot(
    error = TRUE,
    vpro_validate_environment_codes(context, reference_path, use_active_su = NA)
  )

  invalid_reference <- tempfile(fileext = ".db")
  DBI::dbConnect(RSQLite::SQLite(), invalid_reference) |> DBI::dbDisconnect()
  expect_snapshot(
    error = TRUE,
    vpro_validate_environment_codes(context, invalid_reference)
  )
})
