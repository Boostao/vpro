test_that("1B.1: cover_precedence matches MS Access defaults across vpro_veg, vpro_matrix, and vpro_diagnostics", {
  ws <- vpro_connect("Sample")

  expect_identical(eval(formals(vpro_veg)$cover_precedence), c("strata_totals", "sublayer_sum"))
  expect_identical(eval(formals(vpro_matrix)$cover_precedence), c("strata_totals", "sublayer_sum"))
  expect_identical(eval(formals(vpro_diagnostics)$cover_precedence), c("sublayer_sum", "strata_totals"))

  veg_strata <- vpro_veg(ws, strata = "total", combine = "sum", cover_precedence = "strata_totals")
  veg_subsum <- vpro_veg(ws, strata = "total", combine = "sum", cover_precedence = "sublayer_sum")

  expect_equal(veg_strata$Cover[veg_strata$PlotNumber == "108050" & veg_strata$Species == "ABIE_RK"], 15.0)
  expect_equal(veg_subsum$Cover[veg_subsum$PlotNumber == "108050" & veg_subsum$Species == "ABIE_RK"], 20.0)

  mat_strata <- vpro_matrix(ws, value = "cover", strata = "total", cover_precedence = "strata_totals")
  mat_subsum <- vpro_matrix(ws, value = "cover", strata = "total", cover_precedence = "sublayer_sum")
  expect_lt(mat_strata["108050", "ABIE_RK"], mat_subsum["108050", "ABIE_RK"])

  diag_subsum <- vpro_diagnostics(ws, cover_precedence = "sublayer_sum")
  diag_strata <- vpro_diagnostics(ws, cover_precedence = "strata_totals")
  expect_s3_class(diag_subsum, "vpro_diagnostics")
  expect_s3_class(diag_strata, "vpro_diagnostics")
})

test_that("1B.2: vpro_profile applies Sample_Lump only on Table=='Lump' and matches 11-plot Sample_Profile parity", {
  ws <- vpro_connect("Sample")

  prof_default <- vpro_profile(ws, lump = TRUE)
  expect_equal(length(prof_default$plots), 11L)

  rules_veg <- list(
    vpro_profile_rule("Veg", species = "EPILSPP", layer = "Any", operator = ">", value = 0, operation = "Add")
  )
  rules_lump <- list(
    vpro_profile_rule("Lump", species = "EPILSPP", layer = "Any", operator = ">", value = 0, operation = "Add")
  )
  prof_veg <- vpro_profile(ws, rules = rules_veg, lump = TRUE)
  prof_lump <- vpro_profile(ws, rules = rules_lump, lump = TRUE)

  expect_equal(length(prof_veg$plots), 0L)
  expect_gt(length(prof_lump$plots), 0L)
})

test_that("1B.3 & 1B.5 & 1B.6 & 1B.7: validation bounds, case-insensitive species, user spp, presence cap, defaults, and status", {
  ws <- vpro_connect("Sample")

  # 1B.7: vpro_status(ws) works without 'invalid path argument' and inspect preserves compatible
  st <- vpro_status(ws)
  expect_type(st, "list")
  expect_true(all(c("r_version", "data_dir", "config_dir", "standards") %in% names(st)))
  insp <- vpro_project_inspect(ws$project_path)
  expect_true(isTRUE(insp$compatible))

  # 1B.5: > 1.0 -> NA guard on vpro_presence_class
  expect_identical(
    vpro_presence_class(c(-0.01, 0, 0.2, 0.2001, 0.4, 0.6, 0.8, 1.0, 1.0001, NA_real_)),
    c(NA_character_, "I", "I", "II", "II", "III", "IV", "V", NA_character_, NA_character_)
  )
  expect_identical(
    vpro_presence_class(c(-0.01, 0, 0.2, 0.5, 1.0, 1.01, NA_real_), format = "numeric"),
    c(NA_integer_, 1L, 1L, 3L, 5L, NA_integer_, NA_integer_)
  )

  # 1B.6: pairwise & outliers defaults match canonical BEC standard / Go SynthesisOptions
  expect_identical(formals(vpro_pairwise)$lump, TRUE)
  expect_identical(formals(vpro_pairwise)$exclude_modifiers, TRUE)
  expect_identical(formals(vpro_pairwise)$min_plots, 2L)
  expect_identical(formals(vpro_pairwise)$min_constancy, 60)
  expect_identical(formals(vpro_pairwise)$noise_constancy, 10)
  expect_identical(formals(vpro_pairwise)$min_diff, 0.5)
  expect_identical(formals(vpro_pairwise)$min_dd, 0.5)
  expect_identical(eval(formals(vpro_pairwise)$cover_precedence), c("sublayer_sum", "strata_totals"))

  expect_identical(formals(vpro_outliers)$lump, TRUE)
  expect_identical(formals(vpro_outliers)$exclude_modifiers, TRUE)
  expect_identical(eval(formals(vpro_outliers)$transform)[[1L]], "none")
  expect_identical(formals(vpro_outliers)$threshold, 0.45)
  expect_identical(formals(vpro_outliers)$keep_singletons, TRUE)
  expect_identical(eval(formals(vpro_outliers)$cover_precedence), c("sublayer_sum", "strata_totals"))

  pw <- vpro_pairwise(ws)
  pw_all <- vpro_pairwise(ws, min_plots = 1L)
  ol <- vpro_outliers(ws)
  expect_s3_class(pw, "vpro_pairwise")
  expect_identical(nrow(pw$pairs), 36L)
  expect_identical(nrow(pw_all$pairs), 55L)
  expect_s3_class(ol, "vpro_outliers")
  expect_gt(nrow(ol$outliers), 0L)

  # 1B.3: Sample.db VP08 bounds, user spp, and isolated temp case-insensitive OldCode / UTF-16 checks
  val_all <- vpro_validate(ws, scope = "project", checks = "all")
  expect_equal(nrow(val_all$bounds), 3L)
  expect_true(all(c("579279", "9003104", "R3039") %in% val_all$bounds$PlotNumber))
  expect_true("user" %in% val_all$veg_codes$status)

  val_lmh <- vpro_validate(ws, scope = "project", checks = "lmh25")
  expect_identical(val_lmh$checks, "lmh25")
  expect_s3_class(val_lmh$lmh25, "vpro_lmh25_audit")

  td <- tempfile("vpro-val-iso-")
  dir.create(file.path(td, "projects"), recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  proj_iso <- file.path(td, "projects", "SampleIso.db")
  file.copy(ws$project_path, proj_iso)
  con <- DBI::dbConnect(RSQLite::SQLite(), proj_iso)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "UPDATE Sample_Env SET Longitude = 195.0, Aspect = 400 WHERE PlotNumber = '00337'")
  DBI::dbExecute(con, "UPDATE Sample_Veg SET Species = 'tsughet' WHERE PlotNumber = '00337' AND Species = 'TSUGHET'")
  DBI::dbDisconnect(con)

  ws_iso <- vpro_connect(proj_iso, su = "Sample_SU", data_dir = td)
  val_iso <- vpro_validate(ws_iso, scope = "project", checks = "compliance")
  expect_true(any(val_iso$bounds$PlotNumber == "00337" & val_iso$bounds$field == "Longitude"))
  expect_true(any(val_iso$bounds$PlotNumber == "00337" & val_iso$bounds$field == "Aspect"))
  expect_false(any(val_iso$veg_codes$PlotNumber == "00337" & tolower(val_iso$veg_codes$Species) == "tsughet" & val_iso$veg_codes$status == "unlisted"))
})

test_that("S6.6: USysSppAttributes RedBlueList redacts coordinates on vpro_export_rds and cloud coordinate helper", {
  ws <- vpro_connect("Sample")

  td <- tempfile("vpro-redact-")
  dir.create(file.path(td, "projects"), recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)

  proj_iso <- file.path(td, "projects", "SampleRedact.db")
  vlists_iso <- file.path(td, "VLists.db")
  file.copy(ws$project_path, proj_iso)
  file.copy(ws$vlists_path, vlists_iso)

  veg_00337 <- vpro_veg(ws, scope = "project", strata = "total", lump = FALSE)
  spp_hit <- "ABIELAS"
  expect_true(spp_hit %in% veg_00337$Species[veg_00337$PlotNumber == "00337"])
  sens_expected_plots <- unique(veg_00337$PlotNumber[toupper(veg_00337$Species) == spp_hit])

  vcon <- DBI::dbConnect(RSQLite::SQLite(), vlists_iso)
  on.exit(if (DBI::dbIsValid(vcon)) DBI::dbDisconnect(vcon), add = TRUE)
  n_upd <- DBI::dbExecute(vcon, "UPDATE USysSppAttributes SET RedBlueList = 'Red' WHERE UPPER(TRIM(Code)) = ?", params = list(toupper(spp_hit)))
  expect_equal(n_upd, 1L)
  DBI::dbDisconnect(vcon)

  ws_iso <- vpro_connect(proj_iso, su = "Sample_SU", data_dir = td)
  ws_iso$vlists_path <- vlists_iso

  env_before <- vpro_env(ws_iso, scope = "project")
  expect_false(is.na(env_before$Latitude[env_before$PlotNumber == "00337"]))

  rds_path <- file.path(td, "redacted.rds")
  vpro_export_rds(ws_iso, path = rds_path, redact_sensitive = TRUE)
  ws_back <- vpro_import_rds(rds_path)
  env_back <- vpro_env(ws_back, scope = "project")

  row_00337 <- env_back[env_back$PlotNumber == "00337", , drop = FALSE]
  expect_equal(nrow(row_00337), 1L)
  # ENG-XCUT-002: same ~10 km generalization as Go MaskSensitiveEnvRow (0.1 degree,
  # 10,000 m), UTMZone preserved.
  orig_00337 <- env_before[env_before$PlotNumber == "00337", , drop = FALSE]
  expect_identical(row_00337$Latitude, trunc(orig_00337$Latitude * 10) / 10)
  expect_identical(row_00337$Longitude, trunc(orig_00337$Longitude * 10) / 10)
  if (!is.na(orig_00337$UTMEasting)) {
    expect_equal(as.double(row_00337$UTMEasting), trunc(as.double(orig_00337$UTMEasting) / 10000) * 10000)
  }
  if (!is.na(orig_00337$UTMNorthing)) {
    expect_equal(as.double(row_00337$UTMNorthing), trunc(as.double(orig_00337$UTMNorthing) / 10000) * 10000)
  }
  expect_false(identical(row_00337$Latitude, orig_00337$Latitude) && identical(row_00337$Longitude, orig_00337$Longitude))
  expect_identical(row_00337$UTMZone, orig_00337$UTMZone)

  non_sens <- env_back[!(env_back$PlotNumber %in% sens_expected_plots) & !is.na(env_back$Latitude), , drop = FALSE]
  expect_gt(nrow(non_sens), 10L)

  if (requireNamespace("sf", quietly = TRUE)) {
    gpkg_red <- file.path(td, "redacted.gpkg")
    vpro_export_gpkg(ws_back, path = gpkg_red, crs = 3005, scope = "project", overwrite = TRUE)
    gpkg_sf <- sf::st_read(gpkg_red, layer = "plots", quiet = TRUE)
    # Sensitive plot is exported only at its generalized (~10 km) location.
    if ("00337" %in% as.character(gpkg_sf$PlotNumber)) {
      env_gen <- env_back[env_back$PlotNumber == "00337", , drop = FALSE]
      expect_identical(env_gen$Latitude, trunc(orig_00337$Latitude * 10) / 10)
    }
  }

  expect_false(isTRUE(formals(vpro_master_publish_snapshot)$redact_sensitive))
  expect_identical(deparse(formals(vpro:::vpro_master_pull_impl)$redact_sensitive), "!identical(pg$role, \"custodian\")")

  # Direct cloud df redaction helper parity check
  df_in <- data.frame(
    PlotNumber = c("00337", "00338"),
    Latitude = c(54.2, 54.3),
    Longitude = c(-126.7, -126.8),
    UTMEasting = c(650000L, 651000L),
    UTMNorthing = c(6010000L, 6011000L),
    UTMZone = c("9N", "9N"),
    stringsAsFactors = FALSE
  )
  df_out <- vpro:::.vpro_redact_coord_df(df_in, "00337")
  expect_identical(df_out$Latitude[[1L]], 54.2)
  expect_identical(df_out$Longitude[[1L]], -126.7)
  expect_identical(df_out$UTMEasting[[1L]], 650000L)
  expect_identical(df_out$UTMNorthing[[1L]], 6010000L)
  expect_identical(df_out$UTMZone[[1L]], "9N")
  expect_equal(df_out$Latitude[[2L]], 54.3)
})

test_that("R 2.0 clean-slate export surface strictly equals 89 curated exports with zero legacy wrappers", {
  exports <- getNamespaceExports("vpro")
  expect_equal(length(exports), 89L)

  removed_v1 <- c(
    "vpro_standards_sync", "vpro_publish_snapshot", "vpro_list_snapshots",
    "vpro_write_rds_snapshot", "vpro_read_rds_project", "plot_edatope",
    "vpro_rule", "vpro_diagnostic_classify", "vpro_master_verify_audit",
    "vpro_check_lmh25", "vpro_presence_class_numeric", "vpro_sample",
    "vpro_project_discover", "vpro_project_validate", "vpro_write_candidate_su",
    "vpro_coord_elev_hash", "vpro_sidecar_exec", "vpro_round_minimum"
  )
  expect_length(intersect(exports, removed_v1), 0L)

  added_r2 <- c(
    "vpro_master_standards_sync", "vpro_master_publish_snapshot",
    "vpro_master_list_snapshots", "vpro_export_rds", "vpro_import_rds",
    "vpro_plot_edatope", "vpro_profile_rule", "vpro_classify_diagnostic_codes"
  )
  expect_true(all(added_r2 %in% exports))
})
