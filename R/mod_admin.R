
mod_admin_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_fillable(
      navset_card_tab(
        full_screen = TRUE,
        
        # --- TAB 1: Project Metadata ---
        nav_panel("Project Metadata",
           layout_sidebar(
             sidebar = sidebar(
               selectInput(ns("proj_select"), "Select Project", choices = NULL),
               actionButton(ns("proj_new"), "New Project", class = "btn-success w-100 mt-2"),
               div(class="mt-4"),
               h5("Actions"),
               actionButton(ns("proj_del"), "Delete Selected", class = "btn-danger w-100")
             ),
             card(
               card_header(textOutput(ns("proj_form_header"))),
               card_body(
                 textInput(ns("proj_id"), "Project ID (Unique Key)"),
                 textInput(ns("proj_title"), "Project Title"),
                 textInput(ns("proj_coord"), "Coordinating Agency"),
                 layout_column_wrap(
                   width = 1/2,
                   textInput(ns("proj_start"), "Start Date (Text)"),
                   textInput(ns("proj_end"), "End Date (Text)")
                 ),
                 textAreaInput(ns("proj_notes"), "Notes", rows = 5),
                 div(class = "d-flex justify-content-end",
                     actionButton(ns("proj_save"), "Save Project", class = "btn-primary btn-lg")
                 )
               )
             )
           )        
        ),
        
        # --- TAB 2: Code Maintenance ---
        nav_panel("Code Maintenance",
           layout_sidebar(
             sidebar = sidebar(
               selectInput(ns("code_list_select"), "Select Lookup List", choices = NULL),
               actionButton(ns("code_refresh"), "Refresh Lists", class = "btn-secondary w-100 mt-2")
             ),
             card(
               card_header(textOutput(ns("code_list_header"))),
               card_body(
                 DTOutput(ns("code_dt")),
                 div(class = "mt-3 d-flex gap-2",
                     actionButton(ns("code_add_row"), "Add Row", class = "btn-info"),
                     actionButton(ns("code_save"), "Save All Item Changes", class = "btn-warning")
                 ),
                 helpText("Double-click cells to edit. Added rows appear at bottom. 'Save' overwrites the list in DB.")
               )
             )
           )
        ),
        nav_panel("Audit Log",
           layout_sidebar(
             sidebar = sidebar(
               textInput(ns("audit_project"), "Project", value = ""),
               textInput(ns("audit_plot"), "Plot", value = ""),
               selectInput(ns("audit_table"), "Table", choices = c("All" = "")),
              dateInput(ns("audit_from"), "From", value = NULL),
              dateInput(ns("audit_to"), "To", value = NULL),
              actionButton(ns("audit_refresh"), "Refresh", class = "btn-secondary w-100 mt-2"),
              downloadButton(ns("audit_export"), "Export CSV", class = "btn-outline-primary w-100 mt-2")
             ),
             card(
               card_header("Audit Trail"),
               card_body(
                 DTOutput(ns("audit_dt"))
               )
             )
           )
        )
      )
    )
  )
}

mod_admin_server <- function(id, con) {
  moduleServer(id, function(input, output, session) {
    
    # ==========================================================================
    # 1. Project Metadata Logic
    # ==========================================================================
    
    # Reactive list of projects
    update_proj_list <- function(selected_id = NULL) {
      projs <- dbGetQuery(con, "SELECT projectid, projecttitle FROM USysProjectMetadata ORDER BY projectid")
      choices <- NULL
      if (nrow(projs) > 0) {
        choices <- setNames(projs$projectid, paste(projs$projectid, "-", projs$projecttitle))
      }
      updateSelectInput(session, "proj_select", choices = choices, selected = selected_id)
    }
    
    update_proj_list() # Init
    
    # Observe Selection
    observeEvent(input$proj_select, {
      req(input$proj_select)
      pid <- input$proj_select
      
      data <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(pid))
      
      if (nrow(data) > 0) {
        # Bind data
        updateTextInput(session, "proj_id", value = data$projectid)
        # Lock ID for edit
        shinyjs::disable("proj_id") 
        
        updateTextInput(session, "proj_title", value = data$projecttitle)
        updateTextInput(session, "proj_coord", value = data$coordinatingagency)
        updateTextInput(session, "proj_start", value = data$startdate)
        updateTextInput(session, "proj_end", value = data$enddate)
        updateTextAreaInput(session, "proj_notes", value = data$notes)
        
        output$proj_form_header <- renderText(paste("Editing:", data$projecttitle))
      }
    }, ignoreInit = TRUE)
    
    # New Project
    observeEvent(input$proj_new, {
      shinyjs::enable("proj_id")
      updateTextInput(session, "proj_id", value = "")
      updateTextInput(session, "proj_title", value = "")
      updateTextInput(session, "proj_coord", value = "")
      updateTextInput(session, "proj_start", value = "")
      updateTextInput(session, "proj_end", value = "")
      updateTextAreaInput(session, "proj_notes", value = "")
      output$proj_form_header <- renderText("New Project")
      
      # Clear selection to show we are in 'new' mode logic if needed, 
      # but simplistic way is just relying on proj_id input being new.
    })
    
    # Save Project
    observeEvent(input$proj_save, {
      req(input$proj_id) # ID is mandatory
      
      is_new <- FALSE
      # Check existence
      exists <- dbGetQuery(con, "SELECT 1 FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      existing <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      
      tryCatch({
          if (nrow(exists) > 0) {
            # Update
            dbExecute(con, "UPDATE USysProjectMetadata SET projecttitle=?, coordinatingagency=?, startdate=?, enddate=?, notes=? WHERE projectid=?",
                      list(input$proj_title, input$proj_coord, input$proj_start, input$proj_end, input$proj_notes, input$proj_id))
            if (nrow(existing) > 0) {
              new_row <- data.frame(
                projecttitle = input$proj_title,
                coordinatingagency = input$proj_coord,
                startdate = input$proj_start,
                enddate = input$proj_end,
                notes = input$proj_notes,
                stringsAsFactors = FALSE
              )
              log_audit_diff(
                con,
                input$proj_id,
                "Admin",
                input$proj_id,
                "USysProjectMetadata",
                existing[1, , drop = FALSE],
                new_row,
                fields = c("projecttitle", "coordinatingagency", "startdate", "enddate", "notes")
              )
            }
            showNotification("Project Updated", type = "message")
          } else {
            # Insert
            dbExecute(con, "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes) VALUES (?, ?, ?, ?, ?, ?)",
                      list(input$proj_id, input$proj_title, input$proj_coord, input$proj_start, input$proj_end, input$proj_notes))
            log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "projecttitle", NA, input$proj_title)
            log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "coordinatingagency", NA, input$proj_coord)
            log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "startdate", NA, input$proj_start)
            log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "enddate", NA, input$proj_end)
            log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "notes", NA, input$proj_notes)
            showNotification("Project Created", type = "message")
          }
          update_proj_list(selected_id = input$proj_id)
      }, error = function(e) {
          showNotification(paste("Error:", e$message), type = "error")
      })
    })
    
    # Delete Project
    observeEvent(input$proj_del, {
      req(input$proj_id)
      existing <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      # In a real app, use a modalDialog confirm here
      tryCatch({
        dbExecute(con, "DELETE FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
        if (nrow(existing) > 0) {
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "projecttitle", existing$projecttitle[1], NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "coordinatingagency", existing$coordinatingagency[1], NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "startdate", existing$startdate[1], NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "enddate", existing$enddate[1], NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "notes", existing$notes[1], NA)
        }
        showNotification("Project Deleted", type = "warning")
        updateTextInput(session, "proj_id", value = "") # Clear form
        update_proj_list()
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
      })
    })
    
    
    # ==========================================================================
    # 2. Code Maintenance Logic
    # ==========================================================================
    
    # Using 'rv' to hold the current table data for editing
    rv_codes <- reactiveValues(data = NULL)
    
    # Load List Names
    observe({
      # Assuming 'lists' schema attached in server.R
      tryCatch({
         lists <- dbGetQuery(con, "SELECT DISTINCT listname FROM lists.USysTableOfLists ORDER BY listname")
         updateSelectInput(session, "code_list_select", choices = lists$listname)
      }, error = function(e) {
         # Fallback if lists not attached (dev mode sometimes)
         print(e)
      })
    })
    
    # Load Table Data
    observeEvent(input$code_list_select, {
      req(input$code_list_select)
      query <- "SELECT item, itemdescription, itemorder FROM lists.USysTableOfLists WHERE listname = ? ORDER BY itemorder"
      df <- dbGetQuery(con, query, list(input$code_list_select))
      rv_codes$data <- df
      output$code_list_header <- renderText(paste("List:", input$code_list_select))
    })
    
    # Render DT
    output$code_dt <- renderDT({
      req(rv_codes$data)
      datatable(rv_codes$data, 
                editable = 'cell', 
                selection = 'none',
                options = list(pageLength = 15, dom = 't,p'))
    })
    
    # Handle Cell Edits
    observeEvent(input$code_dt_cell_edit, {
      info <- input$code_dt_cell_edit
      # info keys: row, col, value
      i <- info$row
      j <- info$col + 1 # DT uses 0-based col (sometimes, depending on rownames), R uses 1-based
      v <- info$value
      
      rv_codes$data[i, j] <- coerceValue(v, rv_codes$data[i, j])
    })
    
    # Handle Add Row
    observeEvent(input$code_add_row, {
      req(rv_codes$data)
      new_row <- data.frame(
        item = "NEW_CODE",
        itemdescription = "New Description",
        itemorder = 0,
        stringsAsFactors = FALSE
      )
      rv_codes$data <- rbind(rv_codes$data, new_row)
    })
    
    # Handle Save
    observeEvent(input$code_save, {
      req(input$code_list_select)
      req(rv_codes$data)
      lname <- input$code_list_select

      old_rows <- dbGetQuery(con, "SELECT item, itemdescription, itemorder FROM lists.USysTableOfLists WHERE listname = ?", list(lname))
      
      # Transactional Replacement
      dbBegin(con)
      tryCatch({
        # 1. Delete existing for this list
        dbExecute(con, "DELETE FROM lists.USysTableOfLists WHERE listname = ?", list(lname))
        
        # 2. Insert new
        # Make a DF that matches schema
        # Schema has: listname, listfilter, itemorder, item, itemdescription, fieldusedin, validateloops, _validate, note, flag
        # We only have item, itemdescription, itemorder. We need to fill listname. Others can be NULL or default.
        
        to_save <- rv_codes$data
        to_save$listname <- lname
        
        # We need to ensure column order or use named insert
        # Simplest is dbWriteTable with append=TRUE, if columns match.
        # But dbWriteTable might fail if columns missing.
        # Better: use dbAppendTable with a matching DF.
        
        # Fetch empty structure
        # template <- dbGetQuery(con, "SELECT * FROM lists.USysTableOfLists LIMIT 0")
        # common_cols <- intersect(names(template), names(to_save))
        # ... logic too complex for simple insert.
        
        # Custom INSERT
        # Query: INSERT INTO lists.USysTableOfLists (listname, item, itemdescription, itemorder) VALUES ...
        
        # Prepare statement
        sql <- "INSERT INTO lists.USysTableOfLists (listname, item, itemdescription, itemorder) VALUES (?, ?, ?, ?)"
        
        # Loop or bind
        # DuckDB R client supports bulk insert via dbAppendTable if dataframes match. 
        # But we only have partial columns.
        
        # Let's iterate (slow but safe for admin tool)
        for(i in 1:nrow(to_save)) {
            dbExecute(con, sql, list(to_save$listname[i], to_save$item[i], to_save$itemdescription[i], as.numeric(to_save$itemorder[i])))
        }
        
        dbCommit(con)
        showNotification("List saved successfully.", type = "message")

        if (nrow(to_save) > 0 || nrow(old_rows) > 0) {
          old_map <- if (nrow(old_rows) > 0) split(old_rows, old_rows$item) else list()
          new_map <- if (nrow(to_save) > 0) split(to_save, to_save$item) else list()

          removed_items <- setdiff(names(old_map), names(new_map))
          added_items <- setdiff(names(new_map), names(old_map))
          common_items <- intersect(names(old_map), names(new_map))

          for (item_key in removed_items) {
            row <- old_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "item", row$item, NA)
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemdescription", row$itemdescription, NA)
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemorder", row$itemorder, NA)
          }

          for (item_key in added_items) {
            row <- new_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "item", NA, row$item)
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemdescription", NA, row$itemdescription)
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemorder", NA, row$itemorder)
          }

          for (item_key in common_items) {
            old_row <- old_map[[item_key]][1, , drop = FALSE]
            new_row <- new_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemdescription", old_row$itemdescription, new_row$itemdescription)
            log_audit_change(con, NA, "Admin", lname, "lists.USysTableOfLists", "itemorder", old_row$itemorder, new_row$itemorder)
          }
        }
        
      }, error = function(e) {
        dbRollback(con)
        showNotification(paste("Save failed:", e$message), type = "error")
      })
    })

    # ==========================================================================
    # 3. Audit Log
    # ==========================================================================

    observe({
      if (!audit_table_exists(con)) {
        updateSelectInput(session, "audit_table", choices = c("All" = ""))
        return()
      }

      tables <- dbGetQuery(con, "SELECT DISTINCT \"Table\" AS table_name FROM user.USysAuditTrail ORDER BY \"Table\"")
      choices <- c("All" = "", setNames(tables$table_name, tables$table_name))
      updateSelectInput(session, "audit_table", choices = choices)
    })

    output$audit_dt <- renderDT({
      project_filter <- trimws(input$audit_project)
      plot_filter <- trimws(input$audit_plot)
      table_filter <- input$audit_table
      date_from <- input$audit_from
      date_to <- input$audit_to

      project_value <- if (nzchar(project_filter)) project_filter else NULL
      plot_value <- if (nzchar(plot_filter)) plot_filter else NULL
      table_value <- if (!is.null(table_filter) && nzchar(table_filter)) table_filter else NULL
      from_value <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
      to_value <- if (!is.null(date_to) && !is.na(date_to)) as.POSIXct(date_to) else NULL

      audit <- fetch_audit_entries(
        con,
        plot_number = plot_value,
        project_id = project_value,
        table_name = table_value,
        date_from = from_value,
        date_to = to_value
      )
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = 12, ordering = FALSE))
    })

    output$audit_export <- downloadHandler(
      filename = function() {
        paste0("audit_log_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        project_filter <- trimws(input$audit_project)
        plot_filter <- trimws(input$audit_plot)
        table_filter <- input$audit_table
        date_from <- input$audit_from
        date_to <- input$audit_to

        project_value <- if (nzchar(project_filter)) project_filter else NULL
        plot_value <- if (nzchar(plot_filter)) plot_filter else NULL
        table_value <- if (!is.null(table_filter) && nzchar(table_filter)) table_filter else NULL
        from_value <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
        to_value <- if (!is.null(date_to) && !is.na(date_to)) as.POSIXct(date_to) else NULL

        audit <- fetch_audit_entries(
          con,
          plot_number = plot_value,
          project_id = project_value,
          table_name = table_value,
          date_from = from_value,
          date_to = to_value
        )
        utils::write.csv(audit, file, row.names = FALSE)
      }
    )
    
  })
}
