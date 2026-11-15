.vpro_cache <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  invisible(NULL)
}

vpro_bundled_file <- function(..., must_work = TRUE) {
  path <- system.file(..., package = "vpro")
  if (!nzchar(path)) {
    # Fallback during pkgload/devtools development if inst/ layout is queried directly
    dev_path <- file.path("inst", ...)
    if (file.exists(dev_path)) {
      path <- normalizePath(dev_path, winslash = "/", mustWork = TRUE)
    } else if (isTRUE(must_work)) {
      rlang::abort(paste0("Bundled vpro resource was not found: ", file.path(...)))
    } else {
      return("")
    }
  }
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

vpro_bundled_db <- function(name) {
  direct <- vpro_bundled_file("extdata", name, must_work = FALSE)
  if (nzchar(direct) && file.exists(direct)) {
    return(direct)
  }
  gz_path <- vpro_bundled_file("extdata", paste0(name, ".gz"), must_work = TRUE)
  cached <- .vpro_cache[[name]]
  if (is.character(cached) && length(cached) == 1L && file.exists(cached)) {
    return(cached)
  }
  cache_dir <- file.path(tempdir(), "vpro-extdata-cache")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  target <- file.path(cache_dir, name)
  if (!file.exists(target)) {
    comp <- readBin(gz_path, what = "raw", n = file.info(gz_path)$size)
    raw_bytes <- memDecompress(comp, type = "gzip")
    tmp <- tempfile(pattern = paste0(name, "-"), tmpdir = cache_dir)
    on.exit(unlink(tmp), add = TRUE)
    writeBin(raw_bytes, tmp)
    if (!file.rename(tmp, target)) {
      file.copy(tmp, target, overwrite = TRUE)
    }
  }
  resolved <- normalizePath(target, winslash = "/", mustWork = TRUE)
  .vpro_cache[[name]] <- resolved
  resolved
}
