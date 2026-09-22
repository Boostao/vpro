# Read-only vegetation duplicate diagnosis ---------------------------------

#' Find duplicate vegetation cover values by plot, species, and layer
#'
#' Translates the diagnostic query in
#' `V7mdlOptimizeVeg.Check4DuplicatedSpecies` using the active project's
#' physical `_Veg` table. Like the Access `USysAllVeg` query, each non-null
#' cover field is unpivoted with `UNION` (not `UNION ALL`): identical cover
#' values in the same plot, species, and layer count only once. This checks
#' the complete project regardless of the active SU. It does not run
#' `OptimizeVeg` or modify vegetation rows.
#'
#' @param context A VPRO context with an active project.
#'
#' @return A data frame of `PlotNumber`, `Species`, `Layer`, and `n_of_spp`
#'   for groups with more than one distinct non-null cover value. Layers
#'   include 1–7, 5a–5c, A, and B, but not 8–10. Null plot numbers and
#'   species are retained. Results are ordered by plot, species, and layer.
#' @export
vpro_vegetation_duplicates <- function(context) {
  project <- vpro_plot_active(context)
  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  veg <- DBI::dbQuoteIdentifier(con, vpro_project_table(project$project, "Veg"))
  layers <- c(
    "1" = "Cover1", "2" = "Cover2", "3" = "Cover3", "4" = "Cover4",
    "5" = "Cover5", "5a" = "Cover5a", "5b" = "Cover5b", "5c" = "Cover5c",
    "6" = "Cover6", "7" = "Cover7", "A" = "TotalA", "B" = "TotalB"
  )
  branches <- vapply(seq_along(layers), function(i) {
    cover <- DBI::dbQuoteIdentifier(con, unname(layers[[i]]))
    paste(
      'SELECT "PlotNumber", "Species",',
      DBI::dbQuoteString(con, names(layers)[[i]]),
      'AS "Layer",', cover, 'AS "Cover" FROM', veg,
      'WHERE', cover, 'IS NOT NULL'
    )
  }, character(1))
  result <- DBI::dbGetQuery(con, paste(
    'SELECT "PlotNumber", "Species", "Layer", COUNT("Cover") AS "n_of_spp"',
    'FROM (', paste(branches, collapse = ' UNION '), ') AS unpivoted',
    'GROUP BY "PlotNumber", "Species", "Layer"',
    'HAVING COUNT("Cover") > 1',
    'ORDER BY "PlotNumber", "Species", "Layer"'
  ))
  result$Layer <- as.character(result$Layer)
  result$n_of_spp <- as.integer(result$n_of_spp)
  result
}
