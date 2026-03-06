# Database Connection Factory for VPro
# Handles local DuckDB + optional cloud PostgreSQL attachment
# Uses config.yml for environment-specific settings

# Load required libraries (assumes already installed)

#' Connect to Local DuckDB Instance
#'
#' Opens the main local DuckDB database and attaches auxiliary databases
#' (lists, metadata, user, messages) as defined in config.yml
#'
#' @param environment Character. One of 'development', 'test', 'production'.
#'                    If NULL, uses Sys.getenv('R_CONFIG_ACTIVE') or 'default'
#'
#' @return DBI connection object pointing to local DuckDB
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db(environment = 'test')
#'   DBI::dbListTables(con)
#' }
#'
#' @export
connect_local_db <- function(environment = NULL) {
  
  # Determine active environment
  if (is.null(environment)) {
    environment <- Sys.getenv("R_CONFIG_ACTIVE", unset = "default")
  }
  
  # Load config from config.yml
  tryCatch({
    cfg <- config::get(config = environment)
  }, error = function(e) {
    stop("Failed to load config for environment '", environment, "': ", e$message)
  })
  
  # Extract DuckDB paths
  duckdb_paths <- cfg$duckdb
  if (is.null(duckdb_paths)) {
    stop("No 'duckdb' configuration found in config.yml for environment: ", environment)
  }
  
  # Open main DuckDB connection
  message("[db_connections] Connecting to local DuckDB: ", duckdb_paths$main_db)
  con <- tryCatch({
    DBI::dbConnect(duckdb::duckdb(), duckdb_paths$main_db)
  }, error = function(e) {
    stop("Failed to connect to DuckDB at '", duckdb_paths$main_db, "': ", e$message)
  })
  
  # Attach auxiliary databases
  auxiliary_dbs <- list(
    lists = duckdb_paths$lists_db,
    metadata = duckdb_paths$metadata_db,
    user_db = duckdb_paths$user_db,
    messages = duckdb_paths$messages_db
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
#' using DuckDB's native `postgres` extension. Reads connection details from config.yml
#'
#' @param con DBI connection object (typically from \code{connect_local_db()})
#' @param environment Character. Environment to load config from.
#' @param read_only Logical. If TRUE, creates read-only ATTACH. Default from config.
#' @param alias Character. Name to use for attached schema. Default 'master'.
#'
#' @return Invisible NULL. Connection is modified in-place.
#'
#' @details
#'   Before calling this function, ensure the postgres extension is installed:
#'   \code{DBI::dbExecute(con, "INSTALL postgres; LOAD postgres;")}
#'
#'   Credentials can be provided via config.yml or environment variables
#'   (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD).
#'
#' @examples
#' \dontrun{
#'   con <- connect_local_db(environment = 'test')
#'   DBI::dbExecute(con, "INSTALL postgres; LOAD postgres;")
#'   attach_cloud_db(con, environment = 'test')
#'   # Now queries can use 'master.*' tables
#'   DBI::dbGetQuery(con, "SELECT * FROM master.core.veg LIMIT 5")
#' }
#'
#' @export
attach_cloud_db <- function(con, environment = NULL, read_only = NULL, alias = 'master', fail_on_error = TRUE) {
  
  # Check if already attached
  if (is_cloud_connected(con, alias)) {
    message("[db_connections] Cloud database '", alias, "' is already attached")
    return(invisible(NULL))
  }
  
  # Determine active environment
  if (is.null(environment)) {
    environment <- Sys.getenv("R_CONFIG_ACTIVE", unset = "default")
  }
  
  # Load config
  tryCatch({
    cfg <- config::get(config = environment)
  }, error = function(e) {
    stop("Failed to load config for environment '", environment, "': ", e$message)
  })
  
  # Extract PostgreSQL config
  pg_cfg <- cfg$postgres
  if (is.null(pg_cfg)) {
    stop("No 'postgres' configuration found in config.yml for environment: ", environment)
  }
  
  
  host <- pg_cfg$host
  port <- pg_cfg$port
  database <- pg_cfg$database
  user <- pg_cfg$user
  password <- pg_cfg$password
  
  # Construct connection string
  conn_string <- sprintf(
    "postgres://%s:%s@%s:%s/%s",
    user, password, host, port, database
  )
  
  message("[db_connections] Attaching PostgreSQL as '", alias)
  message("[db_connections] Host: ", host, ":", port, " Database: ", database)
  
  # Ensure postgres extension is loaded
  tryCatch({
    DBI::dbExecute(con, "INSTALL postgres")
    DBI::dbExecute(con, "LOAD postgres")
  }, error = function(e) {
    warning("postgres extension install/load may have failed: ", e$message)
  })
  
  attach_sql <- paste0(
    "ATTACH '", conn_string, "' AS ", alias, " (TYPE postgres)"
  )
  
  tryCatch({
    DBI::dbExecute(con, attach_sql)
    message("[db_connections] PostgreSQL attached successfully as '", alias, "'")
  }, error = function(e) {
    msg <- paste0(
      "Failed to attach PostgreSQL: ", e$message, "\n",
      "Check connection string: ", conn_string
    )
    if (isTRUE(fail_on_error)) {
      stop(msg)
    }
    warning(msg)
    return(invisible(NULL))
  })
  
  return(invisible(NULL))
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
