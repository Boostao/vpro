library(shiny)
library(bslib)
library(DT)

mod_fs882_6x4_reimagined_ui <- function(id) {
  ns <- shiny::NS(id)

  section_card <- function(title, ...) {
    bslib::card(
      class = "mb-3",
      bslib::card_header(tags$strong(title)),
      bslib::card_body(...)
    )
  }

  tags$div(
    class = "container-fluid py-3 fs882-reimagined-ui",
    tags$head(
      tags$style(HTML(
        ".fs882-reimagined-ui .fs882-subform-shell { min-height: 16rem; }\n",
        ".fs882-reimagined-ui .fs882-note-shell { min-height: 8rem; }\n",
        ".fs882-reimagined-ui .shiny-input-container { margin-bottom: 0.75rem; }"
      ))
    ),

    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "d-flex flex-wrap align-items-center justify-content-between gap-2",
        tags$div(
          tags$h4(class = "mb-0", "ECOSYSTEM FIELD FORM (FS882)"),
          tags$small(class = "text-body-secondary", "UI prototype focused on Access-to-web transition")
        ),
        tags$div(
          class = "d-flex flex-wrap gap-2",
          shiny::actionButton(ns("btnSaveRecord"), "Save", class = "btn btn-primary"),
          shiny::actionButton(ns("btnG2MainMenu"), "Close", class = "btn btn-outline-secondary")
        )
      ),

      bslib::card_body(
        bslib::navset_card_tab(
          id = ns("tabPages"),

          bslib::nav_panel(
            "Site",
            section_card(
              "Record Context",
              bslib::layout_columns(
                shiny::selectInput(ns("ProjectID"), "Project ID", choices = character(0)),
                shiny::textInput(ns("StartDate"), "Yr."),
                shiny::textInput(ns("Date"), "Date"),
                shiny::textInput(ns("PlotNumber"), "Plot Number"),
                shiny::textInput(ns("FieldNumber"), "Field No."),
                shiny::textInput(ns("SiteSurveyor"), "Surveyor"),
                col_widths = c(2, 1, 2, 2, 2, 3)
              )
            ),

            section_card(
              "Unit Assignment",
              bslib::layout_columns(
                shiny::selectInput(ns("BECSiteUnit"), "BEC Master", choices = character(0)),
                shiny::selectInput(ns("UserSiteUnit"), "Working Unit", choices = character(0)),
                shiny::radioButtons(
                  ns("optAssignedSuSource"),
                  "Assigned SU Source",
                  choices = c("Env" = "1", "Master" = "2", "SU Tbl" = "3"),
                  inline = TRUE
                ),
                col_widths = c(4, 4, 4)
              ),
              tags$div(
                class = "d-flex flex-wrap gap-2",
                shiny::actionButton(ns("btnCopyToUserSU"), "Copy to Working Unit", class = "btn btn-outline-primary"),
                shiny::actionButton(ns("btnLoadMetadata"), "Edit Metadata", class = "btn btn-outline-primary")
              )
            ),

            section_card(
              "Location",
              bslib::layout_columns(
                shiny::textAreaInput(ns("Location"), "General Location", width = "100%", height = "90px"),
                shiny::selectInput(ns("FSRegionDistrict"), "Forest Region/Dist.", choices = character(0)),
                shiny::textInput(ns("NtsMapSheet"), "Map Sheet"),
                shiny::textInput(ns("UTMZone"), "UTM Zone"),
                shiny::textInput(ns("UTMEasting"), "Easting"),
                shiny::textInput(ns("UTMNorthing"), "Northing"),
                shiny::textInput(ns("LocationAccuracy"), "Accur. (m)"),
                col_widths = c(12, 3, 2, 1, 2, 2, 2)
              ),
              bslib::layout_columns(
                shiny::radioButtons(
                  ns("optCoordMethod2"),
                  "Coordinate Method",
                  choices = c("D.d" = "1", "DM.m" = "2", "DMS.s" = "3"),
                  inline = TRUE
                ),
                shiny::textInput(ns("AirPhotoNum"), "Air Photo No."),
                shiny::textInput(ns("XCoord"), "X Co-ord."),
                shiny::textInput(ns("YCoord"), "Y Co-ord."),
                col_widths = c(6, 2, 2, 2)
              ),
              bslib::layout_columns(
                shiny::textInput(ns("Latitude"), "Latitude"),
                shiny::textInput(ns("Longitude"), "Longitude"),
                shiny::textInput(ns("LatD"), "Lat D"),
                shiny::textInput(ns("LatM"), "Lat M"),
                shiny::textInput(ns("LatS"), "Lat S"),
                shiny::textInput(ns("LonD"), "Lon D"),
                shiny::textInput(ns("LonM"), "Lon M"),
                shiny::textInput(ns("LonS"), "Lon S"),
                col_widths = c(2, 2, 1, 1, 1, 1, 1, 1)
              )
            ),

            section_card(
              "Site Information",
              bslib::layout_columns(
                shiny::selectInput(ns("Ecosection"), "Ecosection", choices = character(0)),
                shiny::textInput(ns("PlotRepresenting"), "Plot Representing"),
                shiny::selectInput(ns("Zone"), "Biogeoclimatic Unit", choices = character(0)),
                shiny::selectInput(ns("SubZone"), "Subzone", choices = character(0)),
                shiny::selectInput(ns("SiteSeries"), "Site Series", choices = character(0)),
                shiny::selectInput(ns("RealmClass"), "Realm/Class", choices = character(0)),
                shiny::selectInput(ns("TransDistrib"), "Transition/Distrib.", choices = character(0)),
                shiny::textInput(ns("MapUnit"), "Map Unit"),
                col_widths = c(2, 3, 2, 1, 2, 2, 2, 2)
              ),
              bslib::layout_columns(
                shiny::selectInput(ns("MoistureRegime"), "Moisture Regime", choices = character(0)),
                shiny::selectInput(ns("NutrientRegime"), "Nutrient Regime", choices = character(0)),
                shiny::selectInput(ns("SuccessionalStatus"), "Successional Status", choices = character(0)),
                shiny::selectInput(ns("StructuralStage"), "Structural Stage", choices = character(0)),
                shiny::textInput(ns("StandAge"), "Stand Age"),
                col_widths = c(3, 3, 3, 2, 1)
              ),
              bslib::layout_columns(
                shiny::textInput(ns("Elevation"), "Elevation (m)"),
                shiny::textInput(ns("SlopeGradient"), "Slope (%)"),
                shiny::textInput(ns("Aspect"), "Aspect"),
                shiny::selectInput(ns("MesoSlopePosition"), "Meso Slope Pos.", choices = character(0)),
                shiny::selectInput(ns("SurfaceShape"), "Surface Shape", choices = character(0)),
                shiny::selectInput(ns("SurfaceTopographyType"), "Microtop. type", choices = character(0)),
                shiny::selectInput(ns("SurfaceTopographySize"), "Microtop. size", choices = character(0)),
                col_widths = c(2, 2, 1, 2, 2, 2, 1)
              )
            ),

            section_card(
              "Quality, Disturbance, Substrate, Notes",
              bslib::layout_columns(
                shiny::selectInput(ns("SitePlotQuality"), "Site Quality", choices = character(0)),
                shiny::selectInput(ns("VegPlotQuality"), "Veg Quality", choices = character(0)),
                shiny::selectInput(ns("SoilPlotQuality"), "Soil Quality", choices = character(0)),
                shiny::selectInput(ns("SiteDisturbance1"), "Site Disturbance 1", choices = character(0)),
                shiny::selectInput(ns("SiteDisturbance2"), "Site Disturbance 2", choices = character(0)),
                shiny::selectInput(ns("SiteDisturbance3"), "Site Disturbance 3", choices = character(0)),
                shiny::selectInput(ns("Exposure1"), "Exposure 1", choices = character(0)),
                shiny::selectInput(ns("Exposure2"), "Exposure 2", choices = character(0)),
                col_widths = c(2, 2, 2, 2, 1, 1, 1, 1)
              ),
              bslib::layout_columns(
                shiny::textInput(ns("SubstrateOrganicMatter"), "Org. Matter"),
                shiny::textInput(ns("SubstrateDecWood"), "Dec. Wood"),
                shiny::textInput(ns("SubstrateBedRock"), "Bedrock"),
                shiny::textInput(ns("SubstrateRocks"), "Rocks"),
                shiny::textInput(ns("SubstrateMineralSoil"), "Mineral Soil"),
                shiny::textInput(ns("SubstrateWater"), "Water"),
                col_widths = c(2, 2, 2, 2, 2, 2)
              ),
              bslib::layout_columns(
                tags$div(
                  class = "border rounded p-3 fs882-subform-shell",
                  tags$div(class = "fw-semibold mb-2", "SITE DIAGRAM/PICTURE"),
                  tags$small(class = "text-body-secondary", "Picture placeholder (`frmVPics` / `btnManagePictures`)"),
                  shiny::textInput(ns("Photo"), "Photo")
                ),
                tags$div(
                  class = "vstack gap-2",
                  shiny::textAreaInput(ns("SiteNotes"), "Field Notes", width = "100%", height = "140px"),
                  shiny::textAreaInput(ns("OfficeNotes"), "Office Notes", width = "100%", height = "110px")
                ),
                col_widths = c(4, 8)
              ),
              tags$div(
                class = "d-flex flex-wrap gap-2",
                shiny::actionButton(ns("btnManagePictures"), "Picture Manager", class = "btn btn-outline-primary"),
                shiny::actionButton(ns("btnGoogleEarth"), "Google Earth", class = "btn btn-outline-secondary"),
                shiny::actionButton(ns("btnPlotPicture"), "Plot Picture", class = "btn btn-outline-secondary")
              )
            )
          ),

          bslib::nav_panel(
            "Vegetation",
            section_card(
              "Vegetation Header",
              bslib::layout_columns(
                shiny::textInput(ns("VegPlotNumber"), "Plot"),
                shiny::textInput(ns("VegSurveyor"), "Surveyor"),
                shiny::textInput(ns("StrataCoverTree"), "Tree(A)"),
                shiny::textInput(ns("StrataCoverShrub"), "Shrub(B)"),
                shiny::textInput(ns("StrataCoverHerb"), "Herb(C)"),
                shiny::textInput(ns("StrataCoverMoss"), "Moss/Lichen(D)"),
                col_widths = c(2, 4, 1, 1, 1, 1)
              ),
              tags$div(
                class = "d-flex flex-wrap gap-2",
                shiny::actionButton(ns("btnFindPlot"), "Find Plot", class = "btn btn-outline-secondary"),
                shiny::actionButton(ns("btnAddVegRow"), "Add Species", class = "btn btn-outline-secondary"),
                shiny::actionButton(ns("btnDeleteVegRow"), "Delete Selected", class = "btn btn-outline-secondary"),
                shiny::actionButton(ns("btnSaveVeg"), "Save Vegetation", class = "btn btn-outline-primary"),
                shiny::actionButton(ns("btnAllowSmallEntry"), "Allow <0.1% Entry", class = "btn btn-outline-secondary"),
                shiny::actionButton(ns("btnCoverAndHeight"), "Cover & Height", class = "btn btn-outline-secondary")
              )
            ),
            bslib::layout_columns(
              section_card(
                "SubVegA",
                tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("SubVegA")))
              ),
              section_card(
                "SubVegC",
                tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("SubVegC")))
              ),
              section_card(
                "SubVegD",
                tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("SubVegD")))
              ),
              col_widths = c(5, 3, 4)
            ),
            section_card(
              "Notes",
              shiny::checkboxInput(ns("SpeciesListComplete"), "Spp. List Complete?", value = FALSE),
              shiny::textAreaInput(ns("VegNotes"), "NOTES", width = "100%", height = "140px")
            )
          ),

          bslib::nav_panel(
            "Veg Other",
            section_card(
              "USysVegOther",
              tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("USysVegOther"))),
              tags$div(
                class = "mt-2 text-body-secondary",
                tags$small("LL = Arboreal Lichen loading code | AF = Available Forage | DC = Distribution | UT = Utilization | VI = Vigour | PV/PG = Phenology | FFA = Fruit/Flower abundance")
              )
            )
          ),

          bslib::nav_panel(
            "Soil/Terrain",
            section_card(
              "Soil & Terrain Header",
              bslib::layout_columns(
                shiny::textInput(ns("MensPlotNumber"), "Plot"),
                shiny::textInput(ns("SoilSurveyor"), "Surveyor(s)"),
                shiny::selectInput(ns("BedrockGeology1"), "Bedrock Type", choices = character(0)),
                shiny::selectInput(ns("CoarseFragLith1"), "Coarse Frag. Lith.", choices = character(0)),
                shiny::selectInput(ns("SoilClassSubGroup"), "Soil subgroup", choices = character(0)),
                shiny::selectInput(ns("SoilClassGroup"), "Great group", choices = character(0)),
                shiny::selectInput(ns("HumusForm"), "Humus Form", choices = character(0)),
                shiny::selectInput(ns("HydroGeoSystem"), "System", choices = character(0)),
                shiny::selectInput(ns("HydroGeoSubSystem"), "Sub-system", choices = character(0)),
                col_widths = c(2, 3, 2, 2, 2, 2, 2, 2, 2)
              ),
              bslib::layout_columns(
                shiny::textInput(ns("RootingDepth"), "Rooting Depth (cm)"),
                shiny::selectInput(ns("RootRestrictingType"), "Root Restrict. Type", choices = character(0)),
                shiny::textInput(ns("RootRestrictingDepth"), "Root Restrict. Depth"),
                shiny::selectInput(ns("WaterSource"), "Water Source", choices = character(0)),
                shiny::textInput(ns("SeepageDepth"), "Seepage (cm)"),
                shiny::selectInput(ns("FloodingRegimeFreq"), "Flood Regime Frequency", choices = character(0)),
                shiny::selectInput(ns("FloodingRegimeDur"), "Flood Regime Duration", choices = character(0)),
                shiny::selectInput(ns("SoilDrainage"), "Drainage Class", choices = character(0)),
                col_widths = c(2, 2, 2, 2, 1, 2, 2, 2)
              )
            ),
            bslib::layout_columns(
              section_card(
                "ORGANIC HORIZONS/LAYERS (SoilHumus)",
                tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("SoilHumus")))
              ),
              section_card(
                "MINERAL HORIZONS/LAYERS (SoilMineral)",
                tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("SoilMineral")))
              ),
              col_widths = c(6, 6)
            ),
            section_card(
              "Notes",
              shiny::textAreaInput(ns("SoilNotes"), "NOTES", width = "100%", height = "120px")
            )
          ),

          bslib::nav_panel(
            "Other",
            section_card(
              "SubOther",
              bslib::layout_columns(
                shiny::textInput(ns("DataName"), "Data Name"),
                shiny::textInput(ns("DataItem"), "Data Item"),
                col_widths = c(6, 6)
              ),
              shiny::textAreaInput(ns("UserItem1"), "User Item1", width = "100%", height = "80px"),
              shiny::textAreaInput(ns("UserItem2"), "User Item2", width = "100%", height = "80px"),
              shiny::textAreaInput(ns("UserItem3"), "User Item3", width = "100%", height = "80px"),
              bslib::layout_columns(
                shiny::checkboxInput(ns("UserFlag1"), "User Flag 1", value = FALSE),
                shiny::checkboxInput(ns("UserFlag2"), "User Flag 2", value = FALSE),
                shiny::checkboxInput(ns("UserFlag3"), "User Flag 3", value = FALSE),
                col_widths = c(4, 4, 4)
              ),
              shiny::textInput(ns("Text287"), "Plot")
            )
          ),

          bslib::nav_panel(
            "Audit",
            section_card(
              "AUDIT",
              bslib::layout_columns(
                shiny::textInput(ns("MensWildPlotNumber"), "Plot"),
                shiny::radioButtons(
                  ns("optAuditStrength"),
                  "Audit Strength",
                  choices = c("Edit" = "1", "Edit & Add" = "2", "Edit, Add, & Delete" = "3"),
                  inline = TRUE
                ),
                col_widths = c(2, 10)
              ),
              tags$div(class = "fs882-subform-shell", DT::DTOutput(ns("USysAudit"))),
              shiny::actionButton(ns("btnRestoreSelectedChanges"), "Restore selected change(s)", class = "btn btn-outline-secondary")
            )
          )
        )
      ),

      bslib::card_footer(
        class = "d-flex flex-wrap gap-2 justify-content-between",
        tags$div(
          class = "d-flex flex-wrap gap-2",
          shiny::actionButton(ns("btnAudit"), "Audit", class = "btn btn-outline-secondary"),
          shiny::actionButton(ns("btnSuIntoEnv"), "SU Into Env", class = "btn btn-outline-secondary"),
          shiny::actionButton(ns("btnEnvIntoSu"), "Env Into SU", class = "btn btn-outline-secondary"),
          shiny::actionButton(ns("btnCreateSuFromFilter"), "Create SU From Form Filter", class = "btn btn-outline-secondary")
        ),
        shiny::actionButton(ns("btnVegProfiling"), "Plot Profiling", class = "btn btn-outline-secondary")
      )
    )
  )
}

if (!exists("open_fs882_destination_context", mode = "function")) {
  open_fs882_destination_context <- function(state,
                                             con,
                                             form_name = "FS882-6x4XL",
                                             close_forms = c("FS882-8x6XL", "FS882-1x1")) {
    curr_su <- shiny::isolate(state$CurrSU)
    pref_plot <- shiny::isolate(state$PrefPlot)

    state$CurrForm <- form_name
    state$sysCurrForm <- form_name
    state$DeferredCloseForms <- close_forms
    if ((is.null(curr_su) || !nzchar(trimws(as.character(curr_su)))) &&
        !is.null(pref_plot) && nzchar(trimws(as.character(pref_plot)))) {
      state$CurrSU <- pref_plot
      state$sysCurrSU <- pref_plot
    }
    config("Current", "DataFormName", form_name)
  }
}

fs882_reimagined_as_text <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) return("")
  as.character(value)
}

fs882_reimagined_as_num <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) return(NA_real_)
  text <- trimws(as.character(value))
  if (!nzchar(text)) return(NA_real_)
  suppressWarnings(as.numeric(text))
}

fs882_reimagined_list_tables <- function(con) {
  tryCatch({
    DBI::dbGetQuery(
      con,
      "SELECT schema_name, table_name FROM duckdb_tables() WHERE internal = FALSE"
    )
  }, error = function(e) {
    data.frame(schema_name = "main", table_name = DBI::dbListTables(con), stringsAsFactors = FALSE)
  })
}

fs882_reimagined_find_table <- function(con, candidates) {
  tables <- fs882_reimagined_list_tables(con)
  if (!nrow(tables)) return(NULL)

  table_names <- as.character(tables$table_name)
  schema_names <- as.character(tables$schema_name)
  full_names <- paste0(schema_names, ".", table_names)

  for (candidate in candidates) {
    if (!nzchar(candidate)) next
    idx <- match(tolower(candidate), tolower(full_names))
    if (!is.na(idx)) return(full_names[[idx]])

    idx2 <- match(tolower(candidate), tolower(table_names))
    if (!is.na(idx2)) return(full_names[[idx2]])
  }

  NULL
}

fs882_reimagined_quote_table <- function(con, table_name) {
  parts <- strsplit(table_name, "\\.")[[1]]
  pasted <- vapply(parts, function(part) as.character(DBI::dbQuoteIdentifier(con, part)), character(1))
  paste(pasted, collapse = ".")
}

fs882_reimagined_table_fields <- function(con, table_name) {
  tryCatch(DBI::dbListFields(con, table_name), error = function(e) character(0))
}

fs882_reimagined_col <- function(fields, target_name) {
  if (!length(fields)) return(NULL)
  idx <- match(tolower(target_name), tolower(fields))
  if (is.na(idx)) return(NULL)
  fields[[idx]]
}

fs882_reimagined_list_choices <- function(con, list_name) {
  sql <- paste(
    "SELECT item, itemdescription",
    "FROM VLists.USysTableOfLists",
    "WHERE lower(listname) = lower(?)",
    "ORDER BY itemorder, item"
  )
  rows <- tryCatch(DBI::dbGetQuery(con, sql, list(list_name)), error = function(e) data.frame())
  if (!nrow(rows)) return(character(0))
  labels <- ifelse(
    is.na(rows$itemdescription) | !nzchar(trimws(as.character(rows$itemdescription))),
    rows$item,
    paste0(rows$item, " - ", rows$itemdescription)
  )
  stats::setNames(as.character(rows$item), labels)
}

fs882_reimagined_empty_df <- function(title = "No records") {
  data.frame(Message = title, stringsAsFactors = FALSE)
}

fs882_reimagined_read_plot_rows <- function(con, table_name, plot_id, order_col_candidates = character(0)) {
  if (is.null(table_name) || !nzchar(table_name)) return(data.frame())

  fields <- fs882_reimagined_table_fields(con, table_name)
  if (!length(fields)) return(data.frame())
  plot_col <- fs882_reimagined_col(fields, "plotnumber")
  if (is.null(plot_col) || !nzchar(trimws(as.character(plot_id)))) return(data.frame())

  q_table <- fs882_reimagined_quote_table(con, table_name)
  q_plot_col <- as.character(DBI::dbQuoteIdentifier(con, plot_col))

  order_cols <- vapply(
    order_col_candidates,
    function(candidate) fs882_reimagined_col(fields, candidate),
    character(1)
  )
  order_cols <- order_cols[nzchar(order_cols)]
  order_clause <- ""
  if (length(order_cols)) {
    quoted <- vapply(order_cols, function(col) as.character(DBI::dbQuoteIdentifier(con, col)), character(1))
    order_clause <- paste(" ORDER BY", paste(quoted, collapse = ", "))
  }

  sql <- paste0("SELECT * FROM ", q_table, " WHERE ", q_plot_col, " = ?", order_clause)
  tryCatch(DBI::dbGetQuery(con, sql, list(plot_id)), error = function(e) data.frame())
}

fs882_reimagined_upsert_env <- function(con, table_name, field_values) {
  if (is.null(table_name) || !nzchar(table_name)) return(FALSE)

  fields <- fs882_reimagined_table_fields(con, table_name)
  if (!length(fields)) return(FALSE)

  plot_col <- fs882_reimagined_col(fields, "plotnumber")
  if (is.null(plot_col)) return(FALSE)

  present_names <- names(field_values)
  actual_cols <- vapply(present_names, function(nm) fs882_reimagined_col(fields, nm), character(1))
  keep <- nzchar(actual_cols)
  present_names <- present_names[keep]
  actual_cols <- actual_cols[keep]

  plot_idx <- match(tolower("plotnumber"), tolower(present_names))
  if (is.na(plot_idx)) return(FALSE)

  q_table <- fs882_reimagined_quote_table(con, table_name)
  q_plot_col <- as.character(DBI::dbQuoteIdentifier(con, plot_col))
  plot_value <- field_values[[present_names[[plot_idx]]]]

  set_idx <- setdiff(seq_along(actual_cols), plot_idx)
  if (length(set_idx)) {
    assignments <- vapply(
      actual_cols[set_idx],
      function(col) paste0(as.character(DBI::dbQuoteIdentifier(con, col)), " = ?"),
      character(1)
    )
    update_sql <- paste0(
      "UPDATE ", q_table, " SET ", paste(assignments, collapse = ", "),
      " WHERE ", q_plot_col, " = ?"
    )
    update_params <- c(unname(field_values[present_names[set_idx]]), list(plot_value))
    n_updated <- tryCatch(DBI::dbExecute(con, update_sql, update_params), error = function(e) 0L)
    if (!is.na(n_updated) && n_updated > 0) return(TRUE)
  }

  insert_cols <- actual_cols
  insert_vals <- unname(field_values[present_names])
  placeholders <- paste(rep("?", length(insert_cols)), collapse = ", ")
  q_insert_cols <- vapply(insert_cols, function(col) as.character(DBI::dbQuoteIdentifier(con, col)), character(1))
  insert_sql <- paste0(
    "INSERT INTO ", q_table, " (", paste(q_insert_cols, collapse = ", "), ") ",
    "VALUES (", placeholders, ")"
  )

  ok <- tryCatch({
    DBI::dbExecute(con, insert_sql, insert_vals)
    TRUE
  }, error = function(e) FALSE)

  ok
}

mod_fs882_6x4_reimagined_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    rv <- shiny::reactiveValues(
      current_plot = NULL,
      veg_a = data.frame(),
      veg_c = data.frame(),
      veg_d = data.frame(),
      humus = data.frame(),
      mineral = data.frame(),
      audit = data.frame(),
      veg_other = data.frame()
    )

    env_table <- fs882_reimagined_find_table(con, c("main.Env", "Env"))
    veg_table <- fs882_reimagined_find_table(con, c("main.Veg", "Veg"))
    humus_table <- fs882_reimagined_find_table(con, c("main.Humus", "Humus"))
    mineral_table <- fs882_reimagined_find_table(con, c("main.Mineral", "Mineral"))
    audit_table <- fs882_reimagined_find_table(con, c("main.USysAudit", "USysAudit", "main.AuditTrail", "AuditTrail"))
    veg_other_table <- fs882_reimagined_find_table(con, c("main.USysVegOther", "USysVegOther", "main.VegOther", "VegOther"))

    current_plot_from_state <- shiny::reactive({
      state_plot <- trimws(as.character(state$CurrSU %||% ""))
      pref_plot <- trimws(as.character(state$PrefPlot %||% ""))

      candidates <- c(state_plot, pref_plot)
      candidates <- candidates[nzchar(candidates)]
      if (!length(candidates)) return(NULL)
      candidates[[1]]
    })

    observe({
      open_fs882_destination_context(
        state = state,
        con = con,
        form_name = "FS882-6x4XL",
        close_forms = c("FS882-8x6XL", "FS882-1x1")
      )
    })

    observe({
      shiny::updateSelectInput(session, "MesoSlopePosition", choices = fs882_reimagined_list_choices(con, "MesoSlopePosition"))
      shiny::updateSelectInput(session, "SurfaceShape", choices = fs882_reimagined_list_choices(con, "SurfaceShape"))
      shiny::updateSelectInput(session, "MoistureRegime", choices = fs882_reimagined_list_choices(con, "MoistureRegime"))
      shiny::updateSelectInput(session, "NutrientRegime", choices = fs882_reimagined_list_choices(con, "NutrientRegime"))
    })

    load_plot_header <- function(plot_id) {
      if (is.null(env_table) || !nzchar(plot_id)) return(invisible(NULL))

      env_rows <- fs882_reimagined_read_plot_rows(
        con,
        env_table,
        plot_id,
        order_col_candidates = c("plotnumber")
      )

      if (!nrow(env_rows)) {
        shiny::updateTextInput(session, "PlotNumber", value = plot_id)
        return(invisible(NULL))
      }

      row <- env_rows[1, , drop = FALSE]
      fields <- names(row)
      col <- function(target) {
        nm <- fs882_reimagined_col(fields, target)
        if (is.null(nm)) return(NA)
        row[[nm]][[1]]
      }

      shiny::updateTextInput(session, "ProjectID", value = fs882_reimagined_as_text(col("projectid")))
      shiny::updateTextInput(session, "PlotNumber", value = fs882_reimagined_as_text(col("plotnumber")))
      shiny::updateTextInput(session, "FieldNumber", value = fs882_reimagined_as_text(col("fieldnumber")))
      date_value <- fs882_reimagined_as_text(col("date"))
      shiny::updateTextInput(session, "Date", value = date_value)
      shiny::updateTextInput(session, "StartDate", value = if (nzchar(date_value)) substr(date_value, 1, 4) else "")
      shiny::updateTextInput(session, "SiteSurveyor", value = fs882_reimagined_as_text(col("sitesurveyor")))
      shiny::updateTextInput(session, "Location", value = fs882_reimagined_as_text(col("_location")))
      shiny::updateTextInput(session, "Latitude", value = fs882_reimagined_as_text(col("latitude")))
      shiny::updateTextInput(session, "Longitude", value = fs882_reimagined_as_text(col("longitude")))
      shiny::updateTextInput(session, "UTMEasting", value = fs882_reimagined_as_text(col("utmeasting")))
      shiny::updateTextInput(session, "UTMNorthing", value = fs882_reimagined_as_text(col("utmnorthing")))
      shiny::updateTextInput(session, "Elevation", value = fs882_reimagined_as_text(col("elevation")))
      shiny::updateTextInput(session, "SlopeGradient", value = fs882_reimagined_as_text(col("slopegradient")))
      shiny::updateTextInput(session, "Aspect", value = fs882_reimagined_as_text(col("aspect")))
      shiny::updateSelectInput(session, "MesoSlopePosition", selected = fs882_reimagined_as_text(col("mesoslopeposition")))
      shiny::updateSelectInput(session, "SurfaceShape", selected = fs882_reimagined_as_text(col("surfaceshape")))
      shiny::updateSelectInput(session, "MoistureRegime", selected = fs882_reimagined_as_text(col("moistureregime")))
      shiny::updateSelectInput(session, "NutrientRegime", selected = fs882_reimagined_as_text(col("nutrientregime")))
      shiny::updateTextAreaInput(session, "SiteNotes", value = fs882_reimagined_as_text(col("sitenotes")))
      shiny::updateTextAreaInput(session, "OfficeNotes", value = fs882_reimagined_as_text(col("officenotes")))
    }

    load_subforms <- function(plot_id) {
      rv$veg_a <- data.frame()
      rv$veg_c <- data.frame()
      rv$veg_d <- data.frame()
      rv$humus <- data.frame()
      rv$mineral <- data.frame()
      rv$audit <- data.frame()
      rv$veg_other <- data.frame()

      if (!nzchar(plot_id)) return(invisible(NULL))

      veg_rows <- fs882_reimagined_read_plot_rows(
        con,
        veg_table,
        plot_id,
        order_col_candidates = c("layer", "species", "id")
      )

      if (nrow(veg_rows)) {
        layer_col <- fs882_reimagined_col(names(veg_rows), "layer")
        if (!is.null(layer_col)) {
          layer_values <- toupper(trimws(as.character(veg_rows[[layer_col]])))
          rv$veg_a <- veg_rows[startsWith(layer_values, "A"), , drop = FALSE]
          rv$veg_c <- veg_rows[startsWith(layer_values, "C"), , drop = FALSE]
          rv$veg_d <- veg_rows[startsWith(layer_values, "D"), , drop = FALSE]
        } else {
          rv$veg_a <- veg_rows
          rv$veg_c <- veg_rows[0, , drop = FALSE]
          rv$veg_d <- veg_rows[0, , drop = FALSE]
        }
      }

      rv$humus <- fs882_reimagined_read_plot_rows(
        con,
        humus_table,
        plot_id,
        order_col_candidates = c("horizon", "upperdepth", "id")
      )
      rv$mineral <- fs882_reimagined_read_plot_rows(
        con,
        mineral_table,
        plot_id,
        order_col_candidates = c("horizon", "upperdepth", "id")
      )

      if (!is.null(audit_table)) {
        audit_fields <- fs882_reimagined_table_fields(con, audit_table)
        audit_plot_col <- fs882_reimagined_col(audit_fields, "plotnumber")
        q_audit <- fs882_reimagined_quote_table(con, audit_table)
        if (!is.null(audit_plot_col)) {
          rv$audit <- tryCatch(
            DBI::dbGetQuery(
              con,
              paste0("SELECT * FROM ", q_audit, " WHERE ", as.character(DBI::dbQuoteIdentifier(con, audit_plot_col)), " = ?"),
              list(plot_id)
            ),
            error = function(e) data.frame()
          )
        } else {
          rv$audit <- tryCatch(DBI::dbGetQuery(con, paste0("SELECT * FROM ", q_audit, " LIMIT 200")), error = function(e) data.frame())
        }
      }

      if (!is.null(veg_other_table)) {
        veg_other_fields <- fs882_reimagined_table_fields(con, veg_other_table)
        veg_other_plot_col <- fs882_reimagined_col(veg_other_fields, "plotnumber")
        q_veg_other <- fs882_reimagined_quote_table(con, veg_other_table)
        if (!is.null(veg_other_plot_col)) {
          rv$veg_other <- tryCatch(
            DBI::dbGetQuery(
              con,
              paste0("SELECT * FROM ", q_veg_other, " WHERE ", as.character(DBI::dbQuoteIdentifier(con, veg_other_plot_col)), " = ?"),
              list(plot_id)
            ),
            error = function(e) data.frame()
          )
        } else {
          rv$veg_other <- tryCatch(DBI::dbGetQuery(con, paste0("SELECT * FROM ", q_veg_other, " LIMIT 200")), error = function(e) data.frame())
        }
      }
    }

    observeEvent(current_plot_from_state(), {
      plot_id <- trimws(as.character(current_plot_from_state() %||% ""))
      if (!nzchar(plot_id)) return()

      rv$current_plot <- plot_id
      state$CurrSU <- plot_id
      state$sysCurrSU <- plot_id

      load_plot_header(plot_id)
      load_subforms(plot_id)
    }, ignoreInit = FALSE)

    observeEvent(input$btnFindPlot, {
      plot_id <- trimws(as.character(input$PlotNumber %||% ""))
      if (!nzchar(plot_id)) {
        shiny::showNotification("Enter a plot number first.", type = "warning")
        return()
      }
      rv$current_plot <- plot_id
      state$CurrSU <- plot_id
      state$sysCurrSU <- plot_id
      load_plot_header(plot_id)
      load_subforms(plot_id)
      shiny::showNotification(paste("Loaded plot", plot_id), type = "message")
    })

    observeEvent(input$btnSaveRecord, {
      if (is.null(env_table)) {
        shiny::showNotification("Env table is not available.", type = "error")
        return()
      }

      plot_id <- trimws(as.character(input$PlotNumber %||% rv$current_plot %||% state$CurrSU %||% ""))
      if (!nzchar(plot_id)) {
        shiny::showNotification("Plot Number is required to save.", type = "error")
        return()
      }

      field_values <- list(
        plotnumber = plot_id,
        fieldnumber = fs882_reimagined_as_text(input$FieldNumber),
        date = fs882_reimagined_as_text(input$Date),
        sitesurveyor = fs882_reimagined_as_text(input$SiteSurveyor),
        `_location` = fs882_reimagined_as_text(input$Location),
        latitude = fs882_reimagined_as_num(input$Latitude),
        longitude = fs882_reimagined_as_num(input$Longitude),
        utmeasting = fs882_reimagined_as_num(input$UTMEasting),
        utmnorthing = fs882_reimagined_as_num(input$UTMNorthing),
        elevation = fs882_reimagined_as_num(input$Elevation),
        slopegradient = fs882_reimagined_as_num(input$SlopeGradient),
        aspect = fs882_reimagined_as_num(input$Aspect),
        mesoslopeposition = fs882_reimagined_as_text(input$MesoSlopePosition),
        surfaceshape = fs882_reimagined_as_text(input$SurfaceShape),
        moistureregime = fs882_reimagined_as_text(input$MoistureRegime),
        nutrientregime = fs882_reimagined_as_text(input$NutrientRegime),
        sitenotes = fs882_reimagined_as_text(input$SiteNotes),
        officenotes = fs882_reimagined_as_text(input$OfficeNotes),
        projectid = fs882_reimagined_as_text(input$ProjectID)
      )

      ok <- fs882_reimagined_upsert_env(con, env_table, field_values)
      if (!isTRUE(ok)) {
        shiny::showNotification("Save failed for Env.", type = "error")
        return()
      }

      rv$current_plot <- plot_id
      state$CurrSU <- plot_id
      state$sysCurrSU <- plot_id

      shiny::showNotification("FS882 site record saved.", type = "message")
      load_subforms(plot_id)
    })

    observeEvent(input$btnSaveVeg, {
      shiny::showNotification("Vegetation grid save is not yet wired for inline editing in this block.", type = "message")
    })

    observeEvent(input$btnAddVegRow, {
      shiny::showNotification("Use Vegetation module for full species row editing in this block.", type = "message")
    })

    observeEvent(input$btnDeleteVegRow, {
      shiny::showNotification("Delete row action is deferred in this block.", type = "message")
    })

    observeEvent(input$btnG2MainMenu, {
      target_tab <- state$DataEntryReturnTab %||% "Vegetation"
      bslib::nav_select("main_tabs", target_tab, session = root_session)
    })

    observeEvent(input$btnAudit, {
      bslib::nav_select("tabPages", "Audit", session = session)
    })

    observeEvent(input$btnManagePictures, {
      shiny::showNotification("Picture manager integration is deferred for this block.", type = "message")
    })

    observeEvent(input$btnGoogleEarth, {
      shiny::showNotification("Google Earth launch is deferred for this block.", type = "message")
    })

    observeEvent(input$btnPlotPicture, {
      shiny::showNotification("Plot picture action is deferred for this block.", type = "message")
    })

    observeEvent(input$btnSuIntoEnv, {
      shiny::showNotification("SU Into Env transfer is deferred for this block.", type = "message")
    })

    observeEvent(input$btnEnvIntoSu, {
      shiny::showNotification("Env Into SU transfer is deferred for this block.", type = "message")
    })

    observeEvent(input$btnCreateSuFromFilter, {
      shiny::showNotification("Create SU From Form Filter is deferred for this block.", type = "message")
    })

    observeEvent(input$btnVegProfiling, {
      shiny::showNotification("Plot Profiling is deferred for this block.", type = "message")
    })

    render_grid <- function(df, empty_message) {
      display_df <- if (nrow(df)) df else fs882_reimagined_empty_df(empty_message)
      DT::datatable(
        display_df,
        rownames = FALSE,
        options = list(pageLength = 8, scrollX = TRUE, autoWidth = TRUE)
      )
    }

    output$SubVegA <- DT::renderDT({
      render_grid(rv$veg_a, "No Layer A records")
    })
    output$SubVegC <- DT::renderDT({
      render_grid(rv$veg_c, "No Layer C records")
    })
    output$SubVegD <- DT::renderDT({
      render_grid(rv$veg_d, "No Layer D records")
    })
    output$SoilHumus <- DT::renderDT({
      render_grid(rv$humus, "No humus records")
    })
    output$SoilMineral <- DT::renderDT({
      render_grid(rv$mineral, "No mineral records")
    })
    output$USysAudit <- DT::renderDT({
      render_grid(rv$audit, "No audit records")
    })
    output$USysVegOther <- DT::renderDT({
      render_grid(rv$veg_other, "No Veg Other records")
    })
  })
}

mod_fs882_6x4xl_ui <- function(id) {
  mod_fs882_6x4_reimagined_ui(id)
}

mod_fs882_6x4xl_server <- function(id, state, con) {
  mod_fs882_6x4_reimagined_server(id, state, con)
}

mod_fs882_6x4_ui <- function(id) {
  mod_fs882_6x4_reimagined_ui(id)
}

mod_fs882_6x4_server <- function(id, state, con) {
  mod_fs882_6x4_reimagined_server(id, state, con)
}

mod_fs882_ui <- function(id) {
  mod_fs882_6x4_reimagined_ui(id)
}

mod_fs882_server <- function(id, state, con) {
  mod_fs882_6x4_reimagined_server(id, state, con)
}
