mod_sidebar_ui <- function(id) {
  ns <- NS(id)

  tagList(
    card(
      card_header("Data Sources"),
      selectizeInput(ns("cmbCurrProject"), "Project:", choices = NULL),
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

mod_sidebar_server <- function(id, con) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    # Combinaison of db attached in 01.state.R except project db
    actions <- c("Attach", "New", "Unattach")

    db_choices <- function() {
      proj_db <- setdiff(db_query(con, "SHOW databases;")$database_name, db_sys_dbs) |> sort()

      Filter(
        length,
        list(
          Actions = setNames(actions, actions),
          Sources = setNames(proj_db, proj_db)
        )
      )
    }

    update_selectors <- function() {
      proj_choices <- db_choices()
      updateSelectizeInput(
        session,
        "cmbCurrProject",
        choices = proj_choices,
        selected = config("Current", "CurrProject")
      )
      updateSelectizeInput(
        session,
        "cmbCurrHierarchy",
        choices = proj_choices,
        selected = config("Current", "CurrHierarchy")
      )
      # Handling None as NULL
      proj_choices$Actions <- c(proj_choices$Actions, "None" = "None")
      updateSelectizeInput(
        session,
        "cmbCurrSU",
        choices = proj_choices,
        selected = config("Current", "CurrPlotlist") %||% "None"
      )
    }

    update_selectors()

    # Select Case Me.cmbCurrProject
    #     Case "--------------------------------------"
    #     Case "Attach"
    #         AttachProject
    #     Case "Unattach"
    #         UnattachProject
    #     Case "New"
    #         CreateTableSet
    #         Me.cmbCurrHierarchy.SetFocus
    #         Me.cmbCurrProject.SetFocus
    #     Case Else
    #         LogProjectOut
    #         SetCurrentProject Me.cmbCurrProject
    #         UpdateDataForms
    #         LogProjectIn
    # End Select
    #     cmbCurrProject_GotFocus
    #     Me.cmbCurrProject = clsVProReg.CurrProject
    #     Me.cmbCurrSU = clsVProReg.CurrPlotlist

    observeEvent(
      input$cmbCurrProject,
      {
        # No change
        if (input$cmbCurrProject == config("Current", "CurrProject")) {
          return()
        }
        # Action selected
        if (input$cmbCurrProject %in% actions) {
          if (input$cmbCurrProject == "Attach") {
            # TODO: Write implementation
            AttachProject(con, session)
          } else if (input$cmbCurrProject == "Unattach") {
            # TODO: Write implementation
            UnattachProject(con, session)
          } else if (input$cmbCurrProject == "New") {
            # TODO: Write implementation
            CreateTableSet(con, session)
            # TODO: Write implementation
            # focus1
            # focus2
          }
          # Different project selected
        } else {
          LogProjectOut(con, session)
          # TODO: Write implementation
          SetCurrentProject(input$cmbCurrProject)
          # TODO: Write implementation
          UpdateDataForms(con, session)
          LogProjectIn(con, session)
        }
        # TODO: Write implementation
        # focus1
        updateSelectizeInput(session, "cmbCurrProject", selected = config("Current", "CurrProject"))
        updateSelectizeInput(session, "cmbCurrSU", selected = config("Current", "CurrPlotlist"))
      },
      ignoreInit = TRUE
    )

    observeEvent(input$cmbCurrSU, {}, ignoreInit = TRUE)
    observeEvent(input$cmbCurrHierarchy, {}, ignoreInit = TRUE)

    # Data Forms Navigation
    observeEvent(input$btnOpenFS882a, {
      config("Current", "DataFormName", "FS882-6x4XL")
      bslib::nav_select("main_tabs", selected = "fs882_6x4", session = root_session)
    })

    observeEvent(input$btnOpenFS882b, {
      config("Current", "DataFormName", "FS882-8x6XL")
      bslib::nav_select("main_tabs", selected = "fs882_8x6", session = root_session)
    })

    observeEvent(input$btnOpenSIVIForm, {
      bslib::nav_select("main_tabs", selected = "fs1333", session = root_session)
    })

    # Classification Navigation
    observeEvent(input$btnOpenSUForm, {
      global$sysStopCode <- FALSE
    })

    observeEvent(input$btnOpenSiteUnitTable, {})

    observeEvent(input$btnOpenHierarchyForm, {})

    invisible(NULL)
  })
}
