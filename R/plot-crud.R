# Plot CRUD ----------------------------------------------------------------

vpro_plot_active <- function(context) {
  vpro_project_assert_context(context)
  if (is.null(context$active)) {
    stop("A VPRO project must be active before plot data can be accessed.", call. = FALSE)
  }
  context$active
}

vpro_plot_number <- function(plot_number) {
  if (
    length(plot_number) != 1L ||
      is.na(plot_number) ||
      !is.character(plot_number) ||
      !nzchar(trimws(plot_number)) ||
      nchar(plot_number) > 7L
  ) {
    stop("`plot_number` must be one nonblank character value of at most 7 characters.", call. = FALSE)
  }
  plot_number
}

vpro_plot_changes <- function(changes, argument) {
  if (is.null(changes) || length(changes) == 0L) {
    return(list())
  }
  if (
    !is.list(changes) ||
      is.null(names(changes)) ||
      anyNA(names(changes)) ||
      any(!nzchar(names(changes))) ||
      anyDuplicated(names(changes))
  ) {
    stop("`", argument, "` must be a named list with unique, nonblank field names.", call. = FALSE)
  }
  invalid <- vapply(changes, function(value) length(value) != 1L, logical(1))
  if (any(invalid)) {
    stop("Every value in `", argument, "` must have length one; use a typed `NA` to clear a field.", call. = FALSE)
  }
  changes
}

vpro_plot_user <- function(context, user) {
  if (is.null(user) && is.function(context$config)) {
    user <- context$config("Current", "User")
  }
  if (length(user) != 1L || is.na(user) || !is.character(user) || !nzchar(trimws(user))) {
    stop("`user` must be one nonblank character value or be available as `Current.User` in configuration.", call. = FALSE)
  }
  user
}

vpro_plot_audit_strength <- function(context, audit_strength) {
  if (is.null(audit_strength) && is.function(context$config)) {
    audit_strength <- context$config("Audit", "AuditStrength")
  }
  if (is.null(audit_strength)) {
    audit_strength <- 1L
  }
  audit_strength <- suppressWarnings(as.integer(audit_strength))
  if (length(audit_strength) != 1L || is.na(audit_strength) || !audit_strength %in% 0:3) {
    stop("`audit_strength` must be one integer from 0 through 3.", call. = FALSE)
  }
  audit_strength
}

vpro_plot_table_row <- function(con, table, key, plot_number) {
  sql <- paste(
    "SELECT * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE",
    DBI::dbQuoteIdentifier(con, key),
    "= ?"
  )
  DBI::dbGetQuery(con, sql, params = list(plot_number))
}

vpro_plot_equal <- function(before, after) {
  if (is.na(before) && is.na(after)) {
    return(TRUE)
  }
  if (is.na(before) || is.na(after)) {
    return(FALSE)
  }
  isTRUE(all.equal(before, after, check.attributes = FALSE))
}

vpro_plot_audited <- function(before, after, strength) {
  if (vpro_plot_equal(before, after)) {
    return(FALSE)
  }
  if (is.na(before)) {
    return(!is.na(after) && strength >= 2L)
  }
  if (is.na(after)) {
    return(strength == 3L)
  }
  strength >= 1L
}

vpro_plot_audit_text <- function(value) {
  if (is.na(value)) NA_character_ else as.character(value)
}

vpro_plot_protected_admin_fields <- function() {
  c("BECSiteUnit", "HumusThickness", "StrataCoverTotal")
}

vpro_plot_validate_value <- function(value, field, declared_type) {
  if (is.na(value)) {
    return(invisible(TRUE))
  }
  type <- toupper(declared_type)
  valid <- if (grepl("INT", type)) {
    (is.numeric(value) || is.integer(value) || is.logical(value)) && isTRUE(value == as.integer(value))
  } else if (grepl("REAL|FLOA|DOUB|NUM", type)) {
    is.numeric(value) || is.integer(value)
  } else if (grepl("BOOL", type)) {
    is.logical(value) || (is.numeric(value) && value %in% c(0, 1))
  } else if (grepl("DATE|TIME", type)) {
    inherits(value, c("Date", "POSIXt")) || is.character(value)
  } else {
    is.character(value)
  }
  if (!isTRUE(valid)) {
    stop("Value for `", field, "` is incompatible with declared SQLite type ", declared_type, ".", call. = FALSE)
  }
  if (identical(field, "StartDate") && (value < 1900 || value > 2500)) {
    stop("`StartDate` must be between 1900 and 2500.", call. = FALSE)
  }
  invisible(TRUE)
}

vpro_plot_apply_changes <- function(con, table, key, plot_number, changes) {
  if (length(changes) == 0L) {
    return(invisible(0L))
  }
  assignments <- paste(DBI::dbQuoteIdentifier(con, names(changes)), "= ?", collapse = ", ")
  sql <- paste(
    "UPDATE",
    DBI::dbQuoteIdentifier(con, table),
    "SET",
    assignments,
    "WHERE",
    DBI::dbQuoteIdentifier(con, key),
    "= ?"
  )
  DBI::dbExecute(con, sql, params = c(unname(changes), list(plot_number)))
}

#' Read one plot from the active VPRO project
#'
#' Reads the canonical environmental and administrative base rows corresponding
#' to Access's joined `USysEnv` record source. It does not depend on Shiny or
#' mutate active project, SU, or hierarchy state.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#'
#' @return A list with one-row `env` and `admin` data frames.
#' @export
vpro_plot_get <- function(context, plot_number) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  env <- vpro_plot_table_row(con, vpro_project_table(record$project, "Env"), "PlotNumber", plot_number)
  admin <- vpro_plot_table_row(con, vpro_project_table(record$project, "Admin"), "Plot", plot_number)
  if (nrow(env) == 0L) {
    stop("VPRO plot does not exist in the active project: ", plot_number, call. = FALSE)
  }
  if (nrow(env) != 1L || nrow(admin) != 1L) {
    stop("VPRO plot must have exactly one Env row and one Admin row: ", plot_number, call. = FALSE)
  }
  list(env = env, admin = admin)
}

#' Update one plot in the active VPRO project
#'
#' Updates environmental and administrative fields in one SQLite transaction and
#' writes field-level audit rows in that same transaction. Audit strength follows
#' `V7mdlAudit.AuditTrail`: changed populated values are logged at strength 1 or
#' greater, newly populated values at strength 2 or greater, and cleared values
#' only at strength 3. Plot keys cannot be changed through this operation.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param env Named list of environmental field values to update.
#' @param admin Named list of administrative field values to update. Protected or
#'   derived Admin fields require `update_protected_plot_field` authorization from
#'   the project context.
#' @param user Stable user identity for audit rows. Defaults to `Current.User`
#'   from the context configuration when available.
#' @param audit_strength Integer from 0 through 3. Defaults to
#'   `Audit.AuditStrength` from configuration, then 1 when unavailable.
#'
#' @return A list containing the updated plot and audit rows written, invisibly.
#' @export
vpro_plot_update <- function(
  context,
  plot_number,
  env = list(),
  admin = list(),
  user = NULL,
  audit_strength = NULL
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  env <- vpro_plot_changes(env, "env")
  admin <- vpro_plot_changes(admin, "admin")
  if (length(env) == 0L && length(admin) == 0L) {
    stop("At least one Env or Admin field update is required.", call. = FALSE)
  }
  overlapping <- intersect(names(env), names(admin))
  if (length(overlapping) > 0L) {
    stop("Fields shared by Env and Admin must be updated in only one table: ", paste(overlapping, collapse = ", "), call. = FALSE)
  }
  if ("PlotNumber" %in% names(env) || "Plot" %in% names(admin)) {
    stop("Plot keys are immutable in `vpro_plot_update()`.", call. = FALSE)
  }
  user <- vpro_plot_user(context, user)
  audit_strength <- vpro_plot_audit_strength(context, audit_strength)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  tables <- list(
    env = vpro_project_table(record$project, "Env"),
    admin = vpro_project_table(record$project, "Admin"),
    audit = vpro_project_table(record$project, "Audit")
  )
  fields <- list(
    env = DBI::dbListFields(con, tables$env),
    admin = DBI::dbListFields(con, tables$admin)
  )
  unknown_env <- setdiff(names(env), fields$env)
  unknown_admin <- setdiff(names(admin), fields$admin)
  if (length(unknown_env) > 0L) {
    stop("Unknown VPRO Env field(s): ", paste(unknown_env, collapse = ", "), call. = FALSE)
  }
  if (length(unknown_admin) > 0L) {
    stop("Unknown VPRO Admin field(s): ", paste(unknown_admin, collapse = ", "), call. = FALSE)
  }
  protected <- intersect(names(admin), vpro_plot_protected_admin_fields())
  for (field in protected) {
    resource <- list(project = record$project, plot_number = plot_number, table = "Admin", field = field)
    if (!is.function(context$authorize) || !isTRUE(context$authorize("update_protected_plot_field", resource))) {
      stop("Updating protected VPRO Admin field requires `update_protected_plot_field` authorization: ", field, call. = FALSE)
    }
  }
  definitions <- list(
    env = DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteString(con, tables$env), ")")),
    admin = DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteString(con, tables$admin), ")"))
  )
  for (field in names(env)) {
    vpro_plot_validate_value(env[[field]], field, definitions$env$type[match(field, definitions$env$name)])
  }
  for (field in names(admin)) {
    vpro_plot_validate_value(admin[[field]], field, definitions$admin$type[match(field, definitions$admin$name)])
  }

  audit <- DBI::dbWithTransaction(con, {
    before_env <- vpro_plot_table_row(con, tables$env, "PlotNumber", plot_number)
    before_admin <- vpro_plot_table_row(con, tables$admin, "Plot", plot_number)
    if (nrow(before_env) == 0L) {
      stop("VPRO plot does not exist in the active project: ", plot_number, call. = FALSE)
    }
    if (nrow(before_env) != 1L || nrow(before_admin) != 1L) {
      stop("VPRO plot must have exactly one Env row and one Admin row: ", plot_number, call. = FALSE)
    }

    before <- c(
      unname(as.list(before_env[1, names(env), drop = FALSE])),
      unname(as.list(before_admin[1, names(admin), drop = FALSE]))
    )

    vpro_plot_apply_changes(con, tables$env, "PlotNumber", plot_number, env)
    vpro_plot_apply_changes(con, tables$admin, "Plot", plot_number, admin)
    after_env <- vpro_plot_table_row(con, tables$env, "PlotNumber", plot_number)
    after_admin <- vpro_plot_table_row(con, tables$admin, "Plot", plot_number)
    after <- c(
      unname(as.list(after_env[1, names(env), drop = FALSE])),
      unname(as.list(after_admin[1, names(admin), drop = FALSE]))
    )
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
      Table = rep("_Env", sum(audited)),
      EditField = c(names(env), names(admin))[audited],
      EditWhen = rep(format(Sys.time(), tz = "UTC", usetz = TRUE), sum(audited)),
      BeforeEdit = vapply(before[audited], vpro_plot_audit_text, character(1)),
      AfterEdit = vapply(after[audited], vpro_plot_audit_text, character(1)),
      stringsAsFactors = FALSE
    )
    if (nrow(audit_rows) > 0L) {
      DBI::dbAppendTable(con, tables$audit, audit_rows)
    }
    attr(audit_rows, "changed_fields") <- c(names(env), names(admin))[changed]
    audit_rows
  })

  result <- list(plot = vpro_plot_get(context, plot_number), audit = audit)
  attr(result, "changed_fields") <- attr(audit, "changed_fields")
  invisible(result)
}
