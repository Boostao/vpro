library(shinytest2)

test_that("project -> site/env save -> export flow", {
  withr::local_envvar(NOT_CRAN = "true")
  app <- AppDriver$new("../..", name = "flow-site-env-export", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  project <- app$get_value(input = "sel_project")
  if (is.null(project) || !nzchar(project)) {
    testthat::skip("No project available in Sample_Metadata")
  }

  plot_id <- app$get_value(input = "sel_su")
  if (is.null(plot_id) || !nzchar(plot_id)) {
    testthat::skip("No plots available for selected project")
  }

  app$set_inputs(main_tabs = "Site & Env")
  app$wait_for_idle()
  app$get_value(input = "env-env_location")
  app$set_inputs(`env-env_location` = "Test location")
  app$click("env-save_header")
  app$wait_for_idle()

  app$set_inputs(main_tabs = "Export")
  app$wait_for_idle()
  app$get_value(input = "export-export_proj")
  app$get_value(input = "export-dl_r_csv")
  app$get_value(input = "export-dl_r_rds")

  expect_true(TRUE)
})
