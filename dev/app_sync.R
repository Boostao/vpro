# dev/app_sync.R
# Standalone dev test app for mod_sync — no global.R required.
#
# Run from workspace root:
#   shiny::runApp("dev/app_sync.R")
#
# ── Scenario sidebar buttons ───────────────────────────────────────────────────
#   1. Insert 3 fake Env rows (DEV_TEST_ prefix) → should appear as green inserts
#   2. Mark 2 existing Env rows as updated       → yellow updates
#   3. Inject a sync.conflict_queue row          → blocking conflict modal fires
#   4. Insert 3 fake MRs in master.admin         → requires cloud attached
#   5. Reset — delete all DEV_TEST_ artefacts
# ──────────────────────────────────────────────────────────────────────────────

root_dir <- tryCatch(
  {
    script_path <- rstudioapi::getSourceEditorContext()$path
    dirname(dirname(script_path))
  },
  error = function(e) {
    if (dir.exists("../R") && dir.exists("../data")) ".." else "."
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
source("R/logic_state.R")
source("R/mod_auth.R")
source("R/mod_sync.R")

Sys.setenv(PGHOST = "localhost")
Sys.setenv(PGPORT = "5433")
Sys.setenv(PGDATABASE = "becmaster")
Sys.setenv(VPRO_PG_APP_USER = "vpro_app")
Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")

con <- connect_local_db()
sync_ensure_local_tables(con)

# ── DEV ONLY defaults ─────────────────────────────────────────────────────────
DEV_PREFIX     <- "DEV_TEST_"
DEV_PROJECT_ID <- 99L

ui <- page_sidebar(
  title  = "Sync Module — Dev Test",
  theme  = bs_theme(version = 5),
  shinyjs::useShinyjs(),
  sidebar = sidebar(
    width = 250,
    h6(class = "text-muted mt-2", "Scenarios"),
    hr(class = "my-1"),
    actionButton("btn_scenario_inserts",  "1. Add 3 Env inserts",  class = "btn btn-outline-success btn-sm w-100 mb-1"),
    actionButton("btn_scenario_updates",  "2. Mark 2 Env updates", class = "btn btn-outline-warning btn-sm w-100 mb-1"),
    actionButton("btn_scenario_conflict", "3. Inject conflict",    class = "btn btn-outline-danger  btn-sm w-100 mb-1"),
    actionButton("btn_scenario_mrs",      "4. Add fake MRs",       class = "btn btn-outline-info    btn-sm w-100 mb-1"),
    hr(class = "my-2"),
    actionButton("btn_scenario_reset",    "5. Reset DEV_TEST_ rows", class = "btn btn-danger btn-sm w-100")
  ),
  mod_sync_ui("sync")
)

server <- function(input, output, session) {
  
  state <- init_sys_state()
  attach_cloud(con, fail_on_error = TRUE)
  auth_init_state(state)
  .auth_set_state(state, data.frame(
    email = paste0(Sys.getenv("USER", "dev"), "@dev.local"),
    id = 1L,
    app_role = "guest",
    stringsAsFactors = FALSE
  ))
  state$User        <- paste0(Sys.getenv("USER", "dev"), "@dev.local")
  state$CurrProject <- DEV_PROJECT_ID

  mod_sync_server("sync", state, con)

  # ── DEV ONLY: scenario handlers ───────────────────────────────────────────

  # Scenario 1: 3 new Env inserts
  observeEvent(input$btn_scenario_inserts, {
    # DEV ONLY
    for (i in 1:3) {
      pn <- paste0(DEV_PREFIX, "ENV_", format(Sys.time(), "%H%M%S"), "_", i)
      tryCatch(
        DBI::dbExecute(con,
          "INSERT INTO Env (PlotNumber, ProjectID, local_modified_utc)
           VALUES (?, ?, now())",
          list(pn, DEV_PROJECT_ID)
        ),
        error = function(e) print(e)
      )
    }
    state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
    showNotification("Scenario 1: 3 DEV_TEST_ Env inserts added.", type = "message")
  })

  # Scenario 2: mark 2 existing Env rows as updated locally
  observeEvent(input$btn_scenario_updates, {
    # DEV ONLY
    existing <- tryCatch(
      DBI::dbGetQuery(con,
        "SELECT PlotNumber FROM Env WHERE PlotNumber NOT LIKE ? LIMIT 2",
        list(paste0(DEV_PREFIX, "%"))
      )$PlotNumber,
      error = function(e) character(0)
    )
    if (length(existing) == 0) {
      showNotification("No existing non-DEV rows to mark as updated.", type = "warning")
      return()
    }
    for (pn in existing) {
      tryCatch(
        DBI::dbExecute(con,
          "UPDATE Env SET local_modified_utc = now() WHERE PlotNumber = ?",
          list(pn)
        ),
        error = function(e) NULL
      )
    }
    state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
    showNotification(
      paste0("Scenario 2: marked ", length(existing), " row(s) as locally updated."),
      type = "message"
    )
  })

  # Scenario 3: inject a pull conflict into sync.conflict_queue
  observeEvent(input$btn_scenario_conflict, {
    # DEV ONLY
    pn <- paste0(DEV_PREFIX, "CONF_", format(Sys.time(), "%H%M%S"))
    # Ensure a local row exists for the conflict
    tryCatch(
      DBI::dbExecute(con,
        "INSERT OR IGNORE INTO Env (PlotNumber, ProjectID, local_modified_utc)
         VALUES (?, ?, now())",
        list(pn, DEV_PROJECT_ID)
      ),
      error = function(e) NULL
    )
    tryCatch({
      DBI::dbExecute(con,
        "INSERT INTO sync.conflict_queue
           (table_name, plot_number, project_id, local_values, master_values)
         VALUES ('env', ?, ?, '{\"note\":\"local version\"}', '{\"note\":\"master version\"}')",
        list(pn, DEV_PROJECT_ID)
      )
      state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
      showNotification("Scenario 3: conflict injected — modal should appear.", type = "warning")
    }, error = function(e) {
      showNotification(paste("Scenario 3 error:", e$message), type = "error")
    })
  })

  # Scenario 4: insert fake MRs into master.admin (requires cloud attached)
  observeEvent(input$btn_scenario_mrs, {
    # DEV ONLY
    if (!sync_cloud_connected(con)) {
      showNotification("Scenario 4 requires cloud attached. Log in first.", type = "warning")
      return()
    }
    statuses <- c("pending_review", "merged", "rejected")
    for (st in statuses) {
      tryCatch(
        DBI::dbExecute(con,
          "INSERT INTO master.admin.merge_requests
             (project_id, submitter_name, status, env_record_count, review_notes)
           VALUES (?, ?, ?, 3, 'DEV_TEST scenario 4')",
          list(DEV_PROJECT_ID, state$User, st)
        ),
        error = function(e) {
          showNotification(paste("Scenario 4 error:", e$message), type = "error")
        }
      )
    }
    state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
    showNotification("Scenario 4: 3 fake MRs inserted in master.", type = "message")
  })

  # Scenario 5: reset all DEV_TEST_ artefacts
  observeEvent(input$btn_scenario_reset, {
    # DEV ONLY
    tryCatch({
      DBI::dbExecute(con,
        "DELETE FROM Env WHERE PlotNumber LIKE ?", list(paste0(DEV_PREFIX, "%")))
      DBI::dbExecute(con,
        "DELETE FROM SU  WHERE PlotNumber LIKE ?", list(paste0(DEV_PREFIX, "%")))
      DBI::dbExecute(con,
        "DELETE FROM Veg WHERE PlotNumber LIKE ?", list(paste0(DEV_PREFIX, "%")))
      DBI::dbExecute(con,
        "DELETE FROM sync.conflict_queue WHERE plot_number LIKE ?",
        list(paste0(DEV_PREFIX, "%")))
      # Also clear locally-dirtied non-DEV rows
      DBI::dbExecute(con,
        "UPDATE Env SET local_modified_utc = NULL WHERE local_modified_utc IS NOT NULL
         AND PlotNumber NOT LIKE ?", list(paste0(DEV_PREFIX, "%")))
    }, error = function(e) NULL)

    # Clean master MRs if cloud attached
    if (sync_cloud_connected(con)) {
      tryCatch(
        DBI::dbExecute(con,
          "DELETE FROM master.admin.merge_requests
           WHERE submitter_name = ? AND review_notes = 'DEV_TEST scenario 4'",
          list(state$User)
        ),
        error = function(e) NULL
      )
    }

    state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
    showNotification("Scenario 5: all DEV_TEST_ artefacts reset.", type = "message")
  })
}

shinyApp(ui, server)
