# Multivariate BEC Clustering & Indicator Species Synthesis --------------------

vpro_with_seed <- function(seed, expr) {
  if (is.null(seed) || length(seed) == 0L || is.na(seed[[1L]])) {
    return(force(expr))
  }
  has_old <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (has_old) {
    old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(assign(".Random.seed", old_seed, envir = globalenv()), add = TRUE)
  } else {
    on.exit(
      {
        if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
          rm(".Random.seed", envir = globalenv())
        }
      },
      add = TRUE
    )
  }
  set.seed(as.integer(seed[[1L]]))
  force(expr)
}

#' Cluster VPro plots with hierarchical, medoid, or fuzzy noise classification
#'
#' Builds a community matrix via [vpro_matrix()], computes ecological
#' dissimilarities via [vegan::vegdist()], and executes hierarchical
#' (`"ward.D2"`, `"average"`, Lance-Williams `"beta_flexible"`), medoid
#' (`"pam"`), or De Caceres fuzzy/noise clustering (`"vegclust_fcm"`,
#' `"vegclust_nc"`). Returns an S3 `vpro_clusters` bundle whose `$memberships`
#' tibble (`PlotNumber`, `SiteUnit`, `Cluster`, `Silhouette`, `MaxMembership`,
#' `IsNoise`) is ready for review and guarded candidate-SU write-back.
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param method Clustering algorithm: `"ward.D2"`, `"average"`,
#'   `"beta_flexible"` (Lance-Williams flexible-beta via [cluster::agnes()]),
#'   `"pam"` (partitioning around medoids via [cluster::pam()]), `"vegclust_fcm"`
#'   (fuzzy C-means via [vegclust::vegclust()]), or `"vegclust_nc"` (fuzzy noise
#'   clustering via [vegclust::vegclust()] with `nstart = 20`).
#' @param distance Dissimilarity metric passed to [vegan::vegdist()] (default
#'   `"bray"`; also supports `"chord"`, `"jaccard"`, `"kulczynski"`, `"euclidean"`,
#'   etc.).
#' @param transform Community abundance transformation passed to [vpro_matrix()]
#'   (default `"sqrt"`).
#' @param k Target number of clusters (integer `>= 2`, clamped to `nrow(mat) - 1`).
#' @param m Fuzziness exponent (`> 1`) for `"vegclust_fcm"` and `"vegclust_nc"`
#'   (default `1.25`).
#' @param dnoise Distance-to-noise threshold for `"vegclust_nc"` (default `0.75`).
#' @param beta Lance-Williams flexible-beta parameter for `"beta_flexible"`
#'   (default `-0.25`).
#' @param unit_prefix Prefix for generated `SiteUnit` labels (default `"CL"`,
#'   yielding `"CL_01"`, `"CL_02"`, ..., and `"CL_Noise"` for noise plots).
#' @param lump Species lump setting passed to [vpro_matrix()] (default `TRUE`).
#' @param exclude_modifiers Logical; if `TRUE` (default), excludes `.support`,
#'   `.poor`, and `.nudum` modifier units before clustering.
#' @param seed Optional integer RNG seed for reproducible fuzzy/medoid starts
#'   (default `42L`, restoring caller RNG state on exit).
#' @param ... Additional arguments forwarded to [vpro_matrix()] (e.g. `scope`,
#'   `strata`, `value`, `drop_rare`).
#' @return An S3 object of class `vpro_clusters` containing `memberships`,
#'   `clusters`, `mean_silhouette`, `cophenetic`, `dendrogram`, `fuzzy_weights`,
#'   `matrix`, and `dist`.
#' @export
vpro_cluster <- function(
  ws,
  method = c("ward.D2", "average", "beta_flexible", "pam", "vegclust_fcm", "vegclust_nc"),
  distance = "bray",
  transform = "sqrt",
  k = 4L,
  m = 1.25,
  dnoise = 0.75,
  beta = -0.25,
  unit_prefix = "CL",
  lump = TRUE,
  exclude_modifiers = TRUE,
  seed = 42L,
  ...
) {
  vpro_assert_workspace(ws)
  method <- match.arg(method)
  rlang::check_installed("vegan", reason = "to compute ecological dissimilarity matrices.")
  rlang::check_installed("cluster", reason = "to compute silhouette widths and flexible/PAM clustering.")
  if (method %in% c("vegclust_fcm", "vegclust_nc")) {
    rlang::check_installed("vegclust", reason = "to run fuzzy C-means and noise clustering.")
  }

  if (!is.character(unit_prefix) || length(unit_prefix) != 1L || is.na(unit_prefix) || !nzchar(trimws(unit_prefix))) {
    rlang::abort("`unit_prefix` must be a single non-empty character string.")
  }
  unit_prefix <- trimws(unit_prefix)

  if (!is.numeric(k) || length(k) != 1L || is.na(k) || k < 2) {
    rlang::abort("`k` must be a single integer >= 2.")
  }

  mat_raw <- vpro_matrix(
    ws,
    transform = transform,
    lump = lump,
    exclude_modifiers = exclude_modifiers,
    ...
  )
  env_attr <- attr(mat_raw, "env")
  mat <- as.matrix(mat_raw)
  attr(mat, "env") <- env_attr

  n_plots <- nrow(mat)
  if (n_plots < 3L) {
    rlang::abort(sprintf("`vpro_cluster()` requires at least 3 vegetated plots (found %d).", n_plots))
  }
  k_eff <- as.integer(max(2L, min(as.integer(k), n_plots - 1L)))
  plots_chr <- as.character(rownames(mat))

  dist_mat <- if (identical(tolower(distance), "chord")) {
    stats::dist(vpro_dense_transform(mat, "chord"), method = "euclidean")
  } else {
    vegan::vegdist(mat, method = distance)
  }

  fit <- vpro_with_seed(seed, {
    if (method %in% c("ward.D2", "average")) {
      hc <- stats::hclust(dist_mat, method = method)
      hc$labels <- plots_chr
      grp <- as.integer(stats::cutree(hc, k = k_eff))
      coph <- suppressWarnings(stats::cor(dist_mat, stats::cophenetic(hc)))
      list(
        dendrogram = hc,
        coph = if (is.finite(coph)) as.double(coph) else NA_real_,
        cluster_int = grp,
        site_unit = sprintf("%s_%02d", unit_prefix, grp),
        max_memb = rep(1.0, n_plots),
        is_noise = rep(FALSE, n_plots),
        fuzzy_weights = NULL,
        pam_medoids = NULL
      )
    } else if (identical(method, "beta_flexible")) {
      if (!is.numeric(beta) || length(beta) != 1L || !is.finite(beta) || beta >= 1 || beta <= -1) {
        rlang::abort("`beta` must be a finite number strictly between -1 and 1.")
      }
      alpha <- (1.0 - as.double(beta)) / 2.0
      ag <- cluster::agnes(
        dist_mat,
        diss = TRUE,
        method = "flexible",
        par.method = c(alpha, alpha, as.double(beta), 0.0)
      )
      hc <- stats::as.hclust(ag)
      hc$labels <- plots_chr
      grp <- as.integer(stats::cutree(hc, k = k_eff))
      coph <- suppressWarnings(stats::cor(dist_mat, stats::cophenetic(hc)))
      list(
        dendrogram = hc,
        coph = if (is.finite(coph)) as.double(coph) else NA_real_,
        cluster_int = grp,
        site_unit = sprintf("%s_%02d", unit_prefix, grp),
        max_memb = rep(1.0, n_plots),
        is_noise = rep(FALSE, n_plots),
        fuzzy_weights = NULL,
        pam_medoids = NULL
      )
    } else if (identical(method, "pam")) {
      pm <- cluster::pam(dist_mat, k = k_eff, diss = TRUE)
      grp <- as.integer(pm$clustering)
      meds <- as.character(pm$medoids)
      names(meds) <- sprintf("%s_%02d", unit_prefix, seq_along(meds))
      list(
        dendrogram = NULL,
        coph = NA_real_,
        cluster_int = grp,
        site_unit = sprintf("%s_%02d", unit_prefix, grp),
        max_memb = rep(1.0, n_plots),
        is_noise = rep(FALSE, n_plots),
        fuzzy_weights = NULL,
        pam_medoids = meds
      )
    } else {
      vc_data <- vpro_dense_transform(mat, "chord")
      m_eff <- max(1.05, as.double(m))
      vc_obj <- if (identical(method, "vegclust_nc")) {
        vegclust::vegclust(
          x = vc_data,
          mobileCenters = k_eff,
          method = "NC",
          m = m_eff,
          dnoise = max(0.05, as.double(dnoise)),
          nstart = 20L,
          iter.max = 100L
        )
      } else {
        vegclust::vegclust(
          x = vc_data,
          mobileCenters = k_eff,
          method = "FCM",
          m = m_eff,
          nstart = 20L,
          iter.max = 100L
        )
      }
      memb_mat <- as.matrix(vc_obj$memb)
      rownames(memb_mat) <- plots_chr
      defuzz <- as.character(vegclust::defuzzify(vc_obj)$cluster)
      c_int <- rep(NA_integer_, n_plots)
      s_unit <- character(n_plots)
      noise_flag <- rep(FALSE, n_plots)
      max_m <- apply(memb_mat, 1L, max, na.rm = TRUE)

      for (i in seq_len(n_plots)) {
        raw_lbl <- defuzz[[i]]
        if (is.na(raw_lbl) || identical(raw_lbl, "N") || identical(raw_lbl, "N+")) {
          noise_flag[[i]] <- TRUE
          c_int[[i]] <- NA_integer_
          s_unit[[i]] <- paste0(unit_prefix, "_Noise")
        } else {
          num <- suppressWarnings(as.integer(gsub("[^0-9]", "", raw_lbl)))
          if (is.finite(num)) {
            c_int[[i]] <- num
            s_unit[[i]] <- sprintf("%s_%02d", unit_prefix, num)
          } else {
            s_unit[[i]] <- paste0(unit_prefix, "_", raw_lbl)
          }
        }
      }
      fw_df <- data.frame(
        PlotNumber = plots_chr,
        memb_mat,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      rownames(fw_df) <- plots_chr
      list(
        dendrogram = NULL,
        coph = NA_real_,
        cluster_int = c_int,
        site_unit = s_unit,
        max_memb = as.double(max_m),
        is_noise = noise_flag,
        fuzzy_weights = fw_df,
        pam_medoids = NULL
      )
    }
  })

  # Compute per-plot silhouette widths across non-noise clusters (or all groups if needed)
  sil_vec <- rep(0.0, n_plots)
  d_full <- as.matrix(dist_mat)
  non_noise_idx <- which(!fit$is_noise)
  non_noise_units <- unique(fit$site_unit[non_noise_idx])

  if (length(non_noise_units) >= 2L && length(non_noise_idx) > length(non_noise_units)) {
    sub_codes <- as.integer(factor(fit$site_unit[non_noise_idx]))
    sub_dist <- stats::as.dist(d_full[non_noise_idx, non_noise_idx, drop = FALSE])
    sil_obj <- tryCatch(cluster::silhouette(sub_codes, sub_dist), error = function(e) NULL)
    if (!is.null(sil_obj)) {
      sil_mat <- as.matrix(sil_obj)
      sil_vec[non_noise_idx] <- as.double(sil_mat[, "sil_width"])
    }
    if (any(fit$is_noise)) {
      sil_vec[fit$is_noise] <- NA_real_
    }
  } else {
    all_codes <- as.integer(factor(fit$site_unit))
    if (length(unique(all_codes)) >= 2L && length(unique(all_codes)) < n_plots) {
      sil_obj <- tryCatch(cluster::silhouette(all_codes, dist_mat), error = function(e) NULL)
      if (!is.null(sil_obj)) {
        sil_vec <- as.double(as.matrix(sil_obj)[, "sil_width"])
      }
    }
  }

  memberships_tbl <- tibble::tibble(
    PlotNumber = plots_chr,
    SiteUnit = as.character(fit$site_unit),
    Cluster = as.integer(fit$cluster_int),
    Silhouette = as.double(sil_vec),
    MaxMembership = as.double(fit$max_memb),
    IsNoise = as.logical(fit$is_noise)
  )

  # Order cluster summary with numbered clusters first and Noise last
  uniq_units <- unique(fit$site_unit)
  is_noise_unit <- grepl("_Noise$", uniq_units)
  uniq_units <- c(sort(uniq_units[!is_noise_unit]), sort(uniq_units[is_noise_unit]))

  summary_rows <- lapply(uniq_units, function(u) {
    idx <- which(fit$site_unit == u)
    medoid <- if (!is.null(fit$pam_medoids) && u %in% names(fit$pam_medoids)) {
      unname(fit$pam_medoids[[u]])
    } else if (length(idx) == 1L) {
      plots_chr[[idx]]
    } else {
      avg_d <- rowMeans(d_full[idx, idx, drop = FALSE])
      plots_chr[[idx[[which.min(avg_d)]]]]
    }
    s_vals <- sil_vec[idx]
    mean_s <- if (all(is.na(s_vals))) NA_real_ else mean(s_vals, na.rm = TRUE)
    tibble::tibble(
      SiteUnit = as.character(u),
      n_plots = as.integer(length(idx)),
      mean_silhouette = as.double(mean_s),
      medoid_plot = as.character(medoid),
      is_noise = any(fit$is_noise[idx])
    )
  })
  clusters_tbl <- do.call(rbind, summary_rows)

  valid_sil <- sil_vec[!is.na(sil_vec)]
  mean_sil_overall <- if (length(valid_sil) == 0L) NA_real_ else mean(valid_sil)

  structure(
    list(
      method = method,
      distance = distance,
      transform = transform,
      k = k_eff,
      unit_prefix = unit_prefix,
      memberships = memberships_tbl,
      clusters = clusters_tbl,
      mean_silhouette = as.double(mean_sil_overall),
      cophenetic = fit$coph,
      dendrogram = fit$dendrogram,
      fuzzy_weights = fit$fuzzy_weights,
      matrix = mat,
      dist = dist_mat
    ),
    class = "vpro_clusters"
  )
}

#' Print a `vpro_clusters` classification summary
#'
#' @param x A `vpro_clusters` object from [vpro_cluster()].
#' @param ... Unused additional arguments.
#' @return `x`, invisibly.
#' @export
print.vpro_clusters <- function(x, ...) {
  n_noise <- sum(x$memberships[["IsNoise"]], na.rm = TRUE)
  sil_txt <- if (is.na(x$mean_silhouette)) "NA" else sprintf("%.3f", x$mean_silhouette)
  coph_txt <- if (is.na(x$cophenetic)) "n/a" else sprintf("%.3f", x$cophenetic)
  b1 <- sprintf("Plots: %d (%d noise) | Species: %d", nrow(x$memberships), n_noise, ncol(x$matrix))
  b2 <- sprintf("Mean silhouette: %s | Cophenetic r: %s", sil_txt, coph_txt)
  cli::cli_h3(sprintf("vpro_clusters (%s, distance = %s, k = %d)", x$method, x$distance, x$k))
  cli::cli_bullets(c(
    "*" = b1,
    "*" = b2,
    "*" = "Units: {.val {x$clusters$SiteUnit}}"
  ))
  invisible(x)
}

#' Summarize cluster units from a `vpro_clusters` classification
#'
#' @param object A `vpro_clusters` object from [vpro_cluster()].
#' @param ... Unused additional arguments.
#' @return A tibble with `SiteUnit`, `n_plots`, `mean_silhouette`, `medoid_plot`,
#'   and `is_noise`.
#' @export
summary.vpro_clusters <- function(object, ...) {
  object$clusters
}

#' Coerce a `vpro_clusters` result to a plot-membership tibble
#'
#' @param x A `vpro_clusters` object from [vpro_cluster()].
#' @param ... Unused additional arguments.
#' @return The `$memberships` tibble (`PlotNumber`, `SiteUnit`, `Cluster`,
#'   `Silhouette`, `MaxMembership`, `IsNoise`).
#' @export
as_tibble.vpro_clusters <- function(x, ...) {
  x$memberships
}

#' Plot a `vpro_clusters` dendrogram, silhouette profile, or PCoA ordination
#'
#' @param x A `vpro_clusters` object from [vpro_cluster()].
#' @param type Plot type: `"auto"` (dendrogram when hierarchical, otherwise
#'   2D PCoA ordination of `x$dist`), `"dendrogram"`, or `"ordination"`.
#' @param ... Additional graphical arguments passed to [graphics::plot()].
#' @return `x`, invisibly.
#' @export
plot.vpro_clusters <- function(x, type = c("auto", "dendrogram", "ordination"), ...) {
  type <- match.arg(type)
  if (identical(type, "auto")) {
    type <- if (!is.null(x$dendrogram)) "dendrogram" else "ordination"
  }
  if (identical(type, "dendrogram")) {
    if (is.null(x$dendrogram)) {
      rlang::abort("`x` has no hierarchical dendrogram; use `type = \"ordination\"`.")
    }
    dots <- list(...)
    plot_args <- utils::modifyList(
      list(
        x = x$dendrogram,
        main = sprintf("VPro Cluster Dendrogram (%s, %s)", x$method, x$distance),
        xlab = "PlotNumber",
        sub = "",
        col = "#003366",
        col.main = "#003366",
        col.lab = "#313132",
        col.axis = "#313132"
      ),
      dots
    )
    do.call(graphics::plot, plot_args)
  } else {
    coords <- stats::cmdscale(x$dist, k = 2L)
    grp_fac <- factor(x$memberships[["SiteUnit"]])
    bc_pal <- c("#003366", "#FCBA19", "#38598A", "#2E8540", "#D8292F", "#606060", "#4A6F94", "#8B6F00")
    pal_fn <- if (nlevels(grp_fac) <= length(bc_pal)) {
      bc_pal[seq_len(nlevels(grp_fac))]
    } else {
      grDevices::colorRampPalette(bc_pal)(nlevels(grp_fac))
    }
    cols <- pal_fn[as.integer(grp_fac)]
    graphics::plot(
      coords[, 1L],
      coords[, 2L],
      col = cols,
      pch = ifelse(x$memberships[["IsNoise"]], 4L, 19L),
      xlab = "PCoA Axis 1",
      ylab = "PCoA Axis 2",
      main = sprintf("VPro Cluster Ordination (%s, k = %d)", x$method, x$k),
      ...
    )
    graphics::legend(
      "topright",
      legend = levels(grp_fac),
      col = pal_fn,
      pch = 19L,
      bty = "n",
      cex = 0.85
    )
  }
  invisible(x)
}

#' Compute indicator species fidelity (`IndVal`) across BEC units or clusters
#'
#' Wraps [indicspecies::multipatt()] (falling back to [labdsv::indval()] when
#' `indicspecies` is unavailable) over a VPro community matrix to identify
#' statistically significant diagnostic/indicator species per classification
#' unit or unit combination, enriched with `BCPlantTaxonomy v19` `ScientificName`.
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param clusters Optional grouping specification: `NULL` (uses active
#'   `SiteUnit` from `ws`), a `vpro_clusters` object from [vpro_cluster()]
#'   (excluding `IsNoise` plots), a `data.frame` with `PlotNumber` and
#'   `SiteUnit` columns, or a character/factor vector of group labels (named by
#'   `PlotNumber` or matching `rownames(vpro_matrix(ws, ...))`).
#' @param max_order Maximum site-group combination order for
#'   [indicspecies::multipatt()] (default `1L` for single-unit indicators).
#' @param permutations Number of random permutations for significance testing
#'   (default `199L`).
#' @param seed Optional integer RNG seed for reproducible permutation `p_value`s
#'   (default `42L`).
#' @param ... Additional arguments passed to [vpro_matrix()] (defaults to
#'   `value = "cover"` and `transform = "none"` unless overridden).
#' @return A tibble with `Species`, `Group`, `IndVal`, `p_value`, and
#'   `ScientificName`.
#' @export
vpro_indicators <- function(
  ws,
  clusters = NULL,
  max_order = 1L,
  permutations = 199L,
  seed = 42L,
  ...
) {
  vpro_assert_workspace(ws)
  has_indicspecies <- requireNamespace("indicspecies", quietly = TRUE)
  if (!has_indicspecies) {
    rlang::check_installed(
      "labdsv",
      reason = "to compute indicator species values (install `indicspecies` or `labdsv`)."
    )
  }

  dots <- list(...)
  mat_args <- utils::modifyList(
    list(ws = ws, value = "cover", transform = "none", sparse = FALSE),
    dots
  )
  mat_args$sparse <- FALSE
  mat <- as.matrix(do.call(vpro_matrix, mat_args))
  env_df <- attr(mat, "env")
  plots_chr <- as.character(rownames(mat))

  empty_res <- tibble::tibble(
    Species = character(),
    Group = character(),
    IndVal = numeric(),
    p_value = numeric(),
    ScientificName = character()
  )
  if (nrow(mat) < 2L || ncol(mat) == 0L) {
    return(empty_res)
  }

  grp_vec <- if (is.null(clusters)) {
    as.character(env_df[["SiteUnit"]])
  } else if (inherits(clusters, "vpro_clusters")) {
    m_df <- clusters$memberships
    m_df <- m_df[!m_df[["IsNoise"]], , drop = FALSE]
    g_map <- stats::setNames(as.character(m_df[["SiteUnit"]]), as.character(m_df[["PlotNumber"]]))
    unname(g_map[plots_chr])
  } else if (is.data.frame(clusters)) {
    if (!("PlotNumber" %in% names(clusters))) {
      rlang::abort("`clusters` data.frame must contain a `PlotNumber` column.")
    }
    u_col <- intersect(c("SiteUnit", "Cluster", "Group"), names(clusters))
    if (length(u_col) == 0L) {
      rlang::abort("`clusters` data.frame must contain a `SiteUnit`, `Cluster`, or `Group` column.")
    }
    g_map <- stats::setNames(as.character(clusters[[u_col[[1L]]]]), as.character(clusters[["PlotNumber"]]))
    unname(g_map[plots_chr])
  } else if (is.atomic(clusters) || is.factor(clusters)) {
    if (!is.null(names(clusters))) {
      g_map <- stats::setNames(as.character(clusters), names(clusters))
      unname(g_map[plots_chr])
    } else if (length(clusters) == nrow(mat)) {
      as.character(clusters)
    } else {
      rlang::abort("Unnamed `clusters` vector must match the number of rows in `vpro_matrix(ws, ...)`.")
    }
  } else {
    rlang::abort("`clusters` must be NULL, a `vpro_clusters` object, a data.frame, or a group vector.")
  }

  valid_rows <- !is.na(grp_vec) & nzchar(trimws(grp_vec)) & !grepl("_Noise$", grp_vec)
  mat_sub <- mat[valid_rows, , drop = FALSE]
  grp_sub <- trimws(grp_vec[valid_rows])

  if (nrow(mat_sub) < 2L || length(unique(grp_sub)) < 2L) {
    rlang::abort("`vpro_indicators()` requires plots spanning at least 2 non-empty groups.")
  }

  keep_spp <- colSums(mat_sub > 0) > 0
  mat_sub <- mat_sub[, keep_spp, drop = FALSE]
  if (ncol(mat_sub) == 0L) {
    return(empty_res)
  }

  raw_tbl <- vpro_with_seed(seed, {
    if (has_indicspecies) {
      ctrl <- eval(formals(indicspecies::multipatt)$control, envir = asNamespace("indicspecies"))
      ctrl$nperm <- as.integer(permutations)
      max_ord <- max(1L, min(as.integer(max_order), length(unique(grp_sub))))
      mp <- indicspecies::multipatt(
        mat_sub,
        grp_sub,
        func = "IndVal.g",
        duleg = (max_ord == 1L),
        max.order = max_ord,
        control = ctrl
      )
      sign_df <- mp$sign
      comb_nms <- colnames(mp$comb)
      idx <- as.integer(sign_df[["index"]])
      grp_out <- ifelse(!is.na(idx) & idx >= 1L & idx <= length(comb_nms), comb_nms[idx], NA_character_)
      tibble::tibble(
        Species = as.character(rownames(sign_df)),
        Group = as.character(grp_out),
        IndVal = as.double(sign_df[["stat"]]),
        p_value = as.double(sign_df[["p.value"]])
      )
    } else {
      grp_fac <- factor(grp_sub)
      iv <- labdsv::indval(mat_sub, as.numeric(grp_fac), numitr = as.integer(permutations))
      lvls <- levels(grp_fac)
      tibble::tibble(
        Species = as.character(colnames(mat_sub)),
        Group = as.character(lvls[as.integer(iv$maxcls)]),
        IndVal = sqrt(pmax(0.0, as.double(iv$indcls))),
        p_value = as.double(iv$pval)
      )
    }
  })

  tax <- vpro_taxonomy(ws, include_synonyms = FALSE, include_user = TRUE)
  base_code <- sub("_[A-Za-z0-9]+$", "", raw_tbl[["Species"]])
  exact_ix <- match(raw_tbl[["Species"]], tax[["Code"]])
  fallback_ix <- match(base_code, tax[["Code"]])
  use_ix <- ifelse(!is.na(exact_ix), exact_ix, fallback_ix)
  raw_tbl[["ScientificName"]] <- as.character(tax[["ScientificName"]][use_ix])

  raw_tbl <- raw_tbl[!is.na(raw_tbl[["Group"]]), , drop = FALSE]
  ord <- order(raw_tbl[["p_value"]], -raw_tbl[["IndVal"]], raw_tbl[["Species"]], na.last = TRUE)
  raw_tbl <- raw_tbl[ord, c("Species", "Group", "IndVal", "p_value", "ScientificName"), drop = FALSE]
  rownames(raw_tbl) <- NULL
  tibble::as_tibble(raw_tbl)
}
