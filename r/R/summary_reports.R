# BEC Summary Vegetation, Summary Environment & Workbook Export ---------------

#' Produce BEC vegetation constancy and cover synthesis tables
#'
#' Computes unit-level (or `~` tilde `BreakpointUnit`-rolled-up) BEC vegetation
#' synthesis statistics grouped by `"strata"` (`A`, `B`, `C`, `D`), `"layer"`
#' (`1..10`, `5a..5c`, `A`, `B`), `"lifeform"`, or `"total"`, returning both a
#' tidy long tibble (`n_plots`, `constancy`, `presence_class`, `mean_cover`,
#' `characteristic_cover`, `significance_class`, `prominence`) and a wide
#' species-by-unit synthesis table (`Constancy`, `MeanCover`,
#' `Presence-Signif`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param group_by Vegetation grouping level: `"strata"` (`A`, `B`, `C`, `D`),
#'   `"layer"`, `"lifeform"`, or `"total"`.
#' @param hierarchy_breaks Logical; if `TRUE` and `ws$hierarchy` has `~`
#'   breakpoint nodes, aggregates plots by `BreakpointUnit`.
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE`, a `*_Lump` table
#'   name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` units.
#' @param min_constancy Minimum constancy percentage (`[0, 100]`) required in at
#'   least one unit to retain a species/group row.
#' @param digits Integer decimal places for ACE 15-significant-digit rounding
#'   (default `1L`).
#' @param cover_precedence Precedence when both `TotalA`/`TotalB` and sublayers
#'   (`Cover1..3`/`Cover4..5c`) exist: `"strata_totals"` (default, matching MS
#'   Access summary queries) or `"sublayer_sum"`.
#' @return An S3 object of class `vpro_summary_veg` containing `$long`, `$wide`,
#'   and `$units` tibbles.
#' @export
vpro_summary_veg <- function(
  ws,
  group_by = c("strata", "layer", "lifeform", "total"),
  hierarchy_breaks = FALSE,
  lump = TRUE,
  exclude_modifiers = TRUE,
  min_constancy = 0,
  digits = 1L,
  cover_precedence = c("strata_totals", "sublayer_sum")
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  group_by <- match.arg(group_by)
  cover_precedence <- match.arg(cover_precedence)
  digits <- as.integer(digits)

  scoped <- .vpro_resolve_classified_plots(
    ws,
    exclude_modifiers = exclude_modifiers,
    hierarchy_breaks = hierarchy_breaks
  )
  su_df <- scoped$su
  ordered_units <- scoped$units

  empty_long <- tibble::tibble(
    SiteUnit = character(),
    Group = character(),
    Species = character(),
    ScientificName = character(),
    EnglishName = character(),
    Lifeform = integer(),
    n_plots = integer(),
    n_present = integer(),
    constancy = numeric(),
    presence_class = character(),
    mean_cover = numeric(),
    characteristic_cover = numeric(),
    significance_class = character(),
    prominence = numeric()
  )
  empty_wide <- tibble::tibble(
    Group = character(),
    Species = character(),
    ScientificName = character(),
    EnglishName = character(),
    Lifeform = integer()
  )
  empty_units <- tibble::tibble(SiteUnit = character(), n_plots = integer())

  if (nrow(su_df) == 0L || length(ordered_units) == 0L) {
    return(structure(
      list(
        long = empty_long,
        wide = empty_wide,
        units = empty_units,
        group_by = group_by,
        hierarchy_breaks = scoped$breaks_applied
      ),
      class = "vpro_summary_veg"
    ))
  }

  su_dt <- unique(data.table::as.data.table(su_df), by = c("PlotNumber", "SiteUnit"))
  uc_dt <- su_dt[, list(n_plots = .N), by = "SiteUnit"]
  n_plots_map <- stats::setNames(as.integer(uc_dt[["n_plots"]]), uc_dt[["SiteUnit"]])
  units_tbl <- tibble::tibble(
    SiteUnit = ordered_units,
    n_plots = unname(n_plots_map[ordered_units])
  )

  strata_arg <- switch(
    group_by,
    "strata" = "abcd",
    "layer" = "raw",
    "lifeform" = "lifeform",
    "total" = "total"
  )
  veg_df <- vpro_veg(
    ws,
    scope = "project",
    lump = lump,
    strata = strata_arg,
    combine = "sum",
    exclude_modifiers = FALSE,
    cover_precedence = cover_precedence
  )
  veg_df <- veg_df[veg_df$PlotNumber %in% su_dt[["PlotNumber"]] & !is.na(veg_df$Cover) & veg_df$Cover > 0, , drop = FALSE]

  if (nrow(veg_df) == 0L) {
    w_tbl <- empty_wide
    for (u in ordered_units) {
      w_tbl[[paste0(u, "_Constancy")]] <- numeric()
      w_tbl[[paste0(u, "_MeanCover")]] <- numeric()
      w_tbl[[paste0(u, "_Presence-Signif")]] <- character()
    }
    return(structure(
      list(
        long = empty_long,
        wide = w_tbl,
        units = units_tbl,
        group_by = group_by,
        hierarchy_breaks = scoped$breaks_applied
      ),
      class = "vpro_summary_veg"
    ))
  }

  vdt <- data.table::as.data.table(veg_df)
  if ("SiteUnit" %in% names(vdt)) {
    data.table::set(vdt, j = "SiteUnit", value = NULL)
  }

  grp_vec <- switch(
    group_by,
    "strata" = as.character(vdt[["Strata"]]),
    "layer" = as.character(vdt[["Layer"]]),
    "lifeform" = .vpro_lifeform_catalog(vdt[["Lifeform"]])$lifeform_name,
    "total" = rep("All", nrow(vdt))
  )
  data.table::set(vdt, j = "Group", value = grp_vec)

  # Ensure at most one cover record per (PlotNumber, Group, Species)
  plot_grp_spp <- vdt[,
    list(
      Cover = sum(get("Cover")),
      ScientificName = get("ScientificName")[[1L]],
      EnglishName = get("EnglishName")[[1L]],
      Lifeform = get("Lifeform")[[1L]]
    ),
    by = c("PlotNumber", "Group", "Species")
  ]

  joined <- merge(su_dt, plot_grp_spp, by = "PlotNumber", all = FALSE, allow.cartesian = TRUE)

  agg <- joined[,
    list(
      n_present = .N,
      sum_cover = sum(get("Cover")),
      ScientificName = get("ScientificName")[[1L]],
      EnglishName = get("EnglishName")[[1L]],
      Lifeform = as.integer(get("Lifeform")[[1L]])
    ),
    by = c("SiteUnit", "Group", "Species")
  ]

  data.table::set(agg, j = "n_plots", value = unname(n_plots_map[agg[["SiteUnit"]]]))
  pres_raw <- pmin(agg[["n_present"]] / agg[["n_plots"]], 1.0)
  const_raw <- pres_raw * 100.0
  data.table::set(agg, j = "const_raw", value = const_raw)

  if (min_constancy > 0) {
    mx <- agg[, list(max_c = max(get("const_raw"))), by = c("Group", "Species")]
    keep_keys <- paste0(mx[["Group"]][mx[["max_c"]] >= min_constancy], "\r", mx[["Species"]][mx[["max_c"]] >= min_constancy])
    agg <- agg[paste0(agg[["Group"]], "\r", agg[["Species"]]) %in% keep_keys]
    pres_raw <- pmin(agg[["n_present"]] / agg[["n_plots"]], 1.0)
    const_raw <- pres_raw * 100.0
  }

  mean_cov_raw <- agg[["sum_cover"]] / agg[["n_plots"]]
  char_cov_raw <- agg[["sum_cover"]] / agg[["n_present"]]
  pres_cls <- vpro_presence_class(pres_raw)
  sig_cls <- vpro_significance_class(mean_cov_raw)
  prom_raw <- vpro_prominence_class(mean_cov_raw, pres_raw, return_score = TRUE)

  long_tbl <- tibble::tibble(
    SiteUnit = as.character(agg[["SiteUnit"]]),
    Group = as.character(agg[["Group"]]),
    Species = as.character(agg[["Species"]]),
    ScientificName = as.character(agg[["ScientificName"]]),
    EnglishName = as.character(agg[["EnglishName"]]),
    Lifeform = as.integer(agg[["Lifeform"]]),
    n_plots = as.integer(agg[["n_plots"]]),
    n_present = as.integer(agg[["n_present"]]),
    constancy = vpro_round_ace(const_raw, digits = digits),
    presence_class = pres_cls,
    mean_cover = vpro_round_ace(mean_cov_raw, digits = digits),
    characteristic_cover = vpro_round_ace(char_cov_raw, digits = digits),
    significance_class = sig_cls,
    prominence = vpro_round_ace(prom_raw, digits = digits)
  )

  group_sort_key <- function(g) {
    if (identical(group_by, "strata")) {
      m <- match(g, c("A", "B", "C", "D"))
      ifelse(is.na(m), 99L, m)
    } else if (identical(group_by, "layer")) {
      m <- match(g, c("A", "1", "2", "3", "B", "4", "5", "5a", "5b", "5c", "6", "7", "8", "9", "10"))
      ifelse(is.na(m), 99L, m)
    } else {
      rank(g, ties.method = "min")
    }
  }

  ord_long <- order(
    match(long_tbl$SiteUnit, ordered_units),
    group_sort_key(long_tbl$Group),
    ifelse(is.na(long_tbl$Lifeform), 999L, long_tbl$Lifeform),
    -long_tbl$constancy,
    -long_tbl$mean_cover,
    long_tbl$Species
  )
  long_tbl <- long_tbl[ord_long, , drop = FALSE]

  # Build wide species x unit synthesis table
  row_key <- paste0(long_tbl$Group, "\r", long_tbl$Species)
  uniq_ix <- which(!duplicated(row_key))
  base_rows <- long_tbl[uniq_ix, c("Group", "Species", "ScientificName", "EnglishName", "Lifeform"), drop = FALSE]
  ord_wide <- order(
    group_sort_key(base_rows$Group),
    ifelse(is.na(base_rows$Lifeform), 999L, base_rows$Lifeform),
    base_rows$Species
  )
  base_rows <- base_rows[ord_wide, , drop = FALSE]
  wide_keys <- paste0(base_rows$Group, "\r", base_rows$Species)

  n_w <- nrow(base_rows)
  n_u <- length(ordered_units)
  c_mat <- matrix(NA_real_, nrow = n_w, ncol = n_u)
  m_mat <- matrix(NA_real_, nrow = n_w, ncol = n_u)
  ps_mat <- matrix(NA_character_, nrow = n_w, ncol = n_u)

  r_m <- match(row_key, wide_keys)
  u_m <- match(long_tbl$SiteUnit, ordered_units)
  lin <- cbind(r_m, u_m)
  c_mat[lin] <- long_tbl$constancy
  m_mat[lin] <- long_tbl$mean_cover
  ps_mat[lin] <- paste0(long_tbl$presence_class, "-", long_tbl$significance_class)

  wide_list <- as.list(base_rows)
  for (u_j in seq_len(n_u)) {
    u <- ordered_units[[u_j]]
    wide_list[[paste0(u, "_Constancy")]] <- c_mat[, u_j]
    wide_list[[paste0(u, "_MeanCover")]] <- m_mat[, u_j]
    wide_list[[paste0(u, "_Presence-Signif")]] <- ps_mat[, u_j]
  }
  wide_tbl <- tibble::as_tibble(wide_list)

  structure(
    list(
      long = long_tbl,
      wide = wide_tbl,
      units = units_tbl,
      group_by = group_by,
      hierarchy_breaks = scoped$breaks_applied
    ),
    class = "vpro_summary_veg"
  )
}

#' Print a `vpro_summary_veg` synthesis table
#'
#' @param x A `vpro_summary_veg` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_summary_veg <- function(x, ...) {
  cli::cli_h3("vpro_summary_veg ({nrow(x$units)} unit{?s}, group_by = {.val {x$group_by}})")
  cli::cli_bullets(c(
    "*" = "Long unit-species rows: {nrow(x$long)} | Wide taxa rows: {nrow(x$wide)}",
    "*" = "Hierarchy `~` breakpoints applied: {x$hierarchy_breaks}"
  ))
  invisible(x)
}

#' Coerce `vpro_summary_veg` to a tibble
#'
#' @param x A `vpro_summary_veg` object.
#' @param format Either `"long"` (default) or `"wide"`.
#' @param ... Unused; included for S3 method compatibility.
#' @return A tibble of vegetation synthesis values.
#' @export
as_tibble.vpro_summary_veg <- function(x, format = c("long", "wide"), ...) {
  format <- match.arg(format)
  x[[format]]
}

.vpro_modal_chr <- function(x) {
  vals <- trimws(as.character(x[!is.na(x)]))
  vals <- vals[nzchar(vals)]
  if (length(vals) == 0L) {
    return(NA_character_)
  }
  tab <- table(vals)
  names(tab)[order(-as.integer(tab), names(tab))][[1L]]
}

.vpro_aspect_sector <- function(aspect, slope = NULL) {
  asp <- suppressWarnings(as.numeric(aspect))
  slp <- if (!is.null(slope)) suppressWarnings(as.numeric(slope)) else rep(NA_real_, length(asp))
  sectors <- rep(NA_character_, length(asp))
  is_level <- (!is.na(asp) & asp == 999) | (!is.na(slp) & slp == 0)
  sectors[is_level] <- "Level"
  valid <- !is_level & !is.na(asp) & is.finite(asp) & asp >= 0 & asp <= 360
  if (any(valid)) {
    labels <- c("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    norm <- (asp[valid] + 360) %% 360
    idx <- (as.integer(floor((norm + 22.5) / 45.0)) %% 8L) + 1L
    sectors[valid] <- labels[idx]
  }
  sectors
}

.vpro_parse_smr <- function(x) {
  s <- trimws(ifelse(is.na(x), "", as.character(x)))
  out <- rep(NA_integer_, length(s))
  ok <- grepl("^[0-8]($|[^0-9])", s)
  out[ok] <- as.integer(substr(s[ok], 1L, 1L))
  out
}

.vpro_parse_snr <- function(x) {
  s <- toupper(trimws(ifelse(is.na(x), "", as.character(x))))
  out <- rep(NA_character_, length(s))
  ok <- grepl("^[A-F]($|[^A-Z])", s)
  out[ok] <- substr(s[ok], 1L, 1L)
  out
}

#' Produce BEC site and environment unit summaries
#'
#' Summarizes plot site, topographic, edatopic (`MoistureRegime` /
#' `NutrientRegime`), biogeoclimatic (`Zone`, `SubZone`, `SiteSeries`), and
#' strata cover attributes per `SiteUnit` (or rolled up to `~` tilde
#' `BreakpointUnit`s when `hierarchy_breaks = TRUE`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param hierarchy_breaks Logical; if `TRUE` and `ws$hierarchy` contains `~`
#'   breakpoint nodes, rolls plots up to their `BreakpointUnit`.
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` units.
#' @return A tibble of class `c("vpro_summary_env", "tbl_df", "tbl", "data.frame")`
#'   with one row per unit.
#' @export
vpro_summary_env <- function(
  ws,
  hierarchy_breaks = FALSE,
  exclude_modifiers = TRUE
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  scoped <- .vpro_resolve_classified_plots(
    ws,
    exclude_modifiers = exclude_modifiers,
    hierarchy_breaks = hierarchy_breaks
  )
  env_df <- scoped$env
  ordered_units <- scoped$units

  empty_tbl <- tibble::tibble(
    SiteUnit = character(),
    n_plots = integer(),
    Zone = character(),
    SubZone = character(),
    SiteSeries = character(),
    elevation_mean = numeric(),
    elevation_min = numeric(),
    elevation_max = numeric(),
    slope_mean = numeric(),
    slope_min = numeric(),
    slope_max = numeric(),
    aspect_modal = character(),
    smr_modal = character(),
    smr_range = character(),
    snr_modal = character(),
    snr_range = character(),
    StrataCoverTree = numeric(),
    StrataCoverShrub = numeric(),
    StrataCoverHerb = numeric(),
    StrataCoverMoss = numeric()
  )
  if (nrow(env_df) == 0L || length(ordered_units) == 0L) {
    class(empty_tbl) <- unique(c("vpro_summary_env", class(empty_tbl)))
    return(empty_tbl)
  }

  num_stats <- function(v, digits = 1L) {
    vn <- suppressWarnings(as.numeric(v))
    vn <- vn[!is.na(vn) & is.finite(vn)]
    if (length(vn) == 0L) {
      return(list(mean = NA_real_, min = NA_real_, max = NA_real_))
    }
    list(
      mean = vpro_round_ace(mean(vn), digits = digits),
      min = vpro_round_ace(min(vn), digits = digits),
      max = vpro_round_ace(max(vn), digits = digits)
    )
  }

  mean_col <- function(sub_df, col, digits = 1L) {
    if (!(col %in% names(sub_df))) {
      return(NA_real_)
    }
    vn <- suppressWarnings(as.numeric(sub_df[[col]]))
    vn <- vn[!is.na(vn) & is.finite(vn)]
    if (length(vn) == 0L) NA_real_ else vpro_round_ace(mean(vn), digits = digits)
  }

  pull_col <- function(sub_df, col) {
    if (col %in% names(sub_df)) sub_df[[col]] else rep(NA, nrow(sub_df))
  }

  rows <- lapply(ordered_units, function(u) {
    sub <- env_df[!is.na(env_df$SiteUnit) & env_df$SiteUnit == u, , drop = FALSE]
    el <- num_stats(pull_col(sub, "Elevation"), digits = 1L)
    sl <- num_stats(pull_col(sub, "SlopeGradient"), digits = 1L)
    asp_sec <- .vpro_aspect_sector(pull_col(sub, "Aspect"), pull_col(sub, "SlopeGradient"))

    smr_int <- .vpro_parse_smr(pull_col(sub, "MoistureRegime"))
    smr_ok <- smr_int[!is.na(smr_int)]
    smr_mod <- if (length(smr_ok) > 0L) {
      .vpro_modal_chr(as.character(smr_ok))
    } else {
      .vpro_modal_chr(pull_col(sub, "MoistureRegime"))
    }
    smr_rng <- if (length(smr_ok) == 0L) {
      NA_character_
    } else if (min(smr_ok) == max(smr_ok)) {
      as.character(min(smr_ok))
    } else {
      paste0(min(smr_ok), "-", max(smr_ok))
    }

    snr_chr <- .vpro_parse_snr(pull_col(sub, "NutrientRegime"))
    snr_ok <- snr_chr[!is.na(snr_chr)]
    snr_mod <- if (length(snr_ok) > 0L) {
      .vpro_modal_chr(snr_ok)
    } else {
      .vpro_modal_chr(pull_col(sub, "NutrientRegime"))
    }
    snr_rng <- if (length(snr_ok) == 0L) {
      NA_character_
    } else {
      snr_sorted <- sort(unique(snr_ok))
      if (length(snr_sorted) == 1L) snr_sorted[[1L]] else paste0(snr_sorted[[1L]], "-", snr_sorted[[length(snr_sorted)]])
    }

    tibble::tibble(
      SiteUnit = u,
      n_plots = as.integer(nrow(sub)),
      Zone = .vpro_modal_chr(pull_col(sub, "Zone")),
      SubZone = .vpro_modal_chr(pull_col(sub, "SubZone")),
      SiteSeries = .vpro_modal_chr(pull_col(sub, "SiteSeries")),
      elevation_mean = el$mean,
      elevation_min = el$min,
      elevation_max = el$max,
      slope_mean = sl$mean,
      slope_min = sl$min,
      slope_max = sl$max,
      aspect_modal = .vpro_modal_chr(asp_sec),
      smr_modal = smr_mod,
      smr_range = smr_rng,
      snr_modal = snr_mod,
      snr_range = snr_rng,
      StrataCoverTree = mean_col(sub, "StrataCoverTree", digits = 1L),
      StrataCoverShrub = mean_col(sub, "StrataCoverShrub", digits = 1L),
      StrataCoverHerb = mean_col(sub, "StrataCoverHerb", digits = 1L),
      StrataCoverMoss = mean_col(sub, "StrataCoverMoss", digits = 1L)
    )
  })

  res <- do.call(rbind, rows)
  class(res) <- unique(c("vpro_summary_env", class(res)))
  res
}

#' Print a `vpro_summary_env` tibble
#'
#' @param x A `vpro_summary_env` object.
#' @param ... Passed to the underlying tibble `print()` method.
#' @return `x`, invisibly.
#' @export
print.vpro_summary_env <- function(x, ...) {
  NextMethod()
}

#' Coerce `vpro_summary_env` to a plain tibble
#'
#' @param x A `vpro_summary_env` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return A plain `tbl_df` tibble.
#' @export
as_tibble.vpro_summary_env <- function(x, ...) {
  cls <- setdiff(class(x), "vpro_summary_env")
  class(x) <- cls
  tibble::as_tibble(x)
}

.vpro_sanitize_sheet_names <- function(nms) {
  clean <- gsub("[:\\\\/?*\\[\\]]", "_", trimws(as.character(nms)))
  clean[!nzchar(clean) | is.na(clean)] <- "Sheet"
  out <- character(length(clean))
  used_low <- character()
  for (i in seq_along(clean)) {
    cand <- substr(clean[[i]], 1L, 31L)
    k <- 1L
    while (tolower(cand) %in% used_low) {
      k <- k + 1L
      suffix <- paste0("_", k)
      cand <- paste0(substr(clean[[i]], 1L, 31L - nchar(suffix)), suffix)
    }
    out[[i]] <- cand
    used_low <- c(used_low, tolower(cand))
  }
  out
}

#' Export BEC synthesis tables to a multi-sheet `.xlsx` workbook
#'
#' Writes a [vpro_diagnostics()], [vpro_pairwise()], [vpro_outliers()],
#' [vpro_profile()], [vpro_summary_veg()], [vpro_summary_env()], named
#' list of data frames, or single data frame to an `.xlsx` workbook via
#' `writexl::write_xlsx()`.
#'
#' @param x A BEC synthesis result object, data frame, or named list of data
#'   frames.
#' @param path Destination `.xlsx` file path.
#' @param overwrite Logical; if `TRUE` (default), replaces an existing `.xlsx`
#'   at `path`. If `FALSE` and `path` exists, aborts with an error.
#' @return Normalized path (`winslash = "/"`) to the written `.xlsx` file,
#'   invisibly.
#' @export
vpro_export_xlsx <- function(x, path, overwrite = TRUE) {
  rlang::check_installed("writexl", reason = "to export BEC synthesis workbooks to `.xlsx`.")
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    rlang::abort("`path` must be a single non-empty `.xlsx` file path.")
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    rlang::abort("`overwrite` must be TRUE or FALSE.")
  }
  out_path <- vpro_abs_path(trimws(path))
  if (file.exists(out_path) && !isTRUE(overwrite)) {
    rlang::abort(paste0("Workbook already exists and `overwrite = FALSE`: ", out_path))
  }

  sheets <- if (inherits(x, "vpro_diagnostics")) {
    list(
      Crosstab = as.data.frame(x$crosstab),
      Unit_Species = as.data.frame(x$unit_species),
      Units = as.data.frame(x$units)
    )
  } else if (inherits(x, "vpro_pairwise")) {
    sim_m <- x$similarity_matrix
    sim_df <- if (nrow(sim_m) == 0L) {
      data.frame(SiteUnit = character(), stringsAsFactors = FALSE)
    } else {
      cbind(
        data.frame(SiteUnit = rownames(sim_m), stringsAsFactors = FALSE),
        as.data.frame(sim_m, check.names = FALSE, stringsAsFactors = FALSE)
      )
    }
    rownames(sim_df) <- NULL
    list(
      Pairs = as.data.frame(x$pairs),
      Similarity_Matrix = sim_df,
      Species_Diffs = as.data.frame(x$species_diffs)
    )
  } else if (inherits(x, "vpro_outliers")) {
    list(
      Outlier_Queue = as.data.frame(x$queue),
      Flagged_Outliers = as.data.frame(x$outliers)
    )
  } else if (inherits(x, "vpro_profile_result")) {
    list(
      Retained_Plots = as.data.frame(x$env),
      Profile_Steps = as.data.frame(x$steps)
    )
  } else if (inherits(x, "vpro_summary_veg")) {
    list(
      Veg_Wide = as.data.frame(x$wide),
      Veg_Long = as.data.frame(x$long),
      Units = as.data.frame(x$units)
    )
  } else if (inherits(x, "vpro_summary_env")) {
    list(Env_Summary = as.data.frame(as_tibble.vpro_summary_env(x)))
  } else if (is.data.frame(x)) {
    list(Sheet1 = as.data.frame(x))
  } else if (is.list(x) && length(x) > 0L && all(vapply(x, is.data.frame, logical(1)))) {
    nms <- names(x)
    if (is.null(nms)) {
      nms <- paste0("Sheet", seq_along(x))
    } else {
      blank <- is.na(nms) | !nzchar(trimws(nms))
      nms[blank] <- paste0("Sheet", which(blank))
    }
    stats::setNames(lapply(x, as.data.frame), nms)
  } else {
    rlang::abort("`x` must be a vpro synthesis object, data.frame, or non-empty list of data.frames.")
  }

  names(sheets) <- .vpro_sanitize_sheet_names(names(sheets))
  parent_dir <- dirname(out_path)
  if (!dir.exists(parent_dir)) {
    dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  }
  writexl::write_xlsx(sheets, path = out_path)
  invisible(normalizePath(out_path, winslash = "/", mustWork = TRUE))
}
