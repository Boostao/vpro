# Module: User log
# Access parity: USysfrmUserLog — "VPro User Log"
# RecordSource: USysUserLog (User, InTime, OutTime, LocalMachine)
# Default view: tabular, showing only rows where OutTime IS NULL ("Show Current").
# Toggle: optShow with two options — "Show All" and "Show Current" (default).

mod_user_log_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    class = "h-100",
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center",
        shiny::tags$span(class = "fw-semibold", "VPro User Log"),
        shiny::tags$div(
          class = "d-flex gap-2 align-items-center",
          shiny::radioButtons(
            ns("optShow"), NULL,
            choices = c("Show Current" = "current", "Show All" = "all"),
            selected = "current", inline = TRUE
          ),
          shiny::actionButton(ns("btnCloseForm"), "Close", class = "btn btn-outline-secondary btn-sm")
        )
      )
    ),
    bslib::card_body(
      DT::DTOutput(ns("log_table")),
      shiny::textOutput(ns("status"))
    )
  )
}

mod_user_log_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    status_text <- shiny::reactiveVal("")

    log_data <- shiny::reactive({
      # Re-run when toggle changes
      show_mode <- input$optShow %||% "current"
      # USysUserLog lives in VPro64.db (attached as VPro64 in DuckDB)
      base_sql <- 'SELECT "User", "InTime", "OutTime", "LocalMachine" FROM "USysUserLog"'
      sql <- if (identical(show_mode, "current")) {
        paste(base_sql, 'WHERE "OutTime" IS NULL ORDER BY "InTime" DESC')
      } else {
        paste(base_sql, 'ORDER BY "InTime" DESC')
      }
      # Try VPro64-qualified first, then unqualified
      df <- tryCatch(
        DBI::dbGetQuery(con, sql),
        error = function(e) {
          sql2 <- gsub('"USysUserLog"', 'VPro64."USysUserLog"', sql, fixed = TRUE)
          tryCatch(DBI::dbGetQuery(con, sql2), error = function(e2) {
            status_text(paste("Could not load user log:", conditionMessage(e2)))
            data.frame(User = character(), InTime = character(),
                       OutTime = character(), LocalMachine = character(),
                       stringsAsFactors = FALSE)
          })
        }
      )
      status_text(sprintf("%d log entries.", nrow(df)))
      df
    })

    output$log_table <- DT::renderDT({
      df <- log_data()
      DT::datatable(
        df,
        colnames = c("User", "Login", "Logout", "Local Machine"),
        options = list(pageLength = 25, scrollX = TRUE),
        rownames = FALSE,
        selection = "none"
      )
    })

    observeEvent(input$btnCloseForm, {
      return_tab <- state$DataEntryReturnTab %||% "fs882_6x4"
      bslib::nav_select("main_tabs", return_tab, session = session$rootScope())
    })

    output$status <- shiny::renderText(status_text())
  })
}
