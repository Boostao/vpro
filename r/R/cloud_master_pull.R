# PostgreSQL BECMaster Subset Checkout to Local VP08 SQLite ------------------

vpro_master_pull_impl <- function(
  pg,
  dest_path,
  project_name,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  overwrite = FALSE,
  limit = NULL,
  allow_full = FALSE,
  log_download = TRUE,
  allow_reserved_name = FALSE,
  unit_col = NULL,
  unit_col_fallback = TRUE,
  redact_sensitive = !identical(pg$role, "custodian")
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  overwrite <- vpro_pg_validate_flag(overwrite, "overwrite")
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  log_download <- vpro_pg_validate_flag(log_download, "log_download")
  redact_sensitive <- vpro_pg_validate_flag(redact_sensitive, "redact_sensitive")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  project_name <- vpro_validate_splinter_project_name(
    project_name,
    allow_reserved_name = allow_reserved_name
  )

  if (!is.character(dest_path) || length(dest_path) != 1L || is.na(dest_path) || !nzchar(trimws(dest_path))) {
    cli::cli_abort("{.arg dest_path} must be a single non-empty file path.")
  }
  dest_clean <- trimws(dest_path)
  if (!nzchar(tools::file_ext(dest_clean))) {
    dest_clean <- paste0(dest_clean, ".db")
  }
  dest_resolved <- vpro_abs_path(dest_clean)

  if (vpro_is_protected_support_db(dest_resolved) || vpro_is_bundled_package_path(dest_resolved)) {
    cli::cli_abort(
      "Refusing to write subset database onto protected system or bundled path: {.path {dest_resolved}}."
    )
  }
  if (file.exists(paste0(dest_resolved, "-wal")) || file.exists(paste0(dest_resolved, "-shm"))) {
    cli::cli_abort(
      "Refusing to write to {.path {dest_resolved}} while active SQLite WAL/SHM sidecar files exist."
    )
  }
  if (file.exists(dest_resolved)) {
    if (dir.exists(dest_resolved)) {
      cli::cli_abort("{.arg dest_path} points to an existing directory: {.path {dest_resolved}}.")
    }
    if (!isTRUE(overwrite)) {
      cli::cli_abort(
        "Destination SQLite file already exists (pass {.code overwrite = TRUE} to replace): {.path {dest_resolved}}."
      )
    }
  }

  sub <- vpro_pg_subset_where(
    pg = pg,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    table_alias = "e",
    allow_full = allow_full,
    has_limit = !is.null(limit_int)
  )

  tx_open <- FALSE
  on.exit({
    if (tx_open) {
      tryCatch(
        vpro_pg_execute(pg, "ROLLBACK", params = NULL, action = "rollback subset snapshot transaction"),
        error = function(e) NULL
      )
    }
  }, add = TRUE)

  vpro_pg_exec_safe(
    function() vpro_pg_begin_isolated_tx(pg$conn, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY", "vpro_master_pull"),
    action = "begin subset snapshot transaction"
  )
  tx_open <- TRUE

  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  plot_sql <- paste0(
    'SELECT CAST(e."PlotNumber" AS TEXT) AS "PlotNumber" FROM becmaster.env AS e',
    where_part,
    ' ORDER BY e."PlotNumber"',
    limit_part
  )
  matched_df <- vpro_pg_query(
    pg,
    plot_sql,
    params = if (length(sub$params) > 0L) sub$params else NULL,
    action = "query matching BECMaster plots"
  )
  plot_list <- as.character(matched_df$PlotNumber)
  plot_list <- plot_list[!is.na(plot_list) & nzchar(plot_list)]
  if (length(plot_list) == 0L) {
    cli::cli_abort("Subset filter matched 0 plots in {.code becmaster.env}.")
  }

  sensitive_plots <- if (isTRUE(redact_sensitive)) {
    sens_codes <- .vpro_sensitive_species_codes(pg = pg)
    .vpro_sensitive_plots_in_pg(pg, plot_list, sens_codes)
  } else {
    character(0L)
  }

  dir.create(dirname(dest_resolved), recursive = TRUE, showWarnings = FALSE)
  tmp_db <- tempfile(pattern = ".vpro-pgsubset-", tmpdir = dirname(dest_resolved), fileext = ".db")
  published <- FALSE
  on.exit({
    if (!published) {
      unlink(tmp_db, force = TRUE)
    }
    unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)
  }, add = TRUE)

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA foreign_keys = OFF")
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = NORMAL")

  veg_n <- 0L
  humus_n <- 0L
  mineral_n <- 0L
  other_n <- 0L
  meta_n <- 0L
  su_n <- 0L

  plot_chunks <- split(plot_list, ceiling(seq_along(plot_list) / 20000L))

  DBI::dbWithTransaction(sq_con, {
    deferred_idx <- vpro_clone_sample_schema(sq_con, project_name)

    DBI::dbExecute(
      sq_con,
      'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)'
    )
    for (sfx in .vpro_core_project_suffixes) {
      DBI::dbExecute(
        sq_con,
        'INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
        params = list(paste0(project_name, "_", sfx))
      )
    }
    DBI::dbExecute(
      sq_con,
      'CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" ("ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable", "ID"))'
    )

    stream_plot_table <- function(pg_tbl, plot_col, suffix) {
      spec <- vpro_pg_vp08_specs(suffix)
      col_names <- as.character(spec$name)
      quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
      dst_tbl <- paste0(project_name, "_", suffix)
      dst_fields <- DBI::dbListFields(sq_con, dst_tbl)
      enforce_unique_id <- suffix %in% c("Veg", "Humus", "Mineral", "Other")
      used_ids <- new.env(hash = TRUE, parent = emptyenv())
      total_rows <- 0L

      ord_clause <- if (identical(suffix, "Audit")) {
        " ORDER BY audit_seq ASC"
      } else if ("ID" %in% col_names) {
        paste0(" ORDER BY ", vpro_quote_ident(plot_col), ', "ID"')
      } else {
        paste0(" ORDER BY ", vpro_quote_ident(plot_col))
      }

      for (ch in plot_chunks) {
        q <- paste0(
          "SELECT ", quoted_cols,
          " FROM becmaster.", vpro_quote_ident(pg_tbl),
          " WHERE ", vpro_quote_ident(plot_col), " = ANY($1::text[])",
          ord_clause
        )
        part <- vpro_pg_query(
          pg,
          q,
          params = list(vpro_pg_text_array(ch)),
          action = paste0("stream becmaster.", pg_tbl)
        )
        if (nrow(part) == 0L) {
          next
        }
        part <- vpro_pg_canonicalize_to_sqlite(part, spec)
        if (plot_col %in% names(part)) {
          part[[plot_col]] <- as.character(part[[plot_col]])
        }
        if (identical(suffix, "Env") && length(sensitive_plots) > 0L) {
          part <- .vpro_redact_coord_df(part, sensitive_plots)
        }
        bool_cols <- as.character(spec$name[!is.na(spec$is_bool) & spec$is_bool])
        for (bc in intersect(bool_cols, names(part))) {
          part[[bc]] <- vpro_logical_to_access(part[[bc]])
        }
        if (identical(suffix, "Veg") && "Species" %in% names(part)) {
          part$Species <- as.character(part$Species)
          part$Species[is.na(part$Species)] <- ""
        }
        if (identical(suffix, "Audit") && "Project" %in% names(part)) {
          part$Project <- rep(project_name, nrow(part))
        }
        if (enforce_unique_id && "ID" %in% names(part)) {
          part$ID <- vpro_assign_unique_ids(
            part$ID,
            used_env = used_ids,
            start_id = 100000000,
            require_positive = FALSE
          )
        }
        keep_cols <- intersect(dst_fields, names(part))
        DBI::dbAppendTable(sq_con, dst_tbl, part[, keep_cols, drop = FALSE])
        total_rows <- total_rows + nrow(part)
      }
      total_rows
    }

    stream_plot_table("env", "PlotNumber", "Env")
    stream_plot_table("admin", "Plot", "Admin")
    veg_n <- stream_plot_table("veg", "PlotNumber", "Veg")
    humus_n <- stream_plot_table("humus", "PlotNumber", "Humus")
    mineral_n <- stream_plot_table("mineral", "PlotNumber", "Mineral")
    other_n <- stream_plot_table("other", "PlotNumber", "Other")
    stream_plot_table("audit", "PlotNumber", "Audit")

    DBI::dbExecute(
      sq_con,
      paste0("UPDATE ", vpro_quote_ident(paste0(project_name, "_Audit")), ' SET "Project" = ?'),
      params = list(project_name)
    )

    # Populate <Project>_Metadata for referenced ProjectIDs (with 1-row fallback)
    ref_pids <- DBI::dbGetQuery(
      sq_con,
      paste0(
        'SELECT DISTINCT "ProjectID" FROM ',
        vpro_quote_ident(paste0(project_name, "_Env")),
        ' WHERE typeof("ProjectID") = \'text\' AND TRIM("ProjectID") <> \'\''
      )
    )$ProjectID
    ref_pids <- vpro_pg_clean_tokens(ref_pids, "project_ids")

    meta_dst <- paste0(project_name, "_Metadata")
    if (length(ref_pids) > 0L) {
      meta_spec <- vpro_pg_vp08_specs("Metadata")
      meta_cols <- as.character(meta_spec$name)
      meta_csv <- paste(vapply(meta_cols, vpro_quote_ident, character(1)), collapse = ", ")
      meta_df <- vpro_pg_query(
        pg,
        paste0(
          "SELECT ", meta_csv,
          ' FROM becmaster.metadata WHERE "ProjectID" = ANY($1::text[]) ORDER BY "ProjectID"'
        ),
        params = list(vpro_pg_text_array(ref_pids)),
        action = "stream becmaster.metadata"
      )
      if (nrow(meta_df) > 0L) {
        meta_df <- vpro_pg_canonicalize_to_sqlite(meta_df, meta_spec)
        if ("ID" %in% names(meta_df)) {
          used_meta_ids <- new.env(hash = TRUE, parent = emptyenv())
          meta_df$ID <- vpro_assign_unique_ids(
            meta_df$ID,
            used_env = used_meta_ids,
            start_id = 1,
            require_positive = TRUE
          )
        }
        meta_fields <- DBI::dbListFields(sq_con, meta_dst)
        keep_m <- intersect(meta_fields, names(meta_df))
        DBI::dbAppendTable(sq_con, meta_dst, meta_df[, keep_m, drop = FALSE])
        meta_n <- nrow(meta_df)
      }
    }

    if (meta_n == 0L) {
      DBI::dbExecute(
        sq_con,
        paste0(
          "INSERT INTO ", vpro_quote_ident(meta_dst),
          ' ("ProjectID", "ProjectTitle", "ID") VALUES (?, ?, 1)'
        ),
        params = list(project_name, paste0(project_name, " BECMaster Subset"))
      )
      meta_n <- 1L
    }

    # Seed __VPRO_ChildIdentity for all child tables
    for (sfx in c("Veg", "Humus", "Mineral", "Other", "Metadata", "Audit")) {
      full_tbl <- paste0(project_name, "_", sfx)
      q_full <- vpro_quote_ident(full_tbl)
      DBI::dbExecute(
        sq_con,
        paste0(
          'INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") ',
          "SELECT ?, \"ID\" FROM ", q_full,
          ' WHERE typeof("ID") = \'integer\' AND "ID" >= 0'
        ),
        params = list(q_full)
      )
    }

    # Build <Project>_SU so classification, matrix, and diagnostics work immediately
    su_tbl <- paste0(project_name, "_SU")
    q_su <- vpro_quote_ident(su_tbl)
    q_env <- vpro_quote_ident(paste0(project_name, "_Env"))
    q_adm <- vpro_quote_ident(paste0(project_name, "_Admin"))

    DBI::dbExecute(
      sq_con,
      paste0("CREATE TABLE ", q_su, ' ("PlotNumber" TEXT, "SiteUnit" TEXT)')
    )

    coalesced_su_expr <- paste(
      "COALESCE(",
      "  NULLIF(TRIM(CAST(a.\"BECSiteUnit\" AS TEXT)), ''),",
      "  NULLIF(TRIM(CAST(a.\"UserSiteUnit\" AS TEXT)), ''),",
      "  CASE",
      "    WHEN e.\"Zone\" IS NOT NULL AND TRIM(CAST(e.\"Zone\" AS TEXT)) <> ''",
      "     AND e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
      "    THEN TRIM(CAST(e.\"Zone\" AS TEXT)) || COALESCE(TRIM(CAST(e.\"SubZone\" AS TEXT)), '') || '/' || TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
      "    ELSE NULL",
      "  END",
      ")"
    )

    su_expr <- if (is.null(unit_col)) {
      coalesced_su_expr
    } else if (identical(unit_col, "BECSiteUnit")) {
      'NULLIF(TRIM(CAST(a."BECSiteUnit" AS TEXT)), \'\')'
    } else if (identical(unit_col, "UserSiteUnit")) {
      'NULLIF(TRIM(CAST(a."UserSiteUnit" AS TEXT)), \'\')'
    } else if (identical(unit_col, "SiteSeries")) {
      paste(
        "CASE",
        "  WHEN e.\"Zone\" IS NOT NULL AND TRIM(CAST(e.\"Zone\" AS TEXT)) <> ''",
        "   AND e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
        "  THEN TRIM(CAST(e.\"Zone\" AS TEXT)) || COALESCE(TRIM(CAST(e.\"SubZone\" AS TEXT)), '') || '/' || TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
        "  WHEN e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
        "  THEN TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
        "  ELSE NULL",
        "END"
      )
    } else {
      coalesced_su_expr
    }

    insert_su_with_expr <- function(expr_sql) {
      DBI::dbExecute(
        sq_con,
        paste0(
          "INSERT INTO ", q_su, ' ("PlotNumber", "SiteUnit") ',
          "SELECT PlotNumber, SiteUnit FROM (",
          '  SELECT CAST(e."PlotNumber" AS TEXT) AS PlotNumber, ',
          expr_sql, " AS SiteUnit ",
          "  FROM ", q_env, " AS e ",
          "  LEFT JOIN ", q_adm, ' AS a ON e."PlotNumber" = a."Plot" ',
          '  WHERE typeof(e."PlotNumber") = \'text\' AND TRIM(e."PlotNumber") <> \'\' ',
          '  ORDER BY e."PlotNumber"',
          ") WHERE SiteUnit IS NOT NULL AND TRIM(SiteUnit) <> ''"
        )
      )
      as.integer(DBI::dbGetQuery(sq_con, paste0("SELECT COUNT(*) AS n FROM ", q_su))$n[[1L]])
    }

    su_n <- insert_su_with_expr(su_expr)
    if (su_n == 0L && !is.null(unit_col) && isTRUE(unit_col_fallback)) {
      su_n <- insert_su_with_expr(coalesced_su_expr)
    }

    DBI::dbExecute(
      sq_con,
      paste0(
        "CREATE UNIQUE INDEX ",
        vpro_quote_ident(paste0("uidx_", su_tbl, "_PlotNumber")),
        " ON ", q_su, ' ("PlotNumber")'
      )
    )
    DBI::dbExecute(
      sq_con,
      paste0(
        "CREATE INDEX ",
        vpro_quote_ident(paste0("idx_", su_tbl, "_SiteUnit")),
        " ON ", q_su, ' ("SiteUnit")'
      )
    )
    DBI::dbExecute(
      sq_con,
      'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP04\')',
      params = list(su_tbl)
    )

    for (idx_sql in deferred_idx) {
      DBI::dbExecute(sq_con, idx_sql)
    }
  })

  # Capture snapshot-consistent standards release & audit tail inside the same REPEATABLE READ transaction
  snap_bec_ver <- "BECdb_v13_2026"
  snap_tax_ver <- "BCPlantTaxa_v19_2025"
  rel_in_tx <- tryCatch(
    vpro_pg_query(
      pg,
      "SELECT bec_version, taxonomy_version FROM standards.library_releases WHERE is_current = TRUE ORDER BY published_at DESC, release_id DESC LIMIT 1",
      params = NULL,
      action = "query active standards release inside snapshot"
    ),
    error = function(e) data.frame()
  )
  if (nrow(rel_in_tx) >= 1L) {
    if (!is.na(rel_in_tx$bec_version[[1L]]) && nzchar(trimws(as.character(rel_in_tx$bec_version[[1L]])))) {
      snap_bec_ver <- trimws(as.character(rel_in_tx$bec_version[[1L]]))
    }
    if (!is.na(rel_in_tx$taxonomy_version[[1L]]) && nzchar(trimws(as.character(rel_in_tx$taxonomy_version[[1L]])))) {
      snap_tax_ver <- trimws(as.character(rel_in_tx$taxonomy_version[[1L]]))
    }
  }
  tail_in_tx <- tryCatch(
    vpro_pg_query(
      pg,
      "SELECT COALESCE((SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1), $1) AS tail_hash",
      params = list(.vpro_genesis_audit_hash),
      action = "query audit tail row_hash inside snapshot"
    ),
    error = function(e) data.frame(tail_hash = .vpro_genesis_audit_hash)
  )
  snap_tail_hash <- if (nrow(tail_in_tx) >= 1L && !is.na(tail_in_tx$tail_hash[[1L]]) && nzchar(trimws(as.character(tail_in_tx$tail_hash[[1L]])))) {
    tolower(trimws(as.character(tail_in_tx$tail_hash[[1L]])))
  } else {
    .vpro_genesis_audit_hash
  }

  # Close read-only PostgreSQL snapshot transaction cleanly before WAL finalization & download_log write
  vpro_pg_execute(pg, "ROLLBACK", params = NULL, action = "close subset snapshot transaction")
  tx_open <- FALSE

  DBI::dbDisconnect(sq_con)

  insp <- vpro_project_inspect(tmp_db, project_name)
  if (!isTRUE(insp$compatible)) {
    cli::cli_abort("Staged subset SQLite database did not pass {.code VP08} compatibility verification.")
  }

  wal_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db, flags = RSQLite::SQLITE_RW)
  tryCatch({
    DBI::dbExecute(wal_con, "PRAGMA journal_mode = WAL")
    DBI::dbExecute(wal_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  }, finally = {
    if (DBI::dbIsValid(wal_con)) DBI::dbDisconnect(wal_con)
  })
  unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)

  if (file.exists(paste0(dest_resolved, "-wal")) || file.exists(paste0(dest_resolved, "-shm"))) {
    cli::cli_abort(
      "Refusing to overwrite {.path {dest_resolved}} while active SQLite WAL/SHM sidecar files exist."
    )
  }

  if (!file.rename(tmp_db, dest_resolved)) {
    if (isTRUE(overwrite) && file.exists(dest_resolved)) {
      unlink(dest_resolved)
    }
    if (!file.rename(tmp_db, dest_resolved)) {
      if (!file.copy(tmp_db, dest_resolved, overwrite = isTRUE(overwrite))) {
        cli::cli_abort("Failed to atomically publish subset SQLite database to {.path {dest_resolved}}.")
      }
      unlink(tmp_db, force = TRUE)
    }
  }
  published <- TRUE

  dest_final <- normalizePath(dest_resolved, winslash = "/", mustWork = TRUE)
  ws <- vpro_connect(dest_final)
  attr(ws, "cloud_redacted") <- (isTRUE(redact_sensitive) && length(sensitive_plots) > 0L)
  attr(ws, "cloud_role") <- as.character(pg$role)

  # Cleanly close a RW handle after SQLITE_RO inspection inside vpro_connect() so
  # SQLite removes idle -shm/-wal sidecars while preserving journal_mode = WAL
  clean_con <- DBI::dbConnect(RSQLite::SQLite(), dest_final, flags = RSQLite::SQLITE_RW)
  tryCatch({
    DBI::dbGetQuery(clean_con, "SELECT 1 FROM sqlite_master LIMIT 1")
    DBI::dbExecute(clean_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  }, finally = {
    if (DBI::dbIsValid(clean_con)) DBI::dbDisconnect(clean_con)
  })
  sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(dest_final)))))

  download_log_id <- NA_integer_
  if (isTRUE(log_download)) {
    actor <- if (!is.null(pg$user) && length(pg$user) >= 1L &&
                 !is.na(pg$user[[1L]]) && nzchar(trimws(as.character(pg$user[[1L]])))) {
      trimws(as.character(pg$user[[1L]]))
    } else {
      "VProUser"
    }
    role_tier <- if (!is.null(pg$role) && length(pg$role) >= 1L &&
                     !is.na(pg$role[[1L]]) && nzchar(trimws(as.character(pg$role[[1L]])))) {
      trimws(as.character(pg$role[[1L]]))
    } else {
      "contributor"
    }
    filter_json <- vpro_serialize_subset_filter_json(
      sub$filters,
      limit_int = limit_int,
      allow_full = allow_full
    )
    log_df <- vpro_pg_query(
      pg,
      paste(
        "INSERT INTO becmaster.download_log (actor, role_tier, filter_json, format, plot_count)",
        "VALUES ($1, $2, $3::jsonb, 'VP08_SQLite', $4)",
        "RETURNING id"
      ),
      params = list(actor, role_tier, filter_json, as.integer(length(plot_list))),
      action = "record becmaster.download_log entry"
    )
    if (nrow(log_df) >= 1L && "id" %in% names(log_df)) {
      id_chr <- as.character(log_df$id[[1L]])
      id_dbl <- suppressWarnings(as.double(id_chr))
      download_log_id <- if (!is.na(id_dbl) && abs(id_dbl) <= .Machine$integer.max) {
        as.integer(id_chr)
      } else {
        id_dbl
      }
    }
  }

  list(
    dest_path = dest_final,
    project_name = project_name,
    sha256 = sha256,
    plot_count = as.integer(length(plot_list)),
    veg_count = as.integer(veg_n),
    humus_count = as.integer(humus_n),
    mineral_count = as.integer(mineral_n),
    other_count = as.integer(other_n),
    metadata_count = as.integer(meta_n),
    su_count = as.integer(su_n),
    download_log_id = download_log_id,
    snapshot_meta = list(
      bec_version = snap_bec_ver,
      taxonomy_version = snap_tax_ver,
      tail_audit_hash = snap_tail_hash
    ),
    workspace = ws
  )
}

#' Pull a snapshot-consistent PostgreSQL `BECMaster` subset into a local `VP08` SQLite `.db`
#'
#' Streams a filtered regional or project checkout from PostgreSQL `becmaster.*`
#' inside a `REPEATABLE READ READ ONLY` transaction into an atomic `VP08` SQLite
#' WAL database (`_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`,
#' `_Audit`, `_Metadata`, `_SU`, `_table_metadata`, and `__VPRO_ChildIdentity`),
#' verifies `VP08` compatibility via [vpro_project_inspect()], and records a
#' provenance receipt in `becmaster.download_log`.
#'
#' @inheritParams vpro_master_env
#' @param dest_db Destination SQLite `.db` file path (`.db` is appended if no
#'   file extension is present).
#' @param project Target `VP08` project prefix (must start with an ASCII
#'   letter, contain only letters, digits, or underscores up to 31 characters,
#'   and cannot be `"None"`, `"Sample"`, or contain `"master"`).
#' @param overwrite Logical; if `TRUE`, replaces an existing `dest_db` when no
#'   active `-wal`/`-shm` sidecar files exist.
#' @return A list containing `dest_path`, `project_name`, `sha256`, `plot_count`,
#'   `veg_count`, `humus_count`, `mineral_count`, `other_count`,
#'   `metadata_count`, `download_log_id`, and `workspace` (`vpro_workspace`).
#' @export
vpro_master_pull <- function(
  pg,
  dest_db,
  project,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  overwrite = FALSE,
  limit = NULL,
  allow_full = FALSE
) {
  res <- vpro_master_pull_impl(
    pg = pg,
    dest_path = dest_db,
    project_name = project,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = overwrite,
    limit = limit,
    allow_full = allow_full,
    log_download = TRUE,
    allow_reserved_name = FALSE,
    unit_col = NULL,
    unit_col_fallback = TRUE
  )
  res$su_count <- NULL
  res
}
