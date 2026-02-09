# Compliance checks for core data integrity

get_table_fields <- function(con, table_name) {
  if (!DBI::dbExistsTable(con, table_name)) return(character())
  DBI::dbListFields(con, table_name)
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
  if (!DBI::dbExistsTable(con, "Sample_Veg") || !DBI::dbExistsTable(con, "lists.SppList")) {
    return(data.frame())
  }

  veg_fields <- get_table_fields(con, "Sample_Veg")
  if (!has_cols(veg_fields, c("plotnumber", "species"))) return(data.frame())

  sql <- "SELECT plotnumber, species FROM Sample_Veg"
  params <- list()
  if (!is.null(project_id) && "projectid" %in% veg_fields) {
    sql <- paste0(sql, " WHERE projectid = ?")
    params <- list(project_id)
  }

  veg <- DBI::dbGetQuery(con, sql, params)
  if (nrow(veg) == 0) return(data.frame())

  spp <- DBI::dbGetQuery(con, "SELECT code FROM lists.SppList")
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
  if (!DBI::dbExistsTable(con, "Sample_Env") || !DBI::dbExistsTable(con, "lists.USysZoneList")) {
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
  if (!DBI::dbExistsTable(con, "vw_USysAllVeg")) return(data.frame())

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

  bad_lat <- which(!is.na(env$latitude) & (env$latitude < 48 | env$latitude > 60))
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

  bad_lon <- which(!is.na(env$longitude) & (env$longitude < -140 | env$longitude > -114))
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

  bad_elev <- which(!is.na(env$elevation) & (env$elevation < 0 | env$elevation > 4000))
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

check_cover_ranges <- function(con, project_id = NULL) {
  if (!DBI::dbExistsTable(con, "vw_USysAllVeg")) return(data.frame())

  sql <- "SELECT plotnumber, cover_value FROM vw_USysAllVeg"
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

run_compliance_checks <- function(con, project_id = NULL) {
  checks <- list(
    check_required_fields(con, project_id),
    check_species_fk(con, project_id),
    check_zone_fk(con, project_id),
    check_coord_ranges(con, project_id),
    check_cover_ranges(con, project_id),
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
