mod_auth_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("auth_panel"))
}

# con  — local DuckDB connection (always open; cloud PG is attached/detached here)
# state — reactive session state
mod_auth_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    auth_init_state(state)
    rv <- reactiveValues(
      login_status      = "",
      change_pass_msg   = "",
      grant_msg         = ""
    )

    output$auth_panel <- renderUI({
      if (auth_is_authenticated(state)) {
        tagList(
          p(class = "fw-bold",
            if (auth_is_admin(state)) "Admin:" else "Guest:",
            state$AuthUser
          ),
          actionButton(ns("auth_logout"), "Sign Out", class = "btn-outline-secondary btn-sm"),
          if (auth_is_admin(state)) tagList(
            hr(),
            card(
              card_header("Change Password"),
              passwordInput(ns("old_pass"),  "Current password"),
              passwordInput(ns("new_pass"),  "New password (min 8 chars)"),
              passwordInput(ns("new_pass2"), "Confirm new password"),
              actionButton(ns("change_pass"), "Update Password", class = "btn-warning btn-sm"),
              textOutput(ns("change_pass_status"))
            ),
            card(
              card_header("Grant Admin Access"),
              textInput(ns("grant_email"), "User email"),
              passwordInput(ns("grant_pass"), "Initial password (min 8 chars)"),
              actionButton(ns("grant_admin"), "Grant Admin", class = "btn-danger btn-sm"),
              textOutput(ns("grant_status"))
            )
          )
        )
      } else {
        tagList(
          p(class = "text-muted small", "Sign in to enable cloud sync"),
          navset_tab(
            id = ns("login_tabs"),
            nav_panel("Continue as Guest",
              div(class = "mt-3",
                textInput(ns("guest_email"), "Email"),
                textInput(ns("guest_name"),  "Full Name",
                          placeholder = "Optional"),
                actionButton(ns("guest_login"), "Continue", class = "btn-primary")
              )
            ),
            nav_panel("Admin Sign In",
              div(class = "mt-3",
                textInput(ns("admin_email"), "Email"),
                passwordInput(ns("admin_pass"), "Password"),
                actionButton(ns("admin_login"), "Sign In", class = "btn-primary")
              )
            )
          ),
          textOutput(ns("login_status"))
        )
      }
    })

    # ---- Guest login -----------------------------------------------------------
    # 1. Attach cloud as vpro_app (single password-protected role)
    # 2. Look up / create user in master.admin.users
    # 3. On failure: detach and show error
    observeEvent(input$guest_login, {
      req(input$guest_email)

      if (!is_cloud_connected(con)) {
        attached <- tryCatch({
          attach_cloud(con, fail_on_error = TRUE)
          TRUE
        }, error = function(e) {
          rv$login_status <- paste("Cannot connect to cloud database:", conditionMessage(e))
          FALSE
        })
        if (!isTRUE(attached)) return()
      }

      guest_name <- if (nzchar(trimws(input$guest_name %||% ""))) input$guest_name else NULL
      result <- tryCatch(
        auth_guest_login(con, state, input$guest_email, guest_name),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )

      if (!isTRUE(result$ok)) {
        detach_db(con, "master")
      }
      rv$login_status <- result$message %||% ""
    })

    # ---- Admin login -----------------------------------------------------------
    # 1. Attach cloud as vpro_app (single role; auth happens at R level via bcrypt)
    # 2. Verify credentials via auth_login (reads admin.users, checks bcrypt)
    # 3. On failure: detach and show error
    observeEvent(input$admin_login, {
      req(input$admin_email, input$admin_pass)

      if (!is_cloud_connected(con)) {
        attached <- tryCatch({
          attach_cloud(con, fail_on_error = TRUE)
          TRUE
        }, error = function(e) {
          rv$login_status <- paste("Cannot connect to cloud database:", conditionMessage(e))
          FALSE
        })
        if (!isTRUE(attached)) return()
      }

      result <- tryCatch(
        auth_login(con, state, input$admin_email, input$admin_pass),
        error = function(e) list(ok = FALSE, message = conditionMessage(e)),
        finally = {
          # Clear password input on every attempt for security
          updateTextInput(session, "admin_pass", value = "")
        }
      )

      if (!isTRUE(result$ok)) {
        detach_db(con, "master")
        rv$login_status <- result$message %||% "Authentication failed"
        return()
      }

      rv$login_status <- result$message %||% ""
    })

    # ---- Logout ----------------------------------------------------------------
    observeEvent(input$auth_logout, {
      if (is_cloud_connected(con)) detach_db(con, "master")
      auth_logout(state)
      rv$login_status <- ""
    })

    # ---- Change password (admin only) ------------------------------------------
    observeEvent(input$change_pass, {
      req(input$old_pass, input$new_pass, input$new_pass2)
      if (input$new_pass != input$new_pass2) {
        rv$change_pass_msg <- "New passwords do not match"
        return()
      }
      result <- tryCatch(
        auth_change_password(con, state, input$old_pass, input$new_pass),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )
      rv$change_pass_msg <- result$message
    })

    # ---- Grant admin -----------------------------------------------------------
    observeEvent(input$grant_admin, {
      req(input$grant_email, input$grant_pass)
      result <- tryCatch(
        auth_grant_admin(con, state, input$grant_email, input$grant_pass),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )
      rv$grant_msg <- result$message
    })

    output$login_status       <- renderText(rv$login_status)
    output$change_pass_status <- renderText(rv$change_pass_msg)
    output$grant_status       <- renderText(rv$grant_msg)
  })
}
