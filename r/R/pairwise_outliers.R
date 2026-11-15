# BEC Pairwise Diagnostic Similarity & LOO Outlier Detection -------------------

.vpro_sorensen_vec <- function(v1, v2) {
  denom <- sum(v1) + sum(v2)
  if (denom <= 0) {
    return(0.0)
  }
  (2.0 * sum(pmin(v1, v2))) / denom
}

.vpro_pairwise_d_points <- function(const_self, const_other, mean_self, min_constancy, min_diff, minor_cover = 1.0) {
  const_diff <- const_self - const_other
  n <- length(const_diff)
  pts <- rep(0.0, n)
  elig <- const_diff >= 20.0 & const_self >= min_constancy
  if (!any(elig)) {
    return(pts)
  }
  cd <- const_diff[elig]
  cs <- const_self[elig]
  ms <- mean_self[elig]

  const_score <- (cd^(1 / 3)) * (cd / 100.0)
  wt <- ifelse(
    cs >= (min_constancy + 10.0),
    1.0,
    pmax(0.0, pmin(1.0, (cs - min_constancy) / 10.0))
  )
  p <- const_score * wt
  minor_mask <- ms <= minor_cover
  if (any(minor_mask)) {
    p[minor_mask] <- p[minor_mask] * (ms[minor_mask] / minor_cover)
  }
  mid_mask <- cd < 40.0
  if (any(mid_mask)) {
    p[mid_mask] <- p[mid_mask] * ((cd[mid_mask] - 20.0) / 20.0)
  }
  p[p < min_diff] <- 0.0
  pts[elig] <- p
  pts
}

.vpro_pairwise_dd_points <- function(mean_self, mean_other, min_dd) {
  n <- length(mean_self)
  pts <- rep(0.0, n)
  elig <- mean_self > mean_other & mean_self > 5.0
  if (!any(elig)) {
    return(pts)
  }
  ms <- mean_self[elig]
  mo <- mean_other[elig]
  ddiff <- abs(ms^(1 / 3) - pmax(mo, 0.0)^(1 / 3))
  p <- ifelse(ms >= 10.0, ddiff, ddiff * ((ms - 5.0) / 5.0))
  p[p <= min_dd] <- 0.0
  pts[elig] <- p
  pts
}

#' Compute BEC diagnostic-potential pairwise unit similarity
#'
#' Implements the B.C. Ministry of Forests BEC pairwise unit comparison
#' algorithm (`_do_pairwise.R` and VPro Desktop `app/internal/diagnostics`), combining
#' quantitative Sørensen / Bray-Curtis unit similarity with BEC constancy (`d`)
#' and abundance (`dd`) differential points and shared diagnostic potential.
#'
#' @param ws A `vpro_workspace` handle.
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE`, a `*_Lump` table
#'   name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` units.
#' @param min_plots Minimum number of plots required for a unit to enter pairwise
#'   comparison (default `2L`, matching the canonical BEC standard and Go `SynthesisOptions`).
#' @param min_constancy Minimum constancy percentage (`[0, 100]`, default `60`)
#'   required in at least one unit for diagnostic-potential scoring.
#' @param noise_constancy Constancy threshold (`[0, 100]`, default `10`) below
#'   which noisy unit-species occurrences are ignored in differential scoring.
#' @param min_diff Minimum constancy differential points (default `0.5`).
#' @param min_dd Minimum dominant-differential points (default `0.5`).
#' @param cover_precedence Stratum cover precedence (`"sublayer_sum"` default,
#'   or `"strata_totals"`).
#' @return An S3 object of class `vpro_pairwise` with `$pairs` tibble,
#'   `$species_diffs` tibble, and `$similarity_matrix` symmetric numeric matrix.
#' @export
vpro_pairwise <- function(
  ws,
  lump = TRUE,
  exclude_modifiers = TRUE,
  min_plots = 2L,
  min_constancy = 60,
  noise_constancy = 10,
  min_diff = 0.5,
  min_dd = 0.5,
  cover_precedence = c("sublayer_sum", "strata_totals")
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  cover_precedence <- match.arg(cover_precedence)
  min_plots <- as.integer(min_plots)
  if (length(min_plots) != 1L || is.na(min_plots) || min_plots < 1L) {
    rlang::abort("`min_plots` must be a positive integer.")
  }

  scoped <- .vpro_resolve_classified_plots(ws, exclude_modifiers = exclude_modifiers)
  su_df <- scoped$su

  empty_pairs <- tibble::tibble(
    Unit1 = character(),
    Unit2 = character(),
    n_plots_1 = integer(),
    n_plots_2 = integer(),
    shared_diag = numeric(),
    diff_tot_1 = numeric(),
    diff_tot_2 = numeric(),
    diff_tot = numeric(),
    diff_ratio = numeric(),
    bec_sim_min = numeric(),
    bec_sim_mean = numeric(),
    bec_sim_max = numeric(),
    sorensen = numeric()
  )
  empty_diffs <- tibble::tibble(
    Unit1 = character(),
    Unit2 = character(),
    Species = character(),
    ScientificName = character(),
    constancy_1 = numeric(),
    mean_cover_1 = numeric(),
    constancy_2 = numeric(),
    mean_cover_2 = numeric(),
    shared_diag = numeric(),
    d_points_1 = numeric(),
    dd_points_1 = numeric(),
    diff_pts_1 = numeric(),
    d_points_2 = numeric(),
    dd_points_2 = numeric(),
    diff_pts_2 = numeric(),
    favours_unit = character()
  )

  if (nrow(su_df) == 0L) {
    empty_mat <- matrix(numeric(), nrow = 0L, ncol = 0L)
    return(structure(
      list(pairs = empty_pairs, species_diffs = empty_diffs, similarity_matrix = empty_mat),
      class = "vpro_pairwise"
    ))
  }

  su_dt <- unique(data.table::as.data.table(su_df), by = c("PlotNumber", "SiteUnit"))
  uc_dt <- su_dt[, list(n_plots = .N), by = "SiteUnit"]
  elig_units <- .vpro_order_units(uc_dt[["SiteUnit"]][uc_dt[["n_plots"]] >= min_plots])
  n_u <- length(elig_units)

  if (n_u == 0L) {
    empty_mat <- matrix(numeric(), nrow = 0L, ncol = 0L)
    return(structure(
      list(pairs = empty_pairs, species_diffs = empty_diffs, similarity_matrix = empty_mat),
      class = "vpro_pairwise"
    ))
  }

  su_dt <- su_dt[su_dt[["SiteUnit"]] %in% elig_units]
  n_plots_map <- stats::setNames(as.integer(uc_dt[["n_plots"]]), uc_dt[["SiteUnit"]])

  sim_mat <- diag(1.0, nrow = n_u, ncol = n_u)
  dimnames(sim_mat) <- list(elig_units, elig_units)
  bec_mat <- diag(1.0, nrow = n_u, ncol = n_u)
  dimnames(bec_mat) <- list(elig_units, elig_units)

  if (n_u < 2L) {
    attr(sim_mat, "bec_sim_mean") <- bec_mat
    return(structure(
      list(pairs = empty_pairs, species_diffs = empty_diffs, similarity_matrix = sim_mat),
      class = "vpro_pairwise"
    ))
  }

  veg_ps <- .vpro_extract_plot_species_veg(
    ws,
    su_dt[["PlotNumber"]],
    lump = lump,
    cover_precedence = cover_precedence
  )
  tax <- vpro_taxonomy(ws, include_synonyms = FALSE, include_user = TRUE)

  if (nrow(veg_ps) == 0L) {
    pair_rows <- list()
    for (i in seq_len(n_u - 1L)) {
      for (j in (i + 1L):n_u) {
        u1 <- elig_units[[i]]
        u2 <- elig_units[[j]]
        sim_mat[i, j] <- 0.0
        sim_mat[j, i] <- 0.0
        bec_mat[i, j] <- 0.0
        bec_mat[j, i] <- 0.0
        pair_rows[[length(pair_rows) + 1L]] <- tibble::tibble(
          Unit1 = u1, Unit2 = u2,
          n_plots_1 = unname(n_plots_map[[u1]]), n_plots_2 = unname(n_plots_map[[u2]]),
          shared_diag = 0.0, diff_tot_1 = 0.0, diff_tot_2 = 0.0, diff_tot = 0.0,
          diff_ratio = 0.0, bec_sim_min = 0.0, bec_sim_mean = 0.0, bec_sim_max = 0.0,
          sorensen = 0.0
        )
      }
    }
    attr(sim_mat, "bec_sim_mean") <- bec_mat
    return(structure(
      list(pairs = do.call(rbind, pair_rows), species_diffs = empty_diffs, similarity_matrix = sim_mat),
      class = "vpro_pairwise"
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

  mean_cov <- pmin(agg_dt[["sum_cover"]] / agg_dt[["n_plots"]], 100.0)
  const_pct <- pmin((agg_dt[["n_present"]] / agg_dt[["n_plots"]]) * 100.0, 100.0)
  dpot <- .vpro_calc_diagnostic_potential(
    const_pct,
    mean_cov,
    min_constancy = min_constancy,
    dominant = 7.0,
    minor = 1.0,
    min_diff = min_diff
  )$diagnostic_potential

  all_spp <- sort(unique(agg_dt[["Species"]]))
  tax_m <- match(all_spp, tax$Code)
  sci_map <- stats::setNames(ifelse(is.na(tax_m), all_spp, tax$ScientificName[tax_m]), all_spp)

  n_spp <- length(all_spp)
  s_ix <- match(agg_dt[["Species"]], all_spp)
  u_ix <- match(agg_dt[["SiteUnit"]], elig_units)
  lin_ix <- cbind(s_ix, u_ix)

  cov_mat <- matrix(0.0, nrow = n_spp, ncol = n_u, dimnames = list(all_spp, elig_units))
  con_mat <- matrix(0.0, nrow = n_spp, ncol = n_u, dimnames = list(all_spp, elig_units))
  pot_mat <- matrix(0.0, nrow = n_spp, ncol = n_u, dimnames = list(all_spp, elig_units))
  cov_mat[lin_ix] <- mean_cov
  con_mat[lin_ix] <- const_pct
  pot_mat[lin_ix] <- dpot

  # Eligible species for BEC differential potential: max constancy >= min_constancy
  elig_spp_mask <- apply(con_mat, 1L, max) >= min_constancy

  pair_rows <- list()
  diff_rows <- list()

  for (i in seq_len(n_u - 1L)) {
    u1 <- elig_units[[i]]
    for (j in (i + 1L):n_u) {
      u2 <- elig_units[[j]]
      sor <- .vpro_sorensen_vec(cov_mat[, i], cov_mat[, j])
      sim_mat[i, j] <- vpro_round_ace(sor, 4L)
      sim_mat[j, i] <- vpro_round_ace(sor, 4L)

      in_u1 <- elig_spp_mask & (con_mat[, i] > noise_constancy)
      in_u2 <- elig_spp_mask & (con_mat[, j] > noise_constancy)
      union_mask <- in_u1 | in_u2

      c1 <- ifelse(in_u1, con_mat[, i], 0.0)[union_mask]
      m1 <- ifelse(in_u1, cov_mat[, i], 0.0)[union_mask]
      p1 <- ifelse(in_u1, pot_mat[, i], 0.0)[union_mask]

      c2 <- ifelse(in_u2, con_mat[, j], 0.0)[union_mask]
      m2 <- ifelse(in_u2, cov_mat[, j], 0.0)[union_mask]
      p2 <- ifelse(in_u2, pot_mat[, j], 0.0)[union_mask]
      spp_sub <- all_spp[union_mask]

      keep_pot <- (p1 > 0) | (p2 > 0)
      if (any(keep_pot)) {
        c1 <- c1[keep_pot]
        m1 <- m1[keep_pot]
        p1 <- p1[keep_pot]
        c2 <- c2[keep_pot]
        m2 <- m2[keep_pot]
        p2 <- p2[keep_pot]
        spp_sub <- spp_sub[keep_pot]

        sh_spp <- pmin(p1, p2)
        d1 <- .vpro_pairwise_d_points(c1, c2, m1, min_constancy = min_constancy, min_diff = min_diff)
        dd1 <- .vpro_pairwise_dd_points(m1, m2, min_dd = min_dd)
        pts1 <- d1 + dd1
        both1 <- d1 > min_diff & dd1 > min_diff
        pts1[both1] <- pts1[both1] * 1.25
        pts1 <- pmin(pts1, 10.0)

        d2 <- .vpro_pairwise_d_points(c2, c1, m2, min_constancy = min_constancy, min_diff = min_diff)
        dd2 <- .vpro_pairwise_dd_points(m2, m1, min_dd = min_dd)
        pts2 <- d2 + dd2
        both2 <- d2 > min_diff & dd2 > min_diff
        pts2[both2] <- pts2[both2] * 1.25
        pts2 <- pmin(pts2, 10.0)

        shared_diag <- sum(sh_spp)
        diff_tot_1 <- sum(pts1)
        diff_tot_2 <- sum(pts2)

        has_diff <- (pts1 > 0) | (pts2 > 0) | (sh_spp > 0)
        if (any(has_diff)) {
          k_ix <- which(has_diff)
          ord_d <- k_ix[order(-pmax(pts1[k_ix], pts2[k_ix]), -sh_spp[k_ix], spp_sub[k_ix])]
          fav <- ifelse(pts1[ord_d] > pts2[ord_d], u1, ifelse(pts2[ord_d] > pts1[ord_d], u2, "shared"))
          diff_rows[[length(diff_rows) + 1L]] <- tibble::tibble(
            Unit1 = rep(u1, length(ord_d)),
            Unit2 = rep(u2, length(ord_d)),
            Species = spp_sub[ord_d],
            ScientificName = unname(sci_map[spp_sub[ord_d]]),
            constancy_1 = vpro_round_ace(c1[ord_d], 1L),
            mean_cover_1 = vpro_round_ace(m1[ord_d], 2L),
            constancy_2 = vpro_round_ace(c2[ord_d], 1L),
            mean_cover_2 = vpro_round_ace(m2[ord_d], 2L),
            shared_diag = vpro_round_ace(sh_spp[ord_d], 2L),
            d_points_1 = vpro_round_ace(d1[ord_d], 2L),
            dd_points_1 = vpro_round_ace(dd1[ord_d], 2L),
            diff_pts_1 = vpro_round_ace(pts1[ord_d], 2L),
            d_points_2 = vpro_round_ace(d2[ord_d], 2L),
            dd_points_2 = vpro_round_ace(dd2[ord_d], 2L),
            diff_pts_2 = vpro_round_ace(pts2[ord_d], 2L),
            favours_unit = fav
          )
        }
      } else {
        shared_diag <- 0.0
        diff_tot_1 <- 0.0
        diff_tot_2 <- 0.0
      }

      diff_tot <- diff_tot_1 + diff_tot_2
      denom_tot <- diff_tot + 2.0 * shared_diag
      diff_ratio <- if (denom_tot > 0) (2.0 * shared_diag) / denom_tot else 0.0
      r1 <- if ((diff_tot_1 + shared_diag) > 0) shared_diag / (diff_tot_1 + shared_diag) else 0.0
      r2 <- if ((diff_tot_2 + shared_diag) > 0) shared_diag / (diff_tot_2 + shared_diag) else 0.0
      bec_mean <- (r1 + r2) / 2.0
      bec_min <- min(r1, r2)
      bec_max <- max(r1, r2)

      bec_mat[i, j] <- vpro_round_ace(bec_mean, 4L)
      bec_mat[j, i] <- vpro_round_ace(bec_mean, 4L)

      pair_rows[[length(pair_rows) + 1L]] <- tibble::tibble(
        Unit1 = u1,
        Unit2 = u2,
        n_plots_1 = unname(n_plots_map[[u1]]),
        n_plots_2 = unname(n_plots_map[[u2]]),
        shared_diag = vpro_round_ace(shared_diag, 2L),
        diff_tot_1 = vpro_round_ace(diff_tot_1, 2L),
        diff_tot_2 = vpro_round_ace(diff_tot_2, 2L),
        diff_tot = vpro_round_ace(diff_tot, 2L),
        diff_ratio = vpro_round_ace(diff_ratio, 4L),
        bec_sim_min = vpro_round_ace(bec_min, 4L),
        bec_sim_mean = vpro_round_ace(bec_mean, 4L),
        bec_sim_max = vpro_round_ace(bec_max, 4L),
        sorensen = vpro_round_ace(sor, 4L)
      )
    }
  }

  pairs_tbl <- if (length(pair_rows) > 0L) do.call(rbind, pair_rows) else empty_pairs
  diffs_tbl <- if (length(diff_rows) > 0L) do.call(rbind, diff_rows) else empty_diffs
  attr(sim_mat, "bec_sim_mean") <- bec_mat

  structure(
    list(
      pairs = pairs_tbl,
      species_diffs = diffs_tbl,
      similarity_matrix = sim_mat
    ),
    class = "vpro_pairwise"
  )
}

#' Print a `vpro_pairwise` comparison result
#'
#' @param x A `vpro_pairwise` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_pairwise <- function(x, ...) {
  cli::cli_h3("vpro_pairwise ({nrow(x$similarity_matrix)} unit{?s}, {nrow(x$pairs)} pair{?s})")
  if (nrow(x$pairs) > 0L) {
    cli::cli_bullets(c(
      "*" = "Mean BEC similarity: {round(mean(x$pairs$bec_sim_mean), 3)} | Mean Sorensen: {round(mean(x$pairs$sorensen), 3)}",
      "*" = "Differential species comparisons: {nrow(x$species_diffs)}"
    ))
  }
  invisible(x)
}

#' Coerce `vpro_pairwise` to a tibble
#'
#' @param x A `vpro_pairwise` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return The `$pairs` tibble of pairwise unit similarity metrics.
#' @export
as_tibble.vpro_pairwise <- function(x, ...) {
  x$pairs
}

#' Detect candidate misclassified and anomalous plots via Leave-One-Out centroids
#'
#' For every plot in an assigned `SiteUnit` with `>= 2` plots, computes its
#' quantitative Bray-Curtis / chord similarity to its own unit's Leave-One-Out
#' (LOO) centroid (`own_similarity`), identifies its closest rival unit centroid
#' (`nearest_unit`, `nearest_similarity`), computes
#' `margin = own_similarity - nearest_similarity`, and flags plots that are
#' closer to a rival unit (`margin < 0`) or fall below `threshold`
#' (`own_similarity < threshold`), sorted worst-first as a review queue.
#'
#' @param ws A `vpro_workspace` handle.
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE`, a `*_Lump` table
#'   name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` units.
#' @param transform Cover transformation applied before centroid similarity:
#'   `"none"` (or alias `"raw"`, default matching Go `ComputeOutlierQueue`),
#'   `"sqrt"`, `"log1p"`, `"chord"`, or `"hellinger"`.
#' @param threshold Minimum `own_similarity` (`[0, 1]`, default `0.45`) below
#'   which a plot is flagged for ecological review.
#' @param keep_singletons Logical; if `TRUE` (default, matching Go
#'   `ComputeOutlierQueue`), evaluates singleton (`n_unit_plots == 1`) plots with
#'   `own_similarity = 0.0` against rival unit centroids rather than omitting them.
#' @param cover_precedence Stratum cover precedence (`"sublayer_sum"` default,
#'   or `"strata_totals"`).
#' @return An S3 object of class `vpro_outliers` with `$queue` (all evaluated
#'   plots sorted worst-first) and `$outliers` (flagged subset).
#' @export
vpro_outliers <- function(
  ws,
  lump = TRUE,
  exclude_modifiers = TRUE,
  transform = c("none", "raw", "sqrt", "log1p", "chord", "hellinger"),
  threshold = 0.45,
  keep_singletons = TRUE,
  cover_precedence = c("sublayer_sum", "strata_totals")
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  transform <- match.arg(tolower(as.character(transform[[1L]])), c("none", "raw", "sqrt", "log1p", "chord", "hellinger"))
  cover_precedence <- match.arg(cover_precedence)
  if (!is.numeric(threshold) || length(threshold) != 1L || is.na(threshold) || threshold < 0 || threshold > 1) {
    rlang::abort("`threshold` must be a single number in [0, 1].")
  }
  keep_singletons <- isTRUE(keep_singletons)

  scoped <- .vpro_resolve_classified_plots(ws, exclude_modifiers = exclude_modifiers)
  su_df <- scoped$su
  env_df <- scoped$env
  all_units <- scoped$units

  empty_q <- tibble::tibble(
    PlotNumber = character(),
    SiteUnit = character(),
    n_unit_plots = integer(),
    own_similarity = numeric(),
    nearest_unit = character(),
    nearest_similarity = numeric(),
    margin = numeric(),
    misclassified = logical(),
    low_similarity = logical(),
    flagged = logical(),
    reason = character(),
    Zone = character(),
    SubZone = character(),
    SiteSeries = character(),
    MoistureRegime = character(),
    NutrientRegime = character()
  )

  if (nrow(su_df) == 0L || length(all_units) == 0L) {
    return(structure(
      list(queue = empty_q, outliers = empty_q, transform = transform, threshold = threshold),
      class = "vpro_outliers"
    ))
  }

  su_dt <- unique(data.table::as.data.table(su_df), by = c("PlotNumber", "SiteUnit"))
  uc_dt <- su_dt[, list(n_plots = .N), by = "SiteUnit"]
  n_plots_map <- stats::setNames(as.integer(uc_dt[["n_plots"]]), uc_dt[["SiteUnit"]])

  min_u_plots <- if (keep_singletons) 1L else 2L
  eval_units <- all_units[n_plots_map[all_units] >= min_u_plots]
  if (length(eval_units) == 0L) {
    return(structure(
      list(queue = empty_q, outliers = empty_q, transform = transform, threshold = threshold),
      class = "vpro_outliers"
    ))
  }

  all_plots <- su_dt[["PlotNumber"]]
  veg_ps <- .vpro_extract_plot_species_veg(
    ws,
    all_plots,
    lump = lump,
    cover_precedence = cover_precedence
  )
  all_spp <- sort(unique(veg_ps$Species))

  # Build Plot x Species cover matrix across all classified plots (so singleton rival units can also act as centroids)
  uniq_plots <- unique(all_plots)
  mat <- matrix(0.0, nrow = length(uniq_plots), ncol = length(all_spp), dimnames = list(uniq_plots, all_spp))
  if (nrow(veg_ps) > 0L && length(all_spp) > 0L) {
    r_ix <- match(veg_ps$PlotNumber, uniq_plots)
    c_ix <- match(veg_ps$Species, all_spp)
    mat[cbind(r_ix, c_ix)] <- veg_ps$Cover
  }

  # Apply cover transformation
  if (identical(transform, "sqrt")) {
    mat <- sqrt(pmax(mat, 0.0))
  } else if (identical(transform, "log1p")) {
    mat <- log1p(pmax(mat, 0.0))
  } else if (identical(transform, "hellinger")) {
    rs <- rowSums(mat)
    pos <- rs > 0
    mat[pos, ] <- sqrt(mat[pos, , drop = FALSE] / rs[pos])
  } else if (identical(transform, "chord")) {
    rn <- sqrt(rowSums(mat^2))
    pos <- rn > 0
    mat[pos, ] <- mat[pos, , drop = FALSE] / rn[pos]
  }

  use_cosine <- transform %in% c("chord", "hellinger")
  sim_fn <- function(v1, v2) {
    if (use_cosine) {
      n1 <- sqrt(sum(v1^2))
      n2 <- sqrt(sum(v2^2))
      if (n1 <= 0 || n2 <= 0) return(0.0)
      return(min(max(sum(v1 * v2) / (n1 * n2), 0.0), 1.0))
    }
    .vpro_sorensen_vec(v1, v2)
  }

  # Precompute unit sum vectors and centroids
  unit_sums <- lapply(stats::setNames(all_units, all_units), function(u) {
    u_plots <- su_dt[["PlotNumber"]][su_dt[["SiteUnit"]] == u]
    if (ncol(mat) == 0L) return(numeric(0))
    colSums(mat[u_plots, , drop = FALSE])
  })
  unit_centroids <- lapply(stats::setNames(all_units, all_units), function(u) {
    unit_sums[[u]] / n_plots_map[[u]]
  })

  eval_su <- su_dt[su_dt[["SiteUnit"]] %in% eval_units]
  n_eval <- nrow(eval_su)

  own_sim <- numeric(n_eval)
  near_unit <- rep(NA_character_, n_eval)
  near_sim <- rep(NA_real_, n_eval)

  for (i in seq_len(n_eval)) {
    p_num <- eval_su[["PlotNumber"]][[i]]
    u_own <- eval_su[["SiteUnit"]][[i]]
    n_own <- n_plots_map[[u_own]]
    x_vec <- mat[p_num, ]

    if (n_own <= 1L) {
      own_sim[[i]] <- 0.0
    } else {
      loo_centroid <- pmax((unit_sums[[u_own]] - x_vec) / (n_own - 1.0), 0.0)
      own_sim[[i]] <- sim_fn(x_vec, loo_centroid)
    }

    rivals <- setdiff(all_units, u_own)
    if (length(rivals) > 0L) {
      r_sims <- vapply(rivals, function(ru) sim_fn(x_vec, unit_centroids[[ru]]), numeric(1))
      best_r <- order(-r_sims, rivals)[[1L]]
      near_unit[[i]] <- rivals[[best_r]]
      near_sim[[i]] <- r_sims[[best_r]]
    }
  }

  own_sim_r <- vpro_round_ace(own_sim, 4L)
  near_sim_r <- vpro_round_ace(near_sim, 4L)
  margin <- ifelse(is.na(near_sim_r), own_sim_r, vpro_round_ace(own_sim - near_sim, 4L))
  misclassified <- !is.na(near_sim_r) & (own_sim < near_sim)
  low_sim <- own_sim < threshold
  flagged <- misclassified | low_sim

  reason <- ifelse(
    misclassified & low_sim,
    "closer_to_rival_and_below_threshold",
    ifelse(
      misclassified,
      "closer_to_rival",
      ifelse(low_sim, "below_threshold", "ok")
    )
  )

  env_m <- match(eval_su[["PlotNumber"]], env_df$PlotNumber)
  pull_env_chr <- function(col) {
    if (!(col %in% names(env_df))) return(rep(NA_character_, n_eval))
    as.character(env_df[[col]][env_m])
  }

  q_tbl <- tibble::tibble(
    PlotNumber = as.character(eval_su[["PlotNumber"]]),
    SiteUnit = as.character(eval_su[["SiteUnit"]]),
    n_unit_plots = as.integer(unname(n_plots_map[eval_su[["SiteUnit"]]])),
    own_similarity = own_sim_r,
    nearest_unit = near_unit,
    nearest_similarity = near_sim_r,
    margin = margin,
    misclassified = misclassified,
    low_similarity = low_sim,
    flagged = flagged,
    reason = reason,
    Zone = pull_env_chr("Zone"),
    SubZone = pull_env_chr("SubZone"),
    SiteSeries = pull_env_chr("SiteSeries"),
    MoistureRegime = pull_env_chr("MoistureRegime"),
    NutrientRegime = pull_env_chr("NutrientRegime")
  )

  # Sort worst-first: flagged first, then smallest (most negative) margin, then lowest own_similarity
  ord <- order(!q_tbl$flagged, !q_tbl$misclassified, q_tbl$margin, q_tbl$own_similarity, q_tbl$PlotNumber)
  q_tbl <- q_tbl[ord, , drop = FALSE]
  out_tbl <- q_tbl[q_tbl$flagged, , drop = FALSE]

  structure(
    list(
      queue = q_tbl,
      outliers = out_tbl,
      transform = transform,
      threshold = threshold
    ),
    class = "vpro_outliers"
  )
}

#' Print a `vpro_outliers` review queue
#'
#' @param x A `vpro_outliers` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_outliers <- function(x, ...) {
  n_mis <- sum(x$queue$misclassified, na.rm = TRUE)
  cli::cli_h3("vpro_outliers ({nrow(x$outliers)} flagged / {nrow(x$queue)} evaluated plots)")
  cli::cli_bullets(c(
    "*" = "Transform: {.val {x$transform}} | Threshold: {.val {x$threshold}}",
    "*" = "Closer to rival unit (`margin < 0`): {n_mis}"
  ))
  invisible(x)
}

#' Coerce `vpro_outliers` to a tibble
#'
#' @param x A `vpro_outliers` object.
#' @param flagged_only Logical; if `TRUE`, returns only flagged outlier plots; if
#'   `FALSE` (default), returns the full worst-first LOO review queue.
#' @param ... Unused; included for S3 method compatibility.
#' @return A tibble of LOO plot similarity diagnostics.
#' @export
as_tibble.vpro_outliers <- function(x, flagged_only = FALSE, ...) {
  if (isTRUE(flagged_only)) x$outliers else x$queue
}
