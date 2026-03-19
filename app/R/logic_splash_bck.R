# Logic: Splash / application startup bootstrap

vpro_runtime_paths <- function(root = getwd()) {
  list(
    root = normalizePath(root, mustWork = FALSE),
    vpro64 = normalizePath(file.path(root, "data", "VPro64.db"), mustWork = FALSE)
  )
}

vpro_list_runtime_databases <- function(con) {
  tryCatch({
    DBI::dbGetQuery(
      con,
      "SELECT database_name, type, path FROM duckdb_databases() ORDER BY database_name"
    )
  }, error = function(e) {
    data.frame(
      database_name = character(0),
      type = character(0),
      path = character(0),
      stringsAsFactors = FALSE
    )
  })
}

vpro_close_runtime <- function(runtime) {
  con <- NULL

  if (inherits(runtime, "DuckDBConnection")) {
    con <- runtime
  } else if (is.list(runtime) && !is.null(runtime$con)) {
    con <- runtime$con
  }

  if (is.null(con)) {
    return(invisible(NULL))
  }

  tryCatch({
    DBI::dbDisconnect(con, shutdown = TRUE)
  }, error = function(e) {
    invisible(NULL)
  })

  invisible(NULL)
}

vpro_init_runtime <- function(root = getwd()) {
  paths <- vpro_runtime_paths(root)

  if (!file.exists(paths$vpro64)) {
    stop("Canonical VPro64 database not found: ", paths$vpro64)
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")

  tryCatch({
    DBI::dbExecute(con, "INSTALL sqlite")
  }, error = function(e) {
    log_msg("[logic_splash] sqlite INSTALL skipped: ", conditionMessage(e))
  })

  tryCatch({
    DBI::dbExecute(con, "LOAD sqlite")
  }, error = function(e) {
    vpro_close_runtime(con)
    stop("Failed to load DuckDB sqlite extension: ", conditionMessage(e))
  })

  tryCatch({
    DBI::dbExecute(
      con,
      paste0(
        "ATTACH ",
        DBI::dbQuoteString(con, paths$vpro64),
        " AS vpro (TYPE sqlite)"
      )
    )
  }, error = function(e) {
    vpro_close_runtime(con)
    stop("Failed to attach canonical VPro64.db: ", conditionMessage(e))
  })

  structure(
    list(
      con = con,
      paths = paths,
      attached = vpro_list_runtime_databases(con),
      initialized_at = Sys.time()
    ),
    class = "vpro_runtime"
  )
}

get_vpro_runtime_connection <- function(runtime = NULL) {
  if (is.null(runtime) && exists("VPRO_GLOBAL_RUNTIME", inherits = TRUE)) {
    runtime <- get("VPRO_GLOBAL_RUNTIME", inherits = TRUE)
  }

  if (is.list(runtime) && !is.null(runtime$con)) {
    return(runtime$con)
  }

  NULL
}

run_splash_init <- function(runtime = NULL) {
  con <- get_vpro_runtime_connection(runtime)

  if (is.null(con)) {
    stop("Global VPro runtime is not initialized.")
  }

  structure(
    list(
      application_options = list(
        perform_name_autocorrect = FALSE
      ),
      attached_databases = vpro_list_runtime_databases(con),
      stop_before = c("LogVProOn", "frmWhatsNew"),
      handoff_to_server = c("audit_logon", "whats_new")
    ),
    class = "vpro_splash_init"
  )
}