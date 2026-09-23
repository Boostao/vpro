# Project context ----------------------------------------------------------

vpro_project_name <- function(project) {
  if (length(project) != 1L || is.na(project) || !grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", project)) {
    stop(
      "VPRO project names must start with a letter, contain only letters, numbers, and underscores, and be at most 31 characters.",
      call. = FALSE
    )
  }
  project
}

vpro_project_table <- function(project, suffix) {
  paste0(vpro_project_name(project), "_", suffix)
}

vpro_project_metadata <- function(path, project) {
  project <- vpro_project_name(project)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    return("Unknown")
  }

  result <- DBI::dbGetQuery(
    con,
    "SELECT description FROM _table_metadata WHERE table_name = ?",
    params = list(vpro_project_table(project, "Env"))
  )
  if (nrow(result) != 1L || is.na(result$description[[1]]) || !nzchar(result$description[[1]])) {
    return("Unknown")
  }
  result$description[[1]]
}

#' Inspect a VPRO project database
#'
#' This validates the eight-table project family and reads the project version
#' translated from the Access `_Env` table Description property.
#'
#' @param path Path to a VPRO project SQLite database.
#' @param project Project prefix.
#'
#' @return A list containing normalized path, project, version, compatibility,
#'   and table-family validation.
#' @export
vpro_project_inspect <- function(path, project) {
  project <- vpro_project_name(project)
  path <- normalizePath(path, mustWork = FALSE)
  if (!file.exists(path)) {
    stop("VPRO project database does not exist: ", path, call. = FALSE)
  }

  validation <- vpro_project_validate(path, project)
  version <- vpro_project_metadata(path, project)
  list(
    path = path,
    project = project,
    version = version,
    compatible = identical(version, "VP08") && all(validation$present),
    validation = validation
  )
}

#' Create a VPRO project context
#'
#' A context owns the active-project state and a DuckDB coordinator used to
#' compose attached SQLite databases. It does not require a Shiny session.
#'
#' @param con Optional connection created by [vpro_db_connect()]. When omitted,
#'   the context creates and owns a new coordinator.
#' @param config Optional accessor created by [config_init()]. Activating a
#'   project writes `CurrProject`, `CurrPlotlist`, `ProjectPath`, and `SUPath`;
#'   hierarchy lifecycle operations write `CurrHierarchy` and `HierarchyPath`.
#' @param authorize Optional permission callback called as
#'   `authorize(permission, resource)`. Domain operations default to denying
#'   restricted actions when it is absent.
#' @param install_extensions Passed to [vpro_db_connect()] when `con` is absent.
#'
#' @return A mutable object of class `vpro_project_context`.
#' @export
vpro_project_context <- function(
  con = NULL,
  config = NULL,
  authorize = NULL,
  install_extensions = getOption("vpro.install_extensions", FALSE)
) {
  owns_connection <- is.null(con)
  if (owns_connection) {
    con <- vpro_db_connect(install_extensions = install_extensions)
  }
  if (!DBI::dbIsValid(con)) {
    stop("The VPRO project context requires a valid DBI connection.", call. = FALSE)
  }
  if (!is.null(config) && !is.function(config)) {
    stop("`config` must be NULL or an accessor created by `config_init()`.", call. = FALSE)
  }
  if (!is.null(authorize) && !is.function(authorize)) {
    stop("`authorize` must be NULL or a permission callback.", call. = FALSE)
  }

  context <- new.env(parent = emptyenv())
  context$con <- con
  context$config <- config
  context$authorize <- authorize
  context$owns_connection <- owns_connection
  context$databases <- list()
  context$projects <- list()
  context$sus <- list()
  context$hierarchies <- list()
  context$active <- NULL
  context$active_su <- NULL
  context$active_hierarchy <- NULL
  class(context) <- "vpro_project_context"
  context
}

vpro_project_assert_context <- function(context) {
  if (
    !inherits(context, "vpro_project_context") ||
      !DBI::dbIsValid(context$con)
  ) {
    stop("A valid VPRO project context is required.", call. = FALSE)
  }
  invisible(context)
}

vpro_project_alias <- function(project) {
  paste0("vpro_project_", tolower(vpro_project_name(project)))
}

vpro_database_attached <- function(context) {
  databases <- DBI::dbGetQuery(context$con, "SELECT database_name, path FROM duckdb_databases()")
  databases <- databases[!is.na(databases$path), , drop = FALSE]
  if (nrow(databases) > 0L) {
    databases$path <- normalizePath(databases$path, mustWork = FALSE)
  }
  databases
}

vpro_database_acquire <- function(context, path, alias, owner) {
  path <- normalizePath(path, mustWork = TRUE)
  existing <- context$databases[[path]]
  if (!is.null(existing)) {
    existing$owners <- unique(c(existing$owners, owner))
    context$databases[[path]] <- existing
    return(existing$alias)
  }

  attached <- vpro_database_attached(context)
  path_match <- which(attached$path == path)
  if (length(path_match) > 0L) {
    alias <- attached$database_name[[path_match[[1]]]]
    owned <- FALSE
  } else {
    if (alias %in% vpro_db_list(context$con)) {
      stop("The VPRO database alias is already attached: ", alias, call. = FALSE)
    }
    statement <- paste(
      "ATTACH",
      DBI::dbQuoteLiteral(context$con, path),
      "AS",
      DBI::dbQuoteIdentifier(context$con, alias),
      "(TYPE sqlite)"
    )
    DBI::dbExecute(context$con, statement)
    owned <- TRUE
  }

  context$databases[[path]] <- list(
    path = path,
    alias = alias,
    owned = owned,
    owners = owner
  )
  alias
}

vpro_database_release <- function(context, path, owner) {
  path <- normalizePath(path, mustWork = FALSE)
  record <- context$databases[[path]]
  if (is.null(record)) {
    return(invisible(FALSE))
  }
  record$owners <- setdiff(record$owners, owner)
  if (length(record$owners) > 0L) {
    context$databases[[path]] <- record
    return(invisible(FALSE))
  }
  if (isTRUE(record$owned) && record$alias %in% vpro_db_list(context$con)) {
    vpro_db_detach(context$con, record$alias)
  }
  context$databases[[path]] <- NULL
  invisible(TRUE)
}

#' Attach a project to a VPRO project context
#'
#' Only complete VP08 project families are attached directly. VP05 through VP07
#' require a separate conversion workflow, matching the version gate in
#' `V7mdlAttachProjects.AttachProject`.
#'
#' @param context A VPRO project context.
#' @param path Path to a VPRO project SQLite database.
#' @param project Project prefix.
#'
#' @return Project attachment metadata, invisibly.
#' @export
vpro_project_attach <- function(context, path, project) {
  vpro_project_assert_context(context)
  inspection <- vpro_project_inspect(path, project)
  missing <- inspection$validation$table[!inspection$validation$present]
  if (length(missing) > 0L) {
    stop(
      "VPRO project family is incomplete; missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (inspection$version %in% c("VP05", "VP06", "VP07")) {
    stop(
      "VPRO project version ",
      inspection$version,
      " requires conversion before it can be attached.",
      call. = FALSE
    )
  }
  if (!identical(inspection$version, "VP08")) {
    stop(
      "Unsupported VPRO project version: ",
      inspection$version,
      ". Expected VP08.",
      call. = FALSE
    )
  }
  if (inspection$project %in% names(context$projects)) {
    existing <- context$projects[[inspection$project]]
    if (identical(existing$path, inspection$path)) {
      return(invisible(existing))
    }
    stop("A different database is already attached for project: ", inspection$project, call. = FALSE)
  }

  alias <- vpro_database_acquire(
    context,
    inspection$path,
    vpro_project_alias(inspection$project),
    paste0("project:", inspection$project)
  )

  record <- list(
    project = inspection$project,
    path = inspection$path,
    alias = alias,
    version = inspection$version
  )
  context$projects[[inspection$project]] <- record
  invisible(record)
}

vpro_project_relation <- function(context, record, suffix) {
  paste(
    DBI::dbQuoteIdentifier(context$con, record$alias),
    DBI::dbQuoteIdentifier(
      context$con,
      vpro_project_table(record$project, suffix)
    ),
    sep = "."
  )
}

vpro_project_drop_views <- function(context) {
  views <- c(
    "Filtered_Env",
    "USysVegD",
    "USysVegC",
    "USysVegB",
    "USysVegA",
    "USysMetadata",
    "USysOther",
    "USysAuditTrail",
    "USysMineral",
    "USysHumus",
    "USysVeg",
    "USysEnv"
  )
  for (view in views) {
    DBI::dbExecute(
      context$con,
      paste("DROP VIEW IF EXISTS", DBI::dbQuoteIdentifier(context$con, view))
    )
  }
  invisible(TRUE)
}

vpro_project_create_view <- function(context, name, sql) {
  DBI::dbExecute(
    context$con,
    paste(
      "CREATE TEMP VIEW",
      DBI::dbQuoteIdentifier(context$con, name),
      "AS",
      sql
    )
  )
}

vpro_project_veg_sql <- function(context, record) {
  veg <- vpro_project_relation(context, record, "Veg")
  fields <- DBI::dbListFields(
    context$con,
    DBI::Id(schema = record$alias, table = vpro_project_table(record$project, "Veg"))
  )
  succession <- "SuccessionYear" %in% fields
  shared <- if (succession) '"ID", "PlotNumber", "SuccessionYear", "Species"' else '"ID", "PlotNumber", "Species"'

  if (succession) {
    list(
      USysVegA = paste(
        "SELECT DISTINCT",
        shared,
        ', "Cover1", "Cover2", "Cover3", "TotalA", "HeightA", "Cover4", "Cover5", "TotalB", "HeightB", "Collected" FROM',
        veg,
        'WHERE "Cover1" IS NOT NULL OR "Cover2" IS NOT NULL OR "Cover3" IS NOT NULL OR "TotalA" IS NOT NULL OR "Cover4" IS NOT NULL OR "Cover5" IS NOT NULL OR "TotalB" IS NOT NULL'
      ),
      USysVegB = paste(
        "SELECT DISTINCT",
        shared,
        ', "Cover4", "Cover5", "TotalB", "Collected" FROM',
        veg,
        'WHERE "Cover4" IS NOT NULL OR "Cover5" IS NOT NULL OR "TotalB" IS NOT NULL'
      ),
      USysVegC = paste("SELECT DISTINCT", shared, ', "Cover6", "Collected" FROM', veg, 'WHERE "Cover6" IS NOT NULL'),
      USysVegD = paste("SELECT DISTINCT", shared, ', "Cover7", "Collected" FROM', veg, 'WHERE "Cover7" IS NOT NULL')
    )
  } else {
    list(
      USysVegA = paste(
        "SELECT DISTINCT",
        shared,
        ', "Cover1", "Cover2", "Cover3", "TotalA", "HeightA", "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "HeightB", "Collected" FROM',
        veg,
        'WHERE "Cover1" IS NOT NULL OR "Cover2" IS NOT NULL OR "Cover3" IS NOT NULL OR "TotalA" IS NOT NULL OR "Cover4" IS NOT NULL OR "Cover5" IS NOT NULL OR "TotalB" IS NOT NULL OR "Cover5a" IS NOT NULL OR "Cover5b" IS NOT NULL OR "Cover5c" IS NOT NULL'
      ),
      USysVegB = paste(
        "SELECT DISTINCT",
        shared,
        ', "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "Collected" FROM',
        veg,
        'WHERE "Cover4" IS NOT NULL OR "Cover5" IS NOT NULL OR "TotalB" IS NOT NULL OR "Cover5a" IS NOT NULL OR "Cover5b" IS NOT NULL OR "Cover5c" IS NOT NULL'
      ),
      USysVegC = paste("SELECT DISTINCT", shared, ', "Cover6", "Height6", "Collected" FROM', veg, 'WHERE "Cover6" IS NOT NULL'),
      USysVegD = paste(
        "SELECT DISTINCT",
        shared,
        ', "Cover7", "Cover8", "Cover9", "Collected" FROM',
        veg,
        'WHERE "Cover7" IS NOT NULL OR "Cover8" IS NOT NULL OR "Cover9" IS NOT NULL'
      )
    )
  }
}

#' Activate an attached VPRO project
#'
#' Temporary DuckDB views replace the Access query-definition rewrites performed
#' by `V7mdlSetCurrent.SetCurrentProject`. Activation also resets the current
#' plot list when a configuration accessor is present.
#'
#' @param context A VPRO project context.
#' @param project Attached project prefix.
#'
#' @return Active project metadata, invisibly.
#' @export
vpro_project_activate <- function(context, project) {
  vpro_project_assert_context(context)
  project <- vpro_project_name(project)
  record <- context$projects[[project]]
  if (is.null(record)) {
    stop("VPRO project is not attached: ", project, call. = FALSE)
  }

  vpro_project_drop_views(context)
  env <- vpro_project_relation(context, record, "Env")
  admin <- vpro_project_relation(context, record, "Admin")
  view_sql <- list(
    USysEnv = paste("SELECT DISTINCT env.*, admin.* FROM", env, "AS env INNER JOIN", admin, 'AS admin ON env."PlotNumber" = admin."Plot"'),
    USysVeg = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Veg")),
    USysHumus = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Humus")),
    USysMineral = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Mineral")),
    USysAuditTrail = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Audit"), 'ORDER BY "EditWhen"'),
    USysOther = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Other")),
    USysMetadata = paste("SELECT DISTINCT * FROM", vpro_project_relation(context, record, "Metadata"))
  )
  view_sql <- c(view_sql, vpro_project_veg_sql(context, record))
  for (name in names(view_sql)) {
    vpro_project_create_view(context, name, view_sql[[name]])
  }

  context$active <- record
  context$active_su <- NULL
  if (!is.null(context$config)) {
    context$config("Current", "CurrProject", project)
    context$config("Current", "CurrPlotlist", "None")
    context$config("Current", "ProjectPath", record$path)
    context$config("Current", "SUPath", "")
  }
  invisible(record)
}

#' Recover the current VPRO project
#'
#' Startup recovery first attempts to attach and activate the project persisted in
#' the configuration. If that project cannot be opened as a complete VP08 family,
#' the supplied Sample database is activated instead. This is the non-interactive
#' equivalent of `V7mdlSplash.CompareRegToCurrent` and
#' `V7mdlSplash.ReattachSplashProject`.
#'
#' @param context A VPRO project context with a configuration accessor.
#' @param project Project prefix to recover. By default, reads `CurrProject`.
#' @param path Project database path. By default, reads `ProjectPath`.
#' @param sample_path Path to the fallback Sample SQLite database.
#'
#' @return A list containing the active project metadata, whether fallback was
#'   required, and the primary recovery error when applicable, invisibly.
#' @export
vpro_project_recover <- function(
  context,
  project = NULL,
  path = NULL,
  sample_path = vpro_db_path("Sample", "projects")
) {
  vpro_project_assert_context(context)
  if (is.null(context$config)) {
    stop("VPRO project recovery requires a configuration accessor.", call. = FALSE)
  }
  if (is.null(project)) {
    project <- context$config("Current", "CurrProject")
  }
  if (is.null(path)) {
    path <- context$config("Current", "ProjectPath")
  }
  configured_su <- context$config("Current", "CurrPlotlist")
  configured_su_path <- context$config("Current", "SUPath")
  configured_hierarchy <- context$config("Current", "CurrHierarchy")
  configured_hierarchy_path <- context$config("Current", "HierarchyPath")
  if (
    identical(configured_hierarchy, "Sample") &&
      (is.null(configured_hierarchy_path) || !nzchar(configured_hierarchy_path))
  ) {
    configured_hierarchy_path <- sample_path
  }

  activate <- function(candidate_project, candidate_path) {
    vpro_project_attach(context, candidate_path, candidate_project)
    vpro_project_activate(context, candidate_project)
  }
  primary_error <- NULL
  record <- tryCatch(
    activate(project, path),
    error = function(error) {
      primary_error <<- conditionMessage(error)
      NULL
    }
  )
  if (!is.null(record)) {
    su <- vpro_su_recover(
      context,
      su = configured_su,
      path = configured_su_path
    )
    hierarchy <- vpro_hierarchy_recover(
      context,
      hierarchy = configured_hierarchy,
      path = configured_hierarchy_path
    )
    return(invisible(list(
      active = record,
      fallback = FALSE,
      primary_error = NULL,
      su = su,
      hierarchy = hierarchy
    )))
  }
  if (project %in% names(context$projects) && (is.null(context$active) || !identical(context$active$project, project))) {
    vpro_project_detach(context, project)
  }

  fallback <- tryCatch(
    activate("Sample", sample_path),
    error = identity
  )
  if (inherits(fallback, "error")) {
    stop(
      "Could not recover the configured VPRO project (",
      primary_error,
      ") or the Sample fallback (",
      conditionMessage(fallback),
      ").",
      call. = FALSE
    )
  }

  su <- vpro_su_recover(
    context,
    su = configured_su,
    path = configured_su_path
  )
  if (
    identical(configured_hierarchy, "Sample") &&
      (is.null(configured_hierarchy_path) || !nzchar(configured_hierarchy_path))
  ) {
    configured_hierarchy_path <- sample_path
  }
  hierarchy <- vpro_hierarchy_recover(
    context,
    hierarchy = configured_hierarchy,
    path = configured_hierarchy_path
  )
  invisible(list(
    active = fallback,
    fallback = TRUE,
    primary_error = primary_error,
    su = su,
    hierarchy = hierarchy
  ))
}

#' Detach a project from a VPRO project context
#'
#' Detaching removes only the DuckDB attachment. The source SQLite database is
#' never modified or deleted. The active project cannot be detached.
#'
#' @param context A VPRO project context.
#' @param project Attached project prefix.
#'
#' @return `TRUE`, invisibly, when detached; `FALSE` if not attached.
#' @export
vpro_project_detach <- function(context, project) {
  vpro_project_assert_context(context)
  project <- vpro_project_name(project)
  record <- context$projects[[project]]
  if (is.null(record)) {
    return(invisible(FALSE))
  }
  if (!is.null(context$active) && identical(context$active$project, project)) {
    stop("The active VPRO project cannot be detached.", call. = FALSE)
  }

  vpro_database_release(
    context,
    record$path,
    paste0("project:", project)
  )
  context$projects[[project]] <- NULL
  invisible(TRUE)
}

#' Close a VPRO project context
#'
#' @param context A VPRO project context.
#'
#' @return `TRUE`, invisibly. A caller-supplied connection remains open.
#' @export
vpro_project_close <- function(context) {
  vpro_project_assert_context(context)
  if (isTRUE(context$owns_connection)) {
    vpro_db_disconnect(context$con)
  }
  invisible(TRUE)
}

vpro_project_rewrite_schema <- function(sql, source_project, target_project) {
  for (suffix in .vpro_core_project_suffixes) {
    sql <- gsub(
      paste0(source_project, "_", suffix),
      paste0(target_project, "_", suffix),
      sql,
      fixed = TRUE
    )
  }
  sql
}

#' Save an attached VPRO project under a new name
#'
#' The eight core tables, their data, indexes, foreign keys, and table-version
#' metadata are copied in one SQLite transaction. Unlike the Access routine,
#' every target-family collision is rejected before copying begins.
#'
#' @param context A VPRO project context.
#' @param project Attached source project prefix.
#' @param path Target SQLite database path. A new file is created if needed.
#' @param new_project Target project prefix.
#'
#' @return The normalized target path, invisibly.
#' @export
vpro_project_save_as <- function(context, project, path, new_project) {
  vpro_project_assert_context(context)
  project <- vpro_project_name(project)
  new_project <- vpro_project_name(new_project)
  if (identical(new_project, "Sample")) {
    stop("`Sample` is reserved and cannot be used as a save-as project name.", call. = FALSE)
  }
  record <- context$projects[[project]]
  if (is.null(record)) {
    stop("VPRO project is not attached: ", project, call. = FALSE)
  }

  path <- normalizePath(path, mustWork = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  source <- DBI::dbConnect(RSQLite::SQLite(), record$path)
  on.exit(
    if (DBI::dbIsValid(source)) DBI::dbDisconnect(source),
    add = TRUE
  )
  DBI::dbExecute(source, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(source, "ATTACH DATABASE ? AS target", params = list(path))

  copy_suffixes <- c("Env", setdiff(.vpro_core_project_suffixes, "Env"))
  target_tables <- paste0(new_project, "_", copy_suffixes)
  placeholders <- paste(rep("?", length(target_tables)), collapse = ", ")
  collisions <- DBI::dbGetQuery(
    source,
    paste0("SELECT name FROM target.sqlite_master WHERE type = 'table' AND name IN (", placeholders, ")"),
    params = as.list(target_tables)
  )$name
  if (length(collisions) > 0L) {
    stop("Target VPRO project tables already exist: ", paste(collisions, collapse = ", "), call. = FALSE)
  }

  DBI::dbWithTransaction(source, {
    source_tables <- paste0(project, "_", copy_suffixes)
    schemas <- DBI::dbGetQuery(
      source,
      paste0("SELECT name, sql FROM main.sqlite_master WHERE type = 'table' AND name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    schemas <- schemas[match(source_tables, schemas$name), , drop = FALSE]

    for (index in seq_along(source_tables)) {
      sql <- vpro_project_rewrite_schema(schemas$sql[[index]], project, new_project)
      sql <- sub(
        paste0('^CREATE TABLE ["`]?', target_tables[[index]], '["`]?'),
        paste0('CREATE TABLE target."', target_tables[[index]], '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }

    indexes <- DBI::dbGetQuery(
      source,
      paste0("SELECT name, tbl_name, sql FROM main.sqlite_master WHERE type = 'index' AND sql IS NOT NULL AND tbl_name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    for (index in seq_len(nrow(indexes))) {
      sql <- vpro_project_rewrite_schema(indexes$sql[[index]], project, new_project)
      target_index <- vpro_project_rewrite_schema(
        indexes$name[[index]],
        project,
        new_project
      )
      sql <- sub(
        paste0('^CREATE (UNIQUE )?INDEX ["`]?', target_index, '["`]?'),
        paste0('CREATE \\1INDEX target."', target_index, '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }

    for (index in seq_along(source_tables)) {
      DBI::dbExecute(
        source,
        paste(
          "INSERT INTO target.",
          DBI::dbQuoteIdentifier(source, target_tables[[index]]),
          "SELECT * FROM main.",
          DBI::dbQuoteIdentifier(source, source_tables[[index]])
        )
      )
    }

    DBI::dbExecute(
      source,
      paste(
        "CREATE TABLE IF NOT EXISTS target._table_metadata",
        "(table_name TEXT PRIMARY KEY, description TEXT)"
      )
    )
    metadata <- DBI::dbGetQuery(
      source,
      paste0("SELECT table_name, description FROM main._table_metadata WHERE table_name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    if (nrow(metadata) > 0L) {
      metadata$table_name <- vapply(
        metadata$table_name,
        vpro_project_rewrite_schema,
        character(1),
        source_project = project,
        target_project = new_project
      )
      DBI::dbWriteTable(source, DBI::Id(schema = "target", table = "_table_metadata"), metadata, append = TRUE)
    }
  })

  invisible(path)
}
