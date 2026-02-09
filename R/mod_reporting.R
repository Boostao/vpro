
mod_reporting_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Reporting"),
      card_body(
        p("Generate Quarto reports for the current context."),
        selectInput(ns("report_template"), "Report Template", choices = NULL),
        radioButtons(ns("report_format"), "Format", choices = c("HTML" = "html", "PDF" = "pdf"), inline = TRUE),
        verbatimTextOutput(ns("report_ctx")),
        div(class="mt-3",
            actionButton(ns("preview_report"), "Preview HTML", class = "btn-secondary"),
            downloadButton(ns("dl_report"), "Generate Report", class="btn-lg btn-danger")
        ),
        uiOutput(ns("report_preview"))
      )
    )
  )
}

mod_reporting_server <- function(id, sys_state) {
  moduleServer(id, function(input, output, session) {
    observe({
      templates <- list.files(file.path(getwd(), "reports"), pattern = "\\.qmd$", full.names = FALSE)
      if (length(templates) == 0) {
        updateSelectInput(session, "report_template", choices = c("No templates found" = ""))
      } else {
        updateSelectInput(session, "report_template", choices = templates, selected = "site_summary.qmd")
      }
    })
    
    output$report_ctx <- renderText({
      req(sys_state$CurrSU)
      paste("Ready to generate report for Plot:", sys_state$CurrSU)
    })
    
    preview_path <- reactiveVal(NULL)

    observeEvent(input$preview_report, {
      req(sys_state$CurrSU)
      req(input$report_template)

      tmp_dir <- file.path(tempdir(), "report_preview")
      if (!dir.exists(tmp_dir)) dir.create(tmp_dir, recursive = TRUE)

      qmd_path <- file.path(getwd(), "reports", input$report_template)
      if (!file.exists(qmd_path)) {
        showNotification("Report template not found!", type = "error")
        return()
      }

      tmp_qmd <- file.path(tmp_dir, basename(input$report_template))
      file.copy(qmd_path, tmp_qmd, overwrite = TRUE)

      tryCatch({
        quarto::quarto_render(
          input = tmp_qmd,
          output_format = "html",
          execute_params = list(
            plot_number = as.character(sys_state$CurrSU),
            db_path = file.path(getwd(), "data", "vpro.duckdb")
          )
        )

        out_generated <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(input$report_template)), ".html"))
        if (file.exists(out_generated)) {
          preview_path(out_generated)
        } else {
          showNotification("Preview generation failed.", type = "error")
        }
      }, error = function(e) {
        showNotification(paste("Preview error:", e$message), type = "error")
      })
    })

    output$report_preview <- renderUI({
      preview_file <- preview_path()
      if (is.null(preview_file) || !file.exists(preview_file)) return(NULL)

      addResourcePath("report_preview", dirname(preview_file))
      tags$iframe(
        src = file.path("report_preview", basename(preview_file)),
        style = "width:100%; height:600px; border:1px solid #ccc;"
      )
    })

    output$dl_report <- downloadHandler(
      filename = function() {
        template_name <- tools::file_path_sans_ext(basename(input$report_template))
        ext <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format
        paste0(template_name, "_", sys_state$CurrSU, "_", Sys.Date(), ".", ext)
      },
      content = function(file) {
        req(sys_state$CurrSU)
        req(input$report_template)
        
        # Show Notification
        id <- showNotification("Generating Quarto Report...", duration = NULL, closeButton = FALSE)
        on.exit(removeNotification(id), add = TRUE)
        
        # Paths
        qmd_path <- file.path(getwd(), "reports", input$report_template)
        db_path <- file.path(getwd(), "data", "vpro.duckdb")
        
        # Validation
        if (!file.exists(qmd_path)) {
            showNotification("Report template not found!", type = "error")
            return(NULL)
        }
        
        # Render to temp file
        tmp_dir <- tempdir()
        tmp_qmd <- file.path(tmp_dir, "site_summary.qmd")
        file.copy(qmd_path, tmp_qmd, overwrite = TRUE)
        
        out_format <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format

        # Render
        # Note: Quarto generates output in the same dir as input by default
        quarto::quarto_render(
          input = tmp_qmd,
          output_format = out_format,
          execute_params = list(
            plot_number = as.character(sys_state$CurrSU),
            db_path = db_path
          )
        )
        
        # Result file
        out_generated <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(input$report_template)), ".", out_format))
        
        if (file.exists(out_generated)) {
            file.copy(out_generated, file)
        } else {
            showNotification("Report generation failed.", type = "error")
        }
      }
    )
    
  })
}
