# Headless PostgreSQL BECMaster Contributor Staging & Custodian 3-Way Merge ----

.vpro_sync_s3_state <- new.env(parent = emptyenv())

.vpro_register_sync_s3 <- function() {
  if (isTRUE(.vpro_sync_s3_state$registered)) {
    return(invisible(NULL))
  }
  pkg_env <- environment(.vpro_register_sync_s3)
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

  reg_one("base", "print", "vpro_staging_queue")
  reg_one("base", "print", "vpro_merge_preview")
  reg_one("tibble", "as_tibble", "vpro_merge_preview")

  .vpro_sync_s3_state$registered <- TRUE
  invisible(NULL)
}

.vpro_merge_table_suffixes <- c("Env", "Admin", "Veg", "Humus", "Mineral", "Other")

.vpro_custodian_protected_admin_fields <- c("BECSiteUnit", "BEC_Use", "GIS_BGC")

.vpro_uuid_regex <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

# Internal Validation, Snapshot & Canonical Cell Helpers -----------------------

vpro_validate_uuid_arg <- function(x, arg_name = "submission_id") {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort("{.arg {arg_name}} must be a single valid UUID string.")
  }
  val <- tolower(trimws(x))
  if (!grepl(.vpro_uuid_regex, val, perl = TRUE)) {
    cli::cli_abort("{.arg {arg_name}} {.val {x}} is not a valid RFC 4122 UUID.")
  }
  val
}

vpro_validate_optional_scalar_chr <- function(x, arg_name) {
  if (is.null(x)) {
    return(NA_character_)
  }
  if (!is.character(x) || length(x) != 1L) {
    cli::cli_abort("{.arg {arg_name}} must be {.code NULL} or a single character string.")
  }
  if (is.na(x)) {
    return(NA_character_)
  }
  trimmed <- trimws(x)
  if (!nzchar(trimmed)) NA_character_ else trimmed
}

vpro_validate_merge_resolution_vec <- function(x, arg_name) {
  if (is.null(x) || length(x) == 0L) {
    return(stats::setNames(character(0L), character(0L)))
  }
  if (!is.character(x) || is.null(names(x))) {
    cli::cli_abort(
      "{.arg {arg_name}} must be {.code NULL} or a named character vector of {.val keep_target} / {.val accept_source}."
    )
  }
  nms <- names(x)
  if (anyNA(nms) || any(!nzchar(nms))) {
    cli::cli_abort("All names in {.arg {arg_name}} must be non-empty.")
  }
  vals <- trimws(as.character(x))
  bad <- is.na(vals) | !(vals %in% c("keep_target", "accept_source"))
  if (any(bad)) {
    cli::cli_abort(
      "Values in {.arg {arg_name}} must be {.val keep_target} or {.val accept_source}."
    )
  }
  stats::setNames(vals, nms)
}

vpro_sqlite_select_vp08_sql <- function(spec) {
  parts <- character(nrow(spec))
  for (i in seq_len(nrow(spec))) {
    col_nm <- spec$name[[i]]
    q_col <- vpro_quote_ident(col_nm)
    if (identical(spec$pg_type[[i]], "TEXT")) {
      parts[[i]] <- paste0(
        "CASE WHEN typeof(", q_col, ") = 'text' THEN CAST(", q_col, " AS TEXT) ",
        "WHEN ", q_col, " IS NULL THEN NULL ",
        "ELSE CAST(", q_col, " AS TEXT) END AS ", q_col
      )
    } else {
      parts[[i]] <- q_col
    }
  }
  paste(parts, collapse = ", ")
}

vpro_create_wal_consistent_snapshot <- function(src_path) {
  resolved <- normalizePath(src_path, winslash = "/", mustWork = TRUE)

  snap_path <- tempfile(pattern = "vpro-staging-snap-", fileext = ".db")
  unlink(snap_path, force = TRUE)
  cleanup_fn <- function() {
    unlink(c(snap_path, paste0(snap_path, "-wal"), paste0(snap_path, "-shm")), force = TRUE)
    invisible(NULL)
  }

  # Always capture an immutable VACUUM INTO snapshot so validation, SHA-256, and
  # streamed rows observe the exact same point-in-time state even if vpro_wails writes concurrently.
  con_ro <- DBI::dbConnect(RSQLite::SQLite(), resolved, flags = RSQLite::SQLITE_RO)
  tryCatch({
    tryCatch(DBI::dbExecute(con_ro, "PRAGMA busy_timeout = 5000"), error = function(e) NULL)
    esc_snap <- gsub("'", "''", normalizePath(snap_path, winslash = "/", mustWork = FALSE), fixed = TRUE)
    DBI::dbExecute(con_ro, paste0("VACUUM INTO '", esc_snap, "'"))
  }, error = function(e) {
    cleanup_fn()
    cli::cli_abort("Failed to capture WAL-consistent SQLite snapshot: {conditionMessage(e)}", parent = e)
  }, finally = {
    if (DBI::dbIsValid(con_ro)) {
      DBI::dbDisconnect(con_ro)
    }
  })

  list(
    path = normalizePath(snap_path, winslash = "/", mustWork = TRUE),
    cleanup = cleanup_fn
  )
}

vpro_repair_staging_child_ids <- function(ids_raw) {
  n <- length(ids_raw)
  if (n == 0L) {
    return(integer(0L))
  }
  nums <- suppressWarnings(as.double(ids_raw))
  finite_vals <- nums[!is.na(nums) & is.finite(nums) & nums == trunc(nums)]
  max_existing <- if (length(finite_vals) > 0L) max(finite_vals) else 0
  next_id <- max(100000000, max_existing + 1)

  seen <- new.env(hash = TRUE, parent = emptyenv())
  out <- numeric(n)
  for (i in seq_len(n)) {
    v <- nums[[i]]
    valid <- !is.na(v) && is.finite(v) && v == trunc(v)
    key <- if (valid) sprintf("%.0f", v) else ""
    if (!valid || exists(key, envir = seen, inherits = FALSE)) {
      repeat {
        cand_key <- sprintf("%.0f", next_id)
        if (!exists(cand_key, envir = seen, inherits = FALSE)) {
          v <- next_id
          key <- cand_key
          next_id <- next_id + 1
          break
        }
        next_id <- next_id + 1
      }
    }
    assign(key, TRUE, envir = seen)
    out[[i]] <- v
  }

  if (all(abs(out) <= .Machine$integer.max)) {
    as.integer(out)
  } else {
    out
  }
}

vpro_staging_preflight_bounds <- function(dbc, project, scoped_plots = NULL) {
  utf16_issues <- list()
  cover_issues <- list()

  add_u16 <- function(p_vec, tbl_lbl, col_nm, max_u16, vals_chr) {
    if (length(vals_chr) == 0L) return(invisible(NULL))
    non_na <- !is.na(vals_chr)
    if (!any(non_na)) return(invisible(NULL))
    idx_non_na <- which(non_na)
    sub_v <- as.character(vals_chr[idx_non_na])
    u16 <- vpro_utf16_len(sub_v)
    bad_utf8 <- is.na(u16)
    bad_len <- !is.na(u16) & (max_u16 > 0L) & (u16 > max_u16)
    bad <- which(bad_utf8 | bad_len)
    if (length(bad) > 0L) {
      orig_i <- idx_non_na[bad]
      p_sub <- if (length(p_vec) == length(vals_chr)) as.character(p_vec[orig_i]) else rep("", length(orig_i))
      det <- ifelse(
        bad_utf8[bad],
        sprintf("%s.%s contains malformed UTF-8 or unpaired UTF-16 surrogates.", tbl_lbl, col_nm),
        sprintf("%s.%s exceeds %d UTF-16 code units (got %d).", tbl_lbl, col_nm, max_u16, u16[bad])
      )
      utf16_issues[[length(utf16_issues) + 1L]] <<- tibble::tibble(
        PlotNumber = ifelse(is.na(p_sub), "", p_sub),
        category = rep("utf16_bounds", length(orig_i)),
        rule = rep(paste0("utf16:", tbl_lbl, ".", col_nm), length(orig_i)),
        severity = rep("error", length(orig_i)),
        detail = det
      )
    }
    invisible(NULL)
  }

  add_cov <- function(p_vec, tbl_lbl, col_nm, raw_vec) {
    if (length(raw_vec) == 0L) return(invisible(NULL))
    if (is.character(raw_vec)) {
      s <- trimws(raw_vec)
      non_blank <- !is.na(s) & nzchar(s)
      if (!any(non_blank)) return(invisible(NULL))
      idx_nb <- which(non_blank)
      num <- suppressWarnings(as.double(s[idx_nb]))
    } else {
      non_na <- !is.na(raw_vec)
      if (!any(non_na)) return(invisible(NULL))
      idx_nb <- which(non_na)
      num <- suppressWarnings(as.double(raw_vec[idx_nb]))
    }
    narrowed <- suppressWarnings(vpro_narrow_float32(ifelse(is.finite(num), num, NA_real_)))
    bad <- which(is.na(num) | !is.finite(num) | num < 0 | is.na(narrowed) | narrowed < 0 | narrowed >= 100)
    if (length(bad) > 0L) {
      orig_i <- idx_nb[bad]
      p_sub <- if (length(p_vec) == length(raw_vec)) as.character(p_vec[orig_i]) else rep("", length(orig_i))
      det <- sprintf(
        "%s.%s cover value (%s) must narrow to >= 0 and < 100 in IEEE-754 float32.",
        tbl_lbl,
        col_nm,
        as.character(raw_vec[orig_i])
      )
      cover_issues[[length(cover_issues) + 1L]] <<- tibble::tibble(
        PlotNumber = ifelse(is.na(p_sub), "", p_sub),
        category = rep("cover_bounds", length(orig_i)),
        rule = rep(paste0("float32_cover:", tbl_lbl, ".", col_nm), length(orig_i)),
        severity = rep("error", length(orig_i)),
        detail = det
      )
    }
    invisible(NULL)
  }

  for (suffix in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Metadata")) {
    tbl_name <- paste0(project, "_", suffix)
    if (!DBI::dbExistsTable(dbc, tbl_name)) next
    spec <- vpro_pg_vp08_specs(suffix)
    tbl_fields <- DBI::dbListFields(dbc, tbl_name)
    if (length(tbl_fields) == 0L) next

    present_spec <- spec[tolower(spec$name) %in% tolower(tbl_fields), , drop = FALSE]
    if (nrow(present_spec) == 0L) next

    key_col <- if (identical(suffix, "Admin")) {
      "Plot"
    } else if (identical(suffix, "Metadata")) {
      "ProjectID"
    } else {
      "PlotNumber"
    }

    sel_sql <- vpro_sqlite_select_vp08_sql(present_spec)
    q_tbl <- vpro_quote_ident(tbl_name)
    where_sql <- if (key_col %in% c("PlotNumber", "Plot")) {
      paste0(" WHERE typeof(", vpro_quote_ident(key_col), ") = 'text'")
    } else {
      ""
    }
    df_raw <- DBI::dbGetQuery(dbc, paste0("SELECT ", sel_sql, " FROM ", q_tbl, where_sql))
    if (nrow(df_raw) == 0L) next

    if (!is.null(scoped_plots) && (key_col %in% c("PlotNumber", "Plot")) && (key_col %in% names(df_raw))) {
      df_raw <- df_raw[as.character(df_raw[[key_col]]) %in% scoped_plots, , drop = FALSE]
      if (nrow(df_raw) == 0L) next
    }

    p_vec <- if (key_col %in% names(df_raw)) as.character(df_raw[[key_col]]) else rep("", nrow(df_raw))

    for (ci in seq_len(nrow(present_spec))) {
      cn <- present_spec$name[[ci]]
      col_val <- vpro_pg_match_df_col(df_raw, cn)
      if (is.null(col_val)) next
      if (identical(present_spec$pg_type[[ci]], "TEXT")) {
        chr_val <- vpro_pg_format_utc_text(col_val, cn)
        add_u16(p_vec, suffix, cn, present_spec$utf16_max[[ci]], chr_val)
      } else if (isTRUE(present_spec$is_cover[[ci]])) {
        add_cov(p_vec, suffix, cn, col_val)
      }
    }
  }

  empty_issues <- tibble::tibble(
    PlotNumber = character(),
    category = character(),
    rule = character(),
    severity = character(),
    detail = character()
  )
  u16_tbl <- if (length(utf16_issues) == 0L) empty_issues else do.call(rbind, utf16_issues)
  cov_tbl <- if (length(cover_issues) == 0L) empty_issues else do.call(rbind, cover_issues)

  list(
    utf16_issues = u16_tbl,
    cover_issues = cov_tbl,
    n_utf16_errors = nrow(u16_tbl),
    n_cover_errors = nrow(cov_tbl)
  )
}

vpro_extract_submission_artifacts <- function(ws, snap_path, scope = c("project", "su")) {
  scope <- match.arg(scope)
  use_su <- identical(scope, "su")

  su_scope_plots <- NULL
  if (use_su) {
    if (is.null(ws$su) || !nzchar(trimws(ws$su)) || identical(tolower(trimws(ws$su)), "none")) {
      cli::cli_abort(
        "{.code scope = \"su\"} requires an active {.file *_SU} site-unit table on {.arg project}."
      )
    }
    dbc_su <- vpro_sqlite_ro(ws$su_path)
    on.exit(DBI::dbDisconnect(dbc_su), add = TRUE)
    su_q <- vpro_quote_ident(ws$su)
    su_filter_df <- DBI::dbGetQuery(
      dbc_su,
      paste0(
        'SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber" FROM ', su_q,
        ' WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" <> \'\''
      )
    )
    su_scope_plots <- unique(as.character(su_filter_df$PlotNumber))
    if (length(su_scope_plots) == 0L) {
      cli::cli_abort("Active Site Unit table {.val {ws$su}} contains 0 text-keyed plots.")
    }
  }

  dbc <- vpro_sqlite_ro(snap_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  proj <- ws$project
  read_vp08_raw <- function(suffix, where_clause = "", order_clause = "") {
    tbl_nm <- paste0(proj, "_", suffix)
    spec <- vpro_pg_vp08_specs(suffix)
    if (!DBI::dbExistsTable(dbc, tbl_nm)) {
      empty_df <- as.data.frame(
        stats::setNames(replicate(nrow(spec), logical(0L), simplify = FALSE), spec$name),
        stringsAsFactors = FALSE
      )
      return(vpro_pg_canonicalize_to_pg(empty_df, spec))
    }
    existing_cols <- DBI::dbListFields(dbc, tbl_nm)
    present_spec <- spec[tolower(spec$name) %in% tolower(existing_cols), , drop = FALSE]
    if (nrow(present_spec) == 0L) {
      empty_df <- as.data.frame(
        stats::setNames(replicate(nrow(spec), logical(0L), simplify = FALSE), spec$name),
        stringsAsFactors = FALSE
      )
      return(vpro_pg_canonicalize_to_pg(empty_df, spec))
    }
    sql <- paste0(
      "SELECT ", vpro_sqlite_select_vp08_sql(present_spec),
      " FROM ", vpro_quote_ident(tbl_nm),
      where_clause,
      order_clause
    )
    DBI::dbGetQuery(dbc, sql)
  }

  raw_env <- read_vp08_raw("Env", ' WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" <> \'\'')
  if (nrow(raw_env) > 0L) {
    raw_env$PlotNumber <- as.character(raw_env$PlotNumber)
    if (!is.null(su_scope_plots)) {
      raw_env <- raw_env[raw_env$PlotNumber %in% su_scope_plots, , drop = FALSE]
    }
    raw_env <- raw_env[!duplicated(raw_env$PlotNumber), , drop = FALSE]
  }
  scoped_plots <- if (nrow(raw_env) > 0L) as.character(raw_env$PlotNumber) else character(0L)
  if (length(scoped_plots) == 0L) {
    cli::cli_abort("Project {.val {proj}} contains 0 valid text-keyed plots to submit.")
  }

  df_env <- vpro_pg_canonicalize_to_pg(raw_env, vpro_pg_vp08_specs("Env"))

  raw_admin <- read_vp08_raw("Admin", ' WHERE typeof("Plot") = \'text\' AND "Plot" <> \'\'')
  if (nrow(raw_admin) > 0L) {
    raw_admin$Plot <- as.character(raw_admin$Plot)
    raw_admin <- raw_admin[raw_admin$Plot %in% scoped_plots, , drop = FALSE]
    raw_admin <- raw_admin[!duplicated(raw_admin$Plot), , drop = FALSE]
  }
  df_admin <- vpro_pg_canonicalize_to_pg(raw_admin, vpro_pg_vp08_specs("Admin"))

  prep_child <- function(suffix) {
    raw_c <- read_vp08_raw(
      suffix,
      ' WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" <> \'\'',
      ' ORDER BY CAST("PlotNumber" AS BLOB)'
    )
    if (nrow(raw_c) > 0L) {
      raw_c$PlotNumber <- as.character(raw_c$PlotNumber)
      raw_c <- raw_c[raw_c$PlotNumber %in% scoped_plots, , drop = FALSE]
    }
    canon_c <- vpro_pg_canonicalize_to_pg(raw_c, vpro_pg_vp08_specs(suffix))
    if (nrow(canon_c) > 0L && ("ID" %in% names(canon_c))) {
      repaired_ids <- vpro_repair_staging_child_ids(canon_c$ID)
      if (is.double(repaired_ids) && any(abs(repaired_ids) > .Machine$integer.max)) {
        canon_c$ID <- sprintf("%.0f", repaired_ids)
      } else {
        canon_c$ID <- as.integer(repaired_ids)
      }
    }
    canon_c
  }

  df_veg <- prep_child("Veg")
  df_humus <- prep_child("Humus")
  df_mineral <- prep_child("Mineral")
  df_other <- prep_child("Other")

  raw_meta <- read_vp08_raw("Metadata", ' WHERE "ProjectID" IS NOT NULL')
  df_meta <- vpro_pg_canonicalize_to_pg(raw_meta, vpro_pg_vp08_specs("Metadata"))
  if (nrow(df_meta) > 0L) {
    keep_m <- !is.na(df_meta$ProjectID) & nzchar(df_meta$ProjectID)
    df_meta <- df_meta[keep_m, , drop = FALSE]
    if (nrow(df_meta) > 0L) {
      df_meta <- df_meta[!duplicated(df_meta$ProjectID), , drop = FALSE]
    }
  }

  raw_audit <- read_vp08_raw("Audit", "", " ORDER BY rowid")
  df_audit <- vpro_pg_canonicalize_to_pg(raw_audit, vpro_pg_vp08_specs("Audit"))
  if (nrow(df_audit) > 0L) {
    p_aud <- df_audit$PlotNumber
    keep_a <- is.na(p_aud) | !nzchar(p_aud) | (p_aud %in% scoped_plots)
    df_audit <- df_audit[keep_a, , drop = FALSE]
  }

  # ProjectID resolution (Metadata first, then Env fallback)
  project_id <- ""
  if (nrow(df_meta) > 0L && !is.na(df_meta$ProjectID[[1L]]) && nzchar(trimws(df_meta$ProjectID[[1L]]))) {
    project_id <- trimws(df_meta$ProjectID[[1L]])
  } else if (nrow(df_env) > 0L) {
    env_pids <- df_env$ProjectID[!is.na(df_env$ProjectID) & nzchar(trimws(df_env$ProjectID))]
    if (length(env_pids) > 0L) {
      project_id <- trimws(env_pids[[1L]])
    }
  }

  # Referenced personal species from VUser.USysUserSpp
  ref_spp_upper <- character(0L)
  if (nrow(df_veg) > 0L) {
    sp_trimmed <- trimws(ifelse(is.na(df_veg$Species), "", df_veg$Species))
    ref_spp_upper <- unique(toupper(sp_trimmed[nzchar(sp_trimmed)]))
  }

  species_records <- list()
  if (length(ref_spp_upper) > 0L && !is.null(ws$vuser_path) && file.exists(ws$vuser_path)) {
    dbc_u <- vpro_sqlite_ro(ws$vuser_path)
    on.exit(DBI::dbDisconnect(dbc_u), add = TRUE)
    if (DBI::dbExistsTable(dbc_u, "USysUserSpp")) {
      u_fields <- DBI::dbListFields(dbc_u, "USysUserSpp")
      col_or_null <- function(cn, cast_t = "TEXT") {
        hit <- u_fields[tolower(u_fields) == tolower(cn)]
        if (length(hit) >= 1L) {
          paste0("CAST(", vpro_quote_ident(hit[[1L]]), " AS ", cast_t, ") AS ", vpro_quote_ident(cn))
        } else {
          paste0("NULL AS ", vpro_quote_ident(cn))
        }
      }
      u_df <- DBI::dbGetQuery(
        dbc_u,
        paste0(
          "SELECT ",
          paste(
            c(
              col_or_null("Code", "TEXT"),
              col_or_null("ScientificName", "TEXT"),
              col_or_null("LifeForm", "INTEGER"),
              col_or_null("EnglishName", "TEXT"),
              col_or_null("Report", "REAL"),
              col_or_null("SppNumber", "INTEGER"),
              col_or_null("Codetype", "TEXT")
            ),
            collapse = ", "
          ),
          ' FROM "USysUserSpp" ORDER BY "Code" COLLATE NOCASE, "Code"'
        )
      )
      if (nrow(u_df) > 0L) {
        for (ri in seq_len(nrow(u_df))) {
          cd <- u_df$Code[[ri]]
          if (is.na(cd) || !nzchar(trimws(cd))) next
          if (!(toupper(trimws(cd)) %in% ref_spp_upper)) next
          rec <- list(
            code = as.character(cd),
            scientificName = if (is.na(u_df$ScientificName[[ri]])) NULL else as.character(u_df$ScientificName[[ri]]),
            lifeForm = if (is.na(u_df$LifeForm[[ri]])) NULL else as.integer(u_df$LifeForm[[ri]]),
            englishName = if (is.na(u_df$EnglishName[[ri]])) NULL else as.character(u_df$EnglishName[[ri]])
          )
          if (!is.na(u_df$Report[[ri]]) && is.finite(as.double(u_df$Report[[ri]]))) {
            rec$report <- as.double(u_df$Report[[ri]])
          }
          if (!is.na(u_df$SppNumber[[ri]])) {
            rec$sppNumber <- as.integer(u_df$SppNumber[[ri]])
          }
          if (!is.na(u_df$Codetype[[ri]])) {
            rec$codetype <- as.character(u_df$Codetype[[ri]])
          }
          species_records[[length(species_records) + 1L]] <- rec
        }
      }
    }
  }

  species_json <- as.character(jsonlite::toJSON(species_records, auto_unbox = TRUE, null = "null"))
  payload_sha256 <- vpro_sha256_utf8(species_json)[[1L]]
  exported_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  user_manifest <- list(
    schemaVersion = "vpro.userspecies.v1",
    exportedAt = exported_at,
    sourceProject = proj,
    rowCount = as.integer(length(species_records)),
    payloadSha256 = payload_sha256,
    species = species_records
  )

  # Extract <Project>_Lump (or active ws$lump)
  lump_records <- list()
  lump_tbl <- if (!is.null(ws$lump) && nzchar(ws$lump)) ws$lump else paste0(proj, "_Lump")
  lump_db_path <- if (!is.null(ws$lump_path) && file.exists(ws$lump_path) && !identical(ws$lump_path, ws$project_path)) {
    ws$lump_path
  } else {
    snap_path
  }
  dbc_lump <- vpro_sqlite_ro(lump_db_path)
  on.exit(DBI::dbDisconnect(dbc_lump), add = TRUE)
  if (DBI::dbExistsTable(dbc_lump, lump_tbl)) {
    l_df <- DBI::dbGetQuery(
      dbc_lump,
      paste0(
        'SELECT COALESCE(CAST("LumpCode" AS TEXT), \'\') AS "LumpCode", ',
        'COALESCE(CAST("SppCode" AS TEXT), \'\') AS "SppCode", ',
        'COALESCE("Use", 0) AS "Use" FROM ',
        vpro_quote_ident(lump_tbl),
        ' ORDER BY "LumpCode", "SppCode"'
      )
    )
    if (nrow(l_df) > 0L) {
      for (li in seq_len(nrow(l_df))) {
        lc <- as.character(l_df$LumpCode[[li]])
        sc <- as.character(l_df$SppCode[[li]])
        if (nzchar(lc) && nzchar(sc)) {
          lump_records[[length(lump_records) + 1L]] <- list(
            lumpCode = lc,
            sppCode = sc,
            use = isTRUE(vpro_access_to_logical(l_df$Use[[li]]))
          )
        }
      }
    }
  }

  # Extract active *_SU (or <Project>_SU)
  su_records <- list()
  su_tbl_cand <- if (!is.null(ws$su) && nzchar(ws$su)) ws$su else paste0(proj, "_SU")
  su_db_cand <- if (!is.null(ws$su) && !is.null(ws$su_path) && file.exists(ws$su_path) &&
                    !identical(ws$su_path, ws$project_path)) {
    ws$su_path
  } else {
    snap_path
  }
  dbc_su_read <- vpro_sqlite_ro(su_db_cand)
  on.exit(DBI::dbDisconnect(dbc_su_read), add = TRUE)
  if (DBI::dbExistsTable(dbc_su_read, su_tbl_cand)) {
    s_df <- DBI::dbGetQuery(
      dbc_su_read,
      paste0(
        'SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber", ',
        'CAST("SiteUnit" AS TEXT) AS "SiteUnit" FROM ',
        vpro_quote_ident(su_tbl_cand),
        ' WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" <> \'\' ',
        'ORDER BY CAST("PlotNumber" AS BLOB)'
      )
    )
    if (nrow(s_df) > 0L) {
      for (si in seq_len(nrow(s_df))) {
        p_su <- as.character(s_df$PlotNumber[[si]])
        su_v <- s_df$SiteUnit[[si]]
        su_records[[length(su_records) + 1L]] <- list(
          plotNumber = p_su,
          siteUnit = if (is.na(su_v)) NULL else as.character(su_v)
        )
      }
    }
  }

  list(
    scoped_plots = scoped_plots,
    project_id = project_id,
    tables = list(
      env = df_env,
      admin = df_admin,
      veg = df_veg,
      humus = df_humus,
      mineral = df_mineral,
      other = df_other,
      metadata = df_meta,
      audit = df_audit
    ),
    user_manifest = user_manifest,
    lump_records = lump_records,
    su_records = su_records
  )
}

# Public Contributor & Queue Inspection API ------------------------------------

#' Submit a local `VP08` project to PostgreSQL `BECMaster` staging
#'
#' Runs mandatory pre-flight standards, referential, `LMH25 (2023)` pedological,
#' UTF-16 code-unit (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`,
#' `Texture <= 4`, `Colour <= 14`, quality labels `<= 15`), and IEEE-754
#' `float32 < 100` cover validation ([vpro_validate()] +
#' [vpro_narrow_float32()]), captures a WAL-consistent SQLite snapshot, packages
#' referenced personal species from `VUser.db` (`USysUserSpp`) alongside active
#' `<Project>_Lump` and `*_SU` assignments, and streams all eight `VP08` tables
#' into `staging.*` inside a single atomic PostgreSQL transaction.
#'
#' @param con An active `vpro_pg_conn` connection from [vpro_master_connect()].
#' @param project Either a `vpro_workspace` handle from [vpro_connect()] or a
#'   character project name / `.db` file path. The built-in `"Sample"` project
#'   is rejected.
#' @param submitter Non-empty character string identifying the submitting
#'   analyst or ecologist.
#' @param notes Optional character note for custodian review.
#' @param scope Plot submission scope: `"project"` (all valid text-keyed plots
#'   in `<Project>_Env`) or `"su"` (restricted to plots in the active `*_SU`
#'   table).
#' @param base_snapshot_tag Optional `BECMaster` baseline snapshot tag from
#'   which the project splinter was originally checked out.
#' @param custodian_override Logical; if `TRUE` on a `"custodian"` connection,
#'   permits staging upload when [vpro_validate()] reports blocking QA errors
#'   (recording `compliance_passed = FALSE` for custodial remediation).
#' @return A named list with `submission_id`, `project_name`, `project_id`,
#'   `submitted_by`, `db_role`, `status`, `plot_count`, `veg_row_count`,
#'   `user_species_count`, `source_db_sha256`, `compliance_passed`, and
#'   `submitted_at`.
#' @export
vpro_staging_submit <- function(
  con,
  project,
  submitter,
  notes = NULL,
  scope = c("project", "su"),
  base_snapshot_tag = NULL,
  custodian_override = FALSE
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  scope <- match.arg(scope)
  custodian_override <- vpro_pg_validate_flag(custodian_override, "custodian_override")

  if (!is.character(submitter) || length(submitter) != 1L || is.na(submitter) || !nzchar(trimws(submitter))) {
    cli::cli_abort("{.arg submitter} must be a single non-empty character string.")
  }
  submitter_clean <- trimws(submitter)
  notes_clean <- vpro_validate_optional_scalar_chr(notes, "notes")
  base_tag_clean <- vpro_validate_optional_scalar_chr(base_snapshot_tag, "base_snapshot_tag")

  ws <- if (inherits(project, "vpro_workspace")) {
    project
  } else if (is.character(project) && length(project) == 1L && !is.na(project) && nzchar(trimws(project))) {
    vpro_connect(project)
  } else {
    cli::cli_abort(
      "{.arg project} must be a {.cls vpro_workspace} handle or a single non-empty project name / SQLite path."
    )
  }
  vpro_assert_workspace(ws)

  if (identical(tolower(trimws(ws$project)), "sample")) {
    cli::cli_abort(
      "The built-in {.val Sample} project cannot be submitted to provincial {.code BECMaster} staging."
    )
  }
  if (identical(scope, "su") &&
      (is.null(ws$su) || !nzchar(trimws(ws$su)) || identical(tolower(trimws(ws$su)), "none"))) {
    cli::cli_abort(
      "{.code scope = \"su\"} requires an active {.file *_SU} site-unit table on {.arg project}."
    )
  }

  snap <- vpro_create_wal_consistent_snapshot(ws$project_path)
  on.exit(snap$cleanup(), add = TRUE)
  snap_path <- snap$path
  source_db_sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(snap_path)))))

  ws_snap <- ws
  ws_snap$project_path <- snap_path
  if (identical(ws$lump_path, ws$project_path)) {
    ws_snap$lump_path <- snap_path
  }
  if (identical(ws$su_path, ws$project_path)) {
    ws_snap$su_path <- snap_path
  }

  val <- vpro_validate(ws_snap, scope = scope)

  scoped_filter_plots <- NULL
  if (identical(scope, "su")) {
    su_df <- vpro_site_units(ws_snap, exclude_modifiers = FALSE)
    scoped_filter_plots <- unique(as.character(su_df$PlotNumber))
  }

  dbc_bounds <- vpro_sqlite_ro(snap_path)
  bounds_res <- tryCatch(
    vpro_staging_preflight_bounds(dbc_bounds, ws_snap$project, scoped_plots = scoped_filter_plots),
    finally = DBI::dbDisconnect(dbc_bounds)
  )

  val_err_mask <- val$issues$severity == "error"
  n_val_errors <- as.integer(sum(val_err_mask))
  n_val_warnings <- as.integer(sum(val$issues$severity == "warning"))
  n_utf16_errors <- as.integer(bounds_res$n_utf16_errors)
  n_cover_errors <- as.integer(bounds_res$n_cover_errors)
  total_blocking <- n_val_errors + n_utf16_errors + n_cover_errors
  compliance_passed <- isTRUE(val$passed) && (n_utf16_errors == 0L) && (n_cover_errors == 0L)

  can_override <- isTRUE(custodian_override) && identical(con$role, "custodian")
  if (!compliance_passed && !can_override) {
    cli::cli_abort(c(
      "Staging submission for project {.val {ws_snap$project}} blocked by pre-flight compliance gate ({total_blocking} blocking error{?s}).",
      "x" = "Standards/LMH25/orphan errors: {n_val_errors} (warnings: {n_val_warnings})",
      "x" = "UTF-16 length / encoding errors: {n_utf16_errors}",
      "x" = "IEEE-754 float32 cover (< 100) errors: {n_cover_errors}",
      "i" = "Inspect violations with {.fn vpro_validate} and resolve errors before calling {.fn vpro_staging_submit}."
    ))
  }

  combined_issues <- rbind(val$issues, bounds_res$utf16_issues, bounds_res$cover_issues)
  comp_summary <- list(
    validationErrors = n_val_errors,
    validationWarnings = n_val_warnings,
    utf16Errors = n_utf16_errors,
    coverErrors = n_cover_errors,
    envCodeErrors = as.integer(nrow(val$env_codes)),
    unlistedSpecies = as.integer(sum(val$veg_codes$status == "unlisted")),
    synonymWarnings = as.integer(sum(val$veg_codes$status == "synonym")),
    orphanErrors = as.integer(sum(val$orphans$issue != "plot_without_veg")),
    duplicateLayerErrors = as.integer(sum(val$duplicates$same_layer_conflict)),
    lmh25Errors = as.integer(sum(val$lmh25$issues$severity == "error"))
  )
  comp_payload <- list(
    project = ws_snap$project,
    scope = scope,
    passed = compliance_passed,
    blockingCount = total_blocking,
    custodianOverride = isTRUE(!compliance_passed && can_override),
    summary = comp_summary,
    issues = if (nrow(combined_issues) > 500L) combined_issues[seq_len(500L), , drop = FALSE] else combined_issues
  )
  compliance_report_json <- as.character(
    jsonlite::toJSON(comp_payload, dataframe = "rows", auto_unbox = TRUE, null = "null")
  )

  artifacts <- vpro_extract_submission_artifacts(ws_snap, snap_path, scope = scope)
  manifest_json <- as.character(
    jsonlite::toJSON(artifacts$user_manifest, auto_unbox = TRUE, null = "null")
  )
  lump_json <- as.character(
    jsonlite::toJSON(artifacts$lump_records, auto_unbox = TRUE, null = "null")
  )
  su_json <- as.character(
    jsonlite::toJSON(artifacts$su_records, auto_unbox = TRUE, null = "null")
  )

  submission_id <- vpro_uuid_v4()
  plot_count <- as.integer(nrow(artifacts$tables$env))
  veg_row_count <- as.integer(nrow(artifacts$tables$veg))
  proj_id_param <- if (nzchar(artifacts$project_id)) artifacts$project_id else NA_character_

  tx_meta <- vpro_pg_exec_safe(
    function() {
      out_meta <- NULL
      DBI::dbWithTransaction(con$conn, {
        role_df <- DBI::dbGetQuery(
          con$conn,
          "SELECT current_user AS db_role, to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS now_utc"
        )
        cur_role <- as.character(role_df$db_role[[1L]])
        now_utc <- as.character(role_df$now_utc[[1L]])

        DBI::dbExecute(
          con$conn,
          paste(
            "INSERT INTO staging.submissions (",
            "  submission_id, project_name, project_id, submitted_by, db_role, submitted_at,",
            "  status, plot_count, veg_row_count, source_db_sha256, compliance_passed,",
            "  compliance_report, user_species_manifest, lump_rows, su_rows,",
            "  submitter_notes, base_snapshot_tag",
            ") VALUES (",
            "  $1::uuid, $2, $3::text, $4, $5, $6::timestamptz,",
            "  'pending', $7::int, $8::int, $9, $10::boolean,",
            "  $11::jsonb, $12::jsonb, $13::jsonb, $14::jsonb,",
            "  $15::text, $16::text",
            ")"
          ),
          params = list(
            submission_id,
            ws_snap$project,
            proj_id_param,
            submitter_clean,
            cur_role,
            now_utc,
            plot_count,
            veg_row_count,
            source_db_sha256,
            compliance_passed,
            compliance_report_json,
            manifest_json,
            lump_json,
            su_json,
            notes_clean,
            base_tag_clean
          )
        )

        for (pg_tbl in c("env", "admin", "veg", "humus", "mineral", "other", "metadata", "audit")) {
          df_t <- artifacts$tables[[pg_tbl]]
          if (nrow(df_t) == 0L) next
          df_sub <- cbind(
            data.frame(submission_id = rep(submission_id, nrow(df_t)), stringsAsFactors = FALSE),
            df_t
          )
          rownames(df_sub) <- NULL
          DBI::dbAppendTable(
            con$conn,
            DBI::Id(schema = "staging", table = pg_tbl),
            df_sub
          )
        }

        out_meta <- list(db_role = cur_role, submitted_at = now_utc)
      })
      out_meta
    },
    action = "submit project to PostgreSQL staging"
  )

  list(
    submission_id = submission_id,
    project_name = ws_snap$project,
    project_id = artifacts$project_id,
    submitted_by = submitter_clean,
    db_role = tx_meta$db_role,
    status = "pending",
    plot_count = plot_count,
    veg_row_count = veg_row_count,
    user_species_count = as.integer(artifacts$user_manifest$rowCount),
    source_db_sha256 = source_db_sha256,
    compliance_passed = compliance_passed,
    submitted_at = tx_meta$submitted_at
  )
}

vpro_format_staging_queue_df <- function(df) {
  .vpro_register_sync_s3()
  n <- nrow(df)
  chr_col <- function(nm) {
    if (nm %in% names(df)) as.character(df[[nm]]) else rep(NA_character_, n)
  }
  int_col <- function(nm) {
    if (nm %in% names(df)) suppressWarnings(as.integer(as.character(df[[nm]]))) else rep(NA_integer_, n)
  }
  lgl_col <- function(nm) {
    if (nm %in% names(df)) vpro_access_to_logical(df[[nm]]) else rep(NA, n)
  }

  tbl <- tibble::tibble(
    submission_id = chr_col("submission_id"),
    project_name = chr_col("project_name"),
    project_id = chr_col("project_id"),
    submitted_by = chr_col("submitted_by"),
    db_role = chr_col("db_role"),
    submitted_at = chr_col("submitted_at"),
    status = chr_col("status"),
    plot_count = int_col("plot_count"),
    veg_row_count = int_col("veg_row_count"),
    source_db_sha256 = chr_col("source_db_sha256"),
    compliance_passed = lgl_col("compliance_passed"),
    user_species_count = int_col("user_species_count"),
    lump_row_count = int_col("lump_row_count"),
    su_row_count = int_col("su_row_count"),
    submitter_notes = chr_col("submitter_notes"),
    base_snapshot_tag = chr_col("base_snapshot_tag"),
    reviewer_notes = chr_col("reviewer_notes"),
    reviewed_by = chr_col("reviewed_by"),
    reviewed_at = chr_col("reviewed_at"),
    merged_tx_id = chr_col("merged_tx_id")
  )
  structure(tbl, class = c("vpro_staging_queue", "tbl_df", "tbl", "data.frame"))
}

.vpro_staging_summary_select_sql <- paste(
  "SELECT",
  "  submission_id::text AS submission_id,",
  "  project_name,",
  "  project_id,",
  "  submitted_by,",
  "  db_role,",
  "  to_char(submitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS submitted_at,",
  "  status,",
  "  plot_count,",
  "  veg_row_count,",
  "  source_db_sha256,",
  "  compliance_passed,",
  "  COALESCE((user_species_manifest->>'rowCount')::int, 0) AS user_species_count,",
  "  COALESCE(jsonb_array_length(lump_rows), 0) AS lump_row_count,",
  "  COALESCE(jsonb_array_length(su_rows), 0) AS su_row_count,",
  "  submitter_notes,",
  "  base_snapshot_tag,",
  "  reviewer_notes,",
  "  reviewed_by,",
  "  CASE WHEN reviewed_at IS NULL THEN NULL",
  "       ELSE to_char(reviewed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') END AS reviewed_at,",
  "  merged_tx_id::text AS merged_tx_id",
  "FROM staging.submissions"
)

#' List submissions in the PostgreSQL `staging.submissions` queue
#'
#' Queries contributor staging submissions ordered newest-first (`submitted_at DESC`)
#' with optional parameterized status and submitter filters.
#'
#' @param con A `vpro_pg_conn` handle from [vpro_master_connect()].
#' @param status Queue status filter: `"pending"` (default), `"approved"`,
#'   `"rejected"`, `"merged"`, or `NULL` / `"all"` to return all statuses.
#' @param submitted_by Optional submitter name filter (`submitted_by = $n`).
#' @param limit Positive integer maximum rows to return (default `100L`).
#' @return A tibble of class `vpro_staging_queue` summarizing matching
#'   submissions.
#' @export
vpro_staging_list <- function(
  con,
  status = "pending",
  submitted_by = NULL,
  limit = 100L
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  .vpro_register_sync_s3()
  limit_int <- vpro_pg_validate_limit(limit, allow_null = FALSE)

  clauses <- character(0L)
  params <- list()
  next_param <- function(val) {
    params[[length(params) + 1L]] <<- val
    paste0("$", length(params))
  }

  if (!is.null(status)) {
    if (!is.character(status) || length(status) != 1L || is.na(status)) {
      cli::cli_abort(
        "{.arg status} must be {.code NULL}, {.val all}, or one of {.val pending}, {.val approved}, {.val rejected}, {.val merged}."
      )
    }
    st_clean <- tolower(trimws(status))
    if (nzchar(st_clean) && !identical(st_clean, "all")) {
      valid_st <- c("pending", "approved", "rejected", "merged")
      if (!(st_clean %in% valid_st)) {
        cli::cli_abort(
          "{.arg status} must be {.code NULL}, {.val all}, or one of {.or {.val {valid_st}}}."
        )
      }
      clauses <- c(clauses, paste0("status = ", next_param(st_clean)))
    }
  }

  sub_by_clean <- vpro_validate_optional_scalar_chr(submitted_by, "submitted_by")
  if (!is.na(sub_by_clean)) {
    clauses <- c(clauses, paste0("submitted_by = ", next_param(sub_by_clean)))
  }

  lim_p <- next_param(limit_int)
  where_sql <- if (length(clauses) > 0L) paste0(" WHERE ", paste(clauses, collapse = " AND ")) else ""
  sql <- paste0(
    .vpro_staging_summary_select_sql,
    where_sql,
    " ORDER BY submitted_at DESC LIMIT ", lim_p
  )

  df <- vpro_pg_query(con, sql, params = params, action = "list staging.submissions")
  vpro_format_staging_queue_df(df)
}

#' Print a `vpro_staging_queue` submission queue tibble
#'
#' @param x A `vpro_staging_queue` object returned by [vpro_staging_list()].
#' @param ... Additional arguments passed to the underlying tibble `print()`
#'   method.
#' @return `x`, invisibly.
#' @export
print.vpro_staging_queue <- function(x, ...) {
  n <- nrow(x)
  if (n == 0L) {
    cli::cli_h3("vpro_staging_queue (0 submissions)")
  } else {
    counts <- table(x$status)
    parts <- paste0(names(counts), "=", as.integer(counts))
    cli::cli_h3("vpro_staging_queue ({n} submission{?s}: {paste(parts, collapse = ', ')})")
  }
  NextMethod()
  invisible(x)
}

#' Inspect a staging submission's compliance report and provisional species
#'
#' Retrieves full header metadata, parsed `compliance_report`, packaged personal
#' species (`user_species_manifest`), `<Project>_Lump` mappings, and `*_SU`
#' assignments for `submission_id`, comparing each personal species against
#' `standards.usys_all_specs` (`"matches_official"` on `UPPER("Code")`,
#' `"matches_synonym"` on `UPPER("OldCode")`, or `"new_provisional"`).
#'
#' @param con A `vpro_pg_conn` handle from [vpro_master_connect()].
#' @param submission_id Submission UUID string.
#' @return A list with `summary` (1-row `vpro_staging_queue` tibble),
#'   `compliance_report` (parsed list), `user_species` (tibble),
#'   `provisional_diffs` (tibble), `lump` (tibble), and `su` (tibble).
#' @export
vpro_staging_inspect <- function(con, submission_id) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")

  sql <- paste0(
    "SELECT sub.*, ",
    "  s_raw.compliance_report::text AS compliance_report_raw, ",
    "  s_raw.user_species_manifest::text AS user_species_manifest_raw, ",
    "  s_raw.lump_rows::text AS lump_rows_raw, ",
    "  s_raw.su_rows::text AS su_rows_raw ",
    "FROM (", .vpro_staging_summary_select_sql, " WHERE submission_id = $1::uuid) AS sub ",
    "INNER JOIN staging.submissions AS s_raw ON s_raw.submission_id::text = sub.submission_id"
  )
  df <- vpro_pg_query(con, sql, params = list(sub_id), action = "inspect staging submission")
  if (nrow(df) == 0L) {
    cli::cli_abort("Staging submission {.val {sub_id}} was not found.")
  }

  summary_tbl <- vpro_format_staging_queue_df(df[1L, , drop = FALSE])

  parse_json_safe <- function(raw_txt, simplify_vec = FALSE) {
    if (is.null(raw_txt) || length(raw_txt) == 0L || is.na(raw_txt[[1L]]) || !nzchar(trimws(raw_txt[[1L]]))) {
      return(NULL)
    }
    jsonlite::fromJSON(as.character(raw_txt[[1L]]), simplifyVector = simplify_vec)
  }

  comp_parsed <- parse_json_safe(df$compliance_report_raw[[1L]], simplify_vec = TRUE)
  if (is.null(comp_parsed)) {
    comp_parsed <- list()
  }

  manifest_parsed <- parse_json_safe(df$user_species_manifest_raw[[1L]], simplify_vec = FALSE)
  sp_list <- if (is.list(manifest_parsed) && is.list(manifest_parsed$species)) {
    manifest_parsed$species
  } else {
    list()
  }

  if (length(sp_list) == 0L) {
    user_species_tbl <- tibble::tibble(
      Code = character(),
      ScientificName = character(),
      LifeForm = integer(),
      EnglishName = character(),
      Report = numeric(),
      SppNumber = integer(),
      Codetype = character()
    )
  } else {
    extr_chr <- function(rec, k) {
      v <- rec[[k]]
      if (is.null(v) || length(v) == 0L || is.na(v[[1L]])) NA_character_ else as.character(v[[1L]])
    }
    extr_int <- function(rec, k) {
      v <- rec[[k]]
      if (is.null(v) || length(v) == 0L || is.na(v[[1L]])) NA_integer_ else suppressWarnings(as.integer(v[[1L]]))
    }
    extr_num <- function(rec, k) {
      v <- rec[[k]]
      if (is.null(v) || length(v) == 0L || is.na(v[[1L]])) NA_real_ else suppressWarnings(as.double(v[[1L]]))
    }
    user_species_tbl <- tibble::tibble(
      Code = vapply(sp_list, extr_chr, character(1L), "code"),
      ScientificName = vapply(sp_list, extr_chr, character(1L), "scientificName"),
      LifeForm = vapply(sp_list, extr_int, integer(1L), "lifeForm"),
      EnglishName = vapply(sp_list, extr_chr, character(1L), "englishName"),
      Report = vapply(sp_list, extr_num, numeric(1L), "report"),
      SppNumber = vapply(sp_list, extr_int, integer(1L), "sppNumber"),
      Codetype = vapply(sp_list, extr_chr, character(1L), "codetype")
    )
  }

  # Compare personal species against standards.usys_all_specs
  if (nrow(user_species_tbl) == 0L) {
    prov_diffs_tbl <- tibble::tibble(
      Code = character(),
      ScientificName = character(),
      LifeForm = integer(),
      status = character(),
      official_code = character(),
      official_scientific = character()
    )
  } else {
    codes_up <- unique(toupper(trimws(user_species_tbl$Code[!is.na(user_species_tbl$Code) & nzchar(trimws(user_species_tbl$Code))])))
    std_df <- if (length(codes_up) > 0L) {
      tryCatch(
        vpro_pg_query(
          con,
          paste(
            'SELECT UPPER(TRIM(COALESCE("Code", \'\'))) AS code_up,',
            '       UPPER(TRIM(COALESCE("OldCode", \'\'))) AS old_up,',
            '       COALESCE("Code", \'\') AS official_code,',
            '       COALESCE("ScientificName", \'\') AS official_scientific,',
            '       LOWER(TRIM(COALESCE("Codetype", \'\'))) AS codetype_low,',
            "       row_seq",
            "FROM standards.usys_all_specs",
            'WHERE UPPER("Code") = ANY($1::text[]) OR UPPER("OldCode") = ANY($1::text[])',
            "ORDER BY CASE WHEN LOWER(TRIM(COALESCE(\"Codetype\", ''))) = 's' THEN 1 ELSE 0 END, row_seq"
          ),
          params = list(vpro_pg_text_array(codes_up)),
          action = "compare provisional species against standards.usys_all_specs"
        ),
        error = function(e) data.frame()
      )
    } else {
      data.frame()
    }

    st_vec <- rep("new_provisional", nrow(user_species_tbl))
    off_c <- rep(NA_character_, nrow(user_species_tbl))
    off_s <- rep(NA_character_, nrow(user_species_tbl))

    if (nrow(std_df) > 0L) {
      for (i in seq_len(nrow(user_species_tbl))) {
        cu <- toupper(trimws(ifelse(is.na(user_species_tbl$Code[[i]]), "", user_species_tbl$Code[[i]])))
        if (!nzchar(cu)) next
        m_off <- which(std_df$code_up == cu & nzchar(std_df$official_code))
        if (length(m_off) >= 1L) {
          st_vec[[i]] <- "matches_official"
          off_c[[i]] <- as.character(std_df$official_code[[m_off[[1L]]]])
          off_s[[i]] <- as.character(std_df$official_scientific[[m_off[[1L]]]])
        } else {
          m_syn <- which(std_df$old_up == cu & nzchar(std_df$official_code))
          if (length(m_syn) >= 1L) {
            st_vec[[i]] <- "matches_synonym"
            off_c[[i]] <- as.character(std_df$official_code[[m_syn[[1L]]]])
            off_s[[i]] <- as.character(std_df$official_scientific[[m_syn[[1L]]]])
          }
        }
      }
    }

    prov_diffs_tbl <- tibble::tibble(
      Code = user_species_tbl$Code,
      ScientificName = user_species_tbl$ScientificName,
      LifeForm = user_species_tbl$LifeForm,
      status = st_vec,
      official_code = off_c,
      official_scientific = off_s
    )
  }

  json_chr_or_empty <- function(v) {
    if (is.null(v) || length(v) == 0L || is.na(v[[1L]])) "" else as.character(v[[1L]])
  }

  lump_parsed <- parse_json_safe(df$lump_rows_raw[[1L]], simplify_vec = FALSE)
  if (!is.list(lump_parsed) || length(lump_parsed) == 0L) {
    lump_tbl <- tibble::tibble(LumpCode = character(), SppCode = character(), Use = logical())
  } else {
    lump_tbl <- tibble::tibble(
      LumpCode = vapply(lump_parsed, function(r) json_chr_or_empty(r$lumpCode), character(1L)),
      SppCode = vapply(lump_parsed, function(r) json_chr_or_empty(r$sppCode), character(1L)),
      Use = vapply(lump_parsed, function(r) isTRUE(vpro_access_to_logical(r$use)), logical(1L))
    )
  }

  su_parsed <- parse_json_safe(df$su_rows_raw[[1L]], simplify_vec = FALSE)
  if (!is.list(su_parsed) || length(su_parsed) == 0L) {
    su_tbl <- tibble::tibble(PlotNumber = character(), SiteUnit = character())
  } else {
    su_tbl <- tibble::tibble(
      PlotNumber = vapply(su_parsed, function(r) json_chr_or_empty(r$plotNumber), character(1L)),
      SiteUnit = vapply(su_parsed, function(r) {
        if (is.null(r$siteUnit) || length(r$siteUnit) == 0L || is.na(r$siteUnit[[1L]])) {
          NA_character_
        } else {
          as.character(r$siteUnit[[1L]])
        }
      }, character(1L))
    )
  }

  list(
    summary = summary_tbl,
    compliance_report = comp_parsed,
    user_species = user_species_tbl,
    provisional_diffs = prov_diffs_tbl,
    lump = lump_tbl,
    su = su_tbl
  )
}

# Pure In-Memory 3-Way Diff Engine (1:1 with custodian_merge.go) ---------------

vpro_format_float15 <- function(x) {
  out <- rep(NA_character_, length(x))
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    vals <- as.double(x[ok])
    vals[vals == 0] <- 0.0
    res <- sprintf("%.15g", vals)
    res[vals == 0] <- "0"
    out[ok] <- res
  }
  out
}

vpro_float64_hex_bits <- function(x) {
  n <- length(x)
  out <- rep("", n)
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    vals <- as.double(x[ok])
    vals[vals == 0] <- 0.0
    raw_b <- writeBin(vals, raw(), size = 8L, endian = "big")
    hex_mat <- matrix(sprintf("%02x", as.integer(raw_b)), nrow = 8L)
    out[ok] <- paste0(
      hex_mat[1L, ], hex_mat[2L, ], hex_mat[3L, ], hex_mat[4L, ],
      hex_mat[5L, ], hex_mat[6L, ], hex_mat[7L, ], hex_mat[8L, ]
    )
  }
  out
}

vpro_match_table_by_suffix <- function(tables_list, suffix) {
  if (is.null(tables_list) || !is.list(tables_list) || length(tables_list) == 0L) {
    return(NULL)
  }
  nms <- names(tables_list)
  if (is.null(nms)) {
    return(NULL)
  }
  if (suffix %in% nms) {
    return(tables_list[[suffix]])
  }
  ci <- match(tolower(suffix), tolower(nms))
  if (!is.na(ci)) {
    return(tables_list[[ci]])
  }
  NULL
}

vpro_build_cloud_snapshot <- function(label, tables_list) {
  if (is.null(tables_list)) {
    return(NULL)
  }

  plots_seen <- character(0L)
  comp_by_suffix <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  raw_by_suffix <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)

  for (suffix in .vpro_merge_table_suffixes) {
    spec <- vpro_pg_vp08_specs(suffix)
    df_in <- vpro_match_table_by_suffix(tables_list, suffix)
    if (is.null(df_in) || nrow(df_in) == 0L) {
      comp_by_suffix[[suffix]] <- list()
      raw_by_suffix[[suffix]] <- list()
      next
    }

    df <- as.data.frame(df_in, stringsAsFactors = FALSE)
    n_rows <- nrow(df)
    n_cols <- nrow(spec)

    raw_cols <- stats::setNames(vector("list", n_cols), spec$name)
    comp_cols <- stats::setNames(vector("list", n_cols), spec$name)
    hash_cols <- stats::setNames(vector("list", n_cols), spec$name)

    for (ci in seq_len(n_cols)) {
      cn <- spec$name[[ci]]
      pg_t <- spec$pg_type[[ci]]
      is_b <- isTRUE(spec$is_bool[[ci]])
      col_v <- vpro_pg_match_df_col(df, cn)

      if (is_b) {
        acc <- if (is.null(col_v)) rep(NA_integer_, n_rows) else vpro_logical_to_access(col_v)
        raw_cols[[ci]] <- acc
        comp_cols[[ci]] <- ifelse(is.na(acc), NA_character_, as.character(acc))
        hash_cols[[ci]] <- ifelse(is.na(acc), "null", paste0("int:", acc))
      } else if (identical(pg_t, "TEXT")) {
        chr <- if (is.null(col_v)) rep(NA_character_, n_rows) else vpro_pg_format_utc_text(col_v, cn)
        non_na <- !is.na(chr)
        if (any(non_na)) chr[non_na] <- enc2utf8(chr[non_na])
        raw_cols[[ci]] <- chr
        comp_cols[[ci]] <- chr
        hash_cols[[ci]] <- ifelse(is.na(chr), "null", paste0("text:", chr))
      } else if (pg_t %in% c("BIGINT", "SMALLINT")) {
        num <- if (is.null(col_v)) {
          rep(NA_real_, n_rows)
        } else if (is.logical(col_v)) {
          ifelse(is.na(col_v), NA_real_, ifelse(col_v, -1.0, 0.0))
        } else if (is.character(col_v)) {
          s <- trimws(col_v)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(col_v))
        }
        num[!is.finite(num)] <- NA_real_
        rnd <- round(num)
        raw_cols[[ci]] <- rnd
        int_str <- ifelse(is.na(rnd), NA_character_, sprintf("%.0f", rnd))
        comp_cols[[ci]] <- int_str
        hash_cols[[ci]] <- ifelse(is.na(int_str), "null", paste0("int:", int_str))
      } else if (identical(pg_t, "DOUBLE PRECISION")) {
        num <- if (is.null(col_v)) {
          rep(NA_real_, n_rows)
        } else if (is.character(col_v)) {
          s <- trimws(col_v)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(col_v))
        }
        num[!is.finite(num)] <- NA_real_
        raw_cols[[ci]] <- num
        comp_cols[[ci]] <- vpro_format_float15(num)
        hex_b <- vpro_float64_hex_bits(num)
        hash_cols[[ci]] <- ifelse(is.na(num), "null", paste0("float:", hex_b))
      } else {
        chr <- if (is.null(col_v)) rep(NA_character_, n_rows) else as.character(col_v)
        raw_cols[[ci]] <- chr
        comp_cols[[ci]] <- chr
        hash_cols[[ci]] <- ifelse(is.na(chr), "null", paste0("text:", chr))
      }
    }

    plot_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
    plot_vec <- comp_cols[[plot_col]]
    valid_p <- which(!is.na(plot_vec) & nzchar(plot_vec))
    if (length(valid_p) == 0L) {
      comp_by_suffix[[suffix]] <- list()
      raw_by_suffix[[suffix]] <- list()
      next
    }

    plots_seen <- c(plots_seen, plot_vec[valid_p])

    # Compute logical base keys vectorized across valid rows
    base_keys <- if (suffix %in% c("Env", "Admin")) {
      rep(suffix, length(valid_p))
    } else if (identical(suffix, "Veg")) {
      spp_v <- ifelse(is.na(comp_cols[["Species"]][valid_p]), "", comp_cols[["Species"]][valid_p])
      lyr_raw <- comp_cols[["Layer"]][valid_p]
      lyr_v <- ifelse(is.na(lyr_raw), "", trimws(lyr_raw))
      ifelse(nzchar(lyr_v), paste0("Species=", spp_v, "|Layer=", lyr_v), paste0("Species=", spp_v))
    } else if (suffix %in% c("Humus", "Mineral")) {
      hz_v <- ifelse(is.na(comp_cols[["Horizon"]][valid_p]), "", comp_cols[["Horizon"]][valid_p])
      paste0("Horizon=", hz_v)
    } else if (identical(suffix, "Other")) {
      dn_v <- ifelse(is.na(comp_cols[["DataName"]][valid_p]), "", comp_cols[["DataName"]][valid_p])
      paste0("DataName=", dn_v)
    } else {
      rep(suffix, length(valid_p))
    }

    sig_cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))
    sig_parts <- vector("list", length(sig_cols) + 1L)
    sig_parts[[1L]] <- base_keys
    for (si in seq_along(sig_cols)) {
      cv <- comp_cols[[sig_cols[[si]]]][valid_p]
      sig_parts[[si + 1L]] <- ifelse(is.na(cv), "<NULL>", cv)
    }
    row_sigs <- do.call(paste, c(sig_parts, list(sep = "|")))

    comp_df <- as.data.frame(comp_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]
    raw_df <- as.data.frame(raw_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]
    hash_df <- as.data.frame(hash_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]

    p_valid <- plot_vec[valid_p]
    idx_by_plot <- split(seq_along(valid_p), p_valid)

    suffix_comp_map <- list()
    suffix_raw_map <- list()

    for (p_nm in names(idx_by_plot)) {
      ix <- idx_by_plot[[p_nm]]
      if (length(ix) > 1L) {
        ix <- ix[order(row_sigs[ix], method = "radix")]
      }
      bks <- base_keys[ix]
      rks <- character(length(ix))
      seen_bk <- new.env(hash = TRUE, parent = emptyenv())
      for (k in seq_along(ix)) {
        bk <- bks[[k]]
        cnt <- if (exists(bk, envir = seen_bk, inherits = FALSE)) {
          get(bk, envir = seen_bk, inherits = FALSE) + 1L
        } else {
          1L
        }
        assign(bk, cnt, envir = seen_bk)
        rks[[k]] <- if (cnt > 1L) paste0(bk, "#", cnt) else bk
      }

      p_comp <- comp_df[ix, , drop = FALSE]
      rownames(p_comp) <- rks
      p_raw <- raw_df[ix, , drop = FALSE]
      rownames(p_raw) <- rks
      p_hash <- hash_df[ix, , drop = FALSE]
      rownames(p_hash) <- rks
      attr(p_raw, "hash_df") <- p_hash

      suffix_comp_map[[p_nm]] <- p_comp
      suffix_raw_map[[p_nm]] <- p_raw
    }

    comp_by_suffix[[suffix]] <- suffix_comp_map
    raw_by_suffix[[suffix]] <- suffix_raw_map
  }

  list(
    label = as.character(label),
    plots = sort(unique(plots_seen), method = "radix"),
    comp = comp_by_suffix,
    raw = raw_by_suffix
  )
}

vpro_frame_digest_tokens <- function(tokens) {
  u <- enc2utf8(as.character(tokens))
  paste0(nchar(u, type = "bytes"), ":", u, "|", collapse = "")
}

vpro_hash_cloud_snapshot <- function(snap) {
  if (is.null(snap)) {
    return("")
  }
  chunks <- character(1L + length(.vpro_merge_table_suffixes))
  chunks[[1L]] <- vpro_frame_digest_tokens(snap$label)

  for (si in seq_along(.vpro_merge_table_suffixes)) {
    suffix <- .vpro_merge_table_suffixes[[si]]
    spec <- vpro_pg_vp08_specs(suffix)
    s_raw <- snap$raw[[suffix]]
    p_names <- if (length(s_raw) > 0L) sort(names(s_raw), method = "radix") else character(0L)

    if (length(p_names) == 0L) {
      chunks[[1L + si]] <- vpro_frame_digest_tokens(c(suffix, "0"))
      next
    }

    row_blocks <- vector("list", length(p_names))
    total_rows <- 0L
    for (pi in seq_along(p_names)) {
      p_nm <- p_names[[pi]]
      p_hash_df <- attr(s_raw[[p_nm]], "hash_df")
      rks <- rownames(p_hash_df)
      ord <- order(rks, method = "radix")
      rks <- rks[ord]
      p_hash_df <- p_hash_df[ord, spec$name, drop = FALSE]
      total_rows <- total_rows + length(rks)

      col_framed <- lapply(spec$name, function(cn) {
        u <- enc2utf8(p_hash_df[[cn]])
        paste0(nchar(u, type = "bytes"), ":", u, "|")
      })
      rk_u <- enc2utf8(paste0(p_nm, "::", rks))
      rk_framed <- paste0(nchar(rk_u, type = "bytes"), ":", rk_u, "|")
      row_blocks[[pi]] <- paste0(
        rk_framed,
        do.call(paste0, col_framed),
        collapse = ""
      )
    }

    chunks[[1L + si]] <- paste0(
      vpro_frame_digest_tokens(c(suffix, as.character(total_rows))),
      paste0(unlist(row_blocks, use.names = FALSE), collapse = "")
    )
  }

  vpro_sha256_utf8(paste0(chunks, collapse = ""))[[1L]]
}

vpro_summarize_cloud_row <- function(spec, comp_row_vec) {
  cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))
  vals <- comp_row_vec[cols]
  keep <- !is.na(vals) & nzchar(vals) & !(cols == "Flag" & vals == "0")
  if (!any(keep)) {
    return("")
  }
  paste(paste0(cols[keep], "=", vals[keep]), collapse = ", ")
}

vpro_same_nullable_str <- function(a, b) {
  if (is.na(a) || is.na(b)) {
    return(is.na(a) && is.na(b))
  }
  identical(as.character(a), as.character(b))
}

vpro_compute_3way_diff <- function(
  submission_id,
  source_project,
  src_tables,
  tgt_tables,
  base_tables = NULL,
  base_db = "",
  base_project = ""
) {
  .vpro_register_sync_s3()
  sub_id <- as.character(submission_id[[1L]])
  src_proj <- as.character(source_project[[1L]])

  src_snap <- vpro_build_cloud_snapshot(src_proj, src_tables)
  tgt_snap <- vpro_build_cloud_snapshot("BECMaster", tgt_tables)
  base_snap <- if (!is.null(base_tables)) {
    bp_lbl <- if (!is.null(base_project) && nzchar(base_project)) as.character(base_project) else "Base"
    vpro_build_cloud_snapshot(bp_lbl, base_tables)
  } else {
    NULL
  }

  has_base <- !is.null(base_snap)
  src_hash <- vpro_hash_cloud_snapshot(src_snap)
  tgt_hash <- vpro_hash_cloud_snapshot(tgt_snap)
  base_hash <- vpro_hash_cloud_snapshot(base_snap)
  preview_digest <- vpro_sha256_utf8(
    vpro_frame_digest_tokens(c(sub_id, src_hash, tgt_hash, base_hash))
  )[[1L]]

  overlap_plots <- sort(
    unique(c(
      src_snap$plots,
      tgt_snap$plots,
      if (has_base) base_snap$plots else character(0L)
    )),
    method = "radix"
  )

  src_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  for (p in src_snap$plots) assign(p, TRUE, envir = src_plot_env)
  tgt_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  for (p in tgt_snap$plots) assign(p, TRUE, envir = tgt_plot_env)
  base_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  if (has_base) {
    for (p in base_snap$plots) assign(p, TRUE, envir = base_plot_env)
  }

  spec_cache <- stats::setNames(
    lapply(.vpro_merge_table_suffixes, vpro_pg_vp08_specs),
    .vpro_merge_table_suffixes
  )

  lookup_base <- function(suffix, plot, rk, field) {
    if (!has_base || !exists(plot, envir = base_plot_env, inherits = FALSE)) {
      return(list(val = NA_character_, in_base = FALSE))
    }
    b_df <- base_snap$comp[[suffix]][[plot]]
    if (is.null(b_df) || !(rk %in% rownames(b_df))) {
      return(list(val = NA_character_, in_base = TRUE))
    }
    row_vec <- stats::setNames(as.character(b_df[rk, , drop = TRUE]), names(b_df))
    if (identical(field, "*")) {
      return(list(val = vpro_summarize_cloud_row(spec_cache[[suffix]], row_vec), in_base = TRUE))
    }
    list(val = row_vec[[field]], in_base = TRUE)
  }

  added_count <- 0L
  identical_count <- 0L
  fast_forward_count <- 0L
  conflict_count <- 0L
  target_only_count <- 0L

  plot_cats <- character(length(overlap_plots))
  plot_n_items <- integer(length(overlap_plots))

  it_cid <- character(0L)
  it_plot <- character(0L)
  it_tbl <- character(0L)
  it_key <- character(0L)
  it_fld <- character(0L)
  it_base <- character(0L)
  it_src <- character(0L)
  it_tgt <- character(0L)
  it_kind <- character(0L)
  it_def <- character(0L)
  it_prot <- logical(0L)

  push_item <- function(cid, pl, tbl, key, fld, bv, sv, tv, knd, def_r, prot) {
    idx <- length(it_cid) + 1L
    it_cid[[idx]] <<- cid
    it_plot[[idx]] <<- pl
    it_tbl[[idx]] <<- tbl
    it_key[[idx]] <<- key
    it_fld[[idx]] <<- fld
    it_base[[idx]] <<- if (is.null(bv) || length(bv) == 0L) NA_character_ else as.character(bv[[1L]])
    it_src[[idx]] <<- if (is.null(sv) || length(sv) == 0L) NA_character_ else as.character(sv[[1L]])
    it_tgt[[idx]] <<- if (is.null(tv) || length(tv) == 0L) NA_character_ else as.character(tv[[1L]])
    it_kind[[idx]] <<- knd
    it_def[[idx]] <<- def_r
    it_prot[[idx]] <<- isTRUE(prot)
  }

  for (pi in seq_along(overlap_plots)) {
    plot <- overlap_plots[[pi]]
    in_src <- exists(plot, envir = src_plot_env, inherits = FALSE)
    in_tgt <- exists(plot, envir = tgt_plot_env, inherits = FALSE)

    if (in_src && !in_tgt) {
      if (has_base && exists(plot, envir = base_plot_env, inherits = FALSE)) {
        cid <- paste0(plot, "::Env::Plot")
        push_item(
          cid, plot, "Env", "Plot", "PlotNumber",
          "Present", "Present", NA_character_,
          "Conflict", "keep_target", FALSE
        )
        conflict_count <- conflict_count + 1L
        plot_cats[[pi]] <- "Conflict"
        plot_n_items[[pi]] <- 1L
      } else {
        added_count <- added_count + 1L
        plot_cats[[pi]] <- "Added"
        plot_n_items[[pi]] <- 0L
      }
      next
    }

    if (!in_src && in_tgt) {
      target_only_count <- target_only_count + 1L
      plot_cats[[pi]] <- "TargetOnly"
      plot_n_items[[pi]] <- 0L
      next
    }

    if (!in_src && !in_tgt) {
      plot_cats[[pi]] <- "Identical"
      plot_n_items[[pi]] <- 0L
      next
    }

    before_n <- length(it_cid)
    has_real_conflict <- FALSE
    has_fast_forward <- FALSE

    for (suffix in .vpro_merge_table_suffixes) {
      spec <- spec_cache[[suffix]]
      s_df <- src_snap$comp[[suffix]][[plot]]
      t_df <- tgt_snap$comp[[suffix]][[plot]]
      b_df <- if (has_base) base_snap$comp[[suffix]][[plot]] else NULL
      s_keys <- if (!is.null(s_df)) rownames(s_df) else character(0L)
      t_keys <- if (!is.null(t_df)) rownames(t_df) else character(0L)
      b_keys <- if (!is.null(b_df)) rownames(b_df) else character(0L)
      if (length(s_keys) == 0L && length(t_keys) == 0L) {
        next
      }
      rks <- sort(unique(c(s_keys, t_keys)), method = "radix")

      is_ambiguous <- function(rk) {
        if (suffix %in% c("Env", "Admin")) return(FALSE)
        base_k <- sub("#.*$", "", rk)
        k2 <- paste0(base_k, "#2")
        grepl("#", rk, fixed = TRUE) || (k2 %in% s_keys) || (k2 %in% t_keys) || (k2 %in% b_keys)
      }

      diff_cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))

      for (rk in rks) {
        has_s <- rk %in% s_keys
        has_t <- rk %in% t_keys
        ambig <- is_ambiguous(rk)

        if (has_s && !has_t) {
          s_vec <- stats::setNames(as.character(s_df[rk, , drop = TRUE]), names(s_df))
          s_sum <- vpro_summarize_cloud_row(spec, s_vec)
          lb <- lookup_base(suffix, plot, rk, "*")
          if (!ambig && has_base && lb$in_base && is.na(lb$val)) {
            knd <- "FastForward"
            def_r <- "accept_source"
            has_fast_forward <- TRUE
          } else {
            knd <- "Conflict"
            def_r <- "keep_target"
            has_real_conflict <- TRUE
          }
          push_item(
            paste0(plot, "::", suffix, "::", rk),
            plot, suffix, rk, "*",
            lb$val, s_sum, NA_character_,
            knd, def_r, FALSE
          )
          next
        }

        if (!has_s && has_t) {
          t_vec <- stats::setNames(as.character(t_df[rk, , drop = TRUE]), names(t_df))
          t_sum <- vpro_summarize_cloud_row(spec, t_vec)
          lb <- lookup_base(suffix, plot, rk, "*")
          if (!ambig && has_base && lb$in_base && vpro_same_nullable_str(t_sum, lb$val)) {
            knd <- "FastForward"
            def_r <- "accept_source"
            has_fast_forward <- TRUE
          } else {
            knd <- "Conflict"
            def_r <- "keep_target"
            has_real_conflict <- TRUE
          }
          push_item(
            paste0(plot, "::", suffix, "::", rk),
            plot, suffix, rk, "*",
            lb$val, NA_character_, t_sum,
            knd, def_r, FALSE
          )
          next
        }

        s_vec <- stats::setNames(as.character(s_df[rk, , drop = TRUE]), names(s_df))
        t_vec <- stats::setNames(as.character(t_df[rk, , drop = TRUE]), names(t_df))

        for (col_nm in diff_cols) {
          sv <- s_vec[[col_nm]]
          tv <- t_vec[[col_nm]]
          if (vpro_same_nullable_str(sv, tv)) {
            next
          }
          fld_key <- if (suffix %in% c("Env", "Admin")) col_nm else paste0(rk, ".", col_nm)
          lb <- lookup_base(suffix, plot, rk, col_nm)
          is_prot <- identical(suffix, "Admin") && (col_nm %in% .vpro_custodian_protected_admin_fields)

          knd <- "Conflict"
          def_r <- "keep_target"
          if (!is_prot && !ambig && has_base && lb$in_base) {
            if (vpro_same_nullable_str(tv, lb$val) && !vpro_same_nullable_str(sv, lb$val)) {
              knd <- "FastForward"
              def_r <- "accept_source"
              has_fast_forward <- TRUE
            } else if (vpro_same_nullable_str(sv, lb$val) && !vpro_same_nullable_str(tv, lb$val)) {
              knd <- "TargetModifiedOnly"
              def_r <- "keep_target"
            } else {
              has_real_conflict <- TRUE
            }
          } else {
            has_real_conflict <- TRUE
          }

          push_item(
            paste0(plot, "::", suffix, "::", fld_key),
            plot, suffix, fld_key, col_nm,
            lb$val, sv, tv,
            knd, def_r, is_prot
          )
        }
      }
    }

    n_pl_items <- length(it_cid) - before_n
    plot_n_items[[pi]] <- n_pl_items

    if (n_pl_items == 0L) {
      identical_count <- identical_count + 1L
      plot_cats[[pi]] <- "Identical"
    } else if (!has_real_conflict && has_fast_forward) {
      fast_forward_count <- fast_forward_count + 1L
      plot_cats[[pi]] <- "FastForward"
    } else if (!has_real_conflict) {
      target_only_count <- target_only_count + 1L
      plot_cats[[pi]] <- "TargetOnly"
    } else {
      conflict_count <- conflict_count + 1L
      plot_cats[[pi]] <- "Conflict"
    }
  }

  plots_tbl <- tibble::tibble(
    PlotNumber = overlap_plots,
    category = plot_cats,
    n_items = plot_n_items
  )

  items_tbl <- tibble::tibble(
    conflict_id = it_cid,
    PlotNumber = it_plot,
    table = it_tbl,
    key = it_key,
    field = it_fld,
    base_val = it_base,
    source_val = it_src,
    target_val = it_tgt,
    kind = it_kind,
    default_resolution = it_def,
    custodian_protected = it_prot
  )

  conflicts_tbl <- items_tbl[items_tbl$kind == "Conflict", , drop = FALSE]
  protected_tbl <- items_tbl[items_tbl$custodian_protected, , drop = FALSE]

  out <- structure(
    list(
      submission_id = sub_id,
      source_project = src_proj,
      target_project = "BECMaster",
      base_db = if (is.null(base_db) || is.na(base_db)) "" else as.character(base_db),
      base_project = if (is.null(base_project) || is.na(base_project)) "" else as.character(base_project),
      preview_digest = preview_digest,
      added_count = as.integer(added_count),
      identical_count = as.integer(identical_count),
      fast_forward_count = as.integer(fast_forward_count),
      conflict_count = as.integer(conflict_count),
      target_only_count = as.integer(target_only_count),
      plots = plots_tbl,
      items = items_tbl,
      conflicts = conflicts_tbl,
      custodian_protected_diffs = protected_tbl
    ),
    class = "vpro_merge_preview"
  )
  attr(out, "snapshots") <- list(src = src_snap, tgt = tgt_snap, base = base_snap)
  out
}

vpro_resolve_sqlite_base_db <- function(base_db, base_project = NULL) {
  if (is.null(base_db)) {
    return(NULL)
  }
  if (inherits(base_db, "vpro_workspace")) {
    req_p <- vpro_validate_optional_scalar_chr(base_project, "base_project")
    proj <- if (!is.na(req_p)) req_p else base_db$project
    insp <- vpro_project_inspect(base_db$project_path, proj)
    if (!isTRUE(insp$compatible)) {
      cli::cli_abort(
        "Base workspace project {.val {proj}} in {.path {base_db$project_path}} is not a compatible {.code VP08} project."
      )
    }
    return(list(path = insp$path, project = proj))
  }
  if (!is.character(base_db) || length(base_db) != 1L || is.na(base_db)) {
    cli::cli_abort(
      "{.arg base_db} must be {.code NULL}, a {.cls vpro_workspace}, or a SQLite {.file .db} file path."
    )
  }
  trimmed <- trimws(base_db)
  if (!nzchar(trimmed)) {
    return(NULL)
  }
  resolved <- vpro_abs_path(trimmed)
  if (!file.exists(resolved) || dir.exists(resolved)) {
    cli::cli_abort("Base SQLite database does not exist: {.path {resolved}}.")
  }

  disc <- vpro_project_discover(resolved)
  compat <- disc[disc$complete & disc$version == "VP08", , drop = FALSE]
  req_p <- vpro_validate_optional_scalar_chr(base_project, "base_project")
  if (!is.na(req_p)) {
    hit <- compat$project[compat$project == req_p]
    if (length(hit) != 1L) {
      cli::cli_abort(
        "Compatible {.code VP08} project {.val {req_p}} was not found in {.path {resolved}}."
      )
    }
    return(list(path = normalizePath(resolved, winslash = "/", mustWork = TRUE), project = hit[[1L]]))
  }
  if (nrow(compat) == 0L) {
    cli::cli_abort("No compatible {.code VP08} project found in base SQLite file {.path {resolved}}.")
  }
  if (nrow(compat) > 1L) {
    cli::cli_abort(
      "Multiple compatible {.code VP08} projects ({.val {compat$project}}) found in {.path {resolved}}; specify {.arg base_project}."
    )
  }
  list(path = normalizePath(resolved, winslash = "/", mustWork = TRUE), project = compat$project[[1L]])
}

vpro_load_sqlite_base_tables <- function(base_info) {
  if (is.null(base_info)) {
    return(NULL)
  }
  dbc <- vpro_sqlite_ro(base_info$path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  out <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  for (suffix in .vpro_merge_table_suffixes) {
    spec <- vpro_pg_vp08_specs(suffix)
    tbl_nm <- paste0(base_info$project, "_", suffix)
    key_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
    sql <- paste0(
      "SELECT ", vpro_sqlite_select_vp08_sql(spec),
      " FROM ", vpro_quote_ident(tbl_nm),
      " WHERE typeof(", vpro_quote_ident(key_col), ") = 'text'"
    )
    out[[suffix]] <- DBI::dbGetQuery(dbc, sql)
  }
  out
}

vpro_build_pg_merge_preview_on_conn <- function(conn, sub_id, base_info = NULL, preloaded_base_tables = NULL) {
  hdr <- DBI::dbGetQuery(
    conn,
    "SELECT project_name, source_db_sha256 FROM staging.submissions WHERE submission_id = $1::uuid",
    params = list(sub_id)
  )
  if (nrow(hdr) == 0L) {
    cli::cli_abort("Staging submission {.val {sub_id}} was not found.")
  }
  proj_name <- as.character(hdr$project_name[[1L]])
  src_sha <- as.character(hdr$source_db_sha256[[1L]])

  pg_tbl_map <- c(
    Env = "env", Admin = "admin", Veg = "veg",
    Humus = "humus", Mineral = "mineral", Other = "other"
  )

  src_tables <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  src_plots <- character(0L)
  for (suffix in .vpro_merge_table_suffixes) {
    spec <- vpro_pg_vp08_specs(suffix)
    col_csv <- paste(vapply(spec$name, function(cn) {
      q <- vpro_quote_ident(cn)
      if (cn %in% c("PlotNumber", "Plot")) paste0("CAST(", q, " AS TEXT) AS ", q) else q
    }, character(1L)), collapse = ", ")
    df_s <- DBI::dbGetQuery(
      conn,
      paste0("SELECT ", col_csv, " FROM staging.", vpro_quote_ident(pg_tbl_map[[suffix]]), " WHERE submission_id = $1::uuid"),
      params = list(sub_id)
    )
    src_tables[[suffix]] <- df_s
    p_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
    if (nrow(df_s) > 0L && (p_col %in% names(df_s))) {
      pv <- as.character(df_s[[p_col]])
      src_plots <- c(src_plots, pv[!is.na(pv) & nzchar(pv)])
    }
  }

  base_tables <- if (!is.null(preloaded_base_tables)) {
    preloaded_base_tables
  } else {
    vpro_load_sqlite_base_tables(base_info)
  }

  base_plots <- character(0L)
  if (!is.null(base_tables) && !is.null(base_tables$Env) && nrow(base_tables$Env) > 0L) {
    bp <- as.character(base_tables$Env$PlotNumber)
    base_plots <- bp[!is.na(bp) & nzchar(bp)]
  }

  query_plots <- sort(unique(c(src_plots, base_plots)), method = "radix")

  if (!is.null(base_tables)) {
    for (suffix in .vpro_merge_table_suffixes) {
      b_df <- base_tables[[suffix]]
      if (!is.null(b_df) && nrow(b_df) > 0L) {
        p_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
        base_tables[[suffix]] <- b_df[as.character(b_df[[p_col]]) %in% query_plots, , drop = FALSE]
      }
    }
  }

  tgt_tables <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  if (length(query_plots) > 0L) {
    pg_arr <- vpro_pg_text_array(query_plots)
    for (suffix in .vpro_merge_table_suffixes) {
      spec <- vpro_pg_vp08_specs(suffix)
      p_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
      col_csv <- paste(vapply(spec$name, function(cn) {
        q <- vpro_quote_ident(cn)
        if (cn %in% c("PlotNumber", "Plot")) paste0("CAST(", q, " AS TEXT) AS ", q) else q
      }, character(1L)), collapse = ", ")
      tgt_tables[[suffix]] <- DBI::dbGetQuery(
        conn,
        paste0(
          "SELECT ", col_csv,
          " FROM becmaster.", vpro_quote_ident(pg_tbl_map[[suffix]]),
          " WHERE ", vpro_quote_ident(p_col), " = ANY($1::text[])"
        ),
        params = list(pg_arr)
      )
    }
  } else {
    for (suffix in .vpro_merge_table_suffixes) {
      spec <- vpro_pg_vp08_specs(suffix)
      tgt_tables[[suffix]] <- as.data.frame(
        stats::setNames(replicate(nrow(spec), logical(0L), simplify = FALSE), spec$name),
        stringsAsFactors = FALSE
      )
    }
  }

  preview <- vpro_compute_3way_diff(
    submission_id = sub_id,
    source_project = proj_name,
    src_tables = src_tables,
    tgt_tables = tgt_tables,
    base_tables = base_tables,
    base_db = if (!is.null(base_info)) base_info$path else "",
    base_project = if (!is.null(base_info)) base_info$project else ""
  )

  list(preview = preview, source_sha256 = src_sha)
}

# Public Custodian 3-Way Diff, Merge & Reject API ------------------------------

#' Compute a custodian 3-way merge preview between `staging` and `BECMaster`
#'
#' Compares all six plot-keyed `VP08` tables (`Env`, `Admin`, `Veg`, `Humus`,
#' `Mineral`, `Other`) in `staging.*` for `submission_id` against overlapping
#' plots in `becmaster.*` (and an optional common ancestor SQLite snapshot
#' `base_db`), classifying plots and field/row items into `Added`, `Identical`,
#' `FastForward`, `Conflict`, `TargetOnly`, and `TargetModifiedOnly`, flagging
#' custodian-protected `Admin` columns (`BECSiteUnit`, `BEC_Use`, `GIS_BGC`),
#' and computing a deterministic SHA-256 `preview_digest` for optimistic
#' concurrency locking in [vpro_staging_merge()].
#'
#' @param con A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Staging submission UUID string.
#' @param base_db Optional common ancestor `VP08` SQLite `.db` path or
#'   `vpro_workspace` handle for true 3-way diffing (`NULL` runs a 2-way diff).
#' @param base_project Optional project prefix inside `base_db` when `base_db`
#'   contains multiple `VP08` projects.
#' @return An S3 object of class `vpro_merge_preview` with `print()` and
#'   `as_tibble()` methods.
#' @export
vpro_staging_diff <- function(
  con,
  submission_id,
  base_db = NULL,
  base_project = NULL
) {
  vpro_assert_pg_conn(con, require_custodian = TRUE)
  .vpro_register_sync_s3()
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")
  base_info <- vpro_resolve_sqlite_base_db(base_db, base_project)
  base_tables <- vpro_load_sqlite_base_tables(base_info)

  res <- vpro_pg_exec_safe(
    function() {
      vpro_build_pg_merge_preview_on_conn(
        conn = con$conn,
        sub_id = sub_id,
        base_info = base_info,
        preloaded_base_tables = base_tables
      )
    },
    action = "compute staging-to-BECMaster 3-way merge preview"
  )
  res$preview
}

#' Print a `vpro_merge_preview` custodian diff summary
#'
#' @param x A `vpro_merge_preview` object returned by [vpro_staging_diff()].
#' @param ... Unused additional arguments.
#' @return `x`, invisibly.
#' @export
print.vpro_merge_preview <- function(x, ...) {
  base_lbl <- if (nzchar(x$base_project)) {
    paste0("3-way (base: ", x$base_project, ")")
  } else {
    "2-way (no base snapshot)"
  }
  n_prot <- nrow(x$custodian_protected_diffs)
  cli::cli_h3("vpro_merge_preview ({x$source_project} -> {x$target_project}, {base_lbl})")
  cli::cli_bullets(c(
    "*" = "Submission: {x$submission_id}",
    "*" = "Plots: Added={x$added_count}, Identical={x$identical_count}, FastForward={x$fast_forward_count}, Conflict={x$conflict_count}, TargetOnly={x$target_only_count}",
    "*" = "Diff items: {nrow(x$items)} total ({nrow(x$conflicts)} conflicts, {n_prot} custodian-protected)",
    "*" = "Preview digest: {x$preview_digest}"
  ))
  invisible(x)
}

#' Coerce a `vpro_merge_preview` object to a tibble
#'
#' @param x A `vpro_merge_preview` object returned by [vpro_staging_diff()].
#' @param what Component tibble to extract: `"items"` (default), `"plots"`,
#'   `"conflicts"`, or `"custodian_protected"`.
#' @param ... Unused additional arguments.
#' @return A tibble of diff items or plot summaries.
#' @export
as_tibble.vpro_merge_preview <- function(
  x,
  what = c("items", "plots", "conflicts", "custodian_protected"),
  ...
) {
  what <- match.arg(what)
  switch(
    what,
    items = x$items,
    plots = x$plots,
    conflicts = x$conflicts,
    custodian_protected = x$custodian_protected_diffs
  )
}

vpro_validate_merge_cell_value <- function(suffix, col_spec_row, raw_val, plot = "") {
  if (is.null(raw_val) || length(raw_val) == 0L || is.na(raw_val[[1L]])) {
    return(invisible(NULL))
  }
  cn <- col_spec_row$name[[1L]]
  pg_t <- col_spec_row$pg_type[[1L]]
  is_cov <- isTRUE(col_spec_row$is_cover[[1L]])
  u16_max <- col_spec_row$utf16_max[[1L]]

  if (identical(pg_t, "TEXT")) {
    s <- as.character(raw_val[[1L]])
    u16 <- vpro_utf16_len(s)
    if (is.na(u16)) {
      cli::cli_abort("Plot {.val {plot}} {suffix}.{cn} contains malformed UTF-8 or unpaired surrogates.")
    }
    if (u16_max > 0L && u16 > u16_max) {
      cli::cli_abort(
        "Plot {.val {plot}} {suffix}.{cn} exceeds {u16_max} UTF-16 code units (got {u16})."
      )
    }
  } else if (is_cov) {
    v <- suppressWarnings(as.double(raw_val[[1L]]))
    narrowed <- suppressWarnings(vpro_narrow_float32(v))
    if (is.na(v) || !is.finite(v) || v < 0 || is.na(narrowed) || narrowed < 0 || narrowed >= 100) {
      cli::cli_abort(
        "Plot {.val {plot}} {suffix}.{cn} cover={raw_val[[1L]]} must narrow to >= 0 and < 100 in IEEE-754 float32."
      )
    }
  }
  invisible(NULL)
}

vpro_validate_lmh25_merge_horizon <- function(suffix, horizon, upper_depth, lower_depth, plot = "") {
  if (!(suffix %in% c("Humus", "Mineral"))) {
    return(invisible(NULL))
  }
  if (is.null(upper_depth) || is.null(lower_depth) ||
      length(upper_depth) == 0L || length(lower_depth) == 0L ||
      is.na(upper_depth[[1L]]) || is.na(lower_depth[[1L]])) {
    return(invisible(NULL))
  }
  u <- suppressWarnings(as.double(upper_depth[[1L]]))
  l <- suppressWarnings(as.double(lower_depth[[1L]]))
  if (!is.finite(u) || !is.finite(l)) {
    cli::cli_abort("Plot {.val {plot}} {suffix} depth contains non-finite values.")
  }
  hz <- toupper(trimws(ifelse(is.na(horizon), "", as.character(horizon))))
  if (identical(suffix, "Humus")) {
    if (grepl("^[0-9]*(OF|OM|OH)", hz)) {
      if (u < 0 || l < 0 || u >= l) {
        cli::cli_abort(
          "Plot {.val {plot}} LMH25 wetland Humus horizon {.val {horizon}} requires 0 <= UpperDepth < LowerDepth (got {u}..{l})."
        )
      }
    } else if (grepl("^[0-9]*(L|F|H)", hz)) {
      if (u < 0 || l < 0 || u <= l) {
        cli::cli_abort(
          "Plot {.val {plot}} LMH25 upland Humus horizon {.val {horizon}} requires UpperDepth > LowerDepth >= 0 (got {u}..{l})."
        )
      }
    }
  } else if (identical(suffix, "Mineral")) {
    if (u < 0 || l < 0 || u >= l) {
      cli::cli_abort(
        "Plot {.val {plot}} LMH25 Mineral horizon {.val {horizon}} requires 0 <= UpperDepth < LowerDepth (got {u}..{l})."
      )
    }
  }
  invisible(NULL)
}

vpro_pg_param_for_spec <- function(col_spec_row, raw_val) {
  pg_t <- col_spec_row$pg_type[[1L]]
  is_b <- isTRUE(col_spec_row$is_bool[[1L]])
  is_cov <- isTRUE(col_spec_row$is_cover[[1L]])

  if (is.null(raw_val) || length(raw_val) == 0L || is.na(raw_val[[1L]])) {
    if (identical(pg_t, "TEXT")) return(NA_character_)
    if (identical(pg_t, "DOUBLE PRECISION")) return(NA_real_)
    return(NA_integer_)
  }
  if (is_b) {
    return(vpro_logical_to_access(raw_val[[1L]]))
  }
  if (identical(pg_t, "TEXT")) {
    return(enc2utf8(as.character(raw_val[[1L]])))
  }
  if (identical(pg_t, "SMALLINT")) {
    return(as.integer(round(as.double(raw_val[[1L]]))))
  }
  if (identical(pg_t, "BIGINT")) {
    v_num <- round(as.double(raw_val[[1L]]))
    if (abs(v_num) <= .Machine$integer.max) {
      return(as.integer(v_num))
    }
    return(sprintf("%.0f", v_num))
  }
  if (identical(pg_t, "DOUBLE PRECISION")) {
    v_dbl <- as.double(raw_val[[1L]])
    return(if (is_cov) vpro_narrow_float32(v_dbl) else v_dbl)
  }
  raw_val[[1L]]
}

vpro_allocate_master_child_id <- function(conn, child_table) {
  allowed_child <- c("veg", "humus", "mineral", "other", "metadata")
  if (!(child_table %in% allowed_child)) {
    cli::cli_abort("Unsupported child identity table {.val {child_table}}.")
  }
  q_child <- vpro_quote_ident(child_table)
  wm_df <- DBI::dbGetQuery(
    conn,
    paste0(
      "INSERT INTO becmaster.child_identity_watermark (child_table, max_id) ",
      "VALUES ($1, GREATEST(",
      "  COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0),",
      '  COALESCE((SELECT MAX("ID") FROM becmaster.', q_child, "), 0),",
      "  0",
      ") + 1) ",
      "ON CONFLICT (child_table) DO UPDATE SET ",
      "  max_id = GREATEST(",
      "    becmaster.child_identity_watermark.max_id + 1,",
      "    COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0) + 1,",
      '    COALESCE((SELECT MAX("ID") FROM becmaster.', q_child, "), 0) + 1",
      "  ) ",
      "RETURNING max_id::text AS max_id"
    ),
    params = list(child_table)
  )
  next_id <- as.double(wm_df$max_id[[1L]])

  repeat {
    next_id_str <- sprintf("%.0f", next_id)
    aff <- DBI::dbExecute(
      conn,
      "INSERT INTO becmaster.child_identity (child_table, id) VALUES ($1, $2::bigint) ON CONFLICT (child_table, id) DO NOTHING",
      params = list(child_table, next_id_str)
    )
    if (identical(as.integer(aff), 1L)) {
      DBI::dbExecute(
        conn,
        "UPDATE becmaster.child_identity_watermark SET max_id = GREATEST(max_id, $2::bigint) WHERE child_table = $1",
        params = list(child_table, next_id_str)
      )
      return(next_id)
    }
    next_id <- next_id + 1
  }
}

vpro_reserve_master_child_id <- function(conn, child_table, id_val) {
  id_num <- round(as.double(id_val))
  id_str <- sprintf("%.0f", id_num)
  DBI::dbExecute(
    conn,
    "INSERT INTO becmaster.child_identity (child_table, id) VALUES ($1, $2::bigint) ON CONFLICT (child_table, id) DO NOTHING",
    params = list(child_table, id_str)
  )
  if (id_num > 0) {
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO becmaster.child_identity_watermark (child_table, max_id)",
        "VALUES ($1, $2::bigint)",
        "ON CONFLICT (child_table) DO UPDATE SET",
        "  max_id = GREATEST(becmaster.child_identity_watermark.max_id, EXCLUDED.max_id)"
      ),
      params = list(child_table, id_str)
    )
  }
  invisible(id_num)
}

#' Execute an atomic `SERIALIZABLE` custodian merge from `staging` into `BECMaster`
#'
#' Locks the pending `staging.submissions` record inside a single PostgreSQL
#' `SERIALIZABLE` transaction, re-verifies the 3-way merge preview (enforcing
#' `expected_digest` when supplied), resolves every plot and field/row change
#' using `vpro_wails` custodial precedence (`field_resolutions` ->
#' custodian-protected `keep_target` guard -> `plot_resolutions` ->
#' `FastForward`/`TargetModifiedOnly` item defaults -> `default_resolution`),
#' validates UTF-16 bounds, IEEE-754 `float32 < 100` covers, and `LMH25 (2023)`
#' soil horizon depth signs, allocates non-reused child `ID`s via
#' `becmaster.child_identity_watermark` + `becmaster.child_identity`, appends
#' SHA-256 hash-chained rows to `becmaster.audit` (verifiable via
#' [vpro_master_verify_audit()]), and records provenance in
#' `becmaster.merge_ledger` and `staging.submissions`.
#'
#' @param con A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Pending staging submission UUID string.
#' @param default_resolution Fallback resolution for unresolved `Conflict` items:
#'   `"keep_target"` (default) or `"accept_source"`.
#' @param plot_resolutions Optional named character vector (`PlotNumber ->
#'   "keep_target" | "accept_source"`). Note: custodian-protected `Admin` fields
#'   (`BECSiteUnit`, `BEC_Use`, `GIS_BGC`) still default to `"keep_target"`
#'   unless explicitly listed in `field_resolutions`.
#' @param field_resolutions Optional named character vector (`conflict_id ->
#'   "keep_target" | "accept_source"`).
#' @param expected_digest Optional 64-character SHA-256 `preview_digest` from
#'   [vpro_staging_diff()] for optimistic concurrency verification.
#' @param reviewer_notes Optional custodian review note stored on
#'   `staging.submissions`.
#' @param base_db Optional common ancestor `VP08` SQLite `.db` path or
#'   `vpro_workspace` handle matching [vpro_staging_diff()].
#' @param base_project Optional project prefix inside `base_db`.
#' @param actor Optional custodian actor name recorded in `becmaster.audit` and
#'   `becmaster.merge_ledger` (defaults to PostgreSQL `current_user`).
#' @return A named list with `merge_tx_id`, `submission_id`, `source_project`,
#'   `added_plots`, `updated_plots`, `skipped_plots`, `allocated_child_ids`,
#'   `reserved_deleted_ids`, `audit_rows_written`, `tail_audit_hash`, and
#'   `merged_at`.
#' @export
vpro_staging_merge <- function(
  con,
  submission_id,
  default_resolution = c("keep_target", "accept_source"),
  plot_resolutions = NULL,
  field_resolutions = NULL,
  expected_digest = NULL,
  reviewer_notes = NULL,
  base_db = NULL,
  base_project = NULL,
  actor = NULL
) {
  vpro_assert_pg_conn(con, require_custodian = TRUE)
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")
  default_resolution <- match.arg(default_resolution)
  plot_res <- vpro_validate_merge_resolution_vec(plot_resolutions, "plot_resolutions")
  field_res <- vpro_validate_merge_resolution_vec(field_resolutions, "field_resolutions")
  expected_clean <- vpro_validate_optional_scalar_chr(expected_digest, "expected_digest")
  rev_notes_clean <- vpro_validate_optional_scalar_chr(reviewer_notes, "reviewer_notes")
  actor_clean <- vpro_validate_optional_scalar_chr(actor, "actor")

  base_info <- vpro_resolve_sqlite_base_db(base_db, base_project)
  preloaded_base <- vpro_load_sqlite_base_tables(base_info)

  resolve_choice <- function(item_row) {
    cid <- item_row$conflict_id[[1L]]
    pnum <- item_row$PlotNumber[[1L]]
    if (cid %in% names(field_res)) {
      return(unname(field_res[[cid]]))
    }
    if (isTRUE(item_row$custodian_protected[[1L]])) {
      return("keep_target")
    }
    if (pnum %in% names(plot_res)) {
      return(unname(plot_res[[pnum]]))
    }
    knd <- item_row$kind[[1L]]
    if (knd %in% c("FastForward", "TargetModifiedOnly")) {
      return(item_row$default_resolution[[1L]])
    }
    default_resolution
  }

  pg_tbl_map <- c(
    Env = "env", Admin = "admin", Veg = "veg",
    Humus = "humus", Mineral = "mineral", Other = "other"
  )
  spec_cache <- stats::setNames(
    lapply(c(.vpro_merge_table_suffixes, "Metadata", "Audit"), vpro_pg_vp08_specs),
    c(.vpro_merge_table_suffixes, "Metadata", "Audit")
  )

  vpro_pg_exec_safe(
    function() {
      tx_committed <- FALSE
      vpro_pg_begin_isolated_tx(con$conn, "BEGIN ISOLATION LEVEL SERIALIZABLE", "vpro_staging_merge")
      on.exit({
        if (!tx_committed && isTRUE(tryCatch(DBI::dbIsValid(con$conn), error = function(e) FALSE))) {
          tryCatch(DBI::dbExecute(con$conn, "ROLLBACK"), error = function(e) NULL)
        }
      }, add = TRUE)

      lock_df <- DBI::dbGetQuery(
        con$conn,
        paste(
          "SELECT status, current_user AS db_user, source_db_sha256,",
          "       to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') AS now_edit_str,",
          "       to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS now_iso_str",
          "FROM staging.submissions",
          "WHERE submission_id = $1::uuid",
          "FOR UPDATE"
        ),
        params = list(sub_id)
      )
      if (nrow(lock_df) == 0L) {
        cli::cli_abort("Staging submission {.val {sub_id}} was not found.")
      }
      cur_status <- as.character(lock_df$status[[1L]])
      if (!identical(cur_status, "pending")) {
        cli::cli_abort(
          "Staging submission {.val {sub_id}} has status {.val {cur_status}} (only {.val pending} submissions can be merged)."
        )
      }

      actor_eff <- if (!is.na(actor_clean)) actor_clean else as.character(lock_df$db_user[[1L]])
      src_sha <- as.character(lock_df$source_db_sha256[[1L]])
      now_edit_str <- as.character(lock_df$now_edit_str[[1L]])
      now_iso_str <- as.character(lock_df$now_iso_str[[1L]])

      built <- vpro_build_pg_merge_preview_on_conn(
        conn = con$conn,
        sub_id = sub_id,
        base_info = base_info,
        preloaded_base_tables = preloaded_base
      )
      preview <- built$preview
      snaps <- attr(preview, "snapshots")
      src_snap <- snaps$src
      tgt_snap <- snaps$tgt

      if (!is.na(expected_clean) && !identical(preview$preview_digest, tolower(expected_clean))) {
        cli::cli_abort(
          "Staging or BECMaster plots changed since preview (expected digest {.val {expected_clean}}, got {.val {preview$preview_digest}}); re-run {.fn vpro_staging_diff} before merging."
        )
      }

      merge_tx_id <- vpro_uuid_v4()

      aud_plot <- character(0L)
      aud_tbl <- character(0L)
      aud_fld <- character(0L)
      aud_before <- character(0L)
      aud_after <- character(0L)
      aud_id <- numeric(0L)

      record_audit <- function(plot_s, suffix_s, fld_s, before_v, after_v, child_id = NA_real_) {
        k <- length(aud_plot) + 1L
        aud_plot[[k]] <<- as.character(plot_s)
        aud_tbl[[k]] <<- paste0("_", suffix_s)
        aud_fld[[k]] <<- as.character(fld_s)
        aud_before[[k]] <<- if (is.null(before_v) || length(before_v) == 0L || is.na(before_v[[1L]])) {
          NA_character_
        } else {
          as.character(before_v[[1L]])
        }
        aud_after[[k]] <<- if (is.null(after_v) || length(after_v) == 0L || is.na(after_v[[1L]])) {
          NA_character_
        } else {
          as.character(after_v[[1L]])
        }
        aud_id[[k]] <<- if (is.null(child_id) || length(child_id) == 0L || is.na(child_id[[1L]])) {
          NA_real_
        } else {
          as.double(child_id[[1L]])
        }
      }

      allocated_ids <- numeric(0L)
      reserved_deleted_ids <- numeric(0L)
      added_plots <- 0L
      updated_plots <- 0L
      skipped_plots <- 0L

      insert_parent_row <- function(suffix, plot) {
        spec <- spec_cache[[suffix]]
        key_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
        p_raw_df <- src_snap$raw[[suffix]][[plot]]
        p_comp_df <- src_snap$comp[[suffix]][[plot]]
        if (is.null(p_raw_df) || !(suffix %in% rownames(p_raw_df))) {
          cli::cli_abort("Staging plot {.val {plot}} is missing required {.val {suffix}} row.")
        }
        raw_row <- p_raw_df[suffix, , drop = FALSE]
        comp_row <- p_comp_df[suffix, , drop = FALSE]

        placeholders <- character(nrow(spec))
        params <- vector("list", nrow(spec))
        for (i in seq_len(nrow(spec))) {
          c_row <- spec[i, , drop = FALSE]
          cn <- c_row$name[[1L]]
          placeholders[[i]] <- paste0("$", i, "::", tolower(c_row$pg_type[[1L]]))
          if (identical(cn, key_col)) {
            vpro_validate_merge_cell_value(suffix, c_row, plot, plot = plot)
            params[[i]] <- plot
          } else {
            rv <- raw_row[[cn]][[1L]]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            params[[i]] <- vpro_pg_param_for_spec(c_row, rv)
          }
        }

        col_csv <- paste(vapply(spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        ins_sql <- paste0(
          "INSERT INTO becmaster.", vpro_quote_ident(pg_tbl_map[[suffix]]),
          " (", col_csv, ") VALUES (", paste(placeholders, collapse = ", "), ")"
        )
        DBI::dbExecute(con$conn, ins_sql, params = params)

        record_audit(plot, suffix, key_col, NA_character_, plot, NA_real_)
        for (i in seq_len(nrow(spec))) {
          cn <- spec$name[[i]]
          if (identical(cn, key_col)) next
          cv <- comp_row[[cn]][[1L]]
          if (!is.na(cv)) {
            record_audit(plot, suffix, cn, NA_character_, cv, NA_real_)
          }
        }
      }

      insert_child_row <- function(suffix, plot, rk) {
        spec <- spec_cache[[suffix]]
        pg_tbl <- pg_tbl_map[[suffix]]
        raw_row <- src_snap$raw[[suffix]][[plot]][rk, , drop = FALSE]
        comp_row <- src_snap$comp[[suffix]][[plot]][rk, , drop = FALSE]

        if (suffix %in% c("Humus", "Mineral")) {
          vpro_validate_lmh25_merge_horizon(
            suffix = suffix,
            horizon = comp_row[["Horizon"]][[1L]],
            upper_depth = raw_row[["UpperDepth"]][[1L]],
            lower_depth = raw_row[["LowerDepth"]][[1L]],
            plot = plot
          )
        }

        new_id <- vpro_allocate_master_child_id(con$conn, pg_tbl)
        allocated_ids <<- c(allocated_ids, new_id)

        placeholders <- character(nrow(spec))
        params <- vector("list", nrow(spec))
        for (i in seq_len(nrow(spec))) {
          c_row <- spec[i, , drop = FALSE]
          cn <- c_row$name[[1L]]
          placeholders[[i]] <- paste0("$", i, "::", tolower(c_row$pg_type[[1L]]))
          if (identical(cn, "PlotNumber")) {
            params[[i]] <- plot
          } else if (identical(cn, "ID")) {
            params[[i]] <- vpro_pg_param_for_spec(c_row, new_id)
          } else {
            rv <- raw_row[[cn]][[1L]]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            params[[i]] <- vpro_pg_param_for_spec(c_row, rv)
          }
        }

        col_csv <- paste(vapply(spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        ins_sql <- paste0(
          "INSERT INTO becmaster.", vpro_quote_ident(pg_tbl),
          " (", col_csv, ") VALUES (", paste(placeholders, collapse = ", "), ")"
        )
        DBI::dbExecute(con$conn, ins_sql, params = params)

        for (i in seq_len(nrow(spec))) {
          cn <- spec$name[[i]]
          if (cn %in% c("PlotNumber", "ID")) next
          cv <- comp_row[[cn]][[1L]]
          if (is.na(cv) || (identical(cn, "Flag") && identical(cv, "0"))) next
          record_audit(plot, suffix, cn, NA_character_, cv, new_id)
        }
      }

      insert_whole_plot <- function(plot) {
        u16_p <- vpro_utf16_len(plot)
        if (is.na(u16_p) || u16_p > 7L) {
          cli::cli_abort("PlotNumber {.val {plot}} exceeds 7 UTF-16 code units or contains invalid UTF-8.")
        }
        insert_parent_row("Env", plot)
        insert_parent_row("Admin", plot)
        for (suffix in c("Veg", "Humus", "Mineral", "Other")) {
          c_df <- src_snap$raw[[suffix]][[plot]]
          if (is.null(c_df) || nrow(c_df) == 0L) next
          rks <- sort(rownames(c_df), method = "radix")
          for (rk in rks) {
            insert_child_row(suffix, plot, rk)
          }
        }
      }

      items_by_plot <- if (nrow(preview$items) > 0L) {
        split(preview$items, preview$items$PlotNumber)
      } else {
        list()
      }

      for (pi in seq_len(nrow(preview$plots))) {
        plot <- preview$plots$PlotNumber[[pi]]
        cat_p <- preview$plots$category[[pi]]

        if (cat_p %in% c("Identical", "TargetOnly")) {
          skipped_plots <- skipped_plots + 1L
          next
        }

        if (identical(cat_p, "Added")) {
          if ((plot %in% names(plot_res)) && identical(unname(plot_res[[plot]]), "keep_target")) {
            skipped_plots <- skipped_plots + 1L
            next
          }
          insert_whole_plot(plot)
          added_plots <- added_plots + 1L
          next
        }

        p_items <- items_by_plot[[plot]]
        if (is.null(p_items) || nrow(p_items) == 0L) {
          skipped_plots <- skipped_plots + 1L
          next
        }

        if (nrow(p_items) == 1L && identical(p_items$key[[1L]], "Plot") &&
            !(plot %in% tgt_snap$plots) && (plot %in% src_snap$plots)) {
          if (identical(resolve_choice(p_items[1L, , drop = FALSE]), "accept_source")) {
            insert_whole_plot(plot)
            added_plots <- added_plots + 1L
          } else {
            skipped_plots <- skipped_plots + 1L
          }
          next
        }

        plot_modified <- FALSE
        touched_horizons <- list()

        for (ii in seq_len(nrow(p_items))) {
          item <- p_items[ii, , drop = FALSE]
          if (!identical(resolve_choice(item), "accept_source")) {
            next
          }
          suffix <- item$table[[1L]]
          pg_tbl <- pg_tbl_map[[suffix]]
          spec <- spec_cache[[suffix]]
          fld <- item$field[[1L]]

          if (suffix %in% c("Env", "Admin")) {
            key_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
            if (identical(fld, "*")) {
              if (!is.na(item$source_val[[1L]]) && is.na(item$target_val[[1L]])) {
                insert_parent_row(suffix, plot)
                plot_modified <- TRUE
              }
              next
            }
            c_idx <- match(fld, spec$name)
            if (is.na(c_idx)) {
              cli::cli_abort("Unknown column {suffix}.{fld}.")
            }
            c_row <- spec[c_idx, , drop = FALSE]
            rv <- src_snap$raw[[suffix]][[plot]][suffix, fld, drop = TRUE]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            param_val <- vpro_pg_param_for_spec(c_row, rv)
            upd_sql <- paste0(
              "UPDATE becmaster.", vpro_quote_ident(pg_tbl),
              " SET ", vpro_quote_ident(fld), " = $1::", tolower(c_row$pg_type[[1L]]),
              " WHERE ", vpro_quote_ident(key_col), " = $2"
            )
            aff <- DBI::dbExecute(con$conn, upd_sql, params = list(param_val, plot))
            if (!identical(as.integer(aff), 1L)) {
              cli::cli_abort(
                "Merge update on {suffix}.{fld} for plot {.val {plot}} matched {aff} rows (expected 1)."
              )
            }
            record_audit(plot, suffix, fld, item$target_val[[1L]], item$source_val[[1L]], NA_real_)
            plot_modified <- TRUE
            next
          }

          # Child table row insert / delete / field update
          if (identical(fld, "*")) {
            rk <- item$key[[1L]]
            if (!is.na(item$source_val[[1L]]) && is.na(item$target_val[[1L]])) {
              insert_child_row(suffix, plot, rk)
              plot_modified <- TRUE
            } else if (is.na(item$source_val[[1L]]) && !is.na(item$target_val[[1L]])) {
              t_raw_row <- tgt_snap$raw[[suffix]][[plot]][rk, , drop = FALSE]
              t_comp_row <- tgt_snap$comp[[suffix]][[plot]][rk, , drop = FALSE]
              tgt_id <- t_raw_row[["ID"]][[1L]]
              if (is.na(tgt_id)) {
                cli::cli_abort("Target {suffix} row in plot {.val {plot}} lacks an integer ID.")
              }
              vpro_reserve_master_child_id(con$conn, pg_tbl, tgt_id)
              reserved_deleted_ids <- c(reserved_deleted_ids, as.double(tgt_id))

              del_sql <- paste0(
                "DELETE FROM becmaster.", vpro_quote_ident(pg_tbl),
                ' WHERE "PlotNumber" = $1 AND "ID" = $2::bigint'
              )
              aff <- DBI::dbExecute(con$conn, del_sql, params = list(plot, sprintf("%.0f", tgt_id)))
              if (!identical(as.integer(aff), 1L)) {
                cli::cli_abort(
                  "Child delete on {suffix} (plot {.val {plot}}, ID {sprintf('%.0f', tgt_id)}) matched {aff} rows."
                )
              }
              for (ci in seq_len(nrow(spec))) {
                cn <- spec$name[[ci]]
                if (cn %in% c("PlotNumber", "ID")) next
                old_v <- t_comp_row[[cn]][[1L]]
                if (is.na(old_v) || (identical(cn, "Flag") && identical(old_v, "0"))) next
                record_audit(plot, suffix, cn, old_v, NA_character_, tgt_id)
              }
              plot_modified <- TRUE
            }
            next
          }

          full_key <- item$key[[1L]]
          suffix_dot <- paste0(".", fld)
          if (!endsWith(full_key, suffix_dot) || nchar(full_key) <= nchar(suffix_dot)) {
            cli::cli_abort("Malformed child conflict key {.val {full_key}}.")
          }
          rk <- substr(full_key, 1L, nchar(full_key) - nchar(suffix_dot))

          c_idx <- match(fld, spec$name)
          if (is.na(c_idx)) {
            cli::cli_abort("Unknown child column {suffix}.{fld}.")
          }
          c_row <- spec[c_idx, , drop = FALSE]
          rv <- src_snap$raw[[suffix]][[plot]][rk, fld, drop = TRUE]
          vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
          param_val <- vpro_pg_param_for_spec(c_row, rv)

          tgt_id <- tgt_snap$raw[[suffix]][[plot]][rk, "ID", drop = TRUE]
          if (is.na(tgt_id)) {
            cli::cli_abort("Target {suffix} row in plot {.val {plot}} lacks an integer ID.")
          }

          upd_sql <- paste0(
            "UPDATE becmaster.", vpro_quote_ident(pg_tbl),
            " SET ", vpro_quote_ident(fld), " = $1::", tolower(c_row$pg_type[[1L]]),
            ' WHERE "PlotNumber" = $2 AND "ID" = $3::bigint'
          )
          aff <- DBI::dbExecute(con$conn, upd_sql, params = list(param_val, plot, sprintf("%.0f", tgt_id)))
          if (!identical(as.integer(aff), 1L)) {
            cli::cli_abort(
              "Child update on {suffix}.{fld} (plot {.val {plot}}, ID {sprintf('%.0f', tgt_id)}) matched {aff} rows."
            )
          }
          record_audit(plot, suffix, fld, item$target_val[[1L]], item$source_val[[1L]], tgt_id)

          if (suffix %in% c("Humus", "Mineral")) {
            th_key <- paste0(suffix, "::", plot, "::", sprintf("%.0f", tgt_id))
            touched_horizons[[th_key]] <- list(suffix = suffix, plot = plot, id = tgt_id)
          }
          plot_modified <- TRUE
        }

        if (length(touched_horizons) > 0L) {
          for (th in touched_horizons) {
            hz_df <- DBI::dbGetQuery(
              con$conn,
              paste0(
                'SELECT "Horizon", "UpperDepth", "LowerDepth" FROM becmaster.',
                vpro_quote_ident(pg_tbl_map[[th$suffix]]),
                ' WHERE "PlotNumber" = $1 AND "ID" = $2::bigint'
              ),
              params = list(th$plot, sprintf("%.0f", th$id))
            )
            if (nrow(hz_df) >= 1L) {
              vpro_validate_lmh25_merge_horizon(
                suffix = th$suffix,
                horizon = hz_df$Horizon[[1L]],
                upper_depth = hz_df$UpperDepth[[1L]],
                lower_depth = hz_df$LowerDepth[[1L]],
                plot = th$plot
              )
            }
          }
        }

        if (plot_modified) {
          updated_plots <- updated_plots + 1L
        } else {
          skipped_plots <- skipped_plots + 1L
        }
      }

      # Insert genuinely new ProjectID metadata rows into becmaster.metadata
      if (added_plots > 0L || updated_plots > 0L) {
        meta_spec <- spec_cache$Metadata
        meta_csv <- paste(vapply(meta_spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        new_meta <- DBI::dbGetQuery(
          con$conn,
          paste0(
            "SELECT ", meta_csv, " FROM staging.metadata AS s ",
            "WHERE s.submission_id = $1::uuid ",
            '  AND s."ProjectID" IS NOT NULL AND s."ProjectID" <> \'\' ',
            '  AND NOT EXISTS (SELECT 1 FROM becmaster.metadata AS m WHERE m."ProjectID" = s."ProjectID")'
          ),
          params = list(sub_id)
        )
        if (nrow(new_meta) > 0L) {
          m_placeholders <- paste0("$", seq_len(nrow(meta_spec)), "::", tolower(meta_spec$pg_type))
          ins_meta_sql <- paste0(
            "INSERT INTO becmaster.metadata (", meta_csv, ") VALUES (",
            paste(m_placeholders, collapse = ", "),
            ') ON CONFLICT ("ProjectID") DO NOTHING'
          )
          for (mi in seq_len(nrow(new_meta))) {
            new_m_id <- vpro_allocate_master_child_id(con$conn, "metadata")
            m_params <- vector("list", nrow(meta_spec))
            for (ci in seq_len(nrow(meta_spec))) {
              c_row <- meta_spec[ci, , drop = FALSE]
              cn <- c_row$name[[1L]]
              if (identical(cn, "ID")) {
                m_params[[ci]] <- vpro_pg_param_for_spec(c_row, new_m_id)
              } else {
                m_params[[ci]] <- vpro_pg_param_for_spec(c_row, new_meta[[cn]][[mi]])
              }
            }
            m_aff <- DBI::dbExecute(con$conn, ins_meta_sql, params = m_params)
            if (identical(as.integer(m_aff), 1L)) {
              record_audit("", "Metadata", "ProjectID", NA_character_, as.character(new_meta$ProjectID[[mi]]), new_m_id)
            }
          }
        }
      }

      # Append hash-chained audit rows into becmaster.audit
      tail_df <- DBI::dbGetQuery(
        con$conn,
        "SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1"
      )
      prev_hash <- if (nrow(tail_df) >= 1L && !is.na(tail_df$row_hash[[1L]]) && nzchar(trimws(tail_df$row_hash[[1L]]))) {
        tolower(trimws(as.character(tail_df$row_hash[[1L]])))
      } else {
        .vpro_genesis_audit_hash
      }

      n_aud <- length(aud_plot)
      if (n_aud > 0L) {
        prev_vec <- character(n_aud)
        hash_vec <- character(n_aud)
        for (ai in seq_len(n_aud)) {
          id_cell <- if (is.na(aud_id[[ai]])) {
            NA_integer_
          } else if (abs(aud_id[[ai]]) <= .Machine$integer.max) {
            as.integer(aud_id[[ai]])
          } else {
            sprintf("%.0f", aud_id[[ai]])
          }
          vp08_vals <- list(
            "BECMaster",
            actor_eff,
            aud_plot[[ai]],
            aud_tbl[[ai]],
            aud_fld[[ai]],
            now_edit_str,
            aud_before[[ai]],
            aud_after[[ai]],
            0L,
            0L,
            id_cell
          )
          r_hash <- vpro_compute_audit_row_hash(prev_hash, merge_tx_id, vp08_vals)
          prev_vec[[ai]] <- prev_hash
          hash_vec[[ai]] <- r_hash
          prev_hash <- r_hash
        }

        id_col_out <- if (all(is.na(aud_id) | abs(aud_id) <= .Machine$integer.max)) {
          out_i <- rep(NA_integer_, n_aud)
          ok_i <- !is.na(aud_id)
          if (any(ok_i)) out_i[ok_i] <- as.integer(aud_id[ok_i])
          out_i
        } else {
          out_c <- rep(NA_character_, n_aud)
          ok_c <- !is.na(aud_id)
          if (any(ok_c)) out_c[ok_c] <- sprintf("%.0f", aud_id[ok_c])
          out_c
        }

        audit_df <- data.frame(
          Project = rep("BECMaster", n_aud),
          User = rep(actor_eff, n_aud),
          PlotNumber = aud_plot,
          Table = aud_tbl,
          EditField = aud_fld,
          EditWhen = rep(now_edit_str, n_aud),
          BeforeEdit = aud_before,
          AfterEdit = aud_after,
          Restore = rep(0L, n_aud),
          Flag = rep(0L, n_aud),
          ID = id_col_out,
          merge_tx_id = rep(merge_tx_id, n_aud),
          prev_hash = prev_vec,
          row_hash = hash_vec,
          stringsAsFactors = FALSE
        )
        rownames(audit_df) <- NULL
        DBI::dbAppendTable(
          con$conn,
          DBI::Id(schema = "becmaster", table = "audit"),
          audit_df
        )
      }

      summary_json <- as.character(jsonlite::toJSON(
        list(
          sourceProject = preview$source_project,
          previewDigest = preview$preview_digest,
          addedPlots = as.integer(added_plots),
          updatedPlots = as.integer(updated_plots),
          skippedPlots = as.integer(skipped_plots),
          auditRowsWritten = as.integer(n_aud),
          allocatedChildIds = as.integer(length(allocated_ids)),
          reservedDeletedIds = as.integer(length(reserved_deleted_ids)),
          tailAuditHash = prev_hash
        ),
        auto_unbox = TRUE
      ))

      DBI::dbExecute(
        con$conn,
        paste(
          "INSERT INTO becmaster.merge_ledger (",
          "  merge_tx_id, submission_id, actor, merged_at, source_sha256,",
          "  added_plots, updated_plots, summary_json",
          ") VALUES (",
          "  $1::uuid, $2::uuid, $3, $4::timestamptz, $5,",
          "  $6::int, $7::int, $8::jsonb",
          ")"
        ),
        params = list(
          merge_tx_id,
          sub_id,
          actor_eff,
          now_iso_str,
          src_sha,
          as.integer(added_plots),
          as.integer(updated_plots),
          summary_json
        )
      )

      DBI::dbExecute(
        con$conn,
        paste(
          "UPDATE staging.submissions",
          "SET status = 'merged',",
          "    reviewed_by = $2,",
          "    reviewed_at = $3::timestamptz,",
          "    reviewer_notes = COALESCE($4::text, reviewer_notes),",
          "    merged_tx_id = $5::uuid",
          "WHERE submission_id = $1::uuid"
        ),
        params = list(sub_id, actor_eff, now_iso_str, rev_notes_clean, merge_tx_id)
      )

      DBI::dbExecute(con$conn, "COMMIT")
      tx_committed <- TRUE

      norm_id_vec <- function(v) {
        if (length(v) == 0L) return(integer(0L))
        v <- sort(v)
        if (all(abs(v) <= .Machine$integer.max)) as.integer(v) else v
      }

      list(
        merge_tx_id = merge_tx_id,
        submission_id = sub_id,
        source_project = preview$source_project,
        added_plots = as.integer(added_plots),
        updated_plots = as.integer(updated_plots),
        skipped_plots = as.integer(skipped_plots),
        allocated_child_ids = norm_id_vec(allocated_ids),
        reserved_deleted_ids = norm_id_vec(unique(reserved_deleted_ids)),
        audit_rows_written = as.integer(n_aud),
        tail_audit_hash = prev_hash,
        merged_at = now_iso_str
      )
    },
    action = "execute SERIALIZABLE staging-to-BECMaster merge"
  )
}

#' Reject a pending staging submission with custodian review notes
#'
#' Marks a `"pending"` submission in `staging.submissions` as `"rejected"`,
#' recording `reviewer_notes`, `reviewed_by`, and `reviewed_at`.
#'
#' @param con A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Pending staging submission UUID string.
#' @param reviewer_notes Non-empty character string explaining why the
#'   submission was rejected.
#' @param actor Optional custodian reviewer name (defaults to PostgreSQL
#'   `current_user`).
#' @return A 1-row `vpro_staging_queue` tibble containing the updated submission
#'   record.
#' @export
vpro_staging_reject <- function(con, submission_id, reviewer_notes, actor = NULL) {
  vpro_assert_pg_conn(con, require_custodian = TRUE)
  .vpro_register_sync_s3()
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")

  if (!is.character(reviewer_notes) || length(reviewer_notes) != 1L ||
      is.na(reviewer_notes) || !nzchar(trimws(reviewer_notes))) {
    cli::cli_abort("{.arg reviewer_notes} must be a single non-empty character string.")
  }
  notes_clean <- trimws(reviewer_notes)
  actor_clean <- vpro_validate_optional_scalar_chr(actor, "actor")
  actor_param <- if (is.na(actor_clean)) "" else actor_clean

  aff <- vpro_pg_execute(
    con,
    paste(
      "UPDATE staging.submissions",
      "SET status = 'rejected',",
      "    reviewer_notes = $2,",
      "    reviewed_by = COALESCE(NULLIF($3, ''), current_user),",
      "    reviewed_at = now()",
      "WHERE submission_id = $1::uuid AND status = 'pending'"
    ),
    params = list(sub_id, notes_clean, actor_param),
    action = "reject staging submission"
  )
  if (identical(as.integer(aff), 0L)) {
    cli::cli_abort(
      "Staging submission {.val {sub_id}} is not in {.val pending} status or does not exist."
    )
  }

  row_df <- vpro_pg_query(
    con,
    paste0(.vpro_staging_summary_select_sql, " WHERE submission_id = $1::uuid"),
    params = list(sub_id),
    action = "fetch rejected staging submission"
  )
  vpro_format_staging_queue_df(row_df)
}
