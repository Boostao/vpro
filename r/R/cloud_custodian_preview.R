# Custodian 3-Way Merge Preview, Cell Validation & Child ID Reservation ------

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

  disc <- .vpro_project_discover(resolved)
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
      "SELECT ",
      vpro_sqlite_select_vp08_sql(spec),
      " FROM ",
      vpro_quote_ident(tbl_nm),
      " WHERE typeof(",
      vpro_quote_ident(key_col),
      ") = 'text'"
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
    Env = "env",
    Admin = "admin",
    Veg = "veg",
    Humus = "humus",
    Mineral = "mineral",
    Other = "other"
  )

  src_tables <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  src_plots <- character(0L)
  for (suffix in .vpro_merge_table_suffixes) {
    spec <- vpro_pg_vp08_specs(suffix)
    col_csv <- paste(
      vapply(
        spec$name,
        function(cn) {
          q <- vpro_quote_ident(cn)
          if (cn %in% c("PlotNumber", "Plot")) paste0("CAST(", q, " AS TEXT) AS ", q) else q
        },
        character(1L)
      ),
      collapse = ", "
    )
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
      col_csv <- paste(
        vapply(
          spec$name,
          function(cn) {
            q <- vpro_quote_ident(cn)
            if (cn %in% c("PlotNumber", "Plot")) paste0("CAST(", q, " AS TEXT) AS ", q) else q
          },
          character(1L)
        ),
        collapse = ", "
      )
      tgt_tables[[suffix]] <- DBI::dbGetQuery(
        conn,
        paste0(
          "SELECT ",
          col_csv,
          " FROM becmaster.",
          vpro_quote_ident(pg_tbl_map[[suffix]]),
          " WHERE ",
          vpro_quote_ident(p_col),
          " = ANY($1::text[])"
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
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Staging submission ID string.
#' @param base_db Optional common ancestor `VP08` SQLite `.db` path or
#'   `vpro_workspace` handle for true 3-way diffing (`NULL` runs a 2-way diff).
#' @param base_project Optional project prefix inside `base_db` when `base_db`
#'   contains multiple `VP08` projects.
#' @return An S3 object of class `vpro_merge_preview` with `print()` and
#'   `as_tibble()` methods.
#' @export
vpro_staging_diff <- function(
  pg,
  submission_id,
  base_db = NULL,
  base_project = NULL
) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)
  .vpro_register_sync_s3()
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")
  base_info <- vpro_resolve_sqlite_base_db(base_db, base_project)
  base_tables <- vpro_load_sqlite_base_tables(base_info)

  res <- vpro_pg_exec_safe(
    function() {
      vpro_build_pg_merge_preview_on_conn(
        conn = pg$conn,
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
      cli::cli_abort("Plot {.val {plot}} {suffix}.{cn} contains invalid or unsupported text characters.")
    }
    if (u16_max > 0L && u16 > u16_max) {
      cli::cli_abort(
        "Plot {.val {plot}} {suffix}.{cn} exceeds {u16_max} characters (got {u16})."
      )
    }
  } else if (is_cov) {
    v <- suppressWarnings(as.double(raw_val[[1L]]))
    narrowed <- suppressWarnings(vpro_narrow_float32(v))
    if (is.na(v) || !is.finite(v) || v < 0 || is.na(narrowed) || narrowed < 0 || narrowed >= 100) {
      cli::cli_abort(
        "Plot {.val {plot}} {suffix}.{cn} cover={raw_val[[1L]]} must be >= 0 and strictly under 100%."
      )
    }
  }
  invisible(NULL)
}

vpro_validate_lmh25_merge_horizon <- function(suffix, horizon, upper_depth, lower_depth, plot = "") {
  if (!(suffix %in% c("Humus", "Mineral"))) {
    return(invisible(NULL))
  }
  if (is.null(upper_depth) || is.null(lower_depth) || length(upper_depth) == 0L || length(lower_depth) == 0L || is.na(upper_depth[[1L]]) || is.na(lower_depth[[1L]])) {
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
    if (identical(pg_t, "TEXT")) {
      return(NA_character_)
    }
    if (identical(pg_t, "DOUBLE PRECISION")) {
      return(NA_real_)
    }
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
      '  COALESCE((SELECT MAX("ID") FROM becmaster.',
      q_child,
      "), 0),",
      "  0",
      ") + 1) ",
      "ON CONFLICT (child_table) DO UPDATE SET ",
      "  max_id = GREATEST(",
      "    becmaster.child_identity_watermark.max_id + 1,",
      "    COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0) + 1,",
      '    COALESCE((SELECT MAX("ID") FROM becmaster.',
      q_child,
      "), 0) + 1",
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
