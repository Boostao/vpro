test_that("report templates include theme params", {
  report_files <- c(
    "reports/short_veg.qmd",
    "reports/long_veg.qmd",
    "reports/short_veg_env.qmd",
    "reports/lifeform.qmd",
    "reports/short_veg_hierarchy.qmd",
    "reports/short_veg_order_hierarchy.qmd",
    "reports/veg_layer_a.qmd",
    "reports/veg_layer_c.qmd",
    "reports/veg_layer_d.qmd",
    "reports/bec_labels.qmd",
    "reports/env_summary.qmd",
    "reports/long_env.qmd",
    "reports/site_summary.qmd",
    "reports/quality_control.qmd",
    "reports/hierarchy.qmd",
    "reports/flat_hierarchy.qmd"
  )

  for (path in report_files) {
    full_path <- here::here(path)
    expect_true(file.exists(full_path), info = paste("Missing report file", path))
    lines <- readLines(full_path, warn = FALSE)
    expect_true(any(grepl("colour_greater", lines)), info = paste("Missing colour_greater in", path))
    expect_true(any(grepl("gray_greater", lines)), info = paste("Missing gray_greater in", path))
    expect_true(any(grepl("apply_theme", lines)), info = paste("Missing apply_theme in", path))
  }
})

test_that("report templates include report_title params", {
  report_files <- c(
    "reports/short_veg.qmd",
    "reports/long_veg.qmd",
    "reports/short_veg_env.qmd",
    "reports/lifeform.qmd",
    "reports/short_veg_hierarchy.qmd",
    "reports/short_veg_order_hierarchy.qmd",
    "reports/veg_layer_a.qmd",
    "reports/veg_layer_c.qmd",
    "reports/veg_layer_d.qmd",
    "reports/bec_labels.qmd",
    "reports/env_summary.qmd",
    "reports/long_env.qmd",
    "reports/site_summary.qmd",
    "reports/quality_control.qmd",
    "reports/hierarchy.qmd",
    "reports/flat_hierarchy.qmd",
    "reports/field_checklist.qmd"
  )

  for (path in report_files) {
    full_path <- here::here(path)
    expect_true(file.exists(full_path), info = paste("Missing report file", path))
    lines <- readLines(full_path, warn = FALSE)
    expect_true(any(grepl("report_title", lines)), info = paste("Missing report_title in", path))
  }
})
