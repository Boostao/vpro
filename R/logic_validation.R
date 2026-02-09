#' Validation Functions for VPro Data Submission
#'
#' This module provides validation functions for vegetation, environment, and site unit
#' data before submission to PostgreSQL staging tables. Validates against business rules
#' and reference data in lists tables.


# Utility validation functions ----

#' Validate plot_number field
#'
#' @param plot_number Character plot identifier
#' @return Character error message or NULL if valid
#' @noRd
validate_plot_number <- function(plot_number) {
  if (is.null(plot_number) || is.na(plot_number) || nchar(trimws(plot_number)) == 0) {
    return("plot_number must be non-empty text")
  }
  NULL
}

#' Validate project_id field
#'
#' @param project_id Numeric project identifier
#' @return Character error message or NULL if valid
#' @noRd
validate_project_id <- function(project_id) {
  if (is.null(project_id) || is.na(project_id) || !is.numeric(project_id) || project_id <= 0) {
    return("project_id must be a positive integer")
  }
  NULL
}


# Main validation functions ----

#' Validate vegetation sample row
#'
#' Checks cover_percent, height_cm, species_code, layer_code, plot_number, and project_id
#' against business rules and reference data.
#'
#' @param row A single-row data.frame or named list with vegetation data
#' @param con Database connection (PostgreSQL or DuckDB) for reference data lookup
#' @param reference_source Character: "postgres" or "duckdb" - determines table names for lookups
#'
#' @return List with elements:
#'   - valid: Logical indicating if row passes all validations
#'   - errors: Character vector of validation error messages (empty if valid)
#'
#' @examples
#' \dontrun{
#' pg_con <- DBI::dbConnect(RPostgres::Postgres(), ...)
#' result <- validate_veg_row(data.frame(
#'   plot_number = "PLOT001",
#'   species_code = "TSUGHET",
#'   layer_code = "T1",
#'   cover_percent = 25,
#'   height_cm = 1500,
#'   project_id = 1
#' ), pg_con, "postgres")
#' }
#'
#' @export
validate_veg_row <- function(row, con, reference_source = "postgres") {
  errors <- character()
  
  # Convert single row to list for easier access
  if (is.data.frame(row)) {
    if (nrow(row) != 1) {
      stop("validate_veg_row expects a single row, got ", nrow(row), " rows")
    }
    row <- as.list(row[1, ])
  }
  
  # Validate plot_number
  plot_err <- validate_plot_number(row$plot_number)
  if (!is.null(plot_err)) errors <- c(errors, plot_err)
  
  # Validate project_id
  proj_err <- validate_project_id(row$project_id)
  if (!is.null(proj_err)) errors <- c(errors, proj_err)
  
  # Validate cover_percent
  if (!is.null(row$cover_percent) && !is.na(row$cover_percent)) {
    if (!is.numeric(row$cover_percent) || row$cover_percent < 0 || row$cover_percent > 100) {
      errors <- c(errors, "cover_percent must be between 0 and 100")
    }
  }
  
  # Validate height_cm
  if (!is.null(row$height_cm) && !is.na(row$height_cm)) {
    if (!is.numeric(row$height_cm) || row$height_cm < 0) {
      errors <- c(errors, "height_cm must be >= 0")
    }
  }
  
  # Validate species_code against reference data
  if (!is.null(row$species_code) && !is.na(row$species_code)) {
    spp_table <- if (reference_source == "postgres") "lists.spplist" else "SppList"
    spp_col <- "spp_code"
    
    tryCatch({
      spp_exists <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) as cnt FROM %s WHERE %s = '%s'",
        spp_table, spp_col, row$species_code
      ))$cnt > 0
      
      if (!spp_exists) {
        errors <- c(errors, sprintf("species_code '%s' not found in reference data", row$species_code))
      }
    }, error = function(e) {
      errors <<- c(errors, sprintf("Error validating species_code: %s", e$message))
    })
  } else {
    errors <- c(errors, "species_code is required")
  }
  
  # Validate layer_code against reference data
  if (!is.null(row$layer_code) && !is.na(row$layer_code)) {
    layer_table <- if (reference_source == "postgres") "lists.layercode" else "LayerCode"
    layer_col <- "layer_code"
    
    tryCatch({
      layer_exists <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) as cnt FROM %s WHERE %s = '%s'",
        layer_table, layer_col, row$layer_code
      ))$cnt > 0
      
      if (!layer_exists) {
        errors <- c(errors, sprintf("layer_code '%s' not found in reference data", row$layer_code))
      }
    }, error = function(e) {
      errors <<- c(errors, sprintf("Error validating layer_code: %s", e$message))
    })
  } else {
    errors <- c(errors, "layer_code is required")
  }
  
  list(
    valid = length(errors) == 0,
    errors = errors
  )
}


#' Validate environment sample row
#'
#' Checks latitude, longitude, elevation_m, survey_date, plot_number, and project_id
#' against business rules and geographic constraints for BC.
#'
#' @param row A single-row data.frame or named list with environment data
#' @param con Database connection (not currently used for env validation, reserved for future)
#'
#' @return List with elements:
#'   - valid: Logical indicating if row passes all validations
#'   - errors: Character vector of validation error messages (empty if valid)
#'
#' @examples
#' \dontrun{
#' result <- validate_env_row(data.frame(
#'   plot_number = "PLOT001",
#'   project_id = 1,
#'   latitude = 49.5,
#'   longitude = -123.5,
#'   elevation_m = 500
#' ), con)
#' }
#'
#' @export
validate_env_row <- function(row, con = NULL) {
  errors <- character()
  
  # Convert single row to list for easier access
  if (is.data.frame(row)) {
    if (nrow(row) != 1) {
      stop("validate_env_row expects a single row, got ", nrow(row), " rows")
    }
    row <- as.list(row[1, ])
  }
  
  # Validate plot_number
  plot_err <- validate_plot_number(row$plot_number)
  if (!is.null(plot_err)) errors <- c(errors, plot_err)
  
  # Validate project_id
  proj_err <- validate_project_id(row$project_id)
  if (!is.null(proj_err)) errors <- c(errors, proj_err)
  
  # Validate latitude (BC range: ~48-60°N)
  if (!is.null(row$latitude) && !is.na(row$latitude)) {
    if (!is.numeric(row$latitude) || row$latitude < 48 || row$latitude > 60) {
      errors <- c(errors, "latitude must be between 48 and 60 (British Columbia range)")
    }
  }
  
  # Validate longitude (BC range: ~-140 to -114°W)
  if (!is.null(row$longitude) && !is.na(row$longitude)) {
    if (!is.numeric(row$longitude) || row$longitude < -140 || row$longitude > -114) {
      errors <- c(errors, "longitude must be between -140 and -114 (British Columbia range)")
    }
  }
  
  # Validate elevation_m (BC range: 0-4000m)
  if (!is.null(row$elevation_m) && !is.na(row$elevation_m)) {
    if (!is.numeric(row$elevation_m) || row$elevation_m < 0 || row$elevation_m > 4000) {
      errors <- c(errors, "elevation_m must be between 0 and 4000")
    }
  }
  
  # Validate survey_date (optional, but must be valid date if provided)
  if (!is.null(row$survey_date) && !is.na(row$survey_date)) {
    tryCatch({
      as.Date(row$survey_date)
    }, error = function(e) {
      errors <<- c(errors, "survey_date must be a valid date")
    })
  }
  
  list(
    valid = length(errors) == 0,
    errors = errors
  )
}


#' Validate site unit sample row
#'
#' Checks bec_zone and bec_subzone against reference data if provided.
#'
#' @param row A single-row data.frame or named list with site unit data
#' @param con Database connection (PostgreSQL or DuckDB) for reference data lookup
#' @param reference_source Character: "postgres" or "duckdb" - determines table names for lookups
#'
#' @return List with elements:
#'   - valid: Logical indicating if row passes all validations
#'   - errors: Character vector of validation error messages (empty if valid)
#'
#' @examples
#' \dontrun{
#' pg_con <- DBI::dbConnect(RPostgres::Postgres(), ...)
#' result <- validate_su_row(data.frame(
#'   plot_number = "PLOT001",
#'   project_id = 1,
#'   bec_zone = "CWH",
#'   bec_subzone = "dm"
#' ), pg_con, "postgres")
#' }
#'
#' @export
validate_su_row <- function(row, con, reference_source = "postgres") {
  errors <- character()
  
  # Convert single row to list for easier access
  if (is.data.frame(row)) {
    if (nrow(row) != 1) {
      stop("validate_su_row expects a single row, got ", nrow(row), " rows")
    }
    row <- as.list(row[1, ])
  }
  
  # Validate plot_number
  plot_err <- validate_plot_number(row$plot_number)
  if (!is.null(plot_err)) errors <- c(errors, plot_err)
  
  # Validate project_id
  proj_err <- validate_project_id(row$project_id)
  if (!is.null(proj_err)) errors <- c(errors, proj_err)
  
  # Validate bec_zone if provided
  if (!is.null(row$bec_zone) && !is.na(row$bec_zone) && nchar(trimws(row$bec_zone)) > 0) {
    zone_table <- if (reference_source == "postgres") "lists.usyszonelist" else "USysZoneList"
    zone_col <- "zone_code"
    
    tryCatch({
      zone_exists <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) as cnt FROM %s WHERE %s = '%s'",
        zone_table, zone_col, row$bec_zone
      ))$cnt > 0
      
      if (!zone_exists) {
        errors <- c(errors, sprintf("bec_zone '%s' not found in reference data", row$bec_zone))
      }
    }, error = function(e) {
      errors <<- c(errors, sprintf("Error validating bec_zone: %s", e$message))
    })
  }
  
  # Validate bec_subzone combo if both zone and subzone provided
  if (!is.null(row$bec_zone) && !is.na(row$bec_zone) && 
      !is.null(row$bec_subzone) && !is.na(row$bec_subzone) &&
      nchar(trimws(row$bec_zone)) > 0 && nchar(trimws(row$bec_subzone)) > 0) {
    
    subzone_table <- if (reference_source == "postgres") "lists.usyssubzonelist" else "USysSubZoneList"
    
    tryCatch({
      subzone_exists <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) as cnt FROM %s WHERE zone_code = '%s' AND subzone_code = '%s'",
        subzone_table, row$bec_zone, row$bec_subzone
      ))$cnt > 0
      
      if (!subzone_exists) {
        errors <- c(errors, sprintf(
          "bec_subzone '%s' not found for bec_zone '%s' in reference data",
          row$bec_subzone, row$bec_zone
        ))
      }
    }, error = function(e) {
      errors <<- c(errors, sprintf("Error validating bec_subzone: %s", e$message))
    })
  }
  
  list(
    valid = length(errors) == 0,
    errors = errors
  )
}


#' Validate complete submission
#'
#' Validates a named list of data.frames (veg, env, su) and returns aggregated results.
#' Processes all rows and collects validation errors across all tables.
#'
#' @param data_list Named list with elements: veg, env, su (data.frames)
#' @param con Database connection for reference data lookup
#' @param reference_source Character: "postgres" or "duckdb" - determines table names for lookups
#'
#' @return List with elements:
#'   - valid: Logical indicating if ALL rows in ALL tables pass validation
#'   - errors: Named list of data.frames with validation errors per table
#'   - summary: Data.frame with counts of valid/invalid rows per table
#'
#' @examples
#' \dontrun{
#' data <- list(
#'   veg = data.frame(plot_number = "PLOT001", species_code = "TSUGHET", ...),
#'   env = data.frame(plot_number = "PLOT001", latitude = 49.5, ...),
#'   su = data.frame(plot_number = "PLOT001", bec_zone = "CWH", ...)
#' )
#' result <- validate_submission(data, pg_con, "postgres")
#' }
#'
#' @export
validate_submission <- function(data_list, con, reference_source = "postgres") {
  
  results <- list(
    valid = TRUE,
    errors = list(),
    summary = data.frame(
      table = character(),
      total_rows = integer(),
      valid_rows = integer(),
      invalid_rows = integer(),
      stringsAsFactors = FALSE
    )
  )
  
  # Validate veg table if provided
  if (!is.null(data_list$veg) && nrow(data_list$veg) > 0) {
    veg_errors <- list()
    for (i in seq_len(nrow(data_list$veg))) {
      val_result <- validate_veg_row(data_list$veg[i, ], con, reference_source)
      if (!val_result$valid) {
        results$valid <- FALSE
        veg_errors <- c(veg_errors, list(data.frame(
          row_number = i,
          plot_number = data_list$veg$plot_number[i],
          errors = paste(val_result$errors, collapse = "; "),
          stringsAsFactors = FALSE
        )))
      }
    }
    
    if (length(veg_errors) > 0) {
      results$errors$veg <- do.call(rbind, veg_errors)
    }
    
    results$summary <- rbind(results$summary, data.frame(
      table = "veg",
      total_rows = nrow(data_list$veg),
      valid_rows = nrow(data_list$veg) - length(veg_errors),
      invalid_rows = length(veg_errors),
      stringsAsFactors = FALSE
    ))
  }
  
  # Validate env table if provided
  if (!is.null(data_list$env) && nrow(data_list$env) > 0) {
    env_errors <- list()
    for (i in seq_len(nrow(data_list$env))) {
      val_result <- validate_env_row(data_list$env[i, ], con)
      if (!val_result$valid) {
        results$valid <- FALSE
        env_errors <- c(env_errors, list(data.frame(
          row_number = i,
          plot_number = data_list$env$plot_number[i],
          errors = paste(val_result$errors, collapse = "; "),
          stringsAsFactors = FALSE
        )))
      }
    }
    
    if (length(env_errors) > 0) {
      results$errors$env <- do.call(rbind, env_errors)
    }
    
    results$summary <- rbind(results$summary, data.frame(
      table = "env",
      total_rows = nrow(data_list$env),
      valid_rows = nrow(data_list$env) - length(env_errors),
      invalid_rows = length(env_errors),
      stringsAsFactors = FALSE
    ))
  }
  
  # Validate su table if provided
  if (!is.null(data_list$su) && nrow(data_list$su) > 0) {
    su_errors <- list()
    for (i in seq_len(nrow(data_list$su))) {
      val_result <- validate_su_row(data_list$su[i, ], con, reference_source)
      if (!val_result$valid) {
        results$valid <- FALSE
        su_errors <- c(su_errors, list(data.frame(
          row_number = i,
          plot_number = data_list$su$plot_number[i],
          errors = paste(val_result$errors, collapse = "; "),
          stringsAsFactors = FALSE
        )))
      }
    }
    
    if (length(su_errors) > 0) {
      results$errors$su <- do.call(rbind, su_errors)
    }
    
    results$summary <- rbind(results$summary, data.frame(
      table = "su",
      total_rows = nrow(data_list$su),
      valid_rows = nrow(data_list$su) - length(su_errors),
      invalid_rows = length(su_errors),
      stringsAsFactors = FALSE
    ))
  }
  
  results
}
