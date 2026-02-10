# Server Logic Code
# Manages Global State and Module Initializations

server <- function(input, output, session) {
  
  # 1. Database Connection
  # Using a persistent connection for simplicity (DuckDB single user mode)
  con <- dbConnect(duckdb(), "data/vpro.duckdb")
  
  # Attach Reference Database
  # This makes USysTableOfLists available as 'lists.USysTableOfLists' or just 'USysTableOfLists' if unambiguous
  dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
  dbExecute(con, "ATTACH 'data/vpro_user.duckdb' AS user_db")
  
  # Ensure clean disconnect when session ends
  onSessionEnded(function() {
    dbDisconnect(con, shutdown = TRUE)
  })
  
  # 2. Global State
  state <- init_sys_state()

  # Preferences (SaveSetting/GetSetting analog)
  seed_default_preferences(con)
  pref_project <- get_pref(con, "Current", "CurrProject", default = NULL)
  pref_plot <- get_pref(con, "Current", "CurrPlotList", default = NULL)
  pref_hierarchy <- get_pref(con, "Current", "CurrHierarchy", default = NULL)
  pref_form <- get_pref(con, "Current", "DataFormName", default = NULL)
  pref_user <- get_pref(con, "User", "UserName", default = Sys.getenv("USER", "Unknown"))

  state$PrefProject <- pref_project
  state$PrefPlot <- pref_plot
  state$PrefHierarchy <- pref_hierarchy
  state$CurrHierarchy <- pref_hierarchy
  state$sysCurrHierarchy <- pref_hierarchy
  state$CurrForm <- pref_form
  state$sysCurrForm <- pref_form
  state$User <- pref_user
  
  # 3. Populate Project Dropdown
  observe({
    # We use TryCatch in case DB is locked or empty
    tryCatch({
      projects <- dbGetQuery(con, "SELECT projectid, projecttitle FROM Sample_Metadata ORDER BY projectid")
      if (nrow(projects) > 0) {
        choices <- setNames(projects$projectid, paste(projects$projectid, "-", projects$projecttitle))
        selected <- state$PrefProject
        if (is.null(selected) || !(selected %in% projects$projectid)) {
          selected <- projects$projectid[[1]]
        }
        updateSelectInput(session, "sel_project", choices = choices, selected = selected)
      }
    }, error = function(e) {
      log_msg("Error loading projects: ", conditionMessage(e))
    })
  })
  
  # 4. Handle Project Change
  observeEvent(input$sel_project, {
    req(input$sel_project)
    
    # Update State Logic
    set_project(state, input$sel_project, con)
    set_pref(con, "Current", "CurrProject", input$sel_project)
    
    # Update Dependent Dropdown (Cascade)
    # Filter Sample_Env by this ProjectID to get valid plots
    plots <- dbGetQuery(con, sprintf("
      SELECT DISTINCT PlotNumber 
      FROM Sample_Env 
      WHERE ProjectID = '%s' 
      ORDER BY PlotNumber", input$sel_project))
      
    selected_plot <- state$PrefPlot
    if (!is.null(selected_plot) && !(selected_plot %in% plots$plotnumber)) {
      selected_plot <- NULL
    }
    if (is.null(selected_plot) && nrow(plots) > 0) {
      selected_plot <- plots$plotnumber[[1]]
    }
    updateSelectInput(session, "sel_su", choices = plots$plotnumber, selected = selected_plot)
  })
  
  # 5. Handle SU Change
  observeEvent(input$sel_su, {
    req(input$sel_su)
    set_su(state, input$sel_su)
    set_pref(con, "Current", "CurrPlotList", input$sel_su)
  })
  
  # 6. Context Summary
  output$ctx_summary <- renderText({
    req(state$CurrProject)
    p_title <- state$ProjectMetadata$projecttitle
    if (is.null(p_title)) p_title <- ""
    
    paste0(
      "Project: ", state$CurrProject, "\n", 
      "Title:   ", substr(p_title, 1, 20), "...\n",
      "Plot:    ", state$CurrSU
    )
  })

  # 6.1 Keyboard Shortcuts
  observeEvent(input$global_save, {
    req(input$main_tabs)

    if (input$main_tabs == "Site & Env") {
      shinyjs::click("env-save_header")
      shinyjs::click("env-save_mensuration")
      showNotification("Saved site/env fields.", type = "message")
      return()
    }

    if (input$main_tabs == "Vegetation") {
      showNotification("Vegetation edits save automatically.", type = "message")
      return()
    }
  })

  observeEvent(input$global_new, {
    req(input$main_tabs)

    if (input$main_tabs == "Vegetation") {
      shinyjs::click("veg-btn_add_spp")
      return()
    }

    showNotification("No default New action for this tab.", type = "message")
  })
  
  # 7. Initialize Sub-Modules
  mod_admin_server("admin", state, con)
  
  # For Veg, we pass the state directly as it needs plot context
  # Also passing con to avoid multiple connections
  mod_veg_sample_server("veg", state, con)
  
  # Site & Env Module
  # Refactored to accept shared connection 'con' to avoid DB locking issues
  mod_site_env_server("env", state, con)
  
  # Export Module
  mod_export_server("export", state, con)

  # Import Module
  mod_import_server("import", state, con)

  # Upload Module
  mod_upload_server("upload", state, con)

  # Merge Module
  mod_merge_server("merge", state, con)

  # Auth Module
  mod_auth_server("auth", state, con)
  
  # Images & Maps Module
  mod_images_server("imgs", state, con)
  
  # Reporting Module
  mod_reporting_server("report", state, con)

  # Hierarchy Module
  mod_hierarchy_server("hier", state, con)
}
