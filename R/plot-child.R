# Plot child records --------------------------------------------------------

vpro_plot_child_id <- function(id) {
  if (
    length(id) != 1L ||
      is.na(id) ||
      !is.numeric(id) ||
      !isTRUE(id == floor(id)) ||
      id < -2147483648 ||
      id > 2147483647
  ) {
    stop("`id` must be one nonmissing signed 32-bit integer value.", call. = FALSE)
  }
  id
}

vpro_plot_child_row <- function(con, table, plot_number, id) {
  sql <- paste(
    "SELECT * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ? AND",
    DBI::dbQuoteIdentifier(con, "ID"),
    "= ?"
  )
  DBI::dbGetQuery(con, sql, params = list(plot_number, id))
}

vpro_plot_child_assert_row <- function(row, kind, plot_number, id) {
  if (nrow(row) == 0L) {
    stop(
      "VPRO ",
      kind,
      " record does not exist for plot ",
      plot_number,
      " and ID ",
      id,
      ".",
      call. = FALSE
    )
  }
  if (nrow(row) != 1L) {
    stop(
      "VPRO ",
      kind,
      " record identity is not unique for plot ",
      plot_number,
      " and ID ",
      id,
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

vpro_plot_child_new_id <- function(con, table) {
  for (attempt in seq_len(100L)) {
    id <- floor(stats::runif(1L, -2147483647, 2147483648))
    found <- DBI::dbGetQuery(
      con,
      paste(
        "SELECT COUNT(*) AS n FROM",
        DBI::dbQuoteIdentifier(con, table),
        "WHERE",
        DBI::dbQuoteIdentifier(con, "ID"),
        "= ?"
      ),
      params = list(id)
    )$n[[1L]]
    if (found == 0L) {
      return(id)
    }
  }
  stop("Unable to generate an unused signed 32-bit child ID.", call. = FALSE)
}

vpro_plot_child_definitions <- function(con, table) {
  DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, table), ")")
  )
}

vpro_plot_child_validate_changes <- function(
  con,
  table,
  changes,
  kind,
  operation
) {
  changes <- vpro_plot_changes(changes, "values")
  if (any(c("PlotNumber", "ID") %in% names(changes))) {
    stop(kind, " record keys are managed by `", operation, "()`.", call. = FALSE)
  }
  definitions <- vpro_plot_child_definitions(con, table)
  unknown <- setdiff(names(changes), definitions$name)
  if (length(unknown) > 0L) {
    stop(
      "Unknown VPRO ",
      kind,
      " field(s): ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  for (field in names(changes)) {
    vpro_plot_validate_value(
      changes[[field]],
      field,
      definitions$type[match(field, definitions$name)]
    )
  }
  changes
}

vpro_plot_child_audit_rows <- function(
  project,
  user,
  plot_number,
  suffix,
  fields,
  before,
  after,
  id,
  audit_strength
) {
  audited <- vapply(
    seq_along(after),
    function(i) vpro_plot_audited(before[[i]], after[[i]], audit_strength),
    logical(1)
  )
  data.frame(
    Project = rep(project, sum(audited)),
    User = rep(user, sum(audited)),
    PlotNumber = rep(plot_number, sum(audited)),
    Table = rep(suffix, sum(audited)),
    EditField = fields[audited],
    EditWhen = rep(format(Sys.time(), tz = "UTC", usetz = TRUE), sum(audited)),
    BeforeEdit = vapply(before[audited], vpro_plot_audit_text, character(1)),
    AfterEdit = vapply(after[audited], vpro_plot_audit_text, character(1)),
    ID = rep(id, sum(audited)),
    stringsAsFactors = FALSE
  )
}

vpro_plot_child_create <- function(
  context,
  plot_number,
  values,
  kind,
  suffix,
  operation,
  user,
  audit_strength,
  validate = NULL
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  vpro_plot_get(context, plot_number)
  user <- vpro_plot_user(context, user)
  audit_strength <- vpro_plot_audit_strength(context, audit_strength)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  tables <- list(
    child = vpro_project_table(record$project, kind),
    audit = vpro_project_table(record$project, "Audit")
  )
  values <- vpro_plot_child_validate_changes(
    con,
    tables$child,
    values,
    kind,
    operation
  )
  if (is.function(validate)) {
    validate(values)
  }

  result <- DBI::dbWithTransaction(con, {
    id <- vpro_plot_child_new_id(con, tables$child)
    insert <- c(list(PlotNumber = plot_number, ID = id), values)
    sql <- paste(
      "INSERT INTO",
      DBI::dbQuoteIdentifier(con, tables$child),
      paste0(
        "(",
        paste(DBI::dbQuoteIdentifier(con, names(insert)), collapse = ", "),
        ") VALUES (",
        paste(rep("?", length(insert)), collapse = ", "),
        ")"
      )
    )
    DBI::dbExecute(con, sql, params = unname(insert))
    row <- vpro_plot_child_row(con, tables$child, plot_number, id)
    vpro_plot_child_assert_row(row, kind, plot_number, id)
    fields <- setdiff(names(row), c("PlotNumber", "ID"))
    after <- unname(as.list(row[1, fields, drop = FALSE]))
    audit <- vpro_plot_child_audit_rows(
      record$project,
      user,
      plot_number,
      suffix,
      fields,
      rep(list(NA), length(fields)),
      after,
      id,
      audit_strength
    )
    if (nrow(audit) > 0L) {
      DBI::dbAppendTable(con, tables$audit, audit)
    }
    list(row = row, audit = audit)
  })
  names(result)[[1L]] <- tolower(kind)
  invisible(result)
}

vpro_plot_child_delete <- function(context, plot_number, id, kind, label = kind) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  id <- vpro_plot_child_id(id)
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  table <- vpro_project_table(record$project, kind)
  deleted <- DBI::dbWithTransaction(con, {
    row <- vpro_plot_child_row(con, table, plot_number, id)
    vpro_plot_child_assert_row(row, label, plot_number, id)
    sql <- paste(
      "DELETE FROM",
      DBI::dbQuoteIdentifier(con, table),
      "WHERE",
      DBI::dbQuoteIdentifier(con, "PlotNumber"),
      "= ? AND",
      DBI::dbQuoteIdentifier(con, "ID"),
      "= ?"
    )
    affected <- DBI::dbExecute(con, sql, params = list(plot_number, id))
    if (affected != 1L) {
      stop("VPRO ", kind, " deletion did not affect exactly one row.", call. = FALSE)
    }
    row
  })
  invisible(deleted)
}
