#!/usr/bin/env Rscript
# Usage: Rscript data-raw/parity/run_inventory.R --source /path/to/export --target . [--output data-raw/parity/generated]
args <- commandArgs(trailingOnly = TRUE)
value <- function(key, default = NULL) {
  i <- match(key, args)
  if (!is.na(i) && i < length(args)) args[i + 1L] else default
}
`%||%` <- function(x, y) if (is.null(x)) y else x
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- normalizePath(sub("^--file=", "", file_arg[1] %||% "data-raw/parity/run_inventory.R"), mustWork = FALSE)
base <- dirname(script)
source(file.path(base, "R", "io.R"))
source(file.path(base, "R", "access_parser.R"))
source(file.path(base, "R", "target_parser.R"))
source(file.path(base, "R", "inventory.R"))
source_root <- value("--source", Sys.getenv("VPRO_PARITY_SOURCE", unset = ""))
target_root <- value("--target", Sys.getenv("VPRO_PARITY_TARGET", unset = getwd()))
output_root <- value("--output", file.path(base, "generated"))
if (!nzchar(source_root)) {
  stop("--source is required (or set VPRO_PARITY_SOURCE).")
}
summary <- parity_run_inventory(source_root, target_root, output_root)
cat(sprintf("Wrote deterministic inventory for %d source objects to %s\n", summary$source_objects, normalizePath(output_root, winslash = "/", mustWork = FALSE)))
