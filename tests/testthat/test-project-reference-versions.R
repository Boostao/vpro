test_that("reference versions use latest audit events without older-value fallback", {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, 'DELETE FROM "Sample_Audit" WHERE "Table" IN (\'USysAllSpecs\', \'USysTableOfLists\')')
  DBI::dbExecute(
    sqlite,
    paste(
      'INSERT INTO "Sample_Audit" ("Table", "EditWhen", "AfterEdit") VALUES',
      "('USysAllSpecs', '2020-01-01 00:00:00', 'old'),",
      "('USysAllSpecs', '2022-01-01 00:00:00', ''),",
      "('USysTableOfLists', '2021-01-01 00:00:00', 'list-v1')"
    )
  )
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  before <- tools::md5sum(path)

  found <- vpro_project_reference_versions(context)
  expect_identical(found$Table, c("USysAllSpecs", "USysTableOfLists"))
  expect_identical(found$Version, c("Unknown", "list-v1"))
  expect_identical(found$Status, c("unknown", "ok"))
  expect_identical(found$LatestRows, c(1L, 1L))
  expect_match(found$EditWhen[[1L]], "2022-01-01")
  expect_identical(unname(tools::md5sum(path)), unname(before))
  expect_identical(context$active$project, "Sample")
})

test_that("reference versions report equal latest timestamps as ambiguous", {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, 'DELETE FROM "Sample_Audit" WHERE "Table" IN (\'USysAllSpecs\', \'USysTableOfLists\')')
  DBI::dbExecute(
    sqlite,
    paste(
      'INSERT INTO "Sample_Audit" ("Table", "EditWhen", "AfterEdit") VALUES',
      "('USysAllSpecs', NULL, 'first'),",
      "('USysAllSpecs', NULL, 'second')"
    )
  )
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")

  found <- vpro_project_reference_versions(context)
  expect_identical(found$Version, c(NA_character_, "Unknown"))
  expect_identical(found$Status, c("ambiguous", "missing"))
  expect_identical(found$LatestRows, c(2L, 0L))
  expect_identical(found$EditWhen, c(NA_character_, NA_character_))

  DBI::dbExecute(
    sqlite,
    paste(
      'INSERT INTO "Sample_Audit" ("Table", "EditWhen", "AfterEdit") VALUES',
      "('USysAllSpecs', '2024-01-01 00:00:00', 'same'),",
      "('USysAllSpecs', '2024-01-01 00:00:00', 'same'),",
      "('USysTableOfLists', NULL, NULL)"
    )
  )
  found <- vpro_project_reference_versions(context)
  expect_identical(found$Version, c(NA_character_, "Unknown"))
  expect_identical(found$Status, c("ambiguous", "unknown"))
  expect_identical(found$LatestRows, c(2L, 1L))
  expect_match(found$EditWhen[[1L]], "2024-01-01")
})

test_that("reference versions require an active project", {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  expect_snapshot(error = TRUE, vpro_project_reference_versions(context))
})
