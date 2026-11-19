# Community Matrices & Abundance Transformations -------------------------------

vpro_dense_transform <- function(mat, transform) {
  switch(
    transform,
    "none" = mat,
    "sqrt" = sqrt(mat),
    "log1p" = log1p(mat),
    "hellinger" = {
      rs <- rowSums(mat)
      scale <- ifelse(rs > 0, 1.0 / rs, 0.0)
      sqrt(mat * scale)
    },
    "chord" = {
      rn <- sqrt(rowSums(mat^2))
      scale <- ifelse(rn > 0, 1.0 / rn, 0.0)
      mat * scale
    },
    "wisconsin" = {
      rlang::check_installed("vegan", reason = "to apply Wisconsin double standardization.")
      dn <- dimnames(mat)
      if (nrow(mat) == 0L || ncol(mat) == 0L) {
        return(mat)
      }
      w <- as.matrix(vegan::wisconsin(mat))
      w[!is.finite(w)] <- 0.0
      dimnames(w) <- dn
      w
    }
  )
}

vpro_sparse_transform <- function(smat, transform) {
  if (identical(transform, "none") || length(smat@x) == 0L) {
    return(smat)
  }
  if (identical(transform, "sqrt")) {
    smat@x <- sqrt(smat@x)
    return(smat)
  }
  if (identical(transform, "log1p")) {
    smat@x <- log1p(smat@x)
    return(smat)
  }
  if (identical(transform, "hellinger")) {
    rs <- Matrix::rowSums(smat)
    row_i <- smat@i + 1L
    r_tot <- rs[row_i]
    smat@x <- ifelse(r_tot > 0, sqrt(smat@x / r_tot), 0.0)
    return(smat)
  }
  if (identical(transform, "chord")) {
    s2 <- smat
    s2@x <- s2@x^2
    rn <- sqrt(Matrix::rowSums(s2))
    row_i <- smat@i + 1L
    r_norm <- rn[row_i]
    smat@x <- ifelse(r_norm > 0, smat@x / r_norm, 0.0)
    return(smat)
  }
  if (identical(transform, "wisconsin")) {
    rlang::check_installed("vegan", reason = "to apply Wisconsin double standardization.")
    dense <- vpro_dense_transform(as.matrix(smat), "wisconsin")
    nz <- which(dense != 0, arr.ind = TRUE)
    if (nrow(nz) == 0L) {
      return(Matrix::sparseMatrix(
        i = integer(),
        j = integer(),
        x = numeric(),
        dims = dim(dense),
        dimnames = dimnames(dense),
        repr = "C"
      ))
    }
    return(Matrix::sparseMatrix(
      i = nz[, 1L],
      j = nz[, 2L],
      x = as.double(dense[nz]),
      dims = dim(dense),
      dimnames = dimnames(dense),
      repr = "C"
    ))
  }
  smat
}

#' Build a BEC community (`plot x species`) matrix with aligned environment data
#'
#' Extracts tidy plot vegetation and environment records from a `vpro_workspace`
#' and constructs either a base R numeric `matrix` (`sparse = FALSE`) or a
#' compressed column sparse `Matrix::dgCMatrix` (`sparse = TRUE`) ready for
#' one-line ordination, PERMANOVA, clustering, and indicator species analysis
#' in `vegan`, `vegclust`, `indicspecies`, and `labdsv`.
#'
#' Row names are always literal character `PlotNumber`s (preserving leading
#' zeroes such as `"00337"`). Unvegetated plots or plots whose only species are
#' removed by `drop_rare` are excluded so downstream Bray-Curtis / correspondence
#' routines never encounter zero-sum rows; any excluded plot IDs are recorded in
#' `attr(m, "dropped_empty_plots")`, and `attr(m, "env")` is strictly aligned
#' 1-to-1 with `rownames(m)` (`identical(attr(m, "env")$PlotNumber, rownames(m))`).
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param scope Plot scope: `"su"` (active `ws$su` when set, else all project
#'   plots) or `"project"` (all `<Project>_Env` plots).
#' @param value Cell abundance metric prior to `transform`: `"cover"`
#'   (percentage cover), `"presence"` (`1`/`0` incidence), or `"goldstream"`
#'   (`sqrt(cover)` plot-level Goldstream scaling).
#' @param strata Taxonomic column resolution: `"total"` (`Species`), `"abcd"`
#'   (`paste0(Species, "_", Strata)`), or `"raw"` (`paste0(Species, "_", Layer)`).
#' @param lump Logical (`TRUE` uses active `ws$lump` with VPro's `99%` cap),
#'   `FALSE`, a `*_Lump` table name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param transform Ecological standardization applied after `value`: `"none"`,
#'   `"sqrt"`, `"log1p"`, `"hellinger"` (\eqn{\sqrt{x_{ij} / x_{i+}}} with
#'   zero-row safety), `"chord"` (\eqn{x_{ij} / \sqrt{\sum_j x_{ij}^2}} with
#'   zero-row safety), or `"wisconsin"` ([vegan::wisconsin()]).
#' @param drop_rare Rare-species threshold. When `0` (default), retains all
#'   species. When `0 < drop_rare < 1`, drops species occurring in fewer than
#'   `drop_rare` proportion of vegetated plots. When `drop_rare >= 1`, drops
#'   species occurring in fewer than `drop_rare` plots.
#' @param sparse Logical; if `TRUE`, returns a `Matrix::dgCMatrix` instead of a
#'   dense `matrix`.
#' @param exclude_modifiers Logical; if `TRUE`, excludes `.support`, `.poor`,
#'   and `.nudum` site units.
#' @param cover_precedence Precedence rule passed to [vpro_veg()]:
#'   `"strata_totals"` (default, matching MS Access `vpro_veg` where positive
#'   `TotalA`/`TotalB` overrides sublayer combinations) or `"sublayer_sum"`
#'   (matching BEC diagnostics where `TotalA`/`TotalB` is used only when
#'   sublayers are `NA`).
#' @return A `plot x species` numeric `matrix` (or `Matrix::dgCMatrix` when
#'   `sparse = TRUE`) carrying `attr(m, "env")` (row-aligned [vpro_env()] tibble)
#'   and `attr(m, "dropped_empty_plots")` (character vector of zero-sum plots).
#' @export
vpro_matrix <- function(
  ws,
  scope = c("su", "project"),
  value = c("cover", "presence", "goldstream"),
  strata = c("total", "abcd", "raw"),
  lump = TRUE,
  transform = c("none", "sqrt", "log1p", "hellinger", "chord", "wisconsin"),
  drop_rare = 0,
  sparse = FALSE,
  exclude_modifiers = FALSE,
  cover_precedence = c("strata_totals", "sublayer_sum")
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  value <- match.arg(value)
  strata <- match.arg(strata)
  transform <- match.arg(transform)
  cover_precedence <- match.arg(cover_precedence)

  if (!is.numeric(drop_rare) || length(drop_rare) != 1L || is.na(drop_rare) || !is.finite(drop_rare) || drop_rare < 0) {
    rlang::abort("`drop_rare` must be a single finite non-negative number.")
  }
  if (!is.logical(sparse) || length(sparse) != 1L || is.na(sparse)) {
    rlang::abort("`sparse` must be TRUE or FALSE.")
  }
  if (!is.logical(exclude_modifiers) || length(exclude_modifiers) != 1L || is.na(exclude_modifiers)) {
    rlang::abort("`exclude_modifiers` must be TRUE or FALSE.")
  }

  if (isTRUE(sparse)) {
    rlang::check_installed("Matrix", reason = "to build a sparse `dgCMatrix` community matrix.")
  }
  if (identical(transform, "wisconsin")) {
    rlang::check_installed("vegan", reason = "to apply Wisconsin double standardization.")
  }

  env <- vpro_env(ws, scope = scope, exclude_modifiers = exclude_modifiers)
  env[["PlotNumber"]] <- as.character(env[["PlotNumber"]])
  env <- env[!duplicated(env[["PlotNumber"]]), , drop = FALSE]

  veg <- vpro_veg(
    ws,
    scope = scope,
    lump = lump,
    strata = strata,
    exclude_modifiers = exclude_modifiers,
    cover_precedence = cover_precedence
  )

  make_empty_matrix <- function(dropped) {
    dn <- list(character(), character())
    m_empty <- if (isTRUE(sparse)) {
      Matrix::sparseMatrix(
        i = integer(),
        j = integer(),
        x = numeric(),
        dims = c(0L, 0L),
        dimnames = dn,
        repr = "C"
      )
    } else {
      matrix(numeric(), nrow = 0L, ncol = 0L, dimnames = dn)
    }
    env_zero <- env[0L, , drop = FALSE]
    rownames(env_zero) <- NULL
    attr(m_empty, "env") <- env_zero
    attr(m_empty, "dropped_empty_plots") <- as.character(dropped)
    m_empty
  }

  if (nrow(env) == 0L || nrow(veg) == 0L) {
    return(make_empty_matrix(env[["PlotNumber"]]))
  }

  col_key <- switch(
    strata,
    "total" = as.character(veg[["Species"]]),
    "abcd" = paste0(veg[["Species"]], "_", veg[["Strata"]]),
    "raw" = paste0(veg[["Species"]], "_", veg[["Layer"]])
  )
  plot_chr <- as.character(veg[["PlotNumber"]])
  cov_num <- as.double(veg[["Cover"]])

  keep_obs <- (plot_chr %in% env[["PlotNumber"]]) & !is.na(cov_num) & cov_num > 0 & !is.na(col_key) & nzchar(col_key)
  if (!any(keep_obs)) {
    return(make_empty_matrix(env[["PlotNumber"]]))
  }

  dt <- data.table::data.table(
    PlotNumber = plot_chr[keep_obs],
    ColKey = col_key[keep_obs],
    Cover = cov_num[keep_obs]
  )
  agg <- dt[, list(Cover = max(get("Cover"))), by = c("PlotNumber", "ColKey")]

  init_plots <- sort(unique(as.character(agg[["PlotNumber"]])), method = "radix")
  n_init_plots <- length(init_plots)

  if (drop_rare > 0 && n_init_plots > 0L) {
    all_cols <- sort(unique(as.character(agg[["ColKey"]])), method = "radix")
    occ_counts <- tabulate(match(agg[["ColKey"]], all_cols), nbins = length(all_cols))
    keep_cols <- if (drop_rare < 1) {
      all_cols[(occ_counts / n_init_plots) >= drop_rare]
    } else {
      all_cols[occ_counts >= drop_rare]
    }
    agg <- agg[agg[["ColKey"]] %in% keep_cols]
    if (nrow(agg) == 0L) {
      return(make_empty_matrix(env[["PlotNumber"]]))
    }
  }

  plots_vec <- sort(unique(as.character(agg[["PlotNumber"]])), method = "radix")
  cols_vec <- sort(unique(as.character(agg[["ColKey"]])), method = "radix")

  cell_val <- switch(
    value,
    "cover" = as.double(agg[["Cover"]]),
    "presence" = rep(1.0, nrow(agg)),
    "goldstream" = sqrt(as.double(agg[["Cover"]]))
  )

  row_ix <- match(agg[["PlotNumber"]], plots_vec)
  col_ix <- match(agg[["ColKey"]], cols_vec)
  dn <- list(plots_vec, cols_vec)

  out_mat <- if (isTRUE(sparse)) {
    smat <- Matrix::sparseMatrix(
      i = row_ix,
      j = col_ix,
      x = cell_val,
      dims = c(length(plots_vec), length(cols_vec)),
      dimnames = dn,
      repr = "C"
    )
    vpro_sparse_transform(smat, transform)
  } else {
    dmat <- matrix(
      0.0,
      nrow = length(plots_vec),
      ncol = length(cols_vec),
      dimnames = dn
    )
    dmat[cbind(row_ix, col_ix)] <- cell_val
    vpro_dense_transform(dmat, transform)
  }

  env_aligned <- env[match(plots_vec, env[["PlotNumber"]]), , drop = FALSE]
  rownames(env_aligned) <- NULL
  attr(out_mat, "env") <- env_aligned
  attr(out_mat, "dropped_empty_plots") <- as.character(setdiff(env[["PlotNumber"]], plots_vec))
  out_mat
}
