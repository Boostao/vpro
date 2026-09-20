# =============================================================================
# mod_admin_merge.R — Merge Review sub-module (absorbed from mod_merge.R)
# Depends on merge_ensure_tables(con) from logic_sync.R.
# =============================================================================

mod_admin_merge_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      class = "sync-admin-merge-review",
      full_screen = TRUE,
      card_header("Merge Review"),
      tags$p("Review staged uploads, resolve conflicts, and merge into core datasets."),
      layout_columns(
        actionButton(ns("merge_refresh"),  "Refresh",        class = "btn-secondary"),
        selectInput( ns("merge_request"),  "Merge request",  choices = NULL),
        textAreaInput(ns("merge_notes"),   "Review notes",   value = "", rows = 2),
        uiOutput(ns("merge_actions")),
        col_widths = c(1, 3, 4, 4)
      ),
      textOutput(ns("merge_status")),
      textOutput(ns("merge_compliance_status")),
      textOutput(ns("merge_summary_row")),
      DT::DTOutput(ns("merge_compliance")),
      DT::DTOutput(ns("merge_summary")),
      DT::DTOutput(ns("merge_counts")),
      tags$hr(),
      tags$h5("Conflicts"),
      textOutput(ns("merge_conflict_status")),
      layout_columns(
        actionButton(ns("merge_conflicts_refresh"),    "Refresh conflicts", class = "btn-secondary"),
        actionButton(ns("merge_conflict_keep_staged"), "Use staged",        class = "btn-primary"),
        actionButton(ns("merge_conflict_keep_core"),   "Keep core",         class = "btn-secondary"),
        actionButton(ns("merge_conflict_dismiss"),     "Dismiss",           class = "btn-outline-secondary"),
        col_widths = c(2, 2, 2, 2)
      ),
      DT::DTOutput(ns("merge_conflicts")),
      tags$hr(),
      tags$h5("Environment Preview"),
      DT::DTOutput(ns("merge_env_preview")),
      tags$h5("Site Unit Preview"),
      DT::DTOutput(ns("merge_su_preview")),
      tags$h5("Vegetation Preview"),
      DT::DTOutput(ns("merge_veg_preview"))
    )
  )
}

mod_admin_merge_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      status            = "",
      merge_requests    = NULL,
      counts            = NULL,
      diff_env          = NULL,
      diff_su           = NULL,
      diff_veg          = NULL,
      compliance        = NULL,
      compliance_status = "",
      compliance_passed = NA,
      conflicts         = NULL,
      conflict_status   = ""
    )

    refresh_requests <- function() {
      rv$status <- ""
      ready <- tryCatch({
        sync_require_cloud(con, allow_attach = TRUE)
        TRUE
      }, error = function(e) {
        rv$status        <- paste("Cloud unavailable:", e$message)
        rv$merge_requests <- data.frame()
        updateSelectInput(session, "merge_request", choices = c("(none)" = ""), selected = "")
        FALSE
      })
      if (!isTRUE(ready)) return(invisible(FALSE))

      loaded <- tryCatch({
        merge_ensure_tables(con)

        rv$merge_requests <- DBI::dbGetQuery(con,
          "SELECT id, project_id, submitter_user_id, submitted_utc, status,
                  env_record_count, su_record_count, veg_record_count,
                  compliance_passed, compliance_report
           FROM master.admin.merge_requests
           WHERE status = 'pending_review'
           ORDER BY submitted_utc DESC")
        TRUE
      }, error = function(e) {
        rv$status <- paste("Merge review unavailable:", conditionMessage(e))
        rv$merge_requests <- data.frame()
        updateSelectInput(session, "merge_request", choices = c("(none)" = ""), selected = "")
        FALSE
      })
      if (!isTRUE(loaded)) return(invisible(FALSE))

      choices <- if (is.null(rv$merge_requests) || nrow(rv$merge_requests) == 0) {
        c("(none)" = "")
      } else {
        setNames(rv$merge_requests$id,
                 paste0("MR ", rv$merge_requests$id, " (", rv$merge_requests$project_id, ")"))
      }
      selected_value <- if (length(choices) > 0) unname(choices[1]) else ""
      updateSelectInput(session, "merge_request", choices = choices, selected = selected_value)
      invisible(TRUE)
    }

    observeEvent(input$merge_refresh, { refresh_requests() }, ignoreInit = TRUE)

    observe({
      if (isTRUE(auth_is_admin(state)) && is.null(rv$merge_requests)) refresh_requests()
    })

    observeEvent(list(state$AuthAuthenticated, state$AuthRole), {
      if (isTRUE(state$AuthAuthenticated) && identical(state$AuthRole, "admin")) {
        refresh_requests()
      } else {
        rv$status <- ""
        rv$merge_requests <- NULL
        rv$counts <- NULL
        rv$diff_env <- NULL
        rv$diff_su <- NULL
        rv$diff_veg <- NULL
        rv$compliance <- NULL
        rv$compliance_status <- ""
        rv$compliance_passed <- NA
        rv$conflicts <- NULL
        rv$conflict_status <- ""
        updateSelectInput(session, "merge_request", choices = c("(none)" = ""), selected = "")
      }
    }, ignoreInit = TRUE)

    observeEvent(input$merge_request, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()

      mr_id  <- as.integer(input$merge_request)
      mr_row <- rv$merge_requests[rv$merge_requests$id == mr_id, , drop = FALSE]

      compliance_report <- NULL
      if (nrow(mr_row) > 0) {
        if (isTRUE(mr_row$compliance_passed[1])) {
          rv$compliance_status <- "Compliance passed"
          rv$compliance_passed <- TRUE
        } else if (!is.na(mr_row$compliance_passed[1]) && !isTRUE(mr_row$compliance_passed[1])) {
          rv$compliance_status <- "Compliance failed"
          rv$compliance_passed <- FALSE
        } else {
          rv$compliance_status <- "Compliance not evaluated"
          rv$compliance_passed <- NA
        }
        compliance_report <- mr_row$compliance_report[1]
      }

      if (!is.null(compliance_report) && nzchar(as.character(compliance_report)) &&
          requireNamespace("jsonlite", quietly = TRUE)) {
        parsed <- tryCatch(jsonlite::fromJSON(compliance_report), error = function(e) NULL)
        rv$compliance <- if (!is.null(parsed) && !is.null(parsed$details)) parsed$details else NULL
      } else {
        rv$compliance <- NULL
      }

      rv$counts <- data.frame(
        table = c("sample_env", "sample_su", "sample_veg"),
        rows  = c(
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_env WHERE merge_request_id = ?", list(mr_id))$n[1],
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_su  WHERE merge_request_id = ?", list(mr_id))$n[1],
          DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM master.staging.sample_veg WHERE merge_request_id = ?", list(mr_id))$n[1]
        ),
        stringsAsFactors = FALSE
      )

      rv$conflict_status <- ""
      rv$conflicts       <- NULL
      tryCatch({
        merge_request_refresh_conflicts(con, mr_id)
        rv$conflicts <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
        rv$conflict_status <- if (nrow(rv$conflicts) == 0) "No conflicts." else
          paste(nrow(rv$conflicts), "conflict(s) need resolution.")
      }, error = function(e) {
        rv$conflict_status <- paste("Conflict refresh failed:", e$message)
        rv$conflicts       <- data.frame()
      })

      rv$diff_env <- DBI::dbGetQuery(con,
        "SELECT s.plot_number, s.project_id,
                s.latitude AS staged_latitude, c.latitude AS core_latitude,
                s.longitude AS staged_longitude, c.longitude AS core_longitude,
                s.elevation_m AS staged_elevation_m, c.elevation_m AS core_elevation_m,
                s.survey_date AS staged_survey_date, c.survey_date AS core_survey_date,
                s.surveyor_name AS staged_surveyor_name, c.surveyor_name AS core_surveyor_name,
                s.plot_notes AS staged_plot_notes, c.plot_notes AS core_plot_notes
         FROM master.staging.sample_env s
         LEFT JOIN master.core.sample_env c ON c.plot_number = s.plot_number
         WHERE s.merge_request_id = ?", list(mr_id))

      rv$diff_su <- DBI::dbGetQuery(con,
        "SELECT s.plot_number, s.project_id,
                s.su_number AS staged_su_number, c.su_number AS core_su_number,
                s.bec_zone AS staged_bec_zone, c.bec_zone AS core_bec_zone,
                s.bec_subzone AS staged_bec_subzone, c.bec_subzone AS core_bec_subzone,
                s.site_series AS staged_site_series, c.site_series AS core_site_series
         FROM master.staging.sample_su s
         LEFT JOIN master.core.sample_su c ON c.plot_number = s.plot_number
         WHERE s.merge_request_id = ?", list(mr_id))

      rv$diff_veg <- DBI::dbGetQuery(con,
        "SELECT s.plot_number, s.project_id,
                s.species_code, s.layer_code,
                s.cover1 AS staged_cover1, c.cover1 AS core_cover1,
                s.cover2 AS staged_cover2, c.cover2 AS core_cover2,
                s.cover3 AS staged_cover3, c.cover3 AS core_cover3,
                s.totala AS staged_totala, c.totala AS core_totala,
                s.totalb AS staged_totalb, c.totalb AS core_totalb
         FROM master.staging.sample_veg s
         LEFT JOIN master.core.sample_veg c
           ON c.plot_number = s.plot_number AND c.species_code = s.species_code
          AND c.layer_code = s.layer_code AND c.project_id = s.project_id
         WHERE s.merge_request_id = ?", list(mr_id))
    })

    observeEvent(input$merge_approve, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()
      if (isFALSE(rv$compliance_passed)) {
        rv$status <- "Merge blocked: compliance failed."
        return()
      }
      sync_require_cloud(con, allow_attach = TRUE)
      auth_init_state(state)
      tryCatch({ auth_require_permission(state, "approve:merge_requests") },
               error = function(e) { rv$status <- e$message; return() })

      mr_id <- as.integer(input$merge_request)
      tryCatch({
        merge_request_refresh_conflicts(con, mr_id)
        unresolved <- merge_request_unresolved_conflict_count(con, mr_id)
        if (unresolved > 0) {
          rv$status        <- paste("Merge blocked:", unresolved, "unresolved conflict(s). Resolve conflicts first.")
          rv$conflicts     <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
          rv$conflict_status <- rv$status
          return()
        }
      }, error = function(e) { rv$status <- paste("Conflict check failed:", e$message); return() })

      reviewer <- Sys.getenv("USER", "unknown")
      tryCatch({
        merge_approve_request(con, mr_id, reviewer, input$merge_notes)
        rv$status <- paste("Merged request", mr_id)
        refresh_requests()
      }, error = function(e) { rv$status <- paste("Merge failed:", e$message) })
    })

    observeEvent(input$merge_reject, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()
      sync_require_cloud(con, allow_attach = TRUE)
      auth_init_state(state)
      tryCatch({ auth_require_permission(state, "approve:merge_requests") },
               error = function(e) { rv$status <- e$message; return() })

      mr_id    <- as.integer(input$merge_request)
      reviewer <- Sys.getenv("USER", "unknown")
      tryCatch({
        merge_reject_request(con, mr_id, reviewer, input$merge_notes)
        rv$status <- paste("Rejected request", mr_id)
        refresh_requests()
      }, error = function(e) { rv$status <- paste("Reject failed:", e$message) })
    })

    observeEvent(input$merge_conflicts_refresh, {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return()
      mr_id <- as.integer(input$merge_request)
      tryCatch({
        merge_request_refresh_conflicts(con, mr_id)
        rv$conflicts       <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
        rv$conflict_status <- if (nrow(rv$conflicts) == 0) "No conflicts." else
          paste(nrow(rv$conflicts), "conflict(s) need resolution.")
      }, error = function(e) { rv$conflict_status <- paste("Conflict refresh failed:", e$message) })
    }, ignoreInit = TRUE)

    resolve_selected_conflict <- function(resolution) {
      req(input$merge_request)
      if (!nzchar(input$merge_request)) return(invisible(FALSE))
      if (is.null(input$merge_conflicts_rows_selected) || length(input$merge_conflicts_rows_selected) == 0) {
        rv$conflict_status <- "Select a conflict row first."
        return(invisible(FALSE))
      }
      row_idx     <- input$merge_conflicts_rows_selected[1]
      if (is.null(rv$conflicts) || nrow(rv$conflicts) < row_idx) return(invisible(FALSE))
      conflict_id <- rv$conflicts$id[row_idx]
      actor       <- Sys.getenv("USER", "unknown")
      merge_request_resolve_conflict(con, conflict_id, resolution, actor = actor)
      mr_id <- as.integer(input$merge_request)
      rv$conflicts       <- merge_request_get_conflicts(con, mr_id, unresolved_only = TRUE)
      rv$conflict_status <- if (nrow(rv$conflicts) == 0) "No conflicts." else
        paste(nrow(rv$conflicts), "conflict(s) need resolution.")
      invisible(TRUE)
    }

    observeEvent(input$merge_conflict_keep_staged, { resolve_selected_conflict("keep_staged") }, ignoreInit = TRUE)
    observeEvent(input$merge_conflict_keep_core,   { resolve_selected_conflict("keep_core")   }, ignoreInit = TRUE)
    observeEvent(input$merge_conflict_dismiss,     { resolve_selected_conflict("dismiss")     }, ignoreInit = TRUE)

    output$merge_status <- renderText({
      if (nzchar(rv$status)) rv$status else "No pending merge requests."
    })
    output$merge_conflict_status    <- renderText({ rv$conflict_status })
    output$merge_compliance_status  <- renderText({ rv$compliance_status })

    output$merge_compliance <- DT::renderDT({
      if (is.null(rv$compliance) || nrow(rv$compliance) == 0) return(NULL)
      DT::datatable(rv$compliance, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
    })

    output$merge_summary_row <- renderText({
      req(rv$merge_requests, input$merge_request)
      if (!nzchar(input$merge_request)) return("")
      mr_id  <- as.integer(input$merge_request)
      mr_row <- rv$merge_requests[rv$merge_requests$id == mr_id, , drop = FALSE]
      if (nrow(mr_row) == 0) return("")
      submitted      <- mr_row$submitted_utc[1]
      submitted_text <- if (!is.null(submitted) && nzchar(as.character(submitted))) as.character(submitted) else ""
      paste("Project:", mr_row$project_id[1],
            "| Submitter:", mr_row$submitter_user_id[1],
            "| Submitted:", submitted_text,
            "| Env:", mr_row$env_record_count[1],
            "| Veg:", mr_row$veg_record_count[1])
    })

    output$merge_actions <- renderUI({
      disabled <- isFALSE(rv$compliance_passed)
      tagList(
        actionButton(ns("merge_approve"), "Approve + Merge",
                     class    = if (disabled) "btn-secondary" else "btn-primary",
                     disabled = disabled),
        actionButton(ns("merge_reject"), "Reject", class = "btn-outline-danger")
      )
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
    output$merge_conflicts <- DT::renderDT({
      req(rv$conflicts)
      if (is.null(rv$conflicts) || nrow(rv$conflicts) == 0) return(NULL)
      DT::datatable(rv$conflicts, rownames = FALSE, selection = "single",
                    options = list(pageLength = 8, scrollX = TRUE))
    })
  })
}
