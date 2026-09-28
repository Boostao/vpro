# Application --------------------------------------------------------------

#' Run the VPRO Shiny application
#'
#' User storage is initialized before the packaged application is launched.
#' The first online launch installs DuckDB's SQLite extension if absent;
#' subsequent launches use the cached extension and work offline. If offline
#' before the extension is cached, startup fails with setup guidance.
#'
#' @param ... Arguments passed to [shiny::runApp()].
#'
#' @return The value returned by [shiny::runApp()].
#' @export
run_vpro <- function(...) {
  con <- tryCatch(
    vpro_db_connect(install_extensions = TRUE),
    error = function(e) {
      stop("DuckDB's SQLite extension is unavailable. Connect while online ", "to cache it before using VPRO offline: ", conditionMessage(e), call. = FALSE)
    }
  )
  vpro_db_disconnect(con)
  vpro_install()
  vpro_validate_bcgov_theme()
  shiny::runApp(shiny::shinyAppDir(vpro_bundled_file("app")), ...)
}
