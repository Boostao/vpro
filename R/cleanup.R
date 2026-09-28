# User storage cleanup ----------------------------------------------------

vpro_cleanup_dir <- function(path, prompt = readline) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path) ||
      !grepl("^/", path) ||
      path %in% c("/", normalizePath(path.expand("~"), mustWork = FALSE), normalizePath(getwd(), mustWork = FALSE))
  ) {
    stop("Refusing to remove an unsafe VPRO storage directory: ", path, call. = FALSE)
  }
  if (!is.function(prompt)) {
    stop("`prompt` must be a function.", call. = FALSE)
  }
  link <- Sys.readlink(path)
  if (!is.na(link) && nzchar(link)) {
    stop("Refusing to remove a symbolic-link VPRO storage directory: ", path, call. = FALSE)
  }
  if (!dir.exists(path)) {
    if (file.exists(path)) {
      stop("VPRO storage path is not a directory: ", path, call. = FALSE)
    }
    return(invisible(list(deleted = character(), skipped = character(), cancelled = FALSE)))
  }
  if (identical(prompt, readline) && !interactive()) {
    stop("VPRO cleanup requires an interactive R console.", call. = FALSE)
  }

  deleted <- character()
  skipped <- character()
  cancelled <- FALSE
  visit <- function(dir) {
    entries <- list.files(dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    for (entry in entries) {
      link <- Sys.readlink(entry)
      if (!is.na(link) && nzchar(link)) {
        stop("Refusing to clean a symbolic link: ", entry, call. = FALSE)
      }
      if (dir.exists(entry)) {
        visit(entry)
      } else {
        repeat {
          answer <- prompt(paste0("Delete ", entry, "? [y/n/c] "))
          if (!is.character(answer) || length(answer) != 1L || is.na(answer)) {
            answer <- ""
          }
          answer <- tolower(trimws(answer))
          if (answer %in% c("y", "n", "c", "")) {
            break
          }
        }
        if (answer %in% c("c", "")) {
          cancelled <<- TRUE
          return(invisible(NULL))
        }
        if (answer == "n") {
          skipped <<- c(skipped, entry)
        } else {
          if (unlink(entry) != 0L || file.exists(entry)) {
            stop("Could not remove VPRO file: ", entry, call. = FALSE)
          }
          deleted <<- c(deleted, entry)
        }
      }
      if (cancelled) {
        return(invisible(NULL))
      }
    }
    if (
      length(list.files(dir, all.files = TRUE, no.. = TRUE)) == 0L &&
        unlink(dir, recursive = TRUE) != 0L
    ) {
      stop("Could not remove empty VPRO directory: ", dir, call. = FALSE)
    }
    invisible(NULL)
  }
  visit(path)
  invisible(list(deleted = deleted, skipped = skipped, cancelled = cancelled))
}

#' Interactively clean VPRO user configuration
#'
#' Prompts for each file beneath the resolved configuration directory. Respond
#' `y` to delete, `n` to keep, or `c` (or an empty response) to stop. Empty
#' directories are removed; directories containing kept files remain. Close the
#' app and configuration accessors first. After deleting `config.yml`, the next
#' `run_vpro()` recreates the default configuration.
#'
#' @return An invisible list of deleted paths, skipped paths, and a `cancelled`
#'   flag. A missing directory returns empty paths without prompting.
#' @export
vpro_config_cleanup <- function() {
  on.exit(
    {
      .vpro_runtime$config <- NULL
      .vpro_runtime$config_path <- NULL
    },
    add = TRUE
  )
  vpro_cleanup_dir(vpro_config_dir())
}

#' Interactively clean VPRO user data
#'
#' Prompts for each file beneath the resolved data directory, including
#' imported projects, edited SQLite databases, and non-bundled files. Respond
#' `y` to delete, `n` to keep, or `c` (or an empty response) to stop. Empty
#' directories are removed; directories containing kept files remain. Back up
#' anything needed and close the app and database connections first. If all
#' bundled data is deleted, the next `run_vpro()` copies it back.
#'
#' @return An invisible list of deleted paths, skipped paths, and a `cancelled`
#'   flag. A missing directory returns empty paths without prompting.
#' @export
vpro_data_cleanup <- function() {
  vpro_cleanup_dir(vpro_data_dir())
}
