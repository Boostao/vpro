library(vpro)
library(shiny)
library(duckdb)
library(yaml)
library(dplyr)
library(dbplyr)
library(bslib)
library(DT)
library(rhandsontable)
library(shinyjs)
library(shinyTree)
library(leaflet)
library(sf)
library(quarto)

options(shiny.maxRequestSize = 4 * 1024^3) # 4GB max upload size, adjust as needed

# Use a fresh file-backed accessor to avoid the package compatibility cache.
# Per-session UI selections without a canonical config key stay session-local.
.app_session_config_defaults <- list(
  Current = list(
    CurrHerbarium = "None",
    CurrLump = "None"
  )
)

app_config_session_state <- function(session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) {
    return(NULL)
  }

  state <- session$userData$app_config_state
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    session$userData$app_config_state <- state
  }
  state
}

app_config_session_default <- function(section, key) {
  section_defaults <- .app_session_config_defaults[[section]]
  if (is.null(section_defaults) || !(key %in% names(section_defaults))) {
    return(NULL)
  }
  section_defaults[[key]]
}

app_config_get <- function(section, key, session = shiny::getDefaultReactiveDomain()) {
  session_default <- app_config_session_default(section, key)
  if (!is.null(session_default)) {
    state <- app_config_session_state(session)
    state_key <- paste(section, key, sep = "\r")
    if (!is.null(state) && exists(state_key, envir = state, inherits = FALSE)) {
      return(get(state_key, envir = state, inherits = FALSE))
    }
    return(session_default)
  }

  accessor <- vpro::config_init(create = TRUE)
  accessor(section, key)
}

app_config_set <- function(section, key, value, session = shiny::getDefaultReactiveDomain()) {
  session_default <- app_config_session_default(section, key)
  if (!is.null(session_default)) {
    state <- app_config_session_state(session)
    if (is.null(state)) {
      stop("Session-local app configuration requires an active Shiny session.", call. = FALSE)
    }
    assign(paste(section, key, sep = "\r"), value, envir = state)
    return(invisible(value))
  }

  accessor <- vpro::config_init(create = TRUE)
  accessor(section, key, value)
}

app_project_table_id <- function(con, tb, db = NULL, prj = FALSE) {
  if (!is.character(tb) || length(tb) != 1L || is.na(tb) || !nzchar(tb)) {
    stop("`tb` must be one non-empty table name.", call. = FALSE)
  }
  if (!isTRUE(prj)) {
    return(DBI::Id(table = tb))
  }
  if (!is.character(db) || length(db) != 1L || is.na(db) || !nzchar(db)) {
    stop("`db` must be one non-empty project name when `prj` is TRUE.", call. = FALSE)
  }

  physical_table <- paste0(db, "_", tb)
  managed_alias <- paste0("vpro_project_", tolower(db))
  databases <- DBI::dbGetQuery(con, "SELECT database_name, path FROM duckdb_databases()")
  tables <- DBI::dbGetQuery(
    con,
    "SELECT database_name FROM duckdb_tables() WHERE lower(table_name) = lower(?)",
    params = list(physical_table)
  )
  candidates <- merge(tables, databases, by = "database_name")
  aliases <- unique(candidates$database_name[!is.na(candidates$path)])
  if (managed_alias %in% aliases) {
    alias <- managed_alias
  } else if (length(aliases) == 1L) {
    alias <- aliases[[1L]]
  } else {
    stop("Cannot uniquely resolve attached project table: ", physical_table, call. = FALSE)
  }
  DBI::Id(schema = alias, table = physical_table)
}

app_project_table_sql <- function(con, tb, db = NULL, prj = FALSE) {
  DBI::dbQuoteIdentifier(con, app_project_table_id(con, tb, db, prj))
}

# Module Imports
source("modules/mod_whatsnew.R", local = TRUE)
source("modules/mod_sidebar.R", local = TRUE)
source("modules/mod_project_metadata.R", local = TRUE)
source("modules/mod_images.R", local = TRUE)
source("modules/mod_plot_profiling.R", local = TRUE)
source("modules/mod_fs882_6x4.R", local = TRUE)
source("modules/mod_fs1333.R", local = TRUE)
source("modules/mod_combine_species.R", local = TRUE)
source("modules/mod_herbarium.R", local = TRUE)
source("modules/mod_colour_theme.R", local = TRUE)
source("modules/mod_user_setup.R", local = TRUE)
source("modules/mod_user_log.R", local = TRUE)
source("modules/mod_reporting.R", local = TRUE)

# To refactor below ---

# Sys.setenv(PGHOST = "localhost")
# Sys.setenv(PGPORT = "5433")
# Sys.setenv(PGDATABASE = "becmaster")
# Sys.setenv(VPRO_PG_APP_USER = "vpro_app")
# Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")

# # ---- Dev/Test Defaults (temporary) ----
# VPRO_DEV_MODE <- TRUE
# VPRO_DEV_DEFAULT_PROJECT <- "BEC"
# VPRO_DEV_DEFAULT_PLOTNUMBER <- "9624781"

# # Database Connection
# # Using a function to get a fresh connection or manage a pool object
# # For Shiny, usually we want a persistent connection or a pool.
# # Since duckdb allows concurrent reads, we can open one read-only connection for the app lifetime if needed,
# # or open/close per request. We'll use a simple approach: open in server.
# app_db_path <- file.path(getwd(), "data/vpro.duckdb")

# # Simple logging
# log_msg <- function(...) {
#   cat(file=stderr(), paste0(..., "\n"))
# }

# # Runtime bootstrapping is handled per session in server.R.
# app_db_path <- file.path(getwd(), "data", "VPro64.db")

# # Module Imports
# source("R/logic/logic_state.R", local = TRUE) # Global State Logic
# source("R/logic/logic_lumping.R", local = TRUE) # Lumping Logic
# source("R/logic/logic_compliance.R", local = TRUE) # Compliance checks
# source("R/logic/logic_audit.R", local = TRUE) # Audit trail
# source("R/logic/logic_diagnostic.R", local = TRUE) # Diagnostic helpers
# source("R/logic/logic_auth.R", local = TRUE) # Auth + RBAC helpers
# source("R/logic/logic_coord_tools.R", local = TRUE) # Coordinate conversion tools
# source("R/logic/logic_climr.R", local = TRUE) # ClimR climate data integration
# source("R/logic/logic_project.R", local = TRUE) # Project file management
# source("R/logic/logic_hierarchy_sidebar.R", local = TRUE) # Sidebar hierarchy workbench helpers
# source("R/logic/logic_sync.R", local = TRUE) # Sync engine (stub)
# source("R/logic/logic_publish.R", local = TRUE) # Publish pipeline (stub)
# source("R/logic/logic_reports_veg.R", local = TRUE) # Veg report helpers
# source("R/logic/logic_reports_qc.R", local = TRUE) # Quality control filtering
# source("R/logic/logic_reports_hierarchy.R", local = TRUE) # Hierarchy tree formatting
# source("R/logic/logic_reports_env.R", local = TRUE) # Environmental statistics
# source("R/logic/logic_reports_validation.R", local = TRUE) # Data validation
# source("R/logic/logic_report_export.R", local = TRUE) # Excel report export helpers
# source("R/logic/logic_excel_export.R", local = TRUE) # Excel export with styled formatting
# source("R/logic/logic_venus_export.R", local = TRUE) # VENUS XML export
# source("modules/mod_project.R", local = TRUE) # Project management (Open/New/Save/Close)
# source("modules/mod_admin_projects.R", local = TRUE)
# source("modules/mod_admin_codes.R", local = TRUE)
# source("modules/mod_admin_master.R", local = TRUE)
# source("modules/mod_admin_audit.R", local = TRUE)
# source("modules/mod_admin_merge.R", local = TRUE)
# source("modules/mod_admin_publishing.R", local = TRUE)
# source("modules/mod_admin.R", local = TRUE)
# source("modules/mod_images.R", local = TRUE)
# source("modules/mod_veg_sample.R", local = TRUE)
# source("modules/mod_site_env.R", local = TRUE)
# source("modules/mod_su_table.R", local = TRUE)
# source("modules/mod_fs1333.R", local = TRUE)
# source("modules/mod_project_metadata.R", local = TRUE)
# source("modules/mod_combine_species.R", local = TRUE)
# source("modules/mod_herbarium.R", local = TRUE)
# source("modules/mod_export.R", local = TRUE)
# source("modules/mod_reporting.R", local = TRUE)
# source("modules/mod_import.R", local = TRUE)
source("modules/mod_home.R", local = TRUE)
# source("modules/mod_auth.R", local = TRUE)
# source("modules/mod_auth_status.R", local = TRUE)
# source("modules/mod_sync.R", local = TRUE)
# source("modules/mod_hierarchy.R", local = TRUE)
# source("modules/mod_upload.R", local = TRUE)
# source("modules/mod_merge.R", local = TRUE)

# source("modules/mod_becweb_map.R", local = TRUE)
# source("modules/mod_data_entry_context.R", local = TRUE)
source("modules/mod_nav_launcher.R", local = TRUE)

# # Note: The actual 'SysState' object is initialized in server.R
# # because it must be reactive and unique to the session.
