test_that("ENG-R-003: vpro_round_ace matches Go RoundCalibratedDecimal on half-away, 15-sig-digit, and high-magnitude inputs", {
  expect_identical(vpro_round_ace(NA_real_, 2L), NA_real_)
  expect_identical(vpro_round_ace(c(NaN, Inf, -Inf), 2L), c(NA_real_, NA_real_, NA_real_))

  expect_equal(vpro_round_ace(1.005, 2L), 1.01)
  expect_equal(vpro_round_ace(-1.005, 2L), -1.01)
  expect_equal(vpro_round_ace(35.855, 2L), 35.86)
  expect_equal(vpro_round_ace(2.675, 2L), 2.68)
  expect_equal(vpro_round_ace(0.285, 2L), 0.29)
  expect_equal(vpro_round_ace(99.995, 2L), 100.0)
  expect_equal(vpro_round_ace(1.4999999999995, 0L), 1.0)
  expect_equal(vpro_round_ace(-1.4999999999995, 0L), -1.0)
  expect_equal(vpro_round_ace(1e15 + 0.5, 0L), 1e15)
  expect_equal(vpro_round_ace(1e15 + 0.5, 2L), 1e15)
  expect_identical(vpro_round_ace(100000000000.005, 6L), 100000000000.005)
  expect_identical(vpro_round_ace(1e307, 2L), 1e307)
  expect_identical(sprintf("%.1f", vpro_round_ace(-0.001, 2L)), "0.0")
  expect_identical(sprintf("%.1f", vpro_round_ace(-0.0, 2L)), "0.0")
  expect_equal(vpro_round_ace(-0.005, 2L), -0.01)
})

test_that("ENG-R-003: vpro_narrow_float32 preserves NA_real_ and rejects > MaxFloat32 and non-finite doubles", {
  expect_identical(vpro_narrow_float32(NA_real_), NA_real_)
  expect_identical(
    vpro_narrow_float32(c(NA_real_, 3.5e38, -3.5e38, 1e39, Inf, -Inf, NaN)),
    rep(NA_real_, 7L)
  )

  expect_lt(vpro_narrow_float32(99.999996), 100.0)
  expect_identical(vpro_narrow_float32(99.999999), 100.0)
  max_f32 <- (2 - 2^-23) * 2^127
  expect_identical(vpro_narrow_float32(max_f32), max_f32)
  expect_identical(vpro_narrow_float32(max_f32 * (1 + 2^-24)), NA_real_)
  expect_identical(vpro_narrow_float32(1e-50), 0.0)
  expect_identical(sprintf("%.1f", vpro_narrow_float32(-0.0)), "0.0")
})

test_that("ENG-R-003: vpro_access_to_logical and vpro_logical_to_access match Go parseBoolBytes strictly", {
  tokens <- c(
    "-1", "1", "0", "true", "TRUE", "false", "FALSE",
    "yes", "no", "t", "f", "y", "n",
    "2", "", " ", "-5", "1.0", "0.0", "on",
    "9223372036854775807", "-9223372036854775808", "9223372036854775808"
  )
  expect_identical(
    vpro_logical_to_access(tokens),
    c(
      -1L, -1L, 0L, -1L, -1L, 0L, 0L,
      NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_,
      -1L, NA_integer_, NA_integer_, -1L, NA_integer_, NA_integer_, NA_integer_,
      -1L, -1L, NA_integer_
    )
  )
  expect_identical(
    vpro_logical_to_access(c(-1, 0, 1, 2, -5, NA_real_, Inf, -Inf, NaN)),
    c(-1L, 0L, -1L, -1L, -1L, NA_integer_, NA_integer_, NA_integer_, NA_integer_)
  )
})

test_that("ENG-R-003: vpro_validate_lmh25_merge_horizon matches Go ValidateSoilHorizonDepthSign across all horizons", {
  chk <- function(t, h, u, l) {
    tryCatch(
      {
        vpro:::vpro_validate_lmh25_merge_horizon(t, h, u, l, plot = "P01")
        FALSE
      },
      error = function(e) TRUE
    )
  }

  expect_false(chk("Humus", "L", 5, 3))
  expect_true(chk("Humus", "L", 3, 5))
  expect_false(chk("Humus", "Of", 0, 10))
  expect_true(chk("Humus", "Of", 10, 0))
  expect_true(chk("Humus", "X", -1, 3))
  expect_false(chk("Humus", "X", 3, 5))
  expect_true(chk("Humus", "2H", 5, 5))
  expect_false(chk("Mineral", "A", 0, 10))
  expect_true(chk("Mineral", "A", 10, 10))
  expect_true(chk("Mineral", "A", -1, 10))
  expect_true(chk("Humus", "Oh", -1, 5))
  expect_true(chk("Humus", "FH", 5, 5))
  expect_false(chk("Humus", " of", 1, 2))
  expect_false(chk("Humus", "Lf", 2, 1))

  # Discontinuity prefixes, Hydric/Limno/Cumulo, and single-sided negative depths
  expect_false(chk("Humus", "IIOf", 0, 12))
  expect_true(chk("Humus", "IIOf", 12, 0))
  expect_false(chk("Humus", "Hydric", 0, 20))
  expect_true(chk("Humus", "Hydric", 20, 0))
  expect_true(chk("Humus", "L", -2, NA_real_))
  expect_true(chk("Humus", "Of", NA_real_, -2))
  expect_false(chk("Humus", "L", 4, NA_real_))
})

test_that("ENG-R-003: PG canonicalizers, audit row hash, and edatopic tables use half-away rounding and strict bools/covers", {
  spec <- data.frame(
    name = c("Flag", "SmallCol", "BigCol", "Cover1"),
    pg_type = c("SMALLINT", "SMALLINT", "BIGINT", "DOUBLE PRECISION"),
    sqlite_type = c("BOOLEAN", "SMALLINT", "INTEGER", "REAL"),
    is_bool = c(TRUE, FALSE, FALSE, FALSE),
    is_cover = c(FALSE, FALSE, FALSE, TRUE),
    utf16_max = c(0L, 0L, 0L, 0L),
    stringsAsFactors = FALSE
  )

  df_in <- data.frame(
    Flag = c("-1", "2", "-5", "0", "true", "false", ""),
    SmallCol = c(0.5, 1.5, 2.5, -0.5, -1.5, -2.5, NA_real_),
    BigCol = c(0.5, 1.5, 2.5, -0.5, -1.5, -2.5, NA_real_),
    Cover1 = c(99.999996, 0.0, 25.5, NA_real_, 10.0, 5.0, 0.0),
    stringsAsFactors = FALSE
  )

  pg_df <- vpro:::vpro_pg_canonicalize_to_pg(df_in, spec)
  expect_identical(pg_df$Flag, c(-1L, -1L, -1L, 0L, -1L, 0L, NA_integer_))
  expect_identical(pg_df$SmallCol, c(1L, 2L, 3L, -1L, -2L, -3L, NA_integer_))
  expect_identical(pg_df$BigCol, c(1L, 2L, 3L, -1L, -2L, -3L, NA_integer_))

  sq_df <- vpro:::vpro_pg_canonicalize_to_sqlite(df_in, spec)
  expect_identical(sq_df$SmallCol, c(1L, 2L, 3L, -1L, -2L, -3L, NA_integer_))

  tidy_df <- vpro:::vpro_pg_canonicalize_to_tidy(df_in, spec)
  expect_identical(tidy_df$SmallCol, c(1L, 2L, 3L, -1L, -2L, -3L, NA_integer_))
  expect_identical(tidy_df$Flag, c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, NA))

  for (bad_bool in c("yes", "no", "t", "f", "1.0", "on")) {
    bad_df <- data.frame(Flag = bad_bool, SmallCol = 1L, BigCol = 1L, Cover1 = 1.0, stringsAsFactors = FALSE)
    expect_error(vpro:::vpro_pg_canonicalize_to_pg(bad_df, spec), "invalid Access boolean text")
  }

  overflow_cov_df <- data.frame(Flag = "-1", SmallCol = 1L, BigCol = 1L, Cover1 = 3.5e38, stringsAsFactors = FALSE)
  expect_error(vpro:::vpro_pg_canonicalize_to_pg(overflow_cov_df, spec), "strictly under 100%")

  # vpro_pg_param_for_spec half-away rounding on SMALLINT / BIGINT
  small_spec <- spec[2L, , drop = FALSE]
  big_spec <- spec[3L, , drop = FALSE]
  expect_identical(vpro:::vpro_pg_param_for_spec(small_spec, 0.5), 1L)
  expect_identical(vpro:::vpro_pg_param_for_spec(small_spec, 2.5), 3L)
  expect_identical(vpro:::vpro_pg_param_for_spec(small_spec, -0.5), -1L)
  expect_identical(vpro:::vpro_pg_param_for_spec(small_spec, -2.5), -3L)
  expect_identical(vpro:::vpro_pg_param_for_spec(big_spec, 2.5), 3L)
  expect_identical(vpro:::vpro_pg_param_for_spec(big_spec, -2.5), -3L)

  # Edatopic tables ACE half-away rounding (e.g., mean_cover = 1.005 -> 1.01, not base round 1.00)
  pg_grid <- data.frame(
    grid_type = c("relative", "relative"),
    PlotNumber = c("P1", "P2"),
    SiteUnit = c("U1", "U1"),
    SMR = c(4L, 4L),
    SMR_exact = c(1.005, 1.005),
    SNR = c("C", "C"),
    stringsAsFactors = FALSE
  )
  veg_ed <- data.frame(
    PlotNumber = c("P1", "P2"),
    Species = c("TSUGHET", "TSUGHET"),
    Cover = c(1.005, 1.005),
    ScientificName = c("Tsuga heterophylla", "Tsuga heterophylla"),
    EnglishName = c("western hemlock", "western hemlock"),
    Lifeform = c(1L, 1L),
    stringsAsFactors = FALSE
  )
  built <- vpro:::vpro_build_edatopic_tables(pg_grid, veg_ed, min_constancy_pct = 0)
  expect_equal(built$cells$aSMR_mean[[1L]], 1.01)
  expect_equal(built$species$mean_cover[[1L]], 1.01)

  # Custodian diff snapshot half-away rounding & negative-zero normalization on SMALLINT / BIGINT (cloud_custodian_diff.R)
  env_snap_df <- data.frame(
    PlotNumber = c("P1", "P2", "P3", "P4", "P5", "P6", "P7"),
    Elevation = c(0.5, 2.5, -0.5, -2.5, -0.1, 0.0, NA_real_),
    stringsAsFactors = FALSE
  )
  snap <- vpro:::vpro_build_cloud_snapshot("source", list(Env = env_snap_df))
  elev_comp <- vapply(c("P1", "P2", "P3", "P4", "P5", "P6", "P7"), function(p) {
    snap$comp$Env[[p]]$Elevation[[1L]]
  }, character(1L), USE.NAMES = FALSE)
  elev_raw <- vapply(c("P1", "P2", "P3", "P4", "P5", "P6", "P7"), function(p) {
    snap$raw$Env[[p]]$Elevation[[1L]]
  }, numeric(1L), USE.NAMES = FALSE)
  elev_hash <- vapply(c("P1", "P2", "P3", "P4", "P5", "P6", "P7"), function(p) {
    attr(snap$raw$Env[[p]], "hash_df")$Elevation[[1L]]
  }, character(1L), USE.NAMES = FALSE)
  expect_identical(elev_comp, c("1", "3", "-1", "-3", "0", "0", NA_character_))
  expect_identical(elev_raw, c(1.0, 3.0, -1.0, -3.0, 0.0, 0.0, NA_real_))
  expect_identical(elev_hash, c("int:1", "int:3", "int:-1", "int:-3", "int:0", "int:0", "null"))
  # -0.1 and +0.0 both round to 0 and must produce identical snapshot digests (never "int:-0")
  p5_only <- vpro:::vpro_build_cloud_snapshot("source", list(Env = data.frame(PlotNumber = "PX", Elevation = -0.1, stringsAsFactors = FALSE)))
  p6_only <- vpro:::vpro_build_cloud_snapshot("source", list(Env = data.frame(PlotNumber = "PX", Elevation = 0.0, stringsAsFactors = FALSE)))
  expect_identical(vpro:::vpro_hash_cloud_snapshot(p5_only), vpro:::vpro_hash_cloud_snapshot(p6_only))
})
