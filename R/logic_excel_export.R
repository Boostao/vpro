# Excel Export Logic with Styled Formatting
# Provides Access-report-like experience in Excel with formatted tables, headers, and conditional formatting

#' Export Vegetation Data to Styled Excel Workbook
#'
#' @param con Database connection
#' @param output_path Path to save .xlsx file
#' @param options List with export options:
#'   - project_ids: Character vector of project IDs to filter (NULL = all)
#'   - layers: Character vector of layers to include (default: 1-7)
#'   - apply_lumping: Boolean, apply species synonym consolidation
#'   - separate_sheets: Boolean, create separate sheet per layer (default TRUE)
#'   - include_metadata: Boolean, add metadata sheet
#'   - conditional_formatting: Boolean, apply conditional formatting (default TRUE)
#' @return Invisibly returns TRUE on success
export_vegetation_excel <- function(con, output_path, options = list()) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("openxlsx package is required for Excel export. Install with: install.packages('openxlsx')")
  }
  
  # Default options
  opts <- list(
    project_ids = NULL,
    layers = c("1", "2", "3", "4", "5", "6", "7"),
    apply_lumping = FALSE,
    separate_sheets = TRUE,
    include_metadata = TRUE,
    conditional_formatting = TRUE
  )
  opts[names(options)] <- options
  
  # Create workbook
  wb <- openxlsx::createWorkbook()
  
  # Get data
  veg_data <- get_vegetation_data_for_excel(con, opts$project_ids, opts$layers, opts$apply_lumping)
  
  if (nrow(veg_data) == 0) {
    warning("No vegetation data found for export")
    return(invisible(FALSE))
  }
  
  # Export by layer (separate sheets) or combined
  if (opts$separate_sheets) {
    layers_present <- unique(veg_data$Layer)
    layer_names <- c("1" = "VegA_Trees1", "2" = "VegA_Trees2", "3" = "VegA_Trees3",
                     "4" = "VegB_Shrub1", "5" = "VegB_Shrub2", 
                     "6" = "VegC_Herbs", "7" = "VegD_Moss")
    
    for (layer in layers_present) {
      layer_data <- veg_data[veg_data$Layer == layer, ]
      sheet_name <- layer_names[layer]
      if (is.na(sheet_name)) sheet_name <- paste0("Layer_", layer)
      
      add_vegetation_sheet(wb, sheet_name, layer_data, opts$conditional_formatting)
    }
  } else {
    add_vegetation_sheet(wb, "Vegetation", veg_data, opts$conditional_formatting)
  }
  
  # Add metadata sheet if requested
  if (opts$include_metadata && !is.null(opts$project_ids)) {
    add_metadata_sheet(wb, con, opts$project_ids)
  }
  
  # Add instructions/data dictionary
  add_instructions_sheet(wb)
  
  # Save workbook
  openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
  
  invisible(TRUE)
}

#' Export Environment/Site Data to Styled Excel Workbook
#'
#' @param con Database connection
#' @param output_path Path to save .xlsx file
#' @param options List with export options (similar to vegetation export)
#' @return Invisibly returns TRUE on success
export_environment_excel <- function(con, output_path, options = list()) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("openxlsx package is required for Excel export")
  }
  
  opts <- list(
    project_ids = NULL,
    include_soil = TRUE,
    include_metadata = TRUE,
    conditional_formatting = TRUE
  )
  opts[names(options)] <- options
  
  wb <- openxlsx::createWorkbook()
  
  # Get environment data
  env_data <- get_environment_data_for_excel(con, opts$project_ids)
  
  if (nrow(env_data) > 0) {
    add_environment_sheet(wb, "Environment", env_data, opts$conditional_formatting)
  }
  
  # Get soil data if requested
  if (opts$include_soil) {
    humus_data <- get_soil_humus_data(con, opts$project_ids)
    mineral_data <- get_soil_mineral_data(con, opts$project_ids)
    
    if (nrow(humus_data) > 0) {
      add_soil_sheet(wb, "Soil_Humus", humus_data, "humus", opts$conditional_formatting)
    }
    if (nrow(mineral_data) > 0) {
      add_soil_sheet(wb, "Soil_Mineral", mineral_data, "mineral", opts$conditional_formatting)
    }
  }
  
  # Add metadata
  if (opts$include_metadata && !is.null(opts$project_ids)) {
    add_metadata_sheet(wb, con, opts$project_ids)
  }
  
  add_instructions_sheet(wb)
  
  openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
  invisible(TRUE)
}

#' Export Combined Dataset (Vegetation + Environment + Metadata)
#'
#' @param con Database connection
#' @param output_path Path to save .xlsx file
#' @param options List with export options
#' @return Invisibly returns TRUE on success
export_combined_excel <- function(con, output_path, options = list()) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("openxlsx package is required for Excel export")
  }
  
  opts <- list(
    project_ids = NULL,
    layers = c("1", "2", "3", "4", "5", "6", "7"),
    apply_lumping = FALSE,
    include_soil = TRUE,
    conditional_formatting = TRUE
  )
  opts[names(options)] <- options
  
  wb <- openxlsx::createWorkbook()
  
  # Vegetation sheets (by layer)
  veg_data <- get_vegetation_data_for_excel(con, opts$project_ids, opts$layers, opts$apply_lumping)
  if (nrow(veg_data) > 0) {
    layers_present <- unique(veg_data$Layer)
    layer_names <- c("1" = "VegA_Trees1", "2" = "VegA_Trees2", "3" = "VegA_Trees3",
                     "4" = "VegB_Shrub1", "5" = "VegB_Shrub2", 
                     "6" = "VegC_Herbs", "7" = "VegD_Moss")
    
    for (layer in layers_present) {
      layer_data <- veg_data[veg_data$Layer == layer, ]
      sheet_name <- layer_names[layer]
      if (is.na(sheet_name)) sheet_name <- paste0("Layer_", layer)
      add_vegetation_sheet(wb, sheet_name, layer_data, opts$conditional_formatting)
    }
  }
  
  # Environment sheet
  env_data <- get_environment_data_for_excel(con, opts$project_ids)
  if (nrow(env_data) > 0) {
    add_environment_sheet(wb, "Environment", env_data, opts$conditional_formatting)
  }
  
  # Soil sheets
  if (opts$include_soil) {
    humus_data <- get_soil_humus_data(con, opts$project_ids)
    mineral_data <- get_soil_mineral_data(con, opts$project_ids)
    
    if (nrow(humus_data) > 0) {
      add_soil_sheet(wb, "Soil_Humus", humus_data, "humus", opts$conditional_formatting)
    }
    if (nrow(mineral_data) > 0) {
      add_soil_sheet(wb, "Soil_Mineral", mineral_data, "mineral", opts$conditional_formatting)
    }
  }
  
  # Metadata
  if (!is.null(opts$project_ids)) {
    add_metadata_sheet(wb, con, opts$project_ids)
  }
  
  add_instructions_sheet(wb)
  
  openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
  invisible(TRUE)
}

#' Get Vegetation Data Formatted for Excel Export
#' @keywords internal
get_vegetation_data_for_excel <- function(con, project_ids = NULL, layers = c("1", "2", "3", "4", "5", "6", "7"), apply_lumping = FALSE) {
  
  # Build query
  layers_sql <- paste(paste0("'", layers, "'"), collapse = ", ")
  query <- sprintf("SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg WHERE MyLayer IN (%s)", layers_sql)
  
  # Filter by project if specified
  if (!is.null(project_ids) && length(project_ids) > 0) {
    projs_sql <- paste(paste0("'", project_ids, "'"), collapse = ", ")
    query <- sprintf("SELECT v.* FROM vw_USysAllVeg v 
                      JOIN Sample_Env e ON v.PlotNumber = e.plotnumber 
                      WHERE v.MyLayer IN (%s) AND e.projectid IN (%s)", 
                     layers_sql, projs_sql)
  }
  
  df <- DBI::dbGetQuery(con, query)
  
  if (nrow(df) == 0) return(df)

  # Normalize column names for compatibility with lumping logic
  names(df) <- tolower(names(df))
  
  # Convert cover to numeric (handle text codes)
  cover_chr <- trimws(as.character(df$cover))
  cover_num <- suppressWarnings(as.numeric(cover_chr))
  cover_num[cover_chr == ""] <- NA_real_
  cover_num[is.na(cover_num) & nzchar(cover_chr)] <- 0.1  # '+' or 'r' codes
  df$cover_num <- cover_num
  
  # Apply lumping if requested
  if (apply_lumping) {
    if (!exists("apply_lumping", mode = "function")) {
      stop("apply_lumping() not found. Source R/logic_lumping.R before using apply_lumping = TRUE.")
    }
    df <- apply_lumping(
      con,
      df,
      group_cols = c("plotnumber", "mylayer"),
      measure_cols = c("cover_num")
    )
  }
  
  # Join species names
  meta_table <- NULL
  has_lists_specs <- tryCatch({
    DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_catalog = 'lists' AND table_name = 'USysAllSpecs'"
    )$n > 0
  }, error = function(e) FALSE)

  if (isTRUE(has_lists_specs)) {
    meta_table <- "lists.USysAllSpecs"
  } else if (DBI::dbExistsTable(con, "USysAllSpecs")) {
    meta_table <- "USysAllSpecs"
  } else if (DBI::dbExistsTable(con, "SppList")) {
    meta_table <- "SppList"
  }

  spp <- data.frame(code = character(), scientificname = character(), commonname = character())
  if (!is.null(meta_table) && identical(meta_table, "SppList")) {
    spp <- DBI::dbGetQuery(con, "SELECT code, scientificname, '' AS commonname FROM SppList")
  } else if (!is.null(meta_table)) {
    spp <- DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT code AS code, scientificname AS scientificname, COALESCE(common_name_pb, englishname, combinedenglishname, '') AS commonname FROM %s",
        meta_table
      )
    )
  }

  if (nrow(spp) > 0 && "code" %in% names(spp)) {
    spp <- spp[!duplicated(spp$code), , drop = FALSE]
  }
  
  df <- merge(df, spp, by.x = "species", by.y = "code", all.x = TRUE)
  df$ScientificName <- ifelse(is.na(df$scientificname), df$species, df$scientificname)
  df$CommonName <- ifelse(is.na(df$commonname), "", df$commonname)
  
  # Select and order columns for Excel
  df <- df[, c("plotnumber", "mylayer", "species", "ScientificName", "CommonName", "cover_num")]
  colnames(df) <- c("Plot", "Layer", "Code", "Scientific Name", "Common Name", "Cover %")
  
  df[order(df$Plot, df$Layer, df$`Scientific Name`), ]
}

#' Get Environment Data Formatted for Excel Export
#' @keywords internal
get_environment_data_for_excel <- function(con, project_ids = NULL) {
  
  # Key environment fields
  query <- "SELECT 
    plotnumber AS Plot,
    projectid AS Project,
    _location AS Location,
    date AS Date,
    sitesurveyor AS Surveyor,
    latitude AS Latitude,
    longitude AS Longitude,
    elevation AS Elevation,
    slopegradient AS Slope,
    aspect AS Aspect,
    _zone AS Zone,
    subzone AS Subzone,
    siteseries AS \"Site Series\",
    moistureregime AS Moisture,
    nutrientregime AS Nutrient,
    sitenotes AS Notes
  FROM Sample_Env"
  
  if (!is.null(project_ids) && length(project_ids) > 0) {
    projs_sql <- paste(paste0("'", project_ids, "'"), collapse = ", ")
    query <- paste0(query, sprintf(" WHERE projectid IN (%s)", projs_sql))
  }
  
  query <- paste(query, "ORDER BY projectid, plotnumber")
  
  DBI::dbGetQuery(con, query)
}

#' Get Soil Humus Data
#' @keywords internal
get_soil_humus_data <- function(con, project_ids = NULL) {
  
  query <- "SELECT 
    h.plotnumber AS Plot,
    h.horizon AS Horizon,
    h.upperdepth AS 'Upper Depth (cm)',
    h.lowerdepth AS 'Lower Depth (cm)',
    h.humusformbh AS 'Humus Form pH',
    h.vonpost AS 'von Post',
    h.comment AS Comment
  FROM Sample_Humus h"
  
  if (!is.null(project_ids) && length(project_ids) > 0) {
    projs_sql <- paste(paste0("'", project_ids, "'"), collapse = ", ")
    query <- paste0(query, sprintf(" 
      JOIN Sample_Env e ON h.plotnumber = e.plotnumber
      WHERE e.projectid IN (%s)", projs_sql))
  }
  
  query <- paste(query, "ORDER BY h.plotnumber, h.upperdepth")
  
  tryCatch(
    DBI::dbGetQuery(con, query),
    error = function(e) data.frame()  # Table may not exist
  )
}

#' Get Soil Mineral Data
#' @keywords internal
get_soil_mineral_data <- function(con, project_ids = NULL) {
  
  query <- "SELECT 
    m.plotnumber AS Plot,
    m.horizon AS Horizon,
    m.upperdepth AS 'Upper Depth (cm)',
    m.lowerdepth AS 'Lower Depth (cm)',
    m.texture AS Texture,
    m.percentcoarsefragstotal AS 'Coarse Frags %',
    m.mineralformbh AS 'pH',
    m.comments AS Comment
  FROM Sample_Mineral m"
  
  if (!is.null(project_ids) && length(project_ids) > 0) {
    projs_sql <- paste(paste0("'", project_ids, "'"), collapse = ", ")
    query <- paste0(query, sprintf(" 
      JOIN Sample_Env e ON m.plotnumber = e.plotnumber
      WHERE e.projectid IN (%s)", projs_sql))
  }
  
  query <- paste(query, "ORDER BY m.plotnumber, m.upperdepth")
  
  tryCatch(
    DBI::dbGetQuery(con, query),
    error = function(e) data.frame()
  )
}

#' Add Vegetation Sheet with Styling
#' @keywords internal
add_vegetation_sheet <- function(wb, sheet_name, data, apply_formatting = TRUE) {
  
  openxlsx::addWorksheet(wb, sheet_name)
  
  # Write data
  openxlsx::writeData(wb, sheet_name, data, startRow = 1, startCol = 1)
  
  if (apply_formatting && nrow(data) > 0) {
    apply_excel_styles(wb, sheet_name, data, "vegetation")
  }
  
  # Freeze header row
  openxlsx::freezePane(wb, sheet_name, firstRow = TRUE)
  
  # Auto-filter
  openxlsx::addFilter(wb, sheet_name, row = 1, cols = 1:ncol(data))
}

#' Add Environment Sheet with Styling
#' @keywords internal
add_environment_sheet <- function(wb, sheet_name, data, apply_formatting = TRUE) {
  
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, data, startRow = 1, startCol = 1)
  
  if (apply_formatting && nrow(data) > 0) {
    apply_excel_styles(wb, sheet_name, data, "environment")
  }
  
  openxlsx::freezePane(wb, sheet_name, firstRow = TRUE)
  openxlsx::addFilter(wb, sheet_name, row = 1, cols = 1:ncol(data))
}

#' Add Soil Sheet with Styling
#' @keywords internal
add_soil_sheet <- function(wb, sheet_name, data, soil_type = "humus", apply_formatting = TRUE) {
  
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, data, startRow = 1, startCol = 1)
  
  if (apply_formatting && nrow(data) > 0) {
    apply_excel_styles(wb, sheet_name, data, "soil")
  }
  
  openxlsx::freezePane(wb, sheet_name, firstRow = TRUE)
  openxlsx::addFilter(wb, sheet_name, row = 1, cols = 1:ncol(data))
}

#' Add Metadata Sheet
#' @keywords internal
add_metadata_sheet <- function(wb, con, project_ids) {
  
  projs_sql <- paste(paste0("'", project_ids, "'"), collapse = ", ")
  query <- sprintf("SELECT 
    projectid AS 'Project ID',
    projecttitle AS 'Project Title',
    fieldleader AS 'Project Lead',
    coordinatingagency AS Organisation,
    projectpurpose AS Purpose,
    NULL AS Status,
    startdate AS 'Start Date',
    enddate AS 'End Date'
  FROM Sample_Metadata
  WHERE projectid IN (%s)", projs_sql)
  
  meta <- DBI::dbGetQuery(con, query)
  
  if (nrow(meta) > 0) {
    openxlsx::addWorksheet(wb, "Project_Metadata")
    openxlsx::writeData(wb, "Project_Metadata", meta, startRow = 1, startCol = 1)
    apply_excel_styles(wb, "Project_Metadata", meta, "metadata")
    openxlsx::freezePane(wb, "Project_Metadata", firstRow = TRUE)
  }
}

#' Add Instructions/Data Dictionary Sheet
#' @keywords internal
add_instructions_sheet <- function(wb) {
  
  instructions <- data.frame(
    Section = c(
      "Overview",
      "Vegetation Sheets",
      "Environment Sheet",
      "Soil Sheets",
      "Data Codes",
      "Cover Values",
      "Contact"
    ),
    Description = c(
      "This workbook contains field data from VPRO (Vegetation Resources Inventory). Data is organized by sheet type.",
      "VegA/B/C/D sheets contain species observations by layer (A=Trees, B=Shrubs, C=Herbs, D=Moss). Cover values are numeric (0-100%).",
      "Environment sheet contains plot-level site characteristics: location, BEC zone, slope, aspect, etc.",
      "Soil_Humus and Soil_Mineral sheets contain soil profile descriptions by horizon.",
      "Species codes follow BC standard nomenclature. See SppList for full names.",
      "Cover: 0-100 = percent cover. Special codes: '+' = trace (<1%), 'r' = rare, 'P' = present.",
      "For questions about this data, contact the project lead listed in Project_Metadata sheet."
    )
  )
  
  openxlsx::addWorksheet(wb, "Instructions")
  openxlsx::writeData(wb, "Instructions", instructions, startRow = 1, startCol = 1)
  
  # Style instructions
  header_style <- openxlsx::createStyle(
    fgFill = "#4472C4",
    halign = "center",
    textDecoration = "bold",
    fontColour = "#FFFFFF",
    fontSize = 12
  )
  openxlsx::addStyle(wb, "Instructions", header_style, rows = 1, cols = 1:2, gridExpand = TRUE)
  
  # Set column widths
  openxlsx::setColWidths(wb, "Instructions", cols = 1, widths = 20)
  openxlsx::setColWidths(wb, "Instructions", cols = 2, widths = 80)
  
  openxlsx::freezePane(wb, "Instructions", firstRow = TRUE)
}

#' Apply Excel Styles to a Sheet
#'
#' @param workbook openxlsx workbook object
#' @param sheet_name Name of the sheet to style
#' @param data The data frame written to the sheet
#' @param table_type Type of table: "vegetation", "environment", "soil", "metadata"
#' @return NULL (modifies workbook in place)
apply_excel_styles <- function(workbook, sheet_name, data, table_type = "vegetation") {
  
  n_rows <- nrow(data)
  n_cols <- ncol(data)
  
  # Header Style (Access-like blue header)
  header_style <- openxlsx::createStyle(
    fgFill = "#4472C4",
    halign = "center",
    textDecoration = "bold",
    fontColour = "#FFFFFF",
    fontSize = 11,
    border = "TopBottomLeftRight",
    borderColour = "#FFFFFF"
  )
  
  openxlsx::addStyle(workbook, sheet_name, header_style, rows = 1, cols = 1:n_cols, gridExpand = TRUE)
  
  # Alternating row colors (light gray every other row)
  if (n_rows > 1) {
    even_row_style <- openxlsx::createStyle(fgFill = "#F2F2F2")
    even_rows <- seq(2, n_rows + 1, by = 2)
    if (length(even_rows) > 0) {
      openxlsx::addStyle(workbook, sheet_name, even_row_style, rows = even_rows, cols = 1:n_cols, gridExpand = TRUE, stack = TRUE)
    }
  }
  
  # Set column widths based on table type
  if (table_type == "vegetation") {
    widths <- c(12, 6, 10, 25, 25, 8)  # Plot, Layer, Code, Sci Name, Common Name, Cover
    for (i in seq_along(widths)) {
      if (i <= n_cols) {
        openxlsx::setColWidths(workbook, sheet_name, cols = i, widths = widths[i])
      }
    }
    
    # Conditional formatting for cover values (if Cover % column exists)
    cover_col <- which(colnames(data) == "Cover %")
    if (length(cover_col) > 0 && n_rows > 0) {
      # High cover (>75%) = green
      high_cover_style <- openxlsx::createStyle(fgFill = "#C6EFCE")
      openxlsx::conditionalFormatting(
        workbook, sheet_name,
        cols = cover_col,
        rows = 2:(n_rows + 1),
        rule = ">75",
        style = high_cover_style
      )
      
      # Missing cover = yellow
      missing_style <- openxlsx::createStyle(fgFill = "#FFF2CC")
      openxlsx::conditionalFormatting(
        workbook, sheet_name,
        cols = cover_col,
        rows = 2:(n_rows + 1),
        type = "blanks",
        style = missing_style
      )
    }
    
  } else if (table_type == "environment") {
    # Auto-size most columns, set specific widths for key fields
    openxlsx::setColWidths(workbook, sheet_name, cols = 1:n_cols, widths = "auto")
    
    # Override specific columns
    col_names <- colnames(data)
    if ("Plot" %in% col_names) {
      openxlsx::setColWidths(workbook, sheet_name, cols = which(col_names == "Plot"), widths = 12)
    }
    if ("Location" %in% col_names) {
      openxlsx::setColWidths(workbook, sheet_name, cols = which(col_names == "Location"), widths = 25)
    }
    if ("Notes" %in% col_names) {
      openxlsx::setColWidths(workbook, sheet_name, cols = which(col_names == "Notes"), widths = 40)
    }
    
  } else if (table_type == "soil") {
    openxlsx::setColWidths(workbook, sheet_name, cols = 1:n_cols, widths = "auto")
    
  } else {  # metadata or other
    openxlsx::setColWidths(workbook, sheet_name, cols = 1:n_cols, widths = "auto")
  }
  
  # Number formatting
  if (table_type == "vegetation") {
    cover_col <- which(colnames(data) == "Cover %")
    if (length(cover_col) > 0) {
      num_style <- openxlsx::createStyle(numFmt = "0.00")
      openxlsx::addStyle(workbook, sheet_name, num_style, rows = 2:(n_rows + 1), cols = cover_col, gridExpand = TRUE, stack = TRUE)
    }
  }
  
  if (table_type %in% c("environment", "soil")) {
    # Format numeric columns to 2 decimal places
    numeric_cols <- sapply(data, is.numeric)
    if (any(numeric_cols)) {
      num_style <- openxlsx::createStyle(numFmt = "0.00")
      for (col_idx in which(numeric_cols)) {
        openxlsx::addStyle(workbook, sheet_name, num_style, rows = 2:(n_rows + 1), cols = col_idx, gridExpand = TRUE, stack = TRUE)
      }
    }
  }
  
  invisible(NULL)
}
