test_that("startup lists previously saved compatible project copies", {
  con <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(con, "error")) skip(conditionMessage(con))
  vpro_db_disconnect(con)
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  vpro_install()
  vpro_project_create(vpro_db_path("Field", "projects"), "Field", "tester")
  startup <- vpro_startup(config_init(file.path(vpro_config_dir(), "config.yml")))
  withr::defer(vpro_project_close(startup$context))
  expect_setequal(names(startup$context$projects), c("Sample", "Field"))
  expect_identical(startup$context$active$project, "Sample")
  expect_identical(nrow(startup$project_diagnostics), 0L)
})
