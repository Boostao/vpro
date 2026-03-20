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
        shiny::selectizeInput(ns("ProjectID"), "Project ID", choices = character(0), selected = NULL),
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
      mod_fs882_6x4xl_ui(ns("fs882_inner"))
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

      sql <- "SELECT * FROM Env WHERE plotnumber = ? LIMIT 1"
      tryCatch(DBI::dbGetQuery(con, sql, list(plot_number)), error = function(e) data.frame())
    }

    env_has_column <- function(column_name) {
      out <- tryCatch(
        DBI::dbGetQuery(con, "PRAGMA table_info('Env')"),
        error = function(e) data.frame()
      )
      if (!nrow(out) || !"name" %in% names(out)) {
        return(FALSE)
      }
      tolower(column_name) %in% tolower(out$name)
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
      sql <- sprintf("UPDATE Env SET %s = ? WHERE plotnumber = ?", column_name)
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
      invisible(NULL)
    }

    load_current_context <- function() {
      state$CurrForm <- "frmSIVIsite"
      state$sysCurrForm <- "frmSIVIsite"
      set_current_setting("DataFormName", "frmSIVIsite")

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
      source_pref <- suppressWarnings(as.integer(get_current_setting("FS1333ProjectIdSource", default = "1")))
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
      set_current_setting("FS1333ProjectIdSource", as.character(source_mode))
      load_project_id_choices()
    }, ignoreInit = TRUE)

    observeEvent(list(state$CurrProject, state$CurrSU), {
      load_project_id_choices()
      load_current_context()
    }, ignoreInit = TRUE)

    observeEvent(input$ProjectID, {
      value <- normalize_text(input$ProjectID)
      if (!nzchar(value)) {
        return()
      }
      result <- update_env_column(state$CurrSU, "projectid", value)
      if (isTRUE(result$ok)) {
        status_text(sprintf("Project ID set to %s", value))
      } else {
        status_text(result$reason)
      }
    }, ignoreInit = TRUE)

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

    observeEvent(input$btnEditMetadata, {
      status_text("Metadata editor hookup deferred: use Data > Project Metadata.")
      shiny::showNotification("Metadata editor hookup deferred for this block.", type = "message")
    })

    observeEvent(input$btnClose2, {
      return_tab <- state$DataEntryReturnTab %||% "Vegetation"
      bslib::nav_select("main_tabs", return_tab, session = root_session)
    })

    mod_fs882_6x4xl_server("fs882_inner", state, con)
  })
}
