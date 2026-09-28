# Application theme ---------------------------------------------------------

#' Build the bundled BC government theme
#'
#' Reproduces bslib's BCgov Bootswatch preset using the Sass and BCSans fonts
#' shipped with VPRO, without modifying the installed bslib package.
#'
#' @return A bslib theme.
#' @export
vpro_bcgov_theme <- function() {
  theme_dir <- vpro_bundled_file("theme", "lib", "bsw5", "dist", "bcgov")
  fonts_dir <- vpro_bundled_file("theme", "fonts")
  assets <- file.path(theme_dir, c("_variables.scss", "_bootswatch.scss", "font.css"))
  if (
    !all(file.exists(assets)) ||
      !all(file.exists(file.path(
        fonts_dir,
        c(
          "BCSans-Regular.woff2",
          "BCSans-Bold.woff2",
          "BCSans-Italic.woff2",
          "BCSans-BoldItalic.woff2"
        )
      )))
  ) {
    stop("The bundled BC government theme is incomplete.", call. = FALSE)
  }

  layer <- sass::sass_layer(
    file_attachments = c(font.css = assets[[3L]], fonts = fonts_dir),
    defaults = list(
      `bslib-preset-type` = "bootswatch",
      `bslib-preset-name` = "bcgov",
      '$web-font-path: "font.css" !default;',
      sass::sass_file(assets[[1L]])
    ),
    rules = list(
      sass::sass_file(assets[[2L]]),
      "",
      ".btn-default:not(.btn-primary):not(.btn-info):not(.btn-success):not(.btn-warning):not(.btn-danger):not(.btn-dark):not(.btn-light):not([class*='btn-outline-']) { @extend .btn-secondary !optional; }"
    )
  )
  bslib::bs_bundle(bslib::bs_theme(version = 5, preset = "bootstrap"), bootswatch = layer)
}

vpro_validate_bcgov_theme <- function() {
  tryCatch(
    bslib::bs_theme_dependencies(vpro_bcgov_theme()),
    error = function(e) {
      stop("Cannot compile the bundled BC government theme: ", conditionMessage(e), call. = FALSE)
    }
  )
  invisible(TRUE)
}
