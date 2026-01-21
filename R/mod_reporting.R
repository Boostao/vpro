
mod_reporting_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Site Summary Report"),
      card_body(
        p("Generate an HTML summary for the current Site Unit via Quarto."),
        verbatimTextOutput(ns("report_ctx")),
        div(class="mt-3",
            downloadButton(ns("dl_report"), "Generate HTML Report", class="btn-lg btn-danger")
        )
      )
    )
  )
}

mod_reporting_server <- function(id, sys_state) {
  moduleServer(id, function(input, output, session) {
    
    output$report_ctx <- renderText({
      req(sys_state$CurrSU)
      paste("Ready to generate report for Plot:", sys_state$CurrSU)
    })
    
    output$dl_report <- downloadHandler(
      filename = function() {
        paste0("SiteReport_", sys_state$CurrSU, "_", Sys.Date(), ".html")
      },
      content = function(file) {
        req(sys_state$CurrSU)
        
        # Show Notification
        id <- showNotification("Generating Quarto Report...", duration = NULL, closeButton = FALSE)
        on.exit(removeNotification(id), add = TRUE)
        
        # Paths
        qmd_path <- file.path(getwd(), "reports", "site_summary.qmd")
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
        
        # Render
        # Note: Quarto generates output in the same dir as input by default
        quarto::quarto_render(
            input = tmp_qmd,
            output_format = "html",
            execute_params = list(
                plot_number = as.character(sys_state$CurrSU),
                db_path = db_path
            )
        )
        
        # Result file
        out_generated <- file.path(tmp_dir, "site_summary.html")
        
        if (file.exists(out_generated)) {
            file.copy(out_generated, file)
        } else {
            showNotification("Report generation failed.", type = "error")
        }
      }
    )
    
  })
}
