mod_whatsnew_server <- function(id, con, open_trigger = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rv <- reactiveValues(
      rows = data.frame(
        Date = character(0),
        Change = as.POSIXct(character(0)),
        Viewed = logical(0),
        stringsAsFactors = FALSE
      )
    )

    fetch_whatsnew_rows <- function() {
      db_query(con, paste(
        "SELECT rowid AS row_id,",
        "Date,",
        "Change,",
        "CAST(Viewed AS BOOLEAN) AS Viewed",
        "FROM tblWhatsNew",
        "ORDER BY Date DESC NULLS LAST, row_id DESC"
      ))
    }

    has_unviewed_rows <- function(rows) {
      if (!nrow(rows)) return(FALSE)
      any(!rows$Viewed)
    }

    show_whatsnew_modal <- function(force = FALSE) {
      rows <- rv$rows <- fetch_whatsnew_rows()

      if (!force && (!config("Message", "ShowWhatsNew") || !has_unviewed_rows(rows))) {
        return(invisible(NULL))
      }

      showModal(
        modalDialog(
          title = "What's New",
          easyClose = TRUE,
          size = "l",
          tags$p(
            class = "text-muted",
            "Latest updates are shown first. Click the Viewed toggle to mark items as read."
          ),
          DT::DTOutput(ns("whatsnew_table")),
          checkboxInput(
            ns("show_on_startup"),
            width = "100%",
            "If there are unviewed changes, show this form when VPro starts",
            value = config("Message", "ShowWhatsNew")
          ),
          footer = tagList(
            actionButton(ns("mark_all_viewed"), "Mark all as viewed", class = "btn-primary"),
            modalButton("Close")
          )
        )
      )
    }

    format_rows_for_display <- reactive({
      rows <- rv$rows
      viewed_buttons <- sprintf(
        "<button type='button' class='btn btn-link p-0 whatsnew-toggle' data-rowid='%s' data-viewed='%s'>%s</button>",
        rows$row_id,
        c("0", "1")[rows$Viewed + 1],
        c("☐ Mark viewed", "☑ Viewed")[rows$Viewed + 1]
      )
      data.frame(
        Date = as.character(rows$Date),
        Change = rows$Change,
        Viewed = viewed_buttons,
        stringsAsFactors = FALSE
      )
    })

    output$whatsnew_table <- DT::renderDT({
      DT::datatable(
        format_rows_for_display(),
        rownames = FALSE,
        escape = FALSE,
        options = list(
          dom = "t",
          ordering = FALSE,
          paging = FALSE,
          searching = FALSE,
          info = FALSE,
          autoWidth = TRUE,
          scrollY = "320px",
          scrollCollapse = TRUE,
          columnDefs = list(
            list(width = "165px", targets = 0),
            list(width = "130px", targets = 2),
            list(className = "dt-left", targets = c(0, 1, 2))
          )
        ),
        callback = DT::JS(
          sprintf(
            "table.on('click', '.whatsnew-toggle', function() {
               var btn = $(this);
               var rowid = parseInt(btn.data('rowid'), 10);
               var viewed = btn.data('viewed') === 1 || btn.data('viewed') === '1';
               Shiny.setInputValue('%s', {rowid: rowid, viewed: viewed}, {priority: 'event'});
             });",
            ns("toggle_viewed")
          )
        )
      )
    }, server = FALSE)

    update_viewed_row <- function(row_id, viewed_value) {
      db_run(con,
        'UPDATE tblWhatsNew SET "Viewed" = ? WHERE rowid = ?',
        params = list(isTRUE(viewed_value), as.integer(row_id))
      )
      rows <- rv$rows
      idx <- which(rows$row_id == as.integer(row_id))
      rows$Viewed[[idx]] <- isTRUE(viewed_value)
      rv$rows <- rows
    }

    observeEvent(input$toggle_viewed, {
      info <- input$toggle_viewed
      update_viewed_row(info$rowid, !isTRUE(info$viewed))
    })

    observeEvent(input$mark_all_viewed, {
      rows <- rv$rows
      db_run(con, 'UPDATE tblWhatsNew SET "Viewed" = TRUE;')
      rows$Viewed <- TRUE
      rv$rows <- rows
      showNotification("All updates marked as viewed.", type = "message")
    })

    observeEvent(input$show_on_startup, {
      config("Message", "ShowWhatsNew", input$show_on_startup)
    }, ignoreInit = TRUE)

    session$onFlushed(function() { show_whatsnew_modal() }, once = TRUE)

    if (!is.null(open_trigger)) {
      observeEvent(open_trigger(), {
        show_whatsnew_modal(force = TRUE)
      }, ignoreInit = TRUE)
    }

    invisible(NULL)
  })
}