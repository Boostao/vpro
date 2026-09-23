# Installation -------------------------------------------------------------

#' Install the default VPRO configuration
#'
#' @param path Destination YAML file.
#' @param overwrite Whether to replace an existing configuration.
#'
#' @return The destination path, invisibly.
#' @export
vpro_config_install <- function(path = vpro_config_file(), overwrite = FALSE) {
  if (file.exists(path) && !isTRUE(overwrite)) {
    return(invisible(path))
  }

  source <- vpro_bundled_file("config.init.yml")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source, path, overwrite = isTRUE(overwrite))) {
    stop("Could not install the default VPRO configuration: ", path, call. = FALSE)
  }
  invisible(path)
}

#' Install bundled VPRO data files
#'
#' Copies missing package data files to the VPRO user data directory. Existing
#' files are preserved unless `overwrite = TRUE`.
#'
#' @param path Destination data directory.
#' @param overwrite Whether to replace existing files.
#'
#' @return The destination directory, invisibly.
#' @export
vpro_data_install <- function(path = vpro_data_dir(), overwrite = FALSE) {
  source <- vpro_bundled_file("extdata")
  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  files <- list.files(source, recursive = TRUE, full.names = FALSE, include.dirs = FALSE)
  for (relative in files) {
    destination <- file.path(path, relative)
    if (file.exists(destination) && !isTRUE(overwrite)) {
      next
    }
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(source, relative), destination, overwrite = isTRUE(overwrite))) {
      stop("Could not install VPRO data file: ", relative, call. = FALSE)
    }
  }

  invisible(path)
}

#' Initialize VPRO user storage
#'
#' @param overwrite Whether to replace existing bundled data and configuration.
#'
#' @return A list containing the installed data directory and configuration
#'   file, invisibly.
#' @export
vpro_install <- function(overwrite = FALSE) {
  result <- list(
    data_dir = vpro_data_install(overwrite = overwrite),
    config_file = vpro_config_install(overwrite = overwrite)
  )
  invisible(result)
}
