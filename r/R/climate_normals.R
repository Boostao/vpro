# Bioclimate Normals Downscaling & BGC Lapse-Rate Calculations ----------------

vpro_climr_has_local_rasters <- function() {
  if (!requireNamespace("climr", quietly = TRUE)) {
    return(FALSE)
  }
  cache_dir <- tryCatch(as.character(climr::cache_path()), error = function(e) "")
  if (!nzchar(cache_dir) || !dir.exists(cache_dir)) {
    return(FALSE)
  }
  tifs <- list.files(
    cache_dir,
    pattern = "\\.(tif|tiff|vrt)$",
    recursive = TRUE,
    ignore.case = TRUE
  )
  length(tifs) > 0L
}

vpro_downscale_climr_points <- function(pts_df, ref_period) {
  xyz <- data.table::data.table(
    id = seq_len(nrow(pts_df)),
    lon = vpro_normalize_bc_lon(as.double(pts_df$lon)),
    lat = as.double(pts_df$lat),
    elev = as.double(pts_df$elev)
  )
  vars_req <- c(
    "MAT",
    "MWMT",
    "MCMT",
    "MAP",
    "MSP",
    "PAS_an",
    "CMD_an",
    "PPT_05",
    "PPT_06",
    "PPT_07",
    "PPT_08",
    "PPT_09",
    "PPT_at",
    "PPT_wt",
    "DD5_an",
    "NFFD_an"
  )
  dl <- tryCatch(
    {
      if (identical(ref_period, "1991_2020")) {
        climr::downscale(
          xyz = xyz,
          vars = vars_req,
          obs_periods = "1991_2020",
          return_refperiod = FALSE,
          db_option = "local",
          cache = TRUE
        )
      } else {
        climr::downscale(
          xyz = xyz,
          vars = vars_req,
          return_refperiod = TRUE,
          db_option = "local",
          cache = TRUE
        )
      }
    },
    error = function(e) NULL
  )

  if (is.null(dl) || nrow(dl) < nrow(pts_df)) {
    return(NULL)
  }
  dl_dt <- data.table::as.data.table(dl)
  if ("PERIOD" %in% names(dl_dt) && any(dl_dt[["PERIOD"]] == ref_period, na.rm = TRUE)) {
    dl_dt <- dl_dt[dl_dt[["PERIOD"]] == ref_period]
  }
  dl_dt <- dl_dt[!duplicated(dl_dt[["id"]])]
  dl_dt <- dl_dt[order(dl_dt[["id"]])]
  if (nrow(dl_dt) != nrow(pts_df)) {
    return(NULL)
  }

  pick_col <- function(dt, candidates) {
    for (nm in candidates) {
      if (nm %in% names(dt)) {
        return(as.double(dt[[nm]]))
      }
    }
    rep(NA_real_, nrow(dt))
  }

  mat_v <- pick_col(dl_dt, c("MAT"))
  if (!all(is.finite(mat_v))) {
    return(NULL)
  }

  tibble::tibble(
    CoordElevHash = as.character(pts_df$CoordElevHash),
    Source = rep("climr_downscale", nrow(pts_df)),
    MAT = round(mat_v, 2L),
    MWMT = round(pick_col(dl_dt, c("MWMT")), 2L),
    MCMT = round(pick_col(dl_dt, c("MCMT")), 2L),
    MAP = round(pick_col(dl_dt, c("MAP")), 1L),
    MSP = round(pick_col(dl_dt, c("MSP")), 1L),
    PAS = round(pick_col(dl_dt, c("PAS_an", "PAS")), 1L),
    CMD = round(pick_col(dl_dt, c("CMD_an", "CMD")), 1L),
    PPT_05 = round(pick_col(dl_dt, c("PPT_05", "PPT05")), 1L),
    PPT_06 = round(pick_col(dl_dt, c("PPT_06", "PPT06")), 1L),
    PPT_07 = round(pick_col(dl_dt, c("PPT_07", "PPT07")), 1L),
    PPT_08 = round(pick_col(dl_dt, c("PPT_08", "PPT08")), 1L),
    PPT_09 = round(pick_col(dl_dt, c("PPT_09", "PPT09")), 1L),
    PPT_at = round(pick_col(dl_dt, c("PPT_at")), 1L),
    PPT_wt = round(pick_col(dl_dt, c("PPT_wt")), 1L),
    DD5 = round(pick_col(dl_dt, c("DD5_an", "DD5")), 1L),
    NFFD = round(pick_col(dl_dt, c("NFFD_an", "NFFD")), 1L)
  )
}

vpro_compute_bgc_lapse_normals <- function(pts_df, ref_period) {
  assets <- vpro_load_asmr_assets()
  bgc_norm_dt <- assets$bgc_normals
  cmd_adj_dt <- assets$cmd_adj

  delta_t <- if (identical(ref_period, "1991_2020")) 0.85 else 0.0
  precip_mult <- if (identical(ref_period, "1991_2020")) 1.03 else 1.00

  sd_cols <- c(
    "Latitude",
    "Longitude",
    "Elevation",
    "MAT",
    "MWMT",
    "MCMT",
    "MAP",
    "MSP",
    "PAS",
    "CMD",
    "PPT_05",
    "PPT_06",
    "PPT_07",
    "PPT_08",
    "PPT_09",
    "PPT_at",
    "PPT_wt",
    "DD5",
    "NFFD"
  )
  zone_means <- bgc_norm_dt[, lapply(.SD, mean, na.rm = TRUE), by = "Zone", .SDcols = sd_cols]

  bgc_keys <- toupper(trimws(as.character(bgc_norm_dt[["BGC"]])))
  zone_keys <- toupper(trimws(as.character(zone_means[["Zone"]])))
  adj_keys <- toupper(trimws(as.character(cmd_adj_dt[["ID2"]])))
  adj_vals <- as.double(cmd_adj_dt[["CMD_Adjust"]])

  n <- nrow(pts_df)
  mat_v <- numeric(n)
  mwmt_v <- numeric(n)
  mcmt_v <- numeric(n)
  map_v <- numeric(n)
  msp_v <- numeric(n)
  pas_v <- numeric(n)
  cmd_v <- numeric(n)
  p05_v <- numeric(n)
  p06_v <- numeric(n)
  p07_v <- numeric(n)
  p08_v <- numeric(n)
  p09_v <- numeric(n)
  pat_v <- numeric(n)
  pwt_v <- numeric(n)
  dd5_v <- numeric(n)
  nffd_v <- numeric(n)

  norm_lat <- as.double(bgc_norm_dt[["Latitude"]])
  norm_lon <- as.double(bgc_norm_dt[["Longitude"]])
  norm_elev <- as.double(bgc_norm_dt[["Elevation"]])

  for (i in seq_len(n)) {
    bgc_clean <- toupper(gsub("[[:space:]]+", "", ifelse(is.na(pts_df$bgc[[i]]), "", as.character(pts_df$bgc[[i]]))))
    zone_clean <- toupper(gsub("[[:space:]]+", "", ifelse(is.na(pts_df$zone[[i]]), "", as.character(pts_df$zone[[i]]))))
    lat_i <- as.double(pts_df$lat[[i]])
    lon_i <- as.double(pts_df$lon[[i]])
    elev_i <- as.double(pts_df$elev[[i]])

    ref <- NULL
    if (nzchar(bgc_clean)) {
      m_ix <- match(bgc_clean, bgc_keys)
      if (!is.na(m_ix)) {
        ref <- bgc_norm_dt[m_ix]
      }
    }
    if (is.null(ref) && nzchar(zone_clean)) {
      z_ix <- match(zone_clean, zone_keys)
      if (!is.na(z_ix)) {
        ref <- zone_means[z_ix]
      }
    }
    if (is.null(ref)) {
      d2 <- (norm_lat - lat_i)^2 +
        ((norm_lon - lon_i) * cos(lat_i * pi / 180.0))^2 +
        ((norm_elev - elev_i) / 250.0)^2
      idx <- which.min(d2)
      ref <- if (length(idx) == 1L && is.finite(idx)) bgc_norm_dt[idx] else bgc_norm_dt[1L]
    }

    d_elev_km <- (elev_i - as.double(ref[["Elevation"]])) / 1000.0
    d_lat <- lat_i - as.double(ref[["Latitude"]])
    temp_shift <- (-5.8 * d_elev_km) + (-0.55 * d_lat) + delta_t
    elev_precip_factor <- max(0.55, min(1.65, 1.0 + 0.18 * d_elev_km)) * precip_mult

    mat_i <- round(as.double(ref[["MAT"]]) + temp_shift, 2L)
    mwmt_i <- round(as.double(ref[["MWMT"]]) + (0.85 * temp_shift), 2L)
    mcmt_i <- round(as.double(ref[["MCMT"]]) + (1.10 * temp_shift), 2L)

    p05_i <- round(max(5.0, as.double(ref[["PPT_05"]]) * elev_precip_factor), 1L)
    p06_i <- round(max(5.0, as.double(ref[["PPT_06"]]) * elev_precip_factor), 1L)
    p07_i <- round(max(5.0, as.double(ref[["PPT_07"]]) * elev_precip_factor), 1L)
    p08_i <- round(max(5.0, as.double(ref[["PPT_08"]]) * elev_precip_factor), 1L)
    p09_i <- round(max(5.0, as.double(ref[["PPT_09"]]) * elev_precip_factor), 1L)
    pat_i <- round(max(10.0, as.double(ref[["PPT_at"]]) * elev_precip_factor), 1L)
    pwt_i <- round(max(10.0, as.double(ref[["PPT_wt"]]) * elev_precip_factor), 1L)
    msp_i <- round(p05_i + p06_i + p07_i + p08_i + p09_i, 1L)
    map_i <- round(max(msp_i + pat_i + pwt_i, as.double(ref[["MAP"]]) * elev_precip_factor), 1L)

    dd5_i <- round(max(25.0, as.double(ref[["DD5"]]) + (temp_shift * 145.0)), 1L)
    nffd_i <- round(max(10.0, min(365.0, as.double(ref[["NFFD"]]) + (temp_shift * 14.0))), 1L)
    snow_frac <- max(0.02, min(0.85, 1.0 / (1.0 + exp((mat_i - 1.5) / 2.2))))
    pas_i <- round(max(0.0, (pwt_i + 0.45 * pat_i) * snow_frac), 1L)

    bgc_adj <- 0.0
    if (nzchar(bgc_clean)) {
      a_ix <- match(bgc_clean, adj_keys)
      if (!is.na(a_ix)) {
        bgc_adj <- adj_vals[[a_ix]]
      }
    }
    cmd_i <- round(
      max(0.0, as.double(ref[["CMD"]]) + bgc_adj + (temp_shift * 32.0) - ((msp_i - as.double(ref[["MSP"]])) * 0.65)),
      1L
    )

    mat_v[[i]] <- mat_i
    mwmt_v[[i]] <- mwmt_i
    mcmt_v[[i]] <- mcmt_i
    map_v[[i]] <- map_i
    msp_v[[i]] <- msp_i
    pas_v[[i]] <- pas_i
    cmd_v[[i]] <- cmd_i
    p05_v[[i]] <- p05_i
    p06_v[[i]] <- p06_i
    p07_v[[i]] <- p07_i
    p08_v[[i]] <- p08_i
    p09_v[[i]] <- p09_i
    pat_v[[i]] <- pat_i
    pwt_v[[i]] <- pwt_i
    dd5_v[[i]] <- dd5_i
    nffd_v[[i]] <- nffd_i
  }

  tibble::tibble(
    CoordElevHash = as.character(pts_df$CoordElevHash),
    Source = rep("bgc_lapse_model", n),
    MAT = mat_v,
    MWMT = mwmt_v,
    MCMT = mcmt_v,
    MAP = map_v,
    MSP = msp_v,
    PAS = pas_v,
    CMD = cmd_v,
    PPT_05 = p05_v,
    PPT_06 = p06_v,
    PPT_07 = p07_v,
    PPT_08 = p08_v,
    PPT_09 = p09_v,
    PPT_at = pat_v,
    PPT_wt = pwt_v,
    DD5 = dd5_v,
    NFFD = nffd_v
  )
}

#' Extract or compute cached plot climate normals
#'
#' Reads existing cached plot climate rows in `ws$project_path` matching each
#' plot's current coordinates, elevation, and `RefPeriod` (shared directly with
#' VPro Desktop). For uncached plots, uses `climr::downscale()` when `climr` and
#' local cached rasters are available (and `!force_offline`), falling back
#' cleanly to the calibrated BGC lapse-rate model when `allow_fallback = TRUE`.
#' Automatically saves newly computed rows on writable user projects when
#' `cache = TRUE`.
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` (active SU plots) or `"project"` (all `_Env` plots).
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`).
#' @param cache Logical; if `TRUE` (default) and `ws` points to a writable user
#'   `.db` outside the installed `vpro` package, persists cache misses via
#'   [vpro_cache_climate()].
#' @param allow_fallback Logical; if `TRUE` (default), falls back to the offline
#'   BGC lapse-rate model when `climr` or local `climr` rasters are unavailable.
#' @param force_offline Logical; if `TRUE`, bypasses `climr` and uses the BGC
#'   lapse-rate model directly.
#' @return A tibble of coordinatized plot climate normals with literal character
#'   `PlotNumber`, site metadata, `CoordElevHash`, `Source`, and 16 climate variables.
#' @export
vpro_climate <- function(
  ws,
  scope = c("su", "project"),
  ref_period = "1961_1990",
  cache = TRUE,
  allow_fallback = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  ref_period <- vpro_normalize_ref_period(ref_period)

  if (!isTRUE(allow_fallback)) {
    if (isTRUE(force_offline)) {
      rlang::abort("Cannot set both `force_offline = TRUE` and `allow_fallback = FALSE`.")
    }
    rlang::check_installed("climr", reason = "to downscale plot climate normals when `allow_fallback = FALSE`.")
  }

  env_df <- vpro_env(ws, scope = scope, include_admin = TRUE)
  empty_res <- function(skipped = 0L) {
    res <- tibble::tibble(
      PlotNumber = character(),
      SiteUnit = character(),
      Zone = character(),
      SubZone = character(),
      BGC = character(),
      Latitude = numeric(),
      Longitude = numeric(),
      Elevation = numeric(),
      CoordElevHash = character(),
      RefPeriod = character(),
      Source = character(),
      MAT = numeric(),
      MWMT = numeric(),
      MCMT = numeric(),
      MAP = numeric(),
      MSP = numeric(),
      PAS = numeric(),
      CMD = numeric(),
      PPT_05 = numeric(),
      PPT_06 = numeric(),
      PPT_07 = numeric(),
      PPT_08 = numeric(),
      PPT_09 = numeric(),
      PPT_at = numeric(),
      PPT_wt = numeric(),
      DD5 = numeric(),
      NFFD = numeric(),
      ComputedAt = character()
    )
    attr(res, "cache_hits") <- 0L
    attr(res, "cache_misses") <- 0L
    attr(res, "skipped_no_coords") <- as.integer(skipped)
    res
  }

  if (nrow(env_df) == 0L) {
    return(empty_res(0L))
  }

  # Deduplicate plots if an SU table had many-to-many assignments
  env_uniq <- env_df[!duplicated(env_df$PlotNumber), , drop = FALSE]

  lat_raw <- suppressWarnings(as.double(env_uniq$Latitude))
  lon_raw <- suppressWarnings(as.double(env_uniq$Longitude))
  elev_raw <- suppressWarnings(as.double(env_uniq$Elevation))

  valid_coord <- !is.na(lat_raw) &
    is.finite(lat_raw) &
    abs(lat_raw) <= 90.0 &
    lat_raw != 0.0 &
    !is.na(lon_raw) &
    is.finite(lon_raw) &
    abs(lon_raw) <= 180.0 &
    lon_raw != 0.0 &
    !is.na(elev_raw) &
    is.finite(elev_raw) &
    elev_raw >= -100.0 &
    elev_raw <= 6000.0

  skipped_no_coords <- sum(!valid_coord)
  if (!any(valid_coord)) {
    return(empty_res(skipped_no_coords))
  }

  sub_env <- env_uniq[valid_coord, , drop = FALSE]
  lat_v <- lat_raw[valid_coord]
  lon_v <- vpro_normalize_bc_lon(lon_raw[valid_coord])
  elev_v <- elev_raw[valid_coord]

  zone_chr <- trimws(ifelse(is.na(sub_env$Zone), "", as.character(sub_env$Zone)))
  subz_chr <- trimws(ifelse(is.na(sub_env$SubZone), "", as.character(sub_env$SubZone)))
  bgc_chr <- gsub("[[:space:]]+", "", paste0(zone_chr, subz_chr))
  if ("GIS_BGC" %in% names(sub_env)) {
    gis_bgc <- gsub("[[:space:]]+", "", ifelse(is.na(sub_env$GIS_BGC), "", as.character(sub_env$GIS_BGC)))
    miss_bgc <- !nzchar(bgc_chr) & nzchar(gis_bgc)
    bgc_chr[miss_bgc] <- gis_bgc[miss_bgc]
  }

  hashes <- .vpro_coord_elev_hash(lat_v, lon_v, elev_v, ref_period = ref_period)
  existing_cache <- vpro_read_plot_climate_cache(ws$project_path)
  existing_period <- existing_cache[existing_cache$RefPeriod == ref_period, , drop = FALSE]

  plot_match_ix <- match(sub_env$PlotNumber, existing_period$PlotNumber)
  is_hit <- !is.na(plot_match_ix) & existing_period$CoordElevHash[plot_match_ix] == hashes

  n_hits <- sum(is_hit)
  n_misses <- sum(!is_hit)

  # Index already-cached climr normals by CoordElevHash so co-located plots reuse pure coordinate normals;
  # fallback bgc_lapse_model rows depend on plot BGC, so evaluate per-(CoordElevHash, BGC)
  climr_cached <- existing_period[existing_period$Source != "bgc_lapse_model", , drop = FALSE]
  hash_lookup <- climr_cached[!duplicated(climr_cached$CoordElevHash), , drop = FALSE]

  miss_idx <- which(!is_hit)
  miss_keys <- ifelse(
    hashes[miss_idx] %in% hash_lookup$CoordElevHash,
    hashes[miss_idx],
    paste0(hashes[miss_idx], "::", toupper(bgc_chr[miss_idx]))
  )
  need_keys <- setdiff(unique(miss_keys), hash_lookup$CoordElevHash)
  hash_lookup$.lookup_key <- hash_lookup$CoordElevHash

  if (length(need_keys) > 0L) {
    first_miss_pos <- match(need_keys, miss_keys)
    first_pt_ix <- miss_idx[first_miss_pos]
    pts_df <- data.frame(
      CoordElevHash = hashes[first_pt_ix],
      lat = vpro_go_round(lat_v[first_pt_ix] * 1e5) / 1e5,
      lon = vpro_go_round(lon_v[first_pt_ix] * 1e5) / 1e5,
      elev = vpro_go_round(elev_v[first_pt_ix] * 1e1) / 1e1,
      bgc = bgc_chr[first_pt_ix],
      zone = zone_chr[first_pt_ix],
      stringsAsFactors = FALSE
    )

    computed <- NULL
    if (!isTRUE(force_offline) && vpro_climr_has_local_rasters()) {
      # Deduplicate pure coordinate points for climr downscaling
      uniq_h <- !duplicated(pts_df$CoordElevHash)
      dl_res <- vpro_downscale_climr_points(pts_df[uniq_h, , drop = FALSE], ref_period = ref_period)
      if (!is.null(dl_res)) {
        computed <- dl_res[match(pts_df$CoordElevHash, dl_res$CoordElevHash), , drop = FALSE]
      }
    }
    if (is.null(computed)) {
      if (!isTRUE(allow_fallback)) {
        rlang::abort(
          "Local `climr` rasters were unavailable or downscaling failed, and `allow_fallback = FALSE`."
        )
      }
      computed <- vpro_compute_bgc_lapse_normals(pts_df, ref_period = ref_period)
    }
    now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    computed$PlotNumber <- sub_env$PlotNumber[first_pt_ix]
    computed$RefPeriod <- rep(ref_period, nrow(computed))
    computed$ComputedAt <- rep(now_iso, nrow(computed))
    computed <- computed[, .vpro_plot_climate_cols, drop = FALSE]
    computed$.lookup_key <- need_keys
    hash_lookup <- rbind(hash_lookup, computed)
  }

  # Assemble plot-level climate table preserving exact order of sub_env
  n_coord <- nrow(sub_env)
  clim_rows <- vector("list", n_coord)
  if (n_hits > 0L) {
    hit_idx <- which(is_hit)
    hit_tbl <- existing_period[plot_match_ix[hit_idx], .vpro_plot_climate_cols, drop = FALSE]
    for (k in seq_along(hit_idx)) {
      clim_rows[[hit_idx[[k]]]] <- hit_tbl[k, , drop = FALSE]
    }
  }
  if (n_misses > 0L) {
    now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    hl_ix <- match(miss_keys, hash_lookup$.lookup_key)
    miss_tbl <- hash_lookup[hl_ix, .vpro_plot_climate_cols, drop = FALSE]
    miss_tbl$PlotNumber <- sub_env$PlotNumber[miss_idx]
    miss_tbl$CoordElevHash <- hashes[miss_idx]
    miss_tbl$RefPeriod <- rep(ref_period, length(miss_idx))
    miss_tbl$ComputedAt <- ifelse(
      is.na(miss_tbl$ComputedAt) | !nzchar(miss_tbl$ComputedAt),
      now_iso,
      miss_tbl$ComputedAt
    )
    for (k in seq_along(miss_idx)) {
      clim_rows[[miss_idx[[k]]]] <- miss_tbl[k, , drop = FALSE]
    }

    can_auto_write <- isTRUE(cache) &&
      !identical(ws$source, "sample") &&
      !vpro_is_bundled_package_path(ws$project_path) &&
      !vpro_is_protected_support_db(ws$project_path, con = ws)
    if (can_auto_write) {
      vpro_cache_climate(ws, miss_tbl)
    }
  }

  assembled <- do.call(rbind, clim_rows)
  out <- tibble::tibble(
    PlotNumber = as.character(sub_env$PlotNumber),
    SiteUnit = as.character(sub_env$SiteUnit),
    Zone = if ("Zone" %in% names(sub_env)) as.character(sub_env$Zone) else rep(NA_character_, n_coord),
    SubZone = if ("SubZone" %in% names(sub_env)) as.character(sub_env$SubZone) else rep(NA_character_, n_coord),
    BGC = ifelse(nzchar(bgc_chr), bgc_chr, NA_character_),
    Latitude = lat_v,
    Longitude = lon_v,
    Elevation = elev_v,
    CoordElevHash = as.character(assembled$CoordElevHash),
    RefPeriod = as.character(assembled$RefPeriod),
    Source = as.character(assembled$Source),
    MAT = as.double(assembled$MAT),
    MWMT = as.double(assembled$MWMT),
    MCMT = as.double(assembled$MCMT),
    MAP = as.double(assembled$MAP),
    MSP = as.double(assembled$MSP),
    PAS = as.double(assembled$PAS),
    CMD = as.double(assembled$CMD),
    PPT_05 = as.double(assembled$PPT_05),
    PPT_06 = as.double(assembled$PPT_06),
    PPT_07 = as.double(assembled$PPT_07),
    PPT_08 = as.double(assembled$PPT_08),
    PPT_09 = as.double(assembled$PPT_09),
    PPT_at = as.double(assembled$PPT_at),
    PPT_wt = as.double(assembled$PPT_wt),
    DD5 = as.double(assembled$DD5),
    NFFD = as.double(assembled$NFFD),
    ComputedAt = as.character(assembled$ComputedAt)
  )
  attr(out, "cache_hits") <- as.integer(n_hits)
  attr(out, "cache_misses") <- as.integer(n_misses)
  attr(out, "skipped_no_coords") <- as.integer(skipped_no_coords)
  out
}
