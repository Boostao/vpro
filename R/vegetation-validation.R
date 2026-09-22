# Vegetation validation -----------------------------------------------------

vpro_vegetation_reference <- function(path) {
  if (length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO species-reference database does not exist: ", path, call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, "USysAllSpecs")) {
    stop("VPRO species-reference table does not exist: USysAllSpecs", call. = FALSE)
  }
  fields <- DBI::dbListFields(con, "USysAllSpecs")
  if (!"Code" %in% fields) {
    stop("VPRO species-reference table must contain a Code field.", call. = FALSE)
  }
  normalizePath(path)
}

vpro_vegetation_validation_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", argument, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

vpro_vegetation_attach <- function(con, path, alias) {
  DBI::dbExecute(
    con,
    paste(
      "ATTACH DATABASE",
      DBI::dbQuoteString(con, normalizePath(path)),
      "AS",
      DBI::dbQuoteIdentifier(con, alias)
    )
  )
  invisible(TRUE)
}

#' Find vegetation species codes absent from the VPRO master list
#'
#' Reproduces the query in `V7mdlReportsValidateVegCodes.CheckVegData`. Without
#' an active SU, every row in the active project's `_Veg` table is checked.
#' With an active SU, validation starts from that SU and follows the Access
#' left-join shape. The operation uses `USysAllSpecs` directly; user species and
#' the filtered `USysAllSpecies` query are intentionally not included.
#'
#' Matching uses SQLite `NOCASE` collation to approximate Access database text
#' comparison. Findings are deduplicated and sorted for deterministic package
#' output. Null and blank species values are not removed. Under the legacy SU
#' join, an SU plot with no vegetation contributes one row with missing plot and
#' species values.
#'
#' @param context A VPRO project context with an active project.
#' @param reference_path Path to a SQLite database containing `USysAllSpecs`.
#'   Defaults to the bundled VLists database.
#' @param use_active_su Whether to restrict validation through the active SU when
#'   one is selected. Set to `FALSE` to validate the complete active project.
#'
#' @return A data frame containing distinct `PlotNumber` and `Species` findings,
#'   sorted deterministically.
#' @export
vpro_validate_vegetation_codes <- function(
  context,
  reference_path = vpro_bundled_file("extdata", "VLists.db"),
  use_active_su = TRUE
) {
  project <- vpro_plot_active(context)
  reference_path <- vpro_vegetation_reference(reference_path)
  use_active_su <- vpro_vegetation_validation_flag(use_active_su, "use_active_su")

  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  vpro_vegetation_attach(con, reference_path, "vpro_species_reference")

  veg <- DBI::dbQuoteIdentifier(con, vpro_project_table(project$project, "Veg"))
  specs <- paste(
    DBI::dbQuoteIdentifier(con, "vpro_species_reference"),
    DBI::dbQuoteIdentifier(con, "USysAllSpecs"),
    sep = "."
  )

  if (use_active_su && !is.null(context$active_su)) {
    su_record <- context$active_su
    if (normalizePath(su_record$path) == normalizePath(project$path)) {
      su <- DBI::dbQuoteIdentifier(con, su_record$table)
    } else {
      vpro_vegetation_attach(con, su_record$path, "vpro_active_su")
      su <- paste(
        DBI::dbQuoteIdentifier(con, "vpro_active_su"),
        DBI::dbQuoteIdentifier(con, su_record$table),
        sep = "."
      )
    }
    sql <- paste(
      'SELECT DISTINCT veg."PlotNumber" AS "PlotNumber", veg."Species" AS "Species"',
      "FROM",
      su,
      "AS su LEFT JOIN (",
      veg,
      "AS veg LEFT JOIN",
      specs,
      'AS specs ON veg."Species" = specs."Code" COLLATE NOCASE)',
      'ON su."PlotNumber" = veg."PlotNumber"',
      'WHERE specs."Code" IS NULL AND su."PlotNumber" IS NOT NULL',
      'ORDER BY veg."PlotNumber", veg."Species"'
    )
  } else {
    sql <- paste(
      'SELECT DISTINCT veg."PlotNumber" AS "PlotNumber", veg."Species" AS "Species"',
      "FROM",
      veg,
      "AS veg LEFT JOIN",
      specs,
      'AS specs ON veg."Species" = specs."Code" COLLATE NOCASE',
      'WHERE specs."Code" IS NULL',
      'ORDER BY veg."PlotNumber", veg."Species"'
    )
  }

  DBI::dbGetQuery(con, sql)
}
