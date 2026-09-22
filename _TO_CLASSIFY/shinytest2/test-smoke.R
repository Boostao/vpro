library(shinytest2)

new_app_driver <- function(name, height, width, ...) {
  app_obj <- shiny::shinyAppFile(normalizePath(file.path("..", "..", "app.R")))
  AppDriver$new(app = app_obj, name = name, height = height, width = width, ...)
}

select_plot <- function(app, project_id) {
  con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  scope <- tryCatch(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT DISTINCT s.siteunit, s.plotnumber",
        "FROM SU s",
        "INNER JOIN Env e ON e.plotnumber = s.plotnumber",
        "WHERE e.projectid = ?",
        "ORDER BY s.siteunit, s.plotnumber"
      ),
      list(project_id)
    ),
    error = function(e) data.frame(siteunit = character(0), plotnumber = character(0))
  )

  if (nrow(scope) == 0) {
    return(NULL)
  }

  app$click("btn_nav_su_tree")
  app$wait_for_idle()
  app$set_inputs(picker_site_unit = scope$siteunit[[1]])
  app$wait_for_idle()
  app$set_inputs(site_unit_plot_table_rows_selected = 1)
  app$wait_for_idle()

  app$get_value(input = "sel_su")
}

test_that("app loads and context inputs exist", {
  app <- new_app_driver(name = "smoke", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  app$get_value(input = "sel_project")
  app$get_value(input = "sel_su")
})

test_that("core tabs load without errors", {
  app <- new_app_driver(name = "smoke-core", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  project <- app$get_value(input = "sel_project")
  if (is.null(project) || !nzchar(project)) {
    testthat::skip("No project available in Sample_Metadata")
  }

  plot_id <- select_plot(app, project)
  if (is.null(plot_id) || !nzchar(plot_id)) {
    testthat::skip("No plots available for selected project")
  }

  app$set_inputs(main_tabs = "FS882-6x4XL")
  app$wait_for_idle()
  app$get_value(output = "fs882_6x4xl-fs882_context")

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
