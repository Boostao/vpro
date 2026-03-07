# Excel export helpers for report outputs.

sanitize_sheet_names <- function(names_vec) {
  if (length(names_vec) == 0) return(names_vec)
  cleaned <- gsub("[\\[\\]\\*:/\\\\?]", "_", names_vec)
  cleaned <- substr(cleaned, 1, 31)
  make.unique(cleaned, sep = "_")
}

build_short_veg_view <- function(summary, constancy_format, display_mode, show_common) {
  if (nrow(summary) == 0) return(data.frame())

  if (constancy_format) {
    view <- data.frame(
      Group = summary$group_label,
      Species = summary$species_label,
      Constancy = round(summary$presence_pct, 1),
      stringsAsFactors = FALSE
    )
  } else if (display_mode != "standard") {
    view <- data.frame(
      Group = summary$group_label,
      Species = summary$species_label,
      Display = summary$display_value,
      stringsAsFactors = FALSE
    )
  } else {
    view <- data.frame(
      Group = summary$group_label,
      Species = summary$species_label,
      Presence = round(summary$presence_pct, 1),
      MeanCover = round(summary$mean_cover, 1),
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(show_common) && tolower(show_common) != "none") {
    if (constancy_format) {
      view <- cbind(view[, c("Group", "Species")], Common = summary$common_label, view[, "Constancy", drop = FALSE])
    } else if (display_mode != "standard") {
      view <- cbind(view[, c("Group", "Species")], Common = summary$common_label, view[, "Display", drop = FALSE])
    } else {
      view <- cbind(view[, c("Group", "Species")], Common = summary$common_label, view[, c("Presence", "MeanCover")])
    }
  }

  view
}

build_long_veg_view <- function(report_table, constancy_format, display_mode, show_common) {
  if (nrow(report_table) == 0) return(data.frame())

  plot_cols <- setdiff(
    names(report_table),
    c("group_label", "species_label", "common_key", "presence_ratio", "mean_cover", "common_label")
  )
  plot_cols <- plot_cols[order(plot_cols)]

  view <- data.frame(
    Group = report_table$group_label,
    Species = report_table$species_label,
    stringsAsFactors = FALSE
  )
  if (!is.null(show_common) && tolower(show_common) != "none") {
    view$Common <- report_table$common_label
  }
  if (constancy_format) {
    view$Constancy <- round(report_table$presence_pct, 1)
  } else if (display_mode != "standard") {
    view$Display <- report_table$display_value
  } else {
    view$Presence <- round(report_table$presence_ratio * 100, 1)
    view$MeanCover <- round(report_table$mean_cover, 1)
  }

  if (length(plot_cols) > 0) {
    plot_data <- report_table[, plot_cols, drop = FALSE]
    plot_data <- as.data.frame(lapply(plot_data, function(col) {
      col_num <- as.numeric(col)
      ifelse(is.na(col_num), "", round(col_num, 1))
    }), stringsAsFactors = FALSE)
    names(plot_data) <- plot_cols
    view <- cbind(view, plot_data)
  }

  view
}

normalize_env_export <- function(env) {
  if (nrow(env) == 0) return(env)
  cols <- names(env)
  pick_col <- function(candidates) {
    idx <- which(tolower(cols) %in% tolower(candidates))
    if (length(idx) > 0) cols[[idx[1]]] else NA_character_
  }
  map <- list(
    plotnumber = c("plotnumber", "PlotNumber"),
    projectid = c("projectid", "ProjectID"),
    date = c("date", "Date"),
    sitesurveyor = c("sitesurveyor", "SiteSurveyor"),
    latitude = c("latitude", "Latitude"),
    longitude = c("longitude", "Longitude"),
    elevation = c("elevation", "Elevation"),
    aspect = c("aspect", "Aspect"),
    slopegradient = c("slopegradient", "SlopeGradient"),
    mesoslopeposition = c("mesoslopeposition", "MesoSlopePosition"),
    surfaceshape = c("surfaceshape", "SurfaceShape"),
    moistureregime = c("moistureregime", "MoistureRegime"),
    nutrientregime = c("nutrientregime", "NutrientRegime")
  )
  for (target in names(map)) {
    source <- pick_col(map[[target]])
    if (!is.na(source)) env[[target]] <- env[[source]]
  }
  env
}

normalize_env_long_export <- function(env) {
  if (nrow(env) == 0) return(env)
  cols <- names(env)
  pick_col <- function(candidates) {
    idx <- which(tolower(cols) %in% tolower(candidates))
    if (length(idx) > 0) cols[[idx[1]]] else NA_character_
  }
  map <- list(
    plotnumber = c("plotnumber", "PlotNumber"),
    fieldnumber = c("fieldnumber", "FieldNumber"),
    fsregiondistrict = c("fsregiondistrict", "FSRegionDistrict"),
    siteplotquality = c("siteplotquality", "SitePlotQuality"),
    zone = c("zone", "Zone"),
    subzone = c("subzone", "SubZone"),
    siteseries = c("siteseries", "SiteSeries"),
    usersiteunit = c("usersiteunit", "UserSiteUnit"),
    location = c("location", "Location"),
    ntsmapsheet = c("ntsmapsheet", "NtsMapSheet"),
    longitude = c("longitude", "Longitude"),
    latitude = c("latitude", "Latitude"),
    elevation = c("elevation", "Elevation"),
    slopegradient = c("slopegradient", "SlopeGradient"),
    aspect = c("aspect", "Aspect"),
    mesoslopeposition = c("mesoslopeposition", "MesoSlopePosition"),
    surfaceshape = c("surfaceshape", "SurfaceShape"),
    surfacetopographytype = c("surfacetopographytype", "SurfaceTopographyType"),
    moistureregime = c("moistureregime", "MoistureRegime"),
    nutrientregime = c("nutrientregime", "NutrientRegime"),
    exposure1 = c("exposure1", "Exposure1"),
    exposure2 = c("exposure2", "Exposure2"),
    sitedisturbance1 = c("sitedisturbance1", "SiteDisturbance1"),
    sitedisturbance2 = c("sitedisturbance2", "SiteDisturbance2"),
    sitedisturbance3 = c("sitedisturbance3", "SiteDisturbance3"),
    substratedecwood = c("substratedecwood", "SubstrateDecWood"),
    substratebedrock = c("substratebedrock", "SubstrateBedRock"),
    substraterocks = c("substraterocks", "SubstrateRocks"),
    substratemineralsoil = c("substratemineralsoil", "SubstrateMineralSoil"),
    substrateorganicmatter = c("substrateorganicmatter", "SubstrateOrganicMatter"),
    substratewater = c("substratewater", "SubstrateWater"),
    soilclassgroup = c("soilclassgroup", "SoilClassGroup"),
    soilclasssubgroup = c("soilclasssubgroup", "SoilClassSubGroup"),
    bedrockgeology1 = c("bedrockgeology1", "BedrockGeology1"),
    bedrockgeology2 = c("bedrockgeology2", "BedrockGeology2"),
    bedrockgeology3 = c("bedrockgeology3", "BedrockGeology3"),
    coarsefraglith1 = c("coarsefraglith1", "CoarseFragLith1"),
    coarsefraglith2 = c("coarsefraglith2", "CoarseFragLith2"),
    coarsefraglith3 = c("coarsefraglith3", "CoarseFragLith3"),
    terraintexturesurf = c("terraintexturesurf", "TerrainTextureSurf"),
    terraintexturesubsurf = c("terraintexturesubsurf", "TerrainTextureSubSurf"),
    surficialmaterialsurf = c("surficialmaterialsurf", "SurficialMaterialSurf"),
    surficialmaterialsubsurf = c("surficialmaterialsubsurf", "SurficialMaterialSubSurf"),
    surfaceexpsurf = c("surfaceexpsurf", "SurfaceExpSurf"),
    surfaceexpsubsurf = c("surfaceexpsubsurf", "SurfaceExpSubSurf"),
    geomorprosurf = c("geomorprosurf", "GeoMorProSurf"),
    geomorprosubsurf = c("geomorprosubsurf", "GeoMorProSubSurf"),
    rootzoneparticlesize = c("rootzoneparticlesize", "RootZoneParticleSize"),
    rootingdepth = c("rootingdepth", "RootingDepth"),
    rootrestrictingtype = c("rootrestrictingtype", "RootRestrictingType"),
    rootrestrictingdepth = c("rootrestrictingdepth", "RootRestrictingDepth"),
    seepagedepth = c("seepagedepth", "SeepageDepth"),
    soildrainage = c("soildrainage", "SoilDrainage"),
    humusform = c("humusform", "HumusForm"),
    humusformphase = c("humusformphase", "HumusFormPhase"),
    humusthickness = c("humusthickness", "HumusThickness"),
    standage = c("standage", "StandAge"),
    successionalstatus = c("successionalstatus", "SuccessionalStatus"),
    structuralstage = c("structuralstage", "StructuralStage"),
    stratacovertree = c("stratacovertree", "StrataCoverTree"),
    stratacovershrub = c("stratacovershrub", "StrataCoverShrub"),
    stratacoverherb = c("stratacoverherb", "StrataCoverHerb"),
    stratacovermoss = c("stratacovermoss", "StrataCoverMoss"),
    hydrogeosystem = c("hydrogeosystem", "HydroGeoSystem"),
    hydrogeosubsystem = c("hydrogeosubsystem", "HydroGeoSubSystem"),
    watersource = c("watersource", "WaterSource"),
    floodingregimefreq = c("floodingregimefreq", "FloodingRegimeFreq"),
    sitenotes = c("sitenotes", "SiteNotes")
  )
  for (target in names(map)) {
    source <- pick_col(map[[target]])
    if (!is.na(source)) env[[target]] <- env[[source]]
  }
  env
}

normalize_hier_export <- function(hier) {
  if (nrow(hier) == 0) return(hier)
  cols <- names(hier)
  pick_col <- function(candidates) {
    idx <- which(tolower(cols) %in% tolower(candidates))
    if (length(idx) > 0) cols[[idx[1]]] else NA_character_
  }
  id_col <- pick_col(c("id", "ID"))
  name_col <- pick_col(c("name", "Name", "_name"))
  parent_col <- pick_col(c("parent", "Parent"))
  level_col <- pick_col(c("level", "Level"))
  tag_col <- pick_col(c("tag", "Tag"))
  if (!is.na(id_col)) hier$ID <- hier[[id_col]]
  if (!is.na(name_col)) hier$Name <- hier[[name_col]]
  if (!is.na(parent_col)) hier$Parent <- hier[[parent_col]]
  if (!is.na(level_col)) hier$Level <- hier[[level_col]]
  if (!is.na(tag_col)) hier$Tag <- hier[[tag_col]]
  hier
}

build_hierarchy_view <- function(veg, hier_col, constancy_format, display_mode, display_value) {
  if (nrow(veg) == 0) return(data.frame())

  if (constancy_format || display_mode != "standard") {
    veg_norm <- normalize_veg_cols(veg)
    if (!is.null(hier_col)) {
      veg_norm$hierarchy <- as.character(veg[[hier_col]])
    }
    veg_norm$cover_num <- suppressWarnings(as.numeric(veg_norm$cover))
    veg_norm$present_num <- ifelse(is.na(veg_norm$cover) | !nzchar(trimws(veg_norm$cover)), 0L, 1L)
    veg_norm$present <- veg_norm$present_num > 0
    summary <- summarize_veg_report(
      veg_norm,
      group_by = "hierarchy",
      order_by = "species",
      presence_min = 0,
      cover_min = 0,
      value_limit = 0,
      avg_type = "mean",
      show_common = "none",
      display_value = display_value
    )
    view <- data.frame(
      Group = summary$group_label,
      Species = summary$species_label,
      stringsAsFactors = FALSE
    )
    if (constancy_format) {
      view$Constancy <- round(summary$presence_pct, 1)
    } else {
      view$Display <- summary$display_value
    }
  } else {
    desired <- c("PlotNumber", "MyLayer", "Species", "CoverValue")
    cols <- intersect(desired, names(veg))
    if (!is.null(hier_col)) cols <- c(cols, hier_col)
    view <- veg[, cols, drop = FALSE]
  }

  if (!is.null(hier_col)) {
    group_col <- if ("Group" %in% names(view)) "Group" else hier_col
    view <- view[order(view[[group_col]], view$Species, na.last = TRUE), , drop = FALSE]
    split_view <- split(view, view[[group_col]], drop = TRUE)
    view <- do.call(rbind, lapply(names(split_view), function(name) {
      section <- split_view[[name]]
      header <- section[1, , drop = FALSE]
      header[] <- ""
      header[[group_col]] <- paste0("Hierarchy: ", name)
      rbind(header, section)
    }))
  }

  view
}

build_excel_report_data <- function(con, template_name, params) {
  template_name <- if (is.null(template_name)) "" else as.character(template_name)
  if (!nzchar(template_name)) return(NULL)

  if (template_name %in% c("short_veg.qmd", "long_veg.qmd", "short_veg_env.qmd")) {
    plots <- parse_plot_numbers(params$plot_number, params$plot_numbers)
    veg <- load_veg_report_data(
      con,
      plot_numbers = plots,
      site_unit = trimws(params$site_unit),
      project_id = trimws(params$project_id),
      apply_lumping = isTRUE(params$apply_lumping)
    )

    summary <- summarize_veg_report(
      veg,
      group_by = if (isTRUE(params$constancy_format)) "lifeform" else params$group_by,
      order_by = params$order_by,
      presence_min = params$presence_min,
      cover_min = params$cover_min,
      value_limit = params$value_limit,
      avg_type = params$avg_type,
      show_common = params$show_common,
      display_value = params$display_value
    )

    constancy_format <- isTRUE(params$constancy_format)
    display_mode <- if (!is.null(params$display_value) && nzchar(params$display_value)) {
      tolower(params$display_value)
    } else {
      "standard"
    }

    if (template_name == "short_veg.qmd") {
      view <- build_short_veg_view(summary, constancy_format, display_mode, params$show_common)
      return(list(Vegetation = view))
    }

    if (template_name == "short_veg_env.qmd") {
      plot_list <- unique(veg$plotnumber)
      if (length(plot_list) == 0) plot_list <- plots
      if (length(plot_list) > 0) {
        plot_sql <- paste(DBI::dbQuoteString(con, plot_list), collapse = ", ")
        env <- DBI::dbGetQuery(con, sprintf("SELECT * FROM Sample_Env WHERE PlotNumber IN (%s)", plot_sql))
      } else {
        env <- data.frame()
      }
      env <- normalize_env_export(env)
      desired <- c(
        "plotnumber", "projectid", "date", "sitesurveyor", "latitude", "longitude", "elevation",
        "aspect", "slopegradient", "mesoslopeposition", "surfaceshape", "moistureregime",
        "nutrientregime"
      )
      env_view <- env[, intersect(desired, names(env)), drop = FALSE]
      veg_view <- build_short_veg_view(summary, constancy_format, display_mode, params$show_common)
      return(list(Environment = env_view, Vegetation = veg_view))
    }

    if (template_name == "long_veg.qmd") {
      veg_labeled <- label_veg_records(veg, params$group_by, params$show_common)
      if (nrow(veg_labeled) > 0) {
        summary$common_key <- ifelse(is.na(summary$common_label), "", summary$common_label)
        veg_labeled$common_key <- ifelse(is.na(veg_labeled$common_label), "", veg_labeled$common_label)
        summary_keep <- summary[, c(
          "group_label",
          "species_label",
          "common_key",
          "presence_ratio",
          "presence_pct",
          "mean_cover",
          "display_value",
          "common_label"
        )]
        veg_labeled <- dplyr::inner_join(
          veg_labeled,
          summary_keep[, c("group_label", "species_label", "common_key")],
          by = c("group_label", "species_label", "common_key")
        )
      }

      veg_pivot <- data.frame()
      if (nrow(veg_labeled) > 0) {
        veg_pivot <- veg_labeled %>%
          dplyr::group_by(group_label, species_label, common_key, plotnumber) %>%
          dplyr::summarise(cover = sum(cover_num, na.rm = TRUE), .groups = "drop")
      }

      veg_wide <- data.frame()
      if (nrow(veg_pivot) > 0) {
        veg_wide <- reshape(
          veg_pivot,
          idvar = c("group_label", "species_label", "common_key"),
          timevar = "plotnumber",
          direction = "wide"
        )
        plot_cols_raw <- grep("^cover\\.", names(veg_wide), value = TRUE)
        if (length(plot_cols_raw) > 0) {
          plot_cols <- sub("^cover\\.", "", plot_cols_raw)
          names(veg_wide)[match(plot_cols_raw, names(veg_wide))] <- plot_cols
        }
      }

      report_table <- data.frame()
      if (nrow(summary) > 0) {
        summary$common_key <- ifelse(is.na(summary$common_label), "", summary$common_label)
        summary_keep <- summary[, c(
          "group_label",
          "species_label",
          "common_key",
          "presence_ratio",
          "presence_pct",
          "mean_cover",
          "display_value",
          "common_label"
        )]
        if (nrow(veg_wide) > 0) {
          report_table <- dplyr::left_join(
            summary_keep,
            veg_wide,
            by = c("group_label", "species_label", "common_key")
          )
        } else {
          report_table <- summary_keep
        }
      }

      view <- build_long_veg_view(report_table, constancy_format, display_mode, params$show_common)
      return(list(Vegetation = view))
    }
  }

  if (template_name %in% c("short_veg_hierarchy.qmd", "short_veg_order_hierarchy.qmd")) {
    plots <- parse_plot_numbers(params$plot_number, params$plot_numbers)
    if (length(plots) == 0 && (nzchar(trimws(params$site_unit)) || nzchar(trimws(params$project_id)))) {
      seed <- load_veg_report_data(
        con,
        plot_numbers = plots,
        site_unit = trimws(params$site_unit),
        project_id = trimws(params$project_id),
        apply_lumping = FALSE
      )
      plots <- unique(seed$plotnumber)
    }

    if (length(plots) > 0) {
      plot_sql <- paste(DBI::dbQuoteString(con, plots), collapse = ", ")
      veg <- DBI::dbGetQuery(con, sprintf("SELECT * FROM vw_USysAllVeg WHERE PlotNumber IN (%s)", plot_sql))
    } else {
      veg <- data.frame()
    }

    normalize_raw_cols <- function(df) {
      if (nrow(df) == 0) return(df)
      cols <- names(df)
      pick_col <- function(candidates) {
        idx <- which(tolower(cols) %in% tolower(candidates))
        if (length(idx) > 0) cols[[idx[1]]] else NA_character_
      }
      plot_col <- pick_col(c("plotnumber", "PlotNumber"))
      layer_col <- pick_col(c("mylayer", "layer", "MyLayer"))
      species_col <- pick_col(c("species", "species_code", "Species"))
      cover_col <- pick_col(c("covervalue", "cover_value", "cover", "CoverValue"))
      if (!is.na(plot_col)) df$PlotNumber <- df[[plot_col]]
      if (!is.na(layer_col)) df$MyLayer <- df[[layer_col]]
      if (!is.na(species_col)) df$Species <- df[[species_col]]
      if (!is.na(cover_col)) df$CoverValue <- df[[cover_col]]
      df
    }

    veg <- normalize_raw_cols(veg)

    hier_col <- NULL
    for (candidate in c("Hierarchy", "HierarchyName", "hierarchy", "Hierarchy_Path", "HierarchyPath")) {
      if (candidate %in% names(veg)) {
        hier_col <- candidate
        break
      }
    }

    constancy_format <- isTRUE(params$constancy_format)
    display_mode <- if (!is.null(params$display_value) && nzchar(params$display_value)) {
      tolower(params$display_value)
    } else {
      "standard"
    }

    view <- build_hierarchy_view(veg, hier_col, constancy_format, display_mode, params$display_value)
    return(list(Vegetation = view))
  }

  if (template_name == "env_summary.qmd") {
    plots <- parse_plot_numbers(params$plot_number, params$plot_numbers)
    if (length(plots) == 0 && nzchar(trimws(params$site_unit)) && DBI::dbExistsTable(con, "Sample_SU")) {
      su_df <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber FROM Sample_SU WHERE SiteUnit = ?",
        list(trimws(params$site_unit))
      )
      plots <- unique(as.character(su_df$PlotNumber))
    }
    if (length(plots) == 0 && nzchar(trimws(params$project_id)) && DBI::dbExistsTable(con, "Sample_Env")) {
      env_df <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber FROM Sample_Env WHERE ProjectID = ?",
        list(trimws(params$project_id))
      )
      plots <- unique(as.character(env_df$PlotNumber))
    }

    plots <- plots[nzchar(plots)]
    if (length(plots) > 0) {
      plot_sql <- paste(DBI::dbQuoteString(con, plots), collapse = ", ")
      env <- DBI::dbGetQuery(con, sprintf("SELECT * FROM Sample_Env WHERE PlotNumber IN (%s)", plot_sql))
    } else {
      env <- data.frame()
    }

    site_unit_map <- data.frame()
    if (DBI::dbExistsTable(con, "Sample_SU")) {
      site_unit_map <- DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM Sample_SU")
    }

    unit_names <- data.frame()
    if (DBI::dbExistsTable(con, "lists.MasterSiteUnitList")) {
      unit_names <- DBI::dbGetQuery(con, "SELECT SiteSeries, SiteSeriesLongName FROM lists.MasterSiteUnitList")
    }

    env <- normalize_env_export(env)
    if (nrow(env) > 0 && nrow(site_unit_map) > 0) {
      site_unit_map <- dplyr::rename(site_unit_map, plotnumber = PlotNumber, siteunit = SiteUnit)
      env <- dplyr::left_join(env, site_unit_map, by = "plotnumber")
    }
    if (nrow(env) > 0 && nrow(unit_names) > 0) {
      unit_names <- dplyr::rename(unit_names, siteunit = SiteSeries, siteunit_long = SiteSeriesLongName)
      env <- dplyr::left_join(env, unit_names, by = "siteunit")
    }

    if (nzchar(trimws(params$site_unit))) {
      env <- env[env$siteunit == trimws(params$site_unit), , drop = FALSE]
    }

    if (nrow(env) > 0) {
      desired <- c(
        "plotnumber", "siteunit", "siteunit_long", "projectid", "date", "sitesurveyor", "latitude",
        "longitude", "elevation", "aspect", "slopegradient", "mesoslopeposition", "surfaceshape",
        "moistureregime", "nutrientregime", "sitenotes"
      )
      env <- env[, intersect(desired, names(env)), drop = FALSE]
    }

    return(list(Environment = env))
  }

  if (template_name %in% c("hierarchy.qmd", "flat_hierarchy.qmd")) {
    hier <- DBI::dbGetQuery(con, "SELECT * FROM Sample_Hierarchy")
    long_names <- data.frame()
    if (DBI::dbExistsTable(con, c("lists", "MasterSiteUnitList"))) {
      long_names <- DBI::dbGetQuery(
        con,
        "SELECT SiteSeries, SiteSeriesLongName FROM lists.MasterSiteUnitList"
      )
    }
    hier <- normalize_hier_export(hier)
    cutoff_level <- suppressWarnings(as.integer(params$cutoff_level))
    if (!is.na(cutoff_level) && ("Level" %in% names(hier))) {
      hier <- hier[hier$Level <= cutoff_level, , drop = FALSE]
    }

    if (nrow(long_names) > 0) {
      names(long_names) <- tolower(names(long_names))
      names(long_names)[names(long_names) == "siteseries"] <- "name_key"
      names(long_names)[names(long_names) == "siteserieslongname"] <- "long_name"
      long_names$name_key <- as.character(long_names$name_key)
      hier$Name <- as.character(hier$Name)
      hier <- dplyr::left_join(hier, long_names[, c("name_key", "long_name")], by = c("Name" = "name_key"))
    }

    if (nrow(hier) > 0) {
      desired <- c("ID", "Name", "long_name", "Parent", "Level", "Tag")
      hier <- hier[, intersect(desired, names(hier)), drop = FALSE]
    }

    return(list(Hierarchy = hier))
  }

  if (template_name == "long_env.qmd") {
    plots <- parse_plot_numbers(params$plot_number, params$plot_numbers)
    if (length(plots) == 0 && nzchar(trimws(params$site_unit)) && DBI::dbExistsTable(con, "Sample_SU")) {
      su_df <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber FROM Sample_SU WHERE SiteUnit = ?",
        list(trimws(params$site_unit))
      )
      plots <- unique(as.character(su_df$PlotNumber))
    }
    if (length(plots) == 0 && nzchar(trimws(params$project_id)) && DBI::dbExistsTable(con, "Sample_Env")) {
      env_df <- DBI::dbGetQuery(
        con,
        "SELECT PlotNumber FROM Sample_Env WHERE ProjectID = ?",
        list(trimws(params$project_id))
      )
      plots <- unique(as.character(env_df$PlotNumber))
    }

    plots <- plots[nzchar(plots)]
    if (length(plots) > 0) {
      plot_sql <- paste(DBI::dbQuoteString(con, plots), collapse = ", ")
      env <- DBI::dbGetQuery(con, sprintf("SELECT * FROM Sample_Env WHERE PlotNumber IN (%s)", plot_sql))
    } else {
      env <- data.frame()
    }

    site_unit_map <- data.frame()
    if (DBI::dbExistsTable(con, "Sample_SU")) {
      site_unit_map <- DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM Sample_SU")
    }

    unit_names <- data.frame()
    if (DBI::dbExistsTable(con, "lists.MasterSiteUnitList")) {
      unit_names <- DBI::dbGetQuery(con, "SELECT SiteSeries, SiteSeriesLongName FROM lists.MasterSiteUnitList")
    }

    env <- normalize_env_long_export(env)
    if (nrow(env) > 0 && nrow(site_unit_map) > 0) {
      site_unit_map <- dplyr::rename(site_unit_map, plotnumber = PlotNumber, siteunit = SiteUnit)
      env <- dplyr::left_join(env, site_unit_map, by = "plotnumber")
    }
    if (nrow(env) > 0 && nrow(unit_names) > 0) {
      unit_names <- dplyr::rename(unit_names, siteunit = SiteSeries, siteunit_long = SiteSeriesLongName)
      env <- dplyr::left_join(env, unit_names, by = "siteunit")
    }

    if (nzchar(trimws(params$site_unit))) {
      env <- env[env$siteunit == trimws(params$site_unit), , drop = FALSE]
    }

    if (nrow(env) > 0) {
      desired <- c(
        "plotnumber", "fieldnumber", "fsregiondistrict", "siteplotquality", "siteunit",
        "siteunit_long", "zone", "subzone", "siteseries", "usersiteunit", "location", "ntsmapsheet",
        "longitude", "latitude", "elevation", "slopegradient", "aspect", "mesoslopeposition",
        "surfaceshape", "surfacetopographytype", "moistureregime", "nutrientregime", "exposure1",
        "exposure2", "sitedisturbance1", "sitedisturbance2", "sitedisturbance3", "substratedecwood",
        "substratebedrock", "substraterocks", "substratemineralsoil", "substrateorganicmatter",
        "substratewater", "soilclassgroup", "soilclasssubgroup", "bedrockgeology1", "bedrockgeology2",
        "bedrockgeology3", "coarsefraglith1", "coarsefraglith2", "coarsefraglith3",
        "terraintexturesurf", "terraintexturesubsurf", "surficialmaterialsurf", "surficialmaterialsubsurf",
        "surfaceexpsurf", "surfaceexpsubsurf", "geomorprosurf", "geomorprosubsurf",
        "rootzoneparticlesize", "rootingdepth", "rootrestrictingtype", "rootrestrictingdepth",
        "seepagedepth", "soildrainage", "humusform", "humusformphase", "humusthickness",
        "standage", "successionalstatus", "structuralstage", "stratacovertree", "stratacovershrub",
        "stratacoverherb", "stratacovermoss", "hydrogeosystem", "hydrogeosubsystem",
        "watersource", "floodingregimefreq", "sitenotes"
      )
      env <- env[, intersect(desired, names(env)), drop = FALSE]
    }

    if (nrow(env) == 0) {
      return(list(Environment = env))
    }

    if ("siteunit" %in% names(env)) {
      split_env <- split(env, env$siteunit, drop = TRUE)
      data_list <- lapply(names(split_env), function(name) split_env[[name]])
      names(data_list) <- names(split_env)
      return(data_list)
    }

    return(list(Environment = env))
  }

  NULL
}
