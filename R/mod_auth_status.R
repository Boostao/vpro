# Reactive auth + sync status badge for the navbar.
#
# Triggered by state changes only — no polling via reactiveTimer.
# Returns a reactive() emitting "auth" | "sync" when the user clicks the
# respective action links (NULL when idle). The parent app should observe
# this signal and call nav_select() accordingly.

mod_auth_status_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("auth_widget"))
}

#' @param id     Module id.
#' @param state  Reactive values carrying auth state (incl. SyncVersion).
#' @param con    DuckDB connection (cloud may or may not be attached).
#' @return       reactive() → "auth" | "sync" | NULL
mod_auth_status_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Navigation signal — parent observe()s this and calls nav_select()
    nav_dest <- reactiveVal(NULL)
    
    observeEvent(input$go_auth, { 
      nav_dest("Auth")
      # Reset to NULL after brief delay so next click is detected
      shinyjs::delay(100, nav_dest(NULL))
    })
    observeEvent(input$go_sync, { 
      nav_dest("Sync")
      # Reset to NULL after brief delay so next click is detected
      shinyjs::delay(100, nav_dest(NULL))
    })

    observeEvent(input$logout, {
      auth_logout(state)
    })

    output$auth_widget <- renderUI({
      # Reactive dependencies — re-renders automatically when any changes
      auth_ok    <- isTRUE(state$AuthAuthenticated)
      role       <- state$AuthRole
      user_email <- state$AuthUser
      state$SyncVersion  # invalidation counter: sync push/pull increments this

      online <- is_cloud_connected(con)

      # ---- Badge (3 states) ----
      if (!auth_ok) {
        # Offline state: bright gold (#fcba19) with dark text for excellent contrast on #036
        badge <- actionLink(
          ns("go_auth"),
          span(
            class = "badge rounded-pill d-inline-flex align-items-center gap-1",
            style = "background-color: #fcba19; color: #1a1a1a; font-weight: 700; font-size: 0.85rem;",
            bsicons::bs_icon("wifi-off"), "Sign In"
          ),
          style = "text-decoration: none; cursor: pointer;"
        )
      } else if (identical(role, "admin")) {
        # Admin state: bright cyan with white text
        badge <- div(
          class = "d-inline-flex align-items-center gap-2",
          span(
            class = "badge rounded-pill d-inline-flex align-items-center gap-1",
            style = "background-color: #00d9ff; color: #ffffff; font-weight: 700; font-size: 0.85rem;",
            bsicons::bs_icon("shield-fill"), user_email
          ),
          actionLink(
            ns("logout"), 
            bsicons::bs_icon("box-arrow-right"),
            style = "color: #ffffff; font-size: 1.1rem; text-decoration: none; opacity: 0.9; transition: opacity 0.2s;"
          )
        )
      } else {
        # Guest state: bright lime green with white text
        badge <- div(
          class = "d-inline-flex align-items-center gap-2",
          span(
            class = "badge rounded-pill d-inline-flex align-items-center gap-1",
            style = "background-color: #2ecc71; color: #ffffff; font-weight: 700; font-size: 0.85rem;",
            bsicons::bs_icon("cloud"), user_email
          ),
          actionLink(
            ns("logout"), 
            bsicons::bs_icon("box-arrow-right"),
            style = "color: #ffffff; font-size: 1.1rem; text-decoration: none; opacity: 0.9; transition: opacity 0.2s;"
          )
        )
      }

      # ---- Sync line ----
      wm            <- tryCatch(sync_get_watermark(con, "env", "pull"), error = function(e) NULL)
      last_pull_str <- .format_time_ago(wm)

      if (online && !is.null(wm)) {
        # Count rows newer than last pull across all three core tables
        behind_n <- tryCatch({
          n_env <- DBI::dbGetQuery(
            con,
            "SELECT COUNT(*) AS n FROM master.core.env WHERE last_modified_utc > ?",
            list(wm)
          )$n
          n_su <- DBI::dbGetQuery(
            con,
            "SELECT COUNT(*) AS n FROM master.core.su WHERE last_modified_utc > ?",
            list(wm)
          )$n
          n_veg <- DBI::dbGetQuery(
            con,
            "SELECT COUNT(*) AS n FROM master.core.veg WHERE last_modified_utc > ?",
            list(wm)
          )$n
          n_env + n_su + n_veg
        }, error = function(e) NULL)

        behind_str <- if (!is.null(behind_n)) paste0("\u2193 ", behind_n, " behind \u00b7 ") else ""
        sync_label <- paste0(behind_str, "Last pull: ", last_pull_str)
      } else {
        # Offline — cannot query master; show last-pull time only
        sync_label <- paste0("Last pull: ", last_pull_str)
      }

      div(
        class = "d-flex flex-column align-items-end px-3",
        badge,
        div(
          class = "small mt-2",
          style = "color: #ffffff; opacity: 0.95;",
          sync_label, "\u00a0",
          actionLink(ns("go_sync"), "Sync \u2192", style = "color: #fcba19; font-weight: 600; text-decoration: none; font-size: 0.85rem;")
        )
      )
    })

    reactive(nav_dest())
  })
}

# Format a POSIXct timestamp as a human-readable "X ago" string.
# NULL or NA -> "never"; negative deltas (future ts) -> "just now".
.format_time_ago <- function(ts) {
  if (is.null(ts) || (length(ts) == 1L && is.na(ts))) return("never")
  secs <- as.numeric(difftime(Sys.time(), ts, units = "secs"))
  if (secs < 60)    return("just now")
  if (secs < 3600)  return(paste0(floor(secs / 60),   " min ago"))
  if (secs < 86400) return(paste0(floor(secs / 3600),  " hr ago"))
  paste0(floor(secs / 86400), " days ago")
}
