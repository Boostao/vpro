# Quick vegetation report rows -----------------------------------------------

#' Prepare vegetation cover rows for the active site unit
#'
#' Translates the row selection in
#' `V7mdlReportsCommonCode.QuickVegRecords`: each non-null `Cover1` through
#' `Cover9` becomes a separate row, joined to the active SU by `PlotNumber`.
#' Repeated SU plot rows retain their join multiplicity. This returns data
#' instead of creating or replacing the Access `QuickVeg` scratch table; it
#' does not include `Cover10`, intermediate layers, or Excel formatting.
#'
#' @param context A VPRO context with an active project and active SU.
#' @return A data frame with `PlotNumber`, integer `Layer`, `Species`, and
#'   numeric `Cover`, ordered by layer, plot, species, and cover.
#' @export
vpro_report_quick_veg <- function(context) {
  project <- vpro_plot_active(context)
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for quick vegetation rows.", call. = FALSE)
  }
  con <- context$con
  veg <- vpro_project_relation(context, project, "Veg")
  su <- vpro_su_relation(context, context$active_su)
  required <- c("PlotNumber", "Species", paste0("Cover", 1:9))
  fields <- names(DBI::dbGetQuery(con, paste('SELECT * FROM', veg, 'LIMIT 0')))
  if (!all(required %in% fields)) {
    stop("The active vegetation table lacks required quick-report fields.", call. = FALSE)
  }
  if (!"PlotNumber" %in% names(DBI::dbGetQuery(con, paste('SELECT * FROM', su, 'LIMIT 0')))) {
    stop("The active SU table lacks PlotNumber.", call. = FALSE)
  }
  vpro_quick_veg_rows(con, veg, su)
}

vpro_quick_veg_rows <- function(con, veg, su) {
  branches <- vapply(seq_len(9L), function(layer) {
    cover <- DBI::dbQuoteIdentifier(con, paste0("Cover", layer))
    paste(
      'SELECT veg."PlotNumber" AS "PlotNumber",', layer, 'AS "Layer",',
      'veg."Species" AS "Species", veg.', cover, 'AS "Cover"',
      'FROM', veg, 'AS veg INNER JOIN', su,
      'AS su ON veg."PlotNumber" = su."PlotNumber"',
      'WHERE veg.', cover, 'IS NOT NULL'
    )
  }, character(1))
  DBI::dbGetQuery(con, paste(
    paste(branches, collapse = " UNION ALL "),
    'ORDER BY "Layer", "PlotNumber", "Species", "Cover"'
  ))
}
