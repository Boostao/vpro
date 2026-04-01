# {setwd(system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = NULL))}

# if (!any(grepl("^bslib$", rownames(installed.packages())))) {
#   stop("This script must be run from the after the installation of bslib package")
# }

# # Set working directory to repo root
# bsw5_repo <- "https://github.com/bcgov/bootstrap-v5-theme/archive/refs/heads/master.zip"
# z <- tempfile(fileext = ".zip")
# curl::curl_download(bsw5_repo, z)
# f <- unzip(z, list = TRUE)$Name

# # Copy fonts
# f1 <- grep("/dist/fonts/.+woff2?", f, value = TRUE)
# dir.create("theme/fonts", showWarnings = FALSE)
# unzip(z, f1, junkpaths = TRUE, exdir = "theme/fonts", overwrite = TRUE)

# # Copy images
# f2 <- grep("/dist/images/.+(png|svg)", f, value = TRUE)
# dir.create("www/images", showWarnings = FALSE)
# unzip(z, f2, junkpaths = TRUE, exdir = "www/images", overwrite = TRUE)

# # SCSS files
# f3 <- grep("/dist/scss/.+scss", f, value = TRUE)
# unlink("theme/lib/bsw5/dist/bcgov/", recursive = TRUE)
# dir.create("theme/lib/bsw5/dist/bcgov/", showWarnings = FALSE)
# unzip(z, f3, junkpaths = TRUE, exdir = "theme/lib/bsw5/dist/bcgov/", overwrite = TRUE)

# #Font file
# f4 <- grep("_fonts.scss", dir("theme/lib/bsw5/dist/bcgov", recursive = TRUE, full.names = TRUE), value = TRUE)
# f5 <- readLines(f4, warn = FALSE) |> gsub("../fonts/bc-sans", "fonts", x = _)
# writeLines(f5, f4)

# # Appending
# f6 <- grep("_additions.scss|_overrides.scss", dir("theme/lib/bsw5/dist/bcgov", recursive = TRUE, full.names = TRUE), value = TRUE)
# bsw <- "theme/lib/bsw5/dist/bcgov/_bootswatch.scss"
# file.create(bsw)
# lapply(f6, file.append, file1 = bsw)
# cat('
# $web-font-path: "font.css" !default;
# @if $web-font-path {
#   @import url($web-font-path);
# }
# ', file = bsw, append = TRUE)
# unlink(f6)

# # Drop unneeded
# f7 <- grep("_common.scss|bootstrap-theme.scss", dir("theme/lib/bsw5/dist/bcgov", recursive = TRUE, full.names = TRUE), value = TRUE)
# unlink(f7)

# # Files renaming
# file.rename(f4, sub("_fonts.scss","font.css", f4))

# # Patching
# f8 <- readLines(bsw)
# f8 <- gsub("^header nav", "nav.navbar-static-top", f8)
# writeLines(f8, bsw)

# v <- "theme/lib/bsw5/dist/bcgov/_variables.scss"
# cat(c("\n$nav-underline-border-width: 0rem !default;", '\n$theme: "bcgov" !default;', '\n$navbar-bg: theme-color(primary-nav);'), file = v, append = TRUE)

# App Theme ----
bcgov_theme <- function(action = c("install","remove")) {
  action <- match.arg(action)

  # Injecting bcgov theme directly into bslib library
  target <- find.package("bslib")
  if (file.access(target,2) < 0) {
    stop("This must be run with write access to the bslib package")
  }

  src <- "./theme"
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

# if (!"bcgov" %in% bslib::bootswatch_themes()) {
#   bcgov_theme("install")
# }

# unlink("theme/lib", recursive = TRUE)
# unlink("theme/fonts", recursive = TRUE)
