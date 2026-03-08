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

  state$PrefProject <- pref_project
  state$PrefSUTable <- pref_su_table
  state$PrefPlot <- pref_plot
  state$PrefHierarchy <- pref_hierarchy
  state$CurrHierarchy <- pref_hierarchy
  state$sysCurrHierarchy <- pref_hierarchy
  state$CurrForm <- pref_form
  state$sysCurrForm <- pref_form
  state$User <- pref_user

  SU_ACTION_ATTACH <- "__su_action_attach__"
  SU_ACTION_NEW <- "__su_action_new__"
  SU_ACTION_UNATTACH <- "__su_action_unattach__"
  SU_ACTION_NONE <- "__su_action_none__"
  SU_ACTION_SEPARATOR <- "__su_action_separator__"
  HIER_ACTION_ATTACH <- "__hier_action_attach__"
  HIER_ACTION_NEW <- "__hier_action_new__"
  HIER_ACTION_UNATTACH <- "__hier_action_unattach__"
  HIER_ACTION_SEPARATOR <- "__hier_action_separator__"

  # 3. Project module (replaces old sel_project sentinel dropdown)
  project_mod <- mod_project_server("project", state, con)

  # Refresh SU + hierarchy when project changes
  observe({
    project_mod$project_changed()
    refresh_su_dropdown()
    refresh_hierarchy_dropdown()
  })

  build_selector_choices <- function(dynamic_values, action_values, include_none = FALSE) {
    action_labels <- function(include_none = FALSE) {
      base <- c("Attach", "New", "Unattach")
      if (isTRUE(include_none)) base <- c(base, "None")
      c(base, "--------------------------------------")
    }
    if (length(dynamic_values) == 0 && !isTRUE(include_none)) {
      lbl <- action_labels(include_none = FALSE)[1:3]
      return(stats::setNames(action_values[lbl], lbl))
    }
    lbl <- c(action_labels(include_none = include_none), dynamic_values)
    val <- c(unname(action_values[action_labels(include_none = include_none)]), dynamic_values)
    stats::setNames(val, lbl)
  }

  resolve_dynamic_selection <- function(selected, preferred, dynamic_values, none_value = NULL) {
    if (is.null(selected) || !nzchar(selected) || !(selected %in% dynamic_values)) selected <- preferred
    if (is.null(selected) || !nzchar(selected %||% "") || !(selected %in% dynamic_values)) {
      if (length(dynamic_values) > 0) selected <- dynamic_values[[1]]
      else if (!is.null(none_value)) selected <- none_value
    }
    selected
  }

  refresh_su_dropdown <- function(selected_su = NULL) {
    su_actions <- c(
      "Attach" = SU_ACTION_ATTACH, "New" = SU_ACTION_NEW,
      "Unattach" = SU_ACTION_UNATTACH, "None" = SU_ACTION_NONE,
      "--------------------------------------" = SU_ACTION_SEPARATOR
    )
    su_choices <- if (DBI::dbExistsTable(con, "SU")) {
      tryCatch(as.character(DBI::dbGetQuery(con, "SELECT DISTINCT plotnumber FROM SU ORDER BY plotnumber")$plotnumber), error = function(e) character(0))
    } else character(0)
    values <- build_selector_choices(su_choices, su_actions, include_none = TRUE)
    selected_su <- resolve_dynamic_selection(selected_su, state$PrefSUTable, su_choices, SU_ACTION_NONE)
    updateSelectInput(session, "sel_su", choices = values, selected = selected_su)
    invisible(su_choices)
  }

  refresh_plot_dropdown <- function(selected_plot = NULL) refresh_su_dropdown(selected_su = selected_plot)

  refresh_hierarchy_dropdown <- function(selected_hierarchy = NULL) {
    hier_actions <- c(
      "Attach" = HIER_ACTION_ATTACH, "New" = HIER_ACTION_NEW,
      "Unattach" = HIER_ACTION_UNATTACH,
      "--------------------------------------" = HIER_ACTION_SEPARATOR
    )
    hier_choices <- if (DBI::dbExistsTable(con, "Hierarchy")) {
      tryCatch(as.character(DBI::dbGetQuery(con, "SELECT DISTINCT siteunit FROM Hierarchy ORDER BY siteunit")$siteunit), error = function(e) character(0))
    } else character(0)
    values <- build_selector_choices(hier_choices, hier_actions, include_none = FALSE)
    selected_hierarchy <- resolve_dynamic_selection(selected_hierarchy, state$PrefHierarchy, hier_choices, NULL)
    updateSelectInput(session, "sel_hierarchy", choices = values, selected = selected_hierarchy)
    invisible(hier_choices)
  }

  observe({ refresh_su_dropdown() })
  
  # 5. Handle SU Change
  observeEvent(input$sel_su, {
    req(input$sel_su)

    if (identical(input$sel_su, SU_ACTION_SEPARATOR)) {
      refresh_su_dropdown(selected_su = state$PrefSUTable)
      return()
    }

    if (identical(input$sel_su, SU_ACTION_NONE)) {
      state$PrefSUTable <- "None"
      set_pref(con, "Current", "CurrPlotList", "None")
      set_su(state, NULL)
      state$PrefPlot <- NULL
      set_pref(con, "Current", "CurrPlotNumber", "")
      showNotification("Current site unit table cleared.", type = "message")
      return()
    }

    if (identical(input$sel_su, SU_ACTION_ATTACH)) {
      showModal(modalDialog(
        title = "Attach Site Unit Table",
        textInput("su_attach_db_path", "DuckDB file path", value = ""),
        textInput("su_attach_prefix", "Prefix for <prefix>_SU", value = state$CurrProject %||% ""),
        checkboxInput("su_attach_replace", "Replace existing table if present", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("su_attach_confirm", "Attach", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      refresh_su_dropdown(selected_su = state$PrefSUTable)
      return()
    }

    if (identical(input$sel_su, SU_ACTION_NEW)) {
      showModal(modalDialog(
        title = "New Site Unit Table",
        textInput("su_new_prefix", "New prefix", value = state$CurrProject %||% ""),
        textInput("su_new_template", "Template prefix", value = "Sample"),
        checkboxInput("su_new_overwrite", "Overwrite if table exists", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("su_new_confirm", "Create", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      refresh_su_dropdown(selected_su = state$PrefSUTable)
      return()
    }

    if (identical(input$sel_su, SU_ACTION_UNATTACH)) {
      su_prefixes <- discover_prefixes_by_suffix(con, "_SU")
      su_choices <- su_prefixes[!tolower(su_prefixes) %in% c("sample")]
      showModal(modalDialog(
        title = "Unattach Site Unit Table",
        if (length(su_choices) == 0) {
          tags$p("No detachable site unit tables found.")
        } else {
          selectInput("su_unattach_prefix", "Prefix", choices = su_choices)
        },
        footer = tagList(
          modalButton("Cancel"),
          actionButton("su_unattach_confirm", "Unattach", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
      refresh_su_dropdown(selected_su = state$PrefSUTable)
      return()
    }

    state$PrefSUTable <- input$sel_su
    set_pref(con, "Current", "CurrPlotList", input$sel_su)
  })

  observeEvent(input$su_new_confirm, {
    req(input$su_new_prefix)
    tryCatch({
      create_prefixed_table_from_template(
        con,
        prefix = trimws(input$su_new_prefix),
        suffix = "_SU",
        template_prefix = trimws(input$su_new_template),
        overwrite = isTRUE(input$su_new_overwrite)
      )
      removeModal()
      refresh_su_dropdown(selected_su = trimws(input$su_new_prefix))
      updateSelectInput(session, "sel_su", selected = trimws(input$su_new_prefix))
      showNotification(paste0("Created site unit table: ", trimws(input$su_new_prefix), "_SU"), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$su_attach_confirm, {
    req(input$su_attach_db_path, input$su_attach_prefix)
    tryCatch({
      attach_prefixed_table(
        con,
        db_path = trimws(input$su_attach_db_path),
        prefix = trimws(input$su_attach_prefix),
        suffix = "_SU",
        replace_existing = isTRUE(input$su_attach_replace)
      )
      removeModal()
      refresh_su_dropdown(selected_su = trimws(input$su_attach_prefix))
      updateSelectInput(session, "sel_su", selected = trimws(input$su_attach_prefix))
      showNotification(paste0("Attached site unit table: ", trimws(input$su_attach_prefix), "_SU"), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$su_unattach_confirm, {
    req(input$su_unattach_prefix)
    tryCatch({
      removed <- unattach_prefixed_table(con, input$su_unattach_prefix, suffix = "_SU")
      removeModal()
      if (identical(tolower(state$PrefSUTable %||% ""), tolower(input$su_unattach_prefix))) {
        state$PrefSUTable <- "None"
        set_pref(con, "Current", "CurrPlotList", "None")
      }
      refresh_su_dropdown(selected_su = state$PrefSUTable)
      if (!is.null(removed)) {
        showNotification(paste0("Unattached site unit table: ", removed), type = "message")
      }
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observe({
    refresh_hierarchy_dropdown()
  })

  observeEvent(input$sel_hierarchy, {
    req(input$sel_hierarchy)

    if (identical(input$sel_hierarchy, HIER_ACTION_SEPARATOR)) {
      refresh_hierarchy_dropdown(selected_hierarchy = state$CurrHierarchy %||% state$PrefHierarchy)
      return()
    }

    if (identical(input$sel_hierarchy, HIER_ACTION_ATTACH)) {
      showModal(modalDialog(
        title = "Attach Hierarchy Table",
        textInput("hier_attach_db_path", "DuckDB file path", value = ""),
        textInput("hier_attach_prefix", "Prefix for <prefix>_Hierarchy", value = state$CurrProject %||% ""),
        checkboxInput("hier_attach_replace", "Replace existing table if present", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("hier_attach_confirm", "Attach", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      refresh_hierarchy_dropdown(selected_hierarchy = state$CurrHierarchy %||% state$PrefHierarchy)
      return()
    }

    if (identical(input$sel_hierarchy, HIER_ACTION_NEW)) {
      showModal(modalDialog(
        title = "New Hierarchy Table",
        textInput("hier_new_prefix", "New prefix", value = state$CurrProject %||% ""),
        textInput("hier_new_template", "Template prefix", value = "Sample"),
        checkboxInput("hier_new_overwrite", "Overwrite if table exists", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("hier_new_confirm", "Create", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      refresh_hierarchy_dropdown(selected_hierarchy = state$CurrHierarchy %||% state$PrefHierarchy)
      return()
    }

    if (identical(input$sel_hierarchy, HIER_ACTION_UNATTACH)) {
      hierarchy_prefixes <- discover_prefixes_by_suffix(con, "_Hierarchy")
      hierarchy_choices <- hierarchy_prefixes[!tolower(hierarchy_prefixes) %in% c("sample")]
      showModal(modalDialog(
        title = "Unattach Hierarchy Table",
        if (length(hierarchy_choices) == 0) {
          tags$p("No detachable hierarchy tables found.")
        } else {
          selectInput("hier_unattach_prefix", "Prefix", choices = hierarchy_choices)
        },
        footer = tagList(
          modalButton("Cancel"),
          actionButton("hier_unattach_confirm", "Unattach", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
      refresh_hierarchy_dropdown(selected_hierarchy = state$CurrHierarchy %||% state$PrefHierarchy)
      return()
    }

    state$CurrHierarchy <- input$sel_hierarchy
    state$sysCurrHierarchy <- input$sel_hierarchy
    state$PrefHierarchy <- input$sel_hierarchy
    set_pref(con, "Current", "CurrHierarchy", input$sel_hierarchy)
  })

  observeEvent(input$hier_new_confirm, {
    req(input$hier_new_prefix)
    tryCatch({
      create_prefixed_table_from_template(
        con,
        prefix = trimws(input$hier_new_prefix),
        suffix = "_Hierarchy",
        template_prefix = trimws(input$hier_new_template),
        overwrite = isTRUE(input$hier_new_overwrite)
      )
      removeModal()
      refresh_hierarchy_dropdown(selected_hierarchy = trimws(input$hier_new_prefix))
      updateSelectInput(session, "sel_hierarchy", selected = trimws(input$hier_new_prefix))
      showNotification(paste0("Created hierarchy table: ", trimws(input$hier_new_prefix), "_Hierarchy"), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$hier_attach_confirm, {
    req(input$hier_attach_db_path, input$hier_attach_prefix)
    tryCatch({
      attach_prefixed_table(
        con,
        db_path = trimws(input$hier_attach_db_path),
        prefix = trimws(input$hier_attach_prefix),
        suffix = "_Hierarchy",
        replace_existing = isTRUE(input$hier_attach_replace)
      )
      removeModal()
      refresh_hierarchy_dropdown(selected_hierarchy = trimws(input$hier_attach_prefix))
      updateSelectInput(session, "sel_hierarchy", selected = trimws(input$hier_attach_prefix))
      showNotification(paste0("Attached hierarchy table: ", trimws(input$hier_attach_prefix), "_Hierarchy"), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$hier_unattach_confirm, {
    req(input$hier_unattach_prefix)
    tryCatch({
      removed <- unattach_prefixed_table(con, input$hier_unattach_prefix, suffix = "_Hierarchy")
      removeModal()
      if (identical(tolower(state$CurrHierarchy %||% ""), tolower(input$hier_unattach_prefix))) {
        state$CurrHierarchy <- NULL
        state$sysCurrHierarchy <- NULL
        state$PrefHierarchy <- NULL
      }
      refresh_hierarchy_dropdown()
      if (!is.null(removed)) {
        showNotification(paste0("Unattached hierarchy table: ", removed), type = "message")
      }
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
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
