# Calibrated BEC & Access VP08 Domain Helpers --------------------------------

.vpro_core_project_suffixes <- c(
  "Admin",
  "Audit",
  "Env",
  "Humus",
  "Metadata",
  "Mineral",
  "Other",
  "Veg"
)

.vpro_optional_project_suffixes <- c(
  "Herbarium",
  "Hierarchy",
  "Lump",
  "Profile",
  "SU",
  "Theme"
)

vpro_quote_ident <- function(x) {
  paste0('"', gsub('"', '""', as.character(x), fixed = TRUE), '"')
}

vpro_sqlite_ro <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    rlang::abort(paste0("SQLite database does not exist: ", path))
  }
  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    normalizePath(path, winslash = "/", mustWork = TRUE),
    flags = RSQLite::SQLITE_RO,
    synchronous = NULL
  )
  tryCatch(
    {
      DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
      DBI::dbExecute(con, "PRAGMA query_only = ON")
    },
    error = function(e) NULL
  )
  con
}

vpro_sqlite_rw_immediate <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    rlang::abort(paste0("SQLite database does not exist: ", path))
  }
  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    normalizePath(path, winslash = "/", mustWork = TRUE),
    flags = RSQLite::SQLITE_RW
  )
  ok <- FALSE
  on.exit(if (!ok && DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  DBI::dbExecute(con, "PRAGMA synchronous = NORMAL")
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  ok <- TRUE
  con
}

#' Convert Access integer/text booleans to R logical
#'
#' Normalizes Access `BOOLEAN` storage (`-1` or non-zero = `TRUE`, `0` = `FALSE`,
#' `NULL`/`NA` = `NA`) into R `logical`.
#'
#' @param x Atomic vector of Access boolean values.
#' @return A `logical` vector of the same length as `x`.
#' @export
vpro_access_to_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  if (is.numeric(x)) {
    out <- rep(NA, length(x))
    ok <- !is.na(x) & is.finite(x)
    out[ok] <- x[ok] != 0
    return(as.logical(out))
  }
  chr <- tolower(trimws(as.character(x)))
  out <- rep(NA, length(chr))
  out[!is.na(chr) & chr == "true"] <- TRUE
  out[!is.na(chr) & chr == "false"] <- FALSE
  int_idx <- which(!is.na(chr) & grepl("^[+-]?[0-9]+$", chr))
  if (length(int_idx) > 0L) {
    sub_s <- chr[int_idx]
    neg <- startsWith(sub_s, "-")
    digs <- sub("^0+", "", sub("^[+-]", "", sub_s))
    is_zero <- !nzchar(digs)
    nd <- nchar(digs, type = "bytes")
    lim <- ifelse(neg, "9223372036854775808", "9223372036854775807")
    in_range <- is_zero | (nd < 19L) | (nd == 19L & digs <= lim)
    out[int_idx[in_range & is_zero]] <- FALSE
    out[int_idx[in_range & !is_zero]] <- TRUE
  }
  as.logical(out)
}

#' Convert R logical values to Access SQLite integer booleans
#'
#' Serializes `TRUE` to `-1L`, `FALSE` to `0L`, and `NA` to `NA_integer_`.
#'
#' @param x Logical vector.
#' @return An `integer` vector containing `-1L`, `0L`, or `NA_integer_`.
#' @export
vpro_logical_to_access <- function(x) {
  lgl <- vpro_access_to_logical(x)
  out <- rep(NA_integer_, length(lgl))
  out[!is.na(lgl) & lgl] <- -1L
  out[!is.na(lgl) & !lgl] <- 0L
  out
}

#' Round numeric cover values to VPro single-precision bounds
#'
#' Reproduces VPro Desktop and Microsoft Access `Single` cover precision prior
#' to `< 100` bounds checks (`99.999996 -> 99.99999237 < 100`;
#' `99.999999 -> 100.0`).
#'
#' @param x Numeric vector.
#' @return Numeric vector rounded to nearest 32-bit single-precision values.
#' @export
vpro_narrow_float32 <- function(x) {
  if (!is.numeric(x)) {
    rlang::abort("`x` must be a numeric vector.")
  }
  out <- rep(NA_real_, length(x))
  max_f32 <- 3.4028234663852886e+38
  ok <- !is.na(x) & is.finite(x) & abs(x) <= max_f32
  if (any(ok)) {
    raw_buf <- writeBin(as.double(x[ok]), raw(), size = 4L)
    vals <- readBin(raw_buf, what = "numeric", n = sum(ok), size = 4L)
    vals[vals == 0.0] <- 0.0
    out[ok] <- vals
  }
  out
}

.vpro_round_ace_scalar <- function(v, d) {
  if (v == 0.0) {
    return(0.0)
  }
  neg <- v < 0.0
  s <- sprintf("%.14e", abs(v))
  e_pos <- regexpr("[eE]", s)
  mant <- substr(s, 1L, e_pos - 1L)
  exp10 <- as.integer(substring(s, e_pos + 1L))
  dig_str <- paste0(substr(mant, 1L, 1L), substring(mant, 3L))
  digs <- utf8ToInt(dig_str) - 48L

  m <- as.double(exp10) + as.double(d) + 1.0
  if (m < 0.0) {
    return(0.0)
  }
  if (m == 0.0) {
    if (digs[[1L]] >= 5L) {
      res <- as.numeric(paste0(if (neg) "-" else "", "1e", -d))
      if (!is.finite(res)) {
        return(v)
      }
      return(if (res == 0.0) 0.0 else res)
    }
    return(0.0)
  }
  if (m >= 15.0) {
    res <- as.numeric(paste0(if (neg) "-" else "", s))
    if (!is.finite(res)) {
      return(v)
    }
    return(if (res == 0.0) 0.0 else res)
  }

  m_int <- as.integer(m)
  keep <- digs[seq_len(m_int)]
  if (digs[[m_int + 1L]] >= 5L) {
    carry <- 1L
    for (j in seq.int(m_int, 1L, by = -1L)) {
      sum_j <- keep[[j]] + carry
      if (sum_j >= 10L) {
        keep[[j]] <- sum_j - 10L
        carry <- 1L
      } else {
        keep[[j]] <- sum_j
        carry <- 0L
        break
      }
    }
    if (carry > 0L) {
      keep <- c(1L, keep)
      exp10 <- exp10 + 1L
    }
  }
  if (all(keep == 0L)) {
    return(0.0)
  }
  mant_out <- if (length(keep) == 1L) {
    as.character(keep[[1L]])
  } else {
    paste0(keep[[1L]], ".", paste0(keep[-1L], collapse = ""))
  }
  res <- as.numeric(paste0(if (neg) "-" else "", mant_out, "e", exp10))
  if (!is.finite(res)) {
    return(v)
  }
  if (res == 0.0) 0.0 else res
}

#' Round numeric values using ACE 15-significant-digit half-away rounding
#'
#' Formats finite values to 15 significant decimal digits before rounding
#' half-way cases away from zero (`1.005 -> 1.01` at `digits = 2L`), matching
#' calibrated Access / Plot Profiling display math.
#'
#' @param x Numeric vector.
#' @param digits Single non-negative integer number of decimal places.
#' @return Numeric vector rounded to `digits` decimal places.
#' @export
vpro_round_ace <- function(x, digits = 2L) {
  if (!is.numeric(x)) {
    rlang::abort("`x` must be a numeric vector.")
  }
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) || !is.finite(digits) || digits < 0 || digits != trunc(digits)) {
    rlang::abort("`digits` must be a single non-negative integer.")
  }
  d <- min(as.double(digits), 350.0)
  d_int <- as.integer(d)
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    out[ok] <- vapply(as.double(x[ok]), .vpro_round_ace_scalar, numeric(1L), d = d_int)
  }
  out
}

vpro_utf16_len <- function(x) {
  chr <- enc2utf8(as.character(x))
  out <- rep(NA_integer_, length(chr))
  ok <- !is.na(chr) & validUTF8(chr)
  if (!any(ok)) {
    return(out)
  }
  sub_c <- chr[ok]
  nb <- nchar(sub_c, type = "bytes", allowNA = TRUE)
  nc <- nchar(sub_c, type = "chars", allowNA = TRUE)
  is_ascii <- !is.na(nb) & !is.na(nc) & (nb == nc)
  res <- rep(NA_integer_, length(sub_c))
  res[is_ascii] <- nb[is_ascii]
  non_ascii <- which(!is_ascii & !is.na(nc))
  if (length(non_ascii) > 0L) {
    res[non_ascii] <- vapply(
      sub_c[non_ascii],
      function(s) {
        cp <- utf8ToInt(s)
        if (any(cp >= 0xD800L & cp <= 0xDFFFL)) {
          return(NA_integer_)
        }
        as.integer(sum(ifelse(cp > 0xFFFFL, 2L, 1L)))
      },
      integer(1)
    )
  }
  out[ok] <- res
  out
}

vpro_sha256_file <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  # Compiled SHA-256 from cli (already in Imports): identical 64-char lowercase
  # hex on every OS, no PATH binaries and never an MD5 substitute.
  tolower(unname(cli::hash_file_sha256(path)))
}

vpro_value_vector <- function(value, argument) {
  if (!is.numeric(value) || length(value) == 0L) {
    stop("`", argument, "` must be a nonempty numeric vector.", call. = FALSE)
  }
  if (any(!is.finite(value) & !is.na(value))) {
    stop("`", argument, "` must contain only finite values or NA.", call. = FALSE)
  }
  as.numeric(value)
}

vpro_value_recycle <- function(values) {
  sizes <- vapply(values, length, integer(1))
  size <- max(sizes)
  incompatible <- sizes != 1L & sizes != size
  if (any(incompatible)) {
    stop("Inputs must have a common length or length one.", call. = FALSE)
  }
  lapply(values, rep_len, length.out = size)
}

vpro_value_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", argument, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

#' Convert vegetation presence to Roman (`"I"`..`"V"`) or numeric (`1L`..`5L`) classes
#'
#' Maps proportions in `[0, 1]` at breakpoints `0.2, 0.4, 0.6, 0.8` into Roman
#' (`"I"`..`"V"`) or numeric (`1L`..`5L`) presence classes matching VPro reports.
#' Values `< 0`, `> 1`, or `NA` return `NA`.
#'
#' @param presence Numeric vegetation presence expressed as a proportion in `[0, 1]`.
#' @param format Output representation: `"roman"` (character `"I"` through `"V"`)
#'   or `"numeric"` (integer `1L` through `5L`).
#' @return A character vector (when `format = "roman"`) or integer vector (when
#'   `format = "numeric"`), with out-of-range values `< 0` or `> 1` mapped to `NA`.
#' @export
vpro_presence_class <- function(presence, format = c("roman", "numeric")) {
  format <- match.arg(format)
  presence <- vpro_value_vector(presence, "presence")
  valid <- !is.na(presence) & presence >= 0 & presence <= 1
  idx <- findInterval(presence[valid], c(0.2, 0.4, 0.6, 0.8), left.open = TRUE) + 1L
  if (identical(format, "numeric")) {
    result <- rep(NA_integer_, length(presence))
    result[valid] <- as.integer(idx)
    return(result)
  }
  result <- rep(NA_character_, length(presence))
  result[valid] <- c("I", "II", "III", "IV", "V")[idx]
  result
}

vpro_score_result <- function(score, breaks, classes, return_score) {
  if (return_score) {
    return(score)
  }
  result <- rep(NA_integer_, length(score))
  valid <- !is.na(score) & score >= 0
  result[valid] <- classes[
    findInterval(score[valid], breaks, left.open = TRUE) + 1L
  ]
  result
}

#' Calculate prominence classes or scores
#'
#' Computes BEC prominence scores (`mean_cover * 10 * sqrt(presence)`) and
#' classifies them at `15, 50, 100, 200` into `1:5` matching VPro reports.
#'
#' @param mean_cover Numeric mean vegetation cover.
#' @param presence Numeric vegetation presence expressed as a proportion.
#' @param return_score If `TRUE`, return raw numeric scores instead of integer classes.
#' @return Numeric score vector when `return_score = TRUE`, else integer classes `1:5`.
#' @export
vpro_prominence_class <- function(mean_cover, presence, return_score = FALSE) {
  values <- vpro_value_recycle(list(
    mean_cover = vpro_value_vector(mean_cover, "mean_cover"),
    presence = vpro_value_vector(presence, "presence")
  ))
  return_score <- vpro_value_flag(return_score, "return_score")
  score <- rep(NA_real_, length(values$mean_cover))
  valid <- !is.na(values$mean_cover) & !is.na(values$presence) & values$presence >= 0
  score[valid] <- values$mean_cover[valid] * 10 * sqrt(values$presence[valid])
  vpro_score_result(score, c(15, 50, 100, 200), 1:5, return_score)
}

#' Calculate Goldstream classes or scores
#'
#' Computes Goldstream scores (`presence * 100 * sqrt(mean_cover)`) and
#' classifies them at `5, 25, 75, 150, 300, 500` into `0:6` matching VPro reports.
#'
#' @inheritParams vpro_prominence_class
#' @return Numeric score vector when `return_score = TRUE`, else integer classes `0:6`.
#' @export
vpro_goldstream_class <- function(mean_cover, presence, return_score = FALSE) {
  values <- vpro_value_recycle(list(
    mean_cover = vpro_value_vector(mean_cover, "mean_cover"),
    presence = vpro_value_vector(presence, "presence")
  ))
  return_score <- vpro_value_flag(return_score, "return_score")
  score <- rep(NA_real_, length(values$mean_cover))
  valid <- !is.na(values$mean_cover) & !is.na(values$presence) & values$mean_cover >= 0
  score[valid] <- values$presence[valid] * 100 * sqrt(values$mean_cover[valid])
  vpro_score_result(score, c(5, 25, 75, 150, 300, 500), 0:6, return_score)
}

#' Convert significance values to Domin-Krajina report classes
#'
#' Maps mean cover values to Domin-Krajina significance classes (`<= 0.3` ->
#' `"+"`; `1, 2.2, 5, 10, 20, 33, 50, 75` -> `"1"` through `"9"`).
#'
#' @param significance Numeric significance (mean cover) values.
#' @return A character vector containing `"+"`, `"1"` through `"9"`, or `NA`.
#' @export
vpro_significance_class <- function(significance) {
  significance <- vpro_value_vector(significance, "significance")
  result <- rep(NA_character_, length(significance))
  valid <- !is.na(significance) & significance > -1
  result[valid] <- c("+", as.character(1:9))[
    findInterval(
      significance[valid],
      c(0.3, 1, 2.2, 5, 10, 20, 33, 50, 75),
      left.open = TRUE
    ) +
      1L
  ]
  result
}

#' Cap percentage-like values at 100
#'
#' @param x Numeric vector.
#' @return Numeric vector capped above at `100`.
#' @export
vpro_cap_percent <- function(x) {
  x <- vpro_value_vector(x, "x")
  pmin(x, 100)
}

#' Classify a species across ordered site-unit codes
#'
#' Classifies a species into classic BEC diagnostic codes (`d`, `dd`, `cd`, `c`,
#' `ic`) from a named character vector of `"<presence 1-5> - <signif +|1-9>"` cells.
#'
#' @param unit_codes Named character vector in crosstab field order (`"1 - +"` .. `"5 - 9"`).
#' @return List with `unit` and `diagnosis` (`d`, `dd`, `cd`, `c`, `ic`).
#' @export
vpro_classify_diagnostic_codes <- function(unit_codes) {
  units <- names(unit_codes)
  if (!is.character(unit_codes) || length(unit_codes) == 0L || is.null(units) || anyNA(units) || any(!nzchar(units)) || anyDuplicated(units)) {
    stop("`unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.", call. = FALSE)
  }
  present <- !is.na(unit_codes)
  if (any(!grepl("^[1-5] - (\\+|[1-9])$", unit_codes[present]))) {
    stop("Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.", call. = FALSE)
  }
  if (!any(present)) {
    return(list(unit = NA_character_, diagnosis = NA_character_))
  }

  presence <- as.integer(substr(unit_codes[present], 1L, 1L))
  significance_code <- substring(unit_codes[present], 5L)
  significance <- integer(length(significance_code))
  numeric_significance <- significance_code != "+"
  significance[numeric_significance] <- as.integer(significance_code[numeric_significance])
  maximum <- max(presence)
  selected <- which(presence == maximum)[1L]
  selected_significance <- significance[selected]
  count_presence <- sum(presence > maximum - 2L)
  count_five <- sum(presence == 5L)
  count_significance <- sum(significance > selected_significance - 2L)

  differential <- count_presence == 1L && maximum >= 3L
  dominant_differential <- count_significance == 1L && !differential && selected_significance >= 5L
  constant_dominant <- maximum == 5L && count_presence == 1L && selected_significance >= 5L
  constant <- maximum == 5L && count_five == 1L && selected_significance < 5L
  important_companion <- !differential && !dominant_differential && !constant_dominant && !constant && maximum >= 2L && count_presence == 1L

  codes <- c("d", "dd", "cd", "c", "ic")
  chosen <- c(differential, dominant_differential, constant_dominant, constant, important_companion)
  if (!any(chosen)) {
    return(list(unit = NA_character_, diagnosis = NA_character_))
  }
  list(unit = units[present][selected], diagnosis = paste(codes[chosen], collapse = ", "))
}

#' Compose decimal degrees from degrees, minutes, and seconds
#'
#' Converts degrees, minutes, and seconds to decimal degrees following VPro
#' coordinate sign and missing-component conventions.
#'
#' @param degrees Numeric degrees (`NA` yields `NA`).
#' @param minutes Numeric minutes (`NA` treated as `0`).
#' @param seconds Numeric seconds (`NA` treated as `0`).
#' @return Numeric vector of decimal degrees.
#' @export
vpro_coordinate_decimal <- function(degrees, minutes = 0, seconds = 0) {
  values <- vpro_value_recycle(list(
    degrees = vpro_value_vector(degrees, "degrees"),
    minutes = vpro_value_vector(minutes, "minutes"),
    seconds = vpro_value_vector(seconds, "seconds")
  ))
  values$minutes[is.na(values$minutes)] <- 0
  values$seconds[is.na(values$seconds)] <- 0
  values$degrees + (values$minutes + values$seconds / 60) / 60
}

#' Decompose decimal degrees into degrees, minutes, and seconds
#'
#' @param value Numeric vector of decimal-degree values.
#' @return Data frame with `degrees`, `minutes`, and `seconds` columns.
#' @export
vpro_coordinate_dms <- function(value) {
  value <- abs(vpro_value_vector(value, "value"))
  degrees <- trunc(value)
  decimal_minutes <- (value - degrees) * 60
  minutes <- trunc(decimal_minutes)
  seconds <- (decimal_minutes - minutes) * 60
  tibble::tibble(degrees = degrees, minutes = minutes, seconds = seconds)
}

#' Decompose decimal degrees into degrees and decimal minutes
#'
#' @inheritParams vpro_coordinate_dms
#' @return Data frame with `degrees` and `minutes` columns.
#' @export
vpro_coordinate_dm <- function(value) {
  value <- abs(vpro_value_vector(value, "value"))
  degrees <- trunc(value)
  minutes <- (value - degrees) * 60
  tibble::tibble(degrees = degrees, minutes = minutes)
}

#' B.C. Government visual styling and palette assets
#'
#' Returns the B.C. Government BEC visual specification (`#003366` Navy,
#' `#FCBA19` Gold, self-hosted `BC Sans` `.woff2` font paths, and Quarto CSS
#' path), or a configured `ggplot2` theme when `type = "ggplot2"`.
#'
#' @param type Either `"ggplot2"` (returns a `ggplot2::theme` when `ggplot2` is
#'   installed, otherwise the asset list) or `"assets"` (returns palette and
#'   self-hosted `BC Sans` / CSS paths).
#' @param base_size Base font size in points when `type = "ggplot2"`.
#' @return A `ggplot2` theme object or a named list of B.C. Government styling assets.
#' @export
vpro_bcgov_theme <- function(type = c("ggplot2", "assets"), base_size = 11) {
  type <- match.arg(type)
  css_path <- vpro_bundled_file("theme", "bcgov.css")
  fonts_dir <- vpro_bundled_file("theme", "fonts")
  assets <- list(
    navy = "#003366",
    gold = "#FCBA19",
    blue_mid = "#38598A",
    text = "#313132",
    bg_light = "#F2F2F2",
    border = "#D8D8D8",
    font_family = "BC Sans",
    css_path = css_path,
    fonts_dir = fonts_dir,
    woff2 = file.path(
      fonts_dir,
      c(
        "BCSans-Regular.woff2",
        "BCSans-Bold.woff2",
        "BCSans-Italic.woff2",
        "BCSans-BoldItalic.woff2"
      )
    )
  )
  if (identical(type, "assets") || !requireNamespace("ggplot2", quietly = TRUE)) {
    return(assets)
  }
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(colour = "#003366", face = "bold", size = base_size * 1.2),
      plot.subtitle = ggplot2::element_text(colour = "#38598A", size = base_size * 0.95),
      axis.title = ggplot2::element_text(colour = "#003366", face = "bold"),
      axis.text = ggplot2::element_text(colour = "#313132"),
      strip.background = ggplot2::element_rect(fill = "#003366", colour = "#FCBA19", linewidth = 0.6),
      strip.text = ggplot2::element_text(colour = "#FFFFFF", face = "bold"),
      panel.grid.minor = ggplot2::element_blank(),
      panel.border = ggplot2::element_rect(colour = "#D8D8D8", fill = NA, linewidth = 0.5),
      legend.title = ggplot2::element_text(colour = "#003366", face = "bold")
    )
}

.vpro_register_s3_methods <- function(state_env, pairs) {
  if (isTRUE(state_env$registered)) {
    return(invisible(NULL))
  }
  pkg_env <- environment(.vpro_register_s3_methods)
  for (pair in pairs) {
    gen_pkg <- pair[[1L]]
    gen_name <- pair[[2L]]
    cls <- pair[[3L]]
    fn_name <- paste0(gen_name, ".", cls)
    if (!exists(fn_name, envir = pkg_env, mode = "function", inherits = FALSE)) {
      next
    }
    gen_env <- asNamespace(gen_pkg)
    s3_tbl <- gen_env[[".__S3MethodsTable__."]]
    if (is.environment(s3_tbl) && !exists(fn_name, envir = s3_tbl, inherits = FALSE)) {
      base::registerS3method(gen_name, cls, get(fn_name, envir = pkg_env), envir = gen_env)
    }
  }
  state_env$registered <- TRUE
  invisible(NULL)
}

vpro_query_scoped_plots <- function(dbc, table_sql, plot_vec, select_cols = "*", where_extra = NULL) {
  if (!is.null(plot_vec)) {
    if (length(plot_vec) == 0L) {
      return(DBI::dbGetQuery(dbc, paste0("SELECT ", select_cols, " FROM ", table_sql, " WHERE 1 = 0")))
    }
    chunks <- split(unique(as.character(plot_vec)), ceiling(seq_along(unique(plot_vec)) / 450L))
    parts <- lapply(chunks, function(ch) {
      ph_txt <- paste(rep("?", length(ch)), collapse = ",")
      ph_blb <- paste(rep("CAST(? AS BLOB)", length(ch)), collapse = ",")
      w <- paste0(
        'WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" IN (',
        ph_txt,
        ') AND CAST("PlotNumber" AS BLOB) IN (',
        ph_blb,
        ")"
      )
      if (!is.null(where_extra) && nzchar(where_extra)) {
        w <- paste(w, "AND", where_extra)
      }
      DBI::dbGetQuery(dbc, paste("SELECT", select_cols, "FROM", table_sql, w), params = as.list(c(ch, ch)))
    })
    return(do.call(rbind, parts))
  }
  w <- 'WHERE typeof("PlotNumber") = \'text\''
  if (!is.null(where_extra) && nzchar(where_extra)) {
    w <- paste(w, "AND", where_extra)
  }
  DBI::dbGetQuery(dbc, paste("SELECT", select_cols, "FROM", table_sql, w))
}
