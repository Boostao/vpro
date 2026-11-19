# Spatial Geodesy Audit, BCGS 1:20k Mapsheets & OGC GeoPackage Export ----------

vpro_parse_utm_zone <- function(zone_vec) {
  raw <- trimws(ifelse(is.na(zone_vec), "", as.character(zone_vec)))
  out <- rep(NA_integer_, length(raw))
  ok <- grepl("^0*[0-9]{1,2}[A-Za-z]?$", raw)
  if (any(ok)) {
    num_str <- sub("^0*([0-9]{1,2})[A-Za-z]?$", "\\1", raw[ok])
    out[ok] <- suppressWarnings(as.integer(num_str))
  }
  out
}

vpro_bcgs_mapsheet_20k <- function(lat, lon) {
  n <- length(lat)
  out <- rep(NA_character_, n)
  ok <- !is.na(lat) & !is.na(lon) & is.finite(lat) & is.finite(lon) & lat >= 48.0 & lat <= 60.0 & lon >= -140.0 & lon <= -114.0
  if (!any(ok)) {
    return(out)
  }

  # Clamp exact 60N / -114W upper borders into the adjacent BC 1:20k quadrangle
  lat_v <- pmin(as.double(lat[ok]), 60.0 - 1e-9)
  lon_v <- as.double(lon[ok])
  abs_lon <- -lon_v

  primary_col <- as.integer(floor((abs_lon - 48.0) / 8.0))
  primary_col[abs_lon == 112.0] <- 8L
  primary_row <- as.integer(floor((lat_v - 40.0) / 4.0))
  primary_num <- primary_col * 10L + primary_row

  lat_base <- 40.0 + primary_row * 4.0
  lon_east <- -(48.0 + primary_col * 8.0)

  sub_row <- pmin(pmax(as.integer(floor(lat_v - lat_base)), 0L), 3L)
  sub_col_east <- pmin(pmax(as.integer(floor((lon_east - lon_v) / 2.0)), 0L), 3L)

  letter_idx <- ifelse(
    sub_row %% 2L == 0L,
    sub_row * 4L + sub_col_east,
    sub_row * 4L + (3L - sub_col_east)
  )
  letters_1_250k <- LETTERS[letter_idx + 1L]

  block_lat_south <- lat_base + sub_row * 1.0
  block_lon_west <- lon_east - (sub_col_east + 1L) * 2.0

  row_20k <- pmin(pmax(as.integer(floor((lat_v - block_lat_south) * 10.0 + 1e-11)), 0L), 9L)
  col_20k <- pmin(pmax(as.integer(floor((lon_v - block_lon_west) * 5.0 + 1e-11)) + 1L, 1L), 10L)
  sheet_20k <- row_20k * 10L + col_20k

  out[ok] <- sprintf("%03d%s.%03d", primary_num, letters_1_250k, sheet_20k)
  out
}

.vpro_spatial_core_cols <- c(
  "PlotNumber",
  "FieldNumber",
  "ProjectID",
  "FSRegionDistrict",
  "Date",
  "SiteSurveyor",
  "PlotRepresenting",
  "Location",
  "Ecosection",
  "NtsMapSheet",
  "Longitude",
  "Latitude",
  "UTMZone",
  "UTMEasting",
  "UTMNorthing",
  "LocationAccuracy",
  "Zone",
  "SubZone",
  "SiteSeries",
  "SiteModifier1",
  "SiteModifier2",
  "MoistureRegime",
  "NutrientRegime",
  "SuccessionalStatus",
  "StructuralStage",
  "StandAge",
  "Elevation",
  "SlopeGradient",
  "Aspect",
  "MesoSlopePosition",
  "SoilDrainage",
  "HumusForm",
  "StrataCoverTree",
  "StrataCoverShrub",
  "StrataCoverHerb",
  "StrataCoverMoss",
  "Flag",
  "GIS_BGC",
  "BECSiteUnit",
  "UserSiteUnit",
  "SitePlotQuality",
  "VegPlotQuality",
  "SoilPlotQuality"
)

#' Extract spatial `sf` plot features with NAD83 geodesy audit and BCGS mapsheets
#'
#' Reads plot environment records via [vpro_env()], preserves literal character
#' `PlotNumber`s (`"00337"`), repairs unsigned positive Western longitudes in
#' British Columbia (`Longitude > 0 & Longitude >= 110 & Longitude <= 145`
#' negated with `sign_flipped = TRUE`), backfills missing `Latitude`/`Longitude`
#' from NAD83 UTM zones `7..11` (`EPSG:26907`..`EPSG:26911` -> `EPSG:4269`),
#' optionally audits ellipsoidal distance (`utm_dd_divergence_m` and
#' `utm_dd_divergent = utm_dd_divergence_m > 250`) when both DD and UTM are
#' populated, derives standard B.C. 1:20,000 `bcgs_mapsheet_20k` grid codes
#' (e.g. `"093L.054"`), and transforms to `crs` (default `EPSG:3005` BC Albers).
#'
#' Plots lacking both valid decimal degrees and projectable NAD83 UTM
#' coordinates are excluded from the returned point layer and listed in
#' `attr(result, "missing_coords")`.
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param scope Plot scope: `"su"` (active `ws$su` when set) or `"project"`.
#' @param crs Target coordinate reference system passed to [sf::st_transform()]
#'   (default `3005` for NAD83 / BC Albers).
#' @param audit_geodesy Logical; if `TRUE` (default), computes NAD83 ellipsoidal
#'   distance (`utm_dd_divergence_m`) and flags `utm_dd_divergent` (`> 250 m`)
#'   on plots carrying both decimal degrees and UTM coordinates.
#' @param exclude_modifiers Logical; if `TRUE`, excludes `.support`, `.poor`,
#'   and `.nudum` site units.
#' @param columns Either `"core"` (default curated spatial/BEC/quality columns
#'   for fast GIS export), `"all"` (all 130+ `_Env` + `_Admin` columns), or an
#'   explicit character vector of column names.
#' @return An `sf` `POINT` object in `crs` with `sign_flipped`, `utm_backfilled`,
#'   `utm_dd_divergence_m`, `utm_dd_divergent`, `geodesy_flag`, and
#'   `bcgs_mapsheet_20k` columns, plus `attr(sf_obj, "missing_coords")`.
#' @export
vpro_sf <- function(
  ws,
  scope = c("su", "project"),
  crs = 3005,
  audit_geodesy = TRUE,
  exclude_modifiers = FALSE,
  columns = "core"
) {
  vpro_assert_workspace(ws)
  rlang::check_installed("sf", reason = "to build spatial `sf` plot layers and transform CRS.")
  scope <- match.arg(scope)

  if (!is.logical(audit_geodesy) || length(audit_geodesy) != 1L || is.na(audit_geodesy)) {
    cli::cli_abort("`audit_geodesy` must be TRUE or FALSE.", class = c("vpro_error_spatial", "vpro_error"))
  }
  if (!is.logical(exclude_modifiers) || length(exclude_modifiers) != 1L || is.na(exclude_modifiers)) {
    cli::cli_abort("`exclude_modifiers` must be TRUE or FALSE.", class = c("vpro_error_spatial", "vpro_error"))
  }

  col_proj <- if (identical(columns, "all") || is.null(columns)) {
    NULL
  } else if (identical(columns, "core")) {
    .vpro_spatial_core_cols
  } else {
    unique(c("PlotNumber", "Longitude", "Latitude", "UTMZone", "UTMEasting", "UTMNorthing", as.character(columns)))
  }

  env <- vpro_env(ws, scope = scope, exclude_modifiers = exclude_modifiers, columns = col_proj)
  env[["PlotNumber"]] <- as.character(env[["PlotNumber"]])
  n <- nrow(env)

  if (n == 0L) {
    env[["sign_flipped"]] <- logical()
    env[["utm_backfilled"]] <- logical()
    env[["utm_dd_divergence_m"]] <- numeric()
    env[["utm_dd_divergent"]] <- logical()
    env[["geodesy_flag"]] <- character()
    env[["bcgs_mapsheet_20k"]] <- character()
    empty_sf <- sf::st_sf(env, geometry = sf::st_sfc(crs = 4269))
    empty_sf <- sf::st_transform(empty_sf, crs = crs)
    attr(empty_sf, "missing_coords") <- character()
    return(empty_sf)
  }

  lat_raw <- if ("Latitude" %in% names(env)) suppressWarnings(as.double(env[["Latitude"]])) else rep(NA_real_, n)
  lon_raw <- if ("Longitude" %in% names(env)) suppressWarnings(as.double(env[["Longitude"]])) else rep(NA_real_, n)

  dd_finite <- !is.na(lat_raw) &
    !is.na(lon_raw) &
    is.finite(lat_raw) &
    is.finite(lon_raw) &
    !(lat_raw == 0 & lon_raw == 0) &
    lat_raw >= -90.0 &
    lat_raw <= 90.0 &
    lon_raw >= -180.0 &
    lon_raw <= 180.0

  sign_flipped <- dd_finite & lon_raw > 0.0 & lon_raw >= 110.0 & lon_raw <= 145.0
  lat_dd <- ifelse(dd_finite, lat_raw, NA_real_)
  lon_dd <- ifelse(dd_finite, ifelse(sign_flipped, -lon_raw, lon_raw), NA_real_)
  has_dd <- dd_finite

  zone_int <- if ("UTMZone" %in% names(env)) vpro_parse_utm_zone(env[["UTMZone"]]) else rep(NA_integer_, n)
  east_raw <- if ("UTMEasting" %in% names(env)) suppressWarnings(as.double(env[["UTMEasting"]])) else rep(NA_real_, n)
  north_raw <- if ("UTMNorthing" %in% names(env)) suppressWarnings(as.double(env[["UTMNorthing"]])) else rep(NA_real_, n)

  has_utm <- !is.na(zone_int) &
    zone_int >= 7L &
    zone_int <= 11L &
    !is.na(east_raw) &
    is.finite(east_raw) &
    east_raw >= 100000.0 &
    east_raw <= 900000.0 &
    !is.na(north_raw) &
    is.finite(north_raw) &
    north_raw > 0.0 &
    north_raw <= 10000000.0

  utm_lat <- rep(NA_real_, n)
  utm_lon <- rep(NA_real_, n)

  # Project NAD83 UTM zones 7..11 (EPSG:26907..26911) to NAD83 geographic (EPSG:4269) via C++ PROJ matrix projection
  need_utm_proj <- if (isTRUE(audit_geodesy)) has_utm else (has_utm & !has_dd)
  if (any(need_utm_proj)) {
    crs_4269_wkt <- sf::st_crs(4269L)$wkt
    for (z in sort(unique(zone_int[need_utm_proj]))) {
      idx <- which(need_utm_proj & zone_int == z)
      xy <- sf::sf_project(
        from = sf::st_crs(26900L + as.integer(z))$wkt,
        to = crs_4269_wkt,
        pts = cbind(east_raw[idx], north_raw[idx]),
        keep = TRUE
      )
      utm_lon[idx] <- as.double(xy[, 1L])
      utm_lat[idx] <- as.double(xy[, 2L])
    }
  }

  utm_backfilled <- !has_dd & has_utm & !is.na(utm_lat) & !is.na(utm_lon)
  final_lat <- ifelse(has_dd, lat_dd, ifelse(utm_backfilled, utm_lat, NA_real_))
  final_lon <- ifelse(has_dd, lon_dd, ifelse(utm_backfilled, utm_lon, NA_real_))

  utm_dd_divergence_m <- rep(NA_real_, n)
  utm_dd_divergent <- rep(FALSE, n)

  if (isTRUE(audit_geodesy)) {
    both_idx <- which(has_dd & has_utm & !is.na(utm_lat) & !is.na(utm_lon))
    if (length(both_idx) > 0L) {
      # Vectorised GRS80 (NAD83) ellipsoidal arc distance in metres (a = 6378137, f = 1/298.257222101)
      rad <- pi / 180.0
      lat1 <- lat_dd[both_idx] * rad
      lat2 <- utm_lat[both_idx] * rad
      phi_m <- 0.5 * (lat1 + lat2)
      dphi <- lat2 - lat1
      dlam <- (utm_lon[both_idx] - lon_dd[both_idx]) * rad
      a_grs80 <- 6378137.0
      f_grs80 <- 1.0 / 298.257222101
      e2 <- 2.0 * f_grs80 - f_grs80^2
      w_term <- sqrt(1.0 - e2 * sin(phi_m)^2)
      m_rad <- a_grs80 * (1.0 - e2) / (w_term^3)
      n_rad <- a_grs80 / w_term
      # Use exact geodesic via sf::st_distance only for large (>20 km) separations where local curvature approx drifts
      d_m <- sqrt((m_rad * dphi)^2 + (n_rad * cos(phi_m) * dlam)^2)
      far <- which(d_m > 20000.0)
      if (length(far) > 0L) {
        a_hav <- sin(dphi[far] * 0.5)^2 + cos(lat1[far]) * cos(lat2[far]) * sin(dlam[far] * 0.5)^2
        d_m[far] <- 2.0 * 6371008.8 * asin(pmin(1.0, sqrt(a_hav)))
      }
      utm_dd_divergence_m[both_idx] <- d_m
      utm_dd_divergent[both_idx] <- !is.na(d_m) & d_m > 250.0
    }
  }

  geodesy_flag <- rep("ok", n)
  flagged <- which(sign_flipped | utm_backfilled | utm_dd_divergent)
  if (length(flagged) > 0L) {
    geodesy_flag[flagged] <- vapply(
      flagged,
      function(i) {
        flags <- character()
        if (sign_flipped[[i]]) {
          flags <- c(flags, "sign_flipped")
        }
        if (utm_backfilled[[i]]) {
          flags <- c(flags, "utm_backfilled")
        }
        if (utm_dd_divergent[[i]]) {
          flags <- c(flags, "utm_dd_divergent")
        }
        paste(flags, collapse = ",")
      },
      character(1)
    )
  }

  env[["Latitude"]] <- final_lat
  env[["Longitude"]] <- final_lon
  env[["sign_flipped"]] <- sign_flipped
  env[["utm_backfilled"]] <- utm_backfilled
  env[["utm_dd_divergence_m"]] <- utm_dd_divergence_m
  env[["utm_dd_divergent"]] <- utm_dd_divergent
  env[["geodesy_flag"]] <- geodesy_flag
  env[["bcgs_mapsheet_20k"]] <- vpro_bcgs_mapsheet_20k(final_lat, final_lon)

  has_coords <- !is.na(final_lat) & !is.na(final_lon) & is.finite(final_lat) & is.finite(final_lon)
  missing_coords <- as.character(env[["PlotNumber"]][!has_coords])

  coord_df <- env[has_coords, , drop = FALSE]
  rownames(coord_df) <- NULL

  target_crs <- sf::st_crs(crs)
  is_3d_crs <- grepl("geocentric|AXIS\\[\"\\([Zz]\\)\"", ifelse(is.na(target_crs$wkt), "", target_crs$wkt), ignore.case = TRUE)
  if (nrow(coord_df) == 0L) {
    sf_out <- sf::st_transform(sf::st_sf(coord_df, geometry = sf::st_sfc(crs = 4269L)), crs = target_crs)
  } else if (is_3d_crs) {
    sf_out <- sf::st_transform(
      sf::st_as_sf(coord_df, coords = c("Longitude", "Latitude"), crs = 4269L, remove = FALSE),
      crs = target_crs
    )
  } else {
    pts_lonlat <- cbind(coord_df[["Longitude"]], coord_df[["Latitude"]])
    pts_target <- if (identical(target_crs, sf::st_crs(4269L))) {
      pts_lonlat
    } else {
      sf::sf_project(
        from = sf::st_crs(4269L)$wkt,
        to = target_crs$wkt,
        pts = pts_lonlat,
        keep = TRUE
      )
    }
    if (ncol(pts_target) == 2L && all(is.finite(pts_target[, 1L]) & is.finite(pts_target[, 2L]))) {
      coord_df[[".__x"]] <- as.double(pts_target[, 1L])
      coord_df[[".__y"]] <- as.double(pts_target[, 2L])
      sf_out <- sf::st_as_sf(
        coord_df,
        coords = c(".__x", ".__y"),
        crs = target_crs,
        remove = TRUE
      )
    } else {
      sf_out <- sf::st_transform(
        sf::st_as_sf(coord_df, coords = c("Longitude", "Latitude"), crs = 4269L, remove = FALSE),
        crs = target_crs
      )
    }
  }
  attr(sf_out, "missing_coords") <- missing_coords
  sf_out
}

#' Export a multi-layer VPro OGC GeoPackage (`.gpkg`) for QGIS and GIS workflows
#'
#' Writes a standardized 5-layer OGC GeoPackage containing spatial `plots`
#' ([vpro_sf()]) alongside non-spatial relational attribute tables (`veg`,
#' `soil_humus`, `soil_mineral`, and `site_units`) preserving literal character
#' `PlotNumber` keys for instant joins in QGIS, ArcGIS, or [sf::st_read()].
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param path Destination `.gpkg` file path.
#' @param crs Target coordinate reference system for the `plots` point layer
#'   (default `3005` NAD83 / BC Albers).
#' @param scope Plot scope: `"su"` or `"project"`.
#' @param overwrite Logical; if `TRUE` (default), replaces an existing `.gpkg`
#'   at `path`. If `FALSE` and `path` exists, aborts with an error.
#' @return The normalized GeoPackage file path, invisibly.
#' @export
vpro_export_gpkg <- function(
  ws,
  path,
  crs = 3005,
  scope = c("su", "project"),
  overwrite = TRUE
) {
  vpro_assert_workspace(ws)
  rlang::check_installed("sf", reason = "to write multi-layer OGC GeoPackage files.")
  scope <- match.arg(scope)

  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    cli::cli_abort("`path` must be a single non-empty `.gpkg` file path.", class = c("vpro_error_spatial", "vpro_error"))
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    cli::cli_abort("`overwrite` must be TRUE or FALSE.", class = c("vpro_error_spatial", "vpro_error"))
  }

  out_path <- vpro_abs_path(trimws(path))
  parent_dir <- dirname(out_path)
  if (!dir.exists(parent_dir)) {
    dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (file.exists(out_path)) {
    if (!isTRUE(overwrite)) {
      cli::cli_abort(.vpro_cli_escape(paste0("GeoPackage already exists and `overwrite = FALSE`: ", out_path)), class = c("vpro_error_spatial", "vpro_error"))
    }
    unlink(c(out_path, paste0(out_path, "-wal"), paste0(out_path, "-shm")))
  }

  plots_sf <- vpro_sf(ws, scope = scope, crs = crs)
  veg_tbl <- vpro_veg(ws, scope = scope, strata = "raw", lump = FALSE)
  soil_bundle <- vpro_soil(ws, scope = scope, type = "both")
  su_tbl <- vpro_site_units(ws)
  if (identical(scope, "su") && !is.null(ws$su)) {
    # vpro_site_units already reflects active ws$su
    su_tbl[["PlotNumber"]] <- as.character(su_tbl[["PlotNumber"]])
  }

  sf::st_write(
    plots_sf,
    dsn = out_path,
    layer = "plots",
    driver = "GPKG",
    delete_dsn = TRUE,
    quiet = TRUE
  )
  sf::st_write(
    as.data.frame(veg_tbl, stringsAsFactors = FALSE),
    dsn = out_path,
    layer = "veg",
    driver = "GPKG",
    append = TRUE,
    quiet = TRUE
  )
  sf::st_write(
    as.data.frame(soil_bundle$humus, stringsAsFactors = FALSE),
    dsn = out_path,
    layer = "soil_humus",
    driver = "GPKG",
    append = TRUE,
    quiet = TRUE
  )
  sf::st_write(
    as.data.frame(soil_bundle$mineral, stringsAsFactors = FALSE),
    dsn = out_path,
    layer = "soil_mineral",
    driver = "GPKG",
    append = TRUE,
    quiet = TRUE
  )
  sf::st_write(
    as.data.frame(su_tbl, stringsAsFactors = FALSE),
    dsn = out_path,
    layer = "site_units",
    driver = "GPKG",
    append = TRUE,
    quiet = TRUE
  )

  invisible(normalizePath(out_path, winslash = "/", mustWork = TRUE))
}
