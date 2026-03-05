# logic_merge.R
# Admin review and merge functions for VPro staging workflow

#' List all pending merge requests
#'
#' Returns all merge_requests with status='pending_review', including
#' submitter info and record counts.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @return data.frame with columns: id, project_id, submitter_name, 
#'   submitter_email, submitted_utc, record_counts (parsed from JSONB)
#' @export
#' @examples
#' \dontrun{
#'   pending <- list_pending_merges(pg_con)
#'   print(pending)
#' }
list_pending_merges <- function(pg_con) {
  query <- "
    SELECT 
      id,
      project_id,
      submitter_name,
      submitter_email,
      submitted_utc,
      status,
      record_counts::text as record_counts
    FROM staging.merge_requests
    WHERE status = 'pending_review'
    ORDER BY submitted_utc ASC
  "
  
  result <- DBI::dbGetQuery(pg_con, query)
  
  # Parse record_counts JSONB if present
  if (nrow(result) > 0 && "record_counts" %in% names(result)) {
    result$record_counts <- lapply(result$record_counts, function(x) {
      if (is.na(x) || x == "") return(list())
      jsonlite::fromJSON(x)
    })
  }
  
  return(result)
}


#' Get detailed staging data for a merge request
#'
#' Returns all staging rows (veg, env, su) associated with a merge request,
#' grouped by table and change_type.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param merge_request_id integer merge request ID
#' @return Named list with elements: veg, env, su.
#'   Each element is a data.frame with staging rows (if any exist).
#' @export
#' @examples
#' \dontrun{
#'   details <- get_merge_details(pg_con, merge_request_id = 1)
#'   print(details$veg)
#' }
get_merge_details <- function(pg_con, merge_request_id) {
  if (!is.numeric(merge_request_id) || merge_request_id <= 0) {
    stop("merge_request_id must be a positive integer")
  }
  
  tables <- c("veg", "env", "su")
  result <- list()
  
  for (tbl in tables) {
    query <- sprintf(
      "SELECT * FROM staging.%s WHERE merge_request_id = $1",
      tbl
    )
    data <- DBI::dbGetQuery(pg_con, query, params = list(merge_request_id))
    result[[tbl]] <- data
  }
  
  return(result)
}


#' Detect conflicts for a single table
#'
#' Internal utility function to detect conflicts for one table.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param merge_request_id integer merge request ID
#' @param table_name character table name (without schema prefix)
#' @param natural_keys character vector of natural key column names
#' @return data.frame with conflict rows
#' @keywords internal
detect_table_conflicts <- function(pg_con, merge_request_id, table_name, 
                                   natural_keys) {
  # Build natural key join condition
  key_joins <- paste(sprintf("sv.%s = cv.%s", natural_keys, natural_keys), 
                     collapse = " AND ")
  key_joins_other <- paste(sprintf("sv.%s = other.%s", natural_keys, natural_keys),
                           collapse = " AND ")
  
  # Build key display string for column_name field
  key_display <- paste(sprintf("%s=%%s", natural_keys), collapse = ",")
  
  query <- sprintf("
    WITH staging_data AS (
      SELECT %s, merge_request_id, change_type
      FROM staging.%s
      WHERE merge_request_id = $1 AND change_type IN ('I', 'U')
    ),
    core_conflicts AS (
      SELECT 
        sv.*,
        CASE 
          WHEN sv.change_type = 'I' THEN 'insert_collision'
          ELSE 'update_target_missing'
        END as conflict_type
      FROM staging_data sv
      LEFT JOIN core.%s cv ON %s
      WHERE (sv.change_type = 'I' AND cv.id IS NOT NULL)
         OR (sv.change_type = 'U' AND cv.id IS NULL)
    ),
    cross_conflicts AS (
      SELECT DISTINCT
        sv.*,
        'cross_request' as conflict_type
      FROM staging_data sv
      INNER JOIN staging.%s other
        ON %s
        AND other.merge_request_id != sv.merge_request_id
      INNER JOIN staging.merge_requests mr
        ON other.merge_request_id = mr.id
        AND mr.status = 'pending_review'
    )
    SELECT * FROM core_conflicts
    UNION ALL
    SELECT * FROM cross_conflicts
  ", 
  paste(natural_keys, collapse = ", "),
  table_name,
  table_name,
  key_joins,
  table_name,
  key_joins_other)
  
  conflicts <- DBI::dbGetQuery(pg_con, query, params = list(merge_request_id))
  
  # Add table name and formatted key display
  if (nrow(conflicts) > 0) {
    conflicts$table_name <- table_name
    conflicts$key_display <- apply(conflicts[, natural_keys, drop = FALSE], 1, 
                                   function(row) {
                                     do.call(sprintf, c(list(key_display), as.list(row)))
                                   })
  }
  
  return(conflicts)
}


#' Write conflicts to staging.merge_conflicts table
#'
#' Internal utility function to insert conflict records.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param conflicts data.frame with conflict data
#' @return invisible(TRUE)
#' @keywords internal
write_conflicts_to_db <- function(pg_con, conflicts) {
  if (nrow(conflicts) == 0) {
    return(invisible(TRUE))
  }
  
  for (i in 1:nrow(conflicts)) {
    conflict <- conflicts[i, ]
    
    # Get plot_number (all tables have this)
    plot_number <- if ("plot_number" %in% names(conflict)) {
      conflict$plot_number
    } else {
      NA_character_
    }
    
    DBI::dbExecute(pg_con, "
      INSERT INTO staging.merge_conflicts 
        (merge_request_id, table_name, plot_number, column_name, 
         local_value, incoming_value, resolved, resolution)
      VALUES ($1, $2, $3, $4, $5, $6, FALSE, NULL)
    ", params = list(
      conflict$merge_request_id,
      conflict$table_name,
      plot_number,
      conflict$key_display,
      conflict$conflict_type,
      "pending_resolution"
    ))
  }
  
  invisible(TRUE)
}


#' Detect conflicts for a merge request
#'
#' Checks for:
#' 1. Key collisions: staging rows whose natural keys already exist in core.*
#' 2. Cross-request conflicts: same keys in other pending requests
#' 
#' Writes conflicts to staging.merge_conflicts table.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param merge_request_id integer merge request ID
#' @return data.frame with conflict summary (table_name, conflict_count)
#' @export
#' @examples
#' \dontrun{
#'   conflicts <- detect_conflicts(pg_con, merge_request_id = 1)
#'   print(conflicts)
#' }
detect_conflicts <- function(pg_con, merge_request_id) {
  if (!is.numeric(merge_request_id) || merge_request_id <= 0) {
    stop("merge_request_id must be a positive integer")
  }
  
  # Clear existing conflicts for this merge request
  DBI::dbExecute(
    pg_con,
    "DELETE FROM staging.merge_conflicts WHERE merge_request_id = $1",
    params = list(merge_request_id)
  )
  
  conflict_summary <- data.frame(
    table_name = character(),
    conflict_count = integer(),
    stringsAsFactors = FALSE
  )
  
  # Define natural keys for each table
  table_configs <- list(
    veg = c("plot_number", "species_code", "layer_code", "project_id"),
    env = c("plot_number"),
    su = c("plot_number")
  )
  
  # Define natural keys for each table
  table_configs <- list(
    veg = c("plot_number", "species_code", "layer_code", "project_id"),
    env = c("plot_number"),
    su = c("plot_number")
  )
  
  # Detect conflicts for each table
  for (table_name in names(table_configs)) {
    natural_keys <- table_configs[[table_name]]
    
    conflicts <- detect_table_conflicts(pg_con, merge_request_id, 
                                       table_name, natural_keys)
    
    if (nrow(conflicts) > 0) {
      write_conflicts_to_db(pg_con, conflicts)
      
      conflict_summary <- rbind(conflict_summary,
        data.frame(
          table_name = table_name,
          conflict_count = nrow(conflicts),
          stringsAsFactors = FALSE
        ))
    }
  }
  
  if (nrow(conflict_summary) == 0) {
    conflict_summary <- data.frame(
      table_name = character(0),
      conflict_count = integer(0)
    )
  }
  
  return(conflict_summary)
}


#' Resolve a specific conflict
#'
#' Marks a conflict as resolved with chosen resolution strategy.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param conflict_id integer conflict ID from staging.merge_conflicts
#' @param resolution character resolution strategy: 'keep_incoming', 
#'   'keep_existing', 'manual'
#' @return invisible(TRUE) on success
#' @export
#' @examples
#' \dontrun{
#'   resolve_conflict(pg_con, conflict_id = 1, resolution = "keep_incoming")
#' }
resolve_conflict <- function(pg_con, conflict_id, resolution) {
  if (!is.numeric(conflict_id) || conflict_id <= 0) {
    stop("conflict_id must be a positive integer")
  }
  
  valid_resolutions <- c("keep_incoming", "keep_existing", "manual")
  if (!resolution %in% valid_resolutions) {
    stop(sprintf("resolution must be one of: %s", 
                 paste(valid_resolutions, collapse = ", ")))
  }
  
  rows_affected <- DBI::dbExecute(pg_con, "
    UPDATE staging.merge_conflicts
    SET resolved = TRUE, resolution = $1
    WHERE id = $2
  ", params = list(resolution, conflict_id))
  
  if (rows_affected == 0) {
    stop(sprintf("Conflict with id=%d not found", conflict_id))
  }
  
  invisible(TRUE)
}


#' Approve and merge a staging request to core tables
#'
#' Merges staging data to core in a single transaction with automatic
#' audit trigger activation. All conflicts must be resolved first.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param merge_request_id integer merge request ID
#' @param reviewer character reviewer name (for audit trail)
#' @return Named list with merge summary (tables_merged, rows_inserted,
#'   rows_updated, rows_deleted, audit_entries_created)
#' @export
#' @examples
#' \dontrun{
#'   summary <- approve_merge(pg_con, merge_request_id = 1, 
#'                           reviewer = "admin@example.com")
#'   print(summary)
#' }
approve_merge <- function(pg_con, merge_request_id, reviewer) {
  if (!is.numeric(merge_request_id) || merge_request_id <= 0) {
    stop("merge_request_id must be a positive integer")
  }
  if (!is.character(reviewer) || nchar(reviewer) == 0) {
    stop("reviewer must be a non-empty string")
  }
  
  # Check merge request exists and is pending
  mr <- DBI::dbGetQuery(pg_con, "
    SELECT id, status 
    FROM staging.merge_requests 
    WHERE id = $1
  ", params = list(merge_request_id))
  
  if (nrow(mr) == 0) {
    stop(sprintf("Merge request %d not found", merge_request_id))
  }
  if (mr$status != "pending_review") {
    stop(sprintf("Merge request %d has status '%s', expected 'pending_review'",
                 merge_request_id, mr$status))
  }
  
  # Check for unresolved conflicts
  unresolved <- DBI::dbGetQuery(pg_con, "
    SELECT COUNT(*) as cnt
    FROM staging.merge_conflicts
    WHERE merge_request_id = $1 AND resolved = FALSE
  ", params = list(merge_request_id))
  
  if (unresolved$cnt > 0) {
    stop(sprintf("Merge request %d has %d unresolved conflicts", 
                 as.integer(merge_request_id), as.integer(unresolved$cnt)))
  }
  
  # Begin transaction
  DBI::dbBegin(pg_con)
  
  tryCatch({
    summary <- list(
      tables_merged = character(),
      rows_inserted = 0,
      rows_updated = 0,
      rows_deleted = 0,
      audit_entries_created = 0
    )
    
    audit_before <- DBI::dbGetQuery(pg_con, 
      "SELECT COUNT(*) as cnt FROM audit.logged_actions")$cnt
    
    # Process veg
    veg_inserts <- DBI::dbExecute(pg_con, "
      INSERT INTO core.veg 
        (plot_number, species_code, layer_code, cover_percent, height_cm, 
         cover_code, project_id, modified_by)
      SELECT 
        plot_number, species_code, layer_code, cover_percent, height_cm,
        cover_code, project_id, $2
      FROM staging.veg
      WHERE merge_request_id = $1 AND change_type = 'I'
    ", params = list(merge_request_id, reviewer))
    
    veg_updates <- DBI::dbExecute(pg_con, "
      UPDATE core.veg cv
      SET 
        cover_percent = sv.cover_percent,
        height_cm = sv.height_cm,
        cover_code = sv.cover_code,
        modified_by = $2
      FROM staging.veg sv
      WHERE sv.merge_request_id = $1 
        AND sv.change_type = 'U'
        AND cv.plot_number = sv.plot_number
        AND cv.species_code = sv.species_code
        AND cv.layer_code = sv.layer_code
        AND cv.project_id = sv.project_id
    ", params = list(merge_request_id, reviewer))
    
    veg_deletes <- DBI::dbExecute(pg_con, "
      DELETE FROM core.veg cv
      USING staging.veg sv
      WHERE sv.merge_request_id = $1 
        AND sv.change_type = 'D'
        AND cv.plot_number = sv.plot_number
        AND cv.species_code = sv.species_code
        AND cv.layer_code = sv.layer_code
        AND cv.project_id = sv.project_id
    ", params = list(merge_request_id))
    
    if (veg_inserts + veg_updates + veg_deletes > 0) {
      summary$tables_merged <- c(summary$tables_merged, "veg")
      summary$rows_inserted <- summary$rows_inserted + veg_inserts
      summary$rows_updated <- summary$rows_updated + veg_updates
      summary$rows_deleted <- summary$rows_deleted + veg_deletes
    }
    
    # Process env
    env_inserts <- DBI::dbExecute(pg_con, "
      INSERT INTO core.env 
        (plot_number, project_id, latitude, longitude, elevation_m,
         survey_date, surveyor_name, plot_notes, modified_by)
      SELECT 
        plot_number, project_id, latitude, longitude, elevation_m,
        survey_date, surveyor_name, plot_notes, $2
      FROM staging.env
      WHERE merge_request_id = $1 AND change_type = 'I'
    ", params = list(merge_request_id, reviewer))
    
    env_updates <- DBI::dbExecute(pg_con, "
      UPDATE core.env ce
      SET 
        latitude = se.latitude,
        longitude = se.longitude,
        elevation_m = se.elevation_m,
        survey_date = se.survey_date,
        surveyor_name = se.surveyor_name,
        plot_notes = se.plot_notes,
        modified_by = $2
      FROM staging.env se
      WHERE se.merge_request_id = $1 
        AND se.change_type = 'U'
        AND ce.plot_number = se.plot_number
    ", params = list(merge_request_id, reviewer))
    
    env_deletes <- DBI::dbExecute(pg_con, "
      DELETE FROM core.env ce
      USING staging.env se
      WHERE se.merge_request_id = $1 
        AND se.change_type = 'D'
        AND ce.plot_number = se.plot_number
    ", params = list(merge_request_id))
    
    if (env_inserts + env_updates + env_deletes > 0) {
      summary$tables_merged <- c(summary$tables_merged, "env")
      summary$rows_inserted <- summary$rows_inserted + env_inserts
      summary$rows_updated <- summary$rows_updated + env_updates
      summary$rows_deleted <- summary$rows_deleted + env_deletes
    }
    
    # Process su
    su_inserts <- DBI::dbExecute(pg_con, "
      INSERT INTO core.su 
        (plot_number, project_id, su_number, bec_zone, bec_subzone, 
         site_series, modified_by)
      SELECT 
        plot_number, project_id, su_number, bec_zone, bec_subzone,
        site_series, $2
      FROM staging.su
      WHERE merge_request_id = $1 AND change_type = 'I'
    ", params = list(merge_request_id, reviewer))
    
    su_updates <- DBI::dbExecute(pg_con, "
      UPDATE core.su cs
      SET 
        su_number = ss.su_number,
        bec_zone = ss.bec_zone,
        bec_subzone = ss.bec_subzone,
        site_series = ss.site_series,
        modified_by = $2
      FROM staging.su ss
      WHERE ss.merge_request_id = $1 
        AND ss.change_type = 'U'
        AND cs.plot_number = ss.plot_number
    ", params = list(merge_request_id, reviewer))
    
    su_deletes <- DBI::dbExecute(pg_con, "
      DELETE FROM core.su cs
      USING staging.su ss
      WHERE ss.merge_request_id = $1 
        AND ss.change_type = 'D'
        AND cs.plot_number = ss.plot_number
    ", params = list(merge_request_id))
    
    if (su_inserts + su_updates + su_deletes > 0) {
      summary$tables_merged <- c(summary$tables_merged, "su")
      summary$rows_inserted <- summary$rows_inserted + su_inserts
      summary$rows_updated <- summary$rows_updated + su_updates
      summary$rows_deleted <- summary$rows_deleted + su_deletes
    }
    
    # Count audit entries created
    audit_after <- DBI::dbGetQuery(pg_con,
      "SELECT COUNT(*) as cnt FROM audit.logged_actions")$cnt
    summary$audit_entries_created <- audit_after - audit_before
    
    # Update merge request status
    DBI::dbExecute(pg_con, "
      UPDATE staging.merge_requests
      SET 
        status = 'merged',
        reviewer = $2,
        reviewed_utc = CURRENT_TIMESTAMP
      WHERE id = $1
    ", params = list(merge_request_id, reviewer))
    
    DBI::dbCommit(pg_con)
    
    return(summary)
    
  }, error = function(e) {
    DBI::dbRollback(pg_con)
    stop(sprintf("Merge failed: %s", e$message))
  })
}


#' Reject a merge request
#'
#' Sets merge request status to 'rejected' with review notes.
#' Staging data remains for reference.
#'
#' @param pg_con DBI connection to PostgreSQL
#' @param merge_request_id integer merge request ID
#' @param reviewer character reviewer name
#' @param reason character rejection reason
#' @return invisible(TRUE) on success
#' @export
#' @examples
#' \dontrun{
#'   reject_merge(pg_con, merge_request_id = 1, 
#'                reviewer = "admin@example.com",
#'                reason = "Incomplete data quality checks")
#' }
reject_merge <- function(pg_con, merge_request_id, reviewer, reason) {
  if (!is.numeric(merge_request_id) || merge_request_id <= 0) {
    stop("merge_request_id must be a positive integer")
  }
  if (!is.character(reviewer) || nchar(reviewer) == 0) {
    stop("reviewer must be a non-empty string")
  }
  if (!is.character(reason) || nchar(reason) == 0) {
    stop("reason must be a non-empty string")
  }
  
  # Check merge request exists and is pending
  mr <- DBI::dbGetQuery(pg_con, "
    SELECT id, status 
    FROM staging.merge_requests 
    WHERE id = $1
  ", params = list(merge_request_id))
  
  if (nrow(mr) == 0) {
    stop(sprintf("Merge request %d not found", merge_request_id))
  }
  if (mr$status != "pending_review") {
    stop(sprintf("Merge request %d has status '%s', expected 'pending_review'",
                 merge_request_id, mr$status))
  }
  
  rows_affected <- DBI::dbExecute(pg_con, "
    UPDATE staging.merge_requests
    SET 
      status = 'rejected',
      reviewer = $2,
      review_notes = $3,
      reviewed_utc = CURRENT_TIMESTAMP
    WHERE id = $1
  ", params = list(merge_request_id, reviewer, reason))
  
  if (rows_affected == 0) {
    stop(sprintf("Failed to reject merge request %d", merge_request_id))
  }
  
  invisible(TRUE)
}
