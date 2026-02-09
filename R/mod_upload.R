mod_upload_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Upload"),
      p("Upload and stage datasets for review."),
      fileInput(ns("upload_file"), "Dataset", accept = c(".csv", ".zip")),
      actionButton(ns("upload_analyze"), "Analyze", class = "btn-secondary"),
      verbatimTextOutput(ns("upload_status"))
    )
  )
}

mod_upload_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(status = "")

    observeEvent(input$upload_analyze, {
      req(input$upload_file)
      rv$status <- paste("Ready to stage:", input$upload_file$name)
    })

    output$upload_status <- renderText({
      rv$status
    })
  })
}
