# =============================================================================
# mod_sync.R
# Field-user push-only sync module: view local changes (9 tables), push to
# staging, view own merge requests. No pull functionality.
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
        actionButton(
          ns("sync_push"),
            label = tagList(icon("cloud-arrow-up"), "Push changes"),
            style = "background-color: #fcba19; border-color: #fcba19; color: #222;",
            class = "btn btn-sm"
        ),
        actionButton(
          ns("sync_refresh"),
          label = tagList(icon("rotate"), "Refresh"),
          class = "btn btn-outline-secondary btn-sm"
        )
      ),

      # Status message
      uiOutput(ns("sync_status")),

      # 4 accordion groups ordered by field workflow: Site, Soil, Veg, Project
      bslib::accordion(
        id = ns("acc_changes"),
        open = FALSE,

        bslib::accordion_panel(
          title = tagList(icon("map-location-dot"), " Site"),
          value = "site",
          tags$p(class = "text-muted small mb-1", "Admin, Env, SU"),
          DT::dataTableOutput(ns("tbl_admin_changes")),
          DT::dataTableOutput(ns("tbl_env_changes")),
          DT::dataTableOutput(ns("tbl_su_changes"))
        ),

        bslib::accordion_panel(
          title = tagList(icon("layer-group"), " Soil"),
          value = "soil",
          tags$p(class = "text-muted small mb-1", "Humus, Mineral, Other"),
          DT::dataTableOutput(ns("tbl_humus_changes")),
          DT::dataTableOutput(ns("tbl_mineral_changes")),
          DT::dataTableOutput(ns("tbl_other_changes"))
        ),

        bslib::accordion_panel(
          title = tagList(icon("leaf"), " Vegetation"),
          value = "veg",
          tags$p(class = "text-muted small mb-1", "Veg, Herbarium"),
          DT::dataTableOutput(ns("tbl_veg_changes")),
          DT::dataTableOutput(ns("tbl_herbarium_changes"))
        ),

        bslib::accordion_panel(
          title = tagList(icon("folder-open"), " Project"),
          value = "project",
          tags$p(class = "text-muted small mb-1", "Metadata"),
          DT::dataTableOutput(ns("tbl_metadata_changes"))
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
    rv_refresh   <- reactiveVal(0L)
    rv_mr_reload <- reactiveVal(0L)

    observeEvent(input$sync_refresh, rv_refresh(rv_refresh() + 1L))
    observeEvent(input$mr_refresh,   rv_mr_reload(rv_mr_reload() + 1L))

    # Refresh when Sync tab is navigated to
    observeEvent(state$SyncTabActivated, {
      rv_refresh(rv_refresh() + 1L)
    }, ignoreInit = TRUE)


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


    # ── Local changes reactive ────────────────────────────────────────────────
    reactive_changes <- reactive({
      rv_refresh()
      state$SyncVersion  # invalidation signal
      tryCatch(
        sync_get_local_changes(con, project_id = current_project_id()),
        error = function(e) {
          setNames(
            lapply(c("admin","env","su","humus","mineral","other","veg","herbarium","metadata"),
                   function(x) data.frame(table_pg = character(0), change_type = character(0))),
            c("admin","env","su","humus","mineral","other","veg","herbarium","metadata")
          )
        }
      )
    })

    # Helper: render one table's changes as a compact DT
    .render_changes <- function(pg_name, dt_output_id) {
      output[[dt_output_id]] <- DT::renderDataTable({
        changes <- reactive_changes()
        df      <- changes[[pg_name]]
        if (is.null(df) || nrow(df) == 0) {
          return(DT::datatable(
            data.frame(Status = paste0(pg_name, ": no local changes")),
            rownames = FALSE,
            options  = list(dom = "t", pageLength = 5)
          ))
        }
        dt <- DT::datatable(
          df,
          caption  = pg_name,
          rownames  = FALSE,
          selection = "none",
          options   = list(pageLength = 20, scrollX = TRUE)
        )
        if ("change_type" %in% names(df)) {
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

    .render_changes("admin",     "tbl_admin_changes")
    .render_changes("env",       "tbl_env_changes")
    .render_changes("su",        "tbl_su_changes")
    .render_changes("humus",     "tbl_humus_changes")
    .render_changes("mineral",   "tbl_mineral_changes")
    .render_changes("other",     "tbl_other_changes")
    .render_changes("veg",       "tbl_veg_changes")
    .render_changes("herbarium", "tbl_herbarium_changes")
    .render_changes("metadata",  "tbl_metadata_changes")


    # ── Status output ─────────────────────────────────────────────────────────
    sync_status_msg <- reactiveVal(NULL)

    output$sync_status <- renderUI({
      msg <- sync_status_msg()
      if (is.null(msg)) return(NULL)
      cls <- if (isTRUE(attr(msg, "error"))) "alert alert-danger" else "alert alert-success"
      div(class = paste(cls, "py-2 mt-2"), msg)
    })


    # ── Push handler ─────────────────────────────────────────────────────────
    observeEvent(input$sync_push, {
      pid       <- current_project_id()
      submitter <- state$User %||% "unknown"

      tryCatch({
        result <- sync_push(con, project_id = pid, submitter = submitter)

        state$SyncVersion <- (state$SyncVersion %||% 0L) + 1L
        rv_refresh(rv_refresh() + 1L)
        rv_mr_reload(rv_mr_reload() + 1L)

        mr_id  <- result$merge_request_id %||% "?"
        counts <- result$counts %||% list()
        # Build per-table summary (omit tables with 0 rows)
        non_zero <- Filter(function(n) as.integer(n) > 0L, counts)
        count_str <- if (length(non_zero) > 0)
          paste(names(non_zero), unlist(non_zero), sep = ": ", collapse = ", ")
        else
          "no rows"

        msg <- sprintf(
          "Push submitted \u2014 MR #%s (%s). Awaiting admin review.",
          mr_id, count_str
        )
        sync_status_msg(msg)
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

      df$status_label <- dplyr::case_when(
        df$status == "pending_review" ~ "Pending",
        df$status == "merged"         ~ "Merged",
        df$status == "approved"       ~ "Approved",
        df$status == "rejected"       ~ "Rejected",
        TRUE                          ~ df$status
      )

      # Parse record_counts JSONB to compute total
      df$total_rows <- vapply(df$record_counts, function(rc) {
        tryCatch({
          nn <- jsonlite::fromJSON(rc %||% "{}")
          as.integer(sum(unlist(nn), na.rm = TRUE))
        }, error = function(e) NA_integer_)
      }, integer(1))

      display_cols <- intersect(
        c("id", "project_id", "submitted_utc", "status_label", "total_rows", "review_notes"),
        names(df)
      )

      DT::datatable(
        df[, display_cols, drop = FALSE],
        rownames  = FALSE,
        selection = "single",
        colnames  = c("ID", "Project", "Submitted", "Status", "Rows", "Review Notes")[seq_along(display_cols)],
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

      # Parse record_counts JSON -> per-table display
      counts_list <- tryCatch(
        jsonlite::fromJSON(row$record_counts[1] %||% "{}"),
        error = function(e) list()
      )
      count_rows <- if (length(counts_list) > 0) {
        tagList(
          tags$dt(class = "col-sm-3", "Rows by table"),
          tags$dd(class = "col-sm-9",
            tags$ul(
              class = "list-unstyled mb-0",
              lapply(names(counts_list), function(tbl)
                tags$li(paste0(tbl, ": ", counts_list[[tbl]]))
              )
            )
          )
        )
      } else {
        tagList(
          tags$dt(class = "col-sm-3", "Rows"),
          tags$dd(class = "col-sm-9", "—")
        )
      }

      notes   <- row$review_notes[1]
      rev_utc <- row$reviewed_utc[1]

      div(
        class = "card mt-3",
        div(
          class = "card-body",
          h6(class = "card-title", paste("MR #", row$id[1], "— detail")),
          tags$dl(
            class = "row mb-0",
            count_rows,
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
