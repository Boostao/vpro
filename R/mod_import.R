mod_import_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Import"),
      layout_columns(
        fileInput(ns("import_file"), "CSV or ZIP", accept = c(".csv", ".zip")),
        actionButton(ns("import_analyze"), "Analyze", class = "btn-secondary"),
        col_widths = c(8, 4)
      ),
      verbatimTextOutput(ns("import_status")),
      DT::DTOutput(ns("import_preview"))
    )
  )
}

mod_import_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(status = "", preview = NULL)

    observeEvent(input$import_analyze, {
      req(input$import_file)

      file_path <- input$import_file$datapath
      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "csv") {
        tryCatch({
          rv$preview <- utils::read.csv(file_path, nrows = 100, stringsAsFactors = FALSE)
          rv$status <- paste("Loaded", nrow(rv$preview), "rows from", file_name)
        }, error = function(e) {
          rv$status <- paste("CSV read error:", e$message)
          rv$preview <- NULL
        })
        return()
      }

      if (ext == "zip") {
        tryCatch({
          listing <- utils::unzip(file_path, list = TRUE)
          rv$preview <- listing
          rv$status <- paste("ZIP contains", nrow(listing), "files")
        }, error = function(e) {
          rv$status <- paste("ZIP read error:", e$message)
          rv$preview <- NULL
        })
        return()
      }

      rv$status <- "Unsupported file type"
      rv$preview <- NULL
    })

    output$import_status <- renderText({
      rv$status
    })

    output$import_preview <- DT::renderDT({
      req(rv$preview)
      DT::datatable(rv$preview, rownames = FALSE, options = list(pageLength = 10, ordering = FALSE))
    })
  })
}
