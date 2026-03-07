# dev/app_auth_status.R
# Standalone test app for mod_auth_status — no global.R required.
#
# Run from workspace root:
#   shiny::runApp("dev/app_auth_status.R")
#
# Verification steps (from plan-authStatusWidget.prompt.md):
#   1. Offline (no env vars): grey badge, "Sign In" link, "Last pull: never"
#   2. In R console: sync_set_watermark(con, "env", "pull") — last-pull string updates
#   3. Sign in as guest → green badge + email + "↓ N behind" count
#   4. Sign in as admin → blue badge + shield icon + email
#   5. Click "Sync →" → switches to Sync tab
#   6. Click "Sign In" (offline) → switches to Auth tab
#   7. In R console: state$SyncVersion <- state$SyncVersion + 1L → widget re-renders

# Set working directory to workspace root to match main app behavior
root_dir <- tryCatch(
  {
    script_path <- rstudioapi::getSourceEditorContext()$path
    dirname(dirname(script_path))
  },
  error = function(e) {
    # Fallback if RStudio API not available
    if (dir.exists("../R") && dir.exists("../data")) {
      ".."
    } else {
      "."
    }
  }
)
setwd(root_dir)

library(shiny)
library(bslib)
library(DBI)
library(duckdb)
library(shinyjs)

source("R/db_connections.R")
source("R/logic_auth.R")
source("R/logic_sync.R")
source("R/mod_auth.R")
source("R/mod_auth_status.R")


Sys.setenv(PGHOST = "localhost")
Sys.setenv(PGPORT = "5433")
Sys.setenv(PGDATABASE = "becmaster")
Sys.setenv(VPRO_PG_APP_USER = "vpro_app")
Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")

# Open local DB once and ensure sync schema exists
con <- connect_local_db()
sync_ensure_local_tables(con)

ui <- page_navbar(
  title = "Auth Status Widget — Dev Test",
  id    = "main_nav",
  theme = bs_theme(version = 5),
  shinyjs::useShinyjs(),
  nav_panel("Auth", value = "Auth", mod_auth_ui("Auth")),
  nav_panel("Sync", value = "Sync", p("Sync page — coming soon")),
  nav_item(mod_auth_status_ui("auth_status"))
)

server <- function(input, output, session) {
  state <- reactiveValues()
  auth_init_state(state)

  mod_auth_server("Auth", state, con)
  nav_signal <- mod_auth_status_server("auth_status", state, con)

  observe({
    dest <- nav_signal()
    if (!is.null(dest)) {
      nav_select("main_nav", selected = dest)
    }
  })
}
shinyApp(ui, server)
