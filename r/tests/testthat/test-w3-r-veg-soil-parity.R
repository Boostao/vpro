test_that("ENG-R-006: canonical LMH25 soil horizon classifier and SQL Humus ordering agree across all 5 surfaces", {
  expect_identical(
    vpro_classify_horizon(c("2Of", "2of", "Of", "of")),
    rep("wetland_organic", 4L)
  )

  hz <- c(
    "L", "F", "H", "2H", "2h", "FH", "Lf", "Hz",
    "Of", "Om", "Oh", "2Of", "2of", "IIOf", "iiof", "O", "Oe", "Op", "oe", "op", "of",
    "Hydric", "Limno", "Cumulo",
    "A", "Ah", "IXAh", "Bm1", "C", "R", "W",
    "", NA_character_
  )
  expected_reg <- c(
    rep("upland", 8L),
    rep("wetland", 16L),
    rep("", 9L)
  )
  expect_identical(vpro_lmh25_horizon_regime(hz, kind = "Humus"), expected_reg)
  expect_identical(vpro_lmh25_horizon_regime(hz, kind = "Mineral"), rep("mineral", length(hz)))

  expected_soil_hier <- ifelse(
    expected_reg == "wetland",
    "wetland_organic",
    ifelse(expected_reg == "upland", "upland_organic", "mineral")
  )
  expect_identical(vpro_classify_horizon(hz), expected_soil_hier)
  expect_identical(vpro_classify_horizon(hz, kind = "Mineral"), rep("mineral", length(hz)))

  expected_audit <- ifelse(
    expected_reg == "wetland",
    "wetland",
    ifelse(expected_reg == "upland", "upland", "other")
  )
  expected_audit[length(hz) - c(1L, 0L)] <- "surface_or_blank"
  expect_identical(vpro_classify_humus_lmh25(hz), expected_audit)
  expect_identical(vpro_classify_humus_lmh25("S"), "surface_or_blank")

  # Custodian merge validator agrees on O/Oe/Op, 2Of/2of, IIOf, Hydric/Limno/Cumulo, and 2H
  chk_err <- function(suf, h, u, l) {
    tryCatch(
      {
        vpro_validate_lmh25_merge_horizon(suf, h, u, l, plot = "P01")
        FALSE
      },
      error = function(e) TRUE
    )
  }
  for (wh in c("O", "Oe", "Op", "oe", "op", "Of", "of", "2Of", "2of", "IIOf", "Hydric", "Limno", "Cumulo")) {
    expect_false(chk_err("Humus", wh, 0, 15), info = paste("valid downward wetland:", wh))
    expect_true(chk_err("Humus", wh, 15, 0), info = paste("inverted wetland:", wh))
  }
  for (uh in c("L", "F", "H", "2H", "2h", "Lf")) {
    expect_false(chk_err("Humus", uh, 10, 2), info = paste("valid upward upland:", uh))
    expect_true(chk_err("Humus", uh, 2, 10), info = paste("inverted upland:", uh))
  }
  expect_false(chk_err("Mineral", "IXAh", 0, 12))
  expect_true(chk_err("Mineral", "IXAh", 12, 0))

  # Snapshot SQL ordering in vpro_read_workspace_vp08_table(..., "Humus") orders 2Of/2of/Oe/IIOf ascending
  d <- tempfile("snap-humus-")
  dir.create(d, recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  gz <- system.file("extdata", "Sample.db.gz", package = "vpro")
  db <- file.path(d, "Sample.db")
  writeBin(memDecompress(readBin(gz, "raw", 5e7), "gzip"), db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, 'DELETE FROM "Sample_Humus" WHERE "PlotNumber" = \'00337\'')
  ins_sql <- 'INSERT INTO "Sample_Humus" ("PlotNumber", "ID", "Horizon", "UpperDepth", "LowerDepth") VALUES (\'00337\', ?, ?, ?, ?)'
  rows_in <- list(
    list(9101L, "Hydric", 50.0, 70.0),
    list(9102L, "2H",     2.0,  0.0),
    list(9103L, "Oe",     35.0, 50.0),
    list(9104L, "2of",    15.0, 35.0),
    list(9105L, "Lv",     6.0,  2.0),
    list(9106L, "2Of",    0.0,  15.0),
    list(9107L, "Om",     NA_real_, NA_real_)
  )
  for (r in rows_in) {
    DBI::dbExecute(con, ins_sql, params = r)
  }

  hum_snap <- vpro_read_workspace_vp08_table(con, "Sample", "Humus")
  sub_00337 <- hum_snap[hum_snap$PlotNumber == "00337", , drop = FALSE]
  expect_identical(sub_00337$Horizon, c("Lv", "2H", "2Of", "2of", "Oe", "Hydric", "Om"))
})

test_that("ENG-R-006: character order() calls use radix byte order identically across LC_COLLATE locales", {
  old_loc <- Sys.getlocale("LC_COLLATE")
  on.exit(suppressWarnings(Sys.setlocale("LC_COLLATE", old_loc)), add = TRUE)

  df <- data.frame(
    PlotNumber = c("B2", "a1", "A1", "b2", "10", "9", "00337", "337"),
    Horizon = "A",
    UpperDepth = 0,
    LowerDepth = 5,
    stringsAsFactors = FALSE
  )

  lump_in <- data.frame(
    SppCode = c("SPP1", "SPP1", "SPP2", "SPP3"),
    LumpCode = c("BA1", "B-1", "AA1", "A_1"),
    Use = c(TRUE, TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  )

  for (loc in c("C", "en_US.UTF-8")) {
    res_loc <- suppressWarnings(tryCatch(Sys.setlocale("LC_COLLATE", loc), error = function(e) ""))
    if (!nzchar(res_loc)) next

    ordered_plots <- vpro_order_soil_df(df)$PlotNumber
    expect_identical(
      ordered_plots,
      c("00337", "10", "337", "9", "A1", "B2", "a1", "b2"),
      info = paste("locale =", loc)
    )

    norm_lump <- vpro_normalize_lump_tibble(lump_in)
    # In ASCII/UTF-8 radix order: '-' (45) < 'A' (65) < '_' (95), so duplicate SPP1 picks "B-1"
    expect_identical(norm_lump$LumpCode[norm_lump$SppCode == "SPP1"], "B-1")
    expect_identical(norm_lump$LumpCode, c("AA1", "A_1", "B-1"))

    # Modal tie-breaking uses radix byte order
    expect_identical(.vpro_modal_chr(c("b1", "A1", "a1", "B1")), "A1")
  }
})

test_that("ENG-R-007: singleton lump 99% cap, synonym-only fold cap, strata_totals fallback cap, and vpro_master_veg cover_precedence align", {
  d <- tempfile("veg-cap-")
  dir.create(d, recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  gz <- system.file("extdata", "Sample.db.gz", package = "vpro")
  db <- file.path(d, "Sample.db")
  writeBin(memDecompress(readBin(gz, "raw", 5e7), "gzip"), db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  lump_row <- DBI::dbGetQuery(con, 'SELECT "SppCode", "LumpCode" FROM "Sample_Lump" WHERE "Use" != 0 LIMIT 1')
  vlists_con <- DBI::dbConnect(RSQLite::SQLite(), vpro_bundled_db("VLists.db"), flags = RSQLite::SQLITE_RO)
  syn_row <- DBI::dbGetQuery(
    vlists_con,
    paste(
      'SELECT UPPER(TRIM(CAST("OldCode" AS TEXT))) AS "OldCode",',
      'UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code"',
      'FROM "USysAllSpecs"',
      'WHERE LOWER(TRIM(COALESCE("Codetype", \'\'))) = \'s\'',
      'AND UPPER(TRIM(CAST("OldCode" AS TEXT))) <> UPPER(TRIM(CAST("Code" AS TEXT)))',
      'LIMIT 1'
    )
  )
  DBI::dbDisconnect(vlists_con)

  DBI::dbExecute(con, 'INSERT INTO "Sample_Env" ("PlotNumber", "Zone", "SubZone") VALUES (\'99999\', \'SBS\', \'dk\')')
  DBI::dbExecute(con, 'INSERT INTO "Sample_Admin" ("Plot") VALUES (\'99999\')')
  DBI::dbExecute(con, 'INSERT INTO "Sample_SU" ("PlotNumber", "SiteUnit") VALUES (\'99999\', \'TEST_U1\')')

  # 1) Singleton lumped species > 99% (99.5 -> 99.0 across all readers!)
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover1", "ID") VALUES (\'99999\', ?, 99.5, 999901)',
    params = list(lump_row$SppCode[[1L]])
  )
  # 2) Unlumped singleton species > 99% (99.5 -> 99.5 uncapped!)
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover1", "ID") VALUES (\'99999\', \'TSUGHET\', 99.5, 999902)'
  )
  # 3) Synonym-only fold (OldCode + Code in Layer 6: 60 + 55 = 115 -> 99.0 even when lump = FALSE!)
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover6", "ID") VALUES (\'99999\', ?, 60.0, 999903)',
    params = list(syn_row$OldCode[[1L]])
  )
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover6", "ID") VALUES (\'99999\', ?, 55.0, 999904)',
    params = list(syn_row$Code[[1L]])
  )
  # 4) strata_totals vs sublayer_sum: TotalA=0 authoritative suppression & NULL TotalA fallback 99% cap
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover1", "TotalA", "ID") VALUES (\'99999\', \'ABIEGRA\', 25.0, 0.0, 999905)'
  )
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover1", "Cover2", "TotalA", "ID") VALUES (\'99999\', \'THUJPLI\', 60.0, 60.0, NULL, 999906)'
  )
  DBI::dbDisconnect(con)

  ws <- vpro_connect(db, su = "Sample_SU", lump = "Sample_Lump", data_dir = d, config_dir = d)
  target_lump_code <- toupper(trimws(lump_row$LumpCode[[1L]]))
  target_syn_code <- syn_row$Code[[1L]]

  # Singleton lump 99.5 -> 99.0 across raw, abcd, total, and diagnostics
  v_raw <- vpro_veg(ws, strata = "raw", lump = "Sample_Lump")
  v_abcd <- vpro_veg(ws, strata = "abcd", lump = "Sample_Lump")
  v_tot <- vpro_veg(ws, strata = "total", lump = "Sample_Lump")
  diag_lump <- .vpro_extract_plot_species_veg(ws, plot_numbers = "99999", lump = "Sample_Lump")

  expect_equal(v_raw$Cover[v_raw$PlotNumber == "99999" & v_raw$Species == target_lump_code], 99.0)
  expect_equal(v_abcd$Cover[v_abcd$PlotNumber == "99999" & v_abcd$Species == target_lump_code], 99.0)
  expect_equal(v_tot$Cover[v_tot$PlotNumber == "99999" & v_tot$Species == target_lump_code], 99.0)
  expect_equal(diag_lump$Cover[diag_lump$PlotNumber == "99999" & diag_lump$Species == target_lump_code], 99.0)

  # Unlumped singleton TSUGHET 99.5 remains 99.5
  expect_equal(v_raw$Cover[v_raw$PlotNumber == "99999" & v_raw$Species == "TSUGHET"], 99.5)
  expect_equal(diag_lump$Cover[diag_lump$PlotNumber == "99999" & diag_lump$Species == "TSUGHET"], 99.5)

  # Synonym-only fold (lump = FALSE) caps 60 + 55 at 99.0 in both vpro_veg and diagnostics
  v_syn <- vpro_veg(ws, strata = "raw", lump = FALSE, resolve_synonyms = TRUE)
  diag_syn <- .vpro_extract_plot_species_veg(ws, plot_numbers = "99999", lump = FALSE, resolve_synonyms = TRUE)
  expect_equal(v_syn$Cover[v_syn$PlotNumber == "99999" & v_syn$Species == target_syn_code], 99.0)
  expect_equal(diag_syn$Cover[diag_syn$PlotNumber == "99999" & diag_syn$Species == target_syn_code], 99.0)

  # strata_totals suppresses ABIEGRA (TotalA=0) and caps THUJPLI fallback (60+60 -> 99.0)
  v_st <- vpro_veg(ws, strata = "total", combine = "sum", lump = FALSE, cover_precedence = "strata_totals")
  diag_st <- .vpro_extract_plot_species_veg(ws, plot_numbers = "99999", lump = FALSE, cover_precedence = "strata_totals")
  expect_false("ABIEGRA" %in% v_st$Species[v_st$PlotNumber == "99999"])
  expect_false("ABIEGRA" %in% diag_st$Species[diag_st$PlotNumber == "99999"])
  expect_equal(v_st$Cover[v_st$PlotNumber == "99999" & v_st$Species == "THUJPLI"], 99.0)
  expect_equal(diag_st$Cover[diag_st$PlotNumber == "99999" & diag_st$Species == "THUJPLI"], 99.0)

  # sublayer_sum uses Cover1=25 for ABIEGRA
  v_sub <- vpro_veg(ws, strata = "total", combine = "sum", lump = FALSE, cover_precedence = "sublayer_sum")
  diag_sub <- .vpro_extract_plot_species_veg(ws, plot_numbers = "99999", lump = FALSE, cover_precedence = "sublayer_sum")
  expect_equal(v_sub$Cover[v_sub$PlotNumber == "99999" & v_sub$Species == "ABIEGRA"], 25.0)
  expect_equal(diag_sub$Cover[diag_sub$PlotNumber == "99999" & diag_sub$Species == "ABIEGRA"], 25.0)

  # vpro_master_veg accepts cover_precedence = c("strata_totals", "sublayer_sum") and shares .vpro_fold_veg_records
  expect_identical(eval(formals(vpro_master_veg)$cover_precedence), c("strata_totals", "sublayer_sum"))

  mock_raw <- data.frame(
    PlotNumber = c("00337", "00337", "00337"),
    Species = c("ABIE_RK", lump_row$SppCode[[1L]], "TSUGHET"),
    Cover1 = c(2.0, 99.5, 99.5),
    Cover2 = c(1.0, NA_real_, NA_real_),
    Cover3 = c(3.0, NA_real_, NA_real_),
    TotalA = c(3.0, NA_real_, NA_real_),
    Cover5 = c(5.0, NA_real_, NA_real_),
    TotalB = c(12.0, NA_real_, NA_real_),
    `__SiteUnit` = c("CWHvm1/01", "CWHvm1/01", "CWHvm1/01"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    vpro_assert_pg_conn = function(pg, require_custodian = FALSE) invisible(TRUE),
    vpro_pg_subset_where = function(...) list(where_sql = 'WHERE e."PlotNumber" = $1', params = list("00337")),
    vpro_pg_query = function(...) mock_raw,
    vpro_pg_load_cloud_taxonomy = function(pg, resolve_synonyms = TRUE) {
      list(
        syn_map = if (isTRUE(resolve_synonyms)) vpro_synonym_map(NULL) else character(),
        tax = vpro_taxonomy(NULL, include_synonyms = FALSE, include_user = FALSE)
      )
    }
  )

  mv_strata <- vpro_master_veg(
    pg = list(),
    plots = "00337",
    strata = "total",
    combine = "sum",
    lump = lump_row,
    cover_precedence = "strata_totals"
  )
  mv_sub <- vpro_master_veg(
    pg = list(),
    plots = "00337",
    strata = "total",
    combine = "sum",
    lump = lump_row,
    cover_precedence = "sublayer_sum"
  )
  mv_raw <- vpro_master_veg(
    pg = list(),
    plots = "00337",
    strata = "raw",
    lump = lump_row
  )
  mv_pielou <- vpro_master_veg(
    pg = list(),
    plots = "00337",
    strata = "total",
    combine = "pielou",
    lump = lump_row
  )
  expect_equal(mv_strata$Cover[mv_strata$Species == "ABIE_RK"], 15.0)
  expect_equal(mv_sub$Cover[mv_sub$Species == "ABIE_RK"], 11.0)
  expect_equal(mv_strata$Cover[mv_strata$Species == target_lump_code], 99.0)
  expect_equal(mv_strata$Cover[mv_strata$Species == "TSUGHET"], 99.0)
  expect_equal(mv_raw$Cover[mv_raw$Species == target_lump_code & mv_raw$Layer == "1"], 99.0)
  expect_equal(mv_raw$Cover[mv_raw$Species == "TSUGHET" & mv_raw$Layer == "1"], 99.5)
  expect_equal(mv_pielou$Cover[mv_pielou$Species == target_lump_code], 99.0)
  expect_equal(mv_pielou$Cover[mv_pielou$Species == "TSUGHET"], 99.5)
})
