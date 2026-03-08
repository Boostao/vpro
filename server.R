# Server Logic Code
# Manages Global State and Module Initializations

init_bcgov_static_resources <- function() {
  static_dir <- file.path(tempdir(), "vpro-bcgov-static")
  fonts_dir <- file.path(static_dir, "fonts")
  dir.create(fonts_dir, recursive = TRUE, showWarnings = FALSE)

  font_css_src <- file.path(getwd(), "lib", "bsw5", "dist", "bcgov", "font.css")
  font_css_dst <- file.path(static_dir, "font.css")
  if (file.exists(font_css_src)) {
    file.copy(font_css_src, font_css_dst, overwrite = TRUE)
  }

  font_files_src <- list.files(
    file.path(getwd(), "fonts"),
    pattern = "\\.woff2?$",
    full.names = TRUE
  )
  if (length(font_files_src) > 0) {
    file.copy(font_files_src, fonts_dir, overwrite = TRUE)
  }

  tryCatch(
    shiny::addResourcePath("bcgov-static", static_dir),
    error = function(e) {
      message("BC Gov static resources not registered: ", conditionMessage(e))
    }
  )
}

init_bcgov_static_resources()

server <- function(input, output, session) {
  
  # 1. Database Connection
  # Using a persistent connection for simplicity (DuckDB single user mode)
  con <- connect_local_db()

  # Cloud PostgreSQL is NOT attached on startup.
  # It is attached by mod_auth_server when the user logs in,
  # and detached on logout. All local features work without it.

  # Ensure clean disconnect when session ends
  onSessionEnded(function() {
    if (is_cloud_connected(con)) detach_db(con, "master")
    dbDisconnect(con, shutdown = TRUE)
  })
  
  # 2. Global State
  state <- init_sys_state()

  # Startup messaging (What's New)
  mod_whatsnew_server("whatsnew", con, open_trigger = reactive(input$btn_whatsnew))

  # Preferences (SaveSetting/GetSetting analog)
  seed_default_preferences(con)
  pref_project <- get_pref(con, "Current", "CurrProject", default = NULL)
  pref_su_table <- get_pref(con, "Current", "CurrPlotList", default = "None")
  pref_plot <- get_pref(con, "Current", "CurrPlotNumber", default = NULL)
  pref_hierarchy <- get_pref(con, "Current", "CurrHierarchy", default = NULL)
  pref_form <- get_pref(con, "Current", "DataFormName", default = NULL)
  pref_user <- get_pref(con, "User", "UserName", default = Sys.getenv("USER", "Unknown"))

  # Dev mode overrides (temporary)
  if (isTRUE(exists("VPRO_DEV_MODE") && VPRO_DEV_MODE)) {
    if (exists("VPRO_DEV_DEFAULT_PROJECT")) {
      pref_project <- VPRO_DEV_DEFAULT_PROJECT
    }
    if (exists("VPRO_DEV_DEFAULT_PLOTNUMBER")) {
      pref_plot <- VPRO_DEV_DEFAULT_PLOTNUMBER
      pref_su_table <- VPRO_DEV_DEFAULT_PLOTNUMBER
    }
  }

  state$PrefProject <- pref_project
  state$PrefSUTable <- pref_su_table
  state$PrefPlot <- pref_plot
  state$PrefHierarchy <- pref_hierarchy
  state$CurrHierarchy <- pref_hierarchy
  state$sysCurrHierarchy <- pref_hierarchy
  state$CurrForm <- pref_form
  state$sysCurrForm <- pref_form
  state$User <- pref_user

  # Initialize CurrSU from preferred plot
  if (!is.null(pref_plot) && nzchar(pref_plot)) {
    state$CurrSU <- pref_plot
    state$sysCurrSU <- pref_plot
  }

  # 3. Project module (replaces old sel_project sentinel dropdown)
  project_mod <- mod_project_server("project", state, con)

  # Refresh SU + hierarchy when project changes
  observe({
    project_mod$project_changed()
    refresh_su_dropdown()
    refresh_hierarchy_dropdown()
  })

  # Returns plot numbers for the currently active project
  refresh_su_dropdown <- function(selected_su = NULL) {
    pid <- isolate(state$CurrProject)
    su_choices <- if (!is.null(pid) && nzchar(pid %||% "") && 
                      DBI::dbExistsTable(con, "Env")) {
      tryCatch(
        as.character(DBI::dbGetQuery(
          con,
          "SELECT DISTINCT plotnumber FROM Env
           WHERE projectid = ?
           ORDER BY plotnumber",
          list(pid)
        )$plotnumber),
        error = function(e) character(0)
      )
    } else character(0)

    choices <- c("(None)" = "", su_choices)
    if (is.null(selected_su)) selected_su <- state$CurrSU %||% ""
    if (!is.null(selected_su) && !(selected_su %in% su_choices)) selected_su <- ""
    updateSelectInput(session, "sel_su", choices = choices, selected = selected_su)
    invisible(su_choices)
  }

  # Returns site units for the currently active project
  refresh_hierarchy_dropdown <- function(selected_hierarchy = NULL) {
    pid <- isolate(state$CurrProject)
    hier_choices <- if (!is.null(pid) && nzchar(pid %||% "") && DBI::dbExistsTable(con, "Hierarchy")) {
      tryCatch(
        as.character(DBI::dbGetQuery(
          con,
          "SELECT DISTINCT siteunit FROM Hierarchy WHERE projectid = ? ORDER BY siteunit",
          list(pid)
        )$siteunit),
        error = function(e) character(0)
      )
    } else character(0)

    choices <- c("(None)" = "", hier_choices)
    if (is.null(selected_hierarchy)) selected_hierarchy <- state$CurrHierarchy %||% ""
    if (!is.null(selected_hierarchy) && !(selected_hierarchy %in% hier_choices)) selected_hierarchy <- ""
    updateSelectInput(session, "sel_hierarchy", choices = choices, selected = selected_hierarchy)
    invisible(hier_choices)
  }

  observe({ refresh_su_dropdown() })

  # 5. Handle SU (site plot) selection
  observeEvent(input$sel_su, {
    su <- input$sel_su %||% ""
    if (!nzchar(su)) {
      set_su(state, NULL)
      state$PrefPlot <- NULL
      set_pref(con, "Current", "CurrPlotNumber", "")
    } else {
      set_su(state, su)
      state$PrefSUTable <- su
      set_pref(con, "Current", "CurrPlotList", su)
      set_pref(con, "Current", "CurrPlotNumber", su)
    }
  })

  observe({
    refresh_hierarchy_dropdown()
  })

  # 5b. Handle Hierarchy selection
  observeEvent(input$sel_hierarchy, {
    hier <- input$sel_hierarchy %||% ""
    if (!nzchar(hier)) {
      state$CurrHierarchy <- NULL
      state$sysCurrHierarchy <- NULL
      state$PrefHierarchy <- NULL
      set_pref(con, "Current", "CurrHierarchy", "")
    } else {
      state$CurrHierarchy <- hier
      state$sysCurrHierarchy <- hier
      state$PrefHierarchy <- hier
      set_pref(con, "Current", "CurrHierarchy", hier)
    }
  })

  observeEvent(input$btn_nav_data_entry, {
    state$DataEntryReturnTab <- input$main_tabs %||% "Vegetation"
    open_fs882_destination_context(
      state = state,
      con = con,
      form_name = "FS882-6x4XL",
      close_forms = c("FS882-8x6XL", "FS882-1x1")
    )
    bslib::nav_select("main_tabs", "FS882-6x4XL", session = session)
  })

  observeEvent(input$main_tabs, {
    if (!identical(input$main_tabs, "FS882-6x4XL")) {
      return()
    }
    if (is.null(state$DataEntryReturnTab) || !nzchar(state$DataEntryReturnTab)) {
      state$DataEntryReturnTab <- "Vegetation"
    }
    open_fs882_destination_context(
      state = state,
      con = con,
      form_name = "FS882-6x4XL",
      close_forms = c("FS882-8x6XL", "FS882-1x1")
    )
  }, ignoreInit = TRUE)

  observeEvent(input$btn_nav_two_page, {
    bslib::nav_select("main_tabs", "FS882-6x4XL", session = session)
  })

  observeEvent(input$btn_nav_single_page, {
    bslib::nav_select("main_tabs", "FS882-6x4XL", session = session)
  })

  observeEvent(input$btn_nav_sivi, {
    bslib::nav_select("main_tabs", "FS882-6x4XL", session = session)
  })

  observeEvent(input$btn_nav_su_tree, {
    bslib::nav_select("main_tabs", "Hierarchy", session = session)
  })

  observeEvent(input$btn_nav_su_table, {
    bslib::nav_select("main_tabs", "Hierarchy", session = session)
  })

  observeEvent(input$btn_nav_hierarchy_tree, {
    bslib::nav_select("main_tabs", "Hierarchy", session = session)
  })

  # 6.1 Keyboard Shortcuts
  observeEvent(input$global_save, {
    req(input$main_tabs)

    if (input$main_tabs == "FS882-6x4XL") {
      shinyjs::click("fs882_6x4xl-btnSaveRecord")
      shinyjs::click("fs882_6x4xl-btnSaveVeg")
      showNotification("Saved FS882 header and vegetation.", type = "message")
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

    if (input$main_tabs == "FS882-6x4XL") {
      shinyjs::click("fs882_6x4xl-btnAddVegRow")
      return()
    }

    showNotification("No default New action for this tab.", type = "message")
  })

  observeEvent(input$btn_toggle_context, {
    bslib::toggle_sidebar("context_sidebar")
  })
  
  # 7. Initialize Sub-Modules
  mod_admin_server("admin", state, con)
  
  # For Veg, we pass the state directly as it needs plot context
  # Also passing con to avoid multiple connections
  mod_veg_sample_server("veg", state, con)
  
  # FS882-6x4XL destination module (wrapper over existing site/env implementation)
  mod_fs882_6x4xl_server("fs882_6x4xl", state, con)
  
  # Export Module
  mod_export_server("export", state, con)

  # Import Module
  mod_import_server("import", state, con)

  # Upload Module
  #mod_upload_server("upload", state, con)

  # Sync Module
  mod_sync_server("sync", state, con)

  # Invalidate sync incoming count whenever the Sync tab is activated
  observeEvent(input$main_tabs, {
    if (identical(input$main_tabs, "Sync")) {
      state$SyncTabActivated <- (state$SyncTabActivated %||% 0L) + 1L
    }
  }, ignoreInit = TRUE)

  # Merge Module (standalone tab unwired; Merge Review lives in Admin > Merge Review)
  # mod_merge_server("merge", state, con)

  # Auth Module
  mod_auth_server("auth", state, con)

  # Auth Status Widget
  auth_status_nav_signal <- mod_auth_status_server("auth_status", state, con)
  observe({
    dest <- auth_status_nav_signal()
    if (!is.null(dest)) {
      nav_select("main_tabs", selected = dest)
    }
  })
  
  # Images & Maps Module
  mod_images_server("imgs", state, con)
  
  # Reporting Module
  mod_reporting_server("report", state, con)

  # Hierarchy Module
  mod_hierarchy_server("hier", state, con)
  
  # BEC Web Map Module (public-facing, no auth requirement)
  mod_becweb_map_server("becmap", con = con, auth_level = "public")
}
