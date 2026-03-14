# =============================================================================
# logic_sync.R  —  push-only sync engine
# Local DuckDB <-> master PostgreSQL: push dirty rows to staging, admin merges
# =============================================================================

# NULL-coalescing operator
if (!exists("%||%", inherits = FALSE)) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}


# =============================================================================
# 0. Table registry
# =============================================================================

#' Configuration for all push-eligible tables.
#'
#' Fields per entry:
#'   local          - Local DuckDB table name (PascalCase, as created)
#'   pg             - PostgreSQL staging/core schema name (lowercase)
#'   pk             - Natural primary key column name (same in local and PG)
#'   project_scope  - "direct"  = table has its own projectid column
#'                    "via_env" = project derived by joining through Env
#'   env_fk         - (via_env only) column in local table matching Env.plotnumber
SYNC_TABLE_CONFIG <- list(
  list(local = "Admin",     pg = "admin",     pk = "plot",
       project_scope = "via_env",  env_fk = "plot"),
  list(local = "Env",       pg = "env",       pk = "plotnumber",
       project_scope = "direct"),
  list(local = "SU",        pg = "su",        pk = "plotnumber",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Humus",     pg = "humus",     pk = "id",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Mineral",   pg = "mineral",   pk = "id",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Other",     pg = "other",     pk = "id",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Veg",       pg = "veg",       pk = "id",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Herbarium", pg = "herbarium", pk = "recid",
       project_scope = "via_env",  env_fk = "plotnumber"),
  list(local = "Metadata",  pg = "metadata",  pk = "id",
       project_scope = "direct")
)


# =============================================================================
# 1. Cloud connectivity
# =============================================================================

#' Check whether the cloud master database is currently attached.
#' @param con   DuckDB connection.
#' @param alias Catalog alias. Default "master".
#' @return Logical.
sync_cloud_connected <- function(con, alias = "master") {
  tryCatch({
    dbs <- DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
    alias %in% dbs
  }, error = function(e) FALSE)
}

#' Stop if the cloud master is not attached.
#' @param con          DuckDB connection.
#' @param allow_attach Unused; kept for backward compatibility.
#' @param alias        Expected catalog alias.
sync_require_cloud <- function(con, allow_attach = FALSE, alias = "master") {
  if (sync_cloud_connected(con, alias)) return(invisible(TRUE))
  stop("Cloud database '", alias, "' is not attached. Please log in first.")
}


# =============================================================================
# 2. Local schema setup
# =============================================================================

#' Add local_modified_utc to all 9 push-eligible tables (idempotent).
#' @param con DuckDB connection.
sync_ensure_local_tables <- function(con) {
  for (cfg in SYNC_TABLE_CONFIG) {
    if (DBI::dbExistsTable(con, cfg$local)) {
      tryCatch(
        DBI::dbExecute(con, sprintf(
          'ALTER TABLE "%s" ADD COLUMN IF NOT EXISTS local_modified_utc TIMESTAMPTZ',
          cfg$local
        )),
        error = function(e) NULL
      )
    }
  }
  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS sync_local_changes (",
      "table_pg TEXT NOT NULL,",
      "local_table TEXT NOT NULL,",
      "pk_name TEXT NOT NULL,",
      "pk_value TEXT NOT NULL,",
      "project_id TEXT,",
      "change_type TEXT NOT NULL,",
      "prior_payload TEXT,",
      "updated_utc TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP",
      ")"
    )
  )
  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS sync_local_deletes (",
      "table_pg TEXT NOT NULL,",
      "local_table TEXT NOT NULL,",
      "pk_name TEXT NOT NULL,",
      "pk_value TEXT NOT NULL,",
      "project_id TEXT,",
      "deleted_payload TEXT,",
      "baseline_exists BOOLEAN DEFAULT FALSE,",
      "core_exists BOOLEAN DEFAULT FALSE,",
      "deleted_utc TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP",
      ")"
    )
  )
  invisible(TRUE)
}

sync_touch_state <- function(state) {
  state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
  invisible(state$SyncVersion)
}

sync_get_table_config <- function(table_name, key = c("pg", "local")) {
  key <- match.arg(key)
  for (cfg in SYNC_TABLE_CONFIG) {
    if (identical(cfg[[key]], table_name)) {
      return(cfg)
    }
  }
  NULL
}

.sync_find_field <- function(fields, candidates) {
  if (length(fields) == 0 || length(candidates) == 0) return(NA_character_)
  idx <- match(tolower(candidates), tolower(fields), nomatch = 0L)
  idx <- idx[idx > 0L]
  if (length(idx) == 0) return(NA_character_)
  fields[[idx[[1]]]]
}

.sync_payload_from_row <- function(row) {
  if (is.null(row) || length(row) == 0) return(NULL)
  tryCatch(
    as.character(jsonlite::toJSON(row, auto_unbox = TRUE, null = "null", na = "null")),
    error = function(e) NULL
  )
}

.sync_payload_to_row <- function(payload) {
  if (is.null(payload) || !nzchar(as.character(payload))) return(NULL)
  parsed <- tryCatch(jsonlite::fromJSON(payload, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed) || !is.list(parsed)) return(NULL)
  parsed
}

.sync_get_row_value <- function(row, field, default = NULL) {
  if (is.null(row) || is.na(field) || !nzchar(field)) return(default)
  row_names <- names(row)
  if (is.null(row_names) || length(row_names) == 0) return(default)
  idx <- match(tolower(field), tolower(row_names), nomatch = 0L)
  if (idx == 0L) return(default)
  value <- row[[idx]]
  if (is.list(value) && length(value) == 1) value <- value[[1]]
  if (length(value) == 0) return(default)
  value
}

.sync_extract_row_version <- function(row) {
  value <- .sync_get_row_value(row, "rowVersion")
  if (is.null(value)) value <- .sync_get_row_value(row, "rowversion")
  if (is.null(value) || length(value) == 0 || isTRUE(is.na(value[[1]]))) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(value[[1]]))
}

.sync_has_row_version_field <- function(row) {
  row_names <- names(row %||% list())
  !is.na(.sync_find_field(row_names, c("rowVersion", "rowversion")))
}

.sync_make_lookup <- function(df, pk_name) {
  if (is.null(df) || nrow(df) == 0) return(list())
  pk_field <- .sync_find_field(names(df), pk_name)
  if (is.na(pk_field)) return(list())
  setNames(
    lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE])),
    as.character(df[[pk_field]])
  )
}

.sync_project_filter_sql <- function(cfg, project_id) {
  pid_safe <- if (!is.null(project_id) && nzchar(as.character(project_id))) {
    gsub("[^A-Za-z0-9_-]", "", as.character(project_id))
  } else {
    NULL
  }
  if (is.null(pid_safe)) return("")

  if (cfg$project_scope == "direct") {
    paste0(" AND \"projectid\" = '", pid_safe, "'")
  } else {
    sprintf(
      " AND \"%s\" IN (SELECT \"plotnumber\" FROM \"Env\" WHERE \"projectid\" = '%s')",
      cfg$env_fk,
      pid_safe
    )
  }
}

.sync_get_local_rows <- function(con, cfg, project_id = NULL, max_rows = NULL) {
  if (!DBI::dbExistsTable(con, cfg$local)) return(data.frame())
  fields <- tryCatch(DBI::dbListFields(con, cfg$local), error = function(e) character(0))
  if (!("local_modified_utc" %in% fields)) return(data.frame())

  limit_sql <- if (!is.null(max_rows) && is.finite(max_rows)) {
    paste(" LIMIT", as.integer(max_rows))
  } else {
    ""
  }

  tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        'SELECT * FROM "%s" WHERE local_modified_utc IS NOT NULL%s%s',
        cfg$local,
        .sync_project_filter_sql(cfg, project_id),
        limit_sql
      )
    ),
    error = function(e) data.frame()
  )
}

.sync_get_core_lookup <- function(con, cfg, pk_values) {
  pk_values <- unique(as.character(pk_values %||% character(0)))
  pk_values <- pk_values[nzchar(pk_values)]
  if (!sync_cloud_connected(con) || length(pk_values) == 0) return(list())

  placeholders <- paste(rep("?", length(pk_values)), collapse = ", ")
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        'SELECT * FROM master.core.%s WHERE CAST("%s" AS TEXT) IN (%s)',
        cfg$pg,
        cfg$pk,
        placeholders
      ),
      as.list(pk_values)
    ),
    error = function(e) data.frame()
  )
  .sync_make_lookup(rows, cfg$pk)
}

.sync_get_baseline_lookup <- function(con, cfg, project_id, pk_values) {
  pk_values <- unique(as.character(pk_values %||% character(0)))
  pk_values <- pk_values[nzchar(pk_values)]
  if (is.null(project_id) || !nzchar(as.character(project_id)) || length(pk_values) == 0) return(list())

  rows <- tryCatch(
    project_read_baseline_rows(con, project_id, cfg$local, cfg$pk, pk_values),
    error = function(e) data.frame()
  )
  .sync_make_lookup(rows, cfg$pk)
}

.sync_delete_ledger_rows <- function(con, cfg, project_id = NULL) {
  sync_ensure_local_tables(con)
  sql <- paste0(
    "SELECT * FROM sync_local_deletes WHERE table_pg = ?",
    if (!is.null(project_id) && nzchar(as.character(project_id))) " AND project_id = ?" else "",
    " ORDER BY deleted_utc DESC"
  )
  params <- list(cfg$pg)
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    params <- c(params, list(as.character(project_id)))
  }
  tryCatch(
    DBI::dbGetQuery(con, sql, params),
    error = function(e) data.frame()
  )
}

.sync_change_ledger_rows <- function(con, cfg, project_id = NULL) {
  sync_ensure_local_tables(con)
  sql <- paste0(
    "SELECT * FROM sync_local_changes WHERE table_pg = ?",
    if (!is.null(project_id) && nzchar(as.character(project_id))) " AND project_id = ?" else "",
    " ORDER BY updated_utc DESC"
  )
  params <- list(cfg$pg)
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    params <- c(params, list(as.character(project_id)))
  }
  tryCatch(DBI::dbGetQuery(con, sql, params), error = function(e) data.frame())
}

sync_record_local_change <- function(con,
                                     table_name,
                                     pk_value,
                                     project_id = NULL,
                                     change_type = c("insert", "update"),
                                     prior_payload = NULL) {
  change_type <- match.arg(change_type)
  cfg <- sync_get_table_config(table_name, key = "pg")
  if (is.null(cfg)) cfg <- sync_get_table_config(table_name, key = "local")
  if (is.null(cfg)) stop("Unsupported sync table: ", table_name)

  sync_ensure_local_tables(con)
  pk_value <- as.character(pk_value %||% "")
  if (!nzchar(pk_value)) stop("pk_value is required.")

  existing <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT * FROM sync_local_changes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '') ORDER BY updated_utc DESC LIMIT 1",
      list(cfg$pg, pk_value, if (is.null(project_id)) NA_character_ else as.character(project_id))
    ),
    error = function(e) data.frame()
  )

  effective_type <- change_type
  if (nrow(existing) > 0 && identical(existing$change_type[[1]], "insert") && identical(change_type, "update")) {
    effective_type <- "insert"
  }

  existing_payload <- if (nrow(existing) > 0) existing$prior_payload[[1]] else NULL
  payload_json <- if (!is.null(existing_payload) && nzchar(as.character(existing_payload))) {
    existing_payload
  } else {
    .sync_payload_from_row(prior_payload)
  }

  DBI::dbExecute(
    con,
    "DELETE FROM sync_local_changes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '')",
    list(cfg$pg, pk_value, if (is.null(project_id)) NA_character_ else as.character(project_id))
  )

  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO sync_local_changes",
      "(table_pg, local_table, pk_name, pk_value, project_id, change_type, prior_payload, updated_utc)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"
    ),
    list(
      cfg$pg,
      cfg$local,
      cfg$pk,
      pk_value,
      if (is.null(project_id) || !nzchar(as.character(project_id))) NA_character_ else as.character(project_id),
      effective_type,
      payload_json
    )
  )

  invisible(effective_type)
}

sync_clear_local_change <- function(con, table_name, pk_value, project_id = NULL) {
  cfg <- sync_get_table_config(table_name, key = "pg")
  if (is.null(cfg)) cfg <- sync_get_table_config(table_name, key = "local")
  if (is.null(cfg)) stop("Unsupported sync table: ", table_name)

  sync_ensure_local_tables(con)
  DBI::dbExecute(
    con,
    "DELETE FROM sync_local_changes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '')",
    list(cfg$pg, as.character(pk_value), if (is.null(project_id)) NA_character_ else as.character(project_id))
  )
  invisible(TRUE)
}

.sync_classify_local_change <- function(local_row, baseline_row = NULL, core_row = NULL) {
  if (.sync_has_row_version_field(local_row)) {
    local_rv <- .sync_extract_row_version(local_row)
    return(if (is.na(local_rv)) "insert" else "update")
  }
  if (!is.null(baseline_row) || !is.null(core_row)) {
    return("update")
  }
  "insert"
}

sync_collect_table_changes <- function(con, cfg, project_id = NULL, max_rows = 50L) {
  sync_ensure_local_tables(con)

  local_rows <- .sync_get_local_rows(
    con,
    cfg,
    project_id = project_id,
    max_rows = if (is.null(max_rows) || !is.finite(max_rows)) NULL else max_rows
  )
  local_pk_field <- .sync_find_field(names(local_rows), cfg$pk)
  local_pk_values <- if (nrow(local_rows) > 0 && !is.na(local_pk_field)) {
    as.character(local_rows[[local_pk_field]])
  } else {
    character(0)
  }
  local_pk_counts <- if (length(local_pk_values) > 0) table(local_pk_values) else integer(0)

  delete_rows <- .sync_delete_ledger_rows(con, cfg, project_id = project_id)
  explicit_rows <- .sync_change_ledger_rows(con, cfg, project_id = project_id)
  delete_pk_values <- if (nrow(delete_rows) > 0) as.character(delete_rows$pk_value) else character(0)
  explicit_pk_values <- if (nrow(explicit_rows) > 0) as.character(explicit_rows$pk_value) else character(0)
  pk_values <- unique(c(local_pk_values, delete_pk_values, explicit_pk_values))

  core_lookup <- .sync_get_core_lookup(con, cfg, pk_values)
  baseline_lookup <- .sync_get_baseline_lookup(con, cfg, project_id, pk_values)
  explicit_lookup <- if (nrow(explicit_rows) > 0) {
    split(explicit_rows, explicit_rows$pk_value)
  } else {
    list()
  }
  seen_pk <- character(0)

  out <- list()

  if (nrow(local_rows) > 0) {
    for (i in seq_len(nrow(local_rows))) {
      row <- as.list(local_rows[i, , drop = FALSE])
      pk_value <- as.character(.sync_get_row_value(row, cfg$pk, default = ""))
      if (!nzchar(pk_value) || pk_value %in% seen_pk) {
        next
      }
      seen_pk <- c(seen_pk, pk_value)
      baseline_row <- baseline_lookup[[pk_value]]
      core_row <- core_lookup[[pk_value]]
      explicit_row <- explicit_lookup[[pk_value]]
      explicit_type <- if (!is.null(explicit_row) && nrow(explicit_row) > 0) as.character(explicit_row$change_type[[1]]) else NULL
      explicit_prior <- if (!is.null(explicit_row) && nrow(explicit_row) > 0) .sync_payload_to_row(explicit_row$prior_payload[[1]]) else NULL
      before_row <- explicit_prior %||% core_row %||% baseline_row
      inferred_type <- explicit_type %||% .sync_classify_local_change(row, baseline_row = baseline_row, core_row = core_row)
      if (identical(inferred_type, "insert") && is.null(explicit_type) && is.null(before_row)) {
        duplicate_count <- if (length(local_pk_counts) > 0 && pk_value %in% names(local_pk_counts)) as.integer(local_pk_counts[[pk_value]]) else 0L
        if (duplicate_count > 1L) {
          inferred_type <- "update"
        }
      }

      row$local_modified_utc <- NULL

      out[[length(out) + 1L]] <- list(
        table_pg = cfg$pg,
        pk_value = pk_value,
        change_type = inferred_type,
        local_data = row,
        core_data = before_row,
        baseline_data = baseline_row,
        delete_data = NULL
      )
    }
  }

  if (nrow(delete_rows) > 0) {
    for (i in seq_len(nrow(delete_rows))) {
      row <- delete_rows[i, , drop = FALSE]
      pk_value <- as.character(row$pk_value[[1]])
      if (!nzchar(pk_value) || pk_value %in% seen_pk) {
        next
      }
      seen_pk <- c(seen_pk, pk_value)
      baseline_row <- baseline_lookup[[pk_value]]
      core_row <- core_lookup[[pk_value]]
      delete_data <- .sync_payload_to_row(row$deleted_payload[[1]])

      if (!isTRUE(row$baseline_exists[[1]]) && !isTRUE(row$core_exists[[1]]) && is.null(baseline_row) && is.null(core_row)) {
        next
      }

      out[[length(out) + 1L]] <- list(
        table_pg = cfg$pg,
        pk_value = pk_value,
        change_type = "delete",
        local_data = NULL,
        core_data = core_row %||% baseline_row %||% delete_data,
        baseline_data = baseline_row,
        delete_data = delete_data
      )
    }
  }

  if (!is.null(max_rows) && is.finite(max_rows) && length(out) > max_rows) {
    out <- out[seq_len(max_rows)]
  }

  out
}

sync_get_pending_summary <- function(con, project_id = NULL) {
  by_table <- list()
  total <- c(insert = 0L, update = 0L, delete = 0L, total = 0L)

  for (cfg in SYNC_TABLE_CONFIG) {
    records <- sync_collect_table_changes(con, cfg, project_id = project_id, max_rows = Inf)
    counts <- c(
      insert = sum(vapply(records, function(record) identical(record$change_type, "insert"), logical(1))),
      update = sum(vapply(records, function(record) identical(record$change_type, "update"), logical(1))),
      delete = sum(vapply(records, function(record) identical(record$change_type, "delete"), logical(1)))
    )
    counts <- c(counts, total = sum(counts))
    by_table[[cfg$pg]] <- counts
    total <- total + counts
  }

  list(by_table = by_table, total = total)
}

sync_get_pending_total <- function(con, project_id = NULL) {
  sync_get_pending_summary(con, project_id = project_id)$total[["total"]]
}

sync_record_delete <- function(con, cfg, pk_value, project_id = NULL, payload = NULL) {
  sync_ensure_local_tables(con)
  pk_value <- as.character(pk_value %||% "")
  if (!nzchar(pk_value)) stop("pk_value is required.")

  if (is.null(payload)) {
    current <- tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf('SELECT * FROM "%s" WHERE CAST("%s" AS TEXT) = ? LIMIT 1', cfg$local, cfg$pk),
        list(pk_value)
      ),
      error = function(e) data.frame()
    )
    if (nrow(current) > 0) {
      payload <- as.list(current[1, , drop = FALSE])
      payload$local_modified_utc <- NULL
    }
  }

  baseline_exists <- FALSE
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    baseline_exists <- length(.sync_get_baseline_lookup(con, cfg, project_id, pk_value)) > 0
  }
  core_exists <- length(.sync_get_core_lookup(con, cfg, pk_value)) > 0

  DBI::dbExecute(
    con,
    "DELETE FROM sync_local_deletes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '')",
    list(cfg$pg, pk_value, if (is.null(project_id)) NA_character_ else as.character(project_id))
  )

  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO sync_local_deletes",
      "(table_pg, local_table, pk_name, pk_value, project_id, deleted_payload, baseline_exists, core_exists, deleted_utc)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"
    ),
    list(
      cfg$pg,
      cfg$local,
      cfg$pk,
      pk_value,
      if (is.null(project_id) || !nzchar(as.character(project_id))) NA_character_ else as.character(project_id),
      .sync_payload_from_row(payload),
      isTRUE(baseline_exists),
      isTRUE(core_exists)
    )
  )

  invisible(list(baseline_exists = baseline_exists, core_exists = core_exists))
}

sync_delete_local_row <- function(con, table_name, pk_value, project_id = NULL) {
  cfg <- sync_get_table_config(table_name, key = "pg")
  if (is.null(cfg)) cfg <- sync_get_table_config(table_name, key = "local")
  if (is.null(cfg)) stop("Unsupported sync table: ", table_name)

  pk_value <- as.character(pk_value %||% "")
  if (!nzchar(pk_value)) stop("pk_value is required.")

  current <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf('SELECT * FROM "%s" WHERE CAST("%s" AS TEXT) = ? LIMIT 1', cfg$local, cfg$pk),
      list(pk_value)
    ),
    error = function(e) data.frame()
  )
  if (nrow(current) == 0) {
    return(invisible(FALSE))
  }

  sync_record_delete(
    con,
    cfg,
    pk_value = pk_value,
    project_id = project_id,
    payload = as.list(current[1, , drop = FALSE])
  )
  sync_clear_local_change(con, cfg$pg, pk_value = pk_value, project_id = project_id)

  DBI::dbExecute(
    con,
    sprintf('DELETE FROM "%s" WHERE CAST("%s" AS TEXT) = ?', cfg$local, cfg$pk),
    list(pk_value)
  )

  invisible(TRUE)
}

.sync_restore_row <- function(con, cfg, row_data, clear_local_modified = TRUE) {
  if (is.null(row_data) || length(row_data) == 0) stop("Row payload is required.")
  table_fields <- tryCatch(DBI::dbListFields(con, cfg$local), error = function(e) character(0))
  if (length(table_fields) == 0) stop("Table not available: ", cfg$local)

  row_names <- names(row_data)
  keep_idx <- match(tolower(table_fields), tolower(row_names), nomatch = 0L)
  keep_idx <- keep_idx[keep_idx > 0L]
  if (length(keep_idx) == 0) stop("No shared columns available for restore.")

  payload_names <- row_names[keep_idx]
  payload_values <- lapply(payload_names, function(name) row_data[[name]])
  names(payload_values) <- payload_names

  lmu_field <- .sync_find_field(table_fields, "local_modified_utc")
  if (!is.na(lmu_field) && isTRUE(clear_local_modified)) {
    payload_values[[lmu_field]] <- NA
  }

  pk_field <- .sync_find_field(table_fields, cfg$pk)
  pk_value <- .sync_get_row_value(row_data, cfg$pk)
  if (is.null(pk_value)) stop("Restore payload is missing primary key.")

  DBI::dbExecute(
    con,
    sprintf('DELETE FROM "%s" WHERE CAST("%s" AS TEXT) = ?', cfg$local, pk_field),
    list(as.character(pk_value[[1]]))
  )

  columns <- names(payload_values)
  placeholders <- paste(rep("?", length(columns)), collapse = ", ")
  sql <- sprintf(
    'INSERT INTO "%s" (%s) VALUES (%s)',
    cfg$local,
    paste(sprintf('"%s"', columns), collapse = ", "),
    placeholders
  )
  DBI::dbExecute(con, sql, unname(payload_values))
  invisible(TRUE)
}

sync_revert_pending_change <- function(con, table_name, pk_value, project_id = NULL) {
  cfg <- sync_get_table_config(table_name, key = "pg")
  if (is.null(cfg)) cfg <- sync_get_table_config(table_name, key = "local")
  if (is.null(cfg)) stop("Unsupported sync table: ", table_name)

  pk_value <- as.character(pk_value %||% "")
  if (!nzchar(pk_value)) stop("pk_value is required.")

  delete_rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      paste0(
        "SELECT * FROM sync_local_deletes WHERE table_pg = ? AND pk_value = ?",
        if (!is.null(project_id) && nzchar(as.character(project_id))) " AND project_id = ?" else "",
        " ORDER BY deleted_utc DESC LIMIT 1"
      ),
      if (!is.null(project_id) && nzchar(as.character(project_id))) {
        list(cfg$pg, pk_value, as.character(project_id))
      } else {
        list(cfg$pg, pk_value)
      }
    ),
    error = function(e) data.frame()
  )

  if (nrow(delete_rows) > 0) {
    baseline_row <- if (!is.null(project_id) && nzchar(as.character(project_id))) {
      .sync_get_baseline_lookup(con, cfg, project_id, pk_value)[[pk_value]]
    } else {
      NULL
    }
    restore_row <- baseline_row %||% .sync_payload_to_row(delete_rows$deleted_payload[[1]])
    if (is.null(restore_row)) {
      stop("No baseline or tombstone payload available to restore the deleted row.")
    }

    .sync_restore_row(con, cfg, restore_row, clear_local_modified = TRUE)
    DBI::dbExecute(
      con,
      "DELETE FROM sync_local_deletes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '')",
      list(cfg$pg, pk_value, if (is.null(project_id)) NA_character_ else as.character(project_id))
    )
    sync_clear_local_change(con, cfg$pg, pk_value = pk_value, project_id = project_id)
    return(list(ok = TRUE, change_type = "delete", message = sprintf("Restored deleted %s row %s.", cfg$local, pk_value)))
  }

  local_rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf('SELECT * FROM "%s" WHERE CAST("%s" AS TEXT) = ? AND local_modified_utc IS NOT NULL LIMIT 1', cfg$local, cfg$pk),
      list(pk_value)
    ),
    error = function(e) data.frame()
  )
  if (nrow(local_rows) == 0) {
    stop("No pending local change found for this record.")
  }

  local_row <- as.list(local_rows[1, , drop = FALSE])
  local_row$local_modified_utc <- NULL
  explicit_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT * FROM sync_local_changes WHERE table_pg = ? AND pk_value = ? AND COALESCE(project_id, '') = COALESCE(?, '') ORDER BY updated_utc DESC LIMIT 1",
      list(cfg$pg, pk_value, if (is.null(project_id)) NA_character_ else as.character(project_id))
    ),
    error = function(e) data.frame()
  )
  explicit_type <- if (nrow(explicit_row) > 0) as.character(explicit_row$change_type[[1]]) else NULL
  explicit_prior <- if (nrow(explicit_row) > 0) .sync_payload_to_row(explicit_row$prior_payload[[1]]) else NULL
  baseline_row <- if (!is.null(project_id) && nzchar(as.character(project_id))) {
    .sync_get_baseline_lookup(con, cfg, project_id, pk_value)[[pk_value]]
  } else {
    NULL
  }
  core_row <- .sync_get_core_lookup(con, cfg, pk_value)[[pk_value]]
  change_type <- explicit_type %||% .sync_classify_local_change(local_row, baseline_row = baseline_row, core_row = core_row)

  if (identical(change_type, "insert")) {
    DBI::dbExecute(
      con,
      sprintf('DELETE FROM "%s" WHERE CAST("%s" AS TEXT) = ?', cfg$local, cfg$pk),
      list(pk_value)
    )
    sync_clear_local_change(con, cfg$pg, pk_value = pk_value, project_id = project_id)
    return(list(ok = TRUE, change_type = "insert", message = sprintf("Removed pending %s insert %s.", cfg$local, pk_value)))
  }

  restore_row <- explicit_prior %||% baseline_row %||% core_row
  if (is.null(restore_row)) {
    stop("No baseline or core row available to restore this update.")
  }

  .sync_restore_row(con, cfg, restore_row, clear_local_modified = TRUE)
  sync_clear_local_change(con, cfg$pg, pk_value = pk_value, project_id = project_id)
  list(ok = TRUE, change_type = "update", message = sprintf("Reverted pending %s update %s.", cfg$local, pk_value))
}


# =============================================================================
# 3. Column discovery
# =============================================================================

# Staging metadata columns to exclude from shared-column intersection.
.STAGING_META_COLS <- tolower(c(
  "merge_request_id", "baseRowVersion", "changeType",
  "rowVersion", "lastModifiedUTC", "modifiedBy"
))

# Local metadata columns to exclude.
.LOCAL_META_COLS <- c("local_modified_utc")

#' Discover shared data columns between a local table and its PG staging mirror.
#' Returns lowercase column names safe to use in SQL on both sides.
#'
#' @param con         DuckDB connection with master attached.
#' @param local_table Local DuckDB table name.
#' @param pg_table    PG staging/core schema name (lowercase).
#' @return Character vector of shared lowercase column names.
.get_shared_columns <- function(con, local_table, pg_table) {
  local_cols <- tryCatch(
    tolower(DBI::dbListFields(con, local_table)),
    error = function(e) character(0)
  )
  staging_cols <- tryCatch({
    res <- DBI::dbGetQuery(
      con,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_catalog = 'master'
         AND table_schema  = 'staging'
         AND table_name    = ?",
      list(pg_table)
    )
    tolower(res$column_name)
  }, error = function(e) character(0))

  local_cols   <- setdiff(local_cols,   .LOCAL_META_COLS)
  staging_cols <- setdiff(staging_cols, .STAGING_META_COLS)
  intersect(local_cols, staging_cols)
}


# =============================================================================
# 4. PUSH: local -> master.staging
# =============================================================================

#' Push dirty rows of one table into the staging area.
#'
#' Sanitizes project_id for safe SQL embedding. project_id comes from the
#' authenticated session (user-selected project), validated upstream.
#'
#' @param con        DuckDB connection (master attached).
#' @param cfg        One entry from SYNC_TABLE_CONFIG.
#' @param mr_id      Integer merge request id (already created).
#' @param submitter  Character. Username / email of the submitter.
#' @param project_id Character. Project filter.
#' @return Integer count of rows staged.
.push_table <- function(con, cfg, mr_id, submitter, project_id) {
  if (!DBI::dbExistsTable(con, cfg$local)) return(0L)

  shared_cols <- .get_shared_columns(con, cfg$local, cfg$pg)
  if (length(shared_cols) == 0) return(0L)

  records <- sync_collect_table_changes(con, cfg, project_id = project_id, max_rows = Inf)
  if (length(records) == 0) return(0L)

  insert_sql <- sprintf(
    'INSERT INTO master.staging.%s (%s) VALUES (%s)',
    cfg$pg,
    paste(
      c('"merge_request_id"', '"changeType"', '"baseRowVersion"', '"modifiedBy"', sprintf('"%s"', shared_cols)),
      collapse = ", "
    ),
    paste(rep("?", 4 + length(shared_cols)), collapse = ", ")
  )

  staged <- 0L
  for (record in records) {
    payload <- record$local_data %||% record$baseline_data %||% record$core_data %||% record$delete_data %||% list()
    payload_pk_field <- .sync_find_field(names(payload), cfg$pk)
    if (is.na(payload_pk_field)) {
      payload[[cfg$pk]] <- record$pk_value
    }
    values <- c(
      list(
        as.integer(mr_id),
        switch(record$change_type, insert = "I", update = "U", delete = "D", "U"),
        if (is.na(.sync_extract_row_version(record$core_data %||% record$baseline_data %||% record$delete_data))) NA_integer_ else .sync_extract_row_version(record$core_data %||% record$baseline_data %||% record$delete_data),
        as.character(submitter)
      ),
      lapply(shared_cols, function(col) .sync_get_row_value(payload, col, default = NA))
    )
    DBI::dbExecute(con, insert_sql, values)
    staged <- staged + 1L
  }

  staged
}

#' Push all local changes for a project to master.staging, creating a merge request.
#'
#' @param con        DuckDB connection (master must be attached).
#' @param project_id Character. Project to push.
#' @param submitter  Character. Username / email of the submitter.
#' @return Named list: merge_request_id, counts (named by pg table), total.
sync_push <- function(con,
                      project_id = NULL,
                      submitter  = Sys.getenv("USER", "unknown")) {
  sync_require_cloud(con)
  sync_ensure_local_tables(con)

  if (is.null(project_id) || !nzchar(as.character(project_id))) {
    stop("project_id is required for sync_push.")
  }

  mr_id  <- .create_merge_request(con, project_id, submitter)
  counts <- list()

  for (cfg in SYNC_TABLE_CONFIG) {
    n <- tryCatch(
      .push_table(con, cfg, mr_id, submitter, project_id),
      error = function(e) {
        warning(sprintf(".push_table failed for %s: %s", cfg$local, e$message))
        0L
      }
    )
    counts[[cfg$pg]] <- as.integer(n)
  }

  counts_json <- tryCatch(
    as.character(jsonlite::toJSON(counts, auto_unbox = TRUE)),
    error = function(e) "{}"
  )
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests SET record_counts = ? WHERE id = ?",
    list(counts_json, as.integer(mr_id))
  )

  # Optional compliance gate
  if (exists("staging_compliance_checks", mode = "function")) {
    compliance    <- tryCatch(
      staging_compliance_checks(con, mr_id, project_id),
      error = function(e) list(passed = TRUE)
    )
    compliance_ok <- isTRUE(compliance$passed)
    report_json   <- tryCatch(
      as.character(jsonlite::toJSON(
        list(summary = compliance$summary_tibble, details = compliance$detail_tibble),
        auto_unbox = TRUE, na = "null"
      )),
      error = function(e) NULL
    )
    DBI::dbExecute(
      con,
      "UPDATE master.admin.merge_requests
       SET compliance_passed = ?, compliance_report = ? WHERE id = ?",
      list(compliance_ok, report_json, as.integer(mr_id))
    )
    if (!compliance_ok) {
      .delete_staging(con, mr_id)
      DBI::dbExecute(
        con,
        "UPDATE master.admin.merge_requests SET status = 'rejected' WHERE id = ?",
        list(as.integer(mr_id))
      )
      return(list(
        merge_request_id  = mr_id,
        counts            = counts,
        total             = sum(unlist(counts)),
        compliance_failed = TRUE
      ))
    }
  }

  list(
    merge_request_id = mr_id,
    counts           = counts,
    total            = sum(unlist(counts))
  )
}


# =============================================================================
# 5. Local change summary (used by mod_sync)
# =============================================================================

#' Return local dirty rows across all 9 tables for a project.
#'
#' @param con        DuckDB connection.
#' @param project_id Optional character/integer filter.
#' @return Named list keyed by cfg$pg; each element is a data.frame with
#'   columns table_pg and change_type.
sync_get_local_changes <- function(con, project_id = NULL) {
  out <- list()

  for (cfg in SYNC_TABLE_CONFIG) {
    records <- sync_collect_table_changes(con, cfg, project_id = project_id, max_rows = Inf)
    if (length(records) == 0) {
      out[[cfg$pg]] <- data.frame(
        table_pg = character(0),
        pk_value = character(0),
        change_type = character(0),
        stringsAsFactors = FALSE
      )
      next
    }

    out[[cfg$pg]] <- data.frame(
      table_pg = rep(cfg$pg, length(records)),
      pk_value = vapply(records, function(record) as.character(record$pk_value %||% ""), character(1)),
      change_type = vapply(records, function(record) as.character(record$change_type %||% ""), character(1)),
      stringsAsFactors = FALSE
    )
  }
  out
}


# =============================================================================
# 6. Detailed change records (for diff cards)
# =============================================================================

#' Fetch full before/after data for all dirty local rows.
#'
#' For each dirty row the function determines change_type ("insert" when no
#' matching row exists in master.core, "update" otherwise) and packages the
#' local data together with the core data for rendering diff cards.
#'
#' @param con        DuckDB connection (master optionally attached for updates).
#' @param cfg        One entry from SYNC_TABLE_CONFIG.
#' @param project_id Optional project filter (same semantics as sync_get_local_changes).
#' @param max_rows   Integer. Safety cap; default 50L.
#' @return List of records, each: list(pk_value, change_type, local_data, core_data).
sync_get_change_detail <- function(con, cfg, project_id = NULL, max_rows = 50L) {
  sync_collect_table_changes(con, cfg, project_id = project_id, max_rows = max_rows)
}


# =============================================================================
# 7. Internal push helpers
# =============================================================================

.create_merge_request <- function(con, project_id, submitter) {
  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(submitter))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  submitter_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.merge_requests
       (project_id, submitter_user_id, submitter_name, submitted_utc, status)
     VALUES (?, ?, ?, now(), 'pending_review')",
    list(as.character(project_id), submitter_user_id, as.character(submitter))
  )

  res <- DBI::dbGetQuery(
    con,
    "SELECT id FROM master.admin.merge_requests
     WHERE project_id = ? AND submitter_name = ? AND status = 'pending_review'
     ORDER BY submitted_utc DESC LIMIT 1",
    list(as.character(project_id), as.character(submitter))
  )
  if (nrow(res) == 0) stop("Failed to create merge request.")
  res$id[1]
}

.delete_staging <- function(con, mr_id) {
  for (cfg in SYNC_TABLE_CONFIG) {
    tryCatch(
      DBI::dbExecute(
        con,
        sprintf("DELETE FROM master.staging.%s WHERE merge_request_id = ?", cfg$pg),
        list(as.integer(mr_id))
      ),
      error = function(e) NULL
    )
  }
}


# =============================================================================
# 7. Server-side conflict detection
# =============================================================================

.to_json <- function(x) {
  tryCatch(
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, na = "null")),
    error = function(e) "{}"
  )
}

#' Detect version conflicts for one table in a merge request.
#' A conflict exists when core.rowVersion > staging.baseRowVersion at the
#' same natural key (master was updated after the user's last push).
#'
#' @param con   DuckDB connection.
#' @param mr_id Integer merge request id.
#' @param cfg   One entry from SYNC_TABLE_CONFIG.
.detect_table_conflicts <- function(con, mr_id, cfg) {
  pk   <- cfg$pk
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        'SELECT CAST(s."%s" AS TEXT)  AS record_id,
                s."baseRowVersion"   AS staged_rv,
                c."rowVersion"       AS core_rv
         FROM master.staging.%s s
         JOIN master.core.%s c
           ON CAST(c."%s" AS TEXT) = CAST(s."%s" AS TEXT)
         WHERE s.merge_request_id = ?
           AND s."baseRowVersion" IS NOT NULL
           AND c."rowVersion" > s."baseRowVersion"',
        pk, cfg$pg, cfg$pg, pk, pk
      ),
      list(as.integer(mr_id))
    ),
    error = function(e) data.frame()
  )
  if (nrow(rows) == 0) return(invisible(NULL))

  for (i in seq_len(nrow(rows))) {
    r       <- rows[i, , drop = FALSE]
    details <- list(row_version = list(
      staged_base  = r$staged_rv[1],
      core_current = r$core_rv[1]
    ))
    .insert_conflict(con, mr_id, cfg$pg, as.character(r$record_id[1]), .to_json(details))
  }
}

#' Insert or update a conflict record using record_id TEXT.
#' Skips update if the conflict is already resolved (preserves decisions).
#'
#' @param con         DuckDB connection.
#' @param mr_id       Integer merge request id.
#' @param table_name  Character. PG staging table name.
#' @param record_id   Character. String representation of the natural PK value.
#' @param details_json Character. JSON-encoded conflict details.
.insert_conflict <- function(con, mr_id, table_name, record_id, details_json) {
  existing <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id, resolution FROM master.admin.merge_conflicts
       WHERE merge_request_id = ? AND table_name = ? AND record_id = ?",
      list(as.integer(mr_id), as.character(table_name), as.character(record_id))
    ),
    error = function(e) data.frame()
  )

  if (nrow(existing) > 0) {
    if (is.na(existing$resolution[1])) {
      DBI::dbExecute(
        con,
        "UPDATE master.admin.merge_conflicts SET details = ? WHERE id = ?",
        list(as.character(details_json), as.integer(existing$id[1]))
      )
    }
    return(invisible(NULL))
  }

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.merge_conflicts
       (merge_request_id, table_name, record_id, details)
     VALUES (?, ?, ?, ?)",
    list(as.integer(mr_id), as.character(table_name),
         as.character(record_id), as.character(details_json))
  )
}


# =============================================================================
# 8. Apply staging to core (admin approval)
# =============================================================================

#' Apply staged rows for one table to master.core.
#'
#' Uses dynamic column list from .get_shared_columns().
#' Rows with resolution = 'keep_core' are excluded via LEFT JOIN filter.
#' Production BEFORE UPDATE trigger auto-increments rowVersion.
#'
#' @param con   DuckDB connection (master attached).
#' @param mr_id Integer merge request id.
#' @param cfg   One entry from SYNC_TABLE_CONFIG.
.apply_table <- function(con, mr_id, cfg) {
  pk          <- cfg$pk
  shared_cols <- .get_shared_columns(con, cfg$local, cfg$pg)
  if (length(shared_cols) == 0) return(invisible(NULL))

  col_list    <- paste(sprintf('"%s"', shared_cols), collapse = ", ")
  select_list <- paste(sprintf('s."%s"', shared_cols), collapse = ", ")
  update_set  <- paste(
    sprintf('"%s" = EXCLUDED."%s"', shared_cols, shared_cols),
    collapse = ", "
  )

  tbl <- cfg$pg

  DBI::dbExecute(
    con,
    sprintf(
      "DELETE FROM master.core.%s c
       USING master.staging.%s s
       LEFT JOIN master.admin.merge_conflicts mc
         ON  mc.merge_request_id = s.merge_request_id
         AND mc.table_name       = '%s'
         AND mc.record_id        = CAST(s.\"%s\" AS TEXT)
       WHERE s.merge_request_id = ?
         AND s.\"changeType\" = 'D'
         AND (mc.id IS NULL OR mc.resolution IN ('keep_staged', 'dismiss'))
         AND CAST(c.\"%s\" AS TEXT) = CAST(s.\"%s\" AS TEXT)",
      tbl,
      tbl,
      tbl,
      pk,
      pk,
      pk
    ),
    list(as.integer(mr_id))
  )

  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO master.core.%s (%s)
       SELECT %s
       FROM master.staging.%s s
       LEFT JOIN master.admin.merge_conflicts mc
         ON  mc.merge_request_id = s.merge_request_id
         AND mc.table_name       = '%s'
         AND mc.record_id        = CAST(s.\"%s\" AS TEXT)
       WHERE s.merge_request_id = ?
         AND COALESCE(s.\"changeType\", 'U') <> 'D'
         AND (mc.id IS NULL OR mc.resolution IN ('keep_staged', 'dismiss'))
       ON CONFLICT (\"%s\") DO UPDATE SET %s",
      tbl, col_list,
      select_list,
      tbl,
      tbl, pk,
      pk, update_set
    ),
    list(as.integer(mr_id))
  )
}


# =============================================================================
# 9. Merge request management (public API)
# =============================================================================

#' Retrieve a single merge request by id.
#' @param con              DuckDB connection (master attached).
#' @param merge_request_id Integer.
#' @return Single-row data.frame or NULL.
merge_request_get <- function(con, merge_request_id) {
  rows <- DBI::dbGetQuery(
    con,
    "SELECT * FROM master.admin.merge_requests WHERE id = ?",
    list(as.integer(merge_request_id))
  )
  if (nrow(rows) == 0) return(NULL)
  rows[1, , drop = FALSE]
}

#' List merge requests, optionally filtered by status.
#' @param con    DuckDB connection.
#' @param status Optional character filter.
#' @param limit  Integer. Max rows.
#' @return data.frame with unresolved_conflicts column appended.
merge_request_list <- function(con, status = NULL, limit = 200L) {
  sql    <- paste0(
    "SELECT id, project_id, submitter_name, submitted_utc, status,",
    " record_counts, compliance_passed",
    " FROM master.admin.merge_requests"
  )
  params <- list()
  if (!is.null(status) && nzchar(status)) {
    sql    <- paste0(sql, " WHERE status = ?")
    params <- list(status)
  }
  sql    <- paste0(sql, " ORDER BY submitted_utc DESC LIMIT ?")
  params <- c(params, list(as.integer(limit)))

  out <- DBI::dbGetQuery(con, sql, params)
  if (nrow(out) == 0) return(out)

  unresolved <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT merge_request_id, COUNT(*) AS unresolved_conflicts
       FROM master.admin.merge_conflicts
       WHERE resolution IS NULL
       GROUP BY merge_request_id"
    ),
    error = function(e) data.frame()
  )
  if (nrow(unresolved) > 0) {
    out <- merge(out, unresolved, by.x = "id", by.y = "merge_request_id", all.x = TRUE)
  }
  if (!"unresolved_conflicts" %in% names(out)) out$unresolved_conflicts <- 0L
  out$unresolved_conflicts[is.na(out$unresolved_conflicts)] <- 0L
  out
}

#' Detect and refresh version conflicts for all tables in a merge request.
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
merge_request_refresh_conflicts <- function(con, merge_request_id) {
  mr_id <- as.integer(merge_request_id)
  DBI::dbExecute(
    con,
    "DELETE FROM master.admin.merge_conflicts
     WHERE merge_request_id = ? AND resolution IS NULL",
    list(mr_id)
  )
  for (cfg in SYNC_TABLE_CONFIG) {
    tryCatch(.detect_table_conflicts(con, mr_id, cfg), error = function(e) NULL)
  }
  invisible(TRUE)
}

#' List conflicts for a merge request.
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @param unresolved_only  Logical. Default TRUE.
#' @param limit            Integer.
#' @return data.frame with id, table_name, record_id, resolution, details.
merge_request_get_conflicts <- function(con, merge_request_id,
                                         unresolved_only = TRUE, limit = 500L) {
  sql    <- paste0(
    "SELECT id, table_name, record_id, created_utc, resolution, details",
    " FROM master.admin.merge_conflicts",
    " WHERE merge_request_id = ?"
  )
  params <- list(as.integer(merge_request_id))
  if (isTRUE(unresolved_only)) sql <- paste0(sql, " AND resolution IS NULL")
  sql    <- paste0(sql, " ORDER BY created_utc DESC LIMIT ?")
  params <- c(params, list(as.integer(limit)))
  DBI::dbGetQuery(con, sql, params)
}

#' Count unresolved conflicts for a merge request.
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @return Integer.
merge_request_unresolved_count <- function(con, merge_request_id) {
  res <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM master.admin.merge_conflicts
       WHERE merge_request_id = ? AND resolution IS NULL",
      list(as.integer(merge_request_id))
    ),
    error = function(e) data.frame(n = 0L)
  )
  as.integer(res$n[1])
}

#' Resolve a single conflict entry.
#' @param con         DuckDB connection.
#' @param conflict_id Integer. Row id in master.admin.merge_conflicts.
#' @param resolution  One of: 'keep_staged', 'keep_core', 'dismiss'.
#' @param actor       Character. Reviewer username.
merge_request_resolve_conflict <- function(con, conflict_id, resolution,
                                            actor = Sys.getenv("USER", "unknown")) {
  if (!resolution %in% c("keep_staged", "keep_core", "dismiss")) {
    stop("resolution must be 'keep_staged', 'keep_core', or 'dismiss'")
  }
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_conflicts
     SET resolution = ?, resolved_by = ?, resolved_utc = now()
     WHERE id = ?",
    list(resolution, as.character(actor), as.integer(conflict_id))
  )
  invisible(TRUE)
}

#' Approve and apply a merge request to master.core.
#'
#' Refreshes conflicts first; blocks if any remain unresolved.
#' Applies all 9 tables generically via .apply_table().
#'
#' @param con              DuckDB connection (master attached).
#' @param merge_request_id Integer.
#' @param reviewer         Character. Reviewer email/username.
#' @param review_notes     Character. Optional notes.
merge_approve_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  mr_id <- as.integer(merge_request_id)

  # Check compliance gate
  compliance_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT compliance_passed FROM master.admin.merge_requests WHERE id = ? LIMIT 1",
      list(mr_id)
    ),
    error = function(e) data.frame(compliance_passed = NA)
  )
  if (!isTRUE(compliance_row$compliance_passed[1])) {
    stop("Merge blocked: compliance failed. Run compliance check before approving.")
  }

  merge_request_refresh_conflicts(con, mr_id)

  n_unresolved <- merge_request_unresolved_count(con, mr_id)
  if (n_unresolved > 0) {
    stop(sprintf(
      "Merge blocked: %d unresolved conflict(s). Resolve via merge_request_resolve_conflict().",
      n_unresolved
    ))
  }

  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(reviewer))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  approved_by_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  for (cfg in SYNC_TABLE_CONFIG) {
    tryCatch(
      .apply_table(con, mr_id, cfg),
      error = function(e) warning(sprintf(".apply_table failed for %s: %s", cfg$local, e$message))
    )
  }

  .delete_staging(con, mr_id)

  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET status = 'merged', reviewer = ?, reviewer_user_id = ?,
         review_notes = ?, reviewed_utc = now()
     WHERE id = ?",
    list(as.character(reviewer), approved_by_user_id,
         as.character(review_notes), mr_id)
  )

  mr_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT record_counts FROM master.admin.merge_requests WHERE id = ?",
      list(mr_id)
    ),
    error = function(e) data.frame(record_counts = "{}")
  )
  total_records <- tryCatch({
    rc <- jsonlite::fromJSON(mr_row$record_counts[1] %||% "{}")
    as.integer(sum(unlist(rc), na.rm = TRUE))
  }, error = function(e) 0L)

  tryCatch(
    DBI::dbExecute(
      con,
      "INSERT INTO master.admin.merge_history
         (merge_request_id, approved_by_user_id, record_count)
       VALUES (?, ?, ?)",
      list(mr_id, approved_by_user_id, total_records)
    ),
    error = function(e) warning("merge_history INSERT failed: ", e$message)
  )

  invisible(TRUE)
}

#' Reject a merge request, discarding all staged data.
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @param reviewer         Character. Reviewer email/username.
#' @param review_notes     Character. Optional notes.
merge_reject_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  mr_id <- as.integer(merge_request_id)

  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(reviewer))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  reviewer_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  .delete_staging(con, mr_id)
  DBI::dbExecute(
    con,
    "DELETE FROM master.admin.merge_conflicts WHERE merge_request_id = ?",
    list(mr_id)
  )
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET status = 'rejected', reviewer = ?, reviewer_user_id = ?,
         review_notes = ?, reviewed_utc = now()
     WHERE id = ?",
    list(as.character(reviewer), reviewer_user_id,
         as.character(review_notes), mr_id)
  )
  invisible(TRUE)
}


# =============================================================================
# 10. Field-user helpers (used by mod_sync)
# =============================================================================

#' Retrieve the current user's merge requests from master.
#' @param con           DuckDB connection.
#' @param submitter     Character. Matched against submitter_name.
#' @param show_approved Logical. Include merged/approved. Default TRUE.
#' @param show_rejected Logical. Include rejected. Default TRUE.
#' @return data.frame: id, project_id, submitted_utc, status,
#'   record_counts, review_notes, reviewed_utc.
# =============================================================================
# 11. Master schema bootstrap (idempotent)
# =============================================================================

#' Ensure all required master schemas and tables exist.
#'
#' Idempotent — safe to call multiple times. Creates:
#'   master.admin  — merge_requests, merge_conflicts
#'   master.staging — sample_env, sample_su, sample_veg
#'   master.core    — sample_env, sample_su, sample_veg
#'
#' @param con DuckDB connection (master must already be attached).
#' @return Invisible TRUE.
merge_ensure_tables <- function(con) {
  sync_require_cloud(con)

  # Schemas
  for (schema in c("master.admin", "master.staging", "master.core")) {
    DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
  }

  # master.admin.merge_requests
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.admin.merge_requests (
      id                INTEGER PRIMARY KEY,
      project_id        TEXT NOT NULL,
      submitter_user_id TEXT,
      submitter_name    TEXT,
      submitted_utc     TIMESTAMPTZ DEFAULT now(),
      status            TEXT DEFAULT 'pending_review',
      reviewer          TEXT,
      reviewer_user_id  INTEGER,
      review_notes      TEXT,
      reviewed_utc      TIMESTAMPTZ,
      env_record_count  INTEGER DEFAULT 0,
      su_record_count   INTEGER DEFAULT 0,
      veg_record_count  INTEGER DEFAULT 0,
      record_counts     TEXT,
      compliance_passed BOOLEAN,
      compliance_report TEXT
    )
  ")

  # master.admin.merge_conflicts
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.admin.merge_conflicts (
      id                INTEGER PRIMARY KEY,
      merge_request_id  INTEGER NOT NULL,
      table_name        TEXT NOT NULL,
      record_id         TEXT NOT NULL,
      details           TEXT,
      resolution        TEXT,
      resolved_by       TEXT,
      resolved_utc      TIMESTAMPTZ,
      created_utc       TIMESTAMPTZ DEFAULT now()
    )
  ")

  # master.staging tables
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.staging.sample_env (
      plot_number       TEXT,
      project_id        TEXT,
      latitude          DOUBLE,
      longitude         DOUBLE,
      elevation_m       DOUBLE,
      survey_date       DATE,
      surveyor_name     TEXT,
      plot_notes        TEXT,
      merge_request_id  INTEGER,
      modified_by       TEXT,
      baseRowVersion    INTEGER,
      changeType        TEXT,
      rowVersion        INTEGER,
      lastModifiedUTC   TIMESTAMPTZ,
      modifiedBy        TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.staging.sample_su (
      plot_number       TEXT,
      project_id        TEXT,
      su_number         TEXT,
      bec_zone          TEXT,
      bec_subzone       TEXT,
      site_series       TEXT,
      merge_request_id  INTEGER,
      modified_by       TEXT,
      baseRowVersion    INTEGER,
      changeType        TEXT,
      rowVersion        INTEGER,
      lastModifiedUTC   TIMESTAMPTZ,
      modifiedBy        TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.staging.sample_veg (
      plot_number       TEXT,
      project_id        TEXT,
      species_code      TEXT,
      layer_code        TEXT,
      cover1            REAL,
      cover2            REAL,
      cover3            REAL,
      totala            REAL,
      totalb            REAL,
      merge_request_id  INTEGER,
      modified_by       TEXT,
      baseRowVersion    INTEGER,
      changeType        TEXT,
      rowVersion        INTEGER,
      lastModifiedUTC   TIMESTAMPTZ,
      modifiedBy        TEXT
    )
  ")

  # master.core tables
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.core.sample_env (
      plot_number       TEXT UNIQUE,
      project_id        TEXT,
      latitude          DOUBLE,
      longitude         DOUBLE,
      elevation_m       DOUBLE,
      survey_date       DATE,
      surveyor_name     TEXT,
      plot_notes        TEXT,
      modified_by       TEXT,
      row_version       INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now()
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.core.sample_su (
      plot_number       TEXT UNIQUE,
      project_id        TEXT,
      su_number         TEXT,
      bec_zone          TEXT,
      bec_subzone       TEXT,
      site_series       TEXT,
      modified_by       TEXT,
      row_version       INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now()
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS master.core.sample_veg (
      plot_number       TEXT,
      project_id        TEXT,
      species_code      TEXT,
      layer_code        TEXT,
      cover1            REAL,
      cover2            REAL,
      cover3            REAL,
      totala            REAL,
      totalb            REAL,
      modified_by       TEXT,
      row_version       INTEGER DEFAULT 1,
      last_modified_utc TIMESTAMPTZ DEFAULT now(),
      UNIQUE(plot_number, species_code, layer_code, project_id)
    )
  ")

  invisible(TRUE)
}

#' Alias for merge_request_unresolved_count (used in mod_merge.R / mod_admin_merge.R).
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @return Integer.
merge_request_unresolved_conflict_count <- function(con, merge_request_id) {
  merge_request_unresolved_count(con, merge_request_id)
}


# =============================================================================
# 12. Field-user helpers (used by mod_sync)
# =============================================================================

sync_get_user_merge_requests <- function(con, submitter,
                                          show_approved = TRUE,
                                          show_rejected = TRUE) {
  empty_mr <- data.frame(
    id            = integer(0),
    project_id    = character(0),
    submitted_utc = as.POSIXct(character(0)),
    status        = character(0),
    record_counts = character(0),
    review_notes  = character(0),
    reviewed_utc  = as.POSIXct(character(0)),
    stringsAsFactors = FALSE
  )
  if (!sync_cloud_connected(con)) return(empty_mr)

  out <- tryCatch(
    DBI::dbGetQuery(
      con,
      paste0(
        "SELECT id, project_id, submitted_utc, status,",
        " record_counts, review_notes, reviewed_utc",
        " FROM master.admin.merge_requests",
        " WHERE submitter_name = ?",
        " ORDER BY submitted_utc DESC"
      ),
      list(as.character(submitter))
    ),
    error = function(e) empty_mr
  )
  if (nrow(out) == 0) return(empty_mr)

  if (!isTRUE(show_approved)) {
    out <- out[!out$status %in% c("merged", "approved"), , drop = FALSE]
  }
  if (!isTRUE(show_rejected)) {
    out <- out[out$status != "rejected", , drop = FALSE]
  }
  out
}
