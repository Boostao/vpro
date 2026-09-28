test_that("offline SQLite preflight reports missing cache without installing user data", {
  root <- withr::local_tempdir()
  cache <- file.path(root, "extensions")
  withr::local_options(
    duckdb.extension_directory = cache,
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  # An offline connection must give setup guidance without modifying storage.
  error <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "Connect while online", fixed = TRUE)
  expect_identical(dir.exists(vpro_data_dir()), FALSE)
  expect_identical(dir.exists(vpro_config_dir()), FALSE)
  expect_length(list.files(cache, recursive = TRUE), 0L)
})
