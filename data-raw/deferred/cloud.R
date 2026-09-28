# Deferred optional PostgreSQL client feature; not sourced by VPRO or the app.
# Revisit connection ownership, credential handling and tests after Access parity.

.pg_host <- function() Sys.getenv("PGHOST", "localhost")
.pg_port <- function() as.integer(Sys.getenv("PGPORT", "5433"))
.pg_database <- function() Sys.getenv("PGDATABASE", "becmaster")

is_cloud_connected <- function(con, alias = "master") {
  alias <- as.character(DBI::dbQuoteIdentifier(con, alias))
  tryCatch({
    DBI::dbGetQuery(con, paste0("SELECT 1 FROM ", alias, ".information_schema.tables LIMIT 1"))
    TRUE
  }, error = function(e) FALSE)
}

attach_cloud_db <- function(con, pg_user, pg_password = NULL, alias = "master", fail_on_error = TRUE) {
  if (is_cloud_connected(con, alias)) {
    return(invisible(NULL))
  }
  host <- .pg_host()
  port <- .pg_port()
  database <- .pg_database()
  if (is.null(pg_password) || !nzchar(pg_password)) {
    conn_string <- sprintf("postgres://%s@%s:%s/%s", pg_user, host, port, database)
  } else {
    conn_string <- sprintf("postgres://%s:%s@%s:%s/%s", pg_user, pg_password, host, port, database)
  }
  # Extension provisioning occurs only when this deferred function is invoked.
  DBI::dbExecute(con, "INSTALL postgres")
  DBI::dbExecute(con, "LOAD postgres")
  statement <- paste("ATTACH", DBI::dbQuoteLiteral(con, conn_string), "AS", DBI::dbQuoteIdentifier(con, alias), "(TYPE postgres)")
  tryCatch(DBI::dbExecute(con, statement), error = function(e) {
    if (isTRUE(fail_on_error)) stop(e)
    warning(conditionMessage(e), call. = FALSE)
    invisible(NULL)
  })
  invisible(NULL)
}

attach_cloud <- function(con, alias = "master", fail_on_error = TRUE) {
  pg_user <- Sys.getenv("VPRO_PG_APP_USER", "vpro_app")
  pg_pass <- Sys.getenv("VPRO_PG_APP_PASSWORD", "")
  if (!nzchar(pg_pass)) stop("VPRO_PG_APP_PASSWORD env var is not set", call. = FALSE)
  attach_cloud_db(con, pg_user, pg_pass, alias, fail_on_error)
}
