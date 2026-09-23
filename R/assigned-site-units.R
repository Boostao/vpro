# Assigned site-unit choices -----------------------------------------------

#' List site-unit choices for an active project, SU, or master list
#'
#' Returns data for the three concrete SQL branches in
#' `V7mdlTableOfLists.AssignedSiteUnitList`, rather than returning SQL text.
#' Project choices read the active `USysEnv` view (and thus respect active-SU
#' filtering); SU choices read the physical active SU table; master choices
#' read `MasterSiteUnitList` from an explicit SQLite reference database.
#' Project and SU results are distinct, omit nulls but retain empty strings,
#' and are ordered for reproducibility. Master results preserve the Access
#' `Level = 11` filter and `SiteSeries` order. Access's fallback branch uses
#' `Name` and `UnitLongName`, which are absent from the canonical master list;
#' unsupported selectors are rejected rather than returning mismatched data.
#'
#' @param context A VPRO project context. Project and SU scopes require an
#'   active project; SU scope additionally requires an active SU.
#' @param source One of `"project"`, `"master"`, or `"su"`, corresponding to
#'   Access selector values 1, 2, and 3.
#' @param reference_path SQLite reference database for master choices. Defaults
#'   to the bundled `VLists.db`.
#'
#' @return A data frame with `UserSiteUnit` for project, `SiteUnit` for SU,
#'   or `SiteSeries` and `SiteSeriesLongName` for master choices.
#' @export
vpro_assigned_site_units <- function(
  context,
  source = c("project", "master", "su"),
  reference_path = vpro_bundled_file("extdata", "VLists.db")
) {
  source <- match.arg(source)
  if (source == "master") {
    if (!is.character(reference_path) || length(reference_path) != 1L || is.na(reference_path) || !file.exists(reference_path)) {
      stop("VPRO master site-unit database does not exist.", call. = FALSE)
    }
    con <- DBI::dbConnect(RSQLite::SQLite(), reference_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    if (!DBI::dbExistsTable(con, "MasterSiteUnitList")) {
      stop("VPRO master site-unit table does not exist: MasterSiteUnitList", call. = FALSE)
    }
    required <- c("SiteSeries", "SiteSeriesLongName", "Level")
    missing <- setdiff(required, DBI::dbListFields(con, "MasterSiteUnitList"))
    if (length(missing) > 0L) {
      stop("VPRO master site-unit table is missing fields: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    return(DBI::dbGetQuery(
      con,
      'SELECT "SiteSeries", "SiteSeriesLongName" FROM "MasterSiteUnitList" WHERE "Level" = 11 ORDER BY "SiteSeries"'
    ))
  }

  vpro_plot_active(context)
  if (source == "project") {
    return(DBI::dbGetQuery(
      context$con,
      'SELECT DISTINCT "UserSiteUnit" FROM "USysEnv" WHERE "UserSiteUnit" IS NOT NULL ORDER BY "UserSiteUnit"'
    ))
  }
  if (is.null(context$active_su)) {
    stop("An active VPRO SU is required for SU site-unit choices.", call. = FALSE)
  }
  su <- vpro_su_relation(context, context$active_su)
  DBI::dbGetQuery(
    context$con,
    paste(
      'SELECT DISTINCT "SiteUnit" FROM',
      su,
      'WHERE "SiteUnit" IS NOT NULL ORDER BY "SiteUnit"'
    )
  )
}
