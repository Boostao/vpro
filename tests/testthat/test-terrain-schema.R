make_terrain_schema_fixture <- function(path, project, columns = NULL) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!is.null(columns)) {
    DBI::dbExecute(con, paste0('CREATE TABLE "', project, '_Env" (', columns, ')'))
  }
  invisible(path)
}

test_that("canonical SQLite fields have unknown declared widths", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  result <- vpro_terrain_inspect_schema(path, "Sample")
  expect_identical(nrow(result), 8L)
  expect_identical(result$expected_size, c(3L, 6L, 3L, 3L, 3L, 6L, 3L, 3L))
  expect_identical(result$declared_type, rep("VARCHAR", 8))
  expect_identical(result$actual_size, rep(NA_integer_, 8))
  expect_identical(result$status, rep("unknown", 8))
})

test_that("terrain diagnostics distinguish narrow, wide, missing and non-text fields", {
  path <- tempfile(fileext = ".db")
  make_terrain_schema_fixture(
    path,
    "Old",
    '"terraintexturesurf" VARCHAR(2), "SurficialMaterialSurf" TEXT(6), "SurfaceExpSurf" VARCHAR(3), "GeoMorProSurf" TEXT(6), "TerrainTextureSubSurf" VARCHAR, "SurficialMaterialSubSurf" INTEGER, "SurfaceExpSubSurf" TEXT(3)'
  )
  before <- unname(tools::md5sum(path))
  result <- vpro_terrain_inspect_schema(path, "Old")
  expect_identical(result$status, c("undersized", "match", "match", "oversized", "unknown", "non_text", "match", "missing_field"))
  expect_identical(result$actual_size, c(2L, 6L, 3L, 6L, NA_integer_, NA_integer_, 3L, NA_integer_))
  expect_identical(unname(tools::md5sum(path)), before)
})

test_that("terrain diagnostics distinguish missing table and invalid paths", {
  path <- tempfile(fileext = ".db")
  make_terrain_schema_fixture(path, "Other", '"SurfaceExpSurf" TEXT(3)')
  expect_identical(vpro_terrain_inspect_schema(path, "Absent")$status, rep("missing_table", 8))
  expect_snapshot(error = TRUE, vpro_terrain_inspect_schema("missing.db", "Old"))
  expect_snapshot(error = TRUE, vpro_terrain_inspect_schema(path, "bad project"))
})
