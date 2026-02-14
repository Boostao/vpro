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
  environment <- Sys.getenv("R_CONFIG_ACTIVE", unset = "default")
  cfg <- tryCatch({
    config::get(config = environment)
  }, error = function(e) {
    stop("Failed to load config for environment '", environment, "': ", conditionMessage(e))
  })
  
  con <- connect_local_db(environment = environment)
  
  # Optionally attach cloud DB (non-fatal for local-only workflows)
  if (isTRUE(cfg$cloud$enabled) && isTRUE(cfg$cloud$attach_on_startup)) {
    tryCatch({
      attach_cloud_db(con, environment = environment, alias = "master", fail_on_error = FALSE)
    }, error = function(e) {
      warning("Cloud ATTACH failed (continuing in local-only mode): ", conditionMessage(e))
    })
  }
  
  # Ensure clean disconnect when session ends
  onSessionEnded(function() {
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

  PROJECT_ACTION_ATTACH <- "__project_action_attach__"
  PROJECT_ACTION_NEW <- "__project_action_new__"
  PROJECT_ACTION_UNATTACH <- "__project_action_unattach__"
  PROJECT_ACTION_SEPARATOR <- "__project_action_separator__"
  SU_ACTION_ATTACH <- "__su_action_attach__"
  SU_ACTION_NEW <- "__su_action_new__"
  SU_ACTION_UNATTACH <- "__su_action_unattach__"
  SU_ACTION_NONE <- "__su_action_none__"
  SU_ACTION_SEPARATOR <- "__su_action_separator__"
  HIER_ACTION_ATTACH <- "__hier_action_attach__"
  HIER_ACTION_NEW <- "__hier_action_new__"
  HIER_ACTION_UNATTACH <- "__hier_action_unattach__"
  HIER_ACTION_SEPARATOR <- "__hier_action_separator__"
  project_refresh <- reactiveVal(0L)

  action_labels <- function(include_none = FALSE) {
    base <- c("Attach", "New", "Unattach")
    if (isTRUE(include_none)) {
      base <- c(base, "None")
    }
    c(base, "--------------------------------------")
  }

  build_selector_choices <- function(dynamic_values, action_values, include_none = FALSE) {
    if (length(dynamic_values) == 0 && !isTRUE(include_none)) {
      labels <- action_labels(include_none = FALSE)[1:3]
      values <- action_values[labels]
      return(stats::setNames(values, labels))
    }

    labels <- c(action_labels(include_none = include_none), dynamic_values)
    values <- c(unname(action_values[action_labels(include_none = include_none)]), dynamic_values)
    stats::setNames(values, labels)
  }

  resolve_dynamic_selection <- function(selected, preferred, dynamic_values, none_value = NULL) {
    if (is.null(selected) || !nzchar(selected) || !(selected %in% dynamic_values)) {
      selected <- preferred
    }
    if (is.null(selected) || !nzchar(selected) || !(selected %in% dynamic_values)) {
      if (length(dynamic_values) > 0) {
        selected <- dynamic_values[[1]]
      } else if (!is.null(none_value)) {
        selected <- none_value
      }
    }
    selected
  }

  refresh_su_dropdown <- function(selected_su = NULL) {
    su_actions <- c(
      "Attach" = SU_ACTION_ATTACH,
      "New" = SU_ACTION_NEW,
      "Unattach" = SU_ACTION_UNATTACH,
      "None" = SU_ACTION_NONE,
      "--------------------------------------" = SU_ACTION_SEPARATOR
    )

    su_choices <- discover_prefixes_by_suffix(con, "_SU")
    values <- build_selector_choices(su_choices, su_actions, include_none = TRUE)
    selected_su <- resolve_dynamic_selection(
      selected = selected_su,
      preferred = state$PrefSUTable,
      dynamic_values = su_choices,
      none_value = SU_ACTION_NONE
    )

    updateSelectInput(session, "sel_su", choices = values, selected = selected_su)
    invisible(su_choices)
  }

  refresh_plot_dropdown <- function(su_prefix, selected_plot = NULL) {
    if (is.null(su_prefix) || !nzchar(su_prefix) || identical(su_prefix, "None")) {
      updateSelectInput(session, "sel_plot", choices = character(0), selected = character(0))
      return(invisible(character(0)))
    }

    su_table <- resolve_prefixed_table(con, su_prefix, "_SU")
    if (is.null(su_table)) {
      updateSelectInput(session, "sel_plot", choices = character(0), selected = character(0))
      return(invisible(character(0)))
    }

    plot_col <- tryCatch({
      cols <- DBI::dbListFields(con, su_table)
      cols[[match("plotnumber", tolower(cols))]]
    }, error = function(e) NULL)

    if (is.null(plot_col) || !nzchar(plot_col)) {
      updateSelectInput(session, "sel_plot", choices = character(0), selected = character(0))
      return(invisible(character(0)))
    }

    query <- paste0(
      "SELECT DISTINCT ", DBI::dbQuoteIdentifier(con, plot_col), " AS plotnumber ",
      "FROM ", DBI::dbQuoteIdentifier(con, su_table), " ",
      "WHERE ", DBI::dbQuoteIdentifier(con, plot_col), " IS NOT NULL ",
      "ORDER BY ", DBI::dbQuoteIdentifier(con, plot_col)
    )
    plots <- dbGetQuery(con, query)
    plot_values <- as.character(plots$plotnumber)

    selected_plot <- resolve_dynamic_selection(
      selected = selected_plot,
      preferred = state$PrefPlot,
      dynamic_values = plot_values,
      none_value = NULL
    )

    updateSelectInput(session, "sel_plot", choices = plot_values, selected = selected_plot)
    invisible(plot_values)
  }

  refresh_hierarchy_dropdown <- function(selected_hierarchy = NULL) {
    hierarchy_choices <- discover_prefixes_by_suffix(con, "_Hierarchy")
    hierarchy_actions <- c(
      "Attach" = HIER_ACTION_ATTACH,
      "New" = HIER_ACTION_NEW,
      "Unattach" = HIER_ACTION_UNATTACH,
      "--------------------------------------" = HIER_ACTION_SEPARATOR
    )

    values <- build_selector_choices(hierarchy_choices, hierarchy_actions, include_none = FALSE)
    selected_hierarchy <- resolve_dynamic_selection(
      selected = selected_hierarchy,
      preferred = state$PrefHierarchy,
      dynamic_values = hierarchy_choices,
      none_value = NULL
    )

    updateSelectInput(
      session,
      "sel_hierarchy",
      choices = values,
      selected = selected_hierarchy
    )
    invisible(hierarchy_choices)
  }

  refresh_project_dropdown <- function(selected = NULL) {
    projects <- discover_prefixes_by_suffix(con, "_Env")
    project_actions <- c(
      "Attach" = PROJECT_ACTION_ATTACH,
      "New" = PROJECT_ACTION_NEW,
      "Unattach" = PROJECT_ACTION_UNATTACH,
      "--------------------------------------" = PROJECT_ACTION_SEPARATOR
    )
    values <- build_selector_choices(projects, project_actions, include_none = FALSE)

    selected <- resolve_dynamic_selection(
      selected = selected,
      preferred = state$PrefProject,
      dynamic_values = projects,
      none_value = PROJECT_ACTION_NEW
    )

    updateSelectInput(session, "sel_project", choices = values, selected = selected)
    invisible(projects)
  }
  
  # 3. Populate Project Dropdown
  observe({
    project_refresh()
    tryCatch({
      refresh_project_dropdown()
    }, error = function(e) {
      log_msg("Error loading projects: ", conditionMessage(e))
    })
  })
  
  # 4. Handle Project Change
  observeEvent(input$sel_project, {
    req(input$sel_project)

    if (identical(input$sel_project, PROJECT_ACTION_SEPARATOR)) {
      isolate(refresh_project_dropdown(selected = state$CurrProject %||% state$PrefProject))
      return()
    }

    if (identical(input$sel_project, PROJECT_ACTION_ATTACH)) {
      showModal(modalDialog(
        title = "Attach Project",
        textInput("project_attach_db_path", "DuckDB file path", value = ""),
        textInput("project_attach_prefix", "Project prefix", value = ""),
        checkboxInput("project_attach_replace", "Replace existing project tables", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("project_attach_confirm", "Attach", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      isolate(refresh_project_dropdown(selected = state$CurrProject %||% state$PrefProject))
      return()
    }

    if (identical(input$sel_project, PROJECT_ACTION_NEW)) {
      showModal(modalDialog(
        title = "New Project",
        textInput("project_new_prefix", "New project prefix", value = ""),
        textInput("project_new_template", "Template prefix", value = "Sample"),
        checkboxInput("project_new_overwrite", "Overwrite if project tables already exist", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("project_new_confirm", "Create", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      isolate(refresh_project_dropdown(selected = state$CurrProject %||% state$PrefProject))
      return()
    }

    if (identical(input$sel_project, PROJECT_ACTION_UNATTACH)) {
      projects <- discover_prefixes_by_suffix(con, "_Env")
      choices <- projects[!tolower(projects) %in% c("sample")]
      showModal(modalDialog(
        title = "Unattach Project",
        if (length(choices) == 0) {
          tags$p("No detachable projects found.")
        } else {
          selectInput("project_unattach_prefix", "Project prefix", choices = choices)
        },
        footer = tagList(
          modalButton("Cancel"),
          actionButton("project_unattach_confirm", "Unattach", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
      isolate(refresh_project_dropdown(selected = state$CurrProject %||% state$PrefProject))
      return()
    }
    
    # Update State Logic
    set_project(state, input$sel_project, con)
    set_pref(con, "Current", "CurrProject", input$sel_project)
    state$PrefSUTable <- "None"
    set_pref(con, "Current", "CurrPlotList", "None")
    refresh_su_dropdown(selected_su = "None")
    refresh_plot_dropdown("None")
  })

  observeEvent(input$project_new_confirm, {
    req(input$project_new_prefix)
    tryCatch({
      create_project_table_set(
        con,
        prefix = trimws(input$project_new_prefix),
        template_prefix = trimws(input$project_new_template),
        overwrite = isTRUE(input$project_new_overwrite)
      )
      removeModal()
      state$PrefProject <- trimws(input$project_new_prefix)
      project_refresh(project_refresh() + 1L)
      refresh_project_dropdown(selected = state$PrefProject)
      updateSelectInput(session, "sel_project", selected = state$PrefProject)
      showNotification(paste0("Created project table set: ", state$PrefProject), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$project_attach_confirm, {
    req(input$project_attach_db_path, input$project_attach_prefix)
    tryCatch({
      attach_project_table_set(
        con,
        db_path = trimws(input$project_attach_db_path),
        prefix = trimws(input$project_attach_prefix),
        replace_existing = isTRUE(input$project_attach_replace)
      )
      removeModal()
      state$PrefProject <- trimws(input$project_attach_prefix)
      project_refresh(project_refresh() + 1L)
      refresh_project_dropdown(selected = state$PrefProject)
      updateSelectInput(session, "sel_project", selected = state$PrefProject)
      showNotification(paste0("Attached project table set: ", state$PrefProject), type = "message")
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })

  observeEvent(input$project_unattach_confirm, {
    req(input$project_unattach_prefix)
    tryCatch({
      dropped <- unattach_project_table_set(con, input$project_unattach_prefix)
      removeModal()
      project_refresh(project_refresh() + 1L)
      if (identical(tolower(state$CurrProject %||% ""), tolower(input$project_unattach_prefix))) {
        state$CurrProject <- NULL
        state$sysCurrProject <- NULL
      }
      refresh_project_dropdown()
      showNotification(
        paste0("Unattached project '", input$project_unattach_prefix, "' (", length(dropped), " tables)."),
        type = "message"
      )
    }, error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
  })
  
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
      refresh_plot_dropdown("None")
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
    refresh_plot_dropdown(input$sel_su)
  })

  observeEvent(input$sel_plot, {
    req(input$sel_plot)
    set_su(state, input$sel_plot)
    state$PrefPlot <- input$sel_plot
    set_pref(con, "Current", "CurrPlotNumber", input$sel_plot)
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
      refresh_plot_dropdown(trimws(input$su_new_prefix))
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
      refresh_plot_dropdown(trimws(input$su_attach_prefix))
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
        refresh_plot_dropdown("None")
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
    bslib::nav_select("main_tabs", "Vegetation", session = session)
  })

  mod_data_entry_context_server(
    "data_entry_context",
    state = state,
    con = con,
    open_data_entry_trigger = reactive(input$btn_nav_data_entry)
  )

  observeEvent(input$btn_nav_two_page, {
    bslib::nav_select("main_tabs", "Site & Env", session = session)
  })

  observeEvent(input$btn_nav_single_page, {
    bslib::nav_select("main_tabs", "Site & Env", session = session)
  })

  observeEvent(input$btn_nav_sivi, {
    bslib::nav_select("main_tabs", "Site & Env", session = session)
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

  observeEvent(input$btn_toggle_context, {
    bslib::toggle_sidebar("context_sidebar")
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
  
  # BEC Web Map Module (public-facing, no auth requirement)
  mod_becweb_map_server("becmap", con = con, auth_level = "public")
}
