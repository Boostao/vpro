# Location report -----------------------------------------------------------

#' Return plot locations for the active project or site unit
#'
#' Translates the data query in `V7mdlReportLocation.ReportLocation`. Reads the
#' active `USysEnv` view, which is restricted to the active SU when selected;
#' only rows with both latitude and longitude are included. Longitude is
#' multiplied by -1 as in the Access Excel report. The result contains numeric
#' coordinates and plain plot/site-series text, not Excel text prefixes or
#' workbook formatting. No location values are modified.
#'
#' @param context A VPRO project context with an active project.
#' @return A data frame with `PlotNumber`, `Zone`, `SubZone`, `SiteSeries`,
#'   `LocationAccuracy`, `Latitude`, `Longitude`, and `Elevation`, ordered by
#'   plot number. Returns zero rows when no plots have both coordinates.
#' @export
vpro_report_location <- function(context) {
  vpro_plot_active(context)
  DBI::dbGetQuery(
    context$con,
    paste(
      'SELECT "PlotNumber", "Zone", "SubZone", "SiteSeries",',
      '"LocationAccuracy", "Latitude", "Longitude" * -1 AS "Longitude",',
      '"Elevation" FROM "USysEnv"',
      'WHERE "Latitude" IS NOT NULL AND "Longitude" IS NOT NULL',
      'ORDER BY "PlotNumber"'
    )
  )
}
