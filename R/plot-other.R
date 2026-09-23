# Plot Other records --------------------------------------------------------

vpro_plot_other_id <- vpro_plot_child_id

vpro_plot_other_row <- vpro_plot_child_row

vpro_plot_other_apply_changes <- function(con, table, plot_number, id, changes) {
  assignments <- paste(DBI::dbQuoteIdentifier(con, names(changes)), "= ?", collapse = ", ")
  sql <- paste(
    "UPDATE",
    DBI::dbQuoteIdentifier(con, table),
    "SET",
    assignments,
    "WHERE",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ? AND",
    DBI::dbQuoteIdentifier(con, "ID"),
    "= ?"
  )
  DBI::dbExecute(con, sql, params = c(unname(changes), list(plot_number, id)))
}

#' List Other records for one plot in the active VPRO project
#'
#' Reads the canonical `_Other` child rows corresponding to Access's
#' `USysOther` record source. Rows are restricted to an existing plot in the
#' active project and ordered by `DataName`, with `ID` as a deterministic
#' tie-breaker. Active site-unit filtering does not hide base project rows.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#'
#' @return A data frame containing the plot's Other rows.
#' @export
vpro_plot_other_list <- function(context, plot_number) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_project_table(record$project, "Other")
  sql <- paste(
    "SELECT * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ? ORDER BY",
    DBI::dbQuoteIdentifier(con, "DataName"),
    ",",
    DBI::dbQuoteIdentifier(con, "ID")
  )
  DBI::dbGetQuery(con, sql, params = list(plot_number))
}

#' Create one Other record in the active VPRO project
#'
#' Creates a canonical `_Other` child row with a collision-checked signed
#' 32-bit ID. Access initializes the three user flags to false for a new row;
#' the package preserves those defaults unless callers supply explicit values.
#' At audit strength 2 or 3, populated fields are audited with the generated
#' child ID in the same transaction.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param values Named list of field values for the new row.
#' @param user Stable user identity for audit rows. Defaults to `Current.User`
#'   from the context configuration when available.
#' @param audit_strength Integer from 0 through 3. Defaults to
#'   `Audit.AuditStrength` from configuration, then 1 when unavailable.
#'
#' @return A list containing the created Other row and audit rows written,
#'   invisibly.
#' @export
vpro_plot_other_create <- function(
  context,
  plot_number,
  values = list(),
  user = NULL,
  audit_strength = NULL
) {
  defaults <- list(UserFlag1 = FALSE, UserFlag2 = FALSE, UserFlag3 = FALSE)
  values <- vpro_plot_changes(values, "values")
  values <- c(values, defaults[setdiff(names(defaults), names(values))])
  vpro_plot_child_create(
    context,
    plot_number,
    values,
    "Other",
    "_Other",
    "vpro_plot_other_create",
    user,
    audit_strength
  )
}

#' Delete one Other record from the active VPRO project
#'
#' Deletes an existing `_Other` row identified by plot and ID. The Access
#' bound-form workflow does not create audit rows for child-row deletion, so
#' this operation likewise performs no audit insertion.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param id Existing `_Other` child-row ID.
#'
#' @return The deleted row, invisibly.
#' @export
vpro_plot_other_delete <- function(context, plot_number, id) {
  vpro_plot_child_delete(context, plot_number, id, "Other")
}

#' Update one Other record in the active VPRO project
#'
#' Updates an existing `_Other` child row identified by plot and ID and writes
#' qualifying field-level audit rows in the same SQLite transaction. Audit
#' strength follows `V7mdlAudit.AuditTrail`, and each audit row retains the
#' child record ID used by Access restoration logic. Creation, deletion, and
#' audit restoration are separate operations.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param id Existing `_Other` child-row ID.
#' @param changes Named list of field values to update.
#' @param user Stable user identity for audit rows. Defaults to `Current.User`
#'   from the context configuration when available.
#' @param audit_strength Integer from 0 through 3. Defaults to
#'   `Audit.AuditStrength` from configuration, then 1 when unavailable.
#'
#' @return A list containing the updated Other row and audit rows written,
#'   invisibly.
#' @export
vpro_plot_other_update <- function(
  context,
  plot_number,
  id,
  changes,
  user = NULL,
  audit_strength = NULL
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  id <- vpro_plot_other_id(id)
  changes <- vpro_plot_changes(changes, "changes")
  if (length(changes) == 0L) {
    stop("At least one Other field update is required.", call. = FALSE)
  }
  if (any(c("PlotNumber", "ID") %in% names(changes))) {
    stop("Other record keys are immutable in `vpro_plot_other_update()`.", call. = FALSE)
  }
  user <- vpro_plot_user(context, user)
  audit_strength <- vpro_plot_audit_strength(context, audit_strength)
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  tables <- list(
    other = vpro_project_table(record$project, "Other"),
    audit = vpro_project_table(record$project, "Audit")
  )
  fields <- DBI::dbListFields(con, tables$other)
  unknown <- setdiff(names(changes), fields)
  if (length(unknown) > 0L) {
    stop("Unknown VPRO Other field(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  definitions <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, tables$other), ")")
  )
  for (field in names(changes)) {
    vpro_plot_validate_value(changes[[field]], field, definitions$type[match(field, definitions$name)])
  }

  result <- DBI::dbWithTransaction(con, {
    before_row <- vpro_plot_other_row(con, tables$other, plot_number, id)
    if (nrow(before_row) == 0L) {
      stop("VPRO Other record does not exist for plot ", plot_number, " and ID ", id, ".", call. = FALSE)
    }
    if (nrow(before_row) != 1L) {
      stop("VPRO Other record identity is not unique for plot ", plot_number, " and ID ", id, ".", call. = FALSE)
    }
    before <- unname(as.list(before_row[1, names(changes), drop = FALSE]))

    updated <- vpro_plot_other_apply_changes(con, tables$other, plot_number, id, changes)
    if (updated != 1L) {
      stop("VPRO Other update did not affect exactly one row.", call. = FALSE)
    }
    after_row <- vpro_plot_other_row(con, tables$other, plot_number, id)
    after <- unname(as.list(after_row[1, names(changes), drop = FALSE]))
    changed <- !vapply(seq_along(after), function(i) vpro_plot_equal(before[[i]], after[[i]]), logical(1))
    audited <- vapply(
      seq_along(after),
      function(i) vpro_plot_audited(before[[i]], after[[i]], audit_strength),
      logical(1)
    )

    audit_rows <- data.frame(
      Project = rep(record$project, sum(audited)),
      User = rep(user, sum(audited)),
      PlotNumber = rep(plot_number, sum(audited)),
      Table = rep("_Other", sum(audited)),
      EditField = names(changes)[audited],
      EditWhen = rep(format(Sys.time(), tz = "UTC", usetz = TRUE), sum(audited)),
      BeforeEdit = vapply(before[audited], vpro_plot_audit_text, character(1)),
      AfterEdit = vapply(after[audited], vpro_plot_audit_text, character(1)),
      ID = rep(id, sum(audited)),
      stringsAsFactors = FALSE
    )
    if (nrow(audit_rows) > 0L) {
      DBI::dbAppendTable(con, tables$audit, audit_rows)
    }
    attr(audit_rows, "changed_fields") <- names(changes)[changed]
    list(other = after_row, audit = audit_rows)
  })
  attr(result, "changed_fields") <- attr(result$audit, "changed_fields")
  invisible(result)
}
