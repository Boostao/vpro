# Portable VP08 RDS Project Export & Import ----------------------------------

#' Write a compact compressed `VP08` `.rds` snapshot bundle from a workspace
#'
#' Extracts all 8 `VP08` project tables (`env`, `admin`, `veg`, `humus`,
#' `mineral`, `other`, `metadata`, `audit`), site-unit assignments (`su`), and
#' species lump mappings (`lump`) from any `vpro_workspace` (see [vpro_connect()],
#' e.g. `vpro_connect("Sample")`), enforces literal `character` `PlotNumber`/`Plot` keys,
#' normalizes VPro yes/no flags to R `logical`, applies VPro cover precision
#' via [vpro_narrow_float32()], and writes a compressed `"vpro_rds_bundle"`
#' file suitable for portable offline ecological analysis via
#' [vpro_import_rds()].
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param path Destination `.rds` file path.
#' @param snapshot_tag Optional snapshot identifier tag stored in `provenance`.
#'   Defaults to `provenance$snapshot_tag` when present, or the file stem of
#'   `path`.
#' @param provenance Optional named list of provenance metadata (`snapshot_tag`,
#'   `created_at`, `created_by`, `bec_version`, `taxonomy_version`,
#'   `tail_audit_hash`, `notes`).
#' @param compress Compression codec passed to [base::saveRDS()]: `"xz"`
#'   (default maximum compression) or `"gzip"` (faster write).
#' @param redact_sensitive Logical; if `TRUE`, generalizes coordinates
#'   (`Latitude`, `Longitude`, `UTMEasting`, `UTMNorthing`, `XCoord`, `YCoord`)
#'   to an ~10 km grid while preserving `UTMZone` on plots containing Red- or
#'   Blue-listed (`USysSppAttributes.RedBlueList`) species, and aborts if
#'   conservation status metadata is missing or unpopulated. Defaults to
#'   `isTRUE(attr(ws, "cloud_redacted"))`.
#' @return A list with `path`, `sha256`, `bytes`, `plot_count`, and `veg_count`.
#' @seealso [vpro_import_rds()], [vpro_master_publish_snapshot()]
#' @export
vpro_export_rds <- function(
  ws,
  path,
  snapshot_tag = NULL,
  provenance = list(),
  compress = c("xz", "gzip"),
  redact_sensitive = isTRUE(attr(ws, "cloud_redacted"))
) {
  vpro_assert_workspace(ws)
  compress <- match.arg(compress)
  redact_sensitive <- vpro_pg_validate_flag(redact_sensitive, "redact_sensitive")

  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    cli::cli_abort(
      "{.arg path} must be a single non-empty {.file .rds} file path.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (is.null(provenance)) {
    provenance <- list()
  }
  if (!is.list(provenance)) {
    cli::cli_abort(
      "{.arg provenance} must be a named {.cls list}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (!is.null(snapshot_tag) && (!is.character(snapshot_tag) || length(snapshot_tag) != 1L || is.na(snapshot_tag) || !nzchar(trimws(snapshot_tag)))) {
    cli::cli_abort(
      "{.arg snapshot_tag} must be {.code NULL} or a single non-empty character string.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }

  dest_clean <- trimws(path)
  if (!nzchar(tools::file_ext(dest_clean))) {
    dest_clean <- paste0(dest_clean, ".rds")
  }
  dest_resolved <- vpro_abs_path(dest_clean)

  if (file.exists(dest_resolved) && dir.exists(dest_resolved)) {
    cli::cli_abort(
      "{.arg path} points to an existing directory: {.path {dest_resolved}}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (vpro_is_protected_support_db(dest_resolved, con = ws) || vpro_is_bundled_package_path(dest_resolved)) {
    cli::cli_abort(
      "Refusing to write RDS snapshot onto protected or bundled package path: {.path {dest_resolved}}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }

  sens_codes <- if (isTRUE(redact_sensitive)) {
    .vpro_sensitive_species_codes(
      vlists_path = ws$vlists_path,
      extra_codes = attr(ws, "cloud_sensitive_codes"),
      require_populated = TRUE
    )
  } else {
    character(0L)
  }

  tables <- vpro_extract_workspace_snapshot_tables(ws)
  if (
    isTRUE(redact_sensitive) &&
      length(sens_codes) > 0L &&
      is.data.frame(tables$env) &&
      nrow(tables$env) > 0L &&
      is.data.frame(tables$veg) &&
      nrow(tables$veg) > 0L &&
      "Species" %in% names(tables$veg)
  ) {
    veg_spp <- toupper(trimws(as.character(tables$veg$Species)))
    sens_plots <- unique(as.character(tables$veg$PlotNumber[veg_spp %in% sens_codes]))
    if (length(sens_plots) > 0L) {
      tables$env <- .vpro_redact_coord_df(tables$env, sens_plots)
    }
  }
  plot_count <- as.integer(nrow(tables$env))
  veg_count <- as.integer(nrow(tables$veg))

  pick_chr <- function(val, default_val) {
    if (!is.null(val) && length(val) >= 1L && !is.na(val[[1L]]) && nzchar(trimws(as.character(val[[1L]])))) {
      trimws(as.character(val[[1L]]))
    } else {
      default_val
    }
  }

  resolved_tag <- if (!is.null(snapshot_tag)) {
    trimws(snapshot_tag)
  } else {
    stem <- tools::file_path_sans_ext(basename(dest_resolved))
    pick_chr(provenance$snapshot_tag, if (nzchar(stem)) stem else ws$project)
  }

  sys_user <- tryCatch(Sys.info()[["user"]], error = function(e) "")
  default_actor <- if (is.character(sys_user) && length(sys_user) == 1L && !is.na(sys_user) && nzchar(trimws(sys_user))) {
    trimws(sys_user)
  } else {
    "VProUser"
  }

  notes_val <- if (!is.null(provenance$notes) && length(provenance$notes) >= 1L && !is.na(provenance$notes[[1L]])) {
    as.character(provenance$notes[[1L]])
  } else {
    NA_character_
  }

  tail_hash <- pick_chr(provenance$tail_audit_hash, "")
  if (!nzchar(tail_hash)) {
    tail_hash <- vpro_compute_local_audit_tail_hash(tables$audit)
  }

  prov_clean <- list(
    snapshot_tag = resolved_tag,
    created_at = pick_chr(provenance$created_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    created_by = pick_chr(provenance$created_by, default_actor),
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = pick_chr(provenance$bec_version, .vpro_default_bec_version),
    taxonomy_version = pick_chr(provenance$taxonomy_version, .vpro_default_taxonomy_version),
    tail_audit_hash = tail_hash,
    notes = notes_val
  )

  bundle <- structure(
    list(
      schema_version = "VP08",
      project = as.character(ws$project),
      provenance = prov_clean,
      tables = tables
    ),
    class = "vpro_rds_bundle"
  )

  parent_dir <- dirname(dest_resolved)
  if (!dir.exists(parent_dir)) {
    dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  }

  tmp_rds <- tempfile(pattern = ".vpro-rds-snap-", tmpdir = parent_dir, fileext = ".rds")
  published <- FALSE
  on.exit(if (!published) unlink(tmp_rds, force = TRUE), add = TRUE)

  saveRDS(bundle, file = tmp_rds, compress = compress)
  if (!file.rename(tmp_rds, dest_resolved)) {
    if (file.exists(dest_resolved)) {
      unlink(dest_resolved, force = TRUE)
    }
    if (!file.rename(tmp_rds, dest_resolved)) {
      if (!file.copy(tmp_rds, dest_resolved, overwrite = TRUE)) {
        cli::cli_abort(
          "Failed to atomically write RDS snapshot to {.path {dest_resolved}}.",
          class = c("vpro_error_cloud", "vpro_error")
        )
      }
      unlink(tmp_rds, force = TRUE)
    }
  }
  published <- TRUE

  dest_final <- normalizePath(dest_resolved, winslash = "/", mustWork = TRUE)
  list(
    path = dest_final,
    sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(dest_final))))),
    bytes = file.info(dest_final)$size,
    plot_count = plot_count,
    veg_count = veg_count
  )
}

.vpro_rds_unpack_raw_object <- function(rds_norm) {
  raw_obj <- readRDS(rds_norm)

  is_bundle <- inherits(raw_obj, "vpro_rds_bundle") ||
    (is.list(raw_obj) &&
      !is.data.frame(raw_obj) &&
      is.list(raw_obj$tables) &&
      ("env" %in% tolower(names(raw_obj$tables))))
  is_desktop_list <- !is_bundle &&
    is.list(raw_obj) &&
    !is.data.frame(raw_obj) &&
    !is.null(names(raw_obj)) &&
    ("env" %in% tolower(names(raw_obj)))

  if (!is_bundle && !is_desktop_list) {
    cli::cli_abort(
      c(
        "Unsupported RDS object in {.path {rds_norm}}.",
        "i" = "Expected a {.cls vpro_rds_bundle} from {.fn vpro_export_rds} or a named list of data frames ({.field env}, {.field admin}, {.field veg}/{.field veg_long}, ...) from {.code VPro}."
      ),
      class = c("vpro_error_cloud", "vpro_error")
    )
  }

  raw_tables <- if (is_bundle) raw_obj$tables else raw_obj
  tbl_names_low <- tolower(names(raw_tables))
  fetch_tbl <- function(nm) {
    ix <- match(tolower(nm), tbl_names_low)
    if (is.na(ix)) NULL else raw_tables[[ix]]
  }

  file_stem <- tools::file_path_sans_ext(basename(rds_norm))
  raw_proj <- if (is_bundle && is.character(raw_obj$project) && length(raw_obj$project) == 1L && !is.na(raw_obj$project) && nzchar(trimws(raw_obj$project))) {
    trimws(raw_obj$project)
  } else {
    file_stem
  }
  project_name <- tryCatch(
    vpro_project_name(raw_proj),
    error = function(e) vpro_snapshot_project_prefix(raw_proj, fallback = "RDSProject", guard_reserved = FALSE)
  )

  raw_list <- list(
    env = fetch_tbl("env"),
    admin = fetch_tbl("admin"),
    veg = fetch_tbl("veg"),
    veg_long = fetch_tbl("veg_long"),
    humus = fetch_tbl("humus"),
    mineral = fetch_tbl("mineral"),
    other = fetch_tbl("other"),
    metadata = fetch_tbl("metadata"),
    audit = fetch_tbl("audit"),
    su = fetch_tbl("su"),
    lump = fetch_tbl("lump")
  )

  vpro_assert_char_plot_key(raw_list$env, "PlotNumber", "env")
  vpro_assert_char_plot_key(raw_list$admin, "Plot", "admin")
  vpro_assert_char_plot_key(raw_list$veg, "PlotNumber", "veg")
  vpro_assert_char_plot_key(raw_list$humus, "PlotNumber", "humus")
  vpro_assert_char_plot_key(raw_list$mineral, "PlotNumber", "mineral")
  vpro_assert_char_plot_key(raw_list$other, "PlotNumber", "other")
  vpro_assert_char_plot_key(raw_list$audit, "PlotNumber", "audit")

  list(
    raw_obj = raw_obj,
    is_bundle = is_bundle,
    is_desktop_list = is_desktop_list,
    file_stem = file_stem,
    project_name = project_name,
    raw = raw_list
  )
}

.vpro_rds_canonicalize_tables <- function(unpacked, su, lump) {
  raw <- unpacked$raw
  project_name <- unpacked$project_name

  canon_one <- function(df_in, suffix) {
    spec <- vpro_pg_vp08_specs(suffix)
    src <- if (is.null(df_in)) data.frame() else df_in
    out <- vpro_pg_canonicalize_to_tidy(src, spec)
    if ("PlotNumber" %in% names(out)) {
      out$PlotNumber <- as.character(out$PlotNumber)
    }
    if ("Plot" %in% names(out)) {
      out$Plot <- as.character(out$Plot)
    }
    out
  }

  env_tbl <- canon_one(raw$env, "Env")
  if (nrow(env_tbl) > 0L) {
    keep_e <- !is.na(env_tbl$PlotNumber) & nzchar(trimws(env_tbl$PlotNumber))
    env_tbl <- env_tbl[keep_e, , drop = FALSE]
    env_tbl <- env_tbl[!duplicated(env_tbl$PlotNumber), , drop = FALSE]
    env_tbl <- env_tbl[order(env_tbl$PlotNumber, method = "radix"), , drop = FALSE]
  }

  admin_tbl <- canon_one(raw$admin, "Admin")
  if (nrow(admin_tbl) > 0L) {
    keep_a <- !is.na(admin_tbl$Plot) & nzchar(trimws(admin_tbl$Plot))
    admin_tbl <- admin_tbl[keep_a, , drop = FALSE]
    admin_tbl <- admin_tbl[!duplicated(admin_tbl$Plot), , drop = FALSE]
    admin_tbl <- admin_tbl[order(admin_tbl$Plot, method = "radix"), , drop = FALSE]
  }

  veg_tbl <- if (!is.null(raw$veg)) {
    canon_one(raw$veg, "Veg")
  } else if (!is.null(raw$veg_long)) {
    vpro_pivot_veg_long_to_vp08(raw$veg_long)
  } else {
    canon_one(NULL, "Veg")
  }
  if (nrow(veg_tbl) > 0L) {
    keep_v <- !is.na(veg_tbl$PlotNumber) & nzchar(trimws(veg_tbl$PlotNumber))
    veg_tbl <- veg_tbl[keep_v, , drop = FALSE]
    veg_spec <- vpro_pg_vp08_specs("Veg")
    cov_cols <- as.character(veg_spec$name[veg_spec$is_cover])
    for (cc in intersect(cov_cols, names(veg_tbl))) {
      cv <- veg_tbl[[cc]]
      bad_cv <- !is.na(cv) & (!is.finite(cv) | cv < 0 | cv >= 100)
      if (any(bad_cv)) {
        cli::cli_abort(
          "RDS vegetation cover column {.field {cc}} contains value(s) outside [0, 100).",
          class = c("vpro_error_cloud", "vpro_error")
        )
      }
    }
  }

  filter_plot <- function(tbl) {
    if (nrow(tbl) > 0L) {
      tbl[!is.na(tbl$PlotNumber) & nzchar(trimws(tbl$PlotNumber)), , drop = FALSE]
    } else {
      tbl
    }
  }

  humus_tbl <- filter_plot(canon_one(raw$humus, "Humus"))
  mineral_tbl <- filter_plot(canon_one(raw$mineral, "Mineral"))
  other_tbl <- filter_plot(canon_one(raw$other, "Other"))
  metadata_tbl <- canon_one(raw$metadata, "Metadata")
  audit_tbl <- canon_one(raw$audit, "Audit")

  su_disabled <- vpro_is_none_selector(su)
  su_tbl <- if (is.data.frame(su)) {
    vpro_normalize_su_tibble(su)
  } else if (!is.null(raw$su)) {
    vpro_normalize_su_tibble(raw$su)
  } else {
    vpro_derive_su_from_env_admin(env_tbl, admin_tbl)
  }

  lump_disabled <- vpro_is_none_selector(lump)
  lump_tbl <- if (is.data.frame(lump)) {
    vpro_normalize_lump_tibble(lump)
  } else if (!is.null(raw$lump)) {
    vpro_normalize_lump_tibble(raw$lump)
  } else {
    vpro_normalize_lump_tibble(NULL)
  }

  su_table_name <- if (!su_disabled && nrow(su_tbl) > 0L) {
    if (is.character(su) && length(su) == 1L && !is.na(su) && nzchar(trimws(su))) {
      req_s <- trimws(su)
      if (grepl("_SU$", req_s, ignore.case = TRUE)) req_s else paste0(req_s, "_SU")
    } else {
      paste0(project_name, "_SU")
    }
  } else {
    NULL
  }

  lump_table_name <- if (!lump_disabled && nrow(lump_tbl) > 0L) {
    if (is.character(lump) && length(lump) == 1L && !is.na(lump) && nzchar(trimws(lump))) {
      req_l <- trimws(lump)
      if (grepl("_Lump$", req_l, ignore.case = TRUE)) req_l else paste0(req_l, "_Lump")
    } else {
      paste0(project_name, "_Lump")
    }
  } else {
    NULL
  }

  list(
    tables_map = list(
      Env = env_tbl,
      Admin = admin_tbl,
      Veg = veg_tbl,
      Humus = humus_tbl,
      Mineral = mineral_tbl,
      Other = other_tbl,
      Metadata = metadata_tbl,
      Audit = audit_tbl
    ),
    tables_out = list(
      env = env_tbl,
      admin = admin_tbl,
      veg = veg_tbl,
      humus = humus_tbl,
      mineral = mineral_tbl,
      other = other_tbl,
      metadata = metadata_tbl,
      audit = audit_tbl,
      su = su_tbl,
      lump = lump_tbl
    ),
    su_table_name = su_table_name,
    lump_table_name = lump_table_name
  )
}

.vpro_rds_stage_sqlite_db <- function(tmp_db, project_name, canon) {
  sq_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA foreign_keys = OFF")
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = NORMAL")

  tables_map <- canon$tables_map
  su_table_name <- canon$su_table_name
  su_tbl <- canon$tables_out$su
  lump_table_name <- canon$lump_table_name
  lump_tbl <- canon$tables_out$lump

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

    for (sfx in names(tables_map)) {
      src_tbl <- tables_map[[sfx]]
      if (nrow(src_tbl) == 0L) {
        next
      }
      spec <- vpro_pg_vp08_specs(sfx)
      dst_tbl <- paste0(project_name, "_", sfx)
      dst_fields <- DBI::dbListFields(sq_con, dst_tbl)
      sq_df <- vpro_pg_canonicalize_to_sqlite(src_tbl, spec)
      if ("PlotNumber" %in% names(sq_df)) {
        sq_df$PlotNumber <- as.character(sq_df$PlotNumber)
      }
      if ("Plot" %in% names(sq_df)) {
        sq_df$Plot <- as.character(sq_df$Plot)
      }
      bool_cols <- as.character(spec$name[!is.na(spec$is_bool) & spec$is_bool])
      for (bc in intersect(bool_cols, names(sq_df))) {
        sq_df[[bc]] <- vpro_logical_to_access(sq_df[[bc]])
      }
      if (identical(sfx, "Veg") && "Species" %in% names(sq_df)) {
        sq_df$Species <- as.character(sq_df$Species)
        sq_df$Species[is.na(sq_df$Species)] <- ""
      }
      if (sfx %in% c("Veg", "Humus", "Mineral", "Other", "Metadata") && "ID" %in% names(sq_df)) {
        sq_df$ID <- vpro_preserve_or_assign_unique_ids(
          sq_df$ID,
          start_id = if (identical(sfx, "Metadata")) 1L else 100000000L,
          require_positive = FALSE
        )
      }
      keep_cols <- intersect(dst_fields, names(sq_df))
      DBI::dbAppendTable(sq_con, dst_tbl, sq_df[, keep_cols, drop = FALSE])
    }

    for (sfx in c("Veg", "Humus", "Mineral", "Other", "Metadata", "Audit")) {
      full_tbl <- paste0(project_name, "_", sfx)
      q_full <- vpro_quote_ident(full_tbl)
      DBI::dbExecute(
        sq_con,
        paste0(
          'INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") ',
          'SELECT ?, "ID" FROM ',
          q_full,
          ' WHERE typeof("ID") = \'integer\' AND "ID" >= 0'
        ),
        params = list(q_full)
      )
    }

    if (!is.null(su_table_name)) {
      q_su <- vpro_quote_ident(su_table_name)
      DBI::dbExecute(sq_con, paste0("CREATE TABLE ", q_su, ' ("PlotNumber" TEXT, "SiteUnit" TEXT)'))
      DBI::dbAppendTable(
        sq_con,
        su_table_name,
        data.frame(
          PlotNumber = as.character(su_tbl$PlotNumber),
          SiteUnit = as.character(su_tbl$SiteUnit),
          stringsAsFactors = FALSE
        )
      )
      idx_kind <- if (anyDuplicated(su_tbl$PlotNumber) > 0L) "CREATE INDEX " else "CREATE UNIQUE INDEX "
      DBI::dbExecute(
        sq_con,
        paste0(idx_kind, vpro_quote_ident(paste0("idx_", su_table_name, "_PlotNumber")), " ON ", q_su, ' ("PlotNumber")')
      )
      DBI::dbExecute(
        sq_con,
        paste0("CREATE INDEX ", vpro_quote_ident(paste0("idx_", su_table_name, "_SiteUnit")), " ON ", q_su, ' ("SiteUnit")')
      )
      DBI::dbExecute(
        sq_con,
        'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP04\')',
        params = list(su_table_name)
      )
    }

    if (!is.null(lump_table_name)) {
      q_lump <- vpro_quote_ident(lump_table_name)
      DBI::dbExecute(
        sq_con,
        paste0("CREATE TABLE ", q_lump, ' ("LumpCode" VARCHAR(50), "SppCode" VARCHAR(8) UNIQUE, "Use" BOOLEAN)')
      )
      DBI::dbAppendTable(
        sq_con,
        lump_table_name,
        data.frame(
          LumpCode = as.character(lump_tbl$LumpCode),
          SppCode = as.character(lump_tbl$SppCode),
          Use = vpro_logical_to_access(lump_tbl$Use),
          stringsAsFactors = FALSE
        )
      )
      DBI::dbExecute(
        sq_con,
        paste0("CREATE INDEX ", vpro_quote_ident(paste0("idx_", lump_table_name, "_LumpCode")), " ON ", q_lump, ' ("LumpCode")')
      )
      DBI::dbExecute(
        sq_con,
        'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
        params = list(lump_table_name)
      )
    }

    for (idx_sql in deferred_idx) {
      DBI::dbExecute(sq_con, idx_sql)
    }
  })

  DBI::dbExecute(sq_con, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(sq_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  DBI::dbDisconnect(sq_con)
  unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)

  insp <- vpro_project_inspect(tmp_db, project_name)
  if (!isTRUE(insp$compatible)) {
    cli::cli_abort(
      "Staged RDS SQLite workspace failed {.code VP08} compatibility verification.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }

  tmp_db_norm <- normalizePath(tmp_db, winslash = "/", mustWork = TRUE)
  clean_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db_norm, flags = RSQLite::SQLITE_RW)
  tryCatch(
    {
      DBI::dbGetQuery(clean_con, "SELECT 1 FROM sqlite_master LIMIT 1")
      DBI::dbExecute(clean_con, "PRAGMA wal_checkpoint(TRUNCATE)")
    },
    finally = {
      if (DBI::dbIsValid(clean_con)) DBI::dbDisconnect(clean_con)
    }
  )
  tmp_db_norm
}

.vpro_rds_build_provenance <- function(unpacked, rds_norm, canon) {
  raw_prov <- if (unpacked$is_bundle && is.list(unpacked$raw_obj$provenance)) {
    unpacked$raw_obj$provenance
  } else {
    list()
  }
  pick_prov <- function(val, def) {
    if (!is.null(val) && length(val) >= 1L && !is.na(val[[1L]]) && nzchar(trimws(as.character(val[[1L]])))) {
      trimws(as.character(val[[1L]]))
    } else {
      def
    }
  }
  env_tbl <- canon$tables_out$env
  veg_tbl <- canon$tables_out$veg
  audit_tbl <- canon$tables_out$audit
  file_stem <- unpacked$file_stem
  project_name <- unpacked$project_name

  list(
    snapshot_tag = pick_prov(raw_prov$snapshot_tag, if (nzchar(file_stem)) file_stem else project_name),
    created_at = pick_prov(
      raw_prov$created_at,
      format(file.info(rds_norm)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    created_by = pick_prov(raw_prov$created_by, if (unpacked$is_desktop_list) "VProDesktop" else "VProUser"),
    plot_count = as.integer(nrow(env_tbl)),
    veg_count = as.integer(nrow(veg_tbl)),
    bec_version = pick_prov(raw_prov$bec_version, .vpro_default_bec_version),
    taxonomy_version = pick_prov(raw_prov$taxonomy_version, .vpro_default_taxonomy_version),
    tail_audit_hash = pick_prov(raw_prov$tail_audit_hash, vpro_compute_local_audit_tail_hash(audit_tbl)),
    notes = if (!is.null(raw_prov$notes) && length(raw_prov$notes) >= 1L && !is.na(raw_prov$notes[[1L]])) {
      as.character(raw_prov$notes[[1L]])
    } else {
      NA_character_
    }
  )
}

#' Open a portable `.rds` project snapshot as a live `vpro_workspace`
#'
#' Reads either a `"vpro_rds_bundle"` written by [vpro_export_rds()] /
#' [vpro_master_publish_snapshot()] or a named-list `.rds` bundle exported by
#' `VPro` desktop (`ExportProjectRDS` with `env`, `admin`, `veg_long`, `humus`,
#' `mineral`, `su`, `metadata`), automatically pivoting `veg_long` into the
#' canonical 44-column `VP08` `veg` schema when `veg` is absent. Enforces all
#' `VP08` domain invariants, stages a self-cleaning ephemeral SQLite `VP08`
#' database in [base::tempdir()], and returns an S3 object inheriting from
#' `"vpro_workspace"` so [vpro_env()], [vpro_veg()], [vpro_soil()],
#' [vpro_matrix()], [vpro_cluster()], [vpro_diagnostics()], [vpro_climate()],
#' [vpro_asmr()], [vpro_sf()], and [vpro_render_guide()] work out-of-the-box
#' without requiring an external database setup.
#'
#' @param path Path to an `.rds` project snapshot file.
#' @param su Optional site-unit override: `NULL` (default uses bundle `su`
#'   table), `"None"` / `FALSE` to disable active SU scoping, a custom
#'   `data.frame(PlotNumber, SiteUnit)`, or a target `*_SU` table name.
#' @param lump Optional species lump override: `NULL` (default uses bundle
#'   `lump` table), `"None"` / `FALSE` to disable active lumping, a custom
#'   `data.frame(SppCode, LumpCode, Use)`, or a target `*_Lump` table name.
#' @return An S3 object of class `c("vpro_rds_project", "vpro_workspace")`.
#' @seealso [vpro_export_rds()], [vpro_master_publish_snapshot()], [vpro_env()],
#'   [vpro_diagnostics()]
#' @export
vpro_import_rds <- function(path, su = NULL, lump = NULL) {
  .vpro_register_snap_s3()

  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    cli::cli_abort(
      "{.arg path} must be a single non-empty {.file .rds} file path.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (!file.exists(path) || dir.exists(path)) {
    cli::cli_abort(
      "RDS snapshot file does not exist: {.path {path}}.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  rds_norm <- normalizePath(path, winslash = "/", mustWork = TRUE)
  unpacked <- .vpro_rds_unpack_raw_object(rds_norm)
  project_name <- unpacked$project_name
  canon <- .vpro_rds_canonicalize_tables(unpacked, su = su, lump = lump)

  tmp_db <- tempfile(pattern = "vpro-rds-proj-", fileext = ".db")
  staged_ok <- FALSE
  on.exit(
    {
      if (!staged_ok) {
        unlink(c(tmp_db, paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)
      }
    },
    add = TRUE
  )

  tmp_db_norm <- .vpro_rds_stage_sqlite_db(tmp_db, project_name, canon)
  staged_ok <- TRUE

  cleanup_env <- new.env(parent = emptyenv())
  cleanup_env$db_path <- tmp_db_norm
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

  prov_out <- .vpro_rds_build_provenance(unpacked, rds_norm, canon)

  tmp_dir_norm <- normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
  res_obj <- structure(
    list(
      project = project_name,
      project_path = tmp_db_norm,
      su = canon$su_table_name,
      su_path = tmp_db_norm,
      hierarchy = NULL,
      hierarchy_path = tmp_db_norm,
      lump = canon$lump_table_name,
      lump_path = tmp_db_norm,
      vlists_path = vpro_bundled_db("VLists.db"),
      vuser_path = vpro_bundled_db("VUser.db"),
      vpro64_path = vpro_bundled_db("VPro64.db"),
      vmetadata_path = vpro_bundled_db("VMetaData.db"),
      data_dir = tmp_dir_norm,
      config_dir = tmp_dir_norm,
      source = "rds_snapshot",
      rds_path = rds_norm,
      provenance = prov_out,
      tables = canon$tables_out,
      .rds_cleanup = cleanup_env
    ),
    class = c("vpro_rds_project", "vpro_workspace")
  )
  attr(res_obj, "rds_cleanup") <- cleanup_env
  res_obj
}

#' @rdname vpro_import_rds
#' @param x A `vpro_rds_project` object returned by [vpro_import_rds()].
#' @param ... Unused additional arguments.
#' @export
print.vpro_rds_project <- function(x, ...) {
  prov <- if (is.list(x$provenance)) x$provenance else list()
  tag_lbl <- if (!is.null(prov$snapshot_tag) && !is.na(prov$snapshot_tag) && nzchar(prov$snapshot_tag)) {
    as.character(prov$snapshot_tag)
  } else {
    as.character(x$project)
  }
  n_plots <- if (is.list(x$tables) && is.data.frame(x$tables$env)) {
    nrow(x$tables$env)
  } else if (!is.null(prov$plot_count)) {
    as.integer(prov$plot_count)
  } else {
    0L
  }
  n_veg <- if (is.list(x$tables) && is.data.frame(x$tables$veg)) {
    nrow(x$tables$veg)
  } else if (!is.null(prov$veg_count)) {
    as.integer(prov$veg_count)
  } else {
    0L
  }
  bec_lbl <- if (!is.null(prov$bec_version) && !is.na(prov$bec_version) && nzchar(prov$bec_version)) {
    as.character(prov$bec_version)
  } else {
    .vpro_default_bec_version
  }
  tax_lbl <- if (!is.null(prov$taxonomy_version) && !is.na(prov$taxonomy_version) && nzchar(prov$taxonomy_version)) {
    as.character(prov$taxonomy_version)
  } else {
    .vpro_default_taxonomy_version
  }
  su_lbl <- if (!is.null(x$su) && nzchar(x$su)) {
    n_su <- if (is.list(x$tables) && is.data.frame(x$tables$su)) nrow(x$tables$su) else NA_integer_
    paste0(x$su, " (", n_su, " rows)")
  } else {
    "<none>"
  }
  lump_lbl <- if (!is.null(x$lump) && nzchar(x$lump)) {
    n_lmp <- if (is.list(x$tables) && is.data.frame(x$tables$lump)) nrow(x$tables$lump) else NA_integer_
    paste0(x$lump, " (", n_lmp, " rows)")
  } else {
    "<none>"
  }

  cli::cli_h3(paste0(
    "vpro_rds_project: {.val ",
    .vpro_cli_escape(tag_lbl),
    "} (project {.val ",
    .vpro_cli_escape(x$project),
    "})"
  ))
  cli::cli_bullets(c(
    "*" = "RDS snapshot: {.path {x$rds_path}}",
    "*" = .vpro_cli_escape(paste0("Records: ", n_plots, " plots, ", n_veg, " veg rows")),
    "*" = .vpro_cli_escape(paste0("Standards: BEC ", bec_lbl, " | Taxonomy ", tax_lbl)),
    "*" = .vpro_cli_escape(paste0("Active SU: ", su_lbl, " | Active Lump: ", lump_lbl))
  ))
  invisible(x)
}

#' @rdname vpro_import_rds
#' @export
as_tibble.vpro_rds_project <- function(x, ...) {
  tibble::as_tibble(x$tables$env)
}
