# Module: Project Metadata Form

mod_project_meta_ui <- function(id) {
  ns <- NS(id)
  card(
    card_header("Project Metadata"),
    card_body(
      textInput(ns("project_title"), "Project Title"),
      textAreaInput(ns("project_desc"), "Description", rows = 4),
      textInput(ns("coordinator"), "Coordinator"),
      actionButton(ns("save_btn"), "Save Changes", class = "btn-primary")
    )
  )
}

mod_project_meta_server <- function(id, project_id, con) {
  moduleServer(id, function(input, output, session) {
    
    # Load Data
    observeEvent(project_id(), {
      req(project_id())
      pid <- project_id()
      
      # Mock column names based on assumptions or knowns
      # projectid, projecttitle
      # We assume Description is 'notes' or similar? USysProjectMetadata has 'notes'.
      # 'coordinatingagency'?
      
      entry <- dbGetQuery(con, "SELECT * FROM USysProjectMetadata WHERE projectid = ?", params = list(pid))
      
      if (nrow(entry) > 0) {
        updateTextInput(session, "project_title", value = entry$projecttitle)
        updateTextAreaInput(session, "project_desc", value = entry$notes)
        updateTextInput(session, "coordinator", value = entry$coordinatingagency)
      } else {
        # Clear or set defaults
        updateTextInput(session, "project_title", value = "")
        updateTextAreaInput(session, "project_desc", value = "")
        updateTextInput(session, "coordinator", value = "")
      }
    })
    
    # Save Data
    observeEvent(input$save_btn, {
      req(project_id())
      pid <- project_id()
      
      # Upsert Logic (DuckDB >= 0.9 supports ON CONFLICT)
      # Or check exists then update/insert
      exists <- dbGetQuery(con, "SELECT 1 FROM USysProjectMetadata WHERE projectid = ?", params = list(pid))
      
      if (nrow(exists) > 0) {
        sql <- "UPDATE USysProjectMetadata SET projecttitle = ?, notes = ?, coordinatingagency = ? WHERE projectid = ?"
        dbExecute(con, sql, params = list(input$project_title, input$project_desc, input$coordinator, pid))
      } else {
        # Insert
        sql <- "INSERT INTO USysProjectMetadata (projectid, projecttitle, notes, coordinatingagency) VALUES (?, ?, ?, ?)"
        dbExecute(con, sql, params = list(pid, input$project_title, input$project_desc, input$coordinator))
      }
      
      showNotification("Project metadata saved.", type = "message")
    })
    
  })
}
