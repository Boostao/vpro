mod_import_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Import"),
      layout_columns(
        fileInput(ns("import_file"), "CSV or ZIP", accept = c(".csv", ".zip")),
        selectInput(ns("target_table"), "Target Table", choices = NULL),
        actionButton(ns("import_analyze"), "Analyze", class = "btn-secondary"),
        actionButton(ns("import_apply"), "Import", class = "btn-primary"),
        col_widths = c(5, 3, 2, 2)
      ),
      verbatimTextOutput(ns("import_status")),
      DT::DTOutput(ns("import_preview")),
      DT::DTOutput(ns("import_compliance"))
    )
  )
}

mod_import_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(status = "", preview = NULL, target_fields = NULL, compliance = NULL)

    observe({
      tables <- DBI::dbListTables(con)
      tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]
      updateSelectInput(session, "target_table", choices = c("" = "", tables))
    })

    observeEvent(input$import_analyze, {
      req(input$import_file)

      file_path <- input$import_file$datapath
      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "csv") {
        tryCatch({
          rv$preview <- utils::read.csv(file_path, nrows = 100, stringsAsFactors = FALSE)
          status <- paste("Loaded", nrow(rv$preview), "rows from", file_name)

          if (!is.null(input$target_table) && nzchar(input$target_table)) {
            target_fields <- DBI::dbListFields(con, input$target_table)
            rv$target_fields <- target_fields
            missing_cols <- setdiff(target_fields, names(rv$preview))
            extra_cols <- setdiff(names(rv$preview), target_fields)

            if (length(missing_cols) > 0) {
              status <- paste0(status, " | Missing: ", paste(missing_cols, collapse = ", "))
            }
            if (length(extra_cols) > 0) {
              status <- paste0(status, " | Extra: ", paste(extra_cols, collapse = ", "))
            }
            if (length(missing_cols) == 0 && length(extra_cols) == 0) {
              status <- paste0(status, " | Columns match target")
            }
          }

          rv$status <- status
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

    observeEvent(input$import_apply, {
      req(rv$preview)
      req(input$target_table)

      if (is.null(rv$target_fields)) {
        rv$target_fields <- DBI::dbListFields(con, input$target_table)
      }

      missing_cols <- setdiff(rv$target_fields, names(rv$preview))
      extra_cols <- setdiff(names(rv$preview), rv$target_fields)

      if (length(missing_cols) > 0) {
        rv$status <- paste("Import blocked: missing columns", paste(missing_cols, collapse = ", "))
        return()
      }

      if (length(extra_cols) > 0) {
        rv$status <- paste("Import blocked: extra columns", paste(extra_cols, collapse = ", "))
        return()
      }

      tryCatch({
        DBI::dbAppendTable(con, input$target_table, rv$preview)
        rv$status <- paste("Imported", nrow(rv$preview), "rows into", input$target_table)
        rv$compliance <- run_compliance_checks(con, state$CurrProject)
      }, error = function(e) {
        rv$status <- paste("Import error:", e$message)
      })
    })

    output$import_status <- renderText({
      rv$status
    })

    output$import_preview <- DT::renderDT({
      req(rv$preview)
      DT::datatable(rv$preview, rownames = FALSE, options = list(pageLength = 10, ordering = FALSE))
    })

    output$import_compliance <- DT::renderDT({
      req(rv$compliance)
      DT::datatable(rv$compliance$detail_tibble, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })
  })
}
