library(shiny)
library(duckdb)
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


Sys.setenv(PGHOST = "localhost")
Sys.setenv(PGPORT = "5433")
Sys.setenv(PGDATABASE = "becmaster")
Sys.setenv(VPRO_PG_APP_USER = "vpro_app")
Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")

# ---- Dev/Test Defaults (temporary) ----
VPRO_DEV_MODE <- TRUE
VPRO_DEV_DEFAULT_PROJECT <- "BEC"
VPRO_DEV_DEFAULT_PLOTNUMBER <- "9624781"


# Database Connection
# Using a function to get a fresh connection or manage a pool object
# For Shiny, usually we want a persistent connection or a pool.
# Since duckdb allows concurrent reads, we can open one read-only connection for the app lifetime if needed,
# or open/close per request. We'll use a simple approach: open in server.
db_path <- file.path(getwd(), "data/vpro.duckdb")

# Simple logging
log_msg <- function(...) {
  cat(file=stderr(), paste0(..., "\n"))
}

# Module Imports
source("R/logic_state.R") # Global State Logic
source("R/logic_lumping.R") # Lumping Logic
source("R/logic_compliance.R") # Compliance checks
source("R/logic_audit.R") # Audit trail
source("R/logic_diagnostic.R") # Diagnostic helpers
source("R/logic_auth.R") # Auth + RBAC helpers
source("R/logic_coord_tools.R") # Coordinate conversion tools
source("R/logic_climr.R") # ClimR climate data integration
source("R/db_connections.R") # Connection helpers + %||%
source("R/logic_project.R") # Project file management
source("R/logic_sync.R") # Sync engine (stub)
source("R/logic_publish.R") # Publish pipeline (stub)
source("R/logic_reports_veg.R") # Veg report helpers
source("R/logic_reports_qc.R") # Quality control filtering
source("R/logic_reports_hierarchy.R") # Hierarchy tree formatting
source("R/logic_reports_env.R") # Environmental statistics
source("R/logic_reports_validation.R") # Data validation
source("R/logic_report_export.R") # Excel report export helpers
source("R/logic_excel_export.R") # Excel export with styled formatting
source("R/logic_venus_export.R") # VENUS XML export
source("R/mod_project.R") # Project management (Open/New/Save/Close)
source("R/mod_admin_projects.R")
source("R/mod_admin_codes.R")
source("R/mod_admin_master.R")
source("R/mod_admin_audit.R")
source("R/mod_admin_merge.R")
source("R/mod_admin_publishing.R")
source("R/mod_admin.R")
source("R/mod_images.R")
source("R/mod_veg_sample.R")
source("R/mod_site_env.R")
source("R/mod_fs882_6x4_reimagined_ui.R")
source("R/mod_export.R")
source("R/mod_reporting.R")
source("R/mod_import.R")
source("R/mod_auth.R")
source("R/mod_auth_status.R")
source("R/mod_sync.R")
source("R/mod_hierarchy.R")
source("R/mod_upload.R")
source("R/mod_merge.R")

source("R/mod_becweb_map.R")
source("R/mod_whatsnew.R")
source("R/mod_data_entry_context.R")

# Note: The actual 'SysState' object is initialized in server.R 
# because it must be reactive and unique to the session.

