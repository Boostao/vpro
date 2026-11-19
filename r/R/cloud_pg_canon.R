# PostgreSQL Query Execution, Bidirectional Canonicalizers & Audit Chain -----

vpro_pg_exec_safe <- function(expr_fn, secrets = character(), action = "PostgreSQL operation") {
  tryCatch(
    expr_fn(),
    error = function(e) {
      raw_msg <- conditionMessage(e)
      clean_msg <- vpro_redact_pg_secrets(raw_msg, secrets = secrets)
      cli::cli_abort(
        .vpro_cli_escape(paste0(action, " failed: ", clean_msg)),
        class = c("vpro_error_cloud", "vpro_error"),
        parent = NA
      )
    }
  )
}

vpro_assert_pg_conn <- function(pg, require_custodian = FALSE) {
  if (!inherits(pg, "vpro_pg_conn") || !is.list(pg) || is.null(pg$conn)) {
    cli::cli_abort(
      "{.arg pg} must be a {.cls vpro_pg_conn} connection created by {.fn vpro_master_connect}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  valid <- tryCatch(DBI::dbIsValid(pg$conn), error = function(e) FALSE)
  if (!isTRUE(valid)) {
    cli::cli_abort(
      "PostgreSQL BECMaster connection is closed or invalid. Reconnect with {.fn vpro_master_connect}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (isTRUE(require_custodian) && !identical(pg$role, "custodian")) {
    cli::cli_abort(
      c(
        "This operation requires a {.val custodian} PostgreSQL connection (active role: {.val {pg$role}}).",
        "i" = "Connect with {.code vpro_master_connect(role = \"custodian\")}."
      ),
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  invisible(pg)
}

vpro_muffle_pg_result_warning <- function(expr) {
  withCallingHandlers(
    expr,
    warning = function(w) {
      if (grepl("Closing open result set", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

vpro_pg_query <- function(con, sql, params = NULL, action = "PostgreSQL query") {
  vpro_assert_pg_conn(con)
  vpro_pg_exec_safe(
    function() {
      vpro_muffle_pg_result_warning(
        if (is.null(params) || length(params) == 0L) {
          DBI::dbGetQuery(con$conn, sql)
        } else {
          DBI::dbGetQuery(con$conn, sql, params = unname(as.list(params)))
        }
      )
    },
    action = action
  )
}

vpro_pg_begin_isolated_tx <- function(conn, begin_sql, caller_fn = "PostgreSQL transaction") {
  tx_state <- new.env(parent = emptyenv())
  tx_state$already_in_tx <- FALSE
  withCallingHandlers(
    vpro_muffle_pg_result_warning(DBI::dbExecute(conn, begin_sql)),
    warning = function(w) {
      if (grepl("already a transaction in progress", conditionMessage(w), ignore.case = TRUE)) {
        tx_state$already_in_tx <- TRUE
        invokeRestart("muffleWarning")
      }
    }
  )
  if (tx_state$already_in_tx) {
    cli::cli_abort(
      "Cannot start isolated transaction in {.fn {caller_fn}} because {.arg con} already has an open PostgreSQL transaction.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  TRUE
}

vpro_pg_execute <- function(con, sql, params = NULL, action = "PostgreSQL statement") {
  vpro_assert_pg_conn(con)
  vpro_pg_exec_safe(
    function() {
      vpro_muffle_pg_result_warning(
        if (is.null(params) || length(params) == 0L) {
          DBI::dbExecute(con$conn, sql)
        } else {
          DBI::dbExecute(con$conn, sql, params = unname(as.list(params)))
        }
      )
    },
    action = action
  )
}

vpro_pg_text_array <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return("{}")
  }
  chr <- enc2utf8(as.character(x))
  esc <- gsub("\\", "\\\\", chr, fixed = TRUE)
  esc <- gsub('"', '\\"', esc, fixed = TRUE)
  elems <- ifelse(is.na(chr), "NULL", paste0('"', esc, '"'))
  paste0("{", paste(elems, collapse = ","), "}")
}

# Canonical VP08 & Standards Column Specifications ---------------------------

vpro_pg_format_utc_text <- function(v, col_name) {
  n <- length(v)
  if (n == 0L) {
    return(character(0L))
  }
  if (inherits(v, "POSIXt")) {
    out <- rep(NA_character_, n)
    ok <- !is.na(v)
    if (any(ok)) {
      lt <- as.POSIXlt(v[ok], tz = "UTC")
      midnight <- (lt$hour == 0L) & (lt$min == 0L) & (abs(lt$sec) < 1e-6)
      res <- character(sum(ok))
      if (any(midnight)) {
        res[midnight] <- format(lt[midnight], "%Y-%m-%d", tz = "UTC")
      }
      if (any(!midnight)) {
        res[!midnight] <- format(lt[!midnight], "%Y-%m-%d %H:%M:%S", tz = "UTC")
      }
      out[ok] <- res
    }
    return(out)
  }
  if (inherits(v, "Date")) {
    out <- rep(NA_character_, n)
    ok <- !is.na(v)
    if (any(ok)) {
      out[ok] <- format(v[ok], "%Y-%m-%d")
    }
    return(out)
  }
  if (is.list(v)) {
    out <- rep(NA_character_, n)
    for (idx in seq_len(n)) {
      el <- v[[idx]]
      if (is.null(el) || (length(el) == 1L && is.na(el))) {
        next
      }
      if (is.raw(el)) {
        if (any(el == as.raw(0L))) {
          cli::cli_abort(
            "Column {.field {col_name}} contains embedded NUL bytes.",
            class = c("vpro_error_cloud", "vpro_error")
          )
        }
        out[[idx]] <- rawToChar(el)
      } else {
        out[[idx]] <- as.character(el[[1L]])
      }
    }
    return(out)
  }
  if (is.logical(v)) {
    return(ifelse(is.na(v), NA_character_, ifelse(v, "-1", "0")))
  }
  as.character(v)
}

vpro_pg_match_df_col <- function(df, col_name) {
  nms <- names(df)
  if (col_name %in% nms) {
    return(df[[col_name]])
  }
  ci <- match(tolower(col_name), tolower(nms))
  if (!is.na(ci)) {
    return(df[[ci]])
  }
  NULL
}

vpro_pg_canonicalize_to_pg <- function(df, spec) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  n_rows <- nrow(df)
  n_cols <- nrow(spec)
  out_cols <- vector("list", n_cols)
  names(out_cols) <- spec$name

  for (i in seq_len(n_cols)) {
    col_name <- spec$name[[i]]
    pg_type <- spec$pg_type[[i]]
    is_bool <- isTRUE(spec$is_bool[[i]])
    is_cover <- isTRUE(spec$is_cover[[i]])
    utf16_max <- spec$utf16_max[[i]]

    raw_col <- vpro_pg_match_df_col(df, col_name)

    if (is_bool) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_integer_, n_rows)
      } else if (is.character(raw_col)) {
        trimmed <- trimws(raw_col)
        res_bool <- vpro_logical_to_access(raw_col)
        if (any(!is.na(trimmed) & nzchar(trimmed) & is.na(res_bool))) {
          cli::cli_abort(
            "Column {.field {col_name}} contains invalid Access boolean text.",
            class = c("vpro_error_cloud", "vpro_error")
          )
        }
        out_cols[[i]] <- res_bool
      } else if (is.numeric(raw_col)) {
        if (any(!is.na(raw_col) & !is.finite(raw_col))) {
          cli::cli_abort(
            "Column {.field {col_name}} contains non-finite numeric boolean value.",
            class = c("vpro_error_cloud", "vpro_error")
          )
        }
        out_cols[[i]] <- vpro_logical_to_access(raw_col)
      } else {
        out_cols[[i]] <- vpro_logical_to_access(raw_col)
      }
      next
    }

    if (identical(pg_type, "TEXT")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_character_, n_rows)
      } else {
        chr <- vpro_pg_format_utc_text(raw_col, col_name)
        non_na <- !is.na(chr)
        if (any(non_na)) {
          if (any(!validUTF8(chr[non_na]) & is.na(iconv(chr[non_na], from = "", to = "UTF-8")))) {
            cli::cli_abort(
              "Column {.field {col_name}} contains invalid UTF-8 text.",
              class = c("vpro_error_cloud", "vpro_error")
            )
          }
          u16 <- vpro_utf16_len(chr[non_na])
          if (anyNA(u16)) {
            cli::cli_abort(
              "Column {.field {col_name}} contains invalid or unsupported text characters.",
              class = c("vpro_error_cloud", "vpro_error")
            )
          }
          if (utf16_max > 0L && any(u16 > utf16_max)) {
            cli::cli_abort(
              "Column {.field {col_name}} exceeds maximum length of {utf16_max} characters.",
              class = c("vpro_error_cloud", "vpro_error")
            )
          }
          chr[non_na] <- enc2utf8(chr[non_na])
        }
        out_cols[[i]] <- chr
      }
      next
    }

    if (pg_type %in% c("BIGINT", "SMALLINT")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_integer_, n_rows)
      } else if (is.logical(raw_col)) {
        out_cols[[i]] <- ifelse(is.na(raw_col), NA_integer_, ifelse(raw_col, -1L, 0L))
      } else {
        num <- if (is.character(raw_col)) {
          s <- trimws(raw_col)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(raw_col))
        }
        num[!is.finite(num)] <- NA_real_
        rounded <- vpro_go_round(num)
        ok <- !is.na(rounded)
        if (identical(pg_type, "SMALLINT") && any(ok & (rounded < -32768 | rounded > 32767))) {
          cli::cli_abort(
            "Column {.field {col_name}} overflows PostgreSQL SMALLINT (-32768..32767).",
            class = c("vpro_error_cloud", "vpro_error")
          )
        }
        if (any(ok & (rounded < -2147483647 | rounded > 2147483647))) {
          cli::cli_abort(
            "Column {.field {col_name}} overflows 32-bit R integer bounds.",
            class = c("vpro_error_cloud", "vpro_error")
          )
        }
        res_int <- rep(NA_integer_, n_rows)
        if (any(ok)) {
          res_int[ok] <- as.integer(rounded[ok])
        }
        out_cols[[i]] <- res_int
      }
      next
    }

    if (identical(pg_type, "DOUBLE PRECISION")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_real_, n_rows)
      } else {
        num <- if (is.character(raw_col)) {
          s <- trimws(raw_col)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(raw_col))
        }
        num[is.nan(num)] <- NA_real_
        if (is_cover) {
          non_na <- !is.na(num)
          if (any(non_na)) {
            if (any(!is.finite(num[non_na]) | num[non_na] < 0)) {
              cli::cli_abort(
                "Cover column {.field {col_name}} must be finite and >= 0.",
                class = c("vpro_error_cloud", "vpro_error")
              )
            }
            narrowed <- vpro_narrow_float32(num)
            if (any(is.na(narrowed[non_na]) | narrowed[non_na] < 0 | narrowed[non_na] >= 100)) {
              cli::cli_abort(
                "Cover column {.field {col_name}} must be >= 0 and strictly under 100%.",
                class = c("vpro_error_cloud", "vpro_error")
              )
            }
            out_cols[[i]] <- narrowed
          } else {
            out_cols[[i]] <- rep(NA_real_, n_rows)
          }
        } else {
          num[!is.finite(num)] <- NA_real_
          out_cols[[i]] <- as.double(num)
        }
      }
      next
    }

    out_cols[[i]] <- if (is.null(raw_col)) rep(NA, n_rows) else raw_col
  }

  as.data.frame(out_cols, stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE)
}

vpro_pg_canonicalize_to_sqlite <- function(df, spec) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  n_rows <- nrow(df)
  n_cols <- nrow(spec)
  out_cols <- vector("list", n_cols)
  names(out_cols) <- spec$name

  for (i in seq_len(n_cols)) {
    col_name <- spec$name[[i]]
    pg_type <- spec$pg_type[[i]]
    is_bool <- isTRUE(spec$is_bool[[i]])
    raw_col <- vpro_pg_match_df_col(df, col_name)

    if (is_bool) {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA_integer_, n_rows) else vpro_logical_to_access(raw_col)
    } else if (identical(pg_type, "TEXT")) {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA_character_, n_rows) else vpro_pg_format_utc_text(raw_col, col_name)
    } else if (pg_type %in% c("BIGINT", "SMALLINT")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_integer_, n_rows)
      } else {
        num <- suppressWarnings(as.double(raw_col))
        num[!is.finite(num)] <- NA_real_
        res_int <- rep(NA_integer_, n_rows)
        ok <- !is.na(num)
        if (any(ok)) {
          res_int[ok] <- as.integer(vpro_go_round(num[ok]))
        }
        out_cols[[i]] <- res_int
      }
    } else if (identical(pg_type, "DOUBLE PRECISION")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_real_, n_rows)
      } else {
        num <- suppressWarnings(as.double(raw_col))
        num[!is.finite(num)] <- NA_real_
        out_cols[[i]] <- as.double(num)
      }
    } else {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA, n_rows) else raw_col
    }
  }

  as.data.frame(out_cols, stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE)
}

vpro_pg_canonicalize_to_tidy <- function(df, spec) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  n_rows <- nrow(df)
  n_cols <- nrow(spec)
  out_cols <- vector("list", n_cols)
  names(out_cols) <- spec$name

  for (i in seq_len(n_cols)) {
    col_name <- spec$name[[i]]
    pg_type <- spec$pg_type[[i]]
    is_bool <- isTRUE(spec$is_bool[[i]])
    is_cover <- isTRUE(spec$is_cover[[i]])
    raw_col <- vpro_pg_match_df_col(df, col_name)

    if (is_bool) {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA, n_rows) else vpro_access_to_logical(raw_col)
    } else if (identical(pg_type, "TEXT")) {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA_character_, n_rows) else vpro_pg_format_utc_text(raw_col, col_name)
    } else if (pg_type %in% c("BIGINT", "SMALLINT")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_integer_, n_rows)
      } else {
        num <- suppressWarnings(as.double(raw_col))
        num[!is.finite(num)] <- NA_real_
        res_int <- rep(NA_integer_, n_rows)
        ok <- !is.na(num)
        if (any(ok)) {
          res_int[ok] <- as.integer(vpro_go_round(num[ok]))
        }
        out_cols[[i]] <- res_int
      }
    } else if (identical(pg_type, "DOUBLE PRECISION")) {
      if (is.null(raw_col)) {
        out_cols[[i]] <- rep(NA_real_, n_rows)
      } else {
        num <- suppressWarnings(as.double(raw_col))
        num[!is.finite(num)] <- NA_real_
        out_cols[[i]] <- if (is_cover) vpro_narrow_float32(num) else as.double(num)
      }
    } else {
      out_cols[[i]] <- if (is.null(raw_col)) rep(NA, n_rows) else raw_col
    }
  }

  tibble::as_tibble(out_cols)
}

# Tamper-Evident Audit SHA-256 Chain & Unique Transaction IDs ------------------

vpro_compute_audit_row_hash <- function(prev_hash, merge_tx_id, vp08_audit_values) {
  prev_s <- if (is.null(prev_hash) || length(prev_hash) == 0L || is.na(prev_hash[[1L]])) {
    ""
  } else {
    enc2utf8(as.character(prev_hash[[1L]]))
  }
  tx_s <- if (is.null(merge_tx_id) || length(merge_tx_id) == 0L || is.na(merge_tx_id[[1L]])) {
    ""
  } else {
    enc2utf8(as.character(merge_tx_id[[1L]]))
  }

  audit_spec <- .vpro_pg_vp08_spec_map$Audit
  vals_list <- if (is.data.frame(vp08_audit_values)) {
    if (nrow(vp08_audit_values) != 1L) {
      cli::cli_abort(
        "{.arg vp08_audit_values} data frame must have exactly 1 row.",
        class = c("vpro_error_cloud", "vpro_error")
      )
    }
    if (all(audit_spec$name %in% names(vp08_audit_values))) {
      as.list(vp08_audit_values[1L, audit_spec$name, drop = FALSE])
    } else if (ncol(vp08_audit_values) == nrow(audit_spec)) {
      as.list(vp08_audit_values[1L, , drop = FALSE])
    } else {
      cli::cli_abort(
        "{.arg vp08_audit_values} must provide all 11 VP08 Audit columns.",
        class = c("vpro_error_cloud", "vpro_error")
      )
    }
  } else {
    lst <- as.list(vp08_audit_values)
    if (!is.null(names(lst)) && all(audit_spec$name %in% names(lst))) {
      lst[audit_spec$name]
    } else if (length(lst) == nrow(audit_spec)) {
      lst
    } else {
      cli::cli_abort(
        "{.arg vp08_audit_values} must contain exactly 11 VP08 Audit values.",
        class = c("vpro_error_cloud", "vpro_error")
      )
    }
  }

  frame_part <- function(s) {
    s_utf8 <- enc2utf8(s)
    nb <- nchar(s_utf8, type = "bytes")
    paste0(nb, ":", s_utf8, "|")
  }

  parts <- character(2L + nrow(audit_spec))
  parts[[1L]] <- frame_part(prev_s)
  parts[[2L]] <- frame_part(tx_s)

  for (k in seq_len(nrow(audit_spec))) {
    val <- vals_list[[k]]
    if (is.null(val) || length(val) == 0L || (length(val) == 1L && is.na(val[[1L]]))) {
      parts[[2L + k]] <- frame_part("<NULL>")
      next
    }
    if (isTRUE(audit_spec$is_bool[[k]])) {
      acc <- vpro_logical_to_access(val[[1L]])
      parts[[2L + k]] <- if (is.na(acc)) frame_part("<NULL>") else frame_part(paste0("I:", acc))
    } else if (identical(audit_spec$pg_type[[k]], "BIGINT")) {
      v1 <- val[[1L]]
      if (is.integer(v1)) {
        parts[[2L + k]] <- frame_part(sprintf("I:%d", v1))
      } else if (is.numeric(v1)) {
        if (!is.finite(v1)) {
          parts[[2L + k]] <- frame_part("<NULL>")
        } else {
          parts[[2L + k]] <- frame_part(sprintf("I:%.0f", vpro_go_round(v1)))
        }
      } else {
        s1 <- trimws(as.character(v1))
        if (grepl("^-?[0-9]+$", s1)) {
          parts[[2L + k]] <- frame_part(paste0("I:", s1))
        } else {
          parts[[2L + k]] <- frame_part(paste0("V:", s1))
        }
      }
    } else {
      s1 <- vpro_pg_format_utc_text(val[[1L]], audit_spec$name[[k]])
      parts[[2L + k]] <- if (is.na(s1)) frame_part("<NULL>") else frame_part(paste0("S:", s1))
    }
  }

  payload <- paste0(parts, collapse = "")
  vpro_sha256_raw_list(list(charToRaw(enc2utf8(payload))))[[1L]]
}

vpro_uuid_v4 <- function() {
  bytes <- NULL
  if (file.exists("/dev/urandom")) {
    bytes <- tryCatch(
      {
        con_ur <- file("/dev/urandom", open = "rb", raw = TRUE)
        on.exit(close(con_ur), add = TRUE)
        as.integer(readBin(con_ur, what = "raw", n = 16L))
      },
      error = function(e) NULL
    )
  }
  if (is.null(bytes) || length(bytes) != 16L) {
    bytes <- sample.int(256L, 16L, replace = TRUE) - 1L
  }
  bytes[[7L]] <- bitwOr(bitwAnd(bytes[[7L]], 15L), 64L)
  bytes[[9L]] <- bitwOr(bitwAnd(bytes[[9L]], 63L), 128L)
  hex <- sprintf("%02x", bytes)
  paste0(
    paste(hex[1L:4L], collapse = ""),
    "-",
    paste(hex[5L:6L], collapse = ""),
    "-",
    paste(hex[7L:8L], collapse = ""),
    "-",
    paste(hex[9L:10L], collapse = ""),
    "-",
    paste(hex[11L:16L], collapse = "")
  )
}

# DDL Generation Helpers for Idempotent Schema Bootstrap -----------------------
