mod_sidebar_ui <- function(id) {
  ns <- NS(id)
  tagList(
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
      actionButton(ns("btnOpenFS882b"), "2-Page Forms", class = "btn btn-primary btn-sm"),
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

mod_sidebar_server <- function(id, context, state, user) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()
    selected_file <- reactiveVal(NULL)
    selected_families <- reactiveVal(NULL)
    opening <- reactiveVal(FALSE)

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
      vpro::vpro_project_log_lifecycle(context, user, "On")
      vpro::vpro_project_log_lifecycle(context, user, "Open")
      refresh_projects()
    }

    observeEvent(
      input$cmbCurrProject,
      {
        if (identical(input$cmbCurrProject, context$active$project)) {
          return()
        }
        tryCatch(switch_project(input$cmbCurrProject), error = function(e) {
          notify_error(e)
          refresh_projects()
        })
      },
      ignoreInit = TRUE
    )

    observeEvent(input$btnOpenProject, {
      selected_file(NULL)
      selected_families(NULL)
      showModal(modalDialog(
        title = "Open a VPRO project",
        p("Choose a VPRO database (.db) or older Access file (.mdb or .accdb). VPRO will keep your original unchanged and save a copy for you."),
        fileInput(session$ns("projectFile"), "Project file", accept = c(".db", ".sqlite", ".sqlite3", ".mdb", ".accdb")),
        uiOutput(session$ns("projectFamily")),
        footer = tagList(modalButton("Cancel"), actionButton(session$ns("confirmOpen"), "Open project", class = "btn-primary")),
        easyClose = FALSE
      ))
    })
    observeEvent(input$projectFile, {
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
      req(selected_file(), input$projectName)
      if (opening()) {
        return()
      }
      opening(TRUE)
      on.exit(opening(FALSE), add = TRUE)
      tryCatch(
        {
          project <- input$projectName
          vpro::vpro_project_open_file(context, selected_file(), project, file_name = input$projectFile$name)
          switch_project(project)
          removeModal()
          showNotification(paste("Opened", project), type = "message")
        },
        error = function(e) notify_error(e)
      )
    })

    observeEvent(input$btnNewProject, {
      showModal(modalDialog(
        title = "New project",
        textInput(session$ns("newProjectName"), "Project name"),
        p("Use letters, numbers, and underscores; begin with a letter."),
        footer = tagList(modalButton("Cancel"), actionButton(session$ns("confirmNew"), "Create project", class = "btn-primary"))
      ))
    })
    observeEvent(input$confirmNew, {
      req(input$newProjectName)
      tryCatch(
        {
          project <- input$newProjectName
          if (project %in% names(context$projects)) {
            stop("This project is already open.")
          }
          path <- vpro::vpro_db_path(project, "projects")
          if (file.exists(path)) {
            stop("A saved project with that name already exists; choose another name.")
          }
          vpro::vpro_project_create(path, project, user)
          vpro::vpro_project_attach(context, path, project)
          switch_project(project)
          removeModal()
        },
        error = function(e) notify_error(e)
      )
    })
    observeEvent(input$btnCloseProject, {
      choices <- setdiff(names(context$projects), context$active$project)
      if (!length(choices)) {
        showNotification("Only the active project is open. Select another project before closing it.", type = "message")
      } else {
        showModal(modalDialog(
          title = "Close a project",
          selectInput(session$ns("closeProjectName"), "Inactive project", choices = choices),
          p("Closing a project does not delete its saved database."),
          footer = tagList(modalButton("Cancel"), actionButton(session$ns("confirmClose"), "Close project"))
        ))
      }
    })
    observeEvent(input$confirmClose, {
      tryCatch(
        {
          vpro::vpro_project_detach(context, input$closeProjectName)
          removeModal()
          refresh_projects()
        },
        error = function(e) notify_error(e)
      )
    })

    observeEvent(input$btnOpenFS882a, {
      app_config_set("Current", "DataFormName", "FS882-6x4XL")
      bslib::nav_select("main_tabs", selected = "fs882_6x4", session = root_session)
    })
    observeEvent(input$btnOpenFS882b, {
      app_config_set("Current", "DataFormName", "FS882-8x6XL")
      bslib::nav_select("main_tabs", selected = "fs882_8x6", session = root_session)
    })
    observeEvent(input$btnOpenSIVIForm, {
      bslib::nav_select("main_tabs", selected = "fs1333", session = root_session)
    })
    observeEvent(input$btnOpenSUForm, {
      global$sysStopCode <- FALSE
    })
    observeEvent(input$btnOpenSiteUnitTable, {})
    observeEvent(input$btnOpenHierarchyForm, {})
    invisible(NULL)
  })
}
