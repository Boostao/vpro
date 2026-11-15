# LMH25 (2023) Pedological Rules & Workspace Standards QA ----------------------

vpro_classify_humus_lmh25 <- function(horizon, soil_group = "") {
  u <- toupper(trimws(ifelse(is.na(horizon), "", as.character(horizon))))
  sg <- toupper(trimws(ifelse(is.na(soil_group), "", as.character(soil_group))))
  if (!nzchar(u) || identical(u, "S")) {
    return("surface_or_blank")
  }
  if (grepl("^(OF|OM|OH|LIMNO|CUMULO|HYDRIC)", u) || startsWith(u, "O") ||
      grepl("^[0-9]+O[FMHP]?", u)) {
    return("wetland")
  }
  if (grepl("^[0-9]*(L|F|H)", u)) {
    if (sg %in% c("F", "M", "H") && startsWith(u, "O")) {
      return("wetland")
    }
    return("upland")
  }
  "other"
}

vpro_parse_smr_int <- function(x) {
  s <- trimws(ifelse(is.na(x), "", as.character(x)))
  if (!nzchar(s)) {
    return(NA_integer_)
  }
  m <- regexpr("[0-8]", s)
  if (m[[1L]] < 1L) {
    return(NA_integer_)
  }
  as.integer(substr(s, m[[1L]], m[[1L]]))
}

vpro_parse_snr_int <- function(x) {
  s <- toupper(trimws(ifelse(is.na(x), "", as.character(x))))
  if (!nzchar(s)) {
    return(NA_integer_)
  }
  m <- regexpr("[A-F]", s)
  if (m[[1L]] < 1L) {
    return(NA_integer_)
  }
  match(substr(s, m[[1L]], m[[1L]]), LETTERS[1L:6L]) - 1L
}

vpro_parse_munsell_value <- function(colour) {
  s <- trimws(ifelse(is.na(colour), "", as.character(colour)))
  if (!nzchar(s)) {
    return(NA_real_)
  }
  m <- regexec("(?i)(?:[0-9.]+(?:YR|Y|R|GY|G|BG|B|PB)|N)\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:/|$)", s, perl = TRUE)
  reg_m <- regmatches(s, m)[[1L]]
  if (length(reg_m) >= 2L) {
    v <- suppressWarnings(as.double(reg_m[[2L]]))
    if (is.finite(v)) return(v)
  }
  slash_pos <- regexpr("/", s, fixed = TRUE)[[1L]]
  if (slash_pos > 1L) {
    toks <- strsplit(trimws(substr(s, 1L, slash_pos - 1L)), "\\s+")[[1L]]
    if (length(toks) > 0L) {
      v <- suppressWarnings(as.double(toks[[length(toks)]]))
      if (is.finite(v)) return(v)
    }
  }
  NA_real_
}

vpro_humus_form_family <- function(code) {
  u <- toupper(trimws(ifelse(is.na(code), "", as.character(code))))
  if (u %in% c("L", "VL", "YL")) return("MULL")
  if (u %in% c("D", "LD", "MD", "RD", "SD", "TD", "YD")) return("MODER")
  if (u %in% c("R", "FR", "HR", "LR", "MR", "RR", "UR", "YR")) return("MOR")
  ""
}

vpro_infer_lmh25_keys <- function(
  env_row,
  has_peaty, peat_tot, peat_u40, peat_of_u40, peat_om_u40,
  upland_tot, upland_h,
  ah_depth, ae_depth, b_dark, b_light, has_gley, min_gley_depth, lithic_depth,
  max_min_lower, weighted_cf, cf_weight, dom_tex, has_turbation, has_saline
) {
  get_chr <- function(col) {
    if (!(col %in% names(env_row))) return("")
    v <- env_row[[col]][[1L]]
    if (is.na(v)) "" else trimws(as.character(v))
  }
  get_num <- function(col) {
    if (!(col %in% names(env_row))) return(NA_real_)
    v <- suppressWarnings(as.double(env_row[[col]][[1L]]))
    if (is.finite(v)) v else NA_real_
  }

  soil_group <- toupper(get_chr("SoilClassGroup"))
  is_org_order <- soil_group %in% c("F", "M", "H", "FO")
  meso <- toupper(get_chr("MesoSlopePosition"))
  drainage <- tolower(get_chr("SoilDrainage"))
  water_src <- toupper(get_chr("WaterSource"))
  rzps <- toupper(get_chr("RootZoneParticleSize"))
  rr_type <- toupper(get_chr("RootRestrictingType"))
  humus_form <- toupper(get_chr("HumusForm"))
  flood_freq <- toupper(get_chr("FloodingRegimeFreq"))
  surf_mat <- toupper(get_chr("SurficialMaterialSurf"))

  slope_val <- get_num("SlopeGradient")
  has_slope <- !is.na(slope_val)
  slope <- if (has_slope) slope_val else 0.0
  aspect_val <- get_num("Aspect")
  aspect <- if (!is.na(aspect_val)) as.integer(round(aspect_val)) else -1L

  # Only infer Key 9.4 / Key 9.6 divergence when sufficient site/soil indicators exist
  has_site_evidence <- nzchar(meso) || nzchar(drainage) || nzchar(rzps) ||
    nzchar(dom_tex) || has_peaty || is_org_order || cf_weight > 0
  if (!has_site_evidence) {
    return(list(smr_class = NA_integer_, smr_label = NA_character_, snr_class = NA_integer_, snr_label = NA_character_))
  }

  insolation <- slope > 35.0 && aspect >= 157L && aspect <= 285L
  cold_slope <- slope > 35.0 && aspect >= 0L && aspect != 999L && (aspect >= 337L || aspect <= 105L)

  rr_depth <- get_num("RootRestrictingDepth")
  soil_depth <- 120.0
  has_exp_depth <- FALSE
  if (!is.na(rr_depth) && rr_type != "N") {
    soil_depth <- rr_depth
    has_exp_depth <- TRUE
  }
  if (lithic_depth >= 0 && (!has_exp_depth || lithic_depth < soil_depth)) {
    soil_depth <- lithic_depth
    has_exp_depth <- TRUE
  }
  if (!has_exp_depth && max_min_lower > 0 && max_min_lower < 40 && rr_type == "L") {
    soil_depth <- max_min_lower
    has_exp_depth <- TRUE
  }

  avg_cf <- if (cf_weight > 0) weighted_cf / cf_weight else 20.0
  is_sandy <- dom_tex %in% c("S", "LS") || rzps %in% c("S", "SS")
  is_loamy <- dom_tex %in% c("SL", "L", "SCL") || rzps %in% c("CL", "L", "FL")
  is_silty <- dom_tex %in% c("SIL", "SI") || rzps %in% c("CSI", "FSI")
  is_clayey <- dom_tex %in% c("SICL", "CL", "SC", "SIC", "C") || rzps %in% c("C", "FC")

  is_fragmental <- rzps == "F" || avg_cf > 85.0
  is_coarse <- is_fragmental || rzps %in% c("S", "SS", "CI", "CLS", "AS") ||
    (is_sandy && (cf_weight == 0 || avg_cf > 35.0)) ||
    (is_loamy && avg_cf > 70.0) || avg_cf > 70.0
  is_fine <- !is_coarse && (rzps %in% c("C", "FC", "CSI", "FSI") ||
    ((is_silty || is_clayey) && (cf_weight == 0 || avg_cf <= 20.0)))

  seepage <- get_num("SeepageDepth")
  sub_water <- get_num("SubstrateWater")
  sub_bedrock <- get_num("SubstrateBedRock")
  bedrock_pct <- if (!is.na(sub_bedrock)) sub_bedrock else 0.0

  wsi <- FALSE
  wsi_depth <- 999.0
  if (!is.na(seepage) && seepage >= 0) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, seepage)
  }
  if (has_gley) {
    wsi <- TRUE
    if (min_gley_depth >= 0) wsi_depth <- min(wsi_depth, min_gley_depth)
  }
  if (has_peaty || (is_org_order && soil_group != "FO")) {
    wsi <- TRUE
    if (peat_tot >= 20 && wsi_depth > 15) wsi_depth <- 10.0
  }
  if (drainage %in% c("v", "aq", "pa", "6")) {
    wsi <- TRUE
    wsi_depth <- 0.0
  } else if (drainage %in% c("p", "ac", "5")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 20.0)
  } else if (drainage %in% c("i", "sa")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 45.0)
  }
  if (water_src %in% c("G", "S", "M", "T", "E")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 45.0)
  }

  water_at_surface <- drainage %in% c("v", "aq", "pa", "6") ||
    (!is.na(seepage) && seepage == 0) ||
    (!is.na(sub_water) && sub_water >= 25.0)
  active_fluvial <- water_src == "F" || flood_freq %in% c("A", "F") || startsWith(surf_mat, "FA")

  slope_group <- if (meso %in% c("CR", "UP")) {
    "UPPER"
  } else if (meso == "MD") {
    "MID"
  } else if (meso %in% c("LW", "TO", "GU")) {
    "LOWER"
  } else if (meso %in% c("LV", "DP")) {
    "FLAT"
  } else if (has_slope && slope < 5.0) {
    "FLAT"
  } else {
    "MID"
  }

  smr_class <- 4L
  smr_label <- "4"
  if (slope_group == "UPPER") {
    if (wsi) {
      if (wsi_depth < 30) { smr_class <- 6L; smr_label <- "6" } else { smr_class <- 5L; smr_label <- "(4)-5" }
    } else if (has_exp_depth && soil_depth < 40) {
      if (bedrock_pct > 10 || soil_depth < 20) { smr_class <- 0L; smr_label <- "0(-1)" } else { smr_class <- 1L; smr_label <- "1" }
    } else if (is_coarse) {
      if (insolation) { smr_class <- 1L; smr_label <- "1(-2)" } else if (cold_slope) { smr_class <- 3L; smr_label <- "2-3" } else { smr_class <- 2L; smr_label <- "(1-)2" }
    } else {
      if (insolation) { smr_class <- 2L; smr_label <- "2(-3)" } else if (cold_slope) { smr_class <- 4L; smr_label <- "3-4" } else { smr_class <- 3L; smr_label <- "(2-)3" }
    }
  } else if (slope_group == "MID") {
    if (wsi) {
      if (wsi_depth < 30) { smr_class <- 6L; smr_label <- "6" } else { smr_class <- 5L; smr_label <- "(4-)5" }
    } else {
      shallow <- has_exp_depth && soil_depth < 50
      if (is_coarse) {
        if (shallow && insolation) { smr_class <- 1L; smr_label <- "1-(2)" } else if (shallow || insolation) { smr_class <- 2L; smr_label <- "2" } else { smr_class <- 3L; smr_label <- "3" }
      } else {
        if (shallow && insolation) { smr_class <- 2L; smr_label <- "2" } else if (shallow || insolation) { smr_class <- if (cold_slope) 4L else 3L; smr_label <- if (cold_slope) "3-4" else "3" } else { smr_class <- 4L; smr_label <- "4" }
      }
    }
  } else if (slope_group == "LOWER") {
    if (wsi) {
      if (wsi_depth < 30) {
        if (water_at_surface) { smr_class <- 8L; smr_label <- "8" } else { smr_class <- 7L; smr_label <- "7" }
      } else {
        smr_class <- 6L; smr_label <- "6"
      }
    } else if (is_coarse) {
      smr_class <- 4L; smr_label <- "4(-5)"
    } else {
      smr_class <- 5L; smr_label <- "5(-6)"
    }
  } else {
    if ((wsi && wsi_depth < 60) || active_fluvial) {
      if (wsi && wsi_depth < 30) {
        if (water_at_surface) { smr_class <- 8L; smr_label <- "8" } else { smr_class <- 7L; smr_label <- "7" }
      } else if (is_fine) {
        smr_class <- 6L; smr_label <- "6"
      } else {
        smr_class <- 5L; smr_label <- "5"
      }
    } else if (is_coarse) {
      smr_class <- 2L; smr_label <- "2-3"
    } else if (is_fine) {
      smr_class <- 5L; smr_label <- "5"
    } else {
      smr_class <- 4L; smr_label <- "4"
    }
  }

  # Key 9.6 / 9.7 rSNR (0..5 -> A..F)
  restricted_flow <- slope < 5.0 && (drainage %in% c("p", "v", "aq", "pa", "5", "6") || is_fine)
  humus_cls <- vpro_humus_form_family(humus_form)
  is_saline <- water_src == "E" || rr_type == "X" || has_saline

  snr_class <- 2L
  snr_label <- "C"
  if (is_saline) {
    snr_class <- 5L; snr_label <- "F"
  } else if (wsi || active_fluvial) {
    if (peat_tot > 20 || (is_org_order && soil_group != "FO")) {
      of_dom <- (peat_u40 > 0 && peat_of_u40 / peat_u40 >= 0.5) || soil_group == "F"
      of_om_dom <- (peat_u40 > 0 && (peat_of_u40 + peat_om_u40) / peat_u40 >= 0.5) || soil_group == "M"
      if (of_dom) { snr_class <- 0L; snr_label <- "A-B" } else if (of_om_dom) { snr_class <- 1L; snr_label <- "B-C" } else if (restricted_flow) { snr_class <- 2L; snr_label <- "C-D" } else { snr_class <- 3L; snr_label <- "D-E" }
    } else if (wsi && wsi_depth < 30) {
      if (restricted_flow) {
        if (ah_depth > 5 || humus_cls == "MULL") { snr_class <- 2L; snr_label <- "C" } else { snr_class <- 1L; snr_label <- "B" }
      } else {
        if (ah_depth > 5 || active_fluvial || humus_cls == "MULL") { snr_class <- 3L; snr_label <- "D" } else { snr_class <- 2L; snr_label <- "C" }
      }
    } else {
      if (restricted_flow) {
        if (ah_depth > 5 || humus_cls == "MULL") { snr_class <- 3L; snr_label <- "D" } else { snr_class <- 2L; snr_label <- "C" }
      } else {
        if (ah_depth > 5 || active_fluvial || humus_cls == "MULL") { snr_class <- 4L; snr_label <- "E" } else { snr_class <- 3L; snr_label <- "D" }
      }
    }
  } else if ((has_exp_depth && soil_depth < 30) || is_fragmental || soil_group == "FO") {
    if (soil_group == "FO") {
      if ((upland_tot + soil_depth) < 30) { snr_class <- 0L; snr_label <- "A" } else if (upland_tot > 0 && upland_h / upland_tot >= 0.5) { snr_class <- 2L; snr_label <- "C" } else { snr_class <- 1L; snr_label <- "B" }
    } else if (ah_depth > 5 || b_dark || humus_cls == "MULL") {
      snr_class <- 2L; snr_label <- "C"
    } else if (b_light || ae_depth > 2 || (has_exp_depth && soil_depth < 10) || (humus_cls == "MOR" && is_coarse)) {
      snr_class <- 0L; snr_label <- "A"
    } else {
      snr_class <- 1L; snr_label <- "B"
    }
  } else if (is_coarse || (has_exp_depth && soil_depth < 50)) {
    if (ah_depth > 2 || b_dark || humus_cls == "MULL") {
      if (has_turbation || humus_cls == "MULL") { snr_class <- 3L; snr_label <- "D" } else { snr_class <- 2L; snr_label <- "C" }
    } else if (b_light || ae_depth > 2) {
      snr_class <- 0L; snr_label <- "A"
    } else if (humus_cls == "MODER") {
      snr_class <- 2L; snr_label <- "C"
    } else {
      snr_class <- 1L; snr_label <- "B"
    }
  } else {
    if (ah_depth > 2 || b_dark || humus_cls == "MULL") {
      if (is_fine && ah_depth > 5) { snr_class <- 4L; snr_label <- "E" } else { snr_class <- 3L; snr_label <- "D" }
    } else if (b_light || ae_depth > 2 || (humus_cls == "MOR" && cold_slope && upland_tot > 10)) {
      snr_class <- 1L; snr_label <- "B"
    } else if (humus_cls == "MODER" && slope_group == "LOWER") {
      snr_class <- 3L; snr_label <- "D"
    } else {
      snr_class <- 2L; snr_label <- "C"
    }
  }

  active_layer <- get_num("ActiveLayerDepth")
  if ((water_src == "Z" || rr_type == "Z" || (!is.na(active_layer) && active_layer > 0)) &&
      snr_class > 0L && snr_class < 5L) {
    snr_class <- snr_class - 1L
    snr_label <- LETTERS[[snr_class + 1L]]
  }

  list(smr_class = smr_class, smr_label = smr_label, snr_class = snr_class, snr_label = snr_label)
}

#' Audit plots against `LMH25 (2023)` pedological and edatopic consistency rules
#'
#' Evaluates `LMH25` (*Field Manual for Describing Terrestrial Ecosystems*, 2nd
#' Ed., 2023) soil, substrate, and edatopic rules calibrated to
#' `vpro_wails/internal/lmh25rules`:
#' 1. `substrate_sum`: populated 6-component surface substrates out of `[0, 100]`
#'    or not summing to `100%` (`abs(sum - 100) > 1.0`).
#' 2. `upland_depth_sign`: upland organic (`L`, `F`, `H`) horizons must measure
#'    upward from `0 cm` mineral contact (`UpperDepth > LowerDepth >= 0`).
#' 3. `downward_depth_sign`: wetland organic (`Of`, `Om`, `Oh`) and mineral (`A`,
#'    `B`, `C`, `R`, `W`) horizons must measure downward (`0 <= UpperDepth < LowerDepth`).
#' 4. `horizon_contiguity`: depth gaps or overlaps between consecutive horizons
#'    within the same plot and regime (plus lowest upland `L/F/H` not reaching
#'    `0 cm` when mineral horizons exist).
#' 5. `humus_thickness`: `_Admin.HumusThickness` differing by `> 2 cm` from
#'    `max(UpperDepth)` of upland `L/F/H` horizons when both are populated.
#' 6. `von_post`: `vonPost` decomposition scale (`1..10` overall; `Of` `1..4`,
#'    `Om` `5..6`, `Oh` `7..10`).
#' 7. `smr_snr_keys`: `LMH25` Keys `9.3 / 9.4 / 9.6` consistency (`MoistureRegime`
#'    outside `0..8`, `NutrientRegime` outside `A..F`, hydric/subhydric `rSMR >= 7`
#'    paired with rapid/well/xeric drainage or xeric `rSMR <= 1` with poor/very
#'    poor drainage, wetland `Of/Om/Oh >= 40 cm` with dry `rSMR <= 4`, and
#'    `>= 2`-class divergence from Key `9.4` / `9.6` site-soil inference).
#'
#' @param con A `vpro_workspace` handle from [vpro_connect()] or [vpro_sample()].
#' @param scope Plot scope: `"su"` (active `con$su` when set) or `"project"`.
#' @return An S3 object of class `vpro_lmh25_audit` containing `issues` tibble
#'   (`PlotNumber`, `rule`, `severity`, `detail`), `summary` tibble, and
#'   `n_plots_checked`.
#' @export
vpro_check_lmh25 <- function(con, scope = c("su", "project")) {
  vpro_assert_workspace(con)
  scope <- match.arg(scope)

  env <- vpro_env(con, scope = scope, include_admin = TRUE)
  env[["PlotNumber"]] <- as.character(env[["PlotNumber"]])
  env <- env[!duplicated(env[["PlotNumber"]]), , drop = FALSE]

  soil <- vpro_soil(con, scope = scope, type = "both")
  humus <- soil$humus
  mineral <- soil$mineral

  hum_by_plot <- if (nrow(humus) > 0L) split(humus, humus[["PlotNumber"]]) else list()
  min_by_plot <- if (nrow(mineral) > 0L) split(mineral, mineral[["PlotNumber"]]) else list()

  sub_cols <- c(
    "SubstrateDecWood", "SubstrateBedRock", "SubstrateRocks",
    "SubstrateMineralSoil", "SubstrateOrganicMatter", "SubstrateWater"
  )
  present_sub_cols <- intersect(sub_cols, names(env))

  issue_plot <- character()
  issue_rule <- character()
  issue_sev <- character()
  issue_det <- character()

  add_issue <- function(p, rule, sev, detail) {
    issue_plot[[length(issue_plot) + 1L]] <<- as.character(p)
    issue_rule[[length(issue_rule) + 1L]] <<- as.character(rule)
    issue_sev[[length(issue_sev) + 1L]] <<- as.character(sev)
    issue_det[[length(issue_det) + 1L]] <<- as.character(detail)
  }

  for (i in seq_len(nrow(env))) {
    erow <- env[i, , drop = FALSE]
    pnum <- erow[["PlotNumber"]][[1L]]
    soil_grp <- if ("SoilClassGroup" %in% names(erow) && !is.na(erow[["SoilClassGroup"]][[1L]])) {
      trimws(as.character(erow[["SoilClassGroup"]][[1L]]))
    } else {
      ""
    }

    # 1. substrate_sum
    if (length(present_sub_cols) > 0L) {
      sub_vals <- vapply(present_sub_cols, function(sc) suppressWarnings(as.double(erow[[sc]][[1L]])), numeric(1))
      pop <- !is.na(sub_vals) & is.finite(sub_vals)
      if (any(pop)) {
        for (sc_nm in present_sub_cols[pop]) {
          v <- sub_vals[[sc_nm]]
          if (v < 0 || v > 100) {
            add_issue(
              pnum, "substrate_sum", "error",
              sprintf("%s (%.2f%%) must be between 0%% and 100%%.", sc_nm, v)
            )
          }
        }
        s_tot <- sum(sub_vals[pop])
        if (abs(s_tot - 100.0) > 1.0) {
          add_issue(
            pnum, "substrate_sum", "warning",
            sprintf("Surface substrates sum to %.2f%% across %d populated field(s); LMH25 requires 100%%.", vpro_round_ace(s_tot, 2L), sum(pop))
          )
        }
      }
    }

    # 2, 3, 4, 5, 6. Humus horizons: upland_depth_sign, downward_depth_sign, von_post, contiguity, humus_thickness
    h_df <- hum_by_plot[[pnum]]
    m_df <- min_by_plot[[pnum]]

    up_valid <- list()
    wet_valid <- list()
    upland_tot <- 0.0
    upland_h <- 0.0
    has_peaty <- FALSE
    peat_tot <- 0.0
    peat_u40 <- 0.0
    peat_of_u40 <- 0.0
    peat_om_u40 <- 0.0

    if (!is.null(h_df) && nrow(h_df) > 0L) {
      for (r in seq_len(nrow(h_df))) {
        hz_raw <- h_df[["Horizon"]][[r]]
        hz <- toupper(trimws(ifelse(is.na(hz_raw), "", as.character(hz_raw))))
        h_kind <- vpro_classify_humus_lmh25(hz, soil_grp)

        # 6. von_post
        if ("vonPost" %in% names(h_df)) {
          vp <- suppressWarnings(as.double(h_df[["vonPost"]][[r]]))
          if (!is.na(vp) && is.finite(vp)) {
            if (vp < 1 || vp > 10) {
              add_issue(pnum, "von_post", "error", sprintf("Horizon %s has vonPost = %g outside valid 1..10 scale.", hz, vp))
            } else if (grepl("^[0-9]*OF", hz) && (vp < 1 || vp > 4)) {
              add_issue(pnum, "von_post", "warning", sprintf("Fibric horizon %s has vonPost = %g (LMH25 Table 2.23 expects 1..4).", hz, vp))
            } else if (grepl("^[0-9]*OM", hz) && (vp < 5 || vp > 6)) {
              add_issue(pnum, "von_post", "warning", sprintf("Mesic peat horizon %s has vonPost = %g (LMH25 Table 2.23 expects 5..6).", hz, vp))
            } else if (grepl("^[0-9]*OH", hz) && (vp < 7 || vp > 10)) {
              add_issue(pnum, "von_post", "warning", sprintf("Humic peat horizon %s has vonPost = %g (LMH25 Table 2.23 expects 7..10).", hz, vp))
            }
          }
        }

        up_d <- suppressWarnings(as.double(h_df[["UpperDepth"]][[r]]))
        lo_d <- suppressWarnings(as.double(h_df[["LowerDepth"]][[r]]))
        if (is.na(up_d) || is.na(lo_d) || !is.finite(up_d) || !is.finite(lo_d)) {
          next
        }

        if (identical(h_kind, "upland")) {
          if (up_d <= lo_d || lo_d < 0 || up_d < 0) {
            add_issue(
              pnum, "upland_depth_sign", "error",
              sprintf("Upland horizon %s (%.1f to %.1f cm) must have UpperDepth > LowerDepth >= 0.", hz, up_d, lo_d)
            )
          } else {
            up_valid[[length(up_valid) + 1L]] <- list(hz = hz, up = up_d, lo = lo_d)
            thick <- up_d - lo_d
            upland_tot <- upland_tot + thick
            if (grepl("^[0-9]*H", hz)) upland_h <- upland_h + thick
          }
        } else if (identical(h_kind, "wetland")) {
          has_peaty <- TRUE
          if (up_d < 0 || lo_d < 0 || up_d >= lo_d) {
            add_issue(
              pnum, "downward_depth_sign", "error",
              sprintf("Wetland organic horizon %s (%.1f to %.1f cm) must have 0 <= UpperDepth < LowerDepth.", hz, up_d, lo_d)
            )
          } else {
            wet_valid[[length(wet_valid) + 1L]] <- list(hz = hz, up = up_d, lo = lo_d)
            peat_tot <- peat_tot + (lo_d - up_d)
            t_s <- max(0.0, up_d)
            t_e <- min(40.0, lo_d)
            if (t_e > t_s) {
              sp <- t_e - t_s
              peat_u40 <- peat_u40 + sp
              if (grepl("^[0-9]*OF", hz)) peat_of_u40 <- peat_of_u40 + sp
              if (grepl("^[0-9]*OM", hz)) peat_om_u40 <- peat_om_u40 + sp
            }
          }
        }
      }
    }

    # 5. humus_thickness (> 2 cm discrepancy between _Admin.HumusThickness and max(UpperDepth) of upland L/F/H)
    if (length(up_valid) > 0L && "HumusThickness" %in% names(erow)) {
      hdr_ht <- suppressWarnings(as.double(erow[["HumusThickness"]][[1L]]))
      if (!is.na(hdr_ht) && is.finite(hdr_ht)) {
        max_up <- max(vapply(up_valid, `[[`, numeric(1), "up"))
        if (abs(hdr_ht - max_up) > 2.0) {
          add_issue(
            pnum, "humus_thickness", "warning",
            sprintf("Header HumusThickness (%.1f cm) differs from max upland L/F/H UpperDepth (%.1f cm) by %.1f cm.", hdr_ht, max_up, hdr_ht - max_up)
          )
        }
      }
    }

    # Mineral horizons: downward_depth_sign + pedological indicators
    min_valid <- list()
    ah_depth <- 0.0
    ae_depth <- 0.0
    b_dark <- FALSE
    b_light <- FALSE
    has_gley <- FALSE
    min_gley_depth <- -1.0
    lithic_depth <- -1.0
    max_min_lower <- 0.0
    weighted_cf <- 0.0
    cf_weight <- 0.0
    dom_tex <- ""
    max_tex_thick <- 0.0
    has_turbation <- FALSE
    has_saline <- FALSE

    if (!is.null(m_df) && nrow(m_df) > 0L) {
      for (r in seq_len(nrow(m_df))) {
        mz_raw <- ifelse(is.na(m_df[["Horizon"]][[r]]), "", trimws(as.character(m_df[["Horizon"]][[r]])))
        mz <- toupper(mz_raw)
        mz_low <- tolower(mz_raw)
        up_d <- suppressWarnings(as.double(m_df[["UpperDepth"]][[r]]))
        lo_d <- suppressWarnings(as.double(m_df[["LowerDepth"]][[r]]))

        if (grepl("g", mz_low, fixed = TRUE) || startsWith(mz, "W")) {
          has_gley <- TRUE
          if (!is.na(up_d) && is.finite(up_d) && (min_gley_depth < 0 || up_d < min_gley_depth)) {
            min_gley_depth <- up_d
          }
        }
        if (grepl("u", mz_low, fixed = TRUE) || (startsWith(mz, "A") && grepl("b", mz_low, fixed = TRUE))) {
          has_turbation <- TRUE
        }
        if (grepl("sa", mz_low, fixed = TRUE) || (startsWith(mz, "B") && grepl("n", mz_low, fixed = TRUE))) {
          has_saline <- TRUE
        }
        if ("MineralFormpH" %in% names(m_df)) {
          mph <- suppressWarnings(as.double(m_df[["MineralFormpH"]][[r]]))
          if (!is.na(mph) && is.finite(mph) && mph > 8.2) has_saline <- TRUE
        }
        if (startsWith(mz, "R") && !is.na(up_d) && is.finite(up_d)) {
          if (lithic_depth < 0 || up_d < lithic_depth) lithic_depth <- up_d
        }
        if (startsWith(mz, "B") && "Colour" %in% names(m_df)) {
          mval <- vpro_parse_munsell_value(m_df[["Colour"]][[r]])
          if (!is.na(mval)) {
            if (mval <= 3.0) b_dark <- TRUE
            if (mval >= 7.0) b_light <- TRUE
          }
        }

        if (is.na(up_d) || is.na(lo_d) || !is.finite(up_d) || !is.finite(lo_d)) {
          next
        }
        if (up_d < 0 || lo_d < 0 || up_d >= lo_d) {
          add_issue(
            pnum, "downward_depth_sign", "error",
            sprintf("Mineral horizon %s (%.1f to %.1f cm) must have 0 <= UpperDepth < LowerDepth.", mz, up_d, lo_d)
          )
          next
        }

        min_valid[[length(min_valid) + 1L]] <- list(hz = mz, up = up_d, lo = lo_d)
        thick <- lo_d - up_d
        if (lo_d > max_min_lower) max_min_lower <- lo_d
        if (grepl("^[0-9]*(AH|AP)", mz)) ah_depth <- ah_depth + thick
        if (grepl("^[0-9]*AE", mz)) ae_depth <- ae_depth + thick

        if ("PercentCoarseFragsTotal" %in% names(m_df) && up_d < 100) {
          cf_val <- suppressWarnings(as.double(m_df[["PercentCoarseFragsTotal"]][[r]]))
          if (!is.na(cf_val) && is.finite(cf_val)) {
            weighted_cf <- weighted_cf + cf_val * thick
            cf_weight <- cf_weight + thick
          }
        }
        if ("Texture" %in% names(m_df)) {
          tx <- toupper(trimws(ifelse(is.na(m_df[["Texture"]][[r]]), "", as.character(m_df[["Texture"]][[r]]))))
          if (nzchar(tx) && thick > max_tex_thick) {
            max_tex_thick <- thick
            dom_tex <- tx
          }
        }
      }
    }

    # 4. horizon_contiguity
    if (length(up_valid) >= 2L) {
      ord_u <- order(-vapply(up_valid, `[[`, numeric(1), "up"))
      up_sorted <- up_valid[ord_u]
      for (k_ix in seq_len(length(up_sorted) - 1L)) {
        cur <- up_sorted[[k_ix]]
        nxt <- up_sorted[[k_ix + 1L]]
        diff_d <- cur$lo - nxt$up
        if (abs(diff_d) > 0.01) {
          kind_str <- if (diff_d > 0) "gap" else "overlap"
          add_issue(
            pnum, "horizon_contiguity", "warning",
            sprintf("Upland humus contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", kind_str, cur$hz, cur$lo, nxt$hz, nxt$up)
          )
        }
      }
    }
    if (length(up_valid) >= 1L && length(min_valid) >= 1L) {
      min_lo_u <- min(vapply(up_valid, `[[`, numeric(1), "lo"))
      if (min_lo_u > 0.01) {
        add_issue(
          pnum, "horizon_contiguity", "warning",
          sprintf("Lowest upland L/F/H horizon ends at %.1f cm instead of 0 cm mineral contact.", min_lo_u)
        )
      }
    }
    if (length(wet_valid) >= 2L) {
      ord_w <- order(vapply(wet_valid, `[[`, numeric(1), "up"))
      wet_sorted <- wet_valid[ord_w]
      for (k_ix in seq_len(length(wet_sorted) - 1L)) {
        cur <- wet_sorted[[k_ix]]
        nxt <- wet_sorted[[k_ix + 1L]]
        diff_d <- nxt$up - cur$lo
        if (abs(diff_d) > 0.01) {
          kind_str <- if (diff_d > 0) "gap" else "overlap"
          add_issue(
            pnum, "horizon_contiguity", "warning",
            sprintf("Wetland organic contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", kind_str, cur$hz, cur$lo, nxt$hz, nxt$up)
          )
        }
      }
    }
    if (length(min_valid) >= 2L) {
      ord_m <- order(vapply(min_valid, `[[`, numeric(1), "up"))
      min_sorted <- min_valid[ord_m]
      for (k_ix in seq_len(length(min_sorted) - 1L)) {
        cur <- min_sorted[[k_ix]]
        nxt <- min_sorted[[k_ix + 1L]]
        diff_d <- nxt$up - cur$lo
        if (abs(diff_d) > 0.01) {
          kind_str <- if (diff_d > 0) "gap" else "overlap"
          add_issue(
            pnum, "horizon_contiguity", "warning",
            sprintf("Mineral horizon contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", kind_str, cur$hz, cur$lo, nxt$hz, nxt$up)
          )
        }
      }
    }

    # 7. smr_snr_keys (MoistureRegime 0..8, NutrientRegime A..F, drainage/peat consistency, Key 9.4/9.6 inference)
    raw_smr <- if ("MoistureRegime" %in% names(erow) && !is.na(erow[["MoistureRegime"]][[1L]])) {
      trimws(as.character(erow[["MoistureRegime"]][[1L]]))
    } else {
      ""
    }
    raw_snr <- if ("NutrientRegime" %in% names(erow) && !is.na(erow[["NutrientRegime"]][[1L]])) {
      trimws(as.character(erow[["NutrientRegime"]][[1L]]))
    } else {
      ""
    }
    raw_drn <- if ("SoilDrainage" %in% names(erow) && !is.na(erow[["SoilDrainage"]][[1L]])) {
      tolower(trimws(as.character(erow[["SoilDrainage"]][[1L]])))
    } else {
      ""
    }

    smr_int <- vpro_parse_smr_int(raw_smr)
    snr_int <- vpro_parse_snr_int(raw_snr)

    if (nzchar(raw_smr) && (is.na(smr_int) || !grepl("^[0-8]([+-]|[-/][0-8])?$", raw_smr))) {
      if (is.na(smr_int) || suppressWarnings(!is.na(as.numeric(raw_smr)) && (as.numeric(raw_smr) < 0 || as.numeric(raw_smr) > 8))) {
        add_issue(
          pnum, "smr_snr_keys", "error",
          sprintf("MoistureRegime '%s' is outside valid LMH25 rSMR classes 0..8.", raw_smr)
        )
        smr_int <- NA_integer_
      }
    }
    if (nzchar(raw_snr) && (is.na(snr_int) || !grepl("^[A-Fa-f]([+-]|[-/][A-Fa-f])?$", raw_snr))) {
      if (is.na(snr_int) || !grepl("^[A-Fa-f]", raw_snr)) {
        add_issue(
          pnum, "smr_snr_keys", "error",
          sprintf("NutrientRegime '%s' is outside valid LMH25 rSNR classes A..F.", raw_snr)
        )
        snr_int <- NA_integer_
      }
    }

    if (!is.na(smr_int)) {
      if (smr_int >= 7L && raw_drn %in% c("1", "2", "x", "vr", "r", "w", "very rapidly", "rapidly", "well")) {
        add_issue(
          pnum, "smr_snr_keys", "warning",
          sprintf("Subhydric/hydric MoistureRegime (%s) conflicts with xeric/rapid/well SoilDrainage ('%s').", raw_smr, raw_drn)
        )
      } else if (smr_int <= 1L && raw_drn %in% c("5", "6", "p", "v", "vp", "aq", "pa", "poorly", "very poorly")) {
        add_issue(
          pnum, "smr_snr_keys", "warning",
          sprintf("Very xeric/xeric MoistureRegime (%s) conflicts with poor/very poor SoilDrainage ('%s').", raw_smr, raw_drn)
        )
      }
      if (peat_tot >= 40.0 && smr_int <= 4L) {
        add_issue(
          pnum, "smr_snr_keys", "warning",
          sprintf("Wetland Of/Om/Oh peat thickness is %.1f cm (>= 40 cm) but MoistureRegime is '%s' (<= 4).", peat_tot, raw_smr)
        )
      }
    }

    keyed <- vpro_infer_lmh25_keys(
      erow,
      has_peaty, peat_tot, peat_u40, peat_of_u40, peat_om_u40,
      upland_tot, upland_h,
      ah_depth, ae_depth, b_dark, b_light, has_gley, min_gley_depth, lithic_depth,
      max_min_lower, weighted_cf, cf_weight, dom_tex, has_turbation, has_saline
    )
    if (!is.na(smr_int) && !is.na(keyed$smr_class) && abs(smr_int - keyed$smr_class) >= 2L) {
      add_issue(
        pnum, "smr_snr_keys", "warning",
        sprintf("Field MoistureRegime ('%s') diverges by %d classes from LMH25 Key 9.4 inference ('%s').", raw_smr, abs(smr_int - keyed$smr_class), keyed$smr_label)
      )
    }
    if (!is.na(snr_int) && !is.na(keyed$snr_class) && abs(snr_int - keyed$snr_class) >= 2L) {
      add_issue(
        pnum, "smr_snr_keys", "warning",
        sprintf("Field NutrientRegime ('%s') diverges by %d classes from LMH25 Key 9.6 inference ('%s').", raw_snr, abs(snr_int - keyed$snr_class), keyed$snr_label)
      )
    }
  }

  issues_tbl <- tibble::tibble(
    PlotNumber = issue_plot,
    rule = issue_rule,
    severity = issue_sev,
    detail = issue_det
  )

  summary_tbl <- if (nrow(issues_tbl) == 0L) {
    tibble::tibble(rule = character(), severity = character(), n_issues = integer(), n_plots = integer())
  } else {
    dt_s <- data.table::as.data.table(issues_tbl)
    agg_s <- dt_s[, list(
      n_issues = as.integer(length(get("PlotNumber"))),
      n_plots = as.integer(length(unique(get("PlotNumber"))))
    ), by = c("rule", "severity")]
    data.table::setorderv(agg_s, c("rule", "severity"))
    tibble::as_tibble(agg_s)
  }

  structure(
    list(
      issues = issues_tbl,
      summary = summary_tbl,
      n_plots_checked = as.integer(nrow(env))
    ),
    class = "vpro_lmh25_audit"
  )
}

#' Print an `LMH25 (2023)` pedological audit summary
#'
#' @param x A `vpro_lmh25_audit` object from [vpro_check_lmh25()].
#' @param ... Unused additional arguments.
#' @return `x`, invisibly.
#' @export
print.vpro_lmh25_audit <- function(x, ...) {
  n_err <- sum(x$issues[["severity"]] == "error")
  n_wrn <- sum(x$issues[["severity"]] == "warning")
  b1 <- sprintf("Plots checked: %d", x$n_plots_checked)
  b2 <- sprintf("Findings: %d (%d errors, %d warnings)", nrow(x$issues), n_err, n_wrn)
  cli::cli_h3("vpro_lmh25_audit (LMH25 2023)")
  cli::cli_bullets(c("*" = b1, "*" = b2))
  invisible(x)
}

#' Coerce a `vpro_lmh25_audit` result to its issues tibble
#'
#' @param x A `vpro_lmh25_audit` object from [vpro_check_lmh25()].
#' @param ... Unused additional arguments.
#' @return The `$issues` tibble (`PlotNumber`, `rule`, `severity`, `detail`).
#' @export
as_tibble.vpro_lmh25_audit <- function(x, ...) {
  x$issues
}

#' Run comprehensive VPro workspace standards, referential, and `LMH25` QA
#'
#' Combines five canonical VPro validation engines into a single read-only
#' quality-assurance bundle:
#' 1. **`env_codes`**: `USysTableOfLists` picklist validation (`Validate != 0`,
#'    expanding positive `ValidateLoops` such as `SiteDisturbance1..3`, calibrated
#'    to `V7mdlReportsValidateEnvData`).
#' 2. **`veg_codes`**: `BCPlantTaxonomy v19` (`USysAllSpecs`) + user species
#'    (`USysUserSpp`) check for unlisted codes and `OldCode -> Code` synonyms
#'    (calibrated to `V7mdlReportsValidateVegCodes`).
#' 3. **`orphans`**: referential integrity across `_Env <-> _Admin`, `_Veg`,
#'    `_Humus`, `_Mineral`, `_Other`, and active `*_SU`, plus plots without
#'    vegetation (`V7mdlReportValidation`).
#' 4. **`duplicates`**: duplicate physical `(PlotNumber, Species)` rows and
#'    same-layer cover collisions (`V7mdlOptimizeVeg.Check4DuplicatedSpecies`).
#' 5. **`lmh25`**: pedological and edatopic audit via [vpro_check_lmh25()].
#'
#' @param con A `vpro_workspace` handle from [vpro_connect()] or [vpro_sample()].
#' @param scope Validation scope: `"su"` (restricts plot-scoped checks to active
#'   `con$su` when set) or `"project"` (validates the entire `<Project>`).
#' @return An S3 object of class `vpro_validation` containing `$issues`,
#'   `$env_codes`, `$veg_codes`, `$orphans`, `$duplicates`, `$lmh25`,
#'   `$skipped_definitions`, and `$passed`.
#' @export
vpro_validate <- function(con, scope = c("su", "project")) {
  vpro_assert_workspace(con)
  scope <- match.arg(scope)
  use_su <- identical(scope, "su") && !is.null(con$su)

  dbc <- vpro_sqlite_ro(con$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  dbc_vlists <- vpro_sqlite_ro(con$vlists_path)
  on.exit(DBI::dbDisconnect(dbc_vlists), add = TRUE)

  su_df <- if (!is.null(con$su)) vpro_site_units(con, exclude_modifiers = FALSE) else {
    tibble::tibble(PlotNumber = character(), SiteUnit = character())
  }
  su_plots <- unique(as.character(su_df[["PlotNumber"]]))

  env_tbl <- paste0(con$project, "_Env")
  adm_tbl <- paste0(con$project, "_Admin")
  veg_tbl <- paste0(con$project, "_Veg")
  env_q <- vpro_quote_ident(env_tbl)
  adm_q <- vpro_quote_ident(adm_tbl)
  veg_q <- vpro_quote_ident(veg_tbl)

  # 1. USysTableOfLists environment code picklist validation
  env_cols <- DBI::dbListFields(dbc, env_tbl)
  adm_cols <- if (DBI::dbExistsTable(dbc, adm_tbl)) DBI::dbListFields(dbc, adm_tbl) else character()
  env_col_map <- stats::setNames(env_cols, tolower(env_cols))
  adm_col_map <- stats::setNames(adm_cols, tolower(adm_cols))

  defs <- DBI::dbGetQuery(
    dbc_vlists,
    paste(
      'SELECT COALESCE(MIN("ListName"), \'\') AS "ListName",',
      'COALESCE(MIN("FieldUsedIn"), \'\') AS "FieldUsedIn",',
      'COALESCE(CAST("ValidateLoops" AS TEXT), \'\') AS "ValidateLoops"',
      'FROM "USysTableOfLists"',
      'WHERE "Validate" IS NOT NULL AND "Validate" <> 0',
      'GROUP BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"',
      'ORDER BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"'
    )
  )
  all_list_rows <- DBI::dbGetQuery(
    dbc_vlists,
    'SELECT "ListName", "Item" FROM "USysTableOfLists" WHERE "ListName" IS NOT NULL AND "Item" IS NOT NULL'
  )

  # Query Env and Admin separately to avoid column collision in R
  env_valid_plots <- DBI::dbGetQuery(
    dbc,
    paste0(
      "SELECT CAST(env.\"PlotNumber\" AS TEXT) AS \"PlotNumber\" FROM ",
      env_q, " AS env INNER JOIN ", adm_q,
      " AS admin ON typeof(env.\"PlotNumber\") = 'text' AND typeof(admin.\"Plot\") = 'text' ",
      "AND CAST(env.\"PlotNumber\" AS BLOB) = CAST(admin.\"Plot\" AS BLOB)"
    )
  )[["PlotNumber"]]
  if (use_su) {
    env_valid_plots <- intersect(env_valid_plots, su_plots)
  }

  env_raw <- vpro_query_scoped_plots(dbc, env_q, env_valid_plots)
  env_raw[["PlotNumber"]] <- as.character(env_raw[["PlotNumber"]])
  adm_raw <- if (length(env_valid_plots) > 0L) {
    a_all <- DBI::dbGetQuery(dbc, paste0('SELECT CAST("Plot" AS TEXT) AS "__Plot__", * FROM ', adm_q, ' WHERE typeof("Plot") = \'text\''))
    a_all[a_all[["__Plot__"]] %in% env_valid_plots, , drop = FALSE]
  } else {
    DBI::dbGetQuery(dbc, paste0('SELECT CAST("Plot" AS TEXT) AS "__Plot__", * FROM ', adm_q, ' WHERE 1 = 0'))
  }

  ec_list <- character()
  ec_field <- character()
  ec_plot <- character()
  ec_val <- character()
  sk_list <- character()
  sk_field <- character()
  sk_reason <- character()

  for (di in seq_len(nrow(defs))) {
    ln <- defs[["ListName"]][[di]]
    fu <- defs[["FieldUsedIn"]][[di]]
    lp <- trimws(defs[["ValidateLoops"]][[di]])
    if (!nzchar(trimws(ln))) {
      sk_list <- c(sk_list, ln); sk_field <- c(sk_field, fu); sk_reason <- c(sk_reason, "ListName is blank")
      next
    }
    if (!nzchar(trimws(fu))) {
      sk_list <- c(sk_list, ln); sk_field <- c(sk_field, fu); sk_reason <- c(sk_reason, "FieldUsedIn is blank")
      next
    }
    expanded <- fu
    if (nzchar(lp)) {
      if (!grepl("^-?[0-9]+$", lp)) {
        sk_list <- c(sk_list, ln); sk_field <- c(sk_field, fu); sk_reason <- c(sk_reason, "ValidateLoops is not an integer")
        next
      }
      n_lp <- as.integer(lp)
      if (n_lp > 0L) {
        expanded <- paste0(fu, seq_len(n_lp))
      }
    }

    allowed_low <- tolower(all_list_rows[["Item"]][tolower(all_list_rows[["ListName"]]) == tolower(ln)])

    for (fld in expanded) {
      lf <- tolower(fld)
      in_e <- lf %in% names(env_col_map)
      in_a <- lf %in% names(adm_col_map)
      if (in_e && in_a) {
        sk_list <- c(sk_list, ln); sk_field <- c(sk_field, fld); sk_reason <- c(sk_reason, "Field is ambiguous across Env and Admin")
        next
      }
      if (!in_e && !in_a) {
        sk_list <- c(sk_list, ln); sk_field <- c(sk_field, fld); sk_reason <- c(sk_reason, "Field not found in Env/Admin schema")
        next
      }
      if (in_e) {
        actual <- unname(env_col_map[[lf]])
        p_vec <- env_raw[["PlotNumber"]]
        v_vec <- env_raw[[actual]]
      } else {
        actual <- unname(adm_col_map[[lf]])
        p_vec <- adm_raw[["__Plot__"]]
        v_vec <- adm_raw[[actual]]
      }
      v_chr <- ifelse(is.na(v_vec), "", as.character(v_vec))
      bad <- !is.na(v_vec) & nzchar(v_chr) & !(tolower(v_chr) %in% allowed_low)
      if (any(bad)) {
        pairs <- unique(data.frame(p = p_vec[bad], v = v_chr[bad], stringsAsFactors = FALSE))
        pairs <- pairs[order(pairs$p, pairs$v), , drop = FALSE]
        ec_list <- c(ec_list, rep(ln, nrow(pairs)))
        ec_field <- c(ec_field, rep(fld, nrow(pairs)))
        ec_plot <- c(ec_plot, pairs$p)
        ec_val <- c(ec_val, pairs$v)
      }
    }
  }

  env_codes_tbl <- tibble::tibble(
    list_name = ec_list,
    field = ec_field,
    PlotNumber = ec_plot,
    value = ec_val
  )
  skipped_tbl <- tibble::tibble(
    list_name = sk_list,
    field = sk_field,
    reason = sk_reason
  )

  # 2. USysAllSpecs + USysUserSpp species code validation
  specs_all <- DBI::dbGetQuery(
    dbc_vlists,
    'SELECT COALESCE(CAST("Code" AS TEXT), \'\') AS "Code", COALESCE(CAST("OldCode" AS TEXT), \'\') AS "OldCode", COALESCE(LOWER(TRIM(CAST("Codetype" AS TEXT))), \'\') AS "Codetype" FROM "USysAllSpecs"'
  )
  accepted_low <- unique(tolower(specs_all[["Code"]][nzchar(specs_all[["Code"]]) & specs_all[["Codetype"]] != "s"]))
  syn_rows <- specs_all[nzchar(specs_all[["OldCode"]]) & nzchar(specs_all[["Code"]]) & tolower(specs_all[["OldCode"]]) != tolower(specs_all[["Code"]]), , drop = FALSE]
  syn_rows <- syn_rows[!duplicated(tolower(syn_rows[["OldCode"]])), , drop = FALSE]
  syn_map <- stats::setNames(syn_rows[["Code"]], tolower(syn_rows[["OldCode"]]))

  user_low <- character()
  if (file.exists(con$vuser_path)) {
    dbc_vuser <- vpro_sqlite_ro(con$vuser_path)
    on.exit(DBI::dbDisconnect(dbc_vuser), add = TRUE)
    if (DBI::dbExistsTable(dbc_vuser, "USysUserSpp")) {
      u_df <- DBI::dbGetQuery(dbc_vuser, 'SELECT COALESCE(CAST("Code" AS TEXT), \'\') AS "Code" FROM "USysUserSpp"')
      user_low <- unique(tolower(u_df[["Code"]][nzchar(u_df[["Code"]])]))
    }
  }

  veg_scope_plots <- if (use_su) su_plots else NULL
  veg_codes_raw <- if (use_su) {
    vpro_query_scoped_plots(
      dbc, veg_q, veg_scope_plots,
      select_cols = 'CAST("PlotNumber" AS TEXT) AS "PlotNumber", CAST("Species" AS TEXT) AS "Species"'
    )
  } else {
    DBI::dbGetQuery(dbc, paste0('SELECT COALESCE(CAST("PlotNumber" AS TEXT), \'\') AS "PlotNumber", CAST("Species" AS TEXT) AS "Species" FROM ', veg_q))
  }

  vc_plot <- character()
  vc_spp <- character()
  vc_status <- character()
  vc_sugg <- character()

  if (nrow(veg_codes_raw) > 0L) {
    uniq_vs <- unique(veg_codes_raw)
    uniq_vs <- uniq_vs[order(uniq_vs[["PlotNumber"]], uniq_vs[["Species"]]), , drop = FALSE]
    for (vi in seq_len(nrow(uniq_vs))) {
      p_v <- as.character(uniq_vs[["PlotNumber"]][[vi]])
      s_v <- uniq_vs[["Species"]][[vi]]
      s_chr <- ifelse(is.na(s_v), "", as.character(s_v))
      s_low <- tolower(s_chr)
      if (!nzchar(trimws(s_chr))) {
        vc_plot <- c(vc_plot, p_v); vc_spp <- c(vc_spp, s_chr); vc_status <- c(vc_status, "unlisted"); vc_sugg <- c(vc_sugg, NA_character_)
      } else if (s_low %in% accepted_low || s_low %in% user_low) {
        next
      } else if (s_low %in% names(syn_map)) {
        vc_plot <- c(vc_plot, p_v); vc_spp <- c(vc_spp, s_chr); vc_status <- c(vc_status, "synonym"); vc_sugg <- c(vc_sugg, unname(syn_map[[s_low]]))
      } else {
        vc_plot <- c(vc_plot, p_v); vc_spp <- c(vc_spp, s_chr); vc_status <- c(vc_status, "unlisted"); vc_sugg <- c(vc_sugg, NA_character_)
      }
    }
  }
  veg_codes_tbl <- tibble::tibble(
    PlotNumber = vc_plot,
    Species = vc_spp,
    status = vc_status,
    suggested_code = vc_sugg
  )

  # 3. Referential / orphan child check (_Admin, _Veg, _Humus, _Mineral, _Other, *_SU) & plots_without_veg
  or_tbl <- character()
  or_plot <- character()
  or_issue <- character()
  or_n <- integer()

  miss_adm <- DBI::dbGetQuery(
    dbc,
    paste0(
      'SELECT CAST(e."PlotNumber" AS TEXT) AS "PlotNumber" FROM ', env_q, ' AS e ',
      'WHERE NOT EXISTS (SELECT 1 FROM ', adm_q, ' AS a WHERE typeof(a."Plot") = \'text\' AND typeof(e."PlotNumber") = \'text\' AND CAST(a."Plot" AS BLOB) = CAST(e."PlotNumber" AS BLOB)) ORDER BY 1'
    )
  )
  if (nrow(miss_adm) > 0L) {
    or_tbl <- c(or_tbl, rep("Admin", nrow(miss_adm)))
    or_plot <- c(or_plot, as.character(miss_adm[["PlotNumber"]]))
    or_issue <- c(or_issue, rep("missing_admin", nrow(miss_adm)))
    or_n <- c(or_n, rep(1L, nrow(miss_adm)))
  }

  orph_adm <- DBI::dbGetQuery(
    dbc,
    paste0(
      'SELECT COALESCE(CAST(a."Plot" AS TEXT), \'<NULL>\') AS "PlotNumber", COUNT(*) AS "n" FROM ', adm_q, ' AS a ',
      'WHERE a."Plot" IS NULL OR typeof(a."Plot") <> \'text\' OR NOT EXISTS (SELECT 1 FROM ', env_q, ' AS e WHERE typeof(e."PlotNumber") = \'text\' AND CAST(e."PlotNumber" AS BLOB) = CAST(a."Plot" AS BLOB)) GROUP BY 1 ORDER BY 1'
    )
  )
  if (nrow(orph_adm) > 0L) {
    or_tbl <- c(or_tbl, rep("Admin", nrow(orph_adm)))
    or_plot <- c(or_plot, as.character(orph_adm[["PlotNumber"]]))
    or_issue <- c(or_issue, rep("orphan_admin", nrow(orph_adm)))
    or_n <- c(or_n, as.integer(orph_adm[["n"]]))
  }

  for (sfx in c("Veg", "Humus", "Mineral", "Other")) {
    ctbl <- paste0(con$project, "_", sfx)
    if (!DBI::dbExistsTable(dbc, ctbl)) next
    cq <- vpro_quote_ident(ctbl)
    ores <- DBI::dbGetQuery(
      dbc,
      paste0(
        'SELECT COALESCE(CAST(c."PlotNumber" AS TEXT), \'<NULL>\') AS "PlotNumber", COUNT(*) AS "n" FROM ', cq, ' AS c ',
        'WHERE c."PlotNumber" IS NULL OR typeof(c."PlotNumber") <> \'text\' OR NOT EXISTS (SELECT 1 FROM ', env_q, ' AS e WHERE typeof(e."PlotNumber") = \'text\' AND CAST(e."PlotNumber" AS BLOB) = CAST(c."PlotNumber" AS BLOB)) GROUP BY 1 ORDER BY 1'
      )
    )
    if (nrow(ores) > 0L) {
      or_tbl <- c(or_tbl, rep(sfx, nrow(ores)))
      or_plot <- c(or_plot, as.character(ores[["PlotNumber"]]))
      or_issue <- c(or_issue, rep("orphan_child", nrow(ores)))
      or_n <- c(or_n, as.integer(ores[["n"]]))
    }
  }

  all_env_plots <- DBI::dbGetQuery(
    dbc,
    paste0('SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber" FROM ', env_q, ' WHERE typeof("PlotNumber") = \'text\' ORDER BY 1')
  )[["PlotNumber"]]

  if (!is.null(con$su) && nrow(su_df) > 0L) {
    su_orph <- setdiff(su_plots, all_env_plots)
    if (length(su_orph) > 0L) {
      for (sp in sort(su_orph)) {
        cnt <- sum(su_df[["PlotNumber"]] == sp)
        or_tbl <- c(or_tbl, "SU")
        or_plot <- c(or_plot, sp)
        or_issue <- c(or_issue, "orphan_su")
        or_n <- c(or_n, as.integer(cnt))
      }
    }
  }

  plots_with_veg <- DBI::dbGetQuery(
    dbc,
    paste0('SELECT DISTINCT CAST("PlotNumber" AS TEXT) AS "PlotNumber" FROM ', veg_q, ' WHERE typeof("PlotNumber") = \'text\'')
  )[["PlotNumber"]]
  target_env_plots <- if (use_su) intersect(all_env_plots, su_plots) else all_env_plots
  no_veg_plots <- sort(setdiff(target_env_plots, plots_with_veg))
  if (length(no_veg_plots) > 0L) {
    or_tbl <- c(or_tbl, rep("Veg", length(no_veg_plots)))
    or_plot <- c(or_plot, as.character(no_veg_plots))
    or_issue <- c(or_issue, rep("plot_without_veg", length(no_veg_plots)))
    or_n <- c(or_n, rep(0L, length(no_veg_plots)))
  }

  orphans_tbl <- tibble::tibble(
    table = or_tbl,
    PlotNumber = or_plot,
    issue = or_issue,
    n_rows = or_n
  )

  # 4. Duplicate physical (PlotNumber, Species) / same-layer cover check (Check4DuplicatedSpecies)
  veg_flds <- DBI::dbListFields(dbc, veg_tbl)
  layer_map <- c(
    "1" = "Cover1", "2" = "Cover2", "3" = "Cover3", "A" = "TotalA",
    "4" = "Cover4", "5" = "Cover5", "5a" = "Cover5a", "5b" = "Cover5b", "5c" = "Cover5c", "B" = "TotalB",
    "6" = "Cover6", "7" = "Cover7", "8" = "Cover8", "9" = "Cover9", "10" = "Cover10"
  )
  present_lc <- layer_map[layer_map %in% veg_flds]
  flag_exprs <- vapply(names(present_lc), function(lcode) {
    paste0('CASE WHEN ', vpro_quote_ident(present_lc[[lcode]]), ' IS NOT NULL THEN 1 ELSE 0 END AS ', vpro_quote_ident(paste0("f_", lcode)))
  }, character(1))
  lyr_col_sql <- if ("Layer" %in% veg_flds) 'COALESCE(TRIM(CAST("Layer" AS TEXT)), \'\') AS "__lyr__", ' else '\'\' AS "__lyr__", '

  dup_sql_cols <- paste0(
    'CAST("PlotNumber" AS TEXT) AS "PlotNumber", CAST("Species" AS TEXT) AS "Species", ',
    lyr_col_sql,
    paste(flag_exprs, collapse = ", ")
  )
  dup_raw <- vpro_query_scoped_plots(
    dbc, veg_q, veg_scope_plots,
    select_cols = dup_sql_cols,
    where_extra = '"Species" IS NOT NULL AND TRIM(CAST("Species" AS TEXT)) <> \'\''
  )

  duplicates_tbl <- if (nrow(dup_raw) == 0L) {
    tibble::tibble(
      PlotNumber = character(),
      Species = character(),
      overlapping_layers = character(),
      n_rows = integer(),
      same_layer_conflict = logical()
    )
  } else {
    grp_key <- paste0(dup_raw[["PlotNumber"]], "\t", toupper(trimws(as.character(dup_raw[["Species"]]))))
    f_cols <- paste0("f_", names(present_lc))
    f_mat <- as.matrix(dup_raw[, f_cols, drop = FALSE])
    storage.mode(f_mat) <- "integer"
    row_counts <- tabulate(match(grp_key, unique(grp_key)))
    uniq_keys <- unique(grp_key)
    dup_mask <- row_counts > 1L
    if (!any(dup_mask)) {
      tibble::tibble(
        PlotNumber = character(),
        Species = character(),
        overlapping_layers = character(),
        n_rows = integer(),
        same_layer_conflict = logical()
      )
    } else {
      target_keys <- uniq_keys[dup_mask]
      idx_list <- split(seq_len(nrow(dup_raw)), grp_key)[target_keys]
      l_names <- names(present_lc)
      d_plot <- character(length(target_keys))
      d_spp <- character(length(target_keys))
      d_ov <- character(length(target_keys))
      d_n <- integer(length(target_keys))
      d_conf <- logical(length(target_keys))
      for (ki in seq_along(target_keys)) {
        r_ix <- idx_list[[ki]]
        d_plot[[ki]] <- as.character(dup_raw[["PlotNumber"]][[r_ix[[1L]]]])
        d_spp[[ki]] <- as.character(dup_raw[["Species"]][[r_ix[[1L]]]])
        d_n[[ki]] <- length(r_ix)
        cs <- colSums(f_mat[r_ix, , drop = FALSE])
        hits <- l_names[cs > 1L]
        lyrs <- dup_raw[["__lyr__"]][r_ix]
        dup_lcol <- any(duplicated(lyrs[nzchar(lyrs)]))
        d_conf[[ki]] <- length(hits) > 0L || dup_lcol
        d_ov[[ki]] <- paste(hits, collapse = ",")
      }
      ord_d <- order(d_plot, d_spp)
      tibble::tibble(
        PlotNumber = d_plot[ord_d],
        Species = d_spp[ord_d],
        overlapping_layers = d_ov[ord_d],
        n_rows = d_n[ord_d],
        same_layer_conflict = d_conf[ord_d]
      )
    }
  }

  # 5. LMH25 pedological & edatopic validation
  lmh25_res <- vpro_check_lmh25(con, scope = scope)

  # Build unified $issues tibble
  parts <- list()
  if (nrow(env_codes_tbl) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = env_codes_tbl[["PlotNumber"]],
      category = rep("env_codes", nrow(env_codes_tbl)),
      rule = paste0("list:", env_codes_tbl[["list_name"]]),
      severity = rep("error", nrow(env_codes_tbl)),
      detail = sprintf("Field %s has unlisted value '%s' (list %s).", env_codes_tbl[["field"]], env_codes_tbl[["value"]], env_codes_tbl[["list_name"]])
    )
  }
  if (nrow(veg_codes_tbl) > 0L) {
    is_unl <- veg_codes_tbl[["status"]] == "unlisted"
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = veg_codes_tbl[["PlotNumber"]],
      category = rep("veg_codes", nrow(veg_codes_tbl)),
      rule = paste0("species_", veg_codes_tbl[["status"]]),
      severity = ifelse(is_unl, "error", "warning"),
      detail = ifelse(
        is_unl,
        sprintf("Species code '%s' is not in USysAllSpecs or USysUserSpp.", veg_codes_tbl[["Species"]]),
        sprintf("Species code '%s' is a synonym; accepted code is '%s'.", veg_codes_tbl[["Species"]], veg_codes_tbl[["suggested_code"]])
      )
    )
  }
  if (nrow(orphans_tbl) > 0L) {
    is_noveg <- orphans_tbl[["issue"]] == "plot_without_veg"
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = orphans_tbl[["PlotNumber"]],
      category = rep("orphans", nrow(orphans_tbl)),
      rule = orphans_tbl[["issue"]],
      severity = ifelse(is_noveg, "warning", "error"),
      detail = ifelse(
        is_noveg,
        sprintf("Plot %s has no vegetation rows in %s_Veg.", orphans_tbl[["PlotNumber"]], con$project),
        sprintf("Table %s has %s (%d row(s)) for PlotNumber %s.", orphans_tbl[["table"]], orphans_tbl[["issue"]], orphans_tbl[["n_rows"]], orphans_tbl[["PlotNumber"]])
      )
    )
  }
  if (nrow(duplicates_tbl) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = duplicates_tbl[["PlotNumber"]],
      category = rep("duplicates", nrow(duplicates_tbl)),
      rule = ifelse(duplicates_tbl[["same_layer_conflict"]], "duplicate_species_layer", "duplicate_species_rows"),
      severity = ifelse(duplicates_tbl[["same_layer_conflict"]], "error", "warning"),
      detail = ifelse(
        duplicates_tbl[["same_layer_conflict"]],
        sprintf("Species '%s' appears %d times with overlapping cover in layer(s): %s.", duplicates_tbl[["Species"]], duplicates_tbl[["n_rows"]], duplicates_tbl[["overlapping_layers"]]),
        sprintf("Species '%s' is split across %d physical rows without overlapping cover.", duplicates_tbl[["Species"]], duplicates_tbl[["n_rows"]])
      )
    )
  }
  if (nrow(lmh25_res$issues) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = lmh25_res$issues[["PlotNumber"]],
      category = rep("lmh25", nrow(lmh25_res$issues)),
      rule = lmh25_res$issues[["rule"]],
      severity = lmh25_res$issues[["severity"]],
      detail = lmh25_res$issues[["detail"]]
    )
  }

  issues_all <- if (length(parts) == 0L) {
    tibble::tibble(
      PlotNumber = character(),
      category = character(),
      rule = character(),
      severity = character(),
      detail = character()
    )
  } else {
    do.call(rbind, parts)
  }

  passed <- !any(issues_all[["severity"]] == "error")

  structure(
    list(
      passed = passed,
      issues = issues_all,
      env_codes = env_codes_tbl,
      veg_codes = veg_codes_tbl,
      orphans = orphans_tbl,
      duplicates = duplicates_tbl,
      lmh25 = lmh25_res,
      skipped_definitions = skipped_tbl
    ),
    class = "vpro_validation"
  )
}

#' Print a `vpro_validation` workspace QA summary
#'
#' @param x A `vpro_validation` object from [vpro_validate()].
#' @param ... Unused additional arguments.
#' @return `x`, invisibly.
#' @export
print.vpro_validation <- function(x, ...) {
  n_err <- sum(x$issues[["severity"]] == "error")
  n_wrn <- sum(x$issues[["severity"]] == "warning")
  b1 <- sprintf("Total issues: %d (%d errors, %d warnings)", nrow(x$issues), n_err, n_wrn)
  b2 <- sprintf("Env picklist errors: %d | Veg code findings: %d", nrow(x$env_codes), nrow(x$veg_codes))
  b3 <- sprintf("Orphans/no-veg: %d | Duplicate species: %d | LMH25: %d", nrow(x$orphans), nrow(x$duplicates), nrow(x$lmh25$issues))
  cli::cli_h3(sprintf("vpro_validation (%s)", if (x$passed) "PASSED" else "FAILED"))
  cli::cli_bullets(c("*" = b1, "*" = b2, "*" = b3))
  invisible(x)
}

#' Coerce a `vpro_validation` bundle to its unified issues tibble
#'
#' @param x A `vpro_validation` object from [vpro_validate()].
#' @param ... Unused additional arguments.
#' @return The `$issues` tibble (`PlotNumber`, `category`, `rule`, `severity`,
#'   `detail`).
#' @export
as_tibble.vpro_validation <- function(x, ...) {
  x$issues
}
