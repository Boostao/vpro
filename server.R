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
  sync_ensure_local_tables(con)
  project_ensure_baseline_table(con)

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
  sidebar_hierarchy_node_id <- reactiveVal(NULL)
  sidebar_hierarchy_expanded <- reactiveVal(character(0))
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

  observeEvent(state$HierarchyRefreshVersion, {
    refresh_site_unit_scope()
    refresh_hierarchy_dropdown()
    refresh_su_table_page()
  }, ignoreInit = TRUE)

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

  require_sidebar_hierarchy_write <- function() {
    if (!is_cloud_connected(con)) {
      return(TRUE)
    }
    if (!auth_is_authenticated(state)) {
      showNotification("Sign in required.", type = "error")
      return(FALSE)
    }
    allowed <- c("write:project_plots", "write:all", "manage:codes")
    if (!any(vapply(allowed, function(permission) auth_user_has_permission(state, permission), logical(1)))) {
      showNotification("Permission required: edit hierarchy", type = "error")
      return(FALSE)
    }
    TRUE
  }

  sidebar_add_site_token <- "__vpro_add_site__"
  sidebar_add_plot_token <- "__vpro_add_plot__"

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

  current_sidebar_hierarchy_id <- reactive({
    hierarchy_sidebar_normalize_id(sidebar_hierarchy_node_id())
  })

  hierarchy_sidebar_sort_nodes <- function(nodes) {
    if (is.null(nodes) || nrow(nodes) == 0) {
      return(nodes)
    }
    if ("MyOrder" %in% names(nodes) && any(is.finite(nodes$MyOrder))) {
      nodes[order(nodes$MyOrder, tolower(nodes$Name), na.last = TRUE), , drop = FALSE]
    } else {
      nodes[order(tolower(nodes$Name)), , drop = FALSE]
    }
  }

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
    site_units <- unique(scoped$siteunit[nzchar(scoped$siteunit)])
    rows <- rbind(
      data.frame(
        id = sidebar_add_site_token,
        name = "Add Site",
        depth = 0L,
        is_site_unit = TRUE,
        plot_count = NA_integer_,
        is_add_action = TRUE,
        stringsAsFactors = FALSE
      ),
      data.frame(
        id = site_units,
        name = site_units,
        depth = rep(0L, length(site_units)),
        is_site_unit = rep(TRUE, length(site_units)),
        plot_count = rep(0L, length(site_units)),
        is_add_action = rep(FALSE, length(site_units)),
        stringsAsFactors = FALSE
      )
    )

    row_keys <- hierarchy_sidebar_normalize_key(rows$name)
    count_map <- integer(0)
    scoped_with_plots <- scoped[nzchar(scoped$plotnumber), , drop = FALSE]
    if (nrow(scoped_with_plots) > 0) {
      count_map <- tapply(
        scoped_with_plots$plotnumber,
        hierarchy_sidebar_normalize_key(scoped_with_plots$siteunit),
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

    rows$plot_count[rows$is_add_action] <- NA_integer_

    add_rows <- rows[rows$is_add_action, , drop = FALSE]
    regular_rows <- rows[!rows$is_add_action, , drop = FALSE]
    regular_rows <- regular_rows[order(tolower(regular_rows$name)), , drop = FALSE]
    rbind(add_rows, regular_rows)
  })

  project_hierarchy_nodes <- reactive({
    state$CurrProject
    state$HierarchyRefreshVersion
    hierarchy_sidebar_read_nodes(con, project_id = state$CurrProject)
  })

  observe({
    nodes <- project_hierarchy_nodes()
    selected_id <- current_sidebar_hierarchy_id()
    expanded_ids <- isolate(sidebar_hierarchy_expanded())

    if (nrow(nodes) == 0) {
      if (nzchar(selected_id)) {
        sidebar_hierarchy_node_id(NULL)
      }
      if (length(expanded_ids) > 0) {
        sidebar_hierarchy_expanded(character(0))
      }
      return()
    }

    if (nzchar(selected_id) && !(selected_id %in% nodes$ID)) {
      sidebar_hierarchy_node_id(NULL)
    }

    valid_expanded <- intersect(expanded_ids, nodes$ID)
    if (!identical(valid_expanded, expanded_ids)) {
      sidebar_hierarchy_expanded(valid_expanded)
    }
  })

  build_sidebar_hierarchy_visible_rows <- function(nodes, expanded_ids, parent_id = NA_character_, depth = 0L) {
    if (is.null(nodes) || nrow(nodes) == 0) {
      return(data.frame(
        id = character(0),
        parent_id = character(0),
        name = character(0),
        depth = integer(0),
        child_count = integer(0),
        is_expanded = logical(0),
        stringsAsFactors = FALSE
      ))
    }

    branch <- if (is.na(parent_id)) {
      nodes[is.na(nodes$Parent), , drop = FALSE]
    } else {
      nodes[!is.na(nodes$Parent) & nodes$Parent == parent_id, , drop = FALSE]
    }
    branch <- hierarchy_sidebar_sort_nodes(branch)
    if (nrow(branch) == 0) {
      return(data.frame(
        id = character(0),
        parent_id = character(0),
        name = character(0),
        depth = integer(0),
        child_count = integer(0),
        is_expanded = logical(0),
        stringsAsFactors = FALSE
      ))
    }

    pieces <- lapply(seq_len(nrow(branch)), function(idx) {
      row <- branch[idx, , drop = FALSE]
      node_id <- row$ID[[1]]
      direct_child_count <- sum(!is.na(nodes$Parent) & nodes$Parent == node_id)
      child_count <- length(hierarchy_sidebar_get_descendants(nodes, node_id))
      expanded <- node_id %in% expanded_ids

      children <- if (direct_child_count > 0L && expanded) {
        build_sidebar_hierarchy_visible_rows(nodes, expanded_ids, parent_id = node_id, depth = depth + 1L)
      } else {
        data.frame(
          id = character(0),
          parent_id = character(0),
          name = character(0),
          depth = integer(0),
          child_count = integer(0),
          is_expanded = logical(0),
          stringsAsFactors = FALSE
        )
      }

      rbind(
        data.frame(
          id = node_id,
          parent_id = if (is.na(row$Parent[[1]])) "" else row$Parent[[1]],
          name = row$Name[[1]],
          depth = depth,
          child_count = child_count,
          is_expanded = expanded,
          stringsAsFactors = FALSE
        ),
        children
      )
    })

    do.call(rbind, pieces)
  }

  sidebar_hierarchy_tree_rows <- reactive({
    nodes <- project_hierarchy_nodes()
    expanded_ids <- sidebar_hierarchy_expanded()

    if (nrow(nodes) == 0) {
      return(data.frame(
        id = character(0),
        parent_id = character(0),
        name = character(0),
        depth = integer(0),
        child_count = integer(0),
        is_expanded = logical(0),
        stringsAsFactors = FALSE
      ))
    }

    build_sidebar_hierarchy_visible_rows(nodes, expanded_ids)
  })

  selected_sidebar_hierarchy <- reactive({
    nodes <- project_hierarchy_nodes()
    selected_id <- current_sidebar_hierarchy_id()
    root_count <- if (nrow(nodes) == 0) 0L else sum(is.na(nodes$Parent))

    if (!nzchar(selected_id)) {
      return(list(
        id = "",
        name = "Root",
        parent_id = "",
        parent_name = "",
        path = "Root",
        child_count = root_count,
        is_root = TRUE
      ))
    }

    if (nrow(nodes) == 0) {
      return(NULL)
    }

    row <- nodes[nodes$ID == selected_id, , drop = FALSE]
    if (nrow(row) == 0) {
      return(list(
        id = "",
        name = "Root",
        parent_id = "",
        parent_name = "",
        path = "Root",
        child_count = root_count,
        is_root = TRUE
      ))
    }

    parent_id <- if (is.na(row$Parent[[1]])) "" else row$Parent[[1]]
    parent_row <- if (nzchar(parent_id)) nodes[nodes$ID == parent_id, , drop = FALSE] else data.frame()
    list(
      id = row$ID[[1]],
      name = row$Name[[1]],
      parent_id = if (nzchar(parent_id)) parent_id else "",
      parent_name = if (nrow(parent_row) == 0) "Root" else parent_row$Name[[1]],
      path = c("Root", hierarchy_sidebar_get_path_names(nodes, row$ID[[1]])),
      child_count = sum(!is.na(nodes$Parent) & nodes$Parent == row$ID[[1]]),
      is_root = FALSE
    )
  })

  sidebar_hierarchy_breadcrumbs <- reactive({
    details <- selected_sidebar_hierarchy()
    nodes <- project_hierarchy_nodes()

    if (is.null(details) || isTRUE(details$is_root)) {
      return(data.frame(
        id = "",
        label = "Root",
        is_current = TRUE,
        stringsAsFactors = FALSE
      ))
    }

    path_ids <- hierarchy_sidebar_get_path_ids(nodes, details$id)
    path_names <- hierarchy_sidebar_get_path_names(nodes, details$id)
    data.frame(
      id = c("", path_ids),
      label = c("Root", path_names),
      is_current = c(rep(FALSE, length(path_ids)), TRUE),
      stringsAsFactors = FALSE
    )
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
    rows <- rows[nzchar(rows$plotnumber), , drop = FALSE]
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

  output$nav_sync_label <- renderUI({
    state$SyncVersion
    project_id <- normalize_context_value(state$CurrProject %||% state$PrefProject)
    compare_source <- state$SyncCompareSource %||% NULL
    pending_counts <- if (nzchar(project_id)) {
      tryCatch(
        sync_get_pending_summary(con, project_id = project_id, compare_source = compare_source)$total[c("insert", "update", "delete")],
        error = function(e) c(insert = 0L, update = 0L, delete = 0L)
      )
    } else {
      c(insert = 0L, update = 0L, delete = 0L)
    }

    tagList(
      icon("arrows-rotate"),
      span("Sync"),
      if (pending_counts[["insert"]] > 0) tags$span(class = "badge rounded-pill ms-1", style = "background:#43893e;color:#fff;", pending_counts[["insert"]]),
      if (pending_counts[["update"]] > 0) tags$span(class = "badge rounded-pill ms-1", style = "background:#f9ca54;color:#222;", pending_counts[["update"]]),
      if (pending_counts[["delete"]] > 0) tags$span(class = "badge rounded-pill ms-1", style = "background:#c03b2b;color:#fff;", pending_counts[["delete"]])
    )
  })

  output$sidebar_hierarchy_tree <- renderUI({
    rows <- site_unit_tree_rows()
    selected_key <- hierarchy_sidebar_normalize_key(isolate(current_sidebar_site_unit()))

    if (nrow(rows) == 0) {
      return(div(class = "vpro-hierarchy-empty", "No site units loaded for this project."))
    }

    tree_nodes <- lapply(seq_len(nrow(rows)), function(idx) {
      row <- rows[idx, , drop = FALSE]
      row_key <- hierarchy_sidebar_normalize_key(row$name[[1]])
      classes <- c("vpro-hierarchy-node")
      attrs <- list(style = sprintf("--hierarchy-depth:%d;", row$depth[[1]] %||% 0L))
      is_add_action <- isTRUE(row$is_add_action[[1]])

      if (isTRUE(row$is_site_unit[[1]])) {
        classes <- c(classes, "is-site-unit")
        if (is_add_action) {
          classes <- c(classes, "is-add-action")
          attrs[["data-site-unit"]] <- sidebar_add_site_token
        } else {
          classes <- c(classes, "vpro-hierarchy-drop-target")
          attrs[["data-site-unit"]] <- row$name[[1]]
        }
        attrs[["tabindex"]] <- "0"
      }
      if (!is_add_action && isTRUE(row$plot_count[[1]] > 0L)) {
        classes <- c(classes, "has-plots")
      }
      if (!is_add_action && identical(row_key, selected_key)) {
        classes <- c(classes, "is-active")
      }

      attrs$class <- paste(unique(classes), collapse = " ")

      do.call(
        div,
        c(
          attrs,
          list(
            div(class = "vpro-hierarchy-node-main",
              if (is_add_action) {
                span(
                  class = "vpro-hierarchy-node-label vpro-hierarchy-add-label",
                  icon("plus"),
                  span("Add Site")
                )
              } else {
                span(class = "vpro-hierarchy-node-label", row$name[[1]])
              },
              if (isTRUE(row$is_site_unit[[1]]) && !is_add_action) {
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
    plot_rows <- plot_rows[nzchar(plot_rows$plotnumber), , drop = FALSE]
    plot_ids <- sort(unique(plot_rows$plotnumber))

    chips <- c(
      lapply(plot_ids, function(plot_id) {
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
      }),
      list(
        div(
          class = "vpro-hierarchy-plot-chip is-add-action",
          `data-plot-number` = sidebar_add_plot_token,
          `data-site-unit` = site_unit,
          tabindex = "0",
          span(class = "vpro-hierarchy-add-label", icon("plus"), span("Add Plot"))
        )
      )
    )

    div(
      class = "vpro-hierarchy-plot-shell",
      div(class = "vpro-hierarchy-plot-header",
        div(class = "vpro-hierarchy-plot-title", site_unit),
        div(class = "vpro-hierarchy-plot-subtitle", if (length(plot_ids) == 0) "No plots are currently assigned." else sprintf("%d plot%s", length(plot_ids), if (length(plot_ids) == 1) "" else "s"))
      ),
      div(class = "vpro-hierarchy-plot-instruction", "Click a plot to select it or drag it onto another site unit to reassign it."),
      div(class = "vpro-hierarchy-plot-list", chips)
    )
  })

  output$sidebar_hierarchy_status <- renderText({
    sidebar_hierarchy_status()
  })

  output$sidebar_hierarchy_node_tree <- renderUI({
    rows <- sidebar_hierarchy_tree_rows()
    details <- selected_sidebar_hierarchy()
    nodes <- project_hierarchy_nodes()

    if (is.null(details) && nrow(rows) == 0) {
      return(div(class = "vpro-hierarchy-empty", "No hierarchy nodes are available for this project."))
    }

    selected_id <- current_sidebar_hierarchy_id()
    selected_path_ids <- if (nzchar(selected_id) && nrow(nodes) > 0) {
      hierarchy_sidebar_get_path_ids(nodes, selected_id)
    } else {
      character(0)
    }
    tree_rows <- if (nrow(rows) == 0) {
      div(class = "vpro-hierarchy-empty", "No hierarchy nodes are available for this project.")
    } else {
      lapply(seq_len(nrow(rows)), function(idx) {
        row <- rows[idx, , drop = FALSE]
        depth_value <- as.integer(row$depth[[1]] %||% 0L)
        classes <- c(
          "vpro-hierarchy-tree-node",
          "vpro-hierarchy-node",
          "is-hierarchy-node",
          "vpro-hierarchy-drop-target",
          "vpro-hierarchy-nav-target"
        )
        if (depth_value > 0L) {
          classes <- c(classes, "has-depth")
        }
        classes <- c(classes, if ((depth_value %% 2L) == 0L) "is-depth-even" else "is-depth-odd")
        if (identical(row$id[[1]], selected_id)) {
          classes <- c(classes, "is-active")
        }
        if (row$id[[1]] %in% selected_path_ids) {
          classes <- c(classes, "is-selected-path")
        }
        if (length(selected_path_ids) > 0 && identical(row$id[[1]], selected_path_ids[[1]])) {
          classes <- c(classes, "is-path-root")
        }
        if (isTRUE(row$is_expanded[[1]])) {
          classes <- c(classes, "is-expanded")
        }

        has_children <- isTRUE(row$child_count[[1]] > 0L)

        div(
          class = paste(unique(classes), collapse = " "),
          `data-open-node` = row$id[[1]],
          `data-hierarchy-id` = row$id[[1]],
          `data-parent-id` = row$id[[1]],
          `data-depth` = as.character(depth_value),
          style = sprintf("--hierarchy-depth:%d;", depth_value),
          tabindex = "0",
          div(class = "vpro-hierarchy-node-main",
            div(class = "vpro-hierarchy-tree-node-copy",
              tags$button(
                class = paste(
                  c(
                    "vpro-hierarchy-toggle",
                    if (has_children) "has-children" else "is-leaf",
                    if (isTRUE(row$is_expanded[[1]])) "is-expanded"
                  ),
                  collapse = " "
                ),
                type = "button",
                `data-toggle-node` = row$id[[1]],
                tabindex = "-1",
                if (!has_children) "" else if (isTRUE(row$is_expanded[[1]])) "-" else "+"
              ),
              span(class = "vpro-hierarchy-node-label", row$name[[1]])
            ),
            div(class = "vpro-hierarchy-tree-node-actions",
              div(
                class = "vpro-hierarchy-drag-handle",
                `data-drag-node-id` = row$id[[1]],
                `data-drag-parent-id` = row$parent_id[[1]],
                draggable = "true",
                tabindex = "-1",
                "Move"
              ),
              span(class = "vpro-hierarchy-node-count", row$child_count[[1]])
            )
          )
        )
      })
    }

    div(
      class = "vpro-hierarchy-browser vpro-hierarchy-progressive-tree",
      div(
        class = "vpro-hierarchy-browser-current is-root vpro-hierarchy-drop-target",
        `data-parent-id` = "",
        div(class = "vpro-hierarchy-browser-current-label", "Tree root"),
        div(class = "vpro-hierarchy-browser-current-name", "Hierarchy"),
        div(class = "vpro-hierarchy-browser-current-subtitle", "Start at the root and unveil more nodes as needed."),
        div(class = "vpro-hierarchy-detail-path", if (is.null(details)) "Root" else paste(details$path, collapse = " / "))
      ),
      div(class = "vpro-hierarchy-browser-level-header",
        div(class = "vpro-hierarchy-browser-level-title", "Hierarchy tree"),
        div(class = "vpro-hierarchy-browser-level-count", sprintf("%d visible node%s", nrow(rows), if (nrow(rows) == 1) "" else "s"))
      ),
      div(class = "vpro-hierarchy-browser-list", tree_rows),
      div(class = "vpro-hierarchy-plot-instruction", if (is.null(details) || isTRUE(details$is_root)) {
        "Click a node name or its + button to reveal children. Drag a Move handle and drop it on any visible node or on the root card to reassign it."
      } else {
        sprintf("Selected: %s. Expand more branches as needed, or drag a Move handle to reassign a visible node.", details$name)
      }),
      if (nzchar(sidebar_hierarchy_status())) div(class = "vpro-hierarchy-status", sidebar_hierarchy_status())
    )
  })

  observe({
    selected_site_unit <- current_sidebar_site_unit()
    current_mode <- sidebar_mode()

    session$onFlushed(function() {
      session$sendCustomMessage(
        "hierarchy-sidebar-selection",
        list(
          site_unit = selected_site_unit,
          scroll = identical(current_mode, "hierarchy") && nzchar(selected_site_unit)
        )
      )
    }, once = TRUE)
  })

  observe({
    selected_id <- current_sidebar_hierarchy_id()
    current_mode <- sidebar_mode()

    session$onFlushed(function() {
      session$sendCustomMessage(
        "hierarchy-sidebar-node-selection",
        list(
          node_id = selected_id,
          scroll = identical(current_mode, "hierarchy_nodes") && nzchar(selected_id)
        )
      )
    }, once = TRUE)
  })

  output$context_sidebar_content <- renderUI({
    current_mode <- sidebar_mode()

    if (identical(current_mode, "picker")) {
      site_unit_choices <- unique(project_su_scope()$siteunit)
      selected_site_unit <- current_picker_site_unit()
      if (!nzchar(selected_site_unit) || !(selected_site_unit %in% site_unit_choices)) {
        selected_site_unit <- ""
      }

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
                div(class = "fw-semibold", "Site Unit Tree View")
              ),
              actionButton("btn_hierarchy_back", "Back", class = "btn btn-sm btn-outline-primary")
            )
          ),
          bslib::card_body(
            div(class = "vpro-hierarchy-workbench",
              div(class = "vpro-hierarchy-tree-shell", uiOutput("sidebar_hierarchy_tree")),
              div(class = "vpro-hierarchy-plot-panel", uiOutput("sidebar_hierarchy_plots"))
            )
          )
        )
      ))
    }

    if (identical(current_mode, "hierarchy_nodes")) {
      return(tagList(
        bslib::card(
          class = "vpro-picker-card vpro-hierarchy-card mb-2",
          bslib::card_header(
            div(class = "d-flex justify-content-between align-items-center",
              div(
                div(class = "fw-semibold", "Hierarchy Tree View")
              ),
              actionButton("btn_hierarchy_back", "Back", class = "btn btn-sm btn-outline-primary")
            )
          ),
          bslib::card_body(
            div(class = "vpro-hierarchy-workbench vpro-hierarchy-node-workbench",
              div(class = "vpro-hierarchy-tree-shell vpro-hierarchy-single-shell", uiOutput("sidebar_hierarchy_node_tree"))
            )
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

    if (identical(site_unit, sidebar_add_site_token)) {
      if (!require_sidebar_su_write()) {
        return()
      }

      showModal(
        modalDialog(
          title = "New Site Unit",
          textInput("hierarchy_new_site_unit_name", "Site Unit name"),
          div(class = "small text-muted", "The new site unit will appear immediately in the tree, even before any plots are assigned."),
          easyClose = TRUE,
          footer = tagList(
            modalButton("Cancel"),
            actionButton("confirm_new_site_unit", "Create site unit", class = "btn btn-primary")
          )
        )
      )
      return()
    }

    sidebar_hierarchy_site_unit(site_unit)
    picker_site_unit(site_unit)
    state$PrefSUTable <- site_unit
    set_pref(con, "Current", "CurrPlotList", site_unit)
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_select_node, {
    info <- input$hierarchy_sidebar_select_node
    raw_node_id <- if (is.list(info)) info$node_id else info
    node_id <- hierarchy_sidebar_normalize_id(raw_node_id)

    if (is.null(raw_node_id) || identical(raw_node_id, "") || !nzchar(node_id)) {
      sidebar_hierarchy_node_id(NULL)
      sidebar_hierarchy_status("Viewing root")
      return()
    }

    sidebar_hierarchy_node_id(node_id)
    nodes <- project_hierarchy_nodes()
    row <- nodes[nodes$ID == node_id, , drop = FALSE]
    if (nrow(row) > 0) {
      sidebar_hierarchy_status(sprintf("Selected %s", row$Name[[1]]))
    }
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_toggle_node, {
    info <- input$hierarchy_sidebar_toggle_node
    node_id <- hierarchy_sidebar_normalize_id(if (is.list(info)) info$node_id else info)
    if (!nzchar(node_id)) {
      return()
    }

    nodes <- project_hierarchy_nodes()
    row <- nodes[nodes$ID == node_id, , drop = FALSE]
    if (nrow(row) == 0) {
      return()
    }

    expanded_ids <- isolate(sidebar_hierarchy_expanded())
    child_count <- sum(!is.na(nodes$Parent) & nodes$Parent == node_id)
    if (child_count > 0L) {
      if (node_id %in% expanded_ids) {
        descendants <- hierarchy_sidebar_get_descendants(nodes, node_id)
        sidebar_hierarchy_expanded(setdiff(expanded_ids, c(node_id, descendants)))
      } else {
        sidebar_hierarchy_expanded(unique(c(expanded_ids, node_id)))
      }
    }

    sidebar_hierarchy_node_id(node_id)
    sidebar_hierarchy_status(sprintf("Selected %s", row$Name[[1]]))
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_select_plot, {
    info <- input$hierarchy_sidebar_select_plot
    plot_number <- normalize_context_value(if (is.list(info)) info$plot_number else NULL)
    site_unit <- normalize_context_value(if (is.list(info)) info$site_unit else NULL)
    if (!nzchar(plot_number)) {
      return()
    }

    if (identical(plot_number, sidebar_add_plot_token)) {
      if (!require_sidebar_su_write()) {
        return()
      }
      if (!nzchar(site_unit)) {
        showNotification("Choose a site unit before adding a plot.", type = "warning")
        return()
      }

      showModal(
        modalDialog(
          title = paste("New Plot for", site_unit),
          textInput("hierarchy_new_plot_number", "Plot number"),
          div(class = "small text-muted", "The new plot will be created in the current project and assigned to this site unit."),
          easyClose = TRUE,
          footer = tagList(
            modalButton("Cancel"),
            actionButton("confirm_new_plot", "Create plot", class = "btn btn-primary")
          )
        )
      )
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
    sync_touch_state(state)
    showNotification(sprintf("Moved %s to %s", plot_number, to_site_unit), type = "message")
  }, ignoreInit = TRUE)

  observeEvent(input$hierarchy_sidebar_move_node, {
    info <- input$hierarchy_sidebar_move_node
    node_id <- hierarchy_sidebar_normalize_id(if (is.list(info)) info$node_id else NULL)
    parent_id <- hierarchy_sidebar_normalize_id(if (is.list(info)) info$parent_id else NULL)

    if (!nzchar(node_id)) {
      return()
    }
    if (!require_sidebar_hierarchy_write()) {
      return()
    }

    result <- tryCatch(
      hierarchy_sidebar_move_node(
        con = con,
        node_id = node_id,
        parent_id = if (nzchar(parent_id)) parent_id else NULL,
        project_id = state$CurrProject
      ),
      error = function(e) e
    )

    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error")
      sidebar_hierarchy_status(conditionMessage(result))
      return()
    }

    sidebar_hierarchy_node_id(result$node_id)
    state$HierarchyRefreshVersion <- (state$HierarchyRefreshVersion %||% 0L) + 1L
    sync_touch_state(state)

    if (isTRUE(result$changed)) {
      updated_nodes <- hierarchy_sidebar_read_nodes(con, project_id = state$CurrProject, table_name = result$table_name)
      parent_row <- if (!is.na(result$to_parent_id) && nzchar(as.character(result$to_parent_id))) {
        updated_nodes[updated_nodes$ID == result$to_parent_id, , drop = FALSE]
      } else {
        data.frame()
      }
      target_label <- if (nrow(parent_row) == 0) {
        "root"
      } else {
        parent_row$Name[[1]]
      }
      sidebar_hierarchy_status(sprintf("Moved %s under %s.", result$node_name, target_label))
      showNotification(sprintf("Moved %s", result$node_name), type = "message")
    } else {
      sidebar_hierarchy_status(sprintf("%s is already under that parent.", result$node_name))
    }
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

  observeEvent(input$confirm_new_site_unit, {
    site_unit <- normalize_context_value(input$hierarchy_new_site_unit_name)

    result <- tryCatch(
      hierarchy_sidebar_create_site_unit(
        con = con,
        project_id = state$CurrProject,
        site_unit = site_unit
      ),
      error = function(e) e
    )

    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error")
      sidebar_hierarchy_status(conditionMessage(result))
      return()
    }

    removeModal()
    refresh_site_unit_scope()
    refresh_hierarchy_dropdown()
    refresh_su_table_page()
    picker_site_unit(result$site_unit)
    sidebar_hierarchy_site_unit(result$site_unit)
    state$PrefSUTable <- result$site_unit
    set_pref(con, "Current", "CurrPlotList", result$site_unit)

    if (isTRUE(result$changed)) {
      sync_touch_state(state)
      sidebar_hierarchy_status(sprintf("Created %s.", result$site_unit))
      showNotification(sprintf("Created %s", result$site_unit), type = "message")
    } else {
      sidebar_hierarchy_status(sprintf("%s already exists for this project.", result$site_unit))
      showNotification(sprintf("%s already exists", result$site_unit), type = "warning")
    }
  }, ignoreInit = TRUE)

  observeEvent(input$confirm_new_plot, {
    plot_number <- normalize_context_value(input$hierarchy_new_plot_number)
    site_unit <- normalize_context_value(current_sidebar_site_unit())

    if (!nzchar(site_unit)) {
      showNotification("Choose a site unit before adding a plot.", type = "warning")
      sidebar_hierarchy_status("Choose a site unit before adding a plot.")
      return()
    }

    result <- tryCatch(
      hierarchy_sidebar_create_plot(
        con = con,
        project_id = state$CurrProject,
        plot_number = plot_number,
        site_unit = site_unit
      ),
      error = function(e) e
    )

    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error")
      sidebar_hierarchy_status(conditionMessage(result))
      return()
    }

    removeModal()
    refresh_site_unit_scope()
    refresh_su_table_page()
    picker_site_unit(result$site_unit)
    sidebar_hierarchy_site_unit(result$site_unit)
    state$PrefSUTable <- result$site_unit
    set_pref(con, "Current", "CurrPlotList", result$site_unit)
    apply_plot_selection(
      plot_number = result$plot_number,
      project_id = result$project_id,
      site_unit = result$site_unit,
      persist = TRUE
    )
    sync_touch_state(state)
    sidebar_hierarchy_status(sprintf("Created plot %s in %s.", result$plot_number, result$site_unit))
    showNotification(sprintf("Created plot %s", result$plot_number), type = "message")
  }, ignoreInit = TRUE)

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
    sidebar_hierarchy_expanded(character(0))
    sidebar_hierarchy_node_id(NULL)
    sidebar_hierarchy_status("Selected root")
    sidebar_mode("hierarchy_nodes")
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
  
  # FS882 destination module
  mod_fs882_server("fs882", state, con)
  
  # FS1333 destination module
  mod_fs1333_server("fs1333", state, con)

  # Project Metadata destination module
  mod_project_metadata_server("project_metadata", state, con)
  mod_project_metadata_server("project_metadata_data", state, con)

  # Combine Species destination module (USysLumpMaster ribbon target)
  mod_combine_species_server("combine_species", state, con)

  # Herbarium destination module (frmHerbarium ribbon target)
  mod_herbarium_server("herbarium", state, con)

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

  # Auth Status Widget
  auth_status_nav_signal <- mod_auth_status_server("auth_status", state, con)
  observe({
    dest <- auth_status_nav_signal()
    if (!is.null(dest)) {
      bslib::nav_select("main_tabs", selected = dest, session = session)
      state$SyncFocusAuthRequest <- as.numeric(Sys.time())
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

  # Nav launchers: wire remaining Access-style menu entries to active modules/actions.
  mod_nav_launcher_server(
    "launch_project_new",
    open_main_tab = "Vegetation",
    click_id = "project-btn_new",
    run_notification = "Opened project creation action from sidebar controls."
  )
  mod_nav_launcher_server(
    "launch_project_save_as",
    open_main_tab = "Vegetation",
    click_id = "project-btn_save",
    run_notification = "Opened project save action from sidebar controls."
  )

  for (launcher_id in c(
    "launch_colour_theme",
    "launch_user_setup",
    "launch_reference_colour_theme",
    "launch_reference_user_setup"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Auth")
  }

  for (launcher_id in c(
    "launch_user_log",
    "launch_project_merge",
    "launch_reference_attach_species_table",
    "launch_reference_attach_code_list_table",
    "launch_reference_site_environment_codes",
    "launch_reference_species_name_codes",
    "launch_reference_directories",
    "launch_help_service_packs"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Administration")
  }

  for (launcher_id in c(
    "launch_project_export_splinter",
    "launch_project_metadata_export",
    "launch_export_to_r",
    "launch_export_to_turboveg",
    "launch_export_user_species_list"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Export")
  }

  for (launcher_id in c(
    "launch_project_metadata_import",
    "launch_import_vpro_64_project",
    "launch_import_venus_5_0",
    "launch_data_turboveg"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Import")
  }

  for (launcher_id in c(
    "launch_su_table_new",
    "launch_su_table_save_as",
    "launch_su_table_from_query",
    "launch_su_table_from_form_filter",
    "launch_su_table_from_environment",
    "launch_su_table_compare_assignments",
    "launch_su_table_list_units_with_plots",
    "launch_su_table_write_bec_master"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "SU Table")
  }

  for (launcher_id in c(
    "launch_hierarchy_new",
    "launch_hierarchy_save_as",
    "launch_hierarchy_merge",
    "launch_hierarchy_diagram"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Hierarchy")
  }

  for (launcher_id in c(
    "launch_project_compare",
    "launch_report_long_vegetation",
    "launch_report_summary_vegetation",
    "launch_report_long_environment",
    "launch_report_summary_environment",
    "launch_report_subzone_matrix_of_units",
    "launch_report_hierarchy_diagram",
    "launch_report_print_plot_label",
    "launch_report_create_plot_locations_file",
    "launch_report_show_plot_locations_google_earth"
  )) {
    mod_nav_launcher_server(launcher_id, open_main_tab = "Reports")
  }

  mod_nav_launcher_server(
    "launch_validate_data",
    open_main_tab = "Reports",
    open_nested_tab_id = "report-reporting_tabs",
    open_nested_value = "Diagnostics"
  )

  mod_nav_launcher_server(
    "launch_help_vpro_help",
    open_main_tab = "Reports",
    click_id = "btn_whatsnew",
    run_notification = "Opened What\'s New / help dialog."
  )
  mod_nav_launcher_server("launch_help_set_all_to_sample", open_main_tab = "Vegetation")
  mod_nav_launcher_server("launch_help_about_vpro", open_main_tab = "Auth")
}
