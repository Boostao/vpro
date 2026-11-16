# LMH25 (2023) Pedological Rules & Workspace Standards QA ----------------------

vpro_classify_humus_lmh25 <- function(horizon, soil_group = "") {
  u <- toupper(trimws(ifelse(is.na(horizon), "", as.character(horizon))))
  sg <- toupper(trimws(ifelse(is.na(soil_group), "", as.character(soil_group))))
  if (!nzchar(u) || identical(u, "S")) {
    return("surface_or_blank")
  }
  if (grepl("^(OF|OM|OH|LIMNO|CUMULO|HYDRIC)", u) || startsWith(u, "O") || grepl("^[0-9]+O[FMHP]?", u)) {
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
  if (u %in% c("L", "VL", "YL")) {
    return("MULL")
  }
  if (u %in% c("D", "LD", "MD", "RD", "SD", "TD", "YD")) {
    return("MODER")
  }
  if (u %in% c("R", "FR", "HR", "LR", "MR", "RR", "UR", "YR")) {
    return("MOR")
  }
  ""
}

vpro_infer_lmh25_keys <- function(
  env_row,
  has_peaty,
  peat_tot,
  peat_u40,
  peat_of_u40,
  peat_om_u40,
  upland_tot,
  upland_h,
  ah_depth,
  ae_depth,
  b_dark,
  b_light,
  has_gley,
  min_gley_depth,
  lithic_depth,
  max_min_lower,
  weighted_cf,
  cf_weight,
  dom_tex,
  has_turbation,
  has_saline
) {
  get_chr <- function(col) {
    if (!(col %in% names(env_row))) {
      return("")
    }
    v <- env_row[[col]][[1L]]
    if (is.na(v)) "" else trimws(as.character(v))
  }
  get_num <- function(col) {
    if (!(col %in% names(env_row))) {
      return(NA_real_)
    }
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
  has_site_evidence <- nzchar(meso) || nzchar(drainage) || nzchar(rzps) || nzchar(dom_tex) || has_peaty || is_org_order || cf_weight > 0
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
  is_coarse <- is_fragmental || rzps %in% c("S", "SS", "CI", "CLS", "AS") || (is_sandy && (cf_weight == 0 || avg_cf > 35.0)) || (is_loamy && avg_cf > 70.0) || avg_cf > 70.0
  is_fine <- !is_coarse && (rzps %in% c("C", "FC", "CSI", "FSI") || ((is_silty || is_clayey) && (cf_weight == 0 || avg_cf <= 20.0)))

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

  water_at_surface <- drainage %in% c("v", "aq", "pa", "6") || (!is.na(seepage) && seepage == 0) || (!is.na(sub_water) && sub_water >= 25.0)
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
      if (wsi_depth < 30) {
        smr_class <- 6L
        smr_label <- "6"
      } else {
        smr_class <- 5L
        smr_label <- "(4)-5"
      }
    } else if (has_exp_depth && soil_depth < 40) {
      if (bedrock_pct > 10 || soil_depth < 20) {
        smr_class <- 0L
        smr_label <- "0(-1)"
      } else {
        smr_class <- 1L
        smr_label <- "1"
      }
    } else if (is_coarse) {
      if (insolation) {
        smr_class <- 1L
        smr_label <- "1(-2)"
      } else if (cold_slope) {
        smr_class <- 3L
        smr_label <- "2-3"
      } else {
        smr_class <- 2L
        smr_label <- "(1-)2"
      }
    } else {
      if (insolation) {
        smr_class <- 2L
        smr_label <- "2(-3)"
      } else if (cold_slope) {
        smr_class <- 4L
        smr_label <- "3-4"
      } else {
        smr_class <- 3L
        smr_label <- "(2-)3"
      }
    }
  } else if (slope_group == "MID") {
    if (wsi) {
      if (wsi_depth < 30) {
        smr_class <- 6L
        smr_label <- "6"
      } else {
        smr_class <- 5L
        smr_label <- "(4-)5"
      }
    } else {
      shallow <- has_exp_depth && soil_depth < 50
      if (is_coarse) {
        if (shallow && insolation) {
          smr_class <- 1L
          smr_label <- "1-(2)"
        } else if (shallow || insolation) {
          smr_class <- 2L
          smr_label <- "2"
        } else {
          smr_class <- 3L
          smr_label <- "3"
        }
      } else {
        if (shallow && insolation) {
          smr_class <- 2L
          smr_label <- "2"
        } else if (shallow || insolation) {
          smr_class <- if (cold_slope) 4L else 3L
          smr_label <- if (cold_slope) "3-4" else "3"
        } else {
          smr_class <- 4L
          smr_label <- "4"
        }
      }
    }
  } else if (slope_group == "LOWER") {
    if (wsi) {
      if (wsi_depth < 30) {
        if (water_at_surface) {
          smr_class <- 8L
          smr_label <- "8"
        } else {
          smr_class <- 7L
          smr_label <- "7"
        }
      } else {
        smr_class <- 6L
        smr_label <- "6"
      }
    } else if (is_coarse) {
      smr_class <- 4L
      smr_label <- "4(-5)"
    } else {
      smr_class <- 5L
      smr_label <- "5(-6)"
    }
  } else {
    if ((wsi && wsi_depth < 60) || active_fluvial) {
      if (wsi && wsi_depth < 30) {
        if (water_at_surface) {
          smr_class <- 8L
          smr_label <- "8"
        } else {
          smr_class <- 7L
          smr_label <- "7"
        }
      } else if (is_fine) {
        smr_class <- 6L
        smr_label <- "6"
      } else {
        smr_class <- 5L
        smr_label <- "5"
      }
    } else if (is_coarse) {
      smr_class <- 2L
      smr_label <- "2-3"
    } else if (is_fine) {
      smr_class <- 5L
      smr_label <- "5"
    } else {
      smr_class <- 4L
      smr_label <- "4"
    }
  }

  # Key 9.6 / 9.7 rSNR (0..5 -> A..F)
  restricted_flow <- slope < 5.0 && (drainage %in% c("p", "v", "aq", "pa", "5", "6") || is_fine)
  humus_cls <- vpro_humus_form_family(humus_form)
  is_saline <- water_src == "E" || rr_type == "X" || has_saline

  snr_class <- 2L
  snr_label <- "C"
  if (is_saline) {
    snr_class <- 5L
    snr_label <- "F"
  } else if (wsi || active_fluvial) {
    if (peat_tot > 20 || (is_org_order && soil_group != "FO")) {
      of_dom <- (peat_u40 > 0 && peat_of_u40 / peat_u40 >= 0.5) || soil_group == "F"
      of_om_dom <- (peat_u40 > 0 && (peat_of_u40 + peat_om_u40) / peat_u40 >= 0.5) || soil_group == "M"
      if (of_dom) {
        snr_class <- 0L
        snr_label <- "A-B"
      } else if (of_om_dom) {
        snr_class <- 1L
        snr_label <- "B-C"
      } else if (restricted_flow) {
        snr_class <- 2L
        snr_label <- "C-D"
      } else {
        snr_class <- 3L
        snr_label <- "D-E"
      }
    } else if (wsi && wsi_depth < 30) {
      if (restricted_flow) {
        if (ah_depth > 5 || humus_cls == "MULL") {
          snr_class <- 2L
          snr_label <- "C"
        } else {
          snr_class <- 1L
          snr_label <- "B"
        }
      } else {
        if (ah_depth > 5 || active_fluvial || humus_cls == "MULL") {
          snr_class <- 3L
          snr_label <- "D"
        } else {
          snr_class <- 2L
          snr_label <- "C"
        }
      }
    } else {
      if (restricted_flow) {
        if (ah_depth > 5 || humus_cls == "MULL") {
          snr_class <- 3L
          snr_label <- "D"
        } else {
          snr_class <- 2L
          snr_label <- "C"
        }
      } else {
        if (ah_depth > 5 || active_fluvial || humus_cls == "MULL") {
          snr_class <- 4L
          snr_label <- "E"
        } else {
          snr_class <- 3L
          snr_label <- "D"
        }
      }
    }
  } else if ((has_exp_depth && soil_depth < 30) || is_fragmental || soil_group == "FO") {
    if (soil_group == "FO") {
      if ((upland_tot + soil_depth) < 30) {
        snr_class <- 0L
        snr_label <- "A"
      } else if (upland_tot > 0 && upland_h / upland_tot >= 0.5) {
        snr_class <- 2L
        snr_label <- "C"
      } else {
        snr_class <- 1L
        snr_label <- "B"
      }
    } else if (ah_depth > 5 || b_dark || humus_cls == "MULL") {
      snr_class <- 2L
      snr_label <- "C"
    } else if (b_light || ae_depth > 2 || (has_exp_depth && soil_depth < 10) || (humus_cls == "MOR" && is_coarse)) {
      snr_class <- 0L
      snr_label <- "A"
    } else {
      snr_class <- 1L
      snr_label <- "B"
    }
  } else if (is_coarse || (has_exp_depth && soil_depth < 50)) {
    if (ah_depth > 2 || b_dark || humus_cls == "MULL") {
      if (has_turbation || humus_cls == "MULL") {
        snr_class <- 3L
        snr_label <- "D"
      } else {
        snr_class <- 2L
        snr_label <- "C"
      }
    } else if (b_light || ae_depth > 2) {
      snr_class <- 0L
      snr_label <- "A"
    } else if (humus_cls == "MODER") {
      snr_class <- 2L
      snr_label <- "C"
    } else {
      snr_class <- 1L
      snr_label <- "B"
    }
  } else {
    if (ah_depth > 2 || b_dark || humus_cls == "MULL") {
      if (is_fine && ah_depth > 5) {
        snr_class <- 4L
        snr_label <- "E"
      } else {
        snr_class <- 3L
        snr_label <- "D"
      }
    } else if (b_light || ae_depth > 2 || (humus_cls == "MOR" && cold_slope && upland_tot > 10)) {
      snr_class <- 1L
      snr_label <- "B"
    } else if (humus_cls == "MODER" && slope_group == "LOWER") {
      snr_class <- 3L
      snr_label <- "D"
    } else {
      snr_class <- 2L
      snr_label <- "C"
    }
  }

  active_layer <- get_num("ActiveLayerDepth")
  if (
    (water_src == "Z" || rr_type == "Z" || (!is.na(active_layer) && active_layer > 0)) &&
      snr_class > 0L &&
      snr_class < 5L
  ) {
    snr_class <- snr_class - 1L
    snr_label <- LETTERS[[snr_class + 1L]]
  }

  list(smr_class = smr_class, smr_label = smr_label, snr_class = snr_class, snr_label = snr_label)
}
