library(shinytest2)

test_that("app loads and context inputs exist", {
  app <- AppDriver$new("../..", name = "smoke", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  app$get_value(input = "sel_project")
  app$get_value(input = "sel_su")
})

test_that("core tabs load without errors", {
  app <- AppDriver$new("../..", name = "smoke-core", height = 900, width = 1400)
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
  app$get_value(input = "env-env_date")

  app$set_inputs(main_tabs = "Vegetation")
  app$wait_for_idle()
  app$get_value(input = "veg-btn_add_spp")

  app$set_inputs(main_tabs = "Export")
  app$wait_for_idle()
  app$get_value(input = "export-export_proj")

  app$set_inputs(main_tabs = "Import")
  app$wait_for_idle()
  app$get_value(input = "import-import_file")
})
