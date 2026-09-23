# Report vegetation layer rows -----------------------------------------------

#' Return the project-wide `USysAllVeg` report rows
#'
#' Translates the saved Access `USysAllVeg` query on the active project's
#' physical vegetation table. Non-null cover values from layers 1–7, 5a–5c,
#' A, and B are combined with `UNION`, so identical plot/layer/species/cover
#' rows collapse. The query does not filter to the active SU. `Cover8`–`Cover10`
#' and the `USysAllVeg` saved-query UI filter are not part of its SQL.
#'
#' @param context A VPRO context with an active project.
#' @return A data frame with `PlotNumber`, character `MyLayer`, `Species`, and
#'   numeric `Cover`, ordered by layer, plot, species, and cover.
#' @export
vpro_report_all_veg <- function(context) {
  project <- vpro_plot_active(context)
  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_project_table(project$project, "Veg")
  vpro_report_all_veg_rows(con, table)
}

vpro_report_all_veg_rows <- function(con, table) {
  DBI::dbGetQuery(con, paste(
    vpro_report_all_veg_sql(con, table),
    'ORDER BY "MyLayer", "PlotNumber", "Species", "Cover"'
  ))
}

vpro_report_all_veg_sql <- function(con, table) {
  layers <- c(
    "1" = "Cover1", "2" = "Cover2", "3" = "Cover3", "4" = "Cover4",
    "5" = "Cover5", "5a" = "Cover5a", "5b" = "Cover5b", "5c" = "Cover5c",
    "6" = "Cover6", "7" = "Cover7", "A" = "TotalA", "B" = "TotalB"
  )
  required <- c("PlotNumber", "Species", unname(layers))
  if (!DBI::dbExistsTable(con, table) || !all(required %in% DBI::dbListFields(con, table))) {
    stop("The project vegetation table lacks required USysAllVeg fields.", call. = FALSE)
  }
  quoted <- DBI::dbQuoteIdentifier(con, table)
  branches <- vapply(seq_along(layers), function(i) {
    cover <- DBI::dbQuoteIdentifier(con, unname(layers[[i]]))
    paste(
      'SELECT "PlotNumber",', DBI::dbQuoteString(con, names(layers)[[i]]),
      'AS "MyLayer", "Species",', cover, 'AS "Cover" FROM', quoted,
      'WHERE', cover, 'IS NOT NULL'
    )
  }, character(1))
  paste(branches, collapse = " UNION ")
}
