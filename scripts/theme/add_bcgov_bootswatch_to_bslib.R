setwd(system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = NULL))
# App Theme ----
bcgov_theme <- function(action = c("install", "remove")) {
  action <- match.arg(action)

  # Injecting bcgov theme directly into bslib library
  target <- find.package("bslib")
  if (file.access(target, 2) < 0) {
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

if (!"bcgov" %in% bslib::bootswatch_themes()) {
  bcgov_theme("install")
}

# bcgov_theme("remove");bcgov_theme("install")
# unlink("theme/lib", recursive = TRUE)
# unlink("theme/fonts", recursive = TRUE)
