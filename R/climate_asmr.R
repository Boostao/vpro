# Plot Climate Cache (`__VPRO_PlotClimate`), `climr` & Ministry `CMD -> aSMR` --

.vpro_plot_climate_ddl <- paste(
  'CREATE TABLE IF NOT EXISTS main."__VPRO_PlotClimate" (',
  '  "PlotNumber" TEXT PRIMARY KEY,',
  '  "CoordElevHash" TEXT NOT NULL,',
  '  "RefPeriod" TEXT NOT NULL,',
  '  "Source" TEXT NOT NULL,',
  '  "MAT" REAL,',
  '  "MWMT" REAL,',
  '  "MCMT" REAL,',
  '  "MAP" REAL,',
  '  "MSP" REAL,',
  '  "PAS" REAL,',
  '  "CMD" REAL,',
  '  "PPT_05" REAL,',
  '  "PPT_06" REAL,',
  '  "PPT_07" REAL,',
  '  "PPT_08" REAL,',
  '  "PPT_09" REAL,',
  '  "PPT_at" REAL,',
  '  "PPT_wt" REAL,',
  '  "DD5" REAL,',
  '  "NFFD" REAL,',
  '  "ComputedAt" TEXT NOT NULL',
  ')'
)

.vpro_plot_climate_cols <- c(
  "PlotNumber", "CoordElevHash", "RefPeriod", "Source",
  "MAT", "MWMT", "MCMT", "MAP", "MSP", "PAS", "CMD",
  "PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",
  "PPT_at", "PPT_wt", "DD5", "NFFD", "ComputedAt"
)

.vpro_sha256_K_hex <- c(
  "428a2f98", "71374491", "b5c0fbcf", "e9b5dba5", "3956c25b", "59f111f1", "923f82a4", "ab1c5ed5",
  "d807aa98", "12835b01", "243185be", "550c7dc3", "72be5d74", "80deb1fe", "9bdc06a7", "c19bf174",
  "e49b69c1", "efbe4786", "0fc19dc6", "240ca1cc", "2de92c6f", "4a7484aa", "5cb0a9dc", "76f988da",
  "983e5152", "a831c66d", "b00327c8", "bf597fc7", "c6e00bf3", "d5a79147", "06ca6351", "14292967",
  "27b70a85", "2e1b2138", "4d2c6dfc", "53380d13", "650a7354", "766a0abb", "81c2c92e", "92722c85",
  "a2bfe8a1", "a81a664b", "c24b8b70", "c76c51a3", "d192e819", "d6990624", "f40e3585", "106aa070",
  "19a4c116", "1e376c08", "2748774c", "34b0bcb5", "391c0cb3", "4ed8aa4a", "5b9cca4f", "682e6ff3",
  "748f82ee", "78a5636f", "84c87814", "8cc70208", "90befffa", "a4506ceb", "bef9a3f7", "c67178f2"
)

.vpro_sha256_H0_hex <- c(
  "6a09e667", "bb67ae85", "3c6ef372", "a54ff53a",
  "510e527f", "9b05688c", "1f83d9ab", "5be0cd19"
)

.vpro_sha256_K_hi <- strtoi(substr(.vpro_sha256_K_hex, 1L, 4L), 16L)
.vpro_sha256_K_lo <- strtoi(substr(.vpro_sha256_K_hex, 5L, 8L), 16L)
.vpro_sha256_H0_hi <- strtoi(substr(.vpro_sha256_H0_hex, 1L, 4L), 16L)
.vpro_sha256_H0_lo <- strtoi(substr(.vpro_sha256_H0_hex, 5L, 8L), 16L)

# Vectorized pure-R SHA-256 over raw byte vectors using 16-bit half-words so
# R's signed 32-bit NA_integer_ (0x80000000) can never occur.
vpro_sha256_raw_list <- function(raw_list) {
  n <- length(raw_list)
  if (n == 0L) {
    return(character())
  }

  rotr32 <- function(hi, lo, k) {
    if (k < 16L) {
      nhi <- bitwOr(bitwShiftR(hi, k), bitwAnd(bitwShiftL(lo, 16L - k), 65535L))
      nlo <- bitwOr(bitwShiftR(lo, k), bitwAnd(bitwShiftL(hi, 16L - k), 65535L))
    } else if (k == 16L) {
      nhi <- lo
      nlo <- hi
    } else {
      s <- k - 16L
      nhi <- bitwOr(bitwShiftR(lo, s), bitwAnd(bitwShiftL(hi, 16L - s), 65535L))
      nlo <- bitwOr(bitwShiftR(hi, s), bitwAnd(bitwShiftL(lo, 16L - s), 65535L))
    }
    list(nhi, nlo)
  }

  shr32 <- function(hi, lo, k) {
    if (k < 16L) {
      nhi <- bitwShiftR(hi, k)
      nlo <- bitwOr(bitwShiftR(lo, k), bitwAnd(bitwShiftL(hi, 16L - k), 65535L))
    } else {
      s <- k - 16L
      nhi <- integer(length(hi))
      nlo <- bitwShiftR(hi, s)
    }
    list(nhi, nlo)
  }

  add2 <- function(a, b) {
    slo <- a[[2L]] + b[[2L]]
    shi <- bitwAnd(a[[1L]] + b[[1L]] + bitwShiftR(slo, 16L), 65535L)
    list(shi, bitwAnd(slo, 65535L))
  }

  add_many <- function(...) {
    args <- list(...)
    slo <- args[[1L]][[2L]]
    shi <- args[[1L]][[1L]]
    for (i in 2L:length(args)) {
      slo <- slo + args[[i]][[2L]]
      shi <- shi + args[[i]][[1L]]
    }
    shi <- bitwAnd(shi + bitwShiftR(slo, 16L), 65535L)
    list(shi, bitwAnd(slo, 65535L))
  }

  xor3 <- function(a, b, c) {
    list(
      bitwXor(bitwXor(a[[1L]], b[[1L]]), c[[1L]]),
      bitwXor(bitwXor(a[[2L]], b[[2L]]), c[[2L]])
    )
  }

  lens <- lengths(raw_list)
  nblocks <- (lens + 9L + 63L) %/% 64L
  out_hex <- character(n)

  for (nb in unique(nblocks)) {
    idx <- which(nblocks == nb)
    m <- length(idx)
    total_bytes <- nb * 64L
    mat <- matrix(0L, nrow = m, ncol = total_bytes)
    for (r in seq_len(m)) {
      b <- as.integer(raw_list[[idx[[r]]]])
      blen <- length(b)
      if (blen > 0L) {
        mat[r, seq_len(blen)] <- b
      }
      mat[r, blen + 1L] <- 128L
      bit_len <- as.double(blen) * 8.0
      hi_bits <- floor(bit_len / 4294967296.0)
      lo_bits <- bit_len - hi_bits * 4294967296.0
      for (k in 0L:3L) {
        mat[r, total_bytes - 7L + k] <- as.integer(floor(hi_bits / (256.0^(3L - k))) %% 256.0)
        mat[r, total_bytes - 3L + k] <- as.integer(floor(lo_bits / (256.0^(3L - k))) %% 256.0)
      }
    }

    H <- lapply(1L:8L, function(j) {
      list(rep.int(.vpro_sha256_H0_hi[[j]], m), rep.int(.vpro_sha256_H0_lo[[j]], m))
    })

    for (blk in seq_len(nb)) {
      base_col <- (blk - 1L) * 64L
      W <- vector("list", 64L)
      for (t in 1L:16L) {
        c0 <- base_col + (t - 1L) * 4L
        W[[t]] <- list(
          bitwOr(bitwShiftL(mat[, c0 + 1L], 8L), mat[, c0 + 2L]),
          bitwOr(bitwShiftL(mat[, c0 + 3L], 8L), mat[, c0 + 4L])
        )
      }
      for (t in 17L:64L) {
        w15 <- W[[t - 15L]]
        s0 <- xor3(
          rotr32(w15[[1L]], w15[[2L]], 7L),
          rotr32(w15[[1L]], w15[[2L]], 18L),
          shr32(w15[[1L]], w15[[2L]], 3L)
        )
        w2 <- W[[t - 2L]]
        s1 <- xor3(
          rotr32(w2[[1L]], w2[[2L]], 17L),
          rotr32(w2[[1L]], w2[[2L]], 19L),
          shr32(w2[[1L]], w2[[2L]], 10L)
        )
        W[[t]] <- add_many(W[[t - 16L]], s0, W[[t - 7L]], s1)
      }

      a <- H[[1L]]
      b <- H[[2L]]
      cc <- H[[3L]]
      d <- H[[4L]]
      e <- H[[5L]]
      f <- H[[6L]]
      g <- H[[7L]]
      h <- H[[8L]]

      for (t in 1L:64L) {
        S1 <- xor3(
          rotr32(e[[1L]], e[[2L]], 6L),
          rotr32(e[[1L]], e[[2L]], 11L),
          rotr32(e[[1L]], e[[2L]], 25L)
        )
        ch <- list(
          bitwXor(bitwAnd(e[[1L]], f[[1L]]), bitwAnd(bitwAnd(bitwNot(e[[1L]]), 65535L), g[[1L]])),
          bitwXor(bitwAnd(e[[2L]], f[[2L]]), bitwAnd(bitwAnd(bitwNot(e[[2L]]), 65535L), g[[2L]]))
        )
        Kt <- list(rep.int(.vpro_sha256_K_hi[[t]], m), rep.int(.vpro_sha256_K_lo[[t]], m))
        temp1 <- add_many(h, S1, ch, Kt, W[[t]])
        S0 <- xor3(
          rotr32(a[[1L]], a[[2L]], 2L),
          rotr32(a[[1L]], a[[2L]], 13L),
          rotr32(a[[1L]], a[[2L]], 22L)
        )
        maj <- list(
          bitwXor(bitwXor(bitwAnd(a[[1L]], b[[1L]]), bitwAnd(a[[1L]], cc[[1L]])), bitwAnd(b[[1L]], cc[[1L]])),
          bitwXor(bitwXor(bitwAnd(a[[2L]], b[[2L]]), bitwAnd(a[[2L]], cc[[2L]])), bitwAnd(b[[2L]], cc[[2L]]))
        )
        temp2 <- add2(S0, maj)

        h <- g
        g <- f
        f <- e
        e <- add2(d, temp1)
        d <- cc
        cc <- b
        b <- a
        a <- add2(temp1, temp2)
      }

      H[[1L]] <- add2(H[[1L]], a)
      H[[2L]] <- add2(H[[2L]], b)
      H[[3L]] <- add2(H[[3L]], cc)
      H[[4L]] <- add2(H[[4L]], d)
      H[[5L]] <- add2(H[[5L]], e)
      H[[6L]] <- add2(H[[6L]], f)
      H[[7L]] <- add2(H[[7L]], g)
      H[[8L]] <- add2(H[[8L]], h)
    }

    parts <- lapply(H, function(w) sprintf("%04x%04x", w[[1L]], w[[2L]]))
    out_hex[idx] <- do.call(paste0, parts)
  }

  out_hex
}

vpro_sha256_utf8 <- function(x) {
  if (is.raw(x)) {
    return(vpro_sha256_raw_list(list(x)))
  }
  chr <- as.character(x)
  out <- rep(NA_character_, length(chr))
  ok <- !is.na(chr)
  if (any(ok)) {
    raws <- lapply(enc2utf8(chr[ok]), charToRaw)
    out[ok] <- vpro_sha256_raw_list(raws)
  }
  out
}

vpro_go_round <- function(x) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    v <- as.double(x[ok])
    av <- abs(v)
    fl <- floor(av)
    r <- ifelse((av - fl) >= 0.5, fl + 1.0, fl) * ifelse(v < 0.0, -1.0, 1.0)
    r[r == 0.0] <- 0.0
    out[ok] <- r
  }
  out
}

vpro_normalize_bc_lon <- function(lon) {
  out <- as.double(lon)
  flip <- !is.na(out) & is.finite(out) & out >= 110.0 & out <= 145.0
  out[flip] <- -out[flip]
  out
}

vpro_normalize_ref_period <- function(ref_period) {
  if (is.null(ref_period) || length(ref_period) == 0L || is.na(ref_period[[1L]]) || !nzchar(trimws(as.character(ref_period[[1L]])))) {
    return("1961_1990")
  }
  if (!is.character(ref_period) || length(ref_period) != 1L) {
    rlang::abort("`ref_period` must be a single character string ('1961_1990' or '1991_2020').")
  }
  norm <- gsub("-", "_", trimws(ref_period), fixed = TRUE)
  if (!(norm %in% c("1961_1990", "1991_2020"))) {
    rlang::abort(paste0(
      "Unsupported climate reference period `", ref_period,
      "` (expected '1961_1990' or '1991_2020')."
    ))
  }
  norm
}

#' Compute deterministic 128-bit `CoordElevHash` matching `vpro_wails`
#'
#' Normalizes legacy positive B.C. western longitudes (`110..145` -> `-lon`),
#' formats `sprintf("%.5f|%.5f|%.1f|%s", round(lat, 5), round(lon, 5), round(elev, 1), ref_period)`
#' using Go half-away-from-zero rounding, hashes UTF-8 bytes with vectorized
#' pure-R SHA-256, and returns the first 32 lowercase hexadecimal characters
#' (`sha256.Sum256([]byte(...))[:16]`).
#'
#' @param lat Numeric latitude(s) in decimal degrees.
#' @param lon Numeric longitude(s) in decimal degrees (positive B.C. longitudes
#'   in `[110, 145]` are normalized to negative western degrees).
#' @param elev Numeric elevation(s) in metres.
#' @param ref_period Reference normal period (`"1961_1990"` or `"1991_2020"`).
#' @return Character vector of 32-character lowercase hexadecimal digests (`NA`
#'   where coordinates or elevation are missing/non-finite).
#' @export
vpro_coord_elev_hash <- function(lat, lon, elev, ref_period = "1961_1990") {
  vals <- vpro_value_recycle(list(
    lat = as.double(lat),
    lon = as.double(lon),
    elev = as.double(elev)
  ))
  if (length(ref_period) == 1L) {
    rp <- rep(vpro_normalize_ref_period(ref_period), length(vals$lat))
  } else if (length(ref_period) == length(vals$lat)) {
    rp <- vapply(ref_period, vpro_normalize_ref_period, character(1))
  } else {
    rlang::abort("`ref_period` must have length 1 or match the coordinate vector length.")
  }

  n <- length(vals$lat)
  out <- rep(NA_character_, n)
  norm_lon <- vpro_normalize_bc_lon(vals$lon)
  ok <- !is.na(vals$lat) & is.finite(vals$lat) &
    !is.na(norm_lon) & is.finite(norm_lon) &
    !is.na(vals$elev) & is.finite(vals$elev) &
    !is.na(rp) & nzchar(rp)

  if (any(ok)) {
    lat5 <- vpro_go_round(vals$lat[ok] * 1e5) / 1e5
    lon5 <- vpro_go_round(norm_lon[ok] * 1e5) / 1e5
    elev1 <- vpro_go_round(vals$elev[ok] * 10.0) / 10.0
    lat5[lat5 == 0.0] <- 0.0
    lon5[lon5 == 0.0] <- 0.0
    elev1[elev1 == 0.0] <- 0.0
    canonical <- sprintf("%.5f|%.5f|%.1f|%s", lat5, lon5, elev1, rp[ok])
    out[ok] <- substr(vpro_sha256_utf8(canonical), 1L, 32L)
  }
  out
}

vpro_load_asmr_assets <- function() {
  cached <- .vpro_cache[["asmr_assets"]]
  if (!is.null(cached)) {
    return(cached)
  }
  rules_dt <- data.table::fread(vpro_bundled_file("extdata", "aSMR_Rules_HalfStep.csv"))
  cmd_adj_dt <- data.table::fread(vpro_bundled_file("extdata", "CMD_adjustments.csv"))
  bgc_norm_dt <- data.table::fread(vpro_bundled_file("extdata", "bgc_climate_normals.csv"))
  bundle <- list(
    rules = rules_dt,
    cmd_adj = cmd_adj_dt,
    bgc_normals = bgc_norm_dt
  )
  .vpro_cache[["asmr_assets"]] <- bundle
  bundle
}

vpro_parse_rsmr_digit <- function(x) {
  chr <- ifelse(is.na(x), "", trimws(as.character(x)))
  has_dig <- grepl("[0-8]", chr)
  out <- rep(NA_integer_, length(chr))
  if (any(has_dig)) {
    extracted <- sub("^[^0-8]*([0-8]).*$", "\\1", chr[has_dig])
    out[has_dig] <- suppressWarnings(as.integer(extracted))
  }
  out
}

vpro_normalize_rsnr <- function(x) {
  chr <- toupper(ifelse(is.na(x), "", trimws(as.character(x))))
  has_let <- grepl("[A-F]", chr)
  out <- rep(NA_character_, length(chr))
  if (any(has_let)) {
    let <- sub("^[^A-F]*([A-F]).*$", "\\1", chr[has_let])
    let[let == "F"] <- "E"
    out[has_let] <- let
  }
  out
}

vpro_read_plot_climate_cache <- function(db_path) {
  empty <- tibble::tibble(
    PlotNumber = character(),
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
  if (!file.exists(db_path)) {
    return(empty)
  }
  dbc <- vpro_sqlite_ro(db_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  if (!DBI::dbExistsTable(dbc, "__VPRO_PlotClimate")) {
    return(empty)
  }
  df <- DBI::dbGetQuery(
    dbc,
    paste(
      'SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber",',
      'CAST("CoordElevHash" AS TEXT) AS "CoordElevHash",',
      'CAST("RefPeriod" AS TEXT) AS "RefPeriod",',
      'CAST("Source" AS TEXT) AS "Source",',
      'CAST("MAT" AS REAL) AS "MAT",',
      'CAST("MWMT" AS REAL) AS "MWMT",',
      'CAST("MCMT" AS REAL) AS "MCMT",',
      'CAST("MAP" AS REAL) AS "MAP",',
      'CAST("MSP" AS REAL) AS "MSP",',
      'CAST("PAS" AS REAL) AS "PAS",',
      'CAST("CMD" AS REAL) AS "CMD",',
      'CAST("PPT_05" AS REAL) AS "PPT_05",',
      'CAST("PPT_06" AS REAL) AS "PPT_06",',
      'CAST("PPT_07" AS REAL) AS "PPT_07",',
      'CAST("PPT_08" AS REAL) AS "PPT_08",',
      'CAST("PPT_09" AS REAL) AS "PPT_09",',
      'CAST("PPT_at" AS REAL) AS "PPT_at",',
      'CAST("PPT_wt" AS REAL) AS "PPT_wt",',
      'CAST("DD5" AS REAL) AS "DD5",',
      'CAST("NFFD" AS REAL) AS "NFFD",',
      'CAST("ComputedAt" AS TEXT) AS "ComputedAt"',
      'FROM main."__VPRO_PlotClimate"',
      'WHERE typeof("PlotNumber") = \'text\''
    )
  )
  if (nrow(df) == 0L) {
    return(empty)
  }
  df$PlotNumber <- as.character(df$PlotNumber)
  tibble::as_tibble(df)
}

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
    lon = as.double(pts_df$lon),
    lat = as.double(pts_df$lat),
    elev = as.double(pts_df$elev)
  )
  vars_req <- c(
    "MAT", "MWMT", "MCMT", "MAP", "MSP", "PAS_an", "CMD_an",
    "PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",
    "PPT_at", "PPT_wt", "DD5_an", "NFFD_an"
  )
  dl <- tryCatch({
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
  }, error = function(e) NULL)

  if (is.null(dl) || nrow(dl) < nrow(pts_df)) {
    return(NULL)
  }
  dl_dt <- data.table::as.data.table(dl)
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
    "Latitude", "Longitude", "Elevation", "MAT", "MWMT", "MCMT", "MAP", "MSP",
    "PAS", "CMD", "PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",
    "PPT_at", "PPT_wt", "DD5", "NFFD"
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

#' Persist plot climate normals to `__VPRO_PlotClimate` atomically
#'
#' Writes or updates plot climate rows inside `main."__VPRO_PlotClimate"` and
#' appends provenance to `main."__VPRO_RSidecarHistory"` inside a single
#' `BEGIN IMMEDIATE` WAL transaction, preserving literal character `PlotNumber`
#' keys (`typeof("PlotNumber") = 'text'`).
#'
#' @param con A `vpro_workspace` handle referencing a writable user `.db`.
#' @param climate_df Data frame containing `__VPRO_PlotClimate` columns (as
#'   returned by [vpro_climate()]).
#' @return Invisibly returns the written `__VPRO_PlotClimate` tibble.
#' @export
vpro_cache_climate <- function(con, climate_df) {
  vpro_assert_workspace(con)
  vpro_assert_writable_project_db(con$project_path, con = con)

  if (!is.data.frame(climate_df)) {
    rlang::abort("`climate_df` must be a `data.frame` of plot climate records.")
  }

  req_cols <- setdiff(.vpro_plot_climate_cols, "ComputedAt")
  missing_cols <- setdiff(req_cols, names(climate_df))
  if (length(missing_cols) > 0L) {
    rlang::abort(paste0(
      "`climate_df` is missing required `__VPRO_PlotClimate` columns: ",
      paste(missing_cols, collapse = ", ")
    ))
  }

  if (nrow(climate_df) == 0L) {
    vpro_with_immediate_tx(con$project_path, con = con, fn = function(dbc) {
      DBI::dbExecute(dbc, .vpro_plot_climate_ddl)
      vpro_append_rsidecar_history_in_tx(
        dbc,
        action = "CachePlotClimate",
        details = list(rows = 0L)
      )
    })
    return(invisible(tibble::as_tibble(climate_df[, intersect(.vpro_plot_climate_cols, names(climate_df)), drop = FALSE])))
  }

  vpro_validate_plot_numbers_strict(climate_df$PlotNumber, "PlotNumber")
  hashes <- tolower(trimws(as.character(climate_df$CoordElevHash)))
  if (anyNA(hashes) || any(!grepl("^[0-9a-f]{32}$", hashes))) {
    rlang::abort("`CoordElevHash` must be a 32-character hexadecimal SHA-256 prefix.")
  }
  ref_periods <- vapply(climate_df$RefPeriod, vpro_normalize_ref_period, character(1))
  sources <- trimws(as.character(climate_df$Source))
  if (anyNA(sources) || any(!nzchar(sources))) {
    rlang::abort("`Source` must be non-empty for every `__VPRO_PlotClimate` row.")
  }

  now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  comp_at <- if ("ComputedAt" %in% names(climate_df)) {
    ca <- trimws(as.character(climate_df$ComputedAt))
    ifelse(is.na(ca) | !nzchar(ca), now_iso, ca)
  } else {
    rep(now_iso, nrow(climate_df))
  }

  num_cols <- c(
    "MAT", "MWMT", "MCMT", "MAP", "MSP", "PAS", "CMD",
    "PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",
    "PPT_at", "PPT_wt", "DD5", "NFFD"
  )
  clean_tbl <- tibble::tibble(
    PlotNumber = climate_df$PlotNumber,
    CoordElevHash = hashes,
    RefPeriod = ref_periods,
    Source = sources,
    MAT = as.double(climate_df$MAT),
    MWMT = as.double(climate_df$MWMT),
    MCMT = as.double(climate_df$MCMT),
    MAP = as.double(climate_df$MAP),
    MSP = as.double(climate_df$MSP),
    PAS = as.double(climate_df$PAS),
    CMD = as.double(climate_df$CMD),
    PPT_05 = as.double(climate_df$PPT_05),
    PPT_06 = as.double(climate_df$PPT_06),
    PPT_07 = as.double(climate_df$PPT_07),
    PPT_08 = as.double(climate_df$PPT_08),
    PPT_09 = as.double(climate_df$PPT_09),
    PPT_at = as.double(climate_df$PPT_at),
    PPT_wt = as.double(climate_df$PPT_wt),
    DD5 = as.double(climate_df$DD5),
    NFFD = as.double(climate_df$NFFD),
    ComputedAt = comp_at
  )
  for (nc in num_cols) {
    v <- clean_tbl[[nc]]
    v[!is.finite(v)] <- NA_real_
    clean_tbl[[nc]] <- v
  }

  vpro_with_immediate_tx(con$project_path, con = con, fn = function(dbc) {
    DBI::dbExecute(dbc, .vpro_plot_climate_ddl)
    DBI::dbExecute(
      dbc,
      'DELETE FROM main."__VPRO_PlotClimate" WHERE typeof("PlotNumber") = \'text\' AND CAST("PlotNumber" AS BLOB) = CAST(? AS BLOB)',
      params = list(clean_tbl$PlotNumber)
    )
    DBI::dbExecute(
      dbc,
      paste(
        'INSERT INTO main."__VPRO_PlotClimate" (',
        '  "PlotNumber", "CoordElevHash", "RefPeriod", "Source",',
        '  "MAT", "MWMT", "MCMT", "MAP", "MSP", "PAS", "CMD",',
        '  "PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",',
        '  "PPT_at", "PPT_wt", "DD5", "NFFD", "ComputedAt"',
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
      ),
      params = unname(as.list(clean_tbl))
    )
    src_counts <- as.list(table(clean_tbl$Source))
    vpro_append_rsidecar_history_in_tx(
      dbc,
      action = "CachePlotClimate",
      details = list(
        rows = nrow(clean_tbl),
        refPeriods = unique(clean_tbl$RefPeriod),
        sources = src_counts
      )
    )
  })

  invisible(clean_tbl)
}

#' Extract or compute cached plot climate normals (`__VPRO_PlotClimate`)
#'
#' Reads existing `__VPRO_PlotClimate` rows in `con$project_path` whose
#' `CoordElevHash` and `RefPeriod` match each plot's current coordinates and
#' elevation. For cache misses, uses `climr::downscale()` when `climr` and local
#' cached rasters are available (and `!force_offline`), falling back cleanly to
#' the calibrated BGC lapse-rate model (`bgc_climate_normals.csv` +
#' `CMD_adjustments.csv`) when `allow_fallback = TRUE`. Automatically caches
#' newly computed rows on writable user databases when `cache = TRUE`.
#'
#' @param con A `vpro_workspace` handle.
#' @param scope Either `"su"` (active SU plots) or `"project"` (all `_Env` plots).
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`).
#' @param cache Logical; if `TRUE` (default) and `con` points to a writable user
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
  con,
  scope = c("su", "project"),
  ref_period = "1961_1990",
  cache = TRUE,
  allow_fallback = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(con)
  scope <- match.arg(scope)
  ref_period <- vpro_normalize_ref_period(ref_period)

  if (!isTRUE(allow_fallback)) {
    if (isTRUE(force_offline)) {
      rlang::abort("Cannot set both `force_offline = TRUE` and `allow_fallback = FALSE`.")
    }
    rlang::check_installed("climr", reason = "to downscale plot climate normals when `allow_fallback = FALSE`.")
  }

  env_df <- vpro_env(con, scope = scope, include_admin = TRUE)
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

  valid_coord <- !is.na(lat_raw) & is.finite(lat_raw) & abs(lat_raw) <= 90.0 & lat_raw != 0.0 &
    !is.na(lon_raw) & is.finite(lon_raw) & abs(lon_raw) <= 180.0 & lon_raw != 0.0 &
    !is.na(elev_raw) & is.finite(elev_raw) & elev_raw >= -100.0 & elev_raw <= 6000.0

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

  hashes <- vpro_coord_elev_hash(lat_v, lon_v, elev_v, ref_period = ref_period)
  existing_cache <- vpro_read_plot_climate_cache(con$project_path)
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
      !identical(con$source, "sample") &&
      !vpro_is_bundled_package_path(con$project_path) &&
      !vpro_is_protected_support_db(con$project_path, con = con)
    if (can_auto_write) {
      vpro_cache_climate(con, miss_tbl)
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

#' Evaluate the B.C. Ministry `CMD -> aSMR` transfer rules directly
#'
#' Vectorized implementation of B.C. Ministry of Forests `_calculate_aSMR.R` +
#' `aSMR_Rules_HalfStep.csv` matching `vpro_wails` `EvaluateMinistryASMR`:
#' growing-season 5-month moist surplus (`PPT_05..PPT_09 >= 90 mm`), dormant
#' recharge deficit (`max(0, 350 - (PPT_at + PPT_wt))`), steep (`> 35%`) warm SW
#' (`180..270` -> `1.25x`) and cool N (`> 315` or `< 45` -> `0.85x`) aspect
#' modifiers, topographic water-balance step adjustments across `rSMR` `0..8`,
#' and rule lookup in `[0.0, 8.0]`.
#'
#' @param cmd Numeric annual climatic moisture deficit (`CMD`).
#' @param ppt_05,ppt_06,ppt_07,ppt_08,ppt_09 Numeric May--September monthly
#'   precipitation (`mm`).
#' @param ppt_at,ppt_wt Numeric autumn and winter seasonal precipitation (`mm`).
#' @param rsmr Character or numeric relative soil moisture regime (`0..8`).
#' @param slope Numeric slope gradient in percent (`NA` treated as flat/unmodified).
#' @param aspect Numeric slope aspect in degrees (`0..360`; `NA` treated as unmodified).
#' @return A tibble with `rSMR`, `MoistMonths`, `DormantDeficit`, `AspectFactor`,
#'   `CMD_topo`, `CMD_site`, and `aSMR`.
#' @export
vpro_evaluate_asmr <- function(
  cmd,
  ppt_05,
  ppt_06,
  ppt_07,
  ppt_08,
  ppt_09,
  ppt_at,
  ppt_wt,
  rsmr,
  slope = NA_real_,
  aspect = NA_real_
) {
  rec <- vpro_value_recycle(list(
    cmd = as.double(cmd),
    ppt_05 = as.double(ppt_05),
    ppt_06 = as.double(ppt_06),
    ppt_07 = as.double(ppt_07),
    ppt_08 = as.double(ppt_08),
    ppt_09 = as.double(ppt_09),
    ppt_at = as.double(ppt_at),
    ppt_wt = as.double(ppt_wt),
    rsmr = as.character(rsmr),
    slope = as.double(slope),
    aspect = as.double(aspect)
  ))

  rules_dt <- vpro_load_asmr_assets()$rules
  rule_lvl <- as.integer(rules_dt[["SMRLevel"]])
  rule_cmd <- as.double(rules_dt[["CMD"]])
  rule_asmr <- as.double(rules_dt[["aSMR"]])

  n <- length(rec$cmd)
  r_int <- vpro_parse_rsmr_digit(rec$rsmr)
  moist_months <- rep(NA_integer_, n)
  dorm_def <- rep(NA_real_, n)
  asp_fac <- rep(NA_real_, n)
  cmd_topo <- rep(NA_real_, n)
  cmd_site <- rep(NA_real_, n)
  asmr_out <- rep(NA_real_, n)

  has_clim <- is.finite(rec$cmd) & is.finite(rec$ppt_at) & is.finite(rec$ppt_wt)
  if (any(has_clim)) {
    p_mat <- cbind(rec$ppt_05, rec$ppt_06, rec$ppt_07, rec$ppt_08, rec$ppt_09)
    for (i in which(has_clim)) {
      mc <- sum(!is.na(p_mat[i, ]) & p_mat[i, ] >= 90.0)
      moist_flag <- if (mc > 4L) 1.0 else 0.0
      mult <- 1.0 + (moist_flag / 5.0)
      cmd_gs <- rec$cmd[[i]] / mult

      ppt_dorm <- rec$ppt_at[[i]] + rec$ppt_wt[[i]]
      def_i <- max(0.0, 350.0 - ppt_dorm)
      cmd_tot <- cmd_gs + def_i

      af <- 1.0
      sl <- rec$slope[[i]]
      as_v <- rec$aspect[[i]]
      if (is.finite(sl) && is.finite(as_v) && sl > 35.0) {
        if (as_v > 180.0 && as_v < 270.0) {
          af <- 1.25
        } else if (as_v > 315.0 || (as_v >= 0.0 && as_v < 45.0)) {
          af <- 0.85
        }
      }
      ct <- vpro_go_round(cmd_tot * af * 10.0) / 10.0

      moist_months[[i]] <- as.integer(mc)
      dorm_def[[i]] <- vpro_go_round(def_i * 10.0) / 10.0
      asp_fac[[i]] <- af
      cmd_topo[[i]] <- ct

      ri <- r_int[[i]]
      if (is.na(ri) || ri < 0L || ri > 8L) {
        next
      }
      if (ri == 8L) {
        cmd_site[[i]] <- 0.0
        asmr_out[[i]] <- 8.0
        next
      }

      cs_raw <- if (ri < 4L) {
        ct + (4L - ri) * 125.0
      } else if (ri == 4L) {
        ct
      } else if (ri == 5L) {
        ct / 2.0
      } else if (ri == 6L) {
        ct / 4.0
      } else {
        ct / 8.0
      }
      cs <- vpro_go_round(max(0.0, cs_raw) * 10.0) / 10.0
      cmd_site[[i]] <- cs

      smr_lvl <- if (ri <= 4L) 0L else ri
      hits <- which(rule_lvl == smr_lvl & cs <= rule_cmd)
      asmr_out[[i]] <- if (length(hits) == 0L) 0.0 else max(rule_asmr[hits])
    }
  }

  tibble::tibble(
    rSMR = r_int,
    MoistMonths = moist_months,
    DormantDeficit = dorm_def,
    AspectFactor = asp_fac,
    CMD_topo = cmd_topo,
    CMD_site = cmd_site,
    aSMR = asmr_out
  )
}

#' Compute plot climate normals and Ministry Actual Soil Moisture Regime (`aSMR`)
#'
#' Joins plot environment (`_Env` + `*_SU`) with cached/downscaled climate
#' normals ([vpro_climate()]) and evaluates the B.C. Ministry of Forests
#' `CMD -> aSMR` transfer function (`aSMR_Rules_HalfStep.csv` &
#' `CMD_adjustments.csv`).
#'
#' @param con A `vpro_workspace` handle.
#' @param scope Either `"su"` (active SU plots) or `"project"` (all `_Env` plots).
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`).
#' @param cache Logical; passed to [vpro_climate()] to persist new
#'   `__VPRO_PlotClimate` rows on writable user databases.
#' @param force_offline Logical; if `TRUE`, uses the offline BGC lapse-rate
#'   normals model without querying `climr`.
#' @return A tibble joining `PlotNumber` (literal character), `SiteUnit`, `Zone`,
#'   `SubZone`, `BGC`, `MoistureRegime`, `NutrientRegime`, `rSMR`, `rSNR`,
#'   `SlopeGradient`, `Aspect`, `CMD`, `CMD_topo`, `CMD_site`, `aSMR`, and
#'   climate normals.
#' @export
vpro_asmr <- function(
  con,
  scope = c("su", "project"),
  ref_period = "1961_1990",
  cache = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(con)
  scope <- match.arg(scope)
  ref_period <- vpro_normalize_ref_period(ref_period)

  env_df <- vpro_env(con, scope = scope, include_admin = TRUE)
  clim_df <- vpro_climate(
    con,
    scope = scope,
    ref_period = ref_period,
    cache = cache,
    allow_fallback = TRUE,
    force_offline = force_offline
  )

  n <- nrow(env_df)
  if (n == 0L) {
    return(tibble::tibble(
      PlotNumber = character(),
      SiteUnit = character(),
      Zone = character(),
      SubZone = character(),
      SiteSeries = character(),
      BGC = character(),
      MoistureRegime = character(),
      NutrientRegime = character(),
      rSMR = integer(),
      rSNR = character(),
      SlopeGradient = numeric(),
      Aspect = numeric(),
      Latitude = numeric(),
      Longitude = numeric(),
      Elevation = numeric(),
      CMD = numeric(),
      CMD_topo = numeric(),
      CMD_site = numeric(),
      aSMR = numeric(),
      MoistMonths = integer(),
      DormantDeficit = numeric(),
      AspectFactor = numeric(),
      MAT = numeric(),
      MWMT = numeric(),
      MCMT = numeric(),
      MAP = numeric(),
      MSP = numeric(),
      PAS = numeric(),
      PPT_05 = numeric(),
      PPT_06 = numeric(),
      PPT_07 = numeric(),
      PPT_08 = numeric(),
      PPT_09 = numeric(),
      PPT_at = numeric(),
      PPT_wt = numeric(),
      DD5 = numeric(),
      NFFD = numeric(),
      CoordElevHash = character(),
      RefPeriod = character(),
      Source = character(),
      ComputedAt = character()
    ))
  }

  c_ix <- match(env_df$PlotNumber, clim_df$PlotNumber)
  zone_chr <- if ("Zone" %in% names(env_df)) as.character(env_df$Zone) else rep(NA_character_, n)
  subz_chr <- if ("SubZone" %in% names(env_df)) as.character(env_df$SubZone) else rep(NA_character_, n)
  bgc_fallback <- gsub(
    "[[:space:]]+",
    "",
    paste0(ifelse(is.na(zone_chr), "", zone_chr), ifelse(is.na(subz_chr), "", subz_chr))
  )
  bgc_v <- ifelse(!is.na(c_ix), clim_df$BGC[c_ix], ifelse(nzchar(bgc_fallback), bgc_fallback, NA_character_))

  mr_chr <- if ("MoistureRegime" %in% names(env_df)) as.character(env_df$MoistureRegime) else rep(NA_character_, n)
  nr_chr <- if ("NutrientRegime" %in% names(env_df)) as.character(env_df$NutrientRegime) else rep(NA_character_, n)
  slope_v <- if ("SlopeGradient" %in% names(env_df)) suppressWarnings(as.double(env_df$SlopeGradient)) else rep(NA_real_, n)
  aspect_v <- if ("Aspect" %in% names(env_df)) suppressWarnings(as.double(env_df$Aspect)) else rep(NA_real_, n)
  lat_env <- if ("Latitude" %in% names(env_df)) suppressWarnings(as.double(env_df$Latitude)) else rep(NA_real_, n)
  lon_env <- if ("Longitude" %in% names(env_df)) vpro_normalize_bc_lon(suppressWarnings(as.double(env_df$Longitude))) else rep(NA_real_, n)
  elev_env <- if ("Elevation" %in% names(env_df)) suppressWarnings(as.double(env_df$Elevation)) else rep(NA_real_, n)

  cmd_v <- clim_df$CMD[c_ix]
  p05_v <- clim_df$PPT_05[c_ix]
  p06_v <- clim_df$PPT_06[c_ix]
  p07_v <- clim_df$PPT_07[c_ix]
  p08_v <- clim_df$PPT_08[c_ix]
  p09_v <- clim_df$PPT_09[c_ix]
  pat_v <- clim_df$PPT_at[c_ix]
  pwt_v <- clim_df$PPT_wt[c_ix]

  eval_tbl <- vpro_evaluate_asmr(
    cmd = cmd_v,
    ppt_05 = p05_v,
    ppt_06 = p06_v,
    ppt_07 = p07_v,
    ppt_08 = p08_v,
    ppt_09 = p09_v,
    ppt_at = pat_v,
    ppt_wt = pwt_v,
    rsmr = mr_chr,
    slope = slope_v,
    aspect = aspect_v
  )

  ss_chr <- if ("SiteSeries" %in% names(env_df)) as.character(env_df$SiteSeries) else rep(NA_character_, n)
  out <- tibble::tibble(
    PlotNumber = as.character(env_df$PlotNumber),
    SiteUnit = as.character(env_df$SiteUnit),
    Zone = zone_chr,
    SubZone = subz_chr,
    SiteSeries = ss_chr,
    BGC = bgc_v,
    MoistureRegime = mr_chr,
    NutrientRegime = nr_chr,
    rSMR = eval_tbl$rSMR,
    rSNR = vpro_normalize_rsnr(nr_chr),
    SlopeGradient = slope_v,
    Aspect = aspect_v,
    Latitude = ifelse(!is.na(c_ix), clim_df$Latitude[c_ix], lat_env),
    Longitude = ifelse(!is.na(c_ix), clim_df$Longitude[c_ix], lon_env),
    Elevation = ifelse(!is.na(c_ix), clim_df$Elevation[c_ix], elev_env),
    CMD = cmd_v,
    CMD_topo = eval_tbl$CMD_topo,
    CMD_site = eval_tbl$CMD_site,
    aSMR = eval_tbl$aSMR,
    MoistMonths = eval_tbl$MoistMonths,
    DormantDeficit = eval_tbl$DormantDeficit,
    AspectFactor = eval_tbl$AspectFactor,
    MAT = clim_df$MAT[c_ix],
    MWMT = clim_df$MWMT[c_ix],
    MCMT = clim_df$MCMT[c_ix],
    MAP = clim_df$MAP[c_ix],
    MSP = clim_df$MSP[c_ix],
    PAS = clim_df$PAS[c_ix],
    PPT_05 = p05_v,
    PPT_06 = p06_v,
    PPT_07 = p07_v,
    PPT_08 = p08_v,
    PPT_09 = p09_v,
    PPT_at = pat_v,
    PPT_wt = pwt_v,
    DD5 = clim_df$DD5[c_ix],
    NFFD = clim_df$NFFD[c_ix],
    CoordElevHash = clim_df$CoordElevHash[c_ix],
    RefPeriod = clim_df$RefPeriod[c_ix],
    Source = clim_df$Source[c_ix],
    ComputedAt = clim_df$ComputedAt[c_ix]
  )
  attr(out, "cache_hits") <- attr(clim_df, "cache_hits")
  attr(out, "cache_misses") <- attr(clim_df, "cache_misses")
  attr(out, "skipped_no_coords") <- attr(clim_df, "skipped_no_coords")
  out
}
