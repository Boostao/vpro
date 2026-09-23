# Configuration ------------------------------------------------------------

.vpro_runtime <- new.env(parent = emptyenv())

#' Locate the VPRO user configuration directory
#'
#' @return A normalized directory path.
#' @export
vpro_config_dir <- function() {
  path <- getOption("vpro.config_dir", Sys.getenv("VPRO_CONFIG_DIR", unset = ""))
  if (!nzchar(path)) {
    path <- rappdirs::user_config_dir("vpro")
  }
  normalizePath(path, mustWork = FALSE)
}

#' Locate the VPRO user data directory
#'
#' @return A normalized directory path.
#' @export
vpro_data_dir <- function() {
  path <- getOption("vpro.data_dir", Sys.getenv("VPRO_DATA_DIR", unset = ""))
  if (!nzchar(path)) {
    path <- rappdirs::user_data_dir("vpro")
  }
  normalizePath(path, mustWork = FALSE)
}

vpro_config_file <- function() {
  file.path(vpro_config_dir(), "config.yml")
}

vpro_bundled_file <- function(...) {
  path <- system.file(..., package = "vpro")
  if (!nzchar(path)) {
    stop("Bundled VPRO resource was not found: ", file.path(...), call. = FALSE)
  }
  path
}

#' Initialize a VPRO configuration accessor
#'
#' The returned function reads and updates one YAML configuration file. Updates
#' are written atomically. Most callers should use `vpro_config_get()` and
#' `vpro_config_set()` instead of constructing an accessor directly.
#'
#' @param path Path to a YAML configuration file.
#' @param create Create the file from the package default when it is absent.
#'
#' @return A configuration accessor function.
#' @export
config_init <- function(path = vpro_config_file(), create = TRUE) {
  if (!file.exists(path)) {
    if (!isTRUE(create)) {
      stop("VPRO configuration does not exist: ", path, call. = FALSE)
    }
    vpro_config_install(path = path)
  }

  cfg <- yaml::read_yaml(path, readLines.warn = FALSE)
  if (!is.list(cfg)) {
    stop("VPRO configuration must contain a YAML mapping: ", path, call. = FALSE)
  }

  function(section, key, value) {
    if (missing(section)) {
      return(cfg)
    }
    if (!section %in% names(cfg)) {
      stop("Unknown VPRO configuration section: ", section, call. = FALSE)
    }
    if (missing(key)) {
      return(cfg[[section]])
    }
    if (!key %in% names(cfg[[section]])) {
      stop("Unknown VPRO configuration key: ", section, ".", key, call. = FALSE)
    }
    if (missing(value)) {
      return(cfg[[section]][[key]])
    }

    cfg[[section]][[key]] <<- value
    vpro_write_yaml(cfg, path)
    invisible(value)
  }
}

vpro_write_yaml <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "config-", tmpdir = dirname(path), fileext = ".yml")
  on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(value, temporary)
  if (file.exists(path) && unlink(path) != 0L) {
    stop("Could not remove the previous VPRO configuration: ", path, call. = FALSE)
  }
  if (!file.rename(temporary, path)) {
    stop("Could not replace VPRO configuration: ", path, call. = FALSE)
  }
  invisible(path)
}

vpro_config_accessor <- function(refresh = FALSE) {
  path <- vpro_config_file()
  cached_path <- .vpro_runtime$config_path
  if (isTRUE(refresh) || is.null(.vpro_runtime$config) || !identical(cached_path, path)) {
    .vpro_runtime$config <- config_init(path)
    .vpro_runtime$config_path <- path
  }
  .vpro_runtime$config
}

# Compatibility accessor for code translated from registry-backed VBA state.
config <- function(section, key, value) {
  accessor <- vpro_config_accessor()
  if (missing(section)) {
    return(accessor())
  }
  if (missing(key)) {
    return(accessor(section))
  }
  if (missing(value)) {
    return(accessor(section, key))
  }
  accessor(section, key, value)
}

#' Read a VPRO configuration value
#'
#' @param section Configuration section.
#' @param key Configuration key. If omitted, returns the complete section.
#'
#' @return The requested configuration value or section.
#' @export
vpro_config_get <- function(section, key) {
  if (missing(key)) {
    return(config(section))
  }
  config(section, key)
}

#' Set a VPRO configuration value
#'
#' @param section Configuration section.
#' @param key Configuration key.
#' @param value Replacement value.
#'
#' @return `value`, invisibly.
#' @export
vpro_config_set <- function(section, key, value) {
  config(section, key, value)
}
