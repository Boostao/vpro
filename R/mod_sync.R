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

      # Diff card CSS
      tags$style(HTML("
        .sync-diff-card { border-left: 4px solid #ccc; margin-bottom: 10px; border-radius: 4px; background: #fff; }
        .sync-diff-card.sync-insert { border-color: #43893e; }
        .sync-diff-card.sync-update { border-color: #f9ca54; }
        .sync-diff-header { padding: 7px 12px; font-size: 0.82em; font-weight: 600; display: flex; align-items: center; gap: 8px; }
        .sync-diff-card.sync-insert .sync-diff-header { background: #edf7ea; }
        .sync-diff-card.sync-update .sync-diff-header { background: #fef9ec; }
        .sync-diff-body { padding: 4px 0; }
        .sync-diff-row { display: grid; grid-template-columns: 160px 1fr; font-size: 0.8em; padding: 2px 12px; }
        .sync-diff-row.changed { grid-template-columns: 160px 1fr auto 1fr; }
        .sync-diff-field { color: #666; font-family: monospace; }
        .sync-val-before { font-family: monospace; background: #fff3cd; padding: 1px 4px; border-radius: 2px; }
        .sync-val-after  { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
        .sync-val-new    { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
        .sync-diff-arrow { color: #888; padding: 0 6px; }
        .sync-section-badge { display: inline-flex; gap: 4px; margin-left: 8px; }
        .sync-section-badge .badge { font-size: 0.72em; font-weight: 600; vertical-align: middle; }
      ")),

      # 4 accordion groups ordered by field workflow: Site, Soil, Veg, Project
      bslib::accordion(
        id = ns("acc_changes"),
        open = FALSE,

        bslib::accordion_panel(
          title = div(
            style = "display:inline-flex;align-items:center;",
            tagList(icon("map-location-dot"), " Site"),
            uiOutput(ns("badges_site"), inline = TRUE)
          ),
          value = "site",
          uiOutput(ns("cards_admin")),
          uiOutput(ns("cards_env")),
          uiOutput(ns("cards_su"))
        ),

        bslib::accordion_panel(
          title = div(
            style = "display:inline-flex;align-items:center;",
            tagList(icon("layer-group"), " Soil"),
            uiOutput(ns("badges_soil"), inline = TRUE)
          ),
          value = "soil",
          uiOutput(ns("cards_humus")),
          uiOutput(ns("cards_mineral")),
          uiOutput(ns("cards_other"))
        ),

        bslib::accordion_panel(
          title = div(
            style = "display:inline-flex;align-items:center;",
            tagList(icon("leaf"), " Vegetation"),
            uiOutput(ns("badges_veg"), inline = TRUE)
          ),
          value = "veg",
          uiOutput(ns("cards_veg")),
          uiOutput(ns("cards_herbarium"))
        ),

        bslib::accordion_panel(
          title = div(
            style = "display:inline-flex;align-items:center;",
            tagList(icon("folder-open"), " Project"),
            uiOutput(ns("badges_project"), inline = TRUE)
          ),
          value = "project",
          uiOutput(ns("cards_metadata"))
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

    # ── Badge + diff card helpers ──────────────────────────────────────────────

    # Helper: count inserts/updates for a set of pg_names from reactive_changes()
    .section_counts <- function(pg_names) {
      reactive({
        changes <- reactive_changes()
        n_insert <- sum(vapply(pg_names, function(p) {
          df <- changes[[p]]
          if (is.null(df) || nrow(df) == 0) return(0L)
          sum(df$change_type == "insert", na.rm = TRUE)
        }, integer(1)))
        n_update <- sum(vapply(pg_names, function(p) {
          df <- changes[[p]]
          if (is.null(df) || nrow(df) == 0) return(0L)
          sum(df$change_type == "update", na.rm = TRUE)
        }, integer(1)))
        c(insert = n_insert, update = n_update)
      })
    }

    # Helper: renderUI that emits count badges (hidden when 0)
    .render_badges <- function(counts_rv) {
      renderUI({
        counts <- counts_rv()
        badges <- list()
        if (counts[["insert"]] > 0)
          badges <- c(badges, list(
            tags$span(
              class = "badge",
              style = "background:#43893e;color:#fff;",
              paste(counts[["insert"]], "new")
            )
          ))
        if (counts[["update"]] > 0)
          badges <- c(badges, list(
            tags$span(
              class = "badge",
              style = "background:#f9ca54;color:#222;",
              paste(counts[["update"]], "updated")
            )
          ))
        if (length(badges) == 0) return(NULL)
        div(class = "sync-section-badge", badges)
      })
    }

    counts_site    <- .section_counts(c("admin", "env", "su"))
    counts_soil    <- .section_counts(c("humus", "mineral", "other"))
    counts_veg     <- .section_counts(c("veg", "herbarium"))
    counts_project <- .section_counts(c("metadata"))

    output$badges_site    <- .render_badges(counts_site)
    output$badges_soil    <- .render_badges(counts_soil)
    output$badges_veg     <- .render_badges(counts_veg)
    output$badges_project <- .render_badges(counts_project)

    # ── Detailed change records ────────────────────────────────────────────────

    reactive_all_details <- reactive({
      rv_refresh()
      state$SyncVersion
      pid <- current_project_id()
      out <- list()
      for (cfg in SYNC_TABLE_CONFIG) {
        out[[cfg$pg]] <- tryCatch(
          sync_get_change_detail(con, cfg, project_id = pid),
          error = function(e) list()
        )
      }
      out
    })

    # Helper: build one diff card HTML tag
    .build_diff_card <- function(record, pk) {
      is_insert  <- identical(record$change_type, "insert")
      card_class <- if (is_insert) "sync-diff-card sync-insert" else "sync-diff-card sync-update"
      badge_text <- if (is_insert) "INSERT" else "UPDATE"
      badge_col  <- if (is_insert) "#43893e" else "#f9ca54"
      badge_txt_col <- if (is_insert) "#fff" else "#222"

      header <- div(
        class = "sync-diff-header",
        tags$span(
          class = "badge",
          style = paste0("background:", badge_col, ";color:", badge_txt_col, ";"),
          badge_text
        ),
        tags$span(paste(pk, "=", record$pk_value))
      )

      local_d <- record$local_data
      core_d  <- record$core_data
      pk_lc   <- tolower(pk)

      rows <- if (is_insert) {
        # show non-PK, non-null local fields
        field_names <- names(local_d)
        field_names <- field_names[tolower(field_names) != pk_lc]
        field_names <- field_names[vapply(field_names, function(f) {
          v <- local_d[[f]]
          !is.null(v) && length(v) > 0 && !is.na(v[1]) && nzchar(as.character(v[1]))
        }, logical(1))]
        lapply(field_names, function(f) {
          div(
            class = "sync-diff-row",
            span(class = "sync-diff-field", f),
            span(class = "sync-val-new", as.character(local_d[[f]]))
          )
        })
      } else {
        # show only fields that differ between local and core
        field_names <- names(local_d)
        field_names <- field_names[tolower(field_names) != pk_lc]
        diff_fields <- Filter(function(f) {
          lv <- as.character(local_d[[f]] %||% NA)
          cv <- if (!is.null(core_d) && f %in% names(core_d))
            as.character(core_d[[f]] %||% NA) else NA_character_
          !identical(lv, cv)
        }, field_names)
        if (length(diff_fields) == 0) {
          return(div(
            class = card_class,
            header,
            div(class = "sync-diff-body",
              div(class = "sync-diff-row",
                tags$em(class = "text-muted", "no field differences detected")
              )
            )
          ))
        }
        lapply(diff_fields, function(f) {
          lv <- as.character(local_d[[f]] %||% NA)
          cv <- if (!is.null(core_d) && f %in% names(core_d))
            as.character(core_d[[f]] %||% NA) else NA_character_
          div(
            class = "sync-diff-row changed",
            span(class = "sync-diff-field", f),
            span(class = "sync-val-before", cv),
            span(class = "sync-diff-arrow", "\u2192"),
            span(class = "sync-val-after",  lv)
          )
        })
      }

      div(
        class = card_class,
        header,
        div(class = "sync-diff-body", rows)
      )
    }

    # Helper: wire output$cards_<pg> for one table
    .render_cards_output <- function(pg_name, cfg) {
      output[[paste0("cards_", pg_name)]] <- renderUI({
        details <- reactive_all_details()[[pg_name]]
        if (is.null(details) || length(details) == 0) {
          return(div(class = "text-muted small py-2",
            paste0(pg_name, ": no local changes")
          ))
        }
        tagList(lapply(details, .build_diff_card, pk = cfg$pk))
      })
    }

    for (cfg in SYNC_TABLE_CONFIG) {
      local({
        .cfg <- cfg
        .render_cards_output(.cfg$pg, .cfg)
      })
    }


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
