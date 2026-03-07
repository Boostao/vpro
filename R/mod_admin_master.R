# =============================================================================
# mod_admin_master.R — Master Site Units + Master Audit sub-module
# =============================================================================

mod_admin_master_ui <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Master Site Units",
      layout_sidebar(
        sidebar = sidebar(
          selectInput(ns("master_level"), "Level", choices = c("All" = "")),
          actionButton(ns("master_refresh"), "Refresh", class = "btn-secondary w-100 mt-2")
        ),
        card(
          card_header(textOutput(ns("master_header"))),
          card_body(
            DTOutput(ns("master_dt")),
            div(class = "mt-3 d-flex gap-2",
                actionButton(ns("master_add_row"), "Add Row", class = "btn-info"),
                actionButton(ns("master_save"), "Save Master List", class = "btn-warning")
            ),
            helpText("Edit the master site unit list. 'Save' overwrites the list in DB.")
          )
        )
      )
    ),
    nav_panel("Master Audit",
      layout_sidebar(
        sidebar = sidebar(
          textInput(ns("master_audit_user"),   "User",   value = ""),
          textInput(ns("master_audit_action"), "Action", value = ""),
          textInput(ns("master_audit_node"),   "Node",   value = ""),
          dateInput(ns("master_audit_from"), "From", value = NULL),
          dateInput(ns("master_audit_to"),   "To",   value = NULL),
          selectInput(ns("master_audit_page_size"), "Page size", choices = c(25, 50, 100), selected = 25),
          checkboxInput(ns("master_audit_latest_only"), "Latest only", value = FALSE),
          actionButton(ns("master_audit_refresh"), "Refresh",         class = "btn-secondary w-100 mt-2"),
          actionButton(ns("master_audit_latest"),  "Jump to newest",  class = "btn-outline-secondary w-100 mt-2"),
          downloadButton(ns("master_audit_export"), "Export CSV",     class = "btn-outline-primary w-100 mt-2")
        ),
        card(
          card_header("Master Audit"),
          card_body(
            DTOutput(ns("master_audit_dt")),
            div(class = "mt-2 d-flex gap-2",
                actionButton(ns("master_audit_prev"), "Prev", class = "btn-outline-secondary"),
                actionButton(ns("master_audit_next"), "Next", class = "btn-outline-secondary"),
                textOutput(ns("master_audit_page_info"))
            )
          )
        )
      )
    )
  )
}

mod_admin_master_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {

    require_permission <- function(permissions, message) {
      if (!auth_is_authenticated(state)) {
        showNotification("Sign in required.", type = "error")
        return(FALSE)
      }
      if (!any(vapply(permissions, function(p) auth_user_has_permission(state, p), logical(1)))) {
        showNotification(message, type = "error")
        return(FALSE)
      }
      TRUE
    }

    rv_master <- reactiveValues(data = NULL, columns = NULL, table_name = NULL)

    get_master_table <- function() {
      candidates <- c(
        "lists.MasterSiteUnitList",
        "lists.USysMasterSiteUnitList",
        "MasterSiteUnitList",
        "USysMasterSiteUnitList"
      )
      for (candidate in candidates) {
        if (DBI::dbExistsTable(con, candidate)) {
          return(list(id = candidate, name = candidate))
        }
      }
      NULL
    }

    update_master_levels <- function() {
      table_info <- get_master_table()
      if (is.null(table_info)) {
        updateSelectInput(session, "master_level", choices = c("All" = ""))
        return()
      }
      fields <- dbListFields(con, table_info$id)
      if (!("Level" %in% fields)) {
        updateSelectInput(session, "master_level", choices = c("All" = ""))
        return()
      }
      levels <- dbGetQuery(con, sprintf("SELECT DISTINCT Level FROM %s ORDER BY Level", table_info$name))$Level
      level_choices <- c("All" = "", stats::setNames(as.character(levels), as.character(levels)))
      updateSelectInput(session, "master_level", choices = level_choices)
    }

    load_master_table <- function(level = NULL) {
      table_info <- get_master_table()
      rv_master$table_name <- if (is.null(table_info)) NULL else table_info$name

      if (is.null(table_info)) {
        rv_master$data    <- data.frame()
        rv_master$columns <- NULL
        output$master_header <- renderText("Master list not found.")
        return()
      }

      fields      <- dbListFields(con, table_info$id)
      select_cols <- intersect(c("ID", "SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"), fields)
      if (length(select_cols) == 0 || !("SiteSeries" %in% select_cols)) {
        rv_master$data    <- data.frame()
        rv_master$columns <- NULL
        output$master_header <- renderText("Master list missing required columns.")
        return()
      }

      where_clause <- ""
      params <- list()
      if (!is.null(level) && nzchar(level) && ("Level" %in% select_cols)) {
        where_clause <- "WHERE Level = ?"
        params       <- list(as.integer(level))
      }

      sql <- sprintf("SELECT %s FROM %s %s ORDER BY SiteSeries",
                     paste(select_cols, collapse = ", "), table_info$name, where_clause)
      rv_master$data    <- dbGetQuery(con, sql, params)
      rv_master$columns <- select_cols
      output$master_header <- renderText(paste("Master list:", table_info$name))
    }

    observeEvent(input$master_refresh, {
      load_master_table(level = trimws(input$master_level))
    })

    observeEvent(input$master_level, {
      load_master_table(level = trimws(input$master_level))
    }, ignoreInit = TRUE)

    observeEvent(state$CurrProject, {
      update_master_levels()
      load_master_table(level = trimws(input$master_level))
    }, ignoreInit = TRUE)

    output$master_dt <- renderDT({
      req(rv_master$data)
      id_col       <- which(names(rv_master$data) == "ID")
      disable_cols <- if (length(id_col) > 0) list(columns = id_col - 1L) else list()
      datatable(rv_master$data,
                editable  = list(target = "cell", disable = disable_cols),
                selection = "none",
                options   = list(pageLength = 15, dom = "t,p"))
    })

    observeEvent(input$master_dt_cell_edit, {
      info <- input$master_dt_cell_edit
      i <- info$row
      j <- info$col + 1
      v <- info$value
      rv_master$data[i, j] <- DT::coerceValue(v, rv_master$data[i, j])
    })

    observeEvent(input$master_add_row, {
      req(rv_master$columns)
      if (!require_permission(c("manage:codes", "write:all"), "Permission required: manage codes")) return()
      new_row <- as.list(rep(NA, length(rv_master$columns)))
      names(new_row) <- rv_master$columns
      if ("SiteSeries" %in% rv_master$columns)             new_row$SiteSeries             <- "NEW_UNIT"
      if ("SiteSeriesLongName" %in% rv_master$columns)     new_row$SiteSeriesLongName     <- "New Site Unit"
      if ("SiteSeriesScientificName" %in% rv_master$columns) new_row$SiteSeriesScientificName <- ""
      if ("Level" %in% rv_master$columns)                  new_row$Level                  <- 11
      if ("ID" %in% rv_master$columns)                     new_row$ID                     <- NA_integer_
      rv_master$data <- rbind(rv_master$data, as.data.frame(new_row, stringsAsFactors = FALSE))
    })

    observeEvent(input$master_save, {
      req(rv_master$table_name)
      req(rv_master$data)
      if (!require_permission(c("manage:codes", "write:all"), "Permission required: manage codes")) return()

      table_name <- rv_master$table_name
      old_rows   <- dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                            paste(rv_master$columns, collapse = ", "), table_name))
      to_save    <- rv_master$data

      if ("Level" %in% names(to_save)) {
        to_save$Level[is.na(to_save$Level)] <- 11
      }
      if ("ID" %in% names(to_save)) {
        ids     <- suppressWarnings(as.integer(to_save$ID))
        max_id  <- if (any(!is.na(ids))) max(ids, na.rm = TRUE) else 0L
        missing <- which(is.na(ids) | ids <= 0 | duplicated(ids))
        for (idx in missing) {
          max_id    <- max_id + 1L
          ids[idx]  <- max_id
        }
        to_save$ID <- ids
      }

      dbBegin(con)
      tryCatch({
        dbExecute(con, sprintf("DELETE FROM %s", table_name))
        cols         <- names(to_save)
        placeholders <- paste(rep("?", length(cols)), collapse = ", ")
        sql          <- sprintf("INSERT INTO %s (%s) VALUES (%s)",
                                table_name, paste(cols, collapse = ", "), placeholders)
        for (i in seq_len(nrow(to_save))) {
          dbExecute(con, sql, as.list(to_save[i, cols, drop = FALSE]))
        }
        dbCommit(con)
        showNotification("Master list saved.", type = "message")

        if (nrow(to_save) > 0 || nrow(old_rows) > 0) {
          key_col      <- if ("ID" %in% cols) "ID" else "SiteSeries"
          old_map      <- if (nrow(old_rows) > 0) split(old_rows, old_rows[[key_col]]) else list()
          new_map      <- if (nrow(to_save) > 0)  split(to_save,  to_save[[key_col]])  else list()
          removed_keys <- setdiff(names(old_map), names(new_map))
          added_keys   <- setdiff(names(new_map), names(old_map))
          common_keys  <- intersect(names(old_map), names(new_map))
          audit_fields <- intersect(c("SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"), cols)

          for (key in removed_keys) {
            row     <- old_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) row$ID[1] else 0L
            for (field in audit_fields) log_master_audit(con, "Admin", "Delete", row$SiteSeries[1], node_id, field, row[[field]][1], NA)
          }
          for (key in added_keys) {
            row     <- new_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) row$ID[1] else 0L
            for (field in audit_fields) log_master_audit(con, "Admin", "Add", row$SiteSeries[1], node_id, field, NA, row[[field]][1])
          }
          for (key in common_keys) {
            old_row <- old_map[[key]][1, , drop = FALSE]
            new_row <- new_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) new_row$ID[1] else 0L
            for (field in audit_fields) log_master_audit(con, "Admin", "Edit", new_row$SiteSeries[1], node_id, field, old_row[[field]][1], new_row[[field]][1])
          }
        }

        update_master_levels()
        load_master_table(level = trimws(input$master_level))
      }, error = function(e) {
        dbRollback(con)
        showNotification(paste("Save failed:", e$message), type = "error")
      })
    })

    # ------------------------------------------------------------------
    # Master Audit
    # ------------------------------------------------------------------

    rv_master_audit <- reactiveValues(page = 1L)

    observeEvent(input$master_audit_refresh, { rv_master_audit$page <- 1L })
    observeEvent(input$master_audit_page_size, { rv_master_audit$page <- 1L })

    observeEvent(input$master_audit_next, {
      if (isTRUE(input$master_audit_latest_only)) return()
      rv_master_audit$page <- rv_master_audit$page + 1L
    })

    observeEvent(input$master_audit_prev, {
      if (isTRUE(input$master_audit_latest_only)) return()
      rv_master_audit$page <- max(1L, rv_master_audit$page - 1L)
    })

    observeEvent(input$master_audit_latest, {
      updateCheckboxInput(session, "master_audit_latest_only", value = TRUE)
      rv_master_audit$page <- 1L
    })

    output$master_audit_dt <- renderDT({
      user_filter   <- trimws(input$master_audit_user)
      action_filter <- trimws(input$master_audit_action)
      node_filter   <- trimws(input$master_audit_node)
      date_from     <- input$master_audit_from
      date_to       <- input$master_audit_to

      user_value   <- if (nzchar(user_filter))   user_filter   else NULL
      action_value <- if (nzchar(action_filter)) action_filter else NULL
      node_value   <- if (nzchar(node_filter))   node_filter   else NULL
      from_value   <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
      to_value     <- if (!is.null(date_to)   && !is.na(date_to))   as.POSIXct(date_to)   else NULL

      page_size   <- as.integer(input$master_audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      latest_only <- isTRUE(input$master_audit_latest_only)
      offset      <- if (latest_only) 0L else (rv_master_audit$page - 1L) * page_size

      audit <- fetch_master_audit_entries(con,
        user      = user_value,  action = action_value,
        node_name = node_value,
        date_from = from_value,  date_to = to_value,
        limit     = page_size,   offset  = offset)
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = page_size, ordering = FALSE))
    })

    output$master_audit_page_info <- renderText({
      page_size <- as.integer(input$master_audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      if (isTRUE(input$master_audit_latest_only)) return(paste0("Latest ", page_size, " rows"))
      start_row <- (rv_master_audit$page - 1L) * page_size + 1L
      end_row   <- rv_master_audit$page * page_size
      paste0("Rows ", start_row, "-", end_row)
    })

    output$master_audit_export <- downloadHandler(
      filename = function() paste0("master_audit_", format(Sys.Date(), "%Y%m%d"), ".csv"),
      content  = function(file) {
        user_filter   <- trimws(input$master_audit_user)
        action_filter <- trimws(input$master_audit_action)
        node_filter   <- trimws(input$master_audit_node)
        date_from     <- input$master_audit_from
        date_to       <- input$master_audit_to

        audit <- fetch_master_audit_entries(con,
          user      = if (nzchar(user_filter))   user_filter   else NULL,
          action    = if (nzchar(action_filter)) action_filter else NULL,
          node_name = if (nzchar(node_filter))   node_filter   else NULL,
          date_from = if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL,
          date_to   = if (!is.null(date_to)   && !is.na(date_to))   as.POSIXct(date_to)   else NULL)
        utils::write.csv(audit, file, row.names = FALSE)
      }
    )
  })
}
