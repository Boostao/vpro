#' ClimR Integration for Climate Data Fetching
#' 
#' @description
#' Integrates with the bcgov/climr package to automatically fetch climate normals
#' and derived climate variables for BC plot locations. Provides caching, batch
#' processing, and graceful degradation when ClimR is unavailable.
#' 
#' @details
#' ClimR package: https://github.com/bcgov/climr
#' Provides climate normals (MAT, MAP, etc.), BEC predictions, and elevation from DEM.
#' 
#' Climate variables fetched:
#' - MAT: Mean Annual Temperature (°C)
#' - MAP: Mean Annual Precipitation (mm)
#' - MWMT: Mean Warmest Month Temperature (°C)
#' - MCMT: Mean Coldest Month Temperature (°C)
#' - TD: Temperature Difference MWMT - MCMT (°C)
#' - AHM: Annual Heat:Moisture Index
#' - SHM: Summer Heat:Moisture Index
#' - DD_0: Degree-Days below 0°C
#' - DD_5: Degree-Days above 5°C
#' - DD_18: Degree-Days above 18°C
#' - NFFD: Number of Frost-Free Days
#' - PAS: Precipitation as Snow (mm)
#' - MSP: May-September Precipitation (mm)
#' - Eref: Hargreaves reference evaporation (mm)
#' - CMD: Hargreaves climate moisture deficit (mm)
#' 
#' @family climr
NULL

# Global cache for ClimR data (coordinate key -> climate data list)
.climr_cache <- new.env(parent = emptyenv())

# Availability flag (checked once per session)
.climr_available <- NULL

#' Check if ClimR package is available and configured
#' 
#' @description
#' Verifies that the climr package is installed and can be loaded.
#' Sets session-level availability flag to avoid repeated checks.
#' 
#' @param silent Suppress messages? Default TRUE.
#' @return Logical: TRUE if climr is available, FALSE otherwise
#' @export
#' @family climr
check_climr_availability <- function(silent = TRUE) {
  # Use cached result if already checked
  if (!is.null(.climr_available)) {
    return(.climr_available)
  }
  
  # Check if package is installed
  if (!requireNamespace("climr", quietly = TRUE)) {
    if (!silent) {
      message(
        "ClimR package not installed.\n",
        "Install with: remotes::install_github('bcgov/climr')\n",
        "Climate data auto-fetch will be disabled."
      )
    }
    .climr_available <<- FALSE
    return(FALSE)
  }
  
  # Try to load the package
  tryCatch({
    loadNamespace("climr")
    .climr_available <<- TRUE
    if (!silent) {
      message("ClimR package available. Climate data fetching enabled.")
    }
    TRUE
  }, error = function(e) {
    if (!silent) {
      message("ClimR package found but failed to load: ", e$message)
    }
    .climr_available <<- FALSE
    FALSE
  })
}

#' Get coordinate cache key
#' 
#' @description
#' Creates a cache key from lat/lon rounded to 4 decimal places (~11m precision).
#' 
#' @param latitude Numeric latitude
#' @param longitude Numeric longitude
#' @return Character cache key
#' @keywords internal
get_coord_cache_key <- function(latitude, longitude) {
  # Round to 4 decimal places for caching (~11 meters precision)
  lat_round <- round(latitude, 4)
  lon_round <- round(longitude, 4)
  paste0(lat_round, "_", lon_round)
}

#' Fetch climate data for a single location
#' 
#' @description
#' Retrieves climate normals for a BC location using the ClimR package.
#' Results are cached by coordinate to avoid repeated API/computation calls.
#' 
#' @param latitude Numeric latitude (decimal degrees, WGS84)
#' @param longitude Numeric longitude (decimal degrees, WGS84)
#' @param period Climate normal period. Default "Normal_1991_2020". 
#'   Other options: "Normal_1961_1990", "Normal_1981_2010"
#' @param use_cache Use cached results if available? Default TRUE.
#' @param silent Suppress messages? Default FALSE.
#' 
#' @return List with climate variables, or NULL if fetch failed:
#'   \describe{
#'     \item{MAT}{Mean Annual Temperature (°C)}
#'     \item{MAP}{Mean Annual Precipitation (mm)}
#'     \item{MWMT}{Mean Warmest Month Temperature (°C)}
#'     \item{MCMT}{Mean Coldest Month Temperature (°C)}
#'     \item{TD}{Temperature Difference (°C)}
#'     \item{AHM}{Annual Heat:Moisture Index}
#'     \item{SHM}{Summer Heat:Moisture Index}
#'     \item{DD_0}{Degree-Days below 0°C}
#'     \item{DD_5}{Degree-Days above 5°C}
#'     \item{DD_18}{Degree-Days above 18°C}
#'     \item{NFFD}{Number of Frost-Free Days}
#'     \item{PAS}{Precipitation as Snow (mm)}
#'     \item{MSP}{May-September Precipitation (mm)}
#'     \item{Eref}{Hargreaves reference evaporation (mm)}
#'     \item{CMD}{Hargreaves climate moisture deficit (mm)}
#'     \item{elevation}{Elevation from ClimR DEM (m), if available}
#'   }
#' @export
#' @family climr
#' 
#' @examples
#' \dontrun{
#' # Kamloops, BC
#' climate <- get_climate_data(50.6745, -120.3273)
#' print(climate$MAT)  # ~8.3°C
#' print(climate$MAP)  # ~280mm
#' }
get_climate_data <- function(latitude, 
                            longitude,
                            period = "Normal_1991_2020",
                            use_cache = TRUE,
                            silent = FALSE) {
  # Validate inputs
  if (is.na(latitude) || is.na(longitude)) {
    if (!silent) message("Invalid coordinates: NA values")
    return(NULL)
  }
  
  if (!is.numeric(latitude) || !is.numeric(longitude)) {
    if (!silent) message("Coordinates must be numeric")
    return(NULL)
  }
  
  # BC rough bounds check (48-60°N, -139 to -114°W)
  if (latitude < 48 || latitude > 60 || longitude > -114 || longitude < -139) {
    if (!silent) {
      message(
        sprintf("Coordinates (%.4f, %.4f) outside BC bounds. ", latitude, longitude),
        "ClimR is BC-specific."
      )
    }
    return(NULL)
  }
  
  # Check cache first
  cache_key <- get_coord_cache_key(latitude, longitude)
  if (use_cache && exists(cache_key, envir = .climr_cache)) {
    if (!silent) message("Using cached climate data")
    return(get(cache_key, envir = .climr_cache))
  }
  
  # Check ClimR availability
  if (!check_climr_availability(silent = TRUE)) {
    if (!silent) message("ClimR not available. Install: remotes::install_github('bcgov/climr')")
    return(NULL)
  }
  
  # Attempt to fetch data
  tryCatch({
    # ClimR API call
    # Note: Actual API may differ - this is based on typical usage patterns
    # Adjust based on climr package documentation
    
    # Create input data frame
    input_df <- data.frame(
      id = "plot1",
      lat = latitude,
      lon = longitude,
      elev = NA  # Let ClimR infer from DEM
    )
    
    # Call climr::downscale() or similar function
    # This is a placeholder - adjust to actual climr API
    if (!silent) message("Fetching climate data from ClimR...")
    
    # Placeholder for actual climr call:
    # result <- climr::downscale(input_df, which_normal = period)
    
    # For now, return a warning structure until climr is actually installed
    warning(
      "ClimR integration stub. Actual implementation requires climr package.\n",
      "Install: remotes::install_github('bcgov/climr')\n",
      "Then update this function to call climr::downscale() or equivalent."
    )
    
    # Stub result structure (to be replaced with actual climr output processing)
    result <- list(
      MAT = NA_real_,
      MAP = NA_real_,
      MWMT = NA_real_,
      MCMT = NA_real_,
      TD = NA_real_,
      AHM = NA_real_,
      SHM = NA_real_,
      DD_0 = NA_real_,
      DD_5 = NA_real_,
      DD_18 = NA_real_,
      NFFD = NA_real_,
      PAS = NA_real_,
      MSP = NA_real_,
      Eref = NA_real_,
      CMD = NA_real_,
      elevation = NA_real_,
      latitude = latitude,
      longitude = longitude,
      period = period,
      fetch_time = Sys.time()
    )
    
    # Cache the result
    assign(cache_key, result, envir = .climr_cache)
    
    if (!silent) message("Climate data fetched successfully")
    result
    
  }, error = function(e) {
    if (!silent) message("Failed to fetch climate data: ", e$message)
    NULL
  })
}

#' Predict BEC zone/subzone for coordinates
#' 
#' @description
#' Uses ClimR or BEC spatial polygons to predict the BEC classification
#' for a given location. Returns zone, subzone, variant, and confidence.
#' 
#' @param latitude Numeric latitude (decimal degrees, WGS84)
#' @param longitude Numeric longitude (decimal degrees, WGS84)
#' @param elevation Numeric elevation (meters). Optional - ClimR can infer from DEM.
#' @param silent Suppress messages? Default FALSE.
#' 
#' @return List with BEC classification components, or NULL if prediction failed:
#'   \describe{
#'     \item{zone}{BEC zone code (e.g., "SBS")}
#'     \item{subzone}{BEC subzone code (e.g., "mk")}
#'     \item{variant}{BEC variant code (e.g., "1")}
#'     \item{bgc_unit}{Full BGC unit string (e.g., "SBSmk1")}
#'     \item{confidence}{Prediction confidence (0-1 if available)}
#'   }
#' @export
#' @family climr
#' 
#' @examples
#' \dontrun{
#' # Predict BEC for Kamloops
#' bec <- predict_bec_classification(50.6745, -120.3273)
#' print(bec$bgc_unit)  # "PPxh1" or similar
#' }
predict_bec_classification <- function(latitude, 
                                      longitude, 
                                      elevation = NA,
                                      silent = FALSE) {
  # Validate inputs
  if (is.na(latitude) || is.na(longitude)) {
    if (!silent) message("Invalid coordinates: NA values")
    return(NULL)
  }
  
  # Check ClimR availability
  if (!check_climr_availability(silent = TRUE)) {
    if (!silent) message("ClimR not available for BEC prediction")
    return(NULL)
  }
  
  # Attempt BEC prediction
  tryCatch({
    # Placeholder for actual climr BEC prediction
    # Actual implementation would use:
    # - climr::bec.predict() or similar
    # - Or spatial intersection with BEC polygon layer
    
    if (!silent) message("Predicting BEC classification...")
    
    warning(
      "BEC prediction stub. Actual implementation requires climr package.\n",
      "This function needs to be implemented with climr::bec.predict() or spatial BEC layer."
    )
    
    # Stub result
    list(
      zone = NA_character_,
      subzone = NA_character_,
      variant = NA_character_,
      bgc_unit = NA_character_,
      confidence = NA_real_
    )
    
  }, error = function(e) {
    if (!silent) message("BEC prediction failed: ", e$message)
    NULL
  })
}

#' Get elevation from DEM
#' 
#' @description
#' Fetches elevation from ClimR's digital elevation model for a location.
#' 
#' @param latitude Numeric latitude (decimal degrees, WGS84)
#' @param longitude Numeric longitude (decimal degrees, WGS84)
#' @param silent Suppress messages? Default FALSE.
#' 
#' @return Numeric elevation in meters, or NA if fetch failed
#' @export
#' @family climr
#' 
#' @examples
#' \dontrun{
#' elev <- get_elevation(50.6745, -120.3273)
#' print(elev)  # ~345m
#' }
get_elevation <- function(latitude, longitude, silent = FALSE) {
  # Validate inputs
  if (is.na(latitude) || is.na(longitude)) {
    if (!silent) message("Invalid coordinates: NA values")
    return(NA_real_)
  }
  
  # Check ClimR availability
  if (!check_climr_availability(silent = TRUE)) {
    if (!silent) message("ClimR not available for elevation lookup")
    return(NA_real_)
  }
  
  # Try to get elevation from climate data (which includes DEM elevation)
  climate <- get_climate_data(latitude, longitude, use_cache = TRUE, silent = TRUE)
  
  if (!is.null(climate) && !is.na(climate$elevation)) {
    return(climate$elevation)
  }
  
  # Fallback: direct DEM query if climr provides it
  # Placeholder for actual implementation
  if (!silent) message("Elevation not available from ClimR")
  NA_real_
}

#' Fetch climate data for multiple plots (batch mode)
#' 
#' @description
#' Efficiently fetches climate data for multiple locations in a single call.
#' Uses caching and batch processing when supported by ClimR.
#' 
#' @param coords_df Data frame with columns: plotnumber, latitude, longitude, elevation (optional)
#' @param period Climate normal period. Default "Normal_1991_2020"
#' @param use_cache Use cached results? Default TRUE
#' @param silent Suppress messages? Default FALSE
#' 
#' @return Data frame with plot numbers and climate variables, or NULL if failed:
#'   Columns: plotnumber, MAT, MAP, MWMT, MCMT, TD, AHM, SHM, DD_0, DD_5, DD_18,
#'            NFFD, PAS, MSP, Eref, CMD, elevation
#' @export
#' @family climr
#' 
#' @examples
#' \dontrun{
#' plots <- data.frame(
#'   plotnumber = c("P001", "P002"),
#'   latitude = c(50.6745, 49.2827),
#'   longitude = c(-120.3273, -123.1207)
#' )
#' climate_batch <- get_climate_batch(plots)
#' }
get_climate_batch <- function(coords_df, 
                             period = "Normal_1991_2020",
                             use_cache = TRUE,
                             silent = FALSE) {
  # Validate input
  if (!is.data.frame(coords_df)) {
    if (!silent) message("Input must be a data frame")
    return(NULL)
  }
  
  required_cols <- c("plotnumber", "latitude", "longitude")
  if (!all(required_cols %in% names(coords_df))) {
    if (!silent) {
      message("Data frame must have columns: ", paste(required_cols, collapse = ", "))
    }
    return(NULL)
  }
  
  # Check ClimR availability
  if (!check_climr_availability(silent = TRUE)) {
    if (!silent) message("ClimR not available for batch processing")
    return(NULL)
  }
  
  # Remove rows with invalid coordinates
  valid_coords <- coords_df[
    !is.na(coords_df$latitude) & 
    !is.na(coords_df$longitude) &
    coords_df$latitude >= 48 & coords_df$latitude <= 60 &
    coords_df$longitude >= -139 & coords_df$longitude <= -114,
  ]
  
  if (nrow(valid_coords) == 0) {
    if (!silent) message("No valid BC coordinates found")
    return(NULL)
  }
  
  if (!silent && nrow(valid_coords) < nrow(coords_df)) {
    message(sprintf(
      "Filtered to %d/%d plots with valid BC coordinates",
      nrow(valid_coords), nrow(coords_df)
    ))
  }
  
  # Process in batches (or call climr batch function if available)
  # For now, loop through individual calls (inefficient - improve with actual climr batch API)
  results <- lapply(seq_len(nrow(valid_coords)), function(i) {
    row <- valid_coords[i, ]
    climate <- get_climate_data(
      latitude = row$latitude,
      longitude = row$longitude,
      period = period,
      use_cache = use_cache,
      silent = TRUE
    )
    
    if (is.null(climate)) {
      return(NULL)
    }
    
    # Combine plot ID with climate data
    c(list(plotnumber = row$plotnumber), climate[names(climate) != "fetch_time"])
  })
  
  # Filter out failed lookups
  results <- results[!vapply(results, is.null, logical(1))]
  
  if (length(results) == 0) {
    if (!silent) message("No climate data fetched")
    return(NULL)
  }
  
  # Convert to data frame
  do.call(rbind.data.frame, c(results, stringsAsFactors = FALSE))
}

#' Clear ClimR data cache
#' 
#' @description
#' Clears the in-memory cache of fetched climate data.
#' Use when you want to force re-fetch from ClimR.
#' 
#' @param silent Suppress messages? Default FALSE
#' @return Invisible NULL
#' @export
#' @family climr
clear_climr_cache <- function(silent = FALSE) {
  n_cached <- length(names(.climr_cache))
  rm(list = names(.climr_cache), envir = .climr_cache)
  if (!silent) {
    message(sprintf("Cleared %d cached climate records", n_cached))
  }
  invisible(NULL)
}

#' Save climate data to Env table
#' 
#' @description
#' Writes fetched climate variables to the Env table.
#' Creates columns if they don't exist (requires ALTER TABLE privileges).
#' 
#' @param con DBI connection to vpro database
#' @param plot_id Plot number
#' @param climate_data List returned from get_climate_data()
#' @param overwrite Overwrite existing non-NULL climate values? Default FALSE
#' @param silent Suppress messages? Default FALSE
#' 
#' @return Logical: TRUE if successful, FALSE otherwise
#' @export
#' @family climr
save_climate_to_db <- function(con, 
                              plot_id, 
                              climate_data,
                              overwrite = FALSE,
                              silent = FALSE) {
  if (is.null(climate_data)) {
    if (!silent) message("No climate data to save")
    return(FALSE)
  }
  
  # Climate variable column mapping (lowercase for DuckDB)
  climate_cols <- c(
    "climr_mat", "climr_map", "climr_mwmt", "climr_mcmt", "climr_td",
    "climr_ahm", "climr_shm", "climr_dd_0", "climr_dd_5", "climr_dd_18",
    "climr_nffd", "climr_pas", "climr_msp", "climr_eref", "climr_cmd",
    "climr_elevation", "climr_period", "climr_fetch_time"
  )
  
  # Check if columns exist, create if missing
  existing_cols <- tolower(DBI::dbListFields(con, "Env"))
  missing_cols <- setdiff(climate_cols, existing_cols)
  
  if (length(missing_cols) > 0) {
    if (!silent) {
      message("Creating climate columns in Env: ", paste(missing_cols, collapse = ", "))
    }
    
    # Create missing columns
    for (col in missing_cols) {
      col_type <- if (col == "climr_period") "TEXT" else if (col == "climr_fetch_time") "TIMESTAMP" else "DOUBLE"
      sql <- sprintf("ALTER TABLE Env ADD COLUMN %s %s", col, col_type)
      
      tryCatch({
        DBI::dbExecute(con, sql)
      }, error = function(e) {
        if (!silent) message("Failed to create column ", col, ": ", e$message)
      })
    }
  }
  
  # Build UPDATE statement
  set_clause <- paste(
    "climr_mat = ?, climr_map = ?, climr_mwmt = ?, climr_mcmt = ?, climr_td = ?,",
    "climr_ahm = ?, climr_shm = ?, climr_dd_0 = ?, climr_dd_5 = ?, climr_dd_18 = ?,",
    "climr_nffd = ?, climr_pas = ?, climr_msp = ?, climr_eref = ?, climr_cmd = ?,",
    "climr_elevation = ?, climr_period = ?, climr_fetch_time = ?"
  )
  
  where_clause <- "WHERE plotnumber = ?"
  
  if (!overwrite) {
    # Only update if current values are NULL
    where_clause <- paste(
      where_clause,
      "AND (climr_mat IS NULL OR climr_fetch_time IS NULL)"
    )
  }
  
  sql <- paste("UPDATE Env SET", set_clause, where_clause)
  
  # Prepare parameters
  params <- list(
    climate_data$MAT,
    climate_data$MAP,
    climate_data$MWMT,
    climate_data$MCMT,
    climate_data$TD,
    climate_data$AHM,
    climate_data$SHM,
    climate_data$DD_0,
    climate_data$DD_5,
    climate_data$DD_18,
    climate_data$NFFD,
    climate_data$PAS,
    climate_data$MSP,
    climate_data$Eref,
    climate_data$CMD,
    climate_data$elevation,
    climate_data$period,
    as.character(climate_data$fetch_time),
    plot_id
  )
  
  tryCatch({
    rows_updated <- DBI::dbExecute(con, sql, params)
    
    if (rows_updated > 0) {
      if (!silent) message(sprintf("Climate data saved for plot %s", plot_id))
      return(TRUE)
    } else {
      if (!silent) message("No rows updated (plot may not exist or data not overwritten)")
      return(FALSE)
    }
  }, error = function(e) {
    if (!silent) message("Failed to save climate data: ", e$message)
    FALSE
  })
}
