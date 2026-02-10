mod_auth_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Authentication"),
      textInput(ns("auth_user"), "Username"),
      passwordInput(ns("auth_pass"), "Password"),
      div(
        class = "d-flex gap-2",
        actionButton(ns("auth_login"), "Sign In", class = "btn-primary"),
        actionButton(ns("auth_logout"), "Sign Out", class = "btn-outline-secondary")
      ),
      textOutput(ns("auth_status")),
      verbatimTextOutput(ns("auth_roles")),
      verbatimTextOutput(ns("auth_permissions"))
    )
  )
}

mod_auth_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    auth_init_state(state)
    rv <- reactiveValues(status = "Not authenticated")

    observeEvent(input$auth_login, {
      req(input$auth_user, input$auth_pass)
      result <- tryCatch({
        auth_login(con, state, input$auth_user, input$auth_pass)
      }, error = function(e) {
        list(ok = FALSE, message = e$message)
      })
      rv$status <- result$message
    })

    observeEvent(input$auth_logout, {
      auth_logout(state)
      rv$status <- "Signed out"
    })

    output$auth_status <- renderText({
      if (auth_is_authenticated(state)) {
        paste("Authenticated as", state$AuthUser)
      } else {
        rv$status
      }
    })

    output$auth_roles <- renderText({
      if (!auth_is_authenticated(state)) return("")
      roles <- state$AuthRoles %||% character(0)
      if (length(roles) == 0) "Roles: (none)" else paste("Roles:", paste(roles, collapse = ", "))
    })

    output$auth_permissions <- renderText({
      if (!auth_is_authenticated(state)) return("")
      perms <- state$AuthPermissions %||% character(0)
      if (length(perms) == 0) "Permissions: (none)" else paste("Permissions:", paste(perms, collapse = ", "))
    })
  })
}
