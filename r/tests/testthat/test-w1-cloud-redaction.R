# W1 cloud redaction / PG spec parity (ENG-XCUT-002, ENG-XCUT-003, ENG-R-004).

test_that("sensitive-plot coordinates match Go MaskSensitiveEnvRow, incl. XCoord/YCoord", {
  env_df <- data.frame(
    PlotNumber = c("00337", "00338"),
    Latitude = c(49.123456, 49.123456),
    Longitude = c(-123.654321, -123.654321),
    UTMEasting = c(452345.6, 452345.6),
    UTMNorthing = c(5441234.5, 5441234.5),
    UTMZone = c("10", "10"),
    XCoord = c(452345.6, 452345.6),
    YCoord = c(5441234.5, 5441234.5),
    stringsAsFactors = FALSE
  )
  out <- vpro:::.vpro_redact_coord_df(env_df, "00337")
  # Go reference output (evidence/ENG-XCUT-002): 49.1 -123.6 450000 5.44e+06 zone 10.
  expect_identical(out$Latitude[[1]], 49.1)
  expect_identical(out$Longitude[[1]], -123.6)
  expect_identical(out$UTMEasting[[1]], 450000)
  expect_identical(out$UTMNorthing[[1]], 5440000)
  expect_identical(out$XCoord[[1]], 450000)
  expect_identical(out$YCoord[[1]], 5440000)
  expect_identical(out$UTMZone[[1]], "10")
  # Non-sensitive plot untouched.
  expect_identical(out[2, ], env_df[2, ])

  deg <- data.frame(PlotNumber = "A", XCoord = -123.654321, YCoord = 49.123456)
  out_deg <- vpro:::.vpro_redact_coord_df(deg, "A")
  expect_identical(out_deg$XCoord, -123.6)
  expect_identical(out_deg$YCoord, 49.1)
})

test_that("sensitive taxa are Red/Blue accepted codes only, matching Go", {
  tmp_vl <- tempfile(fileext = ".db")
  on.exit(unlink(tmp_vl), add = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp_vl)
  DBI::dbExecute(con, 'CREATE TABLE "USysSppAttributes" ("Code" TEXT, "Codetype" TEXT, "RedBlueList" TEXT)')
  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO \"USysSppAttributes\" VALUES",
      "('RARE_R','V','R'), ('BLUE_B','V','blue'), ('SECURE_Y','V','Y'),",
      "('NODATA_Z','V','Z'), ('SYN_R','S','R'), ('NULLTYPE_R',NULL,'RED')"
    )
  )
  DBI::dbDisconnect(con)
  codes <- vpro:::.vpro_sensitive_species_codes(pg = NULL, vlists_path = tmp_vl)
  expect_identical(sort(codes), c("BLUE_B", "NULLTYPE_R", "RARE_R"))
})

test_that("R PG bootstrap creates standards.usys_spp_attributes and caches the staging GUC", {
  stmts <- vpro:::vpro_pg_build_v1_migration_stmts()
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS standards.\"usys_spp_attributes\"", stmts, fixed = TRUE)))
  expect_true(any(grepl("idx_standards_spp_attr_code", stmts, fixed = TRUE)))
  trigger <- stmts[grepl("CREATE OR REPLACE FUNCTION staging.enforce_staging_child_insert", stmts, fixed = TRUE)]
  expect_length(trigger, 1L)
  expect_match(trigger, "current_setting('vpro.verified_sub_id', true)", fixed = TRUE)
  expect_match(trigger, "set_config('vpro.verified_sub_id', cache_key, true)", fixed = TRUE)
})

test_that("vpro_sha256_file returns a real SHA-256 without PATH binaries", {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeBin(charToRaw("abc"), f)
  want <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  expect_identical(vpro:::vpro_sha256_file(f), want)
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)
  Sys.setenv(PATH = "")
  expect_identical(vpro:::vpro_sha256_file(f), want)
})

# Differential: R PG specs must match app/internal/cloudsync/columns_schemas.go.
.w1_go_specs <- function(path) {
  src <- readLines(path, warn = FALSE)
  out <- list()
  current <- NULL
  for (line in src) {
    m <- regmatches(line, regexec("^var ([A-Za-z0-9]+)Columns = \\[\\]ColumnSpec\\{", line))[[1]]
    if (length(m) == 2L) {
      current <- m[[2]]
      out[[current]] <- list()
      next
    }
    if (!is.null(current) && grepl("^}", line)) {
      current <- NULL
      next
    }
    if (is.null(current)) next
    m <- regmatches(line, regexec('^\\s*([tifb])Col\\("([^"]+)"(?:, "([^"]+)")?(?:, ([0-9]+|true|false))?\\)', line))[[1]]
    if (length(m) == 0L) next
    kind <- m[[2]]
    extra <- m[[5]]
    out[[current]][[length(out[[current]]) + 1L]] <- data.frame(
      name = m[[3]],
      pg_type = switch(kind, t = "TEXT", i = "BIGINT", f = "DOUBLE PRECISION", b = "SMALLINT"),
      is_bool = kind == "b",
      is_cover = kind == "f" && identical(extra, "true"),
      utf16_max = if (kind == "t" && nzchar(extra)) as.integer(extra) else 0L,
      stringsAsFactors = FALSE
    )
  }
  lapply(out, function(rows) do.call(rbind, rows))
}

test_that("R cloud_pg_specs matches Go columns_schemas on every column", {
  go_path <- normalizePath(
    file.path(testthat::test_path(), "..", "..", "..", "app", "internal", "cloudsync", "columns_schemas.go"),
    mustWork = FALSE
  )
  skip_if_not(file.exists(go_path), "Go sources not available (installed package)")
  go <- .w1_go_specs(go_path)
  pairs <- c(
    VP08Env = "Env", VP08Admin = "Admin", VP08Veg = "Veg", VP08Humus = "Humus",
    VP08Mineral = "Mineral", VP08Other = "Other", VP08Metadata = "Metadata", VP08Audit = "Audit",
    StandardsUSysAllSpecs = "usys_all_specs", StandardsUSysTableOfLists = "usys_table_of_lists",
    StandardsBECSiteSeries = "bec_site_series", StandardsMasterSiteUnitList = "master_site_unit_list",
    StandardsUSysZoneList = "usys_zone_list", StandardsUSysSppAttributes = "usys_spp_attributes",
    StandardsProjectMetadata = "project_metadata"
  )
  cols <- c("name", "pg_type", "is_bool", "is_cover", "utf16_max")
  for (go_name in names(pairs)) {
    r_name <- pairs[[go_name]]
    r_spec <- if (startsWith(go_name, "VP08")) {
      vpro:::.vpro_pg_vp08_spec_map[[r_name]]
    } else {
      vpro:::.vpro_pg_standards_spec_map[[r_name]]
    }
    expect_false(is.null(go[[go_name]]), info = go_name)
    expect_false(is.null(r_spec), info = r_name)
    g <- go[[go_name]][, cols]
    r <- as.data.frame(r_spec)[, cols]
    rownames(g) <- NULL
    rownames(r) <- NULL
    expect_identical(r, g, info = paste(go_name, "vs", r_name))
  }
})
