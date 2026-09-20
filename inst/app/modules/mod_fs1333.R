fs1333_plot_type_to_option <- function(value) {
  value <- trimws(as.character(value %||% ""))
  switch(tolower(value),
    "ground" = 1L,
    "visual" = 2L,
    "note" = 3L,
    "fs882" = 4L,
    "other" = 5L,
    NA_integer_
  )
}

fs1333_option_to_plot_type <- function(value) {
  value <- suppressWarnings(as.integer(value))
  switch(as.character(value %||% NA_integer_),
    "1" = "Ground",
    "2" = "Visual",
    "3" = "Note",
    "4" = "FS882",
    "5" = "Other",
    NA_character_
  )
}

fs1333_species_complete_to_option <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(NA_integer_)
  }
  if (isTRUE(value)) {
    return(1L)
  }
  if (identical(value, FALSE)) {
    return(2L)
  }
  NA_integer_
}

fs1333_option_to_species_complete <- function(value) {
  value <- suppressWarnings(as.integer(value))
  if (identical(value, 1L)) {
    return(TRUE)
  }
  if (identical(value, 2L)) {
    return(FALSE)
  }
  NA
}

mod_fs1333_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
        shiny::tags$div(
          shiny::tags$div(class = "fw-semibold", "SIVI (FS1333 Ecosystem Form)"),
          shiny::tags$div(class = "small text-muted", "Access frmSIVIsite context controls")
        ),
        shiny::actionButton(ns("btnClose2"), "Close", class = "btn btn-outline-danger btn-sm")
      )
    ),
    bslib::card_body(
      bslib::layout_columns(
        shiny::radioButtons(
          ns("optProjectID"),
          "Project ID Source",
          choices = c("Env" = "1", "Master" = "2"),
          selected = "1",
          inline = TRUE
        ),
        shiny::selectizeInput(
          ns("ProjectID"), "Project ID", choices = character(0), selected = NULL,
          options = list(create = TRUE, placeholder = "Select or type new...")
        ),
        shiny::selectInput(
          ns("optPlotType"),
          "Plot Type",
          choices = c("(None)" = "", "Ground" = "1", "Visual" = "2", "Note" = "3", "FS882" = "4", "Other" = "5"),
          selected = ""
        ),
        shiny::selectInput(
          ns("optSpeciesListComplete"),
          "Species List",
          choices = c("(None)" = "", "Comp." = "1", "Part." = "2"),
          selected = ""
        ),
        col_widths = c(4, 4, 2, 2)
      ),
      shiny::tags$div(
        class = "d-flex align-items-center gap-2 mb-3",
        shiny::actionButton(ns("btnEditMetadata"), "Edit Metadata", class = "btn btn-outline-primary btn-sm"),
        shiny::textOutput(ns("status"), container = shiny::span)
      ),
      shiny::tags$div(
        class = "small text-muted mb-2",
        "SIVI destination uses the existing FS882 data body while frmSIVIsite context/event semantics are ported in this block."
      ),
      mod_fs882_6x4_ui(ns("fs882_inner"))
    )
  )
}

mod_fs1333_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    root_session <- session$rootScope()

    project_id_source <- shiny::reactiveVal(1L)
    status_text <- shiny::reactiveVal("")

    normalize_text <- function(value) {
      value <- trimws(as.character(value %||% ""))
      if (!nzchar(value)) "" else value
    }

    get_env_record <- function(plot_number) {
      plot_number <- normalize_text(plot_number)
      if (!nzchar(plot_number)) {
        return(data.frame())
      }

      env_table_sql <- as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
      sql <- paste("SELECT * FROM", env_table_sql, "WHERE plotnumber = ? LIMIT 1")
      tryCatch(DBI::dbGetQuery(con, sql, list(plot_number)), error = function(e) data.frame())
    }

    env_has_column <- function(column_name) {
      env_table_id <- db_id("Env", config("Current", "CurrProject"), prj = TRUE)
      out <- tryCatch(DBI::dbListFields(con, env_table_id), error = function(e) character(0))
      if (!length(out)) {
        return(FALSE)
      }
      tolower(column_name) %in% tolower(out)
    }

    update_env_column <- function(plot_number, column_name, value) {
      plot_number <- normalize_text(plot_number)
      if (!nzchar(plot_number)) {
        return(list(ok = FALSE, reason = "No active plot selected."))
      }
      if (!env_has_column(column_name)) {
        return(list(ok = FALSE, reason = sprintf("Env column '%s' is not available in this schema.", column_name)))
      }

      # Column names are internal constants validated from PRAGMA table info above.
      env_table_sql <- as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
      sql <- sprintf("UPDATE %s SET %s = ? WHERE plotnumber = ?", env_table_sql, column_name)
      n_updated <- tryCatch(
        DBI::dbExecute(con, sql, list(value, plot_number)),
        error = function(e) 0L
      )
      if (identical(n_updated, 0L)) {
        return(list(ok = FALSE, reason = "No Env row was updated for the active plot."))
      }
      list(ok = TRUE, reason = "")
    }

    pick_existing_table <- function(candidates) {
      tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
      if (length(tables) == 0) {
        return("")
      }

      for (candidate in candidates) {
        hit <- tables[tolower(tables) == tolower(candidate)]
        if (length(hit) > 0) {
          return(hit[[1]])
        }
      }

      ""
    }

    load_project_id_choices <- function() {
      source_mode <- suppressWarnings(as.integer(input$optProjectID %||% project_id_source() %||% 1L))
      if (is.na(source_mode)) {
        source_mode <- 1L
      }

      data <- data.frame(projectid = character(0), projecttitle = character(0), stringsAsFactors = FALSE)

      if (identical(source_mode, 2L)) {
        sql_candidates <- c(
          "SELECT projectid, projecttitle FROM VLists.UsysMetadata",
          "SELECT projectid, projecttitle FROM UsysMetadata",
          "SELECT projectid, projecttitle FROM ProjectMetaData",
          "SELECT projectid, projecttitle FROM ProjectMetadata"
        )
        for (sql in sql_candidates) {
          data <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data)
          if (nrow(data) > 0) {
            break
          }
        }
      } else {
        current_project <- normalize_text(state$CurrProject %||% state$PrefProject)
        if (nzchar(current_project)) {
          table_name <- pick_existing_table(c(
            paste0(current_project, "_Metadata"),
            paste0(current_project, "_metadata")
          ))
          if (nzchar(table_name)) {
            quoted <- DBI::dbQuoteIdentifier(con, table_name)
            sql <- paste("SELECT projectid, projecttitle FROM", as.character(quoted))
            data <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data)
          }
        }
      }

      if (!nrow(data)) {
        shiny::updateSelectizeInput(session, "ProjectID", choices = character(0), selected = NULL, server = TRUE)
        return(invisible(NULL))
      }

      names(data) <- tolower(names(data))
      if (!all(c("projectid", "projecttitle") %in% names(data))) {
        shiny::updateSelectizeInput(session, "ProjectID", choices = character(0), selected = NULL, server = TRUE)
        return(invisible(NULL))
      }

      labels <- ifelse(
        is.na(data$projecttitle) | !nzchar(trimws(as.character(data$projecttitle))),
        data$projectid,
        paste0(data$projectid, " - ", data$projecttitle)
      )
      choices <- stats::setNames(as.character(data$projectid), labels)

      current_project_id <- normalize_text(input$ProjectID)
      selected <- if (nzchar(current_project_id) && current_project_id %in% unname(choices)) current_project_id else NULL
      shiny::updateSelectizeInput(session, "ProjectID", choices = choices, selected = selected, server = TRUE)
      known_project_ids(unname(choices))
      invisible(NULL)
    }

    load_current_context <- function() {
      state$CurrForm <- "frmSIVIsite"
      state$sysCurrForm <- "frmSIVIsite"
      config("Current", "DataFormName", "frmSIVIsite")

      plot_number <- normalize_text(state$CurrSU)
      if (!nzchar(plot_number)) {
        return(invisible(NULL))
      }

      env_row <- get_env_record(plot_number)
      if (!nrow(env_row)) {
        return(invisible(NULL))
      }

      env_names <- tolower(names(env_row))
      read_col <- function(col_name) {
        idx <- match(tolower(col_name), env_names)
        if (is.na(idx)) {
          return(NULL)
        }
        env_row[[idx]][[1]]
      }

      project_value <- normalize_text(read_col("projectid"))
      if (nzchar(project_value)) {
        shiny::updateSelectizeInput(session, "ProjectID", selected = project_value, server = TRUE)
      }

      plot_type_opt <- fs1333_plot_type_to_option(read_col("plottype"))
      shiny::updateSelectInput(session, "optPlotType", selected = if (is.na(plot_type_opt)) "" else as.character(plot_type_opt))

      spp_opt <- fs1333_species_complete_to_option(read_col("specieslistcomplete"))
      shiny::updateSelectInput(session, "optSpeciesListComplete", selected = if (is.na(spp_opt)) "" else as.character(spp_opt))
    }

    output$status <- shiny::renderText(status_text())

    # Form_Load parity: initialize source mode from remembered session value.
    observeEvent(TRUE, {
      source_pref <- suppressWarnings(as.integer((config("Current", "FS1333ProjectIdSource") %||% "1")))
      if (is.na(source_pref) || !(source_pref %in% c(1L, 2L))) {
        source_pref <- 1L
      }
      project_id_source(source_pref)
      shiny::updateRadioButtons(session, "optProjectID", selected = as.character(source_pref))
      load_project_id_choices()
      load_current_context()
    }, once = TRUE)

    observeEvent(input$optProjectID, {
      source_mode <- suppressWarnings(as.integer(input$optProjectID %||% "1"))
      if (is.na(source_mode) || !(source_mode %in% c(1L, 2L))) {
        source_mode <- 1L
      }
      project_id_source(source_mode)
      config("Current", "FS1333ProjectIdSource", as.character(source_mode))
      load_project_id_choices()
    }, ignoreInit = TRUE)

    observeEvent(list(state$CurrProject, state$CurrSU), {
      load_project_id_choices()
      load_current_context()
    }, ignoreInit = TRUE)

    # ProjectID AfterUpdate + NotInList is handled in the combined observer below (near end of module)

    observeEvent(input$optPlotType, {
      value <- fs1333_option_to_plot_type(input$optPlotType)
      result <- update_env_column(state$CurrSU, "plottype", value)
      if (isTRUE(result$ok)) {
        status_text("Plot type updated")
      } else {
        status_text(result$reason)
      }
    }, ignoreInit = TRUE)

    observeEvent(input$optSpeciesListComplete, {
      value <- fs1333_option_to_species_complete(input$optSpeciesListComplete)
      result <- update_env_column(state$CurrSU, "specieslistcomplete", value)
      if (isTRUE(result$ok)) {
        status_text("Species list status updated")
      } else {
        status_text(result$reason)
      }
    }, ignoreInit = TRUE)

    # ---- btnEditMetadata_Click parity (frmSIVIsite → frmProjectMetaData) ----
    # Opens metadata module, finds matching ProjectID row.
    # If no match, offers to create the metadata record from master or skeleton.
    open_metadata_for_project <- function(project_id) {
      project_id <- normalize_text(project_id)
      if (!nzchar(project_id)) {
        status_text("No Project ID selected.")
        return(invisible(NULL))
      }
      current_project <- normalize_text(state$CurrProject %||% config("Current", "CurrProject"))
      if (!nzchar(current_project)) {
        status_text("No project loaded.")
        return(invisible(NULL))
      }

      # Check if metadata record exists in project-local metadata table
      meta_table <- pick_existing_table(c(
        paste0(current_project, "_Metadata"),
        paste0(current_project, "_metadata")
      ))
      record_exists <- FALSE
      if (nzchar(meta_table)) {
        quoted <- as.character(DBI::dbQuoteIdentifier(con, meta_table))
        count <- tryCatch(
          DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", quoted, " WHERE ProjectID = ?"), list(project_id))$n,
          error = function(e) 0L
        )
        record_exists <- isTRUE(count > 0)
      }

      if (record_exists) {
        # Navigate to metadata tab with filter state
        state$MetadataFilterProjectID <- project_id
        bslib::nav_select("main_tabs", "metadata", session = root_session)
        status_text(sprintf("Opened metadata for '%s'.", project_id))
      } else {
        # Prompt to add — parity with Access MsgBox vbYesNo
        shiny::showModal(shiny::modalDialog(
          title = "VPro",
          shiny::tags$p(
            sprintf(
              "Meta data record does not exist for project ID %s.  Add?  To add a new meta data record with project ID %s click Yes.",
              project_id, project_id
            )
          ),
          footer = shiny::tagList(
            shiny::actionButton(ns("btnMetaAddYes"), "Yes", class = "btn btn-primary"),
            shiny::modalButton("No")
          ),
          easyClose = TRUE
        ))
      }
    }

    observeEvent(input$btnEditMetadata, {
      open_metadata_for_project(input$ProjectID)
    })

    # Handle "Yes" from the add-metadata confirmation dialog
    observeEvent(input$btnMetaAddYes, {
      shiny::removeModal()
      project_id <- normalize_text(input$ProjectID)
      current_project <- normalize_text(state$CurrProject %||% config("Current", "CurrProject"))
      if (!nzchar(project_id) || !nzchar(current_project)) {
        status_text("Cannot add metadata — missing project context.")
        return()
      }
      meta_table <- pick_existing_table(c(
        paste0(current_project, "_Metadata"),
        paste0(current_project, "_metadata")
      ))
      if (!nzchar(meta_table)) {
        status_text(sprintf("Metadata table for project '%s' not found.", current_project))
        return()
      }

      # Try to copy from master ProjectMetaData (VUser.db) first, else insert skeleton
      master_row <- tryCatch(
        DBI::dbGetQuery(con, "SELECT * FROM ProjectMetaData WHERE ProjectID = ?", list(project_id)),
        error = function(e) data.frame()
      )
      if (nrow(master_row) > 0) {
        # Copy full row from master into project-local metadata
        meta_cols <- tryCatch(DBI::dbListFields(con, meta_table), error = function(e) character(0))
        common_cols <- intersect(tolower(names(master_row)), tolower(meta_cols))
        if (length(common_cols) > 0) {
          insert_df <- master_row[, names(master_row)[tolower(names(master_row)) %in% common_cols], drop = FALSE]
          names(insert_df) <- meta_cols[match(tolower(names(insert_df)), tolower(meta_cols))]
          tryCatch(
            DBI::dbAppendTable(con, meta_table, insert_df),
            error = function(e) {
              status_text(paste("Error copying master metadata:", conditionMessage(e)))
            }
          )
        }
      } else {
        # Insert skeleton row with just ProjectID
        pid_col <- "ProjectID"
        meta_cols <- tryCatch(DBI::dbListFields(con, meta_table), error = function(e) character(0))
        pid_hit <- meta_cols[tolower(meta_cols) == "projectid"]
        if (length(pid_hit) > 0) pid_col <- pid_hit[[1]]
        insert_df <- data.frame(x = project_id, stringsAsFactors = FALSE)
        names(insert_df) <- pid_col
        tryCatch(
          DBI::dbAppendTable(con, meta_table, insert_df),
          error = function(e) {
            status_text(paste("Error inserting skeleton metadata:", conditionMessage(e)))
          }
        )
      }

      # Navigate to metadata
      state$MetadataFilterProjectID <- project_id
      bslib::nav_select("main_tabs", "metadata", session = root_session)
      status_text(sprintf("Created metadata record for '%s' and opened editor.", project_id))
    })

    # ---- ProjectID_NotInList parity ----
    # selectizeInput with create=TRUE allows free-text. When user types a new ID
    # that is not in the list, the AfterUpdate observer fires. If the value is not
    # in the known choices, trigger the edit-metadata flow (same as Access NotInList
    # calling btnEditMetadata_Click).
    known_project_ids <- shiny::reactiveVal(character(0))
    observeEvent(input$ProjectID, {
      value <- normalize_text(input$ProjectID)
      if (!nzchar(value)) return()
      known <- known_project_ids()
      if (length(known) > 0 && !(value %in% known)) {
        # New value not in list — Access NotInList parity
        open_metadata_for_project(value)
      }
      # Still update the env column regardless
      result <- update_env_column(state$CurrSU, "projectid", value)
      if (isTRUE(result$ok)) {
        status_text(sprintf("Project ID set to %s", value))
      } else {
        status_text(result$reason)
      }
    }, ignoreInit = TRUE)

    observeEvent(input$btnClose2, {
      return_tab <- state$DataEntryReturnTab %||% "Vegetation"
      bslib::nav_select("main_tabs", return_tab, session = root_session)
    })

    mod_fs882_6x4_server("fs882_inner", state, con)
  })
}
