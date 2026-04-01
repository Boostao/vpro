# FS882-6x4 Ecosystem Field Form Module
# Migrated from Access FS882-6x4XL form

# -- Coordinate helpers (port of V7mdlCoordTools) --

coord_dms <- function(decimal) {
  if (is.null(decimal) || is.na(decimal)) return(list(d = NA, m = NA, s = NA))
  val <- abs(as.numeric(decimal))
  d <- floor(val)
  remainder <- val - d
  m <- floor(remainder * 60)
  s <- (remainder * 60 - m) * 60
  list(d = d, m = m, s = round(s, 2))
}

coord_dm <- function(decimal) {
  if (is.null(decimal) || is.na(decimal)) return(list(d = NA, m = NA))
  val <- abs(as.numeric(decimal))
  d <- floor(val)
  m <- (val - d) * 60
  list(d = d, m = round(m, 4))
}

dms_to_dd <- function(d, m, s) {
  d <- as.numeric(d %||% 0)
  m <- as.numeric(m %||% 0)
  s <- as.numeric(s %||% 0)
  if (any(is.na(c(d, m, s)))) return(NA_real_)
  d + m / 60 + s / 3600
}

dm_to_dd <- function(d, m) {
  d <- as.numeric(d %||% 0)
  m <- as.numeric(m %||% 0)
  if (any(is.na(c(d, m)))) return(NA_real_)
  d + m / 60
}

# -- Dropdown loader --

list_choices <- function(con, list_name) {
  rows <- tryCatch(
    db_query(con, paste(
      "SELECT item, itemdescription",
      "FROM VLists.USysTableOfLists",
      "WHERE lower(listname) = lower(?)",
      "ORDER BY itemorder, item"
    ), params = list(list_name)),
    error = function(e) {
      message("[list_choices] ERROR for '", list_name, "': ", conditionMessage(e))
      data.frame()
    }
  )
  # DuckDB returns SQLite column names in title case (Item, ItemDescription);
  # normalize to lowercase so rows$item / rows$itemdescription work reliably.
  names(rows) <- tolower(names(rows))
  if (!nrow(rows)) return(c("---" = ""))
  labels <- ifelse(
    is.na(rows$itemdescription) | !nzchar(trimws(rows$itemdescription)),
    rows$item,
    paste0(rows$item, " - ", rows$itemdescription)
  )
  c(setNames("", ""), stats::setNames(as.character(rows$item), labels))
}

# -- Coercion helpers --

as_text <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) return("")
  as.character(value)
}

as_num <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) return(NA_real_)
  text <- trimws(as.character(value))
  if (!nzchar(text)) return(NA_real_)
  suppressWarnings(as.numeric(text))
}

as_chr <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) return(NA_character_)
  text <- trimws(as.character(value))
  if (!nzchar(text)) NA_character_ else text
}

num_display <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value) || !is.finite(value)) ""
  else formatC(value, format = "fg", flag = "-")
}

# -- Env table SQL helpers --

env_tb <- function(con) {
  as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
}

veg_tb <- function(con) {
  as.character(db_tb(con, "Veg", config("Current", "CurrProject"), prj = TRUE))
}

humus_tb <- function(con) {
  as.character(db_tb(con, "Humus", config("Current", "CurrProject"), prj = TRUE))
}

mineral_tb <- function(con) {
  as.character(db_tb(con, "Mineral", config("Current", "CurrProject"), prj = TRUE))
}

audit_tb <- function(con) {
  as.character(db_tb(con, "Audit", config("Current", "CurrProject"), prj = TRUE))
}

other_tb <- function(con) {
  as.character(db_tb(con, "Other", config("Current", "CurrProject"), prj = TRUE))
}

veg_other_tb <- function(con) {
  as.character(db_tb(con, "Veg", config("Current", "CurrProject"), prj = TRUE))
}

admin_tb <- function(con) {
  # Sample_Admin table (not prefixed, shares schema with project db)
  proj <- config("Current", "CurrProject")
  as.character(db_tb(con, "Sample_Admin", proj, prj = FALSE))
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
      div(
        class = "d-flex flex-wrap gap-1 align-items-center",
        # -- Record navigator (Access record bar parity) --
        actionButton(ns("btnNavFirst"), NULL,
          icon = icon("backward-step"), class = "btn btn-outline-secondary btn-sm px-1"),
        actionButton(ns("btnNavPrev"), NULL,
          icon = icon("caret-left"), class = "btn btn-outline-secondary btn-sm px-1"),
        div(
          class = "d-flex flex-column align-items-center",
          style = "min-width: 160px;",
          selectizeInput(ns("navPlotPicker"), NULL, choices = NULL,
            width = "160px",
            options = list(placeholder = "Plot...")),
          tags$small(class = "text-body-secondary", textOutput(ns("navRecordCount"), inline = TRUE))
        ),
        actionButton(ns("btnNavNext"), NULL,
          icon = icon("caret-right"), class = "btn btn-outline-secondary btn-sm px-1"),
        actionButton(ns("btnNavLast"), NULL,
          icon = icon("forward-step"), class = "btn btn-outline-secondary btn-sm px-1"),
        actionButton(ns("btnNavNew"), NULL,
          icon = icon("plus"), class = "btn btn-outline-success btn-sm px-1",
          title = "New record"),
        tags$div(class = "vr mx-1"),
        # -- Search (Access Find behaviour) --
        div(
          class = "input-group input-group-sm", style = "width: 180px;",
          tags$input(type = "text", class = "form-control form-control-sm",
            id = ns("navSearchBox"), placeholder = "Search..."),
          tags$button(class = "btn btn-outline-secondary btn-sm", type = "button",
            id = ns("btnNavSearch"), icon("magnifying-glass"))
        ),
        tags$div(class = "vr mx-1"),
        # -- Tool buttons --
        actionButton(ns("btnAudit"), "Audit", class = "btn btn-outline-secondary btn-sm"),
        actionButton(ns("btnSuIntoEnv"), "SU Into Env", class = "btn btn-outline-secondary btn-sm"),
        actionButton(ns("btnEnvIntoSu"), "Env Into SU", class = "btn btn-outline-secondary btn-sm"),
        actionButton(ns("btnCreateSuFromFilter"), "Create SU From Filter", class = "btn btn-outline-secondary btn-sm"),
        tags$div(class = "vr mx-1"),
        actionButton(ns("btnVegProfiling"), "Plot Profiling", class = "btn btn-outline-secondary btn-sm"),
        tags$div(class = "vr mx-1"),
        # -- Save / Lock --
        checkboxInput(ns("optLockData"), "Lock data", value = FALSE, width = "auto"),
        actionButton(ns("btnSaveRecord"), "Save", class = "btn btn-primary btn-sm")
      )
    ),

    # Disable bslib fill-shrink inside tab panes so form fields use natural height
    tags$style(HTML("
      .tab-pane .html-fill-item { flex: 0 0 auto !important; }
    ")),

    # JS bridge: wire raw-HTML search box + button into Shiny inputs
    tags$script(HTML(sprintf("
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
    ", ns("")))),

    # -- Tabs --
    tags$div(class = "vpro-form-sm",
    navset_card_tab(
      id = ns("tabPages"),

      # ---- Site tab ----
      nav_panel("Site", class = "p-2",
        layout_columns(
          col_widths = c(3, 2, 2, 2, 3),
          class = "mb-3",
          textInput(ns("PlotNumber"), "Plot Number"),
          textInput(ns("FieldNumber"), "Field No."),
          textInput(ns("Date"), "Date"),
          textInput(ns("StartDate"), "Yr."),
          textInput(ns("SiteSurveyor"), "Surveyor")
        ),

        layout_columns(
          col_widths = c(5, 4, 3),
          class = "mb-3 align-items-end",
          selectInput(ns("ProjectID"), "Project ID", choices = NULL),
          div(),
          radioButtons(ns("optProjectID"), "Project Source",
            choices = c("Env" = "1", "Master" = "2"),
            selected = as_text(config("Current", "ProjectIDSource") %||% "1"),
            inline = TRUE
          )
        ),

        card(
          class = "mb-3",
          card_header("Unit Assignment"),
          card_body(
            layout_columns(
              col_widths = c(4, 4, 4),
              selectInput(ns("BECSiteUnit"), "BEC Master", choices = NULL),
              selectInput(ns("UserSiteUnit"), "Working Unit", choices = NULL),
              radioButtons(ns("optAssignedSuSource"), "Assigned SU Source",
                choices = c("Env" = "1", "Master" = "2", "SU Tbl" = "3"),
                selected = as_text(config("Current", "AssignedSuSource")),
                inline = TRUE
              )
            ),
            div(
              class = "d-flex flex-wrap gap-2 mt-2",
              actionButton(ns("btnCopyToUserSU"), "Copy to Working Unit", class = "btn btn-outline-primary btn-sm"),
              actionButton(ns("btnLoadMetadata"), "Edit Metadata", class = "btn btn-outline-primary btn-sm")
            )
          )
        ),

        card(
          class = "mb-3",
          card_header("Location"),
          card_body(
            textAreaInput(ns("Location"), "General Location", width = "100%", rows = 2),
            layout_columns(
              col_widths = c(4, 2, 2, 2, 2),
              selectInput(ns("FSRegionDistrict"), "Forest Region/Dist.", choices = NULL),
              textInput(ns("NtsMapSheet"), "Map Sheet"),
              textInput(ns("UTMZone"), "UTM Zone"),
              textInput(ns("UTMEasting"), "Easting"),
              textInput(ns("UTMNorthing"), "Northing")
            ),
            layout_columns(
              col_widths = c(2, 2, 2, 6),
              textInput(ns("LocationAccuracy"), "Accur. (m)"),
              textInput(ns("XCoord"), "X Co-ord."),
              textInput(ns("YCoord"), "Y Co-ord"),
              div()
            ),
            layout_columns(
              col_widths = c(2, 3, 3, 4),
              textInput(ns("AirPhotoNum"), "Air Photo No."),
              div(),
              textInput(ns("Photo"), "Photo"),
              radioButtons(ns("optCoordMethod"), "Coordinate Display",
                choices = c("D.d" = "0", "DM.m" = "1", "DMS.s" = "2"),
                selected = as_text(config("Current", "CoordMethod")),
                inline = TRUE
              )
            ),
            # Decimal degrees row
            uiOutput(ns("coord_dd_row")),
            # DM row
            uiOutput(ns("coord_dm_row")),
            # DMS row
            uiOutput(ns("coord_dms_row"))
          )
        ),

        card(
          class = "mb-3",
          card_header("Site Information"),
          card_body(
            layout_columns(
              col_widths = c(3, 3, 2, 2, 2),
              selectInput(ns("Ecosection"), "Ecosection", choices = NULL),
              textInput(ns("PlotRepresenting"), "Plot Representing"),
              selectInput(ns("Zone"), "Zone", choices = NULL),
              selectInput(ns("SubZone"), "Subzone", choices = NULL),
              selectInput(ns("SiteSeries"), "Site Series", choices = NULL)
            ),
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              selectInput(ns("RealmClass"), "Realm/Class", choices = NULL),
              selectInput(ns("TransDistrib"), "Transition/Distrib.", choices = NULL),
              textInput(ns("MapUnit"), "Map Unit"),
              selectInput(ns("SuccessionalStatus"), "Successional Status", choices = NULL)
            ),
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              selectInput(ns("MoistureRegime"), "Moisture Regime", choices = NULL),
              selectInput(ns("NutrientRegime"), "Nutrient Regime", choices = NULL),
              selectInput(ns("StructuralStage"), "Structural Stage", choices = NULL),
              textInput(ns("StandAge"), "Stand Age")
            ),
            layout_columns(
              col_widths = c(2, 2, 2, 3, 3),
              textInput(ns("Elevation"), "Elevation (m)"),
              textInput(ns("SlopeGradient"), "Slope (%)"),
              textInput(ns("Aspect"), "Aspect"),
              selectInput(ns("MesoSlopePosition"), "Meso Slope Pos.", choices = NULL),
              selectInput(ns("SurfaceShape"), "Surface Shape", choices = NULL)
            ),
            layout_columns(
              col_widths = c(4, 4, 4),
              selectInput(ns("SurfaceTopographyType"), "Microtop. type", choices = NULL),
              selectInput(ns("SurfaceTopographySize"), "Microtop. size", choices = NULL),
              div()
            )
          )
        ),

        card(
          class = "mb-3",
          card_header("Quality / Disturbance / Exposure"),
          card_body(
            # Data Quality — Access: "Data Quality" label + Site/Veg/Soil
            div(class = "d-flex align-items-end gap-3 mb-2",
              tags$span(class = "fw-semibold text-nowrap form-label-sm",
                style = "width:7rem;padding-bottom:.35rem;", "Data Quality"),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("SitePlotQuality"), "Site", choices = NULL, width = "100%")),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("VegPlotQuality"), "Veg", choices = NULL, width = "100%")),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("SoilPlotQuality"), "Soil", choices = NULL, width = "100%"))
            ),
            # Exposure Type — Access: "Exposure Type" label + Exposure1/Exposure2
            div(class = "d-flex align-items-end gap-3 mb-2",
              tags$span(class = "fw-semibold text-nowrap form-label-sm",
                style = "width:7rem;padding-bottom:.35rem;", "Exposure Type"),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("Exposure1"), NULL, choices = NULL, width = "100%")),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("Exposure2"), NULL, choices = NULL, width = "100%"))
            ),
            # Site Disturbance — Access: "Site Disturbance" label + 3 dropdowns
            div(class = "d-flex align-items-end gap-3",
              tags$span(class = "fw-semibold text-nowrap form-label-sm",
                style = "width:7rem;padding-bottom:.35rem;", "Site Disturbance"),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("SiteDisturbance1"), NULL, choices = NULL, width = "100%")),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("SiteDisturbance2"), NULL, choices = NULL, width = "100%")),
              div(style = "flex:0 0 auto;width:7.5rem;",
                selectInput(ns("SiteDisturbance3"), NULL, choices = NULL, width = "100%"))
            )
          )
        ),

        card(
          class = "mb-3",
          card_header("Substrate"),
          card_body(
            layout_columns(
              col_widths = c(2, 2, 2, 2, 2, 2),
              textInput(ns("SubstrateOrganicMatter"), "Org. Matter"),
              textInput(ns("SubstrateDecWood"), "Dec. Wood"),
              textInput(ns("SubstrateBedRock"), "Bedrock"),
              textInput(ns("SubstrateRocks"), "Rocks"),
              textInput(ns("SubstrateMineralSoil"), "Mineral Soil"),
              textInput(ns("SubstrateWater"), "Water")
            )
          )
        ),

        layout_columns(
          col_widths = c(4, 8),
          class = "mb-3",
          card(
            card_header("Site Diagram / Picture"),
            card_body(
              uiOutput(ns("site_picture")),
              div(
                class = "d-flex flex-wrap gap-2 mt-2",
                actionButton(ns("btnManagePictures"), "Pictures", class = "btn btn-outline-primary btn-sm"),
                downloadButton(ns("dlGoogleEarth"), "Google Earth", class = "btn btn-outline-secondary btn-sm")
              )
            )
          ),
          card(
            card_header("Notes"),
            card_body(
              textAreaInput(ns("SiteNotes"), "Field Notes", width = "100%", rows = 4),
              textAreaInput(ns("OfficeNotes"), "Office Notes", width = "100%", rows = 3)
            )
          )
        )
      ),

      # ---- Vegetation tab ----
      nav_panel("Vegetation", class = "p-2",
        layout_columns(
          col_widths = c(2, 2, 1, 1, 1, 1, 4),
          class = "mb-3 align-items-end",
          textOutput(ns("VegPlotNumber")),
          textInput(ns("VegSurveyor"), "Surveyor"),
          textInput(ns("StrataCoverTree"), "A"),
          textInput(ns("StrataCoverShrub"), "B"),
          textInput(ns("StrataCoverHerb"), "C"),
          textInput(ns("StrataCoverMoss"), "D"),
          div(
            class = "d-flex flex-wrap gap-1 align-items-end",
            actionButton(ns("btnAddSpp"), "Add Spp", class = "btn btn-outline-primary btn-sm"),
            actionButton(ns("btnCoverAndHeight"), "Cover & Height", class = "btn btn-outline-secondary btn-sm"),
            actionButton(ns("btnAllowSmallEntry"), "Allow <0.1% Entry", class = "btn btn-outline-secondary btn-sm"),
            actionButton(ns("btnCheckSppCodes"), "Check Spp Codes", class = "btn btn-outline-secondary btn-sm")
          )
        ),
        layout_columns(
          col_widths = c(5, 3, 4),
          card(
            card_header("Tree & Shrub (A/B)"),
            card_body(DT::DTOutput(ns("dt_veg_a")))
          ),
          card(
            card_header("Herb (C)"),
            card_body(DT::DTOutput(ns("dt_veg_c")))
          ),
          card(
            card_header("Moss / Lichen (D)"),
            card_body(DT::DTOutput(ns("dt_veg_d")))
          )
        ),
        layout_columns(
          col_widths = c(3, 9),
          checkboxInput(ns("SpeciesListComplete"), "Spp. List Complete?", value = FALSE),
          textAreaInput(ns("VegNotes"), "Notes", width = "100%", rows = 3)
        )
      ),

      # ---- Veg Other tab (Access USysVegOther subform) ----
      nav_panel("Veg Other", class = "p-2",
        card(
          card_header("Vegetation Other Attributes"),
          card_body(DT::DTOutput(ns("dt_veg_other")))
        )
      ),

      # ---- Soil / Terrain tab ----
      nav_panel("Soil / Terrain", class = "p-2",
        card(
          class = "mb-3",
          card_header("Soil Header"),
          card_body(
            # Row 1: Surveyor + Bedrock Geology x3 + Coarse Frag Lith x3
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              textInput(ns("SoilSurveyor"), "Surveyor(s)"),
              selectInput(ns("BedrockGeology1"), "Bedrock Type 1", choices = NULL),
              selectInput(ns("BedrockGeology2"), "Bedrock Type 2", choices = NULL),
              selectInput(ns("BedrockGeology3"), "Bedrock Type 3", choices = NULL)
            ),
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              div(),
              selectInput(ns("CoarseFragLith1"), "Coarse Frag. Lith. 1", choices = NULL),
              selectInput(ns("CoarseFragLith2"), "Coarse Frag. Lith. 2", choices = NULL),
              selectInput(ns("CoarseFragLith3"), "Coarse Frag. Lith. 3", choices = NULL)
            ),
            # Row 2: Classification + Humus
            layout_columns(
              col_widths = c(3, 3, 2, 2, 2),
              selectInput(ns("SoilClassSubGroup"), "Soil Subgroup", choices = NULL),
              selectInput(ns("SoilClassGroup"), "Great Group", choices = NULL),
              selectInput(ns("HumusForm"), "Humus Form", choices = NULL),
              selectInput(ns("HumusFormPhase"), "Phase", choices = NULL),
              textInput(ns("HumusThickness"), "Thickness (cm)")
            ),
            # Row 3: Drainage + Rooting + Seepage + Flooding
            layout_columns(
              col_widths = c(2, 2, 2, 2, 2, 2),
              selectInput(ns("SoilDrainage"), "Drainage", choices = NULL),
              textInput(ns("RootingDepth"), "Rooting Depth (cm)"),
              selectInput(ns("RootRestrictingType"), "Root Rest. Type", choices = NULL),
              textInput(ns("RootRestrictingDepth"), "Root Rest. Depth (cm)"),
              selectInput(ns("RootZoneParticleSize"), "R.Z. Particle Size", choices = NULL),
              textInput(ns("SeepageDepth"), "Seepage (cm)")
            ),
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              selectInput(ns("WaterSource"), "Water Source", choices = NULL),
              selectInput(ns("HydroGeoSystem"), "Hydrogeo System", choices = NULL),
              selectInput(ns("HydroGeoSubSystem"), "Hydrogeo Subsystem", choices = NULL),
              div(
                selectInput(ns("FloodingRegimeFreq"), "Flood Freq.", choices = NULL),
                selectInput(ns("FloodingRegimeDur"), "Flood Duration", choices = NULL)
              )
            )
          )
        ),
        card(
          class = "mb-3",
          card_header("Terrain"),
          card_body(
            # Surface terrain
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              selectInput(ns("TerrainTextureSurf"), "Surface Texture", choices = NULL),
              selectInput(ns("SurficialMaterialSurf"), "Surficial Material", choices = NULL),
              selectInput(ns("SurfaceExpSurf"), "Surface Expression", choices = NULL),
              selectInput(ns("GeoMorProSurf"), "Geomorph. Process", choices = NULL)
            ),
            # Sub-surface terrain
            tags$small(class = "text-body-secondary mt-1 d-block", "Sub-surface"),
            layout_columns(
              col_widths = c(3, 3, 3, 3),
              selectInput(ns("TerrainTextureSubSurf"), "SubSurf Texture", choices = NULL),
              selectInput(ns("SurficialMaterialSubSurf"), "SubSurf Material", choices = NULL),
              selectInput(ns("SurfaceExpSubSurf"), "SubSurf Expression", choices = NULL),
              selectInput(ns("GeoMorProSubSurf"), "SubSurf Geomorph.", choices = NULL)
            )
          )
        ),
        layout_columns(
          col_widths = c(6, 6),
          class = "mb-3",
          card(
            card_header("Organic Horizons (Humus)"),
            card_body(rhandsontable::rHandsontableOutput(ns("hot_humus")))
          ),
          card(
            card_header("Mineral Horizons"),
            card_body(rhandsontable::rHandsontableOutput(ns("hot_mineral")))
          )
        ),
        textAreaInput(ns("SoilNotes"), "Notes", width = "100%", rows = 3)
      ),

      # ---- Other tab ----
      nav_panel("Other", class = "p-2",
        card(
          card_header("Other Data"),
          card_body(DT::DTOutput(ns("dt_other")))
        )
      ),

      # ---- Audit tab ----
      nav_panel("Audit", class = "p-2",
        layout_columns(
          col_widths = c(9, 3),
          class = "mb-3 align-items-end",
          radioButtons(ns("optAuditStrength"), "Audit Strength",
            choices = c("Edit" = "1", "Edit & Add" = "2", "Edit, Add, & Delete" = "3"),
            selected = as_text(config("Audit", "AuditStrength")),
            inline = TRUE
          ),
          actionButton(ns("btnRestoreAudit"), "Restore selected", class = "btn btn-outline-secondary btn-sm")
        ),
        card(
          card_header("Audit Trail"),
          card_body(DT::DTOutput(ns("dt_audit")))
        )
      )
    ),

  )
  ) # end vpro-form-sm wrapper
}

# ============================================================
# Server
# ============================================================

mod_fs882_6x4_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    root_session <- session$rootScope()

    # Trigger for metadata modal: increment each time modal is opened so that
    # mod_project_metadata_server loads data AFTER the modal DOM exists.
    metadata_open_trigger <- shiny::reactiveVal(0L)
    # Current plot's ProjectID passed to metadata module on each open
    metadata_plot_project_id <- shiny::reactiveVal("")

    dyn_choices <- local({
      make <- function(list_name) {
        res <- tryCatch({
          DBI::dbGetQuery(con, glue::glue_sql(
            "SELECT ListValue FROM lists.{`list_name`} ORDER BY SortOrder, ListValue",
            .con = con
          ))$ListValue
        }, error = function(e) character(0))
        c("", res)
      }
      list(
        SurfaceTopography     = make("SurfaceTopography"),
        SurfaceTopographySize = make("SurfaceTopographySize"),
        MoistureRegime        = make("MoistureRegime"),
        NutrientRegime        = make("NutrientRegime"),
        SuccessionalStatus    = make("SuccessionalStatus"),
        StructuralStage       = make("StructuralStage"),
        Ecosection            = make("Ecosection"),
        Zone                  = make("Zone"),
        FSRegionDistrict      = make("Region"),
        RealmClass            = make("RealmClass"),
        TransDistrib          = make("TransDistrib"),
        SitePlotQuality       = make("PlotQualitySite"),
        VegPlotQuality        = make("PlotQualitySite"),
        SoilPlotQuality       = make("PlotQualitySite"),
        Exposure1             = make("Exposure"),
        Exposure2             = make("Exposure"),
        SiteDisturbance1      = make("SiteDisturbance"),
        SiteDisturbance2      = make("SiteDisturbance"),
        SiteDisturbance3      = make("SiteDisturbance"),
        BedrockGeology1       = make("BedrockType"),
        BedrockGeology2       = make("BedrockType"),
        BedrockGeology3       = make("BedrockType"),
        CoarseFragLith1       = make("BedrockType"),
        CoarseFragLith2       = make("BedrockType"),
        CoarseFragLith3       = make("BedrockType"),
        SoilClassSubGroup     = make("SoilClassSubgroup"),
        SoilClassGroup        = make("SoilClassGroup"),
        HumusForm             = make("HumusForm"),
        HumusFormPhase        = make("HumusFormPhase"),
        SoilDrainage          = make("SoilDrainage"),
        RootRestrictingType   = make("RootRestrictingType"),
        RootZoneParticleSize  = make("RootZoneParticleSize"),
        WaterSource           = make("WaterSource"),
        FloodingRegimeFreq    = make("FloodingRegimeFreq"),
        FloodingRegimeDur     = make("FloodingRegimeDur"),
        HydroGeoSystem        = make("HydrogeoSystem"),
        HydroGeoSubSystem     = make("HydrogeoSubsystem"),
        TerrainTextureSurf       = make("TerrainTexture"),
        SurficialMaterialSurf    = make("SurficialMaterial"),
        SurfaceExpSurf           = make("SurfaceExp"),
        GeoMorProSurf            = make("GeoMorPro"),
        TerrainTextureSubSurf    = make("TerrainTexture"),
        SurficialMaterialSubSurf = make("SurficialMaterial"),
        SurfaceExpSubSurf        = make("SurfaceExp"),
        GeoMorProSubSurf         = make("GeoMorPro")
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

    # -- Caption reflects Access Form_Open: "Project: X / SU Table: Y" --
    output$caption <- renderUI({
      project  <- config("Current", "CurrProject")  %||% "None"
      su_table <- config("Current", "CurrPlotlist") %||% "None"
      tags$div(
        tags$h6(class = "mb-0", sprintf("Project: %s / SU Table: %s", project, su_table)),
        tags$small(class = "text-body-secondary", paste("Plot:", rv$current_plot %||% "\u2014"))
      )
    })

    # Method: 0 = D.d, 1 = DM.m, 2 = DMS.s
    output$coord_dd_row <- renderUI({
      req(input$optCoordMethod == "0")
      layout_columns(
        col_widths = c(4, 4, 4),
        textInput(ns("Latitude"), "Latitude"),
        textInput(ns("Longitude"), "Longitude"),
        div()
      )
    })

    output$coord_dm_row <- renderUI({
      req(input$optCoordMethod == "1")
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        textInput(ns("LatD2"), "Lat D"),
        textInput(ns("LatMD"), "Lat M.m"),
        textInput(ns("LonD2"), "Lon D"),
        textInput(ns("LonMD"), "Lon M.m")
      )
    })

    output$coord_dms_row <- renderUI({
      req(input$optCoordMethod == "2")
      layout_columns(
        col_widths = c(2, 2, 2, 2, 2, 2),
        textInput(ns("LatD"), "Lat D"),
        textInput(ns("LatM"), "Lat M"),
        textInput(ns("LatS"), "Lat S"),
        textInput(ns("LonD"), "Lon D"),
        textInput(ns("LonM"), "Lon M"),
        textInput(ns("LonS"), "Lon S")
      )
    })

    # -- Load ProjectID choices from ProjectMetaData (once at init) --
    observe({
      proj_choices <- tryCatch({
        rows <- db_query(con, paste(
          "SELECT ProjectID, ProjectTitle FROM",
          as.character(db_tb(con, "Metadata", config("Current", "CurrProject"), prj = TRUE)),
          "ORDER BY ProjectID"
        ))
        names(rows) <- tolower(names(rows))
        if (nrow(rows)) {
          labels <- ifelse(is.na(rows$projecttitle) | !nzchar(trimws(rows$projecttitle)),
            rows$projectid,
            paste0(rows$projectid, " - ", rows$projecttitle))
          c(setNames("", ""), stats::setNames(rows$projectid, labels))
        } else c("---" = "")
      }, error = function(e) c("---" = ""))
      updateSelectInput(session, "ProjectID", choices = proj_choices)
    }) |> bindEvent(TRUE, once = TRUE)

    output$site_picture <- renderUI({
      tags$div(
        class = "text-muted text-center p-3 border rounded",
        style = "min-height: 120px;",
        tags$small("Picture placeholder")
      )
    })

    output$VegPlotNumber <- renderText(paste("Plot:", rv$current_plot %||% "\u2014"))

    # -- Populate dropdowns (once, using pre-loaded dyn_choices cache) --
    observe({
      for (id in names(dyn_choices)) {
        updateSelectInput(session, id, choices = dyn_choices[[id]])
      }
    }) |> bindEvent(TRUE, once = TRUE)

    # -- Assigned SU source dropdown (Access optAssignedSuSource) --
    observe({
      src <- as.integer(input$optAssignedSuSource %||% 1)
      choices <- tryCatch({
        if (src == 1L) {
          rows <- db_query(con, paste(
            "SELECT DISTINCT UserSiteUnit FROM",
            admin_tb(con),
            "WHERE UserSiteUnit IS NOT NULL ORDER BY UserSiteUnit"
          ))
          c(setNames("", ""), stats::setNames(rows$UserSiteUnit, rows$UserSiteUnit))
        } else if (src == 2L) {
          rows <- db_query(con, paste(
            "SELECT SiteSeries, SiteSeriesLongName",
            "FROM MasterSiteUnitList",
            "WHERE Level = 11 ORDER BY SiteSeries"
          ))
          labels <- ifelse(is.na(rows$SiteSeriesLongName), rows$SiteSeries,
            paste0(rows$SiteSeries, " - ", rows$SiteSeriesLongName))
          c(setNames("", ""), stats::setNames(rows$SiteSeries, labels))
        } else if (src == 3L) {
          plotlist <- config("Current", "CurrPlotlist")
          if (is.null(plotlist) || plotlist == "None") {
            show_toast(toast("Select an SU table first.", type = "warning"))
            c("---" = "")
          } else {
            su_tbl <- as.character(db_tb(con, "SU", plotlist, prj = TRUE))
            rows <- db_query(con, paste(
              "SELECT DISTINCT SiteUnit FROM", su_tbl,
              "WHERE SiteUnit IS NOT NULL ORDER BY SiteUnit"
            ))
            c(setNames("", ""), stats::setNames(rows$SiteUnit, rows$SiteUnit))
          }
        } else {
          c("---" = "")
        }
      }, error = function(e) c("---" = ""))
      updateSelectInput(session, "UserSiteUnit", choices = choices)
    }) |> bindEvent(input$optAssignedSuSource, ignoreInit = FALSE)

    # -- SubZone depends on Zone (Access SubZone_GotFocus -> SubZoneList) --
    observe({
      zone <- input$Zone
      if (is.null(zone) || !nzchar(zone)) return()
      rows <- tryCatch(
        db_query(con, paste(
          "SELECT DISTINCT item FROM VLists.USysTableOfLists",
          "WHERE lower(listname) = 'subzone'",
          "AND lower(parentvalue) = lower(?)",
          "ORDER BY item"
        ), params = list(zone)),
        error = function(e) data.frame()
      )
      choices <- if (nrow(rows)) c(setNames("", ""), stats::setNames(rows$item, rows$item)) else c("---" = "")
      updateSelectInput(session, "SubZone", choices = choices,
        selected = as_text(rv$env_row$subzone))
    }) |> bindEvent(input$Zone, ignoreInit = TRUE)

    # -- SiteSeries depends on Zone + SubZone --
    observe({
      zone <- input$Zone
      subzone <- input$SubZone
      if (is.null(zone) || !nzchar(zone)) return()
      filter_val <- paste0(zone, subzone)
      rows <- tryCatch(
        db_query(con, paste(
          "SELECT DISTINCT SiteSeriesNo, siteseries",
          "FROM VLists.USysSiteSeriesNames",
          "WHERE lower(BEC) = lower(?)",
          "ORDER BY SiteSeriesNo"
        ), params = list(filter_val)),
        error = function(e) data.frame()
      )
      if (nrow(rows)) {
        labels <- paste0(rows$SiteSeriesNo, " - ", rows$siteseries)
        choices <- c(setNames("", ""), stats::setNames(rows$SiteSeriesNo, labels))
      } else {
        choices <- c("---" = "")
      }
      updateSelectInput(session, "SiteSeries", choices = choices,
        selected = as_text(rv$env_row$siteseries))
    }) |> bindEvent(input$SubZone, ignoreInit = TRUE)

    # -- Load plot data --
    load_plot <- function(plot_id) {
      if (is.null(plot_id) || !nzchar(trimws(plot_id))) return()
      plot_id <- trimws(plot_id)
      rv$current_plot <- plot_id

      # Env header: JOIN Sample_Env + Sample_Admin (mirrors Access UsysEnv view)
      env <- tryCatch({
        sql <- paste(
          "SELECT e.*, a.BECSiteUnit, a.UserSiteUnit, a.SitePlotQuality,",
          "a.VegPlotQuality, a.SoilPlotQuality, a.OfficeNotes",
          "FROM", env_tb(con), "e",
          "LEFT JOIN", admin_tb(con), "a ON e.PlotNumber = a.Plot",
          "WHERE e.PlotNumber = ?"
        )
        db_query(con, sql, params = list(plot_id))
      }, error = function(e) {
        # Fallback: env only (Admin table may not exist yet)
        db_query(con, paste("SELECT * FROM", env_tb(con), "WHERE plotnumber = ?"),
          params = list(plot_id))
      })
      if (nrow(env)) {
        row <- env[1, , drop = FALSE]
        rv$env_row <- row
        populate_env_fields(row)
      } else {
        rv$env_row <- NULL
        updateTextInput(session, "PlotNumber", value = plot_id)
      }

      # Vegetation: query directly from Sample_Veg (veg_a) and views (veg_c, veg_d)
      #   Access SubVegA = Cover Only (A1,A2,A3,A,B1,B2,B); SubVegAht = Cover+Height
      #   USysVegA view lacks Height1-5 per-layer heights → query Sample_Veg directly
      {
        proj <- config("Current", "CurrProject")
        veg_raw_tbl <- as.character(db_tb(con, "Veg", proj, prj = TRUE))
        veg_c_tbl <- as.character(db_tb(con, "USysVegC", proj, prj = FALSE))
        veg_d_tbl <- as.character(db_tb(con, "USysVegD", proj, prj = FALSE))
        rv$veg_a <- tryCatch(
          db_query(con, paste(
            "SELECT Species, Cover1, Height1, Cover2, Height2, Cover3, Height3,",
            "TotalA, Cover4, Height4, Cover5, Height5, TotalB, Collected",
            "FROM", veg_raw_tbl,
            "WHERE PlotNumber = ? AND (",
            "Cover1 IS NOT NULL OR Cover2 IS NOT NULL OR Cover3 IS NOT NULL",
            "OR TotalA IS NOT NULL OR Cover4 IS NOT NULL OR Cover5 IS NOT NULL",
            "OR TotalB IS NOT NULL)",
            "ORDER BY Species"
          ), params = list(plot_id)),
          error = function(e) data.frame()
        )
        rv$veg_c <- tryCatch(
          db_query(con, paste("SELECT * FROM", veg_c_tbl,
            "WHERE plotnumber = ? ORDER BY species"), params = list(plot_id)),
          error = function(e) data.frame()
        )
        rv$veg_d <- tryCatch(
          db_query(con, paste("SELECT * FROM", veg_d_tbl,
            "WHERE plotnumber = ? ORDER BY species"), params = list(plot_id)),
          error = function(e) data.frame()
        )
      }

      # Soil
      rv$humus <- tryCatch(
        db_query(con, paste("SELECT * FROM", humus_tb(con),
          "WHERE plotnumber = ? ORDER BY horizon, upperdepth"), params = list(plot_id)),
        error = function(e) data.frame()
      )
      rv$mineral <- tryCatch(
        db_query(con, paste("SELECT * FROM", mineral_tb(con),
          "WHERE plotnumber = ? ORDER BY horizon, upperdepth"), params = list(plot_id)),
        error = function(e) data.frame()
      )

      # Audit
      rv$audit <- tryCatch(
        db_query(con, paste("SELECT * FROM", audit_tb(con),
          "WHERE plotnumber = ? ORDER BY EditWhen DESC"), params = list(plot_id)),
        error = function(e) data.frame()
      )

      # Other
      rv$other <- tryCatch(
        db_query(con, paste("SELECT * FROM", other_tb(con),
          "WHERE plotnumber = ?"), params = list(plot_id)),
        error = function(e) data.frame()
      )

      # Veg Other (USysVegOther columns from Veg table)
      veg_other_cols <- c("PlotNumber", "Species", "LL", "AF", "DC", "UT",
                          "VI", "PV", "PG", "FFA", "Cultural1", "Cultural2",
                          "Other1", "Other2")
      rv$veg_other <- tryCatch({
        sql <- paste(
          "SELECT", paste(paste0('"', veg_other_cols, '"'), collapse = ", "),
          "FROM", veg_other_tb(con),
          "WHERE plotnumber = ? ORDER BY Species"
        )
        db_query(con, sql, params = list(plot_id))
      }, error = function(e) data.frame())
    }

    populate_env_fields <- function(row) {
      col <- function(nm) {
        idx <- match(tolower(nm), tolower(names(row)))
        if (is.na(idx)) NA else row[[idx]][[1]]
      }
      updateTextInput(session, "PlotNumber",   value = as_text(col("plotnumber")))
      updateTextInput(session, "FieldNumber",  value = as_text(col("fieldnumber")))
      updateTextInput(session, "Date",         value = as_text(col("date")))
      date_val <- as_text(col("date"))
      updateTextInput(session, "StartDate",    value = if (nzchar(date_val)) substr(date_val, 1, 4) else "")
      updateTextInput(session, "VegSurveyor",  value = as_text(col("vegsurveyor")))
      updateTextInput(session, "SoilSurveyor", value = as_text(col("soilsurveyor")))
      updateTextInput(session, "RootingDepth", value = num_display(col("rootingdepth")))
      updateTextInput(session, "RootRestrictingDepth", value = num_display(col("rootrestrictingdepth")))
      updateTextInput(session, "SeepageDepth", value = num_display(col("seepagedepth")))
      updateTextInput(session, "HumusThickness", value = num_display(col("humusthickness")))
      updateTextInput(session, "XCoord", value = num_display(col("xcoord")))
      updateTextInput(session, "YCoord", value = num_display(col("ycoord")))
      updateCheckboxInput(session, "SpeciesListComplete",
        value = isTRUE(as.logical(col("specieslistcomplete"))))
      updateTextInput(session, "StrataCoverTree",  value = num_display(col("StrataCoverTree")))
      updateTextInput(session, "StrataCoverShrub", value = num_display(col("StrataCoverShrub")))
      updateTextInput(session, "StrataCoverHerb",  value = num_display(col("StrataCoverHerb")))
      updateTextInput(session, "StrataCoverMoss",  value = num_display(col("StrataCoverMoss")))
      updateTextAreaInput(session, "VegNotes",     value = as_text(col("vegnotes")))
      updateTextAreaInput(session, "SoilNotes",    value = as_text(col("soilnotes")))

      # Substrate
      updateTextInput(session, "SubstrateOrganicMatter", value = num_display(col("substrateorganicmatter")))
      updateTextInput(session, "SubstrateDecWood",       value = num_display(col("substratedecwood")))
      updateTextInput(session, "SubstrateBedRock",       value = num_display(col("substratebedrock")))
      updateTextInput(session, "SubstrateRocks",         value = num_display(col("substraterocks")))
      updateTextInput(session, "SubstrateMineralSoil",   value = num_display(col("substratemineralsoil")))
      updateTextInput(session, "SubstrateWater",         value = num_display(col("substratewater")))

      # Selects: set choices+selected atomically from dyn_choices cache
      # (avoids timing issue where separate choices/selected updates conflict)
      for (sel in names(dyn_choices)) {
        val <- as_text(col(tolower(sel)))
        updateSelectInput(session, sel,
          choices = dyn_choices[[sel]], selected = val)
      }

      # BEC master unit: load full master list so all options are available
      bec_val <- as_text(col("becsiteunit"))
      bec_choices <- tryCatch({
        rows <- db_query(con, paste(
          "SELECT Name, UnitLongName FROM VLists.USysMasterSiteUnitList",
          "WHERE Level = 11 ORDER BY Name"
        ))
        names(rows) <- tolower(names(rows))
        labels <- ifelse(is.na(rows$unitlongname) | !nzchar(trimws(rows$unitlongname)),
          rows$name,
          paste0(rows$name, " - ", rows$unitlongname))
        c(setNames("", ""), stats::setNames(rows$name, labels))
      }, error = function(e) {
        if (nzchar(bec_val)) c(setNames("", ""), setNames(bec_val, bec_val)) else c("---" = "")
      })
      updateSelectInput(session, "BECSiteUnit", choices = bec_choices, selected = bec_val)

      # ProjectID: update selected value (choices already loaded at init)
      updateSelectInput(session, "ProjectID", selected = as_text(col("projectid")))

      # Selects: set choices+selected atomically from dyn_choices cache
      # (avoids timing issue where separate choices/selected updates conflict)
      for (sel in names(dyn_choices)) {
        val <- as_text(col(tolower(sel)))
        updateSelectInput(session, sel,
          choices = dyn_choices[[sel]], selected = val)
      }

      # BEC master unit: always include current value in choices so it shows
      bec_val <- as_text(col("becsiteunit"))
      if (nzchar(bec_val)) {
        updateSelectInput(session, "BECSiteUnit",
          choices = c(setNames("", ""), setNames(bec_val, bec_val)),
          selected = bec_val)
      }
      # Working Unit: update choices from admin if src=1, then select
      user_su <- as_text(col("usersiteunit"))
      updateSelectInput(session, "UserSiteUnit", selected = user_su)

      # Coordinates - populate based on current method
      lat <- as.numeric(col("latitude"))
      lon <- as.numeric(col("longitude"))
      method <- input$optCoordMethod %||% "0"
      set_coord_fields(lat, lon, method)
    }

    set_coord_fields <- function(lat, lon, method) {
      if (method == "0") {
        updateTextInput(session, "Latitude",  value = num_display(lat))
        updateTextInput(session, "Longitude", value = num_display(lon))
      } else if (method == "1") {
        lat_dm <- coord_dm(lat)
        lon_dm <- coord_dm(lon)
        updateTextInput(session, "LatD2", value = num_display(lat_dm$d))
        updateTextInput(session, "LatMD", value = num_display(lat_dm$m))
        updateTextInput(session, "LonD2", value = num_display(lon_dm$d))
        updateTextInput(session, "LonMD", value = num_display(lon_dm$m))
      } else {
        lat_dms <- coord_dms(lat)
        lon_dms <- coord_dms(lon)
        updateTextInput(session, "LatD", value = num_display(lat_dms$d))
        updateTextInput(session, "LatM", value = num_display(lat_dms$m))
        updateTextInput(session, "LatS", value = num_display(lat_dms$s))
        updateTextInput(session, "LonD", value = num_display(lon_dms$d))
        updateTextInput(session, "LonM", value = num_display(lon_dms$m))
        updateTextInput(session, "LonS", value = num_display(lon_dms$s))
      }
    }

    # -- Coord method switch: recalculate from stored lat/lon --
    observeEvent(input$optCoordMethod, {
      config("Current", "CoordMethod", input$optCoordMethod)
      row <- rv$env_row
      if (!is.null(row)) {
        lat_col <- match("latitude", tolower(names(row)))
        lon_col <- match("longitude", tolower(names(row)))
        lat <- if (!is.na(lat_col)) as.numeric(row[[lat_col]]) else NA_real_
        lon <- if (!is.na(lon_col)) as.numeric(row[[lon_col]]) else NA_real_
        set_coord_fields(lat, lon, input$optCoordMethod)
      }
    }, ignoreInit = TRUE)

    # -- Read current lat/lon from whichever coord method is active --
    current_lat_lon <- function() {
      method <- input$optCoordMethod %||% "0"
      if (method == "0") {
        lat <- as_num(input$Latitude)
        lon <- as_num(input$Longitude)
      } else if (method == "1") {
        lat <- dm_to_dd(input$LatD2, input$LatMD)
        lon <- dm_to_dd(input$LonD2, input$LonMD)
      } else {
        lat <- dms_to_dd(input$LatD, input$LatM, input$LatS)
        lon <- dms_to_dd(input$LonD, input$LonM, input$LonS)
      }
      list(lat = lat, lon = lon)
    }

    # ============================================================
    # Record Navigator Wiring
    # ============================================================

    # -- Record count display --
    output$navRecordCount <- renderText({
      n <- length(rv$recordset)
      idx <- rv$record_index
      if (n == 0) "0 of 0" else paste(idx, "of", n)
    })

    # -- Initialise recordset (once, on module startup) --
    observe({
      rs <- refresh_recordset(con)
      rv$recordset <- rs
      updateSelectizeInput(session, "navPlotPicker",
        choices = if (length(rs)) stats::setNames(rs, rs) else character(0),
        server = FALSE)
    }) |> bindEvent(TRUE, once = TRUE)

    # -- Helper: save current record if dirty (detects changes on demand) --
    save_current_if_dirty <- function() {
      plot_id <- rv$current_plot
      if (is.null(plot_id) || !nzchar(plot_id)) return(invisible(FALSE))

      fields <- collect_env_fields(input, current_lat_lon)
      dirty_fields <- detect_dirty_fields(fields, rv$env_row)
      if (!length(dirty_fields)) return(invisible(FALSE))

      tbl  <- env_tb(con)
      atbl <- admin_tb(con)

      admin_field_names <- c("becsiteunit", "usersiteunit", "siteplotquality",
                             "vegplotquality", "soilplotquality", "officenotes")
      env_fields   <- fields[!names(fields) %in% admin_field_names]
      admin_fields <- fields[names(fields) %in% admin_field_names]

      tryCatch({
        q_col <- function(nm) paste0('"', nm, '"')
        # TIMESTAMP columns in SQLite cannot use bind params (DuckDB infers TIMESTAMP
        # type and SQLite::BindValue rejects it). Inject as sanitized SQL literals.
        ts_cols <- c("date")
        sanitize_ts <- function(v)
          paste0("'", gsub("[^0-9: -]", "", as.character(v)), "'")

        param_env_nms <- setdiff(setdiff(names(env_fields), "plotnumber"), ts_cols)
        ts_env_nms   <- intersect(names(env_fields), ts_cols)

        set_parts <- c(
          vapply(param_env_nms, function(nm) paste0(q_col(nm), " = ?"), character(1)),
          vapply(ts_env_nms,    function(nm)
            paste0(q_col(nm), " = ", sanitize_ts(env_fields[[nm]])), character(1))
        )

        # --- Update Sample_Env ---
        set_pairs     <- paste(set_parts, collapse = ", ")
        update_sql    <- paste("UPDATE", tbl, "SET", set_pairs, "WHERE plotnumber = ?")
        update_params <- c(unname(env_fields[param_env_nms]), list(plot_id))
        n <- db_run(con, update_sql, params = update_params)

        if (n == 0) {
          ins_cols    <- names(env_fields)
          ins_val_sql <- vapply(ins_cols, function(nm) {
            if (nm %in% ts_cols) sanitize_ts(env_fields[[nm]]) else "?"
          }, character(1))
          insert_sql    <- paste("INSERT INTO", tbl, "(",
            paste(vapply(ins_cols, q_col, character(1)), collapse = ", "),
            ") VALUES (", paste(ins_val_sql, collapse = ", "), ")")
          insert_params <- unname(env_fields[setdiff(ins_cols, ts_cols)])
          db_run(con, insert_sql, params = insert_params)
        }

        # --- Update Sample_Admin ---
        if (length(admin_fields) > 0) {
          admin_set <- paste(
            vapply(names(admin_fields), function(nm)
              paste0(q_col(nm), " = ?"), character(1)),
            collapse = ", "
          )
          na <- db_run(con,
            paste("UPDATE", atbl, "SET", admin_set, "WHERE Plot = ?"),
            params = c(unname(admin_fields), list(plot_id)))
          if (na == 0) {
            a_all <- c(list(Plot = plot_id), admin_fields)
            a_cols <- paste(vapply(names(a_all), q_col, character(1)), collapse = ", ")
            a_ph   <- paste(rep("?", length(a_all)), collapse = ", ")
            db_run(con, paste("INSERT INTO", atbl, "(", a_cols, ") VALUES (", a_ph, ")"),
              params = unname(a_all))
          }
        }

        # Per-field audit trail (Access AuditTrail Me)
        write_audit_trail(con, fields, rv$env_row, plot_id)

        rv$dirty <- FALSE
        invisible(TRUE)
      }, error = function(e) {
        show_toast(toast(paste("Auto-save failed:", conditionMessage(e)), type = "danger"))
        invisible(FALSE)
      })
    }

    # -- Helper: navigate to a specific plot_id --
    navigate_to <- function(plot_id) {
      if (is.null(plot_id) || !nzchar(plot_id)) return()
      idx <- match(plot_id, rv$recordset)
      if (is.na(idx)) return()

      rv$record_index <- idx
      rv$current_plot <- plot_id
      # Sync the selectize without retriggering the observer
      updateSelectizeInput(session, "navPlotPicker", selected = plot_id)
      load_plot(plot_id)
      rv$dirty <- FALSE
      # Sync state for other modules
      state$CurrSU <- plot_id
    }

    # -- Nav buttons --
    observeEvent(input$btnNavFirst, {
      if (!length(rv$recordset)) return()
      save_current_if_dirty()
      navigate_to(rv$recordset[1])
    })

    observeEvent(input$btnNavPrev, {
      if (!length(rv$recordset) || rv$record_index <= 1L) return()
      save_current_if_dirty()
      navigate_to(rv$recordset[rv$record_index - 1L])
    })

    observeEvent(input$btnNavNext, {
      n <- length(rv$recordset)
      if (!n || rv$record_index >= n) return()
      save_current_if_dirty()
      navigate_to(rv$recordset[rv$record_index + 1L])
    })

    observeEvent(input$btnNavLast, {
      n <- length(rv$recordset)
      if (!n) return()
      save_current_if_dirty()
      navigate_to(rv$recordset[n])
    })

    # -- Selectize picker change (user selects a plot directly) --
    observeEvent(input$navPlotPicker, {
      picked <- input$navPlotPicker
      if (is.null(picked) || !nzchar(picked)) return()
      # Avoid re-entry when navigate_to() sets the selectize
      if (identical(picked, rv$current_plot)) return()
      save_current_if_dirty()
      navigate_to(picked)
    }, ignoreInit = TRUE)

    # -- New record --
    observeEvent(input$btnNavNew, {
      save_current_if_dirty()
      showModal(modalDialog(
        title = "New Record",
        textInput(ns("new_plot_number"), "Plot Number"),
        footer = tagList(
          actionButton(ns("btnConfirmNewRecord"), "Create", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmNewRecord, {
      new_id <- trimws(input$new_plot_number %||% "")
      if (!nzchar(new_id)) {
        show_toast(toast("Plot Number is required.", type = "danger"))
        return()
      }
      if (new_id %in% rv$recordset) {
        show_toast(toast("Plot already exists, navigating to it.", type = "warning"))
        removeModal()
        navigate_to(new_id)
        return()
      }
      # Insert minimal row
      tbl <- env_tb(con)
      tryCatch({
        db_run(con, paste("INSERT INTO", tbl, "(plotnumber) VALUES (?)"),
          params = list(new_id))
        # Refresh recordset and navigate
        rv$recordset <- refresh_recordset(con)
        updateSelectizeInput(session, "navPlotPicker",
          choices = stats::setNames(rv$recordset, rv$recordset),
          server = FALSE)
        removeModal()
        navigate_to(new_id)
        show_toast(toast(paste("Created plot", new_id), type = "success"))
      }, error = function(e) {
        show_toast(toast(paste("Create failed:", conditionMessage(e)), type = "danger"))
      })
    })

    # -- Search (Access Find behaviour: Enter = next match) --
    observeEvent(input$nav_search_trigger, {
      info <- input$nav_search_trigger
      query <- info$query
      if (is.null(query) || !nzchar(trimws(query))) return()
      hit <- search_across_fields(con, rv$recordset, query, rv$search_last_plot)
      updateSelectizeInput(session, "navPlotPicker",
        choices = if (length(rs)) stats::setNames(rs, rs) else character(0),
        server = FALSE)

      if (plot_id %in% rs) {
        navigate_to(plot_id)
      } else if (length(rs)) {
        navigate_to(rs[1])
      }
    }, ignoreInit = FALSE)

    # -- Lock data toggle (Access optLockData) --
    observeEvent(input$optLockData, {
      locked <- isTRUE(input$optLockData)
      # All text/select/textarea environment field IDs
      env_field_ids <- c(
        "PlotNumber", "FieldNumber", "Date", "StartDate", "SiteSurveyor", "Location",
        "UTMEasting", "UTMNorthing", "UTMZone", "LocationAccuracy", "NtsMapSheet",
        "Elevation", "SlopeGradient", "Aspect", "AirPhotoNum", "Photo",
        "PlotRepresenting", "MapUnit", "StandAge", "SiteNotes", "OfficeNotes",
        "SoilSurveyor", "RootingDepth", "RootRestrictingDepth", "SeepageDepth",
        "StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss",
        "VegNotes", "SoilNotes", "SpeciesListComplete",
        "SubstrateOrganicMatter", "SubstrateDecWood", "SubstrateBedRock",
        "SubstrateRocks", "SubstrateMineralSoil", "SubstrateWater",
        "Latitude", "Longitude", "LatD2", "LatMD", "LonD2", "LonMD",
        "LatD", "LatM", "LatS", "LonD", "LonM", "LonS",
        "MesoSlopePosition", "SurfaceShape", "SurfaceTopographyType", "SurfaceTopographySize",
        "MoistureRegime", "NutrientRegime", "SuccessionalStatus", "StructuralStage",
        "Ecosection", "Zone", "SubZone", "SiteSeries",
        "BECSiteUnit", "UserSiteUnit",
        "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality",
        "Exposure1", "Exposure2",
        "SiteDisturbance1", "SiteDisturbance2", "SiteDisturbance3",
        "RealmClass", "TransDistrib", "FSRegionDistrict",
        "BedrockGeology1", "CoarseFragLith1",
        "SoilClassSubGroup", "SoilClassGroup", "HumusForm",
        "SoilDrainage", "RootRestrictingType", "WaterSource", "FloodingRegimeFreq"
      )
      toggle_fn <- if (locked) shinyjs::disable else shinyjs::enable
      for (fid in env_field_ids) toggle_fn(fid)
      # Also toggle save button
      if (locked) shinyjs::disable("btnSaveRecord") else shinyjs::enable("btnSaveRecord")
    }, ignoreInit = TRUE)

    # -- Save (Access btnSaveRecord + Form_BeforeUpdate audit trail) --
    observeEvent(input$btnSaveRecord, {
      plot_id <- trimws(input$PlotNumber %||% rv$current_plot %||% "")
      if (!nzchar(plot_id)) {
        show_toast(toast("Plot Number is required to save.", type = "danger"))
        return()
      }

      fields <- collect_env_fields(input, current_lat_lon)
      tbl <- env_tb(con)
      atbl <- admin_tb(con)

      # Fields that live in Sample_Admin (not Sample_Env)
      admin_field_names <- c("becsiteunit", "usersiteunit", "siteplotquality",
                             "vegplotquality", "soilplotquality", "officenotes")
      env_fields   <- fields[!names(fields) %in% admin_field_names]
      admin_fields <- fields[names(fields) %in% admin_field_names]

      tryCatch({
        q_col <- function(nm) paste0('"', nm, '"')
        # TIMESTAMP columns: inject as sanitized SQL literals (DuckDB-SQLite TIMESTAMP bind workaround)
        ts_cols <- c("date")
        sanitize_ts <- function(v)
          paste0("'", gsub("[^0-9: -]", "", as.character(v)), "'")

        param_env_nms <- setdiff(setdiff(names(env_fields), "plotnumber"), ts_cols)
        ts_env_nms   <- intersect(names(env_fields), ts_cols)

        set_parts <- c(
          vapply(param_env_nms, function(nm) paste0(q_col(nm), " = ?"), character(1)),
          vapply(ts_env_nms,    function(nm)
            paste0(q_col(nm), " = ", sanitize_ts(env_fields[[nm]])), character(1))
        )

        # --- Update Sample_Env ---
        set_pairs     <- paste(set_parts, collapse = ", ")
        update_sql    <- paste("UPDATE", tbl, "SET", set_pairs, "WHERE plotnumber = ?")
        update_params <- c(unname(env_fields[param_env_nms]), list(plot_id))
        n <- db_run(con, update_sql, params = update_params)

        if (n == 0) {
          ins_cols    <- names(env_fields)
          ins_val_sql <- vapply(ins_cols, function(nm) {
            if (nm %in% ts_cols) sanitize_ts(env_fields[[nm]]) else "?"
          }, character(1))
          insert_sql    <- paste("INSERT INTO", tbl, "(",
            paste(vapply(ins_cols, q_col, character(1)), collapse = ", "),
            ") VALUES (", paste(ins_val_sql, collapse = ", "), ")")
          insert_params <- unname(env_fields[setdiff(ins_cols, ts_cols)])
          db_run(con, insert_sql, params = insert_params)
        }

        # --- Update Sample_Admin ---
        if (length(admin_fields) > 0) {
          admin_set <- paste(
            vapply(names(admin_fields), function(nm)
              paste0(q_col(nm), " = ?"), character(1)),
            collapse = ", "
          )
          admin_upd_sql <

    # -- Project source changed (Access optProjectID_AfterUpdate) --
    observeEvent(input$optProjectID, {
      config("Current", "ProjectIDSource", input$optProjectID)
    }, ignoreInit = TRUE)- paste("UPDATE", atbl, "SET", admin_set, "WHERE Plot = ?")
          admin_upd_params <- c(unname(admin_fields), list(plot_id))
          na <- db_run(con, admin_upd_sql, params = admin_upd_params)
          if (na == 0) {
            # No admin row yet - insert with Plot key
            a_all <- c(list(Plot = plot_id), admin_fields)
            a_cols <- paste(vapply(names(a_all), q_col, character(1)), collapse = ", ")
            a_ph   <- paste(rep("?", length(a_all)), collapse = ", ")
            db_run(con, paste("INSERT INTO", atbl, "(", a_cols, ") VALUES (", a_ph, ")"),
              params = unname(a_all))
          }
        }

        # Per-field audit trail (Access AuditTrail Me)
        write_audit_trail(con, fields, rv$env_row, plot_id)

        rv$dirty <- FALSE
        state$CurrSU <- plot_id
        show_toast(toast("FS882 record saved.", type = "success"))
        load_plot(plot_id)
      }, error = function(e) {
        show_toast(toast(paste("Save failed:", conditionMessage(e)), type = "danger"))
      })
    })

    # -- SU source changed (Access optAssignedSuSource_AfterUpdate saves record) --
    observeEvent(input$optAssignedSuSource, {
      config("Current", "AssignedSuSource", input$optAssignedSuSource)
    }, ignoreInit = TRUE)

    # -- Audit strength --
    observeEvent(input$optAuditStrength, {
      config("Audit", "AuditStrength", input$optAuditStrength)
    }, ignoreInit = TRUE)

    # -- Copy to Working Unit (Access btnCoptToWorkingUnit) --
    observeEvent(input$btnCopyToUserSU, {
      bec_val <- input$BECSiteUnit
      if (is.null(bec_val) || !nzchar(bec_val)) {
        show_toast(toast("No BEC Master unit to copy.", type = "warning"))
        return()
      }
      updateSelectInput(session, "UserSiteUnit", selected = bec_val)
    })

    # -- Cover & Height toggle --
    observeEvent(input$btnCoverAndHeight, {
      rv$cover_and_height <- !rv$cover_and_height
      # Mirror Access: button caption shows the mode you will SWITCH TO next
      shiny::updateActionButton(session, "btnCoverAndHeight",
        label = if (rv$cover_and_height) "Cover Only" else "Cover & Height"
      )
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
      show_toast(toast("Check Spp Codes: species validation deferred (hookup pending).",
        type = "success", duration_s = 5))
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

    # -- Add Species (Access USysAddSpp dialog) --
    observeEvent(input$btnAddSpp, {
      showModal(modalDialog(
        title = "Add Species",
        easyClose = TRUE,
        size = "l",
        textInput(ns("new_spp_code"), "Species Code"),
        selectInput(ns("new_spp_layer"), "Layer",
          choices = c("A1", "A2", "A3", "B1", "B2", "C", "D")
        ),
        footer = tagList(
          actionButton(ns("btnConfirmAddSpp"), "Add", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmAddSpp, {
      spp <- trimws(input$new_spp_code %||% "")
      layer <- input$new_spp_layer %||% "C"
      plot_id <- rv$current_plot
      if (!nzchar(spp) || is.null(plot_id)) {
        show_toast(toast("Species code and current plot are required.", type = "warning"))
        return()
      }
      tryCatch({
        db_run(con, paste(
          "INSERT INTO", veg_tb(con),
          "(plotnumber, species, layer) VALUES (?, ?, ?)"
        ), params = list(plot_id, spp, layer))
        removeModal()
        load_plot(plot_id)
        show_toast(toast(paste("Added", spp, "to layer", layer), type = "success"))
      }, error = function(e) {
        show_toast(toast(paste("Add species failed:", conditionMessage(e)), type = "danger"))
      })
    })

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
          paste0(nrow(result$new_units),
            " site units in your Env table are not in the master list. ",
            "Add them to your personal site unit list?"),
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
        db_query(con, paste("SELECT plotnumber FROM", env_tbl, "ORDER BY plotnumber"))$plotnumber,
        error = function(e) character(0)
      )
      if (!length(all_plots)) {
        show_toast(toast("No plots in current project.", type = "warning"))
        return()
      }
      showModal(modalDialog(
        title = "Create SU From Filter",
        p(paste0(length(all_plots), " plots in current project.")),
        radioButtons(ns("create_su_action"), "Action",
          choices = c("Create new SU table" = "create",
                      "Modify current SU table" = "modify",
                      "Append to current SU table" = "append"),
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
        db_query(con, paste("SELECT plotnumber FROM", env_tbl))$plotnumber,
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
      selected_rows <- input$dt_audit_rows_selected
      if (is.null(selected_rows) || !length(selected_rows)) {
        show_toast(toast("Select audit records to restore first.", type = "warning"))
        return()
      }
      showModal(modalDialog(
        title = "Restore Audit Records",
        paste0(length(selected_rows), " record(s) selected. ",
          "Restore field values to their before-edit state?"),
        radioButtons(ns("optRemoveAfterRestore"), "After restoring:",
          choices = c("Keep audit records" = "keep",
                      "Remove audit records" = "remove"),
          selected = "keep"
        ),
        footer = tagList(
          actionButton(ns("btnConfirmRestore"), "Restore", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmRestore, {
      removeModal()
      selected <- input$dt_audit_rows_selected
      if (is.null(selected) || !length(selected)) return()
      audit_df <- rv$audit
      if (!nrow(audit_df)) return()
      remove_after <- identical(input$optRemoveAfterRestore, "remove")

      project <- config("Current", "CurrProject")
      n_restored <- 0

      for (idx in selected) {
        if (idx > nrow(audit_df)) next
        rec <- audit_df[idx, , drop = FALSE]
        names(rec) <- tolower(names(rec))

        tbl_suffix <- rec$table[[1]]
        edit_field <- rec$editfield[[1]]
        before_val <- rec$beforeedit[[1]]
        plot_num   <- rec$plotnumber[[1]]
        rec_id     <- rec$id[[1]]

        # Skip Cover fields and key fields (Access parity)
        if (is.null(edit_field) || is.na(edit_field)) next
        if (grepl("^cover", tolower(edit_field))) next
        if (tolower(edit_field) %in% c("id", "plotnumber")) next

        # Determine target table
        target_tbl <- paste0(project, tbl_suffix)

        # Build WHERE clause
        where <- if (grepl("_Env$", tbl_suffix)) {
          list(sql = paste("WHERE plotnumber = ?"), params = list(plot_num))
        } else {
          list(sql = paste("WHERE plotnumber = ? AND id = ?"),
               params = list(plot_num, rec_id))
        }

        tryCatch({
          update_sql <- paste0(
            "UPDATE ", target_tbl,
            " SET ", edit_field, " = ? ",
            where$sql
          )
          db_run(con, update_sql, params = c(list(before_val), where$params))
          n_restored <- n_restored + 1
        }, error = function(e) NULL)

        # Optionally remove audit record
        if (remove_after) {
          audit_tbl <- audit_tb(con)
          tryCatch(
            db_run(con, paste0(
              "DELETE FROM ", audit_tbl,
              " WHERE plotnumber = ? AND editfield = ? AND editwhen = ?"
            ), params = list(plot_num, edit_field,
              rec$editwhen[[1]])),
            error = function(e) NULL
          )
        }
      }

      show_toast(toast(
        paste0(n_restored, " field(s) restored."),
        type = if (n_restored > 0) "success" else "warning"
      ))
      # Reload plot and audit
      load_plot(rv$current_plot)
    })

    # -- Vegetation grids --
    # Access parity:
    #   SubVegA cover-only:   Species(Tree/Shrubs), A1, A2, A3, A, B1, B2, B, Coll
    #   SubVegAht cover+ht:   Species, A1%, A1HT, A2%, A2HT, A3%, A3HT, A, B1%, B1HT, B2%, B2HT, B, Coll
    #   SubVegC  cover-only:  Species(Herb), C, Coll
    #   SubVegCht cover+ht:   Species, C%, C HT, Coll
    #   SubVegD  always:      Species(Moss/Lichen), D, Dr/Dw, Ep, Coll
    render_veg_grid <- function(data, grid_type) {
      DT::renderDT({
        raw <- data()
        if (!nrow(raw)) {
          return(DT::datatable(
            data.frame(Message = paste("No", grid_type, "records")),
            rownames = FALSE, options = list(dom = "t", ordering = FALSE)
          ))
        }
        df <- raw
        names(df) <- tolower(names(df))

        # Build ordered mapping: db_col -> display_label
        col_labels <- if (grid_type == "A") {
          if (rv$cover_and_height) {
            c(species="Tree/Shrubs", cover1="A1%", height1="A1HT",
              cover2="A2%", height2="A2HT", cover3="A3%", height3="A3HT",
              totala="A", cover4="B1%", height4="B1HT",
              cover5="B2%", height5="B2HT", totalb="B", collected="Coll")
          } else {
            c(species="Tree/Shrubs", cover1="A1", cover2="A2", cover3="A3",
              totala="A", cover4="B1", cover5="B2", totalb="B", collected="Coll")
          }
        } else if (grid_type == "C") {
          if (rv$cover_and_height) {
            c(species="Herb", cover6="C%", height6="C HT", collected="Coll")
          } else {
            c(species="Herb", cover6="C", collected="Coll")
          }
        } else { # D
          c(species="Moss/Lichen", cover7="D", cover8="Dr/Dw", cover9="Ep", collected="Coll")
        }

        # Filter to columns present in data (preserving order)
        present <- names(col_labels)[names(col_labels) %in% names(df)]
        if (!length(present)) present <- names(df)
        labels <- unname(col_labels[present])

        # Column widths: species wider, cover/height columns narrow
        spp_idx <- which(present == "species") - 1L  # 0-based
        other_idx <- setdiff(seq_along(present) - 1L, spp_idx)

        DT::datatable(
          df[, present, drop = FALSE],
          colnames = labels,
          rownames = FALSE,
          selection = "single",
          editable = list(target = "cell", disable = list(columns = c(0))),
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
      }, server = FALSE)
    }

    output$dt_veg_a <- render_veg_grid(reactive(rv$veg_a), "A")
    output$dt_veg_c <- render_veg_grid(reactive(rv$veg_c), "C")
    output$dt_veg_d <- render_veg_grid(reactive(rv$veg_d), "D")

    # -- Soil grids (rhandsontable) --
    humus_cols <- c("horizon", "upperdepth", "lowerdepth",
                    "humusstructuredegree", "humusstructurekind",
                    "humusformph", "_comment")
    mineral_cols <- c("horizon", "upperdepth", "lowerdepth",
                      "texture", "percentcoarsefragstotal",
                      "mineralstructureclass", "colour", "_comments")

    render_soil_hot <- function(data_reactive, cols) {
      rhandsontable::renderRHandsontable({
        df <- data_reactive()
        if (!nrow(df)) return(rhandsontable::rhandsontable(data.frame()))
        valid <- intersect(cols, names(df))
        if (!length(valid)) return(rhandsontable::rhandsontable(data.frame()))
        rhandsontable::rhandsontable(
          df[, valid, drop = FALSE],
          rowHeaders = FALSE,
          useTypes = TRUE,
          stretchH = "all"
        )
      })
    }

    output$hot_humus   <- render_soil_hot(reactive(rv$humus), humus_cols)
    output$hot_mineral <- render_soil_hot(reactive(rv$mineral), mineral_cols)

    # -- Other grid --
    output$dt_other <- DT::renderDT({
      df <- if (nrow(rv$other)) rv$other else data.frame(Message = "No Other records")
      DT::datatable(df, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })

    # -- Veg Other grid (USysVegOther) --
    output$dt_veg_other <- DT::renderDT({
      df <- if (nrow(rv$veg_other)) {
        # Drop PlotNumber column from display (redundant)
        display <- rv$veg_other[, setdiff(names(rv$veg_other), "PlotNumber"), drop = FALSE]
        display
      } else {
        data.frame(Message = "No Veg Other records")
      }
      DT::datatable(df, rownames = FALSE, selection = "single",
        editable = list(target = "cell", disable = list(columns = 0)),
        options = list(pageLength = 20, scrollX = TRUE, dom = "t"))
    }, server = FALSE)

    # -- Audit grid --
    output$dt_audit <- DT::renderDT({
      df <- if (nrow(rv$audit)) rv$audit else data.frame(Message = "No audit records")
      DT::datatable(df, rownames = FALSE, selection = "multiple",
        options = list(pageLength = 20, scrollX = TRUE, dom = "tp"))
    })

    invisible(NULL)
  })
}
