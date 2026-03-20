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
      profile_msg       = "",
      change_pass_msg   = "",
      grant_msg         = "",
      editing_field     = NULL
    )

    output$auth_panel <- renderUI({
      is_authenticated <- isTRUE(state$AuthAuthenticated)
      is_admin <- is_authenticated && identical(state$AuthRole, "admin")

      if (is_authenticated) {
        display_name <- trimws(as.character(state$AuthFullName %||% ""))
        if (!nzchar(display_name)) {
          display_name <- state$AuthUser %||% "Signed in"
        }

        name_is_editing <- identical(rv$editing_field, "name")
        email_is_editing <- identical(rv$editing_field, "email")
        role_badge <- auth_role_badge_ui(
          if (is_admin) "admin" else "guest",
          if (is_admin) "Admin" else "Guest"
        )

        div(
          class = "sync-auth-panel sync-auth-panel-ready",
          div(
            class = "sync-auth-header",
            div(
              class = "sync-auth-header-copy",
              span(class = "sync-auth-kicker", "Cloud account"),
              h4(class = "sync-auth-title", display_name),
              p(
                class = "sync-auth-note",
                if (is_admin) {
                  "Admin access is active. You can push, inspect merge requests, and review the queue from Sync."
                } else {
                  "Cloud sync is ready. You can push updates and track your merge requests from this page."
                }
              )
            ),
            div(
              class = "sync-auth-header-badge",
              actionLink(
                ns("auth_logout"),
                bsicons::bs_icon("box-arrow-right"),
                class = "sync-auth-logout-chip",
                `aria-label` = "Log out"
              )
            )
          ),
          div(
            class = "sync-auth-ready-grid",
            div(
              class = "sync-auth-ready-stat",
              div(
                class = "sync-auth-ready-stat-head",
                span(class = "sync-auth-ready-label", "Name"),
                if (!name_is_editing) {
                  actionLink(ns("edit_name"), bsicons::bs_icon("pencil-square"), class = "sync-auth-edit-link")
                }
              ),
              if (name_is_editing) {
                div(
                  class = "sync-auth-inline-editor",
                  textInput(ns("inline_name"), NULL, value = state$AuthFullName %||% ""),
                  div(
                    class = "sync-auth-inline-actions",
                    actionButton(ns("save_name_inline"), label = bsicons::bs_icon("check-lg"), class = "btn btn-sm btn-primary"),
                    actionButton(ns("cancel_profile_edit"), label = bsicons::bs_icon("x-lg"), class = "btn btn-sm btn-outline-secondary")
                  )
                )
              } else {
                span(class = "sync-auth-ready-value", display_name)
              }
            ),
            div(
              class = "sync-auth-ready-stat",
              div(
                class = "sync-auth-ready-stat-head",
                span(class = "sync-auth-ready-label", "Email"),
                if (!email_is_editing) {
                  actionLink(ns("edit_email"), bsicons::bs_icon("pencil-square"), class = "sync-auth-edit-link")
                }
              ),
              if (email_is_editing) {
                div(
                  class = "sync-auth-inline-editor",
                  textInput(ns("inline_email"), NULL, value = state$AuthUser %||% ""),
                  div(class = "sync-auth-inline-hint", "Enter a valid email address."),
                  div(
                    class = "sync-auth-inline-actions",
                    actionButton(ns("save_email_inline"), label = bsicons::bs_icon("check-lg"), class = "btn btn-sm btn-primary"),
                    actionButton(ns("cancel_profile_edit"), label = bsicons::bs_icon("x-lg"), class = "btn btn-sm btn-outline-secondary")
                  )
                )
              } else {
                span(class = "sync-auth-ready-value", state$AuthUser %||% "Signed in")
              }
            ),
            div(
              class = "sync-auth-ready-stat",
              div(
                class = "sync-auth-ready-stat-head",
                span(class = "sync-auth-ready-label", "Role")
              ),
              div(class = "sync-auth-role-value", role_badge),
              if (is_admin) {
                div(
                  class = "sync-auth-role-actions",
                  actionButton(ns("open_password_modal"), tagList(bsicons::bs_icon("key"), "Change password"), class = "btn btn-sm sync-auth-role-btn"),
                  actionButton(ns("open_access_modal"), tagList(bsicons::bs_icon("person-gear"), "Manage access"), class = "btn btn-sm sync-auth-role-btn")
                )
              }
            )
          ),
          div(class = "sync-auth-status-line", textOutput(ns("profile_status"), container = span))
        )
      } else {
        div(
          class = "sync-auth-panel",
          div(
            class = "sync-auth-header-copy",
            span(class = "sync-auth-kicker", "Authentication"),
            h4(class = "sync-auth-title", "Sign in to unlock cloud sync"),
            p(class = "sync-auth-note", "Guest sign-in is enough to create merge requests. Admin sign-in adds review and management capabilities.")
          ),
          bslib::navset_pill(
            id = ns("login_tabs"),
            bslib::nav_panel(
              title = "Continue as Guest",
              value = "guest",
              div(
                class = "sync-auth-form-grid mt-3",
                textInput(ns("guest_email"), "Email"),
                textInput(ns("guest_name"), "Full Name", placeholder = "Optional"),
                actionButton(ns("guest_login"), "Continue", class = "btn btn-primary sync-auth-submit")
              )
            ),
            bslib::nav_panel(
              title = "Admin Sign In",
              value = "admin",
              div(
                class = "sync-auth-form-grid mt-3",
                textInput(ns("admin_email"), "Email"),
                passwordInput(ns("admin_pass"), "Password"),
                actionButton(ns("admin_login"), "Sign In", class = "btn btn-primary sync-auth-submit")
              )
            )
          ),
          div(class = "sync-auth-status-line", textOutput(ns("login_status"), container = span))
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
      rv$profile_msg <- ""
      rv$change_pass_msg <- ""
      rv$grant_msg <- ""
      rv$editing_field <- NULL
    })

    observeEvent(input$edit_name, {
      rv$profile_msg <- ""
      rv$editing_field <- "name"
    }, ignoreInit = TRUE)

    observeEvent(input$edit_email, {
      rv$profile_msg <- ""
      rv$editing_field <- "email"
    }, ignoreInit = TRUE)

    observeEvent(input$cancel_profile_edit, {
      rv$editing_field <- NULL
      rv$profile_msg <- ""
    }, ignoreInit = TRUE)

    observeEvent(input$save_name_inline, {
      result <- tryCatch(
        auth_update_profile(con, state, state$AuthUser %||% "", input$inline_name %||% ""),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )
      rv$profile_msg <- result$message %||% ""
      if (isTRUE(result$ok)) {
        rv$editing_field <- NULL
      }
    }, ignoreInit = TRUE)

    observeEvent(input$save_email_inline, {
      req(input$inline_email)
      result <- tryCatch(
        auth_update_profile(con, state, input$inline_email, state$AuthFullName %||% ""),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )
      rv$profile_msg <- result$message %||% ""
      if (isTRUE(result$ok)) {
        rv$editing_field <- NULL
      }
    }, ignoreInit = TRUE)

    observeEvent(input$open_password_modal, {
      rv$change_pass_msg <- ""
      showModal(modalDialog(
        title = "Change password",
        passwordInput(ns("old_pass"), "Current password"),
        passwordInput(ns("new_pass"), "New password (min 8 chars)"),
        passwordInput(ns("new_pass2"), "Confirm new password"),
        div(class = "sync-auth-status-line", textOutput(ns("change_pass_status"), container = span)),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("change_pass"), "Update Password", class = "btn btn-primary")
        )
      ))
    }, ignoreInit = TRUE)

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
      if (isTRUE(result$ok)) {
        removeModal()
      }
    })

    observeEvent(input$open_access_modal, {
      rv$grant_msg <- ""
      showModal(modalDialog(
        title = "Grant admin access",
        textInput(ns("grant_email"), "User email"),
        passwordInput(ns("grant_pass"), "Initial password (min 8 chars)"),
        div(class = "sync-auth-status-line", textOutput(ns("grant_status"), container = span)),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("grant_admin"), "Grant Admin", class = "btn btn-primary")
        )
      ))
    }, ignoreInit = TRUE)

    # ---- Grant admin -----------------------------------------------------------
    observeEvent(input$grant_admin, {
      req(input$grant_email, input$grant_pass)
      result <- tryCatch(
        auth_grant_admin(con, state, input$grant_email, input$grant_pass),
        error = function(e) list(ok = FALSE, message = conditionMessage(e))
      )
      rv$grant_msg <- result$message
      if (isTRUE(result$ok)) {
        removeModal()
      }
    })

    output$login_status       <- renderText(rv$login_status)
    output$profile_status     <- renderText(rv$profile_msg)
    output$change_pass_status <- renderText(rv$change_pass_msg)
    output$grant_status       <- renderText(rv$grant_msg)
  })
}
