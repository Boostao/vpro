# Data Validation Functions for Reports
#
# Ported from VPro64 Access VBA modules:
# - V7mdlReportsValidateEnvData.txt (environmental data validation)
# - V7mdlReportsValidateVegCodes.txt (vegetation code validation)
#
# Provides functions for:
# - Validating codes against USysTableOfLists
# - Identifying invalid/orphan codes
# - Generating validation reports

#' Validate environmental data codes
#'
#' Checks environmental field codes against USysTableOfLists
#'
#' @param con DBI connection with access to VLists.USysTableOfLists
#' @param env_df Data frame with environmental data to validate
#' @param project_id Project ID for identification (optional)
#' @return Data frame with PlotNumber, FieldName, InvalidValue, ExpectedList columns
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
#' DBI::dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
#' env <- DBI::dbGetQuery(con, "SELECT * FROM Env LIMIT 10")
#' errors <- validate_env_data(con, env)
#' DBI::dbDisconnect(con)
#' }
validate_env_data <- function(con, env_df, project_id = NULL) {
  
  # VBA source: V7mdlReportsValidateEnvData.txt::ValidateEnvData()
  
  if (nrow(env_df) == 0) {
    return(data.frame(
      PlotNumber = character(),
      FieldName = character(),
      InvalidValue = character(),
      ExpectedList = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Get list of fields that should be validated
  validation_fields_sql <- "
    SELECT DISTINCT
      ListName,
      FieldUsedIn,
      ValidateLoops
    FROM VLists.USysTableOfLists
    WHERE Validate = 'Yes'
  "
  
  validation_fields <- tryCatch(
    DBI::dbGetQuery(con, validation_fields_sql),
    error = function(e) {
      # If Validate column doesn't exist, use all lists
      DBI::dbGetQuery(con, "
        SELECT DISTINCT
          ListName,
          FieldUsedIn,
          0 as ValidateLoops
        FROM VLists.USysTableOfLists
        WHERE FieldUsedIn IS NOT NULL AND FieldUsedIn != ''
      ")
    }
  )
  
  if (nrow(validation_fields) == 0) {
    return(data.frame(
      PlotNumber = character(),
      FieldName = character(),
      InvalidValue = character(),
      ExpectedList = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Collect all validation errors
  all_errors <- data.frame(
    PlotNumber = character(),
    FieldName = character(),
    InvalidValue = character(),
    ExpectedList = character(),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_len(nrow(validation_fields))) {
    list_name <- validation_fields$ListName[i]
    field_base <- validation_fields$FieldUsedIn[i]
    validate_loops <- suppressWarnings(as.integer(validation_fields$ValidateLoops[i]))
    
    if (is.na(validate_loops)) validate_loops <- 0L
    
    # Determine fields to check
    if (validate_loops > 0) {
      # Check numbered fields (e.g., Exposure1, Exposure2, Exposure3)
      fields_to_check <- paste0(field_base, seq_len(validate_loops))
    } else {
      # Check single field
      fields_to_check <- field_base
    }
    
    # Get valid items for this list
    valid_items <- DBI::dbGetQuery(
      con,
      "SELECT Item FROM VLists.USysTableOfLists WHERE ListName = ?",
      list(list_name)
    )
    
    if (nrow(valid_items) == 0) next
    
    valid_codes <- unique(as.character(valid_items$Item))
    
    # Check each field
    for (field_name in fields_to_check) {
      if (!field_name %in% names(env_df)) next
      
      # Find invalid values
      field_values <- as.character(env_df[[field_name]])
      field_values[is.na(field_values)] <- ""
      
      # Only check non-empty values
      non_empty_idx <- nzchar(trimws(field_values))
      
      if (!any(non_empty_idx)) next
      
      # Check which values are invalid
      invalid_idx <- non_empty_idx & !(field_values %in% valid_codes)
      
      if (any(invalid_idx)) {
        errors <- data.frame(
          PlotNumber = as.character(env_df$PlotNumber[invalid_idx]),
          FieldName = field_name,
          InvalidValue = field_values[invalid_idx],
          ExpectedList = list_name,
          stringsAsFactors = FALSE
        )
        all_errors <- rbind(all_errors, errors)
      }
    }
  }
  
  # Remove duplicates
  all_errors <- unique(all_errors)
  
  # Sort by plot number and field name
  if (nrow(all_errors) > 0) {
    all_errors <- all_errors[order(all_errors$PlotNumber, all_errors$FieldName), , drop = FALSE]
  }
  
  all_errors
}

#' Validate vegetation species codes
#'
#' Checks vegetation species codes against USysAllSpecs or SppList
#'
#' @param con DBI connection
#' @param veg_df Data frame with vegetation data (must have Species column)
#' @return Data frame with PlotNumber, Layer, InvalidSpecies columns
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
#' DBI::dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
#' veg <- DBI::dbGetQuery(con, "SELECT * FROM vw_USysAllVeg LIMIT 100")
#' errors <- validate_veg_codes(con, veg)
#' DBI::dbDisconnect(con)
#' }
validate_veg_codes <- function(con, veg_df) {
  
  # VBA source: V7mdlReportsValidateVegCodes.txt (similar pattern to env validation)
  
  if (nrow(veg_df) == 0) {
    return(data.frame(
      PlotNumber = character(),
      Layer = character(),
      InvalidSpecies = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Normalize column names
  cols <- names(veg_df)
  pick_col <- function(candidates) {
    idx <- which(tolower(cols) %in% tolower(candidates))
    if (length(idx) > 0) cols[[idx[1]]] else NA_character_
  }
  
  plot_col <- pick_col(c("plotnumber", "PlotNumber"))
  layer_col <- pick_col(c("mylayer", "layer", "MyLayer"))
  species_col <- pick_col(c("species", "species_code", "Species"))
  
  if (is.na(plot_col) || is.na(species_col)) {
    warning("Required columns (PlotNumber, Species) not found in vegetation data")
    return(data.frame(
      PlotNumber = character(),
      Layer = character(),
      InvalidSpecies = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Get valid species codes
  valid_species <- character()
  
  # Try USysAllSpecs first (preferred) - check with SQL query for schema-qualified table
  table_exists <- tryCatch({
    DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM information_schema.tables 
                          WHERE table_schema = 'lists' AND table_name = 'USysAllSpecs'")$n > 0
  }, error = function(e) FALSE)
  
  if (table_exists) {
    specs <- DBI::dbGetQuery(con, "SELECT Code FROM VLists.USysAllSpecs")
    valid_species <- unique(as.character(specs$Code))
  } else if (DBI::dbExistsTable(con, "USysAllSpecs")) {
    specs <- DBI::dbGetQuery(con, "SELECT Code FROM USysAllSpecs")
    valid_species <- unique(as.character(specs$Code))
  } else {
    # Try SppList
    table_exists_spp <- tryCatch({
      DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM information_schema.tables 
                            WHERE table_schema = 'lists' AND table_name = 'SppList'")$n > 0
    }, error = function(e) FALSE)
    
    if (table_exists_spp) {
      specs <- DBI::dbGetQuery(con, "SELECT Code FROM VLists.SppList")
      valid_species <- unique(as.character(specs$Code))
    } else if (DBI::dbExistsTable(con, "SppList")) {
      specs <- DBI::dbGetQuery(con, "SELECT Code FROM SppList")
      valid_species <- unique(as.character(specs$Code))
    }
  }
  
  if (length(valid_species) == 0) {
    warning("No species reference list found (USysAllSpecs or SppList)")
    return(data.frame(
      PlotNumber = character(),
      Layer = character(),
      InvalidSpecies = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Check for invalid species codes
  plot_numbers <- as.character(veg_df[[plot_col]])
  species_codes <- as.character(veg_df[[species_col]])
  layer_values <- if (!is.na(layer_col)) as.character(veg_df[[layer_col]]) else rep("", nrow(veg_df))
  
  # Filter to non-empty codes
  non_empty <- !is.na(species_codes) & nzchar(trimws(species_codes))
  invalid <- non_empty & !(species_codes %in% valid_species)
  
  if (!any(invalid)) {
    return(data.frame(
      PlotNumber = character(),
      Layer = character(),
      InvalidSpecies = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  errors <- data.frame(
    PlotNumber = plot_numbers[invalid],
    Layer = layer_values[invalid],
    InvalidSpecies = species_codes[invalid],
    stringsAsFactors = FALSE
  )
  
  # Remove duplicates and sort
  errors <- unique(errors)
  errors <- errors[order(errors$PlotNumber, errors$Layer, errors$InvalidSpecies), , drop = FALSE]
  
  errors
}

#' Check for orphaned vegetation records
#'
#' Finds vegetation records where plot doesn't exist in Env
#'
#' @param con DBI connection
#' @return Data frame with orphaned PlotNumber, Layer, Species
#' @export
#' @family validation
check_orphaned_veg_records <- function(con) {
  
  if (!DBI::dbExistsTable(con, "vw_USysAllVeg") || !DBI::dbExistsTable(con, "Env")) {
    return(data.frame(
      PlotNumber = character(),
      Layer = character(),
      Species = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  sql <- "
    SELECT DISTINCT
      v.PlotNumber,
      v.MyLayer as Layer,
      v.Species
    FROM vw_USysAllVeg v
    LEFT JOIN Env e ON v.PlotNumber = e.PlotNumber
    WHERE e.PlotNumber IS NULL
    ORDER BY v.PlotNumber, v.MyLayer, v.Species
  "
  
  DBI::dbGetQuery(con, sql)
}

#' Check for orphaned environmental records
#'
#' Finds environmental records where plot doesn't exist in SU
#'
#' @param con DBI connection
#' @return Data frame with orphaned PlotNumber, ProjectID
#' @export
#' @family validation
check_orphaned_env_records <- function(con) {
  
  if (!DBI::dbExistsTable(con, "Env") || !DBI::dbExistsTable(con, "SU")) {
    return(data.frame(
      PlotNumber = character(),
      ProjectID = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  sql <- "
    SELECT DISTINCT
      e.PlotNumber,
      e.ProjectID
    FROM Env e
    LEFT JOIN SU su ON e.PlotNumber = su.PlotNumber
    WHERE su.PlotNumber IS NULL
    ORDER BY e.PlotNumber
  "
  
  DBI::dbGetQuery(con, sql)
}

#' Generate comprehensive validation report
#'
#' Runs all validation checks and returns combined report
#'
#' @param con DBI connection
#' @param project_id Project ID to validate (NULL for all)
#' @param site_unit Site unit to validate (NULL for all)
#' @return List with env_errors, veg_errors, orphaned_veg, orphaned_env data frames
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
#' DBI::dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
#' report <- generate_validation_report(con, project_id = "TEST")
#' DBI::dbDisconnect(con)
#' }
generate_validation_report <- function(con, project_id = NULL, site_unit = NULL) {
  
  # Get plot list to validate
  plot_list <- NULL
  
  if (!is.null(site_unit) && nzchar(trimws(site_unit))) {
    plots <- DBI::dbGetQuery(
      con,
      "SELECT PlotNumber FROM SU WHERE SiteUnit = ?",
      list(trimws(site_unit))
    )
    plot_list <- plots$PlotNumber
  } else if (!is.null(project_id) && nzchar(trimws(project_id))) {
    plots <- DBI::dbGetQuery(
      con,
      "SELECT PlotNumber FROM Env WHERE ProjectID = ?",
      list(trimws(project_id))
    )
    plot_list <- plots$PlotNumber
  }
  
  # Get environmental data
  if (!is.null(plot_list) && length(plot_list) > 0) {
    plot_sql <- paste0("('", paste(plot_list, collapse = "', '"), "')")
    env <- DBI::dbGetQuery(
      con,
      sprintf("SELECT * FROM Env WHERE PlotNumber IN %s", plot_sql)
    )
    veg <- DBI::dbGetQuery(
      con,
      sprintf("SELECT * FROM vw_USysAllVeg WHERE PlotNumber IN %s", plot_sql)
    )
  } else {
    env <- DBI::dbGetQuery(con, "SELECT * FROM Env")
    veg <- DBI::dbGetQuery(con, "SELECT * FROM vw_USysAllVeg")
  }
  
  # Run validation checks
  env_errors <- validate_env_data(con, env, project_id)
  veg_errors <- validate_veg_codes(con, veg)
  orphaned_veg <- check_orphaned_veg_records(con)
  orphaned_env <- check_orphaned_env_records(con)
  
  # Filter orphaned records to plot list if specified
  if (!is.null(plot_list) && length(plot_list) > 0) {
    orphaned_veg <- orphaned_veg[orphaned_veg$PlotNumber %in% plot_list, , drop = FALSE]
    orphaned_env <- orphaned_env[orphaned_env$PlotNumber %in% plot_list, , drop = FALSE]
  }
  
  list(
    env_errors = env_errors,
    veg_errors = veg_errors,
    orphaned_veg = orphaned_veg,
    orphaned_env = orphaned_env,
    summary = data.frame(
      ErrorType = c("Invalid Env Codes", "Invalid Veg Codes", "Orphaned Veg Records", "Orphaned Env Records"),
      Count = c(nrow(env_errors), nrow(veg_errors), nrow(orphaned_veg), nrow(orphaned_env)),
      stringsAsFactors = FALSE
    )
  )
}

#' Check for duplicate plot numbers
#'
#' Finds plots that appear multiple times in Env
#'
#' @param con DBI connection
#' @return Data frame with PlotNumber, DuplicateCount
#' @export
#' @family validation
check_duplicate_plots <- function(con) {
  
  if (!DBI::dbExistsTable(con, "Env")) {
    return(data.frame(
      PlotNumber = character(),
      DuplicateCount = integer(),
      stringsAsFactors = FALSE
    ))
  }
  
  sql <- "
    SELECT
      PlotNumber,
      COUNT(*) as DuplicateCount
    FROM Env
    GROUP BY PlotNumber
    HAVING COUNT(*) > 1
    ORDER BY DuplicateCount DESC, PlotNumber
  "
  
  DBI::dbGetQuery(con, sql)
}

#' Validate plot number format
#'
#' Checks if plot numbers follow expected format (5 digits)
#'
#' @param plot_numbers Character vector of plot numbers
#' @return Data frame with InvalidPlotNumber, Issue columns
#' @export
#' @family validation
validate_plot_number_format <- function(plot_numbers) {
  
  if (length(plot_numbers) == 0) {
    return(data.frame(
      InvalidPlotNumber = character(),
      Issue = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  issues <- data.frame(
    InvalidPlotNumber = character(),
    Issue = character(),
    stringsAsFactors = FALSE
  )
  
  for (plot in plot_numbers) {
    plot_str <- as.character(plot)
    
    # Check for empty
    if (is.na(plot) || !nzchar(trimws(plot_str))) {
      issues <- rbind(issues, data.frame(
        InvalidPlotNumber = plot_str,
        Issue = "Empty plot number",
        stringsAsFactors = FALSE
      ))
      next
    }
    
    # Check for non-numeric
    if (!grepl("^[0-9]+$", trimws(plot_str))) {
      issues <- rbind(issues, data.frame(
        InvalidPlotNumber = plot_str,
        Issue = "Non-numeric plot number",
        stringsAsFactors = FALSE
      ))
      next
    }
    
    # Check length (expected 5 digits, but flexible)
    if (nchar(trimws(plot_str)) != 5) {
      issues <- rbind(issues, data.frame(
        InvalidPlotNumber = plot_str,
        Issue = sprintf("Unusual length (%d digits, expected 5)", nchar(trimws(plot_str))),
        stringsAsFactors = FALSE
      ))
    }
  }
  
  unique(issues)
}
