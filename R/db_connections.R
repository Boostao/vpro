# Database Connection Factory for VPro
# Handles local DuckDB + optional cloud PostgreSQL attachment
# Connection settings come from environment variables; no config.yml required.

# Internal helpers — read standard PG env vars with app defaults
.pg_host     <- function() Sys.getenv("PGHOST",     "localhost")
.pg_port     <- function() as.integer(Sys.getenv("PGPORT",     "5433"))
.pg_database <- function() Sys.getenv("PGDATABASE", "becmaster")

#' Connect to Local DuckDB Instance
#'
#' Opens the main local DuckDB database and attaches auxiliary databases
#' (lists, metadata, user, messages).  Paths are read from env vars with
#' hardcoded defaults so the function requires no arguments.
#'
#' @return DBI connection object pointing to local DuckDB
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   DBI::dbListTables(con)
#' }
#'
#' @export
connect_local_db <- function() {
  main_db     <- Sys.getenv("VPRO_MAIN_DB",     "data/vpro.duckdb")
  lists_db    <- Sys.getenv("VPRO_LISTS_DB",    "data/vpro_lists.duckdb")
  metadata_db <- Sys.getenv("VPRO_METADATA_DB", "data/vpro_metadata.duckdb")
  user_db     <- Sys.getenv("VPRO_USER_DB",     "data/vpro_user.duckdb")
  messages_db <- Sys.getenv("VPRO_MESSAGES_DB", "data/vpro_messages.duckdb")

  message("[db_connections] Connecting to local DuckDB: ", main_db)
  con <- tryCatch({
    DBI::dbConnect(duckdb::duckdb(), main_db)
  }, error = function(e) {
    stop("Failed to connect to DuckDB at '", main_db, "': ", e$message)
  })

  auxiliary_dbs <- list(
    lists    = lists_db,
    metadata = metadata_db,
    user_db  = user_db,
    messages = messages_db
  )

  for (alias in names(auxiliary_dbs)) {
    db_path <- auxiliary_dbs[[alias]]
    if (!is.null(db_path)) {
      message("[db_connections] Attaching ", alias, " -> ", db_path)
      tryCatch({
        DBI::dbExecute(con, paste0("ATTACH '", db_path, "' AS ", alias))
      }, error = function(e) {
        warning("Failed to attach auxiliary DB '", alias, "': ", e$message)
      })
    }
  }

  message("[db_connections] Local DuckDB connection established")
  return(con)
}

#' Connect to Cloud PostgreSQL via DuckDB postgres Extension
#'
#' Attaches a remote PostgreSQL database to an existing DuckDB connection
#' using DuckDB's native `postgres` extension.  Host/port/database are read
#' from env vars (PGHOST, PGPORT, PGDATABASE); credentials are passed explicitly.
#'
#' @param con         DBI connection object (from \code{connect_local_db()})
#' @param pg_user     Character. PostgreSQL role name.
#' @param pg_password Character or NULL. Password; omitted for trust-auth roles.
#' @param alias       Character. Catalog alias. Default 'master'.
#' @param fail_on_error Logical. Stop on attach failure. Default TRUE.
#'
#' @return Invisible NULL. Connection is modified in-place.
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   attach_cloud_db(con, pg_user = "vpro_default")
#'   DBI::dbGetQuery(con, "SELECT * FROM master.core.veg LIMIT 5")
#' }
#'
#' @export
attach_cloud_db <- function(con, pg_user, pg_password = NULL, alias = "master",
                            fail_on_error = TRUE) {

  if (is_cloud_connected(con, alias)) {
    message("[db_connections] Cloud database '", alias, "' is already attached")
    return(invisible(NULL))
  }

  host     <- .pg_host()
  port     <- .pg_port()
  database <- .pg_database()

  if (is.null(pg_password) || !nzchar(pg_password %||% "")) {
    conn_string <- sprintf("postgres://%s@%s:%s/%s", pg_user, host, port, database)
  } else {
    conn_string <- sprintf("postgres://%s:%s@%s:%s/%s", pg_user, pg_password, host, port, database)
  }

  message("[db_connections] Attaching PostgreSQL as '", alias, "' (user: ", pg_user, ")")

  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
  }, error = function(e) {
    warning("postgres extension install/load may have failed: ", e$message)
  })

  attach_sql <- paste0("ATTACH '", conn_string, "' AS ", alias, " (TYPE postgres)")

  tryCatch({
    DBI::dbExecute(con, attach_sql)
    message("[db_connections] PostgreSQL attached successfully as '", alias, "'")
  }, error = function(e) {
    msg <- paste0("Failed to attach PostgreSQL as '", pg_user, "': ", e$message)
    if (isTRUE(fail_on_error)) stop(msg)
    warning(msg)
    return(invisible(NULL))
  })

  return(invisible(NULL))
}

#' Attach cloud PostgreSQL as the application role (vpro_app)
#'
#' User/password read from VPRO_PG_APP_USER (default "vpro_app") and
#' VPRO_PG_APP_PASSWORD env vars.  Stops if VPRO_PG_APP_PASSWORD is not set.
#' All authentication (guest vs admin) is handled at the R level via admin.users.
#'
#' @param con           DuckDB connection.
#' @param alias         Catalog alias. Default "master".
#' @param fail_on_error Logical. Stop on attach failure. Default TRUE.
#' @return Invisible NULL.
#' @export
attach_cloud <- function(con, alias = "master", fail_on_error = TRUE) {
  pg_user <- Sys.getenv("VPRO_PG_APP_USER", "vpro_app")
  pg_pass <- Sys.getenv("VPRO_PG_APP_PASSWORD", "")
  if (!nzchar(pg_pass)) stop("VPRO_PG_APP_PASSWORD env var is not set")
  attach_cloud_db(con, pg_user = pg_user, pg_password = pg_pass,
                  alias = alias, fail_on_error = fail_on_error)
}

#' Check if Cloud Database is Connected
#'
#' Tests whether the PostgreSQL cloud database is currently attached
#' to the DuckDB connection
#'
#' @param con DBI connection object
#' @param alias Character. Name of the attached schema. Default 'master'.
#'
#' @return Logical. TRUE if alias is attached and queryable, FALSE otherwise.
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   attach_cloud_db(con)
#'   is_cloud_connected(con)  # TRUE
#' }
#'
#' @export
is_cloud_connected <- function(con, alias = 'master') {
  tryCatch({
    result <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM ", alias, ".information_schema.tables LIMIT 1"))
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get List of Attached Databases
#'
#' Returns names of all currently attached databases in a DuckDB connection
#'
#' @param con DBI connection object
#'
#' @return Character vector of database aliases (e.g., 'lists', 'metadata', 'master')
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   list_attached_dbs(con)  # c("lists", "metadata", "user_db", "messages")
#' }
#'
#' @export
list_attached_dbs <- function(con) {
  tryCatch({
    result <- DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases() WHERE database_name != 'memory'")
    return(result$database_name)
  }, error = function(e) {
    warning("Failed to list attached databases: ", e$message)
    return(character(0))
  })
}

#' Detach Database
#'
#' Safely detaches an auxiliary database from the DuckDB connection
#'
#' @param con DBI connection object
#' @param alias Character. Name of the database to detach.
#'
#' @return Invisible NULL
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   detach_db(con, 'master')
#' }
#'
#' @export
detach_db <- function(con, alias) {
  tryCatch({
    DBI::dbExecute(con, paste0("DETACH ", alias))
    message("[db_connections] Detached database: ", alias)
  }, error = function(e) {
    warning("Failed to detach database '", alias, "': ", e$message)
  })
  return(invisible(NULL))
}

#' Close Database Connection
#'
#' Safely closes a DuckDB connection. Detaches all attached databases first.
#'
#' @param con DBI connection object
#'
#' @return Invisible NULL
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   # ... do work ...
#'   close_db(con)
#' }
#'
#' @export
close_db <- function(con) {
  # Detach all attached databases before closing
  attached_dbs <- list_attached_dbs(con)
  # Filter out the main database (usually named "main" or "memory")
  attached_dbs <- attached_dbs[!attached_dbs %in% c("vpro", "memory", "temp", "system")]
  
  if (length(attached_dbs) > 0) {
    message("[db_connections] Detaching ", length(attached_dbs), " database(s): ", paste(attached_dbs, collapse = ", "))
    for (db in attached_dbs) {
      detach_db(con, db)
    }
  }
  
  tryCatch({
    DBI::dbDisconnect(con, shutdown = TRUE)
    message("[db_connections] Database connection closed")
  }, error = function(e) {
    warning("Error closing database: ", e$message)
  })
  return(invisible(NULL))
}

#' Execute Raw SQL Query with Error Handling
#'
#' Execute a raw SQL query with formatted error messages
#'
#' @param con DBI connection object
#' @param sql Character. SQL query string.
#' @param params List. Named list of parameters for parameterized queries (if applicable).
#'
#' @return Result from \code{DBI::dbGetQuery()} or message on success for non-SELECT
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db()
#'   query_db(con, "SELECT COUNT(*) FROM lists.spplist")
#' }
#'
#' @export
query_db <- function(con, sql, params = NULL) {
  tryCatch({
    if (grepl("^\\s*(SELECT|WITH)", sql, ignore.case = TRUE)) {
      return(DBI::dbGetQuery(con, sql))
    } else {
      DBI::dbExecute(con, sql)
      return(invisible(NULL))
    }
  }, error = function(e) {
    stop("Database query failed:\n", sql, "\n\nError: ", e$message)
  })
}

# Helper: %||% null coalescing operator
`%||%` <- function(x, y) if (is.null(x)) y else x
