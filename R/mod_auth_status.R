# Reactive auth status badge for the navbar.
#
# Triggered by state changes only — no polling via reactiveTimer.
# Returns a reactive() emitting "auth" when the user clicks the auth action link (NULL when idle).
# The parent app should observe this signal and call nav_select() accordingly.

mod_auth_status_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("auth_widget"))
}

#' @param id     Module id.
#' @param state  Reactive values carrying auth state.
#' @param con    DuckDB connection (cloud may or may not be attached).
#' @return       reactive() → "auth" | NULL
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

    observeEvent(input$logout, {
      auth_logout(state)
    })

    output$auth_widget <- renderUI({
      # Reactive dependencies — re-renders automatically when any changes
      auth_ok    <- isTRUE(state$AuthAuthenticated)
      role       <- state$AuthRole
      user_email <- state$AuthUser

      online <- is_cloud_connected(con)

      # ---- Badge (3 states) ----
      if (!auth_ok) {
        # Offline state: bright gold (#fcba19) with dark text for excellent contrast on #036
          badge <- actionLink(
            ns("go_auth"),
            span(
              class = "badge rounded-pill d-inline-flex align-items-center gap-1",
              style = "background-color: #ffffff; color: #1a1a1a; font-weight: 700; font-size: 0.85rem; border: 1px solid #ccc;",
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

      badge
    })

    reactive(nav_dest())
  })
}
