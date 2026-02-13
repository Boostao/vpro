#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
quiet <- any(args %in% c("--quiet", "-q"))

log_msg <- function(...) {
  if (!quiet) message(...)
}

if (!requireNamespace("sass", quietly = TRUE)) {
  stop("Missing package 'sass'. Install via renv::restore() or install.packages('sass').")
}
if (!requireNamespace("bslib", quietly = TRUE)) {
  stop("Missing package 'bslib'. Install via renv::restore() or install.packages('bslib').")
}

repo_root <- getwd()
scss_in <- file.path(repo_root, "assets", "bcgov_theme.scss")
out_dir <- file.path(repo_root, "www", "bcgov")
out_css <- file.path(out_dir, "bcgov.css")

if (!file.exists(scss_in)) {
  stop("SCSS entrypoint not found: ", scss_in)
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Local BC Gov theme sources
bsw5_dist <- file.path(repo_root, "lib", "bsw5", "dist")
if (!dir.exists(bsw5_dist)) {
  stop("BC Gov SCSS sources not found (expected directory): ", bsw5_dist)
}

# Bootstrap 5 SCSS shipped inside bslib
bs5_scss <- system.file("lib/bs5/scss", package = "bslib")
if (identical(bs5_scss, "") || !dir.exists(bs5_scss)) {
  stop("Could not locate Bootstrap 5 SCSS in bslib at: ", bs5_scss)
}

log_msg("Compiling BC Gov theme SCSS -> ", out_css)

css <- sass::sass(
  input = sass::sass_file(scss_in),
  options = sass::sass_options(
    output_style = "compressed",
    source_map_embed = FALSE,
    source_map_contents = FALSE,
    include_path = paste(c(bsw5_dist, bs5_scss), collapse = .Platform$path.sep)
  )
)

# Write deterministically (no timestamps)
header <- "/* Auto-generated. Source: assets/bcgov_theme.scss */\n"
writeLines(c(header, as.character(css), ""), out_css)

log_msg("Done.")
