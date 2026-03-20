project_metadata_detect_table <- function(con) {
  candidates <- c(
    "Metadata",
    "VMetaData.Metadata",
    "VUser.ProjectMetaData",
    "VUser.ProjectMetadata",
    "ProjectMetadata",
    "USysProjectMetadata"
  )

  for (table_name in candidates) {
    ok <- tryCatch({
      DBI::dbGetQuery(con, paste("SELECT * FROM", table_name, "LIMIT 1"))
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      return(table_name)
    }
  }

  ""
}

project_metadata_list_choices <- function(con, list_name) {
  sql_candidates <- c(
    paste(
      "SELECT item, itemdescription",
      "FROM VLists.USysTableOfLists",
      "WHERE lower(listname) = lower(?)",
      "ORDER BY itemorder, item"
    ),
    paste(
      "SELECT item, itemdescription",
      "FROM USysTableOfLists",
      "WHERE lower(listname) = lower(?)",
      "ORDER BY itemorder, item"
    )
  )

  out <- data.frame(item = character(0), itemdescription = character(0), stringsAsFactors = FALSE)
  for (sql in sql_candidates) {
    out <- tryCatch(DBI::dbGetQuery(con, sql, list(list_name)), error = function(e) out)
    if (nrow(out) > 0) {
      break
    }
  }

  if (!nrow(out)) {
    return(character(0))
  }

  labels <- ifelse(
    is.na(out$itemdescription) | !nzchar(trimws(as.character(out$itemdescription))),
    out$item,
    paste0(out$item, " - ", out$itemdescription)
  )
  stats::setNames(as.character(out$item), labels)
}

project_metadata_default_table_of_lists <- function(con) {
  if (DBI::dbExistsTable(con, "VLists.USysTableOfLists")) {
    return("VLists.USysTableOfLists")
  }
  if (DBI::dbExistsTable(con, "USysTableOfLists")) {
    return("USysTableOfLists")
  }
  ""
}

project_metadata_default_all_specs <- function(con) {
  if (DBI::dbExistsTable(con, "VLists.USysAllSpecs")) {
    return("VLists.USysAllSpecs")
  }
  if (DBI::dbExistsTable(con, "USysAllSpecs")) {
    return("USysAllSpecs")
  }
  ""
}

mod_project_metadata_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
        shiny::tags$div(
          shiny::tags$div(class = "fw-semibold", "Project Metadata"),
          shiny::tags$div(class = "small text-muted", "Access parity block: frmProjectMetaData")
        ),
        shiny::actionButton(ns("btnClose"), "Close", class = "btn btn-outline-danger btn-sm")
      )
    ),
    bslib::card_body(
      bslib::layout_columns(
        shiny::selectizeInput(ns("ProjectID"), "Project ID", choices = character(0), selected = NULL),
        shiny::textInput(ns("ProjectTitle"), "Project Title"),
        shiny::numericInput(ns("StartDate"), "Start Date (Yr.)", value = "", min = 0, step = 1),
        shiny::textInput(ns("EndDate"), "End Date (Yr.)"),
        col_widths = c(3, 5, 2, 2)
      ),
      bslib::layout_columns(
        shiny::textInput(ns("CoordinatingAgency"), "Coordinating Agency"),
        shiny::textInput(ns("ProponentFunder"), "Proponent/Funder"),
        shiny::textInput(ns("FieldCompanyAgency"), "Field Company/Agency"),
        shiny::textInput(ns("GeographicStudyArea"), "Geographic Study Area"),
        col_widths = c(3, 3, 3, 3)
      ),
      bslib::layout_columns(
        shiny::selectInput(ns("cmbEcosysCollectionStandard"), "Collection Standard", choices = character(0)),
        shiny::selectInput(ns("cmbVegCoverMethod"), "Veg Cover Method", choices = character(0)),
        shiny::selectInput(ns("cmbPlotMethod"), "Plot Method/Size", choices = character(0)),
        shiny::selectInput(ns("cmbGeoRefMethod"), "Georeference Method", choices = character(0)),
        col_widths = c(3, 3, 3, 3)
      ),
      bslib::layout_columns(
        shiny::selectInput(ns("cmbDatum"), "Datum", choices = character(0)),
        shiny::selectInput(ns("cmbCoordinateSystem"), "Coordinate System", choices = character(0)),
        shiny::textInput(ns("AllSpecs"), "Species table"),
        shiny::textInput(ns("TableOfLists"), "Table Of Lists"),
        col_widths = c(3, 3, 3, 3)
      ),
      shiny::textAreaInput(ns("Notes"), "Notes", width = "100%", height = "90px"),
      shiny::tags$div(
        class = "d-flex align-items-center gap-2 flex-wrap",
        shiny::actionButton(ns("btnSave"), "Save", class = "btn btn-primary btn-sm"),
        shiny::actionButton(ns("btnAttachUSysAllSpecs"), "Attach USysAllSpecs", class = "btn btn-outline-secondary btn-sm"),
        shiny::actionButton(ns("btnAttachUSysTableOfLists"), "Attach USysTableOfLists", class = "btn btn-outline-secondary btn-sm"),
        shiny::textOutput(ns("status"), container = shiny::span)
      )
    )
  )
}

mod_project_metadata_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    table_name <- project_metadata_detect_table(con)
    status_text <- shiny::reactiveVal("")
    suppress_project_observer <- shiny::reactiveVal(FALSE)
    current_project_before_edit <- shiny::reactiveVal("")

    blank_numeric_value <- function(value) {
      if (is.null(value) || length(value) == 0 || is.na(value) || !is.finite(value)) {
        return("")
      }
      as.character(value)
    }

    normalize_text <- function(value) {
      value <- trimws(as.character(value %||% ""))
      if (!nzchar(value)) "" else value
    }

    load_project_choices <- function(selected = NULL) {
      if (!nzchar(table_name)) {
        shiny::updateSelectizeInput(session, "ProjectID", choices = character(0), selected = NULL, server = TRUE)
        return(invisible(NULL))
      }

      sql <- paste("SELECT DISTINCT projectid FROM", table_name, "WHERE projectid IS NOT NULL ORDER BY projectid")
      rows <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data.frame(projectid = character(0)))
      choices <- unique(as.character(rows$projectid %||% character(0)))
      choices <- choices[nzchar(choices)]

      shiny::updateSelectizeInput(
        session,
        "ProjectID",
        choices = choices,
        selected = if (!is.null(selected) && nzchar(selected)) selected else NULL,
        server = TRUE
      )
      invisible(NULL)
    }

    read_project_row <- function(project_id) {
      project_id <- normalize_text(project_id)
      if (!nzchar(table_name) || !nzchar(project_id)) {
        return(data.frame())
      }
      sql <- paste("SELECT * FROM", table_name, "WHERE projectid = ? LIMIT 1")
      tryCatch(DBI::dbGetQuery(con, sql, list(project_id)), error = function(e) data.frame())
    }

    write_project_row <- function(project_id, fields) {
      project_id <- normalize_text(project_id)
      if (!nzchar(table_name)) {
        return(list(ok = FALSE, reason = "No metadata table is available."))
      }
      if (!nzchar(project_id)) {
        return(list(ok = FALSE, reason = "Project ID is required."))
      }

      fields$projectid <- project_id
      fields$datelastedited <- as.character(Sys.time())
      fields$tableoflists <- normalize_text(fields$tableoflists)
      fields$allspecs <- normalize_text(fields$allspecs)
      if (!nzchar(fields$tableoflists)) {
        fields$tableoflists <- project_metadata_default_table_of_lists(con)
      }
      if (!nzchar(fields$allspecs)) {
        fields$allspecs <- project_metadata_default_all_specs(con)
      }

      existing <- read_project_row(project_id)
      available <- tryCatch(DBI::dbGetQuery(con, paste("SELECT * FROM", table_name, "LIMIT 0")), error = function(e) data.frame())
      available_cols <- names(available)
      if (length(available_cols) == 0) {
        return(list(ok = FALSE, reason = "Unable to read metadata schema."))
      }

      keep <- intersect(names(fields), available_cols)
      fields <- fields[keep]
      if (length(fields) == 0) {
        return(list(ok = FALSE, reason = "No writable fields available in metadata schema."))
      }

      if (nrow(existing) > 0) {
        set_clause <- paste(sprintf("%s = ?", names(fields)), collapse = ", ")
        sql <- paste("UPDATE", table_name, "SET", set_clause, "WHERE projectid = ?")
        DBI::dbExecute(con, sql, c(unname(fields), list(project_id)))
        return(list(ok = TRUE, reason = "Updated metadata record."))
      }

      col_names <- paste(names(fields), collapse = ", ")
      placeholders <- paste(rep("?", length(fields)), collapse = ", ")
      sql <- paste("INSERT INTO", table_name, "(", col_names, ") VALUES (", placeholders, ")")
      DBI::dbExecute(con, sql, unname(fields))
      list(ok = TRUE, reason = "Inserted metadata record.")
    }

    load_row_into_inputs <- function(project_id) {
      row <- read_project_row(project_id)
      if (!nrow(row)) {
        return(invisible(NULL))
      }

      names(row) <- tolower(names(row))
      getv <- function(col) {
        if (!col %in% names(row)) return("")
        value <- row[[col]][[1]]
        if (is.null(value) || length(value) == 0 || is.na(value)) "" else as.character(value)
      }

      shiny::updateTextInput(session, "ProjectTitle", value = getv("projecttitle"))
      shiny::updateNumericInput(session, "StartDate", value = blank_numeric_value(suppressWarnings(as.numeric(getv("startdate")))))
      shiny::updateTextInput(session, "EndDate", value = getv("enddate"))
      shiny::updateTextInput(session, "CoordinatingAgency", value = getv("coordinatingagency"))
      shiny::updateTextInput(session, "ProponentFunder", value = getv("proponentfunder"))
      shiny::updateTextInput(session, "FieldCompanyAgency", value = getv("fieldcompanyagency"))
      shiny::updateTextInput(session, "GeographicStudyArea", value = getv("geographicstudyarea"))
      shiny::updateSelectInput(session, "cmbEcosysCollectionStandard", selected = getv("ecosyscollectionstandard"))
      shiny::updateSelectInput(session, "cmbVegCoverMethod", selected = getv("vegcovermethod"))
      shiny::updateSelectInput(session, "cmbPlotMethod", selected = getv("plotmethod"))
      shiny::updateSelectInput(session, "cmbGeoRefMethod", selected = getv("georefmethod"))
      shiny::updateSelectInput(session, "cmbDatum", selected = getv("datum"))
      shiny::updateSelectInput(session, "cmbCoordinateSystem", selected = getv("coordinatesystem"))
      shiny::updateTextInput(session, "AllSpecs", value = getv("allspecs"))
      shiny::updateTextInput(session, "TableOfLists", value = getv("tableoflists"))
      shiny::updateTextAreaInput(session, "Notes", value = getv("notes"))
      invisible(NULL)
    }

    apply_standard_defaults <- function() {
      shiny::updateTextInput(session, "CoordinatingAgency", value = "MoF")
      shiny::updateTextInput(session, "ProponentFunder", value = "MoF")
      shiny::updateTextInput(session, "FieldCompanyAgency", value = "Forests, Lands and Natural Resources")
      shiny::updateTextInput(session, "GeographicStudyArea", value = "British Columbia")
      shiny::updateSelectInput(session, "cmbVegCoverMethod", selected = "Percent")
      shiny::updateSelectInput(session, "cmbPlotMethod", selected = "20x20")
      shiny::updateSelectInput(session, "cmbGeoRefMethod", selected = "GPS +/- 10m")
      shiny::updateSelectInput(session, "cmbDatum", selected = "NAD83")
      shiny::updateSelectInput(session, "cmbCoordinateSystem", selected = "dd.mm.ss.s")
      shiny::updateTextInput(session, "TableOfLists", value = project_metadata_default_table_of_lists(con))
      shiny::updateTextInput(session, "AllSpecs", value = project_metadata_default_all_specs(con))
      status_text("Collection standard defaults applied.")
    }

    output$status <- shiny::renderText(status_text())

    observe({
      shiny::updateSelectInput(session, "cmbEcosysCollectionStandard", choices = c("(None)" = "", project_metadata_list_choices(con, "EcosysCollectionStandard")))
      shiny::updateSelectInput(session, "cmbVegCoverMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "VegCoverMethod")))
      shiny::updateSelectInput(session, "cmbPlotMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "PlotMethod")))
      shiny::updateSelectInput(session, "cmbGeoRefMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "GeoreferenceMethod")))
      shiny::updateSelectInput(session, "cmbDatum", choices = c("(None)" = "", project_metadata_list_choices(con, "Datum")))
      shiny::updateSelectInput(session, "cmbCoordinateSystem", choices = c("(None)" = "", project_metadata_list_choices(con, "CoordSystem")))
    })

    observeEvent(TRUE, {
      if (!nzchar(table_name)) {
        status_text("Metadata table not found.")
        return()
      }

      state$CurrForm <- "frmProjectMetaData"
      state$sysCurrForm <- "frmProjectMetaData"
      set_current_setting("DataFormName", "frmProjectMetaData")

      default_project <- normalize_text(state$CurrProject %||% state$PrefProject)
      suppress_project_observer(TRUE)
      load_project_choices(selected = default_project)
      suppress_project_observer(FALSE)
      if (nzchar(default_project)) {
        current_project_before_edit(default_project)
        load_row_into_inputs(default_project)
      }
      status_text(sprintf("Loaded from %s", table_name))
    }, once = TRUE)

    observeEvent(input$ProjectID, {
      if (isTRUE(suppress_project_observer())) {
        return()
      }
      project_id <- normalize_text(input$ProjectID)
      if (!nzchar(project_id)) {
        return()
      }
      current_project_before_edit(project_id)
      load_row_into_inputs(project_id)
    }, ignoreInit = TRUE)

    observeEvent(input$cmbEcosysCollectionStandard, {
      value <- normalize_text(input$cmbEcosysCollectionStandard)
      if (!nzchar(value)) {
        return()
      }

      should_prompt <- startsWith(value, "DEIF") || startsWith(value, "DTE") || identical(value, "LMH25")
      if (!should_prompt) {
        return()
      }

      shiny::showModal(
        shiny::modalDialog(
          title = "VPro",
          "VPro can populate some of these fields based on the selected collection standard. Proceed?",
          footer = shiny::tagList(
            shiny::modalButton("No"),
            shiny::actionButton(session$ns("confirm_standard_defaults"), "Yes", class = "btn btn-primary")
          )
        )
      )
    }, ignoreInit = TRUE)

    observeEvent(input$confirm_standard_defaults, {
      shiny::removeModal()
      apply_standard_defaults()
    }, ignoreInit = TRUE)

    observeEvent(input$btnSave, {
      project_id <- normalize_text(input$ProjectID)
      fields <- list(
        projecttitle = normalize_text(input$ProjectTitle),
        startdate = suppressWarnings(as.integer(input$StartDate)),
        enddate = normalize_text(input$EndDate),
        coordinatingagency = normalize_text(input$CoordinatingAgency),
        proponentfunder = normalize_text(input$ProponentFunder),
        fieldcompanyagency = normalize_text(input$FieldCompanyAgency),
        geographicstudyarea = normalize_text(input$GeographicStudyArea),
        ecosyscollectionstandard = normalize_text(input$cmbEcosysCollectionStandard),
        vegcovermethod = normalize_text(input$cmbVegCoverMethod),
        plotmethod = normalize_text(input$cmbPlotMethod),
        georefmethod = normalize_text(input$cmbGeoRefMethod),
        datum = normalize_text(input$cmbDatum),
        coordinatesystem = normalize_text(input$cmbCoordinateSystem),
        allspecs = normalize_text(input$AllSpecs),
        tableoflists = normalize_text(input$TableOfLists),
        notes = normalize_text(input$Notes)
      )

      result <- write_project_row(project_id, fields)
      status_text(result$reason)
      if (isTRUE(result$ok)) {
        suppress_project_observer(TRUE)
        load_project_choices(selected = project_id)
        suppress_project_observer(FALSE)
      }
    })

    observeEvent(input$btnAttachUSysAllSpecs, {
      shiny::showNotification("Attach USysAllSpecs hookup deferred for this block.", type = "message")
      status_text("Attach USysAllSpecs hookup deferred.")
    })

    observeEvent(input$btnAttachUSysTableOfLists, {
      shiny::showNotification("Attach USysTableOfLists hookup deferred for this block.", type = "message")
      status_text("Attach USysTableOfLists hookup deferred.")
    })

    observeEvent(input$btnClose, {
      bslib::nav_select("main_tabs", "Vegetation", session = root_session)
    })
  })
}
