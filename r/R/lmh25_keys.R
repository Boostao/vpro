# LMH25 (2023) Pedological Rules & Workspace Standards QA ----------------------

vpro_classify_humus_lmh25 <- function(horizon, soil_group = "") {
  u <- vpro_strip_soil_discontinuity(horizon)
  reg <- vpro_lmh25_horizon_regime(horizon, kind = "Humus")
  out <- rep("other", length(u))
  out[reg == "wetland"] <- "wetland"
  out[reg == "upland"] <- "upland"
  out[!nzchar(u) | u == "S"] <- "surface_or_blank"
  out
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

.vpro_infer_lmh25_soil_group <- function(
  env_row,
  has_peaty,
  lithic_depth,
  max_min_lower,
  weighted_cf,
  cf_weight,
  dom_tex
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

  has_site_evidence <- any(c(nzchar(meso), nzchar(drainage), nzchar(rzps), nzchar(dom_tex), has_peaty, is_org_order, cf_weight > 0))
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
  is_sandy <- dom_tex %in% c("S", "LS") | rzps %in% c("S", "SS")
  is_loamy <- dom_tex %in% c("SL", "L", "SCL") | rzps %in% c("CL", "L", "FL")
  is_silty <- dom_tex %in% c("SIL", "SI") | rzps %in% c("CSI", "FSI")
  is_clayey <- dom_tex %in% c("SICL", "CL", "SC", "SIC", "C") | rzps %in% c("C", "FC")

  is_fragmental <- rzps == "F" || avg_cf > 85.0
  sandy_coarse <- is_sandy && (cf_weight == 0 || avg_cf > 35.0)
  loamy_coarse <- is_loamy && avg_cf > 70.0
  is_coarse <- any(c(is_fragmental, rzps %in% c("S", "SS", "CI", "CLS", "AS"), sandy_coarse, loamy_coarse, avg_cf > 70.0))
  fine_tex <- (is_silty || is_clayey) && (cf_weight == 0 || avg_cf <= 20.0)
  is_fine <- !is_coarse && (rzps %in% c("C", "FC", "CSI", "FSI") || fine_tex)

  sub_bedrock <- get_num("SubstrateBedRock")
  list(
    has_site_evidence = has_site_evidence,
    soil_group = soil_group,
    is_org_order = is_org_order,
    meso = meso,
    drainage = drainage,
    water_src = water_src,
    rr_type = rr_type,
    humus_form = humus_form,
    flood_freq = flood_freq,
    surf_mat = surf_mat,
    has_slope = has_slope,
    slope = slope,
    insolation = insolation,
    cold_slope = cold_slope,
    soil_depth = soil_depth,
    has_exp_depth = has_exp_depth,
    is_fragmental = is_fragmental,
    is_coarse = is_coarse,
    is_fine = is_fine,
    seepage = get_num("SeepageDepth"),
    sub_water = get_num("SubstrateWater"),
    bedrock_pct = if (!is.na(sub_bedrock)) sub_bedrock else 0.0,
    active_layer = get_num("ActiveLayerDepth")
  )
}

.vpro_infer_lmh25_humus_form <- function(
  site,
  has_peaty,
  peat_tot,
  peat_u40,
  peat_of_u40,
  peat_om_u40,
  has_gley,
  min_gley_depth,
  has_saline
) {
  wsi <- FALSE
  wsi_depth <- 999.0
  if (!is.na(site$seepage) && site$seepage >= 0) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, site$seepage)
  }
  if (has_gley) {
    wsi <- TRUE
    if (min_gley_depth >= 0) wsi_depth <- min(wsi_depth, min_gley_depth)
  }
  if (has_peaty || (site$is_org_order && site$soil_group != "FO")) {
    wsi <- TRUE
    if (peat_tot >= 20 && wsi_depth > 15) wsi_depth <- 10.0
  }
  if (site$drainage %in% c("v", "aq", "pa", "6")) {
    wsi <- TRUE
    wsi_depth <- 0.0
  } else if (site$drainage %in% c("p", "ac", "5")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 20.0)
  } else if (site$drainage %in% c("i", "sa")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 45.0)
  }
  if (site$water_src %in% c("G", "S", "M", "T", "E")) {
    wsi <- TRUE
    wsi_depth <- min(wsi_depth, 45.0)
  }

  water_at_surface <- any(c(
    site$drainage %in% c("v", "aq", "pa", "6"),
    !is.na(site$seepage) && site$seepage == 0,
    !is.na(site$sub_water) && site$sub_water >= 25.0
  ))
  active_fluvial <- any(c(site$water_src == "F", site$flood_freq %in% c("A", "F"), startsWith(site$surf_mat, "FA")))

  slope_group <- if (site$meso %in% c("CR", "UP")) {
    "UPPER"
  } else if (site$meso == "MD") {
    "MID"
  } else if (site$meso %in% c("LW", "TO", "GU")) {
    "LOWER"
  } else if (site$meso %in% c("LV", "DP") || (site$has_slope && site$slope < 5.0)) {
    "FLAT"
  } else {
    "MID"
  }

  restricted_flow <- site$slope < 5.0 && (site$drainage %in% c("p", "v", "aq", "pa", "5", "6") || site$is_fine)
  humus_cls <- vpro_humus_form_family(site$humus_form)
  is_saline <- any(c(site$water_src == "E", site$rr_type == "X", has_saline))
  of_dom <- (peat_u40 > 0 && peat_of_u40 / peat_u40 >= 0.5) || site$soil_group == "F"
  of_om_dom <- (peat_u40 > 0 && (peat_of_u40 + peat_om_u40) / peat_u40 >= 0.5) || site$soil_group == "M"

  list(
    wsi = wsi,
    wsi_depth = wsi_depth,
    water_at_surface = water_at_surface,
    active_fluvial = active_fluvial,
    slope_group = slope_group,
    restricted_flow = restricted_flow,
    humus_cls = humus_cls,
    is_saline = is_saline,
    of_dom = of_dom,
    of_om_dom = of_om_dom
  )
}

.vpro_infer_lmh25_smr <- function(site, regime) {
  wsi <- regime$wsi
  wsi_depth <- regime$wsi_depth
  water_at_surface <- regime$water_at_surface
  active_fluvial <- regime$active_fluvial
  slope_group <- regime$slope_group

  if (slope_group == "UPPER") {
    if (wsi) {
      if (wsi_depth < 30) {
        return(list(smr_class = 6L, smr_label = "6"))
      }
      return(list(smr_class = 5L, smr_label = "(4)-5"))
    }
    if (site$has_exp_depth && site$soil_depth < 40) {
      if (site$bedrock_pct > 10 || site$soil_depth < 20) {
        return(list(smr_class = 0L, smr_label = "0(-1)"))
      }
      return(list(smr_class = 1L, smr_label = "1"))
    }
    if (site$is_coarse) {
      if (site$insolation) return(list(smr_class = 1L, smr_label = "1(-2)"))
      if (site$cold_slope) return(list(smr_class = 3L, smr_label = "2-3"))
      return(list(smr_class = 2L, smr_label = "(1-)2"))
    }
    if (site$insolation) return(list(smr_class = 2L, smr_label = "2(-3)"))
    if (site$cold_slope) return(list(smr_class = 4L, smr_label = "3-4"))
    return(list(smr_class = 3L, smr_label = "(2-)3"))
  }

  if (slope_group == "MID") {
    if (wsi) {
      if (wsi_depth < 30) return(list(smr_class = 6L, smr_label = "6"))
      return(list(smr_class = 5L, smr_label = "(4-)5"))
    }
    shallow <- site$has_exp_depth && site$soil_depth < 50
    if (site$is_coarse) {
      if (shallow && site$insolation) return(list(smr_class = 1L, smr_label = "1-(2)"))
      if (shallow || site$insolation) return(list(smr_class = 2L, smr_label = "2"))
      return(list(smr_class = 3L, smr_label = "3"))
    }
    if (shallow && site$insolation) return(list(smr_class = 2L, smr_label = "2"))
    if (shallow || site$insolation) {
      if (site$cold_slope) return(list(smr_class = 4L, smr_label = "3-4"))
      return(list(smr_class = 3L, smr_label = "3"))
    }
    return(list(smr_class = 4L, smr_label = "4"))
  }

  if (slope_group == "LOWER") {
    if (wsi) {
      if (wsi_depth < 30) {
        if (water_at_surface) return(list(smr_class = 8L, smr_label = "8"))
        return(list(smr_class = 7L, smr_label = "7"))
      }
      return(list(smr_class = 6L, smr_label = "6"))
    }
    if (site$is_coarse) return(list(smr_class = 4L, smr_label = "4(-5)"))
    return(list(smr_class = 5L, smr_label = "5(-6)"))
  }

  if ((wsi && wsi_depth < 60) || active_fluvial) {
    if (wsi && wsi_depth < 30) {
      if (water_at_surface) return(list(smr_class = 8L, smr_label = "8"))
      return(list(smr_class = 7L, smr_label = "7"))
    }
    if (site$is_fine) return(list(smr_class = 6L, smr_label = "6"))
    return(list(smr_class = 5L, smr_label = "5"))
  }
  if (site$is_coarse) return(list(smr_class = 2L, smr_label = "2-3"))
  if (site$is_fine) return(list(smr_class = 5L, smr_label = "5"))
  list(smr_class = 4L, smr_label = "4")
}

.vpro_infer_lmh25_snr_wet <- function(site, regime, peat_tot, ah_depth) {
  if (peat_tot > 20 || (site$is_org_order && site$soil_group != "FO")) {
    if (regime$of_dom) return(list(snr_class = 0L, snr_label = "A-B"))
    if (regime$of_om_dom) return(list(snr_class = 1L, snr_label = "B-C"))
    if (regime$restricted_flow) return(list(snr_class = 2L, snr_label = "C-D"))
    return(list(snr_class = 3L, snr_label = "D-E"))
  }
  rich_a <- ah_depth > 5 || regime$humus_cls == "MULL"
  rich_fluv <- rich_a || regime$active_fluvial
  if (regime$wsi && regime$wsi_depth < 30) {
    if (regime$restricted_flow) {
      if (rich_a) return(list(snr_class = 2L, snr_label = "C"))
      return(list(snr_class = 1L, snr_label = "B"))
    }
    if (rich_fluv) return(list(snr_class = 3L, snr_label = "D"))
    return(list(snr_class = 2L, snr_label = "C"))
  }
  if (regime$restricted_flow) {
    if (rich_a) return(list(snr_class = 3L, snr_label = "D"))
    return(list(snr_class = 2L, snr_label = "C"))
  }
  if (rich_fluv) return(list(snr_class = 4L, snr_label = "E"))
  list(snr_class = 3L, snr_label = "D")
}

.vpro_infer_lmh25_snr_upland <- function(
  site,
  regime,
  upland_tot,
  upland_h,
  ah_depth,
  ae_depth,
  b_dark,
  b_light,
  has_turbation
) {
  humus_cls <- regime$humus_cls
  shallow_30 <- site$has_exp_depth && site$soil_depth < 30
  if (any(c(shallow_30, site$is_fragmental, site$soil_group == "FO"))) {
    if (site$soil_group == "FO") {
      if ((upland_tot + site$soil_depth) < 30) return(list(snr_class = 0L, snr_label = "A"))
      if (upland_tot > 0 && upland_h / upland_tot >= 0.5) return(list(snr_class = 2L, snr_label = "C"))
      return(list(snr_class = 1L, snr_label = "B"))
    }
    if (any(c(ah_depth > 5, b_dark, humus_cls == "MULL"))) return(list(snr_class = 2L, snr_label = "C"))
    very_poor <- any(c(b_light, ae_depth > 2, site$has_exp_depth && site$soil_depth < 10, humus_cls == "MOR" && site$is_coarse))
    if (very_poor) return(list(snr_class = 0L, snr_label = "A"))
    return(list(snr_class = 1L, snr_label = "B"))
  }

  rich_top <- any(c(ah_depth > 2, b_dark, humus_cls == "MULL"))
  leached <- b_light || ae_depth > 2
  if (site$is_coarse || (site$has_exp_depth && site$soil_depth < 50)) {
    if (rich_top) {
      if (has_turbation || humus_cls == "MULL") return(list(snr_class = 3L, snr_label = "D"))
      return(list(snr_class = 2L, snr_label = "C"))
    }
    if (leached) return(list(snr_class = 0L, snr_label = "A"))
    if (humus_cls == "MODER") return(list(snr_class = 2L, snr_label = "C"))
    return(list(snr_class = 1L, snr_label = "B"))
  }

  if (rich_top) {
    if (site$is_fine && ah_depth > 5) return(list(snr_class = 4L, snr_label = "E"))
    return(list(snr_class = 3L, snr_label = "D"))
  }
  cold_mor <- humus_cls == "MOR" && site$cold_slope && upland_tot > 10
  if (leached || cold_mor) return(list(snr_class = 1L, snr_label = "B"))
  if (humus_cls == "MODER" && regime$slope_group == "LOWER") return(list(snr_class = 3L, snr_label = "D"))
  list(snr_class = 2L, snr_label = "C")
}

.vpro_infer_lmh25_snr <- function(
  site,
  regime,
  peat_tot,
  upland_tot,
  upland_h,
  ah_depth,
  ae_depth,
  b_dark,
  b_light,
  has_turbation
) {
  res <- if (regime$is_saline) {
    list(snr_class = 5L, snr_label = "F")
  } else if (regime$wsi || regime$active_fluvial) {
    .vpro_infer_lmh25_snr_wet(site, regime, peat_tot, ah_depth)
  } else {
    .vpro_infer_lmh25_snr_upland(site, regime, upland_tot, upland_h, ah_depth, ae_depth, b_dark, b_light, has_turbation)
  }

  has_permafrost <- any(c(site$water_src == "Z", site$rr_type == "Z", !is.na(site$active_layer) && site$active_layer > 0))
  if (has_permafrost && res$snr_class > 0L && res$snr_class < 5L) {
    res$snr_class <- res$snr_class - 1L
    res$snr_label <- LETTERS[[res$snr_class + 1L]]
  }
  res
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
  site <- .vpro_infer_lmh25_soil_group(
    env_row = env_row,
    has_peaty = has_peaty,
    lithic_depth = lithic_depth,
    max_min_lower = max_min_lower,
    weighted_cf = weighted_cf,
    cf_weight = cf_weight,
    dom_tex = dom_tex
  )
  if (!site$has_site_evidence) {
    return(list(
      smr_class = NA_integer_,
      smr_label = NA_character_,
      snr_class = NA_integer_,
      snr_label = NA_character_
    ))
  }

  regime <- .vpro_infer_lmh25_humus_form(
    site = site,
    has_peaty = has_peaty,
    peat_tot = peat_tot,
    peat_u40 = peat_u40,
    peat_of_u40 = peat_of_u40,
    peat_om_u40 = peat_om_u40,
    has_gley = has_gley,
    min_gley_depth = min_gley_depth,
    has_saline = has_saline
  )
  smr <- .vpro_infer_lmh25_smr(site, regime)
  snr <- .vpro_infer_lmh25_snr(
    site = site,
    regime = regime,
    peat_tot = peat_tot,
    upland_tot = upland_tot,
    upland_h = upland_h,
    ah_depth = ah_depth,
    ae_depth = ae_depth,
    b_dark = b_dark,
    b_light = b_light,
    has_turbation = has_turbation
  )

  list(
    smr_class = smr$smr_class,
    smr_label = smr$smr_label,
    snr_class = snr$snr_class,
    snr_label = snr$snr_label
  )
}
