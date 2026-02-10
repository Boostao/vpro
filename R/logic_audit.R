# Audit trail helpers

audit_table_name <- "user_db.main.USysAuditTrail"

parse_qualified_table <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NULL)
  parts <- strsplit(name, "\\.")[[1]]
  if (length(parts) != 3) return(NULL)
  list(catalog = parts[[1]], schema = parts[[2]], table = parts[[3]])
}

table_exists_qualified <- function(con, name) {
  parsed <- parse_qualified_table(name)
  if (is.null(parsed)) return(DBI::dbExistsTable(con, name))
  info <- tryCatch(
    DBI::dbGetQuery(con, "SELECT database_name, schema_name, table_name FROM duckdb_tables() WHERE internal = FALSE"),
    error = function(e) data.frame()
  )
  if (nrow(info) == 0) return(FALSE)
  any(
    tolower(info$database_name) == tolower(parsed$catalog) &
      tolower(info$schema_name) == tolower(parsed$schema) &
      tolower(info$table_name) == tolower(parsed$table)
  )
}

quote_ident <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NA_character_)
  paste0("\"", gsub("\"", "\"\"", name), "\"")
}

get_audit_table_fields <- function(con) {
  if (!audit_table_exists(con)) return(character(0))
  fields <- character(0)
  try({
    fields <- DBI::dbListFields(con, audit_table_name)
  }, silent = TRUE)
  if (length(fields) == 0) {
    try({
      fields <- DBI::dbListFields(con, audit_table_name)
    }, silent = TRUE)
  }
  fields
}

resolve_audit_column <- function(con, candidates) {
  fields <- get_audit_table_fields(con)
  if (length(fields) == 0) return(NULL)
  for (candidate in candidates) {
    idx <- which(tolower(fields) == tolower(candidate))
    if (length(idx) > 0) return(fields[[idx[1]]])
  }
  NULL
}

audit_table_name_col <- function(con) {
  resolve_audit_column(con, c("Table", "table", "_table"))
}

audit_table_exists <- function(con) {
  table_exists_qualified(con, audit_table_name)
}

ensure_audit_table <- function(con) {
  if (audit_table_exists(con)) return(TRUE)

  tryCatch({
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS user_db.main.USysAuditTrail (
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
  if (is.null(plot_number) || is.null(table_name) || is.null(field_name)) {
    return(invisible(FALSE))
  }

  resolved_project <- project_id
  if (is.null(resolved_project) || !nzchar(as.character(resolved_project))) {
    resolved_project <- resolve_project_id_for_plot(con, plot_number, fallback_project = project_id)
  }
  if (is.null(resolved_project) || !nzchar(as.character(resolved_project))) {
    return(invisible(FALSE))
  }

  if (!ensure_audit_table(con)) return(invisible(FALSE))

  if (is.na(before_value) && is.na(after_value)) return(invisible(FALSE))
  if (!is.na(before_value) && !is.na(after_value) && as.character(before_value) == as.character(after_value)) {
    return(invisible(FALSE))
  }

  DBI::dbExecute(
    con,
    "INSERT INTO user_db.main.USysAuditTrail (Project, \"User\", PlotNumber, \"Table\", EditField, EditWhen, BeforeEdit, AfterEdit)
     VALUES (?, ?, ?, ?, ?, now(), ?, ?)",
    list(
      resolved_project,
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

resolve_project_id_for_plot <- function(con, plot_number, fallback_project = NULL) {
  if (is.null(plot_number) || !nzchar(as.character(plot_number))) return(fallback_project)
  if (!DBI::dbExistsTable(con, "Sample_Env")) return(fallback_project)

  fields <- tryCatch(DBI::dbListFields(con, "Sample_Env"), error = function(e) character(0))
  if (!("PlotNumber" %in% fields) || !("ProjectID" %in% fields)) return(fallback_project)

  res <- DBI::dbGetQuery(
    con,
    "SELECT ProjectID FROM Sample_Env WHERE PlotNumber = ? LIMIT 1",
    list(as.character(plot_number))
  )
  if (nrow(res) == 0) return(fallback_project)
  project_id <- res$ProjectID[1]
  if (is.na(project_id) || !nzchar(as.character(project_id))) return(fallback_project)
  as.character(project_id)
}

fetch_audit_entries <- function(con, plot_number = NULL, project_id = NULL, table_name = NULL, date_from = NULL, date_to = NULL, limit = NULL, offset = NULL) {
  if (!audit_table_exists(con)) return(data.frame())

  table_col <- audit_table_name_col(con)
  if (is.null(table_col)) return(data.frame())
  table_col_sql <- quote_ident(table_col)
    sql <- sprintf(
      "SELECT Project, \"User\", PlotNumber, %s AS TableName, EditField, EditWhen, BeforeEdit, AfterEdit FROM user_db.main.USysAuditTrail",
      table_col_sql
    )
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
    filters <- c(filters, paste(table_col_sql, "= ?"))
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

  if (!is.null(limit)) {
    sql <- paste(sql, "ORDER BY EditWhen DESC LIMIT ?")
    params <- c(params, list(as.integer(limit)))
    if (!is.null(offset)) {
      sql <- paste(sql, "OFFSET ?")
      params <- c(params, list(as.integer(offset)))
    }
  }

  DBI::dbGetQuery(con, sql, params)
}

fetch_master_audit_entries <- function(con, user = NULL, action = NULL, node_name = NULL, date_from = NULL, date_to = NULL, limit = NULL, offset = NULL) {
  if (!master_audit_table_exists(con)) return(data.frame())

  sql <- "SELECT \"User\", Action, NodeName, NodeID, Parent, EditField, EditWhen, BeforeEdit, AfterEdit FROM user_db.main.USysMasterAudit"
  filters <- c()
  params <- list()

  if (!is.null(user)) {
    filters <- c(filters, "\"User\" = ?")
    params <- c(params, list(user))
  }
  if (!is.null(action)) {
    filters <- c(filters, "Action = ?")
    params <- c(params, list(action))
  }
  if (!is.null(node_name)) {
    filters <- c(filters, "NodeName = ?")
    params <- c(params, list(node_name))
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

  if (!is.null(limit)) {
    sql <- paste(sql, "ORDER BY EditWhen DESC LIMIT ?")
    params <- c(params, list(as.integer(limit)))
    if (!is.null(offset)) {
      sql <- paste(sql, "OFFSET ?")
      params <- c(params, list(as.integer(offset)))
    }
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

    if (is.null(project_value) || !nzchar(as.character(project_value))) {
      project_value <- resolve_project_id_for_plot(con, plot_number, fallback_project = project_value)
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

master_audit_table_name <- "user_db.main.USysMasterAudit"

master_audit_table_exists <- function(con) {
  table_exists_qualified(con, master_audit_table_name)
}

ensure_master_audit_table <- function(con) {
  if (master_audit_table_exists(con)) return(TRUE)

  tryCatch({
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS user_db.main.USysMasterAudit (
        \"User\" TEXT,
        Action TEXT,
        NodeName TEXT,
        NodeID INTEGER,
        Parent TEXT,
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

log_master_audit <- function(con, user, action, node_name, node_id, edit_field, before_edit, after_edit, parent = NULL) {
  if (is.null(node_name) || is.null(node_id) || is.null(action)) return(invisible(FALSE))
  if (!ensure_master_audit_table(con)) return(invisible(FALSE))

  DBI::dbExecute(
    con,
    "INSERT INTO user_db.main.USysMasterAudit (\"User\", Action, NodeName, NodeID, Parent, EditField, EditWhen, BeforeEdit, AfterEdit)
     VALUES (?, ?, ?, ?, ?, ?, now(), ?, ?)",
    list(
      if (is.null(user) || length(user) == 0) "Unknown" else user,
      action,
      node_name,
      as.integer(node_id),
      if (is.null(parent) || !nzchar(as.character(parent))) NA else as.character(parent),
      if (is.null(edit_field)) NA else edit_field,
      ifelse(is.na(before_edit), NA, as.character(before_edit)),
      ifelse(is.na(after_edit), NA, as.character(after_edit))
    )
  )

  invisible(TRUE)
}
