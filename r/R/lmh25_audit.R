# LMH25 (2023) Pedological Audit & VP08 Bounds Checking ----------------------

.vpro_lmh25_acc_new <- function() {
  acc <- new.env(parent = emptyenv())
  acc$n <- 0L
  acc$plot <- list()
  acc$rule <- list()
  acc$sev <- list()
  acc$det <- list()
  acc
}

.vpro_lmh25_acc_add <- function(acc, p, rule, sev, detail) {
  k <- acc$n + 1L
  acc$n <- k
  acc$plot[[k]] <- as.character(p)
  acc$rule[[k]] <- as.character(rule)
  acc$sev[[k]] <- as.character(sev)
  acc$det[[k]] <- as.character(detail)
  invisible(NULL)
}

.vpro_lmh25_acc_tibble <- function(acc) {
  if (acc$n == 0L) {
    return(tibble::tibble(
      PlotNumber = character(),
      rule = character(),
      severity = character(),
      detail = character()
    ))
  }
  tibble::tibble(
    PlotNumber = as.character(unlist(acc$plot, use.names = FALSE)),
    rule = as.character(unlist(acc$rule, use.names = FALSE)),
    severity = as.character(unlist(acc$sev, use.names = FALSE)),
    detail = as.character(unlist(acc$det, use.names = FALSE))
  )
}

.vpro_audit_lmh25_substrates <- function(acc, pnum, erow, present_sub_cols) {
  if (length(present_sub_cols) == 0L) {
    return(invisible(NULL))
  }
  sub_vals <- vapply(present_sub_cols, function(sc) suppressWarnings(as.double(erow[[sc]][[1L]])), numeric(1))
  pop <- !is.na(sub_vals) & is.finite(sub_vals)
  if (!any(pop)) {
    return(invisible(NULL))
  }
  for (sc_nm in present_sub_cols[pop]) {
    v <- sub_vals[[sc_nm]]
    if (v < 0 || v > 100) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "substrate_sum",
        "error",
        sprintf("%s (%.2f%%) must be between 0%% and 100%%.", sc_nm, v)
      )
    }
  }
  s_tot <- sum(sub_vals[pop])
  if (abs(s_tot - 100.0) > 1.0) {
    .vpro_lmh25_acc_add(
      acc,
      pnum,
      "substrate_sum",
      "warning",
      sprintf("Surface substrates sum to %.2f%% across %d populated field(s); LMH25 requires 100%%.", vpro_round_ace(s_tot, 2L), sum(pop))
    )
  }
  invisible(NULL)
}

.vpro_audit_lmh25_humus <- function(acc, pnum, erow, h_df, soil_grp) {
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
      hz_chr <- ifelse(is.na(hz_raw), "", as.character(hz_raw))
      hz <- toupper(trimws(hz_chr))
      hz_base <- toupper(trimws(sub("^[0-9IVXivx ]+", "", trimws(hz_chr))))
      h_kind <- vpro_classify_humus_lmh25(hz_base, soil_grp)

      if ("vonPost" %in% names(h_df)) {
        vp <- suppressWarnings(as.double(h_df[["vonPost"]][[r]]))
        if (!is.na(vp) && is.finite(vp)) {
          if (vp < 1 || vp > 10) {
            .vpro_lmh25_acc_add(acc, pnum, "von_post", "error", sprintf("Horizon %s has vonPost = %g outside valid 1..10 scale.", hz, vp))
          } else if (startsWith(hz_base, "OF") && (vp < 1 || vp > 4)) {
            .vpro_lmh25_acc_add(acc, pnum, "von_post", "warning", sprintf("Fibric horizon %s has vonPost = %g (LMH25 Table 2.23 expects 1..4).", hz, vp))
          } else if (startsWith(hz_base, "OM") && (vp < 5 || vp > 6)) {
            .vpro_lmh25_acc_add(acc, pnum, "von_post", "warning", sprintf("Mesic peat horizon %s has vonPost = %g (LMH25 Table 2.23 expects 5..6).", hz, vp))
          } else if (startsWith(hz_base, "OH") && (vp < 7 || vp > 10)) {
            .vpro_lmh25_acc_add(acc, pnum, "von_post", "warning", sprintf("Humic peat horizon %s has vonPost = %g (LMH25 Table 2.23 expects 7..10).", hz, vp))
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
          .vpro_lmh25_acc_add(
            acc,
            pnum,
            "upland_depth_sign",
            "error",
            sprintf("Upland horizon %s (%.1f to %.1f cm) must have UpperDepth > LowerDepth >= 0.", hz, up_d, lo_d)
          )
        } else {
          up_valid[[length(up_valid) + 1L]] <- list(hz = hz, up = up_d, lo = lo_d)
          thick <- up_d - lo_d
          upland_tot <- upland_tot + thick
          if (startsWith(hz_base, "H")) upland_h <- upland_h + thick
        }
      } else if (identical(h_kind, "wetland")) {
        if (up_d < 0 || lo_d < 0 || up_d >= lo_d) {
          .vpro_lmh25_acc_add(
            acc,
            pnum,
            "downward_depth_sign",
            "error",
            sprintf("Wetland organic horizon %s (%.1f to %.1f cm) must have 0 <= UpperDepth < LowerDepth.", hz, up_d, lo_d)
          )
        } else {
          has_peaty <- TRUE
          wet_valid[[length(wet_valid) + 1L]] <- list(hz = hz, up = up_d, lo = lo_d)
          peat_tot <- peat_tot + (lo_d - up_d)
          t_s <- max(0.0, up_d)
          t_e <- min(40.0, lo_d)
          if (t_e > t_s) {
            sp <- t_e - t_s
            peat_u40 <- peat_u40 + sp
            if (startsWith(hz_base, "OF")) peat_of_u40 <- peat_of_u40 + sp
            if (startsWith(hz_base, "OM")) peat_om_u40 <- peat_om_u40 + sp
          }
        }
      }
    }
  }

  if (length(up_valid) > 0L && "HumusThickness" %in% names(erow)) {
    hdr_ht <- suppressWarnings(as.double(erow[["HumusThickness"]][[1L]]))
    if (!is.na(hdr_ht) && is.finite(hdr_ht)) {
      max_up <- max(vapply(up_valid, `[[`, numeric(1), "up"))
      min_lo <- min(vapply(up_valid, `[[`, numeric(1), "lo"))
      derived_ht <- vpro_round_ace(max_up - min_lo, 2L)
      diff_ht <- vpro_round_ace(hdr_ht - derived_ht, 2L)
      if (abs(diff_ht) > 2.0) {
        .vpro_lmh25_acc_add(
          acc,
          pnum,
          "humus_thickness",
          "warning",
          sprintf("Header HumusThickness (%.1f cm) differs from upland L/F/H horizon span (%.1f cm) by %+.1f cm.", hdr_ht, derived_ht, diff_ht)
        )
      }
    }
  }

  list(
    up_valid = up_valid,
    wet_valid = wet_valid,
    upland_tot = upland_tot,
    upland_h = upland_h,
    has_peaty = has_peaty,
    peat_tot = peat_tot,
    peat_u40 = peat_u40,
    peat_of_u40 = peat_of_u40,
    peat_om_u40 = peat_om_u40
  )
}

.vpro_audit_lmh25_mineral <- function(acc, pnum, m_df) {
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
      mz_stripped <- trimws(sub("^[0-9IVXivx ]+", "", mz_raw))
      mz_base <- toupper(mz_stripped)
      mz_low <- tolower(mz_stripped)
      up_d <- suppressWarnings(as.double(m_df[["UpperDepth"]][[r]]))
      lo_d <- suppressWarnings(as.double(m_df[["LowerDepth"]][[r]]))

      if (grepl("g", mz_low, fixed = TRUE) || startsWith(mz_base, "W")) {
        has_gley <- TRUE
        if (!is.na(up_d) && is.finite(up_d) && (min_gley_depth < 0 || up_d < min_gley_depth)) {
          min_gley_depth <- up_d
        }
      }
      if (grepl("u", mz_low, fixed = TRUE) || (startsWith(mz_base, "A") && grepl("b", mz_low, fixed = TRUE))) {
        has_turbation <- TRUE
      }
      if (grepl("sa", mz_low, fixed = TRUE) || (startsWith(mz_base, "B") && grepl("n", mz_low, fixed = TRUE))) {
        has_saline <- TRUE
      }
      if ("MineralFormpH" %in% names(m_df)) {
        mph <- suppressWarnings(as.double(m_df[["MineralFormpH"]][[r]]))
        if (!is.na(mph) && is.finite(mph) && mph > 8.2) has_saline <- TRUE
      }
      if (startsWith(mz_base, "R") && !is.na(up_d) && is.finite(up_d)) {
        if (lithic_depth < 0 || up_d < lithic_depth) lithic_depth <- up_d
      }
      if (startsWith(mz_base, "B") && "Colour" %in% names(m_df)) {
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
        .vpro_lmh25_acc_add(
          acc,
          pnum,
          "downward_depth_sign",
          "error",
          sprintf("Mineral horizon %s (%.1f to %.1f cm) must have 0 <= UpperDepth < LowerDepth.", mz, up_d, lo_d)
        )
        next
      }

      min_valid[[length(min_valid) + 1L]] <- list(hz = mz, up = up_d, lo = lo_d)
      thick <- lo_d - up_d
      if (lo_d > max_min_lower) max_min_lower <- lo_d
      if (startsWith(mz_base, "AH") || startsWith(mz_base, "AP")) ah_depth <- ah_depth + thick
      if (startsWith(mz_base, "AE")) ae_depth <- ae_depth + thick

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

  list(
    min_valid = min_valid,
    ah_depth = ah_depth,
    ae_depth = ae_depth,
    b_dark = b_dark,
    b_light = b_light,
    has_gley = has_gley,
    min_gley_depth = min_gley_depth,
    lithic_depth = lithic_depth,
    max_min_lower = max_min_lower,
    weighted_cf = weighted_cf,
    cf_weight = cf_weight,
    dom_tex = dom_tex,
    has_turbation = has_turbation,
    has_saline = has_saline
  )
}

.vpro_audit_lmh25_contiguity <- function(acc, pnum, up_valid, wet_valid, min_valid) {
  if (length(up_valid) >= 2L) {
    ord_u <- order(-vapply(up_valid, `[[`, numeric(1), "up"))
    up_sorted <- up_valid[ord_u]
    for (k_ix in seq_len(length(up_sorted) - 1L)) {
      cur <- up_sorted[[k_ix]]
      nxt <- up_sorted[[k_ix + 1L]]
      diff_d <- cur$lo - nxt$up
      if (abs(diff_d) > 0.01) {
        kind_str <- if (diff_d > 0) "gap" else "overlap"
        .vpro_lmh25_acc_add(
          acc,
          pnum,
          "horizon_contiguity",
          "warning",
          sprintf("Upland humus contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", kind_str, cur$hz, cur$lo, nxt$hz, nxt$up)
        )
      }
    }
  }
  if (length(up_valid) >= 1L && length(min_valid) >= 1L) {
    min_lo_u <- min(vapply(up_valid, `[[`, numeric(1), "lo"))
    if (min_lo_u > 0.01) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "horizon_contiguity",
        "warning",
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
        .vpro_lmh25_acc_add(
          acc,
          pnum,
          "horizon_contiguity",
          "warning",
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
        .vpro_lmh25_acc_add(
          acc,
          pnum,
          "horizon_contiguity",
          "warning",
          sprintf("Mineral horizon contiguity %s between %s (LowerDepth %.1f cm) and %s (UpperDepth %.1f cm).", kind_str, cur$hz, cur$lo, nxt$hz, nxt$up)
        )
      }
    }
  }
  invisible(NULL)
}

.vpro_audit_lmh25_edatopic <- function(acc, pnum, erow, hum_res, min_res) {
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
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "smr_snr_keys",
        "error",
        sprintf("MoistureRegime '%s' is outside valid LMH25 rSMR classes 0..8.", raw_smr)
      )
      smr_int <- NA_integer_
    }
  }
  if (nzchar(raw_snr) && (is.na(snr_int) || !grepl("^[A-Fa-f]([+-]|[-/][A-Fa-f])?$", raw_snr))) {
    if (is.na(snr_int) || !grepl("^[A-Fa-f]", raw_snr)) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "smr_snr_keys",
        "error",
        sprintf("NutrientRegime '%s' is outside valid LMH25 rSNR classes A..F.", raw_snr)
      )
      snr_int <- NA_integer_
    }
  }

  if (!is.na(smr_int)) {
    if (smr_int >= 7L && raw_drn %in% c("1", "2", "x", "vr", "r", "w", "very rapidly", "rapidly", "well")) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "smr_snr_keys",
        "warning",
        sprintf("Subhydric/hydric MoistureRegime (%s) conflicts with xeric/rapid/well SoilDrainage ('%s').", raw_smr, raw_drn)
      )
    } else if (smr_int <= 1L && raw_drn %in% c("5", "6", "p", "v", "vp", "aq", "pa", "poorly", "very poorly")) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "smr_snr_keys",
        "warning",
        sprintf("Very xeric/xeric MoistureRegime (%s) conflicts with poor/very poor SoilDrainage ('%s').", raw_smr, raw_drn)
      )
    }
    if (hum_res$peat_tot >= 40.0 && smr_int <= 4L) {
      .vpro_lmh25_acc_add(
        acc,
        pnum,
        "smr_snr_keys",
        "warning",
        sprintf("Wetland Of/Om/Oh peat thickness is %.1f cm (>= 40 cm) but MoistureRegime is '%s' (<= 4).", hum_res$peat_tot, raw_smr)
      )
    }
  }

  keyed <- vpro_infer_lmh25_keys(
    erow,
    hum_res$has_peaty,
    hum_res$peat_tot,
    hum_res$peat_u40,
    hum_res$peat_of_u40,
    hum_res$peat_om_u40,
    hum_res$upland_tot,
    hum_res$upland_h,
    min_res$ah_depth,
    min_res$ae_depth,
    min_res$b_dark,
    min_res$b_light,
    min_res$has_gley,
    min_res$min_gley_depth,
    min_res$lithic_depth,
    min_res$max_min_lower,
    min_res$weighted_cf,
    min_res$cf_weight,
    min_res$dom_tex,
    min_res$has_turbation,
    min_res$has_saline
  )
  if (!is.na(smr_int) && !is.na(keyed$smr_class) && abs(smr_int - keyed$smr_class) >= 2L) {
    .vpro_lmh25_acc_add(
      acc,
      pnum,
      "smr_snr_keys",
      "warning",
      sprintf("Field MoistureRegime ('%s') diverges by %d classes from LMH25 Key 9.4 inference ('%s').", raw_smr, abs(smr_int - keyed$smr_class), keyed$smr_label)
    )
  }
  if (!is.na(snr_int) && !is.na(keyed$snr_class) && abs(snr_int - keyed$snr_class) >= 2L) {
    .vpro_lmh25_acc_add(
      acc,
      pnum,
      "smr_snr_keys",
      "warning",
      sprintf("Field NutrientRegime ('%s') diverges by %d classes from LMH25 Key 9.6 inference ('%s').", raw_snr, abs(snr_int - keyed$snr_class), keyed$snr_label)
    )
  }
  invisible(NULL)
}

#' Audit plots against `LMH25 (2023)` pedological and edatopic consistency rules
#'
#' Evaluates `LMH25` (*Field Manual for Describing Terrestrial Ecosystems*, 2nd
#' Ed., 2023) soil, substrate, and edatopic rules calibrated to VPro Desktop:
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
#' @keywords internal
.vpro_check_lmh25 <- function(ws, scope = c("su", "project")) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)

  env <- vpro_env(ws, scope = scope, include_admin = TRUE)
  env[["PlotNumber"]] <- as.character(env[["PlotNumber"]])
  env <- env[!duplicated(env[["PlotNumber"]]), , drop = FALSE]

  soil <- vpro_soil(ws, scope = scope, type = "both")
  humus <- soil$humus
  mineral <- soil$mineral

  hum_by_plot <- if (nrow(humus) > 0L) split(humus, humus[["PlotNumber"]]) else list()
  min_by_plot <- if (nrow(mineral) > 0L) split(mineral, mineral[["PlotNumber"]]) else list()

  sub_cols <- c(
    "SubstrateDecWood",
    "SubstrateBedRock",
    "SubstrateRocks",
    "SubstrateMineralSoil",
    "SubstrateOrganicMatter",
    "SubstrateWater"
  )
  present_sub_cols <- intersect(sub_cols, names(env))
  acc <- .vpro_lmh25_acc_new()

  for (i in seq_len(nrow(env))) {
    erow <- env[i, , drop = FALSE]
    pnum <- erow[["PlotNumber"]][[1L]]
    soil_grp <- if ("SoilClassGroup" %in% names(erow) && !is.na(erow[["SoilClassGroup"]][[1L]])) {
      trimws(as.character(erow[["SoilClassGroup"]][[1L]]))
    } else {
      ""
    }

    .vpro_audit_lmh25_substrates(acc, pnum, erow, present_sub_cols)
    hum_res <- .vpro_audit_lmh25_humus(acc, pnum, erow, hum_by_plot[[pnum]], soil_grp)
    min_res <- .vpro_audit_lmh25_mineral(acc, pnum, min_by_plot[[pnum]])
    .vpro_audit_lmh25_contiguity(acc, pnum, hum_res$up_valid, hum_res$wet_valid, min_res$min_valid)
    .vpro_audit_lmh25_edatopic(acc, pnum, erow, hum_res, min_res)
  }

  issues_tbl <- .vpro_lmh25_acc_tibble(acc)
  summary_tbl <- if (nrow(issues_tbl) == 0L) {
    tibble::tibble(rule = character(), severity = character(), n_issues = integer(), n_plots = integer())
  } else {
    dt_s <- data.table::as.data.table(issues_tbl)
    agg_s <- dt_s[,
      list(
        n_issues = as.integer(length(get("PlotNumber"))),
        n_plots = as.integer(length(unique(get("PlotNumber"))))
      ),
      by = c("rule", "severity")
    ]
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
#' @param x A `vpro_lmh25_audit` object (e.g., `$lmh25` from [vpro_validate()]).
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
#' @param x A `vpro_lmh25_audit` object (e.g., `$lmh25` from [vpro_validate()]).
#' @param ... Unused additional arguments.
#' @return The `$issues` tibble (`PlotNumber`, `rule`, `severity`, `detail`).
#' @export
as_tibble.vpro_lmh25_audit <- function(x, ...) {
  x$issues
}

.vpro_bounds_acc_new <- function() {
  acc <- new.env(parent = emptyenv())
  acc$n <- 0L
  acc$tbl <- list()
  acc$plot <- list()
  acc$field <- list()
  acc$val <- list()
  acc$rule <- list()
  acc
}

.vpro_bounds_acc_add <- function(acc, tbl, plot, fld, val, rule) {
  k <- acc$n + 1L
  acc$n <- k
  acc$tbl[[k]] <- as.character(tbl)
  acc$plot[[k]] <- as.character(plot)
  acc$field[[k]] <- as.character(fld)
  acc$val[[k]] <- as.character(val)
  acc$rule[[k]] <- as.character(rule)
  invisible(NULL)
}

.vpro_bounds_acc_tibble <- function(acc) {
  if (acc$n == 0L) {
    return(tibble::tibble(
      table = character(),
      PlotNumber = character(),
      field = character(),
      value = character(),
      rule = character()
    ))
  }
  tibble::tibble(
    table = as.character(unlist(acc$tbl, use.names = FALSE)),
    PlotNumber = as.character(unlist(acc$plot, use.names = FALSE)),
    field = as.character(unlist(acc$field, use.names = FALSE)),
    value = as.character(unlist(acc$val, use.names = FALSE)),
    rule = as.character(unlist(acc$rule, use.names = FALSE))
  )
}

.vpro_su_filter_bounds <- function(df, su_plots, use_su, pcol = "PlotNumber") {
  if (!use_su || nrow(df) == 0L) {
    return(df)
  }
  p <- as.character(df[[pcol]])
  df[!is.na(p) & (p %in% su_plots), , drop = FALSE]
}

.vpro_check_vp08_text_bounds <- function(acc, dbc, project, su_plots, use_su) {
  text_rules <- list(
    Env = list(
      plot_col = "PlotNumber",
      limits = c(
        PlotNumber = 7L,
        FieldNumber = 50L,
        ProjectID = 30L,
        Zone = 4L,
        SubZone = 8L,
        SiteSeries = 5L,
        Ecosection = 3L,
        NtsMapSheet = 8L
      )
    ),
    Admin = list(plot_col = "Plot", limits = c(Plot = 7L, PlotType = 10L)),
    Veg = list(
      plot_col = "PlotNumber",
      limits = c(
        PlotNumber = 7L,
        Species = 8L,
        Layer = 2L,
        Collected = 1L
      )
    ),
    Humus = list(plot_col = "PlotNumber", limits = c(PlotNumber = 7L, Horizon = 8L)),
    Mineral = list(
      plot_col = "PlotNumber",
      limits = c(
        PlotNumber = 7L,
        Horizon = 8L,
        Texture = 4L,
        Colour = 14L
      )
    )
  )

  for (sfx in names(text_rules)) {
    phys_tbl <- paste0(project, "_", sfx)
    if (!DBI::dbExistsTable(dbc, phys_tbl)) {
      next
    }
    flds <- DBI::dbListFields(dbc, phys_tbl)
    spec <- text_rules[[sfx]]
    pcol <- spec$plot_col
    check_cols <- names(spec$limits)[names(spec$limits) %in% flds]
    if (!(pcol %in% flds) || length(check_cols) == 0L) {
      next
    }

    sel_parts <- c(
      paste0('CAST(', vpro_quote_ident(pcol), ' AS TEXT) AS "__plot__"'),
      vapply(
        check_cols,
        function(cc) paste0('CAST(', vpro_quote_ident(cc), ' AS TEXT) AS ', vpro_quote_ident(cc)),
        character(1)
      )
    )
    df <- DBI::dbGetQuery(dbc, paste0("SELECT ", paste(sel_parts, collapse = ", "), " FROM ", vpro_quote_ident(phys_tbl)))
    df <- .vpro_su_filter_bounds(df, su_plots, use_su, "__plot__")
    if (nrow(df) == 0L) {
      next
    }
    pvec <- ifelse(is.na(df[["__plot__"]]), "", as.character(df[["__plot__"]]))

    for (cc in check_cols) {
      lim <- spec$limits[[cc]]
      raw_v <- df[[cc]]
      nn <- !is.na(raw_v)
      if (!any(nn)) {
        next
      }
      u16 <- vpro_utf16_len(as.character(raw_v[nn]))
      bad <- is.na(u16) | (u16 > lim)
      if (any(bad)) {
        bad_idx <- which(nn)[bad]
        bad_u16 <- u16[bad]
        for (k in seq_along(bad_idx)) {
          bi <- bad_idx[[k]]
          .vpro_bounds_acc_add(
            acc,
            sfx,
            pvec[[bi]],
            cc,
            raw_v[[bi]],
            if (is.na(bad_u16[[k]])) "Invalid or unsupported text characters" else sprintf("Exceeds %d-character limit", lim)
          )
        }
      }
    }
  }
  invisible(NULL)
}

.vpro_check_vp08_cover_bounds <- function(acc, dbc, project, su_plots, use_su) {
  cover_specs <- list(
    Veg = list(
      plot_col = "PlotNumber",
      cols = c(
        "Cover1",
        "Cover2",
        "Cover3",
        "TotalA",
        "Cover4",
        "Cover5",
        "Cover5a",
        "Cover5b",
        "Cover5c",
        "TotalB",
        "Cover6",
        "Cover7",
        "Cover8",
        "Cover9",
        "Cover10"
      )
    ),
    Env = list(
      plot_col = "PlotNumber",
      cols = c("StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss")
    ),
    Admin = list(plot_col = "Plot", cols = c("StrataCoverTotal"))
  )

  for (sfx in names(cover_specs)) {
    phys_tbl <- paste0(project, "_", sfx)
    if (!DBI::dbExistsTable(dbc, phys_tbl)) {
      next
    }
    flds <- DBI::dbListFields(dbc, phys_tbl)
    spec <- cover_specs[[sfx]]
    pcol <- spec$plot_col
    check_cols <- intersect(spec$cols, flds)
    if (!(pcol %in% flds) || length(check_cols) == 0L) {
      next
    }

    sel_parts <- c(
      paste0('CAST(', vpro_quote_ident(pcol), ' AS TEXT) AS "__plot__"'),
      vapply(
        check_cols,
        function(cc) {
          paste0('CAST(', vpro_quote_ident(cc), ' AS TEXT) AS ', vpro_quote_ident(paste0("__txt_", cc)), ', ', vpro_quote_ident(cc), ' AS ', vpro_quote_ident(cc))
        },
        character(1)
      )
    )
    df <- DBI::dbGetQuery(dbc, paste0("SELECT ", paste(sel_parts, collapse = ", "), " FROM ", vpro_quote_ident(phys_tbl)))
    df <- .vpro_su_filter_bounds(df, su_plots, use_su, "__plot__")
    if (nrow(df) == 0L) {
      next
    }
    pvec <- ifelse(is.na(df[["__plot__"]]), "", as.character(df[["__plot__"]]))

    for (cc in check_cols) {
      raw_v <- df[[cc]]
      nn <- !is.na(raw_v) & !(is.character(raw_v) & !nzchar(trimws(as.character(raw_v))))
      if (!any(nn)) {
        next
      }
      num_v <- suppressWarnings(as.double(raw_v[nn]))
      f32_v <- vpro_narrow_float32(num_v)
      bad <- is.na(f32_v) | !is.finite(f32_v) | f32_v < 0 | f32_v >= 100
      if (any(bad)) {
        bad_idx <- which(nn)[bad]
        txt_col <- paste0("__txt_", cc)
        for (bi in bad_idx) {
          .vpro_bounds_acc_add(acc, sfx, pvec[[bi]], cc, df[[txt_col]][[bi]], "Cover must be >= 0 and under 100%")
        }
      }
    }
  }
  invisible(NULL)
}

.vpro_check_vp08_numeric_bounds <- function(acc, dbc, project, su_plots, use_su) {
  env_tbl <- paste0(project, "_Env")
  if (DBI::dbExistsTable(dbc, env_tbl)) {
    eflds <- DBI::dbListFields(dbc, env_tbl)
    num_want <- intersect(c("Latitude", "Longitude", "Aspect", "SlopeGradient"), eflds)
    if ("PlotNumber" %in% eflds && length(num_want) > 0L) {
      sel <- c('CAST("PlotNumber" AS TEXT) AS "__plot__"', vpro_quote_ident(num_want))
      edf <- DBI::dbGetQuery(dbc, paste0("SELECT ", paste(sel, collapse = ", "), " FROM ", vpro_quote_ident(env_tbl)))
      edf <- .vpro_su_filter_bounds(edf, su_plots, use_su, "__plot__")
      if (nrow(edf) > 0L) {
        pvec <- ifelse(is.na(edf[["__plot__"]]), "", as.character(edf[["__plot__"]]))
        if ("Latitude" %in% num_want) {
          lat <- suppressWarnings(as.double(edf[["Latitude"]]))
          bad <- !is.na(edf[["Latitude"]]) & (is.na(lat) | lat < -90 | lat > 90)
          for (bi in which(bad)) {
            .vpro_bounds_acc_add(acc, "Env", pvec[[bi]], "Latitude", edf[["Latitude"]][[bi]], "Latitude must be between -90 and 90")
          }
        }
        if ("Longitude" %in% num_want) {
          lon <- suppressWarnings(as.double(edf[["Longitude"]]))
          bad <- !is.na(edf[["Longitude"]]) & (is.na(lon) | lon < -180 | lon > 180)
          for (bi in which(bad)) {
            .vpro_bounds_acc_add(acc, "Env", pvec[[bi]], "Longitude", edf[["Longitude"]][[bi]], "Longitude must be between -180 and 180")
          }
        }
        if ("Aspect" %in% num_want) {
          asp <- suppressWarnings(as.double(edf[["Aspect"]]))
          bad <- !is.na(edf[["Aspect"]]) & (is.na(asp) | asp != floor(asp) | (asp != 999 & (asp < 0 | asp > 359)))
          for (bi in which(bad)) {
            .vpro_bounds_acc_add(acc, "Env", pvec[[bi]], "Aspect", edf[["Aspect"]][[bi]], "Aspect must be 0..359 or 999 (level)")
          }
        }
        if ("SlopeGradient" %in% num_want) {
          slp <- suppressWarnings(as.double(edf[["SlopeGradient"]]))
          bad <- !is.na(edf[["SlopeGradient"]]) & (is.na(slp) | slp < 0)
          for (bi in which(bad)) {
            .vpro_bounds_acc_add(acc, "Env", pvec[[bi]], "SlopeGradient", edf[["SlopeGradient"]][[bi]], "SlopeGradient must be >= 0")
          }
        }
      }
    }
  }

  adm_tbl <- paste0(project, "_Admin")
  if (DBI::dbExistsTable(dbc, adm_tbl)) {
    aflds <- DBI::dbListFields(dbc, adm_tbl)
    if (all(c("Plot", "StartDate") %in% aflds)) {
      adf <- DBI::dbGetQuery(
        dbc,
        paste0('SELECT CAST("Plot" AS TEXT) AS "__plot__", typeof("StartDate") AS "__sd_t__", "StartDate" FROM ', vpro_quote_ident(adm_tbl), ' WHERE "StartDate" IS NOT NULL')
      )
      adf <- .vpro_su_filter_bounds(adf, su_plots, use_su, "__plot__")
      if (nrow(adf) > 0L) {
        pvec <- ifelse(is.na(adf[["__plot__"]]), "", as.character(adf[["__plot__"]]))
        sd_num <- suppressWarnings(as.double(adf[["StartDate"]]))
        bad <- adf[["__sd_t__"]] != "integer" | is.na(sd_num) | sd_num < 1900 | sd_num > 2500
        for (bi in which(bad)) {
          .vpro_bounds_acc_add(acc, "Admin", pvec[[bi]], "StartDate", adf[["StartDate"]][[bi]], "StartDate must be between 1900 and 2500")
        }
      }
    }
  }
  invisible(NULL)
}

.vpro_check_vp08_bounds <- function(dbc, project, su_plots, use_su) {
  acc <- .vpro_bounds_acc_new()
  .vpro_check_vp08_text_bounds(acc, dbc, project, su_plots, use_su)
  .vpro_check_vp08_cover_bounds(acc, dbc, project, su_plots, use_su)
  .vpro_check_vp08_numeric_bounds(acc, dbc, project, su_plots, use_su)
  .vpro_bounds_acc_tibble(acc)
}
