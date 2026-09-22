create_schema_fixture <- function(path, project, env_sql = NULL, omit = character()) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  suffixes <- c("Admin", "Audit", "Env", "Humus", "Metadata", "Mineral", "Other", "Veg")
  for (suffix in setdiff(suffixes, omit)) {
    table <- DBI::dbQuoteIdentifier(con, paste0(project, "_", suffix))
    columns <- if (identical(suffix, "Env") && !is.null(env_sql)) {
      env_sql
    } else {
      '"ID" INTEGER'
    }
    DBI::dbExecute(con, paste("CREATE TABLE", table, paste0("(", columns, ")")))
  }
  invisible(path)
}

test_that("a project matches an identical template", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")

  result <- vpro_project_compare_schema(
    path,
    "Sample",
    template_path = path,
    template_project = "Sample"
  )

  expect_identical(
    names(result),
    c("table", "field", "difference", "expected", "actual")
  )
  expect_identical(nrow(result), 0L)
})

test_that("schema comparison reports Access field differences", {
  template_path <- tempfile(fileext = ".db")
  project_path <- tempfile(fileext = ".db")
  create_schema_fixture(
    template_path,
    "Gold",
    env_sql = '"Code" VARCHAR(7), "Measure" DOUBLE, "RequiredField" INTEGER'
  )
  create_schema_fixture(
    project_path,
    "Alpha",
    env_sql = '"code" VARCHAR(9), "Measure" REAL, "ExtraField" TEXT'
  )

  result <- vpro_project_compare_schema(
    project_path,
    "Alpha",
    template_path,
    "Gold"
  )

  expect_identical(result$table, rep("Alpha_Env", 3))
  expect_identical(result$field, c("Code", "Measure", "RequiredField"))
  expect_identical(result$difference, c("Size", "Type", "Missing"))
  expect_identical(result$expected, c("7", "DOUBLE", "RequiredField"))
  expect_identical(result$actual, c("9", "REAL", NA_character_))
  expect_equal(sum(result$field == "ExtraField"), 0)
})

test_that("schema comparison reports a missing project table", {
  template_path <- tempfile(fileext = ".db")
  project_path <- tempfile(fileext = ".db")
  create_schema_fixture(template_path, "Gold")
  create_schema_fixture(project_path, "Alpha", omit = "Veg")

  result <- vpro_project_compare_schema(
    project_path,
    "Alpha",
    template_path,
    "Gold"
  )

  expect_identical(result$table, "Alpha_Veg")
  expect_identical(result$field, NA_character_)
  expect_identical(result$difference, "Missing table")
  expect_identical(result$expected, "Gold_Veg")
  expect_identical(result$actual, NA_character_)
})

test_that("schema comparison validates projects and template resources", {
  path <- tempfile(fileext = ".db")
  create_schema_fixture(path, "Alpha")

  expect_snapshot(error = TRUE, vpro_project_compare_schema("missing.db", "Alpha"))
  expect_snapshot(error = TRUE, vpro_project_compare_schema(path, "not valid"))
  expect_snapshot(
    error = TRUE,
    vpro_project_compare_schema(path, "Alpha", "missing-template.db")
  )
  expect_snapshot(
    error = TRUE,
    vpro_project_compare_schema(path, "Alpha", path, "Absent")
  )
})
