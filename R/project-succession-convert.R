# Succession conversion and recovery -----------------------------------------

vpro_succession_fields <- function(con, table) {
  if (!DBI::dbExistsTable(con, table)) {
    return(character())
  }
  tolower(DBI::dbListFields(con, table))
}

vpro_succession_status_con <- function(con, project, path) {
  tables <- paste0(project, "_", .vpro_core_project_suffixes)
  missing_tables <- tables[!vapply(tables, function(table) DBI::dbExistsTable(con, table), logical(1))]
  if (length(missing_tables)) {
    stop("Incomplete VPRO project family: ", paste(missing_tables, collapse = ", "), call. = FALSE)
  }
  env <- vpro_project_table(project, "Env")
  veg <- vpro_project_table(project, "Veg")
  if (
    !DBI::dbExistsTable(con, "_table_metadata") ||
      !all(c("table_name", "description") %in% DBI::dbListFields(con, "_table_metadata"))
  ) {
    stop("VPRO project version metadata is missing.", call. = FALSE)
  }
  version <- DBI::dbGetQuery(con, "SELECT description FROM _table_metadata WHERE table_name = ?", params = list(env))
  if (nrow(version) != 1L || is.na(version$description[[1L]]) || version$description[[1L]] != "VP08") {
    stop("Succession conversion requires a VP08 project.", call. = FALSE)
  }
  env_fields <- vpro_succession_fields(con, env)
  veg_fields <- vpro_succession_fields(con, veg)
  if (!"plotnumber" %in% env_fields || !all(c("plotnumber", "species", "id") %in% veg_fields)) {
    stop("Required VPRO Env/Veg fields are missing.", call. = FALSE)
  }
  has_year <- "successionyear" %in% veg_fields
  has_flag <- "successionplot" %in% env_fields
  state <- if (has_year && has_flag) {
    "converted"
  } else if (has_year) {
    "partial"
  } else if (has_flag) {
    "inconsistent"
  } else {
    "unconverted"
  }
  qenv <- DBI::dbQuoteIdentifier(con, env)
  qveg <- DBI::dbQuoteIdentifier(con, veg)
  distribution <- function(table, field) {
    if (is.null(field)) {
      return(NULL)
    }
    DBI::dbGetQuery(
      con,
      paste("SELECT", DBI::dbQuoteIdentifier(con, field), "AS value, COUNT(*) AS n FROM", table, "GROUP BY", DBI::dbQuoteIdentifier(con, field), "ORDER BY value")
    )
  }
  list(
    path = path,
    project = project,
    state = state,
    veg_rows = DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", qveg))$n[[1L]],
    env_rows = DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", qenv))$n[[1L]],
    years = distribution(qveg, if (has_year) DBI::dbListFields(con, veg)[match("successionyear", veg_fields)] else NULL),
    flags = distribution(qenv, if (has_flag) DBI::dbListFields(con, env)[match("successionplot", env_fields)] else NULL)
  )
}

#' Inspect physical succession conversion state
#'
#' Unlike [vpro_project_is_successional()], checks both project tables and
#' reports partial or inconsistent conversion. Does not change the database.
#'
#' @param path Existing SQLite project database.
#' @param project Project prefix.
#' @return A list with `state` (`unconverted`, `converted`, `partial`, or
#'   `inconsistent`), row counts, and distributions of present succession fields.
#' @export
vpro_project_succession_status <- function(path, project) {
  project <- vpro_project_name(project)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO project database does not exist.", call. = FALSE)
  }
  path <- normalizePath(path, mustWork = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  vpro_succession_status_con(con, project, path)
}

vpro_succession_guard <- function(context, path, project, backup_path, permission, authorize) {
  if (!is.null(context)) {
    vpro_project_assert_context(context)
  }
  project <- vpro_project_name(project)
  if (identical(tolower(project), "sample")) {
    stop("Sample cannot be converted.", call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO project database does not exist.", call. = FALSE)
  }
  path <- normalizePath(path, mustWork = TRUE)
  bundled <- normalizePath(system.file("extdata", package = "vpro"), mustWork = TRUE)
  if (identical(path, bundled) || startsWith(path, paste0(bundled, .Platform$file.sep))) {
    stop("Bundled VPRO databases cannot be modified.", call. = FALSE)
  }
  if (!is.character(backup_path) || length(backup_path) != 1L || is.na(backup_path) || !nzchar(backup_path)) {
    stop("A new backup path is required.", call. = FALSE)
  }
  backup_path <- normalizePath(backup_path, mustWork = FALSE)
  if (
    identical(path, backup_path) ||
      file.exists(backup_path) ||
      !dir.exists(dirname(backup_path)) ||
      identical(backup_path, bundled) ||
      startsWith(backup_path, paste0(bundled, .Platform$file.sep))
  ) {
    stop("Backup path must name a new file in an existing directory, distinct from the project.", call. = FALSE)
  }
  if (!is.null(context) && (path %in% names(context$databases) || path %in% vpro_database_attached(context)$path)) {
    stop("Detach this database from the VPRO context before changing its schema.", call. = FALSE)
  }
  resource <- list(path = path, project = project, backup_path = backup_path)
  if (!is.function(authorize) || !isTRUE(authorize(permission, resource))) {
    stop("Succession operation requires `", permission, "` authorization.", call. = FALSE)
  }
  list(path = path, project = project, backup_path = backup_path)
}

vpro_succession_year <- function(year) {
  if (!is.numeric(year) || length(year) != 1L || is.na(year) || !is.finite(year) || year < 1 || year > 9999 || year != as.integer(year)) {
    stop("Succession year must be a whole calendar year from 1 to 9999.", call. = FALSE)
  }
  as.integer(year)
}

vpro_succession_identity <- function(con, project) {
  lapply(c("Env", "Veg"), function(suffix) {
    table <- DBI::dbQuoteIdentifier(con, vpro_project_table(project, suffix))
    fields <- if (suffix == "Veg") '"PlotNumber", "Species", "ID"' else '"PlotNumber"'
    DBI::dbGetQuery(con, paste("SELECT rowid,", fields, "FROM", table, "ORDER BY rowid"))
  })
}

vpro_succession_schema <- function(con, project) {
  DBI::dbGetQuery(
    con,
    "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE tbl_name IN (?, ?) AND type IN ('table', 'index') ORDER BY type, name",
    params = list(vpro_project_table(project, "Veg"), vpro_project_table(project, "Env"))
  )
}

vpro_succession_apply <- function(context, path, project, backup_path, permission, from, year = NULL, authorize = NULL, .fail_at = NULL) {
  args <- vpro_succession_guard(context, path, project, backup_path, permission, authorize)
  con <- DBI::dbConnect(RSQLite::SQLite(), args$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  before <- vpro_succession_status_con(con, project, args$path)
  if (before$state != from) {
    stop("Expected ", from, " succession state; found ", before$state, ".", call. = FALSE)
  }
  if (
    from == "partial" &&
      (before$veg_rows == 0L ||
        nrow(before$years) != 1L ||
        is.na(before$years$value[[1L]]) ||
        !isTRUE(tryCatch(vpro_succession_year(before$years$value[[1L]]) == before$years$value[[1L]], error = function(e) FALSE)))
  ) {
    stop("Partial recovery requires one nonmissing valid existing year; vegetation is unchanged.", call. = FALSE)
  }
  identities <- vpro_succession_identity(con, project)
  schema <- vpro_succession_schema(con, project)
  if (nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check"))) {
    stop("Existing foreign-key violations prevent succession conversion.", call. = FALSE)
  }
  # VACUUM INTO takes a consistent snapshot, including databases in WAL mode.
  DBI::dbExecute(con, paste("VACUUM INTO", DBI::dbQuoteString(con, args$backup_path)))
  backup <- DBI::dbConnect(RSQLite::SQLite(), args$backup_path, flags = RSQLite::SQLITE_RO)
  on.exit(if (DBI::dbIsValid(backup)) DBI::dbDisconnect(backup), add = TRUE)
  backup_state <- vpro_succession_status_con(backup, project, args$backup_path)
  backup_valid <- identical(before[c("state", "veg_rows", "env_rows", "years", "flags")], backup_state[c("state", "veg_rows", "env_rows", "years", "flags")]) &&
    identical(identities, vpro_succession_identity(backup, project)) &&
    identical(schema, vpro_succession_schema(backup, project)) &&
    DBI::dbGetQuery(backup, "PRAGMA integrity_check")[[1L]][[1L]] == "ok"
  DBI::dbDisconnect(backup)
  if (!backup_valid) {
    stop("Backup validation failed; original project was not changed.", call. = FALSE)
  }
  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con)) DBI::dbRollback(con), add = TRUE)
  locked <- vpro_succession_status_con(con, project, args$path)
  if (
    !identical(before, locked) ||
      !identical(identities, vpro_succession_identity(con, project)) ||
      !identical(schema, vpro_succession_schema(con, project)) ||
      nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check"))
  ) {
    stop("Project changed since backup; conversion was cancelled.", call. = FALSE)
  }
  veg <- DBI::dbQuoteIdentifier(con, vpro_project_table(project, "Veg"))
  env <- DBI::dbQuoteIdentifier(con, vpro_project_table(project, "Env"))
  if (from == "unconverted") {
    DBI::dbExecute(con, paste("ALTER TABLE", veg, "ADD COLUMN SuccessionYear INTEGER CHECK (SuccessionYear BETWEEN 1 AND 9999)"))
    if (identical(.fail_at, "after_ddl")) {
      stop("Injected succession failure after Veg DDL.", call. = FALSE)
    }
    DBI::dbExecute(con, paste("UPDATE", veg, "SET SuccessionYear = ?"), params = list(year))
    if (identical(.fail_at, "after_update")) stop("Injected succession failure after Veg update.", call. = FALSE)
  }
  DBI::dbExecute(con, paste("ALTER TABLE", env, "ADD COLUMN SuccessionPlot INTEGER DEFAULT 0 CHECK (SuccessionPlot IN (0, 1))"))
  if (identical(.fail_at, "after_env")) {
    stop("Injected succession failure after Env DDL.", call. = FALSE)
  }
  after <- vpro_succession_status_con(con, project, args$path)
  after_schema <- vpro_succession_schema(con, project)
  if (
    after$state != "converted" ||
      after$veg_rows != before$veg_rows ||
      after$env_rows != before$env_rows ||
      (from == "partial" && !identical(after$years, before$years)) ||
      (from == "unconverted" &&
        ((before$veg_rows == 0L && nrow(after$years) != 0L) ||
          (before$veg_rows > 0L && (nrow(after$years) != 1L || after$years$value[[1L]] != year)))) ||
      nrow(after$flags) != as.integer(before$env_rows > 0L) ||
      (nrow(after$flags) && (is.na(after$flags$value[[1L]]) || after$flags$value[[1L]] != 0L)) ||
      !identical(identities, vpro_succession_identity(con, project)) ||
      !identical(schema[schema$type == "index", , drop = FALSE], after_schema[after_schema$type == "index", , drop = FALSE]) ||
      nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check"))
  ) {
    stop("Succession verification failed; changes were rolled back.", call. = FALSE)
  }
  DBI::dbCommit(con)
  committed <- TRUE
  list(
    path = args$path,
    project = project,
    state_before = before$state,
    state_after = after$state,
    year = if (from == "partial") before$years$value[[1L]] else year,
    veg_rows = after$veg_rows,
    env_rows = after$env_rows,
    backup_path = args$backup_path,
    backup_md5 = unname(tools::md5sum(args$backup_path)),
    activation = "not attempted; attach and activate the project in a fresh context"
  )
}

#' Convert a VPRO project to succession data atomically
#'
#' Adds the Veg year and Env plot flag in one SQLite transaction. Requires an
#' explicit authorization callback and a new backup path. If a VPRO context
#' is supplied the database must be detached from it, and other readers
#' and writers must be quiesced by the caller. Does not activate the project.
#' The backup remains available even if conversion rolls back.
#'
#' @param context Optional VPRO project context. Supplied contexts must not
#'   have the project database attached.
#' @param authorize Required callback `authorize(permission, resource)`;
#'   the permission is `convert_succession` or `recover_succession`.
#' @param path Physical SQLite database, not a packaged resource.
#' @param project VP08 project prefix other than Sample.
#' @param year Whole calendar year from 1 through 9999.
#' @param backup_path New file path in an existing directory for a consistent SQLite backup.
#' @return A receipt with before/after states, row counts, backup path and hash,
#'   and activation status.
#' @export
vpro_project_convert_succession <- function(path, project, year, backup_path, authorize, context = NULL) {
  year <- vpro_succession_year(year)
  vpro_succession_apply(context, path, project, backup_path, "convert_succession", "unconverted", year, authorize)
}

#' Repair an interrupted succession conversion without rewriting Veg
#'
#' Only accepts the legacy partial state (Veg year present, Env flag missing)
#' with one valid nonmissing existing year. Adds the Env flag atomically while
#' leaving all Veg values untouched. Requires separate authorization and backup.
#' Other inconsistent states require manual investigation.
#'
#' @inheritParams vpro_project_convert_succession
#' @return A conversion receipt; the year is read from the existing Veg rows.
#' @export
vpro_project_recover_succession <- function(path, project, backup_path, authorize, context = NULL) {
  vpro_succession_apply(context, path, project, backup_path, "recover_succession", "partial", authorize = authorize)
}
