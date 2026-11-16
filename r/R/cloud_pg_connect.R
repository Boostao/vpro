# PostgreSQL BECMaster Connection, Schema Bootstrap & Canonicalizers -----------

.vpro_pg_s3_state <- new.env(parent = emptyenv())

.vpro_register_pg_s3 <- function() {
  .vpro_register_s3_methods(
    .vpro_pg_s3_state,
    list(
      c("base", "print", "vpro_pg_conn"),
      c("base", "print", "vpro_pg_status"),
      c("tibble", "as_tibble", "vpro_pg_status")
    )
  )
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
    if (
      n_val >= 2L &&
        ((startsWith(val, '"') && endsWith(val, '"')) ||
          (startsWith(val, "'") && endsWith(val, "'")))
    ) {
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
      if (!nzchar(pair)) {
        next
      }
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
    if (is.null(val) || length(val) == 0L) {
      return(invisible(NULL))
    }
    for (item in as.character(val)) {
      if (is.na(item)) {
        next
      }
      for (v in unique(c(item, trimws(item)))) {
        if (nchar(v) < 1L) {
          next
        }
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

#' Check offline availability of PostgreSQL `BECMaster` credentials
#'
#' Performs a completely offline inspection of process environment variables
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
#' the exact credential precedence shared with VPro Desktop:
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
#' @param pg A `vpro_pg_conn` connection object (or `NULL`).
#' @return `invisible(TRUE)` when an active connection was closed, or
#'   `invisible(FALSE)` when `pg` was already disconnected.
#' @export
vpro_master_disconnect <- function(pg) {
  if (is.null(pg)) {
    return(invisible(FALSE))
  }
  if (!inherits(pg, "vpro_pg_conn") || !is.list(pg) || is.null(pg$conn)) {
    cli::cli_abort(
      "{.arg pg} must be a {.cls vpro_pg_conn} connection created by {.fn vpro_master_connect}."
    )
  }
  valid <- tryCatch(DBI::dbIsValid(pg$conn), error = function(e) FALSE)
  if (!isTRUE(valid)) {
    return(invisible(FALSE))
  }
  tryCatch(DBI::dbDisconnect(pg$conn), error = function(e) NULL)
  invisible(TRUE)
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
