# Headless PostgreSQL BECMaster Contributor Staging & Custodian 3-Way Merge ----

.vpro_sync_s3_state <- new.env(parent = emptyenv())

.vpro_register_sync_s3 <- function() {
  .vpro_register_s3_methods(.vpro_sync_s3_state, list(
    c("base", "print", "vpro_staging_queue"),
    c("base", "print", "vpro_merge_preview"),
    c("tibble", "as_tibble", "vpro_merge_preview")
  ))
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
  # streamed rows observe the exact same point-in-time state even if VPro Desktop writes concurrently.
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
