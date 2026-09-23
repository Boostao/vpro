# Report quality filtering --------------------------------------------------

vpro_quality_empty_selected <- function() {
  data.frame(
    PlotNumber = character(),
    SiteUnit = character(),
    stringsAsFactors = FALSE
  )
}

vpro_quality_empty_removed <- function() {
  data.frame(
    PlotNumber = character(),
    SiteUnit = character(),
    SitePlotQuality = character(),
    VegPlotQuality = character(),
    SoilPlotQuality = character(),
    BEC_Use = character(),
    removed_by = character(),
    failed_criteria = character(),
    stringsAsFactors = FALSE
  )
}

vpro_quality_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", argument, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

vpro_quality_text <- function(value, argument, allow_null = FALSE) {
  if (allow_null && is.null(value)) {
    return(NULL)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value) || trimws(value) == "") {
    stop("`", argument, "` must be a nonblank character value.", call. = FALSE)
  }
  value
}

vpro_quality_reference <- function(path) {
  if (length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO list-reference database does not exist: ", path, call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, "USysTableOfLists")) {
    stop("VPRO list-reference table does not exist: USysTableOfLists", call. = FALSE)
  }
  required <- c("ListName", "Item", "ItemOrder")
  missing <- setdiff(required, DBI::dbListFields(con, "USysTableOfLists"))
  if (length(missing) > 0L) {
    stop(
      "VPRO list-reference table is missing required fields: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  normalizePath(path)
}

vpro_quality_levels <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  levels <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT "Item", "ItemOrder" FROM "USysTableOfLists"',
      'WHERE "ListName" = \'DataQuality\' COLLATE NOCASE',
      'AND "Item" IS NOT NULL AND "ItemOrder" IS NOT NULL',
      'ORDER BY "ItemOrder", "Item" COLLATE NOCASE'
    )
  )
  all_items <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT DISTINCT "Item" FROM "USysTableOfLists"',
      'WHERE "Item" IS NOT NULL'
    )
  )$Item
  if (nrow(levels) == 0L) {
    stop("VPRO list-reference table has no DataQuality levels.", call. = FALSE)
  }
  keys <- tolower(levels$Item)
  duplicates <- unique(keys[duplicated(keys)])
  if (length(duplicates) > 0L) {
    stop(
      "VPRO DataQuality levels contain duplicate labels: ",
      paste(duplicates, collapse = ", "),
      call. = FALSE
    )
  }
  if (any(!is.finite(levels$ItemOrder))) {
    stop("VPRO DataQuality ItemOrder values must be finite numbers.", call. = FALSE)
  }
  structure(
    data.frame(
      label = levels$Item,
      key = keys,
      order = as.numeric(levels$ItemOrder),
      stringsAsFactors = FALSE
    ),
    all_item_keys = unique(tolower(all_items))
  )
}

vpro_quality_threshold <- function(levels, value, argument) {
  value <- vpro_quality_text(value, argument)
  index <- match(tolower(value), levels$key)
  if (is.na(index)) {
    stop(
      "`",
      argument,
      "` is not a configured DataQuality level: ",
      value,
      call. = FALSE
    )
  }
  list(label = levels$label[[index]], order = levels$order[[index]])
}

vpro_quality_source <- function(
  context,
  con,
  project,
  include_quality = TRUE,
  include_bec = TRUE
) {
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for report quality filtering.", call. = FALSE)
  }
  su_record <- context$active_su
  if (normalizePath(su_record$path) == normalizePath(project$path)) {
    su <- DBI::dbQuoteIdentifier(con, su_record$table)
  } else {
    vpro_environment_validation_attach(con, su_record$path, "vpro_quality_su")
    su <- paste(
      DBI::dbQuoteIdentifier(con, "vpro_quality_su"),
      DBI::dbQuoteIdentifier(con, su_record$table),
      sep = "."
    )
  }
  if (!include_quality) {
    return(DBI::dbGetQuery(
      con,
      paste(
        'SELECT CAST(su."PlotNumber" AS TEXT) AS "PlotNumber",',
        'CAST(su."SiteUnit" AS TEXT) AS "SiteUnit"',
        "FROM",
        su,
        "AS su",
        'ORDER BY su."PlotNumber", su."SiteUnit"'
      )
    ))
  }

  env <- DBI::dbQuoteIdentifier(
    con,
    vpro_project_table(project$project, "Env")
  )
  admin_table <- vpro_project_table(project$project, "Admin")
  admin <- DBI::dbQuoteIdentifier(con, admin_table)
  required <- c(
    "Plot",
    "SitePlotQuality",
    "VegPlotQuality",
    "SoilPlotQuality"
  )
  if (include_bec) {
    required <- c(required, "BEC_Use")
  }
  missing <- setdiff(required, DBI::dbListFields(con, admin_table))
  if (length(missing) > 0L) {
    stop(
      "VPRO Admin table is missing quality fields: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  bec_select <- if (include_bec) {
    'CAST(admin."BEC_Use" AS TEXT) AS "BEC_Use",'
  } else {
    'CAST(NULL AS TEXT) AS "BEC_Use",'
  }
  DBI::dbGetQuery(
    con,
    paste(
      'SELECT CAST(su."PlotNumber" AS TEXT) AS "PlotNumber",',
      'CAST(su."SiteUnit" AS TEXT) AS "SiteUnit",',
      'CAST(admin."SitePlotQuality" AS TEXT) AS "SitePlotQuality",',
      'CAST(admin."VegPlotQuality" AS TEXT) AS "VegPlotQuality",',
      'CAST(admin."SoilPlotQuality" AS TEXT) AS "SoilPlotQuality",',
      bec_select,
      'CASE WHEN env."PlotNumber" IS NOT NULL AND admin."Plot" IS NOT NULL',
      'THEN 1 ELSE 0 END AS "complete_project_plot"',
      "FROM",
      su,
      "AS su",
      "LEFT JOIN",
      env,
      'AS env ON su."PlotNumber" = env."PlotNumber"',
      "LEFT JOIN",
      admin,
      'AS admin ON env."PlotNumber" = admin."Plot"',
      'ORDER BY su."PlotNumber", su."SiteUnit"'
    )
  )
}

vpro_quality_orders <- function(values, levels) {
  levels$order[match(tolower(values), levels$key)]
}

vpro_quality_pass <- function(values, orders, threshold, include_missing, all_item_keys) {
  unmatched <- is.na(orders)
  collides <- !is.na(values) & tolower(values) %in% all_item_keys
  (!unmatched & orders >= threshold) |
    (unmatched & !collides & include_missing)
}

vpro_quality_bec_pass <- function(values, threshold, include_missing) {
  missing <- is.na(values)
  comparison <- rep(FALSE, length(values))
  comparison[!missing] <- vapply(
    values[!missing],
    function(value) {
      value <- tolower(enc2utf8(value))
      threshold <- tolower(enc2utf8(threshold))
      identical(value, threshold) ||
        sort(
          c(value, threshold),
          method = "radix"
        )[[1]] ==
          threshold
    },
    logical(1)
  )
  comparison | (missing & include_missing)
}

vpro_quality_removed <- function(source, failures) {
  removed <- source[
    !failures$selected,
    c(
      "PlotNumber",
      "SiteUnit",
      "SitePlotQuality",
      "VegPlotQuality",
      "SoilPlotQuality",
      "BEC_Use"
    ),
    drop = FALSE
  ]
  if (nrow(removed) == 0L) {
    return(vpro_quality_empty_removed())
  }
  labels <- c("Project", "Site", "Veg", "Soil", "BEC")
  failed <- failures[!failures$selected, labels, drop = FALSE]
  failed_names <- apply(failed, 1L, function(row) labels[as.logical(row)])
  removed$removed_by <- vapply(
    failed_names,
    function(value) if (length(value) == 1L) value else "Mixed",
    character(1)
  )
  removed$failed_criteria <- vapply(
    failed_names,
    paste,
    collapse = ",",
    character(1)
  )
  rownames(removed) <- NULL
  removed
}

#' Filter an active VPRO site unit by report quality
#'
#' Translates `V7mdlReportsQualityControl.QC` and `QCLV` without creating
#' `USysDeleteMe_SU` or changing the current plot list. Site, vegetation, and
#' soil quality labels are ranked by `USysTableOfLists` `DataQuality` rows.
#' Thresholds are inclusive. Missing values and labels absent from every list
#' follow the legacy joined-null branch and are controlled by the corresponding
#' `include_*_missing` argument. Labels belonging to another list are excluded.
#'
#' Supplying `bec_min` enables the short-report BEC predicate from `QC`.
#' `bec_min = NULL` reproduces the long-report `QCLV` scope. The BEC comparison
#' remains a case-insensitive lexical `>=` comparison, matching the Access SQL;
#' it does not use the BEC list's numeric `ItemOrder`.
#'
#' @param context A VPRO project context with an active project and active SU.
#' @param reference_path Path to a SQLite database containing
#'   `USysTableOfLists`. Defaults to the bundled VLists database.
#' @param enforce Whether to apply quality filtering. If `FALSE`, the active SU
#'   is returned unchanged and reference metadata is not consulted.
#' @param site_min,veg_min,soil_min Minimum configured `DataQuality` labels.
#' @param include_site_missing,include_veg_missing,include_soil_missing Whether
#'   missing or unrecognized values pass each quality criterion.
#' @param bec_min Optional lexical minimum for `BEC_Use`. Use `NULL` to omit BEC
#'   filtering, as in the Access long-vegetation report.
#' @param include_bec_missing Whether missing `BEC_Use` values pass when
#'   `bec_min` is supplied.
#'
#' @return A list with deterministic `selected` and `removed` data frames and a
#'   `thresholds` list. Removal diagnostics report `Project`, `Site`, `Veg`,
#'   `Soil`, `BEC`, or `Mixed`, plus all failed criteria.
#' @export
vpro_filter_plot_quality <- function(
  context,
  reference_path = vpro_bundled_file("extdata", "VLists.db"),
  enforce = TRUE,
  site_min = "Poor",
  veg_min = "Poor",
  soil_min = "Poor",
  include_site_missing = TRUE,
  include_veg_missing = TRUE,
  include_soil_missing = TRUE,
  bec_min = NULL,
  include_bec_missing = TRUE
) {
  project <- vpro_plot_active(context)
  enforce <- vpro_quality_flag(enforce, "enforce")
  include_site_missing <- vpro_quality_flag(
    include_site_missing,
    "include_site_missing"
  )
  include_veg_missing <- vpro_quality_flag(
    include_veg_missing,
    "include_veg_missing"
  )
  include_soil_missing <- vpro_quality_flag(
    include_soil_missing,
    "include_soil_missing"
  )
  include_bec_missing <- vpro_quality_flag(
    include_bec_missing,
    "include_bec_missing"
  )
  bec_min <- vpro_quality_text(bec_min, "bec_min", allow_null = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  source <- vpro_quality_source(
    context,
    con,
    project,
    include_quality = enforce,
    include_bec = !is.null(bec_min)
  )

  if (!enforce) {
    selected <- source[c("PlotNumber", "SiteUnit")]
    rownames(selected) <- NULL
    return(list(
      selected = selected,
      removed = vpro_quality_empty_removed(),
      thresholds = NULL
    ))
  }

  reference_path <- vpro_quality_reference(reference_path)
  levels <- vpro_quality_levels(reference_path)
  site <- vpro_quality_threshold(levels, site_min, "site_min")
  veg <- vpro_quality_threshold(levels, veg_min, "veg_min")
  soil <- vpro_quality_threshold(levels, soil_min, "soil_min")

  site_pass <- vpro_quality_pass(
    source$SitePlotQuality,
    vpro_quality_orders(source$SitePlotQuality, levels),
    site$order,
    include_site_missing,
    attr(levels, "all_item_keys")
  )
  veg_pass <- vpro_quality_pass(
    source$VegPlotQuality,
    vpro_quality_orders(source$VegPlotQuality, levels),
    veg$order,
    include_veg_missing,
    attr(levels, "all_item_keys")
  )
  soil_pass <- vpro_quality_pass(
    source$SoilPlotQuality,
    vpro_quality_orders(source$SoilPlotQuality, levels),
    soil$order,
    include_soil_missing,
    attr(levels, "all_item_keys")
  )
  bec_pass <- if (is.null(bec_min)) {
    rep(TRUE, nrow(source))
  } else {
    vpro_quality_bec_pass(source$BEC_Use, bec_min, include_bec_missing)
  }
  complete <- source$complete_project_plot == 1L
  failures <- data.frame(
    selected = complete & site_pass & veg_pass & soil_pass & bec_pass,
    Project = !complete,
    Site = complete & !site_pass,
    Veg = complete & !veg_pass,
    Soil = complete & !soil_pass,
    BEC = complete & !bec_pass,
    stringsAsFactors = FALSE
  )
  selected <- source[failures$selected, c("PlotNumber", "SiteUnit"), drop = FALSE]
  rownames(selected) <- NULL

  list(
    selected = selected,
    removed = vpro_quality_removed(source, failures),
    thresholds = list(
      site = site,
      veg = veg,
      soil = soil,
      bec = bec_min,
      include_site_missing = include_site_missing,
      include_veg_missing = include_veg_missing,
      include_soil_missing = include_soil_missing,
      include_bec_missing = if (is.null(bec_min)) NULL else include_bec_missing
    )
  )
}
