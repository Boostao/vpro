# Quality Control Filtering for Reports
#
# Ported from VPro64 Access VBA module: V7mdlReportsQualityControl.txt
#
# Filters plots based on data quality thresholds:
# - Site plot quality (Poor/Fair/Good/Excellent)
# - Vegetation plot quality
# - Soil plot quality
# - BEC Use classification
#
# NULL handling: Can include or exclude plots with NULL quality values

#' Map quality text to numeric order
#'
#' @param quality_text Character quality level (Poor/Fair/Good/Excellent)
#' @return Integer ItemOrder from USysTableOfLists (1-4)
#' @family quality-control
#'
#' @examples
#' quality_to_order("Good")  # Returns 3
#' quality_to_order("Poor")  # Returns 1
quality_to_order <- function(quality_text) {
  # VBA source: V7mdlReportsQualityControl.txt::LevelAsNumber()
  if (is.na(quality_text) || !nzchar(trimws(quality_text))) return(NA_integer_)
  quality <- trimws(quality_text)
  
  order_map <- c(
    "Poor" = 1L,
    "Fair" = 2L,
    "Good" = 3L,
    "Excellent" = 4L
  )
  
  result <- order_map[quality]
  if (is.na(result)) return(NA_integer_)
  as.integer(result)
}

#' Build quality control filter for plots
#'
#' Creates WHERE clause SQL fragment for filtering plots by quality thresholds
#'
#' @param con DBI connection with access to USysTableOfLists
#' @param site_quality_min Minimum site quality (e.g., "Good")
#' @param veg_quality_min Minimum vegetation quality
#' @param soil_quality_min Minimum soil quality
#' @param site_allow_null Include plots with NULL site quality?
#' @param veg_allow_null Include plots with NULL veg quality?
#' @param soil_allow_null Include plots with NULL soil quality?
#' @param bec_use_min Minimum BEC_Use value (optional)
#' @param bec_allow_null Include plots with NULL BEC_Use?
#' @return List with WHERE clause and parameters
#' @family quality-control
build_quality_filter <- function(con,
                                 site_quality_min = "Good",
                                 veg_quality_min = "Good",
                                 soil_quality_min = "Good",
                                 site_allow_null = TRUE,
                                 veg_allow_null = TRUE,
                                 soil_allow_null = TRUE,
                                 bec_use_min = NULL,
                                 bec_allow_null = TRUE) {
  
  # VBA source: V7mdlReportsQualityControl.txt::QC()
  
  # Get quality order values from lists
  get_quality_order <- function(quality_text) {
    if (is.na(quality_text) || !nzchar(trimws(quality_text))) return(NA_integer_)
    
    sql <- "SELECT ItemOrder FROM lists.USysTableOfLists 
            WHERE ListName = 'dataquality' AND Item = ?"
    result <- DBI::dbGetQuery(con, sql, list(quality_text))
    if (nrow(result) == 0) return(NA_integer_)
    as.integer(result$ItemOrder[1])
  }
  
  site_order <- get_quality_order(site_quality_min)
  veg_order <- get_quality_order(veg_quality_min)
  soil_order <- get_quality_order(soil_quality_min)
  
  # Build NULL handling SQL
  site_null_sql <- if (site_allow_null) " OR" else " AND NOT"
  veg_null_sql <- if (veg_allow_null) " OR" else " AND NOT"
  soil_null_sql <- if (soil_allow_null) " OR" else " AND NOT"
  
  # Build BEC Use filter
  bec_filter <- ""
  if (!is.null(bec_use_min) && nzchar(trimws(bec_use_min))) {
    if (bec_allow_null) {
      bec_filter <- sprintf(" AND (env.BEC_Use >= '%s' OR env.BEC_Use IS NULL)", bec_use_min)
    } else {
      bec_filter <- sprintf(" AND (env.BEC_Use >= '%s' AND env.BEC_Use IS NOT NULL)", bec_use_min)
    }
  }
  
  list(
    site_order = site_order,
    veg_order = veg_order,
    soil_order = soil_order,
    site_null_sql = site_null_sql,
    veg_null_sql = veg_null_sql,
    soil_null_sql = soil_null_sql,
    bec_filter = bec_filter
  )
}

#' Filter plots by quality control criteria
#'
#' Returns a data frame of plots that meet quality thresholds
#'
#' @param con DBI connection to vpro database
#' @param plot_list Character vector of plots to filter, or NULL for all plots in site_unit/project
#' @param site_unit Site unit to filter (if plot_list is NULL)
#' @param project_id Project ID to filter (if plot_list and site_unit are NULL)
#' @param site_quality_min Minimum site quality threshold
#' @param veg_quality_min Minimum vegetation quality threshold
#' @param soil_quality_min Minimum soil quality threshold
#' @param site_allow_null Include plots with NULL site quality?
#' @param veg_allow_null Include plots with NULL veg quality?
#' @param soil_allow_null Include plots with NULL soil quality?
#' @param bec_use_min Minimum BEC_Use value (optional)
#' @param bec_allow_null Include plots with NULL BEC_Use?
#' @param enforce_filter Apply quality filtering? If FALSE, returns all plots unchanged
#' @return Data frame with PlotNumber, SiteUnit columns for plots meeting criteria
#' @export
#' @family quality-control
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
#' DBI::dbExecute(con, "ATTACH 'data/vpro_lists.duckdb' AS lists")
#' 
#' # Filter plots with Good or better quality
#' plots <- filter_plots_by_quality(
#'   con,
#'   project_id = "TEST",
#'   site_quality_min = "Good",
#'   veg_quality_min = "Good",
#'   soil_quality_min = "Fair"
#' )
#' 
#' DBI::dbDisconnect(con)
#' }
filter_plots_by_quality <- function(con,
                                   plot_list = NULL,
                                   site_unit = NULL,
                                   project_id = NULL,
                                   site_quality_min = "Good",
                                   veg_quality_min = "Good",
                                   soil_quality_min = "Good",
                                   site_allow_null = TRUE,
                                   veg_allow_null = TRUE,
                                   soil_allow_null = TRUE,
                                   bec_use_min = NULL,
                                   bec_allow_null = TRUE,
                                   enforce_filter = TRUE) {
  
  # VBA source: V7mdlReportsQualityControl.txt::QC()
  
  # If not enforcing, return all plots
  if (!isTRUE(enforce_filter)) {
    if (!is.null(plot_list) && length(plot_list) > 0) {
      return(data.frame(PlotNumber = plot_list, stringsAsFactors = FALSE))
    }
    if (!is.null(site_unit) && nzchar(trimws(site_unit))) {
      plots <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber, SiteUnit FROM SU WHERE SiteUnit = ?",
        list(trimws(site_unit))
      )
      return(plots)
    }
    if (!is.null(project_id) && nzchar(trimws(project_id))) {
      plots <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber FROM Env WHERE ProjectID = ?",
        list(trimws(project_id))
      )
      return(data.frame(PlotNumber = plots$PlotNumber, stringsAsFactors = FALSE))
    }
    return(data.frame(PlotNumber = character(), stringsAsFactors = FALSE))
  }
  
  # Build quality filter
  qc <- build_quality_filter(
    con,
    site_quality_min = site_quality_min,
    veg_quality_min = veg_quality_min,
    soil_quality_min = soil_quality_min,
    site_allow_null = site_allow_null,
    veg_allow_null = veg_allow_null,
    soil_allow_null = soil_allow_null,
    bec_use_min = bec_use_min,
    bec_allow_null = bec_allow_null
  )
  
  # Determine base plot list
  base_from <- "SU su"
  where_clause <- "1=1"
  
  if (!is.null(plot_list) && length(plot_list) > 0) {
    plot_sql <- paste0("('", paste(plot_list, collapse = "', '"), "')")
    where_clause <- sprintf("su.PlotNumber IN %s", plot_sql)
  } else if (!is.null(site_unit) && nzchar(trimws(site_unit))) {
    where_clause <- sprintf("su.SiteUnit = '%s'", trimws(site_unit))
  } else if (!is.null(project_id) && nzchar(trimws(project_id))) {
    # Filter by project via env table
    where_clause <- sprintf("env.ProjectID = '%s'", trimws(project_id))
  }
  
  # Build full query with quality joins
  # Joins to USysTableOfLists for each quality dimension
  sql <- sprintf("
    SELECT DISTINCT su.PlotNumber, su.SiteUnit
    FROM %s
    INNER JOIN Env env ON su.PlotNumber = env.PlotNumber
    LEFT JOIN lists.USysTableOfLists site_q 
      ON env.SitePlotQuality = site_q.Item AND site_q.ListName = 'dataquality'
    LEFT JOIN lists.USysTableOfLists veg_q 
      ON env.VegPlotQuality = veg_q.Item AND veg_q.ListName = 'dataquality'
    LEFT JOIN lists.USysTableOfLists soil_q 
      ON env.SoilPlotQuality = soil_q.Item AND soil_q.ListName = 'dataquality'
    WHERE (%s)
      AND ((site_q.ItemOrder >= %d)%s (site_q.ItemOrder IS NULL))
      AND ((veg_q.ItemOrder >= %d)%s (veg_q.ItemOrder IS NULL))
      AND ((soil_q.ItemOrder >= %d)%s (soil_q.ItemOrder IS NULL))
      %s
  ",
    base_from,
    where_clause,
    qc$site_order, qc$site_null_sql,
    qc$veg_order, qc$veg_null_sql,
    qc$soil_order, qc$soil_null_sql,
    qc$bec_filter
  )
  
  result <- DBI::dbGetQuery(con, sql)
  
  if (nrow(result) == 0) {
    warning("No plots meet quality control criteria. Consider adjusting thresholds or allowing NULL values.")
  }
  
  result
}

#' Identify which quality criteria removed each plot
#'
#' Returns a data frame showing why plots were filtered out
#'
#' @param con DBI connection to vpro database
#' @param original_plots Character vector of original plot numbers before filtering
#' @param filtered_plots Character vector of plots that passed QC
#' @param site_quality_min Minimum site quality threshold used
#' @param veg_quality_min Minimum vegetation quality threshold used
#' @param soil_quality_min Minimum soil quality threshold used
#' @param bec_use_min Minimum BEC_Use value used
#' @return Data frame with PlotNumber, RemovedBy, Site, Veg, Soil, BEC columns
#' @export
#' @family quality-control
identify_removed_plots <- function(con,
                                  original_plots,
                                  filtered_plots,
                                  site_quality_min = "Good",
                                  veg_quality_min = "Good",
                                  soil_quality_min = "Good",
                                  bec_use_min = NULL) {
  
  # VBA source: V7mdlReportsQualityControl.txt::FillRemovedBy()
  
  # Find plots that were removed
  removed_plots <- setdiff(original_plots, filtered_plots)
  if (length(removed_plots) == 0) {
    return(data.frame(
      PlotNumber = character(),
      RemovedBy = character(),
      Site = character(),
      Veg = character(),
      Soil = character(),
      BEC = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Get quality values for removed plots
  plot_sql <- paste0("('", paste(removed_plots, collapse = "', '"), "')")
  sql <- sprintf("
    SELECT DISTINCT
      env.PlotNumber,
      env.SitePlotQuality AS Site,
      env.VegPlotQuality AS Veg,
      env.SoilPlotQuality AS Soil,
      env.BEC_Use AS BEC
    FROM Env env
    WHERE env.PlotNumber IN %s
  ", plot_sql)
  
  removed_df <- DBI::dbGetQuery(con, sql)
  
  # Convert quality text to numeric
  site_threshold <- quality_to_order(site_quality_min)
  veg_threshold <- quality_to_order(veg_quality_min)
  soil_threshold <- quality_to_order(soil_quality_min)
  
  # Determine removal reason for each plot
  removed_df$RemovedBy <- vapply(seq_len(nrow(removed_df)), function(i) {
    reasons <- character()
    
    site_order <- quality_to_order(removed_df$Site[i])
    if (!is.na(site_order) && !is.na(site_threshold) && site_order < site_threshold) {
      reasons <- c(reasons, "Site")
    }
    
    veg_order <- quality_to_order(removed_df$Veg[i])
    if (!is.na(veg_order) && !is.na(veg_threshold) && veg_order < veg_threshold) {
      reasons <- c(reasons, "Veg")
    }
    
    soil_order <- quality_to_order(removed_df$Soil[i])
    if (!is.na(soil_order) && !is.na(soil_threshold) && soil_order < soil_threshold) {
      reasons <- c(reasons, "Soil")
    }
    
    if (!is.null(bec_use_min) && nzchar(trimws(bec_use_min))) {
      bec_val <- removed_df$BEC[i]
      if (!is.na(bec_val) && bec_val < bec_use_min) {
        reasons <- c(reasons, "BEC")
      }
    }
    
    if (length(reasons) == 0) return("Unknown")
    if (length(reasons) > 1) return("Mixed")
    reasons[1]
  }, character(1))
  
  removed_df[, c("PlotNumber", "RemovedBy", "Site", "Veg", "Soil", "BEC")]
}

#' Get quality control summary statistics
#'
#' Returns counts of plots by quality level
#'
#' @param con DBI connection to vpro database
#' @param plot_list Character vector of plots, or NULL for all
#' @return Data frame with quality level counts
#' @export
#' @family quality-control
get_quality_summary <- function(con, plot_list = NULL) {
  where_clause <- "1=1"
  if (!is.null(plot_list) && length(plot_list) > 0) {
    plot_sql <- paste0("('", paste(plot_list, collapse = "', '"), "')")
    where_clause <- sprintf("PlotNumber IN %s", plot_sql)
  }
  
  sql <- sprintf("
    SELECT
      SitePlotQuality,
      VegPlotQuality,
      SoilPlotQuality,
      COUNT(*) as Count
    FROM Env
    WHERE %s
    GROUP BY SitePlotQuality, VegPlotQuality, SoilPlotQuality
    ORDER BY Count DESC
  ", where_clause)
  
  DBI::dbGetQuery(con, sql)
}
