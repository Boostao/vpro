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

# Config used to replace values that were stored in Windows registry in VPro64.
# Still stored in yaml config file but accessed through config() function.
config <- config_init()
# Global environment to store runtime state values that were declared
# mainly in V7mdlGlobalDeclarations.
global <- new.env(parent = emptyenv())

#### --- Local Database helpers ---

# List of project tables
db_project_tables <- c(
  "Admin",
  "Audit",
  "Env",
  "Herbarium",
  "Hierarchy",
  "Humus",
  "Lump",
  "Metadata",
  "Mineral",
  "Other",
  "Profile",
  "SU",
  "Theme",
  "Veg"
)

db_sys_dbs <- c()

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
  miss_d <- setdiff(db, exist_d)
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

db_convert_access_to_sqlite <- function(path) {
  # Create a temporary file for the converted database
  tmp_sqlite <- tempfile(fileext = ".db")
  on.exit(unlink(tmp_sqlite), add = TRUE)

  access_con <- DBI::dbConnect(mdbr::mdb(), path)
  on.exit(try(DBI::dbDisconnect(access_con), silent = TRUE), add = TRUE)

  tmp_sqlite
}

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

db_log_in <- function(con, session) {
  # Log entry into user log table
  db_insert(
    currentDB,
    "USysUserLog",
    User = Sys.info()[["user"]],
    InTime = Sys.time(),
    OutTime = NA,
    LocalMachine = Sys.info()[["nodename"]]
  )
}

db_log_vpro <- function(con, session, state = c("On", "Off")) {
  state <- match.arg(state)
  # Insert Audit trace in project
  db_insert(
    currentDB,
    "Audit",
    db = config("Current", "CurrProject"),
    prj = TRUE,
    Project = config("Current", "CurrProject"),
    User = config("Current", "User"),
    Table = state,
    EditWhen = Sys.time()
  )
}

db_log_project <- function(con, session, state = c("Open", "Close")) {
  state <- match.arg(state)
  # Insert Audit trace in project
  db_insert(
    con,
    "Audit",
    db = config("Current", "CurrProject"),
    prj = TRUE,
    Project = config("Current", "CurrProject"),
    User = config("Current", "User"),
    Table = state,
    EditWhen = Sys.time()
  )

  if (state == "Open") {
    PVersion <- ProjectVersion(con)
    ASVersion <- AllSpecsVersion(con)
    if (PVersion != ASVersion) {
      db_insert(
        con,
        "Audit",
        db = config("Current", "CurrProject"),
        prj = TRUE,
        Project = config("Current", "CurrProject"),
        User = config("Current", "User"),
        Table = "USysAllSpecs",
        EditWhen = Sys.time(),
        AfterEdit = ASVersion,
        BeforeEdit = PVersion
      )
      bslib::show_toast(
        session = session,
        bslib::toast(
          header = "VPro",
          paste0(
            "FYI: the previous version of USysAllSpecs for project '",
            config("Current", "CurrProject"),
            "' was '",
            PVersion,
            "' and is now '",
            ASVersion,
            "'."
          ),
          type = "info",
        )
      )
    }
    PVersion = ProjectVersionTableOfLists()
    ASVersion = TableOfListsVersion()
    if (PVersion != ASVersion) {
      db_insert(
        con,
        "Audit",
        db = config("Current", "CurrProject"),
        prj = TRUE,
        Project = config("Current", "CurrProject"),
        User = config("Current", "User"),
        Table = "USysTableOfLists",
        EditWhen = Sys.time(),
        AfterEdit = ASVersion,
        BeforeEdit = PVersion
      )
      bslib::show_toast(
        session = session,
        bslib::toast(
          header = "VPro",
          paste0(
            "FYI: the previous version of USysTableOfLists for project '",
            config("Current", "CurrProject"),
            "' was '",
            PVersion,
            "' and is now '",
            ASVersion,
            "'."
          ),
          type = "info",
        )
      )
    }
  }
}

from_audit_Version <- function(con, table) {
  res <- db_query(
    con,
    sprintf(
      "SELECT %s
       FROM %s WHERE %s=?
       ORDER BY EditWhen DESC LIMIT 1;",
      paste0(DBI::dbQuoteIdentifier(con, c("Table", "EditWhen", "AfterEdit")), collapse = ", "),
      db_tb(con, "Audit", config("Current", "CurrProject"), prj = TRUE),
      DBI::dbQuoteIdentifier(con, "Table")
    ),
    params = list(table)
  )

  if (nrow(res) == 0) {
    return("Unknown")
  }

  if (is.na(res$AfterEdit) || res$AfterEdit == "") {
    return("Unknown")
  } else {
    return(res$AfterEdit)
  }
}

from_metadata_Version <- function(con, table, schema = "VLists") {
  res <- db_query(
    con,
    sprintf(
      "SELECT description
       FROM %s._table_metadata
       WHERE table_name = ?;",
      DBI::dbQuoteIdentifier(con, schema)
    ),
    params = list(table)
  )

  if (nrow(res) == 0 || is.na(res$description) || res$description == "") {
    return("Unknown")
  } else {
    return(res$description)
  }
}

ProjectVersion <- function(con) {
  from_audit_Version(con, "USysAllSpecs")
}

AllSpecsVersion <- function(con) {
  from_metadata_Version(con, "USysAllSpecs")
}

ProjectVersionTableOfLists <- function(con) {
  from_audit_Version(con, "USysTableOfLists")
}

TableOfListsVersion <- function(con) {
  from_metadata_Version(con, "USysTableOfLists")
}

GetVProTableVersion <- function(project, table, con) {
  from_metadata_Version(con, table, project)
}

AttachProject <- function(MyDB, session) {
  global$sysSelectedItems <- list()
  global$sysPickTable <- "None"
  GetFileName("Select database to attach", session, "application/vnd.sqlite3", on_file = function(path) {
    if (!is.null(path) && nzchar(path)) {
      tryCatch(
        {
          RemoteDB <- db_con(path)
          ProjectList <- tryCatch(
            BuildProjectPickList(RemoteDB, MyDB),
            finally = try(db_close(RemoteDB), silent = TRUE)
          )
          if (length(ProjectList) == 0) {
            bslib::show_toast(
              session = session,
              bslib::toast(
                header = config("Program", "Name"),
                "No projects found or one with the same name may already be attached.",
                type = "warning"
              )
            )
            return()
          }
          USysPickTable(
            session,
            pick_list = ProjectList,
            on_select = function(selected) {
              for (MyProject in selected) {
                AttachProjectTables(MyProject, path, MyDB, session)
              }
              global$sysSelectedItems <- NULL
            }
          )
        },
        error = function(e) {
          bslib::show_toast(
            session = session,
            bslib::toast(
              header = config("Program", "Name"),
              paste("Failed to attach project database:", conditionMessage(e)),
              type = "danger"
            )
          )
        }
      )
    }
  })
}

# Attach a single project's tables from a remote SQLite file into the main DuckDB connection.
# Access equivalent: AttachProjectTables (DoCmd.TransferDatabase acLink per table)
AttachProjectTables <- function(project, path, con, session) {
  RemoteDB <- db_con(path)
  TableVersion <- GetVProTableVersion(project, sprintf("%s_Env", project), RemoteDB)
  if (TableVersion == "VP05") {} else if (TableVersion == "VP06") {} else if (TableVersion == "VP07") {} else if (TableVersion != "VP08") {
    bslib::show_toast(
      session = session,
      bslib::toast(
        header = config("Program", "Name"),
        "This isn't a VPro 19 project.  Please convert to the current version.",
        type = "info"
      )
    )
    return()
  }

  tryCatch(
    {
      db_attach(con, path)
      bslib::show_toast(
        session = session,
        bslib::toast(
          header = config("Program", "Name"),
          paste0("Project '", project, "' attached."),
          type = "success"
        )
      )
    },
    error = function(e) {
      bslib::show_toast(
        session = session,
        bslib::toast(
          header = config("Program", "Name"),
          paste0("Failed to attach '", project, "': ", conditionMessage(e)),
          type = "danger"
        )
      )
    }
  )
}

GetFileName <- function(title, session, accept = NULL, on_file = NULL) {
  accepted <- c(accept, "application/octet-stream")
  dismiss <- function() {
    obs_file$destroy()
    obs_exit$destroy()
  }
  obs_file <- shiny::observeEvent(
    session$input$getfilename_input,
    {
      dismiss()
      shiny::removeModal(session)
      file <- session$input$getfilename_input
      if (!is.null(file)) {
        if (!is.null(on_file)) on_file(file$datapath)
      }
    },
    domain = session,
    once = TRUE,
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )
  obs_exit <- shiny::observeEvent(
    session$input$picktable_exit,
    {
      dismiss()
      shiny::removeModal(session)
    },
    domain = session,
    once = TRUE,
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )
  shiny::showModal(
    session = session,
    shiny::modalDialog(
      title = title,
      shiny::fileInput("getfilename_input", "Choose file", accept = accepted, multiple = FALSE),
      easyClose = FALSE,
      footer = shiny::actionButton("picktable_exit", icon = shiny::icon("sign-out"), class = "btn btn-default btn-sm")
    )
  )
}

BuildProjectPickList <- function(RemoteDB, LocalDB) {
  strTestTables <- db_query(RemoteDB, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_Env';")$name
  strList <- strTestTables[!TestForTableInVPro(LocalDB, strTestTables)]
  res <- character()
  if (length(strList) > 0) {
    res <- substr(strList, 1, nchar(strList) - nchar("_Env"))
  }
  res
}

TestForTableInVPro <- function(MyDB, TableName) {
  res <- db_query(MyDB, "SELECT name FROM sqlite_master WHERE type='table' AND name=?;", params = list(TableName))
  TableName %in% res$name
}

USysPickTable <- function(session, pick_list = character(), on_select = NULL) {
  dismiss <- function() {
    obs_pick$destroy()
    obs_help$destroy()
    obs_exit$destroy()
  }
  obs_pick <- shiny::observeEvent(
    session$input$picktable_attach,
    {
      selected <- session$input$picktable_list
      if (is.null(selected) || length(selected) == 0) {
        bslib::show_toast(
          session = session,
          bslib::toast("Select an item first.", type = "warning")
        )
        return()
      }
      dismiss()
      shiny::removeModal(session)
      global$sysSelectedItems <- selected
      if (!is.null(on_select)) on_select(selected)
    },
    domain = session,
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )
  obs_help <- shiny::observeEvent(
    session$input$picktable_help,
    {
      bslib::show_toast(
        session = session,
        bslib::toast(
          "VPro hides items of the same name that are already attached. Try unattaching the item first.",
          type = "info"
        )
      )
    },
    domain = session,
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )
  obs_exit <- shiny::observeEvent(
    session$input$picktable_exit,
    {
      dismiss()
      shiny::removeModal(session)
      global$sysSelectedItems <- NULL
    },
    domain = session,
    once = TRUE,
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )
  shiny::showModal(
    session = session,
    shiny::modalDialog(
      title = "Pick Attachment(s)",
      shiny::selectInput(
        "picktable_list",
        label = NULL,
        choices = pick_list,
        multiple = TRUE,
        size = 8,
        selectize = FALSE
      ),
      shiny::tags$small(
        shiny::actionLink("picktable_help", "Don't see an item you expect to see?")
      ),
      easyClose = FALSE,
      footer = bslib::layout_columns(
        shiny::actionButton("picktable_attach", "Attach", class = "btn btn-primary btn-sm"),
        shiny::actionButton("picktable_exit", icon = shiny::icon("sign-out"), class = "btn btn-default btn-sm")
      )
    )
  )
}

PickProjects <- function(session, pick_list = character(), on_select = NULL) {
  USysPickTable(session, pick_list, on_select)
}

LogProjectOut <- function(con, session) {
  # Log project close in audit
  db_log_project(con, session, "Close")
}

LogProjectIn <- function(con, session) {
  # Log project open in audit
  db_log_project(con, session, "Open")
}
