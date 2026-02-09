
build_venus_xml_doc <- function(con, project_ids = character(0), tables = NULL, table_prefix = NULL) {
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("xml2 package is required for VENUS XML export.")
  }

  get_case_insensitive_col <- function(cols, target) {
    idx <- which(tolower(cols) == tolower(target))
    if (length(idx) == 0) return(NULL)
    cols[idx[1]]
  }

  dms_parts <- function(value) {
    if (is.na(value)) return(list(deg = NA_real_, min = NA_real_, sec = NA_real_))
    abs_val <- abs(value)
    d <- floor(abs_val)
    m_full <- (abs_val - d) * 60
    m <- floor(m_full)
    s <- (m_full - m) * 60
    if (!is.na(s) && s >= 59.995) {
      s <- 0
      m <- m + 1
    }
    if (!is.na(m) && m >= 60) {
      m <- 0
      d <- d + 1
    }
    list(deg = d, min = m, sec = round(s, 2))
  }

  access_column_order <- list(
    Sample_Env = c(
      "PlotNumber", "FieldNumber", "ProjectID", "FSRegionDistrict", "Date", "SiteSurveyor",
      "PlotRepresenting", "Location", "Ecosection", "NtsMapSheet", "Latitude",
      "LatitudeDegrees", "LatitudeMinutes", "LatitudeSeconds",
      "Longitude", "LongitudeDegrees", "LongitudeMinutes", "LongitudeSeconds",
      "UTMZone", "UTMEasting", "UTMNorthing", "LocationAccuracy", "AirPhotoNum", "XCoord",
      "YCoord", "Zone", "SubZone", "SiteSeries", "SiteModifier1", "SiteModifier2",
      "TransDistrib", "RealmClass", "MapUnit", "SnowCoverregime", "MoistureRegime",
      "NutrientRegime", "SuccessionalStatus", "StructuralStage", "StructuralStageMod",
      "StandAge", "Elevation", "SlopeGradient", "Aspect", "MesoSlopePosition", "SurfaceShape",
      "SurfaceTopographyType", "SurfaceTopographySize", "WaterSource", "Photo", "Exposure1",
      "Exposure2", "SiteDisturbance1", "SiteDisturbance2", "SiteDisturbance3", "SubstrateDecWood",
      "SubstrateBedRock", "SubstrateRocks", "SubstrateMineralSoil", "SubstrateOrganicMatter",
      "SubstrateWater", "SiteNotes", "SoilSurveyor", "BedrockGeology1", "BedrockGeology2",
      "BedrockGeology3", "CoarseFragLith1", "CoarseFragLith2", "CoarseFragLith3",
      "TerrainTextureSurf", "SurficialMaterialSurf", "SurfaceExpSurf", "GeoMorProSurf",
      "TerrainTextureSubSurf", "SurficialMaterialSubSurf", "SurfaceExpSubSurf", "GeoMorProSubSurf",
      "FloodingRegimeFreq", "MoistureRegimeSub", "FloodingRegimeDur", "SoilDrainage", "SeepageDepth",
      "RootRestrictingType", "RootRestrictingDepth", "RootZoneParticleSize", "RootingDepth",
      "SoilClassSubGroup", "SoilClassGroup", "HumusForm", "HumusFormPhase", "pHMethodCodeMineral",
      "pHMethodCodeOrganic", "SoilNotes", "VegSurveyor", "StrataCoverTree", "StrataCoverShrub",
      "StrataCoverHerb", "StrataCoverMoss", "VegNotes", "HydroGeoSystem", "HydroGeoSubSystem",
      "SpeciesListComplete", "Temporary", "Flag", "SV_PolygonNumber", "SV_FloodPlain",
      "SV_StandAgeEstMeas", "SV_StandHeight", "SV_StandHeightEstMeas", "SV_CanopyComposition",
      "SV_SoilDepth", "SV_RootZoneTexture", "SV_PercentCoarseFrags", "SV_GleyingMottlingCM",
      "SV_WaterTableCM", "SV_FullCruiseCard", "SV_AhorizonType", "SV_AhorizonDepth", "ActiveLayerDepth"
    ),
    Sample_Veg = c(
      "PlotNumber", "Species", "Layer", "Cover1", "Height1", "Cover2", "Height2", "Cover3",
      "Height3", "TotalA", "HeightA", "Cover4", "Height4", "Cover5", "Height5", "Cover5a",
      "Height5a", "Cover5b", "Height5b", "Cover5c", "Height5c", "TotalB", "HeightB", "Cover6",
      "Height6", "Cover7", "Cover8", "Cover9", "Cover10", "Collected", "Flag", "ID", "LL",
      "AF", "DC", "UT", "VI", "PV", "PG", "FFA", "Cultural1", "Cultural2", "Other1", "Other2"
    ),
    Sample_Humus = c(
      "PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HumusStructureDegree",
      "HumusStructureKind", "MycelAbundance", "FecalAbundance", "RootsAbundance", "RootsSize",
      "vonPost", "HumusFormpH", "Consistence", "Character", "Fauna", "Comment", "Flag", "ID"
    ),
    Sample_Mineral = c(
      "PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "PitDepthLimit", "Colour", "ASP",
      "Texture", "PercentCoarseFragsGravel", "PercentCoarseFragsCobbles", "PercentCoarseFragsStones",
      "PercentCoarseFragsTotal", "PercentCoarseFragsShape", "RootsAbundance", "RootsSize",
      "MineralStructureClass", "MineralStructureKind", "MineralFormpH", "MottlesAbundance",
      "MottlesSize", "MottlesContrast", "ClayFilmsFreq", "ClayFilmThickness", "Effervescence",
      "Porosity", "Comments", "Flag", "ID"
    ),
    Sample_Other = c(
      "PlotNumber", "DataName", "DataItem", "UserItem1", "UserItem2", "UserItem3", "UserFlag1",
      "UserFlag2", "UserFlag3", "Flag", "ID"
    ),
    Sample_Audit = c(
      "Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit",
      "Restore", "Flag", "ID"
    )
  )

  if (is.null(tables)) {
    tables <- c("Sample_Env", "Sample_Veg", "Sample_Humus", "Sample_Mineral", "Sample_Other", "Sample_Audit")
  }

  tables <- tables[vapply(tables, function(x) DBI::dbExistsTable(con, x), logical(1))]

  fetch_table_data <- function(table_name, project_ids) {
    if (!DBI::dbExistsTable(con, table_name)) return(NULL)

    fields <- DBI::dbListFields(con, table_name)
    project_col <- get_case_insensitive_col(fields, "ProjectID")
    if (is.null(project_col)) project_col <- get_case_insensitive_col(fields, "Project")
    plot_col <- get_case_insensitive_col(fields, "PlotNumber")

    sql <- paste("SELECT * FROM", table_name)
    params <- list()

    if (length(project_ids) > 0) {
      placeholders <- paste(rep("?", length(project_ids)), collapse = ", ")
      if (!is.null(project_col)) {
        sql <- paste0(sql, " WHERE ", project_col, " IN (", placeholders, ")")
        params <- as.list(project_ids)
      } else if (!is.null(plot_col) && DBI::dbExistsTable(con, "Sample_Env")) {
        env_fields <- DBI::dbListFields(con, "Sample_Env")
        env_project_col <- get_case_insensitive_col(env_fields, "ProjectID")
        env_plot_col <- get_case_insensitive_col(env_fields, "PlotNumber")
        if (!is.null(env_project_col) && !is.null(env_plot_col)) {
          sql <- paste(
            "SELECT t.* FROM", table_name, "t",
            "INNER JOIN Sample_Env e ON t.", plot_col, "= e.", env_plot_col
          )
          sql <- paste0(sql, " WHERE e.", env_project_col, " IN (", placeholders, ")")
          params <- as.list(project_ids)
        }
      }
    }

    DBI::dbGetQuery(con, sql, params)
  }

  resolve_prefix <- function(project_id, prefix, multi_project) {
    prefix <- if (!is.null(prefix) && nzchar(prefix)) prefix else NULL
    if (is.null(prefix)) return(project_id)
    if (multi_project) return(paste0(prefix, "_", project_id))
    prefix
  }

  venus_table_name <- function(project_id, table_name, prefix, multi_project) {
    suffix_map <- c(
      Sample_Env = "Env",
      Sample_Veg = "Veg",
      Sample_Humus = "Humus",
      Sample_Mineral = "Mineral",
      Sample_Other = "Other",
      Sample_Audit = "Audit"
    )
    suffix <- suffix_map[[table_name]]
    if (is.null(suffix)) suffix <- table_name
    paste0(resolve_prefix(project_id, prefix, multi_project), "_", suffix)
  }

  null_coalesce <- function(value, fallback) {
    if (is.null(value)) fallback else value
  }

  build_column_plan <- function(table_name, data_cols, desired_cols) {
    desired_cols <- null_coalesce(desired_cols, character(0))
    data_lower <- tolower(data_cols)
    desired_lower <- tolower(desired_cols)
    used <- rep(FALSE, length(data_cols))
    plan <- list()

    virtual_cols <- list(
      Sample_Env = c(
        "LatitudeDegrees", "LatitudeMinutes", "LatitudeSeconds",
        "LongitudeDegrees", "LongitudeMinutes", "LongitudeSeconds"
      )
    )
    virtual_set <- virtual_cols[[table_name]]

    if (length(desired_cols) > 0) {
      for (idx in seq_along(desired_lower)) {
        match_idx <- which(data_lower == desired_lower[idx])
        if (length(match_idx) > 0) {
          match_idx <- match_idx[1]
          if (used[match_idx]) next
          used[match_idx] <- TRUE
          plan[[length(plan) + 1]] <- list(
            kind = "data",
            data_col = data_cols[match_idx],
            tag_col = desired_cols[idx]
          )
        } else if (!is.null(virtual_set) && desired_cols[idx] %in% virtual_set) {
          plan[[length(plan) + 1]] <- list(
            kind = "virtual",
            tag_col = desired_cols[idx]
          )
        } else {
          plan[[length(plan) + 1]] <- list(
            kind = "missing",
            tag_col = desired_cols[idx]
          )
        }
      }
      return(plan)
    }

    for (col_name in data_cols) {
      plan[[length(plan) + 1]] <- list(kind = "data", data_col = col_name, tag_col = col_name)
    }

    plan
  }

  resolve_virtual_value <- function(table_name, tag_col, row, col_map) {
    if (table_name != "Sample_Env") return("")
    if (is.null(col_map$Latitude) || is.null(col_map$Longitude)) return("")

    lat <- suppressWarnings(as.numeric(row[[col_map$Latitude]]))
    lon <- suppressWarnings(as.numeric(row[[col_map$Longitude]]))
    lat_parts <- dms_parts(lat)
    lon_parts <- dms_parts(lon)

    switch(tag_col,
      LatitudeDegrees = lat_parts$deg,
      LatitudeMinutes = lat_parts$min,
      LatitudeSeconds = lat_parts$sec,
      LongitudeDegrees = lon_parts$deg,
      LongitudeMinutes = lon_parts$min,
      LongitudeSeconds = lon_parts$sec,
      ""
    )
  }

  write_table_xml <- function(doc_node, table_name, project_ids, project_id, prefix, multi_project) {
    data <- fetch_table_data(table_name, project_ids)
    if (is.null(data) || nrow(data) == 0) return()

    col_plan <- build_column_plan(table_name, names(data), access_column_order[[table_name]])
    col_map <- list(
      Latitude = get_case_insensitive_col(names(data), "Latitude"),
      Longitude = get_case_insensitive_col(names(data), "Longitude")
    )

    table_node <- xml2::xml_add_child(doc_node, venus_table_name(project_id, table_name, prefix, multi_project))
    for (row_idx in seq_len(nrow(data))) {
      row_node <- xml2::xml_add_child(table_node, "Row")
      for (col_def in col_plan) {
        if (!is.null(col_def$kind) && col_def$kind == "virtual") {
          value <- resolve_virtual_value(table_name, col_def$tag_col, data[row_idx, , drop = FALSE], col_map)
        } else if (!is.null(col_def$kind) && col_def$kind == "missing") {
          value <- ""
        } else {
          value <- data[[col_def$data_col]][row_idx]
        }
        if (is.na(value) || is.null(value)) value <- ""
        xml2::xml_add_child(row_node, col_def$tag_col, as.character(value))
      }
    }
  }

  get_project_count <- function(project_ids) {
    if (length(project_ids) > 0) {
      return(length(unique(as.character(project_ids))))
    }
    if (DBI::dbExistsTable(con, "Sample_Env")) {
      env_fields <- DBI::dbListFields(con, "Sample_Env")
      env_project_col <- get_case_insensitive_col(env_fields, "ProjectID")
      if (!is.null(env_project_col)) {
        sql <- paste0("SELECT COUNT(DISTINCT ", env_project_col, ") AS n FROM Sample_Env")
        count <- DBI::dbGetQuery(con, sql)$n
        if (length(count) == 1 && !is.na(count) && count > 0) return(as.integer(count))
      }
    }
    1L
  }

  root <- xml2::xml_new_root("VProExport")
  xml2::xml_set_attr(root, "generated", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))

  export_name <- if (!is.null(table_prefix) && nzchar(table_prefix)) {
    table_prefix
  } else if (length(project_ids) == 1) {
    as.character(project_ids)
  } else {
    "ALL"
  }
  meta_node <- xml2::xml_add_child(root, "ExportMeta")
  xml2::xml_add_child(meta_node, "Name", export_name)
  xml2::xml_add_child(meta_node, "ProjectCount", as.character(get_project_count(project_ids)))
  xml2::xml_add_child(meta_node, "GeneratedAt", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))

  multi_project <- length(project_ids) > 1

  if (length(project_ids) == 0) {
    project_node <- xml2::xml_add_child(root, "Project")
    xml2::xml_set_attr(project_node, "id", "ALL")
    for (table_name in tables) {
      write_table_xml(project_node, table_name, project_ids, "ALL", table_prefix, multi_project)
    }
  } else {
    for (project_id in project_ids) {
      project_node <- xml2::xml_add_child(root, "Project")
      xml2::xml_set_attr(project_node, "id", as.character(project_id))
      for (table_name in tables) {
        write_table_xml(project_node, table_name, project_id, project_id, table_prefix, multi_project)
      }
    }
  }

  root
}

mod_export_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Export R Dataset"),
      card_body(
        p("Generate a standard 'Wide' vegetation matrix compatible with R packages like 'vegan'."),
        layout_columns(
            selectInput(ns("export_proj"), "Filter by Project (Optional)", choices = NULL, multiple = TRUE),
            div(
                checkboxGroupInput(ns("export_layers"), "Layers", 
                                   choices = c("1 (Tree A1)"="1", "2 (Tree A2)"="2", "3 (Tree A3)"="3",
                                               "4 (Shrub B1)"="4", "5 (Shrub B2)"="5", 
                                               "6 (Herb C)"="6", "7 (Moss D)"="7"),
                                   selected = c("1","2","3","4","5","6","7"),
                                   inline = TRUE),
                checkboxInput(ns("export_lump"), "Apply Species Lumping", value = FALSE)
            ),
            col_widths = c(4, 8)
        ),
        div(class="d-flex gap-2",
            downloadButton(ns("dl_r_csv"), "Download CSV", class="btn-primary"),
            downloadButton(ns("dl_r_rds"), "Download RDS", class="btn-secondary")
        )
      )
    ),
    
    card(
      card_header("Export VENUS (XML)"),
      card_body(
        p("Export data in the VENUS XML format for submission."),
        textInput(ns("venus_prefix"), "Export name (optional)", placeholder = "e.g., MyProject"),
        downloadButton(ns("dl_venus"), "Download VENUS XML", class="btn-info")
      )
    )
  )
}

mod_export_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    
    # -- Initialize Choices --
    observe({
        # Load projects
        projs <- dbGetQuery(con, "SELECT projectid, projecttitle FROM Sample_Metadata ORDER BY projectid")
        if (nrow(projs) > 0) {
            updateSelectInput(session, "export_proj", choices = setNames(projs$projectid, paste(projs$projectid, "-", projs$projecttitle)))
        }
    })
    
    # -- Data Generation Helper --
    get_export_data <- function() {
        req(input$export_layers)
        
        # 1. Base Query
        # Using vw_USysAllVeg which is (PlotNumber, MyLayer, Species, Cover)
        
        # Filter layers
        layers_sql <- paste(paste0("'", input$export_layers, "'"), collapse=", ")
        query_veg <- sprintf("SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg WHERE MyLayer IN (%s)", layers_sql)
        
        # Filter Project
        if (!is.null(input$export_proj) && length(input$export_proj) > 0) {
            # Filter by project requires joining Sample_Env/Admin to find which project a plot belongs to?
            # Or Sample_Metadata?
            # Sample_Env contains 'projectid'
            projs_sql <- paste(paste0("'", input$export_proj, "'"), collapse=", ")
            query_veg <- sprintf("SELECT v.* FROM vw_USysAllVeg v 
                                  JOIN Sample_Env e ON v.PlotNumber = e.plotnumber 
                                  WHERE v.MyLayer IN (%s) AND e.projectid IN (%s)", 
                                  layers_sql, projs_sql)
        }
        
        df_veg <- dbGetQuery(con, query_veg)
        
        if (nrow(df_veg) == 0) return(NULL)
        
        # 1.5. Convert Cover to Numeric BEFORE Lumping
        # We need sum cover during lumping, so we must convert first.
        cover_chr <- trimws(as.character(df_veg$Cover))
        cover_num <- suppressWarnings(as.numeric(cover_chr))
        cover_num[cover_chr == ""] <- NA_real_
        cover_num[is.na(cover_num) & nzchar(cover_chr)] <- 0.1
        df_veg$CoverNum <- cover_num
        
        # 1.6. Apply Lumping (If selected)
        if (input$export_lump) {
            # Logic: We consolidate Species rows for the same Plot + Layer
            # This handles both 'Synonym Replacement' and 'Merging'
            df_veg <- apply_lumping(con, df_veg, 
                                    group_cols = c("PlotNumber", "MyLayer"), 
                                    measure_cols = c("CoverNum"))
        }

        # 2. Pivot to Wide
        df_veg$ColName <- paste0(df_veg$species, "_", df_veg$MyLayer)
        
        # Pivot
        library(tidyr)
        df_wide <- df_veg %>%
            select(PlotNumber, ColName, CoverNum) %>%
            pivot_wider(names_from = ColName, values_from = CoverNum, values_fill = 0)
            
        # 3. Get Env Data
        query_env <- "SELECT plotnumber, projectid, _location, date, latitude, longitude, elevation, slopegradient, aspect, sitenotes FROM Sample_Env"
        if (!is.null(input$export_proj) && length(input$export_proj) > 0) {
             projs_sql <- paste(paste0("'", input$export_proj, "'"), collapse=", ")
             query_env <- sprintf("%s WHERE projectid IN (%s)", query_env, projs_sql)
        }
        
        df_env <- dbGetQuery(con, query_env)
        
        # Join
        df_final <- right_join(df_env, df_wide, by = c("plotnumber" = "PlotNumber"))
        
        return(df_final)
    }
    
    # -- Download Handlers --
    output$dl_r_csv <- downloadHandler(
        filename = function() { paste0("vpro_export_", Sys.Date(), ".csv") },
        content = function(file) {
            d <- get_export_data()
            if(is.null(d)) { write.csv(data.frame(Message="No Data Found"), file); return() }
            write.csv(d, file, row.names=FALSE)
        }
    )
    
    output$dl_r_rds <- downloadHandler(
        filename = function() { paste0("vpro_export_", Sys.Date(), ".rds") },
        content = function(file) {
            d <- get_export_data()
            if(is.null(d)) { saveRDS(data.frame(Message="No Data Found"), file); return() }
            saveRDS(d, file)
        }
    )

    get_venus_project_ids <- function() {
      if (!is.null(input$export_proj) && length(input$export_proj) > 0) {
        return(input$export_proj)
      }
      if (!is.null(sys_state$CurrProject) && nzchar(as.character(sys_state$CurrProject))) {
        return(as.character(sys_state$CurrProject))
      }
      character(0)
    }

    output$dl_venus <- downloadHandler(
      filename = function() { paste0("vpro_venus_", Sys.Date(), ".xml") },
      content = function(file) {
        project_ids <- get_venus_project_ids()
        prefix <- trimws(as.character(input$venus_prefix))
        if (!nzchar(prefix)) prefix <- NULL
        doc <- build_venus_xml_doc(con, project_ids, table_prefix = prefix)
        xml2::write_xml(doc, file)
      }
    )
    
  })
}
