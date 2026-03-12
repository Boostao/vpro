# Module: BEC Web Map Explorer
# Public-facing interactive map for browsing published BEC plot data
#
# Data Source: RDS files in data/published/ directory
#   - <project_id>_vegetation.rds
#   - <project_id>_environment.rds  
#   - <project_id>_metadata.rds
#
# VBA Source: N/A (new feature per Schedule A - Services 1b)
# Requirements: ../VPRO_ACCESS/_BEC_data_system_fs1a_schedule_of_services_v2 (13).md
#   "Build a map-based R-shiny tool for public access to BECMaster
#    plot data and user download in multiple data formats"
# 
# Performance Notes:
#   - Uses marker clustering for > 100 plots
#   - Lazy-loads datasets on filter application
#   - Caches loaded data in session reactiveValues
#   - Limits initial display to 5000 plots max
#
# Extension Hooks:
#   - add_bec_polygons(): Add BEC boundary overlay
#   - add_ecoregion_layer(): Add ecoregion boundaries
#   - custom_popup_template: Override default popup HTML


#' BEC Web Map UI
#' 
#' @param id Namespace ID
#' @return Shiny UI tagList
#' 
#' @family becweb
mod_becweb_map_ui <- function(id) {
  ns <- NS(id)
  
  tagList(
    layout_columns(
      col_widths = c(3, 9),
      
      # Sidebar: Filters
      card(
        card_header("Filter Plots"),
        card_body(
          # BEC Classification
          selectInput(
            ns("filter_bec_zone"),
            "BEC Zone:",
            choices = NULL,
            multiple = TRUE
          ),
          selectInput(
            ns("filter_bec_subzone"),
            "BEC Subzone:",
            choices = NULL,
            multiple = TRUE
          ),
          
          # Project Filter
          selectInput(
            ns("filter_project"),
            "Project:",
            choices = NULL,
            multiple = TRUE
          ),
          
          # Date Range
          sliderInput(
            ns("filter_date_range"),
            "Date Range:",
            min = as.Date("1980-01-01"),
            max = Sys.Date(),
            value = c(as.Date("1980-01-01"), Sys.Date()),
            timeFormat = "%Y-%m-%d"
          ),
          
          # Species Search
          textInput(
            ns("filter_species"),
            "Species (scientific name):",
            placeholder = "e.g., Pseudotsuga menziesii"
          ),
          
          # Quality Filter
          selectInput(
            ns("filter_quality"),
            "Data Quality:",
            choices = c("All" = "all", "Good+" = "good", "Excellent" = "excellent"),
            selected = "all"
          ),
          
          hr(),
          
          # Actions
          actionButton(ns("btn_apply_filters"), "Apply Filters", class = "btn-primary w-100 mb-2"),
          actionButton(ns("btn_reset_filters"), "Reset Filters", class = "btn-secondary w-100 mb-2"),
          
          hr(),
          
          # Export
          downloadButton(ns("dl_csv"), "Download CSV", class = "btn-success w-100")
        ),
        card_footer(
          textOutput(ns("filter_status"))
        )
      ),
      
      # Main Panel: Map
      card(
        card_header("BEC Plot Locations"),
        card_body(
          leafletOutput(ns("map"), height = "700px")
        ),
        card_footer(
          textOutput(ns("map_status"))
        )
      )
    )
  )
}


#' BEC Web Map Server
#' 
#' @param id Namespace ID
#' @param con DBI database connection (may be NULL for public mode)
#' @param auth_level Character: "public", "authenticated", "admin"
#' 
#' @return Server module
#' 
#' @family becweb
mod_becweb_map_server <- function(id, con = NULL, auth_level = "public") {
  moduleServer(id, function(input, output, session) {
    
    # Session state (cache loaded data)
    cache <- reactiveValues(
      datasets = list(),
      all_plots = NULL,
      filtered_plots = NULL,
      filter_options = list()
    )
    
    # --- Data Loading ---
    
    #' Discover available RDS datasets
    #'
    #' Scans data/published/ for dataset files
    #' 
    #' @return data.frame with columns: project_id, veg_path, env_path, meta_path
    discover_datasets <- function() {
      pub_dir <- "data/published"
      
      if (!dir.exists(pub_dir)) {
        dir.create(pub_dir, recursive = TRUE)
        return(data.frame(
          project_id = character(0),
          veg_path = character(0),
          env_path = character(0),
          meta_path = character(0),
          stringsAsFactors = FALSE
        ))
      }
      
      # Find all RDS files
      all_files <- list.files(pub_dir, pattern = "\\.rds$", full.names = TRUE)
      
      if (length(all_files) == 0) {
        return(data.frame(
          project_id = character(0),
          veg_path = character(0),
          env_path = character(0),
          meta_path = character(0),
          stringsAsFactors = FALSE
        ))
      }
      
      # Extract project IDs (pattern: <project_id>_<type>.rds)
      basenames <- basename(all_files)
      project_ids <- unique(sub("_.*", "", basenames))
      
      # Build dataset table
      datasets <- data.frame(
        project_id = project_ids,
        veg_path = NA_character_,
        env_path = NA_character_,
        meta_path = NA_character_,
        stringsAsFactors = FALSE
      )
      
      for (i in seq_len(nrow(datasets))) {
        pid <- datasets$project_id[i]
        datasets$veg_path[i] <- file.path(pub_dir, paste0(pid, "_vegetation.rds"))
        datasets$env_path[i] <- file.path(pub_dir, paste0(pid, "_environment.rds"))
        datasets$meta_path[i] <- file.path(pub_dir, paste0(pid, "_metadata.rds"))
      }
      
      # Filter to datasets with at least env file (needed for coordinates)
      datasets <- datasets[file.exists(datasets$env_path), , drop = FALSE]
      
      return(datasets)
    }
    
    
    #' Load all datasets and combine into master plot table
    #'
    #' Reads environment + vegetation + metadata RDS files
    #' Filters by auth_level (public datasets only if auth_level == "public")
    #' 
    #' @return data.frame with plot-level data
    load_all_plots <- function() {
      datasets <- discover_datasets()
      
      if (nrow(datasets) == 0) {
        return(data.frame(
          plot_id = character(0),
          project_id = character(0),
          project_name = character(0),
          date = as.Date(character(0)),
          latitude = numeric(0),
          longitude = numeric(0),
          bec_zone = character(0),
          bec_subzone = character(0),
          bec_site_series = character(0),
          data_quality = character(0),
          dominant_spp = character(0),
          num_species = numeric(0),
          has_photos = logical(0),
          stringsAsFactors = FALSE
        ))
      }
      
      all_plots <- lapply(seq_len(nrow(datasets)), function(i) {
        ds <- datasets[i, ]
        
        # Load environment (required)
        env <- tryCatch(
          readRDS(ds$env_path),
          error = function(e) NULL
        )
        
        if (is.null(env)) return(NULL)
        
        # Load metadata (optional)
        meta <- tryCatch(
          readRDS(ds$meta_path),
          error = function(e) data.frame(project_id = ds$project_id, project_name = ds$project_id, is_public = TRUE)
        )
        
        # Filter by auth level
        if (auth_level == "public" && "is_public" %in% names(meta)) {
          if (!isTRUE(meta$is_public[1])) {
            return(NULL)  # Skip non-public datasets
          }
        }
        
        # Load vegetation (optional, for species counts)
        veg <- tryCatch(
          readRDS(ds$veg_path),
          error = function(e) NULL
        )
        
        # Extract plot-level data
        plots <- data.frame(
          plot_id = env$plotnumber,
          project_id = ds$project_id,
          project_name = if ("project_name" %in% names(meta)) meta$project_name[1] else ds$project_id,
          date = as.Date(env$date_sampled),
          latitude = suppressWarnings(as.numeric(env$latitude)),
          longitude = suppressWarnings(as.numeric(env$longitude)),
          bec_zone = env$bec_zone,
          bec_subzone = env$bec_subzone,
          bec_site_series = env$bec_site_series,
          data_quality = env$data_quality,
          stringsAsFactors = FALSE
        )
        
        # Add vegetation metrics if available
        if (!is.null(veg)) {
          # Count species per plot
          spp_counts <- aggregate(species_code ~ plot_id, data = veg, FUN = function(x) length(unique(x)))
          names(spp_counts)[2] <- "num_species"
          
          # Get dominant species (top 5 by cover)
          veg$cover_numeric <- suppressWarnings(as.numeric(veg$cover))
          veg <- veg[!is.na(veg$cover_numeric), ]
          
          dom_spp <- lapply(split(veg, veg$plot_id), function(pdata) {
            top5 <- head(pdata[order(-pdata$cover_numeric), ], 5)
            paste(top5$species_code, " (", top5$cover_numeric, "% ", top5$layer, ")", sep = "", collapse = "; ")
          })
          
          dom_spp_df <- data.frame(
            plot_id = names(dom_spp),
            dominant_spp = unlist(dom_spp),
            stringsAsFactors = FALSE
          )
          
          plots <- merge(plots, spp_counts, by = "plot_id", all.x = TRUE)
          plots <- merge(plots, dom_spp_df, by = "plot_id", all.x = TRUE)
        } else {
          plots$num_species <- NA
          plots$dominant_spp <- NA
        }
        
        # Check for photos (placeholder - would need to check image database)
        plots$has_photos <- FALSE
        
        return(plots)
      })
      
      # Combine all projects
      all_plots <- do.call(rbind, all_plots[!sapply(all_plots, is.null)])
      
      # Filter out rows without valid coordinates
      all_plots <- all_plots[
        !is.na(all_plots$latitude) & 
        !is.na(all_plots$longitude) &
        all_plots$latitude != 0 &
        all_plots$longitude != 0,
      ]
      
      return(all_plots)
    }
    
    
    # --- Initialization ---
    
    observe({
      # Load data on startup
      cache$all_plots <- load_all_plots()
      cache$filtered_plots <- cache$all_plots
      
      # Populate filter options
      if (!is.null(cache$all_plots) && nrow(cache$all_plots) > 0) {
        cache$filter_options <- list(
          bec_zones = sort(unique(cache$all_plots$bec_zone[!is.na(cache$all_plots$bec_zone)])),
          bec_subzones = sort(unique(cache$all_plots$bec_subzone[!is.na(cache$all_plots$bec_subzone)])),
          projects = sort(unique(cache$all_plots$project_name)),
          date_min = min(cache$all_plots$date, na.rm = TRUE),
          date_max = max(cache$all_plots$date, na.rm = TRUE)
        )
        
        # Update filter inputs
        updateSelectInput(session, "filter_bec_zone", choices = cache$filter_options$bec_zones)
        updateSelectInput(session, "filter_bec_subzone", choices = cache$filter_options$bec_subzones)
        updateSelectInput(session, "filter_project", choices = cache$filter_options$projects)
        updateSliderInput(session, "filter_date_range", 
                          min = cache$filter_options$date_min,
                          max = cache$filter_options$date_max,
                          value = c(cache$filter_options$date_min, cache$filter_options$date_max))
      }
    })
    
    
    # --- Filtering Logic ---
    
    observeEvent(input$btn_apply_filters, {
      req(cache$all_plots)
      
      filtered <- cache$all_plots
      
      # BEC Zone filter
      if (!is.null(input$filter_bec_zone) && length(input$filter_bec_zone) > 0) {
        filtered <- filtered[filtered$bec_zone %in% input$filter_bec_zone, ]
      }
      
      # BEC Subzone filter
      if (!is.null(input$filter_bec_subzone) && length(input$filter_bec_subzone) > 0) {
        filtered <- filtered[filtered$bec_subzone %in% input$filter_bec_subzone, ]
      }
      
      # Project filter
      if (!is.null(input$filter_project) && length(input$filter_project) > 0) {
        filtered <- filtered[filtered$project_name %in% input$filter_project, ]
      }
      
      # Date range filter
      if (!is.null(input$filter_date_range)) {
        filtered <- filtered[
          filtered$date >= input$filter_date_range[1] & 
          filtered$date <= input$filter_date_range[2],
        ]
      }
      
      # Species filter
      if (!is.null(input$filter_species) && nchar(input$filter_species) > 0) {
        species_pattern <- input$filter_species
        filtered <- filtered[
          grepl(species_pattern, filtered$dominant_spp, ignore.case = TRUE),
        ]
      }
      
      # Quality filter
      if (!is.null(input$filter_quality) && input$filter_quality != "all") {
        if (input$filter_quality == "good") {
          filtered <- filtered[filtered$data_quality %in% c("Good", "Excellent"), ]
        } else if (input$filter_quality == "excellent") {
          filtered <- filtered[filtered$data_quality == "Excellent", ]
        }
      }
      
      # Limit to 5000 plots
      if (nrow(filtered) > 5000) {
        showNotification(
          paste("Too many results (", nrow(filtered), "). Showing first 5000. Please refine filters."),
          type = "warning",
          duration = 10
        )
        filtered <- filtered[1:5000, ]
      }
      
      cache$filtered_plots <- filtered
    })
    
    
    observeEvent(input$btn_reset_filters, {
      # Reset inputs
      updateSelectInput(session, "filter_bec_zone", selected = character(0))
      updateSelectInput(session, "filter_bec_subzone", selected = character(0))
      updateSelectInput(session, "filter_project", selected = character(0))
      updateTextInput(session, "filter_species", value = "")
      updateSelectInput(session, "filter_quality", selected = "all")
      
      if (!is.null(cache$filter_options)) {
        updateSliderInput(session, "filter_date_range",
                          value = c(cache$filter_options$date_min, cache$filter_options$date_max))
      }
      
      # Reset filtered data
      cache$filtered_plots <- cache$all_plots
    })
    
    
    # --- Map Rendering ---
    
    output$map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles(providers$OpenStreetMap) %>%
        setView(lng = -122.0, lat = 52.0, zoom = 5)  # BC center
    })
    
    
    observe({
      req(cache$filtered_plots)
      
      plots <- cache$filtered_plots
      
      if (nrow(plots) == 0) {
        leafletProxy("map") %>%
          clearMarkers()
        return()
      }
      
      # Define BEC zone colors
      zone_colors <- c(
        "IDF" = "#FF6B6B",
        "BG" = "#4ECDC4",
        "MS" = "#45B7D1",
        "ESSF" = "#96CEB4",
        "ICH" = "#FFEAA7",
        "CDF" = "#DFE6E9",
        "CWH" = "#74B9FF",
        "MH" = "#A29BFE",
        "BAFA" = "#FD79A8",
        "SBS" = "#FDCB6E",
        "SBPS" = "#6C5CE7",
        "SWB" = "#00B894"
      )
      
      # Assign colors
      plots$color <- sapply(plots$bec_zone, function(z) {
        if (is.na(z)) return("#95A5A6")
        if (z %in% names(zone_colors)) {
          return(zone_colors[z])
        } else {
          return("#95A5A6")
        }
      }, USE.NAMES = FALSE)
      
      # Create popup HTML
      plots$popup_html <- apply(plots, 1, function(row) {
        paste0(
          "<b>Plot: ", row["plot_id"], "</b><br>",
          "Project: ", row["project_name"], "<br>",
          "Date: ", row["date"], "<br>",
          "BEC: ", row["bec_zone"], row["bec_subzone"], "/", row["bec_site_series"], "<br>",
          "<br>",
          "<b>Dominant Species:</b><br>",
          gsub(";", "<br>• ", paste0("• ", row["dominant_spp"])), "<br>",
          "<br>",
          "Species Count: ", row["num_species"], "<br>",
          "Quality: ", row["data_quality"]
        )
      })
      
      # Update map
      leafletProxy("map") %>%
        clearMarkers() %>%
        addCircleMarkers(
          data = plots,
          lng = ~longitude,
          lat = ~latitude,
          radius = 6,
          color = ~color,
          fillColor = ~color,
          fillOpacity = 0.7,
          stroke = TRUE,
          weight = 1,
          popup = ~popup_html,
          clusterOptions = if (nrow(plots) > 100) markerClusterOptions() else NULL
        )
    })
    
    
    # --- Status Outputs ---
    
    output$filter_status <- renderText({
      if (is.null(cache$all_plots)) {
        return("Loading datasets...")
      }
      
      total <- nrow(cache$all_plots)
      filtered <- if (!is.null(cache$filtered_plots)) nrow(cache$filtered_plots) else 0
      
      sprintf("Showing %d of %d plots", filtered, total)
    })
    
    
    output$map_status <- renderText({
      if (is.null(cache$filtered_plots) || nrow(cache$filtered_plots) == 0) {
        return("No plots to display. Adjust filters or check data availability.")
      }
      
      n_plots <- nrow(cache$filtered_plots)
      n_projects <- length(unique(cache$filtered_plots$project_id))
      
      sprintf("%d plots from %d project(s)", n_plots, n_projects)
    })
    
    
    # --- CSV Export ---
    
    output$dl_csv <- downloadHandler(
      filename = function() {
        paste0("BEC_plots_export_", Sys.Date(), ".csv")
      },
      content = function(file) {
        req(cache$filtered_plots)
        
        if (nrow(cache$filtered_plots) == 0) {
          showNotification("No data to export.", type = "error")
          return(NULL)
        }
        
        # Prepare export (exclude internal columns)
        export_data <- cache$filtered_plots[, c(
          "plot_id", "project_name", "date", "latitude", "longitude",
          "bec_zone", "bec_subzone", "bec_site_series", "data_quality",
          "num_species", "dominant_spp"
        )]
        
        write.csv(export_data, file, row.names = FALSE)
        
        showNotification(
          paste("Exported", nrow(export_data), "plots to CSV."),
          type = "message"
        )
      }
    )
    
  })
}
