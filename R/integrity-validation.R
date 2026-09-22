# Read-only project and site-unit integrity checks -------------------------

#' Diagnose orphan records and plots without vegetation
#'
#' Translates the read-only queries in `V7mdlReportValidation.One2ManyCheck`,
#' `SuRecordsWoEnvRecords`, and `PlotRecordsWoVegRecords`. Checks use physical
#' project tables, not the active `USysEnv` view: orphan children are checked
#' project-wide, while plots without vegetation follow the active SU by default.
#' No rows are repaired or deleted.
#'
#' @param context A VPRO context with an active project.
#' @param use_active_su Whether to limit the no-vegetation result through the
#'   active SU, when present. SU orphans are reported whenever an SU is active.
#'
#' @return A list of data frames: `orphan_children` (`Table`, `PlotNumber`),
#'   `orphan_su` (`PlotNumber`, `SiteUnit`), and `plots_without_vegetation`
#'   (`PlotNumber`). Null child plot numbers are excluded, but null SU plot
#'   numbers and blank strings are retained. Results are distinct and ordered.
#' @export
vpro_validate_project_integrity <- function(context, use_active_su = TRUE) {
  project <- vpro_plot_active(context)
  use_active_su <- vpro_vegetation_validation_flag(use_active_su, "use_active_su")
  con <- context$con
  env <- vpro_project_relation(context, project, "Env")
  veg <- vpro_project_relation(context, project, "Veg")

  children <- lapply(c("Humus", "Other", "Mineral", "Veg", "Audit"), function(suffix) {
    child <- vpro_project_relation(context, project, suffix)
    result <- DBI::dbGetQuery(con, paste(
      'SELECT DISTINCT child."PlotNumber" AS "PlotNumber" FROM', child,
      'AS child LEFT JOIN', env,
      'AS env ON child."PlotNumber" = env."PlotNumber"',
      'WHERE child."PlotNumber" IS NOT NULL AND env."PlotNumber" IS NULL',
      'ORDER BY child."PlotNumber"'
    ))
    data.frame(
      Table = rep(if (suffix == "Veg") "Vegetation" else suffix, nrow(result)),
      PlotNumber = as.character(result$PlotNumber),
      stringsAsFactors = FALSE
    )
  })
  orphan_children <- do.call(rbind, children)
  rownames(orphan_children) <- NULL

  orphan_su <- data.frame(PlotNumber = character(), SiteUnit = character())
  su <- NULL
  if (!is.null(context$active_su)) {
    su <- vpro_su_relation(context, context$active_su)
    orphan_su <- DBI::dbGetQuery(con, paste(
      'SELECT DISTINCT su."PlotNumber" AS "PlotNumber", su."SiteUnit" AS "SiteUnit"',
      'FROM', su, 'AS su LEFT JOIN', env,
      'AS env ON su."PlotNumber" = env."PlotNumber"',
      'WHERE env."PlotNumber" IS NULL',
      'ORDER BY su."PlotNumber" NULLS FIRST, su."SiteUnit" NULLS FIRST'
    ))
  }

  su_join <- if (use_active_su && !is.null(su)) {
    paste('INNER JOIN', su, 'AS su ON env."PlotNumber" = su."PlotNumber"')
  } else {
    ""
  }
  plots_without_vegetation <- DBI::dbGetQuery(con, paste(
    'SELECT DISTINCT env."PlotNumber" AS "PlotNumber" FROM', env,
    'AS env LEFT JOIN', veg,
    'AS veg ON env."PlotNumber" = veg."PlotNumber"',
    su_join,
    'WHERE veg."PlotNumber" IS NULL',
    'ORDER BY env."PlotNumber" NULLS FIRST'
  ))

  list(
    orphan_children = orphan_children,
    orphan_su = orphan_su,
    plots_without_vegetation = plots_without_vegetation
  )
}
