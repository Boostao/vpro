# VENUS XML Export Logic
# Implements BC Government VENUS (Vegetation Ecology National Unified System) XML export

#' Export Project Data to VENUS XML Format
#'
#' Main function to export vegetation project data to VENUS XML format.
#' VENUS is the BC government standard for vegetation data exchange.
#'
#' @param con DBI connection to DuckDB database
#' @param project_id Character vector of project IDs to export (NULL = current project)
#' @param output_path Character path to output XML file
#' @param options List of export options:
#'   - apply_lumping: Apply species synonym consolidation (default TRUE)
#'   - include_draft: Include plots flagged as draft/temporary (default TRUE)
#'   - date_from: Filter plots by date (YYYY-MM-DD, optional)
#'   - date_to: Filter plots by date (YYYY-MM-DD, optional)
#'   - coords_required: Only export plots with coordinates (default TRUE)
#'   - validate_schema: Validate against XSD if available (default FALSE)
#'
#' @return List with success status and metadata (file size, plot count, etc.)
#' @export
export_venus_xml <- function(con, project_id = NULL, output_path = NULL, options = list()) {
  
  # Default options
  opts <- list(
    apply_lumping = TRUE,
    # Default to including plots flagged as temporary/draft.
    # Unit tests and typical export expectations assume draft plots are included
    # unless explicitly excluded.
    include_draft = TRUE,
    date_from = NULL,
    date_to = NULL,
    coords_required = TRUE,
    validate_schema = FALSE
  )
  opts[names(options)] <- options
  
  # Validate inputs
  if (is.null(output_path)) {
    stop("output_path is required")
  }
  
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("xml2 package is required for VENUS XML export")
  }
  
  # Get project metadata
  metadata <- get_project_metadata(con, project_id)
  
  # Build XML document
  xml_doc <- build_venus_xml_document(con, project_id, metadata, opts)
  
  # Validate if requested
  if (opts$validate_schema) {
    validation <- validate_venus_schema(xml_doc)
    if (!validation$valid) {
      warning("XML does not validate against VENUS schema: ", validation$message)
    }
  }
  
  # Write to file
  tryCatch({
    xml2::write_xml(xml_doc, output_path, options = "format")
    file_size <- file.info(output_path)$size
    
    # Count plots
    plot_count <- length(xml2::xml_find_all(xml_doc, "//Plot"))
    
    list(
      success = TRUE,
      file_path = output_path,
      file_size = file_size,
      plot_count = plot_count,
      project_id = project_id,
      export_date = Sys.time()
    )
  }, error = function(e) {
    list(
      success = FALSE,
      error = e$message
    )
  })
}

#' Build Complete VENUS XML Document
#'
#' @param con Database connection
#' @param project_id Project ID(s)
#' @param metadata Project metadata
#' @param opts Export options
#' @return xml2 document object
build_venus_xml_document <- function(con, project_id, metadata, opts) {
  
  # Create root element
  root <- xml2::xml_new_root("VENUSDataset")
  xml2::xml_set_attr(root, "version", "5.0")
  # Do not set a default XML namespace here.
  # A default namespace makes simple XPath queries (e.g. "//Header", "//Plot")
  # return xml_missing unless callers explicitly manage namespaces.
  
  # Add header
  header_node <- build_venus_header(root, metadata)
  
  # Get plot data
  plot_data <- get_plot_data(con, project_id, opts)
  
  if (nrow(plot_data) == 0) {
    warning("No plots found matching export criteria")
    return(root)
  }
  
  # Add plots section
  plots_node <- xml2::xml_add_child(root, "Plots")
  
  # Process each plot
  for (i in seq_len(nrow(plot_data))) {
    plot_row <- plot_data[i, ]
    build_venus_plot(plots_node, con, plot_row, opts)
  }
  
  root
}

#' Build VENUS Header Section
#'
#' @param root XML root node
#' @param metadata Project metadata
#' @return Header XML node
build_venus_header <- function(root, metadata) {
  header <- xml2::xml_add_child(root, "Header")
  
  # Project information
  proj_node <- xml2::xml_add_child(header, "Project")
  xml2::xml_add_child(proj_node, "ProjectID", as.character(metadata$projectid %||% ""))
  xml2::xml_add_child(proj_node, "ProjectName", as.character(metadata$projecttitle %||% ""))
  xml2::xml_add_child(proj_node, "ProjectDescription", as.character(metadata$projectdescription %||% ""))
  
  # Export metadata
  export_node <- xml2::xml_add_child(header, "Export")
  xml2::xml_add_child(export_node, "ExportDate", format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))
  xml2::xml_add_child(export_node, "ExportedBy", Sys.info()["user"])
  xml2::xml_add_child(export_node, "SourceSystem", "VPro R/Shiny")
  xml2::xml_add_child(export_node, "SourceVersion", "1.0")
  
  header
}

#' Build Individual Plot Element
#'
#' @param plots_node Parent Plots XML node
#' @param con Database connection
#' @param plot_row Single row from plot data
#' @param opts Export options
build_venus_plot <- function(plots_node, con, plot_row, opts) {
  
  plot_node <- xml2::xml_add_child(plots_node, "Plot")
  xml2::xml_set_attr(plot_node, "id", as.character(plot_row$plotnumber))
  
  # Basic plot info
  info_node <- xml2::xml_add_child(plot_node, "PlotInfo")
  xml2::xml_add_child(info_node, "PlotNumber", as.character(plot_row$plotnumber))
  xml2::xml_add_child(info_node, "FieldNumber", as.character(plot_row$fieldnumber %||% ""))
  xml2::xml_add_child(info_node, "Date", as.character(plot_row$date %||% ""))
  xml2::xml_add_child(info_node, "PlotRepresenting", as.character(plot_row$plotrepresenting %||% ""))
  
  # Location
  loc_node <- build_venus_location(plot_node, plot_row)
  
  # Site classification
  site_node <- build_venus_site_classification(plot_node, plot_row)
  
  # Vegetation
  veg_data <- get_vegetation_for_plot(con, plot_row$plotnumber, opts)
  if (nrow(veg_data) > 0) {
    veg_node <- build_venus_vegetation(plot_node, veg_data, plot_row)
  }
  
  # Environment
  env_node <- build_venus_environment(plot_node, plot_row)
  
  # Soil
  soil_data <- get_soil_data_for_plot(con, plot_row$plotnumber)
  if (!is.null(soil_data) && (nrow(soil_data$humus) > 0 || nrow(soil_data$mineral) > 0)) {
    soil_node <- build_venus_soil(plot_node, soil_data)
  }
  
  plot_node
}

#' Build Location Section
#'
#' @param plot_node Plot XML node
#' @param plot_row Plot data row
build_venus_location <- function(plot_node, plot_row) {
  loc_node <- xml2::xml_add_child(plot_node, "Location")
  
  # Geographic coordinates (WGS84 decimal degrees)
  if (!is.na(plot_row$latitude) && !is.na(plot_row$longitude)) {
    geo_node <- xml2::xml_add_child(loc_node, "GeographicCoordinates")
    xml2::xml_set_attr(geo_node, "datum", "WGS84")
    xml2::xml_add_child(geo_node, "Latitude", format(plot_row$latitude, nsmall = 6))
    xml2::xml_add_child(geo_node, "Longitude", format(plot_row$longitude, nsmall = 6))
  }
  
  # UTM coordinates
  if (!is.na(plot_row$utmzone) && !is.na(plot_row$utmeasting) && !is.na(plot_row$utmnorthing)) {
    utm_node <- xml2::xml_add_child(loc_node, "UTMCoordinates")
    xml2::xml_set_attr(utm_node, "datum", "NAD83")
    xml2::xml_add_child(utm_node, "Zone", as.character(plot_row$utmzone))
    xml2::xml_add_child(utm_node, "Easting", as.character(plot_row$utmeasting))
    xml2::xml_add_child(utm_node, "Northing", as.character(plot_row$utmnorthing))
  }
  
  # Administrative location
  xml2::xml_add_child(loc_node, "NTSMapSheet", as.character(plot_row$ntsmapsheet %||% ""))
  xml2::xml_add_child(loc_node, "Ecosection", as.character(plot_row$ecosection %||% ""))
  xml2::xml_add_child(loc_node, "Location", as.character(plot_row$`_location` %||% ""))
  xml2::xml_add_child(loc_node, "Elevation", as.character(plot_row$elevation %||% ""))
  
  loc_node
}

#' Build Site Classification Section
#'
#' @param plot_node Plot XML node
#' @param plot_row Plot data row
build_venus_site_classification <- function(plot_node, plot_row) {
  site_node <- xml2::xml_add_child(plot_node, "SiteClassification")
  
  # BEC classification
  bec_node <- xml2::xml_add_child(site_node, "BEC")
  xml2::xml_add_child(bec_node, "Zone", as.character(plot_row$zone %||% ""))
  xml2::xml_add_child(bec_node, "SubZone", as.character(plot_row$subzone %||% ""))
  xml2::xml_add_child(bec_node, "SiteSeries", as.character(plot_row$siteseries %||% ""))
  
  # Site modifiers
  if (!is.na(plot_row$sitemodifier1) && nzchar(as.character(plot_row$sitemodifier1))) {
    xml2::xml_add_child(bec_node, "Modifier", as.character(plot_row$sitemodifier1))
  }
  if (!is.na(plot_row$sitemodifier2) && nzchar(as.character(plot_row$sitemodifier2))) {
    xml2::xml_add_child(bec_node, "Modifier", as.character(plot_row$sitemodifier2))
  }
  
  # Site conditions
  xml2::xml_add_child(site_node, "MoistureRegime", as.character(plot_row$moistureregime %||% ""))
  xml2::xml_add_child(site_node, "NutrientRegime", as.character(plot_row$nutrientregime %||% ""))
  xml2::xml_add_child(site_node, "StructuralStage", as.character(plot_row$structuralstage %||% ""))
  xml2::xml_add_child(site_node, "SuccessionalStatus", as.character(plot_row$successionalstatus %||% ""))
  
  site_node
}

#' Build Vegetation Section
#'
#' @param plot_node Plot XML node
#' @param veg_data Vegetation data for plot
#' @param plot_row Plot data row (for strata totals)
build_venus_vegetation <- function(plot_node, veg_data, plot_row) {
  veg_node <- xml2::xml_add_child(plot_node, "Vegetation")
  
  # Surveyor
  xml2::xml_add_child(veg_node, "Surveyor", as.character(plot_row$vegsurveyor %||% ""))
  
  # Strata totals
  strata_node <- xml2::xml_add_child(veg_node, "StrataTotals")
  xml2::xml_add_child(strata_node, "TreeCover", as.character(plot_row$stratacovertree %||% ""))
  xml2::xml_add_child(strata_node, "ShrubCover", as.character(plot_row$stratacovershrub %||% ""))
  xml2::xml_add_child(strata_node, "HerbCover", as.character(plot_row$stratacoverherb %||% ""))
  xml2::xml_add_child(strata_node, "MossCover", as.character(plot_row$stratacovermoss %||% ""))
  
  # Group by layer (handle both uppercase and lowercase column names)
  layer_col <- if ("mylayer" %in% names(veg_data)) "mylayer" else "MyLayer"
  species_col <- if ("species" %in% names(veg_data)) "species" else "Species"
  cover_col <- if ("cover" %in% names(veg_data)) "cover" else "Cover"
  
  layers <- unique(veg_data[[layer_col]])
  
  for (layer_code in sort(layers)) {
    layer_data <- veg_data[veg_data[[layer_col]] == layer_code, ]
    
    layer_node <- xml2::xml_add_child(veg_node, "Layer")
    xml2::xml_set_attr(layer_node, "code", as.character(layer_code))
    xml2::xml_set_attr(layer_node, "name", get_layer_name(layer_code))
    
    # Add species
    for (j in seq_len(nrow(layer_data))) {
      spp_row <- layer_data[j, ]
      spp_node <- xml2::xml_add_child(layer_node, "Species")
      xml2::xml_set_attr(spp_node, "code", as.character(spp_row[[species_col]]))
      xml2::xml_add_child(spp_node, "Cover", as.character(spp_row[[cover_col]]))
    }
  }
  
  # Notes
  if (!is.na(plot_row$vegnotes) && nzchar(as.character(plot_row$vegnotes))) {
    xml2::xml_add_child(veg_node, "Notes", as.character(plot_row$vegnotes))
  }
  
  veg_node
}

#' Build Environment Section
#'
#' @param plot_node Plot XML node
#' @param plot_row Plot data row
build_venus_environment <- function(plot_node, plot_row) {
  env_node <- xml2::xml_add_child(plot_node, "Environment")
  
  # Surveyor
  xml2::xml_add_child(env_node, "Surveyor", as.character(plot_row$sitesurveyor %||% ""))
  
  # Topography
  topo_node <- xml2::xml_add_child(env_node, "Topography")
  xml2::xml_add_child(topo_node, "Aspect", as.character(plot_row$aspect %||% ""))
  xml2::xml_add_child(topo_node, "SlopeGradient", as.character(plot_row$slopegradient %||% ""))
  xml2::xml_add_child(topo_node, "MesoSlopePosition", as.character(plot_row$mesoslopeposition %||% ""))
  xml2::xml_add_child(topo_node, "SurfaceShape", as.character(plot_row$surfaceshape %||% ""))
  
  # Substrate
  substr_node <- xml2::xml_add_child(env_node, "Substrate")
  xml2::xml_add_child(substr_node, "DecayedWood", as.character(plot_row$substratedecwood %||% ""))
  xml2::xml_add_child(substr_node, "Bedrock", as.character(plot_row$substratebedrock %||% ""))
  xml2::xml_add_child(substr_node, "Rocks", as.character(plot_row$substraterocks %||% ""))
  xml2::xml_add_child(substr_node, "MineralSoil", as.character(plot_row$substratemineralsoil %||% ""))
  xml2::xml_add_child(substr_node, "OrganicMatter", as.character(plot_row$substrateorganicmatter %||% ""))
  xml2::xml_add_child(substr_node, "Water", as.character(plot_row$substratewater %||% ""))
  
  # Disturbance
  if (!is.na(plot_row$sitedisturbance1) && nzchar(as.character(plot_row$sitedisturbance1))) {
    dist_node <- xml2::xml_add_child(env_node, "Disturbances")
    xml2::xml_add_child(dist_node, "Disturbance", as.character(plot_row$sitedisturbance1))
    if (!is.na(plot_row$sitedisturbance2) && nzchar(as.character(plot_row$sitedisturbance2))) {
      xml2::xml_add_child(dist_node, "Disturbance", as.character(plot_row$sitedisturbance2))
    }
    if (!is.na(plot_row$sitedisturbance3) && nzchar(as.character(plot_row$sitedisturbance3))) {
      xml2::xml_add_child(dist_node, "Disturbance", as.character(plot_row$sitedisturbance3))
    }
  }
  
  # Notes
  if (!is.na(plot_row$sitenotes) && nzchar(as.character(plot_row$sitenotes))) {
    xml2::xml_add_child(env_node, "Notes", as.character(plot_row$sitenotes))
  }
  
  env_node
}

#' Build Soil Section
#'
#' @param plot_node Plot XML node
#' @param soil_data List containing humus and mineral horizon data
build_venus_soil <- function(plot_node, soil_data) {
  soil_node <- xml2::xml_add_child(plot_node, "Soil")
  
  # Organic (Humus) horizons
  if (nrow(soil_data$humus) > 0) {
    organic_node <- xml2::xml_add_child(soil_node, "OrganicHorizons")
    
    for (i in seq_len(nrow(soil_data$humus))) {
      hz_row <- soil_data$humus[i, ]
      hz_node <- xml2::xml_add_child(organic_node, "Horizon")
      
      xml2::xml_add_child(hz_node, "HorizonCode", as.character(hz_row$horizon %||% ""))
      xml2::xml_add_child(hz_node, "UpperDepth", as.character(hz_row$upperdepth %||% ""))
      xml2::xml_add_child(hz_node, "LowerDepth", as.character(hz_row$lowerdepth %||% ""))
      xml2::xml_add_child(hz_node, "vonPost", as.character(hz_row$vonpost %||% ""))
      xml2::xml_add_child(hz_node, "pH", as.character(hz_row$humusformpH %||% ""))
      
      if (!is.na(hz_row$`_comment`) && nzchar(as.character(hz_row$`_comment`))) {
        xml2::xml_add_child(hz_node, "Comments", as.character(hz_row$`_comment`))
      }
    }
  }
  
  # Mineral horizons
  if (nrow(soil_data$mineral) > 0) {
    mineral_node <- xml2::xml_add_child(soil_node, "MineralHorizons")
    
    for (i in seq_len(nrow(soil_data$mineral))) {
      hz_row <- soil_data$mineral[i, ]
      hz_node <- xml2::xml_add_child(mineral_node, "Horizon")
      
      xml2::xml_add_child(hz_node, "HorizonCode", as.character(hz_row$horizon %||% ""))
      xml2::xml_add_child(hz_node, "UpperDepth", as.character(hz_row$upperdepth %||% ""))
      xml2::xml_add_child(hz_node, "LowerDepth", as.character(hz_row$lowerdepth %||% ""))
      xml2::xml_add_child(hz_node, "Colour", as.character(hz_row$colour %||% ""))
      xml2::xml_add_child(hz_node, "Texture", as.character(hz_row$texture %||% ""))
      xml2::xml_add_child(hz_node, "CoarseFragments", as.character(hz_row$percentcoarsefragstotal %||% ""))
      xml2::xml_add_child(hz_node, "pH", as.character(hz_row$mineralformpH %||% ""))
      
      if (!is.na(hz_row$`_comments`) && nzchar(as.character(hz_row$`_comments`))) {
        xml2::xml_add_child(hz_node, "Comments", as.character(hz_row$`_comments`))
      }
    }
  }
  
  soil_node
}

#' Get Project Metadata
#'
#' @param con Database connection
#' @param project_id Project ID
#' @return Dataframe with project metadata
get_project_metadata <- function(con, project_id) {
  if (is.null(project_id)) {
    # Return default metadata
    return(data.frame(
      projectid = "UNKNOWN",
      projecttitle = "VPro Export",
      projectdescription = "",
      stringsAsFactors = FALSE
    ))
  }
  
  project_db <- config("Current", "CurrProject")
  metadata_table_id <- if (!is.null(project_db) && nzchar(trimws(as.character(project_db)))) db_id("Metadata", project_db, prj = TRUE) else NULL
  metadata_exists <- !is.null(metadata_table_id) && isTRUE(tryCatch(DBI::dbExistsTable(con, metadata_table_id), error = function(e) FALSE))
  if (!metadata_exists) {
    return(data.frame(
      projectid = project_id,
      projecttitle = paste("Project", project_id),
      projectdescription = "",
      stringsAsFactors = FALSE
    ))
  }

  metadata_table_sql <- as.character(DBI::dbQuoteIdentifier(con, metadata_table_id))

  sql <- paste("SELECT projectid, projecttitle, projectdescription FROM", metadata_table_sql, "WHERE projectid = ?")
  result <- DBI::dbGetQuery(con, sql, list(project_id))
  
  if (nrow(result) == 0) {
    return(data.frame(
      projectid = project_id,
      projecttitle = paste("Project", project_id),
      projectdescription = "",
      stringsAsFactors = FALSE
    ))
  }
  
  result[1, ]
}

#' Get Plot Data for Export
#'
#' @param con Database connection
#' @param project_id Project ID(s)
#' @param opts Export options
#' @return Dataframe with plot environmental data
get_plot_data <- function(con, project_id, opts) {
  
  # Base query
  env_table_sql <- as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
  sql <- paste("SELECT * FROM", env_table_sql, "WHERE 1=1")
  params <- list()
  
  # Filter by project
  if (!is.null(project_id)) {
    sql <- paste(sql, "AND projectid = ?")
    params <- c(params, list(project_id))
  }
  
  # Exclude draft plots
  if (!opts$include_draft) {
    sql <- paste(sql, "AND (temporary IS NULL OR temporary = 0)")
    sql <- paste(sql, "AND (flag IS NULL OR flag = 0)")
  }
  
  # Filter by date range
  if (!is.null(opts$date_from)) {
    sql <- paste(sql, "AND date >= ?")
    params <- c(params, list(opts$date_from))
  }
  if (!is.null(opts$date_to)) {
    sql <- paste(sql, "AND date <= ?")
    params <- c(params, list(opts$date_to))
  }
  
  # Require coordinates
  if (opts$coords_required) {
    sql <- paste(sql, "AND latitude IS NOT NULL AND longitude IS NOT NULL")
  }
  
  sql <- paste(sql, "ORDER BY plotnumber")
  
  DBI::dbGetQuery(con, sql, params)
}

#' Get Vegetation Data for Single Plot
#'
#' @param con Database connection
#' @param plot_number Plot number
#' @param opts Export options
#' @return Dataframe with vegetation data
get_vegetation_for_plot <- function(con, plot_number, opts) {
  
  # Use the unpivoted view
  sql <- "SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg WHERE PlotNumber = ?"
  veg_data <- DBI::dbGetQuery(con, sql, list(plot_number))
  
  if (nrow(veg_data) == 0) {
    return(veg_data)
  }
  
  # Normalize column names to lowercase for consistency
  names(veg_data) <- tolower(names(veg_data))
  
  # Apply lumping if requested
  if (opts$apply_lumping) {
    # Convert cover to numeric for lumping (trace values to 0.1)
    veg_data$cover_num <- suppressWarnings(as.numeric(veg_data$cover))
    veg_data$cover_num[is.na(veg_data$cover_num) & nzchar(trimws(veg_data$cover))] <- 0.1
    
    # Apply lumping
    veg_data <- apply_lumping(
      con, 
      veg_data,
      group_cols = c("plotnumber", "mylayer"),
      measure_cols = c("cover_num")
    )
    
    # Convert back to original cover format
    # If cover_num is very small (< 1), use trace code, otherwise use number
    veg_data$cover <- ifelse(
      veg_data$cover_num < 1,
      "+",  # Trace
      as.character(round(veg_data$cover_num))
    )
  }
  
  veg_data
}

#' Get Soil Horizon Data for Plot
#'
#' @param con Database connection
#' @param plot_number Plot number
#' @return List with humus and mineral dataframes
get_soil_data_for_plot <- function(con, plot_number) {
  
  # Get humus horizons
  humus_table_id <- db_id("Humus", config("Current", "CurrProject"), prj = TRUE)
  humus_exists <- isTRUE(tryCatch(DBI::dbExistsTable(con, humus_table_id), error = function(e) FALSE))
  humus_table_sql <- if (humus_exists) as.character(DBI::dbQuoteIdentifier(con, humus_table_id)) else NULL
  sql_humus <- if (is.null(humus_table_sql)) NULL else paste("SELECT * FROM", humus_table_sql, "WHERE PlotNumber = ? ORDER BY UpperDepth")
  humus <- if (is.null(sql_humus)) data.frame() else DBI::dbGetQuery(con, sql_humus, list(plot_number))
  
  # Get mineral horizons
  mineral_table_id <- db_id("Mineral", config("Current", "CurrProject"), prj = TRUE)
  mineral_exists <- isTRUE(tryCatch(DBI::dbExistsTable(con, mineral_table_id), error = function(e) FALSE))
  mineral_table_sql <- if (mineral_exists) as.character(DBI::dbQuoteIdentifier(con, mineral_table_id)) else NULL
  sql_mineral <- if (is.null(mineral_table_sql)) NULL else paste("SELECT * FROM", mineral_table_sql, "WHERE PlotNumber = ? ORDER BY UpperDepth")
  mineral <- if (is.null(sql_mineral)) data.frame() else DBI::dbGetQuery(con, sql_mineral, list(plot_number))
  
  list(
    humus = humus,
    mineral = mineral
  )
}

#' Get Layer Name from Code
#'
#' @param layer_code Numeric layer code (1-7)
#' @return Character layer name
get_layer_name <- function(layer_code) {
  layer_names <- c(
    "1" = "Tree Layer A1",
    "2" = "Tree Layer A2",
    "3" = "Tree Layer A3",
    "4" = "Shrub Layer B1",
    "5" = "Shrub Layer B2",
    "6" = "Herb Layer C",
    "7" = "Moss Layer D"
  )
  
  layer_names[as.character(layer_code)] %||% paste("Layer", layer_code)
}

#' Validate VENUS XML Against Schema
#'
#' @param xml_doc xml2 document object
#' @return List with valid (TRUE/FALSE) and message
validate_venus_schema <- function(xml_doc) {
  # Placeholder - would require VENUS XSD schema file
  # For now, just check basic structure
  
  plots <- xml2::xml_find_all(xml_doc, "//Plot")
  
  if (length(plots) == 0) {
    return(list(
      valid = FALSE,
      message = "No plots found in document"
    ))
  }
  
  # Check each plot has required elements
  for (plot in plots) {
    if (length(xml2::xml_find_all(plot, "PlotInfo")) == 0) {
      return(list(
        valid = FALSE,
        message = "Plot missing PlotInfo element"
      ))
    }
    if (length(xml2::xml_find_all(plot, "Location")) == 0) {
      return(list(
        valid = FALSE,
        message = "Plot missing Location element"
      ))
    }
  }
  
  list(
    valid = TRUE,
    message = "Basic structure validation passed"
  )
}

#' Helper: NULL coalescing operator
#' @keywords internal
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(a)))) return(b)
  a
}
