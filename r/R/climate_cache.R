# Plot Climate Cache, climr & Ministry CMD -> aSMR ------------------------

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
  "PlotNumber",
  "CoordElevHash",
  "RefPeriod",
  "Source",
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
  "NFFD",
  "ComputedAt"
)

.vpro_sha256_K_hex <- c(
  "428a2f98",
  "71374491",
  "b5c0fbcf",
  "e9b5dba5",
  "3956c25b",
  "59f111f1",
  "923f82a4",
  "ab1c5ed5",
  "d807aa98",
  "12835b01",
  "243185be",
  "550c7dc3",
  "72be5d74",
  "80deb1fe",
  "9bdc06a7",
  "c19bf174",
  "e49b69c1",
  "efbe4786",
  "0fc19dc6",
  "240ca1cc",
  "2de92c6f",
  "4a7484aa",
  "5cb0a9dc",
  "76f988da",
  "983e5152",
  "a831c66d",
  "b00327c8",
  "bf597fc7",
  "c6e00bf3",
  "d5a79147",
  "06ca6351",
  "14292967",
  "27b70a85",
  "2e1b2138",
  "4d2c6dfc",
  "53380d13",
  "650a7354",
  "766a0abb",
  "81c2c92e",
  "92722c85",
  "a2bfe8a1",
  "a81a664b",
  "c24b8b70",
  "c76c51a3",
  "d192e819",
  "d6990624",
  "f40e3585",
  "106aa070",
  "19a4c116",
  "1e376c08",
  "2748774c",
  "34b0bcb5",
  "391c0cb3",
  "4ed8aa4a",
  "5b9cca4f",
  "682e6ff3",
  "748f82ee",
  "78a5636f",
  "84c87814",
  "8cc70208",
  "90befffa",
  "a4506ceb",
  "bef9a3f7",
  "c67178f2"
)

.vpro_sha256_H0_hex <- c(
  "6a09e667",
  "bb67ae85",
  "3c6ef372",
  "a54ff53a",
  "510e527f",
  "9b05688c",
  "1f83d9ab",
  "5be0cd19"
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
    cli::cli_abort("`ref_period` must be a single character string ('1961_1990' or '1991_2020').", class = c("vpro_error_climate", "vpro_error"))
  }
  norm <- gsub("-", "_", trimws(ref_period), fixed = TRUE)
  if (!(norm %in% c("1961_1990", "1991_2020"))) {
    cli::cli_abort(.vpro_cli_escape(paste0(
      "Unsupported climate reference period `",
      ref_period,
      "` (expected '1961_1990' or '1991_2020')."
    )), class = c("vpro_error_climate", "vpro_error"))
  }
  norm
}

.vpro_coord_elev_hash <- function(lat, lon, elev, ref_period = "1961_1990") {
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
    cli::cli_abort("`ref_period` must have length 1 or match the coordinate vector length.", class = c("vpro_error_climate", "vpro_error"))
  }

  n <- length(vals$lat)
  out <- rep(NA_character_, n)
  norm_lon <- vpro_normalize_bc_lon(vals$lon)
  ok <- !is.na(vals$lat) & is.finite(vals$lat) & !is.na(norm_lon) & is.finite(norm_lon) & !is.na(vals$elev) & is.finite(vals$elev) & !is.na(rp) & nzchar(rp)

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

#' Persist plot climate normals to the project's shared climate cache
#'
#' Writes or updates cached plot climate rows in the project database so VPro
#' Desktop and R reuse previously downscaled normals, recording provenance in one
#' safe transaction while preserving literal character `PlotNumber` keys.
#'
#' @param ws A `vpro_workspace` handle referencing a writable user `.db`.
#' @param climate_df Data frame containing plot climate columns (as returned by
#'   [vpro_climate()]).
#' @return Invisibly returns the written plot climate tibble.
#' @export
vpro_cache_climate <- function(ws, climate_df) {
  vpro_assert_workspace(ws)
  vpro_assert_writable_project_db(ws$project_path, con = ws)

  if (!is.data.frame(climate_df)) {
    cli::cli_abort("`climate_df` must be a `data.frame` of plot climate records.", class = c("vpro_error_climate", "vpro_error"))
  }

  req_cols <- setdiff(.vpro_plot_climate_cols, "ComputedAt")
  missing_cols <- setdiff(req_cols, names(climate_df))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(.vpro_cli_escape(paste0(
      "`climate_df` is missing required plot climate columns: ",
      paste(missing_cols, collapse = ", ")
    )), class = c("vpro_error_climate", "vpro_error"))
  }

  if (nrow(climate_df) == 0L) {
    vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
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
    cli::cli_abort("`CoordElevHash` must be a 32-character hexadecimal SHA-256 prefix.", class = c("vpro_error_climate", "vpro_error"))
  }
  ref_periods <- vapply(climate_df$RefPeriod, vpro_normalize_ref_period, character(1))
  sources <- trimws(as.character(climate_df$Source))
  if (anyNA(sources) || any(!nzchar(sources))) {
    cli::cli_abort("`Source` must be non-empty for every plot climate row.", class = c("vpro_error_climate", "vpro_error"))
  }

  now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  comp_at <- if ("ComputedAt" %in% names(climate_df)) {
    ca <- trimws(as.character(climate_df$ComputedAt))
    ifelse(is.na(ca) | !nzchar(ca), now_iso, ca)
  } else {
    rep(now_iso, nrow(climate_df))
  }

  num_cols <- c(
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

  vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
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
