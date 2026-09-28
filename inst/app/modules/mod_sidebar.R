mod_sidebar_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$script(HTML(sprintf("$(document).on('hidden.bs.modal', '#shiny-modal', function() { if ($(this).find('.sidebar-project-dialog').length) Shiny.setInputValue('%sprojectModalClosed', Date.now(), {priority: 'event'}); });", ns("")))),
    card(
      card_header("Data Sources"),
      selectizeInput(ns("cmbCurrProject"), "Project:", choices = NULL),
      actionButton(ns("btnOpenProject"), "Open project", class = "btn btn-primary btn-sm"),
      actionButton(ns("btnNewProject"), "New project", class = "btn btn-sm"),
      actionButton(ns("btnCloseProject"), "Close inactive project", class = "btn btn-sm"),
      selectizeInput(ns("cmbCurrSU"), "Site Unit:", choices = NULL),
      selectizeInput(ns("cmbCurrHierarchy"), "Hierarchy:", choices = NULL)
    ),
    card(
      card_header("Data Forms"),
      actionButton(ns("btnOpenFS882a"), "Data Entry Forms", class = "btn btn-primary btn-sm"),
      actionButton(ns("btnOpenSIVIForm"), "SIVI Form", class = "btn btn-primary btn-sm")
    ),
    card(
      card_header("Classification"),
      actionButton(ns("btnOpenSUForm"), "Site Unit Tree View", class = "btn btn-primary btn-sm"),
      actionButton(ns("btnOpenSiteUnitTable"), "Site Unit Table", class = "btn btn-primary btn-sm"),
      actionButton(ns("btnOpenHierarchyForm"), "Hierarchy Tree View", class = "btn btn-primary btn-sm")
    )
  )
}

mod_sidebar_server <- function(id, context, state, user, fs882 = NULL) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()
    selected_file <- reactiveVal(NULL)
    selected_families <- reactiveVal(NULL)
    opening <- reactiveVal(FALSE)
    pending_switch <- reactiveVal(NULL)
    project_dialog <- reactiveVal(NULL)
    show_project_modal <- function(dialog, kind) {
      project_dialog(kind)
      showModal(shiny::tagAppendChild(dialog, div(class = "sidebar-project-dialog", style = "display: none;")))
    }
    close_project_dialog <- function() { project_dialog(NULL); removeModal() }
    observeEvent(input$cancelProjectDialog, {
      if (opening()) return()
      pending_switch(NULL)
      close_project_dialog()
      restore_picker()
    })
    restore_picker <- function() {
      updateSelectizeInput(session, "cmbCurrProject", selected = context$active$project)
    }
    source_identity <- function() list(project = context$active$project, path = context$active$path)
    source_matches <- function(source) identical(source, source_identity()) &&
      identical(state$CurrProject, source$project)
    can_request <- function() {
      if (opening()) return(FALSE)
      if (!is.null(pending_switch())) {
        restore_picker()
        return(FALSE)
      }
      if (!is.null(fs882) && isTRUE(fs882$status()$blocked)) {
        showNotification("Close the open dialog or delete confirmation before switching projects.", type = "warning")
        restore_picker()
        return(FALSE)
      }
      TRUE
    }
    finish_switch <- function(request) {
      if (!source_matches(request$source)) stop("Active project changed; retry the switch.")
      if (identical(request$kind, "picker")) {
        if (!request$project %in% names(context$projects)) stop("Project is no longer open.")
        switch_project(request$project)
      } else if (identical(request$kind, "open")) {
        if (!file.exists(request$file)) stop("Selected upload is no longer available.")
        vpro::vpro_project_open_file(context, request$file, request$project, file_name = request$file_name)
        switch_project(request$project)
      } else if (identical(request$kind, "new")) {
        if (request$project %in% names(context$projects)) stop("This project is already open.")
        path <- vpro::vpro_db_path(request$project, "projects")
        if (file.exists(path)) stop("A saved project with that name already exists; choose another name.")
        vpro::vpro_project_create(path, request$project, user)
        vpro::vpro_project_attach(context, path, request$project)
        switch_project(request$project)
      }
      pending_switch(NULL)
      close_project_dialog()
      refresh_projects()
      if (identical(request$kind, "open")) showNotification(paste("Opened", request$project), type = "message")
    }
    request_switch <- function(request) {
      if (!can_request()) return(invisible(FALSE))
      request$source <- source_identity()
      if (!identical(state$CurrProject, request$source$project)) {
        notify_error(simpleError("Active project changed; retry the switch."))
        restore_picker()
        return(invisible(FALSE))
      }
      if (!is.null(fs882) && isTRUE(fs882$status()$dirty)) {
        pending_switch(request)
        restore_picker()
        show_project_modal(modalDialog(
          title = "Unsaved changes", p("Save changes before switching projects?"),
          footer = tagList(actionButton(session$ns("switchSave"), "Save changes", class = "btn-primary"),
                           actionButton(session$ns("switchDiscard"), "Discard changes"),
                           actionButton(session$ns("switchStay"), "Stay")), easyClose = FALSE), "switch")
      } else {
        opening(TRUE)
        on.exit(opening(FALSE), add = TRUE)
        tryCatch(finish_switch(request), error = function(e) { notify_error(e); restore_picker() })
      }
      invisible(TRUE)
    }
    confirm_switch <- function(save) {
      request <- pending_switch()
      if (opening() || is.null(request)) return()
      opening(TRUE)
      on.exit(opening(FALSE), add = TRUE)
      tryCatch({
        if (!source_matches(request$source)) stop("Active project changed; retry the switch.")
        if (is.null(fs882)) stop("Editor unavailable; retry the switch.")
        if (save) {
          if (!isTRUE(fs882$save())) stop("Changes could not be saved; switch cancelled.")
        } else if (!isTRUE(fs882$discard())) stop("Changes could not be discarded; switch cancelled.")
        if (isTRUE(fs882$status()$dirty)) stop("Unsaved changes remain; switch cancelled.")
        finish_switch(request)
      }, error = function(e) { notify_error(e); restore_picker() })
    }
    observeEvent(input$switchSave, { confirm_switch(TRUE) })
    observeEvent(input$switchDiscard, { confirm_switch(FALSE) })
    observeEvent(input$switchStay, {
      if (is.null(pending_switch()) || opening()) return()
      pending_switch(NULL); close_project_dialog(); restore_picker()
    })

    refresh_projects <- function() {
      projects <- sort(names(context$projects))
      updateSelectizeInput(session, "cmbCurrProject", choices = projects, selected = context$active$project)
      updateSelectizeInput(session, "cmbCurrSU", choices = c("None", sort(names(context$sus))), selected = context$active_su$su %||% "None")
      updateSelectizeInput(session, "cmbCurrHierarchy", choices = c("None", sort(names(context$hierarchies))), selected = context$active_hierarchy$hierarchy %||% "None")
    }
    refresh_projects()

    notify_error <- function(error) {
      showNotification(conditionMessage(error), type = "error", duration = NULL)
    }
    switch_project <- function(project) {
      previous <- context$active$project
      if (identical(previous, project)) {
        return(invisible(NULL))
      }
      vpro::vpro_project_log_lifecycle(context, user, "Close")
      vpro::vpro_project_log_lifecycle(context, user, "Off")
      vpro::vpro_project_activate(context, project)
      state$CurrProject <- project
      state$PrefProject <- project
      state$PrefSUTable <- "None"
      if (!is.null(fs882)) fs882$reset()
      refresh_projects()
      for (event in c("On", "Open")) {
        tryCatch(vpro::vpro_project_log_lifecycle(context, user, event),
                 error = function(e) showNotification(
                   paste("Project activated, but lifecycle logging failed:", conditionMessage(e)),
                   type = "warning", duration = NULL))
      }
    }

    observeEvent(
      input$cmbCurrProject,
      {
        if (identical(input$cmbCurrProject, context$active$project)) {
          return()
        }
        if (!is.null(project_dialog())) {
          restore_picker()
          return()
        }
        request_switch(list(kind = "picker", project = input$cmbCurrProject))
      },
      ignoreInit = TRUE
    )

    observeEvent(input$btnOpenProject, {
      if (!can_request() || !is.null(project_dialog())) return()
      selected_file(NULL)
      selected_families(NULL)
      show_project_modal(modalDialog(
        title = "Open a VPRO project",
        p("Choose a VPRO database (.db) or older Access file (.mdb or .accdb). VPRO will keep your original unchanged and save a copy for you."),
        fileInput(session$ns("projectFile"), "Project file", accept = c(".db", ".sqlite", ".sqlite3", ".mdb", ".accdb")),
        uiOutput(session$ns("projectFamily")),
        footer = tagList(actionButton(session$ns("cancelProjectDialog"), "Cancel"), actionButton(session$ns("confirmOpen"), "Open project", class = "btn-primary")),
        easyClose = FALSE
      ), "open")
    })
    observeEvent(input$projectFile, {
      if (!identical(project_dialog(), "open")) return()
      selected_file(input$projectFile$datapath)
      selected_families(tryCatch(vpro::vpro_project_file_families(input$projectFile$datapath, input$projectFile$name), error = function(e) {
        notify_error(e)
        NULL
      }))
    })
    output$projectFamily <- renderUI({
      families <- selected_families()
      if (is.null(families)) {
        return(NULL)
      }
      if (!nrow(families)) {
        return(p("No VPRO project was found in this file."))
      }
      labels <- paste0(families$project, " (", ifelse(is.na(families$version), "unknown version", families$version), ifelse(families$compatible, ")", "; cannot open yet)"))
      selectInput(session$ns("projectName"), "Project in this file", choices = stats::setNames(families$project, labels))
    })
    observeEvent(input$confirmOpen, {
      if (!identical(project_dialog(), "open") || is.null(selected_file()) || is.null(input$projectName)) return()
      request_switch(list(kind = "open", project = input$projectName,
                          file = selected_file(), file_name = input$projectFile$name))
    })

    observeEvent(input$btnNewProject, {
      if (!can_request() || !is.null(project_dialog())) return()
      show_project_modal(modalDialog(
        title = "New project",
        textInput(session$ns("newProjectName"), "Project name"),
        p("Use letters, numbers, and underscores; begin with a letter."),
        footer = tagList(actionButton(session$ns("cancelProjectDialog"), "Cancel"), actionButton(session$ns("confirmNew"), "Create project", class = "btn-primary"))
      ), "new")
    })
    observeEvent(input$confirmNew, {
      if (!identical(project_dialog(), "new") || is.null(input$newProjectName)) return()
      request_switch(list(kind = "new", project = input$newProjectName))
    })
    observeEvent(input$btnCloseProject, {
      if (!can_request() || !is.null(project_dialog())) return()
      choices <- setdiff(names(context$projects), context$active$project)
      if (!length(choices)) {
        showNotification("Only the active project is open. Select another project before closing it.", type = "message")
      } else {
        show_project_modal(modalDialog(
          title = "Close a project",
          selectInput(session$ns("closeProjectName"), "Inactive project", choices = choices),
          p("Closing a project does not delete its saved database."),
          footer = tagList(actionButton(session$ns("cancelProjectDialog"), "Cancel"), actionButton(session$ns("confirmClose"), "Close project"))
        ), "close")
      }
    })
    observeEvent(input$confirmClose, {
      if (!identical(project_dialog(), "close")) return()
      tryCatch(
        {
          vpro::vpro_project_detach(context, input$closeProjectName)
          close_project_dialog()
          refresh_projects()
        },
        error = function(e) notify_error(e)
      )
    })

    observeEvent(input$btnOpenFS882a, {
      app_config_set("Current", "DataFormName", "FS882-6x4XL")
      bslib::nav_select("main_tabs", selected = "fs882_6x4", session = root_session)
    })
    observeEvent(input$btnOpenSIVIForm, {
      bslib::nav_select("main_tabs", selected = "fs1333", session = root_session)
    })
    observeEvent(input$btnOpenSUForm, {})
    observeEvent(input$btnOpenSiteUnitTable, {})
    observeEvent(input$btnOpenHierarchyForm, {})
    invisible(NULL)
  })
}
