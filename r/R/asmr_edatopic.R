# Ministry CMD -> aSMR Edatopic Grid Transfer Rules ----------------------------

vpro_load_asmr_assets <- function() {
  cached <- .vpro_cache[["asmr_assets"]]
  if (!is.null(cached)) {
    return(cached)
  }
  rules_dt <- data.table::fread(vpro_bundled_file("extdata", "aSMR_Rules_HalfStep.csv"))
  cmd_adj_dt <- data.table::fread(vpro_bundled_file("extdata", "CMD_adjustments.csv"))
  bgc_norm_dt <- data.table::fread(vpro_bundled_file("extdata", "bgc_climate_normals.csv"))
  bundle <- list(
    rules = rules_dt,
    cmd_adj = cmd_adj_dt,
    bgc_normals = bgc_norm_dt
  )
  .vpro_cache[["asmr_assets"]] <- bundle
  bundle
}

vpro_parse_rsmr_digit <- function(x) {
  chr <- ifelse(is.na(x), "", trimws(as.character(x)))
  has_dig <- grepl("[0-8]", chr)
  out <- rep(NA_integer_, length(chr))
  if (any(has_dig)) {
    extracted <- sub("^[^0-8]*([0-8]).*$", "\\1", chr[has_dig])
    out[has_dig] <- suppressWarnings(as.integer(extracted))
  }
  out
}

vpro_normalize_rsnr <- function(x) {
  chr <- toupper(ifelse(is.na(x), "", trimws(as.character(x))))
  has_let <- grepl("[A-F]", chr)
  out <- rep(NA_character_, length(chr))
  if (any(has_let)) {
    let <- sub("^[^A-F]*([A-F]).*$", "\\1", chr[has_let])
    let[let == "F"] <- "E"
    out[has_let] <- let
  }
  out
}

#' Evaluate the B.C. Ministry `CMD -> aSMR` transfer rules directly
#'
#' Vectorized implementation of B.C. Ministry of Forests `_calculate_aSMR.R` +
#' `aSMR_Rules_HalfStep.csv` matching VPro Desktop `EvaluateMinistryASMR`:
#' growing-season 5-month moist surplus (`PPT_05..PPT_09 >= 90 mm`), dormant
#' recharge deficit (`max(0, 350 - (PPT_at + PPT_wt))`), steep (`> 35%`) warm SW
#' (`180..270` -> `1.25x`) and cool N (`> 315` or `< 45` -> `0.85x`) aspect
#' modifiers, topographic water-balance step adjustments across `rSMR` `0..8`,
#' and rule lookup in `[0.0, 8.0]`.
#'
#' @param cmd Numeric annual climatic moisture deficit (`CMD`).
#' @param ppt_05,ppt_06,ppt_07,ppt_08,ppt_09 Numeric May--September monthly
#'   precipitation (`mm`).
#' @param ppt_at,ppt_wt Numeric autumn and winter seasonal precipitation (`mm`).
#' @param rsmr Character or numeric relative soil moisture regime (`0..8`).
#' @param slope Numeric slope gradient in percent (`NA` treated as flat/unmodified).
#' @param aspect Numeric slope aspect in degrees (`0..360`; `NA` treated as unmodified).
#' @return A tibble with `rSMR`, `MoistMonths`, `DormantDeficit`, `AspectFactor`,
#'   `CMD_topo`, `CMD_site`, and `aSMR`.
#' @export
vpro_evaluate_asmr <- function(
  cmd,
  ppt_05,
  ppt_06,
  ppt_07,
  ppt_08,
  ppt_09,
  ppt_at,
  ppt_wt,
  rsmr,
  slope = NA_real_,
  aspect = NA_real_
) {
  rec <- vpro_value_recycle(list(
    cmd = as.double(cmd),
    ppt_05 = as.double(ppt_05),
    ppt_06 = as.double(ppt_06),
    ppt_07 = as.double(ppt_07),
    ppt_08 = as.double(ppt_08),
    ppt_09 = as.double(ppt_09),
    ppt_at = as.double(ppt_at),
    ppt_wt = as.double(ppt_wt),
    rsmr = as.character(rsmr),
    slope = as.double(slope),
    aspect = as.double(aspect)
  ))

  rules_dt <- vpro_load_asmr_assets()$rules
  rule_lvl <- as.integer(rules_dt[["SMRLevel"]])
  rule_cmd <- as.double(rules_dt[["CMD"]])
  rule_asmr <- as.double(rules_dt[["aSMR"]])

  n <- length(rec$cmd)
  r_int <- vpro_parse_rsmr_digit(rec$rsmr)
  moist_months <- rep(NA_integer_, n)
  dorm_def <- rep(NA_real_, n)
  asp_fac <- rep(NA_real_, n)
  cmd_topo <- rep(NA_real_, n)
  cmd_site <- rep(NA_real_, n)
  asmr_out <- rep(NA_real_, n)

  has_clim <- is.finite(rec$cmd) & is.finite(rec$ppt_at) & is.finite(rec$ppt_wt)
  if (any(has_clim)) {
    p_mat <- cbind(rec$ppt_05, rec$ppt_06, rec$ppt_07, rec$ppt_08, rec$ppt_09)
    for (i in which(has_clim)) {
      mc <- sum(!is.na(p_mat[i, ]) & p_mat[i, ] >= 90.0)
      moist_flag <- if (mc > 4L) 1.0 else 0.0
      mult <- 1.0 + (moist_flag / 5.0)
      cmd_gs <- rec$cmd[[i]] / mult

      ppt_dorm <- rec$ppt_at[[i]] + rec$ppt_wt[[i]]
      def_i <- max(0.0, 350.0 - ppt_dorm)
      cmd_tot <- cmd_gs + def_i

      af <- 1.0
      sl <- rec$slope[[i]]
      as_v <- rec$aspect[[i]]
      if (is.finite(sl) && is.finite(as_v) && sl > 35.0) {
        if (as_v > 180.0 && as_v < 270.0) {
          af <- 1.25
        } else if (as_v > 315.0 || (as_v >= 0.0 && as_v < 45.0)) {
          af <- 0.85
        }
      }
      ct <- vpro_go_round(cmd_tot * af * 10.0) / 10.0

      moist_months[[i]] <- as.integer(mc)
      dorm_def[[i]] <- vpro_go_round(def_i * 10.0) / 10.0
      asp_fac[[i]] <- af
      cmd_topo[[i]] <- ct

      ri <- r_int[[i]]
      if (is.na(ri) || ri < 0L || ri > 8L) {
        next
      }
      if (ri == 8L) {
        cmd_site[[i]] <- 0.0
        asmr_out[[i]] <- 8.0
        next
      }

      cs_raw <- if (ri < 4L) {
        ct + (4L - ri) * 125.0
      } else if (ri == 4L) {
        ct
      } else if (ri == 5L) {
        ct / 2.0
      } else if (ri == 6L) {
        ct / 4.0
      } else {
        ct / 8.0
      }
      cs <- vpro_go_round(max(0.0, cs_raw) * 10.0) / 10.0
      cmd_site[[i]] <- cs

      smr_lvl <- if (ri <= 4L) 0L else ri
      hits <- which(rule_lvl == smr_lvl & cs <= rule_cmd)
      asmr_out[[i]] <- if (length(hits) == 0L) 0.0 else max(rule_asmr[hits])
    }
  }

  tibble::tibble(
    rSMR = r_int,
    MoistMonths = moist_months,
    DormantDeficit = dorm_def,
    AspectFactor = asp_fac,
    CMD_topo = cmd_topo,
    CMD_site = cmd_site,
    aSMR = asmr_out
  )
}

#' Compute plot climate normals and Ministry Actual Soil Moisture Regime (`aSMR`)
#'
#' Joins plot environment (`_Env` + `*_SU`) with cached/downscaled climate
#' normals ([vpro_climate()]) and evaluates the B.C. Ministry of Forests
#' `CMD -> aSMR` transfer function (`aSMR_Rules_HalfStep.csv` &
#' `CMD_adjustments.csv`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` (active SU plots) or `"project"` (all `_Env` plots).
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`).
#' @param cache Logical; passed to [vpro_climate()] to persist new
#'   `__VPRO_PlotClimate` rows on writable user databases.
#' @param force_offline Logical; if `TRUE`, uses the offline BGC lapse-rate
#'   normals model without querying `climr`.
#' @return A tibble joining `PlotNumber` (literal character), `SiteUnit`, `Zone`,
#'   `SubZone`, `BGC`, `MoistureRegime`, `NutrientRegime`, `rSMR`, `rSNR`,
#'   `SlopeGradient`, `Aspect`, `CMD`, `CMD_topo`, `CMD_site`, `aSMR`, and
#'   climate normals.
#' @export
vpro_asmr <- function(
  ws,
  scope = c("su", "project"),
  ref_period = "1961_1990",
  cache = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  ref_period <- vpro_normalize_ref_period(ref_period)

  env_df <- vpro_env(ws, scope = scope, include_admin = TRUE)
  clim_df <- vpro_climate(
    ws,
    scope = scope,
    ref_period = ref_period,
    cache = cache,
    allow_fallback = TRUE,
    force_offline = force_offline
  )

  n <- nrow(env_df)
  if (n == 0L) {
    return(tibble::tibble(
      PlotNumber = character(),
      SiteUnit = character(),
      Zone = character(),
      SubZone = character(),
      SiteSeries = character(),
      BGC = character(),
      MoistureRegime = character(),
      NutrientRegime = character(),
      rSMR = integer(),
      rSNR = character(),
      SlopeGradient = numeric(),
      Aspect = numeric(),
      Latitude = numeric(),
      Longitude = numeric(),
      Elevation = numeric(),
      CMD = numeric(),
      CMD_topo = numeric(),
      CMD_site = numeric(),
      aSMR = numeric(),
      MoistMonths = integer(),
      DormantDeficit = numeric(),
      AspectFactor = numeric(),
      MAT = numeric(),
      MWMT = numeric(),
      MCMT = numeric(),
      MAP = numeric(),
      MSP = numeric(),
      PAS = numeric(),
      PPT_05 = numeric(),
      PPT_06 = numeric(),
      PPT_07 = numeric(),
      PPT_08 = numeric(),
      PPT_09 = numeric(),
      PPT_at = numeric(),
      PPT_wt = numeric(),
      DD5 = numeric(),
      NFFD = numeric(),
      CoordElevHash = character(),
      RefPeriod = character(),
      Source = character(),
      ComputedAt = character()
    ))
  }

  c_ix <- match(env_df$PlotNumber, clim_df$PlotNumber)
  zone_chr <- if ("Zone" %in% names(env_df)) as.character(env_df$Zone) else rep(NA_character_, n)
  subz_chr <- if ("SubZone" %in% names(env_df)) as.character(env_df$SubZone) else rep(NA_character_, n)
  bgc_fallback <- gsub(
    "[[:space:]]+",
    "",
    paste0(ifelse(is.na(zone_chr), "", zone_chr), ifelse(is.na(subz_chr), "", subz_chr))
  )
  bgc_v <- ifelse(!is.na(c_ix), clim_df$BGC[c_ix], ifelse(nzchar(bgc_fallback), bgc_fallback, NA_character_))

  mr_chr <- if ("MoistureRegime" %in% names(env_df)) as.character(env_df$MoistureRegime) else rep(NA_character_, n)
  nr_chr <- if ("NutrientRegime" %in% names(env_df)) as.character(env_df$NutrientRegime) else rep(NA_character_, n)
  slope_v <- if ("SlopeGradient" %in% names(env_df)) suppressWarnings(as.double(env_df$SlopeGradient)) else rep(NA_real_, n)
  aspect_v <- if ("Aspect" %in% names(env_df)) suppressWarnings(as.double(env_df$Aspect)) else rep(NA_real_, n)
  lat_env <- if ("Latitude" %in% names(env_df)) suppressWarnings(as.double(env_df$Latitude)) else rep(NA_real_, n)
  lon_env <- if ("Longitude" %in% names(env_df)) vpro_normalize_bc_lon(suppressWarnings(as.double(env_df$Longitude))) else rep(NA_real_, n)
  elev_env <- if ("Elevation" %in% names(env_df)) suppressWarnings(as.double(env_df$Elevation)) else rep(NA_real_, n)

  cmd_v <- clim_df$CMD[c_ix]
  p05_v <- clim_df$PPT_05[c_ix]
  p06_v <- clim_df$PPT_06[c_ix]
  p07_v <- clim_df$PPT_07[c_ix]
  p08_v <- clim_df$PPT_08[c_ix]
  p09_v <- clim_df$PPT_09[c_ix]
  pat_v <- clim_df$PPT_at[c_ix]
  pwt_v <- clim_df$PPT_wt[c_ix]

  eval_tbl <- vpro_evaluate_asmr(
    cmd = cmd_v,
    ppt_05 = p05_v,
    ppt_06 = p06_v,
    ppt_07 = p07_v,
    ppt_08 = p08_v,
    ppt_09 = p09_v,
    ppt_at = pat_v,
    ppt_wt = pwt_v,
    rsmr = mr_chr,
    slope = slope_v,
    aspect = aspect_v
  )

  ss_chr <- if ("SiteSeries" %in% names(env_df)) as.character(env_df$SiteSeries) else rep(NA_character_, n)
  out <- tibble::tibble(
    PlotNumber = as.character(env_df$PlotNumber),
    SiteUnit = as.character(env_df$SiteUnit),
    Zone = zone_chr,
    SubZone = subz_chr,
    SiteSeries = ss_chr,
    BGC = bgc_v,
    MoistureRegime = mr_chr,
    NutrientRegime = nr_chr,
    rSMR = eval_tbl$rSMR,
    rSNR = vpro_normalize_rsnr(nr_chr),
    SlopeGradient = slope_v,
    Aspect = aspect_v,
    Latitude = ifelse(!is.na(c_ix), clim_df$Latitude[c_ix], lat_env),
    Longitude = ifelse(!is.na(c_ix), clim_df$Longitude[c_ix], lon_env),
    Elevation = ifelse(!is.na(c_ix), clim_df$Elevation[c_ix], elev_env),
    CMD = cmd_v,
    CMD_topo = eval_tbl$CMD_topo,
    CMD_site = eval_tbl$CMD_site,
    aSMR = eval_tbl$aSMR,
    MoistMonths = eval_tbl$MoistMonths,
    DormantDeficit = eval_tbl$DormantDeficit,
    AspectFactor = eval_tbl$AspectFactor,
    MAT = clim_df$MAT[c_ix],
    MWMT = clim_df$MWMT[c_ix],
    MCMT = clim_df$MCMT[c_ix],
    MAP = clim_df$MAP[c_ix],
    MSP = clim_df$MSP[c_ix],
    PAS = clim_df$PAS[c_ix],
    PPT_05 = p05_v,
    PPT_06 = p06_v,
    PPT_07 = p07_v,
    PPT_08 = p08_v,
    PPT_09 = p09_v,
    PPT_at = pat_v,
    PPT_wt = pwt_v,
    DD5 = clim_df$DD5[c_ix],
    NFFD = clim_df$NFFD[c_ix],
    CoordElevHash = clim_df$CoordElevHash[c_ix],
    RefPeriod = clim_df$RefPeriod[c_ix],
    Source = clim_df$Source[c_ix],
    ComputedAt = clim_df$ComputedAt[c_ix]
  )
  attr(out, "cache_hits") <- attr(clim_df, "cache_hits")
  attr(out, "cache_misses") <- attr(clim_df, "cache_misses")
  attr(out, "skipped_no_coords") <- attr(clim_df, "skipped_no_coords")
  out
}
