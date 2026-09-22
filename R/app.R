# Application --------------------------------------------------------------

#' Run the VPRO Shiny application
#'
#' User storage is initialized before the packaged application is launched.
#'
#' @param ... Arguments passed to [shiny::runApp()].
#'
#' @return The value returned by [shiny::runApp()].
#' @export
run_vpro <- function(...) {
  vpro_install()
  shiny::runApp(vpro_bundled_file("app"), ...)
}
