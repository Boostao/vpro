mod_merge_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Merge Review"),
      p("Review staged uploads and merge into core datasets."),
      verbatimTextOutput(ns("merge_status"))
    )
  )
}

mod_merge_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    output$merge_status <- renderText({
      if (is.null(state$CurrProject)) "Select a project to review." else "No staged uploads found."
    })
  })
}
