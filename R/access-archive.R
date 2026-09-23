# Access source archival ----------------------------------------------------

vpro_access_source <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("VPRO Access source must be an existing file.", call. = FALSE)
  }
  normalizePath(path, mustWork = TRUE)
}

vpro_access_output <- function(path, sources) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("VPRO SQLite output must be one file path.", call. = FALSE)
  }
  path <- normalizePath(path, mustWork = FALSE)
  if (file.exists(path) || path %in% sources || !dir.exists(dirname(path))) {
    stop("VPRO SQLite output must be unused, outside source files, and in an existing directory.", call. = FALSE)
  }
  path
}

vpro_access_description <- function(path, table) {
  properties <- tryCatch(mdbr::mdb_prop(path, name = table), error = identity)
  if (inherits(properties, "error")) {
    stop("Could not inspect Access table description for ", table, ": ", conditionMessage(properties), call. = FALSE)
  }
  table_properties <- properties[[table]][["(none)"]]
  description <- if ("Description" %in% names(table_properties)) table_properties[["Description"]] else NULL
  if (is.null(description) || length(description) == 0L || is.na(description[[1L]])) {
    return(NA_character_)
  }
  as.character(description[[1L]])
}

vpro_access_tables <- function(path) {
  tables <- mdbr::mdb_tables(path, type = "table")
  links <- mdbr::mdb_tables(path, type = "linkedtable")
  if (
    length(intersect(tables, links)) ||
      anyDuplicated(tables) ||
      anyDuplicated(links) ||
      any(tables %in% c("_table_metadata", "_vpro_access_manifest", "_vpro_access_source", "_vpro_access_links", "_vpro_access_columns"))
  ) {
    stop("Access table names conflict with archive metadata or linked-table inventory.", call. = FALSE)
  }
  list(tables = tables, links = links)
}

#' Inspect local Access tables before conversion
#'
#' Lists all local tables, counts and Access table descriptions using `mdbr`.
#' Linked tables are reported separately, never followed automatically.
#' A missing Description is not interpreted as VP08. No files are written.
#'
#' @param source_path Explicit Access `.mdb` or `.accdb` file.
#' @return List with `tables` (`table_name`, `rows`, `description`), `links`,
#'   and `source_path`.
#' @export
vpro_access_inspect <- function(source_path) {
  source_path <- vpro_access_source(source_path)
  inventory <- vpro_access_tables(source_path)
  tables <- data.frame(
    table_name = inventory$tables,
    rows = vapply(inventory$tables, \(table) as.numeric(mdbr::mdb_count(source_path, table)), numeric(1)),
    description = vapply(inventory$tables, \(table) vpro_access_description(source_path, table), character(1))
  )
  list(source_path = source_path, tables = tables, links = inventory$links)
}

vpro_access_column_type <- function(column) {
  if (inherits(column, "POSIXt") || inherits(column, "Date")) {
    return("TEXT")
  }
  if (is.list(column) && all(vapply(column, \(x) is.raw(x) || is.null(x), logical(1)))) {
    return("BLOB")
  }
  if (is.logical(column) || is.integer(column)) {
    return("INTEGER")
  }
  if (is.numeric(column)) {
    return("REAL")
  }
  if (is.character(column)) {
    return("TEXT")
  }
  stop("Access column has an unsupported R type: ", paste(class(column), collapse = "/"), call. = FALSE)
}

vpro_access_normalize_column <- function(column) {
  if (inherits(column, "POSIXt")) {
    result <- rep(NA_character_, length(column))
    present <- !is.na(column)
    result[present] <- format(column[present], "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
    return(result)
  }
  if (inherits(column, "Date")) {
    return(as.character(column))
  }
  if (is.logical(column)) {
    return(as.integer(column))
  }
  column
}

vpro_access_fingerprint_stream <- function(con, table, batch_rows = 1000L) {
  path <- tempfile("vpro-fingerprint-")
  on.exit(unlink(path), add = TRUE)
  output <- file(path, "wb")
  on.exit(try(close(output), silent = TRUE), add = TRUE)
  result <- DBI::dbSendQuery(con, paste("SELECT * FROM", DBI::dbQuoteIdentifier(con, table), "ORDER BY rowid"))
  on.exit(if (DBI::dbIsValid(result)) DBI::dbClearResult(result), add = TRUE)
  repeat {
    chunk <- DBI::dbFetch(result, n = batch_rows)
    # Include the zero-row prototype so empty tables still bind field names and types.
    writeBin(serialize(chunk, NULL, version = 3L), output)
    if (nrow(chunk) < batch_rows) break
  }
  close(output)
  unname(tools::md5sum(path))
}

vpro_access_archive_table <- function(source, target, table, expected_rows, max_table_bytes, batch_rows) {
  cursor <- mdbr::mdb_stream_table(source, table)
  on.exit(DBI::dbClearResult(cursor), add = TRUE)
  prototype <- DBI::dbFetch(cursor, n = 0L)
  if (anyDuplicated(names(prototype)) || length(names(prototype)) == 0L) {
    stop("Access table has duplicate or missing field names: ", table, call. = FALSE)
  }
  types <- vapply(prototype, vpro_access_column_type, character(1))
  columns <- paste(paste(DBI::dbQuoteIdentifier(target, names(prototype)), types), collapse = ", ")
  quoted <- DBI::dbQuoteIdentifier(target, table)
  DBI::dbExecute(target, paste("CREATE TABLE", quoted, paste0("(", columns, ")")))
  rows <- 0
  repeat {
    data <- DBI::dbFetch(cursor, n = batch_rows)
    if (as.numeric(utils::object.size(data)) > max_table_bytes) {
      stop("Access batch exceeds the materialized batch size limit: ", table, call. = FALSE)
    }
    if (!identical(names(data), names(prototype)) || rows + nrow(data) > expected_rows) {
      stop("Access table row count or field names changed during extraction: ", table, call. = FALSE)
    }
    if (nrow(data) == 0L) break
    data[] <- lapply(data, vpro_access_normalize_column)
    DBI::dbAppendTable(target, table, data)
    stored <- DBI::dbGetQuery(target, paste("SELECT * FROM", quoted, "WHERE rowid > ? ORDER BY rowid LIMIT ?"), params = list(rows, nrow(data)))
    if (!identical(names(stored), names(data)) || nrow(stored) != nrow(data) || !isTRUE(all.equal(stored, data, check.attributes = FALSE))) {
      stop("Access table values did not round-trip through SQLite: ", table, call. = FALSE)
    }
    rows <- rows + nrow(data)
  }
  if (rows != expected_rows) {
    stop("Access table row count changed during extraction: ", table, call. = FALSE)
  }
  vpro_access_fingerprint_stream(target, table)
}

#' Archive all readable local Access tables to SQLite
#'
#' Creates a new archival SQLite database; it does not perform historical
#' upgrades or label a family as VP08. Preserves fields, nulls, data rows and
#' translated Access table descriptions in `_table_metadata`; a separate
#' `_vpro_access_manifest` records counts and chunked data fingerprints. Linked
#' tables are recorded but never followed. Extraction and verification hold
#' bounded batches; no existing output or Access source is modified, and staging is
#' removed on failure.
#'
#' @param source_path Explicit Access `.mdb` or `.accdb` source file.
#' @param output_path Unused SQLite destination in an existing directory.
#' @param max_rows_per_table Optional maximum rows in each source table; `Inf`
#'   (the default) permits large tables.
#' @param max_source_bytes Optional maximum Access source size; `Inf` by default.
#' @param max_table_bytes Maximum R size of each extracted batch, checked after
#'   fetching and before copying into SQLite; cannot cap allocation within `mdbr`.
#' @param batch_rows Positive number of rows fetched per batch.
#' @return An invisible inventory with archive path, table results and links.
#' @export
vpro_access_archive <- function(
  source_path,
  output_path,
  max_rows_per_table = Inf,
  max_source_bytes = Inf,
  max_table_bytes = 2e8,
  batch_rows = 1000L
) {
  source_path <- vpro_access_source(source_path)
  output_path <- vpro_access_output(output_path, source_path)
  if (
    !is.numeric(max_rows_per_table) ||
      length(max_rows_per_table) != 1L ||
      is.na(max_rows_per_table) ||
      max_rows_per_table < 0 ||
      max_rows_per_table != floor(max_rows_per_table)
  ) {
    stop("`max_rows_per_table` must be a nonnegative whole number or Inf.", call. = FALSE)
  }
  if (!is.numeric(batch_rows) || length(batch_rows) != 1L || is.na(batch_rows) || !is.finite(batch_rows) || batch_rows < 1 || batch_rows != floor(batch_rows) || batch_rows > .Machine$integer.max) {
    stop("`batch_rows` must be a positive whole number within the integer range.", call. = FALSE)
  }
  byte_limits <- list(max_source_bytes = max_source_bytes, max_table_bytes = max_table_bytes)
  for (limit in names(byte_limits)) {
    value <- byte_limits[[limit]]
    if (!is.numeric(value) || length(value) != 1L || is.na(value) || value < 0 || (limit == "max_table_bytes" && !is.finite(value))) {
      stop("`", limit, "` must be a nonnegative byte count", if (limit == "max_table_bytes") " with a finite value." else " or Inf.", call. = FALSE)
    }
  }
  source_bytes <- file.info(source_path)$size
  if (is.na(source_bytes) || source_bytes > max_source_bytes) {
    stop("Access source exceeds the source file size limit.", call. = FALSE)
  }
  inventory <- vpro_access_inspect(source_path)
  too_large <- inventory$tables$table_name[inventory$tables$rows > max_rows_per_table]
  if (length(too_large)) {
    stop("Access tables exceed the per-table in-memory row limit: ", paste(too_large, collapse = ", "), call. = FALSE)
  }
  stage <- tempfile("vpro-access-", tmpdir = dirname(output_path), fileext = ".db")
  on.exit(unlink(stage), add = TRUE)
  if (utils::packageVersion("mdbr") < "0.3.2") {
    stop("VPRO Access archival requires mdbr 0.3.2 or later for streaming.", call. = FALSE)
  }
  source <- DBI::dbConnect(mdbr::mdb(), source_path)
  on.exit(DBI::dbDisconnect(source), add = TRUE)
  target <- DBI::dbConnect(RSQLite::SQLite(), stage)
  on.exit(if (DBI::dbIsValid(target)) DBI::dbDisconnect(target), add = TRUE)
  hashes <- character(nrow(inventory$tables))
  DBI::dbWithTransaction(target, {
    for (i in seq_len(nrow(inventory$tables))) {
      hashes[[i]] <- vpro_access_archive_table(
        source, target, inventory$tables$table_name[[i]], inventory$tables$rows[[i]], max_table_bytes, as.integer(batch_rows)
      )
    }
    DBI::dbExecute(target, 'CREATE TABLE "_table_metadata" (table_name TEXT PRIMARY KEY, description TEXT)')
    DBI::dbAppendTable(target, "_table_metadata", inventory$tables[, c("table_name", "description"), drop = FALSE])
    DBI::dbExecute(
      target,
      paste(
        'CREATE TABLE "_vpro_access_manifest"',
        '(table_name TEXT PRIMARY KEY, source_rows INTEGER, fingerprint TEXT)'
      )
    )
    DBI::dbAppendTable(
      target,
      "_vpro_access_manifest",
      data.frame(
        table_name = inventory$tables$table_name,
        source_rows = inventory$tables$rows,
        fingerprint = hashes
      )
    )
    DBI::dbExecute(
      target,
      paste(
        'CREATE TABLE "_vpro_access_source"',
        '(source_path TEXT NOT NULL, source_md5 TEXT NOT NULL, archived_at TEXT NOT NULL)'
      )
    )
    DBI::dbExecute(
      target,
      'INSERT INTO "_vpro_access_source" VALUES (?, ?, ?)',
      params = list(source_path, unname(tools::md5sum(source_path)), format(Sys.time(), "%Y-%m-%d %H:%M:%OS6", tz = "UTC"))
    )
    DBI::dbExecute(target, 'CREATE TABLE "_vpro_access_links" (table_name TEXT PRIMARY KEY)')
    if (length(inventory$links)) {
      DBI::dbAppendTable(target, "_vpro_access_links", data.frame(table_name = inventory$links))
    }
    DBI::dbExecute(
      target,
      paste(
        'CREATE TABLE "_vpro_access_columns"',
        '(table_name TEXT NOT NULL, field_name TEXT NOT NULL, ordinal INTEGER NOT NULL, sqlite_type TEXT NOT NULL)'
      )
    )
    for (table in inventory$tables$table_name) {
      fields <- DBI::dbGetQuery(target, paste0('PRAGMA table_info(', DBI::dbQuoteString(target, table), ')'))
      DBI::dbAppendTable(
        target,
        "_vpro_access_columns",
        data.frame(
          table_name = table,
          field_name = fields$name,
          ordinal = fields$cid,
          sqlite_type = fields$type
        )
      )
    }
  })
  if (!identical(unname(tools::md5sum(source_path)), unname(DBI::dbGetQuery(target, 'SELECT source_md5 FROM "_vpro_access_source"')$source_md5[[1L]]))) {
    stop("Access source changed during archival extraction.", call. = FALSE)
  }
  if (DBI::dbGetQuery(target, "PRAGMA integrity_check")[[1L]][[1L]] != "ok") {
    stop("SQLite archive integrity check failed.", call. = FALSE)
  }
  DBI::dbDisconnect(target)
  if (file.exists(output_path) || !file.rename(stage, output_path)) {
    stop("Could not publish the VPRO Access archive without replacing a file.", call. = FALSE)
  }
  inventory$archive_path <- output_path
  inventory$tables$fingerprint <- hashes
  invisible(inventory)
}
