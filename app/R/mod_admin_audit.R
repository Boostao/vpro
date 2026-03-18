# =============================================================================
# mod_admin_audit.R — Audit Log sub-module
# =============================================================================

mod_admin_audit_ui <- function(id) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(
      textInput(ns("audit_project"),   "Project", value = ""),
      textInput(ns("audit_plot"),      "Plot",    value = ""),
      selectInput(ns("audit_table"),   "Table",   choices = c("All" = "")),
      dateInput(ns("audit_from"), "From", value = NULL),
      dateInput(ns("audit_to"),   "To",   value = NULL),
      selectInput(ns("audit_page_size"), "Page size", choices = c(25, 50, 100), selected = 25),
      checkboxInput(ns("audit_latest_only"), "Latest only", value = FALSE),
      actionButton(ns("audit_refresh"), "Refresh",        class = "btn-secondary w-100 mt-2"),
      actionButton(ns("audit_latest"),  "Jump to newest", class = "btn-outline-secondary w-100 mt-2"),
      downloadButton(ns("audit_export"), "Export CSV",    class = "btn-outline-primary w-100 mt-2")
    ),
    card(
      card_header("Audit Trail"),
      card_body(
        DTOutput(ns("audit_dt")),
        div(class = "mt-2 d-flex gap-2",
            actionButton(ns("audit_prev"), "Prev", class = "btn-outline-secondary"),
            actionButton(ns("audit_next"), "Next", class = "btn-outline-secondary"),
            textOutput(ns("audit_page_info"))
        )
      )
    )
  )
}

mod_admin_audit_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {

    rv_audit <- reactiveValues(page = 1L)

    observe({
      if (!audit_table_exists(con)) {
        updateSelectInput(session, "audit_table", choices = c("All" = ""))
        return()
      }
      table_col <- audit_table_name_col(con)
      if (is.null(table_col)) {
        updateSelectInput(session, "audit_table", choices = c("All" = ""))
        return()
      }
      table_col_sql <- quote_ident(table_col)
      sql <- sprintf(
        "SELECT DISTINCT %s AS table_name FROM user_db.main.USysAuditTrail ORDER BY %s",
        table_col_sql, table_col_sql)
      tables  <- dbGetQuery(con, sql)
      choices <- c("All" = "", setNames(tables$table_name, tables$table_name))
      updateSelectInput(session, "audit_table", choices = choices)
    })

    output$audit_dt <- renderDT({
      project_filter <- trimws(input$audit_project)
      plot_filter    <- trimws(input$audit_plot)
      table_filter   <- input$audit_table
      date_from      <- input$audit_from
      date_to        <- input$audit_to

      project_value <- if (nzchar(project_filter)) project_filter else NULL
      plot_value    <- if (nzchar(plot_filter))    plot_filter    else NULL
      table_value   <- if (!is.null(table_filter) && nzchar(table_filter)) table_filter else NULL
      from_value    <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
      to_value      <- if (!is.null(date_to)   && !is.na(date_to))   as.POSIXct(date_to)   else NULL

      page_size   <- as.integer(input$audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      latest_only <- isTRUE(input$audit_latest_only)
      offset      <- if (latest_only) 0L else (rv_audit$page - 1L) * page_size

      audit <- fetch_audit_entries(con,
        plot_number = plot_value,  project_id = project_value,
        table_name  = table_value,
        date_from   = from_value,  date_to    = to_value,
        limit       = page_size,   offset     = offset)
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = page_size, ordering = FALSE))
    })

    output$audit_export <- downloadHandler(
      filename = function() paste0("audit_log_", format(Sys.Date(), "%Y%m%d"), ".csv"),
      content  = function(file) {
        project_filter <- trimws(input$audit_project)
        plot_filter    <- trimws(input$audit_plot)
        table_filter   <- input$audit_table
        date_from      <- input$audit_from
        date_to        <- input$audit_to

        audit <- fetch_audit_entries(con,
          plot_number = if (nzchar(plot_filter))    plot_filter    else NULL,
          project_id  = if (nzchar(project_filter)) project_filter else NULL,
          table_name  = if (!is.null(table_filter) && nzchar(table_filter)) table_filter else NULL,
          date_from   = if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL,
          date_to     = if (!is.null(date_to)   && !is.na(date_to))   as.POSIXct(date_to)   else NULL)
        utils::write.csv(audit, file, row.names = FALSE)
      }
    )

    observeEvent(input$audit_refresh,   { rv_audit$page <- 1L })
    observeEvent(input$audit_page_size, { rv_audit$page <- 1L })

    observeEvent(input$audit_next, {
      if (isTRUE(input$audit_latest_only)) return()
      rv_audit$page <- rv_audit$page + 1L
    })

    observeEvent(input$audit_prev, {
      if (isTRUE(input$audit_latest_only)) return()
      rv_audit$page <- max(1L, rv_audit$page - 1L)
    })

    observeEvent(input$audit_latest, {
      updateCheckboxInput(session, "audit_latest_only", value = TRUE)
      rv_audit$page <- 1L
    })

    output$audit_page_info <- renderText({
      page_size <- as.integer(input$audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      if (isTRUE(input$audit_latest_only)) return(paste0("Latest ", page_size, " rows"))
      start_row <- (rv_audit$page - 1L) * page_size + 1L
      end_row   <- rv_audit$page * page_size
      paste0("Rows ", start_row, "-", end_row)
    })

    observeEvent(state$CurrProject, {
      if (is.null(state$CurrProject)) return()
      if (!nzchar(trimws(input$audit_project))) {
        updateTextInput(session, "audit_project", value = state$CurrProject)
      }
    })

    observeEvent(state$CurrSU, {
      if (is.null(state$CurrSU)) return()
      if (!nzchar(trimws(input$audit_plot))) {
        updateTextInput(session, "audit_plot", value = state$CurrSU)
      }
    })
  })
}
