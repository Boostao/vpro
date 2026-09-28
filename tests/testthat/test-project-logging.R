local_project_logging <- function() {
  root <- tempfile("vpro-logging-")
  dir.create(root)
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  path <- file.path(root, "LogTest.db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(sqlite, 'DELETE FROM "Sample_Audit"')
  DBI::dbDisconnect(sqlite)
  lists <- file.path(root, "VLists.db")
  file.copy(system.file("extdata", "VLists.db", package = "vpro"), lists)
  list_db <- DBI::dbConnect(RSQLite::SQLite(), lists)
  DBI::dbExecute(
    list_db,
    "INSERT INTO _table_metadata (table_name, description) VALUES ('USysAllSpecs', 'new-specs'), ('USysTableOfLists', 'new-lists') ON CONFLICT(table_name) DO UPDATE SET description = excluded.description"
  )
  DBI::dbDisconnect(list_db)
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con), envir = parent.frame())
  context <- vpro_project_context(con = con)
  vpro_db_attach(con, lists)
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  list(context = context, path = path)
}

logging_rows <- function(path) {
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(sqlite), add = TRUE)
  DBI::dbGetQuery(sqlite, 'SELECT "Project", "User", "Table", "BeforeEdit", "AfterEdit" FROM "Sample_Audit" ORDER BY rowid')
}

test_that("project opening and closing log all intended audit entries", {
  fixture <- local_project_logging()
  vpro_project_log_lifecycle(fixture$context, "tester", "Open")
  rows <- logging_rows(fixture$path)
  expect_identical(rows$Table, c("Open", "USysAllSpecs", "USysTableOfLists"))
  expect_identical(rows$BeforeEdit, c(NA_character_, "Unknown", "Unknown"))
  expect_identical(rows$AfterEdit, c(NA_character_, "new-specs", "new-lists"))
  expect_identical(rows$Project, rep("Sample", 3L))
  expect_identical(rows$User, rep("tester", 3L))
  vpro_project_log_lifecycle(fixture$context, "tester", "Open")
  vpro_project_log_lifecycle(fixture$context, "tester", "Close")
  expect_identical(logging_rows(fixture$path)$Table, c("Open", "USysAllSpecs", "USysTableOfLists", "Open", "Close"))
})

test_that("failed later audit insert rolls back the entire opening", {
  fixture <- local_project_logging()
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), fixture$path)
  DBI::dbExecute(
    sqlite,
    paste(
      'CREATE TRIGGER abort_lists BEFORE INSERT ON "Sample_Audit"',
      'WHEN NEW."Table" = \'USysTableOfLists\' BEGIN SELECT RAISE(ABORT, \'blocked\'); END'
    )
  )
  DBI::dbDisconnect(sqlite)
  before <- logging_rows(fixture$path)
  expect_error(vpro_project_log_lifecycle(fixture$context, "tester", "Open"), "blocked")
  expect_identical(logging_rows(fixture$path), before)
})
