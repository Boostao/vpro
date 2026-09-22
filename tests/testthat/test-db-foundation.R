create_project_fixture <- function(path, project = "Sample", complete = TRUE) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  suffixes <- c("Admin", "Audit", "Env", "Humus", "Metadata", "Mineral", "Other", "Veg")
  if (!complete) {
    suffixes <- setdiff(suffixes, "Veg")
  }
  for (suffix in suffixes) {
    table <- DBI::dbQuoteIdentifier(con, paste0(project, "_", suffix))
    DBI::dbExecute(con, paste("CREATE TABLE", table, "(id INTEGER)"))
  }
  invisible(path)
}

test_that("project discovery reports complete table families", {
  path <- tempfile(fileext = ".db")
  create_project_fixture(path)

  projects <- vpro_project_discover(path)
  expect_identical(projects$project, "Sample")
  expect_identical(projects$core_tables, 8L)
  expect_identical(projects$complete, TRUE)
})

test_that("project validation identifies missing core tables", {
  path <- tempfile(fileext = ".db")
  create_project_fixture(path, complete = FALSE)

  validation <- vpro_project_validate(path, "Sample")
  expect_identical(validation$table[!validation$present], "Sample_Veg")
})

test_that("database paths use the user data root", {
  root <- withr::local_tempdir()
  withr::local_options(vpro.data_dir = root)

  expect_identical(
    vpro_db_path("Sample", "projects"),
    file.path(normalizePath(root), "projects", "Sample.db")
  )
})
