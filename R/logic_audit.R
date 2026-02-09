# Audit trail helpers

audit_table_name <- "user.USysAuditTrail"

audit_table_exists <- function(con) {
  DBI::dbExistsTable(con, audit_table_name)
}

ensure_audit_table <- function(con) {
  if (audit_table_exists(con)) return(TRUE)

  tryCatch({
    DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS user")
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS user.USysAuditTrail (
        Project TEXT,
        \"User\" TEXT,
        PlotNumber TEXT,
        \"Table\" TEXT,
        EditField TEXT,
        EditWhen TIMESTAMP,
        BeforeEdit TEXT,
        AfterEdit TEXT
      )
    ")
    TRUE
  }, error = function(e) {
    FALSE
  })
}

log_audit_change <- function(con, project_id, user, plot_number, table_name, field_name, before_value, after_value) {
  if (is.null(project_id) || is.null(plot_number) || is.null(table_name) || is.null(field_name)) {
    return(invisible(FALSE))
  }

  if (!ensure_audit_table(con)) return(invisible(FALSE))

  if (is.na(before_value) && is.na(after_value)) return(invisible(FALSE))
  if (!is.na(before_value) && !is.na(after_value) && as.character(before_value) == as.character(after_value)) {
    return(invisible(FALSE))
  }

  DBI::dbExecute(
    con,
    "INSERT INTO user.USysAuditTrail (Project, \"User\", PlotNumber, \"Table\", EditField, EditWhen, BeforeEdit, AfterEdit)
     VALUES (?, ?, ?, ?, ?, now(), ?, ?)",
    list(
      project_id,
      if (is.null(user) || length(user) == 0) "Unknown" else user,
      plot_number,
      table_name,
      field_name,
      ifelse(is.na(before_value), NA, as.character(before_value)),
      ifelse(is.na(after_value), NA, as.character(after_value))
    )
  )

  invisible(TRUE)
}

log_audit_diff <- function(con, project_id, user, plot_number, table_name, old_row, new_row, fields = NULL) {
  if (is.null(old_row) || is.null(new_row)) return(0L)

  old_row <- as.list(old_row)
  new_row <- as.list(new_row)

  if (is.null(fields)) {
    fields <- intersect(names(old_row), names(new_row))
  }

  if (length(fields) == 0) return(0L)

  logged <- 0L
  for (field_name in fields) {
    before_value <- old_row[[field_name]]
    after_value <- new_row[[field_name]]
    if (length(before_value) > 1) before_value <- before_value[1]
    if (length(after_value) > 1) after_value <- after_value[1]
    if (isTRUE(log_audit_change(con, project_id, user, plot_number, table_name, field_name, before_value, after_value))) {
      logged <- logged + 1L
    }
  }

  logged
}

fetch_audit_entries <- function(con, plot_number = NULL, project_id = NULL, table_name = NULL, date_from = NULL, date_to = NULL) {
  if (!audit_table_exists(con)) return(data.frame())

  sql <- "SELECT Project, \"User\", PlotNumber, \"Table\", EditField, EditWhen, BeforeEdit, AfterEdit FROM user.USysAuditTrail"
  filters <- c()
  params <- list()

  if (!is.null(plot_number)) {
    filters <- c(filters, "PlotNumber = ?")
    params <- c(params, list(plot_number))
  }
  if (!is.null(project_id)) {
    filters <- c(filters, "Project = ?")
    params <- c(params, list(project_id))
  }
  if (!is.null(table_name)) {
    filters <- c(filters, "\"Table\" = ?")
    params <- c(params, list(table_name))
  }
  if (!is.null(date_from)) {
    filters <- c(filters, "EditWhen >= ?")
    params <- c(params, list(date_from))
  }
  if (!is.null(date_to)) {
    filters <- c(filters, "EditWhen <= ?")
    params <- c(params, list(date_to))
  }

  if (length(filters) > 0) {
    sql <- paste(sql, "WHERE", paste(filters, collapse = " AND "))
  }

  DBI::dbGetQuery(con, sql, params)
}

log_audit_rows <- function(con, project_id, user, table_name, rows, fields = NULL, plot_col = "plotnumber", project_col = "projectid") {
  if (is.null(rows)) return(0L)
  rows_df <- as.data.frame(rows)
  if (nrow(rows_df) == 0) return(0L)

  if (is.null(fields)) {
    fields <- names(rows_df)
  }
  if (length(fields) == 0) return(0L)

  logged <- 0L
  for (row_idx in seq_len(nrow(rows_df))) {
    plot_number <- if (plot_col %in% names(rows_df)) rows_df[[plot_col]][row_idx] else NA
    if (is.na(plot_number) || !nzchar(as.character(plot_number))) next

    project_value <- project_id
    if (!is.null(project_col) && project_col %in% names(rows_df)) {
      row_project <- rows_df[[project_col]][row_idx]
      if (!is.na(row_project) && nzchar(as.character(row_project))) {
        project_value <- row_project
      }
    }

    for (field_name in fields) {
      if (!(field_name %in% names(rows_df))) next
      value <- rows_df[[field_name]][row_idx]
      if (length(value) > 1) value <- value[1]
      if (isTRUE(log_audit_change(con, project_value, user, plot_number, table_name, field_name, NA, value))) {
        logged <- logged + 1L
      }
    }
  }

  logged
}
