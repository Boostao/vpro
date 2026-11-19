# BECMaster Cloud Snapshot CSV Bundle & Publication --------------------------

vpro_write_snapshot_csv_bundle <- function(ws, snapshot_tag, out_dir_abs, provenance, overwrite = FALSE, redact_sensitive = FALSE) {
  overwrite <- vpro_pg_validate_flag(overwrite, "overwrite")
  redact_sensitive <- vpro_pg_validate_flag(redact_sensitive, "redact_sensitive")
  csv_dir <- file.path(out_dir_abs, paste0(snapshot_tag, "_csv"))
  tar_path <- file.path(out_dir_abs, paste0(snapshot_tag, "_csv.tar.gz"))

  if ((dir.exists(csv_dir) || file.exists(csv_dir) || file.exists(tar_path)) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Snapshot CSV output already exists (pass {.code overwrite = TRUE} to replace): {.path {tar_path}}."
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

  if (dir.exists(csv_dir) || file.exists(csv_dir)) {
    unlink(csv_dir, recursive = TRUE, force = TRUE)
  }
  if (file.exists(tar_path)) {
    unlink(tar_path, force = TRUE)
  }

  dir.create(csv_dir, recursive = TRUE, showWarnings = FALSE)
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

  csv_targets <- list(
    env = tables$env,
    admin = tables$admin,
    veg = tables$veg,
    humus = tables$humus,
    mineral = tables$mineral,
    other = tables$other,
    metadata = tables$metadata,
    su = tables$su
  )

  file_entries <- vector("list", length(csv_targets))
  nms <- names(csv_targets)
  for (i in seq_along(nms)) {
    nm <- nms[[i]]
    df <- as.data.frame(csv_targets[[nm]], stringsAsFactors = FALSE, check.names = FALSE)
    fname <- paste0(nm, ".csv")
    fpath <- file.path(csv_dir, fname)
    utils::write.csv(
      df,
      file = fpath,
      row.names = FALSE,
      na = "",
      quote = TRUE,
      fileEncoding = "UTF-8"
    )
    f_norm <- normalizePath(fpath, winslash = "/", mustWork = TRUE)
    file_entries[[i]] <- list(
      file = fname,
      rows = as.integer(nrow(df)),
      columns = as.integer(ncol(df)),
      sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(f_norm))))),
      bytes = as.double(file.info(f_norm)$size)
    )
  }

  manifest_obj <- list(
    schema_version = "VP08",
    snapshot_tag = as.character(snapshot_tag),
    project = as.character(ws$project),
    created_at = as.character(provenance$created_at),
    created_by = as.character(provenance$created_by),
    plot_count = as.integer(provenance$plot_count),
    veg_count = as.integer(provenance$veg_count),
    bec_version = as.character(provenance$bec_version),
    taxonomy_version = as.character(provenance$taxonomy_version),
    tail_audit_hash = as.character(provenance$tail_audit_hash),
    notes = if (is.na(provenance$notes)) NULL else as.character(provenance$notes),
    files = file_entries
  )
  manifest_path <- file.path(csv_dir, "manifest.json")
  jsonlite::write_json(
    manifest_obj,
    path = manifest_path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )

  tmp_tar <- tempfile(pattern = ".vpro-csv-snap-", tmpdir = out_dir_abs, fileext = ".tar.gz")
  published <- FALSE
  on.exit(if (!published) unlink(tmp_tar, force = TRUE), add = TRUE)

  old_wd <- getwd()
  tar_status <- tryCatch(
    {
      setwd(out_dir_abs)
      utils::tar(
        tarfile = tmp_tar,
        files = basename(csv_dir),
        compression = "gzip"
      )
    },
    finally = {
      setwd(old_wd)
    }
  )
  if (!identical(as.integer(tar_status), 0L) || !file.exists(tmp_tar)) {
    cli::cli_abort("Failed to create gzipped CSV snapshot archive {.path {tar_path}}.")
  }

  if (!file.rename(tmp_tar, tar_path)) {
    if (!file.copy(tmp_tar, tar_path, overwrite = TRUE)) {
      cli::cli_abort("Failed to publish CSV snapshot archive {.path {tar_path}}.")
    }
    unlink(tmp_tar, force = TRUE)
  }
  published <- TRUE

  tar_final <- normalizePath(tar_path, winslash = "/", mustWork = TRUE)
  list(
    csv_dir = normalizePath(csv_dir, winslash = "/", mustWork = TRUE),
    path = tar_final,
    sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(tar_final))))),
    bytes = file.info(tar_final)$size
  )
}

#' Publish a custodian `BECMaster` snapshot and multi-format release artifacts
#'
#' Requires a custodian PostgreSQL connection (`pg$role == "custodian"`).
#' Pulls a snapshot-consistent release from `becmaster.*`, writes the
#' requested release artifacts (`"rds"`, `"sqlite"`, `"gpkg"` in `EPSG:3005`,
#' and/or `"csv"` directory + `.tar.gz` bundle) into `out_dir`, computes a
#' deterministic SHA-256 manifest digest across artifact hashes, counts, and
#' active standards versions, and upserts the release record into
#' `becmaster.snapshots` matching VPro Desktop.
#'
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`).
#' @param snapshot_tag Snapshot release identifier (`1..80` ASCII characters
#'   matching `^[A-Za-z0-9._-]{1,80}$`, e.g. `"BECMaster_2026_11"`).
#' @param out_dir Output directory where snapshot artifact files are written
#'   (created recursively if absent).
#' @param formats Non-empty character subset of `c("rds", "sqlite", "gpkg", "csv")`.
#' @param notes Optional release notes recorded in `becmaster.snapshots`.
#' @param zones Optional BEC zone filter passed to the snapshot pull.
#' @param subzones Optional BEC subzone/variant filter.
#' @param project_ids Optional `ProjectID` filter.
#' @param plots Optional literal character `PlotNumber` filter.
#' @param bbox Optional spatial bounding box (`c(min_lon, min_lat, max_lon, max_lat)`
#'   in `EPSG:4326` or an `sf` `bbox` object).
#' @param compress Compression codec for `.rds` output (`"xz"` or `"gzip"`).
#' @param overwrite Logical; if `TRUE`, replaces existing local artifacts and
#'   updates an existing `snapshot_tag` row in `becmaster.snapshots`.
#' @param redact_sensitive Logical; if `TRUE`, generalizes coordinates to an
#'   ~10 km grid (preserving `UTMZone`) on plots containing Red- or Blue-listed
#'   (`USysSppAttributes.RedBlueList`) species across generated artifacts, and
#'   aborts if conservation status metadata is missing or unpopulated.
#' @return A structured list with `snapshot_tag`, `created_at`, `created_by`,
#'   `plot_count`, `veg_count`, `bec_version`, `taxonomy_version`,
#'   `manifest_sha256`, `notes`, and an `artifacts` tibble (`format`, `path`,
#'   `sha256`, `bytes`).
#' @seealso [vpro_master_list_snapshots()], [vpro_export_rds()],
#'   [vpro_import_rds()], [vpro_export_gpkg()]
#' @export
vpro_master_publish_snapshot <- function(
  pg,
  snapshot_tag,
  out_dir,
  formats = c("rds", "sqlite", "gpkg", "csv"),
  notes = NULL,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  compress = c("xz", "gzip"),
  overwrite = FALSE,
  redact_sensitive = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)
  tag <- vpro_validate_snapshot_tag(snapshot_tag, "snapshot_tag")
  overwrite <- vpro_pg_validate_flag(overwrite, "overwrite")
  redact_sensitive <- vpro_pg_validate_flag(redact_sensitive, "redact_sensitive")
  compress <- match.arg(compress)

  if (!is.null(notes) && (!is.character(notes) || length(notes) != 1L)) {
    cli::cli_abort("{.arg notes} must be {.code NULL} or a single character string.")
  }
  notes_clean <- if (is.null(notes) || is.na(notes[[1L]]) || !nzchar(trimws(notes[[1L]]))) {
    NA_character_
  } else {
    trimws(notes[[1L]])
  }

  if (!is.character(formats) || length(formats) == 0L || anyNA(formats)) {
    cli::cli_abort(
      "{.arg formats} must be a non-empty subset of {.or {.val {.vpro_valid_snapshot_formats}}}."
    )
  }
  req_formats <- unique(tolower(trimws(formats)))
  bad_fmt <- setdiff(req_formats, .vpro_valid_snapshot_formats)
  if (length(bad_fmt) > 0L || length(req_formats) == 0L) {
    cli::cli_abort(
      "Unsupported snapshot format(s) {.val {bad_fmt}} (expected subset of {.or {.val {.vpro_valid_snapshot_formats}}})."
    )
  }
  if ("gpkg" %in% req_formats) {
    rlang::check_installed("sf", reason = "to export EPSG:3005 GeoPackage snapshots.")
  }

  if (!is.character(out_dir) || length(out_dir) != 1L || is.na(out_dir) || !nzchar(trimws(out_dir))) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  out_dir_abs <- vpro_abs_path(trimws(out_dir))
  if (file.exists(out_dir_abs) && !dir.exists(out_dir_abs)) {
    cli::cli_abort("{.arg out_dir} points to an existing file rather than a directory: {.path {out_dir_abs}}.")
  }
  if (vpro_is_bundled_package_path(out_dir_abs)) {
    cli::cli_abort("Refusing to publish snapshots inside installed package path: {.path {out_dir_abs}}.")
  }
  if (isTRUE(redact_sensitive)) {
    .vpro_sensitive_species_codes(pg = pg, require_populated = TRUE)
  }
  if (!dir.exists(out_dir_abs)) {
    dir.create(out_dir_abs, recursive = TRUE, showWarnings = FALSE)
  }
  out_dir_abs <- normalizePath(out_dir_abs, winslash = "/", mustWork = TRUE)

  rds_dest <- file.path(out_dir_abs, paste0(tag, ".rds"))
  sqlite_dest <- file.path(out_dir_abs, paste0(tag, ".db"))
  gpkg_dest <- file.path(out_dir_abs, paste0(tag, ".gpkg"))
  csv_dir_dest <- file.path(out_dir_abs, paste0(tag, "_csv"))
  csv_tar_dest <- file.path(out_dir_abs, paste0(tag, "_csv.tar.gz"))

  if ("sqlite" %in% req_formats && (file.exists(paste0(sqlite_dest, "-wal")) || file.exists(paste0(sqlite_dest, "-shm")))) {
    cli::cli_abort(
      "Refusing to write {.path {sqlite_dest}} while it is open in another VPro or database session."
    )
  }

  if (!isTRUE(overwrite)) {
    planned <- character()
    if ("rds" %in% req_formats) {
      planned <- c(planned, rds_dest)
    }
    if ("sqlite" %in% req_formats) {
      planned <- c(planned, sqlite_dest)
    }
    if ("gpkg" %in% req_formats) {
      planned <- c(planned, gpkg_dest)
    }
    if ("csv" %in% req_formats) {
      planned <- c(planned, csv_tar_dest, csv_dir_dest)
    }
    existing <- planned[file.exists(planned) | dir.exists(planned)]
    if (length(existing) > 0L) {
      cli::cli_abort(
        "Destination snapshot artifact(s) already exist (pass {.code overwrite = TRUE} to replace): {.path {existing}}."
      )
    }
  }

  snap_proj_name <- vpro_snapshot_project_prefix(
    tag,
    fallback = "Snap_BEC",
    guard_reserved = TRUE
  )

  is_full <- length(vpro_pg_clean_tokens(zones, "zones")) == 0L &&
    length(vpro_pg_clean_tokens(subzones, "subzones")) == 0L &&
    length(vpro_pg_clean_tokens(project_ids, "project_ids")) == 0L &&
    length(vpro_pg_clean_tokens(plots, "plots")) == 0L &&
    is.null(bbox)

  want_sqlite <- "sqlite" %in% req_formats
  stage_dir <- NULL
  if (!want_sqlite) {
    stage_dir <- tempfile(pattern = "vpro-snap-stage-")
    dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)
    stage_sqlite_path <- file.path(stage_dir, paste0(snap_proj_name, ".db"))
  } else {
    stage_sqlite_path <- sqlite_dest
  }

  pull_res <- vpro_master_pull_impl(
    pg = pg,
    dest_path = stage_sqlite_path,
    project_name = snap_proj_name,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = if (want_sqlite) overwrite else TRUE,
    allow_full = is_full,
    log_download = TRUE,
    allow_reserved_name = TRUE,
    redact_sensitive = isTRUE(redact_sensitive)
  )

  ws_snap <- pull_res$workspace
  plot_count <- as.integer(pull_res$plot_count)
  veg_count <- as.integer(pull_res$veg_count)

  bec_version <- if (!is.null(pull_res$snapshot_meta$bec_version)) {
    pull_res$snapshot_meta$bec_version
  } else {
    .vpro_default_bec_version
  }
  taxonomy_version <- if (!is.null(pull_res$snapshot_meta$taxonomy_version)) {
    pull_res$snapshot_meta$taxonomy_version
  } else {
    .vpro_default_taxonomy_version
  }
  tail_audit_hash <- if (!is.null(pull_res$snapshot_meta$tail_audit_hash)) {
    pull_res$snapshot_meta$tail_audit_hash
  } else {
    .vpro_genesis_audit_hash
  }

  usr_df <- tryCatch(
    vpro_pg_query(pg, "SELECT current_user AS usr", params = NULL, action = "read current_user"),
    error = function(e) data.frame()
  )
  pg_actor <- if (nrow(usr_df) >= 1L && !is.na(usr_df$usr[[1L]]) && nzchar(trimws(as.character(usr_df$usr[[1L]])))) {
    trimws(as.character(usr_df$usr[[1L]]))
  } else if (!is.null(pg$user) && nzchar(trimws(as.character(pg$user)))) {
    trimws(as.character(pg$user))
  } else {
    "VProCustodian"
  }
  created_at_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  prov_meta <- list(
    snapshot_tag = tag,
    created_at = created_at_iso,
    created_by = pg_actor,
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    tail_audit_hash = tail_audit_hash,
    notes = notes_clean
  )

  art_rows <- vector("list", length(req_formats))
  for (i in seq_along(req_formats)) {
    fmt <- req_formats[[i]]
    if (identical(fmt, "sqlite")) {
      art_rows[[i]] <- tibble::tibble(
        format = "sqlite",
        path = pull_res$dest_path,
        sha256 = tolower(trimws(as.character(pull_res$sha256))),
        bytes = as.double(file.info(pull_res$dest_path)$size)
      )
    } else if (identical(fmt, "rds")) {
      rds_res <- vpro_export_rds(
        ws = ws_snap,
        path = rds_dest,
        snapshot_tag = tag,
        provenance = prov_meta,
        compress = compress,
        redact_sensitive = isTRUE(redact_sensitive)
      )
      art_rows[[i]] <- tibble::tibble(
        format = "rds",
        path = rds_res$path,
        sha256 = rds_res$sha256,
        bytes = as.double(rds_res$bytes)
      )
    } else if (identical(fmt, "gpkg")) {
      gpkg_written <- vpro_export_gpkg(
        ws_snap,
        path = gpkg_dest,
        crs = 3005,
        scope = "project",
        overwrite = overwrite
      )
      unlink(c(paste0(gpkg_written, "-wal"), paste0(gpkg_written, "-shm")), force = TRUE)
      gpkg_norm <- normalizePath(gpkg_written, winslash = "/", mustWork = TRUE)
      art_rows[[i]] <- tibble::tibble(
        format = "gpkg",
        path = gpkg_norm,
        sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(gpkg_norm))))),
        bytes = as.double(file.info(gpkg_norm)$size)
      )
    } else if (identical(fmt, "csv")) {
      csv_res <- vpro_write_snapshot_csv_bundle(
        ws = ws_snap,
        snapshot_tag = tag,
        out_dir_abs = out_dir_abs,
        provenance = prov_meta,
        overwrite = overwrite,
        redact_sensitive = isTRUE(redact_sensitive)
      )
      art_rows[[i]] <- tibble::tibble(
        format = "csv",
        path = csv_res$path,
        sha256 = csv_res$sha256,
        bytes = as.double(csv_res$bytes)
      )
    }
  }

  artifacts_tbl <- do.call(rbind, art_rows)
  ord_fmt <- order(artifacts_tbl$format, method = "radix")
  art_sig <- paste(
    paste0(artifacts_tbl$format[ord_fmt], ":", tolower(artifacts_tbl$sha256[ord_fmt])),
    collapse = ","
  )
  manifest_payload <- sprintf(
    "%s|%d|%d|%s|%s|%s|%s",
    tag,
    plot_count,
    veg_count,
    bec_version,
    taxonomy_version,
    tail_audit_hash,
    art_sig
  )
  manifest_sha256 <- tolower(vpro_sha256_utf8(manifest_payload)[[1L]])

  upsert_sql <- paste(
    "INSERT INTO becmaster.snapshots (",
    "  snapshot_tag, created_at, created_by, plot_count, veg_count,",
    "  bec_version, taxonomy_version, manifest_sha256, notes",
    ") VALUES ($1, now(), current_user, $2, $3, $4, $5, $6, $7)",
    "ON CONFLICT (snapshot_tag) DO UPDATE SET",
    "  created_at = EXCLUDED.created_at,",
    "  created_by = EXCLUDED.created_by,",
    "  plot_count = EXCLUDED.plot_count,",
    "  veg_count = EXCLUDED.veg_count,",
    "  bec_version = EXCLUDED.bec_version,",
    "  taxonomy_version = EXCLUDED.taxonomy_version,",
    "  manifest_sha256 = EXCLUDED.manifest_sha256,",
    "  notes = EXCLUDED.notes",
    "RETURNING",
    "  snapshot_tag,",
    "  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS created_at,",
    "  created_by"
  )

  up_df <- vpro_pg_query(
    pg,
    upsert_sql,
    params = list(
      tag,
      plot_count,
      veg_count,
      bec_version,
      taxonomy_version,
      manifest_sha256,
      notes_clean
    ),
    action = "upsert becmaster.snapshots record"
  )

  final_created_at <- if (nrow(up_df) >= 1L && !is.na(up_df$created_at[[1L]])) {
    as.character(up_df$created_at[[1L]])
  } else {
    created_at_iso
  }
  final_created_by <- if (nrow(up_df) >= 1L && !is.na(up_df$created_by[[1L]])) {
    as.character(up_df$created_by[[1L]])
  } else {
    pg_actor
  }

  list(
    snapshot_tag = tag,
    created_at = final_created_at,
    created_by = final_created_by,
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    manifest_sha256 = manifest_sha256,
    notes = notes_clean,
    artifacts = artifacts_tbl
  )
}

#' List published `BECMaster` snapshots from PostgreSQL
#'
#' Queries `becmaster.snapshots` ordered newest-first (`created_at DESC`) and
#' returns a tidy tibble matching `ListBECMasterSnapshots` in `vpro`.
#'
#' @param pg A `vpro_pg_conn` connection handle.
#' @param limit Positive integer maximum number of snapshot rows to return
#'   (defaults to `100L`).
#' @return A tibble with `snapshot_tag`, `created_at`, `created_by`,
#'   `plot_count`, `veg_count`, `bec_version`, `taxonomy_version`,
#'   `manifest_sha256`, and `notes`.
#' @seealso [vpro_master_publish_snapshot()], [vpro_import_rds()]
#' @export
vpro_master_list_snapshots <- function(pg, limit = 100L) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  limit_int <- vpro_pg_validate_limit(limit, allow_null = FALSE)

  sql <- paste(
    "SELECT",
    "  snapshot_tag,",
    "  created_at,",
    "  created_by,",
    "  plot_count,",
    "  veg_count,",
    "  bec_version,",
    "  taxonomy_version,",
    "  manifest_sha256,",
    "  notes",
    "FROM becmaster.snapshots",
    "ORDER BY created_at DESC, snapshot_tag DESC",
    "LIMIT $1"
  )
  df <- vpro_pg_query(
    pg,
    sql,
    params = list(as.integer(limit_int)),
    action = "list becmaster.snapshots"
  )

  if (nrow(df) == 0L) {
    return(tibble::tibble(
      snapshot_tag = character(),
      created_at = as.POSIXct(character(), tz = "UTC"),
      created_by = character(),
      plot_count = integer(),
      veg_count = integer(),
      bec_version = character(),
      taxonomy_version = character(),
      manifest_sha256 = character(),
      notes = character()
    ))
  }

  veg_dbl <- suppressWarnings(as.double(as.character(df$veg_count)))
  veg_col <- if (all(is.na(veg_dbl) | abs(veg_dbl) <= .Machine$integer.max)) {
    as.integer(veg_dbl)
  } else {
    veg_dbl
  }

  ts_col <- if (inherits(df$created_at, "POSIXt")) {
    as.POSIXct(df$created_at, tz = "UTC")
  } else {
    as.POSIXct(as.character(df$created_at), tz = "UTC")
  }

  tibble::tibble(
    snapshot_tag = as.character(df$snapshot_tag),
    created_at = ts_col,
    created_by = as.character(df$created_by),
    plot_count = suppressWarnings(as.integer(as.character(df$plot_count))),
    veg_count = veg_col,
    bec_version = as.character(df$bec_version),
    taxonomy_version = as.character(df$taxonomy_version),
    manifest_sha256 = as.character(df$manifest_sha256),
    notes = as.character(df$notes)
  )
}
