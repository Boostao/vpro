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

fetch_audit_entries <- function(con, plot_number = NULL, project_id = NULL, table_name = NULL) {
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

  if (length(filters) > 0) {
    sql <- paste(sql, "WHERE", paste(filters, collapse = " AND "))
  }

  DBI::dbGetQuery(con, sql, params)
}
