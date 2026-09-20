library(testthat)
library(DBI)
library(duckdb)

# ============================================================================
# Quarto Report Smoke Tests
# ============================================================================
# Goal: Ensure all Quarto reports in reports/*.qmd can render without error
# using standard demo data.
# ============================================================================

test_that("All Quarto reports render without error using demo data", {
  # This repository isn't a CRAN package, but `skip_on_cran()` can be
  # overly aggressive in non-interactive / check-like environments.
  # Only skip when running under `R CMD check`.
  if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
    skip("Skipping Quarto render smoke during R CMD check")
  }
  if (!nzchar(Sys.which("quarto"))) {
    skip("Quarto CLI ('quarto') not available on PATH")
  }
  
  # Setup paths relative to tests/testthat
  # We use absolute paths to avoid ambiguity during rendering
  db_path <- normalizePath(file.path("..", "..", "data", "vpro.duckdb"), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
  report_dir <- normalizePath(file.path("..", "..", "reports"), winslash = "/", mustWork = TRUE)

  stale_smoke_dirs <- list.files(
    path = report_dir,
    pattern = "^vpro_report_tests_",
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(stale_smoke_dirs) > 0) {
    unlink(stale_smoke_dirs, recursive = TRUE, force = TRUE)
  }

  stale_smoke_outputs <- list.files(
    path = report_dir,
    pattern = "_smoke_test\\.html$",
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(stale_smoke_outputs) > 0) {
    unlink(stale_smoke_outputs, force = TRUE)
  }

  stale_smoke_assets <- list.files(
    path = report_dir,
    pattern = "_smoke_test_files$",
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(stale_smoke_assets) > 0) {
    unlink(stale_smoke_assets, recursive = TRUE, force = TRUE)
  }

  # Quarto may attempt to write cache assets under <execute-dir>/.quarto.
  # Ensure it exists to avoid NotFound errors in clean workspaces.
  dir.create(file.path(report_dir, ".quarto"), recursive = TRUE, showWarnings = FALSE)

  old_wd <- getwd()
  setwd(project_root)
  on.exit(setwd(old_wd), add = TRUE)
  
  # Standard test parameters matching common report requirements in mod_reporting.R
  # Using demo data found in vpro.duckdb (project 'hju', plot '00337')
  params <- list(
    plot_number = "00337",
    plot_numbers = "00337",
    site_unit = "00337",
    project_id = "hju",
    display_value = "presence_mean",
    constancy_format = FALSE,
    apply_lumping = FALSE,
    colour_greater = 5,
    gray_greater = 65,
    apply_theme = TRUE,
    report_title = "Smoke Test Report",
    db_path = db_path,
    project_root = project_root,
    parquet_dir = "" # Use DB by default if empty
  )
  
  # List all .qmd files in reports/
  qmd_files <- list.files(report_dir, pattern = "\\.qmd$", full.names = TRUE)
  
  # Verify we found the reports (expecting ~15+)
  expect_gt(length(qmd_files), 10, label = "Number of report templates found")
  
  # Create a temporary directory for output to keep workspace clean.
  # Note: Quarto CLI `--output-dir` is input/project-relative, so we create
  # a temp directory under reports/ and clean it up on exit.
  render_out_dir <- tempfile("vpro_report_tests_", tmpdir = report_dir)
  dir.create(render_out_dir, recursive = TRUE)
  on.exit(unlink(render_out_dir, recursive = TRUE), add = TRUE)

  # Avoid passing params via many `-P key:value` CLI args.
  # Quarto CLI can coerce values (e.g., leading-zero plot numbers -> numeric),
  # which breaks reports expecting character params. Instead, write a small
  # YAML file and pass it via `--execute-params`.
  param_to_yaml_scalar <- function(x) {
    if (is.null(x)) return("null")
    if (is.logical(x)) return(tolower(as.character(x)))
    if (is.numeric(x)) return(as.character(x))
    yaml_single_quote <- function(s) {
      s <- gsub("'", "''", as.character(s), fixed = TRUE)
      paste0("'", s, "'")
    }
    if (length(x) > 1) return(yaml_single_quote(paste(as.character(x), collapse = ",")))
    yaml_single_quote(x)
  }

  render_out_dir_arg <- basename(render_out_dir)
  
  for (qmd_path in qmd_files) {
    report_name <- basename(qmd_path)
    qmd_cli_path <- file.path("reports", report_name)
    
    # Define output file path
    output_filename <- paste0(tools::file_path_sans_ext(report_name), "_smoke_test.html")
    
    params_file <- tempfile("quarto_params_", fileext = ".yml")
    on.exit(unlink(params_file), add = TRUE)
    params_lines <- vapply(
      names(params),
      function(key) paste0(key, ": ", param_to_yaml_scalar(params[[key]])),
      character(1)
    )
    writeLines(params_lines, con = params_file, useBytes = TRUE)

    args <- c(
      "render",
      qmd_cli_path,
      "--to",
      "html",
      "--output-dir",
      file.path("reports", render_out_dir_arg),
      "--output",
      output_filename,
      "--execute-dir",
      "reports",
      "--execute-params",
      params_file
    )

    log_file <- tempfile("quarto_render_", fileext = ".log")
    on.exit(unlink(log_file), add = TRUE)

    exit_status <- tryCatch(
      as.integer(system2("quarto", args = args, stdout = log_file, stderr = log_file)),
      error = function(e) {
        attr(e, "error") <- conditionMessage(e)
        structure(1L, error = conditionMessage(e))
      }
    )

    output_lines <- character()
    if (file.exists(log_file)) {
      output_lines <- tryCatch(readLines(log_file, warn = FALSE), error = function(e) character())
    }

    excerpt <- ""
    if (length(output_lines) > 0) {
      n <- length(output_lines)
      start <- max(1L, n - 30L)
      excerpt <- paste(output_lines[start:n], collapse = "\n")
    }

    results <- if (exit_status == 0L) {
      list(success = TRUE, error = NULL)
    } else {
      err <- attr(exit_status, "error")
      msg <- paste0(
        "quarto CLI failed (exit ", exit_status, ")",
        if (!is.null(err) && nzchar(err)) paste0(": ", err) else "",
        if (nzchar(excerpt)) paste0("\n--- quarto output (tail) ---\n", excerpt) else ""
      )
      list(success = FALSE, error = msg)
    }
    
    if (!results$success) {
      cat(sprintf("\n   FAIL: %s\n   Error: %s\n", report_name, results$error))
    } else {
      cat(sprintf("\n   PASS: %s\n", report_name))
    }
    
    expect_true(results$success, label = sprintf("Report %s render status", report_name))

    # Cleanup within the temp output directory (output + any *_files assets)
    generated_html <- file.path(render_out_dir, output_filename)
    if (file.exists(generated_html)) unlink(generated_html)

    generated_files_dir <- file.path(render_out_dir, paste0(tools::file_path_sans_ext(report_name), "_files"))
    if (dir.exists(generated_files_dir)) unlink(generated_files_dir, recursive = TRUE)

    # Defensive cleanup: if Quarto falls back to writing beside the .qmd,
    # remove smoke-only artifacts from reports/ as well.
    stray_html <- file.path(report_dir, output_filename)
    if (file.exists(stray_html)) unlink(stray_html)

    stray_files_dir <- file.path(report_dir, paste0(tools::file_path_sans_ext(output_filename), "_files"))
    if (dir.exists(stray_files_dir)) unlink(stray_files_dir, recursive = TRUE)
  }
})
