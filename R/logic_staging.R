#' Staging Submission Functions for VPro Data
#'
#' This module handles submission of validated data to PostgreSQL staging tables
#' for admin review. Creates merge requests and populates staging tables with
#' change tracking (INSERT/UPDATE/DELETE).

#' Submit changes across multiple tables
#'
#' Wraps submit_to_staging to handle multiple tables and change types in a single
#' merge request. All tables are submitted within the same transaction.
#'
#' @param pg_con PostgreSQL database connection
#' @param changes_list Named list with structure:
#'   list(
#'     sample_veg = list(inserts = df, updates = df, deletes = df),
#'     sample_env = list(inserts = df, updates = df, deletes = df),
#'     sample_su = list(inserts = df, updates = df, deletes = df)
#'   )
#' @param user_name Character: submitter's name
#' @param user_email Character: submitter's email
#' @param project_id Integer: project ID for the merge request
#'
#' @return List with elements:
#'   - merge_request_id: Integer ID of the merge request
#'   - summary: Data.frame with counts per table and change type
#'
#' @examples
#' \dontrun{
#' # Multiple tables with multiple change types
#' changes <- list(
#'   sample_veg = list(
#'     inserts = data.frame(plot_number = "PLOT001", ...),
#'     updates = data.frame(plot_number = "PLOT002", ...),
#'     deletes = data.frame(plot_number = "PLOT003", ...)
#'   ),
#'   sample_env = list(
#'     inserts = data.frame(plot_number = "PLOT001", ...)
#'   )
#' )
#' result <- submit_changes(pg_con, changes, "John Doe", "john@example.com", 1)
#' 
#' # Single table with single change type
#' single_change <- list(
#'   sample_veg = list(inserts = veg_data)
#' )
#' result <- submit_changes(pg_con, single_change, "John Doe", "john@example.com", 1)
#' }
#'
#' @export
submit_changes <- function(pg_con, changes_list, user_name, user_email, project_id = 1) {
  
  # Count total rows to submit
  total_rows <- 0
  for (table in names(changes_list)) {
    for (change_type in names(changes_list[[table]])) {
      if (!is.null(changes_list[[table]][[change_type]]) && 
          nrow(changes_list[[table]][[change_type]]) > 0) {
        total_rows <- total_rows + nrow(changes_list[[table]][[change_type]])
      }
    }
  }
  
  if (total_rows == 0) {
    stop("No changes to submit")
  }
  
  # Begin transaction
  DBI::dbBegin(pg_con)
  
  tryCatch({
    # Create single merge request
    merge_request_id <- DBI::dbGetQuery(pg_con, sprintf("
      INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, submitted_utc, status, record_counts)
      VALUES (%d, '%s', '%s', CURRENT_TIMESTAMP, 'pending_review', '{}'::JSONB)
      RETURNING id
    ", project_id, user_name, user_email))$id
    
    # Track record counts
    record_counts <- list()
    summary_rows <- list()
    
    # Process each table
    for (table in names(changes_list)) {
      if (!table %in% c("sample_veg", "sample_env", "sample_su")) {
        stop(sprintf("Invalid table name: %s", table))
      }
      
      table_counts <- list()
      
      # Process inserts
      if (!is.null(changes_list[[table]]$inserts) && 
          nrow(changes_list[[table]]$inserts) > 0) {
        data <- changes_list[[table]]$inserts
        
        # Validate before inserting
        if (table == "sample_veg") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_veg_row(data[i, ], pg_con, "postgres")
            if (!val_result$valid) {
              stop(sprintf("%s insert row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        } else if (table == "sample_env") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_env_row(data[i, ], pg_con)
            if (!val_result$valid) {
              stop(sprintf("%s insert row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        } else if (table == "sample_su") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_su_row(data[i, ], pg_con, "postgres")
            if (!val_result$valid) {
              stop(sprintf("%s insert row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        }
        
        data$merge_request_id <- merge_request_id
        data$change_type <- "I"
        DBI::dbWriteTable(pg_con, DBI::Id(schema = "staging", table = table),
                         data, append = TRUE, row.names = FALSE)
        
        table_counts$inserts <- nrow(data)
        summary_rows <- c(summary_rows, list(data.frame(
          table = table,
          change_type = "I",
          row_count = nrow(data),
          stringsAsFactors = FALSE
        )))
      }
      
      # Process updates
      if (!is.null(changes_list[[table]]$updates) && 
          nrow(changes_list[[table]]$updates) > 0) {
        data <- changes_list[[table]]$updates
        
        # Validate before updating
        if (table == "sample_veg") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_veg_row(data[i, ], pg_con, "postgres")
            if (!val_result$valid) {
              stop(sprintf("%s update row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        } else if (table == "sample_env") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_env_row(data[i, ], pg_con)
            if (!val_result$valid) {
              stop(sprintf("%s update row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        } else if (table == "sample_su") {
          for (i in seq_len(nrow(data))) {
            val_result <- validate_su_row(data[i, ], pg_con, "postgres")
            if (!val_result$valid) {
              stop(sprintf("%s update row %d validation failed: %s", table, i,
                          paste(val_result$errors, collapse = "; ")))
            }
          }
        }
        
        data$merge_request_id <- merge_request_id
        data$change_type <- "U"
        DBI::dbWriteTable(pg_con, DBI::Id(schema = "staging", table = table),
                         data, append = TRUE, row.names = FALSE)
        
        table_counts$updates <- nrow(data)
        summary_rows <- c(summary_rows, list(data.frame(
          table = table,
          change_type = "U",
          row_count = nrow(data),
          stringsAsFactors = FALSE
        )))
      }
      
      # Process deletes
      if (!is.null(changes_list[[table]]$deletes) && 
          nrow(changes_list[[table]]$deletes) > 0) {
        data <- changes_list[[table]]$deletes
        
        data$merge_request_id <- merge_request_id
        data$change_type <- "D"
        DBI::dbWriteTable(pg_con, DBI::Id(schema = "staging", table = table),
                         data, append = TRUE, row.names = FALSE)
        
        table_counts$deletes <- nrow(data)
        summary_rows <- c(summary_rows, list(data.frame(
          table = table,
          change_type = "D",
          row_count = nrow(data),
          stringsAsFactors = FALSE
        )))
      }
      
      if (length(table_counts) > 0) {
        record_counts[[table]] <- table_counts
      }
    }
    
    # Update record counts in merge_requests
    count_json <- jsonlite::toJSON(record_counts, auto_unbox = TRUE)
    DBI::dbExecute(pg_con, sprintf("
      UPDATE staging.merge_requests 
      SET record_counts = '%s'::JSONB
      WHERE id = %d
    ", count_json, merge_request_id))
    
    # Commit transaction
    DBI::dbCommit(pg_con)
    
    summary_df <- do.call(rbind, summary_rows)
    
    message(sprintf("Successfully submitted %d rows across %d tables (merge_request_id: %d)",
                   total_rows, length(names(changes_list)), merge_request_id))
    
    return(list(
      merge_request_id = merge_request_id,
      summary = summary_df
    ))
    
  }, error = function(e) {
    DBI::dbRollback(pg_con)
    stop(sprintf("Failed to submit changes: %s", e$message))
  })
}
