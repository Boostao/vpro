# Dual 9x5 BEC Edatopic Grids (`rSMR x rSNR` & `aSMR x rSNR`) & Visualization --

.vpro_snr_levels <- c("A", "B", "C", "D", "E")

vpro_effective_site_unit <- function(site_unit, bgc = NULL, site_series = NULL) {
  su <- ifelse(is.na(site_unit), "", trimws(as.character(site_unit)))
  if (!is.null(bgc)) {
    bgc_c <- ifelse(is.na(bgc), "", trimws(as.character(bgc)))
    ss_c <- if (!is.null(site_series)) ifelse(is.na(site_series), "", trimws(as.character(site_series))) else rep("", length(su))
    miss <- !nzchar(su)
    su[miss & nzchar(bgc_c) & nzchar(ss_c)] <- paste0(bgc_c[miss & nzchar(bgc_c) & nzchar(ss_c)], "/", ss_c[miss & nzchar(bgc_c) & nzchar(ss_c)])
    miss2 <- !nzchar(su)
    su[miss2 & nzchar(bgc_c)] <- bgc_c[miss2 & nzchar(bgc_c)]
  }
  su[!nzchar(su)] <- "Unassigned"
  su
}

vpro_build_edatopic_tables <- function(plot_grid_df, veg_df, min_constancy_pct) {
  empty_cells <- tibble::tibble(
    grid_type = character(),
    SiteUnit = character(),
    SMR = integer(),
    SNR = character(),
    SNR_num = integer(),
    Edatope = character(),
    n_plots = integer(),
    unit_total_plots = integer(),
    unit_prop = numeric(),
    cell_total_plots = integer(),
    aSMR_mean = numeric(),
    is_modal = logical(),
    is_primary = logical()
  )
  empty_bboxes <- tibble::tibble(
    grid_type = character(),
    SiteUnit = character(),
    n_plots = integer(),
    smr_min = integer(),
    smr_max = integer(),
    smr_modal = integer(),
    snr_min = character(),
    snr_max = character(),
    snr_modal = character(),
    snr_min_num = integer(),
    snr_max_num = integer(),
    snr_modal_num = integer(),
    smr_raw_min = integer(),
    smr_raw_max = integer(),
    snr_raw_min = character(),
    snr_raw_max = character()
  )
  empty_hulls <- empty_bboxes
  empty_hulls$hull <- list()
  empty_species <- tibble::tibble(
    grid_type = character(),
    SMR = integer(),
    SNR = character(),
    SNR_num = integer(),
    Edatope = character(),
    Species = character(),
    ScientificName = character(),
    EnglishName = character(),
    Lifeform = integer(),
    n_plots = integer(),
    cell_plots = integer(),
    constancy = numeric(),
    mean_cover = numeric(),
    mean_cover_all = numeric(),
    prominence_tier = integer(),
    order_score = numeric()
  )

  if (nrow(plot_grid_df) == 0L) {
    return(list(
      cells = empty_cells,
      unit_bboxes = empty_bboxes,
      unit_hulls = empty_hulls,
      species = empty_species
    ))
  }

  # Deduplicate (grid_type, PlotNumber, SiteUnit) so plot counts per cell are exact
  pg_dt <- data.table::as.data.table(plot_grid_df)
  pg_dt <- unique(pg_dt, by = c("grid_type", "PlotNumber", "SiteUnit"))

  # Distinct plots per (grid_type, SMR, SNR) cell across all units
  cell_plot_dt <- unique(pg_dt[, c("grid_type", "SMR", "SNR", "PlotNumber"), with = FALSE])
  cell_totals <- cell_plot_dt[, list(cell_total_plots = .N), by = c("grid_type", "SMR", "SNR")]

  # Plot counts per (grid_type, SiteUnit, SMR, SNR)
  cells_dt <- pg_dt[,
    list(
      n_plots = .N,
      aSMR_mean = if (all(is.na(get("SMR_exact")))) NA_real_ else round(mean(get("SMR_exact"), na.rm = TRUE), 2L)
    ),
    by = c("grid_type", "SiteUnit", "SMR", "SNR")
  ]

  unit_totals <- cells_dt[, list(unit_total_plots = sum(get("n_plots"))), by = c("grid_type", "SiteUnit")]
  cells_dt <- merge(cells_dt, unit_totals, by = c("grid_type", "SiteUnit"), all.x = TRUE, sort = FALSE)
  cells_dt <- merge(cells_dt, cell_totals, by = c("grid_type", "SMR", "SNR"), all.x = TRUE, sort = FALSE)

  data.table::set(cells_dt, j = "SNR_num", value = as.integer(match(cells_dt[["SNR"]], .vpro_snr_levels)))
  data.table::set(cells_dt, j = "Edatope", value = paste0(cells_dt[["SMR"]], cells_dt[["SNR"]]))
  data.table::set(cells_dt, j = "unit_prop", value = round(cells_dt[["n_plots"]] / cells_dt[["unit_total_plots"]], 4L))

  # Order deterministically so modal ties break consistently toward central/mesic order
  data.table::setorderv(cells_dt, c("grid_type", "SiteUnit", "SMR", "SNR_num"))
  is_modal_vec <- logical(nrow(cells_dt))
  grp_key <- paste0(cells_dt[["grid_type"]], "||", cells_dt[["SiteUnit"]])
  for (gk in unique(grp_key)) {
    ix <- which(grp_key == gk)
    mx <- max(cells_dt[["n_plots"]][ix])
    is_modal_vec[ix[which(cells_dt[["n_plots"]][ix] == mx)[[1L]]]] <- TRUE
  }
  data.table::set(cells_dt, j = "is_modal", value = is_modal_vec)
  data.table::set(cells_dt, j = "is_primary", value = (cells_dt[["unit_prop"]] >= 0.20) | is_modal_vec)

  cell_cols <- c(
    "grid_type",
    "SiteUnit",
    "SMR",
    "SNR",
    "SNR_num",
    "Edatope",
    "n_plots",
    "unit_total_plots",
    "unit_prop",
    "cell_total_plots",
    "aSMR_mean",
    "is_modal",
    "is_primary"
  )
  cells_tbl <- tibble::as_tibble(cells_dt[, cell_cols, with = FALSE])

  # Build unit_bboxes & unit_hulls per (grid_type, SiteUnit)
  uniq_groups <- unique(grp_key)
  bbox_rows <- vector("list", length(uniq_groups))
  hull_list <- vector("list", length(uniq_groups))
  for (g_i in seq_along(uniq_groups)) {
    gk <- uniq_groups[[g_i]]
    sub_c <- cells_tbl[grp_key == gk, , drop = FALSE]
    prim_c <- sub_c[sub_c$is_primary, , drop = FALSE]
    if (nrow(prim_c) == 0L) {
      prim_c <- sub_c
    }
    mod_row <- sub_c[sub_c$is_modal, , drop = FALSE][1L, , drop = FALSE]

    snr_min_n <- min(prim_c$SNR_num)
    snr_max_n <- max(prim_c$SNR_num)
    snr_raw_min_n <- min(sub_c$SNR_num)
    snr_raw_max_n <- max(sub_c$SNR_num)

    bbox_rows[[g_i]] <- tibble::tibble(
      grid_type = sub_c$grid_type[[1L]],
      SiteUnit = sub_c$SiteUnit[[1L]],
      n_plots = as.integer(sub_c$unit_total_plots[[1L]]),
      smr_min = as.integer(min(prim_c$SMR)),
      smr_max = as.integer(max(prim_c$SMR)),
      smr_modal = as.integer(mod_row$SMR[[1L]]),
      snr_min = .vpro_snr_levels[[snr_min_n]],
      snr_max = .vpro_snr_levels[[snr_max_n]],
      snr_modal = mod_row$SNR[[1L]],
      snr_min_num = as.integer(snr_min_n),
      snr_max_num = as.integer(snr_max_n),
      snr_modal_num = as.integer(mod_row$SNR_num[[1L]]),
      smr_raw_min = as.integer(min(sub_c$SMR)),
      smr_raw_max = as.integer(max(sub_c$SMR)),
      snr_raw_min = .vpro_snr_levels[[snr_raw_min_n]],
      snr_raw_max = .vpro_snr_levels[[snr_raw_max_n]]
    )

    pts_xy <- unique(prim_c[, c("SNR_num", "SMR", "SNR"), drop = FALSE])
    if (nrow(pts_xy) >= 3L) {
      ch_ix <- grDevices::chull(pts_xy$SNR_num, pts_xy$SMR)
      pts_xy <- pts_xy[ch_ix, , drop = FALSE]
    }
    hull_list[[g_i]] <- tibble::as_tibble(pts_xy)
  }
  bboxes_tbl <- do.call(rbind, bbox_rows)
  hulls_tbl <- bboxes_tbl
  hulls_tbl$hull <- hull_list

  # Species prominence per (grid_type, SMR, SNR, Species) matching 2_0_EdatopicGrid_SpeciesDistribution.R
  if (nrow(veg_df) == 0L || nrow(cell_plot_dt) == 0L) {
    return(list(
      cells = cells_tbl,
      unit_bboxes = bboxes_tbl,
      unit_hulls = hulls_tbl,
      species = empty_species
    ))
  }

  veg_dt <- data.table::as.data.table(veg_df[, c("PlotNumber", "Species", "Cover", "ScientificName", "EnglishName", "Lifeform"), drop = FALSE])
  veg_dt <- veg_dt[!is.na(veg_dt[["Cover"]]) & veg_dt[["Cover"]] > 0]
  # Deduplicate (PlotNumber, Species) if multiple site units mapped the same plot
  if (anyDuplicated(veg_dt, by = c("PlotNumber", "Species")) > 0L) {
    veg_dt <- veg_dt[,
      list(
        Cover = max(get("Cover"), na.rm = TRUE),
        ScientificName = get("ScientificName")[[1L]],
        EnglishName = get("EnglishName")[[1L]],
        Lifeform = get("Lifeform")[[1L]]
      ),
      by = c("PlotNumber", "Species")
    ]
  }

  joined_veg <- merge(cell_plot_dt, veg_dt, by = "PlotNumber", all = FALSE, allow.cartesian = TRUE)
  if (nrow(joined_veg) == 0L) {
    return(list(
      cells = cells_tbl,
      unit_bboxes = bboxes_tbl,
      unit_hulls = hulls_tbl,
      species = empty_species
    ))
  }

  spp_agg <- joined_veg[,
    list(
      n_plots = .N,
      sum_cover = sum(get("Cover"), na.rm = TRUE),
      mean_cover = mean(get("Cover"), na.rm = TRUE),
      ScientificName = get("ScientificName")[[1L]],
      EnglishName = get("EnglishName")[[1L]],
      Lifeform = as.integer(get("Lifeform")[[1L]])
    ),
    by = c("grid_type", "SMR", "SNR", "Species")
  ]

  spp_agg <- merge(spp_agg, cell_totals, by = c("grid_type", "SMR", "SNR"), all.x = TRUE, sort = FALSE)
  data.table::set(spp_agg, j = "cell_plots", value = as.integer(spp_agg[["cell_total_plots"]]))
  data.table::set(spp_agg, j = "constancy", value = round((spp_agg[["n_plots"]] / spp_agg[["cell_plots"]]) * 100.0, 2L))
  spp_agg <- spp_agg[spp_agg[["constancy"]] >= min_constancy_pct]

  if (nrow(spp_agg) == 0L) {
    return(list(
      cells = cells_tbl,
      unit_bboxes = bboxes_tbl,
      unit_hulls = hulls_tbl,
      species = empty_species
    ))
  }

  mc_v <- spp_agg[["mean_cover"]]
  co_v <- spp_agg[["constancy"]]
  tier_v <- ifelse(
    mc_v > 20.0 & co_v > 50.0,
    1L,
    ifelse(mc_v > 10.0 & co_v > 25.0, 2L, 3L)
  )
  data.table::set(spp_agg, j = "SNR_num", value = as.integer(match(spp_agg[["SNR"]], .vpro_snr_levels)))
  data.table::set(spp_agg, j = "Edatope", value = paste0(spp_agg[["SMR"]], spp_agg[["SNR"]]))
  data.table::set(spp_agg, j = "mean_cover", value = round(mc_v, 2L))
  data.table::set(spp_agg, j = "mean_cover_all", value = round(spp_agg[["sum_cover"]] / spp_agg[["cell_plots"]], 2L))
  data.table::set(spp_agg, j = "prominence_tier", value = as.integer(tier_v))
  data.table::set(spp_agg, j = "order_score", value = round(mc_v * co_v, 2L))

  data.table::setorderv(
    spp_agg,
    c("grid_type", "SMR", "SNR_num", "prominence_tier", "order_score", "Species"),
    c(1L, 1L, 1L, 1L, -1L, 1L)
  )
  spp_cols <- c(
    "grid_type",
    "SMR",
    "SNR",
    "SNR_num",
    "Edatope",
    "Species",
    "ScientificName",
    "EnglishName",
    "Lifeform",
    "n_plots",
    "cell_plots",
    "constancy",
    "mean_cover",
    "mean_cover_all",
    "prominence_tier",
    "order_score"
  )
  spp_tbl <- tibble::as_tibble(spp_agg[, spp_cols, with = FALSE])

  list(
    cells = cells_tbl,
    unit_bboxes = bboxes_tbl,
    unit_hulls = hulls_tbl,
    species = spp_tbl
  )
}

#' Compute dual Relative (`rSMR x rSNR`) and Actual (`aSMR x rSNR`) 9x5 BEC edatopic grids
#'
#' Synthesizes plot counts, site-unit proportions, modal/primary edatopic unit
#' bounding boxes & convex hulls, and three-tier species prominence distributions
#' (`EdatopicGrid_Spp_Distribution`) across the standard `9 x 5` BEC edatopic
#' grid (`SMR` `0..8` rows x `SNR` `A..E` columns).
#'
#' @param ws A `vpro_workspace` handle.
#' @param mode Grid synthesis mode: `"dual"` (both Relative and Actual grids),
#'   `"relative"` (`rSMR x rSNR` only), or `"actual"` (`aSMR x rSNR` only).
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`) used
#'   when `mode` includes `"actual"`.
#' @param min_constancy Minimum cell constancy percentage (`0..100`, default
#'   `20`; proportions in `(0, 1)` are automatically scaled to percentages) for
#'   retaining species in `$species`.
#' @param lump Passed to [vpro_veg()] (`TRUE`, `FALSE`, lump table name, or
#'   two-column `data.frame`).
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` modifier site units.
#' @param force_offline Logical; if `TRUE`, uses the offline BGC lapse-rate
#'   model when computing `aSMR`.
#' @return An S3 object of class `vpro_edatope` containing `$cells`,
#'   `$unit_bboxes`, `$unit_hulls`, `$species`, `$plots`, `$mode`, `$ref_period`,
#'   and `$project`.
#' @export
vpro_edatopic_grid <- function(
  ws,
  mode = c("dual", "relative", "actual"),
  ref_period = "1961_1990",
  min_constancy = 20,
  lump = TRUE,
  exclude_modifiers = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(ws)
  mode <- match.arg(mode)
  ref_period <- vpro_normalize_ref_period(ref_period)

  if (!is.numeric(min_constancy) || length(min_constancy) != 1L || is.na(min_constancy) || min_constancy < 0 || min_constancy > 100) {
    rlang::abort("`min_constancy` must be a single numeric percentage in `[0, 100]`.")
  }
  min_const_pct <- if (min_constancy > 0 && min_constancy < 1) min_constancy * 100.0 else as.double(min_constancy)

  if (identical(mode, "relative")) {
    env_df <- vpro_env(ws, scope = "su", include_admin = TRUE, exclude_modifiers = exclude_modifiers)
    zone_c <- if ("Zone" %in% names(env_df)) env_df$Zone else rep(NA_character_, nrow(env_df))
    subz_c <- if ("SubZone" %in% names(env_df)) env_df$SubZone else rep(NA_character_, nrow(env_df))
    bgc_c <- gsub("[[:space:]]+", "", paste0(ifelse(is.na(zone_c), "", zone_c), ifelse(is.na(subz_c), "", subz_c)))
    ss_c <- if ("SiteSeries" %in% names(env_df)) env_df$SiteSeries else rep(NA_character_, nrow(env_df))
    plots_df <- tibble::tibble(
      PlotNumber = as.character(env_df$PlotNumber),
      SiteUnit = vpro_effective_site_unit(env_df$SiteUnit, bgc_c, ss_c),
      BGC = ifelse(nzchar(bgc_c), bgc_c, NA_character_),
      rSMR = vpro_parse_rsmr_digit(env_df$MoistureRegime),
      rSNR = vpro_normalize_rsnr(env_df$NutrientRegime),
      aSMR = rep(NA_real_, nrow(env_df)),
      CMD = rep(NA_real_, nrow(env_df)),
      CMD_site = rep(NA_real_, nrow(env_df))
    )
  } else {
    asmr_df <- vpro_asmr(
      ws,
      scope = "su",
      ref_period = ref_period,
      cache = !identical(ws$source, "sample"),
      force_offline = force_offline
    )
    if (isTRUE(exclude_modifiers) && nrow(asmr_df) > 0L) {
      asmr_df <- asmr_df[!vpro_is_modifier_unit(asmr_df$SiteUnit), , drop = FALSE]
    }
    ss_asmr <- if ("SiteSeries" %in% names(asmr_df)) asmr_df$SiteSeries else rep(NA_character_, nrow(asmr_df))
    plots_df <- tibble::tibble(
      PlotNumber = as.character(asmr_df$PlotNumber),
      SiteUnit = vpro_effective_site_unit(asmr_df$SiteUnit, asmr_df$BGC, ss_asmr),
      BGC = asmr_df$BGC,
      rSMR = asmr_df$rSMR,
      rSNR = asmr_df$rSNR,
      aSMR = asmr_df$aSMR,
      CMD = asmr_df$CMD,
      CMD_site = asmr_df$CMD_site
    )
  }

  grid_parts <- list()
  if (mode %in% c("dual", "relative") && nrow(plots_df) > 0L) {
    ok_rel <- !is.na(plots_df$rSMR) & plots_df$rSMR >= 0L & plots_df$rSMR <= 8L & !is.na(plots_df$rSNR) & plots_df$rSNR %in% .vpro_snr_levels
    if (any(ok_rel)) {
      grid_parts[[length(grid_parts) + 1L]] <- data.frame(
        grid_type = rep("relative", sum(ok_rel)),
        PlotNumber = plots_df$PlotNumber[ok_rel],
        SiteUnit = plots_df$SiteUnit[ok_rel],
        SMR = as.integer(plots_df$rSMR[ok_rel]),
        SMR_exact = as.double(plots_df$rSMR[ok_rel]),
        SNR = plots_df$rSNR[ok_rel],
        stringsAsFactors = FALSE
      )
    }
  }
  if (mode %in% c("dual", "actual") && nrow(plots_df) > 0L) {
    ok_act <- !is.na(plots_df$aSMR) & is.finite(plots_df$aSMR) & !is.na(plots_df$rSNR) & plots_df$rSNR %in% .vpro_snr_levels
    if (any(ok_act)) {
      asmr_int <- pmin(8L, pmax(0L, as.integer(vpro_go_round(plots_df$aSMR[ok_act]))))
      asmr_half <- pmin(8.0, pmax(0.0, vpro_go_round(plots_df$aSMR[ok_act] * 2.0) / 2.0))
      grid_parts[[length(grid_parts) + 1L]] <- data.frame(
        grid_type = rep("actual", sum(ok_act)),
        PlotNumber = plots_df$PlotNumber[ok_act],
        SiteUnit = plots_df$SiteUnit[ok_act],
        SMR = asmr_int,
        SMR_exact = asmr_half,
        SNR = plots_df$rSNR[ok_act],
        stringsAsFactors = FALSE
      )
    }
  }

  plot_grid_df <- if (length(grid_parts) > 0L) {
    do.call(rbind, grid_parts)
  } else {
    data.frame(
      grid_type = character(),
      PlotNumber = character(),
      SiteUnit = character(),
      SMR = integer(),
      SMR_exact = numeric(),
      SNR = character(),
      stringsAsFactors = FALSE
    )
  }

  veg_df <- vpro_veg(
    ws,
    scope = "su",
    lump = lump,
    strata = "total",
    exclude_modifiers = exclude_modifiers
  )

  built <- vpro_build_edatopic_tables(
    plot_grid_df = plot_grid_df,
    veg_df = veg_df,
    min_constancy_pct = min_const_pct
  )

  structure(
    list(
      project = ws$project,
      su = ws$su,
      mode = mode,
      ref_period = ref_period,
      min_constancy = min_const_pct,
      cells = built$cells,
      unit_bboxes = built$unit_bboxes,
      unit_hulls = built$unit_hulls,
      species = built$species,
      plots = plots_df
    ),
    class = "vpro_edatope"
  )
}

#' @export
print.vpro_edatope <- function(x, ...) {
  n_rel <- sum(x$cells$grid_type == "relative")
  n_act <- sum(x$cells$grid_type == "actual")
  n_units <- length(unique(x$unit_bboxes$SiteUnit))
  n_spp <- length(unique(x$species$Species))
  cli::cli_h3(sprintf("vpro_edatope: %s (mode = %s, ref_period = %s)", x$project, x$mode, x$ref_period))
  cli::cli_bullets(c(
    "*" = sprintf("Populated unit-cells: %d (relative: %d, actual: %d)", nrow(x$cells), n_rel, n_act),
    "*" = sprintf("Site units summarized: %d", n_units),
    "*" = sprintf("Species in edatopic cells (>= %g%% constancy): %d", x$min_constancy, n_spp)
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_edatope <- function(x, ...) {
  x$cells
}

#' @export
as.data.frame.vpro_edatope <- function(x, ...) {
  as.data.frame(x$cells, ...)
}

vpro_edatope_grid_label <- function(gt) {
  lbl_map <- c(
    relative = "Relative (rSMR x rSNR)",
    actual = "Actual (aSMR x rSNR)"
  )
  factor(
    unname(lbl_map[gt]),
    levels = unname(lbl_map[intersect(c("relative", "actual"), unique(gt))])
  )
}

vpro_bcgov_unit_palette <- function(n) {
  base_cols <- c(
    "#003366",
    "#FCBA19",
    "#38598A",
    "#2E8540",
    "#B54B28",
    "#6A4C93",
    "#1F7A8C",
    "#A4243B",
    "#4F6D7A",
    "#D9822B",
    "#2B580C",
    "#7A306C"
  )
  if (n <= length(base_cols)) {
    return(base_cols[seq_len(n)])
  }
  grDevices::colorRampPalette(base_cols)(n)
}

#' Plot a B.C. Government 9x5 BEC edatopic grid or species distribution heatmap
#'
#' Renders publication-ready `ggplot2` visualizations of a [vpro_edatopic_grid()]
#' object with `rSNR` (`A..E`) along top and bottom x-axes, reversed `SMR`
#' (`0 -> 8` top-to-bottom) along the y-axis, and [vpro_bcgov_theme()] styling:
#' - When `species = NULL`: draws SiteUnit edatopic bounding boxes and cell plot
#'   counts (faceted side-by-side when `mode = "dual"`).
#' - When `species` is supplied (e.g. `"TSUGHET"` or a character vector): draws
#'   a 9x5 edatopic cover/constancy heatmap across the grid.
#'
#' @param x A `vpro_edatope` object created by [vpro_edatopic_grid()].
#' @param species Optional species code(s) (e.g. `"TSUGHET"`) for species
#'   heatmap mode. When `NULL` (default), plots SiteUnit edatopic boxes.
#' @param units Optional character vector of `SiteUnit` names to display when
#'   `species = NULL`.
#' @param grid_type Optional grid filter: `"relative"`, `"actual"`, or `NULL`
#'   (uses all grids present in `x`).
#' @return A `ggplot` object.
#' @export
vpro_plot_edatope <- function(x, species = NULL, units = NULL, grid_type = NULL) {
  rlang::check_installed("ggplot2", reason = "to plot BEC edatopic grids.")
  if (!inherits(x, "vpro_edatope")) {
    rlang::abort("`x` must be a `vpro_edatope` object created by `vpro_edatopic_grid()`.")
  }

  avail_gt <- if (identical(x$mode, "dual")) c("relative", "actual") else x$mode
  if (!is.null(grid_type)) {
    gt_req <- unique(tolower(trimws(as.character(grid_type))))
    bad_gt <- setdiff(gt_req, c("relative", "actual"))
    if (length(bad_gt) > 0L) {
      rlang::abort("`grid_type` must be NULL, 'relative', or 'actual'.")
    }
    avail_gt <- intersect(avail_gt, gt_req)
    if (length(avail_gt) == 0L) {
      avail_gt <- gt_req
    }
  }

  base_grid <- expand.grid(
    SNR_num = 1L:5L,
    SMR = 0L:8L,
    grid_type = avail_gt,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  base_grid$SNR <- .vpro_snr_levels[base_grid$SNR_num]
  base_grid$grid_label <- vpro_edatope_grid_label(base_grid$grid_type)

  if (!is.null(species) && length(species) > 0L) {
    spp_req <- unique(toupper(trimws(as.character(species))))
    spp_req <- spp_req[nzchar(spp_req)]
    if (length(spp_req) == 0L) {
      rlang::abort("`species` must contain at least one non-empty species code.")
    }

    bg_spp <- do.call(
      rbind,
      lapply(spp_req, function(sp) {
        df <- base_grid
        df$Species <- rep(sp, nrow(df))
        df
      })
    )
    bg_spp$Species <- factor(bg_spp$Species, levels = spp_req)

    sub_spp <- x$species[x$species$grid_type %in% avail_gt & x$species$Species %in% spp_req, , drop = FALSE]
    if (nrow(sub_spp) > 0L) {
      sub_spp$grid_label <- vpro_edatope_grid_label(sub_spp$grid_type)
      sub_spp$Species <- factor(sub_spp$Species, levels = spp_req)
      sub_spp$cell_label <- sprintf("%.0f%%\n(C:%.0f)", sub_spp$mean_cover, sub_spp$constancy)
    }

    p <- ggplot2::ggplot() +
      ggplot2::geom_tile(
        data = bg_spp,
        mapping = ggplot2::aes(x = .data[["SNR_num"]], y = .data[["SMR"]]),
        fill = "#FFFFFF",
        colour = "#D8D8D8",
        linewidth = 0.4
      )

    if (nrow(sub_spp) > 0L) {
      p <- p +
        ggplot2::geom_tile(
          data = sub_spp,
          mapping = ggplot2::aes(
            x = .data[["SNR_num"]],
            y = .data[["SMR"]],
            fill = .data[["mean_cover"]]
          ),
          colour = "#003366",
          linewidth = 0.45
        ) +
        ggplot2::geom_text(
          data = sub_spp,
          mapping = ggplot2::aes(
            x = .data[["SNR_num"]],
            y = .data[["SMR"]],
            label = .data[["cell_label"]]
          ),
          size = 2.7,
          colour = "#FFFFFF",
          fontface = "bold"
        ) +
        ggplot2::scale_fill_gradientn(
          name = "Mean Cover (%)",
          colours = c("#FCBA19", "#38598A", "#003366")
        )
    }

    p <- p +
      ggplot2::scale_x_continuous(
        name = "Soil Nutrient Regime (rSNR)",
        breaks = 1L:5L,
        labels = .vpro_snr_levels,
        limits = c(0.5, 5.5),
        expand = c(0, 0),
        sec.axis = ggplot2::dup_axis(name = NULL)
      ) +
      ggplot2::scale_y_reverse(
        name = "Soil Moisture Regime (SMR)",
        breaks = 0L:8L,
        labels = as.character(0L:8L),
        limits = c(8.5, -0.5),
        expand = c(0, 0)
      ) +
      ggplot2::coord_fixed() +
      ggplot2::labs(
        title = paste0("BEC Edatopic Species Distribution: ", paste(spp_req, collapse = ", ")),
        subtitle = paste0("Project: ", x$project, " (", x$ref_period, ")")
      ) +
      vpro_bcgov_theme(type = "ggplot2") +
      ggplot2::theme(panel.grid.major = ggplot2::element_blank())

    if (length(spp_req) > 1L && length(avail_gt) > 1L) {
      p <- p + ggplot2::facet_grid(Species ~ grid_label)
    } else if (length(spp_req) > 1L) {
      p <- p + ggplot2::facet_wrap(~Species)
    } else if (length(avail_gt) > 1L) {
      p <- p + ggplot2::facet_wrap(~grid_label, nrow = 1L)
    }
    return(p)
  }

  # Unit edatopic boxes + cell plot counts mode
  cells_sub <- x$cells[x$cells$grid_type %in% avail_gt, , drop = FALSE]
  boxes_sub <- x$unit_bboxes[x$unit_bboxes$grid_type %in% avail_gt, , drop = FALSE]
  if (!is.null(units) && length(units) > 0L) {
    u_clean <- trimws(as.character(units))
    cells_sub <- cells_sub[cells_sub$SiteUnit %in% u_clean, , drop = FALSE]
    boxes_sub <- boxes_sub[boxes_sub$SiteUnit %in% u_clean, , drop = FALSE]
  }

  cell_counts <- if (nrow(cells_sub) > 0L) {
    cc_dt <- data.table::as.data.table(cells_sub)
    agg_dt <- cc_dt[, list(n_plots = sum(get("n_plots"))), by = c("grid_type", "SMR", "SNR_num")]
    agg_df <- as.data.frame(agg_dt)
    agg_df$grid_label <- vpro_edatope_grid_label(agg_df$grid_type)
    agg_df
  } else {
    data.frame(
      grid_type = character(),
      SMR = integer(),
      SNR_num = integer(),
      n_plots = integer(),
      grid_label = factor(character()),
      stringsAsFactors = FALSE
    )
  }

  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(
      data = base_grid,
      mapping = ggplot2::aes(x = .data[["SNR_num"]], y = .data[["SMR"]]),
      fill = "#FFFFFF",
      colour = "#D8D8D8",
      linewidth = 0.4
    )

  if (nrow(cell_counts) > 0L) {
    p <- p +
      ggplot2::geom_tile(
        data = cell_counts,
        mapping = ggplot2::aes(
          x = .data[["SNR_num"]],
          y = .data[["SMR"]],
          alpha = .data[["n_plots"]]
        ),
        fill = "#F2F2F2",
        colour = "#D8D8D8",
        linewidth = 0.4
      ) +
      ggplot2::scale_alpha_continuous(range = c(0.35, 0.9), guide = "none") +
      ggplot2::geom_text(
        data = cell_counts,
        mapping = ggplot2::aes(
          x = .data[["SNR_num"]] + 0.34,
          y = .data[["SMR"]] - 0.34,
          label = .data[["n_plots"]]
        ),
        size = 2.6,
        colour = "#38598A"
      )
  }

  if (nrow(boxes_sub) > 0L) {
    boxes_sub$grid_label <- vpro_edatope_grid_label(boxes_sub$grid_type)
    unit_lvls <- sort(unique(boxes_sub$SiteUnit))
    boxes_sub$SiteUnit <- factor(boxes_sub$SiteUnit, levels = unit_lvls)
    # Slight deterministic jitter per unit rank so overlapping unit boxes remain legible
    rank_off <- ((as.integer(boxes_sub$SiteUnit) - 1L) %% 5L - 2L) * 0.03
    boxes_sub$xmin <- boxes_sub$snr_min_num - 0.42 + rank_off
    boxes_sub$xmax <- boxes_sub$snr_max_num + 0.42 + rank_off
    boxes_sub$ymin <- boxes_sub$smr_min - 0.42 + rank_off
    boxes_sub$ymax <- boxes_sub$smr_max + 0.42 + rank_off
    boxes_sub$x_lbl <- (boxes_sub$snr_min_num + boxes_sub$snr_max_num) / 2.0 + rank_off
    boxes_sub$y_lbl <- (boxes_sub$smr_min + boxes_sub$smr_max) / 2.0 + rank_off
    pal <- stats::setNames(vpro_bcgov_unit_palette(length(unit_lvls)), unit_lvls)

    p <- p +
      ggplot2::geom_rect(
        data = boxes_sub,
        mapping = ggplot2::aes(
          xmin = .data[["xmin"]],
          xmax = .data[["xmax"]],
          ymin = .data[["ymin"]],
          ymax = .data[["ymax"]],
          colour = .data[["SiteUnit"]]
        ),
        fill = NA,
        linewidth = 0.85
      ) +
      ggplot2::geom_label(
        data = boxes_sub,
        mapping = ggplot2::aes(
          x = .data[["x_lbl"]],
          y = .data[["y_lbl"]],
          label = .data[["SiteUnit"]],
          colour = .data[["SiteUnit"]]
        ),
        size = 2.5,
        fontface = "bold",
        fill = "#FFFFFF",
        linewidth = 0.25,
        show.legend = FALSE
      ) +
      ggplot2::scale_colour_manual(name = "Site Unit", values = pal)
  }

  p <- p +
    ggplot2::scale_x_continuous(
      name = "Soil Nutrient Regime (rSNR)",
      breaks = 1L:5L,
      labels = .vpro_snr_levels,
      limits = c(0.5, 5.5),
      expand = c(0, 0),
      sec.axis = ggplot2::dup_axis(name = NULL)
    ) +
    ggplot2::scale_y_reverse(
      name = "Soil Moisture Regime (SMR)",
      breaks = 0L:8L,
      labels = as.character(0L:8L),
      limits = c(8.5, -0.5),
      expand = c(0, 0)
    ) +
    ggplot2::coord_fixed() +
    ggplot2::labs(
      title = paste0("BEC Edatopic Grid: ", x$project),
      subtitle = paste0("Reference normal period: ", x$ref_period)
    ) +
    vpro_bcgov_theme(type = "ggplot2") +
    ggplot2::theme(panel.grid.major = ggplot2::element_blank())

  if (length(avail_gt) > 1L) {
    p <- p + ggplot2::facet_wrap(~grid_label, nrow = 1L)
  }
  p
}

#' @rdname vpro_plot_edatope
#' @param ... Unused additional arguments for S3 `plot()` compatibility.
#' @export
plot.vpro_edatope <- function(x, species = NULL, units = NULL, grid_type = NULL, ...) {
  vpro_plot_edatope(x, species = species, units = units, grid_type = grid_type)
}
