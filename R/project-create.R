# Blank project creation ----------------------------------------------------

vpro_project_creation_versions <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO list-reference database does not exist: ", path, call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- c("USysAllSpecs", "USysTableOfLists")
  missing <- tables[!vapply(tables, DBI::dbExistsTable, logical(1), conn = con)]
  if (length(missing) > 0L) {
    stop("VPRO list-reference tables do not exist: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  versions <- stats::setNames(rep("Unknown", length(tables)), tables)
  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    return(versions)
  }
  fields <- DBI::dbListFields(con, "_table_metadata")
  if (!all(c("table_name", "description") %in% fields)) {
    stop("VPRO list-reference metadata must contain table_name and description.", call. = FALSE)
  }
  for (table in tables) {
    rows <- DBI::dbGetQuery(
      con,
      'SELECT description FROM "_table_metadata" WHERE table_name = ?',
      params = list(table)
    )
    if (nrow(rows) > 1L) {
      stop("Ambiguous VPRO list-reference description: ", table, call. = FALSE)
    }
    if (nrow(rows) == 1L && !is.na(rows$description[[1L]]) && nzchar(rows$description[[1L]])) {
      versions[[table]] <- rows$description[[1L]]
    }
  }
  versions
}

#' Create an empty VP08 project with initial reference-version audit rows
#'
#' Translates `V7mdlCreateTables.CreateTableSet` and its call to
#' `V7mdlAudit.LogNewProject`. Copies only the eight *schemas* and indexes of
#' the bundled VP08 Sample project, not its plot data or audit history.
#' Creates the target tables, their translated table descriptions, and three
#' initial audit rows (`NewProject`, `USysAllSpecs`, `USysTableOfLists`) in one
#' SQLite transaction. Missing reference descriptions are recorded as
#' `"Unknown"`. No project is attached or activated and no Shiny session is
#' needed. Save-as remains a distinct operation that preserves audit history.
#'
#' @param path Existing SQLite file or a path for a new file.
#' @param project New project name, excluding the reserved `Sample` name.
#' @param user Nonblank user name recorded in the three audit rows.
#' @param reference_path SQLite list reference with `USysAllSpecs` and
#'   `USysTableOfLists`, defaulting to bundled `VLists.db`.
#' @param template_path SQLite VP08 project schema source, defaulting to the
#'   bundled Sample project. Only table definitions, indexes, and metadata
#'   are copied; no rows are copied.
#'
#' @return Normalized target path, invisibly.
#' @export
vpro_project_create <- function(
  path,
  project,
  user,
  reference_path = vpro_bundled_file("extdata", "VLists.db"),
  template_path = vpro_bundled_file("extdata", "projects", "Sample.db")
) {
  project <- vpro_project_name(project)
  if (identical(project, "Sample")) {
    stop("`Sample` is reserved and cannot be used as a new project name.", call. = FALSE)
  }
  if (!is.character(user) || length(user) != 1L || is.na(user) || !nzchar(trimws(user))) {
    stop("`user` must be one nonblank character value.", call. = FALSE)
  }
  versions <- vpro_project_creation_versions(reference_path)
  template <- vpro_project_inspect(template_path, "Sample")
  if (!isTRUE(template$compatible)) {
    stop("VPRO project creation requires a complete VP08 Sample template.", call. = FALSE)
  }
  path <- normalizePath(path, mustWork = FALSE)
  if (identical(path, template$path) || identical(path, normalizePath(reference_path))) {
    stop("VPRO project target must differ from template and reference databases.", call. = FALSE)
  }
  if (!dir.exists(dirname(path))) {
    stop("VPRO project target directory does not exist: ", dirname(path), call. = FALSE)
  }
  source <- DBI::dbConnect(RSQLite::SQLite(), template$path)
  on.exit(DBI::dbDisconnect(source), add = TRUE)
  DBI::dbExecute(source, "ATTACH DATABASE ? AS target", params = list(path))
  suffixes <- c("Env", setdiff(.vpro_core_project_suffixes, "Env"))
  source_tables <- paste0("Sample_", suffixes)
  target_tables <- paste0(project, "_", suffixes)
  placeholders <- paste(rep("?", length(target_tables)), collapse = ", ")
  collisions <- DBI::dbGetQuery(
    source,
    paste0("SELECT name FROM target.sqlite_master WHERE name IN (", placeholders, ")"),
    params = as.list(target_tables)
  )$name
  if (length(collisions) > 0L) {
    stop("Target VPRO project tables already exist: ", paste(collisions, collapse = ", "), call. = FALSE)
  }

  DBI::dbWithTransaction(source, {
    schemas <- DBI::dbGetQuery(
      source,
      paste0("SELECT name, sql FROM main.sqlite_master WHERE type = 'table' AND name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    schemas <- schemas[match(source_tables, schemas$name), , drop = FALSE]
    for (i in seq_along(source_tables)) {
      sql <- vpro_project_rewrite_schema(schemas$sql[[i]], "Sample", project)
      sql <- sub(
        paste0('^CREATE TABLE ["`]?', target_tables[[i]], '["`]?'),
        paste0('CREATE TABLE target."', target_tables[[i]], '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }
    indexes <- DBI::dbGetQuery(
      source,
      paste0("SELECT name, sql FROM main.sqlite_master WHERE type = 'index' AND sql IS NOT NULL AND tbl_name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    for (i in seq_len(nrow(indexes))) {
      sql <- vpro_project_rewrite_schema(indexes$sql[[i]], "Sample", project)
      name <- vpro_project_rewrite_schema(indexes$name[[i]], "Sample", project)
      sql <- sub(
        paste0('^CREATE (UNIQUE )?INDEX ["`]?', name, '["`]?'),
        paste0('CREATE \\1INDEX target."', name, '"'),
        sql
      )
      DBI::dbExecute(source, sql)
    }
    DBI::dbExecute(source, 'CREATE TABLE IF NOT EXISTS target._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
    metadata <- DBI::dbGetQuery(
      source,
      paste0("SELECT table_name, description FROM main._table_metadata WHERE table_name IN (", placeholders, ")"),
      params = as.list(source_tables)
    )
    if (nrow(metadata) != length(source_tables)) {
      stop("VP08 Sample template is missing project table descriptions.", call. = FALSE)
    }
    metadata$table_name <- vapply(
      metadata$table_name,
      vpro_project_rewrite_schema,
      character(1),
      source_project = "Sample",
      target_project = project
    )
    DBI::dbWriteTable(source, DBI::Id(schema = "target", table = "_table_metadata"), metadata, append = TRUE)

    audit <- paste0('target.', DBI::dbQuoteIdentifier(source, paste0(project, "_Audit")))
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
    for (event in c("NewProject", names(versions))) {
      DBI::dbExecute(
        source,
        paste("INSERT INTO", audit, '("Project", "User", "Table", "EditWhen", "AfterEdit") VALUES (?, ?, ?, ?, ?)'),
        params = list(project, user, event, timestamp, if (event == "NewProject") NA_character_ else versions[[event]])
      )
    }
  })
  invisible(path)
}
