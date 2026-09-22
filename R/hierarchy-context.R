# Hierarchy contexts --------------------------------------------------------

vpro_hierarchy_name <- function(hierarchy) {
  vpro_project_name(hierarchy)
}

vpro_hierarchy_table <- function(hierarchy) {
  paste0(vpro_hierarchy_name(hierarchy), "_Hierarchy")
}

vpro_hierarchy_integer_type <- function(type) {
  grepl("INT", toupper(type))
}

vpro_hierarchy_text_type <- function(type) {
  grepl("CHAR|CLOB|TEXT", toupper(type))
}

vpro_hierarchy_metadata <- function(con, table) {
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

vpro_hierarchy_cycle_rows <- function(nodes) {
  if (nrow(nodes) == 0L) {
    return(0L)
  }
  parent <- stats::setNames(nodes$Parent, as.character(nodes$ID))
  cyclic <- character()
  for (id in names(parent)) {
    current <- id
    visited <- character()
    while (!is.na(current) && nzchar(current) && current %in% names(parent)) {
      repeated <- match(current, visited)
      if (!is.na(repeated)) {
        cyclic <- union(cyclic, visited[repeated:length(visited)])
        break
      }
      visited <- c(visited, current)
      current <- as.character(parent[[current]])
    }
  }
  length(cyclic)
}

#' Inspect a VPRO hierarchy table
#'
#' A hierarchy is an independent `<name>_Hierarchy` SQLite table. Inspection
#' validates the fields used by the Access hierarchy tools and reports
#' non-destructive tree diagnostics.
#'
#' @param path Path to a SQLite database containing the hierarchy table.
#' @param hierarchy Hierarchy name without the `_Hierarchy` suffix.
#'
#' @return A list containing normalized path, hierarchy name, table, translated
#'   version, structural compatibility, fields, indexes, and tree diagnostics.
#' @export
vpro_hierarchy_inspect <- function(path, hierarchy) {
  hierarchy <- vpro_hierarchy_name(hierarchy)
  path <- normalizePath(path, mustWork = FALSE)
  if (!file.exists(path)) {
    stop("VPRO hierarchy database does not exist: ", path, call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_hierarchy_table(hierarchy)
  if (!DBI::dbExistsTable(con, table)) {
    stop("VPRO hierarchy table does not exist: ", table, call. = FALSE)
  }

  fields <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, table), ")")
  )
  indexes <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA index_list(", DBI::dbQuoteString(con, table), ")")
  )
  required <- c("ID", "Name", "Parent", "Level")
  positions <- match(required, fields$name)
  compatible <- !anyNA(positions) &&
    all(vpro_hierarchy_integer_type(fields$type[positions[c(1L, 3L, 4L)]]) &
      vpro_hierarchy_text_type(fields$type[positions[[2L]]]))

  name_index <- FALSE
  parent_index <- FALSE
  if (nrow(indexes) > 0L) {
    for (index in seq_len(nrow(indexes))) {
      columns <- DBI::dbGetQuery(
        con,
        paste0("PRAGMA index_info(", DBI::dbQuoteString(con, indexes$name[[index]]), ")")
      )$name
      name_index <- name_index || (identical(columns, "Name") && indexes$unique[[index]] == 1L)
      parent_index <- parent_index || identical(columns, "Parent")
    }
  }

  diagnostics <- list(
    total_rows = NA_integer_,
    root_rows = NA_integer_,
    blank_name_rows = NA_integer_,
    orphan_parent_rows = NA_integer_,
    cycle_rows = NA_integer_
  )
  if (compatible) {
    nodes <- DBI::dbGetQuery(
      con,
      paste("SELECT ID, Name, Parent, Level FROM", DBI::dbQuoteIdentifier(con, table))
    )
    diagnostics <- list(
      total_rows = nrow(nodes),
      root_rows = sum(is.na(nodes$Parent)),
      blank_name_rows = sum(is.na(nodes$Name) | !nzchar(trimws(nodes$Name))),
      orphan_parent_rows = sum(!is.na(nodes$Parent) & !nodes$Parent %in% nodes$ID),
      cycle_rows = vpro_hierarchy_cycle_rows(nodes)
    )
  }

  list(
    path = path,
    hierarchy = hierarchy,
    table = table,
    version = vpro_hierarchy_metadata(con, table),
    compatible = compatible,
    fields = fields,
    indexes = indexes,
    unique_name_index = name_index,
    parent_index = parent_index,
    diagnostics = diagnostics
  )
}

vpro_hierarchy_alias <- function(hierarchy) {
  paste0("vpro_hierarchy_", tolower(vpro_hierarchy_name(hierarchy)))
}

#' Attach a VPRO hierarchy table
#'
#' Attachment registers an exact `<name>_Hierarchy` table without selecting it.
#' Existing SQLite attachments are reused by normalized path.
#'
#' @param context A VPRO project context.
#' @param path Path to the SQLite database containing the hierarchy.
#' @param hierarchy Hierarchy name without the `_Hierarchy` suffix.
#'
#' @return Hierarchy attachment metadata, invisibly.
#' @export
vpro_hierarchy_attach <- function(context, path, hierarchy) {
  vpro_project_assert_context(context)
  inspection <- vpro_hierarchy_inspect(path, hierarchy)
  if (!isTRUE(inspection$compatible)) {
    stop(
      "VPRO hierarchy table must contain integer ID, Parent, and Level fields and a text Name field: ",
      inspection$table,
      call. = FALSE
    )
  }
  if (inspection$hierarchy %in% names(context$hierarchies)) {
    existing <- context$hierarchies[[inspection$hierarchy]]
    if (identical(existing$path, inspection$path)) {
      return(invisible(existing))
    }
    stop("A different database is already attached for hierarchy: ", inspection$hierarchy, call. = FALSE)
  }

  alias <- vpro_database_acquire(
    context,
    inspection$path,
    vpro_hierarchy_alias(inspection$hierarchy),
    paste0("hierarchy:", inspection$hierarchy)
  )
  record <- list(
    hierarchy = inspection$hierarchy,
    table = inspection$table,
    path = inspection$path,
    alias = alias,
    version = inspection$version,
    unique_name_index = inspection$unique_name_index,
    parent_index = inspection$parent_index,
    diagnostics = inspection$diagnostics
  )
  context$hierarchies[[inspection$hierarchy]] <- record
  invisible(record)
}

vpro_hierarchy_relation <- function(context, record) {
  paste(
    DBI::dbQuoteIdentifier(context$con, record$alias),
    DBI::dbQuoteIdentifier(context$con, record$table),
    sep = "."
  )
}

#' Activate an attached VPRO hierarchy
#'
#' Selection persists the current hierarchy and exposes a coordinator-scoped
#' `Hierarchy` compatibility view over the exact named source table.
#'
#' @param context A VPRO project context.
#' @param hierarchy Attached hierarchy name.
#'
#' @return Active hierarchy metadata, invisibly.
#' @export
vpro_hierarchy_activate <- function(context, hierarchy) {
  vpro_project_assert_context(context)
  hierarchy <- vpro_hierarchy_name(hierarchy)
  record <- context$hierarchies[[hierarchy]]
  if (is.null(record)) {
    stop("VPRO hierarchy is not attached: ", hierarchy, call. = FALSE)
  }

  relation <- vpro_hierarchy_relation(context, record)
  DBI::dbExecute(context$con, 'DROP VIEW IF EXISTS "Hierarchy"')
  vpro_project_create_view(context, "Hierarchy", paste("SELECT * FROM", relation))
  context$active_hierarchy <- record
  if (!is.null(context$config)) {
    context$config("Current", "CurrHierarchy", hierarchy)
    context$config("Current", "HierarchyPath", record$path)
  }
  invisible(record)
}

#' Deactivate the current VPRO hierarchy
#'
#' @param context A VPRO project context.
#'
#' @return `TRUE`, invisibly. Attached hierarchies remain attached.
#' @export
vpro_hierarchy_deactivate <- function(context) {
  vpro_project_assert_context(context)
  DBI::dbExecute(context$con, 'DROP VIEW IF EXISTS "Hierarchy"')
  context$active_hierarchy <- NULL
  if (!is.null(context$config)) {
    context$config("Current", "CurrHierarchy", "None")
    context$config("Current", "HierarchyPath", "")
  }
  invisible(TRUE)
}

#' Detach a VPRO hierarchy
#'
#' Detachment removes only lifecycle registration and releases the database when
#' no other project, SU, or hierarchy uses it. The SQLite source is unchanged.
#'
#' @param context A VPRO project context.
#' @param hierarchy Attached hierarchy name.
#'
#' @return `TRUE`, invisibly, when detached; `FALSE` if not attached.
#' @export
vpro_hierarchy_detach <- function(context, hierarchy) {
  vpro_project_assert_context(context)
  hierarchy <- vpro_hierarchy_name(hierarchy)
  record <- context$hierarchies[[hierarchy]]
  if (is.null(record)) {
    return(invisible(FALSE))
  }
  if (!is.null(context$active_hierarchy) && identical(context$active_hierarchy$hierarchy, hierarchy)) {
    stop("The active VPRO hierarchy cannot be detached.", call. = FALSE)
  }

  vpro_database_release(context, record$path, paste0("hierarchy:", hierarchy))
  context$hierarchies[[hierarchy]] <- NULL
  invisible(TRUE)
}

#' Save an attached VPRO hierarchy under a new name
#'
#' The hierarchy table, rows, explicit indexes, and translated metadata are
#' copied transactionally. The copy is neither attached nor activated.
#'
#' @param context A VPRO project context.
#' @param hierarchy Attached source hierarchy name.
#' @param path Target SQLite database path.
#' @param new_hierarchy Target hierarchy name without the `_Hierarchy` suffix.
#'
#' @return The normalized target path, invisibly.
#' @export
vpro_hierarchy_save_as <- function(context, hierarchy, path, new_hierarchy) {
  vpro_project_assert_context(context)
  hierarchy <- vpro_hierarchy_name(hierarchy)
  new_hierarchy <- vpro_hierarchy_name(new_hierarchy)
  if (identical(new_hierarchy, "Sample")) {
    stop("`Sample` is reserved and cannot be used as a save-as hierarchy name.", call. = FALSE)
  }
  record <- context$hierarchies[[hierarchy]]
  if (is.null(record)) {
    stop("VPRO hierarchy is not attached: ", hierarchy, call. = FALSE)
  }

  path <- normalizePath(path, mustWork = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  source <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(if (DBI::dbIsValid(source)) DBI::dbDisconnect(source), add = TRUE)
  DBI::dbExecute(source, "ATTACH DATABASE ? AS target", params = list(path))
  source_table <- record$table
  target_table <- vpro_hierarchy_table(new_hierarchy)
  collision <- DBI::dbGetQuery(
    source,
    "SELECT name FROM target.sqlite_master WHERE name = ?",
    params = list(target_table)
  )$name
  if (length(collision) > 0L) {
    stop("Target VPRO hierarchy table already exists: ", target_table, call. = FALSE)
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

#' Recover the configured VPRO hierarchy
#'
#' Recovery requires both a hierarchy name and source path. Failure clears the
#' active hierarchy without affecting recovered project or SU state.
#'
#' @param context A VPRO project context with configuration.
#' @param hierarchy Hierarchy name. By default, reads `CurrHierarchy`.
#' @param path Hierarchy database path. By default, reads `HierarchyPath`.
#'
#' @return Recovery status and any error message, invisibly.
#' @export
vpro_hierarchy_recover <- function(context, hierarchy = NULL, path = NULL) {
  vpro_project_assert_context(context)
  if (is.null(context$config)) {
    stop("VPRO hierarchy recovery requires a configuration accessor.", call. = FALSE)
  }
  if (is.null(hierarchy)) {
    hierarchy <- context$config("Current", "CurrHierarchy")
  }
  if (is.null(path)) {
    path <- context$config("Current", "HierarchyPath")
  }
  if (is.null(hierarchy) || !nzchar(hierarchy) || identical(hierarchy, "None") || is.null(path) || !nzchar(path)) {
    vpro_hierarchy_deactivate(context)
    return(invisible(list(active = NULL, recovered = FALSE, error = NULL)))
  }

  result <- tryCatch(
    {
      vpro_hierarchy_attach(context, path, hierarchy)
      vpro_hierarchy_activate(context, hierarchy)
    },
    error = identity
  )
  if (!inherits(result, "error")) {
    return(invisible(list(active = result, recovered = TRUE, error = NULL)))
  }

  if (hierarchy %in% names(context$hierarchies) &&
    (is.null(context$active_hierarchy) || !identical(context$active_hierarchy$hierarchy, hierarchy))) {
    vpro_hierarchy_detach(context, hierarchy)
  }
  vpro_hierarchy_deactivate(context)
  invisible(list(active = NULL, recovered = FALSE, error = conditionMessage(result)))
}
