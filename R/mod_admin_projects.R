# =============================================================================
# mod_admin_projects.R — Project Metadata sub-module
# =============================================================================

mod_admin_projects_ui <- function(id) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(
      selectInput(ns("proj_select"), "Select Project", choices = NULL),
      actionButton(ns("proj_new"), "New Project", class = "btn-success w-100 mt-2"),
      div(class = "mt-4"),
      h5("Actions"),
      actionButton(ns("proj_del"), "Delete Selected", class = "btn-danger w-100")
    ),
    card(
      card_header(textOutput(ns("proj_form_header"))),
      card_body(
        textInput(ns("proj_id"), "Project ID (Unique Key)"),
        textInput(ns("proj_title"), "Project Title"),
        textInput(ns("proj_coord"), "Coordinating Agency"),
        layout_column_wrap(
          width = 1/2,
          textInput(ns("proj_start"), "Start Date (Text)"),
          textInput(ns("proj_end"), "End Date (Text)")
        ),
        textAreaInput(ns("proj_notes"), "Notes", rows = 5),
        div(class = "d-flex justify-content-end",
            actionButton(ns("proj_save"), "Save Project", class = "btn-primary btn-lg")
        )
      )
    )
  )
}

mod_admin_projects_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {

    require_permission <- function(permissions, message) {
      if (!auth_is_authenticated(state)) {
        showNotification("Sign in required.", type = "error")
        return(FALSE)
      }
      if (!any(vapply(permissions, function(p) auth_user_has_permission(state, p), logical(1)))) {
        showNotification(message, type = "error")
        return(FALSE)
      }
      TRUE
    }

    update_proj_list <- function(selected_id = NULL) {
      projs <- dbGetQuery(con, "SELECT projectid, projecttitle FROM USysProjectMetadata ORDER BY projectid")
      choices <- NULL
      if (nrow(projs) > 0) {
        choices <- setNames(projs$projectid, paste(projs$projectid, "-", projs$projecttitle))
      }
      updateSelectInput(session, "proj_select", choices = choices, selected = selected_id)
    }

    update_proj_list()

    observeEvent(input$proj_select, {
      req(input$proj_select)
      pid <- input$proj_select
      data <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(pid))
      if (nrow(data) > 0) {
        updateTextInput(session, "proj_id", value = data$projectid)
        shinyjs::disable("proj_id")
        updateTextInput(session, "proj_title", value = data$projecttitle)
        updateTextInput(session, "proj_coord", value = data$coordinatingagency)
        updateTextInput(session, "proj_start", value = data$startdate)
        updateTextInput(session, "proj_end", value = data$enddate)
        updateTextAreaInput(session, "proj_notes", value = data$notes)
        output$proj_form_header <- renderText(paste("Editing:", data$projecttitle))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$proj_new, {
      shinyjs::enable("proj_id")
      updateTextInput(session, "proj_id", value = "")
      updateTextInput(session, "proj_title", value = "")
      updateTextInput(session, "proj_coord", value = "")
      updateTextInput(session, "proj_start", value = "")
      updateTextInput(session, "proj_end", value = "")
      updateTextAreaInput(session, "proj_notes", value = "")
      output$proj_form_header <- renderText("New Project")
    })

    observeEvent(input$proj_save, {
      req(input$proj_id)
      if (!require_permission(c("write:all", "manage:projects"), "Permission required: manage projects")) return()
      exists   <- dbGetQuery(con, "SELECT 1 FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      existing <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      tryCatch({
        if (nrow(exists) > 0) {
          dbExecute(con,
            "UPDATE USysProjectMetadata SET projecttitle=?, coordinatingagency=?, startdate=?, enddate=?, notes=? WHERE projectid=?",
            list(input$proj_title, input$proj_coord, input$proj_start, input$proj_end, input$proj_notes, input$proj_id))
          if (nrow(existing) > 0) {
            new_row <- data.frame(
              projecttitle       = input$proj_title,
              coordinatingagency = input$proj_coord,
              startdate          = input$proj_start,
              enddate            = input$proj_end,
              notes              = input$proj_notes,
              stringsAsFactors   = FALSE
            )
            log_audit_diff(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata",
                           existing[1, , drop = FALSE], new_row,
                           fields = c("projecttitle", "coordinatingagency", "startdate", "enddate", "notes"))
          }
          showNotification("Project Updated", type = "message")
        } else {
          dbExecute(con,
            "INSERT INTO USysProjectMetadata (projectid, projecttitle, coordinatingagency, startdate, enddate, notes) VALUES (?, ?, ?, ?, ?, ?)",
            list(input$proj_id, input$proj_title, input$proj_coord, input$proj_start, input$proj_end, input$proj_notes))
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "projecttitle",       NA, input$proj_title)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "coordinatingagency", NA, input$proj_coord)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "startdate",          NA, input$proj_start)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "enddate",            NA, input$proj_end)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "notes",              NA, input$proj_notes)
          showNotification("Project Created", type = "message")
        }
        update_proj_list(selected_id = input$proj_id)
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
      })
    })

    observeEvent(input$proj_del, {
      req(input$proj_id)
      if (!require_permission(c("write:all", "manage:projects"), "Permission required: manage projects")) return()
      existing <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
      tryCatch({
        dbExecute(con, "DELETE FROM USysProjectMetadata WHERE projectid = ?", list(input$proj_id))
        if (nrow(existing) > 0) {
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "projecttitle",       existing$projecttitle[1],       NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "coordinatingagency", existing$coordinatingagency[1], NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "startdate",          existing$startdate[1],          NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "enddate",            existing$enddate[1],            NA)
          log_audit_change(con, input$proj_id, "Admin", input$proj_id, "USysProjectMetadata", "notes",              existing$notes[1],              NA)
        }
        showNotification("Project Deleted", type = "warning")
        updateTextInput(session, "proj_id", value = "")
        update_proj_list()
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
      })
    })
  })
}
