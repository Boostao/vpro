test_that("TST01 LMH25 audit matches Go diagnostics on discontinuity prefixes and tolerances (ENG-XCUT-005)", {
  sample_src <- vpro_connect("Sample")$project_path
  tmp_db <- tempfile(fileext = ".db")
  on.exit(unlink(tmp_db), add = TRUE)
  file.copy(sample_src, tmp_db)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  DBI::dbExecute(
    con,
    paste(
      'INSERT INTO "Sample_Env" ("PlotNumber", "SubstrateDecWood", "SubstrateBedRock", "SubstrateRocks",',
      '"SubstrateMineralSoil", "SubstrateOrganicMatter", "SubstrateWater", "SoilClassGroup", "MoistureRegime", "NutrientRegime")',
      "VALUES ('TST01', 99.5, 0, 0, 0, 0, 0, 'DYB', '4', 'C')"
    )
  )
  DBI::dbExecute(con, 'INSERT INTO "Sample_Admin" ("Plot", "HumusThickness") VALUES (\'TST01\', 11.0)')
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "ID") VALUES (\'TST01\', \'L\', 10.0, 0.0, 99001), (\'TST01\', \'2Of\', 30.0, 10.0, 99002)'
  )
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Texture", "Colour", "ID") VALUES (\'TST01\', \'2Ah\', 0.0, 15.0, \'SL\', \'10YR 2/1\', 99003)'
  )
  DBI::dbDisconnect(con)

  ws <- vpro_connect(tmp_db, data_dir = tempdir(), config_dir = tempdir())
  lmh <- vpro_validate(ws, scope = "project", checks = "lmh25")$lmh25
  tst <- lmh$issues[lmh$issues$PlotNumber == "TST01", , drop = FALSE]

  expect_identical(nrow(tst), 1L)
  expect_identical(tst$rule[[1L]], "downward_depth_sign")
  expect_identical(tst$severity[[1L]], "error")
  expect_match(tst$detail[[1L]], "2OF")
})

test_that("lmh25_audit strips Arabic and Roman IVX discontinuity prefixes across Humus and Mineral and enforces max_up - min_lo HumusThickness span", {
  sample_src <- vpro_connect("Sample")$project_path
  tmp_db <- tempfile(fileext = ".db")
  on.exit(unlink(tmp_db), add = TRUE)
  file.copy(sample_src, tmp_db)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  # Plot ROM01:
  # - SubstrateSum = 98.5% -> |98.5 - 100| = 1.5 > 1.0 -> substrate_sum warning
  # - L 10..4 -> span = 6.0 cm vs Header HumusThickness = 10.0 -> diff = +4.0 > 2.0 -> humus_thickness warning
  # - Fine-textured ('C') soil with IXAh (0..4) + XAh (4..10) = 10 cm > 5 cm -> KeyedSNR = 'E' (class 4)
  #   vs Field NutrientRegime = 'B' (class 1) -> divergence 3 -> smr_snr_keys warning
  # Plot PBOG:
  # - 2Of1 (vp=6), IIOm (vp=2), XOh (vp=5) -> 3 von_post warnings
  # - Hydric (0..10), Limno (10..20), Cumulo (20..30) valid, plus inverted Cumulo (40..30) -> downward_depth_sign error
  # - Inverted 2L (0..5) -> upland_depth_sign error; inverted IXAh (10..0) & XAh (10..0) -> downward_depth_sign errors
  # Plot SAL01:
  # - IIBn triggers saline Key 9.6 -> KeyedSNR = 'F' (class 5) vs Field 'B' (class 1) -> smr_snr_keys warning
  # Plot LIT01:
  # - IIR at 10 cm on CR crest with >10% bedrock -> KeyedSMR = 0 vs Field '5' -> smr_snr_keys warning
  DBI::dbExecute(
    con,
    paste(
      'INSERT INTO "Sample_Env" ("PlotNumber", "SubstrateDecWood", "SubstrateBedRock", "SoilClassGroup",',
      '"MesoSlopePosition", "SlopeGradient", "SoilDrainage", "RootZoneParticleSize", "MoistureRegime", "NutrientRegime") VALUES',
      "('ROM01', 98.5, 0.0, 'GL', 'MD', 10.0, 'w', 'C', '4', 'B'),",
      "('PBOG', 100.0, 0.0, 'M', 'DP', 0.5, 'v', NULL, '8', 'A'),",
      "('SAL01', 100.0, 0.0, 'SZ', 'LV', 1.0, 'p', 'C', '6', 'B'),",
      "('LIT01', 80.0, 20.0, 'DYB', 'CR', 25.0, 'r', 'S', '5', 'A')"
    )
  )
  DBI::dbExecute(
    con,
    'INSERT INTO "Sample_Admin" ("Plot", "HumusThickness") VALUES (\'ROM01\', 10.0), (\'PBOG\', NULL), (\'SAL01\', NULL), (\'LIT01\', NULL)'
  )
  DBI::dbExecute(
    con,
    paste(
      'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "vonPost", "ID") VALUES',
      "('ROM01', 'L', 10.0, 4.0, NULL, 9101),",
      "('PBOG', '2Of1', 0.0, 25.0, 6, 9201),",
      "('PBOG', 'IIOm', 25.0, 50.0, 2, 9202),",
      "('PBOG', 'XOh', 50.0, 80.0, 5, 9203),",
      "('PBOG', 'Hydric', 80.0, 90.0, NULL, 9204),",
      "('PBOG', 'Limno', 90.0, 100.0, NULL, 9205),",
      "('PBOG', 'Cumulo', 100.0, 110.0, NULL, 9206),",
      "('PBOG', 'Cumulo', 40.0, 30.0, NULL, 9207),",
      "('PBOG', '2L', 0.0, 5.0, NULL, 9208)"
    )
  )
  DBI::dbExecute(
    con,
    paste(
      'INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Texture", "Colour", "ID") VALUES',
      "('ROM01', 'IXAh', 0.0, 4.0, 'C', '10YR 2/1', 9301),",
      "('ROM01', 'XAh', 4.0, 10.0, 'C', '10YR 2/1', 9302),",
      "('PBOG', 'IXAh', 10.0, 0.0, 'SL', NULL, 9303),",
      "('PBOG', 'XAh', 10.0, 0.0, 'SL', NULL, 9304),",
      "('SAL01', 'IIBn', 0.0, 25.0, 'C', '10YR 4/2', 9305),",
      "('LIT01', '2Bm', 0.0, 10.0, 'S', '10YR 5/4', 9306),",
      "('LIT01', 'IIR', 10.0, 15.0, NULL, NULL, 9307)"
    )
  )
  DBI::dbDisconnect(con)

  ws <- vpro_connect(tmp_db, data_dir = tempdir(), config_dir = tempdir())
  lmh <- vpro_validate(ws, scope = "project", checks = "lmh25")$lmh25
  issues <- lmh$issues

  rom_rules <- issues$rule[issues$PlotNumber == "ROM01"]
  expect_true(all(c("substrate_sum", "humus_thickness", "smr_snr_keys") %in% rom_rules))

  pbog <- issues[issues$PlotNumber == "PBOG", , drop = FALSE]
  expect_identical(sum(pbog$rule == "von_post"), 3L)
  expect_identical(sum(pbog$rule == "upland_depth_sign"), 1L)
  expect_identical(sum(pbog$rule == "downward_depth_sign"), 3L)
  # Valid Hydric/Limno/Cumulo rows (80..90, 90..100, 100..110) must NOT be flagged
  expect_false(any(grepl("80.0 to 90.0|90.0 to 100.0|100.0 to 110.0", pbog$detail)))

  sal <- issues[issues$PlotNumber == "SAL01" & issues$rule == "smr_snr_keys", , drop = FALSE]
  expect_true(any(grepl("'F'", sal$detail, fixed = TRUE)))

  lit <- issues[issues$PlotNumber == "LIT01" & issues$rule == "smr_snr_keys", , drop = FALSE]
  expect_true(any(grepl("0(-1)", lit$detail, fixed = TRUE)))

  # Verify wetland + mixed ordering via vpro_soil() on PBOG
  soil_pbog <- vpro_soil(ws, scope = "project", type = "humus")
  pbog_hz <- soil_pbog$Horizon[soil_pbog$PlotNumber == "PBOG"]
  # Upland '2L' first, then wetland ordered by UpperDepth ASC: 2Of1(0), IIOm(25), Cumulo(40), XOh(50), Hydric(80), Limno(90), Cumulo(100)
  expect_identical(pbog_hz, c("2L", "2Of1", "IIOm", "Cumulo", "XOh", "Hydric", "Limno", "Cumulo"))
})
