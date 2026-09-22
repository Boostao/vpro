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

  list(
    path = path,
    su = su,
    table = table,
    version = vpro_su_metadata(con, table),
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
#'
#' @return SU attachment metadata, invisibly.
#' @export
vpro_su_attach <- function(context, path, su) {
  vpro_project_assert_context(context)
  inspection <- vpro_su_inspect(path, su)
  if (!isTRUE(inspection$compatible)) {
    stop(
      "VPRO SU table must contain text PlotNumber and SiteUnit fields: ",
      inspection$table,
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
#' transactionally. The copy is neither attached nor activated.
#'
#' @param context A VPRO project context.
#' @param su Attached source SU name.
#' @param path Target SQLite database path.
#' @param new_su Target SU name without the `_SU` suffix.
#'
#' @return The normalized target path, invisibly.
#' @export
vpro_su_save_as <- function(context, su, path, new_su) {
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

  path <- normalizePath(path, mustWork = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  source <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(if (DBI::dbIsValid(source)) DBI::dbDisconnect(source), add = TRUE)
  DBI::dbExecute(source, "ATTACH DATABASE ? AS target", params = list(path))
  source_table <- record$table
  target_table <- vpro_su_table(new_su)
  collision <- DBI::dbGetQuery(
    source,
    "SELECT name FROM target.sqlite_master WHERE name = ?",
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
      paste0('CREATE TABLE target."', target_table, '"'),
      schema
    )
    DBI::dbExecute(source, schema)
    DBI::dbExecute(
      source,
      paste(
        "INSERT INTO target.",
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
        paste0('CREATE \\1INDEX target."', target_index, '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }

    DBI::dbExecute(
      source,
      "CREATE TABLE IF NOT EXISTS target._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
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
          "INSERT INTO target._table_metadata VALUES (?, ?)",
          params = list(target_table, metadata$description[[1]])
        )
      }
    }
  })
  invisible(path)
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
