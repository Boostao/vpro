# Headless startup ----------------------------------------------------------

#' Recover a VPRO project for an application session
#'
#' Creates a session-owned coordinator, restores the configured project, site
#' unit and hierarchy (falling back to Sample), and attaches the bundled system
#' databases for cross-database queries. The caller must close `context` with
#' [vpro_project_close()]. It creates connection-local reference views and
#' reads reference descriptions; logging is controlled by the app session.
#' It does not mutate reference schemas or install DuckDB extensions.
#'
#' @param config Configuration accessor returned by [config_init()].
#' @param data_dir Directory containing installed VPRO databases.
#' @return A list with `context`, `recovery`, `system_databases`,
#'   `reference_descriptions`, `reference_diagnostics`, and `project_diagnostics`.
#' @export
vpro_startup <- function(config = config_init(), data_dir = vpro_data_dir()) {
  context <- vpro_project_context(config = config, install_extensions = FALSE)
  ok <- FALSE
  on.exit(if (!ok) vpro_project_close(context), add = TRUE)

  system_names <- c("VPro64", "VLists", "VUser", "VMetaData", "VMessageBoard")
  system_paths <- vpro_db_path(system_names, root = data_dir)
  vpro_db_attach(context$con, system_paths)
  reference_diagnostics <- vpro_startup_reference_views(context)
  reference_descriptions <- vpro_reference_descriptions(context)
  recovery <- vpro_project_recover(
    context,
    sample_path = vpro_db_path("Sample", "projects", root = data_dir)
  )
  project_diagnostics <- data.frame(file = character(), message = character(), stringsAsFactors = FALSE)
  candidates <- list.files(file.path(data_dir, "projects"), pattern = "\\.db$", full.names = TRUE)
  for (path in candidates) {
    if (identical(normalizePath(path), recovery$active$path) || grepl("-access-archive\\.db$", path)) {
      next
    }
    result <- tryCatch(
      {
        families <- vpro_project_file_families(path)
        for (index in which(families$compatible)) {
          project <- families$project[[index]]
          if (!(project %in% names(context$projects))) vpro_project_attach(context, path, project)
        }
        NULL
      },
      error = identity
    )
    if (inherits(result, "error")) {
      project_diagnostics <- rbind(project_diagnostics, data.frame(file = path, message = conditionMessage(result)))
    }
  }
  ok <- TRUE
  list(
    context = context,
    recovery = recovery,
    system_databases = system_names,
    reference_descriptions = reference_descriptions,
    reference_diagnostics = reference_diagnostics,
    project_diagnostics = project_diagnostics
  )
}
