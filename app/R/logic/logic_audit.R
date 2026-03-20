# Audit trail helpers

audit_table_name <- "VUser.main.USysAuditTrail"

list_duckdb_tables <- function(con) {
  tryCatch(
    DBI::dbGetQuery(con, "SELECT database_name, schema_name, table_name FROM duckdb_tables() WHERE internal = FALSE"),
    error = function(e) data.frame()
  )
}

resolve_qualified_table <- function(con, candidates, fallback = NULL) {
  info <- list_duckdb_tables(con)
  if (nrow(info) > 0) {
    qualified <- paste(info$database_name, info$schema_name, info$table_name, sep = ".")
    for (candidate in candidates) {
      idx <- which(tolower(qualified) == tolower(candidate))
      if (length(idx) > 0) return(qualified[[idx[[1]]]])
    }
  }
  fallback
}

parse_qualified_table <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NULL)
  parts <- strsplit(name, "\\.")[[1]]
  if (length(parts) != 3) return(NULL)
  list(catalog = parts[[1]], schema = parts[[2]], table = parts[[3]])
}

table_exists_qualified <- function(con, name) {
  parsed <- parse_qualified_table(name)
  if (is.null(parsed)) return(DBI::dbExistsTable(con, name))
  info <- list_duckdb_tables(con)
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

quote_qualified_table <- function(name) {
  parsed <- parse_qualified_table(name)
  if (is.null(parsed)) return(quote_ident(name))
  paste(vapply(unname(parsed), quote_ident, character(1)), collapse = ".")
}

get_table_fields_qualified <- function(con, name) {
  parsed <- parse_qualified_table(name)
  if (is.null(parsed)) {
    return(tryCatch(DBI::dbListFields(con, name), error = function(e) character(0)))
  }

  columns <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT column_name FROM duckdb_columns() WHERE lower(database_name) = lower(?) AND lower(schema_name) = lower(?) AND lower(table_name) = lower(?) ORDER BY column_index",
      list(parsed$catalog, parsed$schema, parsed$table)
    ),
    error = function(e) data.frame()
  )
  if (nrow(columns) == 0) return(character(0))
  as.character(columns$column_name)
}

get_table_columns_qualified <- function(con, name) {
  parsed <- parse_qualified_table(name)
  if (is.null(parsed)) return(data.frame())

  tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT column_name, data_type FROM duckdb_columns() WHERE lower(database_name) = lower(?) AND lower(schema_name) = lower(?) AND lower(table_name) = lower(?) ORDER BY column_index",
      list(parsed$catalog, parsed$schema, parsed$table)
    ),
    error = function(e) data.frame()
  )
}

get_table_column_type <- function(con, name, column_name) {
  if (is.null(column_name) || !nzchar(column_name)) return(NA_character_)
  info <- get_table_columns_qualified(con, name)
  if (nrow(info) == 0) return(NA_character_)
  idx <- which(tolower(info$column_name) == tolower(column_name))
  if (length(idx) == 0) return(NA_character_)
  as.character(info$data_type[[idx[[1]]]])
}

is_text_like_type <- function(data_type) {
  if (is.na(data_type) || !nzchar(data_type)) return(FALSE)
  grepl("char|string|text|varchar|clob", tolower(data_type))
}

audit_table_candidates <- function() {
  c(
    "VUser.main.USysAuditTrail",
    "VLists.main.USysAuditTrail",
    "vpro.main.USysAudit",
    "vpro.main.Audit"
  )
}

audit_table_ref <- function(con) {
  resolve_qualified_table(con, audit_table_candidates(), fallback = audit_table_name)
}

get_audit_table_fields <- function(con) {
  table_ref <- audit_table_ref(con)
  if (!table_exists_qualified(con, table_ref)) return(character(0))
  get_table_fields_qualified(con, table_ref)
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

audit_table_project_col <- function(con) resolve_audit_column(con, c("Project", "project"))
audit_table_user_col <- function(con) resolve_audit_column(con, c("User", "user", "_user"))
audit_table_plot_col <- function(con) resolve_audit_column(con, c("PlotNumber", "plotnumber"))
audit_table_field_col <- function(con) resolve_audit_column(con, c("EditField", "editfield"))
audit_table_when_col <- function(con) resolve_audit_column(con, c("EditWhen", "editwhen"))
audit_table_before_col <- function(con) resolve_audit_column(con, c("BeforeEdit", "beforeedit"))
audit_table_after_col <- function(con) resolve_audit_column(con, c("AfterEdit", "afteredit"))

audit_table_exists <- function(con) {
  table_exists_qualified(con, audit_table_ref(con))
}

normalize_audit_table_schema <- function(con) {
  table_ref <- audit_table_ref(con)
  if (!table_exists_qualified(con, table_ref)) return(FALSE)

  plot_col <- audit_table_plot_col(con)
  if (is.null(plot_col)) return(TRUE)

  plot_type <- get_table_column_type(con, table_ref, plot_col)
  if (is_text_like_type(plot_type)) return(TRUE)

  parsed <- parse_qualified_table(table_ref)
  if (is.null(parsed)) return(FALSE)

  fields <- get_table_fields_qualified(con, table_ref)
  if (length(fields) == 0) return(FALSE)

  temp_table_name <- paste0(parsed$table, "__vpro_text_migration")
  temp_table_ref <- paste(parsed$catalog, parsed$schema, temp_table_name, sep = ".")
  select_list <- vapply(fields, function(field) {
    field_sql <- quote_ident(field)
    if (tolower(field) == tolower(plot_col)) {
      sprintf("CAST(%s AS VARCHAR) AS %s", field_sql, field_sql)
    } else {
      sprintf("%s AS %s", field_sql, field_sql)
    }
  }, character(1))

  tryCatch({
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", quote_qualified_table(temp_table_ref)))
      DBI::dbExecute(
        con,
        sprintf(
          "CREATE TABLE %s AS SELECT %s FROM %s",
          quote_qualified_table(temp_table_ref),
          paste(select_list, collapse = ", "),
          quote_qualified_table(table_ref)
        )
      )
      DBI::dbExecute(con, sprintf("DROP TABLE %s", quote_qualified_table(table_ref)))
      DBI::dbExecute(
        con,
        sprintf(
          "ALTER TABLE %s RENAME TO %s",
          quote_qualified_table(temp_table_ref),
          quote_ident(parsed$table)
        )
      )
    })
    TRUE
  }, error = function(e) {
    FALSE
  })
}

ensure_audit_table <- function(con) {
  if (audit_table_exists(con)) return(normalize_audit_table_schema(con))

  tryCatch({
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS VUser.main.USysAuditTrail (
        project TEXT,
        _user TEXT,
        plotnumber TEXT,
        _table TEXT,
        editfield TEXT,
        editwhen TIMESTAMP,
        beforeedit TEXT,
        afteredit TEXT
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

  table_ref <- audit_table_ref(con)
  project_col <- audit_table_project_col(con)
  user_col <- audit_table_user_col(con)
  plot_col <- audit_table_plot_col(con)
  table_col <- audit_table_name_col(con)
  field_col <- audit_table_field_col(con)
  when_col <- audit_table_when_col(con)
  before_col <- audit_table_before_col(con)
  after_col <- audit_table_after_col(con)
  required_cols <- c(project_col, user_col, plot_col, table_col, field_col, before_col, after_col)
  if (any(vapply(required_cols, is.null, logical(1)))) return(invisible(FALSE))

  insert_cols <- c(project_col, user_col, plot_col, table_col, field_col)
  insert_vals <- c("?", "?", "?", "?", "?")
  params <- list(
    resolved_project,
    if (is.null(user) || length(user) == 0) "Unknown" else user,
    plot_number,
    table_name,
    field_name
  )
  if (!is.null(when_col)) {
    insert_cols <- c(insert_cols, when_col)
    insert_vals <- c(insert_vals, "CURRENT_TIMESTAMP")
  }
  insert_cols <- c(insert_cols, before_col, after_col)
  insert_vals <- c(insert_vals, "?", "?")
  params <- c(params, list(
    ifelse(is.na(before_value), NA, as.character(before_value)),
    ifelse(is.na(after_value), NA, as.character(after_value))
  ))

  insert_sql <- sprintf(
    "INSERT INTO %s (%s) VALUES (%s)",
    quote_qualified_table(table_ref),
    paste(vapply(insert_cols, quote_ident, character(1)), collapse = ", "),
    paste(insert_vals, collapse = ", ")
  )
  DBI::dbExecute(con, insert_sql, params)

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
  if (!DBI::dbExistsTable(con, "Env")) return(fallback_project)

  fields <- tryCatch(DBI::dbListFields(con, "Env"), error = function(e) character(0))
  plot_col <- fields[match(tolower("PlotNumber"), tolower(fields), nomatch = 0L)]
  project_col <- fields[match(tolower("ProjectID"), tolower(fields), nomatch = 0L)]
  if (length(plot_col) == 0 || length(project_col) == 0) return(fallback_project)

  res <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT %s AS project_id FROM %s WHERE %s = ? LIMIT 1",
      quote_ident(project_col[[1]]),
      quote_ident("Env"),
      quote_ident(plot_col[[1]])
    ),
    list(as.character(plot_number))
  )
  if (nrow(res) == 0) return(fallback_project)
  project_id <- res$project_id[1]
  if (is.na(project_id) || !nzchar(as.character(project_id))) return(fallback_project)
  as.character(project_id)
}

fetch_audit_entries <- function(con, plot_number = NULL, project_id = NULL, table_name = NULL, date_from = NULL, date_to = NULL, limit = NULL, offset = NULL) {
  if (!audit_table_exists(con)) return(data.frame())

  table_ref <- audit_table_ref(con)
  project_col <- audit_table_project_col(con)
  user_col <- audit_table_user_col(con)
  plot_col <- audit_table_plot_col(con)
  table_col <- audit_table_name_col(con)
  field_col <- audit_table_field_col(con)
  when_col <- audit_table_when_col(con)
  before_col <- audit_table_before_col(con)
  after_col <- audit_table_after_col(con)
  required_cols <- c(project_col, user_col, plot_col, table_col, field_col, when_col, before_col, after_col)
  if (any(vapply(required_cols, is.null, logical(1)))) return(data.frame())

  project_col_sql <- quote_ident(project_col)
  user_col_sql <- quote_ident(user_col)
  plot_col_sql <- quote_ident(plot_col)
  table_col_sql <- quote_ident(table_col)
  field_col_sql <- quote_ident(field_col)
  when_col_sql <- quote_ident(when_col)
  before_col_sql <- quote_ident(before_col)
  after_col_sql <- quote_ident(after_col)
  sql <- sprintf(
    "SELECT %s AS Project, %s AS User, %s AS PlotNumber, %s AS TableName, %s AS EditField, %s AS EditWhen, %s AS BeforeEdit, %s AS AfterEdit FROM %s",
    project_col_sql,
    user_col_sql,
    plot_col_sql,
    table_col_sql,
    field_col_sql,
    when_col_sql,
    before_col_sql,
    after_col_sql,
    quote_qualified_table(table_ref)
  )
  filters <- c()
  params <- list()

  if (!is.null(plot_number)) {
    filters <- c(filters, paste(plot_col_sql, "= ?"))
    params <- c(params, list(plot_number))
  }
  if (!is.null(project_id)) {
    filters <- c(filters, paste(project_col_sql, "= ?"))
    params <- c(params, list(project_id))
  }
  if (!is.null(table_name)) {
    filters <- c(filters, paste(table_col_sql, "= ?"))
    params <- c(params, list(table_name))
  }
  if (!is.null(date_from)) {
    filters <- c(filters, paste(when_col_sql, ">= ?"))
    params <- c(params, list(date_from))
  }
  if (!is.null(date_to)) {
    filters <- c(filters, paste(when_col_sql, "<= ?"))
    params <- c(params, list(date_to))
  }

  if (length(filters) > 0) {
    sql <- paste(sql, "WHERE", paste(filters, collapse = " AND "))
  }

  if (!is.null(limit)) {
    sql <- paste(sql, "ORDER BY", when_col_sql, "DESC LIMIT ?")
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

  table_ref <- master_audit_table_ref(con)
  user_col <- resolve_master_audit_column(con, c("User", "user", "_user"))
  action_col <- resolve_master_audit_column(con, c("Action", "action", "_action"))
  node_name_col <- resolve_master_audit_column(con, c("NodeName", "nodename"))
  node_id_col <- resolve_master_audit_column(con, c("NodeID", "nodeid"))
  parent_col <- resolve_master_audit_column(con, c("Parent", "parent"))
  field_col <- resolve_master_audit_column(con, c("EditField", "editfield"))
  when_col <- resolve_master_audit_column(con, c("EditWhen", "editwhen"))
  before_col <- resolve_master_audit_column(con, c("BeforeEdit", "beforeedit"))
  after_col <- resolve_master_audit_column(con, c("AfterEdit", "afteredit"))
  required_cols <- c(user_col, action_col, node_name_col, node_id_col, field_col, when_col, before_col, after_col)
  if (any(vapply(required_cols, is.null, logical(1)))) return(data.frame())

  user_col_sql <- quote_ident(user_col)
  action_col_sql <- quote_ident(action_col)
  node_name_col_sql <- quote_ident(node_name_col)
  node_id_col_sql <- quote_ident(node_id_col)
  parent_col_sql <- if (!is.null(parent_col)) quote_ident(parent_col) else "NULL"
  field_col_sql <- quote_ident(field_col)
  when_col_sql <- quote_ident(when_col)
  before_col_sql <- quote_ident(before_col)
  after_col_sql <- quote_ident(after_col)
  sql <- sprintf(
    "SELECT %s AS User, %s AS Action, %s AS NodeName, %s AS NodeID, %s AS Parent, %s AS EditField, %s AS EditWhen, %s AS BeforeEdit, %s AS AfterEdit FROM %s",
    user_col_sql,
    action_col_sql,
    node_name_col_sql,
    node_id_col_sql,
    parent_col_sql,
    field_col_sql,
    when_col_sql,
    before_col_sql,
    after_col_sql,
    quote_qualified_table(table_ref)
  )
  filters <- c()
  params <- list()

  if (!is.null(user)) {
    filters <- c(filters, paste(user_col_sql, "= ?"))
    params <- c(params, list(user))
  }
  if (!is.null(action)) {
    filters <- c(filters, paste(action_col_sql, "= ?"))
    params <- c(params, list(action))
  }
  if (!is.null(node_name)) {
    filters <- c(filters, paste(node_name_col_sql, "= ?"))
    params <- c(params, list(node_name))
  }
  if (!is.null(date_from)) {
    filters <- c(filters, paste(when_col_sql, ">= ?"))
    params <- c(params, list(date_from))
  }
  if (!is.null(date_to)) {
    filters <- c(filters, paste(when_col_sql, "<= ?"))
    params <- c(params, list(date_to))
  }

  if (length(filters) > 0) {
    sql <- paste(sql, "WHERE", paste(filters, collapse = " AND "))
  }

  if (!is.null(limit)) {
    sql <- paste(sql, "ORDER BY", when_col_sql, "DESC LIMIT ?")
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

master_audit_table_name <- "VLists.main.USysMasterAudit"

master_audit_table_candidates <- function() {
  c(
    "VLists.main.USysMasterAudit",
    "VUser.main.USysMasterAudit"
  )
}

master_audit_table_ref <- function(con) {
  resolve_qualified_table(con, master_audit_table_candidates(), fallback = master_audit_table_name)
}

get_master_audit_fields <- function(con) {
  table_ref <- master_audit_table_ref(con)
  if (!table_exists_qualified(con, table_ref)) return(character(0))
  get_table_fields_qualified(con, table_ref)
}

resolve_master_audit_column <- function(con, candidates) {
  fields <- get_master_audit_fields(con)
  if (length(fields) == 0) return(NULL)
  for (candidate in candidates) {
    idx <- which(tolower(fields) == tolower(candidate))
    if (length(idx) > 0) return(fields[[idx[[1]]]])
  }
  NULL
}

master_audit_table_exists <- function(con) {
  table_exists_qualified(con, master_audit_table_ref(con))
}

ensure_master_audit_table <- function(con) {
  if (master_audit_table_exists(con)) return(TRUE)

  tryCatch({
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS VLists.main.USysMasterAudit (
        _user TEXT,
        _action TEXT,
        nodename TEXT,
        nodeid INTEGER,
        parent TEXT,
        editfield TEXT,
        editwhen TIMESTAMP,
        beforeedit TEXT,
        afteredit TEXT
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

  table_ref <- master_audit_table_ref(con)
  user_col <- resolve_master_audit_column(con, c("User", "user", "_user"))
  action_col <- resolve_master_audit_column(con, c("Action", "action", "_action"))
  node_name_col <- resolve_master_audit_column(con, c("NodeName", "nodename"))
  node_id_col <- resolve_master_audit_column(con, c("NodeID", "nodeid"))
  parent_col <- resolve_master_audit_column(con, c("Parent", "parent"))
  field_col <- resolve_master_audit_column(con, c("EditField", "editfield"))
  when_col <- resolve_master_audit_column(con, c("EditWhen", "editwhen"))
  before_col <- resolve_master_audit_column(con, c("BeforeEdit", "beforeedit"))
  after_col <- resolve_master_audit_column(con, c("AfterEdit", "afteredit"))
  required_cols <- c(user_col, action_col, node_name_col, node_id_col, field_col, before_col, after_col)
  if (any(vapply(required_cols, is.null, logical(1)))) return(invisible(FALSE))

  insert_cols <- c(user_col, action_col, node_name_col, node_id_col)
  insert_vals <- c("?", "?", "?", "?")
  params <- list(
    if (is.null(user) || length(user) == 0) "Unknown" else user,
    action,
    node_name,
    as.integer(node_id)
  )

  if (!is.null(parent_col)) {
    insert_cols <- c(insert_cols, parent_col)
    insert_vals <- c(insert_vals, "?")
    params <- c(params, list(if (is.null(parent) || !nzchar(as.character(parent))) NA else as.character(parent)))
  }

  insert_cols <- c(insert_cols, field_col)
  insert_vals <- c(insert_vals, "?")
  params <- c(params, list(if (is.null(edit_field)) NA else edit_field))

  if (!is.null(when_col)) {
    insert_cols <- c(insert_cols, when_col)
    insert_vals <- c(insert_vals, "CURRENT_TIMESTAMP")
  }

  insert_cols <- c(insert_cols, before_col, after_col)
  insert_vals <- c(insert_vals, "?", "?")
  params <- c(params, list(
    ifelse(is.na(before_edit), NA, as.character(before_edit)),
    ifelse(is.na(after_edit), NA, as.character(after_edit))
  ))

  insert_sql <- sprintf(
    "INSERT INTO %s (%s) VALUES (%s)",
    quote_qualified_table(table_ref),
    paste(vapply(insert_cols, quote_ident, character(1)), collapse = ", "),
    paste(insert_vals, collapse = ", ")
  )
  DBI::dbExecute(con, insert_sql, params)

  invisible(TRUE)
}
