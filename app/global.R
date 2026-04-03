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

# Logic imports
source("R/logic/00.db.R") # Database helper functions
source("R/logic/01.state.R") # State management functions
source("R/logic/logic_google_earth.R") # KML generation (Google Earth export)
source("R/logic/logic_su_table_tools.R") # SU table tools (SU↔Env sync)
source("R/logic/logic_record_nav.R") # Record navigation + audit trail

# Module Imports
source("R/modules/mod_whatsnew.R")
source("R/modules/mod_project_metadata.R")
source("R/modules/mod_images.R")
source("R/modules/mod_plot_profiling.R")
source("R/modules/mod_fs882_6x4.R")
source("R/modules/mod_fs882_8x6xl.R")
source("R/modules/mod_fs1333.R")
source("R/modules/mod_combine_species.R")
source("R/modules/mod_herbarium.R")
source("R/modules/mod_colour_theme.R")
source("R/modules/mod_user_setup.R")
source("R/modules/mod_user_log.R")
source("R/modules/mod_reporting.R")

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
# source("R/logic/logic_state.R") # Global State Logic
# source("R/logic/logic_lumping.R") # Lumping Logic
# source("R/logic/logic_compliance.R") # Compliance checks
# source("R/logic/logic_audit.R") # Audit trail
# source("R/logic/logic_diagnostic.R") # Diagnostic helpers
# source("R/logic/logic_auth.R") # Auth + RBAC helpers
# source("R/logic/logic_coord_tools.R") # Coordinate conversion tools
# source("R/logic/logic_climr.R") # ClimR climate data integration
# source("R/logic/logic_project.R") # Project file management
source("R/logic/logic_hierarchy_sidebar.R") # Sidebar hierarchy workbench helpers
# source("R/logic/logic_sync.R") # Sync engine (stub)
# source("R/logic/logic_publish.R") # Publish pipeline (stub)
# source("R/logic/logic_reports_veg.R") # Veg report helpers
# source("R/logic/logic_reports_qc.R") # Quality control filtering
# source("R/logic/logic_reports_hierarchy.R") # Hierarchy tree formatting
# source("R/logic/logic_reports_env.R") # Environmental statistics
# source("R/logic/logic_reports_validation.R") # Data validation
# source("R/logic/logic_report_export.R") # Excel report export helpers
# source("R/logic/logic_excel_export.R") # Excel export with styled formatting
# source("R/logic/logic_venus_export.R") # VENUS XML export
# source("R/modules/mod_project.R") # Project management (Open/New/Save/Close)
# source("R/modules/mod_admin_projects.R")
# source("R/modules/mod_admin_codes.R")
# source("R/modules/mod_admin_master.R")
# source("R/modules/mod_admin_audit.R")
# source("R/modules/mod_admin_merge.R")
# source("R/modules/mod_admin_publishing.R")
# source("R/modules/mod_admin.R")
# source("R/modules/mod_images.R")
# source("R/modules/mod_veg_sample.R")
# source("R/modules/mod_site_env.R")
# source("R/modules/mod_su_table.R")
# source("R/modules/mod_fs1333.R")
# source("R/modules/mod_project_metadata.R")
# source("R/modules/mod_combine_species.R")
# source("R/modules/mod_herbarium.R")
# source("R/modules/mod_export.R")
# source("R/modules/mod_reporting.R")
# source("R/modules/mod_import.R")
# source("R/modules/mod_home.R")
# source("R/modules/mod_auth.R")
# source("R/modules/mod_auth_status.R")
# source("R/modules/mod_sync.R")
# source("R/modules/mod_hierarchy.R")
# source("R/modules/mod_upload.R")
# source("R/modules/mod_merge.R")

# source("R/modules/mod_becweb_map.R")
# source("R/modules/mod_data_entry_context.R")
source("R/modules/mod_nav_launcher.R")

# # Note: The actual 'SysState' object is initialized in server.R 
# # because it must be reactive and unique to the session.

