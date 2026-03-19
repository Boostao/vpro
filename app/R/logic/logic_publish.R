# Publish pipeline helpers

# =============================================================================
# Local (offline-first) publication pipeline for BEC Map Explorer
#
# Contract (data/published/README.md):
#   - <project_id>_environment.rds
#   - <project_id>_vegetation.rds
#   - <project_id>_metadata.rds
#
# This pipeline is intentionally self-contained and does not require Postgres.
# =============================================================================

publish_ci_col <- function(cols, target) {
  if (is.null(cols) || length(cols) == 0) return(NULL)
  idx <- which(tolower(cols) == tolower(target))
  if (length(idx) == 0) return(NULL)
  cols[idx[1]]
}

publish_resolve_path <- function(path) {
  if (requireNamespace("here", quietly = TRUE)) {
    parts <- strsplit(path, "/", fixed = TRUE)[[1]]
    return(do.call(here::here, as.list(parts)))
  }
  path
}

publish_db_has <- function(con, table_name) {
  tryCatch(DBI::dbExistsTable(con, table_name), error = function(e) FALSE)
}

publish_read_project_metadata <- function(con, project_id, is_public = TRUE, description = NULL) {
  meta <- NULL

  # 1) Main app table
  if (publish_db_has(con, "USysProjectMetadata")) {
    cols <- DBI::dbListFields(con, "USysProjectMetadata")
    id_col <- publish_ci_col(cols, "projectid") %||% publish_ci_col(cols, "project_id")
    title_col <- publish_ci_col(cols, "projecttitle") %||% publish_ci_col(cols, "project_name")
    public_col <- publish_ci_col(cols, "ispublic")
    desc_col <- publish_ci_col(cols, "description") %||% publish_ci_col(cols, "projectdescription")
    zone_col <- publish_ci_col(cols, "beczone") %||% publish_ci_col(cols, "primary_bec_zone")

    if (!is.null(id_col)) {
      sql <- sprintf(
        "SELECT %s AS project_id%s%s%s%s FROM USysProjectMetadata WHERE %s = ? LIMIT 1",
        id_col,
        if (!is.null(title_col)) sprintf(", %s AS project_name", title_col) else ", NULL AS project_name",
        if (!is.null(public_col)) sprintf(", %s AS is_public_raw", public_col) else ", NULL AS is_public_raw",
        if (!is.null(zone_col)) sprintf(", %s AS primary_bec_zone", zone_col) else ", NULL AS primary_bec_zone",
        if (!is.null(desc_col)) sprintf(", %s AS description_raw", desc_col) else ", NULL AS description_raw",
        id_col
      )
      meta <- tryCatch(DBI::dbGetQuery(con, sql, list(project_id)), error = function(e) NULL)
    }
  }

  # 2) Attached metadata DB (older pipeline)
  if (is.null(meta) || nrow(meta) == 0) {
    if (publish_db_has(con, DBI::Id(schema = "metadata", table = "tbl_Projects"))) {
      meta <- tryCatch(
        DBI::dbGetQuery(
          con,
          paste(
            "SELECT",
            "projectid AS project_id,",
            "projecttitle AS project_name,",
            "CASE WHEN ispublic = 'True' THEN TRUE ELSE FALSE END AS is_public_raw,",
            "beczone AS primary_bec_zone,",
            "description AS description_raw",
            "FROM metadata.tbl_Projects WHERE projectid = ? LIMIT 1"
          ),
          list(project_id)
        ),
        error = function(e) NULL
      )
    }
  }

  # 3) Fallback minimal metadata
  if (is.null(meta) || nrow(meta) == 0) {
    meta <- data.frame(
      project_id = as.character(project_id),
      project_name = as.character(project_id),
      is_public_raw = NA,
      primary_bec_zone = NA_character_,
      description_raw = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  is_public_val <- if (!is.null(meta$is_public_raw) && !is.na(meta$is_public_raw[1])) {
    as.logical(meta$is_public_raw[1])
  } else {
    as.logical(is_public)
  }
  desc_val <- if (!is.null(description) && nzchar(trimws(as.character(description)))) {
    as.character(description)
  } else if (!is.null(meta$description_raw) && !is.na(meta$description_raw[1]) && nzchar(trimws(as.character(meta$description_raw[1])))) {
    as.character(meta$description_raw[1])
  } else {
    "Published dataset"
  }

  data.frame(
    project_id = as.character(meta$project_id[1] %||% project_id),
    project_name = as.character(meta$project_name[1] %||% project_id),
    is_public = isTRUE(is_public_val),
    primary_bec_zone = as.character(meta$primary_bec_zone[1]),
    description = desc_val,
    stringsAsFactors = FALSE
  )
}

publish_extract_environment <- function(con, project_id) {
  if (!publish_db_has(con, "Env")) {
    stop("Env table not found; cannot publish project dataset.")
  }

  env_cols <- DBI::dbListFields(con, "Env")
  plot_col <- publish_ci_col(env_cols, "plotnumber") %||% publish_ci_col(env_cols, "plot_number")
  proj_col <- publish_ci_col(env_cols, "projectid") %||% publish_ci_col(env_cols, "project_id")
  date_col <- publish_ci_col(env_cols, "date_sampled") %||% publish_ci_col(env_cols, "date") %||% publish_ci_col(env_cols, "survey_date")
  lat_col <- publish_ci_col(env_cols, "latitude")
  lon_col <- publish_ci_col(env_cols, "longitude")
  zone_col <- publish_ci_col(env_cols, "bec_zone") %||% publish_ci_col(env_cols, "zone")
  subzone_col <- publish_ci_col(env_cols, "bec_subzone") %||% publish_ci_col(env_cols, "subzone")
  ss_col <- publish_ci_col(env_cols, "bec_site_series") %||% publish_ci_col(env_cols, "siteseries") %||% publish_ci_col(env_cols, "site_series")
  loc_col <- publish_ci_col(env_cols, "_location") %||% publish_ci_col(env_cols, "location")

  if (is.null(plot_col) || is.null(proj_col) || is.null(lat_col) || is.null(lon_col)) {
    stop("Env missing required columns for publishing (plotnumber/projectid/latitude/longitude).")
  }

  # Optional quality from SU
  quality_sql <- NULL
  if (publish_db_has(con, "SU")) {
    su_cols <- DBI::dbListFields(con, "SU")
    su_plot_col <- publish_ci_col(su_cols, "plotnumber") %||% publish_ci_col(su_cols, "plot_number")
    qual_col <- publish_ci_col(su_cols, "dataquality") %||% publish_ci_col(su_cols, "data_quality")
    if (!is.null(su_plot_col) && !is.null(qual_col)) {
      quality_sql <- sprintf("LEFT JOIN SU s ON e.%s = s.%s", plot_col, su_plot_col)
      quality_sel <- sprintf(", s.%s AS data_quality", qual_col)
    } else {
      quality_sel <- ", NULL AS data_quality"
    }
  } else {
    quality_sel <- ", NULL AS data_quality"
  }

  sel <- paste(
    sprintf("e.%s AS plotnumber", plot_col),
    if (!is.null(date_col)) sprintf(", e.%s AS date_sampled", date_col) else ", NULL AS date_sampled",
    sprintf(", e.%s AS latitude", lat_col),
    sprintf(", e.%s AS longitude", lon_col),
    if (!is.null(zone_col)) sprintf(", e.%s AS bec_zone", zone_col) else ", NULL AS bec_zone",
    if (!is.null(subzone_col)) sprintf(", e.%s AS bec_subzone", subzone_col) else ", NULL AS bec_subzone",
    if (!is.null(ss_col)) sprintf(", e.%s AS bec_site_series", ss_col) else ", NULL AS bec_site_series",
    if (!is.null(loc_col)) sprintf(", e.%s AS _location", loc_col) else ", NULL AS _location",
    quality_sel
  )

  sql <- paste(
    "SELECT",
    sel,
    "FROM Env e",
    quality_sql %||% "",
    sprintf("WHERE e.%s = ?", proj_col)
  )

  DBI::dbGetQuery(con, sql, list(project_id))
}

publish_extract_vegetation <- function(con, project_id) {
  if (!publish_db_has(con, "vw_USysAllVeg")) {
    # If the view doesn't exist, fallback to Veg if present.
    if (!publish_db_has(con, "Veg")) {
      return(data.frame(plot_id = character(0), species_code = character(0), layer = character(0), cover = character(0)))
    }
    veg_cols <- DBI::dbListFields(con, "Veg")
    plot_col <- publish_ci_col(veg_cols, "plotnumber") %||% publish_ci_col(veg_cols, "plot_number")
    spp_col <- publish_ci_col(veg_cols, "species") %||% publish_ci_col(veg_cols, "species_code")
    layer_col <- publish_ci_col(veg_cols, "layer") %||% publish_ci_col(veg_cols, "layer_code")
    cover_col <- publish_ci_col(veg_cols, "cover") %||% publish_ci_col(veg_cols, "cover_percent") %||% publish_ci_col(veg_cols, "cover1")
    proj_col <- publish_ci_col(veg_cols, "projectid") %||% publish_ci_col(veg_cols, "project_id")

    if (is.null(plot_col) || is.null(spp_col) || is.null(layer_col) || is.null(proj_col)) {
      return(data.frame(plot_id = character(0), species_code = character(0), layer = character(0), cover = character(0)))
    }

    sql <- paste(
      "SELECT",
      sprintf("%s AS plot_id, %s AS species_code, %s AS layer, %s AS cover", plot_col, spp_col, layer_col, cover_col %||% "NULL"),
      "FROM Veg",
      sprintf("WHERE %s = ? AND %s IS NOT NULL", proj_col, spp_col)
    )
    return(DBI::dbGetQuery(con, sql, list(project_id)))
  }

  vcols <- DBI::dbListFields(con, "vw_USysAllVeg")
  plot_col <- publish_ci_col(vcols, "plotnumber") %||% publish_ci_col(vcols, "plot_id")
  proj_col <- publish_ci_col(vcols, "projectid") %||% publish_ci_col(vcols, "project_id")
  spp_col <- publish_ci_col(vcols, "code") %||% publish_ci_col(vcols, "species_code") %||% publish_ci_col(vcols, "species")
  layer_col <- publish_ci_col(vcols, "layer") %||% publish_ci_col(vcols, "mylayer")
  cover_col <- publish_ci_col(vcols, "cover")

  if (is.null(plot_col) || is.null(proj_col) || is.null(spp_col) || is.null(layer_col) || is.null(cover_col)) {
    stop("vw_USysAllVeg missing required columns for publishing.")
  }

  sql <- paste(
    "SELECT",
    sprintf("%s AS plot_id, %s AS species_code, %s AS layer, %s AS cover", plot_col, spp_col, layer_col, cover_col),
    "FROM vw_USysAllVeg",
    sprintf("WHERE %s = ? AND %s IS NOT NULL", proj_col, spp_col)
  )
  DBI::dbGetQuery(con, sql, list(project_id))
}

validate_for_publishing <- function(con, project_id) {
  # Base compliance suite (can be empty if schema differs)
  compliance <- tryCatch(run_compliance_checks(con, project_id = project_id), error = function(e) NULL)
  details <- if (!is.null(compliance)) compliance$detail_tibble else data.frame()

  # Publish-specific: env must have non-null/non-zero coordinates
  env <- tryCatch(publish_extract_environment(con, project_id), error = function(e) NULL)
  if (is.null(env) || nrow(env) == 0) {
    details <- rbind(details, data.frame(
      rule = "publish_no_env",
      table = "Env",
      column = "plotnumber",
      plotnumber = NA,
      details = "No environment rows found for project",
      stringsAsFactors = FALSE
    ))
  } else {
    lat <- suppressWarnings(as.numeric(env$latitude))
    lon <- suppressWarnings(as.numeric(env$longitude))
    bad <- which(is.na(lat) | is.na(lon) | lat == 0 | lon == 0)
    if (length(bad) > 0) {
      details <- rbind(details, data.frame(
        rule = "publish_bad_coords",
        table = "Env",
        column = "latitude/longitude",
        plotnumber = env$plotnumber[bad],
        details = "Missing or zero coordinates",
        stringsAsFactors = FALSE
      ))
    }
  }

  list(
    passed = nrow(details) == 0,
    detail_tibble = details
  )
}

transform_for_publication <- function(env,
                                      veg,
                                      meta,
                                      anonymize = FALSE,
                                      coordinate_round_digits = 5,
                                      drop_internal_fields = TRUE) {
  env2 <- env
  veg2 <- veg
  meta2 <- meta

  if (!is.null(env2) && nrow(env2) > 0) {
    env2$latitude <- suppressWarnings(as.numeric(env2$latitude))
    env2$longitude <- suppressWarnings(as.numeric(env2$longitude))
    if (!is.null(coordinate_round_digits) && is.finite(coordinate_round_digits)) {
      env2$latitude <- round(env2$latitude, digits = as.integer(coordinate_round_digits))
      env2$longitude <- round(env2$longitude, digits = as.integer(coordinate_round_digits))
    }
    if (isTRUE(anonymize)) {
      if ("_location" %in% names(env2)) env2$`_location` <- NA_character_
    }
  }

  if (!is.null(veg2) && nrow(veg2) > 0) {
    veg2$plot_id <- as.character(veg2$plot_id)
    veg2$species_code <- toupper(trimws(as.character(veg2$species_code)))
    veg2$layer <- as.character(veg2$layer)
    veg2$cover <- as.character(veg2$cover)
  }

  if (isTRUE(drop_internal_fields)) {
    drop_by_pattern <- function(df) {
      if (is.null(df) || nrow(df) == 0) return(df)
      # Keep required publication contract fields (plot_id/project_id), so do NOT drop generic *_id columns.
      keep <- !grepl("(^id$|^flag$|row_version|modified_by|last_modified|created_)", names(df), ignore.case = TRUE)
      df[, keep, drop = FALSE]
    }
    env2 <- drop_by_pattern(env2)
    veg2 <- drop_by_pattern(veg2)
    meta2 <- drop_by_pattern(meta2)
  }

  list(environment = env2, vegetation = veg2, metadata = meta2)
}

write_publication_files <- function(con,
                                    project_id,
                                    dataset,
                                    output_dir,
                                    formats = c("rds"),
                                    apply_lumping = TRUE,
                                    overwrite = TRUE) {
  formats <- unique(tolower(formats))
  supported <- c("rds", "csv", "xlsx")
  bad <- setdiff(formats, supported)
  if (length(bad) > 0) stop("Unsupported formats: ", paste(bad, collapse = ", "))
  if (length(formats) == 0) stop("No formats requested.")

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  file_paths <- list()

  # RDS/CSV files for BEC map contract
  if ("rds" %in% formats) {
    env_path <- file.path(output_dir, paste0(project_id, "_environment.rds"))
    veg_path <- file.path(output_dir, paste0(project_id, "_vegetation.rds"))
    meta_path <- file.path(output_dir, paste0(project_id, "_metadata.rds"))
    if (!overwrite && (file.exists(env_path) || file.exists(veg_path) || file.exists(meta_path))) {
      stop("Publication files already exist and overwrite=FALSE.")
    }
    saveRDS(dataset$environment, env_path)
    saveRDS(dataset$vegetation, veg_path)
    saveRDS(dataset$metadata, meta_path)
    file_paths$environment_rds <- env_path
    file_paths$vegetation_rds <- veg_path
    file_paths$metadata_rds <- meta_path
  }

  if ("csv" %in% formats) {
    env_path <- file.path(output_dir, paste0(project_id, "_environment.csv"))
    veg_path <- file.path(output_dir, paste0(project_id, "_vegetation.csv"))
    meta_path <- file.path(output_dir, paste0(project_id, "_metadata.csv"))
    if (!overwrite && (file.exists(env_path) || file.exists(veg_path) || file.exists(meta_path))) {
      stop("Publication files already exist and overwrite=FALSE.")
    }
    utils::write.csv(dataset$environment, env_path, row.names = FALSE, na = "")
    utils::write.csv(dataset$vegetation, veg_path, row.names = FALSE, na = "")
    utils::write.csv(dataset$metadata, meta_path, row.names = FALSE, na = "")
    file_paths$environment_csv <- env_path
    file_paths$vegetation_csv <- veg_path
    file_paths$metadata_csv <- meta_path
  }

  # XLSX: use existing Excel exporter (combined workbook)
  if ("xlsx" %in% formats) {
    if (!requireNamespace("openxlsx", quietly = TRUE)) {
      if (length(setdiff(formats, "xlsx")) == 0) {
        stop("openxlsx package is required for XLSX output. Install with: install.packages('openxlsx')")
      }
      warning("openxlsx not installed; skipping XLSX output.")
    } else {
      source(publish_resolve_path("R/logic_excel_export.R"), local = TRUE)
      xlsx_path <- file.path(output_dir, paste0(project_id, "_combined.xlsx"))
      export_combined_excel(
        con,
        xlsx_path,
        options = list(project_ids = c(project_id), apply_lumping = isTRUE(apply_lumping))
      )
      file_paths$combined_xlsx <- xlsx_path
    }
  }

  file_paths
}

record_publication_registry <- function(registry_path,
                                        project_id,
                                        output_dir,
                                        file_paths,
                                        apply_lumping,
                                        created_by,
                                        anonymize,
                                        coordinate_round_digits,
                                        env_rows,
                                        veg_rows) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  timestamp_utc <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")

  md5 <- function(path) {
    if (is.null(path) || is.na(path) || !file.exists(path)) return(NA_character_)
    as.character(tools::md5sum(path))
  }

  row <- data.frame(
    timestamp_utc = timestamp_utc,
    project_id = as.character(project_id),
    output_dir = normalizePath(output_dir, winslash = "/", mustWork = FALSE),
    apply_lumping = isTRUE(apply_lumping),
    anonymize = isTRUE(anonymize),
    coordinate_round_digits = as.integer(coordinate_round_digits),
    env_rows = as.integer(env_rows),
    veg_rows = as.integer(veg_rows),
    environment_rds = as.character(file_paths$environment_rds %||% NA_character_),
    vegetation_rds = as.character(file_paths$vegetation_rds %||% NA_character_),
    metadata_rds = as.character(file_paths$metadata_rds %||% NA_character_),
    combined_xlsx = as.character(file_paths$combined_xlsx %||% NA_character_),
    md5_environment_rds = md5(file_paths$environment_rds),
    md5_vegetation_rds = md5(file_paths$vegetation_rds),
    md5_metadata_rds = md5(file_paths$metadata_rds),
    created_by = as.character(created_by %||% "unknown"),
    stringsAsFactors = FALSE
  )

  if (file.exists(registry_path)) {
    existing <- tryCatch(utils::read.csv(registry_path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(existing)) {
      combined <- rbind(existing, row)
      utils::write.csv(combined, registry_path, row.names = FALSE, na = "")
      return(invisible(row))
    }
  }

  utils::write.csv(row, registry_path, row.names = FALSE, na = "")
  invisible(row)
}

publish_project_dataset <- function(project_id,
                                    output_dir = "data/published",
                                    formats = c("rds", "csv", "xlsx"),
                                    apply_lumping = TRUE,
                                    con = NULL,
                                    anonymize = FALSE,
                                    coordinate_round_digits = 5,
                                    is_public = TRUE,
                                    description = NULL,
                                    registry_path = file.path(output_dir, "publication_registry.csv"),
                                    created_by = Sys.getenv("USER", "unknown"),
                                    overwrite = TRUE,
                                    fail_on_validation = TRUE) {
  if (missing(project_id) || is.null(project_id) || length(project_id) == 0) {
    stop("project_id is required")
  }

  project_id <- as.character(project_id)

  close_when_done <- FALSE
  if (is.null(con)) {
    source(publish_resolve_path("R/db_connections.R"), local = TRUE)
    con <- connect_local_db()
    close_when_done <- TRUE
  }
  on.exit({
    if (isTRUE(close_when_done)) close_db(con)
  }, add = TRUE)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  results <- lapply(project_id, function(pid) {
    validation <- validate_for_publishing(con, pid)
    if (!isTRUE(validation$passed) && isTRUE(fail_on_validation)) {
      stop("Publishing validation failed for project ", pid, ". See validation$detail_tibble.")
    }

    env <- publish_extract_environment(con, pid)
    veg <- publish_extract_vegetation(con, pid)

    # Optional lumping (numeric aggregation)
    if (isTRUE(apply_lumping) && nrow(veg) > 0) {
      source(publish_resolve_path("R/logic_lumping.R"), local = TRUE)
      veg_tmp <- data.frame(
        plot_id = as.character(veg$plot_id),
        layer = as.character(veg$layer),
        species = as.character(veg$species_code),
        cover_num = suppressWarnings(as.numeric(as.character(veg$cover))),
        stringsAsFactors = FALSE
      )
      veg_tmp$cover_num[is.na(veg_tmp$cover_num) & !is.na(veg$cover)] <- 0
      veg_lumped <- apply_lumping(
        con,
        veg_tmp,
        group_cols = c("plot_id", "layer"),
        measure_cols = c("cover_num")
      )
      veg <- data.frame(
        plot_id = as.character(veg_lumped$plot_id),
        species_code = as.character(veg_lumped$species),
        layer = as.character(veg_lumped$layer),
        cover = as.character(veg_lumped$cover_num),
        stringsAsFactors = FALSE
      )
    } else {
      veg$species_code <- toupper(trimws(as.character(veg$species_code)))
      veg$cover <- as.character(veg$cover)
    }

    meta <- publish_read_project_metadata(con, pid, is_public = is_public, description = description)

    transformed <- transform_for_publication(
      env = env,
      veg = veg,
      meta = meta,
      anonymize = anonymize,
      coordinate_round_digits = coordinate_round_digits,
      drop_internal_fields = TRUE
    )

    file_paths <- write_publication_files(
      con = con,
      project_id = pid,
      dataset = transformed,
      output_dir = output_dir,
      formats = formats,
      apply_lumping = apply_lumping,
      overwrite = overwrite
    )

    record_publication_registry(
      registry_path = registry_path,
      project_id = pid,
      output_dir = output_dir,
      file_paths = file_paths,
      apply_lumping = apply_lumping,
      created_by = created_by,
      anonymize = anonymize,
      coordinate_round_digits = coordinate_round_digits,
      env_rows = nrow(transformed$environment),
      veg_rows = nrow(transformed$vegetation)
    )

    list(
      project_id = pid,
      passed_validation = isTRUE(validation$passed),
      validation_details = validation$detail_tibble,
      env_rows = nrow(transformed$environment),
      veg_rows = nrow(transformed$vegetation),
      output_dir = output_dir,
      files = file_paths
    )
  })

  if (length(results) == 1) return(results[[1]])
  results
}

publish_becmaster_rds <- function(con,
                                 out_dir,
                                 version = NULL,
                                 project_ids = NULL,
                                 apply_lumping = TRUE,
                                 created_by = Sys.getenv("USER", "unknown"),
                                 allow_attach = TRUE) {
  if (is.null(out_dir) || !nzchar(out_dir)) {
    stop("Output directory is required for RDS publishing.")
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sync_require_cloud(con, allow_attach = allow_attach)

  filters <- c("a.qa_status = 'approved'")
  params <- list()
  if (!is.null(project_ids) && length(project_ids) > 0) {
    placeholders <- paste(rep("?", length(project_ids)), collapse = ", ")
    filters <- c(filters, paste0("a.project_id IN (", placeholders, ")"))
    params <- c(params, as.list(project_ids))
  }
  where_clause <- paste("WHERE", paste(filters, collapse = " AND "))

  veg_sql <- paste(
    "SELECT v.plotnumber, v.mylayer, v.species, v.cover",
    "FROM master.core.vw_usysallveg v",
    "JOIN master.core.sample_admin a ON v.plotnumber = a.plot_number",
    where_clause
  )
  veg <- DBI::dbGetQuery(con, veg_sql, params)

  env_sql <- paste(
    "SELECT e.plot_number AS plotnumber, e.project_id, e.latitude, e.longitude,",
    "e.elevation_m, e.survey_date, e.surveyor_name, e.plot_notes,",
    "s.su_number, s.bec_zone, s.bec_subzone, s.site_series",
    "FROM master.core.sample_env e",
    "JOIN master.core.sample_admin a ON e.plot_number = a.plot_number",
    "LEFT JOIN master.core.sample_su s ON e.plot_number = s.plot_number",
    where_clause
  )
  env <- DBI::dbGetQuery(con, env_sql, params)

  if (nrow(veg) > 0) {
    veg$cover_num <- suppressWarnings(as.numeric(veg$cover))
    veg$cover_num[is.na(veg$cover_num) & !is.na(veg$cover)] <- 0
    if (isTRUE(apply_lumping)) {
      veg <- apply_lumping(con, veg, group_cols = c("plotnumber", "mylayer"), measure_cols = "cover_num")
    }
    veg$col_name <- paste0(veg$species, "_", veg$mylayer)
    veg_wide <- veg[, c("plotnumber", "col_name", "cover_num"), drop = FALSE]
    veg_wide <- tidyr::pivot_wider(
      veg_wide,
      names_from = "col_name",
      values_from = "cover_num",
      values_fill = 0
    )
  } else {
    veg_wide <- data.frame(plotnumber = character(0), stringsAsFactors = FALSE)
  }

  if (is.null(version) || !nzchar(version)) {
    version <- format(Sys.time(), "%Y%m%d_%H%M%S")
  }

  veg_file <- file.path(out_dir, paste0("becmaster_veg_", version, ".rds"))
  env_file <- file.path(out_dir, paste0("becmaster_env_", version, ".rds"))

  saveRDS(veg_wide, veg_file)
  saveRDS(env, env_file)

  md5_veg <- as.character(tools::md5sum(veg_file))
  md5_env <- as.character(tools::md5sum(env_file))

  snapshot_meta <- list(
    project_ids = project_ids,
    qa_status = "approved",
    apply_lumping = isTRUE(apply_lumping)
  )
  snapshot_json <- if (requireNamespace("jsonlite", quietly = TRUE)) {
    jsonlite::toJSON(snapshot_meta, auto_unbox = TRUE, null = "null")
  } else {
    NA_character_
  }

  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO master.public_export.rds_snapshots",
      " (version, snapshot_date, created_by, rds_filename_veg, rds_filename_env,",
      " veg_row_count, env_row_count, md5_hash_veg, md5_hash_env, snapshot_metadata)",
      " VALUES (?, CURRENT_DATE, ?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    list(
      version,
      created_by,
      basename(veg_file),
      basename(env_file),
      nrow(veg_wide),
      nrow(env),
      md5_veg,
      md5_env,
      snapshot_json
    )
  )

  list(
    version = version,
    veg_path = veg_file,
    env_path = env_file,
    veg_rows = nrow(veg_wide),
    env_rows = nrow(env)
  )
}

publish_snapshot <- function(con,
                             out_dir,
                             version = NULL,
                             project_ids = NULL,
                             apply_lumping = TRUE,
                             created_by = Sys.getenv("USER", "unknown"),
                             allow_attach = TRUE) {
  publish_becmaster_rds(
    con = con,
    out_dir = out_dir,
    version = version,
    project_ids = project_ids,
    apply_lumping = apply_lumping,
    created_by = created_by,
    allow_attach = allow_attach
  )
}

log_export_download <- function(con,
                                dataset_name,
                                format,
                                filters_applied = NULL,
                                row_count = NULL,
                                user_id = NULL,
                                username = NULL,
                                download_status = "success",
                                error_message = NULL,
                                ip_address = NULL,
                                allow_attach = TRUE) {
  allowed_formats <- c("rds", "csv", "excel", "xml")
  if (is.null(dataset_name) || !nzchar(dataset_name)) return(FALSE)
  if (!(format %in% allowed_formats)) return(FALSE)

  filters_json <- NULL
  if (!is.null(filters_applied) && requireNamespace("jsonlite", quietly = TRUE)) {
    filters_json <- jsonlite::toJSON(filters_applied, auto_unbox = TRUE, null = "null")
  }

  result <- tryCatch({
    sync_require_cloud(con, allow_attach = allow_attach)
    DBI::dbExecute(
      con,
      paste0(
        "INSERT INTO master.public_export.download_log",
        " (user_id, username, dataset_name, format, filters_applied,",
        " row_count, ip_address, download_status, error_message)",
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      list(
        user_id,
        username %||% "anonymous",
        dataset_name,
        format,
        filters_json,
        row_count,
        ip_address,
        download_status,
        error_message
      )
    )
    TRUE
  }, error = function(e) FALSE)

  result
}

build_download_log_query <- function(filters = list(), limit = 1000L) {
  clauses <- character(0)
  params <- list()

  user_filter <- trimws(as.character(filters$user %||% ""))
  dataset_filter <- trimws(as.character(filters$dataset %||% ""))
  format_filter <- trimws(as.character(filters$format %||% ""))
  status_filter <- trimws(as.character(filters$status %||% ""))
  from_value <- filters$from
  to_value <- filters$to

  if (nzchar(user_filter)) {
    clauses <- c(clauses, "username ILIKE ?")
    params <- c(params, list(paste0("%", user_filter, "%")))
  }
  if (nzchar(dataset_filter)) {
    clauses <- c(clauses, "dataset_name ILIKE ?")
    params <- c(params, list(paste0("%", dataset_filter, "%")))
  }
  if (nzchar(format_filter)) {
    clauses <- c(clauses, "format = ?")
    params <- c(params, list(format_filter))
  }
  if (nzchar(status_filter)) {
    clauses <- c(clauses, "download_status = ?")
    params <- c(params, list(status_filter))
  }
  if (!is.null(from_value) && !is.na(from_value)) {
    clauses <- c(clauses, "timestamp_utc >= ?")
    params <- c(params, list(from_value))
  }
  if (!is.null(to_value) && !is.na(to_value)) {
    clauses <- c(clauses, "timestamp_utc <= ?")
    params <- c(params, list(to_value))
  }

  where_clause <- if (length(clauses) > 0) paste("WHERE", paste(clauses, collapse = " AND ")) else ""
  sql <- paste(
    "SELECT timestamp_utc, username, dataset_name, format, row_count,",
    "download_status, error_message, ip_address",
    "FROM master.public_export.download_log",
    where_clause,
    sprintf("ORDER BY timestamp_utc DESC LIMIT %d", as.integer(limit))
  )

  list(sql = sql, params = params)
}
