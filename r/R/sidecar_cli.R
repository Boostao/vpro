# Direct VPro Desktop Out-of-Process Sidecar Bridge (`internal/rsidecar`) -----

vpro_rows_to_dt <- function(x) {
  if (is.data.frame(x)) {
    return(data.table::as.data.table(x))
  }
  if (is.list(x) && length(x) > 0L) {
    cleaned <- lapply(x, function(el) {
      el_list <- as.list(el)
      el_list[vapply(el_list, is.null, logical(1))] <- NA
      el_list
    })
    return(data.table::rbindlist(cleaned, fill = TRUE))
  }
  data.table::data.table()
}

vpro_parse_sidecar_payload <- function(payload_json) {
  if (is.list(payload_json)) {
    return(payload_json)
  }
  if (!is.character(payload_json) || length(payload_json) != 1L || is.na(payload_json)) {
    rlang::abort("`payload_json` must be a JSON string, a path to a `.json` file, or a named list.")
  }
  trimmed <- trimws(payload_json)
  if (file.exists(trimmed) && !dir.exists(trimmed)) {
    return(jsonlite::fromJSON(trimmed, simplifyVector = TRUE))
  }
  jsonlite::fromJSON(trimmed, simplifyVector = TRUE)
}

vpro_build_dendrogram_geometry <- function(hc_obj, cluster_labels, plots_unique, is_noise, effective_cut) {
  n <- length(hc_obj$order)
  leaf_pos <- numeric(n)
  leaf_pos[hc_obj$order] <- seq_len(n)
  node_x <- numeric(n - 1L)
  node_y <- as.numeric(hc_obj$height)
  segments <- vector("list", 3L * (n - 1L))
  seg_k <- 0L

  get_coord <- function(idx) {
    if (idx < 0L) c(leaf_pos[[-idx]], 0.0) else c(node_x[[idx]], node_y[[idx]])
  }
  for (i in seq_len(n - 1L)) {
    left <- get_coord(hc_obj$merge[i, 1L])
    right <- get_coord(hc_obj$merge[i, 2L])
    top_y <- node_y[[i]]
    node_x[[i]] <- 0.5 * (left[[1L]] + right[[1L]])
    seg_k <- seg_k + 1L
    segments[[seg_k]] <- list(x1 = left[[1L]], y1 = left[[2L]], x2 = left[[1L]], y2 = top_y)
    seg_k <- seg_k + 1L
    segments[[seg_k]] <- list(x1 = left[[1L]], y1 = top_y, x2 = right[[1L]], y2 = top_y)
    seg_k <- seg_k + 1L
    segments[[seg_k]] <- list(x1 = right[[1L]], y1 = right[[2L]], x2 = right[[1L]], y2 = top_y)
  }

  leaves <- lapply(seq_len(n), function(pos_i) {
    orig_idx <- hc_obj$order[[pos_i]]
    pnum <- hc_obj$labels[[orig_idx]]
    m_ix <- match(pnum, plots_unique)
    list(
      plotNumber = pnum,
      x = as.numeric(pos_i),
      order = as.integer(pos_i),
      clusterUnit = unname(cluster_labels[[m_ix]]),
      isNoise = isTRUE(is_noise[[m_ix]])
    )
  })

  to_newick <- function(idx, parent_h) {
    if (idx < 0L) {
      lbl <- gsub("[:(),;[:space:]]", "_", hc_obj$labels[[-idx]])
      return(sprintf("%s:%.4f", lbl, max(0.0, round(parent_h, 4))))
    }
    h_curr <- node_y[[idx]]
    l_str <- to_newick(hc_obj$merge[idx, 1L], h_curr)
    r_str <- to_newick(hc_obj$merge[idx, 2L], h_curr)
    if (is.na(parent_h)) sprintf("(%s,%s);", l_str, r_str) else sprintf("(%s,%s):%.4f", l_str, r_str, max(0.0, round(parent_h - h_curr, 4)))
  }

  list(
    maxHeight = round(max(c(0.0001, node_y)), 4),
    cutHeight = effective_cut,
    segments = segments,
    leaves = leaves,
    newick = to_newick(n - 1L, NA_real_)
  )
}

vpro_sidecar_probe_runtime <- function() {
  target_pkgs <- c(
    "vpro", "climr", "vegclust", "vegan", "DBI", "RSQLite",
    "duckdb", "sf", "data.table", "jsonlite", "knitr", "rmarkdown"
  )
  required_pkgs <- c("vegan", "vegclust", "DBI", "RSQLite", "data.table", "jsonlite", "knitr", "rmarkdown")
  pkg_rows <- lapply(target_pkgs, function(pkg) {
    inst <- requireNamespace(pkg, quietly = TRUE)
    list(
      name = pkg,
      installed = inst,
      version = if (inst) as.character(utils::packageVersion(pkg)) else "",
      required = pkg %in% required_pkgs
    )
  })
  climr_cache <- ""
  climr_cached <- FALSE
  if (requireNamespace("climr", quietly = TRUE)) {
    climr_cache <- tryCatch(as.character(climr::cache_path()), error = function(e) "")
    if (nzchar(climr_cache) && dir.exists(climr_cache)) {
      climr_cached <- length(list.files(climr_cache, pattern = "\\.(tif|tiff|vrt)$", recursive = TRUE, ignore.case = TRUE)) > 0L
    }
  }
  list(
    ok = TRUE,
    rVersion = paste0(R.version$major, ".", R.version$minor),
    rVersionFull = R.version.string,
    platform = R.version$platform,
    libPaths = as.list(.libPaths()),
    climrCachePath = climr_cache,
    climrRastersCached = climr_cached,
    packages = pkg_rows
  )
}

vpro_sidecar_climate_asmr <- function(req) {
  ref_period <- if (!is.null(req$refPeriod) && nzchar(req$refPeriod)) as.character(req$refPeriod) else "1961_1990"
  ref_period <- vpro_normalize_ref_period(ref_period)
  force_offline <- isTRUE(req$forceOfflineModel)

  vpro_compatible <- FALSE
  if (!is.null(req$projectPath) && nzchar(req$projectPath) &&
      !is.null(req$projectName) && nzchar(req$projectName) &&
      file.exists(req$projectPath)) {
    vpro_compatible <- tryCatch(isTRUE(vpro_project_inspect(req$projectPath, req$projectName)$compatible), error = function(e) FALSE)
  }

  computed_normals <- list()
  climr_used <- FALSE
  if (!is.null(req$uncachedPoints) && length(req$uncachedPoints) > 0L) {
    pts_dt <- vpro_rows_to_dt(req$uncachedPoints)
    lat_in <- as.numeric(pts_dt$lat)
    lon_in <- vpro_normalize_bc_lon(as.numeric(pts_dt$lon))
    elev_in <- as.numeric(pts_dt$elev)
    hashes_in <- if ("coordElevHash" %in% names(pts_dt)) as.character(pts_dt$coordElevHash) else rep("", nrow(pts_dt))
    missing_h <- is.na(hashes_in) | !nzchar(trimws(hashes_in))
    if (any(missing_h)) {
      hashes_in[missing_h] <- .vpro_coord_elev_hash(lat_in[missing_h], lon_in[missing_h], elev_in[missing_h], ref_period = ref_period)
    }
    pts_df <- data.frame(
      CoordElevHash = hashes_in,
      lat = lat_in,
      lon = lon_in,
      elev = elev_in,
      bgc = if ("bgc" %in% names(pts_dt)) as.character(pts_dt$bgc) else rep("", nrow(pts_dt)),
      zone = if ("zone" %in% names(pts_dt)) as.character(pts_dt$zone) else rep("", nrow(pts_dt)),
      stringsAsFactors = FALSE
    )
    dl_df <- NULL
    if (!force_offline && vpro_climr_has_local_rasters()) {
      dl_df <- vpro_downscale_climr_points(pts_df, ref_period = ref_period)
      if (!is.null(dl_df)) climr_used <- TRUE
    }
    if (is.null(dl_df)) {
      dl_df <- vpro_compute_bgc_lapse_normals(pts_df, ref_period = ref_period)
    }
    computed_normals <- lapply(seq_len(nrow(dl_df)), function(i) {
      list(
        coordElevHash = as.character(dl_df$CoordElevHash[[i]]),
        source = as.character(dl_df$Source[[i]]),
        mat = as.numeric(dl_df$MAT[[i]]),
        mwmt = as.numeric(dl_df$MWMT[[i]]),
        mcmt = as.numeric(dl_df$MCMT[[i]]),
        map = as.numeric(dl_df$MAP[[i]]),
        msp = as.numeric(dl_df$MSP[[i]]),
        pas = as.numeric(dl_df$PAS[[i]]),
        cmd = as.numeric(dl_df$CMD[[i]]),
        ppt05 = as.numeric(dl_df$PPT_05[[i]]),
        ppt06 = as.numeric(dl_df$PPT_06[[i]]),
        ppt07 = as.numeric(dl_df$PPT_07[[i]]),
        ppt08 = as.numeric(dl_df$PPT_08[[i]]),
        ppt09 = as.numeric(dl_df$PPT_09[[i]]),
        pptAt = as.numeric(dl_df$PPT_at[[i]]),
        pptWt = as.numeric(dl_df$PPT_wt[[i]]),
        dd5 = as.numeric(dl_df$DD5[[i]]),
        nffd = as.numeric(dl_df$NFFD[[i]])
      )
    })
  }

  norm_env <- new.env(hash = TRUE, parent = emptyenv())
  if (!is.null(req$cachedNormals) && length(req$cachedNormals) > 0L) {
    cn_dt <- vpro_rows_to_dt(req$cachedNormals)
    for (i in seq_len(nrow(cn_dt))) {
      r <- as.list(cn_dt[i])
      assign(as.character(r$coordElevHash), r, envir = norm_env)
    }
  }
  for (item in computed_normals) {
    assign(as.character(item$coordElevHash), item, envir = norm_env)
  }

  plot_evaluations <- list()
  if (!is.null(req$plots) && length(req$plots) > 0L) {
    pl_dt <- vpro_rows_to_dt(req$plots)
    plot_evaluations <- lapply(seq_len(nrow(pl_dt)), function(i) {
      pr <- pl_dt[i]
      h <- as.character(pr$coordElevHash)
      clim <- if (nzchar(h) && exists(h, envir = norm_env, inherits = FALSE)) get(h, envir = norm_env) else NULL
      rsmr_raw <- if ("rsmr" %in% names(pr)) as.character(pr$rsmr) else NA_character_
      rsmr_num <- vpro_parse_rsmr_digit(rsmr_raw)
      if (is.null(clim)) {
        return(list(
          plotNumber = as.character(pr$plotNumber),
          hasClimate = FALSE,
          rsmrNumeric = if (!is.na(rsmr_num)) as.numeric(rsmr_num) else NULL,
          cmdTopo = NULL,
          cmdSite = NULL,
          asmr = NULL
        ))
      }
      ev <- vpro_evaluate_asmr(
        cmd = as.numeric(clim$cmd),
        ppt_05 = as.numeric(clim$ppt05),
        ppt_06 = as.numeric(clim$ppt06),
        ppt_07 = as.numeric(clim$ppt07),
        ppt_08 = as.numeric(clim$ppt08),
        ppt_09 = as.numeric(clim$ppt09),
        ppt_at = as.numeric(clim$pptAt),
        ppt_wt = as.numeric(clim$pptWt),
        rsmr = rsmr_raw,
        slope = if ("slope" %in% names(pr)) as.numeric(pr$slope) else NA_real_,
        aspect = if ("aspect" %in% names(pr)) as.numeric(pr$aspect) else NA_real_
      )
      list(
        plotNumber = as.character(pr$plotNumber),
        hasClimate = TRUE,
        rsmrNumeric = if (!is.na(ev$rSMR[[1L]])) as.numeric(ev$rSMR[[1L]]) else NULL,
        moistMonths = as.integer(ev$MoistMonths[[1L]]),
        pptDormant = round(as.numeric(clim$pptAt) + as.numeric(clim$pptWt), 1),
        dormantDeficit = round(as.numeric(ev$DormantDeficit[[1L]]), 1),
        aspectFactor = as.numeric(ev$AspectFactor[[1L]]),
        cmdTopo = as.numeric(ev$CMD_topo[[1L]]),
        cmdSite = if (is.finite(ev$CMD_site[[1L]])) as.numeric(ev$CMD_site[[1L]]) else NULL,
        asmr = if (is.finite(ev$aSMR[[1L]])) as.numeric(ev$aSMR[[1L]]) else NULL
      )
    })
  }

  list(
    ok = TRUE,
    refPeriod = ref_period,
    vproCompatible = vpro_compatible,
    climrUsed = climr_used,
    computedNormals = computed_normals,
    plotEvaluations = plot_evaluations
  )
}

vpro_sidecar_run_clustering <- function(req) {
  rlang::check_installed("vegan", reason = "to execute sidecar multivariate clustering.")
  project_path <- as.character(req$projectPath)
  project_name <- as.character(req$projectName)
  lump_arg <- if (isTRUE(req$applyLump)) {
    if (!is.null(req$lumpTable) && nzchar(req$lumpTable)) as.character(req$lumpTable) else TRUE
  } else {
    FALSE
  }
  ws <- vpro_connect(
    project = project_path,
    su = "None",
    lump = if (is.character(lump_arg)) lump_arg else "None"
  )
  ws$project <- project_name
  if (isTRUE(lump_arg)) {
    tables <- vpro_sqlite_physical_tables(project_path)
    ws$lump <- vpro_resolve_table_suffix(tables, NULL, "Lump", default_prefix = project_name)
  }
  if (!is.null(req$vlistsPath) && nzchar(req$vlistsPath) && file.exists(req$vlistsPath)) {
    ws$vlists_path <- normalizePath(req$vlistsPath, winslash = "/", mustWork = TRUE)
  }

  method_req <- if (!is.null(req$method) && nzchar(req$method)) toupper(as.character(req$method)) else "NC"
  distance_metric <- if (!is.null(req$distance) && nzchar(req$distance)) tolower(as.character(req$distance)) else "bray"
  linkage <- if (!is.null(req$linkage) && nzchar(req$linkage)) as.character(req$linkage) else "ward.D2"
  transform_mode <- if (!is.null(req$transform) && nzchar(req$transform)) tolower(as.character(req$transform)) else "sqrt"
  k_req <- if (!is.null(req$k)) as.integer(req$k) else 3L
  fuzziness_m <- if (!is.null(req$fuzziness)) as.numeric(req$fuzziness) else 1.25
  dnoise_val <- if (!is.null(req$dnoise)) as.numeric(req$dnoise) else 0.75
  cut_height <- if (!is.null(req$cutHeight) && is.finite(as.numeric(req$cutHeight)) && as.numeric(req$cutHeight) > 0) as.numeric(req$cutHeight) else NA_real_
  unit_prefix <- if (!is.null(req$unitPrefix) && nzchar(req$unitPrefix)) as.character(req$unitPrefix) else "CL"

  lump_applied_count <- 0L
  if (!identical(lump_arg, FALSE)) {
    lump_tbl <- vpro_lump_map(ws, lump = lump_arg)
    if (nrow(lump_tbl) > 0L) {
      raw_veg_spp <- vpro_veg(ws, scope = "project", strata = "total", lump = FALSE, resolve_synonyms = TRUE)
      if (!is.null(req$plotNumbers) && length(req$plotNumbers) > 0L && nrow(raw_veg_spp) > 0L) {
        raw_veg_spp <- raw_veg_spp[raw_veg_spp$PlotNumber %in% as.character(req$plotNumbers), , drop = FALSE]
      }
      if (nrow(raw_veg_spp) > 0L) {
        lump_applied_count <- sum(raw_veg_spp$Species %in% lump_tbl$SppCode)
      }
    }
  }

  mat_raw <- vpro_matrix(ws, scope = "project", value = "cover", strata = "total", lump = if (!identical(lump_arg, FALSE)) lump_arg else FALSE, transform = "none")
  if (!is.null(req$plotNumbers) && length(req$plotNumbers) > 0L) {
    keep_p <- intersect(rownames(mat_raw), as.character(req$plotNumbers))
    mat_raw <- mat_raw[keep_p, , drop = FALSE]
  }
  mat_raw <- mat_raw[rowSums(mat_raw > 0) > 0, colSums(mat_raw > 0) > 0, drop = FALSE]
  plots_unique <- rownames(mat_raw)
  spp_unique <- colnames(mat_raw)
  if (length(plots_unique) < 3L) {
    rlang::abort(sprintf("Clustering requires at least 3 vegetated plots in scope (found %d).", length(plots_unique)))
  }
  k <- max(2L, min(k_req, length(plots_unique) - 1L))

  mat_trans <- switch(
    transform_mode,
    sqrt = sqrt(mat_raw),
    log1p = log1p(mat_raw),
    chord = vegan::decostand(mat_raw, method = "normalize"),
    hellinger = vegan::decostand(mat_raw, method = "hellinger"),
    mat_raw
  )
  dist_obj <- if (identical(distance_metric, "chord")) {
    stats::dist(vegan::decostand(mat_trans, method = "normalize"), method = "euclidean")
  } else {
    vegan::vegdist(mat_trans, method = if (distance_metric %in% c("bray", "jaccard", "kulczynski", "euclidean", "manhattan")) distance_metric else "bray")
  }

  hc_method <- if (linkage %in% c("ward.D2", "average", "complete", "single", "mcquitty")) linkage else "ward.D2"
  hc <- stats::hclust(dist_obj, method = hc_method)
  if (identical(method_req, "BETA_FLEXIBLE")) {
    rlang::check_installed("cluster", reason = "to run flexible-beta hierarchical clustering.")
    beta_val <- if (!is.null(req$beta) && is.finite(as.numeric(req$beta))) as.numeric(req$beta) else -0.25
    if (beta_val <= -1.0 || beta_val >= 1.0) {
      rlang::abort("`beta` must be a finite number strictly between -1 and 1.")
    }
    alpha <- (1.0 - beta_val) / 2.0
    ag <- cluster::agnes(dist_obj, diss = TRUE, method = "flexible", par.method = c(alpha, alpha, beta_val, 0.0))
    hc <- stats::as.hclust(ag)
    hc$labels <- plots_unique
    hc_method <- "beta_flexible"
  }
  coph_corr <- suppressWarnings(stats::cor(dist_obj, stats::cophenetic(hc)))
  if (!is.finite(coph_corr)) coph_corr <- 0.0

  cluster_labels <- character(length(plots_unique))
  names(cluster_labels) <- plots_unique
  max_membership <- rep(1.0, length(plots_unique))
  is_noise <- rep(FALSE, length(plots_unique))
  effective_cut <- if (is.finite(cut_height)) cut_height else round(0.55 * max(c(0.0001, hc$height)), 4)

  set.seed(42L)
  if (method_req %in% c("NC", "FCM", "KM")) {
    rlang::check_installed("vegclust", reason = "to run fuzzy/noise clustering.")
    vc_data <- vegan::decostand(mat_trans, method = "normalize")
    vc_fit <- if (identical(method_req, "NC")) {
      vegclust::vegclust(vc_data, mobileCenters = k, method = "NC", m = max(1.05, fuzziness_m), dnoise = max(0.05, dnoise_val), nstart = 20L, iter.max = 100L)
    } else if (identical(method_req, "FCM")) {
      vegclust::vegclust(vc_data, mobileCenters = k, method = "FCM", m = max(1.05, fuzziness_m), nstart = 20L, iter.max = 100L)
    } else {
      vegclust::vegclust(vc_data, mobileCenters = k, method = "KM", nstart = 20L, iter.max = 100L)
    }
    memb_mat <- as.matrix(vc_fit$memb)
    defuzz <- vegclust::defuzzify(vc_fit)$cluster
    for (i in seq_along(plots_unique)) {
      raw_cl <- as.character(defuzz[[i]])
      max_membership[[i]] <- round(max(memb_mat[i, ], na.rm = TRUE), 4)
      if (is.na(raw_cl) || raw_cl %in% c("N", "N+")) {
        is_noise[[i]] <- TRUE
        cluster_labels[[i]] <- paste0(unit_prefix, "_Noise")
      } else {
        num_part <- suppressWarnings(as.integer(gsub("[^0-9]", "", raw_cl)))
        cluster_labels[[i]] <- if (is.finite(num_part)) sprintf("%s_%02d", unit_prefix, num_part) else paste0(unit_prefix, "_", raw_cl)
      }
    }
  } else if (identical(method_req, "PAM")) {
    rlang::check_installed("cluster", reason = "to run PAM medoid clustering.")
    pm <- cluster::pam(dist_obj, k = k, diss = TRUE)
    cluster_labels[] <- sprintf("%s_%02d", unit_prefix, as.integer(pm$clustering))
  } else {
    grp <- if (is.finite(cut_height)) {
      stats::cutree(hc, h = cut_height)
    } else {
      if (k >= 2L && k <= length(plots_unique) && !is.null(hc$merge) && nrow(hc$merge) >= (k - 1L)) {
        n_m <- nrow(hc$merge)
        idx_lo <- max(1L, n_m - k + 1L)
        idx_hi <- min(n_m, n_m - k + 2L)
        effective_cut <- round(0.5 * (hc$height[[idx_lo]] + hc$height[[idx_hi]]), 4)
      }
      stats::cutree(hc, k = k)
    }
    cluster_labels[] <- sprintf("%s_%02d", unit_prefix, as.integer(grp))
  }

  sil_widths <- rep(0.0, length(plots_unique))
  mean_sil <- 0.0
  non_noise_idx <- which(!is_noise)
  non_noise_units <- unique(cluster_labels[non_noise_idx])
  if (length(non_noise_units) >= 2L && length(non_noise_idx) > length(non_noise_units) && requireNamespace("cluster", quietly = TRUE)) {
    sub_codes <- as.integer(factor(cluster_labels[non_noise_idx]))
    d_full <- as.matrix(dist_obj)
    sub_dist <- stats::as.dist(d_full[non_noise_idx, non_noise_idx, drop = FALSE])
    sil_obj <- tryCatch(cluster::silhouette(sub_codes, sub_dist), error = function(e) NULL)
    if (!is.null(sil_obj)) {
      sil_widths[non_noise_idx] <- round(as.numeric(as.matrix(sil_obj)[, "sil_width"]), 4)
      mean_sil <- round(mean(sil_widths[non_noise_idx], na.rm = TRUE), 4)
    }
  } else {
    int_codes <- as.integer(factor(cluster_labels))
    if (length(unique(int_codes)) >= 2L && length(unique(int_codes)) < length(plots_unique) && requireNamespace("cluster", quietly = TRUE)) {
      sil_obj <- tryCatch(cluster::silhouette(int_codes, dist_obj), error = function(e) NULL)
      if (!is.null(sil_obj)) {
        sil_widths <- round(as.numeric(as.matrix(sil_obj)[, "sil_width"]), 4)
        mean_sil <- round(mean(sil_widths, na.rm = TRUE), 4)
      }
    }
  }

  tax <- vpro_taxonomy(ws, include_synonyms = FALSE, include_user = TRUE)
  syn_map <- vpro_synonym_map(ws)
  tax_ix <- function(sc) {
    ix <- match(sc, tax$Code)
    if (is.na(ix) && sc %in% names(syn_map)) {
      ix <- match(unname(syn_map[[sc]]), tax$Code)
    }
    ix
  }

  unique_clusters <- sort(unique(cluster_labels))
  non_noise <- unique_clusters[!grepl("_Noise$", unique_clusters)]
  if (length(non_noise) == 0L) non_noise <- unique_clusters
  cl_mean_mat <- matrix(0.0, nrow = length(non_noise), ncol = ncol(mat_raw), dimnames = list(non_noise, colnames(mat_raw)))
  for (ci in seq_along(non_noise)) {
    cl_mean_mat[ci, ] <- colMeans(mat_raw[cluster_labels == non_noise[[ci]], , drop = FALSE])
  }
  col_sum_means <- colSums(cl_mean_mat)

  cluster_summaries <- lapply(unique_clusters, function(cname) {
    idx <- which(cluster_labels == cname)
    sub_m <- mat_raw[idx, , drop = FALSE]
    pres_pct <- (colSums(sub_m > 0) / length(idx)) * 100.0
    mean_cov <- colMeans(sub_m)
    spec <- if (cname %in% non_noise) ifelse(col_sum_means > 0, cl_mean_mat[match(cname, non_noise), ] / col_sum_means, 0.0) else rep(0.0, ncol(mat_raw))
    indval <- spec * (pres_pct / 100.0)
    ord <- utils::head(order(-indval, -pres_pct, -mean_cov)[pres_pct[order(-indval, -pres_pct, -mean_cov)] > 0], 8L)
    indicators <- lapply(ord, function(si) {
      scode <- colnames(mat_raw)[[si]]
      ti <- tax_ix(scode)
      pvals <- sub_m[sub_m[, si] > 0, si]
      list(
        species = scode,
        scientificName = if (!is.na(ti) && !is.na(tax$ScientificName[[ti]])) tax$ScientificName[[ti]] else "",
        englishName = if (!is.na(ti) && !is.na(tax$EnglishName[[ti]])) tax$EnglishName[[ti]] else "",
        lifeform = if (!is.na(ti) && !is.na(tax$Lifeform[[ti]])) as.integer(tax$Lifeform[[ti]]) else 0L,
        constancyPct = round(pres_pct[[si]], 1),
        meanCover = round(mean(pvals), 2),
        indVal = round(indval[[si]] * 100.0, 1)
      )
    })
    list(
      clusterUnit = cname,
      isNoise = grepl("_Noise$", cname),
      plotCount = as.integer(length(idx)),
      meanRichness = round(mean(rowSums(sub_m > 0)), 1),
      meanSilhouette = round(mean(sil_widths[idx], na.rm = TRUE), 4),
      indicators = indicators
    )
  })

  dendro <- vpro_build_dendrogram_geometry(hc, cluster_labels, plots_unique, is_noise, effective_cut)
  memberships <- lapply(seq_along(plots_unique), function(i) {
    list(
      plotNumber = plots_unique[[i]],
      clusterUnit = unname(cluster_labels[[i]]),
      membership = max_membership[[i]],
      isNoise = is_noise[[i]],
      silhouette = sil_widths[[i]],
      speciesRichness = as.integer(sum(mat_raw[i, ] > 0))
    )
  })

  list(
    ok = TRUE,
    method = method_req,
    distance = distance_metric,
    linkage = hc_method,
    transform = transform_mode,
    k = as.integer(k),
    plotCount = as.integer(length(plots_unique)),
    speciesCount = as.integer(length(spp_unique)),
    lumpAppliedRows = as.integer(lump_applied_count),
    copheneticCorrelation = round(coph_corr, 4),
    meanSilhouette = mean_sil,
    noiseCount = as.integer(sum(is_noise)),
    clusters = cluster_summaries,
    memberships = memberships,
    dendrogram = dendro
  )
}

vpro_sidecar_render_guide <- function(req) {
  ws <- vpro_connect(
    project = as.character(req$projectPath),
    su = if (isFALSE(req$useActiveSu)) "None" else req$suTable,
    lump = if (isFALSE(req$applyLump)) "None" else req$lumpTable
  )
  if (!is.null(req$projectName) && nzchar(req$projectName)) ws$project <- as.character(req$projectName)
  g_type <- if (!is.null(req$guideType) && req$guideType %in% c("single_unit", "bgc_unit", "veg_summary", "qc_audit")) {
    as.character(req$guideType)
  } else {
    "single_unit"
  }
  art <- vpro_render_guide(
    ws = ws,
    type = g_type,
    unit = req$targetUnit,
    bgc = req$bgcFilter,
    format = "html",
    output_file = req$destinationPath,
    title = req$title,
    concept_notes = req$conceptNotes,
    ref_period = if (!is.null(req$refPeriod) && nzchar(req$refPeriod)) req$refPeriod else "1961_1990",
    min_constancy = if (!is.null(req$minConstancyPct)) as.numeric(req$minConstancyPct) else 20,
    lump = !isFALSE(req$applyLump),
    force_offline = isTRUE(req$forceOfflineModel)
  )
  html_preview <- paste(readLines(art$path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  pdf_path <- ""
  pdf_status <- ""
  if (isTRUE(req$includePdf)) {
    pdf_dest <- paste0(tools::file_path_sans_ext(art$path), ".pdf")
    pdf_try <- tryCatch(
      vpro_render_guide(
        ws = ws,
        type = g_type,
        unit = req$targetUnit,
        bgc = req$bgcFilter,
        format = "pdf",
        output_file = pdf_dest,
        title = req$title,
        concept_notes = req$conceptNotes,
        ref_period = if (!is.null(req$refPeriod) && nzchar(req$refPeriod)) req$refPeriod else "1961_1990",
        min_constancy = if (!is.null(req$minConstancyPct)) as.numeric(req$minConstancyPct) else 20,
        lump = !isFALSE(req$applyLump),
        force_offline = isTRUE(req$forceOfflineModel)
      ),
      error = function(e) e
    )
    if (inherits(pdf_try, "error")) {
      pdf_status <- paste0("skipped: ", conditionMessage(pdf_try))
    } else {
      pdf_path <- pdf_try$path
      pdf_status <- "rendered"
    }
  }
  out <- list(
    ok = TRUE,
    contextId = if (!is.null(req$contextId)) as.character(req$contextId) else "",
    guideType = art$type,
    title = art$title,
    targetUnit = art$target_unit,
    bgcLabel = art$bgc_label,
    plotCount = art$plot_count,
    speciesRowCount = art$species_rows,
    rendererUsed = art$renderer,
    htmlPath = art$path,
    htmlSizeBytes = as.integer(art$size_bytes),
    htmlSha256 = art$sha256,
    htmlPreview = html_preview,
    vegetationTable = art$payload$vegetationTable
  )
  if (nzchar(pdf_path)) out$pdfPath <- pdf_path
  if (nzchar(pdf_status)) out$pdfStatus <- pdf_status
  out
}

#' Execute an internal VPro desktop sidecar action with JSON schema parity
#'
#' Allows VPro (`app/internal/rsidecar`) or internal harnesses to invoke `vpro`'s
#' native engines directly while preserving exact request/response JSON field
#' names for `probe_runtime`, `compute_climate_asmr`, `run_clustering`, and
#' `render_guide`.
#'
#' @param action Sidecar action name: `"probe_runtime"`, `"compute_climate_asmr"`,
#'   `"run_clustering"`, or `"render_guide"`.
#' @param payload_json Named R list, JSON string, or path to a request `.json`
#'   file (ignored when `action = "probe_runtime"` and omitted).
#' @param output_json Optional destination `.json` file path where the serialized
#'   JSON response is written atomically.
#' @return Structured response list matching the `app/internal/rsidecar`
#'   JSON contract.
#' @keywords internal
.vpro_sidecar_exec <- function(
  action = c("probe_runtime", "compute_climate_asmr", "run_clustering", "render_guide"),
  payload_json = list(),
  output_json = NULL
) {
  action <- match.arg(action)
  req <- if (identical(action, "probe_runtime") && missing(payload_json)) {
    list()
  } else {
    vpro_parse_sidecar_payload(payload_json)
  }

  resp <- switch(
    action,
    probe_runtime = vpro_sidecar_probe_runtime(),
    compute_climate_asmr = vpro_sidecar_climate_asmr(req),
    run_clustering = vpro_sidecar_run_clustering(req),
    render_guide = vpro_sidecar_render_guide(req)
  )

  if (!is.null(output_json) && nzchar(trimws(output_json))) {
    out_path <- vpro_abs_path(output_json)
    dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
    tmp <- tempfile("vpro-sidecar-", tmpdir = dirname(out_path), fileext = ".json")
    on.exit(unlink(tmp), add = TRUE)
    jsonlite::write_json(resp, path = tmp, auto_unbox = TRUE, pretty = FALSE, null = "null")
    if (!file.rename(tmp, out_path)) {
      file.copy(tmp, out_path, overwrite = TRUE)
    }
  }
  resp
}
