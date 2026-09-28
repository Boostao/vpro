# FS882-6x4 Ecosystem Field Form Module
# Migrated from Access FS882-6x4XL form

# Plot-wide editor helpers. Only controls backed by canonical Env/Admin columns
# participate; child grids and their navigation remain separate.
fs882_plot_fields <- c(
  "FieldNumber", "Date", "SiteSurveyor", "Location", "FSRegionDistrict",
  "NtsMapSheet", "UTMZone", "UTMEasting", "UTMNorthing", "LocationAccuracy",
  "AirPhotoNum", "XCoord", "YCoord", "Ecosection", "PlotRepresenting",
  "Zone", "SubZone", "SiteSeries", "RealmClass", "TransDistrib", "MapUnit",
  "MoistureRegime", "NutrientRegime", "SuccessionalStatus", "StructuralStage",
  "StandAge", "Elevation", "SlopeGradient", "Aspect", "MesoSlopePosition",
  "SurfaceShape", "SurfaceTopographyType", "SurfaceTopographySize",
  "SubstrateOrganicMatter", "SubstrateRocks", "SubstrateDecWood",
  "SubstrateMineralSoil", "SubstrateBedRock", "SubstrateWater", "SiteNotes",
  "OfficeNotes", "Photo", "SiteDisturbance1", "SiteDisturbance2",
  "SiteDisturbance3", "Exposure1", "Exposure2", "EnteredBy",
  "UpdatedFromCards", "SpeciesListComplete", "StrataCoverTree",
  "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss", "VegSurveyor",
  "VegNotes", "BedrockGeology1", "BedrockGeology2", "BedrockGeology3",
  "CoarseFragLith1", "CoarseFragLith2", "CoarseFragLith3", "SoilSurveyor",
  "TerrainTextureSurf", "SurficialMaterialSurf", "SurfaceExpSurf",
  "GeoMorProSurf", "TerrainTextureSubSurf", "SurficialMaterialSubSurf",
  "SurfaceExpSubSurf", "GeoMorProSubSurf", "SoilClassSubGroup",
  "SoilClassGroup", "HumusForm", "HumusFormPhase", "HumusThickness",
  "HydroGeoSystem", "HydroGeoSubSystem", "RootingDepth",
  "RootZoneParticleSize", "RootRestrictingType", "WaterSource",
  "SoilDrainage", "RootRestrictingDepth", "SeepageDepth",
  "FloodingRegimeFreq", "FloodingRegimeDur", "SoilNotes", "BECSiteUnit",
  "UserSiteUnit", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality",
  "ProjectID", "StartDate", "Latitude", "Longitude"
)
fs882_plot_boolean <- c("UpdatedFromCards", "SpeciesListComplete")

fs882_field_map <- function(plot) {
  columns <- lapply(plot[c("env", "admin")], names)
  lapply(fs882_plot_fields, function(id) {
    hits <- lapply(columns, function(x) x[tolower(x) == tolower(id)])
    if (sum(lengths(hits)) != 1L) return(NULL)
    kind <- names(hits)[lengths(hits) == 1L]
    list(table = kind, column = hits[[kind]])
  }) |> stats::setNames(fs882_plot_fields)
}

fs882_field_value <- function(value, type, field) {
  if (field %in% fs882_plot_boolean) {
    if (length(value) != 1L || is.na(value)) stop("Invalid boolean for ", field, call. = FALSE)
    if (!is.logical(value)) stop("Invalid boolean for ", field, call. = FALSE)
    return(value)
  }
  if (inherits(value, "Date")) value <- format(value, "%Y-%m-%d")
  text <- trimws(as.character(value %||% ""))
  if (length(text) != 1L || is.na(text)) stop("Invalid value for ", field, call. = FALSE)
  if (!nzchar(text)) {
    if (grepl("INT|REAL|FLOA|DOUB|NUM", toupper(type))) return(NA_real_)
    return(NA_character_)
  }
  if (grepl("INT|REAL|FLOA|DOUB|NUM", toupper(type))) {
    number <- suppressWarnings(as.numeric(text))
    if (!is.finite(number) || (grepl("INT", toupper(type)) && number != floor(number)))
      stop("Invalid numeric value for ", field, ": ", text, call. = FALSE)
    return(number)
  }
  if (grepl("DATE|TIME", toupper(type))) {
    parsed <- suppressWarnings(as.Date(text, format = "%Y-%m-%d"))
    if (is.na(parsed) || format(parsed, "%Y-%m-%d") != text ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text))
      stop("Invalid date for ", field, ": use YYYY-MM-DD.", call. = FALSE)
  }
  text
}

fs882_same_value <- function(before, after, id) {
  if (id == "Date" && !is.na(before)) before <- as.character(as.Date(before))
  if (id %in% fs882_plot_boolean && !is.na(before)) before <- as.logical(before)
  (is.na(before) && is.na(after)) || isTRUE(all.equal(before, after, check.attributes = FALSE))
}

fs882_field_changes <- function(draft, baseline, mapping, types) {
  changed <- list(env = list(), admin = list())
  for (id in names(draft)) {
    target <- mapping[[id]]
    if (is.null(target)) stop("No Env/Admin mapping for: ", id, call. = FALSE)
    if (is.null(types[[target$table]][[target$column]]))
      stop("No declared type for: ", id, call. = FALSE)
    before <- baseline[[target$table]][[target$column]][[1L]]
    after <- fs882_field_value(draft[[id]], types[[target$table]][[target$column]], id)
    if (!fs882_same_value(before, after, id)) {
      changed[[target$table]][[target$column]] <- after
    }
  }
  changed
}

fs882_saved_fields <- function(touched, draft, latest, mapping, types) {
  touched[vapply(touched, function(id) {
    target <- mapping[[id]]
    if (is.null(target) || is.null(draft[[id]])) return(FALSE)
    actual <- latest[[target$table]][[target$column]][[1L]]
    intended <- tryCatch(fs882_field_value(draft[[id]], types[[target$table]][[target$column]], id),
                         error = function(e) e)
    !inherits(intended, "error") && fs882_same_value(actual, intended, id)
  }, logical(1))]
}

fs882_project_matches <- function(context, project, path, state_project) {
  identical(project, context$active$project) && identical(path, context$active$path) &&
    identical(project, state_project)
}

fs882_coord_parts <- function(method) {
  if (method == "1") list(Latitude = c("LatD2", "LatMD"), Longitude = c("LonD2", "LonMD"))
  else list(Latitude = c("LatD", "LatM", "LatS"), Longitude = c("LonD", "LonM", "LonS"))
}

fs882_coord_result <- function(parts) {
  tryCatch(list(value = do.call(fs882_compose_coord, parts), error = NULL),
           error = function(e) list(value = NULL, error = conditionMessage(e)))
}

# The coordinate API composes positive components; apply a signed-degree
# convention here: a negative degree means west/south, minutes stay positive.
fs882_compose_coord <- function(degrees, minutes, seconds = 0) {
  if ((is.null(degrees) || !nzchar(trimws(as.character(degrees)))) &&
      (is.null(minutes) || !nzchar(trimws(as.character(minutes)))) &&
      (identical(seconds, 0) || is.null(seconds) || !nzchar(trimws(as.character(seconds))))) return(NA_real_)
  parse <- function(x) {
    if (is.null(x) || !nzchar(trimws(as.character(x)))) return(NA_real_)
    number <- suppressWarnings(as.numeric(x))
    if (!is.finite(number)) stop("Invalid coordinate component: ", x, call. = FALSE)
    number
  }
  d <- parse(degrees); m <- parse(minutes); s <- parse(seconds)
  if (is.na(d) && is.na(m) && is.na(s)) return(NA_real_)
  if (!is.finite(d) || (!is.na(m) && (m < 0 || m >= 60)) ||
      (!is.na(s) && (s < 0 || s >= 60)))
    stop("Invalid coordinate components (minutes and seconds must be in [0, 60)).", call. = FALSE)
  sign <- if (d < 0 || grepl("^-", trimws(as.character(degrees)))) -1 else 1
  sign * vpro::vpro_coordinate_decimal(abs(d), m, s)
}

fs882_decompose_coord <- function(value, method) {
  if (is.na(value)) return(if (method == "1") c("", "") else c("", "", ""))
  parts <- if (method == "1") vpro::vpro_coordinate_dm(value)[1, ] else vpro::vpro_coordinate_dms(value)[1, ]
  parts$degrees <- parts$degrees * if (value < 0) -1 else 1
  if (value < 0 && parts$degrees == 0) parts$degrees <- "-0"
  as.character(unlist(parts))
}

# -- Dropdown loader --

list_choices <- function(con, list_name) {
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT item, itemdescription",
        "FROM VLists.USysTableOfLists",
        "WHERE lower(listname) = lower(?)",
        "ORDER BY itemorder, item"
      ),
      params = list(list_name)
    ),
    error = function(e) {
      message("[list_choices] ERROR for '", list_name, "': ", conditionMessage(e))
      data.frame()
    }
  )
  # DuckDB returns SQLite column names in title case (Item, ItemDescription);
  # normalize to lowercase so rows$item / rows$itemdescription work reliably.
  names(rows) <- tolower(names(rows))
  if (!nrow(rows)) {
    return(c("---" = ""))
  }
  labels <- ifelse(
    is.na(rows$itemdescription) | !nzchar(trimws(rows$itemdescription)),
    rows$item,
    paste0(rows$item, " - ", rows$itemdescription)
  )
  c(setNames("", ""), stats::setNames(as.character(rows$item), labels))
}

# -- Coercion helpers --

as_text <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return("")
  }
  as.character(value)
}

as_num <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(NA_real_)
  }
  text <- trimws(as.character(value))
  if (!nzchar(text)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(text))
}

as_chr <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(NA_character_)
  }
  text <- trimws(as.character(value))
  if (!nzchar(text)) NA_character_ else text
}

num_display <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value) || !is.finite(value)) {
    ""
  } else {
    formatC(value, format = "fg", flag = "-")
  }
}

# -- Env table SQL helpers --

env_tb <- function(con) {
  as.character(app_project_table_sql(con, "Env", app_config_get("Current", "CurrProject"), prj = TRUE))
}

veg_tb <- function(con) {
  as.character(app_project_table_sql(con, "Veg", app_config_get("Current", "CurrProject"), prj = TRUE))
}

humus_tb <- function(con) {
  as.character(app_project_table_sql(con, "Humus", app_config_get("Current", "CurrProject"), prj = TRUE))
}

mineral_tb <- function(con) {
  as.character(app_project_table_sql(con, "Mineral", app_config_get("Current", "CurrProject"), prj = TRUE))
}

audit_tb <- function(con) {
  as.character(app_project_table_sql(con, "Audit", app_config_get("Current", "CurrProject"), prj = TRUE))
}

other_tb <- function(con) {
  as.character(app_project_table_sql(con, "Other", app_config_get("Current", "CurrProject"), prj = TRUE))
}

veg_other_tb <- function(con) {
  as.character(app_project_table_sql(con, "Veg", app_config_get("Current", "CurrProject"), prj = TRUE))
}

admin_tb <- function(con) {
  # Sample_Admin table (not prefixed, shares schema with project db)
  proj <- app_config_get("Current", "CurrProject")
  as.character(app_project_table_sql(con, "Sample_Admin", proj, prj = FALSE))
}

# -- inline UI helper --
# Usage: inline_label(textInput, ns("StartDate"), label = "Yr.")
inline_label <- function(fn, inputId, label, ...) {
  div(
    style = paste0("display: flex; align-items: center; gap: 4px;"),
    tags$label(label, `for` = inputId, class = "control-label"),
    div(
      style = "flex: 1;",
      fn(inputId = inputId, label = NULL, width = "100%", ...)
    )
  )
}

# ============================================================
# UI
# ============================================================

mod_fs882_6x4_ui <- function(id) {
  ns <- NS(id)

  card(
    full_screen = TRUE,

    # -- Header --
    card_header(
      class = "d-flex flex-wrap align-items-center justify-content-between gap-2",
      uiOutput(ns("caption")),
      h6(class = "mb-0", "Based on the 2015 Ecosystem Field Form (FS882)"),
      div(
        class = "d-flex flex-wrap gap-1 align-items-center",
        # -- Record navigator (Access record bar parity) --
        actionButton(ns("btnNavFirst"), NULL, icon = icon("backward-step"), class = "btn btn-outline-primary btn-sm px-2"),
        actionButton(ns("btnNavPrev"), NULL, icon = icon("caret-left"), class = "btn btn-outline-primary btn-sm px-2"),
        selectizeInput(ns("navPlotPicker"), NULL, choices = NULL, width = "100px", options = list(placeholder = "Plot...")),
        tags$small(class = "text-body-secondary", textOutput(ns("navRecordCount"), inline = TRUE)),
        actionButton(ns("btnNavNext"), NULL, icon = icon("caret-right"), class = "btn btn-outline-primary btn-sm px-2"),
        actionButton(ns("btnNavLast"), NULL, icon = icon("forward-step"), class = "btn btn-outline-primary btn-sm px-2"),
        actionButton(ns("btnNavNew"), NULL, icon = icon("plus"), class = "btn btn-outline-primary btn-sm px-2", title = "New record"),
        tags$div(class = "vr mx-1"),
        # -- Search (Access Find behaviour) --
        div(
          class = "input-group input-group-sm",
          style = "width: 180px;",
          tags$input(type = "text", class = "form-control form-control-sm", id = ns("navSearchBox"), placeholder = "Search..."),
          tags$button(class = "btn btn-outline-primary btn-sm", type = "button", id = ns("btnNavSearch"), icon("magnifying-glass"))
        ),
        tags$div(class = "vr mx-1"),
        # -- Tool buttons --
        actionButton(ns("btnAudit"), "Audit", class = "btn btn-outline-primary btn-sm"),
        actionButton(ns("btnSuIntoEnv"), "SU Into Env", class = "btn btn-outline-primary btn-sm"),
        actionButton(ns("btnEnvIntoSu"), "Env Into SU", class = "btn btn-outline-primary btn-sm"),
        actionButton(ns("btnCreateSuFromFilter"), "Create SU From Filter", class = "btn btn-outline-primary btn-sm"),
        tags$div(class = "vr mx-1"),
        actionButton(ns("btnVegProfiling"), "Plot Profiling", class = "btn btn-outline-primary btn-sm"),
        tags$div(class = "vr mx-1"),
        # -- Save / Lock --
        checkboxInput(ns("optLockData"), "Lock data", value = FALSE, width = "auto"),
        actionButton(ns("btnDiscardRecord"), "Discard", class = "btn btn-outline-secondary btn-sm"),
        actionButton(ns("btnSaveRecord"), "Save", class = "btn-bcgold btn-sm")
      )
    ),

    # JS bridge: wire raw-HTML search box + button into Shiny inputs
    tags$script(HTML(sprintf(
      "
      $(function() {
        var ns = '%s';
        // Search button click -> set Shiny input
        $('#' + ns + 'btnNavSearch').on('click', function() {
          var q = $('#' + ns + 'navSearchBox').val();
          Shiny.setInputValue(ns + 'nav_search_trigger', {query: q, ts: Date.now()});
        });
        // Enter key in search box -> same trigger
        $('#' + ns + 'navSearchBox').on('keydown', function(e) {
          if (e.key === 'Enter') {
            e.preventDefault();
            var q = $(this).val();
            Shiny.setInputValue(ns + 'nav_search_trigger', {query: q, ts: Date.now()});
          }
        });
      });
    ",
      ns("")
    ))),

    tags$script(HTML(sprintf("$(document).on('shown.bs.modal', '#shiny-modal', function() { if (!$(this).find('.sidebar-project-dialog').length) Shiny.setInputValue('%1$sfs882_modal_shown', Date.now(), {priority: 'event'}); }); $(document).on('hidden.bs.modal', '#shiny-modal', function() { if (!$(this).find('.sidebar-project-dialog').length) Shiny.setInputValue('%1$sfs882_modal_closed', Date.now(), {priority: 'event'}); });", ns("")))),
    tags$style(HTML(".fs882-changed { box-shadow: inset 3px 0 #bd9b48; }")),
    tags$script(HTML("Shiny.addCustomMessageHandler('fs882-dirty', function(msg) {
      $('[id]').filter(function() { return this.id.indexOf(msg.ns) === 0; })
        .closest('.shiny-input-container').removeClass('fs882-changed');
      msg.ids.forEach(function(id) { $('#' + msg.ns + id).closest('.shiny-input-container').addClass('fs882-changed'); });
    });")),

    # -- Tabs --
    navset_card_tab(
      id = ns("tabPages"),

      # ---- Site tab ----
      nav_panel(
        "Site",
        class = "p-2",
        layout_columns(
          col_widths = c(9, 3),
          layout_columns(
            col_widths = c(3, 3, 6, 12, 12, 3, 9, 12, 12),
            # BEC Master (3)
            card(
              card_header("BEC Master"),
              layout_columns(
                col_widths = c(12, 12),
                selectizeInput(ns("BECSiteUnit"), label = NULL, choices = NULL),
                actionButton(ns("btnCopyToUserSU"), "Copy to Working Unit", class = "btn btn-primary btn-sm")
              )
            ),
            # Working Unit (3)
            card(
              card_header("Working Unit"),
              card_body(
                layout_columns(
                  col_widths = c(12, 12),
                  class = "mb-2",
                  selectInput(ns("UserSiteUnit"), label = NULL, choices = NULL),
                  radioButtons(
                    ns("optAssignedSuSource"),
                    label = NULL,
                    choices = c("Env" = "1", "Master" = "2", "SU Tbl" = "3"),
                    selected = as_text(app_config_get("Current", "AssignedSuSource")),
                    inline = TRUE
                  )
                )
              )
            ),
            # ProjectID (5)
            card(
              card_header("Project"),
              card_body(
                layout_columns(
                  class = "mb-0",
                  col_widths = c(9, 3, 6, 6),
                  inline_label(selectInput, ns("ProjectID"), label = "Project ID", choices = NULL),
                  inline_label(textInput, ns("StartDate"), label = "Yr."),
                  radioButtons(
                    ns("optProjectID"),
                    label = NULL,
                    choices = c("Env" = "1", "Master" = "2"),
                    selected = as_text(app_config_get("Current", "ProjectIdSource") %||% "1"),
                    inline = TRUE
                  ),
                  actionButton(ns("btnLoadMetadata"), "Edit Project Metadata", class = "btn btn-primary btn-sm")
                )
              )
            ),
            # Location (12)
            card(
              card_header("Location"),
              card_body(
                layout_columns(
                  col_widths = c(12, 3, 3, 1, 2, 2, 1, 2, 1, 1, 7, 1),
                  textAreaInput(ns("Location"), "General Location", rows = 2),
                  selectInput(ns("FSRegionDistrict"), "Forest Region/Dist.", choices = NULL),
                  textInput(ns("NtsMapSheet"), "Map Sheet"),
                  textInput(ns("UTMZone"), "UTM Zone"),
                  textInput(ns("UTMEasting"), "Easting"),
                  textInput(ns("UTMNorthing"), "Northing"),
                  textInput(ns("LocationAccuracy"), "Accur. (m)"),
                  textInput(ns("AirPhotoNum"), "Air Photo No."),
                  textInput(ns("XCoord"), "X Co-ord."),
                  textInput(ns("YCoord"), "Y Co-ord"),
                  layout_columns(
                    gap = "0.06rem",
                    col_widths = c(12, 12),
                    inline_label(
                      radioButtons,
                      ns("optCoordMethod"),
                      label = "Coordinate Method",
                      choices = c("D.d" = "0", "DM.m" = "1", "DMS.s" = "2"),
                      selected = as_text(app_config_get("Current", "CoordMethod")),
                      inline = TRUE
                    ),
                    uiOutput(ns("coord_row"))
                  ),
                  selectInput(ns("Ecosection"), "Ecosection", choices = NULL)
                )
              )
            ),
            # Site Information (12)
            card(
              card_header("Site Information"),
              card_body(
                layout_columns(
                  # Row 1: Plot Representing (12)
                  # Row 2: BEC Unit Zone+Sub (3) | SiteSeries (2) | RealmClass (2) | TransDistrib (3) | MapUnit (2)
                  # Row 3: MoistureRegime (3) | NutrientRegime (2) | SuccessionalStatus (2) | StructuralStage (3) | StandAge (2)
                  # Row 4: Elevation (2) | Slope (1) | Aspect (1) | MesoSlopePos (2) | SurfaceShape (2) | MicrotopType (2) | MicrotopSize (2)
                  col_widths = c(12, 3, 2, 2, 3, 2, 3, 2, 2, 3, 2, 2, 1, 1, 2, 2, 2, 2),
                  # Row 1
                  textAreaInput(ns("PlotRepresenting"), "Plot Representing", width = "100%", rows = 2),
                  # Row 2
                  div(
                    class = "shiny-input-container",
                    tags$label("Biogeoclimatic Unit", class = "control-label"),
                    layout_columns(
                      gap = "0.1rem",
                      col_widths = c(7, 5),
                      selectInput(ns("Zone"), label = NULL, choices = NULL),
                      selectInput(ns("SubZone"), label = NULL, choices = NULL)
                    )
                  ),
                  selectInput(ns("SiteSeries"), "Site Series", choices = NULL),
                  selectInput(ns("RealmClass"), "Realm/Class", choices = NULL),
                  selectInput(ns("TransDistrib"), "Transition/Distrib.", choices = NULL),
                  textInput(ns("MapUnit"), "Map Unit"),
                  # Row 3
                  selectInput(ns("MoistureRegime"), "Moisture Regime", choices = NULL),
                  selectInput(ns("NutrientRegime"), "Nutrient Regime", choices = NULL),
                  selectInput(ns("SuccessionalStatus"), "Successional Status", choices = NULL),
                  selectInput(ns("StructuralStage"), "Structural Stage", choices = NULL),
                  textInput(ns("StandAge"), "Stand Age"),
                  # Row 4
                  textInput(ns("Elevation"), "Elevation (m)"),
                  textInput(ns("SlopeGradient"), "Slope (%)"),
                  textInput(ns("Aspect"), "Aspect"),
                  selectInput(ns("MesoSlopePosition"), "Meso Slope Pos.", choices = NULL),
                  selectInput(ns("SurfaceShape"), "Surface Shape", choices = NULL),
                  selectInput(ns("SurfaceTopographyType"), "Microtop. type", choices = NULL),
                  selectInput(ns("SurfaceTopographySize"), "Microtop. size", choices = NULL)
                )
              )
            ),
            # Data Quality (3)
            card(
              card_header("Data Quality"),
              card_body(
                layout_columns(
                  col_widths = c(2, 10, 2, 10, 2, 10),
                  tags$label("Site", class = "control-label"),
                  selectInput(ns("SitePlotQuality"), label = NULL, choices = NULL),
                  tags$label("Veg", class = "control-label"),
                  selectInput(ns("VegPlotQuality"), label = NULL, choices = NULL),
                  tags$label("Soil", class = "control-label"),
                  selectInput(ns("SoilPlotQuality"), label = NULL, choices = NULL)
                )
              )
            ),
            # Substrate % (9)
            card(
              card_header("Substrate %"),
              card_body(
                layout_columns(
                  col_widths = c(3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3),
                  tags$label("Org. Matter", class = "control-label"),
                  textInput(ns("SubstrateOrganicMatter"), label = NULL),
                  tags$label("Rocks", class = "control-label"),
                  textInput(ns("SubstrateRocks"), label = NULL),
                  tags$label("Dec. Wood", class = "control-label"),
                  textInput(ns("SubstrateDecWood"), label = NULL),
                  tags$label("Mineral Soil", class = "control-label"),
                  textInput(ns("SubstrateMineralSoil"), label = NULL),
                  tags$label("Bedrock", class = "control-label"),
                  textInput(ns("SubstrateBedRock"), label = NULL),
                  tags$label("Water", class = "control-label"),
                  textInput(ns("SubstrateWater"), label = NULL)
                )
              )
            ),
            # Field Notes (12)
            card(
              card_header("Field Notes"),
              card_body(
                textAreaInput(ns("SiteNotes"), NULL, width = "100%", rows = 3)
              )
            ),
            # Office Notes (12)
            card(
              card_header("Office Notes"),
              card_body(
                textAreaInput(ns("OfficeNotes"), NULL, width = "100%", rows = 3)
              )
            ),
          ),
          layout_columns(
            col_widths = c(7, 5, 7, 5, 12, 7, 5, 12, 12),
            # Row 1
            dateInput(ns("Date"), "Date"),
            textInput(ns("PlotNumber"), "Plot Number", placeholder = "Use New to create / separate renumber action"),
            # Row 2
            textInput(ns("SiteSurveyor"), "Surveyor"),
            textInput(ns("FieldNumber"), "Field No."),
            # Row 3: Site Diagram / Picture (full width)
            card(
              card_header("Site Diagram / Picture"),
              card_body(
                layout_columns(
                  col_widths = c(12, 12, 12),
                  uiOutput(ns("site_picture")),
                  div(
                    class = "d-flex flex-wrap gap-2 mt-2",
                    actionButton(ns("btnManagePictures"), "Picture Manager", class = "btn btn-primary btn-sm")
                  ),
                  inline_label(textInput, ns("Photo"), "Photo")
                )
              )
            ),
            # Row 4: Site Disturbance (7) | Exposure Type (5)
            card(
              card_header("Site Disturbance"),
              card_body(
                padding = "0rem",
                layout_columns(
                  gap = "0rem",
                  col_widths = c(4, 4, 4),
                  selectInput(ns("SiteDisturbance1"), label = NULL, choices = NULL),
                  selectInput(ns("SiteDisturbance2"), label = NULL, choices = NULL),
                  selectInput(ns("SiteDisturbance3"), label = NULL, choices = NULL)
                )
              )
            ),
            card(
              card_header("Exposure Type"),
              card_body(
                padding = "0rem",
                layout_columns(
                  gap = "0rem",
                  col_widths = c(6, 6),
                  selectInput(ns("Exposure1"), label = NULL, choices = NULL),
                  selectInput(ns("Exposure2"), label = NULL, choices = NULL)
                )
              )
            ),
            # Row 5: Entered By
            inline_label(textInput, ns("EnteredBy"), "Entered by"),
            # Row 6: Updated From Cards
            checkboxInput(ns("UpdatedFromCards"), "Updated From Cards", value = FALSE)
          )
        )
      ),

      # ---- Vegetation tab ----
      nav_panel(
        "Vegetation",
        class = "p-2",
        # Header bar: Spp.Complete | % Cover label | cover inputs | Surveyor | Find Plot + plot#
        layout_columns(
          col_widths = c(2, 1, 1, 1, 1, 1, 3, 2),
          class = "mb-2 align-items-end",
          checkboxInput(ns("SpeciesListComplete"), "Spp. List Complete?", value = FALSE),
          div(class = "form-group shiny-input-container", tags$label(HTML("%<br />Cover"), class = "control-label")),
          textInput(ns("StrataCoverTree"), "Tree(A)"),
          textInput(ns("StrataCoverShrub"), "Shrub(B)"),
          textInput(ns("StrataCoverHerb"), "Herb(C)"),
          textInput(ns("StrataCoverMoss"), "Moss/Lichen(D)"),
          textInput(ns("VegSurveyor"), "Surveyor"),
          div(
            class = "d-flex gap-2 align-items-end",
            actionButton(ns("btnFindPlot"), "Find Plot", class = "btn btn-outline-primary btn-sm"),
            tags$div(class = "fw-semibold", textOutput(ns("VegPlotNumber"), inline = TRUE))
          )
        ),
        # Three species tables
        layout_columns(
          col_widths = c(5, 3, 4),
          class = "mb-2",
          card(
            card_body(DT::DTOutput(ns("dt_veg_a")))
          ),
          card(
            card_body(DT::DTOutput(ns("dt_veg_c")))
          ),
          card(
            card_body(DT::DTOutput(ns("dt_veg_d")))
          )
        ),
        div(class = "d-flex gap-2 mb-2",
            actionButton(ns("veg_edit"), "Edit selected species", class = "btn btn-outline-primary btn-sm"),
            actionButton(ns("veg_delete"), "Delete selected species", class = "btn btn-outline-danger btn-sm")),
        # Vegetation Notes
        textAreaInput(ns("VegNotes"), "Vegetation Notes", width = "100%", rows = 3),
        # Bottom action buttons
        div(
          class = "d-flex flex-wrap gap-2 mt-1",
          actionButton(ns("btnCheckSppCodes"), "Check Spp Codes", class = "btn btn-primary btn-sm"),
          actionButton(ns("btnAddSpp"), "Add Species", class = "btn btn-primary btn-sm"),
          actionButton(ns("btnCoverAndHeight"), "Cover & Height", class = "btn btn-primary btn-sm"),
          actionButton(ns("btnAllowSmallEntry"), "Allow <0.1% Entry", class = "btn btn-primary btn-sm")
        )
      ),

      # ---- Veg Other tab (Access USysVegOther subform) ----
      nav_panel(
        "Veg Other",
        class = "p-2",
        layout_columns(
          col_widths = c(10, 2),
          card(
            card_body(tagList(DT::DTOutput(ns("dt_veg_other")),
              div(class = "d-flex gap-2 mt-2",
                  actionButton(ns("veg_other_add"), "Add", class = "btn btn-primary btn-sm"),
                  actionButton(ns("veg_other_edit"), "Edit selected", class = "btn btn-outline-primary btn-sm"),
                  actionButton(ns("veg_other_delete"), "Delete selected", class = "btn btn-outline-danger btn-sm"))))
          ),
          card(
            card_header("Column Legend"),
            card_body(
              tags$p(tags$b("LL"), " = Arboreal Lichen loading code"),
              tags$p(tags$b("AF"), " = Available Forage Code"),
              tags$p(tags$b("DC"), " = Distribution Code"),
              tags$p(tags$b("UT"), " = Utilization Code"),
              tags$p(tags$b("VI"), " = Vigour Code"),
              tags$p(tags$b("PV"), " = Phenology Code - Vegetative"),
              tags$p(tags$b("PG"), " = Phenology Code - Generative"),
              tags$p(tags$b("FFA"), " = Fruit/Flower abundance code")
            )
          )
        )
      ),

      # ---- Soil / Terrain tab ----
      nav_panel(
        "Soil / Terrain",
        class = "p-2",
        layout_columns(
          col_widths = c(1, 4, 4, 1, 2, 1, 11, 1, 3, 1, 3, 1, 3, 3, 1, 8),
          # --- GEOLOGY: Bedrock Type x3 | Coarse Frag. Lith. x3 | Surveyor ---
          card(card_header("Geology")),
          layout_columns(
            class = "p-2",
            col_widths = c(3, 3, 3, 3),
            tags$label("Bedrock Type", class = "control-label"),
            selectInput(ns("BedrockGeology1"), NULL, choices = NULL),
            selectInput(ns("BedrockGeology2"), NULL, choices = NULL),
            selectInput(ns("BedrockGeology3"), NULL, choices = NULL),
          ),
          layout_columns(
            class = "p-2",
            col_widths = c(3, 3, 3, 3),
            tags$label("Coarse Frag. Lith.", class = "control-label"),
            selectInput(ns("CoarseFragLith1"), NULL, choices = NULL),
            selectInput(ns("CoarseFragLith2"), NULL, choices = NULL),
            selectInput(ns("CoarseFragLith3"), NULL, choices = NULL),
          ),
          card(card_header("Surveyor(s)")),
          layout_columns(
            class = "p-2",
            col_widths = 12,
            textInput(ns("SoilSurveyor"), label = NULL)
          ),
          # --- TERRAIN: Surface row ---
          card(card_header(HTML("Terrain<br />&nbsp;"), class = "p-3")),
          layout_columns(
            class = "p-2",
            col_widths = c(3, 3, 3, 3, 3, 3, 3, 3),
            inline_label(selectInput, ns("TerrainTextureSurf"), "Surface Texture 1", choices = NULL),
            inline_label(selectInput, ns("SurficialMaterialSurf"), "Surficial Material 1", choices = NULL),
            inline_label(selectInput, ns("SurfaceExpSurf"), "Surface Expression 1", choices = NULL),
            inline_label(selectInput, ns("GeoMorProSurf"), "Geomorph. Process 1", choices = NULL),
            inline_label(selectInput, ns("TerrainTextureSubSurf"), "Surface Texture 2", choices = NULL),
            inline_label(selectInput, ns("SurficialMaterialSubSurf"), "Surficial Material 2", choices = NULL),
            inline_label(selectInput, ns("SurfaceExpSubSurf"), "Surface Expression 2", choices = NULL),
            inline_label(selectInput, ns("GeoMorProSubSurf"), "Geomorph. Process 2", choices = NULL)
          ),
          # --- SOIL CLASSIFICATION + HUMUS FORM + HYDROGEO ---
          card(card_header("Soil Subgroup")),
          layout_columns(
            class = "p-2",
            col_widths = c(4, 8),
            selectInput(ns("SoilClassSubGroup"), label = NULL, choices = NULL),
            inline_label(selectInput, ns("SoilClassGroup"), "Great Group", choices = NULL)
          ),
          card(card_header("Humus Form")),
          layout_columns(
            class = "p-2",
            col_widths = c(3, 4, 5),
            selectInput(ns("HumusForm"), label = NULL, choices = NULL),
            inline_label(selectInput, ns("HumusFormPhase"), "Phase", choices = NULL),
            inline_label(textInput, ns("HumusThickness"), "Thickness (cm)")
          ),
          card(card_header("HYDROGEO.")),
          layout_columns(
            class = "p-2",
            col_widths = c(8, 4),
            inline_label(selectInput, ns("HydroGeoSystem"), "Sys./Subsys.", choices = NULL),
            inline_label(selectInput, ns("HydroGeoSubSystem"), label = NULL, choices = NULL)
          ),
          # --- ROOTING + R.Z. PARTICLE SIZE ---
          layout_columns(
            col_widths = c(12, 12),
            inline_label(textInput, ns("RootingDepth"), "Rooting Depth (cm)"),
            inline_label(selectInput, ns("RootZoneParticleSize"), "R.Z. Particle Size", choices = NULL),
          ),
          tags$label(HTML("Root Restricting<br />Layer"), class = "control-label p-3"),
          # --- ROOT RESTRICTING + WATER SOURCE + DRAINAGE + LAYER DEPTH + SEEPAGE + FLOODING ---
          layout_columns(
            col_widths = c(2, 5, 5, 2, 3, 4, 3),
            inline_label(selectInput, ns("RootRestrictingType"), "Type", choices = NULL),
            inline_label(selectInput, ns("WaterSource"), "Water Source", choices = NULL),
            inline_label(selectInput, ns("SoilDrainage"), "Drainage Class", choices = NULL),
            inline_label(textInput, ns("RootRestrictingDepth"), "Depth (cm)"),
            inline_label(textInput, ns("SeepageDepth"), "Seepage (cm)"),
            inline_label(selectInput, ns("FloodingRegimeFreq"), "Flood Regime Frequency", choices = NULL),
            inline_label(selectInput, ns("FloodingRegimeDur"), "Duration", choices = NULL),
          )
        ),
        # --- ORGANIC HORIZONS / LAYERS ---
        card(
          class = "mb-2",
          card_header("Organic Horizons / Layers"),
          card_body(tagList(DT::DTOutput(ns("hot_humus")),
            div(class = "d-flex gap-2 mt-2", actionButton(ns("humus_add"), "Add", class = "btn btn-sm btn-primary"),
              actionButton(ns("humus_edit"), "Edit selected", class = "btn btn-sm btn-outline-primary"),
              actionButton(ns("humus_delete"), "Delete selected", class = "btn btn-sm btn-outline-danger"))))
        ),
        # --- MINERAL HORIZONS / LAYERS ---
        card(
          class = "mb-2",
          card_header("Mineral Horizons / Layers"),
          card_body(tagList(DT::DTOutput(ns("hot_mineral")),
            div(class = "d-flex gap-2 mt-2", actionButton(ns("mineral_add"), "Add", class = "btn btn-sm btn-primary"),
              actionButton(ns("mineral_edit"), "Edit selected", class = "btn btn-sm btn-outline-primary"),
              actionButton(ns("mineral_delete"), "Delete selected", class = "btn btn-sm btn-outline-danger"))))
        ),
        # --- SOIL NOTES ---
        card(
          class = "mb-2",
          card_header("Soil Notes"),
          card_body(
            textAreaInput(ns("SoilNotes"), NULL, width = "100%", rows = 3)
          )
        )
      ),

      # ---- Other tab (Access: SubOtherXL — User Defined Data) ----
      nav_panel(
        "Other",
        class = "p-2",
        card(
          card_header(
            class = "d-flex justify-content-between align-items-center",
            "User Defined Data",
            div(
              class = "d-flex gap-2 align-items-center",
              actionButton(ns("btnOtherPrev"), "\u25c4", class = "btn btn-sm btn-outline-secondary"),
              textOutput(ns("txtOtherNav"), inline = TRUE),
              actionButton(ns("btnOtherNext"), "\u25ba", class = "btn btn-sm btn-outline-secondary"),
              actionButton(ns("btnOtherNew"), "New", class = "btn btn-sm btn-outline-primary"),
              actionButton(ns("btnOtherDelete"), "Delete", class = "btn btn-sm btn-outline-danger"),
              actionButton(ns("btnOtherSave"), "Save", class = "btn btn-sm btn-primary"),
              actionButton(ns("btnOtherDiscard"), "Discard", class = "btn btn-sm btn-outline-secondary")
            )
          ),
          card_body(tagList(DT::DTOutput(ns("dt_other")), uiOutput(ns("other_editor"))))
        )
      ),

      # ---- Audit tab ----
      nav_panel(
        "Audit",
        class = "p-2",
        layout_columns(
          col_widths = c(9, 3),
          class = "mb-3 align-items-end",
          radioButtons(
            ns("optAuditStrength"),
            "Audit Strength",
            choices = c("Edit" = "1", "Edit & Add" = "2", "Edit, Add, & Delete" = "3"),
            selected = as_text(app_config_get("Audit", "AuditStrength")),
            inline = TRUE
          ),
          actionButton(ns("btnRestoreAudit"), "Restore selected", class = "btn btn-primary btn-sm")
        ),
        card(
          card_header("AUDIT"),
          card_body(DT::DTOutput(ns("dt_audit")))
        )
      )
    )
  ) # end vpro-form-sm wrapper
}

# ============================================================
# Server
# ============================================================

mod_fs882_6x4_server <- function(id, state, con, context) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    root_session <- session$rootScope()

    # Trigger for metadata modal: increment each time modal is opened so that
    # mod_project_metadata_server loads data AFTER the modal DOM exists.
    metadata_open_trigger <- shiny::reactiveVal(0L)
    # Current plot's ProjectID passed to metadata module on each open
    metadata_plot_project_id <- shiny::reactiveVal("")

    bec_choices <- tryCatch({
      rows <- DBI::dbGetQuery(con, "SELECT SiteSeries, SiteSeriesLongName FROM USysMasterSiteUnitList WHERE Level=11 ORDER BY SiteSeries")
      stats::setNames(as.character(rows$SiteSeries), paste0(rows$SiteSeries, " - ", rows$SiteSeriesLongName))
    }, error = function(e) character())
    update_bec <- function(selected) {
      choices <- c(setNames("", ""), bec_choices)
      if (nzchar(selected) && !selected %in% choices) choices <- c(choices, stats::setNames(selected, selected))
      updateSelectizeInput(session, "BECSiteUnit", choices = choices, selected = selected, server = TRUE)
    }

    dyn_choices <- local({
      make <- function(list_name) {
        res <- tryCatch(
          {
            DBI::dbGetQuery(
              con,
              glue::glue_sql(
                "SELECT ListValue FROM lists.{`list_name`} ORDER BY SortOrder, ListValue",
                .con = con
              )
            )$ListValue
          },
          error = function(e) character(0)
        )
        c("", res)
      }
      list(
        SurfaceTopography = make("SurfaceTopography"),
        SurfaceTopographySize = make("SurfaceTopographySize"),
        MoistureRegime = make("MoistureRegime"),
        NutrientRegime = make("NutrientRegime"),
        SuccessionalStatus = make("SuccessionalStatus"),
        StructuralStage = make("StructuralStage"),
        Ecosection = make("Ecosection"),
        Zone = make("Zone"),
        FSRegionDistrict = make("Region"),
        RealmClass = make("RealmClass"),
        TransDistrib = make("TransDistrib"),
        SitePlotQuality = make("PlotQualitySite"),
        VegPlotQuality = make("PlotQualitySite"),
        SoilPlotQuality = make("PlotQualitySite"),
        Exposure1 = make("Exposure"),
        Exposure2 = make("Exposure"),
        SiteDisturbance1 = make("SiteDisturbance"),
        SiteDisturbance2 = make("SiteDisturbance"),
        SiteDisturbance3 = make("SiteDisturbance"),
        BedrockGeology1 = make("BedrockType"),
        BedrockGeology2 = make("BedrockType"),
        BedrockGeology3 = make("BedrockType"),
        CoarseFragLith1 = make("BedrockType"),
        CoarseFragLith2 = make("BedrockType"),
        CoarseFragLith3 = make("BedrockType"),
        SoilClassSubGroup = make("SoilClassSubgroup"),
        SoilClassGroup = make("SoilClassGroup"),
        HumusForm = make("HumusForm"),
        HumusFormPhase = make("HumusFormPhase"),
        SoilDrainage = make("SoilDrainage"),
        RootRestrictingType = make("RootRestrictingType"),
        RootZoneParticleSize = make("RootZoneParticleSize"),
        WaterSource = make("WaterSource"),
        FloodingRegimeFreq = make("FloodingRegimeFreq"),
        FloodingRegimeDur = make("FloodingRegimeDur"),
        HydroGeoSystem = make("HydrogeoSystem"),
        HydroGeoSubSystem = make("HydrogeoSubsystem"),
        TerrainTextureSurf = make("TerrainTexture"),
        SurficialMaterialSurf = make("SurficialMaterial"),
        SurfaceExpSurf = make("SurfaceExp"),
        GeoMorProSurf = make("GeoMorPro"),
        TerrainTextureSubSurf = make("TerrainTexture"),
        SurficialMaterialSubSurf = make("SurficialMaterial"),
        SurfaceExpSubSurf = make("SurfaceExp"),
        GeoMorProSubSurf = make("GeoMorPro")
      )
    })

    rv <- reactiveValues(
      current_plot = NULL,
      env_row = NULL,
      veg_a = data.frame(),
      veg_c = data.frame(),
      veg_d = data.frame(),
      humus = data.frame(),
      mineral = data.frame(),
      audit = data.frame(),
      other = data.frame(),
      veg_other = data.frame(),
      cover_and_height = FALSE,
      allow_small_entry = FALSE,
      recordset = character(0),
      record_index = 0L,
      dirty = FALSE,
      search_last_plot = NULL
    )

    # Bootstrap's modal close event also covers Cancel buttons and the X button.
    # Keep confirmation state in sync with dialogs dismissed without a server action.
    modal_open <- shiny::reactiveVal(FALSE)
    observeEvent(input$fs882_modal_shown, { modal_open(TRUE) })
    observeEvent(input$fs882_modal_closed, {
      modal_open(FALSE)
      child_modal(NULL)
      delete_target(NULL)
      other_delete_id(NULL)
    })

    # -- Caption reflects Access Form_Open: "Project: X / SU Table: Y" --
    output$caption <- renderUI({
      project <- state$CurrProject %||% "None"
      su_table <- state$PrefSUTable %||% "None"
      tags$div(
        tags$h6(class = "mb-0", sprintf("Project: %s / SU Table: %s", project, su_table)),
      )
    })

    # Method: 0 = D.d, 1 = DM.m, 2 = DMS.s
    output$coord_row <- renderUI({
      switch(
        coord_method(),
        "0" = layout_columns(
          col_widths = c(6, 6),
          inline_label(textInput, ns("Latitude"), "Latitude"),
          inline_label(textInput, ns("Longitude"), "Longitude")
        ),
        "1" = layout_columns(
          col_widths = c(3, 3, 3, 3),
          inline_label(textInput, ns("LatD2"), "Lat D"),
          inline_label(textInput, ns("LatMD"), "Lat M.m"),
          inline_label(textInput, ns("LonD2"), "Lon D"),
          inline_label(textInput, ns("LonMD"), "Lon M.m")
        ),
        "2" = layout_columns(
          col_widths = c(2, 2, 2, 2, 2, 2),
          inline_label(textInput, ns("LatD"), "Lat D"),
          inline_label(textInput, ns("LatM"), "Lat M"),
          inline_label(textInput, ns("LatS"), "Lat S"),
          inline_label(textInput, ns("LonD"), "Lon D"),
          inline_label(textInput, ns("LonM"), "Lon M"),
          inline_label(textInput, ns("LonS"), "Lon S")
        )
      )
    })

    # -- Refresh metadata choices when the active project changes. --
    observe({
      state$CurrProject
      proj_choices <- tryCatch(
        {
          rows <- DBI::dbGetQuery(
            con,
            paste(
              "SELECT ProjectID, ProjectTitle FROM",
              as.character(app_project_table_sql(con, "Metadata", app_config_get("Current", "CurrProject"), prj = TRUE)),
              "ORDER BY ProjectID"
            )
          )
          names(rows) <- tolower(names(rows))
          if (nrow(rows)) {
            labels <- ifelse(is.na(rows$projecttitle) | !nzchar(trimws(rows$projecttitle)), rows$projectid, paste0(rows$projectid, " - ", rows$projecttitle))
            c(setNames("", ""), stats::setNames(rows$projectid, labels))
          } else {
            c("---" = "")
          }
        },
        error = function(e) c("---" = "")
      )
      selected <- if (project_matches()) as_text(draft()[["ProjectID"]] %||% input$ProjectID) else ""
      if (nzchar(selected) && !selected %in% proj_choices) proj_choices <- c(proj_choices, stats::setNames(selected, selected))
      updateSelectInput(session, "ProjectID", choices = proj_choices, selected = selected)
    }) |>
      bindEvent(state$CurrProject, ignoreInit = FALSE)

    output$site_picture <- renderUI({
      tags$div(
        class = "text-muted text-center p-3 border rounded",
        style = "min-height: 120px;",
        tags$small("Picture placeholder")
      )
    })

    output$VegPlotNumber <- renderText(rv$current_plot %||% "\u2014")

    # -- Populate dropdowns (once, using pre-loaded dyn_choices cache) --
    observe({
      for (id in names(dyn_choices)) {
        updateSelectInput(session, id, choices = dyn_choices[[id]])
      }
    }) |>
      bindEvent(TRUE, once = TRUE)

    # -- Assigned SU source dropdown (Access optAssignedSuSource) --
    observe({
      src <- as.integer(input$optAssignedSuSource %||% 1)
      choices <- tryCatch(
        {
          if (src == 1L) {
            rows <- DBI::dbGetQuery(
              con,
              paste(
                "SELECT DISTINCT UserSiteUnit FROM",
                admin_tb(con),
                "WHERE UserSiteUnit IS NOT NULL ORDER BY UserSiteUnit"
              )
            )
            c(setNames("", ""), stats::setNames(rows$UserSiteUnit, rows$UserSiteUnit))
          } else if (src == 2L) {
            rows <- DBI::dbGetQuery(
              con,
              paste(
                "SELECT SiteSeries, SiteSeriesLongName",
                "FROM MasterSiteUnitList",
                "WHERE Level = 11 AND SiteSeries IS NOT NULL ORDER BY SiteSeries"
              )
            )
            labels <- ifelse(is.na(rows$SiteSeriesLongName), rows$SiteSeries, paste0(rows$SiteSeries, " - ", rows$SiteSeriesLongName))
            c(setNames("", ""), stats::setNames(rows$SiteSeries, labels))
          } else if (src == 3L) {
            plotlist <- app_config_get("Current", "CurrPlotlist")
            if (is.null(plotlist) || plotlist == "None") {
              show_toast(toast("Select an SU table first.", type = "warning"))
              c("---" = "")
            } else {
              su_tbl <- as.character(app_project_table_sql(con, "SU", plotlist, prj = TRUE))
              rows <- DBI::dbGetQuery(
                con,
                paste(
                  "SELECT DISTINCT SiteUnit FROM",
                  su_tbl,
                  "WHERE SiteUnit IS NOT NULL ORDER BY SiteUnit"
                )
              )
              c(setNames("", ""), stats::setNames(rows$SiteUnit, rows$SiteUnit))
            }
          } else {
            c("---" = "")
          }
        },
        error = function(e) c("---" = "")
      )
      selected <- if (project_matches()) as_text(draft()[["UserSiteUnit"]] %||% input$UserSiteUnit) else ""
      if (nzchar(selected) && !selected %in% choices) choices <- c(choices, selected)
      updateSelectInput(session, "UserSiteUnit", choices = choices, selected = selected)
    }) |>
      bindEvent(list(input$optAssignedSuSource, rv$current_plot, state$CurrProject), ignoreInit = FALSE)

    # -- SubZone depends on Zone (Access SubZone_GotFocus -> SubZoneList) --
    observe({
      zone <- input$Zone
      if (is.null(zone) || !nzchar(zone)) {
        return()
      }
      rows <- tryCatch(
        DBI::dbGetQuery(
          con,
          paste(
            "SELECT DISTINCT item FROM VLists.USysTableOfLists",
            "WHERE lower(listname) = 'subzone'",
            "AND lower(parentvalue) = lower(?)",
            "ORDER BY item"
          ),
          params = list(zone)
        ),
        error = function(e) data.frame()
      )
      choices <- if (nrow(rows)) c(setNames("", ""), stats::setNames(rows$item, rows$item)) else c("---" = "")
      selected <- if (project_matches()) as_text(draft()[["SubZone"]] %||% input$SubZone) else ""
      if (nzchar(selected) && !selected %in% choices) choices <- c(choices, selected)
      updateSelectInput(session, "SubZone", choices = choices, selected = selected)
    }) |>
      bindEvent(list(input$Zone, rv$current_plot), ignoreInit = TRUE)

    # -- SiteSeries depends on Zone + SubZone --
    observe({
      zone <- input$Zone
      subzone <- input$SubZone
      if (is.null(zone) || !nzchar(zone)) {
        return()
      }
      filter_val <- paste0(zone, subzone)
      rows <- tryCatch(
        DBI::dbGetQuery(
          con,
          paste(
            "SELECT DISTINCT SiteSeriesNo, siteseries",
            "FROM VLists.USysSiteSeriesNames",
            "WHERE lower(BEC) = lower(?)",
            "ORDER BY SiteSeriesNo"
          ),
          params = list(filter_val)
        ),
        error = function(e) data.frame()
      )
      if (nrow(rows)) {
        labels <- paste0(rows$SiteSeriesNo, " - ", rows$siteseries)
        choices <- c(setNames("", ""), stats::setNames(rows$SiteSeriesNo, labels))
      } else {
        choices <- c("---" = "")
      }
      selected <- if (project_matches()) as_text(draft()[["SiteSeries"]] %||% input$SiteSeries) else ""
      if (nzchar(selected) && !selected %in% choices) choices <- c(choices, selected)
      updateSelectInput(session, "SiteSeries", choices = choices, selected = selected)
    }) |>
      bindEvent(list(input$Zone, input$SubZone, rv$current_plot), ignoreInit = TRUE)

    # -- Child lists are canonical project rows, never the attached display views. --
    refresh_vegetation <- function(plot_id) {
      rows <- vpro::vpro_plot_vegetation_list(context, plot_id)
      names(rows) <- tolower(names(rows))
      covers <- intersect(c("cover1", "cover2", "cover3", "cover4", "cover5", "totala", "totalb"), names(rows))
      a <- if (length(covers)) rowSums(!is.na(rows[, covers, drop = FALSE])) > 0 else rep(FALSE, nrow(rows))
      c <- if ("cover6" %in% names(rows)) !is.na(rows$cover6) else rep(FALSE, nrow(rows))
      dcols <- intersect(c("cover7", "cover8", "cover9"), names(rows))
      d <- if (length(dcols)) rowSums(!is.na(rows[, dcols, drop = FALSE])) > 0 else rep(FALSE, nrow(rows))
      # Rows with no cover yet must remain visible and editable.
      layer <- if ("layer" %in% names(rows)) toupper(as.character(rows$layer)) else rep("", nrow(rows))
      c <- c | (!a & !d & layer == "C")
      d <- d | (!a & !c & layer == "D")
      rv$veg_a <- rows[a | !(a | c | d), , drop = FALSE]
      rv$veg_c <- rows[c & !a, , drop = FALSE]
      rv$veg_d <- rows[d & !a & !c, , drop = FALSE]
      rv$veg_other <- rows
      selected_veg(NULL)
    }
    refresh_child <- function(kind, plot_id = rv$current_plot) {
      rows <- switch(kind,
        humus = vpro::vpro_plot_humus_list(context, plot_id),
        mineral = vpro::vpro_plot_mineral_list(context, plot_id),
        other = vpro::vpro_plot_other_list(context, plot_id),
        veg = return(refresh_vegetation(plot_id)))
      names(rows) <- tolower(names(rows))
      rv[[kind]] <- rows
    }
    load_plot <- function(plot_id, plot = vpro::vpro_plot_get(context, plot_id)) {
      if (is.null(plot_id) || !nzchar(trimws(plot_id))) {
        return()
      }
      plot_id <- trimws(plot_id)
      rv$current_plot <- plot_id

      # Canonical pair; failures do not reset the draft or change the picker.
      rv$env_row <- plot$env
      baseline(plot)
      populate_env_fields(plot)

      # Child grids refresh independently of the plot-wide draft.
      refresh_vegetation(plot_id)

      for (kind in c("humus", "mineral", "other")) refresh_child(kind, plot_id)
      rv$audit <- vpro::vpro_plot_audit_list(context, plot_id)
      other_index(1L)
      other_values(NULL)
      other_dirty(FALSE)
    }

    # Programmatic updates are queued by Shiny. Keep a per-field pending value
    # until the client acknowledges it; a user edit after that is never swallowed.
    pending <- new.env(parent = emptyenv())
    baseline <- shiny::reactiveVal(NULL)
    touched <- shiny::reactiveVal(character())
    draft <- shiny::reactiveVal(list())
    types <- shiny::reactiveVal(NULL)
    mapping <- shiny::reactiveVal(NULL)
    coord_method <- shiny::reactiveVal("0")
    coord_errors <- shiny::reactiveVal(list())
    draft_project <- shiny::reactiveVal(NULL)
    draft_path <- shiny::reactiveVal(NULL)
    coords <- shiny::reactiveVal(c(Latitude = NA_real_, Longitude = NA_real_))
    loading <- shiny::reactiveVal(FALSE)
    track <- function(id, value) {
      assign(id, value, envir = pending)
      invisible(value)
    }
    field_types <- function(plot) {
      db <- DBI::dbConnect(RSQLite::SQLite(), context$active$path)
      on.exit(DBI::dbDisconnect(db))
      lapply(c(env = "Env", admin = "Admin"), function(kind) {
        table <- paste0(context$active$project, "_", kind)
        info <- DBI::dbGetQuery(db, paste0("PRAGMA table_info(", DBI::dbQuoteString(db, table), ")"))
        stats::setNames(info$type, info$name)
      })
    }
    display_value <- function(value, id) {
      if (id %in% fs882_plot_boolean) return(isTRUE(as.logical(value)))
      if (id == "Date") return(if (length(value) == 0L || is.na(value)) as.Date(NA) else as.Date(value))
      if (length(value) == 0L || is.na(value)) return("")
      as.character(value)
    }
    set_field <- function(id, value) {
      track(id, value)
      if (id %in% fs882_plot_boolean) updateCheckboxInput(session, id, value = value)
      else if (id == "Date") {
        if (is.na(value)) session$sendInputMessage(id, list(value = ""))
        else updateDateInput(session, id, value = value)
      }
      else if (id == "BECSiteUnit") update_bec(value)
      else if (id %in% c(names(dyn_choices), "UserSiteUnit", "ProjectID")) {
        if (id %in% names(dyn_choices)) {
          choices <- dyn_choices[[id]]
          if (nzchar(value) && !value %in% choices) choices <- c(choices, value)
          updateSelectInput(session, id, choices = choices, selected = value)
        } else updateSelectInput(session, id, selected = value)
      } else if (id %in% c("Location", "PlotRepresenting", "SiteNotes", "OfficeNotes", "VegNotes", "SoilNotes"))
        updateTextAreaInput(session, id, value = value)
      else updateTextInput(session, id, value = value)
    }
    set_coord_fields <- function(lat, lon, method) {
      if (method == "0") {
        values <- list(Latitude = if (is.na(lat)) "" else as.character(lat),
                       Longitude = if (is.na(lon)) "" else as.character(lon))
      } else {
        lat_parts <- fs882_decompose_coord(lat, method)
        lon_parts <- fs882_decompose_coord(lon, method)
        ids <- if (method == "1") c("LatD2", "LatMD", "LonD2", "LonMD") else c("LatD", "LatM", "LatS", "LonD", "LonM", "LonS")
        values <- stats::setNames(as.list(c(lat_parts, lon_parts)), ids)
      }
      for (id in names(values)) set_field(id, values[[id]])
    }
    populate_env_fields <- function(plot) {
      loading(TRUE)
      on.exit(loading(FALSE))
      map <- fs882_field_map(plot)
      mapping(map)
      types(field_types(plot))
      missing <- names(map)[vapply(map, is.null, logical(1))]
      if (length(missing)) show_toast(toast(paste("Unmapped plot fields (not saveable):", paste(missing, collapse = ", ")), type = "warning"))
      coord_errors(list())
      for (id in ls(pending, all.names = TRUE)) rm(list = id, envir = pending)
      draft_project(context$active$project)
      draft_path(context$active$path)
      values <- list()
      for (id in names(map)) {
        target <- map[[id]]
        if (is.null(target)) next
        value <- display_value(plot[[target$table]][[target$column]][[1L]], id)
        values[[id]] <- value
        if (!id %in% c("Latitude", "Longitude")) set_field(id, value)
      }
      draft(values)
      touched(character())
      set_field("PlotNumber", rv$current_plot)
      shinyjs::disable("PlotNumber")
      coords(c(Latitude = as.numeric(plot$env$Latitude[[1L]]), Longitude = as.numeric(plot$env$Longitude[[1L]])))
      set_coord_fields(coords()[["Latitude"]], coords()[["Longitude"]], coord_method())
    }

    # Preserve latest user input independently of reactive load and server updates.
    for (field_id in fs882_plot_fields) local({
      id <- field_id
      observeEvent(input[[id]], {
        value <- input[[id]]
        if (exists(id, envir = pending, inherits = FALSE)) {
          expected <- get(id, envir = pending)
          if (identical(as.character(value), as.character(expected))) {
            rm(list = id, envir = pending)
            return()
          }
          rm(list = id, envir = pending)
        }
        if (is.null(baseline()) || loading()) return()
        d <- draft(); d[[id]] <- value; draft(d)
        touched(union(touched(), id))
        if (id %in% c("Latitude", "Longitude")) {
          result <- tryCatch(fs882_field_value(value, "REAL", id), error = function(e) e)
          errors <- coord_errors()
          if (inherits(result, "error")) errors[[id]] <- conditionMessage(result)
          else {
            errors[[id]] <- NULL
            xy <- coords(); xy[[id]] <- result; coords(xy)
          }
          coord_errors(errors)
        }
      }, ignoreInit = TRUE)
    })
    component_ids <- c("LatD2", "LatMD", "LonD2", "LonMD", "LatD", "LatM", "LatS", "LonD", "LonM", "LonS")
    for (field_id in component_ids) local({
      id <- field_id
      observeEvent(input[[id]], {
        value <- input[[id]]
        if (exists(id, envir = pending, inherits = FALSE)) {
          expected <- get(id, envir = pending)
          rm(list = id, envir = pending)
          if (identical(as.character(value), as.character(expected))) return()
        }
        if (is.null(baseline()) || loading()) return()
        d <- draft(); d[[id]] <- value
        method <- coord_method()
        if (method == "0") return()
        pairs <- fs882_coord_parts(method)
        if (id %in% unlist(pairs)) {
          axis <- names(pairs)[vapply(pairs, function(x) id %in% x, logical(1))]
          parts <- lapply(pairs[[axis]], function(x) d[[x]] %||% input[[x]])
          result <- fs882_coord_result(parts)
          errors <- coord_errors(); errors[[axis]] <- result$error; coord_errors(errors)
          if (is.null(result$error)) {
            xy <- coords(); xy[[axis]] <- result$value; coords(xy)
            d[[axis]] <- result$value
          }
          draft(d)
          touched(union(touched(), axis))
        }
      }, ignoreInit = TRUE)
    })
    observeEvent(input$optCoordMethod, {
      method <- input$optCoordMethod %||% "0"
      if (identical(method, coord_method())) return()
      # Do not tear down component controls containing invalid input.
      if (length(coord_errors())) {
        show_toast(toast("Correct or discard invalid coordinates before changing method.", type = "warning"))
        updateRadioButtons(session, "optCoordMethod", selected = coord_method())
        return()
      }
      xy <- coords()
      if (!is.null(baseline()) && coord_method() != "0") {
        ids <- fs882_coord_parts(coord_method())
        d <- draft(); errors <- list()
        for (axis in names(ids)) {
          # Untouched, just-rendered components may not yet have reached Shiny.
          if (!axis %in% touched()) next
          parts <- lapply(ids[[axis]], function(x) d[[x]] %||% input[[x]])
          result <- fs882_coord_result(parts)
          if (!is.null(result$error)) errors[[axis]] <- result$error
          else { xy[[axis]] <- result$value; d[[axis]] <- result$value }
        }
        if (length(errors)) {
          coord_errors(errors)
          show_toast(toast("Invalid coordinates: correct or discard before changing method.", type = "danger"))
          updateRadioButtons(session, "optCoordMethod", selected = coord_method())
          return()
        }
        draft(d); coords(xy)
      }
      coord_method(method)
      app_config_set("Current", "CoordMethod", method)
      if (!is.null(baseline())) session$onFlushed(function() set_coord_fields(xy[["Latitude"]], xy[["Longitude"]], method), once = TRUE)
    }, ignoreInit = FALSE)

    # ============================================================
    # Record Navigator Wiring
    # ============================================================

    # -- Record count display --
    output$navRecordCount <- renderText({
      n <- length(rv$recordset)
      idx <- rv$record_index
      if (n == 0) "0 of 0" else paste(idx, "of", n)
    })

    refresh_picker <- function(selected = rv$current_plot) {
      rs <- vpro::vpro_plot_list(context)
      rv$recordset <- rs
      index <- if (is.null(selected) || !length(selected)) NA_integer_ else match(selected, rs)
      rv$record_index <- if (length(index) != 1L || is.na(index)) 0L else index
      updateSelectizeInput(session, "navPlotPicker", choices = stats::setNames(rs, rs),
                           selected = selected %||% "", server = FALSE)
    }
    observeEvent(TRUE, {
      tryCatch({
        refresh_picker()
        if (length(rv$recordset)) navigate_to(rv$recordset[[1L]])
      }, error = function(e) show_toast(toast(conditionMessage(e), type = "danger")))
    }, once = TRUE)

    # Never silently drop touched fields lacking a canonical mapping.
    changes <- function() fs882_field_changes(draft()[intersect(names(draft()), touched())], baseline(), mapping(), types())
    dirty_ids <- function() {
      if (is.null(baseline())) return(character())
      ids <- touched()
      d <- draft(); m <- mapping()
      ids[vapply(ids, function(id) {
        target <- m[[id]]
        if (is.null(target) || is.null(d[[id]])) return(TRUE)
        before <- baseline()[[target$table]][[target$column]][[1L]]
        after <- tryCatch(fs882_field_value(d[[id]], types()[[target$table]][[target$column]], id), error = function(e) e)
        inherits(after, "error") || !fs882_same_value(before, after, id)
      }, logical(1))]
    }
    project_matches <- function() fs882_project_matches(context, draft_project(), draft_path(), state$CurrProject)
    observeEvent(state$CurrProject, {
      if (is.null(draft_project()) || project_matches()) return()
      show_toast(toast("Project changed: old plot draft is unavailable here. No plot writes will be made; return to the original project or discard.", type = "danger"))
    }, ignoreInit = TRUE)
    observe({
      ids <- dirty_ids()
      session$sendCustomMessage("fs882-dirty", list(ns = ns(""), ids = ids))
    })
    save_draft <- function() {
      if (!project_matches() || is.null(rv$current_plot) || is.null(baseline()) ||
          !identical(as.character(baseline()$env$PlotNumber[[1L]]), rv$current_plot)) {
        show_toast(toast("Plot/project identity changed. Discard this draft; no write attempted.", type = "danger"))
        return(FALSE)
      }
      if (length(coord_errors())) {
        show_toast(toast(paste("Invalid coordinates:", paste(names(coord_errors()), unlist(coord_errors()), collapse = "; ")), type = "danger"))
        return(FALSE)
      }
      if (!length(dirty_ids())) return(TRUE)
      unmapped <- touched()[vapply(touched(), function(id) is.null(mapping()[[id]]), logical(1))]
      if (length(unmapped)) {
        show_toast(toast(paste("Unmapped edited fields:", paste(unmapped, collapse = ", ")), type = "danger"))
        return(FALSE)
      }
      if (isTRUE(input$optLockData)) {
        show_toast(toast("Unlock the plot before saving.", type = "warning"))
        return(FALSE)
      }
      tryCatch({
        changed <- changes()
        if (!project_matches()) stop("Project changed before save; no write attempted.")
        if (length(changed$env) + length(changed$admin))
          vpro::vpro_plot_update(context, rv$current_plot, env = changed$env, admin = changed$admin,
                                 user = state$User)
        # Keep untouched and unsaved controls intact. Never clear a dirty field
        # merely because another field was written to the same table.
        latest <- vpro::vpro_plot_get(context, rv$current_plot)
        if (!project_matches() || !identical(as.character(latest$env$PlotNumber[[1L]]), rv$current_plot))
          stop("Plot/project changed during save; draft retained.")
        saved <- fs882_saved_fields(touched(), draft(), latest, mapping(), types())
        baseline(latest)
        d <- draft()
        for (id in saved) {
          target <- mapping()[[id]]
          d[[id]] <- display_value(latest[[target$table]][[target$column]][[1L]], id)
        }
        draft(d)
        touched(setdiff(touched(), saved))
        if (length(dirty_ids())) {
          show_toast(toast(paste("Fields not confirmed saved:", paste(dirty_ids(), collapse = ", ")), type = "danger"))
          return(FALSE)
        }
        show_toast(toast("FS882 record saved.", type = "success"))
        TRUE
      }, error = function(e) {
        show_toast(toast(paste("Save failed:", conditionMessage(e)), type = "danger"))
        FALSE
      })
    }
    navigate_to <- function(plot_id) {
      if (isTRUE(other_dirty()) || !is.null(child_modal()) || !is.null(delete_target()) || !is.null(other_delete_id())) {
        show_toast(toast("Save or Discard Other changes and close child actions before changing plots.", type = "warning"))
        updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot %||% "")
        return(invisible(FALSE))
      }
      if (!is.null(draft_project()) && !project_matches()) {
        show_toast(toast("Project changed: discard the old draft before loading a plot.", type = "danger"))
        return(invisible(FALSE))
      }
      if (is.null(plot_id) || !plot_id %in% rv$recordset) return(invisible(FALSE))
      plot <- tryCatch(vpro::vpro_plot_get(context, plot_id), error = function(e) e)
      if (inherits(plot, "error")) {
        show_toast(toast(conditionMessage(plot), type = "danger"))
        updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot %||% "")
        return(invisible(FALSE))
      }
      rv$current_plot <- plot_id
      rv$record_index <- match(plot_id, rv$recordset)
      updateSelectizeInput(session, "navPlotPicker", selected = plot_id)
      load_plot(plot_id, plot)
      state$CurrSU <- plot_id
      invisible(TRUE)
    }
    pending_navigation <- shiny::reactiveVal(NULL)
    request_navigation <- function(target) {
      if (isTRUE(other_dirty()) || !is.null(child_modal()) || !is.null(delete_target()) || !is.null(other_delete_id())) {
        show_toast(toast("Save or Discard Other changes and close child actions before changing plots.", type = "warning"))
        updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot %||% "")
        return()
      }
      if (!project_matches()) {
        show_toast(toast("Project changed: discard the old plot draft first.", type = "danger"))
        updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot)
        return()
      }
      if (identical(target, rv$current_plot)) return()
      if (!length(dirty_ids()) && !length(coord_errors())) {
        if (identical(target, "<new>")) show_new() else navigate_to(target)
        return()
      }
      pending_navigation(target)
      if (!identical(target, "<new>")) updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot)
      showModal(modalDialog(title = "Unsaved plot changes", "Save changes before leaving this plot?",
        footer = tagList(actionButton(ns("navSave"), "Save", class = "btn-primary"),
                         actionButton(ns("navDiscard"), "Discard"),
                         actionButton(ns("navStay"), "Stay")), easyClose = FALSE))
    }
    complete_navigation <- function() {
      target <- pending_navigation()
      if (is.null(target) || isTRUE(other_dirty()) || !is.null(child_modal())) {
        show_toast(toast("Close the child editor and save or discard Other changes first.", type = "warning"))
        return()
      }
      pending_navigation(NULL); removeModal()
      if (identical(target, "<new>")) show_new() else navigate_to(target)
    }
    observeEvent(input$navSave, {
      if (save_draft() && !length(dirty_ids()) && !length(coord_errors())) complete_navigation()
      else show_toast(toast("Unsaved plot fields remain; navigation blocked.", type = "warning"))
    })
    observeEvent(input$navDiscard, {
      if (!project_matches()) {
        pending_navigation(NULL); removeModal()
        show_toast(toast("Project changed; old draft not written. Use Discard to reload the active project.", type = "warning"))
      } else complete_navigation()
    })
    observeEvent(input$navStay, { pending_navigation(NULL); removeModal(); updateSelectizeInput(session, "navPlotPicker", selected = rv$current_plot) })
    observeEvent(input$btnNavFirst, { if (length(rv$recordset)) request_navigation(rv$recordset[[1L]]) })
    observeEvent(input$btnNavLast, { if (length(rv$recordset)) request_navigation(tail(rv$recordset, 1L)) })
    observeEvent(input$btnNavPrev, { if (rv$record_index > 1L) request_navigation(rv$recordset[[rv$record_index - 1L]]) })
    observeEvent(input$btnNavNext, { if (rv$record_index < length(rv$recordset)) request_navigation(rv$recordset[[rv$record_index + 1L]]) })
    observeEvent(input$navPlotPicker, {
      if (!identical(input$navPlotPicker, rv$current_plot) && input$navPlotPicker %in% rv$recordset)
        request_navigation(input$navPlotPicker)
    }, ignoreInit = TRUE)
    show_new <- function() showModal(modalDialog(title = "New Record",
      textInput(ns("new_plot_number"), "Plot Number"),
      footer = tagList(actionButton(ns("btnConfirmNewRecord"), "Create", class = "btn-primary"), modalButton("Cancel"))))
    observeEvent(input$btnNavNew, { request_navigation("<new>") })
    observeEvent(input$btnConfirmNewRecord, {
      if (!project_matches() || length(dirty_ids()) || length(coord_errors())) {
        show_toast(toast("Discard or save the current plot in its original project before creating another.", type = "danger"))
        return()
      }
      new_id <- trimws(input$new_plot_number %||% "")
      tryCatch({
        vpro::vpro_plot_create(context, new_id)
        refresh_picker(new_id)
        removeModal()
        navigate_to(new_id)
        show_toast(toast(paste("Created plot", new_id), type = "success"))
      }, error = function(e) show_toast(toast(paste("Create failed:", conditionMessage(e)), type = "danger")))
    })
    observeEvent(input$nav_search_trigger, {
      query <- trimws(input$nav_search_trigger$query %||% "")
      if (!nzchar(query)) return()
      hits <- rv$recordset[grepl(query, rv$recordset, fixed = TRUE, ignore.case = TRUE)]
      if (!length(hits)) {
        show_toast(toast("No matching plot number.", type = "warning"))
        return()
      }
      idx <- match(rv$current_plot, hits)
      target <- hits[[if (is.na(idx) || idx == length(hits)) 1L else idx + 1L]]
      request_navigation(target)
    })

    # -- Lock data toggle (Access optLockData) --
    observeEvent(
      input$optLockData,
      {
        locked <- isTRUE(input$optLockData)
        # All text/select/textarea environment field IDs
        env_field_ids <- c(
          "PlotNumber",
          "FieldNumber",
          "Date",
          "StartDate",
          "SiteSurveyor",
          "Location",
          "UTMEasting",
          "UTMNorthing",
          "UTMZone",
          "LocationAccuracy",
          "NtsMapSheet",
          "Elevation",
          "SlopeGradient",
          "Aspect",
          "AirPhotoNum",
          "Photo",
          "PlotRepresenting",
          "MapUnit",
          "StandAge",
          "SiteNotes",
          "OfficeNotes",
          "SoilSurveyor",
          "RootingDepth",
          "RootRestrictingDepth",
          "SeepageDepth",
          "StrataCoverTree",
          "StrataCoverShrub",
          "StrataCoverHerb",
          "StrataCoverMoss",
          "VegNotes",
          "SoilNotes",
          "SpeciesListComplete",
          "SubstrateOrganicMatter",
          "SubstrateDecWood",
          "SubstrateBedRock",
          "SubstrateRocks",
          "SubstrateMineralSoil",
          "SubstrateWater",
          "Latitude",
          "Longitude",
          "LatD2",
          "LatMD",
          "LonD2",
          "LonMD",
          "LatD",
          "LatM",
          "LatS",
          "LonD",
          "LonM",
          "LonS",
          "MesoSlopePosition",
          "SurfaceShape",
          "SurfaceTopographyType",
          "SurfaceTopographySize",
          "MoistureRegime",
          "NutrientRegime",
          "SuccessionalStatus",
          "StructuralStage",
          "Ecosection",
          "Zone",
          "SubZone",
          "SiteSeries",
          "BECSiteUnit",
          "UserSiteUnit",
          "SitePlotQuality",
          "VegPlotQuality",
          "SoilPlotQuality",
          "Exposure1",
          "Exposure2",
          "SiteDisturbance1",
          "SiteDisturbance2",
          "SiteDisturbance3",
          "RealmClass",
          "TransDistrib",
          "FSRegionDistrict",
          "BedrockGeology1",
          "CoarseFragLith1",
          "SoilClassSubGroup",
          "SoilClassGroup",
          "HumusForm",
          "SoilDrainage",
          "RootRestrictingType",
          "WaterSource",
          "FloodingRegimeFreq"
        )
        toggle_fn <- if (locked) shinyjs::disable else shinyjs::enable
        for (fid in env_field_ids) {
          toggle_fn(fid)
        }
        # Also toggle save button
        shinyjs::disable("PlotNumber") # immutable key: never silently renumber
        if (locked) shinyjs::disable("btnSaveRecord") else shinyjs::enable("btnSaveRecord")
      },
      ignoreInit = TRUE
    )

    observeEvent(input$btnSaveRecord, { save_draft() })
    observeEvent(input$btnDiscardRecord, {
      if (isTRUE(other_dirty()) || !is.null(child_modal()) || !is.null(delete_target()) || !is.null(other_delete_id())) {
        show_toast(toast("Save or Discard Other changes and close child actions first.", type = "warning"))
        return()
      }
      pending_navigation(NULL); removeModal()
      if (!project_matches()) {
        show_toast(toast("Discarding the draft from the previous project without writing it.", type = "warning"))
        # Explicit discard only: never use the stale recordset with a new project.
        baseline(NULL); draft(list()); touched(character()); coord_errors(list())
        draft_project(NULL); draft_path(NULL); rv$current_plot <- NULL
        tryCatch({
          refresh_picker(NULL)
          if (length(rv$recordset)) navigate_to(rv$recordset[[1L]])
        }, error = function(e) show_toast(toast(conditionMessage(e), type = "danger")))
      } else if (!is.null(rv$current_plot)) navigate_to(rv$current_plot)
    })
    observeEvent(input$optProjectID, {
      app_config_set("Current", "ProjectIdSource", input$optProjectID)
    }, ignoreInit = TRUE)

    # -- SU source changed (Access optAssignedSuSource_AfterUpdate saves record) --
    observeEvent(
      input$optAssignedSuSource,
      {
        app_config_set("Current", "AssignedSuSource", input$optAssignedSuSource)
      },
      ignoreInit = TRUE
    )

    # -- Audit strength --
    observeEvent(
      input$optAuditStrength,
      {
        app_config_set("Audit", "AuditStrength", input$optAuditStrength)
      },
      ignoreInit = TRUE
    )

    # -- Copy to Working Unit (Access btnCoptToWorkingUnit) --
    observeEvent(input$btnCopyToUserSU, {
      bec_val <- input$BECSiteUnit
      if (is.null(bec_val) || !nzchar(bec_val)) {
        show_toast(toast("No BEC Master unit to copy.", type = "warning"))
        return()
      }
      if (!project_matches() || is.null(baseline())) {
        show_toast(toast("Project changed; discard the old draft first.", type = "danger"))
        return()
      }
      d <- draft(); d[["UserSiteUnit"]] <- bec_val; draft(d)
      touched(union(touched(), "UserSiteUnit"))
      updateSelectInput(session, "UserSiteUnit", choices = c(setNames("", ""), stats::setNames(bec_val, bec_val)), selected = bec_val)
      track("UserSiteUnit", bec_val)
    })

    # -- Cover & Height toggle --
    observeEvent(input$btnCoverAndHeight, {
      rv$cover_and_height <- !rv$cover_and_height
      # Mirror Access: button caption shows the mode you will SWITCH TO next
      shiny::updateActionButton(session, "btnCoverAndHeight", label = if (rv$cover_and_height) "Cover Only" else "Cover & Height")
    })

    # -- Check Species Codes (Access btnCheckSppCodes -> CheckSpeciesCodes module) --
    observeEvent(input$btnCheckSppCodes, {
      plot_id <- rv$current_plot
      if (is.null(plot_id) || !nzchar(plot_id %||% "")) {
        show_toast(toast("No current plot loaded.", type = "warning"))
        return()
      }
      # Access calls CheckSpeciesCodes from V7mdlSpellCheckSppCodes module;
      # full species-validation dialog is deferred. Show a stub notification.
      show_toast(toast("Check Spp Codes: species validation deferred (hookup pending).", type = "success", duration_s = 5))
    })

    # -- Allow <0.1% Entry toggle (Access btnAllowSmallEntry) --
    # Controls whether sub-1% cover values (0.01-0.09) are accepted in veg grids.
    observeEvent(input$btnAllowSmallEntry, {
      rv$allow_small_entry <- !rv$allow_small_entry
      show_toast(toast(
        if (rv$allow_small_entry) "Allow <0.1% entry ON" else "Allow <0.1% entry OFF",
        type = "success"
      ))
    })

    # Species creation uses the same buffered child editor as the other grids.
    observeEvent(input$btnAddSpp, { open_child("veg") })

    # -- Edit Metadata (Access btnLoadMetadata -> frmProjectMetaData) --
    observeEvent(input$btnLoadMetadata, {
      # Pass current plot's ProjectID (from Sample_Env row) so metadata opens on the right record
      proj_id <- trimws(as.character(
        rv$env_row[["projectid"]] %||% rv$env_row[["ProjectID"]] %||% ""
      ))
      metadata_plot_project_id(proj_id)
      metadata_open_trigger(metadata_open_trigger() + 1L)
      showModal(modalDialog(
        title = "Project Metadata",
        size = "xl",
        easyClose = FALSE,
        mod_project_metadata_ui(ns("meta_editor")),
        footer = modalButton("Close")
      ))
    })

    # -- Picture Manager (Access btnManagePictures) --
    observeEvent(input$btnManagePictures, {
      showModal(modalDialog(
        title = "Plot Pictures",
        size = "xl",
        easyClose = TRUE,
        mod_images_ui(ns("pic_manager")),
        footer = modalButton("Close")
      ))
    })

    # -- Google Earth KML download (Access SinglePlotPlotInGE) --
    output$dlGoogleEarth <- downloadHandler(
      filename = function() {
        paste0("VProPlot_", rv$current_plot %||% "unknown", ".kml")
      },
      content = function(file) {
        plot_id <- rv$current_plot
        if (is.null(plot_id) || !nzchar(plot_id)) {
          show_toast(toast("No current plot to export.", type = "warning"))
          return()
        }
        kml <- generate_single_plot_kml(con, plot_id)
        if (is.null(kml)) {
          show_toast(toast("Plot has no coordinates - cannot export to KML.", type = "warning"))
          writeLines("", file)
          return()
        }
        writeLines(kml, file)
      },
      contentType = "application/vnd.google-earth.kml+xml"
    )

    # -- Footer buttons --
    observeEvent(input$btnAudit, {
      nav_select(ns("tabPages"), "Audit", session = session)
    })

    observeEvent(input$btnSuIntoEnv, {
      showModal(modalDialog(
        title = "SU Into Env",
        "This action will modify the current environment table ",
        "by copying SiteUnit from the SU table into Env.UserSiteUnit. Continue?",
        footer = tagList(
          actionButton(ns("btnConfirmSuIntoEnv"), "Continue", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmSuIntoEnv, {
      removeModal()
      result <- su_su_into_env(con)
      show_toast(toast(result$message, type = if (result$ok) "success" else "danger"))
      if (result$ok) load_plot(rv$current_plot)
    })

    observeEvent(input$btnEnvIntoSu, {
      showModal(modalDialog(
        title = "Env Into SU",
        "This action will modify the current site unit table ",
        "by copying Env.UserSiteUnit into the SU table. Continue?",
        footer = tagList(
          actionButton(ns("btnConfirmEnvIntoSu"), "Continue", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmEnvIntoSu, {
      removeModal()
      result <- su_env_into_su(con)
      if (result$ok && nrow(result$new_units)) {
        showModal(modalDialog(
          title = "New Site Units Found",
          paste0(nrow(result$new_units), " site units in your Env table are not in the master list. ", "Add them to your personal site unit list?"),
          footer = tagList(
            actionButton(ns("btnAddUserUnits"), "Add Units", class = "btn-primary"),
            modalButton("Skip")
          )
        ))
      } else {
        show_toast(toast(result$message, type = if (result$ok) "success" else "danger"))
      }
    })

    observeEvent(input$btnAddUserUnits, {
      removeModal()
      result <- su_env_into_su(con)
      if (nrow(result$new_units)) {
        su_add_user_units(con, result$new_units)
        show_toast(toast(
          paste0(nrow(result$new_units), " units added to personal list."),
          type = "success"
        ))
      }
    })

    observeEvent(input$btnCreateSuFromFilter, {
      # Collect plot numbers from current form view (all loaded env plots)
      env_tbl <- env_tb(con)
      all_plots <- tryCatch(
        DBI::dbGetQuery(con, paste("SELECT plotnumber FROM", env_tbl, "ORDER BY plotnumber"))$plotnumber,
        error = function(e) character(0)
      )
      if (!length(all_plots)) {
        show_toast(toast("No plots in current project.", type = "warning"))
        return()
      }
      showModal(modalDialog(
        title = "Create SU From Filter",
        p(paste0(length(all_plots), " plots in current project.")),
        radioButtons(
          ns("create_su_action"),
          "Action",
          choices = c("Create new SU table" = "create", "Modify current SU table" = "modify", "Append to current SU table" = "append"),
          selected = "create"
        ),
        conditionalPanel(
          sprintf("input['%s'] == 'create'", ns("create_su_action")),
          textInput(ns("create_su_name"), "New SU Table Name")
        ),
        footer = tagList(
          actionButton(ns("btnConfirmCreateSu"), "Apply", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmCreateSu, {
      env_tbl <- env_tb(con)
      all_plots <- tryCatch(
        DBI::dbGetQuery(con, paste("SELECT plotnumber FROM", env_tbl))$plotnumber,
        error = function(e) character(0)
      )
      action <- input$create_su_action
      new_name <- trimws(input$create_su_name %||% "")
      result <- su_create_from_filter(con, all_plots, action, new_name)
      removeModal()
      show_toast(toast(result$message, type = if (result$ok) "success" else "danger"))
    })

    observeEvent(input$btnVegProfiling, {
      showModal(modalDialog(
        title = "Plot Profiling",
        size = "xl",
        easyClose = TRUE,
        mod_plot_profiling_ui(ns("plot_profiling")),
        footer = modalButton("Close")
      ))
    })

    observeEvent(input$btnRestoreAudit, {
      if (!child_ready()) return()
      selected_rows <- input$dt_audit_rows_selected
      if (length(selected_rows) != 1L || selected_rows < 1L || selected_rows > nrow(rv$audit)) {
        show_toast(toast("Select exactly one audit record to restore.", type = "warning"))
        return()
      }
      showModal(modalDialog(
        title = "Restore Audit Record",
        "Restore this field to its before-edit value?",
        radioButtons(ns("optRemoveAfterRestore"), "After restoring:", choices = c("Keep audit records" = "keep", "Remove audit records" = "remove"), selected = "keep"),
        footer = tagList(
          actionButton(ns("btnConfirmRestore"), "Restore", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmRestore, {
      if (!child_ready() || !other_guard()) return()
      selected <- input$dt_audit_rows_selected
      if (length(selected) != 1L || selected < 1L || selected > nrow(rv$audit)) return()
      tryCatch({
        vpro::vpro_plot_audit_restore(context, rv$current_plot,
          rv$audit[selected, , drop = FALSE],
          delete_audit = identical(input$optRemoveAfterRestore, "remove"))
        load_plot(rv$current_plot, vpro::vpro_plot_get(context, rv$current_plot))
        removeModal()
        show_toast(toast("Audit record restored.", type = "success"))
      }, error = function(e) show_toast(toast(conditionMessage(e), type = "danger")))
    })

    # Child actions never reload the Env/Admin draft. A dirty plot must be
    # explicitly saved or discarded with the plot controls before child writes.
    child_ready <- function() {
      if (is.null(rv$current_plot) || !nzchar(rv$current_plot)) {
        show_toast(toast("Load a plot first.", type = "warning")); return(FALSE)
      }
      if (!project_matches()) {
        show_toast(toast("Project changed: discard the old plot draft first.", type = "danger"))
        return(FALSE)
      }
      if (length(dirty_ids()) || length(coord_errors())) {
        show_toast(toast("Unsaved plot changes: Save or Discard the plot first.", type = "warning"))
        return(FALSE)
      }
      TRUE
    }
    child_api <- list(
      veg = list(get = vpro::vpro_plot_vegetation_get, list = vpro::vpro_plot_vegetation_list,
                 create = vpro::vpro_plot_vegetation_create, update = vpro::vpro_plot_vegetation_update,
                 delete = vpro::vpro_plot_vegetation_delete),
      humus = list(get = vpro::vpro_plot_humus_get, list = vpro::vpro_plot_humus_list,
                   create = vpro::vpro_plot_humus_create, update = vpro::vpro_plot_humus_update,
                   delete = vpro::vpro_plot_humus_delete),
      mineral = list(get = vpro::vpro_plot_mineral_get, list = vpro::vpro_plot_mineral_list,
                     create = vpro::vpro_plot_mineral_create, update = vpro::vpro_plot_mineral_update,
                     delete = vpro::vpro_plot_mineral_delete),
      other = list(get = vpro::vpro_plot_other_get, list = vpro::vpro_plot_other_list,
                   create = vpro::vpro_plot_other_create, update = vpro::vpro_plot_other_update,
                   delete = vpro::vpro_plot_other_delete))
    child_error <- function(e) show_toast(toast(conditionMessage(e), type = "danger"))
    child_done <- function(kind) {
      refresh_child(kind)
      rv$audit <- vpro::vpro_plot_audit_list(context, rv$current_plot)
    }
    selected_veg <- shiny::reactiveVal(NULL)
    for (grid_name in c("a", "c", "d")) local({
      g <- grid_name
      observeEvent(input[[paste0("dt_veg_", g, "_rows_selected")]], {
        idx <- input[[paste0("dt_veg_", g, "_rows_selected")]]
        rows <- rv[[paste0("veg_", g)]]
        if (length(idx) == 1L && idx >= 1L && idx <= nrow(rows))
          selected_veg(list(plot = rv$current_plot, id = rows$id[[idx]]))
      })
    })
    child_selection <- function(kind) {
      if (kind == "veg") {
        selected <- selected_veg()
        if (!is.null(selected) && identical(selected$plot, rv$current_plot)) return(selected$id)
      } else {
        grid <- switch(kind, humus = "hot_humus", mineral = "hot_mineral", other = "dt_veg_other")
        idx <- input[[paste0(grid, "_rows_selected")]]
        rows <- if (kind == "other") rv$veg_other else rv[[kind]]
        if (length(idx) == 1L && idx >= 1L && idx <= nrow(rows)) return(rows$id[[idx]])
      }
      show_toast(toast("Select one row first.", type = "warning"))
      NULL
    }
    child_modal <- shiny::reactiveVal(NULL)
    # Only approved canonical columns enter a child write. ID is never editable.
    child_columns <- function(kind, rows) {
      columns <- switch(kind,
        veg = c("Species", "Layer", "Cover1", "Height1", "Cover2", "Height2",
                "Cover3", "Height3", "TotalA", "HeightA", "Cover4", "Height4",
                "Cover5", "Height5", "Cover5a", "Height5a", "Cover5b", "Height5b",
                "Cover5c", "Height5c", "TotalB", "HeightB", "Cover6", "Height6",
                "Cover7", "Cover8", "Cover9", "Cover10", "Collected"),
        veg_other = c("Species", "LL", "AF", "DC", "UT", "VI", "PV", "PG", "FFA",
                      "Cultural1", "Cultural2", "Other1", "Other2"),
        humus = c("Horizon", "UpperDepth", "LowerDepth", "HumusStructureDegree",
                  "HumusStructureKind", "HumusFormpH", "Comment"),
        mineral = c("Horizon", "UpperDepth", "LowerDepth", "Texture",
                    "PercentCoarseFragsTotal", "MineralStructureClass", "Colour", "Comments"))
      indices <- match(tolower(columns), tolower(names(rows)))
      columns[!is.na(indices)]
    }
    open_child <- function(kind, id = NULL) {
      if (!child_ready()) return()
      api_kind <- if (kind == "veg_other") "veg" else kind
      tryCatch({
        rows <- child_api[[api_kind]]$list(context, rv$current_plot)
        columns <- child_columns(kind, rows)
        if (!length(columns)) stop("No editable columns available for this child table.")
        row <- if (is.null(id)) NULL else child_api[[api_kind]]$get(context, rv$current_plot, id)
        if (!is.null(row)) names(row) <- tolower(names(row))
        child_modal(list(kind = kind, id = id, plot = rv$current_plot, columns = columns,
                         row = row, schema = rows))
        controls <- lapply(columns, function(col) {
          value <- if (is.null(row)) NA else row[[tolower(col)]][[1L]]
          textInput(ns(paste0("child_", col)), col,
                    value = if (is.na(value)) "" else as.character(value))
        })
        showModal(modalDialog(title = paste(if (is.null(id)) "Add" else "Edit", kind),
          div(style = "max-height: 60vh; overflow-y: auto;", controls), size = "l",
          easyClose = FALSE,
          footer = tagList(actionButton(ns("child_save"), "Save", class = "btn-primary"),
                           actionButton(ns("child_cancel"), "Cancel"))))
      }, error = child_error)
    }
    observeEvent(input$child_cancel, { child_modal(NULL); removeModal() })
    observeEvent(input$child_save, {
      info <- child_modal()
      if (is.null(info) || !identical(info$plot, rv$current_plot) || !child_ready()) return()
      tryCatch({
        values <- list()
        for (col in info$columns) {
          text <- trimws(input[[paste0("child_", col)]] %||% "")
          source <- info$schema[[col]]
          value <- if (!nzchar(text)) NA else if (is.numeric(source)) {
            number <- suppressWarnings(as.numeric(text))
            if (!is.finite(number) || (is.integer(source) && number != floor(number)))
              stop("Invalid number for ", col)
            number
          } else text
          before <- if (is.null(info$id)) NULL else info$row[[tolower(col)]][[1L]]
          same <- !is.null(before) && ((is.na(value) && is.na(before)) ||
            isTRUE(all.equal(value, before, check.attributes = FALSE)))
          if ((is.null(info$id) && !is.na(value)) || (!is.null(info$id) && !same))
            values[[col]] <- value
        }
        if (is.null(info$id) && info$kind %in% c("veg", "veg_other") &&
            (is.null(values$Species) || is.na(values$Species))) stop("Species code is required.")
        if (is.null(info$id) && !length(values)) stop("Enter at least one field.")
        if (length(values)) {
          api_kind <- if (info$kind == "veg_other") "veg" else info$kind
          api <- child_api[[api_kind]]
          if (is.null(info$id)) api$create(context, info$plot, values)
          else api$update(context, info$plot, info$id, values)
          child_done(api_kind)
        }
        child_modal(NULL); removeModal()
      }, error = child_error)
    })
    for (kind in c("humus", "mineral", "veg_other", "veg")) local({
      k <- kind
      add_id <- if (k == "veg") "btnAddSpp" else paste0(k, "_add")
      if (k != "veg") observeEvent(input[[add_id]], { open_child(k) })
      observeEvent(input[[paste0(k, "_edit")]], {
        id <- child_selection(if (k == "veg_other") "other" else k)
        if (!is.null(id)) open_child(k, id)
      })
      observeEvent(input[[paste0(k, "_delete")]], {
        if (!child_ready()) return()
        id <- child_selection(if (k == "veg_other") "other" else k)
        if (is.null(id)) return()
        # Resolve ambiguous legacy IDs before presenting a destructive action.
        api_kind <- if (k == "veg_other") "veg" else k
        tryCatch({
          child_api[[api_kind]]$get(context, rv$current_plot, id)
          delete_target(list(kind = api_kind, id = id, plot = rv$current_plot))
          showModal(modalDialog(title = "Delete child row?", "This cannot be undone.",
            footer = tagList(actionButton(ns("child_delete_confirm"), "Delete", class = "btn-danger"),
                             modalButton("Cancel"))))
        }, error = child_error)
      })
    })
    delete_target <- shiny::reactiveVal(NULL)
    observeEvent(input$child_delete_confirm, {
      target <- delete_target(); delete_target(NULL)
      if (is.null(target) || !identical(target$plot, rv$current_plot) || !child_ready()) return()
      tryCatch({
        child_api[[target$kind]]$delete(context, target$plot, target$id)
        child_done(target$kind); removeModal()
      }, error = child_error)
    })

    # -- Vegetation grids --
    # Access parity:
    #   SubVegA cover-only:   Species(Tree/Shrubs), A1, A2, A3, A, B1, B2, B, Coll
    #   SubVegAht cover+ht:   Species, A1%, A1HT, A2%, A2HT, A3%, A3HT, A, B1%, B1HT, B2%, B2HT, B, Coll
    #   SubVegC  cover-only:  Species(Herb), C, Coll
    #   SubVegCht cover+ht:   Species, C%, C HT, Coll
    #   SubVegD  always:      Species(Moss/Lichen), D, Dr/Dw, Ep, Coll
    render_veg_grid <- function(data, grid_type) {
      DT::renderDT(
        {
          raw <- data()
          if (!nrow(raw)) {
            return(DT::datatable(
              data.frame(Message = paste("No", grid_type, "records")),
              rownames = FALSE,
              options = list(dom = "t", ordering = FALSE)
            ))
          }
          df <- raw
          names(df) <- tolower(names(df))

          # Build ordered mapping: db_col -> display_label
          col_labels <- if (grid_type == "A") {
            if (rv$cover_and_height) {
              c(
                species = "Tree/Shrubs",
                cover1 = "A1%",
                height1 = "A1HT",
                cover2 = "A2%",
                height2 = "A2HT",
                cover3 = "A3%",
                height3 = "A3HT",
                totala = "A",
                cover4 = "B1%",
                height4 = "B1HT",
                cover5 = "B2%",
                height5 = "B2HT",
                totalb = "B",
                collected = "?"
              )
            } else {
              c(species = "Tree/Shrubs", cover1 = "A1", cover2 = "A2", cover3 = "A3", totala = "A", cover4 = "B1", cover5 = "B2", totalb = "B", collected = "?")
            }
          } else if (grid_type == "C") {
            if (rv$cover_and_height) {
              c(species = "Herb", cover6 = "C%", height6 = "C HT", collected = "?")
            } else {
              c(species = "Herb", cover6 = "C", collected = "?")
            }
          } else {
            # D
            c(species = "Moss/Lichen", cover7 = "D", cover8 = "Dr/Dw", cover9 = "Ep", collected = "?")
          }

          # Filter to columns present in data (preserving order)
          present <- names(col_labels)[names(col_labels) %in% names(df)]
          if (!length(present)) {
            present <- names(df)
          }
          labels <- unname(col_labels[present])

          # Column widths: species wider, cover/height columns narrow
          spp_idx <- which(present == "species") - 1L # 0-based
          other_idx <- setdiff(seq_along(present) - 1L, spp_idx)

          DT::datatable(
            df[, present, drop = FALSE],
            colnames = labels,
            rownames = FALSE,
            selection = "single",
            options = list(
              pageLength = 25,
              scrollX = FALSE,
              dom = "t",
              ordering = FALSE,
              autoWidth = TRUE,
              columnDefs = c(
                list(list(className = "dt-center", targets = other_idx)),
                list(list(width = "90px", targets = spp_idx)),
                if (length(other_idx)) list(list(width = "45px", targets = other_idx)) else list()
              )
            )
          )
        },
        server = FALSE
      )
    }

    output$dt_veg_a <- render_veg_grid(reactive(rv$veg_a), "A")
    output$dt_veg_c <- render_veg_grid(reactive(rv$veg_c), "C")
    output$dt_veg_d <- render_veg_grid(reactive(rv$veg_d), "D")

    # -- Soil grids (rhandsontable) --
    humus_cols <- c("horizon", "upperdepth", "lowerdepth", "humusstructuredegree", "humusstructurekind", "humusformph", "_comment")
    mineral_cols <- c("horizon", "upperdepth", "lowerdepth", "texture", "percentcoarsefragstotal", "mineralstructureclass", "colour", "_comments")

    render_soil_hot <- function(data_reactive, cols) {
      DT::renderDT({
        df <- data_reactive()
        valid <- intersect(cols, names(df))
        if (!nrow(df)) df <- data.frame(Message = "No horizon records")
        else df <- df[, valid, drop = FALSE]
        DT::datatable(df, rownames = FALSE, selection = "single",
                      options = list(dom = "t", ordering = FALSE, scrollX = TRUE))
      }, server = FALSE)
    }

    output$hot_humus <- render_soil_hot(reactive(rv$humus), humus_cols)
    output$hot_mineral <- render_soil_hot(reactive(rv$mineral), mineral_cols)

    # -- Other grid --
    output$dt_other <- DT::renderDT({
      df <- if (nrow(rv$other)) rv$other else data.frame(Message = "No Other records")
      DT::datatable(df, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })

    # -- Veg Other grid (USysVegOther) --
    output$dt_veg_other <- DT::renderDT(
      {
        df <- if (nrow(rv$veg_other)) {
          # One row per canonical Veg ID, including species without Other codes.
          display <- rv$veg_other[, intersect(c("species", "ll", "af", "dc", "ut", "vi", "pv", "pg", "ffa", "cultural1", "cultural2", "other1", "other2"), names(rv$veg_other)), drop = FALSE]
          display
        } else {
          data.frame(Message = "No Veg Other records")
        }
        DT::datatable(
          df,
          rownames = FALSE,
          selection = "single",
          options = list(pageLength = 20, scrollX = TRUE, dom = "t")
        )
      },
      server = FALSE
    )

    # Other detail editor: inputs are local until Save. Navigation never loses
    # uncommitted detail text; Discard explicitly reloads the selected row.
    other_index <- shiny::reactiveVal(1L)
    other_epoch <- shiny::reactiveVal(0L)
    other_values <- shiny::reactiveVal(NULL)
    other_dirty <- shiny::reactiveVal(FALSE)
    other_ready <- shiny::reactiveVal(FALSE)
    other_fields <- c("DataName", "DataItem", "UserItem1", "UserItem2", "UserItem3",
                      "UserFlag1", "UserFlag2", "UserFlag3")
    output$txtOtherNav <- renderText({
      n <- nrow(rv$other)
      paste(min(other_index(), n + 1L), "of", n + 1L)
    })
    output$other_editor <- renderUI({
      if (is.null(rv$current_plot)) return(tags$p("Load a plot first."))
      other_epoch()
      idx <- other_index()
      row <- if (idx <= nrow(rv$other)) rv$other[idx, , drop = FALSE] else NULL
      # Ensure editing an existing row has unambiguous identity before enabling inputs.
      if (!is.null(row)) {
        row <- tryCatch(vpro::vpro_plot_other_get(context, rv$current_plot, row$id[[1L]]),
                        error = function(e) e)
        if (inherits(row, "error")) return(tags$p(class = "text-danger", conditionMessage(row)))
      }
      other_values(row)
      other_ready(FALSE)
      tagList(lapply(other_fields, function(field) {
        value <- if (is.null(row)) NA else row[[field]][[1L]]
        if (grepl("^UserFlag", field))
          checkboxInput(ns(paste0("other_", field)), field, value = !is.na(value) && as.logical(value))
        else textAreaInput(ns(paste0("other_", field)), field,
                           value = if (is.na(value)) "" else as.character(value), rows = 2)
      }))
    })
    # Suppress Shiny's initial input binding until it matches the loaded row.
    observe({
      row <- other_values()
      if (is.null(rv$current_plot)) return()
      vals <- lapply(other_fields, function(field) input[[paste0("other_", field)]])
      if (any(vapply(vals, is.null, logical(1)))) return()
      old <- lapply(other_fields, function(field) {
        if (grepl("^UserFlag", field)) {
          if (is.null(row)) FALSE else isTRUE(as.logical(row[[field]][[1L]]))
        } else if (is.null(row) || is.na(row[[field]][[1L]])) ""
        else as.character(row[[field]][[1L]])
      })
      if (!isTRUE(other_ready())) {
        # renderUI replaces inputs asynchronously. Ignore the previous row's
        # bindings until the new controls report the loaded baseline.
        if (identical(vals, old)) other_ready(TRUE)
        return()
      }
      other_dirty(!identical(vals, old))
    })
    other_guard <- function() {
      if (!child_ready()) return(FALSE)
      if (isTRUE(other_dirty())) {
        show_toast(toast("Unsaved Other changes: Save or Discard first.", type = "warning"))
        return(FALSE)
      }
      TRUE
    }
    observeEvent(input$btnOtherPrev, {
      if (other_guard() && other_index() > 1L) other_index(other_index() - 1L)
    })
    observeEvent(input$btnOtherNext, {
      if (other_guard() && other_index() <= nrow(rv$other)) other_index(other_index() + 1L)
    })
    observeEvent(input$btnOtherNew, {
      if (other_guard()) other_index(nrow(rv$other) + 1L)
    })
    observeEvent(input$dt_other_rows_selected, {
      idx <- input$dt_other_rows_selected
      if (length(idx) == 1L && idx <= nrow(rv$other) && other_guard()) other_index(idx)
    })
    observeEvent(input$btnOtherDiscard, {
      if (!child_ready()) return()
      other_dirty(FALSE)
      other_values(NULL)
      other_epoch(other_epoch() + 1L)
    })
    save_other <- function() {
      if (!isTRUE(other_dirty())) return(TRUE)
      if (!child_ready() || !project_matches()) return(FALSE)
      tryCatch({
        idx <- other_index()
        row <- other_values()
        values <- list()
        for (field in other_fields) {
          value <- input[[paste0("other_", field)]]
          if (is.null(value)) stop("Other editor is not ready.")
          if (!grepl("^UserFlag", field)) value <- if (nzchar(trimws(value))) value else NA_character_
          before <- if (is.null(row)) NULL else row[[field]][[1L]]
          if (!is.null(row) && grepl("^UserFlag", field)) before <- isTRUE(as.logical(before))
          if (!is.null(row) && !grepl("^UserFlag", field) && is.na(before)) before <- NA_character_
          same <- !is.null(before) && ((length(value) == 1L && is.na(value) && is.na(before)) ||
            isTRUE(all.equal(value, before, check.attributes = FALSE)))
          if (is.null(row) || !same) values[[field]] <- value
        }
        if (is.null(row)) {
          created <- vpro::vpro_plot_other_create(context, rv$current_plot, values)
          new_id <- created$other$ID[[1L]]
        } else {
          new_id <- row$ID[[1L]]
          if (length(values)) vpro::vpro_plot_other_update(context, rv$current_plot, new_id, values)
        }
        child_done("other")
        other_index(match(new_id, rv$other$id))
        other_values(NULL)
        other_dirty(FALSE)
        other_epoch(other_epoch() + 1L)
        TRUE
      }, error = function(e) { child_error(e); FALSE })
    }
    observeEvent(input$btnOtherSave, { save_other() })
    other_delete_id <- shiny::reactiveVal(NULL)
    observeEvent(input$btnOtherDelete, {
      if (!other_guard()) return()
      row <- other_values()
      if (is.null(row)) return()
      tryCatch({
        vpro::vpro_plot_other_get(context, rv$current_plot, row$ID[[1L]])
        other_delete_id(list(id = row$ID[[1L]], plot = rv$current_plot))
        showModal(modalDialog(title = "Delete Other row?", "This cannot be undone.",
          footer = tagList(actionButton(ns("other_delete_confirm"), "Delete", class = "btn-danger"),
                           modalButton("Cancel"))))
      }, error = child_error)
    })
    observeEvent(input$other_delete_confirm, {
      target <- other_delete_id(); other_delete_id(NULL)
      if (is.null(target) || !identical(rv$current_plot, target$plot) || !other_guard()) return()
      tryCatch({
        vpro::vpro_plot_other_delete(context, target$plot, target$id)
        child_done("other"); other_index(min(other_index(), nrow(rv$other) + 1L))
        other_epoch(other_epoch() + 1L)
        removeModal()
      }, error = child_error)
    })

    # Called by the sidebar before any project mutation. These functions run in
    # the same session, so the draft is saved while its original project is active.
    switch_status <- function() {
      if (isTRUE(modal_open()) || !is.null(child_modal()) || !is.null(delete_target()) ||
          !is.null(other_delete_id()) || !is.null(pending_navigation()))
        return(list(blocked = TRUE, dirty = FALSE))
      list(blocked = FALSE, dirty = length(dirty_ids()) > 0L ||
             length(coord_errors()) > 0L || isTRUE(other_dirty()))
    }
    switch_save <- function() {
      if (!project_matches() && (!is.null(baseline()) || isTRUE(other_dirty()))) return(FALSE)
      if (length(dirty_ids()) || length(coord_errors())) {
        if (!save_draft()) return(FALSE)
      }
      # Other writes use their own canonical CRUD API, not the plot-wide draft.
      if (isTRUE(other_dirty()) && !save_other()) return(FALSE)
      !isTRUE(switch_status()$dirty)
    }
    switch_discard <- function() {
      if (!is.null(baseline()) && !project_matches()) return(FALSE)
      if (isTRUE(other_dirty())) {
        other_dirty(FALSE)
        other_values(NULL)
        other_epoch(other_epoch() + 1L)
      }
      if (!is.null(rv$current_plot) && (length(dirty_ids()) || length(coord_errors()))) {
        populate_env_fields(vpro::vpro_plot_get(context, rv$current_plot))
      }
      TRUE
    }
    switch_reset <- function() {
      baseline(NULL); draft(list()); touched(character()); coord_errors(list())
      draft_project(NULL); draft_path(NULL)
      other_values(NULL); other_dirty(FALSE); other_index(1L)
      other_epoch(other_epoch() + 1L)
      child_modal(NULL); delete_target(NULL); other_delete_id(NULL)
      pending_navigation(NULL); selected_veg(NULL)
      rv$current_plot <- NULL; rv$env_row <- NULL
      for (kind in c("veg_a", "veg_c", "veg_d", "veg_other", "humus", "mineral", "other", "audit"))
        rv[[kind]] <- data.frame()
      state$CurrSU <- NULL
      refresh_picker(NULL)
      if (length(rv$recordset)) navigate_to(rv$recordset[[1L]])
      else {
        updateSelectizeInput(session, "navPlotPicker", selected = "")
        set_field("PlotNumber", "")
        for (id in setdiff(fs882_plot_fields, c("Latitude", "Longitude"))) {
          value <- if (id %in% fs882_plot_boolean) FALSE else if (id == "Date") as.Date(NA) else ""
          set_field(id, value)
        }
        coords(c(Latitude = NA_real_, Longitude = NA_real_))
        set_coord_fields(NA_real_, NA_real_, coord_method())
      }
      invisible(NULL)
    }

    # -- Audit grid --
    output$dt_audit <- DT::renderDT({
      df <- if (nrow(rv$audit)) rv$audit else data.frame(Message = "No audit records")
      DT::datatable(df, rownames = FALSE, selection = "multiple", options = list(pageLength = 20, scrollX = TRUE, dom = "tp"))
    })

    list(status = switch_status, save = switch_save, discard = switch_discard, reset = switch_reset)
  })
}
