# VP08 archive promotion ---------------------------------------------------

#' Promote an archived VP08 Access project to a package-compatible SQLite file
#'
#' Copies one exact VP08 eight-table family from [vpro_access_archive()] to a
#' separate new SQLite file with the bundled Sample schema, indexes, and foreign
#' keys. Historical versions, missing fields, extra project fields, non-VP08
#' Env descriptions, or data violating canonical constraints are refused; the
#' original archive remains intact for inspection. Independent and source-only
#' tables remain in the archive, not in the promoted project. Does not create
#' `NewProject` audit events, attach the file, or run Access upgrade routines.
#'
#' @param archive_path SQLite archive created by [vpro_access_archive()].
#' @param project Exact Access project prefix.
#' @param output_path Unused SQLite destination in an existing directory.
#' @param template_path VP08 schema source, defaulting to bundled Sample.
#' @return Normalized promoted path, invisibly.
#' @export
vpro_access_promote_vp08 <- function(
  archive_path,
  project,
  output_path,
  template_path = vpro_bundled_file("extdata", "projects", "Sample.db")
) {
  project <- vpro_project_name(project)
  archive_path <- vpro_access_source(archive_path)
  template <- vpro_project_inspect(template_path, "Sample")
  if (!isTRUE(template$compatible)) {
    stop("A complete VP08 Sample template is required.", call. = FALSE)
  }
  output_path <- vpro_access_output(output_path, c(archive_path, template$path))
  archive <- DBI::dbConnect(RSQLite::SQLite(), archive_path)
  on.exit(DBI::dbDisconnect(archive), add = TRUE)
  if (!all(c("_vpro_access_manifest", "_table_metadata") %in% DBI::dbListTables(archive))) {
    stop("Input is not a validated VPRO Access archive.", call. = FALSE)
  }
  tables <- paste0(project, "_", c("Env", setdiff(.vpro_core_project_suffixes, "Env")))
  manifest <- DBI::dbGetQuery(archive, 'SELECT table_name, source_rows, fingerprint FROM "_vpro_access_manifest"')
  if (!all(tables %in% manifest$table_name) || !all(tables %in% DBI::dbListTables(archive))) {
    stop("Access archive lacks a complete eight-table project family: ", project, call. = FALSE)
  }
  version <- DBI::dbGetQuery(archive, 'SELECT description FROM "_table_metadata" WHERE table_name = ?', params = list(paste0(project, "_Env")))
  if (nrow(version) != 1L || is.na(version$description[[1L]]) || version$description[[1L]] != "VP08") {
    stop("Only an Access project with VP08 Env description can be promoted.", call. = FALSE)
  }
  model <- DBI::dbConnect(RSQLite::SQLite(), template$path)
  on.exit(DBI::dbDisconnect(model), add = TRUE)
  for (i in seq_along(tables)) {
    expected <- DBI::dbListFields(model, paste0("Sample_", sub(paste0("^", project, "_"), "", tables[[i]])))
    actual <- DBI::dbListFields(archive, tables[[i]])
    if (!identical(actual, expected)) {
      stop("VP08 field names/order differ from the canonical template: ", tables[[i]], call. = FALSE)
    }
    row <- manifest[manifest$table_name == tables[[i]], , drop = FALSE]
    data <- DBI::dbReadTable(archive, tables[[i]], check.names = FALSE)
    if (nrow(row) != 1L || nrow(data) != row$source_rows[[1L]] || !identical(vpro_access_fingerprint(data), row$fingerprint[[1L]])) {
      stop("Archive manifest does not match project table: ", tables[[i]], call. = FALSE)
    }
  }

  stage <- tempfile("vpro-promote-", tmpdir = dirname(output_path), fileext = ".db")
  on.exit(unlink(stage), add = TRUE)
  DBI::dbExecute(model, "ATTACH DATABASE ? AS imported", params = list(archive_path))
  DBI::dbExecute(model, "ATTACH DATABASE ? AS target", params = list(stage))
  placeholders <- paste(rep("?", length(tables)), collapse = ", ")
  DBI::dbExecute(model, "PRAGMA foreign_keys = ON")
  DBI::dbWithTransaction(model, {
    definitions <- DBI::dbGetQuery(
      model,
      paste0("SELECT name, sql FROM main.sqlite_master WHERE type = 'table' AND name IN (", placeholders, ")"),
      params = as.list(paste0("Sample_", sub(paste0("^", project, "_"), "", tables)))
    )
    for (table in tables) {
      sample <- sub(paste0("^", project, "_"), "Sample_", table)
      sql <- vpro_project_rewrite_schema(definitions$sql[match(sample, definitions$name)], "Sample", project)
      sql <- sub(paste0('^CREATE TABLE ["`]?', table, '["`]?'), paste0('CREATE TABLE target."', table, '"'), sql)
      DBI::dbExecute(model, sql)
    }
    indexes <- DBI::dbGetQuery(
      model,
      paste0("SELECT name, sql FROM main.sqlite_master WHERE type = 'index' AND sql IS NOT NULL AND tbl_name IN (", placeholders, ")"),
      params = as.list(paste0("Sample_", sub(paste0("^", project, "_"), "", tables)))
    )
    for (i in seq_len(nrow(indexes))) {
      name <- vpro_project_rewrite_schema(indexes$name[[i]], "Sample", project)
      sql <- vpro_project_rewrite_schema(indexes$sql[[i]], "Sample", project)
      sql <- sub(paste0('^CREATE (UNIQUE )?INDEX ["`]?', name, '["`]?'), paste0('CREATE \\1INDEX target."', name, '"'), sql)
      DBI::dbExecute(model, sql)
    }
    for (table in tables) {
      DBI::dbExecute(model, paste('INSERT INTO target.', DBI::dbQuoteIdentifier(model, table), 'SELECT * FROM imported.', DBI::dbQuoteIdentifier(model, table)))
    }
    DBI::dbExecute(model, 'CREATE TABLE target._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)')
    DBI::dbExecute(
      model,
      paste0(
        'INSERT INTO target._table_metadata SELECT table_name, description FROM imported._table_metadata WHERE table_name IN (',
        placeholders,
        ')'
      ),
      params = as.list(tables)
    )
    for (table in tables) {
      original <- DBI::dbReadTable(archive, table, check.names = FALSE)
      copied <- DBI::dbGetQuery(model, paste('SELECT * FROM target.', DBI::dbQuoteIdentifier(model, table)))
      if (nrow(original) > 0L) {
        columns <- paste(DBI::dbQuoteIdentifier(model, names(original)), collapse = ", ")
        original <- DBI::dbGetQuery(model, paste('SELECT * FROM imported.', DBI::dbQuoteIdentifier(model, table), 'ORDER BY', columns))
        copied <- DBI::dbGetQuery(model, paste('SELECT * FROM target.', DBI::dbQuoteIdentifier(model, table), 'ORDER BY', columns))
      }
      if (!isTRUE(all.equal(original, copied, check.attributes = FALSE))) {
        stop("VP08 promotion changed field values: ", table, call. = FALSE)
      }
    }
    if (nrow(DBI::dbGetQuery(model, 'PRAGMA target.foreign_key_check')) != 0L) {
      stop("VP08 project violates canonical foreign keys.", call. = FALSE)
    }
  })
  if (DBI::dbGetQuery(model, 'PRAGMA target.integrity_check')[[1L]][[1L]] != "ok") {
    stop("Promoted SQLite project integrity check failed.", call. = FALSE)
  }
  DBI::dbExecute(model, "DETACH DATABASE target")
  if (
    !isTRUE(vpro_project_inspect(stage, project)$compatible) ||
      nrow(vpro_project_compare_schema(stage, project)) != 0L
  ) {
    stop("Promoted SQLite project failed VP08 compatibility checks.", call. = FALSE)
  }
  if (file.exists(output_path) || !file.rename(stage, output_path)) {
    stop("Could not publish promoted project without replacing a file.", call. = FALSE)
  }
  invisible(output_path)
}
