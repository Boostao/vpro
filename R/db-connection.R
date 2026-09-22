# Database connections -----------------------------------------------------

vpro_sqlite_extension <- function(con, install = FALSE) {
  status <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT installed, loaded FROM duckdb_extensions()",
      "WHERE extension_name = 'sqlite_scanner'"
    )
  )

  if (nrow(status) != 1L) {
    stop("DuckDB does not report the sqlite_scanner extension.", call. = FALSE)
  }
  if (!isTRUE(status$installed[[1]]) && !isTRUE(install)) {
    stop(
      "DuckDB's sqlite_scanner extension is not installed. ",
      "Call `vpro_db_connect(install_extensions = TRUE)` once while online.",
      call. = FALSE
    )
  }
  if (!isTRUE(status$installed[[1]])) {
    DBI::dbExecute(con, "INSTALL sqlite_scanner")
  }
  if (!isTRUE(status$loaded[[1]])) {
    DBI::dbExecute(con, "LOAD sqlite_scanner")
  }
  invisible(con)
}

#' Open a VPRO database coordinator
#'
#' VPRO persists data in SQLite files and uses an in-memory DuckDB connection
#' to compose queries across those files.
#'
#' @param install_extensions Allow DuckDB to download `sqlite_scanner` when it
#'   is not already installed.
#'
#' @return A DuckDB DBI connection. Close it with `vpro_db_disconnect()`.
#' @export
vpro_db_connect <- function(install_extensions = getOption("vpro.install_extensions", FALSE)) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  tryCatch(
    {
      vpro_sqlite_extension(con, install = install_extensions)
      con
    },
    error = function(error) {
      DBI::dbDisconnect(con, shutdown = TRUE)
      stop(error)
    }
  )
}

#' Close a VPRO database coordinator
#'
#' @param con A connection created by `vpro_db_connect()`.
#'
#' @return `TRUE`, invisibly, when a connection was closed; otherwise `FALSE`.
#' @export
vpro_db_disconnect <- function(con) {
  if (!DBI::dbIsValid(con)) {
    return(invisible(FALSE))
  }
  DBI::dbDisconnect(con, shutdown = TRUE)
  invisible(TRUE)
}

#' List databases attached to a VPRO coordinator
#'
#' @param con A VPRO DuckDB connection.
#'
#' @return A character vector of database aliases.
#' @export
vpro_db_list <- function(con) {
  DBI::dbGetQuery(con, "SHOW DATABASES")$database_name
}

vpro_db_alias <- function(path) {
  tools::file_path_sans_ext(basename(path))
}

#' Attach SQLite databases to a VPRO coordinator
#'
#' @param con A VPRO DuckDB connection.
#' @param paths SQLite database paths.
#'
#' @return The attached aliases, invisibly.
#' @export
vpro_db_attach <- function(con, paths) {
  paths <- normalizePath(paths, mustWork = FALSE)
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0L) {
    stop("VPRO database files do not exist: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  aliases <- vapply(paths, vpro_db_alias, character(1))
  duplicates <- unique(aliases[duplicated(aliases)])
  if (length(duplicates) > 0L) {
    stop("VPRO database aliases must be unique: ", paste(duplicates, collapse = ", "), call. = FALSE)
  }

  attached <- vpro_db_list(con)
  for (index in seq_along(paths)) {
    alias <- aliases[[index]]
    if (alias %in% attached) {
      next
    }
    statement <- paste(
      "ATTACH",
      DBI::dbQuoteLiteral(con, paths[[index]]),
      "AS",
      DBI::dbQuoteIdentifier(con, alias),
      "(TYPE sqlite)"
    )
    DBI::dbExecute(con, statement)
  }
  invisible(aliases)
}

#' Detach a database from a VPRO coordinator
#'
#' @param con A VPRO DuckDB connection.
#' @param alias Attached database alias.
#'
#' @return The number of affected rows, invisibly.
#' @export
vpro_db_detach <- function(con, alias) {
  result <- DBI::dbExecute(
    con,
    paste("DETACH", DBI::dbQuoteIdentifier(con, alias))
  )
  invisible(result)
}

#' Construct a path to a VPRO database
#'
#' @param database Database name without an extension.
#' @param ... Optional subdirectories, such as `"projects"`.
#' @param root VPRO user data directory.
#' @param extension Database file extension.
#'
#' @return A character vector of paths.
#' @export
vpro_db_path <- function(database, ..., root = vpro_data_dir(), extension = "db") {
  file.path(root, ..., paste0(database, ".", extension))
}
