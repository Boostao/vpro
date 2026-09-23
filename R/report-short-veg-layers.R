# Bounded short-vegetation layer data ----------------------------------------

vpro_short_veg_layer_mapping <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !file.exists(path) || dir.exists(path)) {
    stop("Short-vegetation mapping database does not exist.", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!all(c("mapping_set", "layer_mapping") %in% DBI::dbListTables(con))) {
    stop("Short-vegetation mapping tables are missing.", call. = FALSE)
  }
  metadata_fields <- c("version", "source_sha256")
  mapping_fields <- c("Layer1234567", "LayerCode", "Strata")
  if (!all(metadata_fields %in% DBI::dbListFields(con, "mapping_set")) ||
      !all(mapping_fields %in% DBI::dbListFields(con, "layer_mapping"))) {
    stop("Short-vegetation mapping fields are missing.", call. = FALSE)
  }
  metadata <- DBI::dbGetQuery(con, 'SELECT "version", "source_sha256" FROM "mapping_set"')
  if (nrow(metadata) != 1L ||
      is.na(metadata$version[[1L]]) ||
      is.na(metadata$source_sha256[[1L]]) ||
      !identical(metadata$version[[1L]], "access-layercode-v1") ||
      !identical(metadata$source_sha256[[1L]], "8a03d48c3a7f0e0a2e0868569969ad91603b124ce38febb38b5a3b284e99d510")) {
    stop("Short-vegetation mapping version or source SHA256 is invalid.", call. = FALSE)
  }
  mapping <- DBI::dbGetQuery(con, 'SELECT "Layer1234567", "LayerCode", "Strata" FROM "layer_mapping"')
  report_keys <- c(as.character(1:10), "5a", "5b", "5c")
  report_codes <- c(sprintf("%02d", 1:10), "05a", "05b", "05c")
  report_strata <- c(rep("A", 3L), rep("B", 2L), "C", rep("D", 4L), rep("B", 3L))
  nonnull <- mapping[!is.na(mapping$Layer1234567), , drop = FALSE]
  if (nrow(mapping) != 17L || anyNA(mapping$LayerCode) ||
      any(!nzchar(trimws(mapping$LayerCode))) || anyDuplicated(mapping$LayerCode) ||
      anyNA(nonnull$Strata) || any(!nzchar(trimws(nonnull$Strata))) ||
      any(!nzchar(trimws(nonnull$Layer1234567))) ||
      anyDuplicated(nonnull$Layer1234567) ||
      !setequal(nonnull$Layer1234567, report_keys) ||
      !identical(nonnull$LayerCode[match(report_keys, nonnull$Layer1234567)], report_codes) ||
      !identical(nonnull$Strata[match(report_keys, nonnull$Layer1234567)], report_strata)) {
    stop("Short-vegetation mapping has missing/duplicate keys, invalid strata or row count.", call. = FALSE)
  }
  list(version = metadata$version[[1L]], rows = nonnull)
}

vpro_short_veg_empty_rows <- function() {
  data.frame(SiteUnit = character(), PlotNumber = character(), Species = character(),
             layer = character(), layer_code = character(), strata = character(),
             cover = numeric(), stringsAsFactors = FALSE)
}

#' Return bounded short-vegetation layer data for the active site unit
#'
#' Uses physical SU membership and physical project Veg, not metadata joins or
#' report views. Repeated Veg records for the same plot and species are reduced
#' by independent `MAX` for each of the ten supported cover columns. Non-null
#' zero is retained. Report keys join the versioned `Layer1234567` mapping (not
#' the padded `LayerCode` key). This is layer data, not an Access summary or a
#' taxonomic determination; species values are left unchanged.
#'
#' Null and whitespace-only PlotNumber or SiteUnit memberships are ineligible
#' and counted separately. Other orphan plot memberships remain in the unit
#' denominators when quality is disabled. When enabled, quality filtering uses
#' [vpro_filter_plot_quality()] and can remove orphans through its Project
#' criterion. No source SQLite database is modified.
#'
#' @param context VPRO context with active project and SU.
#' @param mapping_path Versioned SQLite mapping; defaults to the bundled copy.
#' @param enforce_quality Apply report quality criteria; defaults to `FALSE`.
#' @param reference_path Bundled VLists SQLite database by default, used only
#'   when quality is enforced.
#' @param site_min,veg_min,soil_min Inclusive quality thresholds.
#' @param include_site_missing,include_veg_missing,include_soil_missing Whether
#'   missing/unrecognized qualities pass their respective criteria.
#' @param bec_min Optional lexical BEC minimum; `NULL` disables BEC filtering.
#' @param include_bec_missing Whether missing BEC passes when BEC is enabled.
#' @return A list containing `rows` (SiteUnit, PlotNumber, Species, layer,
#'   layer_code, strata, numeric cover), `units` (SiteUnit, integer n_plots
#'   counting unique eligible SU plot memberships including orphans), and
#'   `diagnostics` (mapping_version, quality_applied, quality_removed,
#'   quality_thresholds, excluded_null_or_blank_plot_rows,
#'   excluded_null_or_blank_unit_rows, duplicate_membership_rows and
#'   eligible_memberships). Duplicate count is excess rows per SU/plot pair.
#' @export
vpro_report_short_veg_layers <- function(
  context,
  mapping_path = vpro_bundled_file("extdata", "short-veg-layer-mapping-v1.sqlite"),
  enforce_quality = FALSE,
  reference_path = vpro_bundled_file("extdata", "VLists.db"),
  site_min = "Poor", veg_min = "Poor", soil_min = "Poor",
  include_site_missing = TRUE, include_veg_missing = TRUE,
  include_soil_missing = TRUE, bec_min = NULL, include_bec_missing = TRUE
) {
  project <- vpro_plot_active(context)
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for short-vegetation layers.", call. = FALSE)
  }
  enforce_quality <- vpro_quality_flag(enforce_quality, "enforce_quality")
  mapping <- vpro_short_veg_layer_mapping(mapping_path)
  # Always inspect physical membership before quality filtering to account for
  # excluded blanks and duplicates even when quality removes those rows.
  membership <- vpro_filter_plot_quality(context, enforce = FALSE)$selected
  invalid_plot <- is.na(membership$PlotNumber) | !nzchar(trimws(membership$PlotNumber))
  invalid_unit <- is.na(membership$SiteUnit) | !nzchar(trimws(membership$SiteUnit))
  valid <- membership[!(invalid_plot | invalid_unit), , drop = FALSE]
  duplicates <- nrow(valid) - nrow(unique(valid))
  valid <- unique(valid)
  quality <- if (enforce_quality) {
    vpro_filter_plot_quality(
      context, reference_path = reference_path, enforce = TRUE,
      site_min = site_min, veg_min = veg_min, soil_min = soil_min,
      include_site_missing = include_site_missing,
      include_veg_missing = include_veg_missing,
      include_soil_missing = include_soil_missing, bec_min = bec_min,
      include_bec_missing = include_bec_missing
    )
  } else {
    list(selected = valid, removed = vpro_quality_empty_removed(), thresholds = NULL)
  }
  selected <- unique(quality$selected)
  selected <- selected[!is.na(selected$PlotNumber) & nzchar(trimws(selected$PlotNumber)) &
                         !is.na(selected$SiteUnit) & nzchar(trimws(selected$SiteUnit)), , drop = FALSE]
  selected <- selected[order(selected$SiteUnit, selected$PlotNumber, method = "radix"), , drop = FALSE]
  rownames(selected) <- NULL
  unit_names <- as.character(sort(unique(selected$SiteUnit), method = "radix"))
  units <- data.frame(SiteUnit = unit_names,
                      n_plots = as.integer(tabulate(match(selected$SiteUnit, unit_names),
                                                    nbins = length(unit_names))),
                      stringsAsFactors = FALSE)

  veg_path <- project$path
  veg_table <- vpro_project_table(project$project, "Veg")
  veg <- DBI::dbConnect(RSQLite::SQLite(), veg_path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(veg), add = TRUE)
  layer_order <- c(as.character(1:5), "5a", "5b", "5c", "6", "7")
  covers <- paste0("Cover", layer_order)
  required <- c("PlotNumber", "Species", covers)
  missing <- if (DBI::dbExistsTable(veg, veg_table)) {
    setdiff(required, DBI::dbListFields(veg, veg_table))
  } else {
    required
  }
  if (length(missing) > 0L) {
    stop("Short-vegetation Veg table is missing required fields: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  rows <- vpro_short_veg_empty_rows()
  if (nrow(selected) > 0L) {
    table_sql <- DBI::dbQuoteIdentifier(veg, veg_table)
    columns <- paste(vapply(covers, function(field) paste0("MAX(", DBI::dbQuoteIdentifier(veg, field),
                                                           ") AS ", DBI::dbQuoteIdentifier(veg, field)), character(1)),
                     collapse = ", ")
    plots <- unique(selected$PlotNumber)
    # Parameter chunks keep the SQLite variable limit independent of SU size.
    groups <- lapply(split(plots, ceiling(seq_along(plots) / 500L)), function(chunk) {
      DBI::dbGetQuery(veg, paste0('SELECT "PlotNumber", "Species", ', columns,
                                  " FROM ", table_sql,
                                  ' WHERE "PlotNumber" IN (', paste(rep("?", length(chunk)), collapse = ","),
                                  ') GROUP BY "PlotNumber", "Species"'), params = as.list(chunk))
    })
    grouped <- do.call(rbind, groups)
    parts <- lapply(layer_order, function(layer) {
      field <- paste0("Cover", layer)
      present <- !is.na(grouped[[field]])
      if (!any(present)) return(NULL)
      pair <- merge(selected, grouped[present, c("PlotNumber", "Species", field), drop = FALSE],
                    by = "PlotNumber", sort = FALSE)
      map <- mapping$rows[match(layer, mapping$rows$Layer1234567), , drop = FALSE]
      if (nrow(map) != 1L || is.na(map$LayerCode)) {
        stop("Short-vegetation report layer has no unique mapping: ", layer, call. = FALSE)
      }
      data.frame(SiteUnit = pair$SiteUnit, PlotNumber = pair$PlotNumber,
                 Species = pair$Species, layer = layer, layer_code = map$LayerCode,
                 strata = map$Strata, cover = as.numeric(pair[[field]]),
                 stringsAsFactors = FALSE)
    })
    parts <- Filter(Negate(is.null), parts)
    if (length(parts)) rows <- do.call(rbind, parts)
  }
  if (nrow(rows)) rows <- rows[order(rows$SiteUnit, rows$PlotNumber, rows$Species,
                                    match(rows$layer, layer_order),
                                    method = "radix"), , drop = FALSE]
  rownames(rows) <- NULL
  list(rows = rows, units = units, diagnostics = list(
    mapping_version = mapping$version, quality_applied = enforce_quality,
    quality_removed = quality$removed, quality_thresholds = quality$thresholds,
    excluded_null_or_blank_plot_rows = as.integer(sum(invalid_plot)),
    excluded_null_or_blank_unit_rows = as.integer(sum(invalid_unit)),
    duplicate_membership_rows = as.integer(duplicates),
    eligible_memberships = nrow(selected)
  ))
}
