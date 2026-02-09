save_site_env_header <- function(con, plot_id, fields, project_id = NULL, user = NULL) {
    fields <- lapply(fields, function(value) {
        if (is.null(value) || length(value) == 0) {
            NA
        } else {
            value
        }
    })

    d_save <- fields$date
    if (is.null(d_save)) d_save <- NA
    if (!is.na(d_save)) d_save <- as.character(d_save)

    sql <- paste(
        "UPDATE Sample_Env SET",
        "_location=?, date=?, sitesurveyor=?, latitude=?, longitude=?,",
        "utmeasting=?, utmnorthing=?, elevation=?, slopegradient=?, aspect=?,",
        "mesoslopeposition=?, surfaceshape=?, moistureregime=?, nutrientregime=?, sitenotes=?",
        "WHERE plotnumber=?"
    )

    existing <- DBI::dbGetQuery(con, "SELECT * FROM Sample_Env WHERE plotnumber = ?", list(plot_id))

    res <- DBI::dbExecute(con, sql, list(
        fields$`_location`,
        d_save,
        fields$sitesurveyor,
        fields$latitude,
        fields$longitude,
        fields$utmeasting,
        fields$utmnorthing,
        fields$elevation,
        fields$slopegradient,
        fields$aspect,
        fields$mesoslopeposition,
        fields$surfaceshape,
        fields$moistureregime,
        fields$nutrientregime,
        fields$sitenotes,
        plot_id
    ))

    if (res == 0) {
        sql_ins <- paste(
            "INSERT INTO Sample_Env (plotnumber, _location, date, sitesurveyor, latitude,",
            "longitude, utmeasting, utmnorthing, elevation, slopegradient, aspect,",
            "mesoslopeposition, surfaceshape, moistureregime, nutrientregime, sitenotes)",
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )
        DBI::dbExecute(con, sql_ins, list(
            plot_id,
            fields$`_location`,
            d_save,
            fields$sitesurveyor,
            fields$latitude,
            fields$longitude,
            fields$utmeasting,
            fields$utmnorthing,
            fields$elevation,
            fields$slopegradient,
            fields$aspect,
            fields$mesoslopeposition,
            fields$surfaceshape,
            fields$moistureregime,
            fields$nutrientregime,
            fields$sitenotes
        ))
        if (nrow(existing) == 0) {
            for (field_name in names(fields)) {
                log_audit_change(con, project_id, user, plot_id, "Sample_Env", field_name, NA, fields[[field_name]])
            }
        }
        return("inserted")
    }

    if (nrow(existing) > 0) {
        old_row <- existing[1, , drop = FALSE]
        for (field_name in names(fields)) {
            if (!(field_name %in% names(old_row))) next
            log_audit_change(con, project_id, user, plot_id, "Sample_Env", field_name, old_row[[field_name]][1], fields[[field_name]])
        }
    }

    "updated"
}

soil_numeric_cols <- list(
    Sample_Humus = c("upperdepth", "lowerdepth", "humusformph"),
    Sample_Mineral = c("upperdepth", "lowerdepth", "percentcoarsefragstotal")
)

coerce_soil_value <- function(table, col_name, value) {
    numeric_cols <- soil_numeric_cols[[table]]
    if (!is.null(numeric_cols) && col_name %in% numeric_cols) {
        return(suppressWarnings(as.numeric(value)))
    }
    if (is.null(value) || length(value) == 0 || is.na(value)) {
        return(NA)
    }
    as.character(value)
}

save_soil_cell <- function(con, table, record_id, col_name, value) {
    sql <- sprintf("UPDATE %s SET %s = ? WHERE id = ?", table, col_name)
    DBI::dbExecute(con, sql, list(value, record_id))
}

get_hot_selected_row <- function(selection) {
    if (is.null(selection)) return(NULL)
    if (is.list(selection) && !is.null(selection$r)) return(selection$r)
    if (is.list(selection) && !is.null(selection$select) && !is.null(selection$select$r)) return(selection$select$r)
    if (is.matrix(selection) && ncol(selection) >= 1) return(selection[1, 1])
    NULL
}

mod_site_env_ui <- function(id) {
  ns <- NS(id)
    tab_input <- function(tag, index) {
        tagAppendAttributes(tag, tabindex = index)
    }

  tagList(
    card(
      full_screen = TRUE,
      card_header("Site & Environment"),
      navset_card_tab(
        nav_panel("General", 
            layout_columns(
                            tab_input(textInput(ns("env_location"), "Location"), 1),
                            tab_input(dateInput(ns("env_date"), "Date", value = NULL), 2),
                            tab_input(textInput(ns("env_surveyor"), "Surveyor"), 3),
              col_widths = c(6, 3, 3)
            ),
            layout_columns(
                             tab_input(numericInput(ns("env_lat"), "Latitude", value=0), 4),
                             tab_input(numericInput(ns("env_long"), "Longitude", value=0), 5),
                             tab_input(textInput(ns("env_utme"), "UTM Easting"), 6),
                             tab_input(textInput(ns("env_utmn"), "UTM Northing"), 7),
               col_widths = c(3, 3, 3, 3)
            ),
            layout_columns(
                             tab_input(numericInput(ns("env_elev"), "Elevation (m)", value=0), 8),
                             tab_input(numericInput(ns("env_slope"), "Slope (%)", value=0), 9),
                             tab_input(numericInput(ns("env_aspect"), "Aspect (deg)", value=0), 10),
               col_widths = c(4, 4, 4)
            ),
            layout_columns(
                             tab_input(selectInput(ns("env_meso"), "Meso Slope", choices=NULL), 11),
                             tab_input(selectInput(ns("env_shape"), "Surface Shape", choices=NULL), 12),
                             tab_input(selectInput(ns("env_moisture"), "Moisture Regime", choices=NULL), 13),
                             tab_input(selectInput(ns("env_nutrient"), "Nutrient Regime", choices=NULL), 14),
               col_widths = c(3, 3, 3, 3)
            ),
                        tab_input(textAreaInput(ns("env_notes"), "Site Notes", width = "100%", height = "100px"), 15),
                        div(class="mt-3", tab_input(actionButton(ns("save_header"), "Save General Info", class="btn-primary"), 16)),
                        hr(),
                        div(class = "d-flex align-items-center gap-2",
                            actionButton(ns("run_compliance"), "Run Compliance", class = "btn-secondary"),
                            textOutput(ns("compliance_status"))
                        ),
                        DT::DTOutput(ns("compliance_summary")),
                        DT::DTOutput(ns("compliance_details"))
        ),
        nav_panel("Mensuration",
            layout_columns(
                                tab_input(numericInput(ns("men_age"), "Stand Age (yrs)", value=0), 17),
                                tab_input(numericInput(ns("men_hgt"), "Stand Height (m)", value=0), 18),
                                tab_input(selectInput(ns("men_struct"), "Structural Stage", choices=NULL), 19),
                col_widths = c(4, 4, 4)
            ),
                        div(class="mt-3", tab_input(actionButton(ns("save_mensuration"), "Save Mensuration", class="btn-primary"), 20))
        ),
        nav_panel("Soil: Humus", 
            layout_columns(
               h5("Humus Profile"),
               div(class="text-end", 
                   actionButton(ns("add_humus"), "Add Horizon", icon=icon("plus")),
                   actionButton(ns("edit_humus"), "Edit Selected", icon=icon("pen"), class="btn-warning")
               )
            ),
            rhandsontable::rhandsontableOutput(ns("hot_humus"))
        ),
        nav_panel("Soil: Mineral", 
            layout_columns(
               h5("Mineral Profile"),
               div(class="text-end", 
                   actionButton(ns("add_mineral"), "Add Horizon", icon=icon("plus")),
                   actionButton(ns("edit_mineral"), "Edit Selected", icon=icon("pen"), class="btn-warning")
               )
            ),
            rhandsontable::rhandsontableOutput(ns("hot_mineral"))
                ),
                nav_panel("Audit",
                        DT::DTOutput(ns("dt_audit_env"))
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

    safe_num <- function(value, default = NA_real_) {
        if (is.null(value) || length(value) == 0 || is.na(value)) {
            return(default)
        }
        as.numeric(value)
    }

    safe_chr <- function(value, default = "") {
        if (is.null(value) || length(value) == 0 || is.na(value)) {
            return(default)
        }
        as.character(value)
    }
    
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
            # Update Dropdown Choices first
            choices_meso <- get_list_choices("MesoSlopePosition")
            choices_shape <- get_list_choices("SurfaceShape")
            choices_mois <- get_list_choices("MoistureRegime")
            choices_nut <- get_list_choices("NutrientRegime")
            choices_struct <- get_list_choices("StructuralStage")
            
            updateSelectInput(session, "env_meso", choices=c("", choices_meso), selected=rv$env$mesoslopeposition[1])
            updateSelectInput(session, "env_shape", choices=c("", choices_shape), selected=rv$env$surfaceshape[1])
            updateSelectInput(session, "env_moisture", choices=c("", choices_mois), selected=rv$env$moistureregime[1])
            updateSelectInput(session, "env_nutrient", choices=c("", choices_nut), selected=rv$env$nutrientregime[1])
            updateSelectInput(session, "men_struct", choices=c("", choices_struct), selected=rv$env$structuralstage[1])

            updateTextInput(session, "env_location", value = safe_chr(rv$env[["_location"]][1]))
            
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
            
            updateTextInput(session, "env_surveyor", value = safe_chr(rv$env$sitesurveyor[1]))
            updateNumericInput(session, "env_lat", value = safe_num(rv$env$latitude[1]))
            updateNumericInput(session, "env_long", value = safe_num(rv$env$longitude[1]))
            updateTextInput(session, "env_utme", value = safe_chr(rv$env$utmeasting[1]))
            updateTextInput(session, "env_utmn", value = safe_chr(rv$env$utmnorthing[1]))
            
            updateNumericInput(session, "env_elev", value = safe_num(rv$env$elevation[1]))
            updateNumericInput(session, "env_slope", value = safe_num(rv$env$slopegradient[1]))
            updateNumericInput(session, "env_aspect", value = safe_num(rv$env$aspect[1]))
            
            updateTextAreaInput(session, "env_notes", value = safe_chr(rv$env$sitenotes[1]))
            
            # Mensuration
            updateNumericInput(session, "men_age", value = safe_num(rv$env$standage[1]))
            # sv_standheight is likely the column, or sv_standheightestmeas
            # Checking recent dbListFields: sv_standheightestmeas and sv_standheight are there.
            # Usually strict numbers go in standheight if available.
            val_hgt <- safe_num(rv$env$sv_standheight[1])
            updateNumericInput(session, "men_hgt", value = val_hgt)
        }
    })
    
    # -- Save Header --
    observeEvent(input$save_header, {
        req(sys_state$CurrSU)
        plot_id <- as.character(sys_state$CurrSU)
        
        tryCatch({
            result <- save_site_env_header(
                con,
                plot_id,
                list(
                    `_location` = input$env_location,
                    date = input$env_date,
                    sitesurveyor = input$env_surveyor,
                    latitude = input$env_lat,
                    longitude = input$env_long,
                    utmeasting = input$env_utme,
                    utmnorthing = input$env_utmn,
                    elevation = input$env_elev,
                    slopegradient = input$env_slope,
                    aspect = input$env_aspect,
                    mesoslopeposition = input$env_meso,
                    surfaceshape = input$env_shape,
                    moistureregime = input$env_moisture,
                    nutrientregime = input$env_nutrient,
                    sitenotes = input$env_notes
                ),
                sys_state$CurrProject,
                sys_state$User
            )

            if (result == "inserted") {
                showNotification("Header created successfully.", type = "message")
            } else {
                showNotification("Header updated successfully.", type = "message")
            }

            rv$env <- dbGetQuery(con, "SELECT * FROM Sample_Env WHERE plotnumber = ?", list(plot_id))
        }, error = function(e) {
            showNotification(paste("Error saving header:", e$message), type="error")
        })
    })

    # -- Save Mensuration --
    observeEvent(input$save_mensuration, {
        req(sys_state$CurrSU)
        plot_id <- as.character(sys_state$CurrSU)
        
        sql <- "UPDATE Sample_Env SET standage=?, sv_standheight=?, structuralstage=? WHERE plotnumber=?"
        
        tryCatch({
            res <- dbExecute(con, sql, list(
                input$men_age,
                input$men_hgt,
                input$men_struct,
                plot_id
            ))
            
            if (res == 0) {
                showNotification("Record does not exist to update mensuration.", type="error")
            } else {
                showNotification("Mensuration updated.", type="message")
            }
        }, error = function(e) {
            showNotification(paste("Error saving mensuration:", e$message), type="error")
        })
    })

    # -- Compliance --
    compliance_result <- reactiveVal(NULL)

    observeEvent(input$run_compliance, {
        project_id <- sys_state$CurrProject
        compliance_result(run_compliance_checks(con, project_id))
    })

    output$compliance_status <- renderText({
        result <- compliance_result()
        if (is.null(result)) return("")
        if (isTRUE(result$passed)) "All checks passed" else "Issues found"
    })

    output$compliance_summary <- DT::renderDT({
        result <- compliance_result()
        req(result)
        DT::datatable(result$summary_tibble, rownames = FALSE, options = list(dom = "t", ordering = FALSE))
    })

    output$compliance_details <- DT::renderDT({
        result <- compliance_result()
        req(result)
        DT::datatable(result$detail_tibble, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })

    output$dt_audit_env <- DT::renderDT({
        req(sys_state$CurrSU)
        audit <- fetch_audit_entries(con, plot_number = sys_state$CurrSU, project_id = sys_state$CurrProject)
        DT::datatable(audit, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })

    # -- Editable Grids --
    render_soil_hot <- function(data_source, display_cols) {
        rhandsontable::renderRHandsontable({
            req(data_source())
            d <- data_source()
            valid_cols <- intersect(display_cols, names(d))
            view <- d[, valid_cols, drop = FALSE]

            rhandsontable::rhandsontable(
                view,
                rowHeaders = FALSE,
                useTypes = TRUE,
                stretchH = "all"
            )
        })
    }

    cols_humus <- c("horizon", "upperdepth", "lowerdepth", "humusstructuredegree", "humusstructurekind", "humusformph", "_comment")
    output$hot_humus <- render_soil_hot(reactive(rv$humus), cols_humus)
    
    cols_mineral <- c("horizon", "upperdepth", "lowerdepth", "texture", "percentcoarsefragstotal", "mineralstructureclass", "colour", "_comments")
    output$hot_mineral <- render_soil_hot(reactive(rv$mineral), cols_mineral)

    update_soil_from_hot <- function(hot_input, table, display_cols) {
        req(hot_input)
        new_df <- rhandsontable::hot_to_r(hot_input)

        current <- if (table == "Sample_Humus") rv$humus else rv$mineral
        req(current)
        valid_cols <- intersect(display_cols, names(current))
        old_df <- current[, valid_cols, drop = FALSE]

        if (nrow(new_df) != nrow(old_df)) return()

        for (row_idx in seq_len(nrow(new_df))) {
            for (col_name in valid_cols) {
                old_val <- old_df[[col_name]][row_idx]
                new_val <- new_df[[col_name]][row_idx]

                if (is.na(old_val) && is.na(new_val)) next
                if (!is.na(old_val) && !is.na(new_val) && as.character(old_val) == as.character(new_val)) next
                if (is.na(old_val) && nzchar(as.character(new_val)) == FALSE) next

                record_id <- current$id[row_idx]
                typed_val <- coerce_soil_value(table, col_name, new_val)

                tryCatch({
                    save_soil_cell(con, table, record_id, col_name, typed_val)
                    log_audit_change(
                        con,
                        sys_state$CurrProject,
                        sys_state$User,
                        current$plotnumber[row_idx],
                        table,
                        col_name,
                        old_val,
                        typed_val
                    )
                }, error = function(e) {
                    showNotification(paste("Update Error:", e$message), type = "error")
                })
            }
        }

        if (table == "Sample_Humus") {
            rv$humus <- dbGetQuery(con, "SELECT * FROM Sample_Humus WHERE plotnumber = ? ORDER BY horizon", list(sys_state$CurrSU))
        }
        if (table == "Sample_Mineral") {
            rv$mineral <- dbGetQuery(con, "SELECT * FROM Sample_Mineral WHERE plotnumber = ? ORDER BY horizon", list(sys_state$CurrSU))
        }
    }

    observeEvent(input$hot_humus, {
        update_soil_from_hot(input$hot_humus, "Sample_Humus", cols_humus)
    })

    observeEvent(input$hot_mineral, {
        update_soil_from_hot(input$hot_mineral, "Sample_Mineral", cols_mineral)
    })

    # -- Better Modal State Management --
    rv_modal <- reactiveValues(mode = "new", id = NULL, type = NULL)
    
    observeEvent(input$add_humus, {
        rv_modal$mode <- "new"
        rv_modal$type <- "humus"
        showModal(modal_humus(TRUE))
    })
    
    observeEvent(input$edit_humus, {
        row_idx <- get_hot_selected_row(input$hot_humus_select)
        req(row_idx)
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
        row_idx <- get_hot_selected_row(input$hot_mineral_select)
        req(row_idx)
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
