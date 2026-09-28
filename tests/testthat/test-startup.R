skip_without_sqlite_extension <- function() {
  con <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  vpro_db_disconnect(con)
}

test_that("startup recovers Sample and owns a per-session connection", {
  skip_without_sqlite_extension()
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  vpro_install()
  accessor <- config_init(file.path(vpro_config_dir(), "config.yml"))
  startup <- vpro_startup(config = accessor)
  withr::defer(vpro_project_close(startup$context))

  expect_identical(startup$recovery$active$project, "Sample")
  expect_identical(startup$recovery$fallback, FALSE)
  expect_identical(sort(names(startup$context$projects)), "Sample")
  expect_identical(nrow(startup$project_diagnostics), 0L)
  expect_null(startup$recovery$primary_error)
  expect_identical(accessor("Current", "ProjectPath"), normalizePath(vpro_db_path("Sample", "projects")))
  expect_setequal(
    startup$system_databases,
    c("VPro64", "VLists", "VUser", "VMetaData", "VMessageBoard")
  )
  expect_identical(DBI::dbGetQuery(startup$context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 52)
})

test_that("startup closes its connection after a failed recovery", {
  skip_without_sqlite_extension()
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  vpro_config_install(file.path(vpro_config_dir(), "config.yml"))
  accessor <- config_init(file.path(vpro_config_dir(), "config.yml"))
  error <- tryCatch(vpro_startup(config = accessor), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "VPRO database files do not exist", fixed = TRUE)
})
