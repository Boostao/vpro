#### --- Config management ---

# Note : Tested caching the config but platform so fast and yaml so tiny that reading
# it every time is not a problem. Settled on in memory plus write on changes should
# reduce read I/O. Will not support hot reload of config, restart the app.
config_init <- function(conf = Sys.getenv("VPRO_CONFIG_FILE", "config.yml")) {
  cfg <- yaml::read_yaml(conf, readLines.warn = FALSE)
  function(section, key, value) {
    if (missing(section)) {
      return(cfg)
    }
    if (missing(key)) {
      return(cfg[[section]])
    }
    if (missing(value)) {
      return(cfg[[section]][[key]])
    }
    cfg[[section]][[key]] <<- value
    yaml::write_yaml(cfg, conf)
    invisible(cfg[[section]][[key]])
  }
}

config <- config_init()

#### --- Local Database helpers ---

db_con <- function(db = ":memory:") {
  con <- DBI::dbConnect(duckdb::duckdb(), db)
  # Check if sqlite_scanner extension is installed, if not install and load it. This is required for attaching sqlite databases.
  res <- DBI::dbGetQuery(con, "SELECT installed FROM duckdb_extensions() WHERE extension_name IN ('sqlite_scanner');")
  if (isFALSE(res$installed)) {
    DBI::dbExecute(con, "INSTALL sqlite_scanner;")
    DBI::dbExecute(con, "LOAD sqlite_scanner;")
  }
  con
}

db_close <- function(con) {
  DBI::dbDisconnect(con)
}

db_id <- function(tb, db = NULL, prj = FALSE) {
  if (prj) {
    tb <- sprintf("%s_%s", db, tb)
  }
  DBI::Id(db, tb)
}

db_tb <- function(con, tb, db = NULL, prj = FALSE) {
  DBI::dbQuoteIdentifier(con, db_id(tb, db, prj))
}

db_path <- function(..., db, loc = config("System", "Location"), ext = "db") {
  file.path(loc, "data", ..., paste0(db, ".", ext)) |> unique()
}

# No table description concept in duckdb, so we hash the entire table to detect changes.
db_hash <- function(con, tb, db = NULL, prj = FALSE) {
  q <- sprintf(
    "SELECT bit_xor(hash(*columns(*)))::VARCHAR AS h FROM %s;",
    db_tb(con, tb, db, prj)
  )
  result <- DBI::dbGetQuery(con, q)
  result$h
}

db_list_attached <- function(con) {
  DBI::dbGetQuery(con, "SHOW databases;")$database_name
}

db_attach <- function(con, db) {
  # Check if databases files exist before trying to attach them, error handling if they don't exist
  exist_d <- db[file.exists(db)]
  miss_d <- setdiff(db, db)
  if (length(miss_d) > 0) {
    stop(
      "Missing databases detected.\nThe following databases were expected but not found: [",
      paste0(miss_d, collapse = ", "),
      "]\nPlease check that the expected databases are in place and try again."
    )
  }
  # Check for already attached databases
  atta_db <- db_list_attached(con)
  # Attach databases
  for (d in exist_d) {
    if (
      {
        d |> basename() |> tools::file_path_sans_ext()
      } %in%
        atta_db
    ) {
      next
    }
    DBI::dbExecute(con, sprintf("ATTACH %s (TYPE sqlite);", DBI::dbQuoteLiteral(con, d)))
  }
}

db_detach <- function(con, alias) {
  DBI::dbExecute(con, sprintf("DETACH %s;", DBI::dbQuoteIdentifier(con, alias)))
}

db_query <- function(con, q, ...) {
  DBI::dbGetQuery(con, q, ...)
}

db_run <- function(con, q, ...) {
  DBI::dbExecute(con, q, ...)
}

db_insert <- function(con, tb, ..., db = NULL, prj = FALSE) {
  DBI::dbAppendTable(con, db_id(tb, db, prj), data.frame(...))
}

db_rename <- function(con, tb, old_name, new_name, db = NULL, prj = FALSE) {
  DBI::dbExecute(
    con,
    sprintf(
      "ALTER TABLE %s RENAME COLUMN %s TO %s;",
      db_tb(con, tb, db, prj),
      DBI::dbQuoteIdentifier(con, old_name),
      DBI::dbQuoteIdentifier(con, new_name)
    )
  )
}

db_fields <- function(con, tb, db = NULL, prj = FALSE) {
  DBI::dbListFields(con, db_id(tb, db, prj))
}

#### --- Cloud database helpers ---

.pg_host <- function() Sys.getenv("PGHOST", "localhost")
.pg_port <- function() as.integer(Sys.getenv("PGPORT", "5433"))
.pg_database <- function() Sys.getenv("PGDATABASE", "becmaster")

is_cloud_connected <- function(con, alias = "master") {
  tryCatch(
    {
      db_query(con, paste0("SELECT 1 FROM ", alias, ".information_schema.tables LIMIT 1"))
      TRUE
    },
    error = function(e) {
      FALSE
    }
  )
}

attach_cloud_db <- function(con, pg_user, pg_password = NULL, alias = "master", fail_on_error = TRUE) {
  if (is_cloud_connected(con, alias)) {
    message("[db] Cloud database '", alias, "' is already attached")
    return(invisible(NULL))
  }

  host <- .pg_host()
  port <- .pg_port()
  database <- .pg_database()

  if (is.null(pg_password) || !nzchar(pg_password %||% "")) {
    conn_string <- sprintf("postgres://%s@%s:%s/%s", pg_user, host, port, database)
  } else {
    conn_string <- sprintf("postgres://%s:%s@%s:%s/%s", pg_user, pg_password, host, port, database)
  }

  message("[db] Attaching PostgreSQL as '", alias, "' (user: ", pg_user, ")")

  tryCatch(
    {
      db_run(con, "INSTALL postgres")
      db_run(con, "LOAD postgres")
    },
    error = function(e) {
      warning("postgres extension install/load may have failed: ", e$message)
    }
  )

  attach_sql <- paste0("ATTACH '", conn_string, "' AS ", alias, " (TYPE postgres)")

  tryCatch(
    {
      db_run(con, attach_sql)
      message("[db] PostgreSQL attached successfully as '", alias, "'")
    },
    error = function(e) {
      msg <- paste0("Failed to attach PostgreSQL as '", pg_user, "': ", e$message)
      if (isTRUE(fail_on_error)) {
        stop(msg)
      }
      warning(msg)
      return(invisible(NULL))
    }
  )

  invisible(NULL)
}

attach_cloud <- function(con, alias = "master", fail_on_error = TRUE) {
  pg_user <- Sys.getenv("VPRO_PG_APP_USER", "vpro_app")
  pg_pass <- Sys.getenv("VPRO_PG_APP_PASSWORD", "")
  if (!nzchar(pg_pass)) {
    stop("VPRO_PG_APP_PASSWORD env var is not set")
  }
  attach_cloud_db(con, pg_user = pg_user, pg_password = pg_pass, alias = alias, fail_on_error = fail_on_error)
}

#### --- VPro64 task functions ---

db_rename_fix01 <- function(con) {
  if ("JustEnglishName" %in% db_fields(con, "USysAllSpecs", "VLists")) {
    db_rename(con, "USysAllSpecs", "EnglishName", "CombinedEnglishName", "VLists")
    db_rename(con, "USysAllSpecs", "JustEnglishName", "EnglishName", "VLists")
  }
}

db_masterunitlist_views <- function(con) {
  # Have to be temporary
  # https://sqlite.org/forum/forumpost/e29aa9a425b2c157
  db <- c("VLists", "VUser")
  tb <- c("MasterSiteUnitList", "UserSiteUnitList")
  sql <- sprintf("CREATE OR REPLACE TEMPORARY VIEW USys%s AS SELECT * FROM %s.%s;", tb, db, tb)
  lapply(sql, db_run, con = con)
  tb <- c("MasterSiteUnitList", "MasterUnitList_Hierarchy")
  sql <- paste("CREATE OR REPLACE TEMPORARY VIEW", tb, "AS ", "SELECT * FROM UsysMasterSiteUnitList", "UNION ALL", "SELECT * FROM UsysUserSiteUnitList;")
  lapply(sql, db_run, con = con)
  return()
}
