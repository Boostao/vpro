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

  normalize_context_value <- function(value) {
    value <- trimws(as.character(value %||% ""))
    if (!nzchar(value)) "" else value
  }

  sidebar_mode <- reactiveVal("main")
  picker_site_unit <- reactiveVal(NULL)
  hierarchy_choices <- reactiveVal(character(0))
  site_unit_scope_version <- reactiveVal(0L)
  sidebar_hierarchy_site_unit <- reactiveVal(NULL)
  sidebar_hierarchy_status <- reactiveVal("")
  su_table_refresh_version <- reactiveVal(0L)

  refresh_site_unit_scope <- function() {
    site_unit_scope_version(isolate(site_unit_scope_version()) + 1L)
    invisible(site_unit_scope_version())
  }

  refresh_su_table_page <- function() {
    su_table_refresh_version(isolate(su_table_refresh_version()) + 1L)
    invisible(su_table_refresh_version())
  }

  require_sidebar_su_write <- function() {
    if (!is_cloud_connected(con)) {
      return(TRUE)
    }
    if (!auth_is_authenticated(state)) {
      showNotification("Sign in required.", type = "error")
      return(FALSE)
    }
    allowed <- c("write:project_plots", "write:all", "manage:codes")
    if (!any(vapply(allowed, function(permission) auth_user_has_permission(state, permission), logical(1)))) {
      showNotification("Permission required: edit site units", type = "error")
      return(FALSE)
    }
    TRUE
  }

  current_picker_site_unit <- reactive({
    site_unit <- input$picker_site_unit
    if (is.null(site_unit)) {
      site_unit <- picker_site_unit()
    }
    normalize_context_value(site_unit)
  })

  current_sidebar_site_unit <- reactive({
    normalize_context_value(sidebar_hierarchy_site_unit())
  })

  empty_picker_scope <- function() {
    data.frame(
      plotnumber = character(0),
      siteunit = character(0),
      stringsAsFactors = FALSE
    )
  }

  project_su_scope <- reactive({
    site_unit_scope_version()
    scope <- read_project_site_unit_scope(con, state$CurrProject)
    if (nrow(scope) == 0) empty_picker_scope() else scope
  })

  site_unit_tree_rows <- reactive({
    scoped <- project_su_scope()
    site_units <- unique(scoped$siteunit)
    if (length(site_units) == 0) {
      return(data.frame(
        id = character(0),
        name = character(0),
        depth = integer(0),
        is_site_unit = logical(0),
        plot_count = integer(0),
        stringsAsFactors = FALSE
      ))
    }

    rows <- data.frame(
      id = site_units,
      name = site_units,
      depth = rep(0L, length(site_units)),
      is_site_unit = rep(TRUE, length(site_units)),
      plot_count = rep(0L, length(site_units)),
      stringsAsFactors = FALSE
    )

    row_keys <- hierarchy_sidebar_normalize_key(rows$name)
    count_map <- integer(0)
    if (nrow(scoped) > 0) {
      count_map <- tapply(
        scoped$plotnumber,
        hierarchy_sidebar_normalize_key(scoped$siteunit),
        function(values) length(unique(values))
      )
    }

    rows$plot_count <- if (length(count_map) == 0) {
      rep(0L, nrow(rows))
    } else {
      counts <- count_map[row_keys]
      counts[is.na(counts)] <- 0L
      as.integer(counts)
    }

    rows[order(tolower(rows$name)), , drop = FALSE]
  })

  get_site_unit_for_plot <- function(plot_number, project_id = NULL) {
    plot_number <- normalize_context_value(plot_number)
    project_id <- normalize_context_value(project_id %||% state$CurrProject)
    if (!nzchar(plot_number) || !nzchar(project_id)) {
      return("")
    }

    scoped <- project_su_scope()
    hit <- scoped$siteunit[scoped$plotnumber == plot_number]
    if (length(hit) > 0) {
      return(hit[[1]])
    }

    if (!DBI::dbExistsTable(con, "Env") || !DBI::dbExistsTable(con, "SU")) {
      return("")
    }

    res <- tryCatch(
      DBI::dbGetQuery(
        con,
        paste(
          "SELECT s.siteunit",
          "FROM SU s",
          "INNER JOIN Env e ON e.plotnumber = s.plotnumber",
          "WHERE e.projectid = ? AND s.plotnumber = ?",
          "LIMIT 1"
        ),
        list(project_id, plot_number)
      ),
      error = function(e) data.frame(siteunit = character(0))
    )

    if (nrow(res) == 0) "" else normalize_context_value(res$siteunit[[1]])
  }

  picker_plot_rows <- reactive({
    site_unit <- current_picker_site_unit()
    scoped <- project_su_scope()
    if (!nzchar(site_unit) || nrow(scoped) == 0) {
      return(data.frame(PlotNumber = character(0), stringsAsFactors = FALSE))
    }

    rows <- scoped[scoped$siteunit == site_unit, , drop = FALSE]
    rows <- rows[order(rows$plotnumber), , drop = FALSE]
    data.frame(PlotNumber = unique(rows$plotnumber), stringsAsFactors = FALSE)
  })

  refresh_hierarchy_dropdown <- function() {
    hier_values <- sort(unique(project_su_scope()$siteunit))

    hierarchy_choices(hier_values[nzchar(hier_values)])
    invisible(hier_values)
  }

  apply_plot_selection <- function(plot_number, project_id = NULL, site_unit = NULL, persist = TRUE) {
    plot_number <- normalize_context_value(plot_number)
    project_id <- normalize_context_value(project_id %||% state$CurrProject)
    site_unit <- normalize_context_value(site_unit)
    current_sidebar_mode <- isolate(sidebar_mode())

    if (nzchar(project_id) && !identical(project_id, normalize_context_value(state$CurrProject))) {
      set_project(state, project_id, con)
      state$PrefProject <- project_id
      if (persist) {
        set_pref(con, "Current", "CurrProject", project_id)
      }
      refresh_hierarchy_dropdown()
    }

    if (!nzchar(plot_number)) {
      set_su(state, NULL)
      state$PrefPlot <- NULL
      if (persist) {
        set_pref(con, "Current", "CurrPlotNumber", "")
      }
      shiny::freezeReactiveValue(input, "sel_su")
      updateTextInput(session, "sel_su", value = "")
      return(invisible(NULL))
    }

    if (!nzchar(site_unit)) {
      site_unit <- get_site_unit_for_plot(plot_number, project_id = project_id)
    }

    set_su(state, plot_number)
    state$PrefPlot <- plot_number
    if (nzchar(site_unit) && !identical(site_unit, isolate(picker_site_unit()) %||% "")) {
      picker_site_unit(site_unit)
    }
    if (nzchar(site_unit)) {
      state$PrefSUTable <- site_unit
      if (persist) {
        set_pref(con, "Current", "CurrPlotList", site_unit)
      }
    }

    if (persist) {
      set_pref(con, "Current", "CurrPlotNumber", plot_number)
    }

    shiny::freezeReactiveValue(input, "sel_su")
    updateTextInput(session, "sel_su", value = plot_number)
    if (identical(current_sidebar_mode, "picker")) {
      sidebar_mode("picker")
    }
    invisible(plot_number)
  }

  session$userData$select_plot <- function(plot_number, project_id = NULL, site_unit = NULL, navigate_tab = NULL, sidebar = NULL) {
    selected_plot <- apply_plot_selection(
      plot_number = plot_number,
      project_id = project_id,
      site_unit = site_unit,
      persist = TRUE
    )

    if (!is.null(sidebar)) {
      sidebar_mode(sidebar)
    }

    if (!is.null(navigate_tab) && nzchar(navigate_tab)) {
      bslib::nav_select("main_tabs", navigate_tab, session = session)
    }

    invisible(selected_plot)
  }

  session$userData$show_site_unit_picker <- function(site_unit = NULL) {
    site_unit <- normalize_context_value(site_unit)
    if (nzchar(site_unit)) {
      picker_site_unit(site_unit)
    }
    sidebar_mode("picker")
    invisible(site_unit)
  }

  observe({
    scoped <- project_su_scope()
    available_site_units <- unique(scoped$siteunit)

    preferred_site_unit <- current_picker_site_unit()
    if (!nzchar(preferred_site_unit) || !(preferred_site_unit %in% available_site_units)) {
      preferred_site_unit <- normalize_context_value(state$PrefSUTable)
    }
    if (!nzchar(preferred_site_unit) || !(preferred_site_unit %in% available_site_units)) {
      preferred_site_unit <- get_site_unit_for_plot(state$CurrSU)
    }
    if (!nzchar(preferred_site_unit) || !(preferred_site_unit %in% available_site_units)) {
      preferred_site_unit <- if (length(available_site_units) > 0) available_site_units[[1]] else ""
    }

    normalized_choice <- if (nzchar(preferred_site_unit)) preferred_site_unit else NULL
    cached_choice <- normalize_context_value(isolate(picker_site_unit()))
    if (!identical(normalize_context_value(normalized_choice), cached_choice)) {
      picker_site_unit(normalized_choice)
    }

    cached_sidebar_choice <- normalize_context_value(isolate(sidebar_hierarchy_site_unit()))
    if (!identical(normalize_context_value(normalized_choice), cached_sidebar_choice)) {
      sidebar_hierarchy_site_unit(normalized_choice)
    }
  })

  output$nav_plot_context <- renderUI({
    project_name <- normalize_context_value(state$CurrProject %||% state$PrefProject)
    plot_name <- normalize_context_value(state$CurrSU)
    site_unit_name <- if (nzchar(plot_name)) {
      get_site_unit_for_plot(plot_name, project_id = project_name)
    } else {
      ""
    }

    make_context_item <- function(label, value) {
      div(
        class = "vpro-nav-context-item",
        div(class = "vpro-nav-context-label", label),
        div(class = "vpro-nav-context-value", if (nzchar(value)) value else "None")
      )
    }

    div(
      class = "vpro-nav-context",
      make_context_item("Project", project_name),
      div(class = "vpro-nav-context-sep"),
      make_context_item("Site Unit", site_unit_name),
      div(class = "vpro-nav-context-sep"),
      make_context_item("Plot", plot_name)
    )
  })

  output$sidebar_hierarchy_tree <- renderUI({
    rows <- site_unit_tree_rows()
    selected_key <- hierarchy_sidebar_normalize_key(current_sidebar_site_unit())

    if (nrow(rows) == 0) {
      return(div(class = "vpro-hierarchy-empty", "No site units loaded for this project."))
    }

    tree_nodes <- lapply(seq_len(nrow(rows)), function(idx) {
      row <- rows[idx, , drop = FALSE]
      row_key <- hierarchy_sidebar_normalize_key(row$name[[1]])
      classes <- c("vpro-hierarchy-node")
      attrs <- list(style = sprintf("--hierarchy-depth:%d;", row$depth[[1]] %||% 0L))

      if (isTRUE(row$is_site_unit[[1]])) {
        classes <- c(classes, "is-site-unit", "vpro-hierarchy-drop-target")
        attrs[["data-site-unit"]] <- row$name[[1]]
        attrs[["tabindex"]] <- "0"
      }
      if (isTRUE(row$plot_count[[1]] > 0L)) {
        classes <- c(classes, "has-plots")
      }
      if (identical(row_key, selected_key)) {
        classes <- c(classes, "is-active")
      }

      attrs$class <- paste(unique(classes), collapse = " ")

      do.call(
        div,
        c(
          attrs,
          list(
            div(class = "vpro-hierarchy-node-main",
              span(class = "vpro-hierarchy-node-label", row$name[[1]]),
              if (isTRUE(row$is_site_unit[[1]])) {
                span(class = "vpro-hierarchy-node-count", row$plot_count[[1]])
              }
            )
          )
        )
      )
    })

    div(class = "vpro-hierarchy-tree", tree_nodes)
  })

  output$sidebar_hierarchy_plots <- renderUI({
    site_unit <- current_sidebar_site_unit()
    if (!nzchar(site_unit)) {
      return(div(class = "vpro-hierarchy-empty", "Choose a site unit to browse its plots."))
    }

    scoped <- project_su_scope()
    plot_rows <- scoped[scoped$siteunit == site_unit, , drop = FALSE]
    plot_ids <- sort(unique(plot_rows$plotnumber))

    if (length(plot_ids) == 0) {
      return(
        div(
          class = "vpro-hierarchy-plot-shell",
          div(class = "vpro-hierarchy-plot-header",
            div(class = "vpro-hierarchy-plot-title", site_unit),
            div(class = "vpro-hierarchy-plot-subtitle", "No plots are currently assigned.")
          )
        )
      )
    }

    chips <- lapply(plot_ids, function(plot_id) {
      chip_classes <- c("vpro-hierarchy-plot-chip")
      if (identical(normalize_context_value(plot_id), normalize_context_value(state$CurrSU))) {
        chip_classes <- c(chip_classes, "is-current")
      }
      div(
        class = paste(chip_classes, collapse = " "),
        draggable = "true",
        `data-plot-number` = plot_id,
        `data-site-unit` = site_unit,
        plot_id
      )
    })

    div(
      class = "vpro-hierarchy-plot-shell",
      div(class = "vpro-hierarchy-plot-header",
        div(class = "vpro-hierarchy-plot-title", site_unit),
        div(class = "vpro-hierarchy-plot-subtitle", sprintf("%d plot%s", length(plot_ids), if (length(plot_ids) == 1) "" else "s"))
      ),
      div(class = "vpro-hierarchy-plot-instruction", "Click a plot to select it. Drag it onto another site unit in the list to reassign it."),
      div(class = "vpro-hierarchy-plot-list", chips)
    )
  })

  output$sidebar_hierarchy_status <- renderText({
    sidebar_hierarchy_status()
  })

  output$context_sidebar_content <- renderUI({
    current_mode <- sidebar_mode()
    site_unit_choices <- unique(project_su_scope()$siteunit)
    selected_site_unit <- current_picker_site_unit()
    if (!nzchar(selected_site_unit) || !(selected_site_unit %in% site_unit_choices)) {
      selected_site_unit <- ""
    }

    if (identical(current_mode, "picker")) {
      return(tagList(
        bslib::card(
          class = "vpro-picker-card mb-2",
          bslib::card_header(
            div(class = "d-flex justify-content-between align-items-center",
              div(
                div(class = "fw-semibold", "Site Unit Picker"),
                div(class = "small text-muted", "Choose a Site Unit, then pick a PlotNumber")
              ),
              actionButton("btn_picker_back", "Back", class = "btn btn-sm btn-outline-primary")
            )
          ),
          bslib::card_body(
            selectInput(
              "picker_site_unit",
              "Site Unit",
              choices = c("(None)" = "", site_unit_choices),
              selected = selected_site_unit
            ),
            div(class = "vpro-picker-table", DT::DTOutput("site_unit_plot_table"))
          )
        )
      ))
    }

    if (identical(current_mode, "hierarchy")) {
      return(tagList(
        bslib::card(
          class = "vpro-picker-card vpro-hierarchy-card mb-2",
          bslib::card_header(
            div(class = "d-flex justify-content-between align-items-center",
              div(
                div(class = "fw-semibold", "Site Unit Tree View"),
                div(class = "small text-muted", "Browse site units from the SU table, select plots, and drag them onto another site unit.")
              ),
              actionButton("btn_hierarchy_back", "Back", class = "btn btn-sm btn-outline-primary")
            )
          ),
          bslib::card_body(
            div(class = "vpro-hierarchy-workbench",
              div(class = "vpro-hierarchy-tree-shell", uiOutput("sidebar_hierarchy_tree")),
              div(class = "vpro-hierarchy-plot-panel", uiOutput("sidebar_hierarchy_plots"))
            ),
            div(class = "vpro-hierarchy-status small text-muted mt-2", textOutput("sidebar_hierarchy_status"))
          )
        )
      ))
    }

    tagList(
      mod_project_ui("project"),
      selectInput(
        "sel_hierarchy",
        "Hierarchy:",
        choices = c("(None)" = "", hierarchy_choices()),
        selected = normalize_context_value(state$CurrHierarchy)
      ),
      div(class = "vpro-section-title", "Data Forms"),
      actionButton("btn_nav_data_entry", "Data Entry Forms", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_two_page", "2-Page Forms", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_single_page", "Single-Page Form", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_sivi", "SIVI Form", class = "btn btn-light border w-100 mb-2"),
      div(class = "vpro-section-title", "Classification"),
      actionButton("btn_nav_su_tree", "Site Unit Tree View", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_su_table", "Site Unit Table", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_hierarchy_tree", "Hierarchy Tree View", class = "btn btn-light border w-100 mb-2"),
      hr(class = "my-2"),
      actionButton("btn_whatsnew", "What's New", class = "btn btn-outline-primary w-100 mb-2")
    )
  })

  output$site_unit_plot_table <- DT::renderDT({
    DT::datatable(
      picker_plot_rows(),
      rownames = FALSE,
      colnames = FALSE,
      selection = "single",
      class = "compact",
      options = list(
        dom = "t",
        pageLength = 8,
        ordering = FALSE,
        autoWidth = TRUE,
        scrollY = "280px",
        scroller = FALSE
      )
    )
  })

  observeEvent(input$picker_site_unit, {
    site_unit <- normalize_context_value(input$picker_site_unit)
    if (!identical(site_unit, normalize_context_value(isolate(picker_site_unit())))) {
      picker_site_unit(if (nzchar(site_unit)) site_unit else NULL)
    }
    if (!identical(site_unit, normalize_context_value(isolate(sidebar_hierarchy_site_unit())))) {
      sidebar_hierarchy_site_unit(if (nzchar(site_unit)) site_unit else NULL)
    }
    state$PrefSUTable <- if (nzchar(site_unit)) site_unit else NULL
    set_pref(con, "Current", "CurrPlotList", site_unit)
  }, ignoreNULL = FALSE)

  observeEvent(input$hierarchy_sidebar_select_site_unit, {
    info <- input$hierarchy_sidebar_select_site_unit
    site_unit <- normalize_context_value(if (is.list(info)) info$site_unit else info)
    if (!nzchar(site_unit)) {
      return()
    }

    sidebar_hierarchy_site_unit(site_unit)
    picker_site_unit(site_unit)
    state$PrefSUTable <- site_unit
    set_pref(con, "Current", "CurrPlotList", site_unit)
    sidebar_hierarchy_status(paste("Viewing", site_unit))
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_select_plot, {
    info <- input$hierarchy_sidebar_select_plot
    plot_number <- normalize_context_value(if (is.list(info)) info$plot_number else NULL)
    site_unit <- normalize_context_value(if (is.list(info)) info$site_unit else NULL)
    if (!nzchar(plot_number)) {
      return()
    }

    if (nzchar(site_unit)) {
      sidebar_hierarchy_site_unit(site_unit)
    }
    apply_plot_selection(plot_number = plot_number, site_unit = site_unit, persist = TRUE)
    sidebar_hierarchy_status(paste("Selected plot", plot_number))
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_drop, {
    info <- input$hierarchy_sidebar_drop
    plot_number <- normalize_context_value(if (is.list(info)) info$plot_number else NULL)
    from_site_unit <- normalize_context_value(if (is.list(info)) info$from_site_unit else NULL)
    to_site_unit <- normalize_context_value(if (is.list(info)) info$to_site_unit else NULL)

    if (!nzchar(plot_number) || !nzchar(to_site_unit)) {
      return()
    }
    if (identical(from_site_unit, to_site_unit)) {
      sidebar_hierarchy_status(paste("Plot", plot_number, "is already assigned to", to_site_unit))
      return()
    }
    if (!require_sidebar_su_write()) {
      return()
    }

    result <- tryCatch(
      hierarchy_sidebar_reassign_plot(
        con = con,
        plot_number = plot_number,
        to_site_unit = to_site_unit,
        user = state$User,
        fallback_project = state$CurrProject,
        allowed_site_units = unique(project_su_scope()$siteunit)
      ),
      error = function(e) e
    )

    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error")
      sidebar_hierarchy_status(conditionMessage(result))
      return()
    }

    refresh_site_unit_scope()
    refresh_su_table_page()
    picker_site_unit(to_site_unit)
    sidebar_hierarchy_site_unit(to_site_unit)
    state$PrefSUTable <- to_site_unit
    set_pref(con, "Current", "CurrPlotList", to_site_unit)

    if (identical(normalize_context_value(state$CurrSU), plot_number)) {
      apply_plot_selection(plot_number = plot_number, site_unit = to_site_unit, persist = TRUE)
    }

    sidebar_hierarchy_status(sprintf("Moved %s from %s to %s.", plot_number, if (nzchar(from_site_unit)) from_site_unit else "(unassigned)", to_site_unit))
    showNotification(sprintf("Moved %s to %s", plot_number, to_site_unit), type = "message")
  }, ignoreInit = TRUE)

  observeEvent(input$picker_site_unit, {
    DT::selectRows(DT::dataTableProxy("site_unit_plot_table"), NULL)
  }, ignoreInit = TRUE)

  observeEvent(input$site_unit_plot_table_rows_selected, {
    selected_index <- input$site_unit_plot_table_rows_selected
    rows <- picker_plot_rows()
    if (length(selected_index) != 1 || nrow(rows) < selected_index) {
      return()
    }

    apply_plot_selection(
      plot_number = rows$PlotNumber[[selected_index]],
      site_unit = current_picker_site_unit(),
      persist = TRUE
    )
  }, ignoreInit = TRUE)

  observeEvent(input$sel_su, {
    incoming_plot <- normalize_context_value(input$sel_su)
    current_plot <- normalize_context_value(state$CurrSU)
    if (identical(incoming_plot, current_plot)) {
      return()
    }

    apply_plot_selection(plot_number = incoming_plot, persist = TRUE)
  }, ignoreInit = TRUE)

  # 3. Project module (replaces old sel_project sentinel dropdown)
  project_mod <- mod_project_server("project", state, con)

  # Refresh picker scope + hierarchy when project changes
  observe({
    project_mod$project_changed()
    refresh_hierarchy_dropdown()
    shiny::freezeReactiveValue(input, "sel_su")
    updateTextInput(session, "sel_su", value = normalize_context_value(state$CurrSU))
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
    sidebar_mode("hierarchy")
  })

  observeEvent(input$btn_picker_back, {
    sidebar_mode("main")
  })

  observeEvent(input$btn_hierarchy_back, {
    sidebar_mode("main")
  })

  observeEvent(input$btn_nav_su_table, {
    refresh_su_table_page()
    bslib::nav_select("main_tabs", "SU Table", session = session)
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

  mod_su_table_server(
    "su_table",
    state,
    con,
    refresh_trigger = reactive(su_table_refresh_version()),
    active_tab = reactive(input$main_tabs)
  )

  # Hierarchy Module
  mod_hierarchy_server("hier", state, con)
  
  # BEC Web Map Module (public-facing, no auth requirement)
  mod_becweb_map_server("becmap", con = con, auth_level = "public")
}
