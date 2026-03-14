# Logic: Project Management
# Project-as-file model: each project lives in its own .duckdb file.
# The main vpro.duckdb holds all open project rows with projectid as a filter column.

PROJECT_TABLES <- c(
  "Env", "Veg", "Metadata", "Admin", "Humus", "Mineral",
  "SU", "Audit", "Herbarium", "Profile", "Theme", "Lump",
  "Hierarchy", "Other"
)

PROJECT_TABLE_SCOPE <- list(
  Env = list(mode = "direct", project_col = "projectid"),
  Metadata = list(mode = "direct", project_col = "projectid"),
  Audit = list(mode = "direct", project_col = "projectid"),
  Veg = list(mode = "via_env", env_fk = "plotnumber"),
  SU = list(mode = "via_env", env_fk = "plotnumber"),
  Humus = list(mode = "via_env", env_fk = "plotnumber"),
  Mineral = list(mode = "via_env", env_fk = "plotnumber"),
  Other = list(mode = "via_env", env_fk = "plotnumber"),
  Herbarium = list(mode = "via_env", env_fk = "plotnumber"),
  Admin = list(mode = "via_env", env_fk = "plot")
)

PROJECT_BASELINE_TABLE <- "project_baselines"

project_baseline_dir <- function() {
  dir_path <- file.path(getwd(), "data", "project_baselines")
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, mustWork = FALSE)
}

project_baseline_path <- function(project_id) {
  safe_id <- gsub("[^A-Za-z0-9_-]", "_", as.character(project_id %||% ""))
  file.path(project_baseline_dir(), paste0(safe_id, "_baseline.duckdb"))
}

project_ensure_baseline_table <- function(con) {
  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS", PROJECT_BASELINE_TABLE, "(",
      "project_id TEXT PRIMARY KEY,",
      "baseline_path TEXT NOT NULL,",
      "created_utc TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,",
      "source_file_path TEXT,",
      "source_kind TEXT,",
      "file_size_bytes BIGINT,",
      "file_md5 TEXT",
      ")"
    )
  )
  invisible(TRUE)
}

project_get_baseline <- function(con, project_id) {
  if (is.null(project_id) || !nzchar(project_id %||% "")) return(NULL)
  project_ensure_baseline_table(con)

  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      paste0("SELECT * FROM ", PROJECT_BASELINE_TABLE, " WHERE project_id = ? LIMIT 1"),
      list(as.character(project_id))
    ),
    error = function(e) data.frame()
  )
  if (nrow(rows) == 0) return(NULL)
  rows[1, , drop = FALSE]
}

project_capture_baseline <- function(con,
                                     project_id,
                                     source_file_path = NULL,
                                     source_kind = "project_open",
                                     force = FALSE) {
  if (is.null(project_id) || !nzchar(project_id %||% "")) {
    stop("project_id is required.")
  }

  project_ensure_baseline_table(con)
  existing <- project_get_baseline(con, project_id)
  if (!isTRUE(force) && !is.null(existing)) {
    return(existing)
  }

  baseline_path <- project_baseline_path(project_id)
  if (file.exists(baseline_path)) {
    unlink(baseline_path, force = TRUE)
  }

  save_project(
    con,
    project_id = project_id,
    path = baseline_path,
    alias = paste0("tmp_save_baseline_", gsub("[^A-Za-z0-9]", "_", project_id))
  )

  file_info <- file.info(baseline_path)
  file_md5 <- tryCatch(unname(tools::md5sum(baseline_path)[[1]]), error = function(e) NA_character_)

  DBI::dbExecute(
    con,
    paste0("DELETE FROM ", PROJECT_BASELINE_TABLE, " WHERE project_id = ?"),
    list(as.character(project_id))
  )

  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO ", PROJECT_BASELINE_TABLE,
      " (project_id, baseline_path, created_utc, source_file_path, source_kind, file_size_bytes, file_md5)",
      " VALUES (?, ?, CURRENT_TIMESTAMP, ?, ?, ?, ?)"
    ),
    list(
      as.character(project_id),
      baseline_path,
      if (is.null(source_file_path) || !nzchar(source_file_path %||% "")) NA_character_ else as.character(source_file_path),
      as.character(source_kind %||% "project_open"),
      if (nrow(file_info) == 0 || is.na(file_info$size[[1]])) NA_integer_ else as.numeric(file_info$size[[1]]),
      file_md5
    )
  )

  project_get_baseline(con, project_id)
}

project_read_baseline_rows <- function(con, project_id, table_name, pk_name, pk_values = NULL) {
  baseline <- project_get_baseline(con, project_id)
  if (is.null(baseline) || nrow(baseline) == 0) return(data.frame())

  baseline_path <- baseline$baseline_path[[1]]
  if (is.null(baseline_path) || !file.exists(baseline_path)) return(data.frame())

  bcon <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), baseline_path, read_only = TRUE),
    error = function(e) NULL
  )
  if (is.null(bcon)) return(data.frame())
  on.exit(try(DBI::dbDisconnect(bcon, shutdown = TRUE), silent = TRUE), add = TRUE)

  if (!DBI::dbExistsTable(bcon, table_name)) return(data.frame())
  fields <- tryCatch(DBI::dbListFields(bcon, table_name), error = function(e) character(0))
  pk_field <- .project_find_field(fields, pk_name)
  if (is.na(pk_field)) return(data.frame())

  if (is.null(pk_values) || length(pk_values) == 0) {
    return(DBI::dbGetQuery(bcon, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(bcon, table_name))))
  }

  placeholders <- paste(rep("?", length(pk_values)), collapse = ", ")
  DBI::dbGetQuery(
    bcon,
    paste0(
      "SELECT * FROM ", DBI::dbQuoteIdentifier(bcon, table_name),
      " WHERE CAST(", DBI::dbQuoteIdentifier(bcon, pk_field), " AS TEXT) IN (", placeholders, ")"
    ),
    as.list(as.character(pk_values))
  )
}

project_baseline_has_tables <- function(con, project_id, required_tables = c("Env", "SU", "Veg")) {
  baseline <- project_get_baseline(con, project_id)
  if (is.null(baseline) || nrow(baseline) == 0) return(FALSE)

  baseline_path <- baseline$baseline_path[[1]]
  if (is.null(baseline_path) || !file.exists(baseline_path)) return(FALSE)

  bcon <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), baseline_path, read_only = TRUE),
    error = function(e) NULL
  )
  if (is.null(bcon)) return(FALSE)
  on.exit(try(DBI::dbDisconnect(bcon, shutdown = TRUE), silent = TRUE), add = TRUE)

  all(vapply(required_tables, function(tbl) DBI::dbExistsTable(bcon, tbl), logical(1)))
}

.project_find_field <- function(fields, candidates) {
  if (length(fields) == 0 || length(candidates) == 0) return(NA_character_)
  idx <- match(tolower(candidates), tolower(fields), nomatch = 0L)
  idx <- idx[idx > 0L]
  if (length(idx) == 0) return(NA_character_)
  fields[[idx[[1]]]]
}

.project_table_scope <- function(con, table_name) {
  configured <- PROJECT_TABLE_SCOPE[[table_name]]
  if (!is.null(configured)) {
    return(configured)
  }

  fields <- tryCatch(DBI::dbListFields(con, table_name), error = function(e) character(0))
  project_col <- .project_find_field(fields, c("projectid", "project_id"))
  if (!is.na(project_col)) {
    return(list(mode = "direct", project_col = project_col))
  }

  env_fk <- .project_find_field(fields, c("plotnumber", "plot"))
  if (!is.na(env_fk)) {
    return(list(mode = "via_env", env_fk = env_fk))
  }

  list(mode = "all")
}

.project_where_clause <- function(con, table_name, project_id) {
  scope <- .project_table_scope(con, table_name)
  if (identical(scope$mode, "direct")) {
    list(
      sql = paste0(" WHERE ", DBI::dbQuoteIdentifier(con, scope$project_col), " = ?"),
      params = list(project_id)
    )
  } else if (identical(scope$mode, "via_env") && DBI::dbExistsTable(con, "Env")) {
    env_fields <- tryCatch(DBI::dbListFields(con, "Env"), error = function(e) character(0))
    env_plot_col <- .project_find_field(env_fields, c("plotnumber"))
    env_project_col <- .project_find_field(env_fields, c("projectid", "project_id"))
    if (!is.na(env_plot_col) && !is.na(env_project_col)) {
      list(
        sql = paste0(
          " WHERE ", DBI::dbQuoteIdentifier(con, scope$env_fk),
          " IN (SELECT ", DBI::dbQuoteIdentifier(con, env_plot_col),
          " FROM ", DBI::dbQuoteIdentifier(con, "Env"),
          " WHERE ", DBI::dbQuoteIdentifier(con, env_project_col), " = ?)"
        ),
        params = list(project_id)
      )
    } else {
      list(sql = "", params = list())
    }
  } else {
    list(sql = "", params = list())
  }
}

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
    where <- .project_where_clause(con, tbl, project_id)
    DBI::dbExecute(con, paste0(
      "INSERT INTO ", DBI::dbQuoteIdentifier(con, alias), ".main.", DBI::dbQuoteIdentifier(con, tbl),
      " (", col_list, ") ",
      "SELECT ", col_list,
      " FROM ", DBI::dbQuoteIdentifier(con, tbl),
      where$sql
    ), where$params)
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
    where <- .project_where_clause(con, tbl, project_id)
    if (!nzchar(where$sql)) next
    DBI::dbExecute(
      con,
      paste0("DELETE FROM ", DBI::dbQuoteIdentifier(con, tbl), where$sql),
      where$params
    )
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

#' List project IDs available in an external .duckdb file
#'
#' Opens a read-only connection to the file and returns distinct projectid
#' values.  Use this to detect multiple projects before calling open_project().
#' Do NOT pass the main vpro.duckdb path — use list_open_projects(con) for that.
#'
#' @param path Character. Path to an external project .duckdb file.
#' @return Character vector of project IDs, or character(0) if none found.
list_projects_in_file <- function(path) {
  if (!is.character(path) || !nzchar(path %||% "")) return(character(0))
  if (!file.exists(path)) return(character(0))

  con <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE),
    error = function(e) NULL
  )
  if (is.null(con)) return(character(0))
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  for (tbl in c("Metadata", "Env")) {
    if (!DBI::dbExistsTable(con, tbl)) next
    fields <- tryCatch(tolower(DBI::dbListFields(con, tbl)), error = function(e) character(0))
    if (!("projectid" %in% fields)) next
    res <- tryCatch(
      DBI::dbGetQuery(
        con,
        paste0("SELECT DISTINCT projectid FROM ", DBI::dbQuoteIdentifier(con, tbl),
               " WHERE projectid IS NOT NULL ORDER BY projectid")
      ),
      error = function(e) data.frame(projectid = character(0))
    )
    pids <- as.character(res$projectid)
    pids <- pids[!is.na(pids) & nzchar(pids)]
    if (length(pids) > 0) return(pids)
  }
  character(0)
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
