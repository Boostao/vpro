# Projects -----------------------------------------------------------------

.vpro_core_project_suffixes <- c(
  "Admin",
  "Audit",
  "Env",
  "Humus",
  "Metadata",
  "Mineral",
  "Other",
  "Veg"
)

.vpro_optional_project_suffixes <- c(
  "Herbarium",
  "Hierarchy",
  "Lump",
  "Profile",
  "SU",
  "Theme"
)

vpro_sqlite_tables <- function(path) {
  if (!file.exists(path)) {
    stop("VPRO database file does not exist: ", path, call. = FALSE)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(
    con,
    paste(
      "SELECT name FROM sqlite_master",
      "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'",
      "ORDER BY name"
    )
  )$name
}

#' Discover VPRO projects in a SQLite database
#'
#' A project is identified by an `<project>_Env` table. The returned table also
#' reports whether all eight core VPRO project tables are present.
#'
#' @param path Path to a VPRO project SQLite database.
#'
#' @return A data frame with project names and table-family completeness.
#' @export
vpro_project_discover <- function(path) {
  tables <- vpro_sqlite_tables(path)
  env_tables <- grep("_Env$", tables, value = TRUE)
  projects <- sub("_Env$", "", env_tables)

  if (length(projects) == 0L) {
    return(data.frame(
      project = character(),
      core_tables = integer(),
      optional_tables = integer(),
      complete = logical()
    ))
  }

  rows <- lapply(projects, function(project) {
    core <- paste0(project, "_", .vpro_core_project_suffixes)
    optional <- paste0(project, "_", .vpro_optional_project_suffixes)
    data.frame(
      project = project,
      core_tables = sum(core %in% tables),
      optional_tables = sum(optional %in% tables),
      complete = all(core %in% tables)
    )
  })
  do.call(rbind, rows)
}

#' Validate a VPRO project table family
#'
#' @param path Path to a VPRO project SQLite database.
#' @param project Project prefix.
#'
#' @return A data frame listing required tables and whether each is present.
#' @export
vpro_project_validate <- function(path, project) {
  tables <- vpro_sqlite_tables(path)
  expected <- paste0(project, "_", .vpro_core_project_suffixes)
  data.frame(
    suffix = .vpro_core_project_suffixes,
    table = expected,
    present = expected %in% tables
  )
}
