# Project reference-list versions -------------------------------------------

#' Read reference-list versions recorded in the active project's audit history
#'
#' Translates `V7mdlAllSpecsTools.ProjectVersion` and
#' `V7mdlTableOfLists.ProjectVersionTableOfLists` using the active project's
#' physical `_Audit` table, not the plot-filtered audit view. For each reference
#' table, the most recent `EditWhen` determines the result; a missing, null, or
#' empty `AfterEdit` becomes `"Unknown"` without falling back to older rows.
#' When more than one event has the latest timestamp, Access does not specify
#' which wins: the result is marked `"ambiguous"` and its version is missing,
#' even if the tied values agree. Null timestamps rank after non-null timestamps
#' and are considered tied when no non-null timestamp exists. No audit rows,
#' project state, or reference-list metadata are modified.
#'
#' @param context A VPRO context with an active project.
#'
#' @return A data frame with `Table`, `Version`, `EditWhen` (as stored in
#'   SQLite), `Status` (`"ok"`, `"missing"`, `"unknown"`, or `"ambiguous"`), and
#'   `LatestRows`. An ambiguous version is `NA` rather than a guessed value.
#' @export
vpro_project_reference_versions <- function(context) {
  project <- vpro_plot_active(context)
  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  audit <- DBI::dbQuoteIdentifier(con, vpro_project_table(project$project, "Audit"))
  sql <- paste(
    'WITH latest AS (SELECT "EditWhen" FROM',
    audit,
    'WHERE "Table" = ? ORDER BY "EditWhen" DESC LIMIT 1)',
    'SELECT audit."EditWhen" AS "EditWhen", audit."AfterEdit" AS "AfterEdit"',
    'FROM',
    audit,
    'AS audit JOIN latest',
    'ON audit."EditWhen" IS latest."EditWhen"',
    'WHERE audit."Table" = ?'
  )

  rows <- lapply(c("USysAllSpecs", "USysTableOfLists"), function(table) {
    latest <- DBI::dbGetQuery(con, sql, params = list(table, table))
    count <- nrow(latest)
    status <- if (count == 0L) {
      "missing"
    } else if (count > 1L) {
      "ambiguous"
    } else if (is.na(latest$AfterEdit[[1L]]) || !nzchar(latest$AfterEdit[[1L]])) {
      "unknown"
    } else {
      "ok"
    }
    data.frame(
      Table = table,
      Version = if (status == "ambiguous") {
        NA_character_
      } else if (status == "ok") {
        latest$AfterEdit[[1L]]
      } else {
        "Unknown"
      },
      EditWhen = if (count == 0L) NA_character_ else as.character(latest$EditWhen[[1L]]),
      Status = status,
      LatestRows = count
    )
  })
  do.call(rbind, rows)
}
