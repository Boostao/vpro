# Site-unit and hierarchy reconciliation ------------------------------------

#' Find unmatched site units and level-11 hierarchy names
#'
#' Translates the read-only queries in
#' `V7mdlReportValidation.Report4SuUnitsWoHierarchyUnits` and
#' `Report4HierarchyUnitsWoSuUnits`. Uses the physical tables of the active SU
#' and hierarchy; project Env membership does not restrict either check.
#' Null and blank names remain findings, and only level-11 hierarchy rows are
#' checked in the reverse direction. Case-insensitive comparison approximates
#' Access text comparison. Results are distinct and deterministically ordered,
#' rather than opening Excel or returning only a Boolean.
#'
#' @param context A VPRO context with an active SU and hierarchy.
#'
#' @return A list of data frames: `su_without_hierarchy` (`SiteUnit`) and
#'   `hierarchy_without_su` (`Level`, `Name`).
#' @export
vpro_validate_su_hierarchy <- function(context) {
  vpro_project_assert_context(context)
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for hierarchy validation.", call. = FALSE)
  }
  if (is.null(context$active_hierarchy)) {
    stop("An active VPRO hierarchy is required for SU validation.", call. = FALSE)
  }

  con <- context$con
  su <- vpro_su_relation(context, context$active_su)
  hierarchy <- vpro_hierarchy_relation(context, context$active_hierarchy)
  su_without_hierarchy <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT DISTINCT su."SiteUnit" AS "SiteUnit" FROM',
      su,
      'AS su LEFT JOIN',
      hierarchy,
      'AS h ON su."SiteUnit" = h."Name" COLLATE NOCASE',
      'WHERE h."Name" IS NULL',
      'ORDER BY su."SiteUnit" NULLS FIRST'
    )
  )
  hierarchy_without_su <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT DISTINCT h."Level" AS "Level", h."Name" AS "Name" FROM',
      hierarchy,
      'AS h LEFT JOIN',
      su,
      'AS su ON h."Name" = su."SiteUnit" COLLATE NOCASE',
      'WHERE h."Level" = 11 AND su."SiteUnit" IS NULL',
      'ORDER BY h."Name" NULLS FIRST'
    )
  )

  list(
    su_without_hierarchy = su_without_hierarchy,
    hierarchy_without_su = hierarchy_without_su
  )
}
