# PostgreSQL BECMaster Audit, Ephemeral Workspace & Standards Sync -----------

#' Query hash-chained audit records from PostgreSQL `becmaster.audit`
#'
#' Retrieves audit trail entries filtered by `plots`, `zones` / `subzones` /
#' `project_ids` (via `becmaster.env`), and/or `merge_tx_id`, ordered by
#' `audit_seq DESC`. Optionally verifies the cryptographic SHA-256 hash chain
#' and attaches the result as `attr(result, "chain_verification")`.
#'
#' @param pg A `vpro_pg_conn` handle.
#' @param plots Optional character vector of `PlotNumber` values.
#' @param zones Optional character vector of BEC zone codes.
#' @param subzones Optional character vector of BEC subzone/variant codes.
#' @param project_ids Optional character vector of `ProjectID` values.
#' @param merge_tx_id Optional merge transaction ID(s).
#' @param limit Optional positive integer row limit (defaults to `1000L`, or
#'   `NULL` for all matching rows).
#' @param verify_chain Logical; if `TRUE`, verifies the SHA-256 hash chain and
#'   attaches its report to `attr(result, "chain_verification")`.
#' @return A tibble of `becmaster.audit` records.
#' @export
vpro_master_audit <- function(
  pg,
  plots = NULL,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  merge_tx_id = NULL,
  limit = 1000L,
  verify_chain = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  verify_chain <- vpro_pg_validate_flag(verify_chain, "verify_chain")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  plots_clean <- vpro_pg_clean_tokens(plots, "plots")
  zones_clean <- vpro_pg_clean_tokens(zones, "zones")
  subzones_clean <- vpro_pg_clean_tokens(subzones, "subzones")
  project_ids_clean <- vpro_pg_clean_tokens(project_ids, "project_ids")
  merge_tx_clean <- vpro_pg_clean_tokens(merge_tx_id, "merge_tx_id")

  clauses <- character()
  params <- list()
  next_param <- function(val) {
    params[[length(params) + 1L]] <<- val
    paste0("$", length(params))
  }

  if (length(plots_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(plots_clean))
    clauses <- c(clauses, paste0('a."PlotNumber" = ANY(', p, "::text[])"))
  }

  env_sub <- character()
  if (length(zones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(zones_clean))
    env_sub <- c(env_sub, paste0('e."Zone" = ANY(', p, "::text[])"))
  }
  if (length(subzones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(subzones_clean))
    env_sub <- c(env_sub, paste0('e."SubZone" = ANY(', p, "::text[])"))
  }
  if (length(project_ids_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(project_ids_clean))
    env_sub <- c(env_sub, paste0('e."ProjectID" = ANY(', p, "::text[])"))
  }
  if (length(env_sub) > 0L) {
    clauses <- c(
      clauses,
      paste0(
        'EXISTS (SELECT 1 FROM becmaster.env AS e WHERE e."PlotNumber" = a."PlotNumber" AND ',
        paste(env_sub, collapse = " AND "),
        ")"
      )
    )
  }

  if (length(merge_tx_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(merge_tx_clean))
    clauses <- c(clauses, paste0("a.merge_tx_id::text = ANY(", p, "::text[])"))
  }

  audit_spec <- vpro_pg_vp08_specs("Audit")
  vp08_sel <- paste(
    vapply(
      as.character(audit_spec$name),
      function(f) {
        qf <- vpro_quote_ident(f)
        if (identical(f, "PlotNumber")) {
          'CAST(a."PlotNumber" AS TEXT) AS "PlotNumber"'
        } else {
          paste0("a.", qf, " AS ", qf)
        }
      },
      character(1)
    ),
    collapse = ", "
  )

  where_part <- if (length(clauses) > 0L) paste0(" WHERE ", paste(clauses, collapse = " AND ")) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  sql <- paste0(
    "SELECT a.audit_seq, ",
    vp08_sel,
    ", CAST(a.merge_tx_id AS TEXT) AS merge_tx_id, a.prev_hash, a.row_hash",
    " FROM becmaster.audit AS a",
    where_part,
    " ORDER BY a.audit_seq DESC",
    limit_part
  )

  df <- vpro_pg_query(
    pg,
    sql,
    params = if (length(params) > 0L) params else NULL,
    action = "query becmaster.audit"
  )

  canon <- vpro_pg_canonicalize_to_tidy(
    df[, intersect(audit_spec$name, names(df)), drop = FALSE],
    audit_spec
  )
  for (nm in names(canon)) {
    df[[nm]] <- canon[[nm]]
  }
  df$PlotNumber <- as.character(df$PlotNumber)
  for (bc in intersect(c("Restore", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  if ("merge_tx_id" %in% names(df)) {
    df$merge_tx_id <- as.character(df$merge_tx_id)
  }
  if ("prev_hash" %in% names(df)) {
    df$prev_hash <- as.character(df$prev_hash)
  }
  if ("row_hash" %in% names(df)) {
    df$row_hash <- as.character(df$row_hash)
  }

  tbl <- tibble::as_tibble(df)
  if (isTRUE(verify_chain)) {
    v_lim <- if (is.null(limit_int)) 1000L else limit_int
    attr(tbl, "chain_verification") <- .vpro_master_verify_audit(pg, limit = v_lim)
  }
  tbl
}

#' Read provincial BEC and taxonomy standards tables from PostgreSQL `standards.*`
#'
#' Queries either release metadata (`table = "releases"`, omitting the binary
#' `vlists_gzip` payload and reporting `vlists_gzip_bytes`) or one of the six
#' relational standards catalogues (`usys_all_specs`, `usys_table_of_lists`,
#' `bec_site_series`, `master_site_unit_list`, `usys_zone_list`,
#' `project_metadata`) ordered by `row_seq`.
#'
#' @param pg A `vpro_pg_conn` handle.
#' @param table Standards table to read: `"releases"`, `"usys_all_specs"`,
#'   `"usys_table_of_lists"`, `"bec_site_series"`, `"master_site_unit_list"`,
#'   `"usys_zone_list"`, or `"project_metadata"`.
#' @return A tibble of standards release metadata or catalogue records.
#' @export
vpro_master_standards <- function(
  pg,
  table = c(
    "releases",
    "usys_all_specs",
    "usys_table_of_lists",
    "bec_site_series",
    "master_site_unit_list",
    "usys_zone_list",
    "project_metadata"
  )
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  table <- match.arg(table)

  if (identical(table, "releases")) {
    sql <- paste(
      "SELECT release_id, published_at, published_by, bec_version, taxonomy_version,",
      "       vlists_sha256, bec_db_sha256, vmetadata_sha256, notes, is_current,",
      "       octet_length(vlists_gzip) AS vlists_gzip_bytes",
      "FROM standards.library_releases",
      "ORDER BY published_at DESC, release_id DESC"
    )
    df <- vpro_pg_query(pg, sql, params = NULL, action = "query standards.library_releases")
    for (tc in intersect(
      c(
        "release_id",
        "published_by",
        "bec_version",
        "taxonomy_version",
        "vlists_sha256",
        "bec_db_sha256",
        "vmetadata_sha256",
        "notes"
      ),
      names(df)
    )) {
      df[[tc]] <- as.character(df[[tc]])
    }
    if ("is_current" %in% names(df)) {
      df$is_current <- vpro_access_to_logical(df$is_current)
    }
    if ("vlists_gzip_bytes" %in% names(df)) {
      df$vlists_gzip_bytes <- suppressWarnings(as.integer(as.character(df$vlists_gzip_bytes)))
    }
    return(tibble::as_tibble(df))
  }

  spec <- vpro_pg_standards_specs(table)
  col_names <- as.character(spec$name)
  quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
  sql <- paste0(
    "SELECT ",
    quoted_cols,
    " FROM standards.",
    vpro_quote_ident(table),
    " ORDER BY row_seq"
  )
  df <- vpro_pg_query(pg, sql, params = NULL, action = paste0("query standards.", table))
  df <- vpro_pg_canonicalize_to_tidy(df, spec)

  text_cols <- as.character(spec$name[!is.na(spec$pg_type) & toupper(spec$pg_type) == "TEXT"])
  for (tc in intersect(text_cols, names(df))) {
    df[[tc]] <- as.character(df[[tc]])
  }
  bool_cols <- as.character(spec$name[
    (!is.na(spec$is_bool) & spec$is_bool) |
      (!is.na(spec$sqlite_type) & toupper(spec$sqlite_type) == "BOOLEAN")
  ])
  for (bc in intersect(bool_cols, names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  if ("Lifeform" %in% names(df)) {
    df$Lifeform <- suppressWarnings(as.integer(as.character(df$Lifeform)))
  }

  tibble::as_tibble(df)
}

#' Materialize a temporary local `vpro_workspace` from a PostgreSQL `BECMaster` subset
#'
#' Pulls a snapshot-consistent cloud subset into a session-temporary VPro
#' project database (`log_download = FALSE`), populates `<Project>_SU` from
#' `unit_col`, attaches a garbage-collector / session-exit finalizer to remove
#' the temporary database automatically, and returns a `vpro_workspace` handle
#' ready for [vpro_matrix()], [vpro_cluster()], [vpro_diagnostics()],
#' [vpro_climate()], and [vpro_render_guide()].
#'
#' @inheritParams vpro_master_env
#' @param unit_col Classification column used to populate `<Project>_SU`:
#'   `"BECSiteUnit"` (default), `"UserSiteUnit"`, or `"SiteSeries"`.
#' @param project_name Project prefix inside the temporary workspace database
#'   (defaults to `"CloudSubset"`).
#' @return An S3 `vpro_workspace` object with `ws$source == "cloud_workspace"`.
#' @export
vpro_master_workspace <- function(
  pg,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  unit_col = c("BECSiteUnit", "UserSiteUnit", "SiteSeries"),
  project_name = "CloudSubset",
  limit = NULL
) {
  unit_col_explicit <- !missing(unit_col)
  unit_col <- match.arg(unit_col)

  tmp_ws_db <- tempfile(pattern = "vpro-cloud-ws-", fileext = ".db")
  res <- vpro_master_pull_impl(
    pg = pg,
    dest_path = tmp_ws_db,
    project_name = project_name,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = TRUE,
    limit = limit,
    allow_full = FALSE,
    log_download = FALSE,
    allow_reserved_name = FALSE,
    unit_col = unit_col,
    unit_col_fallback = !unit_col_explicit
  )

  ws <- res$workspace
  ws$source <- "cloud_workspace"
  if (identical(res$su_count, 0L)) {
    ws$su <- NULL
  }

  cleanup_env <- new.env(parent = emptyenv())
  cleanup_env$db_path <- res$dest_path
  reg.finalizer(
    cleanup_env,
    function(e) {
      p <- e$db_path
      if (is.character(p) && length(p) == 1L && !is.na(p) && nzchar(p)) {
        unlink(c(p, paste0(p, "-wal"), paste0(p, "-shm")), force = TRUE)
      }
    },
    onexit = TRUE
  )
  ws$.cloud_cleanup <- cleanup_env
  attr(ws, "cloud_cleanup") <- cleanup_env
  ws
}

vpro_rebuild_vlists_from_standards <- function(pg, base_vlists_path, out_path, bec_version, taxonomy_version) {
  if (!file.copy(base_vlists_path, out_path, overwrite = TRUE)) {
    cli::cli_abort("Failed to stage baseline {.file VLists.db} for relational standards rebuild.")
  }

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), out_path)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = FULL")

  table_map <- list(
    list(pg = "usys_all_specs", sqlite = "USysAllSpecs"),
    list(pg = "usys_table_of_lists", sqlite = "USysTableOfLists"),
    list(pg = "master_site_unit_list", sqlite = "MasterSiteUnitList"),
    list(pg = "usys_zone_list", sqlite = "USysZoneList")
  )

  DBI::dbWithTransaction(sq_con, {
    for (item in table_map) {
      spec <- vpro_pg_standards_specs(item$pg)
      col_names <- as.character(spec$name)
      quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
      df <- vpro_pg_query(
        pg,
        paste0("SELECT ", quoted_cols, " FROM standards.", vpro_quote_ident(item$pg), " ORDER BY row_seq"),
        params = NULL,
        action = paste0("sync standards.", item$pg)
      )
      df <- vpro_pg_canonicalize_to_sqlite(df, spec)
      bool_cols <- as.character(spec$name[
        (!is.na(spec$is_bool) & spec$is_bool) |
          (!is.na(spec$sqlite_type) & toupper(spec$sqlite_type) == "BOOLEAN")
      ])
      for (bc in intersect(bool_cols, names(df))) {
        df[[bc]] <- vpro_logical_to_access(df[[bc]])
      }
      DBI::dbExecute(sq_con, paste0("DELETE FROM ", vpro_quote_ident(item$sqlite)))
      if (nrow(df) > 0L) {
        sq_fields <- DBI::dbListFields(sq_con, item$sqlite)
        keep_c <- intersect(sq_fields, names(df))
        DBI::dbAppendTable(sq_con, item$sqlite, df[, keep_c, drop = FALSE])
      }
    }

    if (DBI::dbExistsTable(sq_con, "_table_metadata")) {
      DBI::dbExecute(
        sq_con,
        'UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = \'USysAllSpecs\'',
        params = list(as.character(taxonomy_version))
      )
      DBI::dbExecute(
        sq_con,
        'UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = \'USysTableOfLists\'',
        params = list(as.character(bec_version))
      )
    }
  })

  DBI::dbDisconnect(sq_con)
  invisible(out_path)
}

#' Synchronize local `VLists.db` with the active provincial standards release
#'
#' Compares the SHA-256 checksum of the workspace `VLists.db` against the active
#' (`is_current = TRUE`) release in `standards.library_releases`. When absent or
#' outdated, refuses to overwrite `VLists.db` if it is open in an active VPro
#' session, downloads and verifies the compressed cloud release (falling back to
#' rebuilding from `standards.*` tables if needed), checks database integrity,
#' and atomically swaps the staged database onto `VLists.db`.
#'
#' @param pg A `vpro_pg_conn` handle.
#' @param data_dir Target VPro workspace data directory (defaults to
#'   [vpro_data_dir()]).
#' @return A list with `updated`, `already_current`, `release_id`,
#'   `bec_version`, `taxonomy_version`, `local_sha256`, `cloud_sha256`,
#'   `vlists_path`, and `published_at`.
#' @export
vpro_master_standards_sync <- function(pg, data_dir = vpro_data_dir()) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  if (!is.character(data_dir) || length(data_dir) != 1L || is.na(data_dir) || !nzchar(trimws(data_dir))) {
    cli::cli_abort("{.arg data_dir} must be a single non-empty directory path.")
  }
  data_dir <- vpro_abs_path(trimws(data_dir))
  if (vpro_is_bundled_package_path(data_dir)) {
    cli::cli_abort("Refusing to write {.file VLists.db} inside the installed {.pkg vpro} package directory.")
  }

  rel_df <- vpro_pg_query(
    pg,
    paste(
      "SELECT release_id, bec_version, taxonomy_version, vlists_sha256, published_at, vlists_gzip",
      "FROM standards.library_releases",
      "WHERE is_current = TRUE",
      "ORDER BY published_at DESC",
      "LIMIT 1"
    ),
    params = NULL,
    action = "query active standards.library_releases"
  )
  if (nrow(rel_df) == 0L) {
    cli::cli_abort(
      "No active provincial standards release ({.code is_current = TRUE}) has been published in {.code standards.library_releases}."
    )
  }

  release_id <- as.character(rel_df$release_id[[1L]])
  bec_version <- as.character(rel_df$bec_version[[1L]])
  taxonomy_version <- as.character(rel_df$taxonomy_version[[1L]])
  cloud_sha256 <- tolower(trimws(as.character(rel_df$vlists_sha256[[1L]])))
  pub_raw <- rel_df$published_at[[1L]]
  published_at <- if (inherits(pub_raw, "POSIXt")) {
    format(pub_raw, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  } else {
    as.character(pub_raw)
  }

  cand_top <- file.path(data_dir, "VLists.db")
  cand_fam <- file.path(data_dir, "database-family", "VLists.db")
  if (file.exists(cand_top)) {
    target_path <- normalizePath(cand_top, winslash = "/", mustWork = FALSE)
    target_exists <- TRUE
  } else if (file.exists(cand_fam)) {
    target_path <- normalizePath(cand_fam, winslash = "/", mustWork = FALSE)
    target_exists <- TRUE
  } else {
    dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
    target_path <- normalizePath(cand_top, winslash = "/", mustWork = FALSE)
    target_exists <- FALSE
  }

  if (target_exists) {
    local_sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(target_path)))))
    if (vpro_same_hash(local_sha256, cloud_sha256)) {
      return(list(
        updated = FALSE,
        already_current = TRUE,
        release_id = release_id,
        bec_version = bec_version,
        taxonomy_version = taxonomy_version,
        local_sha256 = local_sha256,
        cloud_sha256 = cloud_sha256,
        vlists_path = target_path,
        published_at = published_at
      ))
    }
  } else {
    bundled_vlists <- vpro_bundled_db("VLists.db")
    local_sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(bundled_vlists)))))
  }

  wal_path <- paste0(target_path, "-wal")
  shm_path <- paste0(target_path, "-shm")
  has_wal_activity <- (file.exists(wal_path) && !is.na(file.info(wal_path)$size)) ||
    (file.exists(shm_path) && !is.na(file.info(shm_path)$size))
  if (has_wal_activity) {
    cli::cli_abort(
      "Refusing to overwrite {.path {target_path}} while it is open in another VPro or database session."
    )
  }

  gz_col <- rel_df$vlists_gzip
  raw_vec <- if (is.raw(gz_col)) {
    gz_col
  } else if (is.list(gz_col) && length(gz_col) >= 1L) {
    gz_col[[1L]]
  } else {
    NULL
  }

  dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)
  tmp_vlists <- tempfile(pattern = ".vpro-vlists-sync-", tmpdir = dirname(target_path), fileext = ".db")
  published <- FALSE
  on.exit(
    {
      if (!published) {
        unlink(tmp_vlists, force = TRUE)
      }
      unlink(c(paste0(tmp_vlists, "-wal"), paste0(tmp_vlists, "-shm")), force = TRUE)
    },
    add = TRUE
  )

  if (!is.null(raw_vec) && is.raw(raw_vec) && length(raw_vec) > 0L) {
    db_bytes <- tryCatch(
      memDecompress(raw_vec, type = "gzip"),
      error = function(e) {
        cli::cli_abort(
          paste0("Failed to decompress cloud {.file VLists.db} gzip snapshot: ", conditionMessage(e)),
          parent = e
        )
      }
    )
    writeBin(db_bytes, tmp_vlists)
    staged_sha <- tolower(trimws(unname(as.character(vpro_sha256_file(tmp_vlists)))))
    if (!is.na(cloud_sha256) && nzchar(cloud_sha256) && !vpro_same_hash(staged_sha, cloud_sha256)) {
      cli::cli_abort(
        "Cloud {.file VLists.db} SHA-256 mismatch (expected {.val {cloud_sha256}}, got {.val {staged_sha}})."
      )
    }
  } else {
    base_vlists <- if (target_exists) target_path else vpro_bundled_db("VLists.db")
    vpro_rebuild_vlists_from_standards(
      pg = pg,
      base_vlists_path = base_vlists,
      out_path = tmp_vlists,
      bec_version = bec_version,
      taxonomy_version = taxonomy_version
    )
  }

  chk_con <- vpro_sqlite_ro(tmp_vlists)
  ic_df <- tryCatch(
    DBI::dbGetQuery(chk_con, "PRAGMA integrity_check"),
    finally = if (DBI::dbIsValid(chk_con)) DBI::dbDisconnect(chk_con)
  )
  if (nrow(ic_df) == 0L || !identical(tolower(trimws(as.character(ic_df[[1L]][[1L]]))), "ok")) {
    cli::cli_abort("Staged {.file VLists.db} failed database integrity verification.")
  }

  if (file.exists(wal_path) || file.exists(shm_path)) {
    cli::cli_abort(
      "Refusing to overwrite {.path {target_path}} while it is open in another VPro or database session."
    )
  }

  if (!file.rename(tmp_vlists, target_path)) {
    if (file.exists(target_path)) {
      unlink(target_path)
    }
    if (!file.rename(tmp_vlists, target_path)) {
      if (!file.copy(tmp_vlists, target_path, overwrite = TRUE)) {
        cli::cli_abort("Failed to atomically install updated {.file VLists.db} at {.path {target_path}}.")
      }
      unlink(tmp_vlists, force = TRUE)
    }
  }
  published <- TRUE

  final_path <- normalizePath(target_path, winslash = "/", mustWork = TRUE)
  final_sha <- tolower(trimws(unname(as.character(vpro_sha256_file(final_path)))))

  list(
    updated = TRUE,
    already_current = FALSE,
    release_id = release_id,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    local_sha256 = final_sha,
    cloud_sha256 = cloud_sha256,
    vlists_path = final_path,
    published_at = published_at
  )
}
