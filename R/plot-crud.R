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
    (is.numeric(value) || is.integer(value) || is.logical(value)) &&
      is.finite(value) &&
      abs(value) <= 2^53 - 1 &&
      isTRUE(value == floor(value))
  } else if (grepl("REAL|FLOA|DOUB|NUM", type)) {
    (is.numeric(value) || is.integer(value)) && is.finite(value)
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

vpro_plot_insert_row <- function(con, table, values) {
  sql <- paste(
    "INSERT INTO",
    DBI::dbQuoteIdentifier(con, table),
    paste0(
      "(",
      paste(DBI::dbQuoteIdentifier(con, names(values)), collapse = ", "),
      ") VALUES (",
      paste(rep("?", length(values)), collapse = ", "),
      ")"
    )
  )
  DBI::dbExecute(con, sql, params = unname(values))
}

vpro_plot_validate_fields <- function(con, table, values, kind) {
  fields <- DBI::dbListFields(con, table)
  unknown <- setdiff(names(values), fields)
  if (length(unknown) > 0L) {
    stop("Unknown VPRO ", kind, " field(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  definitions <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, table), ")")
  )
  for (field in names(values)) {
    vpro_plot_validate_value(
      values[[field]],
      field,
      definitions$type[match(field, definitions$name)]
    )
  }
  invisible(TRUE)
}

vpro_plot_authorize_admin <- function(context, record, plot_number, fields, action) {
  protected <- intersect(fields, vpro_plot_protected_admin_fields())
  for (field in protected) {
    resource <- list(project = record$project, plot_number = plot_number, table = "Admin", field = field)
    if (!is.function(context$authorize) || !isTRUE(context$authorize("update_protected_plot_field", resource))) {
      stop(action, " protected VPRO Admin field requires `update_protected_plot_field` authorization: ", field, call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' Create one plot in the active VPRO project
#'
#' Creates exactly one canonical Env row and one matching Admin row in a single
#' immediate SQLite transaction. The plot number is supplied explicitly; omitted
#' fields retain their SQLite defaults. Creation writes no audit or child rows and
#' does not change active SU or hierarchy state. Existing complete plots and
#' legacy incomplete Env/Admin pairs are rejected without repair or mutation.
#'
#' This intentionally corrects the Access `FS882-8x6XL` workflow, where a direct
#' Env-only save can leave an orphan Env row and normal focus-driven creation
#' emits meaningless checkbox audit rows.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number New plot identifier.
#' @param env Named list of initial environmental field values. `PlotNumber` is
#'   supplied separately.
#' @param admin Named list of initial administrative field values. `Plot` is
#'   supplied separately. Protected or derived fields require
#'   `update_protected_plot_field` authorization from the project context.
#'
#' @return A list with one-row `env` and `admin` data frames, invisibly.
#' @export
vpro_plot_create <- function(
  context,
  plot_number,
  env = list(),
  admin = list()
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  env <- vpro_plot_changes(env, "env")
  admin <- vpro_plot_changes(admin, "admin")
  if ("PlotNumber" %in% names(env) || "Plot" %in% names(admin)) {
    stop("Plot keys are managed by `vpro_plot_create()`.", call. = FALSE)
  }
  overlapping <- intersect(names(env), names(admin))
  if (length(overlapping) > 0L) {
    stop("Fields shared by Env and Admin must be supplied in only one table: ", paste(overlapping, collapse = ", "), call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  tables <- list(
    env = vpro_project_table(record$project, "Env"),
    admin = vpro_project_table(record$project, "Admin")
  )
  vpro_plot_validate_fields(con, tables$env, env, "Env")
  vpro_plot_validate_fields(con, tables$admin, admin, "Admin")
  vpro_plot_authorize_admin(context, record, plot_number, names(admin), "Creating")

  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con)) DBI::dbRollback(con), add = TRUE)
  existing_env <- vpro_plot_table_row(con, tables$env, "PlotNumber", plot_number)
  existing_admin <- vpro_plot_table_row(con, tables$admin, "Plot", plot_number)
  if (nrow(existing_env) > 0L && nrow(existing_admin) > 0L) {
    stop("VPRO plot already exists in the active project: ", plot_number, call. = FALSE)
  }
  if (nrow(existing_env) > 0L || nrow(existing_admin) > 0L) {
    stop("VPRO plot has an incomplete Env/Admin pair and cannot be created safely: ", plot_number, call. = FALSE)
  }

  inserted_env <- vpro_plot_insert_row(
    con,
    tables$env,
    c(list(PlotNumber = plot_number), env)
  )
  if (inserted_env != 1L) {
    stop("VPRO plot creation did not insert exactly one Env row.", call. = FALSE)
  }
  inserted_admin <- vpro_plot_insert_row(
    con,
    tables$admin,
    c(list(Plot = plot_number), admin)
  )
  if (inserted_admin != 1L) {
    stop("VPRO plot creation did not insert exactly one Admin row.", call. = FALSE)
  }

  created_env <- vpro_plot_table_row(con, tables$env, "PlotNumber", plot_number)
  created_admin <- vpro_plot_table_row(con, tables$admin, "Plot", plot_number)
  if (nrow(created_env) != 1L || nrow(created_admin) != 1L) {
    stop("VPRO plot creation must produce exactly one Env row and one Admin row.", call. = FALSE)
  }
  DBI::dbCommit(con)
  committed <- TRUE
  invisible(list(env = created_env, admin = created_admin))
}

vpro_plot_renumber_relation <- function(con, schema, table) {
  DBI::dbQuoteIdentifier(con, DBI::Id(schema = schema, table = table))
}

vpro_plot_renumber_count <- function(con, relation, key, plot_number) {
  DBI::dbGetQuery(
    con,
    paste(
      "SELECT COUNT(*) AS n FROM",
      relation,
      "WHERE",
      DBI::dbQuoteIdentifier(con, key),
      "= ?"
    ),
    params = list(plot_number)
  )$n[[1L]]
}

vpro_plot_transaction_sus <- function(context, con, project_path, alias_prefix) {
  if (length(context$sus) == 0L) {
    return(list())
  }
  paths <- unique(vapply(context$sus, `[[`, character(1), "path"))
  paths <- paths[paths != project_path]
  aliases <- stats::setNames(paste0(alias_prefix, seq_along(paths)), paths)
  for (path in paths) {
    DBI::dbExecute(
      con,
      paste(
        "ATTACH DATABASE ? AS",
        DBI::dbQuoteIdentifier(con, aliases[[path]])
      ),
      params = list(path)
    )
  }
  lapply(context$sus, function(record) {
    schema <- if (identical(record$path, project_path)) "main" else aliases[[record$path]]
    list(
      su = record$su,
      path = record$path,
      table = record$table,
      relation = vpro_plot_renumber_relation(con, schema, record$table)
    )
  })
}

#' Renumber one plot in the active VPRO project
#'
#' Changes the canonical Env plot key in one immediate SQLite transaction. The
#' project's enforced relationships cascade the new key to Admin, Audit,
#' vegetation, humus, mineral, and Other rows. Every SU currently attached to the
#' context is updated explicitly in the same transaction, including attached SUs
#' stored in other SQLite files. Unattached SU files cannot be discovered and are
#' not changed.
#'
#' This follows the observed Access cascade and no-audit behavior while correcting
#' the unreachable `FS882-8x6XL.PlotNumber_AfterUpdate` code that was intended to
#' update the current SU. Source inconsistencies, target collisions, and attached
#' SU collisions fail before mutation.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Existing plot identifier.
#' @param new_plot_number Unused replacement plot identifier.
#'
#' @return A list containing the old and new identifiers, affected project-row
#'   counts, attached-SU row counts, and the refreshed Env/Admin pair, invisibly.
#' @export
vpro_plot_renumber <- function(context, plot_number, new_plot_number) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  new_plot_number <- vpro_plot_number(new_plot_number)
  if (identical(plot_number, new_plot_number)) {
    stop("`new_plot_number` must differ from `plot_number`.", call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  tables <- stats::setNames(
    lapply(
      c("Env", "Admin", "Audit", "Veg", "Humus", "Mineral", "Other"),
      function(suffix) vpro_project_table(record$project, suffix)
    ),
    c("Env", "Admin", "Audit", "Veg", "Humus", "Mineral", "Other")
  )
  keys <- c(Env = "PlotNumber", Admin = "Plot", Audit = "PlotNumber", Veg = "PlotNumber", Humus = "PlotNumber", Mineral = "PlotNumber", Other = "PlotNumber")
  relations <- lapply(tables, function(table) vpro_plot_renumber_relation(con, "main", table))
  sus <- vpro_plot_transaction_sus(context, con, record$path, "vpro_renumber_su_")

  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con)) DBI::dbRollback(con), add = TRUE)

  source_counts <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], plot_number),
    integer(1)
  )
  if (source_counts[["Env"]] == 0L) {
    stop("VPRO plot does not exist in the active project: ", plot_number, call. = FALSE)
  }
  if (source_counts[["Env"]] != 1L || source_counts[["Admin"]] != 1L) {
    stop("VPRO plot must have exactly one Env row and one Admin row: ", plot_number, call. = FALSE)
  }

  target_counts <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], new_plot_number),
    integer(1)
  )
  if (target_counts[["Env"]] > 0L && target_counts[["Admin"]] > 0L) {
    stop("VPRO plot already exists in the active project: ", new_plot_number, call. = FALSE)
  }
  if (target_counts[["Env"]] > 0L || target_counts[["Admin"]] > 0L) {
    stop("VPRO target plot has an incomplete Env/Admin pair and cannot be used safely: ", new_plot_number, call. = FALSE)
  }
  dependent_collisions <- names(target_counts)[
    !names(target_counts) %in% c("Env", "Admin") & target_counts > 0L
  ]
  if (length(dependent_collisions) > 0L) {
    stop(
      "VPRO target plot has orphan dependent rows in: ",
      paste(dependent_collisions, collapse = ", "),
      call. = FALSE
    )
  }

  su_counts <- lapply(sus, function(su) {
    old <- vpro_plot_renumber_count(con, su$relation, "PlotNumber", plot_number)
    new <- vpro_plot_renumber_count(con, su$relation, "PlotNumber", new_plot_number)
    if (old > 0L && new > 0L) {
      stop(
        "Attached VPRO SU already contains both source and target plot numbers: ",
        su$su,
        call. = FALSE
      )
    }
    list(su = su$su, path = su$path, table = su$table, rows = old)
  })

  DBI::dbExecute(
    con,
    paste(
      "UPDATE",
      relations$Env,
      "SET",
      DBI::dbQuoteIdentifier(con, "PlotNumber"),
      "= ? WHERE",
      DBI::dbQuoteIdentifier(con, "PlotNumber"),
      "= ?"
    ),
    params = list(new_plot_number, plot_number)
  )

  for (index in seq_along(sus)) {
    if (su_counts[[index]]$rows == 0L) {
      next
    }
    changed <- DBI::dbExecute(
      con,
      paste(
        "UPDATE",
        sus[[index]]$relation,
        "SET",
        DBI::dbQuoteIdentifier(con, "PlotNumber"),
        "= ? WHERE",
        DBI::dbQuoteIdentifier(con, "PlotNumber"),
        "= ?"
      ),
      params = list(new_plot_number, plot_number)
    )
    if (changed != su_counts[[index]]$rows) {
      stop("VPRO plot renumbering did not update every matching row in attached SU: ", sus[[index]]$su, call. = FALSE)
    }
  }

  old_after <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], plot_number),
    integer(1)
  )
  new_after <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], new_plot_number),
    integer(1)
  )
  if (any(old_after != 0L) || !identical(new_after, source_counts)) {
    stop("VPRO plot renumbering did not preserve the complete project row family.", call. = FALSE)
  }
  for (index in seq_along(sus)) {
    if (
      vpro_plot_renumber_count(con, sus[[index]]$relation, "PlotNumber", plot_number) != 0L ||
        vpro_plot_renumber_count(con, sus[[index]]$relation, "PlotNumber", new_plot_number) != su_counts[[index]]$rows
    ) {
      stop("VPRO plot renumbering did not preserve attached SU membership: ", sus[[index]]$su, call. = FALSE)
    }
  }
  violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check")
  if (nrow(violations) > 0L) {
    stop("VPRO plot renumbering produced a foreign-key violation.", call. = FALSE)
  }

  renamed <- list(
    env = vpro_plot_table_row(con, tables$Env, "PlotNumber", new_plot_number),
    admin = vpro_plot_table_row(con, tables$Admin, "Plot", new_plot_number)
  )
  DBI::dbCommit(con)
  committed <- TRUE

  if (length(sus) > 0L) {
    for (su in sus) {
      refreshed <- vpro_su_diagnostics(context, context$sus[[su$su]])
      context$sus[[su$su]]$diagnostics <- refreshed
      if (!is.null(context$active_su) && identical(context$active_su$su, su$su)) {
        context$active_su <- context$sus[[su$su]]
      }
    }
  }

  invisible(list(
    plot_number = plot_number,
    new_plot_number = new_plot_number,
    project_rows = source_counts,
    su_rows = su_counts,
    env = renamed$env,
    admin = renamed$admin
  ))
}

#' Delete one plot from the active VPRO project
#'
#' Deletes the canonical Env row in one immediate SQLite transaction. Enforced
#' relationships cascade deletion to Admin, Audit, vegetation, humus, mineral,
#' and Other rows. Every SU currently attached to the context is cleaned in the
#' same transaction, including attached SUs stored in other SQLite files.
#' Unattached SU files cannot be discovered and are not changed.
#'
#' This follows the observed Access project-family cascade, including deletion
#' of the plot's audit history and creation of no replacement audit event. It
#' intentionally corrects Access's stale-SU behavior. Active project, SU,
#' hierarchy, and configuration selections remain unchanged.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Existing plot identifier.
#'
#' @return A list containing the deleted identifier, project-row counts, and
#'   attached-SU row counts, invisibly.
#' @export
vpro_plot_delete <- function(context, plot_number) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  tables <- stats::setNames(
    lapply(
      c("Env", "Admin", "Audit", "Veg", "Humus", "Mineral", "Other"),
      function(suffix) vpro_project_table(record$project, suffix)
    ),
    c("Env", "Admin", "Audit", "Veg", "Humus", "Mineral", "Other")
  )
  keys <- c(Env = "PlotNumber", Admin = "Plot", Audit = "PlotNumber", Veg = "PlotNumber", Humus = "PlotNumber", Mineral = "PlotNumber", Other = "PlotNumber")
  relations <- lapply(tables, function(table) vpro_plot_renumber_relation(con, "main", table))
  sus <- vpro_plot_transaction_sus(context, con, record$path, "vpro_delete_su_")

  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con)) DBI::dbRollback(con), add = TRUE)

  project_counts <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], plot_number),
    integer(1)
  )
  if (project_counts[["Env"]] == 0L && project_counts[["Admin"]] == 0L) {
    stop("VPRO plot does not exist in the active project: ", plot_number, call. = FALSE)
  }
  if (project_counts[["Env"]] != 1L || project_counts[["Admin"]] != 1L) {
    stop("VPRO plot must have exactly one Env row and one Admin row: ", plot_number, call. = FALSE)
  }
  su_counts <- lapply(sus, function(su) {
    list(
      su = su$su,
      path = su$path,
      table = su$table,
      rows = vpro_plot_renumber_count(con, su$relation, "PlotNumber", plot_number)
    )
  })

  DBI::dbExecute(
    con,
    paste(
      "DELETE FROM",
      relations$Env,
      "WHERE",
      DBI::dbQuoteIdentifier(con, "PlotNumber"),
      "= ?"
    ),
    params = list(plot_number)
  )

  for (index in seq_along(sus)) {
    if (su_counts[[index]]$rows == 0L) {
      next
    }
    changed <- DBI::dbExecute(
      con,
      paste(
        "DELETE FROM",
        sus[[index]]$relation,
        "WHERE",
        DBI::dbQuoteIdentifier(con, "PlotNumber"),
        "= ?"
      ),
      params = list(plot_number)
    )
    if (changed != su_counts[[index]]$rows) {
      stop("VPRO plot deletion did not remove every matching row from attached SU: ", sus[[index]]$su, call. = FALSE)
    }
  }

  project_after <- vapply(
    names(relations),
    function(kind) vpro_plot_renumber_count(con, relations[[kind]], keys[[kind]], plot_number),
    integer(1)
  )
  if (any(project_after != 0L)) {
    stop("VPRO plot deletion did not remove the complete project row family.", call. = FALSE)
  }
  for (index in seq_along(sus)) {
    if (vpro_plot_renumber_count(con, sus[[index]]$relation, "PlotNumber", plot_number) != 0L) {
      stop("VPRO plot deletion left matching rows in attached SU: ", sus[[index]]$su, call. = FALSE)
    }
  }
  violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check")
  if (nrow(violations) > 0L) {
    stop("VPRO plot deletion produced a foreign-key violation.", call. = FALSE)
  }

  DBI::dbCommit(con)
  committed <- TRUE

  if (length(sus) > 0L) {
    for (su in sus) {
      refreshed <- vpro_su_diagnostics(context, context$sus[[su$su]])
      context$sus[[su$su]]$diagnostics <- refreshed
      if (!is.null(context$active_su) && identical(context$active_su$su, su$su)) {
        context$active_su <- context$sus[[su$su]]
      }
    }
  }

  invisible(list(
    plot_number = plot_number,
    project_rows = project_counts,
    su_rows = su_counts
  ))
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

#' List audit history for one plot in the active VPRO project
#'
#' Reads the canonical audit rows corresponding to Access's `USysAuditTrail`
#' history view. Rows are restricted to the active project and requested plot and
#' ordered chronologically by `EditWhen`, with audit ID and SQLite row order used
#' to make timestamp ties deterministic. This operation does not modify audit
#' selection fields or other project state.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#'
#' @return A data frame containing the plot's audit rows in chronological order.
#' @export
vpro_plot_audit_list <- function(context, plot_number) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_project_table(record$project, "Audit")
  sql <- paste(
    "SELECT rowid AS audit_rowid, * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE",
    DBI::dbQuoteIdentifier(con, "Project"),
    "= ? AND",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ? ORDER BY",
    DBI::dbQuoteIdentifier(con, "EditWhen"),
    ", CASE WHEN",
    DBI::dbQuoteIdentifier(con, "ID"),
    "IS NULL THEN 1 ELSE 0 END,",
    DBI::dbQuoteIdentifier(con, "ID"),
    ", rowid"
  )
  DBI::dbGetQuery(con, sql, params = list(record$project, plot_number))
}

vpro_plot_audit_rowid <- function(audit_rowid) {
  if (
    length(audit_rowid) != 1L ||
      is.na(audit_rowid) ||
      !is.numeric(audit_rowid) ||
      !isTRUE(audit_rowid == floor(audit_rowid)) ||
      audit_rowid < 1
  ) {
    stop("`audit_rowid` must be one positive integer value.", call. = FALSE)
  }
  audit_rowid
}

vpro_plot_audit_event <- function(con, table, project, plot_number, audit_rowid) {
  sql <- paste(
    "SELECT rowid AS audit_rowid, * FROM",
    DBI::dbQuoteIdentifier(con, table),
    "WHERE rowid = ? AND",
    DBI::dbQuoteIdentifier(con, "Project"),
    "= ? AND",
    DBI::dbQuoteIdentifier(con, "PlotNumber"),
    "= ?"
  )
  DBI::dbGetQuery(con, sql, params = list(audit_rowid, project, plot_number))
}

vpro_plot_audit_selection <- function(audit) {
  if (!is.data.frame(audit) || nrow(audit) != 1L) {
    stop("`audit` must be one row returned by `vpro_plot_audit_list()`.", call. = FALSE)
  }
  required <- c(
    "audit_rowid",
    "Project",
    "User",
    "PlotNumber",
    "Table",
    "EditField",
    "EditWhen",
    "BeforeEdit",
    "AfterEdit",
    "Restore",
    "Flag",
    "ID"
  )
  if (!all(required %in% names(audit))) {
    stop("`audit` must contain the complete event returned by `vpro_plot_audit_list()`.", call. = FALSE)
  }
  vpro_plot_audit_rowid(audit$audit_rowid[[1L]])
  audit[, required, drop = FALSE]
}

vpro_plot_audit_same_event <- function(selected, current) {
  fields <- setdiff(names(selected), "audit_rowid")
  all(vapply(
    fields,
    function(field) {
      vpro_plot_equal(selected[[field]][[1L]], current[[field]][[1L]])
    },
    logical(1)
  ))
}

vpro_plot_audit_suffixes <- function() {
  c(`_Other` = "Other", `_Humus` = "Humus", `_Mineral` = "Mineral", `_Veg` = "Veg")
}

vpro_plot_audit_target <- function(con, project, event) {
  suffix <- event$Table[[1L]]
  field <- event$EditField[[1L]]
  if (is.na(suffix) || is.na(field) || !nzchar(field)) {
    stop("The audit event must identify a table suffix and nonblank field.", call. = FALSE)
  }

  if (identical(suffix, "_Env")) {
    if (field %in% c("PlotNumber", "Plot")) {
      stop("Plot keys cannot be restored from an audit event.", call. = FALSE)
    }
    candidates <- list(
      list(kind = "Env", table = vpro_project_table(project, "Env"), key = "PlotNumber"),
      list(kind = "Admin", table = vpro_project_table(project, "Admin"), key = "Plot")
    )
    matches <- vapply(candidates, function(x) field %in% DBI::dbListFields(con, x$table), logical(1))
    if (sum(matches) == 0L) {
      stop("Audit field is not present in the active project's Env or Admin table: ", field, call. = FALSE)
    }
    if (sum(matches) != 1L) {
      stop("Audit field is ambiguous across the active project's Env and Admin tables: ", field, call. = FALSE)
    }
    return(candidates[[which(matches)]])
  }

  suffixes <- vpro_plot_audit_suffixes()
  if (!suffix %in% names(suffixes)) {
    stop("Unsupported VPRO audit table suffix: ", suffix, call. = FALSE)
  }
  if (is.na(event$ID[[1L]])) {
    stop("Child audit restoration requires a nonmissing child ID.", call. = FALSE)
  }
  if (field %in% c("PlotNumber", "ID")) {
    stop("Child record keys cannot be restored from an audit event.", call. = FALSE)
  }
  target <- list(
    kind = unname(suffixes[[suffix]]),
    table = vpro_project_table(project, unname(suffixes[[suffix]])),
    key = "PlotNumber",
    id = vpro_plot_child_id(event$ID[[1L]])
  )
  if (!field %in% DBI::dbListFields(con, target$table)) {
    stop("Audit field is not present in the target child table: ", field, call. = FALSE)
  }
  target
}

vpro_plot_audit_restore_value <- function(value, declared_type) {
  if (is.na(value)) {
    return(NA)
  }
  type <- toupper(declared_type)
  converted <- if (grepl("INT", type)) {
    if (!grepl("^[+-]?[0-9]+$", value)) {
      NA_real_
    } else {
      suppressWarnings(as.numeric(value))
    }
  } else if (grepl("REAL|FLOA|DOUB|NUM", type)) {
    suppressWarnings(as.numeric(value))
  } else if (grepl("BOOL", type)) {
    normalized <- tolower(trimws(value))
    if (normalized %in% c("true", "1", "-1")) {
      TRUE
    } else if (normalized %in% c("false", "0")) {
      FALSE
    } else {
      NA
    }
  } else {
    as.character(value)
  }
  if (length(converted) != 1L || is.na(converted) || (is.numeric(converted) && !is.finite(converted))) {
    stop("Recorded audit value is incompatible with declared SQLite type ", declared_type, ".", call. = FALSE)
  }
  converted
}

vpro_plot_audit_current_matches <- function(current, recorded) {
  if (is.na(recorded)) {
    return(is.na(current))
  }
  identical(vpro_plot_audit_text(current), as.character(recorded))
}

#' Restore one audited plot field
#'
#' Restores the `BeforeEdit` value recorded by one canonical audit event. The
#' complete one-row event returned by [vpro_plot_audit_list()] is required so its
#' contents can be reverified before mutation; SQLite row IDs alone are not
#' durable event identities. `_Env` fields are resolved against both physical
#' Env and Admin schemas, while child fields require exactly one
#' `(PlotNumber, ID)` row. The current stored value must still equal the event's
#' `AfterEdit` value, preventing an older event from silently overwriting later
#' work.
#'
#' Restoration changes exactly one existing field in one SQLite transaction. It
#' does not create missing child rows, delete empty vegetation rows, or append a
#' second audit event. The restored audit row is preserved unless
#' `delete_audit = TRUE` is explicitly requested.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_number Plot identifier.
#' @param audit Complete one-row event selected from [vpro_plot_audit_list()].
#' @param delete_audit Whether to delete the successfully restored audit event in
#'   the same transaction. Defaults to `FALSE`.
#'
#' @return A list containing the restored target row and audit event, invisibly.
#' @export
vpro_plot_audit_restore <- function(
  context,
  plot_number,
  audit,
  delete_audit = FALSE
) {
  record <- vpro_plot_active(context)
  plot_number <- vpro_plot_number(plot_number)
  audit <- vpro_plot_audit_selection(audit)
  audit_rowid <- audit$audit_rowid[[1L]]
  if (length(delete_audit) != 1L || is.na(delete_audit) || !is.logical(delete_audit)) {
    stop("`delete_audit` must be `TRUE` or `FALSE`.", call. = FALSE)
  }
  vpro_plot_get(context, plot_number)

  con <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  audit_table <- vpro_project_table(record$project, "Audit")

  result <- DBI::dbWithTransaction(con, {
    event <- vpro_plot_audit_event(
      con,
      audit_table,
      record$project,
      plot_number,
      audit_rowid
    )
    if (nrow(event) != 1L) {
      stop("VPRO audit event does not exist for the active project and plot: ", audit_rowid, call. = FALSE)
    }
    if (!vpro_plot_audit_same_event(audit, event)) {
      stop("The selected audit event no longer matches the active database.", call. = FALSE)
    }
    target <- vpro_plot_audit_target(con, record$project, event)
    field <- event$EditField[[1L]]
    definitions <- vpro_plot_child_definitions(con, target$table)
    declared_type <- definitions$type[match(field, definitions$name)]
    before <- vpro_plot_audit_restore_value(event$BeforeEdit[[1L]], declared_type)
    vpro_plot_validate_value(before, field, declared_type)

    row <- if (!is.null(target$id)) {
      child <- vpro_plot_child_row(con, target$table, plot_number, target$id)
      vpro_plot_child_assert_row(child, tolower(target$kind), plot_number, target$id)
      child
    } else {
      base <- vpro_plot_table_row(con, target$table, target$key, plot_number)
      if (nrow(base) != 1L) {
        stop("VPRO plot must have exactly one ", target$kind, " row: ", plot_number, call. = FALSE)
      }
      base
    }
    current <- row[[field]][[1L]]
    if (!vpro_plot_audit_current_matches(current, event$AfterEdit[[1L]])) {
      stop("The target field no longer matches the audit event's `AfterEdit` value; restoration was not applied.", call. = FALSE)
    }
    if (identical(target$kind, "Admin") && field %in% vpro_plot_protected_admin_fields()) {
      resource <- list(project = record$project, plot_number = plot_number, table = "Admin", field = field)
      if (!is.function(context$authorize) || !isTRUE(context$authorize("update_protected_plot_field", resource))) {
        stop("Restoring protected VPRO Admin field requires `update_protected_plot_field` authorization: ", field, call. = FALSE)
      }
    }

    where <- if (is.null(target$id)) {
      list(sql = paste(DBI::dbQuoteIdentifier(con, target$key), "= ?"), params = list(plot_number))
    } else {
      list(
        sql = paste(
          DBI::dbQuoteIdentifier(con, "PlotNumber"),
          "= ? AND",
          DBI::dbQuoteIdentifier(con, "ID"),
          "= ?"
        ),
        params = list(plot_number, target$id)
      )
    }
    updated <- DBI::dbExecute(
      con,
      paste(
        "UPDATE",
        DBI::dbQuoteIdentifier(con, target$table),
        "SET",
        DBI::dbQuoteIdentifier(con, field),
        "= ? WHERE",
        where$sql
      ),
      params = c(list(before), where$params)
    )
    if (updated != 1L) {
      stop("VPRO audit restoration did not affect exactly one target row.", call. = FALSE)
    }
    restored <- if (!is.null(target$id)) {
      vpro_plot_child_row(con, target$table, plot_number, target$id)
    } else {
      vpro_plot_table_row(con, target$table, target$key, plot_number)
    }
    if (isTRUE(delete_audit)) {
      deleted <- DBI::dbExecute(
        con,
        paste(
          "DELETE FROM",
          DBI::dbQuoteIdentifier(con, audit_table),
          "WHERE rowid = ? AND",
          DBI::dbQuoteIdentifier(con, "Project"),
          "= ? AND",
          DBI::dbQuoteIdentifier(con, "PlotNumber"),
          "= ?"
        ),
        params = list(audit_rowid, record$project, plot_number)
      )
      if (deleted != 1L) {
        stop("VPRO audit restoration did not delete exactly one audit event.", call. = FALSE)
      }
    }
    list(target = restored, audit = event, audit_deleted = isTRUE(delete_audit))
  })
  invisible(result)
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
