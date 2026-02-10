# Publish pipeline helpers

publish_becmaster_rds <- function(con,
                                 out_dir,
                                 version = NULL,
                                 project_ids = NULL,
                                 apply_lumping = TRUE,
                                 created_by = Sys.getenv("USER", "unknown"),
                                 environment = NULL,
                                 allow_attach = TRUE) {
  if (is.null(out_dir) || !nzchar(out_dir)) {
    stop("Output directory is required for RDS publishing.")
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sync_require_cloud(con, environment = environment, allow_attach = allow_attach)

  filters <- c("a.qa_status = 'approved'")
  params <- list()
  if (!is.null(project_ids) && length(project_ids) > 0) {
    placeholders <- paste(rep("?", length(project_ids)), collapse = ", ")
    filters <- c(filters, paste0("a.project_id IN (", placeholders, ")"))
    params <- c(params, as.list(project_ids))
  }
  where_clause <- paste("WHERE", paste(filters, collapse = " AND "))

  veg_sql <- paste(
    "SELECT v.plotnumber, v.mylayer, v.species, v.cover",
    "FROM master.core.vw_usysallveg v",
    "JOIN master.core.sample_admin a ON v.plotnumber = a.plot_number",
    where_clause
  )
  veg <- DBI::dbGetQuery(con, veg_sql, params)

  env_sql <- paste(
    "SELECT e.plot_number AS plotnumber, e.project_id, e.latitude, e.longitude,",
    "e.elevation_m, e.survey_date, e.surveyor_name, e.plot_notes,",
    "s.su_number, s.bec_zone, s.bec_subzone, s.site_series",
    "FROM master.core.sample_env e",
    "JOIN master.core.sample_admin a ON e.plot_number = a.plot_number",
    "LEFT JOIN master.core.sample_su s ON e.plot_number = s.plot_number",
    where_clause
  )
  env <- DBI::dbGetQuery(con, env_sql, params)

  if (nrow(veg) > 0) {
    veg$cover_num <- suppressWarnings(as.numeric(veg$cover))
    veg$cover_num[is.na(veg$cover_num) & !is.na(veg$cover)] <- 0
    if (isTRUE(apply_lumping)) {
      veg <- apply_lumping(con, veg, group_cols = c("plotnumber", "mylayer"), measure_cols = "cover_num")
    }
    veg$col_name <- paste0(veg$species, "_", veg$mylayer)
    veg_wide <- veg[, c("plotnumber", "col_name", "cover_num"), drop = FALSE]
    veg_wide <- tidyr::pivot_wider(
      veg_wide,
      names_from = "col_name",
      values_from = "cover_num",
      values_fill = 0
    )
  } else {
    veg_wide <- data.frame(plotnumber = character(0), stringsAsFactors = FALSE)
  }

  if (is.null(version) || !nzchar(version)) {
    version <- format(Sys.time(), "%Y%m%d_%H%M%S")
  }

  veg_file <- file.path(out_dir, paste0("becmaster_veg_", version, ".rds"))
  env_file <- file.path(out_dir, paste0("becmaster_env_", version, ".rds"))

  saveRDS(veg_wide, veg_file)
  saveRDS(env, env_file)

  md5_veg <- as.character(tools::md5sum(veg_file))
  md5_env <- as.character(tools::md5sum(env_file))

  snapshot_meta <- list(
    project_ids = project_ids,
    qa_status = "approved",
    apply_lumping = isTRUE(apply_lumping)
  )
  snapshot_json <- if (requireNamespace("jsonlite", quietly = TRUE)) {
    jsonlite::toJSON(snapshot_meta, auto_unbox = TRUE, null = "null")
  } else {
    NA_character_
  }

  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO master.public_export.rds_snapshots",
      " (version, snapshot_date, created_by, rds_filename_veg, rds_filename_env,",
      " veg_row_count, env_row_count, md5_hash_veg, md5_hash_env, snapshot_metadata)",
      " VALUES (?, CURRENT_DATE, ?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    list(
      version,
      created_by,
      basename(veg_file),
      basename(env_file),
      nrow(veg_wide),
      nrow(env),
      md5_veg,
      md5_env,
      snapshot_json
    )
  )

  list(
    version = version,
    veg_path = veg_file,
    env_path = env_file,
    veg_rows = nrow(veg_wide),
    env_rows = nrow(env)
  )
}

publish_snapshot <- function(con,
                             out_dir,
                             version = NULL,
                             project_ids = NULL,
                             apply_lumping = TRUE,
                             created_by = Sys.getenv("USER", "unknown"),
                             environment = NULL,
                             allow_attach = TRUE) {
  publish_becmaster_rds(
    con = con,
    out_dir = out_dir,
    version = version,
    project_ids = project_ids,
    apply_lumping = apply_lumping,
    created_by = created_by,
    environment = environment,
    allow_attach = allow_attach
  )
}

log_export_download <- function(con,
                                dataset_name,
                                format,
                                filters_applied = NULL,
                                row_count = NULL,
                                user_id = NULL,
                                username = NULL,
                                download_status = "success",
                                error_message = NULL,
                                ip_address = NULL,
                                environment = NULL,
                                allow_attach = TRUE) {
  allowed_formats <- c("rds", "csv", "excel", "xml")
  if (is.null(dataset_name) || !nzchar(dataset_name)) return(FALSE)
  if (!(format %in% allowed_formats)) return(FALSE)

  filters_json <- NULL
  if (!is.null(filters_applied) && requireNamespace("jsonlite", quietly = TRUE)) {
    filters_json <- jsonlite::toJSON(filters_applied, auto_unbox = TRUE, null = "null")
  }

  result <- tryCatch({
    sync_require_cloud(con, environment = environment, allow_attach = allow_attach)
    DBI::dbExecute(
      con,
      paste0(
        "INSERT INTO master.public_export.download_log",
        " (user_id, username, dataset_name, format, filters_applied,",
        " row_count, ip_address, download_status, error_message)",
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      list(
        user_id,
        username %||% "anonymous",
        dataset_name,
        format,
        filters_json,
        row_count,
        ip_address,
        download_status,
        error_message
      )
    )
    TRUE
  }, error = function(e) FALSE)

  result
}

build_download_log_query <- function(filters = list(), limit = 1000L) {
  clauses <- character(0)
  params <- list()

  user_filter <- trimws(as.character(filters$user %||% ""))
  dataset_filter <- trimws(as.character(filters$dataset %||% ""))
  format_filter <- trimws(as.character(filters$format %||% ""))
  status_filter <- trimws(as.character(filters$status %||% ""))
  from_value <- filters$from
  to_value <- filters$to

  if (nzchar(user_filter)) {
    clauses <- c(clauses, "username ILIKE ?")
    params <- c(params, list(paste0("%", user_filter, "%")))
  }
  if (nzchar(dataset_filter)) {
    clauses <- c(clauses, "dataset_name ILIKE ?")
    params <- c(params, list(paste0("%", dataset_filter, "%")))
  }
  if (nzchar(format_filter)) {
    clauses <- c(clauses, "format = ?")
    params <- c(params, list(format_filter))
  }
  if (nzchar(status_filter)) {
    clauses <- c(clauses, "download_status = ?")
    params <- c(params, list(status_filter))
  }
  if (!is.null(from_value) && !is.na(from_value)) {
    clauses <- c(clauses, "timestamp_utc >= ?")
    params <- c(params, list(from_value))
  }
  if (!is.null(to_value) && !is.na(to_value)) {
    clauses <- c(clauses, "timestamp_utc <= ?")
    params <- c(params, list(to_value))
  }

  where_clause <- if (length(clauses) > 0) paste("WHERE", paste(clauses, collapse = " AND ")) else ""
  sql <- paste(
    "SELECT timestamp_utc, username, dataset_name, format, row_count,",
    "download_status, error_message, ip_address",
    "FROM master.public_export.download_log",
    where_clause,
    sprintf("ORDER BY timestamp_utc DESC LIMIT %d", as.integer(limit))
  )

  list(sql = sql, params = params)
}
