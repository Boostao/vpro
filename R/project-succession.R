# Read-only succession schema detection -------------------------------------

#' Detect a successional VPRO project
#'
#' Translates `V7mdlSuccession.SuccessionProject`: a project is successional
#' when its physical `_Veg` table has a `SuccessionYear` field. This is a
#' schema check only; it does not convert the project or inspect its records.
#' Field names are compared without regard to case, as in Access databases.
#'
#' @param path Path to an existing project SQLite database.
#' @param project Project prefix.
#'
#' @return A single logical value. A missing vegetation table is an error,
#'   rather than evidence of a non-successional project.
#' @export
vpro_project_is_successional <- function(path, project) {
  project <- vpro_project_name(project)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO project database does not exist: ", paste(path, collapse = ", "), call. = FALSE)
  }
  table <- vpro_project_table(project, "Veg")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, table)) {
    stop("VPRO vegetation table does not exist: ", table, call. = FALSE)
  }
  any(tolower(DBI::dbListFields(con, table)) == "successionyear")
}
