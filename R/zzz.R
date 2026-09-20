.onAttach <- function(libname, pkgname) {
  # Setup theme
  if (!"bcgov" %in% bslib::bootswatch_themes()) {
    bcgov_theme("install")
  }

  # Setup user local database storage (auto detection)
  vpro_data_install()

  # Launch app
  shiny::runApp(system.file("app", package = "vpro"), launch.browser = TRUE)
}

#' Install vpro package data files into the user data directory
#'
#' Copies subdirectories and files from the package's installed \code{data}
#' directory into the user data directory (as returned by
#' \code{\link[rappdirs]{user_data_dir}}), creating any missing
#' subdirectories along the way. Files that don't yet exist in the user data
#' directory are always copied. Existing files are left untouched unless
#' \code{replace} indicates otherwise.
#'
#' @param replace Controls behaviour when a destination file already exists:
#'   \describe{
#'     \item{\code{FALSE}}{(default) Never overwrite existing files.}
#'     \item{\code{TRUE}}{Always overwrite existing files, without prompting.}
#'     \item{\code{"ask"}}{Prompt interactively for each existing file,
#'       offering the choice to replace it (\code{Yes}), skip it
#'       (\code{No}), replace all remaining files (\code{All}), or skip all
#'       remaining files (\code{None}). Only available in interactive
#'       sessions; falls back to \code{FALSE} otherwise.}
#'   }
#'
#' @return Invisibly returns the path to the user data directory.
#' @export
vpro_data_install <- function(replace = FALSE) {
  d <- rappdirs::user_data_dir("vpro")
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  s <- system.file("data", package = "vpro")

  ask <- identical(replace, "ask")
  if (ask && !interactive()) {
    message("`replace = \"ask\"` requires an interactive session; falling back to `replace = FALSE`.")
    ask <- FALSE
    replace <- FALSE
  }

  # Once the user picks "All"/"None" in response to a prompt, remember it
  # so we stop asking for the remaining files.
  decision <- NULL

  # Copy subdirectories and files from system.file vpro package data dir to
  # user data dir if they don't exist, prompting for replacement if they
  # already exist and `replace` requests it.
  for (f in list.files(s, recursive = TRUE, include.dirs = TRUE)) {
    src <- file.path(s, f)
    dest <- file.path(d, f)

    if (file.info(src)$isdir) {
      dir.create(dest, showWarnings = FALSE, recursive = TRUE)
      next
    }

    dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)

    exists <- file.exists(dest)
    do_copy <- !exists

    if (exists) {
      if (isTRUE(replace)) {
        do_copy <- TRUE
      } else if (ask) {
        if (!is.null(decision)) {
          do_copy <- decision == "All"
        } else {
          choice <- utils::menu(
            c("Yes", "No", "All", "None"),
            title = sprintf("File already exists [%s]\nReplace it?", f)
          )
          choice <- c("Yes", "No", "All", "None")[choice]
          if (choice %in% c("All", "None")) decision <- choice
          do_copy <- choice %in% c("Yes", "All")
        }
      }
    }

    if (do_copy) file.copy(src, dest, overwrite = TRUE)
  }

  invisible(d)
}

#' Install or remove the BC Government theme for bslib
#'
#' Injects the bcgov Bootswatch theme files directly into the installed bslib
#' package so that \code{"bcgov"} becomes available as a theme name.
#'
#' @param action Character. Either \code{"install"} (default) to copy theme
#'   files into bslib, or \code{"remove"} to delete them.
#'
#' @return Invisibly returns \code{NULL}.
#' @export
bcgov_theme <- function(action = c("install", "remove")) {
  action <- match.arg(action)

  # Injecting bcgov theme directly into bslib library
  target <- find.package("bslib")
  if (file.access(target, 2) < 0) {
    warning("Package `bslib` path is not writable [", target, "].\nCannot install vpro bcgov theme.")
    return()
  }

  src <- system.file("theme", package = "vpro")
  f <- dir(src, recursive = TRUE) |> grep("^fonts|^lib", x = _, value = TRUE)

  if (action == "install") {
    lapply(file.path(target, unique(dirname(f))), dir.create, showWarnings = FALSE, recursive = TRUE)
    file.copy(file.path(src, f), file.path(target, f), overwrite = TRUE)
  }

  if (action == "remove") {
    unlink(file.path(target, f))
    unlink(file.path(target, "lib/bsw5/dist/bcgov"), recursive = TRUE)
  }

  return(invisible())
}
