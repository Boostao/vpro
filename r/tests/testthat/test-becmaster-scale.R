test_that("BECMaster_fixing (71,567 plots, 1.65M veg rows) meets all Wave 5 scale and parity gates", {
  skip_on_cran()
  skip_if_not(
    identical(Sys.getenv("VPRO_RUN_BECMASTER"), "true"),
    "Set VPRO_RUN_BECMASTER=true to run 545 MB BECMaster_fixing scale qualification"
  )

  cached_sqlite_candidates <- Sys.glob("/tmp/TestBECMasterProductionScaleQualification*/002/BECMaster_fixing.db")
  accdb_source <- "/home/bruno/Work/VPRO_ACCESS_1/VPro64/BECMaster_fixing.accdb"
  skip_if_not(length(cached_sqlite_candidates) > 0L || file.exists(accdb_source))

  work_db <- tempfile("vpro-becmaster-qual-", fileext = ".db")
  on.exit(unlink(c(work_db, paste0(work_db, "-wal"), paste0(work_db, "-shm"))), add = TRUE)

  if (length(cached_sqlite_candidates) > 0L) {
    src_db <- sort(cached_sqlite_candidates, decreasing = TRUE)[[1L]]
    expect_true(file.copy(src_db, work_db, overwrite = TRUE))
  } else {
    tmp_accdb <- tempfile("becmaster-src-", fileext = ".accdb")
    on.exit(unlink(tmp_accdb), add = TRUE)
    expect_true(file.copy(accdb_source, tmp_accdb, overwrite = TRUE))
    sha_before <- vpro:::vpro_sha256_file(tmp_accdb)
    imp <- vpro_import_access(tmp_accdb, target_db = work_db, batch_rows = 25000L)
    expect_equal(vpro:::vpro_sha256_file(tmp_accdb), sha_before)
    expect_gte(imp$plot_count, 71000L)
  }

  # Ensure PG_Cohort_SU exists (or build an SBSmk1/SBSwk1 cohort if imported fresh from .accdb)
  dbc_setup <- DBI::dbConnect(RSQLite::SQLite(), work_db)
  DBI::dbExecute(dbc_setup, "PRAGMA journal_mode = WAL")
  has_pg <- DBI::dbExistsTable(dbc_setup, "PG_Cohort_SU")
  total_env_plots <- DBI::dbGetQuery(dbc_setup, 'SELECT COUNT(*) AS n FROM "BECMaster_fixing_Env"')$n[[1L]]
  total_veg_rows <- DBI::dbGetQuery(dbc_setup, 'SELECT COUNT(*) AS n FROM "BECMaster_fixing_Veg"')$n[[1L]]
  DBI::dbDisconnect(dbc_setup)

  expect_gte(total_env_plots, 71500L)
  expect_gte(total_veg_rows, 1650000L)

  ws <- vpro_connect(work_db, su = if (has_pg) "PG_Cohort_SU" else "None")
  if (!has_pg) {
    dbc_tmp <- DBI::dbConnect(RSQLite::SQLite(), work_db, flags = RSQLite::SQLITE_RO)
    sbs_su <- DBI::dbGetQuery(
      dbc_tmp,
      paste(
        'SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber",',
        'TRIM("Zone") || TRIM("SubZone") || \'/\' || TRIM("SiteSeries") AS "SiteUnit"',
        'FROM "BECMaster_fixing_Env"',
        'WHERE "Zone" = \'SBS\' AND "SubZone" IS NOT NULL AND "SiteSeries" IS NOT NULL LIMIT 500'
      )
    )
    DBI::dbDisconnect(dbc_tmp)
    ws <- vpro_write_su(ws, sbs_su, su = "PG_Cohort_SU", create = TRUE, overwrite = TRUE)
  }

  custom_lump <- data.frame(
    SppCode = c("ABIEBAL", "ABIELAS2", "POA PRA2", "POA SEC"),
    LumpCode = c("ABIELAS", "ABIELAS", "POASPP", "POASPP"),
    Use = c(TRUE, TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  )

  # Gate 1: Scoped subzone extraction & lumping (< 1.5 s)
  t0 <- proc.time()[["elapsed"]]
  env_sub <- vpro_env(ws, scope = "su", exclude_modifiers = TRUE)
  veg_sub <- vpro_veg(ws, scope = "su", lump = custom_lump, strata = "total", exclude_modifiers = TRUE)
  t_scoped <- proc.time()[["elapsed"]] - t0

  expect_gt(nrow(env_sub), 100L)
  expect_gt(nrow(veg_sub), 1000L)
  expect_lt(t_scoped, 1.5)

  # Gate 2: Dense and sparse (dgCMatrix) community matrix construction
  t0 <- proc.time()[["elapsed"]]
  mat_dense <- vpro_matrix(ws, scope = "su", lump = custom_lump, transform = "sqrt")
  mat_sparse <- vpro_matrix(ws, scope = "su", lump = custom_lump, transform = "sqrt", sparse = TRUE)
  t_matrix <- proc.time()[["elapsed"]] - t0

  expect_true(is.matrix(mat_dense))
  expect_s4_class(mat_sparse, "dgCMatrix")
  expect_equal(dim(mat_dense), dim(mat_sparse))
  expect_equal(rownames(mat_dense), attr(mat_dense, "env")$PlotNumber)

  # Gate 3: BEC diagnostics & pairwise unit similarity parity against VPro desktop Go engine
  t0 <- proc.time()[["elapsed"]]
  diag_res <- vpro_diagnostics(ws, lump = FALSE, exclude_modifiers = FALSE, average_type = "unit")
  pw_res <- vpro_pairwise(ws, lump = FALSE, exclude_modifiers = FALSE, min_plots = 2L)
  t_diag <- proc.time()[["elapsed"]] - t0

  expect_gte(nrow(diag_res$units), 2L)
  expect_gt(nrow(diag_res$unit_species), 100L)
  expect_gt(nrow(pw_res$pairs), 0L)

  # Direct cross-verification against VPro Go-generated BECMaster_PG_Diagnostics.xlsx when present
  go_xlsx_candidates <- Sys.glob("/tmp/TestBECMasterProductionScaleQualification*/002/BECMaster_PG_Diagnostics.xlsx")
  if (length(go_xlsx_candidates) > 0L && has_pg) {
    go_xlsx <- sort(go_xlsx_candidates, decreasing = TRUE)[[1L]]
    read_zip_entry <- function(zf, entry) {
      con_z <- unz(zf, entry, open = "rb")
      on.exit(close(con_z), add = TRUE)
      rawToChar(readBin(con_z, "raw", n = 5000000L))
    }
    xlsx_files <- utils::unzip(go_xlsx, list = TRUE)$Name
    all_text <- paste(
      vapply(intersect(c("xl/sharedStrings.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"), xlsx_files), function(e) read_zip_entry(go_xlsx, e), character(1)),
      collapse = "\n"
    )
    if (grepl("Classified Plots: 438 across 66 Site Units", all_text, fixed = TRUE)) {
      expect_equal(sum(diag_res$units$n_plots), 438L)
      expect_equal(nrow(diag_res$units), 66L)
      rhod_01 <- diag_res$unit_species[diag_res$unit_species$SiteUnit == "ESSFwk2/01" & diag_res$unit_species$Species == "RHODALB", ]
      anap_01 <- diag_res$unit_species[diag_res$unit_species$SiteUnit == "ESSFwk2/01" & diag_res$unit_species$Species == "ANAPMAR", ]
      expect_equal(rhod_01$cell_code, "3 - 5")
      expect_equal(anap_01$cell_code, "5 - 1")
      pw_01_04 <- pw_res$pairs[pw_res$pairs$Unit1 == "ESSFwk2/01" & pw_res$pairs$Unit2 == "ESSFwk2/04", ]
      expect_equal(round(pw_01_04$sorensen * 100, 1), 60.1)
    }
  }

  # Gate 4: Spatial sf (EPSG:3005) across 65,700+ coordinatized plots (< 2.0 s)
  t0 <- proc.time()[["elapsed"]]
  sf_all <- vpro_sf(ws, scope = "project", crs = 3005, audit_geodesy = TRUE)
  t_sf <- proc.time()[["elapsed"]] - t0

  expect_s3_class(sf_all, "sf")
  expect_gte(nrow(sf_all), 65700L)
  expect_equal(sf::st_crs(sf_all)$epsg, 3005L)
  expect_lt(t_sf, 2.0)

  # Gate 5: Live concurrent WAL read/write-back without locking conflicts
  live_reader <- vpro:::vpro_sqlite_ro(work_db)
  open_q <- NULL
  on.exit({
    if (!is.null(open_q) && DBI::dbIsValid(open_q)) DBI::dbClearResult(open_q)
    if (DBI::dbIsValid(live_reader)) DBI::dbDisconnect(live_reader)
  }, add = TRUE)
  open_q <- DBI::dbSendQuery(live_reader, 'SELECT "PlotNumber" FROM "BECMaster_fixing_Env" LIMIT 10')
  first_batch <- DBI::dbFetch(open_q, n = 5L)
  expect_equal(nrow(first_batch), 5L)

  cl_sub <- vpro_cluster(ws, method = "ward.D2", k = 4L, lump = custom_lump)
  t0 <- proc.time()[["elapsed"]]
  ws_after <- vpro_write_su(ws, cl_sub, su = "PG_Cand", candidate = TRUE)
  t_wb <- proc.time()[["elapsed"]] - t0

  rest_batch <- DBI::dbFetch(open_q, n = 5L)
  DBI::dbClearResult(open_q)
  expect_equal(nrow(rest_batch), 5L)
  expect_equal(ws_after$su, "PG_Cand_ClusterCandidate_SU")
  expect_equal(nrow(vpro_site_units(ws_after)), nrow(cl_sub$memberships))

  message(sprintf(
    "\n[BECMaster 71,567-Plot Qualification Timings] scoped_env_veg=%.3fs | matrix_dense_sparse=%.3fs | diagnostics_pairwise=%.3fs | sf_65k_epsg3005=%.3fs (n=%d) | wal_writeback=%.3fs",
    t_scoped, t_matrix, t_diag, t_sf, nrow(sf_all), t_wb
  ))
})
