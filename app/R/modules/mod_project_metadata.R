project_metadata_detect_table <- function(con, project = NULL) {
  candidates <- c()

  # Highest priority: project-specific Metadata table (e.g. Sample_Metadata in Sample.db)
  if (!is.null(project) && nzchar(trimws(project))) {
    proj_tbl <- tryCatch(
      as.character(db_tb(con, "Metadata", project, prj = TRUE)),
      error = function(e) NULL
    )
    if (!is.null(proj_tbl)) candidates <- c(candidates, proj_tbl)
  }

  candidates <- c(
    candidates,
    "VMetaData.ProjectMetadata",
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

  # Helper: compact "collected" select + quality text per data type
  cg <- function(field_suffix, lbl) {
    shiny::tags$div(
      class = "text-center",
      shiny::tags$small(class = "fw-semibold d-block mb-1", lbl),
      shiny::selectInput(ns(paste0("Collected", field_suffix)), NULL,
        choices = c("\u2014" = "", "Complete" = 1, "Partial" = 2, "None" = 3),
        selected = "", width = "85px"
      ),
      shiny::textInput(ns(paste0("DataQuality", field_suffix)), NULL,
        placeholder = "Quality", width = "85px"
      )
    )
  }

  # Helper: labelled layer description row
  lr <- function(lbl, field, ph) {
    shiny::tags$div(
      class = "d-flex align-items-center gap-2 mb-1",
      shiny::tags$div(class = "fw-semibold text-muted text-end",
        style = "width:2.2rem; min-width:2.2rem; font-size:0.8rem;", lbl),
      shiny::textInput(ns(field), NULL, placeholder = ph, width = "100%")
    )
  }

  shiny::tags$div(
    class = "vpro-form-sm",
    # Navigation bar (Access frmProjectMetaData record nav bar parity)
    shiny::tags$div(
      class = "d-flex align-items-center gap-1 mb-1",
      shiny::actionButton(ns("btnMetaNavFirst"), NULL, icon = shiny::icon("backward-step"),
        class = "btn btn-outline-secondary btn-sm px-1"),
      shiny::actionButton(ns("btnMetaNavPrev"), NULL, icon = shiny::icon("caret-left"),
        class = "btn btn-outline-secondary btn-sm px-1"),
      shiny::tags$span(
        class = "small text-muted mx-1", style = "min-width: 56px; text-align: center;",
        shiny::textOutput(ns("navRecordPos"), inline = TRUE)
      ),
      shiny::actionButton(ns("btnMetaNavNext"), NULL, icon = shiny::icon("caret-right"),
        class = "btn btn-outline-secondary btn-sm px-1"),
      shiny::actionButton(ns("btnMetaNavLast"), NULL, icon = shiny::icon("forward-step"),
        class = "btn btn-outline-secondary btn-sm px-1"),
      shiny::tags$span(class = "vr mx-1"),
      shiny::tags$span(class = "small text-muted",
        shiny::textOutput(ns("status"), inline = TRUE))
    ),

    # === Main 2-column layout: fields (left) | DATA COLLECTED (right) ===
    bslib::layout_columns(
      col_widths = c(8, 4),
      gap = "0.6rem",

      # ----- LEFT: primary fields -----
      shiny::tagList(
        # Row: Project ID | BAPID.EP# | Start Date (Yr.) | End Date (Yr.)
        bslib::layout_columns(
          shiny::selectizeInput(ns("ProjectID"), "Project ID",
            choices = character(0), selected = NULL),
          shiny::textInput(ns("BAPID"), "BAPID.EP#"),
          shiny::numericInput(ns("StartDate"), "Start Date (Yr.)",
            value = NA, min = 0, step = 1),
          shiny::textInput(ns("EndDate"), "End Date (Yr.)"),
          col_widths = c(4, 4, 2, 2)
        ),
        # Row: Project Title
        shiny::textInput(ns("ProjectTitle"), "Project Title", width = "100%"),
        # Row: Project Type | Other
        bslib::layout_columns(
          shiny::selectInput(ns("cmbProjectType"), "Project Type",
            choices = c("(None)" = "", "BEC", "TEM", "SIBEC", "Other")),
          shiny::textInput(ns("ProjectTypeOther"), "Other"),
          col_widths = c(6, 6)
        ),
        # Row: Collection Standard | Other
        bslib::layout_columns(
          shiny::selectInput(ns("cmbEcosysCollectionStandard"),
            "Collection Standard", choices = character(0)),
          shiny::textInput(ns("EcosysCollectionStandardOther"), "Other"),
          col_widths = c(6, 6)
        ),
        # Row: Coordinating Agency | Proponent/Funder
        bslib::layout_columns(
          shiny::textInput(ns("CoordinatingAgency"), "Coordinating Agency"),
          shiny::textInput(ns("ProponentFunder"), "Proponent/Funder"),
          col_widths = c(6, 6)
        ),
        # Row: Field Company/Agency | Field Leader
        bslib::layout_columns(
          shiny::textInput(ns("FieldCompanyAgency"), "Field Company/Agency"),
          shiny::textInput(ns("FieldLeader"), "Field Leader"),
          col_widths = c(6, 6)
        ),
        # Row: Field Data Collection Team
        shiny::textInput(ns("FieldDataCollectionTeam"),
          "Field Data Collection Team", width = "100%"),
        # Row: Purpose of Project
        shiny::textInput(ns("ProjectPurpose"), "Purpose of Project",
          width = "100%"),
        # Row: Geographic Study Area | Region/District
        bslib::layout_columns(
          shiny::textInput(ns("GeographicStudyArea"), "Geographic Study Area"),
          shiny::textInput(ns("GeographicStudyRegion"), "Region/District"),
          col_widths = c(7, 5)
        ),
        # Row: No. of FS882 Plots | No. of Site Visits
        bslib::layout_columns(
          shiny::numericInput(ns("NumberOfFS882Plots"),
            "No. of Project FS882 Plots", value = NA),
          shiny::numericInput(ns("NumberOfSiteVisits"),
            "No. of Site Visits", value = NA),
          col_widths = c(6, 6)
        ),
        # Row: Veg Cover Method | Other
        bslib::layout_columns(
          shiny::selectInput(ns("cmbVegCoverMethod"), "Veg Cover Method",
            choices = character(0)),
          shiny::textInput(ns("VegCoverMethodOther"), "Other"),
          col_widths = c(6, 6)
        ),
        # Row: Plot Method/Size | Other
        bslib::layout_columns(
          shiny::selectInput(ns("cmbPlotMethod"), "Plot Method/Size",
            choices = character(0)),
          shiny::textInput(ns("PlotMethodOther"), "Other"),
          col_widths = c(6, 6)
        ),
        # Row: Mensuration Method | Other
        bslib::layout_columns(
          shiny::selectInput(ns("cmbMensurationMethod"), "Mensuration Method",
            choices = character(0)),
          shiny::textInput(ns("MensurationMethodOther"), "Other"),
          col_widths = c(6, 6)
        ),
        # Row: Extra Vegetation Field Description
        shiny::textInput(ns("ExtraVegFieldDescription"),
          "Extra Vegetation Field Description", width = "100%"),
        # Row: Data Custodian | Storage Location
        bslib::layout_columns(
          shiny::textInput(ns("DataCustodian"), "Data Custodian"),
          shiny::textInput(ns("StorageLocation"), "Storage Location"),
          col_widths = c(6, 6)
        ),
        # Row: Georeference Method | Coordinate System | Datum
        bslib::layout_columns(
          shiny::selectInput(ns("cmbGeoRefMethod"), "Georeference Method",
            choices = character(0)),
          shiny::selectInput(ns("cmbCoordinateSystem"), "Coordinate System",
            choices = character(0)),
          shiny::selectInput(ns("cmbDatum"), "Datum", choices = character(0)),
          col_widths = c(4, 4, 4)
        ),
        # Row: Species table | Table Of Lists (+ attach buttons)
        bslib::layout_columns(
          shiny::tags$div(
            shiny::textInput(ns("AllSpecs"), "Species table", width = "100%"),
            shiny::actionButton(ns("btnAttachUSysAllSpecs"), "...",
              class = "btn btn-outline-secondary btn-sm")
          ),
          shiny::tags$div(
            shiny::textInput(ns("TableOfLists"), "Table Of Lists",
              width = "100%"),
            shiny::actionButton(ns("btnAttachUSysTableOfLists"), "...",
              class = "btn btn-outline-secondary btn-sm")
          ),
          col_widths = c(6, 6)
        )
      ),

      # ----- RIGHT: FS882 DATA COLLECTED -----
      shiny::tags$div(
        shiny::tags$h6(class = "fw-semibold mb-2 text-uppercase small",
          "FS882 Data Collected"),
        shiny::tags$p(class = "text-muted small mb-2",
          "Select Complete / Partial / None per data type:"),
        shiny::tags$div(
          class = "d-flex flex-wrap gap-2",
          cg("Site", "Site"),
          cg("Veg", "Veg"),
          cg("Soil", "Soil"),
          cg("Terrain", "Terrain"),
          cg("Mens", "Mens."),
          cg("CWD", "CWD"),
          cg("WildTree", "Wld Tree"),
          cg("SoilChem", "Soil Chem"),
          cg("WildlifeHabitatAssessment", "WHA")
        ),
        shiny::tags$hr(class = "my-2"),
        shiny::tags$small(class = "fw-semibold d-block mb-1", "Other (describe):"),
        shiny::textInput(ns("CollectedCompleteOther"), NULL,
          placeholder = "Complete", width = "100%"),
        shiny::textInput(ns("CollectedPartialOther"), NULL,
          placeholder = "Partial", width = "100%"),
        shiny::textInput(ns("CollectedNoneOther"), NULL,
          placeholder = "None", width = "100%")
      )
    ),

    # === Layer Descriptions ===
    shiny::tags$hr(class = "my-2"),
    shiny::tags$h6(class = "fw-semibold mb-2", "Layer Descriptions"),
    bslib::layout_columns(
      col_widths = c(6, 6),
      shiny::tagList(
        lr("A1",  "CoverA1Description",  "Total of all tree layers (>10m)"),
        lr("A2",  "CoverA2Description",  "Dominant trees"),
        lr("A3",  "CoverA3Description",  "Main canopy"),
        lr("A",   "CoverADescription",   "Trees > 10m but below main canopy"),
        lr("B1",  "CoverB1Description",  "Total of all shrub layers"),
        lr("B2",  "CoverB2Description",  "Tall shrubs between 2 and 10 m tall"),
        lr("B3",  "CoverB2aDescription", "Low shrubs < 2 m tall"),
        lr("B4",  "CoverB2bDescription", ""),
        lr("B5",  "CoverB2cDescription", "")
      ),
      shiny::tagList(
        lr("B",   "CoverBDescription",   "Total of all shrub layers"),
        lr("C",   "CoverCDescription",   "Herbaceous species and dwarf shrubs"),
        lr("D",   "CoverDDescription",   "Mosses, lichens, liverworts and seedlings"),
        lr("Do",  "Cover8Description",   "Epixyls - species on downed wood"),
        lr("De",  "Cover9Description",   "Epiliths - species on rock"),
        lr("Ep",  "Cover10Description",  "Epiphytes - species on trees")
      )
    ),

    # === Notes ===
    shiny::textAreaInput(ns("Notes"), "Notes", width = "100%", height = "80px"),

    # === Footer: Save + status ===
    shiny::tags$div(
      class = "d-flex align-items-center gap-2 flex-wrap mt-2",
      shiny::actionButton(ns("btnSave"), "Save", class = "btn btn-primary btn-sm"),
      shiny::textOutput(ns("status2"), container = shiny::span)
    )
  )
}

mod_project_metadata_server <- function(id, state, con, open_trigger = NULL, plot_project_id = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    table_name <- project_metadata_detect_table(con, project = config("Current", "CurrProject"))
    status_text <- shiny::reactiveVal("")
    suppress_project_observer <- shiny::reactiveVal(FALSE)
    current_project_before_edit <- shiny::reactiveVal("")
    meta_recordset <- shiny::reactiveVal(character(0))
    meta_record_index <- shiny::reactiveVal(0L)

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

      # Ensure the current project appears in the list so it can be selected (new record case)
      if (!is.null(selected) && nzchar(selected) && !selected %in% choices) {
        choices <- sort(c(choices, selected))
      }

      # Update navigation recordset and set current index
      meta_recordset(choices)
      if (!is.null(selected) && nzchar(selected)) {
        idx <- match(selected, choices)
        meta_record_index(if (!is.na(idx)) idx else 0L)
      } else if (length(choices) > 0L) {
        meta_record_index(1L)
      } else {
        meta_record_index(0L)
      }

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
      getn <- function(col) {
        v <- suppressWarnings(as.numeric(getv(col)))
        if (is.na(v)) NA else v
      }

      # Primary fields
      shiny::updateTextInput(session, "BAPID", value = getv("bapid"))
      shiny::updateTextInput(session, "ProjectTitle", value = getv("projecttitle"))
      shiny::updateNumericInput(session, "StartDate", value = getn("startdate"))
      shiny::updateTextInput(session, "EndDate", value = getv("enddate"))
      shiny::updateSelectInput(session, "cmbProjectType", selected = getv("projecttype"))
      shiny::updateTextInput(session, "ProjectTypeOther", value = getv("projecttypeother"))
      shiny::updateSelectInput(session, "cmbEcosysCollectionStandard", selected = getv("ecosyscollectionstandard"))
      shiny::updateTextInput(session, "EcosysCollectionStandardOther", value = getv("ecoscollectionstandardother"))
      shiny::updateTextInput(session, "CoordinatingAgency", value = getv("coordinatingagency"))
      shiny::updateTextInput(session, "ProponentFunder", value = getv("proponentfunder"))
      shiny::updateTextInput(session, "FieldCompanyAgency", value = getv("fieldcompanyagency"))
      shiny::updateTextInput(session, "FieldLeader", value = getv("fieldleader"))
      shiny::updateTextInput(session, "FieldDataCollectionTeam", value = getv("fielddatacollectionteam"))
      shiny::updateTextInput(session, "ProjectPurpose", value = getv("projectpurpose"))
      shiny::updateTextInput(session, "GeographicStudyArea", value = getv("geographicstudyarea"))
      shiny::updateTextInput(session, "GeographicStudyRegion", value = getv("geographicstudyregion"))
      shiny::updateNumericInput(session, "NumberOfFS882Plots", value = getn("numberoffs882plots"))
      shiny::updateNumericInput(session, "NumberOfSiteVisits", value = getn("numberofsitevisits"))
      shiny::updateSelectInput(session, "cmbVegCoverMethod", selected = getv("vegcovermethod"))
      shiny::updateTextInput(session, "VegCoverMethodOther", value = getv("vegcovermethodother"))
      shiny::updateSelectInput(session, "cmbPlotMethod", selected = getv("plotmethod"))
      shiny::updateTextInput(session, "PlotMethodOther", value = getv("plotmethodother"))
      shiny::updateSelectInput(session, "cmbMensurationMethod", selected = getv("mensurationmethod"))
      shiny::updateTextInput(session, "MensurationMethodOther", value = getv("mensurationmethodother"))
      shiny::updateTextInput(session, "ExtraVegFieldDescription", value = getv("extravegfielddescription"))
      shiny::updateTextInput(session, "DataCustodian", value = getv("datacustodian"))
      shiny::updateTextInput(session, "StorageLocation", value = getv("storagelocation"))
      shiny::updateSelectInput(session, "cmbGeoRefMethod", selected = getv("georefmethod"))
      shiny::updateSelectInput(session, "cmbCoordinateSystem", selected = getv("coordinatesystem"))
      shiny::updateSelectInput(session, "cmbDatum", selected = getv("datum"))
      shiny::updateTextInput(session, "AllSpecs", value = getv("allspecs"))
      shiny::updateTextInput(session, "TableOfLists", value = getv("tableoflists"))
      shiny::updateTextAreaInput(session, "Notes", value = getv("notes"))

      # FS882 DATA COLLECTED
      for (suf in c("Site","Veg","Soil","Terrain","Mens","CWD","WildTree","SoilChem")) {
        shiny::updateSelectInput(session, paste0("Collected", suf),
          selected = getv(tolower(paste0("collected", suf))))
        shiny::updateTextInput(session, paste0("DataQuality", suf),
          value = getv(tolower(paste0("dataquality", suf))))
      }
      shiny::updateSelectInput(session, "CollectedWildlifeHabitatAssessment",
        selected = getv("collectedwildlifehabitatassessment"))
      shiny::updateTextInput(session, "DataQualityWildlifeHabitatAssessment",
        value = getv("dataqualitywildlifehabitatassessment"))
      shiny::updateTextInput(session, "CollectedCompleteOther", value = getv("collectedcompleteother"))
      shiny::updateTextInput(session, "CollectedPartialOther", value = getv("collectedpartialother"))
      shiny::updateTextInput(session, "CollectedNoneOther", value = getv("collectednoneother"))

      # Layer descriptions
      shiny::updateTextInput(session, "CoverA1Description", value = getv("covera1description"))
      shiny::updateTextInput(session, "CoverA2Description", value = getv("covera2description"))
      shiny::updateTextInput(session, "CoverA3Description", value = getv("covera3description"))
      shiny::updateTextInput(session, "CoverADescription",  value = getv("coveradescription"))
      shiny::updateTextInput(session, "CoverB1Description", value = getv("coverb1description"))
      shiny::updateTextInput(session, "CoverB2Description", value = getv("coverb2description"))
      shiny::updateTextInput(session, "CoverB2aDescription", value = getv("coverb2adescription"))
      shiny::updateTextInput(session, "CoverB2bDescription", value = getv("coverb2bdescription"))
      shiny::updateTextInput(session, "CoverB2cDescription", value = getv("coverb2cdescription"))
      shiny::updateTextInput(session, "CoverBDescription",  value = getv("covebdescription"))
      shiny::updateTextInput(session, "CoverCDescription",  value = getv("covercdescription"))
      shiny::updateTextInput(session, "CoverDDescription",  value = getv("coverddescription"))
      shiny::updateTextInput(session, "Cover8Description",  value = getv("cover8description"))
      shiny::updateTextInput(session, "Cover9Description",  value = getv("cover9description"))
      shiny::updateTextInput(session, "Cover10Description", value = getv("cover10description"))

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

    output$status  <- shiny::renderText(status_text())
    output$status2 <- shiny::renderText(status_text())

    observe({
      shiny::updateSelectInput(session, "cmbEcosysCollectionStandard", choices = c("(None)" = "", project_metadata_list_choices(con, "EcosysCollectionStandard")))
      shiny::updateSelectInput(session, "cmbVegCoverMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "VegCoverMethod")))
      shiny::updateSelectInput(session, "cmbPlotMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "PlotMethod")))
      shiny::updateSelectInput(session, "cmbGeoRefMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "GeoreferenceMethod")))
      shiny::updateSelectInput(session, "cmbDatum", choices = c("(None)" = "", project_metadata_list_choices(con, "Datum")))
      shiny::updateSelectInput(session, "cmbCoordinateSystem", choices = c("(None)" = "", project_metadata_list_choices(con, "CoordSystem")))
      shiny::updateSelectInput(session, "cmbMensurationMethod", choices = c("(None)" = "", project_metadata_list_choices(con, "MensurationMethod")))
    })

    # Use open_trigger if provided (fires when modal is opened) so update*Input
    # calls land on existing DOM nodes; fall back to TRUE for standalone usage.
    open_ev <- if (!is.null(open_trigger)) open_trigger else shiny::reactiveVal(1L)
    observeEvent(open_ev(), {
      if (!nzchar(table_name)) {
        status_text("Metadata table not found.")
        return()
      }

      state$CurrForm <- "frmProjectMetaData"
      state$sysCurrForm <- "frmProjectMetaData"
      config("Current", "DataFormName", "frmProjectMetaData")

      default_project <- if (!is.null(plot_project_id) && nzchar(plot_project_id())) {
        normalize_text(plot_project_id())
      } else {
        normalize_text(state$CurrProject %||% state$PrefProject)
      }
      suppress_project_observer(TRUE)
      load_project_choices(selected = default_project)
      suppress_project_observer(FALSE)
      if (nzchar(default_project)) {
        current_project_before_edit(default_project)
        load_row_into_inputs(default_project)
      }
      status_text(sprintf("Loaded from %s", table_name))
    }, ignoreInit = !is.null(open_trigger))

    observeEvent(input$ProjectID, {
      if (isTRUE(suppress_project_observer())) {
        return()
      }
      project_id <- normalize_text(input$ProjectID)
      if (!nzchar(project_id)) {
        return()
      }
      idx <- match(project_id, meta_recordset())
      if (!is.na(idx)) meta_record_index(idx)
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

      ni <- function(x) {
        v <- suppressWarnings(as.integer(x))
        if (is.null(v) || is.na(v)) NA_integer_ else v
      }
      nc <- function(x) {
        v <- suppressWarnings(as.integer(x))
        if (is.null(v) || is.na(v)) NA_integer_ else v
      }

      fields <- list(
        bapid = normalize_text(input$BAPID),
        projecttitle = normalize_text(input$ProjectTitle),
        startdate = ni(input$StartDate),
        enddate = normalize_text(input$EndDate),
        projecttype = normalize_text(input$cmbProjectType),
        projecttypeother = normalize_text(input$ProjectTypeOther),
        ecosyscollectionstandard = normalize_text(input$cmbEcosysCollectionStandard),
        ecoscollectionstandardother = normalize_text(input$EcosysCollectionStandardOther),
        coordinatingagency = normalize_text(input$CoordinatingAgency),
        proponentfunder = normalize_text(input$ProponentFunder),
        fieldcompanyagency = normalize_text(input$FieldCompanyAgency),
        fieldleader = normalize_text(input$FieldLeader),
        fielddatacollectionteam = normalize_text(input$FieldDataCollectionTeam),
        projectpurpose = normalize_text(input$ProjectPurpose),
        geographicstudyarea = normalize_text(input$GeographicStudyArea),
        geographicstudyregion = normalize_text(input$GeographicStudyRegion),
        numberoffs882plots = ni(input$NumberOfFS882Plots),
        numberofsitevisits = ni(input$NumberOfSiteVisits),
        vegcovermethod = normalize_text(input$cmbVegCoverMethod),
        vegcovermethodother = normalize_text(input$VegCoverMethodOther),
        plotmethod = normalize_text(input$cmbPlotMethod),
        plotmethodother = normalize_text(input$PlotMethodOther),
        mensurationmethod = normalize_text(input$cmbMensurationMethod),
        mensurationmethodother = normalize_text(input$MensurationMethodOther),
        extravegfielddescription = normalize_text(input$ExtraVegFieldDescription),
        datacustodian = normalize_text(input$DataCustodian),
        storagelocation = normalize_text(input$StorageLocation),
        georefmethod = normalize_text(input$cmbGeoRefMethod),
        coordinatesystem = normalize_text(input$cmbCoordinateSystem),
        datum = normalize_text(input$cmbDatum),
        allspecs = normalize_text(input$AllSpecs),
        tableoflists = normalize_text(input$TableOfLists),
        notes = normalize_text(input$Notes),
        # FS882 DATA COLLECTED
        collectedsite = nc(input$CollectedSite),
        collectedveg = nc(input$CollectedVeg),
        collectedsoil = nc(input$CollectedSoil),
        collectedterrain = nc(input$CollectedTerrain),
        collectedmens = nc(input$CollectedMens),
        collectedcwd = nc(input$CollectedCWD),
        collectedwildtree = nc(input$CollectedWildTree),
        collectedsoilchem = nc(input$CollectedSoilChem),
        collectedwildlifehabitatassessment = nc(input$CollectedWildlifeHabitatAssessment),
        dataqualitysite = normalize_text(input$DataQualitySite),
        dataqualityveg = normalize_text(input$DataQualityVeg),
        dataqualitysoil = normalize_text(input$DataQualitySoil),
        dataqualityterrain = normalize_text(input$DataQualityTerrain),
        dataqualitymens = normalize_text(input$DataQualityMens),
        dataqualitycwd = normalize_text(input$DataQualityCWD),
        dataqualitywildtree = normalize_text(input$DataQualityWildTree),
        dataqualitysoilchem = normalize_text(input$DataQualitySoilChem),
        dataqualitywildlifehabitatassessment = normalize_text(input$DataQualityWildlifeHabitatAssessment),
        collectedcompleteother = normalize_text(input$CollectedCompleteOther),
        collectedpartialother = normalize_text(input$CollectedPartialOther),
        collectednoneother = normalize_text(input$CollectedNoneOther),
        # Layer descriptions
        covera1description = normalize_text(input$CoverA1Description),
        covera2description = normalize_text(input$CoverA2Description),
        covera3description = normalize_text(input$CoverA3Description),
        coveradescription = normalize_text(input$CoverADescription),
        coverb1description = normalize_text(input$CoverB1Description),
        coverb2description = normalize_text(input$CoverB2Description),
        coverb2adescription = normalize_text(input$CoverB2aDescription),
        coverb2bdescription = normalize_text(input$CoverB2bDescription),
        coverb2cdescription = normalize_text(input$CoverB2cDescription),
        coverbdescription = normalize_text(input$CoverBDescription),
        covercdescription = normalize_text(input$CoverCDescription),
        coverddescription = normalize_text(input$CoverDDescription),
        cover8description = normalize_text(input$Cover8Description),
        cover9description = normalize_text(input$Cover9Description),
        cover10description = normalize_text(input$Cover10Description)
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

    # -- Record navigation (Access frmProjectMetaData nav bar parity) --
    meta_navigate_to <- function(project_id) {
      idx <- match(project_id, meta_recordset())
      if (!is.na(idx)) meta_record_index(idx)
      suppress_project_observer(TRUE)
      shiny::updateSelectizeInput(session, "ProjectID", selected = project_id)
      suppress_project_observer(FALSE)
      current_project_before_edit(project_id)
      load_row_into_inputs(project_id)
      status_text(sprintf("Record %d of %d", meta_record_index(), length(meta_recordset())))
    }

    observeEvent(input$btnMetaNavFirst, {
      rs <- meta_recordset()
      if (!length(rs)) return()
      meta_navigate_to(rs[1])
    })

    observeEvent(input$btnMetaNavPrev, {
      rs <- meta_recordset()
      idx <- meta_record_index()
      if (!length(rs) || idx <= 1L) return()
      meta_navigate_to(rs[idx - 1L])
    })

    observeEvent(input$btnMetaNavNext, {
      rs <- meta_recordset()
      idx <- meta_record_index()
      n <- length(rs)
      if (!n || idx >= n) return()
      meta_navigate_to(rs[idx + 1L])
    })

    observeEvent(input$btnMetaNavLast, {
      rs <- meta_recordset()
      if (!length(rs)) return()
      meta_navigate_to(rs[length(rs)])
    })

    output$navRecordPos <- shiny::renderText({
      idx <- meta_record_index()
      n <- length(meta_recordset())
      if (!n) "" else sprintf("%d of %d", idx, n)
    })
  })
}
