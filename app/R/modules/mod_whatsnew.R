mod_whatsnew_server <- function(id, con, open_trigger = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rv <- reactiveValues(rows = NULL, table_ref = NULL)

    find_whatsnew_table <- function() {
      tables <- tryCatch(
        DBI::dbGetQuery(
          con,
          "SELECT database_name, schema_name, table_name FROM duckdb_tables() WHERE lower(table_name) = lower('tblWhatsNew')"
        ),
        error = function(e) data.frame()
      )

      if (nrow(tables) == 0) {
        return(NULL)
      }

      preferred <- which(tolower(tables$database_name) == "vpro")[1]
      idx <- if (is.na(preferred)) 1 else preferred

      sprintf(
        "%s.%s.%s",
        tables$database_name[[idx]],
        tables$schema_name[[idx]],
        tables$table_name[[idx]]
      )
    }

    ensure_whatsnew_table <- function() {
      table_ref <- find_whatsnew_table()
      if (!is.null(table_ref)) {
        return(table_ref)
      }

      DBI::dbExecute(
        con,
        paste(
          "CREATE TABLE IF NOT EXISTS tblWhatsNew (",
          '"Date" TIMESTAMP,',
          '"Change" TEXT,',
          '"Viewed" BOOLEAN DEFAULT FALSE',
          ")"
        )
      )

      find_whatsnew_table()
    }

    fetch_whatsnew_rows <- function() {
      table_ref <- ensure_whatsnew_table()
      rv$table_ref <- table_ref

      if (is.null(table_ref)) {
        return(data.frame())
      }

      DBI::dbGetQuery(
        con,
        paste0(
          "SELECT rowid AS row_id, ",
          "COALESCE(",
          "TRY_CAST(\"Date\" AS TIMESTAMP), ",
          "TRY_STRPTIME(CAST(\"Date\" AS VARCHAR), '%m/%d/%Y %H:%M:%S'), ",
          "TRY_STRPTIME(CAST(\"Date\" AS VARCHAR), '%m/%d/%Y'), ",
          "TRY_STRPTIME(CAST(\"Date\" AS VARCHAR), '%Y-%m-%d %H:%M:%S'), ",
          "TRY_STRPTIME(CAST(\"Date\" AS VARCHAR), '%Y-%m-%d')",
          ") AS change_date, ",
          "CAST(\"Change\" AS VARCHAR) AS change_text, ",
          "COALESCE(CAST(\"Viewed\" AS BOOLEAN), FALSE) AS viewed ",
          "FROM ", table_ref, " ",
          "ORDER BY change_date DESC NULLS LAST, row_id DESC"
        )
      )
    }

    has_unviewed_rows <- function(rows) {
      if (is.null(rows) || nrow(rows) == 0) {
        return(FALSE)
      }
      any(!rows$viewed)
    }

    show_whatsnew_modal <- function(force = FALSE) {
      show_pref <- isTRUE(get_config_setting("Message", "ShowWhatsNew", default = TRUE))
      rows <- fetch_whatsnew_rows()
      rv$rows <- rows

      if (nrow(rows) == 0) {
        return(invisible(NULL))
      }

      if (!force && (!show_pref || !has_unviewed_rows(rows))) {
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
            "If there are unviewed changes, show this form when VPro starts",
            value = show_pref
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
      if (is.null(rows) || nrow(rows) == 0) {
        return(data.frame(
          Date = character(0),
          Change = character(0),
          Viewed = character(0),
          stringsAsFactors = FALSE
        ))
      }

      viewed_buttons <- vapply(
        seq_len(nrow(rows)),
        function(idx) {
          row_id <- rows$row_id[[idx]]
          viewed <- isTRUE(rows$viewed[[idx]])
          label <- if (viewed) "☑ Viewed" else "☐ Mark viewed"
          state <- if (viewed) "1" else "0"
          sprintf(
            "<button type='button' class='btn btn-link p-0 whatsnew-toggle' data-rowid='%s' data-viewed='%s'>%s</button>",
            row_id,
            state,
            label
          )
        },
        character(1)
      )

      data.frame(
        Date = ifelse(is.na(rows$change_date), "", as.character(rows$change_date)),
        Change = rows$change_text %||% "",
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
      req(!is.null(rv$table_ref))

      tryCatch({
        DBI::dbExecute(
          con,
          paste0('UPDATE ', rv$table_ref, ' SET "Viewed" = ? WHERE rowid = ?'),
          params = list(isTRUE(viewed_value), as.integer(row_id))
        )

        rows <- rv$rows
        if (!is.null(rows) && nrow(rows) > 0) {
          idx <- which(rows$row_id == as.integer(row_id))
          if (length(idx) == 1) {
            rows$viewed[[idx]] <- isTRUE(viewed_value)
            rv$rows <- rows
          }
        }
      }, error = function(e) {
        showNotification(
          paste("Unable to update Viewed flag:", conditionMessage(e)),
          type = "error"
        )
      })
    }

    observeEvent(input$toggle_viewed, {
      info <- input$toggle_viewed
      req(!is.null(info$rowid), !is.null(info$viewed))
      update_viewed_row(info$rowid, !isTRUE(info$viewed))
    })

    observeEvent(input$mark_all_viewed, {
      rows <- rv$rows
      req(!is.null(rows), nrow(rows) > 0)

      tryCatch({
        DBI::dbExecute(
          con,
          paste0('UPDATE ', rv$table_ref, ' SET "Viewed" = TRUE WHERE COALESCE(CAST("Viewed" AS BOOLEAN), FALSE) = FALSE')
        )

        rows$viewed <- rep(TRUE, nrow(rows))
        rv$rows <- rows
        showNotification("All updates marked as viewed.", type = "message")
      }, error = function(e) {
        showNotification(
          paste("Unable to mark all as viewed:", conditionMessage(e)),
          type = "error"
        )
      })
    })

    observeEvent(input$show_on_startup, {
      set_config_setting("Message", "ShowWhatsNew", isTRUE(input$show_on_startup))
    }, ignoreInit = TRUE)

    session$onFlushed(function() {
      show_whatsnew_modal(force = FALSE)
    }, once = TRUE)

    if (!is.null(open_trigger)) {
      observeEvent(open_trigger(), {
        show_whatsnew_modal(force = TRUE)
      }, ignoreInit = TRUE)
    }

    invisible(NULL)
  })
}