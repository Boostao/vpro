# 2026 BEC Standards & Runtime Readiness --------------------------------------

#' Read 2026 BECdb v13 and BCPlantTaxonomy v19 provenance metadata
#'
#' Inspects the bundled `standards-2026-provenance.json` manifest and verifies
#' the SHA-256 digest of the active or bundled `VLists.db` reference database.
#'
#' @param vlists_path Optional path to a `VLists.db` SQLite database to verify.
#'   Defaults to the bundled 2026 `VLists.db`.
#' @return A list containing `schema_version`, `sources` tibble (`BECdb_v13_2026`,
#'   `BCPlantTaxa_v19_2025`), `lmh25_pdf_sha256`, `vlists_path`, `vlists_sha256`,
#'   `expected_vlists_sha256`, and `verified` (`logical`).
#' @export
vpro_standards <- function(vlists_path = NULL) {
  prov_path <- vpro_bundled_file("extdata", "standards-2026-provenance.json")
  raw <- jsonlite::fromJSON(prov_path, simplifyVector = FALSE)

  sources_rows <- lapply(raw$sources, function(s) {
    tibble::tibble(
      archive_name = as.character(s$archiveName),
      extracted_name = as.character(s$extractedName),
      version = as.character(s$version),
      archive_sha256 = as.character(s$archiveSha256),
      extracted_sha256 = as.character(s$extractedSha256)
    )
  })
  sources_tbl <- do.call(rbind, sources_rows)

  expected_vlists_sha <- NA_character_
  for (art in raw$artifacts) {
    if (identical(art$path, "resources/database-family/VLists.db")) {
      expected_vlists_sha <- tolower(as.character(art$sha256))
      break
    }
  }

  resolved_vlists <- if (is.null(vlists_path) || !nzchar(vlists_path)) {
    vpro_bundled_db("VLists.db")
  } else {
    normalizePath(vlists_path, winslash = "/", mustWork = TRUE)
  }
  actual_sha <- vpro_sha256_file(resolved_vlists)

  list(
    schema_version = as.integer(raw$schemaVersion),
    sources = sources_tbl,
    lmh25_pdf_sha256 = as.character(raw$lmh25Pdf2023Sha256),
    vlists_path = resolved_vlists,
    vlists_sha256 = actual_sha,
    expected_vlists_sha256 = expected_vlists_sha,
    verified = !is.na(expected_vlists_sha) && identical(actual_sha, expected_vlists_sha)
  )
}

#' Inspect VPro workspace, 2026 standards, and R ecosystem readiness
#'
#' Reports cross-OS VPro workspace directories (`vpro_data_dir()` and
#' `vpro_config_dir()`), active project/SU/hierarchy/profile settings (from `ws`
#' or `config.yml` when present), 7-DB SQLite family availability, 2026 `BECdb v13`
#' and `BCPlantTaxonomy v19` SHA-256 verification, `climr` local raster cache
#' availability, and installed versions of companion R packages.
#'
#' @param ws Optional active `vpro_workspace` handle from [vpro_connect()].
#'   When supplied, reports status using `ws$data_dir`, `ws$config_dir`, and the
#'   live workspace selection (`ws$project`, `ws$su`, `ws$hierarchy`, `ws$lump`).
#' @param data_dir Workspace data directory (defaults to [vpro_data_dir()] or
#'   `ws$data_dir` when `ws` is supplied).
#' @param config_dir Workspace config directory (defaults to [vpro_config_dir()]
#'   or `ws$config_dir` when `ws` is supplied).
#' @return An S3 object of class `vpro_status` with `print()` and `as_tibble()`
#'   methods.
#' @export
vpro_status <- function(ws = NULL, data_dir = vpro_data_dir(), config_dir = vpro_config_dir()) {
  if (!is.null(ws)) {
    vpro_assert_workspace(ws)
    if (missing(data_dir) && !is.null(ws$data_dir) && nzchar(ws$data_dir)) {
      data_dir <- ws$data_dir
    }
    if (missing(config_dir) && !is.null(ws$config_dir) && nzchar(ws$config_dir)) {
      config_dir <- ws$config_dir
    }
  }
  data_dir <- normalizePath(data_dir, winslash = "/", mustWork = FALSE)
  config_dir <- normalizePath(config_dir, winslash = "/", mustWork = FALSE)
  config_path <- file.path(config_dir, "config.yml")
  has_config <- file.exists(config_path)

  active <- list(
    project = NA_character_,
    su = NA_character_,
    hierarchy = NA_character_,
    profile = NA_character_,
    project_path = NA_character_,
    su_path = NA_character_,
    hierarchy_path = NA_character_,
    lump = NA_character_
  )
  chr_or_na <- function(val) {
    if (is.null(val) || length(val) == 0L || is.na(val[[1L]]) || !nzchar(trimws(as.character(val[[1L]])))) {
      NA_character_
    } else {
      as.character(val[[1L]])
    }
  }
  if (has_config) {
    cfg <- tryCatch(yaml::read_yaml(config_path, readLines.warn = FALSE), error = function(e) NULL)
    if (is.list(cfg) && is.list(cfg$Current)) {
      cur <- cfg$Current
      active$project <- chr_or_na(cur$CurrProject)
      active$su <- chr_or_na(cur$CurrPlotlist)
      active$hierarchy <- chr_or_na(cur$CurrHierarchy)
      active$profile <- chr_or_na(cur$CurrVegProfile)
      active$project_path <- chr_or_na(cur$ProjectPath)
      active$su_path <- chr_or_na(cur$SUPath)
      active$hierarchy_path <- chr_or_na(cur$HierarchyPath)
      active$lump <- chr_or_na(cur$CurrLump)
    }
  }
  if (!is.null(ws)) {
    active$project <- chr_or_na(ws$project)
    active$su <- chr_or_na(ws$su)
    active$hierarchy <- chr_or_na(ws$hierarchy)
    active$project_path <- chr_or_na(ws$project_path)
    active$su_path <- chr_or_na(ws$su_path)
    active$hierarchy_path <- chr_or_na(ws$hierarchy_path)
    active$lump <- chr_or_na(ws$lump)
  }

  family_names <- c("VPro64.db", "VLists.db", "VUser.db", "VMetaData.db", "VMessageBoard.db", "VPics.db")
  family_tbl <- tibble::tibble(
    database = family_names,
    workspace_path = vapply(family_names, function(nm) {
      candidates <- c(
        file.path(data_dir, nm),
        file.path(data_dir, "database-family", nm),
        file.path(data_dir, "pics", nm)
      )
      hit <- candidates[file.exists(candidates)]
      if (length(hit) > 0L) normalizePath(hit[[1L]], winslash = "/", mustWork = FALSE) else NA_character_
    }, character(1)),
    present_in_workspace = !is.na(vapply(family_names, function(nm) {
      candidates <- c(
        file.path(data_dir, nm),
        file.path(data_dir, "database-family", nm),
        file.path(data_dir, "pics", nm)
      )
      hit <- candidates[file.exists(candidates)]
      if (length(hit) > 0L) hit[[1L]] else NA_character_
    }, character(1)))
  )

  ws_vlists <- family_tbl$workspace_path[family_tbl$database == "VLists.db"]
  standards <- vpro_standards(if (!is.na(ws_vlists)) ws_vlists else NULL)

  ecosystem_pkgs <- c(
    "DBI", "RSQLite", "RPostgres", "data.table", "tibble", "vegan", "vegclust",
    "indicspecies", "labdsv", "sf", "terra", "climr", "duckdb",
    "mdbr", "ggplot2", "quarto", "writexl"
  )
  pkg_installed <- vapply(ecosystem_pkgs, requireNamespace, logical(1), quietly = TRUE)
  pkg_version <- vapply(seq_along(ecosystem_pkgs), function(i) {
    if (pkg_installed[[i]]) as.character(utils::packageVersion(ecosystem_pkgs[[i]])) else NA_character_
  }, character(1))
  packages_tbl <- tibble::tibble(
    package = ecosystem_pkgs,
    installed = pkg_installed,
    version = pkg_version
  )

  climr_cache <- NA_character_
  climr_rasters <- FALSE
  if (isTRUE(pkg_installed[["climr"]])) {
    climr_cache <- tryCatch(as.character(climr::cache_path()), error = function(e) NA_character_)
    if (!is.na(climr_cache) && nzchar(climr_cache) && dir.exists(climr_cache)) {
      tifs <- list.files(climr_cache, pattern = "\\.(tif|tiff|vrt)$", recursive = TRUE, ignore.case = TRUE)
      climr_rasters <- length(tifs) > 0L
    }
  }

  structure(
    list(
      r_version = R.version.string,
      data_dir = data_dir,
      data_dir_exists = dir.exists(data_dir),
      config_dir = config_dir,
      config_path = config_path,
      config_exists = has_config,
      active = active,
      family = family_tbl,
      standards = standards,
      packages = packages_tbl,
      climr_cache_dir = climr_cache,
      climr_rasters_cached = climr_rasters
    ),
    class = "vpro_status"
  )
}

#' @export
print.vpro_status <- function(x, ...) {
  cli::cli_h2("vpro 2.0 Companion SDK Status")
  cli::cli_bullets(c(
    "*" = "Data dir: {.path {x$data_dir}} ({if (x$data_dir_exists) 'present' else 'absent'})",
    "*" = "Config: {.path {x$config_path}} ({if (x$config_exists) 'present' else 'absent'})",
    "*" = "Active project: {.val {if (is.na(x$active$project)) '<none>' else x$active$project}} (SU: {.val {if (is.na(x$active$su)) '<none>' else x$active$su}})",
    "*" = "2026 Standards (`VLists.db` SHA-256): {if (isTRUE(x$standards$verified)) 'verified' else 'custom/unverified'}",
    "*" = "Ecosystem packages installed: {sum(x$packages$installed)}/{nrow(x$packages)} (climr rasters cached: {x$climr_rasters_cached})"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_status <- function(x, ...) {
  x$packages
}
