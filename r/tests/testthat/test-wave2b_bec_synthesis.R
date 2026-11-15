# Wave 2B Tests: BEC Diagnostics, Pairwise Similarity, Outliers, Profiling & Summaries

make_w2b_scratch <- function() {
  dir_path <- file.path(
    getwd(),
    sprintf(".vpro-w2b-test-%d-%d", Sys.getpid(), sample.int(1000000L, 1L))
  )
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  dir_path
}

build_cwh_synthesis_workspace <- function(scratch_dir) {
  db_path <- file.path(scratch_dir, "Sample.db")
  file.copy(vpro_connect("Sample")$project_path, db_path, overwrite = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  for (tbl in c(
    "Sample_Veg", "Sample_Humus", "Sample_Mineral", "Sample_Other",
    "Sample_Audit", "Sample_Admin", "Sample_Env", "Sample_SU"
  )) {
    DBI::dbExecute(con, paste0('DELETE FROM "', tbl, '"'))
  }

  DBI::dbExecute(con, 'CREATE TABLE "Working_SU" ("PlotNumber" TEXT UNIQUE, "SiteUnit" TEXT)')
  DBI::dbExecute(con, 'CREATE TABLE "CombineTest_Lump" ("LumpCode" TEXT, "SppCode" TEXT UNIQUE, "Use" INTEGER)')
  DBI::dbExecute(
    con,
    paste(
      'INSERT INTO "CombineTest_Lump" ("LumpCode", "SppCode", "Use") VALUES',
      '(\'TSUGHET\', \'TSUGHET1\', -1),',
      '(\'TSUGHET\', \'TSUGHET2\', -1),',
      '(\'IGNORED\', \'THUJPLI\', 0)'
    )
  )

  insert_plot <- function(plot_num, zone, subzone, series, smr, snr, elev, slope, aspect, su_unit, veg_named, humus_form = NULL) {
    DBI::dbExecute(
      con,
      paste(
        'INSERT INTO "Sample_Env"',
        '("PlotNumber", "Zone", "SubZone", "SiteSeries", "MoistureRegime", "NutrientRegime",',
        '"Elevation", "SlopeGradient", "Aspect", "StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss")',
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = list(plot_num, zone, subzone, series, smr, snr, elev, slope, aspect, 65.0, 25.0, 35.0, 40.0)
    )
    DBI::dbExecute(
      con,
      'INSERT INTO "Sample_Admin" ("Plot", "UserSiteUnit", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality") VALUES (?, ?, \'Good\', \'Good\', \'Good\')',
      params = list(plot_num, su_unit)
    )
    if (!is.na(su_unit) && nzchar(su_unit)) {
      DBI::dbExecute(
        con,
        'INSERT INTO "Working_SU" ("PlotNumber", "SiteUnit") VALUES (?, ?)',
        params = list(plot_num, su_unit)
      )
    }
    if (!is.null(humus_form)) {
      DBI::dbExecute(
        con,
        'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HumusFormpH") VALUES (?, ?, 6, 0, 4.2)',
        params = list(plot_num, humus_form)
      )
    }
    for (i in seq_along(veg_named)) {
      sp <- names(veg_named)[[i]]
      cov <- unname(veg_named[[i]])
      DBI::dbExecute(
        con,
        'INSERT INTO "Sample_Veg" ("PlotNumber", "ID", "Species", "Cover1", "Cover6") VALUES (?, ?, ?, ?, NULL)',
        params = list(plot_num, i, sp, cov)
      )
    }
  }

  # Unit 1: CWHvm1/01 (5 normal mesic HwBa-Blueberry plots + 1 misclassified leading-zero plot '00337')
  for (i in 1:5) {
    insert_plot(
      sprintf("U01_%02d", i), "CWH", "vm1", "01", "4", "C",
      300 + i * 10, 15 + i, 180, "CWHvm1/01",
      c(TSUGHET1 = 65.0, TSUGHET2 = 55.0, ABIEAMA = 28.0, VACCMEM = 18.0, HYLOCOM = 40.0),
      humus_form = "Fm"
    )
  }

  # Leading-zero plot '00337' deliberately misassigned to CWHvm1/01 while carrying pure CWHvm1/05 rich flora
  insert_plot(
    "00337", "CWH", "vm1", "05", "5", "D",
    220, 5, 90, "CWHvm1/01",
    c(THUJPLI = 52.0, POLYMUN = 38.0, TIARTRI = 22.0, OPANHOR = 16.0),
    humus_form = "Ah"
  )

  # Unit 2: CWHvm1/05 (5 rich CwHw-Foamflower plots)
  for (i in 1:5) {
    insert_plot(
      sprintf("U05_%02d", i), "CWH", "vm1", "05", "5", "D",
      200 + i * 10, 4 + i, 90, "CWHvm1/05",
      c(THUJPLI = 50.0, POLYMUN = 35.0, TIARTRI = 24.0, OPANHOR = 15.0),
      humus_form = "Moder"
    )
  }

  # Unit 3: CWHvm1/09 (singleton unit with 1 plot)
  insert_plot(
    "U09_01", "CWH", "vm1", "09", "7", "E",
    110, 0, 999, "CWHvm1/09",
    c(PICESIT = 45.0, LYSIAME = 30.0)
  )

  # Excluded modifier units (.support, .poor, .nudum) + unassigned plot
  insert_plot("SUP_01", "CWH", "vm1", "01", "4", "B", 310, 12, 200, "CWHvm1/01.support", c(TSUGHET = 30.0))
  insert_plot("POR_01", "CWH", "vm1", "05", "3", "A", 410, 20, 210, "CWHvm1/05.poor", c(PINUCON = 25.0))
  insert_plot("NUD_01", "CWH", "vm1", "01", "2", "A", 510, 30, 220, "CWHvm1/01.nudum", c(PSEUMEN = 20.0))
  insert_plot("UNAS_1", "CWH", "vm1", "", "2", "B", 600, 25, 270, "", c(PSEUMEN = 40.0))

  vpro_connect(
    project = db_path,
    su = "Working_SU",
    hierarchy = "None",
    lump = "CombineTest_Lump",
    data_dir = dirname(vpro_connect("Sample")$project_path),
    config_dir = scratch_dir
  )
}

test_that("vpro_diagnostics matches vpro_wails test vectors, 99% lump cap, V7mdlDiagnostic, and BEC tiers", {
  scratch <- make_w2b_scratch()
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  ws <- build_cwh_synthesis_workspace(scratch)
  diag <- vpro_diagnostics(ws, lump = TRUE, exclude_modifiers = TRUE)

  expect_s3_class(diag, "vpro_diagnostics")
  expect_message(print(diag), "vpro_diagnostics")
  s_diag <- summary(diag)
  expect_equal(nrow(diag$units), 3L)
  expect_equal(diag$units$SiteUnit, c("CWHvm1/01", "CWHvm1/05", "CWHvm1/09"))
  expect_equal(diag$units$n_plots, c(6L, 5L, 1L))
  expect_gt(s_diag$n_diagnostic_v7, 0L)
  expect_gt(s_diag$n_diagnostic_bec, 0L)

  # Verify 99% cap on lumped TSUGHET (65 + 55 = 120 -> capped to 99 across 5/6 plots => 82.5% unit mean, 99.0% characteristic)
  tsu_us <- diag$unit_species[diag$unit_species$Species == "TSUGHET" & diag$unit_species$SiteUnit == "CWHvm1/01", ]
  expect_equal(nrow(tsu_us), 1L)
  expect_equal(tsu_us$n_plots, 6L)
  expect_equal(tsu_us$n_present, 5L)
  expect_equal(tsu_us$mean_cover_present, 99.0)
  expect_equal(tsu_us$mean_cover_unit, 82.5)
  expect_equal(tsu_us$presence_class, "V")
  expect_equal(tsu_us$presence_num, 5L)
  expect_equal(tsu_us$significance_class, "9")
  expect_equal(tsu_us$cell_code, "5 - 9")
  expect_equal(tsu_us$diagnosis, "d, cd")
  expect_match(tsu_us$bec_diagnosis, "d1")
  expect_match(tsu_us$bec_diagnosis, "dd1")
  expect_match(tsu_us$bec_diagnosis, "cd")

  tsu_ct <- diag$crosstab[diag$crosstab$Species == "TSUGHET", ]
  expect_equal(tsu_ct$DiagnosticUnit, "CWHvm1/01")
  expect_equal(tsu_ct$Diagnosis, "d, cd")
  expect_equal(tsu_ct[["CWHvm1/01"]], "5 - 9")
  expect_true(is.na(tsu_ct[["CWHvm1/05"]]))

  # Characteristic cover mode uses mean_cover_present for significance/goldstream/prominence
  diag_char <- vpro_diagnostics(ws, lump = TRUE, average_type = "characteristic")
  vac_unit <- diag$unit_species[diag$unit_species$Species == "VACCMEM" & diag$unit_species$SiteUnit == "CWHvm1/01", ]
  vac_char <- diag_char$unit_species[diag_char$unit_species$Species == "VACCMEM" & diag_char$unit_species$SiteUnit == "CWHvm1/01", ]
  # VACCMEM has 18% in 5/6 plots -> unit mean = 15% (class 5), characteristic = 18% (class 5), higher prominence
  expect_gt(vac_char$prominence, vac_unit$prominence)

  # Including modifiers retains .support, .poor, .nudum
  diag_mod <- vpro_diagnostics(ws, exclude_modifiers = FALSE)
  expect_equal(nrow(diag_mod$units), 6L)

  # Verify BEC refined differential tier helper across d1..d3, dd1..dd4, cd, c, ic
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.90, 0.05), c(5L, 1L), c(4L, 1L))$primary_diagnosis,
    "d1, c"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.75, 0.10), c(4L, 1L), c(4L, 1L))$primary_diagnosis,
    "d2"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.65, 0.20), c(4L, 1L), c(4L, 1L))$primary_diagnosis,
    "d3"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.70, 0.65), c(4L, 4L), c(6L, 1L))$primary_diagnosis,
    "dd1"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.70, 0.65), c(4L, 4L), c(5L, 1L))$primary_diagnosis,
    "dd2"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.70, 0.65), c(4L, 4L), c(5L, 2L))$primary_diagnosis,
    "dd3"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.70, 0.65), c(4L, 4L), c(5L, 3L))$primary_diagnosis,
    "dd4"
  )
  expect_equal(
    vpro:::.vpro_bec_refined_classify(c("U1", "U2"), c(0.35, 0.0), c(2L, 0L), c(3L, 0L))$primary_diagnosis,
    "ic"
  )

  # S3 as_tibble dispatches for all three tables
  expect_s3_class(tibble::as_tibble(diag), "tbl_df")
  expect_equal(nrow(tibble::as_tibble(diag, table = "crosstab")), nrow(diag$crosstab))
  expect_equal(nrow(tibble::as_tibble(diag, table = "units")), 3L)
})

test_that("vpro_diagnostics supports Sample.db and ~ tilde hierarchy_breaks rollup", {
  ws <- vpro_connect("Sample")
  d_su <- vpro_diagnostics(ws, min_constancy = 20)
  expect_equal(nrow(d_su$units), 11L)
  expect_false(d_su$hierarchy_breaks)

  d_brk <- vpro_diagnostics(ws, hierarchy_breaks = TRUE)
  expect_true(d_brk$hierarchy_breaks)
  expect_equal(nrow(d_brk$units), 4L)
  expect_true(all(grepl("^ASSOC ", d_brk$units$SiteUnit)))
  # Total plots across the 4 ~ASSOC breakpoints is 51 - 6 (unbroken BWBSdk 2 /06) = 45
  expect_equal(sum(d_brk$units$n_plots), 45L)
})

test_that("vpro_pairwise computes BEC differential points and symmetric similarity matrices", {
  scratch <- make_w2b_scratch()
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  ws <- build_cwh_synthesis_workspace(scratch)
  pw <- vpro_pairwise(ws, min_plots = 2L, min_constancy = 60, noise_constancy = 10)

  expect_s3_class(pw, "vpro_pairwise")
  expect_message(print(pw), "vpro_pairwise")
  expect_s3_class(tibble::as_tibble(pw), "tbl_df")

  # Singleton CWHvm1/09 filtered out by min_plots = 2L -> 2 eligible units -> 1 pair
  expect_equal(dim(pw$similarity_matrix), c(2L, 2L))
  expect_equal(rownames(pw$similarity_matrix), c("CWHvm1/01", "CWHvm1/05"))
  expect_equal(as.numeric(diag(pw$similarity_matrix)), c(1.0, 1.0))
  expect_equal(pw$similarity_matrix, t(pw$similarity_matrix))
  expect_equal(nrow(pw$pairs), 1L)

  req_cols <- c(
    "Unit1", "Unit2", "shared_diag", "diff_tot", "diff_ratio",
    "bec_sim_min", "bec_sim_mean", "bec_sim_max", "sorensen"
  )
  expect_true(all(req_cols %in% names(pw$pairs)))
  expect_gt(pw$pairs$diff_tot[[1L]], 10)
  expect_lt(pw$pairs$bec_sim_mean[[1L]], 0.3)
  expect_gt(nrow(pw$species_diffs), 4L)

  # Sample.db pairwise across units with >= 2 plots (9 units -> 36 pairs)
  ws_sample <- vpro_connect("Sample")
  pw_sample <- vpro_pairwise(ws_sample, min_plots = 2L)
  expect_equal(nrow(pw_sample$similarity_matrix), 9L)
  expect_equal(nrow(pw_sample$pairs), 36L)
  expect_equal(pw_sample$similarity_matrix, t(pw_sample$similarity_matrix))
  expect_true(all(pw_sample$pairs$sorensen >= 0 & pw_sample$pairs$sorensen <= 1))
  expect_true(all(pw_sample$pairs$bec_sim_mean >= 0 & pw_sample$pairs$bec_sim_mean <= 1))
})

test_that("vpro_outliers flags injected misclassified plot '00337' #1 with leading zeroes intact", {
  scratch <- make_w2b_scratch()
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  ws <- build_cwh_synthesis_workspace(scratch)

  for (tr in c("sqrt", "raw", "log1p", "chord", "hellinger")) {
    out <- vpro_outliers(ws, transform = tr, threshold = 0.45, keep_singletons = FALSE)
    expect_s3_class(out, "vpro_outliers")
    expect_type(out$queue$PlotNumber, "character")
    # 6 plots in CWHvm1/01 + 5 plots in CWHvm1/05 = 11 evaluated plots when keep_singletons = FALSE
    expect_equal(nrow(out$queue), 11L)
    expect_false("U09_01" %in% out$queue$PlotNumber)

    top <- out$queue[1L, ]
    expect_identical(top$PlotNumber, "00337")
    expect_identical(top$SiteUnit, "CWHvm1/01")
    expect_identical(top$nearest_unit, "CWHvm1/05")
    expect_equal(top$own_similarity, 0.0)
    expect_gt(top$nearest_similarity, 0.90)
    expect_lt(top$margin, -0.90)
    expect_true(top$misclassified)
    expect_true(top$low_similarity)
    expect_true(top$flagged)
  }

  # Default keep_singletons = TRUE aligns with Go ComputeOutlierQueue (includes U09_01 as singleton)
  out_def <- vpro_outliers(ws)
  expect_message(print(out_def), "vpro_outliers")
  expect_equal(nrow(tibble::as_tibble(out_def)), 12L)
  expect_equal(nrow(tibble::as_tibble(out_def, flagged_only = TRUE)), 2L)
  expect_true(all(c("00337", "U09_01") %in% out_def$outliers$PlotNumber))
  expect_identical(out_def$queue$PlotNumber[[1L]], "00337")
})

test_that("vpro_profile evaluates both Sample_Profile SQLite table and vpro_profile_rule set algebra", {
  # 1. Stored Sample_Profile in Sample.db
  ws_sample <- vpro_connect("Sample")
  prof_tbl <- vpro_profile(ws_sample, profile_table = "Sample_Profile", scope = "su")
  expect_s3_class(prof_tbl, "vpro_profile_result")
  expect_message(print(prof_tbl), "vpro_profile_result")
  expect_equal(nrow(prof_tbl$steps), 8L)
  expect_equal(prof_tbl$steps$operation, c("Add", "Add", "Add", "Common", "Subtract", "Add", "Add", "Subtract"))
  # Step 7 adds Elevation > 500 (35 plots), Step 8 subtracts ABIELAS IS NULL (leaving 11 plots with ABIELAS)
  expect_equal(prof_tbl$steps$retained_n[[7L]], 35L)
  expect_equal(prof_tbl$steps$retained_n[[8L]], 11L)
  expect_equal(length(prof_tbl$plots), 11L)
  expect_equal(nrow(tibble::as_tibble(prof_tbl)), 11L)
  expect_type(prof_tbl$plots, "character")

  # 2. Tidy vpro_profile_rule() constructor & ordered Add / Common / Subtract across Env, Humus, Veg, and species absence
  scratch <- make_w2b_scratch()
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- build_cwh_synthesis_workspace(scratch)

  r1 <- vpro_profile_rule("Env", field = "MoistureRegime", operator = "=", value = "4", operation = "Add")
  r2 <- vpro_profile_rule("Env", field = "NutrientRegime", operator = "=", value = "D", operation = "Add")
  r3 <- vpro_profile_rule("Lump", species = "TSUGHET", layer = "Any", operator = "=", value = 0, operation = "Common")
  r4 <- vpro_profile_rule("Humus", field = "Horizon", operator = "LIKE", value = "Mo*", operation = "Subtract")
  expect_s3_class(r1, "vpro_profile_rule")
  expect_message(print(r1), "vpro_profile_rule")

  res <- vpro_profile(ws, rules = list(r1, r2, r3, r4), scope = "project", lump = TRUE)
  # r1 matches 6 SMR=4 plots (U01_01..05 + SUP_01)
  expect_equal(res$steps$retained_n[[1L]], 6L)
  # r2 adds 6 SNR=D plots ('00337' + U05_01..05) -> 12 plots
  expect_equal(res$steps$retained_n[[2L]], 12L)
  # r3 (Table == 'Lump') strictly evaluates *_Lump: U01_01..05 lump TSUGHET1/2 -> TSUGHET and are dropped,
  # while unmapped SUP_01 (raw TSUGHET) + 6 SNR=D plots pass -> 7 plots retained
  expect_equal(res$steps$retained_n[[3L]], 7L)
  # r4 subtracts plots with Humus Horizon LIKE 'Mo*' (U05_01..05 have 'Moder'; '00337' has 'Ah', SUP_01 NULL) -> leaves c('00337', 'SUP_01')
  expect_equal(res$steps$retained_n[[4L]], 2L)
  expect_identical(res$plots, c("00337", "SUP_01"))
  expect_identical(res$env$PlotNumber, c("00337", "SUP_01"))

  # Track 1B.2: Table == "Veg" stays unlumped even when lump = TRUE (U01_* carry raw TSUGHET1/TSUGHET2 while SUP_01 has raw TSUGHET)
  r3_veg <- vpro_profile_rule("Veg", species = "TSUGHET", layer = "Any", operator = "=", value = 0, operation = "Common")
  res_veg_unlumped <- vpro_profile(ws, rules = list(r1, r2, r3_veg, r4), scope = "project", lump = TRUE)
  expect_equal(res_veg_unlumped$steps$retained_n[[3L]], 11L)
  expect_true(all(c("00337", paste0("U01_0", 1:5)) %in% res_veg_unlumped$plots))

  # Verify IS NULL / IS NOT NULL and step-1 Common seeding
  res_null <- vpro_profile(
    ws,
    rules = list(
      vpro_profile_rule("Env", field = "Elevation", operator = "<", value = 260, operation = "Common"),
      vpro_profile_rule("Veg", species = "ABIEAMA", operator = "IS NULL", operation = "Common")
    ),
    scope = "su"
  )
  expect_true("00337" %in% res_null$plots)
  expect_false(any(grepl("^U01_", res_null$plots)))
})

test_that("vpro_summary_veg, vpro_summary_env, ~ breakpoint rollups, and vpro_export_xlsx work end-to-end", {
  ws <- vpro_connect("Sample")

  for (gb in c("strata", "layer", "lifeform", "total")) {
    sv <- vpro_summary_veg(ws, group_by = gb, min_constancy = 20, digits = 1L)
    expect_s3_class(sv, "vpro_summary_veg")
    expect_gt(nrow(sv$long), 10L)
    expect_gt(nrow(sv$wide), 5L)
    expect_true(all(c(
      "SiteUnit", "Group", "Species", "n_plots", "constancy", "presence_class",
      "mean_cover", "characteristic_cover", "significance_class", "prominence"
    ) %in% names(sv$long)))
    expect_true(any(grepl("_Constancy$", names(sv$wide))))
    expect_true(any(grepl("_MeanCover$", names(sv$wide))))
    expect_true(any(grepl("_Presence-Signif$", names(sv$wide))))
  }

  sv_strata <- vpro_summary_veg(ws, group_by = "strata")
  expect_message(print(sv_strata), "vpro_summary_veg")
  expect_equal(nrow(tibble::as_tibble(sv_strata, format = "wide")), nrow(sv_strata$wide))

  # ~ tilde hierarchy breakpoint rollup for vpro_summary_veg and vpro_summary_env
  sv_brk <- vpro_summary_veg(ws, group_by = "strata", hierarchy_breaks = TRUE)
  expect_true(sv_brk$hierarchy_breaks)
  expect_equal(nrow(sv_brk$units), 4L)
  expect_true(all(grepl("^ASSOC ", sv_brk$units$SiteUnit)))

  se <- vpro_summary_env(ws)
  expect_s3_class(se, "vpro_summary_env")
  expect_s3_class(se, "tbl_df")
  expect_equal(nrow(se), 11L)
  expect_true(all(c(
    "SiteUnit", "n_plots", "Zone", "SubZone", "SiteSeries",
    "elevation_mean", "elevation_min", "elevation_max",
    "slope_mean", "slope_min", "slope_max", "aspect_modal",
    "smr_modal", "smr_range", "snr_modal", "snr_range",
    "StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss"
  ) %in% names(se)))

  se_brk <- vpro_summary_env(ws, hierarchy_breaks = TRUE)
  expect_equal(nrow(se_brk), 4L)
  expect_equal(sum(se_brk$n_plots), 45L)
  expect_s3_class(tibble::as_tibble(se_brk), "tbl_df")

  # Multi-sheet .xlsx export checks
  skip_if_not_installed("writexl")
  scratch <- make_w2b_scratch()
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  diag_obj <- vpro_diagnostics(ws)
  pw_obj <- vpro_pairwise(ws)

  p_diag <- vpro_export_xlsx(diag_obj, file.path(scratch, "diag.xlsx"))
  p_pw <- vpro_export_xlsx(pw_obj, file.path(scratch, "pw.xlsx"))
  p_sv <- vpro_export_xlsx(sv_strata, file.path(scratch, "sv.xlsx"))
  p_se <- vpro_export_xlsx(se, file.path(scratch, "se.xlsx"))
  p_lst <- vpro_export_xlsx(
    list(
      "VeryLongSheetNameExceeding31Chars_A[1]" = head(se, 3),
      "verylongsheetnameexceeding31chars_b[2]" = head(se, 2)
    ),
    file.path(scratch, "custom.xlsx")
  )
  p_df <- vpro_export_xlsx(head(se, 4), file.path(scratch, "single.xlsx"))

  for (p in c(p_diag, p_pw, p_sv, p_se, p_lst, p_df)) {
    expect_true(file.exists(p))
    expect_gt(file.info(p)$size, 1000)
    z_files <- utils::unzip(p, list = TRUE)$Name
    expect_true("xl/workbook.xml" %in% z_files)
  }
  expect_equal(sum(grepl("^xl/worksheets/sheet[0-9]+\\.xml$", utils::unzip(p_diag, list = TRUE)$Name)), 3L)
  expect_equal(sum(grepl("^xl/worksheets/sheet[0-9]+\\.xml$", utils::unzip(p_pw, list = TRUE)$Name)), 3L)
  expect_equal(sum(grepl("^xl/worksheets/sheet[0-9]+\\.xml$", utils::unzip(p_sv, list = TRUE)$Name)), 3L)
  expect_equal(sum(grepl("^xl/worksheets/sheet[0-9]+\\.xml$", utils::unzip(p_se, list = TRUE)$Name)), 1L)
  expect_equal(sum(grepl("^xl/worksheets/sheet[0-9]+\\.xml$", utils::unzip(p_lst, list = TRUE)$Name)), 2L)
})
