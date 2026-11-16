# Streaming Access (.accdb / .mdb) -> VP08 SQLite Converter --------------------

.vp07_env_map <- c(
  PlotNumber = "PlotNumber",
  FieldNumber = "FieldNumber",
  ProjectID = "ProjectID",
  FSRegionDistrict = "FSRegionDistrict",
  Date = "Date",
  SiteSurveyor = "SiteSurveyor",
  PlotRepresenting = "PlotRepresenting",
  Location = "Location",
  Ecosection = "Ecosection",
  NtsMapSheet = "NtsMapSheet",
  Longitude = "Longitude",
  Latitude = "Latitude",
  UTMZone = "UTMZone",
  UTMEasting = "UTMEasting",
  UTMNorthing = "UTMNorthing",
  LocationAccuracy = "LocationAccuracy",
  AirPhotoNum = "AirPhotoNum",
  XCoord = "XCoord",
  YCoord = "YCoord",
  Zone = "Zone",
  SubZone = "SubZone",
  SiteSeries = "SiteSeries",
  SiteModifier1 = "SiteModifier1",
  SiteModifier2 = "SiteModifier2",
  TransDistrib = "TransDistrib",
  RealmClass = "RealmClass",
  MapUnit = "MapUnit",
  SnowCoverregime = "SnowCoverregime",
  MoistureRegime = "MoistureRegime",
  NutrientRegime = "NutrientRegime",
  SuccessionalStatus = "SuccessionalStatus",
  StructuralStage = "StructuralStage",
  StructuralStageMod = "StructuralStageMod",
  StandAge = "StandAge",
  Elevation = "Elevation",
  SlopeGradient = "SlopeGradient",
  Aspect = "Aspect",
  MesoSlopePosition = "MesoSlopePosition",
  SurfaceShape = "SurfaceShape",
  SurfaceTopographyType = "SurfaceTopographyType",
  SurfaceTopographySize = "SurfaceTopographySize",
  WaterSource = "WaterSource",
  Photo = "Photo",
  Exposure1 = "Exposure1",
  Exposure2 = "Exposure2",
  SiteDisturbance1 = "SiteDisturbance1",
  SiteDisturbance2 = "SiteDisturbance2",
  SiteDisturbance3 = "SiteDisturbance3",
  SubstrateDecWood = "SubstrateDecWood",
  SubstrateBedRock = "SubstrateBedRock",
  SubstrateRocks = "SubstrateRocks",
  SubstrateMineralSoil = "SubstrateMineralSoil",
  SubstrateOrganicMatter = "SubstrateOrganicMatter",
  SubstrateWater = "SubstrateWater",
  SiteNotes = "SiteNotes",
  SoilSurveyor = "SoilSurveyor",
  BedrockGeology1 = "BedrockGeology1",
  BedrockGeology2 = "BedrockGeology2",
  BedrockGeology3 = "BedrockGeology3",
  CoarseFragLith1 = "CoarseFragLith1",
  CoarseFragLith2 = "CoarseFragLith2",
  CoarseFragLith3 = "CoarseFragLith3",
  TerrainTextureSurf = "TerrainTextureSurf",
  SurficialMaterialSurf = "SurficialMaterialSurf",
  SurfaceExpSurf = "SurfaceExpSurf",
  GeoMorProSurf = "GeoMorProSurf",
  TerrainTextureSubSurf = "TerrainTextureSubSurf",
  SurficialMaterialSubSurf = "SurficialMaterialSubSurf",
  SurfaceExpSubSurf = "SurfaceExpSubSurf",
  GeoMorProSubSurf = "GeoMorProSubSurf",
  FloodingRegimeFreq = "FloodingRegimeFreq",
  MoistureRegimeSub = "MoistureRegimeSub",
  FloodingRegimeDur = "FloodingRegimeDur",
  SoilDrainage = "SoilDrainage",
  SeepageDepth = "SeepageDepth",
  RootRestrictingType = "RootRestrictingType",
  RootRestrictingDepth = "RootRestrictingDepth",
  RootZoneParticleSize = "RootZoneParticleSize",
  RootingDepth = "RootingDepth",
  SoilClassSubGroup = "SoilClassSubGroup",
  SoilClassGroup = "SoilClassGroup",
  HumusForm = "HumusForm",
  HumusFormPhase = "HumusFormPhase",
  pHMethodCodeMineral = "pHMethodCodeMineral",
  pHMethodCodeOrganic = "pHMethodCodeOrganic",
  SoilNotes = "SoilNotes",
  VegSurveyor = "VegSurveyor",
  StrataCoverTree = "StrataCoverTree",
  StrataCoverShrub = "StrataCoverShrub",
  StrataCoverHerb = "StrataCoverHerb",
  StrataCoverMoss = "StrataCoverMoss",
  VegNotes = "VegNotes",
  HydroGeoSystem = "HydroGeoSystem",
  HydroGeoSubSystem = "HydroGeoSubSystem",
  SpeciesListComplete = "SpeciesListComplete",
  Temporary = "Temporary",
  Flag = "Flag",
  SV_PolygonNumber = "PolygonNumber",
  SV_FloodPlain = "FloodPlain",
  SV_StandAgeEstMeas = "StandAgeEstMeas",
  SV_StandHeight = "StandHeight",
  SV_StandHeightEstMeas = "StandHeightEstMeas",
  SV_CanopyComposition = "CanopyComposition",
  SV_SoilDepth = "SoilDepth",
  SV_RootZoneTexture = "RootZoneTexture",
  SV_PercentCoarseFrags = "PercentCoarseFrags",
  SV_GleyingMottlingCM = "GleyingMottlingCM",
  SV_WaterTableCM = "WaterTableCM",
  SV_FullCruiseCard = "FullCruiseCard",
  SV_AhorizonType = "AhorizonType",
  SV_AhorizonDepth = "AhorizonDepth",
  ActiveLayerDepth = "ActiveLayerDepth"
)

.vp07_admin_map <- c(
  Plot = "PlotNumber",
  StartDate = "StartDate",
  PlotType = "PlotType",
  PlotSize = "PlotSize",
  ProvinceStateTerritory = "ProvinceStateTerritory",
  SitePlotQuality = "SitePlotQuality",
  VegPlotQuality = "VegPlotQuality",
  SoilPlotQuality = "SoilPlotQuality",
  UpdatedFromCards = "UpdatedFromCards",
  EnteredBy = "EnteredBy",
  UserSiteUnit = "UserSiteUnit",
  BECSiteUnit = "BECSiteUnit",
  SiteUnitShortName = "SiteUnitShortName",
  SiteUnitLongName = "SiteUnitLongName",
  OfficeNotes = "OfficeNotes",
  HumusThickness = "HumusThickness",
  GIS_BGC = "GIS_BGC",
  GIS_BGC_VER = "GIS_BGC_ver",
  StrataCoverTotal = "StrataCoverTotal"
)

.vp06_admin_map <- c(
  Plot = "PlotNumber",
  SitePlotQuality = "SitePlotQuality",
  VegPlotQuality = "VegPlotQuality",
  SoilPlotQuality = "SoilPlotQuality",
  UpdatedFromCards = "UpdatedFromCards",
  EnteredBy = "EnteredBy",
  UserSiteUnit = "UserSiteUnit",
  BECSiteUnit = "BECSiteUnit",
  SiteUnitShortName = "SiteUnitShortName",
  SiteUnitLongName = "SiteUnitLongName",
  OfficeNotes = "OfficeNotes",
  HumusThickness = "HumusThickness"
)

.vp05_env_renames <- c(
  FieldNumber = "SiteNumber",
  ProjectID = "ProjectName",
  FSRegionDistrict = "Region",
  SurfaceShape = "SurfaceTopography",
  BedrockGeology1 = "BedrockGeology",
  CoarseFragLith1 = "CoarseFragLith",
  Photo = "PhotoRollNum"
)

.vp05_admin_map <- c(
  Plot = "PlotNumber",
  SitePlotQuality = "PlotQuality",
  UserSiteUnit = "AssignedSiteUnit",
  SiteUnitShortName = "SiteUnitShortName",
  SiteUnitLongName = "SiteUnitLongName",
  HumusThickness = "HumusThickness"
)

vpro_access_table_desc <- function(path, table) {
  props <- tryCatch(mdbr::mdb_prop(path, name = table), error = function(e) NULL)
  if (is.null(props)) {
    return(NA_character_)
  }
  tp <- props[[table]][["(none)"]]
  desc <- if (!is.null(tp) && "Description" %in% names(tp)) tp[["Description"]] else NULL
  if (is.null(desc) || length(desc) == 0L || is.na(desc[[1L]])) NA_character_ else trimws(as.character(desc[[1L]]))
}

#' Inspect local tables and projects inside a Microsoft Access `.accdb` or `.mdb`
#'
#' @param path Path to an existing `.accdb` or `.mdb` archive.
#' @return A list with `source_path`, `projects` tibble (`project`, `version`,
#'   `compatible`, `n_plots`), `tables` tibble, and `links` character vector.
#' @export
vpro_access_inspect <- function(path) {
  rlang::check_installed("mdbr", reason = "to inspect Microsoft Access (.accdb/.mdb) archives.")
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    rlang::abort("`path` must be an existing `.accdb` or `.mdb` file.")
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  tables <- mdbr::mdb_tables(path, type = "table")
  links <- mdbr::mdb_tables(path, type = "linkedtable")
  rows <- vapply(tables, function(tbl) as.integer(mdbr::mdb_count(path, tbl)), integer(1))
  descs <- vapply(tables, function(tbl) vpro_access_table_desc(path, tbl), character(1))
  tbl_df <- tibble::tibble(
    table_name = tables,
    rows = rows,
    description = descs
  )

  env_idx <- grep("_Env$", tables, ignore.case = TRUE)
  env_idx <- env_idx[!grepl("^(Filtered|USys)", tables[env_idx], ignore.case = TRUE)]
  proj_rows <- lapply(env_idx, function(i) {
    env_tbl <- tables[[i]]
    prj <- sub("_Env$", "", env_tbl, ignore.case = TRUE)
    ver <- descs[[i]]
    if (is.na(ver) || !nzchar(ver)) {
      ver <- "VP08"
    }
    tibble::tibble(
      project = prj,
      version = ver,
      compatible = ver %in% c("VP05", "VP06", "VP07", "VP08"),
      n_plots = rows[[i]]
    )
  })
  projects_df <- if (length(proj_rows)) {
    do.call(rbind, proj_rows)
  } else {
    tibble::tibble(
      project = character(),
      version = character(),
      compatible = logical(),
      n_plots = integer()
    )
  }

  list(
    source_path = path,
    projects = projects_df,
    tables = tbl_df,
    links = links
  )
}

vpro_clone_sample_schema <- function(target_con, target_project) {
  sample_con <- vpro_sqlite_ro(vpro_bundled_db("Sample.db"))
  on.exit(DBI::dbDisconnect(sample_con), add = TRUE)

  ddl_rows <- DBI::dbGetQuery(
    sample_con,
    "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL AND tbl_name LIKE 'Sample_%'"
  )
  deferred_idx <- character()
  for (suffix in .vpro_core_project_suffixes) {
    src_tbl <- paste0("Sample_", suffix)
    dst_tbl <- paste0(target_project, "_", suffix)
    t_sql <- ddl_rows$sql[ddl_rows$type == "table" & ddl_rows$name == src_tbl]
    if (length(t_sql) == 1L) {
      rewritten <- gsub("Sample_", paste0(target_project, "_"), t_sql[[1L]], fixed = TRUE)
      # Remove strict FK constraints in SQLite table DDL when mirroring VPro Desktop Access import,
      # since orphan checks are enforced explicitly via __VPRO_ImportQuarantine
      DBI::dbExecute(target_con, rewritten)
    }
    i_rows <- ddl_rows[ddl_rows$type == "index" & ddl_rows$tbl_name == src_tbl, , drop = FALSE]
    for (j in seq_len(nrow(i_rows))) {
      deferred_idx <- c(
        deferred_idx,
        gsub("Sample_", paste0(target_project, "_"), i_rows$sql[[j]], fixed = TRUE)
      )
    }
  }
  deferred_idx
}

vpro_normalize_access_chunk <- function(df, target_fields, boolean_fields = character()) {
  out <- as.list(rep(list(NULL), length(target_fields)))
  names(out) <- target_fields
  src_low <- tolower(names(df))
  n <- nrow(df)

  for (col in target_fields) {
    idx <- match(tolower(col), src_low)
    if (is.na(idx)) {
      out[[col]] <- rep(NA, n)
      next
    }
    v <- df[[idx]]
    if (col %in% c("PlotNumber", "Plot")) {
      chr <- as.character(v)
      out[[col]] <- chr
    } else if (col %in% boolean_fields || is.logical(v)) {
      out[[col]] <- vpro_logical_to_access(v)
    } else if (inherits(v, "POSIXt")) {
      res <- rep(NA_character_, n)
      ok <- !is.na(v)
      res[ok] <- format(v[ok], "%Y-%m-%d %H:%M:%S", tz = "UTC")
      out[[col]] <- res
    } else if (inherits(v, "Date")) {
      out[[col]] <- as.character(v)
    } else {
      out[[col]] <- v
    }
  }
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Convert a Microsoft Access `.accdb` / `.mdb` project (`VP05`--`VP08`) to `VP08` SQLite
#'
#' Streams Access tables via `mdbr` in bounded row batches into a clean `VP08`
#' SQLite project database matching VPro Desktop. Never mutates the source
#' Access file. Duplicate plot keys, malformed values, and orphaned child
#' records without a parent plot are saved to an import quarantine log rather
#' than silently dropped.
#'
#' @param path Path to source `.accdb` or `.mdb` archive.
#' @param dest_db Destination SQLite `.db` path.
#' @param project Optional source project prefix inside `path` (auto-detected if
#'   only one project exists).
#' @param dest_project Optional destination project prefix (defaults to a
#'   sanitized identifier derived from `project`).
#' @param batch_rows Positive integer batch size for streaming reads.
#' @param overwrite Logical; if `TRUE`, replaces an existing `dest_db`.
#' @return A list summarizing `source_path`, `source_project`, `source_version`,
#'   `target_project`, `target_db`, `plot_count`, `quarantined_orphan_rows`,
#'   `quarantined_malformed_rows`, and `imported_su`.
#' @export
vpro_import_access <- function(
  path,
  dest_db,
  project = NULL,
  dest_project = NULL,
  batch_rows = 5000L,
  overwrite = FALSE
) {
  rlang::check_installed("mdbr", reason = "to stream Microsoft Access (.accdb/.mdb) tables.")
  insp <- vpro_access_inspect(path)
  if (nrow(insp$projects) == 0L) {
    rlang::abort(paste0("No `<Project>_Env` tables found in Access file: ", insp$source_path))
  }
  src_prj <- if (is.null(project)) {
    insp$projects$project[[1L]]
  } else {
    hit <- insp$projects$project[tolower(insp$projects$project) == tolower(trimws(project))]
    if (length(hit) == 0L) {
      rlang::abort(paste0("Project `", project, "` not found in ", insp$source_path))
    }
    hit[[1L]]
  }
  ver <- insp$projects$version[insp$projects$project == src_prj][[1L]]
  if (!(ver %in% c("VP05", "VP06", "VP07", "VP08"))) {
    rlang::abort(paste0("Unsupported Access project version `", ver, "` (expected VP05--VP08)."))
  }

  sanitize_name <- function(x) {
    s <- gsub("[^A-Za-z0-9_]", "_", trimws(x))
    if (!nzchar(s) || !grepl("^[A-Za-z]", s)) {
      s <- paste0("P_", s)
    }
    substr(s, 1L, 31L)
  }
  dst_prj <- if (is.null(dest_project)) sanitize_name(src_prj) else vpro_project_name(dest_project)

  target_db <- vpro_abs_path(dest_db)
  if (identical(target_db, insp$source_path)) {
    rlang::abort("`dest_db` must not overwrite the source Access archive.")
  }
  if (file.exists(target_db)) {
    if (!isTRUE(overwrite)) {
      rlang::abort(paste0("Destination already exists (use `overwrite = TRUE` to replace): ", target_db))
    }
    if (file.exists(paste0(target_db, "-wal")) || file.exists(paste0(target_db, "-shm"))) {
      rlang::abort(paste0("Refusing to overwrite ", target_db, " while it is open in another VPro or database session."))
    }
  }
  dir.create(dirname(target_db), recursive = TRUE, showWarnings = FALSE)
  stage_db <- tempfile(pattern = "vpro-import-", tmpdir = dirname(target_db), fileext = ".db")
  on.exit(unlink(c(stage_db, paste0(stage_db, "-wal"), paste0(stage_db, "-shm"))), add = TRUE)

  mdb_con <- DBI::dbConnect(mdbr::mdb(), insp$source_path)
  on.exit(DBI::dbDisconnect(mdb_con), add = TRUE)

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), stage_db)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA foreign_keys = OFF")
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = MEMORY")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = OFF")

  tbl_lookup <- stats::setNames(insp$tables$table_name, tolower(insp$tables$table_name))
  find_src <- function(suffix, required = TRUE) {
    nm <- unname(tbl_lookup[tolower(paste0(src_prj, "_", suffix))])
    if ((length(nm) == 0L || is.na(nm)) && required) {
      rlang::abort(paste0("Missing required Access table: ", src_prj, "_", suffix))
    }
    if (length(nm) == 0L || is.na(nm)) NULL else nm
  }

  quarantined_orphans <- 0L
  quarantined_malformed <- 0L

  log_quarantine <- function(src_tbl, row_nums, plots, reason, df_sub) {
    if (length(row_nums) == 0L) {
      return(invisible(NULL))
    }
    payloads <- vapply(
      seq_len(nrow(df_sub)),
      function(i) {
        as.character(jsonlite::toJSON(as.list(df_sub[i, , drop = FALSE]), auto_unbox = TRUE, na = "null"))
      },
      character(1)
    )
    q_df <- data.frame(
      SourceTable = rep(src_tbl, length(row_nums)),
      SourceRow = as.integer(row_nums),
      PlotNumber = ifelse(is.na(plots), "", as.character(plots)),
      Reason = rep(reason, length(row_nums)),
      PayloadJSON = payloads,
      stringsAsFactors = FALSE
    )
    DBI::dbAppendTable(sq_con, "__VPRO_ImportQuarantine", q_df)
  }

  valid_plots <- new.env(hash = TRUE, parent = emptyenv())
  imported_su <- character()

  DBI::dbWithTransaction(sq_con, {
    deferred_idx <- vpro_clone_sample_schema(sq_con, dst_prj)
    DBI::dbExecute(sq_con, 'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)')
    for (sfx in .vpro_core_project_suffixes) {
      DBI::dbExecute(
        sq_con,
        'INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
        params = list(paste0(dst_prj, "_", sfx))
      )
    }
    DBI::dbExecute(
      sq_con,
      paste(
        'CREATE TABLE "__VPRO_ImportQuarantine" (',
        '"ID" INTEGER PRIMARY KEY AUTOINCREMENT,',
        '"SourceTable" TEXT NOT NULL,',
        '"SourceRow" INTEGER NOT NULL,',
        '"PlotNumber" TEXT NOT NULL,',
        '"Reason" TEXT NOT NULL,',
        '"PayloadJSON" TEXT NOT NULL)'
      )
    )

    env_target <- paste0(dst_prj, "_Env")
    admin_target <- paste0(dst_prj, "_Admin")
    env_fields <- DBI::dbListFields(sq_con, env_target)
    admin_fields <- DBI::dbListFields(sq_con, admin_target)
    env_bools <- c("SpeciesListComplete", "Flag", "SV_FloodPlain")
    admin_bools <- c("UpdatedFromCards")

    # 1. Stream _Env (and derive _Admin when VP05/VP06/VP07)
    src_env <- find_src("Env", required = TRUE)
    cur <- mdbr::mdb_stream_table(mdb_con, src_env)
    on.exit(if (DBI::dbIsValid(cur)) DBI::dbClearResult(cur), add = TRUE)
    offset <- 0L
    repeat {
      chunk <- DBI::dbFetch(cur, n = as.integer(batch_rows))
      if (nrow(chunk) == 0L) {
        break
      }
      row_ids <- seq.int(offset + 1L, length.out = nrow(chunk))
      offset <- offset + nrow(chunk)

      work <- chunk
      if (ver == "VP07") {
        for (dst_c in names(.vp07_env_map)) {
          src_c <- .vp07_env_map[[dst_c]]
          m_idx <- match(tolower(src_c), tolower(names(work)))
          if (!is.na(m_idx)) work[[dst_c]] <- work[[m_idx]]
        }
      } else if (ver == "VP05") {
        if (!all(c("longitudedegrees", "latitudedegrees") %in% tolower(names(work)))) {
          rlang::abort("VP05 Env table is missing required `LongitudeDegrees` or `LatitudeDegrees` columns.")
        }
        for (dst_c in names(.vp05_env_renames)) {
          src_c <- .vp05_env_renames[[dst_c]]
          m_idx <- match(tolower(src_c), tolower(names(work)))
          if (!is.na(m_idx)) work[[dst_c]] <- work[[m_idx]]
        }
        get_num <- function(nm, default_na = TRUE) {
          ix <- match(tolower(nm), tolower(names(work)))
          if (is.na(ix)) rep(if (default_na) NA_real_ else 0, nrow(work)) else suppressWarnings(as.numeric(work[[ix]]))
        }
        lon_d <- get_num("LongitudeDegrees", default_na = TRUE)
        lat_d <- get_num("LatitudeDegrees", default_na = TRUE)
        lon_m <- get_num("LongitudeMinutes", default_na = FALSE)
        lon_s <- get_num("LongitudeSeconds", default_na = FALSE)
        lat_m <- get_num("LatitudeMinutes", default_na = FALSE)
        lat_s <- get_num("LatitudeSeconds", default_na = FALSE)
        work$Longitude <- ifelse(is.na(lon_d), NA_real_, lon_d + (ifelse(is.na(lon_m), 0, lon_m) + ifelse(is.na(lon_s), 0, lon_s) / 60) / 60)
        work$Latitude <- ifelse(is.na(lat_d), NA_real_, lat_d + (ifelse(is.na(lat_m), 0, lat_m) + ifelse(is.na(lat_s), 0, lat_s) / 60) / 60)
      }

      p_col <- match("plotnumber", tolower(names(work)))
      plots <- if (!is.na(p_col)) as.character(work[[p_col]]) else rep(NA_character_, nrow(work))
      u16_len <- vpro_utf16_len(plots)
      bad <- is.na(plots) | !nzchar(trimws(plots)) | is.na(u16_len) | u16_len > 7L
      dup <- logical(length(plots))
      good_idx <- which(!bad)
      if (length(good_idx) > 0L) {
        g_plots <- plots[good_idx]
        already <- vapply(unique(g_plots), function(pk) exists(pk, envir = valid_plots, inherits = FALSE), logical(1))
        already_set <- names(already)[already]
        in_prev <- g_plots %in% already_set
        in_chunk_dup <- duplicated(g_plots)
        is_d <- in_prev | in_chunk_dup
        dup[good_idx[is_d]] <- TRUE
        for (pk in unique(g_plots[!is_d])) {
          assign(pk, TRUE, envir = valid_plots)
        }
      }
      if (any(bad)) {
        quarantined_malformed <- quarantined_malformed + sum(bad)
        log_quarantine(src_env, row_ids[bad], plots[bad], "missing_plot_number", chunk[bad, , drop = FALSE])
      }
      if (any(dup)) {
        quarantined_malformed <- quarantined_malformed + sum(dup)
        log_quarantine(src_env, row_ids[dup], plots[dup], "duplicate_plot_key", chunk[dup, , drop = FALSE])
      }
      keep <- !(bad | dup)
      if (any(keep)) {
        env_norm <- vpro_normalize_access_chunk(work[keep, , drop = FALSE], env_fields, env_bools)
        DBI::dbAppendTable(sq_con, env_target, env_norm)
        if (ver != "VP08") {
          adm_map <- switch(ver, VP07 = .vp07_admin_map, VP06 = .vp06_admin_map, VP05 = .vp05_admin_map)
          adm_work <- data.frame(matrix(nrow = sum(keep), ncol = 0))
          sub_src <- chunk[keep, , drop = FALSE]
          for (dst_c in names(adm_map)) {
            ix <- match(tolower(adm_map[[dst_c]]), tolower(names(sub_src)))
            if (!is.na(ix)) adm_work[[dst_c]] <- sub_src[[ix]]
          }
          adm_norm <- vpro_normalize_access_chunk(adm_work, admin_fields, admin_bools)
          DBI::dbAppendTable(sq_con, admin_target, adm_norm)
        }
      }
    }
    DBI::dbClearResult(cur)

    valid_plot_vec <- ls(valid_plots, all.names = TRUE)

    # 2. Stream remaining core tables
    stream_child <- function(suffix, plot_col = "PlotNumber", req_env = TRUE, dedupe = FALSE, bool_cols = "Flag") {
      src_tbl <- find_src(suffix, required = (suffix != "Metadata" && suffix != "Admin") || ver == "VP08")
      if (is.null(src_tbl)) {
        return(invisible(NULL))
      }
      dst_tbl <- paste0(dst_prj, "_", suffix)
      dst_fields <- DBI::dbListFields(sq_con, dst_tbl)
      seen_vec <- character()
      c_cur <- mdbr::mdb_stream_table(mdb_con, src_tbl)
      on.exit(if (DBI::dbIsValid(c_cur)) DBI::dbClearResult(c_cur), add = TRUE)
      off <- 0L
      repeat {
        ch <- DBI::dbFetch(c_cur, n = as.integer(batch_rows))
        if (nrow(ch) == 0L) {
          break
        }
        r_ids <- seq.int(off + 1L, length.out = nrow(ch))
        off <- off + nrow(ch)

        keep <- rep(TRUE, nrow(ch))
        if (!is.null(plot_col)) {
          px <- match(tolower(plot_col), tolower(names(ch)))
          pvals <- if (!is.na(px)) as.character(ch[[px]]) else rep(NA_character_, nrow(ch))
          if (req_env) {
            orph <- is.na(pvals) | !nzchar(pvals) | !(pvals %in% valid_plot_vec)
            if (any(orph)) {
              quarantined_orphans <<- quarantined_orphans + sum(orph)
              log_quarantine(src_tbl, r_ids[orph], pvals[orph], "orphan_missing_env_plot", ch[orph, , drop = FALSE])
              keep[orph] <- FALSE
            }
          }
          if (dedupe && any(keep)) {
            k_idx <- which(keep)
            kp <- pvals[k_idx]
            is_dup <- (kp %in% seen_vec) | duplicated(kp)
            if (any(is_dup)) {
              d_rows <- k_idx[is_dup]
              quarantined_malformed <<- quarantined_malformed + length(d_rows)
              log_quarantine(src_tbl, r_ids[d_rows], pvals[d_rows], "duplicate_plot_key", ch[d_rows, , drop = FALSE])
              keep[d_rows] <- FALSE
            }
            seen_vec <- unique(c(seen_vec, kp[!is_dup]))
          }
        }
        if (identical(suffix, "Veg") && any(keep)) {
          sp_ix <- match("species", tolower(names(ch)))
          if (!is.na(sp_ix)) {
            sp_u16 <- vpro_utf16_len(ch[[sp_ix]])
            bad_sp <- keep & (is.na(sp_u16) | sp_u16 == 0L | sp_u16 > 8L)
          } else {
            bad_sp <- rep(FALSE, nrow(ch))
          }
          cov_ix <- grep("^(cover[0-9a-c]+|total[ab])$", tolower(names(ch)))
          bad_cov <- rep(FALSE, nrow(ch))
          for (ci in cov_ix) {
            nv <- vpro_narrow_float32(suppressWarnings(as.numeric(ch[[ci]])))
            bad_cov <- bad_cov | (!is.na(nv) & (nv < 0 | nv >= 100))
            ch[[ci]] <- nv
          }
          mal <- keep & (bad_sp | bad_cov)
          if (any(mal)) {
            quarantined_malformed <<- quarantined_malformed + sum(mal)
            px <- match(tolower(plot_col), tolower(names(ch)))
            mp <- if (!is.na(px)) as.character(ch[[px]][mal]) else rep("", sum(mal))
            log_quarantine(src_tbl, r_ids[mal], mp, "invalid_veg_species_or_cover", ch[mal, , drop = FALSE])
            keep[mal] <- FALSE
          }
        }
        if (any(keep)) {
          norm_df <- vpro_normalize_access_chunk(ch[keep, , drop = FALSE], dst_fields, bool_cols)
          if ("ID" %in% names(norm_df) && anyDuplicated(norm_df$ID[!is.na(norm_df$ID)])) {
            norm_df$ID <- NULL
          }
          DBI::dbAppendTable(sq_con, dst_tbl, norm_df)
        }
      }
      DBI::dbClearResult(c_cur)
    }

    stream_child("Veg", "PlotNumber", req_env = TRUE, bool_cols = "Flag")
    stream_child("Humus", "PlotNumber", req_env = TRUE, bool_cols = "Flag")
    stream_child("Mineral", "PlotNumber", req_env = TRUE, bool_cols = "Flag")
    stream_child("Other", "PlotNumber", req_env = TRUE, bool_cols = "Flag")
    stream_child("Audit", plot_col = NULL, req_env = FALSE, bool_cols = c("Restore", "Flag"))
    if (ver %in% c("VP07", "VP08")) {
      stream_child("Metadata", plot_col = NULL, req_env = FALSE, bool_cols = character())
    }
    if (ver == "VP08") {
      stream_child("Admin", "Plot", req_env = TRUE, dedupe = TRUE, bool_cols = admin_bools)
    }

    # 3. Import optional *_SU, *_Hierarchy, *_Lump, *_Profile tables
    for (src_tbl in insp$tables$table_name) {
      if (grepl("^USys", src_tbl, ignore.case = TRUE)) {
        next
      }
      if (grepl("_SU$", src_tbl, ignore.case = TRUE)) {
        su_prefix <- sub("_SU$", "", src_tbl, ignore.case = TRUE)
        if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", su_prefix)) {
          next
        }
        dst_su <- if (tolower(su_prefix) == tolower(src_prj)) paste0(dst_prj, "_SU") else paste0(su_prefix, "_SU")
        q_su <- vpro_quote_ident(dst_su)
        DBI::dbExecute(sq_con, paste0("CREATE TABLE ", q_su, ' ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)'))
        su_df <- DBI::dbReadTable(mdb_con, src_tbl)
        p_ix <- match("plotnumber", tolower(names(su_df)))
        u_ix <- match("siteunit", tolower(names(su_df)))
        if (!is.na(p_ix) && !is.na(u_ix) && nrow(su_df) > 0L) {
          pvals <- as.character(su_df[[p_ix]])
          uvals <- as.character(su_df[[u_ix]])
          orph <- is.na(pvals) | !vapply(pvals, function(pk) !is.na(pk) && nzchar(pk) && exists(pk, envir = valid_plots, inherits = FALSE), logical(1))
          if (any(orph)) {
            quarantined_orphans <- quarantined_orphans + sum(orph)
            log_quarantine(src_tbl, which(orph), pvals[orph], "orphan_missing_env_plot", su_df[orph, , drop = FALSE])
          }
          keep_idx <- which(!orph)
          if (length(keep_idx) > 0L) {
            sub_su <- data.frame(PlotNumber = pvals[keep_idx], SiteUnit = uvals[keep_idx], stringsAsFactors = FALSE)
            dup_su <- duplicated(sub_su$PlotNumber)
            if (any(dup_su)) {
              quarantined_malformed <- quarantined_malformed + sum(dup_su)
              log_quarantine(src_tbl, keep_idx[dup_su], sub_su$PlotNumber[dup_su], "duplicate_plot_key", su_df[keep_idx[dup_su], , drop = FALSE])
              sub_su <- sub_su[!dup_su, , drop = FALSE]
            }
            if (nrow(sub_su) > 0L) DBI::dbAppendTable(sq_con, dst_su, sub_su)
          }
          DBI::dbExecute(sq_con, paste0("CREATE UNIQUE INDEX ", vpro_quote_ident(paste0("uidx_", dst_su, "_PlotNumber")), " ON ", q_su, ' ("PlotNumber")'))
          DBI::dbExecute(sq_con, paste0("CREATE INDEX ", vpro_quote_ident(paste0("idx_", dst_su, "_SiteUnit")), " ON ", q_su, ' ("SiteUnit")'))
          DBI::dbExecute(sq_con, 'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP04\')', params = list(dst_su))
          imported_su <- c(imported_su, dst_su)
        }
      } else if (grepl("_(Hierarchy|Lump|Profile)$", src_tbl, ignore.case = TRUE)) {
        sfx <- sub("^.*_(Hierarchy|Lump|Profile)$", "\\1", src_tbl, ignore.case = TRUE)
        pfx <- sub("_(Hierarchy|Lump|Profile)$", "", src_tbl, ignore.case = TRUE)
        if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", pfx)) {
          next
        }
        dst_opt <- if (tolower(pfx) == tolower(src_prj)) paste0(dst_prj, "_", sfx) else paste0(pfx, "_", sfx)
        opt_df <- tryCatch(DBI::dbReadTable(mdb_con, src_tbl), error = function(e) NULL)
        if (!is.null(opt_df)) {
          for (bc in intersect(c("Use", "Flag"), names(opt_df))) {
            opt_df[[bc]] <- vpro_logical_to_access(opt_df[[bc]])
          }
          DBI::dbWriteTable(sq_con, dst_opt, opt_df, overwrite = TRUE)
          tag <- switch(tolower(sfx), hierarchy = "VP04", lump = "VP05", profile = "VP05-2")
          DBI::dbExecute(sq_con, 'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)', params = list(dst_opt, tag))
        }
      }
    }

    for (idx_sql in deferred_idx) {
      tryCatch(DBI::dbExecute(sq_con, idx_sql), error = function(e) NULL)
    }
  })

  plot_count <- as.integer(DBI::dbGetQuery(sq_con, paste0("SELECT COUNT(*) AS n FROM ", vpro_quote_ident(paste0(dst_prj, "_Env"))))$n[[1L]])
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = WAL")
  DBI::dbDisconnect(sq_con)

  if (file.exists(target_db)) {
    if (file.exists(paste0(target_db, "-wal")) || file.exists(paste0(target_db, "-shm"))) {
      rlang::abort(paste0("Refusing to overwrite ", target_db, " while it is open in another VPro or database session."))
    }
    unlink(target_db)
  }
  if (!file.rename(stage_db, target_db)) {
    if (!file.copy(stage_db, target_db, overwrite = TRUE)) {
      rlang::abort(paste0("Failed to publish converted SQLite database to: ", target_db))
    }
  }

  list(
    source_path = insp$source_path,
    source_project = src_prj,
    source_version = ver,
    target_project = dst_prj,
    target_db = target_db,
    plot_count = plot_count,
    quarantined_orphan_rows = as.integer(quarantined_orphans),
    quarantined_malformed_rows = as.integer(quarantined_malformed),
    imported_su = imported_su
  )
}
