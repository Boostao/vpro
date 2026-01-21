mod_site_env_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Site & Environment"),
      navset_card_tab(
        nav_panel("General", 
            layout_columns(
              textInput(ns("env_location"), "Location"),
              dateInput(ns("env_date"), "Date", value = NULL),
              textInput(ns("env_surveyor"), "Surveyor"),
              col_widths = c(6, 3, 3)
            ),
            layout_columns(
               numericInput(ns("env_lat"), "Latitude", value=0),
               numericInput(ns("env_long"), "Longitude", value=0),
               textInput(ns("env_utme"), "UTM Easting"),
               textInput(ns("env_utmn"), "UTM Northing"),
               col_widths = c(3, 3, 3, 3)
            ),
            textAreaInput(ns("env_notes"), "Site Notes", width = "100%", height = "100px"),
            div(class="mt-3", actionButton(ns("save_header"), "Save General Info", class="btn-primary"))
        ),
        nav_panel("Soil: Humus", 
            layout_columns(
               h5("Humus Profile"),
               div(class="text-end", 
                   actionButton(ns("add_humus"), "Add Horizon", icon=icon("plus")),
                   actionButton(ns("edit_humus"), "Edit Selected", icon=icon("pen"), class="btn-warning")
               )
            ),
            DTOutput(ns("dt_humus"))
        ),
        nav_panel("Soil: Mineral", 
            layout_columns(
               h5("Mineral Profile"),
               div(class="text-end", 
                   actionButton(ns("add_mineral"), "Add Horizon", icon=icon("plus")),
                   actionButton(ns("edit_mineral"), "Edit Selected", icon=icon("pen"), class="btn-warning")
               )
            ),
            DTOutput(ns("dt_mineral"))
        )
      )
    )
  )
}

mod_site_env_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Reactive Data Store
    rv <- reactiveValues(env = NULL, humus = NULL, mineral = NULL)
    
    # -- Load Data --
    observeEvent(sys_state$CurrSU, {
        req(sys_state$CurrSU)
        plot_id <- as.character(sys_state$CurrSU)
        
        # con provided by moduleServer arguments
        
        rv$env <- dbGetQuery(con, "SELECT * FROM Sample_Env WHERE plotnumber = ?", list(plot_id))
        rv$humus <- dbGetQuery(con, "SELECT * FROM Sample_Humus WHERE plotnumber = ? ORDER BY horizon", list(plot_id))
        rv$mineral <- dbGetQuery(con, "SELECT * FROM Sample_Mineral WHERE plotnumber = ? ORDER BY horizon", list(plot_id))
        
        # Populate Inputs
        if(nrow(rv$env) > 0) {
            updateTextInput(session, "env_location", value = rv$env[["_location"]][1])
            
            # Safe Date Handling
            d_val <- rv$env$date[1]
            if(inherits(d_val, "Date") || inherits(d_val, "POSIXt")) {
                updateDateInput(session, "env_date", value = as.Date(d_val))
            } else if (is.character(d_val) && !is.na(d_val) && d_val != "") {
                # Try simple cast
                updateDateInput(session, "env_date", value = tryCatch(as.Date(d_val), error=function(e) NULL))
            } else {
                updateDateInput(session, "env_date", value = NULL)
            }
            
            updateTextInput(session, "env_surveyor", value = rv$env$sitesurveyor[1])
            updateNumericInput(session, "env_lat", value = as.numeric(rv$env$latitude[1]))
            updateNumericInput(session, "env_long", value = as.numeric(rv$env$longitude[1]))
            updateTextInput(session, "env_utme", value = as.character(rv$env$utmeasting[1]))
            updateTextInput(session, "env_utmn", value = as.character(rv$env$utmnorthing[1]))
            updateTextAreaInput(session, "env_notes", value = rv$env$sitenotes[1])
        }
    })
    
    # -- Save Header --
    observeEvent(input$save_header, {
        req(sys_state$CurrSU)
        plot_id <- as.character(sys_state$CurrSU)
        
        # con provided by moduleServer arguments
        
        # Handle Date Logic for DB
        d_save <- input$env_date
        if(is.null(d_save)) d_save <- NA
        if(!is.na(d_save)) d_save <- as.character(d_save)
        
        sql <- "UPDATE Sample_Env SET _location=?, date=?, sitesurveyor=?, latitude=?, longitude=?, utmeasting=?, utmnorthing=?, sitenotes=? WHERE plotnumber=?"
        
        tryCatch({
            res <- dbExecute(con, sql, list(
                input$env_location, 
                d_save,
                input$env_surveyor,
                input$env_lat,
                input$env_long,
                input$env_utme,
                input$env_utmn,
                input$env_notes,
                plot_id
            ))
            
            if (res == 0) {
                # Update failed (row doesn't exist), try INSERT
                sql_ins <- "INSERT INTO Sample_Env (plotnumber, _location, date, sitesurveyor, latitude, longitude, utmeasting, utmnorthing, sitenotes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                dbExecute(con, sql_ins, list(
                    plot_id,
                    input$env_location, 
                    d_save,
                    input$env_surveyor,
                    input$env_lat,
                    input$env_long,
                    input$env_utme,
                    input$env_utmn,
                    input$env_notes
                ))
                showNotification("Header created successfully.", type="message")
                
                # Update reactive value to ensure subsequent loads work
                rv$env <- dbGetQuery(con, "SELECT * FROM Sample_Env WHERE plotnumber = ?", list(plot_id))
            } else {
                showNotification("Header updated successfully.", type="message")
            }
        }, error = function(e) {
            showNotification(paste("Error saving header:", e$message), type="error")
        })
    })

    # -- Grid Rendering (Non-Editable) --
    render_grid <- function(data_source, display_cols) {
        renderDT({
            req(data_source())
            d <- data_source()
            valid_cols <- intersect(display_cols, names(d))
            datatable(d[, valid_cols, drop=FALSE],
                      selection = 'single', # Enable Row Selection
                      editable = FALSE,     # Disable Grid Edit
                      rownames = FALSE,
                      options = list(dom='t', pageLength=50, ordering=FALSE))
        })
    }

    cols_humus <- c("horizon", "upperdepth", "lowerdepth", "humusstructuredegree", "humusstructurekind", "humusformph", "_comment")
    output$dt_humus <- render_grid(reactive(rv$humus), cols_humus)
    
    cols_mineral <- c("horizon", "upperdepth", "lowerdepth", "texture", "percentcoarsefragstotal", "mineralstructureclass", "colour", "_comments")
    output$dt_mineral <- render_grid(reactive(rv$mineral), cols_mineral)

    # -- Better Modal State Management --
    rv_modal <- reactiveValues(mode = "new", id = NULL, type = NULL)
    
    observeEvent(input$add_humus, {
        rv_modal$mode <- "new"
        rv_modal$type <- "humus"
        showModal(modal_humus(TRUE))
    })
    
    observeEvent(input$edit_humus, {
        req(input$dt_humus_rows_selected)
        row_idx <- input$dt_humus_rows_selected
        record <- rv$humus[row_idx, ]
        rv_modal$mode <- "edit"
        rv_modal$id <- record$id
        rv_modal$type <- "humus"
        showModal(modal_humus(FALSE, record))
    })
    
    # (Duplicate save_humus handler removed)
    
    # -- Mineral Modal Logic --
    observeEvent(input$add_mineral, {
        rv_modal$mode <- "new"
        rv_modal$type <- "mineral"
        showModal(modal_mineral(TRUE))
    })
    
    observeEvent(input$edit_mineral, {
        req(input$dt_mineral_rows_selected)
        row_idx <- input$dt_mineral_rows_selected
        record <- rv$mineral[row_idx, ]
        rv_modal$mode <- "edit"
        rv_modal$id <- record$id
        rv_modal$type <- "mineral"
        showModal(modal_mineral(FALSE, record))
    })

    # -- Helper for Dropdowns --
    get_list_choices <- function(list_name) {
        # Query the ATTACHED 'lists' database
        # Using shared connection `con` which already has 'lists' attached.
        
        # Note: Columns are lowercased in the DB
        df <- dbGetQuery(con, "SELECT item, itemdescription FROM lists.USysTableOfLists WHERE listname = ? ORDER BY itemorder", list(list_name))
        if(nrow(df) > 0) {
            # Create named vector: "Description" = "Code" (or just Code if no desc)
            # Access logic usually shows Description but stores Code (Item)
            # Let's combine them: "Code - Description"
            setNames(df$item, paste(df$item, "-", df$itemdescription))
        } else {
            NULL
        }
    }

    modal_humus <- function(new, record=NULL) {
        
        # Load choices dynamically
        c_horizon <- get_list_choices("HumusHorizon")
        c_deg <- get_list_choices("HumusStructureDegree")
        c_kind <- get_list_choices("HumusStructureKind")
        
        modalDialog(
            title = if(new) "Add Humus Horizon" else "Edit Humus Horizon",
            layout_columns(
                # Use SelectInput if choices exist, else TextInput
                if(!is.null(c_horizon)) selectInput(ns("h_horizon"), "Horizon", choices=c("", c_horizon), selected = if(!new) record$horizon else "") 
                else textInput(ns("h_horizon"), "Horizon", value = if(!new) record$horizon else ""),
                
                numericInput(ns("h_upper"), "Upper Depth", value = if(!new) record$upperdepth else 0),
                numericInput(ns("h_lower"), "Lower Depth", value = if(!new) record$lowerdepth else 0),
                col_widths = c(4, 4, 4)
            ),
            layout_columns(
                if(!is.null(c_deg)) selectInput(ns("h_deg"), "Structure Degree", choices=c("", c_deg), selected = if(!new) record$humusstructuredegree else "")
                else textInput(ns("h_deg"), "Structure Degree", value = if(!new) record$humusstructuredegree else ""),
                
                if(!is.null(c_kind)) selectInput(ns("h_kind"), "Structure Kind", choices=c("", c_kind), selected = if(!new) record$humusstructurekind else "")
                else textInput(ns("h_kind"), "Structure Kind", value = if(!new) record$humusstructurekind else ""),
                
                col_widths = c(6, 6)
            ),
            numericInput(ns("h_ph"), "pH", value = if(!new) record$humusformph else NA),
            textInput(ns("h_comment"), "Comment", value = if(!new) record[["_comment"]] else ""),
            
            footer = tagList(
                modalButton("Cancel"),
                actionButton(ns("save_humus"), "Save", class = "btn-primary")
            )
        )
    }
    
    observeEvent(input$save_humus, {
        req(rv_modal$type == "humus")
        save_soil_record("Sample_Humus", rv_modal$mode, rv_modal$id, 
                         list(
                             horizon = input$h_horizon,
                             upperdepth = input$h_upper,
                             lowerdepth = input$h_lower,
                             humusstructuredegree = input$h_deg,
                             humusstructurekind = input$h_kind,
                             humusformph = input$h_ph,
                             `_comment` = input$h_comment,
                             plotnumber = as.character(sys_state$CurrSU)
                         ))
        removeModal()
    })
    
    modal_mineral <- function(new, record=NULL) {
        modalDialog(
            title = if(new) "Add Mineral Horizon" else "Edit Mineral Horizon",
            layout_columns(
                textInput(ns("m_horizon"), "Horizon", value = if(!new) record$horizon else ""),
                numericInput(ns("m_upper"), "Upper Depth", value = if(!new) record$upperdepth else 0),
                numericInput(ns("m_lower"), "Lower Depth", value = if(!new) record$lowerdepth else 0),
                col_widths = c(4, 4, 4)
            ),
            layout_columns(
                textInput(ns("m_texture"), "Texture", value = if(!new) record$texture else ""),
                textInput(ns("m_struct"), "Structure", value = if(!new) record$mineralstructureclass else ""),
                col_widths = c(6, 6)
            ),
            layout_columns(
                numericInput(ns("m_cf"), "% Coarse Frag", value = if(!new) record$percentcoarsefragstotal else 0),
                textInput(ns("m_col"), "Colour", value = if(!new) record$colour else ""),
                col_widths = c(6, 6)
            ),
            textInput(ns("m_comment"), "Comment", value = if(!new) record[["_comments"]] else ""),
            
            footer = tagList(
                modalButton("Cancel"),
                actionButton(ns("save_mineral"), "Save", class = "btn-primary")
            )
        )
    }

    observeEvent(input$save_mineral, {
        req(rv_modal$type == "mineral")
        save_soil_record("Sample_Mineral", rv_modal$mode, rv_modal$id, 
                         list(
                             horizon = input$m_horizon,
                             upperdepth = input$m_upper,
                             lowerdepth = input$m_lower,
                             texture = input$m_texture,
                             mineralstructureclass = input$m_struct,
                             percentcoarsefragstotal = input$m_cf,
                             colour = input$m_col,
                             `_comments` = input$m_comment, # Note schema spelling 'comments' vs 'comment'
                             plotnumber = as.character(sys_state$CurrSU)
                         ))
        removeModal()
    })
    
    # -- Generic Save Helper --
    save_soil_record <- function(table, mode, id, fields) {
        # Using shared connection `con`
        
        if (mode == "new") {
            # Generate ID safely
            max_res <- dbGetQuery(con, sprintf("SELECT MAX(id) as m FROM %s", table))
            max_id <- if(is.na(max_res[[1]])) 0 else max_res[[1]]
            new_id <- max_id + 1
            fields$id <- new_id
            
            # Construct INSERT
            cols <- names(fields)
            placeholders <- paste(rep("?", length(cols)), collapse=", ")
            sql <- sprintf("INSERT INTO %s (%s) VALUES (%s)", table, paste(cols, collapse=", "), placeholders)
            values <- unname(fields)
            # Ensure values list is flat and lacks NULLs (replace with explicit NA if needed)
            
            tryCatch({
                dbExecute(con, sql, values)
                showNotification("Record added.", type="message")
                # Refresh Data
                if(table == "Sample_Humus") rv$humus <- dbGetQuery(con, "SELECT * FROM Sample_Humus WHERE plotnumber = ? ORDER BY horizon", list(fields$plotnumber))
                if(table == "Sample_Mineral") rv$mineral <- dbGetQuery(con, "SELECT * FROM Sample_Mineral WHERE plotnumber = ? ORDER BY horizon", list(fields$plotnumber))
            }, error = function(e) { showNotification(paste("Insert Error:", e$message), type="error") })
            
        } else {
            # Construct UPDATE
            # fields contains all data, but we filter out plotnumber usually? No, update it too for safety or ignore.
            # We exclude 'id' from fields list passed in, we use 'id' arg.
            
            # Remove plotnumber from update fields generally unless we allow moving horizons between plots (unlikely)
            update_fields <- fields[names(fields) != "plotnumber"]
            
            set_clause <- paste(names(update_fields), "= ?", collapse=", ")
            sql <- sprintf("UPDATE %s SET %s WHERE id = ?", table, set_clause)
            values <- c(unname(update_fields), id)
            
            tryCatch({
                dbExecute(con, sql, values)
                showNotification("Record updated.", type="message")
                # Refresh Data
                if(table == "Sample_Humus") rv$humus <- dbGetQuery(con, "SELECT * FROM Sample_Humus WHERE plotnumber = ? ORDER BY horizon", list(fields$plotnumber))
                if(table == "Sample_Mineral") rv$mineral <- dbGetQuery(con, "SELECT * FROM Sample_Mineral WHERE plotnumber = ? ORDER BY horizon", list(fields$plotnumber))
            }, error = function(e) { showNotification(paste("Update Error:", e$message), type="error") })
        }
    }
    
  })
}
