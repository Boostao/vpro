# Environmental Data Statistics for Reports
#
# Ported from VPro64 Access VBA module: V7mdlReportsEnv.txt
#
# Provides functions for:
# - Environmental variable summary statistics
# - Frequency distributions for categorical variables
# - Transpose helpers (plots as columns)
# - Environmental data quality summaries

#' Calculate summary statistics for numeric environmental variables
#'
#' Returns mean, median, min, max, SD for numeric env columns
#'
#' @param env_df Data frame with environmental data
#' @param numeric_vars Character vector of numeric column names (auto-detect if NULL)
#' @return Data frame with Variable, Mean, Median, Min, Max, SD, N columns
#' @export
#' @family environmental-reports
#'
#' @examples
#' \dontrun{
#' env <- data.frame(
#'   PlotNumber = c("001", "002", "003"),
#'   Elevation = c(450, 520, 380),
#'   SlopeGradient = c(15, 25, 10)
#' )
#' summarize_env_numeric(env)
#' }
summarize_env_numeric <- function(env_df, numeric_vars = NULL) {
  
  # VBA source: V7mdlReportsEnv.txt::EnvReport() - calculates summaries
  
  if (nrow(env_df) == 0) {
    return(data.frame(
      Variable = character(),
      Mean = numeric(),
      Median = numeric(),
      Min = numeric(),
      Max = numeric(),
      SD = numeric(),
      N = integer(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Auto-detect numeric columns if not specified
  if (is.null(numeric_vars)) {
    numeric_vars <- names(env_df)[vapply(env_df, function(col) {
      is.numeric(col) || all(grepl("^[0-9.+-]+$", na.omit(col)))
    }, logical(1))]
  }
  
  # Filter to valid columns
  numeric_vars <- intersect(numeric_vars, names(env_df))
  
  if (length(numeric_vars) == 0) {
    return(data.frame(
      Variable = character(),
      Mean = numeric(),
      Median = numeric(),
      Min = numeric(),
      Max = numeric(),
      SD = numeric(),
      N = integer(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Calculate statistics for each variable
  stats_list <- lapply(numeric_vars, function(var_name) {
    values <- suppressWarnings(as.numeric(env_df[[var_name]]))
    values <- values[!is.na(values)]
    
    if (length(values) == 0) {
      return(data.frame(
        Variable = var_name,
        Mean = NA_real_,
        Median = NA_real_,
        Min = NA_real_,
        Max = NA_real_,
        SD = NA_real_,
        N = 0L,
        stringsAsFactors = FALSE
      ))
    }
    
    data.frame(
      Variable = var_name,
      Mean = round(mean(values, na.rm = TRUE), 2),
      Median = round(median(values, na.rm = TRUE), 2),
      Min = round(min(values, na.rm = TRUE), 2),
      Max = round(max(values, na.rm = TRUE), 2),
      SD = round(sd(values, na.rm = TRUE), 2),
      N = length(values),
      stringsAsFactors = FALSE
    )
  })
  
  do.call(rbind, stats_list)
}

#' Calculate frequency distributions for categorical environmental variables
#'
#' Returns counts and percentages for each category
#'
#' @param env_df Data frame with environmental data
#' @param categorical_vars Character vector of categorical column names
#' @return Data frame with Variable, Category, Count, Percent columns
#' @export
#' @family environmental-reports
#'
#' @examples
#' \dontrun{
#' env <- data.frame(
#'   PlotNumber = c("001", "002", "003", "004"),
#'   MoistureRegime = c("5", "6", "5", "7"),
#'   NutrientRegime = c("C", "C", "D", "C")
#' )
#' summarize_env_categorical(env, c("MoistureRegime", "NutrientRegime"))
#' }
summarize_env_categorical <- function(env_df, categorical_vars) {
  
  if (nrow(env_df) == 0 || length(categorical_vars) == 0) {
    return(data.frame(
      Variable = character(),
      Category = character(),
      Count = integer(),
      Percent = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Filter to valid columns
  categorical_vars <- intersect(categorical_vars, names(env_df))
  
  if (length(categorical_vars) == 0) {
    return(data.frame(
      Variable = character(),
      Category = character(),
      Count = integer(),
      Percent = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Calculate frequencies for each variable
  freq_list <- lapply(categorical_vars, function(var_name) {
    values <- as.character(env_df[[var_name]])
    values <- values[!is.na(values) & nzchar(trimws(values))]
    
    if (length(values) == 0) {
      return(data.frame(
        Variable = var_name,
        Category = character(),
        Count = integer(),
        Percent = numeric(),
        stringsAsFactors = FALSE
      ))
    }
    
    tbl <- table(values)
    total <- sum(tbl)
    
    data.frame(
      Variable = var_name,
      Category = names(tbl),
      Count = as.integer(tbl),
      Percent = round(100 * as.numeric(tbl) / total, 1),
      stringsAsFactors = FALSE
    )
  })
  
  do.call(rbind, freq_list)
}

#' Transpose environmental data (plots as columns)
#'
#' Converts long format (plots as rows) to wide format (plots as columns)
#' matching Access report layout
#'
#' @param env_df Data frame with PlotNumber column and environmental variables
#' @param id_col Name of plot identifier column (default "PlotNumber")
#' @return Transposed data frame with variables as rows, plots as columns
#' @export
#' @family environmental-reports
transpose_env_for_report <- function(env_df, id_col = "PlotNumber") {
  
  # VBA source: V7mdlReportsEnv.txt::EnvReport() - transposes data for Excel
  
  if (nrow(env_df) == 0) return(data.frame())
  
  # Ensure ID column exists
  if (!id_col %in% names(env_df)) {
    stop("ID column '", id_col, "' not found in data")
  }
  
  # Get plot IDs
  plot_ids <- as.character(env_df[[id_col]])
  
  # Get variable columns (everything except ID)
  var_cols <- setdiff(names(env_df), id_col)
  
  if (length(var_cols) == 0) return(data.frame())
  
  # Build transposed table
  transposed <- data.frame(
    Variable = var_cols,
    stringsAsFactors = FALSE
  )
  
  # Add column for each plot
  for (i in seq_along(plot_ids)) {
    plot_id <- plot_ids[i]
    col_name <- paste0("Plot_", plot_id)
    
    transposed[[col_name]] <- vapply(var_cols, function(var) {
      val <- env_df[i, var]
      if (is.na(val)) return("")
      as.character(val)
    }, character(1))
  }
  
  transposed
}

#' Add environmental data section headers
#'
#' Inserts blank rows with section headers for visual grouping
#'
#' @param env_df Transposed environmental data frame
#' @param sections Named list of section headers and their variable prefixes
#' @return Data frame with section headers inserted
#' @export
#' @family environmental-reports
add_env_section_headers <- function(env_df,
                                   sections = list(
                                     "GENERAL LOCATION" = c("Zone", "SubZone", "SiteSeries"),
                                     "SITE" = c("Elevation", "Slope", "Aspect", "Meso", "Surface", "Moisture", "Nutrient"),
                                     "SOIL" = c("Soil", "Bedrock", "Coarse", "Terrain", "Surficial", "Root", "Seepage", "Drainage", "Humus"),
                                     "VEGETATION" = c("Stand", "Successional", "Structural", "Strata"),
                                     "OTHER" = c("Hydro", "Water", "Flooding")
                                   )) {
  
  # VBA source: V7mdlReportsEnv.txt::EnvReport() - adds NULL rows for headers
  
  if (nrow(env_df) == 0) return(env_df)
  
  # Build new table with headers
  result <- data.frame()
  
  for (section_name in names(sections)) {
    # Create header row
    header_row <- env_df[1, , drop = FALSE]
    header_row[1, ] <- ""
    header_row$Variable <- section_name
    
    # Find variables in this section
    prefixes <- sections[[section_name]]
    section_vars <- character()
    
    for (prefix in prefixes) {
      matching <- grep(paste0("^", prefix), env_df$Variable, ignore.case = TRUE, value = TRUE)
      section_vars <- c(section_vars, matching)
    }
    
    # Add header and section variables
    if (length(section_vars) > 0) {
      result <- rbind(result, header_row)
      section_data <- env_df[env_df$Variable %in% section_vars, , drop = FALSE]
      result <- rbind(result, section_data)
    }
  }
  
  result
}

#' Calculate environmental data completeness
#'
#' Returns percentage of fields filled for each plot
#'
#' @param env_df Data frame with environmental data
#' @param required_fields Character vector of field names to check (NULL for all)
#' @return Data frame with PlotNumber, FieldsComplete, FieldsTotal, PercentComplete
#' @export
#' @family environmental-reports
calculate_env_completeness <- function(env_df, required_fields = NULL) {
  
  if (nrow(env_df) == 0) {
    return(data.frame(
      PlotNumber = character(),
      FieldsComplete = integer(),
      FieldsTotal = integer(),
      PercentComplete = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Determine fields to check
  if (is.null(required_fields)) {
    # Exclude PlotNumber and other ID fields
    required_fields <- setdiff(names(env_df), c("PlotNumber", "ProjectID", "FieldNumber"))
  } else {
    required_fields <- intersect(required_fields, names(env_df))
  }
  
  if (length(required_fields) == 0) {
    return(data.frame(
      PlotNumber = character(),
      FieldsComplete = integer(),
      FieldsTotal = integer(),
      PercentComplete = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Calculate completeness for each plot
  completeness <- data.frame(
    PlotNumber = as.character(env_df$PlotNumber),
    FieldsComplete = integer(nrow(env_df)),
    FieldsTotal = length(required_fields),
    PercentComplete = numeric(nrow(env_df)),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_len(nrow(env_df))) {
    complete_count <- sum(vapply(required_fields, function(field) {
      val <- env_df[i, field]
      !is.na(val) && nzchar(trimws(as.character(val)))
    }, logical(1)))
    
    completeness$FieldsComplete[i] <- complete_count
    completeness$PercentComplete[i] <- round(100 * complete_count / length(required_fields), 1)
  }
  
  completeness
}

#' Build environmental summary by site unit
#'
#' Groups plots by site unit and calculates summary statistics
#'
#' @param con DBI connection
#' @param site_unit Site unit to summarize (NULL for all)
#' @param numeric_vars Numeric variables to summarize
#' @param categorical_vars Categorical variables to summarize
#' @return List with numeric_summary and categorical_summary data frames
#' @export
#' @family environmental-reports
build_env_summary_by_su <- function(con,
                                   site_unit = NULL,
                                   numeric_vars = c(
                                     "Elevation", "SlopeGradient", "Aspect",
                                     "StrataCoverTree", "StrataCoverShrub",
                                     "StrataCoverHerb", "StrataCoverMoss"
                                   ),
                                   categorical_vars = c(
                                     "MoistureRegime", "NutrientRegime",
                                     "MesoSlopePosition", "SurfaceShape"
                                   )) {
  
  # Get environmental data
  if (!is.null(site_unit) && nzchar(trimws(site_unit))) {
    plots <- DBI::dbGetQuery(
      con,
      "SELECT PlotNumber FROM Sample_SU WHERE SiteUnit = ?",
      list(trimws(site_unit))
    )
    plot_list <- plots$PlotNumber
  } else {
    plot_list <- NULL
  }
  
  if (!is.null(plot_list) && length(plot_list) > 0) {
    plot_sql <- paste0("('", paste(plot_list, collapse = "', '"), "')")
    env <- DBI::dbGetQuery(
      con,
      sprintf("SELECT * FROM Sample_Env WHERE PlotNumber IN %s", plot_sql)
    )
  } else {
    env <- DBI::dbGetQuery(con, "SELECT * FROM Sample_Env")
  }
  
  if (nrow(env) == 0) {
    return(list(
      numeric_summary = data.frame(),
      categorical_summary = data.frame()
    ))
  }
  
  # Calculate summaries
  numeric_summary <- summarize_env_numeric(env, numeric_vars)
  categorical_summary <- summarize_env_categorical(env, categorical_vars)
  
  list(
    numeric_summary = numeric_summary,
    categorical_summary = categorical_summary,
    plot_count = nrow(env)
  )
}

#' Format environmental variable names for display
#'
#' Converts database column names to human-readable labels
#'
#' @param var_names Character vector of variable names
#' @return Character vector of formatted names
#' @export
#' @family environmental-reports
format_env_var_names <- function(var_names) {
  
  # Access uses specific labels - match them
  # VBA source: V7mdlReportsEnv.txt::EnvReport() - SQL SELECT aliases
  
  label_map <- c(
    "PlotNumber" = "Plot",
    "FieldNumber" = "Site Number",
    "SitePlotQuality" = "Plot Quality",
    "Zone" = "Biogeoclimatic Zone",
    "SubZone" = "SubZone",
    "SiteSeries" = "Site Series",
    "UserSiteUnit" = "Assigned Site Unit",
    "NtsMapSheet" = "NTS Map Sheet",
    "Elevation" = "Elevation (m)",
    "SlopeGradient" = "Slope Gradient (%)",
    "Aspect" = "Aspect (degrees)",
    "MesoSlopePosition" = "Meso Slope Position",
    "SurfaceShape" = "Surface Shape",
    "SurfaceTopographyType" = "Surface Topography Type",
    "MoistureRegime" = "Moisture Regime",
    "NutrientRegime" = "Nutrient Regime",
    "SubstrateDecWood" = "Substrate Decaying Wood (%)",
    "SubstrateBedRock" = "Substrate Bedrock (%)",
    "SubstrateRocks" = "Substrate Rocks (%)",
    "SubstrateMineralSoil" = "Substrate Mineral Soil (%)",
    "SubstrateOrganicMatter" = "Substrate Organic Matter (%)",
    "SubstrateWater" = "Substrate Water (%)",
    "SoilClassGroup" = "Soil Great Group",
    "SoilClassSubGroup" = "Soil Subgroup",
    "BedrockGeology1" = "Bedrock Geology 1",
    "RootZoneParticleSize" = "Root Zone Particle Size",
    "RootingDepth" = "Rooting Depth (cm)",
    "RootRestrictingDepth" = "Root Restricting Depth (cm)",
    "SeepageDepth" = "Seepage Depth (cm)",
    "SoilDrainage" = "Soil Drainage",
    "HumusForm" = "Humus Form (MOF 81)",
    "StandAge" = "Stand Age",
    "SuccessionalStatus" = "Successional Status",
    "StructuralStage" = "Structural Stage",
    "StrataCoverTree" = "Strata Cover Tree (%)",
    "StrataCoverShrub" = "Strata Cover Shrub (%)",
    "StrataCoverHerb" = "Strata Cover Herb (%)",
    "StrataCoverMoss" = "Strata Cover Moss (%)",
    "HydroGeoSystem" = "System",
    "HydroGeoSubSystem" = "Subsystem",
    "WaterSource" = "Water Source",
    "FloodingRegimeFreq" = "Flood Frequency"
  )
  
  vapply(var_names, function(name) {
    if (name %in% names(label_map)) {
      label_map[[name]]
    } else {
      # Default: add spaces before capitals, capitalize first letter
      gsub("([a-z])([A-Z])", "\\1 \\2", name)
    }
  }, character(1), USE.NAMES = FALSE)
}
