veg_numeric_cols <- c(
  "height1", "height2", "height3", "height4", "height5", "height6",
  "heighta", "heightb", "totala", "totalb"
)

coerce_veg_value <- function(col_name, value) {
  if (col_name %in% veg_numeric_cols) {
    return(suppressWarnings(as.numeric(value)))
  }
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(NA)
  }
  as.character(value)
}

save_veg_cell <- function(con, record_id, col_name, value) {
  sync_ensure_local_tables(con)
  sql <- sprintf("UPDATE Veg SET %s = ?, local_modified_utc = CURRENT_TIMESTAMP WHERE id = ?", col_name)
  DBI::dbExecute(con, sql, list(value, record_id))
}

detect_hot_changes <- function(old_df, new_df) {
  if (nrow(old_df) == 0 || nrow(new_df) == 0) return(list())
  changes <- list()
  cols <- intersect(names(old_df), names(new_df))

  for (row_idx in seq_len(nrow(new_df))) {
    for (col_name in cols) {
      old_val <- old_df[[col_name]][row_idx]
      new_val <- new_df[[col_name]][row_idx]

      if (is.na(old_val) && is.na(new_val)) next
      if (!is.na(old_val) && !is.na(new_val) && as.character(old_val) == as.character(new_val)) next
      if (is.na(old_val) && nzchar(as.character(new_val)) == FALSE) next

      changes[[length(changes) + 1]] <- list(
        row = row_idx,
        col = col_name,
        value = new_val
      )
    }
  }

  changes
}

sum_numeric_or_na <- function(values) {
  flat <- unlist(values, use.names = FALSE)
  nums <- suppressWarnings(as.numeric(flat))
  if (all(is.na(nums))) return(NA_real_)
  sum(nums, na.rm = TRUE)
}

get_hot_selected_row <- function(selection) {
  if (is.null(selection)) return(NULL)
  if (is.list(selection) && !is.null(selection$r)) return(selection$r)
  if (is.list(selection) && !is.null(selection$select) && !is.null(selection$select$r)) return(selection$select$r)
  if (is.matrix(selection) && ncol(selection) >= 1) return(selection[1, 1])
  NULL
}

mod_veg_sample_ui <- function(id) {
  ns <- NS(id)
  tab_input <- function(tag, index) {
    tagAppendAttributes(tag, tabindex = index)
  }

  tagList(
    card(
      full_screen = TRUE,
      card_header(
        "Vegetation Data",
        uiOutput(ns("veg_context_hint")),
        div(class="float-end",
            tab_input(actionButton(ns("btn_add_spp"), "Add Species", icon=icon("plus"), class="btn-sm btn-primary"), 1),
            tab_input(actionButton(ns("btn_del_spp"), "Delete Selected", icon=icon("trash"), class="btn-sm btn-danger"), 2)
        )
      ),
      navset_card_tab(
        id = ns("layers_tab"),
        nav_panel("Layer A (Trees)", rhandsontable::rHandsontableOutput(ns("hot_veg_a"))),
        nav_panel("Layer B (Shrubs)", rhandsontable::rHandsontableOutput(ns("hot_veg_b"))),
        nav_panel("Layer C (Herbs)", rhandsontable::rHandsontableOutput(ns("hot_veg_c"))),
        nav_panel("Layer D (Moss)", rhandsontable::rHandsontableOutput(ns("hot_veg_d"))),
        nav_panel("Audit",
          selectInput(ns("veg_audit_table"), "Table", choices = c("Veg")),
          DT::DTOutput(ns("dt_audit_veg"))
        ),
        nav_panel("Compliance",
          actionButton(ns("veg_compliance"), "Run Compliance", class = "btn-secondary"),
          textOutput(ns("veg_compliance_status")),
          DT::DTOutput(ns("veg_compliance_summary")),
          DT::DTOutput(ns("veg_compliance_details"))
        )
      )
    )
  )
}

mod_veg_sample_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session
    
    # --- Data State ---
    rv <- reactiveValues(data = NULL)

    output$veg_context_hint <- renderUI({
      req(sys_state$CurrSU)
      tags$span(class = "text-muted ms-2", paste("Plot:", sys_state$CurrSU))
    })
    
    # --- Loading ---
    observeEvent(sys_state$CurrSU, {
      req(sys_state$CurrSU)
      
      # Using shared con
      
      # Fetch all columns for the current plot, ordered by species
      query <- "SELECT * FROM Veg WHERE plotnumber = ? ORDER BY species"
      
      # Debug / Fix: ensure simple string passed to duckdb
      plot_id <- as.character(sys_state$CurrSU)
      rv$data <- dbGetQuery(con, query, list(plot_id))
    })
    
    # --- Mappings ---
    display_cols_a <- c("species", "cover1", "height1", "cover2", "height2", "cover3", "height3", "totala", "heighta")
    display_cols_b <- c("species", "cover4", "height4", "cover5", "height5", "totalb", "heightb")
    display_cols_c <- c("species", "cover6", "height6")
    display_cols_d <- c("species", "cover7")
    
    # --- Helper: Editable Grid ---

    require_plot_write <- function() {
      if (!auth_is_authenticated(sys_state)) {
        showNotification("Sign in required.", type = "error")
        return(FALSE)
      }
      allowed <- c("write:own_plots", "write:project_plots", "write:all")
      if (!any(vapply(allowed, function(p) auth_user_has_permission(sys_state, p), logical(1)))) {
        showNotification("Permission required: write plots", type = "error")
        return(FALSE)
      }
      TRUE
    }

    render_layer_hot <- function(cols) {
      rhandsontable::renderRHandsontable({
        req(rv$data)
        valid_cols <- intersect(cols, names(rv$data))
        d <- rv$data[, valid_cols, drop = FALSE]

        ht <- rhandsontable::rhandsontable(
          d,
          rowHeaders = FALSE,
          useTypes = TRUE,
          stretchH = "all"
        )

        for (col_name in veg_numeric_cols) {
          if (col_name %in% valid_cols) {
            ht <- rhandsontable::hot_col(ht, col = col_name, type = "numeric")
          }
        }

        ht
      })
    }

    output$hot_veg_a <- render_layer_hot(display_cols_a)
    output$hot_veg_b <- render_layer_hot(display_cols_b)
    output$hot_veg_c <- render_layer_hot(display_cols_c)
    output$hot_veg_d <- render_layer_hot(display_cols_d)

    update_from_hot <- function(hot_input, display_cols) {
      req(sys_state$CurrSU, rv$data, hot_input)
      if (!require_plot_write()) return()

      new_df <- rhandsontable::hot_to_r(hot_input)
      valid_cols <- intersect(display_cols, names(rv$data))
      old_df <- rv$data[, valid_cols, drop = FALSE]

      if (nrow(new_df) != nrow(old_df)) return()

      changes <- detect_hot_changes(old_df, new_df)
      if (length(changes) == 0) return()

      update_totals_for_row <- function(row_idx) {
        covers_a <- rv$data[row_idx, c("cover1", "cover2", "cover3"), drop = FALSE]
        covers_b <- rv$data[row_idx, c("cover4", "cover5"), drop = FALSE]

        total_a <- sum_numeric_or_na(covers_a)
        total_b <- sum_numeric_or_na(covers_b)

        old_total_a <- rv$data$totala[row_idx]
        old_total_b <- rv$data$totalb[row_idx]

        if (!identical(rv$data$totala[row_idx], total_a)) {
          rv$data$totala[row_idx] <- total_a
          tryCatch({
            save_veg_cell(con, rv$data$id[row_idx], "totala", total_a)
            log_audit_change(
              con,
              sys_state$CurrProject,
              sys_state$User,
              rv$data$plotnumber[row_idx],
              "Veg",
              "totala",
              old_total_a,
              total_a
            )
          }, error = function(e) {
            showNotification(paste("Error updating totala:", e$message), type = "error")
          })
        }

        if (!identical(rv$data$totalb[row_idx], total_b)) {
          rv$data$totalb[row_idx] <- total_b
          tryCatch({
            save_veg_cell(con, rv$data$id[row_idx], "totalb", total_b)
            log_audit_change(
              con,
              sys_state$CurrProject,
              sys_state$User,
              rv$data$plotnumber[row_idx],
              "Veg",
              "totalb",
              old_total_b,
              total_b
            )
          }, error = function(e) {
            showNotification(paste("Error updating totalb:", e$message), type = "error")
          })
        }
      }

      for (change in changes) {
        record_id <- rv$data$id[change$row]
        col_name <- change$col
        typed_val <- coerce_veg_value(col_name, change$value)
        rv$data[change$row, col_name] <- typed_val

        tryCatch({
          save_veg_cell(con, record_id, col_name, typed_val)
          log_audit_change(
            con,
            sys_state$CurrProject,
            sys_state$User,
            rv$data$plotnumber[change$row],
            "Veg",
            col_name,
            old_df[[col_name]][change$row],
            typed_val
          )
          sync_touch_state(sys_state)
        }, error = function(e) {
          showNotification(paste("Error updating DB:", e$message), type = "error")
        })

        if (col_name %in% c("cover1", "cover2", "cover3", "cover4", "cover5")) {
          update_totals_for_row(change$row)
        }
      }
    }

    observeEvent(input$hot_veg_a, { update_from_hot(input$hot_veg_a, display_cols_a) })
    observeEvent(input$hot_veg_b, { update_from_hot(input$hot_veg_b, display_cols_b) })
    observeEvent(input$hot_veg_c, { update_from_hot(input$hot_veg_c, display_cols_c) })
    observeEvent(input$hot_veg_d, { update_from_hot(input$hot_veg_d, display_cols_d) })
    
    # --- Add Species Logic ---
    observeEvent(input$btn_add_spp, {
        req(sys_state$CurrSU)
      if (!require_plot_write()) return()
        
        # Load species list efficiently
        # We query code and clean name
        spp_df <- dbGetQuery(con, "SELECT code, scientificname FROM SppList ORDER BY code")
        spp_choices <- setNames(spp_df$code, paste(spp_df$code, "-", spp_df$scientificname))
        
        showModal(modalDialog(
            title = "Add Species",
            selectizeInput(ns("sel_add_species"), "Select Species", choices = spp_choices, width = "100%"),
            footer = tagList(
                modalButton("Cancel"),
                actionButton(ns("save_new_spp"), "Add", class="btn-primary")
            )
        ))
    })
    
    observeEvent(input$save_new_spp, {
        req(input$sel_add_species, sys_state$CurrSU)
      if (!require_plot_write()) {
        removeModal()
        return()
      }
        removeModal()
        
        plot_id <- as.character(sys_state$CurrSU)
        new_species <- input$sel_add_species
        
        # Check if already exists for this plot? 
        # Usually duplicates are allowed if they are different layers, but here we have one row per species (wide).
        # We should check if species already in rv$data
        if (new_species %in% rv$data$species) {
            showNotification("Species already exists in this plot.", type="warning")
            return()
        }
        
        # Insert
        tryCatch({
          sync_ensure_local_tables(con)
            # Get max ID for safety if not auto-increment (Access migration implies we might need to handle IDs)
            # Veg usually has 'id' column.
            max_res <- dbGetQuery(con, "SELECT MAX(id) as m FROM Veg")
            new_id <- if(is.na(max_res[[1]])) 1 else max_res[[1]] + 1
            
            dbExecute(con, "INSERT INTO Veg (id, plotnumber, species) VALUES (?, ?, ?)", 
                      list(new_id, plot_id, new_species))
            dbExecute(con, "UPDATE Veg SET local_modified_utc = CURRENT_TIMESTAMP WHERE id = ?", list(new_id))
          log_audit_change(
            con,
            sys_state$CurrProject,
            sys_state$User,
            plot_id,
            "Veg",
            "species",
            NA,
            new_species
          )
            
            # Refresh
            rv$data <- dbGetQuery(con, "SELECT * FROM Veg WHERE plotnumber = ? ORDER BY species", list(plot_id))
              sync_touch_state(sys_state)
            showNotification(paste("Added:", new_species), type="message")
            
        }, error = function(e) {
            showNotification(paste("Error adding species:", e$message), type="error")
        })
    })

    # --- Delete Species Logic ---
    # Better approach for delete state
    rv_del <- reactiveValues(id = NULL)
    
    observeEvent(input$btn_del_spp, {
      req(rv$data, input$layers_tab)
      if (!require_plot_write()) return()
      idx <- NULL
      if (input$layers_tab == "Layer A (Trees)") idx <- get_hot_selected_row(input$hot_veg_a_select)
      else if (input$layers_tab == "Layer B (Shrubs)") idx <- get_hot_selected_row(input$hot_veg_b_select)
      else if (input$layers_tab == "Layer C (Herbs)") idx <- get_hot_selected_row(input$hot_veg_c_select)
      else if (input$layers_tab == "Layer D (Moss)") idx <- get_hot_selected_row(input$hot_veg_d_select)
        
      req(idx)
      rv_del$id <- rv$data$id[idx]
      rec_spp <- rv$data$species[idx]
        
        showModal(modalDialog(
            title = "Delete Species",
            paste("Delete species:", rec_spp, "?"),
            footer = tagList(
                modalButton("Cancel"),
                actionButton(ns("do_delete"), "Confirm Delete", class="btn-danger")
            )
        ))
    })
    
    observeEvent(input$do_delete, {
        req(rv_del$id)
      if (!require_plot_write()) {
        removeModal()
        return()
      }
        removeModal()
        
        tryCatch({
        sync_ensure_local_tables(con)
        row <- rv$data[rv$data$id == rv_del$id, , drop = FALSE]
        if (nrow(row) > 0) {
          log_audit_change(
            con,
            sys_state$CurrProject,
            sys_state$User,
            row$plotnumber[1],
            "Veg",
            "species",
            row$species[1],
            NA
          )
        }
            sync_delete_local_row(
              con,
              table_name = "veg",
              pk_value = rv_del$id,
              project_id = sys_state$CurrProject
            )
            
            # Refresh
            plot_id <- as.character(sys_state$CurrSU)
            rv$data <- dbGetQuery(con, "SELECT * FROM Veg WHERE plotnumber = ? ORDER BY species", list(plot_id))
            sync_touch_state(sys_state)
            showNotification("Species deleted.", type="message")
            
        }, error = function(e) {
            showNotification(paste("Delete Error:", e$message), type="error")
        })
    })

    output$dt_audit_veg <- DT::renderDT({
      req(sys_state$CurrSU)
      table_filter <- input$veg_audit_table
      table_name <- if (!is.null(table_filter) && nzchar(table_filter)) table_filter else "Veg"
      audit <- fetch_audit_entries(con, plot_number = sys_state$CurrSU, project_id = sys_state$CurrProject, table_name = table_name)
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })

    veg_compliance <- reactiveVal(NULL)

    observeEvent(input$veg_compliance, {
      veg_compliance(run_compliance_checks(con, sys_state$CurrProject))
    })

    output$veg_compliance_status <- renderText({
      result <- veg_compliance()
      if (is.null(result)) return("")
      if (isTRUE(result$passed)) "All checks passed" else "Issues found"
    })

    output$veg_compliance_summary <- DT::renderDT({
      result <- veg_compliance()
      req(result)
      DT::datatable(result$summary_tibble, rownames = FALSE, options = list(dom = "t", ordering = FALSE))
    })

    output$veg_compliance_details <- DT::renderDT({
      result <- veg_compliance()
      req(result)
      DT::datatable(result$detail_tibble, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })

  })
}
