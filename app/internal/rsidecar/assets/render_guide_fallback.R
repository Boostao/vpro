#!/usr/bin/env Rscript
# Standalone HTML fallback renderer via knitr/rmarkdown when quarto CLI is absent on a workstation

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) {
  stop("Usage: render_guide_fallback.R <template.qmd> <payload.json> <output.html>", call. = FALSE)
}
qmd_path <- args[[1L]]
payload_path <- args[[2L]]
out_html <- args[[3L]]

# Strip all Quarto ```{=html} ... ``` raw HTML fences cleanly while preserving ```{r ...}``` chunks
strip_quarto_raw_html_fences <- function(src_lines) {
  out <- character(length(src_lines))
  in_raw_html <- FALSE
  raw_ticks <- ""
  in_code_chunk <- FALSE
  code_ticks <- ""

  for (i in seq_along(src_lines)) {
    ln <- src_lines[[i]]
    if (in_raw_html) {
      if (grepl(paste0("^\\s*", raw_ticks, "\\s*$"), ln)) {
        out[[i]] <- ""
        in_raw_html <- FALSE
        raw_ticks <- ""
      } else {
        out[[i]] <- ln
      }
    } else if (in_code_chunk) {
      out[[i]] <- ln
      if (grepl(paste0("^\\s*", code_ticks, "\\s*$"), ln)) {
        in_code_chunk <- FALSE
        code_ticks <- ""
      }
    } else if (grepl("^\\s*(`{3,})\\{=html\\}\\s*$", ln)) {
      raw_ticks <- sub("^\\s*(`{3,})\\{=html\\}\\s*$", "\\1", ln)
      in_raw_html <- TRUE
      out[[i]] <- ""
    } else if (grepl("^\\s*(`{3,})\\{[^}]+\\}\\s*$", ln) || grepl("^\\s*(`{3,})\\s*[A-Za-z0-9_-]*\\s*$", ln)) {
      code_ticks <- sub("^\\s*(`{3,}).*$", "\\1", ln)
      in_code_chunk <- TRUE
      out[[i]] <- ln
    } else {
      out[[i]] <- ln
    }
  }
  out
}

lines <- readLines(qmd_path, warn = FALSE, encoding = "UTF-8")
clean_lines <- strip_quarto_raw_html_fences(lines)
rmd_path <- sub("\\.qmd$", "_fallback.Rmd", qmd_path)
writeLines(clean_lines, rmd_path, useBytes = TRUE)

rmarkdown::render(
  input = rmd_path,
  output_format = rmarkdown::html_document(self_contained = TRUE, theme = NULL),
  output_file = basename(out_html),
  output_dir = dirname(out_html),
  params = list(payload_json = payload_path),
  quiet = TRUE,
  envir = new.env(parent = globalenv())
)
