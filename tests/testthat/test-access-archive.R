test_that("empty Access date columns retain their SQLite text type", {
  empty <- as.POSIXct(character(), tz = "UTC")
  expect_identical(vpro_access_normalize_column(empty), character())
  expect_identical(
    vpro_access_normalize_column(as.POSIXct(c(NA, "2026-09-23 12:34:56"), tz = "UTC")),
    c(NA_character_, "2026-09-23 12:34:56.000000")
  )
})

test_that("Access archive preserves tables and descriptions without altering source", {
  source <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  access <- normalizePath(file.path(testthat::test_path("..", "..", ".."), "VPRO_ACCESS", "VPro64", "VPro64.accdb"), mustWork = FALSE)
  skip_if_not(file.exists(access), "Optional Access fixture unavailable")
  root <- withr::local_tempdir()
  copy <- file.path(root, "source.accdb")
  file.copy(access, copy)
  before <- tools::md5sum(copy)
  dry <- vpro_access_inspect(copy)
  expect_identical(dry$tables$description[match("Sample_Env", dry$tables$table_name)], "VP08")
  expect_identical(dry$links, character())
  archive_path <- file.path(root, "archive.db")
  receipt <- vpro_access_archive(copy, archive_path, max_rows_per_table = 2000L)
  expect_identical(receipt$archive_path, normalizePath(archive_path))
  expect_identical(unname(tools::md5sum(copy)), unname(before))
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), archive_path)
  withr::defer(DBI::dbDisconnect(sqlite))
  expect_identical(DBI::dbGetQuery(sqlite, 'SELECT description FROM _table_metadata WHERE table_name = \'Sample_Env\'')$description, "VP08")
  expect_identical(nrow(DBI::dbReadTable(sqlite, "Sample_Veg")), 1633L)
  expect_identical(DBI::dbGetQuery(sqlite, 'PRAGMA integrity_check')[[1L]][[1L]], "ok")
  expect_identical(DBI::dbGetQuery(sqlite, 'SELECT source_md5 FROM _vpro_access_source')$source_md5, unname(before))
  expect_identical(DBI::dbGetQuery(sqlite, 'SELECT COUNT(*) AS n FROM _vpro_access_columns WHERE table_name = \'Sample_Env\'')$n[[1L]], 112L)
  expect_snapshot(error = TRUE, vpro_access_archive(copy, archive_path, max_rows_per_table = 2000L))
  expect_snapshot(error = TRUE, vpro_access_archive(copy, file.path(root, "too-small.db"), max_rows_per_table = 1L))
  expect_identical(file.exists(file.path(root, "too-small.db")), FALSE)
  oversized_source <- file.path(root, "oversized-source.db")
  expect_error(
    vpro_access_archive(copy, oversized_source, max_source_bytes = file.info(copy)$size - 1),
    "exceeds the source file size limit"
  )
  expect_false(file.exists(oversized_source))
  oversized_table <- file.path(root, "oversized-table.db")
  expect_error(
    vpro_access_archive(copy, oversized_table, max_rows_per_table = 2000L, max_table_bytes = 0),
    "exceeds the materialized table size limit"
  )
  expect_false(file.exists(oversized_table))
  for (arg in list(list(max_source_bytes = NA_real_), list(max_table_bytes = Inf), list(max_table_bytes = -1))) {
    expect_error(
      do.call(vpro_access_archive, c(list(copy, file.path(root, "invalid-limit.db")), arg)),
      "nonnegative finite byte count"
    )
  }
  expect_false(file.exists(file.path(root, "invalid-limit.db")))
})

test_that("older Access families remain archives rather than VP08 projects", {
  access <- normalizePath(file.path(testthat::test_path("..", "..", ".."), "VPRO_ACCESS", "VPro64", "Templates", "TemplateVProXP.mdb"), mustWork = FALSE)
  skip_if_not(file.exists(access), "Optional historical Access fixture unavailable")
  root <- withr::local_tempdir()
  copy <- file.path(root, "historical.mdb")
  file.copy(access, copy)
  before <- tools::md5sum(copy)
  archive <- file.path(root, "historical.db")
  receipt <- vpro_access_archive(copy, archive, max_rows_per_table = 1000L)
  expect_identical(file.exists(archive), TRUE)
  expect_identical(receipt$tables$description[match("VProXP_Env", receipt$tables$table_name)], "VP05")
  expect_identical(unname(tools::md5sum(copy)), unname(before))
  promoted <- file.path(root, "unsupported.db")
  expect_snapshot(error = TRUE, vpro_access_promote_vp08(archive, "VProXP", promoted))
  expect_identical(file.exists(promoted), FALSE)
})

test_that("VP08 promotion preserves data and refuses uncertain conversions", {
  access <- normalizePath(file.path(testthat::test_path("..", "..", ".."), "VPRO_ACCESS", "VPro64", "VPro64.accdb"), mustWork = FALSE)
  skip_if_not(file.exists(access), "Optional Access fixture unavailable")
  root <- withr::local_tempdir()
  copy <- file.path(root, "source.accdb")
  file.copy(access, copy)
  archive <- file.path(root, "archive.db")
  vpro_access_archive(copy, archive, max_rows_per_table = 2000L)
  promoted <- file.path(root, "promoted.db")
  expect_identical(vpro_access_promote_vp08(archive, "Sample", promoted), normalizePath(promoted))
  expect_identical(vpro_project_inspect(promoted, "Sample")$compatible, TRUE)
  result <- DBI::dbConnect(RSQLite::SQLite(), promoted)
  withr::defer(DBI::dbDisconnect(result))
  expect_identical(DBI::dbGetQuery(result, 'SELECT COUNT(*) AS n FROM "Sample_Veg"')$n[[1L]], 1633L)
  expect_identical(nrow(DBI::dbGetQuery(result, 'PRAGMA foreign_key_check')), 0L)
  expect_snapshot(error = TRUE, vpro_access_promote_vp08(archive, "Sample", promoted))

  staging <- DBI::dbConnect(RSQLite::SQLite(), archive)
  DBI::dbExecute(staging, "UPDATE _table_metadata SET description = 'VP07' WHERE table_name = 'Sample_Env'")
  DBI::dbDisconnect(staging)
  older <- file.path(root, "older.db")
  expect_snapshot(error = TRUE, vpro_access_promote_vp08(archive, "Sample", older))
  expect_identical(file.exists(older), FALSE)
  staging <- DBI::dbConnect(RSQLite::SQLite(), archive)
  DBI::dbExecute(staging, "UPDATE _table_metadata SET description = 'VP08' WHERE table_name = 'Sample_Env'")
  DBI::dbExecute(staging, 'ALTER TABLE "Sample_Admin" ADD COLUMN "Custom" TEXT')
  DBI::dbDisconnect(staging)
  drift <- file.path(root, "drift.db")
  expect_snapshot(error = TRUE, vpro_access_promote_vp08(archive, "Sample", drift))
  expect_identical(file.exists(drift), FALSE)
})
