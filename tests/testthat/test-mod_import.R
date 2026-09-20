# Tests for Import module

source(here::here("R", "logic_compliance.R"))
source(here::here("R", "db_connections.R"))
source(here::here("R", "logic_auth.R"))
source(here::here("R", "mod_import.R"))

setup_import_tables <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE Test_Table (a TEXT, b INTEGER)")
}

setup_import_env_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT,
      projectid TEXT,
      zone TEXT,
      subzone TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation DOUBLE,
      slopegradient DOUBLE,
      aspect DOUBLE
    )
  ")
}

setup_import_veg_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Veg (
      plotnumber TEXT,
      species TEXT,
      projectid TEXT,
      cover TEXT
    )
  ")
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")

  table_ref <- DBI::Id(schema = "lists", table = "SppList")
  if (!DBI::dbExistsTable(con, table_ref)) {
    DBI::dbExecute(con, "CREATE TABLE lists.SppList (spp_code TEXT)")
  }

  fields <- DBI::dbListFields(con, table_ref)
  code_col <- if ("code" %in% fields) "code" else if ("spp_code" %in% fields) "spp_code" else NULL
  if (is.null(code_col)) return()

  DBI::dbExecute(con, sprintf("DELETE FROM lists.SppList"))
  DBI::dbExecute(con, sprintf("INSERT INTO lists.SppList (%s) VALUES ('OK')", code_col))
}

setup_import_lists_table <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  if (DBI::dbExistsTable(con, DBI::Id(schema = "lists", table = "SppList"))) {
    DBI::dbExecute(con, "DROP TABLE lists.SppList")
  }
  DBI::dbExecute(con, "CREATE TABLE lists.SppList (code TEXT, common TEXT)")
}

write_csv_named <- function(dir_path, file_name, data) {
  path <- file.path(dir_path, file_name)
  utils::write.csv(data, path, row.names = FALSE)
  path
}

setup_import_auth <- function(state) {
  auth_init_state(state)
  state$AuthAuthenticated <- TRUE
  state$AuthPermissions <- c("manage:imports")
}

test_that("mod_import imports CSV into target table", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)

  temp_dir <- tempfile("vpro_import_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = c("x", "y"), b = c(1, 2)))

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "Test_Table.csv"))
    session$setInputs(target_table = "Test_Table")
    session$setInputs(import_analyze = 1)

    expect_true(grepl("Columns match target", rv$status))
    expect_equal(nrow(rv$import_validation), 1)
    expect_equal(rv$import_validation$status[1], "Columns match target")

    session$setInputs(import_apply = 1)

    expect_true(grepl("Imported 2 rows", rv$status))
    expect_true(is.data.frame(rv$import_results))
    expect_equal(nrow(rv$import_results), 1)
  })

  rows <- DBI::dbGetQuery(con, "SELECT * FROM Test_Table")
  expect_equal(nrow(rows), 2)
})

test_that("mod_import maps project-suffixed CSV and fills projectid", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_env_table(con)

  temp_dir <- tempfile("vpro_import_project_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(
    temp_dir,
    "PRJ_Env.csv",
    data.frame(
      plotnumber = "P1",
      zone = "ICH",
      subzone = "wk",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "PRJ_Env.csv"))
    session$setInputs(target_table = "Env")
    session$setInputs(import_analyze = 1)

    expect_equal(rv$import_project_override, "PRJ")
    expect_equal(rv$import_validation$status[1], "Columns match target")

    session$setInputs(import_apply = 1)
    expect_true(grepl("Imported 1 rows", rv$status))
  })

  rows <- DBI::dbGetQuery(con, "SELECT projectid FROM Env WHERE plotnumber = 'P1'")
  expect_equal(rows$projectid[[1]], "PRJ")
})

test_that("mod_import can replace existing project data", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_env_table(con)

  DBI::dbExecute(con, "INSERT INTO Env VALUES ('OLD', 'PRJ', 'ICH', 'wk', 55, -120, 100, 10, 180)")

  temp_dir <- tempfile("vpro_import_replace_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(
    temp_dir,
    "PRJ_Env.csv",
    data.frame(
      plotnumber = "NEW",
      zone = "ICH",
      subzone = "wk",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "PRJ_Env.csv"))
    session$setInputs(target_table = "Env")
    session$setInputs(import_analyze = 1)
    session$setInputs(import_allow_replace = TRUE)
    session$setInputs(import_confirm_replace = TRUE)
    session$setInputs(import_apply = 1)

    expect_true(grepl("Imported 1 rows", rv$status))
  })

  rows <- DBI::dbGetQuery(con, "SELECT plotnumber FROM Env WHERE projectid = 'PRJ'")
  expect_equal(rows$plotnumber, "NEW")
})

test_that("mod_import handles ZIP files and imports selected tables", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)

  temp_dir <- tempfile("vpro_import_zip_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_ok <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "z", b = 3))
  csv_bad <- write_csv_named(temp_dir, "Unknown.csv", data.frame(c = "bad"))

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = c(csv_ok, csv_bad))

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    expect_true(any(rv$zip_meta$status == "Unknown table"))
    expect_equal(nrow(rv$import_validation), 2)

    known_id <- rv$zip_map$id[rv$zip_map$table == "Test_Table"][1]
    session$setInputs(zip_tables = as.character(known_id))
    session$setInputs(import_apply = 1)

    expect_true(grepl("Imported 1 tables", rv$status))
    expect_true(is.data.frame(rv$import_results))
    expect_equal(rv$import_results$status[1], "Imported")
  })

  rows <- DBI::dbGetQuery(con, "SELECT * FROM Test_Table")
  expect_equal(nrow(rows), 1)
})

test_that("mod_import supports ZIP imports with multiple project IDs", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_env_table(con)

  temp_dir <- tempfile("vpro_import_zip_projects_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_prj <- write_csv_named(
    temp_dir,
    "PRJ_Env.csv",
    data.frame(
      plotnumber = "P1",
      zone = "ICH",
      subzone = "wk",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )
  csv_pr2 <- write_csv_named(
    temp_dir,
    "PR2_Env.csv",
    data.frame(
      plotnumber = "P2",
      zone = "ICH",
      subzone = "wk",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = c(csv_prj, csv_pr2))

  state <- shiny::reactiveValues(CurrProject = "PRJ")
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    expect_true(all(rv$zip_meta$status == "Columns match target"))

    session$setInputs(zip_tables = as.character(rv$zip_map$id))
    session$setInputs(import_apply = 1)

    expect_true(grepl("Imported 2 tables", rv$status))
    expect_true(all(rv$import_results$status == "Imported"))
  })

  rows <- DBI::dbGetQuery(con, "SELECT plotnumber, projectid FROM Env ORDER BY plotnumber")
  expect_equal(rows$projectid, c("PRJ", "PR2"))
})

test_that("mod_import blocks CSV import when compliance fails", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_env_table(con)

  temp_dir <- tempfile("vpro_import_compliance_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(
    temp_dir,
    "Env.csv",
    data.frame(
      plotnumber = "P1",
      projectid = "PRJ",
      zone = "",
      subzone = "",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )

  state <- shiny::reactiveValues(CurrProject = "PRJ")
  setup_import_auth(state)
  setup_import_auth(state)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "Env.csv"))
    session$setInputs(target_table = "Env")
    session$setInputs(import_analyze = 1)
    session$setInputs(import_apply = 1)

    expect_true(grepl("compliance checks failed", rv$status))
    expect_false(is.null(rv$compliance))
  })

  rows <- DBI::dbGetQuery(con, "SELECT * FROM Env")
  expect_equal(nrow(rows), 0)
})

test_that("mod_import blocks CSV import when validation fails", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)

  temp_dir <- tempfile("vpro_import_validation_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "x"))

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "Test_Table.csv"))
    session$setInputs(target_table = "Test_Table")
    session$setInputs(import_analyze = 1)
    session$setInputs(import_apply = 1)

    expect_true(grepl("validation errors", rv$status))
  })

  rows <- DBI::dbGetQuery(con, "SELECT * FROM Test_Table")
  expect_equal(nrow(rows), 0)
})

test_that("mod_import updates validation when target table changes", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)

  DBI::dbExecute(con, "CREATE TABLE Other_Table (a TEXT)")

  temp_dir <- tempfile("vpro_import_target_update_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "x", b = 1))

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "Test_Table.csv"))
    session$setInputs(target_table = "Other_Table")
    session$setInputs(import_analyze = 1)

    expect_equal(rv$import_validation$status[1], "Column mismatch")

    session$setInputs(target_table = "Test_Table")
    expect_equal(rv$import_validation$status[1], "Columns match target")
  })
})

test_that("mod_import imports CSV into schema-qualified list table", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_lists_table(con)

  temp_dir <- tempfile("vpro_import_lists_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- write_csv_named(
    temp_dir,
    "SppList.csv",
    data.frame(code = "ABBA", common = "Fir", stringsAsFactors = FALSE)
  )

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = csv_path, name = "SppList.csv"))
    session$setInputs(target_table = "lists.SppList")
    session$setInputs(import_analyze = 1)

    expect_equal(rv$import_validation$status[1], "Columns match target")

    session$setInputs(import_apply = 1)
    expect_true(grepl("Imported 1 rows", rv$status))
  })

  rows <- DBI::dbGetQuery(con, "SELECT code, common FROM lists.SppList")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$code[[1]], "ABBA")
})

test_that("mod_import resolves list table names in ZIP imports", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_lists_table(con)

  temp_dir <- tempfile("vpro_import_lists_zip_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_lists <- write_csv_named(
    temp_dir,
    "SppList.csv",
    data.frame(code = "PICEA", common = "Spruce", stringsAsFactors = FALSE)
  )

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = csv_lists)

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    expect_true(any(rv$zip_map$table == "lists.SppList"))

    list_id <- rv$zip_map$id[rv$zip_map$table == "lists.SppList"][1]
    session$setInputs(zip_tables = as.character(list_id))
    session$setInputs(import_apply = 1)

    expect_true(grepl("Imported 1 tables", rv$status))
    expect_true(all(rv$import_results$status == "Imported"))
  })

  rows <- DBI::dbGetQuery(con, "SELECT code, common FROM lists.SppList")
  expect_equal(nrow(rows), 1)
  expect_equal(rows$code[[1]], "PICEA")
})

test_that("mod_import rolls back ZIP imports on compliance failure", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)
  setup_import_env_table(con)

  temp_dir <- tempfile("vpro_import_zip_compliance_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_env <- write_csv_named(
    temp_dir,
    "Env.csv",
    data.frame(
      plotnumber = "P1",
      projectid = "PRJ",
      zone = "",
      subzone = "",
      latitude = 55,
      longitude = -120,
      elevation = 100,
      slopegradient = 10,
      aspect = 180
    )
  )
  csv_ok <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "x", b = 1))

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = c(csv_env, csv_ok))

  state <- shiny::reactiveValues(CurrProject = "PRJ")
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    ids <- rv$zip_map$id[rv$zip_map$table %in% c("Env", "Test_Table")]
    session$setInputs(zip_tables = as.character(ids))
    session$setInputs(import_apply = 1)

    expect_true(grepl("compliance checks failed", rv$status))
  })

  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM Env")), 0)
  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM Test_Table")), 0)
})

test_that("mod_import blocks ZIP import when validation fails", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)

  temp_dir <- tempfile("vpro_import_zip_validation_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_ok <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "x", b = 1))
  csv_bad <- write_csv_named(temp_dir, "Unknown.csv", data.frame(c = "bad"))

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = c(csv_ok, csv_bad))

  state <- shiny::reactiveValues(CurrProject = NULL)
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    ids <- rv$zip_map$id[rv$zip_map$table %in% c("Test_Table", "Unknown")]
    session$setInputs(zip_tables = as.character(ids))
    session$setInputs(import_apply = 1)

    expect_true(grepl("validation errors", rv$status))
  })

  rows <- DBI::dbGetQuery(con, "SELECT * FROM Test_Table")
  expect_equal(nrow(rows), 0)
})

test_that("mod_import rolls back ZIP imports on veg compliance failure", {
  testthat::skip_if_not_installed("shiny")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_import_tables(con)
  setup_import_veg_table(con)

  temp_dir <- tempfile("vpro_import_zip_veg_")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  csv_veg <- write_csv_named(
    temp_dir,
    "Veg.csv",
    data.frame(
      plotnumber = "P1",
      species = "BAD",
      projectid = "PRJ",
      cover = "10"
    )
  )
  csv_ok <- write_csv_named(temp_dir, "Test_Table.csv", data.frame(a = "x", b = 1))

  zip_path <- tempfile(fileext = ".zip")
  utils::zip(zipfile = zip_path, files = c(csv_veg, csv_ok))

  state <- shiny::reactiveValues(CurrProject = "PRJ")
  setup_import_auth(state)

  shiny::testServer(mod_import_server, args = list(state = state, con = con), {
    session$setInputs(import_file = list(datapath = zip_path, name = "batch.zip"))
    session$setInputs(import_analyze = 1)

    ids <- rv$zip_map$id[rv$zip_map$table %in% c("Veg", "Test_Table")]
    session$setInputs(zip_tables = as.character(ids))
    session$setInputs(import_apply = 1)

    expect_true(grepl("compliance checks failed", rv$status))
  })

  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM Veg")), 0)
  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM Test_Table")), 0)
})
