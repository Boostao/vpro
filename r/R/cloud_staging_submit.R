# PostgreSQL BECMaster Contributor Staging Submit & Queue Review -------------

#' Submit a local `VP08` project to PostgreSQL `BECMaster` staging
#'
#' Runs mandatory pre-flight standards, referential, `LMH25 (2023)` pedological,
#' text character-length (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`,
#' `Texture <= 4`, `Colour <= 14`, quality labels `<= 15`), and cover (`0` to
#' under `100%`) validation ([vpro_validate()] + [vpro_narrow_float32()]),
#' captures a point-in-time snapshot of the project, packages referenced
#' personal species from `VUser.db` (`USysUserSpp`) alongside active
#' `<Project>_Lump` and `*_SU` assignments, and uploads all eight `VP08` tables
#' into `staging.*` in one safe transaction.
#'
#' @param pg An active `vpro_pg_conn` connection from [vpro_master_connect()].
#' @param ws Either a `vpro_workspace` handle from [vpro_connect()] or a
#'   character project name / `.db` file path. The built-in `"Sample"` project
#'   is rejected.
#' @param submitter Non-empty character string identifying the submitting
#'   analyst or ecologist.
#' @param notes Optional character note for custodian review.
#' @param scope Plot submission scope: `"project"` (all valid plots with text
#'   `PlotNumber` keys in `<Project>_Env`) or `"su"` (restricted to plots in the
#'   active `*_SU` table).
#' @param base_snapshot_tag Optional `BECMaster` baseline snapshot tag from
#'   which the regional working copy was originally checked out.
#' @param custodian_override Logical; if `TRUE` on a `"custodian"` connection,
#'   permits staging upload when [vpro_validate()] reports blocking QA errors
#'   (recording `compliance_passed = FALSE` for custodial remediation).
#' @return A named list with `submission_id`, `project_name`, `project_id`,
#'   `submitted_by`, `db_role`, `status`, `plot_count`, `veg_row_count`,
#'   `user_species_count`, `source_db_sha256`, `compliance_passed`, and
#'   `submitted_at`.
#' @export
vpro_staging_submit <- function(
  pg,
  ws,
  submitter,
  notes = NULL,
  scope = c("project", "su"),
  base_snapshot_tag = NULL,
  custodian_override = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  scope <- match.arg(scope)
  custodian_override <- vpro_pg_validate_flag(custodian_override, "custodian_override")

  if (!is.character(submitter) || length(submitter) != 1L || is.na(submitter) || !nzchar(trimws(submitter))) {
    cli::cli_abort(
      "{.arg submitter} must be a single non-empty character string.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  submitter_clean <- trimws(submitter)
  notes_clean <- vpro_validate_optional_scalar_chr(notes, "notes")
  base_tag_clean <- vpro_validate_optional_scalar_chr(base_snapshot_tag, "base_snapshot_tag")

  ws <- if (inherits(ws, "vpro_workspace")) {
    ws
  } else if (is.character(ws) && length(ws) == 1L && !is.na(ws) && nzchar(trimws(ws))) {
    vpro_connect(ws)
  } else {
    cli::cli_abort(
      "{.arg ws} must be a {.cls vpro_workspace} handle or a single non-empty project name / SQLite path.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  vpro_assert_workspace(ws)

  if (identical(tolower(trimws(ws$project)), "sample")) {
    cli::cli_abort(
      "The built-in {.val Sample} project cannot be submitted to provincial {.code BECMaster} staging.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  if (
    identical(scope, "su") &&
      (is.null(ws$su) || !nzchar(trimws(ws$su)) || identical(tolower(trimws(ws$su)), "none"))
  ) {
    cli::cli_abort(
      "{.code scope = \"su\"} requires an active {.file *_SU} site-unit table on {.arg ws}.",
      class = c("vpro_error_cloud", "vpro_error")
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

  can_override <- isTRUE(custodian_override) && identical(pg$role, "custodian")
  if (!compliance_passed && !can_override) {
    cli::cli_abort(
      c(
        "Staging submission for project {.val {ws_snap$project}} blocked by pre-flight compliance gate ({total_blocking} blocking error{?s}).",
        "x" = "Standards/LMH25/orphan errors: {n_val_errors} (warnings: {n_val_warnings})",
        "x" = "Text length / encoding errors: {n_utf16_errors}",
        "x" = "Vegetation cover (0 to under 100%) errors: {n_cover_errors}",
        "i" = "Inspect violations with {.fn vpro_validate} and resolve errors before calling {.fn vpro_staging_submit}."
      ),
      class = c("vpro_error_cloud", "vpro_error")
    )
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
      DBI::dbWithTransaction(pg$conn, {
        role_df <- DBI::dbGetQuery(
          pg$conn,
          "SELECT current_user AS db_role, to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS now_utc"
        )
        cur_role <- as.character(role_df$db_role[[1L]])
        now_utc <- as.character(role_df$now_utc[[1L]])

        DBI::dbExecute(
          pg$conn,
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
          if (nrow(df_t) == 0L) {
            next
          }
          df_sub <- cbind(
            data.frame(submission_id = rep(submission_id, nrow(df_t)), stringsAsFactors = FALSE),
            df_t
          )
          rownames(df_sub) <- NULL
          DBI::dbAppendTable(
            pg$conn,
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
#' @param pg A `vpro_pg_conn` handle from [vpro_master_connect()].
#' @param status Queue status filter: `"pending"` (default), `"approved"`,
#'   `"rejected"`, `"merged"`, or `NULL` / `"all"` to return all statuses.
#' @param submitted_by Optional submitter name filter (`submitted_by = $n`).
#' @param limit Positive integer maximum rows to return (default `100L`).
#' @return A tibble of class `vpro_staging_queue` summarizing matching
#'   submissions.
#' @export
vpro_staging_list <- function(
  pg,
  status = "pending",
  submitted_by = NULL,
  limit = 100L
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  .vpro_register_sync_s3()
  limit_int <- vpro_pg_validate_limit(limit, allow_null = FALSE)

  clauses <- character(0L)
  param_state <- new.env(parent = emptyenv())
  param_state$params <- list()
  next_param <- function(val) {
    param_state$params[[length(param_state$params) + 1L]] <- val
    paste0("$", length(param_state$params))
  }

  if (!is.null(status)) {
    if (!is.character(status) || length(status) != 1L || is.na(status)) {
      cli::cli_abort(
        "{.arg status} must be {.code NULL}, {.val all}, or one of {.val pending}, {.val approved}, {.val rejected}, {.val merged}.",
        class = c("vpro_error_cloud", "vpro_error")
      )
    }
    st_clean <- tolower(trimws(status))
    if (nzchar(st_clean) && !identical(st_clean, "all")) {
      valid_st <- c("pending", "approved", "rejected", "merged")
      if (!(st_clean %in% valid_st)) {
        cli::cli_abort(
          "{.arg status} must be {.code NULL}, {.val all}, or one of {.or {.val {valid_st}}}.",
          class = c("vpro_error_cloud", "vpro_error")
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
    " ORDER BY submitted_at DESC LIMIT ",
    lim_p
  )

  df <- vpro_pg_query(pg, sql, params = param_state$params, action = "list staging.submissions")
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
    summary_str <- paste(parts, collapse = ", ")
    cli::cli_h3(paste0("vpro_staging_queue ({n} submission{?s}: ", .vpro_cli_escape(summary_str), ")"))
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
#' @param pg A `vpro_pg_conn` handle from [vpro_master_connect()].
#' @param submission_id Staging submission ID string.
#' @return A list with `summary` (1-row `vpro_staging_queue` tibble),
#'   `compliance_report` (parsed list), `user_species` (tibble),
#'   `provisional_diffs` (tibble), `lump` (tibble), and `su` (tibble).
#' @export
vpro_staging_inspect <- function(pg, submission_id) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")

  sql <- paste0(
    "SELECT sub.*, ",
    "  s_raw.compliance_report::text AS compliance_report_raw, ",
    "  s_raw.user_species_manifest::text AS user_species_manifest_raw, ",
    "  s_raw.lump_rows::text AS lump_rows_raw, ",
    "  s_raw.su_rows::text AS su_rows_raw ",
    "FROM (",
    .vpro_staging_summary_select_sql,
    " WHERE submission_id = $1::uuid) AS sub ",
    "INNER JOIN staging.submissions AS s_raw ON s_raw.submission_id::text = sub.submission_id"
  )
  df <- vpro_pg_query(pg, sql, params = list(sub_id), action = "inspect staging submission")
  if (nrow(df) == 0L) {
    cli::cli_abort(
      "Staging submission {.val {sub_id}} was not found.",
      class = c("vpro_error_cloud", "vpro_error")
    )
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
          pg,
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
        if (!nzchar(cu)) {
          next
        }
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
      SiteUnit = vapply(
        su_parsed,
        function(r) {
          if (is.null(r$siteUnit) || length(r$siteUnit) == 0L || is.na(r$siteUnit[[1L]])) {
            NA_character_
          } else {
            as.character(r$siteUnit[[1L]])
          }
        },
        character(1L)
      )
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

# Custodian Queue Review & Rejection -------------------------------------------

#' Reject a pending staging submission with custodian review notes
#'
#' Marks a `"pending"` submission in `staging.submissions` as `"rejected"`,
#' recording `reviewer_notes`, `reviewed_by`, and `reviewed_at`.
#'
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Pending staging submission ID string.
#' @param reviewer_notes Non-empty character string explaining why the
#'   submission was rejected.
#' @param actor Optional custodian reviewer name (defaults to PostgreSQL
#'   `current_user`).
#' @return A 1-row `vpro_staging_queue` tibble containing the updated submission
#'   record.
#' @export
vpro_staging_reject <- function(pg, submission_id, reviewer_notes, actor = NULL) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)
  .vpro_register_sync_s3()
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")

  if (!is.character(reviewer_notes) || length(reviewer_notes) != 1L || is.na(reviewer_notes) || !nzchar(trimws(reviewer_notes))) {
    cli::cli_abort(
      "{.arg reviewer_notes} must be a single non-empty character string.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }
  notes_clean <- trimws(reviewer_notes)
  actor_clean <- vpro_validate_optional_scalar_chr(actor, "actor")
  actor_param <- if (is.na(actor_clean)) "" else actor_clean

  aff <- vpro_pg_execute(
    pg,
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
      "Staging submission {.val {sub_id}} is not in {.val pending} status or does not exist.",
      class = c("vpro_error_cloud", "vpro_error")
    )
  }

  row_df <- vpro_pg_query(
    pg,
    paste0(.vpro_staging_summary_select_sql, " WHERE submission_id = $1::uuid"),
    params = list(sub_id),
    action = "fetch rejected staging submission"
  )
  vpro_format_staging_queue_df(row_df)
}
