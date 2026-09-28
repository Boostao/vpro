test_that("missing SQLite extension fails without an implicit download", {
  cache <- withr::local_tempdir()
  withr::local_options(duckdb.extension_directory = cache)

  error <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "vpro_db_install_sqlite", fixed = TRUE)
  expect_length(list.files(cache, recursive = TRUE), 0L)
})
