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

test_that("cloud_rds_bundle roxygen documents ~10 km grid generalization and fail-closed RedBlueList check", {
  rds_src <- normalizePath(
    file.path(testthat::test_path(), "..", "..", "R", "cloud_rds_bundle.R"),
    mustWork = FALSE
  )
  skip_if_not(file.exists(rds_src), "R source files not available (installed package)")
  lines <- readLines(rds_src, warn = FALSE)
  hdr <- paste(lines[1:40], collapse = "\n")
  expect_match(hdr, "XCoord", fixed = TRUE)
  expect_match(hdr, "YCoord", fixed = TRUE)
  expect_match(hdr, "preserving `UTMZone`", fixed = TRUE)
  expect_false(grepl("`UTMZone`\\) to `NA`", hdr))
})

test_that("vpro_export_rds and CSV snapshot fail closed when RedBlueList is empty or missing, while redact_sensitive = FALSE succeeds", {
  td <- tempfile("vpro-w1r-rds-")
  dir.create(file.path(td, "projects"), recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)

  ws_sample <- vpro_connect("Sample")
  proj_copy <- file.path(td, "projects", "SampleUnred.db")
  bundled_vl <- file.path(td, "VLists.db")
  file.copy(ws_sample$project_path, proj_copy)
  file.copy(ws_sample$vlists_path, bundled_vl)

  ws <- vpro_connect(proj_copy, su = "Sample_SU", data_dir = td)
  ws$vlists_path <- bundled_vl

  # 1. Bundled VLists.db has 0 Red/Blue rows: redact_sensitive = TRUE must fail loud and write nothing.
  expect_error(
    vpro:::.vpro_sensitive_species_codes(pg = NULL, vlists_path = bundled_vl),
    "0 Red/Blue-listed species rows"
  )
  expect_identical(
    vpro:::.vpro_sensitive_species_codes(pg = NULL, vlists_path = bundled_vl, require_populated = FALSE),
    character(0)
  )

  rds_blocked <- file.path(td, "blocked_redacted.rds")
  expect_error(
    vpro_export_rds(ws, path = rds_blocked, compress = "gzip", redact_sensitive = TRUE),
    "0 Red/Blue-listed species rows"
  )
  expect_false(file.exists(rds_blocked))

  csv_out_dir <- file.path(td, "csv_blocked")
  dir.create(csv_out_dir)
  prov_stub <- list(
    created_at = "2026-11-19T00:00:00Z",
    created_by = "qa",
    plot_count = 52L,
    veg_count = 100L,
    bec_version = "BECdb_v13_2026",
    taxonomy_version = "BCPlantTaxa_v19_2025",
    tail_audit_hash = strrep("0", 64L),
    notes = NA_character_
  )
  expect_error(
    vpro:::vpro_write_snapshot_csv_bundle(
      ws = ws,
      snapshot_tag = "BlockedSnap",
      out_dir_abs = csv_out_dir,
      provenance = prov_stub,
      redact_sensitive = TRUE
    ),
    "0 Red/Blue-listed species rows"
  )
  expect_false(file.exists(file.path(csv_out_dir, "BlockedSnap_csv.tar.gz")))

  # 2. Even if <Project>_Veg has 0 rows, redact_sensitive = TRUE still fails closed on unpopulated VLists.db.
  empty_veg_proj <- file.path(td, "projects", "EmptyVeg.db")
  file.copy(proj_copy, empty_veg_proj)
  ev_con <- DBI::dbConnect(RSQLite::SQLite(), empty_veg_proj)
  DBI::dbExecute(ev_con, 'DELETE FROM "Sample_Veg"')
  DBI::dbDisconnect(ev_con)
  ws_empty_veg <- vpro_connect(empty_veg_proj, su = "Sample_SU", data_dir = td)
  ws_empty_veg$vlists_path <- bundled_vl
  rds_blocked_ev <- file.path(td, "blocked_empty_veg.rds")
  expect_error(
    vpro_export_rds(ws_empty_veg, path = rds_blocked_ev, compress = "gzip", redact_sensitive = TRUE),
    "0 Red/Blue-listed species rows"
  )
  expect_false(file.exists(rds_blocked_ev))

  # 3. Missing USysSppAttributes table and Z/Y/S-synonym-only rows also fail loud.
  no_tbl_vl <- file.path(td, "VLists_NoTbl.db")
  nt_con <- DBI::dbConnect(RSQLite::SQLite(), no_tbl_vl)
  DBI::dbExecute(nt_con, 'CREATE TABLE "USysAllSpecs" ("Code" TEXT, "OldCode" TEXT)')
  DBI::dbDisconnect(nt_con)
  ws_no_tbl <- ws
  ws_no_tbl$vlists_path <- no_tbl_vl
  expect_error(
    vpro_export_rds(ws_no_tbl, path = file.path(td, "no_tbl.rds"), compress = "gzip", redact_sensitive = TRUE),
    "USysSppAttributes.*missing"
  )

  z_only_vl <- file.path(td, "VLists_ZOnly.db")
  z_con <- DBI::dbConnect(RSQLite::SQLite(), z_only_vl)
  DBI::dbExecute(z_con, 'CREATE TABLE "USysSppAttributes" ("Code" TEXT, "Codetype" TEXT, "RedBlueList" TEXT)')
  DBI::dbExecute(
    z_con,
    "INSERT INTO \"USysSppAttributes\" VALUES ('NODATA','V','Z'), ('YELLOW','V','Y'), ('SYNR','S','R')"
  )
  DBI::dbDisconnect(z_con)
  ws_z_only <- ws
  ws_z_only$vlists_path <- z_only_vl
  expect_error(
    vpro_export_rds(ws_z_only, path = file.path(td, "z_only.rds"), compress = "gzip", redact_sensitive = TRUE),
    "0 Red/Blue-listed species rows"
  )

  # 4. Missing vlists_path file fails loud instead of silently falling back.
  ws_missing_vl <- ws
  ws_missing_vl$vlists_path <- file.path(td, "does_not_exist.db")
  expect_error(
    vpro_export_rds(ws_missing_vl, path = file.path(td, "missing_vl.rds"), compress = "gzip", redact_sensitive = TRUE),
    "was not found"
  )

  # 5. redact_sensitive = FALSE (and default unredacted local export) continues to work normally.
  rds_ok <- file.path(td, "allowed_unredacted.rds")
  res_ok <- vpro_export_rds(ws, path = rds_ok, compress = "gzip", redact_sensitive = FALSE)
  expect_true(file.exists(res_ok$path))
  env_orig <- vpro_env(ws, scope = "project")
  env_unred <- vpro_env(vpro_import_rds(res_ok$path), scope = "project")
  expect_identical(
    env_unred$Latitude[env_unred$PlotNumber == "00337"],
    env_orig$Latitude[env_orig$PlotNumber == "00337"]
  )

  csv_ok <- vpro:::vpro_write_snapshot_csv_bundle(
    ws = ws,
    snapshot_tag = "AllowedSnap",
    out_dir_abs = csv_out_dir,
    provenance = prov_stub,
    redact_sensitive = FALSE
  )
  expect_true(file.exists(csv_ok$path))
})

.w1_ensure_mock_pg_class <- function() {
  if (!methods::isClass("VProMockRedactionConn", where = .GlobalEnv)) {
    methods::setClass(
      "VProMockRedactionConn",
      contains = "DBIConnection",
      slots = c(state = "environment"),
      where = .GlobalEnv
    )
    methods::setMethod(DBI::dbIsValid, "VProMockRedactionConn", function(dbObj, ...) {
      isTRUE(dbObj@state$valid)
    }, where = .GlobalEnv)
    methods::setMethod(DBI::dbDisconnect, "VProMockRedactionConn", function(conn, ...) {
      conn@state$valid <- FALSE
      invisible(TRUE)
    }, where = .GlobalEnv)
    methods::setMethod(
      DBI::dbExecute,
      signature(conn = "VProMockRedactionConn", statement = "character"),
      function(conn, statement, ...) 0L,
      where = .GlobalEnv
    )
    methods::setMethod(
      DBI::dbGetQuery,
      signature(conn = "VProMockRedactionConn", statement = "character"),
      function(conn, statement, ...) {
        conn@state$query_fn(statement, list(...)$params)
      },
      where = .GlobalEnv
    )
  }
}

.w1_make_mock_pg <- function(role = "contributor", has_pg_attr = TRUE, pg_codes = character()) {
  .w1_ensure_mock_pg_class()
  empty_spec_df <- function(sfx) {
    spec <- vpro:::vpro_pg_vp08_specs(sfx)
    cols <- lapply(seq_len(nrow(spec)), function(i) {
      tp <- spec$pg_type[[i]]
      if (tp == "TEXT") character() else if (tp == "DOUBLE PRECISION") numeric() else integer()
    })
    names(cols) <- spec$name
    as.data.frame(cols, stringsAsFactors = FALSE)
  }

  env_df <- empty_spec_df("Env")[c(1L, 2L), , drop = FALSE]
  rownames(env_df) <- NULL
  env_df$PlotNumber <- c("00337", "00338")
  env_df$ProjectID <- c("P_QA", "P_QA")
  env_df$Zone <- c("CWH", "CWH")
  env_df$SubZone <- c("vm1", "vm1")
  env_df$SiteSeries <- c("01", "01")
  env_df$Latitude <- c(49.123456, 50.987654)
  env_df$Longitude <- c(-123.654321, -124.876543)
  env_df$UTMEasting <- c(452345.6, 368765.4)
  env_df$UTMNorthing <- c(5441234.5, 5651234.5)
  env_df$UTMZone <- c("10", "10")
  env_df$XCoord <- c(452345.6, 368765.4)
  env_df$YCoord <- c(5441234.5, 5651234.5)
  env_df$Flag <- c(0L, 0L)

  adm_df <- empty_spec_df("Admin")[c(1L, 2L), , drop = FALSE]
  rownames(adm_df) <- NULL
  adm_df$Plot <- c("00337", "00338")
  adm_df$BECSiteUnit <- c("CWHvm1/01", "CWHvm1/01")
  adm_df$UpdatedFromCards <- c(0L, 0L)

  veg_df <- empty_spec_df("Veg")[c(1L, 2L), , drop = FALSE]
  rownames(veg_df) <- NULL
  veg_df$PlotNumber <- c("00337", "00338")
  veg_df$Species <- c("ABIELAS", "TSUGHET")
  veg_df$Layer <- c("1", "1")
  veg_df$Cover1 <- c(25.0, 40.0)
  veg_df$Flag <- c(0L, 0L)
  veg_df$ID <- c(101L, 102L)

  st <- new.env(parent = emptyenv())
  st$valid <- TRUE
  st$query_fn <- function(sql, params) {
    if (grepl("information_schema\\.tables.*usys_spp_attributes", sql)) {
      return(data.frame(ok = isTRUE(has_pg_attr), stringsAsFactors = FALSE))
    }
    if (grepl("FROM standards\\.usys_spp_attributes", sql)) {
      return(data.frame(code = as.character(pg_codes), stringsAsFactors = FALSE))
    }
    if (grepl("FROM standards\\.usys_all_specs", sql)) {
      return(data.frame(
        Code = character(),
        OldCode = character(),
        ScientificName = character(),
        EnglishName = character(),
        Lifeform = integer(),
        Codetype = character(),
        stringsAsFactors = FALSE
      ))
    }
    if (grepl('SELECT CAST\\(e\\."PlotNumber" AS TEXT\\) AS "PlotNumber" FROM becmaster\\.env', sql)) {
      return(data.frame(PlotNumber = c("00337", "00338"), stringsAsFactors = FALSE))
    }
    if (grepl("FROM becmaster\\.env AS e", sql) && grepl("LEFT JOIN becmaster\\.admin", sql)) {
      out <- cbind(env_df, SiteUnit = c("CWHvm1/01", "CWHvm1/01"), BECSiteUnit = c("CWHvm1/01", "CWHvm1/01"))
      return(out)
    }
    if (grepl("SELECT DISTINCT CAST\\(\"PlotNumber\" AS TEXT\\).*FROM becmaster\\.veg", sql)) {
      hits <- if ("ABIELAS" %in% toupper(pg_codes)) "00337" else character()
      return(data.frame(PlotNumber = hits, stringsAsFactors = FALSE))
    }
    if (grepl('FROM becmaster\\."env"', sql)) return(env_df)
    if (grepl('FROM becmaster\\."admin"', sql)) return(adm_df)
    if (grepl('FROM becmaster\\."veg"', sql)) return(veg_df)
    if (grepl('FROM becmaster\\."humus"', sql)) return(empty_spec_df("Humus"))
    if (grepl('FROM becmaster\\."mineral"', sql)) return(empty_spec_df("Mineral"))
    if (grepl('FROM becmaster\\."other"', sql)) return(empty_spec_df("Other"))
    if (grepl('FROM becmaster\\."audit"', sql)) return(empty_spec_df("Audit"))
    if (grepl("FROM becmaster\\.metadata", sql)) return(empty_spec_df("Metadata"))
    if (grepl("FROM standards\\.library_releases", sql)) {
      return(data.frame(
        bec_version = "BECdb_v13_2026",
        taxonomy_version = "BCPlantTaxa_v19_2025",
        stringsAsFactors = FALSE
      ))
    }
    if (grepl("SELECT COALESCE\\(\\(SELECT row_hash FROM becmaster\\.audit", sql)) {
      return(data.frame(tail_hash = strrep("0", 64L), stringsAsFactors = FALSE))
    }
    if (grepl("INSERT INTO becmaster\\.download_log", sql)) {
      return(data.frame(id = 1L, stringsAsFactors = FALSE))
    }
    if (grepl("SELECT current_user AS usr", sql)) {
      return(data.frame(usr = "qa_custodian", stringsAsFactors = FALSE))
    }
    if (grepl("INSERT INTO becmaster\\.snapshots", sql)) {
      return(data.frame(
        snapshot_tag = as.character(params[[1L]]),
        created_at = "2026-11-19T12:00:00Z",
        created_by = "qa_custodian",
        stringsAsFactors = FALSE
      ))
    }
    stop("Unexpected SQL in VProMockRedactionConn: ", sql)
  }

  structure(
    list(
      conn = methods::new(methods::getClassDef("VProMockRedactionConn", where = .GlobalEnv), state = st),
      role = role,
      host = "127.0.0.1",
      port = 5432L,
      dbname = "becmaster_test",
      user = paste0("qa_", role),
      sslmode = "require",
      config_source = "args"
    ),
    class = "vpro_pg_conn"
  )
}

test_that("vpro_master_env, vpro_master_pull, and vpro_master_publish_snapshot fail closed on empty/missing conservation metadata", {
  td <- tempfile("vpro-w1r-pg-")
  dir.create(td, recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)

  withr::local_options(list(vpro.data_dir = td, vpro.vlists_path = NULL))

  # 1. Empty standards.usys_spp_attributes (0 Red/Blue rows) + bundled VLists.db (0 Red/Blue rows):
  contrib_empty <- .w1_make_mock_pg(role = "contributor", has_pg_attr = TRUE, pg_codes = character())
  custodian_empty <- .w1_make_mock_pg(role = "custodian", has_pg_attr = TRUE, pg_codes = character())

  expect_error(
    vpro_master_env(contrib_empty, zones = "CWH"),
    "0 Red/Blue-listed species rows"
  )
  # Custodian unredacted read works normally
  cust_env <- vpro_master_env(custodian_empty, zones = "CWH")
  expect_identical(nrow(cust_env), 2L)
  expect_identical(cust_env$Latitude[cust_env$PlotNumber == "00337"], 49.123456)

  # Contributor pull (default redact_sensitive = TRUE) fails loud and writes no SQLite file
  blocked_pull_db <- file.path(td, "BlockedPull.db")
  expect_error(
    vpro_master_pull(contrib_empty, dest_db = blocked_pull_db, project = "BlockedPull", zones = "CWH"),
    "0 Red/Blue-listed species rows"
  )
  expect_false(file.exists(blocked_pull_db))

  # Custodian pull (default redact_sensitive = FALSE) works normally
  ok_pull_db <- file.path(td, "CustodianPull.db")
  pulled_cust <- vpro_master_pull(custodian_empty, dest_db = ok_pull_db, project = "CustodianPull", zones = "CWH")
  expect_true(file.exists(pulled_cust$dest_path))
  expect_identical(pulled_cust$plot_count, 2L)

  # Custodian snapshot with redact_sensitive = TRUE fails loud and creates no snapshot directory/files
  blocked_snap_dir <- file.path(td, "snap_blocked")
  expect_error(
    vpro_master_publish_snapshot(
      custodian_empty,
      snapshot_tag = "Snap_Blocked",
      out_dir = blocked_snap_dir,
      formats = c("rds", "sqlite", "csv"),
      zones = "CWH",
      compress = "gzip",
      redact_sensitive = TRUE
    ),
    "0 Red/Blue-listed species rows"
  )
  expect_false(dir.exists(blocked_snap_dir))

  # Custodian snapshot with redact_sensitive = FALSE works normally
  ok_snap_dir <- file.path(td, "snap_unredacted")
  pub_unred <- vpro_master_publish_snapshot(
    custodian_empty,
    snapshot_tag = "Snap_Unred",
    out_dir = ok_snap_dir,
    formats = c("rds", "sqlite", "csv"),
    zones = "CWH",
    compress = "gzip",
    redact_sensitive = FALSE
  )
  expect_identical(pub_unred$plot_count, 2L)
  expect_true(all(file.exists(pub_unred$artifacts$path)))

  # 2. Missing standards.usys_spp_attributes AND missing local USysSppAttributes fails loud with missing-table error
  no_tbl_vl <- file.path(td, "NoAttrVLists.db")
  nt_con <- DBI::dbConnect(RSQLite::SQLite(), no_tbl_vl)
  DBI::dbExecute(nt_con, 'CREATE TABLE "USysAllSpecs" ("Code" TEXT, "OldCode" TEXT)')
  DBI::dbDisconnect(nt_con)
  withr::with_options(list(vpro.vlists_path = no_tbl_vl), {
    contrib_missing <- .w1_make_mock_pg(role = "contributor", has_pg_attr = FALSE, pg_codes = character())
    expect_error(
      vpro_master_pull(contrib_missing, dest_db = file.path(td, "MissingTbl.db"), project = "MissingTbl", zones = "CWH"),
      "USysSppAttributes.*missing"
    )
  })

  # 3. Populated PG standards.usys_spp_attributes ('ABIELAS') succeeds across sqlite/rds/csv even when local VLists.db has 0 rows
  custodian_pop <- .w1_make_mock_pg(role = "custodian", has_pg_attr = TRUE, pg_codes = "ABIELAS")
  red_snap_dir <- file.path(td, "snap_redacted_pg")
  pub_red <- vpro_master_publish_snapshot(
    custodian_pop,
    snapshot_tag = "Snap_RedPG",
    out_dir = red_snap_dir,
    formats = c("rds", "sqlite", "csv"),
    zones = "CWH",
    compress = "gzip",
    redact_sensitive = TRUE
  )
  expect_identical(pub_red$plot_count, 2L)
  rds_env <- vpro_env(vpro_import_rds(pub_red$artifacts$path[pub_red$artifacts$format == "rds"][[1L]]), scope = "project")
  hit_00337 <- rds_env[rds_env$PlotNumber == "00337", , drop = FALSE]
  safe_00338 <- rds_env[rds_env$PlotNumber == "00338", , drop = FALSE]
  expect_identical(hit_00337$Latitude, 49.1)
  expect_identical(hit_00337$Longitude, -123.6)
  expect_identical(as.double(hit_00337$UTMEasting), 450000)
  expect_identical(as.double(hit_00337$UTMNorthing), 5440000)
  expect_identical(hit_00337$UTMZone, "10")
  expect_identical(safe_00338$Latitude, 50.987654)
})
