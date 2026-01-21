mod_veg_sample_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header(
        "Vegetation Data",
        div(class="float-end",
            actionButton(ns("btn_add_spp"), "Add Species", icon=icon("plus"), class="btn-sm btn-primary"),
            actionButton(ns("btn_del_spp"), "Delete Selected", icon=icon("trash"), class="btn-sm btn-danger")
        )
      ),
      navset_card_tab(
        id = ns("layers_tab"),
        nav_panel("Layer A (Trees)", DTOutput(ns("dt_veg_a"))),
        nav_panel("Layer B (Shrubs)", DTOutput(ns("dt_veg_b"))),
        nav_panel("Layer C (Herbs)", DTOutput(ns("dt_veg_c"))),
        nav_panel("Layer D (Moss)", DTOutput(ns("dt_veg_d")))
      )
    )
  )
}

mod_veg_sample_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session
    
    # --- Data State ---
    rv <- reactiveValues(data = NULL)
    
    # --- Loading ---
    observeEvent(sys_state$CurrSU, {
      req(sys_state$CurrSU)
      
      # Using shared con
      
      # Fetch all columns for the current plot, ordered by species
      query <- "SELECT * FROM Sample_Veg WHERE plotnumber = ? ORDER BY species"
      
      # Debug / Fix: ensure simple string passed to duckdb
      plot_id <- as.character(sys_state$CurrSU)
      rv$data <- dbGetQuery(con, query, list(plot_id))
    })
    
    # --- Mappings ---
    display_cols_a <- c("species", "cover1", "height1", "cover2", "height2", "cover3", "height3", "totala", "heighta")
    display_cols_b <- c("species", "cover4", "height4", "cover5", "height5", "totalb", "heightb")
    display_cols_c <- c("species", "cover6", "height6")
    display_cols_d <- c("species", "cover7")
    
    # --- Helper: Render DT ---
    render_layer_dt <- function(cols) {
      renderDT({
        req(rv$data)
        valid_cols <- intersect(cols, names(rv$data))
        d <- rv$data[, valid_cols, drop=FALSE]
        
        datatable(d, 
                  selection = 'single', 
                  editable = TRUE,
                  rownames = FALSE,
                  options = list(
                    pageLength = 50, 
                    dom = 't',
                    ordering = FALSE
                  )) %>% 
          formatStyle(columns = valid_cols, fontSize = '90%')
      })
    }
    
    output$dt_veg_a <- render_layer_dt(display_cols_a)
    output$dt_veg_b <- render_layer_dt(display_cols_b)
    output$dt_veg_c <- render_layer_dt(display_cols_c)
    output$dt_veg_d <- render_layer_dt(display_cols_d)
    
    # --- Helper: Update DB ---
    update_data <- function(info, display_cols) {
      req(sys_state$CurrSU, rv$data)
      
      i <- info$row 
      j <- info$col 
      v <- info$value
      
      col_idx_r <- j + 1
      valid_cols <- intersect(display_cols, names(rv$data))
      col_name <- valid_cols[col_idx_r]
      
      record_id <- rv$data$id[i]
      
      # Update Local State
      # Simple type handling assuming numeric or text
      current_val <- rv$data[i, col_name]
      if (is.numeric(current_val) && !is.na(current_val)) {
        v_typed <- suppressWarnings(as.numeric(v)) 
        if(is.na(v_typed)) v_typed <- v # Fallback if cast fails? Or allow NA?
      } else {
        v_typed <- v
      }
      # Force numeric if column is known numeric (simplification)
      if (col_name %in% c("cover1","cover2","cover3","cover4","cover5","cover6","cover7")) {
          v_typed <- as.numeric(v)
      }

      rv$data[i, col_name] <- v_typed
      
      # Update DB (using shared con)
      
      sql <- sprintf("UPDATE Sample_Veg SET %s = ? WHERE id = ?", col_name)
      
      tryCatch({
        dbExecute(con, sql, list(v_typed, record_id))
      }, error = function(e) {
        showNotification(paste("Error updating DB:", e$message), type = "error")
      })
    }
    
    observeEvent(input$dt_veg_a_cell_edit, { update_data(input$dt_veg_a_cell_edit, display_cols_a) })
    observeEvent(input$dt_veg_b_cell_edit, { update_data(input$dt_veg_b_cell_edit, display_cols_b) })
    observeEvent(input$dt_veg_c_cell_edit, { update_data(input$dt_veg_c_cell_edit, display_cols_c) })
    observeEvent(input$dt_veg_d_cell_edit, { update_data(input$dt_veg_d_cell_edit, display_cols_d) })
    
    # --- Add Species Logic ---
    observeEvent(input$btn_add_spp, {
        req(sys_state$CurrSU)
        
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
            # Get max ID for safety if not auto-increment (Access migration implies we might need to handle IDs)
            # Sample_Veg usually has 'id' column.
            max_res <- dbGetQuery(con, "SELECT MAX(id) as m FROM Sample_Veg")
            new_id <- if(is.na(max_res[[1]])) 1 else max_res[[1]] + 1
            
            dbExecute(con, "INSERT INTO Sample_Veg (id, plotnumber, species) VALUES (?, ?, ?)", 
                      list(new_id, plot_id, new_species))
            
            # Refresh
            rv$data <- dbGetQuery(con, "SELECT * FROM Sample_Veg WHERE plotnumber = ? ORDER BY species", list(plot_id))
            showNotification(paste("Added:", new_species), type="message")
            
        }, error = function(e) {
            showNotification(paste("Error adding species:", e$message), type="error")
        })
    })

    # --- Delete Species Logic ---
    observeEvent(input$btn_del_spp, {
        req(rv$data)
        
        # Determine selected row based on active tab
        idx <- NULL
        tab <- input$layers_tab
        if (is.null(tab)) return()
        
        if (tab == "Layer A (Trees)") idx <- input$dt_veg_a_rows_selected
        else if (tab == "Layer B (Shrubs)") idx <- input$dt_veg_b_rows_selected
        else if (tab == "Layer C (Herbs)") idx <- input$dt_veg_c_rows_selected
        else if (tab == "Layer D (Moss)") idx <- input$dt_veg_d_rows_selected
        
        if (is.null(idx)) {
            showNotification("Please select a species row to delete.", type="warning")
            return()
        }
        
        record_id <- rv$data$id[idx]
        spp_name <- rv$data$species[idx]
        
        # Confirm Dialog? For now direct delete with notification
        # Or better: Modal confirmation
        showModal(modalDialog(
            title = "Confirm Delete",
            paste("Are you sure you want to delete", spp_name, "?"),
            footer = tagList(
                modalButton("Cancel"),
                actionButton(ns("confirm_del_spp"), "Delete", class="btn-danger", onclick = sprintf("Shiny.setInputValue('%s', %d)", ns("del_id_conf"), record_id))
            )
        ))
    })
    
    observeEvent(input$confirm_del_spp, {
        # We need the ID. I used a trick in onclick, but pure Shiny way:
        # Store pending delete ID in reactive
        # Let's use a reactiveVal for pending delete
    })
    
    # Better approach for delete state
    rv_del <- reactiveValues(id = NULL)
    
    observeEvent(input$btn_del_spp, {
        req(rv$data, input$layers_tab)
        idx <- NULL
        if (input$layers_tab == "Layer A (Trees)") idx <- input$dt_veg_a_rows_selected
        else if (input$layers_tab == "Layer B (Shrubs)") idx <- input$dt_veg_b_rows_selected
        else if (input$layers_tab == "Layer C (Herbs)") idx <- input$dt_veg_c_rows_selected
        else if (input$layers_tab == "Layer D (Moss)") idx <- input$dt_veg_d_rows_selected
        
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
        removeModal()
        
        tryCatch({
            dbExecute(con, "DELETE FROM Sample_Veg WHERE id = ?", list(rv_del$id))
            
            # Refresh
            plot_id <- as.character(sys_state$CurrSU)
            rv$data <- dbGetQuery(con, "SELECT * FROM Sample_Veg WHERE plotnumber = ? ORDER BY species", list(plot_id))
            showNotification("Species deleted.", type="message")
            
        }, error = function(e) {
            showNotification(paste("Delete Error:", e$message), type="error")
        })
    })

  })
}
