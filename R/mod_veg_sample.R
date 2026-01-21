mod_veg_sample_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Vegetation Data"),
      navset_card_tab(
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
                  selection = 'none', 
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
    
  })
}
