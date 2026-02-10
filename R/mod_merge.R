mod_merge_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Merge Review"),
      p("Review staged uploads and merge into core datasets."),
      layout_columns(
        actionButton(ns("merge_refresh"), "Refresh", class = "btn-secondary"),
        selectInput(ns("merge_request"), "Merge request", choices = NULL),
        textAreaInput(ns("merge_notes"), "Review notes", value = "", rows = 2),
        actionButton(ns("merge_approve"), "Approve + Merge", class = "btn-primary"),
        actionButton(ns("merge_reject"), "Reject", class = "btn-outline-danger"),
        col_widths = c(1, 3, 4, 2, 2)
      ),
      textOutput(ns("merge_status")),
      DT::DTOutput(ns("merge_summary")),
      DT::DTOutput(ns("merge_counts")),
      tags$hr(),
      h5("Environment Preview"),
      DT::DTOutput(ns("merge_env_preview")),
      h5("Site Unit Preview"),
      DT::DTOutput(ns("merge_su_preview")),
      h5("Vegetation Preview"),
      DT::DTOutput(ns("merge_veg_preview"))
    )
  )
}

mod_merge_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(
      status = "",
      merge_requests = NULL,
      counts = NULL,
      diff_env = NULL,
      diff_su = NULL,
      diff_veg = NULL
    )

    refresh_requests <- function() {
      rv$status <- ""
      ready <- tryCatch({
        sync_require_cloud(con, allow_attach = TRUE)
        TRUE
      }, error = function(e) {
        rv$status <- paste("Cloud unavailable:", e$message)
        rv$merge_requests <- data.frame()
        updateSelectInput(session, "merge_request", choices = c("(none)" = ""), selected = "")
        FALSE
      })

      if (!isTRUE(ready)) return(invisible(FALSE))

      rv$merge_requests <- DBI::dbGetQuery(
        con,
        "SELECT id, project_id, submitter_user_id, submitted_utc, status, env_record_count, veg_record_count
         FROM master.admin.merge_requests
         WHERE status = 'pending_review'
         ORDER BY submitted_utc DESC"
      )

      choices <- if (is.null(rv$merge_requests) || nrow(rv$merge_requests) == 0) {
        c("(none)" = "")
      } else {
        setNames(rv$merge_requests$id, paste0("MR ", rv$merge_requests$id, " (", rv$merge_requests$project_id, ")"))
      }
      selected_value <- if (length(choices) > 0) unname(choices[1]) else ""
      updateSelectInput(session, "merge_request", choices = choices, selected = selected_value)
      invisible(TRUE)
    }

    observeEvent(input$merge_refresh, {
      refresh_requests()
    }, ignoreInit = TRUE)

    observe({
      if (is.null(rv$merge_requests)) {
        refresh_requests()
      }
    })

    observeEvent(input$merge_request, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()

      mr_id <- as.integer(input$merge_request)
      rv$counts <- data.frame(
        table = c("sample_env", "sample_su", "sample_veg"),
        rows = c(
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_env WHERE merge_request_id = ?", list(mr_id))$n[1],
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_su WHERE merge_request_id = ?", list(mr_id))$n[1],
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_veg WHERE merge_request_id = ?", list(mr_id))$n[1]
        ),
        stringsAsFactors = FALSE
      )

      rv$diff_env <- DBI::dbGetQuery(
        con,
        "SELECT
           s.plot_number,
           s.project_id,
           s.latitude AS staged_latitude,
           c.latitude AS core_latitude,
           s.longitude AS staged_longitude,
           c.longitude AS core_longitude,
           s.elevation_m AS staged_elevation_m,
           c.elevation_m AS core_elevation_m,
           s.survey_date AS staged_survey_date,
           c.survey_date AS core_survey_date,
           s.surveyor_name AS staged_surveyor_name,
           c.surveyor_name AS core_surveyor_name,
           s.plot_notes AS staged_plot_notes,
           c.plot_notes AS core_plot_notes
         FROM master.staging.sample_env s
         LEFT JOIN master.core.sample_env c
           ON c.plot_number = s.plot_number
         WHERE s.merge_request_id = ?",
        list(mr_id)
      )

      rv$diff_su <- DBI::dbGetQuery(
        con,
        "SELECT
           s.plot_number,
           s.project_id,
           s.su_number AS staged_su_number,
           c.su_number AS core_su_number,
           s.bec_zone AS staged_bec_zone,
           c.bec_zone AS core_bec_zone,
           s.bec_subzone AS staged_bec_subzone,
           c.bec_subzone AS core_bec_subzone,
           s.site_series AS staged_site_series,
           c.site_series AS core_site_series
         FROM master.staging.sample_su s
         LEFT JOIN master.core.sample_su c
           ON c.plot_number = s.plot_number
         WHERE s.merge_request_id = ?",
        list(mr_id)
      )

      rv$diff_veg <- DBI::dbGetQuery(
        con,
        "SELECT
           s.plot_number,
           s.project_id,
           s.species_code,
           s.layer_code,
           s.cover1 AS staged_cover1,
           c.cover1 AS core_cover1,
           s.cover2 AS staged_cover2,
           c.cover2 AS core_cover2,
           s.cover3 AS staged_cover3,
           c.cover3 AS core_cover3,
           s.totala AS staged_totala,
           c.totala AS core_totala,
           s.totalb AS staged_totalb,
           c.totalb AS core_totalb
         FROM master.staging.sample_veg s
         LEFT JOIN master.core.sample_veg c
           ON c.plot_number = s.plot_number
          AND c.species_code = s.species_code
          AND c.layer_code = s.layer_code
          AND c.project_id = s.project_id
         WHERE s.merge_request_id = ?",
        list(mr_id)
      )
    })

    observeEvent(input$merge_approve, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()
      sync_require_cloud(con, allow_attach = TRUE)
      auth_init_state(state)
      tryCatch({
        auth_require_permission(state, "approve:merge_requests")
      }, error = function(e) {
        rv$status <- e$message
        return()
      })
      mr_id <- as.integer(input$merge_request)
      reviewer <- Sys.getenv("USER", "unknown")
      tryCatch({
        merge_approve_request(con, mr_id, reviewer, input$merge_notes)
        rv$status <- paste("Merged request", mr_id)
        refresh_requests()
      }, error = function(e) {
        rv$status <- paste("Merge failed:", e$message)
      })
    })

    observeEvent(input$merge_reject, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()
      sync_require_cloud(con, allow_attach = TRUE)
      auth_init_state(state)
      tryCatch({
        auth_require_permission(state, "approve:merge_requests")
      }, error = function(e) {
        rv$status <- e$message
        return()
      })
      mr_id <- as.integer(input$merge_request)
      reviewer <- Sys.getenv("USER", "unknown")
      tryCatch({
        DBI::dbExecute(
          con,
          "UPDATE master.admin.merge_requests
           SET status = 'rejected', reviewer_user_id = ?, review_notes = ?, reviewed_utc = now()
           WHERE id = ?",
          list(reviewer, input$merge_notes, mr_id)
        )
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_env WHERE merge_request_id = ?", list(mr_id))
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_su WHERE merge_request_id = ?", list(mr_id))
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_veg WHERE merge_request_id = ?", list(mr_id))
        rv$status <- paste("Rejected request", mr_id)
        refresh_requests()
      }, error = function(e) {
        rv$status <- paste("Reject failed:", e$message)
      })
    })

    output$merge_status <- renderText({
      if (nzchar(rv$status)) rv$status else "No pending merge requests."
    })

    output$merge_summary <- DT::renderDT({
      req(rv$merge_requests)
      DT::datatable(rv$merge_requests, rownames = FALSE, options = list(pageLength = 6))
    })

    output$merge_counts <- DT::renderDT({
      req(rv$counts)
      DT::datatable(rv$counts, rownames = FALSE, options = list(pageLength = 6, ordering = FALSE))
    })

    output$merge_env_preview <- DT::renderDT({
      req(rv$diff_env)
      if (nrow(rv$diff_env) == 0) return(NULL)
      DT::datatable(rv$diff_env, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
    })

    output$merge_su_preview <- DT::renderDT({
      req(rv$diff_su)
      if (nrow(rv$diff_su) == 0) return(NULL)
      DT::datatable(rv$diff_su, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
    })

    output$merge_veg_preview <- DT::renderDT({
      req(rv$diff_veg)
      if (nrow(rv$diff_veg) == 0) return(NULL)
      DT::datatable(rv$diff_veg, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
    })
  })
}
