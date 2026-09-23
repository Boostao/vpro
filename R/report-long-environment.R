# Long environment report ---------------------------------------------------

vpro_report_long_environment_fields <- function() {
  spec <- list(
    c("Env", "PlotNumber", "Plot"),
    c("Env", "FieldNumber", "Site Number"),
    c("Env", "FSRegionDistrict", "FSRegionDistrict"),
    c("Admin", "SitePlotQuality", "Plot Quality"),
    c("heading", NA, "GENERAL LOCATION"),
    c("Env", "Zone", "Biogeoclimatic Zone"),
    c("Env", "SubZone", "SubZone"),
    c("Env", "SiteSeries", "Site Series"),
    c("Admin", "UserSiteUnit", "Assigned Site Unit"),
    c("Env", "Location", "Location"),
    c("Env", "NtsMapSheet", "NTS Map Sheet"),
    c("Env", "Longitude", "Longitude"),
    c("Env", "Latitude", "Latitude"),
    c("heading", NA, "SITE"),
    c("Env", "Elevation", "Elevation(m)"),
    c("Env", "SlopeGradient", "Slope Gradient(%)"),
    c("Env", "Aspect", "Aspect (degrees)"),
    c("Env", "MesoSlopePosition", "Meso Slope Position"),
    c("Env", "SurfaceShape", "Surface Shape"),
    c("Env", "SurfaceTopographyType", "Surface Topography Type"),
    c("Env", "MoistureRegime", "Moisture Regime"),
    c("Env", "NutrientRegime", "Nutrient Regime"),
    c("Env", "Exposure1", "Exposure1"),
    c("Env", "Exposure2", "Exposure2"),
    c("Env", "SiteDisturbance1", "Site Disturbance 1"),
    c("Env", "SiteDisturbance2", "Site Disturbance 2"),
    c("Env", "SiteDisturbance3", "Site Disturbance 3"),
    c("Env", "SubstrateDecWood", "Substrate Decaying Wood(%)"),
    c("Env", "SubstrateBedRock", "Substrate Bedrock(%)"),
    c("Env", "SubstrateRocks", "Substrate Rocks(%)"),
    c("Env", "SubstrateMineralSoil", "Substrate Mineral Soil(%)"),
    c("Env", "SubstrateOrganicMatter", "Substrate Organic Matter(%)"),
    c("Env", "SubstrateWater", "Substrate Water(%)"),
    c("heading", NA, "SOIL"),
    c("Env", "SoilClassGroup", "Soil Great Group"),
    c("Env", "SoilClassSubGroup", "Soil Subgroup"),
    c("Env", "BedrockGeology1", "Bedrock Geology 1"),
    c("Env", "BedrockGeology2", "Bedrock Geology 2"),
    c("Env", "BedrockGeology3", "Bedrock Geology3"),
    c("Env", "CoarseFragLith1", "Coarse Frag Lith 1"),
    c("Env", "CoarseFragLith2", "Coarse Frag Lith2"),
    c("Env", "CoarseFragLith3", "Coarse Frag Lith3"),
    c("Env", "TerrainTextureSurf", "Terrain Texture Surface"),
    c("Env", "TerrainTextureSubSurf", "Terrain Texture Sub Surface"),
    c("Env", "SurficialMaterialSurf", "Surficial Material Surface"),
    c("Env", "SurficialMaterialSubSurf", "Surficial Material Sub Surface"),
    c("Env", "SurfaceExpSurf", "Surface Expression Surface"),
    c("Env", "SurfaceExpSubSurf", "Surface Expression Sub Surface"),
    c("Env", "GeoMorProSurf", "Geomorphological Process Surface"),
    c("Env", "GeoMorProSubSurf", "Geomorphological Process Sub Surface"),
    c("Env", "RootZoneParticleSize", "Root Zone Particle Size"),
    c("Env", "RootingDepth", "Rooting Depth(cm)"),
    c("Env", "RootRestrictingType", "RootRestrictingType"),
    c("Env", "RootRestrictingDepth", "Root Restricting Depth(cm)"),
    c("Env", "SeepageDepth", "Seepage Depth(cm)"),
    c("Env", "SoilDrainage", "Soil Drainage"),
    c("Env", "HumusForm", "Humus Form (MOF 81)"),
    c("Env", "HumusFormPhase", "Humus Form Phase"),
    c("Admin", "HumusThickness", "Humus Thickness"),
    c("heading", NA, "VEGETATION"),
    c("Env", "StandAge", "Stand Age"),
    c("Env", "SuccessionalStatus", "Successional Status"),
    c("Env", "StructuralStage", "Structural Stage"),
    c("Env", "StrataCoverTree", "Strata Cover Tree(%)"),
    c("Env", "StrataCoverShrub", "Strata Cover Shrub(%)"),
    c("Env", "StrataCoverHerb", "Strata Cover Herb(%)"),
    c("Env", "StrataCoverMoss", "Strata Cover Moss(%)"),
    c("heading", NA, "OTHER"),
    c("Env", "HydroGeoSystem", "System"),
    c("Env", "HydroGeoSubSystem", "Subsystem"),
    c("Env", "WaterSource", "Water Source"),
    c("Env", "FloodingRegimeFreq", "Flood Frequency")
  )
  result <- as.data.frame(do.call(rbind, spec), stringsAsFactors = FALSE)
  names(result) <- c("source", "field", "label")
  result$position <- seq_len(nrow(result))
  result$heading <- result$source == "heading"
  result$field[result$heading] <- NA_character_
  result <- result[, c("position", "source", "field", "label", "heading")]
  rownames(result) <- NULL
  result
}

vpro_report_long_environment_check_fields <- function(con, relation, required, description) {
  fields <- names(DBI::dbGetQuery(con, paste("SELECT * FROM", relation, "LIMIT 0")))
  missing <- setdiff(required, fields)
  if (length(missing) > 0L) {
    stop("VPRO long environment report ", description, " is missing fields: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

vpro_report_long_environment_duplicates <- function(con, relation, key, description) {
  key_sql <- DBI::dbQuoteIdentifier(con, key)
  duplicate <- DBI::dbGetQuery(con, paste("SELECT", key_sql, "FROM", relation, "GROUP BY", key_sql, "HAVING COUNT(*) > 1 LIMIT 1"))
  if (nrow(duplicate) > 0L) {
    stop("VPRO long environment report cannot safely use ambiguous duplicate ", description, " keys.", call. = FALSE)
  }
}

#' Return bounded long-environment data for the active site unit
#'
#' Implements the data contract derived from `EnvReport`'s live Access query.
#' It begins with physical active-SU membership, preserves orphan memberships,
#' and reads physical Env/Admin tables rather than the inner-joined `USysEnv`
#' view. It returns data only: it does not alter source databases, create Excel
#' files, or change existing report/UI behavior.
#'
#' @param context A VPRO project context with an active project and active SU.
#' @param reference_path SQLite reference database containing
#'   `MasterSiteUnitList`. Defaults to bundled `VLists.db`.
#'
#' @return A list with `plots`, `units`, `names`, `fields`, and `diagnostics`.
#'   `plots` has one row per unique SU membership: `SiteUnit`, membership
#'   `PlotNumber`, `status` (`ok`, `missing_env`, or `missing_admin`),
#'   `duplicate_membership_count`, and projected report columns. Projected `Plot`
#'   and all other report columns are missing for unmatched Env or Admin rows.
#'   `units` has one row per site unit with `title` and `name_status` (`ok`,
#'   `missing_unit_name`, or `conflicting_unit_names`). `names` contains sorted
#'   candidate-name vectors. `fields` gives ordered labels and heading metadata.
#'   `diagnostics` counts unique eligible memberships and excess duplicate rows.
#'   Unlike Access's `First()` lookup, ambiguous names never select an arbitrary
#'   title; the unit code is used instead. Sorting and orphan labels are deliberate
#'   modernizations, not Excel-layout parity.
#' @export
vpro_report_long_environment <- function(
  context,
  reference_path = vpro_bundled_file("extdata", "VLists.db")
) {
  vpro_plot_active(context)
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for the long environment report.", call. = FALSE)
  }
  if (!is.character(reference_path) || length(reference_path) != 1L || is.na(reference_path) || !file.exists(reference_path) || dir.exists(reference_path)) {
    stop("VPRO long environment reference database does not exist.", call. = FALSE)
  }

  fields <- vpro_report_long_environment_fields()
  env <- vpro_project_relation(context, context$active, "Env")
  admin <- vpro_project_relation(context, context$active, "Admin")
  su <- vpro_su_relation(context, context$active_su)
  env_fields <- fields$field[fields$source == "Env"]
  admin_fields <- fields$field[fields$source == "Admin"]
  vpro_report_long_environment_check_fields(context$con, env, unique(c("PlotNumber", env_fields)), "Env table")
  vpro_report_long_environment_check_fields(context$con, admin, unique(c("Plot", admin_fields)), "Admin table")
  vpro_report_long_environment_check_fields(context$con, su, c("PlotNumber", "SiteUnit"), "SU table")
  vpro_report_long_environment_duplicates(context$con, env, "PlotNumber", "Env")
  vpro_report_long_environment_duplicates(context$con, admin, "Plot", "Admin")

  reference <- DBI::dbConnect(RSQLite::SQLite(), reference_path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(reference), add = TRUE)
  if (!DBI::dbExistsTable(reference, "MasterSiteUnitList")) {
    stop("VPRO master site-unit table does not exist: MasterSiteUnitList", call. = FALSE)
  }
  reference_fields <- DBI::dbListFields(reference, "MasterSiteUnitList")
  missing_reference <- setdiff(c("SiteSeries", "SiteSeriesLongName"), reference_fields)
  if (length(missing_reference) > 0L) {
    stop("VPRO master site-unit table is missing fields: ", paste(missing_reference, collapse = ", "), call. = FALSE)
  }

  values <- fields[!fields$heading, , drop = FALSE]
  select_values <- vapply(
    seq_len(nrow(values)),
    function(i) {
      item <- values[i, ]
      source <- if (identical(item$source, "Env")) "env" else "admin"
      paste0(
        'CASE WHEN env."PlotNumber" IS NOT NULL AND admin."Plot" IS NOT NULL THEN ',
        source,
        ".",
        DBI::dbQuoteIdentifier(context$con, item$field),
        " ELSE NULL END AS ",
        DBI::dbQuoteIdentifier(context$con, item$label)
      )
    },
    character(1)
  )
  plots_sql <- paste(
    "WITH membership AS (SELECT \"SiteUnit\", \"PlotNumber\", COUNT(*) AS \"duplicate_membership_count\" FROM",
    su,
    "WHERE \"SiteUnit\" IS NOT NULL AND \"PlotNumber\" IS NOT NULL GROUP BY \"SiteUnit\", \"PlotNumber\")",
    "SELECT membership.\"SiteUnit\", membership.\"PlotNumber\",",
    "CASE WHEN env.\"PlotNumber\" IS NULL THEN 'missing_env' WHEN admin.\"Plot\" IS NULL THEN 'missing_admin' ELSE 'ok' END AS \"status\",",
    "membership.\"duplicate_membership_count\",",
    paste(select_values, collapse = ", "),
    "FROM membership LEFT JOIN",
    env,
    "AS env ON membership.\"PlotNumber\" = env.\"PlotNumber\" LEFT JOIN",
    admin,
    "AS admin ON membership.\"PlotNumber\" = admin.\"Plot\""
  )
  plots <- DBI::dbGetQuery(context$con, plots_sql)
  plots$duplicate_membership_count <- as.integer(plots$duplicate_membership_count)
  if (nrow(plots) > 0L) {
    plots <- plots[order(tolower(plots$SiteUnit), plots$SiteUnit, tolower(plots$PlotNumber), plots$PlotNumber), , drop = FALSE]
  }

  master <- DBI::dbGetQuery(reference, 'SELECT "SiteSeries", "SiteSeriesLongName" FROM "MasterSiteUnitList"')
  unit_codes <- unique(plots$SiteUnit)
  candidates <- lapply(unit_codes, function(unit) {
    matching <- !is.na(master$SiteSeries) & master$SiteSeries == unit & !is.na(master$SiteSeriesLongName) & nzchar(master$SiteSeriesLongName)
    sort(unique(master$SiteSeriesLongName[matching]))
  })
  name_status <- vapply(
    candidates,
    function(x) {
      if (length(x) == 1L) {
        "ok"
      } else if (length(x) == 0L) {
        "missing_unit_name"
      } else {
        "conflicting_unit_names"
      }
    },
    character(1)
  )
  titles <- vapply(seq_along(unit_codes), function(i) if (identical(name_status[[i]], "ok")) candidates[[i]][[1L]] else unit_codes[[i]], character(1))
  units <- data.frame(SiteUnit = unit_codes, title = titles, name_status = name_status, stringsAsFactors = FALSE)
  names <- data.frame(SiteUnit = unit_codes, candidate_names = I(candidates), stringsAsFactors = FALSE)
  if (nrow(units) > 0L) {
    order_units <- order(tolower(units$SiteUnit), units$SiteUnit)
    units <- units[order_units, , drop = FALSE]
    names <- names[order_units, , drop = FALSE]
  }
  rownames(units) <- NULL
  rownames(names) <- NULL
  list(
    plots = plots,
    units = units,
    names = names,
    fields = fields,
    diagnostics = list(
      eligible_memberships = nrow(plots),
      duplicate_membership_rows = sum(pmax(plots$duplicate_membership_count - 1L, 0L))
    )
  )
}
