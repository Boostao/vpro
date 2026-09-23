# Site-unit contexts -------------------------------------------------------

vpro_su_name <- function(su) {
  vpro_project_name(su)
}

vpro_su_table <- function(su) {
  paste0(vpro_su_name(su), "_SU")
}

vpro_su_metadata <- function(con, table) {
  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    return("Unknown")
  }
  result <- DBI::dbGetQuery(
    con,
    "SELECT description FROM _table_metadata WHERE table_name = ?",
    params = list(table)
  )
  if (nrow(result) != 1L || is.na(result$description[[1]]) || !nzchar(result$description[[1]])) {
    return("Unknown")
  }
  result$description[[1]]
}

vpro_su_text_type <- function(type) {
  grepl("CHAR|CLOB|TEXT", toupper(type))
}

vpro_su_policy <- function(con, table) {
  default <- list(kind = "ordinary", source_path = NA_character_, source_table = NA_character_, created_at = NA_character_, created_by = NA_character_)
  if (!DBI::dbExistsTable(con, "_vpro_su_policy")) {
    return(default)
  }
  policy <- DBI::dbGetQuery(
    con,
    "SELECT kind, source_path, source_table, created_at, created_by FROM _vpro_su_policy WHERE table_name = ?",
    params = list(table)
  )
  if (nrow(policy) != 1L || !policy$kind[[1]] %in% c("ordinary", "master", "working")) {
    return(default)
  }
  as.list(policy[1, , drop = FALSE])
}

vpro_su_authorized <- function(authorize, permission, inspection) {
  is.function(authorize) && isTRUE(authorize(permission, inspection))
}

vpro_su_authorizer <- function(context, authorize = NULL) {
  if (is.function(authorize)) {
    return(authorize)
  }
  if (is.function(context$authorize)) {
    return(context$authorize)
  }
  NULL
}

#' Inspect a VPRO site-unit table
#'
#' An SU is an independent `<name>_SU` SQLite table with text `PlotNumber` and
#' `SiteUnit` fields. Blank and project-orphan rows are valid structural data and
#' are reported during activation rather than removed.
#'
#' @param path Path to a SQLite database containing the SU table.
#' @param su SU name without the `_SU` suffix.
#'
#' @return A list containing normalized path, SU name, table, translated version,
#'   structural compatibility, fields, and index information.
#' @export
vpro_su_inspect <- function(path, su) {
  su <- vpro_su_name(su)
  path <- normalizePath(path, mustWork = FALSE)
  if (!file.exists(path)) {
    stop("VPRO SU database does not exist: ", path, call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_su_table(su)
  if (!DBI::dbExistsTable(con, table)) {
    stop("VPRO SU table does not exist: ", table, call. = FALSE)
  }

  fields <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, table), ")")
  )
  indexes <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA index_list(", DBI::dbQuoteString(con, table), ")")
  )
  required <- c("PlotNumber", "SiteUnit")
  positions <- match(required, fields$name)
  compatible <- !anyNA(positions) && all(vpro_su_text_type(fields$type[positions]))
  unique_plot_index <- FALSE
  site_unit_index <- FALSE
  if (nrow(indexes) > 0L) {
    for (index in seq_len(nrow(indexes))) {
      columns <- DBI::dbGetQuery(
        con,
        paste0("PRAGMA index_info(", DBI::dbQuoteString(con, indexes$name[[index]]), ")")
      )$name
      unique_plot_index <- unique_plot_index ||
        (identical(columns, "PlotNumber") && indexes$unique[[index]] == 1L)
      site_unit_index <- site_unit_index || identical(columns, "SiteUnit")
    }
  }

  policy <- vpro_su_policy(con, table)
  list(
    path = path,
    su = su,
    table = table,
    version = vpro_su_metadata(con, table),
    kind = policy$kind,
    policy = policy,
    compatible = compatible,
    fields = fields,
    indexes = indexes,
    unique_plot_index = unique_plot_index,
    site_unit_index = site_unit_index
  )
}

vpro_su_alias <- function(su) {
  paste0("vpro_su_", tolower(vpro_su_name(su)))
}

#' Attach a VPRO site-unit table
#'
#' Attachment registers an exact `<name>_SU` table without activating it. When
#' the SQLite file is already used by a project or another SU, the existing
#' DuckDB attachment is reused.
#'
#' @param context A VPRO project context.
#' @param path Path to the SQLite database containing the SU.
#' @param su SU name without the `_SU` suffix.
#' @param authorize Optional function called as `authorize("attach_master_su",
#'   inspection)` for an SU explicitly marked as master. It must return `TRUE` to
#'   permit direct master attachment.
#'
#' @return SU attachment metadata, invisibly.
#' @export
vpro_su_attach <- function(context, path, su, authorize = NULL) {
  vpro_project_assert_context(context)
  inspection <- vpro_su_inspect(path, su)
  authorize <- vpro_su_authorizer(context, authorize)
  if (!isTRUE(inspection$compatible)) {
    stop(
      "VPRO SU table must contain text PlotNumber and SiteUnit fields: ",
      inspection$table,
      call. = FALSE
    )
  }
  if (identical(inspection$kind, "master") && !vpro_su_authorized(authorize, "attach_master_su", inspection)) {
    stop(
      "Direct attachment of a master VPRO SU requires `attach_master_su` authorization; create a working copy instead.",
      call. = FALSE
    )
  }
  if (inspection$su %in% names(context$sus)) {
    existing <- context$sus[[inspection$su]]
    if (identical(existing$path, inspection$path)) {
      return(invisible(existing))
    }
    stop("A different database is already attached for SU: ", inspection$su, call. = FALSE)
  }

  alias <- vpro_database_acquire(
    context,
    inspection$path,
    vpro_su_alias(inspection$su),
    paste0("su:", inspection$su)
  )
  record <- list(
    su = inspection$su,
    table = inspection$table,
    path = inspection$path,
    alias = alias,
    version = inspection$version,
    kind = inspection$kind,
    policy = inspection$policy,
    unique_plot_index = inspection$unique_plot_index,
    site_unit_index = inspection$site_unit_index
  )
  context$sus[[inspection$su]] <- record
  invisible(record)
}

vpro_su_relation <- function(context, record) {
  paste(
    DBI::dbQuoteIdentifier(context$con, record$alias),
    DBI::dbQuoteIdentifier(context$con, record$table),
    sep = "."
  )
}

vpro_su_diagnostics <- function(context, record) {
  su <- vpro_su_relation(context, record)
  env <- vpro_project_relation(context, context$active, "Env")
  admin <- vpro_project_relation(context, context$active, "Admin")
  summary <- DBI::dbGetQuery(
    context$con,
    paste(
      "SELECT COUNT(*) AS total_rows,",
      "COUNT(DISTINCT CASE WHEN PlotNumber IS NOT NULL AND TRIM(PlotNumber) <> '' THEN PlotNumber END) AS distinct_nonblank_plots,",
      "COALESCE(SUM(CASE WHEN PlotNumber IS NULL OR TRIM(PlotNumber) = '' THEN 1 ELSE 0 END), 0) AS blank_plot_rows",
      "FROM",
      su
    )
  )
  orphan_rows <- DBI::dbGetQuery(
    context$con,
    paste(
      "SELECT COUNT(*) AS n FROM",
      su,
      "AS su",
      "LEFT JOIN",
      env,
      'AS env ON su."PlotNumber" = env."PlotNumber"',
      'WHERE su."PlotNumber" IS NOT NULL AND TRIM(su."PlotNumber") <> \'\' AND env."PlotNumber" IS NULL'
    )
  )$n[[1]]
  selected <- DBI::dbGetQuery(
    context$con,
    paste(
      "SELECT COUNT(*) AS n FROM (SELECT DISTINCT env.* FROM",
      env,
      "AS env",
      "INNER JOIN",
      su,
      'AS su ON env."PlotNumber" = su."PlotNumber"',
      "INNER JOIN",
      admin,
      'AS admin ON env."PlotNumber" = admin."Plot")'
    )
  )$n[[1]]
  duplicate_rows <- DBI::dbGetQuery(
    context$con,
    paste(
      "SELECT COALESCE(SUM(n - 1), 0) AS n FROM (",
      'SELECT "PlotNumber", COUNT(*) AS n FROM',
      su,
      'WHERE "PlotNumber" IS NOT NULL AND TRIM("PlotNumber") <> \'\'',
      'GROUP BY "PlotNumber" HAVING COUNT(*) > 1)'
    )
  )$n[[1]]

  list(
    total_rows = as.integer(summary$total_rows[[1]]),
    distinct_nonblank_plots = as.integer(summary$distinct_nonblank_plots[[1]]),
    blank_plot_rows = as.integer(summary$blank_plot_rows[[1]]),
    orphan_plot_rows = as.integer(orphan_rows),
    active_project_plots = as.integer(selected),
    duplicate_plot_rows = as.integer(duplicate_rows)
  )
}

#' Activate an attached VPRO site-unit table
#'
#' Activation filters `USysEnv` to the active Env-SU-Admin intersection and
#' returns non-destructive diagnostics. Invalid rows are never deleted.
#'
#' @param context A VPRO project context with an active project.
#' @param su Attached SU name.
#'
#' @return A list containing attachment metadata and diagnostics, invisibly.
#' @export
vpro_su_activate <- function(context, su) {
  vpro_project_assert_context(context)
  su <- vpro_su_name(su)
  if (is.null(context$active)) {
    stop("A VPRO project must be active before an SU can be activated.", call. = FALSE)
  }
  record <- context$sus[[su]]
  if (is.null(record)) {
    stop("VPRO SU is not attached: ", su, call. = FALSE)
  }

  diagnostics <- vpro_su_diagnostics(context, record)
  vpro_project_activate(context, context$active$project)
  env <- vpro_project_relation(context, context$active, "Env")
  admin <- vpro_project_relation(context, context$active, "Admin")
  relation <- vpro_su_relation(context, record)
  filtered_sql <- paste(
    "SELECT DISTINCT env.*, admin.* FROM",
    env,
    "AS env",
    "INNER JOIN",
    relation,
    'AS su ON env."PlotNumber" = su."PlotNumber"',
    "INNER JOIN",
    admin,
    'AS admin ON env."PlotNumber" = admin."Plot"'
  )
  vpro_project_create_view(context, "Filtered_Env", filtered_sql)
  DBI::dbExecute(context$con, 'DROP VIEW IF EXISTS "USysEnv"')
  vpro_project_create_view(context, "USysEnv", "SELECT DISTINCT * FROM Filtered_Env")

  record$diagnostics <- diagnostics
  context$active_su <- record
  if (!is.null(context$config)) {
    context$config("Current", "CurrPlotlist", su)
    context$config("Current", "SUPath", record$path)
  }
  invisible(list(su = record, diagnostics = diagnostics))
}

#' Deactivate the current VPRO site-unit table
#'
#' @param context A VPRO project context with an active project.
#'
#' @return `TRUE`, invisibly. Attached SU tables remain attached.
#' @export
vpro_su_deactivate <- function(context) {
  vpro_project_assert_context(context)
  if (is.null(context$active)) {
    stop("A VPRO project must be active before an SU can be deactivated.", call. = FALSE)
  }
  vpro_project_activate(context, context$active$project)
  invisible(TRUE)
}

#' Detach a VPRO site-unit table
#'
#' Detachment removes the SU registration and releases its database only when no
#' project or other SU still uses that attachment. The SQLite file is unchanged.
#'
#' @param context A VPRO project context.
#' @param su Attached SU name.
#'
#' @return `TRUE`, invisibly, when detached; `FALSE` if not attached.
#' @export
vpro_su_detach <- function(context, su) {
  vpro_project_assert_context(context)
  su <- vpro_su_name(su)
  record <- context$sus[[su]]
  if (is.null(record)) {
    return(invisible(FALSE))
  }
  if (!is.null(context$active_su) && identical(context$active_su$su, su)) {
    stop("The active VPRO SU cannot be detached.", call. = FALSE)
  }

  vpro_database_release(context, record$path, paste0("su:", su))
  context$sus[[su]] <- NULL
  invisible(TRUE)
}

#' Save an attached VPRO site-unit table under a new name
#'
#' The SU table, rows, explicit indexes, and translated table metadata are copied
#' transactionally. The copy is neither attached nor activated. A master source
#' always produces a working copy with explicit provenance; creating another
#' master requires `create_master_su` authorization.
#'
#' @param context A VPRO project context.
#' @param su Attached source SU name.
#' @param path Target SQLite database path.
#' @param new_su Target SU name without the `_SU` suffix.
#' @param kind Target policy kind: `"auto"` creates a working copy from a master
#'   and otherwise an ordinary SU; `"ordinary"` and `"working"` may be selected
#'   explicitly; `"master"` requires authorization.
#' @param authorize Optional function called as `authorize("create_master_su",
#'   inspection)` when `kind = "master"`.
#' @param created_by Optional stable caller identity recorded as provenance.
#'
#' @return The normalized target path, invisibly.
#' @export
vpro_su_save_as <- function(
  context,
  su,
  path,
  new_su,
  kind = c("auto", "ordinary", "working", "master"),
  authorize = NULL,
  created_by = NULL
) {
  vpro_project_assert_context(context)
  su <- vpro_su_name(su)
  new_su <- vpro_su_name(new_su)
  if (identical(new_su, "Sample")) {
    stop("`Sample` is reserved and cannot be used as a save-as SU name.", call. = FALSE)
  }
  record <- context$sus[[su]]
  if (is.null(record)) {
    stop("VPRO SU is not attached: ", su, call. = FALSE)
  }
  kind <- match.arg(kind)
  authorize <- vpro_su_authorizer(context, authorize)
  target_kind <- if (identical(record$kind, "master") && !identical(kind, "master")) {
    "working"
  } else if (identical(kind, "auto")) {
    "ordinary"
  } else {
    kind
  }
  if (identical(target_kind, "master") && !vpro_su_authorized(authorize, "create_master_su", record)) {
    stop("Creating a master VPRO SU requires `create_master_su` authorization.", call. = FALSE)
  }
  if (!is.null(created_by) && (length(created_by) != 1L || is.na(created_by))) {
    stop("`created_by` must be NULL or one non-missing character value.", call. = FALSE)
  }

  path <- normalizePath(path, mustWork = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  source <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(if (DBI::dbIsValid(source)) DBI::dbDisconnect(source), add = TRUE)
  same_database <- identical(path, record$path)
  target_schema <- if (same_database) "main" else "target"
  if (!same_database) {
    DBI::dbExecute(source, "ATTACH DATABASE ? AS target", params = list(path))
  }
  source_table <- record$table
  target_table <- vpro_su_table(new_su)
  collision <- DBI::dbGetQuery(
    source,
    paste0("SELECT name FROM ", target_schema, ".sqlite_master WHERE name = ?"),
    params = list(target_table)
  )$name
  if (length(collision) > 0L) {
    stop("Target VPRO SU table already exists: ", target_table, call. = FALSE)
  }

  DBI::dbWithTransaction(source, {
    schema <- DBI::dbGetQuery(
      source,
      "SELECT sql FROM main.sqlite_master WHERE type = 'table' AND name = ?",
      params = list(source_table)
    )$sql[[1]]
    schema <- sub(
      paste0('^CREATE TABLE ["`]?', source_table, '["`]?'),
      paste0('CREATE TABLE ', target_schema, '."', target_table, '"'),
      schema
    )
    DBI::dbExecute(source, schema)
    DBI::dbExecute(
      source,
      paste(
        "INSERT INTO ", target_schema, ".",
        DBI::dbQuoteIdentifier(source, target_table),
        "SELECT * FROM main.",
        DBI::dbQuoteIdentifier(source, source_table)
      )
    )

    indexes <- DBI::dbGetQuery(
      source,
      "SELECT name, sql FROM main.sqlite_master WHERE type = 'index' AND sql IS NOT NULL AND tbl_name = ?",
      params = list(source_table)
    )
    for (index in seq_len(nrow(indexes))) {
      target_index <- sub(source_table, target_table, indexes$name[[index]], fixed = TRUE)
      sql <- gsub(source_table, target_table, indexes$sql[[index]], fixed = TRUE)
      sql <- sub(
        paste0('^CREATE (UNIQUE )?INDEX ["`]?', target_index, '["`]?'),
        paste0('CREATE \\1INDEX ', target_schema, '."', target_index, '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }

    DBI::dbExecute(
      source,
      paste0("CREATE TABLE IF NOT EXISTS ", target_schema, "._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)")
    )
    if (DBI::dbExistsTable(source, "_table_metadata")) {
      metadata <- DBI::dbGetQuery(
        source,
        "SELECT description FROM main._table_metadata WHERE table_name = ?",
        params = list(source_table)
      )
      if (nrow(metadata) == 1L) {
        DBI::dbExecute(
          source,
          paste0("INSERT INTO ", target_schema, "._table_metadata VALUES (?, ?)"),
          params = list(target_table, metadata$description[[1]])
        )
      }
    }

    DBI::dbExecute(
      source,
      paste(
        "CREATE TABLE IF NOT EXISTS ", target_schema, "._vpro_su_policy (",
        "table_name TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('ordinary', 'master', 'working')),",
        "source_path TEXT, source_table TEXT, created_at TEXT NOT NULL, created_by TEXT)"
      )
    )
    DBI::dbExecute(
      source,
      paste0("INSERT INTO ", target_schema, "._vpro_su_policy VALUES (?, ?, ?, ?, ?, ?)"),
      params = list(
        target_table,
        target_kind,
        if (identical(target_kind, "working")) record$path else NA_character_,
        if (identical(target_kind, "working")) record$table else NA_character_,
        format(Sys.time(), tz = "UTC", usetz = TRUE),
        if (is.null(created_by)) NA_character_ else as.character(created_by)
      )
    )
  })
  invisible(path)
}

#' Mark a VPRO site-unit table as a master
#'
#' Master status is explicit package metadata. This avoids Access's ambiguous
#' substring test and requires a caller-supplied authorization decision.
#'
#' @param path Path to the SQLite database containing the SU.
#' @param su SU name without the `_SU` suffix.
#' @param authorize Function called as `authorize("manage_master_su", inspection)`.
#' @param created_by Optional stable caller identity recorded in policy metadata.
#'
#' @return Updated SU inspection metadata, invisibly.
#' @export
vpro_su_mark_master <- function(path, su, authorize, created_by = NULL) {
  inspection <- vpro_su_inspect(path, su)
  if (!vpro_su_authorized(authorize, "manage_master_su", inspection)) {
    stop("Marking a master VPRO SU requires `manage_master_su` authorization.", call. = FALSE)
  }
  if (!is.null(created_by) && (length(created_by) != 1L || is.na(created_by))) {
    stop("`created_by` must be NULL or one non-missing character value.", call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), inspection$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(
      con,
      paste(
        "CREATE TABLE IF NOT EXISTS _vpro_su_policy (",
        "table_name TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('ordinary', 'master', 'working')),",
        "source_path TEXT, source_table TEXT, created_at TEXT NOT NULL, created_by TEXT)"
      )
    )
    DBI::dbExecute(
      con,
      paste(
        "INSERT INTO _vpro_su_policy VALUES (?, 'master', NULL, NULL, ?, ?)",
        "ON CONFLICT(table_name) DO UPDATE SET kind = 'master', source_path = NULL,",
        "source_table = NULL, created_at = excluded.created_at, created_by = excluded.created_by"
      ),
      params = list(
        inspection$table,
        format(Sys.time(), tz = "UTC", usetz = TRUE),
        if (is.null(created_by)) NA_character_ else as.character(created_by)
      )
    )
  })
  invisible(vpro_su_inspect(inspection$path, inspection$su))
}

#' Create an ordinary working copy of a master VPRO site-unit table
#'
#' This is the package-native translation of `V7mdlAttachSU.MakeMasterCopy`.
#' The master is read directly from SQLite and is never attached to the project
#' context, activated, or modified. The copy records explicit source provenance.
#'
#' @param context A VPRO project context.
#' @param path Path to the SQLite database containing the master SU.
#' @param su Master SU name without the `_SU` suffix.
#' @param target_path Target SQLite database path.
#' @param new_su Working-copy name without the `_SU` suffix.
#' @param created_by Optional stable caller identity recorded as provenance.
#'
#' @return The normalized target path, invisibly.
#' @export
vpro_su_create_working_copy <- function(context, path, su, target_path, new_su, created_by = NULL) {
  vpro_project_assert_context(context)
  inspection <- vpro_su_inspect(path, su)
  if (!identical(inspection$kind, "master")) {
    stop("A VPRO working copy can only be created from an SU explicitly marked as master.", call. = FALSE)
  }

  copy_context <- new.env(parent = emptyenv())
  copy_context$con <- context$con
  copy_context$sus <- stats::setNames(
    list(list(
      su = inspection$su,
      table = inspection$table,
      path = inspection$path,
      version = inspection$version,
      kind = inspection$kind,
      policy = inspection$policy
    )),
    inspection$su
  )
  class(copy_context) <- "vpro_project_context"
  vpro_su_save_as(
    copy_context,
    inspection$su,
    target_path,
    new_su,
    kind = "working",
    created_by = created_by
  )
}

#' Recover the configured VPRO site-unit table
#'
#' Recovery is attempted only when both an SU name and path are present. Failure
#' leaves the active project unfiltered and clears persisted SU state.
#'
#' @param context A VPRO project context with an active project and configuration.
#' @param su SU name. By default, reads `CurrPlotlist`.
#' @param path SU database path. By default, reads `SUPath`.
#'
#' @return Recovery status, diagnostics, and any error message, invisibly.
#' @export
vpro_su_recover <- function(context, su = NULL, path = NULL) {
  vpro_project_assert_context(context)
  if (is.null(context$config)) {
    stop("VPRO SU recovery requires a configuration accessor.", call. = FALSE)
  }
  if (is.null(su)) {
    su <- context$config("Current", "CurrPlotlist")
  }
  if (is.null(path)) {
    path <- context$config("Current", "SUPath")
  }
  if (is.null(su) || !nzchar(su) || identical(su, "None") || is.null(path) || !nzchar(path)) {
    vpro_su_deactivate(context)
    return(invisible(list(active = NULL, recovered = FALSE, error = NULL)))
  }

  result <- tryCatch(
    {
      vpro_su_attach(context, path, su)
      vpro_su_activate(context, su)
    },
    error = identity
  )
  if (!inherits(result, "error")) {
    return(invisible(list(active = result$su, recovered = TRUE, diagnostics = result$diagnostics, error = NULL)))
  }

  if (su %in% names(context$sus) && (is.null(context$active_su) || !identical(context$active_su$su, su))) {
    vpro_su_detach(context, su)
  }
  vpro_su_deactivate(context)
  invisible(list(active = NULL, recovered = FALSE, error = conditionMessage(result)))
}
