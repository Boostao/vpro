# BEC Differential & Diagnostic Synthesis Engine ------------------------------

.vpro_s3_state <- new.env(parent = emptyenv())

.vpro_register_wave2b_s3 <- function() {
  if (isTRUE(.vpro_s3_state$registered)) {
    return(invisible(NULL))
  }
  pkg_env <- topenv()
  reg_one <- function(gen_pkg, gen_name, cls) {
    fn_name <- paste0(gen_name, ".", cls)
    if (!exists(fn_name, envir = pkg_env, mode = "function", inherits = FALSE)) {
      return(invisible(NULL))
    }
    gen_env <- asNamespace(gen_pkg)
    s3_tbl <- gen_env[[".__S3MethodsTable__."]]
    if (is.environment(s3_tbl) && !exists(fn_name, envir = s3_tbl, inherits = FALSE)) {
      base::registerS3method(gen_name, cls, get(fn_name, envir = pkg_env), envir = gen_env)
    }
    invisible(NULL)
  }

  reg_one("base", "print", "vpro_diagnostics")
  reg_one("base", "summary", "vpro_diagnostics")
  reg_one("tibble", "as_tibble", "vpro_diagnostics")

  reg_one("base", "print", "vpro_pairwise")
  reg_one("tibble", "as_tibble", "vpro_pairwise")

  reg_one("base", "print", "vpro_outliers")
  reg_one("tibble", "as_tibble", "vpro_outliers")

  reg_one("base", "print", "vpro_profile_rule")
  reg_one("base", "print", "vpro_profile_result")
  reg_one("tibble", "as_tibble", "vpro_profile_result")

  reg_one("base", "print", "vpro_summary_veg")
  reg_one("tibble", "as_tibble", "vpro_summary_veg")

  reg_one("base", "print", "vpro_summary_env")
  reg_one("tibble", "as_tibble", "vpro_summary_env")

  .vpro_s3_state$registered <- TRUE
  invisible(NULL)
}

.vpro_lifeform_catalog <- function(code) {
  lf <- suppressWarnings(as.integer(code))
  n <- length(lf)
  lf_name <- rep("Unclassified", n)
  stratum <- rep("Unclassified", n)

  map_name <- c(
    "1" = "Conifer Tree",
    "2" = "Deciduous Tree",
    "3" = "Evergreen Shrub",
    "4" = "Deciduous Shrub",
    "5" = "Fern",
    "6" = "Graminoid",
    "7" = "Forb",
    "8" = "Parasitic",
    "9" = "Moss",
    "10" = "Liverwort",
    "11" = "Lichen",
    "12" = "Dwarf Woody Plant",
    "13" = "Macro Algae"
  )
  map_stratum <- c(
    "1" = "Tree",
    "2" = "Tree",
    "3" = "Shrub",
    "4" = "Shrub",
    "5" = "Herb",
    "6" = "Herb",
    "7" = "Herb",
    "8" = "Herb",
    "9" = "Moss",
    "10" = "Moss",
    "11" = "Moss",
    "12" = "Shrub",
    "13" = "Moss"
  )

  ok <- !is.na(lf)
  if (any(ok)) {
    keys <- as.character(lf[ok])
    known <- keys %in% names(map_name)
    if (any(known)) {
      lf_name[ok][known] <- unname(map_name[keys[known]])
      stratum[ok][known] <- unname(map_stratum[keys[known]])
    }
    if (any(!known)) {
      lf_name[ok][!known] <- paste0("Lifeform ", keys[!known])
    }
  }
  list(lifeform_name = lf_name, stratum_group = stratum)
}

.vpro_stratum_rank <- function(stratum) {
  ranks <- c("Tree" = 1L, "Shrub" = 2L, "Herb" = 3L, "Moss" = 4L, "Unclassified" = 5L)
  out <- unname(ranks[as.character(stratum)])
  out[is.na(out)] <- 5L
  out
}

.vpro_order_units <- function(units) {
  u <- unique(as.character(units[!is.na(units) & nzchar(trimws(units))]))
  if (length(u) <= 1L) {
    return(u)
  }
  u[order(tolower(u), u, method = "radix")]
}

.vpro_apply_hierarchy_breaks <- function(ws, su_df) {
  if (nrow(su_df) == 0L || is.null(ws$hierarchy)) {
    return(list(su = su_df, applied = FALSE))
  }
  hier <- vpro_hierarchy(ws, as = "both")
  if (nrow(hier$nodes) == 0L || !any(hier$nodes$IsBreakpoint, na.rm = TRUE)) {
    return(list(su = su_df, applied = FALSE))
  }

  # Map every hierarchy node (leaf or interior) to its lowest `~` breakpoint ancestor
  nodes <- hier$nodes
  id_chr <- as.character(nodes$ID)
  par_chr <- ifelse(is.na(nodes$Parent), NA_character_, as.character(nodes$Parent))
  idx_by_id <- stats::setNames(seq_along(id_chr), id_chr)

  node_brk <- rep(NA_character_, nrow(nodes))
  for (i in seq_len(nrow(nodes))) {
    chain <- integer()
    cur <- i
    seen <- integer()
    while (!is.na(cur) && !(cur %in% seen)) {
      chain <- c(cur, chain)
      seen <- c(seen, cur)
      p_id <- par_chr[[cur]]
      if (is.na(p_id) || !(p_id %in% names(idx_by_id))) break
      nxt <- idx_by_id[[p_id]]
      if (identical(nxt, cur)) break
      cur <- nxt
    }
    brk <- NA_character_
    for (ci in chain) {
      if (isTRUE(nodes$IsBreakpoint[[ci]])) {
        brk <- nodes$CleanName[[ci]]
      }
    }
    node_brk[[i]] <- brk
  }

  # Match exact CleanName, raw Name, and whitespace-normalized names
  norm_key <- function(x) tolower(trimws(as.character(x)))
  compact_key <- function(x) tolower(gsub("[[:space:]]+", "", as.character(x)))

  brk_by_clean <- stats::setNames(node_brk, norm_key(nodes$CleanName))
  brk_by_raw <- stats::setNames(node_brk, norm_key(nodes$Name))
  brk_by_compact <- stats::setNames(node_brk, compact_key(nodes$CleanName))

  su_keys <- norm_key(su_df$SiteUnit)
  mapped <- unname(brk_by_clean[su_keys])
  miss <- is.na(mapped)
  if (any(miss)) {
    mapped[miss] <- unname(brk_by_raw[su_keys[miss]])
  }
  miss2 <- is.na(mapped)
  if (any(miss2)) {
    mapped[miss2] <- unname(brk_by_compact[compact_key(su_df$SiteUnit[miss2])])
  }

  keep <- !is.na(mapped) & nzchar(mapped)
  rolled <- tibble::tibble(
    PlotNumber = as.character(su_df$PlotNumber[keep]),
    SiteUnit = as.character(mapped[keep])
  )
  rolled <- rolled[!duplicated(paste0(rolled$PlotNumber, "\r", rolled$SiteUnit)), , drop = FALSE]
  list(su = rolled, applied = TRUE)
}

.vpro_resolve_classified_plots <- function(
  ws,
  exclude_modifiers = TRUE,
  hierarchy_breaks = FALSE
) {
  env_df <- vpro_env(ws, scope = "project", include_admin = TRUE, exclude_modifiers = FALSE)
  if (nrow(env_df) == 0L) {
    return(list(
      su = tibble::tibble(PlotNumber = character(), SiteUnit = character()),
      env = env_df,
      units = character(),
      breaks_applied = FALSE
    ))
  }

  if (!is.null(ws$su)) {
    su_raw <- vpro_site_units(ws, exclude_modifiers = FALSE)
    su_raw <- su_raw[su_raw$PlotNumber %in% env_df$PlotNumber, , drop = FALSE]
  } else if ("UserSiteUnit" %in% names(env_df)) {
    usu <- trimws(ifelse(is.na(env_df$UserSiteUnit), "", as.character(env_df$UserSiteUnit)))
    ok <- nzchar(usu)
    su_raw <- tibble::tibble(
      PlotNumber = as.character(env_df$PlotNumber[ok]),
      SiteUnit = usu[ok]
    )
  } else {
    su_raw <- tibble::tibble(PlotNumber = character(), SiteUnit = character())
  }

  if (nrow(su_raw) > 0L) {
    su_raw$SiteUnit <- trimws(as.character(su_raw$SiteUnit))
    su_raw <- su_raw[!is.na(su_raw$SiteUnit) & nzchar(su_raw$SiteUnit), , drop = FALSE]
  }
  if (isTRUE(exclude_modifiers) && nrow(su_raw) > 0L) {
    su_raw <- su_raw[!vpro_is_modifier_unit(su_raw$SiteUnit), , drop = FALSE]
  }

  breaks_applied <- FALSE
  if (isTRUE(hierarchy_breaks) && nrow(su_raw) > 0L) {
    hb <- .vpro_apply_hierarchy_breaks(ws, su_raw)
    su_raw <- hb$su
    breaks_applied <- hb$applied
  }

  units <- .vpro_order_units(su_raw$SiteUnit)
  env_sub <- env_df[match(su_raw$PlotNumber, env_df$PlotNumber), , drop = FALSE]
  if (nrow(env_sub) > 0L) {
    env_sub$SiteUnit <- su_raw$SiteUnit
  }

  list(
    su = su_raw,
    env = tibble::as_tibble(env_sub),
    units = units,
    breaks_applied = breaks_applied
  )
}

.vpro_extract_plot_species_veg <- function(
  ws,
  plot_numbers,
  lump = TRUE,
  resolve_synonyms = FALSE,
  cover_precedence = c("sublayer_sum", "strata_totals")
) {
  cover_precedence <- match.arg(cover_precedence)
  empty <- tibble::tibble(
    PlotNumber = character(),
    Species = character(),
    Cover = numeric()
  )
  plot_numbers <- unique(as.character(plot_numbers[!is.na(plot_numbers) & nzchar(plot_numbers)]))
  if (length(plot_numbers) == 0L) {
    return(empty)
  }

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  veg_tbl <- paste0(ws$project, "_Veg")
  veg_fields <- DBI::dbListFields(dbc, veg_tbl)
  all_layer_cols <- c(
    "Cover1", "Cover2", "Cover3", "TotalA",
    "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
    "Cover6", "Cover7", "Cover8", "Cover9", "Cover10"
  )
  present_cols <- intersect(all_layer_cols, veg_fields)
  if (length(present_cols) == 0L) {
    return(empty)
  }

  sel_cols <- paste(
    c(
      'CAST("PlotNumber" AS TEXT) AS "PlotNumber"',
      'UPPER(TRIM(CAST("Species" AS TEXT))) AS "Species"',
      vapply(
        present_cols,
        function(col) paste0("CAST(", vpro_quote_ident(col), " AS REAL) AS ", vpro_quote_ident(col)),
        character(1)
      )
    ),
    collapse = ", "
  )

  raw_df <- vpro_query_scoped_plots(
    dbc,
    vpro_quote_ident(veg_tbl),
    plot_numbers,
    select_cols = sel_cols,
    where_extra = '"Species" IS NOT NULL AND TRIM(CAST("Species" AS TEXT)) <> \'\''
  )
  if (nrow(raw_df) == 0L) {
    return(empty)
  }

  dt <- data.table::as.data.table(raw_df)
  data.table::set(dt, j = "PlotNumber", value = as.character(dt[["PlotNumber"]]))
  data.table::set(dt, j = "Species", value = toupper(trimws(as.character(dt[["Species"]]))))

  for (cc in present_cols) {
    v <- vpro_narrow_float32(as.numeric(dt[[cc]]))
    v[!is.na(v) & v > 100] <- 100
    v[!is.na(v) & v < 0] <- NA_real_
    data.table::set(dt, j = cc, value = v)
  }

  # Stratum A/B cover precedence:
  # - "sublayer_sum" (diagnostics/synthesis engine default): use Cover1..3 when any sublayer is populated, else TotalA
  # - "strata_totals" (MS Access vpro_veg default): use positive TotalA (or non-NA TotalA when sublayers are absent)
  sub_a <- intersect(c("Cover1", "Cover2", "Cover3"), present_cols)
  if ("TotalA" %in% present_cols && length(sub_a) > 0L) {
    has_sub_a <- rowSums(!is.na(as.matrix(dt[, sub_a, with = FALSE]))) > 0L
    ta <- dt[["TotalA"]]
    if (identical(cover_precedence, "sublayer_sum")) {
      ta[has_sub_a] <- NA_real_
      data.table::set(dt, j = "TotalA", value = ta)
    } else {
      use_ta <- !is.na(ta) & (ta > 0 | !has_sub_a)
      ta[!use_ta] <- NA_real_
      data.table::set(dt, j = "TotalA", value = ta)
      for (sc in sub_a) {
        sv <- dt[[sc]]
        sv[use_ta] <- NA_real_
        data.table::set(dt, j = sc, value = sv)
      }
    }
  }
  sub_b <- intersect(c("Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c"), present_cols)
  if ("TotalB" %in% present_cols && length(sub_b) > 0L) {
    has_sub_b <- rowSums(!is.na(as.matrix(dt[, sub_b, with = FALSE]))) > 0L
    tb <- dt[["TotalB"]]
    if (identical(cover_precedence, "sublayer_sum")) {
      tb[has_sub_b] <- NA_real_
      data.table::set(dt, j = "TotalB", value = tb)
    } else {
      use_tb <- !is.na(tb) & (tb > 0 | !has_sub_b)
      tb[!use_tb] <- NA_real_
      data.table::set(dt, j = "TotalB", value = tb)
      for (sc in sub_b) {
        sv <- dt[[sc]]
        sv[use_tb] <- NA_real_
        data.table::set(dt, j = sc, value = sv)
      }
    }
  }

  # Resolve optional species lump mapping & synonyms
  lump_tbl <- vpro_lump_map(ws, lump = lump)
  has_lump <- nrow(lump_tbl) > 0L
  lmap <- if (has_lump) stats::setNames(lump_tbl$LumpCode, lump_tbl$SppCode) else character()
  syn_map <- if (isTRUE(resolve_synonyms)) vpro_synonym_map(ws) else character()

  if (length(lmap) > 0L && length(syn_map) > 0L) {
    syn_spp <- unname(syn_map[names(lmap)])
    extra <- !is.na(syn_spp) & !(syn_spp %in% names(lmap))
    if (any(extra)) {
      extra_map <- stats::setNames(unname(lmap[extra]), syn_spp[extra])
      extra_map <- extra_map[!duplicated(names(extra_map))]
      lmap <- c(lmap, extra_map)
    }
  }

  was_mapped <- rep(FALSE, nrow(dt))
  if (length(lmap) > 0L) {
    m1 <- lmap[dt[["Species"]]]
    hit1 <- !is.na(m1) & m1 != dt[["Species"]]
    if (any(hit1)) {
      spp_new <- dt[["Species"]]
      spp_new[hit1] <- unname(m1[hit1])
      data.table::set(dt, j = "Species", value = spp_new)
      was_mapped[hit1] <- TRUE
    }
  }
  if (length(syn_map) > 0L) {
    ms <- syn_map[dt[["Species"]]]
    hits <- !is.na(ms)
    if (any(hits)) {
      spp_new <- dt[["Species"]]
      spp_new[hits] <- unname(ms[hits])
      data.table::set(dt, j = "Species", value = spp_new)
    }
  }
  if (length(lmap) > 0L) {
    m2 <- lmap[dt[["Species"]]]
    hit2 <- !is.na(m2) & m2 != dt[["Species"]]
    if (any(hit2)) {
      spp_new <- dt[["Species"]]
      spp_new[hit2] <- unname(m2[hit2])
      data.table::set(dt, j = "Species", value = spp_new)
      was_mapped[hit2] <- TRUE
    }
  }

  # Unpivot populated layer observations and fold per (PlotNumber, Layer, Species)
  # applying the 99% cap to lumped cells (matching engine.go lines 979-984)
  layer_parts <- lapply(seq_along(present_cols), function(idx) {
    cc <- present_cols[[idx]]
    vals <- dt[[cc]]
    ok <- !is.na(vals) & vals >= 0
    if (!any(ok)) return(NULL)
    data.table::data.table(
      PlotNumber = dt[["PlotNumber"]][ok],
      LayerID = rep(idx, sum(ok)),
      Species = dt[["Species"]][ok],
      Cover = vals[ok],
      Mapped = was_mapped[ok]
    )
  })
  long_dt <- data.table::rbindlist(Filter(Negate(is.null), layer_parts))
  if (nrow(long_dt) == 0L) {
    return(empty)
  }

  folded <- long_dt[, list(
    Cover = sum(get("Cover")),
    N = .N,
    AnyMapped = any(get("Mapped"))
  ), by = c("PlotNumber", "LayerID", "Species")]

  if (has_lump) {
    cov_vec <- folded[["Cover"]]
    cap_mask <- (folded[["AnyMapped"]] | folded[["N"]] > 1L) & cov_vec > 99.0
    if (any(cap_mask)) {
      cov_vec[cap_mask] <- 99.0
      data.table::set(folded, j = "Cover", value = cov_vec)
    }
  }

  plot_spp <- folded[, list(Cover = sum(get("Cover"))), by = c("PlotNumber", "Species")]
  data.table::setorderv(plot_spp, c("PlotNumber", "Species"))
  tibble::as_tibble(plot_spp)
}

.vpro_calc_diagnostic_potential <- function(
  constancy,
  mean_cover,
  min_constancy = 50,
  dominant = 7,
  minor = 1,
  min_diff = 0.1
) {
  const_exp <- 0.5
  cover_exp <- 0.333
  max_pot <- 10.0

  d_pot <- ifelse(
    constancy >= min_constancy & min_constancy < 100,
    4.0 * ((constancy - min_constancy) / (100.0 - min_constancy))^const_exp,
    ifelse(constancy >= min_constancy & constancy >= 100, 4.0, 0.0)
  )
  dd_pot <- ifelse(
    constancy >= min_constancy & mean_cover >= dominant & dominant < 100,
    4.0 * ((mean_cover - dominant) / (100.0 - dominant))^cover_exp,
    0.0
  )
  cov_wt <- ifelse(
    mean_cover >= minor,
    1.0,
    ifelse(mean_cover <= 0, 0.0, sqrt(pmax(mean_cover, 0.0) / minor))
  )
  d_pot_adj <- d_pot * cov_wt
  bonus <- ifelse(
    d_pot_adj > 0 & mean_cover >= dominant,
    2.0 * (d_pot_adj / 4.0)^2,
    0.0
  )
  diag_pot <- pmin(d_pot_adj + dd_pot + bonus, max_pot)
  diag_pot[diag_pot <= min_diff] <- 0.0
  list(
    d_potential = d_pot,
    dd_potential = dd_pot,
    diagnostic_potential = diag_pot
  )
}

.vpro_bec_refined_classify <- function(units, presence_vec, presence_num_vec, sig_num_vec) {
  k <- length(units)
  if (k == 0L || all(presence_num_vec == 0L)) {
    return(list(
      primary_unit = NA_character_,
      primary_diagnosis = NA_character_,
      cell_diagnosis = rep(NA_character_, k)
    ))
  }

  cell_diag <- rep(NA_character_, k)
  for (i in seq_len(k)) {
    if (presence_num_vec[[i]] == 0L) next
    p_self <- presence_vec[[i]]
    pn_self <- presence_num_vec[[i]]
    sn_self <- sig_num_vec[[i]]

    other_p <- if (k > 1L) max(presence_vec[-i], 0) else 0
    other_sn <- if (k > 1L) max(sig_num_vec[-i], 0L) else 0L

    d_diff <- p_self - other_p
    sig_diff <- sn_self - other_sn
    count_pres_near <- sum(presence_num_vec[presence_num_vec > 0L] > (pn_self - 2L))
    count_sig_near <- sum(sig_num_vec[presence_num_vec > 0L] > (sn_self - 2L))

    codes <- character()

    # BEC Diagnostic10.xla refined differential tiers (d1 >= 0.80, d2 >= 0.60, d3 >= 0.40 at presence >= 0.60)
    if (p_self >= 0.60 && d_diff >= 0.80) {
      codes <- c(codes, "d1")
    } else if (p_self >= 0.60 && d_diff >= 0.60) {
      codes <- c(codes, "d2")
    } else if ((p_self >= 0.60 && d_diff >= 0.40) || (pn_self >= 3L && count_pres_near == 1L && d_diff >= 0.40)) {
      codes <- c(codes, "d3")
    }

    # BEC Diagnostic10.xla dominant differential tiers (dd1 >= 5, dd2 == 4, dd3 == 3, dd4 == 2 classes above others)
    has_d <- length(codes) > 0L
    dd_eligible <- sn_self >= 5L && (p_self >= 0.60 || (!has_d && count_sig_near == 1L))
    if (dd_eligible) {
      if (sig_diff >= 5L) {
        codes <- c(codes, "dd1")
      } else if (sig_diff >= 4L) {
        codes <- c(codes, "dd2")
      } else if (sig_diff >= 3L) {
        codes <- c(codes, "dd3")
      } else if (sig_diff >= 2L) {
        codes <- c(codes, "dd4")
      }
    }

    # Constant dominant (cd), Constant (c), and Important companion (ic)
    if (pn_self == 5L && sn_self >= 5L) {
      codes <- c(codes, "cd")
    } else if (pn_self == 5L && sn_self < 5L) {
      codes <- c(codes, "c")
    } else if (length(codes) == 0L && pn_self >= 2L && count_pres_near == 1L) {
      codes <- c(codes, "ic")
    }

    if (length(codes) > 0L) {
      cell_diag[[i]] <- paste(codes, collapse = ", ")
    }
  }

  # Select primary BEC diagnostic unit prioritizing strongest differential/constant tier
  tier_score <- function(diag_str) {
    if (is.na(diag_str) || !nzchar(diag_str)) return(0L)
    parts <- trimws(strsplit(diag_str, ",", fixed = TRUE)[[1L]])
    weights <- c(
      "d1" = 100L, "d2" = 90L, "d3" = 80L,
      "dd1" = 70L, "dd2" = 60L, "dd3" = 50L, "dd4" = 40L,
      "cd" = 20L, "c" = 10L, "ic" = 5L
    )
    sum(unname(weights[parts]), na.rm = TRUE)
  }
  scores <- vapply(cell_diag, tier_score, integer(1))
  if (all(scores == 0L)) {
    return(list(
      primary_unit = NA_character_,
      primary_diagnosis = NA_character_,
      cell_diagnosis = cell_diag
    ))
  }
  best_ord <- order(-scores, -presence_vec, -sig_num_vec, seq_len(k))
  best_i <- best_ord[[1L]]
  list(
    primary_unit = units[[best_i]],
    primary_diagnosis = cell_diag[[best_i]],
    cell_diagnosis = cell_diag
  )
}

#' Compute BEC differential and diagnostic vegetation synthesis
#'
#' Vectorised R counterpart to legacy `V7mdlDiagnostic` (`Diagnostic10.xla`) and
#' `vpro_wails/internal/diagnostics`. Aggregates plot-level vegetation across
#' `SiteUnit`s (or `~` tilde `BreakpointUnit`s when `hierarchy_breaks = TRUE`),
#' applying IEEE-754 `float32` cover narrowing and VPro's `99%` per-layer cap on
#' lumped taxa, then computes Presence (`I..V` / `1..5`), Domin-Krajina
#' Significance (`+`, `1..9`), Goldstream and Prominence scores, Access
#' `V7mdlDiagnostic` crosstab classifications (`d`, `dd`, `cd`, `c`, `ic`), and
#' BEC refined differential tiers (`d1`, `d2`, `d3`, `dd1`, `dd2`, `dd3`, `dd4`,
#' `cd`, `c`, `ic`).
#'
#' @param ws A `vpro_workspace` handle created by [vpro_connect()].
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE`, a `*_Lump` table
#'   name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` units.
#' @param min_constancy Numeric minimum species constancy percentage (`[0, 100]`)
#'   required in at least one unit to retain a species.
#' @param average_type Cover denominator for Domin-Krajina significance,
#'   Goldstream, and Prominence: `"unit"` (`sum(cover) / n_plots`, standard BEC
#'   `By n Plots`) or `"characteristic"` (`sum(cover) / n_present`).
#' @param hierarchy_breaks Logical; if `TRUE` and `ws$hierarchy` contains `~`
#'   breakpoint nodes, rolls plots up to their `BreakpointUnit`.
#' @param cover_precedence Stratum cover precedence: `"sublayer_sum"` (default,
#'   matching Go/MS Access diagnostics where `TotalA`/`TotalB` is used only when
#'   sublayers are `NA`) or `"strata_totals"` (matching `vpro_veg` where positive
#'   `TotalA`/`TotalB` overrides sublayers).
#' @return An S3 object of class `vpro_diagnostics` containing `$unit_species`
#'   (long tibble), `$crosstab` (wide species-by-unit tibble with
#'   `DiagnosticUnit`, `Diagnosis`, `BECDiagnosticUnit`, and `BECDiagnosis`), and
#'   `$units` (unit summary tibble).
#' @export
vpro_diagnostics <- function(
  ws,
  lump = TRUE,
  exclude_modifiers = TRUE,
  min_constancy = 0,
  average_type = c("unit", "characteristic"),
  hierarchy_breaks = FALSE,
  cover_precedence = c("sublayer_sum", "strata_totals")
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  average_type <- match.arg(average_type)
  cover_precedence <- match.arg(cover_precedence)
  if (!is.numeric(min_constancy) || length(min_constancy) != 1L || is.na(min_constancy) || min_constancy < 0 || min_constancy > 100) {
    rlang::abort("`min_constancy` must be a single number between 0 and 100.")
  }

  scoped <- .vpro_resolve_classified_plots(
    ws,
    exclude_modifiers = exclude_modifiers,
    hierarchy_breaks = hierarchy_breaks
  )
  su_df <- scoped$su
  ordered_units <- scoped$units

  empty_unit_spp <- tibble::tibble(
    SiteUnit = character(),
    Species = character(),
    ScientificName = character(),
    EnglishName = character(),
    Lifeform = integer(),
    StratumGroup = character(),
    n_plots = integer(),
    n_present = integer(),
    presence = numeric(),
    constancy = numeric(),
    presence_class = character(),
    presence_num = integer(),
    mean_cover_unit = numeric(),
    mean_cover_present = numeric(),
    significance_class = character(),
    significance_num = integer(),
    goldstream = numeric(),
    prominence = numeric(),
    cell_code = character(),
    diagnostic_potential = numeric(),
    diagnosis = character(),
    bec_diagnosis = character(),
    is_diagnostic_unit = logical()
  )
  empty_crosstab <- tibble::tibble(
    Species = character(),
    ScientificName = character(),
    EnglishName = character(),
    Lifeform = integer(),
    StratumGroup = character(),
    DiagnosticUnit = character(),
    Diagnosis = character(),
    BECDiagnosticUnit = character(),
    BECDiagnosis = character()
  )
  empty_units <- tibble::tibble(
    SiteUnit = character(),
    n_plots = integer(),
    species_richness = integer(),
    n_diagnostic = integer(),
    n_constant = integer(),
    diag_potential_sum = numeric()
  )

  if (length(ordered_units) == 0L || nrow(su_df) == 0L) {
    return(structure(
      list(
        unit_species = empty_unit_spp,
        crosstab = empty_crosstab,
        units = empty_units,
        average_type = average_type,
        hierarchy_breaks = scoped$breaks_applied
      ),
      class = "vpro_diagnostics"
    ))
  }

  # Unit plot counts (distinct PlotNumber per unit)
  su_dt <- data.table::as.data.table(su_df)
  su_dt <- unique(su_dt, by = c("PlotNumber", "SiteUnit"))
  unit_counts_dt <- su_dt[, list(n_plots = .N), by = "SiteUnit"]
  n_plots_map <- stats::setNames(as.integer(unit_counts_dt[["n_plots"]]), unit_counts_dt[["SiteUnit"]])

  veg_ps <- .vpro_extract_plot_species_veg(
    ws,
    su_dt[["PlotNumber"]],
    lump = lump,
    cover_precedence = cover_precedence
  )
  if (nrow(veg_ps) == 0L) {
    units_tbl <- tibble::tibble(
      SiteUnit = ordered_units,
      n_plots = unname(n_plots_map[ordered_units]),
      species_richness = rep(0L, length(ordered_units)),
      n_diagnostic = rep(0L, length(ordered_units)),
      n_constant = rep(0L, length(ordered_units)),
      diag_potential_sum = rep(0.0, length(ordered_units))
    )
    ct <- empty_crosstab
    for (u in ordered_units) ct[[u]] <- character()
    return(structure(
      list(
        unit_species = empty_unit_spp,
        crosstab = ct,
        units = units_tbl,
        average_type = average_type,
        hierarchy_breaks = scoped$breaks_applied
      ),
      class = "vpro_diagnostics"
    ))
  }

  veg_dt <- merge(
    su_dt,
    data.table::as.data.table(veg_ps),
    by = "PlotNumber",
    all = FALSE,
    allow.cartesian = TRUE
  )
  agg_dt <- veg_dt[, list(
    n_present = .N,
    sum_cover = sum(get("Cover"))
  ), by = c("SiteUnit", "Species")]

  data.table::set(agg_dt, j = "n_plots", value = unname(n_plots_map[agg_dt[["SiteUnit"]]]))
  presence_raw <- pmin(agg_dt[["n_present"]] / agg_dt[["n_plots"]], 1.0)
  constancy_raw <- presence_raw * 100.0
  mean_unit_raw <- agg_dt[["sum_cover"]] / agg_dt[["n_plots"]]
  mean_pres_raw <- agg_dt[["sum_cover"]] / agg_dt[["n_present"]]

  # Filter species by min_constancy across units
  agg_dt[, "constancy_raw" := constancy_raw]
  if (min_constancy > 0) {
    max_c_dt <- agg_dt[, list(max_c = max(get("constancy_raw"))), by = "Species"]
    keep_spp <- max_c_dt[["Species"]][max_c_dt[["max_c"]] >= min_constancy]
    agg_dt <- agg_dt[agg_dt[["Species"]] %in% keep_spp]
    if (nrow(agg_dt) == 0L) {
      units_tbl <- tibble::tibble(
        SiteUnit = ordered_units,
        n_plots = unname(n_plots_map[ordered_units]),
        species_richness = rep(0L, length(ordered_units)),
        n_diagnostic = rep(0L, length(ordered_units)),
        n_constant = rep(0L, length(ordered_units)),
        diag_potential_sum = rep(0.0, length(ordered_units))
      )
      ct <- empty_crosstab
      for (u in ordered_units) ct[[u]] <- character()
      return(structure(
        list(
          unit_species = empty_unit_spp,
          crosstab = ct,
          units = units_tbl,
          average_type = average_type,
          hierarchy_breaks = scoped$breaks_applied
        ),
        class = "vpro_diagnostics"
      ))
    }
    presence_raw <- pmin(agg_dt[["n_present"]] / agg_dt[["n_plots"]], 1.0)
    constancy_raw <- presence_raw * 100.0
    mean_unit_raw <- agg_dt[["sum_cover"]] / agg_dt[["n_plots"]]
    mean_pres_raw <- agg_dt[["sum_cover"]] / agg_dt[["n_present"]]
  }

  eff_cover <- if (identical(average_type, "unit")) mean_unit_raw else mean_pres_raw
  pres_cls <- vpro_presence_class(presence_raw)
  pres_num <- as.integer(vpro_presence_class(presence_raw, format = "numeric"))
  sig_cls <- vpro_significance_class(eff_cover)
  sig_num <- ifelse(sig_cls == "+", 0L, suppressWarnings(as.integer(sig_cls)))
  gold_vec <- vpro_goldstream_class(eff_cover, presence_raw, return_score = TRUE)
  prom_vec <- vpro_prominence_class(eff_cover, presence_raw, return_score = TRUE)
  cell_code_vec <- paste0(pres_num, " - ", sig_cls)
  diag_pot_vec <- .vpro_calc_diagnostic_potential(constancy_raw, mean_unit_raw)$diagnostic_potential

  tax <- vpro_taxonomy(ws, include_synonyms = FALSE, include_user = TRUE)
  all_spp <- sort(unique(agg_dt[["Species"]]))
  tax_m <- match(all_spp, tax$Code)
  spp_sci <- ifelse(is.na(tax_m), all_spp, tax$ScientificName[tax_m])
  spp_eng <- ifelse(is.na(tax_m), "", ifelse(is.na(tax$EnglishName[tax_m]), "", tax$EnglishName[tax_m]))
  spp_lf <- as.integer(tax$Lifeform[tax_m])
  lf_meta <- .vpro_lifeform_catalog(spp_lf)
  spp_stratum <- lf_meta$stratum_group

  spp_idx <- match(agg_dt[["Species"]], all_spp)
  unit_idx <- match(agg_dt[["SiteUnit"]], ordered_units)
  n_spp <- length(all_spp)
  n_u <- length(ordered_units)

  # Build species x unit matrices for fast vectorised / rowwise classification
  code_mat <- matrix(NA_character_, nrow = n_spp, ncol = n_u, dimnames = list(all_spp, ordered_units))
  pres_mat <- matrix(0.0, nrow = n_spp, ncol = n_u)
  pnum_mat <- matrix(0L, nrow = n_spp, ncol = n_u)
  snum_mat <- matrix(0L, nrow = n_spp, ncol = n_u)
  mcov_mat <- matrix(0.0, nrow = n_spp, ncol = n_u)

  lin_idx <- cbind(spp_idx, unit_idx)
  code_mat[lin_idx] <- cell_code_vec
  pres_mat[lin_idx] <- presence_raw
  pnum_mat[lin_idx] <- pres_num
  snum_mat[lin_idx] <- sig_num
  mcov_mat[lin_idx] <- mean_unit_raw

  diag_unit <- rep(NA_character_, n_spp)
  diag_str <- rep(NA_character_, n_spp)
  bec_unit <- rep(NA_character_, n_spp)
  bec_str <- rep(NA_character_, n_spp)

  cell_v7_mat <- matrix(NA_character_, nrow = n_spp, ncol = n_u)
  cell_bec_mat <- matrix(NA_character_, nrow = n_spp, ncol = n_u)
  cell_prim_mat <- matrix(FALSE, nrow = n_spp, ncol = n_u)

  for (s_i in seq_len(n_spp)) {
    uc <- stats::setNames(code_mat[s_i, ], ordered_units)
    v7 <- vpro_classify_diagnostic_codes(uc)
    diag_unit[[s_i]] <- v7$unit
    diag_str[[s_i]] <- v7$diagnosis

    for (u_j in seq_len(n_u)) {
      if (pnum_mat[s_i, u_j] == 0L) next
      if (!is.na(v7$unit) && identical(ordered_units[[u_j]], v7$unit)) {
        cell_prim_mat[s_i, u_j] <- TRUE
        cell_v7_mat[s_i, u_j] <- v7$diagnosis
      } else if (pnum_mat[s_i, u_j] == 5L) {
        cell_v7_mat[s_i, u_j] <- if (snum_mat[s_i, u_j] >= 5L) "cd" else "c"
      }
    }

    bec_res <- .vpro_bec_refined_classify(
      ordered_units,
      pres_mat[s_i, ],
      pnum_mat[s_i, ],
      snum_mat[s_i, ]
    )
    bec_unit[[s_i]] <- bec_res$primary_unit
    bec_str[[s_i]] <- bec_res$primary_diagnosis
    cell_bec_mat[s_i, ] <- bec_res$cell_diagnosis
  }

  # Order species matching vpro_wails/internal/diagnostics/engine.go:
  # diagnostic units first (in ordered_units order), then non-diagnostic, by stratum -> lifeform -> constancy -> cover
  has_diag <- !is.na(diag_unit) & nzchar(diag_unit)
  diag_u_rank <- ifelse(has_diag, match(diag_unit, ordered_units), n_u + 1L)
  st_rank <- .vpro_stratum_rank(spp_stratum)
  lf_sort <- ifelse(is.na(spp_lf), 999L, spp_lf)
  max_const_spp <- apply(pres_mat * 100.0, 1L, max)
  max_cov_spp <- apply(mcov_mat, 1L, max)

  spp_ord <- order(
    ifelse(has_diag, 0L, 1L),
    diag_u_rank,
    st_rank,
    lf_sort,
    -vpro_round_ace(max_const_spp, 1L),
    -vpro_round_ace(max_cov_spp, 2L),
    spp_sci,
    all_spp
  )

  # Assemble wide $crosstab tibble
  ct_list <- list(
    Species = all_spp[spp_ord],
    ScientificName = spp_sci[spp_ord],
    EnglishName = spp_eng[spp_ord],
    Lifeform = spp_lf[spp_ord],
    StratumGroup = spp_stratum[spp_ord],
    DiagnosticUnit = diag_unit[spp_ord],
    Diagnosis = diag_str[spp_ord],
    BECDiagnosticUnit = bec_unit[spp_ord],
    BECDiagnosis = bec_str[spp_ord]
  )
  code_mat_ord <- code_mat[spp_ord, , drop = FALSE]
  for (u_j in seq_len(n_u)) {
    ct_list[[ordered_units[[u_j]]]] <- as.character(code_mat_ord[, u_j])
  }
  crosstab_tbl <- tibble::as_tibble(ct_list)

  # Assemble long $unit_species tibble
  unit_species_tbl <- tibble::tibble(
    SiteUnit = as.character(agg_dt[["SiteUnit"]]),
    Species = as.character(agg_dt[["Species"]]),
    ScientificName = as.character(spp_sci[spp_idx]),
    EnglishName = as.character(spp_eng[spp_idx]),
    Lifeform = as.integer(spp_lf[spp_idx]),
    StratumGroup = as.character(spp_stratum[spp_idx]),
    n_plots = as.integer(agg_dt[["n_plots"]]),
    n_present = as.integer(agg_dt[["n_present"]]),
    presence = presence_raw,
    constancy = vpro_round_ace(constancy_raw, 1L),
    presence_class = pres_cls,
    presence_num = pres_num,
    mean_cover_unit = vpro_round_ace(mean_unit_raw, 2L),
    mean_cover_present = vpro_round_ace(mean_pres_raw, 2L),
    significance_class = sig_cls,
    significance_num = as.integer(sig_num),
    goldstream = vpro_round_ace(gold_vec, 2L),
    prominence = vpro_round_ace(prom_vec, 2L),
    cell_code = cell_code_vec,
    diagnostic_potential = vpro_round_ace(diag_pot_vec, 2L),
    diagnosis = as.character(cell_v7_mat[lin_idx]),
    bec_diagnosis = as.character(cell_bec_mat[lin_idx]),
    is_diagnostic_unit = as.logical(cell_prim_mat[lin_idx])
  )
  us_ord <- order(
    match(unit_species_tbl$SiteUnit, ordered_units),
    .vpro_stratum_rank(unit_species_tbl$StratumGroup),
    ifelse(is.na(unit_species_tbl$Lifeform), 999L, unit_species_tbl$Lifeform),
    -unit_species_tbl$constancy,
    -unit_species_tbl$mean_cover_unit,
    unit_species_tbl$Species
  )
  unit_species_tbl <- unit_species_tbl[us_ord, , drop = FALSE]

  # Assemble $units summary tibble
  richness_vec <- colSums(pnum_mat > 0L)
  n_const_vec <- colSums(pnum_mat == 5L)
  n_diag_vec <- colSums(cell_prim_mat)
  dpot_sum_vec <- vapply(ordered_units, function(u) {
    vpro_round_ace(sum(diag_pot_vec[agg_dt[["SiteUnit"]] == u]), 2L)
  }, numeric(1))

  units_tbl <- tibble::tibble(
    SiteUnit = ordered_units,
    n_plots = unname(n_plots_map[ordered_units]),
    species_richness = as.integer(unname(richness_vec)),
    n_diagnostic = as.integer(unname(n_diag_vec)),
    n_constant = as.integer(unname(n_const_vec)),
    diag_potential_sum = unname(dpot_sum_vec)
  )

  structure(
    list(
      unit_species = unit_species_tbl,
      crosstab = crosstab_tbl,
      units = units_tbl,
      average_type = average_type,
      hierarchy_breaks = scoped$breaks_applied
    ),
    class = "vpro_diagnostics"
  )
}

#' Print a `vpro_diagnostics` synthesis result
#'
#' @param x A `vpro_diagnostics` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_diagnostics <- function(x, ...) {
  n_diag <- sum(!is.na(x$crosstab$Diagnosis) & nzchar(x$crosstab$Diagnosis))
  cli::cli_h3("vpro_diagnostics ({nrow(x$units)} unit{?s}, {nrow(x$crosstab)} species)")
  cli::cli_bullets(c(
    "*" = "Classified plots: {sum(x$units$n_plots)} (average_type: {.val {x$average_type}}, hierarchy_breaks: {x$hierarchy_breaks})",
    "*" = "Diagnostic species (`V7mdlDiagnostic`): {n_diag}/{nrow(x$crosstab)}"
  ))
  invisible(x)
}

#' Summarize a `vpro_diagnostics` synthesis result
#'
#' @param object A `vpro_diagnostics` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return A list containing `units` tibble, `n_species`, `n_diagnostic_v7`,
#'   `n_diagnostic_bec`, and `diagnosis_counts`.
#' @export
summary.vpro_diagnostics <- function(object, ...) {
  d_v7 <- object$crosstab$Diagnosis[!is.na(object$crosstab$Diagnosis) & nzchar(object$crosstab$Diagnosis)]
  d_bec <- object$crosstab$BECDiagnosis[!is.na(object$crosstab$BECDiagnosis) & nzchar(object$crosstab$BECDiagnosis)]
  tab <- table(d_v7)
  diag_counts <- if (length(tab) == 0L) {
    tibble::tibble(Diagnosis = character(), n = integer())
  } else {
    tibble::tibble(Diagnosis = names(tab), n = as.integer(unname(tab)))
  }
  list(
    units = object$units,
    n_species = nrow(object$crosstab),
    n_diagnostic_v7 = length(d_v7),
    n_diagnostic_bec = length(d_bec),
    diagnosis_counts = diag_counts
  )
}

#' Coerce `vpro_diagnostics` to a tibble
#'
#' @param x A `vpro_diagnostics` object.
#' @param table Component tibble to extract: `"unit_species"` (default),
#'   `"crosstab"`, or `"units"`.
#' @param ... Unused; included for S3 method compatibility.
#' @return A tibble.
#' @export
as_tibble.vpro_diagnostics <- function(x, table = c("unit_species", "crosstab", "units"), ...) {
  table <- match.arg(table)
  x[[table]]
}
