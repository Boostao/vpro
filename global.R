library(shiny)
library(duckdb)
library(dplyr)
library(dbplyr)
library(bslib)
library(DT)
library(rhandsontable)
library(shinyjs)
library(shinyTree)

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
source("R/db_connections.R") # Connection helpers + %||%
source("R/logic_sync.R") # Sync engine (stub)
source("R/logic_publish.R") # Publish pipeline (stub)
source("R/mod_admin.R")
source("R/mod_images.R")
source("R/mod_veg_sample.R")
source("R/mod_site_env.R")
source("R/mod_export.R")
source("R/mod_reporting.R")
source("R/mod_import.R")
source("R/mod_hierarchy.R")
source("R/mod_upload.R")
source("R/mod_merge.R")
source("R/mod_auth.R")

# Note: The actual 'SysState' object is initialized in server.R 
# because it must be reactive and unique to the session.
