test_that("project discovery reports compatible SQLite families and upload names", {
  source <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  upload <- tempfile()
  file.copy(source, upload)
  withr::defer(unlink(upload))
  families <- vpro_project_file_families(upload, file_name = "old-project.db")
  expect_identical(families$project, "Sample")
  expect_identical(families$version, "VP08")
  expect_identical(families$compatible, TRUE)
  expect_match(
    conditionMessage(tryCatch(vpro_project_file_families(upload, file_name = "project.txt"), error = identity)),
    "Choose a SQLite"
  )
})

test_that("opening a project copies the source and leaves the session inactive until selected", {
  con <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  vpro_db_disconnect(con)
  root <- withr::local_tempdir()
  source <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  context <- vpro_project_context(install_extensions = FALSE)
  withr::defer(vpro_project_close(context))
  copy <- file.path(root, "copied", "projects", "Sample.db")
  record <- vpro_project_open_file(context, source, "Sample", file.path(root, "copied"))
  expect_identical(record$path, normalizePath(copy))
  expect_null(context$active)
  expect_identical(unname(tools::md5sum(copy)), unname(tools::md5sum(source)))
  expect_match(
    conditionMessage(tryCatch(vpro_project_open_file(context, source, "Sample", file.path(root, "copied")), error = identity)),
    "already open"
  )
  vpro_project_activate(context, "Sample")
  expect_identical(context$active$project, "Sample")
})
