test_that("standalone Quick Summary QMD renders the package data contract", {
  skip_if_not_installed("quarto")
  skip_if_not_installed("rmarkdown")
  if (!nzchar(Sys.which("quarto"))) skip("Quarto CLI unavailable")
  template <- system.file("reports", "quick_summary.qmd", package = "vpro")
  project_path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  expect_true(file.exists(template))
  root <- withr::local_tempdir()
  input <- file.path(root, "quick_summary.qmd")
  file.copy(template, input)
  before <- unname(tools::md5sum(project_path))
  tryCatch(
    quarto::quarto_render(
      input,
      execute_params = list(project_path = project_path, project = "Sample"),
      output_file = "quick_summary.html",
      quiet = TRUE
    ),
    error = function(e) {
      if (grepl("sqlite_scanner extension is not installed", conditionMessage(e), fixed = TRUE)) {
        skip("DuckDB sqlite_scanner unavailable for a separate Quarto R process")
      }
      stop(e)
    }
  )
  output <- file.path(root, "quick_summary.html")
  expect_true(file.exists(output))
  html <- paste(readLines(output, warn = FALSE), collapse = "\n")
  expect_match(html, "Project: Sample. Rows: 2026.", fixed = TRUE)
  expect_match(html, "AssignedSiteUnit", fixed = TRUE)
  expect_match(html, "BWBSmw 2 /05", fixed = TRUE)
  expect_identical(unname(tools::md5sum(project_path)), before)
})
