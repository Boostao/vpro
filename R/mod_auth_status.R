# Reactive auth status badge for the navbar.
#
# Triggered by state changes only — no polling via reactiveTimer.
# Returns a reactive() emitting "auth" when the user clicks the auth action link (NULL when idle).
# The parent app should observe this signal and call nav_select() accordingly.

mod_auth_status_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("auth_widget"))
}

.auth_role_palette <- function(role) {
  if (identical(role, "admin")) {
    list(
      icon = "shield-fill",
      background = "#e4f6ff",
      foreground = "#0c6f90",
      border = "#bfe3f1"
    )
  } else {
    list(
      icon = "cloud",
      background = "#e3f7ee",
      foreground = "#1d7a56",
      border = "#bee7d3"
    )
  }
}

auth_role_badge_ui <- function(role, label, input_id = NULL, ns = identity) {
  palette <- .auth_role_palette(role)
  badge <- span(
    class = "badge rounded-pill d-inline-flex align-items-center gap-1",
    style = paste(
      "background-color:", palette$background, ";",
      "color:", palette$foreground, ";",
      "border: 1px solid", palette$border, ";",
      "font-weight: 700; font-size: 0.85rem; padding: 0.48rem 0.78rem;"
    ),
    bsicons::bs_icon(palette$icon),
    label
  )

  if (is.null(input_id)) {
    return(badge)
  }

  actionLink(
    ns(input_id),
    badge,
    style = "text-decoration: none;"
  )
}

auth_logout_icon_ui <- function(input_id, ns = identity, color = "#5f7283") {
  actionLink(
    ns(input_id),
    bsicons::bs_icon("box-arrow-right"),
    style = paste(
      "color:", color, ";",
      "font-size: 1.05rem; text-decoration: none; line-height: 1;"
    )
  )
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
      nav_dest("Sync")
      # Reset to NULL after brief delay so next click is detected
      shinyjs::delay(100, nav_dest(NULL))
    })

    observeEvent(input$logout, {
      if (is_cloud_connected(con)) detach_db(con, "master")
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
        badge <- div(
          class = "d-inline-flex align-items-center gap-2",
          auth_role_badge_ui("admin", user_email, input_id = "go_auth", ns = ns),
          auth_logout_icon_ui("logout", ns = ns, color = "#0c6f90")
        )
      } else {
        badge <- div(
          class = "d-inline-flex align-items-center gap-2",
          auth_role_badge_ui("guest", user_email, input_id = "go_auth", ns = ns),
          auth_logout_icon_ui("logout", ns = ns, color = "#1d7a56")
        )
      }

      badge
    })

    reactive(nav_dest())
  })
}
