# Headless PostgreSQL BECMaster Connection, Schema Bootstrap & Canonicalizers --

.vpro_pg_s3_state <- new.env(parent = emptyenv())

.vpro_register_pg_s3 <- function() {
  if (isTRUE(.vpro_pg_s3_state$registered)) {
    return(invisible(NULL))
  }
  pkg_env <- environment(.vpro_register_pg_s3)
  reg_one <- function(gen_pkg, gen_name, cls) {
    fn_name <- paste0(gen_name, ".", cls)
    if (!exists(fn_name, envir = pkg_env, mode = "function", inherits = FALSE)) {
      return(invisible(NULL))
    }
    gen_env <- asNamespace(gen_pkg)
    s3_tbl <- gen_env[[".__S3MethodsTable__."]]
    if (is.environment(s3_tbl) && !exists(fn_name, envir = s3_tbl, inherits = FALSE)) {
      base::registerS3method(gen_name, cls, get(fn_name, envir = pkg_env), envir = gen_env)
    }
    invisible(NULL)
  }

  reg_one("base", "print", "vpro_pg_conn")
  reg_one("base", "print", "vpro_pg_status")
  reg_one("tibble", "as_tibble", "vpro_pg_status")

  .vpro_pg_s3_state$registered <- TRUE
  invisible(NULL)
}

.vpro_valid_sslmodes <- c(
  "disable",
  "allow",
  "prefer",
  "require",
  "verify-ca",
  "verify-full"
)

.vpro_genesis_audit_hash <- strrep("0", 64L)

# Internal Dotenv, URL & Secret-Safe Credential Resolution ---------------------

vpro_parse_dotenv <- function(lines) {
  out <- stats::setNames(character(0L), character(0L))
  if (is.null(lines) || length(lines) == 0L) {
    return(out)
  }
  chr <- as.character(lines)
  chr <- chr[!is.na(chr)]
  if (length(chr) == 0L) {
    return(out)
  }
  raw_lines <- unlist(strsplit(chr, "\r?\n", perl = TRUE), use.names = FALSE)
  for (raw_line in raw_lines) {
    line <- trimws(raw_line)
    if (!nzchar(line) || startsWith(line, "#")) {
      next
    }
    line <- trimws(sub("^export[[:space:]]+", "", line))
    eq_pos <- regexpr("=", line, fixed = TRUE)[[1L]]
    if (eq_pos <= 1L) {
      next
    }
    key <- trimws(substr(line, 1L, eq_pos - 1L))
    val <- trimws(substring(line, eq_pos + 1L))
    n_val <- nchar(val)
    if (n_val >= 2L && (
      (startsWith(val, '"') && endsWith(val, '"')) ||
      (startsWith(val, "'") && endsWith(val, "'"))
    )) {
      val <- substr(val, 2L, n_val - 1L)
    } else {
      hash_pos <- regexpr("[[:space:]]#", val)[[1L]]
      if (hash_pos > 0L) {
        val <- trimws(substr(val, 1L, hash_pos - 1L))
      }
    }
    if (nzchar(key)) {
      out[key] <- val
    }
  }
  out
}

vpro_urldecode_safe <- function(s) {
  if (is.null(s) || length(s) == 0L || is.na(s[[1L]]) || !nzchar(s[[1L]])) {
    return("")
  }
  str <- as.character(s[[1L]])
  if (!grepl("%", str, fixed = TRUE)) {
    return(str)
  }
  if (grepl("^(?:[^%]|%[0-9A-Fa-f]{2})*$", str, perl = TRUE)) {
    return(utils::URLdecode(str))
  }
  m <- gregexpr("(?:%[0-9A-Fa-f]{2})+", str, perl = TRUE)
  regmatches(str, m) <- lapply(regmatches(str, m), function(chunks) {
    vapply(chunks, utils::URLdecode, character(1L), USE.NAMES = FALSE)
  })
  str
}

vpro_parse_pg_url_impl <- function(raw_url) {
  if (!is.character(raw_url) || length(raw_url) != 1L || is.na(raw_url) || !nzchar(trimws(raw_url))) {
    cli::cli_abort("PostgreSQL connection URL must be a non-empty character string.")
  }
  u <- trimws(raw_url)
  if (!grepl("^postgres(?:ql)?://", u, ignore.case = TRUE, perl = TRUE)) {
    cli::cli_abort("Invalid PostgreSQL URL scheme (expected {.code postgres://} or {.code postgresql://}).")
  }
  rest <- sub("^postgres(?:ql)?://", "", u, ignore.case = TRUE, perl = TRUE)

  q_pos <- regexpr("?", rest, fixed = TRUE)[[1L]]
  if (q_pos > 0L) {
    auth_path <- substr(rest, 1L, q_pos - 1L)
    query_str <- substring(rest, q_pos + 1L)
  } else {
    auth_path <- rest
    query_str <- ""
  }

  slash_pos <- regexpr("/", auth_path, fixed = TRUE)[[1L]]
  if (slash_pos > 0L) {
    authority <- substr(auth_path, 1L, slash_pos - 1L)
    path_str <- substring(auth_path, slash_pos + 1L)
  } else {
    authority <- auth_path
    path_str <- ""
  }

  at_locs <- gregexpr("@", authority, fixed = TRUE)[[1L]]
  if (at_locs[[1L]] > 0L) {
    last_at <- at_locs[[length(at_locs)]]
    userinfo <- substr(authority, 1L, last_at - 1L)
    hostport <- substring(authority, last_at + 1L)
    colon_pos <- regexpr(":", userinfo, fixed = TRUE)[[1L]]
    if (colon_pos > 0L) {
      user <- vpro_urldecode_safe(substr(userinfo, 1L, colon_pos - 1L))
      password <- vpro_urldecode_safe(substring(userinfo, colon_pos + 1L))
    } else {
      user <- vpro_urldecode_safe(userinfo)
      password <- ""
    }
  } else {
    hostport <- authority
    user <- ""
    password <- ""
  }

  port_str <- ""
  if (startsWith(hostport, "[")) {
    close_br <- regexpr("]", hostport, fixed = TRUE)[[1L]]
    if (close_br <= 1L) {
      cli::cli_abort("Malformed bracketed IPv6 host in PostgreSQL URL.")
    }
    host <- substr(hostport, 2L, close_br - 1L)
    after_br <- substring(hostport, close_br + 1L)
    if (startsWith(after_br, ":") && nchar(after_br) > 1L) {
      port_str <- substring(after_br, 2L)
    } else if (nzchar(after_br)) {
      cli::cli_abort("Malformed port specification in PostgreSQL URL.")
    }
  } else {
    colon_pos <- regexpr(":", hostport, fixed = TRUE)[[1L]]
    if (colon_pos > 0L) {
      host <- vpro_urldecode_safe(substr(hostport, 1L, colon_pos - 1L))
      port_str <- substring(hostport, colon_pos + 1L)
    } else {
      host <- vpro_urldecode_safe(hostport)
    }
  }

  dbname <- if (nzchar(path_str)) vpro_urldecode_safe(path_str) else ""
  sslmode <- ""

  if (nzchar(query_str)) {
    pairs <- strsplit(query_str, "&", fixed = TRUE)[[1L]]
    for (pair in pairs) {
      if (!nzchar(pair)) next
      eq <- regexpr("=", pair, fixed = TRUE)[[1L]]
      if (eq > 0L) {
        qk <- tolower(trimws(vpro_urldecode_safe(substr(pair, 1L, eq - 1L))))
        qv <- vpro_urldecode_safe(gsub("+", " ", substring(pair, eq + 1L), fixed = TRUE))
      } else {
        qk <- tolower(trimws(vpro_urldecode_safe(pair)))
        qv <- ""
      }
      if (identical(qk, "sslmode") && nzchar(qv)) {
        sslmode <- trimws(qv)
      } else if (identical(qk, "host") && !nzchar(host) && nzchar(qv)) {
        host <- trimws(qv)
      } else if (identical(qk, "port") && !nzchar(port_str) && nzchar(qv)) {
        port_str <- trimws(qv)
      } else if (qk %in% c("dbname", "database") && !nzchar(dbname) && nzchar(qv)) {
        dbname <- trimws(qv)
      } else if (identical(qk, "user") && !nzchar(user) && nzchar(qv)) {
        user <- qv
      } else if (identical(qk, "password") && !nzchar(password) && nzchar(qv)) {
        password <- qv
      }
    }
  }

  explicit_port <- nzchar(port_str)
  if (explicit_port) {
    if (!grepl("^[0-9]+$", port_str)) {
      cli::cli_abort("Invalid port in PostgreSQL URL (must be an integer in 1..65535).")
    }
    port_num <- suppressWarnings(as.integer(port_str))
    if (is.na(port_num) || port_num < 1L || port_num > 65535L) {
      cli::cli_abort("Invalid port in PostgreSQL URL (must be an integer in 1..65535).")
    }
  } else {
    port_num <- 5432L
  }

  list(
    host = host,
    port = port_num,
    dbname = dbname,
    user = user,
    password = password,
    sslmode = sslmode,
    explicit_port = explicit_port
  )
}

vpro_parse_pg_url <- function(raw_url) {
  parsed <- vpro_parse_pg_url_impl(raw_url)
  list(
    host = parsed$host,
    port = parsed$port,
    dbname = parsed$dbname,
    user = parsed$user,
    password = parsed$password,
    sslmode = parsed$sslmode
  )
}

vpro_validate_pg_port <- function(port_val, label = "port") {
  if (is.numeric(port_val) && length(port_val) == 1L && !is.na(port_val)) {
    if (!is.finite(port_val) || port_val != trunc(port_val) || port_val < 1 || port_val > 65535) {
      cli::cli_abort("Invalid PostgreSQL {label} (must be an integer between 1 and 65535).")
    }
    return(as.integer(port_val))
  }
  s <- trimws(as.character(port_val[[1L]]))
  if (!grepl("^[0-9]+$", s)) {
    cli::cli_abort("Invalid PostgreSQL {label} (must be an integer between 1 and 65535).")
  }
  iv <- suppressWarnings(as.integer(s))
  if (is.na(iv) || iv < 1L || iv > 65535L) {
    cli::cli_abort("Invalid PostgreSQL {label} (must be an integer between 1 and 65535).")
  }
  iv
}

vpro_validate_pg_sslmode <- function(sslmode) {
  s <- trimws(as.character(sslmode[[1L]]))
  if (!(s %in% .vpro_valid_sslmodes)) {
    cli::cli_abort(
      "Invalid PostgreSQL {.arg sslmode} {.val {s}} (expected one of {.or {.val {.vpro_valid_sslmodes}}})."
    )
  }
  s
}

vpro_resolve_pg_credentials <- function(
  role = c("contributor", "custodian"),
  host = NULL,
  port = NULL,
  dbname = NULL,
  user = NULL,
  password = NULL,
  sslmode = NULL,
  url = NULL,
  config_dir = vpro_config_dir()
) {
  role <- match.arg(role)

  env_file_exists <- FALSE
  file_vals <- stats::setNames(character(0L), character(0L))
  if (!is.null(config_dir) && length(config_dir) == 1L && !is.na(config_dir) && nzchar(trimws(config_dir))) {
    env_path <- file.path(normalizePath(config_dir, winslash = "/", mustWork = FALSE), "becmaster.env")
    if (file.exists(env_path) && !dir.exists(env_path)) {
      raw_lines <- tryCatch(readLines(env_path, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
      if (!is.null(raw_lines)) {
        env_file_exists <- TRUE
        file_vals <- vpro_parse_dotenv(raw_lines)
      }
    }
  }

  resolve_key <- function(arg_val, env_key, trim_value = TRUE) {
    if (!is.null(arg_val) && length(arg_val) >= 1L && !is.na(arg_val[[1L]])) {
      raw_s <- as.character(arg_val[[1L]])
      if (nzchar(trimws(raw_s))) {
        return(list(val = if (trim_value) trimws(raw_s) else raw_s, tier = 1L))
      }
    }
    env_s <- Sys.getenv(env_key, unset = "")
    if (nzchar(trimws(env_s))) {
      return(list(val = if (trim_value) trimws(env_s) else trimws(env_s), tier = 2L))
    }
    if (env_key %in% names(file_vals)) {
      file_s <- file_vals[[env_key]]
      if (!is.na(file_s) && nzchar(trimws(file_s))) {
        return(list(val = if (trim_value) trimws(file_s) else file_s, tier = 3L))
      }
    }
    list(val = "", tier = 4L)
  }

  is_custodian <- identical(role, "custodian")
  user_key <- if (is_custodian) "VPRO_PG_ADMIN_USER" else "VPRO_PG_USER"
  pass_key <- if (is_custodian) "VPRO_PG_ADMIN_PASSWORD" else "VPRO_PG_PASSWORD"
  url_key <- if (is_custodian) "VPRO_PG_ADMIN_URL" else "VPRO_PG_URL"

  r_host <- resolve_key(host, "VPRO_PG_HOST", trim_value = TRUE)
  r_port <- resolve_key(port, "VPRO_PG_PORT", trim_value = TRUE)
  r_db <- resolve_key(dbname, "VPRO_PG_DBNAME", trim_value = TRUE)
  r_ssl <- resolve_key(sslmode, "VPRO_PG_SSLMODE", trim_value = TRUE)
  r_user <- resolve_key(user, user_key, trim_value = TRUE)
  r_pass <- resolve_key(password, pass_key, trim_value = FALSE)
  r_url <- resolve_key(url, url_key, trim_value = TRUE)

  resolved_host <- r_host$val
  resolved_port <- if (nzchar(r_port$val)) vpro_validate_pg_port(r_port$val) else 5432L
  resolved_db <- if (nzchar(r_db$val)) r_db$val else "becmaster"
  resolved_ssl <- if (nzchar(r_ssl$val)) r_ssl$val else "require"
  resolved_user <- r_user$val
  resolved_pass <- r_pass$val
  resolved_url <- r_url$val

  # Explicit scalar host/user arguments override environment/file URLs
  if (nzchar(resolved_url) && r_url$tier > 1L && (r_host$tier == 1L || r_user$tier == 1L)) {
    resolved_url <- ""
    r_url$tier <- 4L
  }

  if (nzchar(resolved_url)) {
    parsed_u <- vpro_parse_pg_url_impl(resolved_url)
    url_eff_tier <- if (r_url$tier == 1L) 1.5 else as.numeric(r_url$tier)

    if (nzchar(parsed_u$host) && r_host$tier >= url_eff_tier) {
      resolved_host <- parsed_u$host
    }
    if (parsed_u$explicit_port && r_port$tier >= url_eff_tier) {
      resolved_port <- parsed_u$port
    }
    if (nzchar(parsed_u$dbname) && r_db$tier >= url_eff_tier) {
      resolved_db <- parsed_u$dbname
    }
    if (nzchar(parsed_u$user) && r_user$tier >= url_eff_tier) {
      resolved_user <- parsed_u$user
    }
    if (nzchar(parsed_u$password) && r_pass$tier >= url_eff_tier) {
      resolved_pass <- parsed_u$password
    }
    if (nzchar(parsed_u$sslmode) && r_ssl$tier >= url_eff_tier) {
      resolved_ssl <- parsed_u$sslmode
    }
  }

  resolved_port <- vpro_validate_pg_port(resolved_port)
  resolved_ssl <- vpro_validate_pg_sslmode(resolved_ssl)

  tiers_used <- c(r_host$tier, r_port$tier, r_db$tier, r_ssl$tier, r_user$tier, r_pass$tier, r_url$tier)
  min_tier <- min(tiers_used)
  configured <- nzchar(resolved_url) || (nzchar(resolved_host) && nzchar(resolved_user))

  source_lbl <- if (!configured && min_tier == 4L) {
    "unconfigured"
  } else if (min_tier == 1L) {
    "args"
  } else if (min_tier == 2L) {
    "env"
  } else if (min_tier == 3L) {
    "becmaster.env"
  } else {
    "unconfigured"
  }

  list(
    source = source_lbl,
    env_file_exists = env_file_exists,
    role = role,
    host = resolved_host,
    port = resolved_port,
    dbname = resolved_db,
    sslmode = resolved_ssl,
    user = resolved_user,
    password = resolved_pass,
    url = resolved_url
  )
}

vpro_redact_pg_secrets <- function(msg, secrets = character(), redact_ip = FALSE) {
  if (is.null(msg)) {
    return("")
  }
  out <- as.character(msg)
  if (length(out) == 0L) {
    return(character(0L))
  }
  ok <- !is.na(out) & nzchar(out)
  if (!any(ok)) {
    return(out)
  }

  cand <- character(0L)
  add_candidate <- function(val) {
    if (is.null(val) || length(val) == 0L) return(invisible(NULL))
    for (item in as.character(val)) {
      if (is.na(item)) next
      for (v in unique(c(item, trimws(item)))) {
        if (nchar(v) < 1L) next
        cand <<- c(
          cand,
          v,
          utils::URLencode(v, reserved = TRUE),
          utils::URLencode(v, reserved = FALSE)
        )
        if (grepl("^postgres(?:ql)?://", v, ignore.case = TRUE, perl = TRUE)) {
          pw <- tryCatch(vpro_parse_pg_url_impl(v)$password, error = function(e) "")
          if (nchar(pw) >= 1L) {
            cand <<- c(
              cand,
              pw,
              utils::URLencode(pw, reserved = TRUE),
              utils::URLencode(pw, reserved = FALSE)
            )
          }
        }
      }
    }
    invisible(NULL)
  }
  add_candidate(secrets)
  cand <- unique(cand[nzchar(cand) & nchar(cand) >= 1L])
  if (length(cand) > 1L) {
    cand <- cand[order(nchar(cand), decreasing = TRUE)]
  }

  sub_out <- out[ok]
  # Scrub exact secret values first so quoted passwords never leave unredacted suffixes
  for (s in cand) {
    sub_out <- gsub(s, "<redacted>", sub_out, fixed = TRUE)
  }
  sub_out <- gsub(
    "(?i)postgres(?:ql)?://[^[:space:]\"']+",
    "postgres://<redacted>",
    sub_out,
    perl = TRUE
  )
  sub_out <- gsub(
    "(?i)((?:VPRO_PG_(?:ADMIN_)?PASSWORD|PGPASSWORD|password)\\s*=\\s*)([^[:space:]\"']+|'[^']*'|\"[^\"]*\")",
    "\\1<redacted>",
    sub_out,
    perl = TRUE
  )
  if (isTRUE(redact_ip)) {
    sub_out <- gsub("\\b\\d{1,3}(?:\\.\\d{1,3}){3}\\b", "<redacted-ip>", sub_out, perl = TRUE)
  }
  out[ok] <- sub_out
  out
}

vpro_pg_exec_safe <- function(expr_fn, secrets = character(), action = "PostgreSQL operation") {
  tryCatch(
    expr_fn(),
    error = function(e) {
      raw_msg <- conditionMessage(e)
      clean_msg <- vpro_redact_pg_secrets(raw_msg, secrets = secrets)
      cli::cli_abort("{action} failed: {clean_msg}", parent = NA)
    }
  )
}

vpro_assert_pg_conn <- function(con, require_custodian = FALSE) {
  if (!inherits(con, "vpro_pg_conn") || !is.list(con) || is.null(con$conn)) {
    cli::cli_abort(
      "{.arg con} must be a {.cls vpro_pg_conn} connection created by {.fn vpro_master_connect}."
    )
  }
  valid <- tryCatch(DBI::dbIsValid(con$conn), error = function(e) FALSE)
  if (!isTRUE(valid)) {
    cli::cli_abort(
      "PostgreSQL BECMaster connection is closed or invalid. Reconnect with {.fn vpro_master_connect}."
    )
  }
  if (isTRUE(require_custodian) && !identical(con$role, "custodian")) {
    cli::cli_abort(c(
      "This operation requires a {.val custodian} PostgreSQL connection (active role: {.val {con$role}}).",
      "i" = "Connect with {.code vpro_master_connect(role = \"custodian\")}."
    ))
  }
  invisible(con)
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
  already_in_tx <- FALSE
  withCallingHandlers(
    vpro_muffle_pg_result_warning(DBI::dbExecute(conn, begin_sql)),
    warning = function(w) {
      if (grepl("already a transaction in progress", conditionMessage(w), ignore.case = TRUE)) {
        already_in_tx <<- TRUE
        invokeRestart("muffleWarning")
      }
    }
  )
  if (already_in_tx) {
    cli::cli_abort(
      "Cannot start isolated transaction in {.fn {caller_fn}} because {.arg con} already has an open PostgreSQL transaction."
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

# Canonical VP08 & Standards Column Specifications (1:1 with columns.go) -------

vpro_pg_tcol <- function(name, sqlite_type, utf16_max = 0L) {
  list(name, "TEXT", sqlite_type, FALSE, FALSE, as.integer(utf16_max))
}

vpro_pg_icol <- function(name, sqlite_type) {
  list(name, "BIGINT", sqlite_type, FALSE, FALSE, 0L)
}

vpro_pg_fcol <- function(name, sqlite_type, is_cover = FALSE) {
  list(name, "DOUBLE PRECISION", sqlite_type, FALSE, isTRUE(is_cover), 0L)
}

vpro_pg_bcol <- function(name) {
  list(name, "SMALLINT", "BOOLEAN", TRUE, FALSE, 0L)
}

vpro_pg_build_spec_df <- function(rows) {
  data.frame(
    name = vapply(rows, `[[`, character(1L), 1L),
    pg_type = vapply(rows, `[[`, character(1L), 2L),
    sqlite_type = vapply(rows, `[[`, character(1L), 3L),
    is_bool = vapply(rows, `[[`, logical(1L), 4L),
    is_cover = vapply(rows, `[[`, logical(1L), 5L),
    utf16_max = vapply(rows, `[[`, integer(1L), 6L),
    stringsAsFactors = FALSE
  )
}

.vpro_pg_vp08_spec_map <- list(
  Env = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro_pg_tcol("FieldNumber", "VARCHAR", 50L),
    vpro_pg_tcol("ProjectID", "VARCHAR", 30L),
    vpro_pg_tcol("FSRegionDistrict", "VARCHAR", 7L),
    vpro_pg_tcol("Date", "TIMESTAMP", 0L),
    vpro_pg_tcol("SiteSurveyor", "VARCHAR", 0L),
    vpro_pg_tcol("PlotRepresenting", "VARCHAR", 0L),
    vpro_pg_tcol("Location", "VARCHAR", 0L),
    vpro_pg_tcol("Ecosection", "VARCHAR", 3L),
    vpro_pg_tcol("NtsMapSheet", "VARCHAR", 8L),
    vpro_pg_fcol("Longitude", "DOUBLE", FALSE),
    vpro_pg_fcol("Latitude", "DOUBLE", FALSE),
    vpro_pg_tcol("UTMZone", "VARCHAR", 0L),
    vpro_pg_fcol("UTMEasting", "REAL", FALSE),
    vpro_pg_fcol("UTMNorthing", "REAL", FALSE),
    vpro_pg_icol("LocationAccuracy", "SMALLINT"),
    vpro_pg_tcol("AirPhotoNum", "VARCHAR", 20L),
    vpro_pg_fcol("XCoord", "REAL", FALSE),
    vpro_pg_fcol("YCoord", "REAL", FALSE),
    vpro_pg_tcol("Zone", "VARCHAR", 4L),
    vpro_pg_tcol("SubZone", "VARCHAR", 8L),
    vpro_pg_tcol("SiteSeries", "VARCHAR", 5L),
    vpro_pg_tcol("SiteModifier1", "VARCHAR", 0L),
    vpro_pg_tcol("SiteModifier2", "VARCHAR", 0L),
    vpro_pg_tcol("TransDistrib", "VARCHAR", 0L),
    vpro_pg_tcol("RealmClass", "VARCHAR", 5L),
    vpro_pg_tcol("MapUnit", "VARCHAR", 30L),
    vpro_pg_tcol("SnowCoverregime", "VARCHAR", 1L),
    vpro_pg_tcol("MoistureRegime", "VARCHAR", 0L),
    vpro_pg_tcol("NutrientRegime", "VARCHAR", 0L),
    vpro_pg_tcol("SuccessionalStatus", "VARCHAR", 0L),
    vpro_pg_tcol("StructuralStage", "VARCHAR", 0L),
    vpro_pg_tcol("StructuralStageMod", "VARCHAR", 0L),
    vpro_pg_icol("StandAge", "SMALLINT"),
    vpro_pg_icol("Elevation", "SMALLINT"),
    vpro_pg_fcol("SlopeGradient", "REAL", FALSE),
    vpro_pg_icol("Aspect", "SMALLINT"),
    vpro_pg_tcol("MesoSlopePosition", "VARCHAR", 0L),
    vpro_pg_tcol("SurfaceShape", "VARCHAR", 0L),
    vpro_pg_tcol("SurfaceTopographyType", "VARCHAR", 0L),
    vpro_pg_tcol("SurfaceTopographySize", "VARCHAR", 0L),
    vpro_pg_tcol("WaterSource", "VARCHAR", 5L),
    vpro_pg_tcol("Photo", "VARCHAR", 50L),
    vpro_pg_tcol("Exposure1", "VARCHAR", 2L),
    vpro_pg_tcol("Exposure2", "VARCHAR", 2L),
    vpro_pg_tcol("SiteDisturbance1", "VARCHAR", 8L),
    vpro_pg_tcol("SiteDisturbance2", "VARCHAR", 8L),
    vpro_pg_tcol("SiteDisturbance3", "VARCHAR", 8L),
    vpro_pg_fcol("SubstrateDecWood", "REAL", FALSE),
    vpro_pg_fcol("SubstrateBedRock", "REAL", FALSE),
    vpro_pg_fcol("SubstrateRocks", "REAL", FALSE),
    vpro_pg_fcol("SubstrateMineralSoil", "REAL", FALSE),
    vpro_pg_fcol("SubstrateOrganicMatter", "REAL", FALSE),
    vpro_pg_fcol("SubstrateWater", "REAL", FALSE),
    vpro_pg_tcol("SiteNotes", "TEXT", 0L),
    vpro_pg_tcol("SoilSurveyor", "VARCHAR", 30L),
    vpro_pg_tcol("BedrockGeology1", "VARCHAR", 4L),
    vpro_pg_tcol("BedrockGeology2", "VARCHAR", 4L),
    vpro_pg_tcol("BedrockGeology3", "VARCHAR", 4L),
    vpro_pg_tcol("CoarseFragLith1", "VARCHAR", 12L),
    vpro_pg_tcol("CoarseFragLith2", "VARCHAR", 12L),
    vpro_pg_tcol("CoarseFragLith3", "VARCHAR", 12L),
    vpro_pg_tcol("TerrainTextureSurf", "VARCHAR", 3L),
    vpro_pg_tcol("SurficialMaterialSurf", "VARCHAR", 6L),
    vpro_pg_tcol("SurfaceExpSurf", "VARCHAR", 3L),
    vpro_pg_tcol("GeoMorProSurf", "VARCHAR", 3L),
    vpro_pg_tcol("TerrainTextureSubSurf", "VARCHAR", 3L),
    vpro_pg_tcol("SurficialMaterialSubSurf", "VARCHAR", 6L),
    vpro_pg_tcol("SurfaceExpSubSurf", "VARCHAR", 3L),
    vpro_pg_tcol("GeoMorProSubSurf", "VARCHAR", 3L),
    vpro_pg_tcol("FloodingRegimeFreq", "VARCHAR", 7L),
    vpro_pg_tcol("MoistureRegimeSub", "VARCHAR", 0L),
    vpro_pg_tcol("FloodingRegimeDur", "VARCHAR", 2L),
    vpro_pg_tcol("SoilDrainage", "VARCHAR", 5L),
    vpro_pg_icol("SeepageDepth", "SMALLINT"),
    vpro_pg_tcol("RootRestrictingType", "VARCHAR", 1L),
    vpro_pg_icol("RootRestrictingDepth", "SMALLINT"),
    vpro_pg_tcol("RootZoneParticleSize", "VARCHAR", 6L),
    vpro_pg_icol("RootingDepth", "SMALLINT"),
    vpro_pg_tcol("SoilClassSubGroup", "VARCHAR", 4L),
    vpro_pg_tcol("SoilClassGroup", "VARCHAR", 4L),
    vpro_pg_tcol("HumusForm", "VARCHAR", 4L),
    vpro_pg_tcol("HumusFormPhase", "VARCHAR", 50L),
    vpro_pg_tcol("pHMethodCodeMineral", "VARCHAR", 0L),
    vpro_pg_tcol("pHMethodCodeOrganic", "VARCHAR", 0L),
    vpro_pg_tcol("SoilNotes", "TEXT", 0L),
    vpro_pg_tcol("VegSurveyor", "VARCHAR", 30L),
    vpro_pg_fcol("StrataCoverTree", "REAL", FALSE),
    vpro_pg_fcol("StrataCoverShrub", "REAL", FALSE),
    vpro_pg_fcol("StrataCoverHerb", "REAL", FALSE),
    vpro_pg_fcol("StrataCoverMoss", "REAL", FALSE),
    vpro_pg_tcol("VegNotes", "TEXT", 0L),
    vpro_pg_tcol("HydroGeoSystem", "VARCHAR", 3L),
    vpro_pg_tcol("HydroGeoSubSystem", "VARCHAR", 2L),
    vpro_pg_bcol("SpeciesListComplete"),
    vpro_pg_tcol("Temporary", "VARCHAR", 0L),
    vpro_pg_bcol("Flag"),
    vpro_pg_tcol("SV_PolygonNumber", "VARCHAR", 0L),
    vpro_pg_bcol("SV_FloodPlain"),
    vpro_pg_tcol("SV_StandAgeEstMeas", "VARCHAR", 0L),
    vpro_pg_fcol("SV_StandHeight", "REAL", FALSE),
    vpro_pg_tcol("SV_StandHeightEstMeas", "VARCHAR", 0L),
    vpro_pg_tcol("SV_CanopyComposition", "VARCHAR", 0L),
    vpro_pg_fcol("SV_SoilDepth", "REAL", FALSE),
    vpro_pg_tcol("SV_RootZoneTexture", "VARCHAR", 0L),
    vpro_pg_fcol("SV_PercentCoarseFrags", "REAL", FALSE),
    vpro_pg_fcol("SV_GleyingMottlingCM", "REAL", FALSE),
    vpro_pg_fcol("SV_WaterTableCM", "REAL", FALSE),
    vpro_pg_tcol("SV_FullCruiseCard", "VARCHAR", 0L),
    vpro_pg_tcol("SV_AhorizonType", "VARCHAR", 0L),
    vpro_pg_fcol("SV_AhorizonDepth", "REAL", FALSE),
    vpro_pg_fcol("ActiveLayerDepth", "REAL", FALSE)
  )),
  Admin = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("Plot", "VARCHAR", 7L),
    vpro_pg_icol("StartDate", "SMALLINT"),
    vpro_pg_tcol("PlotType", "VARCHAR", 10L),
    vpro_pg_fcol("PlotSize", "REAL", FALSE),
    vpro_pg_tcol("ProvinceStateTerritory", "VARCHAR", 0L),
    vpro_pg_tcol("SitePlotQuality", "VARCHAR", 15L),
    vpro_pg_tcol("VegPlotQuality", "VARCHAR", 15L),
    vpro_pg_tcol("SoilPlotQuality", "VARCHAR", 15L),
    vpro_pg_bcol("UpdatedFromCards"),
    vpro_pg_tcol("EnteredBy", "VARCHAR", 50L),
    vpro_pg_tcol("UserSiteUnit", "VARCHAR", 100L),
    vpro_pg_tcol("BECSiteUnit", "VARCHAR", 100L),
    vpro_pg_tcol("SiteUnitShortName", "VARCHAR", 0L),
    vpro_pg_tcol("SiteUnitLongName", "VARCHAR", 0L),
    vpro_pg_tcol("OfficeNotes", "TEXT", 0L),
    vpro_pg_fcol("HumusThickness", "REAL", FALSE),
    vpro_pg_tcol("GIS_BGC", "VARCHAR", 0L),
    vpro_pg_icol("GIS_BGC_VER", "SMALLINT"),
    vpro_pg_tcol("BEC_Use", "VARCHAR", 0L),
    vpro_pg_fcol("StrataCoverTotal", "REAL", FALSE)
  )),
  Veg = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro_pg_tcol("Species", "VARCHAR", 8L),
    vpro_pg_tcol("Layer", "VARCHAR", 2L),
    vpro_pg_fcol("Cover1", "REAL", TRUE),
    vpro_pg_fcol("Height1", "REAL", FALSE),
    vpro_pg_fcol("Cover2", "REAL", TRUE),
    vpro_pg_fcol("Height2", "REAL", FALSE),
    vpro_pg_fcol("Cover3", "REAL", TRUE),
    vpro_pg_fcol("Height3", "REAL", FALSE),
    vpro_pg_fcol("TotalA", "REAL", TRUE),
    vpro_pg_fcol("HeightA", "REAL", FALSE),
    vpro_pg_fcol("Cover4", "REAL", TRUE),
    vpro_pg_fcol("Height4", "REAL", FALSE),
    vpro_pg_fcol("Cover5", "REAL", TRUE),
    vpro_pg_fcol("Height5", "REAL", FALSE),
    vpro_pg_fcol("Cover5a", "REAL", TRUE),
    vpro_pg_fcol("Height5a", "REAL", FALSE),
    vpro_pg_fcol("Cover5b", "REAL", TRUE),
    vpro_pg_fcol("Height5b", "REAL", FALSE),
    vpro_pg_fcol("Cover5c", "REAL", TRUE),
    vpro_pg_fcol("Height5c", "REAL", FALSE),
    vpro_pg_fcol("TotalB", "REAL", TRUE),
    vpro_pg_tcol("HeightB", "VARCHAR", 0L),
    vpro_pg_fcol("Cover6", "REAL", TRUE),
    vpro_pg_fcol("Height6", "REAL", FALSE),
    vpro_pg_fcol("Cover7", "REAL", TRUE),
    vpro_pg_fcol("Cover8", "REAL", TRUE),
    vpro_pg_fcol("Cover9", "REAL", TRUE),
    vpro_pg_fcol("Cover10", "REAL", TRUE),
    vpro_pg_tcol("Collected", "VARCHAR", 1L),
    vpro_pg_bcol("Flag"),
    vpro_pg_icol("ID", "INTEGER"),
    vpro_pg_icol("LL", "INTEGER"),
    vpro_pg_icol("AF", "SMALLINT"),
    vpro_pg_icol("DC", "SMALLINT"),
    vpro_pg_icol("UT", "SMALLINT"),
    vpro_pg_icol("VI", "SMALLINT"),
    vpro_pg_icol("PV", "INTEGER"),
    vpro_pg_icol("PG", "SMALLINT"),
    vpro_pg_icol("FFA", "SMALLINT"),
    vpro_pg_icol("Cultural1", "SMALLINT"),
    vpro_pg_icol("Cultural2", "SMALLINT"),
    vpro_pg_icol("Other1", "SMALLINT"),
    vpro_pg_icol("Other2", "SMALLINT")
  )),
  Humus = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro_pg_tcol("Horizon", "VARCHAR", 8L),
    vpro_pg_fcol("UpperDepth", "REAL", FALSE),
    vpro_pg_fcol("LowerDepth", "REAL", FALSE),
    vpro_pg_tcol("HumusStructureDegree", "VARCHAR", 0L),
    vpro_pg_tcol("HumusStructureKind", "VARCHAR", 0L),
    vpro_pg_tcol("MycelAbundance", "VARCHAR", 0L),
    vpro_pg_tcol("FecalAbundance", "VARCHAR", 0L),
    vpro_pg_tcol("RootsAbundance", "VARCHAR", 0L),
    vpro_pg_tcol("RootsSize", "VARCHAR", 0L),
    vpro_pg_icol("vonPost", "SMALLINT"),
    vpro_pg_fcol("HumusFormpH", "REAL", FALSE),
    vpro_pg_tcol("Consistence", "VARCHAR", 0L),
    vpro_pg_tcol("Character", "VARCHAR", 0L),
    vpro_pg_tcol("Fauna", "VARCHAR", 0L),
    vpro_pg_tcol("Comment", "TEXT", 0L),
    vpro_pg_bcol("Flag"),
    vpro_pg_icol("ID", "INTEGER")
  )),
  Mineral = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro_pg_tcol("Horizon", "VARCHAR", 8L),
    vpro_pg_fcol("UpperDepth", "REAL", FALSE),
    vpro_pg_fcol("LowerDepth", "REAL", FALSE),
    vpro_pg_tcol("PitDepthLimit", "VARCHAR", 0L),
    vpro_pg_tcol("Colour", "VARCHAR", 14L),
    vpro_pg_icol("ASP", "SMALLINT"),
    vpro_pg_tcol("Texture", "VARCHAR", 4L),
    vpro_pg_icol("PercentCoarseFragsGravel", "SMALLINT"),
    vpro_pg_icol("PercentCoarseFragsCobbles", "SMALLINT"),
    vpro_pg_icol("PercentCoarseFragsStones", "SMALLINT"),
    vpro_pg_icol("PercentCoarseFragsTotal", "SMALLINT"),
    vpro_pg_tcol("PercentCoarseFragsShape", "VARCHAR", 0L),
    vpro_pg_tcol("RootsAbundance", "VARCHAR", 0L),
    vpro_pg_tcol("RootsSize", "VARCHAR", 0L),
    vpro_pg_tcol("MineralStructureClass", "VARCHAR", 0L),
    vpro_pg_tcol("MineralStructureKind", "VARCHAR", 0L),
    vpro_pg_fcol("MineralFormpH", "REAL", FALSE),
    vpro_pg_tcol("MottlesAbundance", "VARCHAR", 0L),
    vpro_pg_tcol("MottlesSize", "VARCHAR", 0L),
    vpro_pg_tcol("MottlesContrast", "VARCHAR", 0L),
    vpro_pg_tcol("ClayFilmsFreq", "VARCHAR", 0L),
    vpro_pg_tcol("ClayFilmThickness", "VARCHAR", 0L),
    vpro_pg_tcol("Effervescence", "VARCHAR", 0L),
    vpro_pg_tcol("Porosity", "VARCHAR", 0L),
    vpro_pg_tcol("Comments", "TEXT", 0L),
    vpro_pg_bcol("Flag"),
    vpro_pg_icol("ID", "INTEGER")
  )),
  Other = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro_pg_tcol("DataName", "VARCHAR", 0L),
    vpro_pg_tcol("DataItem", "VARCHAR", 0L),
    vpro_pg_tcol("UserItem1", "VARCHAR", 0L),
    vpro_pg_tcol("UserItem2", "VARCHAR", 0L),
    vpro_pg_tcol("UserItem3", "VARCHAR", 0L),
    vpro_pg_bcol("UserFlag1"),
    vpro_pg_bcol("UserFlag2"),
    vpro_pg_bcol("UserFlag3"),
    vpro_pg_bcol("Flag"),
    vpro_pg_icol("ID", "INTEGER")
  )),
  Metadata = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("ProjectID", "VARCHAR", 30L),
    vpro_pg_icol("StartDate", "SMALLINT"),
    vpro_pg_icol("EndDate", "SMALLINT"),
    vpro_pg_tcol("ProjectTitle", "VARCHAR", 0L),
    vpro_pg_tcol("CoordinatingAgency", "VARCHAR", 0L),
    vpro_pg_tcol("ProponentFunder", "VARCHAR", 0L),
    vpro_pg_tcol("FieldCompanyAgency", "VARCHAR", 0L),
    vpro_pg_tcol("FieldLeader", "VARCHAR", 0L),
    vpro_pg_tcol("FieldDataCollectionTeam", "VARCHAR", 0L),
    vpro_pg_tcol("ProjectPurpose", "VARCHAR", 0L),
    vpro_pg_tcol("GeographicStudyArea", "VARCHAR", 0L),
    vpro_pg_tcol("GeographicStudyRegion", "VARCHAR", 0L),
    vpro_pg_icol("NumberOfFS882Plots", "INTEGER"),
    vpro_pg_icol("NumberOfSiteVisits", "SMALLINT"),
    vpro_pg_tcol("ProjectType", "VARCHAR", 0L),
    vpro_pg_tcol("ProjectTypeOther", "VARCHAR", 0L),
    vpro_pg_tcol("EcosysCollectionStandard", "VARCHAR", 0L),
    vpro_pg_tcol("EcosysCollectionStandardOther", "VARCHAR", 0L),
    vpro_pg_tcol("VegCoverMethod", "VARCHAR", 0L),
    vpro_pg_tcol("VegCoverMethodOther", "VARCHAR", 0L),
    vpro_pg_tcol("PlotMethod", "VARCHAR", 0L),
    vpro_pg_tcol("PlotMethodOther", "VARCHAR", 0L),
    vpro_pg_tcol("MensurationMethod", "VARCHAR", 0L),
    vpro_pg_tcol("MensurationMethodOther", "VARCHAR", 0L),
    vpro_pg_tcol("ExtraVegFieldDescription", "VARCHAR", 0L),
    vpro_pg_tcol("DataCustodian", "VARCHAR", 0L),
    vpro_pg_tcol("StorageLocation", "VARCHAR", 0L),
    vpro_pg_icol("CollectedSite", "SMALLINT"),
    vpro_pg_tcol("DataQualitySite", "VARCHAR", 0L),
    vpro_pg_icol("CollectedVeg", "SMALLINT"),
    vpro_pg_tcol("DataQualityVeg", "VARCHAR", 0L),
    vpro_pg_icol("CollectedSoil", "SMALLINT"),
    vpro_pg_tcol("DataQualitySoil", "VARCHAR", 0L),
    vpro_pg_icol("CollectedTerrain", "SMALLINT"),
    vpro_pg_tcol("DataQualityTerrain", "VARCHAR", 0L),
    vpro_pg_icol("CollectedMens", "SMALLINT"),
    vpro_pg_tcol("DataQualityMens", "VARCHAR", 0L),
    vpro_pg_icol("CollectedCWD", "SMALLINT"),
    vpro_pg_tcol("DataQualityCWD", "VARCHAR", 0L),
    vpro_pg_icol("CollectedWildTree", "SMALLINT"),
    vpro_pg_tcol("DataQualityWildTree", "VARCHAR", 0L),
    vpro_pg_icol("CollectedSoilChem", "SMALLINT"),
    vpro_pg_tcol("DataQualitySoilChem", "VARCHAR", 0L),
    vpro_pg_icol("CollectedWildlifeHabitatAssessment", "SMALLINT"),
    vpro_pg_tcol("DataQualityWildlifeHabitatAssessment", "VARCHAR", 0L),
    vpro_pg_tcol("CollectedCompleteOther", "VARCHAR", 0L),
    vpro_pg_tcol("CollectedPartialOther", "VARCHAR", 0L),
    vpro_pg_tcol("CollectedNoneOther", "VARCHAR", 0L),
    vpro_pg_tcol("GeoRefMethod", "VARCHAR", 0L),
    vpro_pg_tcol("GeoRefMethodOther", "VARCHAR", 0L),
    vpro_pg_tcol("Datum", "VARCHAR", 0L),
    vpro_pg_tcol("DatumOther", "VARCHAR", 0L),
    vpro_pg_tcol("CoordinateSystem", "VARCHAR", 0L),
    vpro_pg_tcol("CoordinateSystemOther", "VARCHAR", 0L),
    vpro_pg_tcol("AllSpecs", "VARCHAR", 0L),
    vpro_pg_tcol("TableOfLists", "VARCHAR", 0L),
    vpro_pg_tcol("CoverA1Description", "VARCHAR", 0L),
    vpro_pg_tcol("CoverA2Description", "VARCHAR", 0L),
    vpro_pg_tcol("CoverA3Description", "VARCHAR", 0L),
    vpro_pg_tcol("CoverADescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverB1Description", "VARCHAR", 0L),
    vpro_pg_tcol("CoverB2Description", "VARCHAR", 0L),
    vpro_pg_tcol("CoverB2aDescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverB2bDescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverB2cDescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverBDescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverCDescription", "VARCHAR", 0L),
    vpro_pg_tcol("CoverDDescription", "VARCHAR", 0L),
    vpro_pg_tcol("Cover8Description", "VARCHAR", 0L),
    vpro_pg_tcol("Cover9Description", "VARCHAR", 0L),
    vpro_pg_tcol("Cover10Description", "VARCHAR", 0L),
    vpro_pg_icol("BAPID", "INTEGER"),
    vpro_pg_tcol("DateLastEdited", "TIMESTAMP", 0L),
    vpro_pg_tcol("Notes", "TEXT", 0L),
    vpro_pg_icol("ID", "INTEGER")
  )),
  Audit = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("Project", "VARCHAR", 0L),
    vpro_pg_tcol("User", "VARCHAR", 0L),
    vpro_pg_tcol("PlotNumber", "VARCHAR", 0L),
    vpro_pg_tcol("Table", "VARCHAR", 0L),
    vpro_pg_tcol("EditField", "VARCHAR", 0L),
    vpro_pg_tcol("EditWhen", "TIMESTAMP", 0L),
    vpro_pg_tcol("BeforeEdit", "TEXT", 0L),
    vpro_pg_tcol("AfterEdit", "TEXT", 0L),
    vpro_pg_bcol("Restore"),
    vpro_pg_bcol("Flag"),
    vpro_pg_icol("ID", "INTEGER")
  ))
)

.vpro_pg_standards_spec_map <- list(
  usys_all_specs = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("YearOfChange", "TEXT", 0L),
    vpro_pg_tcol("ChangeDescription", "TEXT", 0L),
    vpro_pg_tcol("APCFamily", "TEXT", 0L),
    vpro_pg_tcol("FamilyCode", "TEXT", 0L),
    vpro_pg_tcol("OldCode", "TEXT", 0L),
    vpro_pg_tcol("Code", "TEXT", 0L),
    vpro_pg_tcol("SplCode", "TEXT", 0L),
    vpro_pg_tcol("TreeCode", "TEXT", 0L),
    vpro_pg_tcol("ScientificName", "TEXT", 0L),
    vpro_pg_icol("Lifeform", "INTEGER"),
    vpro_pg_tcol("Authority", "TEXT", 0L),
    vpro_pg_tcol("EnglishName_Old", "TEXT", 0L),
    vpro_pg_tcol("EnglishName", "TEXT", 0L),
    vpro_pg_tcol("common_name_pb", "TEXT", 0L),
    vpro_pg_tcol("Notes_on_names", "TEXT", 0L),
    vpro_pg_tcol("ShortenedGuideName", "TEXT", 0L),
    vpro_pg_tcol("Native", "TEXT", 0L),
    vpro_pg_tcol("Codetype", "TEXT", 0L),
    vpro_pg_tcol("Province", "TEXT", 0L),
    vpro_pg_icol("ID", "INTEGER"),
    vpro_pg_tcol("TaxonLevel", "TEXT", 0L),
    vpro_pg_icol("IsAttribute", "BOOLEAN"),
    vpro_pg_icol("Report", "INTEGER"),
    vpro_pg_tcol("SplCode_calc", "TEXT", 0L),
    vpro_pg_icol("Codelength", "INTEGER"),
    vpro_pg_tcol("CombinedEnglishName", "TEXT", 0L)
  )),
  usys_table_of_lists = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("ListName", "TEXT", 0L),
    vpro_pg_tcol("ListFilter", "TEXT", 0L),
    vpro_pg_fcol("ItemOrder", "REAL", FALSE),
    vpro_pg_tcol("Item", "TEXT", 0L),
    vpro_pg_tcol("ItemDescription", "TEXT", 0L),
    vpro_pg_tcol("FieldUsedIn", "TEXT", 0L),
    vpro_pg_tcol("ValidateLoops", "TEXT", 0L),
    vpro_pg_icol("Validate", "BOOLEAN"),
    vpro_pg_tcol("Note", "TEXT", 0L),
    vpro_pg_icol("Flag", "BOOLEAN")
  )),
  bec_site_series = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("RowID", "TEXT", 0L),
    vpro_pg_tcol("SourceID", "TEXT", 0L),
    vpro_pg_tcol("SSCode", "TEXT", 0L),
    vpro_pg_tcol("Name", "TEXT", 0L),
    vpro_pg_tcol("Region", "TEXT", 0L),
    vpro_pg_tcol("Zone", "TEXT", 0L),
    vpro_pg_tcol("SubZone", "TEXT", 0L),
    vpro_pg_tcol("BaseSubZone", "TEXT", 0L),
    vpro_pg_tcol("Variant", "TEXT", 0L),
    vpro_pg_tcol("Phase", "TEXT", 0L),
    vpro_pg_tcol("SiteSeries", "TEXT", 0L),
    vpro_pg_tcol("SiteSeriesPhase", "TEXT", 0L),
    vpro_pg_tcol("Variation", "TEXT", 0L),
    vpro_pg_tcol("Seral", "TEXT", 0L),
    vpro_pg_tcol("Description", "TEXT", 0L),
    vpro_pg_tcol("PlantAssociation", "TEXT", 0L),
    vpro_pg_tcol("Comments", "TEXT", 0L),
    vpro_pg_fcol("ReferenceID", "REAL", FALSE),
    vpro_pg_tcol("AddedDate", "TEXT", 0L),
    vpro_pg_tcol("ExpiredDate", "TEXT", 0L),
    vpro_pg_tcol("OriginalSourceID", "TEXT", 0L),
    vpro_pg_tcol("MergedBGC", "TEXT", 0L),
    vpro_pg_tcol("Suballiance", "TEXT", 0L),
    vpro_pg_tcol("Alliance", "TEXT", 0L),
    vpro_pg_tcol("MissingNpeNa", "TEXT", 0L),
    vpro_pg_tcol("TransferID", "TEXT", 0L),
    vpro_pg_icol("Flag", "BOOLEAN")
  )),
  master_site_unit_list = vpro_pg_build_spec_df(list(
    vpro_pg_icol("ID", "INTEGER"),
    vpro_pg_tcol("SiteSeries", "TEXT", 0L),
    vpro_pg_tcol("SiteSeriesLongName", "TEXT", 0L),
    vpro_pg_tcol("SiteSeriesScientificName", "TEXT", 0L),
    vpro_pg_icol("Level", "INTEGER")
  )),
  usys_zone_list = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("Zone", "TEXT", 0L),
    vpro_pg_tcol("SubZone", "TEXT", 0L),
    vpro_pg_tcol("ZoneDescription", "TEXT", 0L),
    vpro_pg_tcol("SubZoneVarDescription", "TEXT", 0L)
  )),
  project_metadata = vpro_pg_build_spec_df(list(
    vpro_pg_tcol("ProjectID", "TEXT", 0L),
    vpro_pg_tcol("ProjectTitle", "TEXT", 0L),
    vpro_pg_tcol("CoordinatingAgency", "TEXT", 0L),
    vpro_pg_tcol("ProponentFunder", "TEXT", 0L),
    vpro_pg_tcol("FieldCompanyAgency", "TEXT", 0L),
    vpro_pg_tcol("FieldLeader", "TEXT", 0L),
    vpro_pg_tcol("FieldDataCollectionTeam", "TEXT", 0L),
    vpro_pg_tcol("ProjectPurpose", "TEXT", 0L),
    vpro_pg_tcol("GeographicStudyArea", "TEXT", 0L),
    vpro_pg_tcol("GeographicStudyRegion", "TEXT", 0L),
    vpro_pg_tcol("GeographicStudyDistrict", "TEXT", 0L),
    vpro_pg_tcol("StartDate", "TIMESTAMP", 0L),
    vpro_pg_tcol("EndDate", "TIMESTAMP", 0L),
    vpro_pg_icol("NumberOfFS882Plots", "INTEGER"),
    vpro_pg_icol("NumberOfSiteVisits", "INTEGER"),
    vpro_pg_icol("CollectedSite", "INTEGER"),
    vpro_pg_icol("CollectedVeg", "INTEGER"),
    vpro_pg_icol("CollectedSoil", "INTEGER"),
    vpro_pg_icol("CollectedTerrain", "INTEGER"),
    vpro_pg_icol("CollectedMens", "INTEGER"),
    vpro_pg_icol("CollectedCWD", "INTEGER"),
    vpro_pg_icol("CollectedWildTree", "INTEGER"),
    vpro_pg_icol("CollectedSoilChem", "INTEGER"),
    vpro_pg_icol("CollectedOther", "INTEGER"),
    vpro_pg_tcol("CollectedCompleteOtherName", "TEXT", 0L),
    vpro_pg_tcol("CollectedPartialOtherName", "TEXT", 0L),
    vpro_pg_tcol("CollectedNoneOtherName", "TEXT", 0L),
    vpro_pg_icol("GeoRefMethod", "INTEGER"),
    vpro_pg_icol("Map", "INTEGER"),
    vpro_pg_icol("Datum", "INTEGER"),
    vpro_pg_icol("CoordinateSystem", "INTEGER"),
    vpro_pg_icol("EcosysCollectionStandard", "INTEGER"),
    vpro_pg_tcol("EcosysCollectionStandardOtherName", "TEXT", 0L),
    vpro_pg_icol("VegCoverMethod", "INTEGER"),
    vpro_pg_tcol("VegCoverMethodOtherName", "TEXT", 0L),
    vpro_pg_icol("MensurationMethod", "INTEGER"),
    vpro_pg_tcol("MensurationMethodOtherName", "TEXT", 0L),
    vpro_pg_tcol("ExtraVegFieldDescription", "TEXT", 0L),
    vpro_pg_icol("PlotMethod", "INTEGER"),
    vpro_pg_tcol("DataCustodian", "TEXT", 0L),
    vpro_pg_tcol("StorageLocation", "TEXT", 0L),
    vpro_pg_tcol("Notes", "TEXT", 0L)
  ))
)

vpro_pg_vp08_specs <- function(suffix) {
  if (!is.character(suffix) || length(suffix) != 1L || is.na(suffix) || !nzchar(trimws(suffix))) {
    cli::cli_abort("{.arg suffix} must be one of {.or {.val {names(.vpro_pg_vp08_spec_map)}}}.")
  }
  key <- names(.vpro_pg_vp08_spec_map)[tolower(names(.vpro_pg_vp08_spec_map)) == tolower(trimws(suffix))]
  if (length(key) != 1L) {
    cli::cli_abort("Unknown VP08 table suffix {.val {suffix}} (expected one of {.or {.val {names(.vpro_pg_vp08_spec_map)}}}).")
  }
  .vpro_pg_vp08_spec_map[[key]]
}

vpro_pg_standards_specs <- function(table) {
  if (!is.character(table) || length(table) != 1L || is.na(table) || !nzchar(trimws(table))) {
    cli::cli_abort("{.arg table} must be one of {.or {.val {names(.vpro_pg_standards_spec_map)}}}.")
  }
  key <- names(.vpro_pg_standards_spec_map)[tolower(names(.vpro_pg_standards_spec_map)) == tolower(trimws(table))]
  if (length(key) != 1L) {
    cli::cli_abort("Unknown standards table {.val {table}} (expected one of {.or {.val {names(.vpro_pg_standards_spec_map)}}}).")
  }
  .vpro_pg_standards_spec_map[[key]]
}

# Bidirectional Type Canonicalizers (SQLite <-> Postgres <-> Tidy R) -----------

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
          cli::cli_abort("Column {.field {col_name}} contains embedded NUL bytes.")
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
        trimmed <- tolower(trimws(raw_col))
        known_tok <- c("-1", "1", "true", "yes", "t", "y", "0", "false", "no", "f", "n")
        unrec <- !is.na(trimmed) & nzchar(trimmed) & !(trimmed %in% known_tok)
        if (any(unrec)) {
          parsed_int <- suppressWarnings(as.integer(trimmed[unrec]))
          if (anyNA(parsed_int)) {
            cli::cli_abort("Column {.field {col_name}} contains invalid Access boolean text.")
          }
          res_bool <- vpro_logical_to_access(raw_col)
          res_bool[unrec] <- ifelse(parsed_int != 0L, -1L, 0L)
          out_cols[[i]] <- res_bool
        } else {
          out_cols[[i]] <- vpro_logical_to_access(raw_col)
        }
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
            cli::cli_abort("Column {.field {col_name}} contains invalid UTF-8 text.")
          }
          u16 <- vpro_utf16_len(chr[non_na])
          if (anyNA(u16)) {
            cli::cli_abort("Column {.field {col_name}} contains invalid UTF-8 or unpaired UTF-16 surrogates.")
          }
          if (utf16_max > 0L && any(u16 > utf16_max)) {
            cli::cli_abort(
              "Column {.field {col_name}} exceeds maximum length of {utf16_max} UTF-16 code units."
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
        rounded <- round(num)
        ok <- !is.na(rounded)
        if (identical(pg_type, "SMALLINT") && any(ok & (rounded < -32768 | rounded > 32767))) {
          cli::cli_abort("Column {.field {col_name}} overflows PostgreSQL SMALLINT (-32768..32767).")
        }
        if (any(ok & (rounded < -2147483647 | rounded > 2147483647))) {
          cli::cli_abort("Column {.field {col_name}} overflows 32-bit R integer bounds.")
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
              cli::cli_abort("Cover column {.field {col_name}} must be finite and >= 0.")
            }
            narrowed <- vpro_narrow_float32(num)
            if (any(narrowed[non_na] < 0 | narrowed[non_na] >= 100)) {
              cli::cli_abort(
                "Cover column {.field {col_name}} must narrow to >= 0 and < 100 in IEEE-754 float32."
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
          res_int[ok] <- as.integer(round(num[ok]))
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
          res_int[ok] <- as.integer(round(num[ok]))
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

# Tamper-Evident Audit SHA-256 Chain & RFC 4122 UUID v4 ------------------------

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
      cli::cli_abort("{.arg vp08_audit_values} data frame must have exactly 1 row.")
    }
    if (all(audit_spec$name %in% names(vp08_audit_values))) {
      as.list(vp08_audit_values[1L, audit_spec$name, drop = FALSE])
    } else if (ncol(vp08_audit_values) == nrow(audit_spec)) {
      as.list(vp08_audit_values[1L, , drop = FALSE])
    } else {
      cli::cli_abort("{.arg vp08_audit_values} must provide all 11 VP08 Audit columns.")
    }
  } else {
    lst <- as.list(vp08_audit_values)
    if (!is.null(names(lst)) && all(audit_spec$name %in% names(lst))) {
      lst[audit_spec$name]
    } else if (length(lst) == nrow(audit_spec)) {
      lst
    } else {
      cli::cli_abort("{.arg vp08_audit_values} must contain exactly 11 VP08 Audit values.")
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
          parts[[2L + k]] <- frame_part(sprintf("I:%.0f", round(v1)))
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
    bytes <- tryCatch({
      con_ur <- file("/dev/urandom", open = "rb", raw = TRUE)
      on.exit(close(con_ur), add = TRUE)
      as.integer(readBin(con_ur, what = "raw", n = 16L))
    }, error = function(e) NULL)
  }
  if (is.null(bytes) || length(bytes) != 16L) {
    bytes <- sample.int(256L, 16L, replace = TRUE) - 1L
  }
  bytes[[7L]] <- bitwOr(bitwAnd(bytes[[7L]], 15L), 64L)
  bytes[[9L]] <- bitwOr(bitwAnd(bytes[[9L]], 63L), 128L)
  hex <- sprintf("%02x", bytes)
  paste0(
    paste(hex[1L:4L], collapse = ""), "-",
    paste(hex[5L:6L], collapse = ""), "-",
    paste(hex[7L:8L], collapse = ""), "-",
    paste(hex[9L:10L], collapse = ""), "-",
    paste(hex[11L:16L], collapse = "")
  )
}

# DDL Generation Helpers for Idempotent Schema Bootstrap -----------------------

vpro_pg_col_ddl <- function(spec) {
  q_names <- vpro_quote_ident(spec$name)
  defs <- paste0("  ", q_names, " ", spec$pg_type)
  bool_idx <- which(spec$is_bool)
  if (length(bool_idx) > 0L) {
    defs[bool_idx] <- paste0(defs[bool_idx], " CHECK (", q_names[bool_idx], " IN (-1, 0))")
  }
  defs
}

vpro_pg_master_table_ddl <- function(table, spec, pk_cols = character(), extra = character()) {
  defs <- vpro_pg_col_ddl(spec)
  if (length(pk_cols) > 0L) {
    defs <- c(defs, paste0("  PRIMARY KEY (", paste(vpro_quote_ident(pk_cols), collapse = ", "), ")"))
  }
  if (length(extra) > 0L) {
    defs <- c(defs, paste0("  ", extra))
  }
  paste0(
    "CREATE TABLE IF NOT EXISTS becmaster.", vpro_quote_ident(table), " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_staging_table_ddl <- function(table, spec, pk_cols = character(), fk_to_env = FALSE) {
  sub_col <- if (isTRUE(fk_to_env)) {
    "  submission_id UUID NOT NULL"
  } else {
    "  submission_id UUID NOT NULL REFERENCES staging.submissions(submission_id) ON DELETE CASCADE"
  }
  defs <- c(sub_col, vpro_pg_col_ddl(spec))
  if (length(pk_cols) > 0L) {
    defs <- c(
      defs,
      paste0("  PRIMARY KEY (submission_id, ", paste(vpro_quote_ident(pk_cols), collapse = ", "), ")")
    )
  }
  if (isTRUE(fk_to_env)) {
    plot_col <- if (identical(table, "admin")) "Plot" else "PlotNumber"
    defs <- c(
      defs,
      paste0(
        "  FOREIGN KEY (submission_id, ", vpro_quote_ident(plot_col),
        ') REFERENCES staging.env(submission_id, "PlotNumber") ON DELETE CASCADE'
      )
    )
  }
  paste0(
    "CREATE TABLE IF NOT EXISTS staging.", vpro_quote_ident(table), " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_standards_table_ddl <- function(table, spec) {
  defs <- c("  row_seq BIGSERIAL PRIMARY KEY", vpro_pg_col_ddl(spec))
  paste0(
    "CREATE TABLE IF NOT EXISTS standards.", vpro_quote_ident(table), " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_trigger_if_missing_ddl <- function(schema_name, table_name, trigger_name, fn_qualified) {
  paste0(
    "DO $$\nBEGIN\n",
    "  IF NOT EXISTS (\n",
    "    SELECT 1 FROM pg_trigger t\n",
    "    JOIN pg_class c ON c.oid = t.tgrelid\n",
    "    JOIN pg_namespace n ON n.oid = c.relnamespace\n",
    "    WHERE n.nspname = '", schema_name, "'\n",
    "      AND c.relname = '", table_name, "'\n",
    "      AND t.tgname = '", trigger_name, "'\n",
    "  ) THEN\n",
    "    CREATE TRIGGER ", vpro_quote_ident(trigger_name), "\n",
    "      BEFORE INSERT ON ", vpro_quote_ident(schema_name), ".", vpro_quote_ident(table_name), "\n",
    "      FOR EACH ROW EXECUTE FUNCTION ", fn_qualified, "();\n",
    "  END IF;\n",
    "END $$;"
  )
}

vpro_pg_build_v1_migration_stmts <- function(has_postgis = FALSE, postgis_schema = "public") {
  stmts <- c(
    vpro_pg_master_table_ddl("env", .vpro_pg_vp08_spec_map$Env, "PlotNumber"),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_zone ON becmaster.env ("Zone");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_subzone ON becmaster.env ("SubZone");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_projectid ON becmaster.env ("ProjectID");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_coords ON becmaster.env ("Longitude", "Latitude");'
  )

  if (isTRUE(has_postgis)) {
    q_pgis <- vpro_quote_ident(postgis_schema)
    stmts <- c(
      stmts,
      paste0(
        "ALTER TABLE becmaster.env ADD COLUMN IF NOT EXISTS geom ", q_pgis, ".geometry(Point, 4326) GENERATED ALWAYS AS (\n",
        "  CASE\n",
        '    WHEN "Longitude" IS NOT NULL AND "Latitude" IS NOT NULL\n',
        '         AND "Longitude" >= -180.0 AND "Longitude" <= 180.0\n',
        '         AND "Latitude" >= -90.0 AND "Latitude" <= 90.0\n',
        "    THEN ", q_pgis, ".ST_SetSRID(", q_pgis, '.ST_MakePoint("Longitude", "Latitude"), 4326)\n',
        "    ELSE NULL\n",
        "  END\n",
        ") STORED;"
      ),
      "CREATE INDEX IF NOT EXISTS idx_becmaster_env_geom ON becmaster.env USING GIST (geom);"
    )
  }

  audit_master_defs <- c(
    "  audit_seq BIGSERIAL PRIMARY KEY",
    vpro_pg_col_ddl(.vpro_pg_vp08_spec_map$Audit),
    "  merge_tx_id UUID",
    "  prev_hash TEXT NOT NULL",
    "  row_hash TEXT NOT NULL"
  )

  stmts <- c(
    stmts,
    vpro_pg_master_table_ddl(
      "admin",
      .vpro_pg_vp08_spec_map$Admin,
      "Plot",
      'FOREIGN KEY ("Plot") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "veg",
      .vpro_pg_vp08_spec_map$Veg,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_veg_species ON becmaster.veg ("Species");',
    vpro_pg_master_table_ddl(
      "humus",
      .vpro_pg_vp08_spec_map$Humus,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "mineral",
      .vpro_pg_vp08_spec_map$Mineral,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "other",
      .vpro_pg_vp08_spec_map$Other,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.child_identity (",
      "  child_table TEXT NOT NULL,",
      "  id BIGINT NOT NULL,",
      "  PRIMARY KEY (child_table, id)",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.child_identity_watermark (",
      "  child_table TEXT PRIMARY KEY,",
      "  max_id BIGINT NOT NULL",
      ");",
      sep = "\n"
    ),
    vpro_pg_master_table_ddl("metadata", .vpro_pg_vp08_spec_map$Metadata, "ProjectID"),
    paste0("CREATE TABLE IF NOT EXISTS becmaster.audit (\n", paste(audit_master_defs, collapse = ",\n"), "\n);"),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_audit_plot ON becmaster.audit ("PlotNumber");',
    "CREATE INDEX IF NOT EXISTS idx_becmaster_audit_mergetx ON becmaster.audit (merge_tx_id);",
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.merge_ledger (",
      "  merge_tx_id UUID PRIMARY KEY,",
      "  submission_id UUID,",
      "  actor TEXT NOT NULL,",
      "  merged_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  source_sha256 TEXT NOT NULL,",
      "  added_plots INT NOT NULL,",
      "  updated_plots INT NOT NULL,",
      "  summary_json JSONB NOT NULL",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.snapshots (",
      "  snapshot_tag TEXT PRIMARY KEY,",
      "  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  created_by TEXT NOT NULL,",
      "  plot_count INT NOT NULL,",
      "  veg_count BIGINT NOT NULL,",
      "  bec_version TEXT NOT NULL,",
      "  taxonomy_version TEXT NOT NULL,",
      "  manifest_sha256 TEXT NOT NULL,",
      "  notes TEXT",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.download_log (",
      "  id BIGSERIAL PRIMARY KEY,",
      "  downloaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  actor TEXT NOT NULL,",
      "  role_tier TEXT NOT NULL,",
      "  filter_json JSONB NOT NULL,",
      "  format TEXT NOT NULL,",
      "  plot_count INT NOT NULL",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE OR REPLACE FUNCTION becmaster.enforce_download_log_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "BEGIN",
      "  NEW.downloaded_at := COALESCE(NEW.downloaded_at, now());",
      "  IF NEW.actor IS NULL OR btrim(NEW.actor) = '' THEN",
      "    NEW.actor := current_user;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    ),
    vpro_pg_trigger_if_missing_ddl(
      "becmaster",
      "download_log",
      "trg_becmaster_download_log_insert",
      "becmaster.enforce_download_log_insert"
    )
  )

  stg_audit_defs <- c(
    "  audit_seq BIGSERIAL PRIMARY KEY",
    "  submission_id UUID NOT NULL REFERENCES staging.submissions(submission_id) ON DELETE CASCADE",
    vpro_pg_col_ddl(.vpro_pg_vp08_spec_map$Audit)
  )

  stmts <- c(
    stmts,
    paste(
      "CREATE TABLE IF NOT EXISTS staging.submissions (",
      "  submission_id UUID PRIMARY KEY,",
      "  project_name TEXT NOT NULL,",
      "  project_id TEXT,",
      "  submitted_by TEXT NOT NULL,",
      "  db_role TEXT NOT NULL,",
      "  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'merged')),",
      "  plot_count INT NOT NULL DEFAULT 0,",
      "  veg_row_count INT NOT NULL DEFAULT 0,",
      "  source_db_sha256 TEXT NOT NULL,",
      "  compliance_passed BOOLEAN NOT NULL,",
      "  compliance_report JSONB NOT NULL,",
      "  user_species_manifest JSONB NOT NULL,",
      "  lump_rows JSONB NOT NULL DEFAULT '[]'::jsonb,",
      "  su_rows JSONB NOT NULL DEFAULT '[]'::jsonb,",
      "  submitter_notes TEXT,",
      "  base_snapshot_tag TEXT,",
      "  reviewer_notes TEXT,",
      "  reviewed_by TEXT,",
      "  reviewed_at TIMESTAMPTZ,",
      "  merged_tx_id UUID",
      ");",
      sep = "\n"
    ),
    "CREATE INDEX IF NOT EXISTS idx_staging_submissions_status ON staging.submissions (status, submitted_at DESC);",
    vpro_pg_staging_table_ddl("env", .vpro_pg_vp08_spec_map$Env, "PlotNumber", fk_to_env = FALSE),
    vpro_pg_staging_table_ddl("admin", .vpro_pg_vp08_spec_map$Admin, "Plot", fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("veg", .vpro_pg_vp08_spec_map$Veg, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("humus", .vpro_pg_vp08_spec_map$Humus, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("mineral", .vpro_pg_vp08_spec_map$Mineral, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("other", .vpro_pg_vp08_spec_map$Other, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("metadata", .vpro_pg_vp08_spec_map$Metadata, "ProjectID", fk_to_env = FALSE),
    paste0("CREATE TABLE IF NOT EXISTS staging.audit (\n", paste(stg_audit_defs, collapse = ",\n"), "\n);"),
    "CREATE INDEX IF NOT EXISTS idx_staging_audit_sub ON staging.audit (submission_id);",
    paste(
      "CREATE OR REPLACE FUNCTION staging.enforce_submission_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "DECLARE",
      "  is_table_owner BOOLEAN;",
      "BEGIN",
      "  NEW.db_role := current_user;",
      "  NEW.submitted_at := COALESCE(NEW.submitted_at, now());",
      "  SELECT pg_has_role(current_user, c.relowner, 'USAGE')",
      "  INTO is_table_owner",
      "  FROM pg_class c",
      "  JOIN pg_namespace n ON n.oid = c.relnamespace",
      "  WHERE n.nspname = 'staging' AND c.relname = 'submissions';",
      "",
      "  IF NOT COALESCE(is_table_owner, FALSE) THEN",
      "    IF NEW.status <> 'pending' THEN",
      "      RAISE EXCEPTION 'contributor submissions must start with status = pending' USING ERRCODE = '42501';",
      "    END IF;",
      "    IF NEW.compliance_passed IS NOT TRUE THEN",
      "      RAISE EXCEPTION 'contributor submissions require compliance_passed = TRUE' USING ERRCODE = '42501';",
      "    END IF;",
      "    NEW.reviewed_by := NULL;",
      "    NEW.reviewed_at := NULL;",
      "    NEW.merged_tx_id := NULL;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    ),
    vpro_pg_trigger_if_missing_ddl(
      "staging",
      "submissions",
      "trg_staging_submission_insert",
      "staging.enforce_submission_insert"
    ),
    paste(
      "CREATE OR REPLACE FUNCTION staging.enforce_staging_child_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "DECLARE",
      "  is_table_owner BOOLEAN;",
      "  sub_ok BOOLEAN;",
      "BEGIN",
      "  SELECT pg_has_role(current_user, c.relowner, 'USAGE')",
      "  INTO is_table_owner",
      "  FROM pg_class c",
      "  JOIN pg_namespace n ON n.oid = c.relnamespace",
      "  WHERE n.nspname = 'staging' AND c.relname = 'submissions';",
      "",
      "  IF NOT COALESCE(is_table_owner, FALSE) THEN",
      "    SELECT EXISTS (",
      "      SELECT 1 FROM staging.submissions s",
      "      WHERE s.submission_id = NEW.submission_id",
      "        AND s.status = 'pending'",
      "        AND s.db_role = current_user",
      "    ) INTO sub_ok;",
      "    IF NOT COALESCE(sub_ok, FALSE) THEN",
      "      RAISE EXCEPTION 'contributor child row insert requires owned pending submission_id' USING ERRCODE = '42501';",
      "    END IF;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    )
  )

  for (child_tbl in c("env", "admin", "veg", "humus", "mineral", "other", "metadata", "audit")) {
    stmts <- c(
      stmts,
      vpro_pg_trigger_if_missing_ddl(
        "staging",
        child_tbl,
        paste0("trg_staging_", child_tbl, "_insert"),
        "staging.enforce_staging_child_insert"
      )
    )
  }

  stmts <- c(
    stmts,
    paste(
      "CREATE TABLE IF NOT EXISTS standards.library_releases (",
      "  release_id TEXT PRIMARY KEY,",
      "  published_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  published_by TEXT NOT NULL,",
      "  bec_version TEXT NOT NULL,",
      "  taxonomy_version TEXT NOT NULL,",
      "  vlists_sha256 TEXT NOT NULL,",
      "  bec_db_sha256 TEXT,",
      "  vmetadata_sha256 TEXT,",
      "  notes TEXT,",
      "  is_current BOOLEAN NOT NULL DEFAULT FALSE,",
      "  vlists_gzip BYTEA",
      ");",
      sep = "\n"
    ),
    vpro_pg_standards_table_ddl("usys_all_specs", .vpro_pg_standards_spec_map$usys_all_specs),
    'CREATE INDEX IF NOT EXISTS idx_standards_specs_code ON standards.usys_all_specs ("Code");',
    'CREATE INDEX IF NOT EXISTS idx_standards_specs_oldcode ON standards.usys_all_specs ("OldCode");',
    vpro_pg_standards_table_ddl("usys_table_of_lists", .vpro_pg_standards_spec_map$usys_table_of_lists),
    'CREATE INDEX IF NOT EXISTS idx_standards_lists_name ON standards.usys_table_of_lists ("ListName");',
    vpro_pg_standards_table_ddl("bec_site_series", .vpro_pg_standards_spec_map$bec_site_series),
    'CREATE INDEX IF NOT EXISTS idx_standards_bec_zone ON standards.bec_site_series ("Zone", "SubZone");',
    vpro_pg_standards_table_ddl("master_site_unit_list", .vpro_pg_standards_spec_map$master_site_unit_list),
    vpro_pg_standards_table_ddl("usys_zone_list", .vpro_pg_standards_spec_map$usys_zone_list),
    vpro_pg_standards_table_ddl("project_metadata", .vpro_pg_standards_spec_map$project_metadata)
  )

  stmts
}

# Public Exported API ----------------------------------------------------------

#' Check offline availability of PostgreSQL `BECMaster` credentials
#'
#' Performs a 100% offline inspection of process environment variables
#' (`VPRO_PG_*`) and `file.path(config_dir, "becmaster.env")` without opening
#' network sockets or requiring `RPostgres` to be installed. Never throws on
#' missing or malformed configuration files.
#'
#' @param role Target PostgreSQL role tier (`"contributor"` or `"custodian"`).
#' @param config_dir Directory containing `becmaster.env` (defaults to
#'   [vpro_config_dir()]).
#' @return `TRUE` when a connection URL or (`host` and `user`) are configured
#'   for `role`, otherwise `FALSE`.
#' @export
vpro_has_pg_credentials <- function(
  role = c("contributor", "custodian"),
  config_dir = vpro_config_dir()
) {
  role <- match.arg(role)
  creds <- tryCatch(
    vpro_resolve_pg_credentials(role = role, config_dir = config_dir),
    error = function(e) NULL
  )
  if (is.null(creds)) {
    return(FALSE)
  }
  isTRUE(nzchar(creds$url) || (nzchar(creds$host) && nzchar(creds$user)))
}

#' Connect to the PostgreSQL `BECMaster` cloud service
#'
#' Opens a secret-redacted `RPostgres` connection to the provincial `BECMaster`
#' PostgreSQL database (`becmaster`, `staging`, and `standards` schemas) using
#' the exact credential precedence shared with `vpro_wails`:
#' 1. Explicit function arguments (`source = "args"`).
#' 2. Process environment variables (`VPRO_PG_HOST`, `VPRO_PG_PORT`,
#'    `VPRO_PG_DBNAME`, `VPRO_PG_SSLMODE`, plus `VPRO_PG_USER` /
#'    `VPRO_PG_PASSWORD` / `VPRO_PG_URL` for `"contributor"`, or
#'    `VPRO_PG_ADMIN_USER` / `VPRO_PG_ADMIN_PASSWORD` / `VPRO_PG_ADMIN_URL` for
#'    `"custodian"`, `source = "env"`).
#' 3. Fallback `file.path(config_dir, "becmaster.env")` (`source = "becmaster.env"`).
#'
#' Passwords and connection URLs are never stored on the returned
#' `vpro_pg_conn` handle and are scrubbed from any connection errors.
#'
#' @param role Connection role tier: `"contributor"` (read `becmaster.*` /
#'   `standards.*` and append to `staging.*`) or `"custodian"` (full schema
#'   bootstrap, staging review, and 3-way master merge privileges).
#' @param host Optional PostgreSQL hostname override.
#' @param port Optional TCP port override (`1..65535`; default `5432L`).
#' @param dbname Optional database name override (default `"becmaster"`).
#' @param user Optional PostgreSQL role/username override.
#' @param password Optional password override (never retained on the handle).
#' @param sslmode Optional TLS mode (`"disable"`, `"allow"`, `"prefer"`,
#'   `"require"`, `"verify-ca"`, or `"verify-full"`; default `"require"`).
#' @param url Optional `postgres://` or `postgresql://` connection URI.
#' @param config_dir Directory inspected for `becmaster.env` (defaults to
#'   [vpro_config_dir()]).
#' @param bootstrap If `TRUE` (requires `role = "custodian"`), runs idempotent
#'   [vpro_master_bootstrap()] immediately after connecting and refreshes
#'   `status`.
#' @return An S3 object of class `vpro_pg_conn`.
#' @export
vpro_master_connect <- function(
  role = c("contributor", "custodian"),
  host = NULL,
  port = NULL,
  dbname = NULL,
  user = NULL,
  password = NULL,
  sslmode = NULL,
  url = NULL,
  config_dir = vpro_config_dir(),
  bootstrap = FALSE
) {
  role <- match.arg(role)
  if (!is.logical(bootstrap) || length(bootstrap) != 1L || is.na(bootstrap)) {
    cli::cli_abort("{.arg bootstrap} must be {.code TRUE} or {.code FALSE}.")
  }
  if (isTRUE(bootstrap) && !identical(role, "custodian")) {
    cli::cli_abort("{.arg bootstrap = TRUE} requires {.code role = \"custodian\"}.")
  }

  rlang::check_installed("RPostgres", reason = "to connect to the PostgreSQL BECMaster service.")
  .vpro_register_pg_s3()

  creds <- vpro_resolve_pg_credentials(
    role = role,
    host = host,
    port = port,
    dbname = dbname,
    user = user,
    password = password,
    sslmode = sslmode,
    url = url,
    config_dir = config_dir
  )

  if (!nzchar(creds$host) || !nzchar(creds$user)) {
    if (identical(role, "custodian")) {
      cli::cli_abort(c(
        "PostgreSQL custodian credentials are not configured.",
        "i" = "Set {.envvar VPRO_PG_HOST}, {.envvar VPRO_PG_ADMIN_USER}, and {.envvar VPRO_PG_ADMIN_PASSWORD} (or {.envvar VPRO_PG_ADMIN_URL}), or configure {.file becmaster.env} in {.fn vpro_config_dir}."
      ))
    }
    cli::cli_abort(c(
      "PostgreSQL contributor credentials are not configured.",
      "i" = "Set {.envvar VPRO_PG_HOST}, {.envvar VPRO_PG_USER}, and {.envvar VPRO_PG_PASSWORD} (or {.envvar VPRO_PG_URL}), or configure {.file becmaster.env} in {.fn vpro_config_dir}."
    ))
  }

  raw_conn <- vpro_pg_exec_safe(
    function() {
      DBI::dbConnect(
        RPostgres::Postgres(),
        host = creds$host,
        port = as.integer(creds$port),
        dbname = creds$dbname,
        user = creds$user,
        password = creds$password,
        sslmode = creds$sslmode,
        bigint = "integer",
        connect_timeout = 15L
      )
    },
    secrets = c(creds$password, creds$url),
    action = "PostgreSQL connection"
  )

  ok <- FALSE
  on.exit(
    if (!ok && isTRUE(tryCatch(DBI::dbIsValid(raw_conn), error = function(e) FALSE))) {
      tryCatch(DBI::dbDisconnect(raw_conn), error = function(e) NULL)
    },
    add = TRUE
  )

  con_obj <- structure(
    list(
      conn = raw_conn,
      role = creds$role,
      host = creds$host,
      port = as.integer(creds$port),
      dbname = creds$dbname,
      user = creds$user,
      sslmode = creds$sslmode,
      config_source = creds$source,
      connected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      status = NULL
    ),
    class = "vpro_pg_conn"
  )

  if (isTRUE(bootstrap)) {
    vpro_master_bootstrap(con_obj)
  }
  con_obj$status <- vpro_master_status(con_obj)

  ok <- TRUE
  con_obj
}

#' Disconnect a PostgreSQL `BECMaster` connection
#'
#' Cleanly closes the underlying `PqConnection` when valid. Safe to call inside
#' `on.exit()` even if the connection has already been closed.
#'
#' @param con A `vpro_pg_conn` connection object (or `NULL`).
#' @return `invisible(TRUE)` when an active connection was closed, or
#'   `invisible(FALSE)` when `con` was already disconnected.
#' @export
vpro_master_disconnect <- function(con) {
  if (is.null(con)) {
    return(invisible(FALSE))
  }
  if (!inherits(con, "vpro_pg_conn") || !is.list(con) || is.null(con$conn)) {
    cli::cli_abort(
      "{.arg con} must be a {.cls vpro_pg_conn} connection created by {.fn vpro_master_connect}."
    )
  }
  valid <- tryCatch(DBI::dbIsValid(con$conn), error = function(e) FALSE)
  if (!isTRUE(valid)) {
    return(invisible(FALSE))
  }
  tryCatch(DBI::dbDisconnect(con$conn), error = function(e) NULL)
  invisible(TRUE)
}

#' Inspect PostgreSQL `BECMaster` server health, RBAC privileges, and counts
#'
#' Probes round-trip latency, PostgreSQL and PostGIS versions, `becmaster` /
#' `staging` / `standards` schema bootstrap status, table-level RBAC
#' capabilities, master plot and vegetation row counts, snapshot tags, active
#' 2026 standards release metadata, and pending contributor submissions.
#'
#' @param con An active `vpro_pg_conn` connection object.
#' @return An S3 object of class `vpro_pg_status` with `print()` and
#'   `as_tibble()` methods.
#' @export
vpro_master_status <- function(con) {
  vpro_assert_pg_conn(con)
  .vpro_register_pg_s3()

  t0 <- proc.time()[["elapsed"]]
  ver_df <- vpro_pg_query(con, "SHOW server_version", action = "Probe PostgreSQL version")
  elapsed_ms <- max(1L, as.integer(round((proc.time()[["elapsed"]] - t0) * 1000)))
  server_version <- if (nrow(ver_df) >= 1L && ncol(ver_df) >= 1L) {
    trimws(as.character(ver_df[[1L]][[1L]]))
  } else {
    NA_character_
  }

  ext_df <- tryCatch(
    vpro_pg_query(
      con,
      "SELECT extversion FROM pg_extension WHERE extname = 'postgis' LIMIT 1",
      action = "Inspect PostGIS extension"
    ),
    error = function(e) data.frame()
  )
  postgis_version <- if (nrow(ext_df) >= 1L && !is.na(ext_df[[1L]][[1L]]) && nzchar(ext_df[[1L]][[1L]])) {
    as.character(ext_df[[1L]][[1L]])
  } else {
    NA_character_
  }

  can_bootstrap_schema <- tryCatch({
    b_df <- vpro_pg_query(
      con,
      "SELECT has_database_privilege(current_user, current_database(), 'CREATE') AS ok",
      action = "Check database CREATE privilege"
    )
    nrow(b_df) >= 1L && isTRUE(as.logical(b_df$ok[[1L]]))
  }, error = function(e) FALSE)

  sch_df <- vpro_pg_query(
    con,
    "SELECT COUNT(*) AS n FROM information_schema.schemata WHERE schema_name IN ('becmaster', 'staging', 'standards')",
    action = "Inspect VPro PostgreSQL schemas"
  )
  schema_count <- if (nrow(sch_df) >= 1L) as.integer(sch_df$n[[1L]]) else 0L

  has_env_table <- FALSE
  if (schema_count == 3L) {
    env_tbl_df <- tryCatch(
      vpro_pg_query(
        con,
        paste(
          "SELECT EXISTS (",
          "  SELECT 1 FROM pg_class c",
          "  JOIN pg_namespace n ON n.oid = c.relnamespace",
          "  WHERE n.nspname = 'becmaster' AND c.relname = 'env'",
          ") AS ok"
        ),
        action = "Check becmaster.env existence"
      ),
      error = function(e) data.frame(ok = FALSE)
    )
    has_env_table <- nrow(env_tbl_df) >= 1L && isTRUE(as.logical(env_tbl_df$ok[[1L]]))
  }
  schemas_bootstrapped <- (schema_count == 3L) && has_env_table

  can_read_master <- FALSE
  can_submit_staging <- FALSE
  can_merge_master <- FALSE
  can_read_staging <- FALSE

  if (schemas_bootstrapped) {
    priv_sql <- paste(
      "SELECT",
      "  CASE WHEN has_schema_privilege(current_user, 'becmaster', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'becmaster' AND c.relname = 'env')",
      "       THEN has_table_privilege(current_user, 'becmaster.env', 'SELECT')",
      "       ELSE FALSE END AS can_read_master,",
      "  CASE WHEN has_schema_privilege(current_user, 'staging', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'staging' AND c.relname = 'submissions')",
      "       THEN has_table_privilege(current_user, 'staging.submissions', 'INSERT')",
      "       ELSE FALSE END AS can_submit_staging,",
      "  CASE WHEN has_schema_privilege(current_user, 'becmaster', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'becmaster' AND c.relname = 'env')",
      "       THEN (has_table_privilege(current_user, 'becmaster.env', 'INSERT') AND has_table_privilege(current_user, 'becmaster.env', 'UPDATE'))",
      "       ELSE FALSE END AS can_merge_master,",
      "  CASE WHEN has_schema_privilege(current_user, 'staging', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'staging' AND c.relname = 'submissions')",
      "       THEN has_table_privilege(current_user, 'staging.submissions', 'SELECT')",
      "       ELSE FALSE END AS can_read_staging"
    )
    priv_df <- tryCatch(
      vpro_pg_query(con, priv_sql, action = "Check PostgreSQL table privileges"),
      error = function(e) data.frame()
    )
    if (nrow(priv_df) >= 1L) {
      can_read_master <- isTRUE(as.logical(priv_df$can_read_master[[1L]]))
      can_submit_staging <- isTRUE(as.logical(priv_df$can_submit_staging[[1L]]))
      can_merge_master <- isTRUE(as.logical(priv_df$can_merge_master[[1L]]))
      can_read_staging <- isTRUE(as.logical(priv_df$can_read_staging[[1L]]))
    }
    if (can_merge_master) {
      can_bootstrap_schema <- TRUE
    }
  }

  becmaster_plots <- 0L
  becmaster_veg <- 0L
  snapshot_count <- 0L
  latest_snapshot_tag <- NA_character_
  standards_release <- NA_character_
  bec_version <- NA_character_
  taxonomy_version <- NA_character_
  vlists_sha256 <- NA_character_
  pending_submissions <- 0L

  if (schemas_bootstrapped && can_read_master) {
    becmaster_plots <- tryCatch({
      d <- vpro_pg_query(con, "SELECT COUNT(*) AS n FROM becmaster.env")
      if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
    }, error = function(e) 0L)

    becmaster_veg <- tryCatch({
      d <- vpro_pg_query(con, "SELECT COUNT(*) AS n FROM becmaster.veg")
      if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
    }, error = function(e) 0L)

    snapshot_count <- tryCatch({
      d <- vpro_pg_query(con, "SELECT COUNT(*) AS n FROM becmaster.snapshots")
      if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
    }, error = function(e) 0L)

    latest_snapshot_tag <- tryCatch({
      d <- vpro_pg_query(
        con,
        "SELECT snapshot_tag FROM becmaster.snapshots ORDER BY created_at DESC LIMIT 1"
      )
      if (nrow(d) >= 1L && !is.na(d$snapshot_tag[[1L]]) && nzchar(d$snapshot_tag[[1L]])) {
        as.character(d$snapshot_tag[[1L]])
      } else {
        NA_character_
      }
    }, error = function(e) NA_character_)

    rel_df <- tryCatch(
      vpro_pg_query(
        con,
        paste(
          "SELECT release_id, bec_version, taxonomy_version, vlists_sha256",
          "FROM standards.library_releases",
          "WHERE is_current = TRUE",
          "ORDER BY published_at DESC",
          "LIMIT 1"
        )
      ),
      error = function(e) data.frame()
    )
    if (nrow(rel_df) >= 1L) {
      standards_release <- as.character(rel_df$release_id[[1L]])
      bec_version <- as.character(rel_df$bec_version[[1L]])
      taxonomy_version <- as.character(rel_df$taxonomy_version[[1L]])
      vlists_sha256 <- as.character(rel_df$vlists_sha256[[1L]])
    }
  }

  if (schemas_bootstrapped && can_read_staging) {
    pending_submissions <- tryCatch({
      d <- vpro_pg_query(
        con,
        "SELECT COUNT(*) AS n FROM staging.submissions WHERE status = 'pending'"
      )
      if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
    }, error = function(e) 0L)
  }

  structure(
    list(
      connected = TRUE,
      role = as.character(con$role),
      config_source = as.character(con$config_source),
      dbname = as.character(con$dbname),
      sslmode = as.character(con$sslmode),
      latency_ms = elapsed_ms,
      server_version = server_version,
      postgis_version = postgis_version,
      schemas_bootstrapped = schemas_bootstrapped,
      can_read_master = can_read_master,
      can_submit_staging = can_submit_staging,
      can_merge_master = can_merge_master,
      can_bootstrap_schema = can_bootstrap_schema,
      becmaster_plots = becmaster_plots,
      becmaster_veg = becmaster_veg,
      pending_submissions = pending_submissions,
      snapshot_count = snapshot_count,
      latest_snapshot_tag = latest_snapshot_tag,
      standards_release = standards_release,
      bec_version = bec_version,
      taxonomy_version = taxonomy_version,
      vlists_sha256 = vlists_sha256,
      checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    class = "vpro_pg_status"
  )
}

#' @export
print.vpro_pg_status <- function(x, ...) {
  pgis_lbl <- if (!is.na(x$postgis_version) && nzchar(x$postgis_version)) {
    paste0("PostGIS ", x$postgis_version)
  } else {
    "PostGIS absent"
  }
  std_lbl <- if (!is.na(x$standards_release) && nzchar(x$standards_release)) {
    paste0(x$standards_release, " (BEC ", x$bec_version, ", Taxonomy ", x$taxonomy_version, ")")
  } else {
    "<none>"
  }
  snap_lbl <- if (!is.na(x$latest_snapshot_tag) && nzchar(x$latest_snapshot_tag)) {
    paste0(x$snapshot_count, " (latest: ", x$latest_snapshot_tag, ")")
  } else {
    as.character(x$snapshot_count)
  }

  cli::cli_h3("vpro_pg_status ({x$role} on {.val {x$dbname}}, TLS {.val {x$sslmode}})")
  cli::cli_bullets(c(
    "*" = "Server: PostgreSQL {x$server_version} ({pgis_lbl}, {x$latency_ms} ms)",
    "*" = "Capabilities: bootstrapped={x$schemas_bootstrapped}, read={x$can_read_master}, stage={x$can_submit_staging}, merge={x$can_merge_master}",
    "*" = "BECMaster: {x$becmaster_plots} plots, {x$becmaster_veg} veg rows | Snapshots: {snap_lbl}",
    "*" = "Standards: {std_lbl} | Pending staging: {x$pending_submissions}"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_pg_status <- function(x, ...) {
  tibble::tibble(
    connected = as.logical(x$connected),
    role = as.character(x$role),
    config_source = as.character(x$config_source),
    dbname = as.character(x$dbname),
    sslmode = as.character(x$sslmode),
    latency_ms = as.integer(x$latency_ms),
    server_version = as.character(x$server_version),
    postgis_version = as.character(x$postgis_version),
    schemas_bootstrapped = as.logical(x$schemas_bootstrapped),
    can_read_master = as.logical(x$can_read_master),
    can_submit_staging = as.logical(x$can_submit_staging),
    can_merge_master = as.logical(x$can_merge_master),
    can_bootstrap_schema = as.logical(x$can_bootstrap_schema),
    becmaster_plots = as.integer(x$becmaster_plots),
    becmaster_veg = as.integer(x$becmaster_veg),
    pending_submissions = as.integer(x$pending_submissions),
    snapshot_count = as.integer(x$snapshot_count),
    latest_snapshot_tag = as.character(x$latest_snapshot_tag),
    standards_release = as.character(x$standards_release),
    bec_version = as.character(x$bec_version),
    taxonomy_version = as.character(x$taxonomy_version),
    vlists_sha256 = as.character(x$vlists_sha256),
    checked_at = as.character(x$checked_at)
  )
}

#' Bootstrap `becmaster`, `staging`, and `standards` PostgreSQL schemas
#'
#' Non-destructively inspects `information_schema.schemata` and
#' `information_schema.tables`, then executes idempotent `CREATE SCHEMA IF NOT
#' EXISTS`, `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, trigger,
#' PostGIS `geom` column (when `postgis` is installed), and optional least-privilege
#' role grants / RLS policies matching `vpro_wails/internal/cloudsync/schema.go`.
#' Never modifies `public` or drops existing data.
#'
#' @param con A custodian `vpro_pg_conn` connection (`role == "custodian"`).
#' @param contributor_role Optional PostgreSQL role name to receive contributor
#'   `SELECT` / `staging` `INSERT` grants and RLS policies when present in
#'   `pg_roles`.
#' @param custodian_role Optional PostgreSQL role name to receive explicit
#'   custodian `ALL PRIVILEGES` grants on the three VPro schemas when present
#'   in `pg_roles`.
#' @return A list summarizing pre-existing and newly created schemas/tables,
#'   applied migrations, extension flags, and role grant status.
#' @export
vpro_master_bootstrap <- function(con, contributor_role = NULL, custodian_role = NULL) {
  vpro_assert_pg_conn(con, require_custodian = TRUE)

  norm_role <- function(r, arg_nm) {
    if (is.null(r)) return("")
    if (!is.character(r) || length(r) != 1L || is.na(r)) {
      cli::cli_abort("{.arg {arg_nm}} must be {.code NULL} or a single character string.")
    }
    trimws(r)
  }
  contrib_r <- norm_role(contributor_role, "contributor_role")
  custod_r <- norm_role(custodian_role, "custodian_role")
  if (nzchar(contrib_r) && nzchar(custod_r) && identical(contrib_r, custod_r)) {
    cli::cli_abort(
      "{.arg contributor_role} and {.arg custodian_role} must be distinct PostgreSQL roles."
    )
  }

  target_schemas <- c("becmaster", "staging", "standards")

  existing_sch_df <- vpro_pg_query(
    con,
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('becmaster', 'staging', 'standards')",
    action = "Inspect existing PostgreSQL schemas"
  )
  existing_schemas <- if (nrow(existing_sch_df) > 0L) {
    as.character(existing_sch_df$schema_name)
  } else {
    character(0L)
  }

  existing_tbl_df <- vpro_pg_query(
    con,
    paste(
      "SELECT table_schema, table_name FROM information_schema.tables",
      "WHERE table_schema IN ('becmaster', 'staging', 'standards') AND table_type = 'BASE TABLE'",
      "ORDER BY table_schema, table_name"
    ),
    action = "Inspect existing PostgreSQL tables"
  )
  existing_tables <- if (nrow(existing_tbl_df) > 0L) {
    paste0(existing_tbl_df$table_schema, ".", existing_tbl_df$table_name)
  } else {
    character(0L)
  }

  created_schemas <- character(0L)
  for (s_name in target_schemas) {
    if (s_name %in% existing_schemas) {
      priv <- vpro_pg_query(
        con,
        "SELECT has_schema_privilege(current_user, $1, 'CREATE') AS ok",
        params = list(s_name),
        action = "Check schema CREATE privilege"
      )
      if (nrow(priv) == 0L || !isTRUE(as.logical(priv$ok[[1L]]))) {
        cli::cli_abort(
          "Custodian role lacks CREATE privilege on existing PostgreSQL schema {.val {s_name}}."
        )
      }
    } else {
      db_priv <- vpro_pg_query(
        con,
        "SELECT has_database_privilege(current_user, current_database(), 'CREATE') AS ok",
        action = "Check database CREATE privilege"
      )
      if (nrow(db_priv) == 0L || !isTRUE(as.logical(db_priv$ok[[1L]]))) {
        cli::cli_abort(c(
          "Custodian role lacks CREATE privilege on database to initialize schema {.val {s_name}}.",
          "i" = "Ask a PostgreSQL DBA/superuser to run GRANT CREATE ON DATABASE <db> TO <custodian_role>."
        ))
      }
      vpro_pg_execute(
        con,
        paste0("CREATE SCHEMA IF NOT EXISTS ", vpro_quote_ident(s_name)),
        action = paste0("Create schema ", s_name)
      )
      created_schemas <- c(created_schemas, s_name)
    }
  }

  ext_df <- vpro_pg_query(
    con,
    paste(
      "SELECT e.extname, n.nspname AS schema_name",
      "FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace",
      "WHERE e.extname IN ('postgis', 'pgcrypto')"
    ),
    action = "Inspect PostgreSQL extensions"
  )
  has_postgis <- nrow(ext_df) > 0L && ("postgis" %in% ext_df$extname)
  has_pgcrypto <- nrow(ext_df) > 0L && ("pgcrypto" %in% ext_df$extname)
  postgis_schema <- if (has_postgis) {
    as.character(ext_df$schema_name[ext_df$extname == "postgis"][[1L]])
  } else {
    "public"
  }

  vpro_pg_execute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.schema_migrations (",
      "  version INT PRIMARY KEY,",
      "  name TEXT NOT NULL,",
      "  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()",
      ");",
      sep = "\n"
    ),
    action = "Ensure becmaster.schema_migrations"
  )

  mig_df <- vpro_pg_query(
    con,
    "SELECT EXISTS (SELECT 1 FROM becmaster.schema_migrations WHERE version = 1) AS ok",
    action = "Check schema_migrations version 1"
  )
  v1_already_applied <- nrow(mig_df) >= 1L && isTRUE(as.logical(mig_df$ok[[1L]]))

  stmts <- vpro_pg_build_v1_migration_stmts(
    has_postgis = has_postgis,
    postgis_schema = postgis_schema
  )

  applied_migrations <- character(0L)
  vpro_pg_exec_safe(
    function() {
      DBI::dbWithTransaction(con$conn, {
        for (stmt in stmts) {
          DBI::dbExecute(con$conn, stmt)
        }
        if (!v1_already_applied) {
          DBI::dbExecute(
            con$conn,
            "INSERT INTO becmaster.schema_migrations (version, name) VALUES (1, 'v1_becmaster_staging_standards') ON CONFLICT (version) DO NOTHING"
          )
          applied_migrations <<- "1:v1_becmaster_staging_standards"
        }
      })
    },
    action = "Bootstrap PostgreSQL BECMaster schemas"
  )

  role_exists <- function(r_name) {
    if (!nzchar(r_name)) return(FALSE)
    d <- vpro_pg_query(
      con,
      "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1) AS ok",
      params = list(r_name),
      action = "Check PostgreSQL pg_roles"
    )
    nrow(d) >= 1L && isTRUE(as.logical(d$ok[[1L]]))
  }

  has_contrib_role <- role_exists(contrib_r)
  has_custod_role <- role_exists(custod_r)
  role_grants_applied <- FALSE
  contributor_role_set <- FALSE

  if (has_contrib_role || has_custod_role) {
    grant_stmts <- character(0L)
    for (sch in target_schemas) {
      q_sch <- vpro_quote_ident(sch)
      grant_stmts <- c(
        grant_stmts,
        paste0("REVOKE ALL ON SCHEMA ", q_sch, " FROM PUBLIC"),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA ", q_sch, " FROM PUBLIC"),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA ", q_sch, " FROM PUBLIC")
      )
    }

    if (has_custod_role) {
      q_admin <- vpro_quote_ident(custod_r)
      for (sch in target_schemas) {
        q_sch <- vpro_quote_ident(sch)
        grant_stmts <- c(
          grant_stmts,
          paste0("GRANT ALL PRIVILEGES ON SCHEMA ", q_sch, " TO ", q_admin),
          paste0("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ", q_sch, " TO ", q_admin),
          paste0("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ", q_sch, " TO ", q_admin)
        )
      }
    }

    if (has_contrib_role) {
      q_user <- vpro_quote_ident(contrib_r)
      grant_stmts <- c(
        grant_stmts,
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA becmaster FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA becmaster FROM ", q_user),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA staging FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA staging FROM ", q_user),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA standards FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA standards FROM ", q_user),
        paste0("GRANT USAGE ON SCHEMA becmaster, staging, standards TO ", q_user),
        paste0("GRANT SELECT ON ALL TABLES IN SCHEMA becmaster TO ", q_user),
        paste0("GRANT SELECT ON ALL TABLES IN SCHEMA standards TO ", q_user),
        paste0("GRANT INSERT ON TABLE becmaster.download_log TO ", q_user),
        paste0("GRANT USAGE, SELECT ON SEQUENCE becmaster.download_log_id_seq TO ", q_user),
        paste0("GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA staging TO ", q_user),
        paste0("GRANT USAGE, SELECT ON SEQUENCE staging.audit_audit_seq_seq TO ", q_user),
        "ALTER TABLE staging.submissions ENABLE ROW LEVEL SECURITY",
        "DROP POLICY IF EXISTS submissions_contributor_select ON staging.submissions",
        paste0("CREATE POLICY submissions_contributor_select ON staging.submissions FOR SELECT TO ", q_user, " USING (true)"),
        "DROP POLICY IF EXISTS submissions_contributor_insert ON staging.submissions",
        paste0(
          "CREATE POLICY submissions_contributor_insert ON staging.submissions FOR INSERT TO ", q_user,
          " WITH CHECK (status = 'pending' AND compliance_passed = TRUE AND db_role = current_user AND reviewed_by IS NULL AND merged_tx_id IS NULL)"
        )
      )
      for (stg_tbl in c("env", "admin", "veg", "humus", "mineral", "other", "metadata", "audit")) {
        q_tbl <- vpro_quote_ident(stg_tbl)
        grant_stmts <- c(
          grant_stmts,
          paste0("DROP POLICY IF EXISTS ", vpro_quote_ident(paste0(stg_tbl, "_contributor_select")), " ON staging.", q_tbl),
          paste0("DROP POLICY IF EXISTS ", vpro_quote_ident(paste0(stg_tbl, "_contributor_insert")), " ON staging.", q_tbl),
          paste0("ALTER TABLE staging.", q_tbl, " DISABLE ROW LEVEL SECURITY")
        )
      }
    }

    vpro_pg_exec_safe(
      function() {
        DBI::dbWithTransaction(con$conn, {
          for (g_stmt in grant_stmts) {
            DBI::dbExecute(con$conn, g_stmt)
          }
        })
      },
      action = "Apply PostgreSQL role grants and RLS policies"
    )
    role_grants_applied <- TRUE
    contributor_role_set <- has_contrib_role
  }

  after_tbl_df <- vpro_pg_query(
    con,
    paste(
      "SELECT table_schema, table_name FROM information_schema.tables",
      "WHERE table_schema IN ('becmaster', 'staging', 'standards') AND table_type = 'BASE TABLE'",
      "ORDER BY table_schema, table_name"
    ),
    action = "Verify bootstrapped PostgreSQL tables"
  )
  all_tables <- if (nrow(after_tbl_df) > 0L) {
    paste0(after_tbl_df$table_schema, ".", after_tbl_df$table_name)
  } else {
    character(0L)
  }
  created_tables <- setdiff(all_tables, existing_tables)

  list(
    schema_version = 1L,
    schemas_verified = target_schemas,
    existing_schemas = existing_schemas,
    created_schemas = created_schemas,
    existing_tables = existing_tables,
    created_tables = created_tables,
    applied_migrations = applied_migrations,
    postgis_enabled = has_postgis,
    pgcrypto_enabled = has_pgcrypto,
    role_grants_applied = role_grants_applied,
    contributor_role_set = contributor_role_set,
    bootstrapped_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

#' @export
print.vpro_pg_conn <- function(x, ...) {
  valid <- !is.null(x$conn) && isTRUE(tryCatch(DBI::dbIsValid(x$conn), error = function(e) FALSE))
  state_lbl <- if (valid) "valid" else "disconnected"

  safe_host <- vpro_redact_pg_secrets(as.character(x$host))
  safe_db <- vpro_redact_pg_secrets(as.character(x$dbname))
  safe_user <- vpro_redact_pg_secrets(as.character(x$user))
  safe_role <- vpro_redact_pg_secrets(as.character(x$role))
  safe_ssl <- vpro_redact_pg_secrets(as.character(x$sslmode))
  safe_port <- as.integer(x$port)

  st <- x$status
  if (is.null(st) && valid) {
    st <- tryCatch(vpro_master_status(x), error = function(e) NULL)
  }

  plots_lbl <- if (is.list(st) && !is.null(st$becmaster_plots)) as.character(st$becmaster_plots) else "0"
  veg_lbl <- if (is.list(st) && !is.null(st$becmaster_veg)) as.character(st$becmaster_veg) else "0"
  pending_lbl <- if (is.list(st) && !is.null(st$pending_submissions)) as.character(st$pending_submissions) else "0"

  std_lbl <- if (is.list(st) && !is.null(st$standards_release) && !is.na(st$standards_release) && nzchar(st$standards_release)) {
    paste0(st$standards_release, " (BEC ", st$bec_version, " / Taxonomy ", st$taxonomy_version, ")")
  } else {
    "<none>"
  }

  cli::cli_h3("vpro_pg_conn [{state_lbl}] ({safe_role})")
  cli::cli_bullets(c(
    "*" = "Endpoint: {safe_host}:{safe_port}/{safe_db} (user: {.val {safe_user}}, TLS sslmode: {.val {safe_ssl}})",
    "*" = "BECMaster: {plots_lbl} plots, {veg_lbl} veg rows",
    "*" = "Active standards: {std_lbl}",
    "*" = "Pending staging submissions: {pending_lbl}"
  ))
  invisible(x)
}
