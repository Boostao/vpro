# VP08 Quick Summary data ---------------------------------------------------

#' Return VP08 Quick Summary data for the active project
#'
#' Modernizes the query written by `V7mdlReportsCommonCode.QuickSummaryReport`.
#' The Access query references a historical `_Env.AssignedSiteUnit` field that
#' is absent from VP08; the VP05 import maps that field to `UserSiteUnit`, now
#' stored in `_Admin`. An explicit left join supplies this value while retaining
#' plots whose Admin row is missing. Like the original query, the scope is the
#' entire project regardless of active SU. Vegetation rows use the saved
#' `USysAllVeg` distinct union, not the SU-scoped `QuickVeg` scratch table.
#' No DQY or Excel output is created.
#'
#' @param context A VPRO context with an active VP08 project.
#' @return A data frame with `PlotNumber`, `AssignedSiteUnit` (from Admin
#'   `UserSiteUnit`), `MyLayer`, `Species`, and `Cover`, ordered by layer, plot,
#'   species, and cover. Missing Admin rows have a missing unit label.
#' @export
vpro_report_quick_summary <- function(context) {
  project <- vpro_plot_active(context)
  if (!identical(project$version, "VP08")) {
    stop("Quick Summary requires an active VP08 project.", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  vpro_report_quick_summary_rows(con, project$project)
}

vpro_report_quick_summary_rows <- function(con, project) {
  env_table <- vpro_project_table(project, "Env")
  admin_table <- vpro_project_table(project, "Admin")
  for (entry in list(
    list(table = env_table, fields = "PlotNumber"),
    list(table = admin_table, fields = c("Plot", "UserSiteUnit"))
  )) {
    if (!DBI::dbExistsTable(con, entry$table) ||
        !all(entry$fields %in% DBI::dbListFields(con, entry$table))) {
      stop("Quick Summary requires VP08 Env and Admin plot/unit fields.", call. = FALSE)
    }
  }
  veg_sql <- vpro_report_all_veg_sql(con, vpro_project_table(project, "Veg"))
  env <- DBI::dbQuoteIdentifier(con, env_table)
  admin <- DBI::dbQuoteIdentifier(con, admin_table)
  DBI::dbGetQuery(con, paste(
    'SELECT e."PlotNumber" AS "PlotNumber",',
    'a."UserSiteUnit" AS "AssignedSiteUnit",',
    'v."MyLayer", v."Species", v."Cover"',
    'FROM', env, 'AS e',
    'INNER JOIN (', veg_sql, ') AS v ON v."PlotNumber" = e."PlotNumber"',
    'LEFT JOIN', admin, 'AS a ON a."Plot" = e."PlotNumber"',
    'ORDER BY v."MyLayer", e."PlotNumber", v."Species", v."Cover"'
  ))
}
