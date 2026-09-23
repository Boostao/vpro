# Package hooks ------------------------------------------------------------

.onLoad <- function(libname, pkgname) {
  options(duckdb.extension_directory = rappdirs::user_cache_dir("vpro"))
  invisible(NULL)
}
