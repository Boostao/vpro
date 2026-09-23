# Environment report --------------------------------------------------------

vpro_report_environment_plot_numbers <- function(plot_numbers) {
  if (is.null(plot_numbers)) {
    return(NULL)
  }
  if (
    !is.character(plot_numbers) ||
      anyNA(plot_numbers) ||
      any(!nzchar(trimws(plot_numbers)))
  ) {
    stop(
      "`plot_numbers` must be a character vector of non-missing, nonblank plot numbers.",
      call. = FALSE
    )
  }
  plot_numbers
}

#' Return environmental rows for the active project or site unit
#'
#' Reads every column from the active `USysEnv` DuckDB temporary view. The view
#' supplies the active project scope and, when selected, the active-SU scope.
#' Rows are ordered by plot number. The existing `USysEnv` view removes
#' duplicate SU-membership rows; order among equal plot numbers is unspecified.
#' Supplying `plot_numbers` restricts the result to exact plot-number matches.
#'
#' This is a bounded data API only. It does not reproduce EnvReport's Excel
#' transposition, site-unit worksheet grouping, or RIGHT JOIN handling of SU
#' rows that have no environmental row. It neither modifies source databases nor
#' creates report files.
#'
#' @param context A VPRO project context with an active project.
#' @param plot_numbers Optional character vector of exact plot numbers. Every
#'   value must be non-missing and nonblank; `character(0)` returns typed empty
#'   rows.
#'
#' @return A data frame containing every `USysEnv` column. Rows are ordered by
#'   `PlotNumber`.
#' @export
vpro_report_environment <- function(context, plot_numbers = NULL) {
  vpro_plot_active(context)
  plot_numbers <- vpro_report_environment_plot_numbers(plot_numbers)
  fields <- DBI::dbListFields(context$con, "USysEnv")
  select_fields <- paste(DBI::dbQuoteIdentifier(context$con, fields), collapse = ", ")

  where <- ""
  params <- NULL
  if (!is.null(plot_numbers)) {
    if (length(plot_numbers) == 0L) {
      where <- "WHERE FALSE"
    } else {
      where <- paste0(
        "WHERE \"PlotNumber\" IN (",
        paste(rep("?", length(plot_numbers)), collapse = ", "),
        ")"
      )
      params <- as.list(plot_numbers)
    }
  }
  sql <- paste("SELECT", select_fields, 'FROM "USysEnv"', where, 'ORDER BY "PlotNumber"')
  DBI::dbGetQuery(context$con, sql, params = params)
}
