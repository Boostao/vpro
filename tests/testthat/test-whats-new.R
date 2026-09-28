test_that("What's New reads and updates only the attached VPro64 copy", {
  check <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(check, "error")) {
    skip(conditionMessage(check))
  }
  vpro_db_disconnect(check)

  root <- withr::local_tempdir()
  path <- file.path(root, "VPro64.db")
  file.copy(system.file("extdata", "VPro64.db", package = "vpro"), path)
  con <- vpro_db_connect(install_extensions = FALSE)
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  vpro_db_attach(con, path)

  rows <- vpro_whats_new_list(context)
  expect_named(rows, c("row_id", "Date", "Change", "Viewed"))
  expect_gt(nrow(rows), 0L)
  expect_identical(rows$Viewed, rep(FALSE, nrow(rows)))
  expect_identical(rows$row_id, rows$row_id[order(rows$Date, rows$row_id, decreasing = TRUE)])

  id <- rows$row_id[[1L]]
  expect_invisible(vpro_whats_new_set_viewed(context, id, TRUE))
  expect_identical(vpro_whats_new_list(context)$Viewed[[1L]], TRUE)
  expect_invisible(vpro_whats_new_set_viewed(context, id, FALSE))
  expect_identical(vpro_whats_new_list(context)$Viewed[[1L]], FALSE)
  expect_identical(vpro_whats_new_mark_all_viewed(context), nrow(rows))
  expect_identical(vpro_whats_new_mark_all_viewed(context), 0L)
  expect_identical(vpro_whats_new_list(context)$Viewed, rep(TRUE, nrow(rows)))

  expect_match(
    conditionMessage(tryCatch(vpro_whats_new_set_viewed(context, max(rows$row_id) + 100L, TRUE), error = identity)),
    "does not exist"
  )
  expect_match(
    conditionMessage(tryCatch(vpro_whats_new_set_viewed(context, id, NA), error = identity)),
    "must be TRUE or FALSE"
  )
})

test_that("What's New refuses to read without VPro64", {
  check <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(check, "error")) {
    skip(conditionMessage(check))
  }
  withr::defer(vpro_db_disconnect(check))
  context <- vpro_project_context(con = check)
  expect_match(
    conditionMessage(tryCatch(vpro_whats_new_list(context), error = identity)),
    "attached VPro64"
  )
})
