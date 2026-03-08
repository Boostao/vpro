# Module: Project Management
# Sidebar UI: label showing open project + Open/New/Save/Close buttons.

mod_project_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("project_label")),
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

    # Reactive: last known file path for this session
    current_path <- reactiveVal(NULL)

    # Reactive: triggers downstream refresh (SU dropdown etc.)
    project_changed <- reactiveVal(0L)

    # ---- Label ----
    output$project_label <- renderUI({
      pid <- isolate(state$CurrProject)
      if (is.null(pid) || !nzchar(pid %||% "")) {
        div(class = "text-muted small mb-1", "No project open")
      } else {
        div(class = "fw-semibold small mb-1 text-primary", pid)
      }
    })

    # Re-render label when project changes
    observe({
      state$CurrProject  # take dependency
      output$project_label <- renderUI({
        pid <- state$CurrProject
        if (is.null(pid) || !nzchar(pid %||% "")) {
          div(class = "text-muted small mb-1", "No project open")
        } else {
          div(class = "fw-semibold small mb-1 text-primary", pid)
        }
      })
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
      showModal(modalDialog(
        title = "Open Project",
        textInput(ns("open_path"), "Project file path (.duckdb)", value = current_path() %||% ""),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("open_confirm"), "Open", class = "btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$open_confirm, {
      path <- trimws(input$open_path %||% "")
      if (!nzchar(path)) {
        showNotification("File path is required.", type = "error")
        return()
      }
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
