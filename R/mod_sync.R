# =============================================================================
# mod_sync.R
# Field-user sync module: view local changes, pull from master, push to staging,
# view own merge requests. Full-blocking conflict modal when queue is non-empty.
# =============================================================================

# ── UI ────────────────────────────────────────────────────────────────────────

mod_sync_ui <- function(id) {
  ns <- NS(id)

  bslib::navset_card_tab(
    id = ns("sync_tabs"),

    # ── Tab 1: Changes ────────────────────────────────────────────────────────
    bslib::nav_panel(
      title = "Changes",
      value = "changes",

      # Action bar
      div(
        class = "d-flex align-items-center gap-2 flex-wrap mb-3 mt-1",
        uiOutput(ns("project_badge")),
        uiOutput(ns("pull_count_badge")),
        uiOutput(ns("btn_pull_ui")),
        actionButton(
          ns("sync_push"),
          label = tagList(icon("cloud-arrow-up"), "Push changes"),
          class = "btn btn-success btn-sm"
        ),
        actionButton(
          ns("sync_refresh"),
          label = tagList(icon("rotate"), "Refresh"),
          class = "btn btn-outline-secondary btn-sm"
        )
      ),

      # Status message
      uiOutput(ns("sync_status")),

      # Accordions for each table
      bslib::accordion(
        id = ns("acc_changes"),
        open = FALSE,
        bslib::accordion_panel(
          title = tagList(icon("mountain"), " Environment"),
          value = "env",
          DT::dataTableOutput(ns("tbl_env_changes"))
        ),
        bslib::accordion_panel(
          title = tagList(icon("layer-group"), " Site Units"),
          value = "su",
          DT::dataTableOutput(ns("tbl_su_changes"))
        ),
        bslib::accordion_panel(
          title = tagList(icon("leaf"), " Vegetation"),
          value = "veg",
          DT::dataTableOutput(ns("tbl_veg_changes"))
        )
      )
    ),

    # ── Tab 2: Merge Requests ─────────────────────────────────────────────────
    bslib::nav_panel(
      title = "Merge Requests",
      value = "merge_requests",

      div(
        class = "d-flex align-items-center gap-3 flex-wrap mb-3 mt-1",
        checkboxInput(ns("hide_approved"), "Hide approved/merged", value = FALSE),
        checkboxInput(ns("hide_rejected"), "Hide rejected",        value = FALSE),
        actionButton(
          ns("mr_refresh"),
          label = tagList(icon("rotate"), "Refresh"),
          class = "btn btn-outline-secondary btn-sm"
        )
      ),

      DT::dataTableOutput(ns("tbl_mrs")),

      # Detail panel — revealed on row click
      uiOutput(ns("mr_detail"))
    )
  )
}


# ── Server ────────────────────────────────────────────────────────────────────

mod_sync_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Invalidation signals ─────────────────────────────────────────────────
    # rv_refresh: incremented by Refresh button and push/pull success
    rv_refresh   <- reactiveVal(0L)
    # rv_mr_reload: also incremented after push to force MR list refresh
    rv_mr_reload <- reactiveVal(0L)

    observeEvent(input$sync_refresh, rv_refresh(rv_refresh() + 1L))
    observeEvent(input$mr_refresh,   rv_mr_reload(rv_mr_reload() + 1L))

    # Also refresh incoming count whenever the Sync tab is navigated to
    observeEvent(state$SyncTabActivated, {
      rv_refresh(rv_refresh() + 1L)
    }, ignoreInit = TRUE)


    # ── Conflict modal (global blocking) ─────────────────────────────────────
    # Check on startup and whenever SyncVersion changes.
    conflict_modal_shown <- reactiveVal(FALSE)

    check_conflicts <- function() {
      n <- tryCatch(
        sync_count_local_conflicts(con),
        error = function(e) 0L
      )
      if (n > 0 && !isTRUE(conflict_modal_shown())) {
        conflict_rows <- tryCatch(
          sync_get_local_conflicts(con),
          error = function(e) data.frame()
        )
        showModal(modalDialog(
          title = tagList(icon("triangle-exclamation", class = "text-danger"), " Unresolved Sync Conflicts"),
          easyClose = FALSE,
          footer = NULL,
          div(
            class = "alert alert-danger mb-2",
            strong("You have unresolved pull conflicts that must be resolved before you can push."),
            " For each row below, choose whether to keep your local version or accept the master version."
          ),
          DT::renderDataTable({
            DT::datatable(
              conflict_rows[, intersect(c("id", "table_name", "plot_number", "project_id",
                                          "species_code", "layer_code", "local_values",
                                          "master_values", "conflict_at"), names(conflict_rows))],
              selection = "single",
              rownames  = FALSE,
              options   = list(pageLength = 10, scrollX = TRUE)
            )
          }),
          div(
            class = "d-flex gap-2 mt-3",
            uiOutput(ns("conflict_selected_info")),
            actionButton(ns("conflict_keep_local"),    "Keep Local",    class = "btn btn-warning btn-sm"),
            actionButton(ns("conflict_accept_master"), "Accept Master", class = "btn btn-danger btn-sm ms-auto")
          )
        ))
        conflict_modal_shown(TRUE)
      } else if (n == 0 && isTRUE(conflict_modal_shown())) {
        removeModal()
        conflict_modal_shown(FALSE)
      }
    }

    # Run on module load
    observe({ check_conflicts() })

    # Re-run when SyncVersion increments
    observeEvent(state$SyncVersion, {
      check_conflicts()
    }, ignoreInit = TRUE)

    # Selected conflict row id
    selected_conflict_id <- reactive({
      rows <- input$`conflict_rows-rows_current`  # not reliable for selection
      # Use DT selection via proxy name
      sel  <- input$conflict_table_rows_selected
      if (is.null(sel) || length(sel) == 0) return(NULL)
      cq <- tryCatch(sync_get_local_conflicts(con), error = function(e) data.frame())
      if (nrow(cq) == 0 || sel > nrow(cq)) return(NULL)
      cq$id[sel]
    })

    output$conflict_selected_info <- renderUI({
      id <- selected_conflict_id()
      if (is.null(id)) {
        span(class = "text-muted small", "Select a row above to resolve it.")
      } else {
        span(class = "text-muted small", paste("Conflict #", id, "selected"))
      }
    })

    resolve_conflict_and_recheck <- function(resolution) {
      id <- selected_conflict_id()
      if (is.null(id)) {
        showNotification("Select a conflict row first.", type = "warning")
        return()
      }
      tryCatch({
        sync_resolve_local_conflict(con, id, resolution)
        state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
        check_conflicts()
      }, error = function(e) {
        showNotification(paste("Error resolving conflict:", e$message), type = "error")
      })
    }

    observeEvent(input$conflict_keep_local,    resolve_conflict_and_recheck("keep_local"))
    observeEvent(input$conflict_accept_master, resolve_conflict_and_recheck("accept_master"))


    # ── Current project from state ────────────────────────────────────────────
    current_project_id <- reactive({
      state$CurrProject %||% state$PrefProject
    })

    output$project_badge <- renderUI({
      pid <- current_project_id()
      if (!is.null(pid) && nzchar(as.character(pid))) {
        span(class = "badge bg-primary", paste("Project:", pid))
      }
    })


    # ── Incoming count (computed on tab open + Refresh) ───────────────────────
    reactive_incoming <- reactive({
      rv_refresh()
      tryCatch(
        sync_count_incoming(con, project_id = current_project_id()),
        error = function(e) list(env = 0L, su = 0L, veg = 0L, available = FALSE)
      )
    })

    output$pull_count_badge <- renderUI({
      inc <- reactive_incoming()
      if (!isTRUE(inc$available)) {
        span(class = "badge bg-secondary", "Cloud: offline")
      } else {
        total <- (inc$env %||% 0L) + (inc$su %||% 0L) + (inc$veg %||% 0L)
        if (total > 0) {
          span(class = "badge bg-info text-dark", paste(total, "incoming"))
        } else {
          span(class = "badge bg-success", "Up to date")
        }
      }
    })

    output$btn_pull_ui <- renderUI({
      inc   <- reactive_incoming()
      total <- (inc$env %||% 0L) + (inc$su %||% 0L) + (inc$veg %||% 0L)
      label <- if (isTRUE(inc$available) && total > 0) {
        tagList(icon("cloud-arrow-down"), paste0("Pull (", total, " changes)"))
      } else {
        tagList(icon("cloud-arrow-down"), "Pull")
      }
      disabled <- !isTRUE(inc$available)
      btn <- actionButton(
        ns("sync_pull"),
        label = label,
        class = if (disabled) "btn btn-outline-primary btn-sm disabled" else "btn btn-primary btn-sm"
      )
      btn
    })


    # ── Local changes reactive ────────────────────────────────────────────────
    reactive_changes <- reactive({
      rv_refresh()
      state$SyncVersion  # invalidation
      tryCatch(
        sync_get_local_changes(con, project_id = current_project_id()),
        error = function(e) list(
          env = data.frame(change_type = character(0)),
          su  = data.frame(change_type = character(0)),
          veg = data.frame(change_type = character(0))
        )
      )
    })

    # Helper: render a changes table with row background coloring
    render_changes_table <- function(df_reactive, id) {
      output[[id]] <- DT::renderDataTable({
        df <- df_reactive()
        if (nrow(df) == 0) {
          return(DT::datatable(
            data.frame(Message = "No local changes."),
            rownames = FALSE,
            options  = list(dom = "t", pageLength = 5)
          ))
        }
        dt <- DT::datatable(
          df,
          rownames  = FALSE,
          selection = "none",
          options   = list(pageLength = 20, scrollX = TRUE)
        )
        # Row background: green = insert, yellow = update
        if ("change_type" %in% names(df)) {
          insert_rows <- which(df$change_type == "insert") - 1L  # 0-indexed for JS
          update_rows <- which(df$change_type == "update") - 1L
          dt <- DT::formatStyle(
            dt, "change_type",
            target          = "row",
            backgroundColor = DT::styleEqual(
              c("insert", "update"),
              c("#d4edda",  "#fff3cd")
            )
          )
        }
        dt
      })
    }

    render_changes_table(reactive({ reactive_changes()$env }), "tbl_env_changes")
    render_changes_table(reactive({ reactive_changes()$su  }), "tbl_su_changes")
    render_changes_table(reactive({ reactive_changes()$veg }), "tbl_veg_changes")


    # ── Status output ─────────────────────────────────────────────────────────
    sync_status_msg <- reactiveVal(NULL)

    output$sync_status <- renderUI({
      msg <- sync_status_msg()
      if (is.null(msg)) return(NULL)
      cls <- if (isTRUE(attr(msg, "error"))) "alert alert-danger" else "alert alert-success"
      div(class = paste(cls, "py-2 mt-2"), msg)
    })


    # ── Pull handler ─────────────────────────────────────────────────────────
    observeEvent(input$sync_pull, {
      pid <- current_project_id()
      tryCatch({
        result <- sync_pull(
          con,
          project_id   = pid,
          tables       = c("env", "su", "veg", "lists"),
          allow_attach = FALSE
        )
        state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
        rv_refresh(rv_refresh() + 1L)

        env_n   <- result$env$pulled       %||% 0L
        su_n    <- result$su$pulled        %||% 0L
        veg_n   <- result$veg$pulled       %||% 0L
        conf_n  <- (result$env$conflicts   %||% 0L) +
                   (result$su$conflicts    %||% 0L) +
                   (result$veg$conflicts   %||% 0L)
        msg <- sprintf(
          "Pull complete — env: %d, su: %d, veg: %d rows. Conflicts queued: %d.",
          as.integer(env_n), as.integer(su_n), as.integer(veg_n), as.integer(conf_n)
        )
        sync_status_msg(msg)
      }, error = function(e) {
        m <- conditionMessage(e)
        attr(m, "error") <- TRUE
        sync_status_msg(m)
      })
    })


    # ── Push handler ─────────────────────────────────────────────────────────
    observeEvent(input$sync_push, {
      # Guard: unresolved conflicts
      n_conf <- tryCatch(sync_count_local_conflicts(con), error = function(e) 0L)
      if (n_conf > 0) {
        showNotification(
          paste0("Push blocked: ", n_conf, " unresolved conflict(s). Resolve them first."),
          type     = "error",
          duration = 8
        )
        return()
      }

      pid       <- current_project_id()
      submitter <- state$User %||% "unknown"

      tryCatch({
        result  <- sync_push(
          con,
          project_id   = pid,
          submitter    = submitter,
          allow_attach = FALSE
        )
        state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
        rv_refresh(rv_refresh() + 1L)
        rv_mr_reload(rv_mr_reload() + 1L)

        mr_id <- result$merge_request_id %||% "?"
        env_n <- result$env  %||% 0L
        su_n  <- result$su   %||% 0L
        veg_n <- result$veg  %||% 0L
        msg   <- sprintf(
          "Push submitted — MR #%s (env: %d, su: %d, veg: %d rows). Awaiting admin review.",
          mr_id, as.integer(env_n), as.integer(su_n), as.integer(veg_n)
        )
        sync_status_msg(msg)

        # Navigate to Merge Requests tab
        bslib::nav_select(session$ns("sync_tabs"), selected = "merge_requests")
      }, error = function(e) {
        m <- conditionMessage(e)
        attr(m, "error") <- TRUE
        sync_status_msg(m)
      })
    })


    # ── Merge requests panel ─────────────────────────────────────────────────
    reactive_mrs <- reactive({
      rv_mr_reload()
      state$SyncVersion
      sync_get_user_merge_requests(
        con,
        submitter     = state$User %||% "",
        show_approved = !isTRUE(input$hide_approved),
        show_rejected = !isTRUE(input$hide_rejected)
      )
    })

    output$tbl_mrs <- DT::renderDataTable({
      df <- reactive_mrs()
      if (nrow(df) == 0) {
        return(DT::datatable(
          data.frame(Message = "No merge requests found."),
          rownames = FALSE,
          options  = list(dom = "t")
        ))
      }

      # Format status as badge-style label
      df$status_label <- dplyr::case_when(
        df$status == "pending_review" ~ "Pending",
        df$status == "merged"         ~ "Merged",
        df$status == "approved"       ~ "Approved",
        df$status == "rejected"       ~ "Rejected",
        TRUE                          ~ df$status
      )

      display_cols <- intersect(
        c("id", "project_id", "submitted_utc", "status_label",
          "env_record_count", "su_record_count", "veg_record_count", "review_notes"),
        names(df)
      )

      DT::datatable(
        df[, display_cols, drop = FALSE],
        rownames  = FALSE,
        selection = "single",
        colnames  = c("ID", "Project", "Submitted", "Status",
                      "Env", "SU", "Veg", "Review Notes")[seq_along(display_cols)],
        options   = list(pageLength = 20, scrollX = TRUE)
      ) |>
        DT::formatStyle(
          "status_label",
          target          = "row",
          backgroundColor = DT::styleEqual(
            c("Pending", "Merged", "Approved", "Rejected"),
            c("#fff3cd",  "#d4edda", "#d4edda",  "#f8d7da")
          )
        )
    })

    output$mr_detail <- renderUI({
      sel <- input$tbl_mrs_rows_selected
      if (is.null(sel) || length(sel) == 0) return(NULL)
      df  <- reactive_mrs()
      if (nrow(df) == 0 || sel > nrow(df)) return(NULL)
      row <- df[sel, , drop = FALSE]

      notes    <- row$review_notes[1]
      rev_utc  <- row$reviewed_utc[1]

      div(
        class = "card mt-3",
        div(
          class = "card-body",
          h6(class = "card-title", paste("MR #", row$id[1], "— detail")),
          tags$dl(
            class = "row mb-0",
            tags$dt(class = "col-sm-3", "Env rows"),
            tags$dd(class = "col-sm-9", row$env_record_count[1] %||% "—"),
            tags$dt(class = "col-sm-3", "SU rows"),
            tags$dd(class = "col-sm-9", row$su_record_count[1]  %||% "—"),
            tags$dt(class = "col-sm-3", "Veg rows"),
            tags$dd(class = "col-sm-9", row$veg_record_count[1] %||% "—"),
            tags$dt(class = "col-sm-3", "Reviewed"),
            tags$dd(class = "col-sm-9",
              if (!is.na(rev_utc) && !is.null(rev_utc)) as.character(rev_utc) else "—"
            ),
            tags$dt(class = "col-sm-3", "Review notes"),
            tags$dd(class = "col-sm-9",
              if (!is.na(notes) && nzchar(notes %||% "")) notes else "—"
            )
          )
        )
      )
    })
  })
}
