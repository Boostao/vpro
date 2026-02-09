# Compliance checks for core data integrity

table_id <- function(table_name) {
  if (grepl("\\.", table_name)) {
    parts <- strsplit(table_name, "\\.")[[1]]
    if (length(parts) == 2) {
      return(DBI::Id(schema = parts[1], table = parts[2]))
    }
  }
  table_name
}

get_table_fields <- function(con, table_name) {
  table_ref <- table_id(table_name)
  if (!DBI::dbExistsTable(con, table_ref)) return(character())
  DBI::dbListFields(con, table_ref)
}

has_cols <- function(fields, cols) {
  all(cols %in% fields)
}

check_required_fields <- function(con, project_id = NULL) {
  fields <- get_table_fields(con, "Sample_Env")
  required <- intersect(c("plotnumber", "projectid", "zone", "subzone"), fields)

  if (length(required) == 0) {
    return(data.frame())
  }

  sql <- "SELECT * FROM Sample_Env"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  issues <- list()
  for (col_name in required) {
    missing <- which(is.na(env[[col_name]]) | env[[col_name]] == "")
    if (length(missing) > 0) {
      issues[[length(issues) + 1]] <- data.frame(
        rule = "required",
        table = "Sample_Env",
        column = col_name,
        plotnumber = env$plotnumber[missing],
        details = "Missing required value",
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

check_species_fk <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "Sample_Veg")) == 0 || length(get_table_fields(con, "lists.SppList")) == 0) {
    return(data.frame())
  }

  veg_fields <- get_table_fields(con, "Sample_Veg")
  if (!has_cols(veg_fields, c("plotnumber", "species"))) return(data.frame())

  spp_fields <- get_table_fields(con, "lists.SppList")
  code_col <- if ("code" %in% spp_fields) {
    "code"
  } else if ("spp_code" %in% spp_fields) {
    "spp_code"
  } else {
    NULL
  }
  if (is.null(code_col)) return(data.frame())

  sql <- "SELECT plotnumber, species FROM Sample_Veg"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% veg_fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  veg <- DBI::dbGetQuery(con, sql, params)
  if (nrow(veg) == 0) return(data.frame())

  spp <- DBI::dbGetQuery(con, sprintf("SELECT %s AS code FROM lists.SppList", code_col))
  valid <- unique(spp$code)
  missing <- veg[!(veg$species %in% valid), , drop = FALSE]
  if (nrow(missing) == 0) return(data.frame())

  data.frame(
    rule = "fk_species",
    table = "Sample_Veg",
    column = "species",
    plotnumber = missing$plotnumber,
    details = paste0("Unknown species: ", missing$species),
    stringsAsFactors = FALSE
  )
}

check_zone_fk <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "Sample_Env")) == 0 || length(get_table_fields(con, "lists.USysZoneList")) == 0) {
    return(data.frame())
  }

  env_fields <- get_table_fields(con, "Sample_Env")
  if (!has_cols(env_fields, c("plotnumber", "zone", "subzone"))) return(data.frame())

  sql <- "SELECT plotnumber, zone, subzone FROM Sample_Env"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% env_fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  zone_fields <- get_table_fields(con, "lists.USysZoneList")
  zone_col <- if ("zone_code" %in% zone_fields) "zone_code" else if ("zone" %in% zone_fields) "zone" else NULL
  subzone_col <- if ("subzone" %in% zone_fields) "subzone" else NULL

  if (is.null(zone_col)) return(data.frame())

  zone_sql <- sprintf("SELECT DISTINCT %s AS zone_code%s FROM lists.USysZoneList", zone_col,
                      if (!is.null(subzone_col)) paste0(", ", subzone_col, " AS subzone") else "")
  zones <- DBI::dbGetQuery(con, zone_sql)
  valid_zones <- unique(zones$zone_code)

  issues <- list()
  bad_zone <- which(!is.na(env$zone) & !(env$zone %in% valid_zones))
  if (length(bad_zone) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "fk_zone",
      table = "Sample_Env",
      column = "zone",
      plotnumber = env$plotnumber[bad_zone],
      details = "Unknown zone",
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(subzone_col) && "subzone" %in% names(zones)) {
    valid_subzone <- unique(zones$subzone)
    bad_subzone <- which(!is.na(env$subzone) & !(env$subzone %in% valid_subzone))
    if (length(bad_subzone) > 0) {
      issues[[length(issues) + 1]] <- data.frame(
        rule = "fk_subzone",
        table = "Sample_Env",
        column = "subzone",
        plotnumber = env$plotnumber[bad_subzone],
        details = "Unknown subzone",
        stringsAsFactors = FALSE
      )
    }

    valid_pairs <- unique(zones[, c("zone_code", "subzone"), drop = FALSE])
    env_pairs <- data.frame(zone_code = env$zone, subzone = env$subzone, plotnumber = env$plotnumber)
    env_pairs <- env_pairs[!is.na(env_pairs$zone_code) & !is.na(env_pairs$subzone), , drop = FALSE]
    if (nrow(env_pairs) > 0) {
      pair_key <- paste(env_pairs$zone_code, env_pairs$subzone, sep = "|")
      valid_key <- paste(valid_pairs$zone_code, valid_pairs$subzone, sep = "|")
      bad_pair <- which(!(pair_key %in% valid_key))
      if (length(bad_pair) > 0) {
        issues[[length(issues) + 1]] <- data.frame(
          rule = "fk_zone_subzone",
          table = "Sample_Env",
          column = "subzone",
          plotnumber = env_pairs$plotnumber[bad_pair],
          details = "Zone/subzone combination not valid",
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

check_duplicate_plots <- function(con, project_id = NULL) {
  fields <- get_table_fields(con, "Sample_Env")
  if (!has_cols(fields, c("plotnumber", "projectid"))) return(data.frame())

  sql <- "SELECT plotnumber, projectid, COUNT(*) AS cnt FROM Sample_Env"
  params <- list()
  if (!is.null(project_id)) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }
  sql <- paste0(sql, " GROUP BY plotnumber, projectid HAVING COUNT(*) > 1")

  dupes <- DBI::dbGetQuery(con, sql, params)
  if (nrow(dupes) == 0) return(data.frame())

  data.frame(
    rule = "dup_plot",
    table = "Sample_Env",
    column = "plotnumber",
    plotnumber = dupes$plotnumber,
    details = "Duplicate plot number within project",
    stringsAsFactors = FALSE
  )
}

check_duplicate_veg <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "vw_USysAllVeg")) == 0) return(data.frame())

  veg_fields <- get_table_fields(con, "vw_USysAllVeg")
  species_col <- if ("species_code" %in% veg_fields) "species_code" else if ("species" %in% veg_fields) "species" else NULL
  layer_col <- if ("layer" %in% veg_fields) "layer" else if ("layer_code" %in% veg_fields) "layer_code" else NULL

  if (is.null(species_col) || is.null(layer_col) || !("plotnumber" %in% veg_fields)) {
    return(data.frame())
  }

  sql <- sprintf("SELECT plotnumber, %s AS species, %s AS layer, COUNT(*) AS cnt FROM vw_USysAllVeg", species_col, layer_col)
  params <- list()
  if (!is.null(project_id) && "projectid" %in% veg_fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }
  sql <- paste0(sql, " GROUP BY plotnumber, species, layer HAVING COUNT(*) > 1")

  dupes <- DBI::dbGetQuery(con, sql, params)
  if (nrow(dupes) == 0) return(data.frame())

  data.frame(
    rule = "dup_veg",
    table = "vw_USysAllVeg",
    column = "species",
    plotnumber = dupes$plotnumber,
    details = "Duplicate plot/species/layer",
    stringsAsFactors = FALSE
  )
}

check_coord_ranges <- function(con, project_id = NULL) {
  fields <- get_table_fields(con, "Sample_Env")
  needed <- c("plotnumber", "latitude", "longitude", "elevation")
  if (!has_cols(fields, needed)) return(data.frame())

  sql <- "SELECT plotnumber, latitude, longitude, elevation FROM Sample_Env"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  issues <- list()

  lat <- suppressWarnings(as.numeric(env$latitude))
  lon <- suppressWarnings(as.numeric(env$longitude))
  elev <- suppressWarnings(as.numeric(env$elevation))

  bad_lat <- which(!is.na(lat) & (lat < 48 | lat > 60))
  if (length(bad_lat) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "range_lat",
      table = "Sample_Env",
      column = "latitude",
      plotnumber = env$plotnumber[bad_lat],
      details = "Latitude out of range",
      stringsAsFactors = FALSE
    )
  }

  bad_lon <- which(!is.na(lon) & (lon < -140 | lon > -114))
  if (length(bad_lon) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "range_lon",
      table = "Sample_Env",
      column = "longitude",
      plotnumber = env$plotnumber[bad_lon],
      details = "Longitude out of range",
      stringsAsFactors = FALSE
    )
  }

  bad_elev <- which(!is.na(elev) & (elev < 0 | elev > 4000))
  if (length(bad_elev) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "range_elev",
      table = "Sample_Env",
      column = "elevation",
      plotnumber = env$plotnumber[bad_elev],
      details = "Elevation out of range",
      stringsAsFactors = FALSE
    )
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

check_slope_aspect_ranges <- function(con, project_id = NULL) {
  fields <- get_table_fields(con, "Sample_Env")
  needed <- c("plotnumber", "slopegradient", "aspect")
  if (!has_cols(fields, needed)) return(data.frame())

  sql <- "SELECT plotnumber, slopegradient, aspect FROM Sample_Env"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  issues <- list()
  slope <- suppressWarnings(as.numeric(env$slopegradient))
  aspect <- suppressWarnings(as.numeric(env$aspect))

  bad_slope <- which(!is.na(slope) & (slope < 0 | slope > 100))
  if (length(bad_slope) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "range_slope",
      table = "Sample_Env",
      column = "slopegradient",
      plotnumber = env$plotnumber[bad_slope],
      details = "Slope out of range",
      stringsAsFactors = FALSE
    )
  }

  bad_aspect <- which(!is.na(aspect) & (aspect < 0 | aspect > 360))
  if (length(bad_aspect) > 0) {
    issues[[length(issues) + 1]] <- data.frame(
      rule = "range_aspect",
      table = "Sample_Env",
      column = "aspect",
      plotnumber = env$plotnumber[bad_aspect],
      details = "Aspect out of range",
      stringsAsFactors = FALSE
    )
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

check_non_negative_fields <- function(con, project_id = NULL) {
  fields <- get_table_fields(con, "Sample_Env")
  targets <- c(
    "rootrestrictingdepth",
    "rootingdepth",
    "seepagedepth",
    "sv_soildepth",
    "sv_gleyingmottlingcm",
    "sv_watertablecm",
    "sv_ahorizondepth",
    "activelayerdepth"
  )
  present <- intersect(targets, fields)
  if (length(present) == 0) return(data.frame())

  select_cols <- paste(c("plotnumber", present), collapse = ", ")
  sql <- sprintf("SELECT %s FROM Sample_Env", select_cols)
  params <- list()
  if (!is.null(project_id) && "projectid" %in% fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  issues <- list()
  for (col_name in present) {
    values <- suppressWarnings(as.numeric(env[[col_name]]))
    bad <- which(!is.na(values) & values < 0)
    if (length(bad) > 0) {
      issues[[length(issues) + 1]] <- data.frame(
        rule = paste0("range_nonneg_", col_name),
        table = "Sample_Env",
        column = col_name,
        plotnumber = env$plotnumber[bad],
        details = "Value must be non-negative",
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

check_cover_ranges <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "vw_USysAllVeg")) == 0) return(data.frame())

  veg_fields <- get_table_fields(con, "vw_USysAllVeg")
  plot_col <- if ("plotnumber" %in% veg_fields) "plotnumber" else if ("PlotNumber" %in% veg_fields) "PlotNumber" else NULL
  cover_col <- if ("cover_value" %in% veg_fields) "cover_value" else if ("cover" %in% veg_fields) "cover" else if ("Cover" %in% veg_fields) "Cover" else NULL

  if (is.null(plot_col) || is.null(cover_col)) return(data.frame())

  sql <- sprintf("SELECT %s AS plotnumber, %s AS cover_value FROM vw_USysAllVeg", plot_col, cover_col)
  params <- list()
  if (!is.null(project_id)) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  veg <- DBI::dbGetQuery(con, sql, params)
  if (nrow(veg) == 0) return(data.frame())

  suppressWarnings({
    cover_num <- as.numeric(veg$cover_value)
  })

  bad <- which(!is.na(cover_num) & (cover_num < 0 | cover_num > 100))
  if (length(bad) == 0) return(data.frame())

  data.frame(
    rule = "range_cover",
    table = "vw_USysAllVeg",
    column = "cover_value",
    plotnumber = veg$plotnumber[bad],
    details = "Cover out of range",
    stringsAsFactors = FALSE
  )
}

check_cover_codes <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "vw_USysAllVeg")) == 0) return(data.frame())

  veg_fields <- get_table_fields(con, "vw_USysAllVeg")
  plot_col <- if ("plotnumber" %in% veg_fields) "plotnumber" else if ("PlotNumber" %in% veg_fields) "PlotNumber" else NULL
  cover_col <- if ("cover_value" %in% veg_fields) "cover_value" else if ("cover" %in% veg_fields) "cover" else if ("Cover" %in% veg_fields) "Cover" else NULL

  if (is.null(plot_col) || is.null(cover_col)) return(data.frame())

  sql <- sprintf("SELECT %s AS plotnumber, %s AS cover_value FROM vw_USysAllVeg", plot_col, cover_col)
  params <- list()
  if (!is.null(project_id)) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  veg <- DBI::dbGetQuery(con, sql, params)
  if (nrow(veg) == 0) return(data.frame())

  cover_raw <- trimws(as.character(veg$cover_value))
  is_blank <- is.na(cover_raw) | cover_raw == ""
  suppressWarnings({
    cover_num <- as.numeric(cover_raw)
  })
  allowed_codes <- c("+", "r", "p")
  is_allowed_code <- tolower(cover_raw) %in% allowed_codes
  invalid <- which(!is_blank & is.na(cover_num) & !is_allowed_code)
  if (length(invalid) == 0) return(data.frame())

  data.frame(
    rule = "code_cover",
    table = "vw_USysAllVeg",
    column = "cover_value",
    plotnumber = veg$plotnumber[invalid],
    details = "Cover code not allowed",
    stringsAsFactors = FALSE
  )
}

check_table_list_values <- function(con, project_id = NULL) {
  if (length(get_table_fields(con, "lists.USysTableOfLists")) == 0 || length(get_table_fields(con, "Sample_Env")) == 0) {
    return(data.frame())
  }

  list_fields <- get_table_fields(con, "lists.USysTableOfLists")
  listname_col <- if ("listname" %in% list_fields) "listname" else if ("ListName" %in% list_fields) "ListName" else NULL
  item_col <- if ("item" %in% list_fields) "item" else if ("Item" %in% list_fields) "Item" else NULL

  if (is.null(listname_col) || is.null(item_col)) return(data.frame())

  env_fields <- get_table_fields(con, "Sample_Env")
  plot_col <- if ("plotnumber" %in% env_fields) "plotnumber" else if ("PlotNumber" %in% env_fields) "PlotNumber" else NULL
  project_col <- if ("projectid" %in% env_fields) "projectid" else if ("ProjectID" %in% env_fields) "ProjectID" else NULL
  if (is.null(plot_col)) return(data.frame())

  list_map <- c(
    mesoslopeposition = "MesoSlopePosition",
    surfaceshape = "SurfaceShape",
    moistureregime = "MoistureRegime",
    nutrientregime = "NutrientRegime",
    structuralstage = "StructuralStage"
  )
  present_cols <- intersect(names(list_map), env_fields)
  if (length(present_cols) == 0) return(data.frame())

  select_cols <- paste(c(plot_col, present_cols), collapse = ", ")
  sql <- sprintf("SELECT %s FROM Sample_Env", select_cols)
  params <- list()
  if (!is.null(project_id) && !is.null(project_col)) {
    sql <- paste0(sql, " WHERE ", project_col, " = ?")
    params <- list(project_id)
  }

  env <- DBI::dbGetQuery(con, sql, params)
  if (nrow(env) == 0) return(data.frame())

  issues <- list()
  for (col_name in present_cols) {
    list_name <- list_map[[col_name]]
    list_sql <- sprintf("SELECT %s AS item FROM lists.USysTableOfLists WHERE %s = ?", item_col, listname_col)
    list_items <- DBI::dbGetQuery(con, list_sql, list(list_name))
    valid <- unique(list_items$item)

    values <- env[[col_name]]
    invalid_idx <- which(!is.na(values) & values != "" & !(values %in% valid))
    if (length(invalid_idx) > 0) {
      issues[[length(issues) + 1]] <- data.frame(
        rule = paste0("fk_list_", col_name),
        table = "Sample_Env",
        column = col_name,
        plotnumber = env[[plot_col]][invalid_idx],
        details = paste0("Invalid value for list ", list_name),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(issues) == 0) return(data.frame())
  do.call(rbind, issues)
}

run_compliance_checks <- function(con, project_id = NULL) {
  checks <- list(
    check_required_fields(con, project_id),
    check_species_fk(con, project_id),
    check_zone_fk(con, project_id),
    check_coord_ranges(con, project_id),
    check_slope_aspect_ranges(con, project_id),
    check_non_negative_fields(con, project_id),
    check_cover_ranges(con, project_id),
    check_cover_codes(con, project_id),
    check_table_list_values(con, project_id),
    check_duplicate_plots(con, project_id),
    check_duplicate_veg(con, project_id)
  )

  details <- do.call(rbind, Filter(function(x) nrow(x) > 0, checks))
  if (is.null(details)) {
    details <- data.frame()
  }

  summary <- if (nrow(details) == 0) {
    data.frame(rule = character(), count = integer())
  } else {
    aggregate(list(count = details$rule), by = list(rule = details$rule), FUN = length)
  }

  list(
    passed = nrow(details) == 0,
    summary_tibble = summary,
    detail_tibble = details
  )
}
