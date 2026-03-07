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
  invisible(TRUE)
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

  pk       <- cfg$pk
  tmp_name <- paste0("tmp_push_", cfg$pg)
  DBI::dbExecute(con, paste0("DROP TABLE IF EXISTS ", tmp_name))

  # Sanitize project_id: only allow alphanumeric and simple separators
  pid_safe <- gsub("[^A-Za-z0-9_-]", "", as.character(project_id))

  # Build project scoping filter (project_id from auth session, sanitized)
  proj_filter <- if (cfg$project_scope == "direct") {
    paste0('l."projectid" = ', "'", pid_safe, "'")
  } else {
    paste0(
      'l."', cfg$env_fk, '" IN ',
      '(SELECT "plotnumber" FROM "Env" WHERE "projectid" = ', "'", pid_safe, "')"
    )
  }

  col_select <- paste(sprintf('l."%s"', shared_cols), collapse = ", ")

  DBI::dbExecute(con, sprintf(
    'CREATE TEMP TABLE %s AS
     SELECT %s,
            CAST(c."rowVersion" AS INTEGER) AS _base_row_version,
            CASE WHEN CAST(c."%s" AS TEXT) IS NULL THEN \'I\' ELSE \'U\' END AS _changetype
     FROM "%s" l
     LEFT JOIN master.core.%s c
       ON CAST(c."%s" AS TEXT) = CAST(l."%s" AS TEXT)
     WHERE l.local_modified_utc IS NOT NULL
       AND %s',
    tmp_name, col_select,
    pk,
    cfg$local, cfg$pg,
    pk, pk,
    proj_filter
  ))

  n <- tryCatch(
    as.integer(DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", tmp_name))$n[1]),
    error = function(e) 0L
  )
  if (n == 0L) return(0L)

  staging_col_list <- paste(
    c('"merge_request_id"', '"changeType"', '"baseRowVersion"', '"modifiedBy"',
      sprintf('"%s"', shared_cols)),
    collapse = ", "
  )
  # Build select list: literal mr_id via DBI param, submitter as sanitized literal
  sub_safe <- gsub("'", "", as.character(submitter))
  select_col_list <- paste(
    c("?", "_changetype", "_base_row_version",
      paste0("'", sub_safe, "'"),
      sprintf('"%s"', shared_cols)),
    collapse = ", "
  )

  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO master.staging.%s (%s) SELECT %s FROM %s",
      cfg$pg, staging_col_list, select_col_list, tmp_name
    ),
    list(as.integer(mr_id))
  )
  n
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
    if (!DBI::dbExistsTable(con, cfg$local)) {
      out[[cfg$pg]] <- data.frame(table_pg = character(0), change_type = character(0))
      next
    }
    fields  <- tryCatch(DBI::dbListFields(con, cfg$local), error = function(e) character(0))
    has_lmu <- "local_modified_utc" %in% fields
    if (!has_lmu) {
      out[[cfg$pg]] <- data.frame(table_pg = character(0), change_type = character(0))
      next
    }

    pid_safe <- if (!is.null(project_id) && nzchar(as.character(project_id)))
      gsub("[^A-Za-z0-9_-]", "", as.character(project_id)) else NULL

    if (cfg$project_scope == "direct") {
      pid_clause <- if (!is.null(pid_safe))
        paste0(' AND "projectid" = \'', pid_safe, '\'') else ""

      has_rv <- "rowversion" %in% tolower(fields)
      ct_expr <- if (has_rv)
        "CASE WHEN \"rowVersion\" IS NULL THEN 'insert' ELSE 'update' END"
      else
        "'insert'"

      sql <- sprintf(
        "SELECT '%s' AS table_pg, %s AS change_type FROM \"%s\" WHERE local_modified_utc IS NOT NULL%s",
        cfg$pg, ct_expr, cfg$local, pid_clause
      )
    } else {
      pid_clause <- if (!is.null(pid_safe))
        sprintf(
          ' AND "%s" IN (SELECT "plotnumber" FROM "Env" WHERE "projectid" = \'%s\')',
          cfg$env_fk, pid_safe
        ) else ""

      sql <- sprintf(
        "SELECT '%s' AS table_pg, 'update' AS change_type FROM \"%s\" WHERE local_modified_utc IS NOT NULL%s",
        cfg$pg, cfg$local, pid_clause
      )
    }

    out[[cfg$pg]] <- tryCatch(
      DBI::dbGetQuery(con, sql),
      error = function(e) data.frame(table_pg = character(0), change_type = character(0))
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
  if (!DBI::dbExistsTable(con, cfg$local)) return(list())

  fields <- tryCatch(DBI::dbListFields(con, cfg$local), error = function(e) character(0))
  if (!"local_modified_utc" %in% fields) return(list())

  pk       <- cfg$pk
  pid_safe <- if (!is.null(project_id) && nzchar(as.character(project_id)))
    gsub("[^A-Za-z0-9_-]", "", as.character(project_id)) else NULL

  # Build project filter (same logic as sync_get_local_changes)
  proj_filter <- if (!is.null(pid_safe)) {
    if (cfg$project_scope == "direct") {
      paste0(' AND "projectid" = \'', pid_safe, '\'')
    } else {
      sprintf(
        ' AND "%s" IN (SELECT "plotnumber" FROM "Env" WHERE "projectid" = \'%s\')',
        cfg$env_fk, pid_safe
      )
    }
  } else ""

  local_rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        'SELECT * FROM "%s" WHERE local_modified_utc IS NOT NULL%s LIMIT %d',
        cfg$local, proj_filter, as.integer(max_rows)
      )
    ),
    error = function(e) data.frame()
  )
  if (nrow(local_rows) == 0) return(list())

  # Fetch matching core rows (only when cloud is connected)
  pk_values <- as.character(local_rows[[pk]])
  pk_placeholders <- paste(rep("?", length(pk_values)), collapse = ", ")

  core_rows <- if (sync_cloud_connected(con) && length(pk_values) > 0) {
    tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf(
          'SELECT * FROM master.core.%s WHERE CAST("%s" AS TEXT) IN (%s)',
          cfg$pg, pk, pk_placeholders
        ),
        as.list(pk_values)
      ),
      error = function(e) data.frame()
    )
  } else {
    data.frame()
  }

  # Build lookup: pk_value (character) -> core row as list
  core_lookup <- if (nrow(core_rows) > 0) {
    setNames(
      lapply(seq_len(nrow(core_rows)), function(i) as.list(core_rows[i, , drop = FALSE])),
      as.character(core_rows[[pk]])
    )
  } else {
    list()
  }

  # Build per-row detail records
  lapply(seq_len(nrow(local_rows)), function(i) {
    row       <- local_rows[i, , drop = FALSE]
    pk_val    <- as.character(row[[pk]])
    core_data <- core_lookup[[pk_val]]

    change_type <- if (is.null(core_data)) "insert" else "update"

    # Strip internal metadata from local_data
    local_list <- as.list(row)
    local_list[["local_modified_utc"]] <- NULL

    list(
      pk_value    = pk_val,
      change_type = change_type,
      local_data  = local_list,
      core_data   = core_data
    )
  })
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
      "INSERT INTO master.core.%s (%s)
       SELECT %s
       FROM master.staging.%s s
       LEFT JOIN master.admin.merge_conflicts mc
         ON  mc.merge_request_id = s.merge_request_id
         AND mc.table_name       = '%s'
         AND mc.record_id        = CAST(s.\"%s\" AS TEXT)
       WHERE s.merge_request_id = ?
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
