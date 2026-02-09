mod_auth_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Authentication"),
      textInput(ns("auth_user"), "Username"),
      passwordInput(ns("auth_pass"), "Password"),
      actionButton(ns("auth_login"), "Sign In", class = "btn-primary"),
      verbatimTextOutput(ns("auth_status"))
    )
  )
}

mod_auth_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(status = "Not authenticated")

    observeEvent(input$auth_login, {
      rv$status <- "Auth not configured yet"
    })

    output$auth_status <- renderText({
      rv$status
    })
  })
}
