# Guided project opening ---------------------------------------------------

#' Discover project families in a SQLite or Access file
#'
#' @param path Existing `.db`, `.sqlite`, `.mdb`, or `.accdb` file.
#' @param file_name Original filename, needed when `path` is a Shiny upload.
#' @return Data frame with project, version, and whether it can be opened.
#' @export
vpro_project_file_families <- function(path, file_name = basename(path)) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("Select an existing VPRO project file.", call. = FALSE)
  }
  extension <- tolower(tools::file_ext(file_name))
  if (extension %in% c("mdb", "accdb")) {
    inventory <- vpro_access_inspect(path)
    tables <- inventory$tables$table_name
    description <- inventory$tables$description
  } else if (extension %in% c("db", "sqlite", "sqlite3")) {
    con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tables <- DBI::dbListTables(con)
    description <- rep(NA_character_, length(tables))
    if ("_table_metadata" %in% tables) {
      metadata <- DBI::dbGetQuery(con, 'SELECT table_name, description FROM "_table_metadata"')
      description <- metadata$description[match(tables, metadata$table_name)]
    }
  } else {
    stop("Choose a SQLite (.db) or Access (.mdb/.accdb) file.", call. = FALSE)
  }
  env <- grep("^[A-Za-z][A-Za-z0-9_]{0,30}_Env$", tables)
  env <- env[!tables[env] %in% c("Filtered_Env", "USysEnv")]
  projects <- sub("_Env$", "", tables[env])
  complete <- vapply(
    projects,
    function(project) {
      all(paste0(project, "_", .vpro_core_project_suffixes) %in% tables)
    },
    logical(1)
  )
  result <- data.frame(
    project = projects,
    version = description[env],
    compatible = complete & !is.na(description[env]) & description[env] == "VP08",
    stringsAsFactors = FALSE
  )
  result[order(result$project), , drop = FALSE]
}

#' Copy and open a selected VPRO project
#'
#' Copies a validated SQLite project or archives an Access file before promoting
#' an exact VP08 family. Historical Access families remain archival only. The
#' source is never edited. The caller activates the returned attachment after
#' successful copying; an Access archive is kept even if promotion fails.
#' Names already attached to the context are refused.
#'
#' @param context Session-owned VPRO project context.
#' @param source_path File selected by the user.
#' @param project Project family name inside the file.
#' @param data_dir Managed VPRO user data directory.
#' @param file_name Original filename, needed when `source_path` is a Shiny upload.
#' @return Attached project record, invisibly.
#' @export
vpro_project_open_file <- function(context, source_path, project, data_dir = vpro_data_dir(), file_name = basename(source_path)) {
  vpro_project_assert_context(context)
  project <- vpro_project_name(project)
  families <- vpro_project_file_families(source_path, file_name = file_name)
  family <- families[families$project == project, , drop = FALSE]
  if (nrow(family) != 1L) {
    stop("The selected file has no project named ", project, ".", call. = FALSE)
  }
  if (project %in% names(context$projects)) {
    stop("This project is already open. Select it from the project list instead.", call. = FALSE)
  }
  source_path <- normalizePath(source_path, mustWork = TRUE)
  access <- tolower(tools::file_ext(file_name)) %in% c("mdb", "accdb")
  if (!isTRUE(family$compatible)) {
    stop(
      "Project ",
      project,
      " is ",
      if (is.na(family$version)) "unversioned" else family$version,
      ". Only complete VP08 projects can currently be opened; the original file was not changed.",
      call. = FALSE
    )
  }
  directory <- file.path(data_dir, "projects")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  if (identical(normalizePath(dirname(source_path)), normalizePath(directory))) {
    stop("This file is already in VPRO's project storage; choose it from the project list.", call. = FALSE)
  }
  destination <- file.path(directory, paste0(project, ".db"))
  archive <- file.path(directory, paste0(project, "-access-archive.db"))
  if (file.exists(destination) || (access && file.exists(archive))) {
    stop("A saved copy of ", project, " already exists. No files were replaced.", call. = FALSE)
  }
  if (access) {
    vpro_access_archive(source_path, archive)
    vpro_access_promote_vp08(archive, project, destination)
  } else {
    vpro_project_inspect(source_path, project)
    if (!file.copy(source_path, destination, overwrite = FALSE)) {
      stop("Could not copy the selected project into VPRO storage.", call. = FALSE)
    }
    if (!identical(unname(tools::md5sum(source_path)), unname(tools::md5sum(destination)))) {
      unlink(destination)
      stop("The copied project did not match the source.", call. = FALSE)
    }
  }
  record <- tryCatch(vpro_project_attach(context, destination, project), error = function(e) {
    if (!access) {
      unlink(destination)
    }
    stop(e)
  })
  invisible(record)
}
