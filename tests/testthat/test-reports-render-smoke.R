library(testthat)
library(quarto)
library(DBI)
library(duckdb)

# ============================================================================
# Quarto Report Smoke Tests
# ============================================================================
# Goal: Ensure all Quarto reports in reports/*.qmd can render without error
# using standard demo data.
# ============================================================================

test_that("All Quarto reports render without error using demo data", {
  skip_on_cran()
  
  # Setup paths relative to tests/testthat
  # We use absolute paths to avoid ambiguity during rendering
  db_path <- normalizePath(file.path("..", "..", "data", "vpro.duckdb"), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
  report_dir <- normalizePath(file.path("..", "..", "reports"), winslash = "/", mustWork = TRUE)
  
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
  
  # Create a temporary directory for output to keep workspace clean
  render_out_dir <- file.path(tempdir(), "vpro_report_tests")
  if (!dir.exists(render_out_dir)) dir.create(render_out_dir, recursive = TRUE)
  on.exit(unlink(render_out_dir, recursive = TRUE), add = TRUE)
  
  for (qmd_path in qmd_files) {
    report_name <- basename(qmd_path)
    
    # Define output file path
    output_filename <- paste0(tools::file_path_sans_ext(report_name), ".html")
    
    # Try rendering
    results <- tryCatch({
      quarto::quarto_render(
        input = qmd_path,
        output_format = "html",
        output_file = output_filename,
        execute_params = params,
        quiet = TRUE
      )
      list(success = TRUE, error = NULL)
    }, error = function(e) {
      list(success = FALSE, error = e$message)
    })
    
    if (!results$success) {
      cat(sprintf("\n   FAIL: %s\n   Error: %s\n", report_name, results$error))
    } else {
      cat(sprintf("\n   PASS: %s\n", report_name))
    }
    
    expect_true(results$success, label = sprintf("Report %s render status", report_name))
    
    # Cleanup: Quarto creates .html and often a _files folder in the reports/ directory
    generated_html <- file.path(report_dir, output_filename)
    if (file.exists(generated_html)) unlink(generated_html)
    
    generated_files_dir <- file.path(report_dir, paste0(tools::file_path_sans_ext(report_name), "_files"))
    if (dir.exists(generated_files_dir)) unlink(generated_files_dir, recursive = TRUE)
  }
})
