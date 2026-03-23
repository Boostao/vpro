# Logic: Project Management
# Canonical project storage is one SQLite database per project under data/projects.
# Open projects are represented by attached SQLite databases whose alias matches the project id.

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
PROJECT_TEMPLATE_ID <- "Sample"

project_storage_dir <- function() {
  cfg <- tryCatch(config(), error = function(e) list(System = list(Location = getwd())))
  base_dir <- cfg$System$Location %||% getwd()
  dir_path <- file.path(base_dir, "data", "projects")
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, mustWork = FALSE)
}

project_db_path <- function(project_id) {
  safe_id <- trimws(as.character(project_id %||% ""))
  if (!nzchar(safe_id)) {
    stop("project_id is required.")
  }
  file.path(project_storage_dir(), paste0(safe_id, ".db"))
}

list_project_storage_ids <- function() {
  storage_dir <- project_storage_dir()
  if (!dir.exists(storage_dir)) {
    return(character(0))
  }

  files <- list.files(storage_dir, pattern = "\\.db$", full.names = FALSE)
  ids <- tools::file_path_sans_ext(files)
  sort(unique(ids[nzchar(ids)]))
}

project_table_id <- function(project_id, table_name) {
  db_id(table_name, project_id, prj = TRUE)
}

project_attached <- function(con, project_id) {
  project_id %in% db_list_attached(con)
}

project_file_is_sqlite <- function(path) {
  tolower(tools::file_ext(path %||% "")) %in% c("db", "sqlite", "sqlite3")
}

project_file_connect <- function(path) {
  if (!file.exists(path)) {
    stop("Project file not found: ", path)
  }

  if (project_file_is_sqlite(path)) {
    con <- db_con()
    alias <- "projectfile"
    DBI::dbExecute(
      con,
      paste0("ATTACH ", DBI::dbQuoteString(con, path), " AS ", DBI::dbQuoteIdentifier(con, alias), " (TYPE sqlite)")
    )
    list(con = con, alias = alias, is_sqlite = TRUE)
  } else {
    con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
    list(con = con, alias = NULL, is_sqlite = FALSE)
  }
}

project_file_disconnect <- function(handle) {
  if (is.null(handle) || is.null(handle$con)) {
    return(invisible(NULL))
  }
  try(DBI::dbDisconnect(handle$con), silent = TRUE)
  invisible(NULL)
}

project_file_table_names <- function(path) {
  handle <- tryCatch(project_file_connect(path), error = function(e) NULL)
  if (is.null(handle)) {
    return(character(0))
  }
  on.exit(project_file_disconnect(handle), add = TRUE)

  if (isTRUE(handle$is_sqlite)) {
    DBI::dbGetQuery(
      handle$con,
      "SELECT table_name FROM duckdb_tables() WHERE database_name = ? AND internal = FALSE ORDER BY table_name",
      list(handle$alias)
    )$table_name
  } else {
    tryCatch(DBI::dbListTables(handle$con), error = function(e) character(0))
  }
}

project_file_resolve_table <- function(path, table_name, project_id = NULL) {
  tables <- project_file_table_names(path)
  if (length(tables) == 0) {
    return(NA_character_)
  }

  candidates <- character(0)
  if (!is.null(project_id) && nzchar(as.character(project_id %||% ""))) {
    candidates <- c(candidates, paste0(project_id, "_", table_name))
  }
  candidates <- c(candidates, table_name)

  for (candidate in candidates) {
    idx <- match(tolower(candidate), tolower(tables), nomatch = 0L)
    if (idx > 0L) {
      return(tables[[idx]])
    }
  }

  NA_character_
}

project_file_prefixes <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(character(0))
  }
  if (!file.exists(path)) {
    return(character(0))
  }

  tables <- project_file_table_names(path)

  prefixes <- character(0)
  for (suffix in c("_Metadata", "_Env")) {
    matches <- tables[endsWith(tables, suffix)]
    if (length(matches) > 0) {
      prefixes <- c(prefixes, sub(paste0(suffix, "$"), "", matches))
    }
  }

  sort(unique(prefixes[nzchar(prefixes)]))
}

project_import_align_columns <- function(data, target_fields, project_id = NULL) {
  if (is.null(target_fields) || length(target_fields) == 0) {
    return(data)
  }

  data_names <- names(data)
  target_lower <- tolower(target_fields)
  data_lower <- tolower(data_names)
  data_out <- data.frame(matrix(nrow = nrow(data), ncol = 0), stringsAsFactors = FALSE)

  for (idx in seq_along(target_fields)) {
    field_name <- target_fields[[idx]]
    match_idx <- match(target_lower[[idx]], data_lower, nomatch = 0L)
    if (match_idx > 0L) {
      data_out[[field_name]] <- data[[match_idx]]
    } else {
      data_out[[field_name]] <- rep(NA, nrow(data))
    }
  }

  if (!is.null(project_id) && nzchar(as.character(project_id %||% ""))) {
    project_cols <- target_fields[target_lower %in% c("projectid", "project_id")]
    for (field_name in project_cols) {
      data_out[[field_name]] <- rep(as.character(project_id), nrow(data_out))
    }
  }

  data_out
}

project_access_source_tables <- function(access_path, source_project_id) {
  if (!requireNamespace("mdbtoolr", quietly = TRUE)) {
    stop("Package 'mdbtoolr' is required for Access project import.")
  }

  source_project_id <- trimws(as.character(source_project_id %||% ""))
  if (!nzchar(source_project_id)) {
    stop("source_project_id is required.")
  }

  access_con <- DBI::dbConnect(mdbtoolr::mdb(), access_path)
  on.exit(try(DBI::dbDisconnect(access_con), silent = TRUE), add = TRUE)

  table_names <- tryCatch(DBI::dbListTables(access_con), error = function(e) character(0))
  source_tables <- list()
  for (table_name in PROJECT_TABLES) {
    candidate <- paste0(source_project_id, "_", table_name)
    match_idx <- match(tolower(candidate), tolower(table_names), nomatch = 0L)
    if (match_idx > 0L) {
      source_tables[[table_name]] <- table_names[[match_idx]]
    }
  }

  source_tables
}

project_import_access_project <- function(con, access_path, source_project_id, target_project_id = source_project_id, overwrite = FALSE) {
  if (!requireNamespace("mdbtoolr", quietly = TRUE)) {
    stop("Package 'mdbtoolr' is required for Access project import.")
  }
  if (!is.character(access_path) || length(access_path) != 1L || is.na(access_path) || !nzchar(access_path)) {
    stop("access_path is required.")
  }
  if (!file.exists(access_path)) {
    stop("Access project file not found: ", access_path)
  }

  source_project_id <- trimws(as.character(source_project_id %||% ""))
  target_project_id <- trimws(as.character(target_project_id %||% ""))
  if (!is_valid_project_prefix(source_project_id) || !is_valid_project_prefix(target_project_id)) {
    stop("Access import requires valid project ids using letters, numbers, and underscores.")
  }

  source_tables <- project_access_source_tables(access_path, source_project_id)
  if (length(source_tables) == 0) {
    stop("No matching project tables found in Access file for prefix: ", source_project_id)
  }

  target_path <- project_db_path(target_project_id)
  if (file.exists(target_path)) {
    if (!isTRUE(overwrite)) {
      stop("Project database already exists: ", target_path)
    }
    if (project_attached(con, target_project_id)) {
      db_detach(con, target_project_id)
    }
    unlink(target_path)
  }

  project_clone_template(con, target_project_id)
  if (!project_attached(con, target_project_id)) {
    project_attach_file(con, target_path, target_project_id)
  }

  access_con <- DBI::dbConnect(mdbtoolr::mdb(), access_path)
  on.exit(try(DBI::dbDisconnect(access_con), silent = TRUE), add = TRUE)

  imported <- list()
  for (table_name in names(source_tables)) {
    source_table <- source_tables[[table_name]]
    target_id <- project_table_id(target_project_id, table_name)
    if (!DBI::dbExistsTable(con, target_id)) {
      next
    }

    source_data <- tryCatch(DBI::dbReadTable(access_con, source_table, check.names = FALSE), error = function(e) NULL)
    if (is.null(source_data)) {
      stop("Failed to read Access table: ", source_table)
    }

    target_fields <- DBI::dbListFields(con, target_id)
    import_data <- project_import_align_columns(source_data, target_fields, project_id = target_project_id)
    if (nrow(import_data) > 0) {
      DBI::dbAppendTable(con, target_id, import_data)
    }
    imported[[table_name]] <- nrow(import_data)
  }

  list(
    project_id = target_project_id,
    path = target_path,
    tables = imported
  )
}

project_attach_file <- function(con, path, project_id) {
  if (project_attached(con, project_id)) {
    return(invisible(project_id))
  }

  DBI::dbExecute(
    con,
    paste0("ATTACH ", DBI::dbQuoteString(con, path), " AS ", DBI::dbQuoteIdentifier(con, project_id), " (TYPE sqlite)")
  )

  if (!DBI::dbExistsTable(con, project_table_id(project_id, "Metadata"))) {
    db_detach(con, project_id)
    stop("Attached project database is missing the expected metadata table for project ", project_id)
  }

  invisible(project_id)
}

project_clone_template <- function(con, project_id, template_id = PROJECT_TEMPLATE_ID) {
  template_path <- project_db_path(template_id)
  target_path <- project_db_path(project_id)

  if (!file.exists(template_path)) {
    stop("Project template database not found: ", template_path)
  }
  if (file.exists(target_path)) {
    stop("Project database already exists: ", target_path)
  }

  template_alias <- "project_template"
  if (template_alias %in% db_list_attached(con)) {
    db_detach(con, template_alias)
  }

  DBI::dbExecute(
    con,
    paste0("ATTACH ", DBI::dbQuoteString(con, template_path), " AS ", DBI::dbQuoteIdentifier(con, template_alias), " (TYPE sqlite)")
  )
  on.exit(try(db_detach(con, template_alias), silent = TRUE), add = TRUE)

  if (project_attached(con, project_id)) {
    db_detach(con, project_id)
  }
  DBI::dbExecute(
    con,
    paste0("ATTACH ", DBI::dbQuoteString(con, target_path), " AS ", DBI::dbQuoteIdentifier(con, project_id), " (TYPE sqlite)")
  )

  template_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM duckdb_tables() WHERE database_name = ? AND internal = FALSE ORDER BY table_name",
    list(template_alias)
  )$table_name

  template_tables <- template_tables[startsWith(template_tables, paste0(template_id, "_"))]
  for (template_tbl in template_tables) {
    suffix <- sub(paste0("^", template_id, "_"), "", template_tbl)
    target_tbl <- paste0(project_id, "_", suffix)
    DBI::dbExecute(
      con,
      paste0(
        "CREATE TABLE ", DBI::dbQuoteIdentifier(con, DBI::Id(project_id, target_tbl)),
        " AS SELECT * FROM ", DBI::dbQuoteIdentifier(con, DBI::Id(template_alias, template_tbl)),
        " WHERE 1 = 0"
      )
    )
  }

  invisible(target_path)
}

project_baseline_dir <- function() {
  dir_path <- file.path(getwd(), "data", "project_baselines")
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, mustWork = FALSE)
}

project_baseline_path <- function(project_id) {
  safe_id <- gsub("[^A-Za-z0-9_-]", "_", as.character(project_id %||% ""))
  file.path(project_baseline_dir(), paste0(safe_id, "_baseline.db"))
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
    path = baseline_path
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

  resolved_table <- project_file_resolve_table(baseline_path, table_name, project_id = project_id)
  if (is.na(resolved_table)) return(data.frame())

  handle <- tryCatch(project_file_connect(baseline_path), error = function(e) NULL)
  if (is.null(handle)) return(data.frame())
  on.exit(project_file_disconnect(handle), add = TRUE)

  bcon <- handle$con
  table_id <- if (isTRUE(handle$is_sqlite)) DBI::Id(handle$alias, resolved_table) else resolved_table

  if (!DBI::dbExistsTable(bcon, table_id)) return(data.frame())
  fields <- tryCatch(DBI::dbListFields(bcon, table_id), error = function(e) character(0))
  pk_field <- .project_find_field(fields, pk_name)
  if (is.na(pk_field)) return(data.frame())

  if (is.null(pk_values) || length(pk_values) == 0) {
    return(DBI::dbReadTable(bcon, table_id))
  }

  placeholders <- paste(rep("?", length(pk_values)), collapse = ", ")
  DBI::dbGetQuery(
    bcon,
    paste0(
      "SELECT * FROM ", DBI::dbQuoteIdentifier(bcon, table_id),
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

  all(vapply(required_tables, function(tbl) !is.na(project_file_resolve_table(baseline_path, tbl, project_id = project_id)), logical(1)))
}

project_baseline_file_has_tables <- function(path, required_tables = c("Env", "SU", "Veg")) {
  if (is.null(path) || !nzchar(as.character(path)) || !file.exists(path)) return(FALSE)

  prefixes <- project_file_prefixes(path)
  project_id <- if (length(prefixes) == 1) prefixes[[1]] else NULL
  all(vapply(required_tables, function(tbl) !is.na(project_file_resolve_table(path, tbl, project_id = project_id)), logical(1)))
}

project_replace_baseline_from_file <- function(con,
                                               project_id,
                                               source_path,
                                               source_file_path = NULL,
                                               source_kind = "sync_backup_upload",
                                               required_tables = c("Env", "SU", "Veg")) {
  if (is.null(project_id) || !nzchar(as.character(project_id %||% ""))) {
    stop("project_id is required.")
  }
  if (is.null(source_path) || !nzchar(as.character(source_path %||% ""))) {
    stop("source_path is required.")
  }
  if (!file.exists(source_path)) {
    stop("Backup file not found: ", source_path)
  }
  if (!project_baseline_file_has_tables(source_path, required_tables = required_tables)) {
    stop("Selected backup file does not contain the required VPro project tables.")
  }

  project_ensure_baseline_table(con)

  baseline_path <- project_baseline_path(project_id)
  if (file.exists(baseline_path)) {
    unlink(baseline_path, force = TRUE)
  }

  if (!isTRUE(file.copy(source_path, baseline_path, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE))) {
    stop("Failed to register the selected backup file as the project baseline.")
  }

  file_info <- file.info(baseline_path)
  file_md5 <- tryCatch(unname(tools::md5sum(baseline_path)[[1]]), error = function(e) NA_character_)
  recorded_source <- source_file_path %||% source_path

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
      as.character(recorded_source),
      as.character(source_kind %||% "sync_backup_upload"),
      if (nrow(file_info) == 0 || is.na(file_info$size[[1]])) NA_integer_ else as.numeric(file_info$size[[1]]),
      file_md5
    )
  )

  project_get_baseline(con, project_id)
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

list_open_projects <- function(con) {
  attached <- setdiff(
    db_list_attached(con),
    c("memory", "system", "temp", "VLists", "VMetaData", "VUser", "VMessageBoard", "VPics")
  )

  projects <- attached[vapply(
    attached,
    function(project_id) {
      tryCatch(DBI::dbExistsTable(con, project_table_id(project_id, "Metadata")), error = function(e) FALSE)
    },
    logical(1)
  )]

  sort(unique(projects))
}

open_project <- function(con, path, project_id = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Project file path is required.")
  }
  if (!file.exists(path)) {
    stop("Project file not found: ", path)
  }

  project_ids <- list_projects_in_file(path)
  if (length(project_ids) == 0) {
    stop("Could not detect project tables from project file: ", path)
  }
  if (is.null(project_id)) {
    if (length(project_ids) > 1) {
      stop("Project file contains multiple project prefixes. Specify which project to open.")
    }
    project_id <- project_ids[[1]]
  }
  if (!(project_id %in% project_ids)) {
    stop("Project ", project_id, " was not found in file: ", path)
  }

  project_attach_file(con, path, project_id)

  project_id
}

save_project <- function(con, project_id, path) {
  if (is.null(project_id) || !nzchar(project_id)) stop("project_id is required.")
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("Project file path is required.")
  }

  source_path <- project_db_path(project_id)
  if (!file.exists(source_path)) {
    stop("Project database not found: ", source_path)
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (normalizePath(source_path, mustWork = TRUE) == normalizePath(path, mustWork = FALSE)) {
    return(invisible(path))
  }

  ok <- file.copy(source_path, path, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)
  if (!isTRUE(ok)) {
    stop("Failed to save project database to ", path)
  }

  invisible(path)
}

close_project <- function(con, project_id, path = NULL) {
  if (is.null(project_id) || !nzchar(project_id)) stop("project_id is required.")

  if (!is.null(path) && nzchar(path)) {
    save_project(con, project_id, path)
  }

  if (project_attached(con, project_id)) {
    db_detach(con, project_id)
  }

  invisible(project_id)
}

new_project <- function(con, project_id, project_title) {
  if (is.null(project_id) || !nzchar(trimws(project_id))) stop("project_id is required.")
  if (is.null(project_title) || !nzchar(trimws(project_title))) stop("project_title is required.")

  project_id    <- trimws(project_id)
  project_title <- trimws(project_title)

  if (project_exists(con, project_id)) {
    stop("Project '", project_id, "' already exists.")
  }

  project_clone_template(con, project_id)
  if (!project_attached(con, project_id)) {
    project_attach_file(con, project_db_path(project_id), project_id)
  }

  meta_id <- project_table_id(project_id, "Metadata")
  meta_cols <- tolower(DBI::dbListFields(con, meta_id))
  title_col <- if ("projecttitle" %in% meta_cols) "projecttitle" else if ("projectname" %in% meta_cols) "projectname" else NULL

  field_names <- c("projectid", if (!is.null(title_col)) title_col)
  field_sql <- paste(DBI::dbQuoteIdentifier(con, field_names), collapse = ", ")
  values_sql <- paste(rep("?", length(field_names)), collapse = ", ")
  params <- c(list(project_id), if (!is.null(title_col)) list(project_title))

  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO ", DBI::dbQuoteIdentifier(con, meta_id),
      " (", field_sql, ") VALUES (", values_sql, ")"
    ),
    params
  )

  env_id <- project_table_id(project_id, "Env")
  if (DBI::dbExistsTable(con, env_id) && "projectid" %in% tolower(DBI::dbListFields(con, env_id))) {
    DBI::dbExecute(
      con,
      paste0(
        "UPDATE ", DBI::dbQuoteIdentifier(con, env_id),
        " SET ", DBI::dbQuoteIdentifier(con, "ProjectID"), " = ?",
        " WHERE ", DBI::dbQuoteIdentifier(con, "ProjectID"), " IS NULL"
      ),
      list(project_id)
    )
  }

  invisible(project_id)
}

list_projects_in_file <- function(path) {
  project_file_prefixes(path)
}

#' Check if a project exists in Metadata
#'
#' @param con DBI connection
#' @param project_id Character
#' @return Logical
project_exists <- function(con, project_id) {
  if (is.null(project_id) || !nzchar(project_id %||% "")) {
    return(FALSE)
  }

  project_attached(con, project_id) || file.exists(project_db_path(project_id))
}
