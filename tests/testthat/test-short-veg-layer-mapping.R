test_that("versioned short-vegetation layer mapping preserves Access keys", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  script <- file.path(root, "data-raw", "projects", "build-short-veg-layer-mapping.R")
  canonical_output <- file.path(root, "data-raw", "projects", "short-veg-layer-mapping-v1.sqlite")
  canonical_before <- readBin(canonical_output, "raw", n = file.info(canonical_output)$size)
  source(script, local = TRUE)
  expect_identical(
    readBin(canonical_output, "raw", n = file.info(canonical_output)$size),
    canonical_before
  )

  output <- tempfile(fileext = ".sqlite")
  expect_identical(build_short_veg_layer_mapping(output_path = output), normalizePath(output, winslash = "/"))
  con <- DBI::dbConnect(RSQLite::SQLite(), output)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  metadata <- DBI::dbGetQuery(con, "SELECT * FROM mapping_set")
  expect_identical(metadata$version, "access-layercode-v1")
  expect_identical(metadata$created_date, "2026-09-23")
  expect_identical(metadata$source_path, "data-raw/vpro/LayerCode.csv")
  expect_identical(metadata$source_sha256, short_veg_layer_mapping_sha256(
    file.path(root, "data-raw", "vpro", "LayerCode.csv")
  ))
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM layer_mapping")$n, 17L)

  report_keys <- data.frame(Layer1234567 = c("1", "5a", "6", "7"))
  DBI::dbWriteTable(con, "report_keys", report_keys)
  joined <- DBI::dbGetQuery(con, paste(
    "SELECT report_keys.Layer1234567, layer_mapping.LayerCode, layer_mapping.Strata",
    "FROM report_keys JOIN layer_mapping",
    "ON report_keys.Layer1234567 = layer_mapping.Layer1234567",
    "ORDER BY report_keys.rowid"
  ))
  expect_identical(joined$LayerCode, c("01", "05a", "06", "07"))
  expect_identical(joined$Strata, c("A", "B", "C", "D"))

  expect_error(
    DBI::dbExecute(con, "INSERT INTO layer_mapping (LayerCode) VALUES ('01')"),
    "UNIQUE constraint failed"
  )
  expect_error(
    DBI::dbExecute(con, "INSERT INTO layer_mapping (LayerCode, Layer1234567) VALUES ('99', '1')"),
    "UNIQUE constraint failed"
  )
})

test_that("invalid CSV leaves an existing output untouched", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  script <- file.path(root, "data-raw", "projects", "build-short-veg-layer-mapping.R")
  source(script, local = TRUE)

  output <- tempfile(fileext = ".sqlite")
  writeBin(charToRaw("existing output"), output)
  invalid_csv <- tempfile(fileext = ".csv")
  writeLines("not,a,valid,LayerCode,CSV", invalid_csv)

  expect_error(
    build_short_veg_layer_mapping(output_path = output, source_csv = invalid_csv),
    "18 nonblank physical rows"
  )
  expect_identical(readBin(output, "raw", n = file.info(output)$size), charToRaw("existing output"))
})
