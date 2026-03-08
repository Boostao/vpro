# Logic: Project Management
# Project-as-file model: each project lives in its own .duckdb file.
# The main vpro.duckdb holds all open project rows with projectid as a filter column.

PROJECT_TABLES <- c(
  "Env", "Veg", "Metadata", "Admin", "Humus", "Mineral",
  "SU", "Audit", "Herbarium", "Profile", "Theme", "Lump",
  "Hierarchy", "Other"
)

#' List all open project IDs
#'
#' Returns distinct projectid values present in the Metadata table.
#'
#' @param con DBI connection
#' @return Character vector of project IDs
list_open_projects <- function(con) {
  if (!DBI::dbExistsTable(con, "Metadata")) return(character(0))
  tryCatch({
    res <- DBI::dbGetQuery(con, "SELECT DISTINCT projectid FROM Metadata ORDER BY projectid")
    as.character(res$projectid)
  }, error = function(e) character(0))
}

#' Open a project from a .duckdb file
#'
#' Attaches the project file, detects the projectid from Env or Metadata,
#' INSERTs all rows into the main tables, then detaches.
#'
#' @param con DBI connection (main vpro.duckdb)
#' @param path Character. Path to project .duckdb file.
#' @param alias Character. Temporary attach alias.
#' @return Character. The projectid loaded.
open_project <- function(con, path, alias = "tmp_open_project") {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Project file path is required.")
  }
  if (!file.exists(path)) {
    stop("Project file not found: ", path)
  }

  attached <- list_attached_dbs(con)
  if (alias %in% attached) detach_db(con, alias)

  DBI::dbExecute(con, paste0("ATTACH ", DBI::dbQuoteString(con, path), " AS ", DBI::dbQuoteIdentifier(con, alias)))
  on.exit(try(detach_db(con, alias), silent = TRUE), add = TRUE)

  # Detect projectid from Metadata or Env in the source file
  project_id <- tryCatch({
    src_tables <- DBI::dbGetQuery(
      con,
      "SELECT table_name FROM duckdb_tables() WHERE database_name = ? AND schema_name = 'main' AND internal = FALSE",
      list(alias)
    )$table_name

    pid <- NULL
    for (tbl in c("Metadata", "Env")) {
      if (tbl %in% src_tables) {
        fields <- tolower(DBI::dbListFields(con, DBI::Id(database = alias, schema = "main", table = tbl)))
        if ("projectid" %in% fields) {
          res <- DBI::dbGetQuery(
            con,
            paste0("SELECT DISTINCT projectid FROM ", DBI::dbQuoteIdentifier(con, alias), ".main.", DBI::dbQuoteIdentifier(con, tbl), " LIMIT 1")
          )
          if (nrow(res) > 0 && !is.na(res$projectid[[1]])) {
            pid <- as.character(res$projectid[[1]])
            break
          }
        }
      }
    }
    pid
  }, error = function(e) NULL)

  if (is.null(project_id) || !nzchar(project_id)) {
    stop("Could not detect projectid from project file: ", path)
  }

  # INSERT all available PROJECT_TABLES rows into main
  src_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM duckdb_tables() WHERE database_name = ? AND schema_name = 'main' AND internal = FALSE",
    list(alias)
  )$table_name

  for (tbl in PROJECT_TABLES) {
    if (!(tbl %in% src_tables)) next
    if (!DBI::dbExistsTable(con, tbl)) next

    main_cols <- tolower(DBI::dbListFields(con, tbl))
    src_cols  <- tolower(DBI::dbListFields(con, DBI::Id(database = alias, schema = "main", table = tbl)))
    common    <- intersect(main_cols, src_cols)
    if (length(common) == 0) next

    col_list <- paste(
      sapply(common, function(c) DBI::dbQuoteIdentifier(con, c)),
      collapse = ", "
    )
    DBI::dbExecute(con, paste0(
      "INSERT INTO ", DBI::dbQuoteIdentifier(con, tbl),
      " (", col_list, ") ",
      "SELECT ", col_list,
      " FROM ", DBI::dbQuoteIdentifier(con, alias), ".main.", DBI::dbQuoteIdentifier(con, tbl)
    ))
  }

  project_id
}

#' Save a project to a .duckdb file
#'
#' Creates (or overwrites) a project file and writes all rows for project_id.
#'
#' @param con DBI connection (main vpro.duckdb)
#' @param project_id Character. Project to save.
#' @param path Character. Destination .duckdb file path.
#' @param alias Character. Temporary attach alias.
save_project <- function(con, project_id, path, alias = "tmp_save_project") {
  if (is.null(project_id) || !nzchar(project_id)) stop("project_id is required.")
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Project file path is required.")
  }

  attached <- list_attached_dbs(con)
  if (alias %in% attached) detach_db(con, alias)

  DBI::dbExecute(con, paste0("ATTACH ", DBI::dbQuoteString(con, path), " AS ", DBI::dbQuoteIdentifier(con, alias)))
  on.exit(try(detach_db(con, alias), silent = TRUE), add = TRUE)

  for (tbl in PROJECT_TABLES) {
    if (!DBI::dbExistsTable(con, tbl)) next

    cols      <- DBI::dbListFields(con, tbl)
    # Create table in project file if needed (schema copy)
    DBI::dbExecute(con, paste0(
      "CREATE TABLE IF NOT EXISTS ", DBI::dbQuoteIdentifier(con, alias), ".main.", DBI::dbQuoteIdentifier(con, tbl),
      " AS SELECT * FROM ", DBI::dbQuoteIdentifier(con, tbl), " WHERE 1=0"
    ))

    col_list <- paste(
      sapply(cols, function(c) DBI::dbQuoteIdentifier(con, c)),
      collapse = ", "
    )
    pid_cols <- cols[tolower(cols) == "projectid"]
    if (length(pid_cols) == 0) next
    pid_col <- pid_cols[[1]]
    DBI::dbExecute(con, paste0(
      "INSERT INTO ", DBI::dbQuoteIdentifier(con, alias), ".main.", DBI::dbQuoteIdentifier(con, tbl),
      " (", col_list, ") ",
      "SELECT ", col_list,
      " FROM ", DBI::dbQuoteIdentifier(con, tbl),
      " WHERE ", DBI::dbQuoteIdentifier(con, pid_col), " = ?"
    ), list(project_id))
  }

  invisible(path)
}

#' Close a project (optionally saving first)
#'
#' Removes all rows for project_id from all PROJECT_TABLES in main.
#'
#' @param con DBI connection
#' @param project_id Character
#' @param path Character or NULL. If provided, save_project is called first.
close_project <- function(con, project_id, path = NULL) {
  if (is.null(project_id) || !nzchar(project_id)) stop("project_id is required.")

  if (!is.null(path) && nzchar(path)) {
    save_project(con, project_id, path)
  }

  for (tbl in PROJECT_TABLES) {
    if (!DBI::dbExistsTable(con, tbl)) next
    cols <- tolower(DBI::dbListFields(con, tbl))
    if (!("projectid" %in% cols)) next
    DBI::dbExecute(con, paste0(
      "DELETE FROM ", DBI::dbQuoteIdentifier(con, tbl),
      " WHERE projectid = ?"
    ), list(project_id))
  }

  invisible(project_id)
}

#' Create a new project
#'
#' Inserts a row into Metadata for the new project.
#'
#' @param con DBI connection
#' @param project_id Character. Must be unique.
#' @param project_title Character. Human-readable name.
#' @return Invisible project_id
new_project <- function(con, project_id, project_title) {
  if (is.null(project_id) || !nzchar(trimws(project_id))) stop("project_id is required.")
  if (is.null(project_title) || !nzchar(trimws(project_title))) stop("project_title is required.")

  project_id    <- trimws(project_id)
  project_title <- trimws(project_title)

  if (project_exists(con, project_id)) {
    stop("Project '", project_id, "' already exists.")
  }

  if (!DBI::dbExistsTable(con, "Metadata")) {
    stop("Metadata table not found. Cannot create project.")
  }

  meta_cols <- tolower(DBI::dbListFields(con, "Metadata"))
  title_col <- if ("projecttitle" %in% meta_cols) "projecttitle" else if ("projectname" %in% meta_cols) "projectname" else NULL

  if (!is.null(title_col)) {
    DBI::dbExecute(con,
      paste0("INSERT INTO Metadata (projectid, ", DBI::dbQuoteIdentifier(con, title_col), ") VALUES (?, ?)"),
      list(project_id, project_title)
    )
  } else {
    DBI::dbExecute(con, "INSERT INTO Metadata (projectid) VALUES (?)", list(project_id))
  }

  invisible(project_id)
}

#' Check if a project exists in Metadata
#'
#' @param con DBI connection
#' @param project_id Character
#' @return Logical
project_exists <- function(con, project_id) {
  if (!DBI::dbExistsTable(con, "Metadata")) return(FALSE)
  tryCatch({
    res <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM Metadata WHERE projectid = ?", list(project_id))
    res$n[[1]] > 0
  }, error = function(e) FALSE)
}
