# Module: Project Management
# Sidebar UI: project switcher + Open/New/Save/Close buttons.

# Default data folder path used to pre-populate the Open dialog and auto-restore
.default_db_path <- function() {
  normalizePath(file.path(getwd(), "data", "vpro.duckdb"), mustWork = FALSE)
}

mod_project_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("project_switcher")),
    div(
      class = "d-flex gap-1 mb-1",
      actionButton(ns("btn_open"),  "Open",  class = "btn btn-sm btn-outline-primary flex-fill"),
      actionButton(ns("btn_new"),   "New",   class = "btn btn-sm btn-outline-success flex-fill"),
      actionButton(ns("btn_save"),  "Save",  class = "btn btn-sm btn-outline-secondary flex-fill")
    ),
    uiOutput(ns("close_ui"))
  )
}

mod_project_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive: last known file path (NULL = main db, no separate file)
    current_path <- reactiveVal(NULL)

    # Reactive: triggers downstream refresh (SU dropdown etc.)
    project_changed <- reactiveVal(0L)

    # ---- Startup: auto-restore project from main db ----
    observe({
      open_pids <- list_open_projects(con)
      if (length(open_pids) == 0) return()

      # If there's only one project, or the preferred project is in the db, activate it
      pref <- shiny::isolate(state$PrefProject)
      pid_to_activate <- if (!is.null(pref) && nzchar(pref %||% "") && pref %in% open_pids) {
        pref
      } else {
        open_pids[[1]]
      }

      set_project(state, pid_to_activate, con)
      
      # Restore preferred plot/SU after project activation (set_project clears it)
      pref_plot <- shiny::isolate(state$PrefPlot)
      if (!is.null(pref_plot) && nzchar(pref_plot %||% "")) {
        state$CurrSU <- pref_plot
        state$sysCurrSU <- pref_plot
      }
      
      project_changed(project_changed() + 1L)
    }) |> bindEvent(session$clientData$url_hostname, once = TRUE, ignoreNULL = FALSE)

    # ---- Project switcher (visible when multiple projects are open) ----
    output$project_switcher <- renderUI({
      open_pids <- list_open_projects(con)
      pid       <- state$CurrProject

      if (length(open_pids) <= 1) {
        # Single project: just show the label
        if (is.null(pid) || !nzchar(pid %||% "")) {
          div(class = "text-muted small mb-1", "No project open")
        } else {
          div(class = "fw-semibold small mb-1 text-primary", pid)
        }
      } else {
        # Multiple projects: show a dropdown to switch
        selectInput(
          ns("sel_active_project"),
          label = NULL,
          choices = open_pids,
          selected = pid %||% open_pids[[1]]
        )
      }
    })

    # Handle active project switch via the dropdown
    observeEvent(input$sel_active_project, {
      pid <- input$sel_active_project
      if (!is.null(pid) && nzchar(pid) && !identical(pid, isolate(state$CurrProject))) {
        set_project(state, pid, con)
        set_pref(con, "Current", "CurrProject", pid)
        project_changed(project_changed() + 1L)
      }
    })

    # ---- Close button (only when project open) ----
    output$close_ui <- renderUI({
      pid <- state$CurrProject
      if (!is.null(pid) && nzchar(pid %||% "")) {
        actionButton(ns("btn_close"), "Close project",
                     class = "btn btn-sm btn-outline-danger w-100 mb-1")
      }
    })

    # ---- Open ----
    observeEvent(input$btn_open, {
      default_path <- current_path() %||% .default_db_path()
      showModal(modalDialog(
        title = "Open Project File",
        textInput(ns("open_path"), "Project file path (.duckdb)", value = default_path),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("open_confirm"), "Open", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    # Internal: holds path pending project selection when file has multiple projects
    .pending_open_path <- reactiveVal(NULL)

    observeEvent(input$open_confirm, {
      path <- trimws(input$open_path %||% "")
      if (!nzchar(path)) {
        showNotification("File path is required.", type = "error")
        return()
      }
      if (!file.exists(path)) {
        showNotification(paste0("File not found: ", path), type = "error")
        return()
      }

      # Check if the file contains multiple projects before loading
      file_pids <- tryCatch(list_projects_in_file(path), error = function(e) character(0))

      if (length(file_pids) > 1) {
        # Multiple projects in file — ask which to activate
        .pending_open_path(path)
        removeModal()
        showModal(modalDialog(
          title = "Select Project to Activate",
          p(class = "text-muted small", paste0("File: ", path)),
          selectInput(ns("open_pick_pid"), "Project", choices = file_pids),
          footer = tagList(
            modalButton("Cancel"),
            actionButton(ns("open_pick_confirm"), "Activate", class = "btn-primary")
          ),
          easyClose = TRUE
        ))
      } else {
        # Single project (or unknown — let open_project detect)
        tryCatch({
          pid <- open_project(con, path)
          current_path(path)
          set_project(state, pid, con)
          set_pref(con, "Current", "CurrProject", pid)
          removeModal()
          project_changed(project_changed() + 1L)
          showNotification(paste0("Opened project: ", pid), type = "message")
        }, error = function(e) {
          showNotification(conditionMessage(e), type = "error")
        })
      }
    })

    # Confirm project selection after multi-project file open
    observeEvent(input$open_pick_confirm, {
      path <- .pending_open_path()
      pid  <- input$open_pick_pid
      if (is.null(path) || !nzchar(path %||% "")) {
        showNotification("No pending file path.", type = "error")
        return()
      }
      if (is.null(pid) || !nzchar(pid %||% "")) {
        showNotification("No project selected.", type = "error")
        return()
      }
      tryCatch({
        open_project(con, path)  # loads ALL projects from file into main db
        current_path(path)
        set_project(state, pid, con)
        set_pref(con, "Current", "CurrProject", pid)
        .pending_open_path(NULL)
        removeModal()
        project_changed(project_changed() + 1L)
        showNotification(paste0("Opened project: ", pid), type = "message")
      }, error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      })
    })

    # ---- New ----
    observeEvent(input$btn_new, {
      showModal(modalDialog(
        title = "New Project",
        textInput(ns("new_id"),    "Project ID (required)",    value = ""),
        textInput(ns("new_title"), "Project Title (required)", value = ""),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("new_confirm"), "Create", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$new_confirm, {
      pid   <- trimws(input$new_id    %||% "")
      title <- trimws(input$new_title %||% "")
      if (!nzchar(pid) || !nzchar(title)) {
        showNotification("Project ID and Title are both required.", type = "error")
        return()
      }
      tryCatch({
        new_project(con, pid, title)
        set_project(state, pid, con)
        set_pref(con, "Current", "CurrProject", pid)
        removeModal()
        project_changed(project_changed() + 1L)
        showNotification(paste0("Created project: ", pid), type = "message")
      }, error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      })
    })

    # ---- Save ----
    observeEvent(input$btn_save, {
      pid <- isolate(state$CurrProject)
      if (is.null(pid) || !nzchar(pid %||% "")) {
        showNotification("No project is currently open.", type = "warning")
        return()
      }
      showModal(modalDialog(
        title = "Save Project",
        textInput(ns("save_path"), "Save to file (.duckdb)", value = current_path() %||% ""),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("save_confirm"), "Save", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$save_confirm, {
      pid  <- isolate(state$CurrProject)
      path <- trimws(input$save_path %||% "")
      if (!nzchar(path)) {
        showNotification("File path is required.", type = "error")
        return()
      }
      tryCatch({
        save_project(con, pid, path)
        current_path(path)
        removeModal()
        showNotification(paste0("Saved project '", pid, "' to ", path), type = "message")
      }, error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      })
    })

    # ---- Close ----
    observeEvent(input$btn_close, {
      pid <- isolate(state$CurrProject)
      if (is.null(pid) || !nzchar(pid %||% "")) return()
      showModal(modalDialog(
        title = "Close Project",
        p(paste0("Close project '", pid, "'?")),
        if (!is.null(current_path()))
          p(class = "text-muted small", paste0("Will save to: ", current_path())),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("close_confirm"), "Close", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$close_confirm, {
      pid  <- isolate(state$CurrProject)
      path <- isolate(current_path())
      tryCatch({
        close_project(con, pid, path)
        state$CurrProject    <- NULL
        state$sysCurrProject <- NULL
        state$CurrSU         <- NULL
        state$sysCurrSU      <- NULL
        set_pref(con, "Current", "CurrProject", "")
        removeModal()
        project_changed(project_changed() + 1L)
        showNotification(paste0("Closed project '", pid, "'."), type = "message")
      }, error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      })
    })

    # ---- Auto-save on session end ----
    session$onSessionEnded(function() {
      pid  <- isolate(state$CurrProject)
      path <- isolate(current_path())
      if (!is.null(pid) && nzchar(pid %||% "") && !is.null(path) && nzchar(path %||% "")) {
        try(save_project(con, pid, path), silent = TRUE)
      }
    })

    # Return module exports
    list(
      project_changed = project_changed
    )
  })
}
