# Plot soil records ---------------------------------------------------------

vpro_plot_soil_id <- vpro_plot_child_id

vpro_plot_soil_spec <- function(kind) {
  switch(
    kind,
    Humus = list(order = c("UpperDepth DESC", "Horizon DESC", "ID"), suffix = "_Humus"),
    Mineral = list(order = c("UpperDepth", "Horizon", "ID"), suffix = "_Mineral"),
    stop("Unknown VPRO soil record kind: ", kind, call. = FALSE)
  )
}

vpro_plot_soil_row <- vpro_plot_child_row

vpro_plot_soil_assert_row <- vpro_plot_child_assert_row

vpro_plot_soil_list <- function(context, plot_number, kind) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  vpro_plot_get(context, plot_number)
  spec <- vpro_plot_soil_spec(kind)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_project_table(record$project, kind)
  order <- vapply(
    strsplit(spec$order, " ", fixed = TRUE),
    function(part) {
      paste(DBI::dbQuoteIdentifier(con, part[[1L]]), paste(part[-1L], collapse = " "))
    },
    character(1)
  )
  sql <- paste(
    "SELECT * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ? ORDER BY",
    paste(order, collapse = ", ")
  )
  DBI::dbGetQuery(con, sql, params = list(plot_number))
}

vpro_plot_soil_get <- function(context, plot_number, id, kind) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  id <- vpro_plot_soil_id(id)
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- vpro_plot_soil_row(
    con,
    vpro_project_table(record$project, kind),
    plot_number,
    id
  )
  vpro_plot_soil_assert_row(row, kind, plot_number, id)
  row
}

vpro_plot_soil_apply_changes <- function(con, table, plot_number, id, changes) {
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

vpro_plot_soil_update <- function(
  context,
  plot_number,
  id,
  changes,
  user,
  audit_strength,
  kind
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  id <- vpro_plot_soil_id(id)
  changes <- vpro_plot_changes(changes, "changes")
  if (length(changes) == 0L) {
    stop("At least one ", kind, " field update is required.", call. = FALSE)
  }
  if (any(c("PlotNumber", "ID") %in% names(changes))) {
    stop(kind, " record keys are immutable in soil update operations.", call. = FALSE)
  }
  user <- vpro_plot_user(context, user)
  audit_strength <- vpro_plot_audit_strength(context, audit_strength)
  vpro_plot_get(context, plot_number)
  spec <- vpro_plot_soil_spec(kind)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  tables <- list(
    soil = vpro_project_table(record$project, kind),
    audit = vpro_project_table(record$project, "Audit")
  )
  fields <- DBI::dbListFields(con, tables$soil)
  unknown <- setdiff(names(changes), fields)
  if (length(unknown) > 0L) {
    stop(
      "Unknown VPRO ",
      kind,
      " field(s): ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  definitions <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, tables$soil), ")")
  )
  for (field in names(changes)) {
    vpro_plot_validate_value(
      changes[[field]],
      field,
      definitions$type[match(field, definitions$name)]
    )
  }

  result <- DBI::dbWithTransaction(con, {
    before_row <- vpro_plot_soil_row(con, tables$soil, plot_number, id)
    vpro_plot_soil_assert_row(before_row, kind, plot_number, id)
    before <- unname(as.list(before_row[1, names(changes), drop = FALSE]))

    updated <- vpro_plot_soil_apply_changes(
      con,
      tables$soil,
      plot_number,
      id,
      changes
    )
    if (updated != 1L) {
      stop("VPRO ", kind, " update did not affect exactly one row.", call. = FALSE)
    }
    after_row <- vpro_plot_soil_row(con, tables$soil, plot_number, id)
    after <- unname(as.list(after_row[1, names(changes), drop = FALSE]))
    changed <- !vapply(
      seq_along(after),
      function(i) vpro_plot_equal(before[[i]], after[[i]]),
      logical(1)
    )
    audited <- vapply(
      seq_along(after),
      function(i) vpro_plot_audited(before[[i]], after[[i]], audit_strength),
      logical(1)
    )

    audit_rows <- data.frame(
      Project = rep(record$project, sum(audited)),
      User = rep(user, sum(audited)),
      PlotNumber = rep(plot_number, sum(audited)),
      Table = rep(spec$suffix, sum(audited)),
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
    list(soil = after_row, audit = audit_rows)
  })
  names(result)[[1L]] <- tolower(kind)
  attr(result, "changed_fields") <- attr(result$audit, "changed_fields")
  invisible(result)
}

#' Read Humus records for one plot in the active VPRO project
#'
#' `vpro_plot_humus_list()` reads all canonical `_Humus` child rows for an
#' existing plot. It preserves the Access soil form's descending upper-depth
#' and horizon order, with `ID` as a deterministic tie-breaker.
#' `vpro_plot_humus_get()` reads one existing row by plot and signed 32-bit ID.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param id Existing `_Humus` child-row ID.
#'
#' @return `vpro_plot_humus_list()` returns a data frame of Humus rows.
#'   `vpro_plot_humus_get()` returns one Humus row.
#' @export
vpro_plot_humus_list <- function(context, plot_number) {
  vpro_plot_soil_list(context, plot_number, "Humus")
}

#' @rdname vpro_plot_humus_list
#' @export
vpro_plot_humus_get <- function(context, plot_number, id) {
  vpro_plot_soil_get(context, plot_number, id, "Humus")
}

#' Create or delete one Humus record
#'
#' `vpro_plot_humus_create()` creates a canonical `_Humus` child row with a
#' collision-checked signed 32-bit ID and audits populated fields at strength 2
#' or 3. `vpro_plot_humus_delete()` deletes exactly one existing row without
#' adding audit rows, matching the observed Access bound-form behavior.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param values Named list of field values for the new row.
#' @param user Stable user identity for audit rows. Defaults to `Current.User`
#'   from the context configuration when available.
#' @param audit_strength Integer from 0 through 3. Defaults to
#'   `Audit.AuditStrength` from configuration, then 1 when unavailable.
#' @param id Existing `_Humus` child-row ID.
#'
#' @return Creation returns the created row and audit rows; deletion returns the
#'   deleted row. Both are returned invisibly.
#' @export
vpro_plot_humus_create <- function(
  context,
  plot_number,
  values = list(),
  user = NULL,
  audit_strength = NULL
) {
  vpro_plot_child_create(
    context,
    plot_number,
    values,
    "Humus",
    "_Humus",
    "vpro_plot_humus_create",
    user,
    audit_strength
  )
}

#' @rdname vpro_plot_humus_create
#' @export
vpro_plot_humus_delete <- function(context, plot_number, id) {
  vpro_plot_child_delete(context, plot_number, id, "Humus")
}

#' Update one Humus record in the active VPRO project
#'
#' Updates an existing `_Humus` child row identified by plot and ID and writes
#' qualifying field-level audit rows carrying the child ID in the same SQLite
#' transaction. Creation, deletion, and audit restoration are separate
#' operations.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param id Existing `_Humus` child-row ID.
#' @param changes Named list of field values to update.
#' @param user Stable user identity for audit rows. Defaults to `Current.User`
#'   from the context configuration when available.
#' @param audit_strength Integer from 0 through 3. Defaults to
#'   `Audit.AuditStrength` from configuration, then 1 when unavailable.
#'
#' @return A list containing the updated Humus row and audit rows written,
#'   invisibly.
#' @export
vpro_plot_humus_update <- function(
  context,
  plot_number,
  id,
  changes,
  user = NULL,
  audit_strength = NULL
) {
  vpro_plot_soil_update(
    context,
    plot_number,
    id,
    changes,
    user,
    audit_strength,
    "Humus"
  )
}

#' Read Mineral records for one plot in the active VPRO project
#'
#' `vpro_plot_mineral_list()` reads all canonical `_Mineral` child rows for an
#' existing plot. It preserves the Access soil form's ascending upper-depth and
#' horizon order, with `ID` as a deterministic tie-breaker.
#' `vpro_plot_mineral_get()` reads one existing row by plot and signed 32-bit ID.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param id Existing `_Mineral` child-row ID.
#'
#' @return `vpro_plot_mineral_list()` returns a data frame of Mineral rows.
#'   `vpro_plot_mineral_get()` returns one Mineral row.
#' @export
vpro_plot_mineral_list <- function(context, plot_number) {
  vpro_plot_soil_list(context, plot_number, "Mineral")
}

#' @rdname vpro_plot_mineral_list
#' @export
vpro_plot_mineral_get <- function(context, plot_number, id) {
  vpro_plot_soil_get(context, plot_number, id, "Mineral")
}

#' Create or delete one Mineral record
#'
#' `vpro_plot_mineral_create()` creates a canonical `_Mineral` child row with a
#' collision-checked signed 32-bit ID and audits populated fields at strength 2
#' or 3. `vpro_plot_mineral_delete()` deletes exactly one existing row without
#' adding audit rows, matching the observed Access bound-form behavior.
#'
#' @inheritParams vpro_plot_humus_create
#' @param id Existing `_Mineral` child-row ID.
#'
#' @return Creation returns the created row and audit rows; deletion returns the
#'   deleted row. Both are returned invisibly.
#' @export
vpro_plot_mineral_create <- function(
  context,
  plot_number,
  values = list(),
  user = NULL,
  audit_strength = NULL
) {
  vpro_plot_child_create(
    context,
    plot_number,
    values,
    "Mineral",
    "_Mineral",
    "vpro_plot_mineral_create",
    user,
    audit_strength
  )
}

#' @rdname vpro_plot_mineral_create
#' @export
vpro_plot_mineral_delete <- function(context, plot_number, id) {
  vpro_plot_child_delete(context, plot_number, id, "Mineral")
}

#' Update one Mineral record in the active VPRO project
#'
#' Updates an existing `_Mineral` child row identified by plot and ID and writes
#' qualifying field-level audit rows carrying the child ID in the same SQLite
#' transaction. Creation, deletion, and audit restoration are separate
#' operations.
#'
#' @inheritParams vpro_plot_humus_update
#' @param id Existing `_Mineral` child-row ID.
#'
#' @return A list containing the updated Mineral row and audit rows written,
#'   invisibly.
#' @export
vpro_plot_mineral_update <- function(
  context,
  plot_number,
  id,
  changes,
  user = NULL,
  audit_strength = NULL
) {
  vpro_plot_soil_update(
    context,
    plot_number,
    id,
    changes,
    user,
    audit_strength,
    "Mineral"
  )
}
