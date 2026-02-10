
publish_panel_ui <- function(ns) {
  layout_sidebar(
    sidebar = sidebar(
      textInput(ns("publish_out_dir"), "RDS output dir", value = ""),
      textInput(ns("publish_version"), "Version (optional)", value = ""),
      selectInput(ns("publish_projects"), "Projects (optional)", choices = NULL, multiple = TRUE),
      checkboxInput(ns("publish_lump"), "Apply species lumping", value = TRUE),
      actionButton(ns("publish_run"), "Publish RDS Snapshot", class = "btn-primary w-100 mt-2"),
      actionButton(ns("publish_refresh"), "Refresh Snapshot List", class = "btn-outline-secondary w-100 mt-2")
    ),
    card(
      card_header("RDS Publishing"),
      card_body(
        textOutput(ns("publish_status")),
        tableOutput(ns("publish_snapshots"))
      )
    )
  )
}

download_panel_ui <- function(ns) {
  layout_sidebar(
    sidebar = sidebar(
      textInput(ns("download_user"), "User", value = ""),
      textInput(ns("download_dataset"), "Dataset", value = ""),
      selectInput(ns("download_format"), "Format", choices = c("All" = "", "rds", "csv", "excel", "xml"), selected = ""),
      selectInput(ns("download_status"), "Status", choices = c("All" = "", "success", "failed"), selected = ""),
      dateInput(ns("download_from"), "From", value = NULL),
      dateInput(ns("download_to"), "To", value = NULL),
      actionButton(ns("download_refresh"), "Refresh", class = "btn-secondary w-100 mt-2"),
      downloadButton(ns("download_export"), "Export CSV", class = "btn-outline-primary w-100 mt-2")
    ),
    card(
      card_header("Download Log"),
      card_body(
        textOutput(ns("download_status_text")),
        DTOutput(ns("download_dt"))
      )
    )
  )
}

mod_admin_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_fillable(
      card(
        full_screen = TRUE,
        navset_card_tab(
        
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
               textInput(ns("master_audit_user"), "User", value = ""),
               textInput(ns("master_audit_action"), "Action", value = ""),
               textInput(ns("master_audit_node"), "Node", value = ""),
               dateInput(ns("master_audit_from"), "From", value = NULL),
               dateInput(ns("master_audit_to"), "To", value = NULL),
               selectInput(ns("master_audit_page_size"), "Page size", choices = c(25, 50, 100), selected = 25),
               checkboxInput(ns("master_audit_latest_only"), "Latest only", value = FALSE),
               actionButton(ns("master_audit_refresh"), "Refresh", class = "btn-secondary w-100 mt-2"),
               actionButton(ns("master_audit_latest"), "Jump to newest", class = "btn-outline-secondary w-100 mt-2"),
               downloadButton(ns("master_audit_export"), "Export CSV", class = "btn-outline-primary w-100 mt-2")
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
        ),
        nav_panel("Audit Log",
           layout_sidebar(
             sidebar = sidebar(
               textInput(ns("audit_project"), "Project", value = ""),
               textInput(ns("audit_plot"), "Plot", value = ""),
               selectInput(ns("audit_table"), "Table", choices = c("All" = "")),
              dateInput(ns("audit_from"), "From", value = NULL),
              dateInput(ns("audit_to"), "To", value = NULL),
              selectInput(ns("audit_page_size"), "Page size", choices = c(25, 50, 100), selected = 25),
              checkboxInput(ns("audit_latest_only"), "Latest only", value = FALSE),
              actionButton(ns("audit_refresh"), "Refresh", class = "btn-secondary w-100 mt-2"),
              actionButton(ns("audit_latest"), "Jump to newest", class = "btn-outline-secondary w-100 mt-2"),
              downloadButton(ns("audit_export"), "Export CSV", class = "btn-outline-primary w-100 mt-2")
             ),
             card(
               card_header("Audit Trail"),
               card_body(
                 DTOutput(ns("audit_dt")),
                 div(class = "mt-2 d-flex gap-2",
                     actionButton(ns("audit_prev"), "Prev", class = "btn-outline-secondary"),
                     actionButton(ns("audit_next"), "Next", class = "btn-outline-secondary"),
                     textOutput(ns("audit_page_info"))
                 )
               )
             )
           )
        ),
        nav_panel("Sync",
          layout_sidebar(
            sidebar = sidebar(
              textInput(ns("sync_project"), "Project ID", value = ""),
              checkboxGroupInput(
                ns("sync_tables"),
                "Tables",
                choices = c(
                  "Environment" = "sample_env",
                  "Site Unit" = "sample_su",
                  "Vegetation" = "sample_veg"
                ),
                selected = c("sample_env", "sample_su", "sample_veg")
              ),
              actionButton(ns("sync_pull"), "Sync Pull", class = "btn-outline-primary w-100 mt-2"),
              actionButton(ns("sync_push"), "Sync Push", class = "btn-outline-danger w-100 mt-2"),
              actionButton(ns("sync_refresh"), "Refresh Status", class = "btn-secondary w-100 mt-2"),
              tags$hr(),
              textInput(ns("sync_snapshot_dir"), "Parquet snapshot dir", value = ""),
              actionButton(ns("sync_snapshot"), "Export Parquet Snapshot", class = "btn-outline-secondary w-100 mt-2")
            ),
            card(
              card_header("Cloud Sync"),
              card_body(
                textOutput(ns("sync_status")),
                tableOutput(ns("sync_status_table")),
                textOutput(ns("sync_snapshot_status"))
              )
            )
          )
        ),
        nav_panel("Publishing",
          uiOutput(ns("publish_panel"))
        ),
        nav_panel("Download Logs",
          uiOutput(ns("download_panel"))
        )
      )
      )
    )
  )
}

mod_admin_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
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
    # 2.1 Sync Panel
    # ==========================================================================

    sync_status_table <- reactiveVal(data.frame())
    sync_snapshot_status <- reactiveVal("")

    observeEvent(state$CurrProject, {
      if (!is.null(input$sync_project)) {
        updateTextInput(session, "sync_project", value = state$CurrProject %||% "")
      }
    }, ignoreInit = TRUE)

    refresh_sync_status <- function() {
      sync_ensure_state_tables(con)
      tables <- input$sync_tables %||% character(0)
      project_id <- trimws(input$sync_project)
      table_rows <- lapply(tables, function(table_key) {
        pull_scope <- paste("last_pull", table_key, if (nzchar(project_id)) project_id else "all", sep = ":")
        push_scope <- paste("last_push", table_key, if (nzchar(project_id)) project_id else "all", sep = ":")
        data.frame(
          table = table_key,
          last_pull = sync_get_state(con, pull_scope),
          last_push = sync_get_state(con, push_scope),
          stringsAsFactors = FALSE
        )
      })
      sync_status_table(do.call(rbind, table_rows))

      cloud_state <- if (sync_cloud_connected(con)) "connected" else "not attached"
      output$sync_status <- renderText(paste("Cloud:", cloud_state))
    }

    observeEvent(input$sync_tables, {
      refresh_sync_status()
    }, ignoreInit = FALSE)

    observeEvent(input$sync_refresh, {
      refresh_sync_status()
    })

    observeEvent(input$sync_pull, {
      tables <- input$sync_tables %||% character(0)
      project_id <- trimws(input$sync_project)
      if (!length(tables)) {
        showNotification("Select at least one table.", type = "warning")
        return()
      }

      tryCatch({
        result <- sync_pull(con, project_id = if (nzchar(project_id)) project_id else NULL, tables = tables)
        showNotification(paste("Sync pull complete.", paste(names(result), collapse = ", ")), type = "message")
      }, error = function(e) {
        showNotification(paste("Sync pull failed:", e$message), type = "error")
      })

      refresh_sync_status()
    })

    observeEvent(input$sync_push, {
      tables <- input$sync_tables %||% character(0)
      project_id <- trimws(input$sync_project)
      if (!length(tables)) {
        showNotification("Select at least one table.", type = "warning")
        return()
      }

      tryCatch({
        result <- sync_push(con, project_id = if (nzchar(project_id)) project_id else NULL, tables = tables)
        merge_id <- result$merge_request_id %||% NA
        showNotification(paste("Sync push complete. Merge request:", merge_id), type = "message")
      }, error = function(e) {
        showNotification(paste("Sync push failed:", e$message), type = "error")
      })

      refresh_sync_status()
    })

    observeEvent(input$sync_snapshot, {
      out_dir <- trimws(input$sync_snapshot_dir)
      if (!nzchar(out_dir)) {
        showNotification("Provide a snapshot directory.", type = "warning")
        return()
      }

      tryCatch({
        result <- export_parquet_snapshot(con, out_dir)
        sync_snapshot_status(paste("Snapshot files:", length(result$files), "Errors:", length(result$errors)))
        showNotification("Snapshot export complete.", type = "message")
      }, error = function(e) {
        sync_snapshot_status("")
        showNotification(paste("Snapshot export failed:", e$message), type = "error")
      })
    })

    output$sync_status_table <- renderTable({
      sync_status_table()
    }, striped = TRUE, spacing = "s")

    output$sync_snapshot_status <- renderText({
      sync_snapshot_status()
    })

    # ==========================================================================
    # 2.2 Publish Panel
    # ==========================================================================

    publish_status <- reactiveVal("")
    publish_snapshots <- reactiveVal(data.frame())

    require_admin_permission <- function(permission) {
      if (!auth_is_authenticated(state)) {
        showNotification("Sign in required.", type = "error")
        return(FALSE)
      }
      if (!auth_user_has_permission(state, permission)) {
        showNotification(paste("Permission required:", permission), type = "error")
        return(FALSE)
      }
      TRUE
    }

    output$publish_panel <- renderUI({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "publish_rds")) {
        return(card(
          card_header("RDS Publishing"),
          card_body("Sign in with publish permissions to access this panel.")
        ))
      }
      publish_panel_ui(ns)
    })

    output$download_panel <- renderUI({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "view_download_logs")) {
        return(card(
          card_header("Download Log"),
          card_body("Sign in with download log permissions to access this panel.")
        ))
      }
      download_panel_ui(ns)
    })

    observe({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "publish_rds")) return()
      if (is.null(input$publish_projects)) return()
      if (!sync_cloud_connected(con)) return()
      projects <- tryCatch({
        dbGetQuery(con, "SELECT project_id, project_name FROM master.core.sample_metadata ORDER BY project_id")
      }, error = function(e) data.frame())
      if (nrow(projects) > 0) {
        updateSelectInput(
          session,
          "publish_projects",
          choices = setNames(projects$project_id, paste(projects$project_id, "-", projects$project_name))
        )
      }
    })

    refresh_publish_snapshots <- function() {
      tryCatch({
        sync_require_cloud(con, allow_attach = TRUE)
        snaps <- dbGetQuery(
          con,
          paste(
            "SELECT version, snapshot_date, created_by, veg_row_count, env_row_count,",
            "rds_filename_veg, rds_filename_env",
            "FROM master.public_export.rds_snapshots",
            "ORDER BY created_utc DESC LIMIT 25"
          )
        )
        publish_snapshots(snaps)
        publish_status("")
      }, error = function(e) {
        publish_snapshots(data.frame())
        publish_status(paste("Snapshot list unavailable:", e$message))
      })
    }

    observeEvent(input$publish_refresh, {
      refresh_publish_snapshots()
    })

    observeEvent(input$publish_run, {
      out_dir <- trimws(input$publish_out_dir)
      if (!nzchar(out_dir)) {
        showNotification("Provide an output directory.", type = "warning")
        return()
      }

      if (!require_admin_permission("publish_rds")) return()

      version <- trimws(input$publish_version)
      if (!nzchar(version)) version <- NULL
      project_ids <- input$publish_projects %||% character(0)
      if (length(project_ids) == 0) project_ids <- NULL

      tryCatch({
        result <- publish_becmaster_rds(
          con,
          out_dir = out_dir,
          version = version,
          project_ids = project_ids,
          apply_lumping = isTRUE(input$publish_lump)
        )
        publish_status(paste("Published version", result$version, "(veg", result$veg_rows, "env", result$env_rows, ")"))
        showNotification("RDS snapshot published.", type = "message")
        refresh_publish_snapshots()
      }, error = function(e) {
        publish_status("")
        showNotification(paste("Publish failed:", e$message), type = "error")
      })
    })

    output$publish_status <- renderText({
      publish_status()
    })

    output$publish_snapshots <- renderTable({
      publish_snapshots()
    })

    # ==========================================================================
    # 2.3 Download Log Viewer
    # ==========================================================================

    download_status <- reactiveVal("")
    download_log <- reactiveVal(data.frame())

    refresh_download_log <- function() {
      if (!require_admin_permission("view_download_logs")) {
        download_log(data.frame())
        download_status("Permission required: view_download_logs")
        return()
      }
      tryCatch({
        sync_require_cloud(con, allow_attach = TRUE)
        query <- build_download_log_query(
          filters = list(
            user = trimws(input$download_user),
            dataset = trimws(input$download_dataset),
            format = input$download_format,
            status = input$download_status,
            from = if (!is.null(input$download_from)) as.POSIXct(input$download_from) else NULL,
            to = if (!is.null(input$download_to)) as.POSIXct(input$download_to) + 86400 else NULL
          ),
          limit = 1000L
        )
        rows <- dbGetQuery(con, query$sql, query$params)
        download_log(rows)
        download_status("")
      }, error = function(e) {
        download_log(data.frame())
        download_status(paste("Download log unavailable:", e$message))
      })
    }

    observeEvent(input$download_refresh, {
      refresh_download_log()
    })

    output$download_status_text <- renderText({
      download_status()
    })

    output$download_dt <- renderDT({
      datatable(download_log(), options = list(pageLength = 25, order = list(list(0, "desc"))))
    })

    output$download_export <- downloadHandler(
      filename = function() { paste0("download_log_", Sys.Date(), ".csv") },
      content = function(file) {
        if (!require_admin_permission("view_download_logs")) {
          stop("Permission required: view_download_logs")
        }
        write.csv(download_log(), file, row.names = FALSE)
      }
    )

    # ==========================================================================
    # 3. Master Site Units
    # ==========================================================================

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
          return(list(
            id = candidate,
            name = candidate
          ))
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
        rv_master$data <- data.frame()
        rv_master$columns <- NULL
        output$master_header <- renderText("Master list not found.")
        return()
      }

      fields <- dbListFields(con, table_info$id)
      select_cols <- intersect(
        c("ID", "SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"),
        fields
      )
      if (length(select_cols) == 0 || !("SiteSeries" %in% select_cols)) {
        rv_master$data <- data.frame()
        rv_master$columns <- NULL
        output$master_header <- renderText("Master list missing required columns.")
        return()
      }

      where_clause <- ""
      params <- list()
      if (!is.null(level) && nzchar(level) && ("Level" %in% select_cols)) {
        where_clause <- "WHERE Level = ?"
        params <- list(as.integer(level))
      }

      sql <- sprintf("SELECT %s FROM %s %s ORDER BY SiteSeries", paste(select_cols, collapse = ", "), table_info$name, where_clause)
      rv_master$data <- dbGetQuery(con, sql, params)
      rv_master$columns <- select_cols
      output$master_header <- renderText(paste("Master list:", table_info$name))
    }

    observeEvent(input$master_refresh, {
      level_val <- trimws(input$master_level)
      load_master_table(level = level_val)
    })

    observeEvent(input$master_level, {
      level_val <- trimws(input$master_level)
      load_master_table(level = level_val)
    }, ignoreInit = TRUE)

    observeEvent(state$CurrProject, {
      update_master_levels()
      load_master_table(level = trimws(input$master_level))
    }, ignoreInit = TRUE)

    output$master_dt <- renderDT({
      req(rv_master$data)
      id_col <- which(names(rv_master$data) == "ID")
      disable_cols <- if (length(id_col) > 0) list(columns = id_col - 1L) else list()
      datatable(
        rv_master$data,
        editable = list(target = "cell", disable = disable_cols),
        selection = "none",
        options = list(pageLength = 15, dom = "t,p")
      )
    })

    observeEvent(input$master_dt_cell_edit, {
      info <- input$master_dt_cell_edit
      i <- info$row
      j <- info$col + 1
      v <- info$value
      rv_master$data[i, j] <- coerceValue(v, rv_master$data[i, j])
    })

    observeEvent(input$master_add_row, {
      req(rv_master$columns)
      new_row <- as.list(rep(NA, length(rv_master$columns)))
      names(new_row) <- rv_master$columns
      if ("SiteSeries" %in% rv_master$columns) new_row$SiteSeries <- "NEW_UNIT"
      if ("SiteSeriesLongName" %in% rv_master$columns) new_row$SiteSeriesLongName <- "New Site Unit"
      if ("SiteSeriesScientificName" %in% rv_master$columns) new_row$SiteSeriesScientificName <- ""
      if ("Level" %in% rv_master$columns) new_row$Level <- 11
      if ("ID" %in% rv_master$columns) new_row$ID <- NA_integer_
      rv_master$data <- rbind(rv_master$data, as.data.frame(new_row, stringsAsFactors = FALSE))
    })

    observeEvent(input$master_save, {
      req(rv_master$table_name)
      req(rv_master$data)

      table_name <- rv_master$table_name
      old_rows <- dbGetQuery(con, sprintf("SELECT %s FROM %s", paste(rv_master$columns, collapse = ", "), table_name))
      to_save <- rv_master$data

      if ("Level" %in% names(to_save)) {
        to_save$Level[is.na(to_save$Level)] <- 11
      }

      if ("ID" %in% names(to_save)) {
        ids <- suppressWarnings(as.integer(to_save$ID))
        max_id <- if (any(!is.na(ids))) max(ids, na.rm = TRUE) else 0L
        missing <- which(is.na(ids) | ids <= 0 | duplicated(ids))
        for (idx in missing) {
          max_id <- max_id + 1L
          ids[idx] <- max_id
        }
        to_save$ID <- ids
      }

      dbBegin(con)
      tryCatch({
        dbExecute(con, sprintf("DELETE FROM %s", table_name))

        cols <- names(to_save)
        placeholders <- paste(rep("?", length(cols)), collapse = ", ")
        sql <- sprintf("INSERT INTO %s (%s) VALUES (%s)", table_name, paste(cols, collapse = ", "), placeholders)

        for (i in seq_len(nrow(to_save))) {
          dbExecute(con, sql, as.list(to_save[i, cols, drop = FALSE]))
        }

        dbCommit(con)
        showNotification("Master list saved.", type = "message")

        if (nrow(to_save) > 0 || nrow(old_rows) > 0) {
          key_col <- if ("ID" %in% cols) "ID" else "SiteSeries"
          old_map <- if (nrow(old_rows) > 0) split(old_rows, old_rows[[key_col]]) else list()
          new_map <- if (nrow(to_save) > 0) split(to_save, to_save[[key_col]]) else list()

          removed_keys <- setdiff(names(old_map), names(new_map))
          added_keys <- setdiff(names(new_map), names(old_map))
          common_keys <- intersect(names(old_map), names(new_map))

          audit_fields <- intersect(c("SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"), cols)

          for (key in removed_keys) {
            row <- old_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) row$ID[1] else 0L
            for (field in audit_fields) {
              log_master_audit(con, "Admin", "Delete", row$SiteSeries[1], node_id, field, row[[field]][1], NA)
            }
          }

          for (key in added_keys) {
            row <- new_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) row$ID[1] else 0L
            for (field in audit_fields) {
              log_master_audit(con, "Admin", "Add", row$SiteSeries[1], node_id, field, NA, row[[field]][1])
            }
          }

          for (key in common_keys) {
            old_row <- old_map[[key]][1, , drop = FALSE]
            new_row <- new_map[[key]][1, , drop = FALSE]
            node_id <- if ("ID" %in% cols) new_row$ID[1] else 0L
            for (field in audit_fields) {
              log_master_audit(con, "Admin", "Edit", new_row$SiteSeries[1], node_id, field, old_row[[field]][1], new_row[[field]][1])
            }
          }
        }

        update_master_levels()
        load_master_table(level = trimws(input$master_level))
      }, error = function(e) {
        dbRollback(con)
        showNotification(paste("Save failed:", e$message), type = "error")
      })
    })

    rv_master_audit <- reactiveValues(page = 1L)

    observeEvent(input$master_audit_refresh, {
      rv_master_audit$page <- 1L
    })

    observeEvent(input$master_audit_next, {
      if (isTRUE(input$master_audit_latest_only)) return()
      rv_master_audit$page <- rv_master_audit$page + 1L
    })

    observeEvent(input$master_audit_prev, {
      if (isTRUE(input$master_audit_latest_only)) return()
      rv_master_audit$page <- max(1L, rv_master_audit$page - 1L)
    })

    observeEvent(input$master_audit_page_size, {
      rv_master_audit$page <- 1L
    })

    observeEvent(input$master_audit_latest, {
      updateCheckboxInput(session, "master_audit_latest_only", value = TRUE)
      rv_master_audit$page <- 1L
    })

    output$master_audit_dt <- renderDT({
      user_filter <- trimws(input$master_audit_user)
      action_filter <- trimws(input$master_audit_action)
      node_filter <- trimws(input$master_audit_node)
      date_from <- input$master_audit_from
      date_to <- input$master_audit_to

      user_value <- if (nzchar(user_filter)) user_filter else NULL
      action_value <- if (nzchar(action_filter)) action_filter else NULL
      node_value <- if (nzchar(node_filter)) node_filter else NULL
      from_value <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
      to_value <- if (!is.null(date_to) && !is.na(date_to)) as.POSIXct(date_to) else NULL

      page_size <- as.integer(input$master_audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      latest_only <- isTRUE(input$master_audit_latest_only)
      offset <- if (latest_only) 0L else (rv_master_audit$page - 1L) * page_size

      audit <- fetch_master_audit_entries(
        con,
        user = user_value,
        action = action_value,
        node_name = node_value,
        date_from = from_value,
        date_to = to_value,
        limit = page_size,
        offset = offset
      )
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = page_size, ordering = FALSE))
    })

    output$master_audit_page_info <- renderText({
      page_size <- as.integer(input$master_audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      if (isTRUE(input$master_audit_latest_only)) {
        return(paste0("Latest ", page_size, " rows"))
      }
      start_row <- (rv_master_audit$page - 1L) * page_size + 1L
      end_row <- rv_master_audit$page * page_size
      paste0("Rows ", start_row, "-", end_row)
    })

    output$master_audit_export <- downloadHandler(
      filename = function() {
        paste0("master_audit_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        user_filter <- trimws(input$master_audit_user)
        action_filter <- trimws(input$master_audit_action)
        node_filter <- trimws(input$master_audit_node)
        date_from <- input$master_audit_from
        date_to <- input$master_audit_to

        user_value <- if (nzchar(user_filter)) user_filter else NULL
        action_value <- if (nzchar(action_filter)) action_filter else NULL
        node_value <- if (nzchar(node_filter)) node_filter else NULL
        from_value <- if (!is.null(date_from) && !is.na(date_from)) as.POSIXct(date_from) else NULL
        to_value <- if (!is.null(date_to) && !is.na(date_to)) as.POSIXct(date_to) else NULL

        audit <- fetch_master_audit_entries(
          con,
          user = user_value,
          action = action_value,
          node_name = node_value,
          date_from = from_value,
          date_to = to_value
        )
        utils::write.csv(audit, file, row.names = FALSE)
      }
    )

    # ==========================================================================
    # 4. Audit Log
    # ==========================================================================

    observe({
      if (!audit_table_exists(con)) {
        updateSelectInput(session, "audit_table", choices = c("All" = ""))
        return()
      }

      table_col <- audit_table_name_col(con)
      if (is.null(table_col)) {
        updateSelectInput(session, "audit_table", choices = c("All" = ""))
        return()
      }
      table_col_sql <- quote_ident(table_col)
      sql <- sprintf(
        "SELECT DISTINCT %s AS table_name FROM user.USysAuditTrail ORDER BY %s",
        table_col_sql,
        table_col_sql
      )
      tables <- dbGetQuery(con, sql)
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

      page_size <- as.integer(input$audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      latest_only <- isTRUE(input$audit_latest_only)
      offset <- if (latest_only) 0L else (rv_audit$page - 1L) * page_size

      audit <- fetch_audit_entries(
        con,
        plot_number = plot_value,
        project_id = project_value,
        table_name = table_value,
        date_from = from_value,
        date_to = to_value,
        limit = page_size,
        offset = offset
      )
      DT::datatable(audit, rownames = FALSE, options = list(pageLength = page_size, ordering = FALSE))
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

    rv_audit <- reactiveValues(page = 1L)

    observeEvent(input$audit_refresh, {
      rv_audit$page <- 1L
    })

    observeEvent(input$audit_next, {
      if (isTRUE(input$audit_latest_only)) return()
      rv_audit$page <- rv_audit$page + 1L
    })

    observeEvent(input$audit_prev, {
      if (isTRUE(input$audit_latest_only)) return()
      rv_audit$page <- max(1L, rv_audit$page - 1L)
    })

    observeEvent(input$audit_page_size, {
      rv_audit$page <- 1L
    })

    observeEvent(input$audit_latest, {
      updateCheckboxInput(session, "audit_latest_only", value = TRUE)
      rv_audit$page <- 1L
    })

    output$audit_page_info <- renderText({
      page_size <- as.integer(input$audit_page_size)
      if (is.na(page_size) || page_size <= 0) page_size <- 25
      if (isTRUE(input$audit_latest_only)) {
        return(paste0("Latest ", page_size, " rows"))
      }
      start_row <- (rv_audit$page - 1L) * page_size + 1L
      end_row <- rv_audit$page * page_size
      paste0("Rows ", start_row, "-", end_row)
    })

    observeEvent(state$CurrProject, {
      if (is.null(state$CurrProject)) return()
      if (!nzchar(trimws(input$audit_project))) {
        updateTextInput(session, "audit_project", value = state$CurrProject)
      }
    })

    observeEvent(state$CurrSU, {
      if (is.null(state$CurrSU)) return()
      if (!nzchar(trimws(input$audit_plot))) {
        updateTextInput(session, "audit_plot", value = state$CurrSU)
      }
    })
    
  })
}
