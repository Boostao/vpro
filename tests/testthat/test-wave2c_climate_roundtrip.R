new_wave2c_scratch_dir <- function(prefix = "w2c") {
  dir_path <- file.path(
    getwd(),
    sprintf(".vpro-%s-%d-%06d", prefix, Sys.getpid(), sample.int(999999L, 1L))
  )
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, winslash = "/", mustWork = TRUE)
}

clone_sample_wal_workspace <- function(scratch_dir) {
  db_path <- file.path(scratch_dir, "Sample.db")
  src_ws <- vpro_sample()
  file.copy(src_ws$project_path, db_path, overwrite = TRUE)

  rw <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RW)
  on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
  DBI::dbExecute(rw, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(rw, "PRAGMA busy_timeout = 5000")
  # Enrich leading-zero plot '00337' with coordinates, elevation, steep warm SW slope/aspect, and rSMR/rSNR
  DBI::dbExecute(
    rw,
    paste(
      'UPDATE "Sample_Env"',
      'SET "Zone" = \'SBS\', "SubZone" = \'dk\',',
      '    "Latitude" = 54.7804, "Longitude" = 127.1743, "Elevation" = 520,',
      '    "SlopeGradient" = 42, "Aspect" = 225,',
      '    "MoistureRegime" = \'2\', "NutrientRegime" = \'B\'',
      'WHERE typeof("PlotNumber") = \'text\' AND CAST("PlotNumber" AS BLOB) = CAST(\'00337\' AS BLOB)'
    )
  )
  DBI::dbDisconnect(rw)

  vpro_connect(
    project = db_path,
    su = "Sample_SU",
    hierarchy = "Sample_Hierarchy",
    lump = "Sample_Lump",
    data_dir = scratch_dir,
    config_dir = scratch_dir
  )
}

test_that("CoordElevHash and pure-R vectorized SHA-256 match NIST and vpro_wails byte-for-byte", {
  # NIST FIPS 180-4 test vectors (empty, single-block, multi-block)
  nist <- vpro:::vpro_sha256_utf8(c(
    "",
    "abc",
    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  ))
  expect_equal(
    nist,
    c(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    )
  )

  # Exact parity with Go sha256.Sum256([]byte("54.78040|-127.17430|520.0|1961_1990"))[:16]
  h_pos <- vpro_coord_elev_hash(54.7804, 127.1743, 520, ref_period = "1961_1990")
  h_neg <- vpro_coord_elev_hash(54.7804, -127.1743, 520, ref_period = "1961_1990")
  expect_equal(h_pos, "bc5ff0530174eae75e03932178b77e96")
  expect_equal(h_pos, h_neg)
  expect_equal(nchar(h_pos), 32L)

  # Changing ref_period produces a distinct hash; NA inputs yield NA_character_
  h_9120 <- vpro_coord_elev_hash(54.7804, -127.1743, 520, ref_period = "1991-2020")
  expect_false(identical(h_pos, h_9120))
  expect_identical(vpro_coord_elev_hash(NA_real_, -127.1, 500), NA_character_)

  # 1,000 vectorized hashes execute in milliseconds without external processes
  lats <- seq(49.0, 59.0, length.out = 1000L)
  lons <- seq(115.0, 135.0, length.out = 1000L)
  elevs <- seq(50.0, 1550.0, length.out = 1000L)
  h_batch <- vpro_coord_elev_hash(lats, lons, elevs, ref_period = "1961_1990")
  expect_length(h_batch, 1000L)
  expect_true(all(grepl("^[0-9a-f]{32}$", h_batch)))
})

test_that("vpro_climate, __VPRO_PlotClimate round-trip cache hit, and vpro_asmr transfer rules work cleanly", {
  # Direct Ministry CMD -> aSMR rule parity against vpro_wails rsidecar_test.go
  wet_cool <- vpro_evaluate_asmr(
    cmd = 180,
    ppt_05 = 110, ppt_06 = 105, ppt_07 = 95, ppt_08 = 100, ppt_09 = 140,
    ppt_at = 400, ppt_wt = 500,
    rsmr = "4", slope = 45, aspect = 15
  )
  expect_equal(wet_cool$MoistMonths, 5L)
  expect_equal(wet_cool$DormantDeficit, 0.0)
  expect_equal(wet_cool$AspectFactor, 0.85)
  expect_equal(wet_cool$CMD_topo, 127.5)
  expect_equal(wet_cool$aSMR, 4.5)

  dry_sw <- vpro_evaluate_asmr(
    cmd = 300,
    ppt_05 = 30, ppt_06 = 35, ppt_07 = 25, ppt_08 = 28, ppt_09 = 30,
    ppt_at = 70, ppt_wt = 80,
    rsmr = "1", slope = 45, aspect = 225
  )
  expect_equal(dry_sw$MoistMonths, 0L)
  expect_equal(dry_sw$DormantDeficit, 200.0)
  expect_equal(dry_sw$AspectFactor, 1.25)
  expect_equal(dry_sw$CMD_topo, 625.0)
  expect_equal(dry_sw$CMD_site, 1000.0)
  expect_equal(dry_sw$aSMR, 0.0)

  hydric <- vpro_evaluate_asmr(
    cmd = 400,
    ppt_05 = 20, ppt_06 = 20, ppt_07 = 20, ppt_08 = 20, ppt_09 = 20,
    ppt_at = 50, ppt_wt = 50,
    rsmr = "8"
  )
  expect_equal(hydric$CMD_site, 0.0)
  expect_equal(hydric$aSMR, 8.0)

  # Bundled Sample.db skips auto-writing to package extdata and refuses explicit vpro_cache_climate
  ws_sample <- vpro_sample()
  clim_sample <- vpro_climate(ws_sample, scope = "su", cache = TRUE, force_offline = TRUE)
  expect_gt(nrow(clim_sample), 30L)
  expect_error(vpro_cache_climate(ws_sample, clim_sample), "read-only installed")

  # Disposable WAL workspace round-trip cache test
  scratch <- new_wave2c_scratch_dir("climate")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- clone_sample_wal_workspace(scratch)

  clim1 <- vpro_climate(ws, scope = "project", ref_period = "1961_1990", cache = TRUE, force_offline = TRUE)
  expect_equal(attr(clim1, "cache_hits"), 0L)
  expect_equal(attr(clim1, "cache_misses"), nrow(clim1))
  expect_true("00337" %in% clim1$PlotNumber)
  row_337 <- clim1[clim1$PlotNumber == "00337", ]
  expect_equal(row_337$CoordElevHash, "bc5ff0530174eae75e03932178b77e96")
  expect_equal(row_337$Source, "bgc_lapse_model")

  # Verify literal SQLite 'text' storage of '00337' and __VPRO_RSidecarHistory entry
  ro <- DBI::dbConnect(RSQLite::SQLite(), ws$project_path, flags = RSQLite::SQLITE_RO)
  on.exit(if (DBI::dbIsValid(ro)) DBI::dbDisconnect(ro), add = TRUE)
  chk_337 <- DBI::dbGetQuery(
    ro,
    'SELECT typeof("PlotNumber") AS tp, "CoordElevHash", "Source" FROM "__VPRO_PlotClimate" WHERE typeof("PlotNumber") = \'text\' AND CAST("PlotNumber" AS BLOB) = CAST(\'00337\' AS BLOB)'
  )
  expect_equal(nrow(chk_337), 1L)
  expect_equal(chk_337$tp, "text")
  expect_equal(chk_337$CoordElevHash, "bc5ff0530174eae75e03932178b77e96")
  hist_rows <- DBI::dbGetQuery(ro, 'SELECT * FROM "__VPRO_RSidecarHistory" WHERE "Action" = \'CachePlotClimate\'')
  expect_gte(nrow(hist_rows), 1L)
  DBI::dbDisconnect(ro)

  # Stamp a custom Source tag on '00337' via vpro_cache_climate and confirm 100% cache hit on Run 2
  mod_337 <- row_337
  mod_337$Source <- "cached_probe_hit"
  vpro_cache_climate(ws, mod_337)

  clim2 <- vpro_climate(ws, scope = "project", ref_period = "1961_1990", cache = FALSE, force_offline = TRUE)
  expect_equal(attr(clim2, "cache_hits"), nrow(clim2))
  expect_equal(attr(clim2, "cache_misses"), 0L)
  expect_equal(clim2$Source[clim2$PlotNumber == "00337"], "cached_probe_hit")

  # Switching ref_period to 1991_2020 invalidates cache and yields warmer MAT
  clim_9120 <- vpro_climate(ws, scope = "project", ref_period = "1991_2020", cache = TRUE, force_offline = TRUE)
  expect_equal(attr(clim_9120, "cache_misses"), nrow(clim_9120))
  expect_gt(
    clim_9120$MAT[clim_9120$PlotNumber == "00337"],
    clim1$MAT[clim1$PlotNumber == "00337"]
  )

  # Full vpro_asmr table checks
  asmr <- vpro_asmr(ws, scope = "project", ref_period = "1961_1990", cache = TRUE, force_offline = TRUE)
  expect_s3_class(asmr, "tbl_df")
  expect_true(all(c("PlotNumber", "SiteUnit", "Zone", "SubZone", "MoistureRegime", "NutrientRegime", "SlopeGradient", "Aspect", "CMD", "CMD_site", "aSMR") %in% names(asmr)))
  expect_true("00337" %in% asmr$PlotNumber)
  a337 <- asmr[asmr$PlotNumber == "00337", ]
  expect_equal(a337$AspectFactor, 1.25)
  expect_true(is.finite(a337$aSMR))
  valid_asmr <- asmr$aSMR[!is.na(asmr$aSMR)]
  expect_gt(length(valid_asmr), 20L)
  expect_true(all(valid_asmr >= 0.0 & valid_asmr <= 8.0))
})

test_that("vpro_edatopic_grid (dual 9x5) and plot_edatope render unit boxes and species heatmaps", {
  # Register S3 methods during pre-roxygenise pkgload::load_all() worktree runs;
  # once roxygen2::roxygenise() runs on master, NAMESPACE registers them natively.
  if (!exists("print.vpro_edatope", envir = baseenv()$.__S3MethodsTable__., inherits = FALSE)) {
    registerS3method("print", "vpro_edatope", vpro:::print.vpro_edatope, envir = baseenv())
    registerS3method("plot", "vpro_edatope", vpro:::plot.vpro_edatope, envir = baseenv())
    registerS3method("as.data.frame", "vpro_edatope", vpro:::as.data.frame.vpro_edatope, envir = baseenv())
    registerS3method("as_tibble", "vpro_edatope", vpro:::as_tibble.vpro_edatope, envir = asNamespace("tibble"))
  }

  ws <- vpro_sample()
  ed <- vpro_edatopic_grid(ws, mode = "dual", min_constancy = 20, lump = TRUE, exclude_modifiers = TRUE, force_offline = TRUE)

  expect_s3_class(ed, "vpro_edatope")
  expect_message(print(ed), "vpro_edatope")
  expect_s3_class(tibble::as_tibble(ed), "tbl_df")
  expect_s3_class(as.data.frame(ed), "data.frame")

  expect_true(all(c("relative", "actual") %in% ed$cells$grid_type))
  expect_true(all(ed$cells$SMR %in% 0L:8L))
  expect_true(all(ed$cells$SNR %in% c("A", "B", "C", "D", "E")))
  expect_true(all(ed$cells$unit_prop > 0 & ed$cells$unit_prop <= 1))

  expect_gt(nrow(ed$unit_bboxes), 0L)
  expect_equal(nrow(ed$unit_bboxes), nrow(ed$unit_hulls))
  expect_true(all(ed$unit_bboxes$smr_min <= ed$unit_bboxes$smr_max))
  expect_true(all(ed$unit_bboxes$snr_min_num <= ed$unit_bboxes$snr_max_num))

  expect_gt(nrow(ed$species), 0L)
  expect_true(all(ed$species$constancy >= 20))
  expect_true(all(ed$species$prominence_tier %in% 1L:3L))

  skip_if_not_installed("ggplot2")
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  p_units <- plot_edatope(ed)
  expect_s3_class(p_units, "ggplot")
  built_units <- ggplot2::ggplot_build(p_units)
  expect_gt(length(built_units$data), 1L)

  top_spp <- ed$species$Species[[1L]]
  p_spp <- plot_edatope(ed, species = top_spp)
  expect_s3_class(p_spp, "ggplot")
  built_spp <- ggplot2::ggplot_build(p_spp)
  expect_gt(length(built_spp$data), 1L)

  p_s3 <- plot(ed, grid_type = "relative", units = ed$unit_bboxes$SiteUnit[[1L]])
  expect_s3_class(p_s3, "ggplot")
})

test_that("writeback enforces refusal guards, confirmation flags, provenance, leading zeroes, and live WAL coexistence", {
  scratch <- new_wave2c_scratch_dir("writeback")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- clone_sample_wal_workspace(scratch)

  # Keep a live read-only SQLite connection open concurrently throughout all BEGIN IMMEDIATE write-backs
  live_reader <- vpro:::vpro_sqlite_ro(ws$project_path)
  on.exit(if (DBI::dbIsValid(live_reader)) DBI::dbDisconnect(live_reader), add = TRUE)
  pre_env_n <- DBI::dbGetQuery(live_reader, 'SELECT COUNT(*) AS n FROM "Sample_Env"')$n[[1L]]
  expect_equal(pre_env_n, 52L)

  cand_df <- tibble::tibble(
    PlotNumber = c("00337", "108050", "1976075"),
    Cluster = c("CL_01", "CL_01", "CL_02")
  )

  # 1. Hard database refusal guards (bundled Sample.db and VLists.db)
  expect_error(vpro_write_candidate_su(vpro_sample(), cand_df), "read-only installed")
  ws_vlists <- ws
  ws_vlists$project_path <- ws$vlists_path
  expect_error(vpro_write_candidate_su(ws_vlists, cand_df), "protected VPro system")

  # 2. Hard table/prefix refusal guards (Master*, USys*, BECSiteUnit, core VP08, numeric PlotNumber)
  expect_error(vpro_write_candidate_su(ws, cand_df, name = "Master"), "Master")
  expect_error(vpro_write_su(ws, cand_df, su_name = "Master_SU", create = TRUE, confirm_overwrite = TRUE), "Master")
  expect_error(vpro_write_su(ws, cand_df, su_name = "BECMaster_2026", create = TRUE), "Master")
  expect_error(vpro_write_su(ws, cand_df, su_name = "USysSuTable", create = TRUE, confirm_overwrite = TRUE), "USys")
  expect_error(vpro_write_su(ws, cand_df, su_name = "BECSiteUnit", create = TRUE, confirm_overwrite = TRUE), "BECSiteUnit")
  expect_error(vpro_write_su(ws, cand_df, su_name = "Sample_Env", create = TRUE, confirm_overwrite = TRUE), "core VP08")
  expect_error(
    vpro_write_candidate_su(ws, data.frame(PlotNumber = c(337, 108050), SiteUnit = c("A", "B"))),
    "literal `character`"
  )

  # 3. vpro_write_candidate_su works with both data.frame and vpro_clusters S3 objects
  mock_clusters <- structure(
    list(
      memberships = tibble::tibble(
        PlotNumber = c("00337", "108050", "1976075"),
        ClusterUnit = c("SBSdk_C1", "MHun_C2", "BWBS_C3")
      )
    ),
    class = "vpro_clusters"
  )
  ws_cand <- vpro_write_candidate_su(ws, mock_clusters, actor = "ecologist_test")
  expect_equal(ws_cand$su, "Sample_ClusterCandidate_SU")
  su_cand_rows <- vpro_site_units(ws_cand)
  expect_equal(su_cand_rows$PlotNumber, c("00337", "108050", "1976075"))
  expect_error(vpro_write_candidate_su(ws, cand_df, overwrite = FALSE), "overwrite = TRUE")

  # 4. vpro_write_su enforces create = TRUE and confirm_overwrite = TRUE
  expect_error(vpro_write_su(ws, cand_df, su_name = "Working2026", create = FALSE), "create = TRUE")
  ws_work <- vpro_write_su(ws, cand_df, su_name = "Working2026", create = TRUE, actor = "ecologist_test")
  expect_equal(ws_work$su, "Working2026_SU")
  expect_error(
    vpro_write_su(ws, cand_df, su_name = "Working2026_SU", create = TRUE, confirm_overwrite = FALSE),
    "confirm_overwrite = TRUE"
  )
  expect_error(
    vpro_write_su(ws, cand_df, su_name = "Sample_SU", confirm_overwrite = FALSE),
    "confirm_overwrite = TRUE"
  )
  ws_work2 <- vpro_write_su(
    ws,
    tibble::tibble(PlotNumber = c("00337", "108050"), SiteUnit = c("SBSdk/01", "MHun/02")),
    su_name = "Working2026",
    confirm_overwrite = TRUE,
    actor = "ecologist_test"
  )
  expect_equal(nrow(vpro_site_units(ws_work2)), 2L)
  expect_true("00337" %in% vpro_site_units(ws_work2)$PlotNumber)

  # 5. vpro_write_lump validates UTF-16 lengths, reserved names, confirm_overwrite, and -1L/0L Access booleans
  lump_in <- tibble::tibble(
    LumpCode = c("ABIESPP", "SALISPP"),
    SppCode = c("ABIELAS", "SALIBEB"),
    Use = c(TRUE, FALSE)
  )
  expect_error(vpro_write_lump(ws, lump_in, lump_name = "Master_Lump"), "Master")
  expect_error(vpro_write_lump(ws, lump_in, lump_name = "USysCustom"), "USys")
  expect_error(vpro_write_lump(ws, lump_in, lump_name = "CombinedSpp"), "reserved")
  expect_error(vpro_write_lump(ws, lump_in, lump_name = "Sample_Lump", confirm_overwrite = FALSE), "confirm_overwrite = TRUE")
  expect_error(
    vpro_write_lump(ws, tibble::tibble(LumpCode = "ABIESPP", SppCode = "TOOLONGSPP99", Use = TRUE), lump_name = "BadSpp"),
    "8 UTF-16"
  )

  ws_lump <- vpro_write_lump(ws, lump_in, lump_name = "Custom2026", create = TRUE, actor = "ecologist_test")
  expect_equal(ws_lump$lump, "Custom2026_Lump")
  active_lump <- vpro_lump_map(ws_lump, lump = TRUE)
  expect_equal(active_lump$SppCode, "ABIELAS")
  expect_equal(active_lump$LumpCode, "ABIESPP")

  # Verify live_reader remained valid throughout WAL write-backs and sees committed _table_metadata, _Audit, and __VPRO_RSidecarHistory
  raw_lump_disk <- DBI::dbGetQuery(live_reader, 'SELECT "LumpCode", "SppCode", CAST("Use" AS INTEGER) AS "UseInt" FROM "Custom2026_Lump" ORDER BY "SppCode"')
  expect_equal(raw_lump_disk$UseInt, c(-1L, 0L))

  meta_rows <- DBI::dbGetQuery(
    live_reader,
    'SELECT "table_name", "description" FROM "_table_metadata" WHERE "table_name" IN (\'Sample_ClusterCandidate_SU\', \'Working2026_SU\', \'Custom2026_Lump\') ORDER BY "table_name"'
  )
  expect_equal(meta_rows$description, c("VP05", "VP04", "VP04"))

  audit_rows <- vpro_audit(ws)
  new_audits <- audit_rows[!is.na(audit_rows$User) & audit_rows$User == "ecologist_test", ]
  expect_equal(nrow(new_audits), 4L)
  expect_equal(length(unique(new_audits$ID)), 4L)

  hist_all <- DBI::dbGetQuery(live_reader, 'SELECT "Action" FROM "__VPRO_RSidecarHistory" ORDER BY "ID"')
  expect_true(all(c("MaterializeClusterCandidate", "WriteWorkingSU", "WriteLumpTable") %in% hist_all$Action))

  su_type_disk <- DBI::dbGetQuery(
    live_reader,
    'SELECT typeof("PlotNumber") AS tp FROM "Working2026_SU" WHERE CAST("PlotNumber" AS BLOB) = CAST(\'00337\' AS BLOB)'
  )
  expect_equal(su_type_disk$tp, "text")
})
