mod_hierarchy_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Hierarchy"),
      p("Hierarchy tools are under development."),
      verbatimTextOutput(ns("hier_status"))
    )
  )
}

mod_hierarchy_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    output$hier_status <- renderText({
      if (is.null(state$CurrProject)) {
        "Select a project to begin."
      } else {
        paste("Current project:", state$CurrProject)
      }
    })
  })
}
