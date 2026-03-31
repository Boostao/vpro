# ============================================================
# Record Navigation Logic (Access record-bar parity)
# ============================================================
# Provides: refresh_recordset, collect_env_fields,
#           write_audit_trail, search_across_fields

# -- Fetch ordered PlotNumber vector from UsysEnv -----------------
# Mirrors Access Filtered_Env: INNER JOIN with SU table when CurrPlotlist is set.
refresh_recordset <- function(con, filter_expr = NULL) {
  proj <- config("Current", "CurrProject")
  su   <- config("Current", "CurrPlotlist")

  tbl <- tryCatch(
    as.character(db_tb(con, "Env", proj, prj = TRUE)),
    error = function(e) NULL
  )
  if (is.null(tbl)) return(character(0))

  # SU table: {CurrPlotlist}_SU in the {CurrPlotlist} database
  su_tbl <- if (!is.null(su) && nzchar(su)) {
    tryCatch(
      as.character(db_tb(con, paste0(su, "_SU"), su, prj = FALSE)),
      error = function(e) NULL
    )
  } else NULL

  if (!is.null(su_tbl)) {
    base_sql <- paste(
      "SELECT DISTINCT e.PlotNumber FROM", tbl, "e",
      "INNER JOIN", su_tbl, "su ON e.PlotNumber = su.PlotNumber",
      "WHERE su.PlotNumber IS NOT NULL"
    )
  } else {
    base_sql <- paste("SELECT DISTINCT PlotNumber FROM", tbl)
  }

  if (!is.null(filter_expr) && nzchar(trimws(filter_expr))) {
    sql <- paste("SELECT PlotNumber FROM (", base_sql, ") _rs WHERE", filter_expr)
  } else {
    sql <- base_sql
  }
  sql <- paste(sql, "ORDER BY PlotNumber")

  tryCatch(
    db_query(con, sql)$PlotNumber,
    error = function(e) character(0)
  )
}

# -- Collect current form input values into a named list ----------
# Returns list(field_name = current_value) using the same field
# names as populate_env_fields / the save handler.
collect_env_fields <- function(input, coord_fn) {
  coords <- coord_fn()
  list(
    plotnumber         = trimws(input$PlotNumber %||% ""),
    fieldnumber        = as_chr(input$FieldNumber),
    date               = as_chr(input$Date),
    sitesurveyor       = as_chr(input$SiteSurveyor),
    location           = as_chr(input$Location),
    latitude           = coords$lat,
    longitude          = coords$lon,
    utmeasting         = as_num(input$UTMEasting),
    utmnorthing        = as_num(input$UTMNorthing),
    utmzone            = as_chr(input$UTMZone),
    locationaccuracy   = as_chr(input$LocationAccuracy),
    ntsmapsheet        = as_chr(input$NtsMapSheet),
    airphotonum        = as_chr(input$AirPhotoNum),
    elevation          = as_num(input$Elevation),
    slopegradient      = as_num(input$SlopeGradient),
    aspect             = as_num(input$Aspect),
    mesoslopeposition  = as_chr(input$MesoSlopePosition),
    surfaceshape       = as_chr(input$SurfaceShape),
    moistureregime     = as_chr(input$MoistureRegime),
    nutrientregime     = as_chr(input$NutrientRegime),
    successionalstatus = as_chr(input$SuccessionalStatus),
    structuralstage    = as_chr(input$StructuralStage),
    ecosection         = as_chr(input$Ecosection),
    zone               = as_chr(input$Zone),
    subzone            = as_chr(input$SubZone),
    siteseries         = as_chr(input$SiteSeries),
    plotrepresenting   = as_chr(input$PlotRepresenting),
    mapunit            = as_chr(input$MapUnit),
    standage           = as_num(input$StandAge),
    sitenotes          = as_chr(input$SiteNotes),
    officenotes        = as_chr(input$OfficeNotes),
    soilsurveyor       = as_chr(input$SoilSurveyor),
    rootingdepth       = as_num(input$RootingDepth),
    rootrestrictingdepth = as_num(input$RootRestrictingDepth),
    seepagedepth       = as_num(input$SeepageDepth),
    photo              = as_chr(input$Photo),
    becsiteunit        = as_chr(input$BECSiteUnit),
    usersiteunit       = as_chr(input$UserSiteUnit),
    siteplotquality    = as_chr(input$SitePlotQuality),
    vegplotquality     = as_chr(input$VegPlotQuality),
    soilplotquality    = as_chr(input$SoilPlotQuality),
    substrateorganicmatter = as_num(input$SubstrateOrganicMatter),
    substratedecwood       = as_num(input$SubstrateDecWood),
    substratebedrock       = as_num(input$SubstrateBedRock),
    substraterocks         = as_num(input$SubstrateRocks),
    substratemineralsoil   = as_num(input$SubstrateMineralSoil),
    substratewater         = as_num(input$SubstrateWater),
    surfacetopographytype  = as_chr(input$SurfaceTopographyType),
    surfacetopographysize  = as_chr(input$SurfaceTopographySize),
    exposure1              = as_chr(input$Exposure1),
    exposure2              = as_chr(input$Exposure2),
    sitedisturbance1       = as_chr(input$SiteDisturbance1),
    sitedisturbance2       = as_chr(input$SiteDisturbance2),
    sitedisturbance3       = as_chr(input$SiteDisturbance3),
    StrataCoverTree        = as_num(input$StrataCoverTree),
    StrataCoverShrub       = as_num(input$StrataCoverShrub),
    StrataCoverHerb        = as_num(input$StrataCoverHerb),
    StrataCoverMoss        = as_num(input$StrataCoverMoss),
    vegnotes               = as_chr(input$VegNotes),
    realmclass             = as_chr(input$RealmClass),
    transdistrib           = as_chr(input$TransDistrib),
    fsregiondistrict       = as_chr(input$FSRegionDistrict),
    bedrockgeology1        = as_chr(input$BedrockGeology1),
    bedrockgeology2        = as_chr(input$BedrockGeology2),
    bedrockgeology3        = as_chr(input$BedrockGeology3),
    coarsefraglith1        = as_chr(input$CoarseFragLith1),
    coarsefraglith2        = as_chr(input$CoarseFragLith2),
    coarsefraglith3        = as_chr(input$CoarseFragLith3),
    soilclasssubgroup      = as_chr(input$SoilClassSubGroup),
    soilclassgroup         = as_chr(input$SoilClassGroup),
    humusform              = as_chr(input$HumusForm),
    humusformphase         = as_chr(input$HumusFormPhase),
    humusthickness         = as_num(input$HumusThickness),
    soildrainage           = as_chr(input$SoilDrainage),
    rootrestrictingtype    = as_chr(input$RootRestrictingType),
    rootzoneparticlesize   = as_chr(input$RootZoneParticleSize),
    watersource            = as_chr(input$WaterSource),
    floodingregimefreq     = as_chr(input$FloodingRegimeFreq),
    floodingregimeDur      = as_chr(input$FloodingRegimeDur),
    hydrogeoystem          = as_chr(input$HydroGeoSystem),
    hydrogeosubystem       = as_chr(input$HydroGeoSubSystem),
    terraintexturesurf     = as_chr(input$TerrainTextureSurf),
    surficialmaterialsurf  = as_chr(input$SurficialMaterialSurf),
    surfaceexpsurf         = as_chr(input$SurfaceExpSurf),
    geomorprosurf          = as_chr(input$GeoMorProSurf),
    terraintexturesubsurf  = as_chr(input$TerrainTextureSubSurf),
    surficialmaterialsubsurf = as_chr(input$SurficialMaterialSubSurf),
    surfaceexpsubsurf      = as_chr(input$SurfaceExpSubSurf),
    geomorprosubsurf       = as_chr(input$GeoMorProSubSurf),
    projectid              = as_chr(input$ProjectID),
    xcoord                 = as_num(input$XCoord),
    ycoord                 = as_num(input$YCoord),
    vegsurveyor            = as_chr(input$VegSurveyor),
    specieslistcomplete    = isTRUE(input$SpeciesListComplete),
    soilnotes              = as_chr(input$SoilNotes)
  )
}

# -- Detect dirty: compare current inputs to loaded env_row -------
# Returns named character vector of changed field names, or
# character(0) if clean.
detect_dirty_fields <- function(current_fields, env_row) {
  if (is.null(env_row)) return(names(current_fields))

  col <- function(nm) {
    idx <- match(tolower(nm), tolower(names(env_row)))
    if (is.na(idx)) NA else env_row[[idx]][[1]]
  }

  changed <- character(0)
  for (nm in names(current_fields)) {
    if (nm == "plotnumber") next
    new_val <- current_fields[[nm]]
    old_val <- col(nm)
    # Normalise NAs for comparison
    new_is_empty <- is.null(new_val) || (length(new_val) == 1 && (is.na(new_val) || !nzchar(trimws(as.character(new_val)))))
    old_is_empty <- is.null(old_val) || (length(old_val) == 1 && (is.na(old_val) || !nzchar(trimws(as.character(old_val)))))
    if (new_is_empty && old_is_empty) next
    if (new_is_empty != old_is_empty) {
      changed <- c(changed, nm)
      next
    }
    # Both non-empty: compare as character, normalising date/timestamp types
    fmt_val <- function(v) {
      if (inherits(v, c("POSIXct", "POSIXt", "Date"))) format(as.Date(v), "%Y-%m-%d")
      else trimws(as.character(v))
    }
    if (fmt_val(new_val) != fmt_val(old_val)) {
      changed <- c(changed, nm)
    }
  }
  changed
}

# -- Write audit trail (Access AuditTrail Me port) ----------------
# Compares current fields to env_row, writes one audit row per
# changed field, respecting AuditStrength (1/2/3).
write_audit_trail <- function(con, current_fields, env_row, plot_id) {
  audit_strength <- as.integer(config("Audit", "AuditStrength") %||% 1)
  project <- config("Current", "CurrProject")
  user <- config("Current", "User") %||% "unknown"

  col <- function(nm) {
    if (is.null(env_row)) return(NA)
    idx <- match(tolower(nm), tolower(names(env_row)))
    if (is.na(idx)) NA else env_row[[idx]][[1]]
  }

  audit_tbl <- tryCatch(
    as.character(db_tb(con, "Audit", project, prj = TRUE)),
    error = function(e) NULL
  )
  if (is.null(audit_tbl)) return(invisible(0L))

  n <- 0L
  for (nm in names(current_fields)) {
    if (nm == "plotnumber") next

    new_val <- current_fields[[nm]]
    old_val <- col(nm)

    new_is_empty <- is.null(new_val) || (length(new_val) == 1 && (is.na(new_val) || !nzchar(trimws(as.character(new_val)))))
    old_is_empty <- is.null(old_val) || (length(old_val) == 1 && (is.na(old_val) || !nzchar(trimws(as.character(old_val)))))

    should_log <- FALSE

    if (!old_is_empty && !new_is_empty) {
      # Edit: both present, value changed
      if (trimws(as.character(new_val)) != trimws(as.character(old_val))) {
        should_log <- (audit_strength >= 1)
      }
    } else if (old_is_empty && !new_is_empty) {
      # Add: was null, now has value
      should_log <- (audit_strength >= 2)
    } else if (!old_is_empty && new_is_empty) {
      # Delete: had value, now null
      should_log <- (audit_strength >= 3)
    }

    if (should_log) {
      tryCatch({
        db_run(con, paste0(
          "INSERT INTO ", audit_tbl,
          " (Project, \"User\", PlotNumber, \"Table\", EditField, EditWhen, BeforeEdit, AfterEdit)",
          " VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ), params = list(
          project,
          user,
          plot_id,
          "Env",
          nm,
          format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          if (old_is_empty) NA_character_ else as.character(old_val),
          if (new_is_empty) NA_character_ else as.character(new_val)
        ))
        n <- n + 1L
      }, error = function(e) NULL)
    }
  }
  invisible(n)
}

# -- Search across fields in the recordset ------------------------
# Returns a list: $plot (PlotNumber of first hit), $field (field name),
# or NULL if no match.
# `start_plot` is the PlotNumber to start searching AFTER (F3 = next).
search_across_fields <- function(con, recordset, query, start_plot = NULL) {
  if (!length(recordset) || !nzchar(trimws(query))) return(NULL)
  query_lower <- tolower(trimws(query))

  tbl <- tryCatch(
    as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE)),
    error = function(e) NULL
  )
  if (is.null(tbl)) return(NULL)

  # Determine start position (search wraps around)
  start_idx <- if (!is.null(start_plot)) {
    pos <- match(start_plot, recordset)
    if (is.na(pos)) 1L else pos + 1L
  } else {
    1L
  }

  # Reorder recordset: from start_idx to end, then wrap to beginning
  n <- length(recordset)
  order <- c(seq_len(n)[start_idx:n], if (start_idx > 1) seq_len(start_idx - 1L) else integer(0))

  # Search in batches of 50 for efficiency
  batch_size <- 50L
  for (batch_start in seq(1, length(order), by = batch_size)) {
    batch_end <- min(batch_start + batch_size - 1L, length(order))
    batch_plots <- recordset[order[batch_start:batch_end]]

    placeholders <- paste(rep("?", length(batch_plots)), collapse = ", ")
    rows <- tryCatch(
      db_query(con, paste("SELECT * FROM", tbl, "WHERE PlotNumber IN (", placeholders, ")"),
        params = as.list(batch_plots)),
      error = function(e) data.frame()
    )
    if (!nrow(rows)) next

    # Search each row in recordset order
    for (plot in batch_plots) {
      row_idx <- which(tolower(trimws(rows$PlotNumber)) == tolower(trimws(plot)))
      if (!length(row_idx)) next
      row <- rows[row_idx[1], , drop = FALSE]
      for (col_name in names(row)) {
        val <- row[[col_name]]
        if (is.null(val) || is.na(val)) next
        if (grepl(query_lower, tolower(as.character(val)), fixed = TRUE)) {
          return(list(plot = plot, field = col_name))
        }
      }
    }
  }
  NULL
}
